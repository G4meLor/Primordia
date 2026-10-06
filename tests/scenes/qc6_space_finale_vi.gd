# QC round 6 — agent-space-finale probe: the FINALE under locale VI + the
# CLICK dismiss path (round 5 only proved the KEY dismiss; the task's canon
# is "click dismiss"). Rides the qc5_space_finale shape:
#   boot REAL Game (all six stages registered, manual stepping) → pin
#   start_new_game seed → REAL switch to space → i18n.set_lang("vi") (the
#   exact call pause.gd:152's language button makes) → debug_seed_colonies
#   (the documented cheat) + a real held F to 3 thriving → AWAKENS banner
#   text latched (EN or VI?) → PULLS objective text latched → real steer to
#   the core (d<60 → endingDone) → veil at alpha 1 → purple pixel count of
#   the tr("THE CHAOS CORE ACCEPTS YOU") patch + png evidence saved →
#   translation reads (i18n resolve for the 3 finale keys — pure getters) →
#   a REAL mouse click dismisses → calm objective text latched (VI or EN?).
# Every input rides the real pipeline (Input.parse_input_event + flush);
# direct sim calls: debug_seed_colonies ONLY.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const WORLD_SEED := 48879  # 0xBEEF — the proven M6 pin
const DT := 1.0 / 60.0

var _phase := "boot"
var _frames := 0
var _game: Variant = null
var _held := {}
var _grab_next := false

# latched observations
var awakens_title := ""     # the banner title as the HUD received it (VI locale!)
var awakens_subtitle := ""
var pulls_obj := ""         # the PULLS objective line (VI locale)
var calm_obj := ""          # the calm objective line latched post-restore/ending
var ending_fired := false
var veil_purple := -1
var accepts_resolved := ""  # i18n resolve of the title key
var calm_resolved := ""     # i18n resolve of the calm key
var awakens_resolved := ""  # i18n resolve of the banner title key (gap evidence)
var click_dismissed := false
var dismiss_t := -1.0
var lang_seen := ""

var _prev_dna := -1.0
var _prev_invuln := -1.0
var _d_bill := -1
var _d_exp := -1
var obj_text := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://qc6_finale_vi")


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > 60 * 240:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	match _phase:
		"boot":
			_game = _build_game()
			_game.step_for_testing(1, DT)
			_game.stages["menu"].start_new_game(0, "normal", WORLD_SEED)
			_phase = "card"
		"card":
			_game.step_for_testing(1, DT)
			if _game.transition == null:
				_game.switch_stage("space")
				_phase = "settle"
		"settle":
			_game.step_for_testing(1, DT)
			if _game.stages["space"].sim != null and _game.current.id == "space":
				# the REAL language path: the same call the pause menu's
				# language row makes (pause.gd:150-152)
				_game.i18n.set_lang("vi")
				lang_seen = String(_game.i18n.get_lang())
				print("QC6VI_LANDED lang=%s planets=%d dna=%d" % [
					lang_seen, _sim().planets.size(), int(_game.context.dna)])
				_phase = "seed_ff"
				_frames = 0
		"seed_ff":
			if _frames == 1:
				_sim().debug_seed_colonies()
				print("QC6VI_SEED colonies=%d" % _colonies())
				_press(KEY_F, true)
			_step_watch()
			if _thriving() >= 3:
				_press(KEY_F, false)
				_steer(_sim(), Vector2.ZERO)
				if awakens_title == "":
					_fail("seed_ff: 3 thriving but the AWAKENS banner was never latched")
					return
				print("QC6VI_AWAKENS title='%s' subtitle='%s' obj='%s'" % [
					awakens_title, awakens_subtitle, pulls_obj])
				_phase = "core_fly"
				_frames = 0
		"core_fly":
			_step_watch()
			var fin: Variant = _sim().finale
			if fin == null:
				_fail("core_fly: the finale vanished before the fly")
				return
			var fd: float = Vector2(float(fin["x"]) - float(_sim().sx),
					float(fin["y"]) - float(_sim().sy)).length()
			if fd < 60.0:
				_steer(_sim(), Vector2.ZERO)
				if not bool(_sim().endingDone):
					_fail("core_fly: d<60 but the ending never fired")
					return
				ending_fired = true
				print("QC6VI_ENDING obj_at_fire='%s'" % pulls_obj)
				_phase = "veil"
				_frames = 0
			elif _frames > 60 * 60:
				_fail("core_fly: never reached the core (%.0f px to go)" % fd)
				return
			else:
				_steer(_sim(), _hazard_desired(_sim(), Vector2(
					float(fin["x"]) - float(_sim().sx),
					float(fin["y"]) - float(_sim().sy))))
		"veil":
			# hands-off; the veil fades in — grab at alpha 1, save png evidence
			_step_watch()
			if _grab_next:
				_grab_next = false
				var img: Image = _grab()
				img.save_png("user://qc6_finale_vi/veil_vi.png")
				veil_purple = _count_purple(img)
				accepts_resolved = String(_game.i18n.tr_key("THE CHAOS CORE ACCEPTS YOU"))
				calm_resolved = String(_game.i18n.tr_key("the core sleeps — the sandbox is yours"))
				awakens_resolved = String(_game.i18n.tr_key("THE CHAOS CORE AWAKENS"))
				print("QC6VI_VEIL purple=%d accepts_resolved='%s' calm_resolved='%s' awakens_resolved='%s'" % [
					veil_purple, accepts_resolved, calm_resolved, awakens_resolved])
				_phase = "click"
				_frames = 0
			elif float(_sim().endingT) >= 2.2 and not bool(_sim().endingDismissed):
				_game._do_render(0.0)
				_grab_next = true
		"click":
			# the REAL click path (round 5 proved only the KEY path): a plain
			# mouse press at screen center during the veil
			if _frames == 1:
				var c := Vector2(float(_game.vw) / 2.0, float(_game.vh) / 2.0)
				_mouse_down(c)
			elif _frames == 2:
				_mouse_up()
			_game.step_for_testing(1, DT)
			_watch()
			if bool(_sim().endingDismissed):
				click_dismissed = true
				dismiss_t = float(_sim().dismissT)
				print("QC6VI_CLICK_DISMISS ok=true dismissT=%.2f obj='%s'" % [
					dismiss_t, calm_obj])
				_phase = "report"
				_frames = 0
			elif _frames > 60 * 8:
				_fail("click: the veil never dismissed on a real click (endingT=%.2f)" % [
					float(_sim().endingT)])
				return
		"report":
			_report()
			_phase = "done"
		"done":
			pass


# ---- per-frame watch + step -----------------------------------------------------

func _step_watch() -> void:
	_game.step_for_testing(1, DT)
	_watch()


func _watch() -> void:
	var hud: Variant = _game.stages["space"].hud_inst
	if hud == null:
		return
	if awakens_title == "":
		if hud._cur_banner != null and String(hud._cur_banner.get("title", "")).contains("CHAOS CORE"):
			awakens_title = String(hud._cur_banner["title"])
			awakens_subtitle = String(hud._cur_banner.get("subtitle", ""))
		for b in hud._banner_queue:
			if String(b.get("title", "")).contains("CHAOS CORE"):
				awakens_title = String(b["title"])
				awakens_subtitle = String(b.get("subtitle", ""))
	var obj: Variant = hud.show_objective
	if obj != null:
		obj_text = String(obj)
		if String(obj).contains("CHAOS CORE PULLS"):
			pulls_obj = String(obj)
		if String(obj).contains("core sleeps") or String(obj).contains("lõi đã ngủ"):
			calm_obj = String(obj)


# ---- helpers ---------------------------------------------------------------------

func _sim() -> Variant:
	return _game.stages["space"].sim


func _colonies() -> int:
	var n := 0
	for p in _sim().planets:
		if p["colony"] != null:
			n += 1
	return n


func _thriving() -> int:
	var n := 0
	for p in _sim().planets:
		if p["colony"] != null and float(p["colony"]["pop"]) >= 20.0:
			n += 1
	return n


func _steer(sim: Variant, desired: Vector2) -> void:
	var want := {
		"KeyW": desired.y < -20.0, "KeyS": desired.y > 20.0,
		"KeyA": desired.x < -20.0, "KeyD": desired.x > 20.0,
	}
	for pair in [["KeyW", KEY_W], ["KeyA", KEY_A], ["KeyS", KEY_S], ["KeyD", KEY_D]]:
		var code: String = pair[0]
		var kc: int = pair[1]
		if bool(want[code]) and not _held.has(code):
			_press(kc, true)
			_held[code] = true
		elif not bool(want[code]) and _held.has(code):
			_press(kc, false)
			_held.erase(code)


func _press(kc: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = kc
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _mouse_down(screen_pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = screen_pos
	m.global_position = screen_pos
	Input.parse_input_event(m)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = screen_pos
	ev.global_position = screen_pos
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _mouse_up() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _hazard_desired(sim: Variant, want: Vector2) -> Vector2:
	var pos := Vector2(float(sim.sx), float(sim.sy))
	var sun_d := pos.length()
	if sun_d < 280.0 and sun_d > 0.001:
		want = pos / sun_d * 300.0 + want * 0.3
	for bh in sim.blackHoles:
		var off := pos - Vector2(float(bh["x"]), float(bh["y"]))
		var bd := off.length()
		if bd < 500.0 and bd > 0.001:
			want = want + off / bd * (500.0 - bd) * 2.0
	return want


func _grab() -> Image:
	return _game.get_viewport().get_texture().get_image()


func _count_purple(img: Image) -> int:
	if img == null:
		return -1
	var n := 0
	var box := [float(_game.vw) / 2.0 - 260.0, float(_game.vh) / 2.0 - 140.0,
			float(_game.vw) / 2.0 + 260.0, float(_game.vh) / 2.0 - 100.0]
	for yy in range(int(box[1]), int(box[3]) + 1):
		for xx in range(int(box[0]), int(box[2]) + 1):
			if xx < 0 or xx >= img.get_width() or yy < 0 or yy >= img.get_height():
				continue
			var c := img.get_pixel(xx, yy)
			var p := Vector3(roundf(c.r * 255.0), roundf(c.g * 255.0), roundf(c.b * 255.0))
			if p.x >= 180.0 and p.z >= 230.0 and p.y >= 120.0 and p.y <= 210.0:
				n += 1
	return n


func _report() -> void:
	print("QC6VI_SUMMARY lang=%s awakens='%s' pulls='%s' calm='%s' ending=%s purple=%d click_dismiss=%s dismissT=%.2f" % [
		lang_seen, awakens_title, pulls_obj, calm_obj, str(ending_fired),
		veil_purple, str(click_dismissed), dismiss_t])
	print("QC6VI_ALL_OK")
	get_tree().quit(0)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(WORLD_SEED)
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


func _fail(msg: String) -> void:
	printerr("QC6VI_FAIL: " + msg)
	get_tree().quit(1)
