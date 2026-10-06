# QC round 4 — full-run speedrunner probe (agent-full-run-2). ONE pass of the
# proven full arc (arrival→founding→tribe→civ→space, the test_bot_space
# composition) plus the speedrunner checks riding REAL input:
#   gate_cell : the shore button clicked with legs==0 (gate must hold),
#               the editor E tap (no buy without a click), a 600-tick idle.
#   space_pre : (C) the EARLY CORE FLY — thrust straight to the finale's fixed
#               spawn (0,-1900) before any colony exists; the ending must NOT
#               fire (finale null). (D) the BARREN SEED — park at a planet
#               with eco==null and read the panel rows; SEED must be disabled.
# Timeline watcher: a TL row every 300 ticks + a STAGE_X row on every stage
# change (dna/chaos/karma ride along) — the speedrun's stage-timing table.
# Single pass (the ×2 determinism gate is NOT this scene's job). Graceful
# partial exit: a leg failure logs QC4_LEG_FAIL + the leg name and quits 0 —
# the log is the report. QC4_FULLRUN_OK = the whole arc + ending + dismissal.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const BotSpaceScript := preload("res://tests/bots/bot_space.gd")
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")

const DT := 1.0 / 60.0
const TIMEOUT_FRAMES := 20000
const SLOTS := 3
const CARD_STEPS := 180
const TRANSITION_POLL := 300
const TL_EVERY := 300
const CORE_FLY_TICKS := 480      # probe C: 8 sim-seconds of real thrust
const BARREN_BUDGET := 60 * 25   # probe D: the station park budget
const BARREN_WAIT := 40          # ticks after the SEED click

var _phase := "build_probe"
var _frames := 0
var _tl := 0
var _last_stage := "menu"
var _timeline: Array = []
var _probe := ""                 # the space_pre sub-state
var _core_ticks := 0
var _barren_i := -1
var _done := false
var _game: Variant = null
var _bot: Variant = null
var _g2: Variant = null          # the probe game (freed before the arc game)
var _g2_drv: Variant = null


func _ready() -> void:
	_wipe_saves()


func _process(_dt: float) -> void:
	_frames += 1
	_tl += 1
	if _frames > TIMEOUT_FRAMES:
		_finish("QC4_TIMEOUT at phase %s frame %d" % [_phase, _frames])
		return
	if _done:
		return
	match _phase:
		"build_probe":
			_g2 = _build_game()
			_g2_drv = BotDriverScript.new()
			_phase = "gate_cell"
		"gate_cell":
			_gate_cell()
		"drop_probe":
			_g2.free()
			_g2 = null
			_bot = BotSpaceScript.new()
			_game = _build_game()
			_tl = 0
			_phase = "arrival"
		"arrival":
			_leg(_bot.bc.tb.cb.arrival_tick(_game), "arrival", "founding")
		"founding":
			_leg(_bot.bc.tb.cb.founding_tick(_game), "founding", "tribe")
		"tribe":
			_leg(_bot.bc.tb.tribe_tick(_game), "tribe", "civ")
		"civ":
			_leg(_bot.bc.civ_tick(_game), "civ",
					"space" if OS.get_environment("QC4_SKIP_PROBES") == "1" else "space_pre")
		"space_pre":
			_space_pre()
		"space":
			_leg(_bot.space_tick(_game), "space", "")
		"post":
			_post()
		"done":
			pass


# ---- the shared leg pump + the timeline watcher ---------------------------------

func _leg(res: String, leg: String, next: String) -> void:
	_watch_timeline(leg)
	if res == "OK":
		print("QC4_LEG_OK %s f=%d" % [leg, _frames])
		_phase = "post" if next == "" else next
		return
	if res != "":
		_finish("QC4_LEG_FAIL %s: %s" % [leg, res])


func _watch_timeline(leg: String) -> void:
	var st: String = _game.context.stage
	if st != _last_stage:
		print("STAGE_X f=%d %s->%s dna=%d chaos=%.3f karma=%.3f" % [
				_frames, _last_stage, st, int(_game.context.dna),
				float(_game.context.chaos), float(_game.context.karma)])
		_timeline.append("f%d %s->%s dna=%d" % [_frames, _last_stage, st, int(_game.context.dna)])
		_last_stage = st
	if _tl >= TL_EVERY:
		_tl = 0
		var sim: Variant = _game.current.sim
		var pos := ""
		if sim != null and "sx" in sim and "sy" in sim:
			pos = " sx=%.0f sy=%.0f shp=%.0f" % [float(sim.sx), float(sim.sy), float(sim.shp)]
		print("TL f=%d ph=%s st=%s dna=%d chaos=%.3f%s" % [
				_frames, leg, st, int(_game.context.dna),
				float(_game.context.chaos), pos])


# ---- gate_cell: the cell-stage gate probes on a THROWAWAY game ------------------

func _gate_cell() -> void:
	_g2.step_for_testing(5, DT)
	if _g2.context.stage != "menu":
		_finish("gate: expected menu after 5 steps, got %s" % _g2.context.stage)
		return
	var menu: Variant = _g2.current
	menu.start_new_game(0, "normal", _g2.context.seed)
	var steps := 0
	while _g2.context.stage != "cell" and steps < TRANSITION_POLL:
		_g2.step_for_testing(1, DT)
		steps += 1
	if _g2.context.stage != "cell":
		_finish("gate: cell not reached in %d steps" % TRANSITION_POLL)
		return
	_g2.step_for_testing(CARD_STEPS, DT)  # the card slot (the known window)
	var sim: Variant = _g2.current.sim
	var drv: Variant = _g2_drv
	var dna0: int = int(_g2.context.dna)
	var legs0: float = float(_g2.context.genome.get("legs", 0))
	# probe A: click the shore rect with legs==0 (shoreAvailable false)
	var r: Dictionary = sim.shoreRect
	var cx: float = float(r["x"]) + float(r["w"]) / 2.0
	var cy: float = float(r["y"]) + float(r["h"]) / 2.0
	drv.mouse_down(Vector2(cx, cy))
	_g2.step_for_testing(1, DT)
	drv.mouse_up()
	_g2.step_for_testing(60, DT)
	var still_cell: bool = _g2.context.stage == "cell"
	var avail: bool = bool(sim.shoreAvailable)
	if still_cell and not avail:
		print("QC4_GATE_OK shore gate holds at legs=%.0f dna=%d (click at %.0f,%.0f no transition, shoreAvailable=false)" % [
				legs0, dna0, cx, cy])
	else:
		print("QC4_GATE_FAIL shore gate: still_cell=%s avail=%s legs=%.0f (SKIP FOUND?)" % [
				str(still_cell), str(avail), legs0])
	# probe B: E opens the editor, dna unchanged without a buy click
	var dna_e: int = int(_g2.context.dna)
	drv.tap_key(KEY_E)
	_g2.step_for_testing(2, DT)
	var opened: bool = bool(_g2.editor.get("open", false)) if _g2.editor != null else false
	drv.tap_key(KEY_E)
	_g2.step_for_testing(2, DT)
	print("QC4_GATE_EDITOR open=%s dna %d->%d (no buy without a click)" % [
			str(opened), dna_e, int(_g2.context.dna)])
	# idle watch: 600 ticks standing at spawn — hp/dna movement (famine rides
	# the timeline later; this is the cell baseline)
	var hp0: float = float(sim.php)
	_g2.step_for_testing(600, DT)
	print("QC4_CELL_IDLE 600t dna %d->%d php %.0f->%.0f ents=%d" % [
			dna0, int(_g2.context.dna), hp0, float(sim.php), sim.ents.size()])
	_phase = "drop_probe"


# ---- space_pre: the early-core fly (C) + the barren seed (D) --------------------

func _space_pre() -> void:
	var sim: Variant = _bot.space_sim(_game)
	match _probe:
		"":
			_probe = "core_fly"
			_core_ticks = 0
			print("QC4_PROBE_C start ship=(%.0f,%.0f) finale_present=%s" % [
					float(sim.sx), float(sim.sy), str(sim.finale != null)])
		"core_fly":
			# real thrust toward the finale's fixed spawn (0,-1900)
			var want := Vector2(0.0 - float(sim.sx), -1900.0 - float(sim.sy))
			_bot._steer(_game, _bot._hazard_desired(sim, want))
			_bot.step(_game, 1)
			_core_ticks += 1
			if bool(sim.endingDone):
				print("QC4_SKIP_FOUND ending fired with %d colonies before any space leg!" % _colonies(sim))
				_probe = "barren"
				_core_ticks = 0
				return
			if _core_ticks >= CORE_FLY_TICKS:
				_bot._release_all(_game)
				var fd: float = Vector2(0.0 - float(sim.sx), -1900.0 - float(sim.sy)).length()
				print("QC4_PROBE_C_DONE t=%d finale_present=%s endingDone=%s d_to_core=%.0f shp=%.0f/%.0f dna=%d (ending needs the 3-thriving gate — expected)" % [
						_core_ticks, str(sim.finale != null), str(bool(sim.endingDone)),
						fd, float(sim.shp), float(sim.shpMax), int(_game.context.dna)])
				_probe = "barren"
				_core_ticks = 0
		"barren":
			# the nearest planet with eco==null — the seed target
			_barren_i = -1
			var best := INF
			for i in sim.planets.size():
				var p: Dictionary = sim.planets[i]
				if p["eco"] != null or p["colony"] != null:
					continue
				var d: float = Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length()
				if d < best:
					best = d
					_barren_i = i
			if _barren_i < 0:
				print("QC4_PROBE_D skip: no barren uncolonized planet on the board (%d planets)" % sim.planets.size())
				_probe = "done"
				return
			print("QC4_PROBE_D target barren p%d at %.0f px" % [_barren_i, best])
			_probe = "barren_station"
			_core_ticks = 0
		"barren_station":
			var p: Dictionary = sim.planets[_barren_i]
			if _bot._parked(sim, p):
				_bot._release_all(_game)
				_probe = "barren_click"
				_core_ticks = 0
				return
			_bot._steer(_game, _bot._hazard_desired(sim, _bot._station_desired(sim, p)))
			_bot.step(_game, 1)
			_core_ticks += 1
			if _core_ticks > BARREN_BUDGET:
				print("QC4_PROBE_D station never parked in %d ticks (d=%.0f v=%.0f) — probe abort" % [
						_core_ticks,
						Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length(),
						Vector2(float(sim.svx), float(sim.svy)).length()])
				_probe = "done"
		"barren_click":
			var p: Dictionary = sim.planets[_barren_i]
			var rows: Array = _bot._panel_rows(_game)
			var fail: String = _bot._panel_click(_game, "seed")
			var dna0: int = int(_game.context.dna)
			for k in BARREN_WAIT:
				_bot.step(_game, 1)
			if fail != "":
				print("QC4_PROBE_D_RESULT gate holds: no enabled SEED row on a barren planet (rows=%s)" % str(rows))
			else:
				var col: Variant = p["colony"]
				print("QC4_PROBE_D_RESULT SEED click delivered on BARREN planet: colony_born=%s dna %d->%d (expect colony_born=false + no spend if the gate holds)" % [
						str(col != null), dna0, int(_game.context.dna)])
			var fail2: String = _bot._panel_click(_game, "scan")
			for k in BARREN_WAIT:
				_bot.step(_game, 1)
			if fail2 != "":
				print("QC4_PROBE_D_RESULT scan on barren: gate holds (%s) scanned=%s dna=%d" % [
						fail2, str(bool(p["scanned"])), int(_game.context.dna)])
			else:
				print("QC4_PROBE_D_RESULT scan on barren: click delivered scanned=%s dna=%d" % [
						str(bool(p["scanned"])), int(_game.context.dna)])
			_probe = "done"
		"done":
			_core_ticks = 0
			_phase = "space"


func _colonies(sim: Variant) -> int:
	var n := 0
	for p in sim.planets:
		if p["colony"] != null:
			n += 1
	return n


# ---- post -----------------------------------------------------------------------

func _post() -> void:
	var fp: Dictionary = _bot.space_fingerprint(_game)
	var sane: PackedStringArray = _bot.driver.sane_violations
	print("QC4_SUMMARY sane_violations=%d delivery_ok=%s" % [
			sane.size(), str(_bot.driver.delivery_ok)])
	if not sane.is_empty():
		print("QC4_SANE %s" % str(sane))
	print("QC4_SUMMARY latches: ending_fired=%s win_flush=%s ending_seen=%s dismissed=%s calm=%s ship_back=%s" % [
			str(_bot.ending_fired), str(_bot.win_flush_ok), str(_bot.ending_seen),
			str(_bot.dismissed_seen), str(_bot.calm_objective), str(_bot.ship_returned)])
	print("QC4_SUMMARY arc: colony_born=%s scanned=%s splice=%s siege=%s/%d awakens=%s" % [
			str(_bot.colony_born), str(_bot.scanned_seen), str(_bot.splice_child),
			str(_bot.siege_seen), _bot.siege_kills, str(_bot.awakens_seen)])
	print("QC4_ENDFP endingDone=%s endingDismissed=%s dna=%d extinctions=%d" % [
			str(bool(fp["endingDone"])), str(bool(fp["endingDismissed"])),
			int(fp["dna"]), int(fp["extinct"])])
	if _bot.ending_fired and _bot.win_flush_ok and _bot.dismissed_seen:
		print("QC4_FULLRUN_OK")
	else:
		print("QC4_PARTIAL (the ending did not fully latch — see the latches above)")
	_finish("QC4_DONE")


func _finish(msg: String) -> void:
	if _done:
		return
	_done = true
	print(msg)
	print("QC4_TIMELINE %s" % " | ".join(_timeline))
	# NO wipe at finish — the restore scene (chunk 2) restores the slot this
	# run leaves behind (the r2 wipe-at-finish bug cost chunk 2 its slot)
	get_tree().quit(0)


# ---- the standard composition ---------------------------------------------------

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


func _wipe_saves() -> void:
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for i in SLOTS:
			if dir.file_exists("slot%d.json" % i):
				dir.remove("slot%d.json" % i)
