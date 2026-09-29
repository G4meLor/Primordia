# Camera rig tests: follow damp formula, shake decay/latching, to_world inverse
# round-trip through a known camera transform, view bounds. Math-only (the rig
# works without a tree; the Camera2D child sync is exercised by the boot test).
extends "res://tests/test_base.gd"

const CamScript := preload("res://src/game/cam.gd")


func test_follow_damp_formula() -> void:
	var cam: Variant = CamScript.new()
	cam.follow(100.0, 0.0, 1.0 / 60.0, 6.0)
	# k = 1-exp(-6/60) — TS formula exact
	approx(cam.x, 100.0 * (1.0 - exp(-0.1)), "follow x after one step")
	approx(cam.y, 0.0, "follow y unmoved")


func test_follow_converges() -> void:
	var cam: Variant = CamScript.new()
	for i in 600:
		cam.follow(100.0, -50.0, 1.0 / 60.0, 6.0)
	ok(absf(cam.x - 100.0) < 0.01, "x converged")
	ok(absf(cam.y + 50.0) < 0.01, "y converged")


func test_default_rate_is_6() -> void:
	var cam: Variant = CamScript.new()
	cam.follow(100.0, 0.0, 1.0 / 60.0)
	approx(cam.x, 100.0 * (1.0 - exp(-0.1)), "default rate 6 (TS)")


func test_snap_teleports() -> void:
	var cam: Variant = CamScript.new()
	cam.snap(5.0, 7.0)
	eq(cam.x, 5.0, "snap x")
	eq(cam.y, 7.0, "snap y")


func test_zoom_default_1() -> void:
	var cam: Variant = CamScript.new()
	eq(cam.zoom, 1.0, "zoom default (TS)")


func test_shake_decays_to_zero() -> void:
	var cam: Variant = CamScript.new()
	cam.shake(10.0, 0.4)
	eq(cam._shake_mag, 10.0, "shake latches magnitude")
	cam.update(0.1)
	# active shake: m = mag * max(0, t*2.5) = 10 * 0.75
	var m := 10.0 * 0.3 * 2.5
	ok(absf(cam.shake_x) <= m, "shake_x within decayed magnitude")
	ok(absf(cam.shake_y) <= m, "shake_y within decayed magnitude")
	approx(cam._shake_t, 0.3, "shake timer decays")
	cam.update(0.4)
	eq(cam.shake_x, 0.0, "expired shake zeroes x")
	eq(cam.shake_y, 0.0, "expired shake zeroes y")
	eq(cam._shake_mag, 0.0, "expired shake clears magnitude")


func test_weaker_shake_ignored_while_active() -> void:
	var cam: Variant = CamScript.new()
	cam.shake(5.0, 0.4)
	cam.shake(3.0, 0.4)
	eq(cam._shake_mag, 5.0, "weaker shake during active shake ignored")


func test_weaker_shake_taken_after_expiry() -> void:
	var cam: Variant = CamScript.new()
	cam.shake(5.0, 0.1)
	cam.update(0.2)  # expired
	cam.shake(3.0, 0.4)
	eq(cam._shake_mag, 3.0, "shake after expiry accepted (shakeT <= 0)")


func test_shake_is_seeded_deterministic() -> void:
	# TS used Math.random; native draws from a private Rng stream (constraint 4)
	var a: Variant = CamScript.new()
	var b: Variant = CamScript.new()
	a.shake(4.0, 0.4)
	b.shake(4.0, 0.4)
	a.update(0.1)
	b.update(0.1)
	eq(a.shake_x, b.shake_x, "same seed → same jitter x")
	eq(a.shake_y, b.shake_y, "same seed → same jitter y")


func test_to_world_inverts_the_transform() -> void:
	var cam: Variant = CamScript.new()
	cam.snap(100.0, 50.0)
	cam.zoom = 2.0
	# TS formula: (sx - vw/2)/zoom + x
	eq(cam.to_world(400.0, 300.0, 800.0, 600.0), Vector2(100.0, 50.0), "screen center → cam pos")
	var w: Vector2 = cam.to_world(500.0, 350.0, 800.0, 600.0)
	approx(w.x, 150.0, "to_world x")
	approx(w.y, 75.0, "to_world y")


func test_to_world_round_trips_a_known_point() -> void:
	var cam: Variant = CamScript.new()
	cam.snap(100.0, 50.0)
	cam.zoom = 2.0
	# world → screen through the known transform, then back through to_world
	var p := Vector2(321.5, 117.25)
	var s := Vector2((p.x - cam.x) * cam.zoom + 400.0, (p.y - cam.y) * cam.zoom + 300.0)
	var back: Vector2 = cam.to_world(s.x, s.y, 800.0, 600.0)
	approx(back.x, p.x, "round-trip x")
	approx(back.y, p.y, "round-trip y")


func test_view_bounds_for_culling() -> void:
	var cam: Variant = CamScript.new()
	cam.snap(100.0, 50.0)
	cam.zoom = 2.0
	cam.update_view_bounds(800.0, 600.0)
	approx(cam.view_l, 100.0 - 400.0 / 2.0, "view_l")
	approx(cam.view_r, 100.0 + 400.0 / 2.0, "view_r")
	approx(cam.view_t, 50.0 - 300.0 / 2.0, "view_t")
	approx(cam.view_b, 50.0 + 300.0 / 2.0, "view_b")
