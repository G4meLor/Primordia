## Living ecosystem: species populations that eat, breed, collapse and go
## extinct for real. Shared by cell stage, creature stage and space-stage
## planets. Overhunting genuinely breaks the food chain — permanently.
## Port of Spore src/evo/ecosystem.ts (full file): core tick (flora logistic
## growth, herb drain + sterility floor, carrying caps, growth/decay,
## extinction, background speciation), notifyKill pricing, EcoMods, the
## kin_memory valves, bio_shift reequilibrate, corpse_tide and save
## serialization. EcoMods is a plain
## Dictionary with the TS keys verbatim (growth_mult, predation_mult,
## speciation_mult, meal_dna_mult, herb_drain_mult, selection_sweep,
## rot_circle) — the eco never sees the world genome; stages set `mods`.
## Species are plain Dictionaries (EcoSpecies): id/name/genome/pop/discovered/
## extinct/kills_by_player/kin, genome in the shared genome.gd shape. Valve and
## tide fields ride the same dicts (Task 8 seam naming: grudge/grudge_t/harass/
## harass_t/kin_tag; TS-verbatim optional fields: tideBorn/shifted/pendingAllele).
## rng stays untyped: a global class_name annotation would not resolve in `-s`
## mode on a fresh clone (see names.gd).
class_name Ecosystem
extends RefCounted

# Same -s-mode constraint as rng.gd's SELF_SCRIPT idiom: resolve scripts by path.
const SELF_SCRIPT := "res://src/evo/ecosystem.gd"
const GenomeScript := preload("res://src/evo/genome.gd")
const NamesScript := preload("res://src/evo/names.gd")
const MutationScript := preload("res://src/evo/mutation.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")

# ---- kin_memory valves (catalog I.b: the ledger must not be a life sentence)
## Grudge half-life: ~40 short generations (mid-band of the catalog's 30-50).
## A short generation ≈ 30 s of stage time for micro-organisms → 20 game-min.
const GRUDGE_HALFLIFE_GEN := 40
const GRUDGE_GEN_SECONDS := 30
## Harassment cap: at most this many grudge-driven presses per window…
const HARASS_CAP := 4
## …of this many eco-tick-minutes; past the cap the network rests.
const HARASS_WINDOW_MIN := 100


## Effective grudge for behavior reads — 0 once the harassment cap is hit,
## so the network rests and flee is restored until the window rolls.
static func effective_grudge(sp: Dictionary) -> float:
	if float(sp.get("harass", 0.0)) >= float(HARASS_CAP):
		return 0.0
	return float(sp.get("grudge", 0.0))

var species: Array[Dictionary] = []
var flora := 60.0  # plant mass
var flora_cap := 100.0
var total_eaten := 0
## World-trait modifiers — runtime only: stages re-set them each tick, never
## saved. Every read is mods.get(key, default), so {} is bit-identical to unset
## (no rng reordering, no extra rng consumption).
var mods: Dictionary = {}

## corpse_tide kill ledger — every player kill under the combo leaves a
## corpse; the ledger feeds the scavenger line and decays on its own.
var corpses := 0.0
## bio_shift (catalog V): standing nutritional-role conversions — one pair
## per extinction event (plus a second silent rng pair); roles stay
## converted for the rest of the run.
var shifts: Array = []

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
## Returns { "extinctions": [...], "speciations": [...], "shifts": [...]? }
## (`shifts` present only when a bio_shift conversion batch landed).
func tick(dt: float, player_species_id: String = "") -> Dictionary:
	var out: Dictionary = {"extinctions": [], "speciations": []}
	var m := dt / 60.0  # minutes elapsed
	var gm := float(mods.get("growth_mult", 1))

	# corpse ledger decays on its own — the tide auto-ends when kills stop
	corpses = maxf(0.0, corpses - 3.0 * m)

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

	# bio_shift standing conversions: a converted role stays converted for the
	# rest of the run — living lines convert once (then exempt); newborn lines
	# of the old role convert here the tick after they appear. Kin lines are
	# load-bearing and never convert.
	if shifts.size() > 0:
		for s in living():
			if s["kin"] == true or s.get("shifted") == true:
				continue
			var sh: Variant = null
			for x in shifts:
				if x["from"] == s["genome"]["diet"]:
					sh = x
					break
			if sh != null:
				var ng: Dictionary = s["genome"].duplicate()
				ng["diet"] = sh["to"]
				s["genome"] = GenomeScript.clamp_genome(ng)
				s["shifted"] = true

	for s in living():
		if float(s["pop"]) > float(s.get("peak", 0.0)):
			s["peak"] = s["pop"]  # peak precedes the kin exemption (gaia tier 2 reads kin peaks)
		if s["id"] == player_species_id or s["kin"]:
			continue  # player line is hand-driven
		var g: Dictionary = s["genome"]
		# kin_memory decay valve (catalog I.b): the ledger fades — halve the
		# grudge every ~40 short generations (~30 s each for micro-organisms →
		# a 20 game-min half-life). Int-clamped; at 0 the network is neutral.
		if s.get("kin_tag") == true and float(s.get("grudge", 0.0)) > 0.0:
			s["grudge_t"] = float(s.get("grudge_t", 0.0)) + dt
			if float(s["grudge_t"]) >= float(GRUDGE_HALFLIFE_GEN * GRUDGE_GEN_SECONDS):
				s["grudge"] = floori(float(s.get("grudge", 0.0)) / 2.0)
				s["grudge_t"] = 0.0
		# kin_memory harassment window: presses counted by the stages roll off
		# here — past HARASS_CAP within the window the network rests (effective
		# grudge 0, flee restored) until the window resets.
		if s.get("kin_tag") == true \
				and (float(s.get("harass", 0.0)) > 0.0 or float(s.get("harass_t", 0.0)) > 0.0):
			s["harass_t"] = float(s.get("harass_t", 0.0)) + m
			if float(s["harass_t"]) >= float(HARASS_WINDOW_MIN):
				s["harass_t"] = 0.0
				s["harass"] = 0.0
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
		# corpse_tide: scavengers live on the ledger — their ceiling is the
		# corpse supply and 8% of total population (combo budget). Obligate
		# corpse-eaters: starvation ramps up as the ledger empties, so when the
		# kills stop the tide auto-ends ≤ ~5 game-min (catalog budget).
		if s.get("tideBorn") == true:
			cap = minf(minf(cap, 0.3 + corpses * 1.5), _pop_sum() * 0.08)
			s["pop"] = float(s["pop"]) - float(s["pop"]) * 1.5 * maxf(0.0, 1.0 - corpses / 3.0) * m
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
			# I-bug2: the tide line revives through drop_corpse — it must not run
			# the extinction ceremony (banner/counters/bio_shift conversion) or
			# every feast/famine cycle rings the world bell and inflates the
			# extinction counters epoch_apex feeds on
			if s.get("tideBorn") != true:
				out["extinctions"].append(s)
		# Background speciation: rare but actually observable (~1 per 15-20
		# stage-minutes in a healthy ecosystem), capped roster. Tide-born
		# scavengers are a dead-end line — they never branch. (The tideBorn
		# guard draws no rng, so the stream is unaffected without a tide line.)
		if s.get("tideBorn") != true and living().size() < 12 and float(s["pop"]) > 6.0 \
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
		_reequilibrate(out["extinctions"], out)
	return out


## bio_shift (catalog V): a death re-equilibrates the web — the extinct
## species' nutritional role converts (seeded target) plus a second silent
## rng-chosen pair, both standing for the run. Solvability re-check after
## each shift: never leave fewer than 2 living lines (top-up discipline).
func _reequilibrate(extinct: Array, out: Dictionary) -> void:
	var diets := ["herbivore", "omnivore", "carnivore"]
	var added: Array = []
	_push_shift(extinct[0]["genome"]["diet"], diets, added)  # the primary pair: the fallen role converts
	_push_shift(rng.pick(diets), diets, added)  # the second, silent pair
	# solvability re-check runs BEFORE the dedupe short-circuit — a late-run
	# extinction whose role-pairs already stand must still top the web up,
	# or the eco could sit at 1-0 living lines for the rest of the run
	while living().size() < 2:
		add_species(GenomeScript.clone_genome(GenomeScript.default_genome()), 6.0)
	if added.is_empty():
		return
	out["shifts"] = added


## One role-pair conversion attempt: seeded target off the eco's rng stream
## (TS order — the primary pick, then the silent pair's source pick, then the
## silent pick itself), deduped against the standing ledger.
func _push_shift(from_diet: String, diets: Array, added: Array) -> void:
	var others: Array = diets.filter(func(d): return d != from_diet)
	if others.is_empty():
		return
	var to: Variant = rng.pick(others)
	for s in shifts:
		if s["from"] == from_diet and s["to"] == to:
			return
	shifts.append({"from": from_diet, "to": to})
	added.append({"from": from_diet, "to": to})


## Chaos hook: force-mutate a living species into a new one.
func force_speciation() -> Variant:
	var candidates: Array = living().filter(func(s): return not s["kin"] and s["id"] != "player")
	if candidates.is_empty():
		return null
	var src: Dictionary = rng.pick(candidates)
	return add_species(MutationScript.mutate(src["genome"], rng, 0.8), 2.0)


## corpse_tide hook: the stage reports a player kill while the combo is
## live — the kill bursts into 2-3 small fierce scavengers (hard-capped at
## 8% of total population) and one corpse joins the standing ledger (the
## pantry that keeps the line alive, capped at 8 so it flushes fast). A
## collapsed line is revived, not re-founded — same scavengers, the tide
## keeps coming back while the kills do ("here death does not end").
func drop_corpse(n: int = 1) -> void:
	corpses = minf(8.0, corpses + 1.0)
	var pop_sum := _pop_sum()
	var sp: Variant = tide_species()
	if sp == null:
		# most recently founded tideBorn line first — revive, don't re-found
		for i in range(species.size() - 1, -1, -1):
			var cand: Dictionary = species[i]
			if cand.get("tideBorn") == true and cand["extinct"] == true:
				sp = cand
				break
		if sp != null:
			sp["extinct"] = false
			sp["pop"] = 0.0
		else:
			var g: Dictionary = GenomeScript.default_genome()
			g.merge({
				"size": 0.55, "diet": "carnivore", "flagella": 4, "jaw": 3,
				"spikes": 2, "hue": 20, "pattern": "stripes", "generation": 1,
			}, true)
			sp = add_species(GenomeScript.clamp_genome(g), 0.0,
					{"tideBorn": true, "name": "Cadaverexus"})
	sp["pop"] = minf(maxf(0.0, pop_sum * 0.08), float(sp["pop"]) + float(n))


## The living tide-born scavenger line, if any.
func tide_species() -> Variant:
	for s in living():
		if s.get("tideBorn") == true:
			return s
	return null


## Sum of living populations (TS `this.living.reduce((a, x) => a + x.pop, 0)`).
func _pop_sum() -> float:
	var sum := 0.0
	for x in living():
		sum += float(x["pop"])
	return sum


# ---- kin_memory shared plumbing (minor 14: one home, two stage consumers) ----

## Designate the ONE social species carrying the world's single grudge
## ledger (first herding non-kin lineage). Idempotent — the tag persists
## on the shared eco across stages.
func designate_kin_tag(world: Dictionary) -> void:
	if not _world_has(world, "kin_grudge"):
		return
	for s in species:
		if s.get("kin_tag") == true:
			return
	var host: Variant = null
	for s in living():
		if s["kin"] != true and s["genome"]["diet"] != "carnivore":
			host = s
			break
	if host == null:
		for s in living():
			if s["kin"] != true:
				host = s
				break
	if host != null:
		host["kin_tag"] = true


## Effective grudge for behavior reads (0 = the harassment valve is shut).
func grudge_of(world: Dictionary, species_id: String) -> float:
	if not _world_has(world, "kin_grudge"):
		return 0.0
	for x in species:
		if x["id"] == species_id:
			return effective_grudge(x) if x.get("kin_tag") == true else 0.0
	return 0.0


## A grudge-driven press engagement — counted toward the harassment valve.
@warning_ignore("unused_parameter")
func register_press(world: Dictionary, species_id: String) -> void:
	for x in species:
		if x["id"] == species_id:
			if x.get("kin_tag") == true:
				x["harass"] = float(x.get("harass", 0.0)) + 1.0
			return


# ---- save serialization -------------------------------------------------------

## Restore from save. Corrupt fields coerce instead of poisoning the run:
## junk species rows drop, genomes snap to defaults, and the ledger/valve
## counters coerce like TS numOrUndef (non-number → absent, which every
## reader treats as 0 — here the key is erased; JSON cannot hold undefined).
## TS keys grudgeT/harassT — native keeps the Task 8 seam naming grudge_t/
## harass_t on the wire (native saves never meet the TS ones).
static func from_json(data: Dictionary, rng_v: Variant) -> Variant:
	var eco: Variant = load(SELF_SCRIPT).new(rng_v)
	var raw: Variant = data.get("species")
	if raw is Array:
		for sp in raw:
			if not (sp is Dictionary) or not (sp.get("id") is String):
				continue
			var pop_v: Variant = sp.get("pop")
			if not ((pop_v is float or pop_v is int) and is_finite(pop_v)):
				continue
			if not (sp.get("genome") is Dictionary):
				continue
			var s: Dictionary = sp.duplicate()
			# partial/corrupt genomes (missing genes → NaN stats) snap to defaults
			s["genome"] = GenomeScript.clamp_genome(sp["genome"])
			s["pop"] = maxf(0.0, float(pop_v))
			# TS rides a missing core field as undefined (falsy on every read);
			# the native dicts are strict-indexed, so absent core fields snap to
			# the same falsy defaults instead of poisoning living()/tick reads
			if not s.has("extinct"):
				s["extinct"] = false
			if not s.has("kin"):
				s["kin"] = false
			if not s.has("discovered"):
				s["discovered"] = false
			if not s.has("kills_by_player"):
				s["kills_by_player"] = 0
			# ledger/valve counters coerce — a corrupt string would poison the
			# decay/window arithmetic downstream
			for key in ["grudge", "grudge_t", "harass", "harass_t"]:
				var v: Variant = sp.get(key)
				if (v is float or v is int) and is_finite(v):
					s[key] = float(v)
				else:
					s.erase(key)
			eco.species.append(s)
	var flora_v: Variant = data.get("flora")
	eco.flora = float(flora_v) \
			if (flora_v is float or flora_v is int) and is_finite(flora_v) else 60.0
	var cap_v: Variant = data.get("floraCap")
	eco.flora_cap = float(cap_v) \
			if (cap_v is float or cap_v is int) and is_finite(cap_v) else 100.0
	# optional fields tolerate older saves; unknown species fields
	# (grudge/kin_tag/tideBorn/defect/pendingAllele) ride the dict copy above
	var corpses_v: Variant = data.get("corpses")
	eco.corpses = maxf(0.0, float(corpses_v)) \
			if (corpses_v is float or corpses_v is int) and is_finite(corpses_v) else 0.0
	# bio_shift pairs ride the save (the conversion stands for the run);
	# malformed entries drop silently
	var shifts_v: Variant = data.get("shifts")
	if shifts_v is Array:
		for e in shifts_v:
			if e is Dictionary and e.get("from") is String and e.get("to") is String:
				eco.shifts.append(e)
	return eco


## Save blob — TS wire key names verbatim (floraCap); species fields ride the
## native EcoSpecies dict keys (fresh native saves never meet the TS ones).
func to_json() -> Dictionary:
	return {
		"species": species,
		"flora": flora,
		"floraCap": flora_cap,
		"corpses": corpses,
		"shifts": shifts,
	}


# worldGenome.ts flagFrom: a world flag is live when any carried trait lists
# an effect {kind: 'flag', key}. Delegates to world_genome.gd's world_has —
# one home, two consumers: the eco reads raw world blobs, the codex reads
# full genomes, both ride the same tolerant walk (a gate that cannot be read
# stays shut).
static func _world_has(world: Dictionary, key: String) -> bool:
	return WorldGenomeScript.world_has(world, key)


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
