# GameLoop accumulator tests: 60Hz fixed step, frameDt clamp 0.25, 8-step cap,
# render(alpha) once per tick, tick_manual for tests/bots. Port of the TS
# loop.ts semantics — the rAF frame became tick(frame_dt).
extends "res://tests/test_base.gd"

const LoopScript := preload("res://src/core/loop.gd")

var updates: Array = []
var renders: Array = []


func _loop() -> Variant:
	updates = []
	renders = []
	var l: Variant = LoopScript.new(
		func(dt: float) -> void: updates.append(dt),
		func(alpha: float) -> void: renders.append(alpha)
	)
	return l


func test_step_size_is_1_over_60() -> void:
	var l: Variant = _loop()
	approx(l.step, 1.0 / 60.0, "step = 1/60")


func test_tick_runs_fixed_steps_then_renders() -> void:
	var l: Variant = _loop()
	l.tick(0.25)
	eq(updates.size(), 8, "0.25s at 60Hz minus the cap → 8 steps")
	for dt in updates:
		approx(dt, 1.0 / 60.0, "each update gets the fixed step")
	eq(renders.size(), 1, "render once per tick")
	# acc = 0.25 - 8/60 → alpha = acc/step = 7
	approx(renders[0], 0.25 / (1.0 / 60.0) - 8.0, "alpha = acc/step")


func test_tick_below_step_accumulates() -> void:
	var l: Variant = _loop()
	l.tick(0.01)
	eq(updates.size(), 0, "no step yet below 1/60")
	approx(renders[0], 0.6, "alpha = 0.01/step")
	l.tick(0.01)
	eq(updates.size(), 1, "accumulator crossed the step")
	approx(updates[0], 1.0 / 60.0, "update got the fixed step")


func test_big_delta_clamped_so_sim_never_explodes() -> void:
	var l: Variant = _loop()
	l.tick(10.0)
	eq(updates.size(), 8, "tab-switch delta clamped to the 8-step cap")
	# acc clamped to 0.25 → after 8 steps: 0.25 - 8/60
	approx(l.acc, 0.25 - 8.0 / 60.0, "acc clamped to 0.25 before stepping")
	# a 0.5s frame behaves exactly like a 0.25s frame (frameDt clamp first)
	var l2: Variant = _loop()
	l2.tick(0.5)
	eq(updates.size(), 8, "0.5s frame same as clamped")
	approx(l2.acc, l.acc, "frameDt clamp 0.25 matches")


func test_step_cap_never_exceeds_eight() -> void:
	var l: Variant = _loop()
	l.tick(0.25)
	l.tick(0.25)
	# second tick: acc = min(0.1167 + 0.25, 0.25) = 0.25 → 8 more steps (cap), not 22
	eq(updates.size(), 16, "second tick also capped at 8")
	approx(l.acc, 0.25 - 8.0 / 60.0, "acc re-clamped to 0.25 each tick")


func test_tick_manual_drives_exact_steps() -> void:
	var l: Variant = _loop()
	l.tick_manual(5, 0.1)
	eq(updates.size(), 5, "exactly n updates")
	for dt in updates:
		approx(dt, 0.1, "manual dt passed through")
	eq(renders.size(), 0, "no render on the manual path")


func test_tick_manual_default_dt_is_step() -> void:
	var l: Variant = _loop()
	l.tick_manual(3)
	eq(updates.size(), 3, "3 updates")
	for dt in updates:
		approx(dt, 1.0 / 60.0, "default dt = step")


func test_is_active_guard_skips_everything() -> void:
	updates = []
	renders = []
	var l: Variant = LoopScript.new(
		func(dt: float) -> void: updates.append(dt),
		func(alpha: float) -> void: renders.append(alpha),
		60.0,
		func() -> bool: return false
	)
	l.tick(0.25)
	eq(updates.size(), 0, "inactive: no updates")
	eq(renders.size(), 0, "inactive: no render")
