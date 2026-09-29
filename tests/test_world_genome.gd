# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path — a bare global name (WorldGenome,
# Traits, Fixtures) would not resolve without the editor's class cache.
const WorldGenome := preload("res://src/evo/world_genome.gd")
const Traits := preload("res://src/evo/world_traits.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const Genome := preload("res://src/evo/genome.gd")
const RngScript := preload("res://src/core/rng.gd")
const Eco := preload("res://src/evo/ecosystem.gd")

# TS worldGenome.ts signal dict — all keys are single words, so the native
# Dictionary keys are the TS WorldSignals fields verbatim.
func _sig(stage: String, timer: float, chaos: float, kills: float, extinctions: float) -> Dictionary:
	return {"stage": stage, "timer": timer, "chaos": chaos, "kills": kills, "extinctions": extinctions}


func _def(id: String) -> Dictionary:
	for d in Traits.TRAIT_DEFS:
		if d["id"] == id:
			return d
	return {}


func _ids(w: Dictionary) -> Array:
	var ids: Array = []
	for t in w["traits"]:
		ids.append(t["id"])
	return ids


# Hand-built genome (TS WorldGenome object-literal shape) for scripted turn
# scenarios the derive table cannot reach (specific trait/turn pairings).
func _genome(seed: int, trait_ids: Array, turns: Array, revealed: Array) -> Dictionary:
	var traits: Array = []
	for id in trait_ids:
		traits.append(_def(id))
	var rev := {}
	for r in revealed:
		rev[r] = true
	return {
		"seed": seed, "traits": traits, "turns": turns, "firedTurns": {},
		"revealed": rev, "comboFired": {}, "timers": {}, "temperament": "none",
	}


# --- catalog -----------------------------------------------------------------


func test_catalog_trait_defs_match_ts() -> void:
	# 13 defs in TS declaration order: 11 drawable + 2 turn-only replacements.
	var want_ids := ["hungry_bloom", "iron_gut", "toxin_sea", "swift_world", "old_blood",
		"pirate_wind", "calm_veil", "mutation_moon", "world_temperament",
		"temperament_bands", "kin_memory", "false_wing", "trophic_release"]
	eq(Traits.TRAIT_DEFS.size(), 13, "catalog pins exactly 13 trait defs")
	var ids: Array = []
	for d in Traits.TRAIT_DEFS:
		ids.append(d["id"])
	eq(ids, want_ids, "trait ids match the TS catalog, declaration order included")
	# turn-only replacements never draw (weight 0, turnOnly true); the rest draw
	for d in Traits.TRAIT_DEFS:
		var turn_only: bool = d.get("turnOnly", false) == true
		eq(turn_only, d["id"] == "false_wing" or d["id"] == "trophic_release",
				"turnOnly flags: %s" % d["id"])
		if turn_only:
			eq(d["weight"], 0, "turn-only %s has weight 0" % d["id"])
		else:
			ok(float(d["weight"]) > 0.0, "drawable %s has weight > 0" % d["id"])
		ok(d["excludes"] is Array, "%s carries an excludes list" % d["id"])
		ok(d["effects"] is Array and d["reveal"] is Dictionary, "%s carries effects + reveal" % d["id"])
	# spot-check the shape-carrying defs (ecoSeed corners, num values, flags)
	eq(_def("hungry_bloom")["effects"][0],
			{"kind": "num", "key": "herb_drain_mult", "value": 1.6}, "hungry_bloom num effect")
	eq(_def("hungry_bloom")["effects"][1],
			{"kind": "ecoSeed", "archetype": "herbivore", "weight": 1.5}, "hungry_bloom ecoSeed")
	eq(_def("old_blood")["effects"][1],
			{"kind": "ecoSeed", "archetype": "titan", "weight": 2.0}, "old_blood titan corner (weight 2)")
	eq(_def("calm_veil")["effects"][1],
			{"kind": "num", "key": "speciation_mult", "value": 0.8}, "calm_veil sub-1 speciation")
	eq(_def("mutation_moon")["effects"],
			[{"kind": "num", "key": "mutation_rate_add", "value": 0.15},
				{"kind": "flag", "key": "wild_mutations", "value": true}], "mutation_moon num + flag")
	eq(_def("world_temperament")["effects"],
			[{"kind": "flag", "key": "world_temperament", "value": true}], "world_temperament flag")
	# exclusions are catalog-verbatim (calm_veil is one-sided vs mutation_moon —
	# derive enforces the mutual rule at draw time)
	eq(_def("calm_veil")["excludes"], ["hungry_bloom", "swift_world", "pirate_wind"], "calm_veil excludes")
	eq(_def("mutation_moon")["excludes"], ["calm_veil"], "mutation_moon excludes calm_veil (one-sided)")
	eq(_def("iron_gut")["excludes"], [], "iron_gut excludes nothing")


func test_catalog_combos_turns_words_patch_keys() -> void:
	eq(Traits.COMBO_DEFS.size(), 5, "catalog pins exactly 5 combo defs")
	var want := {
		"rot_circle": [["hungry_bloom", "toxin_sea"], "extinct"],
		"war_graves": [["old_blood", "pirate_wind"], "stageTime"],
		"corpse_tide": [["iron_gut", "toxin_sea"], "kill"],
		"selection_sweep": [["mutation_moon", "toxin_sea"], "chaos"],
		"borrowed_flesh": [["swift_world", "old_blood"], "stageEnter"],
	}
	for c in Traits.COMBO_DEFS:
		ok(want.has(c["id"]), "combo id %s is catalog-verbatim" % c["id"])
		eq(c["requires"], want[c["id"]][0], "combo %s requires pair" % c["id"])
		eq(c["trigger"]["kind"], want[c["id"]][1], "combo %s trigger kind" % c["id"])
		eq(c["effects"], [{"kind": "flag", "key": c["id"], "value": true}],
				"combo %s carries its own flag" % c["id"])
	# INCLUSIVE chaos boundary pin: selection_sweep/toxin_sea trigger above 0.45
	eq(_def("toxin_sea")["reveal"], {"kind": "chaos", "above": 0.45}, "toxin_sea reveal (inclusive >= 0.45)")
	eq(Traits.COMBO_DEFS[3]["trigger"], {"kind": "chaos", "above": 0.45}, "selection_sweep trigger (inclusive >= 0.45)")

	eq(Traits.WORLD_TURN_DEFS.size(), 3, "catalog pins exactly 3 world-turn defs")
	eq(Traits.WORLD_TURN_DEFS[0],
			{"id": "great_frost", "replaces": "hungry_bloom", "replacement": "calm_veil",
				"trigger": {"kind": "chaos", "above": 0.75}, "sigil": "❄️",
				"title": "The Great Frost",
				"body": "The bloom froze mid-bite. This world grows slower, quieter now."},
			"great_frost def verbatim")
	eq(Traits.WORLD_TURN_DEFS[1]["replaces"], "swift_world", "epoch_gate replaces swift_world")
	eq(Traits.WORLD_TURN_DEFS[1]["replacement"], "false_wing", "epoch_gate -> false_wing (turn-only)")
	eq(Traits.WORLD_TURN_DEFS[2]["replaces"], "old_blood", "epoch_apex replaces old_blood")
	eq(Traits.WORLD_TURN_DEFS[2]["replacement"], "trophic_release", "epoch_apex -> trophic_release (turn-only)")

	eq(Traits.WORLD_ADJ, ["ancient", "restless", "patient", "voracious", "gentle",
		"burning", "sunken", "hidden", "howling", "cracked"], "WORLD_ADJ 10 words")
	eq(Traits.WORLD_NOUN, ["ocean", "cradle", "garden", "furnace", "veil",
		"deep", "march", "seedbed", "mirror", "engine"], "WORLD_NOUN 10 words")

	eq(Traits.PATCH_KEYS, ["growth_mult", "predation_mult", "speciation_mult",
		"meal_dna_mult", "herb_drain_mult", "mutation_rate_add"], "PATCH_KEYS union")


# --- derive: fixture table + determinism + bounds + exclusions ----------------


func test_fixture_derive_table_20_seeds() -> void:
	var data := Fixtures.load_json("world_genome")
	ok(not data.is_empty(), "fixture world_genome.json loads")
	var seeds: Array = data["seeds"]
	eq(seeds.size(), 20, "fixture pins seeds 0..19")
	for entry in seeds:
		var seed: int = int(entry["seed"])
		var w: Dictionary = WorldGenome.derive_world_genome(seed)
		eq(_ids(w), entry["traitIds"], "seed %d traitIds (draw order)" % seed)
		eq(w["temperament"], entry["temperament"], "seed %d temperament" % seed)
		eq(w["turns"], entry["turnIds"], "seed %d turnIds (0-2, competing pool)" % seed)


func test_derived_genome_dict_shape() -> void:
	var w: Dictionary = WorldGenome.derive_world_genome(0)
	var keys: Array = w.keys()
	keys.sort()
	eq(keys, ["comboFired", "firedTurns", "revealed", "seed", "temperament",
		"timers", "traits", "turns"], "genome carries the 8 TS fields verbatim")
	eq(w["firedTurns"], {}, "fresh genome: firedTurns empty")
	eq(w["revealed"], {}, "fresh genome: revealed empty")
	eq(w["comboFired"], {}, "fresh genome: comboFired empty")
	eq(w["timers"], {}, "fresh genome: timers empty (Game-owned clock)")
	# traits are the shared catalog defs (TS object identity semantics)
	ok(Traits.TRAIT_DEFS.has(w["traits"][0]), "genome traits are catalog def objects")


func test_1000_seed_determinism_and_bounds() -> void:
	var bad := -1
	var bad_why := ""
	for seed in range(1000):
		var a: Dictionary = WorldGenome.derive_world_genome(seed)
		var b: Dictionary = WorldGenome.derive_world_genome(seed)
		if _ids(a) != _ids(b):
			bad = seed
			bad_why = "trait set differs on re-derive"
			break
		if a["turns"] != b["turns"] or a["temperament"] != b["temperament"]:
			bad = seed
			bad_why = "turns/temperament differ on re-derive"
			break
		var n: int = a["traits"].size()
		if n < 4 or n > 6:
			bad = seed
			bad_why = "trait count %d outside 4..6" % n
			break
		if a["turns"].size() > 2:
			bad = seed
			bad_why = "turn count %d outside 0..2" % a["turns"].size()
			break
		var finite := true
		for t in a["traits"]:
			for e in t["effects"]:
				for k in ["value", "weight"]:
					if e.has(k) and (e[k] is float or e[k] is int) and not is_finite(float(e[k])):
						finite = false
		if not finite:
			bad = seed
			bad_why = "non-finite effect number"
			break
		# temperament is one of the four TS literal values, always present
		if not ["none", "cradle", "lean", "wildcard"].has(a["temperament"]):
			bad = seed
			bad_why = "temperament %s out of band" % a["temperament"]
			break
	ok(bad < 0, "1000 seeds: deterministic, 4-6 traits, 0-2 turns, finite, banded (first bad: seed %d %s)" % [bad, bad_why])


func test_1000_seed_mutual_exclusion() -> void:
	# Spec: traits exclude each other — no excluded pair may co-occur in ANY
	# derived genome, regardless of draw order (calm_veil vs mutation_moon is
	# one-sided in the catalog, so draw-time enforcement is load-bearing).
	var bad := -1
	var bad_pair := ""
	for seed in range(1000):
		var w: Dictionary = WorldGenome.derive_world_genome(seed)
		var ids: Array = _ids(w)
		var found := false
		for t in w["traits"]:
			for ex in t["excludes"]:
				if ids.has(ex):
					bad = seed
					bad_pair = "%s<->%s" % [t["id"], ex]
					found = true
					break
			if found:
				break
		if found:
			break
	ok(bad < 0, "1000 seeds: no excluded pair co-occurs (first: seed %d %s)" % [bad, bad_pair])


# --- accessors ----------------------------------------------------------------


func test_world_num_first_wins_and_fallback() -> void:
	var w: Dictionary = WorldGenome.derive_world_genome(0)
	# old_blood (meal_dna_mult 0.9) draws BEFORE iron_gut (1.2) — first wins
	approx(WorldGenome.world_num(w, "meal_dna_mult", 9.9), 0.9, "seed 0 meal_dna_mult first-wins", 1e-9)
	approx(WorldGenome.world_num(w, "growth_mult", 1.0), 1.0, "absent key returns the fallback", 1e-9)
	approx(WorldGenome.world_num(WorldGenome.derive_world_genome(2), "mutation_rate_add", 0.0),
			0.15, "seed 2 mutation_rate_add (PatchKey outside EcoMods)", 1e-9)
	# first-wins across traits, in genome order
	var two := {"traits": [
		{"effects": [{"kind": "num", "key": "growth_mult", "value": 1.25}]},
		{"effects": [{"kind": "num", "key": "growth_mult", "value": 3.0}]},
	]}
	approx(WorldGenome.world_num(two, "growth_mult", 0.0), 1.25, "first-wins across traits", 1e-9)


func test_world_has_tolerant_shapes() -> void:
	ok(not WorldGenome.world_has(WorldGenome.derive_world_genome(0), "kin_grudge"),
			"seed 0 carries no kin_grudge flag")
	ok(WorldGenome.world_has(WorldGenome.derive_world_genome(2), "kin_grudge"),
			"seed 2 (kin_memory) carries the kin_grudge flag")
	# raw eco-shaped world blobs read through the same door (eco delegation)
	ok(WorldGenome.world_has({"traits": [{"effects": [{"kind": "flag", "key": "kin_grudge"}]}]}, "kin_grudge"),
			"raw {traits:[{effects:[...]}]} blob reads")
	ok(not WorldGenome.world_has({}, "kin_grudge"), "absent traits -> false (gate stays shut)")
	ok(not WorldGenome.world_has({"traits": "junk"}, "kin_grudge"), "non-array traits -> false")
	ok(not WorldGenome.world_has({"traits": [null, 7]}, "kin_grudge"), "junk trait rows -> false")
	ok(not WorldGenome.world_has({"traits": [{"effects": "junk"}]}, "kin_grudge"), "junk effects -> false")


func test_archetype_weights() -> void:
	var w: Dictionary = WorldGenome.derive_world_genome(0)
	var aw: Dictionary = WorldGenome.archetype_weights(w)
	eq(aw.size(), 3, "seed 0 seeds three archetypes")
	approx(float(aw["titan"]), 2.0, "titan weight (old_blood)", 1e-9)
	approx(float(aw["herbivore"]), 1.5, "herbivore weight (hungry_bloom)", 1e-9)
	approx(float(aw["carnivore"]), 1.4, "carnivore weight (iron_gut)", 1e-9)
	# same archetype multiplies: (absent ?? 1) * weight, per ecoSeed effect
	var two := {"traits": [
		{"effects": [{"kind": "ecoSeed", "archetype": "swarm", "weight": 1.5}]},
		{"effects": [{"kind": "ecoSeed", "archetype": "swarm", "weight": 1.3}]},
	]}
	approx(float(WorldGenome.archetype_weights(two)["swarm"]), 1.95, "repeat archetype multiplies", 1e-9)
	eq(WorldGenome.archetype_weights({"traits": []}), {}, "no ecoSeeds -> empty weights")


func test_calm_proxy() -> void:
	ok(WorldGenome.calm_proxy(WorldGenome.derive_world_genome(6)),
			"seed 6 (calm_veil, speciation_mult 0.8) is a calm world")
	ok(not WorldGenome.calm_proxy(WorldGenome.derive_world_genome(0)),
			"seed 0 (no speciation_mult, fallback 1) is not")


# --- fixture walks (reveal / combo / boundaries) ------------------------------


# Runs one fixture walk (steps carry state; fresh derive per walk). Asserts
# every step's newly-revealed ids, fired combos and turn, then the final state.
# Returns the walked genome for follow-on assertions (eco mods etc.).
func _walk_fixture(seed: int) -> Dictionary:
	var data := Fixtures.load_json("world_genome")
	ok(not data.is_empty(), "fixture world_genome.json loads")
	var walk: Dictionary = data["walks"]["seed%d" % seed]
	var w: Dictionary = WorldGenome.derive_world_genome(seed)
	for step in walk["steps"]:
		var s: Dictionary = step["signals"]
		var sig := _sig(s["stage"], float(s["timer"]), float(s["chaos"]), float(s["kills"]), float(s["extinctions"]))
		var out: Dictionary = WorldGenome.tick_world_reveals(w, sig)
		eq(out["revealed"], step["revealed"], "seed%d step %d revealed (%s)" % [seed, step["step"], step["why"]])
		eq(out["combos"], step["combos"], "seed%d step %d combos" % [seed, step["step"]])
		eq(out.get("turn", null), step["turn"], "seed%d step %d turn" % [seed, step["step"]])
	var fin: Dictionary = walk["final"]
	eq(_ids(w), fin["traitIds"], "seed%d walk final traitIds" % seed)
	eq(w["temperament"], fin["temperament"], "seed%d walk final temperament" % seed)
	eq(w["revealed"], fin["revealed"], "seed%d walk final revealed" % seed)
	eq(w["comboFired"], fin["comboFired"], "seed%d walk final comboFired" % seed)
	eq(w["firedTurns"], fin["firedTurns"], "seed%d walk final firedTurns" % seed)
	return w


func test_fixture_walk_seed0_all_condition_kinds_and_boundaries() -> void:
	_walk_fixture(0)


func test_fixture_walk_seed2_combos_and_inclusive_chaos_boundary() -> void:
	# pins: chaos 0.45 reveals toxin_sea INCLUSIVELY, a trait revealed this tick
	# can complete a combo the same tick, combos fire exactly once
	var w: Dictionary = _walk_fixture(2)
	ok(WorldGenome.combo_active(w, "selection_sweep"), "selection_sweep live after the walk")
	ok(WorldGenome.combo_active(w, "rot_circle"), "rot_circle live after the walk")


# --- eco-side combo effects ---------------------------------------------------


func test_eco_mods_from_world_shape() -> void:
	# fresh seed 0: numeric mods only (first-wins), no combo flags, no absent keys
	eq(WorldGenome.eco_mods_from_world(WorldGenome.derive_world_genome(0)),
			{"meal_dna_mult": 0.9, "herb_drain_mult": 1.6},
			"seed 0 mods: first-wins numbers, no combo flags, no absent keys")
	# seed 2 after the fixture walk: both combo flags live beside the numbers
	var w: Dictionary = _walk_fixture(2)
	eq(WorldGenome.eco_mods_from_world(w),
			{"herb_drain_mult": 1.6, "selection_sweep": true, "rot_circle": true},
			"seed 2 fired mods: TS EcoMods shape verbatim")
	# empty genome -> empty mods (world mod additions inert under empty mods)
	eq(WorldGenome.eco_mods_from_world({"traits": []}), {}, "no traits -> empty mods")


func test_eco_reads_derived_genome_and_fired_mods() -> void:
	# the eco's kin gate consumes a REAL derived genome (seed 2 carries kin_memory)
	var eco: Variant = Eco.new(RngScript.new_from(7))
	eco.add_species(Genome.default_genome(), 5.0)
	eco.designate_kin_tag(WorldGenome.derive_world_genome(2))
	var tagged := 0
	for s in eco.species:
		if s.get("kin_tag") == true:
			tagged += 1
	eq(tagged, 1, "kin_memory genome gates the kin tag on")
	# seed 0 carries no flags — the gate stays shut
	var eco2: Variant = Eco.new(RngScript.new_from(7))
	eco2.add_species(Genome.default_genome(), 5.0)
	eco2.designate_kin_tag(WorldGenome.derive_world_genome(0))
	tagged = 0
	for s in eco2.species:
		if s.get("kin_tag") == true:
			tagged += 1
	eq(tagged, 0, "flag-less genome gates the kin tag off")
	# fired combo mods ride the eco's mods dict without breaking a tick
	var eco3: Variant = Eco.new(RngScript.new_from(7))
	eco3.mods = WorldGenome.eco_mods_from_world(_walk_fixture(2))
	var res: Dictionary = eco3.tick(1.0)
	ok(res.has("extinctions") and res.has("speciations"), "eco tick with live world mods runs")


# --- scripted turn walks (beyond the fixture: turns, top-up, exclusion) -------


func test_turn_swap_excludes_clashing_survivors() -> void:
	# TS pin (SWAP-B): great_frost replaces hungry_bloom with calm_veil;
	# swift_world clashes with calm_veil in BOTH directions -> dropped
	var w: Dictionary = _genome(0, ["hungry_bloom", "swift_world", "toxin_sea", "iron_gut"],
			["great_frost"], ["hungry_bloom", "toxin_sea"])
	var out: Dictionary = WorldGenome.tick_world_reveals(w, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	eq(out.get("turn", null), "great_frost", "great_frost fires at chaos 0.8")
	eq(out["revealed"], ["calm_veil"], "replacement pushed into out.revealed (announce pump)")
	eq(_ids(w), ["toxin_sea", "iron_gut", "calm_veil"],
			"survivors keep order, clashers dropped, replacement appended last")
	eq(w["revealed"]["calm_veil"], true, "replacement flagged revealed in the genome")
	eq(w["firedTurns"], {"great_frost": true}, "turn marked fired")


func test_turn_top_up_to_three() -> void:
	# TS pin (TOPUP-A): the swap leaves the world thin (2 traits) — the
	# seed-branched rng (seed ^ 0x7a9e) tops up to >= 3 from the eligible pool
	var w: Dictionary = _genome(0, ["hungry_bloom", "toxin_sea"], ["great_frost"],
			["hungry_bloom", "toxin_sea"])
	var out: Dictionary = WorldGenome.tick_world_reveals(w, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	eq(out["revealed"], ["calm_veil"], "only the replacement announced (top-up is silent)")
	eq(_ids(w), ["toxin_sea", "calm_veil", "old_blood"], "top-up pulls old_blood (seed 0 ^ 0x7a9e)")
	eq(w["temperament"], "none", "top-up did not draw world_temperament: temperament untouched")
	ok(not WorldGenome.world_has(w, "wild_mutations"), "top-up carried no flag side effects")
	# the refill is deterministic: same scenario -> same top-up
	var w2: Dictionary = _genome(0, ["hungry_bloom", "toxin_sea"], ["great_frost"],
			["hungry_bloom", "toxin_sea"])
	WorldGenome.tick_world_reveals(w2, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	eq(_ids(w2), _ids(w), "top-up deterministic across identical scenarios")


func test_turn_top_up_respects_exclusions() -> void:
	# a thin world left by calm_veil's arrival must not top up a calm_veil clash
	var w: Dictionary = _genome(0, ["hungry_bloom", "toxin_sea"], ["great_frost"],
			["hungry_bloom", "toxin_sea"])
	WorldGenome.tick_world_reveals(w, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	var ids: Array = _ids(w)
	eq(ids.size(), 3, "world topped up to 3")
	for t in w["traits"]:
		for ex in t["excludes"]:
			ok(not ids.has(ex), "post-top-up exclusion holds for %s -> %s" % [t["id"], ex])


func test_turn_sequence_one_per_tick() -> void:
	# TS pin (PER-TICK): BOTH turn triggers met in tick 1 — epoch_apex fires
	# (first in w.turns), great_frost waits a tick. rot_circle fires in tick 1
	# off persisted reveal flags (hungry_bloom not replaced until tick 2).
	var w: Dictionary = _genome(0, ["hungry_bloom", "old_blood", "toxin_sea", "iron_gut"],
			["epoch_apex", "great_frost"], ["hungry_bloom", "old_blood", "toxin_sea", "iron_gut"])
	var o1: Dictionary = WorldGenome.tick_world_reveals(w, _sig("cell", 0.0, 0.8, 0.0, 1.0))
	eq(o1.get("turn", null), "epoch_apex", "tick 1: first turn in w.turns wins, one per tick")
	eq(o1["combos"], ["rot_circle"], "tick 1: rot_circle fires (both legs revealed)")
	eq(o1["revealed"], ["trophic_release"], "tick 1: replacement announced")
	var o2: Dictionary = WorldGenome.tick_world_reveals(w, _sig("cell", 0.0, 0.8, 0.0, 1.0))
	eq(o2.get("turn", null), "great_frost", "tick 2: the second turn fires")
	eq(o2["combos"], [], "tick 2: rot_circle does not refire")
	eq(_ids(w), ["toxin_sea", "iron_gut", "trophic_release", "calm_veil"],
			"two sequential replacements compose")


func test_turn_sequence_frost_then_apex_with_rot_circle_after_replacement() -> void:
	# TS pin (SEQ-C): great_frost removes hungry_bloom, yet rot_circle still
	# fires next tick — revealed flags persist by id through replacements.
	var w: Dictionary = _genome(0, ["hungry_bloom", "old_blood", "toxin_sea", "iron_gut"],
			["great_frost", "epoch_apex"], ["hungry_bloom", "old_blood", "toxin_sea", "iron_gut"])
	var o1: Dictionary = WorldGenome.tick_world_reveals(w, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	eq(o1.get("turn", null), "great_frost", "tick 1: great_frost (apex trigger not yet met)")
	var o2: Dictionary = WorldGenome.tick_world_reveals(w, _sig("cell", 0.0, 0.8, 0.0, 1.0))
	eq(o2.get("turn", null), "epoch_apex", "tick 2: epoch_apex fires")
	eq(o2["combos"], ["rot_circle"], "tick 2: rot_circle fires — revealed flags outlive the replaced trait")
	eq(o2["revealed"], ["trophic_release"], "tick 2: trophic_release announced")
	eq(_ids(w), ["toxin_sea", "iron_gut", "calm_veil", "trophic_release"], "final composition")


func test_turn_epoch_gate_brings_false_wing() -> void:
	# TS pin (GATE-D): epoch_gate swaps swift_world for the turn-only false_wing
	var w: Dictionary = _genome(0, ["swift_world", "toxin_sea", "iron_gut"],
			["epoch_gate"], ["swift_world", "toxin_sea", "iron_gut"])
	var out: Dictionary = WorldGenome.tick_world_reveals(w, _sig("creature", 0.0, 0.0, 0.0, 0.0))
	eq(out.get("turn", null), "epoch_gate", "epoch_gate fires on creature enter")
	eq(out["revealed"], ["false_wing"], "false_wing announced via out.revealed")
	eq(_ids(w), ["toxin_sea", "iron_gut", "false_wing"], "false_wing rides the genome (3 traits, no top-up)")
	eq(w["revealed"]["false_wing"], true, "false_wing flagged revealed")


func test_turn_gates() -> void:
	# old trait not revealed -> no fire
	var w1: Dictionary = _genome(0, ["hungry_bloom", "toxin_sea"], ["great_frost"], ["toxin_sea"])
	var o1: Dictionary = WorldGenome.tick_world_reveals(w1, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	ok(not o1.has("turn"), "unrevealed replaced trait: no turn")
	eq(_ids(w1), ["hungry_bloom", "toxin_sea"], "unrevealed: traits untouched")
	# trigger unmet -> no fire
	var w2: Dictionary = _genome(0, ["hungry_bloom", "toxin_sea"], ["great_frost"],
			["hungry_bloom", "toxin_sea"])
	var o2: Dictionary = WorldGenome.tick_world_reveals(w2, _sig("cell", 0.0, 0.5, 0.0, 0.0))
	ok(not o2.has("turn"), "chaos 0.5 < 0.75: no turn")
	# replaced trait already gone from the genome -> no fire (its revealed flag
	# alone is not enough — the trait must still be carried)
	var w3: Dictionary = _genome(0, ["toxin_sea"], ["great_frost"], ["hungry_bloom", "toxin_sea"])
	var o3: Dictionary = WorldGenome.tick_world_reveals(w3, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	ok(not o3.has("turn"), "replaced trait absent from genome: no turn")
	# a fired turn never refires
	var w4: Dictionary = _genome(0, ["hungry_bloom", "swift_world", "toxin_sea", "iron_gut"],
			["great_frost"], ["hungry_bloom", "toxin_sea"])
	WorldGenome.tick_world_reveals(w4, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	var o4: Dictionary = WorldGenome.tick_world_reveals(w4, _sig("cell", 0.0, 0.8, 0.0, 0.0))
	ok(not o4.has("turn"), "fired turn does not refire")
	eq(_ids(w4), ["toxin_sea", "iron_gut", "calm_veil"], "state stable after the fired turn")


func test_tick_never_touches_timers() -> void:
	# w.timers is Game-owned: the pump reads seconds from the incoming signals
	# and must not write the genome's timer ledger (TS tickWorldReveals never
	# touches w.timers)
	var w: Dictionary = WorldGenome.derive_world_genome(0)
	for i in 5:
		WorldGenome.tick_world_reveals(w, _sig("cell", 500.0, 0.9, 20.0, 3.0))
	eq(w["timers"], {}, "timers untouched after 5 ticks")
	ok(not w["timers"].has("cell"), "no per-stage timer key created")


# --- title / bands / dominance / mirror ---------------------------------------


func test_world_title_pins() -> void:
	# TS worldTitleParts: own Rng stream (seed ^ 0x1017), one pick per list
	eq(WorldGenome.world_title(0), "The restless cradle", "title seed 0")
	eq(WorldGenome.world_title(1), "The sunken mirror", "title seed 1")
	eq(WorldGenome.world_title(2), "The howling mirror", "title seed 2")
	eq(WorldGenome.world_title(3), "The howling seedbed", "title seed 3")
	# seed 4119 XORs the stream to 0 — both sides map a 0 seed to 0x9e3779b9
	eq(WorldGenome.world_title(4119), "The voracious cradle", "title seed 4119 (0-stream guard)")


func test_behavior_band() -> void:
	# no temperament_bands trait -> neutral band
	var bare: Dictionary = WorldGenome.behavior_band({"traits": [], "seed": 12345}, "sp0_abc")
	approx(float(bare["aggression"]), 1.0, "no flag: aggression 1", 1e-9)
	approx(float(bare["fear"]), 1.0, "no flag: fear 1", 1e-9)
	# TS pins: toFixed(3) rounding, seed+species hash stream (two draws: aggr then fear)
	var b1: Dictionary = WorldGenome.behavior_band(
			{"traits": [_def("temperament_bands")], "seed": 12345}, "sp0_abc")
	approx(float(b1["aggression"]), 1.262, "band 12345/sp0_abc aggression", 1e-9)
	approx(float(b1["fear"]), 1.232, "band 12345/sp0_abc fear", 1e-9)
	var b2: Dictionary = WorldGenome.behavior_band(
			{"traits": [_def("temperament_bands")], "seed": 0}, "player")
	approx(float(b2["aggression"]), 0.813, "band 0/player aggression", 1e-9)
	approx(float(b2["fear"]), 1.168, "band 0/player fear", 1e-9)
	var b3: Dictionary = WorldGenome.behavior_band(
			{"traits": [_def("temperament_bands")], "seed": 999}, "sp3_quor")
	approx(float(b3["aggression"]), 0.993, "band 999/sp3_quor aggression", 1e-9)
	approx(float(b3["fear"]), 1.255, "band 999/sp3_quor fear", 1e-9)


func test_dominance_severity() -> void:
	eq(WorldGenome.DOMINANCE_THRESHOLD, 0.6, "DOMINANCE_THRESHOLD 0.6")
	approx(WorldGenome.dominance_severity(0.0), 1.0, "low share: severity 1", 1e-9)
	approx(WorldGenome.dominance_severity(0.6), 1.0, "at threshold: severity 1 (inclusive)", 1e-9)
	approx(WorldGenome.dominance_severity(0.7), 1.2, "sub-linear ramp: 0.7 -> 1.2", 1e-9)
	approx(WorldGenome.dominance_severity(1.0), 1.8, "1.0 -> cap 1.8", 1e-9)
	approx(WorldGenome.dominance_severity(5.0), 1.8, "hard cap holds", 1e-9)


func test_mirror_bucket() -> void:
	# trait-drawn temperament passes straight through
	eq(WorldGenome.mirror_bucket({"traits": [], "seed": 0, "temperament": "lean"}), "lean",
			"drawn temperament passes through")
	# hidden temperament: seed-branched stream (seed ^ 0x5eed) — TS pins.
	# Hand-built worlds with temperament "none" isolate the hidden path (a
	# derived genome may carry a drawn temperament, which passes through).
	eq(WorldGenome.mirror_bucket({"traits": [], "seed": 0, "temperament": "none"}), "wildcard",
			"hidden bucket seed 0")
	eq(WorldGenome.mirror_bucket({"traits": [], "seed": 7, "temperament": "none"}), "cradle",
			"hidden bucket seed 7")
	eq(WorldGenome.mirror_bucket({"traits": [], "seed": 4119, "temperament": "none"}), "wildcard",
			"hidden bucket seed 4119 (0-stream guard)")
	eq(WorldGenome.mirror_bucket({"traits": [], "seed": 12345, "temperament": "none"}), "cradle",
			"hidden bucket seed 12345")
	# object-literal genomes omit temperament — same hidden path as "none"
	eq(WorldGenome.mirror_bucket({"traits": [], "seed": 0}), "wildcard",
			"absent temperament reads the hidden stream")
	# pure: no rng stream disturbance, no state writes
	var w: Dictionary = WorldGenome.derive_world_genome(0)
	WorldGenome.mirror_bucket(w)
	eq(w["temperament"], "none", "mirror_bucket does not write the genome")
