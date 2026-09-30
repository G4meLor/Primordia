## Tribe-stage chaos event deck — port of Spore src/game/tribe/tribeEvents.ts
## (frozen, 156 lines). Static factory: make_tribe_chaos_events(world) folds the
## WorldGenome in — a traitless world gets exactly the baseline defs plus the
## always-present siege_hoard (TS appends it unconditionally in the array
## literal; only its WEIGHT is gated).
## Def shape = the M1 ChaosScheduler's (camelCase TS keys): id / name / warn? /
## mirrorOf? / weight (Callable on the ctx Dictionary) / duration [lo, hi] /
## cooldown / apply (sim, rng) / tick? (sim, elapsed, dt) / end? (sim).
## The apply Callables receive the TribeSim (the scheduler's "stage") and route
## every audio effect through its hooks (_fire — GDScript privacy is advisory;
## the defs stay data, the sim owns the wiring).
## Def name/warn strings stay the raw English keys — the TS hud renders banner
## titles through t() at display time, so the native HUD translates them.
## DIVERGENCE (tribeEvents.ts:20/24): the storm's two UNSEEDED Math.random()
## sites — the apply delay `2 + Math.random() * 4` and the tick roll
## `Math.random() < 0.01` — have no TS stream to match. The port keeps both
## draws (count identical) on seeded rngs: the apply sources the deck rng the
## scheduler passes in (the draw lands in the chaos stream position — the
## creature earthquake precedent); the tick sources the sim's stage rng (the
## scheduler's tick signature carries no rng). TS stream parity is unobservable
## at both sites by construction; the replay pins live in
## tests/test_tribe_events.gd.
extends RefCounted

const WorldGenomeScript := preload("res://src/evo/world_genome.gd")


# ---- the 5 baseline defs (tribeEvents.ts:10-77, verbatim) ---------------------------

static func _baseline() -> Array:
	var out: Array = []

	# storm
	var storm_apply := func(s, rng) -> void:
		s._fire("audio_play", ["quake", 0.6, 0.0])
		# DIVERGENCE: TS `2 + Math.random() * 4` — deck-rng draw (see header)
		var strike := func() -> void:
			s.lightning_strike()
		s.after(2.0 + rng.next() * 4.0, strike)
	var storm_tick := func(s, elapsed, _dt) -> void:
		# a few strikes over the storm
		# DIVERGENCE: TS `Math.random() < 0.01` — stage-rng draw (see header)
		if float(elapsed) > 6.0 and s.rng.chance(0.01):
			s.lightning_strike()
	out.append({
		"id": "storm",
		"name": "⚡ STORM FRONT",
		"warn": "The wind dies. Clouds boil green-black…",
		"weight": func(c) -> float: return 0.7 + float(c["chaos"]),
		"duration": [14.0, 22.0],
		"cooldown": 55,
		"apply": storm_apply,
		"tick": storm_tick,
	})

	# beast
	var beast_apply := func(s, _rng) -> void:
		s.spawn_beast()
		s._fire("audio_play", ["alarm", 0.8, 0.0])
	var beast_end := func(s) -> void:
		s.despawn_beast()
	out.append({
		"id": "beast",
		"name": "🦁 A GREAT BEAST HUNTS",
		"warn": "Birds go silent in every direction…",
		"weight": func(c) -> float: return 0.6 + float(c["chaos"]),
		"duration": [25.0, 25.0],
		"cooldown": 65,
		"apply": beast_apply,
		"end": beast_end,
	})

	# rivalsurprise
	var rivalsurprise_apply := func(s, _rng) -> void:
		# launchRivalRaidNow() already refuses on peaceful+hutless — a refuse
		# here keeps the warning honest (no alarm with no raid)
		if s.raids_blocked():
			return
		s.launch_rival_raid_now()
		s._fire("audio_play", ["alarm", 1.0, 0.0])
	out.append({
		"id": "rivalsurprise",
		"name": "🗡 SURPRISE ATTACK",
		"warn": "Drums answer from beyond the ridge…",
		"weight": func(c) -> float: return 0.6 + float(c["karma"]) * -0.3,
		"duration": [10.0, 10.0],
		"cooldown": 70,
		"apply": rivalsurprise_apply,
	})

	# festival
	var festival_apply := func(s, _rng) -> void:
		s.festival()
		s._fire("audio_play", ["charm", 0.9, 0.0])
	out.append({
		"id": "festival",
		"name": "🔥 FESTIVAL NIGHT",
		"weight": func(c) -> float: return 0.8 + maxf(0.0, float(c["karma"])),
		"duration": [16.0, 22.0],
		"cooldown": 80,
		"apply": festival_apply,
	})

	# gift
	var gift_apply := func(s, _rng) -> void:
		s.star_shower()
		s._fire("audio_play", ["spawn", 0.7, 0.0])
	out.append({
		"id": "gift",
		"name": "🌠 STAR SHOWER",
		"weight": func(_c) -> float: return 0.5,
		"duration": [10.0, 14.0],
		"cooldown": 90,
		"apply": gift_apply,
	})

	return out


# ---- the world-parameterized faces (tribeEvents.ts:79-155) --------------------------
# The factory draws NOTHING from any stage stream — the gates read the world
# genome only (mirror_bucket owns a private stream), so the scheduler
# construction stays draw-free (the stage stream is final at TS:135).

## Pirate Wind: the surprise attack keeps its identity but comes 50% keener
## (TS:84-89 — a spread copy whose weight wraps the ORIGINAL def's weight).


static func _bold_keener(base: Array) -> Array:
	var out: Array = []
	for d in base:
		if String(d["id"]) == "rivalsurprise":
			var orig: Callable = d["weight"]
			var d2: Dictionary = d.duplicate()
			d2["weight"] = func(c) -> float: return float(orig.call(c)) * 1.5
			out.append(d2)
		else:
			out.append(d)
	return out


## variant: bold raid (pirate_wind) — sails before the raid clock is due.
static func _bold_raid(bold: bool) -> Dictionary:
	var apply := func(s, _rng) -> void:
		# same refuse as rivalsurprise — no alarm with no raid
		if s.raids_blocked():
			return
		s.launch_rival_raid_now()
		s._fire("audio_play", ["alarm", 0.9, 0.0])
	return {
		"id": "bold_raid",
		"name": "🏴 BOLD SAILS",
		"warn": "Sails where no sails should be…",
		"weight": func(c) -> float: return (0.5 + float(c["chaos"]) * 0.6) if bold else 0.0,
		"duration": [0.1, 0.1],
		"cooldown": 55,
		"apply": apply,
	}


## variant: rival festival (calm_veil) — the rivals throw a feast and lay
## down arms; your tribe is invited (mood + healing, the gift exchange).
static func _rival_festival(calm: bool) -> Dictionary:
	var apply := func(s, _rng) -> void:
		s.pause_raids(45.0)
		s.festival()
		s._fire("audio_play", ["charm", 0.9, 0.0])
	# I-q3: the storyteller's bless mood leans on gift events (×1.3)
	var weight := func(c) -> float:
		return ((0.7 + maxf(0.0, float(c["karma"])) * 0.5) \
				* (1.3 if String(c.get("mood", "")) == "bless" else 1.0)) if calm else 0.0
	return {
		"id": "rival_festival",
		"name": "🎊 RIVAL FESTIVAL",
		"weight": weight,
		"duration": [16.0, 22.0],
		"cooldown": 90,
		"apply": apply,
	}


## variant: siege hoard (catalog III #8) — Punish the Hoard, tribe flavor:
## the richest hoard draws the biggest siege right when it is richest;
## severity rides the ONE dominanceSeverity formula, capped like #3. ALWAYS in
## the deck — below the threshold (or with no dominance reading) the weight
## reads 0 and the pool math never picks it.
static func _siege_hoard() -> Dictionary:
	var weight := func(c) -> float:
		var dom: Variant = c.get("dominance")
		if dom == null or float(dom) <= WorldGenomeScript.DOMINANCE_THRESHOLD:
			return 0.0
		return 0.6 * WorldGenomeScript.dominance_severity(float(dom))
	var apply := func(s, _rng) -> void:
		s.launch_rival_raid_now()
		# a second wave — the siege presses while the hoard is fat
		var wave2 := func() -> void:
			s.launch_rival_raid_now()
		s.after(9.0, wave2)
		s._fire("audio_play", ["alarm", 1.0, 0.0])
	return {
		"id": "siege_hoard",
		"name": "🏹 THE HOARD DRAWS SIEGE",
		"warn": "Torches mass beyond the ridge — they smell your stores…",
		"weight": weight,
		"duration": [16.0, 24.0],
		"cooldown": 100,
		"apply": apply,
	}


## mirror face of the festival (cradle worlds): SAME event id, exactly one
## rule inverted — the feast sours (mood rule); food cost and fires stay.
## Only reachable after a festival survived (the stage's onEnd mirror ledger).
static func _festival_mirror() -> Dictionary:
	var apply := func(s, _rng) -> void:
		s.festival_mirror()
		s._fire("audio_play", ["charm", 0.9, 0.0])
	return {
		"id": "festival",
		"mirrorOf": "festival",
		"name": "🔥 FESTIVAL NIGHT",
		"weight": func(c) -> float: return 0.9 \
				if c.get("mirrors", []).has("festival") else 0.0,
		"duration": [16.0, 22.0],
		"cooldown": 80,
		"apply": apply,
	}


## TS makeTribeChaosEvents (tribeEvents.ts:79-156).
static func make_tribe_chaos_events(world: Dictionary) -> Array:
	var bold: bool = WorldGenomeScript.world_has(world, "raider_bold")   # pirate_wind
	var calm: bool = WorldGenomeScript.world_num(world, "speciation_mult", 1.0) < 1.0  # calm_veil
	# mirror_rule: cradle worlds mirror the festival
	var festival_mirror: bool = WorldGenomeScript.mirror_bucket(world) == "cradle"
	var base: Array = _baseline()
	if bold:
		base = _bold_keener(base)
	var out: Array = []
	out.append_array(base)
	if bold:
		out.append(_bold_raid(bold))
	if calm:
		out.append(_rival_festival(calm))
	out.append(_siege_hoard())
	if festival_mirror:
		out.append(_festival_mirror())
	return out
