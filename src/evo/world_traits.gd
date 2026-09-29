## The world-trait catalog: 13 trait definitions (11 drawable — 8 patch/seed
## traits plus the 9a temperament trio — and 2 turn-only replacements that
## never draw), 5 combo definitions, 3 world-turn definitions, the title word
## lists, and the PatchKey union. Port of Spore src/evo/worldTraits.ts —
## data verbatim: ids, weights, exclusion lists, effect tuples, reveal
## conditions, sigils and the EN name/body strings are the TS values, key for
## key. Effect and reveal kinds ride the TS camelCase names (stageTime /
## stageEnter / ecoSeed / turnOnly) so the shapes stay diffable against the
## frozen source.
## TraitDef / TraitEffect / RevealCondition are plain Dictionaries:
##   TraitDef = {id, weight, excludes, effects, reveal, sigil, name, body, turnOnly?}
##   effect   = {kind: "num", key, value} | {kind: "flag", key, value}
##            | {kind: "ecoSeed", archetype, weight}
##   reveal   = {kind: "stageTime", stage, seconds} | {kind: "stageEnter", stage}
##            | {kind: "extinct", count} | {kind: "chaos", above} | {kind: "kill", count}
## The const arrays are deeply read-only in Godot — consumers share the same
## def objects (TS module-identity semantics) and must never mutate them.
class_name WorldTraits
extends RefCounted

# ---- patch keys (nguồn duy nhất; hệ khác import từ đây) ----
const PATCH_KEYS := ["growth_mult", "predation_mult", "speciation_mult",
	"meal_dna_mult", "herb_drain_mult", "mutation_rate_add"]

const TRAIT_DEFS := [
	{"id": "hungry_bloom", "weight": 10, "excludes": ["calm_veil"],
		"effects": [{"kind": "num", "key": "herb_drain_mult", "value": 1.6},
			{"kind": "ecoSeed", "archetype": "herbivore", "weight": 1.5}],
		"reveal": {"kind": "stageTime", "stage": "cell", "seconds": 90}, "sigil": "🌱",
		"name": "Hungry Bloom", "body": "Herbivores here strip plant mass 60% faster."},
	{"id": "iron_gut", "weight": 10, "excludes": [],
		"effects": [{"kind": "num", "key": "meal_dna_mult", "value": 1.2},
			{"kind": "ecoSeed", "archetype": "carnivore", "weight": 1.4}],
		"reveal": {"kind": "kill", "count": 15}, "sigil": "🦴",
		"name": "Iron Gut", "body": "Every meal in this ocean pays 20% more DNA."},
	{"id": "toxin_sea", "weight": 8, "excludes": [],
		"effects": [{"kind": "flag", "key": "toxin_rain_cell", "value": true}],
		"reveal": {"kind": "chaos", "above": 0.45}, "sigil": "☣️",
		"name": "Toxin Sea", "body": "Chaos here condenses into drifting toxin clouds."},
	{"id": "swift_world", "weight": 9, "excludes": ["calm_veil"],
		"effects": [{"kind": "num", "key": "growth_mult", "value": 1.25},
			{"kind": "num", "key": "speciation_mult", "value": 1.5},
			{"kind": "ecoSeed", "archetype": "swarm", "weight": 1.3}],
		"reveal": {"kind": "stageEnter", "stage": "creature"}, "sigil": "⏩",
		"name": "Swift World", "body": "Life reproduces and branches half again as fast."},
	{"id": "old_blood", "weight": 7, "excludes": [],
		"effects": [{"kind": "num", "key": "meal_dna_mult", "value": 0.9},
			{"kind": "ecoSeed", "archetype": "titan", "weight": 2.0}],
		"reveal": {"kind": "stageTime", "stage": "cell", "seconds": 180}, "sigil": "🗿",
		"name": "Old Blood", "body": "Titans swim here — meals are poorer but legends are real."},
	{"id": "pirate_wind", "weight": 8, "excludes": ["calm_veil"],
		"effects": [{"kind": "flag", "key": "raider_bold", "value": true}],
		"reveal": {"kind": "stageEnter", "stage": "tribe"}, "sigil": "🏴",
		"name": "Pirate Wind", "body": "Rivals sail earlier and hit harder."},
	{"id": "calm_veil", "weight": 7, "excludes": ["hungry_bloom", "swift_world", "pirate_wind"],
		"effects": [{"kind": "num", "key": "growth_mult", "value": 1.05},
			{"kind": "num", "key": "speciation_mult", "value": 0.8},
			{"kind": "ecoSeed", "archetype": "predator", "weight": 0.6}],
		"reveal": {"kind": "stageEnter", "stage": "civ"}, "sigil": "🕯️",
		"name": "Calm Veil", "body": "A slow, quiet world — events come gently, if at all."},
	{"id": "mutation_moon", "weight": 8, "excludes": ["calm_veil"],
		"effects": [{"kind": "num", "key": "mutation_rate_add", "value": 0.15},
			{"kind": "flag", "key": "wild_mutations", "value": true}],
		"reveal": {"kind": "chaos", "above": 0.6}, "sigil": "🌗",
		"name": "Mutation Moon", "body": "Under this moon, mutation storms touch two species at once."},
	# ---- catalog wave 9a ----------------------------------------------------
	{"id": "world_temperament", "weight": 8, "excludes": [],
		"effects": [{"kind": "flag", "key": "world_temperament", "value": true}],
		"reveal": {"kind": "stageTime", "stage": "cell", "seconds": 300}, "sigil": "☯",
		"name": "World Temperament",
		"body": "This world has a temper — Cradle softens every blow, Lean Seasons starve in long cycles, the Wildcard streaks without mercy."},
	{"id": "temperament_bands", "weight": 8, "excludes": [],
		"effects": [{"kind": "flag", "key": "behavior_band", "value": true}],
		"reveal": {"kind": "kill", "count": 3}, "sigil": "◐",
		"name": "Temperament Bands",
		"body": "Every species here carries its own disposition — some shy, some relentless."},
	{"id": "kin_memory", "weight": 7, "excludes": [],
		"effects": [{"kind": "flag", "key": "kin_grudge", "value": true}],
		"reveal": {"kind": "kill", "count": 1}, "sigil": "⚱",
		"name": "Kin Memory",
		"body": "One lineage here keeps a ledger of your kills — one that fades over generations."},
	# ---- world-turn-only replacements (catalog V: arrive only via epoch turns)
	{"id": "false_wing", "weight": 0, "turnOnly": true, "excludes": [],
		"effects": [{"kind": "num", "key": "speciation_mult", "value": 1.25},
			{"kind": "num", "key": "growth_mult", "value": 1.1},
			{"kind": "flag", "key": "false_wing", "value": true}],
		"reveal": {"kind": "stageEnter", "stage": "creature"}, "sigil": "🪽",
		"name": "False Wing",
		"body": "The ancestor's fin catches air again — a short glide, never flight."},
	{"id": "trophic_release", "weight": 0, "turnOnly": true, "excludes": [],
		"effects": [{"kind": "num", "key": "growth_mult", "value": 1.15},
			{"kind": "num", "key": "predation_mult", "value": 0.85},
			{"kind": "flag", "key": "trophic_release", "value": true}],
		"reveal": {"kind": "extinct", "count": 1}, "sigil": "🌿",
		"name": "Trophic Release",
		"body": "The apex lane stands open — the middle of the web blooms into it."},
]

const COMBO_DEFS := [
	{"id": "rot_circle", "requires": ["hungry_bloom", "toxin_sea"],
		"trigger": {"kind": "extinct", "count": 1},
		"effects": [{"kind": "flag", "key": "rot_circle", "value": true}],
		"title": "Rot Circle",
		"body": "When a species dies here, the ruins bloom — flora surges and a new grazer rises.", "sigil": "♻️"},
	{"id": "war_graves", "requires": ["old_blood", "pirate_wind"],
		"trigger": {"kind": "stageTime", "stage": "tribe", "seconds": 60},
		"effects": [{"kind": "flag", "key": "war_graves", "value": true}],
		"title": "War Graves",
		"body": "Raids on this world leave DNA caches in the wreckage.", "sigil": "⚔️"},
	# ---- catalog wave 9a ----------------------------------------------------
	{"id": "corpse_tide", "requires": ["iron_gut", "toxin_sea"],
		"trigger": {"kind": "kill", "count": 15},
		"effects": [{"kind": "flag", "key": "corpse_tide", "value": true}],
		"title": "Corpse Tide",
		"body": "Your kills do not end here — the dead burst into small, fierce scavengers.", "sigil": "🦐"},
	{"id": "selection_sweep", "requires": ["mutation_moon", "toxin_sea"],
		"trigger": {"kind": "chaos", "above": 0.45},
		"effects": [{"kind": "flag", "key": "selection_sweep", "value": true}],
		"title": "Selection Sweep",
		"body": "The toxin tide tithes the ornamented — the plain survive, and the hue of the whole system shifts.", "sigil": "🌀"},
	{"id": "borrowed_flesh", "requires": ["swift_world", "old_blood"],
		"trigger": {"kind": "stageEnter", "stage": "tribe"},
		"effects": [{"kind": "flag", "key": "borrowed_flesh", "value": true}],
		"title": "Borrowed Flesh",
		"body": "One graft slot opens in the Gene Splicer — borrow a part of an extinct species.", "sigil": "🫱"},
]

const WORLD_TURN_DEFS := [
	{"id": "great_frost", "replaces": "hungry_bloom", "replacement": "calm_veil",
		"trigger": {"kind": "chaos", "above": 0.75}, "sigil": "❄️",
		"title": "The Great Frost",
		"body": "The bloom froze mid-bite. This world grows slower, quieter now."},
	# epoch_turn branches (a) + (b) of the catalog — same replace-trait
	# machinery, competing for the run-cap 0-2 alongside great_frost.
	# Branches (c)/(d) (sigil desecrate, sundance) stay deferred.
	{"id": "epoch_gate", "replaces": "swift_world", "replacement": "false_wing",
		"trigger": {"kind": "stageEnter", "stage": "creature"}, "sigil": "🪽",
		"title": "The Gate Crossed",
		"body": "Fins that once cut the water learn to catch air — the age of the gliders begins."},
	{"id": "epoch_apex", "replaces": "old_blood", "replacement": "trophic_release",
		"trigger": {"kind": "extinct", "count": 1}, "sigil": "👑",
		"title": "An Epoch Begins",
		"body": "The dominant line has fallen; the web re-shapes around who is left."},
]

const WORLD_ADJ := ["ancient", "restless", "patient", "voracious", "gentle",
	"burning", "sunken", "hidden", "howling", "cracked"]
const WORLD_NOUN := ["ocean", "cradle", "garden", "furnace", "veil",
	"deep", "march", "seedbed", "mirror", "engine"]
