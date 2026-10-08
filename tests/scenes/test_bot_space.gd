# Space play-bot scene test — M6 task 7, the space-stage parity gate. Drives
# the bot (tests/bots/bot_space.gd) through the FULL arc on the REAL input
# pipeline — Input.parse_input_event + flush into _unhandled_input (Global
# Constraint 8): menu start → the cell stage PLAYED to landfall → the real
# F-hold charm + REAL FOUND A TRIBE click → the registered tribe stage LANDS
# → the tribe arc to the REAL victory (ALL of it bot_tribe's own legs) → the
# registered civ stage → the civ arc to the REAL unification victory (ALL of
# it bot_civ's own legs — the go_to('space') lands the REGISTERED SpaceStage,
# 38bf9fb) → the space arc: the WASD flight with the engine trail + the
# ship-hull capture, the R abduct (beam + cargo + the +10 first catch), the
# drawn panel SEED/SCAN clicks (the panel_rects dispatch end-to-end), the
# held-F fast-forward (generations climb, ecos churn, the ff tint), the G
# splice (the child slot, −15 DNA), the pirate siege survived (click-to-shoot
# kills OR the ttl lift), then the finale: debug_seed_colonies (the
# documented cheat) + ff to 3 thriving → THE CHAOS CORE AWAKENS → the core
# fly → d < 60 → endingDone + the win flush → THE CHAOS CORE ACCEPTS YOU →
# a real click dismisses → the sandbox returns (the ship visible, the calm
# objective).
#
# Phases: per pass in [1, 2]: one game — arrival ticks → founding ticks →
# tribe ticks → civ ticks → space ticks → asserts + fingerprint → next pass.
# Both passes run at bot LCG seed 777 / world seed 0xBEEF; the determinism
# gate compares the quantized SPACE end-state fingerprints field-for-field
# across passes (the M2-M5 ×2 pattern, with the bot's per-600-frame sweep
# trace as first-divergence triage — game.stages['space'].sim, NEVER
# game.current.sim: the d7a5cb8 bot lesson). All pass → BOT_SPACE_ALL_OK,
# exit 0; else BOT_SPACE_FAIL on stderr, exit 1.
#
# Run (xvfb, rendering on — the real pipeline needs a live SceneTree):
#   tools/test_bot_space.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_bot_space.tscn
# xvfb REQUIRED: Input.flush_buffered_events dispatches into the SceneTree
# only with a real display server — headless silently drops the delivery
# (see test_bot_civ.gd's header). Runtime: the civ arc (~8 min/pass) plus
# the space legs (~2-4 min/pass) — budget ~25 min for the ×2 gate.
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
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")  # the WORLD_SEED pin lives on the arrival/founding legs

# The full arc rides the real raid clock (~75 s), the civ legs, and the
# space legs (the flight, the beam, two ff holds, the siege wait + fight,
# the core fly, the ending) — the M5 civ gate ran ~31 fps under llvmpipe
# (~16 min wall for both passes ≈ 34k ticks); the space legs add ~5-8k
# ticks per pass, so the whole-run guard sits at 90k.
const TIMEOUT_FRAMES := 90000
const SLOTS := 3              # the save slots the flow writes — wiped after
const OUT_DIR := "user://visual_capture_space_bot"

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
			_bot = BotSpaceScript.new()  # fresh LCG (seed 777) per pass
			_game = _build_game()
			_phase = "arrival"
		"arrival":
			var ra: String = _bot.bc.tb.cb.arrival_tick(_game)
			if ra == "OK":
				_phase = "founding"
			elif ra != "":
				_fail("pass %d arrival: %s" % [_pass_i + 1, ra])
		"founding":
			var rf: String = _bot.bc.tb.cb.founding_tick(_game)
			if rf == "OK":
				_phase = "tribe"
			elif rf != "":
				_fail("pass %d founding: %s" % [_pass_i + 1, rf])
		"tribe":
			# the M4 bot's own legs — the totem arc lands the REGISTERED civ
			# stage through the real go_to (d7a5cb8); reused, never re-walked.
			# R14: the reused civ legs pin the TS base board (output 10) —
			# seed the collapsed eco EVERY tribe-phase frame like
			# test_bot_civ.gd's tribe branch (the creature exit's own snapshot
			# fires at the tribe landing, inside this phase; the tribe bot's
			# OK only arrives after the civ stage landed).
			_game.context.flags["ecoHealth"] = 0.0
			var rt: String = _bot.bc.tb.tribe_tick(_game)
			if rt == "OK":
				_phase = "civ"
			elif rt != "":
				_fail("pass %d tribe (%s): %s" % [_pass_i + 1, _bot.bc.tb._leg, rt])
		"civ":
			# the M5 bot's own legs — the unification victory lands the
			# REGISTERED space stage through the real go_to (38bf9fb);
			# reused, never re-walked
			var rc: String = _bot.bc.civ_tick(_game)
			if rc == "OK":
				_phase = "space"
			elif rc != "":
				_fail("pass %d civ (%s): %s" % [_pass_i + 1, _bot.bc._leg, rc])
		"space":
			var rs: String = _bot.space_tick(_game)
			if rs == "OK":
				_phase = "post"
			elif rs != "":
				_fail("pass %d space (%s): %s" % [_pass_i + 1, _bot._leg, rs])
		"post":
			_test_post()
		"done":
			pass


# ---- phases -------------------------------------------------------------------

func _test_post() -> void:
	var fp: Dictionary = _bot.space_fingerprint(_game)
	var sane: PackedStringArray = _bot.driver.sane_violations
	if not sane.is_empty():
		_fail("pass %d: sane violations %s" % [_pass_i + 1, str(sane)])
		return
	if not _bot.driver.delivery_ok:
		_fail("pass %d: an injected input event failed to reach the wrapper" % (_pass_i + 1))
		return
	# the arrival legs' authenticity (the reused bot_tribe module's latches)
	if not _bot.bc.tb.delivery_seen:
		_fail("pass %d: no tribesman delivery was observed on the arrival legs" % (_pass_i + 1))
		return
	if not _bot.bc.tb.raid_seen or not _bot.bc.tb.raid_banner_seen:
		_fail("pass %d: the tribe raid lifecycle asserts did not latch (seen %s banner %s)" % [
				_pass_i + 1, str(_bot.bc.tb.raid_seen), str(_bot.bc.tb.raid_banner_seen)])
		return
	if not _bot.bc.tb.totem_banner_seen:
		_fail("pass %d: the totem banner assert did not latch" % (_pass_i + 1))
		return
	# the civ arc's victory card (the reused bot_civ module's latch)
	if String(_bot.bc.victory_card.get("next", "")) != "space" \
			or String(_bot.bc.victory_card.get("title", "")) != "THE BLACK OCEAN" \
			or String(_bot.bc.victory_card.get("sub", "")) != "a planet was never going to be enough":
		_fail("pass %d: the space victory card did not capture (%s)" % [
				_pass_i + 1, str(_bot.bc.victory_card)])
		return
	# the space arc's latches — the fly
	if not _bot.thrust_seen or not _bot.trail_seen or not _bot.capture_ok:
		_fail("pass %d: the fly leg did not latch (thrust %s trail %s capture %s)" % [
				_pass_i + 1, str(_bot.thrust_seen), str(_bot.trail_seen), str(_bot.capture_ok)])
		return
	# the abduct: the beam, the cargo slot, the +10 first catch
	if not _bot.beam_seen or not _bot.ledger_first or not _bot.first_catch_pay10:
		_fail("pass %d: the abduct asserts did not latch (beam %s ledger %s pay %s)" % [
				_pass_i + 1, str(_bot.beam_seen), str(_bot.ledger_first),
				str(_bot.first_catch_pay10)])
		return
	# the panel clicks: the seed (colony + banner + the 20 spend) and the
	# scan (+15 + the flag)
	if not _bot.colony_born or not _bot.seeded_banner:
		_fail("pass %d: the SEED click asserts did not latch (colony %s banner %s)" % [
				_pass_i + 1, str(_bot.colony_born), str(_bot.seeded_banner)])
		return
	if not _bot.scanned_seen or not _bot.scan_pay15:
		_fail("pass %d: the SCAN click asserts did not latch (scanned %s pay %s)" % [
				_pass_i + 1, str(_bot.scanned_seen), str(_bot.scan_pay15)])
		return
	# the fast-forward: the hold, the ability slot, the growth + churn, the tint
	if not _bot.ff_hold_seen or not _bot.ff_ability_active \
			or not _bot.generations_climbed or not _bot.eco_churned or not _bot.ff_tint_ok:
		_fail("pass %d: the ff asserts did not latch (hold %s ability %s gens %s churn %s tint %s)" % [
				_pass_i + 1, str(_bot.ff_hold_seen), str(_bot.ff_ability_active),
				str(_bot.generations_climbed), str(_bot.eco_churned), str(_bot.ff_tint_ok)])
		return
	# the splice: the child slot at the −15 spend
	if not _bot.splice_child:
		_fail("pass %d: the splice child slot did not latch" % (_pass_i + 1))
		return
	# the siege: survived (the kill path or the ttl lift — whichever the seed dealt)
	if not _bot.siege_seen or not _bot.siege_lift:
		_fail("pass %d: the siege did not latch (seen %s lift %s kills %d)" % [
				_pass_i + 1, str(_bot.siege_seen), str(_bot.siege_lift), _bot.siege_kills])
		return
	# the finale: the cheat's 3 colonies, the AWAKENS banner, the core fly,
	# the ending, the win flush, the dismissal, the sandbox handed back
	if not _bot.awakens_seen or not _bot.pulls_seen:
		_fail("pass %d: the finale latches did not fire (awakens %s pulls %s)" % [
				_pass_i + 1, str(_bot.awakens_seen), str(_bot.pulls_seen)])
		return
	if not _bot.ending_fired or not _bot.win_flush_ok:
		_fail("pass %d: the ending did not fire with the win flush (done %s flush %s)" % [
				_pass_i + 1, str(_bot.ending_fired), str(_bot.win_flush_ok)])
		return
	if not _bot.ending_seen or not _bot.dismissed_seen \
			or not _bot.calm_objective or not _bot.ship_returned:
		_fail("pass %d: the dismissal asserts did not latch (title %s dismissed %s calm %s ship %s)" % [
				_pass_i + 1, str(_bot.ending_seen), str(_bot.dismissed_seen),
				str(_bot.calm_objective), str(_bot.ship_returned)])
		return
	# the end fingerprint's own outcome rows (the ×2 gate compares them too)
	if not bool(fp["endingDone"]) or not bool(fp["endingDismissed"]):
		_fail("pass %d: the end fingerprint does not carry the dismissed ending" % (_pass_i + 1))
		return
	var colonies := 0
	var thriving := 0
	for i in 6:
		if int(fp["p%d_pop" % i]) >= 0:
			colonies += 1
			if int(fp["p%d_pop" % i]) >= 2000:
				thriving += 1
	if colonies < 3 or thriving < 3:
		_fail("pass %d: the end fingerprint lacks 3 thriving colonies (%d colonies, %d thriving)" % [
				_pass_i + 1, colonies, thriving])
		return
	if int(fp["cargo"]) != 1 or not String(fp["cargoNames"]).contains("(spliced)"):
		_fail("pass %d: the end fingerprint does not carry the spliced child (%s)" % [
				_pass_i + 1, str(fp["cargoNames"])])
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
		print("BOT_SPACE_OK fp=%s" % str(fp))
	_drop_game()
	if _pass_i == 0:
		_pass_i = 1
		_phase = "pass_build"
		return
	_phase = "done"
	print("BOT_SPACE_ALL_OK")
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
	printerr("BOT_SPACE_FAIL: " + msg)
	get_tree().quit(1)
