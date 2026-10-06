# QC r2 C2 probe — quit-to-title silent crash (heisenbug), solo repro x5.
# Drives the REAL main.tscn with real input (parse_input_event pipeline) through
# CYCLES rounds of heavy interaction history (3x Esc pause/resume, editor
# open/close, KeyM, held swim) then Esc -> real click on 'Quit to title'. The
# ~80-frame window after the quit click is traced PER FRAME into
# user://c2_probe_markers.log (flush per write — stdout dies with a segfault,
# the file does not). In-game breadcrumbs (C2Q[..] lines in
# user://crash_markers.log, pause.gd/context.gd/game.gd) bracket save_all /
# go_to / switch_stage from the inside. When the title lands: CONTINUE -> slot
# row -> back in cell -> next cycle (the r2 repro loop: quit -> CONTINUE ->
# Esc -> Quit inside ONE process).
#
# Run: xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_qc2_c2_quit.tscn
# Prints C2Q_PROBE_OK (all cycles landed) or C2Q_PROBE_FAIL: <why>; exits 0/1.
extends Node

const MainScene := preload("res://main.tscn")
const DriverScript := preload("res://tests/bots/bot_driver.gd")

const CYCLES := 5
const TIMEOUT_FRAMES := 5400
const SETTLE_FRAMES := 30
const QUIT_WINDOW_FRAMES := 240

var _main: Variant = null
var _driver: Variant = null
var _phase := "boot"
var _pf := 0
var _cycle := 1
var _done := false
var _hist_left := 0
var _hist_kind := ""
var _hist_hold := 0
var _trace_left := 0
var _swim_frame := 0


func _ready() -> void:
	_driver = DriverScript.new()
	var dir := DirAccess.open("user://")
	if dir != null:
		if dir.dir_exists("saves"):
			var s := DirAccess.open("user://saves")
			for i in 3:
				if s.file_exists("slot%d.json" % i):
					s.remove("slot%d.json" % i)
		dir.remove("c2_probe_markers.log")
		dir.remove("crash_markers.log")
		dir.remove("test_qc2_settings.cfg")
		dir.remove("test_qc2_settings.cfg.tmp")
	_main = MainScene.instantiate()
	add_child(_main)
	var g: Variant = _main.game
	g.i18n.settings_path = "user://test_qc2_settings.cfg"
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	_mark("probe boot")


func _mark(line: String) -> void:
	var l := "C2P[%d] c%d %s" % [Time.get_ticks_msec(), _cycle, line]
	print(l)
	var f := FileAccess.open("user://c2_probe_markers.log", FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
	else:
		f = FileAccess.open("user://c2_probe_markers.log", FileAccess.WRITE)
	if f != null:
		f.store_string(l + "\n")
		f.flush()


func _process(_dt: float) -> void:
	if _done:
		return
	_pf += 1
	if _pf > TIMEOUT_FRAMES:
		_fail("timeout in phase %s cycle %d" % [_phase, _cycle])
		return
	var game: Variant = _main.game
	if game == null:
		return  # main not booted yet — keep the frame budget, retry next frame
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
				_hist_left = 3
				_hist_kind = "pause"
				_next("hist_pause_open")
		# ---- heavy interaction history (the r2 repro profile) ----
		"hist_pause_open":
			_driver.tap_key(KEY_ESCAPE)
			_next("hist_pause_wait")
		"hist_pause_wait":
			if not bool(game.paused):
				return
			_hist_hold = 20
			_next("hist_pause_hold")
		"hist_pause_hold":
			_hist_hold -= 1
			if _hist_hold <= 0:
				_driver.tap_key(KEY_ESCAPE)
				_next("hist_resume_wait")
		"hist_resume_wait":
			if bool(game.paused):
				return
			_hist_left -= 1
			if _hist_left > 0:
				_next("hist_pause_open")
			else:
				_hist_kind = "editor"
				_next("hist_editor_open")
		"hist_editor_open":
			_driver.tap_key(KEY_E)
			_next("hist_editor_wait")
		"hist_editor_wait":
			if _pf > 120:
				# editor may be gated (dead/transition) — the history stays heavy
				# without it; note and move on rather than fail the cycle
				_mark("KeyE open timed out — skipping editor leg")
				_hist_kind = "mute"
				_next("hist_mute_a")
				return
			if not bool(game.editor["open"]):
				return
			_hist_hold = 20
			_next("hist_editor_hold")
		"hist_editor_hold":
			_hist_hold -= 1
			if _hist_hold <= 0:
				_driver.tap_key(KEY_ESCAPE)
				_next("hist_editor_close_wait")
		"hist_editor_close_wait":
			if bool(game.editor["open"]):
				return
			_hist_kind = "mute"
			_next("hist_mute_a")
		"hist_mute_a":
			_driver.tap_key(KEY_M)
			_next("hist_mute_b")
		"hist_mute_b":
			if _pf < 10:
				return
			_driver.tap_key(KEY_M)
			_next("hist_swim")
		"hist_swim":
			# held swim click (the r2 repro kept a held click through pauses)
			if _swim_frame == 0:
				_driver.mouse_down(Vector2(game.vw / 2.0, game.vh / 2.0))
			_swim_frame += 1
			_driver.move_mouse(Vector2(game.vw / 2.0 + 40.0, game.vh / 2.0))
			if _swim_frame >= 30:
				_driver.mouse_up()
				_swim_frame = 0
				_next("hist_quit_pause")
		"hist_quit_pause":
			_driver.tap_key(KEY_ESCAPE)
			_next("hist_quit_wait")
		"hist_quit_wait":
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
					_mark("quit clicked (cycle %d)" % _cycle)
					_trace_left = QUIT_WINDOW_FRAMES
					_next("quit_window")
					return
		# ---- the death window: per-frame flushed trace ----
		"quit_window":
			if _trace_left > 0:
				var ph := ""
				if game.transition != null:
					ph = String(game.transition["phase"])
				_mark("f%d cur=%s trans=%s paused=%s" % [
					QUIT_WINDOW_FRAMES - _trace_left, game.current.id, ph,
					str(game.paused)])
				_trace_left -= 1
			if game.current.id == "menu" and game.transition == null:
				if _pf < SETTLE_FRAMES:
					return
				_mark("menu reached")
				_next("click_continue")
			elif _pf > 1200:
				_fail("quit did not reach the menu in 1200 frames")
		"click_continue":
			if _click_button(game, "CONTINUE"):
				_next("continue_view_wait")
		"continue_view_wait":
			if game.current.view != "continue":
				return
			if _pf < SETTLE_FRAMES:
				return
			_next("click_row")
		"click_row":
			var rows: Array = _label_empty_buttons(game)
			if rows.is_empty():
				return
			_click_rect(game, rows[0])
			_next("land_wait")
		"land_wait":
			if game.context.stage == "cell" and game.transition == null:
				_mark("landed back in cell (cycle %d done)" % _cycle)
				if _cycle >= CYCLES:
					print("C2Q_PROBE_OK %d quit-to-title cycles landed in one process" % CYCLES)
					_done = true
					get_tree().quit(0)
					return
				_cycle += 1
				_hist_left = 3
				_hist_kind = "pause"
				_next("hist_pause_open")
			elif game.current.id == "menu" and game.transition == null \
					and _pf > 900:
				_fail("CONTINUE dead after quit-to-title")


func _next(p: String) -> void:
	_phase = p
	_pf = 0


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
	var game: Variant = _main.game if _main != null else null
	printerr("C2Q_PROBE_FAIL: " + msg)
	if game == null:
		printerr("C2Q state: main not booted")
		get_tree().quit(1)
		return
	printerr("C2Q state: stage=%s cur=%s transition=%s paused=%s editor=%s" % [
			game.context.stage,
			str(game.current.id if game.current != null else null),
			str(game.transition), str(game.paused),
			str(game.editor.get("open"))])
	get_tree().quit(1)
