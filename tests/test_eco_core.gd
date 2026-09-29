# Ecosystem core tick tests: fixture parity walk + empty-mods baseline +
# single-mod floor probes (patterns mirrored from TS tests/econ-probe.test.ts).
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path.
const Ecosystem := preload("res://src/evo/ecosystem.gd")
const Rng := preload("res://src/core/rng.gd")
const Genome := preload("res://src/evo/genome.gd")
const Fixtures := preload("res://tests/fixtures.gd")

# Fixture floats carry <=1 ulp Godot-parse noise vs node (see fixtures.gd).
const PARITY_EPS := 1e-9


# TS econ-probe simMinutes: 6 lines from defaultGenome(), diets cycling
# carnivore/herbivore (i % 3 == 0), sizes 0.8..1.8, pop 8; mods set after the
# roster (null = never touched — the "unset" side of the baseline pin).
func _sim_mods(mins: int, mods) -> Variant:
	var eco: Variant = Ecosystem.new(Rng.new_from(7))
	for i in 6:
		var g: Dictionary = Genome.default_genome()
		g["diet"] = "carnivore" if i % 3 == 0 else "herbivore"
		g["size"] = 0.8 + i * 0.2
		eco.add_species(g, 8.0)
	if mods != null:
		eco.mods = mods
	for s in mins * 60:
		eco.tick(1.0)
	return eco


func _check_snapshot(eco, snap: Dictionary, label: String) -> void:
	approx(float(eco.flora), float(snap["flora"]), "%s flora" % label, PARITY_EPS)
	eq(int(eco.total_eaten), int(snap["totalEaten"]), "%s totalEaten" % label)
	var wants: Array = snap["species"]
	eq(eco.species.size(), wants.size(), "%s species count" % label)
	for i in wants.size():
		var want: Dictionary = wants[i]
		var got: Dictionary = eco.species[i]
		eq(got["id"], want["id"], "%s sp%d id" % [label, i])
		eq(got["name"], want["name"], "%s sp%d name" % [label, i])
		approx(float(got["pop"]), float(want["pop"]), "%s sp%d pop" % [label, i], PARITY_EPS)
		eq(got["extinct"], want["extinct"], "%s sp%d extinct" % [label, i])


# --- fixture parity: the absolute arbiter ------------------------------------


func test_fixture_walk_snapshot_parity() -> void:
	var data := Fixtures.load_json("eco_tick")
	ok(not data.is_empty(), "fixture eco_tick.json loads")
	if data.is_empty():
		return
	var eco: Variant = Ecosystem.new(Rng.new_from(int(data["ecoSeed"])))
	for entry in data["roster"]:
		eco.add_species(entry["genome"], float(entry["pop"]))
	var snaps: Array = data["snapshots"]
	var next := 0
	# t = 0 is snapshotted BEFORE the first tick
	_check_snapshot(eco, snaps[next], "t=0")
	next += 1
	var dt := float(data["dt"])
	for s in range(1, int(data["ticks"]) + 1):
		eco.tick(dt)
		if next < snaps.size() and s == int(snaps[next]["t"]):
			_check_snapshot(eco, snaps[next], "t=%d" % s)
			next += 1
	eq(next, snaps.size(), "every fixture snapshot was checked")


# --- empty mods = baseline (every read is mods.get(key, default)) ------------


func test_empty_mods_equal_unset_baseline_bit_identical() -> void:
	var a: Variant = _sim_mods(30, null)  # mods never touched
	var b: Variant = _sim_mods(30, {})  # mods = {}
	# every modifier spelled at its default value must read bit-identical to
	# the key being absent (TS econ-probe "empty mods equal baseline exactly")
	var c: Variant = _sim_mods(30, {
		"growth_mult": 1, "predation_mult": 1, "speciation_mult": 1,
		"meal_dna_mult": 1, "herb_drain_mult": 1,
	})
	eq(b.species.size(), a.species.size(), "mods {} leaves the roster identical in size")
	eq(c.species.size(), a.species.size(), "spelled defaults leave the roster identical in size")
	for i in a.species.size():
		var sa: Dictionary = a.species[i]
		# in-process runs share the same float64 ops — equality IS the point
		# (the TS test deep-equals toJSON())
		ok(sa["pop"] == b.species[i]["pop"] and sa["pop"] == c.species[i]["pop"],
				"sp%d pop bit-identical across unset/{}/defaults" % i)
		eq(sa["id"], b.species[i]["id"], "sp%d id identical (rng stream untouched)" % i)
		eq(sa["id"], c.species[i]["id"], "sp%d id identical with spelled defaults" % i)
	ok(a.flora == b.flora and a.flora == c.flora, "flora bit-identical across unset/{}/defaults")
	eq(a.total_eaten, b.total_eaten, "total_eaten identical")
	eq(b.total_eaten, c.total_eaten, "total_eaten identical with spelled defaults")


func test_mods_actually_reach_the_sim() -> void:
	var a: Variant = _sim_mods(30, null)
	var b: Variant = _sim_mods(30, {"herb_drain_mult": 4})
	var diverged: bool = a.flora != b.flora or a.species.size() != b.species.size()
	if not diverged:
		for i in a.species.size():
			if a.species[i]["pop"] != b.species[i]["pop"]:
				diverged = true
				break
	ok(diverged, "herb_drain_mult 4 changes the trajectory (mods reach tick)")


# --- single-mod probes: the eco floors hold over 60 min ----------------------


func test_single_mod_probes_keep_eco_floors() -> void:
	# mirrors TS "every single seed trait keeps a living minimum eco" as the
	# four known single-mod multipliers (the world genome lands in a later task)
	var probes := [
		{"herb_drain_mult": 1.6},
		{"growth_mult": 1.25},
		{"speciation_mult": 1.5},
		{"predation_mult": 1.3},
	]
	for probe in probes:
		var label: String = "%s=%s" % [probe.keys()[0], probe.values()[0]]
		var eco: Variant = _sim_mods(60, probe)
		ok(eco.living().size() >= 2, "%s: >=2 living lines after 60 min" % label)
		ok(is_finite(eco.flora) and eco.flora >= 12.0, "%s: flora >= 12 after 60 min" % label)
		for sp in eco.species:
			ok(is_finite(float(sp["pop"])) and float(sp["pop"]) >= 0.0,
					"%s: %s pop >= 0" % [label, sp["id"]])


# --- add_species shape --------------------------------------------------------


func test_add_species_shape_and_opts() -> void:
	var eco: Variant = Ecosystem.new(Rng.new_from(9))
	var s: Dictionary = eco.add_species(Genome.default_genome(), 8.0)
	ok(String(s["id"]).begins_with("sp0_"), "id prefix sp0_ (index before append)")
	ok(String(s["name"]).length() > 0, "name drawn from Names")
	eq(s["discovered"], false, "non-kin starts undiscovered")
	eq(s["kin"], false, "non-kin flag false")
	eq(s["extinct"], false, "starts alive")
	eq(int(s["kills_by_player"]), 0, "kill ledger starts at 0")
	approx(float(s["pop"]), 8.0, "pop stored")
	# genome is clamped AND copied (TS clampGenome({...genome}))
	var g2: Dictionary = Genome.default_genome()
	g2["spikes"] = 99
	var s2: Dictionary = eco.add_species(g2, 2.0)
	eq(int(s2["genome"]["spikes"]), 8, "genome clamped to GENE_BOUNDS on add")
	g2["spikes"] = 0
	eq(int(s2["genome"]["spikes"]), 8, "species genome not aliased to the caller's dict")
	# kin opts: discovered rides kin (TS opts.kin === true)
	var s3: Dictionary = eco.add_species(Genome.default_genome(), 4.0, {"kin": true})
	eq(s3["kin"], true, "kin flag from opts")
	eq(s3["discovered"], true, "kin lines start discovered")
	# opts override fields (drop_corpse renames the tide line in Task 9)
	var s4: Dictionary = eco.add_species(Genome.default_genome(), 0.0, {"name": "Cadaverexus"})
	eq(s4["name"], "Cadaverexus", "opts.name overrides the drawn name")


# --- tick outputs and dynamics ------------------------------------------------


func test_tick_returns_extinction_and_speciation_lists() -> void:
	var eco: Variant = Ecosystem.new(Rng.new_from(11))
	eco.add_species(Genome.default_genome(), 8.0)
	var out: Dictionary = eco.tick(1.0)
	ok(out.has("extinctions") and out.has("speciations"), "tick returns extinctions+speciations")
	eq(out["extinctions"].size(), 0, "no extinctions in a healthy tick")
	# a species below the 0.4 threshold dies at the next tick
	var s: Dictionary = eco.species[0]
	s["pop"] = 0.2
	out = eco.tick(1.0)
	eq(out["extinctions"].size(), 1, "pop < 0.4 -> extinct, reported in extinctions")
	eq(s["extinct"], true, "extinct flag set")
	approx(float(s["pop"]), 0.0, "pop clamped to 0 on extinction")
	# Task 9: the bio_shift reequilibrate tops the web back up to >= 2 living
	# lines after a loss (TS solvability top-up — cloneGenome(defaultGenome()))
	eq(eco.living().size(), 2, "solvability top-up refills the web to 2 living lines")


func test_player_species_is_exempt_from_dynamics() -> void:
	# TS: s.id === playerSpeciesId -> continue (the player line is hand-driven)
	var eco: Variant = Ecosystem.new(Rng.new_from(14))
	var player: Dictionary = eco.add_species(Genome.default_genome(), 10.0)
	eco.add_species(Genome.default_genome(), 10.0)
	for i in 60:
		eco.tick(1.0, player["id"])
	approx(float(player["pop"]), 10.0, "player line pop untouched over 60 ticks")
	# the kin flag exempts without an id too
	var eco2: Variant = Ecosystem.new(Rng.new_from(15))
	var kin: Dictionary = eco2.add_species(Genome.default_genome(), 10.0, {"kin": true})
	for i in 60:
		eco2.tick(1.0)
	approx(float(kin["pop"]), 10.0, "kin line exempt from dynamics")


# --- notify_kill pricing -------------------------------------------------------


func test_notify_kill_pricing_matches_ts_formula() -> void:
	# default genome: size 1, spikes 0, jaw 1 -> meal = 1*(1+0+0.1) = 1.1
	# base = 9 + meal*6 + max(0, meal - strength)*6 = 9 + 6.6 + 0.6 = 16.2.
	# Values hand-pinned from the TS formulas (no fixture covers notifyKill).
	var eco: Variant = Ecosystem.new(Rng.new_from(3))
	var sp: Dictionary = eco.add_species(Genome.default_genome(), 40.0)
	# husbandry: pop 40 -> 39 after the decrement, >25 herds pay a premium
	eq(eco.notify_kill(sp["id"], 1.0), 19, "pop>25 premium: 16.2 * 1.2 -> 19")
	approx(float(sp["pop"]), 39.0, "pop decremented by 1")
	eq(int(sp["kills_by_player"]), 1, "kills_by_player counted")
	eq(int(eco.total_eaten), 1, "total_eaten counted")
	# mid band: pop 8 -> 7 -> sc 1
	sp["pop"] = 8.0
	eq(eco.notify_kill(sp["id"], 1.0), 16, "mid band sc 1 -> 16")
	# brink discount: pop 6 -> 5 -> sc 0.6 (don't finish the species off)
	sp["pop"] = 6.0
	eq(eco.notify_kill(sp["id"], 1.0), 10, "pop<6 discount: 16.2 * 0.6 -> 10")
	# meal_dna_mult scales the payout
	eco.mods = {"meal_dna_mult": 1.2}
	sp["pop"] = 8.0
	eq(eco.notify_kill(sp["id"], 1.0), 19, "meal_dna_mult 1.2: 16.2 * 1.2 -> 19")
	# a big player eats down: no (meal - strength) bonus
	eco.mods = {}
	sp["pop"] = 8.0
	eq(eco.notify_kill(sp["id"], 5.0), 16, "strength 5 > meal: round(15.6) = 16")
	# unknown id / dead line pay nothing
	eq(eco.notify_kill("nope", 1.0), 0, "unknown id -> 0")
	sp["extinct"] = true
	eq(eco.notify_kill(sp["id"], 1.0), 0, "extinct species -> 0")


# --- chaos hook -----------------------------------------------------------------


func test_force_speciation_chaos_hook() -> void:
	var eco: Variant = Ecosystem.new(Rng.new_from(12))
	eco.add_species(Genome.default_genome(), 8.0)
	eco.add_species(Genome.default_genome(), 8.0, {"kin": true})
	var ns: Dictionary = eco.force_speciation()
	ok(ns != null, "force_speciation returns the new line")
	eq(eco.species.size(), 3, "roster grew by one")
	eq(ns["kin"], false, "forced line is not kin")
	ok(String(ns["id"]).begins_with("sp2_"), "forced line gets the next id slot")
	# an all-kin roster has no candidates -> null
	var eco2: Variant = Ecosystem.new(Rng.new_from(13))
	eco2.add_species(Genome.default_genome(), 8.0, {"kin": true})
	ok(eco2.force_speciation() == null, "no candidates -> null")
