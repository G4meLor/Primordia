# QC r9 death-stall probe — adjudicates the agent-cell-arc [MAJOR] "cell
# death→respawn stall" (deathFade frozen ~0.033, deathStarted stuck, no
# respawn in ≥720 engine-stepped frames, no pause; repro ×2 on tree c3aa742).
#
# Code reading (pre-probe): both qc8/qc9 bot death phases share ONE
# `_leg_frames` counter between the predator-hug CHASE (+2/tick, fail at
# 60*150 in qc9) and the dead WATCH (+1/tick, fail at 60*12). The counter is
# reset only on phase ENTRY, so a chase ≥ 720 frames makes the watch's
# `elif _leg_frames > 60 * 12` fire on the FIRST dead tick — the fail text
# then prints deathFade = 2-3 steps (0.0333/0.05), exactly the r9 sightings.
# This probe excludes that harness artifact and any real sim stall:
#   - inject php=0 directly (M1 fixture pattern), 5 cycles, watch ≤ 1200
#     sim frames each with a PER-CYCLE watch counter (bug excluded);
#   - R9P_MODE=hug — the REAL r9 kill path (hold-move onto the nearest
#     predator until deathStarted), then the same fixed-counter watch;
#   - R9P_RENDER=1 — call game._do_render(0.0) every tick (r8 harness law:
#     the r9 bot's death phase never rendered) vs default no-render (the
#     exact r9 death-phase shape);
#   - step-integrity detector: LAG = requested sim steps − sim.time progress.
#     sim.time += dt is the FIRST statement of CellSim.update, so lag > 0
#     means steps were gated (paused/editor/card) or aborted (script error —
#     the stderr capture names the file/line). The heartbeat prints BEFORE the
#     step call, so an aborting step can never silence it silently.
#   - NaN guard on php/deathFade/sim.time.
# Run: xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/qc9_deathstall_probe.tscn
# Env: R9P_MODE=inject|hug  R9P_RENDER=0|1  R9P_BATCH=n (watch batch, 1)
# Prints R9P_PROBE_OK / R9P_PROBE_FAIL: <why>; exits 0/1/2 (2 = step-lag).
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

const CYCLES := 5
const WATCH_FRAMES := 1200     # the r9 observation window (sim frames)
const STABLE_FRAMES := 120     # post-respawn stability window (2 sim-s)
const DT := 1.0 / 60.0
const TIMEOUT_FRAMES := 40000
const CHASE_LIMIT := 60 * 150  # qc9's hug budget

var _render: bool = OS.get_environment("R9P_RENDER") == "1"
var _mode: String = "hug" if OS.get_environment("R9P_MODE") == "hug" else "inject"
var _batch: int = maxi(1, int(OS.get_environment("R9P_BATCH"))) \
		if OS.get_environment("R9P_BATCH") != "" else 1
var _seed: int = int(OS.get_environment("R9P_SEED")) \
		if OS.get_environment("R9P_SEED") != "" else 5150

var _game: Variant = null
var _driver: Variant = null
var _held_down := false
var _phase := "boot"
var _eng := 0                  # engine frames (heartbeat clock)
var _cycle := 0
var _chase_f := 0              # hug-chase counter (mode=hug)
var _watch_f := 0              # per-cycle watch counter (the r9 bug excluded)
var _stable := 0
var _expected_steps := 0       # sim steps requested since cycle inject
var _cycle_time0 := 0.0
var _lag_seen := 0
var _dna0 := -1.0
var _chaos0 := -1.0
var _respawn_frames: Array = []
var _last_log_f := -30
var _done := false


func _ready() -> void:
	print("R9P config mode=%s render=%s batch=%d seed=%d" % [
			_mode, str(_render), _batch, _seed])


func _process(_dt: float) -> void:
	if _done:
		return
	_eng += 1
	if _eng > TIMEOUT_FRAMES:
		_fail("engine timeout in phase %s cycle %d" % [_phase, _cycle])
		return
	# Heartbeat BEFORE the step call: an aborting step cannot eat it silently.
	if _eng % 120 == 0:
		print("R9P HB eng=%d cyc=%d phase=%s %s" % [_eng, _cycle, _phase,
				_state_str(_sim())])
	match _phase:
		"boot":
			_game = _build_game()
			_game.stages["menu"].start_new_game(0, "normal", _seed)
			_phase = "card"
		"card":
			_step(1)
			if _game.transition == null and _game.context.stage == "cell" \
					and _game.current.id == "cell":
				print("R9P landed dna=%d php=%.1f" % [
						int(_game.context.dna), float(_game.current.sim.php)])
				_phase = "cycle"
		"cycle":
			_cycle += 1
			if _cycle > CYCLES:
				_report()
				return
			var sim: Variant = _sim()
			if sim == null:
				_fail("no cell sim at cycle %d" % _cycle)
				return
			_dna0 = float(_game.context.dna)
			_chaos0 = float(_game.context.chaos)
			_watch_f = 0
			_chase_f = 0
			_stable = 0
			_expected_steps = 0
			_last_log_f = -30
			_cycle_time0 = float(sim.time)
			if _mode == "inject":
				sim.php = 0.0
				print("R9P INJECT cyc=%d dna0=%.0f php->0 chaos0=%.3f" % [
						_cycle, _dna0, _chaos0])
				_phase = "watch"
			else:
				print("R9P ARM cyc=%d dna0=%.0f php=%.1f chaos0=%.3f" % [
						_cycle, _dna0, float(sim.php), _chaos0])
				_phase = "chase"
		"chase":
			# the REAL r9 kill path: hug the nearest predator until it bites
			# the player to 0 (qc9 death-phase shape, chase batch 4)
			var sim2: Variant = _sim()
			if bool(sim2.deathStarted):
				_stop_hold()
				print("R9P DEATH_HIT cyc=%d chase_f=%d deathFade=%.4f dna %.0f→%.0f chaos %.3f→%.3f" % [
						_cycle, _chase_f, float(sim2.deathFade), _dna0,
						float(_game.context.dna), _chaos0,
						float(_game.context.chaos)])
				_watch_f = 0
				_last_log_f = -30
				_phase = "watch"
				return
			var pred: Variant = _nearest_predator(sim2)
			if pred == null:
				if _chase_f % 60 == 0:
					var a: float = _driver.rand() * TAU
					_hold_move(float(sim2.px) + cos(a) * 600.0,
							float(sim2.py) + sin(a) * 600.0)
			else:
				_hold_move(float(pred["x"]), float(pred["y"]))
			_chase_f += 4
			_expected_steps += 4
			_step(4)
			if _chase_f > CHASE_LIMIT:
				_fail("chase: never died hugging predators in %d sim frames (php=%s)" % [
						CHASE_LIMIT, str(sim2.php)])
		"watch":
			var sim3: Variant = _sim()
			if sim3 == null:
				_fail("no cell sim in watch (cycle %d)" % _cycle)
				return
			_step(_batch)
			_expected_steps += _batch
			if _render:
				_game._do_render(0.0)
			_watch_f += _batch
			# step-integrity: sim.time += dt is CellSim.update's first line —
			# lag means gated or aborted steps (dump names the gate; stderr
			# names a script error)
			var lag := _lag(sim3)
			if lag > 0:
				_lag_seen = maxi(_lag_seen, lag)
				print("R9P LAG cyc=%d f=%d lag=%d %s" % [
						_cycle, _watch_f, lag, _state_str(sim3)])
				if lag >= 3:
					_fail("sim steps aborted/gated: lag=%d %s" % [
							lag, _state_str(sim3)], 2)
					return
			if _nan(sim3):
				_fail("NaN in sim state: %s" % _state_str(sim3))
				return
			if _watch_f - _last_log_f >= 30:
				_last_log_f = _watch_f
				print("R9P W cyc=%d f=%d deathFade=%.4f deathStarted=%s php=%.4f simTime=%.3f %s" % [
						_cycle, _watch_f, float(sim3.deathFade),
						str(bool(sim3.deathStarted)), float(sim3.php),
						float(sim3.time), _state_str(sim3)])
			if bool(sim3.deathStarted):
				if _watch_f > WATCH_FRAMES:
					_fail("stall: deathStarted for %d watch frames (deathFade=%s) %s" % [
							_watch_f, str(sim3.deathFade), _state_str(sim3)])
				return
			# respawned — verify the full cycle once
			var r := Vector2(float(sim3.px), float(sim3.py)).length()
			var hp_ok: bool = float(sim3.php) >= float(sim3.pmaxHp) - 0.001
			var inv_ok: bool = float(sim3.invuln) > 3.9
			var r_tol := 2.0 + 4.0 * float(_batch)
			var r_ok: bool = absf(r - 600.0) < r_tol
			var dna_now := float(_game.context.dna)
			# chaos bump may race a settle drift — informational only
			print("R9P RESPAWN cyc=%d frames=%d r=%.1f php=%.1f/%.1f invuln=%.2f dna %.0f→%.0f (−%.0f) chaos %.3f→%.3f hp=%s inv=%s r_ok=%s" % [
					_cycle, _watch_f, r, float(sim3.php), float(sim3.pmaxHp),
					float(sim3.invuln), _dna0, dna_now, _dna0 - dna_now,
					_chaos0, float(_game.context.chaos), str(hp_ok),
					str(inv_ok), str(r_ok)])
			if not (hp_ok and inv_ok and r_ok):
				_fail("respawn broken (hp=%s inv=%s r_ok=%s r=%.1f)" % [
						str(hp_ok), str(inv_ok), str(r_ok), r])
				return
			_respawn_frames.append(_watch_f)
			_stable = 0
			_phase = "stable"
		"stable":
			_step(_batch)
			if _render:
				_game._do_render(0.0)
			_stable += _batch
			var sim4: Variant = _sim()
			if bool(sim4.deathStarted):
				_fail("re-death during stability window (f=%d deathFade=%s)" % [
						_stable, str(sim4.deathFade)])
				return
			if _stable >= STABLE_FRAMES:
				print("R9P STABLE cyc=%d (php=%.1f invuln=%.2f)" % [
						_cycle, float(sim4.php), float(sim4.invuln)])
				_phase = "cycle"


func _sim() -> Variant:
	if _game != null and _game.current != null and _game.current.id == "cell":
		return _game.current.get("sim")
	return null


func _lag(sim: Variant) -> int:
	var advanced := int(roundf((float(sim.time) - _cycle_time0) / DT))
	return _expected_steps - advanced


func _nan(sim: Variant) -> bool:
	return is_nan(float(sim.php)) or is_nan(float(sim.deathFade)) \
			or is_nan(float(sim.time))


func _state_str(sim: Variant) -> String:
	if sim == null:
		return "nosim"
	var trn: Variant = _game.transition
	return "paused=%s ed=%s trans=%s(%s) playtime=%.2f" % [
			str(bool(_game.paused)), str(bool(_game.editor["open"])),
			str(trn != null), str(trn["phase"]) if trn != null else "-",
			float(_game.context.playtime)]


func _report() -> void:
	var n := _respawn_frames.size()
	var mx := 0
	for f in _respawn_frames:
		mx = maxi(mx, int(f))
	print("R9P_PROBE_OK %d/%d %s-mode respawn cycles (render=%s batch=%d seed=%d, frames/cycle max %d)" % [
			n, CYCLES, _mode, str(_render), _batch, _seed, mx])
	print("R9P respawn_frames=%s max_lag=%d" % [str(_respawn_frames), _lag_seen])
	_done = true
	get_tree().quit(0)


func _fail(msg: String, code := 1) -> void:
	if _done:
		return
	_done = true
	var sim: Variant = _sim()
	printerr("R9P_PROBE_FAIL: " + msg)
	printerr("R9P state: cyc=%d phase=%s %s deathFade=%s deathStarted=%s" % [
			_cycle, _phase,
			_state_str(sim) if _game != null else "nogame",
			str(sim.deathFade) if sim != null else "-",
			str(sim.deathStarted) if sim != null else "-"])
	get_tree().quit(code)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(_seed)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	_driver = BotDriverScript.new()
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.register(CreatureStageScript.new(game))
	game.register(TribeStageScript.new(game))
	game.register(CivStageScript.new(game))
	game.register(SpaceStageScript.new(game))
	game.start()
	return game


func _step(n: int) -> void:
	_game.step_for_testing(n, DT)


func _hold_move(wx: float, wy: float) -> void:
	var s: Vector2 = _driver.world_to_screen(_game, wx, wy)
	if not _held_down:
		_driver.mouse_down(s)
		_held_down = true
	else:
		_driver.move_mouse(s)


func _stop_hold() -> void:
	if _held_down:
		_driver.mouse_up()
		_held_down = false


var _last_pred_dmg := -1.0


func _nearest_predator(sim: Variant) -> Variant:
	var best: Variant = null
	var bd := 1400.0
	for e in sim.ents:
		if float(e["hp"]) <= 0.0:
			continue
		var dmg := float(e["stats"].get("damage", 0.0))
		if dmg <= 0.0:
			continue
		var d: float = Vector2(float(e["x"]), float(e["y"])).distance_to(
				Vector2(float(sim.px), float(sim.py)))
		if d < bd:
			bd = d
			best = e
			_last_pred_dmg = dmg
	return best
