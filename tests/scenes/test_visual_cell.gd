# Visual pixel-assert scene (xvfb, Compatibility renderer) — task 7 AC.
# Boots a REAL Game with a pinned world seed + pinned player genome (size 1.0,
# hue 120, spots, flagella 2, jaw 1), enters the cell stage, waits for the
# arrival invuln to decay (the player must paint at alpha 1 — the blink
# windows are time-dependent), captures two frames via
# get_viewport().get_texture().get_image():
#   cell_calm.png  — chaos at its fresh-save value (0.15)
#   cell_chaos.png — chaos forced to 0.8 with the sim FROZEN (same sim time →
#                    the corner delta is pure chaos tint)
# saves them to user://visual_capture/, then runs tools/visual_check.py (PIL)
# via OS.execute and mirrors its exit code. No golden images — the asserts are
# structural (see the checker). Prints the capture paths.
# Run: tools/test_visual.sh (one-command entry).
extends Node

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const SEED := 20260929
const OUT_DIR := "user://visual_capture"
const TIMEOUT_FRAMES := 1800

var game: Variant = null
var _phase := "boot"
var _frames := 0


func _ready() -> void:
	var ctx: Variant = ContextScript.new(SEED)
	# pinned player genome (brief): size 1.0, hue 120, spots, flagella 2, jaw 1
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.0
	g["hue"] = 120
	g["sat"] = 0.55
	g["pattern"] = "spots"
	g["flagella"] = 2
	g["jaw"] = 1
	ctx.genome = g
	game = GameScript.new(ctx)
	add_child(game)
	game.register(CellStageScript.new(game))
	game.switch_stage("cell")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		printerr("VISUAL_TEST_FAIL: timeout in phase %s (sim.invuln=%s)" % [
			_phase, str(game.current.sim.invuln) if game.current != null and game.current.sim != null else "?"])
		get_tree().quit(1)
		return
	match _phase:
		"boot":
			# settle until the arrival invuln decays → the player paints at
			# alpha 1 regardless of the blink phase; the fixed-step loop
			# accrues real frames, so this is condition-based (deterministic
			# per seed up to one step).
			var st: Variant = game.current.sim if game.current != null else null
			if st != null and st.invuln <= 0.0:
				_phase = "calm_arm"
		"calm_arm":
			_phase = "calm_shot"  # next frame's texture holds the drawn state
		"calm_shot":
			_capture("cell_calm.png")
			print("captured %s/cell_calm.png" % OUT_DIR)
			# chaos-tint capture: force 0.8 and FREEZE the sim (no step → the
			# two captures share sim time; only the tint differs)
			game.context.chaos = 0.8
			game.current.frozen = true
			_phase = "chaos_arm"
		"chaos_arm":
			_phase = "chaos_shot"
		"chaos_shot":
			_capture("cell_chaos.png")
			print("captured %s/cell_chaos.png" % OUT_DIR)
			# glitch-overlay presence capture: force the overlay on for the
			# same frozen frame (render() re-derives visibility per frame, so
			# the stage exposes a forced flag — the chaos gate stays off; this
			# exercises the difference-composite path the event would drive)
			game.current.glitch_forced = true
			_phase = "glitch_arm"
		"glitch_arm":
			_phase = "glitch_shot"
		"glitch_shot":
			_capture("cell_glitch.png")
			print("captured %s/cell_glitch.png" % OUT_DIR)
			game.current.glitch_forced = false
			_phase = "check"
		"check":
			_phase = "done"
			_run_checker()


func _capture(file_name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("VISUAL_TEST_FAIL: save_png %s → %s" % [file_name, str(err)])
		get_tree().quit(1)


func _run_checker() -> void:
	var checker := ProjectSettings.globalize_path("res://tools/visual_check.py")
	var png1 := ProjectSettings.globalize_path(OUT_DIR + "/cell_calm.png")
	var png2 := ProjectSettings.globalize_path(OUT_DIR + "/cell_chaos.png")
	var png3 := ProjectSettings.globalize_path(OUT_DIR + "/cell_glitch.png")
	var output: Array = []
	var code := OS.execute("python3", [checker, png1, png2, png3], output, true)
	for line in output:
		print(String(line).strip_edges())
	if code != 0:
		printerr("VISUAL_TEST_FAIL: visual_check.py exited %d" % code)
		get_tree().quit(1)
	else:
		print("VISUAL_TEST_OK")
		get_tree().quit(0)
