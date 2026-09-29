# Boot smoke test — run under xvfb:
#   xvfb-run -a ~/.local/bin/godot --path . res://tests/scenes/test_boot.tscn
# Boots the REAL main.tscn, asserts the placeholder menu stage, injects a real
# InputEventKey (Enter) through Input.parse_input_event (Global Constraint 8 —
# the bot parity law: progression gates go through the actual input pipeline),
# then polls <= 300 frames for the go_to('cell', no-title) transition to run
# its full out → in shape (no card — the placeholder card has an empty title).
# Prints BOOT_TEST_OK and exits 0; failures print to stderr and exit 1.
extends Node

const MainScene := preload("res://main.tscn")

var _main: Variant = null
var _frames := 0
var _injected := false


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
	if _frames == 6 and not _injected:
		_injected = true
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ENTER
		ev.pressed = true
		Input.parse_input_event(ev)
	if _injected and game.context.stage == "cell" and game.transition == null:
		print("BOOT_TEST_OK")
		get_tree().quit(0)
		return
	# no-title shape: out 0.55 → in 0.6 DIRECTLY — a card phase must never run
	if game.transition != null and game.transition["phase"] == "card":
		_fail("empty-title card must skip the card phase (got %s)" % str(game.transition["phase"]))
		return
	if _frames > 300:
		_fail("timeout waiting for cell stage (context.stage=%s, frames=%d)" % [
			str(game.context.stage), _frames])


func _fail(msg: String) -> void:
	printerr("BOOT_TEST_FAIL: " + msg)
	get_tree().quit(1)
