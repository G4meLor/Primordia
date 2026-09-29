# Port of the TS world.test.ts math expectations: TS-exact values for every
# helper in src/core/math.ts. Ease/format values are computed by hand from the
# TS formulas; float comparisons ride approx(eps >= 1e-9) per M1 carry-forward.
extends "res://tests/test_base.gd"

# Same -s-mode constraint as every M1 test: resolve scripts by path.
const MathScript := preload("res://src/core/math.gd")


# --- dead-test guard (fix round 2) -------------------------------------------
# A math.gd compile break used to be SILENT: preload handed the tests a dead
# script, every static call aborted its method as a runtime script error, and
# the runner reported "ok (0 checks, 0 failures)" — a green lie (found by T3).
# GDScript has no try/catch, so the guard probes metadata only — calling a
# MathScript member here would abort the guard itself — and EVERY test starts
# with `if not _alive(): return`, so a broken load records a real FAILURE.
func _alive() -> bool:
	# widen to Script: with math.gd healthy the preload const is typed as the
	# global class PMath, which rejects instance-only Script methods at parse
	var s: Script = MathScript
	if s == null or not s.can_instantiate():
		ok(false, "math.gd failed to load/compile — this test's checks never ran")
		return false
	if s.get_script_method_list().is_empty():
		ok(false, "math.gd compiled to an empty method table — math tests are dead")
		return false
	return true


func test_damp() -> void:
	if not _alive():
		return
	# damp(rate,dt) = 1-exp(-rate*dt); TS-exact values
	approx(MathScript.damp(6.0, 1.0 / 60.0), 0.0951625819640405, "damp(6, 1/60)")
	approx(MathScript.damp(1.5, 0.5), 0.5276334472589853, "damp(1.5, 0.5)")
	eq(MathScript.damp(0.0, 1.0), 0.0, "damp(0, dt) is 0")
	eq(MathScript.damp(6.0, 0.0), 0.0, "damp(rate, 0) is 0")


func test_smoothstep() -> void:
	if not _alive():
		return
	approx(MathScript.smoothstep(0.25), 0.15625, "smoothstep(0.25)")
	eq(MathScript.smoothstep(-1.0), 0.0, "smoothstep clamps low")
	eq(MathScript.smoothstep(2.0), 1.0, "smoothstep clamps high")
	approx(MathScript.smoothstep(0.5), 0.5, "smoothstep(0.5)")


func test_easings() -> void:
	if not _alive():
		return
	approx(MathScript.ease_out_cubic(0.5), 0.875, "ease_out_cubic(0.5)")
	approx(MathScript.ease_in_cubic(0.5), 0.125, "ease_in_cubic(0.5)")
	# ease_out_back: c = 1.70158 exact; 1 + x*x*((c+1)*x + c) at x = -0.5
	approx(MathScript.ease_out_back(0.5), 1.0876975, "ease_out_back(0.5)")
	# clamps low to a float residue, not exact 0 (TS float64 matches)
	approx(MathScript.ease_out_back(-1.0), 0.0, "ease_out_back clamps low")
	eq(MathScript.ease_out_back(2.0), 1.0, "ease_out_back clamps high")


func test_wrap_angle() -> void:
	if not _alive():
		return
	# JS % keeps the sign (fmod), then the ±TAU shifts — wrap_angle(3π/2) < 0
	approx(MathScript.wrap_angle(3.0 * PI / 2.0), -PI / 2.0, "wrap_angle(3π/2)")
	approx(MathScript.wrap_angle(-4.0), MathScript.TAU - 4.0, "wrap_angle(-4)")
	approx(MathScript.wrap_angle(PI), PI, "wrap_angle(PI) stays PI (not > PI)")
	approx(MathScript.wrap_angle(PI + 0.1), 0.1 - PI, "wrap_angle just past PI")
	eq(MathScript.wrap_angle(0.0), 0.0, "wrap_angle(0)")


func test_tau() -> void:
	if not _alive():
		return
	approx(MathScript.TAU, 6.283185307179586, "TAU = 2π")


func test_clamp_lerp() -> void:
	if not _alive():
		return
	eq(MathScript.clamp(-5.0, 0.0, 10.0), 0.0, "clamp low")
	eq(MathScript.clamp(5.0, 0.0, 10.0), 5.0, "clamp mid")
	eq(MathScript.clamp(15.0, 0.0, 10.0), 10.0, "clamp high")
	eq(MathScript.lerp(10.0, 20.0, 0.25), 12.5, "lerp(10, 20, 0.25)")


func test_vec_helpers() -> void:
	if not _alive():
		return
	var a := Vector2(3.0, 4.0)
	var b := Vector2(1.0, 2.0)
	eq(MathScript.vec_dist(Vector2.ZERO, a), 5.0, "vec_dist = Vector2.distance_to")
	eq(MathScript.vec_dist2(Vector2.ZERO, a), 25.0, "vec_dist2")
	eq(MathScript.vec_len(a), 5.0, "vec_len")
	eq(MathScript.vec_len2(a), 25.0, "vec_len2")
	eq(MathScript.vec_dot(b, Vector2(3.0, 4.0)), 11.0, "vec_dot")
	var n := MathScript.vec_normalize(a)
	# eps 1e-6: Vector2 stores float32 — 3/5 lands at 0.60000002384… there,
	# while TS's Vec2 math is float64 (0.59999999999999998). eps floor 1e-9
	# cannot hold across the float32 storage boundary.
	approx(n.x, 0.6, "vec_normalize x", 1e-6)
	approx(n.y, 0.8, "vec_normalize y", 1e-6)
	eq(MathScript.vec_normalize(Vector2.ZERO), Vector2.ZERO, "vec_normalize zero")
	# TS guard: l < 1e-9 → {0,0} (Vector2.normalized() would divide instead)
	eq(MathScript.vec_normalize(Vector2(1e-10, 0.0)), Vector2.ZERO, "vec_normalize tiny")


func test_angles() -> void:
	if not _alive():
		return
	approx(MathScript.angle_of(Vector2(0.0, 1.0)), PI / 2.0, "angle_of up")
	approx(MathScript.angle_of(Vector2(-1.0, 0.0)), PI, "angle_of left")
	eq(MathScript.angle_diff(0.1, 0.1), 0.0, "angle_diff same")
	approx(MathScript.angle_diff(0.0, 3.0 * PI / 2.0), -PI / 2.0, "angle_diff shortest")
	approx(MathScript.angle_diff(3.0 * PI / 2.0, 0.0), PI / 2.0, "angle_diff reverse")


func test_on_circle() -> void:
	if not _alive():
		return
	eq(MathScript.on_circle(Vector2(10.0, 10.0), 5.0, 0.0), Vector2(15.0, 10.0), "on_circle angle 0")
	var p := MathScript.on_circle(Vector2.ZERO, 2.0, PI / 2.0)
	approx(p.x, 0.0, "on_circle x")
	approx(p.y, 2.0, "on_circle y")
	var q := MathScript.shortest_vec_on_circle(Vector2(1.0, 1.0), 1.0, 0.0)
	eq(q, Vector2(2.0, 1.0), "shortest_vec_on_circle")


func test_format_num() -> void:
	if not _alive():
		return
	# TS toFixed(1) decimal formatting — ties pick the LARGER n (JS spec rule),
	# which %.1f (round-half-even) would get wrong on the 12.25k case below.
	eq(MathScript.format_num(12345.0), "12.3k", "format_num 12345")
	eq(MathScript.format_num(12250.0), "12.3k", "format_num exact tie picks larger")
	# double-rounding trap: fl(12.35) sits BELOW the .35 tie (−3.55e-16) so TS
	# prints "12.3k"; a multiply-then-round _to_fixed1 lands fl(12.35)*10
	# exactly on 123.5 and rounds up to "12.4k" — pinning that was pinning a
	# port bug (fix round 2); the spec-exact divide-compare form fixes it
	eq(MathScript.format_num(12350.0), "12.3k", "format_num below-tie 12.35 (double-round trap)")
	eq(MathScript.format_num(10000.0), "10.0k", "format_num 1e4 boundary")
	eq(MathScript.format_num(9999.0), "9999", "format_num below k")
	eq(MathScript.format_num(123.6), "124", "format_num rounds")
	eq(MathScript.format_num(0.4), "0", "format_num sub-1")
	eq(MathScript.format_num(1234567.0), "1.2M", "format_num millions")
	eq(MathScript.format_num(1000000.0), "1.0M", "format_num 1e6 boundary")
	eq(MathScript.format_num(1500000000.0), "1.5B", "format_num billions")
	eq(MathScript.format_num(1000000000.0), "1.0B", "format_num 1e9 boundary")
