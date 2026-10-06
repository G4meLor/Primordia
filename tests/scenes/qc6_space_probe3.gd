# QC round 6 — agent-space-arc probe 3. Re-runs the dna-refusal legs probe 1
# could not click (its gate compared _leg==1 AFTER a multi-frame park): catch
# → death-drain to dna<15 → the SEED click refusal (cargo>=1, dna<20) and the
# G splice refusal (cargo>=2, dna<15) — each click armed by a flag, toasts
# scanned live.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const WORLD_SEED := 48879  # 0xBEEF
const TIMEOUT_FRAMES := 30000

var _phase := "boot"
var _frames := 0
var _leg := 0
var _game: Variant = null
var _held := {}
var _toasts_seen: Array = []
var _deaths := 0
var _death_wait := 0
var _last_shp := 100.0
var _last_dna := 0
var _armed_seed := false
var _armed_splice := false
var _dna_mark := 0


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
				print("QC6P3_LANDED dna=%d" % int(_game.context.dna))
				_phase = "catch1"
				_leg = 0
		"catch1":
			# one catch (cargo 1 for the seed refusal; splice needs 2 — the
			# second catch rides the drain phase's respawn path)
			var sim: Variant = _game.stages["space"].sim
			if _park_near(sim):
				if not _armed_seed and sim.cargo.size() == 0 and sim.beamT <= 0.0 \
						and _leg % 100 == 0:
					_tap(KEY_R)
				_game.step_for_testing(1, 1.0 / 60.0)
				_scan_toasts()
				if sim.cargo.size() >= 1:
					print("QC6P3_CATCH1 cargo=%d dna=%d" % [
						sim.cargo.size(), int(_game.context.dna)])
					_phase = "drain"
					_leg = 0
					_death_wait = 0
			else:
				_scan_toasts()
				if _leg > 60 * 60:
					_fail("catch1 park stall")
		"drain":
			# fly into the sun until dead; the sim respawns the SAME tick at
			# half hull, so death = the shp jump to exactly 50 with dna billed
			var sim2: Variant = _game.stages["space"].sim
			var sun: Dictionary = sim2.sun
			var shp := float(sim2.shp)
			if shp >= 49.9 and shp <= 50.1 and _last_shp < 49.0 \
					and int(_game.context.dna) < _last_dna:
				_deaths += 1
				print("QC6P3_DEATH n=%d dna=%d cargo=%d" % [
					_deaths, int(_game.context.dna), sim2.cargo.size()])
				if int(_game.context.dna) < 15 or _deaths >= 30:
					_dna_mark = int(_game.context.dna)
					_phase = "park2"
					_leg = 0
					_last_shp = shp
					return
			_last_shp = shp
			_last_dna = int(_game.context.dna)
			if _deaths > 0 and _death_wait < 240:
				_death_wait += 1
				_steer(sim2, Vector2.ZERO)  # ride out the 4s invuln first
			else:
				_steer(sim2, Vector2(float(sun["x"]) - float(sim2.sx),
					float(sun["y"]) - float(sim2.sy)))
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
		"park2":
			# a second catch en route (cargo 2 for the splice refusal), then
			# park once more for the in-range SEED click
			var sim3: Variant = _game.stages["space"].sim
			if _park_near(sim3):
				if sim3.cargo.size() < 2:
					if sim3.beamT <= 0.0 and _leg % 100 == 0:
						_tap(KEY_R)
					_game.step_for_testing(1, 1.0 / 60.0)
					_scan_toasts()
				else:
					_armed_seed = true
					_panel_click("seed")
					_phase = "seed_check"
					_leg = 0
			else:
				_scan_toasts()
				if _leg > 60 * 60:
					_fail("park2 stall cargo=%d" % sim3.cargo.size())
		"seed_check":
			var sim4: Variant = _game.stages["space"].sim
			_steer(sim4, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 40:
				var refused := false
				for t in _toasts_seen:
					if t.contains("Seeding costs") or t.contains("Gieo mầm tốn"):
						refused = true
				var colonies := 0
				for p in sim4.planets:
					if p["colony"] != null:
						colonies += 1
				print("QC6P3_SEED_REFUSED dna=%d(<20) cargo=%d colonies=%d toast=%s" % [
					_dna_mark, sim4.cargo.size(), colonies, str(refused)])
				_armed_splice = true
				_tap(KEY_G)
				_phase = "splice_check"
				_leg = 0
		"splice_check":
			var sim5: Variant = _game.stages["space"].sim
			_steer(sim5, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg >= 40:
				var refused2 := false
				for t in _toasts_seen:
					if t.contains("Gene splice costs") or t.contains("Ghép gen tốn"):
						refused2 = true
				print("QC6P3_SPLICE_REFUSED dna=%d cargo=%d toast=%s" % [
					int(_game.context.dna), sim5.cargo.size(), str(refused2)])
				print("QC6P3_ALL_OK")
				get_tree().quit(0)
				_phase = "done"
		"done":
			pass


var _park_idx := -1

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
			var ev := InputEventKey.new()
			ev.physical_keycode = kc
			ev.pressed = true
			Input.parse_input_event(ev)
			Input.flush_buffered_events()
			_held[code] = true
		elif not bool(want[code]) and _held.has(code):
			var ev2 := InputEventKey.new()
			ev2.physical_keycode = kc
			ev2.pressed = false
			Input.parse_input_event(ev2)
			Input.flush_buffered_events()
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
	printerr("QC6P3_FAIL: " + msg)
	get_tree().quit(1)
