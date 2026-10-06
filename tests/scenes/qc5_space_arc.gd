# QC round 5 — agent-space-arc golden-path scene. Boots the REAL Game (all six
# stages registered, manual stepping — the test_bot_space pattern), pins a
# start_new_game seed, jumps to the space stage through the REAL transition,
# then walks the WHOLE space arc on the real input pipeline via the proven
# bot_space module (fly → abduct → seed → scan → abduct2 → abduct3 → ff →
# splice → siege → finale → core fly → ending). No debug setters anywhere;
# the only direct sim call is bot_space's debug_seed_colonies finale cheat
# (documented seam). Prints QC5_SPACE_<LEG>_OK markers as legs latch.
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

const WORLD_SEED := 48879  # 0xBEEF — the M6 bot pin
const TIMEOUT_FRAMES := 60000

var _phase := "boot"
var _frames := 0
var _game: Variant = null
var _bot: Variant = null
var _marked := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://qc5_space_arc")


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	match _phase:
		"boot":
			_game = _build_game()
			_game.step_for_testing(1, 1.0 / 60.0)
			_bot = BotSpaceScript.new()
			# real menu stage instance → the real start_new_game (documented
			# bot cheat, bot.test.ts:62)
			_game.stages["menu"].start_new_game(0, "normal", WORLD_SEED)
			_phase = "card"
		"card":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.transition == null:
				# the CELL card fully landed — jump to space through the real
				# switch (registers hud, builds the sim, fires the objective)
				_game.switch_stage("space")
				_phase = "space_settle"
		"space_settle":
			_game.step_for_testing(1, 1.0 / 60.0)
			if _game.stages["space"].sim != null and _game.current.id == "space":
				var sim: Variant = _game.stages["space"].sim
				print("QC5_SPACE_LANDED planets=%d dna=%d objective_set=%s" % [
					sim.planets.size(), int(_game.context.dna),
					str(_game.stages["space"].hud_inst != null)])
				_phase = "space"
		"space":
			var rs: String = _bot.space_tick(_game)
			if rs == "OK":
				_phase = "post"
			elif rs != "":
				_fail("space (%s): %s" % [_bot._leg, rs])
		"post":
			_report()
			_phase = "done"
		"done":
			pass


func _report() -> void:
	var sane: PackedStringArray = _bot.driver.sane_violations
	if not sane.is_empty():
		_fail("sane violations %s" % str(sane))
		return
	if not _bot.driver.delivery_ok:
		_fail("an injected input event failed to reach the wrapper")
		return
	_leg_mark("FLY", _bot.thrust_seen and _bot.trail_seen and _bot.capture_ok)
	_leg_mark("ABDUCT", _bot.beam_seen and _bot.ledger_first and _bot.first_catch_pay10)
	_leg_mark("SEED", _bot.colony_born and _bot.seeded_banner)
	_leg_mark("SCAN", _bot.scanned_seen and _bot.scan_pay15)
	_leg_mark("FF", _bot.ff_hold_seen and _bot.ff_ability_active
			and _bot.generations_climbed and _bot.eco_churned and _bot.ff_tint_ok)
	_leg_mark("SPLICE", _bot.splice_child)
	_leg_mark("SIEGE", _bot.siege_seen and _bot.siege_lift, " kills=%d" % _bot.siege_kills)
	_leg_mark("FINALE", _bot.awakens_seen and _bot.pulls_seen)
	_leg_mark("ENDING", _bot.ending_fired and _bot.win_flush_ok
			and _bot.ending_seen and _bot.dismissed_seen
			and _bot.calm_objective and _bot.ship_returned)
	var fp: Dictionary = _bot.space_fingerprint(_game)
	print("QC5_SPACE_ALL_OK dna=%d cargo=%s colonies_thriving_read=fp" % [
		int(fp["dna"]), str(fp["cargoNames"])])
	get_tree().quit(0)


func _leg_mark(name_v: String, ok: bool, suffix := "") -> void:
	if ok:
		print("QC5_SPACE_%s_OK%s" % [name_v, suffix])
	else:
		print("QC5_SPACE_%s_MISS%s" % [name_v, suffix])


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(WORLD_SEED)
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


func _fail(msg: String) -> void:
	printerr("QC5_SPACE_FAIL: " + msg)
	get_tree().quit(1)
