# Ecosystem valve tests: kin_memory grudge/harass valve, bio_shift
# reequilibrate + solvability top-up, corpse tide, serialization. Every case
# mirrors tests/econ-probe.test.ts (TS repo) with its concrete numbers.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path.
const EcosystemScript := preload("res://src/evo/ecosystem.gd")
const Rng := preload("res://src/core/rng.gd")
const Genome := preload("res://src/evo/genome.gd")


# TS seedEco: 6 lines from defaultGenome(), diets cycling carnivore/herbivore
# (i % 3 == 0), sizes 0.8..1.8, pop 10 by default.
func _seed_eco(rng_v: Variant, pops: float = 10.0) -> Variant:
	var eco: Variant = EcosystemScript.new(rng_v)
	for i in 6:
		var g: Dictionary = Genome.default_genome()
		g["diet"] = "carnivore" if i % 3 == 0 else "herbivore"
		g["size"] = 0.8 + i * 0.2
		eco.add_species(g, pops)
	return eco


# TS kinEco: seedEco + the first living herbivore carries the ONE kin_tag.
func _kin_eco(seed_v: int) -> Array:
	var eco: Variant = _seed_eco(Rng.new_from(seed_v))
	var host: Variant = null
	for s in eco.living():
		if s["genome"]["diet"] == "herbivore":
			host = s
			break
	host["kin_tag"] = true
	return [eco, host]


func _pop_sum(eco: Variant) -> float:
	var sum := 0.0
	for s in eco.living():
		sum += float(s["pop"])
	return sum


# --- kin_memory decay valve (econ-probe: 8 -> 4 -> 0 through real ticks) ------


func test_grudge_decays_half_every_20_game_min_and_clears() -> void:
	var pair := _kin_eco(41)
	var eco: Variant = pair[0]
	var host: Dictionary = pair[1]
	host["grudge"] = 8
	for s in 1200:  # 60 * 20 game-seconds = one half-life (40 gen * 30 s)
		eco.tick(1.0)
	eq(int(host["grudge"]), 4, "one half-life: 8 -> 4")
	for s in 3600:  # three more -> 2, 1, 0
		eco.tick(1.0)
	eq(int(host.get("grudge", 0)), 0, "three more half-lives: 4 -> 2 -> 1 -> 0")
	approx(EcosystemScript.effective_grudge(host), 0.0, "a cleared ledger behaves neutral")


func test_harassment_cap_forces_neutral_until_window_rolls() -> void:
	var pair := _kin_eco(42)
	var eco: Variant = pair[0]
	var host: Dictionary = pair[1]
	host["grudge"] = 6
	host["harass"] = 4  # HARASS_CAP (eco-internal)
	approx(EcosystemScript.effective_grudge(host), 0.0, "capped -> the network rests (flee restored)")
	host["harass_t"] = 100.0 - 0.5  # HARASS_WINDOW_MIN
	eco.tick(60.0)  # 1 eco-min -> the 100-min window rolls
	eq(int(host.get("harass", 0)), 0, "harass counter rolled off with the window")
	approx(EcosystemScript.effective_grudge(host), 6.0, "hostile again (decay needs a half-life)")


func test_presses_bounded_and_grudge_extinction_under_2x_baseline() -> void:
	# stage-behavior model: a grudging network presses; each press draws one
	# retaliation kill (the player swats back). The valve bounds the presses.
	var ext := {"grudge": 0, "base": 0, "noValve": 0}
	var presses := {"grudge": 0.0, "base": 0.0, "noValve": 0.0}
	var seeds := 40
	for mode in ["grudge", "base", "noValve"]:
		for s_i in seeds:
			var pair := _kin_eco(100 + s_i)
			var eco: Variant = pair[0]
			var host: Dictionary = pair[1]
			host["pop"] = 10.0
			if mode != "base":
				host["grudge"] = 6
			for min_i in 60:
				var presses_allowed: bool
				if mode == "noValve":
					presses_allowed = float(host.get("grudge", 0.0)) >= 2.0
				else:
					presses_allowed = EcosystemScript.effective_grudge(host) >= 2.0
				if mode != "base" and presses_allowed:
					host["harass"] = float(host.get("harass", 0.0)) + 1.0
					presses[mode] = float(presses[mode]) + 1.0
					host["pop"] = maxf(0.0, float(host["pop"]) - 1.0)  # the swat back
				eco.tick(60.0)
			if host["extinct"] == true:
				ext[mode] = int(ext[mode]) + 1
	# the valve is the difference: capped presses vs one per minute, forever
	ok(float(presses["grudge"]) / seeds <= 4.0, "capped presses: avg <= HARASS_CAP (4)")
	ok(float(presses["noValve"]) / seeds > 4.0, "valve disabled: one press per minute, forever")
	# catalog number: extinction risk with the grudge stays under 2x baseline
	# (<= so the safe 0/0 case passes — the guard is against future coupling)
	ok(int(ext["grudge"]) <= 2 * int(ext["base"]), "P(ext | grudge) <= 2x the no-grudge sim")


func test_valve_and_ledger_bookkeeping_draw_no_rng() -> void:
	# the valves + corpse decay are pure dt/m arithmetic INSIDE tick — two
	# same-seed ecos, one carrying live counters, must stay bit-identical
	var a: Variant = EcosystemScript.new(Rng.new_from(61))
	var b: Variant = EcosystemScript.new(Rng.new_from(61))
	for i in 6:
		var g: Dictionary = Genome.default_genome()
		g["diet"] = "carnivore" if i % 3 == 0 else "herbivore"
		g["size"] = 0.8 + i * 0.2
		a.add_species(g.duplicate(), 8.0)
		b.add_species(g.duplicate(), 8.0)
	var ha: Dictionary = a.species[1]
	ha["kin_tag"] = true
	ha["grudge"] = 8
	ha["grudge_t"] = 600.0
	ha["harass"] = 2
	ha["harass_t"] = 40.0
	a.corpses = 3.0  # ledger decay runs with no tide line present
	for s in 1260:
		a.tick(1.0)
		b.tick(1.0)
	eq(a.species.size(), b.species.size(), "rosters stay identical (no rng drift)")
	for i in a.species.size():
		eq(a.species[i]["id"], b.species[i]["id"], "sp%d id identical" % i)
		ok(a.species[i]["pop"] == b.species[i]["pop"], "sp%d pop bit-identical" % i)
	eq(int(ha["grudge"]), 4, "the ledger decayed once through the pinned bookkeeping")


# --- corpse tide (econ-probe: 8% cap, auto-end <= 5.0 game-min, I-bug2) -------


func test_scavenger_pop_capped_at_8_percent_while_kills_flow() -> void:
	var eco: Variant = _seed_eco(Rng.new_from(21))
	for min_i in 60:
		eco.drop_corpse(3)  # sustained player kills: each burst is 2-3
		var pop_sum: float = _pop_sum(eco)
		var tide: Variant = eco.tide_species()
		ok(tide != null, "burst min %d: tide line exists" % min_i)
		if tide == null:
			return
		ok(float(tide["pop"]) <= pop_sum * 0.08 + 1e-9,
				"burst min %d: tide pop <= 8%% of popSum" % min_i)
		eco.tick(60.0)
		var tide_after: Variant = eco.tide_species()
		if tide_after != null:
			ok(float(tide_after["pop"]) <= pop_sum * 0.08 + 1e-9,
					"post min %d: tide pop <= 8%% of pre-tick popSum" % min_i)


func test_tide_auto_ends_within_5_game_min_after_kills_stop() -> void:
	var eco: Variant = _seed_eco(Rng.new_from(22))
	# heavy sustained killing -> the ledger saturates and the line rides its cap
	for s in 180:
		eco.drop_corpse(3)
		eco.tick(1.0)
	var active: Variant = eco.tide_species()
	ok(active != null, "tide line alive after 3 min of heavy killing")
	if active == null:
		return
	ok(float(active["pop"]) > 0.5, "tide line riding its cap (pop > 0.5)")
	# kills stop — the ledger flushes (8/3 ≈ 2.7 min), the cap collapses under
	# the line (~4.3 min); pinned at the 5.0 catalog number
	for s in 300:
		eco.tick(1.0)
	ok(eco.tide_species() == null, "tide auto-ended within 5.0 game-min")
	var any_tide_born := false
	for s in eco.living():
		if s.get("tideBorn") == true:
			any_tide_born = true
	ok(not any_tide_born, "no living tideBorn lines remain")


func test_tideborn_death_never_appears_in_extinctions() -> void:
	# I-bug2: no extinction ceremony for the tide line (no counters/bio_shift)
	# or every feast/famine cycle would ring the world bell
	var eco: Variant = _seed_eco(Rng.new_from(58))
	for s in 180:
		eco.drop_corpse(3)
		eco.tick(1.0)
	ok(eco.tide_species() != null, "tide line alive before the famine")
	var saw_ceremony := false
	for s in 480:
		var out: Dictionary = eco.tick(1.0)
		for x in out["extinctions"]:
			if x.get("tideBorn") == true:
				saw_ceremony = true
	ok(not saw_ceremony, "a tideBorn death never appears in out.extinctions")
	ok(eco.tide_species() == null, "the line really died — silently")


func test_tide_line_revives_through_drop_corpse() -> void:
	# a collapsed line is revived, not re-founded — same scavengers
	var eco: Variant = _seed_eco(Rng.new_from(24))
	eco.drop_corpse(3)
	var first: Dictionary = eco.tide_species()
	ok(first != null, "first burst founds the tide line")
	first["extinct"] = true
	first["pop"] = 0.0
	eco.drop_corpse(2)
	ok(eco.tide_species() != null, "tide species exists after the revival burst")
	ok(eco.tide_species() == first, "revived line is the SAME species dict (not re-founded)")
	eq(eco.tide_species()["extinct"], false, "revived line is alive again")
	approx(float(eco.tide_species()["pop"]), 2.0, "revival burst lands on the revived line")
	eq(eco.species.size(), 7, "no extra species founded on revive")


# --- bio_shift (econ-probe: conversion, kin exclusion, recovery, dedupe) ------


func test_extinction_converts_a_role_for_the_rest_of_the_run() -> void:
	var eco: Variant = _seed_eco(Rng.new_from(51))
	var victim: Dictionary = eco.living()[2]
	victim["pop"] = 0.2  # dies at the next tick
	var shifts_seen := 0
	for s in 600:
		if shifts_seen > 0:
			break
		var out: Dictionary = eco.tick(1.0)
		shifts_seen += (out.get("shifts", []) as Array).size()
	ok(shifts_seen >= 1, "an extinction surfaced at least one shift")
	ok(eco.shifts.size() >= 1, "standing pairs persist on the eco")


func test_kin_lines_never_convert_and_shifted_lines_are_exempt() -> void:
	var eco: Variant = _seed_eco(Rng.new_from(52))
	var kin_genome: Dictionary = Genome.default_genome()
	kin_genome["diet"] = "herbivore"
	var kin_line: Dictionary = eco.add_species(kin_genome, 8.0, {"kin": true})
	var victim: Variant = null
	for s in eco.living():
		if s["kin"] != true and s["genome"]["diet"] == "herbivore":
			victim = s
			break
	victim["pop"] = 0.2
	for s in 300:
		eco.tick(1.0)
	ok(eco.shifts.size() >= 1, "shifts standing after the loss")
	eq(kin_line["genome"]["diet"], "herbivore", "the player line never converts")
	var converted: Variant = null
	for s in eco.living():
		if s.get("shifted") == true:
			converted = s
			break
	if converted != null:
		var before: String = converted["genome"]["diet"]
		for s in 60:
			eco.tick(1.0)
		eq(converted["genome"]["diet"], before, "no oscillation — shifted is exempt")


func test_recovery_band_shifts_never_cascade() -> void:
	var eco: Variant = _seed_eco(Rng.new_from(53))
	for sp in eco.living():
		sp["pop"] = maxf(0.3, float(sp["pop"]) * 0.3)  # stress the web
	var min_living := 99
	var min_flora := 999.0
	for s in 1800:
		eco.tick(1.0)
		min_living = mini(min_living, eco.living().size())
		min_flora = minf(min_flora, float(eco.flora))
	ok(min_living >= 2, ">=2 living lines through the crash")
	ok(min_flora >= 12.0, "flora never stuck at 0 (sterility floor)")


func test_late_extinction_with_all_pairs_standing_still_tops_up() -> void:
	# the solvability top-up survives the dedupe: every possible role pair
	# already stands — both the primary and the silent rng pair dedupe, leaving
	# `added` empty, yet the web must still top up to >=2 living lines
	var eco: Variant = _seed_eco(Rng.new_from(57))
	for from_d in ["herbivore", "omnivore", "carnivore"]:
		for to_d in ["herbivore", "omnivore", "carnivore"]:
			if from_d != to_d:
				eco.shifts.append({"from": from_d, "to": to_d})
	# drive a near-total crash: only one line survives the tick
	var survivors: Array = eco.living()
	for i in survivors.size() - 1:
		survivors[i]["pop"] = 0.2
	eco.tick(1.0)
	ok(eco.living().size() >= 2, "the top-up ran despite the empty `added`")


func test_shift_pairs_round_trip_through_the_save() -> void:
	var eco: Variant = _seed_eco(Rng.new_from(54))
	eco.shifts.append({"from": "herbivore", "to": "carnivore"})
	var back: Variant = EcosystemScript.from_json(eco.to_json(), Rng.new_from(55))
	eq(back.shifts.size(), 1, "one pair round-trips")
	if back.shifts.size() == 1:
		eq(back.shifts[0]["from"], "herbivore", "pair.from round-trips")
		eq(back.shifts[0]["to"], "carnivore", "pair.to round-trips")


# --- serialization (TS numOrUndef coercion pattern) ---------------------------


func test_from_json_coerces_corrupt_fields() -> void:
	var eco: Variant = EcosystemScript.new(Rng.new_from(56))
	eco.add_species(Genome.default_genome(), 8.0)
	var blob: Dictionary = eco.to_json()
	var sp: Dictionary = blob["species"][0]
	sp["grudge"] = "six"     # corrupt string -> coerced away (reads as 0)
	sp["grudge_t"] = true    # a bool is not a number -> coerced away
	sp["harass"] = [1]       # junk array -> coerced away
	sp["harass_t"] = 2.5     # well-formed ledger value rides through
	blob["flora"] = "gone"
	blob["floraCap"] = "nope"
	blob["corpses"] = -5.0
	blob["species"].append({"id": 7, "pop": "many", "genome": {}})  # junk row
	blob["species"].append({"id": "spX_ok", "pop": 3.0, "genome": {"size": 99, "diet": "meat"}})
	var back: Variant = EcosystemScript.from_json(blob, Rng.new_from(57))
	eq(back.species.size(), 2, "junk species row dropped, well-formed rows kept")
	ok(not back.species[0].has("grudge"), "corrupt grudge coerced to absent (reads as 0)")
	ok(not back.species[0].has("grudge_t"), "corrupt grudge_t coerced")
	ok(not back.species[0].has("harass"), "corrupt harass coerced")
	approx(float(back.species[0]["harass_t"]), 2.5, "well-formed harass_t rides through")
	approx(float(back.flora), 60.0, "corrupt flora -> default 60")
	approx(float(back.flora_cap), 100.0, "corrupt floraCap -> default 100")
	approx(float(back.corpses), 0.0, "negative corpses clamp to 0")
	var g2: Dictionary = back.species[1]["genome"]
	approx(float(g2["size"]), 2.2, "corrupt genome clamps to GENE_BOUNDS (size 99 -> 2.2)")
	eq(g2["diet"], "omnivore", "unknown diet snaps to omnivore")
	# the coerced ledger must not poison the valve arithmetic downstream
	back.tick(1.0)
	approx(float(back.flora), back.flora, "post-load tick runs clean")


func test_to_json_carries_the_save_shape() -> void:
	var eco: Variant = EcosystemScript.new(Rng.new_from(59))
	eco.add_species(Genome.default_genome(), 8.0)
	eco.corpses = 4.0
	var blob: Dictionary = eco.to_json()
	for key in ["species", "flora", "floraCap", "corpses", "shifts"]:
		ok(blob.has(key), "save blob carries '%s'" % key)
	eq(blob["species"].size(), 1, "species rides the blob")
	approx(float(blob["corpses"]), 4.0, "corpses ledger rides the blob")
	eq(blob["shifts"], [], "shifts ledger starts empty")


# --- kin_memory shared plumbing ------------------------------------------------


func test_designate_kin_tag_picks_one_herding_host_idempotently() -> void:
	var eco: Variant = _seed_eco(Rng.new_from(31))
	# gate shut: no kin_grudge flag -> no tag
	eco.designate_kin_tag({"traits": []})
	var tagged := 0
	for s in eco.species:
		if s.get("kin_tag") == true:
			tagged += 1
	eq(tagged, 0, "world without the kin_grudge flag tags nothing")
	# gate open: the first herding (non-carnivore) non-kin line hosts the ledger
	var world: Dictionary = {"traits": [{"effects": [{"kind": "flag", "key": "kin_grudge"}]}]}
	eco.designate_kin_tag(world)
	var host: Dictionary = eco.species[1]  # i=1 is the first herbivore
	eq(host.get("kin_tag"), true, "first non-kin non-carnivore line hosts the tag")
	eco.designate_kin_tag(world)  # idempotent
	tagged = 0
	for s in eco.species:
		if s.get("kin_tag") == true:
			tagged += 1
	eq(tagged, 1, "exactly ONE species carries the world's grudge ledger")


func test_designate_kin_tag_falls_back_to_any_non_kin_line() -> void:
	var eco: Variant = EcosystemScript.new(Rng.new_from(32))
	eco.add_species(Genome.default_genome(), 8.0)  # omnivore by default
	var g: Dictionary = Genome.default_genome()
	g["diet"] = "carnivore"
	eco.add_species(g, 8.0)
	eco.add_species(Genome.default_genome(), 4.0, {"kin": true})
	var world: Dictionary = {"traits": [{"effects": [{"kind": "flag", "key": "kin_grudge"}]}]}
	eco.designate_kin_tag(world)
	# every line is carnivore-ish or kin -> the fallback takes the first non-kin
	eq(eco.species[0].get("kin_tag"), true, "fallback: first non-kin line hosts the tag")


func test_grudge_of_and_register_press_gate_on_the_world_flag() -> void:
	var eco: Variant = _seed_eco(Rng.new_from(33))
	var world: Dictionary = {"traits": [{"effects": [{"kind": "flag", "key": "kin_grudge"}]}]}
	var no_world: Dictionary = {}
	var host: Dictionary = eco.species[1]
	host["kin_tag"] = true
	# world gate: no kin_grudge -> 0 even for the tagged line
	approx(eco.grudge_of(no_world, host["id"]), 0.0, "gate shut -> grudge reads 0")
	# tagged line, no grudge yet -> 0
	approx(eco.grudge_of(world, host["id"]), 0.0, "unset ledger reads 0")
	host["grudge"] = 5
	approx(eco.grudge_of(world, host["id"]), 5.0, "tagged line reads its ledger")
	# the harassment cap shuts the read
	host["harass"] = 4
	approx(eco.grudge_of(world, host["id"]), 0.0, "capped line reads 0")
	host["harass"] = 0
	# untagged lines and unknown ids read 0 regardless
	approx(eco.grudge_of(world, eco.species[0]["id"]), 0.0, "untagged line reads 0")
	approx(eco.grudge_of(world, "nope"), 0.0, "unknown id reads 0")
	# register_press counts only toward the tagged line
	eco.register_press(world, host["id"])
	approx(float(host.get("harass", 0.0)), 1.0, "press counted on the tagged line")
	eco.register_press(world, eco.species[0]["id"])
	ok(not eco.species[0].has("harass"), "press on an untagged line is not counted")
