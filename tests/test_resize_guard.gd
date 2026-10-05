## QC r1 B4 root guard — game.gd `_resize` must reject degenerate viewport
## sizes (the X11/llvmpipe transient collapse 1152→300→30→0 under load) and
## keep the previously latched vw/vh, while every genuine resize — including a
## deliberately small window and the very first resize from zero — still
## lands. The decision lives in the pure `_resize_ok(new, old)`, tested here
## against every branch; the real `_resize` is smoked for the headless
## treeless no-op (the -s suite has no live tree — see the tail of this file).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")


## The reference "real window" for win-relative cases: the OS report when it
## is sane (≥64/axis), else the project's 1152×648 — with a degenerate
## headless window (this server reports (0,0)) the ratio leg is inert anyway,
## so any sane reference gives the same verdicts for viewport == window sizes.
func _win_ref() -> Vector2:
	var win: Vector2i = DisplayServer.window_get_size()
	return Vector2(win) if (win.x >= 64 and win.y >= 64) else Vector2(1152, 648)


func _bare_game() -> Variant:
	return GameScript.new(ContextScript.new())


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the stub-Callable cycle (test_game_flow._drop)
		g.free()


# ---- _resize_ok: the pure decision --------------------------------------------


func test_resize_ok_rejects_degenerate() -> void:
	var g: Variant = _bare_game()
	# the B4 collapse signature — sub-floor on either axis is never a resize
	ok(g._resize_ok(Vector2(30, 30), Vector2(640, 360)) == false, "30x30 is degenerate")
	ok(g._resize_ok(Vector2(640, 30), Vector2(1152, 648)) == false, "collapsed height is degenerate")
	ok(g._resize_ok(Vector2(30, 648), Vector2(1152, 648)) == false, "collapsed width is degenerate")
	ok(g._resize_ok(Vector2(0, 0), Vector2(1152, 648)) == false, "zero size is degenerate")
	_drop(g)


func test_resize_ok_accepts_genuine_sizes() -> void:
	var g: Variant = _bare_game()
	var target := _win_ref()
	# viewport == OS window is sane by construction (no stretch configured) —
	# only the floor could reject, and any sane target clears it
	ok(g._resize_ok(target, Vector2(640, 360)) == true, "grow to the full OS window is accepted")
	# the QC case verbatim: 1152x648 -> 640x360 is a genuine shrink (a real
	# 1152x648 window accepts it through the ratio; the headless (0,0) report
	# has no trustworthy reference and degrades to the plain floor)
	ok(g._resize_ok(Vector2(640, 360), Vector2(1152, 648)) == true,
			"valid 1152x648 -> 640x360 shrink is accepted")
	# a genuine player shrink lands too: half the sane window, floor-clamped
	var half := Vector2(maxf(target.x * 0.5, 64.0), maxf(target.y * 0.5, 64.0))
	ok(g._resize_ok(half, target) == true, "shrink to half the sane window is accepted")
	# the ratio leg — only decidable when the window itself reports sane
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x >= 64 and win.y >= 64:
		ok(g._resize_ok(Vector2(win.x * 0.25, win.y), Vector2(1152.0, 648.0)) == false,
				"quarter-width viewport vs a sane window is the glitch, not a resize")
	_drop(g)


func test_resize_ok_boot_from_zero() -> void:
	var g: Variant = _bare_game()
	ok(g._resize_ok(Vector2(640, 360), Vector2(0, 0)) == true,
			"first resize from zero accepts a small playable window")
	ok(g._resize_ok(Vector2(1152, 648), Vector2(0, 0)) == true,
			"first resize from zero accepts the full window")
	ok(g._resize_ok(Vector2(30, 30), Vector2(0, 0)) == false,
			"first resize from zero still rejects sub-floor sizes")
	_drop(g)


# ---- the real _resize path -----------------------------------------------------
# The -s suite has NO live tree: SceneTree.root is itself treeless headless
# (root.get_tree() == null — probed), so get_viewport() is null for every test
# node and even a SubViewport child never enters the tree to become one. The
# accept/skip DECISIONS are therefore covered by the _resize_ok tests above;
# here the real _resize is called for the path smoke — with no viewport it
# must degrade to a clean no-op (latch untouched, no script error). The real
# viewport latch is exercised by every xvfb scene boot (e.g.
# tests/scenes/test_b4_vw.gd calls game._resize() on the live tree).

func test_resize_real_path_headless_noop() -> void:
	var g: Variant = _bare_game()
	g.vw = -1.0  # sentinel — proves _resize left the latch untouched
	g.vh = -1.0
	g.input.vw = -1.0
	g.input.vh = -1.0
	g._resize()  # treeless — must return cleanly, never error mid-body
	eq(g.vw, -1.0, "treeless _resize is a no-op (vw latch untouched)")
	eq(g.vh, -1.0, "treeless _resize is a no-op (vh latch untouched)")
	eq(g.input.vw, -1.0, "input mirror untouched by the treeless no-op (vw)")
	eq(g.input.vh, -1.0, "input mirror untouched by the treeless no-op (vh)")
	_drop(g)
