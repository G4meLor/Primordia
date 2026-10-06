# QC round 7 batch1 — hud.gd toast_gate anchor acceptance (synthesis item 1).
# The r2 gate anchor lived in the live-toast scan inside toast(), so ttl-expire
# (4 s) and the 6-cap pop_front both destroyed it: a window > ttl re-fired
# every ~4.1 s — the tribe gatherer dead-zone (window 10) measured 4 emissions
# in a 15 s hold against the promised 2. The fix stamps a per-text timestamp
# OUTSIDE the toast list and checks it before the append.
# Legs (real pipeline; state injections marked):
#   A  tribe dead-zone — bushes/trees cleared (injection) + 2 injected
#      gatherers, a 15 s hold must DISPLAY exactly 2 gate toasts (t≈0 + t≈10);
#      an injected 8-toast flood right after the first display forces the cap
#      pop_front while the anchor must hold (old code re-fired right after).
#   B  creature pack-full — 2 ents packed (injection) + a bait ent re-parked
#      next to the player every tick (injection), F held 5.5 s must DISPLAY
#      exactly 1 (the t≈4 re-fire lands while the t=0 toast is still on screen
#      and folds into it).
# Counting: displayed toasts = absent→present transitions of the gate text in
# hud._toasts, read AFTER each step (the frame order is stage-fires-gate then
# hud.update ages it, so a fresh append always reads as present, age ≈ dt).
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
const TIMEOUT_FRAMES := 36000
const HOLD_STEPS := 900       # 15 s
const PACK_HOLD_STEPS := 330  # 5.5 s

var _phase := "boot"
var _frames := 0
var _leg := 0
var _game: Variant = null
var _displays: Array = []        # leg A display hud-clocks
var _pack_displays: Array = []   # leg B display hud-clocks
var _seen := {"seen": false}
var _pack_seen := {"seen": false}
var _noise_done := false


func _process(_dt: float) -> void:
	_frames += 1
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
			_phase = "to_cell"
			_leg = 0
		"to_cell":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null and _game.current.id == "cell" \
					and _game.stages["cell"].sim != null:
				_game.switch_stage("tribe")
				_phase = "tribe_hold"
				_leg = 0
		"tribe_hold":
			var sim: Variant = _game.stages["tribe"].sim
			if sim == null:
				_fail("tribe sim missing")
				return
			if _leg == 0:
				# injection: a barren range — the dead-zone condition holds from
				# tick one (and stays held: re-clear every tick in case a
				# sapling respawn lands mid-hold)
				sim.bushes.clear()
				sim.trees.clear()
				sim.add_tribesman(_game.context.genome, "gather")
				sim.add_tribesman(_game.context.genome, "gather")
				print("QC7GA_TRIBE_SETUP bushes=%d trees=%d tribe=%d" % [
					sim.bushes.size(), sim.trees.size(), sim.tribe.size()])
			sim.bushes.clear()
			sim.trees.clear()
			_game.step_for_testing(1, 1.0 / 60.0)
			var hud: Variant = _game.stages["tribe"].hud_inst
			_count_displays(hud, "Gatherers idle", _seen, _displays)
			if _leg == 60 and not _noise_done:
				# injection: flood the cap so the gate toast is popped out of
				# the list right after its first display — the anchor must
				# survive the pop_front (old code re-fired here)
				_noise_done = true
				for i in 8:
					hud.toast("noise%d" % i, "info", "•")
			if _leg >= HOLD_STEPS:
				print("QC7GA_DEADZONE displays=%d times=%s"
						% [_displays.size(), str(_times(_displays))])
				print("QC7GA_POPFRONT anchor_held=%s (8-toast cap flood at t≈1)"
						% str(_displays.size() <= 2))
				print("QC7GA_ANCHOR %s" % str(hud.get("_gate_last_shown")))
				_game.switch_stage("creature")
				_phase = "to_creature"
				_leg = 0
				return
			_leg += 1
		"to_creature":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.current.id == "creature" and _game.stages["creature"].sim != null:
				var sim2: Variant = _game.stages["creature"].sim
				# the world populates over the first seconds (spawn_timer_check
				# runs maintain_population every 1.5 s) — wait for it
				if sim2.ents.size() <= int(sim2.packLimit) and _leg < 600:
					_leg += 1
					return
				if sim2.ents.size() <= int(sim2.packLimit):
					_fail("creature world never populated (%d ents after 10 s, eco_living=%d)"
							% [sim2.ents.size(), sim2.eco.living().size()])
					return
				# injection: fill the pack to its limit (default genome: 2) but
				# keep at least one ent unpacked for the bait below
				var need := int(sim2.packLimit)
				var packed := 0
				for e in sim2.ents:
					if packed >= need:
						break
					e["pack"] = true
					packed += 1
				print("QC7GA_PACK_SETUP ents=%d packed=%d packLimit=%d"
						% [sim2.ents.size(), packed, need])
				_press(KEY_F, true)
				_phase = "pack_hold"
				_leg = 0
		"pack_hold":
			var sim3: Variant = _game.stages["creature"].sim
			# keep a charmable (unpacked, alive) ent inside the 120 px charm
			# range — try_charm needs a `best` or the gate never fires
			var bait: Variant = null
			for e in sim3.ents:
				if not bool(e["pack"]) and not e.has("corpseT") and not bool(e["baby"]):
					bait = e
					break
			if bait != null:
				bait["x"] = float(sim3.px) + 60.0
				bait["z"] = float(sim3.pz)
			_game.step_for_testing(1, 1.0 / 60.0)
			_count_displays(_game.stages["creature"].hud_inst, "pack is full",
					_pack_seen, _pack_displays)
			if _leg >= PACK_HOLD_STEPS:
				_press(KEY_F, false)
				print("QC7GA_PACKFULL displays=%d times=%s (hold 5.5s window 4)"
						% [_pack_displays.size(), str(_times(_pack_displays))])
				_phase = "report"
				_leg = 0
				return
			_leg += 1
		"report":
			var ok_a := _displays.size() == 2
			var ok_b := _pack_displays.size() == 1
			print("QC7GA_VERDICT deadzone=%s (%d) packfull=%s (%d)"
					% [str(ok_a), _displays.size(), str(ok_b), _pack_displays.size()])
			if ok_a and ok_b:
				print("QC7GA_ALL_OK")
				get_tree().quit(0)
			else:
				_fail("verdict deadzone=%s packfull=%s"
						% [str(ok_a), str(ok_b)])
			_phase = "done"
		"done":
			pass


## Displayed-toast count for one gate text: record the hud clock each time the
## text appears in the live list after having been absent (one record per
## append — a same-tick double append is impossible, one gate call per tick).
func _count_displays(hud: Variant, needle: String, state: Dictionary, out: Array) -> void:
	if hud == null:
		return
	var present := false
	for t in hud._toasts:
		if String(t["text"]).contains(needle):
			present = true
			break
	if present and not bool(state.get("seen", false)):
		out.append(float(hud.get("_gate_clock")))
	state["seen"] = present


func _times(stamps: Array) -> Array:
	var out: Array = []
	for s in stamps:
		out.append(snappedf(float(s), 0.01))
	return out


func _press(kc: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = kc
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _fail(msg: String) -> void:
	printerr("QC7GA_FAIL: " + msg)
	get_tree().quit(1)
