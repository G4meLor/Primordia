# Space play-bot headless pins — M6 task 7. The bot's PURE surface, verified
# without the xvfb scene gate (the scene needs the live SceneTree for the
# parse_input_event → flush dispatch — test_bot_civ.gd's header):
#   - the composition law: bot_space wraps bot_civ (whose tb is bot_tribe,
#     whose cb is bot_creature) and shares ONE driver — ONE LCG stream across
#     arrival → founding → tribe → civ → space, the M4/M5 composition shape;
#   - the seed pins the determinism gate rides: LCG 777 (bot_creature.gd:62)
#     and world 0xBEEF (bot_creature.gd:59);
#   - the SPACE fingerprint reads the STAGE-NAMED sim (game.stages['space']
#     .sim — the d7a5cb8 bot lesson: game.current.sim aliases whatever stage
#     is live; the decoy stage here carries creature-shaped fields that must
#     NOT leak into the fingerprint) with an exact key set and the floori(x·k)
#     quantization the ×2 gate compares;
#   - the bot's independent nearest-living-planet scan (the fly/station
#     target): strict-< minimum over the eco != null filter — first minimum
#     wins ties (the stable-scan pin, the bot_civ cross-check convention);
#   - the pure steering seams: the bang-bang station vector (brake against
#     the velocity when the predicted stop overshoots the r+90 ring, settle
#     inside r+110, else thrust toward the planet — accel 420,
#     space_sim.gd:344) and the hazard dodge (the sun's r+60 danger band,
#     the black holes' 600 pull);
#   - the per-600-frame sweep cadence the determinism triage rides (the
#     M2/M3/M4/M5 pattern) with the driver's assert_sane riding the same
#     beats;
#   - THE BOT LAW AUDIT (the brief's 1:1 table, enforced): the bot's direct
#     `sim.*(...)` call surface is EXACTLY the documented debug cheat
#     debug_seed_colonies (space_sim.gd's debug-seam surface: debug_state
#     read + debug_seed_colonies) — no interaction method (try_abduct/
#     seed_nearest/merge_cargo/scan_planet/...), no machine method
#     (spawn_pirates/persist_colonies/...), nothing else is ever called.
# RED-first: this file ran against the suite BEFORE tests/bots/bot_space.gd
# existed (the preload failed to compile → a visible red), then went green
# with the bot.
extends "res://tests/test_base.gd"

const BotSpaceScript := preload("res://tests/bots/bot_space.gd")
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")

const OUT_FP_KEYS := 26  # the scalar fingerprint keys before the 6×6 planet rows


# A stub game for the pure-function pins: Dictionary-shaped stages/context
# (dot access reads through) plus a scripted step_for_testing the sweep
# cadence drive can count on.
class StubEco:
	var rows: Array = []
	func living() -> Array:
		return rows


class StubGame:
	var steps := 0
	var sim: Variant = {}
	var context: Variant = {}
	var stages: Variant = {}
	var current: Variant = {}

	func step_for_testing(_n: int, dt: float) -> void:
		steps += 1
		sim["time"] = float(sim["time"]) + dt


func _stub_sim() -> Dictionary:
	var eco := StubEco.new()
	eco.rows = [{"pop": 4.5, "name": "stub species"}]
	var planets: Array = []
	for i in 6:
		planets.append({
			"angle": 1.25 + float(i), "scanned": i == 1,
			"colony": {"pop": 2.5, "generations": 3.5} if i < 2 else null,
			"eco": eco if i < 3 else null,
		})
	return {
		"time": 12.5, "sx": 8.25, "sy": -4.5, "svx": 1.5, "svy": -2.5,
		"shp": 80.0, "shpMax": 100.0, "shipAngle": -1.5, "ffHold": 0.5,
		"beamT": -0.25, "cargo": [{"genome": {}, "name": "spec"}],
		"abductCount": {"0:1": 1.0}, "resurveyCd": 1.5, "persistT": 2.5,
		"deckSeed": 48879, "pirates": [{"x": 1.0, "y": 2.0}],
		"blackHoles": [], "endingDone": true, "endingDismissed": true,
		"endingT": 3.5, "dismissT": 2.5, "planets": planets,
	}


func _stub_game() -> StubGame:
	# All quantizer inputs are exact binary fractions so the expected floors
	# are exact (12.34·100 would floor to 1233 — a float artifact, not a pin).
	var g := StubGame.new()
	g.sim = _stub_sim()
	g.stages = {"space": {"sim": g.sim, "hud_inst": null, "fx": null}}
	# the DECOY: a live stage whose sim carries creature-shaped fields — every
	# value here must stay OUT of the space fingerprint (the alias pin)
	g.current = {"id": "creature", "sim": {"px": 1.0, "py": 2.0, "ents": [1, 2, 3]}}
	g.context = {"karma": 0.5, "chaos": 0.25, "dna": 1079, "stage": "space",
			"world_stats": {"kills": 3, "extinctions": 2}}
	return g


func test_bot_composition_shares_one_lcg_stream() -> void:
	var b: Variant = BotSpaceScript.new()
	ok(b.bc != null, "bot_space wraps a bot_civ instance")
	ok(b.bc.tb != null, "the civ bot wraps a bot_tribe (the tribe legs)")
	ok(b.bc.tb.cb != null, "the tribe bot wraps a bot_creature (the arrival legs)")
	ok(b.driver != null, "bot_space exposes the shared driver")
	eq(b.driver, b.bc.driver, "the driver is ONE instance across civ+space legs")
	eq(b.driver, b.bc.tb.driver, "the driver is ONE instance across tribe+civ legs")
	eq(b.driver, b.bc.tb.cb.driver, "the driver is ONE instance across creature+tribe legs")
	eq(int(b.driver.lcg_seed), 777, "the LCG seed is the TS bot pin (777)")
	eq(int(BotCreatureScript.WORLD_SEED), 0xBEEF, "the world seed is the native 0xBEEF pin")
	eq(b.trace.size(), 0, "the space sweep trace starts empty")


func test_space_fingerprint_is_stage_named_and_exact() -> void:
	var b: Variant = BotSpaceScript.new()
	var g := _stub_game()
	var fp: Dictionary = b.space_fingerprint(g)
	# the stage-named read: every value comes from stages['space'].sim
	eq(int(fp["time"]), 1250, "time rides the space sim (quantized x100)")
	eq(int(fp["sx"]), 825, "sx rides the space sim")
	eq(int(fp["sy"]), -450, "sy quantized x100 (negatives floor toward -inf)")
	eq(int(fp["svx"]), 150, "svx rides the space sim")
	eq(int(fp["svy"]), -250, "svy quantized x100")
	eq(int(fp["shp"]), 8000, "shp quantized x100")
	eq(int(fp["shpMax"]), 10000, "shpMax quantized x100")
	eq(int(fp["shipAngle"]), floori(fmod(-1.5 + PI, TAU) * 1000.0),
			"shipAngle normalizes into [0, TAU) before the quantize")
	eq(int(fp["ffHold"]), 50, "ffHold quantized x100")
	eq(int(fp["beamT"]), 0, "the unclamped negative beamT reads 0 (the sim's no-clamp pin)")
	eq(int(fp["cargo"]), 1, "the cargo count rides the sim")
	eq(String(fp["cargoNames"]), "spec|", "the cargo names join with the | separator")
	eq(int(fp["abducts"]), 1, "the abductCount ledger size rides the sim")
	eq(int(fp["resurvey"]), 150, "resurveyCd quantized x100")
	eq(int(fp["persistT"]), 250, "persistT quantized x100")
	eq(int(fp["deckSeed"]), 48879, "deckSeed rides the sim (0xBEEF)")
	eq(int(fp["pirates"]), 1, "the pirate count rides the sim")
	eq(int(fp["holes"]), 0, "the black-hole count rides the sim")
	eq(bool(fp["endingDone"]), true, "endingDone rides the sim")
	eq(bool(fp["endingDismissed"]), true, "endingDismissed rides the sim")
	eq(int(fp["endingT"]), 350, "endingT quantized x100")
	eq(int(fp["dismissT"]), 250, "dismissT quantized x100")
	eq(int(fp["dna"]), 1079, "dna rides the context (the M5 cross-run anchor)")
	eq(int(fp["karma"]), 500, "karma rides the context (quantized x1000)")
	eq(int(fp["chaos"]), 250, "chaos rides the context (quantized x1000)")
	eq(int(fp["extinct"]), 2, "the extinctions counter rides the world stats")
	# per-planet rows (angle/scanned/colony/eco)
	eq(int(fp["p0_ang"]), floori(1.25 * 1000.0), "the planet angle quantizes x1000")
	eq(bool(fp["p1_scan"]), true, "the scanned flag rides the planet")
	eq(int(fp["p0_pop"]), 250, "the colony pop quantized x100")
	eq(int(fp["p1_gen"]), 350, "the colony generations quantized x100")
	eq(int(fp["p2_pop"]), -1, "a colony-less planet reads -1 (not a fake zero)")
	eq(int(fp["p0_live"]), 1, "the eco living count rides the planet")
	eq(int(fp["p0_epop"]), 450, "the eco living pop quantized x100")
	eq(int(fp["p3_live"]), -1, "an eco-less planet reads -1")
	# the ALIAS pin: the decoy live stage's creature fields must not leak
	ok(not fp.has("ents"), "no creature ents key (the fingerprint cannot alias game.current)")
	ok(not fp.has("px"), "no creature px key")
	ok(not fp.has("py"), "no creature py key")
	# the exact key set — a removed field fails the ×2 gate loudly here
	var keys := fp.keys()
	keys.sort()
	var want := ["abducts", "beamT", "cargo", "cargoNames", "chaos", "deckSeed",
		"dismissT", "dna", "endingDone", "endingDismissed", "endingT", "extinct",
		"ffHold", "holes", "karma", "persistT", "pirates", "resurvey",
		"shipAngle", "shp", "shpMax", "svx", "svy", "sx", "sy", "time"]
	for i in 6:
		for suf in ["ang", "epop", "gen", "live", "pop", "scan"]:
			want.append("p%d_%s" % [i, suf])
	want.sort()
	eq(str(keys), str(want), "the fingerprint key set is exact (%d scalars + 36 planet rows)" % OUT_FP_KEYS)


func test_nearest_living_scan_mirrors_the_station_target() -> void:
	var b: Variant = BotSpaceScript.new()
	# p0 nearest WITH eco (the scan's pick), p1 nearer but barren (the eco
	# filter excludes it), p2 farther with eco, p3 nearer still but barren.
	var planets := [
		{"x": 300.0, "y": 0.0, "eco": RefCounted.new()},
		{"x": 100.0, "y": 0.0, "eco": null},
		{"x": 500.0, "y": 0.0, "eco": RefCounted.new()},
		{"x": 50.0, "y": 0.0, "eco": null},
	]
	eq(b.nearest_living_index({"sx": 0.0, "sy": 0.0, "planets": planets}), 0,
			"the nearest LIVING planet wins (the barren rocks are excluded)")
	# the TIE pin: two equidistant living candidates — the FIRST minimum
	var tied := [
		{"x": 0.0, "y": 100.0, "eco": RefCounted.new()},
		{"x": 100.0, "y": 0.0, "eco": RefCounted.new()},
	]
	eq(b.nearest_living_index({"sx": 0.0, "sy": 0.0, "planets": tied}), 0,
			"a tie keeps the first minimum (the stable pin)")
	# ALL barren → -1 (the fly leg's no-target rung)
	var none := [{"x": 10.0, "y": 0.0, "eco": null}]
	eq(b.nearest_living_index({"sx": 0.0, "sy": 0.0, "planets": none}), -1,
			"no living planet scans to -1")


func test_station_and_hazard_vectors_are_pure_field_math() -> void:
	var b: Variant = BotSpaceScript.new()
	# the bang-bang station: a fast ship whose predicted stop (d + v²/840)
	# would overshoot the r+90 ring brakes AGAINST its velocity…
	var sim := {"sx": 0.0, "sy": 0.0, "svx": 0.0, "svy": 380.0}
	var p := {"x": 0.0, "y": 200.0, "r": 46.0}
	var want: Vector2 = b._station_desired(sim, p)
	approx(want.x, 0.0, "the brake vector keeps no lateral component")
	approx(want.y, -380.0, "the brake vector is the velocity's negation")
	# …a slow ship short of the ring thrusts toward the planet…
	sim["svy"] = 10.0
	p["y"] = 300.0
	want = b._station_desired(sim, p)
	approx(want.x, 0.0, "the approach vector keeps no lateral component")
	approx(want.y, 300.0, "the approach vector points at the planet")
	# …a ship already inside r+110 settles (brakes) wherever it drifts.
	sim["svy"] = 20.0
	p["y"] = 100.0
	want = b._station_desired(sim, p)
	approx(want.y, -20.0, "inside the ring the ship settles against its drift")
	# the hazard dodge: inside the sun's 280 ring the vector flips outward
	var sim2 := {"sx": 0.0, "sy": 100.0, "blackHoles": []}
	var dodged: Vector2 = b._hazard_desired(sim2, Vector2(0.0, -500.0))
	ok(dodged.y > 0.0, "the sun dodge overcomes a toward-sun bearing")
	# the black-hole dodge: within 500 the vector gains the away component
	var sim3 := {"sx": 0.0, "sy": 0.0,
			"blackHoles": [{"x": 100.0, "y": 0.0, "vx": 0.0, "vy": 0.0}]}
	var dodged2: Vector2 = b._hazard_desired(sim3, Vector2(100.0, 0.0))
	ok(dodged2.x < 0.0, "the hole dodge overcomes a toward-hole bearing")


func test_sweep_trace_cadence_is_600() -> void:
	var b: Variant = BotSpaceScript.new()
	var g := _stub_game()
	for i in 1201:
		b._sp_wait_step(g)
	var fs: Array = []
	for r in b.trace:
		fs.append(int(r["f"]))
	eq(fs, [600, 1200], "the sweep trace rows land exactly on 600-frame beats")
	eq(int(g.steps), 1201, "every wait step drove exactly one game step")
	eq(b.driver.sane_violations.size(), 0,
			"the assert_sane sweeps riding the beats stayed clean")
	# the row payload is the fingerprint (triage reads the same shape)
	var row: Dictionary = b.trace[0]
	ok(row.has("fp") and int(row["fp"]["sx"]) == 825,
			"the sweep rows carry the space fingerprint")


func test_bot_law_audit_the_sim_call_surface_is_the_debug_cheat() -> void:
	# The brief's audit table, enforced at the source level: the bot's direct
	# `sim.<method>(...)` call surface is EXACTLY the documented debug cheat
	# debug_seed_colonies (space_sim.gd's debug-seam surface). Every
	# interaction/machine method must ride REAL input or stay a field read.
	var src: String = (load("res://tests/bots/bot_space.gd") as GDScript).source_code
	ok(src.length() > 1000, "the bot source is readable for the audit scan")
	var rx := RegEx.create_from_string("sim\\.([a-z_][a-z0-9_]*)\\s*\\(")
	var calls := {}
	for m in rx.search_all(src):
		calls[m.get_string(1)] = true
	var got := calls.keys()
	got.sort()
	eq(str(got), str(["debug_seed_colonies"]),
			"the direct sim-call surface is exactly the documented debug cheat")
	# the forbidden faces (the sim's public methods minus the cheat): none may
	# appear as a direct call — each rides the REAL input pipeline instead
	for forbidden in ["update", "on_enter", "on_exit", "persist_state",
			"persist_colonies", "generate_system", "make_planet_eco",
			"has_active_chaos", "nearest_planet", "try_abduct", "finish_abduct",
			"seed_nearest", "merge_cargo", "borrowed_flesh_graft", "spawn_pirates",
			"nebula_flip", "pirate_lull_begin", "pirate_lull_end",
			"spawn_black_hole", "demand_tribute", "pay_tribute", "solar_flare",
			"repair_hull", "scan_planet", "update_chaos", "debug_state"]:
		ok(not calls.has(forbidden), "no direct sim.%s() call (the bot-law forbidden face)" % forbidden)
	# the documented cheat IS used (the finale's colony leg)
	ok(src.contains("debug_seed_colonies"), "the debug cheat is the finale's colony leg")
	# the engine-trail color literal matches the sim's _hsl format
	# (space_sim.gd:1336-1338: 'hsl(%d %d%% %d%% / %.2f)' at 200/1/0.7)
	eq(String(BotSpaceScript.TRAIL_COLOR), "hsl(200 100% 70% / 1.00)",
			"the trail latch reads the sim's engine-particle color")
