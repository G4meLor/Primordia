# M4 Tribe Stage Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full TS-verbatim port of the Tribe stage (RTS-lite: gather/build/roles, rival raids, beast, lightning fires, festivals, Great Totem → civ handoff) — playable, §5.3-gated, tagged `tribe-parity-m4`.

**Architecture:** Mirror the creature milestone's shape exactly: `tribe_sim.gd` (RefCounted sim core, hooks-Dictionary, `update(dt, inp)` M2 snapshot) + `tribe_stage.gd` (Node2D scene: the T7 land backdrop reuse, z-sorted painter draws, Cam) + `tribe_events.gd` (world-parameterized chaos deck) + the founding handoff from creature's `found_tribe` + save/continue via the `tribeState` flags blob + bot/probes/PARITY-M4.

**Tech Stack:** Godot 4.2.2 + GDScript typed; the frozen TS authority at ~/Desktop/RD/Spore (read in full for this plan: src/game/tribe/TribeStage.ts 1431 lines + tribeEvents.ts 156 lines, 2026-10-01 state incl. the war_graves/rival_festival wiring).

**Spec:** docs/specs/2026-09-29-native-migration-design.md §5.4 (same 4 criteria gates as §5.3, tribe flavor).

**Milestone ruling:** spec §5 doctrine is "mỗi bước = một milestone chơi được/test được" — Tribe → Civ → Space are THREE steps in one bullet, so they become three milestones: **M4 = Tribe** (this plan, tag `tribe-parity-m4`), M5 = Civ, M6 = Space, then M7 = CI/release + repo overwrite. Each keeps the M3 gate shape (feature list + bot arc + probes + pixel asserts + A-B + perf).

## Global Constraints

- **Parity-pin porting:** TS logic/constants/draw-order 1:1; every divergence documented in the file header + report; rng draw order sacred (lazy where TS lazy; TS `Math.random()` sites → the stage rng IN-STREAM with a header note + replay pin — the tribe deck has exactly 2 sites: storm apply `2 + Math.random()*4` and storm tick `Math.random() < 0.01` (tribeEvents.ts:20/24)).
- **Save-wire camelCase TS-verbatim:** `tribeState`, `packGenomes`, `firstRaidHint`, `showObjective` values ('GATHER · BUILD · SURVIVE — raise the Great Totem').
- **No Input singleton reads in the sim** — the STAGE builds the M2 snapshot {mx,my,wx,wy,down,clicked,take_click,keys_held,keys_pressed} (keys_pressed canonical); bot law (all bot input through Input.parse_input_event + flush; direct sim calls only the documented debug cheats).
- **No randi/randf anywhere** — the sim's rng only.
- Float discipline: pure-float f64 Dictionaries in the sim; Vector2 only at solve boundaries (the creature painter contract — reuse as-is).
- **TS line citations dense and accurate** in every ported file (the final review's verified standard).
- Tribe constants that DIFFER from creature (port per-stage, do not share): WORLD_HALF **2400** (creature 2700), cam follow rate **4** zoom **0.95** (creature 5/1.15), lawn stops **hsl(105−chaos·30, 0.3, 0.28) / hsl(95−chaos·30, 0.36, 0.2)** with NO isNight dim (creature 0.32/0.30−0.12), day cycle **240 s** (creature 180), night window (0.55, 0.95) same, night overlay **rgba(10,10,40, 0.4)** flat (creature depth·0.42), vignette **0.4**.
- The chief IS the player creature (drawCreature with ctx.genome, scale 2.1, mood 'happy') — the creature painter serves the tribe stage unchanged.
- `hud.toastInset = 190` — the tribe stage is the first native setter (M3 ruling recorded civ 150/tribe 190; verify src/ui/hud.gd supports toast_inset — if the M2 port omitted it, add it in task 5).

**User decisions (already made):** none this plan (the milestone split ruling above is the controller's, ledgered).

---

### Task 1: Tribe sim core — state, chief, tribesmen, economy

**Goal:** `src/game/tribe/tribe_sim.gd` (RefCounted, M2 patterns): all state fields, constructor world-seeding, on_enter semantics (restore/re-found/pack conversion), chief movement + death/respawn, tribesman AI (fight/job/arrive), economy (deliveries, regrow, saplings, hut build/repair/recruit, totem progress, festival passive), popCap.

**Files:**
- Create: `src/game/tribe/tribe_sim.gd`
- Test: `tests/test_tribe_sim.gd`

**Acceptance Criteria:**
- [ ] Constants TS-verbatim (TribeStage.ts:21-24): Z_TO_Y 0.62, Z_MIN −200, Z_MAX 240, WORLD_HALF 2400. Constructor seeds (101-137): 30 trees (x∈[−2400,2400], z∈[−200,240], wood rng 4..9, seed rng 0..9), 26 bushes (food rng 3..7), 1 starting hut {x 0, z 80, hp 100, maxHp 100, pop 0, buildT 0}, 2 rivals (±1 side, x rng 1300..2000, z rng −120..160, hp 100, names Gnash/Ruk), food 60 wood 30, dayPhase 0.2, raidTimer 75.
- [ ] popCap = built huts (buildT ≤ 0) × 3 + 1 (:272). onEnter (:139-191): deckSeed rebuild gate (C1), chiefStats recompute, fallenT/fallFired/victoryFired/deathHandled resets, invulnT 3, restoreState() short-circuit with the showObjective set; hutless re-found reseeds hut+food+wood; pack conversion ONCE (`tribe.length == 0`): raw = JSON.parse(flags.packGenomes ?? '[]') guarded, count = max(3, raw.length), genomes clamp_genome'd (never clone-only — NaN genes crashed every frame), else mutateLike(ctx.genome); flags.packGenomes = '[]' after.
- [ ] persist_state (:197-210): corpse guard (fallenT > 0 && tribe 0 && huts 0 → write nothing); blob {food, wood, huts map (x,z,hp,maxHp,pop,buildT), totemProg, totemActive, tribe map (genome, role)} → flags.tribeState JSON. restore_state (:212-244): non-finite food/wood → false; EMPTY village (0 huts AND 0 tribe) → false; REPLACE the roster (never append — the 3→6→12 doubling bug); cap slice(0, max(12, huts·3+1)); role sanitize ('hunt'/'warrior' else 'gather'); totem progress clamp 0..100.
- [ ] Chief (:456-516, :422-454): click-move (deadzone 12, wy/Z_TO_Y clamp) + WASD; accel/drag `exp(−6dt)`, vz accel ×0.8, speed clamp from chiefStats; gait += dt·(3 + speed01·9); role hotkeys Digit1/2/3 → assign_role (all tribesmen, toast "Everyone: {role}"); KeyR → try_build_hut (death/hutCd guards, wood ≥ 40 CHECK BEFORE the 2s cooldown arms — the A-rank fix), KeyT → try_totem (active/empty-tribe/100-food-80-wood gates, banners); hut-proximity heal is a TS noop (line 487-491 — dna += 0); raid-touch death (dist < 40, chance dt·2, invuln/deathFade gates, 'raiders cut you down'); handle_chief_death: 15% DNA tax once (deathHandled latch), toast with cause, respawn at 1.6s to the SAFEST of 8 sampled points (farthest from beast + warriors + fires, minD 9999 fallback), invulnT 3.
- [ ] Tribesmen (:586-718, :747-856): hurtT/attack/eatT decays ×3/×2/×2; fight rivals < 44 (power warrior 1.6 / hunt 1 / gather 0.5, dmg 22·power·dt, self-damage 10 @ chance dt·1.2, mood angry, stand ground drag exp(−4dt)); else tribe_job_ai (retarget cadence 0.5s; gather: wood quota — while wood < 80 every EVEN-INDEXED tribesman chops trees regardless, nearest bush radius 600 else tree; hunt: bush 600 else tree; warrior: patrol hut ±90/±60, rare rival march chance 0.005); movement accel 260/208·dt, drag exp(−5.5dt), speed cap stats.speed·0.8, z clamp; death splices + burst + toast 'A tribesman has fallen…'; delivery food/wood +8 (tribeArrive via the economy arrivals block :1088-1102 with atHut/atChief < 44 gates); pickup < 30 (bush food −1 + regrow 30; tree wood −1, burning excluded).
- [ ] Economy (:1086-1172): bush regrow (empty → rng 3..7 after 30 s); sapling every 45 s while alive trees < 30 (same ranges as constructor); tree burnout (burn → wood 0); hut build 6 s (toast 'A new hut raises the roof!'), repair +5·dt to maxHp, recruitT 45 s + no-recruit mid-siege (rivalWarriors 0 gate) + popCap gate ('A child was born in the hut! (+1 tribesman)'); totem progress += workers·dt·1.6 (clamp 100); festival passive (food > 80, chance dt·0.05: karma +0.01, food −5, mood happy).
- [ ] MutateLike (:1426-1431): hue ±40 wrap, size + gauss·0.1 clamp 0.6..2.2 — same mutation seam as the sim's existing mutate helpers (reuse creature_sim's if signatures match, else port locally; note the choice).
- [ ] Headless tests: constructor seeding pins (30/26/1/2 counts + ranges at a pinned seed), popCap formula, onEnter pack conversion (3 minimum, clamp guard, packGenomes reset), persist/restore round-trip + the THREE corrupt-blob guards (non-finite, corpse blob, replace-not-append), chief movement integration + death/respawn geometry, tribesman job AI branches (quota on/off, fight power ×3 roles), economy integration (delivery +8, regrow, recruit gates incl. the mid-siege block), totem progress.

**Verify:** `~/.local/bin/godot --headless -s res://tests/run.gd --path .` — suite green with the new tests.
**Steps:** write tests red → port sim core → green → commit `feat: tribe sim core (chief, tribesmen, economy)`.

### Task 2: Raids, beast, fires, storm helpers, fall/victory

**Goal:** The rival war machine + hazards + the two stage-transition paths.

**Files:**
- Modify: `src/game/tribe/tribe_sim.gd`
- Test: `tests/test_tribe_sim.gd` (extend)

**Acceptance Criteria:**
- [ ] Raid clock (:327-339): invuln decay, raidTimer −= dt; peaceful && huts 0 → raidTimer floored at 30; fire when ≤ 0 and (not peaceful || huts > 0): reset 80 + rng(−15, 25), peaceful +40; first-raid hint once (flags.firstRaidHint = 'seen', toast 'Raiders rally beyond the ridge — press 3 to arm warriors!' kind bad ⚔️); launch_rival_raid (:561-584): rng.pick(rivals), hp ≤ 0 → return, party cap 5 alive, wave = peaceful ? 1 : 2, n = min(wave + floor(rng 0..2), 5 − alive); warriors spawn at rival ±60/±40, hp 60, genome = ctx genome clone overrides hue 5 / diet carnivore / spikes 3 / jaw 3, state march; banner '{NAME} RAIDS!' + raidActive = true.
- [ ] Rival warrior update (:656-707): hp ≤ 0 → splice + food +8; march target = nearest BUILT hut (fallback: nearest tribesman when hutless — the pop-1 fix), flee → home rival; accel 240/190·dt, drag exp(−5dt), gait += dt·8; hut siege (dist < 40, state march): hp − 6·dt, crack fx @ chance dt·6, destruction splices + raidTimer floored at 120 + 'A HUT BURNS' + boom; hutless+tribeless → flee; flee → home < 90 → slip away splice.
- [ ] Tribe-vs-rival-camp assault (:858-879): warriors within 90 of a living rival camp deal 4·dt each, anger +0.1·dt clamp 1; rival death → '{NAME} JOINS YOUR PEOPLE' + food +60 wood +40 + karma −0.05.
- [ ] war_graves combo (:709-717): raidActive && warriors emptied → raidActive false; combo_active(world, 'war_graves') → DNA +15 'war graves' + toast 'War graves yield DNA.' reward ⚔️ — once per raid instance (verify world_genome combo_active exists; port if M2 omitted it).
- [ ] Beast (:881-935, :1004-1021, :969): spawn (genome ctx clone size 2.1 carnivore jaw 5 spikes 4 horns 3 hue 300 coat plates eyes 4, angle rng·TAU, dist 900/300 clamped, hp 420); march to nearest hut (90/70·dt) or chief; siege 6·dt + 'THE BEAST DESTROYS A HUT'; fighters < 60 → 9·dt each + chief near 14; gore chance dt·0.5 chief-proximity-gated (the A08 fix comment stays) → 'the great beast gored you'; death → 'THE GREAT BEAST FALLS' + food +60 + DNA +50 + levelup; despawn → 'The great beast wanders away…'.
- [ ] Fires (:937-967): ttl decay, tribesman extinguish (nearby < 50 → ttl − 4·dt each), smoke fx @ chance dt·10, spread (spread 8, chance 0.25, unburnt tree < 90 → ignite), splice at 0; ignite_tree (burn 8, fires push ttl 10 spread 8, stump guard, 'fire' audio); lightning_strike (:971-993): targets = unburnt trees + huts, none → 'The storm crackles…' info ⚡; rng.pick; HUT branch (the TS duck-typing `'speciesId' in t || !('wood' in t)` → port as an explicit type check with a comment): hp − 35 → 'LIGHTNING SPLITS A HUT' at 0; tree → ignite; shake 6/0.4 + zap + 'Lightning! Fire spreads with the wind!'.
- [ ] Stage timers (:306-313, :998-1002): `{left, fn}` drain (splice then call) — the tribe sim's own `after()` (the volcano-timer seam the M3 review verified: fn ALWAYS runs after removal).
- [ ] Fall path (:381-398): tribe 0 && huts 0 && fallenT 0 → fallenT 0.0001 + 'THE TRIBE HAS FALLEN' banner (ttl 6) + die audio; fallenT > 4 && !fallFired → latch, DELETE flags.tribeState, save_all (hook), fire go_to('creature', {title 'BACK TO THE WILDS', sub 'gather your strength and found a new people'}) — via the go_to hook (the sim cannot see the game).
- [ ] Victory path (:400-409): totem ≥ 100 → victoryT; > 2.5 && !victoryFired → latch, save_all hook, ascend audio hook, go_to('civ', {title 'THE FIRST CITY', sub 'drums become laws; laws become empires'}).
- [ ] Headless tests: raid clock cadence + peaceful gates + first-raid hint once; party cap/wave math; siege → hut destruction → raidTimer 120 floor; flee-home slip; rival camp death rewards + karma; war_graves payoff once-per-raid (combo on/off); beast full lifecycle; fire spread/extinguish/lightning hut-vs-tree branches; timer drain fn-always-runs; fall path (blob delete + go_to hook capture) + victory path (go_to hook + latches).

**Verify:** suite green. **Commit:** `feat: tribe raids, beast, fires, fall/victory`.

### Task 3: Tribe chaos events deck

**Goal:** `src/game/tribe/tribe_events.gd` — 5 baseline + 4 gated defs verbatim; scheduler wiring in tribe_sim (the M3 chaos.gd pattern: warn_fn seam, MirrorLedger, world gates).

**Files:**
- Create: `src/game/tribe/tribe_events.gd`
- Modify: `src/game/tribe/tribe_sim.gd` (chaos update call)
- Test: `tests/test_tribe_events.gd`

**Acceptance Criteria:**
- [ ] Baseline 5 (tribeEvents.ts:10-77): storm 0.7+chaos [14,22] cd 55 (apply: quake audio + after(rng 2..6) → lightning — **Math.random → stage rng in-stream, divergence documented**; tick: elapsed > 6 && rng chance 0.01 → lightning); beast 0.6+chaos [25,25] cd 65 (spawn/despawn); rivalsurprise 0.6 − karma·0.3 [10,10] cd 70 (raidsBlocked refuse keeps the warning honest); festival 0.8 + max(0, karma) [16,22] cd 80; gift 0.5 flat [10,14] cd 90 (star_shower: DNA +80, float_world, toast).
- [ ] Gated 4 (:79-155): bold_raid (worldHas raider_bold / pirate_wind — PLUS the rivalsurprise ×1.5 weight remap in the same gate) 0.5+chaos·0.6 [0.1,0.1] cd 55; rival_festival (calm_veil: speciation_mult < 1) (0.7 + max(0,karma)·0.5) × (mood bless ? 1.3 : 1) [16,22] cd 90 (pause_raid 45 + festival); siege_hoard ALWAYS in deck, weight = dominance > DOMINANCE_THRESHOLD ? 0.6·dominanceSeverity : 0 [16,24] cd 100 (launch + after 9 second wave — the ONE severity formula, cap like #3); festival MIRROR face (mirrorBucket cradle): SAME id 'festival' + mirrorOf, weight mirrors-include 0.9, apply festival_mirror (exactly ONE rule inverted: mood afraid instead of happy; food −20 and 3 spread-999 fires stay — :1041-1064 both bodies verbatim).
- [ ] Scheduler wiring (:341-369): chaos.update(dt, this, {chaos, karma, stageTime, gapMult: ctx.chaosGapMult·storyteller.gapBias(), mood, warnScale: storyteller.warnScale(), mirrors: mirrorLedger.queued(), dominance: wealthPressure()}) — wealthPressure = min(1, (food+wood)/500); onWarn (static warn → banner danger ttl 2.4 + alarm 0.5); onApply (banner kind chaos + ctx.addChaos(0.03) + mirrorOf onFired + storyteller.noteChaosEvent); onEnd (mirrorLedger.maybeQueue(rng, def.id, 'festival')). mirrorLedger = a MirrorLedger instance on the sim (port from M2's chaos.gd — verify it exists).
- [ ] Headless tests (the task-5 test shape): verbatim-constants pin; weight formulas at 1e-12 (incl. the ×1.5 remap and bless ×1.3); raid-refuse branches; siege two-wave via the timers; mirror-once flow (queue survives a no-warn spawn); deck order traitless = 5 + siege_hoard.

**Verify:** suite green. **Commit:** `feat: tribe chaos events + scheduler wiring`.

### Task 4: Tribe stage scene node

**Goal:** `src/game/tribe/tribe_stage.gd` (Node2D, the creature_stage pattern): render port + input snapshot + the tribe camera.

**Files:**
- Create: `src/game/tribe/tribe_stage.gd` + `tests/scenes/test_tribe_scene.tscn` + `.gd` + `tools/test_tribe_scene.sh` + `tools/visual_check_tribe_scene.py`
- Test: `tests/test_tribe_scene.gd` headless (the boot/phase pieces that don't need pixels)

**Acceptance Criteria:**
- [ ] Render order TS-verbatim (:1176-1394): draw_land_backdrop(ctx, cam, vw, vh, time, chaos, dayPhase, horizonScreenY = vh/2 + (0 − cam.y)·zoom) → cam.begin → lawn gradient (two stops hsl(105−chaos·30, 0.3, 0.28)/hsl(95−chaos·30, 0.36, 0.2), lawnH = (Z_MAX+120)·Z_TO_Y, fillRect view span) → draw_ground(..., 500, time, chaos) → rival camps (disc 60 rgba(120,60,40,0.25) + 3 totem poles hsl(30,0.3,0.35) rect 8×34 + disc 6 hsl(10,0.5,0.45) + name outlinedText 12) → bushes (ellipse 15/10 hsl(120,0.36,0.24), berries min(4, ceil(food/2)) discs 2.4 #ff6a9a) → huts (alpha built 1 : 0.5; walls rect 44×26 hsl(30,0.32,0.4:0.3); roof triangle ±30 → y−52 hsl(18,0.42,0.34); door 14×14 hsl(28,0.3,0.2); damage cracks stroke when hp < 60% maxHp; '🏠{hp}' outlinedText 9) → totem (progress-scaled rect 20×90·p hsl(40,0.4,0.4) at x −10; discs at p 0.3/0.6; glow at 1; 'TOTEM {p}%' label) → trees AFTER totem (sway sin(time·0.6 + seed)·2.5; quadratic trunk lw 8 hsl(28,0.32,0.26); crown ellipse 26/20 hsl(120,0.38,0.26) or burn hsl(20,0.8,0.45) + glow) → z-sorted drawables (the creature_stage insertion pattern: tribesmen scale 1.7 + role/cargo icon 🍒🪵⚔️🥩 + hp bar 28×3 #8fe89a when damaged; rival warriors scale 1.7 mood angry + ⚔️; beast scale 2.6 + 🦁 + hp bar 48×4 #ff5a5a; chief scale 2.1 mood happy + 👑, hidden while deathFade > 0.4) → fires glow on top (rgba(255,140,40,0.65) r 34) → fx renders → cam.end → night overlay rgba(10,10,40,0.4) full-canvas at isNight (0.55, 0.95) → vignette 0.4 → HUD → death card (red veil min(0.55, fade·0.4) + 'THE CHIEF HAS FALLEN' 26).
- [ ] HUD (:1400-1423): stockpile panel at (18, vh−172) 210×52 + '🍒 {food} 🪵 {wood}' 16 + '👥 {tribe}/{popCap} 🏠 {huts}' 13; hut button (18, vh−110) 170×40 (canHut = wood ≥ 40, green/dim fill, 'R · HUT (40🪵)'); totem button (18, vh−64) (canTotem = !active && food ≥ 100 && wood ≥ 80; active shows '🗿 TOTEM {p}%'); **hudRects re-registered each frame** (filter+push, action 'hut'/'totem') and dispatched in UPDATE not render (the sim owns the click; the stage carries rects to the sim via the snapshot or a stage-side callback — match the creature_stage tribeRect pattern: the sim holds the rects, the stage re-positions them each frame).
- [ ] Camera + snapshot: cam.follow(px, pz·Z_TO_Y, dt, **4**), cam.zoom = **0.95**, wx/wy from cam.to_world into the snapshot; abilities setAbilities (1 🍒 / 2 🥩 / 3 ⚔️ active when ALL tribesmen hold that role, cd 0); dayPhase advances dt/240.
- [ ] The 3-RID painter contract honored for EVERY creature draw (tribesmen, warriors, beast, chief) — one painter item per creature (pooled pairs like creature_stage); RIDs freed per repaint + PREDELETE.
- [ ] main.gd registers TribeStage (the M4 entry: creature found_tribe's transition_target 'tribe' now LANDS — go_to('tribe') after THE FIRST FIRE… wait, TS: creature's found_tribe fires the 'THE FIRST FIRE' transition INTO tribe (task-9's placeholder); the registered stage makes it real. Verify the creature→tribe transition title comes from the creature side (task 9 pinned 'THE FIRST FIRE' on the transition object) — do not double-banner.)
- [ ] xvfb scene test (the test_creature_scene pattern): fixture world → phases → captures: village-day (lawn band, hut shapes, totem), raid (warriors present + banner), night (overlay + campfire glows), death card, z-order (a tribesman at z 100 over the chief at z 60 — Ruling 14 class), toast-inset panel position. ≥ 3 structural asserts per moment, python checker in the visual_check family.

**Verify:** `tools/test_tribe_scene.sh` exit 0; headless suite green. **Commit:** `feat: tribe stage scene (render, camera, HUD panel)`.

### Task 5: HUD wiring, founding handoff, save/continue

**Goal:** The game-level wiring: toastInset 190, objective line, creature→tribe founding E2E, tribeState save/continue.

**Files:**
- Modify: `src/ui/hud.gd` (toast_inset if the M2 port omitted it), `src/game/game.gd` (stage routing already generic — verify), `src/main.gd` (TribeStage registration)
- Test: `tests/test_hud_tribe.gd`, extend `tests/test_world_creature_pins.gd` (tribe save/continue pins)

**Acceptance Criteria:**
- [ ] hud.toast_inset = 190 set by tribe_stage on enter, reset per the game.ts:213 rule ('stages with bottom-left UI re-arm their own inset' — game resets to 0 on stage switch; verify the native game.gd does the same reset, port if missing); toasts draw at vh − 30 − inset (hud.ts:274) — verify/wire the draw side.
- [ ] Founding E2E headless: creature sim found_tribe → transitionTarget 'tribe' → game switch lands the REGISTERED TribeStage → pack conversion consumed (packGenomes → tribesmen, minimum 3) → packGenomes '[]' after. (The task-9 bot test's placeholder assert upgrades to the real landing.)
- [ ] Save/continue: creature-stage save_all → CONTINUE → tribe (found_tribe path re-runs restore); TRIBE-stage save mid-progress (hut built, food gathered) → CONTINUE → restoreState returns true → village as it stood (food/wood/huts/totem/tribe) — the persist-on-exit + autosave seam (game save_all has_method('persist_state') calls tribe_stage.persist_state like creature's).
- [ ] The fall path E2E: a dead village → 'BACK TO THE WILDS' transition lands creature with the blob deleted (no resurrection on re-found — the 3-bounce bug's pin).
- [ ] i18n: every tr() site in the tribe surface mapped in assets/i18n/vi.csv (grep the TS VI object for the tribe strings — same 1:1 verification as T8: any UNwrapped TS site stays unwrapped).
- [ ] Headless tests: all five flows pinned with real transitions.

**Verify:** suite green. **Commit:** `feat: tribe HUD wiring + founding handoff + save/continue`.

### Task 6: Tribe bot + flow integration

**Goal:** `tests/bots/bot_tribe.gd` through the REAL input pipeline; determinism ×2.

**Files:**
- Create: `tests/bots/bot_tribe.gd` + `tests/scenes/test_bot_tribe.gd` + `.tscn` + `tools/test_bot_tribe.sh`
- Test: extend `tests/test_world_creature_pins.gd` if flow pins need a home

**Acceptance Criteria:**
- [ ] Bot arc (the TS bot-tribe test if one exists — grep ~/Desktop/RD/Spore/tests/ for the tribe bot shape and port ITS cheats verbatim; if none exists, the bot mirrors the creature bot's TS-true cheat set: direct start_new_game, then everything real): arrival via the REAL founding transition (creature stage → found_tribe through the real tribe button — reuse bot_creature's founding leg), then in tribe: assign roles (Digit1/2 real taps), watch a tribesman deliver (+8 food), build a hut via the REAL drawn R · HUT button click (wood granted via debug_grant to 40+ — the documented cheat), recruit gate observed, raise the totem via the REAL drawn TOTEM button (debug_grant food 100+ wood 80+), totem progress advances with workers, victory transition fires → civ placeholder (unregistered → switch_stage no-ops, the tribe stage remains — the M3 placeholder ruling pattern).
- [ ] Raid survival leg: debug-spawn a raid (or wait the clock with the raidTimer made deterministic via a debug seam — prefer the real clock with a pinned seed), warriors march, a hut takes damage, war party can be fought off; assertions: banner fired, raidActive lifecycle.
- [ ] Determinism: the full bot ×2 at a pinned seed → identical fingerprints (the M2/M3 pattern, per-600-frame sweep trace).
- [ ] Bot law audit clean: every input through parse_input_event + flush; direct sim calls ONLY the documented debug cheats (add `debug_grant` reuse + any tribe-specific cheat to the documented surface in the sim header).

**Verify:** `tools/test_bot_tribe.sh` exit 0 ×2 determinism; suite green. **Commit:** `feat: tribe bot (founding, gather, build, totem, determinism)`.

### Task 7: Tribe econ probes + visual moments + PARITY-M4

**Goal:** The QC gates, tribe flavor.

**Files:**
- Create: `tests/test_probe_tribe.gd` + `tools/probe_tribe.sh`; Modify: the scene visual harness (tribe moments), `docs/PARITY-M4.md`
- Test: the probes

**Acceptance Criteria:**
- [ ] Econ probes (headless, TS-verbatim, pinned seeds — the test_probe_creature shape): wood-quota income (under-80 quota → every even gatherer chops; delivery +8 each leg), bush regrow 30 s cycle (food 3..7), hut recruit 45 s + popCap gate + mid-siege block, raid cadence (80 + rng(−15,25), peaceful +40/half), war_graves payoff (+15 DNA per raid, combo-gated), totem progress rate (workers·1.6·dt), rival camp assault (+60/+40/−0.05 karma), beast DPS (9·fighters + 14 chief).
- [ ] Visual moments (xvfb, the T10 pattern): village founding (starting hut + tribesmen), raid (warriors + banner), campfire night, totem raising (progress label), beast attack, rival camp, chief death card, hut construction. Each ≥ 3 structural asserts.
- [ ] `docs/PARITY-M4.md`: per-feature rows (the M3 format) — every tribe feature with TS line + native pointer + test pointer; the §5.3-style criteria checklist (a)-(d); the M5 deferred list.

**Verify:** `tools/probe_tribe.sh` exit 0; visual suite exit 0. **Commit:** `test: tribe econ probes` then `test: tribe visual moments + parity list`.

### Task 8: M4 wrap — A-B, perf, review, tag

**Goal:** Close M4.

**Files:**
- Modify: `tools/ab_test.sh` usage only (no code), `docs/PARITY-M4.md`, `docs/ARCHITECTURE.md` (tribe section), README (status row)

**Acceptance Criteria:**
- [ ] A-B run: base `creature-parity-m3` → HEAD, cell+creature state dump IDENTICAL (the standing dump must not move — the tribe stage is additive); any diff line ruled.
- [ ] Perf: tribe sim tick @ 60 tribesmen + 6 rival warriors measured headless (the split metric — sim vs render vs frame, the T11 pattern); painter draw pass asserted ≤ 4 ms; tripwires standing; record honestly vs the M3 2 ms lesson (tribe targets its own budget row in PARITY-M4).
- [ ] ARCHITECTURE.md tribe section (module map, the hudRects update-dispatch pattern, the fall/victory go_to hooks, the debug cheat surface); README status row (M4).
- [ ] Full suite green: headless runner + all xvfb entries (bot, bot_creature, bot_tribe, editor_click, menu, visual ×2, creature_scene, tribe_scene, perf ×2, boot, visual_suite).
- [ ] Final whole-branch review (controller) → riders → tag `tribe-parity-m4` + PARITY-M4 completion note.

**Verify:** `./tools/test.sh` green; `git tag` shows `tribe-parity-m4`. **Commit:** `docs: M4 wrap (parity table, perf, architecture)`.

---

## Completion

- [ ] All 8 tasks complete, final whole-branch review TAG-READY, tag `tribe-parity-m4`, PARITY-M4 completion note, ledger closed.
- **Next milestone:** M5 = Civ (CivStage.ts 27.5K + civEvents 2.8K — the §5.4 gates at civ flavor), then M6 = Space, then M7 = CI/release + repo overwrite.
