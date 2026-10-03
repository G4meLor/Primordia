# M6 Space Stage Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full TS-verbatim port of the Space stage — the finale AND the sandbox (ship flight, per-planet ecosystems, abduct/seed/splice gene lab, pirates/black holes/the Void Empire, fast-forward evolution, the Chaos Core finale) — playable, §5.4-gated, tagged `space-parity-m6`.

**Architecture:** Mirror the tribe milestone's two-part sim split (tribe was 1431 lines → 8 tasks): `space_sim.gd` (RefCounted, hooks-Dictionary, `update(dt, inp)` M2 snapshot) in TWO tasks (state+system+ecosystems+persist, then interactions+hazards+finale) + `space_events.gd` (6 defs — the FIRST deck def with an `end` hook) + `space_stage.gd` (Node2D: world-space cam render + the screen HUD + the planet panel) in TWO tasks + wiring (registration, `spaceWorld` save/continue, the civ-victory landing, i18n) + bot/probes/PARITY-M6/wrap.

**Tech Stack:** Godot 4.2.2 + GDScript typed; the frozen TS authority at ~/Desktop/RD/Spore (read in full for this plan: src/game/space/SpaceStage.ts 1288 lines + spaceEvents.ts 77 lines, 2026-10-01 state).

**Spec:** docs/specs/2026-09-29-native-migration-design.md §5.4 (same 4 criteria gates, space flavor).

**Milestone ruling:** spec §5 doctrine — M5 = Civ ✅ (tag `civ-parity-m5` @ af22996), **M6 = Space** (this plan, tag `space-parity-m6`), then M7 = CI/release + repo overwrite. Space is the LAST stage: its finale is IN-STAGE (no further go_to) — the ending overlay + sandbox persistence is the terminal state.

## Global Constraints

- **Parity-pin porting:** TS logic/constants/draw-order 1:1; every divergence documented in the file header + report; rng draw order sacred (lazy where TS lazy; TS `Math.random()` sites → the stage rng IN-STREAM with a header note + replay pin — the space surface has these rng sites: constructor system generation (orbitR/angle/orbitSpeed/r/hue/ring/name per planet + per-planet eco rosters, SpaceStage.ts:103-179), engine particles chance dt·40 (:353), pirate damage burst chance dt·6 (:477), pirate spawn angle rng.next()·TAU (:799), black-hole spawn angle + vx/vy (:841-845), abduct rng.pick (:682), nebulaFlip rng.pick (:820), graft rng.shuffled (:780), splice child name speciesName (:756), and **the deck's pirate-count draw `2 + Math.floor(Math.random()·2)` (spaceEvents.ts:18) — the ONE Math.random site; port it to the DECK/SCHEDULER rng in-stream with the M4 storm precedent's header note + replay pin**). The stage rng is a BRANCH of the context rng taken in the constructor (TS :97); the chaos scheduler takes a SECOND branch (:98) — the boot-order branch becomes **5 branches** (cell → creature → tribe → civ → space); T6 updates the exactly-N pin.
- **Save-wire camelCase TS-verbatim:** `spaceWorld` blob (SpaceStage.ts:282-297) rides `flags.spaceWorld` — planets[{id,name,orbitR,angle,orbitSpeed,r,hue,kind,ring,scanned,colony{pop,generations},eco}], cargo[{genome,name}], abductCount, endingDone, endingDismissed. The restore whitelist (TS :190-267) is LOAD-BEARING port verbatim: shapes check (array + length match), per-field numeric sanity (`num(v, min)` — finite + > min BEFORE assign: r>0, orbitR, orbitSpeed, angle, hue), name string, kind enum, ring bool, **colony + scanned ride the whitelist** (the round-4 hardening dropped them and wiped the 3-thriving gate — TS :218-225 comment), eco `instanceof` guard + **fromJSON ALWAYS takes the saved eco** (the old `!p.eco` check re-rolled rosters — TS :234-240), colonist eco rebuild for seeded barrens (:242-245), cargo filter + clampGenome merge (:247-251), abductCount ledger restore (the pay curve survives — :252-255), endingDone/Dismissed persistence with the dismissed-finale-null rule (:256-264).
- **No Input singleton reads in the sim** — the STAGE builds the M2 snapshot {mx,my,wx,wy,down,clicked,take_click,keys_held,keys_pressed} (keys_pressed canonical; the sim ALSO reads keys_held for W/A/S/D/arrows + the F hold + isDown/mx/my/wx/wy for cursor-thrust and panel clicks — the FULL snapshot contract, the richest consumer yet; `anyKeyPressed` for the ending dismiss = keys_pressed non-empty via input.any_key_pressed() which EXISTS at src/core/input.gd:108). `game.set_cursor` exists (game.gd:743).
- **No randi/randf anywhere** — the sim's rng only. No Date/time reads.
- Float discipline: pure-float f64 Dictionaries in the sim; Vector2 only at render/solve boundaries.
- **TS line citations dense and accurate** in every ported file (the final review's verified standard).
- **Audio is the standing native deferral** (the M2 noop-hook pattern): every TS audio.* site gets the `# TS audio.play('…') — audio core: its own task` comment through the noop hooks (setMood('space') same).
- **The two-particle-pool architecture ports AS-IS:** the stage owns `fx = Fx(1300)` (its own pool) AND calls `game.fx.update/render` (the shared pool) — both exist natively (test_particles). The engine trail + pirate bursts + zap bursts go to the STAGE pool; the resolveArmada-style shared spawns stay on game.fx.
- Space constants that are ITS OWN (port per-stage, do not share): ship accel **420**, drag **exp(−1.1dt)**, deadzone **20**, sun r **130** danger +60 shp−30dt, hull regen +8dt near thriving colonies (pop ≥ 5, d < r+150), ff timeScale **26** + orbit ×0.4, colony logistic `dt·ts·0.08·(1+pop·0.01)·max(0,1−pop/120)`, beam 1.4 s, cargo cap 4, abduct pay first +10 / repeat +3, seed 20 DNA / splice 15 DNA / repair 50 DNA / scan +15 / resurvey +3 (cd 4), pirate hp 140 dmg −34/click −14dt chase 300 drag exp(−1.4dt) life 40 ring 700, black-hole pull 24000/max(80,d) dmg −60dt ttl 45, death −15% DNA (0 post-ending) respawn (0,−900) cull 700 invuln 4, cam follow rate **5** zoom **0.85**, backdrop seed **7**, vignette 0.5, finale at (0,−1900) trigger d<60 thriving≥3.
- The space deck's chaos ctx INCLUDES **onEnd** (TS :539-547 — the tribute unpaid→pirates rule): the first stage whose ctx carries all three hooks. pirate_lull is the first DECK def with an end hook (spaceEvents.ts:74) — verify chaos.gd dispatches `end` (the M2 `_fire` pattern should already; note in the report if not).
- The planet panel is the tribe hudRects pattern: the SIM owns `panel_rects` + the update-side click dispatch (disabled buttons OWN their click — `overPanel` swallows, TS :408-432, with the uiHold rule :431/:434); the STAGE's render writes `sim.panel_rects` each frame before update (renderPlanetPanel :1195-1231 draws and pushes rects; the NOTE at :1230 is the contract).
- The objective line is DYNAMIC here: the finale bearing rewrites show_objective EVERY update while the core lives (TS :566-568) — the sim fires the hud hook per-update; the static objective only until the finale spawns.
- The M6 FIRST RIDER (from the M5 ledger): the exit RID-leak baseline comparison — ONE clean-baseline stderr diff (full suite at `civ-parity-m5` vs HEAD, the 152→215 provenance pinned in M5 §9) lands in T8 (probes/wrap-prep) and is recorded in PARITY-M6.

**User decisions (already made):** none this plan (the milestone split ruling is the controller's, ledgered since M4).

---

### Task 1: Space sim core — state, system generation, per-planet ecosystems, persist/restore

**Goal:** `src/game/space/space_sim.gd` part 1 (RefCounted, M2 patterns): all state fields (SpaceStage.ts:25-93), constructor + generateSystem + makePlanetEco (the archetype diet dial), onEnter (C1 gate + the FULL restore whitelist), persistColonies, the ship-physics block + sun/colony regen + orbit update.

**Files:**
- Create: `src/game/space/space_sim.gd`
- Test: `tests/test_space_sim.gd`

**Acceptance Criteria:**
- [ ] Constructor TS-verbatim (:95-101): rng = context rng BRANCH (boot-order branch pin — the 5th), chaos scheduler on a second rng.branch() with the space deck, deckSeed = world seed, generateSystem().
- [ ] generateSystem (:103-132): 6 planets, kinds [lush, ocean, volcanic, barren, lush, barren], orbitR 520 + i·380 + rng(−60,60), name `{speciesName(rng)}-{i+1}`, angle rng(0,TAU), orbitSpeed rng(0.008,0.02)·(even?1:−1)/(1+i·0.12), r 46 + rng(0,34) + (lush?10), hue by kind (lush 90-140 / ocean 190-220 / volcanic 5-30 / else 30-60), ring chance 0.25, eco for non-barren via makePlanetEco, x/y 0 (orbit fills them).
- [ ] makePlanetEco (:134-179): Ecosystem on a rng.branch(), floraCap 140/110/70 (lush/ocean/volcanic-and-barren-seeded), flora 0.7·cap; the archetypeWeights diet dial — herbW = weights.herbivore??1, carnW = (carnivore??1)·(predator??1), herbPull = min(0.9, max(0,herbW−1)·0.5 + max(0,1−carnW)·0.5), carnPull mirrored; n = rng.int(2,4) species: cloneGenome(default) + mutate(·, 0.9), size rng(0.7,1.9), hue (p.hue + rng(−40,40) + 360)%360, volcanic → diet carnivore + jaw max(2,·), ocean → flagella max(3,·), the diet flip chances (herbivore && chance(carnPull) → carnivore; else non-herb && chance(herbPull) → herbivore), addSpecies(arch, rng(4,10)); **bonus species AFTER the roster** (titan ≥ 1 → size 2.2 carnivore hue+180; swarm ≥ 1 → size 0.55 herbivore flagella ≥ 4 hue+60) so the diet dial never touches them — the ordering comment rides along.
- [ ] on_enter (:181-268): C1 deck-rebuild gate; audio_set_mood 'space' + show_objective 'SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve' (hud hooks); the restore whitelist per Global Constraints (EVERY guard test-pinned: shapes/length, numeric sanity per field with the r>0 min, the colony/scanned whitelist, eco instanceof + always-take-saved fromJSON, the colonist eco rebuild, cargo clamp merge, abductCount, the ending-done persistence incl. dismissed→finale-null). on_exit → persistColonies; persist_state → persistColonies (the saveAll splice-rollback pin, TS :274-278).
- [ ] persistColonies (:282-297): the full world spec blob → flags.spaceWorld (eco.toJSON() per planet, cargo, abductCount, endingDone/Dismissed).
- [ ] Ship physics + world tick (:301-394 subset): time += dt; ff gate (KeyF held → ffHold 1, decay max(0,·−dt)); timeScale = ffHold > 0 ? 26 : 1; ff block (:306-325): per-planet eco.mods = ecoModsFromWorld (the wire), eco.tick(dt·timeScale), extinctions → bump_extinction + colony toast, speciations → scanned toast, colony generations += dt·ts/30; ship control (cursor thrust with the 20 deadzone + uiHold gate, WASD/arrows, accel 420, drag exp(−1.1dt), thrust flag, shipAngle atan2); engine particles (thrust > 0 && chance(dt·40) — back-of-ship spawn, stage fx pool); planets orbit (angle += orbitSpeed·dt·(ff?0.4:1), x/y fill) + colony logistic growth; sun danger (d < r+60 && invuln ≤ 0 → shp −30dt, hurtT 1, cam_shake 4/0.2); hull regen (colony pop ≥ 5, d < r+150 → shp min(max, +8dt)).
- [ ] Hooks-Dictionary contract (the M2/M5 pattern): hud (toast/banner/show_objective/set_abilities), audio noop hooks, cam_shake, fx_spawn (stage pool) + game_fx hooks, go_to/save_all (space never go_to's onward — the hooks exist for parity), context reads (chaos/karma/dna/playtime/total_dna_earned/bestiary/world/flags) via the injected ctx refs, spend_dna/add_dna/discover/bump_extinction hooks or ctx-direct (follow the tribe/civ precedent per method). Debug cheats documented in the header: `debug_state()`, `debug_seed_colonies()` (TS :1275-1287 — 3 nearest non-barren uncolonized, eco + species 6 + colony {1,0}, persist), `debug_set_ship(hp, x, y)` if needed for bot legs (document ANY addition).
- [ ] Headless tests: constructor/system pins (6 planets, kinds order, orbit/r/hue/ring formulas at a pinned seed — parallel-branch replay), makePlanetEco (floraCap by kind, roster count 2-4, the diet dial pulls at a pinned stream, volcanic/ocean modifiers, titan/swarm bonus AFTER-roster ordering — assert the bonus species' diet survives), the restore whitelist (EVERY guard: corrupt r NaNs rejected, colony/scanned round-trip, eco always-taken + the seeded-barren colonist eco, cargo clamp, abductCount, ending persistence + dismissed-finale-null), persist round-trip (spaceWorld blob shape), ship physics (cursor deadzone, WASD, accel/drag integration at pinned dt, thrust/angle), sun danger + hull regen windows, orbit + colony logistic growth (the cap-120 brake), ff timeScale math (eco.tick receives dt·26, generations +dt·26/30, orbit ×0.4).

**Verify:** `~/.local/bin/godot --headless -s res://tests/run.gd --path .` — suite green.
**Steps:** tests red → port → green → commit `feat: space sim core (system generation, planet ecosystems, ship flight)`.

### Task 2: Space sim core — interactions, gene lab, hazards, finale

**Goal:** space_sim.gd part 2: the planet-panel interaction dispatch, abduct/seed/merge/graft/scan/repair/jettison, pirates, black holes, ship death, the finale/ending state machine.

**Files:**
- Modify: `src/game/space/space_sim.gd`
- Test: `tests/test_space_sim.gd` (extend)

**Acceptance Criteria:**
- [ ] Panel interaction dispatch (:391-434): near-planet gate (nearest, d < r+130) → hover cursor (enabled rects only) → wasClicked dispatch loop with the **disabled-button-owns-click rule** (overPanel swallows the click; enabled → take_click + the action) — actions abduct/seed/scan/repair/merge/jettison (jettison: cargo.pop + toast + persist); the uiHold rule (:431: (consumed || overPanel) && isDown; :434: !isDown → false).
- [ ] tryAbduct (:644-670): beamT gate → nearest → distance FIRST (the wrong-lesson comment) → cargo 4 → eco null → living empty (each its exact toast) → beamTarget + beamT 1.4 + warp. finishAbduct (:672-707): candidates pop ≥ 1 (the infinite-DNA-faucet pin), rng.pick, pop −1, the abductCount ledger key `{p.id}:{sp.id}` (first +10 / repeat +3), last-member → pop 0 + extinct + bump_extinction + the gone-from-this-world toast, cargo push (cloneGenome), add_dna(pay), discover(genome, name, 'space', kin), persist flush (the 60s-autosave-lag comment).
- [ ] seedNearest (:709-733): nearest + cargo > 0 → distance → spendDna(20) (exact refusal) → cargo.pop → barren gets a fresh eco (floraCap volcanic 60 : 100, flora 0.6·cap, kind barren→lush) → addSpecies(genome, 5, {kin, name}) → discover → colony {pop 0, generations 0} ?? → SEEDED banner → levelup → persist.
- [ ] mergeCargo (:735-770): cargo ≥ 2 → spendDna(15) → crossover(cargo[0], cargo[1], rng, 0.3, {anomalyChance wild?0.15:0.10, defectRate wild?0.3:0.2, bias {rate_add: worldNum(mutation_rate_add, 0)}, info}) — the I-q2 rate_add note + the M1/M2 post-crossover-table comment — child name `{speciesName(rng)} (spliced)`, slice(2) + push, the ANOMALY_NAMES/DEFECT_NAMES toasts, discover, borrowedFleshGraft, persist.
- [ ] borrowedFleshGraft (:776-792): combo_active(world, 'borrowed_flesh') + flags.borrowed_flesh_graft guard → extinct bestiary entries rng.shuffled → standoutPart → GENE_BOUNDS[part.def.gene] → graftValue(cur, level, bound.max ?? level) → **a graft never downgrades** (raised ≤ cur → next lineage) → flag set + toast.
- [ ] Pirates (:454-498, :794-810): spawnPirates (cap 5 total, life 40, ring 700 at rng.next()·TAU, hp 140, alarm); the chase loop — ttl splice + 'The siege lifts' toast, accel 300 toward ship when d > 30, drag exp(−1.4dt), gait += dt, damage d < 60 && invuln ≤ 0 && !pirateLull (shp −14dt, hurtT 0.5, burst chance dt·6 + hit), **click-to-shoot the clicked pirate** (clickD < 60 → hp −34, takeClick, zap + burst, death → splice + '+30 DNA' toast + add_dna(30) + boom + big burst).
- [ ] Black holes (:436-452): pull d < 600 (24000/max(80,d) toward), damage d < 40 (−60dt, hurtT 1), drift, ttl decay, filter; the ship-death cull radius 700 comment (:595-597).
- [ ] Ship death (:584-602): shp ≤ 0 → shp = max·0.5, DNA −15% (0 once endingDone — the no-bill comment), cargo SURVIVES (the seeding-block comment), toast, respawn (0,−900) zeroed, invuln 4, black-hole cull > 700, pirates + ttls cleared, boom + shake 10/0.8.
- [ ] Abduct/gene-lab/tribute keys (:500-517): R → tryAbduct; beam countdown → finishAbduct; G (cargo ≥ 2) → mergeCargo; V (tributeDemand > 0) → payTribute (:861-870: dna ≥ demand → pay + satisfied toast + zero; else the raid-is-coming toast).
- [ ] Chaos ctx WITH onEnd (:519-548): the full ctx (same shape as civ) + onEnd — tribute unpaid → spawnPirates(3) + demand 0; resurveyCd decay (:550).
- [ ] Finale/ending (:552-582): thriving ≥ 3 (colony pop ≥ 20) && !finale && !endingDone → finale {0, −1900, active, t 0} + 'THE CHAOS CORE AWAKENS' banner (subtitle 'something pulses beyond the outer light', ttl 6) + ascend; the per-update objective bearing (distance + up/down, or the post-ending calm line 'the core sleeps — the sandbox is yours'); d < 60 && !endingDone → endingDone + ascend + persist (the win hits disk immediately); the dismiss rule (wasClicked || anyKeyPressed → endingDismissed + dismissT = endingT).
- [ ] Cooldowns + camera feed + persist cadence (:604-623): invuln/hurtT decays; persistT 5 s → persistColonies; cam.follow(sx, sy, dt, 5) + zoom 0.85 + the world-pointer recompute + BOTH fx pools update.
- [ ] Headless tests: the dispatch ladder (disabled-owns-click, uiHold, each action), tryAbduct full gate ladder + the ledger pay curve (10 then 3) + the last-member extinction, seedNearest (barren→lush conversion + floraCap + colony init + the DNA refusal), mergeCargo (crossover opts at a pinned stream, the wild_mutations rates, the info toasts, cargo slice/push), borrowedFleshGraft (combo off / flag guard / never-downgrade / the flag set), pirates full lifecycle (spawn cap, chase, ttl siege-lift, click-to-shoot 34-dmg kill +30 DNA, lull), black holes (pull math at pinned distances, damage, cull-on-death), ship death (the −15% / 0-post-ending bill, cargo survival, the cull), ff e2e (extinction/speciation toasts + generations), the finale trigger + bearing + the d<60 ending + the dismiss fade state, tribute pay/refuse + the onEnd unpaid→pirates.

**Verify:** suite green. **Commit:** `feat: space interactions, gene lab, hazards, chaos core finale`.

### Task 3: Space chaos events deck

**Goal:** `src/game/space/space_events.gd` — 4 baseline + 2 gated defs verbatim (spaceEvents.ts); the FIRST deck def with an end hook; the deck's Math.random pirate-count draw → the scheduler rng in-stream.

**Files:**
- Create: `src/game/space/space_events.gd`
- Modify: `src/game/space/space_sim.gd` (deck construction + the onEnd ctx — verify T2 already wired it)

**Acceptance Criteria:**
- [ ] Baseline defs (:10-47) verbatim: pirates {name '☠ PIRATE AMBUSH', warn 'Unfriendly signatures on the scope…', weight 0.7 + chaos, dur [30,30], cd 55, apply spawnPirates(2 + floor(rng·2)) — **the Math.random site → the scheduler rng in-stream with the M4 storm precedent note**}; blackhole {name '🕳 ROGUE BLACK HOLE', warn 'Starlight bends where it should not…', weight 0.5 + chaos·0.8, dur [45,45], cd 90, apply spawnBlackHole}; flare {name '☀️ SOLAR FLARE', weight 0.6 constant, dur [0.1,0.1], cd 60, apply solarFlare}; tribute {name '📦 VOID EMPIRE TAX', warn 'A shadow shaped like paperwork falls across your ship…', weight 0.5 + max(0,−karma)·0.7, dur [12,12], cd 100, apply demandTribute(60)}.
- [ ] Gated variants (:49-77): nebula = worldHas(wild_mutations) → nebula_flip {name '🌌 MUTATION NEBULA', warn 'A rainbow wall of charged gas rolls in…', weight nebula? 0.5 + chaos·0.7 : 0, dur [0.1,0.1], cd 80, apply nebulaFlip}; calm = calmProxy(world) → pirate_lull {name '🕊 PIRATE LULL', weight calm? 0.6 + max(0,karma)·0.5 : 0, dur [30,30], cd 100, apply pirateLullBegin, **end pirateLullEnd — the first deck def with an end hook**}.
- [ ] The stage's chaos hooks (T2 already ported the methods — verify signatures): spawnPirates/spawnBlackHole/solarFlare/demandTribute/nebulaFlip/pirateLullBegin/End per TS :794-883 (nebulaFlip: living planets rng.pick, forceSpeciation ×2, the made==0 toast, the seeds-N toast).
- [ ] The tribute onEnd rides the STAGE ctx (T2) — the deck def itself carries NO end; document the split (the def's apply demands; the ctx's onEnd punishes unpaid).
- [ ] Headless tests: traitless world → exactly 4 defs verbatim; wild_mutations → 5; calm_veil → 6; every def's constants; the pirate-count draw pinned at a seeded scheduler stream (the in-stream port's replay pin); a live pirate_lull through the real scheduler (begin sets the lull, the END hook clears it — the first end-hook wiring pin); a live tribute (demand banner, pay, the onEnd unpaid→3-pirates path).

**Verify:** suite green. **Commit:** `feat: space chaos deck (pirates, black holes, flares, the Void Empire, variants)`.

### Task 4: Space stage scene — world render

**Goal:** `src/game/space/space_stage.gd` part 1 (Node2D): the world-space render port — backdrop, sun, orbits, black holes, planets, finale core, beam, ship, pirate, fx — through the REAL cam.

**Files:**
- Create: `src/game/space/space_stage.gd`
- Test: `tests/test_space_scene.gd` (headless boot/phase pieces)

**Acceptance Criteria:**
- [ ] This stage USES the cam (unlike civ): cam.begin/cam.end around the world layer (TS :894/:1025) — the tribe_stage pattern; drawSpaceBackdrop BEFORE cam.begin with the REAL cam (not fakeCam) and seed **7** (:892).
- [ ] Render order TS-verbatim (:887-1099): sun (pulse = 1 + sin(time·2)·0.03; glow r·3·pulse rgba(255,200,90,0.4) 0.7; discs r hsl(45,1,0.65) + r·0.85 hsl(50,1,0.8)) → orbit paths (rgba(140,170,255,0.08) lw 1, arcs at orbitR) → black holes (radial gradient 2→90: #000 / 0.4 rgba(80,40,160,0.8) / transparent; the rotating arc stroke rgba(180,120,255,0.5) lw 2, r 46 + sin(time·5)·5, from time to time+4) → planets (the shadow-side radial gradient: center offset (−0.35r, −0.35r) inner 0.2r, stops hsl(hue,0.55,0.55)/0.7 hsl(hue,0.5,0.32)/hsl(hue,0.5,0.14); ring: translate+rotate 0.4, ellipse 1.7r × 0.5r stroke hsl(hue+30,0.4,0.6,0.5) lw 6; rim glow 1.3r hsl(hue,0.7,0.6,0.4) 0.5; colony `🏳 {pop}` bob sin(time·2+id)·3 at y−r−16 + '★ thriving' at −30 when pop ≥ 20; scanned name label when !colony) → finale core (pulse 1 + sin(t·3)·0.2, glow 140·pulse rgba(255,90,200,0.5) 0.9, discs 26·pulse hsl(320,1,0.7) + 14 #fff, 3 arcs r 40+i·16 from a = t·(1+i·0.4)+i·2.1 spanning 2.4, stroke hsl(300+i·30,1,0.7,0.7) lw 2) → pirates (drawPirate) → beam (linear gradient ship→planet rgba(150,220,255,0.9→0.2), lw 10 + sin(time·30)·4; the rising creature at the midpoint − t·30: legs > 0 → drawCreature {facing 1, speed 0.2, gaitPhase time·8, airborne 1, mood 'afraid', scale 1.2} else drawCell {scale 1.6, seed 4}) → ship (drawShip when !endingDone || endingDismissed — the after-cam.end placement bug comment :1017-1019) → stage fx.render + game fx.render → cam.end.
- [ ] drawShip (:1124-1168): blink (invuln > 0 && floor(time·10)%2 — alpha 0.5), translate(sx,sy) rotate(shipAngle + π/2), the hull path (moveTo(0,−18) quad(12,2)(8,14) line(−8,14) quad(−12,2)(0,−18), fill #cfe0f0 stroke #5a7a9a lw 1.5), cockpit ellipse (0,−4, 4.5, 6) hsl(200,0.8,0.65), wings (two 3-point paths #8fb0cc), hurt flash (alpha hurtT·0.7, disc 20 #ff8a7a). drawPirate (:1170-1188): translate+rotate(atan2 + π/2), the 4-point hull #6a3a3a stroke #3a1a1a, glow 20 rgba(255,90,60,0.4) 0.6, '☠' at y−22.
- [ ] The 3-RID painter contract for EVERY drawCreature (the beam creature, the cargo creatures in T5) — the cell painter likewise for cells (the M2 cell painter's draw contract; verify its exact signature — the TS pose dict maps to the native call).
- [ ] Hooks built by the stage (the tribe/civ pattern): the 16+ hook surface + the panel_rects write-back (the stage's renderPlanetPanel writes sim.panel_rects each frame BEFORE sim.update — the T5 panel task completes this; T4 stubs the write with an empty array + a TODO-free comment pointing at T5).
- [ ] Headless tests: the render guards (pre/post restore, the cam begin/end pairing), the draw dispatch (beam creature-vs-cell branch on legs), the ship visibility rule (!endingDone || endingDismissed).

**Verify:** suite green. **Commit:** `feat: space stage world render (system view, ship, beam)`.

### Task 5: Space stage scene — screen HUD, planet panel, xvfb suite

**Goal:** space_stage.gd part 2: the screen-space HUD layer (chip/ff/hull/cargo), the planet panel + the panel_rects write-back, set_abilities, the ending overlay; the xvfb scene test.

**Files:**
- Modify: `src/game/space/space_stage.gd`
- Create: `tests/scenes/test_space_scene.tscn` + `.gd` + `tools/test_space_scene.sh` + `tools/visual_check_space_scene.py`

**Acceptance Criteria:**
- [ ] Screen layer TS-verbatim (:1027-1098, AFTER cam.end): the colonies chip (panel vw/2−110, 44, 220×26 fill rgba(6,12,28,0.85) stroke rgba(150,220,150,0.4); `🏳 {colonies} colonies · ★ {thriving}/3 thriving` 11 at y 57, fill thriving ≥ 3 ? #ffe08a : #9fe89a) → the ff tint (rgba(150,100,255,0.06) full + '⏩ EVOLUTION ACCELERATING' 14 #e2a4ff at y 160 — below the banner band comment) → vignette 0.5 → the hull bar (hpW min(300, vw·0.26), panel (hx−6, hy−6, +12, 22) at hy = vh−104; fill hpP > 0.35 ? #5ab8ff : #ff5a5a width hpW·hpP height 10; 'HULL {ceil}' 10 centered) → the cargo bar (cargoW 4·54 + 3·8 at cy = vh−178; panel (cx0−10, cy−8, +20, 70); 'CARGO' 9; 4 slots 54×54 panelled, each clipped (rect clip) with legs/arms → drawCreature {x+27, cy+44, facing 1, speed 0.05, gaitPhase time·3+i, mood 'idle', scale 0.85} else drawCell {x+27, cy+27, scale 1.1, seed i·3}) → the planet panel when near (renderPlanetPanel) → the ending veil (alpha: dismissed ? max(0, 1−(endingT−dismissT)/1.5) : min(1, endingT/2); fill rgba(4,6,20, a·0.86) full when a > 0; renderEnding when a ≥ 1 && !dismissed) → renderEnding (:1101-1122: 'THE CHAOS CORE ACCEPTS YOU' 34 #e2a4ff w700 at vh/2−120; the 4 stat lines 14 rgba(210,230,255,0.85) stepping 30 — playtime min, DNA harvested, thriving/seeded/bestiary, karma ± toFixed(2) + chaos %, the karma flavor ternary; the sandbox line + the keys line).
- [ ] renderPlanetPanel (:1195-1231): w 250 at x = vw−270, h = cargo > 0 ? 290 : 252, y = vh−h−150; panel stroke hsl(p.hue, 0.5, 0.6, 0.6); name 14 w700 hsl(hue,0.7,0.75); the kind/colony/gen line 10; the bio line (living count + flora, or 'lifeless rock'); the buttons via mkBtn (rect {x+14, yy, w−28, 30}, fill enabled ? rgba(50,90,170,0.9) : rgba(45,50,62,0.9), label 12 enabled ? #fff : rgba(255,255,255,0.4)): ABDUCT (enabled eco && !cargoFull && beamT ≤ 0) at y+70 / SEED (cargo > 0) y+106 / SCAN or RE-SURVEY (+3) (eco) y+142 / REPAIR (shp < max && dna ≥ 50 — the label shows the hull fraction when disabled) y+178 / GENE LAB (cargo ≥ 2) y+214 / JETTISON (cargo > 0, the count) y+250; **the rects push to sim.panel_rects each frame** (the NOTE :1230 contract — the update dispatch reads them).
- [ ] setAbilities (:626-631): [{R 🛸, active beamT > 0}, {F ⏩, active ffHold > 0}, {G 🧪, active cargo ≥ 2}, {LMB 🔫}] — every frame via the hook.
- [ ] The T3 doctrine (binding): this stage's node subtrees are WORLD-SPACE under the cam — but the cargo slots' clipped creature draws and the panel are screen-space: any node-subtree canvas applies the same cancellation discipline (the civ lesson, cited in the header).
- [ ] xvfb scene test (the test_tribe_scene pattern, freeze-arm doctrine — sim-state arms only): fixture world (pinned seed, debug_seed_colonies for the 3-colony state where needed) → moments: system view (sun discs + orbit paths + ≥ 3 planet discs with the shadow gradient + a ring), pirates (ships + ☠ + the red glow), black hole (the gradient + the rotating arc), beam abduction (the beam line + the rising creature), cargo bar (4 slots with creature/cell pixels + the empty slot), planet panel (the 6 buttons with enabled/disabled fills + the hull-fraction label), ff tint (the purple veil + the label), colonies chip (the counts + the gold at 3 thriving), ending overlay (the veil alpha + THE CHAOS CORE ACCEPTS YOU + the stat lines) — each ≥ 3 structural asserts; python checker in the visual_check family.
- [ ] Headless tests: the panel_rects write-back per frame (the sim reads what the stage drew — a rect click through the snapshot dispatches the action), the abilities payload per frame, the ending fade math (the 2s in / 1.5s out windows).

**Verify:** `tools/test_space_scene.sh` exit 0; headless suite green. **Commit:** `feat: space stage HUD, planet panel, ending (xvfb suite)`.

### Task 6: Wiring — registration, spaceWorld save/continue, civ-victory landing, i18n

**Goal:** The game-level wiring: SpaceStage registration (the 5th rng branch), the civ-victory placeholder becomes the REAL landing, spaceWorld save/continue E2E, the ending-dismissed persistence, i18n.

**Files:**
- Modify: `src/main.gd` (registration: the boot list AND resetStagesForNewRun — space in BOTH, boot order cell → creature → tribe → civ → space), extend `tests/test_world_creature_pins.gd` (space save/continue pins), the boot-order branch pin (the exactly-4 → exactly-5 upgrade in test_hud_civ.gd or its new home)
- Create: `tests/test_hud_space.gd`

**Acceptance Criteria:**
- [ ] Registration: main.gd preloads + registers SpaceStageScript after CivStage (both lists — the drifter rule); the constructor's 5th context-rng branch joins the boot-order pin.
- [ ] Civ→space landing E2E: the M5 test's placeholder assert (space unregistered → switch_stage no-ops, title/sub swallowed) upgrades — with space REGISTERED, the civ victory go_to('space', {title 'THE BLACK OCEAN', sub 'a planet was never going to be enough'}) lands the REAL SpaceStage (on_enter fires: the objective, the C1 gate, the constructor system stands); grep for stale space-unregistered asserts suite-wide and upgrade them all (the M5 bot's victory leg asserted the civ stage REMAINED — that assert now upgrades to the real landing).
- [ ] spaceWorld save/continue E2E: space save_all (on_exit persist + the 5 s cadence + the win flush) → CONTINUE → the restore whitelist round-trip — the system AS IT STOOD (planets incl. eco rosters + colonies + scanned, cargo, abductCount, endingDone); the corrupt-blob guards E2E (a wrong-length blob → fresh system; a NaN r → the field keeps the constructor value).
- [ ] The ending E2E: a won run (debug_seed_colonies + ff to thriving + the core approach via debug seam or a real flight) → endingDone persists → CONTINUE → the ending stays DONE (the a-won-run-stays-won pin :256-264); the dismissed ending sleeps (no stale orb, no AWAKENS replay — the finale-null rule).
- [ ] i18n: every t() site in the space surface mapped in assets/i18n/vi.csv (the M4/M5 1:1 method — grep the TS VI object; unwrapped sites stay unwrapped; normative absences pinned vi_has == false). The t() sites include the objective strings, 'The siege lifts — pirates give up', 'Pirate destroyed! +30 DNA', the abduct/seed/splice/scan/repair refusal + success toasts, the nebula/lull lines, the cargo-full line, 'THE CHAOS CORE ACCEPTS YOU', the ending flavor lines, 'the sandbox remains yours — keep flying, keep evolving', '(ESC to pause · M mute · F fast-forward · R abduct)', the panel button labels. Raw (non-t) strings stay raw: 'THE CHAOS CORE AWAKENS', the finale bearing line, 'THE VOID EMPIRE DEMANDS TRIBUTE' + subtitle, the colony/species toasts with interpolated names.
- [ ] Headless tests: all flows pinned with real transitions.

**Verify:** suite green. **Commit:** `feat: space wiring (registration, civ handoff, spaceWorld save/continue, i18n)`.

### Task 7: Space bot + flow integration

**Goal:** `tests/bots/bot_space.gd` through the REAL input pipeline; determinism ×2.

**Files:**
- Create: `tests/bots/bot_space.gd` + `tests/scenes/test_bot_space.gd` + `.tscn` + `tools/test_bot_space.sh`

**Acceptance Criteria:**
- [ ] Bot law: every input through the driver; field reads OK; direct sim calls ONLY the documented debug cheats (debug_seed_colonies + debug_state + any T1-documented addition; the audit table 1:1 vs the sim header).
- [ ] Bot arc: arrival via the REAL civ victory (reuse the M5 bot's civ-unification leg — bot_civ's victory leg lands space through the real go_to; do NOT re-implement civ legs), then in space — real keys/mouse: fly (WASD thrust toward a planet, the engine trail), abduct (R at range — the beam + the cargo slot fills + the +10 DNA), seed (the panel SEED click or the debug-cheat-free path: fly + click the drawn button), scan (the +15 survey), fast-forward (hold F — generations climb, ecos churn), splice (G at cargo 2 — the child slot), survive a pirate siege (the click-to-shoot kill OR the ttl lift), then the finale: debug_seed_colonies (the documented cheat) + ff to 3 thriving → 'THE CHAOS CORE AWAKENS' → fly to the core (real thrust) → d < 60 → THE CHAOS CORE ACCEPTS YOU → dismiss (a real click) → the sandbox returns (the ship visible again).
- [ ] Determinism ×2: the full bot at a pinned seed → identical fingerprints (the per-600-frame sweep).
- [ ] Stage-named reads (the d7a5cb8 lesson): game.stages['space'].sim everywhere post-landing.
- [ ] Bot law audit in the report 1:1.

**Verify:** `tools/test_bot_space.sh` exit 0 ×2 determinism; suite green. **Commit:** `feat: space bot (fly, abduct, seed, splice, siege, finale, determinism)`.

### Task 8: Space probes + visual moments + PARITY-M6

**Goal:** The QC gates, space flavor.

**Files:**
- Create: `tests/test_probe_space.gd` + `tools/probe_space.sh`; Modify: the scene visual harness (space moments), `docs/PARITY-M6.md`

**Acceptance Criteria:**
- [ ] Probes (headless, TS-verbatim, pinned seeds — the M4/M5 probe shape, independent derivations with provenance comments): the diet-dial pulls (herbPull/carnPull closed-form at a pinned stream + the bonus-species ordering), the abduct pay curve (10/3 ledger + the last-member extinction + bump_extinction), the colony logistic growth (the cap-120 brake exact), ff generations (+dt·26/30) + the eco.mods wire (a world trait's effect observed through a planet eco), the crossover opts (wild vs normal rates at a pinned stream + the rate_add bias), the graft (never-downgrade + the flag), the pirate chase/damage math (300 accel, exp(−1.4dt), −14dt, the 34-dmg click kill +30), the black-hole pull (24000/max(80,d) at pinned distances) + the cull-on-death, ship death (−15% vs 0 post-ending), the tribute onEnd (unpaid → 3 pirates), sun danger + hull regen windows, the finale trigger (thriving ≥ 3) + the ending fade windows (2 s in / 1.5 s out), the resurvey cadence (cd 4, +3).
- [ ] **The M6 FIRST RIDER (from the M5 ledger, mandatory): the exit RID-leak baseline comparison** — one clean-baseline stderr diff (full suite at `civ-parity-m5` vs HEAD, single instance each, sequential); record the leak provenance (152 → 215) as pinned-pre-existing or find the owner, in PARITY-M6.
- [ ] Visual moments (xvfb — may share the T5 scene captures; count honestly in PARITY-M6 §7): the T5 moment list is the inventory (9 moments × ≥ 3 asserts).
- [ ] `docs/PARITY-M6.md`: per-feature rows (every space feature: TS line + native pointer + test pointer); the §5.4-style (a)-(d) checklist; the M7 deferred list (CI/release, the repo overwrite, any standing carry-forwards: audio core, the ledgered minors from M5's final review — the continents pin, the factory-order pin, the probe/sim overlap disclosure).

**Verify:** `tools/probe_space.sh` exit 0; visual suite exit 0. **Commit:** `test: space probes` then `test: space visual moments + parity list`.

### Task 9: M6 wrap — A-B, perf, review, tag

**Goal:** Close M6.

**Files:**
- Modify: `docs/PARITY-M6.md`, `docs/ARCHITECTURE.md` (space section), README (status row)

**Acceptance Criteria:**
- [ ] A-B run: base `civ-parity-m5` → HEAD, cell-state dump IDENTICAL (the standing dump must not move — space is additive; the 5th boot branch joins the replay pin; any diff line ruled).
- [ ] Perf: space sim tick @ 6 planets (3 with live ecosystems) + pirates + black holes, the split metric (sim vs render vs frame — the T11/M4/M5 pattern); sim_avg_ms asserted ≤ 2 ms (NOTE: the ff block ticks 3 planet ecos at dt·26 in ONE update — measure ff-hold AND normal ticks, both rows in PARITY-M6); render ≤ 4 ms; tripwires standing.
- [ ] ARCHITECTURE.md space section (module map, the two-pool fx architecture, the panel_rects write-back, the restore whitelist doctrine, the debug cheat surface, the in-stage finale); README row (M6 — all five stages landed).
- [ ] Full suite green: headless + ALL xvfb entries (bot, bot_creature, bot_tribe, bot_civ, bot_space, editor_click, menu, visual ×2, creature/tribe/civ/space_scene, perf ×N, boot, visual_suite — caps ≥ 900 s).
- [ ] Final whole-branch review (controller) → riders → tag `space-parity-m6` + PARITY-M6 completion note.

**Verify:** `./tools/test.sh` green; `git tag` shows `space-parity-m6`. **Commit:** `docs: M6 wrap (parity table, perf, architecture)`.

---

## Completion

- [ ] All 9 tasks complete, final whole-branch review TAG-READY, tag `space-parity-m6`, PARITY-M6 completion note, ledger closed.
- **Next milestone:** M7 = CI/release + the repo overwrite (the goal's terminal step — the old GitHub repo gets replaced per spec §5; plan to be written fresh).
