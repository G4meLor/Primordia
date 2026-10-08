# R14 — civ attaches to the world: the trait-gated chaos deck (acid monsoon /
# famine / moon cult), the ecoHealth start-output stack (creature-exit
# snapshot → civ start output), the pacifist + eco-collapsed bots and the
# tribe-fall DNA floor.
# Sources: the R14 spec row (experience-redesign-design.md :112) + the task-15
# brief's binding values (output = 10 + conduct ±2 + roundi(eco·12), cap 22 —
# the preflight ruling supersedes the spec sketch's 8 + round(·4); famine
# pauses the output regen for EXACTLY its 20 s active span, eps 1e-9; acid
# monsoon drains city hp only after the warn phase — the chaos law).
# Fold-twice law: every gate asserts presence with the trait AND absence
# without it (two seeded worlds per trait, the test_civ_events synthetic-world
# shape — a real derive draws 4-6 traits, tests pin exact decks).
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const CivEvents := preload("res://src/game/civ/civ_events.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")
const BotAttach := preload("res://tests/bots/bot_civ_attach.gd")

const DT := 1.0 / 60.0
const SEED := 0xC1DE

# Synthetic worlds (the test_civ_events shape: temperament set explicitly so
# mirror_bucket never surprises; the R14 trait dicts carry their CATALOG ids —
# has_trait reads t.id, the flag effects stay for the cell-deck consumers).
const W_TRAITLESS := {"seed": 51, "traits": [], "turns": [], "firedTurns": {},
		"revealed": {}, "comboFired": {}, "timers": {}, "temperament": "lean"}
const W_TOXIN := {"seed": 52, "traits": [{"id": "toxin_sea", "effects": [
		{"kind": "flag", "key": "toxin_rain_cell", "value": true}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
const W_HUNGRY := {"seed": 53, "traits": [{"id": "hungry_bloom", "effects": [
		{"kind": "num", "key": "herb_drain_mult", "value": 1.6}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
const W_MOON := {"seed": 54, "traits": [{"id": "mutation_moon", "effects": [
		{"kind": "num", "key": "mutation_rate_add", "value": 0.15},
		{"kind": "flag", "key": "wild_mutations", "value": true}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
const W_ALL_R14 := {"seed": 55, "traits": [
		{"id": "toxin_sea", "effects": [{"kind": "flag", "key": "toxin_rain_cell", "value": true}]},
		{"id": "hungry_bloom", "effects": [{"kind": "num", "key": "herb_drain_mult", "value": 1.6}]},
		{"id": "mutation_moon", "effects": [{"kind": "flag", "key": "wild_mutations", "value": true}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}

const BASELINE_IDS := ["quake", "rebellion", "goldenage", "worldwar"]


# The test_civ_sim harness shape: real context, the stage rng branch,
# recording hooks.
func _mk_sim(world: Dictionary = W_TRAITLESS, seed_v: int = SEED,
		eco_health: Variant = null, profile: Array = []) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.difficulty = "normal"
	ctx.world = world.duplicate(true)
	ctx.karma_by_stage = profile
	if eco_health != null:
		ctx.flags["ecoHealth"] = eco_health
	var rec: Dictionary = {"toasts": [], "banners": [], "audio": [], "floats": []}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CivSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _inp(keys: Array = []) -> Dictionary:
	return {"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": keys}


func _deck_ids(world: Dictionary) -> Array:
	var out: Array = []
	for d in CivEvents.make_civ_chaos_events(world):
		out.append(String(d["id"]))
	return out


func _has_id(ids: Array, id: String) -> bool:
	return ids.has(id)


# ---- the fold gates (fold twice: presence WITH the trait, absence WITHOUT) ----

func test_fold_trait_gates() -> void:
	# a traitless world folds to EXACTLY the TS baseline (the parity pin holds)
	var none := _deck_ids(W_TRAITLESS)
	for id in BASELINE_IDS:
		ok(_has_id(none, id), "traitless deck keeps %s" % id)
	ok(not _has_id(none, "acid_monsoon"), "traitless deck: no acid_monsoon")
	ok(not _has_id(none, "famine"), "traitless deck: no famine")
	ok(not _has_id(none, "moon_cult"), "traitless deck: no moon_cult")
	# each trait lights EXACTLY its own event (fold twice per trait)
	var tox := _deck_ids(W_TOXIN)
	ok(_has_id(tox, "acid_monsoon"), "toxin_sea world folds acid_monsoon")
	ok(not _has_id(tox, "famine"), "toxin_sea world: famine still gated shut")
	ok(not _has_id(tox, "moon_cult"), "toxin_sea world: moon_cult still gated shut")
	var hun := _deck_ids(W_HUNGRY)
	ok(_has_id(hun, "famine"), "hungry_bloom world folds famine")
	ok(not _has_id(hun, "acid_monsoon"), "hungry_bloom world: acid_monsoon gated shut")
	ok(not _has_id(hun, "moon_cult"), "hungry_bloom world: moon_cult gated shut")
	var moon := _deck_ids(W_MOON)
	ok(_has_id(moon, "moon_cult"), "mutation_moon world folds moon_cult")
	ok(not _has_id(moon, "acid_monsoon"), "mutation_moon world: acid_monsoon gated shut")
	ok(not _has_id(moon, "famine"), "mutation_moon world: famine gated shut")
	# all three together: the full 7-def deck
	var all_ids := _deck_ids(W_ALL_R14)
	for id in ["quake", "rebellion", "goldenage", "worldwar",
			"acid_monsoon", "famine", "moon_cult"]:
		ok(_has_id(all_ids, id), "all-traits deck carries %s" % id)
	eq(all_ids.size(), 7, "the all-traits deck is exactly the 7 defs")


func test_folded_events_carry_warn_and_scheduler_shape() -> void:
	# chaos law: every warned def rides the warn→apply(+tick)→end struct — the
	# monsoon warns FIRST and ticks its drain; famine warns and rides its
	# 20 s duration; the cult is an instant burst (the quake/rebellion shape)
	var deck: Array = CivEvents.make_civ_chaos_events(W_ALL_R14)
	var by_id := {}
	for d in deck:
		by_id[String(d["id"])] = d
	var mon: Dictionary = by_id["acid_monsoon"]
	ok(mon.get("warn") != null and not String(mon["warn"]).is_empty(),
			"acid_monsoon carries a warn phase")
	ok(mon.get("tick") is Callable, "acid_monsoon drains through a tick fn")
	eq(mon["duration"], [6.0, 6.0], "acid monsoon drains over ~6 s")
	var fam: Dictionary = by_id["famine"]
	ok(fam.get("warn") != null and not String(fam["warn"]).is_empty(),
			"famine carries a warn phase")
	eq(fam["duration"], [20.0, 20.0], "famine's pause IS its 20 s duration")
	var cult: Dictionary = by_id["moon_cult"]
	ok(not (cult.get("tick") is Callable), "moon cult has no tick — the burst is once")
	for id in ["acid_monsoon", "famine", "moon_cult"]:
		ok(by_id[id].get("apply") is Callable, "%s carries an apply fn" % id)
		ok(float(by_id[id]["weight"].call({"chaos": 0.5, "karma": 0.0})) > 0.0,
				"%s weight is live when folded in" % id)


# ---- the ecoHealth start-output stack -----------------------------------------

func test_eco_output_formula_pins() -> void:
	# the brief's pins: eco 0 → 10, 0.5 → 16, 1.0 → 22 cap (neutral conduct)
	var m0: Dictionary = _mk_sim(W_TRAITLESS, SEED, 0.0)
	m0["sim"].on_enter()
	approx(float(m0["sim"].output), 10.0, "ecoHealth 0 → start output 10", 1e-9)
	var m5: Dictionary = _mk_sim(W_TRAITLESS, SEED, 0.5)
	m5["sim"].on_enter()
	approx(float(m5["sim"].output), 16.0, "ecoHealth 0.5 → start output 16", 1e-9)
	var m1: Dictionary = _mk_sim(W_TRAITLESS, SEED, 1.0)
	m1["sim"].on_enter()
	approx(float(m1["sim"].output), 22.0, "ecoHealth 1.0 → start output 22", 1e-9)
	# out-of-band snapshots clamp (a bonus-species web reads full health; a
	# negative/corrupt read cannot push output past the cap)
	var m2: Dictionary = _mk_sim(W_TRAITLESS, SEED, 1.5)
	m2["sim"].on_enter()
	approx(float(m2["sim"].output), 22.0, "ecoHealth 1.5 clamps to the cap", 1e-9)
	var m3: Dictionary = _mk_sim(W_TRAITLESS, SEED, -0.4)
	m3["sim"].on_enter()
	approx(float(m3["sim"].output), 10.0, "ecoHealth −0.4 clamps to 0", 1e-9)


func test_eco_output_stacks_conduct_then_caps() -> void:
	# the cap is the ceiling of the SUM (the preflight ruling): conduct +2 and
	# eco 1.0 would sum 24 — the cap holds 22; eco 0.5 + conduct +2 sums 18
	var m: Dictionary = _mk_sim(W_TRAITLESS, SEED, 1.0, [0.2, 0.2, 0.2, 0.2])
	m["sim"].on_enter()
	approx(float(m["sim"].output), 22.0, "conduct +2 + eco 12 sums 24 → capped 22", 1e-9)
	var m2: Dictionary = _mk_sim(W_TRAITLESS, SEED, 0.5, [0.2, 0.2, 0.2, 0.2])
	m2["sim"].on_enter()
	approx(float(m2["sim"].output), 18.0, "conduct +2 + eco 6 → 18 (under the cap)", 1e-9)
	var m3: Dictionary = _mk_sim(W_TRAITLESS, SEED, 0.0, [-0.2, -0.2, -0.2, -0.2])
	m3["sim"].on_enter()
	approx(float(m3["sim"].output), 8.0, "conduct −2 + eco 0 → 8", 1e-9)


func test_eco_missing_snapshot_derivation() -> void:
	# the old-save ruling: a MISSING snapshot derives from the CURRENT eco
	# (continue-runs); without an eco at all it reads the 0.5 neutral
	var m: Dictionary = _mk_sim(W_TRAITLESS, SEED, null)
	m["sim"].on_enter()
	approx(float(m["sim"].output), 16.0, "no snapshot + no eco → the 0.5 neutral", 1e-9)
	# a live eco with 3 living lines derives 0.5 → 16; 6 lines → 22
	var m2: Dictionary = _mk_sim(W_TRAITLESS, SEED, null)
	m2["ctx"].eco = StubEco.new(3)
	m2["sim"].on_enter()
	approx(float(m2["sim"].output), 16.0, "no snapshot + 3 living lines → 0.5 → 16", 1e-9)
	var m3: Dictionary = _mk_sim(W_TRAITLESS, SEED, null)
	m3["ctx"].eco = StubEco.new(6)
	m3["sim"].on_enter()
	approx(float(m3["sim"].output), 22.0, "no snapshot + 6 living lines → 1.0 → 22", 1e-9)
	# a corrupt (non-numeric) snapshot reads as missing, not as a crash
	var m4: Dictionary = _mk_sim(W_TRAITLESS, SEED, null)
	m4["ctx"].flags["ecoHealth"] = "half"
	m4["sim"].on_enter()
	approx(float(m4["sim"].output), 16.0, "a corrupt snapshot reads as missing", 1e-9)


## Duck-typed eco stub — only living() is read (the -s mode has no
## class_name globals; the sim consumes the eco through preloads).
class StubEco:
	var n := 0
	func _init(count: int) -> void:
		n = count
	func living() -> Array:
		var out: Array = []
		for i in n:
			out.append({"id": i})
		return out


# ---- famine pauses the econ regen for EXACTLY its 20 s ------------------------

func test_famine_pauses_regen_exactly_20s() -> void:
	var m: Dictionary = _mk_sim(W_HUNGRY)
	var sim: Variant = m["sim"]
	sim.on_enter()
	# the econ lane's refill is the regen drip target (lastRaised='econ'):
	# empty the board so every beat lands on econ
	sim.mil = 0.0
	sim.culture = 0.0
	sim.econ = 0.0
	sim.output = 10.0
	sim.lastRaised = "econ"
	sim.regenT = 0.0
	# the famine enters through its WARN phase — the regen keeps running there
	ok(bool(sim.chaos.trigger("famine", sim)), "the famine def exists in the deck")
	var t_trigger: float = float(sim.time)
	var guard := 0
	while not bool(sim.chaos.is_active("famine")) and guard < 600:
		guard += 1
		sim.update(0.1, _inp())
	var t0: float = float(sim.time)
	var regen_t0: float = float(sim.regenT)
	var econ_at_start: float = float(sim.econ)
	ok(float(sim.chaos.warn_remaining()) <= 0.0, "the warn window ran before apply")
	ok(regen_t0 > 0.0, "warn phase: the regen clock still ran (warn first)")
	# 10 s in: the regen clock is FROZEN at its warn-exit value (no drip, econ
	# unchanged) — dt 0.1 keeps the accumulated float error under eps 1e-9
	for i in 100:
		sim.update(0.1, _inp())
	approx(float(sim.regenT), regen_t0,
			"mid-famine: the regen clock is frozen at its warn-exit value", 1e-9)
	approx(float(sim.econ), econ_at_start, "mid-famine: econ regen paused", 1e-9)
	# ride out the remaining span; the pause lifts EXACTLY 20 s after apply
	guard = 0
	while bool(sim.chaos.is_active("famine")) and guard < 1200:
		guard += 1
		sim.update(0.1, _inp())
	var t1: float = float(sim.time)
	approx(t1 - t0, 20.0, "the famine pause spans exactly 20 s (sim clock)", 1e-9)
	# the drip resumes: the frozen regenT (~2.6 at the warn exit) crosses 6.0
	# ~3.4 s later → exactly one econ beat (lastRaised = econ)
	for i in 40:
		sim.update(0.1, _inp())
	approx(float(sim.econ), econ_at_start + 1.0,
			"after the pause the econ regen drip resumes", 1e-9)
	ok(float(sim.time) - t_trigger > 20.0, "the whole ride sits past the trigger")


# ---- acid monsoon: the drain waits for the warn phase --------------------------

func test_acid_monsoon_drains_only_after_warn() -> void:
	var m: Dictionary = _mk_sim(W_TOXIN)
	var sim: Variant = m["sim"]
	sim.on_enter()
	# the military rival's ambient shelling would pollute the exact hp pins —
	# zero its aggression (the probe-fixture seam: straight at the rival field)
	sim.rivals[0]["aggression"] = 0.0
	for c in sim.cities:
		c["hp"] = 100.0
	ok(bool(sim.chaos.trigger("acid_monsoon", sim)),
			"the acid_monsoon def exists in the deck")
	# the warn window: banners fly, hp untouched (chaos law — warn FIRST);
	# ride 2 s of the 2.5 s window — never past it
	var guard := 0
	while float(sim.chaos.warn_remaining()) <= 0.0 and guard < 600:
		guard += 1
		sim.update(DT, _inp())
	for i in 120:
		sim.update(DT, _inp())
	ok(float(sim.chaos.warn_remaining()) > 0.0, "still inside the warn window")
	ok(not bool(sim.chaos.is_active("acid_monsoon")), "the monsoon has not applied")
	for c in sim.cities:
		approx(float(c["hp"]), 100.0, "warn phase: %s hp untouched" % c["id"], 1e-9)
	# the active phase drains ~2 hp/s per city over the 6 s span
	guard = 0
	while not bool(sim.chaos.is_active("acid_monsoon")) and guard < 600:
		guard += 1
		sim.update(DT, _inp())
	for i in 360:
		sim.update(DT, _inp())
	for c in sim.cities:
		ok(float(c["hp"]) < 100.0, "active phase: %s took monsoon damage" % c["id"])
		ok(float(c["hp"]) >= 5.0, "the drain respects the burning floor")
	# and the drain STOPS with the event (6 s span: −12 total, floor aside)
	guard = 0
	while bool(sim.chaos.is_active("acid_monsoon")) and guard < 600:
		guard += 1
		sim.update(DT, _inp())
	var hp_after: float = float(sim.cities[1]["hp"])
	for i in 120:
		sim.update(DT, _inp())
	approx(float(sim.cities[1]["hp"]), hp_after, "the drain stops at the end", 1e-9)


# ---- moon cult: the +15% burst, once -------------------------------------------

func test_moon_cult_bursts_culture_once() -> void:
	var m: Dictionary = _mk_sim(W_MOON)
	var sim: Variant = m["sim"]
	sim.on_enter()
	sim.culture = 4.0
	ok(bool(sim.chaos.trigger("moon_cult", sim)),
			"the moon_cult def exists in the deck")
	# the burst lands at the apply (instant — the quake/rebellion shape)
	var guard := 0
	while not bool(sim.chaos.is_active("moon_cult")) and guard < 600:
		guard += 1
		sim.update(DT, _inp())
	approx(float(sim.culture), 4.6, "the burst is +15% of current (4 → 4.6)", 1e-9)
	# ONCE — no tick re-applies it
	for i in 600:
		sim.update(DT, _inp())
	approx(float(sim.culture), 4.6, "the burst does not repeat", 1e-9)
	# the slider cap holds: 9.5 × 1.15 = 10.925 → clamped 10
	var m2: Dictionary = _mk_sim(W_MOON)
	m2["sim"].on_enter()
	m2["sim"].culture = 9.5
	m2["sim"].chaos.trigger("moon_cult", m2["sim"])
	guard = 0
	while not bool(m2["sim"].chaos.is_active("moon_cult")) and guard < 600:
		guard += 1
		m2["sim"].update(DT, _inp())
	approx(float(m2["sim"].culture), 10.0, "the burst respects the lane cap", 1e-9)


# ---- the bots -------------------------------------------------------------------

func test_eco_snapshot_recorded_at_creature_exit() -> void:
	# the WRITE side: every creature-stage exit snapshots the living web into
	# the camelCase wire flag — the real sim's own bootstrap seeds the 6-line
	# base roster → full health; one extinction drags it to 5/6
	var CreatureSim := preload("res://src/game/creature/creature_sim.gd")
	var ctx: Variant = Ctx.new(0xEC0)
	ctx.world = W_TRAITLESS.duplicate(true)
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, {})
	sim.on_exit()
	approx(float(ctx.flags["ecoHealth"]), 1.0,
			"the 6-line base roster exits at full health", 1e-9)
	sim.eco.species[0]["extinct"] = true
	sim.on_exit()
	approx(float(ctx.flags["ecoHealth"]), 5.0 / 6.0,
			"one extinction reads 5/6 (living / base roster)", 1e-9)


func test_eco_collapsed_armada_route_bot() -> void:
	# the eco-collapsed world (ecoHealth 0 → start output 10) must still
	# complete the armada route: the launch gate PASSES (no refusal toast),
	# the honest resolve lands net-positive, and unification completes within
	# the launch budget (the baseline full-mil route measures ~6-8 launches)
	var r: Dictionary = BotAttach.armada_eco0_run(W_TRAITLESS, 0.0, 0xC14)
	ok(bool(r["completed"]), "ecoHealth 0 completes the armada route")
	eq(bool(r["gate_refused"]), false, "the launch gate never refuses at mil 10")
	ok(int(r["honest_launches"]) >= 1, "one honest launch flew")
	ok(int(r["honest_resolves"]) >= 1, "the honest resolve landed net-positive")
	ok(int(r["launches"]) <= 10, "launches ≤ 10 at ecoHealth 0 (got %d)" % int(r["launches"]))
	approx(float(r["output"]), 10.0, "start output 10 at ecoHealth 0", 1e-9)
	ok(r["space_card"].size() > 0, "the victory fired the space card")


func test_pacifist_bot_timing() -> void:
	# the culture-only completion: NO armadas, the hearts lane flips all three
	# cities, the run completes ≤ 1200 s game-time with the buffed regen
	# constant (the probe ledger: the old 0.006 weight measured NO completion
	# within a 3000 s probe; the buffed run measures 989 s)
	var r: Dictionary = BotAttach.pacifist_run(W_TRAITLESS, 1.0, 0xC1DE, 1500.0)
	ok(bool(r["completed"]), "the pacifist route completes (time %d s)" % int(r["time"]))
	ok(float(r["time"]) <= 1200.0, "pacifist completion ≤ 1200 s (got %d)" % int(float(r["time"])))
	eq(int(r["launches"]), 0, "no armadas on the culture-only route")
	approx(float(r["output"]), 22.0, "the full-web snapshot rides the cap", 1e-9)
	approx(float(r["mil"]), 0.0, "the passive route drains military", 1e-9)
	ok(float(r["culture"]) >= 10.0, "culture at the lane cap")


# ---- the tribe-fall DNA floor ----------------------------------------------------

func test_tribe_fall_dna_floor_and_no_loop() -> void:
	# the fall path floors DNA at 50 (the rebirth purse) deterministically and
	# the re-founded village STANDS (the fall→creature→regrow→re-found loop
	# terminates — the restore-resurrection bug stays dead)
	var low: Dictionary = BotAttach.tribe_fall_run(0xFA11, 12)
	ok(bool(low["fall_fired"]), "the fall latched")
	eq(int(low["dna_after"]), 50, "DNA 12 floors to 50 at the fall")
	ok(bool(low["blob_erased"]), "the dead village blob is erased")
	eq(low["goto_payload"], ["creature", {"title": "BACK TO THE WILDS",
			"sub": "gather your strength and found a new people"}],
			"the creature payload rides the fall")
	ok(bool(low["refound_ok"]), "the re-founded village stands (no loop)")
	ok(int(low["refound_tribe"]) > 0 and int(low["refound_huts"]) > 0,
			"the refound has people and a hut")
	# a rich purse is untouched (max, not set)
	var high: Dictionary = BotAttach.tribe_fall_run(0xFA11, 200)
	eq(int(high["dna_after"]), 200, "DNA 200 stays 200 (max, not set)")
	ok(bool(high["refound_ok"]), "the rich-purse refound stands too")
