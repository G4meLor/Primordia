# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path — a bare global name (Genome,
# Fixtures) would not resolve without the editor's class cache.
const Genome := preload("res://src/evo/genome.gd")
const Fixtures := preload("res://tests/fixtures.gd")

# TS defaultGenome() literal (Spore src/evo/genome.ts) — 22 fields, value for value.
# Both sides of the eq below are GDScript literals, so exact equality is safe
# (same decimal parser); node-vs-Godot parse noise cannot split them.
const TS_DEFAULT := {
	"size": 1, "diet": "omnivore", "hue": 120, "sat": 0.55, "pattern": "plain",
	"flagella": 2, "cilia": 0, "spikes": 0, "jaw": 1, "toxin": 0, "proboscis": 0,
	"electro": 0, "jet": 0, "legs": 0, "arms": 0, "eyes": 1, "horns": 0,
	"tail": false, "wings": 0, "brain": 0, "coat": "skin", "generation": 1
}

# TS GENE_BOUNDS literal — 15 entries (tail, hue, sat, enums, generation excluded).
const TS_BOUNDS := {
	"size": {"min": 0.6, "max": 2.2},
	"flagella": {"min": 0, "max": 6},
	"cilia": {"min": 0, "max": 4},
	"spikes": {"min": 0, "max": 8},
	"jaw": {"min": 0, "max": 5},
	"toxin": {"min": 0, "max": 5},
	"proboscis": {"min": 0, "max": 3},
	"electro": {"min": 0, "max": 3},
	"jet": {"min": 0, "max": 3},
	"legs": {"min": 0, "max": 8},
	"arms": {"min": 0, "max": 4},
	"eyes": {"min": 1, "max": 6},
	"horns": {"min": 0, "max": 4},
	"wings": {"min": 0, "max": 2},
	"brain": {"min": 0, "max": 5}
}


func test_default_genome_matches_ts() -> void:
	var g: Dictionary = Genome.default_genome()
	eq(g, TS_DEFAULT, "default_genome() equals TS defaultGenome() value for value")
	eq(g.size(), 22, "default genome has exactly 22 keys")
	# TS arrow returns a fresh object literal per call; a shared template dict
	# would leak mutations between callers.
	var a: Dictionary = Genome.default_genome()
	a["jaw"] = 5
	eq(Genome.default_genome()["jaw"], 1, "default_genome() returns a fresh dict per call")


func test_gene_bounds_match_ts() -> void:
	var b: Dictionary = Genome.gene_bounds()
	eq(b, TS_BOUNDS, "gene_bounds() equals TS GENE_BOUNDS")
	eq(b.size(), 15, "GENE_BOUNDS has exactly 15 entries")


func test_clamp_genome_garbage_snaps_like_ts() -> void:
	var clamped: Dictionary = Genome.clamp_genome({
		"size": "abc", "eyes": NAN, "flagella": NAN, "jaw": "x", "cilia": null,
		"hue": NAN, "sat": 2, "diet": "xyz", "pattern": "bogus", "coat": "nope",
		"tail": "yes", "generation": 99
	})
	# non-numeric garbage snaps to the TS rule: size -> 1, eyes -> 1, rest -> 0
	eq(clamped["size"], 1, 'garbage size "abc" -> 1')
	eq(clamped["eyes"], 1, "NaN eyes -> 1")
	eq(clamped["flagella"], 0, "NaN flagella -> 0")
	eq(clamped["jaw"], 0, 'garbage jaw "x" -> 0')
	eq(clamped["cilia"], 0, "null cilia -> 0")
	# hue/sat: non-finite snaps to 120 / 0.55; numeric sat clamps into [0.05, 1]
	eq(clamped["hue"], 120, "NaN hue -> 120")
	eq(clamped["sat"], 1, "sat 2 clamps to 1")
	# bad enums -> defaults; tail/generation are not clamp fields and pass through
	eq(clamped["diet"], "omnivore", 'bad diet "xyz" -> omnivore')
	eq(clamped["pattern"], "plain", 'bad pattern "bogus" -> plain')
	eq(clamped["coat"], "skin", 'bad coat "nope" -> skin')
	eq(clamped["tail"], "yes", "clamp leaves tail untouched")
	eq(clamped["generation"], 99, "clamp leaves generation untouched")


func test_clamp_genome_fills_missing_keys() -> void:
	var clamped: Dictionary = Genome.clamp_genome({})
	# TS spread + bounds loop creates every bound key; hue/sat/enum checks add
	# theirs. tail/generation are never written by clampGenome.
	eq(clamped.size(), 20, "clamping {} yields 20 keys (15 bounds + hue + sat + 3 enums)")
	eq(clamped["size"], 1, "missing size -> 1")
	eq(clamped["eyes"], 1, "missing eyes -> 1")
	eq(clamped["flagella"], 0, "missing flagella -> 0")
	eq(clamped["hue"], 120, "missing hue -> 120")
	approx(clamped["sat"], 0.55, "missing sat -> 0.55")
	eq(clamped["diet"], "omnivore", "missing diet -> omnivore")
	eq(clamped["pattern"], "plain", "missing pattern -> plain")
	eq(clamped["coat"], "skin", "missing coat -> skin")
	ok(not clamped.has("tail"), "clamp does not create tail")
	ok(not clamped.has("generation"), "clamp does not create generation")


func test_clamp_genome_bounds_and_hue_wrap() -> void:
	var clamped: Dictionary = Genome.clamp_genome({
		"size": 5, "flagella": 9, "eyes": 0, "brain": -3, "hue": -30, "sat": -1
	})
	eq(clamped["size"], 2.2, "size 5 clamps to max 2.2")
	eq(clamped["flagella"], 6, "flagella 9 clamps to max 6")
	eq(clamped["eyes"], 1, "eyes 0 clamps to min 1")
	eq(clamped["brain"], 0, "brain -3 clamps to min 0")
	# GDScript % keeps the dividend's sign like JS %, so the TS double-mod
	# formula ports verbatim: (-30 % 360 + 360) % 360 = 330.
	eq(clamped["hue"], 330, "hue -30 wraps to 330")
	eq(clamped["sat"], 0.05, "sat -1 clamps to 0.05")
	eq(Genome.clamp_genome({"hue": 730})["hue"], 10, "hue 730 wraps to 10")
	eq(Genome.clamp_genome({"hue": 720})["hue"], 0, "hue 720 wraps to 0")
	eq(Genome.clamp_genome({"sat": 0.5})["sat"], 0.5, "sat 0.5 in range passes through")
	# the default genome is already canonical: clamp is identity on it
	eq(Genome.clamp_genome(Genome.default_genome()), TS_DEFAULT, "clamp(default) == default")


func test_clamp_genome_does_not_mutate_input() -> void:
	var g := {"size": 99, "hue": -30, "diet": "xyz", "flagella": 9}
	var snapshot := g.duplicate()
	Genome.clamp_genome(g)
	eq(g, snapshot, "clamp_genome does not mutate its input (TS {...g} spread)")


func test_genome_hash_matches_fixture_keys() -> void:
	var data := Fixtures.load_json("genome_stats")
	ok(not data.is_empty(), "fixture genome_stats.json loads")
	var genomes: Dictionary = data.get("genomes", {})
	eq(genomes.size(), 8, "fixture pins 8 genomes")
	# The fixture keys ARE the pin: keyNote says key = genomeHash(genome), so
	# each stored genome must rehash to its own key. Hashes are strings -> exact eq.
	for key in genomes.keys():
		var entry: Dictionary = genomes[key]
		var g: Dictionary = entry["genome"]
		eq(Genome.genome_hash(g), key, "genome_hash pin: %s" % entry.get("name", "?"))


func test_genome_hash_field_shape() -> void:
	var g: Dictionary = Genome.default_genome()
	var h := Genome.genome_hash(g)
	eq(h, "10-omnivore-8-6-plain-2-0-0-1-0-0-0-0-0-0-1-0-0-0-0-skin",
			"default hash equals the fixture 'default' key")
	var g2: Dictionary = Genome.clone_genome(g)
	g2["generation"] = 99
	g2["bogus"] = "x"
	eq(Genome.genome_hash(g2), h, "hash covers exactly the 21 TS fields (no generation, no extras)")


func test_clone_genome_deep_enough() -> void:
	var g: Dictionary = Genome.default_genome()
	var c: Dictionary = Genome.clone_genome(g)
	eq(c, g, "clone equals original")
	c["jaw"] = 5
	c["coat"] = "fur"
	eq(g["jaw"], 1, "mutating clone leaves original untouched (jaw)")
	eq(g["coat"], "skin", "mutating clone leaves original untouched (coat)")
