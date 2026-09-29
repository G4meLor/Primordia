## Parts catalog: what the editor can buy, what each level costs, and the
## flavor text. Stats derived from genes live in stats.gd; this file is about
## the shopping/identity layer.
## Port of Spore src/evo/parts.ts. PartDef is a plain Dictionary with snake_case
## keys (baseCost -> base_cost, costMult -> cost_mult); everything else keeps the
## TS shape. Static funcs only, like Genome.
class_name Parts
extends RefCounted

# TS PartDef { id, gene, name, desc, max, baseCost, costMult, stage, effect }.
const PARTS: Array[Dictionary] = [
	# ---- cell parts ----------------------------------------------------------
	{ "id": "flagella", "gene": "flagella", "name": "Flagellum",
		"desc": "A whip-tail that propels you through the primordial soup.",
		"max": 6, "base_cost": 15, "cost_mult": 1.35, "stage": "cell", "effect": "+speed" },
	{ "id": "cilia", "gene": "cilia", "name": "Cilia",
		"desc": "Tiny hairs for quick turns and bursts of acceleration.",
		"max": 4, "base_cost": 20, "cost_mult": 1.4, "stage": "cell", "effect": "+accel" },
	{ "id": "spikes", "gene": "spikes", "name": "Spike",
		"desc": "Pointy. Hurts on contact. Fashionable in rough neighborhoods.",
		"max": 8, "base_cost": 25, "cost_mult": 1.3, "stage": "both", "effect": "+contact dmg" },
	{ "id": "jaw", "gene": "jaw", "name": "Jaw",
		"desc": "Bite things. Keep them. Chew slowly.",
		"max": 5, "base_cost": 30, "cost_mult": 1.45, "stage": "both", "effect": "+bite dmg" },
	{ "id": "toxin", "gene": "toxin", "name": "Toxin Sac",
		"desc": "Leaves a cloud of regret behind you.",
		"max": 5, "base_cost": 35, "cost_mult": 1.4, "stage": "both", "effect": "+poison aura" },
	{ "id": "proboscis", "gene": "proboscis", "name": "Proboscis",
		"desc": "Siphons DNA straight out of bigger cells. Rude but effective.",
		"max": 3, "base_cost": 45, "cost_mult": 1.6, "stage": "cell", "effect": "drain DNA" },
	{ "id": "electro", "gene": "electro", "name": "Electro-organ",
		"desc": "Discharges a stunning arc. Works on nearly everything.",
		"max": 3, "base_cost": 50, "cost_mult": 1.6, "stage": "cell", "effect": "stun burst" },
	{ "id": "jet", "gene": "jet", "name": "Jet Bladder",
		"desc": "Compressed-gas escape pod. Or approach pod. Your call.",
		"max": 3, "base_cost": 40, "cost_mult": 1.5, "stage": "cell", "effect": "+dash" },
	# ---- body plan --------------------------------------------------------------
	{ "id": "legs", "gene": "legs", "name": "Leg",
		"desc": "Walks you out of the ocean. Legs pair well with ambition.",
		"max": 6, "base_cost": 65, "cost_mult": 1.25, "stage": "both", "effect": "+land speed" },
	{ "id": "arms", "gene": "arms", "name": "Arm",
		"desc": "Grabby bits. Useful for tools, hugs, unsporting grabs.",
		"max": 4, "base_cost": 35, "cost_mult": 1.4, "stage": "creature", "effect": "+gather/charm" },
	{ "id": "eyes", "gene": "eyes", "name": "Eye",
		"desc": "More eyes, fewer ambushes. Also: unsettlingly cute.",
		"max": 6, "base_cost": 20, "cost_mult": 1.35, "stage": "creature", "effect": "+vision, +charm" },
	{ "id": "horns", "gene": "horns", "name": "Horn",
		"desc": "Impressive to rivals. Even more impressive implanted in them.",
		"max": 4, "base_cost": 40, "cost_mult": 1.45, "stage": "creature", "effect": "+charge dmg" },
	{ "id": "tail", "gene": "tail", "name": "Tail",
		"desc": "Counterweight, rudder, mood indicator.",
		"max": 1, "base_cost": 25, "cost_mult": 1.0, "stage": "creature", "effect": "+balance" },
	{ "id": "wings", "gene": "wings", "name": "Wings",
		"desc": "Not quite flight. Very much style.",
		"max": 2, "base_cost": 60, "cost_mult": 1.7, "stage": "creature", "effect": "hops, +charm" },
	{ "id": "brain", "gene": "brain", "name": "Brain",
		"desc": "The expensive bit. Bigger brains end the creature era.",
		"max": 5, "base_cost": 60, "cost_mult": 1.58, "stage": "creature", "effect": "ascension" },
]

# starter levels that ship unpaid with a fresh genome
const DEFAULTS := { "flagella": 2, "jaw": 1, "eyes": 1 }

const DIETS := [
	{ "id": "herbivore", "name": "Herbivore", "desc": "Plants only. Peaceful-ish.", "cost": 0 },
	{ "id": "omnivore", "name": "Omnivore", "desc": "Eats everything. Regrets nothing.", "cost": 40 },
	{ "id": "carnivore", "name": "Carnivore", "desc": "Meat. It is what is for dinner.", "cost": 60 },
]

const PATTERNS := [
	{ "id": "plain", "name": "Plain", "cost": 0 },
	{ "id": "spots", "name": "Spots", "cost": 15 },
	{ "id": "stripes", "name": "Stripes", "cost": 15 },
	{ "id": "glow", "name": "Bioluminescent", "cost": 45 },
]

const COATS := [
	{ "id": "skin", "name": "Bare Skin", "cost": 0, "effect": "—" },
	{ "id": "fur", "name": "Fur", "cost": 25, "effect": "+warmth, +charm" },
	{ "id": "scales", "name": "Scales", "cost": 35, "effect": "+defense" },
	{ "id": "plates", "name": "Bone Plates", "cost": 55, "effect": "++defense, -speed" },
]


## TS returns undefined on a miss; GDScript has no undefined, so a miss returns
## an empty Dictionary (check with is_empty()).
static func part_by_id(id: String) -> Dictionary:
	for p in PARTS:
		if p["id"] == id:
			return p
	return {}


## Strongest buyable part gene on a genome (the borrowed_flesh graft source).
## Requires level >= 2 to count as a real part; booleans/categoricals skip.
## TS returns null when nothing qualifies, so the return type stays Variant.
static func standout_part(g: Dictionary) -> Variant:
	var best: Dictionary = {}
	for p in PARTS:
		var v: Variant = g.get(p["gene"])
		if not (v is float or v is int) or v < 2:
			continue
		if best.is_empty() or v > best["level"]:
			best = { "def": p, "level": v }
	if best.is_empty():
		return null
	return best


## borrowed_flesh graft target — a graft only ever RAISES the gene.
static func graft_value(cur: float, level: float, max: float) -> float:
	return maxf(cur, minf(level, max))


## Math.round rounds .5 toward +infinity; Godot roundi rounds half away from
## zero — identical here because base_cost > 0 and cost_mult > 0 keep every
## input positive.
static func part_cost(def: Dictionary, current_level: int) -> int:
	return roundi(def["base_cost"] * pow(def["cost_mult"], current_level))


## Refund when removing a part level (partial, encourages commitment).
## Starter-genome levels (DEFAULTS) were never PAID — selling them used to mint
## ~63 free DNA from a fresh spawn.
static func part_refund(def: Dictionary, level_after_removal: int) -> int:
	if level_after_removal < 0:
		return 0
	var dflt: int = DEFAULTS.get(def["gene"], 0)
	if level_after_removal < dflt:
		return 0  # below starter baseline: nothing was ever paid
	return roundi(part_cost(def, level_after_removal) * 0.5)
