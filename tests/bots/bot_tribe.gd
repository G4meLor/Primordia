## Tribe play-bot — M4 task 6. Drives the REAL input pipeline (Global
## Constraint 8) through the full tribe arc, riding bot_creature's now-real
## legs (tests/bots/bot_creature.gd): menu start → the cell stage PLAYED to
## landfall (real shore click) → the real F-hold charm + REAL FOUND A TRIBE
## click → the registered tribe stage LANDS (task 5) → then, in tribe:
## role hotkeys (Digit1/2 real taps) → a watched tribesman DELIVERY (+8 food)
## → a hut built through the REAL drawn R · HUT button (wood granted through
## the documented debug cheat) → the recruit gate observed → the FIRST RAID
## survived on the REAL raid clock (pinned seed — the hint toast + the
## '{NAME} RAIDS!' banner + raidActive true→false lifecycle, the war party
## fought off with a real Digit3 arm) → the Great Totem raised through the
## REAL drawn TOTEM button → the victory transition fires and 'civ' —
## unregistered in the bot scene — makes switch_stage no-op so the tribe
## stage remains (the M3 placeholder ruling pattern).
##
## TS AUTHORITY: no tribe bot test exists in the frozen repo (Spore/tests/
## holds bot/bot-arc/bot-creature only — bot-creature.test.ts ENDS at the
## tribe landing, :113-114), so per the task brief the cheat set mirrors the
## creature bot's TS-true family: direct start_new_game (bot.test.ts:62),
## debug_grant/debug_spawn_pack through their documented sim mutators,
## everything else real input. The tribe-specific cheat is
## tribe_sim.debug_grant(food, wood) — the ONE sim mutator this task adds
## (documented in the sim's debug-seam surface): the REAL button clicks gate
## on wood ≥ 40 (hut) and food ≥ 100 + wood ≥ 80 (totem, TribeStage.ts:530/
## 547) and would otherwise hold the legs hostage to gather round-trips.
##
## TICK SHAPE: the scene calls arrival_tick/founding_tick/tribe_tick once per
## _process frame. The rect reads here (the R · HUT and TOTEM buttons) ride
## the sim's hudRects — re-registered synchronously by the stage's
## render()/_sync_hud_rects (NOT a deferred canvas _draw record), so one
## explicit game._do_render(0.0) makes them readable in the same tick; the
## legs still poll tick-per-frame around the reads (the deferred-_draw lesson
## kept uniform). Every other watch is a plain field read: the raid banner
## and toasts poll the hud instance's live state (hud_inst._cur_banner /
## _toasts — the test_tribe_scene precedent), raid/hut/recruit state reads
## the named stage's sim.
##
## BOT LAW AUDIT: every input rides the driver (Input.parse_input_event +
## flush) — Digit1/2/3 taps, the hut/totem button clicks, the park
## held-mouse walk. Direct sim calls: debug_grant ONLY (the documented
## cheat above). Everything else is field reads: sim fields, hud_inst
## banner/toast lists, hudRects records.
##
## DETERMINISM: the full bot ×2 at LCG 777 / world 0xBEEF must produce
## identical quantized TRIBE fingerprints (game.stages['tribe'].sim — the
## task-5 lesson: NAME the stage, never game.current.sim, which aliases the
## creature stage's sim in the early legs) plus a per-600-frame sweep trace
## through the tribe legs (the M2/M3 pattern; failures print the first
## divergent sweep). All legs exit on sim-field conditions at deterministic
## frames, so the sweep indices align across passes.
extends RefCounted

const BotCreatureScript := preload("res://tests/bots/bot_creature.gd")

const DT := 1.0 / 60.0
const Z_TO_Y := 0.62          # tribe sim's z→screen-y (tribe_sim.gd)
const RECT_TICKS := 90        # a hud-rect poll budget in scene ticks (1.5 s)
const DELIVER_BUDGET := 60 * 70    # a gather round trip well inside the 75 s raid clock
const HUT_WAIT_BUDGET := 60 * 12   # buildT 6 s + toast margin
const RAID_WAIT_BUDGET := 60 * 150 # clock 75 s + march 1300-2000 @ ~48/s + the fight
const TOTEM_WAIT_BUDGET := 60 * 45 # workers·1.6·dt ≥ 4.8/s → ≤ 21 s + drift
const VICTORY_BUDGET := 60 * 12   # victoryT 2.5 s + the out/card/in transition
## The raid watch parks the chief out of raid-touch reach (warriors besiege
## the huts at the origin; the touch gate needs dist < 40, TS:504-515).
const PARK_WX := 600.0
const PARK_WZ := 225.0

var cb: Variant = null        # bot_creature — the now-real arrival + founding legs
var driver: Variant = null    # cb's driver — ONE LCG stream across the whole run
## Per-600-frame quantized sweep trace through the tribe legs (determinism
## triage; the hard gate is the end fingerprint).
var trace: Array = []

# latched observations (asserted at the leg ends)
var delivery_seen := false    # a Δfood that is a clean +8 multiple (a delivery)
var recruit_seen := false     # tribe grew past the founding roster
var hut_damaged := false      # any hut hp dipped below maxHp during the raid
var raid_banner_seen := false # the '{NAME} RAIDS!' center banner
var raid_hint_seen := false   # the 'Raiders rally…' first-raid toast
var totem_banner_seen := false # the 'THE GREAT TOTEM' center banner
var raid_seen := false        # raidActive observed true

# state machine
var _leg := "roles"
var _frames := 0              # leg-local budget counter (ticks; 1 sim frame each)
var _tribe_f := 0             # global tribe-frame counter (sweep trace phase)
var _tribe0 := 0              # founding roster size (the recruit latch baseline)
var _food0 := 0.0             # delivery-watch baseline
var _food_prev := 0.0         # per-frame Δfood detector
var _wood_before := 0.0       # click-deduction proofs
var _food_before := 0.0
var _huts_before := 0
var _hut_rect := Vector2.ZERO
var _totem_rect := Vector2.ZERO
var _rect_tries := 0
var _digit_armed := false     # the Digit3 war-party arm is one-shot


func _init() -> void:
	cb = BotCreatureScript.new()
	driver = cb.driver


# ---- shared ---------------------------------------------------------------------

func step(game: Variant, n: int) -> void:
	game.step_for_testing(n, DT)


func tribe_sim(game: Variant) -> Variant:
	# the task-5 lesson: NAME the stage — game.current.sim aliases the
	# creature stage's sim before the founding lands
	return game.stages["tribe"].sim


## Quantized tribe-state snapshot (the determinism gate + sweep rows): the
## village economy, roster, defenses, hazards and the victory latch.
func tribe_fingerprint(game: Variant) -> Dictionary:
	var sim: Variant = tribe_sim(game)
	var c: Variant = game.context
	return {
		"food": floori(float(sim.food) * 100.0),
		"wood": floori(float(sim.wood) * 100.0),
		"tribe": sim.tribe.size(),
		"huts": sim.huts.size(),
		"px": floori(float(sim.px) * 100.0),
		"pz": floori(float(sim.pz) * 100.0),
		"totemP": floori(float(sim.totem["progress"]) * 100.0),
		"totemA": bool(sim.totem["active"]),
		"day": floori(float(sim.dayPhase) * 1000.0),
		"time": floori(float(sim.time) * 100.0),
		"raidT": floori(float(sim.raidTimer) * 100.0),
		"trees": sim.trees.size(),
		"bushes": sim.bushes.size(),
		"warriors": sim.rivalWarriors.size(),
		"rivals": sim.rivals.size(),
		"fires": sim.fires.size(),
		"victory": bool(sim.victoryFired),
		"karma": floori(float(c.karma) * 1000.0),
		"chaos": floori(float(c.chaos) * 1000.0),
		"dna": floori(float(c.dna) * 100.0),
	}


## The per-frame watch every wait leg rides: latches the observations the
## leg ends assert (a field-read sweep — no sim calls, no input).
func _watch(game: Variant) -> void:
	var sim: Variant = tribe_sim(game)
	if sim.tribe.size() > _tribe0:
		recruit_seen = true
	for h in sim.huts:
		if float(h["hp"]) < float(h["maxHp"]) - 0.001:
			hut_damaged = true
	var hud: Variant = game.current.hud_inst
	if hud != null:
		if hud._cur_banner != null:
			var title := String(hud._cur_banner["title"])
			if title.contains("RAIDS!"):
				raid_banner_seen = true
			elif title.contains("THE GREAT TOTEM"):
				totem_banner_seen = true
		for t in hud._toasts:
			if String(t["text"]).contains("Raiders rally beyond the ridge"):
				raid_hint_seen = true


## One stepped tribe frame inside a wait leg: the sweep trace rides the
## GLOBAL tribe-frame counter so rows align across passes.
func _wait_step(game: Variant) -> void:
	_tribe_f += 1
	step(game, 1)
	_watch(game)
	if _tribe_f % 600 == 0:
		trace.append({"f": _tribe_f, "fp": tribe_fingerprint(game)})


## The raid-watch park: hold the chief at a fixed world point through REAL
## pointer events (the charm-walk vocabulary — a held mouse the stage's
## click-move chases; re-aimed every frame like the M2 step_loop's
## TS-setWorld replacement).
func _park_aim(game: Variant) -> void:
	var aim: Vector2 = driver.world_to_screen(game, PARK_WX, PARK_WZ * Z_TO_Y)
	if game.input.is_down():
		driver.move_mouse(aim)
	else:
		driver.mouse_down(aim)


func _park_release(game: Variant) -> void:
	if game.input.is_down():
		driver.mouse_up()


func _hud_rect_center(game: Variant, action: String) -> Variant:
	for b in tribe_sim(game).hudRects:
		if String(b["action"]) == action:
			var r: Dictionary = b["r"]
			return Vector2(float(r["x"]) + float(r["w"]) / 2.0,
					float(r["y"]) + float(r["h"]) / 2.0)
	return null


func _roles_of(sim: Variant) -> String:
	var out: Array = []
	for t in sim.tribe:
		out.append(String(t["role"]))
	return str(out)


# ---- the tribe arc (one tick per scene frame) --------------------------------------

## Returns "OK" when the full arc completed (the victory transition landed
## its civ no-op), "" while still walking, else the failure reason.
func tribe_tick(game: Variant) -> String:
	var sim: Variant = tribe_sim(game)
	match _leg:
		"roles":
			# role hotkeys through the REAL pipeline (TS:495-497 Digit1/2/3 →
			# assignRole "Everyone: {role}")
			_tribe0 = sim.tribe.size()
			driver.tap_key(KEY_2)
			step(game, 1)
			for t in sim.tribe:
				if String(t["role"]) != "hunt":
					return "roles: Digit2 did not arm every hunter (%s)" % _roles_of(sim)
			driver.tap_key(KEY_1)
			step(game, 1)
			for t in sim.tribe:
				if String(t["role"]) != "gather":
					return "roles: Digit1 did not re-arm every gatherer (%s)" % _roles_of(sim)
			_food0 = float(sim.food)
			_food_prev = _food0
			_leg = "deliver"
		"deliver":
			# watch a tribesman DELIVER (+8 food — the arrivals block's
			# tribe_arrive, TS:1088-1102). Δfood must be a clean multiple of
			# 8: rival kills also pay +8 but cannot fire before the first
			# raid reaches the village, while the beast's +60 and the
			# festival's −5 fail the modulo — a delivery is the only food
			# source of that shape here. Full soundness argument (the task-6
			# review's Minor 2): the raid CLOCK first fires at 75 s, but chaos
			# events launch PRE-clock raids via launch_rival_raid_now
			# (rivalsurprise, bold_raid) whose warrior deaths also pay +8 —
			# so "before the raid clock" alone is not sound in general. At
			# the pinned 0xBEEF world the gate's RESULT is verified sound:
			# the delivery latch fires at tribe-frame 1119 while the first
			# rival warriors of any kind appear at frame 4461 (the task-6
			# reviewer's instrumented probe), so no rival-kill +8 can precede
			# the latch. A seed change must re-derive this frame ordering.
			var d := float(sim.food) - _food_prev
			_food_prev = float(sim.food)
			if d > 0.001 and absf(fmod(d, 8.0)) < 0.001:
				delivery_seen = true
			_wait_step(game)
			_frames += 1
			if delivery_seen and float(sim.food) >= _food0 + 8.0:
				_frames = 0
				_leg = "hut_grant"
			elif _frames > DELIVER_BUDGET:
				return "deliver: no tribesman delivery in %d frames (food %s → %s)" % [
						DELIVER_BUDGET, str(_food0), str(sim.food)]
		"hut_grant":
			# the documented cheat: wood to 70 (the 40-wood hut + drift
			# margin), food untouched — the REAL R · HUT button click then
			# proves the sim's own gate (wood ≥ 40 checked BEFORE the
			# cooldown arms, TS:526-541)
			sim.debug_grant(float(sim.food), 70.0)
			if float(sim.wood) < 70.0:
				return "hut_grant: the debug grant did not land (wood %s)" % str(sim.wood)
			game._do_render(0.0)  # _sync_hud_rects runs synchronously in render
			_rect_tries = 0
			_leg = "hut_rect"
		"hut_rect":
			game._do_render(0.0)
			var c: Variant = _hud_rect_center(game, "hut")
			if c != null:
				_hut_rect = c
				_leg = "hut_click"
			else:
				_rect_tries += 1
				if _rect_tries > RECT_TICKS:
					return "hut_rect: no R · HUT rect in the sim's hudRects (%s)" % str(sim.hudRects)
		"hut_click":
			_huts_before = sim.huts.size()
			_wood_before = float(sim.wood)
			driver.mouse_down(_hut_rect)
			step(game, 1)
			driver.mouse_up()
			if sim.huts.size() != _huts_before + 1:
				return "hut_click: the drawn HUT button click did not build (huts %d → %d)" % [
						_huts_before, sim.huts.size()]
			if absf(float(sim.wood) - (_wood_before - 40.0)) > 0.001:
				return "hut_click: the hut did not cost 40 wood (%s → %s)" % [
						str(_wood_before), str(sim.wood)]
			_frames = 0
			_leg = "hut_wait"
		"hut_wait":
			# the 6 s build (toast 'A new hut raises the roof!') — and the
			# recruit gate's preconditions arm here: a BUILT second hut lifts
			# popCap to 7 with the roster still below it (TS:1134-1157)
			_wait_step(game)
			_frames += 1
			var built := true
			for h in sim.huts:
				if float(h["buildT"]) > 0.0:
					built = false
			if built:
				if sim.pop_cap() < _tribe0 + 1 or not sim.rivalWarriors.is_empty():
					return "hut_wait: recruit gate preconditions missing (popCap %d, raiders %d)" % [
							sim.pop_cap(), sim.rivalWarriors.size()]
				_frames = 0
				_leg = "raid_wait"
			elif _frames > HUT_WAIT_BUDGET:
				var bt := -1.0
				if not sim.huts.is_empty():
					bt = float(sim.huts[-1]["buildT"])
				return "hut_wait: the hut never finished building (buildT %s)" % str(bt)
		"raid_wait":
			# the FIRST RAID on the REAL clock (pinned seed: raidTimer 75 →
			# the launch is a deterministic frame) — park the chief out of
			# raid-touch, arm the war party with a real Digit3 when the raid
			# fires, and hold until the war_graves block closes the raid
			# (raidActive false once rivalWarriors empties, TS:709-717)
			if bool(sim.raidActive):
				raid_seen = true
				if not _digit_armed:
					driver.tap_key(KEY_3)
					_digit_armed = true
			_park_aim(game)
			_wait_step(game)
			_frames += 1
			if raid_seen and not bool(sim.raidActive) and sim.rivalWarriors.is_empty():
				_park_release(game)
				if not raid_banner_seen:
					return "raid_wait: the raid closed without the '{NAME} RAIDS!' banner"
				if not raid_hint_seen:
					return "raid_wait: the first-raid hint toast never fired (TS:334-336)"
				if not recruit_seen:
					return "raid_wait: the recruit gate never fired (tribe %d, popCap %d)" % [
							sim.tribe.size(), sim.pop_cap()]
				_frames = 0
				_leg = "totem_grant"
			elif _frames > RAID_WAIT_BUDGET:
				return "raid_wait: no raid lifecycle in %d frames (raidTimer %s, active %s, warriors %d)" % [
						RAID_WAIT_BUDGET, str(sim.raidTimer), str(sim.raidActive),
						sim.rivalWarriors.size()]
		"totem_grant":
			# the documented cheat: food 120 / wood 100 — the REAL TOTEM
			# button click then proves the sim's own gate (100 food + 80
			# wood, TS:543-559)
			sim.debug_grant(120.0, 100.0)
			if float(sim.food) < 100.0 or float(sim.wood) < 80.0:
				return "totem_grant: the debug grant did not land (food %s wood %s)" % [
						str(sim.food), str(sim.wood)]
			game._do_render(0.0)
			_rect_tries = 0
			_leg = "totem_rect"
		"totem_rect":
			game._do_render(0.0)
			var c2: Variant = _hud_rect_center(game, "totem")
			if c2 != null:
				_totem_rect = c2
				_leg = "totem_click"
			else:
				_rect_tries += 1
				if _rect_tries > RECT_TICKS:
					return "totem_rect: no TOTEM rect in the sim's hudRects (%s)" % str(sim.hudRects)
		"totem_click":
			_food_before = float(sim.food)
			_wood_before = float(sim.wood)
			driver.mouse_down(_totem_rect)
			step(game, 1)
			driver.mouse_up()
			if not bool(sim.totem["active"]):
				return "totem_click: the drawn TOTEM button click did not raise the totem (food %s wood %s)" % [
						str(sim.food), str(sim.wood)]
			if float(sim.food) >= _food_before or float(sim.wood) >= _wood_before:
				return "totem_click: the totem cost did not land (food %s→%s wood %s→%s)" % [
						str(_food_before), str(sim.food), str(_wood_before), str(sim.wood)]
			_frames = 0
			_leg = "totem_wait"
		"totem_wait":
			# progress += workers·dt·1.6 (TS:1160-1163) → ≥ 4.8/s with the
			# founding roster
			_wait_step(game)
			_frames += 1
			if _frames == 300 and float(sim.totem["progress"]) <= 0.0:
				return "totem_wait: totem progress did not advance with workers (%s after 5 s)" % str(sim.totem["progress"])
			if float(sim.totem["progress"]) >= 100.0:
				if not totem_banner_seen:
					return "totem_wait: the totem completed without the THE GREAT TOTEM banner"
				_frames = 0
				_leg = "victory"
			elif _frames > TOTEM_WAIT_BUDGET:
				return "totem_wait: totem never reached 100 (%s after %d frames, tribe %d)" % [
						str(sim.totem["progress"]), _frames, sim.tribe.size()]
		"victory":
			# victoryT > 2.5 → go_to('civ') (TS:400-409) — the civ card
			# fires even though 'civ' is unregistered (the hook fires first)
			_wait_step(game)
			_frames += 1
			if game.transition != null:
				if String(game.transition["next"]) != "civ":
					return "victory: wrong transition target (%s)" % str(game.transition)
				if String(game.transition["title"]) != "THE FIRST CITY" \
						or String(game.transition["sub"]) != "drums become laws; laws become empires":
					return "victory: wrong card (%s)" % str(game.transition)
				_frames = 0
				_leg = "victory_land"
			elif _frames > VICTORY_BUDGET:
				return "victory: the victory transition never fired (progress %s, victoryT %s)" % [
						str(sim.totem["progress"]), str(sim.victoryT)]
		"victory_land":
			# 'civ' is unregistered in the bot scene → switch_stage no-ops
			# (game.gd, TS game.ts:208-210) — the tribe stage REMAINS (the
			# M3 placeholder ruling pattern)
			_wait_step(game)
			_frames += 1
			if game.transition == null:
				if String(game.context.stage) != "tribe":
					return "victory_land: the unregistered civ switch did not no-op (%s)" % game.context.stage
				if game.current.id != "tribe":
					return "victory_land: the live stage is not the tribe stage (%s)" % game.current.id
				if not bool(sim.victoryFired):
					return "victory_land: victoryFired never latched"
				if game.stages.has("civ"):
					return "victory_land: civ is registered — the placeholder premise is broken"
				_leg = "done"
				return "OK"
			elif _frames > VICTORY_BUDGET:
				return "victory_land: the transition never completed (%d frames)" % _frames
	return ""
