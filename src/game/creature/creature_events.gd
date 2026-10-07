## Creature-stage chaos event deck — port of Spore src/game/creature/
## creatureEvents.ts (frozen). Static factory: make_creature_chaos_events(world)
## folds the WorldGenome in — a traitless world gets exactly the baseline defs.
## Def shape = the M1 ChaosScheduler's (camelCase TS keys): id / name / warn? /
## warnS? / mirrorOf? / weight (Callable on the ctx Dictionary) / duration
## [lo, hi] / cooldown / apply (sim, rng) / tick? (sim, elapsed, dt) / end? (sim).
## The apply Callables receive the CreatureSim (the scheduler's "stage") and
## route every audio/camera effect through its hooks (_fire — GDScript privacy
## is advisory; the defs stay data, the sim owns the wiring).
## Def name/warn strings stay the raw English keys — the TS hud renders banner
## titles through t() at display time, so the native HUD translates them.
## DIVERGENCE (creatureEvents.ts:47-48): earthquake's three fire blisters are
## jittered by two UNSEEDED Math.random() sites in TS — no seeded stream exists
## to match. The port keeps both draws (count identical) but sources them from
## the deck rng inside apply, so they land in the chaos stream position; TS
## stream parity is unobservable there by construction.
extends RefCounted

const WorldGenomeScript := preload("res://src/evo/world_genome.gd")


## Old Blood is the only catalog trait seeding the titan archetype — gate the
## titan on the ecoSeed itself, not on a number it happens to also set.
## (TS seedsTitans, creatureEvents.ts:13-14.)
static func _seeds_titans(w: Dictionary) -> bool:
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
			if e is Dictionary and e.get("kind") == "ecoSeed" \
					and e.get("archetype") == "titan":
				return true
	return false


static func make_creature_chaos_events(world: Dictionary) -> Array:
	var bold: bool = WorldGenomeScript.world_has(world, "raider_bold")   # pirate_wind
	var titan: bool = _seeds_titans(world)                               # old_blood
	# mirror_rule: wildcard worlds mirror the soft rain
	var rain_mirror: bool = WorldGenomeScript.mirror_bucket(world) == "wildcard"
	var out: Array = _baseline()
	# variant: night pack (pirate_wind) — a coordinated pack hunts as one
	# body; silent when the world runs hot
	if bold:
		out.append(_night_pack(bold))
	# variant: titans walk (old_blood) — one huge, calm wanderer crosses the
	# land; rare, harmless, hunting it pays the world's poor meal tax
	if titan:
		out.append(_titans_walk(titan))
	# variant: predator convergence (catalog III #3) — Punish the Hoard: when
	# the player's line holds >60% of the regional biomass, multiple predator
	# species converge; severity rides the ONE dominanceSeverity formula and
	# is capped so it can never pile past what maxActive absorbs
	out.append(_predator_convergence())
	# R13 transposon (experience redesign) — the deck's ONE cosmetic gene-jump:
	# always gated in (weight modest), the hue mutation is the single sanctioned
	# player-genome write (see context.transposon_apply)
	out.append(_transposon())
	# mirror face of the soft rain (wildcard worlds): SAME event id, exactly
	# one rule inverted — the berry swell rots; the rain still falls
	if rain_mirror:
		out.append(_rain_mirror())
	return out


# ---- the 8 baseline defs (creatureEvents.ts:16-127, verbatim) ----------------------

static func _baseline() -> Array:
	var out: Array = []

	# volcano
	var volcano_apply := func(s, rng) -> void:
		for i in 5:
			var x: float = float(s.px) + rng.range(-500.0, 500.0)
			var z: float = float(s.pz) + rng.range(-160.0, 160.0)
			var lava := func() -> void:
				s.add_hazard(x, z, 64.0, 12.0, 14.0, "lava")
			s.after(rng.range(1.0, 12.0), lava)
		s._fire("audio_play", ["quake", 0.9, 0.0])
		s._fire("cam_shake", [8.0, 1.2])
	out.append({
		"id": "volcano",
		"name": "🌋 VOLCANIC ERUPTION",
		"warn": "The mountain groans. Ash whispers down…",
		"weight": func(c) -> float: return 0.6 + float(c["chaos"]),
		"duration": [16.0, 24.0],
		"cooldown": 60,
		"apply": volcano_apply,
	})

	# earthquake
	var earthquake_apply := func(s, rng) -> void:
		s._fire("cam_shake", [9.0, 3.0])
		s._fire("audio_play", ["quake", 1.0, 0.0])
		for i in 3:
			# the two Math.random() jitter sites (see header DIVERGENCE note)
			var x: float = float(s.px) + float(i - 1) * 220.0 + rng.next() * 120.0
			var z: float = float(s.pz) + (rng.next() - 0.5) * 200.0
			var fire := func() -> void:
				s.add_hazard(x, z, 46.0, 10.0, 6.0, "fire")
			s.after(1.0 + float(i) * 0.8, fire)
	out.append({
		"id": "earthquake",
		"name": "🫨 EARTHQUAKE",
		"warn": "Tiny pebbles begin to hop…",
		"weight": func(c) -> float: return 0.6 + float(c["chaos"]) * 0.7,
		"duration": [6.0, 9.0],
		"cooldown": 50,
		"apply": earthquake_apply,
	})

	# stampede
	var stampede_apply := func(s, _rng) -> void:
		s.stampede()
		s._fire("audio_play", ["alarm", 0.7, 0.0])
	out.append({
		"id": "stampede",
		"name": "🐂 STAMPEDE",
		"warn": "The ground drums. Many hooves…",
		"weight": func(c) -> float: return 0.7 + float(c["chaos"]) * 0.6,
		"duration": [14.0, 14.0],
		"cooldown": 55,
		"apply": stampede_apply,
	})

	# nightraid
	# I-q3: the storyteller's twist mood leans on threat events (×1.3)
	var nightraid_apply := func(s, _rng) -> void:
		s.night_raid()
		s._fire("audio_play", ["alarm", 0.8, 0.0])
	out.append({
		"id": "nightraid",
		"name": "🌙 NIGHT RAID",
		"warn": "Eyes open in the dark…",
		"weight": func(c) -> float:
			return ((1.2 + float(c["chaos"])) * (1.3 if String(c.get("mood", "")) == "twist" else 1.0)) \
					if bool(c.get("night", false)) else 0.05,
		"duration": [20.0, 20.0],
		"cooldown": 70,
		"apply": nightraid_apply,
	})

	# mutationstorm
	var mutationstorm_apply := func(s, _rng) -> void:
		s._fire("audio_play", ["warp", 0.8, 0.0])
		s.mutation_storm_zap()
	out.append({
		"id": "mutationstorm",
		"name": "🧪 MUTATION STORM",
		"warn": "Purple lightning knits new genes in the air…",
		"weight": func(c) -> float: return 0.6 + float(c["chaos"]),
		"duration": [10.0, 14.0],
		"cooldown": 65,
		"apply": mutationstorm_apply,
	})

	# glorp
	var glorp_apply := func(s, _rng) -> void:
		s.glorp()
		s._fire("audio_play", ["spawn", 0.8, 0.0])
	out.append({
		"id": "glorp",
		"name": "🫧 A GLORP APPEARS",
		"weight": func(c) -> float: return 0.4 + (1.0 - maxf(0.0, float(c["karma"]))) * 0.3,
		"duration": [8.0, 12.0],
		"cooldown": 80,
		"apply": glorp_apply,
	})

	# rain
	var rain_apply := func(s, _rng) -> void:
		s.rain()
		s._fire("audio_play", ["heal", 0.6, 0.0])
	out.append({
		"id": "rain",
		"name": "🌧 SOFT RAIN",
		"weight": func(_c) -> float: return 0.7,
		"duration": [14.0, 20.0],
		"cooldown": 45,
		"apply": rain_apply,
	})

	# meteor
	var meteor_apply := func(s, rng) -> void:
		var x: float = float(s.px) + rng.range(-500.0, 500.0)
		var z: float = float(s.pz) + rng.range(-120.0, 120.0)
		s._fire("audio_play", ["warp", 0.6, 0.0])
		var boom := func() -> void:
			s.drop_meteor(x, z)
		s.after(2.5, boom)
	out.append({
		"id": "meteor",
		"name": "☄ METEOR CRASH",
		"warn": "A whistling star scratches the sky…",
		"weight": func(c) -> float: return 0.5 + float(c["chaos"]),
		"duration": [0.1, 0.1],
		"cooldown": 75,
		"apply": meteor_apply,
	})

	return out


# ---- the R13 transposon (experience redesign) ---------------------------------------

## Raw EN display keys — the hud translates at draw (banner) / fire (toast);
## vi.csv carries the rows.
const TRANSPOSON_NAME := "🧬 TRANSPOSON JUMP"
const TRANSPOSON_WARN := "The air tingles — your COLORS are about to shift…"
const TRANSPOSON_TOAST := "A transposon jumped — your hue changed! Revert is free in the LOOK tab."


## variant: transposon — a 2.5 s omen names the hue shift BEFORE it lands (the
## chaos law), then the apply jumps the player's hue ±30 (seeded direction, the
## deck rng) and stores the pre-shift hue for the free LOOK-tab revert. Once
## per run, both halves of the latch visible here: the weight gates to 0 once
## ctx.transposonFired is set (the sim folds the flags latch into the chaos
## ctx), and the warn_fn reads the same latch through the weight's box so a
## post-fire re-pick (the scheduler's 0.01 weight floor) degrades to an
## immediate silent no-op apply instead of a spurious second omen.
static func _transposon() -> Dictionary:
	var box := {"fired": false}
	var weight := func(c) -> float:
		box["fired"] = bool(c.get("transposonFired", false))
		return (0.35 + float(c["chaos"]) * 0.2) \
				if not bool(c.get("transposonFired", false)) else 0.0
	var warn_fn := func() -> Variant:
		return null if bool(box["fired"]) else TRANSPOSON_WARN
	var apply := func(s, rng) -> void:
		# the trigger() path bypasses the weight gate — apply re-guards
		if bool(s.ctx.flags.get("transposonFired", false)):
			return
		var before: Variant = s.ctx.transposon_apply(rng)
		if before == null:
			return
		s._fire("audio_play", ["warp", 0.7, 0.0])
		s._fire("hud_toast", [s.tr(TRANSPOSON_TOAST), "chaos", "🧬"])
	return {
		"id": "transposon",
		"name": TRANSPOSON_NAME,
		"warn_fn": warn_fn,
		"warnS": 2.5,  # the omen window is pinned — a per-def warnS wins over the temperament bucket
		"weight": weight,
		"duration": [0.1, 0.1],  # the mutation is instantaneous (the meteor shape)
		"cooldown": 999,
		"apply": apply,
	}


# ---- the world-parameterized faces (creatureEvents.ts:129-200) ---------------------

## variant: night pack (pirate_wind) — the pack's warn is re-read at spawn
## time: weight() records the live chaos level first, so at high chaos the
## pack gives no warning at all. (The trigger() path uses the last polled
## value; cosmetic only — TS comment verbatim.) GDScript lambdas capture by
## value, so the mutable `let packChaos` rides a Dictionary box (reference).
static func _night_pack(bold: bool) -> Dictionary:
	var box := {"packChaos": 0.0}
	var weight := func(c) -> float:
		box["packChaos"] = float(c["chaos"])
		return (1.1 + float(c["chaos"]) * 0.8) \
				if bold and bool(c.get("night", false)) else 0.0
	var warn_fn := func() -> Variant:
		return null if float(box["packChaos"]) > 0.5 \
				else "Something moves between the trees…"
	var apply := func(s, _rng) -> void:
		s.night_pack()
		s._fire("audio_play", ["alarm", 0.8, 0.0])
	return {
		"id": "night_pack",
		"name": "🐺 NIGHT PACK",
		"warn_fn": warn_fn,
		"weight": weight,
		"duration": [20.0, 20.0],
		"cooldown": 75,
		"apply": apply,
	}


## variant: titans walk (old_blood) — one huge, calm wanderer crosses the
## land; rare, harmless, hunting it pays the world's poor meal tax.
static func _titans_walk(titan: bool) -> Dictionary:
	var apply := func(s, _rng) -> void:
		s.titan_walk()
		s._fire("audio_play", ["quake", 0.5, 0.0])
	return {
		"id": "titans_walk",
		"name": "🗿 A TITAN WALKS",
		"warn": "The ground trembles in a slow rhythm…",
		"weight": func(c) -> float: return (0.35 + float(c["chaos"]) * 0.3) if titan else 0.0,
		"duration": [26.0, 30.0],
		"cooldown": 140,
		"apply": apply,
	}


## variant: predator convergence (catalog III #3) — Punish the Hoard. The
## weight rides dominanceSeverity() above the threshold; 0 below or when the
## ctx carries no dominance reading at all (TS `c.dominance !== undefined`).
static func _predator_convergence() -> Dictionary:
	var weight := func(c) -> float:
		var dom: Variant = c.get("dominance")
		if dom == null or float(dom) <= WorldGenomeScript.DOMINANCE_THRESHOLD:
			return 0.0
		return 0.6 * WorldGenomeScript.dominance_severity(float(dom))
	var apply := func(s, _rng) -> void:
		s.converge_predators()
		s._fire("audio_play", ["alarm", 0.9, 0.0])
	return {
		"id": "predator_convergence",
		"name": "🩸 PREDATORS CONVERGE",
		"warn": "Every hunter on the island turns toward you…",
		"weight": weight,
		"duration": [18.0, 26.0],
		"cooldown": 90,
		"apply": apply,
	}


## mirror face of the soft rain (wildcard worlds): SAME event id, exactly one
## rule inverted — the berry swell rots; the rain still falls. Only queues
## after a rain survived (the stage's onEnd mirror ledger).
static func _rain_mirror() -> Dictionary:
	var apply := func(s, _rng) -> void:
		s.rain_mirror()
		s._fire("audio_play", ["heal", 0.6, 0.0])
	return {
		"id": "rain",
		"mirrorOf": "rain",
		"name": "🌧 SOFT RAIN",
		"weight": func(c) -> float: return 0.9 \
				if c.get("mirrors", []).has("rain") else 0.0,
		"duration": [14.0, 20.0],
		"cooldown": 45,
		"apply": apply,
	}
