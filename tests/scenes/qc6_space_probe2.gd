# QC round 6 — agent-space-arc probe 2. Real-input legs probe 1 could not
# reach or that need a fresh world: the Escape pause freeze, the cargo-full
# toast (EN), an IN-RANGE repair after sun damage, the ff generations climb,
# save→quit→continue restore (colony/cargo/dna + the [space-restore] log),
# the ending → save → continue sandbox hand-back (endingDone restored, no
# re-awaken), and the real window resize through the resize guard.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const WORLD_SEED := 51966  # 0xCAFE — r5 edge's seed (proven livable board)
const TIMEOUT_FRAMES := 36000

var _phase := "boot"
var _frames := 0
var _leg := 0
var _game: Variant = null
var _held := {}
var _toasts_seen: Array = []
var _banners_seen: Array = []
var _t0 := 0.0
var _t1 := 0.0
var _cargo_mark := 0
var _repair_dna0 := 0
var _gen0 := -1.0
var _save_cargo := 0
var _save_dna := 0
var _save_col := -1
var _save_gens := -1.0
var _post_dna := 0
var _awakens_latched := false
var _ending_done := false
var _resize_ok := false


func _process(_dt: float) -> void:
	_frames += 1
	_leg += 1
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
			_phase = "card"
		"card":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null:
				_game.switch_stage("space")
				_phase = "settle"
		"settle":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.current != null and _game.current.id == "space" \
					and _game.stages["space"].sim != null:
				print("QC6P2_LANDED dna=%d" % int(_game.context.dna))
				_phase = "pause_freeze"
				_leg = 0
		"pause_freeze":
			var sim: Variant = _game.stages["space"].sim
			if _leg == 5:
				_tap(KEY_ESCAPE)
			elif _leg == 10:
				_t0 = float(sim.time)
			elif _leg == 130:
				_t1 = float(sim.time)
				var frozen := absf(_t1 - _t0) < 0.0001
				print("QC6P2_PAUSE frozen=%s paused_flag=%s dt=%.3f" % [
					str(frozen), str(_game.paused), _t1 - _t0])
				_tap(KEY_ESCAPE)  # resume
			elif _leg == 190:
				var resumed := float(sim.time) > _t1
				print("QC6P2_RESUME advanced=%s" % str(resumed))
				_phase = "park_seed"
				_leg = 0
			_game.step_for_testing(1, 1.0 / 60.0)
		"park_seed":
			var sim2: Variant = _game.stages["space"].sim
			if _park_near(sim2):
				if _leg == 1:
					_tap(KEY_R)
				_game.step_for_testing(1, 1.0 / 60.0)
				_scan_toasts()
				if sim2.cargo.size() >= 1:
					_panel_click("seed")
					_phase = "seed_check"
					_leg = 0
				elif _leg > 60 * 12:
					_fail("park_seed no catch")
			else:
				if _leg == 1 or (_leg % 120 == 0 and sim2.cargo.size() == 0 and sim2.beamT <= 0.0):
					_tap(KEY_R)
				_scan_toasts()
		"seed_check":
			var sim3: Variant = _game.stages["space"].sim
			_steer(sim3, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 30:
				var col := -1
				for i in sim3.planets.size():
					if sim3.planets[i]["colony"] != null:
						col = i
				print("QC6P2_SEED colony=%s dna=%d" % [str(col), int(_game.context.dna)])
				_gen0 = -1.0
				if col >= 0:
					_gen0 = float(sim3.planets[col]["colony"]["generations"])
				_press(KEY_F, true)
				_phase = "ff_hold"
				_leg = 0
		"ff_hold":
			# a real held F — the ff churn climbs colony generations
			var sim4: Variant = _game.stages["space"].sim
			_steer(sim4, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 60 * 14:
				_press(KEY_F, false)
				var col2 := -1
				var gens := -1.0
				for i in sim4.planets.size():
					if sim4.planets[i]["colony"] != null:
						col2 = i
						gens = float(sim4.planets[i]["colony"]["generations"])
				var climb := gens > _gen0 if (_gen0 >= 0.0 and gens >= 0.0) else false
				print("QC6P2_FF gens %.2f->%.2f climb=%s ffHold=%.1f" % [
					_gen0, gens, str(climb), float(sim4.ffHold)])
				_cargo_mark = sim4.cargo.size()
				_phase = "fill_cargo"
				_leg = 0
		"fill_cargo":
			# catch on other planets up to cargo 4, then one more R in range
			# → the cargo-full toast (EN this run)
			var sim5: Variant = _game.stages["space"].sim
			if sim5.cargo.size() >= 4:
				if _leg == 1:
					_tap(KEY_R)  # parked in range → the full toast must fire
				_game.step_for_testing(1, 1.0 / 60.0)
				_scan_toasts()
				if _leg >= 40:
					var full := false
					for t in _toasts_seen:
						if t.contains("Cargo full"):
							full = true
					print("QC6P2_CARGOFULL cargo=%d toast=%s" % [sim5.cargo.size(), str(full)])
					_phase = "repair_dmg"
					_leg = 0
			else:
				if _park_near(sim5):
					if sim5.beamT <= 0.0 and _leg % 100 == 0:
						_tap(KEY_R)
					_game.step_for_testing(1, 1.0 / 60.0)
					_scan_toasts()
				if _leg > 60 * 90:
					_fail("fill_cargo stalled cargo=%d" % sim5.cargo.size())
		"repair_dmg":
			# into the sun band to dent the hull, back OUT, then to the parked
			# planet ring — repair clicked IN range this time
			var sim6: Variant = _game.stages["space"].sim
			var sun: Dictionary = sim6.sun
			var d := Vector2(float(sim6.sx) - float(sun["x"]), float(sim6.sy) - float(sun["y"])).length()
			if float(sim6.shp) > float(sim6.shpMax) * 0.6 and d < 1000.0:
				_steer(sim6, Vector2(float(sun["x"]) - float(sim6.sx), float(sun["y"]) - float(sim6.sy)))
			elif float(sim6.shp) < float(sim6.shpMax) * 0.55 and d < 190.0:
				_steer(sim6, Vector2(float(sun["x"]) - float(sim6.sx), float(sun["y"]) - float(sim6.sy)) * -1.0)
			elif float(sim6.shp) < float(sim6.shpMax) * 0.55 and d > 400.0:
				var tgt := _near_living(sim6)
				if tgt >= 0:
					var p: Dictionary = sim6.planets[tgt]
					_steer(sim6, Vector2(float(p["x"]) - float(sim6.sx), float(p["y"]) - float(sim6.sy)))
					var pd := Vector2(float(p["x"]) - float(sim6.sx), float(p["y"]) - float(sim6.sy)).length()
					if pd < float(p["r"]) + 120.0:
						_steer(sim6, Vector2.ZERO)
						_repair_dna0 = int(_game.context.dna)
						_panel_click("repair")
						_phase = "repair_check"
						_leg = 0
						return
				else:
					_steer(sim6, Vector2.ZERO)
			else:
				_steer(sim6, Vector2(float(sun["x"]) - float(sim6.sx), float(sun["y"]) - float(sim6.sy)))
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg > 60 * 40:
				_fail("repair_dmg never parked damaged (shp=%.0f d=%.0f)" % [float(sim6.shp), d])
		"repair_check":
			var sim7: Variant = _game.stages["space"].sim
			_steer(sim7, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 30:
				var cost := _repair_dna0 - int(_game.context.dna)
				var full := absf(float(sim7.shp) - float(sim7.shpMax)) < 0.01
				print("QC6P2_REPAIR cost=%d hull_full=%s (in-range click)" % [cost, str(full)])
				_phase = "save_cycle"
				_leg = 0
		"save_cycle":
			# real save → quit-to-title → CONTINUE → the restore must carry
			# colony/cargo/dna (counted AFTER the fade lands — brief law)
			var sim8: Variant = _game.stages["space"].sim
			if _leg == 1:
				_save_cargo = sim8.cargo.size()
				_save_dna = int(_game.context.dna)
				_save_col = -1
				for i in sim8.planets.size():
					if sim8.planets[i]["colony"] != null:
						_save_col = i
						_save_gens = float(sim8.planets[i]["colony"]["generations"])
				_game.save_all()
				_game.go_to("menu")
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null and _game.current != null \
					and _game.current.id == "menu":
				_game.stages["menu"].continue_slot(0)
				_phase = "verify_restore"
				_leg = 0
		"verify_restore":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 120:
				var sim9: Variant = _game.stages["space"].sim
				var col_ok: bool = _save_col < 0 or sim9.planets[_save_col]["colony"] != null
				_post_dna = int(_game.context.dna)
				print("QC6P2_RESTORE cargo=%d/%d colony=%s dna=%d/%d space_stage=%s" % [
					sim9.cargo.size(), _save_cargo, str(col_ok), _post_dna, _save_dna,
					str(_game.current.id == "space")])
				# the ending cycle: the documented cheat seeds 3 colonies
				sim9.debug_seed_colonies()
				_press(KEY_F, true)
				_phase = "ff_thriving"
				_leg = 0
		"ff_thriving":
			var sim10: Variant = _game.stages["space"].sim
			_steer(sim10, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			_scan_banners()
			if _leg >= 60 * 30:
				_press(KEY_F, false)
				var thriving := 0
				for p in sim10.planets:
					if p["colony"] != null and float(p["colony"]["pop"]) >= 20.0:
						thriving += 1
				print("QC6P2_THRIVING thriving=%d awakens=%s" % [thriving, str(_awakens_latched)])
				_phase = "core_fly"
				_leg = 0
		"core_fly":
			var sim11: Variant = _game.stages["space"].sim
			if sim11.finale != null:
				_steer(sim11, Vector2(float(sim11.finale["x"]) - float(sim11.sx),
					float(sim11.finale["y"]) - float(sim11.sy)))
			else:
				_steer(sim11, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_banners()
			if bool(sim11.endingDone):
				_ending_done = true
				_tap(KEY_SPACE)  # dismiss the veil (any key)
				_phase = "ending_save"
				_leg = 0
			elif _leg > 60 * 45:
				_fail("core_fly never ended (finale=%s)" % str(sim11.finale != null))
		"ending_save":
			var sim12: Variant = _game.stages["space"].sim
			_steer(sim12, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 30:
				print("QC6P2_ENDING done=%s dismissed=%s" % [
					str(bool(sim12.endingDone)), str(bool(sim12.endingDismissed))])
				_game.save_all()
				_game.go_to("menu")
				_phase = "ending_continue"
				_leg = 0
		"ending_continue":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null and _game.current != null \
					and _game.current.id == "menu":
				_game.stages["menu"].continue_slot(0)
				_phase = "ending_verify"
				_leg = 0
		"ending_verify":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 120:
				var sim13: Variant = _game.stages["space"].sim
				var reawaken := false
				_scan_banners()
				for b in _banners_seen:
					if String(b).contains("AWAKENS") and _leg > 130:
						reawaken = true
				print("QC6P2_SANDBOX endingDone=%s finale=%s dna=%d" % [
					str(bool(sim13.endingDone)), str(sim13.finale != null),
					int(_game.context.dna)])
				_phase = "resize"
				_leg = 0
		"resize":
			# the REAL WM resize path through the resize guard: a junk tiny
			# size (must be rejected) then a real size (must reflow)
			var sim14: Variant = _game.stages["space"].sim
			_steer(sim14, Vector2.ZERO)
			if _leg == 5:
				DisplayServer.window_set_size(Vector2i(300, 200))
			elif _leg == 65:
				var vw1 := int(_game.vw)
				DisplayServer.window_set_size(Vector2i(1280, 720))
				print("QC6P2_RESIZE_TINY vw_after_tiny=%d (guard floor?)" % vw1)
			elif _leg == 130:
				var vw2 := int(_game.vw)
				var vh2 := int(_game.vh)
				var sane := vw2 > 320 and vh2 > 200
				_resize_ok = sane
				print("QC6P2_RESIZE_BIG vw=%d vh=%d sane=%s" % [vw2, vh2, str(sane)])
				_phase = "report"
				_leg = 0
			_game.step_for_testing(1, 1.0 / 60.0)
		"report":
			var dupes: Dictionary = {}
			for t in _toasts_seen:
				dupes[t] = int(dupes.get(t, 0)) + 1
			var dupe_lines: Array = []
			for k in dupes:
				if int(dupes[k]) > 1:
					dupe_lines.append("%dx%s" % [dupes[k], k])
			print("QC6P2_TOASTS total=%d unique=%d dupes=%s banners=%s" % [
				_toasts_seen.size(), dupes.size(), str(dupe_lines), str(_banners_seen)])
			print("QC6P2_ALL_OK")
			get_tree().quit(0)
			_phase = "done"
		"done":
			pass


func _scan_banners() -> void:
	var hud: Variant = _game.stages["space"].hud_inst
	if hud == null:
		return
	var cur: Variant = hud.get("_cur_banner")
	if cur != null and (cur as Dictionary).has("title"):
		var s := String((cur as Dictionary)["title"])
		if not _banners_seen.has(s):
			_banners_seen.append(s)
		# r7 patch: the latch was read by the THRIVING report but never set —
		# the AWAKENS banner (pop >= 20 → THE PLANET AWAKENS) is the marker
		if s.contains("AWAKENS"):
			_awakens_latched = true
	for b in hud.get("_banner_queue"):
		var s2 := String(b["title"]) if (b as Dictionary).has("title") else str(b)
		if not _banners_seen.has(s2):
			_banners_seen.append(s2)
		if String(s2).contains("AWAKENS"):
			_awakens_latched = true


var _park_idx := -1
var _parked := false

func _park_near(sim: Variant) -> bool:
	var idx := _near_living(sim)
	if idx < 0:
		_parked = false
		return false
	var p: Dictionary = sim.planets[idx]
	var d := Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length()
	var v := Vector2(float(sim.svx), float(sim.svy))
	if d < float(p["r"]) + 110.0:
		_steer(sim, -v)
		if v.length() < 40.0:
			_steer(sim, Vector2.ZERO)
			_park_idx = idx
			_game.step_for_testing(1, 1.0 / 60.0)
			# r7 patch: park_seed's `if _leg == 1: _tap(KEY_R)` only fired when
			# the ship was parked on the very first frame of the phase — a slow
			# approach burned the leg counter and the beam never re-armed once
			# parked (the "no catch" dead end). Restart the phase clock at the
			# moment parking actually lands.
			if not _parked:
				_parked = true
				_leg = 0
			return true
		_park_idx = idx
		_parked = false
	else:
		_park_idx = idx
		_parked = false
		_steer(sim, Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)))
	_game.step_for_testing(1, 1.0 / 60.0)
	return false


func _near_living(sim: Variant) -> int:
	var best := -1
	var best_d := INF
	for i in sim.planets.size():
		var p: Dictionary = sim.planets[i]
		if p["eco"] == null:
			continue
		var d: float = Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length()
		if d < best_d:
			best_d = d
			best = i
	return best


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


func _scan_toasts() -> void:
	var hud: Variant = _game.stages["space"].hud_inst
	if hud != null:
		for t in hud._toasts:
			var s := String(t["text"])
			if not _toasts_seen.has(s):
				_toasts_seen.append(s)


func _panel_click(action: String) -> void:
	_game._do_render(0.0)
	var rows: Array = _game.stages["space"]._panel_rects
	for b in rows:
		if String(b["action"]) == action and bool(b["enabled"]):
			var r: Dictionary = b["r"]
			var center := Vector2(float(r["x"]) + float(r["w"]) / 2.0,
					float(r["y"]) + float(r["h"]) / 2.0)
			var mv := InputEventMouseMotion.new()
			mv.position = center
			mv.global_position = center
			Input.parse_input_event(mv)
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = center
			ev.global_position = center
			Input.parse_input_event(ev)
			Input.flush_buffered_events()
			return


func _fail(msg: String) -> void:
	printerr("QC6P2_FAIL: " + msg)
	get_tree().quit(1)
