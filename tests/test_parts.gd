# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path — a bare global name (Parts,
# Genome) would not resolve without the editor's class cache.
const Parts := preload("res://src/evo/parts.gd")
const Genome := preload("res://src/evo/genome.gd")

# TS PartDef { id, gene, name, desc, max, baseCost, costMult, stage, effect } —
# nine fields (snake_case for baseCost/costMult), pinned below.
const PART_FIELDS := ["id", "gene", "name", "desc", "max", "base_cost", "cost_mult", "stage", "effect"]


func test_parts_catalog_shape() -> void:
	var parts: Array = Parts.PARTS
	eq(parts.size(), 15, "PARTS has exactly 15 entries")
	var ids := []
	for p in parts:
		eq(p.size(), 9, "part '%s' has exactly 9 fields" % p.get("id", "?"))
		for f in PART_FIELDS:
			ok(p.has(f), "part '%s' has field '%s'" % [p.get("id", "?"), f])
		ok(["cell", "creature", "both"].has(p["stage"]), "stage is a TS literal union value")
		eq(p["gene"], p["id"], "gene key matches id")
		ids.append(p["id"])
	# order pinned to the TS catalog literal
	eq(ids, ["flagella", "cilia", "spikes", "jaw", "toxin", "proboscis", "electro", "jet",
			"legs", "arms", "eyes", "horns", "tail", "wings", "brain"], "PARTS ids in TS order")


func test_parts_defs_match_ts() -> void:
	# Full TS PartDef literals (Spore src/evo/parts.ts), value for value. Both
	# sides are GDScript literals, so exact equality is safe (same parser).
	eq(Parts.part_by_id("flagella"), {
		"id": "flagella", "gene": "flagella", "name": "Flagellum",
		"desc": "A whip-tail that propels you through the primordial soup.",
		"max": 6, "base_cost": 15, "cost_mult": 1.35, "stage": "cell", "effect": "+speed",
	}, "flagella def matches TS")
	eq(Parts.part_by_id("legs"), {
		"id": "legs", "gene": "legs", "name": "Leg",
		"desc": "Walks you out of the ocean. Legs pair well with ambition.",
		"max": 6, "base_cost": 65, "cost_mult": 1.25, "stage": "both", "effect": "+land speed",
	}, "legs def matches TS")
	eq(Parts.part_by_id("brain"), {
		"id": "brain", "gene": "brain", "name": "Brain",
		"desc": "The expensive bit. Bigger brains end the creature era.",
		"max": 5, "base_cost": 60, "cost_mult": 1.58, "stage": "creature", "effect": "ascension",
	}, "brain def matches TS")
	eq(Parts.part_by_id("no_such_part"), {}, "part_by_id miss returns empty dict (TS undefined)")


func test_parts_cost_fields_match_ts() -> void:
	# (id, max, baseCost, costMult) straight from the TS catalog literal —
	# catches typos the three full-def spot checks miss.
	var ts := [
		["flagella", 6, 15, 1.35], ["cilia", 4, 20, 1.4], ["spikes", 8, 25, 1.3],
		["jaw", 5, 30, 1.45], ["toxin", 5, 35, 1.4], ["proboscis", 3, 45, 1.6],
		["electro", 3, 50, 1.6], ["jet", 3, 40, 1.5], ["legs", 6, 65, 1.25],
		["arms", 4, 35, 1.4], ["eyes", 6, 20, 1.35], ["horns", 4, 40, 1.45],
		["tail", 1, 25, 1], ["wings", 2, 60, 1.7], ["brain", 5, 60, 1.58],
	]
	for row in ts:
		var d: Dictionary = Parts.part_by_id(row[0])
		ok(not d.is_empty(), "part '%s' exists" % row[0])
		eq(d["max"], row[1], "%s max" % row[0])
		eq(d["base_cost"], row[2], "%s base_cost" % row[0])
		eq(d["cost_mult"], row[3], "%s cost_mult" % row[0])


func test_part_cost_table() -> void:
	var flagella: Dictionary = Parts.part_by_id("flagella")
	var legs: Dictionary = Parts.part_by_id("legs")
	var tail: Dictionary = Parts.part_by_id("tail")
	eq(Parts.part_cost(flagella, 0), 15, "partCost(flagella, 0) = 15")
	eq(Parts.part_cost(flagella, 1), 20, "partCost(flagella, 1) = round(15 * 1.35) = 20")
	eq(Parts.part_cost(flagella, 2), 27, "partCost(flagella, 2) = round(15 * 1.35^2 = 27.3375) = 27")
	eq(Parts.part_cost(legs, 0), 65, "partCost(legs, 0) = 65")
	eq(Parts.part_cost(legs, 2), 102, "partCost(legs, 2) = round(65 * 1.25^2 = 101.5625) = 102")
	eq(Parts.part_cost(tail, 1), 25, "costMult 1: level never raises the price")


func test_part_refund_starter_baseline() -> void:
	# DEFAULTS (flagella 2, jaw 1, eyes 1) ship unpaid with a fresh genome —
	# selling below the baseline refunds 0 or it would mint free DNA.
	eq(Parts.DEFAULTS, {"flagella": 2, "jaw": 1, "eyes": 1}, "DEFAULTS match TS")
	var flagella: Dictionary = Parts.part_by_id("flagella")
	var jaw: Dictionary = Parts.part_by_id("jaw")
	var eyes: Dictionary = Parts.part_by_id("eyes")
	var legs: Dictionary = Parts.part_by_id("legs")
	var tail: Dictionary = Parts.part_by_id("tail")
	eq(Parts.part_refund(flagella, 1), 0, "flagella 2->1: below starter baseline 2, nothing was paid")
	eq(Parts.part_refund(jaw, 0), 0, "jaw 1->0: below starter baseline 1")
	eq(Parts.part_refund(eyes, 0), 0, "eyes 1->0: below starter baseline 1")
	eq(Parts.part_refund(flagella, -1), 0, "negative levelAfterRemoval -> 0")
	eq(Parts.part_refund(flagella, 2), 14, "flagella ->2: round(partCost(2) * 0.5) = round(13.66875) = 14")
	eq(Parts.part_refund(legs, 2), 51, "legs 3->2: round(101.5625 * 0.5) = 51")
	eq(Parts.part_refund(eyes, 1), 14, "eyes 2->1: at baseline, round(27 * 0.5) = 14 (positive .5 rounds up)")
	eq(Parts.part_refund(legs, 0), 33, "legs 1->0: no default entry -> baseline 0, round(32.5) = 33")
	eq(Parts.part_refund(tail, 0), 13, "tail has no default: round(25 * 0.5) = 13")


func test_standout_part() -> void:
	# strongest buyable number-level gene >= 2; bool/categorical genes skip
	var g: Dictionary = Genome.default_genome()
	g["jaw"] = 5
	g["spikes"] = 3
	var best: Variant = Parts.standout_part(g)
	ok(best is Dictionary, "jaw 5 + spikes 3 has a standout")
	eq(best["def"]["id"], "jaw", "highest level wins")
	eq(best["level"], 5, "standout level")

	var weak: Dictionary = Genome.default_genome()
	weak["flagella"] = 1  # default genome has flagella 2 — drop below the >= 2 bar
	eq(Parts.standout_part(weak), null, "all numeric levels <= 1 -> null (TS null)")

	var tailed: Dictionary = Genome.default_genome()
	tailed["flagella"] = 1
	tailed["tail"] = true
	eq(Parts.standout_part(tailed), null, "bool genes (tail) never stand out")

	var tie: Dictionary = Genome.default_genome()  # flagella 2
	tie["cilia"] = 2  # cilia comes after flagella in PARTS order
	var tied: Variant = Parts.standout_part(tie)
	eq(tied["def"]["id"], "flagella", "tie goes to the earlier PARTS entry (strict >)")


func test_graft_value() -> void:
	# borrowed_flesh graft target — a graft only ever RAISES the gene, to at most max
	eq(Parts.graft_value(3, 5, 8), 5.0, "graft_value(3, 5, 8) = 5")
	eq(Parts.graft_value(6, 5, 8), 6.0, "graft never lowers: graft_value(6, 5, 8) = 6")
	eq(Parts.graft_value(0, 9, 8), 8.0, "level clamps to max: graft_value(0, 9, 8) = 8")


func test_shop_catalogs() -> void:
	eq(Parts.DIETS.size(), 3, "DIETS has 3 entries")
	eq(Parts.PATTERNS.size(), 4, "PATTERNS has 4 entries")
	eq(Parts.COATS.size(), 4, "COATS has 4 entries")
	eq(Parts.DIETS[1], {"id": "omnivore", "name": "Omnivore",
			"desc": "Eats everything. Regrets nothing.", "cost": 40}, "omnivore entry matches TS")
	eq(Parts.DIETS[2]["cost"], 60, "carnivore cost 60")
	# R6: the cosmetic costs are zeroed IN THE DATA (the LOOK tab is free) —
	# the deliberate divergence from the frozen TS catalog (15/15/45, 25/35/55)
	eq(Parts.PATTERNS[3], {"id": "glow", "name": "Bioluminescent", "cost": 0},
			"glow entry — R6 zeroed cosmetic cost")
	eq(Parts.COATS[3], {"id": "plates", "name": "Bone Plates", "cost": 0,
			"effect": "++defense, -speed"}, "plates entry — R6 zeroed cosmetic cost")
	eq(Parts.COATS[0]["effect"], "—", "skin effect is the TS em-dash")
