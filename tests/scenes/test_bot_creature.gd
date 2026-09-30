# Creature play-bot scene test — Task 9, the creature-stage parity gate.
# Port of Spore tests/bot-creature.test.ts onto the M2 bot-arc harness shape
# (tests/scenes/test_bot_arc.gd): the bot (tests/bots/bot_creature.gd) drives
# the REAL input pipeline — Input.parse_input_event + flush into
# _unhandled_input (Global Constraint 8) — through the FULL creature flow:
# menu start → the cell stage PLAYED to landfall (real editor leg buy + real
# shore click — the TS toCreature goTo cheat has no native analog) → the
# 2-minute chaos survival loop → the founding (debug_* cheats + a real F-hold
# charm + a real tribe-button click → the tribe-placeholder transition).
#
# Phases: per pass in [1, 2]: test-1 game (arrival ticks → chaos → asserts →
# fingerprint) → test-2 game (arrival ticks → founding ticks → asserts →
# fingerprint) → next pass. Both passes run at bot LCG seed 777 / world seed
# 0xBEEF; the determinism gate compares BOTH fingerprints field-for-field
# across passes (the M2 bot-arc ×2 pattern). The bot's rect reads (editor
# rows, shore button, tribe button) need a SceneTree draw flush between
# ticks — hence one bot tick per _process frame around those reads (see the
# bot header). All pass → BOT_CREATURE_ALL_OK, exit 0; else
# BOT_CREATURE_FAIL on stderr, exit 1.
#
# Run (xvfb, rendering on — the real pipeline needs a live SceneTree):
#   tools/test_bot_creature.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_bot_creature.tscn
# xvfb REQUIRED: Input.flush_buffered_events dispatches into the SceneTree
# only with a real display server — headless silently drops the delivery
# (see test_bot_arc.gd's header).
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")

# NO tribe stage registered (M4): the founding go_to('tribe') no-ops in
# switch_stage and the card + fade complete on the creature stage — that IS
# the tribe placeholder (the task-4 report ruling). Registering a stub here
# would fake the landing the real boot will see.

const TIMEOUT_FRAMES := 7200  # real-frame guard for the WHOLE run
const SLOTS := 3              # the save slots the flow writes — wiped after

var _phase := "pass_build"
var _pass_i := 0              # 0-based; 2 passes for the determinism gate
var _test_i := 0              # 0 = chaos survival, 1 = founding
var _frames := 0
var _done := false
var _game: Variant = null
var _bot: Variant = null
var _fps := [{}, {}]          # [test][{fp, trace}] per pass (determinism)


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
			_test_i = 0
			_phase = "game_build"
		"game_build":
			_bot = BotCreatureScript.new()  # fresh LCG (seed 777) per test
			_game = _build_game()
			_phase = "arrival"
		"arrival":
			var ra: String = _bot.arrival_tick(_game)
			if ra == "OK":
				_phase = "run"
			elif ra != "":
				_fail("pass %d test %d: %s" % [_pass_i + 1, _test_i + 1, ra])
		"run":
			if _test_i == 0:
				# the chaos loop has no rect reads — one synchronous tick
				var r1: String = _bot.chaos_survival(_game)
				if r1 != "OK":
					_fail("pass %d test 1 (chaos): %s" % [_pass_i + 1, r1])
					return
				_phase = "post"
			else:
				var r2: String = _bot.founding_tick(_game)
				if r2 == "OK":
					_phase = "post"
				elif r2 != "":
					_fail("pass %d test 2 (founding): %s" % [_pass_i + 1, r2])
		"post":
			_test_post()
		"done":
			pass


# ---- phases -------------------------------------------------------------------

func _test_post() -> void:
	var fp: Dictionary = _bot.creature_fingerprint(_game)
	var sane: PackedStringArray = _bot.driver.sane_violations
	if not sane.is_empty():
		_fail("pass %d test %d: sane violations %s" % [_pass_i + 1, _test_i + 1, str(sane)])
		return
	if not _bot.driver.delivery_ok:
		_fail("pass %d test %d: an injected input event failed to reach the wrapper"
				% [_pass_i + 1, _test_i + 1])
		return
	if _pass_i == 0:
		_fps[_test_i] = {"fp": fp, "trace": _bot.trace}
	else:
		# second pass: quantized exacts must match field-for-field
		var fp0: Dictionary = _fps[_test_i]["fp"]
		for k in fp:
			if fp0.get(k) != fp[k]:
				_fail("determinism test %d: fingerprint %s differs (run1=%s run2=%s) first-divergence=%s" % [
						_test_i + 1, k, str(fp0.get(k)), str(fp[k]),
						_first_trace_divergence(_test_i)])
				return
		print("BOT_CREATURE_OK test=%d fp=%s" % [_test_i + 1, str(fp)])
	_drop_game()
	_test_i += 1
	if _test_i >= 2:
		if _pass_i == 0:
			_pass_i = 1
			_phase = "pass_build"
			return
		_phase = "done"
		print("BOT_CREATURE_ALL_OK")
		_wipe_saves()
		_done = true
		get_tree().quit(0)
		return
	_phase = "game_build"


# ---- helpers ------------------------------------------------------------------

## First divergent sweep between the two passes of a test (determinism triage).
func _first_trace_divergence(test_i: int) -> String:
	var t1: Array = _fps[test_i]["trace"]
	var t2: Array = _bot.trace
	for i in range(mini(t1.size(), t2.size())):
		var r1s: String = str(t1[i])
		var r2s: String = str(t2[i])
		if r1s != r2s:
			return "sweep[%d] run1=%s run2=%s" % [i, r1s, r2s]
	return "none (divergence outside sweep points)"


## The REAL composition the bot flows through (main.gd's boot minus the
## factory — the bot never starts a NEW LIFE mid-run): menu + cell + creature
## registered at boot, manual stepping ONLY (see test_bot_arc.gd — the real
## _process would add wall-clock-clamped phantom steps).
func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(BotCreatureScript.WORLD_SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.register(CreatureStageScript.new(game))
	game.start()
	return game


## Free the finished Game before the next one — the Input singleton is shared,
## so a live second Game would double-consume every injected event.
func _drop_game() -> void:
	if _game != null:
		_game.free()
		_game = null


## The flow writes real slots (the start_new_game seed save, the shore flush,
## the editor's dirty close, found_tribe's ctx.save) — clean before and after.
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
	printerr("BOT_CREATURE_FAIL: " + msg)
	get_tree().quit(1)
