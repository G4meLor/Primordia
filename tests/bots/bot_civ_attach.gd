## R14 civ-attach bots — sim-level drivers for the two balance scenarios the
## redesign pins (spec R14 + the task-15 preflight rulings):
##
##   pacifist_run    the culture-only route: NO armadas (Digit1/2/3 never
##                   pressed — the launch count must stay 0), the player fills
##                   the passive hearts lanes (culture AND econ — the hearts
##                   regen culture×c + econ×0.004 − 0.02 rewards both) and
##                   waits for the enemy cities to flip on national output
##                   alone. Completes when victoryFired (all owned → space).
##   armada_eco0_run the eco-collapsed world (ecoHealth 0 → start output 10):
##                   the armada route must not brick. One HONEST launch first
##                   (real Q taps to mil, real Digit1 — the gate must PASS at
##                   low output and resolve net-positive), then the existing
##                   civ bot's documented victory-leg shape: debug_set_influence
##                   grants to 98 (one resolve's +net always crosses 100) and
##                   one honest launch per city completes unification.
##   tribe_fall_loop the tribe-fall rebirth: force the fall state, ride the
##                   honest 4 s fall timer (the DNA floor + blob erase + the
##                   go_to('creature') payload), re-found through the REAL
##                   on_enter, and prove the new village STANDS (no loop).
##
## SIM-LEVEL DEVIATION (documented): the 1200 s game-time bound makes the
## xvfb scene gate infeasible (72000 frames × 2 passes — the scene bots cap
## TIMEOUT_FRAMES 60000 for the WHOLE arc), so these drivers step
## sim.update(dt, inp) directly on the M2 input-SNAPSHOT surface (civ_sim.gd
## header: "update(dt, inp) takes the M2 input SNAPSHOT and reads
## keys_pressed ONLY") — the same field shape the scene bot's
## parse_input_event → flush pipeline produces, one frame per tick. Scenario
## seeding (the ecoHealth flag, the tribe-fall arrays) rides the same
## direct-field seam the sim-level tests already use (test_tribe_sim.gd's
## huts.clear()); every gameplay input rides keys_pressed and every victory
## rides the real flip/victory path.
extends RefCounted

const Ctx := preload("res://src/game/context.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")
const TribeSim := preload("res://src/game/tribe/tribe_sim.gd")

const DT := 1.0 / 60.0

## The flip threshold minus one honest resolve's minimum net — the grant that
## a single launch always converts (the existing bot_civ.gd victory-leg
## GRANT_NEAR, with the same reasoning: an economy-rival −2 buy proc between
## grant and resolve cannot starve the flip at power ≥ 12: 96 + 60 ≥ 100).
const GRANT_FLIP := 98.0


# ---- shared harness ---------------------------------------------------------

## The test_civ_sim harness shape: real context (explicit seed), the stage rng
## branch, recording hooks.
static func _mk_civ(world: Dictionary, eco_health: Variant, seed_v: int) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.difficulty = "normal"
	ctx.world = world.duplicate(true)
	if eco_health != null:
		ctx.flags["ecoHealth"] = eco_health
	var rec: Dictionary = {"toasts": [], "banners": [], "gotos": [], "floats": []}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append(text),
		"go_to": func(stage, data): rec["gotos"].append([stage, data]),
		"save_all": func(): rec["gotos"].append(["__save__", null]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CivSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


static func _inp(keys: Array = []) -> Dictionary:
	return {"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": keys}


## Tap one key for one tick (the keys_pressed one-shot — the M2 snapshot's
## per-frame press semantics).
static func _tap(sim_v: Variant, key: String) -> void:
	sim_v.update(DT, _inp([key]))


## Step until the predicate holds or the tick budget dies. Returns the ticks
## stepped (budget when unsatisfied).
static func _until(sim_v: Variant, pred: Callable, budget_ticks: int) -> int:
	for i in budget_ticks:
		sim_v.update(DT, _inp())
		if pred.call():
			return i + 1
	return budget_ticks


# ---- pacifist bot ------------------------------------------------------------

## The culture-only completion. Policy: drain mil (A ×4), fill culture (W ×7)
## and econ (E ×7) — 20 output points at start output ≥ 20 (the full-web
## ecoHealth 1.0 snapshot the real arc produces: seed_land_ecology plants the
## 6-line base roster; a leaner web would need the regen beats, the bound
## below still holds at output 16 with the buffed constant at culture 10 —
## the scenario pins the snapshot its arc measures) — then wait on the hearts
## lane. Returns {completed, time, launches, launches_after_fill, output,
## culture, econ, mil}.
static func pacifist_run(world: Dictionary, eco_health: float, seed_v: int,
		budget_s := 1500.0) -> Dictionary:
	var m := _mk_civ(world, eco_health, seed_v)
	var sim: Variant = m["sim"]
	sim.on_enter()
	for i in 4:
		_tap(sim, "KeyA")
	for i in 7:
		_tap(sim, "KeyW")
	for i in 7:
		_tap(sim, "KeyE")
	var t_launches := int(sim.launches)  # must stay 0 forever after
	var ticks := _until(sim, func(): return bool(sim.victoryFired), int(budget_s / DT))
	return {
		"completed": bool(sim.victoryFired),
		"time": float(sim.time),
		"launches": int(sim.launches),
		"launches_after_fill": int(sim.launches) - t_launches,
		"output": float(sim.output),
		"culture": float(sim.culture),
		"econ": float(sim.econ),
		"mil": float(sim.mil),
	}


# ---- eco-collapsed armada bot -------------------------------------------------

## The ecoHealth-0 unification. Policy: Q ×6 (mil 4 → 10 — the full-board
## transfers ride the raise path), ONE honest Digit1 (the gate proof: the
## refusal toast must NOT appear, the armada must fly), then per unowned city
## the documented debug_set_influence grant to GRANT_FLIP + one honest launch.
## Returns {completed, launches, output, gate_refused, honest_resolves}.
static func armada_eco0_run(world: Dictionary, eco_health := 0.0,
		seed_v: int = 0xC14, budget_s := 600.0) -> Dictionary:
	var m := _mk_civ(world, eco_health, seed_v)
	var sim: Variant = m["sim"]
	sim.on_enter()
	# mil to the practical cap: the launch gate needs power > rival_def + 2
	# (mil ≥ 5 at normal); mil 10 makes every resolve +80 (power 14)
	for i in 6:
		_tap(sim, "KeyQ")
	# the honest gate proof — one real launch, watched
	var refused := false
	for i in 12:
		_tap(sim, "Digit1")
		if _has_toast(m["rec"], "needs 2 output") or _has_toast(m["rec"], "more output"):
			refused = true
			break
		if int(sim.armadas.size()) > 0:
			break
	var honest_launches := int(sim.launches)
	# let the flight resolve (220 px/s over ~360-900 px + margin); the honest
	# resolve is proven by an influence JUMP on some unowned city (target-
	# agnostic — no re-implementation of the sim's nearest-scan)
	var before_infl := _influences(sim)
	_until(sim, func(): return int(sim.armadas.size()) == 0, int(30.0 / DT))
	var honest_resolves := 0
	for i in sim.cities.size():
		if float(sim.cities[i]["influence"]) - float(before_infl[i]) > 0.0:
			honest_resolves += 1
	# the victory leg (the existing bot's documented cheat): grant each city
	# to the flip threshold, one honest launch converts it
	var guard := 0
	while not bool(sim.victoryFired) and guard < 12:
		guard += 1
		var idx := _unowned_index(sim)
		if idx < 0:
			break
		sim.debug_set_influence(idx, GRANT_FLIP)
		if not _launch_and_wait(m, budget_s):
			break
	return {
		"completed": bool(sim.victoryFired),
		"launches": int(sim.launches),
		"honest_launches": honest_launches,
		"honest_resolves": honest_resolves,
		"gate_refused": refused,
		"output": float(sim.output),
		"space_card": m["rec"]["gotos"],
	}


static func _has_toast(rec: Dictionary, fragment: String) -> bool:
	for t in rec["toasts"]:
		if String(t[0]).find(fragment) >= 0:
			return true
	return false


static func _unowned_index(sim_v: Variant) -> int:
	for i in sim_v.cities.size():
		var c: Dictionary = sim_v.cities[i]
		if String(c["owner"]) != "you":
			return i
	return -1


static func _influences(sim_v: Variant) -> Array:
	var out: Array = []
	for c in sim_v.cities:
		out.append(float(c["influence"]))
	return out


## One Digit1 launch + the flight/cooldown wait. The launch spends 2 mil and
## arms the 5 s route cooldown; the regen beat refills lastRaised='mil' at
## +1/6 s — the wait keeps the next gate HONEST (a refusal at mil < 5 is the
## gate working, never a brick).
static func _launch_and_wait(m: Dictionary, _budget_s: float) -> bool:
	var sim: Variant = m["sim"]
	var before := int(sim.launches)
	_until(sim, func(): return float(sim.launchCds["attack"]) <= 0.0 \
			and float(sim.mil) >= 5.0, int(30.0 / DT))
	for i in 4:
		_tap(sim, "Digit1")
		if int(sim.launches) > before:
			break
		if _has_toast(m["rec"], "needs 2 output") or _has_toast(m["rec"], "more output"):
			return false
	if int(sim.launches) == before:
		return false
	_until(sim, func(): return int(sim.armadas.size()) == 0, int(30.0 / DT))
	return true


# ---- tribe-fall bot -----------------------------------------------------------

## The fall → creature → re-found loop, ridden on ONE TribeSim instance (the
## real re-entry path: the stage node persists, on_enter re-founds). The fall
## STATE is seeded directly (tribe/huts emptied — the sim-level test seam the
## existing fall test uses); everything after rides update()/on_enter. Returns
## {fall_fired, dna_after, dna_before, blob_erased, goto_payload, refound_ok,
## refound_stands_s, refound_tribe, refound_huts}.
static func tribe_fall_run(seed_v: int, dna_before: int, stand_s := 60.0) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.difficulty = "peaceful"
	ctx.dna = dna_before
	var rec: Dictionary = {"gotos": [], "saves": 0, "banners": []}
	var hooks: Dictionary = {
		"go_to": func(stage, data): rec["gotos"].append([stage, data]),
		"save_all": func(): rec["saves"] += 1,
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_toast": func(text, kind, icon): pass,
		"hud_toast_inset": func(px): pass,
		"hud_show_objective": func(text): pass,
		"audio_play": func(n, v, p): pass,
		"audio_set_mood": func(name_v): pass,
		"cam_shake": func(mag, dur): pass,
		"fx_spawn": func(opts): pass,
		"fx_burst": func(x, y, n, colors, opts): pass,
		"get_gap_bias": func(): return 1.0,
		"get_mood": func(): return "test",
		"get_warn_scale": func(): return 1.0,
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = TribeSim.new(ctx, rng, hooks)
	sim.on_enter()
	# seed the fall state: the village is gone (raids/the beast took everyone)
	sim.tribe.clear()
	sim.huts.clear()
	# the honest 4 s fall timer → latch → erase → save → go_to (tribe_sim :537)
	var fall_ticks := _until(sim, func(): return bool(sim.fallFired), int(10.0 / DT))
	var blob_erased: bool = not ctx.flags.has("tribeState")
	var dna_after := int(ctx.dna)
	var payload: Variant = null
	if rec["gotos"].size() > 0:
		payload = rec["gotos"][0]
	# re-found through the REAL on_enter (the stage re-entry; the dead blob is
	# gone so restore_state reads false → the fresh-start branch)
	sim.on_enter()
	# the refound village must STAND: step the full stand window and prove the
	# fall timer never re-armed (the old bug re-fell ~4 s after re-founding —
	# restoreState resurrecting the dead blob)
	var stood_ticks := int(stand_s / DT)
	for i in stood_ticks:
		sim.update(DT, _inp())
	var refound_ok: bool = float(sim.fallenT) == 0.0 and not bool(sim.fallFired) \
			and sim.huts.size() > 0 and sim.tribe.size() > 0
	return {
		"fall_ticks": fall_ticks,
		"fall_fired": bool(sim.fallFired) or fall_ticks < int(10.0 / DT),
		"dna_before": dna_before,
		"dna_after": dna_after,
		"blob_erased": blob_erased,
		"goto_payload": payload,
		"refound_ok": refound_ok,
		"refound_stood_s": float(stood_ticks) * DT,
		"refound_tribe": sim.tribe.size(),
		"refound_huts": sim.huts.size(),
	}
