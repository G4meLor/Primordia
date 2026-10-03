## SPACE STAGE sim core — the finale/sandbox system as a headless RefCounted.
## PART 1 (task 1): all state fields, the constructor (the stage rng branch +
## the chaos scheduler on a SECOND branch + deckSeed + generateSystem), the
## per-planet ecosystems (makePlanetEco — the archetype diet dial), the onEnter
## C1 gate + the FULL restore whitelist, persistColonies, and the update
## subset: the fast-forward block, ship control (cursor thrust + WASD), engine
## particles, planet orbits + colony logistic growth, sun danger + hull regen.
## PART 2 (task 2, TS:391-632 + the private methods): the near-planet panel
## interaction dispatch (the disabled-button-owns-click rule + the uiHold
## write side), black holes, pirates (chase + click-to-shoot), the R/G/V keys
## and the beam countdown, the chaos update with the FULL ctx incl. onEnd (the
## tribute unpaid→pirates rule), the finale/ending state machine, ship death,
## the cooldown decays, the 5 s persist cadence, and the methods
## nearestPlanet/tryAbduct/finishAbduct/seedNearest/mergeCargo/
## borrowedFleshGraft/spawnPirates/spawnBlackHole/demandTribute/payTribute/
## repairHull/scanPlanet. The render pass (:885+) and the stage-side hook
## bindings are task 4/5's.
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
##              Keys PART 2 fires: hud_banner(data), hud_float_world(x, y,
##              text, color, size), hud_set_abilities(list), audio_play(name,
##              vol, pan — the TS audio core is its own task), fx_burst(x, y,
##              n, opts — the sim replays the TS burst rng draws, the
##              cell_sim precedent), set_cursor(state), plus the storyteller
##              seam get_gap_bias/get_mood/get_warn_scale/
##              storyteller_note_chaos_event (the civ wiring). go_to/save_all
##              exist for parity but neither part fires them.
## No Input singleton reads: update(dt, inp) takes the M2 input SNAPSHOT and
## reads keys_held (KeyF hold, WASD/arrows) + keys_pressed (R/G/V canonical)
## + down/wx/wy (cursor thrust) + mx/my (the panel rects, screen space) +
## clicked/take_click (the panel and pirate-click dispatches consume via
## inp["take_click"] = true — Dictionaries pass by reference, so the take is
## visible to every later read this frame, the TS takeClick semantics).
## The camera feed + the fx-pool steps + the world-pointer recompute
## (TS:616-623) stay SCENE-SIDE (task 5 binds them right after sim.update —
## the cell_sim precedent: the sim never touches cam; the stage runs the
## block in the TS order).
## The chaos scheduler rides a SECOND branch of the stage rng (TS:98) holding
## the world-parameterized space deck (space_events.gd — the spaceEvents.ts
## port): 4 baseline defs + the nebula_flip/pirate_lull variants the world
## genome gates in. The factory draws NOTHING from any stream (the M5
## draw-nothing ruling; the deck's one Math.random site — the pirate count —
## rides the scheduler's own rng in-stream, the M4 storm precedent).
## chaos.update receives the FULL ctx incl. onEnd (TS:519-548) — the tribute
## unpaid→pirates rule; the deck def itself carries no end (the deck/ctx
## split, documented in space_events.gd's header).
## The panel rects (panel_rects, TS:1192) are written by the STAGE each frame
## before update (task 5's render pass); the sim only READS them — an empty
## array no-ops the dispatch ladder gracefully (clicks pass through to the
## pirate shooting).
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
##  - the panel dispatch: even a DISABLED button owns its click (:412-415) —
##    greyed-out presses must not fall through and thrust the ship away;
##    uiHold is written ONLY on click frames (:431) and cleared on !isDown
##    (:434); panel clicks outrank pirate shooting (:391 block order)
##  - tryAbduct checks DISTANCE FIRST (:646-647) — a full-cargo message from
##    out of range teaches the wrong lesson
##  - finishAbduct filters candidates to pop ≥ 1 (:676) — pop-0 leftovers must
##    not stay farmable forever (the infinite-DNA faucet)
##  - the last-member abduct is a player-caused extinction counted HERE (it
##    never passes through eco.tick, TS:692-696)
##  - the beamT countdown is NOT clamped (:503) — it lands negative and stays
##    there until the next tryAbduct resets it
##  - a graft NEVER downgrades (:786) — raised ≤ cur tries the next lineage
##  - ship death keeps the cargo (:589-590) and skips the DNA bill post-ending
##    (:587); the black-hole cull radius 700 must exceed the 600 pull radius
##    (:595-597); finishAbduct flushes the save (the 60s autosave lag, :706)
##  - splice/jettison costs DNA (:737-738) — free splices + free abducts were
##    a 395 DNA/min AFK faucet; the re-survey trickle is cooled by resurveyCd
##    (:1246-1251, an unbounded mash measured ~720 DNA/min)
##  - the pirate ttl reads `pirateTtl[pi] ?? 40` (:457) — a desynced array
##    reads the 40 default
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
##  - the abductCount ledger reads numerically (`?? 0` + the JS string-concat
##    pathology for a hand-corrupted "0" value is unreachable through the
##    real write path — the ledger is sim-written and JSON-restored, and JSON
##    numbers stay numbers); the port numeric-guards instead.
##  - the graft's `child[part.def.gene] as number` on a MISSING gene reads NaN
##    in TS (NaN ≤ NaN false → the graft fires with NaN); unreachable for
##    real children (crossover outputs are clamped full genomes) — the port
##    reads 0.0 via .get().
## Documented debug seam surface (bot parity law's exception list, the civ
## analog of tribe's debug_grant): debug_state() (read) +
## debug_seed_colonies() (TS:1275-1287, the task-6 bot's colony leg). No
## debug_set_ship — PART 1's tests set the ship fields directly; task 6 may
## add it for bot legs (any addition gets documented here). debug_state also
## exposes the part-2 machine fields: pirates, blackHoles, beamT,
## tributeDemand, resurveyCd, pirateLull, persistT, endingT, dismissT.
class_name SpaceSim
extends RefCounted

const ChaosScript := preload("res://src/game/chaos.gd")
const SpaceEventsScript := preload("res://src/game/space/space_events.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const MutationScript := preload("res://src/evo/mutation.gd")
const NamesScript := preload("res://src/evo/names.gd")
const PartsScript := preload("res://src/evo/parts.gd")

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
# position on a SECOND rng.branch(); the deck is space_events.gd's
# make_space_chaos_events(ctx.world) — draw-free at build (the M5 ruling).
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
# panel-interaction block below (TS:431/434)
var uiHold := false
# TS:280 — the 5 s auto-persist tick is task 2's (TS:610-613); the field rides
var persistT := 0.0
# TS:1192 — the planet-panel button rects, written by the STAGE each frame
# before update (task 5's render pass); the sim only READS them here. Rows:
# {action: String, enabled: bool, r: {x, y, w, h}}. Empty array = no panel —
# the dispatch ladder no-ops gracefully (clicks pass through to the pirates).
var panel_rects: Array = []


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


## The deck factory (spaceEvents.ts:49) — the world-parameterized space deck
## (space_events.gd). Draws nothing from any stage rng: the nebula/calm gates
## read the world genome only and fold into the weight Callables at build time
## (the M5 draw-nothing ruling — the scheduler construction stays TS-aligned).
func _make_deck() -> Array:
	return SpaceEventsScript.make_space_chaos_events(ctx.world)


# ---- stage lifecycle (TS:181-297) --------------------------------------------------

func on_enter() -> void:
	# C1: a CONTINUE/NEW LIFE landing on a different world rebuilds the deck
	# folding the NEW world in (TS:182-186)
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

	# hull regen near your thriving colonies (TS:384-389)
	for p in planets:
		if p["colony"] != null and float(p["colony"]["pop"]) >= 5.0 \
				and sqrt(pow(sx - float(p["x"]), 2.0) + pow(sy - float(p["y"]), 2.0)) < float(p["r"]) + 150.0:
			shp = minf(shpMax, shp + 8.0 * dt)

	# ---- near-planet interactions (TS:391-434) — panel clicks outrank pirate
	# shooting, so this block runs BEFORE the pirate loop
	var near0: Variant = nearest_planet()  # TS:392
	if near0 != null and _dist_ship(near0) < float(near0["r"]) + 130.0:
		var mx: float = float(inp.get("mx", 0.0))
		var my: float = float(inp.get("my", 0.0))
		# hover feedback BEFORE any click — pointer only showed mid-click before
		# (TS:394-403)
		for b in panel_rects:
			if bool(b["enabled"]) and _in_rect(mx, my, b["r"]):
				_fire("set_cursor", ["pointer"])  # TS:399
				break
		if _was_clicked(inp):  # TS:404
			var consumed := false
			var over_panel := false
			for b in panel_rects:
				var inside: bool = _in_rect(mx, my, b["r"])  # TS:409
				if inside and bool(b["enabled"]):
					_fire("set_cursor", ["pointer"])  # TS:410
				if not inside:
					continue
				# even a DISABLED button owns its click — greyed-out presses must
				# not fall through and thrust the ship out of interaction range
				# (TS:412-414)
				over_panel = true
				if not bool(b["enabled"]):
					continue
				_take_click(inp)  # TS:416
				consumed = true
				_fire("audio_play", ["click", 1.0, 0.0])  # TS audio.play('click') — audio core: its own task
				match String(b["action"]):  # TS:419-428 — the else-if chain
					"abduct":
						try_abduct()
					"seed":
						seed_nearest()
					"scan":
						scan_planet(near0)
					"repair":
						repair_hull()
					"merge":
						merge_cargo()
					"jettison":
						var dropped: Variant = cargo.pop_back()  # TS:425 — JS .pop() = Godot pop_back
						if dropped != null:
							_fire("hud_toast", ["%s released back to the void" % String(dropped["name"]),
								"info", "🗑"])  # TS:426
						persist_colonies()  # TS:427
				break  # TS:429 — the first inside rect dispatches and stops the loop
			uiHold = (consumed or over_panel) and bool(inp.get("down", false))  # TS:431
	if not bool(inp.get("down", false)):
		uiHold = false  # TS:434

	# black holes pull + damage (TS:436-452)
	for bh in blackHoles:
		var bd: float = _dist_ship(bh)
		if bd < 600.0 and bd > 0.001 and invuln <= 0.0:
			var pull: float = 24000.0 / maxf(80.0, bd)
			svx += ((float(bh["x"]) - sx) / bd) * pull * dt
			svy += ((float(bh["y"]) - sy) / bd) * pull * dt
		if bd < 40.0 and invuln <= 0.0:
			shp -= 60.0 * dt
			hurtT = 1.0
		bh["x"] = float(bh["x"]) + float(bh["vx"]) * dt
		bh["y"] = float(bh["y"]) + float(bh["vy"]) * dt
		bh["ttl"] = float(bh["ttl"]) - dt
	var holes_alive: Array = []
	for bh in blackHoles:
		if float(bh["ttl"]) > 0.0:
			holes_alive.append(bh)
	blackHoles = holes_alive  # TS:452 filter

	# pirates chase (with lifetime so sieges end) (TS:454-498)
	var pi := pirates.size() - 1
	while pi >= 0:
		var p: Dictionary = pirates[pi]
		# TS `pirateTtl[pi] ?? 40` — a desynced ttl array reads the default
		var ttl: float = (float(pirateTtl[pi]) if pi < pirateTtl.size() else 40.0) - dt
		if ttl <= 0.0:
			pirates.remove_at(pi)
			pirateTtl.remove_at(pi)
			_fire("hud_toast", [tr("The siege lifts — pirates give up"), "good", "🌿"])  # TS:461
			pi -= 1
			continue
		if pi < pirateTtl.size():
			pirateTtl[pi] = ttl
		else:
			pirateTtl.append(ttl)  # TS `this.pirateTtl[pi] = ttl` — an index assign past the end extends the array
		var pd: float = _dist_ship(p)
		if pd > 30.0:
			p["vx"] = float(p["vx"]) + ((sx - float(p["x"])) / pd) * 300.0 * dt
			p["vy"] = float(p["vy"]) + ((sy - float(p["y"])) / pd) * 300.0 * dt
		var drag_p := exp(-1.4 * dt)
		p["vx"] = float(p["vx"]) * drag_p
		p["vy"] = float(p["vy"]) * drag_p
		p["x"] = float(p["x"]) + float(p["vx"]) * dt
		p["y"] = float(p["y"]) + float(p["vy"]) * dt
		p["gait"] = float(p["gait"]) + dt
		if pd < 60.0 and invuln <= 0.0 and not pirateLull:
			shp -= 14.0 * dt
			hurtT = maxf(hurtT, 0.5)
			if rng.chance(dt * 6.0):
				_fx_burst(sx, sy, 4, ["#ff8a5a"], {"speed": 120.0, "ttl": 0.4})  # TS:478
				_fire("audio_play", ["hit", 0.4, 0.0])  # TS audio.play('hit', 0.4) — audio core: its own task
		# shoot the pirate you actually CLICKED ON (TS:482-497)
		var click_d: float = sqrt(pow(wx - float(p["x"]), 2.0) + pow(wy - float(p["y"]), 2.0))
		if _was_clicked(inp) and click_d < 60.0:
			p["hp"] = float(p["hp"]) - 34.0
			_take_click(inp)  # TS:486
			_fire("audio_play", ["zap", 0.7, 0.0])  # TS audio.play('zap', 0.7) — audio core: its own task
			_fx_burst(float(p["x"]), float(p["y"]), 8, ["#ffe97a", "#9fd8ff"], {"speed": 140.0, "ttl": 0.5})
			if float(p["hp"]) <= 0.0:
				pirates.remove_at(pi)
				pirateTtl.remove_at(pi)
				_fire("hud_toast", [tr("Pirate destroyed! +30 DNA"), "good", "💥"])  # TS:492
				ctx.add_dna(30.0)  # TS:493
				_fx_burst(float(p["x"]), float(p["y"]), 20, ["#ff8a5a", "#ffd08a"], {"speed": 180.0, "ttl": 0.9})
				_fire("audio_play", ["boom", 0.6, 0.0])  # TS audio.play('boom', 0.6) — audio core: its own task
		pi -= 1

	# abduction (R — A was double-booked with strafe-left) (TS:500-507)
	var pressed: Array = inp.get("keys_pressed", [])
	if pressed.has("KeyR"):
		try_abduct()
	if beamT > 0.0:
		beamT -= dt  # NOT clamped — lands negative until the next tryAbduct (the verbatim read)
		if beamT <= 0.0 and beamTarget != null:
			finish_abduct(beamTarget)

	# gene lab key (G) (TS:509-512)
	if pressed.has("KeyG") and cargo.size() >= 2:
		merge_cargo()

	# pay the Void Empire's tribute (V) (TS:514-517)
	if pressed.has("KeyV") and tributeDemand > 0.0:
		pay_tribute()

	# chaos — the FULL ctx incl. onEnd (the tribute rule) (TS:519-548)
	update_chaos(dt)

	resurveyCd = maxf(0.0, resurveyCd - dt)  # TS:550

	# finale trigger: 3 thriving colonies (TS:552-559)
	var thriving := 0
	for p in planets:
		if p["colony"] != null and float(p["colony"]["pop"]) >= 20.0:
			thriving += 1
	if thriving >= 3 and finale == null and not endingDone:
		# spawn in clear space between sun and outermost orbit (TS:555)
		finale = {"x": 0.0, "y": -1900.0, "active": true, "t": 0.0}
		_fire("hud_banner", [{"title": "THE CHAOS CORE AWAKENS",
			"subtitle": "something pulses beyond the outer light", "kind": "chaos", "ttl": 6}])  # TS:557
		_fire("audio_play", ["ascend", 1.0, 0.0])  # TS audio.play('ascend', 1) — audio core: its own task
	if finale != null:
		finale["t"] = float(finale["t"]) + dt
		var fd: float = _dist_ship(finale)
		# a persistent bearing — the 6s banner was the only pointer to a core
		# spawning 1000px off-screen. Post-ending it swaps to a calm line
		# (the old one nagged forever over the sandbox) (TS:563-568). The TS
		# writes hud.showObjective every frame while the finale lives — the
		# hook fire is the sim-side analog.
		_fire("hud_show_objective", [tr("the core sleeps — the sandbox is yours") if endingDone
			else "THE CHAOS CORE PULLS — fly %dpx %s to the storm" % [roundi(fd),
			"up" if float(finale["y"]) < sy else "down"]])
		if fd < 60.0 and not endingDone:
			endingDone = true
			_fire("audio_play", ["ascend", 1.0, 0.0])  # TS:571
			persist_colonies()  # the win state hits disk immediately (TS:572)
	if endingDone:
		endingT += dt
		# the overlay used to be permanent — any input hands the sandbox back
		# (TS:577-581); wasClicked reads POST-take — a panel/pirate-consumed
		# click does not dismiss
		if not endingDismissed and (_was_clicked(inp) or not (pressed as Array).is_empty()):
			endingDismissed = true
			dismissT = endingT  # fade-out timer start

	# ship death (no DNA bill once the ending fired — you already won) (TS:584-602)
	if shp <= 0.0:
		shp = shpMax * 0.5
		var lost: int = 0 if endingDone else roundi(float(ctx.dna) * 0.15)
		ctx.add_dna(float(-lost))
		# cargo survives — deleting specimens too blocked seeding → blocked
		# thriving → blocked the ending (9-15 deaths/run at chaos) (TS:589-590)
		_fire("hud_toast", ["%s %d DNA" % [tr("Ship destroyed! Lost"), lost], "bad", "💀"])  # TS:591
		sx = 0.0
		sy = -900.0
		svx = 0.0
		svy = 0.0
		invuln = 4.0
		# cull radius must exceed the 600px pull radius or the hole that
		# killed you chain-kills the fresh respawn (TS:595-597)
		var holes_kept: Array = []
		for bh in blackHoles:
			if sqrt(pow(float(bh["x"]) - sx, 2.0) + pow(float(bh["y"]) - sy, 2.0)) > 700.0:
				holes_kept.append(bh)
		blackHoles = holes_kept
		pirates = []
		pirateTtl = []
		_fire("audio_play", ["boom", 1.0, 0.0])  # TS audio.play('boom', 1) — audio core: its own task
		_fire("cam_shake", [10.0, 0.8])  # TS:601

	# cooldowns (TS:604-606)
	invuln = maxf(0.0, invuln - dt)
	hurtT = maxf(0.0, hurtT - dt * 3.0)

	# keep the save current: planets/cargo persist every 5 s (TS:609-613)
	persistT += dt
	if persistT > 5.0:
		persistT = 0.0
		persist_colonies()

	# camera (TS:616-623 — follow(sx, sy, dt, 5), zoom 0.85, toWorld → setWorld)
	# and the fx pool steps (:622-623): scene-side, task 5 binds them right
	# after sim.update in the TS order (the cell_sim precedent — the sim never
	# touches cam).

	# hud ability slots (TS:626-631) — ONE list arg (the civ wiring shape)
	_fire("hud_set_abilities", [[
		{"key": "R", "icon": "🛸", "cd": 0.0, "active": beamT > 0.0},
		{"key": "F", "icon": "⏩", "cd": 0.0, "active": ffHold > 0.0},
		{"key": "G", "icon": "🧪", "cd": 0.0, "active": cargo.size() >= 2},
		{"key": "LMB", "icon": "🔫", "cd": 0.0},
	]])


# ---- debug seams -------------------------------------------------------------------

## Debug/test access to internal sim state (mirrors civ_sim.debug_state; the
## bot law's documented read surface — the part-2 machine fields documented
## in the header).
func debug_state() -> Dictionary:
	return {"planets": planets, "cargo": cargo, "abductCount": abductCount,
		"time": time, "sx": sx, "sy": sy, "svx": svx, "svy": svy, "shp": shp,
		"shpMax": shpMax, "shipAngle": shipAngle, "thrust": thrust, "invuln": invuln,
		"ffHold": ffHold, "deckSeed": deckSeed, "finale": finale,
		"endingDone": endingDone, "endingDismissed": endingDismissed,
		"pirates": pirates, "blackHoles": blackHoles, "beamT": beamT,
		"tributeDemand": tributeDemand, "resurveyCd": resurveyCd,
		"pirateLull": pirateLull, "persistT": persistT,
		"endingT": endingT, "dismissT": dismissT}


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


# ---- methods (TS:634-870 + :1233-1272) ----------------------------------------------

## TS nearestPlanet (:634-642) — the strict-min scan.
func nearest_planet() -> Variant:
	var best: Variant = null
	var bd := INF
	for p in planets:
		var d: float = _dist_ship(p)
		if d < bd:
			bd = d
			best = p
	return best


## TS tryAbduct (:644-670).
func try_abduct() -> void:
	if beamT > 0.0:
		return  # TS:645
	# distance FIRST — a full-cargo message from out of range teaches the
	# wrong lesson about why nothing happened (TS:646-647)
	var p: Variant = nearest_planet()
	if p == null:
		return
	if _dist_ship(p) > float(p["r"]) + 130.0:
		_fire("hud_toast", [tr("Fly closer to a planet to abduct"), "info", "🛸"])  # TS:651
		return
	if cargo.size() >= 4:
		_fire("hud_toast", [tr("Cargo full — SEED a world, SPLICE genes (G), or JETTISON from the planet panel"),
			"info", "📦"])  # TS:655
		return
	if p["eco"] == null:
		_fire("hud_toast", [tr("No life to abduct here"), "info", "🛸"])  # TS:659
		return
	var living: Array = p["eco"].living()
	if living.is_empty():
		_fire("hud_toast", [tr("No life to abduct here"), "info", "🛸"])  # TS:664
		return
	beamTarget = p
	beamT = 1.4
	_fire("audio_play", ["warp", 0.6, 0.0])  # TS audio.play('warp', 0.6) — audio core: its own task


## TS finishAbduct (:672-707).
func finish_abduct(p: Dictionary) -> void:
	if p["eco"] == null:
		return  # TS:673
	# only species with an actual member left can be abducted — pop-0
	# leftovers must not stay farmable forever (infinite-DNA faucet) (TS:674-675)
	var candidates: Array = p["eco"].living().filter(func(sp): return float(sp["pop"]) >= 1.0)
	if candidates.is_empty():
		_fire("hud_toast", [tr("Nothing left to abduct here"), "info", "🛸"])  # TS:678
		beamTarget = null
		return
	var sp: Dictionary = rng.pick(candidates)
	sp["pop"] = float(sp["pop"]) - 1.0
	# diminishing returns per species per planet — park-and-beam used to
	# print ~395 DNA/min (first catch +10, repeats +3) (TS:684-685)
	var key := "%s:%s" % [str(p["id"]), str(sp["id"])]
	# the ledger values are sim-written numbers restored through JSON; the TS
	# `?? 0` null-fallback + the string-concat pathology for a hand-corrupted
	# "0" is unreachable through the real write path — the port numeric-guards
	# (see the divergence note in the header)
	var repeats: float = float(abductCount[key]) \
			if abductCount.has(key) and (abductCount[key] is float or abductCount[key] is int) else 0.0
	abductCount[key] = repeats + 1.0
	var pay: int = 10 if repeats == 0.0 else 3
	if float(sp["pop"]) < 1.0:
		sp["pop"] = 0.0
		sp["extinct"] = true  # living getter filters this out — no re-farming
		# beaming up a species' last member wipes it from this world — that is
		# a player-caused extinction for the world-story counters (it never
		# passes through eco.tick, so this is the only place it gets counted)
		# (TS:692-696)
		ctx.bump_extinction()
		_fire("hud_toast", ["%s %s — %s" % [tr("Abducted:"), String(sp["name"]),
			tr("that species is now gone from this world")], "bad", "🛸"])  # TS:697
	else:
		_fire("hud_toast", ["%s %s +%d" % [tr("Abducted:"), String(sp["name"]), pay], "good", "🛸"])  # TS:699
	cargo.append({"genome": GenomeScript.clone_genome(sp["genome"]), "name": sp["name"]})  # TS:701
	ctx.add_dna(float(pay))  # TS:702
	ctx.discover(sp["genome"], String(sp["name"]), "space", bool(sp.get("kin", false)))  # TS:703
	_fire("audio_play", ["dna", 0.8, 0.0])  # TS audio.play('dna', 0.8) — audio core: its own task
	beamTarget = null
	persist_colonies()  # flush — the 60s autosave lagged catches by up to a minute (TS:706)


## TS seedNearest (:709-733).
func seed_nearest() -> void:
	var p: Variant = nearest_planet()
	if p == null or cargo.is_empty():
		return  # TS:711
	if _dist_ship(p) > float(p["r"]) + 130.0:
		_fire("hud_toast", [tr("Fly closer to seed"), "info", "🌱"])  # TS:713
		return
	if not ctx.spend_dna(20):
		_fire("hud_toast", [tr("Seeding costs 20 DNA"), "bad", "🌱"])  # TS:717
		return
	var item: Dictionary = cargo.pop_back()  # TS:720 — JS .pop() = Godot pop_back
	if p["eco"] == null:
		p["eco"] = EcoScript.new(rng.branch())  # TS:722 — ONE stage-stream draw
		p["eco"].flora_cap = 60.0 if String(p["kind"]) == "volcanic" else 100.0  # TS:723
		p["eco"].flora = float(p["eco"].flora_cap) * 0.6  # TS:724
		p["kind"] = "lush" if String(p["kind"]) == "barren" else String(p["kind"])  # TS:725
	var sp: Dictionary = p["eco"].add_species(item["genome"], 5.0, {"kin": true, "name": item["name"]})  # TS:727
	ctx.discover(sp["genome"], String(sp["name"]), "space", true)  # TS:728
	if p["colony"] == null:
		p["colony"] = {"pop": 0.0, "generations": 0.0}  # TS:729 — the ?? keeps an existing one
	_fire("hud_banner", [{"title": "%s SEEDED" % String(p["name"]),
		"subtitle": "%s takes its first breath" % String(item["name"]), "kind": "reward"}])  # TS:730
	_fire("audio_play", ["levelup", 1.0, 0.0])  # TS audio.play('levelup', 1) — audio core: its own task
	persist_colonies()  # TS:732


## TS mergeCargo (:735-770).
func merge_cargo() -> void:
	if cargo.size() < 2:
		return  # TS:736
	# splicing costs DNA — free splices + free abducts were a 395 DNA/min AFK faucet (TS:737)
	if not ctx.spend_dna(15):
		_fire("hud_toast", [tr("Gene splice costs 15 DNA"), "bad", "🧪"])  # TS:739
		return
	var a: Dictionary = cargo[0]
	var b: Dictionary = cargo[1]
	# M1/M2 run as the post-crossover table (crossover itself is untouched):
	# wild-mutation worlds run the recessive table hotter; defect_rate is the
	# TOTAL per-splice budget (never additive — catalog IV) (TS:744-746)
	var info: Dictionary = {"anomaly": null, "defect": null}
	var wild: bool = WorldGenomeScript.world_has(ctx.world, "wild_mutations")
	var child: Dictionary = MutationScript.crossover(a["genome"], b["genome"], rng, 0.3, {
		"anomalyChance": 0.15 if wild else 0.10,  # TS:750
		"defectRate": 0.3 if wild else 0.2,  # TS:751
		# I-q2: mutation_moon's rate_add rides the fresh-mutation step (TS:752-753)
		"bias": {"rate_add": WorldGenomeScript.world_num(ctx.world, "mutation_rate_add", 0.0)},
		"info": info,
	})
	var child_name := "%s (spliced)" % NamesScript.species_name(rng)  # TS:756
	cargo = cargo.slice(2)
	cargo.append({"genome": child, "name": child_name})  # TS:758
	if info["anomaly"] != null:
		var ak: String = String(info["anomaly"]["kind"])
		_fire("hud_toast", ["%s — %s" % [tr("UNEXPECTED EXPRESSION"),
			tr(String(MutationScript.ANOMALY_NAMES[ak]))], "chaos", "🧬"])  # TS:760
	if info["defect"] != null:
		var dk: String = String(info["defect"]["kind"])
		_fire("hud_toast", ["%s %s" % [tr("Defective splice:"),
			tr(String(MutationScript.DEFECT_NAMES[dk]))], "bad", "⚠️"])  # TS:763
	_fire("hud_toast", ["%s %s!" % [tr("Gene splice:"), child_name], "chaos", "🧪"])  # TS:765
	_fire("audio_play", ["levelup", 0.9, 0.0])  # TS audio.play('levelup', 0.9) — audio core: its own task
	ctx.discover(child, child_name, "space")  # TS:767 — kin defaults false
	borrowed_flesh_graft(child)  # TS:768
	persist_colonies()  # TS:769


## borrowed_flesh: the ONE graft slot — one part value of an extinct species
## joins the splice result. Once per run (flag-guarded); the slot only
## exists while the combo is live and a grafted species exists in the
## bestiary. (TS:772-792)
func borrowed_flesh_graft(child: Dictionary) -> void:
	if not WorldGenomeScript.combo_active(ctx.world, "borrowed_flesh"):
		return  # TS:778 — the guard precedes the shuffle: no draw when off
	var fg: Variant = ctx.flags.get("borrowed_flesh_graft")
	if fg is bool and bool(fg):
		return  # TS `=== true` — the strict flag read
	var extinct: Array = []
	for entry in ctx.bestiary.values():
		if bool(entry["extinct"]):
			extinct.append(entry)  # TS:779
	for src in rng.shuffled(extinct):
		var part: Variant = PartsScript.standout_part(src["genome"])
		if part == null:
			continue  # TS:782
		var gene: String = String(part["def"]["gene"])
		var bound: Variant = GenomeScript.GENE_BOUNDS.get(gene)
		# TS `child[part.def.gene] as number` reads NaN on a missing gene —
		# unreachable for real children (crossover outputs are clamped full
		# genomes); the port reads 0.0 (see the divergence note in the header)
		var cur: float = float(child.get(gene, 0.0))
		var bound_max: float = float(part["level"]) if bound == null else float(bound["max"])
		var raised: float = PartsScript.graft_value(cur, float(part["level"]), bound_max)
		if raised <= cur:
			continue  # a graft never downgrades — try the next lineage (TS:786)
		child[gene] = raised
		ctx.flags["borrowed_flesh_graft"] = true
		_fire("hud_toast", ["%s %s ← %s" % [tr("Borrowed flesh:"), tr(String(part["def"]["name"])),
			String(src["name"])], "good", "🫱"])  # TS:789
		return


## TS spawnPirates (:794-810).
func spawn_pirates(n: int) -> void:
	if pirates.size() >= 5:
		return  # TS:795
	n = mini(n, 5 - pirates.size())  # TS:796
	var life := 40.0
	for i in n:
		var a: float = rng.next() * TAU  # TS:799
		pirates.append({
			"x": sx + cos(a) * 700.0, "y": sy + sin(a) * 700.0,
			"vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0,
		})
		pirateTtl.append(life)
	_fire("audio_play", ["alarm", 0.9, 0.0])  # TS audio.play('alarm', 0.9) — audio core: its own task


## TS nebulaFlip (:812-827) — chaos variant (nebula_flip): a mutation nebula
## washes one living world — two forced speciations there.
func nebula_flip() -> void:
	var living: Array = []
	for p in planets:
		if p["eco"] != null:
			living.append(p)
	if living.is_empty():
		_fire("hud_toast", [tr("The nebula washes only dead rock."), "info", "🌌"])  # TS:816
		return
	var p: Dictionary = rng.pick(living)  # TS:819 — ONE stage-stream draw
	# TS: [forceSpeciation(), forceSpeciation()].filter(sp => sp !== null).length
	# — both calls always run (the array literal evaluates both)
	var made := 0
	for i in 2:
		if p["eco"].force_speciation() != null:
			made += 1
	if made == 0:
		_fire("hud_toast", ["%s %s — %s" % [tr("The nebula passes over"),
			String(p["name"]), tr("nothing takes hold.")], "info", "🌌"])  # TS:821
		return
	_fire("hud_toast", ["%s %d %s %s!" % [tr("The nebula seeds"), made,
		tr("new species on"), String(p["name"])], "chaos", "🌌"])  # TS:823


## TS pirateLullBegin (:829-833) — chaos variant (pirate_lull): pirates hold
## fire while the calm lasts.
func pirate_lull_begin() -> void:
	pirateLull = true
	_fire("hud_toast", [tr("The pirates pull back — an uneasy quiet falls."), "good", "🕊"])  # TS:831


## TS pirateLullEnd (:835-838) — the pirate_lull def's END hook clears the lull.
func pirate_lull_end() -> void:
	pirateLull = false


## TS spawnBlackHole (:840-849).
func spawn_black_hole() -> void:
	var a: float = rng.next() * TAU
	blackHoles.append({
		"x": sx + cos(a) * 1000.0, "y": sy + sin(a) * 1000.0,
		"vx": rng.range(-12.0, 12.0), "vy": rng.range(-12.0, 12.0), "ttl": 45.0,
	})


## TS demandTribute (:851-859).
func demand_tribute(amount: float) -> void:
	tributeDemand = amount
	_fire("hud_banner", [{"title": "THE VOID EMPIRE DEMANDS TRIBUTE",
		"subtitle": "pay %s DNA (press V) or face the raid" % str(amount),
		"kind": "danger", "ttl": 8}])  # TS:853-857
	_fire("audio_play", ["alarm", 1.0, 0.0])  # TS audio.play('alarm', 1) — audio core: its own task


## TS payTribute (:861-870).
func pay_tribute() -> void:
	if tributeDemand <= 0.0:
		return  # TS:862
	if float(ctx.dna) >= tributeDemand:
		ctx.add_dna(-tributeDemand)
		_fire("hud_toast", [tr("Tribute paid. The Void Empire is satisfied… for now."), "info", "📦"])  # TS:865
		tributeDemand = 0.0
	else:
		_fire("hud_toast", [tr("Not enough DNA — the raid is coming!"), "bad", "⚔️"])  # TS:868


## TS solarFlare (:872-884).
func solar_flare() -> void:
	shp = maxf(10.0, shp - 20.0)  # TS:873 — the 10 floor
	hurtT = 1.0
	_fire("cam_shake", [7.0, 0.8])  # TS:875 camShakeFor(7, 0.8)
	_fire("hud_toast", [tr("Solar flare scorches your hull!"), "bad", "☀️"])  # TS:876
	for p in planets:
		if p["eco"] != null:
			for sp in p["eco"].living():
				sp["pop"] = maxf(0.5, float(sp["pop"]) * 0.7)  # TS:880 — the 0.5 floor
	_fire("audio_play", ["boom", 0.8, 0.0])  # TS audio.play('boom', 0.8) — audio core: its own task


## TS repairHull (:1233-1242).
func repair_hull() -> void:
	if shp >= shpMax:
		return  # TS:1234
	if not ctx.spend_dna(50):
		_fire("hud_toast", [tr("Not enough DNA"), "bad", "🧬"])  # TS:1236
		return
	shp = shpMax
	_fire("audio_play", ["heal", 0.9, 0.0])  # TS audio.play('heal', 0.9) — audio core: its own task
	_fire("hud_toast", [tr("Hull fully repaired"), "good", "🔧"])  # TS:1241


## TS scanPlanet (:1244-1272).
func scan_planet(p: Dictionary) -> void:
	if bool(p["scanned"]):
		# re-survey pays a trickle — the only legal income for a pacifist
		# with full cargo and no DNA (was a total softlock). Cooled: an
		# unbounded mash measured ~720 DNA/min. (TS:1246-1248)
		if resurveyCd > 0.0:
			_fire("hud_toast", [tr("Survey instruments recharging"), "info", "📡"])  # TS:1250
			return
		resurveyCd = 4.0
		ctx.add_dna(3.0)  # TS:1254-1255
		_fire("hud_float_world", [float(p["x"]), float(p["y"]) - float(p["r"]) - 14.0,
			"+3 %s" % tr("survey"), "#8fd0ff", 12.0])  # TS:1256
		_fire("audio_play", ["dna", 0.4, 0.0])  # TS audio.play('dna', 0.4) — audio core: its own task
		persist_colonies()  # TS:1258
		return
	p["scanned"] = true
	if p["eco"] != null:
		for sp in p["eco"].living():
			ctx.discover(sp["genome"], String(sp["name"]), "space", bool(sp.get("kin", false)))  # TS:1263-1264
		ctx.add_dna(15.0)  # survey pay so pacifist runs fund repairs (TS:1266)
		_fire("hud_toast", ["%s +15" % tr("Scan complete: %d species on %s"
			% [p["eco"].living().size(), String(p["name"])]), "good", "📡"])  # TS:1267
	else:
		_fire("hud_toast", ["Scan complete: %s is lifeless — bring life!" % String(p["name"]),
			"info", "📡"])  # TS:1269
	_fire("audio_play", ["dna", 0.7, 0.0])  # TS audio.play('dna', 0.7) — audio core: its own task


## TS:519-548 — chaos.update with the FULL ctx incl. onEnd (the civ wiring
## lacks onEnd; space's tribute rule needs it). The storyteller reference
## arrives through hooks (get_gap_bias / get_mood / get_warn_scale — the civ
## pattern), noteChaosEvent through storyteller_note_chaos_event. The onEnd
## reads the def id: an UNPAID tribute demand ends in 3 pirates (the deck
## def itself carries no end — the deck/ctx split, space_events.gd's header).
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
		# TS `if (def.warn)` (:527) — effective_warn keeps the static-key
		# semantics (the civ/creature/tribe wiring shape)
		if ChaosScript.effective_warn(def):
			_fire("hud_banner", [{"title": ChaosScript.effective_warn(def), "kind": "danger", "ttl": 2.4}])  # TS:528
			_fire("audio_play", ["alarm", 0.5, 0.0])  # TS audio.play('alarm', 0.5) — audio core: its own task
	var on_apply := func(def) -> void:
		_fire("hud_banner", [{"title": def["name"], "kind": "chaos"}])  # TS:533
		ctx.add_chaos(0.03)  # TS:534
		# world_temperament pacing: warned events going live are the
		# high-severity marker (cradle grace / lean cycles / wildcard streak)
		_fire("storyteller_note_chaos_event", [float(ctx.playtime)])  # TS:537
	var on_end := func(def) -> void:
		# the tribute rule (TS:539-547): if unpaid → pirates!
		if String(def.get("id", "")) == "tribute":
			if tributeDemand > 0.0:
				spawn_pirates(3)
				tributeDemand = 0.0
	chaos.update(dt, self, {
		"chaos": float(ctx.chaos), "karma": float(ctx.karma), "stageTime": time,
		"gapMult": ctx.chaos_gap_mult() * gap_bias,
		"mood": mood,
		"warnScale": warn_scale,  # bio_tell bucket (TS:524)
	}, {
		"onWarn": on_warn,
		"onApply": on_apply,
		"onEnd": on_end,
	})


# ---- internals -----------------------------------------------------------------------

## TS vecDist inlined against the ship (the civ precedent).
func _dist_ship(p: Dictionary) -> float:
	return sqrt(pow(float(p["x"]) - sx, 2.0) + pow(float(p["y"]) - sy, 2.0))


## TS:398/409 — the screen-space panel-rect hit (mx/my from the snapshot).
func _in_rect(mx: float, my: float, r: Dictionary) -> bool:
	return mx >= float(r["x"]) and mx <= float(r["x"]) + float(r["w"]) \
			and my >= float(r["y"]) and my <= float(r["y"]) + float(r["h"])


## TS input.wasClicked() — the snapshot's clicked minus the pre-taken flag
## (the cell_sim read convention).
func _was_clicked(inp: Dictionary) -> bool:
	return bool(inp.get("clicked", false)) and not bool(inp.get("take_click", false))


## TS input.takeClick() — sets the pre-taken flag; Dictionaries pass by
## reference, so the consume is visible to every later read this frame.
func _take_click(inp: Dictionary) -> void:
	inp["take_click"] = true


## The TS fx.burst(x, y, n, rng, opts) — the sim replays the TS rng draws
## (particles.ts burst: ang/sp/color/ttl/size per particle) and ships the
## sampled particles in the hook payload (the cell_sim precedent).
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
