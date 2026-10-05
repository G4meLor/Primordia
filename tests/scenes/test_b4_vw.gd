# QC r1 B4 vw-collapse probe — the flat-frame survivors (left dark band whose
# width VARIES per frame: ~300px in 22_card_tribe, ~30px in 23_live_tribe;
# clouds only within [-300, vw+300]; the lawn sliver at screen center) all fit
# game.vw collapsing to a tiny value while the window stays 1152x648. This
# scene FORCES game.vw to a few values through the real creature stage render
# and captures, to confirm the visual mechanism end-to-end.
#
# Run (xvfb):
#   xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_b4_vw.tscn
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")

const OUT := "user://b4_vw"
const STEPS_PER_FRAME := 5

var game: Variant = null
var phase := "boot"
var frames := 0
var cases := [1152.0, 300.0, 30.0, 0.0]
var case_i := 0
var arm := 0


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
	g.start()
	return g


func _process(_dt: float) -> void:
	frames += 1
	if frames > 8000:
		get_tree().quit(1)
		return
	match phase:
		"boot":
			game = _build_game()
			game.current.start_new_game(0, "normal", 0xBEEF)
			phase = "to_cell"
		"to_cell":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			if String(game.context.stage) != "cell":
				return
			game.go_to("creature", {"title": "THE LONG WALK", "sub": "vw probe"})
			phase = "land"
		"land":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			if String(game.context.stage) != "creature":
				return
			game.step_for_testing(300, 1.0 / 60.0)
			phase = "case"
			arm = 0
		"case":
			if arm == 0:
				if case_i >= cases.size():
					print("B4_VW_ALL_OK")
					get_tree().quit(0)
					return
				game.vw = cases[case_i]
				print("B4_VW set vw=%.1f (vh=%.1f)" % [game.vw, game.vh])
				game._do_render(0.0)
				arm = 2
			else:
				arm -= 1
				if arm == 0:
					var img: Image = game.get_viewport().get_texture().get_image()
					var name := "vw%d" % int(cases[case_i])
					img.save_png("%s/%s.png" % [OUT, name])
					var counts := {}
					var samples := 0
					for y in range(0, img.get_height(), 8):
						for x in range(0, img.get_width(), 8):
							var c := img.get_pixel(x, y)
							counts["%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]] = int(counts.get("%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)], 0)) + 1
							samples += 1
					var top_key := ""
					var top_n := 0
					for k in counts:
						if counts[k] > top_n:
							top_n = counts[k]
							top_key = k
					print("STAT %s top=%s:%d/%d unique=%d" % [name, top_key, top_n, samples, counts.size()])
					# restore for the next case
					game._resize()
					case_i += 1
