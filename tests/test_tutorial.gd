# Tests for src/ui/tutorial.gd — the step engine port (Task 8). Ports the
# tutorial describe block of Spore tests/features.test.ts (advance on done
# conditions, finish persists the flag per slot, a fresh Tutorial for a done
# key starts inactive) plus the cell stage's REAL 5-step table reacting to
# driven sim counters (TS CellStage.ts:253-260 — the stage builds the steps,
# the test drives sim.tut / context.genome and watches step_index move).
# Path-based extends + preload-by-path per the -s runner rules.
extends "res://tests/test_base.gd"

const TutorialScript := preload("res://src/ui/tutorial.gd")
const GameInputScript := preload("res://src/core/input.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CellSimScript := preload("res://src/game/cell/cell_sim.gd")
const RngScript := preload("res://src/core/rng.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const DT := 1.0 / 60.0
const SCRATCH := "user://test_tutorial_settings.cfg"

# EN locale must be forced: tr_key falls back to the key only in EN, and the
# suite shares one process (test_i18n.gd may have left another locale).
func _en() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_tutorial_settings.cfg")
		dir.remove("test_tutorial_settings.cfg.tmp")
	TranslationServer.set_locale("en")


## Duck-typed game for the headless UI tests (the UI classes read game.context/
## game.input/game.i18n/game.hud and call game.save_all()/set_cursor()).
class MockGame extends RefCounted:
	var context: Variant
	var input: Variant
	var i18n: Variant
	var vw := 800.0
	var vh := 600.0
	var toasts: Array = []
	var saves := 0
	var cursors: PackedStringArray = []
	var hud: Dictionary = {}

	func _init() -> void:
		context = ContextScript.new(77)
		input = GameInputScript.new()
		i18n = I18nScript.new(SCRATCH)
		i18n.set_lang("en")
		hud = {
			"toast": func(text: String, kind: String, icon: String) -> void:
				toasts.append([text, kind, icon]),
		}

	func save_all() -> bool:
		saves += 1
		return true

	func set_cursor(c: String) -> void:
		cursors.append(c)

	func hover_cursor() -> void:
		cursors.append("pointer")


var _hits := 0


func _done_a() -> bool:
	_hits += 1
	return _hits >= 2


func _never_done() -> bool:
	return false


# ---- features.test.ts: 'advances on conditions, finishes, and persists' ----

func test_advance_finish_and_persist() -> void:
	_en()
	_hits = 0
	var g: Variant = MockGame.new()
	var steps: Array = [
		{"id": "a", "text": "step A", "done": _done_a},
		{"id": "b", "text": "step B", "done": _never_done},
	]
	var tut: Variant = TutorialScript.new(g, "tutTest", steps)
	ok(tut.active, "fresh tutorial is active (flag unset)")
	eq(int(tut.step_index), 0, "starts on step 0")
	tut.update(DT)  # hits=1 → not done
	eq(int(tut.step_index), 0, "condition not met holds the step")
	tut.update(DT)  # hits=2 → done
	eq(int(tut.step_index), 1, "done() true advances")
	tut.finish()
	eq(bool(tut.active), false, "finish deactivates")
	eq(String(g.context.flags.get("tutTest", "")), "done", "flag persists per slot")
	eq(int(g.saves), 1, "finish flushes a save (stage-state flush comment)")
	# a fresh Tutorial for the same key starts inactive
	var again: Variant = TutorialScript.new(g, "tutTest", steps)
	eq(bool(again.active), false, "fresh Tutorial for a done key starts inactive")


# ---- the cell stage's real 5-step table (CellStage.ts:253-260) -------------

func test_cell_stage_steps_exact_table() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = CellStageScript.new(g)
	# headless: the scene layer never entered the tree — hand it a sim so the
	# step lambdas read the same counters the real stage would
	stage.sim = CellSimScript.new(g.context, RngScript.new_from(5), {})
	var steps: Array = stage._build_tutorial_steps()
	eq(steps.size(), 5, "the cell stage ships exactly 5 steps")
	eq(String(steps[0]["id"]), "move", "step ids are TS-verbatim")
	eq(String(steps[1]["id"]), "eat", "step ids are TS-verbatim")
	eq(String(steps[2]["id"]), "editor", "step ids are TS-verbatim")
	eq(String(steps[3]["id"]), "kill", "step ids are TS-verbatim")
	eq(String(steps[4]["id"]), "legs", "step ids are TS-verbatim")
	# exact TS step texts (the tutorial draws them through tr_key)
	eq(String(steps[0]["text"]), "Hold LEFT MOUSE — swim toward the cursor.", "step 1 text")
	eq(String(steps[1]["text"]), "Bump into the green bits to EAT them. Food is DNA.", "step 2 text")
	eq(String(steps[2]["text"]), "Press E — the EDITOR. Buy parts with DNA (try a Flagellum).", "step 3 text")
	eq(String(steps[3]["text"]), "Smaller cells are FOOD — bite one (E first to upgrade if it fights back!).", "step 4 text")
	eq(String(steps[4]["text"]), "Buy a LEG (65 DNA), then press the 🐢 CRAWL ASHORE button.", "step 5 text")


func test_cell_stage_steps_react_to_driven_counters() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = CellStageScript.new(g)
	stage.sim = CellSimScript.new(g.context, RngScript.new_from(5), {})
	var tut: Variant = TutorialScript.new(g, "tutCell", stage._build_tutorial_steps())
	eq(int(tut.step_count), 5, "5 steps")
	eq(int(tut.step_index), 0, "starts on the move step")

	# step 1 'move': sim.tut.moved > 140
	stage.sim.tut["moved"] = 140.0
	tut.update(DT)
	eq(int(tut.step_index), 0, "moved == 140 does not advance (strict >)")
	stage.sim.tut["moved"] = 141.0
	tut.update(DT)
	eq(int(tut.step_index), 1, "moved > 140 advances")

	# step 2 'eat': sim.tut.eaten >= 3
	stage.sim.tut["eaten"] = 2
	tut.update(DT)
	eq(int(tut.step_index), 1, "eaten 2 holds")
	stage.sim.tut["eaten"] = 3
	tut.update(DT)
	eq(int(tut.step_index), 2, "eaten 3 advances")

	# step 3 'editor': sim.tut.editorOpened >= 1 (the stage's KeyE branch
	# increments it — here the counter is driven directly)
	stage.sim.tut["editorOpened"] = 1
	tut.update(DT)
	eq(int(tut.step_index), 3, "editorOpened advances")

	# step 4 'kill': sim.tut.killed >= 1
	stage.sim.tut["killed"] = 1
	tut.update(DT)
	eq(int(tut.step_index), 4, "killed advances")

	# step 5 'legs': reads game.context.genome.legs — not a sim counter
	stage.sim.tut["killed"] = 5
	tut.update(DT)
	eq(int(tut.step_index), 4, "more kills hold the legs step (it polls the genome)")
	eq(float(g.context.genome.get("legs", 0)), 0.0, "starter genome is legless")
	g.context.genome["legs"] = 1
	tut.update(DT)
	eq(int(tut.step_index), 5, "legs >= 1 completes the table")
	eq(bool(tut.active), false, "natural end finishes the tutorial")
	eq(String(g.context.flags.get("tutCell", "")), "done", "tutCell flag persists")
	eq(g.toasts.size(), 1, "the natural end fires the good-luck toast")
	if g.toasts.size() == 1:
		eq(String(g.toasts[0][0]), "Editor tutorial done — the rest is evolution. Good luck.",
				"finish toast text is the TS key")
		eq(String(g.toasts[0][1]), "good", "finish toast kind good")
		eq(String(g.toasts[0][2]), "🎓", "finish toast icon")
	eq(int(g.saves), 1, "finish flushed one save")


func test_inactive_engine_never_advances() -> void:
	_en()
	_hits = 0
	var g: Variant = MockGame.new()
	g.context.flags["tutCell"] = "done"
	var stage: Variant = CellStageScript.new(g)
	stage.sim = CellSimScript.new(g.context, RngScript.new_from(5), {})
	var tut: Variant = TutorialScript.new(g, "tutCell", stage._build_tutorial_steps())
	eq(bool(tut.active), false, "done flag → inactive on construction")
	stage.sim.tut["moved"] = 99999.0
	tut.update(DT)
	eq(int(tut.step_index), 0, "inactive engine never advances")
	tut.finish()
	eq(int(g.saves), 0, "finish on an inactive engine is a no-op (TS guard)")


# ---- the skip chip: 0.4s HOLD (tutorial.ts:49-68) ------------------------------

func test_skip_chip_needs_a_0_4s_hold() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = CellStageScript.new(g)
	stage.sim = CellSimScript.new(g.context, RngScript.new_from(5), {})
	var tut: Variant = TutorialScript.new(g, "tutCell", stage._build_tutorial_steps())
	# press INSIDE the chip rect (the pre-draw stub sits at (0,0) 92x30)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10.0, 10.0)
	g.input.handle_event(press)
	ok(g.input.is_down(), "mouse held")
	tut.update(0.2)
	eq(bool(tut.active), true, "0.2s hold does not skip")
	tut.update(0.2)
	eq(bool(tut.active), true, "0.4s hold does not skip (strictly > 0.4)")
	tut.update(0.2)
	eq(bool(tut.active), false, "0.6s hold skips")
	eq(String(g.context.flags.get("tutCell", "")), "done", "skip persists the flag")
	eq(int(g.saves), 1, "skip flushes the stage-state save (TS comment)")
	eq(bool(g.input.was_clicked()), false, "the skip consumes the click (TS takeClick)")
	eq(g.toasts.size(), 0, "a SKIPPED tutorial fires no good-luck toast (natural end only)")
