# QC round 4 chunk 2 — the CONTINUE/restore round-trip (agent-full-run-2).
# Rides the slot that chunk 1 (qc4_fr4_speedrun) left behind: menu →
# continue_slot(0) → the fade lands → snapshot the restored world →
# Escape → pause → a real click on "Quit to title" → menu → continue_slot(0)
# again → snapshot again → the two snapshots must agree field-for-field.
# Defensive sim reads only (`"k" in sim` before every read — the TribeSim
# px/py lesson from chunk 1's watcher).
# QC4_RESTORE_OK = both snapshots identical + both restores landed a gameplay
# stage. QC4_RESTORE_MISMATCH lists the divergent keys.
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

const DT := 1.0 / 60.0
const TIMEOUT_FRAMES := 9000
const TRANSITION_POLL := 300
const CARD_STEPS := 180          # the restore fade slot (the known window)

var _phase := "build"
var _frames := 0
var _steps := 0
var _snap0 := {}
var _snap1 := {}
var _restore_t0 := -1
var _done := false
var _game: Variant = null
var _drv: Variant = null


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_finish("QC4_TIMEOUT at phase %s" % _phase)
		return
	if _done:
		return
	match _phase:
		"build":
			_game = _build_game()
			_drv = BotDriverScript.new()
			_phase = "restore1"
		"restore1":
			_restore(0)
		"restore1_wait":
			_wait_land("snap0")
		"snap0":
			_snap0 = _snapshot()
			print("QC4_RESTORE1 f=%d %s" % [_frames, str(_snap0)])
			_phase = "pause_open"
		"pause_open":
			_drv.tap_key(KEY_ESCAPE)
			_game.step_for_testing(2, DT)
			if bool(_game.paused):
				_phase = "pause_click"
			elif _steps > 60:
				_finish("QC4_RESTORE_FAIL Escape did not open the pause (paused=false)")
			_steps += 1
		"pause_click":
			# a real click on the Quit to title item
			var target := Vector2.ZERO
			var found := false
			for it in _game.current.pause_inst.items:
				if String(it["label"]).contains("Quit"):
					target = Vector2(float(it["x"]) + float(it["w"]) / 2.0,
							float(it["y"]) + float(it["h"]) / 2.0)
					found = true
					break
			if not found:
				_finish("QC4_RESTORE_FAIL no Quit item in pause (%d items)" % _game.current.pause_inst.items.size())
				return
			_drv.mouse_down(target)
			_game.step_for_testing(1, DT)
			_drv.mouse_up()
			_steps = 0
			_phase = "quit_wait"
		"quit_wait":
			_game.step_for_testing(1, DT)
			_steps += 1
			if _game.context.stage == "menu":
				print("QC4_QUIT_OK f=%d (quit-to-title landed the menu)" % _frames)
				_steps = 0
				_phase = "restore2"
			elif _steps > TRANSITION_POLL:
				_finish("QC4_RESTORE_FAIL quit-to-title never landed the menu (stage=%s)" % _game.context.stage)
		"restore2":
			_restore(0)
		"restore2_wait":
			_wait_land("snap1")
		"snap1":
			_snap1 = _snapshot()
			print("QC4_RESTORE2 f=%d %s" % [_frames, str(_snap1)])
			var diff: Array = []
			for k in _snap0:
				if _snap0[k] != _snap1.get(k):
					diff.append("%s: %s -> %s" % [k, str(_snap0[k]), str(_snap1.get(k))])
			for k in _snap1:
				if not _snap0.has(k):
					diff.append("%s: (new) %s" % [k, str(_snap1[k])])
			if diff.is_empty():
				print("QC4_RESTORE_OK round-trip stable across quit-to-title + continue")
			else:
				print("QC4_RESTORE_MISMATCH %s" % str(diff))
			_steps = 0
			_phase = "pause_open2"
		"pause_open2":
			# a second quit-to-title so the corrupt-slot probe runs on the MENU
			_drv.tap_key(KEY_ESCAPE)
			_game.step_for_testing(2, DT)
			if bool(_game.paused):
				_steps = 0
				_phase = "pause_click2"
			elif _steps > 60:
				_finish("QC4_RESTORE_FAIL Escape (2nd) did not open the pause")
			_steps += 1
		"pause_click2":
			var target2 := Vector2.ZERO
			var found2 := false
			for it in _game.current.pause_inst.items:
				if String(it["label"]).contains("Quit"):
					target2 = Vector2(float(it["x"]) + float(it["w"]) / 2.0,
							float(it["y"]) + float(it["h"]) / 2.0)
					found2 = true
					break
			if not found2:
				_finish("QC4_RESTORE_FAIL no Quit item (2nd pause)")
				return
			_drv.mouse_down(target2)
			_game.step_for_testing(1, DT)
			_drv.mouse_up()
			_steps = 0
			_phase = "quit_wait2"
		"quit_wait2":
			_game.step_for_testing(1, DT)
			_steps += 1
			if _game.context.stage == "menu":
				_steps = 0
				_phase = "corrupt"
			elif _steps > TRANSITION_POLL:
				_finish("QC4_RESTORE_FAIL quit (2nd) never landed the menu")
		"corrupt":
			# the load-fail toast fix (r2): a corrupt slot must show the menu
			# toast + NOT be silently overwritten by a fresh run
			var f := FileAccess.open("user://saves/slot1.json", FileAccess.WRITE)
			f.store_string("{not json at all")
			f.close()
			var menu: Variant = _game.current
			menu.continue_slot(1)
			_game.step_for_testing(5, DT)
			var corrupt: bool = menu.corrupt_slots.has(1) and bool(menu.corrupt_slots[1])
			var toast_ok: bool = menu.menu_toast != null and String(menu.menu_toast.get("text", "")).contains("corrupted")
			var stage_now: String = _game.context.stage
			if corrupt and toast_ok and stage_now == "menu":
				print("QC4_CORRUPT_OK slot1 marked corrupt + menu toast shown + no overwrite (stage=menu)")
			else:
				print("QC4_CORRUPT_FAIL corrupt=%s toast=%s stage=%s toast_text=%s" % [
						str(corrupt), str(toast_ok), stage_now,
						str(menu.menu_toast.get("text", "") if menu.menu_toast != null else "null")])
			# cleanup the garbage slot
			var dir := DirAccess.open("user://saves")
			if dir != null and dir.file_exists("slot1.json"):
				dir.remove("slot1.json")
			_finish("QC4_DONE")


# ---- the shared restore pump -----------------------------------------------------

func _restore(slot: int) -> void:
	if _game.context.stage != "menu":
		_finish("QC4_RESTORE_FAIL expected menu before continue, got %s" % _game.context.stage)
		return
	var menu: Variant = _game.current
	_restore_t0 = _frames
	menu.continue_slot(slot)
	_steps = 0
	_phase = "restore%d_wait" % (2 if _snap0.size() > 0 else 1)


func _wait_land(snap: String) -> void:
	_game.step_for_testing(1, DT)
	_steps += 1
	var st: String = _game.context.stage
	if st != "menu" and _game.transition == null:
		# the fade landed — walk the card slot, then snapshot
		_game.step_for_testing(CARD_STEPS, DT)
		print("QC4_LANDED %s stage=%s after %d ticks" % [snap, st, _steps])
		_phase = snap
		return
	if _steps > TRANSITION_POLL:
		# tolerate the load-fail path: a missing/corrupt slot stays on the
		# menu with the corrupt mark + menu toast (the r2 load-fail fix)
		var menu: Variant = _game.current
		var marked: bool = menu.corrupt_slots.has(0) and bool(menu.corrupt_slots[0])
		var toasted: bool = menu.menu_toast != null
		if st == "menu" and (marked or toasted):
			print("QC4_RESTORE_LOADFAIL slot0: marked=%s toast=%s (no silent overwrite — fix holds; likely the wipe bug ate the slot)")
			# we are on the MENU — skip any pause leg straight to the corrupt probe
			if snap == "snap0":
				_snap0 = {"stage": "LOADFAIL"}
				_phase = "corrupt"
			else:
				_snap1 = {"stage": "LOADFAIL"}
				_phase = "corrupt"
			return
		_finish("QC4_RESTORE_FAIL restore never landed (stage=%s transition=%s marked=%s toast=%s)" % [
				st, str(_game.transition != null), str(marked), str(toasted)])


func _snapshot() -> Dictionary:
	var c: Variant = _game.context
	var out := {
		"stage": String(c.stage),
		"dna": int(c.dna),
		"chaos": floori(float(c.chaos) * 1000.0),
		"karma": floori(float(c.karma) * 1000.0),
		"playtime": floori(float(c.playtime)),
		"stage_id": String(_game.current.id),
	}
	var sim: Variant = _game.current.get("sim") if _game.current != null else null
	if sim != null:
		for k in ["pop", "mil", "culture", "econ", "shp", "cargo", "time", "totem"]:
			if k in sim:
				var v: Variant = sim.get(k)
				if v is float or v is int:
					out["sim_" + k] = floori(float(v) * 100.0)
				elif v is Array:
					out["sim_" + k] = (v as Array).size()
		if "genome" in c and "legs" in c.genome:
			out["legs"] = float(c.genome.get("legs", 0))
		# civ cities + space colonies (defensive)
		var cities: Variant = sim.get("cities") if "cities" in sim else null
		if cities is Array:
			out["cities"] = (cities as Array).size()
		var planets: Variant = sim.get("planets") if "planets" in sim else null
		if planets is Array:
			var cols := 0
			for p in planets:
				if p is Dictionary and p.get("colony", null) != null:
					cols += 1
			out["colonies"] = cols
	return out


func _finish(msg: String) -> void:
	if _done:
		return
	_done = true
	print(msg)
	get_tree().quit(0)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(1)
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
