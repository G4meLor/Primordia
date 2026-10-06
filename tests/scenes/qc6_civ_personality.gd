# QC round 6 — civ rival-personality observation bot (agent civ-personality).
# Area: the three rival personalities as the PLAYER SEES them + the civ chaos
# deck (quake/rebellion/goldenage/worldwar [+ golden_rival/trade_winds if the
# world genome opens them]):
#   military (r1 Khorate Dominion) — shells the capital every tick_second
#     (-0.8*0.4 hp/s vs the capital's own +0.5/s heal → heal-dominant), the
#     2%/s "shells your capital!" toast + cam shake
#   culture (r2 Vexi Concord) — per YOUR city, 3%/s of a -1.5 influence erode
#     (vs your unrest heal +0.12/s → net near 0 — observed, not assumed)
#   economy (r3 Ompa Syndicate) — pop +0.05/s UNCAPPED (the TS:418 quirk) and
#     a 1%/s -2 influence buy on ANY city it does not own (yours included)
#   chaos — quake (-30 hp + burning + toast), rebellion (-40 on a NON-CAPITAL
#     owned city — the id exclusion no-ops while you hold only the capital),
#     goldenage (hp 100 / +15 inf / +2 pop), worldwar (-25 capital, WAR banner)
#
# The pre-civ arc rides bot_civ's composition (arrival → founding → tribe →
# the REAL go_to landing the registered civ stage — never re-implemented).
# The civ legs are OBSERVATION: p_idle1 (270 sim-s, capital only) watches the
# personalities + the chaos deck fire; p_grant flips r1's own city through the
# DOCUMENTED debug_set_influence seam (setup only — rebellion needs a
# non-capital owned city to have any target at all); p_hold2 (270 sim-s) keeps
# watching with 2 owned cities (rebellion hits, erode on 2 cities, the
# revolt→REVOLTS! arc when influence sinks ≤ -99.8).
#
# Every watch is a plain field read (hud._toasts/_banner_queue/_cur_banner,
# sim cities/debug_state); the only sim call is the documented grant. Real
# input pipeline is exercised by the arrival legs; the civ legs intentionally
# inject NOTHING so the personalities run undisturbed (the regen beats still
# tick — idle is what a watching player does).
#
# Run: xvfb-run -a godot --rendering-driver opengl3 --path . \
#          res://tests/scenes/qc6_civ_personality.tscn
# Pass → QC6_CIVP_ALL_OK, exit 0; else QC6_CIVP_FAIL on stderr, exit 1.
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
const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")  # the WORLD_SEED pin

const TIMEOUT_FRAMES := 60000
const SLOTS := 3
const BULK := 24  # sim ticks per engine frame (the qc6_civ_arc pacing)

# observation budgets (sim frames; 60 = 1 sim-second)
const IDLE1_S := 270.0
const HOLD2_S := 270.0

var _phase := "build"
var _frames := 0
var _done := false
var _game: Variant = null
var _bot: Variant = null

# ---- civ-legs state ----
var _leg := "p_idle1"
var _civ_f := 0                  # sim ticks since civ landed
var _granted := false

# per-second trace + delta counters (index = city index)
var _prev_inf := [0.0, 0.0, 0.0, 0.0]
var _prev_hp := [0.0, 0.0, 0.0, 0.0]
var _prev_pop := [0.0, 0.0, 0.0, 0.0]
var _prev_owner := ["", "", "", ""]
var _prev_burn := [0.0, 0.0, 0.0, 0.0]
var _erode_steps := [0, 0, 0, 0]     # -1.5 culture-rival procs
var _buy_steps := [0, 0, 0, 0]       # -2.0 economy-rival buys
var _reb_steps := [0, 0, 0, 0]       # ≤ -39 steps (rebellion-sized)
var _war_steps := 0                  # capital ≤ -24 steps (worldwar-sized)
var _rows := 0

# toast/banner latches (the player-visible surface)
var shell_toasts := 0               # "shells your capital!" DISTINCT arrivals
var quake_toasts := 0
var unrest_toasts := 0              # "Unrest in ... (-40 influence)"
var goldenage_toasts := 0
var surge_toasts := 0               # "A rival golden age!"
var tradewinds_toasts := 0
var war_banners := 0                # "DECLARES WAR"
var revolt_banners := 0             # "REVOLTS!"
var join_banners := 0               # "JOINS YOUR PLANETARY STATE"
var warn_banners := {}              # warn-phase titles seen
var chaos_apply_banners := {}       # apply-phase def names seen (🫨 MEGA-QUAKE…)
var _active_toast_texts := {}       # texts present last tick (distinct-arrival count)
var _traced_cities := ""            # last per-second row (for the fail message)


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
			_bot = BotCivScript.new()
			_game = _build_game()
			_phase = "arrival"
		"arrival":
			var ra := ""
			for _i in BULK:
				ra = _bot.tb.cb.arrival_tick(_game)
				if ra != "":
					break
			if ra == "OK":
				_phase = "founding"
			elif ra != "":
				_fail("arrival: %s" % ra)
		"founding":
			var rf := ""
			for _i in BULK:
				rf = _bot.tb.cb.founding_tick(_game)
				if rf != "":
					break
			if rf == "OK":
				_phase = "tribe"
			elif rf != "":
				_fail("founding: %s" % rf)
		"tribe":
			var rt := ""
			for _i in BULK:
				rt = _bot.tb.tribe_tick(_game)
				if rt != "":
					break
			if rt == "OK":
				_phase = "civ"
				_leg = "p_idle1"
				_frames = 0
				_civ_f = 0
				print("QC6CIVP civ landed, observation legs start")
			elif rt != "":
				_fail("tribe (%s): %s" % [_bot.tb._leg, rt])
		"civ":
			var rc := ""
			for _i in BULK:
				rc = _civ_tick(_game)
				if rc != "":
					break
			if rc == "OK":
				_phase = "post"
				_frames = 0
			elif rc != "":
				_fail("civ (%s): %s" % [_leg, rc])
		"post":
			_test_post()
		"done":
			pass


# ---- the civ legs ------------------------------------------------------------------

func _civ_tick(game: Variant) -> String:
	var sim: Variant = _bot.civ_sim(game)
	_civ_f += 1
	_bot.step(game, 1)
	_bot._watch(game)
	_watch_toasts(game)
	_city_sweep(sim)
	var t := float(sim.time)
	match _leg:
		"p_idle1":
			if _civ_f >= int(IDLE1_S * 60.0):
				print("QC6CIVP idle1 done t=%s shells=%d quake=%d war=%d ga=%d reb=%d" % [
						str(t), shell_toasts, quake_toasts, war_banners,
						goldenage_toasts, unrest_toasts])
				_leg = "p_grant"
				_frames = 0
				_civ_f = 0
			return ""
		"p_grant":
			if not _granted:
				sim.debug_set_influence(1, 100.5)  # the documented seam — setup only
				_granted = true
				print("QC6CIVP granted city1 influence 100.5 (hearts flip setup)")
			if String(sim.cities[1]["owner"]) == "you":
				if join_banners == 0:
					return "grant: city1 flipped but the JOINS banner never latched"
				print("QC6CIVP city1 flipped to you (banner %d)" % join_banners)
				_leg = "p_hold2"
				_frames = 0
				_civ_f = 0
			elif _civ_f > 60 * 20:
				return "grant: city1 never flipped (owner %s inf %s)" % [
						String(sim.cities[1]["owner"]), str(sim.cities[1]["influence"])]
			return ""
		"p_hold2":
			if _civ_f >= int(HOLD2_S * 60.0):
				print("QC6CIVP hold2 done t=%s revolt=%d unrest=%d erode=%s buys=%s" % [
						str(t), revolt_banners, unrest_toasts,
						str(_erode_steps), str(_buy_steps)])
				return "OK"
			return ""
	return ""


# ---- the watches -------------------------------------------------------------------

func _watch_toasts(game: Variant) -> void:
	var hud: Variant = game.stages["civ"].hud_inst
	if hud == null:
		return
	var now := {}
	for t in hud._toasts:
		var s := String(t["text"])
		now[s] = true
		if not _active_toast_texts.has(s):
			# a DISTINCT arrival of this toast text
			if s.contains("shells your capital"):
				shell_toasts += 1
			elif s.contains("Earthquake damages"):
				quake_toasts += 1
			elif s.contains("(-40 influence)"):
				unrest_toasts += 1
			elif s.contains("Golden age!"):
				goldenage_toasts += 1
			elif s.contains("rival golden age"):
				surge_toasts += 1
			elif s.contains("Trade winds"):
				tradewinds_toasts += 1
	for b in hud._banner_queue:
		_latch_banner(String(b.get("title", "")))
	if hud._cur_banner != null:
		_latch_banner(String(hud._cur_banner.get("title", "")))
	_active_toast_texts = now


func _latch_banner(title: String) -> void:
	if title.contains("DECLARES WAR"):
		war_banners += 1
	elif title.contains("REVOLTS!"):
		revolt_banners += 1
	elif title.contains("JOINS YOUR PLANETARY STATE"):
		join_banners += 1
	elif title.contains("Seismographs") or title.contains("Mobilization") \
			or title.contains("Foreign banners") or title.contains("Sails crowd"):
		warn_banners[title] = warn_banners.get(title, 0) + 1
	elif title.contains("MEGA-QUAKE") or title.contains("UNREST SPREADS") \
			or title.contains("GOLDEN AGE") or title.contains("WORLD WAR") \
			or title.contains("RIVAL GOLDEN AGE") or title.contains("TRADE WINDS"):
		chaos_apply_banners[title] = chaos_apply_banners.get(title, 0) + 1


## The per-sim-tick city delta sweep — runs AFTER the step, so every d is one
## tick's change. Steps are bucketed by their sim-source sizes:
##   erode -1.5 | buy -2.0 | rebellion -40 | worldwar -25 (capital)
## The unrest heal (+0.12/s) and the hearts drift (±0.02/s) ride between the
## buckets, so a bucket hit is exact-size evidence of that rival's agenda.
func _city_sweep(sim: Variant) -> void:
	var row_dirty := false
	for i in sim.cities.size():
		var c: Dictionary = sim.cities[i]
		var inf := float(c["influence"])
		var hp := float(c["hp"])
		var pop := float(c["pop"])
		var own := String(c["owner"])
		var burn := float(c["burning"])
		var dinf: float = inf - float(_prev_inf[i])
		var dhp: float = hp - float(_prev_hp[i])
		if _prev_owner[i] != "":
			if dinf <= -1.3 and dinf >= -1.7:
				_erode_steps[i] += 1
			elif dinf <= -1.9 and dinf >= -2.1:
				_buy_steps[i] += 1
			elif dinf <= -39.0:
				_reb_steps[i] += 1
			if i == 0 and dhp <= -24.0:
				_war_steps += 1
			if own != _prev_owner[i]:
				print("QC6CIVP OWNER c%d %s→%s (inf %s hp %s t %s)" % [i,
						_prev_owner[i], own, str(inf), str(hp), str(float(sim.time))])
				row_dirty = true
			if burn > 0.0 and _prev_burn[i] <= 0.0:
				print("QC6CIVP BURN c%d start (hp %s t %s)" % [i, str(hp), str(float(sim.time))])
				row_dirty = true
		_prev_inf[i] = inf
		_prev_hp[i] = hp
		_prev_pop[i] = pop
		_prev_owner[i] = own
		_prev_burn[i] = burn
	# a 1-row-per-sim-second trace (compact)
	if _civ_f % 60 == 0:
		var parts := ["t=%s" % str(_s1(float(sim.time)))]
		for i in sim.cities.size():
			var c: Dictionary = sim.cities[i]
			parts.append("c%d %s hp%s i%s p%s%s" % [i, String(c["owner"]).substr(0, 2),
					str(_s1(float(c["hp"]))), str(_s1(float(c["influence"]))),
					str(_s1(float(c["pop"]))),
					" B" if float(c["burning"]) > 0.0 else ""])
		_traced_cities = " ".join(parts)
		_rows += 1
		if _rows % 15 == 1:  # print every 15th row (~15 s) — the log stays small
			print("QC6CIVP ROW " + _traced_cities)
	if row_dirty:
		print("QC6CIVP ROW " + _traced_cities)


func _s1(v: float) -> String:
	return str(snappedf(v, 0.1))


# ---- post --------------------------------------------------------------------------

func _test_post() -> void:
	var sim: Variant = _bot.civ_sim(_game)
	_city_sweep(sim)  # final sweep so the tail deltas count
	var sane: PackedStringArray = _bot.driver.sane_violations
	if not sane.is_empty():
		_fail("sane violations %s" % str(sane))
		return
	if not _bot.driver.delivery_ok:
		_fail("an injected input event failed to reach the wrapper")
		return
	var owned := 0
	for c in sim.cities:
		if String(c["owner"]) == "you":
			owned += 1
	print("QC6CIVP_RESULT t=%s idle1=270s hold2=270s shells=%d quake=%d unrest=%d goldenage=%d surge=%d winds=%d war_b=%d revolt_b=%d join_b=%d erode=%s buys=%s reb=%s war_steps=%d warns=%s applies=%s owned_now=%d karma=%s chaos=%s" % [
			str(_s1(float(sim.time))), shell_toasts, quake_toasts, unrest_toasts,
			goldenage_toasts, surge_toasts, tradewinds_toasts, war_banners,
			revolt_banners, join_banners, str(_erode_steps), str(_buy_steps),
			str(_reb_steps), _war_steps, str(warn_banners), str(chaos_apply_banners),
			owned, str(_s1(float(_game.context.karma))),
			str(_s1(float(_game.context.chaos)))])
	# hard gates: the session PLAYED (observation time served on both legs)
	if float(sim.time) < IDLE1_S + 60.0:
		_fail("civ sim-time too short: %s (want idle1 270s + hold2 leg)" % str(sim.time))
		return
	if owned < 1:
		_fail("the board lost the capital (owned %d)" % owned)
		return
	if _erode_steps[0] + _erode_steps[1] + _erode_steps[2] + _erode_steps[3] == 0 \
			and _buy_steps[0] + _buy_steps[1] + _buy_steps[2] + _buy_steps[3] == 0 \
			and shell_toasts == 0:
		_fail("NO personality signal observed at all in 540 sim-s (shells %d, erode %s, buys %s)"
				% [shell_toasts, str(_erode_steps), str(_buy_steps)])
		return
	print("QC6_CIVP_ALL_OK")
	_wipe_saves()
	_done = true
	get_tree().quit(0)


# ---- helpers ----------------------------------------------------------------------

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


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("QC6_CIVP_FAIL: " + msg)
	if _traced_cities != "":
		printerr("QC6_CIVP_TRACE " + _traced_cities)
	get_tree().quit(1)
