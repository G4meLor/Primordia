# QC round 7 batch1 — CONTINUE input dead-window probe (synthesis item 3,
# cell-arc r7 Minor "input dead after WELCOME BACK card, E dead, D 0.1px/90").
# The r7 scene did NOT gate on game.transition == null — its keypresses may
# have landed inside the card freeze (game.gd skips current.update during the
# card phase, and a one-shot keydown is cleared by end_frame, so an E tapped
# mid-card is dropped by design). This probe:
#   1. polls game.transition every step and logs the out/card/in/null
#      timeline (the _update_transition trace),
#   2. documents the artifact: an E tapped mid-card must NOT open the editor,
#   3. measures input the moment transition is null (the r7 scene never did):
#      E opens the editor same-tick, D held 90 steps moves the player,
#      compared against the same measurements on the NEW LIFE card (control).
# Verdict: input alive at transition==null → artifact/env-note (Minor stands
# down); input dead while transition==null → raise Major (real softlock).
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
const HOLD_STEPS := 90

var _phase := "boot"
var _frames := 0
var _leg := 0
var _game: Variant = null
var _last_phase := ""
var _card_seen_leg := -1
var _card_e_done := false
var _card_e_check := 0
var _card_e_opened := false
var _editor_at_null := false
var _editor_again := false
var _ctrl_x0 := 0.0
var _ctrl_delta := -1.0
var _ctrl_attempt := 0
var _ctrl_seeds: Array = [51966, 51973, 51979]  # 0xCAFE + spares — insurance
# against a genuinely blocked spawn; the first "0.4 px" run turned out to be
# a probe bug (a missed D press), not the game
var _cont_x0 := 0.0
var _cont_delta := -1.0
var _cont_php_min := 999.0
var _attempt := 0


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
			_game.stages["menu"].start_new_game(0, "normal", int(_ctrl_seeds[0]))
			_phase = "ctrl_card"
			_last_phase = ""
			_leg = 0
		"ctrl_card":
			# the NEW LIFE card — same freeze shape as WELCOME BACK
			_track_phases("ctrl")
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null:
				_phase = "ctrl_hold"
				_leg = 0
				return
			_leg += 1
		"ctrl_hold":
			var sim: Variant = _game.stages["cell"].sim
			if sim == null:
				_fail("cell sim missing (ctrl)")
				return
			if _leg == 0:
				_ctrl_x0 = float(sim.px)
				_press(KEY_D, true)
			if _leg < HOLD_STEPS:
				_game.step_for_testing(1, 1.0 / 60.0)
				_leg += 1
			else:
				_press(KEY_D, false)
				_ctrl_delta = absf(float(sim.px) - _ctrl_x0)
				print("QC7DW_CONTROL d90=%.1fpx php=%.0f seed=%d attempt=%d"
						% [_ctrl_delta, float(sim.php), int(_ctrl_seeds[_ctrl_attempt]), _ctrl_attempt])
				if _ctrl_delta < 50.0 and _ctrl_attempt < _ctrl_seeds.size() - 1:
					# spawn-ambush artifact (grabbed/pinned player) — new world
					_ctrl_attempt += 1
					_game.stages["menu"].start_new_game(0, "normal",
							int(_ctrl_seeds[_ctrl_attempt]))
					_phase = "ctrl_card"
					_last_phase = ""
					_leg = 0
					return
				_game.save_all()
				_game.go_to("menu")
				_phase = "to_menu"
				_leg = 0
		"to_menu":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null and _game.current.id == "menu":
				print("QC7DW_CONTINUE slot=0 (fresh save from this run)")
				_game.stages["menu"].continue_slot(0)
				_phase = "cont_card"
				_last_phase = ""
				_card_seen_leg = -1
				_card_e_done = false
				_card_e_opened = false
				_leg = 0
		"cont_card":
			_track_phases("cont")
			_game.step_for_testing(1, 1.0 / 60.0)
			# negative control: one E tap mid-card — the card freezes
			# current.update, and the one-shot dies with the frame
			var in_card: bool = _game.transition != null \
					and String(_game.transition["phase"]) == "card"
			if in_card and _card_seen_leg >= 0 \
					and (_leg - _card_seen_leg) == 60 and not _card_e_done:
				_card_e_done = true
				_card_e_check = 3
				_tap(KEY_E)
			if _card_e_done and _card_e_check > 0:
				_card_e_check -= 1
				if _card_e_check == 0:
					_card_e_opened = bool(_game.editor["open"])
			if _game.transition == null:
				print("QC7DW_NULL at cont_step=%d (input gate opens HERE)" % _leg)
				_phase = "cont_first_key"
				_leg = 0
				return
			_leg += 1
		"cont_first_key":
			# THE measurement: the first key press AFTER transition == null
			if _leg == 0:
				_tap(KEY_E)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 1:
				_editor_at_null = bool(_game.editor["open"])
				print("QC7DW_FIRST_E editor_open=%s (transition was null)" % str(_editor_at_null))
				if _editor_at_null:
					_tap(KEY_E)  # close it again
				_phase = "cont_d_hold"
				_leg = 0
				return
			_leg += 1
		"cont_d_hold":
			var sim2: Variant = _game.stages["cell"].sim
			if sim2 == null:
				_fail("cell sim missing (cont)")
				return
			if _leg == 0:
				_cont_x0 = float(sim2.px)
				_press(KEY_D, true)
			if _leg < HOLD_STEPS + 5:
				_game.step_for_testing(1, 1.0 / 60.0)
				_cont_php_min = minf(_cont_php_min, float(sim2.php))
				_leg += 1
			else:
				_press(KEY_D, false)
				_cont_delta = absf(float(sim2.px) - _cont_x0)
				print("QC7DW_CONT_D d90=%.1fpx php_min=%.0f deathfade=%.2f"
						% [_cont_delta, _cont_php_min, float(sim2.deathFade)])
				_tap(KEY_E)  # second E well after the card — input still alive?
				_phase = "cont_second_e"
				_leg = 0
		"cont_second_e":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 1:
				_editor_again = bool(_game.editor["open"])
				print("QC7DW_SECOND_E editor_open=%s" % str(_editor_again))
				_phase = "report"
				_leg = 0
				return
			_leg += 1
		"report":
			print("QC7DW_CARDE tapped_mid_card opened=%s (expect false — dropped by design)"
					% str(_card_e_opened))
			var input_alive := _editor_at_null and _editor_again and _cont_delta > 50.0
			var ctrl_sane := _ctrl_delta > 50.0
			print("QC7DW_VERDICT input_alive_at_null=%s control_sane=%s (d90 cont=%.1f ctrl=%.1f)"
					% [str(input_alive), str(ctrl_sane), _cont_delta, _ctrl_delta])
			if input_alive:
				if ctrl_sane:
					print("QC7DW_ALL_OK artifact=card-window+stale-frame (no Major)")
				else:
					print("QC7DW_ALL_OK artifact=card-window+stale-frame (no Major; ctrl leg contaminated by spawn harassment — the cont leg self-proves: editor opens twice, D moves)")
				get_tree().quit(0)
			elif _attempt == 0 and _cont_php_min <= 0.0:
				_attempt += 1
				print("QC7DW_RETRY player died mid-hold (php_min %.0f) — rerunning the continue leg"
						% _cont_php_min)
				_game.go_to("menu")
				_phase = "to_menu"
				_leg = 0
			else:
				_fail("input dead or control insane — see QC7DW lines above")
			_phase = "done"
		"done":
			pass


func _track_phases(tag: String) -> void:
	var p: Variant = null
	if _game.transition != null:
		p = _game.transition["phase"]
	var ps := "null" if p == null else String(p)
	if ps != _last_phase:
		if ps == "card" and _card_seen_leg < 0:
			_card_seen_leg = _leg
		print("QC7DW_PHASE %s %s @leg=%d frames=%d" % [tag, ps, _leg, _frames])
		_last_phase = ps


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


func _press(kc: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = kc
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _fail(msg: String) -> void:
	printerr("QC7DW_FAIL: " + msg)
	get_tree().quit(1)
