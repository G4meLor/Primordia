## Creature painter headless smoke — task 6 PART A. No pixel asserts here (the
## xvfb pixel suite is part B): the draw path must complete without script
## errors on a bare offscreen CanvasItem, the Ruling 11 clip sub-items (clip,
## pattern, front — the part B back/front split) must come back wired (valid
## RIDs, fresh per call, caller-freeable), a second
## creature with a different genome/pose must draw on the same item, and the
## T1 rig must be consumed verbatim (returned spine ≡ creature_rig.spine_points).
extends "res://tests/test_base.gd"

const Painter := preload("res://src/gfx/creature_painter.gd")
const RigScript := preload("res://src/gfx/creature_rig.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

# part B's pixel fixture base: size 1.2, legs 4, hue 120, fur + spots — plus
# tail/arms/horns/spikes/carnivore jaw so the smoke exercises most draw blocks
func _genome_a() -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.2
	g["legs"] = 4
	g["hue"] = 120
	g["sat"] = 0.55
	g["pattern"] = "spots"
	g["coat"] = "fur"
	g["tail"] = true
	g["arms"] = 2
	g["eyes"] = 2
	g["diet"] = "carnivore"
	g["jaw"] = 3
	g["spikes"] = 3
	g["horns"] = 2
	return g


# the "different genome/pose" creature: herbivore glow plates, wings, 6 legs,
# no tail, mirrored facing, angry + hurt + chewing
func _genome_b() -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 0.8
	g["legs"] = 6
	g["hue"] = 20
	g["sat"] = 0.8
	g["pattern"] = "glow"
	g["coat"] = "plates"
	g["diet"] = "herbivore"
	g["wings"] = 2
	g["horns"] = 4
	g["eyes"] = 5
	return g


func _pose_a() -> Dictionary:
	return {
		"x": 100.0, "y": 300.0, "facing": 1, "speed": 0.6, "gaitPhase": 1.3,
		"attack": 0.25, "hurt": 0.0, "eat": 0.0, "airborne": 0.15,
		"mood": "idle", "scale": 1.0
	}


func _pose_b() -> Dictionary:
	return {
		"x": -40.0, "y": 220.0, "facing": -1, "speed": 0.0, "gaitPhase": 4.2,
		"attack": 0.0, "hurt": 0.5, "eat": 0.7, "airborne": 0.0,
		"mood": "angry", "scale": 1.0
	}


func test_draw_smoke_fixed_genome() -> void:
	var ci := Node2D.new()  # offscreen: never added to the tree, bare canvas item
	var res: Dictionary = Painter.draw_creature(ci, _genome_a(), _pose_a(), {"t": 3.7})
	# the Ruling 11 clip sub-items exist and are valid RIDs
	ok(res.has("clip_item") and res.has("pattern_item") and res.has("front_item")
			and res.has("spine"), "draw returns {clip_item, pattern_item, front_item, spine}")
	var clip: RID = res["clip_item"]
	var pat: RID = res["pattern_item"]
	ok(clip.is_valid(), "clip sub-item RID valid (exists on the RenderingServer)")
	ok(pat.is_valid(), "pattern sub-item RID valid")
	var front: RID = res["front_item"]
	ok(front.is_valid(), "front sub-item RID valid (back/front split)")
	# the rig is consumed (spine count 6)
	var spine: Array = res["spine"]
	eq(spine.size(), 6, "returned spine has SEG=6 entries")
	# caller-owned lifecycle: the returned RIDs free cleanly (contract documented
	# in the painter header — a stage frees them before the next redraw)
	RenderingServer.free_rid(front)
	RenderingServer.free_rid(pat)
	RenderingServer.free_rid(clip)
	ci.free()


func test_second_creature_different_genome_pose() -> void:
	var ci := Node2D.new()
	var res_a: Dictionary = Painter.draw_creature(ci, _genome_a(), _pose_a(), {"t": 3.7})
	# second creature on the SAME offscreen item — different genome/pose, plus
	# lookDx/lookDy (the eye look-at path)
	var res_b: Dictionary = Painter.draw_creature(ci, _genome_b(), _pose_b(),
			{"t": 1.1, "lookDx": 40.0, "lookDy": -12.0})
	ok(res_b["clip_item"].is_valid(), "second creature clip RID valid")
	ok(res_b["pattern_item"].is_valid(), "second creature pattern RID valid")
	ok(res_b["front_item"].is_valid(), "second creature front RID valid")
	eq((res_b["spine"] as Array).size(), 6, "second creature spine count 6")
	# the painter is stateless: fresh sub-items per call, no reuse
	ok(res_a["clip_item"] != res_b["clip_item"], "stateless: distinct clip items per call")
	RenderingServer.free_rid(res_b["front_item"])
	RenderingServer.free_rid(res_b["pattern_item"])
	RenderingServer.free_rid(res_b["clip_item"])
	RenderingServer.free_rid(res_a["front_item"])
	RenderingServer.free_rid(res_a["pattern_item"])
	RenderingServer.free_rid(res_a["clip_item"])
	ci.free()


func test_rig_output_consumed_verbatim() -> void:
	# the painter must ride the T1 rig, not re-derive: the returned spine is the
	# rig's exact output for the same inputs (pure → bit-identical)
	var ci := Node2D.new()
	var g := _genome_a()
	var pose := _pose_a()
	var res: Dictionary = Painter.draw_creature(ci, g, pose, {"t": 3.7})
	var expected: Array = RigScript.spine_points(g, pose, 3.7)
	var spine: Array = res["spine"]
	eq(spine.size(), expected.size(), "spine length matches the rig")
	for i in expected.size():
		approx(float(spine[i]["x"]), float(expected[i]["x"]), "spine[%d].x = rig" % i, 1e-9)
		approx(float(spine[i]["y"]), float(expected[i]["y"]), "spine[%d].y = rig" % i, 1e-9)
		approx(float(spine[i]["r"]), float(expected[i]["r"]), "spine[%d].r = rig" % i, 1e-9)
	RenderingServer.free_rid(res["front_item"])
	RenderingServer.free_rid(res["front_item"])
	RenderingServer.free_rid(res["pattern_item"])
	RenderingServer.free_rid(res["clip_item"])
	ci.free()


func test_dead_pose_and_optional_paths() -> void:
	# remaining branches: dead rotate, shadow off, alpha fade, glow sclera +
	# look target, stripes pattern, legs 0 (no legs block)
	var ci := Node2D.new()
	var g := _genome_b()
	g["pattern"] = "stripes"
	g["legs"] = 0
	var pose := _pose_b()
	pose["mood"] = "dead"
	pose["airborne"] = 0.4
	var res: Dictionary = Painter.draw_creature(ci, g, pose,
			{"t": 2.5, "shadow": false, "alpha": 0.4, "lookDx": -30.0, "lookDy": 8.0})
	ok(res["clip_item"].is_valid(), "dead pose draw: clip RID valid")
	eq((res["spine"] as Array).size(), 6, "dead pose spine count 6")
	RenderingServer.free_rid(res["front_item"])
	RenderingServer.free_rid(res["pattern_item"])
	RenderingServer.free_rid(res["clip_item"])
	ci.free()
