## PRIMORDIA native entry point (boot scene). Registers the placeholder menu
## stage and starts the Game loop — Task 9 replaces the placeholder Menu/Cell
## stages with the real MenuStage; their only job here is proving the boot
## path and the go_to transition shape (no-title card → out 0.55 → in 0.6).
## PRIMORDIA_BOOT_QUIT_FRAMES=N quits cleanly after N frames (test-only hook,
## brief Boot AC: "quits via an env var after N frames").
extends Node

const GameScript := preload("res://src/game/game.gd")
const StageScript := preload("res://src/game/stage.gd")

var game: Variant = null

var _boot_quit_frames := 0
var _frames := 0


## Placeholder menu: Enter/click starts a new game into the placeholder cell
## stage via the no-title transition path.
class MenuPlaceholder extends "res://src/game/stage.gd":
	func _init(g: Variant) -> void:
		super(g, "menu")

	func update(_dt: float) -> void:
		if game.input.key_pressed("Enter") or game.input.was_clicked():
			start_new_game()

	## TS MenuStage.startNewGame rebuilds every stage via stageFactory (Task 9);
	## the placeholder just registers its cell once.
	func start_new_game() -> void:
		if not game.stages.has("cell"):
			game.register(CellPlaceholder.new(game))
		game.go_to("cell", {"title": "", "sub": ""})


## Placeholder cell: the real CellStage lands with the cell sim tasks.
class CellPlaceholder extends "res://src/game/stage.gd":
	func _init(g: Variant) -> void:
		super(g, "cell")


func _ready() -> void:
	game = GameScript.new()
	add_child(game)
	game.register(MenuPlaceholder.new(game))
	game.start()
	var env := OS.get_environment("PRIMORDIA_BOOT_QUIT_FRAMES")
	if env != "":
		_boot_quit_frames = int(env)


func _process(_delta: float) -> void:
	if _boot_quit_frames > 0:
		_frames += 1
		if _frames >= _boot_quit_frames:
			get_tree().quit(0)
