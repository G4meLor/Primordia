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
