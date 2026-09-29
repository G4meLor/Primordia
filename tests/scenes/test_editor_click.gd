# Editor REAL-input click test — Task 8 (the re-routed T6 editor acceptance
# criterion). Opens the editor through the REAL KeyE pipeline (bot-driver
# pattern), then presses a synthetic mouse button at the flagella '+' button —
# the rect read from the editor's OWN row-rect records, populated by its draw
# pass — and one fixed step later the gene has bumped and the DNA dropped by
# part_cost (Global Constraint 8: the gate goes through the actual input
# pipeline + the game's blocked-branch overlay dispatch, never a direct
# editor.click_part call).
#
# Run (xvfb, rendering on — the draw pass + input dispatch need a live tree):
#   tools/test_editor_click.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_editor_click.tscn
# Prints EDITOR_CLICK_OK and exits 0; failures print EDITOR_CLICK_FAIL on
# stderr and exit 1.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")  # the REAL menu since Task 9
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")
const PartsScript := preload("res://src/evo/parts.gd")

const SEED := 0xED17
const DT := 1.0 / 60.0
const TRANSITION_POLL := 300
const CARD_STEPS := 180
const TIMEOUT_FRAMES := 1800

var _phase := "build"
var _frames := 0
var _game: Variant = null
var _driver: Variant = null
var _dna_before := 0
var _level_before := 0
var _plus := Vector2.ZERO
var _done := false


func _ready() -> void:
	_driver = BotDriverScript.new()


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	if _done:
		return
	match _phase:
		"build":
			_game = _build_game()
			_phase = "prologue"
		"prologue":
			if not _prologue():
				return
			_game.context.dna = 500
			# the tutorial's move/eat steps gate the editor step — drive the
			# counters (the sanctioned scripted-sim pattern for the passive
			# tutorial observer; the editor gate itself stays real-input)
			_game.current.sim.tut["moved"] = 500.0
			_game.current.sim.tut["eaten"] = 3
			# real KeyE press → the stage's editor branch (CellStage.ts:351-358)
			_driver.tap_key(KEY_E)
			_game.step_for_testing(1, DT)
			if not bool(_game.editor["open"]):
				_fail("KeyE through the real pipeline did not open the editor")
				return
			if int(_game.current.sim.tut["editorOpened"]) != 1:
				_fail("the editorOpened tutorial gate did not increment")
				return
			_phase = "render"
		"render":
			_game._do_render(0.0)  # queue every layer → the draw pass records row_rects
			_phase = "read"
		"read":
			# the draw pass runs at frame end — poll for the records
			var rects: Array = _game.current.editor_inst.row_rects
			if rects.is_empty():
				return
			var found := {}
			for rr in rects:
				if rr["btn"] != null and String(rr["btn"]) == "+" \
						and String(rr["row"]["kind"]) == "part" \
						and String(rr["row"]["def"]["id"]) == "flagella":
					found = rr["r"]
			if found.is_empty():
				_fail("no flagella '+' rect in the editor's row-rect records")
				return
			_plus = Vector2(float(found["x"]) + float(found["w"]) / 2.0,
					float(found["y"]) + float(found["h"]) / 2.0)
			_level_before = int(_game.context.genome["flagella"])
			_dna_before = int(_game.context.dna)
			_phase = "click"
		"click":
			# REAL mouse press at the button center; the next fixed step runs
			# the blocked-branch editor.update (TS game.ts:308-311) which
			# consumes the click and buys the part
			_driver.mouse_down(_plus)
			_game.step_for_testing(1, DT)
			_driver.mouse_up()
			var g: Dictionary = _game.context.genome
			if int(g["flagella"]) != _level_before + 1:
				_fail("the click did not bump flagella (%d → %s)"
						% [_level_before, str(g["flagella"])])
				return
			var cost: int = PartsScript.part_cost(PartsScript.part_by_id("flagella"), _level_before)
			if int(_game.context.dna) != _dna_before - cost:
				_fail("dna did not drop by part_cost (got %d, want %d)"
						% [int(_game.context.dna), _dna_before - cost])
				return
			# the tutorial's editor step polls on STAGE updates — blocked while
			# the overlay is open (TS identical), so close via a real KeyE and
			# let the next stage update react
			_driver.tap_key(KEY_E)
			_game.step_for_testing(1, DT)  # blocked branch: editor.update closes
			if bool(_game.editor["open"]):
				_fail("KeyE through the real pipeline did not close the editor")
				return
			# live stage again: the tutorial polls one step per update —
			# move → eat → editor (the counters were pre-driven)
			for i in 3:
				_game.step_for_testing(1, DT)
			if _game.current.tutorial != null and int(_game.current.tutorial.step_index) < 3:
				_fail("the tutorial editor step did not react (step_index=%s)"
						% str(_game.current.tutorial.step_index))
				return
			# test hygiene: the dirty close flushed a real slot save
			var dir := DirAccess.open("user://saves")
			if dir != null:
				dir.remove("slot0.json")
			print("EDITOR_CLICK_OK flagella=%d dna=%d cost=%d tut_step=%s" % [
					int(g["flagella"]), int(_game.context.dna), cost,
					str(_game.current.tutorial.step_index)])
			_phase = "done"
			_done = true
			get_tree().quit(0)


# ---- helpers (the T6 trap pattern, verbatim) -----------------------------------

## Boot → menu → new game → transition → card-slot (bot.test.ts:55-73).
func _prologue() -> bool:
	_game.step_for_testing(5)
	if _game.context.stage != "menu":
		_fail("prologue: expected menu after 5 steps, got %s" % str(_game.context.stage))
		return false
	var menu: Variant = _game.current
	# the seed rides along (see test_bot_arc.gd's prologue note — the real
	# menu replaces the context world)
	menu.start_new_game(0, "normal", SEED)
	var steps := 0
	while _game.context.stage != "cell" and steps < TRANSITION_POLL:
		_game.step_for_testing(1, DT)
		steps += 1
	if _game.context.stage != "cell":
		_fail("prologue: cell stage not reached within %d steps" % TRANSITION_POLL)
		return false
	_game.step_for_testing(CARD_STEPS, DT)
	return true


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	# Manual stepping ONLY (see test_bot_arc.gd): set_process must come AFTER
	# tree entry, and the loop's is_active_cb kills tick() even if a future
	# refactor re-enables processing.
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.start()
	return game


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("EDITOR_CLICK_FAIL: " + msg)
	get_tree().quit(1)
