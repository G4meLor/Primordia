## Chaos engine: weighted random world events with foreshadowing warnings.
## Every stage registers its own event set; the scheduler handles timing,
## warnings ("Something glows beneath the silt..."), stacking limits and the
## global chaos meter scaling.
## Port of Spore src/game/chaos.ts. Defs and the context Dictionary keep the
## TS camelCase keys (save-wire parity); hooks are Callables keyed onWarn /
## onApply / onEnd, exactly the TS hook names. The rng and stage params are
## duck-typed Variants — the global class_name cache is absent in `-s` mode,
## so this file never references the Rng class name (GDScript has no
## generics, so the TS <S> stage param stays Variant too).
class_name ChaosScheduler
extends RefCounted

const WARN_WINDOW := 2.5

## Base seconds between chaos events, exported so stages never hardcode it.
const BASE_GAP := 26

## Multiplier on the gap; chaos shrinks it.
var gap: float = BASE_GAP
var gap_chaos_scale: float = 0.45
## TS ChaosEventDef<S>[] — Dictionaries keyed id/name/warn/warnS/mirrorOf/
## weight/duration/cooldown/apply/tick/end; optional keys are absent when
## unset, weight/apply/tick/end hold Callables.
var defs: Array = []

# TS privates are compile-time only; GDScript underscores them.
var _rng  # duck-typed Rng
# TS Active<S>[] — {def, phase ("warn"|"active"), remaining, elapsed}.
var _active: Array = []
# TS Map<string, number> — def id → seconds left on its cooldown.
var _cooldowns: Dictionary = {}
var _since_last: float = 0.0


func _init(rng, defs: Array) -> void:
	_rng = rng
	self.defs = defs


## TS activeEvents getter: {def, elapsed} pairs for active-phase events.
func active_events() -> Array:
	var out: Array = []
	for a in _active:
		if a["phase"] == "active":
			out.append({"def": a["def"], "elapsed": a["elapsed"]})
	return out


## bio_tell: seconds left in the current warn phase (0 when none) — stages
## drive the ambient panic-drift window off this, so both the natural
## scheduler path and trigger() open the window.
func warn_remaining() -> float:
	var m := 0.0
	for a in _active:
		if a["phase"] == "warn":
			m = maxf(m, float(a["remaining"]))
	return m


func is_active(id: String) -> bool:
	for a in _active:
		if a["def"]["id"] == id and a["phase"] == "active":
			return true
	return false


## Force-trigger by id (scripts, buttons, testing). Returns success.
## No hooks forwarded — TS spawns with the default empty hooks.
func trigger(id: String, stage: Variant, ctx: Variant = null) -> bool:
	var def: Variant = null
	for d in defs:
		if d["id"] == id:
			def = d
			break
	if def == null:
		return false
	for a in _active:
		if a["def"]["id"] == id:
			return false
	var c: Dictionary = ctx if ctx != null else {"chaos": 0.0, "karma": 0.0, "stageTime": 0.0}
	_spawn(def, stage, c, {})
	return true


func _spawn(def: Dictionary, stage: Variant, ctx: Dictionary, hooks: Dictionary = {}) -> void:
	# drawn even for warned defs (discarded there) — the TS rng stream consumes
	# this draw, and the conversion below draws AGAIN; parity keeps both
	var dur: float = _rng.range(def["duration"][0], def["duration"][1])
	if def.get("warn"):
		# bio_tell: per-def window wins (clamped to the 0.8x factory floor),
		# else the temperament bucket scales the base window (the ctx scale
		# already respects the floor)
		var window: float
		if def.get("warnS") != null:
			window = maxf(WARN_WINDOW * 0.8, float(def["warnS"]))
		else:
			window = WARN_WINDOW * float(ctx.get("warnScale", 1.0))
		_active.append({"def": def, "phase": "warn", "remaining": window, "elapsed": 0.0})
		_fire_hook(hooks, "onWarn", def)
	else:
		_active.append({"def": def, "phase": "active", "remaining": dur, "elapsed": 0.0})
		def["apply"].call(stage, _rng)


func update(dt: float, stage: Variant, ctx: Dictionary, hooks: Dictionary = {}) -> void:
	var i: int = _active.size() - 1
	while i >= 0:
		var a: Dictionary = _active[i]
		a["remaining"] = float(a["remaining"]) - dt

		if a["phase"] == "warn":
			if float(a["remaining"]) <= 0.0:
				# the cap also applies at conversion — warned events held in warn
				# used to stack past maxActive the moment they went live
				var warn_cap: int = int(ctx.get("maxChaosEvents", 3))
				if _count_phase("active") >= warn_cap:
					a["remaining"] = 1.0  # hold one more warn second, retry next tick
					i -= 1
					continue
				a["phase"] = "active"
				a["elapsed"] = 0.0
				a["remaining"] = _rng.range(a["def"]["duration"][0], a["def"]["duration"][1])
				a["def"]["apply"].call(stage, _rng)
				_fire_hook(hooks, "onApply", a["def"])
			i -= 1
			continue

		# active phase
		a["elapsed"] = float(a["elapsed"]) + dt
		var tick: Variant = a["def"].get("tick")
		if tick != null:
			tick.call(stage, a["elapsed"], dt)
		if float(a["remaining"]) <= 0.0:
			var end_f: Variant = a["def"].get("end")
			if end_f != null:
				end_f.call(stage)
			_fire_hook(hooks, "onEnd", a["def"])
			var cd: Variant = a["def"].get("cooldown")
			_cooldowns[a["def"]["id"]] = 20.0 if cd == null else float(cd)
			_active.remove_at(i)
		i -= 1

	var expired: Array = []
	for k in _cooldowns:
		var nv: float = float(_cooldowns[k]) - dt
		if nv <= 0.0:
			expired.append(k)
		else:
			_cooldowns[k] = nv
	for k in expired:
		_cooldowns.erase(k)

	# stacking limit — unbounded concurrent events pinned the chaos meter
	# at ~0.79 (designed rest: 0.25) and buried the player at the weakest stage
	var max_active: int = int(ctx.get("maxChaosEvents", 3))
	if _count_phase("active") >= max_active:
		return

	_since_last += dt
	var effective_gap: float = gap * float(ctx.get("gapMult", 1.0)) \
			* (1.0 - gap_chaos_scale * float(ctx.get("chaos", 0.0)))
	if _since_last < effective_gap:
		return
	var pool: Array = []
	for d in defs:
		if _has_active_id(d["id"]):
			continue
		if _cooldowns.has(d["id"]):
			continue
		pool.append(d)
	if pool.is_empty():
		return
	var entries: Array = []
	for d in pool:
		entries.append([maxf(0.01, float(d["weight"].call(ctx))), d])
	var chosen: Variant = _rng.weighted(entries)
	_since_last = 0.0
	_spawn(chosen, stage, ctx, hooks)


## Fresh-run reset: actives, cooldown ledger and the gap clock all clear.
func clear() -> void:
	_active = []
	_cooldowns.clear()
	_since_last = 0.0


func _count_phase(phase: String) -> int:
	var n: int = 0
	for a in _active:
		if a["phase"] == phase:
			n += 1
	return n


func _has_active_id(id: String) -> bool:
	for a in _active:
		if a["def"]["id"] == id:
			return true
	return false


## TS `hooks.onX?.(def)` — a missing hook key reads null and is skipped.
func _fire_hook(hooks: Dictionary, key: String, def: Dictionary) -> void:
	var h: Variant = hooks.get(key)
	if h != null:
		h.call(def)


## mirror_rule state shared by every stage: the queued return faces plus the
## fired-base ledger (at most ONE mirror return per base per run).
class MirrorLedger:
	var _queue: Array = []
	var _fired: Dictionary = {}  # TS Set<string> — keys only

	## After a base event survived, the seeded roll queues its mirror return
	## (one mirror face per world — the temperament bucket picked it). A base
	## whose mirror already fired never queues again.
	func maybe_queue(rng, def_id: String, mirrorable: String) -> void:
		if def_id != mirrorable:
			return
		if _fired.has(def_id):
			return
		if _queue.has(def_id):
			return
		if rng.chance(0.25):
			_queue.append(def_id)

	## A mirror face went live — record it and clear the queued entry.
	func on_fired(base_id: String) -> void:
		_fired[base_id] = true
		_queue = _queue.filter(func(id): return id != base_id)

	## The ids whose mirror face is currently queued (ChaosContext.mirrors).
	func queued() -> Array:
		return _queue

	## Whether a base's mirror already fired (test/inspect seam).
	func has_fired(base_id: String) -> bool:
		return _fired.has(base_id)
