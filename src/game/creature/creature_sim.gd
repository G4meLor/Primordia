## CREATURE STAGE sim core — the side-view island as a headless RefCounted:
## state structs, seedLandEcology, spawn tables, player physics/interactions,
## world objects (bushes/bones/nests/hazards), death/respawn, the eco tick and
## the chaos update loop. Port of Spore src/game/creature/CreatureStage.ts
## (frozen), minus the render pass and the scene-only surfaces (editor
## overlay, tutorial engine, camera/fx stepping, HUD objective — scene layer,
## later tasks). NPC AI (update_ents), the charm minigame (try_charm/
## update_charm) and the founding/tribe flow are LATER TASKS: the call sites
## stand here in TS order with stub bodies so the tick shape is already true.
##
## Architecture (M2 ruling, same as cell_sim.gd): CreatureSim.new(ctx,
## rng_branch, hooks) —
##   ctx        the M1 GameContext; sim calls ctx methods directly
##   rng_branch the stage's dedicated Rng (the CALLER draws ctx.rng.branch(),
##              mirroring TS `this.rng = ctx.rng.branch()`)
##   hooks      Dictionary of Callables for every scene/audio effect; missing
##              key = silent no-op so tests can record selectively
## No Input singleton reads: update(dt, inp) takes an input SNAPSHOT
## Dictionary (mx/my/wx/wy/down/clicked/take_click/keys_held/keys_pressed —
## keys_pressed canonical) the scene layer builds and tests construct
## literally. Ent/world dicts keep the TS camelCase field names verbatim;
## the ent `stats` dict carries the M1 stats.gd shape (snake_case keys —
## the established compute_creature_stats port surface).
##
## Recorded divergences:
##  - TS first-frame death idiom `deathFade <= dt` (CreatureStage.ts:618) ->
##    deathStarted bool (the M2 ruling: float-accumulate re-triggers at
##    variable dt).
##  - The ent seed/gait/facing draws ARE TS-true here (stage rng, TS:377-390)
##    — no playerSeed divergence in this stage (that was a CellStage quirk).
##  - get_is_night / get_dominance hooks: TS computes both from sim state
##    (dayPhase, dominanceShare) — the sim still computes them as defaults;
##    a present hook overrides (scene/test injection seam).
##  - The wing-hop fx burst anchors at (px, py) in TS — py is the JUMP HEIGHT
##    there, not the depth-squashed z. Ported verbatim (TS quirk, TS:674).
## TS-optional ent fields (eggT/corpseT/flying/lifespanStampede/pressCd) stay
## ABSENT until set, matching TS undefined semantics — readers use .get().
class_name CreatureSim
extends RefCounted

const StatsScript := preload("res://src/evo/stats.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const ChaosScript := preload("res://src/game/chaos.gd")
const CreatureEventsScript := preload("res://src/game/creature/creature_events.gd")
const NamesScript := preload("res://src/evo/names.gd")
const PartsScript := preload("res://src/evo/parts.gd")

## Seconds between counted grudge presses for one ent (an engagement, not a
## frame) — mirrors the eco-side harassment valve. Kept stage-local: the valve
## constants are eco-internal. (Consumed by the Task 3 AI loop.)
const PRESS_COOLDOWN := 20.0

const Z_TO_Y := 0.62    # pseudo-depth squash
const Z_MIN := -200.0
const Z_MAX := 240.0
const WORLD_HALF := 2700.0

# ---- hooks ---------------------------------------------------------------------

var ctx: Variant = null           # TS game.context
var rng: Variant = null           # TS this.rng (the stage branch)
var _hooks: Dictionary = {}


## Missing hook key = silent no-op (Callable check) — tests record selectively.
func _fire(hook: String, args: Array) -> void:
	var c: Variant = _hooks.get(hook)
	if c is Callable:
		(c as Callable).callv(args)


# ---- state (TS field names verbatim) ---------------------------------------------

# player
var px := -2400.0
var pz := 20.0
var pvx := 0.0
var pvz := 0.0
var py := 0.0               # jump height offset
var pvy := 0.0
var php := 100.0
var pmaxHp := 100.0
var pStats: Dictionary = {}
var facing := 1
var gait := 0.0
var speed01 := 0.0
var attackT := 0.0
var hurtT := 0.0
var eatT := 0.0
var biteCd := 0.0
var invuln := 2.0
var jumpCd := 0.0

# world
var ents: Array[Dictionary] = []
var bushes: Array = []      # {x, z, food, regrow, seed}
var bones: Array = []       # {x, z, taken, kind}
var nests: Array = []       # {x, z, speciesId, members}
var hazards: Array = []     # {x, z, r, dps, ttl, kind}
var nextEid := 1
var time := 0.0
var dayPhase := 0.15        # start morning
var eco: Variant = null
var ecoTimer := 0.0
# TS ChaosScheduler<CreatureStage> (private `chaos` + getter in TS; GDScript
# keeps one public field). Constructed in _init at the TS stream position.
var chaos: Variant = null
## TS deckSeed (C1: decks rebuilt from a stale WorldGenome) — ensure_deck()
## compares and rebuilds.
var deckSeed := -1

# charm minigame (state fields now; the bodies are Task 4)
var charmTarget: Variant = null
var charmHits := 0
var charmMarker := 0.0
var charmDir := 1
var charmMustExit := false
var charmsSeen := 0
var barrenT := 0.0
var biteHintShown := false
var charmActive := false

# progression
var tribeReady := false
# The tribe button rect lives in SCREEN space; the scene layer re-positions it
# each frame (TS render() mutated tribeRect directly — native: the scene
# writes this same dict, the sim only hit-tests it).
var tribeRect := {"x": 0.0, "y": 0.0, "w": 200.0, "h": 46.0}
var deathFade := 0.0
# TS `deathFade <= dt` first-frame idiom -> an honest bool (divergence ruling).
var deathStarted := false
var packLimit := 2
## Tutorial progress counters (polled by the tutorial engine, scene side).
var tut := {"actioned": 0, "editorOpened": 0}
## bio_tell: seconds left in the ambient panic-drift window.
var warnDriftT := 0.0
## Pointer-held state for the corpse-eat read in update_ents (TS input2Down
## reads game.input live inside updateEnts, CreatureStage.ts:848 — the native
## sim takes the input SNAPSHOT through update(), which parks the flag here).
var _inp_down := false
## mirror_rule state (minor 14) — the shared MirrorLedger.
var mirrorLedger := ChaosScript.MirrorLedger.new()
var spawnTimerCheckT := 0.0
var timers: Array = []      # {left: float, fn: Callable} — TS stage clock


func _init(ctx_v: Variant, rng_branch: Variant, hooks: Dictionary = {}) -> void:
	ctx = ctx_v
	rng = rng_branch
	_hooks = hooks
	pStats = StatsScript.compute_creature_stats(ctx.genome)
	pmaxHp = float(pStats["max_hp"])
	php = pmaxHp

	# ---- ecosystem bootstrap ---------------------------------------------------
	if ctx.eco == null:
		eco = EcoScript.new(rng.branch())
		ctx.eco = eco
		# bootstrap land species if coming from a fresh save
		seed_land_ecology()
		eco.designate_kin_tag(ctx.world)
	else:
		eco = ctx.eco
		if needs_land_fauna():
			seed_land_ecology()
			eco.designate_kin_tag(ctx.world)

	# TS CreatureStage.ts:157 — the chaos deck. The scheduler's stage-rng
	# branch is drawn AFTER the eco bootstrap (seedLandEcology) and BEFORE the
	# bushes: stream-order sensitive (branch() consumes one parent draw).
	# make_creature_chaos_events itself draws nothing (weights are Callables).
	chaos = ChaosScript.new(rng.branch(), CreatureEventsScript.make_creature_chaos_events(ctx.world))
	deckSeed = int(ctx.world["seed"])
	# the creature stage is the weakest stage — its default cadence measured
	# 4.6-8.4 events/min at chaos (one every 7-13s). Widen the gap.
	chaos.gap = 40.0
	chaos.gap_chaos_scale = 0.35

	# bushes + bones + nest sites
	for i in 46:
		bushes.append({
			"x": rng.range(-WORLD_HALF, WORLD_HALF),
			"z": rng.range(Z_MIN, Z_MAX),
			"food": rng.range(2.0, 5.0),
			"regrow": 0.0,
			"seed": rng.range(0.0, 9.0),
		})
	for i in 8:
		bones.append({
			"x": rng.range(-WORLD_HALF, WORLD_HALF),
			"z": rng.range(Z_MIN, Z_MAX),
			"taken": false,
			"kind": "meteor" if i == 0 else "bone",
		})
	packLimit = _pack_limit()


func _pack_limit() -> int:
	# TS: 2 + Math.floor(ctx.genome.arms / 2) + Math.floor(ctx.genome.brain / 2)
	return 2 + floori(float(ctx.genome.get("arms", 0)) / 2.0) \
			+ floori(float(ctx.genome.get("brain", 0)) / 2.0)


# ---------------------------------------------------------------------------------

## Land fauna gate: species COUNT lies — arriving from the cell stage the
## roster is sea species with legs=0 and zero wild nests (no threat, no prey
## worth chasing). Seed when nothing legged exists. (TS:188-190)
func needs_land_fauna() -> bool:
	for sp in eco.living():
		if float(sp["genome"].get("legs", 0)) > 0.0:
			return false
	return true


## Port 1:1 — the 6 land archetype genomes (exact field values, TS:194-201),
## world-weighted diet flips (same dial as cell's seeder), titan/swarm bonus
## species appended AFTER the roster, and a nest per species (members 4).
func seed_land_ecology() -> void:
	var archetypes: Array = [
		{"size": 0.9, "diet": "herbivore", "legs": 4, "eyes": 2, "tail": true, "hue": 85, "coat": "fur"},
		{"size": 1.2, "diet": "carnivore", "legs": 4, "jaw": 3, "horns": 1, "hue": 15, "pattern": "stripes"},
		{"size": 0.7, "diet": "herbivore", "legs": 2, "eyes": 3, "hue": 190},
		{"size": 1.7, "diet": "carnivore", "legs": 4, "jaw": 4, "spikes": 4, "horns": 2, "hue": 265, "coat": "plates"},
		{"size": 1.0, "diet": "omnivore", "legs": 4, "arms": 2, "hue": 55, "coat": "fur", "tail": true},
		{"size": 1.4, "diet": "herbivore", "legs": 4, "horns": 3, "hue": 130},
	]
	# World-genome archetype weights bend the starting food web — same dial
	# as CellStage.seedEcology (deterministic, this stage's rng branch only).
	var weights: Dictionary = WorldGenomeScript.archetype_weights(ctx.world)
	var herbW: float = float(weights.get("herbivore", 1))
	var carnW: float = float(weights.get("carnivore", 1)) * float(weights.get("predator", 1))
	var herbPull: float = minf(0.9, maxf(0.0, herbW - 1.0) * 0.5 + maxf(0.0, 1.0 - carnW) * 0.5)
	var carnPull: float = minf(0.9, maxf(0.0, carnW - 1.0) * 0.5 + maxf(0.0, 1.0 - herbW) * 0.5)
	for arch in archetypes:
		# fixed base — seeding from the player's genome leaked unpaid parts
		# into wild species (same fix the cell seeder got)
		var g: Dictionary = GenomeScript.clone_genome(GenomeScript.default_genome())
		g.merge(arch, true)
		g["generation"] = 1
		# JS short-circuit: exactly ONE chance draw per archetype either way
		if String(arch["diet"]) == "herbivore":
			if rng.chance(carnPull):
				g["diet"] = "carnivore"
		elif rng.chance(herbPull):
			g["diet"] = "herbivore"
		# addSpecies generates the name/id from the ECO's own rng (TS passes
		# no name here — unlike the cell seeder)
		var sp: Dictionary = eco.add_species(g, rng.range(5.0, 10.0))
		ctx.discover(g, sp["name"], "creature")
		nests.append({
			"x": rng.range(-WORLD_HALF * 0.9, WORLD_HALF * 0.9),
			"z": rng.range(Z_MIN + 40.0, Z_MAX - 40.0),
			"speciesId": sp["id"],
			"members": 4,
		})
	# bonus species appended AFTER the base roster so their diet/size
	# survive the diet dial above untouched
	if float(weights.get("titan", 0)) >= 1.0:
		var gt: Dictionary = GenomeScript.clone_genome(GenomeScript.default_genome())
		gt.merge({"size": 2.1, "diet": "carnivore", "legs": 4, "jaw": 4, "spikes": 4,
				"horns": 3, "hue": 300, "coat": "plates"}, true)
		gt["generation"] = 1
		var spt: Dictionary = eco.add_species(gt, rng.range(5.0, 10.0))
		ctx.discover(gt, spt["name"], "creature")
		nests.append({
			"x": rng.range(-WORLD_HALF * 0.9, WORLD_HALF * 0.9),
			"z": rng.range(Z_MIN + 40.0, Z_MAX - 40.0),
			"speciesId": spt["id"],
			"members": 4,
		})
	if float(weights.get("swarm", 0)) >= 1.0:
		var gs: Dictionary = GenomeScript.clone_genome(GenomeScript.default_genome())
		gs.merge({"size": 0.6, "diet": "herbivore", "legs": 4, "eyes": 2, "hue": 200}, true)
		gs["generation"] = 1
		var sps: Dictionary = eco.add_species(gs, rng.range(5.0, 10.0))
		ctx.discover(gs, sps["name"], "creature")
		nests.append({
			"x": rng.range(-WORLD_HALF * 0.9, WORLD_HALF * 0.9),
			"z": rng.range(Z_MIN + 40.0, Z_MAX - 40.0),
			"speciesId": sps["id"],
			"members": 4,
		})


# ---- enter / exit / persist -------------------------------------------------------

## TS onEnter (CreatureStage.ts:258-335), minus the scene surfaces (audio mood,
## objective line, tutorial engine — scene layer, later tasks).
func on_enter() -> void:
	# C1: a CONTINUE/NEW LIFE landing on a different world rebuilds the deck
	ensure_deck(int(ctx.world["seed"]))
	pStats = StatsScript.compute_creature_stats(ctx.genome)
	pmaxHp = float(pStats["max_hp"])
	if php <= 0.0 or php > pmaxHp:
		php = pmaxHp
	deathFade = 0.0
	deathStarted = false
	php = pmaxHp  # arrivals arrive healthy (the reload grace covers danger)
	# reload ambush: CONTINUE dropped you into a predator pack at full speed
	# with no grace (the post-death respawn grants 3s — a load grants none)
	invuln = 3.0
	# a save point 130px from an aggroed carnivore still killed you at zero
	# input (php 70->46.5 by +2.4s) — calm hunters camped on the arrival
	for e in ents:
		if bool(e["pack"]) or e.has("corpseT"):
			continue
		if _vdist(float(e["x"]), float(e["z"]), px, pz) < 300.0:
			e["mood"] = "idle"
			e["packCd"] = 10.0  # back off before re-aggroing
	# audio.setMood('land') — scene-side (the sim owns no audio graph)
	packLimit = _pack_limit()

	# the creature names itself from its own traits — one-time arrival card
	if String(ctx.player_name) == "Squish":
		var autoName: String = NamesScript.self_name(ctx.genome)
		ctx.player_name = autoName
		_fire("hud_banner", [{
			"title": "THE PACK WILL CALL YOU %s" % autoName.to_upper(),
			"subtitle": "drag yourself forward — the ocean is done with you",
			"kind": "stage", "ttl": 5,
		}])
	# rebuild the ecosystem if a NEW LIFE reset it
	if ctx.eco != eco:
		nests = []
		if ctx.eco != null:
			eco = ctx.eco
		else:
			eco = EcoScript.new(rng.branch())
		ctx.eco = eco
		if needs_land_fauna():
			seed_land_ecology()
			eco.designate_kin_tag(ctx.world)
	# showObjective + the tutorial engine — scene-side (Tasks 6+).

	# spawn player's kin nest at spawn point
	var hasKin := false
	for n in nests:
		if String(n["speciesId"]) == "player":
			hasKin = true
			break
	if not hasKin:
		nests.append({"x": -2400.0, "z": 20.0, "speciesId": "player", "members": 0})

	# pack persists across a REAL page reload — flags.packGenomes was
	# write-only here (only TribeStage read it): F5 ate your friends while
	# the save file claimed they existed
	var livePack := 0
	for e in ents:
		if bool(e["pack"]) and not e.has("corpseT"):
			livePack += 1
	if livePack == 0:
		var raw: Variant = ctx.flags.get("packGenomes")
		var packList: Array = []
		if raw is String and not (raw as String).is_empty():
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Array:
				packList = parsed
			# corrupt flag — start alone (the TS try/catch swallows everything)
		var n_restore: int = mini(packList.size(), packLimit)
		for i in n_restore:
			var item: Variant = packList[i]
			if not (item is Dictionary) or not (item.get("genome") is Dictionary):
				continue
			var merged: Dictionary = GenomeScript.default_genome()
			merged.merge(item["genome"], true)
			var e: Dictionary = spawn_ent(null,
					px + rng.range(-60.0, 60.0), pz + rng.range(-40.0, 40.0),
					GenomeScript.clamp_genome(merged))
			e["pack"] = true
			e["mood"] = "happy"


func on_exit() -> void:
	ctx.eco = eco
	persist_state()


## Pack snapshot — flags.packGenomes was only written at foundTribe, so a
## mid-creature autosave reloaded the pack as 0 (A02 measured). (TS:344-347)
func persist_state() -> void:
	var list: Array = []
	for e in ents:
		if bool(e["pack"]) and not e.has("corpseT"):
			list.append({"genome": e["genome"], "baby": false})
	ctx.flags["packGenomes"] = JSON.stringify(list)


# ---- spawning -----------------------------------------------------------------

## TS:351-395. Draw order is sacred: facing (chance) -> gait (range 0..6) ->
## seed (range 0..100), all from the stage branch.
func spawn_ent(sp: Variant, x: float, z: float, genome_override: Dictionary = {},
		opts: Dictionary = {}) -> Dictionary:
	var genome: Dictionary
	if not genome_override.is_empty():
		genome = genome_override
	elif sp != null:
		genome = sp["genome"]
	else:
		genome = ctx.genome
	var stats: Dictionary = StatsScript.compute_creature_stats(genome)
	# wild speed partially tracks the player's legs — a legs-0 hatchling is
	# not expected to outrun a legs-4 hunter (gate-stage death soak)
	var playerLegs: float = minf(4.0, float(ctx.genome.get("legs", 0)))
	stats["speed"] = float(stats["speed"]) * (0.6 + 0.4 * (playerLegs / 4.0))
	# peaceful promises gentler WILDLIFE (ambient deaths measured identical
	# to normal: 43 vs 42 — the difficulty only touched event frequency)
	if String(ctx.difficulty) == "peaceful":
		stats["damage"] = float(stats["damage"]) * 0.7
		stats["max_hp"] = float(stats["max_hp"]) * 0.8
		stats["speed"] = float(stats["speed"]) * 0.9
	var scaleHp: float = 0.4 if bool(opts.get("baby", false)) else 1.0
	var speciesId: String = sp["id"] if sp != null else "mutant"
	var e: Dictionary = {
		"eid": nextEid,
		"speciesId": speciesId,
		"genome": genome,
		"x": x, "z": z,
		"vx": 0.0, "vz": 0.0, "y": 0.0, "vy": 0.0,
		"hp": float(stats["max_hp"]) * scaleHp,
		"maxHp": float(stats["max_hp"]) * scaleHp,
		"stats": stats,
		"facing": 1 if rng.chance(0.5) else -1,
		"gait": rng.range(0.0, 6.0),
		"speed01": 0.0,
		"attack": 0.0,
		"hurtT": 0.0,
		"eatT": 0.0,
		"biteCd": 0.0,
		"mood": "idle",
		"wanderT": 0.0,
		"tx": x, "tz": z,
		"pack": bool(opts.get("pack", false)),
		"packCd": 0.0,
		"baby": bool(opts.get("baby", false)),
		"seed": rng.range(0.0, 100.0),
		"band": WorldGenomeScript.behavior_band(ctx.world, speciesId),
	}
	nextEid += 1
	# TS-optional fields (eggT/corpseT/flying/lifespanStampede/pressCd) stay
	# ABSENT until set (undefined semantics): tasks 3/4 read them with .get().
	ents.append(e)
	return e


func maintain_population() -> void:
	# Remove far-away ents (pack exempt)
	var kept: Array[Dictionary] = []
	for e in ents:
		if absf(float(e["x"]) - px) < 2200.0 or bool(e["pack"]):
			kept.append(e)
	ents = kept
	for sp in eco.living():
		if bool(sp.get("kin", false)):
			continue
		var visible := 0
		for e in ents:
			if String(e["speciesId"]) == String(sp["id"]):
				visible += 1
		var target: int = mini(10, floori(float(sp["pop"]) * 0.5 + 0.5))  # JS Math.round
		if visible < target and rng.chance(0.35):
			var nest: Variant = null
			for n in nests:
				if String(n["speciesId"]) == String(sp["id"]):
					nest = n
					break
			if nest != null:
				var a: float = rng.next() * TAU
				spawn_ent(sp, float(nest["x"]) + cos(a) * rng.range(30.0, 220.0),
						clampf(float(nest["z"]) + sin(a) * 120.0, Z_MIN, Z_MAX))
			else:
				spawn_ent(sp, px + rng.range(-900.0, 900.0), rng.range(Z_MIN, Z_MAX))


# ---- update -----------------------------------------------------------------------

## inp: input SNAPSHOT Dictionary — mx, my, wx, wy, down, clicked,
## take_click (pre-taken flag), keys_held: Array[String],
## keys_pressed: Array[String]. The scene layer builds it; tests construct
## it literally. The sim never touches the Input singleton.
func update(dt: float, inp: Dictionary) -> void:
	time += dt
	# the frame's pointer state, for update_ents' corpse-eat read (TS input2Down)
	_inp_down = bool(inp.get("down", false))

	# stage timers
	for ti in range(timers.size() - 1, -1, -1):
		var t: Dictionary = timers[ti]
		t["left"] = float(t["left"]) - dt
		if float(t["left"]) <= 0.0:
			timers.remove_at(ti)
			var fn: Callable = t["fn"]
			fn.call()

	# bushes regrow berries (b.regrow was write-only before — grazing had a
	# hard ~83 DNA cap vs the 305 brain gate) (TS:435-443)
	for b in bushes:
		if float(b["regrow"]) > 0.0:
			b["regrow"] = float(b["regrow"]) - dt
			if float(b["regrow"]) <= 0.0:
				b["regrow"] = 0.0
				b["food"] = rng.range(2.0, 5.0)

	# dead-island escape: if every wild creature is gone for ~60 s (total
	# land collapse, stampede wipe…), life finds a way — reseed (TS:447-461)
	var wildAlive := false
	for e in ents:
		if not bool(e["pack"]) and not e.has("corpseT") and not e.has("lifespanStampede"):
			wildAlive = true
			break
	if not wildAlive and php > 0.0:
		barrenT += dt
		if barrenT > 60.0:
			barrenT = 0.0
			if needs_land_fauna():
				seed_land_ecology()  # no duplicate stacking
				eco.designate_kin_tag(ctx.world)
			for n in nests:
				if String(n["speciesId"]) != "player":
					n["members"] = 4
			_fire("hud_toast", [tr("Life finds a way — new creatures migrate in from beyond the ridge."), "good", "🌱"])
	else:
		barrenT = 0.0

	# day/night: full cycle 3 minutes
	dayPhase = fmod(dayPhase + dt / 180.0, 1.0)

	# editor (Tab or E) — scene overlay; the TS branch RETURNS early here
	# (TS:467-475, the dead cannot edit). Native scene owns that gate.

	# found-tribe button (handleTribeClick -> foundTribe) — Task 5.
	# tutorial — scene-side engine.

	# charm interactions (hold F) — the minigame body is Task 4; the call
	# site + the reset branch are TS-true now (TS:487-493). The editor-open
	# gate is scene-side (the sim's editor never blocks).
	if inp.get("keys_held", []).has("KeyF"):
		try_charm()
	else:
		charmActive = false
		charmTarget = null
	if charmActive:
		update_charm(dt)

	update_player(dt, inp)
	# bio_tell: the panic window tracks the live warn phase — herds drift out
	# of the strike zone while it runs (TS reads chaos.warnRemaining, TS:498)
	warnDriftT = chaos.warn_remaining()
	update_ents(dt)

	# hazards (lava/fire) tick (TS:502-514)
	var hi: int = hazards.size() - 1
	while hi >= 0:
		var h: Dictionary = hazards[hi]
		h["ttl"] = float(h["ttl"]) - dt
		if float(h["ttl"]) <= 0.0:
			hazards.remove_at(hi)
			hi -= 1
			continue
		if rng.chance(dt * 6.0):
			_fire("fx_spawn", [{
				"x": float(h["x"]) + rng.range(-float(h["r"]), float(h["r"])) * 0.6,
				"y": float(h["z"]) * Z_TO_Y,
				"vx": rng.range(-6.0, 6.0), "vy": rng.range(-40.0, -16.0),
				"ttl": 1.0, "size": rng.range(3.0, 7.0), "kind": "smoke",
				"color": "rgba(255,140,60,0.5)" if String(h["kind"]) == "lava"
						else "rgba(255,190,90,0.45)",
				"drag": 0.5,
			}])
		hi -= 1

	# ecology (TS:517-537)
	ecoTimer += dt
	if ecoTimer >= 2.0:
		var batch: float = ecoTimer
		ecoTimer = 0.0
		# the wire that makes world-trait effects real: refresh the eco mods
		# from the world genome right before the tick batch
		eco.mods = WorldGenomeScript.eco_mods_from_world(ctx.world)
		var out: Dictionary = eco.tick(batch, "player")
		for ex in out["extinctions"]:
			ctx.bump_extinction()
			ctx.mark_extinct(ex["genome"])
			ctx.add_chaos(0.04)
			var keptNests: Array = []
			for n in nests:
				if String(n["speciesId"]) != String(ex["id"]):
					keptNests.append(n)
			nests = keptNests
			_fire("hud_banner", [{
				"title": "%s is extinct" % ex["name"],
				"subtitle": "the island falls silent…",
				"kind": "chaos",
			}])
		for sh in out.get("shifts", []):
			# bio_shift: the web re-equilibrates around the loss
			_fire("hud_toast", ["%s %s → %s" % [tr("The web re-equilibrates:"),
					_diet_name(sh["from"]), _diet_name(sh["to"])], "chaos", "🕸"])

	spawn_timer_check(dt)

	# chaos (TS:541-568)
	update_chaos(dt)

	# camera (cam.follow(px, pz * Z_TO_Y, dt, 5), zoom 1.15, toWorld ->
	# setWorld) and the fx pool steps: scene-side. The sim never touches cam.

	# cooldowns/anims (TS:581-586)
	biteCd = maxf(0.0, biteCd - dt)
	attackT = maxf(0.0, attackT - dt * 2.2)
	hurtT = maxf(0.0, hurtT - dt * 3.0)
	eatT = maxf(0.0, eatT - dt * 2.0)
	invuln = maxf(0.0, invuln - dt)
	jumpCd = maxf(0.0, jumpCd - dt)

	# tribe readiness (TS:589-590); the objective HUD line is scene-side
	var pop := 0
	for e in ents:
		if bool(e["pack"]):
			pop += 1
	tribeReady = float(ctx.genome.get("brain", 0)) >= 3.0 and pop >= 2

	# death
	if php <= 0.0:
		handle_death(dt)

	# hud abilities push (TS setAbilities) — the native HUD polls the cd
	# fields through the public state instead (no hook by ruling).


func spawn_timer_check(dt: float) -> void:
	spawnTimerCheckT += dt
	if spawnTimerCheckT >= 1.5:
		spawnTimerCheckT = 0.0
		maintain_population()


func handle_death(dt: float) -> void:
	deathFade += dt
	if not deathStarted:
		# TS first-frame idiom `deathFade <= dt` (CreatureStage.ts:618) -> bool
		deathStarted = true
		_fire("context_event", ["playerDeath", "creature"])  # storyteller signal
		_fire("audio_play", ["die", 0.9, 0.0])
		_fire("cam_shake", [10.0, 0.6])
		ctx.add_chaos(0.03)
		var lost := floori(float(ctx.dna) * 0.12 + 0.5)  # JS Math.round
		ctx.add_dna(-lost)
		_fire("hud_toast", ["%s %d DNA" % [tr("You died — lost"), lost], "bad", "💀"])
		charmActive = false
		charmTarget = null
		# pack scatters (tell the player — silent losses read as bugs)
		var scattered := 0
		for e in ents:
			if bool(e["pack"]):
				scattered += 1
		for e in ents:
			if bool(e["pack"]):
				e["pack"] = false
				e["mood"] = "afraid"
		if scattered > 0:
			_fire("hud_toast", ["The pack scattered (%d fled)" % scattered, "bad", "🐾"])
	if deathFade > 1.8:
		deathFade = 0.0
		deathStarted = false
		php = pmaxHp
		invuln = 3.0
		# respawn closer to the action: x=-2400 was a 45 s walk from everything
		# (TS sets -2400/20 then overwrites — the intermediate was dead there too)
		px = -1600.0
		pz = 20.0
		pvx = 0.0
		pvz = 0.0
		var kept: Array[Dictionary] = []
		for e in ents:
			if _vdist(float(e["x"]), float(e["z"]), px, pz) > 600.0 or bool(e["pack"]):
				kept.append(e)
		ents = kept


func update_player(dt: float, inp: Dictionary) -> void:
	var s: Dictionary = pStats
	var held: Array = inp.get("keys_held", [])
	var pressed: Array = inp.get("keys_pressed", [])
	var mx: float = float(inp.get("mx", 0.0))
	var my: float = float(inp.get("my", 0.0))
	var wx: float = float(inp.get("wx", 0.0))
	var wy: float = float(inp.get("wy", 0.0))
	var down: bool = bool(inp.get("down", false))

	# movement target: mouse (world) via pseudo-depth, or WASD
	var dx := 0.0
	var dz := 0.0
	if down and not over_tribe(mx, my):
		# invert projection: screenY = z * Z_TO_Y  ->  z = wy / Z_TO_Y
		var tz_m: float = clampf(wy / Z_TO_Y, Z_MIN, Z_MAX)
		dx = wx - px
		dz = tz_m - pz
		if absf(dx) < 10.0:
			dx = 0.0
		if absf(dz) < 10.0:
			dz = 0.0
	if held.has("KeyW") or held.has("ArrowUp"):
		dz -= 1.0
	if held.has("KeyS") or held.has("ArrowDown"):
		dz += 1.0
	if held.has("KeyA") or held.has("ArrowLeft"):
		dx -= 1.0
	if held.has("KeyD") or held.has("ArrowRight"):
		dx += 1.0
	var dl: float = sqrt(dx * dx + dz * dz)
	if dl > 0.0:
		dx /= dl
		dz /= dl
	if dx != 0.0:
		facing = 1 if dx > 0.0 else -1

	# jump / wing hop
	var wings: float = float(ctx.genome.get("wings", 0))
	if pressed.has("Space") and py <= 0.0 and jumpCd <= 0.0:
		pvy = 320.0 + wings * 60.0
		jumpCd = 1.2
		_fire("audio_play", ["dash", 0.4, 0.0])
		if wings > 0.0:
			# TS quirk verbatim: the burst anchors at (px, py) — py is the
			# JUMP HEIGHT here, not the depth-squashed z (CreatureStage.ts:674)
			_fx_burst(px, py, 8, ["#cfe8ff"], {"speed": 70.0, "ttl": 0.5, "size": 2.4})

	# physics
	pvx += dx * float(s["accel"]) * dt
	pvz += dz * float(s["accel"]) * dt * 0.8
	var drag: float = exp(-6.0 * dt)
	pvx *= drag
	pvz *= drag
	var sp: float = sqrt(pvx * pvx + pvz * pvz)
	var maxSp: float = maxf(0.0, float(s["speed"]))
	if sp > maxSp:
		pvx *= maxSp / sp
		pvz *= maxSp / sp
	px += pvx * dt
	pz += pvz * dt
	pz = clampf(pz, Z_MIN, Z_MAX)
	px = clampf(px, -WORLD_HALF - 200.0, WORLD_HALF + 200.0)

	# jump gravity
	if py > 0.0 or pvy > 0.0:
		pvy -= 950.0 * dt
		py += pvy * dt
		if py <= 0.0:
			py = 0.0
			pvy = 0.0

	speed01 = minf(1.0, sp / maxf(1.0, maxSp))
	gait += dt * (3.0 + speed01 * 9.0)

	# dust when running
	if speed01 > 0.5 and py <= 0.0 and rng.chance(dt * 10.0):
		_fire("fx_spawn", [{
			"x": px - float(facing) * 10.0, "y": pz * Z_TO_Y,
			"vx": rng.range(-14.0, 14.0), "vy": rng.range(-18.0, -4.0),
			"ttl": 0.8, "size": rng.range(2.0, 4.0), "kind": "smoke",
			"color": "rgba(180,160,130,0.5)", "drag": 2.0,
		}])

	# interactions
	var pR: float = 16.0 * float(ctx.genome.get("size", 1))
	for e in ents:
		if e.has("corpseT"):
			continue
		var d: float = _vdist(float(e["x"]), float(e["z"]), px, pz)
		var charming: bool = charmActive or (held.has("KeyF") and d < 150.0)
		if d < pR + 14.0 * float(e["genome"]["size"]):
			# bite (unless pack/allied, charming, or baby)
			if biteCd <= 0.0 and not bool(e["pack"]) and not charming \
					and php > 0.0 and deathFade <= 0.0:
				biteCd = 0.6
				attackT = 1.0
				var dmg: float = float(s["damage"]) \
						* (1.0 - minf(0.6, float(e["stats"]["defense"])))
				e["hp"] = float(e["hp"]) - dmg
				e["hurtT"] = 0.7
				e["mood"] = "afraid"
				_fire("audio_play", ["chomp", 0.6, 0.0])
				_fx_burst(float(e["x"]), float(e["z"]) * Z_TO_Y, 7,
						["#ff9a8a", _hsl(float(e["genome"]["hue"]), 0.7, 0.55)],
						{"speed": 140.0, "ttl": 0.5, "size": 2.6})
				ctx.add_karma(-0.008)
				if float(e["hp"]) <= 0.0:
					kill_ent(e)
			# their response bite (the charm target holds still and tolerates
			# you) — any F-held creature tolerates you (holding F genuinely
			# wards off its bites) (TS:732-746)
			if float(e["biteCd"]) <= 0.0 and not bool(e["pack"]) and invuln <= 0.0 \
					and float(e["stats"]["damage"]) > 0.0 and not charming:
				e["biteCd"] = 0.9
				e["attack"] = 1.0
				e["mood"] = "angry"
				if not biteHintShown:
					biteHintShown = true
					_fire("hud_toast", [tr("Hold F near a creature to CHARM it instead of being bitten"), "info", "🐾"])
				var dmg2: float = float(e["stats"]["damage"]) \
						* (1.0 - float(s["defense"])) * 0.85
				php -= dmg2
				hurtT = 1.0
				_fire("cam_shake", [3.5, 0.25])
				_fire("audio_play", ["hurt", 0.55, 0.0])
				_fx_burst(px, pz * Z_TO_Y - 10.0, 5, ["#ff8a9a"],
						{"speed": 100.0, "ttl": 0.4, "size": 2.0})

	# eat bushes / bones (alive only — a posthumous heal out-races the
	# death fade and leaves an invisible ghost) (TS:752-787)
	for b in bushes:
		if float(b["food"]) > 0.0 and php > 0.0 and deathFade <= 0.0 \
				and _vdist(float(b["x"]), float(b["z"]), px, pz) < 30.0:
			if down or held.has("KeyF"):
				var bite: float = dt * 2.0
				var took: float = minf(bite, float(b["food"]))
				b["food"] = float(b["food"]) - took
				b["regrow"] = 25.0
				php = minf(pmaxHp, php + 6.0 * took)
				ctx.add_dna(took * 1.2)
				ctx.add_karma(dt * 0.02)
				eatT = 1.0
				if rng.chance(dt * 6.0):
					_fire("audio_play", ["eat", 0.35, 0.0])
				_fx_burst(float(b["x"]), float(b["z"]) * Z_TO_Y, 2, ["#9fe89a"],
						{"speed": 50.0, "ttl": 0.4, "size": 2.0})
	for bo in bones:
		if not bool(bo["taken"]) and php > 0.0 and deathFade <= 0.0 \
				and _vdist(float(bo["x"]), float(bo["z"]), px, pz) < 34.0:
			bo["taken"] = true
			tut["actioned"] = int(tut["actioned"]) + 1
			# TS reassigns this.bones mid-for-of — the loop keeps walking the
			# ORIGINAL array, so a second in-range bone fires the same tick
			var keptBones: Array = []
			for b2 in bones:
				if not bool(b2["taken"]):
					keptBones.append(b2)
			bones = keptBones
			if bones.size() > 60:
				bones = bones.slice(bones.size() - 60)  # splice(0, len-60): keep the tail
			var isMeteor: bool = String(bo["kind"]) == "meteor"
			var dnaGain: int = 120 if isMeteor else 45
			ctx.add_dna(dnaGain)
			_fire("audio_play", ["levelup", 0.8, 0.0])
			_fire("hud_float_world", [float(bo["x"]), float(bo["z"]) * Z_TO_Y - 30.0,
					"+%d DNA %s" % [dnaGain, "☄" if isMeteor else "🦴"], "#ffe08a", 15.0])
			if isMeteor:
				ctx.add_chaos(0.05)
				_fire("hud_toast", [tr("Meteor marrow! Rare genes course through you."), "reward", "☄"])
			else:
				_fire("hud_toast", [tr("Ancient bones: +45 DNA"), "good", "🦴"])
			_fx_burst(float(bo["x"]), float(bo["z"]) * Z_TO_Y, 16,
					["#ffe08a", "#cfe8ff"], {"speed": 120.0, "ttl": 0.8})

	# lava zones (volcano event)
	for hz in hazards:
		if _vdist(float(hz["x"]), float(hz["z"]), px, pz) < float(hz["r"]) \
				and py <= 0.0 and invuln <= 0.0:
			php -= float(hz["dps"]) * dt
			hurtT = maxf(hurtT, 0.4)

	# pack follow gains karma slowly
	var anyPack := false
	for e in ents:
		if bool(e["pack"]):
			anyPack = true
			break
	if anyPack:
		ctx.add_karma(dt * 0.002)


func kill_ent(e: Dictionary) -> void:
	tut["actioned"] = int(tut["actioned"]) + 1
	_fire("audio_play", ["die", 0.6, 0.0])
	_fx_burst(float(e["x"]), float(e["z"]) * Z_TO_Y - 10.0, 20,
			[_hsl(float(e["genome"]["hue"]), 0.75, 0.55), "#ff9a8a", "#ffe0b0"],
			{"speed": 170.0, "ttl": 0.9, "size": 3.0})
	var dna: int = eco.notify_kill(String(e["speciesId"]), float(ctx.genome["size"]))
	ctx.bump_kill()  # world-story counter (feeds 'kill' reveal conditions)
	ctx.add_dna(dna)
	_fire("hud_float_world", [float(e["x"]), float(e["z"]) * Z_TO_Y - 26.0,
			"+%d" % dna, "#9fd8ff", 13.0])
	# kin_memory: the kin-tag network keeps the ONE grudge ledger — the
	# first entry is preceded by exactly one warning (catalog I.b)
	var sp: Variant = null
	for x in eco.species:
		if String(x["id"]) == String(e["speciesId"]):
			sp = x
			break
	if sp != null and bool(sp.get("kin_tag", false)) \
			and WorldGenomeScript.world_has(ctx.world, "kin_grudge"):
		if float(sp.get("grudge", 0.0)) == 0.0:
			_fire("hud_toast", [tr("the kin are watching"), "chaos", "⚱"])
		sp["grudge"] = float(sp.get("grudge", 0.0)) + 1.0
	# corpse_tide: every kill leaves a corpse that bursts into 2-3 small,
	# fierce scavengers (high-risk combo — budgets probed in econ-probe)
	if WorldGenomeScript.combo_active(ctx.world, "corpse_tide"):
		eco.drop_corpse(2 + (1 if rng.chance(0.5) else 0))
	# corpse meat
	_fx_burst(float(e["x"]), float(e["z"]) * Z_TO_Y, 10, ["#ffb08a"],
			{"speed": 80.0, "ttl": 0.7, "size": 3.0})
	e["corpseT"] = 12.0  # meat lasts a while; the corpse lifecycle is Task 3
	e["hp"] = 0.0
	# pack members gain loyalty when you hunt
	for p in ents:
		if bool(p["pack"]):
			p["mood"] = "happy"


# ---- NPC AI -------------------------------------------------------------------------

## TS CreatureStage.ts:835-1019 — the z-band NPC loop, reverse index (corpses
## and stampede ents splice out mid-loop). Per-ent branch order: corpse
## lifecycle (player meat-eat, 35% bone on expiry, removal) -> anim/cooldown
## decay -> baby growth (eggT) -> stampede lifetime (pack exempt -> cleared) ->
## movement AI (panic drift > charmed hold > pack follow > wild
## hunt/flee/graze) -> physics -> bush/corpse grazing -> hazard damage ->
## the hp<=0 killEnt sweep. Rng draws stay TS-lazy: the corpse bone roll, the
## corpse-eat audio chance, and the two wander offsets only when no bush won.
func update_ents(dt: float) -> void:
	for i in range(ents.size() - 1, -1, -1):
		var e: Dictionary = ents[i]

		# corpses: meat that player/predators can eat, then bones
		if e.has("corpseT"):
			e["corpseT"] = float(e["corpseT"]) - dt
			if float(e["corpseT"]) <= 0.0:
				if rng.chance(0.35):
					bones.append({"x": e["x"], "z": e["z"], "taken": false, "kind": "bone"})
				ents.remove_at(i)
			elif php > 0.0 and deathFade <= 0.0 \
					and _vdist(float(e["x"]), float(e["z"]), px, pz) < 30.0 \
					and String(ctx.genome["diet"]) != "herbivore" and _inp_down:
				# eat corpse (player)
				php = minf(pmaxHp, php + 14.0 * dt)
				ctx.add_dna(2.4 * dt)
				eatT = 1.0
				if rng.chance(dt * 5.0):
					_fire("audio_play", ["eat", 0.4, 0.0])
			continue

		e["hurtT"] = maxf(0.0, float(e["hurtT"]) - dt * 3.0)
		e["eatT"] = maxf(0.0, float(e["eatT"]) - dt * 2.0)
		e["biteCd"] = maxf(0.0, float(e["biteCd"]) - dt)
		e["attack"] = maxf(0.0, float(e["attack"]) - dt * 2.2)
		e["packCd"] = maxf(0.0, float(e["packCd"]) - dt)
		e["pressCd"] = maxf(0.0, float(e.get("pressCd", 0.0)) - dt)

		# baby growth
		if bool(e["baby"]) and e.has("eggT"):
			e["eggT"] = float(e["eggT"]) - dt
			if float(e["eggT"]) <= 0.0:
				e["baby"] = false
				e["stats"] = StatsScript.compute_creature_stats(e["genome"])
				e["maxHp"] = float(e["stats"]["max_hp"])
				e["hp"] = float(e["maxHp"])

		# stampede lifetime
		if e.has("lifespanStampede"):
			e["lifespanStampede"] = float(e["lifespanStampede"]) - dt
			if float(e["lifespanStampede"]) <= 0.0:
				if not bool(e["pack"]):
					ents.remove_at(i)
					continue
				e.erase("lifespanStampede")  # TS `= undefined`

		# ---- movement AI ------------------------------------------------------
		var tx: float
		var tz: float
		var sp: float = float(e["stats"]["speed"])
		var dPlayer: float = _vdist(float(e["x"]), float(e["z"]), px, pz)
		var vision: float = 360.0 * float(e["stats"]["vision"])
		var night := is_night()

		var charmed: bool = charmActive and charmTarget != null \
				and is_same(e, charmTarget)
		# bio_tell: during a warn window the ambient panics away from the strike
		# epicenter (the player's position) — herds visibly leave the region
		if warnDriftT > 0.0 and not bool(e["pack"]) and not charmed:
			var d: float = maxf(1.0, dPlayer)
			tx = float(e["x"]) + ((float(e["x"]) - px) / d) * 120.0
			tz = clampf(float(e["z"]) + ((float(e["z"]) - pz) / d) * 120.0, Z_MIN, Z_MAX)
			sp = 40.0
			e["mood"] = "alert"
		elif charmed:
			# the charm target holds still for the minigame — walking away
			# mid-song made the beat bar unwinnable at gate-stage speeds
			tx = float(e["x"])
			tz = float(e["z"])
			sp = 0.0
			e["vx"] = float(e["vx"]) * exp(-8.0 * dt)
			e["vz"] = float(e["vz"]) * exp(-8.0 * dt)
			e["mood"] = "alert"
		elif bool(e["pack"]):
			# follow player, help attack
			var followD := 60.0
			if dPlayer > followD + 40.0:
				tx = px - signf(px - float(e["x"])) * followD
				tz = pz
				sp *= 1.05
			else:
				tx = float(e["x"])
				tz = float(e["z"])
				sp = 0.0
			e["mood"] = "happy"
		else:
			var preySpecies: bool = String(e["genome"]["diet"]) != "herbivore"
			var playerThreat: bool = float(pStats["damage"]) > float(e["stats"]["damage"]) * 0.8 \
					or float(ctx.genome["size"]) > float(e["genome"]["size"])
			# hunt radius shrinks with the size gap — big carnivores ignore a
			# much smaller player (full-vision aggro on a hatchling was a
			# death spiral: 21 deaths/8.9 min measured)
			var sizeGap: float = maxf(0.35,
					1.0 - (float(e["genome"]["size"]) - float(ctx.genome["size"])) * 0.6)
			var peaceful: float = 0.65 if String(ctx.difficulty) == "peaceful" else 1.0
			# temperament_bands: per-species seeded band on the aggression/fear reads
			var band: Dictionary = e.get("band", {})
			var aggr: float = float(band.get("aggression", 1.0))
			var fear: float = float(band.get("fear", 1.0))
			# kin_memory: a grudging kin-tag network presses in force — and it
			# targets the weakest moment (hunt radius opens when the player is
			# hurt). effectiveGrudge rides the harassment valve: capped networks
			# rest and flee is restored.
			var grudge: float = eco.grudge_of(ctx.world, String(e["speciesId"]))
			var grudgeHunt: bool = grudge >= 2.0 and dPlayer < vision * 0.9 \
					* (1.4 if php < pmaxHp * 0.4 else 1.0)
			if (preySpecies and dPlayer < vision * sizeGap * peaceful * aggr \
					and not playerThreat) or grudgeHunt:
				# grudge presses count toward the harassment valve (one per engagement)
				if grudgeHunt and float(e.get("pressCd", 0.0)) <= 0.0:
					eco.register_press(ctx.world, String(e["speciesId"]))
					e["pressCd"] = PRESS_COOLDOWN
				# hunt player
				tx = px
				tz = pz
				e["mood"] = "angry"
			elif not charmed and grudge < 2.0 \
					and dPlayer < vision * 0.45 * fear and playerThreat \
					and float(e["packCd"]) <= 0.0 and not e.has("lifespanStampede"):
				# flee
				tx = float(e["x"]) + (float(e["x"]) - px) * 2.0
				tz = clampf(float(e["z"]) + (float(e["z"]) - pz) * 2.0, Z_MIN, Z_MAX)
				sp *= 1.05
				e["mood"] = "afraid"
			else:
				# wander / graze bushes
				e["wanderT"] = float(e["wanderT"]) - dt
				if float(e["wanderT"]) <= 0.0:
					e["wanderT"] = rng.range(2.0, 5.0)
					var best: Variant = null
					var bd := 420.0
					if String(e["genome"]["diet"]) != "carnivore":
						for b in bushes:
							if float(b["food"]) <= 0.0:
								continue
							var d2: float = _vdist(float(b["x"]), float(b["z"]),
									float(e["x"]), float(e["z"]))
							if d2 < bd:
								best = b
								bd = d2
					if best != null:
						e["tx"] = float(best["x"])
						e["tz"] = float(best["z"])
					else:
						e["tx"] = clampf(float(e["x"]) + rng.range(-300.0, 300.0),
								-WORLD_HALF, WORLD_HALF)
						e["tz"] = clampf(float(e["z"]) + rng.range(-160.0, 160.0),
								Z_MIN, Z_MAX)
				tx = float(e["tx"])
				tz = float(e["tz"])
				sp *= 0.5
				e["mood"] = "idle"
				if night:
					e["mood"] = "alert"

		var dx: float = tx - float(e["x"])
		var dz: float = tz - float(e["z"])
		var dl: float = sqrt(dx * dx + dz * dz)
		if dl > 8.0:
			e["vx"] = float(e["vx"]) + (dx / dl) * float(e["stats"]["accel"]) * dt
			e["vz"] = float(e["vz"]) + (dz / dl) * float(e["stats"]["accel"]) * dt * 0.8
			e["facing"] = 1 if dx > 0.0 else -1
		var drag: float = exp(-5.5 * dt)
		e["vx"] = float(e["vx"]) * drag
		e["vz"] = float(e["vz"]) * drag
		var spd: float = sqrt(float(e["vx"]) * float(e["vx"]) + float(e["vz"]) * float(e["vz"]))
		var cap: float = maxf(0.0, sp)
		if spd > cap and cap > 0.0:
			e["vx"] = float(e["vx"]) * cap / spd
			e["vz"] = float(e["vz"]) * cap / spd
		e["x"] = float(e["x"]) + float(e["vx"]) * dt
		e["z"] = float(e["z"]) + float(e["vz"]) * dt
		e["z"] = clampf(float(e["z"]), Z_MIN, Z_MAX)
		e["speed01"] = minf(1.0, spd / maxf(1.0, float(e["stats"]["speed"])))
		e["gait"] = float(e["gait"]) + dt * (3.0 + float(e["speed01"]) * 9.0)

		# eat bushes
		if String(e["genome"]["diet"]) != "carnivore":
			for b in bushes:
				if float(b["food"]) > 0.0 \
						and _vdist(float(b["x"]), float(b["z"]), float(e["x"]), float(e["z"])) < 26.0:
					b["food"] = maxf(0.0, float(b["food"]) - dt)
					b["regrow"] = 25.0
					e["eatT"] = 1.0
					e["hp"] = minf(float(e["maxHp"]), float(e["hp"]) + 3.0 * dt)

		# eat corpses (carnivores)
		if String(e["genome"]["diet"]) == "carnivore":
			for o in ents:
				if o.has("corpseT") \
						and _vdist(float(o["x"]), float(o["z"]), float(e["x"]), float(e["z"])) < 28.0:
					o["corpseT"] = float(o["corpseT"]) - dt * 2.0
					e["eatT"] = 1.0
					e["hp"] = minf(float(e["maxHp"]), float(e["hp"]) + 6.0 * dt)

		# hazard damage
		for hz in hazards:
			if _vdist(float(hz["x"]), float(hz["z"]), float(e["x"]), float(e["z"])) < float(hz["r"]):
				e["hp"] = float(e["hp"]) - float(hz["dps"]) * dt
				e["hurtT"] = maxf(float(e["hurtT"]), 0.3)
		if float(e["hp"]) <= 0.0 and not e.has("corpseT"):
			kill_ent(e)


# ---- charm (Task 4) -------------------------------------------------------------------

## TASK 4: the charm minigame ports here (TS CreatureStage.ts:1023-1058) —
## target pick, pack/size gates, the beat-marker start. The F-key call site
## + the reset branch already run in update(); until then holding F still
## wards off bites (the tolerance lives in update_player, TS-true).
func try_charm() -> void:
	pass


## TASK 4: the beat bar (TS CreatureStage.ts:1060-1115) — marker oscillation,
## the 3-hit befriending, miss annoyance, persistState on success.
func update_charm(_dt: float) -> void:
	pass


# ---- chaos -----------------------------------------------------------------------------

## TS CreatureStage.ts:541-568 — chaos.update with the full ctx and hooks.
## The storyteller reference arrives through hooks (get_gap_bias / get_mood /
## get_warn_scale Callables — the sim stays decoupled from the object); when
## absent they read the storyteller's neutral defaults (gap 1.0, mood "test",
## warnScale 1.0). night/dominance compute from sim state; the get_is_night /
## get_dominance hooks override when present.
func update_chaos(dt: float) -> void:
	var gap_bias := 1.0
	var mood := "test"  # Storyteller.MOOD_TEST
	var warn_scale := 1.0
	var gb: Variant = _hooks.get("get_gap_bias")
	if gb is Callable:
		gap_bias = float(gb.call())
	var gm: Variant = _hooks.get("get_mood")
	if gm is Callable:
		mood = String(gm.call())
	var ws: Variant = _hooks.get("get_warn_scale")
	if ws is Callable:
		warn_scale = float(ws.call())
	var night := is_night()
	var gn: Variant = _hooks.get("get_is_night")
	if gn is Callable:
		night = bool(gn.call())
	var dom: float = dominance_share()
	var gdom: Variant = _hooks.get("get_dominance")
	if gdom is Callable:
		dom = float(gdom.call())
	var on_warn := func(def) -> void:
		if String(def.get("warn", "")) != "":
			_fire("hud_banner", [{"title": def["warn"], "kind": "danger", "ttl": 2.4}])
			_fire("audio_play", ["alarm", 0.5, 0.0])
	var on_apply := func(def) -> void:
		_fire("hud_banner", [{"title": def["name"], "kind": "chaos"}])
		ctx.add_chaos(0.03)
		# mirror_rule: a fired mirror face leaves the return queue
		if def.get("mirrorOf") != null:
			mirrorLedger.on_fired(String(def["mirrorOf"]))
		# world_temperament pacing: warned events going live are the
		# high-severity marker (cradle grace / lean cycles / wildcard streak)
		_fire("storyteller_note_chaos_event", [float(ctx.playtime)])
	var on_end := func(def) -> void:
		# mirror_rule: an event that survived once may queue its mirror return
		mirrorLedger.maybe_queue(rng, String(def["id"]), "rain")
	chaos.update(dt, self, {
		"chaos": float(ctx.chaos), "karma": float(ctx.karma), "stageTime": time,
		"night": night,
		"gapMult": ctx.chaos_gap_mult() * gap_bias,
		"mood": mood,
		"warnScale": warn_scale,  # bio_tell bucket
		"mirrors": mirrorLedger.queued(),  # mirror_rule returns
		"dominance": dom,  # predator_convergence input
	}, {
		"onWarn": on_warn,
		"onApply": on_apply,
		"onEnd": on_end,
	})


## C1 deck rebuild (TS onEnter, CreatureStage.ts:261-264): a CONTINUE/NEW LIFE
## landing on a different world rebuilds the deck. The scene layer calls this
## on enter; headless tests call it directly. Returns true on a rebuild.
func ensure_deck(world_seed: int) -> bool:
	if world_seed == deckSeed:
		return false
	chaos = ChaosScript.new(rng.branch(), CreatureEventsScript.make_creature_chaos_events(ctx.world))
	deckSeed = world_seed
	return true


## TS hasActiveChaos(): the ACTIVE-phase set only — a warn-phase event does
## not count.
func has_active_chaos() -> bool:
	return chaos.active_events().size() > 0


# ---- chaos helpers / accessors ---------------------------------------------------------

## TS CreatureStage.ts:1119 — the event defs (Task 5) call this; the hazard
## state and both damage reads (player + ents) live here from Task 2.
func add_hazard(x: float, z: float, r: float, dps: float, ttl: float,
		kind: String = "lava") -> void:
	hazards.append({"x": x, "z": z, "r": r, "dps": dps, "ttl": ttl, "kind": kind})


## Stage-time timer (TS after()).
func after(seconds: float, fn: Callable) -> void:
	timers.append({"left": seconds, "fn": fn})


## predator_convergence (catalog III #3): the player's line (self + pack)
## vs the wild biomass near them — the dominance share feeding
## dominanceSeverity(). Regional: only ents within 900px count. (TS:1271-1285)
func dominance_share() -> float:
	var radius := 900.0
	var mine: float = float(ctx.genome["size"]) * float(ctx.genome["size"])
	var wild := 0.0
	for e in ents:
		if e.has("corpseT") or bool(e["pack"]):
			continue
		if absf(float(e["x"]) - px) > radius:
			continue
		wild += float(e["genome"]["size"]) * float(e["genome"]["size"])
	for e in ents:
		if e.has("corpseT") or not bool(e["pack"]):
			continue
		mine += float(e["genome"]["size"]) * float(e["genome"]["size"])
	return minf(1.0, mine / maxf(0.001, mine + wild))


## TS isNight getter: night = dayPhase in (0.55, 0.95), exclusive.
func is_night() -> bool:
	return dayPhase > 0.55 and dayPhase < 0.95


## Click hit-test for the found-tribe button (the button itself is Task 5;
## updatePlayer's movement dead-zone consults this, TS-true).
func over_tribe(sx: float, sy: float) -> bool:
	if not tribeReady:
		return false
	var r: Dictionary = tribeRect
	return sx >= float(r["x"]) and sx <= float(r["x"]) + float(r["w"]) \
			and sy >= float(r["y"]) and sy <= float(r["y"]) + float(r["h"])


## Editor hook: recompute derived stats so purchases apply immediately.
func on_stats_changed() -> void:
	pStats = StatsScript.compute_creature_stats(ctx.genome)
	pmaxHp = float(pStats["max_hp"])
	if php > 0.0:
		php = minf(php, pmaxHp)
	packLimit = _pack_limit()


## Debug/test access to internal sim state (TS debugState shape).
func debug_state() -> Dictionary:
	return {"px": px, "pz": pz, "php": php, "pmaxHp": pmaxHp, "ents": ents, "bushes": bushes}


## Debug/test: spawn real pack members around the player.
func debug_spawn_pack(n: int) -> void:
	for i in n:
		spawn_ent(null, px + float(i + 1) * 45.0, pz, {}, {"pack": true})


# ---- internals --------------------------------------------------------------------

## TS Particles.burst consumes the stage rng — per particle: 1 angle draw,
## 1 speed draw, 1 color pick (colors array present), 1 ttl draw, 1 size
## draw (range(0.6, 1.4) × opts.size, drawn AFTER ttl — gfx/particles.ts:70-84).
## The sim replays those 5 draws verbatim so the stream stays TS-aligned,
## embeds the sampled primitives under opts["parts"] (the scene layer may
## render them 1:1 or ignore them), and fires the fx_burst hook.
func _fx_burst(x: float, y: float, n: int, colors: Array, opts: Dictionary = {}) -> void:
	var o: Dictionary = opts.duplicate()
	o["colors"] = colors
	var parts: Array = []
	for i in n:
		var ang: float = rng.next() * PI * 2.0
		var sp: float = rng.range(0.3, 1.0) * float(o.get("speed", 90.0))
		var color: String = String(rng.pick(colors)) if not colors.is_empty() \
				else String(o.get("color", "#ffffff"))
		var ttl: float = rng.range(0.4, 1.0) * float(o.get("ttl", 0.7))
		var psz: float = rng.range(0.6, 1.4) * float(o.get("size", 3.0))
		parts.append({"ang": ang, "sp": sp, "color": color, "ttl": ttl, "size": psz})
	o["parts"] = parts
	_fire("fx_burst", [x, y, n, o])


func _diet_name(d: String) -> String:
	for x in PartsScript.DIETS:
		if x["id"] == d:
			return tr(x["name"])
	return d


## TS core/math vecDist — f64 inline (a f32 Vector2 would lose bits at the
## ±2900 world scale; the M2 sanctioned-divergence class, see PARITY-M2 §17).
func _vdist(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := ax - bx
	var dy := ay - by
	return sqrt(dx * dx + dy * dy)


## TS gfx/renderer.ts hsl(): `hsl(H S% L% / A)` with toFixed(0) rounding
## (ties toward +infinity -> floori(x + 0.5), positive domain here).
func _hsl(h: float, s: float, l: float, a: float = 1.0) -> String:
	return "hsl(%d %d%% %d%% / %.2f)" % [floori(h + 0.5), floori(s * 100.0 + 0.5),
			floori(l * 100.0 + 0.5), a]
