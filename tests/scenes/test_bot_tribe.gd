# Tribe play-bot scene test — M4 task 6, the tribe-stage parity gate. Drives
# the bot (tests/bots/bot_tribe.gd) through the FULL arc on the REAL input
# pipeline — Input.parse_input_event + flush into _unhandled_input (Global
# Constraint 8): menu start → the cell stage PLAYED to landfall (bot_creature's
# arrival leg) → the real charm + REAL FOUND A TRIBE click (its founding leg,
# landing the REGISTERED tribe stage) → the tribe arc: role hotkeys, a watched
# +8 delivery, a hut built through the REAL drawn R · HUT button, the recruit
# gate, the first raid survived on the REAL clock (banner + raidActive
# lifecycle), the Great Totem raised through the REAL drawn TOTEM button, and
# the victory transition firing its unregistered-'civ' no-op so the tribe
# stage remains.
#
# Phases: per pass in [1, 2]: one game — arrival ticks → founding ticks →
# tribe ticks → asserts + fingerprint → next pass. Both passes run at bot LCG
# seed 777 / world seed 0xBEEF; the determinism gate compares the TRIBE
# end-state fingerprints field-for-field across passes (the M2/M3 ×2 pattern,
# with the bot's per-600-frame sweep trace as first-divergence triage). The
# tribe ticks poll per frame around the hud-rect reads (see the bot header).
# All pass → BOT_TRIBE_ALL_OK, exit 0; else BOT_TRIBE_FAIL on stderr, exit 1.
#
# Run (xvfb, rendering on — the real pipeline needs a live SceneTree):
#   tools/test_bot_tribe.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_bot_tribe.tscn
# xvfb REQUIRED: Input.flush_buffered_events dispatches into the SceneTree
# only with a real display server — headless silently drops the delivery
# (see test_bot_arc.gd's header).
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const BotTribeScript := preload("res://tests/bots/bot_tribe.gd")
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")  # the WORLD_SEED pin lives on the arrival/founding legs

# The full arc rides the real raid clock (~75 s) plus the march/fight and the
# gather round trips — the longest timeout in the suite by design.
const TIMEOUT_FRAMES := 60000
const SLOTS := 3              # the save slots the flow writes — wiped after

var _phase := "pass_build"
var _pass_i := 0              # 0-based; 2 passes for the determinism gate
var _frames := 0
var _done := false
var _game: Variant = null
var _bot: Variant = null
var _fps := [{}, {}]          # [{fp, trace}] per pass (determinism)


func _ready() -> void:
	_wipe_saves()


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	if _done:
		return
	match _phase:
		"pass_build":
			_phase = "game_build"
		"game_build":
			_bot = BotTribeScript.new()  # fresh LCG (seed 777) per pass
			_game = _build_game()
			_phase = "arrival"
		"arrival":
			var ra: String = _bot.cb.arrival_tick(_game)
			if ra == "OK":
				_phase = "founding"
			elif ra != "":
				_fail("pass %d arrival: %s" % [_pass_i + 1, ra])
		"founding":
			var rf: String = _bot.cb.founding_tick(_game)
			if rf == "OK":
				_phase = "tribe"
			elif rf != "":
				_fail("pass %d founding: %s" % [_pass_i + 1, rf])
		"tribe":
			var rt: String = _bot.tribe_tick(_game)
			if rt == "OK":
				_phase = "post"
			elif rt != "":
				_fail("pass %d tribe (%s): %s" % [_pass_i + 1, _bot._leg, rt])
		"post":
			_test_post()
		"done":
			pass


# ---- phases -------------------------------------------------------------------

func _test_post() -> void:
	var fp: Dictionary = _bot.tribe_fingerprint(_game)
	var sane: PackedStringArray = _bot.driver.sane_violations
	if not sane.is_empty():
		_fail("pass %d: sane violations %s" % [_pass_i + 1, str(sane)])
		return
	if not _bot.driver.delivery_ok:
		_fail("pass %d: an injected input event failed to reach the wrapper" % (_pass_i + 1))
		return
	if not _bot.delivery_seen:
		_fail("pass %d: no tribesman delivery was observed" % (_pass_i + 1))
		return
	if not _bot.raid_seen or not _bot.raid_banner_seen:
		_fail("pass %d: the raid lifecycle asserts did not latch (seen %s banner %s)" % [
				_pass_i + 1, str(_bot.raid_seen), str(_bot.raid_banner_seen)])
		return
	if not _bot.totem_banner_seen:
		_fail("pass %d: the totem banner assert did not latch" % (_pass_i + 1))
		return
	if not _bot.hut_damaged:
		_fail("pass %d: no hut siege damage was observed (the raid never touched a hut — "
				+ "the task-6 rider latch upgraded to an assert)" % (_pass_i + 1))
		return
	if _pass_i == 0:
		_fps[_pass_i] = {"fp": fp, "trace": _bot.trace}
	else:
		# second pass: quantized exacts must match field-for-field
		var fp0: Dictionary = _fps[0]["fp"]
		for k in fp:
			if fp0.get(k) != fp[k]:
				_fail("determinism: fingerprint %s differs (run1=%s run2=%s) first-divergence=%s" % [
						k, str(fp0.get(k)), str(fp[k]), _first_trace_divergence()])
				return
		print("BOT_TRIBE_OK fp=%s" % str(fp))
	_drop_game()
	if _pass_i == 0:
		_pass_i = 1
		_phase = "pass_build"
		return
	_phase = "done"
	print("BOT_TRIBE_ALL_OK")
	_wipe_saves()
	_done = true
	get_tree().quit(0)


# ---- helpers ------------------------------------------------------------------

## First divergent sweep between the two passes (determinism triage).
func _first_trace_divergence() -> String:
	var t1: Array = _fps[0]["trace"]
	var t2: Array = _bot.trace
	for i in range(mini(t1.size(), t2.size())):
		var r1s: String = str(t1[i])
		var r2s: String = str(t2[i])
		if r1s != r2s:
			return "sweep[%d] run1=%s run2=%s" % [i, r1s, r2s]
	return "none (divergence outside sweep points)"


## The REAL composition the bot flows through (main.gd's boot minus the
## factory): menu + cell + creature + tribe registered at boot — 'civ' is
## deliberately UNREGISTERED so the victory go_to no-ops (the M3 placeholder
## ruling pattern) — manual stepping ONLY (the real _process would add
## wall-clock-clamped phantom steps).
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
	game.start()
	return game


## Free the finished Game before the next one — the Input singleton is shared,
## so a live second Game would double-consume every injected event.
func _drop_game() -> void:
	if _game != null:
		_game.free()
		_game = null


## The flow writes real slots (the start_new_game seed save, the shore flush,
## the editor's dirty close, found_tribe's save, the 60 s autosaves, the
## victory save_all) — clean before and after.
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
	printerr("BOT_TRIBE_FAIL: " + msg)
	get_tree().quit(1)
