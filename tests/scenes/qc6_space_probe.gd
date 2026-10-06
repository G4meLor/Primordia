# QC round 6 — agent-space-arc probe scene. NEW real-input probes the r5
# golden/edge scenes never ride: VI panel rows via the REAL set_lang settings
# path (pause.gd:152 call), the mid-beam double-R, the cargo-fill-to-4 +
# cargo-full toast, JETTISON through the panel row, the REPAIR positive cycle
# + disabled-row no-op at full hull, the death-drain to dna<20, the SEED/SPLICE
# dna-refusal toasts, and the re-survey cooldown. Only direct calls: the
# documented start_new_game cheat + i18n.set_lang (the pause menu's own call).
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const WORLD_SEED := 61453  # 0xF00D
const TIMEOUT_FRAMES := 40000

var _phase := "boot"
var _frames := 0
var _leg := 0
var _game: Variant = null
var _held := {}
var _toasts_seen: Array = []
var _labels_dumped := false
var _vi_r_far_checked := false
var _catch0_dna := 0
var _midbeam_armed := false
var _midbeam_extra := 0
var _cargo_target := 0
var _jett_dna := 0
var _jett_cargo := 0
var _repair_dna0 := 0
var _repair_hit := false
var _repair_full_dna := 0
var _repair_full_done := false
var _deaths := 0
var _death_wait := 0
var _seed_refusal_dna := 0
var _splice_dna := 0
var _resurvey_dna := 0
var _resurvey_hits := 0


func _process(_dt: float) -> void:
	_frames += 1
	_leg += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
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
				var sim: Variant = _game.stages["space"].sim
				print("QC6_LANDED dna=%d planets=%d shpMax=%.0f" % [
					int(_game.context.dna), sim.planets.size(), float(sim.shpMax)])
				# VI via the REAL settings path (pause menu's own call, pause.gd:152)
				_game.i18n.set_lang("vi")
				_phase = "vi_r_far"
				_leg = 0
		"vi_r_far":
			# R far from any planet → the refusal toast must render in VI
			var sim: Variant = _game.stages["space"].sim
			_steer(sim, Vector2.ZERO)
			if _leg == 5:
				_tap(KEY_R)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 40 and not _vi_r_far_checked:
				_vi_r_far_checked = true
				var vi := false
				for t in _toasts_seen:
					if t.contains("Bay sát"):
						vi = true
				print("QC6_VI_RFAR %s toasts=%s" % ["OK" if vi else "EN?", str(_toasts_seen)])
				_phase = "park_a"
				_leg = 0
		"park_a":
			var sim2: Variant = _game.stages["space"].sim
			if _park_near(sim2):
				print("QC6_PARKED_A planet=%s" % str(sim2.planets[_near_living(sim2)]["name"]))
				_phase = "labels"
				_leg = 0
			else:
				_game.step_for_testing(1, 1.0 / 60.0)
		"labels":
			# the REAL render-synced rows under VI — read what the player reads
			var sim3: Variant = _game.stages["space"].sim
			_steer(sim3, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 5 and not _labels_dumped:
				_labels_dumped = true
				_game._do_render(0.0)
				var rows: Array = _game.stages["space"]._panel_rects
				var labels: Array = []
				for b in rows:
					labels.append("%s|en=%s" % [String(b["action"]), str(bool(b["enabled"]))])
				print("QC6_PANEL_VI rows=%s" % str(labels))
				_phase = "catch0"
				_leg = 0
		"catch0":
			# first catch: the +10 and the VI "Đã bắt:" toast
			var sim4: Variant = _game.stages["space"].sim
			_steer(sim4, Vector2.ZERO)
			if _leg == 5:
				_catch0_dna = int(_game.context.dna)
				_tap(KEY_R)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if sim4.cargo.size() >= 1:
				var pay := int(_game.context.dna) - _catch0_dna
				var vi_toast := false
				for t in _toasts_seen:
					if t.contains("Đã bắt"):
						vi_toast = true
				print("QC6_CATCH0 cargo1 pay=%d vi_toast=%s" % [pay, str(vi_toast)])
				_phase = "midbeam"
				_leg = 0
			elif _leg > 60 * 10:
				_fail("catch0 no catch")
		"midbeam":
			# second catch with a SECOND R tapped mid-beam (beamT 1.4s) — the
			# early-return gate must keep it ONE catch, ONE cargo slot
			var sim5: Variant = _game.stages["space"].sim
			_steer(sim5, Vector2.ZERO)
			if _leg == 5:
				_tap(KEY_R)
				_midbeam_armed = true
			elif _leg == 35 and _midbeam_armed:
				_tap(KEY_R)  # mid-beam — beamT ≈ 0.5s left
				_midbeam_extra += 1
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg > 60 * 5:
				print("QC6_MIDBEAM extra_taps=%d cargo=%d" % [_midbeam_extra, sim5.cargo.size()])
				_phase = "fill3"
				_leg = 0
				_cargo_target = 4
		"fill3":
			# catch until cargo 4 (hop planets when the eco runs dry), then one
			# more R → the cargo-full toast, cargo stays 4
			var sim6: Variant = _game.stages["space"].sim
			if sim6.cargo.size() >= _cargo_target:
				if _leg == 1:
					_tap(KEY_R)
				_game.step_for_testing(1, 1.0 / 60.0)
				_scan_toasts()
				if _leg > 60 * 3:
					var full := false
					for t in _toasts_seen:
						if t.contains("Khoang đầy"):
							full = true
					print("QC6_CARGOFULL cargo=%d vi_full=%s" % [
						sim6.cargo.size(), str(full)])
					_jett_dna = int(_game.context.dna)
					_jett_cargo = sim6.cargo.size()
					_phase = "jettison"
					_leg = 0
			else:
				if sim6.beamT > 0.0:
					_steer(sim6, Vector2.ZERO)
				elif sim6.cargo.size() > 0 and sim6.beamT <= 0.0 and _leg % 90 == 0:
					_tap(KEY_R)
				if _near_living(sim6) != _park_idx:
					_park_near(sim6)
				else:
					_steer(sim6, Vector2.ZERO)
				_game.step_for_testing(1, 1.0 / 60.0)
				_scan_toasts()
				if _leg > 60 * 60:
					_fail("fill3 stalled cargo=%d" % sim6.cargo.size())
		"jettison":
			# panel JETTISON → the NEWEST cargo pops, dna unchanged
			var sim7: Variant = _game.stages["space"].sim
			_steer(sim7, Vector2.ZERO)
			if _leg == 1:
				_panel_click("jettison")
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 30:
				var rel := false
				for t in _toasts_seen:
					if t.contains("released back to the void"):
						rel = true
				print("QC6_JETTISON cargo=%d->%d dna_same=%s released_toast=%s" % [
					_jett_cargo, sim7.cargo.size(),
					str(int(_game.context.dna) == _jett_dna), str(rel)])
				_phase = "scan_leg"
				_leg = 0
		"scan_leg":
			# first SCAN (+15) then an immediate re-survey → the cooldown toast,
			# then after 4.5s → +3 again
			var sim8: Variant = _game.stages["space"].sim
			_steer(sim8, Vector2.ZERO)
			if _leg == 5:
				_resurvey_dna = int(_game.context.dna)
				_panel_click("scan")
			elif _leg == 40:
				_panel_click("scan")
			elif _leg == 60:
				_resurvey_hits = int(_game.context.dna) - _resurvey_dna
			elif _leg == 70:
				_panel_click("scan")  # inside the 4s cooldown → recharge toast
			elif _leg == 100:
				_panel_click("scan")  # still ~2.5s left → recharge again
			elif _leg == 420:
				_panel_click("scan")  # ~4.7s since the +3 → pay again
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 480:
				var recharge := 0
				for t in _toasts_seen:
					if t.contains("recharging"):
						recharge += 1
				var second_pay := int(_game.context.dna) - _resurvey_dna - _resurvey_hits
				print("QC6_RESURVEY first_pay=%d recharge_toasts=%d second_pay=%d dna=%d" % [
					_resurvey_hits, recharge, second_pay, int(_game.context.dna)])
				_phase = "repair_dmg"
				_leg = 0
		"repair_dmg":
			# fly into the sun band, take hull damage, fly out, REPAIR via panel
			var sim9: Variant = _game.stages["space"].sim
			var sun: Dictionary = sim9.sun
			var d := Vector2(float(sim9.sx) - float(sun["x"]), float(sim9.sy) - float(sun["y"])).length()
			if float(sim9.shp) < float(sim9.shpMax) * 0.5 or d > 900.0:
				_steer(sim9, Vector2(float(sun["x"]) - float(sim9.sx), float(sun["y"]) - float(sim9.sy)) * -1.0)
			else:
				_steer(sim9, Vector2(float(sun["x"]) - float(sim9.sx), float(sun["y"]) - float(sim9.sy)))
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if d > 700.0 and float(sim9.shp) < float(sim9.shpMax) * 0.55:
				_repair_dna0 = int(_game.context.dna)
				_steer(sim9, Vector2.ZERO)
				_panel_click("repair")
				_phase = "repair_check"
				_leg = 0
			elif _leg > 60 * 30:
				_fail("repair_dmg never damaged (shp=%.0f d=%.0f)" % [float(sim9.shp), d])
		"repair_check":
			var sim10: Variant = _game.stages["space"].sim
			_steer(sim10, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 30:
				var cost := _repair_dna0 - int(_game.context.dna)
				var full := absf(float(sim10.shp) - float(sim10.shpMax)) < 0.01
				print("QC6_REPAIR cost=%d hull_full=%s dna=%d" % [
					cost, str(full), int(_game.context.dna)])
				_repair_full_dna = int(_game.context.dna)
				_panel_click("repair")  # full hull → the row reads disabled
				_phase = "repair_full"
				_leg = 0
		"repair_full":
			var sim11: Variant = _game.stages["space"].sim
			_steer(sim11, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg >= 30:
				var noop := int(_game.context.dna) == _repair_full_dna
				print("QC6_REPAIR_FULL_NOOP dna_same=%s" % str(noop))
				_phase = "death_drain"
				_leg = 0
				_death_wait = 0
		"death_drain":
			# fly into the sun until the ship dies; the 15% bills drain dna to
			# <15 (each death: cargo survives, holes cull, respawn (0,-900))
			var sim12: Variant = _game.stages["space"].sim
			var sun2: Dictionary = sim12.sun
			if float(sim12.shp) <= 0.0 or _death_wait > 0:
				_death_wait += 1
				_steer(sim12, Vector2.ZERO)
				if _death_wait == 90:
					_deaths += 1
					_death_wait = 0
					print("QC6_DEATH n=%d dna=%d cargo=%d" % [
						_deaths, int(_game.context.dna), sim12.cargo.size()])
					if int(_game.context.dna) < 15 or _deaths >= 30:
						_seed_refusal_dna = int(_game.context.dna)
						_phase = "seed_refusal"
						_leg = 0
						return
			else:
				_steer(sim12, Vector2(float(sun2["x"]) - float(sim12.sx),
					float(sun2["y"]) - float(sim12.sy)))
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
		"seed_refusal":
			# SEED with cargo ≥1 and dna <20 → the refusal toast, no colony,
			# cargo intact
			var sim13: Variant = _game.stages["space"].sim
			if _park_near(sim13):
				if _leg == 1:
					_panel_click("seed")
				_phase = "seed_check"
				_leg = 0
			else:
				_game.step_for_testing(1, 1.0 / 60.0)
		"seed_check":
			var sim14: Variant = _game.stages["space"].sim
			_steer(sim14, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 30:
				var refused := false
				for t in _toasts_seen:
					if t.contains("Gieo mầm tốn"):
						refused = true
				var colonies := 0
				for p in sim14.planets:
					if p["colony"] != null:
						colonies += 1
				print("QC6_SEED_REFUSED dna=%d cargo=%d colonies=%d toast=%s" % [
					_seed_refusal_dna, sim14.cargo.size(), colonies, str(refused)])
				_splice_dna = int(_game.context.dna)
				_phase = "splice_refusal"
				_leg = 0
		"splice_refusal":
			# G with cargo ≥2 and dna <15 → the splice refusal, cargo intact
			var sim15: Variant = _game.stages["space"].sim
			if _leg == 5:
				_tap(KEY_G)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 40:
				var refused2 := false
				for t in _toasts_seen:
					if t.contains("Ghép gen tốn"):
						refused2 = true
				print("QC6_SPLICE_REFUSED dna=%d cargo=%d toast=%s" % [
					_splice_dna, sim15.cargo.size(), str(refused2)])
				_phase = "report"
				_leg = 0
		"report":
			var sim16: Variant = _game.stages["space"].sim
			var dupes: Dictionary = {}
			for t in _toasts_seen:
				dupes[t] = int(dupes.get(t, 0)) + 1
			var dupe_lines: Array = []
			for k in dupes:
				if int(dupes[k]) > 1:
					dupe_lines.append("%dx%s" % [dupes[k], k])
			print("QC6_TOASTS total=%d unique=%d dupes=%s" % [
				_toasts_seen.size(), dupes.size(), str(dupe_lines)])
			print("QC6_ALL_OK dna=%d cargo=%d deaths=%d" % [
				int(_game.context.dna), sim16.cargo.size(), _deaths])
			get_tree().quit(0)
			_phase = "done"
		"done":
			pass


var _park_idx := -1

## Steer toward the nearest LIVING planet; true when parked in the ring.
func _park_near(sim: Variant) -> bool:
	var idx := _near_living(sim)
	if idx < 0:
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
			return true
		_park_idx = idx
	else:
		_park_idx = idx
		_steer(sim, Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)))
	_game.step_for_testing(1, 1.0 / 60.0)
	if _leg > 60 * 50:
		_fail("park never landed (d=%.0f)" % d)
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
	printerr("QC6_PROBE_FAIL: " + msg)
	get_tree().quit(1)
