## Cell-stage chaos event deck — port of Spore src/game/cell/cellEvents.ts
## (frozen). Static factory: make_cell_chaos_events(world) folds the
## WorldGenome in — a traitless world gets exactly the baseline defs, nothing
## else. Def shape = the M1 ChaosScheduler's (camelCase TS keys):
## id / name / warn? / warnS? / mirrorOf? / weight (Callable on the ctx
## Dictionary) / duration [lo, hi] / cooldown / apply (sim, rng) /
## tick? (sim, elapsed, dt) / end? (sim).
## The apply/tick/end Callables receive the CellSim (the scheduler's "stage")
## and route every audio/camera effect through its hooks (_fire — GDScript
## privacy is advisory; the defs stay data, the sim owns the wiring).
## Def name/warn strings stay the raw English keys — the TS hud renders
## banner titles through t() at display time (hud.ts:325), so the native HUD
## translates them; the i18n audit pins event-field literals to the VI table,
## which carries all of them.
extends RefCounted

const ChaosScript := preload("res://src/game/chaos.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")


static func make_cell_chaos_events(world: Dictionary) -> Array:
	var toxin: bool = WorldGenomeScript.world_has(world, "toxin_rain_cell")             # toxin_sea
	var surge: bool = WorldGenomeScript.world_num(world, "herb_drain_mult", 1.0) > 1.0  # hungry_bloom
	# mirror_rule (catalog III #10): the temperament bucket designates WHICH
	# event carries a mirror face — lean worlds mirror the bloom
	var bloom_mirror: bool = WorldGenomeScript.mirror_bucket(world) == "lean"
	var out: Array = _baseline()
	if toxin:
		out.append(_toxin_clouds(toxin))
	if surge:
		out.append(_algae_surge(surge))
	if bloom_mirror:
		out.append(_bloom_mirror())
	return out


# ---- the 8 baseline defs (cellEvents.ts:12-124, verbatim) --------------------------

static func _baseline() -> Array:
	var out: Array = []

	# meteor
	var meteor_apply := func(s, rng) -> void:
		var a: float = rng.next() * TAU
		var d: float = rng.range(80.0, 420.0)
		var x: float = s.px + cos(a) * d
		var y: float = s.py + sin(a) * d
		s.spawn_meteor_target(x, y)
		var impact := func() -> void:
			s.meteor_impact(x, y)
		s.after(2.5, impact)
	out.append({
		"id": "meteor",
		"name": "☄ METEOR STRIKE",
		"warn": "The water flickers. Something falls from the sky…",
		"weight": func(c) -> float: return 0.6 + float(c["chaos"]),
		"duration": [0.1, 0.1],
		"cooldown": 35,
		"apply": meteor_apply,
	})

	# bloom
	var bloom_apply := func(s, _rng) -> void:
		s.bloom()
		s._fire("audio_play", ["spawn", 0.7, 0.0])
	out.append({
		"id": "bloom",
		"name": "🌿 ALGAL BLOOM",
		"weight": func(c) -> float: return 0.8 - float(c["karma"]) * 0.2,
		"duration": [8.0, 14.0],
		"cooldown": 30,
		"apply": bloom_apply,
	})

	# redtide
	var redtide_apply := func(s, rng) -> void:
		for i in 3:
			var a: float = rng.next() * TAU
			var d: float = rng.range(150.0, 500.0)
			s.add_toxin_zone(s.px + cos(a) * d, s.py + sin(a) * d,
					rng.range(90.0, 150.0), 7.0, rng.range(18.0, 26.0), "redtide")
		s._fire("audio_play", ["toxin", 0.7, 0.0])
	out.append({
		"id": "redtide",
		"name": "🩸 RED TIDE",
		"warn": "The water turns warm and smells of iron…",
		"weight": func(c) -> float: return 0.5 + float(c["chaos"]) * 0.8,
		"duration": [18.0, 26.0],
		"cooldown": 40,
		"apply": redtide_apply,
	})

	# swarm
	var swarm_apply := func(s, _rng) -> void:
		s.spawn_swarm()
		s._fire("audio_play", ["alarm", 0.6, 0.0])
	out.append({
		"id": "swarm",
		"name": "🦈 FEEDING FRENZY",
		"warn": "Tiny teeth glint in the dark…",
		"weight": func(c) -> float: return 0.7 + float(c["chaos"]),
		"duration": [30.0, 30.0],
		"cooldown": 45,
		"apply": swarm_apply,
	})

	# bigbro
	var bigbro_apply := func(s, _rng) -> void:
		s.spawn_big_brother()
		s._fire("cam_shake", [6.0, 1.0])
	out.append({
		"id": "bigbro",
		"name": "👁 THE OLD ONE WAKES",
		"warn": "The seafloor trembles beneath something vast…",
		"weight": func(c) -> float: return (0.5 + float(c["chaos"])) \
				if float(c["chaos"]) > 0.3 else 0.05,
		"duration": [26.0, 26.0],
		"cooldown": 70,
		"apply": bigbro_apply,
	})

	# vents
	var vents_apply := func(s, rng) -> void:
		for i in 2:
			var a: float = rng.next() * TAU
			s.add_vent(s.px + cos(a) * rng.range(200.0, 500.0),
					s.py + sin(a) * rng.range(200.0, 500.0))
		s._fire("audio_play", ["boom", 0.5, 0.0])
	out.append({
		"id": "vents",
		"name": "🌋 VENT ERUPTION",
		"weight": func(_c) -> float: return 0.5,
		"duration": [12.0, 20.0],
		"cooldown": 50,
		"apply": vents_apply,
	})

	# glitch
	var glitch_apply := func(s, _rng) -> void:
		s._fire("audio_play", ["warp", 0.9, 0.0])
		s.chaos.gap = 10.0  # the glitch invites friends
	var glitch_end := func(s) -> void:
		s.chaos.gap = ChaosScript.BASE_GAP
	out.append({
		"id": "glitch",
		"name": "🌀 THE GLITCH",
		"warn": "R̶e̶a̶l̶i̶t̶y̶ ̶b̶u̶f̶f̶e̶r̶i̶n̶g̶…",
		"weight": func(c) -> float: return (0.7 + float(c["chaos"])) \
				if float(c["chaos"]) > 0.55 else 0.02,
		"duration": [12.0, 16.0],
		"cooldown": 90,
		"apply": glitch_apply,
		"end": glitch_end,
	})

	# mutationwave
	var mutationwave_apply := func(s, _rng) -> void:
		s.spawn_mutant_wave()
		s._fire("audio_play", ["spawn", 0.8, 0.0])
	out.append({
		"id": "mutationwave",
		"name": "🧪 MUTATION WAVE",
		"warn": "DNA hums at a frequency you feel in your membrane…",
		"weight": func(c) -> float: return 0.6 + float(c["chaos"]) * 0.6,
		"duration": [0.1, 0.1],
		"cooldown": 60,
		"apply": mutationwave_apply,
	})

	return out


# ---- the 3 world-parameterized defs (cellEvents.ts:137-182) ------------------------

## variant: toxin clouds (toxin_sea) — surprise hit (no warn): wide, slow,
## drifting clouds with a light sting; the zone system stings whatever swims
## in, and the clouds lean toward the player while the event runs.
static func _toxin_clouds(toxin: bool) -> Dictionary:
	var apply := func(s, rng) -> void:
		for i in 2:
			var a: float = rng.next() * TAU
			var d: float = rng.range(60.0, 240.0)
			# a cloud, not a red tide: wider, softer, longer-lived
			s.add_toxin_zone(s.px + cos(a) * d, s.py + sin(a) * d,
					rng.range(120.0, 170.0), 3.0, 26.0, "clouds")
		s._fire("audio_play", ["toxin", 0.5, 0.0])
	var tick := func(s, _elapsed, dt) -> void:
		s.drift_toxin_clouds(dt)
	return {
		"id": "toxin_clouds",
		"name": "☣ TOXIN CLOUDS",
		"weight": func(c) -> float: return 5.0 \
				if toxin and float(c["chaos"]) > 0.35 else 0.0,
		"duration": [10.0, 18.0],
		"cooldown": 40,
		"apply": apply,
		"tick": tick,
	}


## variant: runaway bloom (hungry_bloom) — the base bloom, but the whole
## grazer population booms on the windfall.
static func _algae_surge(surge: bool) -> Dictionary:
	var apply := func(s, _rng) -> void:
		s.algae_surge()
		s._fire("audio_play", ["spawn", 0.8, 0.0])
	return {
		"id": "algae_surge",
		"name": "🌿 RUNAWAY BLOOM",
		"weight": func(c) -> float: return (0.9 - float(c["karma"]) * 0.2) \
				if surge else 0.0,
		"duration": [10.0, 16.0],
		"cooldown": 45,
		"apply": apply,
	}


## mirror face of the bloom (lean worlds): SAME event id, exactly one rule
## inverted — the flora direction turns on itself (blight), the pellet
## sprinkle is identical. Only queues after a bloom survived (stage onEnd).
static func _bloom_mirror() -> Dictionary:
	var apply := func(s, _rng) -> void:
		s.blight()
		s._fire("audio_play", ["spawn", 0.7, 0.0])
	return {
		"id": "bloom",
		"mirrorOf": "bloom",
		"name": "🌿 ALGAL BLOOM",
		"weight": func(c) -> float: return 1.2 \
				if c.get("mirrors", []).has("bloom") else 0.0,
		"duration": [8.0, 14.0],
		"cooldown": 30,
		"apply": apply,
	}
