# Tests for game/space/space_sim.gd — the space stage sim core.
# PART 1 (M6 T1): constructor seeding (the 6-planet system at a pinned seed —
# parallel-branch replay, the boot-order branch pin), makePlanetEco (floraCap
# by kind, the archetype diet dial pulls, volcanic/ocean modifiers,
# titan/swarm bonus AFTER the roster), the onEnter restore whitelist (EVERY
# guard), persistColonies + the CONTINUE round-trip, ship physics (cursor
# deadzone, WASD/arrows, accel/drag integration, engine particles), the ff
# timeScale block (eco.tick dt·26, the ecoMods wire, extinctions/speciations
# toasts, generations), orbits + colony logistic growth (the cap-120 brake),
# sun danger + hull regen windows, debug seams.
# PART 2 (M6 T2): the planet-panel interaction dispatch (the
# disabled-button-owns-click rule + uiHold), tryAbduct/finishAbduct (the gate
# ladder, the pay-curve ledger, the last-member extinction), seedNearest
# (barren→lush), mergeCargo (crossover opts at a pinned stream),
# borrowedFleshGraft (never-downgrade), pirates (chase/ttl/click-to-shoot),
# black holes (pull math), ship death (the bill + cull), the R/G/V keys, the
# chaos ctx WITH onEnd (tribute unpaid→pirates), the finale/ending state
# machine, cooldowns + the 5 s persist cadence, the ff e2e through a REAL eco.
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
const PartsLib := preload("res://src/evo/parts.gd")
const SpaceEventsLib := preload("res://src/game/space/space_events.gd")

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

	# persist_colonies calls to_json on every non-null eco — the part-2
	# persist cadence reaches the recorder in long-update tests
	func to_json() -> Dictionary:
		return {"species": [], "flora": 0.0, "floraCap": 0.0}


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
		"gotos": [], "saves": 0, "cursors": [], "bursts": [], "notes": [],
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
		# part-2 hooks (additive — the part-1 tests never asserted these)
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"hud_set_abilities": func(list): rec["abilities"].append(list),
		"fx_burst": func(x, y, n, o): rec["bursts"].append([x, y, n, o]),
		"set_cursor": func(state): rec["cursors"].append(state),
		"storyteller_note_chaos_event": func(t): rec["notes"].append(t),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = SpaceSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec, "rng": rng, "hooks": hooks}


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
	# the deck is the real factory deck now (task 3): the constructor folds
	# ctx.world in (TS:98) — compared against the factory on the SAME world
	var deck_exp: Array = SpaceEventsLib.make_space_chaos_events(ctx.world)
	var ids_exp: Array = []
	for d in deck_exp:
		ids_exp.append(d["id"])
	var ids_got: Array = []
	for d in sim.chaos.defs:
		ids_got.append(d["id"])
	eq(ids_got, ids_exp, "chaos deck = the factory deck for ctx.world (task 3)")
	ok(ids_got.size() >= 4, "the deck carries at least the 4 baseline defs")
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
	# a different world seed rebuilds the scheduler + updates deckSeed, folding
	# the (seed-changed) world into the deck (task 3)
	m["ctx"].world["seed"] = SEED + 1
	sim.on_enter()
	ok(not is_same(sim.chaos, old), "world seed changed → scheduler rebuilt (C1, TS:184)")
	eq(int(sim.deckSeed), SEED + 1, "deckSeed updated (TS:185)")
	eq(sim.chaos.defs.size(),
			SpaceEventsLib.make_space_chaos_events(m["ctx"].world).size(),
			"rebuilt deck folds the world in (task 3)")


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


func test_restore_ledger_and_ending_inside_the_gate() -> void:
	# GATE PLACEMENT (the T1-review AST fact): the abductCount + ending blocks
	# nest INSIDE the shapes gate (TS:201-265 — the trailing :265 closer closes
	# the gate; the TS source's 8-space indentation there is a formatting
	# artifact) — a corrupt/wrong-length blob discards the WHOLE restore incl.
	# the ledger and the won-run state
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# a SHAPES-FAILING blob (planets not an array) restores NOTHING
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob("notarray", {
		"abductCount": {"Glorbus": 3},
		"endingDone": true, "endingDismissed": true,
	}))
	sim.on_enter()
	eq(sim.planets.size(), 6, "planets untouched by the shapes failure")
	eq(sim.abductCount, {}, "corrupt shapes → the ledger is NOT restored (inside the gate, TS:201-265)")
	eq(bool(sim.endingDone), false, "corrupt shapes → endingDone NOT restored (TS:257)")
	eq(bool(sim.endingDismissed), false, "corrupt shapes → endingDismissed NOT restored")
	eq(float(sim.endingT), 0.0, "endingT untouched by the shapes failure")
	eq(float(sim.dismissT), 0.0, "dismissT untouched by the shapes failure")
	eq(sim.finale, null, "corrupt shapes → no finale re-arm (TS:263)")
	# a length mismatch discards the ledger too
	var m2 := _mk_sim(SEED, m["ctx"])
	var sim2: Variant = m2["sim"]
	var gen_r: float = float(sim2.planets[0]["r"])
	var rows5: Array = [_row({}), _row({}), _row({}), _row({}), _row({})]  # 5 rows
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows5, {"abductCount": {"Zor": 1}}))
	sim2.on_enter()
	eq(float(sim2.planets[0]["r"]), gen_r, "length mismatch → planets untouched (TS:201)")
	eq(sim2.abductCount, {}, "length mismatch → ledger NOT restored (inside the gate)")
	# through a VALID shapes gate the ledger + ending restore as before
	var rows6: Array = [_row({}), _row({}), _row({}), _row({}), _row({}), _row({})]
	var m3 := _mk_sim(SEED, m["ctx"])
	var sim3: Variant = m3["sim"]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows6, {
		"abductCount": {"Glorbus": 3},
		"endingDone": true, "endingDismissed": true,
	}))
	sim3.on_enter()
	eq(int(sim3.abductCount["Glorbus"]), 3, "valid shapes → the ledger restores (TS:253-255)")
	eq(bool(sim3.endingDone), true, "endingDone latches (TS:257-264)")
	eq(bool(sim3.endingDismissed), true, "endingDismissed === true restored (TS:259)")
	eq(float(sim3.endingT), 99.0, "dismissed → endingT 99 (TS:260)")
	eq(float(sim3.dismissT), 99.0, "dismissed → dismissT 99 (TS:261)")
	eq(sim3.finale, null, "a dismissed ending sleeps — finale null (TS:263)")
	# a WON but UNDISMISSED run re-arms the finale orb (valid shapes)
	var m4 := _mk_sim(SEED, m["ctx"])
	var sim4: Variant = m4["sim"]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows6, {
		"endingDone": true, "endingDismissed": false,
	}))
	sim4.on_enter()
	eq(bool(sim4.endingDone), true, "endingDone latches")
	eq(bool(sim4.endingDismissed), false, "endingDismissed false on a non-true saved value (TS:259)")
	eq(float(sim4.endingT), 0.0, "endingT UNCHANGED when not dismissed (TS:260 ternary)")
	eq(float(sim4.dismissT), 0.0, "dismissT unchanged when not dismissed (TS:261)")
	var fin: Dictionary = sim4.finale
	ok(fin != null, "an undismissed won run re-arms the finale (TS:263)")
	eq(float(fin["x"]), 0.0, "finale x 0 (TS:263)")
	eq(float(fin["y"]), -1900.0, "finale y −1900 (TS:263)")
	eq(bool(fin["active"]), true, "finale active (TS:263)")
	eq(float(fin["t"]), 0.0, "finale t 0 (TS:263)")
	# endingDismissed without endingDone → NOTHING (the conjunction, TS:257)
	var m5 := _mk_sim(SEED, m["ctx"])
	var sim5: Variant = m5["sim"]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows6, {"endingDismissed": true}))
	sim5.on_enter()
	eq(bool(sim5.endingDone), false, "endingDone false without a saved true (TS:257)")
	eq(sim5.finale, null, "finale stays null (the fresh value)")
	# a non-object abductCount is rejected; the empty object IS taken
	# (JS object truthiness — TS:253; valid shapes)
	var m6 := _mk_sim(SEED, m["ctx"])
	var sim6: Variant = m6["sim"]
	sim6.abductCount = {"Keep": 1}
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows6, {"abductCount": 5}))
	sim6.on_enter()
	eq(int(sim6.abductCount["Keep"]), 1, "numeric abductCount rejected (TS:253)")
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(rows6, {"abductCount": {}}))
	sim6.on_enter()
	eq(sim6.abductCount, {}, "EMPTY abductCount object taken — JS {} is truthy (TS:253)")
	# the TS shapes predicate admits ARRAY rows (typeof 'object') — the gate
	# STAYS OPEN: the array row restores nothing per-field, but the Dictionary
	# rows, cargo and the ledger all still ride (TS:200-201/247)
	var m7 := _mk_sim(SEED, m["ctx"])
	var sim7: Variant = m7["sim"]
	var gen_name1: String = String(sim7.planets[1]["name"])
	var mixed: Array = [_row({"name": "Valid-1"}), [], _row({}), _row({}), _row({}), _row({})]
	ctx.flags["spaceWorld"] = JSON.stringify(_whitelist_blob(mixed, {
		"abductCount": {"Arr": 7}, "cargo": [{"genome": {}, "name": "Rider"}],
	}))
	sim7.on_enter()
	eq(int(sim7.abductCount["Arr"]), 7, "an array row keeps the gate OPEN — the ledger rides (TS:200)")
	eq(sim7.cargo.size(), 1, "an array row keeps the gate OPEN — cargo rides (TS:247)")
	eq(String(sim7.cargo[0]["name"]), "Rider", "cargo restored past the array row")
	eq(String(sim7.planets[1]["name"]), gen_name1, "the array row restores nothing per-field (undefined reads, TS:203)")
	eq(String(sim7.planets[0]["name"]), "Valid-1", "the Dictionary rows restore normally")


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
	# compare against the DERIVED rebuild expectation — the ORIGINAL sim's
	# planet 3 eco is null here (only the restore rebuilds it; the T1-review
	# Important 3: dereferencing the original read Nil and crashed mid-body)
	eq(String(sim2.planets[3]["eco"].species[0]["name"]),
		"%s colonists" % String(sim.planets[3]["name"]),
		"round-trip: colonist line name (the rebuild rule at the RESTORED name, TS:244)")


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
	# FORCED-SPAWN leg: dt 1.0 → chance(dt·40) = chance(40) — next() < 40 is
	# ALWAYS true (next() ∈ [0,1)), so every payload pin runs deterministically
	# at the pinned seed (the T1-review Important 2: at dt 1/60 they silently
	# skipped — 2 checks instead of 9). The probe replays the frame's jitter
	# draws (the forced chance consumes draw 1, the two ranges follow).
	var dt := 1.0
	var p: Variant = _probe(sim)
	p.next()  # the forced chance draw
	var d_vx: float = p.next()
	var d_vy: float = p.next()
	sim.update(dt, _inp({"keys_held": ["KeyW"]}))
	eq(m["rec"]["spawns"].size(), 1, "exactly one engine spawn per thrusting frame (TS:353)")
	var s: Dictionary = m["rec"]["spawns"][0]
	# the ship integrates FIRST (accel 420, drag exp(−1.1·dt)) — KeyW: svy
	# −420 → ·exp(−1.1) → sy −900 − 420·exp(−1.1); sx stays 0 (svx 0)
	var sy_at_draw: float = -900.0 + (-420.0 * exp(-1.1)) * dt
	var back: float = -PI / 2.0 + PI
	approx(float(s["x"]), 0.0 + cos(back) * 14.0, "spawn x = ship + cos(back)·14 (TS:356)")
	approx(float(s["y"]), sy_at_draw + sin(back) * 14.0, "spawn y = the MOVED ship + sin(back)·14 (TS:356)")
	approx(float(s["vx"]), cos(back) * 120.0 + (-20.0 + d_vx * 40.0), "spawn vx = cos(back)·120 + rng(−20,20) (TS:357)")
	approx(float(s["vy"]), sin(back) * 120.0 + (-20.0 + d_vy * 40.0), "spawn vy = sin(back)·120 + rng(−20,20) (TS:358)")
	eq(float(s["ttl"]), 0.5, "ttl 0.5 (TS:359)")
	eq(float(s["size"]), 3.0, "size 3 (TS:359)")
	eq(String(s["kind"]), "dot", "kind dot (TS:359)")
	eq(String(s["color"]), "hsl(200 100% 70% / 1.00)", "color hsl(200,1,0.7) (TS:359)")
	eq(float(s["drag"]), 3.0, "drag 3 (TS:360)")
	# CADENCE leg at dt 1/60: the probe replays the frame's draws BEFORE the
	# update (independent derivation) — whichever branch the pinned seed
	# picks, its stream cadence asserts.
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var dt2 := 1.0 / 60.0
	var p2: Variant = _probe(sim2)
	var d2: float = p2.next()
	sim2.update(dt2, _inp({"keys_held": ["KeyW"]}))
	if d2 >= dt2 * 40.0:
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
	eq(float(sim.invuln), 1.5, "invuln decayed 2−dt=1.5 — the part-2 cooldown block landed (TS:605)")
	# inside the sun window with invuln 0: −30·dt, hurtT 1 — the part-2
	# cooldown decay (dt·3) then eats it IN THE SAME FRAME: max(0, 1−1.5) = 0
	# (the TS :380-set → :606-decay composite; the SET itself is pinned in the
	# black-hole test at dt 1/60 where the decay leaves 0.95)
	sim.invuln = 0.0
	sim.update(0.5, _inp())
	approx(float(sim.shp), 100.0 - 30.0 * 0.5, "sun damage −30·dt (TS:379)")
	eq(float(sim.hurtT), 0.0, "hurtT set 1 mid-frame, decayed to 0 by dt·3 (TS:380→:606)")
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


# ===================================================================================
# PART 2 (M6 T2) — interactions, gene lab, hazards, finale (TS:391-632 + methods)
# ===================================================================================

# A duck-typed chaos scheduler stand-in: records the update call so the test
# can pin the FULL ctx payload (incl. onEnd — the tribute rule) and fire the
# recorded hooks directly.
class ChaosRec:
	var calls: Array = []

	func update(dt: float, stage: Variant, ctx: Dictionary, hooks: Dictionary) -> void:
		calls.append({"dt": dt, "ctx": ctx, "hooks": hooks})

	func active_events() -> Array:
		return []


# ---- part-2 fixtures ----------------------------------------------------------------

# Panel rect row in the TS panelRects shape (TS:1192) — the STAGE writes these
# (task 5); the tests write them the same way.
func _rect(action: String, enabled: bool, x: float, y: float, w: float, h: float) -> Dictionary:
	return {"action": action, "enabled": enabled, "r": {"x": x, "y": y, "w": w, "h": h}}


# Pin planet i at world (x, y): orbitSpeed 0 freezes the position and the
# orbit block fills x/y BEFORE the panel block reads them (no warm-up update);
# x/y are also set directly for tests that never update.
func _place_planet(sim_v: Variant, i: int, x: float, y: float, r: float = 50.0) -> Dictionary:
	var p: Dictionary = sim_v.planets[i]
	p["angle"] = atan2(y, x)
	p["orbitR"] = sqrt(x * x + y * y)
	p["orbitSpeed"] = 0.0
	p["r"] = r
	p["x"] = x
	p["y"] = y
	return p


# Push every planet except `keep` out to orbit 5000 so nearestPlanet is unambiguous.
func _isolate_planet(sim_v: Variant, keep: int) -> void:
	for i in 6:
		if i != keep:
			sim_v.planets[i]["orbitR"] = 5000.0
			sim_v.planets[i]["orbitSpeed"] = 0.0


# Craft a hermetic eco on planet i with species at the given pops (each a
# clamped default genome). The eco rides its own fixed rng — the STAGE stream
# stays untouched (only rng.pick in finishAbduct draws from it).
func _craft_eco(sim_v: Variant, i: int, pops: Array) -> Variant:
	var eco: Variant = EcoScript.new(RngLib.new_from(4242 + i))
	for pop in pops:
		eco.add_species(GenomeLib.clone_genome(GenomeLib.default_genome()), float(pop))
	sim_v.planets[i]["eco"] = eco
	return eco


# ---- the panel interaction dispatch (TS:391-434) -------------------------------------

func test_panel_dispatch_ladder() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	_place_planet(sim, 0, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 0)
	sim.sx = 900.0  # d 100 < r 50 + 130 → inside the interaction range
	sim.sy = 0.0
	sim.invuln = 0.0

	# EMPTY panel_rects: the near-planet gate holds but the ladder no-ops
	# gracefully — no cursor, the click passes through unconsumed, uiHold false
	var inp_e: Dictionary = _inp({"clicked": true, "down": true, "mx": 750.0, "my": 110.0})
	sim.update(1.0 / 60.0, inp_e)
	eq(rec["cursors"], [], "empty panel_rects → no cursor (the dispatch no-ops)")
	eq(bool(sim.uiHold), false, "empty panel_rects → uiHold false")
	eq(bool(inp_e.get("take_click", false)), false, "empty panel_rects → the click NOT consumed")
	# the dna is untouched by the empty-panel click
	eq(int(ctx.dna), 40, "no action fired through the empty panel")

	# hover feedback BEFORE any click (TS:394-403) — an ENABLED rect under the
	# pointer shows the cursor on a no-click frame; a DISABLED one does not
	sim.panel_rects = [_rect("abduct", true, 700.0, 100.0, 200.0, 40.0)]
	rec["cursors"].clear()
	sim.update(1.0 / 60.0, _inp({"mx": 750.0, "my": 110.0}))
	eq(rec["cursors"], ["pointer"], "hover over an enabled rect → setCursor('pointer') (TS:398-400)")
	rec["cursors"].clear()
	sim.panel_rects = [_rect("abduct", false, 700.0, 100.0, 200.0, 40.0)]
	sim.update(1.0 / 60.0, _inp({"mx": 750.0, "my": 110.0}))
	eq(rec["cursors"], [], "hover over a DISABLED rect → no cursor (TS:398 gate)")

	# DISABLED BUTTON OWNS ITS CLICK (TS:412-415): overPanel swallows the
	# press (no consume, no action), uiHold = overPanel && isDown
	sim.panel_rects = [_rect("abduct", false, 700.0, 100.0, 200.0, 40.0)]
	var inp_d: Dictionary = _inp({"clicked": true, "down": true, "mx": 750.0, "my": 110.0})
	sim.update(1.0 / 60.0, inp_d)
	eq(rec["cursors"], [], "disabled rect click → no cursor from the dispatch loop (enabled gate)")
	eq(bool(inp_d.get("take_click", false)), false, "disabled rect does NOT consume the click (TS:415 continue)")
	eq(bool(sim.uiHold), true, "uiHold = (consumed||overPanel) && isDown → overPanel alone holds it (TS:431)")
	eq(rec["toasts"], [], "disabled rect fires NO action")
	# the hold persists into the next frame (the write only happens on click
	# frames) and suppresses the cursor thrust (TS:329 reads the flag first)
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(1.0 / 60.0, _inp({"down": true, "wx": 1200.0, "wy": 0.0, "mx": 750.0, "my": 110.0}))
	eq(bool(sim.uiHold), true, "uiHold persists while held (the write is click-frame-only, TS:431)")
	eq(float(sim.thrust), 0.0, "uiHold suppresses the cursor pull (TS:329)")
	# release → the :434 reset
	sim.update(1.0 / 60.0, _inp({"down": false}))
	eq(bool(sim.uiHold), false, "!isDown → uiHold false (TS:434)")

	# enabled dispatch — jettison: cargo.pop + toast + persist (TS:424-428)
	ctx.flags.erase("spaceWorld")
	sim.panel_rects = [_rect("jettison", true, 700.0, 100.0, 200.0, 40.0)]
	sim.cargo = [{"genome": GenomeLib.default_genome(), "name": "Spec A"}]
	var inp_j: Dictionary = _inp({"clicked": true, "down": true, "mx": 750.0, "my": 110.0})
	sim.update(1.0 / 60.0, inp_j)
	eq(sim.cargo.size(), 0, "jettison pops the last cargo row (TS:425)")
	eq(String(rec["toasts"][0][0]), "Spec A released back to the void", "jettison toast text (TS:426)")
	eq(String(rec["toasts"][0][1]), "info", "jettison toast kind")
	eq(String(rec["toasts"][0][2]), "🗑", "jettison toast icon")
	eq(bool(inp_j.get("take_click", false)), true, "enabled rect CONSUMES the click (TS:416)")
	eq(bool(sim.uiHold), true, "consumed click while held → uiHold true (TS:431)")
	ok(ctx.flags.has("spaceWorld"), "jettison persists (TS:427)")
	eq(rec["audio"][0], ["click", 1.0, 0.0], "audio.play('click') — the default vol 1 pan 0 (TS:418)")
	# hover loop + dispatch loop both cursor on the click frame (TS:398 + :410)
	eq(rec["cursors"], ["pointer", "pointer"], "click frame cursors: hover + dispatch (TS:398/410)")
	# jettison with EMPTY cargo: pop → null → no toast, persist still runs
	rec["toasts"].clear()
	ctx.flags.erase("spaceWorld")
	sim.update(1.0 / 60.0, _inp({"clicked": true, "down": false, "mx": 750.0, "my": 110.0}))
	eq(rec["toasts"], [], "jettison of an empty cargo → no toast (the dropped guard, TS:426)")
	ok(ctx.flags.has("spaceWorld"), "jettison of an empty cargo STILL persists (TS:427)")
	eq(bool(sim.uiHold), false, "overPanel && !isDown → uiHold false (TS:431)")

	# enabled dispatch — scan on a scanned planet under cooldown: the recharge
	# toast, cd UNCHANGED (the early return precedes the reset, TS:1249-1251)
	sim.planets[0]["scanned"] = true
	sim.resurveyCd = 9.0
	sim.panel_rects = [_rect("scan", true, 700.0, 100.0, 200.0, 40.0)]
	sim.update(1.0 / 60.0, _inp({"clicked": true, "down": false, "mx": 750.0, "my": 110.0}))
	ok(_toasted(rec, "Survey instruments recharging"), "cooldown scan → the recharge toast (TS:1250)")
	approx(float(sim.resurveyCd), 9.0 - 1.0 / 60.0,
		"cooldown scan leaves resurveyCd at 9 minus the :550 decay (TS:1251 return)")

	# OVERLAPPING rects: the FIRST inside rect dispatches and breaks (TS:429)
	sim.shp = 50.0
	ctx.dna = 100
	sim.panel_rects = [_rect("abduct", true, 700.0, 100.0, 200.0, 40.0),
		_rect("repair", true, 700.0, 100.0, 200.0, 40.0)]
	sim.update(1.0 / 60.0, _inp({"clicked": true, "down": false, "mx": 750.0, "my": 110.0}))
	approx(float(sim.beamT), 1.4 - 1.0 / 60.0,
		"the first inside rect (abduct) dispatched — beamT armed then −dt (TS:419/503)")
	eq(float(sim.shp), 50.0, "the second rect (repair) NEVER ran — the break (TS:429)")
	sim.beamT = 0.0
	sim.beamTarget = null

	# OUT OF RANGE: no near-planet gate → the ladder never runs at all
	sim.sx = 0.0
	sim.sy = -900.0
	rec["cursors"].clear()
	rec["toasts"].clear()
	sim.panel_rects = [_rect("abduct", true, 700.0, 100.0, 200.0, 40.0)]
	var inp_far: Dictionary = _inp({"clicked": true, "down": true, "mx": 750.0, "my": 110.0})
	sim.update(1.0 / 60.0, inp_far)
	eq(rec["cursors"], [], "out of range → no hover cursor (TS:393 gate)")
	eq(bool(inp_far.get("take_click", false)), false, "out of range → the click passes through (TS:393 gate)")
	eq(bool(sim.uiHold), false, "out of range → uiHold untouched")
	eq(rec["toasts"], [], "out of range → no action")

	# PANEL CLICKS OUTRANK PIRATE SHOOTING (TS:391): one click under BOTH the
	# panel rect (mx/my) and a pirate (wx/wy) — the panel consumes it first
	sim.sx = 900.0
	sim.sy = 0.0
	sim.pirates = [{"x": 900.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	sim.update(1.0 / 60.0, _inp({"clicked": true, "down": false, "mx": 750.0, "my": 110.0,
		"wx": 900.0, "wy": 0.0}))
	eq(float(sim.pirates[0]["hp"]), 140.0, "the panel consumed the click — the pirate is NOT shot (TS:391 order)")
	sim.pirates = []
	sim.pirateTtl = []

	# the ability slots ride every update (TS:626-631)
	sim.beamT = 1.0
	sim.cargo = [{"genome": GenomeLib.default_genome(), "name": "a"}, {"genome": GenomeLib.default_genome(), "name": "b"}]
	sim.update(1.0 / 60.0, _inp({"keys_held": ["KeyF"]}))
	var ab: Array = rec["abilities"][rec["abilities"].size() - 1]
	eq(ab.size(), 4, "four ability slots (TS:626-631)")
	eq(String(ab[0]["key"]), "R", "slot R (TS:627)")
	eq(String(ab[0]["icon"]), "🛸", "slot R icon")
	eq(bool(ab[0]["active"]), true, "R active while beamT > 0 (TS:627)")
	eq(String(ab[1]["key"]), "F", "slot F (TS:628)")
	eq(bool(ab[1]["active"]), true, "F active while ffHold > 0 (TS:628)")
	eq(String(ab[2]["key"]), "G", "slot G (TS:629)")
	eq(bool(ab[2]["active"]), true, "G active with cargo ≥ 2 (TS:629)")
	eq(String(ab[3]["key"]), "LMB", "slot LMB (TS:630)")
	eq(String(ab[3]["icon"]), "🔫", "slot LMB icon")
	ok(not ab[3].has("active"), "LMB carries NO active key (TS:630)")
	eq(float(ab[0]["cd"]), 0.0, "cd 0 (TS:627)")


# ---- tryAbduct / finishAbduct (TS:644-707) -------------------------------------------

func test_try_abduct_gates_and_ledger() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	var eco: Variant = _craft_eco(sim, 0, [3.0])
	var sp1: Dictionary = eco.species[0]
	_place_planet(sim, 0, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 0)
	sim.sx = 900.0
	sim.sy = 0.0
	sim.invuln = 0.0

	# the beamT gate: an active beam blocks re-abduction (TS:645) — the
	# countdown still ticks in the same frame (1.4-style decay: 1 − dt)
	sim.beamT = 1.0
	var st0: int = int(sim.rng.state())
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyR"]}))
	approx(float(sim.beamT), 1.0 - 1.0 / 60.0, "beamT > 0 → tryAbduct returns; the countdown still ticks (TS:645/503)")
	eq(sim.beamTarget, null, "no beamTarget while the beam runs")
	eq(int(sim.rng.state()), st0, "the beamT gate draws NOTHING from the stage stream")

	# DISTANCE FIRST (TS:646-647): out of range with FULL cargo → the distance
	# toast, NOT the cargo toast — the wrong-lesson comment
	sim.beamT = 0.0
	sim.sx = 0.0
	sim.sy = -900.0
	var g: Dictionary = GenomeLib.default_genome()
	sim.cargo = [{"genome": g, "name": "1"}, {"genome": g, "name": "2"},
		{"genome": g, "name": "3"}, {"genome": g, "name": "4"}]
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(rec["toasts"][0], [tr("Fly closer to a planet to abduct"), "info", "🛸"],
		"distance FIRST — the full-cargo ship gets the distance toast (TS:650-651)")
	eq(sim.beamTarget, null, "no beam out of range")

	# the cargo-4 gate (TS:654-656) — the ship back in range of planet 0
	sim.sx = 900.0
	sim.sy = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(rec["toasts"][1], [tr("Cargo full — SEED a world, SPLICE genes (G), or JETTISON from the planet panel"),
		"info", "📦"], "cargo 4 → the cargo-full toast (TS:655)")
	eq(sim.cargo.size(), 4, "cargo untouched by the refusal")

	# the eco-null gate on a barren planet (TS:658-660)
	sim.cargo = []
	_place_planet(sim, 3, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 3)
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(rec["toasts"][2], [tr("No life to abduct here"), "info", "🛸"], "eco null → the no-life toast (TS:659)")

	# the living-empty gate: an all-extinct eco (TS:662-665)
	_place_planet(sim, 0, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 0)
	eco.species[0]["extinct"] = true
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(rec["toasts"][3], [tr("No life to abduct here"), "info", "🛸"], "living empty → the no-life toast (TS:664)")
	eco.species[0]["extinct"] = false

	# SUCCESS: the beam arms with NO stage-stream draw (TS:667-669) — the
	# countdown then ticks in the same frame (1.4 − dt)
	st0 = int(sim.rng.state())
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyR"]}))
	ok(is_same(sim.beamTarget, sim.planets[0]), "beamTarget = the nearest planet (TS:667)")
	approx(float(sim.beamT), 1.4 - 1.0 / 60.0, "beamT 1.4 armed, then −dt in the same frame (TS:668/503)")
	eq(rec["audio"][0], ["warp", 0.6, 0.0], "audio warp 0.6 (TS:669)")
	eq(int(sim.rng.state()), st0, "arming the beam draws NOTHING from the stage stream")

	# the beam countdown + finish IN THE SAME FRAME (R then beamT −dt, TS:501-507):
	# dt 2.0 > 1.4 → beamT lands NEGATIVE (no clamp — the TS verbatim read)
	var probe: Variant = _probe(sim)
	probe.next()  # the finishAbduct rng.pick draw
	sim.cargo = []
	ctx.dna = 0
	ctx.world_stats["extinctions"] = 0
	ctx.flags.erase("spaceWorld")
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	# the arming frame left beamT at 1.4 − dt; this frame: −dt again →
	# (1.4 − 1/60) − 2.0 — NEGATIVE, unclamped (the TS verbatim read)
	approx(float(sim.beamT), (1.4 - 1.0 / 60.0) - 2.0, "beamT lands NEGATIVE, unclamped (TS:503)")
	eq(sim.beamTarget, null, "finishAbduct cleared the target (TS:705)")
	eq(sim.cargo.size(), 1, "cargo push (TS:701)")
	eq(String(sim.cargo[0]["name"]), String(sp1["name"]), "cargo name = the species name (TS:701)")
	eq(int(sim.cargo[0]["genome"]["jaw"]), int(sp1["genome"]["jaw"]), "cargo genome = cloneGenome (TS:701)")
	eq(int(ctx.dna), 10, "FIRST catch pays 10 (TS:689)")
	eq(int(sim.abductCount["0:%s" % str(sp1["id"])]), 1, "the ledger key '{p.id}:{sp.id}' counts 1 (TS:686-688)")
	eq(rec["toasts"][4], ["%s %s +10" % [tr("Abducted:"), String(sp1["name"])], "good", "🛸"],
		"the +10 abducted toast (TS:699)")
	eq(int(ctx.world_stats["extinctions"]), 0, "a healthy catch is NOT an extinction")
	ok(ctx.flags.has("spaceWorld"), "finishAbduct FLUSHES the save (the 60s-autosave-lag comment, TS:706)")
	eq(int(sim.rng.state()), int(probe.state()), "the finish consumed exactly the pick draw")
	var bestiary_key: String = ""
	for k in ctx.bestiary:
		if String(ctx.bestiary[k]["name"]) == String(sp1["name"]):
			bestiary_key = k
	ok(bestiary_key != "", "discover(genome, name, 'space', kin) ran (TS:703)")
	if bestiary_key != "":
		eq(String(ctx.bestiary[bestiary_key]["stage"]), "space", "the discovery rides stage 'space' (TS:703)")

	# the pay curve: repeats pay 3 (TS:684-689)
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(int(ctx.dna), 13, "second catch pays 3 (TS:689)")
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(int(ctx.dna), 16, "third catch pays 3 (TS:689)")
	eq(int(sim.abductCount["0:%s" % str(sp1["id"])]), 3, "the ledger climbed to 3 (TS:688)")
	ok(_toasted(rec, "+3"), "the +3 repeat toast (TS:699)")

	# the LAST MEMBER (TS:690-697): pop 1 → pop 0 + extinct + bump_extinction
	# + the gone-from-this-world toast — a player-caused extinction counted
	# HERE (it never passes through eco.tick)
	var eco2: Variant = _craft_eco(sim, 1, [1.0])
	var sp_last: Dictionary = eco2.species[0]
	_place_planet(sim, 1, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 1)
	sim.cargo = []
	sim.abductCount = {}
	ctx.dna = 0
	ctx.world_stats["extinctions"] = 0
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	approx(float(sp_last["pop"]), 0.0, "the last member's pop clamped to 0 (TS:691)")
	eq(bool(sp_last["extinct"]), true, "the last member goes extinct (TS:692)")
	eq(int(ctx.world_stats["extinctions"]), 1, "bumpExtinction for the last member (TS:696)")
	eq(rec["toasts"][rec["toasts"].size() - 1],
		["%s %s — %s" % [tr("Abducted:"), String(sp_last["name"]),
			tr("that species is now gone from this world")], "bad", "🛸"],
		"the gone-from-this-world toast (TS:697)")
	eq(sim.cargo.size(), 1, "the genome still rides to cargo (TS:701)")
	eq(int(ctx.dna), 10, "the first catch of the new species pays 10 (the pay curve precedes the pop check)")
	# re-farm attempt: living() is now EMPTY → the tryAbduct gate, not finishAbduct
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(rec["toasts"][rec["toasts"].size() - 1], [tr("No life to abduct here"), "info", "🛸"],
		"an extinct species cannot be re-farmed (TS:664 gate)")

	# the infinite-DNA-faucet pin (TS:674-675): a pop-0.5 leftover is NOT a
	# candidate — the beam arms (living non-empty) but finish pays NOTHING
	var eco3: Variant = _craft_eco(sim, 2, [0.5])
	_place_planet(sim, 2, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 2)
	sim.cargo = []
	ctx.dna = 0
	sim.abductCount = {}
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(rec["toasts"][rec["toasts"].size() - 1], [tr("Nothing left to abduct here"), "info", "🛸"],
		"pop 0.5 is not a candidate → 'Nothing left' (TS:676-680)")
	eq(sim.cargo.size(), 0, "no cargo from a starved roster")
	eq(int(ctx.dna), 0, "no DNA from a starved roster (the infinite-DNA-faucet pin)")
	eq(sim.beamTarget, null, "the failed finish cleared the target (TS:679)")


# ---- seedNearest (TS:709-733) ---------------------------------------------------------

func test_seed_nearest() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	_place_planet(sim, 3, 1000.0, 0.0, 50.0)  # planet 3 is the KINDS-ring barren
	_isolate_planet(sim, 3)
	sim.invuln = 0.0
	var item: Dictionary = {"genome": GenomeLib.default_genome(), "name": "Pilgrim"}

	# the distance gate (TS:712-715)
	sim.cargo = [item]
	sim.sx = 0.0
	sim.sy = -900.0
	sim.seed_nearest()
	eq(rec["toasts"][0], [tr("Fly closer to seed"), "info", "🌱"], "out of range → 'Fly closer to seed' (TS:713)")
	eq(sim.cargo.size(), 1, "cargo untouched by the refusal")
	eq(int(ctx.dna), 40, "dna untouched by the refusal")

	# the spendDna(20) refusal (TS:716-719)
	sim.sx = 900.0
	sim.sy = 0.0
	ctx.dna = 19
	ctx.flags.erase("spaceWorld")
	sim.seed_nearest()
	eq(rec["toasts"][1], [tr("Seeding costs 20 DNA"), "bad", "🌱"], "dna 19 → the cost toast (TS:717)")
	eq(int(ctx.dna), 19, "dna unchanged on the refusal")
	eq(sim.cargo.size(), 1, "cargo unchanged on the refusal")
	eq(ctx.flags.has("spaceWorld"), false, "the refusal does NOT persist (TS:718 return)")

	# the empty-cargo gate (TS:711)
	ctx.dna = 100
	sim.cargo = []
	sim.seed_nearest()
	eq(int(ctx.dna), 100, "empty cargo → no spend (TS:711)")

	# SUCCESS on the barren planet: fresh eco, floraCap 100 (not volcanic),
	# flora 0.6·cap, barren→lush, colony {0, 0}, the SEEDED banner (TS:720-732)
	sim.cargo = [{"genome": GenomeLib.default_genome(), "name": "Pilgrim"}]
	var probe: Variant = _probe(sim)
	probe.branch()  # TS:722 — the fresh Ecosystem's ONE branch draw
	sim.seed_nearest()
	var p3: Dictionary = sim.planets[3]
	ok(p3["eco"] != null, "the barren planet gained an eco (TS:722)")
	approx(float(p3["eco"].flora_cap), 100.0, "barren floraCap 100 (the non-volcanic branch, TS:723)")
	approx(float(p3["eco"].flora), 60.0, "flora 0.6·cap (TS:724)")
	eq(String(p3["kind"]), "lush", "barren → lush (TS:725)")
	eq(p3["eco"].species.size(), 1, "one seeded species (TS:727)")
	var sp: Dictionary = p3["eco"].species[0]
	eq(String(sp["name"]), "Pilgrim", "the species carries the cargo name (TS:727)")
	eq(bool(sp["kin"]), true, "the seeded line is kin (TS:727)")
	approx(float(sp["pop"]), 5.0, "seeded pop 5 (TS:727)")
	eq(p3["colony"], {"pop": 0.0, "generations": 0.0}, "colony init {pop 0, generations 0} (TS:729)")
	eq(rec["banners"][0], {"title": "%s SEEDED" % String(p3["name"]),
		"subtitle": "Pilgrim takes its first breath", "kind": "reward"},
		"the SEEDED banner (TS:730)")
	eq(int(ctx.dna), 80, "seeding spent 20 (TS:716)")
	eq(sim.cargo.size(), 0, "the cargo row popped (TS:720)")
	eq(rec["audio"][0], ["levelup", 1.0, 0.0], "audio levelup 1 (TS:731)")
	ok(ctx.flags.has("spaceWorld"), "seeding persists (TS:732)")
	eq(int(sim.rng.state()), int(probe.state()), "seeding drew exactly the ONE eco-branch draw (TS:722)")

	# the VOLCANIC floraCap 60 branch: a volcanic planet with a nulled eco
	# (unreachable by generation — reachable by craft) keeps kind volcanic
	_place_planet(sim, 2, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 2)
	sim.planets[2]["eco"] = null
	sim.cargo = [{"genome": GenomeLib.default_genome(), "name": "Ember"}]
	sim.seed_nearest()
	var p2: Dictionary = sim.planets[2]
	approx(float(p2["eco"].flora_cap), 60.0, "volcanic floraCap 60 (TS:723)")
	approx(float(p2["eco"].flora), 36.0, "flora 0.6·60 (TS:724)")
	eq(String(p2["kind"]), "volcanic", "a non-barren kind is untouched (TS:725 ternary)")

	# seeding a planet with an EXISTING eco appends; the eco/floraCap/kind are
	# untouched; an existing colony SURVIVES (the ?? keeps it, TS:729)
	_place_planet(sim, 0, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 0)
	var p0: Dictionary = sim.planets[0]
	var eco_n: int = p0["eco"].species.size()
	p0["colony"] = {"pop": 9.0, "generations": 2.0}
	sim.cargo = [{"genome": GenomeLib.default_genome(), "name": "Latecomer"}]
	sim.seed_nearest()
	eq(p0["eco"].species.size(), eco_n + 1, "the existing eco gained ONE species (TS:727)")
	eq(String(p0["eco"].species[p0["eco"].species.size() - 1]["name"]), "Latecomer", "the appended row (TS:727)")
	approx(float(p0["eco"].flora_cap), 140.0, "the existing eco's floraCap untouched (no TS:722-724 branch)")
	eq(String(p0["kind"]), "lush", "kind unchanged")
	eq(p0["colony"], {"pop": 9.0, "generations": 2.0}, "an existing colony survives (TS:729 ??)")


# ---- mergeCargo (TS:735-770) -----------------------------------------------------------

func test_merge_cargo_pinned_stream() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	sim.invuln = 0.0
	var ga: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	ga.merge({"size": 1.2, "jaw": 3, "diet": "herbivore", "hue": 100.0}, true)
	var gb: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	gb.merge({"size": 1.8, "spikes": 2, "diet": "carnivore", "hue": 200.0}, true)

	# the cargo gate (TS:736)
	ctx.dna = 100
	sim.cargo = [{"genome": ga, "name": "Al"}]
	var st0: int = int(sim.rng.state())
	sim.merge_cargo()
	eq(sim.cargo.size(), 1, "cargo < 2 → mergeCargo returns (TS:736)")
	eq(int(ctx.dna), 100, "no spend under the cargo gate")
	eq(int(sim.rng.state()), st0, "the cargo gate draws NOTHING")

	# the spend refusal (TS:738-740)
	sim.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
	ctx.dna = 14
	sim.merge_cargo()
	eq(rec["toasts"][0], [tr("Gene splice costs 15 DNA"), "bad", "🧪"], "dna 14 → the cost toast (TS:739)")
	eq(sim.cargo.size(), 2, "cargo unchanged on the refusal")
	eq(int(ctx.dna), 14, "dna unchanged on the refusal")

	# SUCCESS at a pinned stream (non-wild world): the child bit-matches the
	# probe replay of crossover(a, b, rng, 0.3, {anomalyChance 0.10,
	# defectRate 0.2, bias {rate_add 0}, info}) + the species_name draw
	rec["toasts"].clear()
	ctx.dna = 100
	ctx.flags.erase("spaceWorld")
	sim.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
	var probe: Variant = _probe(sim)
	var info: Dictionary = {"anomaly": null, "defect": null}
	var expected: Dictionary = MutationLib.crossover(ga, gb, probe, 0.3, {
		"anomalyChance": 0.10, "defectRate": 0.2,
		"bias": {"rate_add": WorldGenomeLib.world_num(ctx.world, "mutation_rate_add", 0.0)},
		"info": info})
	var child_name: String = NamesLib.species_name(probe) + " (spliced)"
	sim.merge_cargo()
	eq(sim.cargo.size(), 1, "slice(2) dropped both parents (TS:757)")
	eq(sim.cargo[0]["genome"], expected, "the child bit-matches the crossover replay (TS:749-755)")
	eq(String(sim.cargo[0]["name"]), child_name, "child name '{speciesName} (spliced)' (TS:756)")
	eq(int(ctx.dna), 85, "the splice spent 15 (TS:738)")
	# the info toasts follow the probe's SpliceInfo, in TS order:
	# anomaly → defect → the 'Gene splice:' line
	var exp_toasts: Array = []
	if info["anomaly"] != null:
		var ak: String = String(info["anomaly"]["kind"])
		exp_toasts.append(["%s — %s" % [tr("UNEXPECTED EXPRESSION"),
			tr(String(MutationLib.ANOMALY_NAMES[ak]))], "chaos", "🧬"])
	if info["defect"] != null:
		var dk: String = String(info["defect"]["kind"])
		exp_toasts.append(["%s %s" % [tr("Defective splice:"),
			tr(String(MutationLib.DEFECT_NAMES[dk]))], "bad", "⚠️"])
	exp_toasts.append(["%s %s!" % [tr("Gene splice:"), child_name], "chaos", "🧪"])
	eq(rec["toasts"].size(), exp_toasts.size(), "the toast count follows the SpliceInfo (TS:759-765)")
	for i in exp_toasts.size():
		eq(rec["toasts"][i], exp_toasts[i], "splice toast %d matches the probe info order (TS:759-765)" % i)
	eq(rec["audio"][0], ["levelup", 0.9, 0.0], "audio levelup 0.9 (TS:766)")
	var disc_key: String = ""
	for k in ctx.bestiary:
		if String(ctx.bestiary[k]["name"]) == child_name:
			disc_key = k
	ok(disc_key != "", "discover(child, name, 'space') ran (TS:767)")
	if disc_key != "":
		eq(bool(ctx.bestiary[disc_key]["kin"]), false, "the splice discovery is NOT kin (TS:767 default)")
	ok(ctx.flags.has("spaceWorld"), "the splice persists (TS:769)")
	eq(int(sim.rng.state()), int(probe.state()),
		"the merge consumed exactly crossover + speciesName (no combo → the graft drew nothing)")

	# the 3-cargo slice: only the FIRST TWO merge; the third survives
	sim.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"},
		{"genome": ga, "name": "Cy"}]
	ctx.dna = 100
	sim.merge_cargo()
	eq(sim.cargo.size(), 2, "[A,B,C] → [C, child] (TS:757)")
	eq(String(sim.cargo[0]["name"]), "Cy", "the third row survived the slice")

	# the I-q2 rate_add pin: a world num-effect rides the bias — the child
	# bit-matches the rate_add 0.5 replay and DIFFERS from the rate_add 0 one
	var m2 := _mk_sim(SEED, null, {"traits": [{"effects": [
		{"kind": "num", "key": "mutation_rate_add", "value": 0.5}]}]})
	var sim2: Variant = m2["sim"]
	var ctx2: Variant = m2["ctx"]
	ctx2.dna = 100
	sim2.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
	var probe2: Variant = _probe(sim2)
	var expected_hot: Dictionary = MutationLib.crossover(ga, gb, probe2, 0.3, {
		"anomalyChance": 0.10, "defectRate": 0.2,
		"bias": {"rate_add": 0.5}, "info": {"anomaly": null, "defect": null}})
	NamesLib.species_name(probe2)
	sim2.merge_cargo()
	eq(sim2.cargo[0]["genome"], expected_hot, "rate_add 0.5 rode the bias (the I-q2 note, TS:753)")
	var probe2b: Variant = RngLib.new_from(sim2.rng.state())
	var cold_child: Dictionary = MutationLib.crossover(ga, gb, probe2b, 0.3, {
		"anomalyChance": 0.10, "defectRate": 0.2,
		"bias": {"rate_add": 0.0}, "info": {"anomaly": null, "defect": null}})
	NamesLib.species_name(probe2b)
	ok(sim2.cargo[0]["genome"] != cold_child, "a rate_add 0 replay gives a DIFFERENT child (the bias is live)")

	# the WILD_MUTATIONS rates (TS:748-751): scan fixed seeds for one where
	# the two tables DIVERGE at the REAL merge stream position (post-
	# construction) — building BOTH sims per candidate and probe-replaying
	# each merge with the world-derived rate_add. The found pair is used
	# directly (the probes clone the stream; the sims' streams stay intact).
	var wild_world: Dictionary = {"traits": [{"effects": [{"kind": "flag", "key": "wild_mutations"}]}]}
	var div_seed := -1
	var mw: Variant = null
	var mn: Variant = null
	var infow: Dictionary = {}
	var infon: Dictionary = {}
	for i in 16:
		var cand := SEED + i
		var mw_c: Dictionary = _mk_sim(cand, null, wild_world)
		var mn_c: Dictionary = _mk_sim(cand)
		# the derived world must NOT carry the wild flag (or the comparison
		# is meaningless — the sim would run the wild table "normally")
		if WorldGenomeLib.world_has(mn_c["ctx"].world, "wild_mutations"):
			continue
		var pw: Variant = _probe(mw_c["sim"])
		var wi: Dictionary = {"anomaly": null, "defect": null}
		MutationLib.crossover(ga, gb, pw, 0.3, {
			"anomalyChance": 0.15, "defectRate": 0.3,
			"bias": {"rate_add": WorldGenomeLib.world_num(mw_c["ctx"].world, "mutation_rate_add", 0.0)},
			"info": wi})
		var pn: Variant = _probe(mn_c["sim"])
		var ni: Dictionary = {"anomaly": null, "defect": null}
		MutationLib.crossover(ga, gb, pn, 0.3, {
			"anomalyChance": 0.10, "defectRate": 0.2,
			"bias": {"rate_add": WorldGenomeLib.world_num(mn_c["ctx"].world, "mutation_rate_add", 0.0)},
			"info": ni})
		var wfired: bool = wi["anomaly"] != null or wi["defect"] != null
		var nfired: bool = ni["anomaly"] != null or ni["defect"] != null
		if wfired != nfired:
			div_seed = cand
			mw = mw_c
			mn = mn_c
			infow = wi
			infon = ni
			break
	ok(div_seed >= 0, "a divergence seed exists within the fixed scan")
	if div_seed >= 0:
		var simw: Variant = mw["sim"]
		var recw: Dictionary = mw["rec"]
		var ctxw: Variant = mw["ctx"]
		ctxw.dna = 100
		simw.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
		var probew: Variant = _probe(simw)
		var expectedw: Dictionary = MutationLib.crossover(ga, gb, probew, 0.3, {
			"anomalyChance": 0.15, "defectRate": 0.3,
			"bias": {"rate_add": WorldGenomeLib.world_num(ctxw.world, "mutation_rate_add", 0.0)},
			"info": {"anomaly": null, "defect": null}})
		simw.merge_cargo()
		eq(simw.cargo[0]["genome"], expectedw, "the wild child bit-matches the 0.15/0.3 replay (TS:750-751)")
		eq(infow["anomaly"] != null or infow["defect"] != null, true,
			"the divergence seed actually FIRES under the wild table (premise)")
		var fired_toast: bool = _toasted(recw, "UNEXPECTED EXPRESSION") \
				or _toasted(recw, "Defective splice:")
		eq(fired_toast, true, "the wild run's surprise toast fired (TS:759-763)")
		# the SAME seed without the flag: the normal table does NOT fire
		var simn: Variant = mn["sim"]
		var recn: Dictionary = mn["rec"]
		var ctxn: Variant = mn["ctx"]
		ctxn.dna = 100
		simn.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
		var proben: Variant = _probe(simn)
		var expectedn: Dictionary = MutationLib.crossover(ga, gb, proben, 0.3, {
			"anomalyChance": 0.10, "defectRate": 0.2,
			"bias": {"rate_add": WorldGenomeLib.world_num(ctxn.world, "mutation_rate_add", 0.0)},
			"info": {"anomaly": null, "defect": null}})
		simn.merge_cargo()
		eq(simn.cargo[0]["genome"], expectedn, "the normal child bit-matches the 0.10/0.2 replay (TS:750-751)")
		eq(infon["anomaly"], null, "the normal table does NOT fire at the divergence seed (premise)")
		eq(infon["defect"], null, "no defect under the normal table either (premise)")
		eq(recn["toasts"].size(), 1, "only the 'Gene splice:' line fired (TS:759/762 gates)")

	# the G key runs mergeCargo when cargo ≥ 2 (TS:510-512)
	var m3 := _mk_sim()
	var sim3: Variant = m3["sim"]
	var ctx3: Variant = m3["ctx"]
	ctx3.dna = 100
	sim3.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
	sim3.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyG"]}))
	eq(sim3.cargo.size(), 1, "G spliced the pair (TS:510-512)")
	eq(int(ctx3.dna), 85, "the G path spent 15")
	# G with cargo < 2 → nothing
	ctx3.dna = 100
	sim3.cargo = [{"genome": ga, "name": "Al"}]
	sim3.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyG"]}))
	eq(sim3.cargo.size(), 1, "G with cargo < 2 → no merge (TS:510 gate)")
	eq(int(ctx3.dna), 100, "no spend under the G gate")


# ---- borrowedFleshGraft (TS:772-792) ----------------------------------------------------

func test_borrowed_flesh_graft() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]

	# COMBO OFF: the graft returns before any draw (TS:778)
	var child: Dictionary = GenomeLib.default_genome()
	child["jaw"] = 5
	var st0: int = int(sim.rng.state())
	sim.borrowed_flesh_graft(child)
	ok(not ctx.flags.has("borrowed_flesh_graft"), "combo off → no flag (TS:778)")
	eq(int(child["jaw"]), 5, "combo off → the child untouched")
	eq(int(sim.rng.state()), st0, "combo off → NO rng draw (the guard precedes the shuffle)")
	eq(rec["toasts"], [], "combo off → no toast")

	# the FLAG GUARD: once per run (TS:778 === true)
	rec["toasts"].clear()
	ctx.world["comboFired"] = {"borrowed_flesh": true}
	ctx.flags["borrowed_flesh_graft"] = true
	ctx.bestiary["k2"] = {"key": "k2", "name": "Ridgeback",
		"genome": GenomeLib.clamp_genome(GenomeLib.default_genome()), "stage": "cell",
		"seen": 1, "killsByPlayer": 0, "extinct": true, "kin": false}
	sim.borrowed_flesh_graft(child)
	eq(bool(ctx.flags["borrowed_flesh_graft"]), true, "the flag guard returned early — still set (TS:778)")
	eq(rec["toasts"], [], "flag guard → no toast (TS:778)")

	# THE GRAFT: e1's jaw 5 cannot raise the child's jaw 5 (never downgrades /
	# no-ops at equal), e2's spikes 3 raises the child's spikes 0; the shuffled
	# visit order is derived from the probe — both orders converge here
	ctx.flags.erase("borrowed_flesh_graft")
	ctx.bestiary = {
		"k1": {"key": "k1", "name": "Old One",
			"genome": GenomeLib.clamp_genome(GenomeLib.default_genome()), "stage": "cell",
			"seen": 1, "killsByPlayer": 0, "extinct": true, "kin": false},
		"k2": {"key": "k2", "name": "Ridgeback",
			"genome": GenomeLib.clamp_genome(GenomeLib.default_genome()), "stage": "cell",
			"seen": 1, "killsByPlayer": 0, "extinct": true, "kin": false},
		"k3": {"key": "k3", "name": "Aliveus",
			"genome": GenomeLib.clamp_genome(GenomeLib.default_genome()), "stage": "cell",
			"seen": 1, "killsByPlayer": 0, "extinct": false, "kin": false},
	}
	ctx.bestiary["k1"]["genome"]["jaw"] = 5
	ctx.bestiary["k2"]["genome"]["spikes"] = 3
	ctx.bestiary["k3"]["genome"]["toxin"] = 4  # NOT extinct — never visited
	child = GenomeLib.default_genome()
	child["jaw"] = 5
	child["spikes"] = 0
	var probe: Variant = _probe(sim)
	var order: Array = probe.shuffled([ctx.bestiary["k1"], ctx.bestiary["k2"]])
	sim.borrowed_flesh_graft(child)
	eq(bool(ctx.flags["borrowed_flesh_graft"]), true, "the graft set the once-per-run flag (TS:788)")
	approx(float(child["spikes"]), 3.0, "spikes raised to the graft level 3 (TS:785/787)")
	eq(int(child["jaw"]), 5, "the jaw-5 lineage was skipped (raised ≤ cur → next, TS:786)")
	eq(rec["toasts"][0], ["%s %s ← %s" % [tr("Borrowed flesh:"), tr("Spike"), "Ridgeback"], "good", "🫱"],
		"the borrowed-flesh toast with the part name + source (TS:789)")
	eq(order.size(), 2, "the probe shuffled both extinct lineages (premise)")
	eq(int(sim.rng.state()), int(probe.state()),
		"the graft consumed exactly the shuffle draw (the early continue drew nothing)")

	# NEVER DOWNGRADES (TS:786): a source at the child's own value is skipped —
	# no flag, no toast, child untouched; a 1-entry shuffle draws NOTHING
	rec["toasts"].clear()
	ctx.flags.erase("borrowed_flesh_graft")
	ctx.bestiary = {"k1": {"key": "k1", "name": "Old One",
		"genome": GenomeLib.clamp_genome(GenomeLib.default_genome()), "stage": "cell",
		"seen": 1, "killsByPlayer": 0, "extinct": true, "kin": false}}
	ctx.bestiary["k1"]["genome"]["jaw"] = 5
	child = GenomeLib.default_genome()
	child["jaw"] = 5
	st0 = int(sim.rng.state())
	sim.borrowed_flesh_graft(child)
	ok(not ctx.flags.has("borrowed_flesh_graft"), "raised == cur → NO flag (the never-downgrade skip, TS:786)")
	eq(rec["toasts"], [], "raised == cur → no toast")
	eq(int(child["jaw"]), 5, "the child untouched by the skip")
	eq(int(sim.rng.state()), st0, "a 1-entry shuffle draws nothing (Fisher-Yates i>0)")

	# a LOWER level never downgrades either: source spikes 2 vs child spikes 3
	ctx.bestiary["k1"]["genome"] = GenomeLib.clamp_genome(GenomeLib.default_genome())
	ctx.bestiary["k1"]["genome"]["spikes"] = 2
	child = GenomeLib.default_genome()
	child["spikes"] = 3
	st0 = int(sim.rng.state())
	sim.borrowed_flesh_graft(child)
	ok(not ctx.flags.has("borrowed_flesh_graft"), "level 2 < cur 3 → skipped (graft_value clamps to level, TS:785)")
	eq(int(sim.rng.state()), st0, "the skip consumed nothing")

	# a lineage with NO standout part is passed over (TS:781-782)
	ctx.bestiary["k1"]["genome"] = {
		"size": 1.0, "diet": "herbivore", "hue": 120.0, "sat": 0.5, "pattern": "plain",
		"flagella": 0, "cilia": 0, "spikes": 0, "jaw": 0, "toxin": 0, "proboscis": 0,
		"electro": 0, "jet": 0, "legs": 0, "arms": 0, "eyes": 0, "horns": 0,
		"tail": false, "wings": 0, "brain": 0, "coat": "skin", "generation": 1}
	child = GenomeLib.default_genome()
	child["jaw"] = 5
	st0 = int(sim.rng.state())
	sim.borrowed_flesh_graft(child)
	ok(not ctx.flags.has("borrowed_flesh_graft"), "standout_part null → continue (TS:782)")
	eq(int(sim.rng.state()), st0, "the standout-null pass consumed nothing")

	# NO extinct entries: the shuffle runs on an empty array (no draws)
	ctx.bestiary = {}
	child = GenomeLib.default_genome()
	st0 = int(sim.rng.state())
	sim.borrowed_flesh_graft(child)
	ok(not ctx.flags.has("borrowed_flesh_graft"), "no extinct bestiary rows → no graft (TS:779)")
	eq(int(sim.rng.state()), st0, "an empty shuffle draws nothing")

	# E2E: the graft rides mergeCargo AFTER the discover (TS:768) — craft the
	# bestiary from the PROBE child (a maxed gene skips, a zeroed gene grafts)
	var ga: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	ga.merge({"jaw": 3, "diet": "herbivore", "hue": 100.0}, true)
	var gb: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	gb.merge({"size": 1.8, "spikes": 2, "diet": "carnivore", "hue": 200.0}, true)
	var m2 := _mk_sim(SEED)
	var sim2: Variant = m2["sim"]
	var rec2: Dictionary = m2["rec"]
	var ctx2: Variant = m2["ctx"]
	ctx2.world["comboFired"] = {"borrowed_flesh": true}
	ctx2.dna = 100
	sim2.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
	var probe2: Variant = _probe(sim2)
	var child2: Dictionary = MutationLib.crossover(ga, gb, probe2, 0.3, {
		"anomalyChance": 0.10, "defectRate": 0.2, "bias": {"rate_add": 0.0},
		"info": {"anomaly": null, "defect": null}})
	NamesLib.species_name(probe2)
	# find a ZERO gene on the probe child whose part exists (the graft target)
	var graft_gene := ""
	for pdef in PartsLib.PARTS:
		if int(child2.get(pdef["gene"], 0)) == 0:
			graft_gene = String(pdef["gene"])
			break
	ok(graft_gene != "", "the probe child has a zeroed part gene to graft (premise)")
	# find the child's MAX gene (the skip source at its own value)
	var max_gene := ""
	var max_v := -1.0
	for gene in GenomeLib.GENE_BOUNDS:
		if float(child2.get(gene, 0)) > max_v:
			max_v = float(child2.get(gene, 0))
			max_gene = String(gene)
	ctx2.bestiary = {
		"ka": {"key": "ka", "name": "Skipper",
			"genome": GenomeLib.clamp_genome(GenomeLib.default_genome()), "stage": "cell",
			"seen": 1, "killsByPlayer": 0, "extinct": true, "kin": false},
		"kb": {"key": "kb", "name": "Giver",
			"genome": GenomeLib.clamp_genome(GenomeLib.default_genome()), "stage": "cell",
			"seen": 1, "killsByPlayer": 0, "extinct": true, "kin": false},
	}
	ctx2.bestiary["ka"]["genome"][max_gene] = int(max_v)
	ctx2.bestiary["kb"]["genome"][graft_gene] = 3
	sim2.merge_cargo()
	eq(float(sim2.cargo[0]["genome"][graft_gene]), 3.0, "the e2e graft raised the zeroed gene (TS:768/787)")
	eq(bool(ctx2.flags["borrowed_flesh_graft"]), true, "the e2e flag set")
	var grafted := false
	for t in rec2["toasts"]:
		if String(t[0]).find("Borrowed flesh:") >= 0:
			grafted = true
	ok(grafted, "the e2e borrowed-flesh toast fired")
	# the splice line precedes the graft toast (TS:765 before :768)
	var splice_i := -1
	var graft_i := -1
	for i in rec2["toasts"].size():
		if String(rec2["toasts"][i][0]).find("Gene splice:") >= 0:
			splice_i = i
		if String(rec2["toasts"][i][0]).find("Borrowed flesh:") >= 0:
			graft_i = i
	ok(splice_i >= 0 and graft_i > splice_i, "the graft toast follows the splice toast (TS:765/789)")


# ---- pirates (TS:794-810 spawn + :454-498 chase) -----------------------------------------

func test_pirates_lifecycle() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	sim.invuln = 0.0
	sim.sx = 0.0
	sim.sy = -900.0

	# spawnPirates: the 5 cap, ring 700, hp 140, ttl 40 (TS:794-809)
	var probe: Variant = _probe(sim)
	var exp_pos: Array = []
	for i in 5:
		var a: float = probe.next() * TAU
		exp_pos.append({"x": 0.0 + cos(a) * 700.0, "y": -900.0 + sin(a) * 700.0})
	sim.spawn_pirates(7)
	eq(sim.pirates.size(), 5, "spawn cap 5 (TS:795-796)")
	eq(sim.pirateTtl.size(), 5, "ttls ride in parallel (TS:807)")
	for i in 5:
		approx(float(sim.pirates[i]["x"]), float(exp_pos[i]["x"]), "pirate %d ring x 700 (TS:800)" % i)
		approx(float(sim.pirates[i]["y"]), float(exp_pos[i]["y"]), "pirate %d ring y 700 (TS:801)" % i)
		eq(float(sim.pirates[i]["vx"]), 0.0, "pirate %d vx 0 (TS:802)" % i)
		eq(float(sim.pirates[i]["hp"]), 140.0, "pirate %d hp 140 (TS:804)" % i)
		eq(float(sim.pirates[i]["gait"]), 0.0, "pirate %d gait 0 (TS:805)" % i)
		eq(float(sim.pirateTtl[i]), 40.0, "pirate %d life 40 (TS:797)" % i)
	eq(rec["audio"][0], ["alarm", 0.9, 0.0], "ONE alarm for the whole spawn (TS:809)")
	eq(int(sim.rng.state()), int(probe.state()), "the spawn consumed exactly the 5 angle draws")

	# at the cap: early return, NO draw, NO audio (TS:795)
	probe = _probe(sim)
	rec["audio"].clear()
	sim.spawn_pirates(3)
	eq(sim.pirates.size(), 5, "the cap holds (TS:795)")
	eq(rec["audio"], [], "no alarm at the cap (TS:795 return)")
	eq(int(sim.rng.state()), int(probe.state()), "the cap return drew NOTHING")

	# the partial top-up: n = min(n, 5 − len) (TS:796)
	sim.pirates.remove_at(0)
	sim.pirateTtl.remove_at(0)
	sim.spawn_pirates(2)
	eq(sim.pirates.size(), 5, "4 existing + request 2 → +1 (TS:796)")

	# the chase integration (TS:465-473): accel 300 toward the ship when
	# d > 30, drag exp(−1.4dt), drift, gait — bit-exact at dt 0.1
	sim.pirates = [{"x": 100.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	sim.sx = 0.0
	sim.update(0.1, _inp())
	var p0: Dictionary = sim.pirates[0]
	var exp_vx: float = (-300.0 * 0.1) * exp(-1.4 * 0.1)
	approx(float(p0["vx"]), exp_vx, "vx = accel(−300·dt) then drag exp(−1.4dt) (TS:467/470)")
	approx(float(p0["x"]), 100.0 + exp_vx * 0.1, "x integrates vx·dt (TS:472)")
	approx(float(p0["gait"]), 0.1, "gait += dt (TS:473)")
	eq(float(sim.shp), 100.0, "d 100 > 60 → no damage (TS:474 gate)")

	# d ≤ 30 → no accel (TS:466). The pirate sits INSIDE the damage radius too
	# (d < 60), so invuln silences the damage branch (and its chance draw)
	# while the chase math is pinned
	sim.invuln = 5.0
	sim.pirates = [{"x": 0.0, "y": -900.0, "vx": 5.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	sim.update(0.1, _inp())
	approx(float(sim.pirates[0]["vx"]), 5.0 * exp(-1.4 * 0.1), "d 0: no accel, drag only (TS:466)")
	sim.invuln = 0.0

	# the ttl siege-lift (TS:457-462)
	sim.pirateTtl = [0.05]
	sim.update(0.06, _inp())
	eq(sim.pirates.size(), 0, "ttl ≤ 0 → the pirate splices out (TS:458-460)")
	eq(sim.pirateTtl.size(), 0, "the ttl row splices too (TS:460)")
	eq(rec["toasts"][0], [tr("The siege lifts — pirates give up"), "good", "🌿"], "the siege-lift toast (TS:461)")

	# the `?? 40` ttl fallback: a desynced ttl array reads 40 (TS:457)
	sim.pirates = [{"x": 100.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = []
	sim.update(0.1, _inp())
	approx(float(sim.pirateTtl[0]), 39.9, "a missing ttl row reads 40 (TS:457 ??)")

	# the damage window (TS:474-481): d < 60, invuln 0, no lull → shp −14dt,
	# hurtT raised to 0.5 (then decayed 3dt → 0.45 at dt 1/60), the
	# chance(dt·6) burst + hit — the burst is CONDITIONAL at dt 1/60, so the
	# probe replay decides the branch and the stream cadence is asserted
	sim.pirates = [{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	sim.shp = 100.0
	sim.hurtT = 0.0
	var dt_p := 1.0 / 60.0
	probe = _probe(sim)
	var fired_p: bool = probe.chance(dt_p * 6.0)  # the damage-branch chance draw
	var bparts: Array = []
	if fired_p:
		for i in 4:
			var ang: float = probe.next() * PI * 2.0
			var bsp: float = probe.range(0.3, 1.0) * 120.0
			var col: String = String(probe.pick(["#ff8a5a"]))
			var bttl: float = probe.range(0.4, 1.0) * 0.4
			var bsz: float = probe.range(0.6, 1.4) * 3.0
			bparts.append({"ang": ang, "sp": bsp, "color": col, "ttl": bttl, "size": bsz})
	sim.update(dt_p, _inp())
	approx(float(sim.shp), 100.0 - 14.0 * dt_p, "shp −14·dt (TS:475)")
	approx(float(sim.hurtT), 0.5 - 3.0 * dt_p, "hurtT max(hurtT, 0.5) then decayed 3dt (TS:476→:606)")
	eq(rec["bursts"].size(), 1 if fired_p else 0, "the burst follows chance(dt·6) at the pinned stream (TS:477)")
	if fired_p:
		eq(int(rec["bursts"][0][2]), 4, "burst n 4 (TS:478)")
		eq(rec["bursts"][0][3]["parts"], bparts, "the burst parts bit-match the replay (the _fx_burst draw order)")
		eq(rec["bursts"][0][3]["colors"], ["#ff8a5a"], "burst colors (TS:478)")
		eq(float(rec["bursts"][0][3]["speed"]), 120.0, "burst speed 120 (TS:478)")
		eq(float(rec["bursts"][0][3]["ttl"]), 0.4, "burst ttl 0.4 (TS:478)")
		eq(rec["audio"][0], ["hit", 0.4, 0.0], "audio hit 0.4 (TS:479)")
	eq(int(sim.rng.state()), int(probe.state()), "the frame consumed exactly the chance (+burst) draws (TS:477-479)")

	# the deterministic-burst frame at dt 1.0 (chance(6) always true) — the
	# decay then eats hurtT entirely (max(0, 0.5−3))
	sim.pirates = [{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	sim.shp = 100.0
	sim.hurtT = 0.0
	probe = _probe(sim)
	probe.chance(1.0 * 6.0)  # the damage-branch chance draw (always true at dt 1)
	for i in 4:
		probe.next()
		probe.range(0.3, 1.0)
		probe.pick(["#ff8a5a"])
		probe.range(0.4, 1.0)
		probe.range(0.6, 1.4)
	sim.update(1.0, _inp())
	eq(rec["bursts"].size(), (2 if fired_p else 1), "dt 1.0 → chance(6) ALWAYS fires the burst (TS:477)")
	eq(float(sim.hurtT), 0.0, "the decay dominates at dt 1: max(0, 0.5−3) (TS:606)")
	eq(int(sim.rng.state()), int(probe.state()), "the dt-1 frame consumed exactly the 20 burst draws")

	# the LULL: no damage, no burst, NO draw (TS:474 !pirateLull)
	sim.pirateLull = true
	sim.shp = 100.0
	sim.hurtT = 0.0
	var bursts_n: int = rec["bursts"].size()
	probe = _probe(sim)
	sim.update(1.0, _inp())
	eq(float(sim.shp), 100.0, "lull → no shp damage (TS:474)")
	eq(float(sim.hurtT), 0.0, "lull → no hurt flash")
	eq(rec["bursts"].size(), bursts_n, "lull → no burst")
	eq(int(sim.rng.state()), int(probe.state()), "lull → the chance draw never happens")
	sim.pirateLull = false

	# the invuln gate: the whole damage block is skipped (TS:474)
	sim.invuln = 5.0
	sim.shp = 100.0
	probe = _probe(sim)
	sim.update(1.0, _inp())
	eq(float(sim.shp), 100.0, "invuln > 0 → no damage (TS:474)")
	eq(int(sim.rng.state()), int(probe.state()), "invuln → no chance draw")
	sim.invuln = 0.0

	# CLICK-TO-SHOOT (TS:482-497): the pirate sits ON the ship (d 0 → no
	# move), every click at its position lands; hp 140 → dead on the 5th
	sim.pirates = [{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	ctx.dna = 0
	sim.invuln = 5.0  # silence the damage branch — the click shot is NOT invuln-gated
	for i in 4:
		var hp_before: float = float(sim.pirates[0]["hp"])
		sim.update(1.0 / 60.0, _inp({"clicked": true, "wx": 0.0, "wy": -900.0}))
		eq(float(sim.pirates[0]["hp"]), hp_before - 34.0, "click %d: hp −34 (TS:485)" % (i + 1))
		eq(sim.pirates.size(), 1, "click %d: still alive (TS:489 gate)" % (i + 1))
	eq(int(ctx.dna), 0, "no DNA before the kill")
	sim.update(1.0 / 60.0, _inp({"clicked": true, "wx": 0.0, "wy": -900.0}))
	eq(sim.pirates.size(), 0, "hp ≤ 0 → the pirate splices (TS:490)")
	eq(sim.pirateTtl.size(), 0, "the ttl row splices (TS:491)")
	eq(rec["toasts"][rec["toasts"].size() - 1], [tr("Pirate destroyed! +30 DNA"), "good", "💥"],
		"the kill toast (TS:492)")
	eq(int(ctx.dna), 30, "addDna(30) on the kill (TS:493)")
	# the kill frame's audio: zap + boom
	var zap_i := -1
	var boom_i := -1
	for i in rec["audio"].size():
		if String(rec["audio"][i][0]) == "zap":
			zap_i = i
		if String(rec["audio"][i][0]) == "boom":
			boom_i = i
	ok(zap_i >= 0, "audio zap 0.7 on every hit (TS:487)")
	ok(boom_i >= 0, "audio boom 0.6 on the kill (TS:495)")
	# the kill frame fired the 20-particle death burst
	var death_bursts := 0
	for b in rec["bursts"]:
		if int(b[2]) == 20:
			death_bursts += 1
	eq(death_bursts, 1, "the death burst n 20 (TS:494)")

	# the clickD < 60 STRICT boundary (TS:484): a click 60 units away misses
	# and is NOT consumed
	sim.pirates = [{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	var inp_edge: Dictionary = _inp({"clicked": true, "wx": 60.0, "wy": -900.0})
	sim.update(1.0 / 60.0, inp_edge)
	eq(float(sim.pirates[0]["hp"]), 140.0, "clickD exactly 60 → no hit (strict <, TS:484)")
	eq(bool(inp_edge.get("take_click", false)), false, "the miss is NOT consumed (TS:486 not reached)")
	sim.update(1.0 / 60.0, _inp({"clicked": true, "wx": 59.9, "wy": -900.0}))
	eq(float(sim.pirates[0]["hp"]), 106.0, "clickD 59.9 → hit (TS:484)")


# ---- black holes (TS:436-452 + spawn :840-849) -------------------------------------------

func test_black_holes() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	sim.invuln = 0.0
	sim.sx = 0.0
	sim.sy = -900.0

	# spawnBlackHole: ring 1000, the vx/vy range(−12,12) pair, ttl 45 (TS:840-849)
	var probe: Variant = _probe(sim)
	var ea: float = probe.next() * TAU
	var evx: float = probe.range(-12.0, 12.0)
	var evy: float = probe.range(-12.0, 12.0)
	sim.spawn_black_hole()
	eq(sim.blackHoles.size(), 1, "one hole spawned (TS:842)")
	approx(float(sim.blackHoles[0]["x"]), 0.0 + cos(ea) * 1000.0, "hole ring x 1000 (TS:843)")
	approx(float(sim.blackHoles[0]["y"]), -900.0 + sin(ea) * 1000.0, "hole ring y 1000 (TS:844)")
	approx(float(sim.blackHoles[0]["vx"]), evx, "hole vx range(−12,12) (TS:845)")
	approx(float(sim.blackHoles[0]["vy"]), evy, "hole vy range(−12,12) (TS:846)")
	eq(float(sim.blackHoles[0]["ttl"]), 45.0, "hole ttl 45 (TS:847)")
	eq(int(sim.rng.state()), int(probe.state()), "the spawn consumed angle + 2 velocity draws")

	# the PULL at pinned distances (TS:438-443): d 500 → 24000/500 = 48
	sim.blackHoles = [{"x": 500.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.svx = 0.0
	sim.svy = 0.0
	sim.update(0.5, _inp())
	approx(float(sim.svx), (24000.0 / 500.0) * 0.5, "pull at d 500: (24000/500)·dt toward the hole (TS:440-442)")
	eq(float(sim.svy), 0.0, "no lateral pull (the hole sits on the x axis)")

	# the max(80, d) clamp: d 79 → 24000/80 = 300 (TS:440)
	sim.blackHoles = [{"x": 79.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.svx = 0.0
	sim.update(0.5, _inp())
	approx(float(sim.svx), (24000.0 / 80.0) * 0.5, "pull at d 79 clamps to 24000/80 (TS:440)")

	# the d < 600 STRICT boundary (TS:439)
	sim.blackHoles = [{"x": 600.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.svx = 0.0
	sim.update(0.5, _inp())
	eq(float(sim.svx), 0.0, "d = 600 → NO pull (strict <, TS:439)")

	# the d > 0.001 guard: a hole AT the ship pulls nothing but still damages
	# (the damage branch has no such guard, TS:444) — dt 1/60 keeps the hurtT
	# set observable past the decay (max(0, 1 − 3/60) = 0.95)
	sim.blackHoles = [{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.svx = 0.0
	sim.shp = 100.0
	sim.hurtT = 0.0
	sim.update(1.0 / 60.0, _inp())
	eq(float(sim.svx), 0.0, "d 0 → no pull (the 0.001 guard, TS:439)")
	approx(float(sim.shp), 100.0 - 60.0 / 60.0, "d 0 < 40 → shp −60·dt (TS:445)")
	approx(float(sim.hurtT), 0.95, "hurtT set 1, decayed 3/60 (TS:446→:606)")

	# the d < 40 STRICT boundary (TS:444)
	sim.blackHoles = [{"x": 40.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.shp = 100.0
	sim.update(0.5, _inp())
	eq(float(sim.shp), 100.0, "d = 40 → NO damage (strict <, TS:444)")
	sim.blackHoles = [{"x": 39.9, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.shp = 100.0
	sim.update(0.5, _inp())
	approx(float(sim.shp), 100.0 - 30.0, "d 39.9 → damage (TS:444)")

	# the invuln gate covers BOTH the pull and the damage; the drift/ttl are
	# UNGATED (TS:439/444 vs :448-450)
	sim.blackHoles = [{"x": 100.0, "y": -900.0, "vx": 12.0, "vy": -5.0, "ttl": 1.0}]
	sim.invuln = 2.0
	sim.svx = 0.0
	sim.shp = 100.0
	sim.update(0.5, _inp())
	eq(float(sim.svx), 0.0, "invuln → no pull (TS:439)")
	eq(float(sim.shp), 100.0, "invuln → no damage (TS:444)")
	approx(float(sim.blackHoles[0]["x"]), 106.0, "the drift runs ungated (TS:448)")
	approx(float(sim.blackHoles[0]["ttl"]), 0.5, "the ttl decays ungated (TS:450)")
	sim.invuln = 0.0

	# the ttl filter (TS:452): ttl ≤ 0 → the hole is gone
	sim.blackHoles = [{"x": 0.0, "y": -900.0, "vx": 12.0, "vy": -5.0, "ttl": 0.3}]
	sim.update(0.4, _inp())
	eq(sim.blackHoles.size(), 0, "ttl ≤ 0 → filtered out (TS:452)")
	sim.blackHoles = [{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 0.3}]
	sim.update(0.2, _inp())
	eq(sim.blackHoles.size(), 1, "ttl > 0 → the hole survives (TS:452)")


# ---- ship death (TS:584-602) --------------------------------------------------------------

func test_ship_death() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	sim.sx = 500.0
	sim.sy = 500.0
	sim.svx = 30.0
	sim.svy = 40.0
	sim.shp = 0.0
	sim.invuln = 0.0
	ctx.dna = 100
	var cargo_row: Dictionary = {"genome": GenomeLib.default_genome(), "name": "Keeper"}
	sim.cargo = [cargo_row, cargo_row, cargo_row]
	sim.pirates = [{"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "hp": 1.0, "gait": 0.0},
		{"x": 1.0, "y": 1.0, "vx": 0.0, "vy": 0.0, "hp": 2.0, "gait": 0.0}]
	sim.pirateTtl = [10.0, 11.0]
	sim.blackHoles = [
		{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0},    # d 0 from the respawn
		{"x": 0.0, "y": -1700.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0},   # d 800 → kept
		{"x": 700.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0},  # d 700 → culled (strict >)
	]
	ctx.flags.erase("spaceWorld")
	sim.update(0.1, _inp())
	# the respawn + bill (TS:585-594)
	eq(float(sim.shp), 50.0, "shp = shpMax·0.5 (TS:586)")
	eq(int(ctx.dna), 85, "lost = round(dna·0.15) = 15 (TS:587-588)")
	eq(rec["toasts"][0], ["%s %d DNA" % [tr("Ship destroyed! Lost"), 15], "bad", "💀"],
		"the death toast (TS:591)")
	eq(float(sim.sx), 0.0, "respawn sx 0 (TS:592)")
	eq(float(sim.sy), -900.0, "respawn sy −900 (TS:592)")
	eq(float(sim.svx), 0.0, "svx zeroed (TS:593)")
	eq(float(sim.svy), 0.0, "svy zeroed (TS:593)")
	approx(float(sim.invuln), 4.0 - 0.1, "invuln 4 (TS:594), then the :605 decay in the same frame (4−dt)")
	# the cull radius 700 (TS:595-597 — must exceed the 600 pull radius or the
	# killing hole chain-kills the respawn)
	eq(sim.blackHoles.size(), 1, "holes ≤ 700 from the respawn are CULLED (b1 d 0, b3 d 700 strict >)")
	approx(float(sim.blackHoles[0]["y"]), -1700.0, "the d-800 hole survived")
	eq(sim.pirates.size(), 0, "pirates cleared (TS:598)")
	eq(sim.pirateTtl.size(), 0, "ttls cleared (TS:599)")
	eq(sim.cargo.size(), 3, "cargo SURVIVES — deleting specimens blocked seeding → the ending (TS:589-590)")
	eq(rec["audio"][0], ["boom", 1.0, 0.0], "audio boom 1 (TS:600)")
	eq(rec["shakes"][0], [10.0, 0.8], "camShakeFor(10, 0.8) (TS:601)")
	eq(ctx.flags.has("spaceWorld"), false, "the death block does NOT persist (no TS persist call)")

	# the Math.round curve: 30·0.15 = 4.5 → 5 (round half up)
	sim.shp = 0.0
	sim.invuln = 0.0
	ctx.dna = 30
	sim.update(0.1, _inp())
	eq(int(ctx.dna), 25, "lost = round(4.5) = 5 (TS:587)")

	# POST-ENDING: no DNA bill — you already won (TS:584/587)
	sim.endingDone = true
	sim.shp = 0.0
	sim.invuln = 0.0
	ctx.dna = 100
	sim.update(0.1, _inp())
	eq(int(ctx.dna), 100, "endingDone → lost 0 — the no-bill pin (TS:587 ternary)")
	eq(rec["toasts"][rec["toasts"].size() - 1], ["%s %d DNA" % [tr("Ship destroyed! Lost"), 0], "bad", "💀"],
		"the toast still reads 'Lost 0 DNA' (TS:591)")
	eq(float(sim.shp), 50.0, "the respawn still runs post-ending (TS:586)")
	sim.endingDone = false


# ---- the ff e2e through a REAL eco + the 5 s persist cadence (TS:306-325 + :609-613) ------

func test_ff_e2e_real_eco_and_persist_cadence() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	# a REAL eco with a doomed carnivore: pop 8 single-species → cap = 0.18·pop
	# (biomass-derived) → the dt·26 tick collapses it below the 0.4 floor.
	# Frame 1 (dt·1) only dents it — the extinction lands exactly on frame 2.
	var eco: Variant = EcoScript.new(RngLib.new_from(777))
	eco.flora_cap = 140.0
	eco.flora = 0.0
	var doomed_genome: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	doomed_genome["diet"] = "carnivore"
	eco.add_species(doomed_genome, 8.0)
	sim.planets[0]["eco"] = eco
	sim.planets[0]["colony"] = {"pop": 1.0, "generations": 0.0}
	sim.planets[0]["scanned"] = true
	sim.planets[1]["eco"] = null
	sim.planets[2]["eco"] = null
	sim.planets[4]["eco"] = null
	sim.invuln = 0.0
	var doomed: Dictionary = eco.species[0]
	ctx.world_stats["extinctions"] = 0
	ctx.flags.erase("spaceWorld")

	# frame 1: timeScale pre-reads ffHold 0 → tick dt·1 (TS:306/315)
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	eq(bool(doomed["extinct"]), false, "frame 1 (dt·1): the carnivore survives")
	approx(float(doomed["pop"]), 8.0 + (0.5 * 8.0 * (1.0 - 8.0 / maxf(1.0, 8.0 * 1.0 * 0.18))
		- 8.0 * 0.02) * (1.0 / 60.0), "frame 1 pop decay (the eco valve math, m = dt/60)")
	approx(float(sim.planets[0]["colony"]["generations"]), 1.0 / 30.0, "generations += dt·1/30 (TS:323)")
	var pop_a: float = 1.0 + 1.0 * 1.0 * 0.08 * (1.0 + 1.0 * 0.01) * maxf(0.0, 1.0 - 1.0 / 120.0)
	approx(float(sim.planets[0]["colony"]["pop"]), pop_a, "colony growth ×ts 1 (TS:306/372)")

	# frame 2: timeScale 26 → tick dt·26 → EXTINCTION through the REAL tick
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	eq(bool(doomed["extinct"]), true, "frame 2 (dt·26): the carnivore goes extinct (pop < 0.4)")
	approx(float(doomed["pop"]), 0.0, "the dead line's pop clamps to 0")
	eq(int(ctx.world_stats["extinctions"]), 1, "bump_extinction rode the REAL extinction (TS:317)")
	eq(rec["toasts"][0], ["%s went extinct on %s" % [String(doomed["name"]), String(sim.planets[0]["name"])],
		"chaos", "💀"], "the extinction toast through the real tick (TS:318)")
	approx(float(sim.planets[0]["colony"]["generations"]), (1.0 + 26.0) / 30.0,
		"generations += dt·26/30 (TS:323)")
	var pop_b: float = pop_a + 1.0 * 26.0 * 0.08 * (1.0 + pop_a * 0.01) * maxf(0.0, 1.0 - pop_a / 120.0)
	approx(float(sim.planets[0]["colony"]["pop"]), pop_b, "colony growth ×26 (TS:306/372)")

	# frame 3: released — timeScale pre-read 26 but ffHold decays to 0 → no tick
	sim.update(1.0, _inp())
	eq(bool(doomed["extinct"]), true, "frame 3: no ff tick (the part-1 pre-read pin)")
	# frames 4-5: idle — persistT 4, 5 (still not > 5)
	sim.update(1.0, _inp())
	sim.update(1.0, _inp())

	# the persist cadence (TS:609-613): strict > 5 — 5.0 does NOT fire
	eq(ctx.flags.has("spaceWorld"), false, "persistT 5.0 → NOT yet (strict >, TS:611)")
	eq(float(sim.persistT), 5.0, "persistT accumulated 5·dt 1")
	sim.update(1.0, _inp())
	eq(float(sim.persistT), 0.0, "persistT reset to 0 after the fire (TS:612)")
	ok(ctx.flags.has("spaceWorld"), "persistT > 5 → persistColonies (TS:613)")


# ---- the R/G/V keys + tribute (TS:500-517, :851-870) ---------------------------------------

func test_keys_and_tribute() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	sim.invuln = 0.0

	# V with no demand → nothing (TS:515)
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyV"]}))
	eq(rec["toasts"], [], "V with tributeDemand 0 → nothing (TS:515 gate)")
	eq(int(ctx.dna), 40, "no dna moved")

	# demandTribute (TS:851-859)
	sim.demand_tribute(50.0)
	eq(float(sim.tributeDemand), 50.0, "the demand stored (TS:852)")
	eq(rec["banners"][0], {"title": "THE VOID EMPIRE DEMANDS TRIBUTE",
		"subtitle": "pay 50 DNA (press V) or face the raid", "kind": "danger", "ttl": 8},
		"the demand banner (TS:853-857)")
	eq(rec["audio"][0], ["alarm", 1.0, 0.0], "audio alarm 1 (TS:858)")

	# V pays when dna ≥ demand (TS:861-866)
	ctx.dna = 100
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyV"]}))
	eq(int(ctx.dna), 50, "the tribute deducted (TS:864)")
	eq(float(sim.tributeDemand), 0.0, "the demand zeroed (TS:866)")
	eq(rec["toasts"][0], [tr("Tribute paid. The Void Empire is satisfied… for now."), "info", "📦"],
		"the paid toast (TS:865)")

	# V refuses when dna < demand (TS:867-869)
	sim.tributeDemand = 50.0
	ctx.dna = 30
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyV"]}))
	eq(int(ctx.dna), 30, "no deduction on the refusal")
	eq(float(sim.tributeDemand), 50.0, "the demand STANDS on the refusal")
	eq(rec["toasts"][1], [tr("Not enough DNA — the raid is coming!"), "bad", "⚔️"],
		"the raid-is-coming toast (TS:868)")

	# payTribute with no demand → early return (TS:862)
	sim.tributeDemand = 0.0
	var st0: int = int(sim.rng.state())
	sim.pay_tribute()
	eq(rec["toasts"].size(), 2, "no demand → no toast (TS:862)")
	eq(int(sim.rng.state()), st0, "the early return drew nothing")


# ---- the chaos ctx WITH onEnd + the cooldown decay (TS:519-550) -----------------------------

func test_chaos_ctx_and_on_end() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	sim.invuln = 0.0
	var chaos_rec: ChaosRec = ChaosRec.new()
	sim.chaos = chaos_rec

	# the FULL ctx (TS:520-525) — the same shape as civ + the storyteller
	# hooks at their neutral defaults
	sim.update(0.5, _inp())
	eq(chaos_rec.calls.size(), 1, "chaos.update ran (TS:520)")
	var call: Dictionary = chaos_rec.calls[0]
	approx(float(call["dt"]), 0.5, "the dt passthrough")
	approx(float(call["ctx"]["chaos"]), 0.15, "ctx.chaos (TS:521)")
	approx(float(call["ctx"]["karma"]), 0.0, "ctx.karma (TS:521)")
	approx(float(call["ctx"]["stageTime"]), 0.5, "ctx.stageTime = sim.time (TS:521)")
	approx(float(call["ctx"]["gapMult"]), 1.0, "gapMult = chaosGapMult·gapBias at the defaults (TS:522)")
	eq(String(call["ctx"]["mood"]), "test", "mood at the neutral default (TS:523)")
	approx(float(call["ctx"]["warnScale"]), 1.0, "warnScale at the neutral default (TS:524)")
	ok(call["hooks"].has("onWarn") and call["hooks"].has("onApply") and call["hooks"].has("onEnd"),
		"the hooks carry onWarn + onApply + onEnd (TS:526-547)")

	# the storyteller hooks bend the ctx (the civ pattern)
	m["hooks"]["get_gap_bias"] = func(): return 2.0
	m["hooks"]["get_mood"] = func(): return "grim"
	m["hooks"]["get_warn_scale"] = func(): return 1.5
	sim.update(0.5, _inp())
	var call2: Dictionary = chaos_rec.calls[1]
	approx(float(call2["ctx"]["gapMult"]), 2.0, "gapBias hook rode gapMult (TS:522)")
	eq(String(call2["ctx"]["mood"]), "grim", "the mood hook (TS:523)")
	approx(float(call2["ctx"]["warnScale"]), 1.5, "the warnScale hook (TS:524)")

	# onWarn (TS:526-530): a warned def banners danger + alarm; an unwarned
	# def is silent
	var hooks: Dictionary = call["hooks"]
	hooks["onWarn"].call({"id": "x", "warn": "Something glows beneath the void"})
	eq(rec["banners"][0], {"title": "Something glows beneath the void", "kind": "danger", "ttl": 2.4},
		"onWarn banner (TS:528)")
	eq(rec["audio"][0], ["alarm", 0.5, 0.0], "onWarn alarm 0.5 (TS:529)")
	var banners_n: int = rec["banners"].size()
	hooks["onWarn"].call({"id": "y"})
	eq(rec["banners"].size(), banners_n, "an unwarned def → no banner (TS:527 gate)")

	# onApply (TS:532-538): the chaos banner + addChaos(0.03) + the note
	hooks["onApply"].call({"id": "z", "name": "Meteor Storm"})
	eq(rec["banners"][banners_n], {"title": "Meteor Storm", "kind": "chaos"},
		"onApply banner (TS:533)")
	approx(float(ctx.chaos), 0.18, "addChaos(0.03) (TS:534)")
	eq(rec["notes"], [0.0], "noteChaosEvent(playtime) (TS:537)")

	# onEnd — THE TRIBUTE RULE (TS:539-547): an unpaid demand → 3 pirates +
	# the demand zeroed
	sim.tributeDemand = 5.0
	var probe: Variant = _probe(sim)
	probe.next()
	probe.next()
	probe.next()
	hooks["onEnd"].call({"id": "tribute"})
	eq(sim.pirates.size(), 3, "unpaid tribute → spawnPirates(3) (TS:543)")
	eq(float(sim.tributeDemand), 0.0, "the demand zeroed (TS:544)")
	eq(int(sim.rng.state()), int(probe.state()), "the spawn consumed exactly the 3 angle draws")
	# a paid-up tribute end spawns nothing
	probe = _probe(sim)
	hooks["onEnd"].call({"id": "tribute"})
	eq(sim.pirates.size(), 3, "demand 0 → no pirates (TS:542 gate)")
	eq(int(sim.rng.state()), int(probe.state()), "no draw without the demand")
	# a non-tribute end never touches the rule
	sim.tributeDemand = 7.0
	hooks["onEnd"].call({"id": "nebula_flip"})
	eq(float(sim.tributeDemand), 7.0, "a non-tribute end leaves the demand (TS:540 gate)")
	eq(sim.pirates.size(), 3, "no pirates from a non-tribute end")

	# the resurveyCd decay with the floor (TS:550)
	sim.resurveyCd = 9.0
	sim.update(0.5, _inp())
	approx(float(sim.resurveyCd), 8.5, "resurveyCd −dt (TS:550)")
	sim.resurveyCd = 0.2
	sim.update(0.5, _inp())
	eq(float(sim.resurveyCd), 0.0, "the decay floors at 0 (TS:550 max)")


# ---- the finale / ending state machine (TS:552-582) ------------------------------------------

func test_finale_and_ending() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	sim.invuln = 0.0
	_isolate_planet(sim, -1)  # keep −1 → EVERY planet out to orbit 5000

	# thrival gate: two thriving + one at 19.9 → NO finale (TS:553-554)
	for i in 3:
		sim.planets[i]["colony"] = {"pop": 20.0 if i < 2 else 19.9, "generations": 0.0}
	sim.update(1.0 / 60.0, _inp())
	eq(sim.finale, null, "2 thriving + 19.9 → no finale (the pop ≥ 20 gate)")
	# the third crosses 20 → the core awakens (TS:554-559)
	sim.planets[2]["colony"]["pop"] = 20.0
	sim.update(1.0 / 60.0, _inp())
	var fin: Dictionary = sim.finale
	ok(fin != null, "3 thriving → the finale spawned (TS:556)")
	eq(float(fin["x"]), 0.0, "finale x 0 (TS:556)")
	eq(float(fin["y"]), -1900.0, "finale y −1900 (TS:556)")
	eq(bool(fin["active"]), true, "finale active (TS:556)")
	# the spawn frame ALREADY advances t (TS:556 set → :560 `if (finale)` same
	# frame): t = dt on the awakening frame
	approx(float(fin["t"]), 1.0 / 60.0, "finale t = dt after the spawn frame (TS:556/561)")
	eq(rec["banners"][0], {"title": "THE CHAOS CORE AWAKENS",
		"subtitle": "something pulses beyond the outer light", "kind": "chaos", "ttl": 6},
		"the AWAKENS banner (TS:557)")
	eq(rec["audio"][0], ["ascend", 1.0, 0.0], "audio ascend 1 (TS:558)")
	# the bearing fired the SAME frame (ship at (0,−900) → d 1000 → up)
	eq(rec["objectives"][0], "THE CHAOS CORE PULLS — fly 1000px up to the storm",
		"the per-update bearing: d rounded + up/down (TS:566-568)")
	# no re-trigger while the finale exists (TS:554 !this.finale)
	sim.update(1.0 / 60.0, _inp())
	eq(rec["banners"].size(), 1, "no re-trigger while the finale lives (TS:554)")
	approx(float(fin["t"]), 2.0 / 60.0, "finale.t += dt again (TS:561)")

	# the DOWN bearing: the ship below the core (finale.y > sy)
	sim.sx = 0.0
	sim.sy = -2000.0
	sim.update(1.0 / 60.0, _inp())
	eq(rec["objectives"][rec["objectives"].size() - 1], "THE CHAOS CORE PULLS — fly 100px down to the storm",
		"the ship below the core → 'down' (TS:568 ternary)")

	# the d < 60 ENDING (TS:569-573): the win hits disk immediately
	sim.sx = 0.0
	sim.sy = -1850.0  # d 50
	ctx.flags.erase("spaceWorld")
	var audio_n: int = rec["audio"].size()
	sim.update(1.0 / 60.0, _inp())
	eq(bool(sim.endingDone), true, "d < 60 → endingDone (TS:569-570)")
	eq(rec["audio"].size(), audio_n + 1, "the ending ascend (TS:571)")
	ok(ctx.flags.has("spaceWorld"), "the win state persisted immediately (TS:572)")
	eq(bool(JSON.parse_string(String(ctx.flags["spaceWorld"]))["endingDone"]), true,
		"the persisted blob carries endingDone (TS:572)")
	# the objective on the flip frame still showed the PULL line (the write
	# precedes the flip, TS:566 before :569)
	eq(rec["objectives"][rec["objectives"].size() - 1].find("THE CHAOS CORE PULLS") >= 0, true,
		"the flip frame's objective was the pull line (the TS write order)")
	# the post-ending calm line (TS:566-567)
	sim.update(1.0, _inp())
	eq(rec["objectives"][rec["objectives"].size() - 1], tr("the core sleeps — the sandbox is yours"),
		"post-ending → the calm line (TS:567)")
	# endingT started on the FLIP frame (the same-frame :575 +=): 1/60, +1 now
	approx(float(sim.endingT), 1.0 + 1.0 / 60.0, "endingT += dt (TS:576; the flip frame seeded 1/60)")

	# the DISMISS rule (TS:578-581): any unconsumed click or key hands the
	# sandbox back; dismissT = endingT AT the dismiss frame
	sim.update(1.0, _inp({"clicked": true}))
	eq(bool(sim.endingDismissed), true, "an unconsumed click dismisses (TS:578-579)")
	approx(float(sim.dismissT), 2.0 + 1.0 / 60.0, "dismissT = endingT at the dismiss frame (TS:580)")

	# anyKeyPressed also dismisses (TS:578) — a fresh run
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	sim2.endingDone = true
	sim2.update(1.0, _inp({"keys_pressed": ["KeyW"]}))
	eq(bool(sim2.endingDismissed), true, "anyKeyPressed dismisses (TS:578)")
	approx(float(sim2.dismissT), 1.0, "dismissT after one dt-1 frame")

	# a PANEL-CONSUMED click does NOT dismiss (the takeClick chain, TS:416
	# before :578): the ship sits near a scanned planet whose re-survey is on
	# cooldown — the enabled scan rect eats the click
	var m3 := _mk_sim()
	var sim3: Variant = m3["sim"]
	var rec3: Dictionary = m3["rec"]
	_place_planet(sim3, 0, 0.0, -1850.0, 50.0)
	_isolate_planet(sim3, 0)
	sim3.planets[0]["scanned"] = true
	sim3.resurveyCd = 9.0
	sim3.panel_rects = [_rect("scan", true, 700.0, 100.0, 200.0, 40.0)]
	sim3.endingDone = true
	sim3.finale = {"x": 0.0, "y": -1900.0, "active": true, "t": 0.0}
	sim3.sx = 0.0
	sim3.sy = -1850.0
	sim3.update(1.0, _inp({"clicked": true, "mx": 750.0, "my": 110.0}))
	eq(bool(sim3.endingDismissed), false, "a panel-consumed click does NOT dismiss (TS:578 read-after-take)")
	ok(_toasted(rec3, "Survey instruments recharging"), "the panel really consumed the click (the dispatch ran)")
	# a later unconsumed click dismisses
	sim3.update(1.0, _inp({"clicked": true, "mx": 0.0, "my": 0.0}))
	eq(bool(sim3.endingDismissed), true, "the free click dismisses (TS:578)")

	# endingDone blocks a re-trigger + a re-flip (TS:554/569 gates)
	var m4 := _mk_sim()
	var sim4: Variant = m4["sim"]
	var rec4: Dictionary = m4["rec"]
	sim4.endingDone = true
	for i in 3:
		sim4.planets[i]["colony"] = {"pop": 20.0, "generations": 0.0}
	sim4.update(1.0 / 60.0, _inp())
	eq(sim4.finale, null, "endingDone → no new finale on 3 thriving (TS:554)")
	eq(rec4["banners"].size(), 0, "no AWAKENS replay (TS:554)")
	# a live finale + endingDone: d < 60 does NOT re-flip or re-persist
	sim4.finale = {"x": 0.0, "y": -1900.0, "active": true, "t": 0.0}
	sim4.sx = 0.0
	sim4.sy = -1900.0
	var audio_n4: int = rec4["audio"].size()
	sim4.update(1.0 / 60.0, _inp())
	eq(rec4["audio"].size(), audio_n4, "d < 60 post-ending → no second ascend (TS:569 gate)")


# ---- scanPlanet + repairHull (TS:1233-1272) ---------------------------------------------------

func test_scan_and_repair() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	sim.invuln = 0.0
	var p0: Dictionary = _place_planet(sim, 0, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 0)
	sim.sx = 900.0
	sim.sy = 0.0

	# repairHull at full hull → early return (TS:1234)
	sim.shp = 100.0
	ctx.dna = 100
	sim.repair_hull()
	eq(int(ctx.dna), 100, "full hull → no spend (TS:1234)")
	eq(rec["toasts"], [], "no toast at full hull")

	# the spend refusal (TS:1235-1238)
	sim.shp = 50.0
	ctx.dna = 49
	sim.repair_hull()
	eq(rec["toasts"][0], [tr("Not enough DNA"), "bad", "🧬"], "dna 49 → 'Not enough DNA' (TS:1236)")
	eq(float(sim.shp), 50.0, "hull unchanged on the refusal")

	# the repair (TS:1239-1241)
	ctx.dna = 100
	sim.repair_hull()
	eq(float(sim.shp), 100.0, "shp = shpMax (TS:1239)")
	eq(int(ctx.dna), 50, "the repair spent 50 (TS:1235)")
	eq(rec["audio"][0], ["heal", 0.9, 0.0], "audio heal 0.9 (TS:1240)")
	eq(rec["toasts"][1], [tr("Hull fully repaired"), "good", "🔧"], "the repaired toast (TS:1241)")

	# scanPlanet — the fresh scan (TS:1261-1271): discovers EVERY living
	# species, pays 15, toasts the count. The two species carry DISTINCT
	# genomes — identical genomes dedup into ONE bestiary hash.
	var eco: Variant = _craft_eco(sim, 0, [4.0, 2.0])
	var g2: Dictionary = GenomeLib.clone_genome(eco.species[1]["genome"])
	g2["flagella"] = 5
	eco.species[1]["genome"] = g2
	var sp_names: Array = [String(eco.species[0]["name"]), String(eco.species[1]["name"])]
	ctx.dna = 0
	ctx.flags.erase("spaceWorld")
	sim.scan_planet(p0)
	eq(bool(p0["scanned"]), true, "scanned latched (TS:1261)")
	eq(int(ctx.dna), 15, "survey pay 15 (TS:1266)")
	eq(rec["toasts"][2], ["%s +15" % tr("Scan complete: 2 species on %s" % String(p0["name"])),
		"good", "📡"], "the scan toast +15 (TS:1267)")
	eq(rec["audio"][1], ["dna", 0.7, 0.0], "audio dna 0.7 (TS:1271)")
	for sp_name in sp_names:
		var found := false
		for k in ctx.bestiary:
			if String(ctx.bestiary[k]["name"]) == sp_name:
				found = true
		ok(found, "discover rode the scan for '%s' (TS:1263-1264)" % sp_name)
	eq(ctx.flags.has("spaceWorld"), false, "the FRESH scan does NOT persist (no TS persist call)")

	# the eco-null scan (a barren planet) (TS:1268-1270) — the dna audio plays
	# OUTSIDE the if/else for BOTH branches (TS:1271)
	var p3: Dictionary = _place_planet(sim, 3, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 3)
	sim.scan_planet(p3)
	eq(bool(p3["scanned"]), true, "the barren scan latches too (TS:1261)")
	eq(rec["toasts"][3], ["Scan complete: %s is lifeless — bring life!" % String(p3["name"]),
		"info", "📡"], "the lifeless toast (TS:1269)")
	eq(int(ctx.dna), 15, "no pay for a lifeless rock")
	eq(rec["audio"][2], ["dna", 0.7, 0.0], "the lifeless branch STILL plays the dna audio (TS:1271)")

	# the RE-SURVEY trickle (TS:1245-1259): cd 0 → pays 3, sets cd 4, the
	# floatWorld text, dna audio, persists
	ctx.dna = 0
	ctx.flags.erase("spaceWorld")
	sim.scan_planet(p0)
	eq(float(sim.resurveyCd), 4.0, "resurveyCd 4 (TS:1253)")
	eq(int(ctx.dna), 3, "the re-survey pays 3 (TS:1254-1255)")
	eq(rec["floats"][0], [float(p0["x"]), float(p0["y"]) - float(p0["r"]) - 14.0,
		"+3 %s" % tr("survey"), "#8fd0ff", 12.0], "the floatWorld survey text (TS:1256)")
	eq(rec["audio"][3], ["dna", 0.4, 0.0], "audio dna 0.4 (TS:1257)")
	ok(ctx.flags.has("spaceWorld"), "the re-survey persists (TS:1258)")

	# the cooldown gate (TS:1249-1251): cd > 0 → the recharge toast, no pay
	ctx.dna = 10
	sim.scan_planet(p0)
	ok(_toasted(rec, "Survey instruments recharging"), "cd > 0 → the recharge toast (TS:1250)")
	eq(int(ctx.dna), 10, "no pay under the cooldown")
	eq(float(sim.resurveyCd), 4.0, "cd untouched by the gated return (TS:1251)")


# ---- debug_state extension (the documented bot-parity surface) ---------------------------------

func test_debug_state_part2_fields() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.pirates = [{"x": 1.0, "y": 2.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.blackHoles = [{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.beamT = 1.2
	sim.tributeDemand = 5.0
	sim.resurveyCd = 3.0
	sim.pirateLull = true
	sim.endingDismissed = true
	sim.dismissT = 7.0
	sim.endingT = 8.0
	sim.persistT = 2.0
	var st: Dictionary = sim.debug_state()
	# the part-1 fields still ride
	ok(st.has("planets") and st.has("cargo") and st.has("abductCount"), "the part-1 fields still exposed")
	# the part-2 machine fields
	ok(st.has("pirates") and st.has("blackHoles"), "pirates + blackHoles exposed")
	ok(st.has("beamT") and st.has("tributeDemand") and st.has("resurveyCd"), "beamT/tributeDemand/resurveyCd exposed")
	ok(st.has("pirateLull") and st.has("persistT"), "pirateLull/persistT exposed")
	ok(st.has("endingT") and st.has("dismissT"), "endingT/dismissT exposed")
	eq(int(st["pirates"].size()), 1, "the pirates read")
	eq(float(st["beamT"]), 1.2, "the beamT read")
	eq(float(st["tributeDemand"]), 5.0, "the tributeDemand read")
	eq(bool(st["pirateLull"]), true, "the pirateLull read")

