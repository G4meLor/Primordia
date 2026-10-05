# QC r1 B4 geometry probe — draws each suspected degenerate-geometry primitive
# ALONE on a cleared canvas under xvfb/llvmpipe and captures the frame. A
# variant whose draw poisons the rasterizer shows up as a flat clear-colored
# frame (the B4 signature: #4d4d4d = Godot's 0.3 default clear). Variants:
#
#   control   — a plain creature (well-formed reference)
#   glow      — pattern=glow (creature_painter._radial_disc self-touching strip)
#   wings     — wings=2 (wing_loop: duplicated tip vertex → zero-length segment)
#   snout     — carnivore jaw 3 (snout_loop: duplicated joints)
#   plates    — coat=plates (half-ellipse chord fill)
#   horns     — horns=4 (AA polyline horn curves)
#   closedisc — _closed_loop disc outline (duplicate seam point)
#   duppoly   — RAW add_polygon self-touching strip (the M6 pattern, RID)
#   dupaa     — RAW add_polyline AA with an exact duplicate consecutive point
#   degenquad — RAW add_polygon with a zero-area quad
#
# Run (xvfb):
#   xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_b4_geom.tscn
extends Node2D

const Painter := preload("res://src/gfx/creature_painter.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const OUT_DIR := "user://b4_geom"

var _variants := [
	{"name": "control", "genome": {}, "raw": ""},
	{"name": "glow", "genome": {"pattern": "glow"}, "raw": ""},
	{"name": "wings", "genome": {"wings": 2}, "raw": ""},
	{"name": "snout", "genome": {"diet": "carnivore", "jaw": 3}, "raw": ""},
	{"name": "plates", "genome": {"coat": "plates"}, "raw": ""},
	{"name": "horns", "genome": {"horns": 4}, "raw": ""},
	{"name": "wings_glow_all", "genome": {"wings": 2, "pattern": "glow",
			"diet": "carnivore", "jaw": 2, "coat": "plates", "horns": 4,
			"spikes": 6, "arms": 2, "eyes": 3, "tail": true}, "raw": ""},
	{"name": "duppoly", "genome": {}, "raw": "duppoly"},
	{"name": "dupaa", "genome": {}, "raw": "dupaa"},
	{"name": "degenquad", "genome": {}, "raw": "degenquad"},
]

var _phase := 0
var _frames := 0
var _rids: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _genome(extra: Dictionary) -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.4
	g["legs"] = 4
	g["hue"] = 120
	g["tail"] = true
	g.merge(extra, true)
	return g


func _pose() -> Dictionary:
	return {"x": 576.0, "y": 340.0, "facing": 1, "speed": 0.5, "gaitPhase": 0.0,
			"attack": 0.0, "hurt": 0.0, "eat": 0.0, "airborne": 0.0,
			"mood": "idle", "scale": 1.0}


# ---- raw degenerate primitives -------------------------------------------------

func _raw_duppoly() -> void:
	# the M6 self-touching annulus strip (one polygon, corners repeated)
	var ci := get_canvas_item()
	var c := Vector2(576, 324)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 36:
		var a0 := float(i) / 36.0 * TAU
		var a1 := float(i + 1) / 36.0 * TAU
		pts.append(c + Vector2(cos(a0), sin(a0)) * 60.0)
		pts.append(c + Vector2(cos(a1), sin(a1)) * 60.0)
		pts.append(c + Vector2(cos(a1), sin(a1)) * 140.0)
		pts.append(c + Vector2(cos(a0), sin(a0)) * 140.0)
		cols.append(Color(0.2, 0.8, 0.3))
		cols.append(Color(0.2, 0.8, 0.3))
		cols.append(Color(0.9, 0.3, 0.2))
		cols.append(Color(0.9, 0.3, 0.2))
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)


func _raw_dupaa() -> void:
	# an antialiased polyline with an EXACT duplicate consecutive point
	# (zero-length segment — the suspected NaN-vector source)
	var ci := get_canvas_item()
	var pts := PackedVector2Array([
		Vector2(376, 324), Vector2(476, 224), Vector2(576, 324),
		Vector2(576, 324),  # exact duplicate
		Vector2(676, 224), Vector2(776, 324),
	])
	RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([Color(0.2, 0.9, 0.4)]), 6.0, true)
	# and one with the duplicate FIRST (some guards only handle the seam)
	var pts2 := PackedVector2Array([
		Vector2(376, 380), Vector2(376, 380), Vector2(476, 420),
		Vector2(576, 380), Vector2(676, 420), Vector2(776, 380),
	])
	RenderingServer.canvas_item_add_polyline(ci, pts2, PackedColorArray([Color(0.9, 0.5, 0.2)]), 6.0, true)


func _raw_degenquad() -> void:
	# a zero-area quad + a collinear triangle
	var ci := get_canvas_item()
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([
		Vector2(476, 500), Vector2(676, 500), Vector2(676, 500), Vector2(476, 500),
	]), PackedColorArray([Color(0.8, 0.8, 0.1)]))
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([
		Vector2(376, 540), Vector2(576, 540), Vector2(776, 540),
	]), PackedColorArray([Color(0.8, 0.8, 0.1)]))


func _draw_variant(v: Dictionary) -> void:
	RenderingServer.canvas_item_clear(get_canvas_item())
	for rid in _rids:
		RenderingServer.free_rid(rid)
	_rids = []
	# a reference backdrop quad so "everything dropped" is distinguishable
	# from "only the variant dropped"
	RenderingServer.canvas_item_add_polygon(get_canvas_item(), PackedVector2Array([
		Vector2(0, 0), Vector2(1152, 0), Vector2(1152, 648), Vector2(0, 648),
	]), PackedColorArray([Color(0.05, 0.09, 0.18), Color(0.05, 0.09, 0.18),
		Color(0.02, 0.04, 0.10), Color(0.02, 0.04, 0.10)]))
	var raw := String(v["raw"])
	if raw == "duppoly":
		_raw_duppoly()
	elif raw == "dupaa":
		_raw_dupaa()
	elif raw == "degenquad":
		_raw_degenquad()
	else:
		var res: Dictionary = Painter.draw_creature(self, _genome(v["genome"]), _pose(), {"t": 3.0})
		_rids = [res["clip_item"], res["pattern_item"], res["front_item"]]


func _free_rids() -> void:
	for rid in _rids:
		RenderingServer.free_rid(rid)
	_rids = []


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > 2000:
		printerr("B4_GEOM_FAIL: timeout at variant %d" % _phase)
		get_tree().quit(1)
		return
	match _frames % 4:
		0:
			if _phase >= _variants.size():
				print("B4_GEOM_ALL_OK")
				get_tree().quit(0)
				return
			_draw_variant(_variants[_phase])
		2:
			var img: Image = get_viewport().get_texture().get_image()
			var name: String = _variants[_phase]["name"]
			img.save_png(OUT_DIR + "/geom_%s.png" % name)
			var counts := {}
			var samples := 0
			for y in range(0, img.get_height(), 8):
				for x in range(0, img.get_width(), 8):
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
			var flat := float(top_n) / float(samples) >= 0.9
			print("STAT %s flat=%s top=%s:%d/%d unique=%d" % [name, str(flat), top_key, top_n, samples, counts.size()])
			_free_rids()
			_phase += 1
