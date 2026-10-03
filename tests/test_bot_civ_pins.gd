# Civ play-bot headless pins — M5 task 5. The bot's PURE surface, verified
# without the xvfb scene gate (the scene needs the live SceneTree for the
# parse_input_event → flush dispatch — test_bot_tribe.gd's header):
#   - the composition law: bot_civ wraps bot_tribe (whose cb is bot_creature)
#     and shares ONE driver — ONE LCG stream across arrival → founding →
#     tribe → civ, the M4 composition shape (bot_tribe.gd:68-69, :99-102);
#   - the seed pins the determinism gate rides: LCG 777 (bot_creature.gd:62)
#     and world 0xBEEF (bot_creature.gd:59);
#   - the CIV fingerprint reads the STAGE-NAMED sim (game.stages['civ'].sim —
#     the d7a5cb8 bot lesson: game.current.sim aliases whatever stage is live;
#     the decoy stage here carries creature-shaped fields that must NOT leak
#     into the fingerprint) with an exact key set and the floori(x·k)
#     quantization the ×2 gate compares;
#   - the bot's independent nearest-unowned scan (the launch-target
#     cross-check): strict-< minimum over the sim's own target filter
#     (owner != 'you' AND influence < 100, civ_sim.gd:469-487) — first
#     minimum wins ties (the stable-sort pin, the sim header's ledger);
#   - the per-600-frame sweep cadence the determinism triage rides (the
#     M2/M3/M4 pattern) with the driver's assert_sane riding the same beats.
# RED-first: this file ran against the suite BEFORE tests/bots/bot_civ.gd
# existed (the preload failed to compile → a visible red), then went green
# with the bot.
extends "res://tests/test_base.gd"

const BotCivScript := preload("res://tests/bots/bot_civ.gd")
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")


# A stub game for the pure-function pins: Dictionary-shaped stages/context
# (dot access reads through) plus a scripted step_for_testing the sweep
# cadence drive can count on.
class StubGame:
	var steps := 0
	var sim: Variant = {}
	var context: Variant = {}
	var stages: Variant = {}
	var current: Variant = {}

	func step_for_testing(_n: int, dt: float) -> void:
		steps += 1
		sim["time"] = float(sim["time"]) + dt


func _stub_game() -> StubGame:
	# All quantizer inputs are exact binary fractions so the expected floors
	# are exact (12.34·100 would floor to 1233 — a float artifact, not a pin).
	var g := StubGame.new()
	g.sim = {
		"mil": 7.25, "culture": 2.5, "econ": 3.75, "output": 10.0,
		"lastRaised": "econ", "regenT": 1.5, "time": 12.5,
		"launchCds": {"attack": 2.5, "charm": 0.0, "trade": 0.0},
		"camX": -12.5, "camY": 40.25, "victoryFired": true,
		"armadas": [],
		"cities": [
			{"id": "you", "owner": "you", "influence": 100.0, "hp": 100.0,
				"pop": 8.0, "burning": 0.0},
			{"id": "r1", "owner": "r1", "influence": -60.0, "hp": 100.0,
				"pop": 6.5, "burning": 0.0},
			{"id": "r2", "owner": "r2", "influence": -30.0, "hp": 88.0,
				"pop": 6.0, "burning": 6.0},
			{"id": "r3", "owner": "you", "influence": 100.0, "hp": 40.0,
				"pop": 7.0, "burning": 0.0},
		],
	}
	g.stages = {"civ": {"sim": g.sim, "hud_inst": null}}
	# the DECOY: a live stage whose sim carries creature-shaped fields — every
	# value here must stay OUT of the civ fingerprint (the alias pin)
	g.current = {"id": "creature", "sim": {"px": 1.0, "py": 2.0, "ents": [1, 2, 3]}}
	g.context = {"karma": 0.5, "chaos": 0.25, "dna": 3.5, "stage": "civ"}
	return g


func test_bot_composition_shares_one_lcg_stream() -> void:
	var b: Variant = BotCivScript.new()
	ok(b.tb != null, "bot_civ wraps a bot_tribe instance")
	ok(b.tb.cb != null, "the tribe bot wraps a bot_creature (the arrival legs)")
	ok(b.driver != null, "bot_civ exposes the shared driver")
	eq(b.driver, b.tb.driver, "the driver is ONE instance across tribe+civ legs")
	eq(b.driver, b.tb.cb.driver, "the driver is ONE instance across creature+tribe legs")
	eq(int(b.driver.lcg_seed), 777, "the LCG seed is the TS bot pin (777)")
	eq(int(BotCreatureScript.WORLD_SEED), 0xBEEF, "the world seed is the native 0xBEEF pin")
	eq(b.trace.size(), 0, "the civ sweep trace starts empty")


func test_civ_fingerprint_is_stage_named_and_exact() -> void:
	var b: Variant = BotCivScript.new()
	var g := _stub_game()
	var fp: Dictionary = b.civ_fingerprint(g)
	# the stage-named read: every value comes from stages['civ'].sim
	eq(int(fp["mil"]), 725, "mil rides the civ sim (quantized x100)")
	eq(int(fp["culture"]), 250, "culture rides the civ sim")
	eq(int(fp["econ"]), 375, "econ rides the civ sim")
	eq(int(fp["output"]), 1000, "output rides the civ sim")
	eq(String(fp["lastRaised"]), "econ", "lastRaised rides the civ sim")
	eq(int(fp["regenT"]), 150, "regenT quantized x100")
	eq(int(fp["time"]), 1250, "time quantized x100")
	eq(int(fp["cdA"]), 250, "the attack cooldown quantized x100")
	eq(int(fp["camX"]), -1250, "camX quantized x100 (negatives floor toward -inf)")
	eq(int(fp["camY"]), 4025, "camY quantized x100")
	eq(int(fp["armadas"]), 0, "the armada count rides the civ sim")
	eq(bool(fp["victory"]), true, "victoryFired rides the civ sim")
	eq(int(fp["karma"]), 500, "karma rides the context (quantized x1000)")
	eq(int(fp["chaos"]), 250, "chaos rides the context (quantized x1000)")
	eq(int(fp["dna"]), 350, "dna rides the context (quantized x100)")
	# per-city rows (owner/influence/hp/pop/burning)
	eq(String(fp["c0_own"]), "you", "the capital owner rides the board")
	eq(int(fp["c1_inf"]), -6000, "rival influence quantized x100")
	eq(int(fp["c2_hp"]), 8800, "city hp quantized x100")
	eq(int(fp["c2_burn"]), 600, "city burning quantized x100")
	eq(int(fp["c3_pop"]), 700, "city pop quantized x100")
	eq(String(fp["c3_own"]), "you", "a flipped rival reads owner you")
	# the ALIAS pin: the decoy live stage's creature fields must not leak
	ok(not fp.has("ents"), "no creature ents key (the fingerprint cannot alias game.current)")
	ok(not fp.has("px"), "no creature px key")
	ok(not fp.has("py"), "no creature py key")
	# the exact key set — a removed field fails the ×2 gate loudly here
	var keys := fp.keys()
	keys.sort()
	var want := ["armadas", "c0_burn", "c0_hp", "c0_inf", "c0_own", "c0_pop",
		"c1_burn", "c1_hp", "c1_inf", "c1_own", "c1_pop", "c2_burn", "c2_hp",
		"c2_inf", "c2_own", "c2_pop", "c3_burn", "c3_hp", "c3_inf", "c3_own",
		"c3_pop", "camX", "camY", "cdA", "chaos", "culture", "dna", "econ",
		"karma", "lastRaised", "mil", "output", "regenT", "time", "victory"]
	eq(str(keys), str(want), "the fingerprint key set is exact")


func test_nearest_unowned_scan_mirrors_the_launch_filter() -> void:
	var b: Variant = BotCivScript.new()
	# cities[0] the capital (0,120); the rivals ring it. c1 nearest (the
	# scan's pick), c2 EXCLUDED by influence >= 100 (the launch gate's
	# no-target filter), c3 farther, c4 owned (the owner filter).
	var sim := {"cities": [
		{"id": "you", "owner": "you", "x": 0.0, "y": 120.0, "influence": 100.0},
		{"id": "r2", "owner": "r2", "x": -300.0, "y": 300.0, "influence": -60.0},
		{"id": "r1", "owner": "r1", "x": 50.0, "y": 170.0, "influence": 100.0},
		{"id": "r3", "owner": "r3", "x": 700.0, "y": -60.0, "influence": -60.0},
	]}
	eq(b.nearest_unowned_index(sim), 1, "the nearest un-owned under-100 city wins")
	# the TIE pin: two equidistant candidates — the FIRST minimum (the
	# stable-sort shape the sim's strict-< scan ports, civ_sim.gd:485)
	var tied := {"cities": [
		{"id": "you", "owner": "you", "x": 0.0, "y": 0.0, "influence": 100.0},
		{"id": "rB", "owner": "rB", "x": 0.0, "y": 100.0, "influence": -60.0},
		{"id": "rA", "owner": "rA", "x": 100.0, "y": 0.0, "influence": -60.0},
	]}
	eq(b.nearest_unowned_index(tied), 1, "a tie keeps the first minimum (the stable pin)")
	# ALL excluded → -1 (the no-targets rung's shape; the bot never launches)
	var none := {"cities": [
		{"id": "you", "owner": "you", "x": 0.0, "y": 0.0, "influence": 100.0},
		{"id": "rA", "owner": "you", "x": 10.0, "y": 0.0, "influence": -60.0},
	]}
	eq(b.nearest_unowned_index(none), -1, "no eligible target scans to -1")


func test_sweep_trace_cadence_is_600() -> void:
	var b: Variant = BotCivScript.new()
	var g := _stub_game()
	for i in 1201:
		b._civ_wait_step(g)
	var fs: Array = []
	for r in b.trace:
		fs.append(int(r["f"]))
	eq(fs, [600, 1200], "the sweep trace rows land exactly on 600-frame beats")
	eq(int(g.steps), 1201, "every wait step drove exactly one game step")
	eq(b.driver.sane_violations.size(), 0,
			"the assert_sane sweeps riding the beats stayed clean")
	# the row payload is the fingerprint (triage reads the same shape)
	var row: Dictionary = b.trace[0]
	ok(row.has("fp") and int(row["fp"]["mil"]) == 725,
			"the sweep rows carry the civ fingerprint")
