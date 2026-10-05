## QC r1 B5 measurement scene — creature hunt-loop death-spiral probe (KITER).
## READ-ONLY over the sim: no valving, no fixes — this scene only MEASURES.
##
## Question (B5, Major): after B1 (bind editor stats) landed, does the hunt
## loop still spiral? The game's own target valve lives in creature_sim.gd
## ~:1022: "full-vision aggro on a hatchling was a death spiral: 21 deaths/
## 8.9 min measured" — so the target is ~21 deaths per 8.9 min on a profile
## that is NOT hyper-aggressive. The old QC number (38 deaths / 7 kills /
## net +11 DNA / 5 min) came from a hyper-aggressive bot, 1 seed, pre-B1.
##
## PROFILE (the middle player): hunt → bite on contact (the sim's contact
## auto-bite) → RETREAT when hp < ~50% with danger near (real held-mouse
## run-away) → turn and FIGHT when cornered (hp < 35%: every wild archetype
## outruns a legs-1 player, a doomed retreat just dies tired) → farm the
## nearest bush when no safe prey / to heal (real held-mouse eat) → buy a JAW
## level every ~40 s when DNA affords it (the B1 kill lane: jaw now really
## raises damage, which flips `playerThreat` and shrinks the aggro set).
## Safe prey = the live DPS trade (my bite-rate vs their counter-bite), so
## the carnivore lane opens as jaw levels land — that opening IS the signal.
##
## INPUT LAW (Global Constraint 8): every gameplay input rides
## Input.parse_input_event + flush through the REAL pipeline (bot_driver.gd).
## Two documented exceptions, both measurement-only:
##   - stage transition: game.go_to("creature", …) — the same call the real
##     shore handler makes (cell_sim "shore_travel"); the B4-probe precedent.
##     The cell messy-play burst before it is fully real.
##   - editor buys: editor_inst.click_part(row, "+") — the documented
##     programmatic path (editor.gd hit-tests route to exactly this method);
##     it goes through spend_dna + refresh_stats + the B1 on_stats_changed
##     binding, so the sim effect is identical to a real "+" click without
##     needing a llvmpipe draw pass headless.
## Editor open/close still rides the REAL KeyE pipeline both ways.
##
## Run (headless — needs xvfb on diskless servers: the input pipeline wants a
## display server; no per-frame rendering happens):
##   xvfb-run -a godot --rendering-driver opengl3 --path . \
##       res://tests/scenes/test_b5_kiter.tscn -- 0xBEEF 0xC0FFEE 0x5EED5EED
## TWO ARMS per seed: arm=kit buys jaw every ~40 s (the B1 kill lane),
## arm=nokit never buys — the deaths delta between arms isolates what the B1
## binding contributes to the valve. Prints B5_* lines; per-run summary on
## B5_SEED_RESULT. Exit 0 when the runs complete (measurement scene —
## findings, not asserts).
extends Node

const MainScene := preload("res://main.tscn")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")
const PartsScript := preload("res://src/evo/parts.gd")

const Z_TO_Y := 0.62        # creature sim's z→screen-y (creature_sim.gd)
const DT := 1.0 / 60.0
const CARD_STEPS := 180     # the M2 prologue card slot (bot.test.ts:72)
const SETTLE := 300         # post-landing settle (B4 probe used 300)
const BURST_FRAMES := 240   # the cell messy-play burst (bot_creature)
const RUN_SEC := 540.0      # 9.0 min > the 8.9-min (534 s) valve window
const VALVE_SEC := 534.0    # the comment's measured window
const STEP_BUDGET := 42000  # hard failsafe (~11.7 min of sim time)

# kiter tuning (the profile, not a valve)
const RETREAT_HP := 0.5     # rút khi hp < ~50%
const CORNERED_HP := 0.35   # quá thấp để rút (kẻ săn nhanh hơn) → đánh lại
const ANGRY_RADIUS := 380.0 # a committed hunter (mood angry) within ~aggro radius
const CLOSE_RADIUS := 150.0 # about to be bitten
const PREY_RANGE := 900.0
const BUSH_RANGE := 800.0
const JAW_EVERY := 40.0     # seconds between jaw-buy attempts
const JAW_RESERVE := 15     # keep this much DNA in the wallet

const DEFAULT_SEEDS := [0xBEEF, 0xC0FFEE, 0x5EED5EED]
const DEFAULT_LCGS := [777, 4242, 90909]

var driver: Variant = null
var game: Variant = null
var _pending_seed := 0

# wander state (module-level: survives across prey-less stretches)
var _wander_t := 0.0
var _wander_x := 0.0
var _wander_z := 0.0


func _ready() -> void:
	var seeds: Array = DEFAULT_SEEDS.duplicate()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		seeds = []
		for a in args:
			seeds.append(_parse_seed(a))
	print("B5_BEGIN seeds=%s" % str(seeds))
	for i in range(seeds.size()):
		# two arms per seed: "kit" buys jaw (the B1 kill lane), "nokit" never
		# buys — the delta isolates what the B1 binding contributes
		var res := run_seed(int(seeds[i]), DEFAULT_LCGS[i % DEFAULT_LCGS.size()], true)
		print("B5_SEED_RESULT arm=kit " + _flat(res))
		var res2 := run_seed(int(seeds[i]), DEFAULT_LCGS[i % DEFAULT_LCGS.size()], false)
		print("B5_SEED_RESULT arm=nokit " + _flat(res2))
	get_tree().quit(0)


func _parse_seed(a: String) -> int:
	var s := a.strip_edges().to_lower()
	if s.begins_with("0x"):
		return s.hex_to_int()
	return s.to_int()


# ---- one seed -------------------------------------------------------------------

func run_seed(world_seed: int, lcg_seed: int, allow_buy: bool) -> Dictionary:
	driver = BotDriverScript.new()
	driver.lcg_seed = lcg_seed
	_pending_seed = world_seed
	game = _build_game()
	var out := {"seed": world_seed, "lcg": lcg_seed}
	var err := _arrival(world_seed)
	if err != "":
		out["error"] = err
		game.queue_free()
		return out

	var sim: Variant = game.stages["creature"].sim
	var ctx: Variant = game.context
	out["arrival_dna"] = int(ctx.dna)
	out["player"] = "jaw%d legs%d size%.1f dmg%.0f hp%.0f spd%.0f" % [
		int(ctx.genome.get("jaw", 0)), int(ctx.genome.get("legs", 0)),
		float(ctx.genome.get("size", 1)), float(sim.pStats["damage"]),
		float(sim.pmaxHp), float(sim.pStats["speed"])]

	# ---- t0 ledger
	var t0: float = float(sim.time)
	var dna0 := float(ctx.dna)
	var deaths0: int = int(game.deaths_in_stage)
	var wpk0 := _wp_kills(ctx)
	var run := {
		"deaths": 0, "death_t": [], "death_lost": [], "death_by": [],
		"kills": 0, "kill_t": [],
		"respawn_clear": [], "respawn_threat10": [],
		"modes": {"hunt": 0, "farm": 0, "retreat": 0, "wander": 0, "dead": 0},
		"dna_min": {}, "jaw_buys": 0, "jaw_end": int(ctx.genome.get("jaw", 0)),
	}
	out["arm"] = "kit" if allow_buy else "nokit"
	var prev_alive := true
	var prev_dna := dna0
	var mode := "wander"
	var prey_id := -1
	var contact_before := false
	var last_min := -1
	var jaw_attempts := 0
	var respawn_sample_until := -1.0
	var respawn_min := INF
	var step := 0

	while float(sim.time) - t0 < RUN_SEC and step < STEP_BUDGET:
		step += 1
		var alive: bool = float(sim.php) > 0.0 and float(sim.deathFade) <= 0.0
		if not alive:
			# dead: drop the mouse, wait out the 1.8 s fade through the sim
			if game.input.is_down():
				driver.mouse_up()
			run["modes"]["dead"] = int(run["modes"]["dead"]) + 1
			game.step_for_testing(1, DT)
			if float(sim.php) > 0.0 and float(sim.deathFade) <= 0.0:
				# respawned this step (px reset to -1600, ents within 600 cleared):
				# record the instant clearance, then sample the 3-s invuln window
				# WHILE RESUMING normal policy (no stand-still — the first run's
				# 10-s passive window was a death factory that poisoned the data)
				_record_respawn_instant(run, sim)
				respawn_sample_until = float(sim.time) + 3.0
				respawn_min = INF
				prev_alive = true
			continue

		# jaw buy cadence (alive only; the editor refuses the dead anyway)
		if allow_buy and float(sim.time) - t0 >= float(jaw_attempts) * JAW_EVERY \
				and int(ctx.genome.get("jaw", 0)) < 5:
			jaw_attempts += 1
			_buy_jaw(run)
			run["jaw_end"] = int(ctx.genome.get("jaw", 0))
			if float(sim.php) <= 0.0 or float(sim.deathFade) > 0.0:
				# died inside the buy's one unblocked open-step
				_count_death(run, sim, t0, prev_dna)
				prev_alive = false
				continue

		# ---- perceive
		var angry: Variant = _nearest_angry(sim)
		var close: Variant = _nearest_close(sim)
		var prey: Variant = _pick_prey(sim)
		var bush: Variant = _nearest_bush(sim)

		# ---- decide + drive (the middle-player loop)
		var t_alive: float = float(sim.time) - t0
		if float(sim.php) < float(sim.pmaxHp) * CORNERED_HP and close != null:
			# cornered: a faster hunter will run us down — turn and fight
			mode = _hunt(sim, close)
			prey_id = int(close["eid"])
			contact_before = _in_contact(sim, close)
		elif float(sim.php) < float(sim.pmaxHp) * RETREAT_HP \
				and (angry != null or close != null):
			# RÚT: hp < ~50% with danger near
			mode = _retreat_from(sim, angry if angry != null else close)
		elif angry != null and _their_dps(sim, angry) > _my_dps(sim, angry) \
				and float(sim.php) < float(sim.pmaxHp) * 0.8:
			# a committed predator that out-trades us while we are mid-hp
			mode = _retreat_from(sim, angry)
		elif bush != null and angry == null \
				and float(sim.php) < float(sim.pmaxHp) * 0.88:
			# heal-up leg: top off at a berry bush before the next hunt
			# (no passive regen exists — the kiter cycle NEEDS this leg)
			mode = _farm_bush(sim, bush)
		elif prey != null:
			mode = _hunt(sim, prey)
			prey_id = int(prey["eid"])
			contact_before = _in_contact(sim, prey)
		elif bush != null and float(sim.php) < float(sim.pmaxHp) * 0.98:
			mode = _farm_bush(sim, bush)
		else:
			mode = _wander(sim)
		run["modes"][mode] = int(run["modes"][mode]) + 1

		# ---- step the REAL sim
		game.step_for_testing(1, DT)

		# ---- post reads
		if float(sim.php) <= 0.0 or float(sim.deathFade) > 0.0:
			# died THIS step (the tax fired in the same step — handle_death's
			# first frame); the dead branch above just waits the fade now
			_count_death(run, sim, t0, prev_dna)
			prev_alive = false
			continue
		# my-kill detection (the bite that killed MY target)
		if mode == "hunt" and contact_before:
			var t: Variant = _ent_by_id(sim, prey_id)
			if t != null and (t.has("corpseT") or float(t["hp"]) <= 0.0):
				run["kills"] += 1
				run["kill_t"].append(snake_t(t_alive))
				prey_id = -1
		# respawn-to-threat under play (the 3-s invuln window, bot active)
		if respawn_sample_until > 0.0:
			if float(sim.time) >= respawn_sample_until:
				run["respawn_threat10"].append(
						-1.0 if respawn_min == INF else snappedf(respawn_min, 1.0))
				respawn_sample_until = -1.0
			else:
				var rt: Variant = _nearest_wild(sim)
				if rt != null:
					respawn_min = minf(respawn_min, _dist(sim, rt))
		# a death that starts and ends between two bot frames is impossible
		# (the fade alone is 1.8 s) — no missed transitions
		prev_alive = float(sim.php) > 0.0 and float(sim.deathFade) <= 0.0
		prev_dna = float(ctx.dna)
		var minute := int(t_alive / 60.0)
		if minute != last_min and minute <= 9:
			run["dna_min"][str(minute)] = int(ctx.dna)
			last_min = minute

	# ---- t1 ledger
	var t1: float = float(sim.time) - t0
	out["ran_sec"] = snappedf(t1, 0.01)
	out["steps"] = step
	out["deaths"] = run["deaths"]
	out["deaths_534"] = _count_le(run["death_t"], VALVE_SEC)
	out["deaths_in_stage_delta"] = int(game.deaths_in_stage) - deaths0
	out["kills"] = run["kills"]
	out["kills_by_min"] = _histogram(run["kill_t"], 60.0, 9)
	out["dna_start"] = int(dna0)
	out["dna_end"] = int(ctx.dna)
	out["dna_delta"] = int(ctx.dna) - int(dna0)
	out["dna_min"] = run["dna_min"]
	out["jaw_buys"] = run["jaw_buys"]
	out["jaw_end"] = run["jaw_end"]
	out["wp_kills_delta"] = _wp_kills(ctx) - wpk0
	var total := 0
	for m in run["modes"]:
		total += int(run["modes"][m])
	var shares := {}
	for m in run["modes"]:
		shares[m] = int(round(100.0 * float(run["modes"][m]) / maxf(1.0, float(total))))
	out["mode_share_pct"] = shares
	out["respawn_clear"] = run["respawn_clear"]
	out["respawn_threat10"] = run["respawn_threat10"]
	out["death_t"] = run["death_t"]
	out["death_lost"] = run["death_lost"]
	out["death_by"] = run["death_by"]
	var ev := ""
	if not driver.sane_violations.is_empty():
		ev = "sane: " + str(driver.sane_violations)
	if not driver.delivery_ok:
		ev += " delivery FAILED"
	out["input_law"] = ev if ev != "" else "ok"
	game.queue_free()
	return out


# ---- arrival (menu → real cell burst → legs via editor path → creature) ---------

func _arrival(world_seed: int) -> String:
	game.step_for_testing(5, DT)
	if String(game.context.stage) != "menu":
		return "arrival: expected menu, got %s" % game.context.stage
	game.current.start_new_game(0, "normal", world_seed)
	var waited := 0
	while String(game.context.stage) != "cell":
		game.step_for_testing(1, DT)
		waited += 1
		if waited > 600:
			return "arrival: cell not reached"
	game.step_for_testing(CARD_STEPS, DT)
	driver.step_loop(game, BURST_FRAMES, DT)
	if not driver.delivery_ok:
		return "arrival: burst input failed to reach the wrapper"
	if not driver.sane_violations.is_empty():
		return "arrival: sane violations in burst: %s" % str(driver.sane_violations)
	# legs via the documented editor buy path (real KeyE open/close around it)
	driver.tap_key(KEY_E)
	game.step_for_testing(1, DT)
	if not bool(game.editor["open"]):
		return "arrival: KeyE did not open the editor"
	var ctx: Variant = game.context
	var before := int(ctx.genome.get("legs", 0))
	game.current.editor_inst.click_part({"def": _part_def("legs")}, "+")
	game.step_for_testing(1, DT)
	if int(ctx.genome.get("legs", 0)) != before + 1:
		return "arrival: legs buy did not land (dna %d)" % int(ctx.dna)
	driver.tap_key(KEY_E)
	game.step_for_testing(1, DT)
	if bool(game.editor["open"]):
		return "arrival: KeyE did not close the editor"
	# the real shore handler's transition call (B4-probe precedent)
	game.go_to("creature", {"title": "THE LONG WALK", "sub": "B5 kiter"})
	waited = 0
	while game.transition != null or String(game.context.stage) != "creature":
		game.step_for_testing(1, DT)
		waited += 1
		if waited > 900:
			return "arrival: creature stage not reached (%s)" % game.context.stage
	game.step_for_testing(SETTLE, DT)
	if game.stages["creature"].sim == null:
		return "arrival: creature sim missing"
	return ""


func _build_game() -> Variant:
	# B4-probe construction: a real Game with the real stage set, loop manual.
	var ctx: Variant = load("res://src/game/context.gd").new(_pending_seed)
	var gg: Variant = load("res://src/game/game.gd").new(ctx)
	add_child(gg)
	gg.set_process(false)
	gg.loop.is_active_cb = func() -> bool: return false
	gg.register(load("res://src/game/menu.gd").new(gg))
	gg.register(load("res://src/game/cell/cell_stage.gd").new(gg))
	gg.register(load("res://src/game/creature/creature_stage.gd").new(gg))
	gg.register(load("res://src/game/tribe/tribe_stage.gd").new(gg))
	gg.start()
	return gg


# ---- drive helpers (all real pipeline: held mouse = move/attack/eat) -------------

func _walk_to(sim: Variant, wxx: float, wzz: float) -> void:
	var aim: Vector2 = driver.world_to_screen(game, wxx, wzz * Z_TO_Y)
	if game.input.is_down():
		driver.move_mouse(aim)
	else:
		driver.mouse_down(aim)


func _retreat_from(sim: Variant, threat: Variant) -> String:
	var dx: float = float(sim.px) - float(threat["x"])
	var dz: float = float(sim.pz) - float(threat["z"])
	var d: float = maxf(1.0, sqrt(dx * dx + dz * dz))
	_walk_to(sim, float(sim.px) + dx / d * 420.0, float(sim.pz) + dz / d * 420.0)
	return "retreat"


func _flee_any(sim: Variant) -> String:
	var nearest: Variant = _nearest_wild(sim)
	if nearest == null:
		return _wander(sim)
	return _retreat_from(sim, nearest)


func _hunt(sim: Variant, prey: Variant) -> String:
	_walk_to(sim, float(prey["x"]), float(prey["z"]))
	return "hunt"


func _farm_bush(sim: Variant, bush: Variant) -> String:
	_walk_to(sim, float(bush["x"]), float(bush["z"]))
	return "farm"


func _wander(sim: Variant) -> String:
	_wander_t -= DT
	if _wander_t <= 0.0:
		_wander_t = 3.0
		_wander_x = clampf(float(sim.px) + (driver.rand() - 0.5) * 1200.0, -2600.0, 2600.0)
		_wander_z = clampf(float(sim.pz) + (driver.rand() - 0.5) * 700.0, -180.0, 220.0)
	_walk_to(sim, _wander_x, _wander_z)
	return "wander"


func _buy_jaw(run: Dictionary) -> void:
	var ctx: Variant = game.context
	var def := _part_def("jaw")
	var lv := int(ctx.genome.get("jaw", 0))
	var cost := int(round(float(def["base_cost"]) * pow(float(def["cost_mult"]), lv)))
	if float(ctx.dna) < float(cost) + float(JAW_RESERVE):
		return  # too poor this window — retry at the next 40-s mark
	if game.input.is_down():
		driver.mouse_up()
	driver.tap_key(KEY_E)
	game.step_for_testing(1, DT)
	if not bool(game.editor["open"]):
		return  # the dead cannot edit (shouldn't happen — caller checks alive)
	var editor_inst: Variant = game.current.editor_inst
	editor_inst.click_part({"def": def}, "+")
	if int(ctx.genome.get("jaw", 0)) == lv + 1:
		run["jaw_buys"] = int(run["jaw_buys"]) + 1
	driver.tap_key(KEY_E)
	game.step_for_testing(1, DT)
	var guard := 0
	while bool(game.editor["open"]) and guard < 30:
		game.step_for_testing(1, DT)
		guard += 1


# ---- perception -------------------------------------------------------------------

func _dist(sim: Variant, e: Variant) -> float:
	var dx: float = float(e["x"]) - float(sim.px)
	var dz: float = float(e["z"]) - float(sim.pz)
	return sqrt(dx * dx + dz * dz)


func _in_contact(sim: Variant, e: Variant) -> bool:
	# the sim's bite radius: pR + 14*entSize (creature_sim.update_player)
	var pr: float = 16.0 * float(game.context.genome.get("size", 1))
	return _dist(sim, e) < pr + 14.0 * float(e["genome"]["size"]) + 4.0


func _nearest_wild(sim: Variant) -> Variant:
	# nearest wild, damage-capable ent at ANY distance (respawn clearance read)
	var best: Variant = null
	var bd := INF
	for e in sim.ents:
		if bool(e["pack"]) or e.has("corpseT") or bool(e["baby"]):
			continue
		if float(e["stats"]["damage"]) <= 0.0:
			continue
		var d: float = _dist(sim, e)
		if d < bd:
			bd = d
			best = e
	return best


func _nearest_angry(sim: Variant) -> Variant:
	# a COMMITTED hunter: the sim's hunt branch sets mood "angry"
	var best: Variant = null
	var bd := ANGRY_RADIUS
	for e in sim.ents:
		if bool(e["pack"]) or e.has("corpseT") or bool(e["baby"]):
			continue
		if float(e["stats"]["damage"]) <= 0.0:
			continue
		if String(e["mood"]) != "angry":
			continue
		var d: float = _dist(sim, e)
		if d < bd:
			bd = d
			best = e
	return best


func _nearest_close(sim: Variant) -> Variant:
	# about to be bitten (the sim's bite radius is pR + 14*entSize)
	var best: Variant = null
	var bd := CLOSE_RADIUS
	for e in sim.ents:
		if bool(e["pack"]) or e.has("corpseT") or bool(e["baby"]):
			continue
		if float(e["stats"]["damage"]) <= 0.0:
			continue
		var d: float = _dist(sim, e)
		if d < bd:
			bd = d
			best = e
	return best


func _my_dps(sim: Variant, e: Variant) -> float:
	# player bite per 0.6 s into this ent's defense (creature_sim bite math)
	var def: float = minf(0.6, float(e["stats"]["defense"]))
	return float(sim.pStats["damage"]) * (1.0 - def) / 0.6


func _their_dps(sim: Variant, e: Variant) -> float:
	# their counter-bite per 0.9 s into the player's defense
	var pdef: float = minf(0.65, float(sim.pStats["defense"]))
	return float(e["stats"]["damage"]) * 0.85 * (1.0 - pdef) / 0.9


func _pick_prey(sim: Variant) -> Variant:
	# safe prey by the DPS trade: we win the bite exchange, or the meal dies
	# in <=4 of our bites; herbivores preferred on ties. The carnivore lane
	# OPENS as jaw buys land (post-B1 damage is real) — that is the question
	# under measurement, so the rule must read live pStats, not a fixed list.
	var best: Variant = null
	var best_rank := -INF
	for e in sim.ents:
		if bool(e["pack"]) or e.has("corpseT") or bool(e["baby"]):
			continue
		var d: float = _dist(sim, e)
		if d >= PREY_RANGE:
			continue
		var quick_kill: bool = float(e["maxHp"]) <= float(sim.pStats["damage"]) * 4.0
		var wins_trade: bool = _my_dps(sim, e) >= _their_dps(sim, e)
		if not quick_kill and not wins_trade:
			continue
		var score := 1.0
		if String(e["genome"]["diet"]) != "carnivore":
			score = 2.0
		var rank := score * 10000.0 - d
		if best == null or rank > best_rank:
			best = e
			best_rank = rank
	return best


func _nearest_bush(sim: Variant) -> Variant:
	var best: Variant = null
	var bd := BUSH_RANGE
	for b in sim.bushes:
		if float(b["food"]) <= 0.0:
			continue
		var dx: float = float(b["x"]) - float(sim.px)
		var dz: float = float(b["z"]) - float(sim.pz)
		var d: float = sqrt(dx * dx + dz * dz)
		if d < bd:
			bd = d
			best = b
	return best


func _ent_by_id(sim: Variant, eid: int) -> Variant:
	if eid < 0:
		return null
	for e in sim.ents:
		if int(e["eid"]) == eid:
			return e
	return null


func _part_def(id: String) -> Dictionary:
	for p in PartsScript.PARTS:
		if String(p["id"]) == id:
			return p
	return {}


func _count_death(run: Dictionary, sim: Variant, t0: float, prev_dna: float) -> void:
	# the tax fires in handle_death's first frame — the SAME step the hp
	# crosses 0, so prev_dna → dna IS the 12% loss (plus any same-step income)
	run["deaths"] = int(run["deaths"]) + 1
	run["death_t"].append(snake_t(float(sim.time) - t0))
	run["death_lost"].append(int(prev_dna) - int(sim_ctx_dna()))
	run["death_by"].append(_death_cause(sim))


func sim_ctx_dna() -> float:
	return float(game.context.dna)


func _record_respawn_instant(run: Dictionary, sim: Variant) -> void:
	# the respawn clears ents within 600 (creature_sim.handle_death) — the
	# instant read verifies that clearance held; the under-play 3-s invuln
	# exposure is sampled back in the main loop while the bot keeps playing
	var instant := INF
	for e in sim.ents:
		if bool(e["pack"]) or e.has("corpseT") or bool(e["baby"]):
			continue
		if float(e["stats"]["damage"]) <= 0.0:
			continue
		var d: float = _dist(sim, e)
		if d < instant:
			instant = d
	run["respawn_clear"].append(-1.0 if instant == INF else snappedf(instant, 1.0))


func _death_cause(sim: Variant) -> String:
	# one-line diagnosis: who was on us when we died (nearest wild dmg-ent)
	var e: Variant = _nearest_wild(sim)
	if e == null:
		return "none"
	return "%s/%s/d%.0f" % [String(e["speciesId"]).substr(0, 8),
			String(e["mood"]), float(e["stats"]["damage"])]


# ---- small utils ------------------------------------------------------------------

func snake_t(t: float) -> float:
	return snappedf(t, 0.1)


func _count_le(arr: Array, cap: float) -> int:
	var n := 0
	for v in arr:
		if float(v) <= cap:
			n += 1
	return n


func _histogram(arr: Array, width: float, buckets: int) -> Array:
	var out: Array = []
	for i in range(buckets):
		out.append(0)
	for v in arr:
		var idx := int(float(v) / width)
		if idx >= 0 and idx < buckets:
			out[idx] = int(out[idx]) + 1
	return out


func _wp_kills(ctx: Variant) -> int:
	return int(ctx.world_stats.get("kills", 0))


func _flat(d: Dictionary) -> String:
	var parts: Array = []
	for k in d.keys():
		var v: Variant = d[k]
		if v is Dictionary:
			var inner: Array = []
			for k2 in (v as Dictionary).keys():
				inner.append("%s=%s" % [str(k2), str((v as Dictionary)[k2])])
			parts.append("%s={%s}" % [str(k), ",".join(inner)])
		elif v is Array:
			var items: Array = []
			for x in (v as Array):
				items.append(str(x))
			parts.append("%s=[%s]" % [str(k), ",".join(items)])
		else:
			parts.append("%s=%s" % [str(k), str(v)])
	return " ".join(parts)
