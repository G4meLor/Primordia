# QC round 1 B4 repro #2 — mimics the QC i18n playtest flow exactly (the run
# that produced the flat #4a4a4a creature/tribe captures): real-input legs at
# the QC cadence, 5 sim steps per render frame, the QC seed, ~110 s per stage,
# go_to jumps with the real landfall card. When a capture comes back FLAT
# (top color ≥ 90% of samples), the scene freezes the state and runs the
# per-canvas bisect + diagnostics (camera transform, ent genome census,
# dayPhase/chaos) before quitting.
#
# Run (xvfb):
#   xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_b4_repro2.tscn
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const DriverScript := preload("res://tests/bots/bot_driver.gd")

const OUT := "user://b4_repro2"
const SEED := 0xBEEF
const STEPS_PER_FRAME := 5
const SHOT_EVERY := 110          # _process frames between shots
const STAGE_STEPS := 6600
const TIMEOUT_FRAMES := 16000

var game: Variant = null
var driver: Variant = null
var phase := "boot"
var frames := 0
var steps_in_stage := 0
var shot_n := 0
var stage_i := 0
var stages_plan := ["cell", "creature", "tribe"]
var flat_seen := 0
var bisect_queue: Array = []
var restoring: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
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
		printerr("B4_REPRO2_FAIL: timeout in phase %s" % phase)
		get_tree().quit(1)
		return
	match phase:
		"boot":
			game = _build_game()
			driver = DriverScript.new()
			game.i18n.set_lang("vi")
			phase = "ride"
			frames = 0
		"ride":
			_ride_frame()
		"bisect":
			_bisect_frame()
		"done":
			pass


# the QC playtest's exact input cadence (qc_i18n_play.gd _ride_frame)
func _qc_input() -> void:
	if frames % 30 == 0:
		driver.move_mouse(Vector2(640 + 300.0 * sin(frames * 0.013), 360 + 200.0 * cos(frames * 0.017)))
	if frames % 90 == 20:
		driver.mouse_down(Vector2(640 + 250.0 * sin(frames * 0.031), 360 + 180.0 * cos(frames * 0.023)))
	if frames % 90 == 55:
		driver.mouse_up()
	if frames % 240 == 120:
		driver.tap_key(KEY_SPACE)
	if frames % 300 == 200:
		driver.tap_key(KEY_1)
	if frames % 360 == 300:
		driver.tap_key(KEY_2)


func _ride_frame() -> void:
	var st := String(game.context.stage)
	_qc_input()
	game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
	game._do_render(0.0)
	steps_in_stage += STEPS_PER_FRAME
	if frames % SHOT_EVERY == 0:
		var flat := _shot("live_%s" % st)
		_diag("live_%s_%d" % [st, shot_n])
		if flat:
			flat_seen += 1
			if flat_seen >= 1 and st != "cell":
				print("B4_REPRO2 FLAT confirmed in %s — entering bisect" % st)
				_enter_bisect()
				return
	if steps_in_stage >= STAGE_STEPS:
		stage_i += 1
		if stage_i >= stages_plan.size():
			print("B4_REPRO2_ALL_OK")
			get_tree().quit(0)
			return
		var nxt: String = stages_plan[stage_i]
		var card: Variant = null
		if nxt == "creature":
			card = {"title": "THE LONG WALK",
					"sub": "400 million years of ambition, one nervous step onto land"}
		print("B4_REPRO2 GO_TO ", nxt)
		game.go_to(nxt, card)
		steps_in_stage = 0
		frames = 0


# ---- flat-state bisect ---------------------------------------------------------

func _enter_bisect() -> void:
	# stop the input cadence; freeze sim stepping (render-only from here)
	bisect_queue = ["sky", "ground", "ents", "fx", "ui", "hud"]
	phase = "bisect"
	frames = 0


func _bisect_frame() -> void:
	if restoring.is_empty():
		if bisect_queue.is_empty():
			print("B4_REPRO2 bisect done")
			get_tree().quit(0)
			return
		var layer: String = bisect_queue.pop_front()
		var node: Node2D = _layer_node(layer)
		if node != null:
			restoring.append(node)
			node.visible = false
		game._do_render(0.0)
		_bisect_arm = 2
		return
	_bisect_arm -= 1
	if _bisect_arm == 0:
		var layer: String = String(restoring[0].get("layer"))
		_shot("bisect_no_%s" % layer)
		_diag("bisect_no_%s" % layer)
		for node in restoring:
			node.visible = true
		restoring = []


var _bisect_arm := 0


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


# ---- capture + diagnostics -----------------------------------------------------

## Full-frame capture + stats. Returns true when the frame is FLAT
## (top color ≥ 90% of the sampled pixels).
func _shot(name_tag: String) -> bool:
	var img: Image = game.get_viewport().get_texture().get_image()
	if img == null:
		printerr("B4_REPRO2_FAIL: null image for %s" % name_tag)
		get_tree().quit(1)
		return false
	var p := "%s/%02d_%s.png" % [OUT, shot_n, name_tag]
	shot_n += 1
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
	var st: Variant = game.current
	var ct: Transform2D = game.get_viewport().canvas_transform
	var c2d: Variant = game.cam.cam2d
	var cpos: String = str(c2d.get_global_transform()) if c2d != null else "null"
	print("DIAG %s stage=%s canvas_t=%s cam2d_xf=%s" % [tag, game.context.stage, str(ct), cpos])
	var sim: Variant = st.sim
	if sim != null and "px" in sim:
		var night: String = str(sim.is_night()) if sim.has_method("is_night") else "-"
		var dp: float = float(sim.get("dayPhase")) if "dayPhase" in sim else -1.0
		print("DIAG %s px=%.3f pz=%.3f ents=%d dayPhase=%.3f night=%s chaos=%.3f" % [
				tag, float(sim.px), float(sim.pz), sim.ents.size(), dp, night, float(game.context.chaos)])
		var census := {}
		for e in sim.ents:
			if e.has("corpseT"):
				continue
			var g: Dictionary = e.get("genome", {})
			var key := "pat=%s coat=%s w=%s h=%s legs=%s" % [str(g.get("pattern", "-")), str(g.get("coat", "-")),
					str(g.get("wings", "-")), str(g.get("horns", "-")), str(g.get("legs", "-"))]
			census[key] = int(census.get(key, 0)) + 1
		var parts := PackedStringArray()
		for k in census:
			parts.append("%s x%d" % [k, census[k]])
		print("DIAG %s census: %s" % [tag, " | ".join(parts)])
