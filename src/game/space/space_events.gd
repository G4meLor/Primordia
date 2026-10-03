## Space-stage chaos event deck — port of Spore src/game/space/spaceEvents.ts
## (frozen, 77 lines). Static factory: make_space_chaos_events(world) folds the
## WorldGenome in — a traitless world gets exactly the baseline defs.
## Def shape = the M1 ChaosScheduler's (camelCase TS keys): id / name / warn? /
## weight (Callable on the ctx Dictionary) / duration [lo, hi] / cooldown /
## apply (sim, rng) / end? (sim). No tick defs (TS has none).
## PIRATE_LULL CARRIES THE PORT'S FIRST END HOOK: chaos.gd dispatches the def's
## end Callable with the stage when the event expires (the tribe beast
## precedent) — begin raises sim.pirateLull, end clears it.
## THE TRIBUTE DECK/CTX SPLIT (spaceEvents.ts:45 vs SpaceStage.ts:539-547): the
## def carries NO end — its apply only demands; the STAGE ctx's onEnd (wired in
## space_sim.gd update_chaos) punishes an unpaid demand with 3 pirates.
## THE ONE Math.random SITE (spaceEvents.ts:18): the pirate-count draw
## `2 + Math.floor(Math.random() * 2)` ports to the deck rng the scheduler
## passes into apply — the draw lands in the chaos stream position (the M4
## storm precedent; see the tribe_events.gd header). Replay pins live in
## tests/test_space_events.gd.
## The factory draws NOTHING from any rng stream — nebula/calm read the world
## genome only and fold into the weight Callables at build time (the TS deck fn
## closes over the same booleans, computed at makeSpaceChaosEvents time WITHOUT
## touching the stage rng), so the scheduler construction stays draw-free and
## the stage stream stays TS-aligned (the civ_events.gd header; the M5
## draw-nothing ruling). The nebula/calm ternaries inside the weight fns port
## verbatim even though the defs only exist when the gate is open.
## Def name/warn strings stay the raw English keys — the TS hud renders banner
## titles through t() at display time, so the native HUD translates them.
extends RefCounted

const WorldGenomeScript := preload("res://src/evo/world_genome.gd")


# ---- the 4 baseline defs (spaceEvents.ts:10-47, verbatim) ---------------------------

static func _baseline() -> Array:
	var out: Array = []

	# pirates — the ONE Math.random site in the deck (spaceEvents.ts:18): the
	# count rides the scheduler's deck rng in-stream (the M4 storm precedent)
	out.append({
		"id": "pirates",
		"name": "☠ PIRATE AMBUSH",
		"warn": "Unfriendly signatures on the scope…",
		"weight": func(c) -> float: return 0.7 + float(c["chaos"]),
		"duration": [30.0, 30.0],
		"cooldown": 55,
		"apply": func(s, rng) -> void: s.spawn_pirates(2 + floori(rng.next() * 2.0)),
	})

	# blackhole
	out.append({
		"id": "blackhole",
		"name": "🕳 ROGUE BLACK HOLE",
		"warn": "Starlight bends where it should not…",
		"weight": func(c) -> float: return 0.5 + float(c["chaos"]) * 0.8,
		"duration": [45.0, 45.0],
		"cooldown": 90,
		"apply": func(s, _rng) -> void: s.spawn_black_hole(),
	})

	# flare — the deck's one CONSTANT weight
	out.append({
		"id": "flare",
		"name": "☀️ SOLAR FLARE",
		"warn": "The sun swells and spits…",
		"weight": func(_c) -> float: return 0.6,
		"duration": [0.1, 0.1],
		"cooldown": 60,
		"apply": func(s, _rng) -> void: s.solar_flare(),
	})

	# tribute — the def demands; the ctx's onEnd punishes unpaid (the split)
	out.append({
		"id": "tribute",
		"name": "📦 VOID EMPIRE TAX",
		"warn": "A shadow shaped like paperwork falls across your ship…",
		"weight": func(c) -> float: return 0.5 + maxf(0.0, -float(c["karma"])) * 0.7,
		"duration": [12.0, 12.0],
		"cooldown": 100,
		"apply": func(s, _rng) -> void: s.demand_tribute(60.0),
	})

	return out


# ---- the world-parameterized faces (spaceEvents.ts:49-77) ---------------------------

## variant: nebula flip (mutation_moon) — a charged nebula washes one living
## world and forces two speciations there (spaceEvents.ts:54-64).
static func _nebula_flip(nebula: bool) -> Dictionary:
	return {
		"id": "nebula_flip",
		"name": "🌌 MUTATION NEBULA",
		"warn": "A rainbow wall of charged gas rolls in…",
		"weight": func(c) -> float: return (0.5 + float(c["chaos"]) * 0.7) if nebula else 0.0,
		"duration": [0.1, 0.1],
		"cooldown": 80,
		"apply": func(s, _rng) -> void: s.nebula_flip(),
	}


## variant: pirate lull (calm_veil) — the pirates stand down while the calm
## lasts; the scope stays honest, the siege simply pauses (spaceEvents.ts:65-75).
## The FIRST deck def with an end hook in the whole port.
static func _pirate_lull(calm: bool) -> Dictionary:
	return {
		"id": "pirate_lull",
		"name": "🕊 PIRATE LULL",
		"weight": func(c) -> float: return (0.6 + maxf(0.0, float(c["karma"])) * 0.5) if calm else 0.0,
		"duration": [30.0, 30.0],
		"cooldown": 100,
		"apply": func(s, _rng) -> void: s.pirate_lull_begin(),
		"end": func(s) -> void: s.pirate_lull_end(),
	}


## TS makeSpaceChaosEvents (spaceEvents.ts:49-77): BASELINE + (nebula ?
## nebula_flip) + (calm ? pirate_lull).
static func make_space_chaos_events(world: Dictionary) -> Array:
	# mutation_moon: the wild_mutations flag (TS:50)
	var nebula: bool = WorldGenomeScript.world_has(world, "wild_mutations")
	# calm_veil: the quiet-world proxy (speciation_mult below 1, TS:51)
	var calm: bool = WorldGenomeScript.calm_proxy(world)
	var out: Array = _baseline()
	if nebula:
		out.append(_nebula_flip(nebula))
	if calm:
		out.append(_pirate_lull(calm))
	return out
