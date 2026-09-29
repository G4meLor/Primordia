## Living ecosystem: species populations that eat, breed, collapse and go
## extinct for real. Shared by cell stage, creature stage and space-stage
## planets. Overhunting genuinely breaks the food chain — permanently.
## Port of Spore src/evo/ecosystem.ts — CORE tick scope: flora logistic growth,
## herb drain + sterility floor, carrying caps, growth/decay, extinction,
## background speciation, notifyKill pricing and EcoMods. EcoMods is a plain
## Dictionary with the TS keys verbatim (growth_mult, predation_mult,
## speciation_mult, meal_dna_mult, herb_drain_mult, selection_sweep,
## rot_circle) — the eco never sees the world genome; stages set `mods`.
## Species are plain Dictionaries (EcoSpecies): id/name/genome/pop/discovered/
## extinct/kills_by_player/kin, genome in the shared genome.gd shape.
## Task 9 (marked inline, inert here): kin_memory valves (grudge/harass),
## bio_shift reequilibrate, corpse_tide ledger, save serialization.
## rng stays untyped: a global class_name annotation would not resolve in `-s`
## mode on a fresh clone (see names.gd).
class_name Ecosystem
extends RefCounted

# Same -s-mode constraint as rng.gd's SELF_SCRIPT idiom: resolve scripts by path.
const GenomeScript := preload("res://src/evo/genome.gd")
const NamesScript := preload("res://src/evo/names.gd")
const MutationScript := preload("res://src/evo/mutation.gd")

var species: Array[Dictionary] = []
var flora := 60.0  # plant mass
var flora_cap := 100.0
var total_eaten := 0
## World-trait modifiers — runtime only: stages re-set them each tick, never
## saved. Every read is mods.get(key, default), so {} is bit-identical to unset
## (no rng reordering, no extra rng consumption).
var mods: Dictionary = {}

var rng: Variant = null  # TS constructor(private rng: Rng)


func _init(rng_v) -> void:
	rng = rng_v


## TS `get living()` — the species still breathing.
func living() -> Array:
	return species.filter(func(s): return not s["extinct"])


## Register a species. opts rides the TS Partial<EcoSpecies> spread (applied
## LAST, so opts fields override the defaults: name/kin/tideBorn/...).
func add_species(genome: Dictionary, pop: float, opts: Dictionary = {}) -> Dictionary:
	var base_name: String = NamesScript.species_name(rng)
	var ep: String = NamesScript.epithet(genome, rng)
	var s: Dictionary = {
		# TS: `sp${this.species.length}_${Math.floor(this.rng.next() * 1e9).toString(36)}`
		"id": "sp%d_%s" % [species.size(), _base36(floori(rng.next() * 1e9))],
		"name": base_name if ep.is_empty() else "%s %s" % [base_name, ep],
		"genome": GenomeScript.clamp_genome(genome.duplicate()),
		"pop": pop,
		"discovered": opts.get("kin") == true,
		"extinct": false,
		"kills_by_player": 0,
		"kin": opts.get("kin") == true,
	}
	s.merge(opts, true)  # TS ...opts
	species.append(s)
	return s


## The player ate one member of this species. Returns DNA value gained.
func notify_kill(id: String, player_strength: float) -> int:
	var s: Variant = null
	for x in species:
		if x["id"] == id:
			s = x
			break
	if s == null or s["extinct"]:
		return 0
	s["pop"] = maxf(0.0, float(s["pop"]) - 1.0)
	s["kills_by_player"] = int(s["kills_by_player"]) + 1
	total_eaten += 1
	# DNA scales with how big/tough the meal is relative to the player.
	var g: Dictionary = s["genome"]
	var meal: float = float(g["size"]) * (1.0 + float(g["spikes"]) * 0.1 + float(g["jaw"]) * 0.1)
	# Husbandry beats genocide: a species on the brink pays LITTLE (don't
	# finish it off), healthy herds pay a premium — leave bloodlines alive.
	var sc: float = 0.6 if float(s["pop"]) < 6.0 else (1.2 if float(s["pop"]) > 25.0 else 1.0)
	var sc0: float = float(mods.get("meal_dna_mult", 1))
	var v: float = (9.0 + meal * 6.0 + maxf(0.0, meal - player_strength) * 6.0) * sc * sc0
	# JS Math.round — floori(x + 0.5) matches it on this always-positive value
	# (same convention as names.gd's tail pick).
	return floori(v + 0.5)


## Advance populations by dt seconds.
## `player_species_id` — the player's own species is exempt from dynamics.
## Returns { "extinctions": [...], "speciations": [...] } (Task 9 adds shifts).
func tick(dt: float, player_species_id: String = "") -> Dictionary:
	var out: Dictionary = {"extinctions": [], "speciations": []}
	var m := dt / 60.0  # minutes elapsed
	var gm := float(mods.get("growth_mult", 1))

	# Task 9: corpse_tide — the corpse ledger decays on its own here
	# (corpses = max(0, corpses - 3 * m)); the ledger and drop_corpse land with
	# the tide in Task 9.

	# Flora grows logistically.
	var f_cap := flora_cap
	flora += 0.8 * flora * (1.0 - flora / f_cap) * m

	# Herbivore pressure on flora. Famine lines are always starving — they
	# strip twice their share (M2 stress behavior).
	var herb_biomass := 0.0
	for s in living():
		if s["genome"]["diet"] != "carnivore":
			herb_biomass += float(s["pop"]) * float(s["genome"]["size"]) \
					* (2.0 if s.get("defect") == "famine" else 1.0)
	flora = maxf(0.0, flora - herb_biomass * 0.012 * float(mods.get("herb_drain_mult", 1)) * m * 10.0)

	# the sterility floor applies AFTER the drain — clamping before it let a
	# mature ocean eat straight through 12 and pellets stopped spawning
	# forever (herbivore income collapsed to 0 after 15-30 min)
	flora = maxf(12.0, minf(f_cap, flora))

	var total_biomass := 0.0
	for s in living():
		total_biomass += float(s["pop"]) * float(s["genome"]["size"])

	# Task 9: bio_shift — standing nutritional-role conversions apply to living
	# lines here (converted once, then exempt; kin lines never convert).

	for s in living():
		if float(s["pop"]) > float(s.get("peak", 0.0)):
			s["peak"] = s["pop"]  # peak precedes the kin exemption (gaia tier 2 reads kin peaks)
		if s["id"] == player_species_id or s["kin"]:
			continue  # player line is hand-driven
		var g: Dictionary = s["genome"]
		# Task 9: valves — kin_memory decay (grudge halves every ~20 game-min)
		# and the harassment window roll, for kinTag lines only.
		# M1 dormant: the sleeper allele wakes at its generation — normal slot,
		# clamped, then the pending stamp clears.
		var pa: Variant = s.get("pendingAllele")
		if pa != null and int(g["generation"]) >= int(pa["wakeGen"]):
			var ng: Dictionary = g.duplicate()
			ng[pa["gene"]] = pa["value"]
			s["genome"] = GenomeScript.clamp_genome(ng)
			s.erase("pendingAllele")
		# Carrying capacity from food supply.
		var cap: float
		if g["diet"] == "herbivore":
			cap = flora * 2.2 / maxf(0.4, float(g["size"]))
		elif g["diet"] == "omnivore":
			cap = (flora * 1.1 + total_biomass * 0.15 * float(mods.get("predation_mult", 1))) \
					/ maxf(0.4, float(g["size"]))
		else:
			cap = maxf(1.0, total_biomass * 0.18 * float(mods.get("predation_mult", 1))) \
					/ maxf(0.4, float(g["size"]))
		cap = minf(cap, 90.0)
		# selection_sweep: the ornamented pay a metabolic tithe while the toxin
		# sweep is live (catalog budget: 15-30% differential, cap 50%)
		if _truthy(mods.get("selection_sweep")) \
				and (g["pattern"] != "plain" or float(g["sat"]) > 0.85):
			cap *= 0.78
		# Task 9: corpse_tide — tideBorn scavengers cap on the corpse ledger
		# (min(cap, 0.3 + corpses * 1.5, pop_sum * 0.08)) and starve as it empties.
		var growth := 0.5 * gm * float(s["pop"]) * (1.0 - float(s["pop"]) / maxf(1.0, cap))
		# M2 glass_bones: the defective allele runs at half strength but the
		# line is fragile — 1.75x the background mortality
		var death_rate := 0.035 if s.get("defect") == "glass_bones" else 0.02
		s["pop"] = maxf(0.0, float(s["pop"]) + growth * m - float(s["pop"]) * death_rate * m)
		# M2 frenzy: crowd stress turns the line on itself — cascade capped at
		# ≤30% of the pack per trigger
		if s.get("defect") == "frenzy" and float(s["pop"]) > 24.0 and rng.chance(0.25 * m):
			s["pop"] = float(s["pop"]) * 0.72
		# M2 famine: in a starving world the line eats its own
		if s.get("defect") == "famine" and flora < 15.0:
			s["pop"] = float(s["pop"]) * (1.0 - 0.15 * m)
		if float(s["pop"]) < 0.4:
			s["extinct"] = true
			s["pop"] = 0.0
			# Task 9: tideBorn lines revive through drop_corpse and must NOT run
			# the extinction ceremony — the tideBorn skip joins with the ledger.
			out["extinctions"].append(s)
		# Background speciation: rare but actually observable (~1 per 15-20
		# stage-minutes in a healthy ecosystem), capped roster. (Task 9 adds the
		# tideBorn guard ahead of the size check — it draws no rng, so the
		# stream is unaffected until then.)
		if living().size() < 12 and float(s["pop"]) > 6.0 \
				and rng.chance(0.004 * float(mods.get("speciation_mult", 1)) * m):
			out["speciations"].append(add_species(MutationScript.mutate(g, rng, 0.5), 2.0))
	# rot_circle (catalog II.a): a death blooms the ruins — flora surges and
	# a new grazer rises, once per extinction tick batch (combo wired here,
	# the flag rides EcoMods from the live world genome)
	if out["extinctions"].size() > 0 and _truthy(mods.get("rot_circle")) and living().size() < 12:
		flora = minf(flora_cap, flora + 20.0)
		var rg: Dictionary = GenomeScript.default_genome()
		rg.merge({
			"diet": "herbivore", "size": 0.7, "flagella": 3, "hue": 100,
			"pattern": "spots", "generation": 1,
		}, true)
		add_species(GenomeScript.clamp_genome(rg), 2.0)
	if out["extinctions"].size() > 0:
		pass  # Task 9: bio_shift reequilibrate — role conversions + solvability top-up
	return out


## Chaos hook: force-mutate a living species into a new one.
func force_speciation() -> Variant:
	var candidates: Array = living().filter(func(s): return not s["kin"] and s["id"] != "player")
	if candidates.is_empty():
		return null
	var src: Dictionary = rng.pick(candidates)
	return add_species(MutationScript.mutate(src["genome"], rng, 0.8), 2.0)


# Task 9 surface (not yet ported — structure noted here so the seams show):
#   - kin_memory valves: GRUDGE_HALFLIFE_GEN/GRUDGE_GEN_SECONDS/HARASS_CAP/
#     HARASS_WINDOW_MIN constants, effective_grudge(), designate_kin_tag(),
#     grudge_of(), register_press(), and the grudge/harass/grudge_t/harass_t/
#     kin_tag ledger fields on EcoSpecies.
#   - bio_shift: shifts ledger + reequilibrate() (role conversion + the
#     "never fewer than 2 living lines" top-up) + out["shifts"].
#   - corpse_tide: corpses ledger, drop_corpse(), tide_species().
#   - serialization: to_json()/from_json().


# JS truthiness for the boolean EcoMods flags (selection_sweep/rot_circle):
# absent/null/false skip the branch without rng cost; a stray 1 or "" still
# counts like it would in TS.
static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is String:
		return not v.is_empty()
	if v is float or v is int:
		var f := float(v)
		return not is_nan(f) and f != 0.0
	return true


## JS `n.toString(36)` — lowercase digits (ids only ever see n >= 0 here:
## floori(next() * 1e9) stays in [0, 1e9)).
@warning_ignore("integer_division")
static func _base36(n: int) -> String:
	const D := "0123456789abcdefghijklmnopqrstuvwxyz"
	if n <= 0:
		return "0"
	var out := ""
	var v := n
	while v > 0:
		out = D[v % 36] + out
		v = v / 36
	return out
