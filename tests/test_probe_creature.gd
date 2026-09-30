# Task 10 econ probes — the §5.3 econ-parity criterion through the REAL
# creature stage: each probe boots the full Game + real CreatureStage
# (out-of-tree, the M2 test_econ_probes boot shape) on a pinned seed and drives
# the sim through its documented input-SNAPSHOT contract (the
# tests/econ_det_shard.gd runner shape — "tests construct it literally",
# creature_sim.update's docstring), with eco observations pinned to the
# TS-verbatim formulas (each probe's provenance comment cites the frozen TS
# line; the probe IS the pin — divergence = documented here + in the report).
#
# Probes (task-10 brief AC + TS CreatureStage.ts / creatureEvents.ts):
#   bush-eat      — hold-input: DNA = 1.2·took, heal 6·took, regrow cycle 25 s
#                   (CreatureStage.ts:752-763 + the 435-443 regrow clock)
#   bone rate     — the 8 world bones: meteor 120 first then 45 each, cap 60
#                   (CreatureStage.ts:767-787 + the 174-181 meteor index)
#   charm→pack    — packLimit 2 + ⌊arms/2⌋ + ⌊brain/2⌋, the beat bar to the
#                   pack-full gate (CreatureStage.ts:182 + 1023-1115)
#   day cycle     — dayPhase += dt/180, night window (0.55, 0.95) exclusive
#                   (CreatureStage.ts:464 + 1318)
#   spawn         — maintain_population: despawn 2200 (pack exempt), target
#                   min(10, round(pop·0.5)), 0.35 per 1.5 s check
#                   (CreatureStage.ts:391-410 + 569-573)
#   corpse econ   — corpseT 12 s, meat-eat heal 14·dt / DNA 2.4·dt gated on a
#                   non-herbivore diet, the 35 % bone roll on expiry
#                   (CreatureStage.ts:829 + 841-855)
#   stampede      — cadence under chaos through the REAL scheduler: gap 40 ·
#                   gapMult · (1 − 0.35·chaos), warn→apply, duration [14,14],
#                   cooldown 55, 6-ent herd with lifespanStampede 14
#                   (chaos.ts update + creatureEvents.ts stampede def +
#                   CreatureStage.ts:1155-1169)
#
# Statistical windows (the 0.35 rate pins) are binomial-3σ over fresh-seed
# trials; every other number is an exact TS-formula pin at the probe's seed.
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const ChaosScript := preload("res://src/game/chaos.gd")

const DT := 1.0 / 60.0
const Z_TO_Y := 0.62


# ---- hud toast/banner recorder (method Callables — the T8 arity shape) --------

var _toasts: Array = []
var _banners: Array = []


func _rec_toast(text: String, kind: String, icon: String, _ttl := 4.0,
		_card: Variant = null) -> void:
	_toasts.append([text, kind, icon])


func _rec_banner(data: Variant) -> void:
	_banners.append(data)


# ---- scenario scaffold ---------------------------------------------------------

## Real boot: Game + the REAL creature stage, out-of-tree (run.gd drives tests
## synchronously inside _initialize — the main loop never reaches a frame, so
## tree-entered nodes never fire _ready; the stage's _ready is invoked ONCE
## manually, the M2 probe's cell._ready shape). switch_stage fires the real
## on_enter (arrival banner, eco bootstrap onto ctx, pack restore).
func _boot(seed_v: int) -> Variant:
	var ctx: Variant = ContextScript.new(seed_v)
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(CreatureStageScript.new(game))
	game.stages["creature"]._ready()
	game.switch_stage("creature")
	return game


## Eventless world for clean econ accounting: the chaos scheduler's natural
## path never spawns inside the window (probe seam — the deck itself stays the
## real one; P7 drives it for the cadence pins).
func _silence_chaos(sim: Variant) -> void:
	sim.chaos.gap = 1.0e9


## Park every wild nest beyond the 2200 despawn ring so maintain_population's
## respawns land far away (the player's own kin nest never spawns — no eco
## species carries the "player" id).
func _park_nests(sim: Variant) -> void:
	for n in sim.nests:
		n["x"] = 99999.0
		n["z"] = 20.0


## Input snapshot — the sim's documented contract shape (test_creature_sim
## fixture, creature_sim.update docstring).
func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


func _drop(game: Variant) -> void:
	# break the overlay Callable cycles before free (test_game_flow pattern)
	game.hud = {}
	game.editor = {}
	game.pause = {}
	game.free()


func _pack_count(sim: Variant) -> int:
	var n := 0
	for e in sim.ents:
		if bool(e["pack"]) and not e.has("corpseT"):
			n += 1
	return n


## First living NON-kin species (kin lines are exempt from the population
## valve — the spawn-pressure probes must drive a valve-eligible line).
func _valve_species(sim: Variant) -> Dictionary:
	for sp in sim.eco.living():
		if not bool(sp.get("kin", false)):
			return sp
	failures.append("no non-kin living species for the valve probes")
	return {}


# ---- probes --------------------------------------------------------------------

## Pin provenance: CreatureStage.ts:752-763 verbatim — bite = dt·2, took =
## min(bite, b.food), b.regrow = 25, php += 6·took (cap pmaxHp), addDna(took·
## 1.2); the regrow clock TS:435-443 (regrow -= dt, refill food 2..5 at 0).
## Seed 0x0BEF. The 60 s hold rides the per-tick accounting below (a regrow
## refill lands at the START of a tick — the block precedes the eat — so a
## tick whose previous regrow read ∈ (0, dt] contributes a full bite).
func test_bush_eat_dna_heal_and_regrow_cycle() -> void:
	var g: Variant = _boot(0x0BEF)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	_park_nests(sim)
	sim.ents.clear()
	# isolate bush 0 on the player, park the rest + the auto-pickup bones
	for i in sim.bushes.size():
		var b: Dictionary = sim.bushes[i]
		if i == 0:
			b["x"] = float(sim.px)
			b["z"] = float(sim.pz)
			b["food"] = 5.0
			b["regrow"] = 0.0
		else:
			b["x"] = 99999.0
			b["z"] = 99999.0
	for bo in sim.bones:
		bo["x"] = 99999.0
		bo["z"] = 99999.0
	# heal headroom: 6·5 = 30 lands UNCAPPED below pmaxHp 70
	sim.php = 30.0
	var dna0: int = int(g.context.dna)
	var frac0: float = float(g.context._dna_frac)
	var held := _inp({"down": true, "wx": float(sim.px), "wy": float(sim.pz) * Z_TO_Y})
	var took := 0.0
	for f in 150:  # 5.0 food at 2 food/s = 2.5 s — no regrow mid-drain
		took += minf(DT * 2.0, float(sim.bushes[0]["food"]))
		sim.update(DT, held)
	approx(took, 5.0, "the bush drained 5.0 food at the TS dt·2 bite rate", 1e-9)
	approx(float(g.context.dna) + float(g.context._dna_frac) - float(dna0) - frac0,
			6.0, "DNA = 1.2·took (TS addDna(took·1.2), fractional ledger exact)", 1e-6)
	approx(float(sim.php), 60.0, "heal = 6·took, uncapped (30 → 60 < pmaxHp 70)", 1e-6)
	ok(absf(float(sim.bushes[0]["food"])) < 1e-9, "bush stripped to 0 (float residue)")
	approx(float(sim.bushes[0]["regrow"]), 25.0, "regrow armed at 25 s on the last bite", 1e-6)
	# the regrow cycle: still bare a hair under 25 s, re-grown right after
	var idle := _inp()
	for f in 1493:  # 24.883 s
		sim.update(DT, idle)
	ok(absf(float(sim.bushes[0]["food"])) < 1e-9, "regrow not yet due at 24.9 s")
	for f in 15:  # cross the 25 s line
		sim.update(DT, idle)
	var rg: float = float(sim.bushes[0]["food"])
	ok(rg >= 2.0 and rg <= 5.0, "regrown food back in the TS 2..5 band (%.3f)" % rg)
	eq(float(sim.bushes[0]["regrow"]), 0.0, "regrow clock cleared on the refill")
	# the AC's hold-input 60 s window with EXACT per-tick accounting from the
	# sim's own observables (the regrow boundary drifts a float-hair past the
	# inferred clock tick, so the consumed food is read off the food deltas):
	# a refill tick shows food INCREASING (fresh 2..5 minus one bite) → the
	# sim took exactly one bite; otherwise it took fb − fa.
	var dna1: int = int(g.context.dna)
	var frac1: float = float(g.context._dna_frac)
	var took_total := 0.0
	for f in 3600:  # 60 s of held input
		var food_before: float = float(sim.bushes[0]["food"])
		sim.update(DT, held)
		var food_after: float = float(sim.bushes[0]["food"])
		took_total += DT * 2.0 if food_after > food_before + 1e-12 \
				else (food_before - food_after)
	approx(float(g.context.dna) + float(g.context._dna_frac) - float(dna1) - frac1,
			1.2 * took_total, "60 s hold: DNA = 1.2·took through regrow cycles", 1e-6)
	eq(float(sim.php), float(sim.pmaxHp), "60 s hold: healed to the pmaxHp cap")
	_drop(g)


## Pin provenance: CreatureStage.ts:767-787 verbatim — the auto-pickup (34 px,
## no input), dna = isMeteor ? 120 : 45, the taken-filter + splice(0, len-60)
## cap keeping the TAIL, the same-tick second bone (the TS mid-for reassign
## quirk). The 8 world bones with index 0 = meteor: TS:174-181. Seed 0x0BF0.
func test_bone_dna_meteor_first_then_45_and_cap_60() -> void:
	var g: Variant = _boot(0x0BF0)
	var sim: Variant = g.current.sim
	_park_nests(sim)
	sim.ents.clear()
	_toasts = []
	g.hud["toast"] = _rec_toast
	# the real 8 world bones teleported onto the player — all 8 in range fires
	# the same tick (the loop keeps walking the ORIGINAL array)
	for i in sim.bones.size():
		sim.bones[i]["x"] = float(sim.px)
		sim.bones[i]["z"] = float(sim.pz)
	eq(String(sim.bones[0]["kind"]), "meteor", "world bone 0 is the meteor (TS:174-181)")
	var dna0: int = int(g.context.dna)
	sim.update(DT, _inp())
	eq(int(g.context.dna) - dna0, 435, "8 bones: meteor 120 first, then 45 × 7")
	eq(sim.bones.size(), 0, "all taken bones filtered out (8 ≤ cap 60)")
	var marrow := 0
	var ancient := 0
	for t in _toasts:
		if String(t[0]).contains("Meteor marrow"):
			marrow += 1
		if String(t[0]).contains("Ancient bones"):
			ancient += 1
	eq(marrow, 1, "one meteor-marrow toast")
	eq(ancient, 7, "seven ancient-bones toasts")
	# cap 60: 65 fresh untaken bones (tagged), the LAST one in range — the
	# taken-filter leaves 64, the splice keeps the tail 60 (drops the head 4)
	var fresh: Array = []
	for i in 65:
		fresh.append({"x": 99999.0, "z": 99999.0, "taken": false, "kind": "bone", "tag": i})
	fresh[64]["x"] = float(sim.px)
	fresh[64]["z"] = float(sim.pz)
	sim.bones = fresh
	dna0 = int(g.context.dna)
	sim.update(DT, _inp())
	eq(int(g.context.dna) - dna0, 45, "the 66th bone pays 45 (plain bone)")
	eq(sim.bones.size(), 60, "cap: splice(0, len-60) keeps 60")
	var tags: Array = []
	for bo in sim.bones:
		tags.append(int(bo["tag"]))
	eq(tags[0], 4, "cap keeps the TAIL: head 4 dropped")
	eq(tags[59], 63, "cap keeps the TAIL: the last untaken stays")
	_drop(g)


## Pin provenance: packLimit TS CreatureStage.ts:182 (2 + ⌊arms/2⌋ + ⌊brain/2⌋,
## recomputed on_enter:283 and on_stats_changed:1326); the charm beat TS
## 1023-1115 (3 hits in the shrinking zone, mustExit re-arm, karma +0.03,
## persist_state) and the pack-full gate 1036-1039. Seed 0x0BF1.
func test_pack_limit_formula_and_charm_pack_full_gate() -> void:
	var g: Variant = _boot(0x0BF1)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	_park_nests(sim)
	sim.ents.clear()
	# the formula table through the real recompute seam
	var cases := [[0, 0, 2], [1, 0, 2], [2, 0, 3], [3, 0, 3], [4, 0, 4],
			[0, 2, 3], [0, 3, 3], [0, 4, 4], [2, 3, 4], [4, 4, 6]]
	for cse in cases:
		g.context.genome["arms"] = cse[0]
		g.context.genome["brain"] = cse[1]
		sim.on_stats_changed()
		eq(int(sim.packLimit), cse[2],
				"packLimit arms %d brain %d (TS 2 + ⌊arms/2⌋ + ⌊brain/2⌋)" % [cse[0], cse[1]])
	g.context.genome["arms"] = 0
	g.context.genome["brain"] = 0
	sim.on_stats_changed()
	eq(int(sim.packLimit), 2, "packLimit restored to 2 for the charm beat")
	_toasts = []
	g.hud["toast"] = _rec_toast
	# charm #1: a wild (non-pack) player-genome ent beside the player
	var e1: Dictionary = sim.spawn_ent(null, float(sim.px) + 60.0, float(sim.pz), {}, {})
	var karma0: float = float(g.context.karma)
	var guard := 0
	while _pack_count(sim) == 0 and guard < 900:
		guard += 1
		var zone: float = 0.35 - float(sim.charmHits) * 0.05
		var over := {"keys_held": ["KeyF"]}
		if sim.charmActive and absf(float(sim.charmMarker)) < zone:
			over["keys_pressed"] = ["Space"]
		sim.update(DT, _inp(over))
	eq(_pack_count(sim), 1, "3 beat hits befriended the first ent (TS charmHits ≥ 3)")
	ok(bool(e1["pack"]), "the target joined the pack")
	eq(String(e1["mood"]), "happy", "befriended mood happy")
	# the befriend pays karma +0.03 (TS) — and update_charm runs BEFORE
	# update_player in the same tick, so one pack-follow karma tick
	# (dt·0.002) rides the loop's exit tick
	var karma_paid: float = float(g.context.karma) - karma0
	ok(karma_paid >= 0.03 - 1e-9 and karma_paid <= 0.03 + DT * 0.002 + 1e-9,
			"befriend karma +0.03 (TS) (+≤1 pack-follow tick) (got %.6f)" % karma_paid)
	var friends := 0
	for t in _toasts:
		if String(t[0]).contains("A new friend joins your pack"):
			friends += 1
	eq(friends, 1, "one befriend toast")
	# charm #2: the second wild ent (the pack member is excluded by try_charm)
	var e2: Dictionary = sim.spawn_ent(null, float(sim.px) + 60.0, float(sim.pz), {}, {})
	guard = 0
	while _pack_count(sim) < 2 and guard < 900:
		guard += 1
		var zone2: float = 0.35 - float(sim.charmHits) * 0.05
		var over2 := {"keys_held": ["KeyF"]}
		if sim.charmActive and absf(float(sim.charmMarker)) < zone2:
			over2["keys_pressed"] = ["Space"]
		sim.update(DT, _inp(over2))
	eq(_pack_count(sim), 2, "second befriend reaches packLimit 2")
	# the pack-full gate: a third wild ent cannot join
	var e3: Dictionary = sim.spawn_ent(null, float(sim.px) + 60.0, float(sim.pz), {}, {})
	_toasts = []
	guard = 0
	while guard < 30:
		guard += 1
		sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	var full := 0
	for t in _toasts:
		if String(t[0]).contains("pack is full"):
			full += 1
	ok(full >= 1, "the pack-full toast fired (%d)" % full)
	eq(_pack_count(sim), 2, "pack stays at packLimit")
	eq(bool(e3["pack"]), false, "the third ent never joined")
	# the befriend path snapshots the pack for autosaves (TS persistState)
	var raw: Variant = g.context.flags.get("packGenomes", "")
	var pack: Variant = JSON.parse_string(String(raw)) if String(raw) != "" else null
	ok(pack is Array and (pack as Array).size() == 2,
			"packGenomes snapshot holds 2 members")
	_drop(g)


## Pin provenance: dayPhase TS CreatureStage.ts:102 (start 0.15) + 464
## ((dayPhase + dt/180) % 1 — the 180 s full loop); the night window TS:1318
## (0.55, 0.95) EXCLUSIVE. Seed 0x0BF2.
func test_day_cycle_180s_loop_and_night_window() -> void:
	var g: Variant = _boot(0x0BF2)
	var sim: Variant = g.current.sim
	approx(float(sim.dayPhase), 0.15, "dayPhase starts morning 0.15", 1e-9)
	for f in 3600:  # 60 s of real update
		sim.update(DT, _inp())
	approx(float(sim.dayPhase), 0.15 + 60.0 / 180.0,
			"dayPhase += dt/180 through real updates", 1e-6)
	for f in 7200:  # another 120 s → the full 180 s loop
		sim.update(DT, _inp())
	approx(float(sim.dayPhase), 0.15, "180 s = one full day/night loop", 1e-6)
	sim.dayPhase = 0.25
	eq(sim.is_night(), false, "0.25 noon: not night")
	sim.dayPhase = 0.55
	eq(sim.is_night(), false, "0.55: not night (window exclusive)")
	sim.dayPhase = 0.550001
	eq(sim.is_night(), true, "0.550001: night")
	sim.dayPhase = 0.75
	eq(sim.is_night(), true, "0.75 midnight: night")
	sim.dayPhase = 0.949999
	eq(sim.is_night(), true, "0.949999: night")
	sim.dayPhase = 0.95
	eq(sim.is_night(), false, "0.95: not night (window exclusive)")
	_drop(g)


## Pin provenance: maintain_population TS CreatureStage.ts:391-410 — the 2200
## despawn (pack exempt), target = min(10, round(pop·0.5)), the 0.35 chance per
## check, the check every 1.5 s (spawnTimerCheckT, TS:569-573). Seeds
## 0x0BF3 (exact plateaus) + 0x1000+i (the 0.35 rate trials).
func test_spawn_pressure_target_cap_and_rate() -> void:
	# (a) plateau: pop 3.0 → target round(1.5) = 2, exactly 2 visible and no more
	var g: Variant = _boot(0x0BF3)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	_park_nests(sim)
	sim.ents.clear()
	var sp: Dictionary = _valve_species(sim)
	var nest: Dictionary = {"x": float(sim.px) + 100.0, "z": float(sim.pz),
			"speciesId": String(sp["id"]), "members": 4}
	var found_nest := false
	for n in sim.nests:
		if String(n["speciesId"]) == String(sp["id"]):
			n["x"] = nest["x"]
			n["z"] = nest["z"]
			found_nest = true
			break
	if not found_nest:
		sim.nests.append(nest)
	sp["pop"] = 3.0
	for f in 5400:  # 90 s — expected fills in ~4-6 checks at 0.35
		sp["pop"] = 3.0  # hold the eco dynamic still: the target must read round(1.5)
		sim.update(DT, _inp())
	var visible := 0
	for e in sim.ents:
		if String(e["speciesId"]) == String(sp["id"]):
			visible += 1
	eq(visible, 2, "plateau: pop 3.0 → min(10, round(pop·0.5)) = 2 visible")
	for f in 1800:  # 30 more seconds — the plateau holds (never exceeds target)
		sp["pop"] = 3.0
		sim.update(DT, _inp())
	visible = 0
	for e2 in sim.ents:
		if String(e2["speciesId"]) == String(sp["id"]):
			visible += 1
	eq(visible, 2, "plateau holds: the valve stops at the target")
	# (b) the cap: pop 100 → target 10, never 11
	sp["pop"] = 100.0
	for f in 5400:
		sp["pop"] = 100.0
		sim.update(DT, _inp())
	visible = 0
	for e3 in sim.ents:
		if String(e3["speciesId"]) == String(sp["id"]):
			visible += 1
	eq(visible, 10, "cap: pop 100 → target min(10, …) = 10 visible")
	_drop(g)
	# (c) the 2200 despawn with the pack exemption (fresh boot, one check)
	var g2: Variant = _boot(0x0BF3)
	var sim2: Variant = g2.current.sim
	_silence_chaos(sim2)
	_park_nests(sim2)
	sim2.ents.clear()
	var wild: Dictionary = sim2.spawn_ent(null, float(sim2.px) + 2500.0, float(sim2.pz), {}, {})
	var pack_ent: Dictionary = sim2.spawn_ent(null, float(sim2.px) + 2500.0,
			float(sim2.pz), {}, {"pack": true})
	for f in 120:  # two spawn checks
		sim2.update(DT, _inp())
	var wild_gone := true
	var pack_kept := false
	for e5 in sim2.ents:
		if is_same(e5, wild):
			wild_gone = false
		if is_same(e5, pack_ent):
			pack_kept = true
	eq(wild_gone, true, "wild ent beyond 2200 despawned")
	eq(pack_kept, true, "pack ent beyond 2200 is exempt")
	_drop(g2)
	# (d) the 0.35 rate: 40 fresh one-check trials (binomial 40 @ 0.35 →
	# mean 14, 3σ ≈ 9 → window [5, 23])
	var hits := 0
	for i in 40:
		var gt: Variant = _boot(0x1000 + i)
		var simt: Variant = gt.current.sim
		_silence_chaos(simt)
		_park_nests(simt)
		simt.ents.clear()
		var spt: Dictionary = _valve_species(simt)
		for n in simt.nests:
			if String(n["speciesId"]) == String(spt["id"]):
				n["x"] = float(simt.px) + 100.0
				n["z"] = float(simt.pz)
		spt["pop"] = 1.0  # target round(0.5) = 1
		for f in 92:  # exactly one 1.5 s check
			spt["pop"] = 1.0
			simt.update(DT, _inp())
		var vis := 0
		for e6 in simt.ents:
			if String(e6["speciesId"]) == String(spt["id"]):
				vis += 1
		if vis > 0:
			hits += 1
		_drop(gt)
	ok(hits >= 5 and hits <= 23,
			"0.35 per-check spawn rate over 40 trials (got %d, binomial 3σ window 5..23)" % hits)


## Pin provenance: corpseT 12 (TS CreatureStage.ts:829), the player meat-eat
## (heal 14·dt, DNA 2.4·dt, gated on diet != herbivore + held input, TS
## 841-855), the 35 % bone roll on expiry (TS:844). Seeds 0x0BF4 (timing) +
## 0x2000+i (the 40-trial bone-rate window).
func test_corpse_economy_12s_meat_and_bone_rate() -> void:
	var g: Variant = _boot(0x0BF4)
	var sim: Variant = g.current.sim
	_silence_chaos(sim)
	_park_nests(sim)
	sim.ents.clear()
	for bo in sim.bones:
		bo["x"] = 99999.0
		bo["z"] = 99999.0
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 20.0, float(sim.pz), {}, {})
	sim.kill_ent(e)
	ok(e.has("corpseT"), "kill_ent marked the corpse")
	approx(float(e["corpseT"]), 12.0, "corpseT 12 s (TS:829)", 1e-9)
	# meat-eat through the real corpse branch (omnivore player, held input)
	g.context.genome["diet"] = "omnivore"
	sim.php = 40.0
	var dna0: int = int(g.context.dna)
	var frac0: float = float(g.context._dna_frac)
	var held := _inp({"down": true})
	for f in 60:  # 1 s on the corpse
		sim.update(DT, held)
	approx(float(sim.php), 54.0, "corpse meat heals 14·dt (40 → 54 over 1 s)", 1e-6)
	approx(float(g.context.dna) + float(g.context._dna_frac) - float(dna0) - frac0,
			2.4, "corpse meat pays 2.4·dt DNA over 1 s", 1e-6)
	# herbivores cannot eat meat: fresh corpse, fresh window, php untouched
	var e2: Dictionary = sim.spawn_ent(null, float(sim.px) + 20.0, float(sim.pz), {}, {})
	sim.kill_ent(e2)
	g.context.genome["diet"] = "herbivore"
	sim.php = 40.0
	for f in 60:
		sim.update(DT, _inp({"down": true}))
	approx(float(sim.php), 40.0, "herbivore diet: no corpse meat-eat", 1e-6)
	# the 12 s expiry: the first corpse (12 s − the 1 s already eaten off) and
	# the second (12 s fresh) both leave the list; the bone roll is probed
	# statistically below
	var eid1: int = int(e["eid"])
	var eid2: int = int(e2["eid"])
	for f in 1400:  # 23.3 s — past both expiries
		sim.update(DT, _inp())
	var corpses_left := 0
	for e3 in sim.ents:
		if int(e3["eid"]) == eid1 or int(e3["eid"]) == eid2:
			corpses_left += 1
	eq(corpses_left, 0, "both corpses removed by the 12 s lifecycle")
	_drop(g)
	# the 35 % bone roll on expiry: 40 fresh trials (binomial 40 @ 0.35 →
	# mean 14, 3σ ≈ 9 → window [5, 23])
	var bones_dropped := 0
	for i in 40:
		var gt: Variant = _boot(0x2000 + i)
		var simt: Variant = gt.current.sim
		_silence_chaos(simt)
		_park_nests(simt)
		simt.ents.clear()
		for bo in simt.bones:
			bo["x"] = 99999.0
			bo["z"] = 99999.0
		var et: Dictionary = simt.spawn_ent(null, float(simt.px) + 900.0,
				float(simt.pz), {}, {})
		simt.kill_ent(et)
		var bones0: int = simt.bones.size()
		for f in 740:  # 12.3 s — past the expiry
			simt.update(DT, _inp())
		var gained: int = simt.bones.size() - bones0
		ok(gained == 0 or gained == 1, "trial %d: 0 or 1 bone on expiry" % i)
		bones_dropped += gained
		_drop(gt)
	ok(bones_dropped >= 5 and bones_dropped <= 23,
			"35 %% bone roll over 40 trials (got %d, binomial 3σ window 5..23)" % bones_dropped)


## Pin provenance: the cadence under chaos through the REAL scheduler — gap 40
## (creature_sim constructor, TS CreatureStage.ts:160-162), gap_chaos_scale
## 0.35, effective gap = gap · gapMult · (1 − 0.35·chaos) (chaos.ts update),
## the stampede def creatureEvents.ts:114-126 (warn → duration [14,14] →
## cooldown 55) and the herd TS CreatureStage.ts:1155-1169 (6 ents,
## lifespanStampede 14, one lane, tx = dir·WORLD_HALF). Seed 0x0BF5 (a) drives
## the deck rebuilt to ONLY the real stampede def for exact cadence pins;
## seed 0x0BF6 (b) rides the FULL deck as a fires-under-chaos smoke.
func test_stampede_cadence_under_chaos() -> void:
	# (a) exact cadence: single real def, chaos 0.9 → gap_eff = 40·(1−0.315) = 27.4
	var g: Variant = _boot(0x0BF5)
	var sim: Variant = g.current.sim
	_park_nests(sim)
	sim.ents.clear()
	g.context.chaos = 0.9
	sim.invuln = 9999.0  # the herd/meteors may not hurt the cadence witness
	var stampede_def: Dictionary = {}
	for d in sim.chaos.defs:
		if String(d["id"]) == "stampede":
			stampede_def = d
	eq(String(stampede_def.get("id", "")), "stampede", "the real stampede def found")
	sim.chaos = ChaosScript.new(sim.rng.branch(), [stampede_def])
	# mirror the sim constructor's widened cadence (creature_sim constructor,
	# TS CreatureStage.ts:160-162) — a fresh scheduler resets gap 26/scale 0.45
	sim.chaos.gap = 40.0
	sim.chaos.gap_chaos_scale = 0.35
	var gap_mult: float = float(g.context.chaos_gap_mult())
	var gap_bias: float = float(sim._hooks["get_gap_bias"].call())
	var warn_scale: float = float(sim._hooks["get_warn_scale"].call())
	var gap_eff: float = 40.0 * gap_mult * gap_bias * (1.0 - 0.35 * 0.9)
	var flips: Array = []  # sim.time at each warn→active conversion
	var prev_active := false
	for f in 9600:  # 160 s — the second stampede lands ~first + 14 + 55 + warn
		var now_active := false
		for a in sim.chaos._active:
			if String(a["def"]["id"]) == "stampede" and String(a["phase"]) == "active":
				now_active = true
		if now_active and not prev_active:
			flips.append(float(sim.time))
		prev_active = now_active
		sim.update(DT, _inp())
	ok(flips.size() >= 2, "two stampedes fired under chaos (got %d)" % flips.size())
	if flips.size() >= 2:
		approx(float(flips[0]), gap_eff + 2.5 * warn_scale,
				"first stampede: warn→apply at gap_eff %.2f + warn %.2f (chaos 0.9)" % [
						gap_eff, 2.5 * warn_scale], 0.1)
		ok(float(flips[1]) - float(flips[0]) >= 14.0 + 55.0 - 0.1,
				"cadence floor: duration 14 + cooldown 55 (%.2f)" % (float(flips[1]) - float(flips[0])))
		ok(float(flips[1]) - float(flips[0]) <= 14.0 + 55.0 + 2.5 * warn_scale + 1.0,
				"cadence ceiling: the next warn opens on the first eligible tick")
		# the herd through the REAL apply — replay deterministically to just
		# past the first flip and inspect the 6 spawned ents + the toast
		var g2: Variant = _boot(0x0BF5)
		var sim2: Variant = g2.current.sim
		_park_nests(sim2)
		sim2.ents.clear()
		g2.context.chaos = 0.9
		sim2.invuln = 9999.0
		var def2: Dictionary = {}
		for d in sim2.chaos.defs:
			if String(d["id"]) == "stampede":
				def2 = d
		sim2.chaos = ChaosScript.new(sim2.rng.branch(), [def2])
		sim2.chaos.gap = 40.0
		sim2.chaos.gap_chaos_scale = 0.35
		_toasts = []
		g2.hud["toast"] = _rec_toast
		while float(sim2.time) < float(flips[0]) + 2.0 * DT:
			sim2.update(DT, _inp())
		var herd := 0
		var lane_z := 0.0
		for e in sim2.ents:
			if e.has("lifespanStampede"):
				herd += 1
				lane_z = float(e["z"]) if herd == 1 else lane_z
				# 1-2 update ticks old at the replay stop — the clock ticked
				ok(absf(float(e["lifespanStampede"]) - 14.0) <= 0.1, "herd lifespan 14")
				ok(absf(float(e["z"]) - lane_z) <= 100.0 + 1e-6, "one shared lane z (±60±40)")
		eq(herd, 6, "the apply spawned the 6-ent herd")
		var st := 0
		for t in _toasts:
			if String(t[0]).contains("STAMPEDE!"):
				st += 1
		eq(st, 1, "the stampede toast fired")
		_drop(g2)
	_drop(g)
	# (b) full-deck smoke: the stampede fires among the real deck under chaos
	var g3: Variant = _boot(0x0BF6)
	var sim3: Variant = g3.current.sim
	_park_nests(sim3)
	sim3.ents.clear()
	g3.context.chaos = 0.9
	sim3.invuln = 9999.0
	var stampede_times: Array = []
	var prev3 := false
	for f in 9600:  # 160 s of the real deck at chaos 0.9
		var now3 := false
		for a in sim3.chaos._active:
			if String(a["def"]["id"]) == "stampede" and String(a["phase"]) == "active":
				now3 = true
		if now3 and not prev3:
			stampede_times.append(float(sim3.time))
		prev3 = now3
		sim3.update(DT, _inp())
	ok(stampede_times.size() >= 1,
			"full deck: a stampede fired under chaos 0.9 in 160 s (times %s)" % str(stampede_times))
	if stampede_times.size() >= 2:
		ok(float(stampede_times[1]) - float(stampede_times[0]) >= 69.0 - 0.1,
				"full deck: the stampede cadence floor holds")
	_drop(g3)
