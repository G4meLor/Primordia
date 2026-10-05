# QC r1 B4 death repro — the QC i18n ride's flat frames correlated with the
# creature-stage player deaths (toast "Bạn đã chết" at the first flat shot).
# This scene forces the death through the documented seam (sim.php = 0, the
# visual-suite pattern) shortly after the creature card lands, and captures
# PNGs + camera diagnostics on a fine grid around the death to catch the
# exact frame the render goes clear-colored.
#
# Run (xvfb):
#   xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_b4_death.tscn
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const DriverScript := preload("res://tests/bots/bot_driver.gd")

const OUT := "user://b4_death"
const STEPS_PER_FRAME := 5
const TIMEOUT_FRAMES := 30000

var game: Variant = null
var driver: Variant = null
var phase := "boot"
var frames := 0
var visit_steps := 0
var shot_i := 0
var death_at := 600       # visit-step when php is forced to 0
var killed := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(0xBEEF)
	var g: Variant = GameScript.new(ctx)
	add_child(g)
	g.set_process(false)
	g.loop.is_active_cb = func() -> bool: return false
	g.register(MenuStageScript.new(g))
	g.register(CellStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	g.register(TribeStageScript.new(g))
	g.register(CivStageScript.new(g))
	g.register(SpaceStageScript.new(g))
	g.start()
	return g


func _process(_dt: float) -> void:
	frames += 1
	if frames > TIMEOUT_FRAMES:
		printerr("B4_DEATH_FAIL: timeout in phase %s" % phase)
		get_tree().quit(1)
		return
	match phase:
		"boot":
			game = _build_game()
			driver = DriverScript.new()
			game.i18n.set_lang("vi")
			game.current.start_new_game(0)
			phase = "to_cell"
		"to_cell":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			if String(game.context.stage) != "cell":
				return
			game.go_to("creature", {"title": "THE LONG WALK", "sub": "b4 death repro"})
			phase = "land"
		"land":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			if String(game.context.stage) != "creature":
				return
			phase = "visit"
		"visit":
			if frames % 30 == 0:
				driver.move_mouse(Vector2(640 + 300.0 * sin(frames * 0.013), 360 + 200.0 * cos(frames * 0.017)))
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			game._do_render(0.0)
			visit_steps += STEPS_PER_FRAME
			# fine captures around the forced death
			if visit_steps >= death_at - 60 and visit_steps % 30 == 0 or visit_steps == death_at:
				if not killed and visit_steps >= death_at:
					var sim: Variant = game.current.sim
					sim.php = 0.0
					killed = true
					print("B4_DEATH forced php=0 at visit_step=%d" % visit_steps)
				var flat := _shot("d%d" % visit_steps)
				_diag(visit_steps, flat)
			if visit_steps >= death_at + 600:
				print("B4_DEATH ride done flats=%d" % shot_i)
				get_tree().quit(0)


func _shot(name_tag: String) -> bool:
	var img: Image = game.get_viewport().get_texture().get_image()
	if img == null:
		return false
	var p := "%s/%02d_%s.png" % [OUT, shot_i, name_tag]
	shot_i += 1
	img.save_png(p)
	var w := img.get_width()
	var h := img.get_height()
	var counts := {}
	var samples := 0
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			var c := img.get_pixel(x, y)
			var key := "%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]
			counts[key] = int(counts.get(key, 0)) + 1
			samples += 1
	var top_key := ""
	var top_n := 0
	for k in counts:
		if counts[k] > top_n:
			top_n = counts[k]
			top_key = k
	var flat := samples > 0 and float(top_n) / float(samples) >= 0.9
	print("STAT %s flat=%s top=%s:%d/%d unique=%d" % [name_tag, str(flat), top_key, top_n, samples, counts.size()])
	return flat


func _diag(step: int, flat: bool) -> void:
	var cam: Variant = game.cam
	var c2d: Variant = cam.cam2d
	var ct: Transform2D = game.get_viewport().canvas_transform
	var ct_finite: bool = is_finite(ct.origin.x) and is_finite(ct.origin.y) \
			and is_finite(ct.x.x) and is_finite(ct.y.y)
	print("DIAG step=%d flat=%s cam(x=%.2f y=%.2f zoom=%.4f off=%.2f,%.2f) cam2d_pos=%s ct_ok=%s ct=%s" % [
			step, str(flat), float(cam.x), float(cam.y), float(cam.zoom),
			float(cam.shake_x), float(cam.shake_y),
			str(c2d.position) if c2d != null else "null", str(ct_finite), str(ct)])
	var sim: Variant = game.current.sim
	if sim != null and "px" in sim:
		print("DIAG step=%d px=%.2f pz=%.2f php=%.1f deathFade=%.2f ents=%d visible=%s" % [
				step, float(sim.px), float(sim.pz), float(sim.php), float(sim.deathFade),
				sim.ents.size(), _vis_flags()])


func _vis_flags() -> String:
	var st: Variant = game.current
	var out := PackedStringArray()
	for node in st.get_children():
		if node is CanvasItem:
			out.append("%s=%s" % [String(node.name).substr(0, 4), str(node.visible)])
	return " ".join(out)
