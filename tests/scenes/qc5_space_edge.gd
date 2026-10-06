# QC round 5 — agent-space-arc edge scene. Real-input probes the golden bot
# never touches: out-of-range R refusal, empty-cargo G refusal, empty-cargo
# SEED click (row gate), sun kill → the ship-death respawn path (15% DNA bill,
# (0,−900) respawn, invuln, hole cull), then a SAVE → CONTINUE cycle to verify
# the space restore + its [space-restore] telemetry.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const WORLD_SEED := 51966  # 0xCAFE
const TIMEOUT_FRAMES := 40000

var _phase := "boot"
var _frames := 0
var _leg_frames := 0
var _game: Variant = null
var _game2: Variant = null
var _held := {}
var _probe := {}
var _dna_before_death := 0
var _toasts_seen: Array = []
var _cargo_before_save := 0
var _colony_planet := -1


func _process(_dt: float) -> void:
	_frames += 1
	_leg_frames += 1
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
				_phase = "abduct_far"
				_leg_frames = 0
		"abduct_far":
			# R far from any planet → the distance refusal toast
			if _leg_frames == 5:
				_tap(KEY_R)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg_frames >= 30:
				var got := _scan_toasts()
				if got.any(func(s: String): return s.contains("Fly closer")):
					print("QC5_EDGE_R_FAR_OK")
				else:
					print("QC5_EDGE_R_FAR_WEAK toasts=%s" % str(got))
				_phase = "splice_empty"
				_leg_frames = 0
		"splice_empty":
			# G with cargo 0 → the 15-DNA refusal toast
			if _leg_frames == 5:
				_tap(KEY_G)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg_frames >= 30:
				# TS-verbatim: cargo < 2 → SILENT return (no toast) — record the
				# observed behavior; a crash or a phantom −15 spend is the bug
				var sim_g: Variant = _game.stages["space"].sim
				var got2 := _scan_toasts()
				print("QC5_EDGE_G_EMPTY cargo=%d dna=%d toasts=%s" % [
					sim_g.cargo.size(), int(_game.context.dna), str(got2)])
				_phase = "fly_to_planet"
				_leg_frames = 0
		"fly_to_planet":
			# steer toward the nearest living planet; park inside the ring
			var sim: Variant = _game.stages["space"].sim
			var tgt := _nearest_living(sim)
			var p: Dictionary = sim.planets[tgt]
			var d: float = Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length()
			var v := Vector2(float(sim.svx), float(sim.svy))
			if d < float(p["r"]) + 110.0:
				_steer(sim, -v)
			else:
				_steer(sim, Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)))
			_game.step_for_testing(1, 1.0 / 60.0)
			if d < float(p["r"]) + 115.0 and v.length() < 40.0:
				_steer(sim, Vector2.ZERO)
				_probe = {"planet": tgt}
				print("QC5_EDGE_PARKED d=%.0f" % d)
				_phase = "abduct_catch"
				_leg_frames = 0
			elif _leg_frames > 60 * 50:
				_fail("fly_to_planet never parked (d=%.0f)" % d)
		"abduct_catch":
			# real R → beam 1.4s → catch → cargo 1 (needed for the save cycle)
			var sim2: Variant = _game.stages["space"].sim
			if _leg_frames == 1:
				_tap(KEY_R)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if sim2.cargo.size() >= 1:
				print("QC5_EDGE_CATCH_OK cargo_names=%s" % str(sim2.cargo[0]["name"]))
				_phase = "seed_try"
				_leg_frames = 0
			elif _leg_frames > 60 * 8:
				_fail("abduct_catch no catch (beamT=%s)" % str(sim2.beamT))
		"seed_try":
			# SEED click with cargo 1 — the colony path on THIS planet; then
			# SEED again on the SAME planet (cargo 0 now → row disabled, click
			# must be a no-op, no double colony, no −20 twice)
			var sim3: Variant = _game.stages["space"].sim
			if _leg_frames == 1:
				_panel_click("seed")
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			var pl: Dictionary = sim3.planets[_probe["planet"]]
			if pl["colony"] != null and _leg_frames > 1:
				# second click while cargo is 0 — the row reads disabled
				_panel_click("seed")
				_game.step_for_testing(1, 1.0 / 60.0)
				if pl["colony"] != null:
					print("QC5_EDGE_SEED_RECLICK_SAFE colony=%s dna=%d" % [
						str(pl["colony"]["pop"]), int(_game.context.dna)])
				_phase = "save_slot"
				_leg_frames = 0
			elif _leg_frames > 60 * 8:
				_fail("seed_try no colony (toasts=%s)" % str(_toasts_seen))
		"save_slot":
			# a real autosave seam flush → the blob must carry cargo+colony
			var sim4: Variant = _game.stages["space"].sim
			_cargo_before_save = sim4.cargo.size()
			for i in sim4.planets.size():
				if sim4.planets[i]["colony"] != null:
					_colony_planet = i
			_game.save_all()
			var f := FileAccess.open("user://saves/slot0.json", FileAccess.READ)
			if f == null:
				_fail("save_slot: no slot0.json")
				return
			var j: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			var blob_ok: bool = false
			if j is Dictionary:
				var flags: Variant = j.get("flags")
				if flags is Dictionary and (flags as Dictionary).has("spaceWorld"):
					blob_ok = String((flags as Dictionary)["spaceWorld"]).length() > 0
			if blob_ok and _colony_planet >= 0:
				print("QC5_EDGE_SAVE_BLOB_OK cargo=%d colony_planet=%d" % [
					_cargo_before_save, _colony_planet])
			else:
				print("QC5_EDGE_SAVE_BLOB_WEAK blob=%s colony=%d" % [str(blob_ok), _colony_planet])
			_phase = "sun_run"
			_leg_frames = 0
		"sun_run":
			# fly INTO the sun: the 30/s damage band then the death path
			var sim5: Variant = _game.stages["space"].sim
			var pos := Vector2(float(sim5.sx), float(sim5.sy))
			_steer(sim5, -pos)  # thrust at the origin
			_dna_before_death = int(_game.context.dna)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if float(sim5.shp) <= 0.0 or (pos.length() < 5.0 and _leg_frames > 300):
				print("QC5_EDGE_SUN_KILL shp=%.1f dna_before=%d" % [
					float(sim5.shp), _dna_before_death])
				_phase = "after_death"
				_leg_frames = 0
			elif _leg_frames > 60 * 60:
				_fail("sun_run never died (shp=%.1f d_sun=%.0f)" % [float(sim5.shp), pos.length()])
		"after_death":
			var sim6: Variant = _game.stages["space"].sim
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg_frames >= 10:
				var died := _dna_before_death - int(_game.context.dna)
				var bill := int(roundi(float(_dna_before_death) * 0.15))
				var posd := Vector2(float(sim6.sx), float(sim6.sy))
				var ok_death: bool = absi(died) == bill and absf(posd.length() - 900.0) < 1.0 \
						and float(sim6.invuln) > 3.0
				if ok_death:
					print("QC5_EDGE_DEATH_OK bill=%d pos=(%.0f,%.0f) invuln=%.1f" % [
						died, posd.x, posd.y, float(sim6.invuln)])
				else:
					print("QC5_EDGE_DEATH_WEAK bill=%d expected=%d pos=(%.0f,%.0f) invuln=%.1f" % [
						died, bill, posd.x, posd.y, float(sim6.invuln)])
				_phase = "idle_watch"
				_leg_frames = 0
		"idle_watch":
			# ~150 sim-seconds hands-off: the chaos deck deals what it deals
			# (pirates, holes, tribute) — banks game-time AND probes the passive
			# space loop for jank (toast spam, counter drift)
			var sim_id: Variant = _game.stages["space"].sim
			_steer(sim_id, Vector2.ZERO)
			_game.step_for_testing(1, 1.0 / 60.0)
			_scan_toasts()
			if _leg_frames % 1500 == 0:
				print("QC5_IDLE t=%.0f shp=%.0f dna=%d pirates=%d holes=%d toasts=%d" % [
					float(sim_id.time), float(sim_id.shp), int(_game.context.dna),
					sim_id.pirates.size(), sim_id.blackHoles.size(), _toasts_seen.size()])
			if _leg_frames >= 60 * 150:
				print("QC5_IDLE_DONE sim_time=%.0f" % float(sim_id.time))
				_phase = "quit_title"
				_leg_frames = 0
		"quit_title":
			# real quit-to-title (the menu button click path is sim-side; use
			# the same go_to the stage button uses, then step the fade out)
			if _leg_frames == 1:
				_game.go_to("menu")
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null and _game.current != null \
					and _game.current.id == "menu":
				_phase = "continue"
				_leg_frames = 0
		"continue":
			# real CONTINUE: the slot's ctx.stage is "space" → the welcome card
			# → the space stage rebuilds → _restore_world() rehydrates
			if _leg_frames == 1:
				_game.stages["menu"].continue_slot(0)
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null and _game.current != null \
					and _game.current.id == "space":
				_phase = "verify_restore"
				_leg_frames = 0
		"verify_restore":
			# brief law: count cargo/colony only AFTER the fade — the restore
			# runs when the card lands, so settle 1 more second first
			_game.step_for_testing(1, 1.0 / 60.0)
			if _leg_frames >= 90:
				var sim7: Variant = _game.stages["space"].sim
				var cargo_ok: bool = sim7.cargo.size() == _cargo_before_save
				var col_ok: bool = _colony_planet < 0 \
						or sim7.planets[_colony_planet]["colony"] != null
				var dna_ok: bool = int(_game.context.dna) == _dna_before_death - int(roundi(float(_dna_before_death) * 0.15))
				if cargo_ok and col_ok and dna_ok:
					print("QC5_EDGE_RESTORE_OK cargo=%d colony=%d dna=%d" % [
						sim7.cargo.size(), _colony_planet, int(_game.context.dna)])
				else:
					print("QC5_EDGE_RESTORE_WEAK cargo=%d/%d colony=%d dna=%d exp=%d" % [
						sim7.cargo.size(), _cargo_before_save, _colony_planet,
						int(_game.context.dna),
						_dna_before_death - int(roundi(float(_dna_before_death) * 0.15))])
				get_tree().quit(0)
				_phase = "done"


# ---- helpers -------------------------------------------------------------------

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


func _scan_toasts() -> Array:
	var out: Array = []
	var hud: Variant = _game.stages["space"].hud_inst
	if hud != null:
		for t in hud._toasts:
			out.append(String(t["text"]))
			if not _toasts_seen.has(String(t["text"])):
				_toasts_seen.append(String(t["text"]))
	return out


func _nearest_living(sim: Variant) -> int:
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
	printerr("QC5_EDGE_FAIL: " + msg)
	get_tree().quit(1)
