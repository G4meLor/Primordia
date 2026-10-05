# QC i18n playtest (round-1, agent-i18n-1) — QC-only scene, lives only in the
# QC slot worktree on rd-ds-02, never committed to the repo.
# Rides the REAL input pipeline (tests/bots/bot_driver.gd legs) at VI locale
# through every stage's ~2-minute window: menu -> settings -> new-life flow ->
# cell -> creature -> tribe -> civ -> space, screenshotting each screen into
# user://qc_i18n/ and printing every HUD string (objective / toasts / banner)
# so the EN-leftover + cut-text + overflow audit runs against live renders.
# Stage jumps ride the game's own go_to() (the same API the victory handlers
# call) with the REAL landfall card for cell->creature.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const DriverScript := preload("res://tests/bots/bot_driver.gd")

const OUT := "user://qc_i18n"
const STEPS_PER_FRAME := 5
const STAGE_STEPS := 6600            # ~110 game-seconds per stage
const SHOT_EVERY := 220              # _process frames between shots

var game: Variant = null
var driver: Variant = null
var phase := "boot"
var frames := 0
var steps_in_stage := 0
var shot_n := 0
var pend_click := ""                 # button label substring to click next
var pend_shots: Array = []           # extra named shots queued
var jump_after := ""                 # next go_to id when stage budget spent
var card := {}                       # card passed with the next go_to
var e_open := false
var esc_open := false
var lang := ""

var stages_plan := ["cell", "creature", "tribe", "civ", "space"]
var plan_i := -1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	print("QC_I18N boot t=", Time.get_ticks_msec())


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(0xBEEF)
	var g: Variant = GameScript.new(ctx)
	add_child(g)
	g.set_process(false)
	g.loop.is_active_cb = func() -> bool: return false
	g.register(MenuStageScript.new(g))
	g.register(CellStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	g.register(TribeStageScript.new(g))
	g.register(CivStageScript.new(g))
	g.register(SpaceStageScript.new(g))
	g.start()
	return g


var flat_seen := 0
var bisect_queue: Array = []
var restoring: Array = []
var bisect_arm := 0

func _shot(name_tag: String) -> void:
	game._do_render(0.0)
	var img: Image = game.get_viewport().get_texture().get_image()
	if img == null:
		print("QC_I18N SHOT_FAIL ", name_tag)
		return
	var p := "%s/%02d_%s.png" % [OUT, shot_n, name_tag]
	shot_n += 1
	img.save_png(p)
	var counts := {}
	var samples := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			counts["%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]] = int(counts.get("%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)], 0)) + 1
			samples += 1
	var top_key := ""
	var top_n := 0
	for k in counts:
		if counts[k] > top_n:
			top_n = counts[k]
			top_key = k
	var flat := float(top_n) / float(samples) >= 0.9
	var ct: Transform2D = game.get_viewport().canvas_transform
	var vp_size: Vector2 = game.get_viewport().get_visible_rect().size
	var win_size: Vector2 = Vector2(DisplayServer.window_get_size())
	print("STAT %s flat=%s top=%s:%d/%d unique=%d game_vw=%.1f vh=%.1f vp=%s win=%s ct_o=(%.1f,%.1f) ct_s=(%.3f,%.3f)" % [
			name_tag, str(flat), top_key, top_n, samples, counts.size(),
			game.vw, game.vh, str(vp_size), str(win_size), ct.origin.x, ct.origin.y, ct.x.x, ct.y.y])
	if flat:
		flat_seen += 1
		print("B4QCFLOW FLAT at %s (n=%d)" % [name_tag, flat_seen])
		if flat_seen == 1:
			bisect_queue = ["sky", "ground", "ents", "fx", "ui", "hud"]
			set_process(false)
			_run_bisect()


func _click_button(substr: String) -> bool:
	var menu: Variant = game.current
	if menu == null or menu.get("buttons") == null:
		return false
	for b in menu.buttons:
		var label := String(b.get("label", ""))
		if label.to_lower().contains(substr.to_lower()):
			var cx: float = float(b["x"]) + float(b["w"]) / 2.0
			var cy: float = float(b["y"]) + float(b["h"]) / 2.0
			print("QC_I18N CLICK btn '", label, "' at ", cx, ",", cy)
			driver.mouse_down(Vector2(cx, cy))
			game.step_for_testing(1, 1.0 / 60.0)
			driver.mouse_up()
			return true
	print("QC_I18N NO_BTN '", substr, "' labels=", _btn_labels())
	return false


func _btn_labels() -> Array:
	var out: Array = []
	var menu: Variant = game.current
	if menu != null and menu.get("buttons") != null:
		for b in menu.buttons:
			out.append(String(b.get("label", "")))
	return out


func _log_hud(tag: String) -> void:
	var st := String(game.context.stage)
	var lines: Array = []
	var hud: Variant = null
	if game.current != null and game.current.get("hud_inst") != null:
		hud = game.current.hud_inst
	if hud != null:
		if hud.get("show_objective") != null:
			lines.append("OBJ=" + String(hud.show_objective))
		if hud.get("_cur_banner") != null:
			lines.append("BANNER=" + String(hud._cur_banner["title"]) + " | " + String(hud._cur_banner.get("sub", "")))
		if hud.get("_banner_queue") != null:
			for b in hud._banner_queue:
				lines.append("BQ=" + String(b["title"]) + " | " + String(b.get("sub", "")))
		if hud.get("_toasts") != null:
			for t in hud._toasts:
				lines.append("TOAST=" + String(t["text"]))
	print("QC_I18N HUD tag=", tag, " stage=", st, " n=", lines.size())
	for l in lines:
		print("QC_I18N STR ", l)


func _dump_stage_labels(tag: String) -> void:
	# the stage's own visible UI strings, when it exposes label/ability rows
	var cur: Variant = game.current
	if cur == null:
		return
	if cur.get("hud_inst") != null and cur.hud_inst.get("abilities") != null:
		for ab in cur.hud_inst.abilities:
			print("QC_I18N ABILITY ", String(ab.get("key", "")), " label=", String(ab.get("label", ab.get("name", "?"))), " desc=", String(ab.get("desc", ab.get("tip", ""))))


func _process(_dt: float) -> void:
	frames += 1
	if frames > 20000:
		print("QC_I18N GLOBAL_TIMEOUT")
		get_tree().quit()
		return
	match phase:
		"boot":
			game = _build_game()
			driver = DriverScript.new()
			game.i18n.set_lang("vi")
			lang = String(game.i18n.get_lang())
			print("QC_I18N LANG=", lang, " vi_keys=", game.i18n.vi_key_count())
			phase = "menu_title"
			frames = 0
		"menu_title":
			# let the menu render a few frames, then shoot
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			game._do_render(0.0)
			if frames == 4:
				_shot("menu_title")
				_log_hud("menu")
				pend_click = "CÀI ĐẶT"
			if frames > 6 and pend_click != "":
				if _click_button(pend_click):
					pend_click = ""
					phase = "menu_settings"
					frames = 0
				else:
					# settings button missing — go straight to new life
					pend_click = "SỐNG MỚI"
					phase = "menu_to_new"
					frames = 0
		"menu_settings":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			game._do_render(0.0)
			if frames == 4:
				_shot("menu_settings")
				_log_hud("settings")
				# leave: click anything BACK-ish, else raw view reset (scene seam)
				var hit := false
				for s in ["back", "quay", "về", "trở"]:
					if _click_button(s):
						hit = true
						break
				if not hit:
					if game.current != null and game.current.get("_set_view") != null:
						game.current._set_view("title")
						print("QC_I18N SEAM settings->title (no BACK button found) labels=", _btn_labels())
				pend_click = "SỐNG MỚI"
				phase = "menu_to_new"
				frames = 0
		"menu_to_new":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			game._do_render(0.0)
			if frames > 3 and pend_click == "":
				pend_click = "SỐNG MỚI"
			if frames > 3 and pend_click != "":
				if _click_button(pend_click):
					pend_click = ""
					phase = "menu_new"
					frames = 0
		"menu_new":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			game._do_render(0.0)
			if frames == 4:
				_shot("menu_new")
				_log_hud("new")
				# find the begin button: BEGIN / BẮT ĐẦU
				var found := ""
				for l in _btn_labels():
					if l.contains("BẮT ĐẦU"):
						found = l
				if found != "":
					pend_click = found
					phase = "menu_begin"
					frames = 0
				else:
					print("QC_I18N NO_BEGIN labels=", _btn_labels())
					# fall back: start_new_game seam so the run continues
					game.current.start_new_game(0)
					phase = "ride"
					plan_i = 0
					frames = 0
					steps_in_stage = 0
		"menu_begin":
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			game._do_render(0.0)
			if frames > 3 and pend_click != "":
				if _click_button(pend_click):
					pend_click = ""
					phase = "ride"
					plan_i = 0
					frames = 0
					steps_in_stage = 0
		"ride":
			_ride_frame()
		"card_wait":
			# the transition card renders over the fade — shoot it, then resume
			game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
			game._do_render(0.0)
			if frames == 2 or frames == 8 or frames == 30:
				_shot("card_" + jump_after)
				_log_hud("card")
			if frames > 120:
				phase = "ride"
				frames = 0
				steps_in_stage = 1200  # the card ate part of the budget
		"done":
			pass


func _ride_frame() -> void:
	var st := String(game.context.stage)
	# real-input messy play: drift + click + ability taps
	if frames % 30 == 0:
		driver.move_mouse(Vector2(640 + 300.0 * sin(frames * 0.013), 360 + 200.0 * cos(frames * 0.017)))
	if frames % 90 == 20:
		driver.mouse_down(Vector2(640 + 250.0 * sin(frames * 0.031), 360 + 180.0 * cos(frames * 0.023)))
	if frames % 90 == 55:
		driver.mouse_up()
	if frames % 240 == 120:
		driver.tap_key(KEY_SPACE)
	if frames % 300 == 200:
		driver.tap_key(KEY_1)
	if frames % 360 == 300:
		driver.tap_key(KEY_2)
	# editor + pause exercise in cell/creature (the text-heavy panels)
	if (st == "cell" or st == "creature"):
		if frames == 400 and not e_open:
			driver.tap_key(KEY_E)
			e_open = true
		if frames == 430:
			_shot("editor_" + st)
			_log_hud("editor_" + st)
			_dump_stage_labels("editor_" + st)
		if frames == 500:
			driver.tap_key(KEY_E)
		if frames == 560 and not esc_open:
			driver.tap_key(KEY_ESCAPE)
			esc_open = true
		if frames == 590:
			_shot("pause_" + st)
			_log_hud("pause_" + st)
		if frames == 640:
			driver.tap_key(KEY_ESCAPE)
			esc_open = false
	game.step_for_testing(STEPS_PER_FRAME, 1.0 / 60.0)
	game._do_render(0.0)
	steps_in_stage += STEPS_PER_FRAME
	if frames % SHOT_EVERY == 0:
		_shot("live_" + st)
		_log_hud("live_" + st)
		_dump_stage_labels("live_" + st)
	if steps_in_stage >= STAGE_STEPS:
		e_open = false
		esc_open = false
		plan_i += 1
		if plan_i >= stages_plan.size():
			print("QC_I18N ALL_STAGES_DONE")
			_shot("final")
			phase = "done"
			get_tree().quit()
			return
		jump_after = stages_plan[plan_i]
		card = {}
		if jump_after == "creature":
			card = {"title": "THE LONG WALK",
					"sub": "400 million years of ambition, one nervous step onto land"}
		print("QC_I18N GO_TO ", jump_after)
		game.go_to(jump_after, card if not card.is_empty() else null)
		phase = "card_wait"
		frames = 0


# ---- flat bisect ----------------------------------------------------------------

func _layer_node(layer: String) -> Node2D:
	var st: Variant = game.current
	match layer:
		"sky": return st.get("sky_canvas")
		"ground": return st.get("ground_canvas")
		"ents": return st.get("ents_canvas")
		"fx": return st.get("fx_canvas")
		"ui": return st.get("ui_canvas")
		"hud": return st.get("hud_canvas")
	return null


func _run_bisect() -> void:
	print("B4QCFLOW bisect begin — stage=%s" % game.context.stage)
	for it in 8:
		if bisect_queue.is_empty():
			break
		var layer: String = bisect_queue.pop_front()
		var node: Node2D = _layer_node(layer)
		if node == null:
			continue
		node.visible = false
		game._do_render(0.0)
		await RenderingServer.frame_post_draw
		var img: Image = game.get_viewport().get_texture().get_image()
		var counts := {}
		var samples := 0
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				var c := img.get_pixel(x, y)
				counts["%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]] = int(counts.get("%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)], 0)) + 1
				samples += 1
		var top_key := ""
		var top_n := 0
		for k in counts:
			if counts[k] > top_n:
				top_n = counts[k]
				top_key = k
		img.save_png("%s/bisect_%02d_no_%s.png" % [OUT, shot_n, layer])
		shot_n += 1
		print("BISSTAT no_%s top=%s:%d/%d unique=%d" % [layer, top_key, top_n, samples, counts.size()])
		node.visible = true
	print("B4QCFLOW bisect done — quitting")
	get_tree().quit(0)
