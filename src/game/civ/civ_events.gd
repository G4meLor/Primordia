## Civ-stage chaos event deck — port of Spore src/game/civ/civEvents.ts
## (frozen, 79 lines). Static factory: make_civ_chaos_events(world) folds the
## WorldGenome in — a traitless world gets exactly the baseline defs.
## Def shape = the M1 ChaosScheduler's (camelCase TS keys): id / name / warn? /
## weight (Callable on the ctx Dictionary) / duration [lo, hi] / cooldown /
## apply (sim, rng) / tick? (sim, elapsed, dt). No end defs (TS has none), and
## the civ wiring passes no onEnd hook — chaos.gd's _fire_hook no-ops on the
## missing key.
## The factory draws NOTHING from any rng stream — gold/calm read the world
## genome only and fold into the weight Callables at build time (the TS deck
## fns close over the same booleans, computed at makeCivChaosEvents time
## WITHOUT touching the stage rng), so the scheduler construction stays
## draw-free and the stage stream stays TS-aligned (the civ_sim.gd header
## note). The gold/calm ternaries inside the weight fns port verbatim even
## though the defs only exist when the gate is open.
## Def name/warn strings stay the raw English keys — the TS hud renders banner
## titles through t() at display time, so the native HUD translates them.
##
## R14 world attach: three MORE trait-gated defs fold in at make time —
## toxin_sea → acid_monsoon, hungry_bloom → famine, mutation_moon → moon_cult
## (the spec's R14 row; the cell deck's toxin_clouds precedent). These are
## NATIVE-side events (the frozen TS deck has none of them — the traitless
## fold stays byte-identical to civEvents.ts), gated by the world genome's
## trait IDS via WorldGenome.has_trait (hungry_bloom carries no flag effect,
## so the flag-based world_has cannot see it). They keep the def shape —
## famine/monsoon ride the scheduler's own warn→apply→(tick) clock (no
## hand-rolled timers), the cult is the quake/rebellion instant shape.
extends RefCounted

const WorldGenomeScript := preload("res://src/evo/world_genome.gd")


# ---- the 4 baseline defs (civEvents.ts:10-45, verbatim) ---------------------------

static func _baseline() -> Array:
	var out: Array = []

	# quake
	out.append({
		"id": "quake",
		"name": "🫨 MEGA-QUAKE",
		"warn": "Seismographs scream across the continent…",
		"weight": func(c) -> float: return 0.7 + float(c["chaos"]),
		"duration": [0.1, 0.1],
		"cooldown": 55,
		"apply": func(s, _rng): s.earthquake(),
	})

	# rebellion
	out.append({
		"id": "rebellion",
		"name": "🔥 UNREST SPREADS",
		"weight": func(c) -> float: return 0.6 + maxf(0.0, -float(c["karma"])) * 0.8,
		"duration": [0.1, 0.1],
		"cooldown": 45,
		"apply": func(s, _rng): s.rebellion(),
	})

	# goldenage
	out.append({
		"id": "goldenage",
		"name": "✨ GOLDEN AGE",
		"weight": func(c) -> float: return 0.6 + maxf(0.0, float(c["karma"])) * 0.9,
		"duration": [14.0, 20.0],
		"cooldown": 80,
		"apply": func(s, _rng): s.golden_age(),
	})

	# worldwar
	out.append({
		"id": "worldwar",
		"name": "💥 WORLD WAR",
		"warn": "Mobilization everywhere. Ultimatums fly…",
		"weight": func(c) -> float: return 0.6 + float(c["chaos"]),
		"duration": [10.0, 10.0],
		"cooldown": 70,
		"apply": func(s, _rng): s.rival_war(),
	})

	return out


# ---- the world-parameterized faces (civEvents.ts:47-79) ---------------------------

## variant: golden rival (swift_world) — the rivals' output gains an additive
## 30% on top of the still-running baseline for the duration: harder shells,
## faster growth, keener culture push.
static func _golden_rival(gold: bool) -> Dictionary:
	return {
		"id": "golden_rival",
		"name": "🏆 RIVAL GOLDEN AGE",
		"warn": "Foreign banners gleam — their forges never cool…",
		"weight": func(c) -> float: return (0.5 + float(c["chaos"]) * 0.5) if gold else 0.0,
		"duration": [30.0, 30.0],
		"cooldown": 90,
		"apply": func(s, _rng): s.rival_surge_begin(),
		"tick": func(s, _elapsed, dt): s.rival_surge_tick(dt),
	}


## variant: trade winds (calm_veil) — a quiet world trades: your national
## output refills 20% faster and every city gains people while it blows.
## I-q3: the storyteller's bless mood leans on gift events (×1.3) — it rides
## INSIDE the weight fn (the M4 rival_festival precedent).
static func _trade_winds(calm: bool) -> Dictionary:
	var weight := func(c) -> float:
		return ((0.6 + maxf(0.0, float(c["karma"])) * 0.6) \
				* (1.3 if String(c.get("mood", "")) == "bless" else 1.0)) if calm else 0.0
	return {
		"id": "trade_winds",
		"name": "⛵ TRADE WINDS",
		"warn": "Sails crowd every horizon — markets hum…",
		"weight": weight,
		"duration": [40.0, 40.0],
		"cooldown": 100,
		"apply": func(s, _rng): s.trade_winds_begin(),
		"tick": func(s, _elapsed, dt): s.trade_winds_tick(dt),
	}


## R14 trait-gated faces — the world genome's civ-side reach. Weights follow
## the golden_rival shape (0.5 + chaos×0.5, chaos-revealed traits lean on the
## chaos meter); the gate bool rides the weight fn defensively (the def only
## exists when the fold let it in, the _golden_rival pattern).

## toxin_sea → acid monsoon: acid rain falls on EVERY city on the planet —
## hp drains ~2/s across the 6 s span (warn phase FIRST, the chaos law; the
## burning floor 5.0 holds).
static func _acid_monsoon(on: bool) -> Dictionary:
	return {
		"id": "acid_monsoon",
		"name": "☣️ ACID MONSOON",
		"warn": "The clouds curdle — acid rain gathers over every city…",
		"weight": func(c) -> float: return (0.5 + float(c["chaos"]) * 0.5) if on else 0.0,
		"duration": [6.0, 6.0],
		"cooldown": 90,
		"apply": func(s, _rng): s.acid_monsoon_begin(),
		"tick": func(s, _elapsed, dt): s.acid_monsoon_tick(dt),
	}


## hungry_bloom → famine: the granaries run dry — the national-output regen
## clock freezes for the event's EXACT 20 s active span (civ_sim.update gates
## the regenT accumulation on chaos.is_active("famine") — the scheduler's own
## duration is the timer, nothing hand-rolled).
static func _famine(on: bool) -> Dictionary:
	return {
		"id": "famine",
		"name": "🌾 FAMINE",
		"warn": "The granaries run dry — blight rides the wind…",
		"weight": func(c) -> float: return (0.5 + float(c["chaos"]) * 0.5) if on else 0.0,
		"duration": [20.0, 20.0],
		"cooldown": 100,
		"apply": func(s, _rng): s.famine_begin(),
	}


## mutation_moon → moon cult: crescent worshippers preach in your streets —
## a ONE-SHOT culture burst of +15% of the current lane (the slider cap
## holds; no tick — the quake/rebellion instant shape).
static func _moon_cult(on: bool) -> Dictionary:
	return {
		"id": "moon_cult",
		"name": "🌗 MOON CULT",
		"warn": "Moonlight gathers worshippers on the ridgelines…",
		"weight": func(c) -> float: return (0.5 + float(c["chaos"]) * 0.5) if on else 0.0,
		"duration": [0.1, 0.1],
		"cooldown": 75,
		"apply": func(s, _rng): s.moon_cult(),
	}


## TS makeCivChaosEvents (civEvents.ts:47-79): BASELINE + (gold ? golden_rival)
## + (calm ? trade_winds). R14: + (toxin_sea ? acid_monsoon) + (hungry_bloom ?
## famine) + (mutation_moon ? moon_cult) — the trait-ID fold gates.
static func make_civ_chaos_events(world: Dictionary) -> Array:
	# swift_world: growth_mult above 1.2 lights the rival golden age (TS:48)
	var gold: bool = WorldGenomeScript.world_num(world, "growth_mult", 1.0) > 1.2
	# calm_veil: the quiet-world proxy (speciation_mult below 1, TS:49)
	var calm: bool = WorldGenomeScript.calm_proxy(world)
	var out: Array = _baseline()
	if gold:
		out.append(_golden_rival(gold))
	if calm:
		out.append(_trade_winds(calm))
	# R14 — the world genome reaches the civ stage (fold-time gates)
	if WorldGenomeScript.has_trait(world, "toxin_sea"):
		out.append(_acid_monsoon(true))
	if WorldGenomeScript.has_trait(world, "hungry_bloom"):
		out.append(_famine(true))
	if WorldGenomeScript.has_trait(world, "mutation_moon"):
		out.append(_moon_cult(true))
	return out
