# QC round 8 batch2.2 — editor footer overlap pixel check at 1152x648.
# Opens the CELL editor (the row count that put SKIN PATTERN at y=562),
# drives the render side (qc5/qc6 law), saves one PNG before exiting.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const DT := 1.0 / 60.0

var _phase := "build"
var _frames := 0
var _game: Variant = null


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > 1200:
		print("QC8R8ED TIMEOUT phase=%s" % _phase)
		get_tree().quit(1)
		return
	match _phase:
		"build":
			_game = _build_game()
			_game.stages["menu"].start_new_game(0, "normal", 48879)
			_phase = "card"
		"card":
			_game.step_for_testing(1, DT)
			_game._do_render(0.0)
			if _frames % 120 == 0:
				print("QC8R8ED dbg f=%d tr=%s stage=%s" % [_frames,
						str(_game.transition), String(_game.context.stage)])
			if _game.transition == null and _game.context.stage == "cell":
				_game.stages["cell"].editor_inst.show("cell")
				_phase = "shot"
				_frames = 0
		"shot":
			_game.step_for_testing(1, DT)
			_game._do_render(0.0)
			if _frames >= 5:
				var img: Image = _game.get_viewport().get_texture().get_image()
				var dir := DirAccess.open("user://")
				if dir != null and not dir.dir_exists("qc8r8b1"):
					dir.make_dir("qc8r8b1")
				if img != null:
					img.save_png("user://qc8r8b1/editor_footer.png")
					print("QC8R8ED PNG saved %dx%d rows=%d" % [img.get_width(),
							img.get_height(), _game.stages["cell"].editor_inst.rows.size()])
				else:
					print("QC8R8ED PNG miss")
				get_tree().quit(0)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(48879)
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
