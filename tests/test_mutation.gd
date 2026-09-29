# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path — a bare global name (Mutation,
# Genome, Rng, Fixtures) would not resolve without the editor's class cache.
const Mutation := preload("res://src/evo/mutation.gd")
const Genome := preload("res://src/evo/genome.gd")
const Rng := preload("res://src/core/rng.gd")
const Fixtures := preload("res://tests/fixtures.gd")

# Fixture floats carry <=1 ulp node-vs-Godot parse noise -> approx eps 1e-9.
const FLOAT_FIELDS := ["size", "hue", "sat"]

# TS weighted table (Spore src/evo/mutation.ts) — kind shares must land inside
# a loose ±20% band over 200 deterministic rolls.
const ANOMALY_WEIGHTS := {"recessive_echo": 0.45, "dormant": 0.35, "transposed": 0.2}


func _load_fixture() -> Dictionary:
	return Fixtures.load_json("mutate_crossover")


func _assert_genome(got: Dictionary, want: Dictionary, msg: String) -> void:
	eq(got.size(), want.size(), "%s (key count)" % msg)
	for key in want.keys():
		if FLOAT_FIELDS.has(key):
			approx(float(got.get(key)), float(want[key]), "%s.%s" % [msg, key])
		else:
			eq(got.get(key), want[key], "%s.%s" % [msg, key])


# ---- fixture parity pins ----------------------------------------------------

func test_mutate_fixture_20_cases() -> void:
	var data: Dictionary = _load_fixture()
	var mutates: Array = data["mutates"]
	eq(mutates.size(), 20, "fixture pins 20 mutate cases")
	for case_v in mutates:
		var case: Dictionary = case_v
		# TS generator: mutate(defaultGenome(), new Rng(i), 0.35) — no bias
		var out: Dictionary = Mutation.mutate(Genome.default_genome(), Rng.new(int(case["rngSeed"])), float(case["rate"]))
		_assert_genome(out, case["genome"], "mutate i=%d" % int(case["i"]))
		eq(Genome.genome_hash(out), case["hash"], "mutate hash i=%d" % int(case["i"]))


func test_crossover_fixture_10_cases() -> void:
	var data: Dictionary = _load_fixture()
	var parents: Dictionary = data["parents"]
	var crosses: Array = data["crossovers"]
	eq(crosses.size(), 10, "fixture pins 10 crossover cases")
	for case_v in crosses:
		var case: Dictionary = case_v
		# TS generator: crossover(A, B, new Rng(100+j)) — default rate, no opts
		var out: Dictionary = Mutation.crossover(parents["a"], parents["b"], Rng.new(int(case["rngSeed"])), float(case["mutateRate"]))
		_assert_genome(out, case["genome"], "crossover j=%d" % int(case["j"]))
		eq(Genome.genome_hash(out), case["hash"], "crossover hash j=%d" % int(case["j"]))


func test_biased_crossover_fixture_5_cases() -> void:
	var data: Dictionary = _load_fixture()
	var parents: Dictionary = data["parents"]
	var biased: Array = data["biasedCrossovers"]
	eq(biased.size(), 5, "fixture pins 5 biased crossover cases")
	for case_v in biased:
		var case: Dictionary = case_v
		# TS generator: crossover(A, B, new Rng(200+j), 0.18, { bias })
		var out: Dictionary = Mutation.crossover(parents["a"], parents["b"], Rng.new(int(case["rngSeed"])), float(case["mutateRate"]), {"bias": case["bias"]})
		_assert_genome(out, case["genome"], "biased j=%d" % int(case["j"]))
		eq(Genome.genome_hash(out), case["hash"], "biased hash j=%d" % int(case["j"]))


# ---- mutate mechanics --------------------------------------------------------

func test_mutate_does_not_mutate_base() -> void:
	var base: Dictionary = Genome.default_genome()
	var snap: Dictionary = base.duplicate()
	Mutation.mutate(base, Rng.new(42), 0.9)
	eq(base, snap, "mutate leaves its input untouched (TS {...base} spread)")


func test_mutate_rate_clamps_at_12() -> void:
	# the effective rate clamps to 1.2 — rate 10 must ride the exact same stream
	var a: Dictionary = Mutation.mutate(Genome.default_genome(), Rng.new(7), 1.2)
	var b: Dictionary = Mutation.mutate(Genome.default_genome(), Rng.new(7), 10.0)
	eq(a, b, "rate 10 produces the 1.2 stream value for value")
	ok(a != Genome.default_genome(), "rate 1.2 actually changes genes")


func test_mutate_rate_zero_only_bumps_generation() -> void:
	var base: Dictionary = Genome.default_genome()
	base["generation"] = 9
	var out: Dictionary = Mutation.mutate(base, Rng.new(3), 0.0)
	var expect: Dictionary = base.duplicate()
	expect["generation"] = 10
	eq(out, expect, "rate 0 changes nothing but generation = base + 1")


# ---- M1 anomaly table --------------------------------------------------------

func test_anomaly_kind_weights_over_200_rolls() -> void:
	var data: Dictionary = _load_fixture()
	var a: Dictionary = data["parents"]["a"]
	var b: Dictionary = data["parents"]["b"]
	var counts := {"recessive_echo": 0, "dormant": 0, "transposed": 0}
	var n := 200
	for i in n:
		var info: Dictionary = {"anomaly": null, "defect": null}
		Mutation.crossover(a, b, Rng.new(3000 + i), 0.18, {"anomalyChance": 1.0, "info": info})
		var stamp: Variant = info["anomaly"]
		ok(stamp != null, "anomalyChance 1.0 stamps an anomaly on roll %d" % i)
		if stamp == null:
			continue
		var kind: String = stamp["kind"]
		ok(ANOMALY_WEIGHTS.has(kind), "known anomaly kind on roll %d (got %s)" % [i, kind])
		if ANOMALY_WEIGHTS.has(kind):
			counts[kind] += 1
	for kind in ANOMALY_WEIGHTS.keys():
		var share: float = float(counts[kind]) / float(n)
		var w: float = ANOMALY_WEIGHTS[kind]
		ok(share >= w * 0.8 and share <= w * 1.2,
				"kind %s share %f within 20 pct of %f (counts %s)" % [kind, share, w, counts])


func test_transposed_writes_within_gene_bounds() -> void:
	var data: Dictionary = _load_fixture()
	var a: Dictionary = data["parents"]["a"]
	var b: Dictionary = data["parents"]["b"]
	var bounds: Dictionary = Genome.gene_bounds()
	var seen := 0
	for i in 200:
		var info: Dictionary = {"anomaly": null, "defect": null}
		var child: Dictionary = Mutation.crossover(a, b, Rng.new(3200 + i), 0.18, {"anomalyChance": 1.0, "info": info})
		var stamp: Variant = info["anomaly"]
		if stamp == null or stamp["kind"] != "transposed":
			continue
		seen += 1
		var gene: String = stamp["gene"]
		ok(Mutation.INT_GENES.has(gene), "transposed gene %s is an INT_GENE" % gene)
		var bound: Dictionary = bounds[gene]
		var slot: float = float(child[gene])
		ok(slot >= float(bound["min"]) and slot <= float(bound["max"]),
				"transposed slot %s=%f within bounds" % [gene, slot])
		eq(stamp["value"], child[gene], "transposed stamp value == the rewritten slot")
		# same-seed baseline (no opts): the table rewrites exactly this one slot
		var baseline: Dictionary = Mutation.crossover(a, b, Rng.new(3200 + i), 0.18)
		for key in baseline.keys():
			if key == gene:
				continue
			eq(child.get(key), baseline[key], "transposed leaves %s untouched" % key)
	ok(seen > 0, "transposed observed over 200 rolls (seen %d)" % seen)


func test_recessive_echo_carrier_stamp_and_burst() -> void:
	var data: Dictionary = _load_fixture()
	var a: Dictionary = data["parents"]["a"]
	var b: Dictionary = data["parents"]["b"]
	var bounds: Dictionary = Genome.gene_bounds()
	var seen := 0
	for i in 200:
		var info: Dictionary = {"anomaly": null, "defect": null}
		var child: Dictionary = Mutation.crossover(a, b, Rng.new(3400 + i), 0.18, {"anomalyChance": 1.0, "info": info})
		var stamp: Variant = info["anomaly"]
		if stamp == null or stamp["kind"] != "recessive_echo":
			continue
		seen += 1
		# the carrier record: kind + the burst locus + the expressed value
		ok(stamp.has("kind") and stamp.has("gene") and stamp.has("value"),
				"echo stamp carries kind/gene/value")
		ok(not stamp.has("wakeGen"), "echo stamp carries no wakeGen")
		var gene: String = stamp["gene"]
		var bound: Dictionary = bounds[gene]
		var slot: float = float(child[gene])
		ok(slot >= float(bound["min"]) and slot <= float(bound["max"]),
				"echo slot %s=%f within bounds" % [gene, slot])
		# the burst is +/-2 past the masked locus, clamped — one slot only
		var baseline: Dictionary = Mutation.crossover(a, b, Rng.new(3400 + i), 0.18)
		var exp_up: float = minf(float(bound["max"]), float(baseline[gene]) + 2.0)
		var exp_dn: float = maxf(float(bound["min"]), float(baseline[gene]) - 2.0)
		ok(slot == exp_up or slot == exp_dn,
				"echo burst is baseline +/-2 clamped (slot %f, up %f, dn %f)" % [slot, exp_up, exp_dn])
		for key in baseline.keys():
			if key == gene:
				continue
			eq(child.get(key), baseline[key], "echo leaves %s untouched" % key)
	ok(seen > 0, "recessive_echo observed over 200 rolls (seen %d)" % seen)


func test_dormant_wake_gen_and_latent_slot() -> void:
	var data: Dictionary = _load_fixture()
	var a: Dictionary = data["parents"]["a"]
	var b: Dictionary = data["parents"]["b"]
	var seen := 0
	for i in 200:
		var info: Dictionary = {"anomaly": null, "defect": null}
		var child: Dictionary = Mutation.crossover(a, b, Rng.new(3600 + i), 0.18, {"anomalyChance": 1.0, "info": info})
		var stamp: Variant = info["anomaly"]
		if stamp == null or stamp["kind"] != "dormant":
			continue
		seen += 1
		var gen: int = int(child["generation"])
		var wake: int = int(stamp["wakeGen"])
		ok(wake >= gen + 2 and wake <= gen + 4,
				"dormant wakeGen %d in [%d, %d]" % [wake, gen + 2, gen + 4])
		# latent: the allele value rides the stamp, the slot itself is never written
		var gene: String = stamp["gene"]
		var baseline: Dictionary = Mutation.crossover(a, b, Rng.new(3600 + i), 0.18)
		eq(child[gene], baseline[gene], "dormant slot %s stays latent (unwritten)" % gene)
		for key in baseline.keys():
			if key == "hue":
				continue
			eq(child.get(key), baseline[key], "dormant leaves %s untouched" % key)
		# light cosmetic tilt visible from generation 1: hue shifts exactly +/-14
		var d: float = fmod(float(child["hue"]) - float(baseline["hue"]) + 360.0, 360.0)
		ok(absf(d - 14.0) < 1e-6 or absf(d - 346.0) < 1e-6, "dormant hue tilt is +/-14 (got %f)" % d)
	ok(seen > 0, "dormant observed over 200 rolls (seen %d)" % seen)


# ---- M2 defect genes ---------------------------------------------------------

func test_defect_incidence_within_total_budget() -> void:
	var data: Dictionary = _load_fixture()
	var a: Dictionary = data["parents"]["a"]
	var b: Dictionary = data["parents"]["b"]
	var n := 600
	for rate_v in [0.2, 0.3]:
		var hits := 0
		for i in n:
			var info: Dictionary = {"anomaly": null, "defect": null}
			Mutation.crossover(a, b, Rng.new(4000 + i), 0.18, {"defectRate": rate_v, "info": info})
			if info["defect"] != null:
				hits += 1
				ok(Mutation.DEFECT_NAMES.has(info["defect"]["kind"]),
						"defect kind %s in DEFECT_NAMES" % info["defect"]["kind"])
		var incidence: float = float(hits) / float(n)
		ok(incidence <= 0.35, "defectRate %.1f incidence %f <= 0.35 (%d/%d)" % [float(rate_v), incidence, hits, n])
	# the budget gate: defectRate 0 never stamps and never burns RNG
	var zero_info: Dictionary = {"anomaly": null, "defect": null}
	var zero_child: Dictionary = Mutation.crossover(a, b, Rng.new(4999), 0.18, {"defectRate": 0.0, "info": zero_info})
	var plain_child: Dictionary = Mutation.crossover(a, b, Rng.new(4999), 0.18)
	eq(zero_child, plain_child, "defectRate 0 is a no-op on the genome")
	eq(zero_info["defect"], null, "defectRate 0 stamps nothing")


func test_defect_stamp_shape_and_glass_bones_write() -> void:
	var data: Dictionary = _load_fixture()
	var a: Dictionary = data["parents"]["a"]
	var b: Dictionary = data["parents"]["b"]
	var bounds: Dictionary = Genome.gene_bounds()
	var kinds_seen := {}
	for i in 300:
		var info: Dictionary = {"anomaly": null, "defect": null}
		var child: Dictionary = Mutation.crossover(a, b, Rng.new(4200 + i), 0.18, {"defectRate": 1.0, "info": info})
		var stamp: Variant = info["defect"]
		ok(stamp != null, "defectRate 1.0 always stamps (i=%d)" % i)
		if stamp == null:
			continue
		var kind: String = stamp["kind"]
		kinds_seen[kind] = true
		eq(stamp.size(), 1, "defect stamp carries only kind")
		ok(Mutation.DEFECT_NAMES.has(kind), "defect kind %s in DEFECT_NAMES" % kind)
		# anomalyChance absent -> the M1 table stays idle: the baseline is the
		# exact pre-defect child
		var baseline: Dictionary = Mutation.crossover(a, b, Rng.new(4200 + i), 0.18)
		if kind == "glass_bones":
			# half-strength allele: +1 to a speed gene, clamped at the max
			var f_hit: bool = float(child["flagella"]) == minf(float(bounds["flagella"]["max"]), float(baseline["flagella"]) + 1.0)
			var f_same: bool = float(child["flagella"]) == float(baseline["flagella"])
			var l_hit: bool = float(child["legs"]) == minf(float(bounds["legs"]["max"]), float(baseline["legs"]) + 1.0)
			var l_same: bool = float(child["legs"]) == float(baseline["legs"])
			ok((f_hit and l_same) or (l_hit and f_same),
					"glass_bones raises exactly one speed gene by 1")
			for key in baseline.keys():
				if key == "flagella" or key == "legs":
					continue
				eq(child.get(key), baseline[key], "glass_bones leaves %s untouched" % key)
		else:
			# frenzy/famine are stamp-only — the genome is untouched
			eq(child, baseline, "%s leaves the genome untouched" % kind)
	eq(kinds_seen.size(), 3, "all three defect kinds observed over 300 rolls (got %s)" % [kinds_seen])


# ---- MutationBias wiring -----------------------------------------------------

func test_bias_rate_add_raises_gene_changes() -> void:
	var base: Dictionary = Genome.default_genome()
	var changed0 := 0
	var changed9 := 0
	for i in 200:
		var out0: Dictionary = Mutation.mutate(base, Rng.new(5000 + i), 0.35, {})
		var out9: Dictionary = Mutation.mutate(base, Rng.new(5000 + i), 0.35, {"rate_add": 0.9})
		for gene in Mutation.INT_GENES:
			if out0[gene] != base[gene]:
				changed0 += 1
			if out9[gene] != base[gene]:
				changed9 += 1
	ok(changed9 > changed0,
			"rate_add 0.9 changes more int genes (%d) than rate_add 0 (%d)" % [changed9, changed0])


func test_bias_pull_tilts_diet_and_coat() -> void:
	var n := 1000
	var car_pull := 0
	var car_free := 0
	var plates_pull := 0
	var plates_free := 0
	for i in n:
		var w: Dictionary = Mutation.mutate(Genome.default_genome(), Rng.new(6000 + i), 0.35, {"dietPull": "carnivore", "coatPull": "plates"})
		var wo: Dictionary = Mutation.mutate(Genome.default_genome(), Rng.new(6000 + i), 0.35, {})
		if w["diet"] == "carnivore":
			car_pull += 1
		if wo["diet"] == "carnivore":
			car_free += 1
		if w["coat"] == "plates":
			plates_pull += 1
		if wo["coat"] == "plates":
			plates_free += 1
	ok(car_pull > car_free, "dietPull carnivore raises carnivore share (%d vs %d of %d)" % [car_pull, car_free, n])
	ok(plates_pull > plates_free, "coatPull plates raises plates share (%d vs %d of %d)" % [plates_pull, plates_free, n])


func test_anomaly_and_defect_name_tables() -> void:
	eq(Mutation.ANOMALY_NAMES, {
		"recessive_echo": "Recessive Echo", "dormant": "Sleeper Gene", "transposed": "Transposon",
	}, "ANOMALY_NAMES matches the TS table")
	eq(Mutation.DEFECT_NAMES, {
		"glass_bones": "Glass Bones", "frenzy": "Frenzy", "famine": "Famine",
	}, "DEFECT_NAMES matches the TS table")
