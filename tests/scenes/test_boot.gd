# Boot smoke test — run under xvfb:
#   xvfb-run -a ~/.local/bin/godot --path . res://tests/scenes/test_boot.tscn
# Boots the REAL main.tscn, asserts the real menu stage (Task 9 replaced the
# T1 placeholder — the real menu's NEW LIFE flow is exercised by real clicks
# in test_menu.tscn; this boot test keeps the placeholder-era direct
# start_new_game call), then polls <= 300 frames for the go_to('cell', title
# card) transition to run its full out → card → in shape. Prints BOOT_TEST_OK
# and exits 0; failures print to stderr and exit 1.
extends Node

const MainScene := preload("res://main.tscn")

var _main: Variant = null
var _frames := 0
var _started := false
var _saw_card := false


func _ready() -> void:
	_main = MainScene.instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	_frames += 1
	var game: Variant = _main.game
	if _frames == 5:
		if game.current == null or game.current.id != "menu":
			_fail("expected menu stage after boot, got %s" % str(game.current))
			return
	if _frames == 6 and not _started:
		_started = true
		# the real menu's start_new_game (no args = slot 0 / normal / random
		# seed — the click flow itself is test_menu.tscn's job under xvfb)
		game.current.start_new_game()
	if _started:
		if game.transition != null and game.transition["phase"] == "card":
			_saw_card = true
		if game.context.stage == "cell" and game.transition == null:
			if not _saw_card:
				_fail("the real menu's start fires a 'CELL STAGE' title card — card phase never ran")
				return
			print("BOOT_TEST_OK")
			get_tree().quit(0)
			return
	if _frames > 300:
		_fail("timeout waiting for cell stage (context.stage=%s, frames=%d)" % [
			str(game.context.stage), _frames])


func _fail(msg: String) -> void:
	printerr("BOOT_TEST_FAIL: " + msg)
	get_tree().quit(1)
