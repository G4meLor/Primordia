# Tests for game/space/space_sim.gd — the space stage sim core PART 1 (M6 T1):
# constructor seeding (the 6-planet system at a pinned seed — parallel-branch
# replay, the boot-order branch pin), makePlanetEco (floraCap by kind, the
# archetype diet dial pulls, volcanic/ocean modifiers, titan/swarm bonus AFTER
# the roster), the onEnter restore whitelist (EVERY guard), persistColonies +
# the CONTINUE round-trip, ship physics (cursor deadzone, WASD/arrows,
# accel/drag integration, engine particles), the ff timeScale block (eco.tick
# dt·26, the ecoMods wire, extinctions/speciations toasts, generations),
# orbits + colony logistic growth (the cap-120 brake), sun danger + hull regen
# windows, debug seams.
# TS source: Spore src/game/space/SpaceStage.ts (frozen), lines cited per pin.
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const RngLib := preload("res://src/core/rng.gd")
const SpaceSim := preload("res://src/game/space/space_sim.gd")
const NamesLib := preload("res://src/evo/names.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const MutationLib := preload("res://src/evo/mutation.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const WorldGenomeLib := preload("res://src/evo/world_genome.gd")

const SEED := 0x5EED
const OBJECTIVE := "SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve"
# TS:105 — the fixed kind ring, verbatim.
const KINDS := ["lush", "ocean", "volcanic", "barren", "lush", "barren"]


# A duck-typed Ecosystem stand-in for the ff-block wiring pins: records the
# tick dt sequence + the assigned mods, returns canned extinctions/speciations.
class RecEco:
	var mods: Dictionary = {}
	var ticks: Array = []
	var extinctions: Array = []
	var speciations: Array = []

	func tick(dt: float, _player_species_id: String = "") -> Dictionary:
		ticks.append(dt)
		return {"extinctions": extinctions, "speciations": speciations}


# ---- fixtures ------------------------------------------------------------------

# Builds a GameContext (explicit seed), the stage rng branch, a recording
# hooks set, and the sim. world_over merges into ctx.world BEFORE the sim
# constructor reads it (the archetype diet dial / ecoMods crafting seam).
func _mk_sim(seed_v: int = SEED, ctx_v: Variant = null, world_over: Dictionary = {}) -> Dictionary:
	var ctx: Variant = ctx_v if ctx_v != null else Ctx.new(seed_v)
	for k in world_over:
		ctx.world[k] = world_over[k]
	var rec: Dictionary = {
		"toasts": [], "banners": [], "audio": [], "shakes": [], "spawns": [],
		"objectives": [], "insets": [], "moods": [], "floats": [], "abilities": [],
		"gotos": [], "saves": 0,
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_show_objective": func(text): rec["objectives"].append(text),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"audio_set_mood": func(name_v): rec["moods"].append(name_v),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"go_to": func(stage_v, data): rec["gotos"].append([stage_v, data]),
		"save_all": func(): rec["saves"] = int(rec["saves"]) + 1,
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = SpaceSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec, "rng": rng}


# Input snapshot with the M2 field shape (space reads keys_held + wx/wy/down).
func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


# ---- the parallel-branch constructor replay (the civ test's method) -------------

# The TS constructor's exact draw sequence replayed on a parallel branch of a
# fresh same-seed context — pins draw ORDER + formulas bit-exactly. Order per
# TS:95-101: the chaos scheduler branch draw FIRST (:98), then generateSystem
# (:103-132): per planet orbitR, name (speciesName), angle, orbitSpeed, r, hue,
# ring, then makePlanetEco (:134-179) for non-barren kinds.
func _replay_constructor(seed_v: int, world: Dictionary) -> Dictionary:
	var pr: Variant = Ctx.new(seed_v).rng.branch()
	var chaos_state: int = pr.branch().state()  # TS:98 — the SECOND branch
	# the diet dial pulls, derived here from the brief's formula — never from
	# the sim (TS:145-148)
	var weights: Dictionary = WorldGenomeLib.archetype_weights(world)
	var pulls := _diet_pulls(weights)
	var expected: Array = []
	for i in 6:
		var kind: String = KINDS[i]
		var orbit_r: float = 520.0 + i * 380.0 + pr.range(-60.0, 60.0)  # TS:108
		var p_name: String = "%s-%d" % [NamesLib.species_name(pr), i + 1]  # TS:112
		var angle: float = pr.range(0.0, TAU)  # TS:114
		# TS:115 — rng(0.008,0.02) · (even ? 1 : −1) / (1 + i·0.12)
		var orbit_speed: float = pr.range(0.008, 0.02) \
				* (1.0 if i % 2 == 0 else -1.0) / (1.0 + i * 0.12)
		var r: float = 46.0 + pr.range(0.0, 34.0) + (10.0 if kind == "lush" else 0.0)  # TS:116
		var hue: float = pr.range(90.0, 140.0) if kind == "lush" else (
				pr.range(190.0, 220.0) if kind == "ocean" else (
				pr.range(5.0, 30.0) if kind == "volcanic" else pr.range(30.0, 60.0)))  # TS:117-120
		var ring: bool = pr.chance(0.25)  # TS:122
		var eco_replay: Variant = null
		if kind != "barren":
			eco_replay = _replay_planet_eco(pr, hue, kind, weights, pulls)
		expected.append({"id": i, "name": p_name, "orbitR": orbit_r, "angle": angle,
			"orbitSpeed": orbit_speed, "r": r, "hue": hue, "kind": kind, "ring": ring,
			"eco": eco_replay})
	return {"planets": expected, "chaos_state": chaos_state, "stage_state": pr.state(),
		"herb_pull": pulls["herb"], "carn_pull": pulls["carn"]}


# The diet-dial pulls from the brief's formula (independent derivation, TS:145-148):
#   herbW = weights.herbivore ?? 1; carnW = (carnivore ?? 1)·(predator ?? 1)
#   pull(x, y) = min(0.9, max(0, x−1)·0.5 + max(0, 1−y)·0.5)
func _diet_pulls(weights: Dictionary) -> Dictionary:
	var herb_w: float = float(weights.get("herbivore", 1.0))
	var carn_w: float = float(weights.get("carnivore", 1.0)) * float(weights.get("predator", 1.0))
	return {
		"herb": minf(0.9, maxf(0.0, herb_w - 1.0) * 0.5 + maxf(0.0, 1.0 - carn_w) * 0.5),
		"carn": minf(0.9, maxf(0.0, carn_w - 1.0) * 0.5 + maxf(0.0, 1.0 - herb_w) * 0.5),
	}


# makePlanetEco's draw sequence on the parallel stream (TS:134-179). The
# bonus species append AFTER the roster so the diet dial never touches them.
func _replay_planet_eco(pr, hue: float, kind: String, weights: Dictionary, pulls: Dictionary) -> Variant:
	var eco: Variant = EcoScript.new(pr.branch())  # TS:135 — the eco's own branch
	eco.flora_cap = 140.0 if kind == "lush" else (110.0 if kind == "ocean" else 70.0)  # TS:136
	eco.flora = eco.flora_cap * 0.7  # TS:137
	var n: int = pr.int(2, 4)  # TS:149
	for i in n:
		var base: Dictionary = GenomeLib.clone_genome(GenomeLib.default_genome())
		var arch: Dictionary = MutationLib.mutate(base, pr, 0.9)  # TS:152
		arch["size"] = pr.range(0.7, 1.9)  # TS:153
		arch["hue"] = fmod(hue + pr.range(-40.0, 40.0) + 360.0, 360.0)  # TS:154
		if kind == "volcanic":  # TS:155
			arch["diet"] = "carnivore"
			arch["jaw"] = maxi(2, int(arch["jaw"]))
		if kind == "ocean":  # TS:156
			arch["flagella"] = maxi(3, int(arch["flagella"]))
		# TS:157-158 — exactly ONE chance draw per species (JS short-circuit)
		if String(arch["diet"]) == "herbivore":
			if pr.chance(pulls["carn"]):
				arch["diet"] = "carnivore"
		elif pr.chance(pulls["herb"]):
			arch["diet"] = "herbivore"
		eco.add_species(arch, pr.range(4.0, 10.0))  # TS:159 — pop from the STAGE stream
	# the bonus species (TS:163-177) — AFTER the roster, no diet dial on them
	if float(weights.get("titan", 0.0)) >= 1.0:
		var t: Dictionary = MutationLib.mutate(
			GenomeLib.clone_genome(GenomeLib.default_genome()), pr, 0.9)
		t["size"] = 2.2
		t["diet"] = "carnivore"
		t["hue"] = fmod(hue + 180.0, 360.0)
		eco.add_species(t, pr.range(4.0, 10.0))
	if float(weights.get("swarm", 0.0)) >= 1.0:
		var s: Dictionary = MutationLib.mutate(
			GenomeLib.clone_genome(GenomeLib.default_genome()), pr, 0.9)
		s["size"] = 0.55
		s["diet"] = "herbivore"
		s["flagella"] = maxi(4, int(s["flagella"]))
		s["hue"] = fmod(hue + 60.0, 360.0)
		eco.add_species(s, pr.range(4.0, 10.0))
	return eco


func _blob(rec_ctx: Variant) -> Dictionary:
	return JSON.parse_string(String(rec_ctx.flags["spaceWorld"]))


func _toasted(rec: Dictionary, fragment: String) -> bool:
	for t in rec["toasts"]:
		if String(t[0]).find(fragment) >= 0:
			return true
	return false


# A probe Rng cloned from the sim's stream state — replaying the TS draw order
# on it derives expected outcomes without calling the sim.
func _probe(sim_v: Variant) -> Variant:
	return RngLib.new_from(sim_v.rng.state())


func _pin_planet_vs_replay(sim_v: Variant, exp_planets: Array, include_eco: bool) -> void:
	for i in 6:
		var p: Dictionary = sim_v.planets[i]
		var e: Dictionary = exp_planets[i]
		eq(int(p["id"]), i, "planet %d id" % i)
		eq(String(p["name"]), String(e["name"]), "planet %d name at seed (draw-order pin, TS:112)" % i)
		approx(float(p["orbitR"]), float(e["orbitR"]), "planet %d orbitR 520+i·380+rng(−60,60) (TS:108)" % i)
		approx(float(p["angle"]), float(e["angle"]), "planet %d angle rng(0,TAU) (TS:114)" % i)
		approx(float(p["orbitSpeed"]), float(e["orbitSpeed"]), "planet %d orbitSpeed formula (TS:115)" % i)
		approx(float(p["r"]), float(e["r"]), "planet %d r 46+rng(0,34)+lush10 (TS:116)" % i)
		approx(float(p["hue"]), float(e["hue"]), "planet %d hue by kind (TS:117-120)" % i)
		eq(String(p["kind"]), String(e["kind"]), "planet %d kind" % i)
		eq(bool(p["ring"]), bool(e["ring"]), "planet %d ring chance 0.25 (TS:122)" % i)
		eq(float(p["x"]), 0.0, "planet %d x 0 at boot (orbit fills them)" % i)
		eq(float(p["y"]), 0.0, "planet %d y 0 at boot" % i)
		eq(p["colony"], null, "planet %d colony null at boot" % i)
		eq(bool(p["scanned"]), false, "planet %d scanned false at boot" % i)
		if include_eco:
			if String(e["kind"]) == "barren":
				eq(p["eco"], null, "planet %d barren → no eco (TS:128)" % i)
			else:
				ok(p["eco"] != null, "planet %d non-barren → eco (TS:128)" % i)
				_pin_eco_vs_replay(p["eco"], e["eco"], "planet %d" % i)


func _pin_eco_vs_replay(eco: Variant, re_eco: Variant, label: String) -> void:
	approx(float(eco.flora_cap), float(re_eco.flora_cap), "%s floraCap by kind (TS:136)" % label)
	approx(float(eco.flora), float(re_eco.flora), "%s flora 0.7·cap (TS:137)" % label)
	eq(eco.species.size(), re_eco.species.size(), "%s roster size (TS:149 — n = rng.int(2,4) + bonuses)" % label)
	for j in eco.species.size():
		var sp: Dictionary = eco.species[j]
		var rs: Dictionary = re_eco.species[j]
		eq(String(sp["name"]), String(rs["name"]), "%s species %d name (eco-stream replay)" % [label, j])
		eq(String(sp["id"]), String(rs["id"]), "%s species %d id (eco-stream replay)" % [label, j])
		approx(float(sp["genome"]["size"]), float(rs["genome"]["size"]), "%s species %d size (TS:153)" % [label, j])
		approx(float(sp["genome"]["hue"]), float(rs["genome"]["hue"]), "%s species %d hue dial (TS:154)" % [label, j])
		eq(String(sp["genome"]["diet"]), String(rs["genome"]["diet"]), "%s species %d diet (the dial, TS:155-158)" % [label, j])
		eq(int(sp["genome"]["flagella"]), int(rs["genome"]["flagella"]), "%s species %d flagella (ocean/bonus modifier)" % [label, j])
		eq(int(sp["genome"]["jaw"]), int(rs["genome"]["jaw"]), "%s species %d jaw (volcanic modifier)" % [label, j])
		approx(float(sp["pop"]), float(rs["pop"]), "%s species %d pop rng(4,10) (TS:159)" % [label, j])
		eq(bool(sp["kin"]), bool(rs["kin"]), "%s species %d kin flag" % [label, j])


# ---- constructor seeding (TS:53-101 + the field block :25-93) ---------------------

func test_constructor_seeding_pins() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var exp_v: Dictionary = _replay_constructor(SEED, ctx.world)
	# the system (TS:103-132)
	eq(sim.planets.size(), 6, "6 planets (TS:106)")
	_pin_planet_vs_replay(sim, exp_v["planets"], true)
	# ship initial state (TS:58-64)
	eq(float(sim.sx), 0.0, "ship sx 0 (TS:58)")
	eq(float(sim.sy), -900.0, "ship sy −900 (TS:58)")
	eq(float(sim.svx), 0.0, "svx 0 (TS:59)")
	eq(float(sim.svy), 0.0, "svy 0 (TS:59)")
	eq(float(sim.shp), 100.0, "shp 100 (TS:60)")
	eq(float(sim.shpMax), 100.0, "shpMax 100 (TS:60)")
	eq(float(sim.shipAngle), -PI / 2.0, "shipAngle −π/2 (TS:61)")
	eq(float(sim.thrust), 0.0, "thrust 0 (TS:62)")
	eq(float(sim.invuln), 2.0, "invuln 2 (TS:63)")
	eq(float(sim.hurtT), 0.0, "hurtT 0 (TS:64)")
	# the state field block (TS:55, :66-93)
	eq(float(sim.time), 0.0, "time 0 (TS:55)")
	eq(sim.cargo.size(), 0, "cargo empty (TS:73)")
	eq(sim.abductCount, {}, "abductCount empty (TS:70)")
	eq(sim.pirates.size(), 0, "pirates empty (TS:67 — the machine is task 2's)")
	eq(sim.blackHoles.size(), 0, "blackHoles empty (TS:72)")
	eq(bool(sim.pirateLull), false, "pirateLull false (TS:69)")
	eq(float(sim.resurveyCd), 0.0, "resurveyCd 0 (TS:71)")
	eq(float(sim.beamT), 0.0, "beamT 0 (TS:85)")
	eq(sim.beamTarget, null, "beamTarget null (TS:86)")
	eq(float(sim.ffHold), 0.0, "ffHold 0 (TS:87)")
	eq(sim.finale, null, "finale null (TS:88)")
	eq(float(sim.endingT), 0.0, "endingT 0 (TS:89)")
	eq(bool(sim.endingDone), false, "endingDone false (TS:90)")
	eq(bool(sim.endingDismissed), false, "endingDismissed false (TS:91)")
	eq(float(sim.dismissT), 0.0, "dismissT 0 (TS:92)")
	eq(float(sim.tributeDemand), 0.0, "tributeDemand 0 (TS:93)")
	eq(bool(sim.uiHold), false, "uiHold false (TS:1193 — the write side is task 2's)")
	eq(float(sim.persistT), 0.0, "persistT 0 (TS:280 — the 5 s tick is task 2's)")
	# the sun (TS:84)
	eq(float(sim.sun["x"]), 0.0, "sun x 0 (TS:84)")
	eq(float(sim.sun["y"]), 0.0, "sun y 0 (TS:84)")
	eq(float(sim.sun["r"]), 130.0, "sun r 130 (TS:84)")
	# boot-order branch pins (TS:97/98): the caller drew the stage branch; the
	# chaos scheduler rode a SECOND branch before generateSystem drew
	eq(int(sim.rng.state()), int(exp_v["stage_state"]),
		"stage rng state after construction (chaos-branch-then-system draw order)")
	eq(int(sim.chaos._rng.state()), int(exp_v["chaos_state"]),
		"chaos scheduler on a SECOND rng.branch() (TS:98)")
	# the deck is Task 3's: the scheduler holds an EMPTY defs array (the M5-T1
	# ruling) — the C1 rebuild gate is fully wired around it
	eq(sim.chaos.defs.size(), 0, "chaos deck EMPTY until task 3 (spaceEvents.ts)")
	eq(int(sim.deckSeed), int(ctx.world["seed"]), "deckSeed = world seed (TS:99)")
	eq(bool(sim.has_active_chaos()), false, "hasActiveChaos false at boot (TS:80-82)")


# ---- makePlanetEco (TS:134-179) ---------------------------------------------------

func test_make_planet_eco_diet_dial_and_bonuses() -> void:
	# a crafted world: herbivore W 3, predator W 2 (carnW = 1·2 = 2) →
	#   herbPull = min(0.9, (3−1)·0.5 + 0) = 0.9; carnPull = min(0.9, 0.5 + 0) = 0.5
	# plus titan + swarm ≥ 1 → one bonus species each, appended AFTER the roster
	var world_over: Dictionary = {"traits": [{"name": "dial", "effects": [
		{"kind": "ecoSeed", "archetype": "herbivore", "weight": 3.0},
		{"kind": "ecoSeed", "archetype": "predator", "weight": 2.0},
		{"kind": "ecoSeed", "archetype": "titan", "weight": 1.0},
		{"kind": "ecoSeed", "archetype": "swarm", "weight": 1.0},
	]}]}
	var m := _mk_sim(SEED, null, world_over)
	var sim: Variant = m["sim"]
	var exp_v: Dictionary = _replay_constructor(SEED, m["ctx"].world)
	# the pulls, derived independently above from the brief's formula
	approx(float(exp_v["herb_pull"]), 0.9, "herbPull min(0.9, (3−1)·0.5 + max(0,1−2)·0.5) = 0.9 (TS:147)")
	approx(float(exp_v["carn_pull"]), 0.5, "carnPull min(0.9, (2−1)·0.5 + 0) = 0.5 (TS:148)")
	# full per-planet eco pin vs the parallel replay (roster genomes, names,
	# pops, the one-chance-draw-per-species cadence)
	_pin_planet_vs_replay(sim, exp_v["planets"], true)
	# the bonus species ride LAST on every non-barren planet and their diet/
	# size survive the dial untouched (TS:161-177 — the AFTER-roster ordering).
	# NOTE the swarm's 0.55 lands as 0.6 STORED: addSpecies clampGenomes its
	# genome and GENE_BOUNDS floors size at 0.6 — the TS does the same clamp
	# inside addSpecies, so the stored 0.6 IS the parity value.
	for i in 6:
		if String(sim.planets[i]["kind"]) == "barren":
			continue
		var sp_list: Array = sim.planets[i]["eco"].species
		ok(sp_list.size() >= 4, "planet %d roster 2-4 + titan + swarm" % i)
		var titan: Dictionary = sp_list[sp_list.size() - 2]
		var swarm: Dictionary = sp_list[sp_list.size() - 1]
		approx(float(titan["genome"]["size"]), 2.2, "planet %d titan size 2.2 (TS:165)" % i)
		eq(String(titan["genome"]["diet"]), "carnivore", "planet %d titan diet SURVIVED the dial (TS:166)" % i)
		approx(float(titan["genome"]["hue"]), fmod(float(sim.planets[i]["hue"]) + 180.0, 360.0),
			"planet %d titan hue +180 (TS:167)" % i)
		approx(float(swarm["genome"]["size"]), 0.6,
			"planet %d swarm size 0.55 stored as 0.6 (addSpecies clampGenome floor, TS:172)" % i)
		eq(String(swarm["genome"]["diet"]), "herbivore", "planet %d swarm diet SURVIVED the dial (TS:173)" % i)
		ok(int(swarm["genome"]["flagella"]) >= 4, "planet %d swarm flagella ≥ 4 (TS:174)" % i)
		approx(float(swarm["genome"]["hue"]), fmod(float(sim.planets[i]["hue"]) + 60.0, 360.0),
			"planet %d swarm hue +60 (TS:175)" % i)


func test_make_planet_eco_neutral_world_flora_caps() -> void:
	# a traitless world: all weights default → both pulls 0 → NO diet flips
	# ever (the dial is inert); floraCaps by kind (TS:136)
	var m := _mk_sim(SEED, null, {"traits": []})
	var sim: Variant = m["sim"]
	var exp_v: Dictionary = _replay_constructor(SEED, m["ctx"].world)
	approx(float(exp_v["herb_pull"]), 0.0, "neutral world → herbPull 0 (TS:147)")
	approx(float(exp_v["carn_pull"]), 0.0, "neutral world → carnPull 0 (TS:148)")
	_pin_planet_vs_replay(sim, exp_v["planets"], true)
	# the floraCap table, read straight off the planets (TS:136)
	eq(float(sim.planets[0]["eco"].flora_cap), 140.0, "lush floraCap 140 (TS:136)")
	eq(float(sim.planets[1]["eco"].flora_cap), 110.0, "ocean floraCap 110 (TS:136)")
	eq(float(sim.planets[2]["eco"].flora_cap), 70.0, "volcanic floraCap 70 (TS:136)")
	eq(float(sim.planets[4]["eco"].flora_cap), 140.0, "second lush floraCap 140 (TS:136)")
	# roster count 2-4 before bonuses (traitless → no bonuses) (TS:149)
	for i in 6:
		if String(sim.planets[i]["kind"]) != "barren":
			var n: int = sim.planets[i]["eco"].species.size()
			ok(n >= 2 and n <= 4, "planet %d roster 2-4 species (got %d)" % [i, n])


# ---- onEnter semantics (TS:181-190) ------------------------------------------------

func test_on_enter_semantics() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.on_enter()
	eq(rec["moods"], ["space"], "audio.setMood('space') via hook (TS:187)")
	eq(rec["objectives"], [OBJECTIVE], "showObjective (TS:188)")
	# C1 rebuild gate: same seed → the scheduler survives (TS:183-186)
	var old: Variant = sim.chaos
	sim.on_enter()
	ok(is_same(sim.chaos, old), "same world seed → no deck rebuild (TS:183)")
	# a different world seed rebuilds the scheduler + updates deckSeed; the
	# deck stays EMPTY until task 3 (the M5-T1 ruling)
	m["ctx"].world["seed"] = SEED + 1
	sim.on_enter()
	ok(not is_same(sim.chaos, old), "world seed changed → scheduler rebuilt (C1, TS:184)")
	eq(int(sim.deckSeed), SEED + 1, "deckSeed updated (TS:185)")
	eq(sim.chaos.defs.size(), 0, "rebuilt deck still EMPTY until task 3")


# ---- the restore whitelist (TS:190-267) --------------------------------------------

# A saved planet row with every whitelisted field present (valid values).
func _row(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"name": "Rowby", "orbitR": 900.0, "angle": 1.25, "orbitSpeed": 0.011,
		"r": 55.5, "hue": 100.0, "kind": "lush", "ring": true, "scanned": false,
		"colony": null, "eco": null}
	d.merge(over, true)
	return d


# `rows` is untyped on purpose: the shapes-gate tests pass a non-Array
# ("notarray") to prove the ledger/ending restore outside the gate.
func _whitelist_blob(rows_v: Variant, over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"planets": rows_v, "cargo": [], "abductCount": {},
		"endingDone": false, "endingDismissed": false}
	d.merge(over, true)
	return d


func test_restore_whitelist_field_guards() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# generated values captured BEFORE the restore (the keep-on-reject baseline)
	var gen_r0: float = float(sim.planets[0]["r"])
	var gen_name0: String = String(sim.planets[0]["name"])
	var gen_hue0: float = float(sim.planets[0]["hue"])
	var gen_kind0: String = String(sim.planets[0]["kind"])
	var gen_ring0: bool = bool(sim.planets[0]["ring"])
	var gen_angle0: float = float(sim.planets[0]["angle"])
	var gen_ospeed0: float = float(sim.planets[0]["orbitSpeed"])
	var gen_orbit0: float = float(sim.planets[0]["orbitR"])
	var gen_r1: float = float(sim.planets[1]["r"])
	var gen_orbit2: float = float(sim.planets[2]["orbitR"])
	# no blob → fresh system untouched (TS:191)
	sim.on_enter()
	eq(float(sim.planets[0]["r"]), gen_r0, "no blob → nothing restored (TS:191)")
	eq(bool(sim.endingDone), false, "no blob → endingDone false")
	# parse failure → fresh (the TS catch, TS:266)
	ctx.flags["spaceWorld"] = "{not json"
	sim.on_enter()
	eq(float(sim.planets[0]["r"]), gen_r0, "parse failure → fresh (TS:266)")
	# the field guards, one corrupt field per row (TS:200-228)
	var rows: Array = [
		# planet 0: corrupt r (−80 fails the r>0 min), string orbitSpeed,
		# string angle, name 42 (not a string), kind 'lava' (off-list),
		# ring 'yes' (not boolean) — ALL rejected, hue 2000 ACCEPTED
		# (num(v) has no max — the verbatim read, TS:214)
		{"r": -80.0, "orbitSpeed": "fast", "angle": "x", "name": 42,
			"kind": "lava", "ring": "yes", "hue": 2000.0, "scanned": "yes",
			"colony": {"pop": "x"}},
		# planet 1: r 0 fails the STRICT > 0 min; everything else valid
		{"r": 0, "name": "Oceanus-2", "orbitR": 1234.5, "angle": 2.5,
			"orbitSpeed": 0.017, "hue": 200.0, "ring": false, "scanned": true,
			"colony": {"pop": 20.0, "generations": 7.0}},
		# planet 2: valid r but orbitR string → orbitR rejected, r taken
		{"r": 60.0, "orbitR": "big"},
		_row({}),  # planet 3: a fully valid row (no colony)
		_row({}),  # planet 4
		_row({}),  # planet 5
	]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows))
	sim.on_enter()
	# planet 0: every corrupt field kept its GENERATED value (TS:208-217)
	eq(float(sim.planets[0]["r"]), gen_r0, "r −80 rejected by the r>0 min → generated r kept (TS:210)")
	eq(float(sim.planets[0]["orbitSpeed"]), gen_ospeed0, "string orbitSpeed rejected (TS:212)")
	eq(float(sim.planets[0]["angle"]), gen_angle0, "string angle rejected (TS:213)")
	eq(float(sim.planets[0]["orbitR"]), gen_orbit0, "planet 0 orbitR untouched (absent from the row)")
	eq(String(sim.planets[0]["name"]), gen_name0, "numeric name rejected (TS:215)")
	eq(String(sim.planets[0]["kind"]), gen_kind0, "off-list kind rejected (TS:216)")
	eq(bool(sim.planets[0]["ring"]), gen_ring0, "non-boolean ring rejected (TS:217)")
	eq(float(sim.planets[0]["hue"]), 2000.0, "hue 2000 ACCEPTED — num(v) has no max (TS:214, verbatim)")
	eq(bool(sim.planets[0]["scanned"]), false, "non-boolean scanned → post-assign false (TS:225/228)")
	eq(sim.planets[0]["colony"], null, "string pop → colony rejected → null (TS:222/227)")
	# planet 1: valid fields restored; r 0 REJECTED by the strict min
	eq(float(sim.planets[1]["r"]), gen_r1, "r 0 fails the STRICT > 0 min → generated r kept (TS:210)")
	eq(String(sim.planets[1]["name"]), "Oceanus-2", "name restored (TS:215)")
	approx(float(sim.planets[1]["orbitR"]), 1234.5, "orbitR restored (TS:211)")
	approx(float(sim.planets[1]["angle"]), 2.5, "angle restored (TS:213)")
	approx(float(sim.planets[1]["orbitSpeed"]), 0.017, "orbitSpeed restored (TS:212)")
	approx(float(sim.planets[1]["hue"]), 200.0, "hue restored (TS:214)")
	eq(bool(sim.planets[1]["ring"]), false, "ring false restored (TS:217)")
	eq(bool(sim.planets[1]["scanned"]), true, "scanned true restored — the whitelist rides (TS:225)")
	eq(sim.planets[1]["colony"]["pop"], 20.0, "colony pop restored (TS:222-223)")
	eq(sim.planets[1]["colony"]["generations"], 7.0, "colony generations restored (TS:223)")
	# planet 2: valid r taken, corrupt orbitR rejected
	eq(float(sim.planets[2]["r"]), 60.0, "valid r restored (TS:210)")
	approx(float(sim.planets[2]["orbitR"]), gen_orbit2,
		"orbitR string rejected → generated orbitR kept (TS:211)")
	# planet 3: the fully valid row restored wholesale
	eq(String(sim.planets[3]["name"]), "Rowby", "valid row name restored")
	approx(float(sim.planets[3]["r"]), 55.5, "valid row r restored")
	eq(bool(sim.planets[3]["ring"]), true, "valid row ring restored")
	# colony variants on planet 4 (TS:222-223): pop without generations → 1
	var rows2: Array = [_row({}), _row({}), _row({}),
		_row({"colony": {"pop": 9.0}}),  # planet 3: generations missing → 1
		_row({"colony": {"pop": 11.0, "generations": "no"}}),  # planet 4: corrupt generations → 1
		_row({"colony": {"pop": 13.0, "generations": 3.0}}),  # planet 5: valid
	]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows2))
	sim.on_enter()
	eq(sim.planets[3]["colony"]["generations"], 1.0, "missing generations defaults to 1 (TS:223)")
	eq(sim.planets[4]["colony"]["generations"], 1.0, "corrupt generations defaults to 1 (TS:223)")
	eq(sim.planets[4]["colony"]["pop"], 11.0, "pop still taken with a corrupt sibling (TS:222)")
	eq(sim.planets[5]["colony"]["generations"], 3.0, "valid generations restored (TS:223)")


func test_restore_eco_always_taken_and_colonist_rebuild() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# the instanceof guard (TS:229-231): a planet whose eco is NOT an
	# Ecosystem (the old-format plain-object save) is nulled BEFORE the
	# always-take/rebuild steps — a Dictionary eco would crash .tick
	sim.planets[1]["eco"] = {"junk": true}      # ocean, no colony in the save below
	sim.planets[3]["eco"] = {"junk": true}      # barren, WITH a colony → rebuild kicks in
	# planet 0 (lush) already owns a FRESH random eco — the saved eco must
	# replace it anyway (the ALWAYS-take-saved rule, TS:236-240)
	var fresh0: Variant = sim.planets[0]["eco"]
	var saved_eco: Dictionary = {"species": [
		{"id": "sp0_saved", "name": "Savedus Prime", "genome": {"size": 1.5, "diet": "herbivore"}, "pop": 12.0},
	], "flora": 55.5, "floraCap": 140.0}
	var rows: Array = [
		_row({"eco": saved_eco}),
		# planet 1: a corrupt eco (species not an array) → NOT taken
		_row({"kind": "ocean", "eco": {"species": "nope", "flora": 1.0}}),
		_row({}),
		# planet 3 (barren): a colony but NO eco → the colonist eco rebuild
		_row({"kind": "barren", "colony": {"pop": 7.0, "generations": 2.0}}),
		_row({}),
		_row({}),
	]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows))
	sim.on_enter()
	# planet 0: the SAVED eco taken over the fresh random one (TS:235-240)
	ok(not is_same(sim.planets[0]["eco"], fresh0), "the saved eco replaced the fresh roster (TS:238-240)")
	eq(sim.planets[0]["eco"].species.size(), 1, "saved eco species count")
	eq(String(sim.planets[0]["eco"].species[0]["name"]), "Savedus Prime", "saved eco species name rode the save")
	approx(float(sim.planets[0]["eco"].species[0]["genome"]["size"]), 1.5, "saved genes survive (the seeded-genes pin)")
	eq(String(sim.planets[0]["eco"].species[0]["genome"]["diet"]), "herbivore", "saved diet survives")
	approx(float(sim.planets[0]["eco"].flora), 55.5, "saved flora restored (TS:239)")
	approx(float(sim.planets[0]["eco"].flora_cap), 140.0, "saved floraCap restored (fromJSON floraCap)")
	# planet 1: the corrupt eco (species not an array) NOT taken — and the
	# instanceof guard already nulled the planted Dictionary eco → NO eco
	eq(sim.planets[1]["eco"], null,
		"non-Ecosystem eco nulled by the instanceof guard + corrupt saved eco not taken (TS:229-235)")
	# planet 3: a seeded barren world keeps its colonists' ecosystem —
	# rebuilt as ONE kin species named '{name} colonists' at pop 5 (TS:242-245)
	var p3: Dictionary = sim.planets[3]
	ok(p3["eco"] != null, "colonist eco rebuilt (TS:242-245)")
	eq(p3["eco"].species.size(), 1, "colonist eco holds exactly the colonist line")
	eq(String(p3["eco"].species[0]["name"]), "Rowby colonists", "colonist name '{p.name} colonists' (the RESTORED name, TS:244)")
	eq(bool(p3["eco"].species[0]["kin"]), true, "colonist line is kin (TS:244)")
	approx(float(p3["eco"].species[0]["pop"]), 5.0, "colonist pop 5 (TS:244)")
	eq(p3["colony"]["pop"], 7.0, "the colony that demanded the rebuild restored (TS:222)")


func test_restore_cargo_clamp_merge() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rows: Array = [_row({}), _row({}), _row({}), _row({}), _row({}), _row({})]
	var cargo: Array = [
		{"genome": {"size": 99.0, "diet": "carnivore"}, "name": "Big One"},
		{"genome": "junk"},                      # genome not an object → dropped
		null,                                    # not an object → dropped
		{"genome": {"legs": 3}},                 # no name → 'specimen'
		{"genome": {}, "name": 42},              # non-string name → 'specimen'
	]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows, {"cargo": cargo}))
	sim.on_enter()
	eq(sim.cargo.size(), 3, "junk cargo rows dropped (TS:249)")
	var c0: Dictionary = sim.cargo[0]
	eq(String(c0["name"]), "Big One", "cargo name restored (TS:250)")
	approx(float(c0["genome"]["size"]), 2.2, "size 99 clamped to the 2.2 bound (clampGenome merge, TS:250)")
	eq(String(c0["genome"]["diet"]), "carnivore", "cargo diet merged over the default (TS:250)")
	eq(int(c0["genome"]["jaw"]), 1, "unlisted genes snap to the DEFAULT genome (the {...defaults, ...saved} merge)")
	var c1: Dictionary = sim.cargo[1]
	eq(String(c1["name"]), "specimen", "missing name → 'specimen' (TS:250)")
	eq(int(c1["genome"]["legs"]), 3, "legs merged (TS:250)")
	var c2: Dictionary = sim.cargo[2]
	eq(String(c2["name"]), "specimen", "non-string name → 'specimen' (TS:250)")
	# cargo not an array → emptied (still inside the shapes gate, TS:247-251)
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows, {"cargo": "x"}))
	sim.on_enter()
	eq(sim.cargo.size(), 0, "non-array cargo → [] (TS:247-251)")


func test_restore_ledger_and_ending_outside_the_gate() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# a SHAPES-FAILING blob (planets not an array) — the abductCount ledger and
	# the ending persistence live OUTSIDE the shapes gate (TS:253-264 are
	# try-block siblings of the `if (shapesOk...)`, so they restore anyway)
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob("notarray", {
		"abductCount": {"Glorbus": 3},
		"endingDone": true, "endingDismissed": true,
	}))
	sim.on_enter()
	eq(sim.planets.size(), 6, "planets untouched by the shapes failure")
	eq(int(sim.abductCount["Glorbus"]), 3, "abductCount ledger restored DESPITE the shapes failure (TS:253-255)")
	eq(bool(sim.endingDone), true, "endingDone restored despite the shapes failure (TS:257-264)")
	eq(bool(sim.endingDismissed), true, "endingDismissed === true restored (TS:259)")
	eq(float(sim.endingT), 99.0, "dismissed → endingT 99 (TS:260)")
	eq(float(sim.dismissT), 99.0, "dismissed → dismissT 99 (TS:261)")
	eq(sim.finale, null, "a dismissed ending sleeps — finale null (TS:263)")
	# a length mismatch ALSO leaves the planets but restores the ledger
	var m2 := _mk_sim(SEED, m["ctx"])
	var sim2: Variant = m2["sim"]
	var gen_r: float = float(sim2.planets[0]["r"])
	var rows5: Array = [_row({}), _row({}), _row({}), _row({}), _row({})]  # 5 rows
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows5, {"abductCount": {"Zor": 1}}))
	sim2.on_enter()
	eq(float(sim2.planets[0]["r"]), gen_r, "length mismatch → planets untouched (TS:201)")
	eq(int(sim2.abductCount["Zor"]), 1, "ledger restored on a length mismatch (TS:253)")
	# a WON but UNDISMISSED run re-arms the finale orb (TS:257-264)
	var m3 := _mk_sim(SEED, m["ctx"])
	var sim3: Variant = m3["sim"]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob("notarray", {
		"endingDone": true, "endingDismissed": false,
	}))
	sim3.on_enter()
	eq(bool(sim3.endingDone), true, "endingDone latches")
	eq(bool(sim3.endingDismissed), false, "endingDismissed false on a non-true saved value (TS:259)")
	eq(float(sim3.endingT), 0.0, "endingT UNCHANGED when not dismissed (TS:260 ternary)")
	eq(float(sim3.dismissT), 0.0, "dismissT unchanged when not dismissed (TS:261)")
	var fin: Dictionary = sim3.finale
	ok(fin != null, "an undismissed won run re-arms the finale (TS:263)")
	eq(float(fin["x"]), 0.0, "finale x 0 (TS:263)")
	eq(float(fin["y"]), -1900.0, "finale y −1900 (TS:263)")
	eq(bool(fin["active"]), true, "finale active (TS:263)")
	eq(float(fin["t"]), 0.0, "finale t 0 (TS:263)")
	# endingDismissed without endingDone → NOTHING (the conjunction, TS:257)
	var m4 := _mk_sim(SEED, m["ctx"])
	var sim4: Variant = m4["sim"]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob("notarray", {"endingDismissed": true}))
	sim4.on_enter()
	eq(bool(sim4.endingDone), false, "endingDone false without a saved true (TS:257)")
	eq(sim4.finale, null, "finale stays null (the fresh value)")
	# a non-object abductCount is rejected; the empty object IS taken
	# (JS object truthiness — TS:253)
	var m5 := _mk_sim(SEED, m["ctx"])
	var sim5: Variant = m5["sim"]
	sim5.abductCount = {"Keep": 1}
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob("notarray", {"abductCount": 5}))
	sim5.on_enter()
	eq(int(sim5.abductCount["Keep"]), 1, "numeric abductCount rejected (TS:253)")
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob("notarray", {"abductCount": {}}))
	sim5.on_enter()
	eq(sim5.abductCount, {}, "EMPTY abductCount object taken — JS {} is truthy (TS:253)")


# ---- persist (TS:270-297) -----------------------------------------------------------

func test_persist_shape_and_roundtrip() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# mutate the run: a colony, a scan, cargo, the ledger, the ending
	sim.planets[0]["colony"] = {"pop": 15.5, "generations": 2.5}
	sim.planets[1]["scanned"] = true
	sim.cargo.append({"genome": GenomeLib.default_genome(), "name": "Specimen One"})
	sim.abductCount["Glorbus"] = 3
	sim.persist_state()
	# the blob shape (TS:285-296)
	var blob: Dictionary = _blob(ctx)
	ok(blob.has("planets") and blob.has("cargo") and blob.has("abductCount")
		and blob.has("endingDone") and blob.has("endingDismissed"),
		"blob carries planets/cargo/abductCount/endingDone/endingDismissed (TS:285-295)")
	eq(blob["planets"].size(), 6, "blob holds all 6 planets (TS:286)")
	var row: Dictionary = blob["planets"][0]
	for key in ["id", "name", "orbitR", "angle", "orbitSpeed", "r", "hue", "kind",
			"ring", "scanned", "colony", "eco"]:
		ok(row.has(key), "planet row carries %s (TS:287-289)" % key)
	ok(not row.has("x"), "x NOT persisted — the orbit refills it (TS:287-290)")
	ok(not row.has("y"), "y NOT persisted (TS:287-290)")
	eq(row["colony"]["pop"], 15.5, "colony rides the blob (TS:288)")
	ok(row["eco"].has("species") and row["eco"].has("flora") and row["eco"].has("floraCap"),
		"eco persisted via toJSON (TS:289)")
	eq(blob["planets"][3]["eco"], null, "a barren planet persists eco null (TS:289)")
	eq(int(blob["abductCount"]["Glorbus"]), 3, "abductCount rides the blob (TS:292)")
	eq(bool(blob["endingDone"]), false, "endingDone rides the blob (TS:293)")
	eq(blob["cargo"][0]["name"], "Specimen One", "cargo rides the blob (TS:291)")
	# on_exit persists (TS:270-272)
	ctx.flags.erase("spaceWorld")
	sim.planets[0]["colony"]["pop"] = 16.5
	sim.on_exit()
	eq(float(_blob(ctx)["planets"][0]["colony"]["pop"]), 16.5, "on_exit → persistColonies (TS:270-272)")
	# persist_state persists — the saveAll splice-rollback pin (TS:274-278)
	ctx.flags.erase("spaceWorld")
	sim.planets[0]["colony"]["pop"] = 17.5
	sim.persist_state()
	eq(float(_blob(ctx)["planets"][0]["colony"]["pop"]), 17.5, "persist_state → persistColonies (TS:276-278)")
	# full CONTINUE round-trip into a FRESH sim on the SAME context — the fresh
	# sim re-rolls a different base system (the ctx stream advanced), so a
	# match proves the restore took the SAVED values
	var m2 := _mk_sim(SEED, ctx)
	var sim2: Variant = m2["sim"]
	ok(not is_same(sim2.planets[0]["eco"], sim.planets[0]["eco"]),
		"the fresh sim re-rolled its own system (premise)")
	sim2.on_enter()
	eq(float(sim2.planets[0]["colony"]["pop"]), 17.5, "round-trip: colony pop (TS:222)")
	eq(float(sim2.planets[0]["colony"]["generations"]), 2.5, "round-trip: generations")
	eq(bool(sim2.planets[1]["scanned"]), true, "round-trip: scanned (the 12-reports pin, TS:218-221)")
	eq(String(sim2.planets[0]["name"]), String(sim.planets[0]["name"]), "round-trip: name")
	approx(float(sim2.planets[0]["r"]), float(sim.planets[0]["r"]), "round-trip: r")
	approx(float(sim2.planets[0]["orbitSpeed"]), float(sim.planets[0]["orbitSpeed"]), "round-trip: orbitSpeed")
	eq(sim2.planets[0]["eco"].species.size(), sim.planets[0]["eco"].species.size(),
		"round-trip: eco roster size (seeded genes survive, TS:232-240)")
	eq(String(sim2.planets[0]["eco"].species[0]["name"]),
		String(sim.planets[0]["eco"].species[0]["name"]), "round-trip: eco species name")
	eq(int(sim2.abductCount["Glorbus"]), 3, "round-trip: abductCount")
	eq(String(sim2.cargo[0]["name"]), "Specimen One", "round-trip: cargo")
	# the seeded-barren colonist eco also round-trips as a REAL eco
	sim.planets[3]["colony"] = {"pop": 8.0, "generations": 1.0}
	sim.on_exit()
	sim2.on_enter()
	ok(sim2.planets[3]["eco"] != null, "round-trip: the colonist eco came back as an ecosystem (TS:242-245)")
	eq(String(sim2.planets[3]["eco"].species[0]["name"]),
		String(sim.planets[3]["eco"].species[0]["name"]), "round-trip: colonist line name")


# ---- ship control (TS:327-350) -------------------------------------------------------

func test_ship_control_keys_and_integration() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# idle: no thrust, no angle change, drag-only drift; and NO stage-rng draw
	# (the engine-particle chance short-circuits on thrust 0, TS:353)
	var st0: int = int(sim.rng.state())
	sim.svx = 10.0
	sim.sx = 100.0
	sim.update(1.0, _inp())
	eq(float(sim.thrust), 0.0, "idle → thrust 0 (TS:341)")
	eq(float(sim.shipAngle), -PI / 2.0, "idle → angle unchanged (TS:342)")
	approx(float(sim.svx), 10.0 * exp(-1.1), "drag exp(−1.1·dt) (TS:347-348)")
	approx(float(sim.sx), 100.0 + 10.0 * exp(-1.1), "sx integrates svx·dt (TS:349)")
	eq(int(sim.rng.state()), st0, "idle frame draws NOTHING from the stage stream (TS:353 short-circuit)")
	# KeyW: dy −1 → normalized (0,−1), angle −π/2, accel 420 (TS:335/339-346)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.sx = 0.0
	sim.sy = -900.0
	sim.update(1.0 / 60.0, _inp({"keys_held": ["KeyW"]}))
	eq(float(sim.thrust), 1.0, "KeyW → thrust 1 (TS:341)")
	approx(float(sim.shipAngle), -PI / 2.0, "KeyW → angle atan2(−1,0) = −π/2 (TS:342)")
	approx(float(sim.svy), -420.0 / 60.0 * exp(-1.1 / 60.0), "svy = dy·420·dt then drag (TS:345-348)")
	approx(float(sim.sy), -900.0 + (-420.0 / 60.0 * exp(-1.1 / 60.0)) * (1.0 / 60.0), "sy integrates (TS:349-350)")
	eq(float(sim.svx), 0.0, "svx untouched by KeyW")
	eq(float(sim.sx), 0.0, "sx untouched by KeyW")
	# ArrowUp ≡ KeyW (TS:335)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_held": ["ArrowUp"]}))
	approx(float(sim.svy), -420.0 / 60.0 * exp(-1.1 / 60.0), "ArrowUp ≡ KeyW (TS:335)")
	# KeyD: dx +1 → angle 0 (TS:338)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_held": ["KeyD"]}))
	eq(float(sim.shipAngle), 0.0, "KeyD → angle atan2(0,1) = 0")
	approx(float(sim.svx), 420.0 / 60.0 * exp(-1.1 / 60.0), "svx = dx·420·dt then drag (TS:344-348)")
	# KeyS / ArrowDown (TS:336)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_held": ["KeyS"]}))
	approx(float(sim.svy), 420.0 / 60.0 * exp(-1.1 / 60.0), "KeyS → svy positive (TS:336)")
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_held": ["ArrowDown"]}))
	approx(float(sim.svy), 420.0 / 60.0 * exp(-1.1 / 60.0), "ArrowDown ≡ KeyS")
	# KeyA / ArrowLeft (TS:337)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_held": ["KeyA"]}))
	eq(float(sim.shipAngle), PI, "KeyA → angle atan2(0,−1) = π")
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_held": ["ArrowLeft"]}))
	eq(float(sim.shipAngle), PI, "ArrowLeft ≡ KeyA")
	# diagonal W+D: the unit vector, angle −π/4 (TS:339-342)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_held": ["KeyW", "KeyD"]}))
	approx(float(sim.shipAngle), -PI / 4.0, "W+D → angle atan2(−1,1) = −π/4")
	approx(float(sim.svx), (1.0 / sqrt(2.0)) * 420.0 / 60.0 * exp(-1.1 / 60.0),
		"W+D → normalized dx 1/√2 (TS:339-340)")
	# cursor thrust: hold + a far cursor → thrust toward it (TS:329-334)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.sx = 0.0
	sim.sy = -900.0
	sim.update(1.0 / 60.0, _inp({"down": true, "wx": 100.0, "wy": -900.0}))
	eq(float(sim.thrust), 1.0, "cursor hold → thrust 1 (TS:329-341)")
	eq(float(sim.shipAngle), 0.0, "cursor east → angle atan2(0,100) = 0 (TS:342)")
	# the 20-unit deadzone: d < 20 zeroes the cursor pull (TS:332-334)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.sx = 0.0
	sim.sy = -900.0
	sim.shipAngle = -PI / 2.0
	sim.update(1.0 / 60.0, _inp({"down": true, "wx": 15.0, "wy": -900.0}))
	eq(float(sim.thrust), 0.0, "cursor at d 15 < 20 → dead, thrust 0 (TS:333)")
	eq(float(sim.shipAngle), -PI / 2.0, "dead cursor → angle unchanged")
	# the boundary: d exactly 20 is NOT dead (strict <, TS:333)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.sx = 0.0
	sim.sy = -900.0
	sim.update(1.0 / 60.0, _inp({"down": true, "wx": 20.0, "wy": -900.0}))
	eq(float(sim.thrust), 1.0, "cursor at d exactly 20 → NOT dead (strict <, TS:333)")
	# uiHold gate: the panel-hold flag suppresses the cursor thrust (TS:329;
	# the WRITE side is task 2's — the sim only reads)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.sx = 0.0
	sim.sy = -900.0
	sim.shipAngle = -PI / 2.0
	sim.uiHold = true
	sim.update(1.0 / 60.0, _inp({"down": true, "wx": 100.0, "wy": -900.0}))
	eq(float(sim.thrust), 0.0, "uiHold suppresses the cursor pull (TS:329)")
	eq(float(sim.shipAngle), -PI / 2.0, "uiHold → angle unchanged")
	sim.uiHold = false


func test_engine_particles() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var dt := 1.0 / 60.0
	# thrusting frame: chance(dt·40) decides the spawn; the back-of-ship
	# velocity jitter draws TWO ranges after the chance (TS:353-361). The probe
	# replays the frame's draws BEFORE the update (independent derivation).
	var p: Variant = _probe(sim)
	var d_spawn: float = p.next()
	var d_vx: float = p.next()
	var d_vy: float = p.next()
	sim.update(dt, _inp({"keys_held": ["KeyW"]}))
	var expected_spawn: bool = d_spawn < dt * 40.0
	eq(m["rec"]["spawns"].size(), 1 if expected_spawn else 0, "engine spawn iff chance(dt·40) (TS:353)")
	if expected_spawn:
		var s: Dictionary = m["rec"]["spawns"][0]
		var back: float = -PI / 2.0 + PI
		approx(float(s["x"]), 0.0 + cos(back) * 14.0, "spawn x = ship + cos(back)·14 (TS:356)")
		approx(float(s["y"]), -900.0 + sin(back) * 14.0, "spawn y = ship + sin(back)·14 (TS:356)")
		approx(float(s["vx"]), cos(back) * 120.0 + (-20.0 + d_vx * 40.0), "spawn vx = cos(back)·120 + rng(−20,20) (TS:357)")
		approx(float(s["vy"]), sin(back) * 120.0 + (-20.0 + d_vy * 40.0), "spawn vy = sin(back)·120 + rng(−20,20) (TS:358)")
		eq(float(s["ttl"]), 0.5, "ttl 0.5 (TS:359)")
		eq(float(s["size"]), 3.0, "size 3 (TS:359)")
		eq(String(s["kind"]), "dot", "kind dot (TS:359)")
		eq(String(s["color"]), "hsl(200 100% 70% / 1.00)", "color hsl(200,1,0.7) (TS:359)")
		eq(float(s["drag"]), 3.0, "drag 3 (TS:360)")
	# a NON-spawning seeded frame draws only the chance (no ranges) — pin the
	# stream cadence: the sim's post-frame state equals the probe's state
	# after the SAME number of draws (d2 already consumed the chance draw)
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var p2: Variant = _probe(sim2)
	var d2: float = p2.next()
	sim2.update(dt, _inp({"keys_held": ["KeyW"]}))
	if d2 >= dt * 40.0:
		eq(int(sim2.rng.state()), int(p2.state()),
			"no spawn → only the chance draw, no jitter ranges (TS:353-358 cadence)")
	else:
		p2.next()
		p2.next()
		eq(int(sim2.rng.state()), int(p2.state()),
			"spawn → chance + two jitter ranges (TS:353-358 cadence)")


# ---- the fast-forward block (TS:306-325) ----------------------------------------------

func test_ff_timescale_and_wiring() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	# swap planet 0's eco for the recorder; give it a colony + a scan; NULL the
	# other real ecos so the real ecosystems can't tick/toast in this test
	# (hermeticity — the ff loop then touches ONLY the recorder)
	var re := RecEco.new()
	sim.planets[0]["eco"] = re
	sim.planets[1]["eco"] = null
	sim.planets[2]["eco"] = null
	sim.planets[4]["eco"] = null
	sim.planets[0]["colony"] = {"pop": 10.0, "generations": 0.0}
	sim.planets[0]["scanned"] = true
	re.extinctions = [{"name": "Doomus"}]
	re.speciations = [{"name": "Novus"}]
	# the ecoMods wire: a crafted world num-effect → the mods the sim assigns
	ctx.world["traits"] = [{"effects": [{"kind": "num", "key": "growth_mult", "value": 1.5}]}]
	# frame 1 (first F hold): timeScale reads the PRE-update ffHold (0 → 1);
	# the ff block still runs (ffHold updated to 1 first) — tick receives dt·1
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	eq(re.ticks, [1.0], "frame 1: eco.tick(dt·timeScale=1) — timeScale pre-reads ffHold (TS:306/315)")
	approx(float(re.mods.get("growth_mult", 0.0)), 1.5, "eco.mods = ecoModsFromWorld(world) — the wire (TS:311/314)")
	eq(float(sim.ffHold), 1.0, "KeyF held → ffHold 1 (TS:307)")
	# extinctions: bump_extinction + the colony toast (TS:316-318)
	eq(int(ctx.world_stats["extinctions"]), 1, "bump_extinction per extinction (TS:317)")
	eq(String(rec["toasts"][0][0]), "Doomus went extinct on %s" % String(sim.planets[0]["name"]),
		"extinction toast text (TS:318)")
	eq(String(rec["toasts"][0][1]), "chaos", "extinction toast kind")
	eq(String(rec["toasts"][0][2]), "💀", "extinction toast icon")
	# speciations + scanned → the evolve toast (TS:320-321)
	eq(String(rec["toasts"][1][0]), "Novus evolves on %s" % String(sim.planets[0]["name"]),
		"speciation toast text (TS:321)")
	eq(String(rec["toasts"][1][2]), "🧬", "speciation toast icon")
	# generations += dt·timeScale/30 (TS:323)
	approx(float(sim.planets[0]["colony"]["generations"]), 1.0 / 30.0, "generations += dt·1/30 (TS:323)")
	# frame 2 (still held): timeScale 26 → tick dt·26, generations +26/30
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	eq(float(re.ticks[1]), 26.0, "frame 2: eco.tick(dt·26) (TS:306/315)")
	approx(float(sim.planets[0]["colony"]["generations"]), (1.0 + 26.0) / 30.0,
		"generations += dt·26/30 (TS:323)")
	# frame 3 (released, dt 1): timeScale 26 (pre-read), ffHold decays to 0 →
	# the ff block does NOT run (TS:307/308)
	var ticks_n: int = re.ticks.size()
	sim.update(1.0, _inp())
	eq(re.ticks.size(), ticks_n, "released + ffHold decayed to 0 → no ff tick (TS:307-308)")
	eq(float(sim.ffHold), 0.0, "ffHold decayed max(0, 1−dt) (TS:307)")
	# an eco-less planet is skipped by the ff loop (TS:313 — planets 1/2/4
	# hold null ecos; the tick count proves the loop touched only planet 0)
	re.extinctions = [{"name": "Goneus"}]
	re.speciations = []  # clear the queued Novus — the frame must be toast-silent
	sim.planets[0]["colony"] = null  # no colony → the extinction gate (TS:318)
	rec["toasts"].clear()
	ctx.world_stats["extinctions"] = 0
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	eq(re.ticks.size(), ticks_n + 1, "ff runs again while held")
	eq(int(ctx.world_stats["extinctions"]), 1, "bump_extinction without a colony too (TS:317)")
	eq(rec["toasts"].size(), 0, "NO extinction toast without a colony (TS:318 gate)")
	# speciation WITHOUT scanned → no toast (TS:321 gate)
	sim.planets[0]["scanned"] = false
	re.speciations = [{"name": "Hiddenus"}]
	rec["toasts"].clear()
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	eq(rec["toasts"].size(), 0, "speciation toast gated on scanned (TS:321)")


# ---- orbits + colony growth + sun + regen (TS:363-389) -------------------------------

func test_orbit_and_colony_growth() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# planet 0 on a known orbit with a colony (TS:364-374)
	sim.planets[0]["angle"] = 1.0
	sim.planets[0]["orbitSpeed"] = 0.01
	sim.planets[0]["orbitR"] = 800.0
	sim.planets[0]["colony"] = {"pop": 10.0, "generations": 0.0}
	sim.update(1.0, _inp())
	approx(float(sim.planets[0]["angle"]), 1.01, "angle += orbitSpeed·dt (TS:365)")
	approx(float(sim.planets[0]["x"]), cos(1.01) * 800.0, "x = cos(angle)·orbitR (TS:366)")
	approx(float(sim.planets[0]["y"]), sin(1.01) * 800.0, "y = sin(angle)·orbitR (TS:367)")
	# logistic growth: dt·ts·0.08·(1+pop·0.01)·max(0, 1−pop/120) (TS:372)
	var pop1: float = 10.0 + 1.0 * 1.0 * 0.08 * (1.0 + 10.0 * 0.01) * maxf(0.0, 1.0 - 10.0 / 120.0)
	approx(float(sim.planets[0]["colony"]["pop"]), pop1, "colony logistic growth (TS:372)")
	# the cap-120 brake: at pop 120 the factor is 0 (TS:372)
	sim.planets[0]["colony"]["pop"] = 120.0
	sim.update(1.0, _inp())
	approx(float(sim.planets[0]["colony"]["pop"]), 120.0, "pop 120 → zero growth (the brake, TS:372)")
	sim.planets[0]["colony"]["pop"] = 130.0
	sim.update(1.0, _inp())
	approx(float(sim.planets[0]["colony"]["pop"]), 130.0, "pop above 120 → still zero growth (max(0,·), TS:372)")
	# ff orbit ×0.4 (ffHold post-update → already ×0.4 on the first held frame, TS:365)
	sim.planets[0]["angle"] = 1.0
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	approx(float(sim.planets[0]["angle"]), 1.0 + 0.01 * 0.4, "ff → orbit ×0.4 (TS:365)")
	# ff colony growth uses timeScale (the pre-read: frame 1 → ×1, frame 2 → ×26)
	var pop_a: float = float(sim.planets[0]["colony"]["pop"])
	var pop_b: float = pop_a + 1.0 * 1.0 * 0.08 * (1.0 + pop_a * 0.01) * maxf(0.0, 1.0 - pop_a / 120.0)
	approx(float(sim.planets[0]["colony"]["pop"]), pop_b, "ff frame 1: growth ×ts 1 (the pre-read, TS:306/372)")
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	var pop_c: float = pop_b + 1.0 * 26.0 * 0.08 * (1.0 + pop_b * 0.01) * maxf(0.0, 1.0 - pop_b / 120.0)
	approx(float(sim.planets[0]["colony"]["pop"]), pop_c, "ff frame 2: growth ×26 (TS:306/372)")


func test_sun_danger_and_hull_regen() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# the start invuln 2 shields the sun (TS:63/378)
	sim.sx = 0.0
	sim.sy = 0.0
	sim.update(0.5, _inp())
	eq(float(sim.shp), 100.0, "invuln 2 > 0 → no sun damage (TS:378)")
	eq(float(sim.hurtT), 0.0, "no hurt flash (TS:380)")
	eq(rec["shakes"].size(), 0, "no shake (TS:381)")
	eq(float(sim.invuln), 2.0, "invuln NOT decayed here — that decay is task 2's (TS:605)")
	# inside the sun window with invuln 0: −30·dt, hurtT 1, camShakeFor(4, 0.2)
	sim.invuln = 0.0
	sim.update(0.5, _inp())
	approx(float(sim.shp), 100.0 - 30.0 * 0.5, "sun damage −30·dt (TS:379)")
	eq(float(sim.hurtT), 1.0, "hurtT 1 (TS:380)")
	eq(rec["shakes"], [[4.0, 0.2]], "camShakeFor(4, 0.2) (TS:381)")
	# the boundary: d exactly sun.r + 60 is safe (strict <, TS:378)
	sim.sx = 190.0
	sim.sy = 0.0
	var shp_before: float = float(sim.shp)
	var shakes_n: int = rec["shakes"].size()
	sim.update(0.5, _inp())
	eq(float(sim.shp), shp_before, "d = r+60 → safe (strict <, TS:378)")
	eq(rec["shakes"].size(), shakes_n, "no shake at the boundary")
	# hull regen near a thriving colony (pop ≥ 5, d < r + 150) (TS:385-389)
	var p: Dictionary = sim.planets[0]
	p["angle"] = 0.0
	p["orbitR"] = 1000.0
	p["colony"] = {"pop": 5.0, "generations": 0.0}
	sim.sx = 1000.0 + 50.0  # inside p.r + 150 for any generated r (46-90)
	sim.sy = 0.0
	sim.shp = 50.0
	sim.update(0.5, _inp())
	approx(float(sim.shp), 50.0 + 8.0 * 0.5, "hull regen +8·dt near a thriving colony (TS:387)")
	# pop gate: 4.9 < 5 → no regen (TS:386)
	sim.shp = 50.0
	p["colony"]["pop"] = 4.9
	sim.update(0.5, _inp())
	eq(float(sim.shp), 50.0, "pop < 5 → no regen (TS:386)")
	# distance gate: d = r + 150 exactly is safe (strict <, TS:386)
	p["colony"]["pop"] = 5.0
	sim.shp = 50.0
	var pr_r: float = float(p["r"])
	sim.sx = 1000.0 + pr_r + 150.0
	sim.sy = 0.0
	sim.update(0.5, _inp())
	eq(float(sim.shp), 50.0, "d = r + 150 → no regen (strict <, TS:386)")
	# the shpMax cap (TS:387)
	sim.sx = 1050.0
	sim.sy = 0.0
	sim.shp = 99.9
	sim.update(0.5, _inp())
	eq(float(sim.shp), 100.0, "regen caps at shpMax (TS:387)")


# ---- debug seams (TS:1275-1287) ----------------------------------------------------

func test_debug_seams() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# debug_state — the documented read surface
	var st: Dictionary = sim.debug_state()
	ok(st.has("planets") and st.has("cargo") and st.has("abductCount") and st.has("shp")
		and st.has("endingDone"), "debug_state exposes the core fields")
	eq(st["planets"].size(), 6, "debug_state planets")
	# debugSeedColonies (TS:1275-1287): the docstring says 'three nearest lush
	# worlds' but the code takes the FIRST THREE non-barren uncolonized planets
	# in order (0, 1, 2 — the quirk is pinned as coded)
	sim.debug_seed_colonies()
	for i in 6:
		var p: Dictionary = sim.planets[i]
		if i <= 2:
			eq(float(p["colony"]["pop"]), 1.0, "planet %d colony pop 1 (TS:1283)" % i)
			eq(float(p["colony"]["generations"]), 0.0, "planet %d generations 0 (TS:1283)" % i)
			var sp_list: Array = p["eco"].species
			var last: Dictionary = sp_list[sp_list.size() - 1]
			eq(bool(last["kin"]), true, "planet %d seeded line is kin (TS:1282)" % i)
			approx(float(last["pop"]), 6.0, "planet %d seeded pop 6 (TS:1282)" % i)
			ok(String(last["name"]).ends_with(" (seed)"), "planet %d seeded name ' (seed)' (TS:1282)" % i)
		else:
			eq(p["colony"], null, "planet %d untouched (barren 3/5; the cap spent on 0-2, TS:1278)" % i)
	# the seeder persisted (TS:1286)
	ok(ctx.flags.has("spaceWorld"), "debug_seed_colonies → persistColonies (TS:1286)")
	# a second run: planets 0-2 are now colonized, 3/5 barren — but planet 4
	# (lush, uncolonized) IS seeded: the cap of 3 restarts per call (TS:1278)
	var eco_counts: Array = []
	for i in 6:
		eco_counts.append(sim.planets[i]["eco"].species.size() if sim.planets[i]["eco"] != null else 0)
	sim.debug_seed_colonies()
	for i in 6:
		var now_n: int = sim.planets[i]["eco"].species.size() if sim.planets[i]["eco"] != null else 0
		if i == 4:
			eq(now_n, int(eco_counts[i]) + 1, "second call seeds planet 4 (the cap restarts, TS:1278)")
			eq(float(sim.planets[4]["colony"]["pop"]), 1.0, "planet 4 colony pop 1 (TS:1283)")
		else:
			eq(now_n, int(eco_counts[i]), "planet %d untouched by the second call (TS:1279)" % i)
