# Editor REAL-input click test — Task 8 (the re-routed T6 editor acceptance
# criterion). Opens the editor through the REAL KeyE pipeline (bot-driver
# pattern), then presses a synthetic mouse button at the flagella '+' button —
# the rect read from the editor's OWN row-rect records, populated by its draw
# pass — and one fixed step later the gene has bumped and the DNA dropped by
# part_cost (Global Constraint 8: the gate goes through the actual input
# pipeline + the game's blocked-branch overlay dispatch, never a direct
# editor.click_part call).
#
# Task-8 creature extension: the same real-input path continues through the
# stage handoff — a real click buys a LEG in the cell editor, a real click on
# the drawn 🐢 CRAWL ASHORE button walks the transition to the creature stage,
# a real Tab opens the CREATURE editor (mode + tutorial counter), and a real
# click toggles a gene there; the tutCreature engine then finishes on the
# scripted actioned counters (the cell phase's sanctioned pattern).
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
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")
const PartsScript := preload("res://src/evo/parts.gd")

const SEED := 0xED17
const DT := 1.0 / 60.0
const TRANSITION_POLL := 300
const CARD_STEPS := 180
const TIMEOUT_FRAMES := 3600

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
			if not _read_plus_rect("flagella"):
				return
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
			_phase = "legs_open"
		# ---- task-8 creature extension -----------------------------------------
		"legs_open":
			# a real KeyE re-opens the cell editor; a real click then buys the
			# LEG that arms the shore gate
			_driver.tap_key(KEY_E)
			_game.step_for_testing(1, DT)
			if not bool(_game.editor["open"]):
				_fail("the second KeyE did not re-open the cell editor")
				return
			_game._do_render(0.0)
			_phase = "legs_read"
		"legs_read":
			if not _read_plus_rect("legs"):
				return
			_level_before = int(_game.context.genome["legs"])
			_dna_before = int(_game.context.dna)
			_phase = "legs_click"
		"legs_click":
			_driver.mouse_down(_plus)
			_game.step_for_testing(1, DT)
			_driver.mouse_up()
			if int(_game.context.genome["legs"]) != _level_before + 1:
				_fail("the legs click did not bump legs")
				return
			_driver.tap_key(KEY_E)
			_game.step_for_testing(1, DT)  # blocked branch closes (dirty save)
			if bool(_game.editor["open"]):
				_fail("the legs-phase KeyE did not close the editor")
				return
			# live steps: the sim's per-frame shore gate reads the new legs
			# (CellStage.ts:485 shape) on the next unblocked update
			_game.step_for_testing(2, DT)
			_phase = "shore_read"
		"shore_read":
			# the drawn 🐢 CRAWL ASHORE button — the stage repositions the sim's
			# rect every draw pass, so keep the sim + renders cycling while
			# polling (the legs buy only landed after the last queued draw)
			_game.step_for_testing(1, DT)
			_game._do_render(0.0)
			var r: Dictionary = _game.current.sim.shoreRect
			if float(r["x"]) < 100.0:
				return
			_phase = "shore_click"
		"shore_click":
			var r2: Dictionary = _game.current.sim.shoreRect
			_driver.mouse_down(Vector2(float(r2["x"]) + float(r2["w"]) / 2.0,
					float(r2["y"]) + float(r2["h"]) / 2.0))
			_game.step_for_testing(1, DT)
			_driver.mouse_up()
			if _game.transition == null:
				_fail("the shore click did not start the creature handoff")
				return
			_phase = "walk"
		"walk":
			# out (0.55) → switch_stage('creature') → card (2.2) → in (0.6)
			if _game.context.stage != "creature":
				_game.step_for_testing(1, DT)
				return
			for i in CARD_STEPS:
				_game.step_for_testing(1, DT)
			if _game.current.id != "creature" or _game.transition != null:
				_fail("the creature stage did not arrive clean (id=%s transition=%s)"
						% [str(_game.current.id), str(_game.transition)])
				return
			var tut: Variant = _game.current.tutorial
			if tut == null or String(tut._flag_key) != "tutCreature":
				_fail("the tutCreature tutorial did not build on creature enter")
				return
			_phase = "tab"
		"tab":
			# real Tab in the creature stage — the editor opens in CREATURE mode
			_driver.tap_key(KEY_TAB)
			_game.step_for_testing(1, DT)
			if not bool(_game.editor["open"]):
				_fail("Tab through the real pipeline did not open the creature editor")
				return
			if String(_game.editor["mode"]) != "creature":
				_fail("the editor opened in mode %s" % str(_game.editor["mode"]))
				return
			if int(_game.current.sim.tut["editorOpened"]) != 1:
				_fail("the creature editorOpened counter did not bump")
				return
			_game._do_render(0.0)
			_phase = "creature_read"
		"creature_read":
			if not _read_plus_rect("arms"):
				return
			_level_before = int(_game.context.genome["arms"])
			_dna_before = int(_game.context.dna)
			_phase = "creature_click"
		"creature_click":
			_driver.mouse_down(_plus)
			_game.step_for_testing(1, DT)
			_driver.mouse_up()
			var g3: Dictionary = _game.context.genome
			if int(g3["arms"]) != _level_before + 1:
				_fail("the creature click did not bump arms (%d → %s)"
						% [_level_before, str(g3["arms"])])
				return
			var arms_cost: int = PartsScript.part_cost(PartsScript.part_by_id("arms"), _level_before)
			if int(_game.context.dna) != _dna_before - arms_cost:
				_fail("creature dna did not drop by part_cost")
				return
			# the tutCreature table finishes on the live stage updates once the
			# actioned counters are driven (the cell phase's sanctioned pattern)
			_game.current.sim.tut["actioned"] = 2
			_driver.tap_key(KEY_E)
			_game.step_for_testing(1, DT)  # blocked branch: editor.update closes
			if bool(_game.editor["open"]):
				_fail("the creature KeyE did not close the editor")
				return
			for i in 3:
				_game.step_for_testing(1, DT)
			var tut3: Variant = _game.current.tutorial
			if tut3 == null or int(tut3.step_index) < 3 or bool(tut3.active):
				_fail("the creature tutorial did not finish (step_index=%s active=%s)"
						% [str(tut3.step_index if tut3 != null else -1),
								str(tut3.active if tut3 != null else null)])
				return
			if String(_game.context.flags.get("tutCreature", "")) != "done":
				_fail("the tutCreature flag did not persist")
				return
			# test hygiene: the dirty closes + the shore flush wrote a real slot
			var dir := DirAccess.open("user://saves")
			if dir != null:
				dir.remove("slot0.json")
			print("EDITOR_CLICK_OK flagella=%d legs=%d arms=%d dna=%d tut_creature=done" % [
					int(_game.context.genome["flagella"]), int(_game.context.genome["legs"]),
					int(g3["arms"]), int(_game.context.dna)])
			_phase = "done"
			_done = true
			get_tree().quit(0)


# ---- helpers (the T6 trap pattern, verbatim) -----------------------------------

## The '+' rect for a part row, read from the LIVE stage's editor row-rect
## records (draw-populated). Returns false while the records are pending.
func _read_plus_rect(part_id: String) -> bool:
	var rects: Array = _game.current.editor_inst.row_rects
	if rects.is_empty():
		return false
	var found := {}
	for rr in rects:
		if rr["btn"] != null and String(rr["btn"]) == "+" \
				and String(rr["row"]["kind"]) == "part" \
				and String(rr["row"]["def"]["id"]) == part_id:
			found = rr["r"]
	if found.is_empty():
		_fail("no %s '+' rect in the editor's row-rect records" % part_id)
		return false
	_plus = Vector2(float(found["x"]) + float(found["w"]) / 2.0,
			float(found["y"]) + float(found["h"]) / 2.0)
	return true


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
	game.register(CreatureStageScript.new(game))
	game.start()
	return game


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("EDITOR_CLICK_FAIL: " + msg)
	get_tree().quit(1)
