## PRIMORDIA native entry point (boot scene). Registers the REAL MenuStage
## (Task 9 — the T1 placeholder is gone) and injects the composition root's
## stageFactory so a NEW LIFE rebuilds every gameplay stage with fresh
## instances (game.ts resetStagesForNewRun). The PRIMORDIA_BOOT_QUIT_FRAMES=N
## env hook quits cleanly after N frames (test-only hook, brief Boot AC:
## "quits via an env var after N frames").
extends Node

const GameScript := preload("res://src/game/game.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")

var game: Variant = null

var _boot_quit_frames := 0
var _frames := 0


func _ready() -> void:
	game = GameScript.new()
	add_child(game)
	game.stage_factory = func() -> Array:
		# fresh instances every NEW LIFE (game.ts:116-118) — run-1 latches
		# must not leak into run 2 (C1 deck rebuild, totem/civ/space latches).
		# GAMEPLAY stages only (TS main.ts:35-41): the menu persists — the map
		# keeps the registered instance, quit-to-title reuses it (the drifter
		# phase survives), TS shape.
		return [CellStageScript.new(game)]
	game.register(MenuStageScript.new(game))
	game.start()
	var env := OS.get_environment("PRIMORDIA_BOOT_QUIT_FRAMES")
	if env != "":
		_boot_quit_frames = int(env)


func _process(_delta: float) -> void:
	if _boot_quit_frames > 0:
		_frames += 1
		if _frames >= _boot_quit_frames:
			get_tree().quit(0)
