# QC round 1 B4 repro — creature/tribe stage renders as flat gray (#4a4a4a)
# under llvmpipe/xvfb while cell/civ/menu render fine. Bootstraps the REAL
# game (4 stages registered), plays the real cell→creature evolution card and
# the real founding → tribe handoff, and captures full-frame PNGs with pixel
# statistics printed to stdout (no PIL needed server-side):
#
#   cell.png            — the control (renders fine per QC)
#   creature_landed.png — 30 sim-steps after the card lands
#   creature_settled.png— +300 steps
#   creature_no_<layer>.png — the settled state with ONE canvas hidden
#                             (sky/ground/ents/fx/ui/hud) — a per-canvas
#                             bisect of whatever poisons the frame
#   tribe_landed.png / tribe_settled.png — the founding handoff captures
#
# Diagnostics per capture: viewport canvas_transform, the rig cam2d transform,
# player px/pz, and a genome-field census of the drawn ents (pattern/coat/
# wings/horns/arms counts) — printed as STAT lines.
# Run (xvfb):
#   xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_b4_repro.tscn
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")

const SEED := 0xB4B4
const DT := 1.0 / 60.0
const OUT_DIR := "user://b4_repro"
const TRANSITION_POLL := 900
const TIMEOUT_FRAMES := 14000

var _phase := "build"
var _frames := 0
var _game: Variant = null
var _done := false
var _bisect := []          # remaining canvases to hide in the bisect sweep
var _restoring: Array = [] # [node, ...] hidden during the current capture


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


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
			_game.current.start_new_game(0, "normal", SEED)
			_phase = "to_cell"
		"to_cell":
			_game.step_for_testing(1, DT)
			if _game.context.stage != "cell":
				return
			_game.step_for_testing(168, DT)  # arrival card + entry
			_phase = "settle_invuln"
		"settle_invuln":
			var sim: Variant = _game.current.sim
			if float(sim.invuln) > 0.0:
				_game.step_for_testing(2, DT)
				return
			_game._do_render(0.0)
			_phase = "cell_arm"
		"cell_arm":
			_phase = "cell_shot"
		"cell_shot":
			if _capture("cell.png"):
				_diag("cell")
				_phase = "creature_card"
		"creature_card":
			# the REAL evolution card the shore button fires (cell_stage.gd:646)
			_game.go_to("creature", {"title": "THE LONG WALK", "sub": "b4 repro"})
			_game.step_for_testing(1, DT)
			_phase = "creature_land"
		"creature_land":
			_game.step_for_testing(1, DT)
			if _game.context.stage != "creature":
				return
			_game.step_for_testing(30, DT)
			_game._do_render(0.0)
			_phase = "creature_landed_arm"
		"creature_landed_arm":
			_phase = "creature_landed_shot"
		"creature_landed_shot":
			if _capture("creature_landed.png"):
				_diag("creature_landed")
				_phase = "creature_settle"
		"creature_settle":
			_game.step_for_testing(300, DT)
			_game._do_render(0.0)
			_phase = "creature_settled_arm"
		"creature_settled_arm":
			_phase = "creature_settled_shot"
		"creature_settled_shot":
			if _capture("creature_settled.png"):
				_diag("creature_settled")
				_bisect = ["sky", "ground", "ents", "fx", "ui", "hud"]
				_phase = "bisect_hide"
		"bisect_hide":
			if _bisect.is_empty():
				_phase = "found_tribe"
				return
			var layer: String = _bisect.pop_front()
			var node: Node2D = _layer_node(layer)
			if node != null:
				_restoring.append(node)
				node.visible = false
			_game._do_render(0.0)
			_phase = "bisect_arm"
		"bisect_arm":
			_phase = "bisect_shot"
		"bisect_shot":
			var layer: String = String(_restoring[0].get("layer")) if _restoring.size() > 0 \
					and "layer" in _restoring[0] else "layer"
			if _capture("creature_no_%s.png" % layer):
				_phase = "bisect_restore"
		"bisect_restore":
			for node in _restoring:
				node.visible = true
			_restoring = []
			_phase = "bisect_hide"
		"found_tribe":
			var csim: Variant = _game.current.sim
			csim.debug_grant(999.0, 3)
			csim.debug_spawn_pack(2)
			_game.step_for_testing(3, DT)
			csim.found_tribe()
			_game.step_for_testing(1, DT)
			_phase = "tribe_land"
		"tribe_land":
			_game.step_for_testing(1, DT)
			if _game.context.stage != "tribe":
				return
			_game.step_for_testing(30, DT)
			_game._do_render(0.0)
			_phase = "tribe_landed_arm"
		"tribe_landed_arm":
			_phase = "tribe_landed_shot"
		"tribe_landed_shot":
			if _capture("tribe_landed.png"):
				_diag("tribe_landed")
				_phase = "tribe_settle"
		"tribe_settle":
			_game.step_for_testing(300, DT)
			_game._do_render(0.0)
			_phase = "tribe_settled_arm"
		"tribe_settled_arm":
			_phase = "tribe_settled_shot"
		"tribe_settled_shot":
			if _capture("tribe_settled.png"):
				_diag("tribe_settled")
				_phase = "check"
		"check":
			_done = true
			print("B4_REPRO_ALL_OK")
			get_tree().quit(0)


# ---- helpers -------------------------------------------------------------------

func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.register(CreatureStageScript.new(game))
	game.register(TribeStageScript.new(game))
	game.start()
	return game


func _layer_node(layer: String) -> Node2D:
	var st: Variant = _game.current
	match layer:
		"sky": return st.sky_canvas
		"ground": return st.ground_canvas
		"ents": return st.ents_canvas
		"fx": return st.fx_canvas
		"ui": return st.ui_canvas
		"hud": return st.hud_canvas
	return null


## Full-frame capture + pixel statistics. Returns true on success.
func _capture(file_name: String) -> bool:
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		_fail("save_png %s → %s" % [file_name, str(err)])
		return false
	var w := img.get_width()
	var h := img.get_height()
	var counts := {}
	var lmin := 1.0
	var lmax := 0.0
	var samples := 0
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			var c := img.get_pixel(x, y)
			var key := "%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]
			counts[key] = int(counts.get(key, 0)) + 1
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lmin = minf(lmin, l)
			lmax = maxf(lmax, l)
			samples += 1
	var pairs := []
	for k in counts:
		pairs.append([k, counts[k]])
	pairs.sort_custom(func(a, b) -> bool: return a[1] > b[1])
	var top := ""
	for i in mini(5, pairs.size()):
		top += "%s:%d " % [pairs[i][0], pairs[i][1]]
	print("STAT %s samples=%d unique=%d lum=[%.3f..%.3f] top=[%s] px=%dx%d" % [
			file_name, samples, counts.size(), lmin, lmax, top, w, h])
	# the 5x5 grid means the task brief asks for
	var grid := ""
	for gy in 5:
		for gx in 5:
			var cx := (gx + 1) * w / 6
			var cy := (gy + 1) * h / 6
			var acc := Color(0, 0, 0)
			for oy in range(-4, 5, 2):
				for ox in range(-4, 5, 2):
					acc += img.get_pixel(clampi(cx + ox, 0, w - 1), clampi(cy + oy, 0, h - 1))
			acc *= 1.0 / 25.0
			grid += "%02x%02x%02x " % [roundi(acc.r * 255.0), roundi(acc.g * 255.0), roundi(acc.b * 255.0)]
		grid += "| "
	print("GRID %s %s" % [file_name, grid])
	return true


## Camera / sim / genome-census diagnostics — prints as DIAG lines.
func _diag(tag: String) -> void:
	var st: Variant = _game.current
	var ct: Transform2D = get_viewport().canvas_transform
	var c2d: Variant = _game.cam.cam2d
	var cpos: String = str(c2d.get_global_transform().origin) if c2d != null else "null"
	var cam_enabled: String = str(c2d.enabled) if c2d != null else "null"
	print("DIAG %s stage=%s canvas_t=[%s] cam2d=%s enabled=%s zoom=%.4f" % [
			tag, _game.context.stage, str(ct), cpos, cam_enabled, float(_game.cam.zoom)])
	var sim: Variant = st.sim
	if sim != null and "px" in sim:
		print("DIAG %s player px=%.3f pz=%.3f ents=%d" % [tag, float(sim.px), float(sim.pz), sim.ents.size()])
		var census := {}
		for e in sim.ents:
			if e.has("corpseT"):
				continue
			var g: Dictionary = e.get("genome", {})
			for k in ["pattern", "coat", "wings", "horns", "arms", "eyes", "tail"]:
				var key := "%s=%s" % [k, str(g.get(k, "-"))]
				census[key] = int(census.get(key, 0)) + 1
		var parts := PackedStringArray()
		for k in census:
			parts.append("%s x%d" % [k, census[k]])
		print("DIAG %s census: %s" % [tag, " | ".join(parts)])


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("B4_REPRO_FAIL: " + msg)
	get_tree().quit(1)
