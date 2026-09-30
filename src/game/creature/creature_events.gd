## Creature-stage chaos event deck — port of Spore src/game/creature/
## creatureEvents.ts (frozen). TASK 5 owns the full deck (the baseline defs —
## volcano / earthquake / stampede / nightraid / mutationstorm / glorp — plus
## the world-parameterized faces night_pack / titans_walk / convergence and
## the rain mirror). This seam exists so the Task 2 sim can construct its
## ChaosScheduler at the TS stream position (CreatureStage.ts:157): the
## factory itself draws nothing from any rng (weights are Callables evaluated
## at update time), so an empty deck is stream-neutral until the real defs
## land. Def shape = the M1 ChaosScheduler's (camelCase TS keys): id / name /
## warn? / warnS? / mirrorOf? / weight (Callable on the ctx Dictionary) /
## duration [lo, hi] / cooldown / apply (sim, rng) / tick? (sim, elapsed, dt) /
## end? (sim).
extends RefCounted


static func make_creature_chaos_events(_world: Dictionary) -> Array:
	return []  # Task 5 folds the WorldGenome in (seedsTitans gate et al.)
