# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path — a bare global name (Chaos,
# Rng) would not resolve without the editor's class cache.
const Chaos := preload("res://src/game/chaos.gd")
const Rng := preload("res://src/core/rng.gd")

# TS core.test.ts chaos ctx literal — keys stay TS-verbatim camelCase.
const CTX0 := {"chaos": 0.0, "karma": 0.0, "stageTime": 0.0}


# Fake stage: RefCounted, apply/tick/end recorders append into these logs.
class FakeStage:
	var events: Array = []
	var ended: Array = []


func _rec_apply(id: String) -> Callable:
	return func(stage, _rng): stage.events.append("apply:" + id)


func _rec_tick(id: String) -> Callable:
	return func(stage, _elapsed, _dt): stage.events.append("tick:" + id)


func _rec_end(id: String) -> Callable:
	return func(stage): stage.ended.append("end:" + id)


func _w_const(w: float) -> Callable:
	return func(_ctx): return w


## Scripted def: TS ChaosEventDef shape (camelCase keys); cfg merges over the
## defaults, so optional keys (warn/warnS/cooldown/tick/end/…) are ABSENT
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


# --- the 3 TS cases, verbatim -------------------------------------------------


func test_runs_warn_apply_tick_end_in_order() -> void:
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e1", {
		"warn": "incoming…", "cooldown": 5.0,
		"tick": _rec_tick("e1"), "end": _rec_end("e1"),
	})])
	var stg := FakeStage.new()
	ok(sch.trigger("e1", stg), "trigger succeeds")
	# warning window is 2.5s + 1s duration = 3.5s total; advance 4s
	for i in 60 * 4:
		sch.update(1.0 / 60.0, stg, {"chaos": 0.2, "karma": 0.0, "stageTime": 0.0})
	eq(stg.events[0], "apply:e1", "first logged call is apply")
	var first_tick: int = stg.events.find("tick:e1")
	ok(first_tick > 0, "tick comes after apply")
	ok(stg.ended.has("end:e1"), "end recorded")


func test_immediate_events_apply_without_warning() -> void:
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e1", {"cooldown": 5.0, "end": _rec_end("e1")})])
	var stg := FakeStage.new()
	sch.trigger("e1", stg)
	ok(stg.events.has("apply:e1"), "applies immediately on trigger, no warning")
	for i in 120:
		sch.update(1.0 / 60.0, stg, {"chaos": 0.2, "karma": 0.0, "stageTime": 0.0})
	ok(stg.ended.has("end:e1"), "ends after duration")


func test_respects_cooldowns() -> void:
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e1", {
		"cooldown": 5.0, "tick": _rec_tick("e1"),
	})])
	sch.gap = 2.0
	var stg := FakeStage.new()
	var fires := 0
	var last := -1
	for i in 60 * 30:
		var n: int = stg.events.size()
		sch.update(1.0 / 60.0, stg, {"chaos": 0.9, "karma": 0.0, "stageTime": float(i) / 60.0})
		if stg.events.size() > n:
			var last_apply: int = stg.events.rfind("apply:e1")
			if last_apply > last:
				fires += 1
			last = last_apply
	# duration 1s + cooldown 5s → hard ceiling ~5 fires in 30s even at max chaos.
	ok(fires <= 6, "fires <= 6 in 30s (got %d)" % fires)
	ok(fires >= 2, "fires >= 2 in 30s (got %d)" % fires)


# --- warn window math ---------------------------------------------------------


func test_warn_window_and_hook_order() -> void:
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e", {
		"warn": "…", "tick": _rec_tick("e"), "end": _rec_end("e"),
	})])
	sch.gap = 0.0  # natural path spawns immediately on the first update
	var on_warn := func(d): stg.events.append("hookWarn:" + d["id"])
	var on_apply := func(d): stg.events.append("hookApply:" + d["id"])
	var on_end := func(d): stg.ended.append("hookEnd:" + d["id"])
	var hooks := {"onWarn": on_warn, "onApply": on_apply, "onEnd": on_end}
	sch.update(1.0, stg, CTX0, hooks)
	eq(stg.events, ["hookWarn:e"], "warn spawn: onWarn fires, apply does not")
	sch.update(1.0, stg, CTX0, hooks)
	sch.update(1.0, stg, CTX0, hooks)
	eq(stg.events.size(), 1, "still warning at 2s (window 2.5)")
	sch.update(1.0, stg, CTX0, hooks)
	eq(stg.events, ["hookWarn:e", "apply:e", "hookApply:e"],
			"conversion at 3s: apply then onApply")
	sch.update(1.0, stg, CTX0, hooks)
	eq(stg.events, ["hookWarn:e", "apply:e", "hookApply:e", "tick:e"],
			"tick runs on the expiry tick, before end")
	eq(stg.ended, ["end:e", "hookEnd:e"], "end then onEnd")


func test_warn_s_overrides_and_clamps() -> void:
	# warnS below the 0.8x factory floor clamps UP to 2.0s (not 0.5s)
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e", {"warn": "…", "warnS": 0.5})])
	sch.trigger("e", stg)
	sch.update(1.0, stg, CTX0)
	eq(stg.events.size(), 0, "warnS 0.5 clamps to 2.0 — no apply at 1s")
	sch.update(1.0, stg, CTX0)
	eq(stg.events.size(), 1, "apply at exactly 2.0s")
	# warnS above the floor wins unclamped
	var stg2 := FakeStage.new()
	var sch2: Variant = Chaos.new(Rng.new(2), [_mk("e", {"warn": "…", "warnS": 5.0})])
	sch2.trigger("e", stg2)
	for i in 4:
		sch2.update(1.0, stg2, CTX0)
	eq(stg2.events.size(), 0, "warnS 5.0 — no apply at 4s")
	sch2.update(1.0, stg2, CTX0)
	eq(stg2.events.size(), 1, "apply at 5s (override honored)")


func test_warn_scale_ctx_multiplies_window() -> void:
	# bio_tell temperament bucket: 2.5 * 1.6 = 4.0 — the window is fixed at
	# spawn, so the scale must ride the trigger's ctx
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e", {"warn": "…"})])
	var ctx := {"chaos": 0.0, "karma": 0.0, "stageTime": 0.0, "warnScale": 1.6}
	sch.trigger("e", stg, ctx)
	for i in 3:
		sch.update(1.0, stg, ctx)
	eq(stg.events.size(), 0, "warnScale 1.6 — no apply at 3s")
	sch.update(1.0, stg, ctx)
	eq(stg.events.size(), 1, "apply at 4s")
	# missing warnScale falls back to the bare 2.5 window
	var stg2 := FakeStage.new()
	var sch2: Variant = Chaos.new(Rng.new(2), [_mk("e", {"warn": "…"})])
	sch2.trigger("e", stg2)
	sch2.update(2.0, stg2, CTX0)
	eq(stg2.events.size(), 0, "default window — no apply at 2s")
	sch2.update(1.0, stg2, CTX0)
	eq(stg2.events.size(), 1, "apply at 2.5s")


# --- duration draws come from the scheduler's rng -----------------------------


func test_duration_drawn_from_scheduler_rng() -> void:
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e", {"duration": [1.0, 3.0]})])
	var stg := FakeStage.new()
	sch.trigger("e", stg)
	var expected: float = Rng.new(2).range(1.0, 3.0)
	approx(float(sch._active[0]["remaining"]), expected,
			"no-warn duration = the scheduler rng's draw for this seed", 1e-9)


func test_warned_event_conversion_draws_fresh_duration() -> void:
	# TS quirk: spawn draws a duration even for warned defs (discarded), and
	# the warn→active conversion draws AGAIN — the second draw is the real one.
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e", {"warn": "…", "duration": [1.0, 3.0]})])
	var stg := FakeStage.new()
	sch.trigger("e", stg)
	for i in 3:
		sch.update(1.0, stg, CTX0)  # window 2.5 → converts on the 3rd update
	var r: Variant = Rng.new(2)
	r.range(1.0, 3.0)  # spawn-time draw (discarded for warned defs)
	var expected: float = r.range(1.0, 3.0)  # conversion draw
	approx(float(sch._active[0]["remaining"]), expected,
			"conversion draws a FRESH duration (second rng draw)", 1e-9)


# --- stacking limit -----------------------------------------------------------


func test_max_active_hold_retries_conversion() -> void:
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [
		_mk("c1", {"duration": [3.0, 3.0], "end": _rec_end("c1")}),
		_mk("c2", {"duration": [10.0, 10.0]}),
		_mk("c3", {"duration": [10.0, 10.0]}),
		_mk("w4", {"warn": "…", "warnS": 2.0}),
	])
	sch.trigger("c1", stg)
	sch.trigger("c2", stg)
	sch.trigger("c3", stg)
	sch.trigger("w4", stg)
	sch.update(1.0, stg, CTX0)  # t=1
	sch.update(1.0, stg, CTX0)  # t=2: warn hits 0 → conversion attempt
	ok(not stg.events.has("apply:w4"), "held while 3 events are active")
	approx(sch.warn_remaining(), 1.0, "hold resets warn remaining to 1s")
	sch.update(1.0, stg, CTX0)  # t=3: c1 expires this tick, AFTER the retry
	ok(stg.ended.has("end:c1"), "c1 ended at 3s")
	ok(not stg.events.has("apply:w4"), "conversion retried only NEXT tick")
	approx(float(sch._cooldowns.get("c1", -1.0)), 19.0,
			"c1 cooldown set (missing cooldown → 20) and decayed 1s")
	sch.update(1.0, stg, CTX0)  # t=4: slot free → converts now
	ok(stg.events.has("apply:w4"), "converts once a slot frees")
	ok(sch.is_active("w4"), "w4 is active after conversion")
	approx(sch.warn_remaining(), 0.0, "no warn left after conversion")


func test_max_chaos_events_ctx_override() -> void:
	# natural path: cap 1 blocks the second spawn entirely
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [
		_mk("a", {"duration": [10.0, 10.0]}),
		_mk("b", {"duration": [10.0, 10.0]}),
	])
	sch.gap = 0.0
	var ctx := {"chaos": 0.0, "karma": 0.0, "stageTime": 0.0, "maxChaosEvents": 1}
	sch.update(1.0, stg, ctx)
	eq(stg.events.size(), 1, "one spawn")
	sch.update(1.0, stg, ctx)
	eq(stg.events.size(), 1, "maxChaosEvents 1 blocks further natural spawns")
	# conversion path: warned event held at its window end
	var stg2 := FakeStage.new()
	var sch2: Variant = Chaos.new(Rng.new(2), [
		_mk("a", {"duration": [10.0, 10.0]}),
		_mk("w", {"warn": "…", "warnS": 1.0}),
	])
	sch2.trigger("a", stg2)
	sch2.trigger("w", stg2)
	sch2.update(1.0, stg2, ctx)  # warn 2.0 → 1.0
	sch2.update(1.0, stg2, ctx)  # warn hits 0 → blocked by cap 1
	ok(not stg2.events.has("apply:w"), "conversion blocked by maxChaosEvents 1")
	approx(sch2.warn_remaining(), 1.0, "held at 1s")


# --- cooldowns ----------------------------------------------------------------


func test_cooldown_gate_and_expiry() -> void:
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e", {"cooldown": 5.0})])
	sch.gap = 0.0
	sch.update(1.0, stg, CTX0)  # spawn
	eq(stg.events.size(), 1, "spawned")
	sch.update(1.0, stg, CTX0)  # duration 1s → end → cooldown 5 → decay pass
	approx(float(sch._cooldowns.get("e", -1.0)), 4.0,
			"cooldown set (5), then the same tick's decay pass takes 1s off")
	sch.update(1.0, stg, CTX0)  # 3
	sch.update(1.0, stg, CTX0)  # 2
	sch.update(1.0, stg, CTX0)  # 1
	eq(stg.events.size(), 1, "cooldown gates re-fire")
	approx(float(sch._cooldowns.get("e", -1.0)), 1.0, "1s left on the cooldown")
	sch.update(1.0, stg, CTX0)  # 0 → expired, erased, re-fires (gap 0)
	ok(not sch._cooldowns.has("e"), "expired cooldown erased")
	eq(stg.events.size(), 2, "refires after cooldown expiry")


# --- weighted selection -------------------------------------------------------


func test_weighted_selection_determinism() -> void:
	var stg := FakeStage.new()
	var w_a := func(_c): return 3.0
	var w_b := func(_c): return 1.0
	var sch: Variant = Chaos.new(Rng.new(2), [
		_mk("A", {"weight": w_a}),
		_mk("B", {"weight": w_b}),
	])
	sch.gap = 0.0
	var expected: Variant = Rng.new(2).weighted([[3.0, "A"], [1.0, "B"]])
	sch.update(1.0, stg, CTX0)
	eq(stg.events, ["apply:" + str(expected)],
			"first pick matches a hand-rolled weighted over the same entries")


func test_weight_floor_0_01() -> void:
	# find a seed where the floored 0.01 weight actually wins (≈1% per seed);
	# a raw pass-through (-5 → clamped to 0 inside weighted) could never pick N
	var found := 0
	for s in range(1, 2001):
		if Rng.new(s).weighted([[0.01, "N"], [1.0, "P"]]) == "N":
			found = s
			break
	ok(found > 0, "found a seed where the floored weight wins")
	var stg := FakeStage.new()
	var w_neg := func(_c): return -5.0
	var sch: Variant = Chaos.new(Rng.new(found), [
		_mk("N", {"weight": w_neg}),
		_mk("P", {}),
	])
	sch.gap = 0.0
	sch.update(1.0, stg, CTX0)
	eq(stg.events, ["apply:N"], "weight clamps to the max(0.01, w) floor")


# --- ctx pass-through (T12 deferred minor) ------------------------------------


func test_weight_callable_reads_mood_and_ctx_extras() -> void:
	# The scheduler forwards the WHOLE ctx Dictionary to every weight Callable
	# untouched — a scripted def reads `mood` (storyteller-driven odds) and the
	# stage extras (`night` / `mirrors` / `dominance`) must arrive verbatim.
	var got: Array = []
	var w_bless := func(ctx):
		got.append(ctx)
		return 1.0 if ctx.get("mood") == "bless" else 0.0
	# seed hunt (≈50% per seed): 1.0-vs-1.0 must pick B, 0.01-vs-1.0 must pick P
	var seed_b := 0
	for s in range(1, 2001):
		if Rng.new(s).weighted([[1.0, "B"], [1.0, "P"]]) == "B" \
				and Rng.new(s).weighted([[0.01, "B"], [1.0, "P"]]) == "P":
			seed_b = s
			break
	ok(seed_b > 0, "found a seed discriminating weight 1.0 from the 0.01 floor")
	# mood "bless": the scripted weight rides at full strength and wins the draw
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(seed_b), [_mk("B", {"weight": w_bless}), _mk("P", {})])
	sch.gap = 0.0
	var ctx := {"chaos": 0.0, "karma": 0.0, "stageTime": 0.0,
			"mood": "bless", "night": true, "mirrors": ["b"], "dominance": 3.5}
	sch.update(1.0, stg, ctx)
	eq(stg.events, ["apply:B"], "mood 'bless' gates the scripted weight in")
	eq(got.size(), 1, "the weight Callable ran exactly once (one spawn attempt)")
	eq(got[0], ctx, "the ctx the weight sees equals the ctx passed to update")
	eq(got[0].get("mood"), "bless", "mood key arrives intact")
	eq(got[0].get("night"), true, "night flag arrives intact")
	eq(got[0].get("mirrors"), ["b"], "mirrors list arrives verbatim")
	eq(got[0].get("dominance"), 3.5, "dominance number arrives verbatim")
	# mood anything else: the scripted weight floors to 0.01 and 'P' wins
	var stg2 := FakeStage.new()
	var sch2: Variant = Chaos.new(Rng.new(seed_b), [_mk("B", {"weight": w_bless}), _mk("P", {})])
	sch2.gap = 0.0
	sch2.update(1.0, stg2, CTX0)  # no mood key at all — the def reads null
	eq(stg2.events, ["apply:P"], "no mood key: scripted weight floors, plain wins")
	eq(got[1].get("mood"), null, "absent mood reads as null inside the weight")


# --- gap scaling --------------------------------------------------------------


func test_gap_chaos_scaling() -> void:
	# chaos 0.9 → effective gap 26 * (1 - 0.45*0.9) = 15.47
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e")])
	var ctx := {"chaos": 0.9, "karma": 0.0, "stageTime": 0.0}
	for i in 15:
		sch.update(1.0, stg, ctx)
	eq(stg.events.size(), 0, "no spawn before effective gap 15.47")
	sch.update(1.0, stg, ctx)
	eq(stg.events.size(), 1, "spawn at the 16th second")
	# chaos 0 → base gap 26, and the boundary is strict < (== fires)
	var stg2 := FakeStage.new()
	var sch2: Variant = Chaos.new(Rng.new(2), [_mk("e")])
	for i in 25:
		sch2.update(1.0, stg2, CTX0)
	eq(stg2.events.size(), 0, "no spawn at 25s")
	sch2.update(1.0, stg2, CTX0)
	eq(stg2.events.size(), 1, "spawn exactly at 26s (sinceLast == gap proceeds)")


func test_gap_mult_and_chaos_combine() -> void:
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e")])
	var ctx := {"chaos": 0.5, "karma": 0.0, "stageTime": 0.0, "gapMult": 2.0}
	var eff := 26.0 * 2.0 * (1.0 - 0.45 * 0.5)  # 40.3
	for i in ceili(eff) - 1:
		sch.update(1.0, stg, ctx)
	eq(stg.events.size(), 0, "no spawn before effective gap %f" % eff)
	sch.update(1.0, stg, ctx)
	eq(stg.events.size(), 1, "spawn at ceil(effective gap)")


# --- trigger ------------------------------------------------------------------


func test_trigger_paths() -> void:
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e", {"warn": "…"})])
	ok(not sch.trigger("missing", stg), "unknown id fails")
	ok(sch.trigger("e", stg), "first trigger succeeds")
	ok(not sch.trigger("e", stg), "re-trigger while warn-phase active fails")
	ok(not sch.is_active("e"), "warn-phase event is not isActive")
	sch.update(3.0, stg, CTX0)  # default trigger ctx → window 2.5 → converts
	ok(not sch.trigger("e", stg), "re-trigger while active fails")
	ok(sch.is_active("e"), "active after conversion")
	ok(stg.events.has("apply:e"), "trigger spawned the warned event")


# --- warn_remaining -----------------------------------------------------------


func test_warn_remaining_max_over_warns() -> void:
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [
		_mk("a", {"warn": "…", "warnS": 2.0}),
		_mk("b", {"warn": "…", "warnS": 5.0}),
	])
	approx(sch.warn_remaining(), 0.0, "0 when no warn-phase events")
	sch.trigger("a", stg)
	sch.trigger("b", stg)
	approx(sch.warn_remaining(), 5.0, "max over warn-phase actives")
	sch.update(2.0, stg, CTX0)
	approx(sch.warn_remaining(), 3.0, "2s in → 3s left")
	sch.update(2.0, stg, CTX0)
	approx(sch.warn_remaining(), 1.0, "4s in → 1s left")
	sch.update(1.0, stg, CTX0)
	approx(sch.warn_remaining(), 0.0, "both converted at 5s")
	ok(stg.events.has("apply:a") and stg.events.has("apply:b"), "both applied")


# --- is_active / active_events / clear -----------------------------------------


func test_is_active_and_active_events() -> void:
	# raw def with NO optional keys — absent tick/end/cooldown must not crash
	var raw := {
		"id": "r", "name": "Raw",
		"weight": _w_const(1.0), "duration": [3.0, 3.0],
		"apply": _rec_apply("r"),
	}
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [raw, _mk("w", {"warn": "…", "warnS": 5.0})])
	sch.trigger("w", stg)
	ok(not sch.is_active("w"), "warn-phase excluded from isActive")
	eq(sch.active_events(), [], "warn-phase excluded from active_events")
	approx(sch.warn_remaining(), 5.0, "but counted by warn_remaining")
	sch.trigger("r", stg)
	ok(sch.is_active("r"), "active-phase event isActive")
	eq(sch.active_events().size(), 1, "one active event")
	sch.update(1.0, stg, CTX0)
	var evs: Array = sch.active_events()
	eq(evs.size(), 1, "still one after 1s")
	approx(float(evs[0]["elapsed"]), 1.0, "elapsed accumulates")
	eq(evs[0]["def"]["id"], "r", "def reference returned")
	sch.update(2.0, stg, CTX0)
	eq(sch.active_events(), [], "expired event leaves active_events")
	ok(not sch.is_active("r"), "isActive false after end")
	approx(float(sch._cooldowns.get("r", -1.0)), 18.0,
			"missing cooldown defaults to 20s, decayed by dt=2 in the same tick")


func test_clear_resets_state() -> void:
	var stg := FakeStage.new()
	var sch: Variant = Chaos.new(Rng.new(2), [_mk("e", {"cooldown": 5.0})])
	sch.gap = 0.0
	sch.update(1.0, stg, CTX0)  # spawn
	sch.update(1.0, stg, CTX0)  # expire → cooldown 5
	ok(sch._cooldowns.has("e"), "cooldown present pre-clear")
	sch.clear()
	eq(sch._active, [], "actives cleared")
	eq(sch._cooldowns, {}, "cooldowns cleared")
	approx(sch.warn_remaining(), 0.0, "no warns after clear")
	eq(sch.active_events(), [], "no active events after clear")
	sch.update(1.0, stg, CTX0)
	eq(stg.events.size(), 2, "spawns fresh after clear (cooldown gone)")


# --- MirrorLedger -------------------------------------------------------------


func test_mirror_ledger_queue_and_ledger() -> void:
	var ml: Variant = Chaos.MirrorLedger
	# guard: defId must equal mirrorable
	var led_guard: Variant = ml.new()
	led_guard.maybe_queue(Rng.new(1), "other", "base")
	eq(led_guard.queued(), [], "defId != mirrorable never queues")
	# chance-gated queueing: find seeds on both sides of chance(0.25)
	var queued_seed := 0
	var skip_seed := 0
	for s in range(1, 200):
		if Rng.new(s).chance(0.25):
			if queued_seed == 0:
				queued_seed = s
		elif skip_seed == 0:
			skip_seed = s
		if queued_seed > 0 and skip_seed > 0:
			break
	ok(queued_seed > 0 and skip_seed > 0, "found both chance outcomes")
	var led_skip: Variant = ml.new()
	led_skip.maybe_queue(Rng.new(skip_seed), "base", "base")
	eq(led_skip.queued(), [], "chance false → not queued")
	var led: Variant = ml.new()
	led.maybe_queue(Rng.new(queued_seed), "base", "base")
	eq(led.queued(), ["base"], "chance true → queued")
	led.maybe_queue(Rng.new(queued_seed), "base", "base")
	eq(led.queued(), ["base"], "already queued → no duplicate")
	# onFired records + clears the queued entry
	ok(not led.has_fired("base"), "not fired yet")
	led.on_fired("base")
	ok(led.has_fired("base"), "fired recorded")
	eq(led.queued(), [], "queue entry cleared")
	# one mirror per base: a fired base never queues again
	for s in range(1, 200):
		led.maybe_queue(Rng.new(s), "base", "base")
	eq(led.queued(), [], "fired base never queues again")
	# distinct bases queue independently
	var led2: Variant = ml.new()
	led2.maybe_queue(Rng.new(queued_seed), "b1", "b1")
	led2.maybe_queue(Rng.new(queued_seed), "b2", "b2")
	led2.maybe_queue(Rng.new(skip_seed), "b3", "b3")
	eq(led2.queued(), ["b1", "b2"], "independent per-base queueing")
	# onFired of an unqueued id still records
	var led3: Variant = ml.new()
	led3.on_fired("x")
	ok(led3.has_fired("x"), "onFired records an unqueued id")
	eq(led3.queued(), [], "queue untouched")
