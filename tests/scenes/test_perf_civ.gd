# Civ perf probe — the §5.4 civ budgets under the REAL game (xvfb,
# llvmpipe rendering ON — worst case; the contention cross-check to the
# headless tools/perf_civ_sim.gd, which times the SAME 4-city + 3-armada
# world with no game layer at all). Boots the real Game into the civ stage
# directly (the test_perf_tribe pattern: register + switch_stage), keeps the
# CONSTRUCTOR board (4 cities — the §5.4 perf target stocking; no fixture
# writes needed), parks 3 LIVE armadas far out (launch-shaped dicts, one per
# kind — the stocking seams are the headless probe's, documented there) and
# steps 300 ticks. The TIMED METRICS ARE SPLIT (the T10 review minor 4
# lesson, carried from creature/tribe):
#   sim_avg_ms    — the pure sim tick (step_for_testing(1): the stage update
#                   incl. sim.update + the camera/fx scene halves).
#                   RECORDED ONLY here: under llvmpipe the rasterizer process
#                   contends with the timed window — the ASSERTED sim budget
#                   (≤ 2 ms) lives in the contention-immune headless probe
#                   (tools/perf_civ_sim.gd, the M2/M3/M4 lesson),
#   render_avg_ms — the stage render() pass (the portrait fixture re-sync +
#                   the canvas queue_redraw sweep — the GDScript-side
#                   render-prep cost the game controls; the deferred canvas
#                   _draw lands in the frame window) —
#                   ASSERTED ≤ 4 ms (the M3 painter-side budget shape,
#                   civ's own row),
#   frame_avg_ms  — the full engine-frame wall window (previous frame's
#                   measure → this one: sim + render prep + the deferred
#                   _draw + the real llvmpipe rasterization) — recorded
#                   only: rasterization dominates (the planet backdrop + the
#                   ocean gradient + 4 cities + the vignette) and no
#                   GDScript change moves it — the budget targets a real
#                   GPU, not the software rasterizer (the M2 rig caveat:
#                   llvmpipe is the worst case).
# The board stays frozen at 4 cities for the window (far-parked armadas
# never resolve — no flip/victory churn; the victory check runs every tick
# and reads the unchanged board). Deterministic: fixed seed, fixed armada
# placement — every run is the same world.
# Run: tools/test_perf_civ.sh
# Prints PERF_CIV_OK <stats> and exits 0; failures print PERF_CIV_FAIL
# on stderr, exit 1.
extends Node

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")

const SEED := 0x7EC1
const DT := 1.0 / 60.0
const SETTLE := 60
const TARGET_CITIES := 4
const TARGET_ARMADAS := 3
const TICKS := 300
const PAINTER_BUDGET_MS := 4.0  # the render-prep budget (the M3 painter-side shape)
const KINDS := ["attack", "charm", "trade"]
const TIMEOUT_FRAMES := 7200

var _phase := "build"
var _frames := 0
var _game: Variant = null
var _driver: Variant = null
var _ticks_done := 0
var _sim_us := 0.0
var _sim_max_us := 0.0
var _ren_us := 0.0
var _ren_max_us := 0.0
var _wall_us := 0.0
var _wall_max_us := 0.0
var _frame_end_us := 0
var _done := false


func _ready() -> void:
	_driver = BotDriverScript.new()


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	if _done:
		return
	match _phase:
		"build":
			_game = _build_game()
			_phase = "settle"
		"settle":
			if not _settle():
				return
			_phase = "spawn"
		"spawn":
			_stock()
			_frame_end_us = Time.get_ticks_usec()
			_phase = "measure"
		"measure":
			_measure()
		"done":
			pass


## Real Game → civ stage directly (the test_perf_tribe pattern: register +
## switch_stage; _ready builds the constructor board and draws the stage
## rng branch). Manual stepping ONLY (the T6 trap pattern): set_process
## after tree entry, the loop's is_active_cb kills tick() — the probe alone
## drives the clock.
func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(CivStageScript.new(game))
	game.switch_stage("civ")
	return game


func _settle() -> bool:
	if not _stage_ok():
		return false
	_game.step_for_testing(SETTLE, DT)
	return true


func _stage_ok() -> bool:
	if _game.context.stage != "civ":
		_fail("settle: civ stage not reached (got %s)" % str(_game.context.stage))
		return false
	return true


## Park the 3 live armadas far out (the headless probe's seams verbatim:
## the launch body's dict shape, one per kind) and silence chaos.
func _stock() -> void:
	var sim: Variant = _game.current.sim
	sim.chaos.gap = 1.0e9
	if int(sim.cities.size()) != TARGET_CITIES:
		_fail("constructor board is not %d cities (%d)"
				% [TARGET_CITIES, int(sim.cities.size())])
		return
	var cap: Dictionary = sim.cities[0]
	for i in TARGET_ARMADAS:
		sim.armadas.append({
			"x": float(cap["x"]), "y": float(cap["y"]),
			"tx": 6000.0 + float(i) * 100.0, "ty": 6000.0,
			"target": sim.cities[i + 1],
			"kind": KINDS[i], "t": 0.0, "alive": true, "power": 9.0,
		})
	var viol: PackedStringArray = _driver.assert_sane(_game)
	if not viol.is_empty():
		_fail("post-stock assert_sane: %s" % str(viol))
		return
	print("PERF_CIV_SPAWN cities=%d armadas=%d"
			% [int(sim.cities.size()), int(sim.armadas.size())])


## One sim tick per engine frame; the timed metrics are SPLIT (see header):
## the pure sim tick is recorded (the asserted budget lives headless), the
## stage render pass carries the ASSERTED painter-side budget, and the full
## wall window (previous frame end → this frame end — sim + render prep +
## the deferred _draw + the real llvmpipe rasterization) is recorded only.
func _measure() -> void:
	var sim: Variant = _game.current.sim
	var u0 := Time.get_ticks_usec()
	_game.step_for_testing(1, DT)
	var u1 := Time.get_ticks_usec()
	_game._do_render(0.0)
	var u2 := Time.get_ticks_usec()
	_sim_us += float(u1 - u0)
	_sim_max_us = maxf(_sim_max_us, float(u1 - u0))
	_ren_us += float(u2 - u1)
	_ren_max_us = maxf(_ren_max_us, float(u2 - u1))
	_ticks_done += 1
	if _ticks_done % 60 == 0:
		var viol: PackedStringArray = _driver.assert_sane(_game)
		if not viol.is_empty():
			_fail("assert_sane at tick %d: %s" % [_ticks_done, str(viol)])
			return
	if _ticks_done >= TICKS:
		var now := Time.get_ticks_usec()
		_wall_us += float(now - _frame_end_us)
		_frame_end_us = now
		_report()
		return
	# the wall window CLOSES at the next frame's end — the deferred draw pass
	# must land inside it, so accumulate only here (one window per frame)
	var now := Time.get_ticks_usec()
	_wall_us += float(now - _frame_end_us)
	_wall_max_us = maxf(_wall_max_us, float(now - _frame_end_us))
	_frame_end_us = now


func _report() -> void:
	var sim: Variant = _game.current.sim
	var avg_tick_ms := _sim_us / float(_ticks_done) / 1000.0
	var max_tick_ms := _sim_max_us / 1000.0
	var avg_ren_ms := _ren_us / float(_ticks_done) / 1000.0
	var max_ren_ms := _ren_max_us / 1000.0
	var avg_frame_ms := _wall_us / float(_ticks_done) / 1000.0
	var max_frame_ms := _wall_max_us / 1000.0
	var viol: PackedStringArray = _driver.assert_sane(_game)
	if not viol.is_empty():
		_fail("final assert_sane: %s" % str(viol))
		return
	var live := 0
	for a in sim.armadas:
		if bool(a["alive"]):
			live += 1
	if int(sim.cities.size()) != TARGET_CITIES or live != TARGET_ARMADAS:
		_fail("stocking did not hold (cities %d, live armadas %d)"
				% [int(sim.cities.size()), live])
		return
	print("PERF_CIV_NUM ticks=%d cities=%d armadas=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f"
			% [_ticks_done, int(sim.cities.size()), live, avg_tick_ms, max_tick_ms,
			avg_ren_ms, max_ren_ms, avg_frame_ms, max_frame_ms])
	# render_avg_ms is the ASSERTED budget (the stage render() pass — the
	# portrait fixture re-sync + the canvas queue sweep, the GDScript-side
	# render-prep cost the game controls; the deferred canvas _draw +
	# llvmpipe rasterization land in the frame window). frame_avg_ms is
	# recorded informationally only: under llvmpipe the rasterization of the
	# planet pass dominates and no GDScript-side change moves it — that
	# budget targets a real GPU (the M2 rig-caveat precedent). The sim tick
	# is recorded here and ASSERTED in the headless probe
	# (contention-immune).
	if avg_ren_ms > PAINTER_BUDGET_MS:
		_fail("render-prep budget: render avg %.3f ms > %.1f ms over %d ticks @ %d cities + %d live armadas (max %.3f)"
				% [avg_ren_ms, PAINTER_BUDGET_MS, _ticks_done,
				int(sim.cities.size()), live, max_ren_ms])
		return
	print("PERF_CIV_OK ticks=%d cities=%d armadas=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f painter_budget_ms=%.1f"
			% [_ticks_done, int(sim.cities.size()), live,
			avg_tick_ms, max_tick_ms, avg_ren_ms, max_ren_ms,
			avg_frame_ms, max_frame_ms, PAINTER_BUDGET_MS])
	_phase = "done"
	_done = true
	get_tree().quit(0)


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("PERF_CIV_FAIL: " + msg)
	get_tree().quit(1)
