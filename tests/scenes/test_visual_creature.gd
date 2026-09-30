# Creature-painter pixel-assert scene (xvfb, Compatibility renderer) — task 6
# part B. No Game — the painter draws straight onto this Node2D at a NONZERO
# pose (the part-A origin probe could not see the double-transform class of
# bug). The fixture genome/pose are PINNED to match tools/visual_check_creature.py's
# python replica of the TS rig math (PX/PY 240/240, size 1.2, legs 4, hue 120,
# sat 0.55, spots+fur+tail, 2 eyes, herbivore; speed 0.5, t 3.0, gaitPhase 0) —
# change them together or the sample sites drift.
#
# Captures into user://visual_capture/ (phase machine as test_visual_cell.gd —
# the texture lags one frame, hence the arm/shot alternation):
#   creature_base.png   — the pinned fixture
#   creature_base2.png  — same state, a frame later (llvmpipe determinism twin)
#   creature_gait.png   — gaitPhase π/2 (feet move)
#   creature_angry.png  — mood angry (brow + pupil)
#   creature_dead.png   — mood dead (rotate)
#   creature_carn.png   — diet carnivore jaw 3 at size 2.2 (teeth — at the
#                         fixture's 1.2 they are sub-pixel, ~1.3px triangles)
#   creature_scales.png — coat scales (vs fur)
# Each variant FREES the caller-owned painter RIDs and clears the item before
# the next draw (the painter is stateless; sub-items would otherwise stack).
# Then runs tools/visual_check_creature.py via OS.execute and mirrors its exit
# code. No golden images — structural asserts only (see the checker).
# Run: tools/test_visual_creature.sh (one-command entry).
extends Node2D

const Painter := preload("res://src/gfx/creature_painter.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const OUT_DIR := "user://visual_capture"
const TIMEOUT_FRAMES := 1800

# variants after the base pair — overrides merged over the base genome/pose
var _variants := [
	{"name": "gait", "pose": {"gaitPhase": PI / 2.0}},
	{"name": "angry", "pose": {"mood": "angry"}},
	{"name": "dead", "pose": {"mood": "dead"}},
	{"name": "carn", "genome": {"diet": "carnivore", "jaw": 3, "size": 2.2}},
	{"name": "scales", "genome": {"coat": "scales"}},
]

var _phase := "draw_base"
var _frames := 0
var _vi := 0
var _rids: Array = []


# the checker's pinned fixture — size 1.2, legs 4, hue 120, spots + fur + tail,
# 2 eyes, herbivore (no teeth); everything else at the gene defaults
func _genome_base() -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.2
	g["legs"] = 4
	g["hue"] = 120
	g["sat"] = 0.55
	g["pattern"] = "spots"
	g["coat"] = "fur"
	g["tail"] = true
	g["arms"] = 0
	g["eyes"] = 2
	g["diet"] = "herbivore"
	g["jaw"] = 0
	g["spikes"] = 0
	g["horns"] = 0
	g["wings"] = 0
	return g


# pinned pose: x 240 y 240, facing right, walking at speed 0.5, gait 0
func _pose_base() -> Dictionary:
	return {
		"x": 240.0, "y": 240.0, "facing": 1, "speed": 0.5, "gaitPhase": 0.0,
		"attack": 0.0, "hurt": 0.0, "eat": 0.0, "airborne": 0.0,
		"mood": "idle", "scale": 1.0
	}


func _draw_variant(v: Dictionary) -> void:
	var g: Dictionary = _genome_base()
	g.merge(v.get("genome", {}), true)
	var p: Dictionary = _pose_base()
	p.merge(v.get("pose", {}), true)
	var res: Dictionary = Painter.draw_creature(self, g, p, {"t": 3.0})
	_rids = [res["clip_item"], res["pattern_item"], res["front_item"]]


# the two sub-items are CALLER-OWNED (painter header) — free them and wipe the
# item's own commands so the next variant starts from a clean canvas
func _free_rids() -> void:
	for rid in _rids:
		RenderingServer.free_rid(rid)
	_rids = []
	RenderingServer.canvas_item_clear(get_canvas_item())


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		printerr("VISUAL_TEST_FAIL: timeout in phase %s" % _phase)
		get_tree().quit(1)
		return
	match _phase:
		"draw_base":
			_draw_variant({})
			_phase = "arm_base"
		"arm_base":
			_phase = "shot_base"  # next frame's texture holds the drawn state
		"shot_base":
			_capture("creature_base.png")
			_phase = "arm_base2"
		"arm_base2":
			_phase = "shot_base2"  # determinism twin: same commands, one frame on
		"shot_base2":
			_capture("creature_base2.png")
			_free_rids()
			_phase = "draw_variant"
		"draw_variant":
			_draw_variant(_variants[_vi])
			_phase = "arm_variant"
		"arm_variant":
			_phase = "shot_variant"
		"shot_variant":
			var name: String = _variants[_vi]["name"]
			_capture("creature_%s.png" % name)
			_free_rids()
			_vi += 1
			_phase = "draw_variant" if _vi < _variants.size() else "check"
		"check":
			_phase = "done"
			_run_checker()


func _capture(file_name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("VISUAL_TEST_FAIL: save_png %s → %s" % [file_name, str(err)])
		get_tree().quit(1)
	else:
		print("captured %s/%s" % [OUT_DIR, file_name])


func _run_checker() -> void:
	var checker := ProjectSettings.globalize_path("res://tools/visual_check_creature.py")
	var args: Array = [checker]
	for f in ["creature_base", "creature_base2", "creature_gait", "creature_angry",
			"creature_dead", "creature_carn", "creature_scales"]:
		args.append(ProjectSettings.globalize_path(OUT_DIR + "/" + f + ".png"))
	var output: Array = []
	var code := OS.execute("python3", args, output, true)
	for line in output:
		print(String(line).strip_edges())
	if code != 0:
		printerr("VISUAL_TEST_FAIL: visual_check_creature.py exited %d" % code)
		get_tree().quit(1)
	else:
		print("VISUAL_TEST_OK")
		get_tree().quit(0)
