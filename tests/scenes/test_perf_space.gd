# Space perf probe — the §5.4 space budgets under the REAL game (xvfb,
# llvmpipe rendering ON — worst case; the contention cross-check to the
# headless tools/perf_space_sim.gd, which times the SAME 6-planet + 5-pirate
# + 2-hole world in BOTH modes with no game layer at all). Boots the real
# Game into the space stage directly (the test_perf_civ pattern: register +
# switch_stage — the stage _ready fires on tree entry and the switch fires
# the real on_enter with the fresh constructor system), stocks the documented
# probe seams (the headless probe's stocking verbatim: 3 colonies via the
# debug cheat + 5 far-parked live pirates + 2 far black holes + chaos
# silenced) and steps 300 ticks in NORMAL mode. The TIMED METRICS ARE SPLIT
# (the T10 review minor 4 lesson, carried from creature/tribe/civ):
#   sim_avg_ms    — the pure sim tick (step_for_testing(1): the stage update
#                   incl. sim.update + the camera feed + the fx pool steps).
#                   RECORDED ONLY here: under llvmpipe the rasterizer process
#                   contends with the timed window — the ASSERTED sim budget
#                   (≤ 2 ms in BOTH modes — normal AND ff-hold — the wrap
#                   tasking) lives in the contention-immune headless probe
#                   (tools/perf_space_sim.gd, the M2/M3/M4/M5 lesson),
#   render_avg_ms — the stage render() pass (the beam/cargo/panel syncs +
#                   the six-canvas queue sweep — the GDScript-side
#                   render-prep cost the game controls; the deferred canvas
#                   _draw lands in the frame window) —
#                   ASSERTED ≤ 4 ms (the M3 painter-side budget shape,
#                   space's own row),
#   frame_avg_ms  — the full engine-frame wall window (previous frame's
#                   measure → this one: sim + render prep + the deferred
#                   _draw + the real llvmpipe rasterization) — recorded
#                   only: rasterization dominates (the space backdrop + 6
#                   planet discs + the vignette) and no GDScript change
#                   moves it — the budget targets a real GPU, not the
#                   software rasterizer (the M2 rig caveat: llvmpipe is the
#                   worst case).
# The world stays frozen for the window (far-parked pirates never reach the
# damage window — the chase closes ≤ ~1100 of 4200; holes never enter the
# 600 pull gate; pops never reach the 20 thriving trigger). Deterministic:
# fixed seed, fixed stocking — every run is the same world.
# Run: tools/test_perf_space.sh
# Prints PERF_SPACE_OK <stats> and exits 0; failures print PERF_SPACE_FAIL
# on stderr, exit 1.
extends Node

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")

const SEED := 0x5CACE
const DT := 1.0 / 60.0
const SETTLE := 60
const TARGET_PLANETS := 6
const TARGET_COLONIES := 3
const TARGET_PIRATES := 5
const TARGET_HOLES := 2
const TICKS := 300
const PAINTER_BUDGET_MS := 4.0  # the render-prep budget (the M3 painter-side shape)
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


## Real Game → space stage directly (the test_perf_civ pattern: register +
## switch_stage; tree entry fires the stage _ready, the switch fires the
## real on_enter — the fresh constructor system, no blob). Manual stepping
## ONLY (the T6 trap pattern): set_process after tree entry, the loop's
## is_active_cb kills tick() — the probe alone drives the clock.
func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(SpaceStageScript.new(game))
	game.switch_stage("space")
	return game


func _settle() -> bool:
	if not _stage_ok():
		return false
	_game.step_for_testing(SETTLE, DT)
	return true


func _stage_ok() -> bool:
	if _game.context.stage != "space":
		_fail("settle: space stage not reached (got %s)" % str(_game.context.stage))
		return false
	return true


## Stock the headless probe's seams verbatim (tools/perf_space_sim.gd): chaos
## silenced, 3 colonies (the debug cheat), 5 far-parked live pirates, 2 far
## black holes.
func _stock() -> void:
	var sim: Variant = _game.current.sim
	sim.chaos.gap = 1.0e9
	if int(sim.planets.size()) != TARGET_PLANETS:
		_fail("constructor board is not %d planets (%d)"
				% [TARGET_PLANETS, int(sim.planets.size())])
		return
	sim.debug_seed_colonies()
	for i in TARGET_PIRATES:
		var a: float = TAU * float(i) / float(TARGET_PIRATES)
		sim.pirates.append({
			"x": float(sim.sx) + cos(a) * 4200.0, "y": float(sim.sy) + sin(a) * 4200.0,
			"vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0,
		})
		sim.pirateTtl.append(40.0)
	for i in TARGET_HOLES:
		var a: float = TAU * float(i) / float(TARGET_HOLES) + 0.5
		sim.blackHoles.append({
			"x": float(sim.sx) + cos(a) * 3200.0, "y": float(sim.sy) + sin(a) * 3200.0,
			"vx": 6.0, "vy": -6.0, "ttl": 45.0,
		})
	var viol: PackedStringArray = _driver.assert_sane(_game)
	if not viol.is_empty():
		_fail("post-stock assert_sane: %s" % str(viol))
		return
	print("PERF_SPACE_SPAWN planets=%d colonies=%d pirates=%d holes=%d"
			% [int(sim.planets.size()), _colonies(sim),
			int(sim.pirates.size()), int(sim.blackHoles.size())])


func _colonies(sim: Variant) -> int:
	var n := 0
	for p in sim.planets:
		if p["colony"] != null:
			n += 1
	return n


## One sim tick per engine frame; the timed metrics are SPLIT (see header):
## the pure sim tick is recorded (the asserted ≤ 2 ms budgets — BOTH modes —
## live in the headless probe), the stage render pass carries the ASSERTED
## painter-side budget, and the full wall window (previous frame end → this
## frame end — sim + render prep + the deferred _draw + the real llvmpipe
## rasterization) is recorded only.
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
	if _colonies(sim) != TARGET_COLONIES or int(sim.pirates.size()) != TARGET_PIRATES \
			or int(sim.blackHoles.size()) != TARGET_HOLES:
		_fail("stocking did not hold (colonies %d, pirates %d, holes %d)"
				% [_colonies(sim), int(sim.pirates.size()), int(sim.blackHoles.size())])
		return
	print("PERF_SPACE_NUM ticks=%d planets=%d colonies=%d pirates=%d holes=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f"
			% [_ticks_done, int(sim.planets.size()), _colonies(sim),
			int(sim.pirates.size()), int(sim.blackHoles.size()),
			avg_tick_ms, max_tick_ms, avg_ren_ms, max_ren_ms,
			avg_frame_ms, max_frame_ms])
	# render_avg_ms is the ASSERTED budget (the stage render() pass — the
	# beam/cargo/panel syncs + the six-canvas queue sweep, the GDScript-side
	# render-prep cost the game controls; the deferred canvas _draw +
	# llvmpipe rasterization land in the frame window). frame_avg_ms is
	# recorded informationally only: under llvmpipe the rasterization of the
	# space pass dominates and no GDScript-side change moves it — that
	# budget targets a real GPU (the M2 rig-caveat precedent). The sim tick
	# is recorded here and ASSERTED in BOTH modes in the headless probe
	# (contention-immune).
	if avg_ren_ms > PAINTER_BUDGET_MS:
		_fail("render-prep budget: render avg %.3f ms > %.1f ms over %d ticks @ %d planets + %d live pirates + %d holes (max %.3f)"
				% [avg_ren_ms, PAINTER_BUDGET_MS, _ticks_done,
				int(sim.planets.size()), int(sim.pirates.size()),
				int(sim.blackHoles.size()), max_ren_ms])
		return
	print("PERF_SPACE_OK ticks=%d planets=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f painter_budget_ms=%.1f"
			% [_ticks_done, int(sim.planets.size()), avg_tick_ms, max_tick_ms,
			avg_ren_ms, max_ren_ms, avg_frame_ms, max_frame_ms, PAINTER_BUDGET_MS])
	_phase = "done"
	_done = true
	get_tree().quit(0)


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("PERF_SPACE_FAIL: " + msg)
	get_tree().quit(1)
