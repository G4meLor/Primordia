# Tests for game/civ/civ_events.gd (the civ chaos deck) + the deck wiring in
# civ_sim.gd (the constructor hold, _make_deck, the C1 rebuild gate, and the
# update_chaos ctx the weights roll against).
# TS sources: Spore src/game/civ/civEvents.ts + CivStage.ts (frozen), lines
# cited per pin. Path-based extends + preload-by-path: class_name globals
# don't resolve in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

const Chaos := preload("res://src/game/chaos.gd")
const RngLib := preload("res://src/core/rng.gd")
const CivEvents := preload("res://src/game/civ/civ_events.gd")
const Ctx := preload("res://src/game/context.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC1DE

# Synthetic worlds (a real derive draws 4-6 traits — tests pin exact decks).
# temperament set explicitly so mirror_bucket never surprises.
const W_TRAITLESS := {"seed": 41, "traits": [], "turns": [], "firedTurns": {},
		"revealed": {}, "comboFired": {}, "timers": {}, "temperament": "lean"}
const W_SWIFT := {"seed": 42, "traits": [{"effects": [
		{"kind": "num", "key": "growth_mult", "value": 1.5}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
# growth_mult 1.2 sits AT the gate — TS `> 1.2` is strict, no golden_rival.
const W_GROWTH_EDGE := {"seed": 43, "traits": [{"effects": [
		{"kind": "num", "key": "growth_mult", "value": 1.2}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
const W_CALM := {"seed": 44, "traits": [{"effects": [
		{"kind": "num", "key": "speciation_mult", "value": 0.8}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
# speciation_mult 1.0 sits AT the calm_proxy gate — TS `< 1` is strict.
const W_SPEC_EDGE := {"seed": 45, "traits": [{"effects": [
		{"kind": "num", "key": "speciation_mult", "value": 1.0}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
const W_ALL := {"seed": 46, "traits": [{"effects": [
		{"kind": "num", "key": "growth_mult", "value": 1.5},
		{"kind": "num", "key": "speciation_mult", "value": 0.8}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}


# Civ-sim fixture: recording hooks (missing key = silent no-op in the sim);
# the storyteller-read hooks return the mutable rec values so tests can
# retune pacing without rebuilding.
func _mk_sim(world: Dictionary = W_TRAITLESS, seed_v: int = SEED,
		hooks_extra: Dictionary = {}) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.world = world.duplicate(true)
	var rec: Dictionary = {"toasts": [], "banners": [], "audio": [], "shakes": [],
		"spawns": [], "notes": [], "floats": [],
		"gap_bias_out": 1.0, "mood_out": "test", "warn_scale_out": 1.0}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(now): rec["notes"].append(now),
		"get_gap_bias": func(): return float(rec["gap_bias_out"]),
		"get_mood": func(): return String(rec["mood_out"]),
		"get_warn_scale": func(): return float(rec["warn_scale_out"]),
	}
	hooks.merge(hooks_extra, true)
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CivSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec, "rng": rng}


func _def(deck: Array, id: String) -> Variant:
	for d in deck:
		if String(d["id"]) == id:
			return d
	return null


func _ids(deck: Array) -> Array:
	var out: Array = []
	for d in deck:
		out.append(d["id"])
	return out


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


# ---- the deck (civEvents.ts:10-45 baseline, :47-79 factory) ------------------------

func test_traitless_deck_is_four_defs() -> void:
	# the file-header doctrine: a traitless world gets EXACTLY the baseline 4
	var deck: Array = CivEvents.make_civ_chaos_events(W_TRAITLESS)
	eq(deck.size(), 4, "factory: traitless = exactly the 4 baseline defs")
	eq(_ids(deck), ["quake", "rebellion", "goldenage", "worldwar"], "TS deck order")
	# the sim constructor folds ctx.world into the same deck (TS:109)
	var m := _mk_sim()
	eq(m["sim"].chaos.defs.size(), 4, "sim constructor deck: traitless = 4")
	eq(_ids(m["sim"].chaos.defs), ["quake", "rebellion", "goldenage", "worldwar"],
			"sim constructor deck ids match the factory")
	# the civ stage keeps the factory gap defaults — no TS override
	approx(float(m["sim"].chaos.gap), 26.0, "civ gap stays BASE_GAP 26", 1e-12)
	approx(float(m["sim"].chaos.gap_chaos_scale), 0.45, "gap chaos scale 0.45", 1e-12)


func test_gated_defs_gate_on_the_world() -> void:
	# swift_world: growth_mult > 1.2 adds golden_rival (civEvents.ts:48, :55-64)
	var sdeck: Array = CivEvents.make_civ_chaos_events(W_SWIFT)
	eq(sdeck.size(), 5, "swift_world adds golden_rival")
	var gr: Dictionary = _def(sdeck, "golden_rival")
	ok(gr != null, "golden_rival present")
	if gr != null:
		eq(String(gr["name"]), "🏆 RIVAL GOLDEN AGE", "golden_rival name")
		eq(String(gr["warn"]), "Foreign banners gleam — their forges never cool…",
				"golden_rival warn verbatim")
	# traitless and the AT-threshold world (1.2, strict >) carry none
	ok(_def(CivEvents.make_civ_chaos_events(W_TRAITLESS), "golden_rival") == null,
			"traitless world has no golden_rival")
	ok(_def(CivEvents.make_civ_chaos_events(W_GROWTH_EDGE), "golden_rival") == null,
			"growth_mult 1.2 is NOT > 1.2 (strict gate, TS:48)")

	# calm_veil: calmProxy (speciation_mult < 1) adds trade_winds (:49, :67-77)
	var cdeck: Array = CivEvents.make_civ_chaos_events(W_CALM)
	eq(cdeck.size(), 5, "calm_veil adds trade_winds")
	var tw: Dictionary = _def(cdeck, "trade_winds")
	ok(tw != null, "trade_winds present")
	if tw != null:
		eq(String(tw["name"]), "⛵ TRADE WINDS", "trade_winds name")
		eq(String(tw["warn"]), "Sails crowd every horizon — markets hum…",
				"trade_winds warn verbatim")
	ok(_def(CivEvents.make_civ_chaos_events(W_TRAITLESS), "trade_winds") == null,
			"traitless world has no trade_winds")
	ok(_def(CivEvents.make_civ_chaos_events(W_SPEC_EDGE), "trade_winds") == null,
			"speciation_mult 1.0 is NOT < 1 (strict calm_proxy gate)")

	eq(CivEvents.make_civ_chaos_events(W_ALL).size(), 6,
			"swift + calm = 6 defs (BASELINE + golden_rival + trade_winds)")


func test_def_constants_verbatim() -> void:
	var deck: Array = CivEvents.make_civ_chaos_events(W_ALL)
	# id → [duration lo, hi, cooldown, name, warn?]
	var want := {
		"quake": {"dur": [0.1, 0.1], "cd": 55, "name": "🫨 MEGA-QUAKE",
				"warn": "Seismographs scream across the continent…"},
		"rebellion": {"dur": [0.1, 0.1], "cd": 45, "name": "🔥 UNREST SPREADS"},
		"goldenage": {"dur": [14.0, 20.0], "cd": 80, "name": "✨ GOLDEN AGE"},
		"worldwar": {"dur": [10.0, 10.0], "cd": 70, "name": "💥 WORLD WAR",
				"warn": "Mobilization everywhere. Ultimatums fly…"},
		"golden_rival": {"dur": [30.0, 30.0], "cd": 90, "name": "🏆 RIVAL GOLDEN AGE",
				"warn": "Foreign banners gleam — their forges never cool…"},
		"trade_winds": {"dur": [40.0, 40.0], "cd": 100, "name": "⛵ TRADE WINDS",
				"warn": "Sails crowd every horizon — markets hum…"},
	}
	for id in want:
		var d: Dictionary = _def(deck, id)
		ok(d != null, "def %s present" % id)
		if d == null:
			continue
		var w: Dictionary = want[id]
		var dur: Array = d["duration"]
		eq(dur.size(), 2, "%s duration pair" % id)
		approx(float(dur[0]), float(w["dur"][0]), "%s duration lo" % id, 1e-9)
		approx(float(dur[1]), float(w["dur"][1]), "%s duration hi" % id, 1e-9)
		eq(int(d["cooldown"]), int(w["cd"]), "%s cooldown" % id)
		eq(String(d["name"]), String(w["name"]), "%s name verbatim" % id)
		if w.has("warn"):
			eq(String(d["warn"]), String(w["warn"]), "%s warn verbatim" % id)
		else:
			ok(not d.has("warn"), "%s has no warn (TS surprise hit)" % id)
		ok(d["weight"] is Callable, "%s weight is a Callable" % id)
		ok(d["apply"] is Callable, "%s apply is a Callable" % id)
	# duration BANDS: goldenage is the only ranged def — the two tick variants
	# and the three instants are fixed lo == hi (TS verbatim)
	approx(float(_def(deck, "goldenage")["duration"][1])
			- float(_def(deck, "goldenage")["duration"][0]), 6.0,
			"goldenage band width 6 ([14, 20])", 1e-9)
	for fixed in ["quake", "rebellion", "worldwar", "golden_rival", "trade_winds"]:
		var d: Dictionary = _def(deck, fixed)
		approx(float(d["duration"][1]) - float(d["duration"][0]), 0.0,
				"%s duration is fixed (lo == hi)" % fixed, 1e-9)
	# the two variants carry tick Callables; no civ def carries end (TS has
	# none) and the civ wiring passes no onEnd hook
	ok(_def(deck, "golden_rival")["tick"] is Callable, "golden_rival carries tick")
	ok(_def(deck, "trade_winds")["tick"] is Callable, "trade_winds carries tick")
	for d in deck:
		ok(not d.has("end"), "%s has no end (civEvents.ts has none)" % String(d["id"]))


func test_weight_formulas() -> void:
	var deck: Array = CivEvents.make_civ_chaos_events(W_TRAITLESS)
	# expected values derived HERE from the brief's formulas — never by calling
	# anything but the pure math
	approx(float(_def(deck, "quake")["weight"].call({"chaos": 0.2, "karma": 0.5})),
			0.9, "quake 0.7 + chaos", 1e-12)
	approx(float(_def(deck, "worldwar")["weight"].call({"chaos": 0.2, "karma": 0.5})),
			0.8, "worldwar 0.6 + chaos", 1e-12)
	# rebellion: 0.6 + max(0, -karma) * 0.8 — negative karma pushes UP
	approx(float(_def(deck, "rebellion")["weight"].call({"chaos": 0.0, "karma": -1.0})),
			1.4, "rebellion 0.6 + max(0,-karma)*0.8 at karma -1", 1e-12)
	approx(float(_def(deck, "rebellion")["weight"].call({"chaos": 0.0, "karma": 0.5})),
			0.6, "rebellion positive karma clamps to 0.6", 1e-12)
	approx(float(_def(deck, "rebellion")["weight"].call({"chaos": 0.0, "karma": 0.0})),
			0.6, "rebellion karma 0 -> 0.6", 1e-12)
	# goldenage: 0.6 + max(0, karma) * 0.9 — positive karma pushes UP
	approx(float(_def(deck, "goldenage")["weight"].call({"chaos": 0.0, "karma": 0.5})),
			1.05, "goldenage 0.6 + max(0,karma)*0.9", 1e-12)
	approx(float(_def(deck, "goldenage")["weight"].call({"chaos": 0.0, "karma": -1.0})),
			0.6, "goldenage negative karma clamps to 0.6", 1e-12)
	# golden_rival: 0.5 + chaos * 0.5 (the def exists only on swift worlds, and
	# its weight fn closes over the same gold bool the TS ternary re-checks)
	var gr: Dictionary = _def(CivEvents.make_civ_chaos_events(W_SWIFT), "golden_rival")
	approx(float(gr["weight"].call({"chaos": 0.2})), 0.6, "golden_rival 0.5+chaos*0.5", 1e-12)
	approx(float(gr["weight"].call({"chaos": 0.0})), 0.5, "golden_rival chaos 0 -> 0.5", 1e-12)
	# trade_winds: (0.6 + max(0, karma) * 0.6) * (bless ? 1.3 : 1)
	var tw: Dictionary = _def(CivEvents.make_civ_chaos_events(W_CALM), "trade_winds")
	approx(float(tw["weight"].call({"chaos": 0.0, "karma": 0.5, "mood": "test"})),
			0.9, "trade_winds 0.6 + karma*0.6", 1e-12)
	approx(float(tw["weight"].call({"chaos": 0.0, "karma": -1.0, "mood": "test"})),
			0.6, "trade_winds negative karma clamps to 0.6", 1e-12)
	approx(float(tw["weight"].call({"chaos": 0.0, "karma": 0.5, "mood": "bless"})),
			1.17, "trade_winds bless x1.3", 1e-12)
	approx(float(tw["weight"].call({"chaos": 0.0, "karma": -1.0, "mood": "bless"})),
			0.78, "trade_winds negative karma clamps, bless still leans", 1e-12)
	approx(float(tw["weight"].call({"chaos": 0.0, "karma": 0.5})),
			0.9, "trade_winds missing mood key reads x1.0", 1e-12)


func test_bless_mood_ratio_pin() -> void:
	# the I-q3 pin from the brief: the SAME world, mood toggled, the weight
	# ratio is exactly 1.3 (the storyteller's bless mood leans on gift events;
	# it rides INSIDE the weight fn)
	var tw: Dictionary = _def(CivEvents.make_civ_chaos_events(W_CALM), "trade_winds")
	var plain: float = float(tw["weight"].call({"chaos": 0.1, "karma": 0.5, "mood": "test"}))
	var bless: float = float(tw["weight"].call({"chaos": 0.1, "karma": 0.5, "mood": "bless"}))
	approx(bless / plain, 1.3, "bless/test weight ratio is exactly 1.3", 1e-12)
	# and no other civ def reads the mood (the lean belongs to trade_winds only)
	var deck: Array = CivEvents.make_civ_chaos_events(W_ALL)
	for d in deck:
		if String(d["id"]) == "trade_winds":
			continue
		var a: float = float(d["weight"].call({"chaos": 0.1, "karma": 0.5, "mood": "test"}))
		var b: float = float(d["weight"].call({"chaos": 0.1, "karma": 0.5, "mood": "bless"}))
		approx(a, b, "%s ignores the mood" % String(d["id"]), 1e-12)


# ---- the draw-nothing law (civ_sim.gd header note) ---------------------------------

func test_deck_factory_draws_nothing() -> void:
	# T1 ruling: the factory reads the world genome only — no stage-stream
	# draws at build; the weights fold gold/calm in as Callables
	var ctx: Variant = Ctx.new(SEED)
	var st0: int = ctx.rng.state()
	CivEvents.make_civ_chaos_events(W_ALL)
	eq(ctx.rng.state(), st0, "the factory drew nothing from the context rng")
	# and the sim constructor with a GATED deck adds no stage-rng draws beyond
	# the TS:92-110 sequence (6 city draws, then the chaos branch draw)
	var m := _mk_sim(W_ALL)
	var pr: Variant = Ctx.new(SEED).rng.branch()
	for i in 3:
		pr.range(-120.0, 120.0)
		pr.range(-90.0, 90.0)
	var chaos_state: int = pr.branch().state()
	eq(int(m["sim"].rng.state()), int(pr.state()),
			"stage stream after construction: 6 city draws only")
	eq(int(m["sim"].chaos._rng.state()), int(chaos_state),
			"chaos branch draw position unchanged by the deck build")


# ---- sim wiring (constructor hold + the C1 rebuild gate) ---------------------------

func test_sim_holds_deck_and_c1_rebuild() -> void:
	var m := _mk_sim(W_TRAITLESS)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	eq(_ids(sim.chaos.defs), ["quake", "rebellion", "goldenage", "worldwar"],
			"constructor holds the traitless deck (TS:109)")
	# same seed → the scheduler survives (TS:114-118)
	var old: Variant = sim.chaos
	sim.on_enter()
	ok(is_same(sim.chaos, old), "same world seed → no deck rebuild")
	# a different world seed rebuilds the deck folding the NEW world in
	ctx.world = W_ALL.duplicate(true)
	sim.on_enter()
	ok(not is_same(sim.chaos, old), "world seed changed → deck rebuilt (C1, TS:115-117)")
	eq(sim.chaos.defs.size(), 6, "rebuilt deck folds the new world in")
	ok(_def(sim.chaos.defs, "golden_rival") != null, "golden_rival in the rebuilt deck")
	ok(_def(sim.chaos.defs, "trade_winds") != null, "trade_winds in the rebuilt deck")
	eq(int(sim.deckSeed), int(ctx.world["seed"]), "deckSeed updated (TS:117)")


func test_update_drives_the_real_deck() -> void:
	# the sim's update() runs the scheduler at its TS position (TS:258) — gap 0
	# makes the first frame spawn from the REAL traitless deck
	var m := _mk_sim(W_TRAITLESS)
	var sim: Variant = m["sim"]
	sim.chaos.gap = 0.0
	sim.update(DT, _inp())
	var spawned: bool = sim.chaos.active_events().size() > 0 \
			or sim.chaos.warn_remaining() > 0.0
	ok(spawned, "update() drove the real deck (a def spawned or warned)")


# ---- the two tick variants through the REAL scheduler ------------------------------

func test_golden_rival_tick_wiring() -> void:
	# a live golden_rival calls the sim's rival_surge_tick each frame — the
	# sim-side state moves: the military rival erodes the capital (aggression
	# * 0.12 * dt, TS:506), the economy rival's city pop grows 0.015*dt (TS:512)
	var m := _mk_sim(W_SWIFT)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var gr: Dictionary = _def(sim.chaos.defs, "golden_rival")
	ok(gr != null, "the sim-carried deck has golden_rival on a swift world")
	sim.chaos = Chaos.new(RngLib.new(11), [gr])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.warn_remaining() > 0.0, "golden_rival warns first")
	sim.update_chaos(3.0)  # the 2.5 window closes -> apply
	ok(sim.chaos.is_active("golden_rival"), "golden_rival live")
	ok(_toasted(rec, "rival golden age"), "rivalSurgeBegin routed (toast, TS:497)")
	# deterministic legs: capital hp (military r1, aggression 0.8) and the
	# economy r3 city pop — one update_chaos(2.0) = one tick with dt 2.0
	var cap_hp0: float = float(sim.cities[0]["hp"])
	var econ_pop0: float = float(sim.cities[3]["pop"])
	sim.update_chaos(2.0)
	approx(float(sim.cities[0]["hp"]), cap_hp0 - 0.8 * 0.12 * 2.0,
			"military rival erodes the capital at aggression*0.12*dt", 1e-12)
	approx(float(sim.cities[3]["pop"]), minf(30.0, econ_pop0 + 0.015 * 2.0),
			"economy rival city pop +0.015*dt (surge tick caps, TS:512)", 1e-12)


func test_trade_winds_tick_wiring() -> void:
	# a live trade_winds pushes regenT (+20% share, TS:524) and every city's
	# pop (+0.008*dt, TS:525)
	var m := _mk_sim(W_CALM)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var tw: Dictionary = _def(sim.chaos.defs, "trade_winds")
	ok(tw != null, "the sim-carried deck has trade_winds on a calm world")
	sim.chaos = Chaos.new(RngLib.new(11), [tw])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.warn_remaining() > 0.0, "trade_winds warns first")
	sim.update_chaos(3.0)
	ok(sim.chaos.is_active("trade_winds"), "trade_winds live")
	ok(_toasted(rec, "Trade winds"), "tradeWindsBegin routed (toast, TS:520)")
	var regen0: float = float(sim.regenT)
	var pops: Array = []
	for c in sim.cities:
		pops.append(float(c["pop"]))
	sim.update_chaos(2.0)
	approx(float(sim.regenT), regen0 + 2.0 * 0.2, "regenT += dt * 0.2 (TS:524)", 1e-12)
	for i in sim.cities.size():
		approx(float(sim.cities[i]["pop"]), minf(30.0, pops[i] + 0.008 * 2.0),
				"city %d pop +0.008*dt (TS:525)" % i, 1e-12)


# ---- the update_chaos ctx the weights roll against (the T1-review rider) -----------

func test_update_chaos_ctx_real_values() -> void:
	# The rider's cheap pin: with injected hook lambdas returning known
	# storyteller values, the ctx the scheduler hands the weight fns carries
	# EXACTLY the TS key set {chaos, karma, stageTime, gapMult, mood,
	# warnScale} with the real composed values — and no mirrors/dominance.
	# The recorder def's weight captures it at ROLL time (scheduler-side).
	var m := _mk_sim(W_TRAITLESS, SEED, {
		"get_gap_bias": func() -> float: return 0.001,
		"get_mood": func() -> String: return "bless",
		"get_warn_scale": func() -> float: return 1.6,
	})
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	rec["seen"] = null
	var recorder := func(c) -> float:
		rec["seen"] = (c as Dictionary).duplicate()
		return 1.0
	sim.chaos = Chaos.new(RngLib.new(11), [{
		"id": "rec", "name": "REC", "warn": "",
		"weight": recorder, "duration": [0.1, 0.1],
		"apply": func(_s, _r): pass,
	}])
	ctx.chaos = 0.2
	ctx.karma = -0.4
	sim.time = 12.5
	sim.update_chaos(1.0)
	var seen: Dictionary = rec["seen"]
	ok(seen != null, "the weight fn rolled (gap_bias 0.001 -> immediate roll)")
	if seen != null:
		var keys: Array = seen.keys()
		keys.sort()
		eq(keys, ["chaos", "gapMult", "karma", "mood", "stageTime", "warnScale"],
				"ctx carries exactly the TS key set (no mirrors/dominance)")
		approx(float(seen["chaos"]), 0.2, "ctx.chaos", 1e-12)
		approx(float(seen["karma"]), -0.4, "ctx.karma", 1e-12)
		approx(float(seen["stageTime"]), 12.5, "ctx.stageTime = sim.time", 1e-12)
		approx(float(seen["gapMult"]), 1.0 * 0.001,
				"ctx.gapMult = chaos_gap_mult() * gap_bias", 1e-12)
		eq(String(seen["mood"]), "bless", "ctx.mood via the hook")
		approx(float(seen["warnScale"]), 1.6, "ctx.warnScale via the hook", 1e-12)
	# warn "" is falsy -> immediate active, and a natural no-warn spawn fires
	# NO onApply banner (the TS chaos.ts:146 surprise-hit rule)
	ok(sim.chaos.is_active("rec"), "no-warn def spawns immediate-active")
	eq(rec["banners"], [], "natural no-warn spawn: no apply banner")
	# duration 0.1 elapses on the next update -> end with NO onEnd hook wired:
	# the scheduler tolerates the absent hook (no crash, event gone)
	sim.update_chaos(1.0)
	ok(not sim.chaos.is_active("rec"), "the event ended through the real wiring")
	eq(sim.has_active_chaos(), false, "no active chaos after the end")


func _toasted(rec: Dictionary, fragment: String) -> bool:
	for t in rec["toasts"]:
		if String(t[0]).find(fragment) >= 0:
			return true
	return false
