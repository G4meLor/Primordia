# Space sim-tick perf probe — HEADLESS (the §5.4 space budget row; the M5
# civ pattern, PARITY-M5.md §11 — contention-immune, the ASSERTED budget
# lives here). Builds the SpaceSim DIRECTLY (no scene, no game layer, no
# painter — pure sim.update on the constructor board), and times 300 ticks
# in TWO modes — the wrap tasking's both rows (PARITY-M6 §14):
#   NORMAL  — the plain flight world: empty keys_held (ffHold stays 0).
#   FF-HOLD — keys_held ["KeyF"] every frame: the ff block ticks EVERY live
#             planet eco at dt·26 in ONE update (TS:306-325 — the plan's
#             named row; the first held frame ticks dt·1 via the TS:306
#             pre-read, measured as-coded). This is the heavy mode: eco.tick
#             ×26 dt per live planet per frame.
# TWO FRESH same-seed sims (one per mode) — each phase builds its own world,
# so neither window inherits the other's pirate drift; same seed + same
# stocking = the same world (the ab_state_dump pattern).
#
# Stocking (documented probe seams, the civ-probe shape):
#   - 6 planets: the CONSTRUCTOR board verbatim — the KINDS ring
#     ["lush","ocean","volcanic","barren","lush","barren"] gives FOUR live
#     ecosystems (TS:128 builds an eco on every non-barren). The plan's perf
#     row estimates "3 with live ecosystems"; the real ring is HEAVIER (4) —
#     the assert is conservative.
#   - 3 colonies: debug_seed_colonies() (the bot-law's documented cheat) on
#     the first three non-barren planets — the colony logistic growth
#     (TS:370-372) and the ff block's generations leg (TS:323) carry real
#     work in both modes. Pops grow ~1 → ~1.4 (normal) / ~11 (ff) over a
#     300-tick window — never ≥ 20, so no finale churn (the trigger needs 3
#     thriving; the civ probe's "no event churn" principle).
#   - 5 LIVE pirates (the TS cap, spawnPirates' dict body verbatim) parked
#     at ring ~4200 around the ship: the chase loop (accel 300 while d > 30,
#     drag exp(−1.4dt), integrate, gait) holds them ALIVE the whole window;
#     terminal 300/1.4 ≈ 214 u/s closes ≤ ~1100 over 5 s — d never grazes
#     the 60 damage window, ttl 40 ≫ window → no resolve/damage/burst churn
#     (the civ probe's far-parked-armada precedent).
#   - 2 black holes (spawnBlackHole's dict body verbatim) parked at ring
#     ~3200: the pull gate (d < 600) and damage gate (d < 40) never fire;
#     the UNGATED drift + ttl decay (TS:447-452) runs every frame.
#   - chaos silenced (gap 1e9 — the econ-probe seam): the deck's pirates/
#     blackholes/flare/tribute would add uncontrolled churn; the deck itself
#     is pinned by test_space_events.gd. persistT hits the 5 s cadence once
#     per window (a ctx.flags dict write — no disk).
# Deterministic: fixed seed, fixed stocking, empty keys_pressed — every run
# is the same world.
#
# Budget vs measured (2026-10-04, this host — the M6 wrap runs): the §5.4
# space target ≤ 2.0 ms is ASSERTED here directly in BOTH modes (the wrap
# tasking: "assert sim_avg_ms ≤ 2 ms in BOTH modes") — see PARITY-M6 §14
# for the recorded numbers. The xvfb scene probe
# (tests/scenes/test_perf_space.gd) re-measures the normal-mode tick inside
# the real game layer (the contention cross-check) and asserts the stage
# render-prep pass ≤ 4 ms (the M3 painter-side budget shape).
# Run: godot --headless -s tools/perf_space_sim.gd
# Prints SPACE_SIM_OK <stats> and exits 0; failures print SPACE_SIM_FAIL on
# stderr, exit 1.
extends SceneTree

const Ctx := preload("res://src/game/context.gd")
const SpaceSim := preload("res://src/game/space/space_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0x5CACE
const SETTLE := 60
const TICKS := 300
const TARGET_MS := 2.0   # the §5.4 space budget — the assert in BOTH modes
const TARGET_PLANETS := 6
const TARGET_COLONIES := 3
const TARGET_PIRATES := 5
const TARGET_HOLES := 2

var _us := 0.0
var _max_us := 0.0
var _ticks := 0


func _mk() -> Dictionary:
	var ctx: Variant = Ctx.new(SEED)
	# hooks {} — every _fire key missing = silent no-op (the sim's contract)
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = SpaceSim.new(ctx, rng, {})
	return {"sim": sim, "ctx": ctx}


func _inp(ff: bool) -> Dictionary:
	return {"keys_pressed": [], "keys_held": (["KeyF"] if ff else [])}


## Park 5 live pirates far out — spawnPirates' dict body verbatim
## (space_sim.gd spawn_pirates), ring ~4200 so the chase never grazes the
## damage window (see header).
func _stock_pirates(sim: Variant) -> void:
	for i in TARGET_PIRATES:
		var a: float = TAU * float(i) / float(TARGET_PIRATES)
		sim.pirates.append({
			"x": float(sim.sx) + cos(a) * 4200.0, "y": float(sim.sy) + sin(a) * 4200.0,
			"vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0,
		})
		sim.pirateTtl.append(40.0)


## Park 2 black holes far out — spawnBlackHole's dict body verbatim, ring
## ~3200: the pull/damage gates never fire, the drift + ttl decay runs.
func _stock_holes(sim: Variant) -> void:
	for i in TARGET_HOLES:
		var a: float = TAU * float(i) / float(TARGET_HOLES) + 0.5
		sim.blackHoles.append({
			"x": float(sim.sx) + cos(a) * 3200.0, "y": float(sim.sy) + sin(a) * 3200.0,
			"vx": 6.0, "vy": -6.0, "ttl": 45.0,
		})


func _stock(sim: Variant) -> void:
	sim.chaos.gap = 1.0e9
	if int(sim.planets.size()) != TARGET_PLANETS:
		_fail("constructor board is not %d planets (%d)"
				% [TARGET_PLANETS, int(sim.planets.size())])
		return
	var ecos := 0
	for p in sim.planets:
		if p["eco"] != null:
			ecos += 1
	if ecos < 3:
		_fail("constructor ring has %d live ecos, expected >= 3" % ecos)
		return
	sim.debug_seed_colonies()
	_stock_pirates(sim)
	_stock_holes(sim)


func _colonies(sim: Variant) -> int:
	var n := 0
	for p in sim.planets:
		if p["colony"] != null:
			n += 1
	return n


## One phase: fresh same-seed sim, settle, stock, time TICKS ticks in the
## given mode. Returns the avg/max ms, or {} after printing a failure.
func _phase(ff: bool) -> Dictionary:
	var m := _mk()
	var sim: Variant = m["sim"]
	for i in SETTLE:
		sim.update(DT, _inp(false))
	_stock(sim)
	if _colonies(sim) != TARGET_COLONIES or int(sim.pirates.size()) != TARGET_PIRATES \
			or int(sim.blackHoles.size()) != TARGET_HOLES:
		_fail("stocking did not hold (colonies %d, pirates %d, holes %d)"
				% [_colonies(sim), int(sim.pirates.size()), int(sim.blackHoles.size())])
		return {}
	_us = 0.0
	_max_us = 0.0
	_ticks = 0
	for i in TICKS:
		var inp := _inp(ff)  # built untimed — the window times sim.update only
		var u0 := Time.get_ticks_usec()
		sim.update(DT, inp)
		var u1 := Time.get_ticks_usec()
		_us += float(u1 - u0)
		_max_us = maxf(_max_us, float(u1 - u0))
		_ticks += 1
		if not is_finite(sim.time) or not is_finite(sim.sx) or not is_finite(sim.shp) \
				or not is_finite(float(sim.planets[0]["angle"])):
			_fail("non-finite state at tick %d (mode %s)" % [i, "ff" if ff else "normal"])
			return {}
	if _colonies(sim) != TARGET_COLONIES or int(sim.pirates.size()) != TARGET_PIRATES \
			or int(sim.blackHoles.size()) != TARGET_HOLES:
		_fail("stocking did not hold through the window (colonies %d, pirates %d, holes %d)"
				% [_colonies(sim), int(sim.pirates.size()), int(sim.blackHoles.size())])
		return {}
	var ecos := 0
	for p in sim.planets:
		if p["eco"] != null:
			ecos += 1
	return {
		"avg_ms": _us / float(_ticks) / 1000.0,
		"max_ms": _max_us / 1000.0,
		"ecos": ecos,
		"min_pop": _min_colony_pop(sim),
	}


func _min_colony_pop(sim: Variant) -> float:
	var mn := INF
	for p in sim.planets:
		if p["colony"] != null:
			mn = minf(mn, float(p["colony"]["pop"]))
	return mn


func _initialize() -> void:
	var normal := _phase(false)
	if normal.is_empty():
		return
	var ff := _phase(true)
	if ff.is_empty():
		return
	print("SPACE_SIM_NUM ticks=%d planets=%d ecos=%d colonies=%d pirates=%d holes=%d target_ms=%.1f"
			% [_ticks, TARGET_PLANETS, int(ff["ecos"]), TARGET_COLONIES,
			TARGET_PIRATES, TARGET_HOLES, TARGET_MS])
	print("SPACE_SIM_NUM normal_avg_ms=%.3f normal_max_ms=%.3f min_pop=%.2f"
			% [float(normal["avg_ms"]), float(normal["max_ms"]), float(normal["min_pop"])])
	print("SPACE_SIM_NUM ff_avg_ms=%.3f ff_max_ms=%.3f"
			% [float(ff["avg_ms"]), float(ff["max_ms"])])
	if float(normal["avg_ms"]) > TARGET_MS or float(ff["avg_ms"]) > TARGET_MS:
		printerr("SPACE_SIM_FAIL: sim tick avg over budget — normal %.3f ms, ff %.3f ms > %.1f ms over %d ticks @ 6 planets + %d ecos + 3 colonies + 5 pirates + 2 holes"
				% [float(normal["avg_ms"]), float(ff["avg_ms"]), TARGET_MS, _ticks])
		quit(1)
		return
	print("SPACE_SIM_OK ticks=%d planets=%d normal_avg_ms=%.3f normal_max_ms=%.3f ff_avg_ms=%.3f ff_max_ms=%.3f"
			% [_ticks, TARGET_PLANETS, float(normal["avg_ms"]), float(normal["max_ms"]),
			float(ff["avg_ms"]), float(ff["max_ms"])])
	quit(0)


func _fail(msg: String) -> void:
	printerr("SPACE_SIM_FAIL: " + msg)
	quit(1)
