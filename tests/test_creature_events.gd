# Tests for game/creature/creature_events.gd (the creature chaos deck) and the
# ChaosScheduler warn_fn extension that carries night_pack's TS warn-getter.
# TS sources: Spore src/game/creature/creatureEvents.ts + src/game/chaos.ts
# (frozen). Path-based extends + preload-by-path: class_name globals don't
# resolve in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

const Chaos := preload("res://src/game/chaos.gd")
const RngLib := preload("res://src/core/rng.gd")
const CreatureEvents := preload("res://src/game/creature/creature_events.gd")
const Ctx := preload("res://src/game/context.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const StatsLib := preload("res://src/evo/stats.gd")

const DT := 1.0 / 60.0

# TS core.test.ts chaos ctx literal — keys stay TS-verbatim camelCase.
const CTX0 := {"chaos": 0.0, "karma": 0.0, "stageTime": 0.0}


# Fake stage: RefCounted, apply recorder appends into this log.
class FakeStage:
	var events: Array = []


func _rec_apply(id: String) -> Callable:
	return func(stage, _rng): stage.events.append("apply:" + id)


func _w_const(w: float) -> Callable:
	return func(_ctx): return w


## Scripted def: TS ChaosEventDef shape (camelCase keys); cfg merges over the
## defaults, so optional keys (warn/warn_fn/warnS/cooldown/…) are ABSENT
## unless provided — same shape TS defs with omitted fields have.
func _mk(id: String, cfg: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"id": id,
		"name": "Test " + id,
		"weight": _w_const(1.0),
		"duration": [1.0, 1.0],
		"apply": _rec_apply(id),
	}
	d.merge(cfg, true)
	return d


# --- warn_fn (Ruling 13): the TS warn-GETTER port ------------------------------
# TS `get warn()` is re-read at spawn time; a falsy read (undefined) takes the
# no-warn immediate-apply branch. Native: def.warn_fn is a Callable returning
# String (warn phase) or null (immediate). The static `warn` key is untouched.


func test_warn_fn_string_opens_warn_phase() -> void:
	var sch: Variant = Chaos.new(RngLib.new(2), [_mk("wp", {
		"warn_fn": func() -> Variant: return "the pack stirs…",
	})])
	var stg := FakeStage.new()
	ok(sch.trigger("wp", stg), "trigger succeeds")
	ok(stg.events.is_empty(), "warn phase: apply not yet run")
	ok(sch.warn_remaining() > 0.0, "warn window open")
	for i in 60 * 4:
		sch.update(DT, stg, CTX0)
	eq(stg.events, ["apply:wp"], "apply runs after the window")


func test_warn_fn_null_is_immediate() -> void:
	var sch: Variant = Chaos.new(RngLib.new(2), [_mk("wp", {
		"warn_fn": func() -> Variant: return null,
	})])
	var stg := FakeStage.new()
	sch.trigger("wp", stg)
	eq(stg.events, ["apply:wp"], "null warn_fn: immediate apply, no warn phase")
	eq(sch.warn_remaining(), 0.0, "no warn window")


func test_warn_fn_re_read_at_spawn_time() -> void:
	# The getter is evaluated when _spawn runs, not when the def was built —
	# the recorded chaos flip between weight() and spawn() changes the outcome.
	var state := {"hot": false}
	var sch: Variant = Chaos.new(RngLib.new(2), [_mk("wp", {
		"warn_fn": func() -> Variant: return null if bool(state["hot"]) else "warn text",
	})])
	var stg := FakeStage.new()
	state["hot"] = true
	sch.trigger("wp", stg)
	eq(stg.events, ["apply:wp"], "getter read at spawn time")


func test_warn_fn_natural_path_string() -> void:
	# The update() pool path evaluates the getter the same way.
	var sch: Variant = Chaos.new(RngLib.new(2), [_mk("wp", {
		"warn_fn": func() -> Variant: return "warn text",
	})])
	sch.gap = 0.0  # natural path spawns on the first update
	var stg := FakeStage.new()
	sch.update(1.0, stg, CTX0)
	ok(stg.events.is_empty(), "warned via warn_fn on the natural path")
	ok(sch.warn_remaining() > 0.0, "warn window open")
	sch.update(2.5, stg, CTX0)
	eq(stg.events, ["apply:wp"], "applies once the window closes")


func test_static_warn_still_works_unchanged() -> void:
	var sch: Variant = Chaos.new(RngLib.new(2), [_mk("st", {"warn": "…"})])
	var stg := FakeStage.new()
	sch.trigger("st", stg)
	ok(stg.events.is_empty(), "static warn: warn phase")
	ok(sch.warn_remaining() > 0.0, "static warn: window open")


func test_static_warn_empty_string_stays_immediate() -> void:
	# TS `if (def.warn)` — an empty string is falsy -> immediate. The warn_fn
	# extension must not turn the static key into a null-check.
	var sch: Variant = Chaos.new(RngLib.new(2), [_mk("e", {"warn": ""})])
	var stg := FakeStage.new()
	sch.trigger("e", stg)
	eq(stg.events, ["apply:e"], "empty static warn: immediate apply")


func test_warn_fn_warnS_window_still_applies() -> void:
	var sch: Variant = Chaos.new(RngLib.new(2), [_mk("wp", {
		"warn_fn": func() -> Variant: return "w",
		"warnS": 6.0,
	})])
	var stg := FakeStage.new()
	sch.trigger("wp", stg)
	approx(sch.warn_remaining(), 6.0, "per-def warnS window wins over the 2.5 base")


# ---- the deck (creatureEvents.ts): defs + world gating -------------------------
# Synthetic worlds (a real derive draws 4-6 traits — tests pin exact decks).
# temperament is set explicitly so mirror_bucket never surprises.

const SEED := 0xC0FFEE

const W_TRAITLESS := {"seed": 21, "traits": [], "turns": [], "firedTurns": {},
		"revealed": {}, "comboFired": {}, "timers": {}, "temperament": "cradle"}
const W_BOLD := {"seed": 22, "traits": [{"effects": [{"kind": "flag", "key": "raider_bold"}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "cradle"}
const W_TITAN := {"seed": 23, "traits": [{"effects": [
		{"kind": "ecoSeed", "archetype": "titan", "weight": 2.0}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "cradle"}
const W_HERB_SEED := {"seed": 25, "traits": [{"effects": [
		{"kind": "ecoSeed", "archetype": "herbivore", "weight": 1.5}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "cradle"}
const W_WILD := {"seed": 24, "traits": [], "turns": [], "firedTurns": {}, "revealed": {},
		"comboFired": {}, "timers": {}, "temperament": "wildcard"}
const W_BOTH := {"seed": 26, "traits": [{"effects": [{"kind": "flag", "key": "raider_bold"},
		{"kind": "ecoSeed", "archetype": "titan", "weight": 2.0}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "cradle"}


# Creature-sim fixture: recording hooks (missing key = silent no-op in the sim).
func _mk_sim(world: Dictionary = W_TRAITLESS, seed_v: int = SEED,
		hooks_extra: Dictionary = {}) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.world = world.duplicate(true)
	var rec: Dictionary = {"toasts": [], "banners": [], "floats": [], "audio": [],
			"shakes": [], "bursts": [], "spawns": [], "notes": [], "events": []}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(playtime): rec["notes"].append(playtime),
		"context_event": func(ev, data): rec["events"].append([ev, data]),
	}
	hooks.merge(hooks_extra, true)
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _def(deck: Array, id: String) -> Variant:
	for d in deck:
		if String(d["id"]) == id and not d.has("mirrorOf"):
			return d
	return null


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


func _audio_vols(rec: Dictionary, name: String) -> Array:
	var out: Array = []
	for a in rec["audio"]:
		if String(a[0]) == name:
			out.append(float(a[1]))
	return out


func test_traitless_deck_is_nine_defs() -> void:
	var deck: Array = CreatureEvents.make_creature_chaos_events(W_TRAITLESS)
	# R13: the transposon joins the always-gated set — 9 TS defs + 1 redesign def
	eq(deck.size(), 10, "factory: traitless = 8 baseline + predator_convergence + transposon")
	var ids: Array = []
	for d in deck:
		ids.append(d["id"])
	eq(ids, ["volcano", "earthquake", "stampede", "nightraid", "mutationstorm",
			"glorp", "rain", "meteor", "predator_convergence", "transposon"], "TS deck order")
	# the sim constructor folds ctx.world into the same deck (TS:157)
	var m := _mk_sim()
	eq(m["sim"].chaos.defs.size(), 10, "sim constructor deck: traitless = 10")
	approx(float(m["sim"].chaos.gap), 40.0, "creature gap 40")
	approx(float(m["sim"].chaos.gap_chaos_scale), 0.35, "creature gap chaos scale")


func test_gated_defs_gate_on_the_world() -> void:
	var bdeck: Array = CreatureEvents.make_creature_chaos_events(W_BOLD)
	eq(bdeck.size(), 11, "raider_bold adds night_pack")
	var np: Dictionary = _def(bdeck, "night_pack")
	ok(np != null, "night_pack present")
	eq(String(np["name"]), "🐺 NIGHT PACK", "night_pack name")
	ok(np.has("warn_fn") and np["warn_fn"] is Callable,
			"night_pack carries warn_fn (the TS getter port)")
	ok(not np.has("warn"), "night_pack has NO static warn key")
	ok(_def(CreatureEvents.make_creature_chaos_events(W_TRAITLESS), "night_pack") == null,
			"traitless world has no night_pack")

	var tdeck: Array = CreatureEvents.make_creature_chaos_events(W_TITAN)
	eq(tdeck.size(), 11, "old_blood (ecoSeed titan) adds titans_walk")
	var tw: Dictionary = _def(tdeck, "titans_walk")
	ok(tw != null, "titans_walk present")
	eq(String(tw["name"]), "🗿 A TITAN WALKS", "titans_walk name")
	eq(String(tw["warn"]), "The ground trembles in a slow rhythm…", "titan warn verbatim")
	# the gate is the ecoSeed ARCHETYPE scan (seedsTitans), not a number: an
	# herbivore-seeded world never unlocks the titan
	ok(_def(CreatureEvents.make_creature_chaos_events(W_HERB_SEED), "titans_walk") == null,
			"herbivore ecoSeed does not seed titans")

	var wdeck: Array = CreatureEvents.make_creature_chaos_events(W_WILD)
	eq(wdeck.size(), 11, "wildcard adds the rain mirror face")
	var mirrors: Array = []
	for d in wdeck:
		if d.has("mirrorOf"):
			mirrors.append(d)
	eq(mirrors.size(), 1, "exactly one mirror face")
	if mirrors.size() == 1:
		eq(String(mirrors[0]["mirrorOf"]), "rain", "mirrorOf rain")
		eq(String(mirrors[0]["id"]), "rain", "mirror keeps the base id")
		eq(String(mirrors[0]["name"]), "🌧 SOFT RAIN", "mirror keeps the base name")
		ok(not mirrors[0].has("warn"), "the mirror face is a surprise hit (TS verbatim)")
	for d in CreatureEvents.make_creature_chaos_events(W_TRAITLESS):
		ok(not d.has("mirrorOf"), "traitless cradle carries no mirror face")

	eq(CreatureEvents.make_creature_chaos_events(W_BOTH).size(), 12,
			"bold + titan = 12 defs")


func test_def_constants_verbatim() -> void:
	var deck: Array = CreatureEvents.make_creature_chaos_events(W_TRAITLESS)
	# id → [duration, cooldown, name, warn?]
	var want := {
		"volcano": {"dur": [16.0, 24.0], "cd": 60, "name": "🌋 VOLCANIC ERUPTION",
				"warn": "The mountain groans. Ash whispers down…"},
		"earthquake": {"dur": [6.0, 9.0], "cd": 50, "name": "🫨 EARTHQUAKE",
				"warn": "Tiny pebbles begin to hop…"},
		"stampede": {"dur": [14.0, 14.0], "cd": 55, "name": "🐂 STAMPEDE",
				"warn": "The ground drums. Many hooves…"},
		"nightraid": {"dur": [20.0, 20.0], "cd": 70, "name": "🌙 NIGHT RAID",
				"warn": "Eyes open in the dark…"},
		"mutationstorm": {"dur": [10.0, 14.0], "cd": 65, "name": "🧪 MUTATION STORM",
				"warn": "Purple lightning knits new genes in the air…"},
		"glorp": {"dur": [8.0, 12.0], "cd": 80, "name": "🫧 A GLORP APPEARS"},
		"rain": {"dur": [14.0, 20.0], "cd": 45, "name": "🌧 SOFT RAIN"},
		"meteor": {"dur": [0.1, 0.1], "cd": 75, "name": "☄ METEOR CRASH",
				"warn": "A whistling star scratches the sky…"},
		"predator_convergence": {"dur": [18.0, 26.0], "cd": 90,
				"name": "🩸 PREDATORS CONVERGE",
				"warn": "Every hunter on the island turns toward you…"},
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
			ok(not d.has("warn"), "%s has no warn" % id)
		ok(d["weight"] is Callable, "%s weight is a Callable" % id)
		ok(d["apply"] is Callable, "%s apply is a Callable" % id)
	# the gated faces carry the same discipline
	var np: Dictionary = _def(CreatureEvents.make_creature_chaos_events(W_BOLD), "night_pack")
	var npdur: Array = np["duration"]
	approx(float(npdur[0]), 20.0, "night_pack duration lo", 1e-9)
	approx(float(npdur[1]), 20.0, "night_pack duration hi", 1e-9)
	eq(int(np["cooldown"]), 75, "night_pack cooldown")
	var tw: Dictionary = _def(CreatureEvents.make_creature_chaos_events(W_TITAN), "titans_walk")
	var twdur: Array = tw["duration"]
	approx(float(twdur[0]), 26.0, "titans_walk duration lo", 1e-9)
	approx(float(twdur[1]), 30.0, "titans_walk duration hi", 1e-9)
	eq(int(tw["cooldown"]), 140, "titans_walk cooldown")


func test_weight_formulas() -> void:
	var deck: Array = CreatureEvents.make_creature_chaos_events(W_TRAITLESS)
	var c := {"chaos": 0.2, "karma": 0.5, "stageTime": 0.0}
	approx(float(_def(deck, "volcano")["weight"].call(c)), 0.8, "volcano 0.6+chaos", 1e-12)
	approx(float(_def(deck, "earthquake")["weight"].call(c)), 0.74, "earthquake 0.6+chaos*0.7", 1e-12)
	approx(float(_def(deck, "stampede")["weight"].call(c)), 0.82, "stampede 0.7+chaos*0.6", 1e-12)
	approx(float(_def(deck, "mutationstorm")["weight"].call(c)), 0.8, "mutationstorm 0.6+chaos", 1e-12)
	approx(float(_def(deck, "glorp")["weight"].call(c)), 0.55, "glorp 0.4+(1-max(0,karma))*0.3", 1e-12)
	approx(float(_def(deck, "rain")["weight"].call(c)), 0.7, "rain const 0.7", 1e-12)
	approx(float(_def(deck, "meteor")["weight"].call(c)), 0.7, "meteor 0.5+chaos", 1e-12)
	# glorp clamps negative karma to 0 (TS Math.max(0, karma))
	approx(float(_def(deck, "glorp")["weight"].call({"chaos": 0.0, "karma": -1.0})),
			0.7, "glorp negative karma clamps", 1e-12)
	# nightraid: day 0.05; night (1.2+chaos), twist mood x1.3
	approx(float(_def(deck, "nightraid")["weight"].call(c)), 0.05, "nightraid day 0.05", 1e-12)
	var night := {"chaos": 0.2, "karma": 0.0, "night": true, "mood": "test"}
	approx(float(_def(deck, "nightraid")["weight"].call(night)), 1.4, "nightraid night 1.2+chaos", 1e-12)
	var twist := {"chaos": 0.2, "karma": 0.0, "night": true, "mood": "twist"}
	approx(float(_def(deck, "nightraid")["weight"].call(twist)), 1.82, "nightraid twist x1.3", 1e-12)
	# predator_convergence: the ONE dominanceSeverity formula, strict threshold
	var pc: Dictionary = _def(deck, "predator_convergence")
	approx(float(pc["weight"].call({"chaos": 0.0})), 0.0, "no dominance key -> 0", 1e-12)
	approx(float(pc["weight"].call({"dominance": 0.5})), 0.0, "below threshold -> 0", 1e-12)
	approx(float(pc["weight"].call({"dominance": 0.6})), 0.0, "AT the threshold -> 0 (strict >)", 1e-12)
	approx(float(pc["weight"].call({"dominance": 0.61})), 0.612, "just above: 0.6*severity", 1e-12)
	approx(float(pc["weight"].call({"dominance": 1.0})), 1.08, "capped severity x 0.6", 1e-12)
	# titans_walk: 0.35+chaos*0.3 on the gated def
	var tw: Dictionary = _def(CreatureEvents.make_creature_chaos_events(W_TITAN), "titans_walk")
	approx(float(tw["weight"].call(c)), 0.41, "titans_walk 0.35+chaos*0.3", 1e-12)
	# night_pack weight: bold && night ? 1.1+chaos*0.8 : 0 (and it RECORDS chaos)
	var np: Dictionary = _def(CreatureEvents.make_creature_chaos_events(W_BOLD), "night_pack")
	approx(float(np["weight"].call({"chaos": 0.2, "night": true})), 1.26, "night_pack hot night", 1e-12)
	approx(float(np["weight"].call({"chaos": 0.8, "night": false})), 0.0, "night_pack day 0", 1e-12)
	# rain mirror: 0.9 only when the queued mirrors include rain
	var wm: Variant = null
	for d in CreatureEvents.make_creature_chaos_events(W_WILD):
		if d.has("mirrorOf"):
			wm = d
	approx(float(wm["weight"].call({"mirrors": ["rain"]})), 0.9, "mirror queued 0.9", 1e-12)
	approx(float(wm["weight"].call({"mirrors": []})), 0.0, "mirror unqueued 0", 1e-12)
	approx(float(wm["weight"].call({})), 0.0, "missing mirrors key reads 0", 1e-12)


func test_night_pack_warn_box_semantics() -> void:
	var np: Dictionary = _def(CreatureEvents.make_creature_chaos_events(W_BOLD), "night_pack")
	# the weight call records the live chaos; the warn_fn re-reads the box
	np["weight"].call({"chaos": 0.2, "night": true})
	eq(String(np["warn_fn"].call()), "Something moves between the trees…",
			"calm world: the pack warns")
	np["weight"].call({"chaos": 0.8, "night": true})
	eq(np["warn_fn"].call(), null, "hot world (chaos > 0.5): the pack is silent")
	# exactly at 0.5 the warn still shows (strict >, TS verbatim)
	np["weight"].call({"chaos": 0.5, "night": true})
	eq(String(np["warn_fn"].call()), "Something moves between the trees…", "at 0.5: warn")


func test_night_pack_spawn_time_via_scheduler() -> void:
	# Natural-path integration: weight polls the box, then _spawn re-reads it —
	# the Ruling 13 flow over the REAL def (single-def decks isolate the pick).
	# The apply body routes to the CreatureSim, so the recorder replaces it —
	# the warn_fn getter and weight are the surfaces under test here.
	var stg := FakeStage.new()
	var calm: Array = CreatureEvents.make_creature_chaos_events(W_BOLD).filter(
			func(d): return String(d["id"]) == "night_pack")
	calm[0]["apply"] = _rec_apply("night_pack")
	var sch: Variant = Chaos.new(RngLib.new(5), calm)
	sch.gap = 0.0
	sch.update(1.0, stg, {"chaos": 0.2, "karma": 0.0, "stageTime": 0.0, "night": true})
	ok(stg.events.is_empty(), "low chaos: warn phase (getter returns a String)")
	ok(sch.warn_remaining() > 0.0, "warn window open")
	var hot: Array = CreatureEvents.make_creature_chaos_events(W_BOLD).filter(
			func(d): return String(d["id"]) == "night_pack")
	hot[0]["apply"] = _rec_apply("night_pack")
	var sch2: Variant = Chaos.new(RngLib.new(5), hot)
	sch2.gap = 0.0
	sch2.update(1.0, stg, {"chaos": 0.8, "karma": 0.0, "stageTime": 0.0, "night": true})
	eq(stg.events, ["apply:night_pack"], "high chaos: immediate apply, no warn")
	eq(sch2.warn_remaining(), 0.0, "no warn window")


# ---- the helper bodies (CreatureStage.ts:1119-1308) ----------------------------
# Per-def apply scripted through the real deck defs with recording hooks; the
# volcano/earthquake timers ride sim.update's stage clock.

func test_volcano_apply_schedules_five_lava_hazards() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "volcano")
	def["apply"].call(sim, sim.rng)
	eq(sim.timers.size(), 5, "5 delayed lava strikes")
	for t in sim.timers:
		var left: float = float(t["left"])
		ok(left >= 1.0 and left < 12.0, "strike delay 1..12 (%f)" % left)
	eq(sim.hazards.size(), 0, "hazards land via the stage clock")
	eq(_audio_vols(rec, "quake"), [0.9], "quake 0.9")
	eq(rec["shakes"], [[8.0, 1.2]], "cam shake 8/1.2")
	# fire the stage clock by hand — the after() clock itself is
	# test_creature_sim.test_after_timer's surface; direct firing pins the
	# FULL hazard params (a sim.update run would tick the ttls down)
	for t in sim.timers:
		t["fn"].call()
	eq(sim.hazards.size(), 5, "5 lava hazards after the clock")
	for h in sim.hazards:
		eq(float(h["r"]), 64.0, "lava r 64")
		eq(float(h["dps"]), 12.0, "lava dps 12")
		eq(float(h["ttl"]), 14.0, "lava ttl 14")
		eq(String(h["kind"]), "lava", "lava kind")
		ok(absf(float(h["x"]) - float(sim.px)) <= 500.0 + 1e-6, "x within ±500 of player")
		ok(absf(float(h["z"]) - float(sim.pz)) <= 160.0 + 1e-6, "z within ±160 of player")


func test_earthquake_apply_and_divergence_pin() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "earthquake")
	# the two former Math.random() sites are rng draws now — replay them to pin
	# the three blisters exactly (native-vs-native; TS was unseeded there, see
	# the deck header DIVERGENCE note)
	var r: Variant = RngLib.new(7)
	var want: Array = []
	for i in 3:
		want.append([float(sim.px) + float(i - 1) * 220.0 + r.next() * 120.0,
				float(sim.pz) + (r.next() - 0.5) * 200.0])
	def["apply"].call(sim, RngLib.new(7))
	eq(rec["shakes"], [[9.0, 3.0]], "cam shake 9/3")
	eq(_audio_vols(rec, "quake"), [1.0], "quake vol 1")
	eq(sim.timers.size(), 3, "3 delayed fire blisters")
	for i in 3:
		approx(float(sim.timers[i]["left"]), 1.0 + float(i) * 0.8,
				"blister %d delay 1+i*0.8" % i, 1e-9)
	for t in sim.timers:
		t["fn"].call()  # fire the stage clock by hand (see the volcano note)
	eq(sim.hazards.size(), 3, "3 fire hazards")
	for i in 3:
		var h: Dictionary = sim.hazards[i]
		eq(float(h["r"]), 46.0, "fire r 46")
		eq(float(h["dps"]), 10.0, "fire dps 10")
		eq(float(h["ttl"]), 6.0, "fire ttl 6")
		eq(String(h["kind"]), "fire", "fire kind")
		approx(float(h["x"]), float(want[i][0]), "blister %d x pinned by replay" % i, 1e-9)
		approx(float(h["z"]), float(want[i][1]), "blister %d z pinned by replay" % i, 1e-9)


func test_stampede_apply() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "stampede")
	def["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "alarm"), [0.7], "alarm 0.7")
	eq(sim.ents.size(), 6, "6 stampede ents")
	var g: Dictionary = sim.ents[0]["genome"]
	ok(float(g["size"]) > 1.2, "herd genome over the size gate")
	var dir: int = 1 if float(sim.ents[0]["tx"]) > 0.0 else -1
	for e in sim.ents:
		eq(e["genome"], g, "all six share the herd genome")
		eq(float(e["lifespanStampede"]), 14.0, "lifespanStampede 14")
		eq(String(e["mood"]), "alert", "mood alert")
		eq(float(e["tx"]), float(dir) * 2700.0, "tx = dir*WORLD_HALF")
		eq(float(e["tz"]), float(sim.ents[0]["tz"]), "one shared lane z")
		ok(absf(float(e["z"]) - float(sim.pz)) <= 100.0 + 1e-6, "lane z ±60±40 of player")
		ok(absf(float(e["x"]) - float(sim.px)) >= 800.0 - 1e-6, "herd spawns off-screen")


func test_stampede_fallback_genome() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.eco.species.clear()  # TS living getter empty -> the player-derived herd
	var def: Dictionary = _def(sim.chaos.defs, "stampede")
	def["apply"].call(sim, sim.rng)
	eq(sim.ents.size(), 6, "6 stampede ents")
	for e in sim.ents:
		approx(float(e["genome"]["size"]), 1.8, "fallback herd genome size 1.8", 1e-9)
		eq(String(e["genome"]["diet"]), String(m["ctx"].genome["diet"]),
				"player diet carried into the fallback genome")


func test_night_raid_apply() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "nightraid")
	def["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "alarm"), [0.8], "alarm 0.8")
	eq(sim.ents.size(), 3, "3 raiders (a carnivore line lives at this seed)")
	var carnivores: Array = []
	for s in sim.eco.living():
		if String(s["genome"]["diet"]) == "carnivore" and not bool(s.get("kin", false)):
			carnivores.append(s)
	var sid: String = String(sim.ents[0]["speciesId"])
	var is_wild_carnivore := false
	for s2 in carnivores:
		if String(s2["id"]) == sid:
			is_wild_carnivore = true
	ok(is_wild_carnivore, "raider is a wild carnivore line")
	for e in sim.ents:
		eq(String(e["speciesId"]), sid, "one line hunts as the raid")
		eq(String(e["mood"]), "angry", "mood angry")
		eq(float(e["tx"]), float(sim.px), "tx locked on the player")
		eq(float(e["tz"]), float(sim.pz), "tz locked on the player")
		ok(absf(float(e["x"]) - float(sim.px)) <= 500.0 + 1e-6, "x ±500")
		ok(absf(float(e["z"]) - float(sim.pz)) <= 160.0 + 1e-6, "z ±160")
	eq(String(rec["toasts"][-1][1]), "bad", "raid toast bad")


func test_night_pack_apply() -> void:
	var m := _mk_sim(W_BOLD)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "night_pack")
	def["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "alarm"), [0.8], "alarm 0.8")
	eq(sim.ents.size(), 5, "5 pack hunters")
	var sid: String = String(sim.ents[0]["speciesId"])
	for e in sim.ents:
		eq(String(e["speciesId"]), sid, "one line hunts as the pack")
		eq(String(e["mood"]), "angry", "mood angry")
		eq(float(e["tx"]), float(sim.px), "tx locked on the player")
		eq(float(e["tz"]), float(sim.pz), "tz locked on the player")
		# the pack closes as one body: 620px ring, per-ent ±90 jitter
		ok(absf(float(e["x"]) - float(sim.px)) <= 710.0 + 1e-6, "x within ring+jitter")
		ok(absf(float(e["z"]) - float(sim.pz)) <= 330.0 + 1e-6, "z within band+jitter")
	eq(String(rec["toasts"][-1][2]), "🐺", "pack toast icon")


func test_raid_and_pack_empty_roster_noop() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.eco.species.clear()
	_def(sim.chaos.defs, "nightraid")["apply"].call(sim, sim.rng)
	var np: Dictionary = _def(CreatureEvents.make_creature_chaos_events(W_BOLD), "night_pack")
	np["apply"].call(sim, sim.rng)
	eq(sim.ents.size(), 0, "empty predator pool: silent no-op (TS early return)")
	eq(m["rec"]["toasts"], [], "no raid/pack toasts")


func test_titan_walk_apply() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(CreatureEvents.make_creature_chaos_events(W_TITAN), "titans_walk")
	def["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "quake"), [0.5], "quake 0.5")
	eq(sim.ents.size(), 1, "one titan")
	var e: Dictionary = sim.ents[0]
	var g: Dictionary = e["genome"]
	# a COMPLETE genome — every default key present (spawn_ent takes whole
	# genomes only); the 0.05 mutate may shave size/diet/coat rarely
	for key in GenomeLib.default_genome():
		ok(g.has(key), "titan genome carries %s" % key)
	ok(float(g["size"]) >= 2.2 - 1e-9 and float(g["size"]) <= 2.6 + 1e-9,
			"titan size in [2.2, 2.6] (re-based 2.6, mutate clamp floor 2.2)")
	eq(int(g["generation"]), 2, "mutate bumps generation 1 -> 2")
	eq(float(e["lifespanStampede"]), 30.0, "lifespan 30")
	eq(String(e["mood"]), "idle", "mood idle")
	ok(absf(float(e["x"]) - float(sim.px)) >= 900.0 - 1e-6, "spawns 900 out")
	var dir: int = 1 if float(e["tx"]) > 0.0 else -1
	eq(float(e["tx"]), float(dir) * 2700.0, "tx = dir*WORLD_HALF")
	ok(absf(float(e["z"]) - float(sim.pz)) <= 60.0 + 1e-6, "lane z ±60")
	eq(String(rec["toasts"][-1][1]), "info", "titan toast info")


func test_mutation_storm_zap_apply() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var pool: Array = ["flagella", "cilia", "spikes", "jaw", "legs", "arms",
			"eyes", "horns", "toxin"]
	# the zap draws from the STAGE rng (TS this.rng inside the stage method),
	# not the deck rng the apply hands around — diff the genome to find the
	# gene that moved instead of replaying a stream position
	var before_g: Dictionary = m["ctx"].genome.duplicate()
	var def: Dictionary = _def(sim.chaos.defs, "mutationstorm")
	def["apply"].call(sim, RngLib.new(11))
	eq(_audio_vols(rec, "warp"), [0.8], "warp 0.8 (deck apply, before the zap)")
	var changed := ""
	for g in pool:
		if int(m["ctx"].genome[g]) != int(before_g[g]):
			changed = g
	ok(changed != "", "exactly one pool gene moved")
	if changed != "":
		eq(int(m["ctx"].genome[changed]), int(before_g[changed]) + 1,
				"%s +1 free (default genome below every cap)" % changed)
	eq(m["sim"].pStats, StatsLib.compute_creature_stats(m["ctx"].genome), "pStats refreshed")
	var toast: Variant = null
	for t in rec["toasts"]:
		if String(t[0]).begins_with("Mutation storm!"):
			toast = t
	ok(toast != null, "storm toast")
	if toast != null and changed != "":
		eq(String(toast[0]), "Mutation storm! %s +1 (free)" % changed, "toast names the gene")
		eq(String(toast[1]), "chaos", "toast kind chaos")
	var burst22 := false
	for b in rec["bursts"]:
		if int(b[2]) == 22:
			burst22 = true
	ok(burst22, "fanfare burst of 22")


func test_mutation_storm_zap_at_cap_is_silent() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var caps := {"flagella": 6, "cilia": 4, "spikes": 8, "jaw": 5, "legs": 8,
			"arms": 4, "eyes": 6, "horns": 4, "toxin": 5}
	for g in caps:
		m["ctx"].genome[g] = caps[g]
	var before: Dictionary = m["ctx"].genome.duplicate()
	var def: Dictionary = _def(sim.chaos.defs, "mutationstorm")
	def["apply"].call(sim, RngLib.new(11))
	for g in caps:
		eq(int(m["ctx"].genome[g]), int(before[g]), "%s unchanged at cap" % g)
	for t in rec["toasts"]:
		ok(not String(t[0]).begins_with("Mutation storm!"), "no storm toast at cap")
	eq(rec["bursts"], [], "no fanfare at cap")


func test_glorp_apply() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var dna0: int = int(m["ctx"].dna)
	var def: Dictionary = _def(sim.chaos.defs, "glorp")
	def["apply"].call(sim, sim.rng)
	eq(int(m["ctx"].dna), dna0 + 60, "DNA +60")
	eq(_audio_vols(rec, "dna"), [1.0], "dna chime vol 1")
	eq(rec["floats"].size(), 1, "one world float")
	if rec["floats"].size() == 1:
		var f: Array = rec["floats"][0]
		eq(String(f[2]), "GLORP! +60", "float text")
		eq(String(f[3]), "#e2a4ff", "float color")
		approx(float(f[4]), 16.0, "float size 16", 1e-9)
		ok(absf(float(f[0]) - float(sim.px)) <= 100.0 + 1e-6, "float x ±100 of player")
		approx(float(f[1]), float(sim.pz) * 0.62 - 40.0, "float y = pz*Z_TO_Y-40", 1e-9)
	eq(String(rec["toasts"][-1][2]), "🫧", "glorp toast icon")


func test_rain_apply() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.bushes[0]["food"] = 7.0   # +2 would be 9 -> caps at 8
	sim.bushes[1]["food"] = 3.0   # plain +2
	sim.bushes[2]["regrow"] = 5.0 # rain resets the regrow clock
	sim.eco.flora = 10.0
	sim.eco.flora_cap = 20.0
	var def: Dictionary = _def(sim.chaos.defs, "rain")
	def["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "heal"), [0.6], "heal 0.6")
	approx(float(sim.bushes[0]["food"]), 8.0, "food caps at 8", 1e-9)
	approx(float(sim.bushes[1]["food"]), 5.0, "food +2", 1e-9)
	approx(float(sim.bushes[2]["regrow"]), 0.0, "regrow reset", 1e-9)
	approx(float(sim.eco.flora), 20.0, "flora +15 under the cap", 1e-9)
	eq(String(rec["toasts"][-1][1]), "good", "rain toast good")


func test_rain_mirror_apply() -> void:
	var m := _mk_sim(W_WILD)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.bushes[0]["food"] = 5.0
	sim.bushes[1]["food"] = 1.0   # -2 would go negative -> floor 0
	sim.eco.flora = 10.0          # cap 100 default: +15 plainly
	var mirror: Variant = null
	for d in sim.chaos.defs:
		if d.has("mirrorOf"):
			mirror = d
	mirror["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "heal"), [0.6], "the rain still falls (heal 0.6)")
	approx(float(sim.bushes[0]["food"]), 3.0, "berry swell rots -2", 1e-9)
	approx(float(sim.bushes[1]["food"]), 0.0, "food floors at 0", 1e-9)
	approx(float(sim.eco.flora), 25.0, "flora +15 (the ONE inverted rule is the berries)", 1e-9)
	eq(String(rec["toasts"][-1][1]), "info", "mirror toast info")


func test_converge_predators_apply() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var carnivores: Array = []
	for s in sim.eco.living():
		if not bool(s.get("kin", false)) and String(s["genome"]["diet"]) == "carnivore":
			carnivores.append(s)
	var want: int = mini(3, carnivores.size())
	var def: Dictionary = _def(sim.chaos.defs, "predator_convergence")
	def["apply"].call(sim, sim.rng)
	eq(sim.ents.size(), want, "one ent per hunter line (≤3)")
	var sids: Array = []
	for e in sim.ents:
		sids.append(String(e["speciesId"]))
		ok(absf(float(e["x"]) - float(sim.px)) <= 900.0 + 1e-6, "ring x within 900")
		ok(absf(float(e["z"]) - float(sim.pz)) <= 160.0 + 1e-6, "z band ±160")
	var uniq: Dictionary = {}
	for sidv in sids:
		uniq[sidv] = true
	eq(uniq.size(), sids.size(), "distinct hunter lines")
	if want > 0:
		eq(String(rec["toasts"][-1][1]), "chaos", "converge toast chaos")
		eq(String(rec["toasts"][-1][2]), "🩸", "converge toast icon")


func test_converge_predators_empty_roster_noop() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.eco.species.clear()
	var def: Dictionary = _def(sim.chaos.defs, "predator_convergence")
	def["apply"].call(sim, sim.rng)
	eq(sim.ents.size(), 0, "no hunters: no ents")
	eq(m["rec"]["toasts"], [], "no hunters: no toast (TS length gate)")


func test_gaia_wanderer_apply() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# deterministic bestiary: one donor genome holding a gene the player lacks.
	# The hue keeps the donor's hash OFF the wanderer's genome (default hue),
	# so discover records the wanderer as a NEW bestiary entry.
	ctx.bestiary = {}
	var donor: Dictionary = GenomeLib.default_genome()
	donor["spikes"] = 5
	donor["hue"] = 200
	ctx.discover(donor, "Bestiary donor", "creature")
	var ents0: int = sim.ents.size()
	var best0: int = ctx.bestiary.size()
	sim.gaia_wanderer()
	eq(sim.ents.size(), ents0 + 1, "one wanderer")
	var g: Dictionary = sim.ents[ents0]["genome"]
	eq(int(g["spikes"]), 5, "wanderer carries the rare gene")
	eq(ctx.bestiary.size(), best0 + 1, "bestiary notes the wanderer via discover")


func test_gaia_wanderer_no_rare_gene_noop() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	m["ctx"].bestiary = {}
	sim.gaia_wanderer()
	eq(sim.ents.size(), 0, "no rare gene: silent no-op")
	eq(m["ctx"].bestiary.size(), 0, "nothing discovered")


func test_drop_meteor_scorch_bone_and_fx() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.invuln = 0.0
	# geometry: strike at px+100; ent A at px+50 (d=50), ent B at px+400 (d=300)
	var ea: Dictionary = sim.spawn_ent(null, float(sim.px) + 50.0, float(sim.pz))
	var eb: Dictionary = sim.spawn_ent(null, float(sim.px) + 400.0, float(sim.pz))
	var hp_a: float = float(ea["hp"])
	var hp_b: float = float(eb["hp"])
	var php0: float = sim.php
	var bones0: int = sim.bones.size()
	sim.drop_meteor(float(sim.px) + 100.0, float(sim.pz))
	eq(_audio_vols(rec, "boom"), [1.0], "boom vol 1")
	eq(rec["shakes"][-1], [12.0, 0.8], "cam shake 12/0.8")
	eq(sim.bones.size(), bones0 + 1, "meteor bone lands")
	var bo: Dictionary = sim.bones[bones0]
	eq(String(bo["kind"]), "meteor", "bone kind meteor")
	eq(bool(bo["taken"]), false, "bone untaken")
	approx(hp_a - float(ea["hp"]), 55.0 * (1.0 - 50.0 / 150.0), "ent falloff 55*(1-d/150)", 1e-6)
	approx(hp_b - float(eb["hp"]), 0.0, "ent beyond 150 untouched", 1e-9)
	approx(float(ea["hurtT"]), 1.0, "ent hurtT 1", 1e-9)
	approx(php0 - sim.php, 40.0 * (1.0 - 100.0 / 150.0), "player falloff 40*(1-d/150)", 1e-6)
	approx(float(sim.hurtT), 1.0, "player hurtT 1", 1e-9)
	var ring := false
	for s in rec["spawns"]:
		if String(s.get("kind", "")) == "ring":
			ring = true
	ok(ring, "ring fx")
	var burst40 := false
	for b in rec["bursts"]:
		if int(b[2]) == 40:
			burst40 = true
	ok(burst40, "burst of 40")


func test_drop_meteor_kills_and_invuln_guards() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# a dying ent inside the blast radius is finished (kill_ent marks the corpse)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 100.0, float(sim.pz))
	e["hp"] = 10.0
	sim.invuln = 0.0
	sim.drop_meteor(float(sim.px) + 100.0, float(sim.pz))
	eq(e.has("corpseT"), true, "kill_ent marked the corpse")
	approx(float(e["hp"]), 0.0, "corpse hp 0", 1e-9)
	# invuln shields the player
	sim.php = 100.0
	sim.hurtT = 0.0
	sim.invuln = 1.0
	sim.drop_meteor(float(sim.px) + 10.0, float(sim.pz))
	approx(float(sim.php), 100.0, "invuln blocks meteor damage", 1e-9)


# ---- sim integration: the Ruling 13 banner + the mirror-once flow --------------

func test_night_pack_banner_through_update_chaos() -> void:
	# onWarn re-reads the warn_fn getter (TS evaluates def.warn twice): low
	# chaos banners the pack, then the warn converts and the pack applies;
	# hot chaos goes straight to the apply with NO pack banner.
	var m := _mk_sim(W_BOLD, SEED, {"get_is_night": func() -> bool: return true})
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.chaos = Chaos.new(RngLib.new(5), sim.chaos.defs.filter(
			func(d): return String(d["id"]) == "night_pack"))
	sim.chaos.gap = 0.0
	m["ctx"].chaos = 0.2
	sim.update_chaos(1.0)
	var pack_banners: Array = []
	for b in rec["banners"]:
		if String(b.get("title", "")) == "Something moves between the trees…":
			pack_banners.append(b)
	eq(pack_banners.size(), 1, "low chaos: the pack warns with its banner")
	eq(sim.ents.size(), 0, "warn phase: no pack yet")
	sim.update_chaos(3.0)
	eq(sim.ents.size(), 5, "the warn converts and the pack applies")
	var applied: Array = []
	for b in rec["banners"]:
		if String(b.get("title", "")) == "🐺 NIGHT PACK":
			applied.append(b)
	ok(applied.size() >= 1, "onApply banner carries the def name")
	# hot world: the same flow spawns silently
	var m2 := _mk_sim(W_BOLD, SEED, {"get_is_night": func() -> bool: return true})
	var sim2: Variant = m2["sim"]
	sim2.chaos = Chaos.new(RngLib.new(5), sim2.chaos.defs.filter(
			func(d): return String(d["id"]) == "night_pack"))
	sim2.chaos.gap = 0.0
	m2["ctx"].chaos = 0.8
	sim2.update_chaos(1.0)
	eq(sim2.ents.size(), 5, "hot chaos: immediate apply")
	for b in m2["rec"]["banners"]:
		ok(String(b.get("title", "")) != "Something moves between the trees…",
				"hot chaos: no pack warn banner")


func test_mirror_once_flow_creature() -> void:
	# The base rain survives -> the onEnd roll queues the mirror return -> the
	# mirror face fires. TS semantics (chaos.ts:146, the cell deck pins the
	# same shape): the mirror face is a NO-WARN surprise hit — spawn() runs
	# apply but fires NO onApply hook, so the queue entry SURVIVES and the
	# fired-ledger stays empty (the once-guard only engages on the warn
	# conversion path; cooldown 45 gates the re-fire).
	var m := _mk_sim(W_WILD)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.bushes[0]["food"] = 2.0
	# single-def schedulers pin the pick (the weighted pool would let any def win)
	var base: Array = sim.chaos.defs.filter(func(d): return not d.has("mirrorOf") \
			and String(d["id"]) == "rain")
	sim.chaos = Chaos.new(RngLib.new(6), base)
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.is_active("rain"), "base rain live (no warn -> immediate)")
	approx(float(sim.bushes[0]["food"]), 4.0, "base rain swells the berries", 1e-9)
	eq(rec["banners"], [], "no-warn natural spawn: no apply banner (TS chaos.ts:146)")
	sim.update_chaos(30.0)  # rain ends -> onEnd -> maybe_queue(rng, rain, rain)
	var guard := 0
	while sim.mirrorLedger.queued().is_empty() and guard < 200:
		sim.mirrorLedger.maybe_queue(sim.rng, "rain", "rain")
		guard += 1
	ok(guard < 200, "mirror return queued")
	var mirror: Array = CreatureEvents.make_creature_chaos_events(m["ctx"].world).filter(
			func(d): return d.has("mirrorOf"))
	sim.chaos = Chaos.new(RngLib.new(7), mirror)
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.is_active("rain"), "mirror face live (queued -> weight 0.9)")
	approx(float(sim.bushes[0]["food"]), 2.0, "rain +2 then the mirror rots -2", 1e-9)
	var mirror_toast := false
	for t in rec["toasts"]:
		if String(t[0]) == "Warm rain — but the berries rot on the bush.":
			mirror_toast = true
	ok(mirror_toast, "the mirror body ran (info toast)")
	# the no-warn spawn fired no hooks: the queue entry survives, the ledger
	# stays empty — TS-verbatim (contrast the night_pack conversion path,
	# which DOES fire onApply)
	eq(sim.mirrorLedger.queued(), ["rain"], "no-warn spawn: queue entry survives")
	eq(sim.mirrorLedger.has_fired("rain"), false, "no-warn spawn: fired-ledger untouched")
	# the ledger's own semantics (M1 surface): a fired base never re-queues
	sim.mirrorLedger.on_fired("rain")
	eq(sim.mirrorLedger.queued(), [], "on_fired clears the queue")
	sim.mirrorLedger.maybe_queue(sim.rng, "rain", "rain")
	eq(sim.mirrorLedger.queued(), [], "fired base never re-queues")


func test_deck_rebuild_folds_the_new_world() -> void:
	# C1: a CONTINUE landing on a different world rebuilds the deck from the
	# NEW WorldGenome (night_pack gated in by raider_bold).
	var m := _mk_sim(W_TRAITLESS)
	eq(m["sim"].chaos.defs.size(), 10, "traitless deck at boot")
	m["ctx"].world = W_BOLD.duplicate(true)
	eq(bool(m["sim"].ensure_deck(SEED + 1)), true, "seed mismatch rebuilds")
	eq(m["sim"].chaos.defs.size(), 11, "rebuild folds the NEW world")
	ok(_def(m["sim"].chaos.defs, "night_pack") != null, "night_pack present after rebuild")
