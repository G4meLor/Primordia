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
func _mk_sim(world: Dictionary = W_TRAITLESS, seed_v: int = SEED) -> Dictionary:
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
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _def(deck: Array, id: String) -> Variant:
	for d in deck:
		if String(d["id"]) == id and not d.has("mirrorOf"):
			return d
	return null


func test_traitless_deck_is_nine_defs() -> void:
	var deck: Array = CreatureEvents.make_creature_chaos_events(W_TRAITLESS)
	eq(deck.size(), 9, "factory: traitless = 8 baseline + predator_convergence")
	var ids: Array = []
	for d in deck:
		ids.append(d["id"])
	eq(ids, ["volcano", "earthquake", "stampede", "nightraid", "mutationstorm",
			"glorp", "rain", "meteor", "predator_convergence"], "TS deck order")
	# the sim constructor folds ctx.world into the same deck (TS:157)
	var m := _mk_sim()
	eq(m["sim"].chaos.defs.size(), 9, "sim constructor deck: traitless = 9")
	approx(float(m["sim"].chaos.gap), 40.0, "creature gap 40")
	approx(float(m["sim"].chaos.gap_chaos_scale), 0.35, "creature gap chaos scale")


func test_gated_defs_gate_on_the_world() -> void:
	var bdeck: Array = CreatureEvents.make_creature_chaos_events(W_BOLD)
	eq(bdeck.size(), 10, "raider_bold adds night_pack")
	var np: Dictionary = _def(bdeck, "night_pack")
	ok(np != null, "night_pack present")
	eq(String(np["name"]), "🐺 NIGHT PACK", "night_pack name")
	ok(np.has("warn_fn") and np["warn_fn"] is Callable,
			"night_pack carries warn_fn (the TS getter port)")
	ok(not np.has("warn"), "night_pack has NO static warn key")
	ok(_def(CreatureEvents.make_creature_chaos_events(W_TRAITLESS), "night_pack") == null,
			"traitless world has no night_pack")

	var tdeck: Array = CreatureEvents.make_creature_chaos_events(W_TITAN)
	eq(tdeck.size(), 10, "old_blood (ecoSeed titan) adds titans_walk")
	var tw: Dictionary = _def(tdeck, "titans_walk")
	ok(tw != null, "titans_walk present")
	eq(String(tw["name"]), "🗿 A TITAN WALKS", "titans_walk name")
	eq(String(tw["warn"]), "The ground trembles in a slow rhythm…", "titan warn verbatim")
	# the gate is the ecoSeed ARCHETYPE scan (seedsTitans), not a number: an
	# herbivore-seeded world never unlocks the titan
	ok(_def(CreatureEvents.make_creature_chaos_events(W_HERB_SEED), "titans_walk") == null,
			"herbivore ecoSeed does not seed titans")

	var wdeck: Array = CreatureEvents.make_creature_chaos_events(W_WILD)
	eq(wdeck.size(), 10, "wildcard adds the rain mirror face")
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

	eq(CreatureEvents.make_creature_chaos_events(W_BOTH).size(), 11,
			"bold + titan = 11 defs")


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
