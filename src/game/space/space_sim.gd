## SPACE STAGE sim core PART 1 — the finale/sandbox system as a headless
## RefCounted: all state fields, the constructor (the stage rng branch + the
## chaos scheduler on a SECOND branch + deckSeed + generateSystem), the
## per-planet ecosystems (makePlanetEco — the archetype diet dial), the onEnter
## C1 gate + the FULL restore whitelist, persistColonies, and the update
## subset: the fast-forward block, ship control (cursor thrust + WASD), engine
## particles, planet orbits + colony logistic growth, sun danger + hull regen.
## Plus the debug seams (debug_state / debug_seed_colonies). Port of Spore
## src/game/space/SpaceStage.ts (frozen) :25-394 + debugSeedColonies
## (:1275-1287); the near-planet interaction block starts at :391 and is NOT
## ported here.
##
## Architecture (M4/M5 pattern, same as civ_sim.gd): SpaceSim.new(ctx,
## rng_branch, hooks) —
##   ctx        the M1 GameContext; the sim calls ctx methods directly
##              (bump_extinction — the tribe/civ precedent; NOT a hook) and
##              reads ctx.world/ctx.flags/ctx.world_stats
##   rng_branch the stage's dedicated Rng (the CALLER draws ctx.rng.branch(),
##              mirroring TS `this.rng = game.context.rng.branch()` — the 5th
##              boot-order branch; the task-6 pin observes it at ITS level)
##   hooks      Dictionary of Callables for every scene/audio effect; missing
##              key = silent no-op so tests record selectively. Keys used by
##              PART 1: hud_toast(text, kind, icon), hud_show_objective(text),
##              audio_set_mood(name), cam_shake(mag, dur), fx_spawn(opts).
##              Keys that exist for parity but PART 1 never fires: hud_banner,
##              hud_set_abilities, audio_play, go_to (space never go_to's
##              onward), save_all (the stage binds persist_state to it).
##              (Audio sites carry `# TS audio.play(...) — audio core: its own
##              task` per the standing deferral; PART 1 has none.)
## No Input singleton reads: update(dt, inp) takes the M2 input SNAPSHOT and
## reads keys_held (KeyF hold, WASD/arrows) + down/wx/wy (cursor thrust).
## The chaos scheduler rides a SECOND branch of the stage rng (TS:98) holding
## the world-parameterized space deck (spaceEvents.ts) — the DECK IS TASK 3'S:
## the scheduler is constructed with an EMPTY defs array and the C1 rebuild
## gate is fully wired around it (the M5-T1 ruling; _make_deck returns []).
## The finale/ending state fields exist (TS:88-93) but their update logic is
## task 2's (:391-632), as are the pirates/black-holes machines, the panel
## interactions (the uiHold WRITE side, TS:431/434), the 5 s auto-persist tick
## (TS:610-613) and the invuln/hurtT decays (TS:605-606). The render pass
## (:885+) and the stage-side hook bindings are task 4's.
##
## TS quirks ported AS-IS (parity pins, each commented at its site):
##  - timeScale reads ffHold BEFORE the KeyF update (:306 before :307) — the
##    first held frame ticks dt·1, and the frame after release still ticks
##    dt·26 (the decay runs after the read)
##  - the orbit ×0.4 reads ffHold POST-update (:365) — the slow-orbit lands on
##    the first held frame
##  - the engine-particle chance short-circuits on thrust 0 (:353) — an idle
##    frame draws NOTHING from the stage rng stream
##  - makePlanetEco draws exactly ONE diet-flip chance per roster species (the
##    JS &&/else-if short-circuit, :157-158); the volcanic carnivore CAN flip
##    back to herbivore (herbPull applies to it — :158)
##  - the bonus species append AFTER the roster so the diet dial never touches
##    them (:161-177)
##  - the restore's abductCount + ending blocks nest INSIDE the shapes gate
##    (:201-265): the TS source indents them at 8 spaces (try-level-looking) —
##    a formatting artifact; the trailing :265 closer closes the :201 gate
##    (AST-verified in the T1 review) — so a corrupt/wrong-length blob
##    discards the WHOLE restore incl. the ledger and the won-run state
##  - the shapes predicate admits ARRAY rows (typeof 'object') — the gate
##    stays open and every raw.* read of such a row is undefined (the port
##    reads an empty row: identical guard outcomes, nothing restores for it)
##  - colony + scanned ride the whitelist — the round-4 numeric hardening
##    dropped them and every reload wiped the 3-thriving ending gate (12
##    reports, identical repro) (:218-221)
##  - the eco restore ALWAYS takes the saved eco — the old !p.eco check
##    silently re-rolled every lush roster on reload (:236-240)
##  - the restore's num(v, min) helper has NO max: hue 2000 restores as 2000
##    (:208-214, the verbatim read)
##  - debugSeedColonies' docstring says 'three nearest lush worlds' but the
##    code takes the FIRST THREE non-barren uncolonized planets in ORDER
##    (:1275-1287, pinned as coded)
## Recorded divergences (parity-pin ledger):
##  - TS `world.abductCount && typeof world.abductCount === 'object'` passes
##    for ANY JS object ({} included — JS object truthiness; arrays too,
##    typeof 'object'). The port is the type check alone (`is Dictionary or
##    is Array`): GDScript's truthy-Dictionary would wrongly reject {}.
##  - TS `world.cargo` rows with an ARRAY genome pass `typeof === 'object'`;
##    the object spread contributes NO GENE KEYS (indexed '0'/'1'… junk keys
##    only, which the TS clampGenome carries on the saved genome forever but
##    no consumer reads) → the net genome is the default (the tribe
##    packGenomes precedent); the port matches with a clean dict.
##  - Math.hypot/vecDist port as sqrt(dx²+dy²) inline (the civ precedent).
##  - the engine-particle color is the TS hsl(200,1,0.7) CSS STRING via the
##    local _hsl helper (renderer.gd parses it at draw time — the fx pool
##    stores String(opts.color), so a Color would corrupt).
##  - the TS try/catch around the restore ports as JSON.parse_string null
##    checks (no GDScript try/catch): a parse failure reads as "no blob".
## Documented debug seam surface (bot parity law's exception list, the civ
## analog of tribe's debug_grant): debug_state() (read) +
## debug_seed_colonies() (TS:1275-1287, the task-6 bot's colony leg). No
## debug_set_ship — PART 1's tests set the ship fields directly; task 6 may
## add it for bot legs (any addition gets documented here).
class_name SpaceSim
extends RefCounted

const ChaosScript := preload("res://src/game/chaos.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const MutationScript := preload("res://src/evo/mutation.gd")
const NamesScript := preload("res://src/evo/names.gd")

## TS hud.showObjective on onEnter (SpaceStage.ts:188).
const OBJECTIVE_LINE := "SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve"

## TS:105 — the fixed kind ring, verbatim (`kinds[i] ?? 'barren'` is
## unreachable for i < 6).
const KINDS: Array = ["lush", "ocean", "volcanic", "barren", "lush", "barren"]


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

var time := 0.0                  # TS:55

# ship (TS:58-64)
var sx := 0.0
var sy := -900.0
var svx := 0.0
var svy := 0.0
var shp := 100.0
var shpMax := 100.0
var shipAngle := -PI / 2.0
var thrust := 0.0
var invuln := 2.0
var hurtT := 0.0

var planets: Array = []          # TS Planet[] :25-40 — plain dicts, TS keys verbatim
var pirates: Array = []          # TS:42-44/67 — the machine is task 2's; the field rides state
var pirateTtl: Array = []        # TS:68
var pirateLull := false          # TS:69 — pirate_lull: sieges stand down while set
var abductCount: Dictionary = {}  # TS:70 — the abduct pay-curve ledger
var resurveyCd := 0.0            # TS:71
var blackHoles: Array = []       # TS:46-48/72 — task 2's
var cargo: Array = []            # TS:73 — {genome, name} rows

# TS ChaosScheduler<SpaceStage> (:74) — constructed in _init at the TS stream
# position on a SECOND rng.branch(); the space deck arrives with task 3
# (spaceEvents.ts) and the defs array stays EMPTY until then.
var chaos: Variant = null
## TS deckSeed (:75-78) — a CONTINUE/NEW LIFE landing on a different world
## rebuilds the deck at on_enter (C1: decks built from a stale WorldGenome
## played run-1 events in run 2).
var deckSeed := -1

var sun: Dictionary = {"x": 0.0, "y": 0.0, "r": 130.0}  # TS:84
var beamT := 0.0                 # TS:85 — abduction animation (task 2)
var beamTarget: Variant = null   # TS:86 — Planet | null (task 2)
var ffHold := 0.0                # TS:87 — fast-forward visual
var finale: Variant = null       # TS:88 — {x, y, active, t} | null; the state rides, the machine is task 2's
var endingT := 0.0               # TS:89
var endingDone := false          # TS:90
var endingDismissed := false     # TS:91
var dismissT := 0.0              # TS:92
var tributeDemand := 0.0         # TS:93

# TS:1193 — read by the ship control (down && !uiHold); the WRITE side is the
# panel-interaction task's (TS:431/434)
var uiHold := false
# TS:280 — the 5 s auto-persist tick is task 2's (TS:610-613); the field rides
var persistT := 0.0


func _init(ctx_v: Variant, rng_branch: Variant, hooks: Dictionary = {}) -> void:
	ctx = ctx_v
	rng = rng_branch
	_hooks = hooks
	# TS:95-101 — rng comes from the CALLER (ctx.rng.branch()); the chaos
	# scheduler rides a SECOND branch of the stage rng (the deck: task 3);
	# deckSeed + the system build follow in TS order
	chaos = ChaosScript.new(rng.branch(), _make_deck())  # TS:98
	deckSeed = int(ctx.world["seed"])  # TS:99
	generate_system()  # TS:100


## TS hasActiveChaos (:80-82) — the ACTIVE-phase set only; a warn-phase event
## does not count.
func has_active_chaos() -> bool:
	return chaos.active_events().size() > 0


## The deck factory seam (spaceEvents.ts:49) — task 3 ships the
## world-parameterized space deck; until then the scheduler runs with an
## EMPTY defs array (the M5-T1 ruling). Draws nothing from any stage rng.
func _make_deck() -> Array:
	return []


# ---- stage lifecycle (TS:181-297) --------------------------------------------------

func on_enter() -> void:
	# C1: a CONTINUE/NEW LIFE landing on a different world rebuilds the deck
	# (TS:182-186) — the rebuilt scheduler still holds the empty task-3 deck
	if int(ctx.world["seed"]) != deckSeed:
		chaos = ChaosScript.new(rng.branch(), _make_deck())
		deckSeed = int(ctx.world["seed"])
	_fire("audio_set_mood", ["space"])  # TS:187
	_fire("hud_show_objective", [OBJECTIVE_LINE])  # TS:188
	_restore_world()  # TS:190-267 (inlined in TS onEnter; split for readability)


func on_exit() -> void:
	persist_colonies()  # TS:270-272


## saveAll hook seam — splice/jettison/scan used to roll back on quit while
## their DNA/cargo effects stayed (DNA spent, planet unscanned) (TS:274-278).
func persist_state() -> void:
	persist_colonies()


## The restore whitelist (TS:190-267 — TS inlines it in onEnter). EVERY field
## rides a guard: corrupt values keep the generated/current ones instead of
## NaNing the orbit loop.
func _restore_world() -> void:
	# restore the exact system (planets, colonies, cargo) from the last save
	var saved: Variant = ctx.flags.get("spaceWorld")
	if not (saved is String) or (saved as String).is_empty():
		return  # TS:191 — no blob
	# TS try/catch — a parse failure reads as "no blob" (TS:266 `catch /* fresh */`)
	var parsed: Variant = JSON.parse_string(saved)
	if not (parsed is Dictionary):
		return
	var world: Dictionary = parsed
	# TS:200 — shapesOk: an array whose every row is an object (`typeof === 'object'
	# && !== null` — a JSON ARRAY row passes too; the gate stays open for it)
	var planets_v: Variant = world.get("planets")
	var shapes_ok: bool = planets_v is Array
	if shapes_ok:
		for pl in planets_v:
			if not (pl is Dictionary or pl is Array):
				shapes_ok = false
				break
	if shapes_ok and (planets_v as Array).size() == planets.size():
		for i in planets.size():
			var p: Dictionary = planets[i]
			# an ARRAY row keeps the gate open but every raw.* read is
			# undefined in the TS — the port reads an empty row for it
			# (identical guard outcomes: nothing restores for that planet)
			var raw_v: Variant = planets_v[i]
			var raw: Dictionary = raw_v if raw_v is Dictionary else {}
			# numeric sanity BEFORE assign — a corrupt field (r:-80,
			# orbitSpeed:'fast') NaNs the orbit loop and throws in
			# createRadialGradient every frame, bricking the stage (TS:205-208)
			var clean: Dictionary = {}
			var r_v: Variant = _num(raw.get("r"), 0.0)
			if r_v != null:
				clean["r"] = r_v
			var orbit_r_v: Variant = _num(raw.get("orbitR"))
			if orbit_r_v != null:
				clean["orbitR"] = orbit_r_v
			var orbit_speed_v: Variant = _num(raw.get("orbitSpeed"))
			if orbit_speed_v != null:
				clean["orbitSpeed"] = orbit_speed_v
			var angle_v: Variant = _num(raw.get("angle"))
			if angle_v != null:
				clean["angle"] = angle_v
			var hue_v: Variant = _num(raw.get("hue"))
			if hue_v != null:
				clean["hue"] = hue_v
			if raw.get("name") is String:
				clean["name"] = raw["name"]
			if raw.get("kind") == "barren" or raw.get("kind") == "lush" \
					or raw.get("kind") == "ocean" or raw.get("kind") == "volcanic":
				clean["kind"] = raw["kind"]
			if raw.get("ring") is bool:
				clean["ring"] = raw["ring"]
			# colony + scanned must ride the whitelist too — the round-4
			# numeric hardening dropped them and every reload wiped the
			# 3-thriving ending gate (12 reports, identical repro) (TS:218-225)
			var rc: Variant = raw.get("colony")
			if rc is Dictionary and _fin(rc.get("pop")):
				var gens: Variant = rc.get("generations")
				clean["colony"] = {"pop": float(rc["pop"]),
					"generations": float(gens) if _fin(gens) else 1.0}
			if raw.get("scanned") is bool:
				clean["scanned"] = raw["scanned"]
			p.merge(clean, true)  # TS Object.assign(p, clean)
			# the post-assign validity guards (TS:227-228)
			var col: Variant = p["colony"]
			if not (col is Dictionary) or not _fin(col.get("pop")):
				p["colony"] = null
			if not (p["scanned"] is bool):
				p["scanned"] = false
			# old-format saves once embedded the eco as a plain object — a
			# non-Ecosystem eco would crash `.tick` on the first frame (TS:229-231)
			if p["eco"] != null and not (p["eco"] is EcoScript):
				p["eco"] = null
			# rebuild the planet's own ecosystem from the save (seeded genes
			# used to be replaced by a fresh random roster every reload) (TS:232-240)
			var re: Variant = raw.get("eco")
			# ALWAYS take the saved eco — the constructor already built a
			# fresh random one for lush planets, so the old !p.eco check
			# silently re-rolled every roster on reload (TS:236-239)
			if re is Dictionary and (re.get("species") is Array):
				p["eco"] = EcoScript.from_json(re, rng.branch())
			# a seeded barren world keeps its colonists' ecosystem across reloads
			# (TS:241-245)
			if p["colony"] != null and p["eco"] == null:
				p["eco"] = EcoScript.new(rng.branch())
				p["eco"].add_species(GenomeScript.clone_genome(GenomeScript.default_genome()),
						5.0, {"kin": true, "name": "%s colonists" % String(p["name"])})
		# the cargo clamp merge (TS:247-251)
		var cargo_v: Variant = world.get("cargo")
		if cargo_v is Array:
			var merged: Array = []
			for it in cargo_v:
				# TS filter: an object row whose genome is an object (an ARRAY
				# genome passes typeof 'object'; the spread contributes no GENE
				# keys — indexed junk only — so the default genome; see the
				# header divergence note)
				if not (it is Dictionary):
					continue
				var genome_v: Variant = it.get("genome")
				if not (genome_v is Dictionary or genome_v is Array):
					continue
				var g: Dictionary = GenomeScript.default_genome()
				if genome_v is Dictionary:
					g.merge(genome_v, true)  # TS {...defaultGenome(), ...it.genome}
				merged.append({"genome": GenomeScript.clamp_genome(g),
					"name": it["name"] if it.get("name") is String else "specimen"})
			cargo = merged
		else:
			cargo = []
		# abduct pay-curve ledger — otherwise every reload re-pays +10 "firsts"
		# (TS:252-255). GATE PLACEMENT (the T1-review AST fact): the TS source
		# indents this + the ending block at 8 spaces (try-level-looking) but
		# the braces nest them INSIDE the :201 shapes gate — the trailing :265
		# closer closes the gate — so a corrupt/wrong-length blob discards the
		# WHOLE restore incl. the ledger and the won-run state.
		var ac: Variant = world.get("abductCount")
		# TS `world.abductCount && typeof world.abductCount === 'object'` — any
		# JS object passes ({} included, JS object truthiness; arrays too). The
		# port is the type check alone: GDScript's truthy-Dictionary would
		# wrongly reject {}.
		if ac is Dictionary or ac is Array:
			abductCount = ac
		# a won run stays won — the ending used to re-fire on every reload
		# (TS:256-264 — inside the gate, same brace fact)
		var ed: Variant = world.get("endingDone")
		if ed is bool and bool(ed):
			endingDone = true
			endingDismissed = world.get("endingDismissed") is bool \
					and bool(world.get("endingDismissed"))  # TS strict === true
			endingT = 99.0 if endingDismissed else endingT
			dismissT = 99.0 if endingDismissed else dismissT
			# a dismissed ending sleeps — no stale orb, no AWAKENS replay (TS:262-263)
			finale = null if endingDismissed else {"x": 0.0, "y": -1900.0, "active": true, "t": 0.0}


## Full world spec so a reload rebuilds the SAME system (planet eco + abduct
## ledger included — seeded genes and the pay curve survive now) (TS:282-297).
func persist_colonies() -> void:
	var planets_list: Array = []
	for p in planets:
		planets_list.append({
			"id": p["id"], "name": p["name"], "orbitR": p["orbitR"], "angle": p["angle"],
			"orbitSpeed": p["orbitSpeed"], "r": p["r"], "hue": p["hue"], "kind": p["kind"],
			"ring": p["ring"], "scanned": p["scanned"], "colony": p["colony"],
			"eco": p["eco"].to_json() if p["eco"] != null else null,
		})
	var blob: Dictionary = {
		"planets": planets_list,
		"cargo": cargo,
		"abductCount": abductCount,
		"endingDone": endingDone,
		"endingDismissed": endingDismissed,
	}
	ctx.flags["spaceWorld"] = JSON.stringify(blob)  # TS:296


# ---- system generation (TS:103-179) -----------------------------------------------

func generate_system() -> void:
	# TS:104/131 fetches ctx then voids it — nothing in the loop reads it
	for i in 6:
		var kind: String = KINDS[i]
		var orbit_r: float = 520.0 + i * 380.0 + rng.range(-60.0, 60.0)  # TS:108
		var planet: Dictionary = {
			"id": i,
			"name": "%s-%d" % [NamesScript.species_name(rng), i + 1],  # TS:112
			"orbitR": orbit_r,
			"angle": rng.range(0.0, TAU),  # TS:114
			"orbitSpeed": rng.range(0.008, 0.02) * (1.0 if i % 2 == 0 else -1.0) / (1.0 + i * 0.12),  # TS:115
			"r": 46.0 + rng.range(0.0, 34.0) + (10.0 if kind == "lush" else 0.0),  # TS:116
			"hue": rng.range(90.0, 140.0) if kind == "lush" else (
					rng.range(190.0, 220.0) if kind == "ocean" else (
					rng.range(5.0, 30.0) if kind == "volcanic" else rng.range(30.0, 60.0))),  # TS:117-120
			"kind": kind,
			"ring": rng.chance(0.25),  # TS:122
			"eco": null,
			"colony": null,
			"scanned": false,
			"x": 0.0,
			"y": 0.0,
		}
		if kind != "barren":
			planet["eco"] = make_planet_eco(planet)  # TS:128
		planets.append(planet)


func make_planet_eco(p: Dictionary) -> Variant:
	var eco: Variant = EcoScript.new(rng.branch())  # TS:135 — the eco's own branch
	eco.flora_cap = 140.0 if String(p["kind"]) == "lush" else (110.0 if String(p["kind"]) == "ocean" else 70.0)  # TS:136
	eco.flora = float(eco.flora_cap) * 0.7  # TS:137
	# World-genome archetype weights bend each planet's seed roster — same
	# diet dial as CellStage.seedEcology (deterministic, this stage's rng
	# branch only; all planets share the run's one world): (TS:138-143)
	#   herbivore W / carnivore W / predator W → the diet flip chances below
	#   titan ≥ 1 → one extra large species (pop NOT multiplied)
	#   swarm ≥ 1 → one extra small fast species
	var weights: Dictionary = WorldGenomeScript.archetype_weights(ctx.world)
	var herb_w: float = float(weights.get("herbivore", 1.0))
	var carn_w: float = float(weights.get("carnivore", 1.0)) * float(weights.get("predator", 1.0))
	var herb_pull := minf(0.9, maxf(0.0, herb_w - 1.0) * 0.5 + maxf(0.0, 1.0 - carn_w) * 0.5)  # TS:147
	var carn_pull := minf(0.9, maxf(0.0, carn_w - 1.0) * 0.5 + maxf(0.0, 1.0 - herb_w) * 0.5)  # TS:148
	var n: int = rng.int(2, 4)  # TS:149
	for i in n:
		var base: Dictionary = GenomeScript.clone_genome(GenomeScript.default_genome())
		var arch: Dictionary = MutationScript.mutate(base, rng, 0.9)  # TS:152
		arch["size"] = rng.range(0.7, 1.9)  # TS:153
		arch["hue"] = fmod(float(p["hue"]) + rng.range(-40.0, 40.0) + 360.0, 360.0)  # TS:154
		if String(p["kind"]) == "volcanic":  # TS:155
			arch["diet"] = "carnivore"
			arch["jaw"] = maxi(2, int(arch["jaw"]))
		if String(p["kind"]) == "ocean":  # TS:156
			arch["flagella"] = maxi(3, int(arch["flagella"]))
		# exactly ONE chance draw per species — the JS && / else-if
		# short-circuit (TS:157-158); a volcanic carnivore CAN flip back to
		# herbivore here (herbPull applies to every non-herb)
		if String(arch["diet"]) == "herbivore":
			if rng.chance(carn_pull):
				arch["diet"] = "carnivore"
		elif rng.chance(herb_pull):
			arch["diet"] = "herbivore"
		eco.add_species(arch, rng.range(4.0, 10.0))  # TS:159 — pop from the STAGE stream
	# bonus species appended AFTER the roster so their diet/size survive
	# the diet dial above untouched (TS:161-177)
	if float(weights.get("titan", 0.0)) >= 1.0:
		var t: Dictionary = MutationScript.mutate(
				GenomeScript.clone_genome(GenomeScript.default_genome()), rng, 0.9)
		t["size"] = 2.2
		t["diet"] = "carnivore"
		t["hue"] = fmod(float(p["hue"]) + 180.0, 360.0)
		eco.add_species(t, rng.range(4.0, 10.0))
	if float(weights.get("swarm", 0.0)) >= 1.0:
		var s: Dictionary = MutationScript.mutate(
				GenomeScript.clone_genome(GenomeScript.default_genome()), rng, 0.9)
		s["size"] = 0.55
		s["diet"] = "herbivore"
		s["flagella"] = maxi(4, int(s["flagella"]))
		s["hue"] = fmod(float(p["hue"]) + 60.0, 360.0)
		eco.add_species(s, rng.range(4.0, 10.0))
	return eco


# ---- update (TS:301-394 subset) ----------------------------------------------------

func update(dt: float, inp: Dictionary) -> void:
	time += dt  # TS:302
	var held: Array = inp.get("keys_held", [])
	var wx: float = float(inp.get("wx", 0.0))
	var wy: float = float(inp.get("wy", 0.0))
	var down: bool = bool(inp.get("down", false))

	# TS:306 — timeScale reads ffHold BEFORE the KeyF update: the first held
	# frame ticks dt·1, and the frame after release still ticks dt·26
	var timeScale := 26.0 if ffHold > 0.0 else 1.0
	if held.has("KeyF"):
		ffHold = 1.0
	else:
		ffHold = maxf(0.0, ffHold - dt)  # TS:307
	if ffHold > 0.0:
		# fast-forward: ecos churn; costs ship energy? no — it's a gift of the
		# Chaos Core. every planet shares the run's one world, so ONE mods
		# snapshot feeds them all (TS:309-311)
		var mods: Dictionary = WorldGenomeScript.eco_mods_from_world(ctx.world)
		for p in planets:
			if p["eco"] == null:
				continue  # TS:313
			p["eco"].mods = mods  # the wire that makes world-trait effects real
			var out: Dictionary = p["eco"].tick(dt * timeScale)  # TS:315
			for ex in out["extinctions"]:
				ctx.bump_extinction()  # TS:317 — ctx-direct (the tribe/civ precedent)
				if p["colony"] != null:
					_fire("hud_toast", ["%s went extinct on %s" % [String(ex["name"]), String(p["name"])],
						"chaos", "💀"])  # TS:318
			for newsp in out["speciations"]:
				if bool(p["scanned"]):
					_fire("hud_toast", ["%s evolves on %s" % [String(newsp["name"]), String(p["name"])],
						"chaos", "🧬"])  # TS:321
			if p["colony"] != null:
				p["colony"]["generations"] = float(p["colony"]["generations"]) + dt * timeScale / 30.0  # TS:323

	# ship control: thrust toward cursor (TS:327-342)
	var dx := 0.0
	var dy := 0.0
	if down and not uiHold:
		dx = wx - sx
		dy = wy - sy
		var d := sqrt(dx * dx + dy * dy)
		if d < 20.0:  # the deadzone
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
	thrust = 1.0 if dl > 0.0 else 0.0
	if dl > 0.0:
		shipAngle = atan2(dy, dx)

	var accel := 420.0  # TS:344
	svx += dx * accel * dt
	svy += dy * accel * dt
	var drag := exp(-1.1 * dt)  # TS:347
	svx *= drag
	svy *= drag
	sx += svx * dt
	sy += svy * dt

	# engine particles — the chance short-circuits on thrust 0 (an idle frame
	# draws NOTHING from the stage stream) (TS:352-361)
	if thrust > 0.0 and rng.chance(dt * 40.0):
		var back := shipAngle + PI
		# RAW world coords — the stage fx pool draws in world space (task 4)
		_fire("fx_spawn", [{"x": sx + cos(back) * 14.0, "y": sy + sin(back) * 14.0,
			"vx": cos(back) * 120.0 + rng.range(-20.0, 20.0),
			"vy": sin(back) * 120.0 + rng.range(-20.0, 20.0),
			"ttl": 0.5, "size": 3.0, "kind": "dot", "color": _hsl(200.0, 1.0, 0.7), "drag": 3.0}])

	# planets orbit + colony growth (TS:363-374) — the ×0.4 reads ffHold
	# POST-update, so the slow orbit lands on the first held frame
	for p in planets:
		p["angle"] = float(p["angle"]) + float(p["orbitSpeed"]) * dt * (0.4 if ffHold > 0.0 else 1.0)  # TS:365
		p["x"] = cos(float(p["angle"])) * float(p["orbitR"])  # TS:366
		p["y"] = sin(float(p["angle"])) * float(p["orbitR"])  # TS:367
		if p["colony"] != null:
			# logistic growth — colonies settle toward a carrying capacity
			# instead of printing exponential billions (TS:370-372)
			var col: Dictionary = p["colony"]
			col["pop"] = float(col["pop"]) + dt * timeScale * 0.08 \
					* (1.0 + float(col["pop"]) * 0.01) * maxf(0.0, 1.0 - float(col["pop"]) / 120.0)

	# sun danger (TS:376-382) — vecDist inlined (the civ precedent)
	var sun_d := sqrt(pow(sx - float(sun["x"]), 2.0) + pow(sy - float(sun["y"]), 2.0))
	if sun_d < float(sun["r"]) + 60.0 and invuln <= 0.0:
		shp -= 30.0 * dt
		hurtT = 1.0
		_fire("cam_shake", [4.0, 0.2])  # TS:381

	# hull regen near your thriving colonies (TS:384-389) — the invuln/hurtT
	# decays and the ship-death check are task 2's (TS:591/605-606)
	for p in planets:
		if p["colony"] != null and float(p["colony"]["pop"]) >= 5.0 \
				and sqrt(pow(sx - float(p["x"]), 2.0) + pow(sy - float(p["y"]), 2.0)) < float(p["r"]) + 150.0:
			shp = minf(shpMax, shp + 8.0 * dt)


# ---- debug seams -------------------------------------------------------------------

## Debug/test access to internal sim state (mirrors civ_sim.debug_state; the
## bot law's documented read surface).
func debug_state() -> Dictionary:
	return {"planets": planets, "cargo": cargo, "abductCount": abductCount,
		"time": time, "sx": sx, "sy": sy, "svx": svx, "svy": svy, "shp": shp,
		"shpMax": shpMax, "shipAngle": shipAngle, "thrust": thrust, "invuln": invuln,
		"ffHold": ffHold, "deckSeed": deckSeed, "finale": finale,
		"endingDone": endingDone, "endingDismissed": endingDismissed}


## Test/debug: seed colonies on the first three non-barren uncolonized planets
## (TS:1275-1287 — the docstring says 'three nearest lush worlds' but the code
## walks planet ORDER; pinned as coded). Persists when done.
func debug_seed_colonies() -> void:
	var seeded := 0
	for p in planets:
		if seeded >= 3:
			break
		if String(p["kind"]) == "barren" or p["colony"] != null:
			continue
		if p["eco"] == null:
			p["eco"] = EcoScript.new(rng.branch())
		var g: Dictionary = GenomeScript.clone_genome(GenomeScript.default_genome())
		p["eco"].add_species(g, 6.0, {"kin": true, "name": "%s (seed)" % NamesScript.species_name(rng)})
		p["colony"] = {"pop": 1.0, "generations": 0.0}
		seeded += 1
	persist_colonies()


# ---- internals -----------------------------------------------------------------------

## TS num(v, min) (SpaceStage.ts:208) — a numeric JSON value strictly above
## the min, else null. Number.isFinite("50") is false — the port type-checks
## before float() (GDScript's float() WOULD parse it; the civ precedent).
static func _num(v: Variant, min_v: float = -INF) -> Variant:
	if (v is float or v is int) and is_finite(float(v)) and float(v) > min_v:
		return float(v)
	return null


## TS Number.isFinite — a numeric JSON value only.
static func _fin(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


## TS gfx/renderer.ts hsl(): `hsl(H S% L% / A)` with toFixed(0) rounding
## (the cell_sim precedent — the fx pool stores the STRING; renderer.gd's
## css_color parses it at draw time).
func _hsl(h: float, s: float, l: float, a: float = 1.0) -> String:
	return "hsl(%d %d%% %d%% / %.2f)" % [floori(h + 0.5), floori(s * 100.0 + 0.5),
			floori(l * 100.0 + 0.5), a]
