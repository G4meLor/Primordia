## Procedural species naming — faux-Latin + trait epithets. Deterministic
## per-seed so a species keeps its name across saves.
## Port of Spore src/evo/names.ts. The genome is a plain Dictionary (the
## established genome.gd port shape); rng is the rng.gd RefCounted, untyped
## here because a global class_name annotation would not resolve in `-s` mode
## on a fresh clone.
class_name Names
extends RefCounted

const PRE := ["Glor", "Zor", "Blor", "Kri", "Oog", "Wug", "Nim", "Phlor", "Yip", "Squib", "Mib", "Grub", "Snor", "Vex", "Plim", "Drok", "Fwip", "Quor", "Thal", "Nib", "Womp", "Zib", "Krunk", "Fee"]
const MID := ["ba", "glo", "ri", "na", "zo", "mo", "pli", "do", "ku", "wa", "si", "tra", "bo", "ni"]
const SUF := ["bus", "max", "on", "ix", "ath", "imus", "olops", "odon", "apus", "ex", "ung", "ora", "itto", "ax", "eep", "urp"]

# The TS EPITHETS table ({ test: (g) => bool, ep: string[] }) ports as named
# pools checked by the ordered if-chain in epithet() below — GDScript consts
# cannot hold test closures, and the chain preserves the table's membership
# order exactly, so rng consumption matches the TS filter+pick.
const EP_SPIKES := ["the Spiky", "the Pincushion", "Sharpbodied"]
const EP_TOXIN := ["the Toxic", "Venomsoul", "the Foul"]
const EP_EYES := ["Many-Eyed", "the Watchful", "Omniscient"]
const EP_WINGS := ["Windy", "Skytouched", "the Fluttering"]
const EP_HORNS := ["Crownhorned", "the Imposing", "Lancehead"]
const EP_BRAIN := ["the Thinker", "Deepmind", "the Curious"]
const EP_SIZE_BIG := ["the Colossal", "Mountainborn", "the Vast"]
const EP_SIZE_SMALL := ["the Tiny", "Pocket-sized", "the Skippable"]
const EP_CARNIVORE := ["the Ravenous", "Maneater", "the Hungry"]
const EP_HERBIVORE := ["the Gentle", "Leaflover", "the Placid"]
const EP_GLOW := ["the Radiant", "Starlit", "the Luminous"]
const EP_LEGS := ["the Skittering", "Many-legged", "the Busy"]

const TAILS := ["ington", "burger", "zor", "ini", "ax", "zilla", "puff"]

# R7 creature naming — the picker charset (A-Z a-z 0-9 space apostrophe dash,
# the EXACT ruled set as one const) and the cap. context.set_display_name
# filters/truncates through these; the editor's on-canvas grid renders them.
const NAME_CHARSET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 '-"
const NAME_MAX_LEN := 14


## The central name sanitizer: keep only NAME_CHARSET glyphs, strip edge
## whitespace, truncate to NAME_MAX_LEN (truncate-not-reject). An empty result
## means "not set" — the display sites fall back to the self_name suggestion.
static func sanitize_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var ch := raw[i]
		if NAME_CHARSET.contains(ch):
			out += ch
	out = out.strip_edges()
	return out.substr(0, NAME_MAX_LEN) if out.length() > NAME_MAX_LEN else out


static func species_name(rng) -> String:
	var n: String = rng.pick(PRE)
	var mid_count: int = rng.int(0, 2)
	for i in mid_count:
		n += rng.pick(MID)
	n += rng.pick(SUF)
	return n


static func epithet(g: Dictionary, rng) -> String:
	# TS: EPITHETS.filter((e) => e.test(g)) — same entries, same order.
	var matches: Array = []
	if float(g.get("spikes", 0)) >= 4: matches.append(EP_SPIKES)
	if float(g.get("toxin", 0)) >= 3: matches.append(EP_TOXIN)
	if float(g.get("eyes", 0)) >= 4: matches.append(EP_EYES)
	if float(g.get("wings", 0)) >= 1: matches.append(EP_WINGS)
	if float(g.get("horns", 0)) >= 3: matches.append(EP_HORNS)
	if float(g.get("brain", 0)) >= 3: matches.append(EP_BRAIN)
	if float(g.get("size", 0)) >= 1.7: matches.append(EP_SIZE_BIG)
	if float(g.get("size", 0)) <= 0.8: matches.append(EP_SIZE_SMALL)
	if g.get("diet", "") == "carnivore": matches.append(EP_CARNIVORE)
	if g.get("diet", "") == "herbivore": matches.append(EP_HERBIVORE)
	if g.get("pattern", "") == "glow": matches.append(EP_GLOW)
	if float(g.get("legs", 0)) >= 6: matches.append(EP_LEGS)
	if matches.is_empty():
		return ""
	return rng.pick(rng.pick(matches))


static func full_species_name(g: Dictionary, rng) -> String:
	var n := species_name(rng)
	var ep := epithet(g, rng)
	return "%s %s" % [n, ep] if not ep.is_empty() else n


## Silly self-naming for the player creature based on its own traits.
static func self_name(g: Dictionary) -> String:
	var bits := PackedStringArray()
	if g.get("diet", "") == "carnivore": bits.append("Fang")
	if g.get("diet", "") == "herbivore": bits.append("Leaf")
	if float(g.get("spikes", 0)) >= 3: bits.append("Spike")
	if float(g.get("eyes", 0)) >= 3: bits.append("Peep")
	if float(g.get("toxin", 0)) >= 2: bits.append("Stink")
	if float(g.get("wings", 0)) >= 1: bits.append("Flap")
	if float(g.get("horns", 0)) >= 2: bits.append("Horn")
	if float(g.get("brain", 0)) >= 3: bits.append("Brain")
	if bits.is_empty():
		# TS: undefined/NaN size compares false, so a missing size -> Squish
		bits.append("Chonk" if float(g.get("size", 0)) > 1.4 else "Squish")
	# JS Math.round rounds halves toward +infinity (Math.round(-2.5) = -2);
	# GDScript roundi() rounds halves away from zero, so port as floor(x+0.5).
	var idx := absi(floori(float(g.get("hue", 0)) * 7.0 + float(g.get("size", 0)) * 13.0 + 0.5)) \
			% TAILS.size()
	return "".join(bits) + TAILS[idx]
