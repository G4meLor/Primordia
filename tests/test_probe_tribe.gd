# Task 7 tribe econ probes — the §5.4 econ-parity criterion through the REAL
# tribe stage: each probe boots the full Game + the real TribeStage
# (out-of-tree, the M3 test_probe_creature boot shape) on a pinned seed and
# drives the sim through its documented input-SNAPSHOT contract
# (tribe_sim.update's docstring), with econ observations pinned to the
# TS-verbatim formulas (each probe's provenance comment cites the frozen TS
# line; the probe IS the pin — divergence = documented here + in the report).
#
# Probes (task-7 brief AC + TS TribeStage.ts):
#   wood quota    — under-80 quota → every EVEN-indexed gatherer chops trees
#                   regardless (a bush within 600 is ignored); delivery +8/leg
#                   for both currencies (TribeStage.ts:757-768 quota, :815-843
#                   tribeArrive, :1088-1102 arrivals block)
#   bush regrow   — a stripped bush refills rng 3..7 after 30 s; the clock
#                   only runs while food ≤ 0 (TribeStage.ts:1104-1110); every
#                   pickup arms regrow 30 (:828-830)
#   hut recruit   — recruitT accumulates on built huts; ≥ 45 s AND no
#                   mid-siege raiders AND roster < popCap (built × 3 + 1) pays
#                   a birth; the clock resets even when the birth is gated
#                   (TribeStage.ts:272 popCap + :1144-1157)
#   raid cadence  — fire at ≤ 0 → reset 80 + rng(−15, 25); peaceful +40;
#                   peaceful + hutless floors the timer at 30 and refuses to
#                   fire (TribeStage.ts:327-339); the first-raid hint fires
#                   exactly once per run (:334-337); wave 2 vs 1 (:567-568)
#   war graves    — a raid instance whose war party empties pays +15 DNA once
#                   per instance, only with the world combo
#                   (TribeStage.ts:709-717 + worldGenome comboActive)
#   totem rate    — progress += workers·dt·1.6, clamp 100
#                   (TribeStage.ts:1159-1163)
#   camp assault  — player warriors within 90 drain 4·dt each + anger 0.1·dt
#                   clamp 1; a camp death pays +60 food +40 wood −0.05 karma
#                   and dead camps are skipped (TribeStage.ts:858-879)
#   beast DPS     — 9·fighters (< 60) + 14 chief (< 60); the gore roll is
#                   chief-proximity-gated (A08) and invuln-guarded
#                   (TribeStage.ts:898-911)
#
# Method notes: chaos is silenced per probe (gap 1e9 — the scheduler never
# reaches a fire) so the stream stays clean; probe fixture writes go straight
# at sim fields (the M3 precedent). No statistical windows are needed — every
# pin here is an exact TS-formula identity at the probe's seed or a same-seed
# twin replay (the cadence pair).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const DT := 1.0 / 60.0
const Z_TO_Y := 0.62


# ---- scenario scaffold ---------------------------------------------------------

## Real boot: Game + the REAL tribe stage, out-of-tree (run.gd drives tests
## synchronously inside _initialize — the main loop never reaches a frame, so
## tree-entered nodes never fire _ready; the stage's _ready is invoked ONCE
## manually, the M2/M3 probe shape). switch_stage fires the real on_enter:
## pack conversion founds the minimum-3 gatherer roster (TribeStage.ts:176-189).
## genome_mods merge into ctx.genome BEFORE the stage constructs (founder
## mutate_like + chiefStats are construction-time — test_tribe_sim's shape).
func _boot(seed_v: int, genome_mods: Dictionary = {}) -> Variant:
	var ctx: Variant = ContextScript.new(seed_v)
	if not genome_mods.is_empty():
		ctx.genome.merge(genome_mods, true)
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(TribeStageScript.new(game))
	game.stages["tribe"]._ready()
	game.switch_stage("tribe")
	return game


func _drop(game: Variant) -> void:
	# break the overlay Callable cycles before free (test_game_flow pattern)
	game.hud = {}
	game.editor = {}
	game.pause = {}
	game.free()


## Eventless world for clean econ accounting: the chaos scheduler's natural
## path never spawns inside the window (the deck itself stays the real one —
## the task-3 suite drives it for the cadence pins).
func _silence_chaos(sim: Variant) -> void:
	sim.chaos.gap = 1.0e9


## Idle input snapshot — the sim's documented contract shape (tribe_sim.update
## docstring; test_tribe_sim fixture).
func _inp() -> Dictionary:
	return {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}


func _ticks(sim: Variant, n: int) -> void:
	for i in n:
		sim.update(DT, _inp())


## Park every bush/tree beyond any reach radius (600 pickup / map-wide tree
## targeting) so a fixture resource is the only target in the world.
func _park_resources(sim: Variant) -> void:
	for b in sim.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0
	for t in sim.trees:
		t["x"] = 99999.0
		t["z"] = 99999.0


## A fake raid-warrior dict for the mid-siege gate (rivalWarriors must be
## NON-empty to block births) parked beyond any interaction radius.
func _fake_warrior(sim: Variant) -> Dictionary:
	var g: Dictionary = GenomeScript.clone_genome(sim.ctx.genome)
	g["hue"] = 5.0
	return {
		"x": 9999.0, "z": 0.0, "vx": 0.0, "vz": 0.0,
		"hp": 60.0, "genome": g, "gait": 0.0, "facing": 1, "state": "march",
	}


## First raid observation ride: run ticks until the launch (rivalWarriors
## gains its party), then return the party size. The raid-clock reset value is
## still live in sim.raidTimer at that instant (reset precedes launch, TS:332).
func _await_raid(sim: Variant, budget_s: float) -> int:
	var guard := int(budget_s / DT)
	while guard > 0:
		guard -= 1
		sim.update(DT, _inp())
		if not sim.rivalWarriors.is_empty():
			return sim.rivalWarriors.size()
	return -1


## Count hud toasts whose text carries `fragment` (the REAL stage hook records
## into hud_inst._toasts — the test_bot_tribe read-back precedent).
func _toast_count(game: Variant, fragment: String) -> int:
	var n := 0
	for t in game.current.hud_inst._toasts:
		if String(t["text"]).contains(fragment):
			n += 1
	return n


# ---- probes --------------------------------------------------------------------

## Pin provenance: the wood-quota shift TribeStage.ts:757-768 verbatim —
## underQuota = wood < 80; onWoodShift = underQuota && tribe.indexOf(t) % 2 == 0
## (the port threads the loop index, see the sim's header divergence note);
## bush = onWoodShift ? null : nearestBushWithFood(600); a tree target wins
## iff onWoodShift or no bush. Deliveries: wood +8 / food +8 per leg
## (:821-824 / :816-819 via the arrivals block :1088-1102). Every pickup arms
## the bush regrow 30 (:828-830). Seed 0x7E10.
##
## Method: fixed 15 s windows with per-tick Δ attribution — the stockpiles
## are rebased after each tick's read (wood pinned under/at the quota, food
## pinned under the festival-passive line) so the window never flips the
## branch mid-run, and the delivery identity is conserved EXACTLY regardless
## of leg timing: pickups = deliveries + in-flight carries.
func test_wood_quota_even_gatherers_chop_and_delivery_legs() -> void:
	# legs 6 + wings 2: the default legless genome caps founders at ~19 px/s —
	# the leg-cycle windows need a real walking pace (the quota logic under
	# test is speed-blind)
	var g: Variant = _boot(0x7E10, {"legs": 6, "wings": 2})
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.raidTimer = 1.0e9
	_park_resources(sim)
	# fixture world: ONE tree by the hut, ONE bush 360 px east with plenty of
	# food. Geometry keeps the attribution unambiguous: even gatherers 0/2
	# start in the tree's 30 px pickup ring; the odd gatherer 1 starts in the
	# bush's ring; nobody else can reach a ring mid-leg (pickups fire only at
	# arrival points — hasTarget false).
	var tree: Dictionary = sim.trees[0]
	tree["x"] = 40.0
	tree["z"] = 60.0
	var bush: Dictionary = sim.bushes[0]
	bush["x"] = 400.0
	bush["z"] = 60.0
	bush["food"] = 20.0
	sim.tribe[0]["x"] = 20.0
	sim.tribe[1]["x"] = 380.0
	sim.tribe[2]["x"] = 60.0
	for i in sim.tribe.size():
		sim.tribe[i]["z"] = 60.0
		sim.tribe[i]["vx"] = 0.0
		sim.tribe[i]["vz"] = 0.0
		sim.tribe[i]["carrying"] = null
		sim.tribe[i]["hasTarget"] = false
		sim.tribe[i]["retargetT"] = 0.0
	# Phase A — quota ON (wood pinned 30 < 80): even gatherers chop the tree
	# even though the bush stands within 600; the odd gatherer works the bush.
	var a := _quota_window(sim, tree, bush, 30.0, 900)
	ok(a["tree_picks"] >= 2, "even gatherers chopped (%.0f tree picks)" % float(a["tree_picks"]))
	ok(a["bush_picks"] >= 1, "the odd gatherer worked the bush (%.0f picks)" % float(a["bush_picks"]))
	eq(float(a["wood_legs"]), float(a["tree_picks"]) - float(a["carry_wood"]),
			"wood conserved: +8 per delivered leg (TS:821-824)")
	eq(float(a["food_legs"]), float(a["bush_picks"]) - float(a["carry_food"]),
			"food conserved: +8 per delivered leg (TS:816-819)")
	eq(float(a["pick_stray_even"]), 0.0, "every tree pick had an even gatherer in the ring")
	eq(float(a["pick_stray_odd"]), 0.0, "every bush pick was the odd gatherer's (even never left the tree shift)")
	eq(float(bush["regrow"]), 30.0, "every pickup armed the 30 s regrow (TS:828-830)")
	# Phase B — quota OFF (wood pinned 85 ≥ 80): the even gatherers take the
	# bush too; the tree stops being chopped while the 600-bush has food. The
	# bush moves in to (250, 60) so the round-trip legs fit the window.
	bush["x"] = 250.0
	for i in sim.tribe.size():
		sim.tribe[i]["x"] = 160.0 + float(i) * 20.0
		sim.tribe[i]["z"] = 60.0
		sim.tribe[i]["vx"] = 0.0
		sim.tribe[i]["vz"] = 0.0
		sim.tribe[i]["carrying"] = null
		sim.tribe[i]["hasTarget"] = false
		sim.tribe[i]["retargetT"] = 0.0
	var b := _quota_window(sim, tree, bush, 85.0, 1200)
	eq(float(b["tree_picks"]), 0.0,
			"quota off: NO tree pickups while the 600-bush has food (TS:764/766-767)")
	eq(float(b["wood_legs"]), 0.0, "quota off: zero wood legs (nobody chopped)")
	ok(float(b["bush_picks"]) >= 2.0, "the bush fed the quota-off legs (%.0f)" % float(b["bush_picks"]))
	eq(float(b["food_legs"]), float(b["bush_picks"]) - float(b["carry_food"]),
			"quota-off food legs still conserve at +8")
	_drop(g)


## One attribution window: run `n` ticks with the stockpiles rebased each
## tick (wood to `wood_pin`, food to 30 — under the passive's 80 line),
## classifying per-tick deltas: wood/food deliveries (+8 multiples), tree
## pickups (Δwood-tree −1) attributed to the even-indexed ring, bush pickups
## attributed to the odd gatherer's ring. Returns the counters.
func _quota_window(sim: Variant, tree: Dictionary, bush: Dictionary,
		wood_pin: float, n: int) -> Dictionary:
	var out := {
		"wood_legs": 0.0, "food_legs": 0.0,
		"tree_picks": 0.0, "bush_picks": 0.0,
		"pick_stray_even": 0.0, "pick_stray_odd": 0.0,
		"carry_wood": 0.0, "carry_food": 0.0,
	}
	for i in n:
		var wood_prev: float = float(sim.wood)
		var food_prev: float = float(sim.food)
		var tree_prev: float = float(tree["wood"])
		var bush_prev: float = float(bush["food"])
		sim.update(DT, _inp())
		var d_wood: float = float(sim.wood) - wood_prev
		var d_food: float = float(sim.food) - food_prev
		var d_tree: float = tree_prev - float(tree["wood"])
		var d_bush: float = bush_prev - float(bush["food"])
		if d_wood != 0.0:
			ok(absf(fmod(d_wood, 8.0)) < 0.001,
					"wood moved in clean +8 legs (Δ %.3f)" % d_wood)
			out["wood_legs"] = float(out["wood_legs"]) + d_wood / 8.0
		if d_food != 0.0:
			ok(absf(fmod(d_food, 8.0)) < 0.001,
					"food moved in clean +8 legs (Δ %.3f)" % d_food)
			out["food_legs"] = float(out["food_legs"]) + d_food / 8.0
		if d_tree > 0.0:
			out["tree_picks"] = float(out["tree_picks"]) + d_tree
			# attribution: an even-indexed gatherer stood in the tree's ring
			var even_near := false
			for k in sim.tribe.size():
				if k % 2 == 0 and _dist2(sim.tribe[k], tree) <= 900.0:
					even_near = true
			if not even_near:
				out["pick_stray_even"] = float(out["pick_stray_even"]) + 1.0
		if d_bush > 0.0:
			out["bush_picks"] = float(out["bush_picks"]) + d_bush
			var odd_near := false
			var even_near_bush := false
			for k in sim.tribe.size():
				if _dist2(sim.tribe[k], bush) <= 900.0:
					if k % 2 == 1:
						odd_near = true
					else:
						even_near_bush = true
			if not odd_near or even_near_bush:
				out["pick_stray_odd"] = float(out["pick_stray_odd"]) + 1.0
		# rebase the stockpiles: wood holds the branch, food stays under the
		# festival-passive line (its roll would add non-leg deltas)
		sim.wood = wood_pin
		sim.food = 30.0
	# in-flight carries close the conservation identity at window end
	for t in sim.tribe:
		if t["carrying"] == "wood":
			out["carry_wood"] = float(out["carry_wood"]) + 1.0
		elif t["carrying"] == "food":
			out["carry_food"] = float(out["carry_food"]) + 1.0
	return out


func _dist2(t: Dictionary, resource: Dictionary) -> float:
	var dx: float = float(t["x"]) - float(resource["x"])
	var dz: float = float(t["z"]) - float(resource["z"])
	return dx * dx + dz * dz


## Pin provenance: bush regrow TribeStage.ts:1104-1110 verbatim — while food
## ≤ 0, regrow -= dt and at ≤ 0 the refill is rng.range(3, 7). Seed 0x7E11
## (the refill value is the pinned stream's draw — asserted inside the TS
## band, not to a literal).
func test_bush_regrow_30s_cycle() -> void:
	var g: Variant = _boot(0x7E11)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.raidTimer = 1.0e9
	sim.tribe.clear()  # nobody eats the fixture bush (roster 0 < popCap keeps
	# the recruit gate quiet through the ~43 s the probe runs)
	var bush: Dictionary = sim.bushes[0]
	bush["food"] = 0.0
	bush["regrow"] = 30.0
	_ticks(sim, 1770)  # 29.5 s
	eq(float(bush["food"]), 0.0, "no refill a hair under the 30 s clock (TS:1104-1110)")
	_ticks(sim, 60)  # 30.5 s
	var refilled: float = float(bush["food"])
	ok(refilled >= 3.0 and refilled <= 7.0,
			"the refill landed in the TS rng 3..7 band (%.3f)" % refilled)
	var stable: float = float(bush["food"])
	_ticks(sim, 120)
	eq(float(bush["food"]), stable, "the refill holds (no consumers, regrow done)")
	# a HALF-drained bush keeps the clock stopped: it only runs while food ≤ 0
	bush["food"] = 2.0
	bush["regrow"] = 30.0
	_ticks(sim, 600)  # 10 s
	eq(float(bush["food"]), 2.0, "food > 0: the regrow clock does not run")
	eq(float(bush["regrow"]), 30.0, "the arm is untouched until the bush empties")
	_drop(g)


## Pin provenance: popCap TribeStage.ts:272 (built huts × 3 + 1); the recruit
## gate :1144-1157 verbatim — built huts accumulate recruitT; at ≥ 45 AND no
## mid-siege raiders the clock resets and a birth pays only while
## tribe.length < popCap — and the reset happens even when the birth is gated
## (:1149 before :1150). Seed 0x7E12.
func test_hut_recruit_45s_popcap_and_mid_siege() -> void:
	var g: Variant = _boot(0x7E12)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.raidTimer = 1.0e9
	var toasts0: int = _toast_count(g, "A child was born")
	# (a) the 45 s gate: a fresh built hut pays a birth the moment recruitT
	# crosses 45 (roster 3 < popCap 4). Tick one at a time — on the birth tick
	# the clock reads EXACTLY 0 (the reset precedes the birth, TS:1149-1150;
	# later ticks re-accumulate, so the reading must ride the birth tick).
	sim.huts[0]["recruitT"] = 44.9
	var birth_tick := -1
	for i in 30:
		sim.update(DT, _inp())
		if _toast_count(g, "A child was born") > toasts0:
			birth_tick = i
			break
	eq(_toast_count(g, "A child was born") - toasts0, 1, "one birth toast (TS:1152)")
	eq(float(sim.huts[0]["recruitT"]), 0.0, "the gate reset the clock on the birth tick (TS:1149)")
	ok(birth_tick >= 6 and birth_tick <= 8,
			"the crossing landed at the 45 s line (tick %d)" % birth_tick)
	# (b) mid-siege block: raiders in the field hold the clock past 45 with no
	# birth (TS:1148 — 'no births mid-siege')
	sim.rivalWarriors.append(_fake_warrior(sim))
	sim.huts[0]["recruitT"] = 44.9
	_ticks(sim, 60)  # 1 s — well past 45
	eq(sim.tribe.size(), 4, "mid-siege: no birth")
	ok(float(sim.huts[0]["recruitT"]) >= 45.0,
			"the clock held past 45 without resetting (%.3f)" % float(sim.huts[0]["recruitT"]))
	sim.rivalWarriors.clear()
	# (c) the siege lifts → the very next tick pays the held birth. A second
	# built hut first (popCap 7) so the roster 4 still sits under the cap.
	sim.huts.append({"x": 150.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0,
			"pop": 0.0, "buildT": 0.0})
	eq(sim.pop_cap(), 7, "popCap = built × 3 + 1 (TS:272)")
	sim.update(DT, _inp())
	eq(sim.tribe.size(), 5, "the siege-lift birth fired on the next tick")
	eq(float(sim.huts[0]["recruitT"]), 0.0, "the clock reset after the held gate")
	# (d) popCap gate: two more births fill the village to 7; the next cycle
	# resets the clock but pays nothing (TS:1149-1150 order). The silent reset
	# is witnessed by recruitT DROPPING on the crossing tick.
	for k in 2:
		sim.huts[0]["recruitT"] = 44.9
		_ticks(sim, 12)
	eq(sim.tribe.size(), 7, "births filled the village to popCap 7")
	var toasts7: int = _toast_count(g, "A child was born")
	sim.huts[0]["recruitT"] = 44.9
	var reset_seen := false
	for i in 60:
		var prev_rt: float = float(sim.huts[0]["recruitT"])
		sim.update(DT, _inp())
		if float(sim.huts[0]["recruitT"]) < prev_rt:
			reset_seen = true
			eq(float(sim.huts[0]["recruitT"]), 0.0,
					"the clock reset to exactly 0 on the gated crossing tick")
			break
	eq(reset_seen, true, "the clock reset even though the birth was gated")
	eq(sim.tribe.size(), 7, "popCap gate: the roster holds at 7")
	eq(_toast_count(g, "A child was born") - toasts7, 0, "no birth toast past the cap")
	_drop(g)


## Pin provenance: the raid clock TribeStage.ts:327-339 verbatim — fire at
## raidTimer ≤ 0 (normal difficulty, a hut standing) → reset 80 + rng(−15, 25);
## the first-raid hint once per run (:334-337). Seed 0x7E14 drives TWO boots —
## normal + a peaceful twin at the SAME seed: the pre-launch draw history is
## identical (difficulty draws nothing before the launch), so the reset draws
## coincide and the peaceful reset must be exactly +40 and the wave exactly −1
## (wave 2 vs 1, :567-568) — the formula pins ride the twin identity.
func test_raid_cadence_reset_value_and_first_hint_once() -> void:
	# (a) normal boot: the reset value sits in the TS band; the launch wave is
	# 2 + floor(rng 0..2)
	var g: Variant = _boot(0x7E14)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.raidTimer = 0.5
	var n1: int = _await_raid(sim, 5.0)
	ok(n1 >= 2 and n1 <= 4, "wave 2 + floor(rng 0..2) party (got %d)" % n1)
	var reset1: float = float(sim.raidTimer)
	ok(reset1 >= 65.0 and reset1 <= 105.0,
			"reset = 80 + rng(−15, 25) inside the band (%.3f)" % reset1)
	eq(bool(sim.raidActive), true, "raidActive latched on the launch (TS:583)")
	eq(_toast_count(g, "Raiders rally beyond the ridge"), 1, "the first-raid hint fired")
	# fight the party off (kill the field — the war_graves block closes the
	# raid; the combo is off here so no DNA rides)
	for w in sim.rivalWarriors:
		w["hp"] = 0.0
	sim.update(DT, _inp())
	eq(bool(sim.raidActive), false, "the emptied field closed the raid (TS:709-717)")
	# (b) the SECOND raid: reset value again in-band, the hint NOT repeated
	sim.raidTimer = 0.5
	var n2: int = _await_raid(sim, 5.0)
	var reset2: float = float(sim.raidTimer)
	ok(n2 >= 2 and reset2 >= 65.0 and reset2 <= 105.0,
			"second raid launched, reset in-band (%.3f)" % reset2)
	eq(_toast_count(g, "Raiders rally beyond the ridge"), 1,
			"the first-raid hint fired exactly once across two raids (TS:334)")
	eq(String(sim.ctx.flags.get("firstRaidHint", "")), "seen", "the flag latched 'seen'")
	# (c) the peaceful twin at the SAME seed: reset exactly +40, wave exactly −1
	var g2: Variant = _boot(0x7E14)
	var sim2: Variant = g2.current.sim
	sim2.ctx.difficulty = "peaceful"
	_silence_chaos(sim2)
	sim2.raidTimer = 0.5
	var n1p: int = _await_raid(sim2, 5.0)
	var reset1p: float = float(sim2.raidTimer)
	approx(reset1p, reset1 + 40.0, "peaceful reset = base reset + 40 (TS:333 half cadence)", 1e-6)
	eq(n1p, n1 - 1, "peaceful wave = normal wave − 1 (wave 1 vs 2, TS:567)")
	_drop(g2)
	_drop(g)


## Pin provenance: the peaceful-hutless gate TribeStage.ts:327-339 verbatim —
## `peaceful && huts.length === 0` floors raidTimer at 30 EVERY tick and the
## fire gate `(!peaceful || huts > 0)` refuses to launch; one standing hut
## re-arms the clock and the party spawns at wave 1. Seed 0x7E15.
func test_raid_cadence_peaceful_hutless_floor() -> void:
	var g: Variant = _boot(0x7E15)
	var sim: Variant = g.current.sim
	sim.ctx.difficulty = "peaceful"
	_silence_chaos(sim)
	sim.huts.clear()
	sim.raidTimer = -10.0
	_ticks(sim, 120)  # 2 s of a hutless peaceful camp with an overdue clock
	eq(float(sim.raidTimer), 30.0, "the floor lifted the overdue clock to 30 every tick")
	eq(sim.rivalWarriors.size(), 0, "no raid launched while hutless (TS:331 gate)")
	eq(bool(sim.raidActive), false, "raidActive never latched")
	# one standing hut re-arms the real clock — the launch fires at wave 1
	sim.huts.append({"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0,
			"pop": 0.0, "buildT": 0.0})
	sim.raidTimer = 0.1
	var n: int = _await_raid(sim, 5.0)
	ok(n >= 1 and n <= 2, "the hut re-armed raids: wave-1 party (got %d)" % n)
	eq(bool(sim.raidActive), true, "raidActive latched (TS:583)")
	_drop(g)


## Pin provenance: the war_graves combo TribeStage.ts:709-717 verbatim —
## raidActive && rivalWarriors emptied → raidActive false and, ONLY with
## comboActive(world, 'war_graves'), addDna(15, 'war graves') + the reward
## toast — one payment per raid instance. Seeds 0x7E16 (combo on) / 0x7E17
## (combo-off twin).
func test_war_graves_dna_per_raid_combo_gated() -> void:
	# (a) combo ON
	var g: Variant = _boot(0x7E16)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.ctx.world["comboFired"] = {"war_graves": true}
	var dna_start: float = float(sim.ctx.dna) + float(sim.ctx._dna_frac)
	var paid1: float = _raid_to_graves(g, sim)
	approx(dna_start + paid1, dna_start + 15.0, "raid 1 paid +15 DNA ('war graves')", 1e-9)
	eq(_toast_count(g, "War graves yield DNA."), 1, "one reward toast on the payment")
	# the once-per-instance pin: an already-closed raid cannot pay again
	_ticks(sim, 30)
	approx(float(sim.ctx.dna) + float(sim.ctx._dna_frac), dna_start + 15.0,
			"the closed instance never pays twice", 1e-9)
	# raid 2 pays its own +15 (the hud rate-limits identical toasts within
	# 1.5 s — clear the list so the second payment's toast is witnessed)
	g.current.hud_inst._toasts.clear()
	var dna_mid: float = float(sim.ctx.dna) + float(sim.ctx._dna_frac)
	var paid2: float = _raid_to_graves(g, sim)
	approx(dna_mid + paid2, dna_start + 30.0, "raid 2 paid its own +15 (once per raid instance)", 1e-9)
	eq(_toast_count(g, "War graves yield DNA."), 1, "one reward toast per payment")
	_drop(g)
	# (b) combo OFF twin: the same flow pays nothing
	var g2: Variant = _boot(0x7E17)
	var sim2: Variant = g2.current.sim
	_silence_chaos(sim2)
	var paid: float = _raid_to_graves(g2, sim2)
	approx(paid, 0.0, "combo off: the raid closed with no DNA", 1e-9)
	eq(_toast_count(g2, "War graves yield DNA."), 0, "combo off: no reward toast")
	_drop(g2)


## One raid lifecycle to the war_graves payoff: launch on the real clock,
## keep all but the LAST warrior alive through a tick (the instance stays
## open), then empty the field and return the DNA delta the raid earned.
func _raid_to_graves(game: Variant, sim: Variant) -> float:
	var dna0: float = float(sim.ctx.dna) + float(sim.ctx._dna_frac)
	sim.raidTimer = 0.5
	var n: int = _await_raid(sim, 5.0)
	ok(n >= 1, "the raid launched (party %d)" % n)
	if n < 0:
		return 0.0
	for i in sim.rivalWarriors.size() - 1:
		sim.rivalWarriors[i]["hp"] = 0.0
	sim.update(DT, _inp())
	ok(bool(sim.raidActive), "the instance stays open while a warrior stands")
	# the killed rivals paid their own +8 food on the way out (TS:658-661) —
	# irrelevant here; the LAST death closes the instance
	sim.rivalWarriors[sim.rivalWarriors.size() - 1]["hp"] = 0.0
	sim.update(DT, _inp())
	eq(bool(sim.raidActive), false, "the emptied field closed the raid (TS:711-712)")
	return float(sim.ctx.dna) + float(sim.ctx._dna_frac) - dna0


## Pin provenance: totem progress TribeStage.ts:1159-1163 verbatim — while
## active and < 100, progress = min(100, progress + tribe.length·dt·1.6).
## Seed 0x7E18. The 3-founder roster over exactly 10 s pins the rate at 48.0;
## the workers=0 world pins the freeze.
func test_totem_progress_rate_worker_count() -> void:
	var g: Variant = _boot(0x7E18)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.raidTimer = 1.0e9
	sim.totem["active"] = true
	sim.totem["progress"] = 0.0
	_ticks(sim, 600)  # exactly 10 s
	approx(float(sim.totem["progress"]), 3.0 * 10.0 * 1.6,
			"3 workers × 10 s × 1.6 = 48 progress (TS:1162)", 1e-6)
	# the 100 clamp (rate 3·dt·1.6 = 0.08/tick → 0.5 shortfalls cross at 7)
	sim.totem["progress"] = 99.5
	_ticks(sim, 10)
	eq(float(sim.totem["progress"]), 100.0, "the clamp holds at 100 (TS:1162 min)")
	eq(bool(sim.totem["active"]), true, "the totem stays active at 100")
	# zero workers freeze the rate (the roster is empty but the hut stands —
	# no fall path)
	sim.tribe.clear()
	sim.totem["progress"] = 50.0
	_ticks(sim, 120)
	eq(float(sim.totem["progress"]), 50.0, "workers·dt·1.6: no workers, no progress")
	_drop(g)


## Pin provenance: the camp assault TribeStage.ts:858-879 verbatim — player
## warriors (role warrior) within 90 drain 4·dt EACH and anger rises 0.1·dt
## clamped at 1; a camp death pays banner + +60 food +40 wood + addKarma(−0.05)
## and dead camps are skipped (hp ≤ 0 → continue). Seed 0x7E19. The probe pins
## the warriors onto the camp each tick (hasTarget poke — the patrol AI's
## wander is otherwise free) so the attacker count is exact.
func test_rival_camp_assault_drain_and_rewards() -> void:
	var g: Variant = _boot(0x7E19)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.raidTimer = 1.0e9
	_park_resources(sim)
	sim.trees.clear()  # the parked gatherers get no targets and stand still
	var camp: Dictionary = sim.rivals[0]
	camp["x"] = 80.0
	camp["z"] = 60.0
	camp["hp"] = 100.0
	camp["anger"] = 0.0
	sim.rivals[1]["x"] = 9999.0
	# warrior 0 in range; the other founders parked out as standing gatherers
	sim.tribe[0]["role"] = "warrior"
	sim.tribe[0]["x"] = 60.0
	sim.tribe[0]["z"] = 60.0
	sim.tribe[1]["x"] = 2000.0
	sim.tribe[1]["z"] = 60.0
	sim.tribe[2]["x"] = 2100.0
	sim.tribe[2]["z"] = 60.0
	# (a) the anger clamp: 1 attacker for 12 s → anger exactly 1.0 (0.1·12
	# would read 1.2), hp 100 − 4·12 = 52
	for i in 720:
		_poke_camp(sim, camp)
		sim.update(DT, _inp())
	approx(float(camp["anger"]), 1.0, "anger clamped at 1 (TS:866)", 1e-9)
	approx(float(camp["hp"]), 52.0, "1 attacker: 4·dt drain for 12 s", 1e-6)
	# (b) the second attacker doubles the drain: 2·4·dt = 8/s → hp 52 dies in
	# 6.5 s; the death tick pays the full reward package exactly. Food is
	# pinned at 10 so the festival passive (food > 80 roll) cannot add karma
	# draws into the reward accounting.
	sim.tribe[1]["role"] = "warrior"
	sim.tribe[1]["x"] = 100.0
	sim.tribe[1]["z"] = 60.0
	var karma0: float = float(sim.ctx.karma)
	var dead := false
	var guard := 600
	while guard > 0 and not dead:
		guard -= 1
		sim.food = 10.0
		_poke_camp(sim, camp)
		var f0: float = float(sim.food)
		var w0: float = float(sim.wood)
		var k0: float = float(sim.ctx.karma)
		sim.update(DT, _inp())
		if float(camp["hp"]) <= 0.0:
			dead = true
			approx(float(sim.food) - f0, 60.0, "camp death paid +60 food (TS:873)", 1e-9)
			approx(float(sim.wood) - w0, 40.0, "camp death paid +40 wood (TS:874)", 1e-9)
			approx(float(sim.ctx.karma) - k0, -0.05, "camp death paid karma −0.05 (TS:875)", 1e-9)
	ok(dead, "the camp died to the 2-warrior assault (hp 52 at 8/s)")
	approx(float(sim.ctx.karma) - karma0, -0.05, "the total assault karma is exactly −0.05", 1e-9)
	# (c) the dead camp stops draining: hp/anger frozen, no further rewards
	var hp_end: float = float(camp["hp"])
	var anger_end: float = float(camp["anger"])
	sim.food = 10.0
	_ticks(sim, 60)
	eq(float(camp["hp"]), hp_end, "a dead camp is skipped (TS:861)")
	eq(float(camp["anger"]), anger_end, "no anger accrues on a dead camp")
	_drop(g)


## Pin the assault warriors onto the camp each tick (hasTarget + the camp
## point) — the move block converges them and the job AI never re-targets.
func _poke_camp(sim: Variant, camp: Dictionary) -> void:
	for t in sim.tribe:
		if String(t["role"]) == "warrior":
			t["hasTarget"] = true
			t["targetX"] = float(camp["x"])
			t["targetZ"] = float(camp["z"])


## Pin provenance: the beast fight TribeStage.ts:898-911 verbatim —
## fighters = tribe within 60, chiefNear = chief within 60, dps =
## fighters·9 + (chiefNear ? 14 : 0); the gore roll is chief-proximity-gated
## (A08) and invuln-guarded. Seed 0x7E1A. invuln is pinned high so the gore
## roll still draws (stream parity) but never fires.
func test_beast_dps_fighters_and_chief() -> void:
	var g: Variant = _boot(0x7E1A)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	sim.raidTimer = 1.0e9
	_park_resources(sim)
	sim.trees.clear()  # the fighters get no targets and stand where parked
	sim.spawn_beast()  # TS:1012-1021 — hp 420, one pinned angle draw
	var b: Dictionary = sim.beast
	b["x"] = 30.0
	b["z"] = 60.0  # within 60 of the chief (0,60) and of both fighters
	sim.invulnT = 1.0e9
	# fighters 0/1 parked in the 60 ring; founder 2 out
	sim.tribe[0]["x"] = 10.0
	sim.tribe[0]["z"] = 60.0
	sim.tribe[1]["x"] = 30.0
	sim.tribe[1]["z"] = 70.0
	sim.tribe[2]["x"] = 2000.0
	sim.tribe[2]["z"] = 60.0
	# (a) 2 fighters + chief near: dps 2·9 + 14 = 32 for 1 s
	_ticks(sim, 60)
	approx(float(b["hp"]), 420.0 - 32.0, "dps = 9·fighters + 14 chief (TS:901)", 1e-6)
	eq(float(sim.deathFade), 0.0, "the invuln gate held the gore off (TS:906)")
	# (b) the chief walks away: 9·2 = 18 for 1 s
	sim.px = 900.0
	_ticks(sim, 60)
	approx(float(b["hp"]), 420.0 - 32.0 - 18.0, "chiefNear false: the 14 drops (TS:901)", 1e-6)
	# (c) no fighters at all: zero dps
	sim.tribe.clear()
	_ticks(sim, 60)
	approx(float(b["hp"]), 420.0 - 50.0, "no fighters, no chief: dps 0", 1e-6)
	eq(float(sim.deathFade), 0.0, "still no chief death (the chief is far)")
	_drop(g)
