# Civ sim-tick perf probe — HEADLESS (the §5.4 civ budget row; the M4
# tribe pattern, PARITY-M4.md §12 — contention-immune, the ASSERTED budget
# lives here). Builds the CivSim DIRECTLY (no scene, no game layer, no
# painter — pure sim.update on the constructor board), and times 300 ticks.
#
# Stocking (documented probe seams, the tribe-probe shape):
#   - 4 cities: the CONSTRUCTOR board verbatim — your capital + the 3 rivals
#     (the §5.4 perf target stocking; no fixture writes needed — the civ
#     board is born at target size).
#   - 3 LIVE armadas as launch-shaped dicts (the launch body's dict verbatim,
#     civ_sim.gd:511-513 — one per kind attack/charm/trade, power 9, target
#     the matching rival city) parked far out (tx/ty ~8400 map units from the
#     capital): the flight loop holds them ALIVE the whole window (5 s of
#     flight covers 1100 of ~8400 units — d never grazes 14, t never passes
#     14), so the per-tick hot path is the real one: the flight step + the
#     trail chance(0.5) roll per armada (real stream draws, silent fx hooks)
#     + the armada-following camera drift. No resolves → no flip churn, the
#     board stays 4 cities (the tribe probe's "siege the whole window"
#     precedent: hold the hot path at stocked size, no event churn).
#   - chaos silenced (gap 1e9 — the econ-probe seam): the deck's quakes/
#     rebellions would add uncontrolled work spikes; the deck itself is
#     pinned by test_civ_events.gd. tickSecond (production, the three rival
#     personalities, hearts, karma, flips) runs on the REAL 1 s floor-cross
#     gate — 5 in-window ticks at 300 frames.
# Deterministic: fixed seed, fixed armada placement, empty keys_pressed —
# every run is the same world (the ab_state_dump pattern).
#
# Budget vs measured (2026-10-03, this host — the M5 wrap runs): the §5.4
# civ target ≤ 2.0 ms @ 4 cities + 3 live armadas is ASSERTED here directly
# (the wrap tasking: "assert sim_avg_ms ≤ 2 ms") and MET with orders of
# magnitude to spare: **0.026–0.029 ms avg over 5 runs** (max spikes
# 0.047–0.170 ms) — 4 cities vs tribe's 60-sim job-AI world (the M4 shape,
# 0.71–1.00 ms) is a far lighter hot loop; the number is expected ≪ the
# budget. The tribe probe's separate 4 ms 2×-tripwire stays standing for
# ITS stocking; this probe asserts the civ budget itself.
# The xvfb scene probe (tests/scenes/test_perf_civ.gd) re-measures the same
# tick inside the real game layer (the contention cross-check) and asserts
# the stage render-prep pass ≤ 4 ms (the M3 painter-side budget shape).
# Run: godot --headless -s tools/perf_civ_sim.gd
# Prints CIV_SIM_OK <stats> and exits 0; failures print CIV_SIM_FAIL on
# stderr, exit 1.
extends SceneTree

const Ctx := preload("res://src/game/context.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0x7EC1
const SETTLE := 60
const TICKS := 300
const TARGET_MS := 2.0   # the §5.4 civ budget — the assert (see header)
const KINDS := ["attack", "charm", "trade"]

var _us := 0.0
var _max_us := 0.0
var _ticks := 0


func _mk(seed_v: int) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	# hooks {} — every _fire key missing = silent no-op (the sim's contract)
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CivSim.new(ctx, rng, {})
	return {"sim": sim, "ctx": ctx}


func _inp(_i: int) -> Dictionary:
	return {"keys_pressed": []}


## Park 3 live armadas far out — the launch body's dict shape verbatim
## (civ_sim.gd:511-513), one per kind, targets the matching rival city.
## Far tx/ty keep d > 14 and t < 14 for the whole window (see header).
func _stock_armadas(sim: Variant) -> void:
	var cap: Dictionary = sim.cities[0]
	for i in 3:
		sim.armadas.append({
			"x": float(cap["x"]), "y": float(cap["y"]),
			"tx": 6000.0 + float(i) * 100.0, "ty": 6000.0,
			"target": sim.cities[i + 1],
			"kind": KINDS[i], "t": 0.0, "alive": true, "power": 9.0,
		})


func _initialize() -> void:
	var m := _mk(SEED)
	var sim: Variant = m["sim"]
	sim.chaos.gap = 1.0e9
	if int(sim.cities.size()) != 4:
		_fail("constructor board is not 4 cities (%d)" % int(sim.cities.size()))
		return
	for i in SETTLE:
		sim.update(DT, _inp(i))
	_stock_armadas(sim)
	for i in TICKS:
		var inp := _inp(i)  # built untimed — the window times sim.update only
		var u0 := Time.get_ticks_usec()
		sim.update(DT, inp)
		var u1 := Time.get_ticks_usec()
		_us += float(u1 - u0)
		_max_us = maxf(_max_us, float(u1 - u0))
		_ticks += 1
		if not is_finite(sim.time) or not is_finite(sim.camX) \
				or not is_finite(sim.camY) or not is_finite(sim.mil) \
				or not is_finite(float(sim.cities[0]["hp"])):
			_fail("non-finite state at tick %d" % i)
			return
	var avg_ms := _us / float(_ticks) / 1000.0
	var max_ms := _max_us / 1000.0
	var live := 0
	for a in sim.armadas:
		if bool(a["alive"]):
			live += 1
	if int(sim.cities.size()) != 4 or live != 3:
		_fail("stocking did not hold (cities %d, live armadas %d)"
				% [int(sim.cities.size()), live])
		return
	print("CIV_SIM_NUM ticks=%d cities=%d armadas=%d target_ms=%.1f sim_avg_ms=%.3f sim_max_ms=%.3f"
			% [_ticks, int(sim.cities.size()), live, TARGET_MS, avg_ms, max_ms])
	if avg_ms > TARGET_MS:
		printerr("CIV_SIM_FAIL: sim tick avg %.3f ms > %.1f ms budget over %d ticks @ 4 cities + 3 live armadas (max %.3f)"
				% [avg_ms, TARGET_MS, _ticks, max_ms])
		quit(1)
		return
	print("CIV_SIM_OK ticks=%d cities=%d armadas=%d sim_avg_ms=%.3f sim_max_ms=%.3f"
			% [_ticks, int(sim.cities.size()), live, avg_ms, max_ms])
	quit(0)


func _fail(msg: String) -> void:
	printerr("CIV_SIM_FAIL: " + msg)
	quit(1)
