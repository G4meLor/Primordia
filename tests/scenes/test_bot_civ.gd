# Civ play-bot scene test — M5 task 5, the civ-stage parity gate. Drives the
# bot (tests/bots/bot_civ.gd) through the FULL arc on the REAL input pipeline
# — Input.parse_input_event + flush into _unhandled_input (Global Constraint
# 8): menu start → the cell stage PLAYED to landfall → the real F-hold charm
# + REAL FOUND A TRIBE click → the registered tribe stage LANDS → the tribe
# arc to the REAL victory (ALL of it bot_tribe's own legs — the founding→
# totem arc lands civ through the real go_to, NEVER re-implemented here) →
# the registered civ stage → the civ arc: the honest-launch gate's refusal at
# mil 4, the full-board Q transfer toast, TWO honest attack launches (the
# armada flight captured mid-flight — ship disc + dashed trail, numeric pixel
# asserts only), the resolves observed (the influence jump + the sim's own
# net math read back), regen refilling the lastRaised lane between launches,
# then the victory leg: the documented debug_set_influence grants + ONE real
# Digit1 launch completing unification → victoryFired → the space transition
# ({'THE BLACK OCEAN' / 'a planet was never going to be enough'}) landing the
# REGISTERED SpaceStage (M6 task 6 — the M5 unregistered-placeholder leg
# upgraded; the arc's post-landing continuation is Task 7's).
#
# Phases: per pass in [1, 2]: one game — arrival ticks → founding ticks →
# tribe ticks → civ ticks → asserts + fingerprint → next pass. Both passes
# run at bot LCG seed 777 / world seed 0xBEEF; the determinism gate compares
# the quantized CIV end-state fingerprints field-for-field across passes (the
# M2/M3/M4 ×2 pattern, with the bot's per-600-frame sweep trace as
# first-divergence triage — game.stages['civ'].sim, NEVER game.current.sim:
# the d7a5cb8 bot lesson). All pass → BOT_CIV_ALL_OK, exit 0; else
# BOT_CIV_FAIL on stderr, exit 1.
#
# Run (xvfb, rendering on — the real pipeline needs a live SceneTree):
#   tools/test_bot_civ.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_bot_civ.tscn
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
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const BotCivScript := preload("res://tests/bots/bot_civ.gd")
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")  # the WORLD_SEED pin lives on the arrival/founding legs

# The full arc rides the real raid clock (~75 s) plus the march/fight, the
# gather round trips, and the civ legs (two 6 s regen beats, three armada
# flights, the 3.35 s victory transition) — longer than the tribe bot's gate.
const TIMEOUT_FRAMES := 60000
const SLOTS := 3              # the save slots the flow writes — wiped after
const OUT_DIR := "user://visual_capture_civ_bot"

var _phase := "pass_build"
var _pass_i := 0              # 0-based; 2 passes for the determinism gate
var _frames := 0
var _done := false
var _game: Variant = null
var _bot: Variant = null
var _fps := [{}, {}]          # [{fp, trace}] per pass (determinism)


func _ready() -> void:
	_wipe_saves()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


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
			_bot = BotCivScript.new()  # fresh LCG (seed 777) per pass
			_game = _build_game()
			_phase = "arrival"
		"arrival":
			var ra: String = _bot.tb.cb.arrival_tick(_game)
			if ra == "OK":
				_phase = "founding"
			elif ra != "":
				_fail("pass %d arrival: %s" % [_pass_i + 1, ra])
		"founding":
			var rf: String = _bot.tb.cb.founding_tick(_game)
			if rf == "OK":
				_phase = "tribe"
			elif rf != "":
				_fail("pass %d founding: %s" % [_pass_i + 1, rf])
		"tribe":
			# the M4 bot's own legs — the totem arc lands the REGISTERED civ
			# stage through the real go_to (d7a5cb8); reused, never re-walked.
			# R14: the civ legs pin the TS base board (output 10 — the
			# full-board transfer + the mil-4 gate refusal), but the real
			# arc's creature exit snapshots the FULL web (ecoHealth 1.0 →
			# start output 22), which would make the Q raise free. Seed the
			# collapsed eco EVERY tribe-phase frame: the write lands after the
			# creature exit's own snapshot (it fires at the tribe landing,
			# inside this phase) and survives to switch_stage('civ') — the
			# tribe bot's OK only arrives AFTER the civ stage landed, so a
			# hand-off write would be too late. The eco-attached start output
			# is pinned headless (test_civ_world_attach.gd).
			_game.context.flags["ecoHealth"] = 0.0
			var rt: String = _bot.tb.tribe_tick(_game)
			if rt == "OK":
				_phase = "civ"
			elif rt != "":
				_fail("pass %d tribe (%s): %s" % [_pass_i + 1, _bot.tb._leg, rt])
		"civ":
			var rc: String = _bot.civ_tick(_game)
			if rc == "OK":
				_phase = "post"
			elif rc != "":
				_fail("pass %d civ (%s): %s" % [_pass_i + 1, _bot._leg, rc])
		"post":
			_test_post()
		"done":
			pass


# ---- phases -------------------------------------------------------------------

func _test_post() -> void:
	var fp: Dictionary = _bot.civ_fingerprint(_game)
	var sane: PackedStringArray = _bot.driver.sane_violations
	if not sane.is_empty():
		_fail("pass %d: sane violations %s" % [_pass_i + 1, str(sane)])
		return
	if not _bot.driver.delivery_ok:
		_fail("pass %d: an injected input event failed to reach the wrapper" % (_pass_i + 1))
		return
	# the arrival legs' authenticity (the reused bot_tribe module's latches)
	if not _bot.tb.delivery_seen:
		_fail("pass %d: no tribesman delivery was observed on the arrival legs" % (_pass_i + 1))
		return
	if not _bot.tb.raid_seen or not _bot.tb.raid_banner_seen:
		_fail("pass %d: the tribe raid lifecycle asserts did not latch (seen %s banner %s)" % [
				_pass_i + 1, str(_bot.tb.raid_seen), str(_bot.tb.raid_banner_seen)])
		return
	if not _bot.tb.totem_banner_seen:
		_fail("pass %d: the totem banner assert did not latch" % (_pass_i + 1))
		return
	# the civ arc's latches
	if not _bot.gate_refusal_seen:
		_fail("pass %d: the honest-launch gate's hopeless-refuse toast never fired" % (_pass_i + 1))
		return
	if not _bot.transfer_toast_seen:
		_fail("pass %d: the full-board transfer toast ('+1 mil ← culture') never fired" % (_pass_i + 1))
		return
	if _bot.launches_honest < 2:
		_fail("pass %d: only %d honest launches observed (want 2+)" % [
				_pass_i + 1, _bot.launches_honest])
		return
	if _bot.resolves_seen < 2 or _bot.floater_reads < 2:
		_fail("pass %d: the resolve observations did not latch (jumps %d floaters %d)" % [
				_pass_i + 1, _bot.resolves_seen, _bot.floater_reads])
		return
	if _bot.regen_refills != 2:
		_fail("pass %d: the lastRaised regen refills did not land 3→4→5 (%d)" % [
				_pass_i + 1, _bot.regen_refills])
		return
	if not _bot.capture_ok:
		_fail("pass %d: the mid-flight capture asserts did not pass (ship disc + trail)" % (_pass_i + 1))
		return
	if _bot.join_names.size() != 3:
		_fail("pass %d: the three 'JOINS YOUR PLANETARY STATE' banners did not latch (%s)" % [
				_pass_i + 1, str(_bot.join_names.keys())])
		return
	if String(_bot.victory_card.get("next", "")) != "space" \
			or String(_bot.victory_card.get("title", "")) != "THE BLACK OCEAN" \
			or String(_bot.victory_card.get("sub", "")) != "a planet was never going to be enough":
		_fail("pass %d: the space placeholder card did not capture (%s)" % [
				_pass_i + 1, str(_bot.victory_card)])
		return
	if not bool(fp["victory"]):
		_fail("pass %d: the end fingerprint does not carry victoryFired" % (_pass_i + 1))
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
		print("BOT_CIV_OK fp=%s" % str(fp))
	_drop_game()
	if _pass_i == 0:
		_pass_i = 1
		_phase = "pass_build"
		return
	_phase = "done"
	print("BOT_CIV_ALL_OK")
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
## factory): menu + cell + creature + tribe + civ + space registered at boot —
## main.gd parity since M6 (the civ victory lands the REGISTERED space stage)
## — manual stepping ONLY (the real _process would add wall-clock-clamped
## phantom steps).
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


## Free the finished Game before the next one — the Input singleton is shared,
## so a live second Game would double-consume every injected event.
func _drop_game() -> void:
	if _game != null:
		_game.free()
		_game = null


## The flow writes real slots (the start_new_game seed save, the shore flush,
## the editor's dirty close, found_tribe's save, the 60 s autosaves, the
## victory saves) — clean before and after.
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
	printerr("BOT_CIV_FAIL: " + msg)
	get_tree().quit(1)
