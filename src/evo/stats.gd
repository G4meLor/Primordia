## Derived stats from a genome. Pure math, heavily unit-tested.
## Port of Spore src/evo/stats.ts. CreatureStats is a Dictionary with snake_case
## keys: maxHp -> max_hp, swimSpeed -> swim_speed, contactDamage ->
## contact_damage, dashPower -> dash_power; the eight one-word names are
## unchanged. Expression order mirrors the TS source term for term — float64
## addition is not associative, and the genome_stats.json fixture pins the bits.
class_name Stats
extends RefCounted

## Brain level needed to trigger ascension to tribe.
const ASCENSION_BRAIN := 3


static func compute_cell_stats(g: Dictionary) -> Dictionary:
	var size_f: float = float(g.get("size", 1))
	return {
		"max_hp": 30 + size_f * 20 + float(g.get("spikes", 0)) * 2 + float(g.get("jaw", 0)) * 3,
		"speed": 60 + float(g.get("flagella", 0)) * 26 - (size_f - 1) * 18 + float(g.get("jet", 0)) * 6,
		"swim_speed": 60 + float(g.get("flagella", 0)) * 26 - (size_f - 1) * 18,
		"accel": 140 + float(g.get("cilia", 0)) * 90 + float(g.get("flagella", 0)) * 32 + float(g.get("jet", 0)) * 60,
		"damage": 4 + float(g.get("jaw", 0)) * 5 + size_f * 2,
		"contact_damage": float(g.get("spikes", 0)) * 3,
		"defense": minf(0.5, size_f * 0.08 + float(g.get("spikes", 0)) * 0.015),
		"charm": float(g.get("eyes", 0)) * 0.3,
		"vision": 1 + float(g.get("eyes", 0)) * 0.12,
		"toxin": float(g.get("toxin", 0)) * 4,
		"dash_power": float(g.get("jet", 0)),
		"gather": 1,
	}


static func compute_creature_stats(g: Dictionary) -> Dictionary:
	var size_f: float = float(g.get("size", 1))
	var legs_f: float = float(g.get("legs", 0))
	var wings_f: float = float(g.get("wings", 0))
	var coat: String = g.get("coat", "skin")
	var leg_speed: float = 24 if legs_f == 0 else 40 + minf(legs_f, 6) * 14  # no legs = worm
	var wing_bonus: float = (18 + wings_f * 8) if wings_f > 0 else 0
	var coat_def: float = 0
	if coat == "plates":
		coat_def = 0.18
	elif coat == "scales":
		coat_def = 0.1
	elif coat == "fur":
		coat_def = 0.04
	var coat_speed: float = -12 if coat == "plates" else 0
	return {
		"max_hp": 40 + size_f * 30 + float(g.get("spikes", 0)) * 2 + float(g.get("horns", 0)) * 4
				+ (15 if coat == "plates" else 0),
		# the legless worm baseline is exempt from the size penalty — a size-2.2
		# legless genome used to compute NEGATIVE speed: a frozen, silent trap
		"speed": maxf(8, leg_speed + wing_bonus + coat_speed
				- (0 if legs_f == 0 else maxf(0, size_f - 1) * 22)),
		"swim_speed": 30 + float(g.get("flagella", 0)) * 8,
		"accel": 300 + legs_f * 30,
		"damage": 5 + float(g.get("jaw", 0)) * 6 + float(g.get("horns", 0)) * 4 + size_f * 2,
		"contact_damage": float(g.get("spikes", 0)) * 2.5,
		"defense": minf(0.65, size_f * 0.06 + float(g.get("spikes", 0)) * 0.01 + coat_def),
		"charm": float(g.get("eyes", 0)) * 0.5 + float(g.get("arms", 0)) * 0.6
				+ (1.5 if g.get("pattern", "plain") == "glow" else 0)
				+ (1 if coat == "fur" else 0) + (1 if wings_f > 0 else 0)
				+ float(g.get("brain", 0)) * 0.4,
		"vision": 1 + float(g.get("eyes", 0)) * 0.15 + float(g.get("brain", 0)) * 0.05,
		"toxin": float(g.get("toxin", 0)) * 3,
		"dash_power": float(g.get("jet", 0)),
		"gather": 1 + float(g.get("arms", 0)) * 0.8,
	}


static func compute_stats(g: Dictionary, land: bool) -> Dictionary:
	return compute_creature_stats(g) if land else compute_cell_stats(g)


## Rough combat sim: returns true if attacker wins a straight fight vs defender.
static func would_win(attacker: Dictionary, defender: Dictionary) -> bool:
	var atk_time: float = float(defender["max_hp"]) \
			/ maxf(1, float(attacker["damage"]) * (1 - float(defender["defense"])))
	var def_time: float = float(attacker["max_hp"]) \
			/ maxf(1, float(defender["damage"]) * (1 - float(attacker["defense"])))
	return atk_time < def_time
