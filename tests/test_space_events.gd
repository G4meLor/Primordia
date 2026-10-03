# Tests for game/space/space_events.gd (the space chaos deck) + the deck wiring
# in space_sim.gd (the constructor hold, _make_deck, the C1 rebuild gate) + the
# four stage hook bodies the defs route to (nebulaFlip / pirateLullBegin/End /
# solarFlare — TS:812-884, landed with the deck).
# TS sources: Spore src/game/space/spaceEvents.ts + SpaceStage.ts (frozen),
# lines cited per pin. Path-based extends + preload-by-path: class_name globals
# don't resolve in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

const Chaos := preload("res://src/game/chaos.gd")
const RngLib := preload("res://src/core/rng.gd")
const SpaceEvents := preload("res://src/game/space/space_events.gd")
const Ctx := preload("res://src/game/context.gd")
const SpaceSim := preload("res://src/game/space/space_sim.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const GenomeLib := preload("res://src/evo/genome.gd")

const DT := 1.0 / 60.0
const SEED := 0x5CAC

# Synthetic worlds (a real derive draws 4-6 traits — tests pin exact decks).
# temperament set explicitly so mirror_bucket never surprises.
const W_TRAITLESS := {"seed": 51, "traits": [], "turns": [], "firedTurns": {},
		"revealed": {}, "comboFired": {}, "timers": {}, "temperament": "lean"}
# mutation_moon: the wild_mutations flag opens the nebula gate (spaceEvents.ts:50)
const W_WILD := {"seed": 52, "traits": [{"effects": [
		{"kind": "flag", "key": "wild_mutations"}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
# calm_veil: speciation_mult < 1 opens the pirate-lull gate (spaceEvents.ts:51)
const W_CALM := {"seed": 53, "traits": [{"effects": [
		{"kind": "num", "key": "speciation_mult", "value": 0.8}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
# speciation_mult 1.0 sits AT the calm_proxy gate — TS `< 1` is strict.
const W_SPEC_EDGE := {"seed": 54, "traits": [{"effects": [
		{"kind": "num", "key": "speciation_mult", "value": 1.0}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}
const W_ALL := {"seed": 55, "traits": [{"effects": [
		{"kind": "flag", "key": "wild_mutations"},
		{"kind": "num", "key": "speciation_mult", "value": 0.8}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {},
		"timers": {}, "temperament": "lean"}


# Space-sim fixture: recording hooks (missing key = silent no-op in the sim).
func _mk_sim(world: Dictionary = W_TRAITLESS, seed_v: int = SEED) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.world = world.duplicate(true)
	var rec: Dictionary = {"toasts": [], "banners": [], "audio": [], "shakes": [],
		"spawns": [], "floats": [], "bursts": [], "notes": [], "objectives": []}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_show_objective": func(text): rec["objectives"].append(text),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"fx_burst": func(x, y, n, o): rec["bursts"].append([x, y, n, o]),
		"storyteller_note_chaos_event": func(t): rec["notes"].append(t),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = SpaceSim.new(ctx, rng, hooks)
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


func _audio_vols(rec: Dictionary, name_v: String) -> Array:
	var out: Array = []
	for a in rec["audio"]:
		if String(a[0]) == name_v:
			out.append(float(a[1]))
	return out


func _toasted(rec: Dictionary, fragment: String) -> bool:
	for t in rec["toasts"]:
		if String(t[0]).find(fragment) >= 0:
			return true
	return false


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


# ---- the deck (spaceEvents.ts:10-47 baseline, :49-77 factory) ----------------------

func test_traitless_deck_is_four_defs() -> void:
	# the file-header doctrine: a traitless world gets EXACTLY the baseline 4
	var deck: Array = SpaceEvents.make_space_chaos_events(W_TRAITLESS)
	eq(deck.size(), 4, "factory: traitless = exactly the 4 baseline defs")
	eq(_ids(deck), ["pirates", "blackhole", "flare", "tribute"], "TS deck order")
	# the sim constructor folds ctx.world into the same deck (TS:98)
	var m := _mk_sim()
	eq(m["sim"].chaos.defs.size(), 4, "sim constructor deck: traitless = 4")
	eq(_ids(m["sim"].chaos.defs), ["pirates", "blackhole", "flare", "tribute"],
			"sim constructor deck ids match the factory")
	# the space stage keeps the factory gap defaults — no TS override
	approx(float(m["sim"].chaos.gap), 26.0, "space gap stays BASE_GAP 26", 1e-12)
	approx(float(m["sim"].chaos.gap_chaos_scale), 0.45, "gap chaos scale 0.45", 1e-12)


func test_gated_defs_gate_on_the_world() -> void:
	# mutation_moon: worldHas(wild_mutations) adds nebula_flip (TS:50, :56-64)
	var wdeck: Array = SpaceEvents.make_space_chaos_events(W_WILD)
	eq(wdeck.size(), 5, "wild_mutations adds nebula_flip (4 baseline + 1)")
	var nf: Dictionary = _def(wdeck, "nebula_flip")
	ok(nf != null, "nebula_flip present")
	if nf != null:
		eq(String(nf["name"]), "🌌 MUTATION NEBULA", "nebula_flip name")
		eq(String(nf["warn"]), "A rainbow wall of charged gas rolls in…",
				"nebula_flip warn verbatim")
	ok(_def(SpaceEvents.make_space_chaos_events(W_TRAITLESS), "nebula_flip") == null,
			"traitless world has no nebula_flip")

	# calm_veil: calmProxy (speciation_mult < 1) adds pirate_lull (TS:51, :67-75)
	var cdeck: Array = SpaceEvents.make_space_chaos_events(W_CALM)
	eq(cdeck.size(), 5, "calm_veil adds pirate_lull (4 baseline + 1)")
	var pl: Dictionary = _def(cdeck, "pirate_lull")
	ok(pl != null, "pirate_lull present")
	if pl != null:
		eq(String(pl["name"]), "🕊 PIRATE LULL", "pirate_lull name")
		ok(not pl.has("warn"), "pirate_lull is a surprise hit (TS verbatim)")
	ok(_def(SpaceEvents.make_space_chaos_events(W_TRAITLESS), "pirate_lull") == null,
			"traitless world has no pirate_lull")
	ok(_def(SpaceEvents.make_space_chaos_events(W_SPEC_EDGE), "pirate_lull") == null,
			"speciation_mult 1.0 is NOT < 1 (strict calm_proxy gate)")

	# both gates open → the full 6 (the brief's "calm_veil → 6" arithmetic:
	# 4 baseline + nebula_flip + pirate_lull)
	var adeck: Array = SpaceEvents.make_space_chaos_events(W_ALL)
	eq(adeck.size(), 6, "wild + calm = 6 defs")
	eq(_ids(adeck), ["pirates", "blackhole", "flare", "tribute", "nebula_flip",
			"pirate_lull"], "gated variants append AFTER the baseline (TS order)")


func test_def_constants_verbatim() -> void:
	var deck: Array = SpaceEvents.make_space_chaos_events(W_ALL)
	# id → [duration lo, hi, cooldown, name, warn?]
	var want := {
		"pirates": {"dur": [30.0, 30.0], "cd": 55, "name": "☠ PIRATE AMBUSH",
				"warn": "Unfriendly signatures on the scope…"},
		"blackhole": {"dur": [45.0, 45.0], "cd": 90, "name": "🕳 ROGUE BLACK HOLE",
				"warn": "Starlight bends where it should not…"},
		"flare": {"dur": [0.1, 0.1], "cd": 60, "name": "☀️ SOLAR FLARE",
				"warn": "The sun swells and spits…"},
		"tribute": {"dur": [12.0, 12.0], "cd": 100, "name": "📦 VOID EMPIRE TAX",
				"warn": "A shadow shaped like paperwork falls across your ship…"},
		"nebula_flip": {"dur": [0.1, 0.1], "cd": 80, "name": "🌌 MUTATION NEBULA",
				"warn": "A rainbow wall of charged gas rolls in…"},
		"pirate_lull": {"dur": [30.0, 30.0], "cd": 100, "name": "🕊 PIRATE LULL"},
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
	# every space def is a fixed band (lo == hi — TS verbatim)
	for d in deck:
		approx(float(d["duration"][1]) - float(d["duration"][0]), 0.0,
				"%s duration is fixed (lo == hi)" % String(d["id"]), 1e-9)
	# hook-key discipline: NO space def carries tick (spaceEvents.ts has none);
	# pirate_lull is the FIRST deck def with an end hook in the whole port;
	# tribute carries NO end — its apply demands, the STAGE ctx's onEnd
	# (space_sim.gd update_chaos, TS:539-547) punishes unpaid
	for d in deck:
		ok(not d.has("tick"), "%s has no tick (spaceEvents.ts has none)" % String(d["id"]))
		if String(d["id"]) != "pirate_lull":
			ok(not d.has("end"), "%s has no end (the deck/ctx split)" % String(d["id"]))
	ok(_def(deck, "pirate_lull")["end"] is Callable, "pirate_lull carries end (the first)")


func test_weight_formulas() -> void:
	var deck: Array = SpaceEvents.make_space_chaos_events(W_TRAITLESS)
	# expected values derived HERE from the brief's formulas — never by calling
	# anything but the pure math
	approx(float(_def(deck, "pirates")["weight"].call({"chaos": 0.2, "karma": 0.5})),
			0.9, "pirates 0.7 + chaos", 1e-12)
	approx(float(_def(deck, "blackhole")["weight"].call({"chaos": 0.2, "karma": 0.5})),
			0.66, "blackhole 0.5 + chaos*0.8", 1e-12)
	approx(float(_def(deck, "blackhole")["weight"].call({"chaos": 0.0, "karma": 0.0})),
			0.5, "blackhole chaos 0 -> 0.5", 1e-12)
	# flare: the deck's ONE constant weight — ignores the ctx entirely
	approx(float(_def(deck, "flare")["weight"].call({"chaos": 0.9, "karma": -5.0})),
			0.6, "flare constant 0.6", 1e-12)
	# tribute: 0.5 + max(0, -karma) * 0.7 — negative karma pushes UP
	approx(float(_def(deck, "tribute")["weight"].call({"chaos": 0.0, "karma": -1.0})),
			1.2, "tribute 0.5 + max(0,-karma)*0.7 at karma -1", 1e-12)
	approx(float(_def(deck, "tribute")["weight"].call({"chaos": 0.0, "karma": 0.5})),
			0.5, "tribute positive karma clamps to 0.5", 1e-12)
	approx(float(_def(deck, "tribute")["weight"].call({"chaos": 0.0, "karma": 0.0})),
			0.5, "tribute karma 0 -> 0.5", 1e-12)
	# nebula_flip: 0.5 + chaos * 0.7 (the def exists only on wild worlds, and
	# its weight fn closes over the same nebula bool the TS ternary re-checks)
	var nf: Dictionary = _def(SpaceEvents.make_space_chaos_events(W_WILD), "nebula_flip")
	approx(float(nf["weight"].call({"chaos": 0.2})), 0.64, "nebula_flip 0.5+chaos*0.7", 1e-12)
	approx(float(nf["weight"].call({"chaos": 0.0})), 0.5, "nebula_flip chaos 0 -> 0.5", 1e-12)
	# pirate_lull: 0.6 + max(0, karma) * 0.5 — positive karma pushes UP
	var pl: Dictionary = _def(SpaceEvents.make_space_chaos_events(W_CALM), "pirate_lull")
	approx(float(pl["weight"].call({"chaos": 0.0, "karma": 0.8})),
			1.0, "pirate_lull 0.6 + max(0,karma)*0.5 at karma 0.8", 1e-12)
	approx(float(pl["weight"].call({"chaos": 0.0, "karma": -1.0})),
			0.6, "pirate_lull negative karma clamps to 0.6", 1e-12)
	approx(float(pl["weight"].call({"chaos": 0.0, "karma": 0.0})),
			0.6, "pirate_lull karma 0 -> 0.6", 1e-12)


# ---- the draw-nothing law (the M5 ruling, the civ/tribe precedent) -----------------

func test_deck_factory_draws_nothing() -> void:
	# the factory reads the world genome only — no stream draws at build; the
	# weights fold nebula/calm in as Callables
	var ctx: Variant = Ctx.new(SEED)
	var st0: int = ctx.rng.state()
	SpaceEvents.make_space_chaos_events(W_ALL)
	eq(ctx.rng.state(), st0, "the factory drew nothing from the context rng")
	# and the constructor's chaos branch lands where TS:98 put it — the deck
	# build added no draws (the T1 constructor-seeding pin re-proves it live)
	var pr: Variant = Ctx.new(SEED).rng.branch()
	var chaos_state: int = pr.branch().state()  # TS:98 — the SECOND branch
	var m := _mk_sim(W_ALL)
	eq(int(m["sim"].chaos._rng.state()), int(chaos_state),
			"chaos branch draw position unchanged by the deck build")


# ---- the Math.random site (spaceEvents.ts:18) — the in-stream replay pin ----------

func test_pirate_count_draw_in_stream() -> void:
	# TS `2 + Math.floor(Math.random() * 2)` — the port draws the count from
	# the deck rng the scheduler passes into apply (the M4 storm precedent):
	# the draw lands in the chaos stream position. Replay it on a probe cloned
	# from the scheduler's stream state.
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var def: Dictionary = _def(sim.chaos.defs, "pirates")
	var probe: Variant = RngLib.new(1)
	probe.set_state(sim.chaos._rng.state())
	def["apply"].call(sim, sim.chaos._rng)  # the scheduler's OWN rng, in-stream
	var want: int = 2 + floori(probe.next() * 2.0)
	eq(sim.pirates.size(), mini(want, 5), "pirate count = 2 + floor(rng*2)")
	ok(want >= 2 and want <= 3, "count domain {2, 3}")
	eq(int(sim.chaos._rng.state()), int(probe.state()),
			"exactly ONE scheduler-stream draw (the count; the angles ride the stage rng)")


func test_pirate_count_live_through_the_real_scheduler() -> void:
	# the same pin on the LIVE path: warn phase → conversion consumes the
	# [30,30] duration draw + the count draw, in that order, then apply
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "pirates")
	ok(def.has("warn"), "pirates warns first (TS warn key)")
	sim.chaos = Chaos.new(RngLib.new(9), [def])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.warn_remaining() > 0.0, "pirates in warn phase")
	eq(sim.pirates.size(), 0, "warn spawns nothing")
	var probe: Variant = RngLib.new(1)
	probe.set_state(sim.chaos._rng.state())
	sim.update_chaos(3.0)  # the 2.5 window closes -> conversion
	ok(sim.chaos.is_active("pirates"), "pirates live")
	var dur_draw: float = probe.range(30.0, 30.0)  # replay draw 1: the duration
	approx(dur_draw, 30.0, "the [30,30] band replays fixed 30", 1e-9)
	var want: int = 2 + floori(probe.next() * 2.0)  # replay draw 2: the count
	eq(sim.pirates.size(), want, "live conversion count = 2 + floor(rng*2), in-stream order")
	eq(int(sim.chaos._rng.state()), int(probe.state()),
			"conversion consumed exactly the two replayed draws")
	eq(_audio_vols(rec, "alarm"), [0.5, 0.9], "warn alarm 0.5 then spawnPirates alarm 0.9")


# ---- the hook bodies the defs route to (TS:812-884, landed with the deck) ----------

func test_blackhole_apply_routes() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var def: Dictionary = _def(sim.chaos.defs, "blackhole")
	def["apply"].call(sim, sim.rng)
	eq(sim.blackHoles.size(), 1, "spawnBlackHole routed (TS:840-849)")
	eq(float(sim.blackHoles[0]["ttl"]), 45.0, "ttl 45")


func test_solar_flare_body() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "flare")
	# pop ledger BEFORE the flare (independent recomputation of *0.7 / floor 0.5)
	var before: Array = []
	for p in sim.planets:
		if p["eco"] == null:
			continue
		for sp in p["eco"].living():
			before.append([sp, float(sp["pop"])])
	# a near-floor species proves the 0.5 floor
	sim.planets[0]["eco"].living()[0]["pop"] = 0.6
	before[0][1] = 0.6
	sim.shp = 100.0
	def["apply"].call(sim, sim.rng)  # TS solarFlare (:872-884)
	eq(float(sim.shp), 80.0, "shp 100 - 20 = 80")
	eq(float(sim.hurtT), 1.0, "hurtT 1")
	eq(rec["shakes"][-1], [7.0, 0.8], "camShakeFor(7, 0.8)")
	ok(_toasted(rec, "Solar flare scorches your hull!"), "the scorch toast")
	eq(_audio_vols(rec, "boom"), [0.8], "audio boom 0.8")
	for e in before:
		approx(float(e[0]["pop"]), maxf(0.5, float(e[1]) * 0.7),
				"pop *0.7 floored at 0.5 (TS:880)", 1e-9)
	eq(float(before[0][0]["pop"]), 0.5, "the 0.6-pop species floored to 0.5")
	# the Math.max(10, ...) floor: 25 - 20 lands ON the floor
	sim.shp = 25.0
	def["apply"].call(sim, sim.rng)
	eq(float(sim.shp), 10.0, "shp floors at 10 (TS:873)")


func test_nebula_flip_body() -> void:
	# TS nebulaFlip (:812-827): one living world picked, two forced speciations
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# W_TRAITLESS has no nebula_flip — pull the def from the wild deck, run it
	# against the traitless sim (the body is world-independent)
	var def: Dictionary = _def(SpaceEvents.make_space_chaos_events(W_WILD), "nebula_flip")
	var living: Array = sim.planets.filter(func(p): return p["eco"] != null)
	eq(living.size(), 4, "4 living worlds at boot")
	var roster0: int = living[0]["eco"].species.size()
	var st: int = sim.rng.state()
	def["apply"].call(sim, sim.rng)
	# ONE stage-rng draw (the pick, TS:819) — replay it to name the picked world
	var probe: Variant = RngLib.new(1)
	probe.set_state(st)
	var idx: int = floori(probe.next() * float(living.size()))
	eq(int(sim.rng.state()), int(probe.state()),
			"nebulaFlip drew exactly ONE stage-rng draw (the pick)")
	var picked: Dictionary = living[idx]
	# both forceSpeciations succeed on a real roster → made 2
	ok(_toasted(rec, "The nebula seeds 2 new species on %s!" % String(picked["name"])),
			"the made==2 toast names the picked world (TS:823)")
	eq(picked["eco"].species.size(), roster0 + 2,
			"two forced speciations landed on the picked world")
	eq(String(rec["toasts"][-1][1]), "chaos", "toast kind chaos")
	eq(String(rec["toasts"][-1][2]), "🌌", "toast icon")


func test_nebula_flip_dead_rock_and_made_zero() -> void:
	# no living worlds → the dead-rock toast, NO pick draw (TS:815-817)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(SpaceEvents.make_space_chaos_events(W_WILD), "nebula_flip")
	for p in sim.planets:
		p["eco"] = null
	var st: int = sim.rng.state()
	def["apply"].call(sim, sim.rng)
	eq(int(sim.rng.state()), st, "no living worlds → no pick draw")
	ok(_toasted(rec, "washes only dead rock"), "the dead-rock toast")
	# a kin-only roster: both forceSpeciations return null → made 0 → the
	# passes-over toast (TS:820-822)
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var rec2: Dictionary = m2["rec"]
	for p in sim2.planets:
		p["eco"] = null
	var eco: Variant = EcoScript.new(RngLib.new(3))
	eco.add_species(GenomeLib.clone_genome(GenomeLib.default_genome()), 5.0,
			{"kin": true, "name": "kin only"})
	sim2.planets[0]["eco"] = eco
	def["apply"].call(sim2, sim2.rng)  # the single living world is picked
	ok(_toasted(rec2, "nothing takes hold"), "made == 0 → the passes-over toast")
	ok(not _toasted(rec2, "new species on"), "no seeds toast on made 0")


func test_pirate_lull_begin_end_body() -> void:
	# TS pirateLullBegin/End (:829-838) — the FIRST deck def with an end hook:
	# begin sets the lull + the toast; the END hook clears it. Live through the
	# real scheduler (no warn → immediate apply).
	var m := _mk_sim(W_CALM)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "pirate_lull")
	ok(def.has("end"), "the sim-carried def carries the end hook")
	sim.chaos = Chaos.new(RngLib.new(5), [def])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.is_active("pirate_lull"), "pirate_lull live (no warn -> immediate)")
	eq(bool(sim.pirateLull), true, "begin set the lull")
	ok(_toasted(rec, "The pirates pull back — an uneasy quiet falls."),
			"the begin toast (TS:831)")
	eq(String(rec["toasts"][-1][1]), "good", "begin toast good")
	eq(String(rec["toasts"][-1][2]), "🕊", "begin icon")
	sim.update_chaos(31.0)  # duration [30,30] elapses -> END hook fires
	eq(bool(sim.pirateLull), false, "the END hook cleared the lull (TS:836)")
	ok(not sim.chaos.is_active("pirate_lull"), "the event ended")
	# the ledger starts at the def's 100 and decays WITHIN the same update
	# frame (chaos.gd's expiry block runs before the cooldown decay): 100 - 31
	approx(float(sim.chaos._cooldowns.get("pirate_lull", 0.0)), 69.0,
			"cooldown ledger 100 seeded, same-frame decay -31", 1e-9)


func test_pirate_lull_holds_fire() -> void:
	# the lull's whole point: a pirate chewing on the hull does NO damage while
	# pirateLull stands (TS:476 `!this.pirateLull` gate — T2's pirate loop)
	var m := _mk_sim(W_CALM)
	var sim: Variant = m["sim"]
	var def: Dictionary = _def(sim.chaos.defs, "pirate_lull")
	def["apply"].call(sim, sim.rng)  # begin
	eq(bool(sim.pirateLull), true, "the lull stands")
	sim.invuln = 0.0
	sim.pirates.append({"x": sim.sx, "y": sim.sy, "vx": 0.0, "vy": 0.0,
			"hp": 140.0, "gait": 0.0})
	sim.pirateTtl.append(40.0)
	sim.update(DT, _inp())
	eq(float(sim.shp), 100.0, "the lull holds fire — hull untouched")
	sim.pirate_lull_end()
	sim.update(DT, _inp())
	ok(float(sim.shp) < 100.0, "lull lifted → the siege bites again")


# ---- the tribute live path: demand, pay, and the ctx's onEnd unpaid raid -----------

func test_live_tribute_demand_pay_and_onend_raid() -> void:
	# the deck/ctx split, live: the def's apply DEMANDS (banner + alarm); the
	# STAGE ctx's onEnd (T2's update_chaos wiring, TS:539-547) punishes unpaid
	# — the deck def itself carries no end
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "tribute")
	sim.chaos = Chaos.new(RngLib.new(5), [def])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.warn_remaining() > 0.0, "tribute warns first (the paperwork shadow)")
	eq(float(sim.tributeDemand), 0.0, "warn demands nothing yet")
	sim.update_chaos(3.0)  # the 2.5 window closes -> apply
	ok(sim.chaos.is_active("tribute"), "tribute live")
	eq(float(sim.tributeDemand), 60.0, "apply demanded 60 (TS:45 demandTribute(60))")
	var demanded: Array = []
	for b in rec["banners"]:
		if String(b.get("title", "")) == "THE VOID EMPIRE DEMANDS TRIBUTE":
			demanded.append(b)
	eq(demanded.size(), 1, "the demand banner fired")
	if demanded.size() == 1:
		eq(String(demanded[0]["subtitle"]), "pay 60 DNA (press V) or face the raid",
				"banner subtitle verbatim")
		eq(String(demanded[0]["kind"]), "danger", "banner kind danger")
	eq(_audio_vols(rec, "alarm"), [0.5, 1.0], "warn alarm 0.5 then demand alarm 1.0")
	# PAY: V pays the standing demand — the end then fires clean
	m["ctx"].dna = 100
	sim.pay_tribute()
	eq(float(sim.tributeDemand), 0.0, "paid: the demand zeroed")
	eq(int(m["ctx"].dna), 40, "the 60 deducted")
	sim.update_chaos(13.0)  # duration [12,12] elapses -> onEnd, demand 0
	eq(sim.pirates.size(), 0, "a paid tribute ends clean (no raid)")
	ok(not sim.chaos.is_active("tribute"), "the event ended")

	# round 2 on a fresh sim: demand stands UNPAID → the onEnd raid
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var def2: Dictionary = _def(sim2.chaos.defs, "tribute")
	sim2.chaos = Chaos.new(RngLib.new(5), [def2])
	sim2.chaos.gap = 0.0
	sim2.update_chaos(1.0)
	sim2.update_chaos(3.0)
	eq(float(sim2.tributeDemand), 60.0, "the demand stands")
	sim2.update_chaos(13.0)  # end -> onEnd: unpaid → spawnPirates(3)
	eq(sim2.pirates.size(), 3, "unpaid tribute → 3 pirates (TS:543)")
	eq(float(sim2.tributeDemand), 0.0, "the demand zeroed after the raid (TS:544)")


# ---- sim wiring (constructor hold + the C1 rebuild gate) ---------------------------

func test_sim_holds_deck_and_c1_rebuild() -> void:
	var m := _mk_sim(W_TRAITLESS)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	eq(_ids(sim.chaos.defs), ["pirates", "blackhole", "flare", "tribute"],
			"constructor holds the traitless deck (TS:98)")
	# same seed → the scheduler survives (TS:183-186)
	var old: Variant = sim.chaos
	sim.on_enter()
	ok(is_same(sim.chaos, old), "same world seed → no deck rebuild")
	# a different world seed rebuilds the deck folding the NEW world in
	ctx.world = W_ALL.duplicate(true)
	sim.on_enter()
	ok(not is_same(sim.chaos, old), "world seed changed → deck rebuilt (C1, TS:184)")
	eq(sim.chaos.defs.size(), 6, "rebuilt deck folds the new world in")
	ok(_def(sim.chaos.defs, "nebula_flip") != null, "nebula_flip in the rebuilt deck")
	ok(_def(sim.chaos.defs, "pirate_lull") != null, "pirate_lull in the rebuilt deck")
	eq(int(sim.deckSeed), int(ctx.world["seed"]), "deckSeed updated (TS:185)")


func test_update_drives_the_real_deck() -> void:
	# the sim's update() runs the scheduler at its TS position (TS:519) — gap 0
	# makes the first frame spawn (warn or immediate) from the REAL deck
	var m := _mk_sim(W_ALL)
	var sim: Variant = m["sim"]
	sim.chaos.gap = 0.0
	sim.update(DT, _inp())
	var spawned: bool = sim.chaos.active_events().size() > 0 \
			or sim.chaos.warn_remaining() > 0.0
	ok(spawned, "update() drove the real deck (a def spawned or warned)")
