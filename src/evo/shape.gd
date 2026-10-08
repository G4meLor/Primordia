## R12 heredity ledger — the body-plan classifier: a genome snaps to one of
## three SHAPES at each stage exit (game.gd's switch seam) and the consumers
## read the LATEST snapshot off the context. Pure statics (the genome.gd
## convention — the genome is a plain Dictionary, the module holds the math).
## Controller ruling (binding): predator = jaw + spikes + size_rank; minder =
## eyes + arms + brain; wall = coat + horns; highest score wins, tie →
## predator.
class_name Shape
extends RefCounted

const GenomeScript := preload("res://src/evo/genome.gd")

## The three shapes, the tie-break champion first (membership guard on the
## save wire and the card line reads).
const SHAPES := ["predator", "minder", "wall"]

## The display names — raw EN keys translated AT DRAW (the R10/R12 i18n
## ruling); an unknown/absent shape names nothing.
const TRAIT_NAMES := {
	"predator": "Predator-line",
	"minder": "Minder-line",
	"wall": "Wall-line",
}


## The size gene normalized against its GENE_BOUNDS into 0..2 (the ruling's
## size_rank): bound min → 0, bound max → 2, out-of-range clamps.
static func size_rank(g: Dictionary) -> float:
	var b: Dictionary = GenomeScript.GENE_BOUNDS["size"]
	var v := clampf(float(g.get("size", 1.0)), float(b["min"]), float(b["max"]))
	return (v - float(b["min"])) / (float(b["max"]) - float(b["min"])) * 2.0


## The coat gene is categorical — its score IS the COATS defense progression
## (skin 0 → fur 1 → scales 2 → plates 3); garbage/missing reads 0.
static func coat_score(g: Dictionary) -> int:
	return maxi(GenomeScript.COATS.find(String(g.get("coat", ""))), 0)


## The classifier. Runs on clamped genomes in practice (the context clamps on
## every load/merge), but reads defensively: a missing gene scores 0 — except
## size, whose 1.0 fallback is the default body. The numeric genes are levels
## (ints); the scores stay float only because size_rank is fractional.
static func shape_of(g: Dictionary) -> String:
	var predator := float(g.get("jaw", 0)) + float(g.get("spikes", 0)) + size_rank(g)
	var minder := float(g.get("eyes", 0)) + float(g.get("arms", 0)) + float(g.get("brain", 0))
	var wall := float(coat_score(g)) + float(g.get("horns", 0))
	# highest wins; ANY tie for the top → predator (the ruling's default —
	# predator >= the field covers its own ties, the m==w tie falls through)
	if predator >= minder and predator >= wall:
		return "predator"
	if minder > wall:
		return "minder"
	if wall > minder:
		return "wall"
	return "predator"


## The trait display name (raw EN key — the draw translates); empty for an
## unknown/absent shape so consumers can honestly draw nothing.
static func trait_name(shape_v: String) -> String:
	return String(TRAIT_NAMES.get(shape_v, ""))
