## TRIBE STAGE sim core — the RTS-lite village as a headless RefCounted: state
## structs, constructor world-seeding, onEnter semantics (restore / re-found /
## pack conversion), the chief (movement, role hotkeys, hut/totem actions,
## raid-touch death + respawn), tribesman AI (fight / job / arrive), the
## economy (deliveries, regrow, saplings, hut build/repair/recruit, totem
## progress, festival passive) and popCap. Port of Spore
## src/game/tribe/TribeStage.ts (frozen), minus the render pass and the
## scene-only surfaces (camera, fx pools, HUD abilities/objective draw,
## cursor hover — scene layer, tasks 4-5).
##
## Architecture (M4, same as creature_sim.gd): TribeSim.new(ctx, rng_branch,
## hooks) —
##   ctx        the M1 GameContext; sim calls ctx methods directly
##   rng_branch the stage's dedicated Rng (the CALLER draws ctx.rng.branch(),
##              mirroring TS `this.rng = game.context.rng.branch()`)
##   hooks      Dictionary of Callables for every scene/audio effect; missing
##              key = silent no-op so tests can record selectively. Keys used
##              here: hud_toast(text, kind, icon), hud_banner(data),
##              audio_play(name, vol, pan), audio_set_mood(name),
##              hud_toast_inset(px), hud_show_objective(text), cam_shake(m,d),
##              fx_burst(x, y, n, opts), fx_spawn(opts),
##              context_event(ev, from_stage), go_to(stage, data),
##              save_all(). Task 3 adds: hud_float_world(x, y, text, color,
##              size), get_gap_bias(), get_mood(), get_warn_scale(),
##              storyteller_note_chaos_event(playtime) — the storyteller seam
##              rides hooks like creature_sim (neutral defaults when absent).
## No Input singleton reads: update(dt, inp) takes an input SNAPSHOT
## Dictionary (mx/my/wx/wy/down/clicked/take_click/keys_held/keys_pressed —
## keys_pressed canonical) the scene layer builds and tests construct
## literally. HUD-rect clicks are dispatched in update (TS:284-303) — the sim
## owns the rects (hudRects, the stage re-positions them each frame) and
## consumes a click by setting inp["take_click"] = true (TS inp.takeClick();
## the snapshot is by-reference, the scene reads the flag back).
## Documented debug seam surface (bot parity law's exception list):
## debug_state() (read) + debug_grant(food, wood) (the task-6 bot's
## stockpile cheat for the REAL hut/totem button clicks — see below).
## World/entity dicts keep the TS camelCase field names verbatim; the
## `stats` dicts carry the M1 stats.gd shape (snake_case keys — the
## established compute_creature_stats port surface).
##
## M4 task-2 scope: the rival war machine + hazards + the two stage
## transitions — the raid clock (TS:327-339), launchRivalRaid (TS:561-584),
## the rival-warrior field block (TS:656-707, landed in task 1) now closes
## with the war_graves combo (TS:709-717), the camp assault (TS:858-879),
## the beast lifecycle (TS:881-935 + spawn/despawn TS:1004-1021), fires +
## ignite_tree + lightning_strike (TS:937-993), the raidsBlocked /
## pauseRaids / launchRivalRaidNow chaos seam (TS:1023-1039 — landed with
## the raid machine it belongs to; task 3's event defs call it), and the
## fall/victory paths (TS:381-409) firing the go_to/save_all hooks.
## Task-3 scope (this revision): the chaos deck (tribe_events.gd — 5 baseline
## + 4 gated defs, tribeEvents.ts:10-155) + the scheduler wiring
## (TS:341-369, via update_chaos) + the festival / festivalMirror / starShower
## bodies (TS:1041-1084, deferred by task 2).
## Still deferred (tasks 4-6): the scene layer (render/camera/HUD abilities),
## the stage-side hook bindings, bot + flow.
##
## Recorded divergences (parity-pin ledger):
##  - TS `this.tribe.indexOf(t) % 2` (wood quota, TribeStage.ts:763) —
##    GDScript Array.indexOf deep-compares Dictionaries; the port threads the
##    loop index into tribe_job_ai (same element, exact index).
##  - Corrupt packGenomes member with a truthy non-object genome
##    (TS:185): the TS spread `{ ...defaultGenome(), ...item.genome }` no-ops
##    on a number and spawns a default-genome founder; the port matches
##    (default genome). A FALSY genome (missing/null) takes the mutateLike
##    branch in both. A valid-but-non-array packGenomes JSON made TS count
##    NaN → 0 founders (TS:181); the port reads it as an empty pack
##    (minimum 3) instead.
##  - restore_state's per-hut pop/buildT (TS:231) read `Math.max(0, x ?? 0)`:
##    TS Math.max/min COERCE numeric strings ("50"→50) where the port reads
##    the fallback; non-numeric strings NaN the TS read and fall back in the
##    port (hyper-corrupt edge — JSON cannot carry NaN).
##  - mutate_like is ported locally (TS:1426-1431): the M2 mutation.gd
##    `mutate` is a different rate/bias operator, not this shape.
##  - The chief hut-proximity heal is a TS noop (TS:487-491, `dna += 0`) —
##    ported as a comment, no loop (the loop draws nothing).
##  - Cursor hover over hudRects (TS:285-289 setCursor) is scene-side.
##  - fx_burst replays the TS Particles.burst rng draws in-stream
##    (gfx/particles.ts:70-84) and embeds them under opts["parts"] — the
##    creature_sim M2 pattern, kept bit-identical here.
##  - The chaos scheduler is constructed at the TS stream position (the
##    branch draw happens in _init/on_enter, TS:135/142); make_tribe_chaos_events
##    draws nothing (weights are Callables; mirror_bucket owns a private
##    stream), so the stage stream is final at construction. The storm's two
##    former Math.random sites ride seeded streams — see the tribe_events.gd
##    header DIVERGENCE note.
##  - lightning_strike's TS duck-type `'speciesId' in t || !('wood' in t)`
##    (TribeStage.ts:979): speciesId exists on neither tree nor hut dicts,
##    so the branch reduces to "no wood field" = hut — ported as the
##    explicit `has("wood")` key check with a comment at the site.
##  - raidsBlocked / pauseRaids / launchRivalRaidNow (TS:1023-1039) landed
##    with task 2 (they are the raid machine's chaos seam); task 3's event
##    defs call them — no task-2 code path does.
##  - firstRaidHint truthiness (TS:334 `!ctx.flags.firstRaidHint`) ports via
##    the JS-truthiness helper _truthy (the flag may hold any saved value).
class_name TribeSim
extends RefCounted

const StatsScript := preload("res://src/evo/stats.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const ChaosScript := preload("res://src/game/chaos.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const TribeEventsScript := preload("res://src/game/tribe/tribe_events.gd")

const Z_TO_Y := 0.62    # pseudo-depth squash (TribeStage.ts:21)
const Z_MIN := -200.0
const Z_MAX := 240.0
const WORLD_HALF := 2400.0  # creature 2700 — per-stage constant (plan constraint)

## TS hud.showObjective on both onEnter paths (TribeStage.ts:164/190).
const OBJECTIVE_LINE := "GATHER · BUILD · SURVIVE — raise the Great Totem"


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

# stockpile (TS:62-63)
var food := 60.0
var wood := 30.0

# player wanderer — you are still a creature, the chief (TS:66-71)
var px := 0.0
var pz := 60.0
var pvx := 0.0
var pvz := 0.0
var facing := 1
var gait := 0.0
var speed01 := 0.0
var chiefStats: Dictionary = {}

# world rosters (TS:73-79) — TS-optional hut field `recruitT` stays ABSENT
# until the economy writes it (undefined semantics; readers use .get())
var tribe: Array = []            # Tribesman dicts
var huts: Array = []             # {x, z, hp, maxHp, pop, buildT, recruitT?}
var trees: Array = []            # {x, z, wood, burn, seed}
var bushes: Array = []           # {x, z, food, regrow}
var fires: Array = []            # {x, z, ttl, spread} (TS:52)
var rivalWarriors: Array = []    # {x, z, vx, vz, hp, genome, gait, facing, state}
var rivals: Array = []           # {x, z, hp, anger, name}

var time := 0.0
var dayPhase := 0.2              # TS:82
# TS ChaosScheduler<TribeStage> (private `chaos` + getter in TS; GDScript
# keeps one public field). Constructed in _init at the TS stream position;
# the tribe deck arrives with tribe_events.gd (task 3).
var chaos: Variant = null
## TS deckSeed (C1: decks rebuilt from a stale WorldGenome) — on_enter
## compares and rebuilds.
var deckSeed := -1
var raidTimer := 75.0            # TS:88
## war_graves: true while a raid's war party is in the field (TS:91) —
## consumed by the war_graves combo at the update_tribesmen tail.
var raidActive := false
var deathFade := 0.0             # TS:92
# TS:93 — totem as a dict (progress/active ride the persist blob camelCase)
var totem: Dictionary = {"progress": 0.0, "active": false}
var fallenT := 0.0               # TS:94
var fallFired := false           # TS:95
var victoryFired := false        # TS:96
var invulnT := 0.0               # TS:97
var lastDeathCause := ""         # TS:98
var victoryT := 0.0              # TS:99
var deathHandled := false        # TS:420
var hutCd := 0.0                 # TS:524
var saplingT := 60.0             # TS:969
var beast: Variant = null        # TS:996 {x, z, hp, genome} | null
## TS:998 — the stage clock; drained by update() (fn ALWAYS runs after removal).
var timers: Array = []           # {left: float, fn: Callable}
## TS:276 — {action: "hut"|"totem", r: {x, y, w, h}}; the scene layer
## re-positions the rects each frame, the sim hit-tests + dispatches.
var hudRects: Array = []
## mirror_rule state (minor 14) — the shared MirrorLedger (task 3 consumes).
var mirrorLedger := ChaosScript.MirrorLedger.new()


func _init(ctx_v: Variant, rng_branch: Variant, hooks: Dictionary = {}) -> void:
	ctx = ctx_v
	rng = rng_branch
	_hooks = hooks
	chiefStats = StatsScript.compute_creature_stats(ctx.genome)

	# world resources (TS:107-118 — draw order sacred: x, z, wood, seed)
	for i in 30:
		trees.append({
			"x": rng.range(-WORLD_HALF, WORLD_HALF),
			"z": rng.range(Z_MIN, Z_MAX),
			"wood": rng.range(4.0, 9.0),
			"burn": 0.0,
			"seed": rng.range(0.0, 9.0),
		})
	for i in 26:
		bushes.append({
			"x": rng.range(-WORLD_HALF, WORLD_HALF),
			"z": rng.range(Z_MIN, Z_MAX),
			"food": rng.range(3.0, 7.0),
			"regrow": 0.0,
		})

	# starting hut + people from pack (the pack converts in on_enter, TS:121)
	huts.append({"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0, "pop": 0.0, "buildT": 0.0})

	# rival tribes far away (TS:124-133 — the names array holds a third entry
	# the loop never reaches; the ?? fallback ports verbatim)
	var names: Array = ["Gnash", "Ruk", "Ooka"]
	for i in 2:
		rivals.append({
			"x": (-1.0 if i == 0 else 1.0) * rng.range(1300.0, 2000.0),
			"z": rng.range(-120.0, 160.0),
			"hp": 100.0,
			"anger": 0.0,
			"name": names[i] if i < names.size() else "Rival",
		})

	# TS:135 — the chaos deck. The branch draw is at the TS stream position
	# (after trees/bushes/rivals); the factory folds ctx.world in and draws
	# nothing itself, so the stream is final here.
	chaos = ChaosScript.new(rng.branch(), TribeEventsScript.make_tribe_chaos_events(ctx.world))
	deckSeed = int(ctx.world["seed"])


# ---- enter / exit / persist ---------------------------------------------------------

## TS onEnter (TribeStage.ts:139-191), minus the pure scene surfaces —
## audio.setMood / hud.toastInset / hud.showObjective fire hooks the stage
## binds (task 4-5).
func on_enter() -> void:
	# C1: a CONTINUE/NEW LIFE landing on a different world rebuilds the deck
	if int(ctx.world["seed"]) != deckSeed:
		chaos = ChaosScript.new(rng.branch(),
				TribeEventsScript.make_tribe_chaos_events(ctx.world))
		deckSeed = int(ctx.world["seed"])
	_fire("audio_set_mood", ["tribe"])  # TS:146
	chiefStats = StatsScript.compute_creature_stats(ctx.genome)  # TS:147
	# re-founding after a collapse must not inherit the old fall timer —
	# a rebuilt village bounced straight back to 'BACK TO THE WILDS'
	fallenT = 0.0          # TS:150
	fallFired = false      # TS:151
	victoryFired = false   # TS:152
	deathHandled = false   # TS:153
	_fire("hud_toast_inset", [190])  # TS:154 — clears the stockpile panel + buttons
	deathFade = 0.0        # TS:155
	lastDeathCause = ""    # TS:156
	# reload ambushes: CONTINUE dropped the chief next to live raiders with
	# no grace and a stale death fade
	invulnT = 3.0          # TS:159

	# a saved village restores as it stood (food/wood/huts/totem/people);
	# without one, the creature pack founds it (first arrival)
	if restore_state():    # TS:163
		_fire("hud_show_objective", [OBJECTIVE_LINE])  # TS:164
		return
	# a RE-FOUNDED village must not be hutless with popCap 1 — give it the
	# same fresh-start the constructor gives a new instance (TS:169-173)
	if huts.is_empty():
		huts.append({"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0, "pop": 0.0, "buildT": 0.0})
		food = 60.0
		wood = 30.0

	# convert pack genomes into tribesmen (once, TS:176-189)
	if tribe.is_empty():
		var raw_flag: Variant = ctx.flags.get("packGenomes")
		var pack_list: Array = []
		if raw_flag is String:
			var parsed: Variant = JSON.parse_string(raw_flag)
			if parsed is Array:
				pack_list = parsed
			# TS try/catch swallows parse failures → empty pack. A valid
			# NON-array parse made TS count NaN → 0 founders; the port reads
			# it as an empty pack (see header divergence note).
		var count: int = maxi(3, pack_list.size())
		for i in count:
			var item: Variant = pack_list[i] if i < pack_list.size() else null
			var genome_v: Variant = item.get("genome") if item is Dictionary else null
			var g: Dictionary
			if _truthy(genome_v):
				# clampGenome, not clone-only — a corrupt pack genome (NaN
				# genes) used to produce founders with NaN stats that crashed
				# every frame (TS:183-185)
				if genome_v is Dictionary:
					var merged: Dictionary = GenomeScript.default_genome()
					merged.merge(genome_v, true)
					g = GenomeScript.clamp_genome(merged)
				else:
					# TS spread of a truthy non-object no-ops → default genome
					g = GenomeScript.clamp_genome(GenomeScript.default_genome())
			else:
				g = mutate_like(ctx.genome)
			add_tribesman(g, "gather")
		ctx.flags["packGenomes"] = "[]"  # TS:188
	_fire("hud_show_objective", [OBJECTIVE_LINE])  # TS:190


func on_exit() -> void:
	persist_state()  # TS:193


## Snapshot village progress into flags — mid-stage CONTINUE used to
## silently restart the stage (TS:195-210).
func persist_state() -> void:
	# never write a corpse — the fall path deletes the blob and saveAll()
	# used to immediately re-write the empty village over the delete (TS:200)
	if fallenT > 0.0 and tribe.is_empty() and huts.is_empty():
		return
	var huts_list: Array = []
	for h in huts:
		huts_list.append({
			"x": h["x"], "z": h["z"], "hp": h["hp"],
			"maxHp": h["maxHp"], "pop": h["pop"], "buildT": h["buildT"],
		})
	var tribe_list: Array = []
	for t in tribe:
		tribe_list.append({"genome": t["genome"], "role": t["role"]})
	var blob: Dictionary = {
		"food": food,
		"wood": wood,
		"huts": huts_list,
		"totemProg": float(totem["progress"]),
		"totemActive": bool(totem["active"]),
		"tribe": tribe_list,
	}
	ctx.flags["tribeState"] = JSON.stringify(blob)  # TS:209


func restore_state() -> bool:
	var raw: Variant = ctx.flags.get("tribeState")
	if not (raw is String) or (raw as String).is_empty():
		return false  # TS:215 — no blob
	# TS try/catch — a parse failure reads as "no blob" (TS:243)
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return false
	var b: Dictionary = parsed
	# non-finite food/wood → reject the blob (TS:222; Number.isFinite("50")
	# is false in TS — a string fails here the same way)
	var food_v: Variant = b.get("food")
	var wood_v: Variant = b.get("wood")
	if not _fin(food_v) or not _fin(wood_v):
		return false
	var blob_huts: Array = []
	if b.get("huts") is Array:
		blob_huts = b["huts"]
	# an EMPTY village (huts 0 + tribe 0) is a corpse — the fall path used
	# to write it and every FOUND TRIBE resurrected the dead blob (TS:226)
	var blob_tribe: Variant = b.get("tribe")
	var has_tribe: bool = (blob_tribe is Array) and not (blob_tribe as Array).is_empty()
	if blob_huts.is_empty() and not has_tribe:
		return false
	food = maxf(0.0, float(food_v))   # TS:227
	wood = maxf(0.0, float(wood_v))   # TS:228
	huts = []
	for h_v in blob_huts:
		if not (h_v is Dictionary):
			continue
		var h: Dictionary = h_v
		var hx: Variant = h.get("x")
		var hz: Variant = h.get("z")
		var hh: Variant = h.get("hp")
		var hm: Variant = h.get("maxHp")
		# TS:230 — huts with any non-finite anchor are dropped
		if not (_fin(hx) and _fin(hz) and _fin(hh) and _fin(hm)):
			continue
		huts.append({
			"x": float(hx), "z": float(hz),
			"hp": maxf(1.0, float(hh)), "maxHp": maxf(1.0, float(hm)),
			"pop": maxf(0.0, _fin_or(h.get("pop"), 0.0)),
			"buildT": maxf(0.0, _fin_or(h.get("buildT"), 0.0)),
		})
	var prog := _fin_or(b.get("totemProg"), 0.0)
	var act: Variant = b.get("totemActive")
	totem = {"progress": clampf(prog, 0.0, 100.0), "active": act is bool and act}  # TS:232
	# REPLACE, not append — the stage instance survives quit->CONTINUE in
	# the same session, and pushing onto the live roster doubled the
	# village every cycle (3->6->12->24 measured) (TS:236)
	tribe = []
	if has_tribe:
		var cap_n: int = maxi(12, huts.size() * 3 + 1)  # TS:238
		var src: Array = blob_tribe
		var n: int = mini(src.size(), cap_n)
		for i in n:
			var t_v: Variant = src[i]
			if t_v == null:
				# TS throws on a null member mid-restore (t.genome) — the
				# catch returns false with food/wood/huts/totem already
				# applied (partial state, TS-true)
				return false
			var role_v := "gather"
			var genome_v: Variant = null
			if t_v is Dictionary:
				genome_v = t_v.get("genome")
				var r: Variant = t_v.get("role")
				if r is String and (r == "hunt" or r == "warrior"):
					role_v = r  # TS:239 role sanitize
			# else: a non-object member spreads nothing in TS (t.genome is
			# undefined) → default genome, gather role
			var g: Dictionary
			if genome_v is Dictionary:
				var merged: Dictionary = GenomeScript.default_genome()
				merged.merge(genome_v, true)
				g = GenomeScript.clamp_genome(merged)
			else:
				g = GenomeScript.clamp_genome(GenomeScript.default_genome())
			add_tribesman(g, role_v)
	return true  # TS:242


func add_tribesman(genome: Dictionary, role_v: String) -> void:
	# TS:246-270 — draw order sacred: x, z, gait, gaitSeed
	var stats: Dictionary = StatsScript.compute_creature_stats(genome)
	tribe.append({
		"genome": genome,
		"x": rng.range(-60.0, 60.0),
		"z": rng.range(40.0, 120.0),
		"vx": 0.0, "vz": 0.0,
		"hp": float(stats["max_hp"]),
		"maxHp": float(stats["max_hp"]),
		"stats": stats,
		"facing": 1,
		"gait": rng.range(0.0, 6.0),
		"speed01": 0.0,
		"role": role_v,
		"carrying": null,
		"targetX": 0.0, "targetZ": 0.0,
		"hasTarget": false,
		"attack": 0.0,
		"hurtT": 0.0,
		"eatT": 0.0,
		"mood": "idle",
		"gaitSeed": rng.range(0.0, 100.0),
		"retargetT": 0.0,
	})


func pop_cap() -> int:
	# TS:272 — built huts × 3 + 1
	var built := 0
	for h in huts:
		if float(h["buildT"]) <= 0.0:
			built += 1
	return built * 3 + 1


# ---- update -------------------------------------------------------------------------

## inp: input SNAPSHOT Dictionary — mx, my, wx, wy, down, clicked,
## take_click (pre-taken flag), keys_held: Array[String],
## keys_pressed: Array[String]. The scene layer builds it; tests construct
## it literally. The sim never touches the Input singleton.
## TS update (TribeStage.ts:278-418) minus the scene surfaces — camera
## follow, fx pool steps and hud.setAbilities (task 4). The timers drain and
## the chaos.update call both run at their TS stream positions.
func update(dt: float, inp: Dictionary) -> void:
	time += dt
	dayPhase = fmod(dayPhase + dt / 240.0, 1.0)  # TS:282 — 240 s day (tribe flavor)

	# HUD panel clicks (dispatched in update, like every other UI, TS:284-303);
	# the hover setCursor is scene-side. A consumed click sets the snapshot's
	# take_click flag (TS inp.takeClick() — by-reference snapshot).
	var mx: float = float(inp.get("mx", 0.0))
	var my: float = float(inp.get("my", 0.0))
	if bool(inp.get("clicked", false)) and not bool(inp.get("take_click", false)):
		for b in hudRects:
			var r: Dictionary = b["r"]
			if mx >= float(r["x"]) and mx <= float(r["x"]) + float(r["w"]) \
					and my >= float(r["y"]) and my <= float(r["y"]) + float(r["h"]):
				inp["take_click"] = true
				_fire("audio_play", ["click", 1.0, 0.0])
				if String(b["action"]) == "hut":
					try_build_hut()
				else:
					try_totem()
				break

	# stage timers (TS:306-313) — splice then call: the fn ALWAYS runs after
	# removal (the volcano-timer seam the M3 review verified)
	for ti in range(timers.size() - 1, -1, -1):
		var t: Dictionary = timers[ti]
		t["left"] = float(t["left"]) - dt
		if float(t["left"]) <= 0.0:
			timers.remove_at(ti)
			var fn: Callable = t["fn"]
			fn.call()

	if deathFade > 0.0:
		handle_chief_death(dt)  # TS:315

	update_chief(dt, inp)      # TS:317
	update_tribesmen(dt)       # TS:318 (includes the rival-warrior field block)
	update_rival_warriors(dt)  # TS:319 — the camp assault
	update_beast(dt)           # TS:320
	update_fires(dt)           # TS:321
	update_economy(dt)         # TS:322

	# raid clock — peaceful villages get slower, smaller raids and no
	# raids before the first hut stands (a 3-person camp was one raid
	# from the spiral on the calmest difficulty) (TS:327-339)
	invulnT = maxf(0.0, invulnT - dt)
	raidTimer -= dt
	var peaceful: bool = ctx.difficulty == "peaceful"
	if peaceful and huts.is_empty():
		raidTimer = maxf(raidTimer, 30.0)
	if raidTimer <= 0.0 and (not peaceful or not huts.is_empty()):
		raidTimer = 80.0 + rng.range(-15.0, 25.0)
		if peaceful:
			raidTimer += 40.0  # half cadence
		if not _truthy(ctx.flags.get("firstRaidHint")):
			ctx.flags["firstRaidHint"] = "seen"
			_fire("hud_toast", [tr("Raiders rally beyond the ridge — press 3 to arm warriors!"),
					"bad", "⚔️"])
		launch_rival_raid()

	update_chaos(dt)  # TS:341-369

	# the tribe has fallen: offer the walk back to the wilds instead of limbo
	# (TS:381-398) — the transitions ride the go_to/save_all hooks (the sim
	# cannot see the game)
	if tribe.is_empty() and huts.is_empty() and fallenT == 0.0:
		fallenT = 0.0001
		_fire("hud_banner", [{"title": "THE TRIBE HAS FALLEN",
				"subtitle": "the wilds take you back — stronger", "kind": "danger", "ttl": 6}])
		_fire("audio_play", ["die", 1.0, 0.0])
	if fallenT > 0.0:
		fallenT += dt
		if fallenT > 4.0 and not fallFired:
			fallFired = true  # latch — fired every tick otherwise (~33 saves, double cards)
			# delete the DEAD village blob — restoreState resurrected it on every
			# FOUND TRIBE and the village re-fell 4s later (3 bounces measured,
			# slot bricked until NEW LIFE)
			ctx.flags.erase("tribeState")
			_fire("save_all", [])
			_fire("go_to", ["creature", {
				"title": "BACK TO THE WILDS",
				"sub": "gather your strength and found a new people",
			}])

	# victory: totem complete (TS:400-409)
	if float(totem["progress"]) >= 100.0:
		victoryT += dt
		if victoryT > 2.5 and not victoryFired:
			victoryFired = true  # latch
			_fire("save_all", [])
			_fire("audio_play", ["ascend", 1.0, 0.0])
			_fire("go_to", ["civ", {
				"title": "THE FIRST CITY",
				"sub": "drums become laws; laws become empires",
			}])

	# camera follow + cam.toWorld setWorld + fx pool steps + hud.setAbilities
	# — scene-side (task 4)


## Stage-time timer (TS after(), TribeStage.ts:998-1002).
func after(seconds: float, fn: Callable) -> void:
	timers.append({"left": seconds, "fn": fn})


## TS despawnBeast (TribeStage.ts:1004-1010) — the chaos beast event's
## withdrawal seam (task 3 calls it).
func despawn_beast() -> void:
	if beast != null:
		_fx_burst(float(beast["x"]), float(beast["z"]) * Z_TO_Y, 18,
				["#c9a4ff", "#9fd8ff"], {"speed": 120.0, "ttl": 0.9})
		beast = null
		_fire("hud_toast", [tr("The great beast wanders away…"), "good", "🌿"])


## TS spawnBeast (TribeStage.ts:1012-1021) — the chaos beast event's seam.
func spawn_beast() -> void:
	var g: Dictionary = GenomeScript.clone_genome(ctx.genome)
	g["size"] = 2.1
	g["diet"] = "carnivore"
	g["jaw"] = 5.0
	g["spikes"] = 4.0
	g["horns"] = 3.0
	g["hue"] = 300.0
	g["coat"] = "plates"
	g["eyes"] = 4.0
	var a: float = rng.next() * TAU
	beast = {
		"x": px + cos(a) * 900.0,
		"z": clampf(pz + sin(a) * 300.0, Z_MIN, Z_MAX),
		"hp": 420.0,
		"genome": g,
	}


## TS handleChiefDeath (TribeStage.ts:422-454).
func handle_chief_death(dt: float) -> void:
	deathFade += dt
	if not deathHandled:
		deathHandled = true
		_fire("context_event", ["playerDeath", "tribe"])  # storyteller signal (TS:426)
		_fire("audio_play", ["die", 0.9, 0.0])            # TS:427
		var lost := roundi(float(ctx.dna) * 0.15)         # TS:428 Math.round
		ctx.add_dna(float(-lost))
		var cause := ""
		if lastDeathCause != "":
			cause = " — %s" % tr(lastDeathCause)
		_fire("hud_toast", ["%s %d DNA%s" % [tr("The chief fell — lost"), lost, cause],
				"bad", "💀"])  # TS:430
		lastDeathCause = ""                               # TS:431
	if deathFade > 1.6:
		deathFade = 0.0
		deathHandled = false
		# respawn at the safest sampled point (farthest from beast + raiders)
		var bx := 0.0
		var bz := 80.0
		var best_d := -1.0
		for i in 8:
			var cx: float = rng.range(-WORLD_HALF * 0.5, WORLD_HALF * 0.5)
			var cz: float = rng.range(Z_MIN + 30.0, Z_MAX - 30.0)
			var min_d := INF
			if beast != null:
				min_d = minf(min_d, _vdist(float(beast["x"]), float(beast["z"]), cx, cz))
			for w in rivalWarriors:
				min_d = minf(min_d, _vdist(float(w["x"]), float(w["z"]), cx, cz))
			for f in fires:
				min_d = minf(min_d, _vdist(float(f["x"]), float(f["z"]), cx, cz))
			if min_d == INF:
				min_d = 9999.0  # TS:445 — empty-field fallback
			if min_d > best_d:  # strict `>`: ties keep the EARLIEST sample (TS-stable)
				best_d = min_d
				bx = cx
				bz = cz
		px = bx
		pz = bz
		# QC round-2 B3 feedback: the safest sample can drop the chief ~1900 px
		# from camp with no pointer home (walkback 35-50 s, measured by the
		# tribe-edge probe). Pure feedback — the sampling above is TS:437-445
		# verbatim, no mechanic change. QC r3 (synthesis 4D): the 1200 band
		# missed real respawns — tribe-edge measured home_d 1178.6 and 1017
		# with no hint through 10-15 s of walking; 900 covers the band.
		var home: Variant = nearest_hut({"x": px, "z": pz})
		if home != null and _vdist(float(home["x"]), float(home["z"]), px, pz) > 900.0:
			_fire("hud_toast", [tr("Your chief is far — walk back"), "info", "🧭"])
		# brief grace — re-death within ~2s of respawn costed double 15% taxes
		invulnT = 3.0
		# death already taxes 15% DNA — permanently removing a tribesman too
		# made every chief respawn a double loss (measured by A08)


## TS updateChief (TribeStage.ts:456-516) — the input arrives via the snapshot.
func update_chief(dt: float, inp: Dictionary) -> void:
	var held: Array = inp.get("keys_held", [])
	var pressed: Array = inp.get("keys_pressed", [])
	var wx: float = float(inp.get("wx", 0.0))
	var wy: float = float(inp.get("wy", 0.0))
	var dx := 0.0
	var dz := 0.0
	if bool(inp.get("down", false)):
		# invert projection: screenY = z * Z_TO_Y -> z = wy / Z_TO_Y (TS:461)
		var tz: float = clampf(wy / Z_TO_Y, Z_MIN, Z_MAX)
		dx = wx - px
		dz = tz - pz
		if absf(dx) < 12.0:  # deadzone 12 (creature uses 10 — tribe flavor)
			dx = 0.0
		if absf(dz) < 12.0:
			dz = 0.0
	if held.has("KeyW"):
		dz -= 1.0
	if held.has("KeyS"):
		dz += 1.0
	if held.has("KeyA"):
		dx -= 1.0
	if held.has("KeyD"):
		dx += 1.0
	var dl: float = sqrt(dx * dx + dz * dz)
	if dl > 0.0:
		dx /= dl
		dz /= dl
		facing = 1 if dx > 0.0 else -1

	var s: Dictionary = chiefStats
	pvx += dx * float(s["accel"]) * dt            # TS:475
	pvz += dz * float(s["accel"]) * 0.8 * dt      # TS:476 — vz accel ×0.8
	var drag: float = exp(-6.0 * dt)              # TS:477
	pvx *= drag
	pvz *= drag
	var sp: float = sqrt(pvx * pvx + pvz * pvz)
	if sp > float(s["speed"]):
		pvx *= float(s["speed"]) / sp
		pvz *= float(s["speed"]) / sp
	px += pvx * dt
	pz = clampf(pz + pvz * dt, Z_MIN, Z_MAX)      # TS:482 — px unclamped (TS-true)
	speed01 = minf(1.0, sp / maxf(1.0, float(s["speed"])))
	gait += dt * (3.0 + speed01 * 9.0)

	# chief heals near huts — TS noop (TribeStage.ts:487-491, `dna += 0`;
	# the loop draws nothing, so a comment carries it)

	hutCd = maxf(0.0, hutCd - dt)                 # TS:493
	# role hotkeys (TS:495-497)
	if pressed.has("Digit1"):
		assign_role("gather")
	if pressed.has("Digit2"):
		assign_role("hunt")
	if pressed.has("Digit3"):
		assign_role("warrior")

	# build hut (R) / totem (T) (TS:500-502)
	if pressed.has("KeyR"):
		try_build_hut()
	if pressed.has("KeyT"):
		try_totem()

	# rival raid on chief? (TS:504-515)
	for w in rivalWarriors:
		if _vdist(float(w["x"]), float(w["z"]), px, pz) < 40.0:
			w["state"] = "fight"
			# TS `rng.chance(dt * 2) && deathFade <= 0 && invulnT <= 0` — the
			# roll is FIRST in the && chain, so the draw happens regardless
			# of the gates (stream parity)
			if rng.chance(dt * 2.0) and deathFade <= 0.0 and invulnT <= 0.0:
				deathFade = 0.0001
				deathHandled = false
				lastDeathCause = "raiders cut you down"
				_fire("cam_shake", [4.0, 0.3])


## TS assignRole (TribeStage.ts:518-522).
func assign_role(role_v: String) -> void:
	for t in tribe:
		t["role"] = role_v
	_fire("audio_play", ["click", 1.0, 0.0])
	_fire("hud_toast", ["Everyone: %s" % role_v, "info", "📣"])


## TS tryBuildHut (TribeStage.ts:526-541).
func try_build_hut() -> void:
	if deathFade > 0.0:
		return
	if hutCd > 0.0:
		return
	# wood check BEFORE arming the cooldown — the guaranteed first failure
	# (start 30 wood) used to burn the cooldown and eat the timed retry
	if wood < 40.0:
		_fire("hud_toast", [tr("Need 40 wood for a hut"), "bad", "🪵"])
		return
	hutCd = 2.0
	wood -= 40.0
	huts.append({
		"x": px + rng.range(-50.0, 50.0),
		"z": clampf(pz + 30.0, Z_MIN, Z_MAX),
		"hp": 100.0, "maxHp": 100.0, "pop": 0.0, "buildT": 6.0,
	})
	_fire("audio_play", ["build", 0.9, 0.0])
	_fx_burst(px, pz * Z_TO_Y, 14, ["#d8c8a8", "#a88d68"], {"speed": 90.0, "ttl": 0.7})
	_fire("hud_toast", [tr("Hut construction started"), "good", "🏠"])


## TS tryTotem (TribeStage.ts:543-559).
func try_totem() -> void:
	if bool(totem["active"]):
		return
	if tribe.is_empty():
		_fire("hud_toast", [tr("No one left to raise the totem — keep your people alive"),
				"bad", "🗿"])
		return
	if food < 100.0 or wood < 80.0:
		# TS:550 — the have-template is NOT translate-wrapped there
		_fire("hud_toast", ["Totem needs 100 food + 80 wood (have %d/%d)"
				% [roundi(food), roundi(wood)], "bad", "🗿"])
		return
	food -= 100.0
	wood -= 80.0
	totem["active"] = true
	totem["progress"] = 0.0
	_fire("audio_play", ["levelup", 0.9, 0.0])
	_fire("hud_banner", [{
		"title": "THE GREAT TOTEM", "subtitle": "your people carve the sky",
		"kind": "reward",
	}])


## TS launchRivalRaid (TribeStage.ts:561-584).
func launch_rival_raid() -> void:
	var rival: Variant = rng.pick(rivals)
	if float(rival["hp"]) <= 0.0:
		return
	# cap the war party — raid stacking smothered small villages
	var alive := rivalWarriors.size()
	if alive >= 5:
		return
	var wave := 1 if ctx.difficulty == "peaceful" else 2
	var n: int = mini(wave + floori(rng.range(0.0, 2.0)), 5 - alive)
	for i_w in n:
		var g: Dictionary = GenomeScript.clone_genome(ctx.genome)
		g["hue"] = 5.0
		g["diet"] = "carnivore"
		g["spikes"] = 3.0
		g["jaw"] = 3.0
		rivalWarriors.append({
			"x": float(rival["x"]) + rng.range(-60.0, 60.0),
			"z": float(rival["z"]) + rng.range(-40.0, 40.0),
			"vx": 0.0, "vz": 0.0,
			"hp": 60.0,
			"genome": g,
			"gait": 0.0,
			"facing": 1,
			"state": "march",
		})
	_fire("hud_banner", [{
		"title": "%s RAIDS!" % String(rival["name"]).to_upper(),
		"subtitle": "defend the huts", "kind": "danger",
	}])
	_fire("audio_play", ["alarm", 0.9, 0.0])
	raidActive = true


# ---- tribesmen ----------------------------------------------------------------------

## TS updateTribesmen (TribeStage.ts:586-718) — the rival-warrior field
## block (656-707) closes with the war_graves combo (709-717).
func update_tribesmen(dt: float) -> void:
	for i in range(tribe.size() - 1, -1, -1):
		var t: Dictionary = tribe[i]
		t["hurtT"] = maxf(0.0, float(t["hurtT"]) - dt * 3.0)   # TS:594
		t["attack"] = maxf(0.0, float(t["attack"]) - dt * 2.0)  # TS:595
		t["eatT"] = maxf(0.0, float(t["eatT"]) - dt * 2.0)      # TS:596

		# fight rival warriors nearby (hunters a bit, warriors hard)
		var fought := false
		for w in rivalWarriors:
			var d: float = _vdist(float(w["x"]), float(w["z"]), float(t["x"]), float(t["z"]))
			if d < 44.0:
				fought = true
				var power: float = 1.6 if String(t["role"]) == "warrior" \
						else (1.0 if String(t["role"]) == "hunt" else 0.5)  # TS:604
				w["hp"] = float(w["hp"]) - 22.0 * power * dt
				t["attack"] = 1.0
				if rng.chance(dt * 1.2):
					t["hp"] = float(t["hp"]) - 10.0
					t["hurtT"] = 0.6
				if rng.chance(dt * 8.0):
					_fx_burst((float(t["x"]) + float(w["x"])) / 2.0,
							(float(t["z"]) + float(w["z"])) * Z_TO_Y, 4,
							["#ffcf8a", "#ff9a8a"], {"speed": 80.0, "ttl": 0.4})

		if fought:
			t["mood"] = "angry"
			# stand ground
			t["vx"] = float(t["vx"]) * exp(-4.0 * dt)
			t["vz"] = float(t["vz"]) * exp(-4.0 * dt)
		else:
			# TS:623 — the wood-quota parity read uses indexOf(t); GDScript
			# dictionaries deep-compare, so the loop index is threaded instead
			tribe_job_ai(t, dt, i)

		# move toward target
		if bool(t["hasTarget"]) and not fought:
			var mdx: float = float(t["targetX"]) - float(t["x"])
			var mdz: float = float(t["targetZ"]) - float(t["z"])
			var md: float = sqrt(mdx * mdx + mdz * mdz)
			if md > 12.0:
				t["vx"] = float(t["vx"]) + (mdx / md) * 260.0 * dt  # TS:631 — x accel 260
				t["vz"] = float(t["vz"]) + (mdz / md) * 208.0 * dt  # TS:632 — z accel 208 (TS quirk)
				t["facing"] = 1 if mdx > 0.0 else -1
			else:
				t["hasTarget"] = false
		var drag: float = exp(-5.5 * dt)
		t["vx"] = float(t["vx"]) * drag
		t["vz"] = float(t["vz"]) * drag
		var spd: float = sqrt(float(t["vx"]) * float(t["vx"]) + float(t["vz"]) * float(t["vz"]))
		var cap: float = float(t["stats"]["speed"]) * 0.8
		if spd > cap:
			t["vx"] = float(t["vx"]) * cap / spd
			t["vz"] = float(t["vz"]) * cap / spd
		t["x"] = float(t["x"]) + float(t["vx"]) * dt
		t["z"] = clampf(float(t["z"]) + float(t["vz"]) * dt, Z_MIN, Z_MAX)
		t["speed01"] = minf(1.0, spd / maxf(1.0, cap))
		t["gait"] = float(t["gait"]) + dt * (3.0 + float(t["speed01"]) * 9.0)

		if float(t["hp"]) <= 0.0:
			tribe.remove_at(i)
			_fx_burst(float(t["x"]), float(t["z"]) * Z_TO_Y, 16,
					["#ff9a8a", _hsl(float(t["genome"]["hue"]), 0.7, 0.5)],
					{"speed": 130.0, "ttl": 0.8})
			_fire("hud_toast", [tr("A tribesman has fallen…"), "bad", "🪦"])

	# rival warriors fight back, retreat when broken (TS:656-707)
	var wi: int = rivalWarriors.size() - 1
	while wi >= 0:
		var w: Dictionary = rivalWarriors[wi]
		if float(w["hp"]) <= 0.0:
			rivalWarriors.remove_at(wi)
			food += 8.0
			_fx_burst(float(w["x"]), float(w["z"]) * Z_TO_Y, 12, ["#ff9a8a"],
					{"speed": 110.0, "ttl": 0.7})
			wi -= 1
			continue
		# nearest BUILT hut (unbuilt huts are not siege targets, TS:664)
		var nearest_hut_v: Variant = _nearest_built_hut(float(w["x"]), float(w["z"]))
		# with no standing huts the raid hunts the nearest tribesman instead
		# of idling toward the map origin (pop-1 villages were untouchable)
		var near_t: Variant = null
		if nearest_hut_v == null and not tribe.is_empty():
			near_t = _nearest_by(tribe, float(w["x"]), float(w["z"]))
		var tx: float
		var tz: float
		if String(w["state"]) == "flee":
			tx = float(rivals[0]["x"]) if not rivals.is_empty() else 0.0
			tz = float(rivals[0]["z"]) if not rivals.is_empty() else 0.0
		else:
			tx = float(nearest_hut_v["x"]) if nearest_hut_v != null \
					else (float(near_t["x"]) if near_t != null else 0.0)
			tz = float(nearest_hut_v["z"]) if nearest_hut_v != null \
					else (float(near_t["z"]) if near_t != null else 80.0)
		var dx: float = tx - float(w["x"])
		var dz: float = tz - float(w["z"])
		var d: float = maxf(1.0, sqrt(dx * dx + dz * dz))
		w["vx"] = float(w["vx"]) + (dx / d) * 240.0 * dt
		w["vz"] = float(w["vz"]) + (dz / d) * 190.0 * dt
		w["facing"] = 1 if dx > 0.0 else -1
		var wdrag: float = exp(-5.0 * dt)
		w["vx"] = float(w["vx"]) * wdrag
		w["vz"] = float(w["vz"]) * wdrag
		w["x"] = float(w["x"]) + float(w["vx"]) * dt
		w["z"] = clampf(float(w["z"]) + float(w["vz"]) * dt, Z_MIN, Z_MAX)
		w["gait"] = float(w["gait"]) + dt * 8.0
		# damage hut
		if nearest_hut_v != null and String(w["state"]) == "march" \
				and _vdist(float(nearest_hut_v["x"]), float(nearest_hut_v["z"]),
						float(w["x"]), float(w["z"])) < 40.0:
			nearest_hut_v["hp"] = float(nearest_hut_v["hp"]) - 6.0 * dt
			if rng.chance(dt * 6.0):
				_fx_burst(float(nearest_hut_v["x"]), float(nearest_hut_v["z"]) * Z_TO_Y - 10.0,
						3, ["#d8c8a8"], {"speed": 70.0, "ttl": 0.5})
			if float(nearest_hut_v["hp"]) <= 0.0:
				var kept: Array = []
				for h in huts:
					if not is_same(h, nearest_hut_v):  # TS `h !== nearestHut` identity
						kept.append(h)
				huts = kept
				raidTimer = maxf(raidTimer, 120.0)  # breathing room after a loss
				_fire("hud_banner", [{
					"title": "A HUT BURNS", "subtitle": "your people scatter",
					"kind": "danger",
				}])
				_fx_burst(float(nearest_hut_v["x"]), float(nearest_hut_v["z"]) * Z_TO_Y, 24,
						["#ff9a5a", "#ffd08a"], {"speed": 160.0, "ttl": 1.0})
				_fire("audio_play", ["boom", 0.6, 0.0])
		# nothing left to siege AND nobody to fight? the war party goes home
		# (the 'flee' state existed but was never assigned — raids ground on
		# forever against empty villages)
		if String(w["state"]) != "flee" and huts.is_empty() and tribe.is_empty():
			w["state"] = "flee"
		var home: Variant = null
		for r in rivals:
			if float(r["hp"]) > 0.0:
				home = r
				break
		if home == null and not rivals.is_empty():
			home = rivals[0]
		if String(w["state"]) == "flee" and home != null \
				and _vdist(float(home["x"]), float(home["z"]), float(w["x"]), float(w["z"])) < 90.0:
			rivalWarriors.remove_at(wi)  # slipped away into the brush
		wi -= 1
	# war_graves combo (catalog II.a): a finished raid leaves DNA caches in
	# the wreckage — one payment per raid instance (I-bal wire) (TS:709-717)
	if raidActive and rivalWarriors.is_empty():
		raidActive = false
		if WorldGenomeScript.combo_active(ctx.world, "war_graves"):
			ctx.add_dna(15.0, "war graves")
			_fire("hud_toast", [tr("War graves yield DNA."), "reward", "⚔️"])


## Single-pass nearest with STRICT `<`: ties resolve in array order — the
## TS `.sort(compare)[0]` is a stable sort, so this is exactly equivalent.
func _nearest_by(items: Array, x: float, z: float) -> Variant:
	var best: Variant = null
	var best_d := INF
	for it in items:
		if not (it is Dictionary) or not (it.has("x") and it.has("z")):
			continue
		var d: float = _vdist(float(it["x"]), float(it["z"]), x, z)
		if d < best_d:
			best_d = d
			best = it
	return best


## Nearest BUILT hut to a point — TS:664 (no fallback to unbuilt huts here;
## that fallback lives only in nearest_hut, the delivery helper).
func _nearest_built_hut(x: float, z: float) -> Variant:
	var best: Variant = null
	var best_d := INF
	for h in huts:
		if float(h["buildT"]) > 0.0:
			continue
		var d: float = _vdist(float(h["x"]), float(h["z"]), x, z)
		if d < best_d:
			best_d = d
			best = h
	return best


## Single-pass nearest bush with food within `radius` (0 = map-wide). (TS:721-732)
func nearest_bush_with_food(x: float, z: float, radius := 0.0) -> Variant:
	var best: Variant = null
	var bd := INF
	var r2: float = radius * radius if radius > 0.0 else INF
	for b in bushes:
		if float(b["food"]) <= 0.5:
			continue
		var dx: float = float(b["x"]) - x
		var dz: float = float(b["z"]) - z
		var d2: float = dx * dx + dz * dz
		if d2 < bd and d2 <= r2:
			bd = d2
			best = b
	return best


## Single-pass nearest tree that still has wood and is not burning. (TS:735-745)
func nearest_tree_with_wood(x: float, z: float) -> Variant:
	var best: Variant = null
	var bd := INF
	for tr in trees:
		if float(tr["wood"]) <= 0.0 or float(tr["burn"]) > 0.0:
			continue
		var dx: float = float(tr["x"]) - x
		var dz: float = float(tr["z"]) - z
		var d2: float = dx * dx + dz * dz
		if d2 < bd:
			bd = d2
			best = tr
	return best


## TS tribeJobAI (TribeStage.ts:747-812). t_index threads the caller's loop
## position (TS `this.tribe.indexOf(t)` — see header divergence note).
func tribe_job_ai(t: Dictionary, dt: float, t_index: int) -> void:
	if bool(t["hasTarget"]):
		return  # arrived? handled outside
	# re-target on a cadence, not every frame
	t["retargetT"] = float(t["retargetT"]) - dt
	if float(t["retargetT"]) > 0.0:
		return
	t["retargetT"] = 0.5
	match String(t["role"]):
		"gather":
			if t["carrying"] == null:
				# WOOD QUOTA: bushes regrow in 30 s so a 600 px bush nearly
				# always exists and wood income was structurally 0. While
				# stock is under the build quota, every second gatherer chops
				# trees regardless. (TS:759-763)
				var under_quota: bool = wood < 80.0
				var on_wood_shift: bool = under_quota and t_index % 2 == 0
				var bush: Variant = null if on_wood_shift \
						else nearest_bush_with_food(float(t["x"]), float(t["z"]), 600.0)
				var tree: Variant = nearest_tree_with_wood(float(t["x"]), float(t["z"]))
				if tree != null and (on_wood_shift or bush == null):
					t["targetX"] = float(tree["x"])
					t["targetZ"] = float(tree["z"])
					t["hasTarget"] = true
				elif bush != null:
					t["targetX"] = float(bush["x"])
					t["targetZ"] = float(bush["z"])
					t["hasTarget"] = true
				elif tree != null:
					t["targetX"] = float(tree["x"])
					t["targetZ"] = float(tree["z"])
					t["hasTarget"] = true
				else:
					# QC round-2 B3 dead-zone feedback: no bush within 600 px AND
					# no tree with wood anywhere — the gatherer idles forever
					# with no word (the only recovery is the random sapling
					# respawn). Observation only: the targeting above is
					# TS:759-763 verbatim and untouched. The 10 s gate window
					# keeps several idle gatherers from stacking the message.
					_fire("hud_toast_gate",
							[tr("Gatherers idle — no berries or wood in reach"), "info", "🌿", 10.0])
			else:
				# deliver to nearest hut; if the village is GONE, drop at the chief
				var hut: Variant = nearest_hut(t)
				if hut != null:
					t["targetX"] = float(hut["x"])
					t["targetZ"] = float(hut["z"])
				else:
					t["targetX"] = px
					t["targetZ"] = pz
				t["hasTarget"] = true
		"hunt":
			if t["carrying"] == null:
				var bush: Variant = nearest_bush_with_food(float(t["x"]), float(t["z"]), 600.0)
				var tree: Variant = nearest_tree_with_wood(float(t["x"]), float(t["z"]))
				if bush != null:
					t["targetX"] = float(bush["x"])
					t["targetZ"] = float(bush["z"])
					t["hasTarget"] = true
				elif tree != null:
					t["targetX"] = float(tree["x"])
					t["targetZ"] = float(tree["z"])
					t["hasTarget"] = true
			else:
				var hut: Variant = nearest_hut(t)
				if hut != null:
					t["targetX"] = float(hut["x"])
					t["targetZ"] = float(hut["z"])
				else:
					t["targetX"] = px
					t["targetZ"] = pz
				t["hasTarget"] = true
		"warrior":
			# patrol around home hut; auto: march to the nearest living rival
			# occasionally (TS:792-808)
			var rival: Variant = null
			var bd := INF
			for r in rivals:
				if float(r["hp"]) <= 0.0:
					continue
				var d: float = _vdist(float(r["x"]), float(r["z"]), float(t["x"]), float(t["z"]))
				if d < bd:
					bd = d
					rival = r
			if rival != null and rng.chance(0.005):  # TS:796 — drawn only when a rival exists
				t["targetX"] = float(rival["x"]) + rng.range(-80.0, 80.0)
				t["targetZ"] = float(rival["z"]) + rng.range(-60.0, 60.0)
				t["hasTarget"] = true
				t["carrying"] = null
			elif not bool(t["hasTarget"]):
				var hut: Variant = nearest_hut(t)
				if hut != null:
					t["targetX"] = float(hut["x"]) + rng.range(-90.0, 90.0)
					t["targetZ"] = float(hut["z"]) + rng.range(-60.0, 60.0)
					t["hasTarget"] = true


## When a tribesman reaches its destination. (TS:815-843)
func tribe_arrive(t: Dictionary) -> void:
	if t["carrying"] == "food":
		# delivering
		food += 8.0
		t["carrying"] = null
		_fire("fx_spawn", [{"x": float(t["x"]), "y": float(t["z"]) * Z_TO_Y - 20.0,
				"kind": "dot", "color": "#ffd08a", "ttl": 0.6, "vy": -30.0, "size": 3.0}])
	elif t["carrying"] == "wood":
		wood += 8.0
		t["carrying"] = null
		_fire("fx_spawn", [{"x": float(t["x"]), "y": float(t["z"]) * Z_TO_Y - 20.0,
				"kind": "dot", "color": "#c8a878", "ttl": 0.6, "vy": -30.0, "size": 3.0}])
	else:
		# pick up from a bush
		for b in bushes:
			if float(b["food"]) > 0.5 and _vdist(float(b["x"]), float(b["z"]),
					float(t["x"]), float(t["z"])) < 30.0:
				b["food"] = float(b["food"]) - 1.0
				b["regrow"] = 30.0
				t["carrying"] = "food"
				break
		for tr in trees:
			if float(tr["wood"]) > 0.0 and float(tr["burn"]) <= 0.0 \
					and _vdist(float(tr["x"]), float(tr["z"]), float(t["x"]), float(t["z"])) < 30.0:
				tr["wood"] = float(tr["wood"]) - 1.0
				t["carrying"] = "wood"
				break


## TS nearestHut (TribeStage.ts:845-856) — built huts preferred, ALL huts as
## the fallback pool (the delivery path may target a hut still building).
func nearest_hut(t: Dictionary) -> Variant:
	var built: Array = []
	for h in huts:
		if float(h["buildT"]) <= 0.0:
			built.append(h)
	var pool: Array = built if not built.is_empty() else huts
	if pool.is_empty():
		return null
	return _nearest_by(pool, float(t["x"]), float(t["z"]))


# ---- rival camps, beast, fires -------------------------------------------------------

## TS updateRivalWarriors (TribeStage.ts:858-879) — the player's warriors
## assaulting a rival camp.
func update_rival_warriors(dt: float) -> void:
	for r in rivals:
		if float(r["hp"]) <= 0.0:
			continue
		var attackers := 0
		for t in tribe:
			if String(t["role"]) == "warrior" \
					and _vdist(float(r["x"]), float(r["z"]),
							float(t["x"]), float(t["z"])) < 90.0:
				attackers += 1
		if attackers > 0:
			r["hp"] = float(r["hp"]) - float(attackers) * 4.0 * dt
			r["anger"] = minf(1.0, float(r["anger"]) + dt * 0.1)
			if rng.chance(dt * 4.0):
				_fx_burst(float(r["x"]), float(r["z"]) * Z_TO_Y - 14.0, 3,
						["#ffcf8a"], {"speed": 70.0, "ttl": 0.4})
			if float(r["hp"]) <= 0.0:
				_fire("hud_banner", [{
					"title": "%s JOINS YOUR PEOPLE" % String(r["name"]).to_upper(),
					"subtitle": "unified by drums", "kind": "reward",
				}])
				_fire("audio_play", ["levelup", 1.0, 0.0])
				food += 60.0
				wood += 40.0
				ctx.add_karma(-0.05)


## TS updateBeast (TribeStage.ts:881-935) — march the nearest hut (or the
## chief), siege it, take fighter damage, gore the chief.
func update_beast(dt: float) -> void:
	if beast == null:
		return
	var b: Dictionary = beast
	var target: Variant = _nearest_hut_to(float(b["x"]), float(b["z"]))
	var dx: float = (float(target["x"]) if target != null else px) - float(b["x"])
	var dz: float = (float(target["z"]) if target != null else pz) - float(b["z"])
	var d: float = maxf(1.0, sqrt(dx * dx + dz * dz))
	if d > 40.0:
		b["x"] = float(b["x"]) + (dx / d) * 90.0 * dt          # TS:888 — x rate 90
		b["z"] = clampf(float(b["z"]) + (dz / d) * 70.0 * dt, Z_MIN, Z_MAX)  # TS:889 — z rate 70
	elif target != null:
		target["hp"] = float(target["hp"]) - 6.0 * dt
		if float(target["hp"]) <= 0.0:
			var kept: Array = []
			for h in huts:
				if not is_same(h, target):  # TS `h !== target` identity
					kept.append(h)
			huts = kept
			_fire("hud_banner", [{"title": "THE BEAST DESTROYS A HUT", "kind": "danger"}])
			_fire("audio_play", ["boom", 0.7, 0.0])
	# tribesmen + chief fight it
	var fighters := 0
	for t in tribe:
		if _vdist(float(t["x"]), float(t["z"]), float(b["x"]), float(b["z"])) < 60.0:
			fighters += 1
	var chief_near: bool = _vdist(px, pz, float(b["x"]), float(b["z"])) < 60.0
	var dps: float = float(fighters) * 9.0 + (14.0 if chief_near else 0.0)
	b["hp"] = float(b["hp"]) - dps * dt
	# the BEAST gores the chief — chance scales with chief proximity, not
	# fighter count (gatherers near the beast were killing the chief from
	# 2000px away: 18 fells in 163s, DNA 900->66) (A08)
	if chief_near and rng.chance(dt * 0.5) and deathFade <= 0.0 and invulnT <= 0.0:
		deathFade = 0.0001
		deathHandled = false
		lastDeathCause = "the great beast gored you"
	if rng.chance(dt * 10.0):
		_fx_burst(float(b["x"]), float(b["z"]) * Z_TO_Y - 30.0, 2,
				["#ffcf8a"], {"speed": 80.0, "ttl": 0.4})
	if float(b["hp"]) <= 0.0:
		beast = null
		_fire("hud_banner", [{"title": "THE GREAT BEAST FALLS",
				"subtitle": "feast for a week (+60 food)", "kind": "reward"}])
		food += 60.0
		ctx.add_dna(50.0)
		_fire("audio_play", ["levelup", 1.0, 0.0])
		_fx_burst(float(b["x"]), float(b["z"]) * Z_TO_Y, 30,
				["#ff9a8a", "#ffd08a"], {"speed": 180.0, "ttl": 1.0})


## TS nearestHutTo (TribeStage.ts:924-935) — built huts preferred, ALL huts
## as the fallback pool (same pool rule as nearest_hut, at a raw point).
func _nearest_hut_to(x: float, z: float) -> Variant:
	var built: Array = []
	for h in huts:
		if float(h["buildT"]) <= 0.0:
			built.append(h)
	var pool: Array = built if not built.is_empty() else huts
	if pool.is_empty():
		return null
	return _nearest_by(pool, x, z)


## TS updateFires (TribeStage.ts:937-960).
func update_fires(dt: float) -> void:
	for i in range(fires.size() - 1, -1, -1):
		var f: Dictionary = fires[i]
		f["ttl"] = float(f["ttl"]) - dt
		# tribesmen extinguish
		var nearby := 0
		for t in tribe:
			if _vdist(float(t["x"]), float(t["z"]), float(f["x"]), float(f["z"])) < 50.0:
				nearby += 1
		if nearby > 0:
			f["ttl"] = float(f["ttl"]) - float(nearby) * 4.0 * dt
		if rng.chance(dt * 10.0):
			_fire("fx_spawn", [{
				"x": float(f["x"]) + rng.range(-14.0, 14.0),
				"y": float(f["z"]) * Z_TO_Y - rng.range(0.0, 10.0),
				"vx": rng.range(-8.0, 8.0), "vy": rng.range(-60.0, -30.0),
				"ttl": 0.8, "size": rng.range(3.0, 7.0),
				"kind": "smoke", "color": "rgba(255,150,60,0.6)", "drag": 0.6,
			}])
		# spread
		f["spread"] = float(f["spread"]) - dt
		if float(f["spread"]) <= 0.0 and rng.chance(0.25):
			f["spread"] = 8.0
			for tr in trees:  # TS .find — the FIRST unburnt tree within 90
				if float(tr["burn"]) <= 0.0 \
						and _vdist(float(tr["x"]), float(tr["z"]),
								float(f["x"]), float(f["z"])) < 90.0:
					ignite_tree(tr)
					break
		if float(f["ttl"]) <= 0.0:
			fires.remove_at(i)


## TS igniteTree (TribeStage.ts:962-967) — public: the fire spread and
## lightning_strike both land here.
func ignite_tree(tree: Dictionary) -> void:
	if float(tree["burn"]) > 0.0 or float(tree["wood"]) <= 0.0:
		return  # stumps do not burn
	tree["burn"] = 8.0
	fires.append({"x": float(tree["x"]), "z": float(tree["z"]), "ttl": 10.0, "spread": 8.0})
	_fire("audio_play", ["fire", 0.6, 0.0])


## TS lightningStrike (TribeStage.ts:971-993) — public: the storm chaos
## event (task 3) calls it.
func lightning_strike() -> void:
	# strikes a random tree near the tribe, or a hut
	var targets: Array = []
	for tr in trees:
		if float(tr["burn"]) <= 0.0 and float(tr["wood"]) > 0.0:
			targets.append(tr)
	targets.append_array(huts)
	if targets.is_empty():
		_fire("hud_toast", [tr("The storm crackles but finds nothing to burn"),
				"info", "⚡"])
		return
	var t: Dictionary = rng.pick(targets)
	# TS duck-type `'speciesId' in t || !('wood' in t)`: speciesId exists on
	# neither shape here (tree/hut dicts), so the branch reduces to "no wood
	# field" = hut — ported as the explicit key check
	if not t.has("wood"):
		# a hut was picked — burn it directly
		t["hp"] = maxf(0.0, float(t["hp"]) - 35.0)
		if float(t["hp"]) <= 0.0:
			var kept: Array = []
			for h in huts:
				if not is_same(h, t):  # TS `h !== hut` identity
					kept.append(h)
			huts = kept
			_fire("hud_banner", [{"title": "LIGHTNING SPLITS A HUT", "kind": "danger"}])
	else:
		ignite_tree(t)
	_fire("cam_shake", [6.0, 0.4])
	_fire("audio_play", ["zap", 1.0, 0.0])
	_fire("hud_toast", [tr("Lightning! Fire spreads with the wind!"), "bad", "⚡"])


## True when raids are forbidden: peaceful AND no hut standing yet.
## (TS:1023-1026 — the chaos raid events gate on this.)
func raids_blocked() -> bool:
	return ctx.difficulty == "peaceful" and huts.is_empty()


## Chaos variant (rival_festival): rivals lay down arms for a while — the
## raid clock may not fire sooner than `seconds` from now. (TS:1029-1032)
func pause_raids(seconds: float) -> void:
	raidTimer = maxf(raidTimer, seconds)


## TS launchRivalRaidNow (TribeStage.ts:1034-1039) — the chaos event path
## bypassed the raid-clock gate — a hutless PEACEFUL camp got raiders anyway
## (popCap 1, no births, unrecoverable).
func launch_rival_raid_now() -> void:
	if raids_blocked():
		return
	launch_rival_raid()


# ---- chaos -----------------------------------------------------------------------------

## TS TribeStage.ts:341-369 — chaos.update with the full ctx and hooks. The
## storyteller reference arrives through hooks (get_gap_bias / get_mood /
## get_warn_scale Callables — the sim stays decoupled from the object); when
## absent they read the storyteller's neutral defaults (gap 1.0, mood "test",
## warnScale 1.0). dominance = wealth_pressure() from sim state (TS:348).
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
		# TS `if (def.warn)` — effective_warn keeps the static-key semantics
		# (the tribe deck carries no warn_fn defs; the Ruling 13 seam stays
		# uniform with the creature wiring)
		if ChaosScript.effective_warn(def):
			_fire("hud_banner", [{"title": ChaosScript.effective_warn(def),
					"kind": "danger", "ttl": 2.4}])
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
		mirrorLedger.maybe_queue(rng, String(def["id"]), "festival")
	chaos.update(dt, self, {
		"chaos": float(ctx.chaos), "karma": float(ctx.karma), "stageTime": time,
		"gapMult": ctx.chaos_gap_mult() * gap_bias,
		"mood": mood,
		"warnScale": warn_scale,  # bio_tell bucket
		"mirrors": mirrorLedger.queued(),  # mirror_rule returns
		"dominance": wealth_pressure(),  # siege_hoard input
	}, {
		"onWarn": on_warn,
		"onApply": on_apply,
		"onEnd": on_end,
	})


## siege_hoard (catalog III #8) input: the tribe's wealth pressure — the
## richest hoard draws the biggest siege right when it is richest. (TS:1066-1070)
func wealth_pressure() -> float:
	return minf(1.0, (food + wood) / 500.0)


## TS hasActiveChaos (TribeStage.ts:1075-1077) — the ACTIVE-phase set only —
## a warn-phase event does not count.
func has_active_chaos() -> bool:
	return chaos.active_events().size() > 0


## TS festival (TribeStage.ts:1041-1051).
func festival() -> void:
	ctx.add_karma(0.08)
	food = maxf(0.0, food - 20.0)
	for t in tribe:
		t["mood"] = "happy"
		t["hp"] = t["maxHp"]
	_fire("hud_toast", [tr("Drums all night! The tribe is one."), "good", "🔥"])
	var hx: float = float(huts[0]["x"]) if not huts.is_empty() else 0.0
	var hz: float = float(huts[0]["z"]) if not huts.is_empty() else 80.0
	for i in 3:
		fires.append({"x": hx + rng.range(-80.0, 80.0),
				"z": hz + rng.range(-40.0, 40.0), "ttl": 12.0, "spread": 999.0})


## mirror_rule (festival's mirror face): exactly ONE rule inverted — the
## feast sours; the mood rule flips, the food cost and fires stay. (TS:1053-1064)
func festival_mirror() -> void:
	food = maxf(0.0, food - 20.0)
	for t in tribe:
		t["mood"] = "afraid"
	_fire("hud_toast", [tr("The feast sours — the tribe bickers all night."), "bad", "🔥"])
	var hx: float = float(huts[0]["x"]) if not huts.is_empty() else 0.0
	var hz: float = float(huts[0]["z"]) if not huts.is_empty() else 80.0
	for i in 3:
		fires.append({"x": hx + rng.range(-80.0, 80.0),
				"z": hz + rng.range(-40.0, 40.0), "ttl": 12.0, "spread": 999.0})


## TS starShower (TribeStage.ts:1079-1084).
func star_shower() -> void:
	var dna := 80
	ctx.add_dna(float(dna))
	_fire("hud_float_world", [px, pz * Z_TO_Y - 60.0, "+%d DNA" % dna, "#c9a4ff", 16.0])
	_fire("hud_toast", [tr("Falling stars seed the sky with DNA."), "reward", "🌠"])


# ---- economy ------------------------------------------------------------------------

## TS updateEconomy (TribeStage.ts:1086-1172).
func update_economy(dt: float) -> void:
	# arrivals (TS:1088-1102)
	for t in tribe:
		if not bool(t["hasTarget"]) and t["carrying"] != null:
			# standing at hut (or beside the chief when hutless)? deliver
			var hut: Variant = nearest_hut(t)
			var at_hut: bool = hut != null and _vdist(float(hut["x"]), float(hut["z"]),
					float(t["x"]), float(t["z"])) < 44.0
			var at_chief: bool = hut == null and _vdist(px, pz,
					float(t["x"]), float(t["z"])) < 44.0
			if at_hut or at_chief:
				tribe_arrive(t)
		if not bool(t["hasTarget"]) and t["carrying"] == null:
			# standing at resource? pick up
			tribe_arrive(t)

	# bush regrow (TS:1105-1110)
	for b in bushes:
		if float(b["food"]) <= 0.0:
			b["regrow"] = float(b["regrow"]) - dt
			if float(b["regrow"]) <= 0.0:
				b["food"] = rng.range(3.0, 7.0)
	# forest regrows: a sapling every ~45 s up to the original stand (TS:1112-1125)
	saplingT -= dt
	if saplingT <= 0.0:
		saplingT = 45.0
		var alive := 0
		for tr in trees:
			if float(tr["wood"]) > 0.0:
				alive += 1
		if alive < 30:
			trees.append({
				"x": rng.range(-WORLD_HALF, WORLD_HALF),
				"z": rng.range(Z_MIN, Z_MAX),
				"wood": rng.range(4.0, 9.0),
				"burn": 0.0,
				"seed": rng.range(0.0, 9.0),
			})
	# tree burnout (TS:1127-1132)
	for tr in trees:
		if float(tr["burn"]) > 0.0:
			tr["burn"] = float(tr["burn"]) - dt
			if float(tr["burn"]) <= 0.0:
				tr["wood"] = 0.0
	# huts build (TS:1134-1157)
	for h in huts:
		if float(h["buildT"]) > 0.0:
			h["buildT"] = float(h["buildT"]) - dt
			if float(h["buildT"]) <= 0.0:
				h["buildT"] = 0.0
				_fire("hud_toast", [tr("A new hut raises the roof!"), "good", "🏠"])
				_fire("audio_play", ["build", 0.8, 0.0])
		if float(h["hp"]) < float(h["maxHp"]):
			h["hp"] = minf(float(h["maxHp"]), float(h["hp"]) + dt * 5.0)
		# built huts recruit new tribesmen over time (why huts matter)
		if float(h["buildT"]) <= 0.0:
			h["recruitT"] = float(h.get("recruitT", 0.0)) + dt
			# no births mid-siege — recruits spawned straight into the raid
			if float(h["recruitT"]) >= 45.0 and rivalWarriors.is_empty():
				h["recruitT"] = 0.0
				if tribe.size() < pop_cap():
					add_tribesman(mutate_like(ctx.genome), "gather")
					_fire("hud_toast", [tr("A child was born in the hut! (+1 tribesman)"),
							"good", "👶"])
					_fire("audio_play", ["spawn", 0.7, 0.0])

	# totem building (TS:1160-1163)
	if bool(totem["active"]) and float(totem["progress"]) < 100.0:
		var workers := tribe.size()
		totem["progress"] = minf(100.0, float(totem["progress"]) + float(workers) * dt * 1.6)

	# festival passive: karma drifts up when everyone is well fed (TS:1166-1171)
	if food > 80.0 and rng.chance(dt * 0.05):
		ctx.add_karma(0.01)
		food -= 5.0
		_fire("hud_toast", [tr("The tribe feasts! (+harmony)"), "good", "🔥"])
		for t in tribe:
			t["mood"] = "happy"


## TS mutateLike (TribeStage.ts:1426-1431) — the pack-conversion / recruit
## mutation seam. Draw order: hue range first, then the 3-draw gauss.
func mutate_like(g: Dictionary) -> Dictionary:
	var out: Dictionary = GenomeScript.clone_genome(g)
	out["hue"] = fmod(float(out["hue"]) + rng.range(-40.0, 40.0) + 360.0, 360.0)
	out["size"] = clampf(float(out["size"]) + rng.gauss() * 0.1, 0.6, 2.2)
	return out


# ---- debug seams --------------------------------------------------------------------

## Debug/test access to internal sim state (mirrors creature_sim.debug_state;
## the bot law's documented read surface).
func debug_state() -> Dictionary:
	return {
		"px": px, "pz": pz, "food": food, "wood": wood,
		"tribe": tribe, "huts": huts, "trees": trees, "bushes": bushes,
		"fires": fires, "rivalWarriors": rivalWarriors, "rivals": rivals,
		"beast": beast, "totem": totem, "dayPhase": dayPhase, "time": time,
		"popCap": pop_cap(), "raidTimer": raidTimer,
	}


## Debug/test: the tribe bot's stockpile cheat — the ONE sim mutator the
## M4 task-6 bot adds to this sim (bot parity law's exception list, alongside
## creature_sim's debug_grant/debug_spawn_pack family). The bot's REAL drawn
## R · HUT / TOTEM button clicks gate on wood ≥ 40 and food ≥ 100 + wood ≥ 80
## (TribeStage.ts:530/547); the gather economy would otherwise hold the click
## legs hostage to bush round-trip timing. SET semantics (absolute, like
## creature_sim.debug_grant's `ctx.dna = dna_amount`) keep a re-armed retry
## idempotent; the bot passes its current food when only wood must move.
func debug_grant(food_amount: float, wood_amount: float) -> void:
	food = food_amount
	wood = wood_amount


# ---- internals ----------------------------------------------------------------------

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


## TS core/math vecDist — f64 inline (a f32 Vector2 would lose bits at the
## ±2400 world scale; the sanctioned-divergence class, see PARITY-M2 §17).
func _vdist(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := ax - bx
	var dy := ay - by
	return sqrt(dx * dx + dy * dy)


## TS gfx/renderer.ts hsl(): `hsl(H S% L% / A)` with toFixed(0) rounding
## (ties toward +infinity -> floori(x + 0.5), positive domain here).
func _hsl(h: float, s: float, l: float, a: float = 1.0) -> String:
	return "hsl(%d %d%% %d%% / %.2f)" % [floori(h + 0.5), floori(s * 100.0 + 0.5),
			floori(l * 100.0 + 0.5), a]


## Number.isFinite gate for blob fields (strings/bools/missing → false).
static func _fin(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


## TS `x ?? fallback` where a non-number must not poison the math: TS
## Math.max/min coerce numeric strings ("50"→50) — the port reads the
## fallback instead; non-numeric strings NaN the TS read (see header
## divergence note).
static func _fin_or(v: Variant, fallback: float) -> float:
	return float(v) if _fin(v) else fallback


## JS truthiness for the pack-genome gate (TS `raw[i]?.genome ? … : …`,
## TribeStage.ts:185): {} and [] are truthy, 0/""/null/false are not.
static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is String:
		return not (v as String).is_empty()
	if v is float or v is int:
		var f := float(v)
		return not is_nan(f) and f != 0.0
	return true  # objects/arrays are always truthy in JS
