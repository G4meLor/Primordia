# Tests for game/civ/civ_sim.gd — the civ stage sim core (M5 task 1):
# constructor seeding (capital + 3 rivals + city jitter, the boot-order branch
# pins), slider raise/transfer/regen + lastRaised, armada launch gates in
# order + the power SNAPSHOT + flight/resolve (net math, flip, burning chance),
# the rivalDefFor matrix, tickSecond (production, rival personalities, hearts,
# karma drift, flips, the -99.8-above-heal revolt), the chaos hook methods,
# the scheduler wiring, persist/restore guards, brick hardening, the victory
# path, debug seams.
# TS source: Spore src/game/civ/CivStage.ts (frozen), lines cited per pin.
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const RngLib := preload("res://src/core/rng.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")
const CivEvents := preload("res://src/game/civ/civ_events.gd")

const SEED := 0xC1F1E5
const OBJECTIVE := "UNIFY THE PLANET — slider keys Q/W/E · launch armadas with 1/2/3"

# TS:85-89 — the rival table, verbatim.
const RIVAL_DEFS := [
	{"id": "r1", "name": "Khorate Dominion", "personality": "military", "aggression": 0.8, "color": "#ff7a5a"},
	{"id": "r2", "name": "Vexi Concord", "personality": "culture", "aggression": 0.35, "color": "#9a7aff"},
	{"id": "r3", "name": "Ompa Syndicate", "personality": "economy", "aggression": 0.25, "color": "#5ad0a8"},
]


# ---- fixtures ------------------------------------------------------------------

# Builds a GameContext (explicit seed), the stage rng branch, a recording
# hooks set, and the sim. The storyteller-read hooks return the mutable rec
# values so tests can retune pacing without rebuilding.
func _mk_sim(seed_v: int = SEED, difficulty: String = "normal", ctx_v: Variant = null) -> Dictionary:
	var ctx: Variant = ctx_v if ctx_v != null else Ctx.new(seed_v)
	ctx.difficulty = difficulty
	var rec: Dictionary = {
		"toasts": [], "banners": [], "audio": [], "shakes": [], "spawns": [],
		"objectives": [], "insets": [], "moods": [], "floats": [], "abilities": [],
		"gotos": [], "saves": 0, "notes": [],
		"gap_bias_out": 1.0, "mood_out": "test", "warn_scale_out": 1.0,
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_toast_inset": func(px): rec["insets"].append(px),
		"hud_show_objective": func(text): rec["objectives"].append(text),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"hud_set_abilities": func(list): rec["abilities"].append(list),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"audio_set_mood": func(name_v): rec["moods"].append(name_v),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"go_to": func(stage_v, data): rec["gotos"].append([stage_v, data]),
		"save_all": func(): rec["saves"] = int(rec["saves"]) + 1,
		"get_gap_bias": func(): return float(rec["gap_bias_out"]),
		"get_mood": func(): return String(rec["mood_out"]),
		"get_warn_scale": func(): return float(rec["warn_scale_out"]),
		"storyteller_note_chaos_event": func(now): rec["notes"].append(now),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CivSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec, "rng": rng}


# Input snapshot with the M2 field shape (civ reads keys_pressed only).
func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


# The TS constructor's exact draw sequence replayed on a parallel branch of a
# fresh same-seed context — pins draw ORDER + formulas bit-exactly (TS:92-110:
# capital fixed, then per rival x then y, then the chaos branch draw).
func _expected_constructor(seed_v: int) -> Dictionary:
	var pr: Variant = Ctx.new(seed_v).rng.branch()
	var pos: Array = []
	for i in 3:
		pos.append({
			"x": cos(float(i) / 3.0 * TAU) * 700.0 + pr.range(-120.0, 120.0),
			"y": sin(float(i) / 3.0 * TAU) * 480.0 + pr.range(-90.0, 90.0) - 60.0,
		})
	var chaos_state: int = pr.branch().state()
	return {"pos": pos, "chaos_state": chaos_state, "stage_state": pr.state()}


# Independent derivation of the launch target: the nearest enemy city to the
# capital by the brief's stable hypot sort (first minimum wins ties).
func _nearest_target(sim_v: Variant) -> Dictionary:
	var cap: Dictionary = sim_v.cities[0]
	var best: Dictionary = {}
	var best_d := INF
	for c in sim_v.cities:
		if String(c["owner"]) == "you" or float(c["influence"]) >= 100.0:
			continue
		var d: float = sqrt(pow(float(c["x"]) - float(cap["x"]), 2.0) + pow(float(c["y"]) - float(cap["y"]), 2.0))
		if best.is_empty() or d < best_d:
			best_d = d
			best = c
	return best


func _toasted(rec: Dictionary, fragment: String) -> bool:
	for t in rec["toasts"]:
		if String(t[0]).find(fragment) >= 0:
			return true
	return false


func _heard(rec: Dictionary, name_v: String) -> bool:
	for a in rec["audio"]:
		if a[0] == name_v:
			return true
	return false


# A probe Rng cloned from the sim's stream state — replaying the TS draw order
# on it derives expected outcomes without calling the sim (independent
# derivations for the chance/pick pins).
func _probe(sim_v: Variant) -> Variant:
	return RngLib.new_from(sim_v.rng.state())


func _blob(rec_ctx: Variant) -> Dictionary:
	return JSON.parse_string(String(rec_ctx.flags["civState"]))


# ---- constructor seeding (TS:79-111) ---------------------------------------------

func test_constructor_seeding_pins() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var exp_v: Dictionary = _expected_constructor(SEED)
	eq(sim.cities.size(), 4, "capital + 3 rival cities (TS:92-107)")
	# capital, TS:92 — all fields fixed (no rng draws)
	var cap: Dictionary = sim.cities[0]
	eq(String(cap["id"]), "you", "capital id 'you'")
	eq(String(cap["name"]), "%sgrad" % String(ctx.player_name), "capital name {player_name}grad (TS:92)")
	eq(String(cap["owner"]), "you", "capital owner 'you'")
	eq(float(cap["x"]), 0.0, "capital x 0")
	eq(float(cap["y"]), 120.0, "capital y 120")
	eq(float(cap["hp"]), 100.0, "capital hp 100")
	eq(float(cap["influence"]), 100.0, "capital influence 100")
	eq(float(cap["pop"]), 8.0, "capital pop 8")
	eq(float(cap["burning"]), 0.0, "capital burning 0")
	# rivals, TS:85-89
	eq(sim.rivals.size(), 3, "3 rivals")
	for i in 3:
		var r: Dictionary = sim.rivals[i]
		var def: Dictionary = RIVAL_DEFS[i]
		eq(String(r["id"]), String(def["id"]), "rival %d id" % i)
		eq(String(r["name"]), String(def["name"]), "rival %d name" % i)
		eq(String(r["personality"]), String(def["personality"]), "rival %d personality" % i)
		eq(float(r["aggression"]), float(def["aggression"]), "rival %d aggression" % i)
		eq(String(r["color"]), String(def["color"]), "rival %d color" % i)
	# rival cities, TS:96-106 — names[1..3] ('Prime' is the unused [0], TS:84)
	var city_names: Array = ["Khora", "Vex", "Ompa"]
	for i in 3:
		var c: Dictionary = sim.cities[i + 1]
		var def: Dictionary = RIVAL_DEFS[i]
		eq(String(c["id"]), String(def["id"]), "city %d id" % i)
		eq(String(c["name"]), String(city_names[i]), "city %d name Prime-idx" % i)
		eq(String(c["owner"]), String(def["id"]), "city %d owner" % i)
		approx(float(c["x"]), float(exp_v["pos"][i]["x"]), "city %d x at seed (draw-order pin, TS:100)" % i)
		approx(float(c["y"]), float(exp_v["pos"][i]["y"]), "city %d y at seed (draw-order pin, TS:101)" % i)
		eq(float(c["hp"]), 100.0, "city %d hp 100" % i)
		eq(float(c["influence"]), -60.0, "city %d influence -60" % i)
		eq(float(c["pop"]), 6.0, "city %d pop 6" % i)
		eq(float(c["burning"]), 0.0, "city %d burning 0" % i)
	# sliders + bookkeeping, TS:57-68 + :308
	eq(float(sim.mil), 4.0, "mil 4 (TS:57)")
	eq(float(sim.culture), 3.0, "culture 3 (TS:58)")
	eq(float(sim.econ), 3.0, "econ 3 (TS:59)")
	eq(float(sim.output), 10.0, "output 10 (TS:60)")
	eq(String(sim.lastRaised), "mil", "lastRaised 'mil' (TS:63)")
	eq(float(sim.regenT), 0.0, "regenT 0 (TS:62)")
	eq(float(sim.launchCds["attack"]), 0.0, "launchCds.attack 0")
	eq(float(sim.launchCds["charm"]), 0.0, "launchCds.charm 0")
	eq(float(sim.launchCds["trade"]), 0.0, "launchCds.trade 0")
	eq(bool(sim.victoryFired), false, "victoryFired false (TS:73)")
	eq(float(sim.camX), 0.0, "camX 0 (TS:74)")
	eq(float(sim.camY), 0.0, "camY 0 (TS:74)")
	eq(float(sim.time), 0.0, "time 0 (TS:50)")
	eq(sim.armadas.size(), 0, "no armadas (TS:54)")
	# boot-order branch pins (TS:81/109): 6 city draws, then the chaos branch
	eq(int(sim.rng.state()), int(exp_v["stage_state"]), "stage rng state after construction (branch draw order)")
	eq(int(sim.chaos._rng.state()), int(exp_v["chaos_state"]), "chaos scheduler on a SECOND rng.branch() (TS:109)")
	# the deck landed in task 2 (civ_events.gd): the constructor holds the
	# world-parameterized deck — exactly the factory's defs for ctx.world
	var want_ids: Array = []
	for d in CivEvents.make_civ_chaos_events(ctx.world):
		want_ids.append(d["id"])
	var deck_ids: Array = []
	for d in sim.chaos.defs:
		deck_ids.append(d["id"])
	eq(deck_ids, want_ids, "constructor deck = the factory deck for ctx.world")
	ok(not deck_ids.is_empty(), "the derived ctx.world yields a non-empty deck")
	eq(int(sim.deckSeed), int(ctx.world["seed"]), "deckSeed = world seed (TS:110)")
	ok(is_same(sim.rulerGenome, ctx.genome), "rulerGenome is the context genome REFERENCE (TS:82)")
	eq(bool(sim.has_active_chaos()), false, "hasActiveChaos false at boot (TS:70-72)")


# ---- sliders (TS:182-222) --------------------------------------------------------

func test_slider_raise_transfer() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# full board (4+3+3 = 10): raise mil — transfer 1 from the largest OTHER;
	# culture 3 vs econ 3 tie → the TS stable sort keeps canonical order →
	# culture donates (the brief's culture-before-econ tie pin, TS:203-210)
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyQ"]}))
	eq(float(sim.mil), 5.0, "mil raised to 5")
	eq(float(sim.culture), 2.0, "culture donated (tie → culture before econ, TS stable sort)")
	eq(float(sim.econ), 3.0, "econ untouched")
	eq(String(sim.lastRaised), "mil", "lastRaised tracks the raised lane (TS:217)")
	eq(rec["toasts"].size(), 1, "one toast")
	eq(String(rec["toasts"][0][0]), "+1 mil ← culture", "transfer toast text (TS:210)")
	eq(String(rec["toasts"][0][1]), "info", "transfer toast kind")
	eq(String(rec["toasts"][0][2]), "⚖", "transfer toast icon")
	# donor = the largest other, not the tie default: 0/5/5 raise culture → econ donates
	sim.mil = 0.0
	sim.culture = 5.0
	sim.econ = 5.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyW"]}))
	eq(float(sim.culture), 6.0, "culture raised to 6")
	eq(float(sim.econ), 4.0, "econ donated (largest other, TS:206-209)")
	eq(float(sim.mil), 0.0, "mil untouched")
	# board maxed 10/0/0: raising the maxed lane is a SILENT no-op — the
	# donor-0 revert branch (TS:211-214) is unreachable: both others 0
	# ⟹ total = lane ≤ 10 ⟹ `total > output` is false (proof, not a skip —
	# the branch is ported verbatim and must stay dead)
	var n_toasts: int = rec["toasts"].size()
	sim.mil = 10.0
	sim.culture = 0.0
	sim.econ = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyQ"]}))
	eq(float(sim.mil), 10.0, "maxed lane unchanged")
	eq(rec["toasts"].size(), n_toasts, "no board-full toast (donor-0 revert unreachable — TS quirk kept dead)")
	# raise below output: no transfer
	sim.mil = 1.0
	sim.culture = 1.0
	sim.econ = 1.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyE"]}))
	eq(float(sim.econ), 2.0, "econ raised freely under output")
	eq(float(sim.mil), 1.0, "mil untouched under output")
	eq(float(sim.culture), 1.0, "culture untouched under output")
	# A/S/D lower with the 0 clamp (TS:218/220/222)
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyA"]}))
	eq(float(sim.mil), 0.0, "A clamps mil at 0")
	sim.mil = 5.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyA"]}))
	eq(float(sim.mil), 4.0, "A lowers mil")
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyS"]}))
	eq(float(sim.culture), 0.0, "S lowers culture (clamped at 0)")
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["KeyD"]}))
	eq(float(sim.econ), 1.0, "D lowers econ")
	eq(String(sim.lastRaised), "econ", "lowering does not touch lastRaised (TS:218-222)")


func test_regen_and_lastraised() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# total 8 < 10, lastRaised culture → the 6 s regen refills CULTURE (TS:186-195)
	sim.mil = 2.0
	sim.culture = 3.0
	sim.econ = 3.0
	sim.lastRaised = "culture"
	for i in 6:
		sim.update(1.0, _inp())
	eq(float(sim.culture), 4.0, "regen refills lastRaised lane at 6 s")
	eq(float(sim.regenT), 0.0, "regenT resets")
	eq(float(sim.mil), 2.0, "other lanes untouched")
	eq(float(sim.econ), 3.0, "other lanes untouched")
	for i in 6:
		sim.update(1.0, _inp())
	eq(float(sim.culture), 5.0, "regen repeats each 6 s")
	# board full → no regen (TS:191)
	sim.mil = 4.0
	sim.culture = 3.0
	sim.econ = 3.0
	for i in 7:
		sim.update(1.0, _inp())
	eq(float(sim.mil), 4.0, "no regen at total == output")
	eq(float(sim.culture), 3.0, "no regen at total == output")
	eq(float(sim.econ), 3.0, "no regen at total == output")


func test_launch_spend_sets_lastraised() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# charm launch at culture 5 (power 9 > rivalDef 6 + 2 — passes, TS:331-335)
	sim.culture = 5.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit2"]}))
	eq(sim.armadas.size(), 1, "charm armada launched")
	eq(float(sim.culture), 3.0, "2 output spent (TS:338)")
	eq(String(sim.lastRaised), "culture", "launch-spend sets lastRaised (TS:340-343 — the pacifist-drain pin)")
	eq(float(sim.launchCds["charm"]), 5.0, "cd 5 (TS:344)")
	# drain the other lanes → total < output → regen must refill the SPENT lane
	sim.mil = 1.0
	sim.econ = 1.0
	for i in 6:
		sim.update(1.0, _inp())
	eq(float(sim.culture), 4.0, "regen refills the spent lane — charm/trade launches never raised it before (TS:340-343)")


# ---- launch gates (TS:310-349) ---------------------------------------------------

func test_launch_gates_order() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# gate 1 — cd: with the route on cooldown NOTHING else fires (no stat toast) (TS:311)
	sim.launchCds["attack"] = 5.0
	sim.mil = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(rec["toasts"].size(), 0, "cd gate first — silent return")
	eq(sim.armadas.size(), 0, "no armada on cd")
	# gate 2 — stat < 2 (TS:312-315)
	sim.launchCds["attack"] = 0.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(rec["toasts"].size(), 1, "stat gate fires after cd")
	eq(String(rec["toasts"][0][0]), "attack needs 2 output in its lane (raise with Q/W/E)", "stat toast text (TS:314)")
	eq(String(rec["toasts"][0][2]), "⚖", "stat toast icon")
	eq(sim.armadas.size(), 0, "no armada under stat 2")
	# gate 2 precedes gate 3: stat toast even with no targets
	sim.cities[1]["influence"] = 100.0
	sim.cities[2]["influence"] = 100.0
	sim.cities[3]["influence"] = 100.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(rec["toasts"].size(), 2, "stat gate precedes the targets gate")
	eq(String(rec["toasts"][1][0]), "attack needs 2 output in its lane (raise with Q/W/E)", "stat toast again")
	# gate 3 — no targets (TS:317-320)
	sim.mil = 4.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(String(rec["toasts"][2][0]), "No city left to persuade — build output!", "no-target toast text (TS:319)")
	eq(String(rec["toasts"][2][2]), "🏛", "no-target toast icon")
	eq(sim.armadas.size(), 0, "no armada without targets")


func test_launch_boundary_and_toast() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# normal difficulty: rivalDef 6 → refuse at power ≤ 8 (stat ≤ 4) (TS:331-335)
	sim.mil = 4.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(String(rec["toasts"][0][0]),
		"attack needs 1+ more output in its lane (5+ total) — raise with Q/W/E, or lower a full slider",
		"hopeless refuse toast at stat 4 (power 8 ≤ 6+2, TS:333)")
	eq(sim.armadas.size(), 0, "no armada on refuse")
	# stat 2 → the 5−stat term reads 3
	sim.mil = 2.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(String(rec["toasts"][1][0]),
		"attack needs 3+ more output in its lane (5+ total) — raise with Q/W/E, or lower a full slider",
		"5−stat term (TS:333)")
	# stat 5 → power 9 > 8 → launches
	sim.mil = 5.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(sim.armadas.size(), 1, "power 9 > rivalDef+2 launches")
	var target: Dictionary = _nearest_target(sim)
	eq(is_same(sim.armadas[0]["target"], target), true, "armada target is the nearest enemy city (stable hypot min, TS:323-325)")
	eq(is_same(sim.armadas[0]["target"], sim.cities[2]), true, "target holds the LIVE city dict reference")
	eq(float(sim.armadas[0]["power"]), 9.0, "power = stat + 4 SNAPSHOT (TS:327)")
	eq(float(sim.mil), 3.0, "2 spent")
	eq(float(sim.launchCds["attack"]), 5.0, "cd 5")
	eq(String(sim.lastRaised), "mil", "lastRaised = the lane")
	eq(String(rec["toasts"][2][0]), "ATTACK armada → %s (power 9)" % String(target["name"]), "launch toast (TS:348)")
	eq(String(rec["toasts"][2][2]), "⚔️", "attack icon")
	ok(_heard(rec, "warp"), "warp audio routed through the hook (TS:347 — audio deferred)")


func test_launch_gate_difficulty_matrix() -> void:
	# chaos: rivalDef 9 → stat 6 (power 10 ≤ 11) refuses; peaceful: rivalDef 5
	# → stat 4 (power 8 > 7) launches (TS:351-355 via the launch gate)
	var m1 := _mk_sim(SEED, "chaos")
	m1["sim"].mil = 6.0
	m1["sim"].update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(m1["sim"].armadas.size(), 0, "chaos refuses power 10 ≤ 9+2")
	var m2 := _mk_sim(SEED, "peaceful")
	m2["sim"].mil = 4.0
	m2["sim"].update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(m2["sim"].armadas.size(), 1, "peaceful launches power 8 > 5+2")
	eq(float(m2["sim"].armadas[0]["power"]), 8.0, "power snapshot 8")


# ---- flight + resolve (TS:230-250, :357-390) --------------------------------------

func test_armada_flight_timeout_and_trail() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# city 1 at 6000 (> 220·14 = 3080) and the other rivals pushed away → the
	# nearest target is city 1 and the armada hits the t > 14 timeout (TS:236)
	sim.cities[1]["x"] = 6000.0
	sim.cities[1]["y"] = 120.0
	sim.cities[2]["x"] = -5000.0
	sim.cities[2]["y"] = 5000.0
	sim.cities[3]["x"] = -5000.0
	sim.cities[3]["y"] = -5000.0
	sim.mil = 5.0
	sim.culture = 4.0  # total 10 → the regen never fires → the drift term is constant
	# the launch frame already flies the armada (t += dt, TS:230 runs after the
	# launch keys) — its trail chance(dt·30) = chance(0.5) is the FIRST draw
	var launch_trail: bool = _probe(sim).next() < 0.5
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(sim.armadas.size(), 1, "attack launched at the far city")
	eq(rec["spawns"].size(), 1 if launch_trail else 0, "launch-frame trail per the seeded chance")
	for i in 13:
		sim.update(1.0, _inp())
	eq(sim.armadas.size(), 1, "still flying at t ≈ 13.02")
	eq(bool(sim.armadas[0]["alive"]), true, "alive until the timeout")
	# flight step: (dx/d)·220·dt — dy 0 → x = 220/60 + 220k exactly; trail
	# spawns ride the RAW map coords (TS:240-247); one spawn per big frame
	# (chance(dt·30) always true at dt 1)
	var launch_count: int = 1 if launch_trail else 0
	eq(rec["spawns"].size(), launch_count + 13, "one trail spawn per flight frame")
	var s0: Dictionary = rec["spawns"][launch_count]
	approx(float(s0["x"]), 220.0 / 60.0 + 220.0, "trail x = moved position (RAW map coords)")
	eq(float(s0["y"]), 120.0, "trail y unchanged")
	eq(String(s0["kind"]), "dot", "trail kind")
	eq(String(s0["color"]), "#9fd8ff", "trail color")
	eq(float(s0["ttl"]), 0.5, "trail ttl 0.5")
	eq(float(s0["size"]), 2.0, "trail size 2")
	eq(float(s0["drag"]), 1.0, "trail drag 1")
	# t > 14 → resolve on the 14th big update (TS:236-238); the filter drops it
	# (TS:250). The resolve's burning chance is that frame's FIRST draw — the
	# resolve branch skips the trail else — and tick 14 (same frame, after the
	# flight loop) then runs the burning tail on it
	var burn2: bool = _probe(sim).next() < 0.5
	sim.update(1.0, _inp())
	eq(sim.armadas.size(), 0, "dead armada filtered (TS:250 — alive||t<0)")
	# resolve effects: net (9−6)·10 = +30 → the float text reads +3 influence
	eq(String(rec["floats"][0][2]), "+3 influence", "floatWorld text rounds net/10 (TS:372)")
	eq(float(rec["floats"][0][4]), 14.0, "floatWorld size 14")
	eq(String(rec["floats"][0][3]), "#9fe89a", "positive net color")
	# camera: launch frame drifts 0.0733 (factor dt·1.2), then snaps (factor 1)
	# for 13 big frames → camX = 3.667 + 220·13; the float coords are the
	# toScreen correction (TS:372)
	var cam_x: float = 220.0 / 60.0 + 220.0 * 13.0
	approx(float(rec["floats"][0][0]), 6000.0 * 0.62 - cam_x * 0.5, "floatWorld x correction")
	approx(float(rec["floats"][0][1]), (120.0 - 30.0) * 0.62 - 120.0 * 0.5 + 40.0, "floatWorld y correction")
	# hp: 100 − 12 at the resolve; when the seeded burning fired, tick 14's
	# burning tail already took −2 more (TS:376/427)
	eq(float(sim.cities[1]["hp"]), 88.0 - (2.0 if burn2 else 0.0), "attack hp −12 (−2 more via the burning tail)")
	if burn2:
		eq(float(sim.cities[1]["burning"]), 5.5, "burning 6 then the tail −0.5 (TS:378/427)")
	else:
		eq(float(sim.cities[1]["burning"]), 0.0, "no burning on the seeded chance")
	# the launch frame crosses NO floor (floor(1/60)==floor(0)) → 14 ticks:
	# (culture−mil)·0.0004 = +0.0004 each (no regen — total 10) + the resolve −0.02
	approx(float(m["ctx"].karma), 14.0 * 0.0004 - 0.02, "karma: 14 drifts + attack −0.02")
	# the resolve ring at RAW map coords (TS:374)
	var ring: Dictionary = rec["spawns"][launch_count + 13]
	eq(String(ring["kind"]), "ring", "resolve ring kind")
	eq(float(ring["ttl"]), 0.7, "ring ttl 0.7")
	eq(float(ring["size"]), 30.0, "ring size 30")
	eq(float(ring["grow"]), 2.0, "ring grow 2")
	eq(String(ring["color"]), "rgba(255,120,90,0.9)", "attack ring color")
	eq(float(ring["x"]), 6000.0, "ring at RAW map coords")
	eq(float(ring["y"]), 120.0, "ring at RAW map coords")


func test_armada_resolve_near_target() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# city 1 within the 14-unit arrive radius → resolve on the launch frame,
	# before any trail draw — the burning chance is the FIRST rng draw after
	# construction (TS:236/378)
	sim.cities[1]["x"] = 5.0
	sim.cities[1]["y"] = 125.0
	sim.mil = 5.0
	var burn_draw: float = _probe(sim).next()
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(sim.armadas.size(), 0, "resolved + filtered on the same frame")
	eq(rec["spawns"].size(), 1, "no trail spawns; only the resolve ring")
	# net (9−6)·10 = +30 → influence −60 → −30 (exact: no tick ran — floor(1/60)==floor(0))
	eq(float(sim.cities[1]["influence"]), -30.0, "net math on the live city (TS:368-369)")
	# floatWorld at toScreen-corrected coords (camX/camY still 0):
	# x 5·0.62 = 3.1, y (125−30)·0.62 + 40 = 98.9
	approx(float(rec["floats"][0][0]), 3.1, "floatWorld x (TS:372)")
	approx(float(rec["floats"][0][1]), 98.9, "floatWorld y (TS:372)")
	eq(String(rec["floats"][0][2]), "+3 influence", "float text")
	eq(rec["shakes"].size(), 1, "one cam shake (TS:373)")
	eq(float(rec["shakes"][0][0]), 3.0, "shake magnitude 3")
	eq(float(rec["shakes"][0][1]), 0.2, "shake duration 0.2")
	eq(float(sim.cities[1]["hp"]), 88.0, "hp −12 (TS:376)")
	if burn_draw < 0.5:
		eq(float(sim.cities[1]["burning"]), 6.0, "burning 6 on the seeded chance draw (chance(0.5) true)")
	else:
		eq(float(sim.cities[1]["burning"]), 0.0, "no burning on the seeded chance draw (chance(0.5) false)")
	approx(float(m["ctx"].karma), -0.02, "attack karma −0.02 (TS:379)")


func test_armada_charm_flip() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.culture = 5.0
	sim.cities[2]["influence"] = 80.0
	sim.cities[2]["hp"] = 20.0
	sim.cities[2]["x"] = 5.0
	sim.cities[2]["y"] = 125.0
	var tgt_name: String = String(_nearest_target(sim)["name"])  # BEFORE the flip
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit2"]}))
	# net (9−6)·10 = 30 → 80+30 = 110 → clamp 100 → FLIP (TS:384-389)
	eq(String(sim.cities[2]["owner"]), "you", "flip at influence 100")
	eq(float(sim.cities[2]["hp"]), 40.0, "flip hp floor max(hp, 40)")
	eq(String(rec["banners"][0]["title"]), "VEX JOINS YOUR PLANETARY STATE", "flip banner (TS:387)")
	eq(String(rec["banners"][0]["kind"]), "reward", "flip banner kind")
	ok(_heard(rec, "levelup"), "levelup audio on flip (TS:388)")
	approx(float(m["ctx"].karma), 0.015, "charm karma +0.015 (TS:382)")
	eq(String(rec["spawns"][0]["color"]), "rgba(150,200,255,0.9)", "charm ring color")
	eq(float(sim.cities[2]["burning"]), 0.0, "charm sets no burning")
	eq(String(rec["toasts"][0][0]), "CHARM armada → %s (power 9)" % tgt_name, "charm launch toast (TS:348)")
	eq(String(rec["toasts"][0][2]), "🎭", "charm icon")


func test_armada_trade_karma() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.econ = 5.0
	sim.cities[3]["x"] = 5.0
	sim.cities[3]["y"] = 115.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit3"]}))
	approx(float(sim.cities[3]["influence"]), -30.0, "trade net (9−6)·10 (TS:368)")
	eq(float(sim.cities[3]["hp"]), 100.0, "trade leaves hp (TS:380-382 else branch)")
	eq(float(sim.cities[3]["burning"]), 0.0, "trade sets no burning")
	approx(float(m["ctx"].karma), 0.01, "trade karma +0.01 (TS:382)")
	eq(String(rec["toasts"][0][0]), "TRADE armada → %s (power 9)" % String(sim.cities[3]["name"]), "trade launch toast")
	eq(String(rec["toasts"][0][2]), "💰", "trade icon")
	eq(String(rec["spawns"][0]["color"]), "rgba(150,200,255,0.9)", "trade ring color (non-attack)")


func test_resolve_owned_target_noop() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# target far → timeout resolve; flip the city to 'you' mid-flight — the
	# resolve returns before ANY effect (TS:359)
	sim.mil = 5.0
	sim.cities[1]["x"] = 6000.0
	sim.cities[1]["y"] = 120.0
	sim.cities[2]["owner"] = "you"  # kill the culture agenda → short draw chain
	sim.cities[3]["x"] = -5000.0
	sim.cities[3]["y"] = -5000.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	eq(sim.armadas.size(), 1, "launched at city 1")
	sim.cities[1]["owner"] = "you"
	for i in 13:
		sim.update(1.0, _inp())
	# the 14th update crosses t > 14 → resolve hits the owned-target return
	var inf_before: float = float(sim.cities[1]["influence"])
	var karma_before: float = float(m["ctx"].karma)
	var p: Variant = _probe(sim)
	var d_buy: float = p.next()  # economy rival chance(0.01)
	var pick_i: int = -1
	if d_buy < 0.01:
		pick_i = floori(p.next() * 3.0)  # pool [cap, c1, c2] (r3's excluded, TS:421)
	sim.update(1.0, _inp())
	eq(sim.armadas.size(), 0, "armada resolved (timeout)")
	eq(rec["floats"].size(), 0, "NO floatWorld on the owned-target return (TS:359)")
	var exp_delta: float = 0.12  # the unrest heal only — no resolve net term
	if pick_i == 1:
		exp_delta -= 2.0  # the economy buy landed on city 1
	approx(float(sim.cities[1]["influence"]) - inf_before, exp_delta,
		"influence moved by the heal (+0.12) and any buy — NOT by a resolve net (TS:359/400)")
	var exp_drift: float = (float(sim.culture) - float(sim.mil)) * 0.0004
	approx(float(m["ctx"].karma) - karma_before, exp_drift,
		"karma moved by the drift term only — no attack −0.02 (TS:359/439)")


# ---- rivalDefFor (TS:351-355) ------------------------------------------------------

func test_rival_def_matrix() -> void:
	# (rival ? 6 : 3) + (chaos ? 3 : peaceful ? −1 : 0) — ONE source of truth
	# for the launch gate AND resolve (the drift pin comment, TS:364-367)
	var m := _mk_sim(SEED, "normal")
	var sim: Variant = m["sim"]
	eq(float(sim.rival_def_for(true)), 6.0, "normal rival 6")
	eq(float(sim.rival_def_for(false)), 3.0, "normal own 3")
	m["ctx"].difficulty = "chaos"
	eq(float(sim.rival_def_for(true)), 9.0, "chaos rival 9")
	eq(float(sim.rival_def_for(false)), 6.0, "chaos own 6")
	m["ctx"].difficulty = "peaceful"
	eq(float(sim.rival_def_for(true)), 5.0, "peaceful rival 5")
	eq(float(sim.rival_def_for(false)), 2.0, "peaceful own 2")
	# the resolve side reads the SAME fn — an injected armada on chaos with
	# snapshot power 10 nets (10−9)·10 = +10 (the gate/resolve agreement pin)
	m["ctx"].difficulty = "chaos"
	sim.cities[1]["x"] = 5.0
	sim.cities[1]["y"] = 125.0
	sim.armadas.append({"x": 0.0, "y": 120.0, "tx": 5.0, "ty": 125.0,
		"target": sim.cities[1], "kind": "attack", "t": 0.0, "alive": true, "power": 10.0})
	sim.update(1.0 / 60.0, _inp())
	approx(float(sim.cities[1]["influence"]), -50.0, "resolve used rivalDefFor(!!rival) = 9 → net +10 (TS:367-369)")
	eq(String(m["rec"]["floats"][0][2]), "+1 influence", "resolve float text net/10 (TS:372)")


# ---- tickSecond (TS:392-457) ------------------------------------------------------

func test_tick_second_floor_gate() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# dt 0.4: floor(0.4)==floor(0), floor(0.8)==floor(0.4), floor(1.2)!=floor(0.8)
	# → exactly ONE tickSecond in three updates (TS:253)
	for i in 3:
		sim.update(0.4, _inp())
	approx(float(sim.cities[0]["pop"]), 8.02, "one tick in three 0.4 s updates (float floor-cross gate, TS:253)")
	approx(float(m["ctx"].karma), -0.0004, "karma drifted exactly once")


func test_tick_second_full_derivation() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# rig the capital: hp 99.9 (production +0.5 → capped 100, then shell −0.32),
	# influence −99 (heal +0.12 → −98.88; the culture erosion can floor at −100)
	sim.cities[0]["hp"] = 99.9
	sim.cities[0]["influence"] = -99.0
	# probe the tick's draw chain: d1 military shell toast chance(0.02),
	# d2 culture erosion chance(0.03) on the capital, d3 economy buy chance(0.01),
	# d4 the pick over [cap, r1, r2] cities (r3's excluded, TS:421)
	var p: Variant = _probe(sim)
	var d_shell: float = p.next()
	var d_eros: float = p.next()
	var d_buy: float = p.next()
	var pick_i: int = -1
	if d_buy < 0.01:
		pick_i = floori(p.next() * 3.0)
	sim.tick_second()
	# capital: production then the military shell (0.8·0.4 = 0.32, TS:398/407)
	approx(float(sim.cities[0]["hp"]), minf(100.0, 99.9 + 0.5) - 0.32,
		"capital hp: production +0.5 capped, then shell −aggression·0.4")
	# influence: heal min(0, +0.12), then erosion max(−100, −1.5) if drawn
	var exp_cap_inf: float = minf(0.0, -99.0 + 0.12)
	if d_eros < 0.03:
		exp_cap_inf = maxf(-100.0, exp_cap_inf - 1.5)
	approx(float(sim.cities[0]["influence"]), exp_cap_inf, "unrest heal +0.12 then culture erosion −1.5 floored (TS:400/414)")
	approx(float(sim.cities[0]["pop"]), 8.02, "pop +0.02 (TS:397)")
	if d_shell < 0.02:
		eq(_toasted(rec, "Khorate Dominion shells your capital!"), true, "shell toast names the rival (TS:409)")
		eq(rec["shakes"].size(), 1, "shell camShakeFor(3, 0.3) rides the same chance (TS:410)")
		eq(float(rec["shakes"][0][0]), 3.0, "shake 3")
		eq(float(rec["shakes"][0][1]), 0.3, "0.3")
	else:
		eq(rec["shakes"].size(), 0, "no shake without the toast (TS:408-411 — both ride the chance)")
	# per-city influence: hearts (culture·0.014 + econ·0.004 − 0.02 = +0.034 at
	# 3/3 — R14 raised the culture weight 0.006 → 0.014, the pacifist-viability
	# knob; the econ weight and the unrest baseline stay TS-verbatim TS:433)
	# composed with the buy −2 wherever it lands (TS:433-434/422)
	var exp_inf: Array = [exp_cap_inf, -59.966, -59.966, -59.966]
	if pick_i >= 0:
		exp_inf[pick_i] -= 2.0
	for i in 4:
		approx(float(sim.cities[i]["influence"]), exp_inf[i], "city %d influence (hearts/erosion/buy composed)" % i)
	# r3's own city: the pool excluded it → hearts only — the `rival.id ===
	# t.owner ? 0 : −2` check is always −2 by construction (TS:422 quirk) but
	# can never hit its own city
	approx(float(sim.cities[3]["pop"]), 6.05, "economy rival pop +0.05 UNCAPPED (TS:418 — no min(30), quirk kept)")
	# culture/economy rivals don't grow pop (only economy does)
	eq(float(sim.cities[1]["pop"]), 6.0, "military rival pop untouched")
	eq(float(sim.cities[2]["pop"]), 6.0, "culture rival pop untouched")
	# karma drift (culture − mil)·0.0004 = −0.0004 (TS:439)
	approx(float(m["ctx"].karma), -0.0004, "karma drift")


func test_tick_military_shell_floor() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# 19.6 + 0.5 production = 20.1 → shell max(20, 20.1−0.32) = 20 → the floor bites
	sim.cities[0]["hp"] = 19.6
	sim.tick_second()
	eq(float(sim.cities[0]["hp"]), 20.0, "shell floor max(20, hp − aggression·0.4) (TS:407)")


func test_tick_burning() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# your city: burning −= 1 in the owner branch AND −= 0.5 in the tail
	# (TS:399 + :427 — the double-decrement quirk); hp −2 in the tail after
	# the +0.5 production
	sim.cities[0]["burning"] = 6.0
	sim.cities[0]["hp"] = 50.0
	sim.cities[1]["burning"] = 6.0
	sim.tick_second()
	approx(float(sim.cities[0]["burning"]), 4.5, "your burning −1 then −0.5 (TS:399/427)")
	approx(float(sim.cities[0]["hp"]), 48.18, "your burning city: 50 + 0.5 production, tail −2, shell −0.32 (TS:398/407/427)")
	approx(float(sim.cities[1]["burning"]), 5.5, "enemy burning −0.5 only (TS:427)")
	approx(float(sim.cities[1]["hp"]), 98.0, "enemy burning hp −2")
	# the 5 floor (TS:427)
	sim.cities[1]["hp"] = 6.0
	sim.cities[1]["burning"] = 6.0
	sim.tick_second()
	eq(float(sim.cities[1]["hp"]), 5.0, "burning hp floor 5")


func test_tick_flips_and_revolt() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# flip at influence ≥ 100 — NO hp floor in the tick flip (TS:442-447),
	# unlike resolveArmada's max(hp, 40) — pin the difference
	sim.cities[1]["influence"] = 100.0
	sim.cities[1]["hp"] = 33.0
	sim.tick_second()
	eq(String(sim.cities[1]["owner"]), "you", "flip at 100 (TS:443-444)")
	eq(float(sim.cities[1]["hp"]), 33.0, "tick flip does NOT touch hp (no 40 floor here)")
	ok(_heard(rec, "levelup"), "levelup audio (TS:445)")
	eq(String(rec["banners"][0]["title"]), "KHORA JOINS YOUR PLANETARY STATE", "flip banner (TS:446)")
	eq(String(rec["banners"][0]["kind"]), "reward", "flip banner kind")
	# revolt: the unrest-heal step (+0.12) runs EARLIER in the tick — a city
	# at −100 heals to −99.88 which still sits ≤ the −99.8 gate (the
	# heal-order comment, TS:448-450) → revolts back to its former rival BY
	# CITY ID
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -100.0
	sim.tick_second()
	eq(String(sim.cities[2]["owner"]), "r2", "revolt returns the city to its former owner (id lookup, TS:452)")
	eq(float(sim.cities[2]["influence"]), -100.0, "revolt resets influence −100 (TS:454)")
	eq(String(rec["banners"][1]["title"]), "Vex REVOLTS!", "revolt banner (TS:453)")
	eq(String(rec["banners"][1]["kind"]), "danger", "revolt banner kind")
	# just above the gate → no revolt
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -99.7
	sim.tick_second()
	eq(String(sim.cities[2]["owner"]), "you", "−99.7 heals to −99.58 — above the −99.8 gate, no revolt")
	# capital revolt: id 'you' matches NO rival → the rivals[0] fallback (TS:452 ??)
	sim.cities[0]["influence"] = -100.0
	sim.tick_second()
	eq(String(sim.cities[0]["owner"]), "r1", "capital revolt falls back to rivals[0] (TS:452)")
	eq(float(sim.cities[0]["influence"]), -100.0, "revolt influence reset")
	eq(String(rec["banners"][2]["title"]), "%sgrad REVOLTS!" % String(m["ctx"].player_name), "capital revolt banner")


# ---- chaos hooks (TS:459-526) -----------------------------------------------------

func test_chaos_hook_earthquake() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var idx: int = floori(_probe(sim).next() * 4.0)  # TS:462 rng.pick(cities)
	sim.earthquake()
	var c: Dictionary = sim.cities[idx]
	eq(float(c["hp"]), 70.0, "picked city hp max(10, −30) (TS:463)")
	eq(float(c["burning"]), 4.0, "burning 4 (TS:464)")
	eq(String(rec["toasts"][0][0]), "Earthquake damages %s!" % String(c["name"]), "toast (TS:467)")
	eq(String(rec["toasts"][0][1]), "bad", "kind")
	eq(String(rec["toasts"][0][2]), "🫨", "icon")
	eq(rec["shakes"].size(), 1, "camShakeFor(8, 1) (TS:465)")
	eq(float(rec["shakes"][0][0]), 8.0, "mag 8")
	eq(float(rec["shakes"][0][1]), 1.0, "dur 1")
	ok(_heard(rec, "quake"), "quake audio (TS:466)")
	for i in 4:
		if i != idx:
			eq(float(sim.cities[i]["hp"]), 100.0, "city %d untouched" % i)


func test_chaos_hook_rebellion() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# only the capital yours → the id-quirk filter empties the pool → return
	# BEFORE the draw (TS:470-472)
	sim.rebellion()
	eq(rec["toasts"].size(), 0, "no rebellion without a conquered city (capital excluded by ID, TS:471)")
	# conquer city 2 → pool [cities[2]] → deterministic pick
	sim.cities[2]["owner"] = "you"
	sim.rebellion()
	eq(float(sim.cities[2]["influence"]), -100.0, "influence max(−100, −60−40) (TS:474)")
	eq(String(rec["toasts"][0][0]), "Unrest in Vex! (-40 influence)", "toast (TS:475)")
	eq(String(rec["toasts"][0][1]), "bad", "kind")
	eq(String(rec["toasts"][0][2]), "🔥", "icon")


func test_chaos_hook_golden_age() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# capital + a conquered city: hp 100, influence +15 clamped, pop +2 UNCAPPED
	# (TS:480 — tickSecond caps pop, goldenAge does not — quirk kept)
	sim.cities[0]["pop"] = 29.5
	sim.cities[0]["influence"] = 90.0
	sim.cities[1]["hp"] = 55.0  # enemy city — must stay untouched
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = -95.0
	sim.cities[2]["hp"] = 40.0
	sim.golden_age()
	eq(float(sim.cities[0]["hp"]), 100.0, "hp 100")
	approx(float(sim.cities[0]["influence"]), 100.0, "influence +15 clamped at 100")
	approx(float(sim.cities[0]["pop"]), 31.5, "pop +2 uncapped (TS:480 quirk)")
	approx(float(sim.cities[2]["influence"]), -80.0, "conquered city +15")
	eq(float(sim.cities[2]["hp"]), 100.0, "conquered hp 100")
	eq(float(sim.cities[1]["hp"]), 55.0, "enemy city untouched")
	eq(String(rec["toasts"][0][0]), "Golden age! Your cities flourish.", "toast (TS:482)")
	eq(String(rec["toasts"][0][1]), "good", "kind")
	eq(String(rec["toasts"][0][2]), "✨", "icon")


func test_chaos_hook_rival_war() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var idx: int = floori(_probe(sim).next() * 3.0)  # TS:486 rng.pick(rivals)
	sim.rival_war()
	eq(float(sim.cities[0]["hp"]), 75.0, "capital hp max(15, −25) (TS:488)")
	var r: Dictionary = sim.rivals[idx]
	eq(String(rec["banners"][0]["title"]), "%s DECLARES WAR" % String(r["name"]).to_upper(), "banner title (TS:489)")
	eq(String(rec["banners"][0]["subtitle"]), "your capital is shelled", "banner subtitle")
	eq(String(rec["banners"][0]["kind"]), "danger", "banner kind")
	eq(rec["shakes"][0], [6.0, 0.8], "camShakeFor(6, 0.8) (TS:491)")
	ok(_heard(rec, "alarm"), "alarm audio (TS:490)")


func test_chaos_hook_rival_surge() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.rival_surge_begin()
	eq(String(rec["toasts"][0][0]), "A rival golden age! Their forges and fleets swell.", "surge begin toast (TS:497)")
	eq(String(rec["toasts"][0][1]), "bad", "kind")
	eq(String(rec["toasts"][0][2]), "🏆", "icon")
	# tick(1.0): military −aggression·0.12·dt on the capital; culture −1.5 at
	# chance 0.009·dt; economy pop min(30, +0.015·dt) (TS:500-515)
	var d_eros: float = _probe(sim).next()
	sim.rival_surge_tick(1.0)
	approx(float(sim.cities[0]["hp"]), 100.0 - 0.8 * 0.12, "military surge shell ×1.3 (TS:506)")
	if d_eros < 0.009:
		approx(float(sim.cities[0]["influence"]), 98.5, "culture surge erosion −1.5 (TS:509)")
	else:
		eq(float(sim.cities[0]["influence"]), 100.0, "no erosion on the seeded chance")
	approx(float(sim.cities[3]["pop"]), 6.015, "economy surge pop +0.015·dt (TS:512)")
	sim.cities[3]["pop"] = 29.99
	sim.rival_surge_tick(1.0)
	eq(float(sim.cities[3]["pop"]), 30.0, "surge pop capped 30 (TS:512)")


func test_chaos_hook_trade_winds() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.trade_winds_begin()
	eq(String(rec["toasts"][0][0]), "Trade winds! Every market on the planet hums.", "begin toast (TS:520)")
	eq(String(rec["toasts"][0][1]), "good", "kind")
	eq(String(rec["toasts"][0][2]), "⛵", "icon")
	# tick: regenT += dt·0.2 + all pops +0.008·dt (TS:523-525)
	sim.trade_winds_tick(1.0)
	approx(float(sim.regenT), 0.2, "regenT += dt·0.2 (TS:524)")
	approx(float(sim.cities[0]["pop"]), 8.008, "pop +0.008·dt (your city)")
	approx(float(sim.cities[2]["pop"]), 6.008, "pop +0.008·dt (enemy city)")
	# the +20% share feeds the NORMAL 6 s regen check (TS:524 comment)
	sim.mil = 2.0
	sim.culture = 3.0
	sim.econ = 3.0
	sim.regenT = 5.9
	sim.trade_winds_tick(1.0)  # regenT 6.1 — past the gate
	sim.update(1.0, _inp())    # regenT 7.1 ≥ 6 → fires into lastRaised ('mil')
	eq(float(sim.mil), 3.0, "the trade-wind share feeds the normal 6 s regen check (TS:524)")


# ---- persist / restore (TS:132-173) -----------------------------------------------

func test_persist_restore_roundtrip() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# mutate: conquer city 2, spend sliders, move lastRaised
	sim.cities[2]["owner"] = "you"
	sim.cities[2]["influence"] = 55.0
	sim.cities[2]["hp"] = 70.0
	sim.cities[2]["pop"] = 12.0
	sim.mil = 6.0
	sim.culture = 2.0
	sim.econ = 2.0
	sim.lastRaised = "econ"
	sim.persist_state()
	# blob shape (TS:135-142)
	var blob: Dictionary = _blob(ctx)
	eq(blob["cities"].size(), 4, "blob cities 4")
	eq(float(blob["mil"]), 6.0, "blob mil")
	eq(float(blob["culture"]), 2.0, "blob culture")
	eq(float(blob["econ"]), 2.0, "blob econ")
	eq(bool(blob["victoryFired"]), false, "blob victoryFired")
	eq(String(blob["lastRaised"]), "econ", "blob lastRaised")
	var b2: Dictionary = blob["cities"][2]
	eq(String(b2["id"]), "r2", "blob city id")
	eq(String(b2["owner"]), "you", "blob city owner")
	eq(float(b2["influence"]), 55.0, "blob city influence")
	eq(float(b2["hp"]), 70.0, "blob city hp")
	eq(float(b2["pop"]), 12.0, "blob city pop")
	# round trip into a FRESH sim on the SAME context (the CONTINUE path)
	var m2 := _mk_sim(SEED, "normal", ctx)
	var sim2: Variant = m2["sim"]
	eq(float(sim2.mil), 4.0, "fresh sim pre-restore mil")
	ok(sim2.restore_state(), "restore returns true (TS:171)")
	eq(String(sim2.cities[2]["owner"]), "you", "restored owner")
	approx(float(sim2.cities[2]["influence"]), 55.0, "restored influence")
	approx(float(sim2.cities[2]["hp"]), 70.0, "restored hp")
	approx(float(sim2.cities[2]["pop"]), 12.0, "restored pop")
	eq(float(sim2.mil), 6.0, "restored mil")
	eq(float(sim2.culture), 2.0, "restored culture")
	eq(float(sim2.econ), 2.0, "restored econ")
	eq(String(sim2.lastRaised), "econ", "restored lastRaised (the TS:169-170 first-drip pin)")
	eq(bool(sim2.victoryFired), false, "restored victoryFired")
	# on_exit persists (TS:130)
	sim2.mil = 1.0
	sim2.on_exit()
	eq(float(_blob(ctx)["mil"]), 1.0, "on_exit → persist_state (TS:130)")


func test_restore_guards() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# no blob → false (TS:148)
	eq(bool(sim.restore_state()), false, "no blob → false")
	# length mismatch → false, state untouched (TS:154)
	ctx.flags["civState"] = JSON.stringify({"cities": [{"id": "you"}, {"id": "r1"}, {"id": "r2"}], "mil": 5.0})
	eq(bool(sim.restore_state()), false, "length mismatch → false")
	eq(float(sim.mil), 4.0, "state untouched on reject")
	# parse failure → false (the TS catch, TS:172)
	ctx.flags["civState"] = "{not json"
	eq(bool(sim.restore_state()), false, "parse failure → false")
	# owner sanitize: an unknown owner is dropped (TS:160)
	var ok_blob: Dictionary = {"cities": [
		{"id": "you", "owner": "you", "influence": 100.0, "hp": 100.0, "pop": 8.0},
		{"id": "r1", "owner": "hacker", "influence": -60.0, "hp": 100.0, "pop": 6.0},
		{"id": "r2", "owner": "r2", "influence": -60.0, "hp": 100.0, "pop": 6.0},
		{"id": "r3", "owner": "r3", "influence": -60.0, "hp": 100.0, "pop": 6.0},
	], "mil": 4.0, "culture": 3.0, "econ": 3.0, "victoryFired": false, "lastRaised": "mil"}
	ctx.flags["civState"] = JSON.stringify(ok_blob)
	ok(sim.restore_state(), "valid blob restores")
	eq(String(sim.cities[1]["owner"]), "r1", "unknown owner dropped → current owner kept (TS:160)")
	# corrupt values: non-numeric keep the current value; clamps apply (TS:161-167)
	var bad_blob: Dictionary = {"cities": [
		{"id": "you", "owner": "you", "influence": "50", "hp": 250.0, "pop": 0},
		{"id": "r1", "owner": "r1", "influence": 200.0, "hp": 1.0, "pop": 99.0},
		{"id": "r2", "owner": "r2", "influence": -60.0, "hp": 100.0, "pop": 6.0},
		{"id": "r3", "owner": "r3", "influence": -60.0, "hp": 100.0, "pop": 6.0},
	], "mil": 50.0, "culture": "7", "econ": -3.0, "victoryFired": 1, "lastRaised": "bogus"}
	ctx.flags["civState"] = JSON.stringify(bad_blob)
	ok(sim.restore_state(), "corrupt blob still restores (guarded)")
	eq(float(sim.cities[0]["influence"]), 100.0, "non-numeric influence → current kept (Number.isFinite, TS:161)")
	eq(float(sim.cities[0]["hp"]), 100.0, "hp clamp ≤ 100")
	eq(float(sim.cities[0]["pop"]), 1.0, "pop clamp ≥ 1")
	eq(float(sim.cities[1]["influence"]), 100.0, "influence clamp ≤ 100")
	eq(float(sim.cities[1]["hp"]), 5.0, "hp clamp ≥ 5")
	eq(float(sim.cities[1]["pop"]), 30.0, "pop clamp ≤ 30")
	eq(float(sim.mil), 10.0, "mil clamp ≤ 10")
	eq(float(sim.culture), 3.0, "non-numeric culture → current kept")
	eq(float(sim.econ), 0.0, "econ clamp ≥ 0")
	eq(bool(sim.victoryFired), false, "victoryFired STRICT === true — a 1 restores false (TS:168)")
	eq(String(sim.lastRaised), "mil", "unknown lastRaised → current kept (TS:170)")
	# strict true restores true
	bad_blob["victoryFired"] = true
	bad_blob["lastRaised"] = "culture"
	ctx.flags["civState"] = JSON.stringify(bad_blob)
	ok(sim.restore_state(), "restore again")
	eq(bool(sim.victoryFired), true, "victoryFired true restores true")
	eq(String(sim.lastRaised), "culture", "lastRaised 'culture' restores")
	# cities match BY ID, not order (TS:156-158) — swap two blob entries
	var shuffled: Dictionary = ok_blob.duplicate(true)
	var cs: Array = shuffled["cities"]
	var tmp: Dictionary = cs[0]
	cs[0] = cs[3]
	cs[3] = tmp
	ctx.flags["civState"] = JSON.stringify(shuffled)
	ok(sim.restore_state(), "shuffled blob restores")
	eq(float(sim.cities[3]["influence"]), -60.0, "id-matched restore (order-independent, TS:157)")
	eq(String(sim.cities[0]["owner"]), "you", "capital still matched by id")


# ---- onEnter semantics (TS:113-130) ------------------------------------------------

func test_on_enter_semantics() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.on_enter()
	eq(rec["moods"], ["civ"], "audio.setMood('civ') via hook (TS:119)")
	eq(rec["insets"], [150.0], "toastInset 150 — clears the ruler portrait (TS:120)")
	eq(rec["objectives"], [OBJECTIVE], "showObjective (TS:121)")
	eq(rec["gotos"].size(), 0, "no brick go_to on a fresh run")
	# C1 rebuild gate: same seed → the scheduler survives (TS:114-118)
	var old: Variant = sim.chaos
	sim.on_enter()
	ok(is_same(sim.chaos, old), "same world seed → no deck rebuild")
	# a different world seed rebuilds the deck + updates deckSeed
	m["ctx"].world["seed"] = SEED + 1
	sim.on_enter()
	ok(not is_same(sim.chaos, old), "world seed changed → deck rebuilt (C1, TS:115-117)")
	eq(int(sim.deckSeed), SEED + 1, "deckSeed updated (TS:117)")
	# the deck landed in task 2: the rebuild folds the CURRENT world in
	eq(sim.chaos.defs.size(), CivEvents.make_civ_chaos_events(m["ctx"].world).size(),
			"rebuilt deck = the factory deck for the current world")


func test_brick_hardening() -> void:
	# a restored run that ALREADY unified must go to space (TS:123-128)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	for i in 4:
		sim.cities[i]["owner"] = "you"
	sim.victoryFired = true
	sim.persist_state()
	var m2 := _mk_sim(SEED, "normal", m["ctx"])
	m2["sim"].on_enter()
	eq(m2["rec"]["gotos"].size(), 1, "brick gate fires on a unified restore")
	eq(String(m2["rec"]["gotos"][0][0]), "space", "go_to 'space'")
	eq(String(m2["rec"]["gotos"][0][1]["title"]), "THE BLACK OCEAN", "brick title (TS:127)")
	eq(String(m2["rec"]["gotos"][0][1]["sub"]), "a planet was never going to be enough", "brick sub")
	# victoryFired true but a rival city remains → NO brick
	var m3 := _mk_sim()
	m3["sim"].victoryFired = true
	m3["sim"].persist_state()
	var m4 := _mk_sim(SEED, "normal", m3["ctx"])
	m4["sim"].on_enter()
	eq(m4["rec"]["gotos"].size(), 0, "no brick while a city stays rival")
	# all owned but victoryFired false → NO brick (both conditions, TS:126)
	var m5 := _mk_sim()
	for i in 4:
		m5["sim"].cities[i]["owner"] = "you"
	m5["sim"].persist_state()
	var m6 := _mk_sim(SEED, "normal", m5["ctx"])
	m6["sim"].on_enter()
	eq(m6["rec"]["gotos"].size(), 0, "no brick without victoryFired")


# ---- victory (TS:289-296) ----------------------------------------------------------

func test_victory_path() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# not all owned → no victory (TS:290-291)
	sim.update(1.0 / 60.0, _inp())
	eq(bool(sim.victoryFired), false, "no victory while rivals hold cities")
	eq(int(rec["saves"]), 0, "no save_all")
	# unify → victory fires ONCE (TS:289-296)
	for i in 4:
		sim.cities[i]["owner"] = "you"
	sim.update(1.0 / 60.0, _inp())
	eq(bool(sim.victoryFired), true, "victoryFired latches")
	eq(int(rec["saves"]), 1, "save_all flushes the board (TS:293)")
	ok(_heard(rec, "ascend"), "ascend audio (TS:294 — audio deferred)")
	eq(rec["gotos"].size(), 1, "go_to space")
	eq(String(rec["gotos"][0][0]), "space", "stage 'space'")
	eq(String(rec["gotos"][0][1]["title"]), "THE BLACK OCEAN", "victory title")
	eq(String(rec["gotos"][0][1]["sub"]), "a planet was never going to be enough", "victory sub")
	# second update: latched — no double save/go_to (TS:291 !victoryFired)
	sim.update(1.0 / 60.0, _inp())
	eq(int(rec["saves"]), 1, "victory fires once")
	eq(rec["gotos"].size(), 1, "no second go_to")


# ---- chaos scheduler wiring (TS:258-277) -------------------------------------------

func test_chaos_scheduler_wiring() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var ctx: Variant = m["ctx"]
	# the scheduler holds ONLY the probe def (task 2 shipped the real deck —
	# swapping it out keeps these pins hermetic) exercising the TS:258-277
	# wiring end to end: warn → banner+alarm; apply → earthquake +
	# chaos-kind banner + addChaos(0.03) + noteChaosEvent
	rec["gap_bias_out"] = 0.001  # effective gap ≈ 26·0.001·(1−0.45·0.15) ≈ 0.024 s
	sim.chaos.defs = [{
		"id": "tq", "name": "TestQuake", "warn": "the ground grumbles",
		"weight": func(_c): return 10.0, "duration": [1.0, 1.0],
		"apply": func(stage_v, _rng_v): stage_v.earthquake(),
	}]
	sim.update_chaos(1.0)
	# warn phase: hasActiveChaos counts ACTIVE only (TS:70-72)
	eq(bool(sim.has_active_chaos()), false, "warn phase is not active (TS:70-72)")
	eq(String(rec["banners"][0]["title"]), "the ground grumbles", "onWarn banner title (TS:266)")
	eq(String(rec["banners"][0]["kind"]), "danger", "onWarn kind")
	eq(float(rec["banners"][0]["ttl"]), 2.4, "onWarn ttl 2.4 (TS:266)")
	ok(_heard(rec, "alarm"), "onWarn alarm 0.5 (TS:267)")
	# 2.5 s warn window at warnScale 1.0 → converts on the 4th update
	for i in 3:
		sim.update_chaos(1.0)
	eq(bool(sim.has_active_chaos()), true, "warn → active conversion")
	# onApply: the def's apply ran (earthquake damaged a city), chaos banner,
	# meter +0.03, storyteller note with ctx.playtime
	var damaged := 0
	for c in sim.cities:
		if float(c["burning"]) == 4.0:
			damaged += 1
	eq(damaged, 1, "apply hand-off ran (earthquake via the stage ref, TS:270)")
	var n_banners: int = rec["banners"].size()
	eq(String(rec["banners"][n_banners - 1]["title"]), "TestQuake", "onApply banner title (TS:271)")
	eq(String(rec["banners"][n_banners - 1]["kind"]), "chaos", "onApply kind 'chaos'")
	approx(float(ctx.chaos), 0.18, "addChaos(0.03) on apply (TS:272)")
	eq(rec["notes"].size(), 1, "noteChaosEvent(ctx.playtime) (TS:275)")
	approx(float(rec["notes"][0]), 0.0, "note carries ctx.playtime")
	# duration 1.0 → the event ends on the next update; cooldown 20 blocks a re-fire
	sim.update_chaos(1.0)
	eq(bool(sim.has_active_chaos()), false, "event ended after its duration")
	sim.update_chaos(1.0)
	eq(bool(sim.has_active_chaos()), false, "cooldown 20 blocks the immediate re-fire")
	# the warnScale hook read scales the warn window: 2.5 × 1.6 = 4.0 s
	rec["warn_scale_out"] = 1.6
	rec["gap_bias_out"] = 0.001
	sim.chaos.defs = [{  # probe-only again (the real deck waits on the bench)
		"id": "tq2", "name": "TQ2", "warn": "hum",
		"weight": func(_c): return 10.0, "duration": [1.0, 1.0],
		"apply": func(_stage_v, _rng_v): pass,
	}]
	sim.update_chaos(1.0)  # spawn (warn 4.0)
	sim.update_chaos(1.0)
	sim.update_chaos(1.0)
	sim.update_chaos(1.0)  # 3 s in — still warn
	eq(bool(sim.has_active_chaos()), false, "warnScale 1.6 → 4 s window (3 s in, still warn)")
	sim.update_chaos(1.0)  # 4 s — converts
	eq(bool(sim.has_active_chaos()), true, "conversion at the scaled window")


# ---- abilities + camera (TS:280-287, :298-305) --------------------------------------

func test_update_abilities_and_camera() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.econ = 0.0
	sim.update(1.0 / 60.0, _inp())
	var ab: Array = rec["abilities"][rec["abilities"].size() - 1]
	eq(ab.size(), 6, "6 ability entries (TS:298-305)")
	eq(String(ab[0]["key"]), "1", "key '1'")
	eq(String(ab[0]["icon"]), "⚔️", "icon ⚔️")
	ok(not ab[0].has("active"), "cd entries carry NO active key (TS:299-301 undefined semantics)")
	eq(float(ab[0]["cd"]), 0.0, "cd 0")
	eq(String(ab[3]["key"]), "Q/A", "slider entry key Q/A")
	eq(bool(ab[3]["active"]), true, "mil > 0 → active")
	eq(bool(ab[4]["active"]), true, "culture > 0 → active")
	eq(bool(ab[5]["active"]), false, "econ == 0 → inactive")
	# launch → cd shows /5 on the same frame (the launch set it mid-update)
	sim.mil = 5.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit1"]}))
	ab = rec["abilities"][rec["abilities"].size() - 1]
	approx(float(ab[0]["cd"]), 1.0, "attack cd 5/5 = 1 after the launch (TS:299)")
	# cds decay max(0, cd − dt) each frame (TS:182-184)
	sim.update(1.0, _inp())
	sim.update(1.0, _inp())
	ab = rec["abilities"][rec["abilities"].size() - 1]
	approx(float(ab[0]["cd"]), 0.6, "cd decayed 5 − 2 = 3 → 3/5")
	for i in 7:
		sim.update(1.0, _inp())
	ab = rec["abilities"][rec["abilities"].size() - 1]
	eq(float(ab[0]["cd"]), 0.0, "cd floors at 0 (max(0, ·))")
	# camera drift toward the last armada at min(1, dt·1.2) = 1 → snap (TS:280-283)
	approx(float(sim.camX), float(sim.armadas[0]["x"]), "camX tracks the last armada")
	approx(float(sim.camY), float(sim.armadas[0]["y"]), "camY tracks the last armada")
	# drive until the armada resolves (the ~422-away target oscillates until
	# the t > 14 timeout) — the resolve frame already decays once (the filter
	# empties armadas before the camera block) → then 0.5× per second
	# (min(1, dt·0.5) = 0.5 at dt 1, TS:284-287)
	var guard := 0
	while not sim.armadas.is_empty() and guard < 25:
		sim.update(1.0, _inp())
		guard += 1
	ok(sim.armadas.is_empty(), "armada resolved inside the guard")
	var cam_x0: float = float(sim.camX)
	sim.update(1.0, _inp())
	approx(float(sim.camX), cam_x0 * 0.5, "camX decays toward 0 without an armada")


# ---- debug seams --------------------------------------------------------------------

func test_debug_seams() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# debug_set_influence — the bot's victory-leg grant (SET semantics, absolute)
	sim.debug_set_influence(1, 100.0)
	eq(float(sim.cities[1]["influence"]), 100.0, "debug_set_influence sets absolute")
	# a tick flips the granted city through the REAL flip path (hearts → ≥100)
	sim.update(1.0, _inp())
	eq(String(sim.cities[1]["owner"]), "you", "the grant drives the real flip path")
	# + the rest → the victory leg
	sim.debug_set_influence(2, 100.0)
	sim.debug_set_influence(3, 100.0)
	sim.update(1.0, _inp())
	eq(bool(sim.victoryFired), true, "debug grant drives the victory leg")
	# debug_state read surface
	var st: Dictionary = sim.debug_state()
	ok(st.has("cities") and st.has("armadas") and st.has("mil") and st.has("launchCds"),
		"debug_state exposes the core fields")
	# debug_clear_chaos — determinism legs
	rec["gap_bias_out"] = 0.001
	sim.chaos.defs = [{  # probe-only scheduler (the real deck waits on the bench)
		"id": "tq", "name": "TQ", "warn": "",
		"weight": func(_c): return 10.0, "duration": [9.0, 9.0],
		"apply": func(_stage_v, _rng_v): pass,
	}]
	sim.update_chaos(1.0)  # warn "" → falsy → immediate active
	eq(bool(sim.has_active_chaos()), true, "probe event live")
	sim.debug_clear_chaos()
	eq(bool(sim.has_active_chaos()), false, "debug_clear_chaos empties the scheduler")
