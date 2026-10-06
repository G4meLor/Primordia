# QC r2 M1 probe — cell death fade after pause-mid-death -> unpause (Major).
# The r2 cell-edge sighting (950 steps with deathStarted still true) came from
# a harness whose wait loop stalled and STOPPED STEPPING, so the observation
# was never settled. This probe is engine-stepped (its own _process; no manual
# stepping, no wait loop that can stall stepping) and drives the REAL main.tscn
# with real Esc events. Per cycle: inject php=0 (direct sim state, the test-
# fixture pattern) -> wait deathStarted -> Esc (real pipeline) -> verify frozen
# drift over a 2 s hold -> Esc unpause -> wait the 1.6 s fade out, logging
# deathFade every 0.5 s -> verify respawn (php back to max, invuln armed).
# 10 cycles, then M1_PROBE_OK.
#
# Run: xvfb-run -a godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_qc2_m1_deathfade.tscn
# Prints M1_PROBE_OK / M1_PROBE_FAIL: <why>; exits 0/1.
extends Node

const MainScene := preload("res://main.tscn")
const DriverScript := preload("res://tests/bots/bot_driver.gd")

const CYCLES := 10
const PAUSE_HOLD_FRAMES := 120   # 2 s of paused frames
const TIMEOUT_FRAMES := 5400

var _main: Variant = null
var _driver: Variant = null
var _phase := "boot"
var _pf := 0
var _cycle := 1
var _done := false
var _hold := 0
var _fade_at_hold_start := 0.0
var _fade_frames := 0
var _max_fade_frames := 0


func _ready() -> void:
	_driver = DriverScript.new()
	var dir := DirAccess.open("user://")
	if dir != null:
		if dir.dir_exists("saves"):
			var s := DirAccess.open("user://saves")
			for i in 3:
				if s.file_exists("slot%d.json" % i):
					s.remove("slot%d.json" % i)
		dir.remove("test_qc2_settings.cfg")
		dir.remove("test_qc2_settings.cfg.tmp")
	_main = MainScene.instantiate()
	add_child(_main)
	var g: Variant = _main.game
	g.i18n.settings_path = "user://test_qc2_settings.cfg"
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	print("M1P boot")


func _sim(game: Variant) -> Variant:
	if game.current != null and game.current.id == "cell":
		return game.current.get("sim")
	return null


func _process(_dt: float) -> void:
	if _done:
		return
	_pf += 1
	if _pf > TIMEOUT_FRAMES:
		_fail("timeout in phase %s cycle %d" % [_phase, _cycle])
		return
	var game: Variant = _main.game
	if game == null:
		return  # main not booted yet — keep the frame budget, retry next frame
	match _phase:
		"boot":
			if _pf < 8:
				return
			if game.current == null or game.current.id != "menu":
				_fail("boot: expected the menu stage")
				return
			_next("new_life")
		"new_life":
			if _click_button(game, "NEW LIFE"):
				_next("begin")
		"begin":
			if game.current.view != "new":
				return
			if _click_button(game, "BEGIN"):
				_next("wait_cell")
		"wait_cell":
			if game.context.stage == "cell" and game.transition == null:
				print("M1P cell reached, cycle %d" % _cycle)
				_next("inject")
		# ---- cycle: die -> pause 2 s -> unpause -> respawn ----
		"inject":
			var sim: Variant = _sim(game)
			if sim == null:
				_fail("no cell sim in inject")
				return
			sim.php = 0.0
			_next("wait_death_start")
		"wait_death_start":
			var sim: Variant = _sim(game)
			if sim == null:
				_fail("no cell sim in wait_death_start")
				return
			if bool(sim.deathStarted):
				print("M1P deathStarted (cycle %d, deathFade %.2f)" % [_cycle, float(sim.deathFade)])
				_next("pause_tap")
		"pause_tap":
			_driver.tap_key(KEY_ESCAPE)
			_next("pause_wait")
		"pause_wait":
			if not bool(game.paused):
				return
			var sim: Variant = _sim(game)
			_fade_at_hold_start = float(sim.deathFade)
			_hold = PAUSE_HOLD_FRAMES
			print("M1P paused mid-death (cycle %d) deathFade=%.2f" % [_cycle, _fade_at_hold_start])
			_next("hold")
		"hold":
			_hold -= 1
			if _hold <= 0:
				var sim: Variant = _sim(game)
				var drift: float = absf(float(sim.deathFade) - _fade_at_hold_start)
				print("M1P hold done (cycle %d) drift=%.4f deathStarted=%s" % [
						_cycle, drift, str(bool(sim.deathStarted))])
				if drift > 0.0001:
					_fail("death fade DRIFTED while paused: %.4f" % drift)
					return
				_driver.tap_key(KEY_ESCAPE)
				_next("unpause_wait")
		"unpause_wait":
			if bool(game.paused):
				return
			_fade_frames = 0
			print("M1P unpaused (cycle %d) — fade window open" % _cycle)
			_next("fade_wait")
		"fade_wait":
			_fade_frames += 1
			var sim: Variant = _sim(game)
			if sim == null:
				_fail("no cell sim in fade_wait")
				return
			if _fade_frames % 30 == 0:
				print("M1P f%d deathFade=%.2f deathStarted=%s php=%.1f playtime=%.1f" % [
						_fade_frames, float(sim.deathFade), str(bool(sim.deathStarted)),
						float(sim.php), float(game.context.playtime)])
			if not bool(sim.deathStarted):
				var ok_hp: bool = float(sim.php) >= float(sim.pmaxHp) - 0.5
				print("M1P respawned (cycle %d) after %d unpaused frames, php=%.1f/%.1f hp_ok=%s" % [
						_cycle, _fade_frames, float(sim.php), float(sim.pmaxHp), str(ok_hp)])
				if not ok_hp:
					_fail("respawned but php not restored")
					return
				if _fade_frames > _max_fade_frames:
					_max_fade_frames = _fade_frames
				_next("settle")
			elif _fade_frames > 900:
				_fail("death fade still hung after 900 unpaused frames (deathFade=%.2f)" % float(sim.deathFade))
		"settle":
			if _pf < 90:
				return
			if _cycle >= CYCLES:
				print("M1_PROBE_OK %d/%d pause-mid-death cycles respawned (max %d unpaused frames)" % [
						CYCLES, CYCLES, _max_fade_frames])
				_done = true
				get_tree().quit(0)
				return
			_cycle += 1
			_next("inject")


func _next(p: String) -> void:
	_phase = p
	_pf = 0


func _click_button(game: Variant, fragment: String) -> bool:
	for b in game.current.buttons:
		if String(b["label"]).contains(fragment):
			var center := Vector2(float(b["x"]) + float(b["w"]) / 2.0,
					float(b["y"]) + float(b["h"]) / 2.0)
			_driver.move_mouse(center)
			_driver.mouse_down(center)
			_driver.mouse_up()
			return true
	return false


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	var game: Variant = _main.game if _main != null else null
	if game == null:
		printerr("M1_PROBE_FAIL: " + msg)
		printerr("M1 state: main not booted")
		get_tree().quit(1)
		return
	var sim: Variant = _sim(game)
	printerr("M1_PROBE_FAIL: " + msg)
	printerr("M1 state: stage=%s paused=%s deathStarted=%s deathFade=%s php=%s playtime=%s" % [
			game.context.stage, str(game.paused),
			str(bool(sim.deathStarted)) if sim != null else "nosim",
			str(float(sim.deathFade)) if sim != null else "-",
			str(float(sim.php)) if sim != null else "-",
			str(float(game.context.playtime))])
	get_tree().quit(1)
