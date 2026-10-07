## CIV STAGE sim core — the lean grand-strategy layer as a headless RefCounted:
## the planetary state (City/Rival/Armada shapes), the constructor (capital +
## 3 rivals + city jitter), the national output sliders (raise/transfer/regen),
## the armada machine (launch gates, flight, resolve, the power SNAPSHOT),
## rivalDefFor, tickSecond (production, rival personalities, hearts, karma,
## flips + revolt) and the 6 chaos hook methods. Port of Spore
## src/game/civ/CivStage.ts (frozen) :17-526, minus the render pass
## (:530-662 — scene layer, task 3).
##
## Architecture (M4 pattern, same as tribe_sim.gd): CivSim.new(ctx, rng_branch,
## hooks) —
##   ctx        the M1 GameContext; the sim calls ctx methods directly
##              (add_karma/add_chaos, difficulty/player_name/genome/world
##              reads — the tribe precedent; they are NOT hooks)
##   rng_branch the stage's dedicated Rng (the CALLER draws ctx.rng.branch(),
##              mirroring TS `this.rng = game.context.rng.branch()`)
##   hooks      Dictionary of Callables for every scene/audio effect; missing
##              key = silent no-op so tests record selectively. Keys used:
##              hud_toast(text, kind, icon), hud_banner(data),
##              hud_toast_inset(px), hud_show_objective(text),
##              hud_float_world(x, y, text, color, size), hud_set_abilities(list),
##              audio_play(name, vol, pan), audio_set_mood(name),
##              cam_shake(mag, dur), fx_spawn(opts), go_to(stage, data),
##              save_all(), get_gap_bias(), get_mood(), get_warn_scale(),
##              storyteller_note_chaos_event(playtime).
##              (Audio sites carry `# TS audio.play(...) — audio core: its own
##              task` per the standing deferral.)
## No Input singleton reads: update(dt, inp) takes the M2 input SNAPSHOT and
## reads keys_pressed ONLY — Q/A/W/S/E/D sliders, Digit1/2/3 launches.
## The chaos scheduler rides a SECOND branch of the stage rng (TS:109) holding
## the world-parameterized civ deck (civ_events.gd, task 2): the factory draws
## NOTHING from any stage stream — the weights are Callables folding the world
## genome's gold/calm gates in at build time — so the stream stays TS-aligned.
## i18n: the sim emits the raw keys through plain tr() — the M1 convention
## (context.gd): the VI dictionary is registered into the TranslationServer at
## Game boot, so the t()-wrapped TS strings resolve (and degrade to EN
## headless). The stage layer needs no second translation pass.
##
## TS quirks ported AS-IS (parity pins, each commented at its site):
##  - the armadas filter `a.alive || a.t < 0` (:250) — the t<0 arm never
##    keeps anything (t is advanced before the filter every frame)
##  - rebellion's exclusion is BY ID (`c.id !== 'you'`), not ownership (:471)
##  - the revolt threshold −99.8 sits ABOVE the unrest-heal step (+0.12 runs
##    earlier in the tick: −100 heals to −99.88) — a city at −100 must revolt
##    (:448-450)
##  - rivalDefFor is the ONE source of truth for the launch gate AND the
##    resolve (they drifted in TS: chaos launches passed the gate and resolved
##    net 0) (:351-355, :364-367)
##  - the launch power SNAPSHOT (:327) — slider edits mid-flight neither
##    strengthen nor nerf an already-launched fleet
##  - the tickSecond float floor-cross gate (:253)
##  - economy-rival pop growth is UNCAPPED in tickSecond (:418 — the surge
##    tick caps, the base tick does not)
##  - the economy buy's `rival.id === t.owner ? 0 : −2` is always −2 by
##    construction (the pool filtered its own cities out) (:422)
##  - goldenAge's pop +2 is uncapped (:480)
##  - your burning city decrements twice per tick (owner branch −1 + tail
##    −0.5) (:399 + :427)
##  - the slider donor-0 revert branch (:211-214) is UNREACHABLE (both others
##    0 ⟹ total = lane ≤ 10 ⟹ `total > output` false) — kept verbatim, dead
##
## Recorded divergences (parity-pin ledger):
##  - TS Array.sort is stable; GDScript's is not. The two sort sites port as
##    explicit stable selections: the launch target is a strict-< minimum scan
##    (first minimum wins ties — the stable sort's [0]), and the 2-element
##    donor sort swaps only when strictly out of order.
##  - Math.round ports via _round_js (floor(x + 0.5) — ties toward +infinity;
##    GDScript round() ties away from zero).
##  - `rng.pick` on an empty pool would throw in TS (:421 — only reachable if
##    a rival owned every city, impossible: revolts return cities to their
##    FORMER owner by id, so a rival can hold at most its own + the capital);
##    the port guards the null pick defensively.
##  - restore_state's non-finite guards: TS Number.isFinite("50") is false —
##    the port type-checks before float() (GDScript's float("50") WOULD parse).
##  - TS `b.victoryFired === true` ports as an `is bool` check (GDScript's
##    `1.0 == true` would be true).
## Documented debug seam surface (bot parity law's exception list, the civ
## analog of tribe's debug_grant): debug_state() (read),
## debug_set_influence(index, value) (the task-4/5 bot's victory-leg grant),
## debug_clear_chaos() (determinism legs).
class_name CivSim
extends RefCounted

const ChaosScript := preload("res://src/game/chaos.gd")
const CivEventsScript := preload("res://src/game/civ/civ_events.gd")

## TS hud.showObjective on onEnter (CivStage.ts:121). R2 ruling: NO chip —
## the sims track no natural cur/max state toward unification (the conquest
## meters live in-scene), so this objective stays a plain line; documented
## per the task brief rather than left implicit.
const OBJECTIVE_LINE := "UNIFY THE PLANET — slider keys Q/W/E · launch armadas with 1/2/3"


# ---- hooks ---------------------------------------------------------------------

var ctx: Variant = null           # TS game.context
var rng: Variant = null           # TS this.rng (the stage branch)
var _hooks: Dictionary = {}


## Missing hook key = silent no-op (Callable check) — tests record selectively.
func _fire(hook: String, args: Array) -> void:
	var c: Variant = _hooks.get(hook)
	if c is Callable:
		(c as Callable).callv(args)


# ---- state (TS field names verbatim) ---------------------------------------------

var time := 0.0                  # TS:50
var cities: Array = []           # TS City[] :17-26
var rivals: Array = []           # TS Rival[] :28-34
var armadas: Array = []          # TS Armada[] :36-44

# national output sliders (0..10 each, sum capped) (TS:56-60)
var mil := 4.0
var culture := 3.0
var econ := 3.0
var output := 10.0

var regenT := 0.0                # TS:62
var lastRaised := "mil"          # TS:63 — 'mil' | 'culture' | 'econ'
# TS ChaosScheduler<CivStage> (private `chaos` in TS; GDScript keeps one
# public field). Constructed in _init at the TS stream position on a SECOND
# rng.branch(); the civ deck arrives with civ_events.gd (task 2).
var chaos: Variant = null
## TS deckSeed (C1: decks rebuilt from a stale WorldGenome) — on_enter
## compares and rebuilds.
var deckSeed := -1
var victoryFired := false        # TS:73
var camX := 0.0                  # TS:74
var camY := 0.0                  # TS:74
# your ruler genome for flavor portrait (TS:77) — the context genome
# REFERENCE, not a clone
var rulerGenome: Variant = null

# TS:308 — {attack, charm, trade} (declared mid-file in TS)
var launchCds: Dictionary = {"attack": 0.0, "charm": 0.0, "trade": 0.0}


func _init(ctx_v: Variant, rng_branch: Variant, hooks: Dictionary = {}) -> void:
	ctx = ctx_v
	rng = rng_branch
	_hooks = hooks
	rulerGenome = ctx.genome  # TS:82

	var names: Array = ["Prime", "Khora", "Vex", "Ompa"]  # TS:84 — [0] unused
	var rival_defs: Array = [  # TS:85-89
		{"id": "r1", "name": "Khorate Dominion", "personality": "military", "aggression": 0.8, "color": "#ff7a5a"},
		{"id": "r2", "name": "Vexi Concord", "personality": "culture", "aggression": 0.35, "color": "#9a7aff"},
		{"id": "r3", "name": "Ompa Syndicate", "personality": "economy", "aggression": 0.25, "color": "#5ad0a8"},
	]

	# your capital + 3 rival cities on a continent (TS:91-107)
	cities.append({"id": "you", "name": "%sgrad" % String(ctx.player_name), "owner": "you",
		"x": 0.0, "y": 120.0, "hp": 100.0, "influence": 100.0, "pop": 8.0, "burning": 0.0})
	for i in 3:
		var r: Dictionary = rival_defs[i]  # TS rivalDefs[i]!
		rivals.append(r)
		# x then y — the draw order the constructor pin replays (TS:100-101)
		var cx: float = cos(float(i) / 3.0 * TAU) * 700.0 + rng.range(-120.0, 120.0)
		var cy: float = sin(float(i) / 3.0 * TAU) * 480.0 + rng.range(-90.0, 90.0) - 60.0
		cities.append({
			"id": r["id"],
			"name": names[i + 1] if i + 1 < names.size() else "City",  # TS ?? 'City' — unreachable for i < 3
			"owner": r["id"],
			"x": cx,
			"y": cy,
			"hp": 100.0,
			"influence": -60.0,
			"pop": 6.0,
			"burning": 0.0,
		})

	# TS:109 — the scheduler rides a SECOND branch of the stage rng, holding
	# the world-parameterized civ deck (the factory draw is stream-free)
	chaos = ChaosScript.new(rng.branch(), _make_deck())
	deckSeed = int(ctx.world["seed"])  # TS:110


## TS hasActiveChaos (:70-72) — the ACTIVE-phase set only; a warn-phase event
## does not count.
func has_active_chaos() -> bool:
	return chaos.active_events().size() > 0


# ---- stage lifecycle (TS:113-130) --------------------------------------------------

func on_enter() -> void:
	# C1: a CONTINUE/NEW LIFE landing on a different world rebuilds the deck
	if int(ctx.world["seed"]) != deckSeed:
		chaos = ChaosScript.new(rng.branch(), _make_deck())
		deckSeed = int(ctx.world["seed"])
	_fire("audio_set_mood", ["civ"])  # TS:119
	_fire("hud_toast_inset", [150.0])  # TS:120 — clear the ruler portrait
	_fire("hud_show_objective", [OBJECTIVE_LINE])  # TS:121
	restore_state()  # TS:122
	# brick hardening: a restored run that ALREADY unified must go to space
	# (victoryFired true + no targets = the old silent softlock, now
	# reachable once saves stop being stale) (TS:123-128)
	if victoryFired and _all_owned():
		_fire("go_to", ["space", {"title": "THE BLACK OCEAN",
			"sub": "a planet was never going to be enough"}])


func on_exit() -> void:
	persist_state()  # TS:130


## The deck factory seam (civEvents.ts:47) — the world-parameterized civ deck.
## Draws nothing from any stage rng (see the header note); the C1 rebuild in
## on_enter reuses it on a fresh branch.
func _make_deck() -> Array:
	return CivEventsScript.make_civ_chaos_events(ctx.world)


func _all_owned() -> bool:
	for c in cities:
		if String(c["owner"]) != "you":
			return false
	return true


# ---- persist / restore (TS:132-173) -------------------------------------------------

## Snapshot the planetary state — CONTINUE mid-civ used to reset sliders,
## conquests and rival influence (menu row said 'CIV · 15 min' but you got
## a fresh cold war) (TS:132-143).
func persist_state() -> void:
	var cities_list: Array = []
	for c in cities:
		cities_list.append({"id": c["id"], "owner": c["owner"], "influence": c["influence"],
			"hp": c["hp"], "pop": c["pop"]})
	var blob: Dictionary = {
		"cities": cities_list,
		"mil": mil, "culture": culture, "econ": econ,
		"victoryFired": victoryFired,
		"lastRaised": lastRaised,
	}
	ctx.flags["civState"] = JSON.stringify(blob)  # TS:142


func restore_state() -> bool:
	var raw: Variant = ctx.flags.get("civState")
	if not (raw is String) or (raw as String).is_empty():
		return false  # TS:148 — no blob
	# TS try/catch — a parse failure reads as "no blob" (TS:172)
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return false
	var b: Dictionary = parsed
	if not (b.get("cities") is Array) or (b["cities"] as Array).size() != cities.size():
		return false  # TS:154
	for i in cities.size():
		var saved: Variant = null
		for sc in b["cities"]:
			if sc is Dictionary and String(sc.get("id", "")) == String(cities[i]["id"]):
				saved = sc
				break
		if saved == null:
			return false  # TS:158
		var c: Dictionary = cities[i]
		# owner sanitize — only 'you' or a known rival id applies (TS:160)
		var owner_v := String(saved.get("owner", ""))
		if owner_v == "you" or _is_rival_id(owner_v):
			c["owner"] = owner_v
		# non-finite reads KEEP the current value (Number.isFinite gate, TS:161)
		if _fin(saved.get("influence")):
			c["influence"] = clampf(float(saved["influence"]), -100.0, 100.0)
		if _fin(saved.get("hp")):
			c["hp"] = clampf(float(saved["hp"]), 5.0, 100.0)
		if _fin(saved.get("pop")):
			c["pop"] = clampf(float(saved["pop"]), 1.0, 30.0)
	# TS Math.max/min COERCE through Number.isFinite first — a non-finite
	# saved lane keeps the current one (already in range) (TS:165-167)
	if _fin(b.get("mil")):
		mil = clampf(float(b["mil"]), 0.0, 10.0)
	if _fin(b.get("culture")):
		culture = clampf(float(b["culture"]), 0.0, 10.0)
	if _fin(b.get("econ")):
		econ = clampf(float(b["econ"]), 0.0, 10.0)
	# STRICT === true — a saved 1 restores false (TS:168)
	victoryFired = b.get("victoryFired") is bool and bool(b["victoryFired"])
	# the first post-CONTINUE regen drip used to always land in Military (TS:170)
	var lr: Variant = b.get("lastRaised")
	if lr == "mil" or lr == "culture" or lr == "econ":
		lastRaised = String(lr)
	return true  # TS:171


func _is_rival_id(id_v: String) -> bool:
	for r in rivals:
		if String(r["id"]) == id_v:
			return true
	return false


## TS Number.isFinite — a numeric JSON value only (a "50" STRING fails the
## same way TS does; GDScript's float() would parse it, so type-check first).
static func _fin(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


# ---- update (TS:177-306) ---------------------------------------------------------

func update(dt: float, inp: Dictionary) -> void:
	time += dt

	for k in launchCds:
		launchCds[k] = maxf(0.0, float(launchCds[k]) - dt)  # TS:182-184

	# national output regenerates over time (TS:186-195)
	regenT += dt
	if regenT >= 6.0:
		regenT = 0.0
		var total := mil + culture + econ
		if total < output:
			# regen refills the lane the player is actually using first
			_lane_set(lastRaised, _lane_get(lastRaised) + 1.0)

	# slider keys (TS:197-222)
	var pressed: Array = inp.get("keys_pressed", [])
	if pressed.has("KeyQ"):
		_raise_lane("mil")
		lastRaised = "mil"
	if pressed.has("KeyA"):
		mil = clampf(mil - 1.0, 0.0, 10.0)
	if pressed.has("KeyW"):
		_raise_lane("culture")
		lastRaised = "culture"
	if pressed.has("KeyS"):
		culture = clampf(culture - 1.0, 0.0, 10.0)
	if pressed.has("KeyE"):
		_raise_lane("econ")
		lastRaised = "econ"
	if pressed.has("KeyD"):
		econ = clampf(econ - 1.0, 0.0, 10.0)

	# launch armadas: 1 attack nearest enemy, 2 charm, 3 trade (TS:224-227)
	if pressed.has("Digit1"):
		launch("attack")
	if pressed.has("Digit2"):
		launch("charm")
	if pressed.has("Digit3"):
		launch("trade")

	# armadas fly (TS:229-249)
	for a in armadas:
		if not bool(a["alive"]):
			continue
		a["t"] = float(a["t"]) + dt
		var dx: float = float(a["tx"]) - float(a["x"])
		var dy: float = float(a["ty"]) - float(a["y"])
		var d: float = sqrt(dx * dx + dy * dy)
		var spd := 220.0
		if d < 14.0 or float(a["t"]) > 14.0:
			a["alive"] = false
			resolve_armada(a)
		else:
			a["x"] = float(a["x"]) + (dx / d) * spd * dt
			a["y"] = float(a["y"]) + (dy / d) * spd * dt
			if rng.chance(dt * 30.0):
				# RAW map coords — the fx pool draws in map space; the scene
				# layer projects (render task 3). resolveArmada's floatWorld
				# corrects by hand instead (TS:370-372).
				_fire("fx_spawn", [{"x": a["x"], "y": a["y"],
					"vx": rng.range(-8.0, 8.0), "vy": rng.range(-8.0, 8.0),
					"ttl": 0.5, "size": 2.0, "kind": "dot", "color": "#9fd8ff", "drag": 1}])
	# TS:250 — `a.alive || a.t < 0`: t is advanced before this line every
	# frame, so the t<0 arm never keeps anything (dead-armada removal);
	# ported verbatim
	armadas = armadas.filter(func(a): return bool(a["alive"]) or float(a["t"]) < 0.0)

	# economy tick (1x per second) — the float floor-cross gate (TS:253)
	if floorf(time) != floorf(time - dt):
		tick_second()

	# chaos (TS:258-277)
	update_chaos(dt)

	# camera drift toward action (TS:279-287)
	var focus: Variant = armadas.back() if not armadas.is_empty() else null
	if focus != null:
		camX += (float(focus["x"]) - camX) * minf(1.0, dt * 1.2)
		camY += (float(focus["y"]) - camY) * minf(1.0, dt * 1.2)
	else:
		camX += (0.0 - camX) * minf(1.0, dt * 0.5)
		camY += (0.0 - camY) * minf(1.0, dt * 0.5)

	# victory (fires once) (TS:289-296)
	if _all_owned() and not victoryFired:
		victoryFired = true
		_fire("save_all", [])  # flush the board — a quit here used to undo unification
		_fire("audio_play", ["ascend", 1.0, 0.0])  # TS audio.play('ascend', 1) — audio core: its own task
		_fire("go_to", ["space", {"title": "THE BLACK OCEAN",
			"sub": "a planet was never going to be enough"}])

	# TS:298-305 — the first three entries carry NO active key (TS undefined
	# semantics); the slider entries do
	_fire("hud_set_abilities", [[
		{"key": "1", "icon": "⚔️", "cd": float(launchCds["attack"]) / 5.0},
		{"key": "2", "icon": "🎭", "cd": float(launchCds["charm"]) / 5.0},
		{"key": "3", "icon": "💰", "cd": float(launchCds["trade"]) / 5.0},
		{"key": "Q/A", "icon": "🔫", "cd": 0.0, "active": mil > 0.0},
		{"key": "W/S", "icon": "🎭", "cd": 0.0, "active": culture > 0.0},
		{"key": "E/D", "icon": "💰", "cd": 0.0, "active": econ > 0.0},
	]])


# ---- sliders (TS:198-222) ----------------------------------------------------------

## Lane field access by name — the TS `this[lane]` writes, kept as explicit
## matches (the lanes stay discrete float vars, not a Dictionary).
func _lane_get(lane: String) -> float:
	match lane:
		"mil":
			return mil
		"culture":
			return culture
		"econ":
			return econ
	return 0.0


func _lane_set(lane: String, v: float) -> void:
	match lane:
		"mil":
			mil = v
		"culture":
			culture = v
		"econ":
			econ = v


## TS raise lambda (:198-216).
func _raise_lane(lane: String) -> void:
	_lane_set(lane, clampf(_lane_get(lane) + 1.0, 0.0, 10.0))
	var total := mil + culture + econ
	if total > output:
		# full board: transfer 1 point from the largest OTHER slider.
		# TS stable sort desc — 2 elements: swap only when strictly out of
		# order (the canonical lane order breaks the culture/econ tie toward
		# culture, exactly the TS stable sort's behavior)
		var others: Array = []
		for k in ["mil", "culture", "econ"]:
			if k != lane:
				others.append([k, _lane_get(k)])
		if others.size() == 2 and float(others[1][1]) > float(others[0][1]):
			var tmp: Array = others[0]
			others[0] = others[1]
			others[1] = tmp
		var donor: Array = others[0]
		if float(donor[1]) > 0.0:
			_lane_set(String(donor[0]), _lane_get(String(donor[0])) - 1.0)
			_fire("hud_toast", ["+1 %s ← %s" % [lane, donor[0]], "info", "⚖"])  # TS:210
		else:
			# nothing to transfer — UNREACHABLE (both others 0 ⟹ total = lane
			# ≤ 10 ⟹ total > output false); kept verbatim, dead (TS:211-214)
			_lane_set(lane, clampf(_lane_get(lane) - 1.0, 0.0, 10.0))
			_fire("hud_toast", [tr("Board full — lower another slider first"), "info", "⚖"])  # TS:213


# ---- armadas (TS:308-349) ------------------------------------------------------------

func launch(kind: String) -> void:
	if float(launchCds[kind]) > 0.0:
		return  # pacing: no armada-mash (TS:311)
	var stat: float = mil if kind == "attack" else (culture if kind == "charm" else econ)  # TS:312
	if stat < 2.0:
		# r4 i18n: the template rides tr() BEFORE the kind composes — a raw
		# compose would make the whole sentence an orphan lookup key (VI leak)
		_fire("hud_toast", [tr("%s needs 2 output in its lane (raise with Q/W/E)") % kind, "info", "⚖"])  # TS:314
		return
	var targets: Array = []
	for c in cities:
		if String(c["owner"]) != "you" and float(c["influence"]) < 100.0:
			targets.append(c)  # TS:317
	if targets.is_empty():
		_fire("hud_toast", [tr("No city left to persuade — build output!"), "info", "🏛"])  # TS:319
		return
	# nearest enemy city to your capital — the TS stable sort's [0] ports as a
	# strict-< minimum scan (first minimum wins ties) (TS:322-325)
	var cap: Dictionary = cities[0]
	var target: Dictionary = targets[0]
	var best_d: float = sqrt(pow(float(targets[0]["x"]) - float(cap["x"]), 2.0) \
			+ pow(float(targets[0]["y"]) - float(cap["y"]), 2.0))
	for i in range(1, targets.size()):
		var t: Dictionary = targets[i]
		var d: float = sqrt(pow(float(t["x"]) - float(cap["x"]), 2.0) + pow(float(t["y"]) - float(cap["y"]), 2.0))
		if d < best_d:
			best_d = d
			target = t
	# snapshot national power NOW (slider spend later must not weaken the fleet)
	var power := stat + 4.0  # TS:327 — the SNAPSHOT
	# hopeless launches refuse honestly — power <= rivalDef+2 resolves net
	# <= +20 and reads as a broken button (charm at output 2 measured a
	# NEGATIVE delta: it spent output to lose ground) (TS:328-335)
	var rival_def := rival_def_for(true)
	if power <= rival_def + 2.0:
		_fire("hud_toast", [tr("%s needs %s+ more output in its lane (5+ total) — raise with Q/W/E, or lower a full slider")
			% [kind, str(5.0 - stat)], "info", "⚖"])  # TS:333
		return
	# spend 2 from the matching slider + start the route cooldown (TS:336-339)
	if kind == "attack":
		mil = maxf(0.0, mil - 2.0)
	if kind == "charm":
		culture = maxf(0.0, culture - 2.0)
	if kind == "trade":
		econ = maxf(0.0, econ - 2.0)
	# regen must refill the lane the player is SPENDING — charm/trade
	# launches never raised lastRaised, so culture drained to 0 forever and
	# the pacifist route could not unify (126 refusals in 900s measured) (TS:340-343)
	lastRaised = "mil" if kind == "attack" else ("culture" if kind == "charm" else "econ")
	launchCds[kind] = 5.0  # pacing — a max armada no longer flips a city on its own (TS:344)

	armadas.append({"x": float(cap["x"]), "y": float(cap["y"]),
		"tx": float(target["x"]), "ty": float(target["y"]),
		"target": target, "kind": kind, "t": 0.0, "alive": true, "power": power})  # TS:346
	_fire("audio_play", ["warp", 0.5, 0.0])  # TS audio.play('warp', 0.5) — audio core: its own task
	var icon := "⚔️" if kind == "attack" else ("🎭" if kind == "charm" else "💰")
	_fire("hud_toast", ["%s %s %s (power %s)" % [kind.to_upper(), tr("armada →"), String(target["name"]), str(power)],
		"info", icon])  # TS:348


## Single source of truth for rival defense (launch gate + resolve) (TS:351-355).
func rival_def_for(rival: bool) -> float:
	var d := String(ctx.difficulty)
	return (6.0 if rival else 3.0) + (3.0 if d == "chaos" else (-1.0 if d == "peaceful" else 0.0))


func resolve_armada(a: Dictionary) -> void:
	var c: Dictionary = a["target"]
	if String(c["owner"]) == "you":
		return  # TS:359
	# use the power snapshotted at launch — slider edits mid-flight must not
	# strengthen or nerf an already-launched fleet (TS:360-362)
	var power := float(a["power"])
	var rival: Variant = null
	for r in rivals:
		if String(r["id"]) == String(c["owner"]):
			rival = r
			break
	# rivalDef scales with difficulty — ONE source of truth so the launch
	# gate and the resolve math always agree (they drifted: chaos launches
	# passed the gate and resolved net 0) (TS:364-367)
	var rival_def := rival_def_for(rival != null)
	var net := (power - rival_def) * 10.0  # TS:368
	c["influence"] = clampf(float(c["influence"]) + net, -100.0, 100.0)  # TS:369
	# cities draw through the civ camera (scale 0.62, pan*0.5) — raw map
	# coords floated detached from their city or culled off-screen (TS:370-372)
	_fire("hud_float_world", [float(c["x"]) * 0.62 - camX * 0.5,
		(float(c["y"]) - 30.0) * 0.62 - camY * 0.5 + 40.0,
		"%s%s influence" % ["+" if net >= 0.0 else "", str(_round_js(net / 10.0))],
		"#9fe89a" if net >= 0.0 else "#ff9a8a", 14.0])
	_fire("cam_shake", [3.0, 0.2])  # TS:373
	# RAW map coords — the fx pool draws in map space (scene task 3 projects) (TS:374)
	_fire("fx_spawn", [{"x": c["x"], "y": c["y"], "kind": "ring", "ttl": 0.7, "size": 30.0, "grow": 2.0,
		"color": "rgba(255,120,90,0.9)" if String(a["kind"]) == "attack" else "rgba(150,200,255,0.9)"}])
	if String(a["kind"]) == "attack":
		c["hp"] = clampf(float(c["hp"]) - 12.0, 5.0, 100.0)  # TS:376
		_fire("audio_play", ["boom", 0.5, 0.0])  # TS audio.play('boom', 0.5) — audio core: its own task
		if float(c["burning"]) <= 0.0 and rng.chance(0.5):
			c["burning"] = 6.0  # TS:378
		ctx.add_karma(-0.02)  # TS:379
	else:
		_fire("audio_play", ["charm", 0.6, 0.0])  # TS audio.play('charm', 0.6) — audio core: its own task
		ctx.add_karma(0.015 if String(a["kind"]) == "charm" else 0.01)  # TS:382
	if float(c["influence"]) >= 100.0 and String(c["owner"]) != "you":
		c["owner"] = "you"
		c["hp"] = maxf(float(c["hp"]), 40.0)  # TS:386
		# QC r6: the template goes through tr FIRST — the banner payload is
		# drawn with a plain tr_key of the composed string, which could never
		# resolve a key. EN output is byte-identical (tr passthrough).
		_fire("hud_banner", [{"title": tr("%s JOINS YOUR PLANETARY STATE") % String(c["name"]).to_upper(),
			"kind": "reward"}])  # TS:387
		_fire("audio_play", ["levelup", 1.0, 0.0])  # TS audio.play('levelup', 1) — audio core: its own task


# ---- tickSecond (TS:392-457) ---------------------------------------------------------

func tick_second() -> void:
	# your cities produce; rivals push their agenda (TS:394-428)
	for c in cities:
		if String(c["owner"]) == "you":
			c["pop"] = minf(30.0, float(c["pop"]) + 0.02)  # TS:397
			c["hp"] = minf(100.0, float(c["hp"]) + 0.5)  # TS:398
			if float(c["burning"]) > 0.0:
				c["burning"] = float(c["burning"]) - 1.0  # TS:399
			if float(c["influence"]) < 0.0:
				# unrest heals (rebellion hit -40 every ~60s) (TS:400)
				c["influence"] = minf(0.0, float(c["influence"]) + 0.12)
		else:
			var rival: Variant = null
			for r in rivals:
				if String(r["id"]) == String(c["owner"]):
					rival = r
					break
			if rival != null:
				# rivals push their agenda (TS:404)
				if String(rival["personality"]) == "military":
					var cap: Dictionary = cities[0]
					cap["hp"] = maxf(20.0, float(cap["hp"]) - float(rival["aggression"]) * 0.4)  # TS:407
					if rng.chance(0.02):
						_fire("hud_toast", [tr("%s shells your capital!") % String(rival["name"]), "bad", "💥"])  # TS:409
						_fire("cam_shake", [3.0, 0.3])  # TS:410
				elif String(rival["personality"]) == "culture":
					for cc in cities:
						if String(cc["owner"]) == "you" and rng.chance(0.03):
							cc["influence"] = maxf(-100.0, float(cc["influence"]) - 1.5)  # TS:414
				else:
					# economy rivals grow — UNCAPPED (the surge tick caps,
					# this does not — TS:418 quirk kept)
					c["pop"] = float(c["pop"]) + 0.05  # TS:418
					if rng.chance(0.01):
						# buy influence somewhere (TS:420-423)
						var pool: Array = []
						for x in cities:
							if String(x["owner"]) != String(rival["id"]):
								pool.append(x)
						var t: Variant = rng.pick(pool)
						if t != null:
							# `rival.id === t.owner ? 0 : −2` is always −2 by
							# construction (the pool filtered its own cities
							# out) — ported verbatim (TS:422)
							t["influence"] = float(t["influence"]) \
									+ (0.0 if String(rival["id"]) == String(t["owner"]) else -2.0)
		if float(c["burning"]) > 0.0:
			c["hp"] = maxf(5.0, float(c["hp"]) - 2.0)  # TS:427
			c["burning"] = float(c["burning"]) - 0.5  # TS:427

	# national output slowly wins hearts in enemy cities (per second) (TS:430-436)
	for c in cities:
		if String(c["owner"]) != "you":
			c["influence"] = float(c["influence"]) + (culture * 0.006 + econ * 0.004 - 0.02)
			c["influence"] = clampf(float(c["influence"]), -100.0, 100.0)

	# karma drift: culture-heavy → harmonious (TS:438-439)
	ctx.add_karma((culture - mil) * 0.0004)

	# rival cities fall to you when influence high; your cities drain if
	# influence negative (TS:441-456)
	for c in cities:
		if String(c["owner"]) != "you" and float(c["influence"]) >= 100.0:
			c["owner"] = "you"  # TS:444
			_fire("audio_play", ["levelup", 1.0, 0.0])  # TS audio.play('levelup', 1) — audio core: its own task
			_fire("hud_banner", [{"title": tr("%s JOINS YOUR PLANETARY STATE") % String(c["name"]).to_upper(),
				"kind": "reward"}])  # TS:446
		# threshold sits above the unrest-heal step (+0.12 runs earlier in
		# the tick: -100 heals to -99.88) — a city at -100 must revolt (TS:448-450)
		if String(c["owner"]) == "you" and float(c["influence"]) <= -99.8:
			# reconquered by rival — return to its former owner (TS:451-453)
			var former: Variant = null
			for r in rivals:
				if String(r["id"]) == String(c["id"]):
					former = r
					break
			if former == null and not rivals.is_empty():
				former = rivals[0]  # TS ?? this.rivals[0]
			if former != null:
				c["owner"] = String(former["id"])
				_fire("hud_banner", [{"title": tr("%s REVOLTS!") % String(c["name"]), "kind": "danger"}])  # TS:453
			c["influence"] = -100.0  # TS:454 — runs regardless of `former`


# ---- chaos hooks (TS:459-526) ---------------------------------------------------------

func earthquake() -> void:
	var c: Dictionary = rng.pick(cities)  # TS:462
	c["hp"] = maxf(10.0, float(c["hp"]) - 30.0)  # TS:463
	c["burning"] = 4.0  # TS:464
	_fire("cam_shake", [8.0, 1.0])  # TS:465
	_fire("audio_play", ["quake", 1.0, 0.0])  # TS audio.play('quake', 1) — audio core: its own task
	_fire("hud_toast", [tr("Earthquake damages %s!") % String(c["name"]), "bad", "🫨"])  # TS:467


func rebellion() -> void:
	# the exclusion is BY ID (`c.id !== 'you'`), not ownership — the capital
	# is filtered even though it is yours (TS:471 quirk)
	var yours: Array = []
	for c in cities:
		if String(c["owner"]) == "you" and String(c["id"]) != "you":
			yours.append(c)
	if yours.is_empty():
		return  # TS:472 — before any rng draw
	var c: Dictionary = rng.pick(yours)  # TS:473
	c["influence"] = maxf(-100.0, float(c["influence"]) - 40.0)  # TS:474
	_fire("hud_toast", [tr("Unrest in %s! (-40 influence)") % String(c["name"]), "bad", "🔥"])  # TS:475


func golden_age() -> void:
	for c in cities:
		if String(c["owner"]) == "you":
			c["hp"] = 100.0  # TS:480
			c["influence"] = clampf(float(c["influence"]) + 15.0, -100.0, 100.0)  # TS:480
			c["pop"] = float(c["pop"]) + 2.0  # TS:480 — UNCAPPED (tickSecond caps; this does not)
	_fire("hud_toast", [tr("Golden age! Your cities flourish."), "good", "✨"])  # TS:482


func rival_war() -> void:
	var rival: Dictionary = rng.pick(rivals)  # TS:486
	var cap: Dictionary = cities[0]
	cap["hp"] = maxf(15.0, float(cap["hp"]) - 25.0)  # TS:488
	# QC r6: the title template goes through tr FIRST; the subtitle stays a
	# raw EN key — the hud's draw-time tr_key resolves it (vi.csv ships it).
	_fire("hud_banner", [{"title": tr("%s DECLARES WAR") % String(rival["name"]).to_upper(),
		"subtitle": "your capital is shelled", "kind": "danger"}])  # TS:489
	_fire("audio_play", ["alarm", 1.0, 0.0])  # TS audio.play('alarm', 1) — audio core: its own task
	_fire("cam_shake", [6.0, 0.8])  # TS:491


## Chaos variant (golden_rival): the rivals' output runs 30% hotter while
## the event lasts. Rates below mirror tickSecond's rival branch ×1.3 (TS:494-515).
func rival_surge_begin() -> void:
	_fire("hud_toast", [tr("A rival golden age! Their forges and fleets swell."), "bad", "🏆"])  # TS:497


func rival_surge_tick(dt: float) -> void:
	for c in cities:
		var rival: Variant = null
		for r in rivals:
			if String(r["id"]) == String(c["owner"]):
				rival = r
				break
		if rival == null:
			continue
		if String(rival["personality"]) == "military":
			var cap: Dictionary = cities[0]
			cap["hp"] = maxf(20.0, float(cap["hp"]) - float(rival["aggression"]) * 0.12 * dt)  # TS:506
		elif String(rival["personality"]) == "culture":
			for cc in cities:
				if String(cc["owner"]) == "you" and rng.chance(0.009 * dt):
					cc["influence"] = maxf(-100.0, float(cc["influence"]) - 1.5)  # TS:509
		else:
			c["pop"] = minf(30.0, float(c["pop"]) + 0.015 * dt)  # TS:512


## Chaos variant (trade_winds): commerce blooms in the calm — your national
## output refills 20% faster and every city on the planet gains people (TS:517-525).
func trade_winds_begin() -> void:
	_fire("hud_toast", [tr("Trade winds! Every market on the planet hums."), "good", "⛵"])  # TS:520


func trade_winds_tick(dt: float) -> void:
	regenT += dt * 0.2  # the +20% share feeds the normal 6s regen check (TS:524)
	for c in cities:
		c["pop"] = minf(30.0, float(c["pop"]) + 0.008 * dt)  # TS:525


# ---- chaos wiring (TS:258-277) ---------------------------------------------------------

func update_chaos(dt: float) -> void:
	var gap_bias := 1.0
	var mood := "test"  # Storyteller.MOOD_TEST
	var warn_scale := 1.0
	var gb: Variant = _hooks.get("get_gap_bias")
	if gb is Callable:
		gap_bias = float(gb.call())
	var gm: Variant = _hooks.get("get_mood")
	if gm is Callable:
		mood = String(gm.call())
	var ws: Variant = _hooks.get("get_warn_scale")
	if ws is Callable:
		warn_scale = float(ws.call())
	var on_warn := func(def) -> void:
		# TS `if (def.warn)` (:265) — effective_warn keeps the static-key
		# semantics (the civ deck's warn_fn seam, the Ruling 13 shape, stays
		# uniform with the creature/tribe wiring)
		if ChaosScript.effective_warn(def):
			_fire("hud_banner", [{"title": ChaosScript.effective_warn(def), "kind": "danger", "ttl": 2.4}])  # TS:266
			_fire("audio_play", ["alarm", 0.5, 0.0])  # TS audio.play('alarm', 0.5) — audio core: its own task
	var on_apply := func(def) -> void:
		_fire("hud_banner", [{"title": def["name"], "kind": "chaos"}])  # TS:271
		ctx.add_chaos(0.03)  # TS:272
		# world_temperament pacing: warned events going live are the
		# high-severity marker (cradle grace / lean cycles / wildcard streak)
		_fire("storyteller_note_chaos_event", [float(ctx.playtime)])  # TS:275
	# TS passes exactly {chaos, karma, stageTime, gapMult, mood, warnScale} and
	# {onWarn, onApply} — no mirrors/dominance/onEnd in the civ wiring
	chaos.update(dt, self, {
		"chaos": float(ctx.chaos), "karma": float(ctx.karma), "stageTime": time,
		"gapMult": ctx.chaos_gap_mult() * gap_bias,
		"mood": mood,
		"warnScale": warn_scale,  # bio_tell bucket (TS:262)
	}, {
		"onWarn": on_warn,
		"onApply": on_apply,
	})


# ---- debug seams --------------------------------------------------------------------

## Debug/test access to internal sim state (mirrors tribe_sim.debug_state;
## the bot law's documented read surface).
func debug_state() -> Dictionary:
	return {"cities": cities, "rivals": rivals, "armadas": armadas,
		"mil": mil, "culture": culture, "econ": econ, "output": output,
		"regenT": regenT, "lastRaised": lastRaised, "launchCds": launchCds,
		"time": time, "victoryFired": victoryFired, "camX": camX, "camY": camY}


## Debug/test: the bot's victory-leg grant — sets a city's influence directly
## (SET semantics, absolute, like tribe_sim.debug_grant). debug_set_influence
## followed by a tick drives the real hearts→flip→victory path.
func debug_set_influence(index: int, value: float) -> void:
	cities[index]["influence"] = value


## Debug/test: determinism legs — a live chaos event would desync a seeded
## replay; clears actives, the cooldown ledger and the gap clock.
func debug_clear_chaos() -> void:
	chaos.clear()


# ---- internals -----------------------------------------------------------------------

## JS Math.round: ties toward +infinity (GDScript round() ties away from zero).
static func _round_js(x: float) -> int:
	return floori(x + 0.5)
