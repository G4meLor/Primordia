## CELL STAGE sim core — the primordial ocean as a headless RefCounted: state
## structs, spawn tables, player physics/interactions, NPC AI (update_ents),
## pellet economy, zones, death/respawn, chaos event helpers + the chaos
## update loop. Port of Spore src/game/cell/CellStage.ts (frozen), minus the
## render pass (scene layer, Tasks 7-9). Event defs live in cell_events.gd
## (the cellEvents.ts port); the REVEAL PUMP itself is Task 9's scope (game
## orchestrator) — this file exposes what it needs (per-tick stage time, the
## warn window, the chaos ctx fields) and owns the eco-batch outcomes.
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
const ChaosScript := preload("res://src/game/chaos.gd")
const CellEventsScript := preload("res://src/game/cell/cell_events.gd")

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

# Flat read-mirrors for update_ents' O(N)/O(P) inner scans (M2 perf probe:
# the 200-ent budget measured the Dictionary chains hot). Same values in the
# same candidate order — pure read-path change, bit-exact by construction.
# Rebuilt at update_ents entry; synced on every in-loop mutation (death-sweep
# removals, position/hp writes, kill_ent/spawn_ent/spawn_pellet appends).
var _exs := PackedFloat64Array()
var _eys := PackedFloat64Array()
var _ehps := PackedFloat64Array()
var _esizes := PackedFloat64Array()
var _eeids := PackedInt32Array()
var _evision := PackedFloat64Array()
var _edmg := PackedFloat64Array()
var _espeed := PackedFloat64Array()
var _eaccel := PackedFloat64Array()
var _pxs := PackedFloat64Array()
var _pys := PackedFloat64Array()
var _pk := PackedInt32Array()  # 0 plant / 1 meat / 2 dna
var _pdead := PackedInt32Array()  # 1 = eaten this tick (compacted at tick end)
var _flat_live := false
# Order-preserving neighborhood grids over the flat arrays (candidate PRUNING
# only — a candidate the grid excludes provably fails its distance check, and
# the gathered indices are sorted ascending = the full scan's order, so every
# order-sensitive accumulation keeps its exact term order). Rebuilt lazily:
# any ent removal/append or pellet append marks the grid dirty; the next
# gather rebuilds it. Exactness of the pruning, per grid:
# - ent grid: cell ≥ 14·(size_i+size_j) for every pair, and the buckets hold
#   LIVE cells (tick-start build + _ent_cell_sync at every position write) —
#   so a candidate within minD of the scanning ent's live position is always
#   in the ent's current-cell ±1 neighborhood. (A tick-start-frame-only grid
#   would NOT be exact: an ent drifting across a boundary mid-tick while its
#   bucket stayed stale could be missed — the sync closes that gap.)
# - pellet grids: pellets never move during update_ents, so build cells are
#   live cells; cell > eatR / the 300 px seek radius covers every in-range
#   candidate.
# The grid_gather=false seam (test_grid_gather_equivalence_full_scan) runs
# seeded crowded configs through both gathers and asserts identical state —
# the automated grid≡full-scan gate behind this comment.
var _eg: Dictionary = {}
var _eg_cell := 29.0
var _eg_dirty := false
# each ent's CURRENT grid cell (kept live by _ent_cell_sync — buckets always
# reflect live positions, which is what makes the 3x3 gather exact under
# mid-tick drift, not just at tick start)
var _ecellx := PackedInt32Array()
var _ecelly := PackedInt32Array()
var _pg_eat: Dictionary = {}
var _pg_seek: Dictionary = {}
var _pg_cell := 15.0
var _pg_dirty := false
# toxin-zone flat snapshot (zones are constant during update_ents —
# update_zones runs after it)
var _zn := 0
var _zxs := PackedFloat64Array()
var _zys := PackedFloat64Array()
var _zr := PackedFloat64Array()
var _zdps := PackedFloat64Array()
var _ztoxin := PackedInt32Array()
var _zmine := PackedInt32Array()
var _cand := PackedInt32Array()  # reusable candidate gather (grid_near + sort)
## Test seam (grid-equivalence test): false forces the candidate gathers to
## full scans — the same lists the pre-optimization loops iterated. The
## equivalence test runs identical seeded configs through both modes and
## asserts identical state evolution.
var grid_gather := true
# per-tick AI hoists (invariant reads) + the species grudge cache
var _first_ai := true
var _p_size := 1.0
var _p_damage := 0.0
var _gcache: Dictionary = {}
# per-tick tide_species cache — the original re-read eco.tide_species() per
# ent; the result can only change mid-tick through kill_ent (drop_corpse's
# revive/refound), which invalidates. Reproduces the fresh reads exactly.
var _tide: Variant = null
var _tide_valid := false

var nextEid := 1
var time := 0.0
var eco: Variant = null
var ecoTimer := 0.0
var spawnTimer := 0.0
# TS deckSeed (C1: decks rebuilt from a stale WorldGenome) — ensure_deck()
# compares and rebuilds.
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
## TS ChaosScheduler<CellStage> (private `chaos` + getter in TS; GDScript
## keeps one public field). Constructed in _init at the TS stream position.
var chaos: Variant = null
## mirror_rule state (minor 14) — the shared MirrorLedger.
var mirrorLedger := ChaosScript.MirrorLedger.new()


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

	# TS CellStage.ts:146 — the chaos deck. The scheduler's stage-rng branch is
	# drawn AFTER the eco bootstrap (seedEcology) and BEFORE kelp: stream-order
	# sensitive (branch() consumes one parent draw). make_cell_chaos_events
	# itself draws nothing (a traitless mirror_bucket roll uses a fresh rng).
	chaos = ChaosScript.new(rng.branch(), CellEventsScript.make_cell_chaos_events(ctx.world))
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
	# this.chaos.warnRemaining, CellStage.ts:397).
	warnDriftT = chaos.warn_remaining()
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
				"title": tr("%s is extinct") % ex["name"],
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

	# chaos (TS CellStage.ts:418)
	update_chaos(dt)

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
		# defensive ordering deviation (QC r3, synthesis 4E): the death penalty
		# lands BEFORE the hook dispatch — a throwing listener must not eat the
		# loss. TS pays after the dispatch (its hooks are plain calls today);
		# natively _fire callv's the hook directly, so one bad future listener
		# would otherwise skip the DNA loss, its toast and the chaos bump.
		# A listener now observes the post-penalty dna — accepted (defensive).
		var lost := floori(float(ctx.dna) * 0.12 + 0.5)  # JS Math.round
		ctx.add_dna(-lost)
		# R7: the toast names the creature (the display name is data — it
		# interpolates outside tr; the "," is typography, the R2 chip precedent)
		_fire("hud_toast", ["%s, %s %d DNA" % [ctx.get_display_name(), tr("You died — lost"), lost],
				"bad", "💀"])
		ctx.add_chaos(0.03)
		_fire("context_event", ["playerDeath", "cell"])  # storyteller signal
		_fire("audio_play", ["die", 0.8, 0.0])
		_fire("cam_shake", [10.0, 0.5])
		_fx_burst(px, py, 30, [_hsl(float(ctx.genome["hue"]), 0.7, 0.6), "#ff8a9a"],
				{"speed": 160.0, "ttl": 1.0})
		# R4: the debrief commit — the DNA bill this path just computed rides
		# to the stage layer (the cause came with the killing blow's note)
		_fire("death_debrief", ["", "", lost])
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


# ---- chaos -----------------------------------------------------------------------

## TS CellStage.ts:418-447 — chaos.update with the full ctx and hooks. The
## storyteller reference arrives through hooks (get_gap_bias / get_mood /
## get_warn_scale Callables — the sim stays decoupled from the object); when
## absent they read the storyteller's neutral defaults (gap 1.0, mood "test",
## warnScale 1.0).
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
		if String(def["id"]) == "glitch":
			ctx.add_dna(40.0, "glitch tribute")
			_fire("hud_toast", [tr("The Glitch pays tribute: +40 DNA"), "reward", "🌀"])
		# mirror_rule: an event that survived once may queue its mirror return
		mirrorLedger.maybe_queue(rng, String(def["id"]), "bloom")
	chaos.update(dt, self, {
		"chaos": float(ctx.chaos), "karma": float(ctx.karma), "stageTime": time,
		"gapMult": ctx.chaos_gap_mult() * gap_bias,
		"mood": mood,
		"warnScale": warn_scale,  # bio_tell bucket
		"mirrors": mirrorLedger.queued(),  # mirror_rule returns
	}, {
		"onWarn": on_warn,
		"onApply": on_apply,
		"onEnd": on_end,
	})


## C1 deck rebuild (TS onEnter, CellStage.ts:221-224): a CONTINUE/NEW LIFE
## landing on a different world rebuilds the deck. The scene layer calls this
## on enter; headless tests call it directly. Returns true on a rebuild.
func ensure_deck(world_seed: int) -> bool:
	if world_seed == deckSeed:
		return false
	chaos = ChaosScript.new(rng.branch(), CellEventsScript.make_cell_chaos_events(ctx.world))
	deckSeed = world_seed
	return true


## TS hasActiveChaos(): the ACTIVE-phase set only — a warn-phase event does
## not count (the gaia_wanderer offer gate reads this, game.ts:396).
func has_active_chaos() -> bool:
	return chaos.active_events().size() > 0


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
					# R4: the killing blow names its killer for the stage-side
					# debrief (UI-side recording — no sim state; the A-B dump
					# contract). The species id resolves to the bestiary name
					# in the stage's hook handler.
					if php <= 0.0 and not deathStarted:
						_fire("death_debrief", ["cell_bite", String(e["speciesId"]), -1])
				_fx_burst(px, py, 4, ["#ff8a9a"], {"speed": 90.0, "ttl": 0.4, "size": 2.0})

	# vent healing (never rescues a dying cell)
	if php > 0.0 and not deathStarted:
		for z in zones:
			if z["kind"] == "vent" \
					and Vector2(px, py).distance_to(Vector2(z["x"], z["y"])) < float(z["r"]):
				php = minf(pmaxHp, php + float(z.get("heal", 0.0)) * dt)


func kill_ent(e: Dictionary) -> void:
	_tide_valid = false  # drop_corpse may revive/refound the tide line
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
		if _flat_live:
			_pel_mirror_append(pellets[pellets.size() - 1])
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
			_gcache.erase(String(e["speciesId"]))  # the bump must reach later same-species ents this tick
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


## Port 1:1 — TS CellStage.ts updateEnts(dt) (~743-933): the hp<=0 death
## sweep (tagged killEnt payment, else green burst), lifespan expiry,
## cooldown/stun decay, then per-ent AI — panic > hunt > flee > graze —
## separation, accel/current/drag/cap integration, world containment, inline
## pellet eating and toxin-zone damage. Reverse iteration with mid-loop
## removals is TS-verbatim; ent identity uses eid (GDScript Dictionary ==
## compares by content — eid is the unique `o === e` proxy). RNG draw sites,
## in TS evaluation order: (1) the sweep's green burst — 8 particles × 5
## draws via _fx_burst, only when lastPlayerHit is empty; (2) the tagged
## sweep path draws inside kill_ent; (3) the graze wanderT re-roll —
## range(1.5, 4) first, then (only when no pellet target) next() +
## range(60, 320); the pellet-seek loop itself draws nothing. Every other
## branch is draw-free.
func update_ents(dt: float) -> void:
	_flat_rebuild()
	var stunDrag := exp(-3.0 * dt)  # constant per call — same value per ent
	var entDrag := exp(-2.4 * dt)
	var i: int = ents.size() - 1
	while i >= 0:
		var e: Dictionary = ents[i]
		if float(e["hp"]) <= 0.0:
			# contact/drain/tagged toxin deaths pay like a bite (kill_ent marks
			# hp = -1; the bite branch guards e.hp > 0 so no double-pay)
			if String(e["lastPlayerHit"]) != "":
				kill_ent(e)
				e["lastPlayerHit"] = ""  # no stale-tag leaks into chaos deaths
			else:
				_fx_burst(float(e["x"]), float(e["y"]), 8,
						["#9fff9f", "#8fff4f"], {"speed": 80.0, "ttl": 0.6})
			ents.remove_at(i)
			_exs.remove_at(i)
			_eys.remove_at(i)
			_ehps.remove_at(i)
			_esizes.remove_at(i)
			_eeids.remove_at(i)
			_ecellx.remove_at(i)
			_ecelly.remove_at(i)
			_eg_dirty = true  # index space shifted; next gather rebuilds
			i -= 1
			continue
		if e.has("lifespan"):
			e["lifespan"] = float(e["lifespan"]) - dt
			if float(e["lifespan"]) <= 0.0:
				ents.remove_at(i)
				_exs.remove_at(i)
				_eys.remove_at(i)
				_ehps.remove_at(i)
				_esizes.remove_at(i)
				_eeids.remove_at(i)
				_eg_dirty = true  # index space shifted; next gather rebuilds
				i -= 1
				continue
		e["hurtT"] = maxf(0.0, float(e["hurtT"]) - dt * 3.0)
		e["eatT"] = maxf(0.0, float(e["eatT"]) - dt * 2.0)
		e["biteCd"] = maxf(0.0, float(e["biteCd"]) - dt)
		e["pressCd"] = maxf(0.0, float(e.get("pressCd", 0.0)) - dt)
		e["stun"] = maxf(0.0, float(e["stun"]) - dt)

		if float(e["stun"]) > 0.0:
			e["vx"] = float(e["vx"]) * stunDrag
			e["vy"] = float(e["vy"]) * stunDrag
			e["x"] = float(e["x"]) + float(e["vx"]) * dt
			e["y"] = float(e["y"]) + float(e["vy"]) * dt
			_exs[i] = float(e["x"])
			_eys[i] = float(e["y"])
			if floori(_exs[i] / _eg_cell) != int(_ecellx[i]) or floori(_eys[i] / _eg_cell) != int(_ecelly[i]):
				_ent_cell_sync(i)
			i -= 1
			continue

		# ---- AI ------------------------------------------------------------------
		# hoists: values invariant across the tick's ent loop (the player's
		# genome/stats and the ent's own identity fields) — same reads, once
		# per tick instead of once per ent
		if _first_ai:
			_p_size = float(ctx.genome["size"])
			_p_damage = float(pStats["damage"])
			_first_ai = false
		var myEid: int = _eeids[i]
		var isSwarm := bool(e.get("swarm", false))
		var eSize: float = _esizes[i]
		var eEx: float = _exs[i]
		var eEy: float = _eys[i]
		var ddx: float = eEx - px
		var ddy: float = eEy - py
		# f64 distance — SANCTIONED divergence (controller I5): the
		# pre-optimization Vector2 form computed in f32 (a parity wart vs
		# TS's f64 vecDist); this form is TS-closer. Residual threshold-flip
		# deltas vs the pre-optimization build are part of the sanctioned
		# class — see PARITY-M2.md §17.
		var dPlayer := sqrt(ddx * ddx + ddy * ddy)
		var vision: float = _evision[i]
		var iAmBigger: bool = eSize > _p_size * 1.05 \
				or (_edmg[i] > _p_damage and eSize > 1.2)

		# temperament_bands: per-species seeded band on the aggression/fear reads
		var band_v: Variant = e.get("band")
		var aggr := 1.0
		var fear := 1.0
		if band_v is Dictionary:
			aggr = float((band_v as Dictionary).get("aggression", 1.0))
			fear = float((band_v as Dictionary).get("fear", 1.0))
		# kin_memory: a grudging kin-tag network shifts from fleeing to pressing
		# (effectiveGrudge hits the harassment valve — capped networks rest).
		# Cached per species; the two mid-tick mutations of the read fields
		# (register_press's harass bump, kill_ent's grudge bump) invalidate
		# their entry — the original re-read eco.grudge_of per ent, which the
		# cache reproduces exactly.
		var sid: String = String(e["speciesId"])
		var grudge: float
		if _gcache.has(sid):
			grudge = _gcache[sid]
		else:
			grudge = eco.grudge_of(ctx.world, sid)
			_gcache[sid] = grudge
		var grudgePress: bool = grudge >= 2.0 and dPlayer < vision * 0.9
		# corpse_tide: the scavenger line harasses far above its weight
		# (cached per tick — kill_ent invalidates; see the member note)
		if not _tide_valid:
			_tide = eco.tide_species()
			_tide_valid = true
		var tideBold: bool = _tide != null and String(_tide["id"]) == sid
		var diet: String = String(e["genome"]["diet"])
		var hunting: bool = isSwarm \
				or (diet != "herbivore"
					and dPlayer < vision * 0.65 * aggr and iAmBigger) \
				or grudgePress \
				or (tideBold and dPlayer < vision * 0.5)
		var fleeing: bool = not isSwarm and grudge < 2.0 \
				and dPlayer < vision * 0.7 * fear and not iAmBigger
		# bio_tell: during a warn window the ambient panics away from the strike
		# epicenter (the player's position) — herds visibly leave. The panic
		# overrides hunt/flee/wander for the window; a fixed pace keeps the
		# vacate rate near the catalog's 40-60% band.
		var panicking: bool = warnDriftT > 0.0 and not isSwarm \
				and dPlayer < 500.0  # the event footprint (vents/meteor land ≤500 out)
		var ax := 0.0
		var ay := 0.0
		var speed: float = _espeed[i]

		if panicking:
			# the drift is positional — a deterministic pace that does not drown
			# in the accel/drag pipeline (~115px per 2.4s window → ~half of an
			# area-uniform zone vacates, the catalog's 40-60% band)
			var pd: float = maxf(1.0, dPlayer)
			e["x"] = float(e["x"]) + ((float(e["x"]) - px) / pd) * 48.0 * dt
			e["y"] = float(e["y"]) + ((float(e["y"]) - py) / pd) * 48.0 * dt
			_exs[i] = float(e["x"])
			_eys[i] = float(e["y"])
			if floori(_exs[i] / _eg_cell) != int(_ecellx[i]) or floori(_eys[i] / _eg_cell) != int(_ecelly[i]):
				_ent_cell_sync(i)
			# the drift moved THIS ent — the downstream sections (separation,
			# eat, toxin zones) must see the post-drift position the way the
			# pre-optimization code did (it read e["x"]/e["y"] live)
			eEx = float(e["x"])
			eEy = float(e["y"])
			ax = 0.0
			ay = 0.0
			speed = minf(speed, 45.0)
		elif hunting:
			# grudge presses count toward the harassment valve (one per engagement)
			if grudgePress and float(e.get("pressCd", 0.0)) <= 0.0:
				eco.register_press(ctx.world, sid)
				e["pressCd"] = PRESS_COOLDOWN
				# the press moved the valve — later ents of this species must
				# read the new grudge (the original re-read it per ent)
				_gcache[sid] = eco.grudge_of(ctx.world, sid)
			# chase player (or nearby smaller ent)
			var tx: float = px
			var ty: float = py
			if not isSwarm:
				# prefer smaller cells nearby (single pass, squared distances)
				var hBest := -1
				var hBestD2: float = vision * vision
				for oj in ents.size():
					if _eeids[oj] == myEid or _ehps[oj] <= 0.0:
						continue
					if _esizes[oj] >= eSize * 0.85:
						continue
					var odx: float = _exs[oj] - eEx
					var ody: float = _eys[oj] - eEy
					var d2: float = odx * odx + ody * ody
					if d2 < hBestD2:
						hBest = oj
						hBestD2 = d2
				if hBest >= 0:
					tx = _exs[hBest]
					ty = _eys[hBest]
			var hx: float = tx - eEx
			var hy: float = ty - eEy
			var hd: float = maxf(1.0, sqrt(hx * hx + hy * hy))
			ax = hx / hd
			ay = hy / hd
			speed *= 1.25 if isSwarm else 1.0
		elif fleeing:
			var fd: float = maxf(1.0, dPlayer)
			ax = (float(e["x"]) - px) / fd
			ay = (float(e["y"]) - py) / fd
			# fleeing prey is capped vs the player's ACHIEVABLE speed (accel/2.6
			# drag terminal), not the stat sheet — the stat-sheet cap preserved
			# absolute gaps and froze honest chases at ~268px forever
			speed = minf(speed * 0.95, (float(pStats["accel"]) / 2.6) * 0.85)
		else:
			# graze / wander
			e["wanderT"] = float(e["wanderT"]) - dt
			if float(e["wanderT"]) <= 0.0:
				e["wanderT"] = rng.range(1.5, 4.0)
				# seek pellets if herbivore-ish
				var gBest := -1
				var bd: float = 300.0
				if _pg_dirty:
					_rebuild_pg()
				_cand.clear()
				if grid_gather:
					_grid_near(_pg_seek, eEx, eEy, 301.0, _cand)
					if _cand.size() > 1:
						_cand.sort()  # tie-break order = full-scan order
				else:
					for pj3 in pellets.size():
						_cand.append(pj3)
				for gi in _cand.size():
					var pj: int = _cand[gi]
					if _pdead[pj] == 1:
						continue
					var wd: float = Vector2(_pxs[pj], _pys[pj]).distance_to(Vector2(eEx, eEy))
					var want: bool = (_pk[pj] == 1) if diet == "carnivore" else (_pk[pj] == 0)
					if wd < bd and want:
						gBest = pj
						bd = wd
				if gBest >= 0:
					e["tx"] = _pxs[gBest]
					e["ty"] = _pys[gBest]
				else:
					var wa: float = rng.next() * TAU
					var wr: float = rng.range(60.0, 320.0)
					e["tx"] = float(e["x"]) + cos(wa) * wr
					e["ty"] = float(e["y"]) + sin(wa) * wr
			var gx: float = float(e["tx"]) - float(e["x"])
			var gy: float = float(e["ty"]) - float(e["y"])
			var gd: float = sqrt(gx * gx + gy * gy)
			if gd > 10.0:
				ax = gx / gd
				ay = gy / gd
				speed *= 0.55

		# separation from big crowding
		if _eg_dirty:
			_rebuild_eg()
		_cand.clear()
		if grid_gather:
			_grid_near(_eg, eEx, eEy, _eg_cell, _cand)
			if _cand.size() > 1:
				_cand.sort()  # reproduce the full scan's ascending order
		else:
			for oj in ents.size():
				_cand.append(oj)
		for oi in _cand.size():
			var oj: int = _cand[oi]
			if _eeids[oj] == myEid:
				continue
			var sdx: float = eEx - _exs[oj]
			var sdy: float = eEy - _eys[oj]
			var sd2: float = sdx * sdx + sdy * sdy
			var minD: float = 14.0 * (eSize + _esizes[oj])
			if sd2 < minD * minD and sd2 > 0.01:
				var sd: float = sqrt(sd2)
				ax += (sdx / sd) * 0.6
				ay += (sdy / sd) * 0.6

		# locals carry the integration (same ops on the same values in the
		# same order as the dict round-trips they replace — bit-exact)
		var al: float = sqrt(ax * ax + ay * ay)
		var nvx: float = float(e["vx"])
		var nvy: float = float(e["vy"])
		if al > 0.0:
			nvx += (ax / al) * _eaccel[i] * dt
			nvy += (ay / al) * _eaccel[i] * dt
		nvx += current_at(float(e["y"])) * dt
		nvx *= entDrag
		nvy *= entDrag
		var sp := sqrt(nvx * nvx + nvy * nvy)
		if sp > speed:
			nvx = nvx * speed / sp
			nvy = nvy * speed / sp
		var nx: float = float(e["x"]) + nvx * dt
		var ny: float = float(e["y"]) + nvy * dt
		e["x"] = nx
		e["y"] = ny
		e["vx"] = nvx
		e["vy"] = nvy
		_exs[i] = nx
		_eys[i] = ny
		if floori(nx / _eg_cell) != int(_ecellx[i]) or floori(ny / _eg_cell) != int(_ecelly[i]):
			_ent_cell_sync(i)

		# ents stay in world
		var dO: float = sqrt(nx * nx + ny * ny)
		if dO > WORLD_R + 100.0:
			e["vx"] = nvx - (nx / dO) * 40.0 * dt * 10.0
			e["vy"] = nvy - (ny / dO) * 40.0 * dt * 10.0

		# eat pellets (inline squared distances — hot loop, no allocations).
		# Eats mark _pdead instead of splicing so the grids' indices stay
		# stable; the tick-end compaction performs the physical removal
		# (order-preserving — identical survivor array to splice-as-you-go).
		# NO candidate sort: every in-range qualifying pellet is eaten and the
		# capped heal is order-independent, so the gather order can't matter.
		# The A-B harness caught this loop reading the pre-integration hoist —
		# the original reads e["x"]/e["y"] LIVE here (post-integration), so
		# gather + distance use nx/ny, the values just written above.
		var eatR: float = 14.0 * eSize + 5.0
		var eatR2: float = eatR * eatR
		if _pg_dirty:
			_rebuild_pg()
		_cand.clear()
		if grid_gather:
			_grid_near(_pg_eat, nx, ny, _pg_cell, _cand)
		else:
			for pj2 in pellets.size():
				_cand.append(pj2)
		var ci := _cand.size() - 1
		while ci >= 0:
			var pj: int = _cand[ci]
			if _pdead[pj] == 0:
				var pdx: float = _pxs[pj] - nx
				var pdy: float = _pys[pj] - ny
				if pdx * pdx + pdy * pdy < eatR2:
					var kindOk: bool = (_pk[pj] == 1) if diet == "carnivore" else (_pk[pj] == 0)
					if kindOk or diet == "omnivore":
						_pdead[pj] = 1
						e["hp"] = minf(float(e["maxHp"]), float(e["hp"]) + 4.0)
						_ehps[i] = float(e["hp"])
						e["eatT"] = 1.0
			ci -= 1

		# toxin zones hurt ents (flat zone snapshot — zones are constant
		# during update_ents; the inline distance is (b-a).length() verbatim).
		# f64 distance — SANCTIONED divergence (I5), same class as dPlayer.
		for zi in _zn:
			var zdx: float = _zxs[zi] - float(e["x"])
			var zdy: float = _zys[zi] - float(e["y"])
			if _ztoxin[zi] and sqrt(zdx * zdx + zdy * zdy) < _zr[zi]:
				e["hp"] = float(e["hp"]) - _zdps[zi] * dt
				_ehps[i] = float(e["hp"])
				e["hurtT"] = maxf(float(e["hurtT"]), 0.2)
				if _zmine[zi]:
					e["lastPlayerHit"] = "toxin"
		# hp<=0 here is swept by the top-of-loop check next pass (kill_ent
		# already paid if the kill was tagged)
		i -= 1
	# tick-end pellet compaction: physically remove this tick's dead (eaten)
	# pellets — order-preserving, so the survivor array is identical to the
	# original splice-as-you-go; flat mirrors rebuild at the next entry
	var dead := 0
	for pj in _pdead.size():
		if _pdead[pj] == 1:
			dead += 1
	if dead > 0:
		var kept: Array[Dictionary] = []
		kept.resize(pellets.size() - dead)
		var w := 0
		for pj in pellets.size():
			if _pdead[pj] == 0:
				kept[w] = pellets[pj]
				w += 1
		pellets = kept
	_flat_live = false


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
	if _flat_live:
		_pel_mirror_append(pellets[pellets.size() - 1])
	if pellets.size() > PELLET_CAP:
		pellets.pop_front()  # TS shift()
		if _flat_live:
			_pxs.remove_at(0)
			_pys.remove_at(0)
			_pk.remove_at(0)
			_pdead.remove_at(0)


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
	if _flat_live:
		_exs.append(float(e["x"]))
		_eys.append(float(e["y"]))
		_ehps.append(float(e["hp"]))
		_esizes.append(float(genome.get("size", 1)))
		_eeids.append(int(e["eid"]))
		_ecellx.append(0)
		_ecelly.append(0)  # placeholders — the dirty rebuild derives real cells
		_eg_dirty = true  # index space shifted; next gather rebuilds
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


# ---- flat read-mirrors (update_ents inner scans) --------------------------------

## Rebuild the mirrors from the live arrays. Called at update_ents entry —
## cross-function mutations (update_player bites, chaos spawns, meteor) land
## before this point, so only mutations made INSIDE update_ents need mirrors.
func _flat_rebuild() -> void:
	var n := ents.size()
	_exs.resize(n)
	_eys.resize(n)
	_ehps.resize(n)
	_esizes.resize(n)
	_eeids.resize(n)
	_evision.resize(n)
	_edmg.resize(n)
	_espeed.resize(n)
	_eaccel.resize(n)
	for j in n:
		var e: Dictionary = ents[j]
		_exs[j] = float(e["x"])
		_eys[j] = float(e["y"])
		_ehps[j] = float(e["hp"])
		_esizes[j] = float(e["genome"]["size"])
		_eeids[j] = int(e["eid"])
		var st: Dictionary = e["stats"]
		_evision[j] = 340.0 * float(st["vision"])
		_edmg[j] = float(st["damage"])
		_espeed[j] = float(st["speed"])
		_eaccel[j] = float(st["accel"])
	var np := pellets.size()
	_pxs.resize(np)
	_pys.resize(np)
	_pk.resize(np)
	_pdead.resize(np)
	_pdead.fill(0)
	for j in np:
		var p: Dictionary = pellets[j]
		_pxs[j] = float(p["x"])
		_pys[j] = float(p["y"])
		_pk[j] = _kind_code(String(p["kind"]))
	_flat_live = true
	_rebuild_eg()
	_rebuild_pg()
	_first_ai = true
	_gcache.clear()
	_tide = null
	_tide_valid = false
	_zn = zones.size()
	_zxs.resize(_zn)
	_zys.resize(_zn)
	_zr.resize(_zn)
	_zdps.resize(_zn)
	_ztoxin.resize(_zn)
	_zmine.resize(_zn)
	for zj in _zn:
		var z: Dictionary = zones[zj]
		_zxs[zj] = float(z["x"])
		_zys[zj] = float(z["y"])
		_zr[zj] = float(z["r"])
		_zdps[zj] = float(z["dps"])
		_ztoxin[zj] = 1 if String(z["kind"]) == "toxin" else 0
		_zmine[zj] = 1 if bool(z.get("mine", false)) else 0


func _kind_code(kind: String) -> int:
	return 1 if kind == "meat" else (0 if kind == "plant" else 2)


func _pel_mirror_append(p: Dictionary) -> void:
	_pxs.append(float(p["x"]))
	_pys.append(float(p["y"]))
	_pk.append(_kind_code(String(p["kind"])))
	_pdead.append(0)
	_pg_dirty = true


## Insert index j into grid g at the cell (x, y) lands in. Packed buckets are
## copy-on-write — the mutated bucket is written back.
func _grid_add(g: Dictionary, x: float, y: float, cell: float, j: int) -> void:
	var ck := Vector2i(floori(x / cell), floori(y / cell))
	var b: Variant = g.get(ck)
	if b == null:
		g[ck] = PackedInt32Array([j])
	else:
		var bucket: PackedInt32Array = b
		bucket.append(j)
		g[ck] = bucket


## Append every candidate index in the 3×3 cell neighborhood of (x, y) to out
## (unsorted — order-sensitive callers sort ascending to reproduce the full
## scan's order; the eat gather needs no sort, see the eat loop).
func _grid_near(g: Dictionary, x: float, y: float, cell: float, out: PackedInt32Array) -> void:
	var cx := floori(x / cell)
	var cy := floori(y / cell)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var b: Variant = g.get(Vector2i(cx + dx, cy + dy))
			if b != null:
				out.append_array(b)


## Keep ent i's bucket membership on its LIVE cell — called after every
## position write. Without this, an ent drifting across a cell boundary mid
## tick would sit in a stale bucket while the gather centers on live
## positions, and a within-minD candidate could be missed (the ent grid is
## the only one that needs this: pellets never move during update_ents).
func _ent_cell_sync(i: int) -> void:
	if _eg_dirty:
		return  # pending wholesale rebuild — the sync would be discarded
	var ck := Vector2i(floori(_exs[i] / _eg_cell), floori(_eys[i] / _eg_cell))
	if ck.x == int(_ecellx[i]) and ck.y == int(_ecelly[i]):
		return
	var old := Vector2i(int(_ecellx[i]), int(_ecelly[i]))
	var b: Variant = _eg.get(old)
	if b != null:
		var bucket: PackedInt32Array = b
		var k := bucket.find(i)
		if k >= 0:
			bucket.remove_at(k)
			_eg[old] = bucket
	var nb: Variant = _eg.get(ck)
	if nb == null:
		_eg[ck] = PackedInt32Array([i])
	else:
		var nbucket: PackedInt32Array = nb
		nbucket.append(i)
		_eg[ck] = nbucket
	_ecellx[i] = ck.x
	_ecelly[i] = ck.y


## Rebuild the ent grid (also after any ent removal/append — indices shift).
func _rebuild_eg() -> void:
	_eg.clear()
	var n := ents.size()
	_eg_cell = 29.0
	for j in n:
		if 28.0 * _esizes[j] + 1.0 > _eg_cell:
			_eg_cell = 28.0 * _esizes[j] + 1.0
	_ecellx.resize(n)
	_ecelly.resize(n)
	for j in n:
		_grid_add(_eg, _exs[j], _eys[j], _eg_cell, j)
		_ecellx[j] = floori(_exs[j] / _eg_cell)
		_ecelly[j] = floori(_eys[j] / _eg_cell)
	_eg_dirty = false


## Rebuild both pellet grids (also after any pellet append/remove).
func _rebuild_pg() -> void:
	_pg_eat.clear()
	_pg_seek.clear()
	var maxS := 1.0
	for j in _esizes.size():
		if _esizes[j] > maxS:
			maxS = _esizes[j]
	_pg_cell = 14.0 * maxS + 6.0
	for pj in pellets.size():
		_grid_add(_pg_eat, _pxs[pj], _pys[pj], _pg_cell, pj)
		_grid_add(_pg_seek, _pxs[pj], _pys[pj], 301.0, pj)
	_pg_dirty = false


# ---- chaos event helpers (called by cell_events.gd — the cellEvents.ts
# apply/tick/end bodies). TS CellStage.ts:1203-1381, ported 1:1; audio and
# camera effects route through the hooks.

## TS CellStage.ts:1203 — meteorTarget ring, r 150, ttl 2.5.
func spawn_meteor_target(x: float, y: float) -> void:
	zones.append({"x": x, "y": y, "r": 150.0, "kind": "meteorTarget", "ttl": 2.5,
			"dps": 0.0, "pulse": 0.0})


## TS CellStage.ts:1207 — boom/shake/damage ring + DNA debris.
func meteor_impact(x: float, y: float) -> void:
	_fire("audio_play", ["boom", 1.0, 0.0])
	_fire("cam_shake", [14.0, 0.8])
	_fx_burst(x, y, 50, ["#ffd08a", "#ff8a5a", "#fff"],
			{"speed": 320.0, "ttl": 1.0, "size": 3.4})
	_fire("fx_spawn", [{"x": x, "y": y, "kind": "ring", "ttl": 0.8, "size": 30.0,
			"grow": 3.0, "color": "rgba(255,220,150,0.9)"}])
	# damage everything near
	for e in ents:
		var d: float = Vector2(e["x"], e["y"]).distance_to(Vector2(x, y))
		if d < 200.0:
			e["hp"] = float(e["hp"]) - 60.0 * (1.0 - d / 200.0)
			e["hurtT"] = 1.0
			if float(e["hp"]) <= 0.0:
				kill_ent(e)
	var dp: float = Vector2(px, py).distance_to(Vector2(x, y))
	if dp < 200.0 and invuln <= 0.0:
		php -= 45.0 * (1.0 - dp / 200.0)
		hurtT = 1.0
		# R4: a blast kill notes its cause for the stage-side debrief
		if php <= 0.0 and not deathStarted:
			_fire("death_debrief", ["cell_meteor", "", -1])
	# DNA debris
	for i in 6:
		var a: float = rng.next() * TAU
		pellets.append({
			"x": x + cos(a) * rng.range(10.0, 90.0),
			"y": y + sin(a) * rng.range(10.0, 90.0),
			"vx": 0.0, "vy": 0.0, "kind": "dna", "ttl": 45.0, "val": 12,
		})
	ctx.add_chaos(0.04)


## TS CellStage.ts:1239 — toxin zone push (redtide / toxin_clouds).
func add_toxin_zone(x: float, y: float, r: float, dps: float, ttl: float,
		source: String = "redtide") -> void:
	zones.append({"x": x, "y": y, "r": r, "kind": "toxin", "ttl": ttl, "dps": dps,
			"pulse": 0.0, "source": source})


## Chaos variant (toxin_clouds): the drifting clouds lean toward warm bodies.
## TS CellStage.ts:1244.
func drift_toxin_clouds(dt: float) -> void:
	for z in zones:
		# minor 1: only the variant's own clouds home the player — the baseline
		# red tide keeps its static zones (cross-event coupling broke dodges)
		if String(z["kind"]) != "toxin" or bool(z.get("mine", false)) \
				or String(z.get("source", "")) != "clouds":
			continue
		var d: float = maxf(1.0, Vector2(z["x"], z["y"]).distance_to(Vector2(px, py)))
		if d > 60.0:
			z["x"] = float(z["x"]) + ((px - float(z["x"])) / d) * 14.0 * dt
			z["y"] = float(z["y"]) + ((py - float(z["y"])) / d) * 14.0 * dt


## Chaos variant (algae_surge): the bloom runs away with the ocean — flora
## slams the cap and the wild grazers boom on the windfall. TS
## CellStage.ts:1259.
func algae_surge() -> void:
	bloom()
	for sp in eco.living():
		if String(sp["genome"]["diet"]) == "herbivore" \
				and not bool(sp.get("kin", false)):
			sp["pop"] = minf(90.0, float(sp["pop"]) * 1.8 + 3.0)
	for i in 20:
		var a: float = rng.next() * TAU
		var d: float = rng.range(100.0, 700.0)
		pellets.append({
			"x": px + cos(a) * d, "y": py + sin(a) * d,
			"vx": 0.0, "vy": 0.0, "kind": "plant", "ttl": 60.0, "val": 2,
		})


## Bounded: vents cool into cold seeps after a few minutes. TS
## CellStage.ts:1274 — cap 6, FIFO.
func add_vent(x: float, y: float) -> void:
	var vents: Array = []
	for z in zones:
		if z["kind"] == "vent":
			vents.append(z)
	if vents.size() >= 6:
		var idx: int = zones.find(vents[0])
		if idx >= 0:
			zones.remove_at(idx)
	zones.append({"x": x, "y": y, "r": 80.0, "kind": "vent", "ttl": 240.0,
			"dps": 0.0, "heal": 6.0, "pulse": rng.range(0.0, 9.0)})


## TS CellStage.ts:1281 — flora surge + 30 plant pellets.
func bloom() -> void:
	eco.flora = minf(eco.flora_cap, eco.flora * 1.9 + 20.0)
	for i in 30:
		var a: float = rng.next() * TAU
		var d: float = rng.range(100.0, 700.0)
		pellets.append({
			"x": px + cos(a) * d, "y": py + sin(a) * d,
			"vx": rng.range(-10.0, 10.0), "vy": rng.range(-10.0, 10.0),
			"kind": "plant", "ttl": 60.0, "val": 2,
		})


## mirror_rule (bloom's mirror face): exactly ONE rule inverted — the flora
## direction turns on itself; the pellet sprinkle is identical.
## TS CellStage.ts:1296.
func blight() -> void:
	eco.flora = maxf(12.0, eco.flora * 0.35)
	for i in 30:
		var a: float = rng.next() * TAU
		var d: float = rng.range(100.0, 700.0)
		pellets.append({
			"x": px + cos(a) * d, "y": py + sin(a) * d,
			"vx": rng.range(-10.0, 10.0), "vy": rng.range(-10.0, 10.0),
			"kind": "plant", "ttl": 60.0, "val": 2,
		})


## Chaos event: four mutant hunters ring the player. TS CellStage.ts:1326.
func spawn_swarm() -> void:
	var base: Dictionary = GenomeScript.clone_genome(ctx.genome)
	base.merge({"size": 0.62, "diet": "carnivore", "jaw": 1, "flagella": 3,
			"spikes": 1, "hue": 350, "pattern": "stripes"}, true)
	var g: Dictionary = MutationScript.mutate(base, rng, 0.1)
	for i in 4:
		var a: float = (float(i) / 7.0) * TAU
		spawn_ent(null, px + cos(a) * 620.0, py + sin(a) * 620.0, g,
				{"swarm": true, "lifespan": 30})


## TS CellStage.ts:1335 — the Old One: max(2.0, player*1.6), jaw 5, lifespan 26.
func spawn_big_brother() -> Variant:
	var base: Dictionary = GenomeScript.clone_genome(ctx.genome)
	base.merge({"size": maxf(2.0, float(ctx.genome.get("size", 1.0)) * 1.6),
			"diet": "carnivore", "jaw": 5, "flagella": 4, "spikes": 4, "hue": 285,
			"pattern": "glow", "eyes": 4}, true)
	var g: Dictionary = MutationScript.mutate(base, rng, 0.05)
	var a: float = rng.next() * TAU
	var e: Dictionary = spawn_ent(null, px + cos(a) * 900.0, py + sin(a) * 900.0, g,
			{"lifespan": 26})
	_fire("hud_toast", [tr("SOMETHING HUGE has noticed you"), "bad", "👁"])
	return e


## Chaos event: several species visibly mutate; mutants spawn near player.
## TS CellStage.ts:1367.
func spawn_mutant_wave() -> int:
	var pool: Array = []
	for sp in eco.living():
		if not bool(sp.get("kin", false)):
			pool.append(sp)
	if pool.is_empty():
		return 0
	var count: int = 2 + floori(rng.next() * 2.0)
	for i in count:
		var sp: Variant = rng.pick(pool)
		if sp == null:
			break
		var mutant: Dictionary = MutationScript.mutate(sp["genome"], rng, 0.85)
		var a: float = rng.next() * TAU
		spawn_ent(null, px + cos(a) * rng.range(400.0, 700.0),
				py + sin(a) * rng.range(400.0, 700.0), mutant, {"lifespan": 40})
		# QC r6: compose through the split keys the TS VI object ships
		# ('A mutant' / 'crawls out of the noise') — composed raw it was an
		# orphan-key miss. EN output is byte-identical.
		_fire("hud_toast", ["%s %s %s" % [tr("A mutant"), String(sp["name"]),
				tr("crawls out of the noise")], "chaos", "🧪"])
	ctx.add_chaos(0.02)
	return count


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
