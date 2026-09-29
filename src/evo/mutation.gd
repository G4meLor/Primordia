## Mutation operators: the chaos backbone. `mutate` perturbs a genome;
## `crossover` blends two genomes (Gene Splicer lab, breeding).
## Port of Spore src/evo/mutation.ts (post review-fix state): bias wiring with
## the effective rate clamped to 1.2, plus the catalog-IV splice table (M1
## anomalies recessive_echo/dormant/transposed + M2 defect genes) applied AFTER
## the crossover invariant — the table never changes how genes inherit.
## Genomes are plain Dictionaries (the established genome.gd port shape);
## MutationBias / CrossoverOpts / SpliceInfo are Dictionaries too, keeping the
## TS field names verbatim (rate_add, dietPull, anomalyChance, defectRate,
## wakeGen — the mutate_crossover fixture pins the bias keys). rng stays
## untyped: a global class_name annotation would not resolve in `-s` mode on a
## fresh clone (see names.gd).
class_name Mutation
extends RefCounted

# Same -s-mode constraint as rng.gd's SELF_SCRIPT idiom: resolve Genome by
# path — a bare global name would not resolve without the editor's class cache.
const GenomeScript := preload("res://src/evo/genome.gd")

const INT_GENES: Array[String] = [
	"flagella", "cilia", "spikes", "jaw", "toxin", "proboscis", "electro", "jet",
	"legs", "arms", "eyes", "horns", "wings", "brain",
]

# ---- catalog IV: mutation mechanics (post-hook on crossover) ---------------
# Crossover stays an invariant; every "surprise" is this ONE table applied to
# its output. Anomalies write normal gene slots, so the gate math is intact.
const ANOMALY_NAMES := {
	"recessive_echo": "Recessive Echo",
	"dormant": "Sleeper Gene",
	"transposed": "Transposon",
}
const DEFECT_NAMES := {
	"glass_bones": "Glass Bones",
	"frenzy": "Frenzy",
	"famine": "Famine",
}


## Perturb a genome. `rate` ~0..1 scales how many genes change (effective
## rate clamped to 1.2). Chaos-heavy events pass a high rate.
## bias: MutationBias dict {rate_add, dietPull, coatPull, allele_hidden,
## defect_rate} — every field optional.
static func mutate(base: Dictionary, rng, rate: float = 0.35, bias: Dictionary = {}) -> Dictionary:
	var g: Dictionary = GenomeScript.clamp_genome(base.duplicate())
	var ra: Variant = bias.get("rate_add")
	var r: float = minf(1.2, rate + (0.0 if ra == null else float(ra)))
	for gene in INT_GENES:
		if rng.chance(r * 0.45):
			var b: Dictionary = GenomeScript.GENE_BOUNDS[gene]
			var dir: int = 1 if rng.chance(0.5) else -1
			# inline bounds clamp; the final clamp_genome collapses integral
			# floats back to int genes
			g[gene] = maxf(float(b["min"]), minf(float(b["max"]), float(g[gene]) + dir))
	if rng.chance(r * 0.3):
		g["size"] = maxf(0.6, minf(2.2, float(g["size"]) + rng.gauss() * 0.15))
	if rng.chance(r * 0.5):
		# g.hue is already wrapped into [0, 360) by the opening clamp, so the
		# +360 keeps the dividend positive and fmod matches the TS `%` exactly
		g["hue"] = fmod(float(g["hue"]) + rng.range(-30.0, 30.0) + 360.0, 360.0)
	if rng.chance(r * 0.2):
		g["sat"] = maxf(0.05, minf(1.0, float(g["sat"]) + rng.gauss() * 0.12))
	if rng.chance(r * 0.12):
		# TS short-circuit: with no dietPull the 0.6 chance roll never happens
		if _truthy(bias.get("dietPull")) and rng.chance(0.6):
			g["diet"] = bias["dietPull"]
		else:
			g["diet"] = rng.pick(["herbivore", "omnivore", "carnivore"])
	if rng.chance(r * 0.1):
		g["pattern"] = rng.pick(["plain", "spots", "stripes", "glow"])
	if rng.chance(r * 0.1):
		g["tail"] = not g.get("tail")  # JS !g.tail — a missing tail flips to true
	if rng.chance(r * 0.08):
		if _truthy(bias.get("coatPull")) and rng.chance(0.6):
			g["coat"] = bias["coatPull"]
		else:
			g["coat"] = rng.pick(["skin", "fur", "scales", "plates"])
	# (TS NaN on a generation-less base is unreachable for real genomes; the
	# default keeps GDScript type-safe)
	g["generation"] = int(base.get("generation", 1)) + 1
	return GenomeScript.clamp_genome(g)


## Sexual-style crossover for the Gene Splicer: per-gene inheritance with
## occasional blending, plus a guaranteed fresh mutation. The M1/M2 anomaly
## table runs AFTER the invariant result — it never changes how genes
## inherit, only what the child additionally expresses.
## opts: CrossoverOpts dict {anomalyChance, defectRate, bias, info} — every
## field optional; info is the caller's SpliceInfo {anomaly, defect}, written
## in place (Dictionaries pass by reference, like the TS object).
static func crossover(a: Dictionary, b: Dictionary, rng, mutate_rate: float = 0.18, opts: Dictionary = {}) -> Dictionary:
	var g: Dictionary = a.duplicate()
	for gene in INT_GENES:
		if rng.chance(0.5):
			g[gene] = b[gene]
	g["size"] = a["size"] if rng.chance(0.5) else b["size"]
	g["hue"] = a["hue"] if rng.chance(0.5) else b["hue"]
	if rng.chance(0.25):
		g["hue"] = (float(a["hue"]) + float(b["hue"])) / 2.0  # blend sometimes
	g["diet"] = a["diet"] if rng.chance(0.5) else b["diet"]
	g["pattern"] = a["pattern"] if rng.chance(0.5) else b["pattern"]
	g["coat"] = a["coat"] if rng.chance(0.5) else b["coat"]
	g["tail"] = a["tail"] if rng.chance(0.5) else b["tail"]
	g["generation"] = maxi(int(a.get("generation", 1)), int(b.get("generation", 1))) + 1
	var bias_v: Variant = opts.get("bias")
	var child: Dictionary = GenomeScript.clamp_genome(mutate(g, rng, mutate_rate, bias_v if bias_v is Dictionary else {}))
	# TS `if (opts)` — an empty opts table is a no-op that burns no RNG
	_apply_splice_table(child, a, b, rng, opts)
	return child


## The ONE post-crossover surprise table (catalog IV): M1 kinds
## {recessive_echo, dormant, transposed} + M2 defects. Everything writes
## ordinary gene slots via clampGenome — no new gene system.
static func _apply_splice_table(child: Dictionary, a: Dictionary, b: Dictionary, rng, opts: Dictionary) -> void:
	var info: Variant = opts.get("info")
	if _truthy(opts.get("anomalyChance")) and rng.chance(float(opts["anomalyChance"])):
		var kind: String = rng.weighted([
			[0.45, "recessive_echo"],
			[0.35, "dormant"],
			[0.2, "transposed"],
		])
		if kind == "transposed":
			# transposon: jumps to a neighbouring locus — the rewrite occupies a
			# normal gene slot (gate math intact), clamped by clampGenome
			var gene: String = rng.pick(INT_GENES)
			var bound: Dictionary = GenomeScript.GENE_BOUNDS[gene]
			var cur: float = float(child[gene])
			var dir: int = 1 if rng.chance(0.5) else -1
			var value: Variant = _num(maxf(float(bound["min"]), minf(float(bound["max"]), cur + dir)))
			child[gene] = value
			if info != null:
				info["anomaly"] = {"kind": kind, "gene": gene, "value": value}
		elif kind == "recessive_echo":
			# recessive echo: a locus where BOTH parents agree was masking an older
			# allele — the child bursts past it (ancestor phenotype, absent from
			# both parents)
			var shared: Array = []
			for gene in INT_GENES:
				if a[gene] == b[gene]:
					shared.append(gene)
			var picked: String = rng.pick(shared) if shared.size() > 0 else rng.pick(INT_GENES)
			var bound: Dictionary = GenomeScript.GENE_BOUNDS[picked]
			var cur: float = float(child[picked])
			var value: Variant = _num(maxf(float(bound["min"]), minf(float(bound["max"]), cur + (2 if rng.chance(0.5) else -2))))
			child[picked] = value
			if info != null:
				info["anomaly"] = {"kind": kind, "gene": picked, "value": value}
		else:
			# dormant: sleeps until generation N (≥ +2 — never wakes before the
			# 3rd generation); a light cosmetic tilt shows from generation 1.
			# The allele value rides the info stamp only — the slot stays latent.
			var gene: String = rng.pick(INT_GENES)
			var bound: Dictionary = GenomeScript.GENE_BOUNDS[gene]
			var cur: float = float(child[gene])
			var value: Variant = _num(maxf(float(bound["min"]), minf(float(bound["max"]), cur + (1 if rng.chance(0.5) else -1))))
			var wake_gen: int = int(child["generation"]) + 2 + floori(rng.next() * 3.0)  # +2..+4
			child["hue"] = fmod(float(child["hue"]) + (14.0 if rng.chance(0.5) else -14.0) + 360.0, 360.0)
			if info != null:
				info["anomaly"] = {"kind": kind, "gene": gene, "value": value, "wakeGen": wake_gen}
	# M2 — ONE defect roll; defect_rate is the TOTAL budget, never added per kind
	if _truthy(opts.get("defectRate")) and rng.chance(float(opts["defectRate"])):
		var kind: String = rng.pick(["glass_bones", "frenzy", "famine"])
		if kind == "glass_bones":
			# half-strength allele: +1 to a speed gene — the visible tell
			var gene: String = rng.pick(["flagella", "legs"])
			var bound: Dictionary = GenomeScript.GENE_BOUNDS[gene]
			child[gene] = _num(minf(float(bound["max"]), float(child[gene]) + 1.0))
		if info != null:
			info["defect"] = {"kind": kind}


# JS truthiness for the optional gate fields (anomalyChance/defectRate/
# dietPull/coatPull): null, 0, NaN and "" are falsy — a 0 budget must skip the
# roll without burning RNG, exactly like the TS short-circuit.
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


# Collapse integral floats to int (mirrors genome.gd's _num): the splice table
# writes gene slots after the final clamp_genome, so it must canonicalize the
# same way to keep gene ints as ints.
static func _num(v: float) -> Variant:
	var i := floorf(v)
	return int(i) if v == i else v
