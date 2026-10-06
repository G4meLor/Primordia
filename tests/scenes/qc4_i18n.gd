# QC round 4 — agent-i18n-1 (i18n/Text, VI locale, tree 43651af).
# ONE scene, 3 modes picked by user args (--mode=a|b|c after "--"):
#   a (xvfb): VI via user://settings.cfg → menu title shot → settings panel
#             (NGÔN NGỮ toggle EN↔VI live) → SỐNG MỚI → BEGIN → cell bot messy
#             900 sim-frames (toast latch) → editor E open (shot) → close →
#             Escape pause (shot). All beats latch HUD/menu strings + shot.
#   b (headless): wipe saves → FULL arc via the proven bot_space composition
#             (arrival→founding→tribe→civ→space→finale→ending→dismiss), latch
#             every HUD surface per stage each chunk, then save_all() slot0
#             (the real save path) → QC4I18N_B_OK.
#   c (xvfb): continue_slot(0) → fade-land wait (the brief's known-issue:
#             state reads AFTER the fade) → space sandbox shots + ff-hold shot
#             + latch → QC4I18N_C_OK.
# Latch law: game.current.hud_inst is a stub-dict — every HUD read goes through
# game.stages[<name>].hud_inst (the round-3 harness lesson); game.transition
# for the cards; menu stage's buttons for the labels. LATCH|stage|kind|text
# lines print incrementally so a timeout still leaves the evidence in the log.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")
const BotSpaceScript := preload("res://tests/bots/bot_space.gd")

const DT := 1.0 / 60.0
const SHOT_DIR := "user://qc4_shots"
const LATCH_PATH := "user://qc4_i18n_latch.json"
const CELL_FRAMES := 900          # mode a/b cell messy-play sim frames
const CHUNK := 20                 # sim frames stepped per _process tick
const B_TIMEOUT := 110000         # mode b frame budget (the full arc)
const A_TIMEOUT := 20000
const C_TIMEOUT := 12000

var mode := "a"
var _phase := "boot"
var _frames := 0
var _cell_done := 0
var _game: Variant = null
var _driver: Variant = null
var _bot: Variant = null
var _latch := {}                  # "stage|kind" -> {text: count}
var _done := false
var _toggle_pos := Vector2.ZERO   # the NGÔN NGỮ button center (click twice)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.substr(7)
	_force_vi()
	if mode == "b":
		_wipe_saves()
	print("QC4I18N_MODE=%s" % mode)


func _force_vi() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "lang", "vi")
	cfg.set_value("settings", "muted", false)
	cfg.save("user://settings.cfg")


func _wipe_saves() -> void:
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for i in 3:
			if dir.file_exists("slot%d.json" % i):
				dir.remove("slot%d.json" % i)


func _process(_dt: float) -> void:
	if _done:
		return
	_frames += 1
	var cap := A_TIMEOUT if mode == "a" else (B_TIMEOUT if mode == "b" else C_TIMEOUT)
	if _frames > cap:
		_flush_latch()
		_finish("QC4I18N_TIMEOUT mode %s phase %s frame %d" % [mode, _phase, _frames])
		return
	match mode:
		"a":
			_tick_a()
		"b":
			_tick_b()
		"c":
			_tick_c()


# ---- shared ---------------------------------------------------------------------

func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(BotCreatureScript.WORLD_SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.register(CreatureStageScript.new(game))
	game.register(TribeStageScript.new(game))
	game.register(CivStageScript.new(game))
	game.register(SpaceStageScript.new(game))
	game.start()
	return game


func _latch_all() -> void:
	if _game == null:
		return
	_game._do_render(0.0)  # rebuild the draw-synced surfaces (menu buttons,
	                       # panel rects) for the CURRENT view before reading
	for sname in ["menu", "cell", "creature", "tribe", "civ", "space"]:
		var st: Variant = _game.stages.get(sname)
		if st == null:
			continue
		var hud: Variant = st.get("hud_inst")
		if hud == null:
			continue
		for t in hud._toasts:
			_add(sname, "toast", String(t["text"]))
		if hud._cur_banner != null:
			_add(sname, "banner", String(hud._cur_banner["title"]))
			_add(sname, "banner_sub", String(hud._cur_banner["sub"]))
		for b in hud._banner_queue:
			_add(sname, "banner", String(b["title"]))
			_add(sname, "banner_sub", String(b["sub"]))
		if hud.show_objective != null:
			_add(sname, "objective", String(hud.show_objective))
		for f in hud._floaters:
			_add(sname, "floater", String(f["text"]))
	if _game.transition != null:
		_add("card", "title", String(_game.transition.get("title", "")))
		_add("card", "sub", String(_game.transition.get("sub", "")))
	var cur: Variant = _game.current
	if cur != null and cur.get("buttons") != null:
		for b in cur.buttons:
			_add("menu", "button", String(b["label"]))


func _add(stage: String, kind: String, text: String) -> void:
	if text.strip_edges() == "":
		return
	var key := "%s|%s" % [stage, kind]
	if not _latch.has(key):
		_latch[key] = {}
	var bucket: Dictionary = _latch[key]
	if not bucket.has(text):
		bucket[text] = 0
		print("LATCH|%s|%s|%s" % [stage, kind, text])
	bucket[text] = int(bucket[text]) + 1


func _shot(shot_name: String) -> void:
	if _game == null:
		return
	_game._do_render(0.0)  # the viewport texture must carry the current frame
	var img: Variant = _game.get_viewport().get_texture().get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var err: int = img.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	if err == OK:
		print("SHOT|%s" % shot_name)


func _flush_latch() -> void:
	var f := FileAccess.open(LATCH_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_latch, "  "))
		f.close()
	print("LATCH_FLUSHED keys=%d" % _latch.size())


func _finish(msg: String) -> void:
	if _done:
		return
	_done = true
	print(msg)
	_flush_latch()
	get_tree().quit(0)


## Real click on the menu button whose label contains `substr` (menu reads
## clicks against the previous frame's rects — down, step, up, step).
func _click_button(substr: String) -> bool:
	_game._do_render(0.0)  # the rects must match the CURRENT view
	var cur: Variant = _game.current
	if cur == null or cur.get("buttons") == null:
		return false
	for b in cur.buttons:
		if String(b["label"]).contains(substr):
			var c := Vector2(float(b["x"]) + float(b["w"]) / 2.0,
					float(b["y"]) + float(b["h"]) / 2.0)
			_toggle_pos = c
			_click_at(c)
			return true
	return false


func _click_at(c: Vector2) -> void:
	_driver.mouse_down(c)
	_game.step_for_testing(1, DT)
	_driver.mouse_up()
	_game.step_for_testing(2, DT)


func _menu_labels() -> Array:
	var out: Array = []
	var cur: Variant = _game.current
	if cur != null and cur.get("buttons") != null:
		for b in cur.buttons:
			out.append(String(b["label"]))
	return out


func _step_chunked(n: int) -> void:
	var left := n
	while left > 0:
		var k: int = mini(CHUNK, left)
		if _driver != null and _game.context.stage == "cell":
			_driver.step_loop(_game, k, DT)  # the real messy-play pipeline
		else:
			_game.step_for_testing(k, DT)
		left -= k
	_latch_all()


# ---- mode a: menu / settings / cell / editor / pause -----------------------------

func _tick_a() -> void:
	match _phase:
		"boot":
			_driver = BotDriverScript.new()
			_game = _build_game()
			_phase = "title_wait"
		"title_wait":
			if _frames > 30:
				_latch_all()
				_shot("a_title")
				if _click_button("CÀI ĐẶT"):
					_phase = "settings_wait"
				else:
					_finish("QC4I18N_A_FAIL no CÀI ĐẶT button")
		"settings_wait":
			if _frames > 60:
				_latch_all()
				_shot("a_settings")
				if _click_button("English"):  # the language buttons are EN/VI names
					_phase = "settings_en_wait"
				else:
					_finish("QC4I18N_A_FAIL no English button (buttons %s)" % str(_menu_labels()))
		"settings_en_wait":
			if _frames > 90:
				_latch_all()
				_shot("a_settings_en")
				if _click_button("Tiếng Việt"):  # back to VI
					_phase = "settings_back_wait"
				else:
					_finish("QC4I18N_A_FAIL no Tiếng Việt button")
		"settings_back_wait":
			if _frames > 120:
				_latch_all()
				if _click_button("Trở lại"):
					_phase = "main2_wait"
				else:
					_finish("QC4I18N_A_FAIL no Trở lại button")
		"main2_wait":
			if _frames > 150:
				_latch_all()
				_shot("a_main2")
				if _click_button("SỐNG MỚI"):
					_phase = "begin_wait"
				else:
					_finish("QC4I18N_A_FAIL no SỐNG MỚI button")
		"begin_wait":
			if _frames > 180:
				_latch_all()
				_shot("a_begin")
				if _click_button("BẮT ĐẦU") or _click_button("BEGIN"):
					_phase = "cell_entry"
				else:
					_finish("QC4I18N_A_FAIL no BEGIN button (buttons %s)" % str(_menu_labels()))
		"cell_entry":
			# the transition card eats clicks ~2.2s — wait it out (brief law)
			if _game.transition == null and _game.context.stage == "cell":
				_shot("a_cell_entry")
				_latch_all()
				_phase = "cell_play"
			elif _frames > 600:
				_finish("QC4I18N_A_FAIL cell never landed (stage %s)" % _game.context.stage)
		"cell_play":
			_step_chunked(CHUNK)
			_cell_done += CHUNK
			if _cell_done >= CELL_FRAMES:
				_shot("a_cell_mid")
				_driver.tap_key(KEY_E)
				_game.step_for_testing(3, DT)
				_phase = "editor_open"
		"editor_open":
			if _frames % 30 == 0:
				_game.step_for_testing(1, DT)
				print("A_EDITOR_STATE open=%s stage=%s" % [
						str(_game.editor.get("open")), _game.context.stage])
			if _frames > _cell_done + 90:
				_shot("a_editor")
				_latch_all()
				_driver.tap_key(KEY_E)
				_game.step_for_testing(3, DT)
				_phase = "editor_close"
		"editor_close":
			if _frames > _cell_done + 150:
				_driver.tap_key(KEY_ESCAPE)
				_game.step_for_testing(3, DT)
				_phase = "pause_wait"
		"pause_wait":
			if _frames > _cell_done + 210:
				_shot("a_pause")
				_latch_all()
				_finish("QC4I18N_A_OK")


# ---- mode b: full arc headless, latch everything, bridge save --------------------

func _tick_b() -> void:
	match _phase:
		"boot":
			_bot = BotSpaceScript.new()
			_driver = _bot.driver
			_game = _build_game()
			_phase = "arrival"
			print("B_ARRIVAL_BEGIN (the arc drives its own cell leg)")
		"arrival":
			var ra: String = _bot.bc.tb.cb.arrival_tick(_game)
			if ra == "OK":
				_latch_all()
				print("B_ARRIVAL_OK")
				_phase = "founding"
			elif ra != "":
				_flush_latch()
				_finish("QC4I18N_B_FAIL arrival: " + ra)
		"founding":
			var rf: String = _bot.bc.tb.cb.founding_tick(_game)
			if rf == "OK":
				_latch_all()
				_shot("b_entry_creature")
				print("B_FOUNDING_OK")
				_phase = "tribe"
			elif rf != "":
				_flush_latch()
				_finish("QC4I18N_B_FAIL founding: " + rf)
		"tribe":
			var rt: String = _bot.bc.tb.tribe_tick(_game)
			if rt == "OK":
				_latch_all()
				print("B_TRIBE_OK")
				_phase = "civ"
			elif rt != "":
				_flush_latch()
				_finish("QC4I18N_B_FAIL tribe (%s): %s" % [_bot.bc.tb._leg, rt])
		"civ":
			var rc: String = _bot.bc.civ_tick(_game)
			if rc == "OK":
				_latch_all()
				print("B_CIV_OK victory=%s" % str(_bot.bc.victory_card))
				_phase = "space"
			elif rc != "":
				_flush_latch()
				_finish("QC4I18N_B_FAIL civ (%s): %s" % [_bot.bc._leg, rc])
		"space":
			var rs: String = _bot.space_tick(_game)
			if rs == "OK":
				_latch_all()
				_phase = "post"
			elif rs != "":
				_flush_latch()
				_finish("QC4I18N_B_FAIL space (%s): %s" % [_bot._leg, rs])
		"post":
			# the ending dismissed, the sandbox handed back — a short sandbox
			# walk to latch the calm objective, then save via the REAL save
			# path for mode c's continue
			_step_chunked(CHUNK)
			_cell_done += CHUNK
			if _cell_done >= 240:
				var ok: bool = _game.save_all()
				print("B_SAVE_ALL ok=%s stage=%s" % [str(ok), _game.context.stage])
				_shot("b_space_end")
				_finish("QC4I18N_B_OK")


# ---- mode c: continue the space sandbox under xvfb, visual pass ------------------

func _tick_c() -> void:
	match _phase:
		"boot":
			_driver = BotDriverScript.new()
			_game = _build_game()
			_phase = "cont"
		"cont":
			if _frames > 30:
				var menu: Variant = _game.stages.get("menu")
				if menu == null:
					_finish("QC4I18N_C_FAIL no menu stage")
					return
				menu.continue_slot(0)
				print("C_CONTINUE_SENT")
				_phase = "restore_wait"
		"restore_wait":
			# the brief's known-issue: the real restore lands when the fade
			# lands — poll transition null + stage space, then extra margin
			if _game.transition == null and _game.context.stage == "space" and _frames > 400:
				_step_chunked(CHUNK)
				_shot("c_space_entry")
				print("C_SPACE_LANDED")
				_phase = "space_ui"
			elif _frames > 3000:
				_flush_latch()
				_finish("QC4I18N_C_FAIL space never restored (stage %s trans %s)" % [
						_game.context.stage, str(_game.transition)])
		"space_ui":
			_step_chunked(CHUNK)
			if _frames % 300 == 0:
				_shot("c_space_mid")
			if _frames > 900:
				_driver.press_key(KEY_F)
				_phase = "ff_hold"
		"ff_hold":
			_game.step_for_testing(CHUNK, DT)
			if _frames % 60 == 0:
				_latch_all()
			if _frames > 1200:
				_driver.release_key(KEY_F)
				_shot("c_ff")
				_latch_all()
				_finish("QC4I18N_C_OK")
