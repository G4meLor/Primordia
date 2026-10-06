# QC round 7 batch1 — creature editor wings/part-row probe (synthesis item 2,
# closes the retracted Major "wings row not clickable", creature-arc r7).
# The r7 scene wheeled 8 notches and never saw a wings rect; the code read
# (editor.gd) says a notch is wheel_delta 100 * 0.6 = 60 px of scroll, so 8
# notches = 480 px — enough to pull row 11 (wings) out from under the fold.
# This probe settles it with a full dump: row_rects + scroll at scroll 0, the
# STALE rects read after the wheel tick but BEFORE a re-render (the r7
# artifact: row_rects only refresh at draw time), the FRESH rects after
# _do_render, and a real click on the wings '+' rect through the input
# pipeline (purchase must land same-tick: genome wings +1, DNA spent).
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const WORLD_SEED := 51966  # 0xCAFE
const TIMEOUT_FRAMES := 36000
const WHEEL_NOTCHES := 12

var _phase := "boot"
var _frames := 0
var _leg := 0
var _game: Variant = null
var _dna0 := 0
var _wings0 := 0


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s" % _phase)
		return
	match _phase:
		"boot":
			var ctx: Variant = ContextScript.new(WORLD_SEED)
			_game = GameScript.new(ctx)
			add_child(_game)
			_game.set_process(false)
			_game.loop.is_active_cb = func() -> bool: return false
			for pair in [["menu", MenuStageScript], ["cell", CellStageScript],
					["creature", CreatureStageScript], ["tribe", TribeStageScript],
					["civ", CivStageScript], ["space", SpaceStageScript]]:
				_game.register(pair[1].new(_game))
			_game.start()
			_game.step_for_testing(1, 1.0 / 60.0)
			_game.stages["menu"].start_new_game(0, "normal", WORLD_SEED)
			_phase = "to_cell"
			_leg = 0
		"to_cell":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null and _game.current.id == "cell" \
					and _game.stages["cell"].sim != null:
				_game.switch_stage("creature")
				_phase = "open_editor"
				_leg = 0
		"open_editor":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 5:
				_game.context.dna = 500
				_tap(KEY_TAB)
				_phase = "editor_baseline"
				_leg = 0
				return
			_leg += 1
		"editor_baseline":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 2:
				var ed: Variant = _game.stages["creature"].editor_inst
				if not bool(_game.editor["open"]) or ed == null:
					_fail("editor did not open on Tab")
					return
				_game._do_render(0.0)
				_dump_rows("ROWS0", ed)
				_phase = "wheel"
				_leg = 0
				return
			_leg += 1
		"wheel":
			if _leg == 0:
				for i in WHEEL_NOTCHES:
					_wheel_notch()
				print("QC7W_WHEEL notches=%d" % WHEEL_NOTCHES)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 1:
				var ed2: Variant = _game.stages["creature"].editor_inst
				# STALE read: the wheel tick applied the scroll but row_rects
				# still hold the pre-wheel render (draw-time recording)
				var stale := _has_wings(ed2.row_rects)
				print("QC7W_STALE scroll=%.1f wings_in_rects=%s (rects pre-render)"
						% [float(ed2.scroll), str(stale)])
				_game._do_render(0.0)
				_dump_rows("ROWS1", ed2)
				var rect: Variant = _wings_plus(ed2.row_rects)
				if rect == null:
					_fail("wings + rect missing AFTER render at scroll %.1f (rows visible band check needed)"
							% float(ed2.scroll))
					return
				print("QC7W_FRESH scroll=%.1f wings_rect=%s" % [float(ed2.scroll), str(rect)])
				_phase = "click"
				_leg = 0
				return
			_leg += 1
		"click":
			if _leg == 0:
				var ed3: Variant = _game.stages["creature"].editor_inst
				var r: Dictionary = _wings_plus(ed3.row_rects)
				var center := Vector2(float(r["x"]) + float(r["w"]) / 2.0,
						float(r["y"]) + float(r["h"]) / 2.0)
				_dna0 = int(_game.context.dna)
				_wings0 = int(_game.context.genome.get("wings", 0))
				_click_at(center)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 2:
				var dna1 := int(_game.context.dna)
				var wings1 := int(_game.context.genome.get("wings", 0))
				print("QC7W_CLICK wings %d->%d dna %d->%d spent=%d"
						% [_wings0, wings1, _dna0, dna1, _dna0 - dna1])
				if wings1 == _wings0 + 1 and dna1 < _dna0:
					print("QC7W_ALL_OK")
					get_tree().quit(0)
				else:
					_fail("wings click did not purchase (wings %d->%d dna %d->%d)"
							% [_wings0, wings1, _dna0, dna1])
				_phase = "done"
			_leg += 1
		"done":
			pass


func _dump_rows(tag: String, ed: Variant) -> void:
	var parts: Array = []
	for rr in ed.row_rects:
		var row: Dictionary = rr["row"]
		var label := String(row.get("kind", "?"))
		if row.has("def"):
			label += "/" + String(row["def"].get("id", "?"))
		if rr["btn"] != null:
			label += ":" + String(rr["btn"])
		var r: Dictionary = rr["r"]
		parts.append("%s@%.0f,%.0f" % [label, float(r["x"]), float(r["y"])])
	print("QC7W_%s scroll=%.1f rows=%d rects=%d list=%s" % [tag, float(ed.scroll),
			ed.rows.size(), ed.row_rects.size(), str(parts)])


func _has_wings(rects: Array) -> bool:
	return _wings_plus(rects) != null


func _wings_plus(rects: Array) -> Variant:
	for rr in rects:
		var row: Dictionary = rr["row"]
		if String(row.get("kind", "")) == "part" and row.has("def") \
				and String(row["def"].get("id", "")) == "wings" \
				and rr["btn"] != null and String(rr["btn"]) == "+":
			return rr["r"]
	return null


func _wheel_notch() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _click_at(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _tap(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = keycode
	ev2.pressed = false
	Input.parse_input_event(ev2)
	Input.flush_buffered_events()


func _fail(msg: String) -> void:
	printerr("QC7W_FAIL: " + msg)
	get_tree().quit(1)
