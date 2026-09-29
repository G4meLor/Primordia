# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path — a bare global name (Stats,
# Fixtures) would not resolve without the editor's class cache.
const Stats := preload("res://src/evo/stats.gd")
const Fixtures := preload("res://tests/fixtures.gd")

# The fixture stores stats under the TS CreatureStats names (camelCase); the
# port keeps TS semantics under snake_case keys. KEY_MAP covers every renamed
# field — the remaining eight (speed, accel, damage, defense, charm, vision,
# toxin, gather) are already one word and map to themselves.
const KEY_MAP := {
	"maxHp": "max_hp",
	"swimSpeed": "swim_speed",
	"contactDamage": "contact_damage",
	"dashPower": "dash_power",
}


func _fixture_key(k: String) -> String:
	return KEY_MAP.get(k, k)


func test_fixture_cell_and_creature_stats() -> void:
	var data := Fixtures.load_json("genome_stats")
	ok(not data.is_empty(), "fixture genome_stats.json loads")
	var genomes: Dictionary = data.get("genomes", {})
	eq(genomes.size(), 8, "fixture pins 8 genomes")
	for key in genomes.keys():
		var entry: Dictionary = genomes[key]
		var g: Dictionary = entry["genome"]
		for mode in [["cell", false], ["creature", true]]:
			var want: Dictionary = entry[mode[0]]
			eq(want.size(), 12, "fixture %s block has the 12 TS stat fields" % mode[0])
			var got: Dictionary = Stats.compute_stats(g, mode[1])
			eq(got.size(), 12, "computed stats dict has exactly 12 fields")
			for fk in want.keys():
				var mk: String = _fixture_key(fk)
				ok(got.has(mk), "%s: stats key for fixture '%s' -> '%s'"
						% [entry.get("name", "?"), fk, mk])
				if got.has(mk):
					# eps 1e-9, never 0.0: fixture floats carry <=1 ulp parse noise
					approx(float(got[mk]), float(want[fk]), "%s %s.%s"
							% [entry.get("name", "?"), mode[0], fk])


func test_compute_stats_dispatch() -> void:
	var data := Fixtures.load_json("genome_stats")
	var genomes: Dictionary = data.get("genomes", {})
	var g: Dictionary = genomes["10-omnivore-8-6-plain-2-0-0-1-0-0-0-0-0-0-1-0-0-0-0-skin"]["genome"]
	eq(Stats.compute_stats(g, false), Stats.compute_cell_stats(g), "compute_stats(g, false) == cell")
	eq(Stats.compute_stats(g, true), Stats.compute_creature_stats(g), "compute_stats(g, true) == creature")


func test_legless_speed_exemption() -> void:
	# fixture genome "legless-2.2": size 2.2, legs 0. The legless worm baseline is
	# exempt from the size penalty — without the exemption the speed term would be
	# max(8, 24 - (2.2 - 1) * 22) = max(8, -2.4) = 8; the fixture pins 24 instead.
	var data := Fixtures.load_json("genome_stats")
	var genomes: Dictionary = data.get("genomes", {})
	var entry: Dictionary = genomes["22-omnivore-8-6-plain-4-0-0-3-0-0-0-2-0-0-1-0-0-0-0-skin"]
	eq(entry.get("name"), "legless-2.2", "fixture entry is the legless case")
	var g: Dictionary = entry["genome"]
	eq(float(g["size"]), 2.2, "size 2.2 (the case that used to go NEGATIVE)")
	eq(int(g["legs"]), 0, "legs 0")
	var s: Dictionary = Stats.compute_creature_stats(g)
	approx(float(s["speed"]), float(entry["creature"]["speed"]), "legless speed pins the fixture value")
	approx(float(s["speed"]), 24.0, "legless worm baseline 24, not the size-penalized 8")


func test_would_win() -> void:
	var strong := {"max_hp": 100.0, "damage": 10.0, "defense": 0.0}
	var weak := {"max_hp": 50.0, "damage": 5.0, "defense": 0.0}
	# atkTime = 50/10 = 5 < defTime = 100/5 = 20 -> attacker wins
	ok(Stats.would_win(strong, weak), "stronger attacker wins")
	ok(not Stats.would_win(weak, strong), "weaker attacker loses")
	# mirrored stats -> atkTime == defTime -> strict < says no win
	ok(not Stats.would_win(strong, strong), "equal stats: strict < returns false")
	# defender defense 0.5 halves the attacker's effective dps and flips the fight:
	# without it atkTime = 50/10 = 5 < 10 -> win; with it 50/5 = 10, not < 10 -> loss
	var hard := {"max_hp": 50.0, "damage": 10.0, "defense": 0.5}
	var soft := {"max_hp": 50.0, "damage": 10.0, "defense": 0.0}
	ok(Stats.would_win(strong, soft), "undefended defender loses")
	ok(not Stats.would_win(strong, hard), "0.5 defense flips the outcome")


func test_ascension_brain_const() -> void:
	eq(Stats.ASCENSION_BRAIN, 3, "ASCENSION_BRAIN = 3")
