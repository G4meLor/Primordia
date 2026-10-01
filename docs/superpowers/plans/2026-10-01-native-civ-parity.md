# M5 Civ Stage Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full TS-verbatim port of the Civ stage (planetary unification: 3-lane national output sliders → attack/charm/trade armadas → flip 3 rival cities → space handoff) — playable, §5.4-gated, tagged `civ-parity-m5`.

**Architecture:** Mirror the tribe milestone's shape exactly: `civ_sim.gd` (RefCounted sim core, hooks-Dictionary, `update(dt, inp)` M2 snapshot) holds ALL logic (sliders, armadas, tickSecond, chaos hooks, persist/restore, brick-hardening) + `civ_stage.gd` (Node2D scene: screen-space render — NO Cam object, the camX/camY drift floats + fakeCam pattern) + `civ_events.gd` (world-parameterized chaos deck: 4 baseline + 2 gated variants) + the tribe-victory handoff (M4's go_to('civ') placeholder lands) + victory → space placeholder ('THE BLACK OCEAN') + civState save/continue + bot/probes/PARITY-M5.

**Tech Stack:** Godot 4.2.2 + GDScript typed; the frozen TS authority at ~/Desktop/RD/Spore (read in full for this plan: src/game/civ/CivStage.ts 663 lines + civEvents.ts 79 lines, 2026-10-01 state).

**Spec:** docs/specs/2026-09-29-native-migration-design.md §5.4 (same 4 criteria gates as §5.3, civ flavor).

**Milestone ruling:** spec §5 doctrine is "mỗi bước = một milestone chơi được/test được" — Tribe → Civ → Space are THREE steps in one bullet, so they become three milestones: M4 = Tribe ✅ (tag `tribe-parity-m4`), **M5 = Civ** (this plan, tag `civ-parity-m5`), M6 = Space, then M7 = CI/release + repo overwrite. Each keeps the M3 gate shape (feature list + bot arc + probes + pixel asserts + A-B + perf).

## Global Constraints

- **Parity-pin porting:** TS logic/constants/draw-order 1:1; every divergence documented in the file header + report; rng draw order sacred (lazy where TS lazy; TS `Math.random()` sites → the stage rng IN-STREAM with a header note + replay pin — the civ surface has these rng sites: constructor city jitter ×2 (CivStage.ts:100-101), attack-resolve burning chance 0.5 (:378), tickSecond personalities 0.02/0.03/0.01 (:408/:414/:419) + the economy buy's rng.pick (:421), chaos hooks rng.pick (:462/:473/:486), armada trail chance dt·30 + range(−8,8) (:242-245). The civ rng is a BRANCH of the context rng taken in the constructor (TS :81) — the stage constructs at BOOT, so branch order (cell → creature → tribe → **civ**) is part of the replay pin.
- **Save-wire camelCase TS-verbatim:** `civState` blob (CivStage.ts:135-143) rides `flags.civState` — cities[{id,owner,influence,hp,pop}], mil/culture/econ, victoryFired, lastRaised. Restore guards TS-verbatim (:145-173): non-array or length-mismatch → false; per-city owner sanitize (only 'you' or a live rival id), influence clamp ±100, hp clamp 5..100, pop clamp 1..30, sliders clamp 0..10, victoryFired strict ===, lastRaised must be one of the three lanes (the first-post-CONTINUE-regen bug pin, TS :169-170).
- **No Input singleton reads in the sim** — the STAGE builds the M2 snapshot {mx,my,wx,wy,down,clicked,take_click,keys_held,keys_pressed} (keys_pressed canonical — civ is keyboard-only: Q/A/W/S/E/D sliders, Digit1/2/3 armadas; NO mouse, NO hudRects in the TS — the sliders panel is display-only).
- **No randi/randf anywhere** — the sim's rng only. No Date/time reads.
- **Chaos ctx shape (civ flavor):** onWarn + onApply ONLY — **NO onEnd key** (CivStage.ts:263-277). Verify the native chaos scheduler tolerates a missing onEnd (the M2 `_fire` no-op pattern); if the M2 port requires it, teach it the no-op — document in the report. onApply does banner + addChaos(0.03) + storyteller.noteChaosEvent (the world_temperament pacing marker). The deck rebuilds on enter when world.seed ≠ deckSeed (C1, TS :113-118).
- Float discipline: pure-float f64 Dictionaries in the sim; Vector2 only at render/solve boundaries.
- **TS line citations dense and accurate** in every ported file (the final review's verified standard).
- **Audio is the standing native deferral** ("audio core: its own task" — the M2 noop-hook pattern): every TS audio.* site gets a `# TS audio.play('…') — audio core: its own task` comment, wired through the noop hooks like creature/tribe stages. setMood('civ') same.
- **The camShakeFor quirk ports AS-IS:** the civ fakeCam zeroes shx/shy (TS :535) and the civ render is screen-space, so TS shake calls are visually inert on this stage — port the calls verbatim (they feed the game-level shake state) with a one-line comment; do NOT "fix" them.
- **The raw-coords fx quirk ports AS-IS:** resolveArmada and the armada trail spawn fx at RAW MAP coords, not toScreen'd (TS :243-246, :374) — the ring/particles land detached from the city disc. TS-verbatim + comment; the floatWorld call IS toScreen-corrected (:372) — keep the asymmetry exactly.
- Civ constants that are ITS OWN (port per-stage, do not share): regen 6 s → lastRaised lane, output 10, slider clamp 0..10, armada speed 220, resolve d<14 / t>14, launchCd 5, launch spend 2, power = stat+4 SNAPSHOT, rivalDef = (rival?6:3) + (difficulty chaos?+3 : peaceful?−1 : 0), resolve net = (power−rivalDef)·10, attack hp−12 clamp 5..100 + burning 6 @chance 0.5 + karma −0.02, charm karma +0.015, trade karma +0.01, flip at influence ≥ 100 (hp floor 40 on flip), toastInset **150**, vignette **0.5**, planet r = min(vw,vh)·0.42, toScreen ×0.62.
- The ruler portrait IS the player creature (drawCreature with ctx.genome, scale 1.4, mood 'happy', clipped 88×88) — the creature painter serves the civ stage (the M4 chief pattern; 3-RID contract).
- **tickSecond gate is the float floor-cross, NOT an accumulator:** `floor(time) ≠ floor(time − dt)` (TS :253) — port verbatim; the rng draw order inside tickSecond (per-city, personalities in city order) is replay-pinned.
- **The armadas filter quirk ports AS-IS:** `armadas.filter(a => a.alive || a.t < 0)` (TS :250) with a comment.
- **The rebellion/revolt id quirks port AS-IS:** capital id = 'you' (its owner AND id); rebellion targets YOUR cities EXCLUDING the capital via `owner === 'you' && id !== 'you'` (TS :471); revolt's former-owner lookup `rivals.find(r => r.id === c.id) ?? rivals[0]` (TS :452 — matches only rival-id'd cities, falls back to rivals[0] for the capital) with the unrest-heal-order comment (:448-449: the −99.8 threshold sits above the +0.12 heal step).
- The board-full transfer: raise() clamps +1 then, if total > output, donates 1 from the LARGEST other lane (desc sort, stable → culture before econ on ties) with toast `+1 {lane} ← {donor}`; donor 0 → revert the raise + `t('Board full — lower another slider first')` (TS :198-216).

**User decisions (already made):** none this plan (the milestone split ruling above is the controller's, ledgered since M4).

---

### Task 1: Civ sim core — state, sliders, armadas, tickSecond, persist/restore

**Goal:** `src/game/civ/civ_sim.gd` (RefCounted, M2 patterns): all state fields (City/Rival/Armada shapes, CivStage.ts:17-77), constructor (capital + 3 rivals + city jitter), slider raise/lower/transfer/regen, armada launch (3 kinds)/flight/resolve, rivalDefFor, tickSecond (production, rival personalities, hearts, karma, flip, revolt), the 6 chaos hook methods, persist/restore with guards, brick-hardening gate, victory go_to hook.

**Files:**
- Create: `src/game/civ/civ_sim.gd`
- Test: `tests/test_civ_sim.gd`

**Acceptance Criteria:**
- [ ] Constructor TS-verbatim (:79-111): rng = context rng BRANCH (boot-order branch pin), rulerGenome = context genome; capital {id 'you', name `{player_name}grad`, owner 'you', x 0, y 120, hp 100, influence 100, pop 8, burning 0}; rivals Khorate Dominion (r1, military, aggression 0.8, #ff7a5a) / Vexi Concord (r2, culture, 0.35, #9a7aff) / Ompa Syndicate (r3, economy, 0.25, #5ad0a8); rival cities at cos(i/3·TAU)·700 + rng(−120,120) / sin(i/3·TAU)·480 + rng(−90,90) − 60, hp 100, influence −60, pop 6, names Prime-idx {Khora, Vex, Ompa}; sliders mil 4 / culture 3 / econ 3, output 10; chaos scheduler on a second rng.branch() with the civ deck; deckSeed = world seed.
- [ ] on_enter semantics (:113-130): C1 deck-rebuild gate (world.seed ≠ deckSeed → new scheduler + deckSeed update), toast_inset 150 (via hud hook), showObjective 'UNIFY THE PLANET — slider keys Q/W/E · launch armadas with 1/2/3' (hud hook), restore_state, brick-hardening (victoryFired && all owned → go_to('space', {title 'THE BLACK OCEAN', sub 'a planet was never going to be enough'}) via the go_to hook). on_exit → persist_state.
- [ ] Sliders (:182-222): launchCds per kind decay max(0, cd − dt); regenT += dt, ≥ 6 → reset, if total < output → lastRaised lane +1; Q/W/E raise (the transfer-from-largest-other block with both toasts), A/S/D lower clamp; lastRaised tracks the raised/spent lane (:217-222, :343 — the launch-spend sets lastRaised too, TS :340-343 comment).
- [ ] Armadas (:224-250, :308-390): Digit1/2/3 → launch(attack/charm/trade); launch (:310-349): cd > 0 return; stat < 2 → toast `{kind} needs 2 output in its lane (raise with Q/W/E)`; no targets (all owner 'you' or influence ≥ 100) → toast t('No city left to persuade — build output!'); target = nearest enemy city to capital (hypot sort, stable); power = stat + 4 SNAPSHOT; hopeless refuse power ≤ rivalDef+2 → toast `{kind} needs {5−stat}+ more output in its lane (5+ total) — raise with Q/W/E, or lower a full slider`; spend 2 from the matching lane (max(0, ·)); lastRaised = the lane; cd 5; push armada {capital pos, target pos, kind, t 0, alive, power}; toast `{KIND} {t('armada →')} {target.name} (power {power})` with the ⚔️/🎭/💰 icon. Flight (:230-249): t += dt, d < 14 || t > 14 → alive false + resolve; else move (dx/d)·220·dt; trail fx chance(dt·30) → rng range(−8,8), ttl 0.5, size 2, dot, #9fd8ff, drag 1 (RAW map coords — the quirk comment). The filter quirk (:250).
- [ ] rivalDefFor (:351-355): (rival ? 6 : 3) + (difficulty 'chaos' ? 3 : 'peaceful' ? −1 : 0) — ONE source of truth for launch gate AND resolve (the drift pin comment).
- [ ] resolveArmada (:357-390): target owned → return; power = the SNAPSHOT; rivalDef via rivalDefFor(!!rival); net = (power − rivalDef)·10; influence clamp ±100; floatWorld at toScreen-corrected coords `{±}{round(net/10)} influence` (#9fe89a / #ff9a8a, size 14); camShakeFor(3, 0.2); fx ring ttl 0.7 size 30 grow 2 (attack rgba(255,120,90,0.9) else rgba(150,200,255,0.9)) at RAW coords (quirk comment); attack: hp clamp(hp−12, 5, 100) + burning 6 @ rng.chance(0.5) when not already + addKarma(−0.02); charm/trade: addKarma(+0.015/+0.01); flip at influence ≥ 100 && owner ≠ 'you': owner 'you', hp max(hp, 40), banner `{NAME} JOINS YOUR PLANETARY STATE` reward.
- [ ] tickSecond (:392-457) — order sacred: (1) per-city: yours → pop min(30, +0.02), hp min(100, +0.5), burning −= 1, influence < 0 → min(0, +0.12) (unrest heals); rival's → military shells capital (hp max(20, − aggression·0.4) + toast `{name} shells your capital!` bad 💥 @ chance 0.02 + camShakeFor(3, 0.3)), culture erodes each YOUR city (influence max(−100, −1.5) @ chance 0.03), economy grows (pop +0.05, buy @ chance 0.01: rng.pick(cities not owned by it) → influence += (its own ? 0 : −2)); burning city (any owner): hp max(5, −2), burning −= 0.5. (2) hearts: each enemy city influence += (culture·0.006 + econ·0.004 − 0.02) clamp. (3) karma drift addKarma((culture − mil)·0.0004). (4) flips: enemy influence ≥ 100 → 'you' + banner + levelup; revolt: YOUR influence ≤ −99.8 → former rival (the id-lookup quirk + rivals[0] fallback) + banner `{name} REVOLTS!` danger + influence −100 (the unrest-heal-order comment, :448-449).
- [ ] Chaos hooks (:459-526): earthquake (rng.pick city → hp max(10, −30), burning 4, camShakeFor(8,1), toast `Earthquake damages {name}!` bad 🫨); rebellion (the id-quirk filter, empty → return; rng.pick → influence max(−100, −40), toast `Unrest in {name}! (-40 influence)` bad 🔥); goldenAge (your cities: hp 100, influence +15 clamp, pop +2; toast t('Golden age! Your cities flourish.') good ✨); rivalWar (rng.pick rival, capital hp max(15, −25), banner `{RIVAL} DECLARES WAR` / subtitle 'your capital is shelled' danger, camShakeFor(6, 0.8)); rivalSurgeBegin (toast t('A rival golden age! Their forges and fleets swell.') bad 🏆) + rivalSurgeTick (per-city ×1.3 rates: military cap hp − aggression·0.12·dt, culture −1.5 @ chance 0.009·dt, economy pop min(30, +0.015·dt)); tradeWindsBegin (toast t('Trade winds! Every market on the planet hums.') good ⛵) + tradeWindsTick (regenT += dt·0.2 — the +20% share feeds the normal 6 s check, pop min(30, +0.008·dt)).
- [ ] persist/restore (:132-173) per the Global Constraints save-wire; victory (:289-296): all owned && !victoryFired → latch, save_all hook, ascend audio comment, go_to('space', {title 'THE BLACK OCEAN', sub 'a planet was never going to be enough'}).
- [ ] Hooks-Dictionary contract (the M2 pattern, `_fire` no-op on missing): hud (toast/banner/show_objective/set_toast_inset/float_world/set_abilities), save_all, go_to, add_karma, add_chaos, cam_shake_for, fx_spawn, storyteller reads (mood/gap_bias/warn_scale/note_chaos_event — verify the native storyteller method names at implementation, note any rename in the report), difficulty + player_name + genome + world reads via constructor-injected context refs. Debug cheat surface documented in the file header: `debug_set_influence(index, value)` (the bot's victory-leg grant — the civ analog of tribe's debug_grant) + `debug_clear_chaos` if needed for determinism legs.
- [ ] Headless tests: constructor seeding pins (capital fields, 3 rivals' personalities/aggressions/colors, city positions at a pinned seed), slider raise/transfer (full-board donation culture-before-econ tie, donor-0 revert + board-full toast, A/S/D lower clamp), regen 6 s → lastRaised lane only when total < output, launch gates in order (cd → stat 2 → no-targets → hopeless-refuse) + power snapshot (slider spend mid-flight does not nerf: resolve uses launch power), armada flight + resolve (net math, flip + hp floor 40, burning chance pin at a seeded stream, karma deltas per kind), rivalDefFor difficulty matrix (chaos/normal/peaceful × rival/own), tickSecond (production rates, military shell exact aggression·0.4 with the 20 floor + toast chance, culture erosion, economy buy −2 not-on-self, hearts formula, karma drift, flip, revolt incl. the −99.8-above-heal pin), chaos hooks (each effect exact), persist/restore round-trip + guards (length mismatch, owner sanitize, hp/pop/clamps, lastRaised restore, victoryFired strict), brick-hardening (go_to hook capture with exact title/sub), victory path (save_all + go_to capture, fires once).

**Verify:** `~/.local/bin/godot --headless -s res://tests/run.gd --path .` — suite green with the new tests.
**Steps:** write tests red → port sim core → green → commit `feat: civ sim core (sliders, armadas, planetary economy)`.

### Task 2: Civ chaos events deck

**Goal:** `src/game/civ/civ_events.gd` — 4 baseline + 2 gated defs verbatim (civEvents.ts); scheduler wiring in civ_sim (the M3/M4 chaos.gd pattern, NO onEnd ctx).

**Files:**
- Create: `src/game/civ/civ_events.gd`, `tests/test_civ_events.gd`
- Modify: `src/game/civ/civ_sim.gd` (deck construction + chaos update call)

**Acceptance Criteria:**
- [ ] Baseline defs (civEvents.ts:10-45) verbatim: quake {name '🫨 MEGA-QUAKE', warn 'Seismographs scream across the continent…', weight 0.7 + chaos, dur [0.1, 0.1], cd 55, apply earthquake}; rebellion {name '🔥 UNREST SPREADS', weight 0.6 + max(0, −karma)·0.8, dur [0.1,0.1], cd 45, apply rebellion}; goldenage {name '✨ GOLDEN AGE', weight 0.6 + max(0, karma)·0.9, dur [14, 20], cd 80, apply goldenAge}; worldwar {name '💥 WORLD WAR', warn 'Mobilization everywhere. Ultimatums fly…', weight 0.6 + chaos, dur [10, 10], cd 70, apply rivalWar}.
- [ ] Gated variants (:47-79): gold = worldNum(world, 'growth_mult', 1) > 1.2 (swift_world) → golden_rival {name '🏆 RIVAL GOLDEN AGE', warn 'Foreign banners gleam — their forges never cool…', weight gold ? 0.5 + chaos·0.5 : 0, dur [30, 30], cd 90, apply rivalSurgeBegin, tick rivalSurgeTick}; calm = calmProxy(world) (calm_veil) → trade_winds {name '⛵ TRADE WINDS', warn 'Sails crowd every horizon — markets hum…', weight calm ? (0.6 + max(0, karma)·0.6)·(mood == 'bless' ? 1.3 : 1) : 0, dur [40, 40], cd 100, apply tradeWindsBegin, tick tradeWindsTick} — the I-q3 bless-mood ×1.3 rides INSIDE the weight fn (the storyteller's bless mood leans on gift events; the M4 mood-weights wiring precedent).
- [ ] The deck fn mirrors makeCivChaosEvents: BASELINE + (gold ? [golden_rival] : []) + (calm ? [trade_winds] : []) — a traitless world gets EXACTLY the baseline 4 (the file-header doctrine).
- [ ] Scheduler wiring: constructed on a second rng.branch() in the sim constructor; rebuilt C1 on enter; update ctx = {chaos, karma, stageTime: time, gapMult: chaosGapMult·storyteller.gap_bias(), mood, warnScale: storyteller.warn_scale()} with onWarn (banner danger ttl 2.4 + alarm audio comment) + onApply (banner chaos + addChaos(0.03) + noteChaosEvent) and NO onEnd — verify chaos.gd tolerates the absent hook (`_fire` no-op) or teach it, per Global Constraints.
- [ ] Headless tests: traitless world → exactly 4 defs with exact ids/weights/durations/cooldowns; swift_world world (growth_mult > 1.2 fixture) → 5 defs with golden_rival present; calm_veil world → trade_winds present; bless-mood weight ×1.3 pin (the same world, mood toggled, weight ratio 1.3); duration bands TS-verbatim ([14,20] goldenage vs fixed 30/40 variants); tick wiring (a golden_rival/trade_winds live event calls the sim's tick hooks — assert the sim-side state moves: rival surge erodes, trade winds push regenT and pop).

**Verify:** suite green. **Commit:** `feat: civ chaos deck (quake, rebellion, golden age, world war, variants)`.

### Task 3: Civ stage scene node

**Goal:** `src/game/civ/civ_stage.gd` (Node2D): screen-space render port + input snapshot + the drift camera + the ruler portrait painter.

**Files:**
- Create: `src/game/civ/civ_stage.gd` + `tests/scenes/test_civ_scene.tscn` + `.gd` + `tools/test_civ_scene.sh` + `tools/visual_check_civ_scene.py`
- Test: `tests/test_civ_scene.gd` headless (boot/phase pieces that don't need pixels)

**Acceptance Criteria:**
- [ ] Render order TS-verbatim (:530-662): drawSpaceBackdrop(fakeCam{camX·0.3, camY·0.3, zoom 1, view rect, shx 0, shy 0}, vw, vh, time, **42**) → planet disc radial gradient (center offset (−pr·0.3, −pr·0.3), inner r pr·0.2) hsl(200, 0.5, 0.35) → hsl(220, 0.55, 0.16) at (vw/2 − camX·0.5, vh/2 − camY·0.5 + 40), r = min(vw, vh)·0.42 → 7 continents (a = i·2.4 + 0.7, rr = pr·(0.25 + (i%3)·0.18), ellipse rr × rr·0.7 rotated a at pcx + cos(a)·pr·0.55 / pcy + sin(a)·pr·0.5, hsl(100 + i·14, 0.3, 0.3)) → atmosphere rim glow(pr·1.18, rgba(120,190,255,0.35), 0.55) → armadas (disc 4 per kind color #ff7a5a/#c9a4ff/#5ad0a8 + glow 10 0.6 + dashed trail [4,6] alpha 0.25 from target-screen to ship-screen) → cities (disc 9 + glow 22 0.5 owner-colored #8fe89a/rival.color/#aaa + name outlinedText 12 at y−22 + `👑 yours`/rival name 9 at y+22 + influence bar 64×6 at y+30 (black 0.5 bg, fill (influence+100)/200, #8fe89a > 0.5 else #ff9a8a) + hp bar 64×4 at y+39 #9fd8ff + burning glow 26 rgba(255,140,50,0.8) 0.8) → ruler portrait (panel (18, vh−120, 96, 96) fill rgba(8,14,32,0.9) stroke rgba(140,190,255,0.4); clip rect (22, vh−116, 88, 88); draw_creature(rulerGenome, {x 66, y vh−40, facing 1, speed 0.05, gaitPhase time·2, attack 0, hurt 0, eat 0, airborne 0, mood 'happy', scale 1.4}) — the 3-RID painter contract, one painter item, freed per repaint + PREDELETE) → sliders panel ((vw−318, vh−150) 300×132 fill rgba(6,10,24,0.88) stroke rgba(140,190,255,0.35); title t('NATIONAL OUTPUT') 11 #9fd8ff centered; 3 bars [t('Q/A Military'), mil, #ff7a5a] / [t('W/S Culture'), culture, #c9a4ff] / [t('E/D Economy'), econ, #5ad0a8]: label left-aligned 11 at sx+12, track round-rect (sx+118, by, 160, 12, r 6) rgba(255,255,255,0.1), fill max(3, 160·val/10), value right-aligned 11 at sx+sw−12; by starts sy+34, step 30) → launch hints t('1 attack · 2 charm caravan · 3 trade caravan') 12 rgba(200,225,255,0.6) at (vw/2, vh−130) → victory shimmer (all owned → t('THE PLANET IS UNITED') 30 #ffe08a at (vw/2, vh/2 − 180)) → vignette 0.5. The TS `void disc;` lint artifact is NOT ported.
- [ ] Snapshot + update plumbing: the stage builds the M2 snapshot each frame (keys_pressed canonical; mouse fields present but unused — no hudRects), calls sim.update(dt, inp), then hud.set_abilities TS-verbatim (:298-305): [{key '1', icon '⚔️', cd attack/5}, {key '2', icon '🎭', cd charm/5}, {key '3', icon '💰', cd trade/5}, {key 'Q/A', icon '🔫', cd 0, active mil > 0}, {key 'W/S', icon '🎭', cd 0, active culture > 0}, {key 'E/D', icon '💰', cd 0, active econ > 0}] — every frame (TS calls it at the end of update).
- [ ] The drift camera: sim-owned camX/camY floats (update :279-287); the stage renders from them; NO Cam object, NO cam.begin/end — screen-space canvases per the M3 Part B doctrine (the live-viewport canvas_transform cancellation if the stage draws into a canvas item that needs it — same pattern as the menu/backdrop stages).
- [ ] hooks dict built by the stage (the tribe_stage pattern :855-895): hud/audio noop hooks + the real game/hud bridges; the sim's `update` invoked from `_process` with the fixed-timestep accumulator (the M2 loop pattern).
- [ ] Headless tests: the sim receives the snapshot keys (Q tap → mil +1 with the transfer toast; Digit1 with stat ≥ 5 → armada spawned), set_abilities payload mirrors sliders/cds each frame, on_enter sets toast_inset 150 + showObjective (hud hook capture), render does not crash pre/post restore.
- [ ] xvfb scene test (the test_tribe_scene pattern): fixture world → phases → captures: planet-day (backdrop stars band, planet disc radius band, ≥ 3 continent blobs, atmosphere rim), cities (4 discs owner-colored + name labels + influence/hp bars), armada flight (ship disc + dashed trail + the launch toast), sliders panel (3 labeled tracks with proportional fills — a full 10 bar vs a near-empty bar width ratio pin), ruler portrait (creature pixels inside the clip rect, NOT outside it), victory shimmer ('THE PLANET IS UNITED' full-alpha vs absent pre-victory). Freeze-arm doctrine: sim-state-conditioned fixtures only, NO engine-frame gates. ≥ 3 structural asserts per moment; python checker in the visual_check family.

**Verify:** `tools/test_civ_scene.sh` exit 0; headless suite green. **Commit:** `feat: civ stage scene (planet render, portrait, sliders panel)`.

### Task 4: Wiring — registration, tribe→civ landing, civState save/continue, space placeholder

**Goal:** The game-level wiring: CivStage registration, toast_inset 150 live, the M4 tribe-victory placeholder becomes the REAL landing, civState save/continue E2E, victory → space placeholder with the BLACK OCEAN title/sub, brick-hardening E2E, i18n.

**Files:**
- Modify: `src/main.gd` (registration: the boot list AND resetStagesForNewRun's fresh-instance list — civ in BOTH, boot order cell → creature → tribe → civ), extend `tests/test_world_creature_pins.gd` (civ save/continue pins)
- Create: `tests/test_hud_civ.gd`

**Acceptance Criteria:**
- [ ] Registration: main.gd preloads + registers CivStageScript after TribeStage (both the boot register AND the quit-to-title fresh list — the drifter rule); the constructor's context-rng branch joins the boot-order pin (cell → creature → tribe → civ).
- [ ] toast_inset 150 flows (the game.ts:213 rule — game.gd:262 already resets to 0 on switch; the civ stage re-arms on enter): toasts draw at vh − 30 − inset clearing the portrait panel (hud.gd:303 seam already wired — verify end-to-end with a capture or a hud-state assert).
- [ ] Tribe→civ landing E2E headless: the M4 bot test's placeholder assert (civ unregistered → switch_stage no-ops) upgrades: with civ REGISTERED, the tribe victory go_to('civ', {title 'THE FIRST CITY', sub 'drums become laws; laws become empires'}) lands the CivStage — on_enter fires (toast_inset 150, objective set), the constructor-seeded board stands (4 cities), NO double-banner (the transition title comes from the tribe side — the M4 task-4 ruling).
- [ ] civState save/continue E2E: civ-stage save_all (on_exit persist + the victory saveAll flush) → CONTINUE → restoreState true → the board AS IT STOOD (influences, owners, sliders, lastRaised, victoryFired) — the TS :132-134 doctrine comment rides along ('CONTINUE mid-civ used to reset sliders…'). The guards E2E: a stale length-mismatch blob → false → fresh board.
- [ ] Victory → space placeholder E2E: unify (debug_set_influence cheat + one honest launch per the Task-5 cheat surface, or direct cheat flip in the headless test) → victoryFired latch + save_all hook + go_to('space', {title 'THE BLACK OCEAN', sub 'a planet was never going to be enough'}) captured; space UNREGISTERED → switch_stage no-ops, the civ stage remains (the M3 placeholder ruling pattern — the transition object's title/sub must be SWALLOWED, not crash).
- [ ] Brick-hardening E2E: flags.civState = a unified blob (victoryFired true, all owned) → CONTINUE → civ on_enter → the space transition fires immediately with the exact title/sub (the old silent softlock pin, TS :123-128).
- [ ] i18n: every t() site in the civ surface mapped in assets/i18n/vi.csv (the TS VI object check — the M4 T8 1:1 method: grep the TS VI object for the civ strings; any UNwrapped TS site stays unwrapped; normative absences pinned `vi_has == false` in the report). The t() sites: 'Board full — lower another slider first', 'No city left to persuade — build output!', 'armada →', 'Golden age! Your cities flourish.', 'A rival golden age! Their forges and fleets swell.', 'Trade winds! Every market on the planet hums.', 'NATIONAL OUTPUT', 'Q/A Military', 'W/S Culture', 'E/D Economy', '1 attack · 2 charm caravan · 3 trade caravan', 'THE PLANET IS UNITED'. Raw (non-t) strings stay raw: the objective line, the raise/spend refusals, 'JOINS YOUR PLANETARY STATE', 'REVOLTS!', the shell/quake/unrest toasts.
- [ ] Headless tests: all five flows pinned with real transitions.

**Verify:** suite green. **Commit:** `feat: civ wiring (registration, tribe handoff, save/continue, space placeholder)`.

### Task 5: Civ bot + flow integration

**Goal:** `tests/bots/bot_civ.gd` through the REAL input pipeline; determinism ×2.

**Files:**
- Create: `tests/bots/bot_civ.gd` + `tests/scenes/test_bot_civ.gd` + `.tscn` + `tools/test_bot_civ.sh`

**Acceptance Criteria:**
- [ ] Bot law (the M2/M4 standing law): every input through bot_driver._send → Input.parse_input_event + flush; field reads OK; direct sim calls ONLY the documented debug cheats (debug_set_influence from the Task-1 header — the civ analog of tribe's debug_grant).
- [ ] Bot arc: arrival via the REAL tribe victory (reuse bot_tribe's founding→totem leg — the totem arc lands civ through the real go_to; do NOT re-implement the tribe legs, reuse the bot_tribe module or its recorded arrival route), then in civ — ALL real keys: Q-taps to raise mil (observe the full-board transfer toast at output 10), Digit1 attack armada at mil ≥ 5 (the honest-launch gate), the armada FLIES (ship disc + trail in the capture), resolve observed (influence delta floatWorld + the net math on the read-back), regen refills mil (lastRaised lane) between launches. 2+ honest launches asserted.
- [ ] Victory leg: debug_set_influence to the flip threshold on the un-owned cities (the documented cheat), then ONE real Digit1 launch flips the nearest → all owned → victoryFired → the space placeholder transition captured with the exact title/sub; the civ stage remains (unregistered space no-op).
- [ ] Determinism ×2: the full bot at a pinned seed → identical fingerprints (the M2/M3/M4 pattern, per-600-frame sweep trace).
- [ ] Chaos note: the pinned seed's chaos behavior is whatever it is — the arc asserts must not depend on chaos-free (the M4 bot lesson); the determinism gate carries replay.
- [ ] Bot law audit in the report: the cheat list vs the sim header's documented surface, 1:1.

**Verify:** `tools/test_bot_civ.sh` exit 0 ×2 determinism; suite green. **Commit:** `feat: civ bot (sliders, armadas, unification, determinism)`.

### Task 6: Civ probes + visual moments + PARITY-M5

**Goal:** The QC gates, civ flavor.

**Files:**
- Create: `tests/test_probe_civ.gd` + `tools/probe_civ.sh`; Modify: the scene visual harness (civ moments), `docs/PARITY-M5.md`

**Acceptance Criteria:**
- [ ] Probes (headless, TS-verbatim, pinned seeds — the test_probe_tribe shape, every assert an independent derivation at a pinned seed with a provenance comment): slider transfer math (full-board Q: mil +1, culture −1, the tie-break culture-before-econ pin at a seeded stream), regen lane pin (spend → lastRaised refills THAT lane, 6 s cadence exact), launch gate ladder (each refusal toast + the honest launch's power snapshot survives a mid-flight slider drop — the TS :326-327 comment pin), resolve net math ((power − rivalDef)·10 exact across the difficulty matrix), flip + hp floor (influence ≥ 100 → owner flip, hp max(hp, 40)), burning pin (attack chance 0.5 at a seeded stream — instrumented rng draw), tickSecond personalities (military shell aggression·0.4 with the 20 floor; culture −1.5 @ 0.03; economy pop +0.05 + the buy −2 not-on-self), hearts formula (culture·0.006 + econ·0.004 − 0.02 per second exact), karma drift ((culture − mil)·0.0004), revolt (−99.8 ABOVE the +0.12 heal — a city at −100 revolts, heals to −99.88 otherwise: the TS :448-449 pin), unrest heal (+0.12 toward 0), goldenAge/tradeWinds/rivalSurge effects exact.
- [ ] Visual moments (xvfb, the T10 pattern): planet backdrop day, cities + bars, armada flight + trail, sliders panel, ruler portrait clip, victory shimmer. Each ≥ 3 structural asserts (may share the scene-test captures — the moments run in the PROBE harness too per the M4 pattern; count them in PARITY-M5).
- [ ] `docs/PARITY-M5.md`: per-feature rows (the M3/M4 format) — every civ feature with TS line + native pointer + test pointer; the §5.4-style criteria checklist (a)-(d); the M6 deferred list (space stage registration, the space surface notes, the standing carry-forwards: creature painter perf M4-optimization prerequisite, audio core).

**Verify:** `tools/probe_civ.sh` exit 0; visual suite exit 0. **Commit:** `test: civ probes` then `test: civ visual moments + parity list`.

### Task 7: M5 wrap — A-B, perf, review, tag

**Goal:** Close M5.

**Files:**
- Modify: `docs/PARITY-M5.md`, `docs/ARCHITECTURE.md` (civ section), README (status row)

**Acceptance Criteria:**
- [ ] A-B run: base `tribe-parity-m4` → HEAD, cell-state dump IDENTICAL (the standing dump must not move — the civ stage is additive; the boot-order rng branch joins the replay pin, and the M4 precedent says stage-constructor branches do not move the cell dump — any diff line ruled).
- [ ] Perf: civ sim tick @ 4 cities + live armadas measured headless (the split metric — sim vs render vs frame, the T11/M4 pattern); sim_avg_ms asserted ≤ 2 ms (expect ≪ — 4 cities vs tribe's 60 sims); painter draw pass ≤ 4 ms; tripwires standing; the row recorded in PARITY-M5.
- [ ] ARCHITECTURE.md civ section (module map, the screen-space no-Cam render pattern + fakeCam, the drift camera, the hooks surface, the debug cheat surface, the brick-hardening gate); README status row (M5).
- [ ] Full suite green: headless runner + all xvfb entries (bot, bot_creature, bot_tribe, bot_civ, editor_click, menu, visual ×2, creature_scene, tribe_scene, civ_scene, perf ×2, boot, visual_suite).
- [ ] Final whole-branch review (controller) → riders → tag `civ-parity-m5` + PARITY-M5 completion note.

**Verify:** `./tools/test.sh` green; `git tag` shows `civ-parity-m5`. **Commit:** `docs: M5 wrap (parity table, perf, architecture)`.

---

## Completion

- [ ] All 7 tasks complete, final whole-branch review TAG-READY, tag `civ-parity-m5`, PARITY-M5 completion note, ledger closed.
- **Next milestone:** M6 = Space (SpaceStage.ts 52.2K + spaceEvents.ts 2.5K — the §5.4 gates at space flavor; the largest TS file in the arc — plan to be written fresh), then M7 = CI/release + repo overwrite.
