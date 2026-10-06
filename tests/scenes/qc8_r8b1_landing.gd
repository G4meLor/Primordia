# QC round 8 batch1 P1 — space-landing pixel probe (gray-band reproduction).
# Two landing routes, the SAME grabbing + marker instrumentation:
#   mode "direct" (QC8_MODE=direct)  — menu → start_new_game → cell card →
#       switch_stage("space") (the qc5 bot_space landfall pattern)
#   mode "civ" (QC8_MODE=civ)        — real civ landing → debug_set_influence
#       flip-all (documented seam, civ_sim.gd:791-803 bot_civ precedent) →
#       victory → go_to("space", THE BLACK OCEAN) → landing through the REAL
#       transition card
# After the transition clears: two PROBE-ONLY marker canvases are appended as
# the last space-stage children (drawn on top of everything, zero game-code
# edits):
#   ScreenMark — draws with _screen_inv(): red border at (0,0,vw,vh) + corner
#       squares (red TL / yellow TR / green BL / blue BR). If the border does
#       NOT hug the screen edges, the canvas transform at draw-record differs
#       from render-time (the stale-transform class).
#   WorldMark  — identity transform: magenta cross at world (0,0) (the sun),
#       cyan cross at the ship position.
# Grabs (law MN-8): save_png BEFORE any assert, at T+10 after the transition
# clears (arrival) and T+310 (idle 5s). Self-analysis prints the gray-band
# fraction + the sharp-edge rows at 3 columns. The probe always exits 0 —
# the verdict is read from the printed QC8R8 lines, not asserted here.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const TIMEOUT_FRAMES := 40000
const DT := 1.0 / 60.0
const WORLD_SEED := 48879
const CIV_SEED := 20261007

var _mode := "direct"
var _phase := "build"
var _frames := 0
var _game: Variant = null
var _leg_f := 0
var _marked := false
var _grabbed := {}
var _run_tag := ""

class ScreenMark extends Node2D:
	var game: Variant = null
	func _draw() -> void:
		if game == null:
			return
		var vp := get_viewport()
		if vp == null:
			return
		draw_set_transform_matrix(vp.canvas_transform.affine_inverse())
		var vw: float = game.vw
		var vh: float = game.vh
		draw_rect(Rect2(0, 0, vw, vh), Color(1, 0, 0, 1), false, 6.0)
		draw_rect(Rect2(0, 0, 40, 40), Color(1, 0, 0, 1), true)
		draw_rect(Rect2(vw - 40.0, 0, 40, 40), Color(1, 1, 0, 1), true)
		draw_rect(Rect2(0, vh - 40.0, 40, 40), Color(0, 1, 0, 1), true)
		draw_rect(Rect2(vw - 40.0, vh - 40.0, 40, 40), Color(0, 0, 1, 1), true)

class WorldMark extends Node2D:
	var game: Variant = null
	func _draw() -> void:
		if game == null:
			return
		var sim: Variant = game.stages.get("space", null)
		if sim == null or sim.sim == null:
			return
		var ship := Vector2(float(sim.sim.sx), float(sim.sim.sy))
		draw_line(Vector2(-30, 0), Vector2(30, 0), Color(1, 0, 1, 1), 6.0)
		draw_line(Vector2(0, -30), Vector2(0, 30), Color(1, 0, 1, 1), 6.0)
		draw_line(ship + Vector2(-40, 0), ship + Vector2(40, 0), Color(0, 1, 1, 1), 6.0)
		draw_line(ship + Vector2(0, -40), ship + Vector2(0, 40), Color(0, 1, 1, 1), 6.0)


func _ready() -> void:
	_mode = OS.get_environment("QC8_MODE")
	if _mode == "":
		_mode = "direct"
	_run_tag = OS.get_environment("QC8_TAG")
	if _run_tag == "":
		_run_tag = "run0"
	print("QC8R8 BOOT mode=%s tag=%s" % [_mode, _run_tag])
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("qc8r8b1"):
		dir.make_dir("qc8r8b1")


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		print("QC8R8 TIMEOUT mode=%s phase=%s" % [_mode, _phase])
		_analyze("timeout")
		get_tree().quit(1)
		return
	match _phase:
		"build":
			_game = _build_game()
			if _mode == "direct":
				_game.stages["menu"].start_new_game(0, "normal", WORLD_SEED)
				_phase = "card"
			else:
				_game.switch_stage("civ")
				_phase = "civ_boot"
		"card":
			_game.step_for_testing(1, DT)
			if _game.transition == null:
				_game.switch_stage("space")
				_phase = "land_wait"
				_leg_f = 0
		"civ_boot":
			_game.step_for_testing(1, DT)
			_leg_f += 1
			if _leg_f >= 120:
				_phase = "civ_flip"
				_leg_f = 0
		"civ_flip":
			_game.step_for_testing(1, DT)
			_leg_f += 1
			var sim: Variant = _game.stages["civ"].sim
			var won: bool = sim != null and bool(sim.victoryFired)
			if sim != null and not won and _leg_f == 2:
				for j in sim.cities.size():
					if String(sim.cities[j]["owner"]) != "you":
						sim.debug_set_influence(j, 100.0)
				print("QC8R8 CIV granted all unowned -> 100")
			if won:
				print("QC8R8 CIV victory fired (t=%s)" % str(sim.time))
				_phase = "land_wait"
				_leg_f = 0
			elif _leg_f > 60 * 30:
				print("QC8R8 CIV no victory — board %s" % _board(sim))
				_analyze("novictory")
				get_tree().quit(1)
		"land_wait":
			_game.step_for_testing(1, DT)
			_leg_f += 1
			var landed: bool = _game.context.stage == "space" \
					and _game.stages["space"].sim != null \
					and (_game.transition == null or _game.transition.is_empty())
			if landed and _leg_f > 5:
				_install_marks()
				_phase = "space"
				_leg_f = 0
				print("QC8R8 LANDED t=%s" % str(_game.context.playtime))
		"space":
			_game.step_for_testing(1, DT)
			_leg_f += 1
			if not _grabbed.has("arrival") and _leg_f >= 10:
				_grabbed["arrival"] = true
				_dump("arrival")
				_analyze("arrival")
			if _leg_f == 310:
				_dump("idle")
				_analyze("idle")
				print("QC8R8 DONE mode=%s tag=%s" % [_mode, _run_tag])
				get_tree().quit(0)


func _board(sim: Variant) -> String:
	var out: Array = []
	for c in sim.cities:
		out.append("%s=%s@%s" % [String(c["name"]), String(c["owner"]),
			str(snappedf(float(c["influence"]), 0.1))])
	return " ".join(out)


func _install_marks() -> void:
	if _marked:
		return
	_marked = true
	var space: Variant = _game.stages["space"]
	var sm := ScreenMark.new()
	sm.name = "ProbeScreenMark"
	sm.game = _game
	space.add_child(sm)
	var wm := WorldMark.new()
	wm.name = "ProbeWorldMark"
	wm.game = _game
	space.add_child(wm)
	print("QC8R8 MARKS installed")


func _dump(tag: String) -> void:
	var vp: Variant = _game.get_viewport()
	print("QC8R8 DUMP[%s] win=%dx%d vp=%dx%d cam=x%s y%s z%s" % [tag,
		DisplayServer.window_get_size().x, DisplayServer.window_get_size().y,
		vp.get_visible_rect().size.x, vp.get_visible_rect().size.y,
		str(_game.cam.x), str(_game.cam.y), str(_game.cam.zoom)])
	print("QC8R8 DUMP[%s] canvas_tf=%s" % [tag, str(vp.canvas_transform)])
	var space: Variant = _game.stages["space"]
	for ch in space.get_children():
		var vis: String = "?"
		if ch is CanvasItem:
			vis = str(ch.visible)
		print("  - %s (%s) visible=%s" % [String(ch.name), ch.get_class(), vis])
	var sim: Variant = space.sim
	print("QC8R8 DUMP[%s] planets=%d ship=(%s,%s) hud=%s" % [tag,
		sim.planets.size(), str(sim.sx), str(sim.sy), str(space.hud_inst != null)])


func _analyze(tag: String) -> void:
	var img: Image = _game.get_viewport().get_texture().get_image()
	if img == null:
		print("QC8R8 ANALYZE[%s] no image" % tag)
		return
	var path := "user://qc8r8b1/%s_%s.png" % [_run_tag, tag]
	img.save_png(path)
	var w := img.get_width()
	var h := img.get_height()
	var gray := 0
	var total := 0
	for y in range(0, h, 2):
		for x in range(0, w, 4):
			total += 1
			var p := img.get_pixel(x, y)
			if absf(p.r - 0.302) < 0.025 and absf(p.g - 0.302) < 0.025 \
					and absf(p.b - 0.302) < 0.025:
				gray += 1
	print("QC8R8 GRAYFRAC[%s] gray=%d/%d frac=%.3f size=%dx%d" % [tag, gray, total,
		float(gray) / float(maxf(1.0, float(total))), w, h])
	for xcol in [100, 576, 1050]:
		var found := false
		for y in range(1, h):
			var a := img.get_pixel(xcol, y - 1)
			var b := img.get_pixel(xcol, y)
			if a.r - b.r > 0.12:
				print("QC8R8 EDGE[%s] x=%d y=%d %.0f,%.0f,%.0f -> %.0f,%.0f,%.0f" % [
					tag, xcol, y, a.r * 255.0, a.g * 255.0, a.b * 255.0,
					b.r * 255.0, b.g * 255.0, b.b * 255.0])
				found = true
				break
		if not found:
			print("QC8R8 EDGE[%s] x=%d none" % [tag, xcol])


func _build_game() -> Variant:
	var seed_v := WORLD_SEED if _mode == "direct" else CIV_SEED
	var ctx: Variant = ContextScript.new(seed_v)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.register(CreatureStageScript.new(game))
	game.register(TribeStageScript.new(game))
	game.register(CivStageScript.new(game))
	game.register(SpaceStageScript.new(game))
	game.start()
	return game
