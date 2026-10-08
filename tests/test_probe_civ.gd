# Task 6 civ probes — the §5.4 civ-parity criteria through the REAL stage:
# each probe boots the full Game + the real CivStage (out-of-tree, the M4
# test_probe_tribe boot shape) on a pinned seed and drives the sim through its
# documented input-SNAPSHOT contract (civ_sim.update), with observations
# pinned to the TS-verbatim formulas (each probe's provenance comment cites
# the frozen TS line; the probe IS the pin — divergence = documented here +
# in the report).
#
# Probes (task-6 brief AC + TS CivStage.ts):
#   slider transfer — full-board Q: mil +1, culture −1 (the stable-sort tie
#                     breaks culture-before-econ), donor = largest OTHER;
#                     the transfer path draws NOTHING from the stage stream
#                     (CivStage.ts:198-222)
#   regen lane pin  — a charm launch sets lastRaised → the 6 s regen refills
#                     THAT lane at the exact cadence over 4 cycles
#                     (CivStage.ts:186-195 + :340-343)
#   launch ladder   — cd → stat-2 → no-targets → hopeless-refuse, each toast
#                     verbatim, then the honest launch's power SNAPSHOT
#                     survives a mid-flight slider drop (TS:310-349, the
#                     :326-327 snapshot comment)
#   resolve net     — (power − rivalDef)·10 exact across the difficulty
#                     matrix (normal/chaos/peaceful, TS:351-355 + :368)
#   flip + hp floor — resolve influence ≥ 100 → owner flip, hp max(hp, 40)
#                     (TS:384-389)
#   burning pin     — the attack resolve's chance(0.5) at a seeded stream —
#                     instrumented rng draw + the stream-position literal;
#                     a burning city consumes NO draw (TS:378)
#   tickSecond      — the three rival personalities over 60 real seconds with
#                     the full draw chain replayed on a cloned stream: military
#                     shell aggression·0.4 + the 20 floor, culture −1.5 @ 0.03,
#                     economy pop +0.05 UNCAPPED + the buy −2 never on the
#                     rival's own city (TS:392-428)
#   hearts          — culture·0.006 + econ·0.004 − 0.02 per second exact:
#                     two phases isolate the two weights; the clamp → the
#                     tick-side flip with NO hp floor (TS:430-436 + :441-447)
#   karma drift     — (culture − mil)·0.0004 per second: the slope flips sign
#                     with the slider split, zero at the 5/5 tie
#                     (TS:438-439)
#   revolt          — the −99.8 gate sits ABOVE the +0.12 heal step: a city
#                     at −100 revolts (heals to −99.88, still ≤ −99.8), one
#                     a hair above the gate survives — the heal-first
#                     ordering discriminator (TS:448-454)
#   unrest heal     — +0.12 per second toward 0, the min(0, ·) cap exact
#                     (TS:400)
#   goldenAge       — hp 100, influence +15 clamped, pop +2 UNCAPPED per
#                     owned city (TS:478-483)
#   tradeWinds      — the +20% regen share compresses the 6 s cadence
#                     (observed fire ~1 s early vs the plain twin) + every
#                     city pop +0.008·dt (TS:517-525)
#   rivalSurge      — the ×1.3 chaos rates: military aggression·0.12·dt with
#                     the 20 floor, culture −1.5 @ 0.009·dt, economy pop
#                     min(30, +0.015·dt) — CAPPED, unlike the base tick
#                     (TS:494-515)
#
# Method notes: chaos is silenced per probe (gap 1e9 — the scheduler never
# reaches a fire, the M4 precedent) so the stage stream stays clean; probe
# fixture writes go straight at sim fields (the M3/M4 precedent, each
# commented at its site). Draw-dependent pins replay the TS draw chain on a
# CLONED stream (Rng.new_from(sim.rng.state()) — the test_civ_sim _probe
# shape): the derivation never calls the sim's own code. The one
# stream-position literal (the burning draw) is pinned beside its band with
# the re-instrument rule: any draw-history change must re-derive it.
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const RngLib := preload("res://src/core/rng.gd")

const DT := 1.0 / 60.0


# ---- scenario scaffold ---------------------------------------------------------

## Real boot: Game + the REAL civ stage, out-of-tree (run.gd drives tests
## synchronously inside _initialize — the main loop never reaches a frame, so
## tree-entered nodes never fire _ready; the stage's _ready is invoked ONCE
## manually, the M2/M3/M4 probe shape). switch_stage fires the real on_enter
## (restore_state reads the empty flags, toast_inset 150, the objective line).
func _boot(seed_v: int) -> Variant:
	var ctx: Variant = ContextScript.new(seed_v)
	# R14: the probes pin the TS-verbatim mechanics at the TS BASE output 10 —
	# the eco snapshot reads the 0.5 neutral when missing, which would lift
	# every full-board/karma pin by +6. Pin the collapsed snapshot (0.0) so
	# the accounting stays the frozen source's.
	ctx.flags["ecoHealth"] = 0.0
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(CivStageScript.new(game))
	game.stages["civ"]._ready()
	game.switch_stage("civ")
	return game


func _drop(game: Variant) -> void:
	# break the overlay Callable cycles before free (test_game_flow pattern)
	game.hud = {}
	game.editor = {}
	game.pause = {}
	game.free()


## Eventless world for clean accounting: the chaos scheduler's natural path
## never reaches a fire (gap 1e9), so the stage stream carries ONLY the draws
## the probe's own drive makes.
func _silence_chaos(sim: Variant) -> void:
	sim.chaos.gap = 1.0e9


## Fixture write (the M4 precedent — probe rigs go straight at sim fields):
## every rival becomes "military". Kills the culture-erosion and economy-buy
## draws so an influence identity is single-term (hearts-only on enemy
## cities, heal-only on yours). The personality pins live in the tickSecond
## probe, which keeps the REAL table and replays the full draw chain instead.
func _defuse_personalities(sim: Variant) -> void:
	for r in sim.rivals:
		r["personality"] = "military"


## Idle input snapshot — the sim's documented contract shape (civ reads
## keys_pressed only; the mouse fields ride along unused).
func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


## Scan the REAL hud's toast list for `fragment`, then clear the list: the
## out-of-tree hud's toast age never advances (hud.update is never driven),
## so the 1.5 s identical-repeat rate-limit would swallow every repeat
## forever, and the 6-deep list evicts — scan-per-step counts every fire
## exactly once (the M4 war-graves precedent).
func _scan_toasts(game: Variant, fragment: String) -> int:
	var n := 0
	for t in game.current.hud_inst._toasts:
		if String(t["text"]).find(fragment) >= 0:
			n += 1
	game.current.hud_inst._toasts.clear()
	return n


## The floatWorld read-back (the resolve's "+N influence" text) through the
## REAL hud floaters.
func _floater_count(game: Variant, text: String) -> int:
	var n := 0
	for f in game.current.hud_inst._floaters:
		if String(f["text"]) == text:
			n += 1
	return n


## Find a banner by title (cur OR queue — concurrent banners queue headless,
## the ttl never advancing): returns the banner dict or null.
func _find_banner(game: Variant, title: String) -> Variant:
	var hud: Variant = game.current.hud_inst
	if hud._cur_banner != null and String(hud._cur_banner["title"]) == title:
		return hud._cur_banner
	for b in hud._banner_queue:
		if String(b["title"]) == title:
			return b
	return null


## A probe Rng cloned from the sim's stream state — replaying the TS draw
## order on it derives expected outcomes without calling the sim (the
## independent derivations for the chance/pick pins, test_civ_sim's shape).
func _probe_rng(sim: Variant) -> Variant:
	return RngLib.new_from(sim.rng.state())


# ---- probes --------------------------------------------------------------------

## Pin provenance: the slider raise TS:198-222 verbatim — raise clamps +1;
## total > output donates 1 from the largest OTHER lane (stable desc sort:
## the culture/econ tie keeps canonical order → CULTURE donates, TS:203-210);
## A/S/D lower clamped and never touch lastRaised (:218-222). The transfer
## path consumes no rng (raise is pure arithmetic) — pinned against the live
## stream state. Seed 0xC171.
func test_slider_transfer_full_board_tie_seeded() -> void:
	var g: Variant = _boot(0xC171)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	# full board 4+3+3 = 10 (the constructor board): Q → mil 5, the tie donates
	# culture (canonical order before econ), econ untouched
	var state0: int = int(sim.rng.state())
	sim.update(DT, _inp({"keys_pressed": ["KeyQ"]}))
	eq(float(sim.mil), 5.0, "full-board Q: mil 4 +1 = 5 (TS:199)")
	eq(float(sim.culture), 2.0, "the culture/econ tie donates CULTURE (stable sort keeps canonical order, TS:203-210)")
	eq(float(sim.econ), 3.0, "econ untouched by the mil raise")
	eq(String(sim.lastRaised), "mil", "lastRaised tracks the raised lane (TS:217)")
	eq(_scan_toasts(g, "+1 mil ← culture"), 1, "the transfer toast verbatim (TS:210)")
	eq(int(sim.rng.state()), state0, "the transfer path draws NOTHING from the stage stream (raise is pure arithmetic)")
	# donor = the largest OTHER, not the tie default: 0/5/5 raise culture →
	# econ donates (5 > 0)
	sim.mil = 0.0
	sim.culture = 5.0
	sim.econ = 5.0
	sim.update(DT, _inp({"keys_pressed": ["KeyW"]}))
	eq(float(sim.culture), 6.0, "culture raised to 6 at the full board")
	eq(float(sim.econ), 4.0, "the largest other (econ 5) donates (TS:206-209)")
	eq(float(sim.mil), 0.0, "mil untouched")
	eq(_scan_toasts(g, "+1 culture ← econ"), 1, "the donor toast names the econ lane")
	eq(String(sim.lastRaised), "culture", "lastRaised follows KeyW (TS:219)")
	# raise UNDER output: free, no transfer, no toast
	sim.mil = 1.0
	sim.culture = 1.0
	sim.econ = 1.0
	sim.update(DT, _inp({"keys_pressed": ["KeyE"]}))
	eq(float(sim.econ), 2.0, "under-output raise is free (total 4 ≤ 10, TS:201)")
	eq(float(sim.mil), 1.0, "no donation under output")
	eq(_scan_toasts(g, "+1"), 0, "no transfer toast under output")
	eq(String(sim.lastRaised), "econ", "lastRaised follows KeyE (TS:221)")
	# a maxed lane at the full board: the clamp makes the raise a SILENT no-op
	# (10 stays 10, total 10 > 10 is false — no donation, no toast) — but the
	# PRESS still latches lastRaised (TS:219 sets it unconditionally)
	sim.mil = 0.0
	sim.culture = 10.0
	sim.econ = 0.0
	sim.update(DT, _inp({"keys_pressed": ["KeyW"]}))
	eq(float(sim.culture), 10.0, "the 0..10 clamp holds the maxed lane (TS:199)")
	eq(_scan_toasts(g, "+1"), 0, "clamped raise: total 10 > 10 is false — silent")
	eq(String(sim.lastRaised), "culture", "the clamped press still latched lastRaised (TS:219 runs after raise)")
	# A lowers without touching lastRaised (TS:218)
	sim.mil = 5.0
	sim.update(DT, _inp({"keys_pressed": ["KeyA"]}))
	eq(float(sim.mil), 4.0, "A lowers mil")
	eq(String(sim.lastRaised), "culture", "lowering never touches lastRaised (TS:218)")
	_drop(g)


## Pin provenance: the regen TS:186-195 verbatim — regenT += dt; at ≥ 6 reset
## to 0 and, only while total < output, refill the lastRaised LANE by 1; the
## charm launch set lastRaised = its lane (the pacifist-drain pin, TS:340-343)
## so the SPENT lane is the refilled lane. Seed 0xC172. The fire ticks are
## derived by replaying the same accumulation on the probe side (each cycle
## restarts from exactly 0.0, so every cycle fires on the same tick offset —
## the cadence is exact over the 4 observed cycles).
func test_regen_lane_pin_cadence_exact() -> void:
	var g: Variant = _boot(0xC172)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	# rig: mil 0 / culture 5 / econ 0 — the charm launch spends culture to 3,
	# total 3 < 10 keeps the regen live all window
	sim.mil = 0.0
	sim.culture = 5.0
	sim.econ = 0.0
	sim.update(DT, _inp({"keys_pressed": ["Digit2"]}))
	eq(sim.armadas.size(), 1, "the honest charm launch (power 9 > 6+2)")
	eq(float(sim.culture), 3.0, "2 output spent (TS:338)")
	eq(String(sim.lastRaised), "culture", "the SPEND lane latched into lastRaised (TS:340-343)")
	# the probe-side derivation: the same regenT accumulation replayed — the
	# launch frame already banked its dt (update order: regen before keys)
	var acc: float = DT
	var fire_ticks: Array = []
	var tick := 0
	for i in 4:
		while true:
			tick += 1
			acc += DT
			if acc >= 6.0:
				fire_ticks.append(tick)
				acc = 0.0
				break
	# the drive: watch the culture lane jump; the armada resolves mid-window
	# (draws only — the resolve cannot touch the lanes)
	var jumps: Array = []
	var prev: float = float(sim.culture)
	var tick2 := 0
	while jumps.size() < 4 and tick2 < 1800:
		tick2 += 1
		sim.update(DT, _inp())
		if float(sim.culture) != prev:
			jumps.append(tick2)
			prev = float(sim.culture)
	eq(jumps, fire_ticks,
			"the regen fired at the derived 6 s cadence ticks (TS:188 — every cycle restarts from 0.0, so the spacing is exact)")
	eq(float(sim.culture), 7.0, "4 refills landed in the spent lane: 3 → 7")
	eq(float(sim.mil), 0.0, "mil never refilled — regen rides lastRaised ONLY (TS:193)")
	eq(float(sim.econ), 0.0, "econ never refilled")
	eq(jumps.size(), 4, "≥ 3 cycles observed (4)")
	_drop(g)


## Pin provenance: the launch ladder TS:310-349 verbatim — cd > 0 returns
## SILENTLY (:311); stat < 2 toasts `{kind} needs 2 output in its lane (raise
## with Q/W/E)` (:314); no targets toasts t('No city left to persuade — build
## output!') (:319); power = stat + 4 is the SNAPSHOT (:326-327) and power ≤
## rivalDef + 2 refuses with the honest `needs {5−stat}+ more output` toast
## (:331-335); the honest launch spends 2, arms cd 5 and toasts
## `{KIND} armada → {name} (power {power})` (:336-348). The SNAPSHOT pin: a
## mid-flight slider drop must not nerf the resolve — net stays
## (snapshot − rivalDef)·10. Seed 0xC173. Sub-second window (no tickSecond).
func test_launch_gate_ladder_and_power_snapshot() -> void:
	var g: Variant = _boot(0xC173)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	# a SHORT route: the nearest city parked 60 px out (13 flight ticks — the
	# whole probe stays under 1 s, so tickSecond never fires and the influence
	# attribution is resolve-only)
	sim.cities[1]["x"] = 60.0
	sim.cities[1]["y"] = 120.0
	# (a) the cd gate: silent return, no toast, no armada (TS:311)
	sim.launchCds["attack"] = 5.0
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(_scan_toasts(g, "needs"), 0, "cd gate: SILENT (no stat toast — the order pin, TS:311)")
	eq(sim.armadas.size(), 0, "cd gate: no armada")
	# (b) the stat gate (TS:312-315)
	sim.launchCds["attack"] = 0.0
	sim.mil = 0.0
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(_scan_toasts(g, "attack needs 2 output in its lane (raise with Q/W/E)"), 1,
			"stat toast verbatim (TS:314)")
	eq(sim.armadas.size(), 0, "stat gate: no armada")
	# (c) stat precedes targets: no targets anywhere, stat still 0 → the stat
	# toast again (TS:312 before :317)
	sim.cities[1]["influence"] = 100.0
	sim.cities[2]["influence"] = 100.0
	sim.cities[3]["influence"] = 100.0
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(_scan_toasts(g, "attack needs 2 output in its lane (raise with Q/W/E)"), 1,
			"stat gate precedes the targets gate (TS:312/317 order)")
	# (d) the no-targets gate with stat OK (TS:317-320)
	sim.mil = 4.0
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(_scan_toasts(g, "No city left to persuade — build output!"), 1,
			"no-target toast verbatim (TS:319)")
	eq(sim.armadas.size(), 0, "no-target gate: no armada")
	# (e) the honest refuse: targets restored, stat 4 → power 8 ≤ rivalDef
	# 6 + 2 → the `needs 1+ more output` toast (TS:331-335)
	for i in [1, 2, 3]:
		sim.cities[i]["influence"] = -60.0
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(_scan_toasts(g, "attack needs 1+ more output in its lane (5+ total) — raise with Q/W/E, or lower a full slider"), 1,
			"hopeless-refuse toast verbatim (TS:333)")
	eq(sim.armadas.size(), 0, "refuse gate: no armada")
	# (f) the honest launch: stat 5 → power 9 > 8 (TS:327 + :332)
	sim.mil = 5.0
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(sim.armadas.size(), 1, "the honest launch")
	eq(float(sim.armadas[0]["power"]), 9.0, "power = stat + 4 SNAPSHOT (TS:327)")
	eq(float(sim.mil), 3.0, "2 spent (TS:337)")
	eq(float(sim.launchCds["attack"]), 5.0, "route cd 5 armed (TS:344)")
	eq(String(sim.lastRaised), "mil", "lastRaised = the spent lane (TS:343)")
	eq(_scan_toasts(g, "ATTACK armada → Khora (power 9)"), 1, "launch toast verbatim (TS:348)")
	# (g) the SNAPSHOT survives a mid-flight slider drop: mil 3 → 1 (the
	# recomputed power would be 5 — below the gate), the resolve must still
	# net (9 − 6)·10 = +30, NOT (5 − 6)·10 = −10 (TS:326-327 + :360-362)
	sim.update(DT, _inp())
	sim.update(DT, _inp())
	sim.update(DT, _inp({"keys_pressed": ["KeyA"]}))
	sim.update(DT, _inp({"keys_pressed": ["KeyA"]}))
	eq(float(sim.mil), 1.0, "the mid-flight drop landed (the would-be power is 5)")
	eq(float(sim.armadas[0]["power"]), 9.0, "the armada still carries the launch SNAPSHOT (TS:327)")
	var guard := 60
	while not sim.armadas.is_empty() and guard > 0:
		sim.update(DT, _inp())
		guard -= 1
	eq(sim.armadas.size(), 0, "the armada resolved inside the guard")
	eq(float(sim.cities[1]["influence"]), -30.0,
			"net = (snapshot 9 − rivalDef 6)·10 = +30 — the drop did NOT nerf the fleet (TS:368)")
	eq(_floater_count(g, "+3 influence"), 1, "the resolve read-back rounds net/10 (TS:372)")
	eq(float(sim.cities[1]["hp"]), 88.0, "attack hp −12 (TS:376)")
	_drop(g)


## One difficulty-matrix leg: boot at the pinned seed, park the nearest city
## inside the 14-unit arrive radius (the resolve fires ON the launch frame —
## no trail draws), set the difficulty, launch at stat_a then (route cd
## re-zeroed — a fixture write) at stat_b; returns [influence after a, after
## b]. The second target re-derivation: the same city stays nearest and its
## influence moves from wherever leg a left it.
func _net_leg(seed_v: int, difficulty: String, stat_a: float, stat_b: float) -> Array:
	var g: Variant = _boot(seed_v)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.ctx.difficulty = difficulty  # fixture write: rival_def_for reads it live (TS:353)
	sim.cities[1]["x"] = 5.0
	sim.cities[1]["y"] = 125.0
	sim.mil = stat_a
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	var inf_a: float = float(sim.cities[1]["influence"])
	sim.launchCds["attack"] = 0.0
	sim.mil = stat_b
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	var inf_b: float = float(sim.cities[1]["influence"])
	eq(float(sim.cities[1]["hp"]), 76.0, "two attack resolves: hp 100 − 24 (TS:376 ×2)")
	_drop(g)
	return [inf_a, inf_b]


## Pin provenance: the resolve net TS:357-369 verbatim — rivalDefFor(rival)
## = (rival ? 6 : 3) + (chaos ? +3 : peaceful ? −1 : 0) (TS:351-355), net =
## (power − rivalDef)·10 (:368), influence clamped ±100 (:369), power = the
## launch SNAPSHOT stat + 4 (:327). Seed 0xC174 — three boots, one per
## difficulty; each flies TWO honest launches at different stats so every
## leg's net pair is distinct (a cross-leg copy bug cannot hide).
func test_resolve_net_math_difficulty_matrix() -> void:
	# normal: def 6. stats 5, 6 → power 9, 10 → nets +30, +40.
	var leg: Array = _net_leg(0xC174, "normal", 5.0, 6.0)
	approx(float(leg[0]), -60.0 + (9.0 - 6.0) * 10.0,
			"normal: (9 − 6)·10 = +30 from −60 (TS:368)", 1e-9)
	approx(float(leg[1]), -30.0 + (10.0 - 6.0) * 10.0,
			"normal: (10 − 6)·10 = +40 composed on −30", 1e-9)
	# chaos: def 9. stats 8, 10 → power 12, 14 → nets +30, +50 (the gate
	# passed at 12 > 9+2 — the same ONE rivalDefFor the resolve reads)
	leg = _net_leg(0xC174, "chaos", 8.0, 10.0)
	approx(float(leg[0]), -60.0 + (12.0 - 9.0) * 10.0,
			"chaos: (12 − 9)·10 = +30 — the gate and resolve read the SAME def (TS:364-367)", 1e-9)
	approx(float(leg[1]), -30.0 + (14.0 - 9.0) * 10.0,
			"chaos: (14 − 9)·10 = +50 composed", 1e-9)
	# peaceful: def 5. stats 4, 9 → power 8, 13 → nets +30, +80 (the second
	# composes on leg a's −30: +50 — no clamp, no flip at < 100)
	leg = _net_leg(0xC174, "peaceful", 4.0, 9.0)
	approx(float(leg[0]), -60.0 + (8.0 - 5.0) * 10.0,
			"peaceful: (8 − 5)·10 = +30", 1e-9)
	approx(float(leg[1]), -30.0 + (13.0 - 5.0) * 10.0,
			"peaceful: (13 − 5)·10 = +80 composed on leg a's −30", 1e-9)


## Pin provenance: the resolve flip TS:384-389 verbatim — influence ≥ 100
## (after the net + clamp) && owner ≠ 'you' → owner 'you' AND hp =
## max(hp, 40): the floor LIFTS a broken city but never LOWERS a healthy one;
## the banner `{NAME} JOINS YOUR PLANETARY STATE` kind reward rides the REAL
## hud. Charm route (no hp damage, no burning draw — the twins stay
## stream-aligned). Seed 0xC175, two boots.
func test_flip_hp_floor_both_directions() -> void:
	# (a) hp 20 below the floor → lifted to 40
	var g: Variant = _boot(0xC175)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.culture = 5.0
	sim.cities[2]["x"] = 5.0
	sim.cities[2]["y"] = 125.0
	sim.cities[2]["influence"] = 80.0
	sim.cities[2]["hp"] = 20.0
	sim.update(DT, _inp({"keys_pressed": ["Digit2"]}))
	eq(sim.armadas.size(), 0, "resolved + filtered on the launch frame (d 7.07 < 14)")
	eq(String(sim.cities[2]["owner"]), "you", "80 + (9−6)·10 clamps to 100 → owner flip (TS:384-385)")
	eq(float(sim.cities[2]["influence"]), 100.0, "the clamp pinned the influence at 100 (TS:369)")
	eq(float(sim.cities[2]["hp"]), 40.0, "hp max(20, 40) = 40 — the floor LIFTED the broken city (TS:386)")
	var b: Variant = _find_banner(g, "VEX JOINS YOUR PLANETARY STATE")
	ok(b != null, "the flip banner rode the REAL hud (TS:387)")
	if b != null:
		eq(String(b["kind"]), "reward", "flip banner kind reward")
	approx(float(sim.ctx.karma), 0.015, "charm karma +0.015 (TS:382)", 1e-9)
	_drop(g)
	# (b) hp 55 above the floor → UNTOUCHED (max, not set)
	var g2: Variant = _boot(0xC175)
	var sim2: Variant = g2.current.sim
	_silence_chaos(sim2)
	sim2.culture = 5.0
	sim2.cities[2]["x"] = 5.0
	sim2.cities[2]["y"] = 125.0
	sim2.cities[2]["influence"] = 80.0
	sim2.cities[2]["hp"] = 55.0
	sim2.update(DT, _inp({"keys_pressed": ["Digit2"]}))
	eq(String(sim2.cities[2]["owner"]), "you", "twin: the flip fired at the same seed")
	eq(float(sim2.cities[2]["hp"]), 55.0, "hp max(55, 40) = 55 — the floor never LOWERS (TS:386)")
	_drop(g2)


## Pin provenance: the burning roll TS:375-378 verbatim — attack resolve:
## `if (c.burning <= 0 && this.rng.chance(0.5)) c.burning = 6`. Seed 0xC176,
## two boots. (a) the roll is the FIRST stream draw after construction (the
## target within 14 resolves on the launch frame before any trail draw) — the
## draw is instrumented on a cloned stream and its stream-position literal is
## pinned beside the 0.5 band (re-instrument on any draw-history change).
## (b) a city ALREADY burning short-circuits BEFORE the roll — the stream
## does not advance at all (the && order is observable in the rng state).
func test_burning_chance_seeded_stream() -> void:
	# (a) the instrumented draw
	var g: Variant = _boot(0xC176)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.cities[1]["x"] = 5.0
	sim.cities[1]["y"] = 125.0
	sim.mil = 5.0
	var p: Variant = _probe_rng(sim)
	var draw: float = p.next()  # TS:378 chance(0.5) — the first post-construction draw
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(sim.armadas.size(), 0, "resolved on the launch frame (no trail draws ahead of the roll)")
	if draw < 0.5:
		eq(float(sim.cities[1]["burning"]), 6.0, "draw < 0.5 → burning 6 (TS:378)")
	else:
		eq(float(sim.cities[1]["burning"]), 0.0, "draw ≥ 0.5 → no burning (TS:378)")
	eq(float(sim.cities[1]["hp"]), 88.0, "the attack hp −12 lands regardless of the roll (TS:376)")
	# the stream-position literal at 0xC176 (seed + the constructor's 6 city
	# jitters + the chaos branch + zero probe history): deterministic; a
	# native drift (base 0.5, an extra upstream draw) moves it off. A legit
	# draw-history change must re-instrument (the M4 literal rule).
	approx(draw, 0.36190336477011442,
			"burning-roll literal at 0xC176 — chance(0.5) at this stream position", 1e-6)
	_drop(g)
	# (b) burning > 0 → the && short-circuits BEFORE the roll: no draw
	var g2: Variant = _boot(0xC176)
	var sim2: Variant = g2.current.sim
	_silence_chaos(sim2)
	sim2.cities[1]["x"] = 5.0
	sim2.cities[1]["y"] = 125.0
	sim2.cities[1]["burning"] = 6.0
	sim2.mil = 5.0
	var state0: int = int(sim2.rng.state())
	sim2.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(int(sim2.rng.state()), state0, "a burning city consumes NO draw (the && order, TS:378)")
	eq(float(sim2.cities[1]["burning"]), 6.0, "burning stays 6 — not re-rolled (TS:378 gate)")
	eq(float(sim2.cities[1]["hp"]), 88.0, "the attack hp −12 still lands")
	_drop(g2)


## Pin provenance: tickSecond TS:392-457 verbatim, driven over 60 REAL
## seconds (update(1.0) — the floor-cross gate fires every update). The full
## draw chain is replayed on a cloned stream: per tickSecond d1 = the military
## shell chance(0.02) (cities[1]'s agenda, TS:408), d2 = the culture erosion
## chance(0.03) × owned cities (=1: the capital, TS:414), d3 = the economy
## buy chance(0.01) (TS:419) + d4 = rng.pick over [capital, c1, c2] (r3's own
## city EXCLUDED, TS:421). Composed identities: capital hp = production
## +0.5 (:397-398) then shell −aggression·0.4 (:407) with the 20 floor;
## capital influence = the erosion −1.5 per fired draw (no heal — inf ≥ 0);
## the economy city pop +0.05 UNCAPPED (:418 — the quirk: no min(30)); the
## economy city influence moves by hearts ONLY — the buy can never land on
## its own city (the pool filter, TS:421-422). Seed 0xC180 — picked (via a
## scratch replay scan over candidates) so all three personalities fire ≥ 1
## time in the window (shells 1, eros 4, buys 2).
func test_tick_second_personalities_over_real_seconds() -> void:
	var g: Variant = _boot(0xC180)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.cities[0]["hp"] = 50.0  # observable composition room; the 20 floor never bites
	sim.cities[3]["pop"] = 29.9  # the UNCAPPED quirk observable: +3 → 32.9 > 30
	# the probe-side derivation — the TS draw chain + effect order replayed
	var p: Variant = _probe_rng(sim)
	var exp_hp := 50.0
	var exp_inf := [100.0, -60.0, -60.0, -60.0]
	var exp_pop := [8.0, 6.0, 6.0, 29.9]
	var shells := 0
	var eros := 0
	var buys := 0
	for s in 60:
		var d_shell: float = p.next()  # TS:408 chance(0.02) — r1 military
		var d_eros: float = p.next()   # TS:414 chance(0.03) — r2 culture × 1 owned city
		var d_buy: float = p.next()    # TS:419 chance(0.01) — r3 economy
		var pick_i := -1
		if d_buy < 0.01:
			pick_i = floori(p.next() * 3.0)  # TS:421 pick([cap, c1, c2])
		# your city (the capital): production (TS:397-398)...
		exp_pop[0] = minf(30.0, float(exp_pop[0]) + 0.02)
		exp_hp = minf(100.0, exp_hp + 0.5)
		# ...then the military agenda shells it (TS:407)
		exp_hp = maxf(20.0, exp_hp - 0.8 * 0.4)
		if d_shell < 0.02:
			shells += 1
		# the culture agenda erodes each YOUR city (TS:414)
		if d_eros < 0.03:
			exp_inf[0] = maxf(-100.0, float(exp_inf[0]) - 1.5)
			eros += 1
		# the economy agenda grows ITS city UNCAPPED (TS:418) and maybe buys
		exp_pop[3] = float(exp_pop[3]) + 0.05
		if pick_i >= 0:
			exp_inf[pick_i] = float(exp_inf[pick_i]) - 2.0  # TS:422 — always −2 (not its own)
			buys += 1
		# the burning tail: nothing burns here (TS:427 skipped)
		# hearts (TS:433-434 + the R14 culture knob 0.006 → 0.014):
		# culture 3 / econ 3 → +0.034/s on enemy cities
		for k in [1, 2, 3]:
			exp_inf[k] = float(exp_inf[k]) + (3.0 * 0.014 + 3.0 * 0.004 - 0.02)
			exp_inf[k] = clampf(float(exp_inf[k]), -100.0, 100.0)
		# the flip/revolt block: unreachable at these values (TS:442-456)
	# the asserts — the sim must match the derivation everywhere
	ok(shells >= 1 and eros >= 1 and buys >= 1,
			"the pinned seed fires all three personalities (shells %d, eros %d, buys %d)" % [shells, eros, buys])
	# the drive — interleaved with the toast scans: the headless hud's 6-deep
	# list would evict and the frozen 1.5 s rate-limit would swallow repeats
	var toast_shells := 0
	for s in 60:
		sim.update(1.0, _inp())
		toast_shells += _scan_toasts(g, "shells your capital!")
	approx(float(sim.cities[0]["hp"]), exp_hp,
			"capital hp: 60 × (production +0.5, shell −0.32) composed (TS:398/407)", 1e-9)
	approx(float(sim.cities[0]["influence"]), float(exp_inf[0]),
			"capital influence: −1.5 per fired erosion draw, nothing else (TS:414)", 1e-9)
	approx(float(sim.cities[0]["pop"]), float(exp_pop[0]),
			"capital pop +0.02/s capped at 30 (TS:397)", 1e-9)
	approx(float(sim.cities[3]["pop"]), float(exp_pop[3]),
			"economy city pop +0.05/s UNCAPPED: 29.9 → 32.9 past 30 (TS:418 quirk)", 1e-9)
	eq(float(sim.cities[1]["pop"]), 6.0, "military rival pop untouched (no personality grows it)")
	eq(float(sim.cities[2]["pop"]), 6.0, "culture rival pop untouched")
	approx(float(sim.cities[3]["influence"]), float(exp_inf[3]),
			"economy city influence: hearts only — the buy NEVER lands on its own city (TS:421-422)", 1e-9)
	approx(float(sim.cities[1]["influence"]), float(exp_inf[1]),
			"r1 city influence: hearts + the buys that landed there", 1e-9)
	approx(float(sim.cities[2]["influence"]), float(exp_inf[2]),
			"r2 city influence: hearts + the buys that landed there", 1e-9)
	approx(float(sim.ctx.karma), 60.0 * (3.0 - 4.0) * 0.0004,
			"karma drifted once per tickSecond: 60 × (c−m)·0.0004 (TS:439)", 1e-9)
	# the shell toasts rode the REAL hud, one per fired draw (counted in the drive)
	eq(toast_shells, shells, "one '{name} shells your capital!' toast per fired 0.02 draw (TS:409)")
	_drop(g)


## Pin provenance: the hearts formula TS:430-436 with the ONE documented R14
## divergence — the culture weight rose 0.006 → 0.014 (the pacifist-viability
## knob; econ 0.004 and the −0.02 unrest baseline stay verbatim) — every
## ENEMY city: influence += culture·0.014 + econ·0.004 − 0.02, clamped ±100,
## per tickSecond. Seed 0xC178. The personalities are DEFUSED (all military —
## the fixture-write comment at the helper) so the enemy-city identity is
## hearts-pure; two 50-second phases isolate the two weights: phase A
## culture 10 → +0.12/s; phase B econ 10 → +0.02/s (a swapped/missing weight
## moves either phase off its pin). The clamp twin: a city at 99.99 clamps to
## 100 and flips on the SAME tick — the tick-side flip has NO hp floor
## (unlike the resolve's max(hp, 40), TS:441-447 vs :384-389).
func test_hearts_formula_over_real_seconds() -> void:
	var g: Variant = _boot(0xC178)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	_defuse_personalities(sim)
	sim.mil = 0.0
	sim.culture = 10.0
	sim.econ = 0.0  # total 10 — the regen stays dead, the lanes never move
	# R14 divergence: the culture weight rose 0.006 → 0.014 (the pacifist-
	# viability knob — the econ weight and the unrest baseline stay TS:433).
	# phase A: culture 10 → rate 0.014·10 + 0.004·0 − 0.02 = +0.12/s
	for i in 50:
		sim.update(1.0, _inp())
	approx(float(sim.cities[1]["influence"]), -60.0 + 50.0 * 0.12,
			"phase A: culture weight 0.014·10 → +0.12/s over 50 s (TS:433 + the R14 knob)", 1e-9)
	approx(float(sim.cities[3]["influence"]), -60.0 + 50.0 * 0.12,
			"phase A: every enemy city drifts at the same rate", 1e-9)
	# phase B: econ 10 → rate 0 + 0.004·10 − 0.02 = +0.02/s (the WEIGHTS are
	# distinguished: B is a sixth of A under the R14 culture weight)
	sim.culture = 0.0
	sim.econ = 10.0
	for i in 50:
		sim.update(1.0, _inp())
	approx(float(sim.cities[1]["influence"]), -54.0 + 50.0 * 0.02,
			"phase B: econ weight 0.004·10 → +0.02/s (TS:433 + the R14 knob)", 1e-9)
	eq(float(sim.cities[1]["pop"]), 6.0, "hearts moves influence only — the enemy pop is frozen")
	_drop(g)
	# the clamp → flip twin: the tick-side flip has NO hp floor
	var g2: Variant = _boot(0xC178)
	var sim2: Variant = g2.current.sim
	_silence_chaos(sim2)
	_defuse_personalities(sim2)
	sim2.mil = 0.0
	sim2.culture = 10.0
	sim2.econ = 0.0
	sim2.cities[1]["influence"] = 99.99
	sim2.cities[1]["hp"] = 33.0
	sim2.update(1.0, _inp())
	eq(float(sim2.cities[1]["influence"]), 100.0, "99.99 + 0.12 clamps at 100 (TS:434 + the R14 knob)")
	eq(String(sim2.cities[1]["owner"]), "you", "influence ≥ 100 → the tick-side flip (TS:443-444)")
	eq(float(sim2.cities[1]["hp"]), 33.0, "the TICK flip does NOT touch hp — no 40 floor here (TS:441-447 vs :386)")
	ok(_find_banner(g2, "KHORA JOINS YOUR PLANETARY STATE") != null,
			"the flip banner rode the REAL hud (TS:446)")
	_drop(g2)


## Pin provenance: the karma drift TS:438-439 verbatim — addKarma((culture −
## mil)·0.0004) once per tickSecond, the ONLY karma source in an idle window
## (no launches, no attack resolves). Seed 0xC179. Three phases on one boot:
## culture 10 → +0.004/s; mil 10 → −0.004/s (the slope flips sign with the
## split); the 5/5 tie → exactly 0 (the zero-drift pin).
func test_karma_drift_split_slopes() -> void:
	var g: Variant = _boot(0xC179)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	var karma0: float = float(sim.ctx.karma)
	# phase A: (10 − 0)·0.0004 = +0.004/s
	sim.mil = 0.0
	sim.culture = 10.0
	sim.econ = 0.0
	var exp: float = karma0
	for i in 30:
		sim.update(1.0, _inp())
		exp += (10.0 - 0.0) * 0.0004
	approx(float(sim.ctx.karma), exp, "phase A: culture-heavy drifts +0.004/s (TS:439)", 1e-9)
	# phase B: (0 − 10)·0.0004 = −0.004/s — back to the start
	sim.mil = 10.0
	sim.culture = 0.0
	for i in 30:
		sim.update(1.0, _inp())
		exp += (0.0 - 10.0) * 0.0004
	approx(float(sim.ctx.karma), exp, "phase B: military-heavy flips the slope — the drift returns to 0", 1e-9)
	approx(exp, karma0, "the two 30-second phases cancel exactly", 1e-9)
	# phase C: the 5/5 tie → (5 − 5)·0.0004 = 0 — frozen
	sim.mil = 5.0
	sim.culture = 5.0
	for i in 10:
		sim.update(1.0, _inp())
	approx(float(sim.ctx.karma), exp, "phase C: the tie drifts exactly 0 (TS:439)", 1e-9)
	_drop(g)


## Pin provenance: the revolt gate TS:448-454 verbatim — the unrest-heal step
## (+0.12, TS:400) runs EARLIER in the tickSecond than the ≤ −99.8 revolt
## gate, so the gate reads the HEALED value: a city at −100 heals to −99.88
## which still sits ≤ −99.8 → REVOLTS (owner back by city id, influence reset
## −100, the banner) — while a city a hair above the gate heals CLEAR of it
## and survives. The discriminator: gate-before-heal would revolt at −99.91
## (−99.91 ≤ −99.8) — heal-first does not (−99.79 > −99.8). The boundary
## case −99.92 sits within float noise of −99.8: the probe derives the healed
## value with the identical TS ops and asserts the sim agrees bit-for-bit.
## Seed 0xC17A, personalities defused (the helper's comment).
func test_revolt_gate_sits_above_the_heal() -> void:
	var g: Variant = _boot(0xC17A)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	_defuse_personalities(sim)
	# (a) −100: heals to −99.88 — STILL ≤ −99.8 → revolt to the former owner
	# BY CITY ID (cities[2].id == 'r2', TS:452)
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -100.0
	sim.update(1.0, _inp())
	eq(String(sim.cities[2]["owner"]), "r2", "a city at −100 REVOLTS — the healed −99.88 still sits at the gate (TS:448-452)")
	eq(float(sim.cities[2]["influence"]), -100.0, "the revolt resets influence −100 (TS:454)")
	ok(_find_banner(g, "Vex REVOLTS!") != null, "the revolt banner rode the REAL hud (TS:453)")
	# (b) the float-noise boundary: −99.92 + 0.12 lands within 1 ulp of −99.8 —
	# derive the outcome with the identical ops and require the sim to agree
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -99.92
	var healed: float = minf(0.0, -99.92 + 0.12)  # TS:400's exact expression
	var want_revolt: bool = healed <= -99.8       # TS:450's exact expression
	sim.update(1.0, _inp())
	eq(String(sim.cities[2]["owner"]), "r2" if want_revolt else "you",
			"the −99.92 boundary matches the derived healed-gate outcome (healed %.17f)" % healed)
	# (c) THE ORDERING DISCRIMINATOR: −99.91 heals to −99.79 — clearly above
	# the gate. A gate-before-heal port would revolt here (−99.91 ≤ −99.8).
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -99.91
	sim.update(1.0, _inp())
	eq(String(sim.cities[2]["owner"]), "you", "−99.91 heals to −99.79 — ABOVE the gate, no revolt (the heal-first ordering, TS:448-450)")
	approx(float(sim.cities[2]["influence"]), minf(0.0, -99.91 + 0.12),
			"the healed value pinned (TS:400)", 1e-9)
	# (d) the capital: id 'you' matches NO rival → the rivals[0] fallback
	# (TS:452 ??)
	sim.cities[0]["influence"] = -100.0
	sim.update(1.0, _inp())
	eq(String(sim.cities[0]["owner"]), "r1", "the capital revolts to rivals[0] (the ?? fallback, TS:452)")
	ok(_find_banner(g, "%sgrad REVOLTS!" % String(sim.ctx.player_name)) != null,
			"the capital revolt banner rode the REAL hud")
	# (e) at-scale: a city just above the gate climbs AWAY every second — it
	# can never cross back down
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -99.7
	for i in 10:
		sim.update(1.0, _inp())
	eq(String(sim.cities[2]["owner"]), "you", "the −99.7 city never revolts — the heal only lifts")
	approx(float(sim.cities[2]["influence"]), -99.7 + 10.0 * 0.12,
			"the climb composed over 10 s (TS:400)", 1e-9)
	_drop(g)


## Pin provenance: the unrest heal TS:400 verbatim — while influence < 0,
## influence = min(0, influence + 0.12) once per tickSecond: +0.12/s toward
## 0, and the min(0, ·) cap lands EXACTLY on 0 (never overshoots). Seed
## 0xC17B, personalities defused so the healed city's influence moves by the
## heal only. The owned-city production rides along (pop +0.02/s, TS:397).
func test_unrest_heal_toward_zero() -> void:
	var g: Variant = _boot(0xC17B)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	_defuse_personalities(sim)
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -50.0
	var exp := -50.0
	for i in 30:
		sim.update(1.0, _inp())
		exp = minf(0.0, exp + 0.12)
	approx(float(sim.cities[2]["influence"]), exp,
			"30 s of +0.12/s: −50 → −46.4 (TS:400)", 1e-9)
	approx(float(sim.cities[2]["pop"]), 6.0 + 30.0 * 0.02,
			"the owned-city production rode along (TS:397)", 1e-9)
	# the cap: a hair below 0 heals to EXACTLY 0, never +0.06
	sim.cities[2]["influence"] = -0.06
	sim.update(1.0, _inp())
	eq(float(sim.cities[2]["influence"]), 0.0, "min(0, −0.06 + 0.12) = 0 EXACTLY — the cap (TS:400)")
	# at 0 the gate (influence < 0) skips — the value is never written again
	sim.update(1.0, _inp())
	eq(float(sim.cities[2]["influence"]), 0.0, "the heal gate is influence < 0 — 0 stays (TS:400)")
	_drop(g)


## Pin provenance: goldenAge TS:478-483 verbatim — every owned city: hp = 100,
## influence = clamp(+15, −100, 100), pop += 2 UNCAPPED (the quirk: tickSecond
## caps pop at 30, goldenAge does not); the toast t('Golden age! Your cities
## flourish.') good ✨; enemy cities untouched. Seed 0xC17C, driven at the
## hook (the deck's apply entry — the wiring was the task-2/3 pin); no
## updates run, so the rigged state is the whole story.
func test_golden_age_effects_exact() -> void:
	var g: Variant = _boot(0xC17C)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.cities[0]["pop"] = 29.5
	sim.cities[0]["influence"] = 90.0
	sim.cities[0]["hp"] = 55.0
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -95.0
	sim.cities[2]["hp"] = 40.0
	sim.cities[2]["pop"] = 6.0
	sim.golden_age()
	eq(float(sim.cities[0]["hp"]), 100.0, "capital hp = 100 (TS:480)")
	eq(float(sim.cities[0]["influence"]), 100.0, "capital influence +15 clamped at 100 (90 + 15, TS:480)")
	approx(float(sim.cities[0]["pop"]), 31.5, "capital pop +2 UNCAPPED: 29.5 → 31.5 past 30 (TS:480 quirk)", 1e-9)
	eq(float(sim.cities[2]["hp"]), 100.0, "conquered city hp = 100")
	approx(float(sim.cities[2]["influence"]), -80.0, "conquered city +15 (no clamp hit)", 1e-9)
	approx(float(sim.cities[2]["pop"]), 8.0, "conquered city pop +2", 1e-9)
	eq(float(sim.cities[1]["hp"]), 100.0, "an enemy city untouched")
	eq(float(sim.cities[1]["influence"]), -60.0, "an enemy city untouched")
	eq(float(sim.cities[3]["pop"]), 6.0, "an enemy city untouched")
	eq(_scan_toasts(g, "Golden age! Your cities flourish."), 1, "the golden-age toast verbatim (TS:482)")
	_drop(g)


## Pin provenance: tradeWindsTick TS:523-525 verbatim — regenT += dt·0.2 (the
## +20% share feeds the NORMAL 6 s check, TS:524) and every city pop =
## min(30, +0.008·dt). Seed 0xC17D, DT drive (the 1 s update grain is too
## coarse to OBSERVE the 20% — the fire must land a full second early).
## Twin A runs plain; twin B takes trade_winds_tick(DT) after every update
## (the chaos-block phase: inside update the tick fires after that frame's
## regen check). The fire ticks are derived by replaying the same
## accumulation (twin B: += dt, check/fire, then += dt·0.2). Personalities
## defused (the helper's comment) so the pop identities are clean.
func test_trade_winds_regen_pace_and_pops() -> void:
	# the probe-side derivations
	var acc := 0.0
	var fire_a: Array = []
	var tick := 0
	while fire_a.size() < 2 and tick < 2000:
		tick += 1
		acc += DT
		if acc >= 6.0:
			fire_a.append(tick)
			acc = 0.0
	acc = 0.0
	var fire_b: Array = []
	tick = 0
	while fire_b.size() < 2 and tick < 2000:
		tick += 1
		acc += DT
		if acc >= 6.0:  # the update's regen check runs FIRST (TS:188)
			fire_b.append(tick)
			acc = 0.0
		acc += DT * 0.2  # then the trade-wind share (TS:524)
	# twin A: the plain 6 s cadence — a FIXED 750-tick drive (both fires land
	# inside; no loop-exit ambiguity for the state reads below)
	var g: Variant = _boot(0xC17D)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	_defuse_personalities(sim)
	sim.mil = 2.0
	sim.culture = 3.0
	sim.econ = 3.0  # total 8 < 10 — the regen lives, lastRaised 'mil' (TS:63)
	var jumps_a: Array = []
	var prev: float = float(sim.mil)
	for t2 in 750:
		sim.update(DT, _inp())
		if float(sim.mil) != prev:
			jumps_a.append(t2 + 1)
			prev = float(sim.mil)
	eq(jumps_a, fire_a, "twin A: the plain regen fired at the derived 6 s ticks")
	_drop(g)
	# twin B: the SAME seed with the trade-wind tick riding every frame
	var g2: Variant = _boot(0xC17D)
	var sim2: Variant = g2.current.sim
	_silence_chaos(sim2)
	_defuse_personalities(sim2)
	sim2.mil = 2.0
	sim2.culture = 3.0
	sim2.econ = 3.0
	var jumps_b: Array = []
	prev = float(sim2.mil)
	for t2 in 750:
		sim2.update(DT, _inp())
		if float(sim2.mil) != prev:
			jumps_b.append(t2 + 1)
			prev = float(sim2.mil)
		sim2.trade_winds_tick(DT)  # TS:524 — the chaos-tick phase (post-check)
	eq(jumps_b, fire_b, "twin B: the regen fired at the derived compressed ticks")
	ok(float(fire_b[0]) < float(fire_a[0]),
			"the +20% share compressed the cadence: fire at ~5 s vs the plain ~6 s (TS:517-518)")
	# the pops over the SAME 750 ticks: the tickSecond count is derived by
	# replaying the floor-cross accumulation (one crossing per second — the
	# 1/60 step cannot skip or double-cross); the tw pop rides EVERY tick
	var t := 0.0
	var secs := 0
	var exp_cap := 8.0
	var exp_en := 6.0
	for i in 750:
		t += DT
		if floorf(t) != floorf(t - DT):
			secs += 1
			exp_cap = minf(30.0, exp_cap + 0.02)  # TS:397 (your city)
		exp_cap = minf(30.0, exp_cap + 0.008 * DT)  # TS:525
		exp_en = minf(30.0, exp_en + 0.008 * DT)
	approx(float(sim2.cities[0]["pop"]), exp_cap,
			"capital pop: %d × production +0.02 + 750 × tw +0.008·dt (TS:397/525)" % secs, 1e-9)
	approx(float(sim2.cities[1]["pop"]), exp_en,
			"enemy city pop: the tw share only (TS:525 — every city on the planet)", 1e-9)
	_drop(g2)


## Pin provenance: the rival surge TS:494-515 verbatim — the chaos variant of
## tickSecond's rival branch ×1.3, driven at the tick hook (the deck's tick
## entry — the wiring was the task-2/3 pin): military shells the capital
## max(20, hp − aggression·0.12·dt) (TS:506); culture erodes each owned city
## max(−100, −1.5) @ chance(0.009·dt) (TS:509); economy grows min(30, pop +
## 0.015·dt) — CAPPED, unlike the base tick's uncapped +0.05 (TS:512 vs :418).
## Per tick only the culture branch draws (1 owned city). Seed 0xC17E —
## picked so the erosion fires ≥ 1 time in the window. The begin toast
## (TS:497) rides the REAL hud. The floor twin: a second boot pins the 20
## floor biting on the very first tick.
func test_rival_surge_rates_exact() -> void:
	var g: Variant = _boot(0xC17E)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.rival_surge_begin()
	eq(_scan_toasts(g, "A rival golden age! Their forges and fleets swell."), 1,
			"the surge begin toast verbatim (TS:497)")
	sim.cities[0]["hp"] = 40.0  # composition room above the 20 floor
	sim.cities[3]["pop"] = 29.9  # the cap engages within the window (min(30, ·), TS:512)
	# the probe-side derivation — 1 draw per tick (the culture branch)
	var p: Variant = _probe_rng(sim)
	var exp_hp := 40.0
	var exp_inf := 100.0
	var eros := 0
	for i in 100:
		var d: float = p.next()  # TS:509 chance(0.009·dt), dt 1.0
		exp_hp = maxf(20.0, exp_hp - 0.8 * 0.12 * 1.0)  # TS:506
		if d < 0.009:
			exp_inf = maxf(-100.0, exp_inf - 1.5)
			eros += 1
		sim.rival_surge_tick(1.0)
	ok(eros >= 1, "the pinned seed fires the culture surge (eros %d)" % eros)
	approx(float(sim.cities[0]["hp"]), exp_hp,
			"capital hp: 100 ticks of −aggression·0.12·dt (TS:506)", 1e-9)
	approx(float(sim.cities[0]["influence"]), exp_inf,
			"capital influence: −1.5 per fired 0.009 draw (TS:509)", 1e-9)
	eq(float(sim.cities[3]["pop"]), 30.0,
			"economy city pop CAPPED at 30 (min(30, +0.015·dt) — TS:512; the base tick's +0.05 is UNCAPPED, :418)")
	_drop(g)
	# the floor twin: the 20 floor bites on the FIRST tick
	var g2: Variant = _boot(0xC17E)
	var sim2: Variant = g2.current.sim
	_silence_chaos(sim2)
	sim2.cities[0]["hp"] = 20.05
	sim2.rival_surge_tick(1.0)
	eq(float(sim2.cities[0]["hp"]), 20.0, "the surge shell floor max(20, ·) bit on the first tick (TS:506)")
	_drop(g2)
