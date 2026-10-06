# QC round 6 — civ revolt-moment probe (agent civ-personality).
# Run 2 (qc6_civ_personality) proved the personalities + rebellion hits live
# but ended before the REVOLTS! threshold. This probe rides the same Game API
# the visual test uses (switch_stage — real Game method, the menu's own path)
# to land civ directly, flips r1's city (the documented grant seam), lets ONE
# real rebellion hit land, then sets the flipped city's influence just above
# the revolt gate (debug_set_influence — the civ-edge precedent) so the NEXT
# real rebellion hit crosses -99.8 and the REVOLTS! arc runs:
#   banner "%name REVOLTS!" (kind danger) + owner returns to the FORMER owner
#   (by id — Khora gets its own city back) + influence reset -100
#   + POST-REVOLT: r1 owns a city again → its military personality RESUMES
#     (shell toasts return) — the mirror of the conquest-blackout observation.
# Everything else is idle observation — real sim time, no input beyond the seams.
#
# Run: xvfb-run -a godot --rendering-driver opengl3 --path . \
#          res://tests/scenes/qc6_civp_revolt.tscn
# Pass → QC6_CIVP_REVOLT_OK, exit 0; else QC6_CIVP_REVOLT_FAIL, exit 1.
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

const TIMEOUT_FRAMES := 60000
const SLOTS := 3
const BULK := 24

# leg budgets (sim seconds)
const ARM_S := 150.0     # wait for the FIRST real rebellion hit
const REVOLT_S := 300.0  # wait for the revolt after the -65 arm
const AFTER_S := 60.0    # post-revolt watch (shell resumption)

var _phase := "build"
var _frames := 0
var _done := false
var _game: Variant = null
var _driver: Variant = null

var _leg := "r_boot"
var _civ_f := 0
var _granted_flip := false
var _armed := false
var _unrest_seen := 0
var _revolt_seen := false
var _shell_total := 0
var _shell_post_revolt := 0
var _revolt_t := -1.0
var _owner_changes: Array = []
var _prev_owner := ""
var _active_toasts := {}
var _last_row := ""


func _ready() -> void:
	_wipe_saves()


func _process(_dt: float) -> void:
	_frames += 1
	if _done:
		return
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s leg %s (frame %d)" % [_phase, _leg, _frames])
		return
	match _phase:
		"build":
			_game = _build_game()
			_driver = BotDriverScript.new()
			_phase = "civ"
		"civ":
			var rc := ""
			for _i in BULK:
				rc = _civ_tick()
				if rc != "":
					break
			if rc == "OK":
				_phase = "post"
			elif rc != "":
				_fail("civ (%s): %s" % [_leg, rc])
		"post":
			_test_post()
		"done":
			pass


func _civ_tick() -> String:
	var stage: Variant = _game.stages["civ"]
	if stage.sim == null or stage.hud_inst == null:
		return ""
	var sim: Variant = stage.sim
	_game.step_for_testing(1, 1.0 / 60.0)
	_civ_f += 1
	_watch_toasts()
	var own := String(sim.cities[1]["owner"])
	if _prev_owner != "" and own != _prev_owner:
		_owner_changes.append("t%s:%s→%s" % [str(snappedf(float(sim.time), 0.1)),
				_prev_owner, own])
		print("QC6CIVPR OWNER1 %s" % _owner_changes.back())
	_prev_owner = own
	if _civ_f % 120 == 0:
		_last_row = "t=%s c1 %s i%s hp%s | unrest=%d revolt=%s shells=%d/%d" % [
				str(snappedf(float(sim.time), 0.1)), own,
				str(snappedf(float(sim.cities[1]["influence"]), 0.1)),
				str(snappedf(float(sim.cities[1]["hp"]), 0.1)),
				_unrest_seen, str(_revolt_seen), _shell_post_revolt, _shell_total]
		if _civ_f % 1200 == 0:
			print("QC6CIVPR ROW " + _last_row)
	match _leg:
		"r_boot":
			if _civ_f >= 120:
				print("QC6CIVPR civ live t=%s" % str(snappedf(float(sim.time), 0.1)))
				_leg = "r_flip"
				_civ_f = 0
			return ""
		"r_flip":
			if not _granted_flip:
				sim.debug_set_influence(1, 100.5)  # documented seam — setup
				_granted_flip = true
			if own == "you":
				print("QC6CIVPR flip done t=%s — waiting for a REAL rebellion hit" % [
						str(snappedf(float(sim.time), 0.1))])
				_leg = "r_arm"
				_civ_f = 0
			elif _civ_f > 60 * 20:
				return "flip never landed (owner %s)" % own
			return ""
		"r_arm":
			# the first REAL -40 on city1 (rebellion needs a non-capital owned city)
			if _unrest_seen > 0:
				print("QC6CIVPR rebellion hit #1 observed (inf %s) — arming -65" % [
						str(snappedf(float(sim.cities[1]["influence"]), 0.1))])
				sim.debug_set_influence(1, -65.0)  # one hit from the gate
				_armed = true
				_leg = "r_revolt"
				_civ_f = 0
			elif _civ_f > int(ARM_S * 60.0):
				return "no rebellion hit in %ds (unrest %d)" % [int(ARM_S), _unrest_seen]
			return ""
		"r_revolt":
			if own != "you":
				if not _revolt_seen:
					return "city1 left my hands with NO REVOLTS banner (owner %s)" % own
				_revolt_t = float(sim.time)
				print("QC6CIVPR REVOLTED t=%s owner back to %s" % [
						str(snappedf(_revolt_t, 0.1)), own])
				_leg = "r_after"
				_civ_f = 0
			elif _revolt_seen and own == "you":
				# banner latched while the owner flip tick is next — hold
				pass
			elif _civ_f > int(REVOLT_S * 60.0):
				return "no revolt in %ds after the -65 arm (inf %s, unrest %d)" % [
						int(REVOLT_S),
						str(snappedf(float(sim.cities[1]["influence"]), 0.1)), _unrest_seen]
			return ""
		"r_after":
			if _civ_f >= int(AFTER_S * 60.0):
				return "OK"
			return ""
	return ""


func _watch_toasts() -> void:
	var hud: Variant = _game.stages["civ"].hud_inst
	if hud == null:
		return
	var now := {}
	for t in hud._toasts:
		var s := String(t["text"])
		now[s] = true
		if not _active_toasts.has(s):
			if s.contains("(-40 influence)"):
				_unrest_seen += 1
			elif s.contains("shells your capital"):
				_shell_total += 1
				if _leg == "r_after" or _revolt_seen:
					_shell_post_revolt += 1
	for b in hud._banner_queue:
		_latch_banner(String(b.get("title", "")))
	if hud._cur_banner != null:
		_latch_banner(String(hud._cur_banner.get("title", "")))
	_active_toasts = now


func _latch_banner(title: String) -> void:
	if title.contains("REVOLTS!") and not _revolt_seen:
		_revolt_seen = true
		print("QC6CIVPR REVOLTS banner: " + title)


func _test_post() -> void:
	var stage: Variant = _game.stages["civ"]
	var sim: Variant = stage.sim
	print("QC6CIVPR_RESULT t=%s unrest=%d revolt_banner=%s owner_changes=%s shells_total=%d shells_post_revolt=%d" % [
			str(snappedf(float(sim.time), 0.1)), _unrest_seen, str(_revolt_seen),
			str(_owner_changes), _shell_total, _shell_post_revolt])
	if not _revolt_seen:
		_fail("the REVOLTS banner never latched")
		return
	if _owner_changes.size() < 2:
		_fail("city1 never round-tripped (changes %s)" % str(_owner_changes))
		return
	print("QC6_CIVP_REVOLT_OK")
	_wipe_saves()
	_done = true
	get_tree().quit(0)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(20261001)
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
	game.switch_stage("civ")  # the visual test's real-Game entry (setup bypass)
	return game


func _wipe_saves() -> void:
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for i in SLOTS:
			if dir.file_exists("slot%d.json" % i):
				dir.remove("slot%d.json" % i)


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("QC6_CIVP_REVOLT_FAIL: " + msg)
	if _last_row != "":
		printerr("QC6CIVPR_TRACE " + _last_row)
	get_tree().quit(1)
