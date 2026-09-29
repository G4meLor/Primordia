## The genome is the single source of truth for what a creature IS, carried
## across all five stages (genetic memory). Genes are small integers (levels)
## plus a few floats/categoricals; bounds live here for mutation + editor.
## Port of Spore src/evo/genome.ts: the Genome is a plain Dictionary (string
## keys, the 22 TS interface fields) and Genome holds only static funcs.
class_name Genome
extends RefCounted

# TS has string-literal union types; GDScript validates enums by membership.
const DIETS := ["herbivore", "carnivore", "omnivore"]
const PATTERNS := ["plain", "spots", "stripes", "glow"]
const COATS := ["skin", "fur", "scales", "plates"]

# Read-only template — default_genome() hands out a fresh duplicate per call
# (the TS arrow function returns a new object literal each time, and callers
# mutate their copy).
const _DEFAULTS := {
	"size": 1, "diet": "omnivore", "hue": 120, "sat": 0.55, "pattern": "plain",
	"flagella": 2, "cilia": 0, "spikes": 0, "jaw": 1, "toxin": 0, "proboscis": 0,
	"electro": 0, "jet": 0, "legs": 0, "arms": 0, "eyes": 1, "horns": 0,
	"tail": false, "wings": 0, "brain": 0, "coat": "skin", "generation": 1
}

# Bound metadata used by mutation + editor to clamp values.
const GENE_BOUNDS := {
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


static func default_genome() -> Dictionary:
	return _DEFAULTS.duplicate()


static func gene_bounds() -> Dictionary:
	return GENE_BOUNDS


static func clamp_genome(g: Dictionary) -> Dictionary:
	var out: Dictionary = g.duplicate()  # TS {...g}; genome is flat, so shallow == deep
	for key in GENE_BOUNDS:
		var b: Dictionary = GENE_BOUNDS[key]
		var v: Variant = out.get(key)
		# non-numeric garbage (corrupt saves) snaps to a sane default
		if not (v is float or v is int) or not is_finite(v):
			out[key] = 1 if (key == "size" or key == "eyes") else 0
			continue
		out[key] = _num(maxf(b["min"], minf(b["max"], float(v))))
	# hue/sat are not bound-clamped: non-finite snaps, then hue wraps into
	# [0, 360) and sat clamps into [0.05, 1].
	var hue: Variant = out.get("hue")
	if not (hue is float or hue is int) or not is_finite(hue):
		hue = 120
	# GDScript's % operator is int-only (float % float is a parse error), so the
	# TS double-mod wrap ports via fmod, which keeps the dividend's sign like JS %.
	out["hue"] = _num(fmod(fmod(float(hue), 360.0) + 360.0, 360.0))
	var sat: Variant = out.get("sat")
	if not (sat is float or sat is int) or not is_finite(sat):
		sat = 0.55
	out["sat"] = _num(maxf(0.05, minf(1.0, float(sat))))
	if not DIETS.has(out.get("diet")):
		out["diet"] = "omnivore"
	if not PATTERNS.has(out.get("pattern")):
		out["pattern"] = "plain"
	if not COATS.has(out.get("coat")):
		out["coat"] = "skin"
	return out


## Deep copy (the genome is flat, so duplicate() matches the TS {...g} spread).
static func clone_genome(g: Dictionary) -> Dictionary:
	return g.duplicate()


## Cheap fingerprint used for dedup in bestiary / breeding. Joins the same 21
## TS fields with "-"; generation is intentionally excluded.
## On missing/garbage fields TS would render "NaN"/"undefined" — unreachable in
## practice (hash runs on clamped genomes); GDScript falls back via .get()
## because direct indexing would crash instead.
static func genome_hash(g: Dictionary) -> String:
	var parts := [
		roundi(float(g.get("size", 0)) * 10.0), g.get("diet", ""),
		roundi(float(g.get("hue", 0)) / 15.0), roundi(float(g.get("sat", 0)) * 10.0),
		g.get("pattern", ""),
		g.get("flagella", 0), g.get("cilia", 0), g.get("spikes", 0), g.get("jaw", 0),
		g.get("toxin", 0), g.get("proboscis", 0), g.get("electro", 0), g.get("jet", 0),
		g.get("legs", 0), g.get("arms", 0), g.get("eyes", 0), g.get("horns", 0),
		1 if g.get("tail", false) else 0, g.get("wings", 0), g.get("brain", 0),
		g.get("coat", "")
	]
	var strs := PackedStringArray()
	for p in parts:
		strs.append(str(p))
	return "-".join(strs)


# TS numbers don't distinguish int/float, but a GDScript JSON round-trip does
# ("2" vs "2.0"). Genome numbers are integer-valued in practice, so collapse
# integral floats to int and keep clamped genomes canonical.
static func _num(v: float) -> Variant:
	var i := floorf(v)
	return int(i) if v == i else v
