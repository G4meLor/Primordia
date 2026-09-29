## CELL STAGE sim core — the primordial ocean as a headless RefCounted: state
## structs, spawn tables, player physics/interactions, pellet economy, zones,
## death/respawn. Port of Spore src/game/cell/CellStage.ts (frozen), minus the
## render pass (scene layer, Tasks 7-9), the NPC AI loop (Task 4) and the
## chaos event bodies (Task 5 — stubbed no-ops below, zero rng draws).
##
## Architecture (M2 ruling): CellSim.new(ctx, rng_branch, hooks) —
##   ctx        the M1 GameContext; sim calls ctx methods directly
##   rng_branch the stage's dedicated Rng (the CALLER draws ctx.rng.branch(),
##              mirroring TS `this.rng = ctx.rng.branch()`)
##   hooks      Dictionary of Callables for every scene/audio effect; missing
##              key = silent no-op so tests can record selectively
## Scene concerns (camera follow/zoom, fx pool stepping, editor overlay,
## tutorial engine, KeyE branch) never enter this file — comments mark where
## the TS lines sit. No Input singleton reads: update(dt, inp) takes an input
## SNAPSHOT Dictionary (mx/my/wx/wy/down/clicked/take_click/keys_held/
## keys_pressed) the scene layer builds and tests construct literally.
##
## Recorded divergences (task 3 report carries the full list):
##  - playerSeed: TS `Math.random()*10` (CellStage.ts:97) draws from the
##    GLOBAL rng — native draws from the stage branch (visual-only seed), so
##    native streams diverge from a same-seed TS run by exactly one draw.
##  - TS first-frame death check `deathFade === dt` → `deathStarted` bool.
##  - ent.lastPlayerHit union → String ("" = none).
##  - fx bursts: TS Particles.burst consumes the stage rng (5 draws/particle:
##    ang, speed, color pick, ttl, size — gfx/particles.ts:70-84); the sim
##    replays those draws verbatim (_fx_burst) and ships the sampled
##    per-particle primitives to the scene through opts["parts"].
## Ent optional fields (swarm/lifespan) stay ABSENT until set, matching TS
## undefined semantics — readers use .get().
class_name CellSim
extends RefCounted

const RngScript := preload("res://src/core/rng.gd")
const StatsScript := preload("res://src/evo/stats.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const MutationScript := preload("res://src/evo/mutation.gd")
const NamesScript := preload("res://src/evo/names.gd")
const PartsScript := preload("res://src/evo/parts.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")

## Seconds between counted grudge presses for one ent (an engagement, not a
## frame) — mirrors the eco-side harassment valve. Kept stage-local: the valve
## constants are eco-internal. (Consumed by the Task 4 AI loop.)
const PRESS_COOLDOWN := 20.0

const WORLD_R := 2400.0
const PELLET_CAP := 260

# ---- hooks ---------------------------------------------------------------------

var ctx: Variant = null           # TS game.context
var rng: Variant = null           # TS this.rng (the stage branch)
var _hooks: Dictionary = {}


## Missing hook key = silent no-op (Callable check) — tests record selectively.
func _fire(hook: String, args: Array) -> void:
	var c: Variant = _hooks.get(hook)
	if c is Callable:
		(c as Callable).callv(args)


# ---- state (TS field names verbatim) --------------------------------------------

# player
var px := 0.0
var py := 0.0
var pvx := 0.0
var pvy := 0.0
var php := 100.0
var pmaxHp := 100.0
var pStats: Dictionary = {}
var invuln := 3.0
var biteCd := 0.0
var toxinCd := 0.0
var electroCd := 0.0
var dashCd := 0.0
var hurtT := 0.0
var eatT := 0.0
var dashT := 0.0
var nutrition := 0.0       # visual growth 0..1
var playerSeed := 0.0      # divergence: drawn from the stage rng (see header)
var moveAngle := 0.0

# world
var ents: Array[Dictionary] = []
var pellets: Array[Dictionary] = []
var zones: Array[Dictionary] = []
var kelp: Array[Dictionary] = []
var nextEid := 1
var time := 0.0
var eco: Variant = null
var ecoTimer := 0.0
var spawnTimer := 0.0
# TS deckSeed (C1: decks rebuilt from a stale WorldGenome) — Task 5 chaos
# wiring reads it; carried so the field keeps its TS place in the state.
var deckSeed := -1
var shoreAvailable := false
# The shore button rect lives in SCREEN space; the scene layer re-positions it
# each frame (TS render() mutated shoreRect directly — native: the scene writes
# this same dict, the sim only hit-tests it).
var shoreRect := {"x": 0.0, "y": 0.0, "w": 190.0, "h": 46.0}
var deathFade := 0.0
# TS `deathFade === dt` first-frame idiom → an honest bool (divergence ruling).
var deathStarted := false
var discovered := {}       # TS Set<string> — speciesId keys
var timers: Array = []     # {left: float, fn: Callable} — TS stage clock
## Tutorial progress counters (polled by the tutorial engine, Task 7-9).
var tut := {"moved": 0.0, "eaten": 0, "killed": 0, "editorOpened": 0}
## bio_tell: seconds left in the ambient panic-drift window.
var warnDriftT := 0.0
## mirror_rule state (minor 14) — Task 5 replaces this placeholder with the
## MirrorLedger port; carried so consumers keep a stable field name.
var mirrorLedger := {}


func _init(ctx_v: Variant, rng_branch: Variant, hooks: Dictionary = {}) -> void:
	ctx = ctx_v
	rng = rng_branch
	_hooks = hooks
	# DIVERGENCE D1 (drawn FIRST, before the eco bootstrap — TS field
	# initializer order): TS `playerSeed = Math.random()*10` (CellStage.ts:97)
	# draws from the GLOBAL rng; native draws from the stage branch instead.
	# Visual-only seed. The native stage stream consumes exactly one draw TS
	# never made, so per-seed runs are native-deterministic but not
	# stream-aligned with a same-seed TS run.
	playerSeed = rng.range(0.0, 10.0)
	pStats = StatsScript.compute_cell_stats(ctx.genome)
	pmaxHp = float(pStats["max_hp"])
	php = pmaxHp

	# ---- ecosystem bootstrap ---------------------------------------------------
	if ctx.eco == null:
		eco = EcoScript.new(rng.branch())
		seed_ecology()
		eco.designate_kin_tag(ctx.world)
		ctx.eco = eco
	else:
		eco = ctx.eco

	# TS CellStage.ts:146 constructs the ChaosScheduler here with
	# makeCellChaosEvents(ctx.world) — Task 5 wires it (deck rebuild included).
	deckSeed = ctx.world.seed

	# decorative kelp forest
	for i in 40:
		var a: float = rng.next() * TAU
		var r: float = rng.range(300.0, WORLD_R * 0.95)
		kelp.append({
			"x": cos(a) * r,
			"y": sin(a) * r,
			"len": rng.range(40.0, 110.0),
			"seed": rng.range(0.0, 10.0),
		})

	# starter pellets
	for i in 30:
		spawn_pellet("plant")


# ---------------------------------------------------------------------------------

## Port 1:1 — the 7 archetype genomes (exact field values), world-weighted
## diet flips, titan/swarm bonus species appended AFTER the roster.
func seed_ecology() -> void:
	var archetypes: Array = [
		{"size": 0.7, "diet": "herbivore", "flagella": 3, "jaw": 0, "spikes": 0, "hue": 90, "pattern": "spots"},
		{"size": 1.0, "diet": "omnivore", "flagella": 2, "jaw": 2, "hue": 30, "pattern": "plain"},
		{"size": 1.3, "diet": "carnivore", "flagella": 2, "jaw": 3, "hue": 0, "pattern": "stripes"},
		{"size": 0.8, "diet": "herbivore", "flagella": 1, "toxin": 3, "hue": 160, "pattern": "glow"},
		{"size": 1.8, "diet": "carnivore", "flagella": 2, "jaw": 4, "spikes": 3, "hue": 280},
		{"size": 0.6, "diet": "herbivore", "flagella": 5, "cilia": 2, "hue": 200},
		{"size": 1.1, "diet": "omnivore", "flagella": 2, "spikes": 4, "hue": 60, "pattern": "spots"},
	]
	# World-genome archetype weights bend the starting food web. All draws
	# come from this stage's rng branch (deterministic per seed). Minimal
	# honest mapping — the exotic catalog archetypes arrive in Task 9:
	#   herbivore W  → hunter/omnivore templates flip grazer, (W-1)*0.5 each
	#   carnivore W  → grazer templates flip hunter the same way
	#   predator W   → multiplies the carnivore pull (calm_veil 0.6 thins
	#                  hunters out of the draw)
	#   titan ≥ 1    → one extra large template species (pop NOT multiplied)
	#   swarm ≥ 1    → one extra small fast template species
	var weights: Dictionary = WorldGenomeScript.archetype_weights(ctx.world)
	var herbW: float = float(weights.get("herbivore", 1))
	var carnW: float = float(weights.get("carnivore", 1)) * float(weights.get("predator", 1))
	var herbPull: float = minf(0.9, maxf(0.0, herbW - 1.0) * 0.5 + maxf(0.0, 1.0 - carnW) * 0.5)
	var carnPull: float = minf(0.9, maxf(0.0, carnW - 1.0) * 0.5 + maxf(0.0, 1.0 - herbW) * 0.5)
	for arch in archetypes:
		# fixed base — seeding from the player's genome leaked unpaid genes
		# (proboscis/jet/electro) into wild species
		var g: Dictionary = GenomeScript.clone_genome(GenomeScript.default_genome())
		g.merge(arch, true)
		g["generation"] = 1
		if arch["diet"] == "herbivore" and rng.chance(carnPull):
			g["diet"] = "carnivore"
		elif arch["diet"] != "herbivore" and rng.chance(herbPull):
			g["diet"] = "herbivore"
		var sp_name: String = ("%s %s" % [NamesScript.species_name(rng), NamesScript.epithet(g, rng)]).strip_edges()
		var sp: Dictionary = eco.add_species(g, rng.range(4, 9), {"name": sp_name})
		ctx.discover(g, sp["name"], "cell")
	# bonus species appended AFTER the base roster so their diet/size
	# survive the diet dial above untouched
	if float(weights.get("titan", 0)) >= 1.0:
		var gt: Dictionary = GenomeScript.clone_genome(GenomeScript.default_genome())
		gt.merge({"size": 2.2, "diet": "carnivore", "flagella": 2, "jaw": 4, "spikes": 3, "hue": 330}, true)
		gt["generation"] = 1
		var nt: String = ("%s %s" % [NamesScript.species_name(rng), NamesScript.epithet(gt, rng)]).strip_edges()
		var spt: Dictionary = eco.add_species(gt, rng.range(4, 9), {"name": nt})
		ctx.discover(gt, spt["name"], "cell")
	if float(weights.get("swarm", 0)) >= 1.0:
		var gs: Dictionary = GenomeScript.clone_genome(GenomeScript.default_genome())
		gs.merge({"size": 0.55, "diet": "herbivore", "flagella": 5, "cilia": 3, "hue": 210, "pattern": "glow"}, true)
		gs["generation"] = 1
		var ns: String = ("%s %s" % [NamesScript.species_name(rng), NamesScript.epithet(gs, rng)]).strip_edges()
		var sps: Dictionary = eco.add_species(gs, rng.range(4, 9), {"name": ns})
		ctx.discover(gs, sps["name"], "cell")


# ---- update ----------------------------------------------------------------------

## inp: input SNAPSHOT Dictionary — mx, my, wx, wy, down, clicked,
## take_click (pre-taken flag), keys_held: Array[String],
## keys_pressed: Array[String]. The scene layer builds it; tests construct
## it literally. The sim never touches the Input singleton.
func update(dt: float, inp: Dictionary) -> void:
	time += dt

	# stage timers
	for i in range(timers.size() - 1, -1, -1):
		var t: Dictionary = timers[i]
		t["left"] = float(t["left"]) - dt
		if float(t["left"]) <= 0.0:
			timers.remove_at(i)
			var fn: Callable = t["fn"]
			fn.call()

	# TS CellStage.ts:351 — the editor branch keys off input.keyPressed('KeyE')
	# and RETURNS early (the dead cannot rewrite their genome). The editor is
	# a scene overlay (Task 8): the branch sits HERE in TS, skipped natively.

	# tutorial: scene-side engine (Task 7-9); the tut counters live on the sim.

	# shore button click (the dead cannot ascend)
	var mx: float = float(inp.get("mx", 0.0))
	var my: float = float(inp.get("my", 0.0))
	if bool(inp.get("clicked", false)) and not bool(inp.get("take_click", false)) \
			and php > 0.0 and shoreAvailable and over_shore(mx, my):
		_fire("audio_play", ["ascend", 0.9, 0.0])
		_fire("game_save_all", [])  # shore arrival — flush stage state with the save
		_fire("shore_travel", [])   # the goTo('creature', …) is scene-side
		return

	update_player(dt, inp)
	# bio_tell: the panic window tracks the live warn phase — ambient herds
	# drift out of the strike zone while it runs (TS reads
	# this.chaos.warnRemaining; Task 5 wires the scheduler).
	warnDriftT = 0.0
	update_ents(dt)
	update_pellets(dt)
	update_zones(dt)

	# ecology tick ~ every 2 s of sim time
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
			ctx.add_chaos(0.05)
			_fire("hud_banner", [{
				"title": "%s is extinct" % ex["name"],
				"subtitle": "the ocean grows quieter…",
				"kind": "chaos",
			}])
		for sh in out.get("shifts", []):
			# bio_shift: the web re-equilibrates around the loss
			_fire("hud_toast", ["%s %s → %s" % [tr("The web re-equilibrates:"),
					_diet_name(sh["from"]), _diet_name(sh["to"])], "chaos", "🕸"])
		for newsp in out["speciations"]:
			ctx.discover(newsp["genome"], newsp["name"], "cell")
			_fire("hud_toast", ["A new species emerges: %s" % newsp["name"], "chaos", "🧬"])
		# keep flora fed pellets
		if eco.flora >= 12.0 and _plant_count() < 60:
			spawn_pellet("plant")

	spawnTimer += dt
	if spawnTimer >= 1.2:
		spawnTimer = 0.0
		maintain_population()

	# chaos (TS CellStage.ts:418 — chaos.update with onWarn/onApply/onEnd;
	# onApply fires storyteller_note_chaos_event(ctx.playtime). Task 5.)

	# camera (TS cam.follow(px, py, dt, 5), zoom = 1, toWorld → setWorld) and
	# the fx pool steps: scene-side, Tasks 7-9. The sim never touches cam.

	# bestiary proximity discovery
	for e in ents:
		if e["speciesId"] == "player" or bool(e.get("swarm", false)):
			continue
		if not discovered.has(e["speciesId"]) \
				and Vector2(e["x"], e["y"]).distance_to(Vector2(px, py)) < 420.0:
			discovered[e["speciesId"]] = true
			var sp: Variant = null
			for s in eco.species:
				if s["id"] == e["speciesId"]:
					sp = s
					break
			if sp != null:
				ctx.discover(sp["genome"], sp["name"], "cell")

	# cooldowns
	biteCd = maxf(0.0, biteCd - dt)
	toxinCd = maxf(0.0, toxinCd - dt)
	electroCd = maxf(0.0, electroCd - dt)
	dashCd = maxf(0.0, dashCd - dt)
	hurtT = maxf(0.0, hurtT - dt * 3.0)
	eatT = maxf(0.0, eatT - dt * 2.0)
	invuln = maxf(0.0, invuln - dt)
	dashT = maxf(0.0, dashT - dt)
	nutrition = maxf(0.0, nutrition - dt * 0.01)

	# death
	if php <= 0.0:
		handle_death(dt)

	# shore button
	shoreAvailable = float(ctx.genome.get("legs", 0)) >= 1.0

	# hud abilities (TS setAbilities push, CellStage.ts:488) — the native HUD
	# polls the cd fields through the public state instead (no hook by ruling).


func handle_death(dt: float) -> void:
	deathFade += dt
	if not deathStarted:
		# TS first-frame idiom `deathFade === dt` (CellStage.ts:499) → bool
		deathStarted = true
		_fire("context_event", ["playerDeath", "cell"])  # storyteller signal
		_fire("audio_play", ["die", 0.8, 0.0])
		_fire("cam_shake", [10.0, 0.5])
		var lost := floori(float(ctx.dna) * 0.12 + 0.5)  # JS Math.round
		ctx.add_dna(-lost)
		_fire("hud_toast", ["%s %d DNA" % [tr("You died — lost"), lost], "bad", "💀"])
		ctx.add_chaos(0.03)
		_fx_burst(px, py, 30, [_hsl(float(ctx.genome["hue"]), 0.7, 0.6), "#ff8a9a"],
				{"speed": 160.0, "ttl": 1.0})
	if deathFade > 1.6:
		deathFade = 0.0
		deathStarted = false
		php = pmaxHp
		invuln = 4.0
		# respawn at safe spot
		var a: float = rng.next() * TAU
		px = cos(a) * 600.0
		py = sin(a) * 600.0
		pvx = 0.0
		pvy = 0.0
		# clear nearby threats
		var kept: Array[Dictionary] = []
		for e in ents:
			if Vector2(e["x"], e["y"]).distance_to(Vector2(px, py)) > 700.0:
				kept.append(e)
		ents = kept


func update_player(dt: float, inp: Dictionary) -> void:
	var s: Dictionary = pStats
	var genome: Dictionary = ctx.genome
	var held: Array = inp.get("keys_held", [])
	var pressed: Array = inp.get("keys_pressed", [])
	var mx: float = float(inp.get("mx", 0.0))
	var my: float = float(inp.get("my", 0.0))
	var wx: float = float(inp.get("wx", 0.0))
	var wy: float = float(inp.get("wy", 0.0))
	var down: bool = bool(inp.get("down", false))

	# desired direction: mouse hold or WASD
	var dx := 0.0
	var dy := 0.0
	if down and not over_shore(mx, my):
		dx = wx - px
		dy = wy - py
		var d := sqrt(dx * dx + dy * dy)
		if d < 12.0:  # dead zone
			dx = 0.0
			dy = 0.0
	if held.has("KeyW") or held.has("ArrowUp"):
		dy -= 1.0
	if held.has("KeyS") or held.has("ArrowDown"):
		dy += 1.0
	if held.has("KeyA") or held.has("ArrowLeft"):
		dx -= 1.0
	if held.has("KeyD") or held.has("ArrowRight"):
		dx += 1.0
	var dl := sqrt(dx * dx + dy * dy)
	if dl > 0.0:
		dx /= dl
		dy /= dl
	if dl > 0.0:
		moveAngle = atan2(dy, dx)

	# dash
	var jet: float = float(genome.get("jet", 0))
	if (pressed.has("Space") or pressed.has("KeyShift")) and jet > 0.0 and dashCd <= 0.0:
		var pow_v: float = 260.0 + jet * 90.0
		var ang: float = atan2(dy, dx) if dl > 0.0 else moveAngle
		pvx += cos(ang) * pow_v
		pvy += sin(ang) * pow_v
		dashCd = 3.0
		dashT = 0.35
		_fire("audio_play", ["dash", 0.7, 0.0])
		_fx_burst(px, py, 12, ["#bfe9ff", "#7fb8ff"], {"speed": 120.0, "ttl": 0.5, "size": 2.5})

	# toxin burst
	var toxin: float = float(genome.get("toxin", 0))
	if pressed.has("Digit1") and toxin > 0.0 and toxinCd <= 0.0 and php > 0.0 and not deathStarted:
		toxinCd = 6.0
		zones.append({
			"x": px, "y": py,
			"r": 60.0 + toxin * 22.0, "kind": "toxin", "ttl": 6.0,
			"dps": 4.0 + toxin * 4.0, "pulse": 0.0, "mine": true,
		})
		_fire("audio_play", ["toxin", 0.8, 0.0])

	# electro burst
	var electro: float = float(genome.get("electro", 0))
	if pressed.has("Digit2") and electro > 0.0 and electroCd <= 0.0 and php > 0.0 and not deathStarted:
		electroCd = 10.0
		var r: float = 160.0 + electro * 70.0
		_fire("audio_play", ["zap", 0.9, 0.0])
		_fire("cam_shake", [4.0, 0.3])
		for e in ents:
			if Vector2(e["x"], e["y"]).distance_to(Vector2(px, py)) < r:
				e["stun"] = maxf(float(e["stun"]), 1.8 + electro * 0.7)
				_fx_burst(float(e["x"]), float(e["y"]), 6, ["#ffe97a", "#9fd8ff"],
						{"speed": 100.0, "ttl": 0.4})
		_fx_burst(px, py, 20, ["#ffe97a", "#9fd8ff"], {"speed": 220.0, "ttl": 0.5})

	# physics
	var accel: float = float(s["accel"])
	pvx += dx * accel * dt
	pvy += dy * accel * dt
	# current
	var cur: float = current_at(py)
	pvx += cur * dt
	var drag: float = exp(-(1.2 if dashT > 0.0 else 2.6) * dt)
	pvx *= drag
	pvy *= drag
	var sp := sqrt(pvx * pvx + pvy * pvy)
	var maxSp: float = float(s["speed"]) * (2.6 if dashT > 0.0 else 1.0)
	if sp > maxSp:
		pvx *= maxSp / sp
		pvy *= maxSp / sp
	px += pvx * dt
	py += pvy * dt
	tut["moved"] = float(tut["moved"]) + sp * dt

	# soft world boundary
	var dOrigin := sqrt(px * px + py * py)
	if dOrigin > WORLD_R:
		var push: float = (dOrigin - WORLD_R) * 2.5
		pvx -= (px / dOrigin) * push * dt * 10.0
		pvy -= (py / dOrigin) * push * dt * 10.0
		if dOrigin > WORLD_R + 200.0:
			px *= (WORLD_R + 200.0) / dOrigin
			py *= (WORLD_R + 200.0) / dOrigin

	# movement particles
	if sp > 40.0 and rng.chance(dt * 14.0):
		_fire("fx_spawn", [{
			"x": px - cos(moveAngle) * 12.0,
			"y": py - sin(moveAngle) * 12.0,
			"vx": rng.range(-6.0, 6.0), "vy": rng.range(-20.0, -4.0),
			"ttl": 1.6, "size": rng.range(1.5, 3.2), "kind": "bubble",
			"color": "rgba(190,230,255,0.8)", "drag": 1.0,
		}])

	# toxin passive aura
	if float(s["toxin"]) > 0.0 and rng.chance(dt * 2.0):
		_fire("fx_spawn", [{
			"x": px + rng.range(-14.0, 14.0), "y": py + rng.range(-14.0, 14.0),
			"vx": rng.range(-10.0, 10.0), "vy": rng.range(-10.0, 10.0),
			"ttl": 1.4, "size": rng.range(3.0, 6.0), "kind": "smoke",
			"color": "rgba(120,255,120,0.5)", "drag": 0.5,
		}])

	# interactions with ents
	var pR: float = player_radius()
	for e in ents:
		var d: float = Vector2(e["x"], e["y"]).distance_to(Vector2(px, py))
		var eR: float = 14.0 * float(e["genome"]["size"])
		if d < pR + eR:
			# spikes hurt enemies touching us (alive only)
			if float(e["hp"]) > 0.0 and float(s["contact_damage"]) > 0.0 \
					and php > 0.0 and not deathStarted:
				e["hp"] = float(e["hp"]) - float(s["contact_damage"]) * dt * 2.0
				e["hurtT"] = 0.5
				e["lastPlayerHit"] = "contact"
			# proboscis drains bigger cells (alive only)
			var proboscis: float = float(genome.get("proboscis", 0))
			if float(e["hp"]) > 0.0 and proboscis > 0.0 \
					and float(e["genome"]["size"]) > float(genome.get("size", 1)) * 0.9 \
					and float(e["stun"]) <= 0.0 and php > 0.0 and not deathStarted:
				var drain: float = proboscis * 3.0 * dt
				e["hp"] = float(e["hp"]) - drain * 2.0
				e["lastPlayerHit"] = "drain"
				ctx.add_dna(drain * 0.4)
				if rng.chance(dt * 8.0):
					_fire("fx_spawn", [{
						"x": e["x"], "y": e["y"],
						"vx": (px - float(e["x"])) * 2.0, "vy": (py - float(e["y"])) * 2.0,
						"ttl": 0.5, "size": 2.4, "kind": "dot", "color": "#b08aff", "drag": 1.0,
					}])
			# our bite (automatic when overlapping) — alive only: a corpse used
			# to keep biting, spiking and draining while the fade ran
			if biteCd <= 0.0 and float(e["hp"]) > 0.0 and php > 0.0 and not deathStarted:
				biteCd = 0.55
				var dmg: float = float(s["damage"]) * (1.0 - minf(0.5, float(e["stats"]["defense"])))
				e["hp"] = float(e["hp"]) - dmg
				e["hurtT"] = 0.6
				eatT = 1.0
				_fire("audio_play", ["chomp", 0.5, clampf((float(e["x"]) - px) / 300.0, -1.0, 1.0)])
				_fx_burst(float(e["x"]), float(e["y"]), 7,
						["#ff9a8a", "#ffd7a8", _hsl(float(e["genome"]["hue"]), 0.7, 0.55)],
						{"speed": 130.0, "ttl": 0.5, "size": 2.6})
				if float(e["hp"]) <= 0.0:
					kill_ent(e)
			# their bite on us
			if float(e["biteCd"]) <= 0.0 and float(e["stun"]) <= 0.0 \
					and float(e["stats"]["damage"]) > 0.0:
				e["biteCd"] = 0.8
				var dmg2: float = float(e["stats"]["damage"]) * (1.0 - float(s["defense"]))
				if invuln <= 0.0:
					php -= dmg2
					hurtT = 1.0
					_fire("cam_shake", [3.0, 0.2])
					_fire("audio_play", ["hurt", 0.5, 0.0])
				_fx_burst(px, py, 4, ["#ff8a9a"], {"speed": 90.0, "ttl": 0.4, "size": 2.0})

	# vent healing (never rescues a dying cell)
	if php > 0.0 and not deathStarted:
		for z in zones:
			if z["kind"] == "vent" \
					and Vector2(px, py).distance_to(Vector2(z["x"], z["y"])) < float(z["r"]):
				php = minf(pmaxHp, php + float(z.get("heal", 0.0)) * dt)


func kill_ent(e: Dictionary) -> void:
	tut["killed"] = int(tut["killed"]) + 1
	_fire("audio_play", ["die", 0.5, clampf((float(e["x"]) - px) / 300.0, -1.0, 1.0)])
	_fx_burst(float(e["x"]), float(e["y"]), 16,
			[_hsl(float(e["genome"]["hue"]), 0.75, 0.55), "#ff9a8a", "#ffe0b0"],
			{"speed": 150.0, "ttl": 0.8, "size": 2.8})
	# meat pellets
	var nMeat := 1 + floori(float(e["genome"]["size"]))
	for i in nMeat:
		pellets.append({
			"x": float(e["x"]) + rng.range(-10.0, 10.0),
			"y": float(e["y"]) + rng.range(-10.0, 10.0),
			"vx": rng.range(-20.0, 20.0), "vy": rng.range(-20.0, 20.0),
			"kind": "meat", "ttl": 30, "val": 3,
		})
	if bool(e.get("swarm", false)):
		ctx.add_dna(8)
		ctx.add_karma(-0.004)
	else:
		var dna: int = eco.notify_kill(e["speciesId"], float(ctx.genome["size"]))
		ctx.bump_kill()  # world-story counter (feeds 'kill' reveal conditions)
		ctx.add_dna(dna)
		_fire("hud_float_world", [float(e["x"]), float(e["y"]) - 20.0, "+%d" % dna, "#9fd8ff", 13.0])
		ctx.add_karma(-0.002 if e["genome"]["diet"] == "herbivore" else -0.0005)
		# kin_memory: the kin-tag network keeps the ONE grudge ledger — the
		# first entry is preceded by exactly one warning (catalog I.b)
		var sp: Variant = null
		for x in eco.species:
			if x["id"] == e["speciesId"]:
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
		if rng.chance(0.06):
			# rare: mutation snack — a glimpse of a mutated cousin
			var lsp: Variant = null
			for s in eco.living():
				if s["id"] == e["speciesId"]:
					lsp = s
					break
			if lsp != null:
				var mutant: Dictionary = MutationScript.mutate(lsp["genome"], rng, 0.9)
				spawn_ent(null, float(e["x"]) + 60.0, float(e["y"]), mutant, {"lifespan": 25})
				_fire("hud_toast", [tr("A mutant cousin appears!"), "chaos", "🧪"])
	e["hp"] = -1.0  # mark for removal
	e["lastPlayerHit"] = ""  # paid once — bite/meteor finishers arrive
	# at the splice tag-free, while contact/drain/toxin deaths keep theirs


## Task 4: full NPC AI port (TS CellStage.ts:743-933) — the hp<=0 death sweep
## (tagged killEnt payment), lifespan expiry, cooldown/stun decay, panic/
## hunt/flee/wander steering, separation, pellet eating and toxin-zone damage
## all live in that loop. STUBBED here: deterministically absent — no
## movement, no rng draws, no removals. Bite-killed ents (hp = -1) linger
## inert until Task 4's sweep; the player-interaction branches guard
## e.hp > 0, so nothing double-pays meanwhile.
@warning_ignore("unused_parameter")
func update_ents(dt: float) -> void:
	pass


func update_pellets(dt: float) -> void:
	var pR: float = player_radius()
	var i: int = pellets.size() - 1
	while i >= 0:
		var p: Dictionary = pellets[i]
		p["ttl"] = float(p["ttl"]) - dt
		p["x"] = float(p["x"]) + float(p["vx"]) * dt
		p["y"] = float(p["y"]) + float(p["vy"]) * dt
		p["vx"] = float(p["vx"]) * exp(-1.5 * dt)
		p["vy"] = float(p["vy"]) * exp(-1.5 * dt)
		p["vx"] = float(p["vx"]) + current_at(float(p["y"])) * dt
		if float(p["ttl"]) <= 0.0:
			pellets.remove_at(i)
			i -= 1
			continue
		if Vector2(p["x"], p["y"]).distance_to(Vector2(px, py)) < pR + 6.0:
			if php <= 0.0 or deathStarted:
				i -= 1
				continue  # no posthumous farming
			pellets.remove_at(i)
			eatT = 1.0
			tut["eaten"] = int(tut["eaten"]) + 1
			if p["kind"] == "dna":
				ctx.add_dna(float(p["val"]))
				_fire("hud_float_world", [float(p["x"]), float(p["y"]),
						"+%d DNA" % int(p["val"]), "#c9a4ff", 13.0])
				_fire("audio_play", ["dna", 0.6, 0.0])
			else:
				ctx.add_dna(float(p["val"]))  # meat advertises val 5 — pay what the pellet says
				if p["kind"] == "plant":
					eco.flora = maxf(0.0, eco.flora - 0.4)
					ctx.add_karma(0.0005)
					nutrition = minf(1.0, nutrition + 0.03)
				elif not deathStarted and php > 0.0:
					# scavenge heal — never out-races the death fade (ghost freeze)
					php = minf(pmaxHp, php + 5.0)
					ctx.add_karma(-0.0005)  # scavenge is not murder
					# scavenging meat counts toward the tutorial hunt step —
					# chasing fleeing prey at stock speed is hard enough already
					tut["killed"] = int(tut["killed"]) + 1
				_fire("audio_play", ["eat", 0.4, 0.0])
				_fx_burst(float(p["x"]), float(p["y"]), 4,
						["#9fe89a" if p["kind"] == "plant" else "#ffb08a"],
						{"speed": 60.0, "ttl": 0.4, "size": 2.0})
		i -= 1


func update_zones(dt: float) -> void:
	var i: int = zones.size() - 1
	while i >= 0:
		var z: Dictionary = zones[i]
		z["pulse"] = float(z["pulse"]) + dt
		if float(z["ttl"]) > 0.0:
			z["ttl"] = float(z["ttl"]) - dt
			if float(z["ttl"]) <= 0.0:
				zones.remove_at(i)
				i -= 1
				continue
		if z["kind"] == "toxin":
			z["x"] = float(z["x"]) + sin(float(z["pulse"]) * 0.7) * 14.0 * dt
			z["y"] = float(z["y"]) + cos(float(z["pulse"]) * 0.5) * 14.0 * dt
			if rng.chance(dt * 8.0):
				_fire("fx_spawn", [{
					"x": float(z["x"]) + rng.range(-float(z["r"]), float(z["r"])) * 0.7,
					"y": float(z["y"]) + rng.range(-float(z["r"]), float(z["r"])) * 0.7,
					"vx": 0.0, "vy": -8.0, "ttl": 1.5, "size": rng.range(4.0, 9.0),
					"kind": "smoke", "color": "rgba(140,255,140,0.35)", "drag": 0.5,
				}])
		elif z["kind"] == "vent":
			# bubble plumes spawn in update, never in render
			if rng.chance(dt * 7.0):
				_fire("fx_spawn", [{
					"x": float(z["x"]) + rng.range(-8.0, 8.0), "y": float(z["y"]),
					"vx": rng.range(-4.0, 4.0), "vy": rng.range(-70.0, -40.0),
					"ttl": 2.0, "size": rng.range(2.0, 5.0), "kind": "bubble",
					"color": "rgba(255,220,180,0.6)", "drag": 0.5,
				}])
		i -= 1


func current_at(y: float) -> float:
	# gentle horizontal currents in bands
	return sin(y * 0.004 + time * 0.05) * 14.0


func player_radius() -> float:
	return 14.0 * float(ctx.genome.get("size", 1)) * (1.0 + nutrition * 0.35)


func over_shore(sx: float, sy: float) -> bool:
	return sx >= float(shoreRect["x"]) and sx <= float(shoreRect["x"]) + float(shoreRect["w"]) \
			and sy >= float(shoreRect["y"]) and sy <= float(shoreRect["y"]) + float(shoreRect["h"]) \
			and shoreAvailable


# ---- spawning --------------------------------------------------------------------

func spawn_pellet(kind: String, x: Variant = null, y: Variant = null) -> void:
	var a: float = rng.next() * TAU
	var r: float = rng.range(0.0, 900.0)
	pellets.append({
		"x": float(x) if x != null else cos(a) * r,
		"y": float(y) if y != null else sin(a) * r,
		"vx": rng.range(-8.0, 8.0),
		"vy": rng.range(-8.0, 8.0),
		"kind": kind,
		"ttl": 25.0 if kind == "meat" else 40.0,
		"val": 5 if kind == "meat" else 2,
	})
	if pellets.size() > PELLET_CAP:
		pellets.pop_front()  # TS shift()


func spawn_ent_for_species(sp: Dictionary) -> void:
	var a: float = rng.next() * TAU
	var d: float = rng.range(750.0, 1000.0)
	spawn_ent(sp, px + cos(a) * d, py + sin(a) * d)


func spawn_ent(sp: Variant, x: float, y: float, genome_override: Dictionary = {},
		opts: Dictionary = {}) -> Dictionary:
	var genome: Dictionary
	if not genome_override.is_empty():
		genome = genome_override
	elif sp != null:
		genome = sp["genome"]
	else:
		genome = ctx.genome
	var stats: Dictionary = StatsScript.compute_cell_stats(genome)
	var speciesId: String = sp["id"] if sp != null else "mutant"
	var e: Dictionary = {
		"eid": nextEid,
		"speciesId": speciesId,
		"genome": genome,
		"x": x, "y": y,
		"vx": 0.0, "vy": 0.0,
		"hp": float(stats["max_hp"]),
		"maxHp": float(stats["max_hp"]),
		"stats": stats,
		"stun": 0.0,
		# TS union 'contact'|'drain'|'toxin'|undefined → String, "" = none
		"lastPlayerHit": "",
		"hurtT": 0.0,
		"eatT": 0.0,
		"biteCd": 0.0,
		"seed": rng.range(0.0, 100.0),
		"wanderT": 0.0,
		"tx": x, "ty": y,
		"big": float(genome.get("size", 1)) > 1.6,
		"band": WorldGenomeScript.behavior_band(ctx.world, speciesId),
	}
	nextEid += 1
	# TS-optional fields stay ABSENT until set (undefined semantics): Task 4
	# reads them with .get() the way TS reads e.swarm / e.lifespan. pressCd
	# is added by the AI loop on the first grudge press.
	if opts.has("swarm"):
		e["swarm"] = opts["swarm"]
	if opts.has("lifespan"):
		e["lifespan"] = opts["lifespan"]
	ents.append(e)
	return e


func maintain_population() -> void:
	# Remove far-away ents
	var kept: Array[Dictionary] = []
	for e in ents:
		if Vector2(e["x"], e["y"]).distance_to(Vector2(px, py)) < 1600.0:
			kept.append(e)
	ents = kept
	for sp in eco.living():
		if bool(sp.get("kin", false)):
			continue
		var visible := 0
		for e in ents:
			if e["speciesId"] == sp["id"]:
				visible += 1
		var target: int = mini(9, floori(float(sp["pop"]) * 0.6 + 0.5))  # JS Math.round
		if visible < target and rng.chance(0.4):
			spawn_ent_for_species(sp)


## Schedule a callback on the stage's game-time clock (TS after()).
func after(seconds: float, fn: Callable) -> void:
	timers.append({"left": seconds, "fn": fn})


# ---- chaos event helpers (called by cellEvents — Task 5 fills the bodies).
# Stubbed no-ops with exact TS signatures; deterministically absent: zero rng
# draws, no state pushes (the test suite pins rng-state invariance).

@warning_ignore("unused_parameter")
func spawn_meteor_target(x: float, y: float) -> void:
	pass  # TS CellStage.ts:1203 — meteorTarget ring, r 150, ttl 2.5


@warning_ignore("unused_parameter")
func meteor_impact(x: float, y: float) -> void:
	pass  # TS CellStage.ts:1207 — boom/shake/damage ring + DNA debris


@warning_ignore("unused_parameter")
func add_toxin_zone(x: float, y: float, r: float, dps: float, ttl: float,
		source: String = "redtide") -> void:
	pass  # TS CellStage.ts:1239 — toxin zone push (redtide / toxin_clouds)


@warning_ignore("unused_parameter")
func drift_toxin_clouds(dt: float) -> void:
	pass  # TS CellStage.ts:1244 — the variant's own clouds home the player


func algae_surge() -> void:
	pass  # TS CellStage.ts:1259 — bloom + grazer boom + 20 plant pellets


@warning_ignore("unused_parameter")
func add_vent(x: float, y: float) -> void:
	pass  # TS CellStage.ts:1274 — bounded heal vent (max 6, ttl 240, heal 6)


func bloom() -> void:
	pass  # TS CellStage.ts:1281 — flora surge + 30 plant pellets


func blight() -> void:
	pass  # TS CellStage.ts:1296 — bloom's mirror face: flora collapses


func spawn_swarm() -> void:
	pass  # TS CellStage.ts:1326 — 4 mutant hunters, lifespan 30


func spawn_big_brother() -> Variant:
	return null  # TS CellStage.ts:1335 — returns the spawned CellEnt


func spawn_mutant_wave() -> int:
	return 0  # TS CellStage.ts:1367 — 2-3 wild mutants near the player


## gaia_redemption tier 2: the Lone Wanderer — one quiet individual with a
## gene this run never owned. The bestiary notes it once (discover), then
## stays silent.
func gaia_wanderer() -> void:
	var rare: Variant = ctx.rare_gene()
	if rare == null:
		return
	var g: Dictionary = GenomeScript.default_genome()
	g[rare["gene"]] = rare["level"]
	g = GenomeScript.clamp_genome(g)
	var a: float = rng.next() * TAU
	spawn_ent(null, px + cos(a) * 260.0, py + sin(a) * 260.0, g, {"lifespan": 120})
	ctx.discover(g, "%s wanderer" % NamesScript.species_name(rng), "cell")


## Editor hook: recompute derived stats so purchases apply immediately.
func on_stats_changed() -> void:
	pStats = StatsScript.compute_cell_stats(ctx.genome)
	pmaxHp = float(pStats["max_hp"])
	if php > 0.0:
		php = minf(php, pmaxHp)


## Test hook: spawn n wild ents inside the bio_tell strike zone
## (area-uniform radius ≤ 320 around the player).
func debug_spawn_near(n: int) -> void:
	var pool: Array = []
	for sp in eco.living():
		if not bool(sp.get("kin", false)):
			pool.append(sp)
	if pool.is_empty():
		return
	for i in n:
		var a: float = rng.next() * TAU
		var d: float = sqrt(rng.next()) * 320.0
		spawn_ent(pool[i % pool.size()], px + cos(a) * d, py + sin(a) * d)


## Debug/test access to internal sim state (TS debugState shape).
func debug_state() -> Dictionary:
	return {"px": px, "py": py, "php": php, "ents": ents, "pellets": pellets}


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


func _plant_count() -> int:
	var n := 0
	for p in pellets:
		if p["kind"] == "plant":
			n += 1
	return n


## TS gfx/renderer.ts hsl(): `hsl(H S% L% / A)` with toFixed(0) rounding
## (ties toward +infinity → floori(x + 0.5), positive domain here).
func _hsl(h: float, s: float, l: float, a: float = 1.0) -> String:
	return "hsl(%d %d%% %d%% / %.2f)" % [floori(h + 0.5), floori(s * 100.0 + 0.5),
			floori(l * 100.0 + 0.5), a]
