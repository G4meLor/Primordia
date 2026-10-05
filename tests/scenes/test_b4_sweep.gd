# QC r1 B4 seed sweep — the QC i18n probe ran start_new_game(0) with NO seed
# (random world each run) and hit a flat creature/tribe/space frame; fixed-seed
# reruns render fine. This scene sweeps random world seeds through a compressed
# creature-stage visit (real new-life → card → 1200 steps → shot) and reports
# flat frames with camera diagnostics. On flat: full canvas-bisect + cam/sim
# dump, then stops.
#
# Run (xvfb):
#   xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_b4_sweep.tscn
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const DriverScript := preload("res://tests/bots/bot_driver.gd")

const OUT := "user://b4_sweep"
const STEPS_PER_FRAME := 5
const VISIT_STEPS := 1200
const SWEEP_N := 24
const TIMEOUT_FRAMES := 60000

var game: Variant = null
var driver: Variant = null
var phase := "boot"
var frames := 0
var seed_i := 0
var visit_steps := 0
var flat_shots := 0
var bisect_queue: Array = []
var restoring: Array = []
var bisect_arm := 0
var flat_tag := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(1)
	var g: Variant = GameScript.new(ctx)
	add_child(g)
	g.set_process(false)
	g.loop.is_active_cb = func() -> bool: return false
	g.register(MenuStageScript.new(g))
	g.register(CellStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	g.register(TribeStageScript.new(g))
	g.start()
	return g


func _process(_dt: float) -> void:
	frames += 1
	if frames > TIMEOUT_FRAMES:
		printerr("B4_SWEEP_FAIL: timeout in phase %s" % phase)
		get_tree().quit(1)
		return
	match phase:
		"boot":
			game = _build_game()
			driver = DriverScript.new()
			phase = "new_life"
		"new_life":
			# the QC path: start_new_game with NO seed → random world
			game.current.start_new_game(0)
			print("B4_SWEEP seed_i=%d world=%d" % [seed_i, int(game.context.world.get("seed", -1)) if game.context.world != null and "seed" in game.context.world else -1])
			visit_steps = 0
			phase = "to_creature"
		"to_creature":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			if String(game.context.stage) != "cell":
				return
			game.go_to("creature", {"title": "THE LONG WALK", "sub": "sweep"})
			phase = "land"
		"land":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			if String(game.context.stage) != "creature":
				return
			phase = "visit"
		"visit":
			if frames % 30 == 0:
				driver.move_mouse(Vector2(640 + 300.0 * sin(frames * 0.013), 360 + 200.0 * cos(frames * 0.017)))
			if frames % 90 == 20:
				driver.mouse_down(Vector2(640 + 250.0 * sin(frames * 0.031), 360 + 180.0 * cos(frames * 0.023)))
			if frames % 90 == 55:
				driver.mouse_up()
			if frames % 240 == 120:
				driver.tap_key(KEY_SPACE)
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			game._do_render(0.0)
			visit_steps += STEPS_PER_FRAME
			if visit_steps >= VISIT_STEPS:
				var flat := _shot("creature_seed%d" % seed_i)
				_diag("seed%d" % seed_i)
				if flat:
					flat_shots += 1
					flat_tag = "seed%d" % seed_i
					print("B4_SWEEP FLAT at %s — bisecting" % flat_tag)
					bisect_queue = ["sky", "ground", "ents", "fx", "ui", "hud"]
					phase = "bisect"
					return
				_next_seed()
		"bisect":
			_bisect_frame()
		"done":
			pass


func _next_seed() -> void:
	seed_i += 1
	if seed_i >= SWEEP_N:
		print("B4_SWEEP_ALL_OK flats=%d" % flat_shots)
		get_tree().quit(0)
		return
	# fresh game per seed (the context/world cannot be reseeded in place)
	game.free()
	game = _build_game()
	driver = DriverScript.new()
	phase = "new_life"
	frames = 0


func _bisect_frame() -> void:
	if restoring.is_empty():
		if bisect_queue.is_empty():
			print("B4_SWEEP bisect done — flat_seed=%s" % flat_tag)
			get_tree().quit(0)
			return
		var layer: String = bisect_queue.pop_front()
		var node: Node2D = _layer_node(layer)
		if node != null:
			restoring.append(node)
			node.visible = false
		game._do_render(0.0)
		bisect_arm = 2
		return
	bisect_arm -= 1
	if bisect_arm == 0:
		var layer: String = String(restoring[0].get("layer"))
		_shot("bisect_%s_no_%s" % [flat_tag, layer])
		for node in restoring:
			node.visible = true
		restoring = []


func _layer_node(layer: String) -> Node2D:
	var st: Variant = game.current
	match layer:
		"sky": return st.sky_canvas
		"ground": return st.ground_canvas
		"ents": return st.ents_canvas
		"fx": return st.fx_canvas
		"ui": return st.ui_canvas
		"hud": return st.hud_canvas
	return null


func _shot(name_tag: String) -> bool:
	var img: Image = game.get_viewport().get_texture().get_image()
	if img == null:
		return false
	var p := "%s/%s.png" % [OUT, name_tag]
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


func _diag(tag: String) -> void:
	var ct: Transform2D = game.get_viewport().canvas_transform
	var c2d: Variant = game.cam.cam2d
	var xf: String = str(c2d.get_global_transform()) if c2d != null else "null"
	print("DIAG %s stage=%s canvas_t=%s cam2d_xf=%s finite=%s" % [tag, game.context.stage, str(ct), xf,
			str(ct.origin.x == ct.origin.x and ct.origin.y == ct.origin.y)])
	var sim: Variant = game.current.sim
	if sim != null and "px" in sim:
		print("DIAG %s px=%.3f pz=%.3f px_finite=%s ents=%d" % [tag, float(sim.px), float(sim.pz),
				str(float(sim.px) == float(sim.px)), sim.ents.size()])
