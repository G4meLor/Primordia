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
## auto-bite) → RETREAT when hp < ~50% (real held-mouse run-away) → farm the
## nearest bush when no safe prey / to heal (real held-mouse eat) → buy a JAW
## level every ~40 s when DNA affords it (the B1 kill lane: jaw now really
## raises damage, which flips `playerThreat` and shrinks the aggro set).
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
## Run (headless):
##   godot --headless --path . res://tests/scenes/test_b5_kiter.tscn -- \
##       0xBEEF 0xC0FFEE 0x5EED5EED
## Prints B5_* lines; per-seed summary on B5_SEED_RESULT. Exit 0 when the
## runs complete (measurement scene — findings, not asserts).
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
const THREAT_RADIUS := 320.0
const PREY_RANGE := 900.0
const BUSH_RANGE := 800.0
const JAW_EVERY := 40.0     # seconds between jaw-buy attempts
const JAW_RESERVE := 25     # keep this much DNA in the wallet

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
		var res := run_seed(int(seeds[i]), DEFAULT_LCGS[i % DEFAULT_LCGS.size()])
		print("B5_SEED_RESULT " + _flat(res))
	get_tree().quit(0)


func _parse_seed(a: String) -> int:
	var s := a.strip_edges().to_lower()
	if s.begins_with("0x"):
		return s.hex_to_int()
	return s.to_int()


# ---- one seed -------------------------------------------------------------------

func run_seed(world_seed: int, lcg_seed: int) -> Dictionary:
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
		"deaths": 0, "death_t": [], "death_lost": [],
		"kills": 0, "kill_t": [],
		"respawn_clear": [], "respawn_threat10": [],
		"modes": {"hunt": 0, "farm": 0, "retreat": 0, "wander": 0, "dead": 0},
		"dna_min": {}, "jaw_buys": 0, "jaw_end": int(ctx.genome.get("jaw", 0)),
	}
	var prev_alive := true
	var prev_dna := dna0
	var mode := "wander"
	var prey_id := -1
	var contact_before := false
	var last_min := -1
	var jaw_attempts := 0
	var step := 0

	while float(sim.time) - t0 < RUN_SEC and step < STEP_BUDGET:
		step += 1
		var alive: bool = float(sim.php) > 0.0 and float(sim.deathFade) <= 0.0
		if not alive:
			# dead: drop the mouse, wait out the 1.8 s fade through the sim
			if prev_alive and game.input.is_down():
				driver.mouse_up()
			if prev_alive:
				run["deaths"] += 1
				run["death_t"].append(snake_t(float(sim.time) - t0))
				run["death_lost"].append(int(prev_dna) - int(ctx.dna))
			run["modes"]["dead"] = int(run["modes"]["dead"]) + 1
			prev_alive = false
			game.step_for_testing(1, DT)
			if float(sim.php) > 0.0 and float(sim.deathFade) <= 0.0:
				# respawned this step (px reset to -1600, ents within 600 cleared)
				_record_respawn(run, sim)
				prev_alive = true
			continue

		# jaw buy cadence (alive only; the editor refuses the dead anyway)
		if float(sim.time) - t0 >= float(jaw_attempts) * JAW_EVERY \
				and int(ctx.genome.get("jaw", 0)) < 5:
			jaw_attempts += 1
			_buy_jaw(run)
			run["jaw_end"] = int(ctx.genome.get("jaw", 0))

		# ---- perceive
		var threat: Variant = _nearest_threat(sim)
		var prey: Variant = _pick_prey(sim) if threat == null else null
		var bush: Variant = _nearest_bush(sim)

		# ---- decide + drive
		var t_alive: float = float(sim.time) - t0
		if float(sim.php) < float(sim.pmaxHp) * RETREAT_HP:
			# RÚT: hp < ~50%
			if threat != null:
				mode = _retreat_from(sim, threat)
			elif bush != null:
				mode = _farm_bush(sim, bush)
			else:
				mode = _flee_any(sim)
		elif threat != null and String(threat["mood"]) == "angry" \
				and float(sim.php) < float(sim.pmaxHp) * 0.75 \
				and float(threat["stats"]["damage"]) >= float(sim.pStats["damage"]) * 0.8:
			# an angry predator that out-bites us while we are mid-HP: disengage
			mode = _retreat_from(sim, threat)
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

		# ---- post reads: my-kill detection (the bite that killed MY target)
		if mode == "hunt" and contact_before:
			var t: Variant = _ent_by_id(sim, prey_id)
			if t != null and (t.has("corpseT") or float(t["hp"]) <= 0.0):
				run["kills"] += 1
				run["kill_t"].append(snake_t(t_alive))
				prey_id = -1
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
	var nearest: Variant = null
	var bd := INF
	for e in sim.ents:
		if bool(e["pack"]) or e.has("corpseT"):
			continue
		var d: float = _dist(sim, e)
		if d < bd:
			bd = d
			nearest = e
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


func _nearest_threat(sim: Variant) -> Variant:
	var best: Variant = null
	var bd := THREAT_RADIUS
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


func _pick_prey(sim: Variant) -> Variant:
	# safe prey: herbivore/omnivore first, then a carnivore we out-damage
	# (post-B1 jaw buys widen this set via the playerThreat flip)
	var best: Variant = null
	var best_rank := -INF
	for e in sim.ents:
		if bool(e["pack"]) or e.has("corpseT") or bool(e["baby"]):
			continue
		var d: float = _dist(sim, e)
		if d >= PREY_RANGE:
			continue
		var diet := String(e["genome"]["diet"])
		var score := 0.0
		if diet != "carnivore":
			score = 2.0
		elif float(e["stats"]["damage"]) < float(sim.pStats["damage"]) * 0.85:
			score = 1.0
		if score <= 0.0:
			continue
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


func _record_respawn(run: Dictionary, sim: Variant) -> void:
	# the respawn clears ents within 600 (creature_sim.handle_death) — the
	# instant read verifies that clearance actually held; the 10-s exposure
	# window is the meaningful "respawn-to-threat" distance.
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
	# sample the next 10 s of sim time for the nearest wild threat
	var deadline: float = float(sim.time) + 10.0
	var best := INF
	while float(sim.time) < deadline:
		game.step_for_testing(1, DT)
		if float(sim.php) <= 0.0:
			break  # died again inside the window — report what we saw
		for e in sim.ents:
			if bool(e["pack"]) or e.has("corpseT") or bool(e["baby"]):
				continue
			if float(e["stats"]["damage"]) <= 0.0:
				continue
			var d: float = _dist(sim, e)
			if d < best:
				best = d
	run["respawn_threat10"].append(-1.0 if best == INF else snappedf(best, 1.0))


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
