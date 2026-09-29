# Six-moment pixel-assert visual suite — Task 10, the §5.2 visual-parity
# criterion as a repeatable test. Extends the task-7 capture-and-PIL-assert
# pattern (tests/scenes/test_visual_cell.gd) to a scripted GAME: one seed
# plays through the real menu, the real cell stage, a forced chaos event, the
# real editor (KeyE + a real purchase click), a forced death and a titled
# transition card — capturing one PNG per moment under user://visual_suite/,
# then running tools/visual_assert.py (the per-moment assert table) via
# OS.execute and mirroring its exit code.
#
# Moments + captures:
#   menu.png / menu_drift.png — the title view, twice 1 s apart (drifters)
#   cell_early.png            — gameplay just past the arrival invuln (~3 s)
#   chaos_banner.png          — t≈60 s, meteor forced via sim.chaos.trigger;
#                               the banner shows when the warn→apply
#                               conversion fires the onApply hud banner
#   editor_a/b.png            — the editor open (real KeyE) and after a real
#                               mouse purchase click (DNA footer changes)
#   death.png                 — php forced 0 (test seam), the fade ~0.8 s in
#   card.png                  — a titled go_to card mid-display
# Asserts: structural only (see the checker). References under
# tests/fixtures/visual/ are RECORDED captures, never byte-diffed.
#
# Capture timing: every moment is render→shot across a frame boundary — the
# step tick queues the layers via game._do_render, the draw pass lands at that
# frame's end, the NEXT tick reads the viewport texture (the T7 arm/shot
# pattern, generalized).
#
# Run (xvfb): tools/test_visual_suite.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_visual_suite.tscn
# Prints VISUAL_SUITE_OK <moment> per capture; the checker's verdict mirrors
# to VISUAL_SUITE_ALL_OK / VISUAL_SUITE_FAIL; exit 0/1.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")
const PartsScript := preload("res://src/evo/parts.gd")

const SEED := 0x51EED
const DT := 1.0 / 60.0
const OUT_DIR := "user://visual_suite"
const TRANSITION_POLL := 600
const CARD_IN_STEPS := 168      # card 132 + in 36
const CHAOS_TARGET := 60.0      # sim seconds before forcing the event
const TIMEOUT_FRAMES := 9000    # real-frame guard for the WHOLE run

var _phase := "build"
var _frames := 0
var _game: Variant = null
var _driver: Variant = null
var _done := false
var _plus := Vector2.ZERO
var _dna_before := 0


func _ready() -> void:
	_driver = BotDriverScript.new()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


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
			_game.step_for_testing(5, DT)
			if _game.context.stage != "menu":
				_fail("expected the menu after 5 steps, got %s" % _game.context.stage)
				return
			_phase = "menu_render"
		"menu_render":
			_game._do_render(0.0)
			_phase = "menu_a"
		"menu_a":
			if not _shot("menu.png", "menu"):
				return
			_game.step_for_testing(60, DT)  # 1 s of title-screen ambience
			_phase = "menu_render2"
		"menu_render2":
			_game._do_render(0.0)
			_phase = "menu_b"
		"menu_b":
			if not _shot("menu_drift.png", "menu_drift"):
				return
			# new life through the REAL menu (the bot-arc prologue shape)
			_game.current.start_new_game(0, "normal", SEED)
			var steps := 0
			while _game.context.stage != "cell" and steps < TRANSITION_POLL:
				_game.step_for_testing(1, DT)
				steps += 1
			if _game.context.stage != "cell":
				_fail("cell stage not reached within %d steps" % TRANSITION_POLL)
				return
			_game.step_for_testing(CARD_IN_STEPS, DT)
			_phase = "settle_invuln"
		"settle_invuln":
			# the T7 condition-based settle: step until the arrival invuln
			# decays so the player paints at alpha 1 (~3 s post-card)
			var sim: Variant = _game.current.sim
			if float(sim.invuln) > 0.0:
				_game.step_for_testing(2, DT)
				return
			_phase = "cell_render"
		"cell_render":
			_game._do_render(0.0)
			_phase = "cell_shot"
		"cell_shot":
			if not _shot("cell_early.png", "cell_early"):
				return
			_phase = "to_chaos"
		"to_chaos":
			var sim: Variant = _game.current.sim
			var remain := CHAOS_TARGET - float(sim.time)
			if remain > 0.0:
				_game.step_for_testing(ceili(remain * 60.0), DT)
			# the TS-true testing seam: the scheduler's trigger (the sim is the
			# scheduler's stage target). The warn→apply conversion in the next
			# updates fires the onApply hud banner — the moment asserted below.
			if not bool(sim.chaos.trigger("meteor", sim)):
				_fail("chaos trigger('meteor') failed")
				return
			print("VISUAL_SUITE_OK chaos-triggered at sim t=%.2f" % float(sim.time))
			_phase = "chaos_wait"
		"chaos_wait":
			var sim: Variant = _game.current.sim
			_game.step_for_testing(2, DT)
			var b: Variant = _game.current.hud_inst._cur_banner
			if b == null or float(b["t"]) < 0.35:
				return
			_game.step_for_testing(4, DT)
			_phase = "chaos_render"
		"chaos_render":
			_game._do_render(0.0)
			_phase = "chaos_shot"
		"chaos_shot":
			if not _shot("chaos_banner.png", "chaos_banner"):
				return
			_phase = "editor_open"
		"editor_open":
			# the editor-click test's real-pipeline shape (Task 8): park DNA,
			# drive the tutorial counters, open through the REAL KeyE
			_game.context.dna = 500
			_game.current.sim.tut["moved"] = 500.0
			_game.current.sim.tut["eaten"] = 3
			_driver.tap_key(KEY_E)
			_game.step_for_testing(1, DT)
			if not bool(_game.editor["open"]):
				_fail("KeyE through the real pipeline did not open the editor")
				return
			_dna_before = int(_game.context.dna)
			_phase = "editor_render_a"
		"editor_render_a":
			_game._do_render(0.0)  # queue layers → the draw pass records rows
			_phase = "editor_read"
		"editor_read":
			var rects: Array = _game.current.editor_inst.row_rects
			if rects.is_empty():
				return
			if not _shot("editor_a.png", "editor_a"):
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
			_phase = "editor_click"
		"editor_click":
			# REAL mouse press at the button center → the blocked-branch
			# editor.update buys the part → the DNA footer text changes
			var lvl_before: int = int(_game.context.genome["flagella"])
			_driver.mouse_down(_plus)
			_game.step_for_testing(1, DT)
			_driver.mouse_up()
			_game.step_for_testing(1, DT)
			var cost: int = PartsScript.part_cost(PartsScript.part_by_id("flagella"), lvl_before)
			if int(_game.context.dna) != _dna_before - cost:
				_fail("the purchase click did not spend part_cost (%d → %d, want %d)" % [
						_dna_before, int(_game.context.dna), _dna_before - cost])
				return
			if int(_game.context.genome["flagella"]) != lvl_before + 1:
				_fail("the purchase click did not bump flagella")
				return
			_phase = "editor_render_b"
		"editor_render_b":
			_game._do_render(0.0)
			_phase = "editor_shot_b"
		"editor_shot_b":
			if not _shot("editor_b.png", "editor_b"):
				return
			_driver.tap_key(KEY_E)  # close through the real pipeline
			_game.step_for_testing(1, DT)
			if bool(_game.editor["open"]):
				_fail("KeyE did not close the editor")
				return
			_game.current.sim.php = 0.0  # the death test seam (brief-mandated)
			_phase = "death_wait"
		"death_wait":
			var sim: Variant = _game.current.sim
			_game.step_for_testing(2, DT)
			if float(sim.deathFade) < 0.8:
				return
			_phase = "death_render"
		"death_render":
			_game._do_render(0.0)
			_phase = "death_shot"
		"death_shot":
			if not _shot("death.png", "death"):
				return
			# a titled card through the REAL go_to (the T9 veil, now asserted)
			_game.go_to("menu", {"title": "THE OCEAN REMEMBERS",
					"sub": "the suite's pinned card"})
			_phase = "card_wait"
		"card_wait":
			_game.step_for_testing(1, DT)
			var tr: Variant = _game.transition
			if tr == null or String(tr["phase"]) != "card" or float(tr["t"]) < 0.3:
				return
			_phase = "card_render"
		"card_render":
			_game._do_render(0.0)
			_phase = "card_shot"
		"card_shot":
			if not _shot("card.png", "card"):
				return
			_phase = "check"
		"check":
			_phase = "done"
			_run_checker()


# ---- helpers -------------------------------------------------------------------

## Save one capture on the tick AFTER its render phase (the draw pass has
## landed) and print the per-moment OK line.
func _shot(file_name: String, moment: String) -> bool:
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		_fail("save_png %s → %s" % [file_name, str(err)])
		return false
	print("VISUAL_SUITE_OK %s" % moment)
	return true


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	# Manual stepping ONLY — the T6 trap pattern (see test_bot_arc.gd): the
	# real _process would add wall-clock-clamped steps (nondeterministic).
	# set_process must come AFTER tree entry.
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	# the bot-arc registration order leaves the NOT-current cell stage's
	# canvases visible — they would draw once over the menu (main.gd's factory
	# path hides fresh instances; mirror that here so the menu moment captures
	# the actual title view)
	game._set_stage_visible(game.stages["cell"], false)
	game.start()
	return game


func _run_checker() -> void:
	var checker := ProjectSettings.globalize_path("res://tools/visual_assert.py")
	var out := ProjectSettings.globalize_path(OUT_DIR)
	var record := ProjectSettings.globalize_path("res://tests/fixtures/visual/reference.json")
	var output: Array = []
	var code := OS.execute("python3", [checker, out, "--record", record], output, true)
	for line in output:
		print(String(line).strip_edges())
	if code != 0:
		printerr("VISUAL_SUITE_FAIL: visual_assert.py exited %d" % code)
		get_tree().quit(1)
	else:
		print("VISUAL_SUITE_ALL_OK")
		get_tree().quit(0)


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("VISUAL_SUITE_FAIL: " + msg)
	get_tree().quit(1)
