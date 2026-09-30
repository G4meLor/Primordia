# Tests for game/creature/creature_sim.gd — the creature stage sim core:
# state structs, seedLandEcology, spawn, player physics/interactions, world
# objects (bushes/bones/nests/hazards), death/respawn, eco tick, chaos wiring.
# TS source: Spore src/game/creature/CreatureStage.ts (frozen). Path-based
# extends + preload-by-path: class_name globals don't resolve in `-s` mode.
# TS-exact pins printed by the throwaway vitest rig
# Spore/tools/print-creature-sim-values.test.ts (seed 0xC0FFEE).
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const RngLib := preload("res://src/core/rng.gd")
const WorldGenome := preload("res://src/evo/world_genome.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const StatsLib := preload("res://src/evo/stats.gd")
const EcoLib := preload("res://src/evo/ecosystem.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE
const Z_TO_Y := 0.62
const Z_MIN := -200.0
const Z_MAX := 240.0
const WORLD_HALF := 2700.0


# ---- fixtures ------------------------------------------------------------------

# Builds a GameContext (explicit seed), the stage rng branch, a recording
# hooks set, and the sim. genome_mods merge into ctx.genome BEFORE sim
# construction (pStats is a construction-time snapshot, TS-verbatim).
func _mk_sim(seed_v: int = SEED, genome_mods: Dictionary = {},
		difficulty: String = "normal", world_override: Variant = null) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	if not genome_mods.is_empty():
		var g: Dictionary = ctx.genome
		g.merge(genome_mods, true)
	ctx.difficulty = difficulty
	if world_override != null:
		ctx.world = world_override
	var rec: Dictionary = {
		"toasts": [], "banners": [], "floats": [], "audio": [], "shakes": [],
		"bursts": [], "spawns": [], "notes": [], "events": [],
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(playtime): rec["notes"].append(playtime),
		"context_event": func(ev, data): rec["events"].append([ev, data]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


# Input snapshot with the ruling's field shape; `over` merges overrides.
func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


# assertSane port: the sim's core numerics stay finite after any run.
func _assert_sane(m: Dictionary, tag: String) -> void:
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ok(is_finite(float(ctx.dna)), tag + ": dna finite")
	ok(is_finite(float(sim.px)), tag + ": px finite")
	ok(is_finite(float(sim.pz)), tag + ": pz finite")
	ok(is_finite(float(sim.php) + 0.001), tag + ": php+0.001 finite")


# Deep native-vs-native determinism snapshot (same code twice -> bit-equal;
# snappedf keeps the compare readable, 1e-6 >> any same-formula wobble).
func _snap(m: Dictionary) -> Dictionary:
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var ents: Array = []
	for e in sim.ents:
		ents.append([e["eid"], e["speciesId"], snappedf(e["x"], 1e-6), snappedf(e["z"], 1e-6),
				snappedf(e["vx"], 1e-6), snappedf(e["vz"], 1e-6), snappedf(e["hp"], 1e-6),
				e["facing"], snappedf(e["gait"], 1e-6), e["mood"], e["pack"], e["baby"],
				snappedf(e["seed"], 1e-9), snappedf(e["wanderT"], 1e-9),
				snappedf(e["tx"], 1e-6), snappedf(e["tz"], 1e-6), snappedf(e["biteCd"], 1e-9),
				e.has("corpseT"), snappedf(float(e.get("corpseT", 0.0)), 1e-9)])
	var bushes: Array = []
	for b in sim.bushes:
		bushes.append([snappedf(b["x"], 1e-9), snappedf(b["z"], 1e-9),
				snappedf(b["food"], 1e-9), snappedf(b["regrow"], 1e-9), snappedf(b["seed"], 1e-9)])
	var bones: Array = []
	for bo in sim.bones:
		bones.append([snappedf(bo["x"], 1e-9), snappedf(bo["z"], 1e-9), bo["taken"], bo["kind"]])
	var nests: Array = []
	for n in sim.nests:
		nests.append([snappedf(n["x"], 1e-9), snappedf(n["z"], 1e-9), n["speciesId"], n["members"]])
	var pops: Array = []
	for sp in ctx.eco.species:
		pops.append(snappedf(float(sp["pop"]), 1e-9))
	return {
		"px": snappedf(sim.px, 1e-6), "pz": snappedf(sim.pz, 1e-6),
		"py": snappedf(sim.py, 1e-9), "pvy": snappedf(sim.pvy, 1e-9),
		"pvx": snappedf(sim.pvx, 1e-6), "pvz": snappedf(sim.pvz, 1e-6),
		"php": snappedf(sim.php, 1e-6), "facing": sim.facing,
		"gait": snappedf(sim.gait, 1e-6), "speed01": snappedf(sim.speed01, 1e-9),
		"dayPhase": snappedf(sim.dayPhase, 1e-9), "time": snappedf(sim.time, 1e-9),
		"dna": ctx.dna, "karma": snappedf(float(ctx.karma), 1e-9),
		"chaos": snappedf(float(ctx.chaos), 1e-9), "invuln": snappedf(sim.invuln, 1e-9),
		"jumpCd": snappedf(sim.jumpCd, 1e-9), "biteCd": snappedf(sim.biteCd, 1e-9),
		"barrenT": snappedf(sim.barrenT, 1e-9),
		"ents": ents, "bushes": bushes, "bones": bones, "nests": nests,
		"pops": pops, "rng": sim.rng.state(),
	}


func _heard(rec: Dictionary, name: String) -> bool:
	for a in rec["audio"]:
		if a[0] == name:
			return true
	return false


# Park bushes/bones far away — bones AUTO-pickup on proximity (no input), so
# proximity-pin tests must isolate the object under test from the random field.
func _park_world_objects(m: Dictionary) -> void:
	var sim: Variant = m["sim"]
	for b in sim.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0
	for bo in sim.bones:
		bo["x"] = 99999.0
		bo["z"] = 99999.0


# ---- constructor bootstrap / seedLandEcology ------------------------------------

func test_boot_state_and_seed_land_ecology() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ok(ctx.eco != null, "eco bootstrapped onto ctx when absent")
	ok(sim.eco == ctx.eco, "sim eco is the ctx eco")
	# player arrival state (TS CreatureStage.ts:80-92)
	approx(sim.px, -2400.0, "px starts at the shore")
	approx(sim.pz, 20.0, "pz starts 20")
	approx(sim.dayPhase, 0.15, "dayPhase starts morning 0.15")
	approx(sim.invuln, 2.0, "constructor invuln 2 (onEnter re-grants 3)")
	# default genome creature stats: max_hp = 40 + 30 = 70
	approx(sim.pmaxHp, 70.0, "pmaxHp from computeCreatureStats")
	approx(sim.php, sim.pmaxHp, "arrive at full hp")
	# chaos: widened cadence (TS:160-162) + C1 deckSeed
	approx(float(sim.chaos.gap), 40.0, "chaos gap 40")
	approx(float(sim.chaos.gap_chaos_scale), 0.35, "chaos gapChaosScale 0.35")
	eq(int(sim.deckSeed), SEED, "deckSeed = world seed")
	# bushes: 46, TS-printed pins (print-creature-sim-values.test.ts)
	eq(sim.bushes.size(), 46, "46 bushes")
	var b0: Dictionary = sim.bushes[0]
	approx(float(b0["x"]), 2652.2416189312935, "bush0 x pin")
	approx(float(b0["z"]), 170.96075204201043, "bush0 z pin")
	approx(float(b0["food"]), 3.9565314000938088, "bush0 food pin 2..5")
	approx(float(b0["regrow"]), 0.0, "bush0 regrow 0")
	approx(float(b0["seed"]), 3.6914340087678283, "bush0 seed pin 0..9")
	var b1: Dictionary = sim.bushes[1]
	approx(float(b1["x"]), -2420.805542729795, "bush1 x pin")
	approx(float(b1["z"]), -78.52652785368264, "bush1 z pin")
	var b45: Dictionary = sim.bushes[45]
	approx(float(b45["x"]), 781.4626806881279, "bush45 x pin")
	approx(float(b45["food"]), 4.309681040002033, "bush45 food pin")
	for b in sim.bushes:
		ok(float(b["x"]) >= -WORLD_HALF and float(b["x"]) <= WORLD_HALF, "bush x in band")
		ok(float(b["z"]) >= Z_MIN and float(b["z"]) <= Z_MAX, "bush z in band")
		ok(float(b["food"]) >= 2.0 and float(b["food"]) <= 5.0, "bush food 2..5")
	# bones: 8, index 0 = meteor (TS:174-181)
	eq(sim.bones.size(), 8, "8 bones")
	var bo0: Dictionary = sim.bones[0]
	eq(String(bo0["kind"]), "meteor", "bone index 0 is the meteor")
	approx(float(bo0["x"]), -224.81783609837294, "bone0 x pin")
	approx(float(bo0["z"]), -31.255038157105446, "bone0 z pin")
	eq(bool(bo0["taken"]), false, "bone0 untaken")
	for i in range(1, 8):
		eq(String(sim.bones[i]["kind"]), "bone", "bones 1..7 are bones")
	var bo7: Dictionary = sim.bones[7]
	approx(float(bo7["x"]), 2048.6855396535248, "bone7 x pin")
	approx(float(bo7["z"]), 23.76760588027537, "bone7 z pin")
	# roster: 6 archetypes + titan + swarm at this seed (weights >= 1)
	var weights: Dictionary = WorldGenome.archetype_weights(ctx.world)
	var expected := 6
	if float(weights.get("titan", 0.0)) >= 1.0:
		expected += 1
	if float(weights.get("swarm", 0.0)) >= 1.0:
		expected += 1
	eq(ctx.eco.species.size(), expected, "roster = 6 archetypes + titan/swarm")
	# TS-printed species pins (ids/names/pops ride the shared eco+names ports)
	var sp0: Dictionary = ctx.eco.species[0]
	eq(String(sp0["id"]), "sp0_31ivkf", "species id pin (eco rng names/ids)")
	eq(String(sp0["name"]), "Squibbowaodon the Placid", "species name pin")
	approx(float(sp0["pop"]), 6.03267858736217, "species pop pin 5..10")
	var g0: Dictionary = sp0["genome"]
	approx(float(g0["size"]), 0.9, "archetype 0 size")
	eq(int(g0["legs"]), 4, "archetype 0 legs")
	eq(int(g0["eyes"]), 2, "archetype 0 eyes")
	eq(bool(g0["tail"]), true, "archetype 0 tail")
	eq(int(g0["hue"]), 85, "archetype 0 hue")
	eq(String(g0["coat"]), "fur", "archetype 0 coat")
	# the diet dial flipped archetype 3 (carnivore template -> herbivore) here
	eq(String(ctx.eco.species[3]["genome"]["diet"]), "herbivore", "diet dial live at this seed")
	eq(String(ctx.eco.species[1]["name"]), "Vexkuurp the Hungry", "species 1 name pin")
	# titan bonus AFTER the roster: size 2.1 plates hue 300 carnivore
	var sp6: Dictionary = ctx.eco.species[6]
	var g6: Dictionary = sp6["genome"]
	approx(float(g6["size"]), 2.1, "titan size 2.1")
	eq(int(g6["hue"]), 300, "titan hue 300")
	eq(String(g6["coat"]), "plates", "titan coat plates")
	eq(String(g6["diet"]), "carnivore", "titan carnivore")
	# swarm bonus: size 0.6, eyes 2, herbivore
	var sp7: Dictionary = ctx.eco.species[7]
	var g7: Dictionary = sp7["genome"]
	approx(float(g7["size"]), 0.6, "swarm size 0.6")
	eq(int(g7["eyes"]), 2, "swarm eyes 2")
	eq(String(g7["diet"]), "herbivore", "swarm herbivore")
	# nests per species, members 4, TS-printed pins + band gates
	eq(sim.nests.size(), expected, "a nest per species")
	var n0: Dictionary = sim.nests[0]
	approx(float(n0["x"]), -1264.4048957247287, "nest0 x pin ±0.9*WORLD_HALF")
	approx(float(n0["z"]), -103.99850809015334, "nest0 z pin Z_MIN+40..Z_MAX-40")
	eq(String(n0["speciesId"]), "sp0_31ivkf", "nest0 speciesId")
	eq(int(n0["members"]), 4, "nest members 4")
	for n in sim.nests:
		ok(absf(float(n["x"])) <= WORLD_HALF * 0.9 + 1e-6, "nest x ±0.9*WORLD_HALF")
		ok(float(n["z"]) >= Z_MIN + 40.0 and float(n["z"]) <= Z_MAX - 40.0, "nest z band")
	# every species discovered into the bestiary as 'creature'
	for sp in ctx.eco.species:
		var key: String = Ctx.genome_hash_lite(sp["genome"])
		ok(ctx.bestiary.has(key), "species discovered at seed")
		if ctx.bestiary.has(key):
			eq(String(ctx.bestiary[key]["stage"]), "creature", "discover stage 'creature'")
	ok(not sim.needs_land_fauna(), "roster is legged -> no land fauna needed")
	# packLimit default = 2 + floor(arms/2) + floor(brain/2) = 2 + 0 + 0
	eq(int(sim.packLimit), 2, "packLimit 2 at default genome")


func test_needs_land_fauna_gate() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# an empty eco (NEW LIFE reset) has no legged living -> true
	var fresh: Variant = EcoLib.new(ctx.rng.branch())
	sim.eco = fresh
	ok(sim.needs_land_fauna(), "empty eco needs land fauna")
	# a legless species does not satisfy the gate
	var g0: Dictionary = GenomeLib.default_genome()
	g0["legs"] = 0
	fresh.add_species(GenomeLib.clamp_genome(g0), 5.0)
	ok(sim.needs_land_fauna(), "legless-only roster still needs land fauna")
	# one legged living line satisfies it
	var g1: Dictionary = GenomeLib.default_genome()
	g1["legs"] = 4
	fresh.add_species(GenomeLib.clamp_genome(g1), 5.0)
	ok(not sim.needs_land_fauna(), "one legged living line satisfies the gate")
	# an extinct legged line does not count (living only)
	for sp in fresh.species:
		sp["extinct"] = true
	ok(sim.needs_land_fauna(), "extinct lines do not count")


# ---- spawnEnt --------------------------------------------------------------------

func test_spawn_ent_pins() -> void:
	var m := _mk_sim(SEED, {"arms": 4, "brain": 3, "legs": 4})
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	eq(int(sim.packLimit), 5, "packLimit 2 + floor(4/2) + floor(3/2) = 5")
	var e: Dictionary = sim.spawn_ent(null, 10.0, 20.0)
	eq(int(e["eid"]), 1, "eid starts at 1")
	eq(String(e["speciesId"]), "mutant", "sp=null -> speciesId 'mutant'")
	approx(float(e["x"]), 10.0, "x verbatim")
	approx(float(e["z"]), 20.0, "z verbatim")
	approx(float(e["hp"]), 70.0, "hp = stats.max_hp")
	approx(float(e["maxHp"]), 70.0, "maxHp = stats.max_hp")
	eq(int(e["facing"]), -1, "facing pin rng.chance(0.5)")
	approx(float(e["gait"]), 4.979101415723562, "gait pin rng.range(0,6)")
	approx(float(e["seed"]), 11.158805550076067, "seed pin rng.range(0,100)")
	approx(float(e["vx"]), 0.0, "vx 0")
	approx(float(e["vz"]), 0.0, "vz 0")
	eq(String(e["mood"]), "idle", "mood idle")
	eq(bool(e["pack"]), false, "pack false")
	eq(bool(e["baby"]), false, "baby false")
	approx(float(e["packCd"]), 0.0, "packCd 0")
	# draw order: facing -> gait -> seed, all stage-rng (TS:377-390)
	var e2: Dictionary = sim.spawn_ent(null, -5.0, 7.0, {}, {"baby": true})
	approx(float(e2["seed"]), 26.097264233976603, "second spawn seed pin (stream order)")
	approx(float(e2["hp"]), 28.0, "baby scaleHp 0.4")
	approx(float(e2["maxHp"]), 28.0, "baby maxHp 0.4")
	eq(bool(e2["baby"]), true, "baby flag")
	var e3: Dictionary = sim.spawn_ent(null, 0.0, 0.0, {}, {"pack": true})
	eq(bool(e3["pack"]), true, "pack opt")
	approx(float(e3["seed"]), 99.08609832637012, "third spawn seed pin")
	# wild speed tracks the player's legs: 96 * (0.6 + 0.4*4/4) = 96
	approx(float(e["stats"]["speed"]), 96.0, "wild speed tracks player legs (4)")
	# optional TS fields stay ABSENT until set (undefined semantics)
	ok(not e.has("eggT"), "eggT absent")
	ok(not e.has("corpseT"), "corpseT absent")
	ok(not e.has("flying"), "flying absent")
	ok(not e.has("lifespanStampede"), "lifespanStampede absent")
	ok(not e.has("pressCd"), "pressCd absent")
	# temperament band seeded from world seed + speciesId (pure, no rng)
	var band: Dictionary = e["band"]
	approx(float(band["aggression"]), 0.94, "band aggression pin")
	approx(float(band["fear"]), 1.259, "band fear pin")
	# legs-0 player: 24 * 0.6 = 14.4
	var m0 := _mk_sim()
	var e0: Dictionary = m0["sim"].spawn_ent(null, 10.0, 20.0)
	approx(float(e0["stats"]["speed"]), 14.399999999999999, "wild speed legs-0 gate soak")
	# peaceful: damage *0.7, maxHp *0.8, speed *0.9
	var mp := _mk_sim(SEED, {}, "peaceful")
	var ep: Dictionary = mp["sim"].spawn_ent(null, 10.0, 20.0)
	approx(float(ep["hp"]), 56.0, "peaceful maxHp *0.8")
	approx(float(ep["stats"]["speed"]), 12.959999999999999, "peaceful speed *0.9")
	approx(float(ep["stats"]["damage"]), 9.1, "peaceful damage *0.7")
	# spawning from a real species rides its genome
	var ms := _mk_sim()
	var sp: Dictionary = ms["ctx"].eco.species[0]
	var es: Dictionary = ms["sim"].spawn_ent(sp, 0.0, 0.0)
	eq(String(es["speciesId"]), String(sp["id"]), "species spawn id")
	approx(float(es["stats"]["max_hp"]),
			float(StatsLib.compute_creature_stats(sp["genome"])["max_hp"]),
			"species spawn stats from its genome")


# ---- maintainPopulation ------------------------------------------------------------

func test_maintain_population_pins() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.maintain_population()
	eq(sim.ents.size(), 3, "first maintain spawn pin (3 species pass the 0.35 roll)")
	var e0: Dictionary = sim.ents[0]
	approx(float(e0["x"]), 396.0901021472938, "maintain x pin (nest + cos(a)*range(30,220))")
	approx(float(e0["z"]), 20.488312958283608, "maintain z pin (nest.z + sin(a)*120 clamped)")
	eq(String(e0["speciesId"]), "sp2_6nzebt", "maintain species order pin")
	approx(float(e0["seed"]), 14.872990571893752, "maintain spawn seed pin")
	eq(int(e0["facing"]), 1, "maintain facing pin")
	approx(float(e0["gait"]), 4.662968264892697, "maintain gait pin")
	var e1: Dictionary = sim.ents[1]
	approx(float(e1["x"]), -2323.758105561267, "maintain ent1 x pin")
	eq(String(e1["speciesId"]), "sp4_baf1af", "maintain ent1 species pin")
	var e2: Dictionary = sim.ents[2]
	approx(float(e2["x"]), 1545.1994764142046, "maintain ent2 x pin")
	eq(String(e2["speciesId"]), "sp5_3tj8nv", "maintain ent2 species pin")
	# second call: one more species clears its roll
	sim.maintain_population()
	eq(sim.ents.size(), 4, "second maintain adds one (pop target min(10, round(pop*0.5)))")
	# despawn 2200, pack exempt
	var far: Dictionary = sim.spawn_ent(null, sim.px + 5000.0, 0.0)
	far["pack"] = true
	var wildFar: Dictionary = sim.spawn_ent(null, sim.px + 5000.0, 10.0)
	wildFar["pack"] = false
	sim.maintain_population()
	var keptFar := false
	var keptWild := false
	for e in sim.ents:
		if e["eid"] == far["eid"]:
			keptFar = true
		if e["eid"] == wildFar["eid"]:
			keptWild = true
	ok(keptFar, "pack ent exempt from the 2200 despawn")
	ok(not keptWild, "wild ent beyond 2200 despawns")


# ---- update_player: movement / jump / dust ----------------------------------------

func test_movement_wasd_and_mouse() -> void:
	var m := _mk_sim(SEED, {"legs": 4})
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	# WASD: KeyD moves +x, facing 1
	for i in 60:
		sim.update(DT, _inp({"keys_held": ["KeyD"]}))
	ok(float(sim.px) > -2400.0 + 30.0, "KeyD moved +x (60 ticks)")
	eq(int(sim.facing), 1, "KeyD faces right")
	approx(float(sim.pz), 20.0, "KeyD left z alone")
	# KeyA moves -x, facing -1
	for i in 120:
		sim.update(DT, _inp({"keys_held": ["KeyA"]}))
	eq(int(sim.facing), -1, "KeyA faces left")
	ok(float(sim.px) < -2400.0 - 10.0, "KeyA moved -x")
	# KeyW/KeyS move z (dz unweighted normalization, physics *0.8)
	for i in 60:
		sim.update(DT, _inp({"keys_held": ["KeyS"]}))
	ok(float(sim.pz) > 20.0, "KeyS moved +z")
	for i in 120:
		sim.update(DT, _inp({"keys_held": ["KeyW"]}))
	ok(float(sim.pz) < 20.0, "KeyW moved -z")
	# mouse pseudo-depth: tz = clamp(wy / Z_TO_Y, Z_MIN, Z_MAX)
	var pz0: float = float(sim.pz)
	var px0: float = float(sim.px)
	for i in 90:
		sim.update(DT, _inp({"down": true, "wx": px0 + 200.0,
				"wy": (pz0 + 100.0) * Z_TO_Y}))
	ok(float(sim.pz) > pz0 + 20.0, "mouse depth target pulls z toward wy/Z_TO_Y")
	ok(float(sim.px) > px0 + 20.0, "mouse wx pulls x")
	# dead zones: |dx|, |dz| < 10 -> no input movement (residual v zeroed first)
	sim.pvx = 0.0
	sim.pvz = 0.0
	var mx0: float = float(sim.px)
	var mz0: float = float(sim.pz)
	for i in 10:
		sim.update(DT, _inp({"down": true, "wx": mx0 + 5.0,
				"wy": mz0 * Z_TO_Y + 5.0}))
	approx(float(sim.px), mx0, "mouse dead zone 10 on x")
	approx(float(sim.pz), mz0, "mouse dead zone 10 on z")
	# gait += dt * (3 + speed01 * 9) — advances even at rest (base 3)
	var gait0: float = float(sim.gait)
	sim.update(DT, _inp({}))
	ok(float(sim.gait) > gait0 + 3.0 * DT * 0.9, "gait advances with the base 3 rate")


func test_movement_clamps() -> void:
	var m := _mk_sim(SEED, {"legs": 4})
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	sim.px = WORLD_HALF + 199.0
	for i in 40:
		sim.update(DT, _inp({"keys_held": ["KeyD"]}))
	approx(float(sim.px), WORLD_HALF + 200.0, "x clamps at ±(WORLD_HALF+200)")
	sim.px = -WORLD_HALF - 199.0
	for i in 40:
		sim.update(DT, _inp({"keys_held": ["KeyA"]}))
	approx(float(sim.px), -WORLD_HALF - 200.0, "x clamps at -(WORLD_HALF+200)")
	sim.pz = Z_MAX - 0.5
	for i in 40:
		sim.update(DT, _inp({"keys_held": ["KeyS"]}))
	approx(float(sim.pz), Z_MAX, "z clamps at Z_MAX 240")
	sim.pz = Z_MIN + 0.5
	for i in 40:
		sim.update(DT, _inp({"keys_held": ["KeyW"]}))
	approx(float(sim.pz), Z_MIN, "z clamps at Z_MIN -200")


func test_jump_and_wing_hop() -> void:
	var m := _mk_sim(SEED)
	var sim: Variant = m["sim"]
	sim.update(DT, _inp({"keys_pressed": ["Space"]}))
	ok(float(sim.py) > 0.0, "jump leaves the ground")
	ok(float(sim.pvy) > 300.0, "pvy starts 320 minus one gravity step")
	approx(float(sim.jumpCd), 1.2 - DT, "jumpCd 1.2 (decayed one tick)")
	ok(_heard(m["rec"], "dash"), "jump plays dash (0.4)")
	# gravity lands the jump
	for i in 120:
		sim.update(DT, _inp({}))
	approx(float(sim.py), 0.0, "gravity returns py to 0")
	approx(float(sim.pvy), 0.0, "pvy zeroed on landing")
	# jumpCd gates re-jumps (checked mid-air: gravity only, no re-impulse)
	sim.py = 10.0
	sim.pvy = 20.0
	sim.jumpCd = 1.0
	sim.update(DT, _inp({"keys_pressed": ["Space"]}))
	approx(float(sim.pvy), 20.0 - 950.0 * DT, "jumpCd blocks an immediate re-jump")
	# wings raise the impulse + fire the fx burst (TS quirk anchor (px, py))
	var mw := _mk_sim(SEED, {"wings": 2})
	var simw: Variant = mw["sim"]
	simw.update(DT, _inp({"keys_pressed": ["Space"]}))
	var expectPvy := (320.0 + 2.0 * 60.0) - 950.0 * DT
	approx(float(simw.pvy), expectPvy, "pvy = 320 + wings*60 (decayed one step)")
	var burst: Variant = null
	for b in mw["rec"]["bursts"]:
		if int(b[2]) == 8:
			burst = b
	ok(burst != null, "wings > 0 fires an 8-particle burst")
	if burst != null:
		approx(float(burst[0]), float(simw.px), "wing burst anchors at px")


func test_running_dust() -> void:
	var m := _mk_sim(SEED, {"legs": 4})
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	for i in 120:
		sim.update(DT, _inp({"keys_held": ["KeyD"]}))
	var dust := 0
	for s in m["rec"]["spawns"]:
		if String(s["kind"]) == "smoke":
			dust += 1
	ok(dust > 0, "running kicks dust (speed01 > 0.5, chance dt*10)")
	if dust > 0:
		var first: Dictionary = m["rec"]["spawns"][0]
		ok(String(first["color"]).begins_with("rgba(180,160,130"), "dust color")
		ok(float(first["size"]) >= 2.0 and float(first["size"]) <= 4.0, "dust size 2..4")


# ---- interactions: bite / their bite / charm ward ---------------------------------

func test_player_bite_and_kill_path() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px), float(sim.pz))
	sim.update(DT, _inp({}))
	# bite: dmg = 13 * (1 - min(0.6, 0.06)) = 12.22; their bite gated by invuln 2
	approx(float(e["hp"]), 70.0 - 13.0 * (1.0 - minf(0.6, 0.06)),
			"bite dmg = damage * (1 - min(0.6, defense))")
	eq(String(e["mood"]), "afraid", "bitten ent is afraid")
	# ent-side anim/cooldown decay lives in update_ents (Task 3 stub) — the
	# value sits at its set state after the tick
	approx(float(e["hurtT"]), 0.7, "hurtT 0.7")
	approx(float(ctx.karma), -0.008, "bite karma -0.008")
	approx(float(sim.biteCd), 0.6 - DT, "biteCd 0.6")
	approx(float(sim.attackT), 1.0 - DT * 2.2, "attackT anim timer 1")
	# cd gates the second swing
	var hpAfter: float = float(e["hp"])
	sim.update(DT, _inp({}))
	approx(float(e["hp"]), hpAfter, "biteCd 0.6 gates a second bite")
	# kill -> CORPSE not removal (corpseT 12, hp 0)
	e["hp"] = 1.0
	sim.biteCd = 0.0
	sim.update(DT, _inp({}))
	eq(bool(e.has("corpseT")), true, "killed ent becomes a corpse")
	approx(float(e["corpseT"]), 12.0, "corpseT 12")
	approx(float(e["hp"]), 0.0, "corpse hp 0")
	eq(sim.ents.size(), 1, "corpse is NOT removed")
	ok(sim.ents.size() > 0 and sim.ents[0].has("corpseT"), "corpse still in ents")
	# notify_kill on a real species pays DNA (meal pricing, pop < 6 -> 0.6x)
	var mk := _mk_sim()
	var simk: Variant = mk["sim"]
	var ctxk: Variant = mk["ctx"]
	var sp: Dictionary = ctxk.eco.species[0]
	var ek: Dictionary = simk.spawn_ent(sp, float(simk.px), float(simk.pz))
	ek["hp"] = 1.0
	var popBefore: float = float(sp["pop"])
	simk.update(DT, _inp({}))
	approx(float(sp["pop"]), popBefore - 1.0, "notify_kill drops pop by 1")
	eq(int(ctxk.dna), 40 + 9, "kill DNA pin (meal 0.99, sc 0.6 -> 9)")
	eq(int(ctxk.world_stats["kills"]), 1, "bumpKill world-story counter")
	ok(_heard(mk["rec"], "die"), "kill plays die (0.6)")
	var floatTexts: Array = []
	for f in mk["rec"]["floats"]:
		floatTexts.append(String(f[2]))
	ok(floatTexts.has("+9"), "floatWorld '+9' paid")
	# pack loyalty: pack members turn happy when you hunt
	var pack_e: Dictionary = simk.spawn_ent(null, 0.0, 0.0, {}, {"pack": true})
	pack_e["mood"] = "idle"
	var ek2: Dictionary = simk.spawn_ent(ctxk.eco.species[1], 500.0, 0.0)
	ek2["hp"] = 1.0
	simk.biteCd = 0.0
	simk.attackT = 0.0
	# move pack ent next to a fresh wild ent and bite that one
	simk.px = float(ek2["x"])
	simk.pz = float(ek2["z"])
	pack_e["x"] = simk.px + 30.0
	simk.update(DT, _inp({}))
	eq(String(pack_e["mood"]), "happy", "pack members gain loyalty on a hunt")
	# corpse_tide combo: the kill leaves corpses on the eco ledger
	var worldTide: Dictionary = {"seed": SEED, "traits": [], "comboFired": {"corpse_tide": true}}
	var mt := _mk_sim(SEED, {}, "normal", worldTide)
	var simt: Variant = mt["sim"]
	var et: Dictionary = simt.spawn_ent(mt["ctx"].eco.species[0], float(simt.px), float(simt.pz))
	et["hp"] = 1.0
	simt.update(DT, _inp({}))
	ok(float(mt["ctx"].eco.corpses) >= 1.0, "corpse_tide dropCorpse joins the ledger")
	var tideBorn := false
	for s in mt["ctx"].eco.species:
		if bool(s.get("tideBorn", false)):
			tideBorn = true
	ok(tideBorn, "tide species founded/kept")


func test_kin_grudge_warn_once() -> void:
	var worldKin: Dictionary = {"seed": SEED,
			"traits": [{"effects": [{"kind": "flag", "key": "kin_grudge"}]}]}
	var m := _mk_sim(SEED, {}, "normal", worldKin)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# designate_kin_tag tagged the first non-carnivore line (sp0, herbivore)
	var sp: Dictionary = ctx.eco.species[0]
	eq(bool(sp.get("kin_tag", false)), true, "kin tag designated on the grazer line")
	var e: Dictionary = sim.spawn_ent(sp, float(sim.px), float(sim.pz))
	e["hp"] = 1.0
	sim.update(DT, _inp({}))
	approx(float(sp["grudge"]), 1.0, "grudge += 1 on the kill")
	var kinToasts := 0
	for t in m["rec"]["toasts"]:
		if String(t[0]) == "the kin are watching":
			kinToasts += 1
	eq(kinToasts, 1, "warn-once: exactly one 'the kin are watching'")
	# second kill: no second warning, grudge 2
	var e2: Dictionary = sim.spawn_ent(sp, float(sim.px), float(sim.pz))
	e2["hp"] = 1.0
	sim.biteCd = 0.0
	sim.update(DT, _inp({}))
	approx(float(sp["grudge"]), 2.0, "grudge 2 after the second kill")
	kinToasts = 0
	for t in m["rec"]["toasts"]:
		if String(t[0]) == "the kin are watching":
			kinToasts += 1
	eq(kinToasts, 1, "still exactly one warning")


func test_their_bite_and_bite_hint() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	sim.invuln = 0.0  # the constructor grace would gate their bite
	var e: Dictionary = sim.spawn_ent(null, float(sim.px), float(sim.pz))
	sim.update(DT, _inp({}))
	var expectDmg: float = 13.0 * (1.0 - 0.06) * 0.85
	approx(float(sim.php), 70.0 - expectDmg,
			"their bite: damage * (1 - defense) * 0.85")
	approx(float(e["biteCd"]), 0.9, "their biteCd 0.9 (decay is Task 3)")
	eq(String(e["mood"]), "angry", "biter is angry")
	approx(float(e["attack"]), 1.0, "attack anim 1 (decay is Task 3)")
	approx(float(sim.hurtT), 1.0 - DT * 3.0, "player hurtT 1")
	var hintCount := 0
	for t in m["rec"]["toasts"]:
		if String(t[0]).begins_with("Hold F near a creature to CHARM"):
			hintCount += 1
	eq(hintCount, 1, "bite hint shown once")
	# invuln gates their bite (respawn grace)
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	sim2.spawn_ent(null, float(sim2.px), float(sim2.pz))
	sim2.update(DT, _inp({}))
	approx(float(sim2.php), 70.0, "invuln 2 gates their bite at spawn")
	# pack members never bite
	var m3 := _mk_sim()
	var sim3: Variant = m3["sim"]
	sim3.invuln = 0.0
	sim3.spawn_ent(null, float(sim3.px), float(sim3.pz), {}, {"pack": true})
	sim3.update(DT, _inp({}))
	approx(float(sim3.php), 70.0, "pack allies do not bite")


func test_charm_stub_structure_and_ward() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var e: Dictionary = sim.spawn_ent(null, float(sim.px), float(sim.pz))
	# try_charm/update_charm are Task 4 stubs: F-hold runs the call site
	# without the minigame, but the F tolerance in update_player is TS-true
	for i in 60:
		sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	eq(bool(sim.charmActive), false, "charm minigame not active (Task 4 stub)")
	eq(bool(sim.charmTarget == null), true, "no charm target")
	approx(float(e["hp"]), 70.0, "F hold wards off the player bite")
	approx(float(sim.php), 70.0, "F hold wards off their bite (invuln aside)")
	approx(float(e["biteCd"]), 0.0, "no their-bite attempts while charmed")
	# the Task 4 hook-up: with F held the flag rides into update_charm (stub)
	sim.charmActive = true
	sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	eq(bool(sim.charmActive), true, "update_charm stub keeps the flag (Task 4 fills)")
	# F released -> the TS reset branch clears the minigame
	sim.update(DT, _inp({}))
	eq(bool(sim.charmActive), false, "F release resets charmActive (TS:490-492)")
	eq(bool(sim.charmTarget == null), true, "F release resets charmTarget")


# ---- world objects: bushes / bones / hazards ---------------------------------------

func test_bush_eating_and_regrow() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_park_world_objects(m)
	var b: Dictionary = sim.bushes[0]
	b["x"] = float(sim.px)
	b["z"] = float(sim.pz)
	b["food"] = 4.0
	b["regrow"] = 0.0
	sim.php = 40.0
	# wx/wy ride at the player so the held mouse dead-zones out (down alone
	# with a far target would walk the player off the bush)
	var eat_inp: Dictionary = _inp({"down": true, "wx": float(sim.px),
			"wy": float(sim.pz) * Z_TO_Y})
	for i in 130:
		eat_inp["wx"] = float(sim.px)
		eat_inp["wy"] = float(sim.pz) * Z_TO_Y
		sim.update(DT, eat_inp)
	ok(float(b["food"]) <= 0.0, "bush depleted by hold-eating")
	eq(int(ctx.dna), 44, "DNA 1.2 * took (4.0 food -> +4 whole)")
	approx(float(sim.php), 40.0 + 24.0, "heal 6 * took")
	approx(float(ctx.karma), 0.04, "karma +dt*0.02 per grazing tick (~120 ticks)", 1e-3)
	ok(float(b["regrow"]) > 24.0 and float(b["regrow"]) < 25.0, "regrow armed at 25 (decaying)")
	ok(float(sim.eatT) > 0.0, "eatT set while eating")
	# F-hold also eats
	var m2 := _mk_sim()
	var b2: Dictionary = m2["sim"].bushes[0]
	b2["x"] = float(m2["sim"].px)
	b2["z"] = float(m2["sim"].pz)
	b2["food"] = 2.0
	for i in 5:
		m2["sim"].update(DT, _inp({"keys_held": ["KeyF"]}))
	ok(float(b2["food"]) < 2.0, "F-hold eats bushes too")
	# dead player does not eat
	var m3 := _mk_sim()
	var b3: Dictionary = m3["sim"].bushes[0]
	b3["x"] = float(m3["sim"].px)
	b3["z"] = float(m3["sim"].pz)
	b3["food"] = 3.0
	m3["sim"].php = 0.0
	m3["sim"].update(DT, _inp({"down": true}))
	approx(float(b3["food"]), 3.0, "no posthumous bush eating")
	# regrow loop: 25s later the bush re-arms 2..5 food
	for i in 1600:
		sim.update(DT, _inp({}))
	approx(float(b["regrow"]), 0.0, "regrow counted down to 0")
	ok(float(b["food"]) >= 2.0 and float(b["food"]) <= 5.0, "regrow re-rolls food 2..5")


func test_bone_pickup() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_park_world_objects(m)
	var bo: Dictionary = sim.bones[1]
	bo["x"] = float(sim.px)
	bo["z"] = float(sim.pz)
	sim.update(DT, _inp({}))
	eq(int(ctx.dna), 40 + 45, "bone pays 45 DNA")
	eq(bool(bo["taken"]), true, "bone taken")
	eq(sim.bones.size(), 7, "taken bones filtered out of the list")
	ok(int(sim.tut["actioned"]) >= 1, "tut.actioned++")
	var found := false
	for t in m["rec"]["toasts"]:
		if String(t[0]) == "Ancient bones: +45 DNA":
			found = true
	ok(found, "bone toast")
	var floatTexts: Array = []
	for f in m["rec"]["floats"]:
		floatTexts.append(String(f[2]))
	ok(floatTexts.has("+45 DNA 🦴"), "floatWorld '+45 DNA 🦴'")
	ok(_heard(m["rec"], "levelup"), "bone plays levelup")
	# meteor: 120 DNA + chaos 0.05
	var bm: Dictionary = sim.bones[0]
	bm["x"] = float(sim.px)
	bm["z"] = float(sim.pz)
	sim.update(DT, _inp({}))
	eq(int(ctx.dna), 40 + 45 + 120, "meteor pays 120 DNA")
	approx(float(ctx.chaos), 0.15 + 0.05, "meteor chaos +0.05")
	var meteorToast := false
	for t in m["rec"]["toasts"]:
		if String(t[0]) == "Meteor marrow! Rare genes course through you.":
			meteorToast = true
	ok(meteorToast, "meteor toast")
	# the 60-bone list cap: only the pickup bone is in range (the rest parked
	# beyond the 34px radius so the single-tick multi-pickup can't bite)
	sim.bones.clear()
	for i in 65:
		sim.bones.append({"x": 99999.0 + float(i) * 100.0, "z": 0.0, "taken": false, "kind": "bone"})
	sim.bones.append({"x": float(sim.px), "z": float(sim.pz), "taken": false, "kind": "bone"})
	sim.update(DT, _inp({}))
	eq(sim.bones.size(), 60, "bones list capped at 60 (splice from the front)")


func test_lava_hazard_player() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	sim.add_hazard(float(sim.px), float(sim.pz), 50.0, 10.0, 14.0, "lava")
	approx(float(sim.php), 70.0, "hazard added")
	# invuln gates hazard damage
	sim.update(DT, _inp({}))
	approx(float(sim.php), 70.0, "invuln gates hazard dps")
	sim.invuln = 0.0
	sim.update(DT, _inp({}))
	approx(float(sim.php), 70.0 - 10.0 * DT, "lava dps ticks the player")
	ok(float(sim.hurtT) >= 0.4 - DT * 3.0, "hurtT 0.4 floor")
	# ttl expiry removes the hazard
	for i in 1000:
		sim.update(DT, _inp({}))
	eq(sim.hazards.size(), 0, "hazard ttl expiry removes it")
	# airborne player is immune
	sim.add_hazard(float(sim.px), float(sim.pz), 50.0, 10.0, 14.0, "lava")
	sim.py = 40.0
	var hp0: float = float(sim.php)
	sim.update(DT, _inp({}))
	approx(float(sim.php), hp0, "airborne player immune to ground hazards")


# ---- eco tick / spawn timer --------------------------------------------------------

func test_eco_tick_and_extinction() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# mods refresh right before each batch (the world-trait wire)
	for i in 130:
		sim.update(DT, _inp({}))
	eq(ctx.eco.mods, WorldGenome.eco_mods_from_world(ctx.world), "eco.mods refreshed per batch")
	ok(float(ctx.eco.flora) != 60.0, "eco.tick ran (flora moved off 60)")
	# extinction ceremony: pop < 0.4 after a batch
	var victim: Dictionary = ctx.eco.species[2]
	victim["pop"] = 0.35
	var nestCountBefore: int = sim.nests.size()
	var chaosBefore: float = float(ctx.chaos)
	sim.ecoTimer = 1.9  # land a batch within a few ticks (the earlier loop consumed one)
	for i in 45:
		sim.update(DT, _inp({}))
	eq(bool(victim["extinct"]), true, "pop < 0.4 goes extinct in a batch")
	eq(int(ctx.world_stats["extinctions"]), 1, "bumpExtinction")
	approx(float(ctx.chaos), chaosBefore + 0.04, "extinction chaos +0.04 (creature rate)")
	eq(sim.nests.size(), nestCountBefore - 1, "extinct species nest removed")
	var banner: Variant = null
	for b in m["rec"]["banners"]:
		if String(b["title"]).ends_with(" is extinct"):
			banner = b
	ok(banner != null, "extinction banner")
	if banner != null:
		eq(String(banner["subtitle"]), "the island falls silent…", "banner subtitle")


func test_spawn_timer_check_and_eco_window() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	# 1.5 s -> maintainPopulation fires once (91 ticks: the accumulated
	# 1.5-compare is float-sensitive at exactly tick 90); no other rng
	# consumers in the window, so the spawn pins match the direct call
	for i in 91:
		sim.update(DT, _inp({}))
	eq(sim.ents.size(), 3, "spawnTimerCheck 1.5s -> one maintain pass")
	approx(float(sim.ents[0]["x"]), 396.0901021472938, "same stream position as the direct call")
	# barrenT accrues while nothing wild is alive (php > 0)
	ok(float(sim.barrenT) > 1.0, "barrenT accrues on a wild-less island")


# ---- death / respawn ----------------------------------------------------------------

func test_death_and_respawn() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var pack_e: Dictionary = sim.spawn_ent(null, float(sim.px) + 100.0, float(sim.pz), {}, {"pack": true})
	var wild_e: Dictionary = sim.spawn_ent(null, float(sim.px) + 50.0, float(sim.pz))
	# an ent that will sit within 600 of the respawn point (-1600, 20)
	var close_e: Dictionary = sim.spawn_ent(null, -1500.0, 20.0)
	sim.php = 0.0
	sim.update(DT, _inp({}))
	# first frame: the ceremony
	eq(m["rec"]["events"], [["playerDeath", "creature"]], "playerDeath storyteller signal")
	ok(_heard(m["rec"], "die"), "death plays die (0.9)")
	var shook := false
	for s in m["rec"]["shakes"]:
		if absf(float(s[0]) - 10.0) < 1e-6:
			shook = true
	ok(shook, "cam shake 10")
	approx(float(ctx.chaos), 0.15 + 0.03, "death chaos +0.03")
	eq(int(ctx.dna), 40 - 5, "DNA -12% (round(40*0.12) = 5)")
	var lostToast := false
	for t in m["rec"]["toasts"]:
		if String(t[0]) == "You died — lost 5 DNA":
			lostToast = true
	ok(lostToast, "death toast")
	eq(bool(pack_e["pack"]), false, "pack scatters")
	eq(String(pack_e["mood"]), "afraid", "scattered ent afraid")
	var scatterToast := false
	for t in m["rec"]["toasts"]:
		if String(t[0]) == "The pack scattered (1 fled)":
			scatterToast = true
	ok(scatterToast, "pack scatter toast with the count")
	# mid-fade: no respawn yet
	sim.php = 0.0
	for i in 100:
		sim.update(DT, _inp({}))
	ok(float(sim.deathFade) > 0.0, "death fade running")
	# past 1.8 s: respawn at the action — catch the respawn tick (the grace
	# decays on later ticks)
	var respawned := false
	for i in 40:
		sim.update(DT, _inp({}))
		if float(sim.deathFade) == 0.0 and float(sim.php) > 0.0:
			respawned = true
			approx(float(sim.invuln), 3.0, "respawn grace 3")
			break
	ok(respawned, "respawned after the fade")
	approx(float(sim.php), sim.pmaxHp, "respawned at full hp")
	approx(float(sim.px), -1600.0, "respawn x -1600 (closer to the action)")
	approx(float(sim.pz), 20.0, "respawn z 20")
	# threats within 600 cleared, pack exempt
	var closeGone := true
	for e in sim.ents:
		if e["eid"] == close_e["eid"]:
			closeGone = false
	ok(closeGone, "respawn cleared the threat within 600 of (-1600, 20)")


# ---- dead-island escape ---------------------------------------------------------------

func test_barren_reseed() -> void:
	# With a living legged roster, maintainPopulation keeps repopulating from
	# the nests — the island self-heals and barrenT never crosses the gate.
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	sim.ents.clear()  # total wild collapse
	for i in 3800:
		sim.update(DT, _inp({}))
	ok(float(sim.barrenT) < 60.0, "self-healing island never trips the 60s escape")
	eq(ctx.eco.species.size(), 8, "no duplicate stacking when fauna lives")
	ok(sim.ents.size() > 0, "maintain repopulated the wild")
	var toasts := 0
	for t in m["rec"]["toasts"]:
		if String(t[0]) == "Life finds a way — new creatures migrate in from beyond the ridge.":
			toasts += 1
	eq(toasts, 0, "no migrate toast while the roster breathes")
	# a truly dead island (every line extinct -> maintain has nothing to
	# respawn from) trips the escape: reseed + nest re-arm + toast
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var ctx2: Variant = m2["ctx"]
	for sp in ctx2.eco.species:
		sp["extinct"] = true
	sim2.ents.clear()
	sim2.nests[0]["members"] = 2  # the escape re-arms every wild nest
	var before2: int = ctx2.eco.species.size()
	for i in 3800:
		sim2.update(DT, _inp({}))
	# 6 archetypes + titan + swarm at this seed
	eq(ctx2.eco.species.size(), before2 + 8, "dead island reseeds the land roster")
	eq(int(sim2.nests[0]["members"]), 4, "escape re-arms nest members at 4")
	# (the reseed is only reachable through the barrenT reset; the fresh wild
	# spawns it enables then zero barrenT again on the next drift window)
	var found := false
	for t in m2["rec"]["toasts"]:
		if String(t[0]) == "Life finds a way — new creatures migrate in from beyond the ridge.":
			found = true
	ok(found, "migrate toast on the dead island")


# ---- day / night ------------------------------------------------------------------------

func test_day_night_cycle() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	ok(not sim.is_night(), "morning is not night")
	sim.dayPhase = 0.55
	ok(not sim.is_night(), "0.55 boundary exclusive")
	sim.dayPhase = 0.56
	ok(sim.is_night(), "0.56 is night")
	sim.dayPhase = 0.94
	ok(sim.is_night(), "0.94 is night")
	sim.dayPhase = 0.95
	ok(not sim.is_night(), "0.95 boundary exclusive")
	# full cycle 180 s
	sim.dayPhase = 0.0
	sim.update(DT, _inp({}))
	approx(float(sim.dayPhase), DT / 180.0, "dayPhase advances dt/180")
	sim.dayPhase = 0.999
	for i in 30:
		sim.update(DT, _inp({}))
	ok(float(sim.dayPhase) < 0.1, "dayPhase wraps at 1")


# ---- onEnter / persist / stats ------------------------------------------------------------

func test_on_enter_ambush_calming() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var wild: Dictionary = sim.spawn_ent(null, float(sim.px) + 100.0, float(sim.pz))
	wild["mood"] = "angry"
	var pack_e: Dictionary = sim.spawn_ent(null, float(sim.px) + 50.0, float(sim.pz), {}, {"pack": true})
	pack_e["mood"] = "angry"
	var corpse: Dictionary = sim.spawn_ent(null, float(sim.px) + 80.0, float(sim.pz))
	corpse["corpseT"] = 5.0
	corpse["mood"] = "angry"
	sim.php = 30.0
	sim.on_enter()
	approx(float(sim.php), sim.pmaxHp, "arrivals arrive healthy")
	approx(float(sim.invuln), 3.0, "reload grace 3")
	approx(float(sim.deathFade), 0.0, "deathFade reset")
	eq(String(wild["mood"]), "idle", "ambush calming: wild ent mood idle")
	approx(float(wild["packCd"]), 10.0, "ambush calming: packCd 10")
	eq(String(pack_e["mood"]), "angry", "pack ent untouched")
	eq(String(corpse["mood"]), "angry", "corpse skipped by the calming")
	eq(int(sim.packLimit), 2, "packLimit recomputed")


func test_on_enter_name_card_and_kin_nest() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	sim.on_enter()
	# default genome self-names Squish -> Squishpuff (hue 120, size 1)
	eq(String(ctx.player_name), "Squishpuff", "arrival self-name")
	var banner: Variant = null
	for b in m["rec"]["banners"]:
		if String(b["title"]).begins_with("THE PACK WILL CALL YOU"):
			banner = b
	ok(banner != null, "arrival banner")
	if banner != null:
		eq(String(banner["title"]), "THE PACK WILL CALL YOU SQUISHPUFF", "banner title pin")
		eq(String(banner["kind"]), "stage", "banner kind stage")
	# kin nest at the spawn point
	var kin: Variant = null
	for n in sim.nests:
		if String(n["speciesId"]) == "player":
			kin = n
	ok(kin != null, "player kin nest exists")
	if kin != null:
		approx(float(kin["x"]), -2400.0, "kin nest x")
		approx(float(kin["z"]), 20.0, "kin nest z")
		eq(int(kin["members"]), 0, "kin nest members 0")
	# idempotent: a second enter does not duplicate it
	sim.on_enter()
	var kinCount := 0
	for n in sim.nests:
		if String(n["speciesId"]) == "player":
			kinCount += 1
	eq(kinCount, 1, "kin nest not duplicated")


func test_on_enter_pack_restore() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var genome: Dictionary = GenomeLib.default_genome()
	genome["legs"] = 2
	var wire: Array = [{"genome": genome, "baby": false}]
	ctx.flags["packGenomes"] = JSON.stringify(wire)
	sim.on_enter()
	eq(sim.ents.size(), 1, "pack restored from the flag")
	var e: Dictionary = sim.ents[0]
	eq(bool(e["pack"]), true, "restored ent is pack")
	eq(String(e["mood"]), "happy", "restored ent happy")
	eq(String(e["speciesId"]), "mutant", "restored via spawnEnt(null) -> mutant")
	eq(int(e["genome"]["legs"]), 2, "restored genome legs 2")
	# restore draws: range(-60,60) then range(-40,40) — stream-order sanity via
	# a second identical run producing the same position
	var m2 := _mk_sim()
	var ctx2: Variant = m2["ctx"]
	ctx2.flags["packGenomes"] = ctx.flags["packGenomes"]
	m2["sim"].on_enter()
	approx(float(m2["sim"].ents[0]["x"]), float(e["x"]), "restore spawn position deterministic")
	# corrupt flag: start alone, no crash
	var m3 := _mk_sim()
	m3["ctx"].flags["packGenomes"] = "{not json"
	m3["sim"].on_enter()
	eq(m3["sim"].ents.size(), 0, "corrupt pack flag starts alone")
	# packLimit caps the restore
	var m4 := _mk_sim(SEED, {"arms": 4})
	var many: Array = []
	for i in 7:
		many.append({"genome": GenomeLib.default_genome(), "baby": false})
	m4["ctx"].flags["packGenomes"] = JSON.stringify(many)
	m4["sim"].on_enter()
	eq(m4["sim"].ents.size(), 4, "restore capped at packLimit")


func test_ensure_deck_c1() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var chaosBefore: Variant = sim.chaos
	eq(bool(sim.ensure_deck(SEED)), false, "same seed -> no rebuild")
	ok(sim.chaos == chaosBefore, "scheduler object kept")
	eq(bool(sim.ensure_deck(SEED + 1)), true, "different seed -> rebuild")
	ok(sim.chaos != chaosBefore, "scheduler rebuilt (new branch draw, TS onEnter)")
	eq(int(sim.deckSeed), SEED + 1, "deckSeed updated")


func test_persist_state_and_on_exit() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	sim.debug_spawn_pack(2)
	eq(sim.ents.size(), 2, "debugSpawnPack spawns 2")
	approx(float(sim.ents[0]["x"]), float(sim.px) + 45.0, "pack spacing +45")
	approx(float(sim.ents[1]["x"]), float(sim.px) + 90.0, "pack spacing +90")
	eq(bool(sim.ents[0]["pack"]), true, "debug pack ent is pack")
	# a corpse among the pack is excluded from the snapshot
	sim.ents[1]["corpseT"] = 3.0
	sim.persist_state()
	var raw: String = String(ctx.flags["packGenomes"])
	var parsed: Variant = JSON.parse_string(raw)
	ok(parsed is Array, "packGenomes is a JSON array")
	if parsed is Array:
		eq(parsed.size(), 1, "corpse excluded from the pack snapshot")
		var item: Dictionary = parsed[0]
		ok(item.has("genome"), "item carries genome")
		eq(bool(item["baby"]), false, "baby false verbatim (TS persistState)")
		eq(int(item["genome"]["legs"]), 0, "genome rides verbatim")
	# on_exit hands the eco back + persists
	sim.on_exit()
	ok(ctx.eco == sim.eco, "on_exit hands the eco to ctx")
	ok(ctx.flags.has("packGenomes"), "on_exit persisted")


func test_on_stats_changed() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	sim.php = 200.0
	ctx.genome["brain"] = 3
	ctx.genome["legs"] = 4
	sim.on_stats_changed()
	approx(float(sim.pmaxHp), 40.0 + 30.0 + 0.0 + 0.0, "pmaxHp refreshed (legs/brain don't move maxHp)")
	approx(float(sim.php), sim.pmaxHp, "php clamped to the new max")
	eq(int(sim.packLimit), 3, "packLimit refreshed (brain 3)")


# ---- chaos wiring / dominance -------------------------------------------------------

func test_dominance_share() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# no ents: share = 1 (all mine)
	approx(sim.dominance_share(), 1.0, "empty region -> share 1")
	# one wild size-2 ent nearby: mine 1, wild 4 -> 1/5 (genome overrides —
	# sp=null ents alias ctx.genome by reference, TS-true; mutating it here
	# would poison ctx.genome.size)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 100.0, 0.0,
			{"size": 2.0, "diet": "herbivore", "hue": 0})
	approx(sim.dominance_share(), 1.0 / 5.0, "share = mine / (mine + wild)")
	# beyond 900px: excluded
	e["x"] = float(sim.px) + 901.0
	approx(sim.dominance_share(), 1.0, "regional: beyond 900px excluded")
	e["x"] = float(sim.px) + 100.0
	# pack ents count toward MINE, corpses count toward neither
	var p: Dictionary = sim.spawn_ent(null, float(sim.px) + 50.0, 0.0,
			{"size": 1.0, "diet": "herbivore", "hue": 0}, {"pack": true})
	approx(sim.dominance_share(), 2.0 / 6.0, "pack adds to mine")
	e["corpseT"] = 1.0
	approx(sim.dominance_share(), 1.0, "corpse wild mass excluded")


func test_chaos_hooks_noop_and_gaps() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# default hooks (silent no-op) run the chaos update without events
	for i in 60:
		sim.update(DT, _inp({}))
	ok(float(sim.chaos._since_last) > 0.0, "chaos gap clock runs")
	# get_* hooks route into the chaos ctx (overloads of the computed values)
	var m2 := _mk_sim()
	var seen: Dictionary = {}
	var hooks2: Dictionary = {
		"get_gap_bias": func() -> float: return _hook_ret(seen, "gap", 1.0),
		"get_mood": func() -> String: return _hook_str(seen, "mood"),
		"get_warn_scale": func() -> float: return _hook_ret(seen, "warn", 1.0),
		"get_is_night": func() -> bool: return _hook_bool(seen, "night"),
		"get_dominance": func() -> float: return _hook_ret(seen, "dom", 0.5),
	}
	var ctx2: Variant = m2["ctx"]
	var rng2: Variant = ctx2.rng.branch()
	var sim3: Variant = CreatureSim.new(ctx2, rng2, hooks2)
	for i in 10:
		sim3.update(DT, _inp({}))
	eq(seen.size(), 5, "all get_* hooks consulted")


func _hook_ret(seen: Dictionary, key: String, v: float) -> float:
	seen[key] = true
	return v


func _hook_str(seen: Dictionary, key: String) -> String:
	seen[key] = true
	return "twist"


func _hook_bool(seen: Dictionary, key: String) -> bool:
	seen[key] = true
	return true


# ---- stage clock ----------------------------------------------------------------------

func test_after_timer() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var fired: Array = []
	sim.after(0.5, func(): fired.append("a"))
	sim.after(0.25, func(): fired.append("b"))
	for i in 20:
		sim.update(DT, _inp({}))
	eq(fired, ["b"], "0.25s timer fired first")
	for i in 20:
		sim.update(DT, _inp({}))
	eq(fired, ["b", "a"], "0.5s timer fired after")


# ---- headless determinism ---------------------------------------------------------------

func _script_input(tick: int, sim: Variant) -> Dictionary:
	var held: Array = []
	var pressed: Array = []
	var phase: int = (tick / 40) % 8
	match phase:
		0: held = ["KeyD"]
		1: held = ["KeyD", "KeyW"]
		2: held = ["KeyA"]
		3: held = ["KeyS"]
		4: held = ["ArrowRight", "ArrowUp"]
		5: held = ["KeyF"]
		6: held = []
		7: held = ["KeyW", "KeyA"]
	if tick % 97 == 0:
		pressed = ["Space"]
	var ang: float = float(tick) * 0.05
	var wy: float = clampf(float(sim.pz) + sin(ang) * 120.0, Z_MIN, Z_MAX) * Z_TO_Y
	return {
		"mx": 400.0 + sin(ang) * 100.0, "my": 300.0 + cos(ang) * 80.0,
		"wx": float(sim.px) + cos(ang) * 300.0, "wy": wy,
		"down": (tick % 160) < 40,
		"clicked": false, "take_click": false,
		"keys_held": held, "keys_pressed": pressed,
	}


func test_determinism_600_ticks() -> void:
	var ma := _mk_sim()
	var mb := _mk_sim()
	for tick in 600:
		var ia := _script_input(tick, ma["sim"])
		ma["sim"].update(DT, ia)
		mb["sim"].update(DT, _script_input(tick, mb["sim"]))
		if tick == 300:
			_assert_sane(ma, "tick 300")
	eq(_snap(ma), _snap(mb), "same seed x 600 scripted ticks -> identical snapshot")
	_assert_sane(ma, "tick 600")
	_assert_sane(mb, "tick 600")
	# a different seed diverges (sanity: the pin is not vacuous)
	var mc := _mk_sim(SEED + 1)
	for tick in 120:
		mc["sim"].update(DT, _script_input(tick, mc["sim"]))
	ok(_snap(ma) != _snap(mc), "different seed diverges")
	# debug_state shape mirrors TS
	var ds: Dictionary = ma["sim"].debug_state()
	ok(ds.has_all(["px", "pz", "php", "pmaxHp", "ents", "bushes"]), "debugState keys TS-verbatim")
