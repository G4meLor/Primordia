## The world genome: every run derives one from the seed — 4-6 world traits
## ("mỗi run một thế giới mới"), 0-2 competing world turns, and a hidden
## temperament. Port of Spore src/evo/worldGenome.ts (full file). The genome
## is a plain Dictionary with the TS field names verbatim (seed / traits /
## turns / firedTurns / revealed / comboFired / timers / temperament) so it
## round-trips saves and the raw world blobs the eco already reads; traits
## are the shared catalog def objects from world_traits.gd.
## rng consumption order is sacred (parity with the frozen TS):
##   derive  = 1 draw for the want count, 1 weighted draw per trait,
##             shuffled(3) + 1 count draw for the turns, 1 temperament pick
##             ONLY on the world_temperament-drawn path;
##   tick    = consumes rng only in the turn top-up branch (seed ^ 0x7a9e
##             stream, plus its temperament pick);
##   title / bands / mirror each own their private stream (0x1017 / the
##             seed+species hash / 0x5eed) — never the derive stream.
## Xor-masking note: TS `seed ^ 0x57ef` runs on ToInt32(seed) (32-bit), so
## the native form is `(seed ^ K) & 0xFFFFFFFF` — identical bit pattern, and
## Rng._init re-masks for the `>>> 0` constructor semantics.
class_name WorldGenome
extends RefCounted

# Same -s-mode constraint as rng.gd's SELF_SCRIPT idiom: resolve scripts by
# path; this file never uses its own class_name as an identifier.
const RngScript := preload("res://src/core/rng.gd")
const Traits := preload("res://src/evo/world_traits.gd")

# ---- dominance_severity (catalog III #3 predator_convergence / #8 siege_hoard)
# ONE formula, two consumers: 1 below the 60% dominance threshold, sub-linear
# ramp above (rank-coupling positive early, tapering), hard cap so a dominant
# line can never pile events past what maxActive absorbs.
const DOMINANCE_THRESHOLD := 0.6
const DOMINANCE_CAP := 1.8


static func world_title_parts(seed: int) -> Dictionary:
	var r: Variant = RngScript.new_from((seed ^ 0x1017) & 0xFFFFFFFF)
	return {"adj": r.pick(Traits.WORLD_ADJ), "noun": r.pick(Traits.WORLD_NOUN)}


static func world_title(seed: int) -> String:
	var p: Dictionary = world_title_parts(seed)
	return "The %s %s" % [p["adj"], p["noun"]]


static func derive_world_genome(seed: int) -> Dictionary:
	var rng: Variant = RngScript.new_from((seed ^ 0x57ef) & 0xFFFFFFFF)
	var pool: Array = []
	for d in Traits.TRAIT_DEFS:
		if not d.get("turnOnly", false):
			pool.append(d)  # turn-only replacements never draw
	var traits: Array = []
	var want: int = 4 + floori(rng.next() * 3.0)  # 4..6
	while traits.size() < want and pool.size() > 0:
		var entries: Array = []
		for d in pool:
			entries.append([float(d["weight"]), d])
		var def: Variant = rng.weighted(entries)
		pool.erase(def)
		# Exclusion is mutual (spec: traits exclude each other) — enforce both
		# directions at draw time so draw order can never leave an excluded
		# pair in the genome.
		for p in pool.duplicate():
			if def["excludes"].has(p["id"]) or p["excludes"].has(def["id"]):
				pool.erase(p)
		traits.append(def)
	var turn_ids: Array = []
	for d in Traits.WORLD_TURN_DEFS:
		turn_ids.append(d["id"])
	var shuffled_turns: Array = rng.shuffled(turn_ids)
	var turn_count: int = floori(rng.next() * 3.0)  # run-cap 0-2, competing pool
	var turns: Array = shuffled_turns.slice(0, turn_count)
	# world_temperament: derived per seed when the trait draws — one rng draw,
	# consumed only on the trait-drawn path (deterministic either way)
	var temperament: Variant = "none"
	for t in traits:
		if t["id"] == "world_temperament":
			temperament = rng.pick(["cradle", "lean", "wildcard"])
			break
	return {
		"seed": seed, "traits": traits, "turns": turns,
		"firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": temperament,
	}


# ---- accessors ---------------------------------------------------------------

## TS numFrom: the first numeric effect carrying `key` wins (traits in genome
## order, effects in definition order). Tolerant of absent or malformed world
## blobs — the eco reads raw saves through the same door, so junk rows read
## as absent instead of crashing (native coercion philosophy).


static func _num_from(w: Dictionary, key: String) -> Variant:
	var traits: Variant = w.get("traits")
	if not (traits is Array):
		return null
	for t in traits:
		if not (t is Dictionary):
			continue
		var effects: Variant = t.get("effects")
		if not (effects is Array):
			continue
		for e in effects:
			if e is Dictionary and e.get("kind") == "num" and e.get("key") == key \
					and (e.get("value") is float or e.get("value") is int):
				return e["value"]
	return null


static func world_num(w: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = _num_from(w, key)
	return float(v) if v != null else fallback


## TS flagFrom/worldHas: a world flag is live when any carried trait lists an
## effect {kind: "flag", key}. Tolerant of absent or malformed blobs — a gate
## that cannot be read stays shut. The eco's former _world_has mirror
## delegates here (one home, two consumers).
static func world_has(w: Dictionary, key: String) -> bool:
	var traits: Variant = w.get("traits")
	if not (traits is Array):
		return false
	for t in traits:
		if not (t is Dictionary):
			continue
		var effects: Variant = t.get("effects")
		if not (effects is Array):
			continue
		for e in effects:
			if e is Dictionary and e.get("kind") == "flag" and e.get("key") == key:
				return true
	return false


## Combo state is live from the moment it fires (comboFired persists in the save).
static func combo_active(w: Dictionary, id: String) -> bool:
	var fired: Variant = w.get("comboFired")
	return fired is Dictionary and fired.get(id, false) == true


## calm_veil is the only catalog trait pushing speciation_mult below 1 — the
## honest proxy for "this world runs quiet" (one home, three consumers).
static func calm_proxy(w: Dictionary) -> bool:
	return world_num(w, "speciation_mult", 1.0) < 1.0


static func archetype_weights(w: Dictionary) -> Dictionary:
	var out := {}
	var traits: Variant = w.get("traits")
	if not (traits is Array):
		return out
	for t in traits:
		if not (t is Dictionary):
			continue
		var effects: Variant = t.get("effects")
		if not (effects is Array):
			continue
		for e in effects:
			if e is Dictionary and e.get("kind") == "ecoSeed" \
					and (e.get("weight") is float or e.get("weight") is int):
				var a: Variant = e.get("archetype")
				# TS: out[e.archetype] = (out[e.archetype] ?? 1) * e.weight
				out[a] = float(out.get(a, 1.0)) * float(e["weight"])
	return out


# ---- EcoMods -----------------------------------------------------------------

## EcoMods is a plain Dictionary with the TS keys verbatim — the eco never
## sees the world genome; stages re-set eco.mods from this each tick. Numbers
## copy only when present (first-wins via numFrom); the two live combos ride
## as flags (rot_circle: deaths bloom the ruins; selection_sweep: the
## ornamented pay a metabolic tithe while live).


static func eco_mods_from_world(w: Dictionary) -> Dictionary:
	var m := {}
	for key in ["growth_mult", "predation_mult", "speciation_mult", "meal_dna_mult", "herb_drain_mult"]:
		var v: Variant = _num_from(w, key)
		if v != null:
			m[key] = float(v)
	if combo_active(w, "selection_sweep"):
		m["selection_sweep"] = true
	if combo_active(w, "rot_circle"):
		m["rot_circle"] = true
	return m


## temperament_bands: per-species aggression/fear band, seeded by world seed
## + species id — the same species under two seeds lands in different bands
## (one pack lurks then flees, the other presses). Pure: stages may call it
## per spawn without disturbing any rng stream.
static func behavior_band(w: Dictionary, species_id: String) -> Dictionary:
	if not world_has(w, "behavior_band"):
		return {"aggression": 1.0, "fear": 1.0}
	# TS `w.seed | 0` + Math.imul(h, 31) hash — only the 32-bit bit pattern
	# survives the chain, so the native hash keeps h masked to uint32
	# (charCodeAt == unicode_at for the ASCII species ids it is called with).
	var h: int = int(w["seed"]) & 0xFFFFFFFF
	for i in range(species_id.length()):
		h = (h * 31 + species_id.unicode_at(i)) & 0xFFFFFFFF
	var r: Variant = RngScript.new_from(h)  # TS new Rng(h >>> 0)
	return {
		"aggression": _to_fixed3(0.8 + r.next() * 0.5),
		"fear": _to_fixed3(0.75 + r.next() * 0.55),
	}


## JS `+x.toFixed(3)`: nearest 3-decimal value, ties toward +inf. For the band
## domain [0.75, 1.3) this is floor(x*1000 + 0.5)/1000 — verified against the
## frozen TS over 10M draws in the domain (0 mismatches).
static func _to_fixed3(x: float) -> float:
	return floor(x * 1000.0 + 0.5) / 1000.0


static func dominance_severity(share: float) -> float:
	if share <= DOMINANCE_THRESHOLD:
		return 1.0
	return minf(DOMINANCE_CAP, 1.0 + (share - DOMINANCE_THRESHOLD) * 2.0)


## mirror_rule bucket: the trait-drawn temperament when present, else the
## seed's hidden temperament (catalog I.b: every seed has one) — decides
## WHICH event carries a mirror face. Pure.
static func mirror_bucket(w: Dictionary) -> String:
	var t: Variant = w.get("temperament")
	if t != null and t != "none":
		return t
	var r: Variant = RngScript.new_from((int(w["seed"]) ^ 0x5eed) & 0xFFFFFFFF)
	return r.pick(["cradle", "lean", "wildcard"])


# ---- the reveal/combo/turn pump ----------------------------------------------

## Called every frame from Game.update — pure data, never touches rendering.
## w.timers is NEVER read or written here (Game owns the per-stage clock; the
## seconds ride the incoming signals Dictionary, TS WorldSignals fields
## verbatim: stage / timer / chaos / kills / extinctions).
## Returns {revealed: [ids newly revealed], combos: [ids fired],
## turn: id} — `turn` is absent on ticks where no world turn fired.


static func _cond_met(c: Dictionary, s: Dictionary) -> bool:
	# Missing signal fields default to 0.0 where TS reads undefined
	# (undefined >= n is a NaN compare -> false). Same outcome for every
	# catalog threshold: counts >= 1, chaos above > 0, seconds >= 90 — a 0.0
	# default never accidentally satisfies one.
	var kind: String = c["kind"]
	if kind == "stageTime":
		return c["stage"] == s.get("stage") and float(s.get("timer", 0.0)) >= float(c["seconds"])
	if kind == "stageEnter":
		return c["stage"] == s.get("stage")
	if kind == "extinct":
		return float(s.get("extinctions", 0.0)) >= float(c["count"])
	if kind == "chaos":
		return float(s.get("chaos", 0.0)) >= float(c["above"])
	if kind == "kill":
		return float(s.get("kills", 0.0)) >= float(c["count"])
	return false


static func _all_revealed(w: Dictionary, ids: Array) -> bool:
	# revealed flags persist by id even after a turn replaces their trait —
	# combos read the flags, not the current trait list (TS allRevealed)
	for id in ids:
		if not w["revealed"].get(id, false):
			return false
	return true


static func tick_world_reveals(w: Dictionary, s: Dictionary) -> Dictionary:
	var out := {"revealed": [], "combos": []}
	for t in w["traits"]:
		if not w["revealed"].get(t["id"], false) and _cond_met(t["reveal"], s):
			w["revealed"][t["id"]] = true
			out["revealed"].append(t["id"])
	for c in Traits.COMBO_DEFS:
		if not combo_active(w, c["id"]) and _all_revealed(w, c["requires"]) \
				and _cond_met(c["trigger"], s):
			w["comboFired"][c["id"]] = true
			out["combos"].append(c["id"])
	for tid_v in w["turns"]:
		if out.has("turn"):
			break  # one turn per tick — report the first fired
		var tid: String = tid_v
		var def: Variant = null
		for d in Traits.WORLD_TURN_DEFS:
			if d["id"] == tid:
				def = d
				break
		if def == null or w["firedTurns"].get(tid, false):
			continue
		var old: Variant = null
		for t in w["traits"]:
			if t["id"] == def["replaces"]:
				old = t
				break
		var rep: Variant = null
		for d in Traits.TRAIT_DEFS:
			if d["id"] == def["replacement"]:
				rep = d
				break
		if old != null and rep != null and w["revealed"].get(old["id"], false) \
				and _cond_met(def["trigger"], s):
			# Same mutual-exclusion rule as derivation: drop survivors that
			# clash with the replacement before appending it.
			var survivors: Array = []
			for t in w["traits"]:
				if t["id"] != def["replaces"] \
						and not t["excludes"].has(def["replacement"]) \
						and not rep["excludes"].has(t["id"]):
					survivors.append(t)
			w["traits"] = survivors + [rep]
			# Ruling T2-M-turn-thin: a turn whose replacement clashes with
			# several survivors can leave the world thin — top up to >= 3 from
			# the remaining pool under the same mutual-exclusion rule, drawing
			# from a seed-branched rng so the refill is deterministic.
			if w["traits"].size() < 3:
				var r: Variant = RngScript.new_from((int(w["seed"]) ^ 0x7a9e) & 0xFFFFFFFF)
				var pool: Array = []
				for d in Traits.TRAIT_DEFS:
					var clash := false
					for t in w["traits"]:
						if t["id"] == d["id"] or t["excludes"].has(d["id"]) \
								or d["excludes"].has(t["id"]):
							clash = true
							break
					if not clash:
						pool.append(d)
				while w["traits"].size() < 3 and pool.size() > 0:
					var entries: Array = []
					for d in pool:
						entries.append([float(d["weight"]), d])
					var tdef: Variant = r.weighted(entries)
					w["traits"].append(tdef)
					var next_pool: Array = []
					for p in pool:
						if p != tdef and not p["excludes"].has(tdef["id"]) \
								and not tdef["excludes"].has(p["id"]):
							next_pool.append(p)
					pool = next_pool
				# the top-up may pull world_temperament into a world that
				# derived none — draw its personality from the same rng
				# (deterministic)
				var has_temp := false
				for t in w["traits"]:
					if t["id"] == "world_temperament":
						has_temp = true
						break
				var tcur: Variant = w.get("temperament")
				if has_temp and not (tcur != null and tcur != "none"):
					w["temperament"] = r.pick(["cradle", "lean", "wildcard"])
			w["firedTurns"][tid] = true
			# the turn card announces the replacement — the codex names it too
			# (pushed into out.revealed so the pump actually announces it; a
			# bare revealed-flag write never reached announceTrait)
			w["revealed"][def["replacement"]] = true
			out["revealed"].append(def["replacement"])
			out["turn"] = tid
	return out
