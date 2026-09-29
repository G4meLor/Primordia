# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path.
const Rng := preload("res://src/core/rng.gd")
const Names := preload("res://src/evo/names.gd")
const Genome := preload("res://src/evo/genome.gd")

# Literal pins captured from the frozen TS source via a one-off vitest run
# (~/Desktop/RD/Spore tools/names-pin.test.ts, `npx vitest run --config
# tools/vitest.config.ts tools/names-pin.test.ts` — output copied verbatim;
# the pin file is not committed to the TS repo).


func _genome(over: Dictionary) -> Dictionary:
	var g: Dictionary = Genome.default_genome()
	g.merge(over, true)
	return g


func test_species_name_seed9_sequence_matches_ts() -> void:
	# speciesName x10 drained from ONE Rng(9) — pins syllable pools + rng order.
	var r: Variant = Rng.new_from(9)
	var expected := [
		"Oogglotraora", "Fwipeep", "Kriwaex", "Nimzosiung", "Yipboax",
		"Mibriwaimus", "Zorridoodon", "Zorwarimax", "Grubung", "Phlorniex",
	]
	for i in expected.size():
		eq(Names.species_name(r), expected[i], "species_name seed 9 seq %d" % i)


func test_species_name_fresh_rng_matches_ts() -> void:
	# One call per fresh rng — pins per-seed determinism (save stability).
	eq(Names.species_name(Rng.new_from(0)), "Yipung", "species_name fresh seed 0")
	eq(Names.species_name(Rng.new_from(1)), "Drokapus", "species_name fresh seed 1")
	eq(Names.species_name(Rng.new_from(42)), "Plimtraung", "species_name fresh seed 42")
	eq(Names.species_name(Rng.new_from(1234)), "Zorbonibus", "species_name fresh seed 1234")
	eq(Names.species_name(Rng.new_from(987654321)), "Krunkbus", "species_name fresh seed 987654321")


func test_epithet_no_match_returns_empty_without_rng_draw() -> void:
	# Default genome matches no EPITHETS test -> '' and the rng is untouched
	# (TS filter finds nothing and returns before any pick).
	var r: Variant = Rng.new_from(5)
	eq(Names.epithet(_genome({}), r), "", "epithet default genome -> ''")
	# the next species_name continues the seed-5 stream exactly as if epithet
	# had never been called (pin: TS "species after-empty seed=5")
	eq(Names.species_name(r), "Fwipnakumax", "rng state unchanged by empty epithet")


func test_epithet_single_category_matches_ts() -> void:
	eq(Names.epithet(_genome({"spikes": 4}), Rng.new_from(11)), "the Pincushion", "spikes seed 11")
	eq(Names.epithet(_genome({"spikes": 4}), Rng.new_from(12)), "the Spiky", "spikes seed 12")
	eq(Names.epithet(_genome({"spikes": 4}), Rng.new_from(13)), "the Pincushion", "spikes seed 13")
	eq(Names.epithet(_genome({"diet": "carnivore"}), Rng.new_from(21)), "Maneater", "carnivore seed 21")
	eq(Names.epithet(_genome({"pattern": "glow"}), Rng.new_from(22)), "the Radiant", "glow seed 22")
	eq(Names.epithet(_genome({"size": 0.7}), Rng.new_from(23)), "the Tiny", "size 0.7 seed 23")


func test_epithet_many_matches_pin_pick_order() -> void:
	# Genome matching 10 EPITHETS entries — pins the double draw
	# pick(pick(matches).ep): outer pick over the filtered table, inner over
	# the chosen pool, six draws from one rng.
	var g := _genome({
		"spikes": 4, "toxin": 3, "eyes": 4, "wings": 1, "horns": 3, "brain": 3,
		"size": 1.8, "diet": "carnivore", "pattern": "glow", "legs": 6,
	})
	var r: Variant = Rng.new_from(77)
	var expected := ["Crownhorned", "Mountainborn", "the Foul", "the Luminous", "the Spiky", "Many-legged"]
	for i in expected.size():
		eq(Names.epithet(g, r), expected[i], "epithet many seed 77 seq %d" % i)


func test_full_species_name_matches_ts() -> void:
	# name + epithet share one rng: the name consumes first, then the epithet.
	eq(Names.full_species_name(_genome({"spikes": 4}), Rng.new_from(31)),
			"Fwipsibaolops the Spiky", "full spikes seed 31")
	eq(Names.full_species_name(_genome({
			"spikes": 4, "toxin": 3, "eyes": 4, "wings": 1, "horns": 3, "brain": 3,
			"size": 1.8, "diet": "carnivore", "pattern": "glow", "legs": 6,
		}), Rng.new_from(32)),
			"Squibnaboapus Crownhorned", "full many seed 32")
	# no epithet -> bare name, no trailing space
	eq(Names.full_species_name(_genome({}), Rng.new_from(33)),
			"Vexkubaodon", "full plain seed 33")


func test_self_name_matches_ts() -> void:
	eq(Names.self_name(_genome({})), "Squishpuff", "self default genome")
	eq(Names.self_name(_genome({
			"diet": "carnivore", "spikes": 3, "eyes": 3, "toxin": 2,
			"wings": 1, "horns": 2, "brain": 3,
		})), "FangSpikePeepStinkFlapHornBrainpuff", "self all trait bits (order fixed)")
	eq(Names.self_name(_genome({"diet": "herbivore", "hue": 0.0, "size": 1.0})), "Leafpuff", "self leaf")
	eq(Names.self_name(_genome({"hue": 214.0, "size": 1.0})), "Squishpuff", "self hue 214")


func test_self_name_tail_rounds_like_js_math_round() -> void:
	# JS Math.round rounds halves toward +infinity; GDScript roundi() rounds
	# halves away from zero — the port uses floor(x + 0.5). Pin the boundary:
	# hue*7 + size*13 = 13.5 -> JS 14 -> 14 % 7 = 0 -> "ington" (a naive
	# roundi() port would give 13 % 7 = 6 -> "puff").
	eq(Names.self_name(_genome({"hue": 0.07142857142857142, "size": 1.0})),
			"Squishington", "self hue*7+13 = 13.5 rounds up like Math.round")
	# fallback split: size > 1.4 -> Chonk, else Squish (tail from hue 120:
	# 120*7 + size*13 -> 858.2/859.5 round to 858/860 -> 858%7=4 "ax", 860%7=6 "puff")
	eq(Names.self_name(_genome({"size": 1.5})), "Chonkpuff", "self chonk fallback")
	eq(Names.self_name(_genome({"size": 1.4})), "Squishax", "self 1.4 not > 1.4 -> Squish")
