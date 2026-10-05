# REAL-click quit-to-title → CONTINUE round-trip (QC r1 B2) — xvfb, rendering
# on: the draw pass builds the button rects and the parse_input_event pipeline
# needs a live SceneTree (the test_menu.gd doctrine). Boots the REAL main.tscn
# and drives TWO full cycles of: cell run → Esc pause → real click on
# 'Quit to title' → the PRIMORDIA card walk → real click on '▶ CONTINUE' →
# real click on the slot row → lands back in the saved cell stage. Cycle 2
# also drives the corrupt-slot path with a real click: junk slot1 file → the
# tombstone row click marks corrupt, records the menu's OWN toast (menu_toast,
# drawn by _draw_menu — the live hud renders only inside gameplay stages) and
# fires NO transition; the healthy row still lands afterwards.
#
# Run: xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_menu_quit_continue.tscn
# Prints MENUQC_OK and exits 0; failures print MENUQC_FAIL and exit 1.
extends Node

const MainScene := preload("res://main.tscn")
const DriverScript := preload("res://tests/bots/bot_driver.gd")

const TIMEOUT_FRAMES := 7200
# the quit card (PRIMORDIA) and continue card (WELCOME BACK) are opaque and
# eat their dismissing click — every click waits for a fully idle transition
const SETTLE_FRAMES := 30

var _main: Variant = null
var _driver: Variant = null

var _phase := "boot"
var _pf := 0
var _done := false
var _cycle := 1
var _corrupt_click_frames := 0


func _ready() -> void:
	_driver = DriverScript.new()
	var dir := DirAccess.open("user://")
	if dir != null:
		if dir.dir_exists("saves"):
			var s := DirAccess.open("user://saves")
			for i in 3:
				if s.file_exists("slot%d.json" % i):
					s.remove("slot%d.json" % i)
		dir.remove("test_menuqc_settings.cfg")
		dir.remove("test_menuqc_settings.cfg.tmp")
	_main = MainScene.instantiate()
	add_child(_main)
	var g: Variant = _main.game
	g.i18n.settings_path = "user://test_menuqc_settings.cfg"
	g.i18n.load_settings()
	g.i18n.set_lang("en")


func _process(_dt: float) -> void:
	if _done:
		return
	_pf += 1
	if _pf > TIMEOUT_FRAMES:
		_fail("timeout in phase %s cycle %d" % [_phase, _cycle])
		return
	var game: Variant = _main.game
	match _phase:
		"boot":
			if _pf < 8:
				return
			if game.current == null or game.current.id != "menu":
				_fail("boot: expected the menu stage")
				return
			_next("new_life")
		"new_life":
			if _click_button(game, "NEW LIFE"):
				_next("begin")
		"begin":
			if game.current.view != "new":
				return
			if _click_button(game, "BEGIN"):
				_next("wait_cell")
		"wait_cell":
			if game.context.stage == "cell" and game.transition == null:
				_next("pause_open")
		"pause_open":
			if _pf < SETTLE_FRAMES:
				return
			_driver.tap_key(KEY_ESCAPE)
			_next("pause_wait")
		"pause_wait":
			if not bool(game.paused):
				return
			_next("click_quit")
		"click_quit":
			var pause: Variant = game.current.get("pause_inst")
			if pause == null:
				return
			for it in pause.items:
				if String(it["label"]).contains("Quit"):
					_click_rect(game, it)
					_next("quit_wait")
					return
		"quit_wait":
			if game.transition != null or game.current.id != "menu" \
					or game.context.stage != "menu":
				return
			if _pf < SETTLE_FRAMES:
				return  # let the draw passes rebuild the title buttons
			_next("click_continue")
		"click_continue":
			# cycle 2 also probes the corrupt path: the junk slot1 must exist
			# BEFORE the CONTINUE click — its refresh_slots builds the
			# tombstone row (⚠ meta, ENABLED) that the corrupt click targets
			if _cycle == 2:
				_write_junk_slot(1)
			if _click_button(game, "CONTINUE"):
				_next("continue_view_wait")
		"continue_view_wait":
			if game.current.view != "continue":
				return
			if _pf < SETTLE_FRAMES:
				return  # let the draw pass rebuild the slot rows
			_next("click_corrupt_row" if _cycle == 2 else "click_row")
		"click_corrupt_row":
			_corrupt_click_frames += 1
			# the tombstone row is the SECOND label-'' button (rows 1..3)
			var rows: Array = _label_empty_buttons(game)
			if rows.size() < 2:
				return
			_click_rect(game, rows[1])
			_next("corrupt_check")
		"corrupt_check":
			# load-fail: marked, no transition, and the menu's own toast set
			if game.transition != null:
				_fail("corrupt row click started a transition")
				return
			if _pf < 60:
				return
			if not bool(game.current.corrupt_slots.has(1)):
				_fail("corrupt slot not marked after the row click")
				return
			if game.current.menu_toast == null:
				_fail("menu toast not recorded after the corrupt load-fail")
				return
			_next("click_row")
		"click_row":
			var rows2: Array = _label_empty_buttons(game)
			if rows2.is_empty():
				return
			_click_rect(game, rows2[0])
			_next("land_wait")
		"land_wait":
			if game.context.stage == "cell" and game.transition == null:
				if _cycle == 1:
					_cycle = 2
					_next("pause_open")
					return
				print("MENUQC_OK both cycles landed; corrupt path handled")
				_done = true
				get_tree().quit(0)
				return
			if game.current.id == "menu" and game.transition == null \
					and _pf > 900:
				_fail("CONTINUE dead after quit-to-title (no transition, no feedback)")


func _next(p: String) -> void:
	_phase = p
	_pf = 0
	if p != "click_corrupt_row":
		_corrupt_click_frames = 0


## Junk slot1 — the tombstone source for the corrupt-row click (cycle 2).
func _write_junk_slot(slot: int) -> void:
	var dir := DirAccess.open("user://saves")
	if dir != null and not dir.file_exists("slot%d.json" % slot):
		var f := FileAccess.open("user://saves/slot%d.json" % slot, FileAccess.WRITE)
		f.store_string("{{{ junk not json")
		f = null


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
	var game: Variant = _main.game
	printerr("MENUQC_FAIL: " + msg)
	printerr("MENUQC state: stage=%s view=%s transition=%s paused=%s corrupt=%s toast=%s" % [
			game.context.stage,
			str(game.current.get("view") if game.current != null else null),
			str(game.transition), str(game.paused),
			str(game.current.get("corrupt_slots") if game.current != null else null),
			str(game.current.get("menu_toast") if game.current != null else null)])
	get_tree().quit(1)
