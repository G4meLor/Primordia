# REAL-click menu flow test — Task 9 (xvfb, rendering on: the draw pass builds
# the button rects and the parse_input_event pipeline needs a live SceneTree).
# Boots the REAL main.tscn, then drives the full NEW LIFE flow through actual
# mouse clicks — title → NEW LIFE → the CHAOS difficulty card → BEGIN → the
# cell stage via the full 'CELL STAGE' card transition — and asserts the
# clicked difficulty took effect (Global Constraint 8: progression gates go
# through the actual input pipeline, never a direct method call).
#
# Button rects are read from the menu's own buttons records (rebuilt every
# draw pass — the same doctrine as the editor-click test's row_rects).
#
# Run: tools/test_menu.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_menu.tscn
# Prints MENU_TEST_OK and exits 0; failures print MENU_TEST_FAIL on stderr
# and exit 1.
extends Node

const MainScene := preload("res://main.tscn")
const DriverScript := preload("res://tests/bots/bot_driver.gd")

const TIMEOUT_FRAMES := 900  # the full card transition is 3.35s of wall time

var _main: Variant = null
var _driver: Variant = null
const SCRATCH_CFG := "user://test_menu_settings.cfg"

var _phase := "boot"
var _frames := 0
var _done := false


func _ready() -> void:
	_driver = DriverScript.new()
	# a stale slot0 from another run would arm the overwrite confirm —
	# this test must click BEGIN exactly once
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for i in 3:
			if dir.file_exists("slot%d.json" % i):
				dir.remove("slot%d.json" % i)
	_main = MainScene.instantiate()
	add_child(_main)
	# locale isolation (test_game_flow's pattern): the shared user cfg may
	# carry lang=vi, which would translate the EN label fragments below
	# ("▶ BEGIN" → "▶ BẮT ĐẦU") — pin EN through a scratch cfg
	var g: Variant = _main.game
	g.i18n.settings_path = SCRATCH_CFG
	var cfg_dir := DirAccess.open("user://")
	if cfg_dir != null:
		cfg_dir.remove("test_menu_settings.cfg")
		cfg_dir.remove("test_menu_settings.cfg.tmp")
	g.i18n.load_settings()
	g.i18n.set_lang("en")


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	if _done:
		return
	var game: Variant = _main.game
	match _phase:
		"boot":
			if _frames < 8:
				return  # let a draw pass build the title buttons
			if game.current == null or game.current.id != "menu":
				_fail("expected the menu stage after boot, got %s" % str(game.current))
				return
			_phase = "click_new_life"
		"click_new_life":
			if _click_button(game, "NEW LIFE"):
				_phase = "verify_new_view"
		"verify_new_view":
			if game.current.view != "new":
				return  # the click lands on the next fixed step
			_phase = "click_chaos"
		"click_chaos":
			# the difficulty cards are the first three label-'' buttons of the
			# new view (builders are TS-verbatim, order stable) — index 2 = chaos
			var cards: Array = _label_empty_buttons(game)
			if cards.size() < 3:
				return
			_click_rect(game, cards[2])
			_phase = "verify_chaos"
		"verify_chaos":
			if String(game.current.sel_difficulty) != "chaos":
				return
			_phase = "click_begin"
		"click_begin":
			if _click_button(game, "BEGIN"):
				_phase = "wait_cell"
		"wait_cell":
			if game.context.stage == "cell" and game.transition == null:
				if String(game.context.difficulty) != "chaos":
					_fail("the clicked chaos difficulty did not reach the context (got %s)"
							% str(game.context.difficulty))
					return
				# 0.45 at start_new_game (pinned exactly by the headless flow
				# test); the card-phase wait lets the settle drag it toward the
				# chaos floor 0.25 — here it must only sit between floor and start
				if float(game.context.chaos) <= 0.25 or float(game.context.chaos) > 0.45:
					_fail("chaos not settling from the chaos start (got %s)"
							% str(game.context.chaos))
					return
				# 100 at start_new_game; the sim is LIVE once the transition
				# clears, so the poll frame may already have eaten a pellet
				if int(game.context.dna) < 100:
					_fail("starting dna below 100 (got %d)" % int(game.context.dna))
					return
				print("MENU_TEST_OK difficulty=%s chaos=%s dna=%d" % [
					str(game.context.difficulty), str(game.context.chaos),
					int(game.context.dna)])
				_done = true
				get_tree().quit(0)


# ---- helpers -------------------------------------------------------------------

## Click the first button whose label contains `fragment` (the menu rebuilds
## its buttons every draw pass; labels are pre-translation keys in EN).
func _click_button(game: Variant, fragment: String) -> bool:
	for b in game.current.buttons:
		if String(b["label"]).contains(fragment):
			_click_rect(game, b)
			return true
	return false


func _label_empty_buttons(game: Variant) -> Array:
	var out := []
	for b in game.current.buttons:
		if String(b["label"]) == "":
			out.append(b)
	return out


func _click_rect(game: Variant, b: Dictionary) -> void:
	var center := Vector2(float(b["x"]) + float(b["w"]) / 2.0,
			float(b["y"]) + float(b["h"]) / 2.0)
	_driver.move_mouse(center)
	_driver.mouse_down(center)
	_driver.mouse_up()


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("MENU_TEST_FAIL: " + msg)
	get_tree().quit(1)
