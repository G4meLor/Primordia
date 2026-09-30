## Creature play-bot — Task 9. Port of Spore tests/bot-creature.test.ts (the
## creature-stage bot) onto the M2 bot-driver vocabulary (tests/bots/
## bot_driver.gd). Global Constraint 8 (bot parity law): every input rides
## Input.parse_input_event + flush through the REAL pipeline — the TS bot's
## input.debugDown/debugUp/debugPress cheats and its direct
## game.goTo/foundTribe calls have NO native analog:
##   - arrival: the TS toCreature helper cheats (`genome.legs = 2` +
##     `game.goTo('creature')`, bot-creature.test.ts:42-43); the native bot
##     PLAYS the cell stage to landfall instead — menu start (start_new_game
##     direct, the one TS-true cheat the TS bot itself uses, bot.test.ts:62),
##     a messy-play burst, a REAL KeyE → legs-'+'-click → KeyE editor pass,
##     then a REAL click on the drawn 🐢 CRAWL ASHORE button → the real
##     cell→creature transition (the task-9 brief: "none needed here if shore
##     flow works").
##   - founding: the TS test 2 cheats `c.genome.brain = 3; c.dna = 999` +
##     debugSpawnPack(2) + a direct stage.foundTribe(). The native bot keeps
##     the two sim cheats through their documented debug_* mutators
##     (debug_grant — the ONE sim mutator added by this task — and
##     debug_spawn_pack), befriends one more member through a REAL F-hold
##     charm (the beat bar driven by real Space taps), and founds through a
##     REAL click on the drawn FOUND A TRIBE button (bot law — stronger than
##     the TS direct call).
##
## TICK SHAPE: the scene calls arrival_tick/founding_tick once per _process
## frame. The button rects this bot must read (the editor's row_rects, the
## shore button, the tribe button) are recorded inside DEFERRED canvas _draw
## passes (cell _draw_ui / creature _draw_ui / editor draw) — a synchronous
## loop would never see them, so every rect read sits in its own tick: render
## in tick T, the SceneTree flushes the draw between ticks, read in tick T+1
## (the test_editor_click phase shape). Everything without a rect read stays
## a synchronous sub-loop (the burst, the transition walks, the chaos loop,
## the charm).
##
## Chaos loop (test 1) is a 1:1 port of bot-creature.test.ts:67-90 — same
## cadences (move f%70==0/down …40, Space f%150==80, KeyF f%400==300, Tab
## f%900==500 then 560, render f%600==0, sanity sweep f%600==0), the same
## stale-aim shape (debugState taken once before the loop, TS st.px) — with
## the native additions the brief pins: dayPhase advanced, ≥1 chaos event
## fired (the creature scheduler's gap is 40s — chaos.gap, creature_sim
## constructor — so 2 min guarantees ≥1), player alive-or-respawned at the
## end, and a per-frame chaos-fire watch (field scan of the scheduler's
## active list — a read, not a sim call).
##
## Determinism: the full bot run ×2 at LCG seed 777 (TS `let seed = 777`)
## and world seed 0xBEEF (TS GameContext(0xbeef)) must produce identical
## quantized fingerprints (the M2 bot-arc pattern).
extends RefCounted

const BotDriverScript := preload("res://tests/bots/bot_driver.gd")
const PartsScript := preload("res://src/evo/parts.gd")

const DT := 1.0 / 60.0
const WORLD_SEED := 0xBEEF   # TS bot-creature: new GameContext(0xbeef)
const LCG_SEED := 777        # TS bot-creature: let seed = 777
const Z_TO_Y := 0.62         # creature sim's z→screen-y (creature_sim.gd)
const TRANSITION_POLL := 600 # brief AC: ≤ 600 frames for the arrival card
const CARD_STEPS := 180      # the M2 prologue card slot (bot.test.ts:72)
const SETTLE := 60 * 3       # brief AC: 60·3 settle after the arrival card
const BURST_FRAMES := 240    # the cell messy-play burst before the editor
const CHAOS_FRAMES := 60 * 120  # TS: f < 60 * 120
const CHARM_MAX := 60 * 90   # charm beat: 90 s of sim time before giving up
const RECT_TICKS := 90       # a rect-draw poll budget in scene ticks (1.5 s)

var driver: Variant = null
## Chaos-watch: an event reached its ACTIVE phase during the 2-min loop.
var saw_active_chaos := false
## Per-sweep (every 600 frames) quantized state trace — determinism failures
## print the first divergent sweep instead of just the end fingerprint.
var trace: Array = []

# tick state machines
var _arr := "boot"
var _arr_steps := 0
var _arr_ticks := 0
var _plus := Vector2.ZERO
var _legs_before := 0
var _fnd := "grant"
var _fnd_tries := 0


func _init() -> void:
	driver = BotDriverScript.new()
	driver.lcg_seed = LCG_SEED


# ---- shared helpers --------------------------------------------------------------

func step(game: Variant, n: int) -> void:
	game.step_for_testing(n, DT)


func pack_count(sim: Variant) -> int:
	var n := 0
	for e in sim.ents:
		if bool(e["pack"]) and not e.has("corpseT"):
			n += 1
	return n


## Quantized creature-state fingerprint (the M2 determinism gate, creature
## fields): ents/pack counts + floor(pos·100) + floor(dna·100) +
## floor(chaos·1000) + floor(dayPhase·1000) + floor(php·100).
func creature_fingerprint(game: Variant) -> Dictionary:
	var sim: Variant = game.current.sim
	var c: Variant = game.context
	return {
		"ents": sim.ents.size(),
		"pack": pack_count(sim),
		"px": floori(float(sim.px) * 100.0),
		"pz": floori(float(sim.pz) * 100.0),
		"dna": floori(float(c.dna) * 100.0),
		"chaos": floori(float(c.chaos) * 1000.0),
		"day": floori(float(sim.dayPhase) * 1000.0),
		"php": floori(float(sim.php) * 100.0),
	}


## Nearest WILD ent mirroring try_charm's eligibility filter exactly
## (creature_sim.try_charm: pack/corpse/baby/packCd>0 excluded) — the bot
## must only ever chase ents the sim would let it charm.
func nearest_charmable(sim: Variant) -> Variant:
	var best: Variant = null
	var bd := INF
	for e in sim.ents:
		if bool(e["pack"]) or e.has("corpseT") or bool(e["baby"]) \
				or float(e["packCd"]) > 0.0:
			continue
		var dx: float = float(e["x"]) - float(sim.px)
		var dz: float = float(e["z"]) - float(sim.pz)
		var d: float = sqrt(dx * dx + dz * dz)
		if d < bd:
			best = e
			bd = d
	return best


func _ent_by_eid(sim: Variant, eid: int) -> Variant:
	if eid < 0:
		return null
	for e in sim.ents:
		if int(e["eid"]) == eid:
			return e
	return null


func _dist_to(sim: Variant, e: Variant) -> float:
	var dx: float = float(e["x"]) - float(sim.px)
	var dz: float = float(e["z"]) - float(sim.pz)
	return sqrt(dx * dx + dz * dz)


## The '+' rect for a part row, read from the LIVE stage's editor row-rect
## records (draw-populated; the test_editor_click helper, verbatim shape).
func read_plus_rect(game: Variant, part_id: String) -> Variant:
	var rects: Array = game.current.editor_inst.row_rects
	var found := {}
	for rr in rects:
		if rr["btn"] != null and String(rr["btn"]) == "+" \
				and String(rr["row"]["kind"]) == "part" \
				and String(rr["row"]["def"]["id"]) == part_id:
			found = rr["r"]
	if found.is_empty():
		return null
	return Vector2(float(found["x"]) + float(found["w"]) / 2.0,
			float(found["y"]) + float(found["h"]) / 2.0)


# ---- the arrival (menu start → cell played to landfall → creature) ---------------

## Real-flow arrival, one tick per scene frame. Returns "OK" when the creature
## stage is reached and settled, "" while still walking, else the failure.
func arrival_tick(game: Variant) -> String:
	match _arr:
		"boot":
			# prologue: boot → menu → new game → cell card (the M2 prologue
			# shape; start_new_game direct = TS-bot parity, bot.test.ts:62 —
			# the world seed rides along because the real menu replaces the
			# context world)
			step(game, 5)
			if String(game.context.stage) != "menu":
				return "arrival: expected menu after 5 steps, got %s" % game.context.stage
			var menu: Variant = game.current
			menu.start_new_game(0, "normal", WORLD_SEED)
			_arr_steps = 0
			_arr = "cell_walk"
		"cell_walk":
			step(game, 1)
			_arr_steps += 1
			if String(game.context.stage) == "cell":
				step(game, CARD_STEPS)  # the CELL STAGE card + fade-in
				_arr = "burst"
			elif _arr_steps >= TRANSITION_POLL:
				return "arrival: cell not reached within %d steps" % TRANSITION_POLL
		"burst":
			# the cell phase PLAYED to landfall: a short messy burst through
			# the real pipeline (the M2 step_loop); the arrival grant (dna
			# 100) already covers LEG's 65
			driver.step_loop(game, BURST_FRAMES, DT)
			if not driver.sane_violations.is_empty():
				return "arrival: sane violations in the cell burst: %s" % str(driver.sane_violations)
			if not driver.delivery_ok:
				return "arrival: an injected input failed to reach the wrapper in the burst"
			_arr = "editor_open"
		"editor_open":
			# REAL editor pass: KeyE open, then the legs '+' click
			driver.tap_key(KEY_E)
			step(game, 1)
			if not bool(game.editor["open"]):
				return "arrival: KeyE through the real pipeline did not open the editor"
			game._do_render(0.0)  # queued; the draw flushes before the next tick
			_arr_ticks = 0
			_arr = "editor_rect"
		"editor_rect":
			var plus: Variant = read_plus_rect(game, "legs")
			if plus != null:
				_plus = plus
				_legs_before = int(game.context.genome["legs"])
				_arr = "legs_click"
			else:
				_arr_ticks += 1
				if _arr_ticks > RECT_TICKS:
					return "arrival: no legs '+' rect in the editor's row-rect records"
				game._do_render(0.0)
		"legs_click":
			var dna_before := int(game.context.dna)
			driver.mouse_down(_plus)
			step(game, 1)
			driver.mouse_up()
			if int(game.context.genome["legs"]) != _legs_before + 1:
				return "arrival: the legs click did not bump legs (%s → %s, dna %d → %d)" % [
						str(_legs_before), str(game.context.genome["legs"]),
						dna_before, int(game.context.dna)]
			driver.tap_key(KEY_E)
			step(game, 1)  # blocked branch: editor.update closes (dirty save — the scene wipes slots)
			if bool(game.editor["open"]):
				return "arrival: the legs-phase KeyE did not close the editor"
			step(game, 2)  # live steps: the shore gate reads the new legs per update
			game._do_render(0.0)
			_arr_ticks = 0
			_arr = "shore_rect"
		"shore_rect":
			# REAL landfall: poll the drawn 🐢 CRAWL ASHORE button
			var r: Dictionary = game.current.sim.shoreRect
			if float(r["x"]) >= 100.0:
				_arr = "shore_click"
			else:
				_arr_ticks += 1
				if _arr_ticks > RECT_TICKS:
					return "arrival: the shore button never drew (legs %s, shoreAvailable %s)" % [
							str(game.context.genome["legs"]),
							str(game.current.sim.shoreAvailable)]
				step(game, 1)
				game._do_render(0.0)
		"shore_click":
			var r2: Dictionary = game.current.sim.shoreRect
			driver.mouse_down(Vector2(float(r2["x"]) + float(r2["w"]) / 2.0,
					float(r2["y"]) + float(r2["h"]) / 2.0))
			step(game, 1)
			driver.mouse_up()
			if game.transition == null:
				return "arrival: the shore click did not start the creature handoff"
			_arr_steps = 0
			_arr = "creature_walk"
		"creature_walk":
			# poll ≤ 600 frames for the arrival card (brief AC)
			step(game, 1)
			_arr_steps += 1
			if String(game.context.stage) == "creature":
				_arr = "settle"
			elif _arr_steps >= TRANSITION_POLL:
				return "arrival: creature stage not reached within %d steps" % TRANSITION_POLL
		"settle":
			step(game, SETTLE)  # the 60·3 settle (brief AC)
			if game.transition != null:
				return "arrival: the transition never finished (card/fade stuck)"
			if game.current.id != "creature":
				return "arrival: landed on %s" % game.current.id
			_arr = "done"
			return "OK"
	return ""


# ---- test 1: 2 simulated minutes of chaos (bot-creature.test.ts:51-91) -----------

## 1:1 cadence port with the brief's native additions. Synchronous (no rect
## reads inside). Returns "OK" or the failure reason.
func chaos_survival(game: Variant) -> String:
	var sim: Variant = game.current.sim
	# TS takes debugState ONCE and aims at the stale px/pz all run
	# (bot-creature.test.ts:59 — `const st = stage.debugState` before the loop)
	var st: Dictionary = sim.debug_state()
	var day0: float = float(sim.dayPhase)
	saw_active_chaos = false
	for f in range(CHAOS_FRAMES):
		if f % 70 == 0:
			driver.mouse_down(Vector2(
					float(st["px"]) + (driver.rand() - 0.5) * 600.0,
					(float(st["pz"]) + (driver.rand() - 0.5) * 300.0) * Z_TO_Y
					+ game.vh / 2.0))
		if f % 70 == 40:
			driver.mouse_up()
		if f % 150 == 80:
			driver.tap_key(KEY_SPACE)   # jump
		if f % 400 == 300:
			driver.tap_key(KEY_F)       # charm attempt
		if f % 900 == 500:
			driver.tap_key(KEY_TAB)     # editor open
		if f % 900 == 560:
			driver.tap_key(KEY_TAB)     # editor close
		# delivery proofs at the first cadence hits (the M2 driver's live
		# check pattern: parse+flush must land in the wrapper immediately)
		if f == 0 and not game.input.is_down():
			return "chaos f=0: the move mouse-down did not reach the wrapper"
		if f == 40 and game.input.is_down():
			return "chaos f=40: the mouse-up did not reach the wrapper"
		if f == 80 and not game.input.key_pressed("Space"):
			return "chaos f=80: the Space press did not reach the wrapper"
		if f == 300 and not game.input.key_pressed("KeyF"):
			return "chaos f=300: the KeyF press did not reach the wrapper"
		if f == 500 and not game.input.key_pressed("Tab"):
			return "chaos f=500: the Tab press did not reach the wrapper"
		if f % 600 == 0:
			game._do_render(0.0)        # periodic render smoke (bot.test.ts:103)
		# chaos-fire watch — a FIELD scan (bot law: no sim method calls); any
		# scheduler entry reaching its active phase counts as fired
		for a in sim.chaos._active:
			if String(a["phase"]) == "active":
				saw_active_chaos = true

		step(game, 1)

		if f % 600 == 0:
			var c: Variant = game.context
			var s2: Dictionary = sim.debug_state()
			# the TS sanity sweep (bot-creature.test.ts:80-88), NaN-hardened
			if not is_finite(float(c.dna)):
				return "chaos f=%d: dna not finite" % f
			if float(c.dna) < 0.0:
				return "chaos f=%d: dna < 0 (%s)" % [f, str(c.dna)]
			if not is_finite(float(s2["px"])) or not is_finite(float(s2["pz"])):
				return "chaos f=%d: player position not finite" % f
			if float(s2["pmaxHp"]) > 0.0 \
					and float(s2["php"]) > float(s2["pmaxHp"]) + 0.001:
				return "chaos f=%d: php > pmaxHp + 0.001 (%s > %s)" % [f,
						str(s2["php"]), str(s2["pmaxHp"])]
			trace.append({"f": f, "fp": creature_fingerprint(game)})

	if String(game.context.stage) != "creature":
		return "chaos: stage left creature (%s)" % game.context.stage
	if not driver.sane_violations.is_empty():
		return "chaos: assert_sane-style violations: %s" % str(driver.sane_violations)
	# alive or died-and-respawned: the sim auto-respawns after the 1.8s fade,
	# so php > 0 at the end covers both branches of the AC claim
	if float(sim.php) <= 0.0:
		return "chaos: player neither alive nor respawned (php %s)" % str(sim.php)
	if not float(sim.dayPhase) > day0:
		return "chaos: dayPhase did not advance (%s → %s)" % [str(day0), str(sim.dayPhase)]
	if not saw_active_chaos:
		return "chaos: no chaos event fired in 2 min (gap-40 cadence)"
	if sim.ents.is_empty():
		return "chaos: world did not respond to play — ents empty"
	return "OK"


# ---- test 2: founding (bot-creature.test.ts:93-120, real-input hardening) --------

## Cheats via the documented debug_* mutators, one REAL F-hold charm, then
## founds through a REAL tribe-button click. One tick per scene frame.
## Returns "OK" / "" (in progress) / the failure reason.
func founding_tick(game: Variant) -> String:
	var sim: Variant = game.current.sim
	match _fnd:
		"grant":
			# the TS cheats (bot-creature.test.ts:97-98) ride the ONE
			# documented sim mutator (bot law's exception list — see
			# debug_grant's header)
			sim.debug_grant(999.0, 3)
			if int(game.context.genome["brain"]) < 3 or float(game.context.dna) < 999.0:
				return "founding: the debug grant did not land (brain %s dna %s)" % [
						str(game.context.genome["brain"]), str(game.context.dna)]
			sim.debug_spawn_pack(2)  # the TS debugSpawnPack(2) cheat, same family
			step(game, 3)
			if not bool(sim.tribeReady):
				return "founding: tribeReady false after brain ×3 + 2-pack (brain %s pack %d)" % [
						str(game.context.genome["brain"]), pack_count(sim)]
			_fnd = "charm"
		"charm":
			# the real-input charm beat: befriend ONE more member through a
			# genuine F-hold + beat bar (the debug pack is already befriended
			# — TS-true). Synchronous: it reads sim fields only.
			var err := charm_one_wild(game)
			if not err.is_empty():
				return err
			if pack_count(sim) < 3:
				return "founding: the charm did not grow the pack (%d)" % pack_count(sim)
			game._do_render(0.0)  # queue the tribe-button draw for the next tick
			_fnd = "tribe_rect"
		"tribe_rect":
			# a death mid-charm scatters the pack — re-arm before the click
			# (the cheat is repeatable; the founding itself stays real-input)
			if not bool(sim.tribeReady):
				_fnd_tries += 1
				if _fnd_tries > 3:
					return "founding: tribeReady never armed for the click"
				sim.debug_spawn_pack(2)
				step(game, 3)
				game._do_render(0.0)
				return ""
			var r: Dictionary = sim.tribeRect
			if float(r["x"]) >= 100.0:
				_fnd = "tribe_click"
			else:
				_fnd_tries += 1
				if _fnd_tries > RECT_TICKS:
					return "founding: the tribe button never drew (rect %s)" % str(r)
				game._do_render(0.0)
		"tribe_click":
			# the REAL tribe button click (bot law — the TS bot called
			# foundTribe() directly)
			if float(sim.php) <= 0.0:
				return "founding: the dead cannot found (php %s)" % str(sim.php)
			var r2: Dictionary = sim.tribeRect
			var center := Vector2(float(r2["x"]) + float(r2["w"]) / 2.0,
					float(r2["y"]) + float(r2["h"]) / 2.0)
			driver.mouse_down(center)
			step(game, 1)
			driver.mouse_up()
			if game.transition == null:
				return "founding: the tribe click did not start the transition"
			if String(game.transition["next"]) != "tribe" \
					or String(game.transition["title"]) != "THE FIRST FIRE":
				return "founding: wrong transition (%s)" % str(game.transition)
			_arr_steps = 0
			_fnd = "landing"
		"landing":
			# the tribe stage is M4 — with no registered 'tribe' stage the
			# switch no-ops (game.ts:251 shape) and the card + fade complete
			# on the creature stage: that IS the placeholder landing (the
			# task-4 report ruling)
			step(game, 1)
			_arr_steps += 1
			if game.transition == null:
				if String(game.context.stage) != "creature":
					return "founding: landed off the tribe placeholder (%s)" % game.context.stage
				# the pack snapshot rode the founding (flags.packGenomes ≥ 1)
				var raw: Variant = game.context.flags.get("packGenomes", "")
				var pack: Variant = JSON.parse_string(String(raw)) if String(raw) != "" else null
				if not (pack is Array) or (pack as Array).is_empty():
					return "founding: packGenomes snapshot missing/empty (%s)" % str(raw)
				_fnd = "done"
				return "OK"
			if _arr_steps >= TRANSITION_POLL:
				return "founding: the transition never completed (%d steps)" % _arr_steps
	return ""


## The charm beat: approach the nearest charmable wild ent with REAL held-mouse
## movement, then hold F (real key) and play the beat bar with real Space taps
## — the full try_charm/update_charm minigame through the pipeline.
func charm_one_wild(game: Variant) -> String:
	var sim: Variant = game.current.sim
	var pack0 := pack_count(sim)
	var target_id := -1
	var holding_f := false
	var frames := 0
	while frames < CHARM_MAX:
		frames += 1
		# death: drop everything, wait out the 1.8s fade + respawn
		if float(sim.php) <= 0.0:
			if holding_f:
				driver.release_key(KEY_F)
				holding_f = false
			if game.input.is_down():
				driver.mouse_up()
			step(game, 1)
			continue
		var t: Variant = _ent_by_eid(sim, target_id)
		var d := INF if t == null else _dist_to(sim, t)
		var charm_live: bool = sim.charmActive and sim.charmTarget != null
		if charm_live:
			# the beat bar: tap Space when the marker swings into the glow
			# (zone 0.35 − hits·0.05; the sim's mustExit re-arm makes in-zone
			# spam a no-op, so a plain in-zone gate rides the re-entry passes)
			var zone: float = 0.35 - float(sim.charmHits) * 0.05
			if absf(float(sim.charmMarker)) < zone:
				driver.tap_key(KEY_SPACE)
			step(game, 1)
			if pack_count(sim) > pack0:
				if holding_f:
					driver.release_key(KEY_F)
					holding_f = false
				return ""
			continue
		if holding_f:
			driver.release_key(KEY_F)
			holding_f = false
		# (re)pick a target — the same eligibility try_charm uses
		if t == null or bool(t["pack"]) or d > 900.0:
			t = nearest_charmable(sim)
			target_id = int(t["eid"]) if t != null else -1
			if t == null:
				step(game, 1)  # barren stretch — wait for the population valve
				continue
			d = _dist_to(sim, t)
		if d > 110.0:
			# walk toward it: held mouse aimed at the ent (world→screen via
			# the live cam state; one update stale like a real mouse)
			var aim: Vector2 = driver.world_to_screen(game,
					float(t["x"]), float(t["z"]) * Z_TO_Y)
			if game.input.is_down():
				driver.move_mouse(aim)
			else:
				driver.mouse_down(aim)
			if not driver.delivery_ok or not game.input.is_down():
				return "charm: the held-mouse walk did not reach the wrapper"
			step(game, 1)
			continue
		# in range: stop, hold F — try_charm fires on the held-state poll
		if game.input.is_down():
			driver.mouse_up()
		driver.press_key(KEY_F)
		if not game.input.key("KeyF"):
			return "charm: the F press did not reach the Input singleton (held-state poll)"
		holding_f = true
		step(game, 1)
	if holding_f:
		driver.release_key(KEY_F)
	if game.input.is_down():
		driver.mouse_up()
	return "charm: no befriended member within %d frames (pack %d → %d)" % [
			CHARM_MAX, pack0, pack_count(sim)]
