# Native Creature Stage Full Parity — Implementation Plan (Milestone 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the creature stage to Godot 4 native with FULL parity to the frozen TS — side-view pseudo-depth island, procedurally animated creatures (analytic 2-bone IK, gait cycles, coats), charm minigame, pack/founding, land chaos — validated by the M2-proven gate stack (headless sims + real-input bots + pixel-asserts + TS-derived probes).

**Architecture:** Same two-layer pattern as M2: (1) `creature_sim.gd` RefCounted (hooks-Dictionary, input-snapshot contract, z-band pseudo-depth state) + `creature_events.gd` def deck; (2) scene layer — `creature_painter.gd` (pure (genome, pose, t) → draw calls, IK solver as a headless-testable static), land backdrop extensions, `creature_stage.gd` scene node. The cell stage's shore path (M2-pinned) hands off; `foundTribe` lands on a tribe PLACEHOLDER (pack-consumption asserts move to M4).

**Tech Stack:** Godot 4.2.2, GDScript typed, Compatibility renderer, xvfb llvmpipe for visual gates, zero plugins.

**Spec:** docs/specs/2026-09-29-native-migration-design.md — §5.3 (creature stage), §7 (creature renderer = heaviest port, prototype first).

## Global Constraints

**M1+M2 carry-forwards (hard, every task):**
1. Test files `extends "res://tests/test_base.gd"`; class construction via `load("res://...")`; `-s` runner picks tests/test_*.gd.
2. Floats: eps ≥ 1e-9 pure-float math; **eps ≥ 1e-6 Vector2-derived (float32 storage)**; creature IK math is PURE-FLOAT f64 from day one (M2 final-review carry: no Vector2.distance_to in new hot paths — TS vecDist is f64).
3. GDScript `%` int-only → fmod; Mulberry32 masking discipline; no randi/randf in sim (sanctioned exception stays GameContext._init); dict keys TS-verbatim camelCase.
4. `cd ~/Desktop/RD/primordia-native &&` prefix on every shell command.
5. Sim layer RefCounted, zero scene-API references; scene layer thin (calls sim, draws, forwards input); NO sim logic in _process.
6. i18n: every user-facing string through `tr_key("English sentence")` — the audit test scans src/game + src/ui (double-quoted dict-call shapes only; no commented-out hud literals).
7. Bot parity law: progression gates through REAL input (`Input.parse_input_event`); TS-bot-true direct calls documented (the TS creature bot sets `genome.legs=2` + calls `goTo` directly — bot-creature.test.ts:42-43 — the native bot mirrors this; the REAL shore path stays pinned by the M2 headless test).
8. Scene tests manually stepping a Game: post-tree processing disable + `loop.is_active_cb` kill-switch (T6 trap pattern).
9. A-B harness (`tools/ab_test.sh`) runs green after ANY sim hot-path change — it is the regression instrument; SANCTIONED_MATCH is the pass verdict.

**M3 additions (binding):**
10. IK solver + spine/gait math are PURE STATIC FUNCTIONS in `creature_painter.gd` (or a sibling `creature_rig.gd`) — headless-tested against TS-exact values BEFORE any drawing exists (the prototype-first doctrine: math green → pixels).
11. Body-silhouette pattern clipping: TS clips patterns/coats to the body Path2D — Godot equivalent is `RenderingServer.canvas_item_set_clip` on a SUB-canvas-item created for the clipped layer (draw silhouette shape first on that item, then patterns); document the chosen mechanism in the task report.
12. TS `Math.random()` sites port as Rng-stream draws with a divergence note (creatureEvents earthquake has TWO: creatureEvents.ts:47-48).
13. The `night_pack` def's TS warn-getter (`get warn()` closing over the last-polled chaos) ports as a chaos.gd extension: an optional `warn_fn: Callable` def key — when present, spawn() calls it (late: at spawn time, TS-equal) instead of reading the static `warn`; null/empty result = no warn phase. chaos.gd is M1-frozen — this extension needs its own review attention.
14. Draw order per TS render(): backdrop → lawn gradient → ground → edge hints → decor trees → hazards → bushes → bones → nests → z-sorted ents (player inserted at its z) → fx → night overlay + fireflies → vignette → HP bar → tutorial → charm UI → death overlay → tribe button.
15. Tribe stage does NOT exist in M3: `foundTribe()` fires the transition to a registered tribe PLACEHOLDER stage; the pack-consumption assert (tribe.tribe.length) is M4 scope.

**User decisions (already made):** Native ngay (Godot 4 + GDScript); repo riêng rồi ghi đè repo cũ; TS freeze làm reference; full delegation "hoàn thành repo đi".

---

### Task 1: Creature rig math — IK solver + spine + gait (headless, prototype-first)

**Goal:** The analytic rig math as pure static functions, TS-exact and headless-green BEFORE any pixels exist (spec §7 prototype-first doctrine).

**Files:**
- Create: `src/gfx/creature_rig.gd` (static funcs)
- Test: `tests/test_creature_rig.gd`

**Acceptance Criteria:**
- [ ] `solve_ik(hx, hy, fx, fy, l1, l2, bend) -> Vector2` (knee) — TS gfx/creature.ts:33-44 op-for-op: reach clamp `l1+l2-0.01`, min-reach `abs(l1-l2)+0.01`, law-of-cosines `a = (d²+l1²−l2²)/(2d)`, `h = sqrt(max(0, l1²−a²))`, knee offset `±h·bend` perpendicular.
- [ ] `spine_points(genome, pose, t) -> Array` (6 segments) — TS:94-108: profile `sin(π·min(1, u·0.85+0.12))`, radius `bodyR·(0.42+profile·0.62)`, bob `sin(gaitPhase·2)·1.6·size·speed`, swim `sin(t·2.2+u·2.4)·1.1·size·(0.3+speed)`, neck rise `u²·−2·size`, head lunge offset.
- [ ] `leg_draws(genome, pose) -> Array` — TS:153-171: legH `(20+min(legs,6)·1.5)·size` (5·size when legs=0), attach `spine[1+round(u·(SEG−3))]`, phase `(gaitPhase + (i%2)·π + floor(i/2)·1.1)`, stride `12·size·(0.25+speed)`, lift `7·size·speed`, footY = −max(0, sin(phase))·lift, bend `u<0.45 ? 1 : −1`, hip offsets.
- [ ] `tail_points(genome, pose, t)` — TS:137-150 (5 segs, ang drift, radii decay).
- [ ] Headless tests: pinned TS values for a fixed genome (size 1.2, legs 4) at fixed pose/t — solve_ik edge cases (straight, folded, over-reach), gait phase parity at phase 0/π/2π, spine profile at u=0/0.5/1. All approx eps 1e-9 (pure f64).

**Verify:** `godot --headless -s tests/run.gd` → test_creature_rig green.

**Steps:**
- [ ] Write failing tests (TS-exact values, hand-computed + cross-checked via a scratch vitest printing TS outputs for the same inputs — provenance comment).
- [ ] Port `creature_rig.gd`; pass. Commit `feat: creature rig math (IK/spine/gait, TS-exact)`.

### Task 2: Creature sim core — state, spawn, land ecology, player, world objects

**Goal:** The creature stage sim as `creature_sim.gd` (RefCounted, hooks-Dictionary, input-snapshot contract — the M2 CellSim pattern): everything except NPC AI (T3) and charm (T4).

**Files:**
- Create: `src/game/creature/creature_sim.gd`
- Test: `tests/test_creature_sim.gd`

**Acceptance Criteria:**
- [ ] Structs TS-verbatim: CreatureEnt (eid, speciesId, genome, x, z, vx, vz, y, vy, hp, maxHp, stats, facing, gait, speed01, attack, hurtT, eatT, biteCd, mood, wanderT, tx, tz, pack, packCd, baby, eggT, seed, corpseT, flying, lifespanStampede, band, pressCd), Bush (x, z, food, regrow, seed), Bone (x, z, taken, kind), Nest (x, z, speciesId, members), Hazard (x, z, r, dps, ttl, kind).
- [ ] Constants exact: Z_TO_Y 0.62, Z_MIN −200, Z_MAX 240, WORLD_HALF 2700, PRESS_COOLDOWN 20, chaos.gap 40 + gapChaosScale 0.35 (the widened cadence), bushes 46 (food 2..5), bones 8 (index 0 = meteor), spawnTimer 1.5s, eco tick 2s, despawn 2200 (pack exempt), pop target min(10, round(pop·0.5)) @ 0.35, day cycle 180s starting 0.15, night = dayPhase ∈ (0.55, 0.95), packLimit `2 + floor(arms/2) + floor(brain/2)`.
- [ ] `seed_land_ecology()` — 6 archetypes TS:194-201 field-exact, world dial (same formulas as cell), titan bonus (size 2.1 plates hue 300) + swarm bonus (0.6 eyes 2) AFTER roster, pop 5..10, **nests per species** (x ±0.9·WORLD_HALF, z Z_MIN+40..Z_MAX−40, members 4), discover 'creature'. `needs_land_fauna()` gate (no legged living).
- [ ] Player update — mouse pseudo-depth target (`tz = clamp(wy / Z_TO_Y, Z_MIN, Z_MAX)`, dead zones 10), WASD, jump (Space, `pvy = 320 + wings·60`, jumpCd 1.2, gravity 950), physics (accel, vz·0.8, drag exp(−6dt), cap speed), z-clamp + x-clamp ±(WORLD_HALF+200), gait `+= dt·(3+speed01·9)`, speed01, dust particles (speed01 > 0.5, chance dt·10).
- [ ] Interactions: bite (cd 0.6, `dmg·(1−min(0.6, defense))`, mood afraid, karma −0.008), their bite (cd 0.9, `·(1−def)·0.85`, charming tolerance, biteHintShown once), bush eating (hold-input, bite dt·2, regrow 25, heal 6·took, DNA 1.2·took, karma +dt·0.02), bones (radius 34, meteor 120/bone 45, list filter + 60 cap, chaos +0.05 on meteor), lava hazard dps, pack karma +dt·0.002.
- [ ] killEnt → CORPSE (corpseT 12, hp 0, pack happy) not removal; corpse meat eating (hold, heal 14dt, DNA 2.4dt, carnivore-only); corpse → bone 35% on expiry; notify_kill + bumpKill + kin grudge (warn-once, += 1) + corpse_tide dropCorpse.
- [ ] handleDeath (fade 1.8, DNA −12%, pack scatters with toast, respawn x −1600 z 20, threats >600 cleared, invuln 3) + onEnter reload-ambush calming (non-pack ents within 300 → mood idle, packCd 10) + barrenT dead-island escape (60s → reseed if needsLandFauna + nests members 4 + toast) + bush regrow loop + dayPhase advance + spawnTimerCheck.
- [ ] `on_stats_changed` (pStats/pmaxHp/packLimit refresh) + `persist_state` (pack genomes JSON → flags.packGenomes) + debug_state + debug_spawn_pack(n) (pack ents at +45px spacing).
- [ ] Hooks Dictionary (M2 pattern): hud_toast/hud_banner/hud_float_world/audio_play/cam_shake/fx_burst/fx_spawn/context_event/get_gap_bias/get_mood/get_warn_scale/storyteller_note_chaos_event + `get_is_night` (chaos ctx night field) + `get_dominance` (convergence input). Missing = silent no-op.
- [ ] Chaos scheduler constructed with gap 40/gapChaosScale 0.35 AFTER the eco branch (TS:157); deckSeed + ensure_deck C1.
- [ ] Divergences documented: `playerSeed`-equivalent ent `seed = rng.range(0,100)` per spawn (TS-true); facing `rng.chance(0.5)`.
- [ ] Headless determinism: same seed × 600 ticks scripted input → identical snapshot; assertSane port (dna/px/pz/php+0.001 finite).

**Verify:** `godot --headless -s tests/run.gd` → test_creature_sim green.

**Steps:**
- [ ] Write failing tests → port → green. Commit `feat: creature sim core (state/spawn/player/world objects)`.

### Task 3: Creature NPC AI — z-band state machine

**Goal:** `update_ents` ported 1:1: corpse lifecycle, baby growth, stampede lifetime, the panic/charmed/pack/hunt/flee/graze decision chain, bush/corpse grazing, hazard damage.

**Files:**
- Modify: `src/game/creature/creature_sim.gd`
- Test: `tests/test_creature_ai.gd`

**Acceptance Criteria:**
- [ ] Decision order exact (TS:841-1017): corpseT branch (meat-eat radius 30 carnivore-player, bone 35%, removal) → cooldown decays → baby growth (eggT, stats refresh) → stampede lifetime (pack exempt → undefined) → AI: panic (warnDriftT > 0 && !pack && !charmed — target 120px away, sp 40, mood alert) > charmed (hold still, sp 0, damp exp(−8dt)) > pack (follow 60px band, sp ×1.05 far / 0 near, happy) > wild (hunt/flee/graze).
- [ ] Wild reads: vision `360·stats.vision`, night flag, preySpecies, playerThreat (`pStats.damage > e.damage·0.8 || player.size > e.size`), sizeGap `max(0.35, 1−(e.size−player.size)·0.6)`, peaceful 0.65, aggr/fear bands, grudge (`eco.grudge_of`), grudgeHunt (`grudge ≥ 2 && d < vision·0.9·(php < 0.4·maxHp ? 1.4 : 1)`) — hunt gate `(prey && d < vision·sizeGap·peaceful·aggr && !threat) || grudgeHunt`, register_press + pressCd on grudgeHunt; flee gate `!charmed && grudge < 2 && d < vision·0.45·fear && threat && packCd ≤ 0 && lifespanStampede === undefined` (tx = e.x + (e.x−px)·2, sp ×1.05); graze (wanderT 2..5, bush seek radius 420 non-carnivore, else random ±300/±160, sp ×0.5, night → alert).
- [ ] Movement: accel apply (vz ·0.8), facing from dx, drag exp(−5.5dt), cap, integrate, z-clamp, speed01, gait.
- [ ] Eating: bushes (non-carnivore, radius 26, food −dt, regrow 25, heal 3dt), corpses (carnivore, radius 28, corpseT −2dt, heal 6dt), hazards (dps, hurtT 0.3), hp ≤ 0 → killEnt.
- [ ] Headless scenarios: hunter aggros a smaller player; big carnivore IGNORES a hatchling (sizeGap); grudgeHunt opens when player hurt (1.4×); pack follows at the 60px band; panic drift moves herds out; charmed target holds still; bush depletion regrows; baby grows at eggT; stampede ent despawns at lifetime (pack exempt).

**Verify:** `-s` runner → test_creature_ai green.

**Steps:**
- [ ] Failing scenario tests → port → green. Commit `feat: creature NPC AI (z-band state machine)`.

### Task 4: Charm minigame + pack + founding

**Goal:** The charm rhythm minigame, pack management, and the tribe-founding handoff to a placeholder.

**Files:**
- Modify: `src/game/creature/creature_sim.gd`
- Test: `tests/test_charm.gd`

**Acceptance Criteria:**
- [ ] `try_charm()`: nearest non-pack/non-corpse/non-baby/packCd≤0 ent within 120; pack-full toast (`Your pack is full (N) — evolve Arms/Brain for more`); size gate (`size > player·1.6 && brain < 2` → ignore toast); init (charmHits 0, **marker 0.75** (start OUTSIDE the zone — mash-to-win exploit), dir rng coin, mustExit false, mood alert, charmsSeen first-time hint).
- [ ] `update_charm(dt)`: escape conditions (target gone/corpse/>200px → 'It got away' variant), marker oscillation (speed `1.6 + hits·0.5`, bounce ±1), mustExit re-arm (|marker| ≥ 0.4), Space hit (zone `0.35 − hits·0.05`, mustExit guard — in-zone spam ignored, hit → star fx + hits++, 3 hits → befriend: lifespanStampede undefined, pack true, happy, karma +0.03, persist_state, burst), miss (active false, mood angry, packCd 6, 'It did not like your rhythm.').
- [ ] F-hold wiring in update (tryCharm when held, clear when released) + charmTarget hold-still AI interplay (T3's charmed branch).
- [ ] `found_tribe()`: tutorial finish (unless transitionTarget menu), pack snapshot (slice 6, genome+baby JSON → flags.packGenomes), playerSpeciesName → flags.playerSpeciesName, ctx.save, ascend hook, go_to('tribe', card 'THE FIRST FIRE') — the tribe stage is a PLACEHOLDER (Constraint 15).
- [ ] Pack persistence: onEnter restores from flags.packGenomes when livePack == 0 (corrupt flag tolerated → start alone); persist_state also fires on befriend (mid-creature autosave keeps the pack — A02).
- [ ] Headless tests: full charm sequence (3 beats with mustExit rhythm → pack +1), mash-in-zone does nothing, miss → angry + packCd, pack-full gate, size gate, restore-from-flag path, found_tribe snapshot + transition fires to placeholder.

**Verify:** `-s` runner → test_charm green.

**Steps:**
- [ ] Failing tests → port → green. Commit `feat: charm minigame + pack + founding`.

### Task 5: Creature chaos events + chaos.gd warn_fn extension

**Goal:** The creature def deck (8 baseline + 4 world-gated) + the chaos.gd `warn_fn` extension for night_pack's TS warn-getter.

**Files:**
- Create: `src/game/creature/creature_events.gd`
- Modify: `src/game/chaos.gd` (warn_fn), `src/game/creature/creature_sim.gd` (helper bodies)
- Test: `tests/test_creature_events.gd`

**Acceptance Criteria:**
- [ ] chaos.gd extension (Ruling 13): spawn() evaluates `def.get("warn_fn")` (Callable) when present — returns String or null; null → the no-warn immediate-apply branch; the static `warn` key still works unchanged; M1 chaos tests stay green (no behavior change without warn_fn).
- [ ] 8 baseline defs verbatim (weights/durations/cooldowns/warns): volcano (5 hazards after rng 1..12, r 64 dps 12 ttl 14 lava, quake + shake 8/1.2), earthquake (3 fire hazards after 1+i·0.8, r 46 dps 10 ttl 6, shake 9/3 — **the two TS `Math.random()` offsets (creatureEvents.ts:47-48) port as rng draws, divergence documented**), stampede (6 ents size > 1.2 genome, lifespanStampede 14, tx ±WORLD_HALF), nightraid (night-gated weight `(1.2+chaos)·(mood twist ? 1.3 : 1)` vs 0.05, 3 predators ±500/±160), mutationstorm (gene +1 free from the 9-gene pool with bounds table, pStats refresh), glorp (DNA 60, floatWorld), rain (bushes min(8, +2) regrow 0, flora +15), meteor (after 2.5 → dropMeteor: shake 12/0.8, ring, bone kind meteor, scorch 55·(1−d/150) + player 40).
- [ ] 4 gated defs: night_pack (raider_bold, weight `bold && night ? 1.1+chaos·0.8 : 0` recording packChaos, **warn_fn: packChaos > 0.5 → null else the warn**), titans_walk (old_blood via the seedsTitans ecoSeed-archetype scan — NOT the number, weight 0.35+chaos·0.3, mutate 0.05, lifespan 30), predator_convergence (ALWAYS in deck, weight `dominance > DOMINANCE_THRESHOLD ? 0.6·dominanceSeverity : 0` — ctx.dominance from the sim's `dominance_share()` (R 900, mine = player² + pack², wild only non-pack non-corpse), 3 hunters × 1 ent at 900px), rain mirror (wildcard bucket, weight 1.2-when-queued, rainMirror: bushes max(0, −2), flora +15).
- [ ] mirror maybeQueue seed: 'rain' (the creature mirrorable — TS:566).
- [ ] Helper bodies in sim: add_hazard/drop_meteor/stampede/night_raid/night_pack/titan_walk/mutation_storm_zap/glorp/rain/rain_mirror/converge_predators/gaia_wanderer (rareGene + discover) — TS:1119-1308 op-for-op.
- [ ] Headless tests: each def apply scripted (recording hooks), warn_fn semantics (low chaos → warn phase; high → immediate), the Math.random divergence pinned, dominance gate at the threshold, C1 rebuild, mirror-once flow.

**Verify:** `-s` runner → test_creature_events green (M1 chaos tests unchanged-green).

**Steps:**
- [ ] chaos.gd warn_fn extension + M1 regression check → commit `feat: chaos warn_fn (TS warn-getter parity)`.
- [ ] Def deck + helpers + tests → commit `feat: creature chaos events`.

### Task 6: Creature painter — prototype (pixel-asserted per part)

**Goal:** `creature_painter.gd` — the pure (genome, pose, t) → draw-calls port of gfx/creature.ts, the heaviest visual port; pixel-asserted part-by-part under xvfb.

**Files:**
- Create: `src/gfx/creature_painter.gd`
- Test: `tests/scenes/test_visual_creature.tscn` + `.gd`, extend `tools/visual_assert.py`

**Acceptance Criteria:**
- [ ] `draw_creature(canvas_item, genome, pose, opts)` port 1:1 — TS structure order: shadow → dead-rotate → spine (T1 rig) → wings (behind, flap `sin(t·(6+speed·8))·(0.5+speed·0.5)`, counter-flap −0.6) → tail (stroke baseDark w bodyR·0.7 then base w 0.4) → far-side legs (odd i) → back spikes (before body, min(spikes,7)) → body silhouette (SEG arcs + head ×1.02 + tail circles as ONE path) → clipped layer (belly ellipse + pattern spots/stripes/glow + coat scales/plates/fur + hurt flash) → near-side legs (even i) → arms (swing sin, hand dot) → jaw/snout by diet (carnivore quadratic snout + teeth min(4, 1+jaw); herbivore muzzle + mouth arc) → horns (quadratic curves) → eyes (blink `sin(t·1.3+hue) > 0.97`, look-at pupil via lookDx/lookDy, mood pupil size, angry brow).
- [ ] Clip mechanism (Ruling 11): the clipped layer on a SUB-canvas-item with `RenderingServer.canvas_item_set_clip` — silhouette shapes drawn first on that item, patterns after; report documents the mechanism.
- [ ] Palette exact: L 0.52, base/baseDark(L−0.16)/belly(sat·0.62, L+0.16)/limb(L−0.1)/outline(sat·1.1, 0.22) via the M2 hsl helper; seeded pattern rnd (`sin(n·127.1 + abs(round(hue·13.7))·...)·43758.5453` fract).
- [ ] Pixel-asserts (fixed genome size 1.2 legs 4 hue 120 fur spots, facing 1): body-disc center ≈ hue-120 at L 0.52 (±12/channel); belly band BELOW body center is lighter (L+0.16 direction); far-side leg pixel darker than near-side at mirrored foot positions; teeth pixels present for jaw 3 carnivore at the snout region (absent for herbivore); fur strokes present (coat fur) vs scale arcs (coat scales) at their clip regions; eye sclera + dark pupil + highlight at the head offset; tail stroke behind body (background pixels at tail x-range); mood angry adds the brow line (two captures differ); dead pose rotates (capture differs from alive).
- [ ] gait animation: two captures at gaitPhase 0 vs π/2 differ in foot positions (the phase math visibly moves feet).
- [ ] All captures structural tolerances, references recorded not diffed, llvmpipe-deterministic (two runs identical).

**Verify:** `-s` runner green (rig tests from T1 still green) + `tools/test_visual_creature.sh` (or the documented command) exit 0.

**Steps:**
- [ ] Read TS cell.ts-style port discipline; port painter → capture → PIL asserts → iterate. Commit `feat: creature painter (IK-animated, pixel-asserted)`.

### Task 7: Land backdrop + creature stage scene node

**Goal:** The world drawing (backdrop extension, z-sorted entity rendering, day/night overlay, fireflies, vignette) and the `creature_stage.gd` Node2D wiring the sim to the scene layer — first Camera2D-consuming stage (carry-forward: Camera2D rig ownership).

**Files:**
- Modify: `src/gfx/backdrop.gd` (land variant)
- Create: `src/game/creature/creature_stage.gd`
- Test: `tests/scenes/test_creature_scene.tscn` + `.gd`, `tests/test_backdrop_land.gd`

**Acceptance Criteria:**
- [ ] Backdrop land extension TS CreatureStage.render:590-660: lawn gradient `hsl(105 − chaos·30, 45%, 24 + 3·sin(t·0.21) + chaos·4%)` full-canvas; ground band below `gh = vh·0.55` `hsl(96 − chaos·20, 35%, 20 + 2·sin(t·0.19))`; decor trees every 170px (scroll parallax `t·6·speed01`, trunk rect + 2-3 canopy circles hsl(110..140, 30%, 18..30%)); distant hills band. Deterministic from seed + t (no per-frame rand).
- [ ] `creature_stage.gd` Node2D: builds `InputSnapshot` dict every frame from real Godot input ({mx, my, wx, wy, down, clicked, take_click, keys_held, keys_pressed} — keys_pressed canonical, M2 contract); calls `sim.update(dt, snap)`; draws via painter for every ent + player inserted into the z-sorted list **by z** (TS:1185-1190 `ents.concat(player)` then sort — player is NOT special-cased in draw order); night overlay `rgba(10, 8, 30, nightAlpha 0..0.45 by dayPhase)` + 20 deterministic fireflies (seed-branched positions, sin drift); vignette 0.42; HP bar, charm UI (bw 260, zone hsl(130..0 by hits), marker white), death card 'THE ISLAND RECLAIMS YOU', tribe button (brain ≥ 3 && pack ≥ 2 → click routes found_tribe).
- [ ] Camera (carry-forward #3 — RESOLVED in M2: `src/game/cam.gd` Cam already wraps Camera2D): creature stage reuses Cam — `cam.follow(px, pz·Z_TO_Y, dt)`, `cam.zoom = 1.15 − pz·0.0001` (clamp 0.9..1.15), shake via the existing cam_shake hook → `cam.shake(mag, dur)`; verify TS CreatureStage camera numbers against cam.gd's TS renderer.ts source before porting.
- [ ] Toast inset (carry-forward #4): creature stage is the first stage incrementing toast_inset — port the TS inset when HUD toasts overlap the creature HP bar.
- [ ] Render-order test (Ruling 14): pixel-assert — an ent at z 100 draws ABOVE the player at z 50 (they overlap); tail pixels behind body; far-side leg pixels behind body silhouette.
- [ ] xvfb scene test: stage boots at a fixed seed, sim steps, capture → structural asserts (lawn hue band present, night overlay dims when dayPhase forced to 0.7, fireflies present at night, vignette corners darker, HP bar at expected inset).

**Verify:** `tools/test_visual_creature.sh` (or documented equivalent) exit 0; `-s` runner still green.

**Steps:**
- [ ] Backdrop land + headless determinism test → commit `feat: land backdrop`.
- [ ] Stage node + z-sort + camera rig + xvfb tests → commit `feat: creature stage scene (z-sort, camera rig, day/night)`.

### Task 8: HUD/editor/tribe-button wiring + tutorial creature beats

**Goal:** The creature stage's UI surface: Tab editor extension (creature rows), charm/toast/banner routing through the M2 HUD, storyteller creature beats, context events.

**Files:**
- Modify: `src/ui/hud.gd`, `src/ui/editor.gd`, `src/ui/tutorial.gd`, `src/game/game.gd` (stage routing)
- Test: `tests/test_hud_creature.gd` + `tests/scenes/test_editor_click.gd` extension

**Acceptance Criteria:**
- [ ] Tab editor: creature mode shows the full genome with applied-mutation rows (the M2 cell editor's creature variant — verify TS editor.ts creature branch for exact rows: dna, genes 0..8, size slider, defects list); editor stays open across stage transitions (TS behavior).
- [ ] HUD routing: toasts (`Your pack is full...`, bush/bone/gorp cards), banners (arrival 'THE PACK WILL CALL YOU', death), float_world (glorp +60, bone pickups), charm hint (first charmsSeen) — all through the M2 hook contract; i18n double-quote dict shapes (carry-forward #5) for any new VI/EN keys; every hud literal in src/game/creature wrapped in tr_key.
- [ ] Storyteller creature beats: the TS storyteller's creature-stage beats (charm first-time, first pack member, first night survived) — verify against src/game/storyteller.ts creature section and port the exact triggers.
- [ ] Context events: eco tick (2s) feeds the storyteller eco signal; onEnter fires the C1 deck rebuild + arrival card through the same signal paths M2 wired.
- [ ] Escape routing: editor close → stage; death card ignores input until respawn.
- [ ] Headless tests: hud stub dict receives expected calls for scripted sim events; editor rows render the creature genome; xvfb editor-click test extension opens Tab in creature stage and toggles a gene.

**Verify:** `-s` runner green; editor xvfb suite exit 0.

**Steps:**
- [ ] Editor creature rows + tests → commit `feat: creature editor rows`.
- [ ] HUD/toast/banner/beat wiring + i18n keys + tests → commit `feat: creature HUD wiring`.

### Task 9: Creature bot + flow integration

**Goal:** The play-bot through the REAL input pipeline (bot parity law): shore arrival → 2-min chaos survival → charm → founding → transition to tribe placeholder. Plus the worldStage creature pins.

**Files:**
- Create: `tests/bots/bot_creature.gd`
- Modify: `src/game/game.gd` (toCreature routing from cell via REAL transition, not direct stage-swap), `src/game/menu.gd` (continue with creature save)
- Test: `tools/test_bot_creature.sh`, `tests/test_world_creature_pins.gd`

**Acceptance Criteria:**
- [ ] bot_creature.gd (TS bot-creature.test.ts shape): helper reaches creature via real flow (menu start → cell stage played to landfall — the REAL shore transition, not a direct goTo; documented TS-true cheats allowed ONLY where the TS bot also cheated: none needed here if shore flow works, else document), poll ≤ 600 frames for the arrival card, then 60·3 settle.
- [ ] Test 1 — 2-min chaos survival: LCG seed 777; move every 70 frames toward (px ± 300, pz·0.62 + vh/2 screen); Space jump at f%150==80; KeyF charm at f%400==300; Tab editor at f%900==500 then 560; sanity every 600; assertions: player alive or died-and-respawned, dna finite, no errors, dayPhase advanced, at least one chaos event fired in 2 min (gap 40 widened cadence).
- [ ] Test 2 — founding: cheat dna (debug), brain ≥ 3, debug_spawn_pack(2), tribeReady assert (brain ≥ 3 && pack ≥ 2), F-hold charm to befriend, found via the REAL tribe button click (not direct foundTribe — bot law), transition lands on tribe placeholder, pack snapshot flags.packGenomes.length ≥ 1. (tribe.tribe.length ≥ 2 assert = M4 scope, noted.)
- [ ] Determinism: the full bot run ×2 at seed 777 → identical final state snapshot (the M2 bot determinism pattern).
- [ ] game.gd routing: cell shore transition → creature stage (real input path: landfall click/condition → goTo('creature')); save/load round-trips a creature-stage save (persist_state → load → pack restored); continue-from-menu with a creature save boots into creature stage.
- [ ] worldStage creature pins (from worldStage.test.ts): the creature-stage bits (narration reset on continue, war_graves corpse interaction, bio_tell vacate band creature refs) — verify each against the TS test and port the ones that touch creature.
- [ ] Every bot input goes through `Input.parse_input_event` + flush (bot parity law); no direct sim method calls except the two documented debug_* cheats.

**Verify:** `tools/test_bot_creature.sh` exit 0 (×2 seeds determinism); `-s` runner green.

**Steps:**
- [ ] game.gd routing + save/continue + tests → commit `feat: creature flow (shore transition, save, continue)`.
- [ ] Bot script + determinism + worldStage pins → commit `feat: creature bot (2-min chaos, founding, determinism)`.

### Task 10: Land econ probes + visual suite creature moments

**Goal:** The QC gates at TS level: econ probes for the creature economy (bushes/bones/pack/DNA/day cycle) and the visual suite creature moments.

**Files:**
- Create: `tests/test_probe_creature.gd`, `tools/probe_creature.sh`
- Modify: visual suite (`tests/scenes/` creature moments), `docs/PARITY-M3.md`

**Acceptance Criteria:**
- [ ] Econ probes (headless, TS-verbatim formulas, seeds pinned): bush-eat rate (hold-input 60s → DNA gained ≈ 1.2·took, heal 6·took, bush regrow cycle 25s), bone rate (8 bones → first-meteor 120 then 45 each, cap 60), charm→pack rate (packLimit formula), day cycle (180s full loop, night window (0.55, 0.95)), spawn pressure (pop target min(10, round(pop·0.5)) @ 0.35), corpse economy (12s corpseT, 35% bone), stampede cadence under chaos.
- [ ] Visual moments (xvfb + pixel-assert, the M2 visual-suite shape): shore arrival card, day meadow (full creature rendered mid-gait), night raid (overlay + fireflies), charm minigame UI mid-hits, death card, volcano aftermath (lava hazards + scorch), stampede herd, editor open in creature. Each moment ≥ 3 structural asserts, references recorded.
- [ ] PARITY-M3.md: feature list per the spec §5.3 criteria (like PARITY-M2.md) — every creature feature row with its test pointer.
- [ ] Probes run green under the pinned seeds; visual suite exit 0.

**Verify:** `tools/probe_creature.sh` exit 0; visual suite exit 0.

**Steps:**
- [ ] Econ probes + script → commit `test: creature econ probes`.
- [ ] Visual moments + PARITY-M3.md → commit `test: creature visual moments + parity list`.

### Task 11: M3 wrap — A-B harness hardening, perf, final review, tag

**Goal:** Close M3: the ab_test.sh carry-forward fix lands, perf measured, whole-branch review, tag `creature-parity-m3`.

**Files:**
- Modify: `tools/ab_test.sh` (the 2-line fail-open fix), `docs/PARITY-M3.md`, `docs/ARCHITECTURE.md` (creature module section), memory files via the coordinator
- Test: full suite

**Acceptance Criteria:**
- [ ] ab_test.sh hardening (carry-forward #1): the evidence write happens AFTER the FAIL verdict, not before — a failing run can no longer clobber the sanctioned sha (the 2-line fix from the M2 final review; write a failure-path test that proves the second failing run does not launder into SANCTIONED_MATCH).
- [ ] A-B run: creature-stage sim hot path (update_ents + painter-free sim tick) base `cell-parity-m2` → HEAD, 4 scenarios × full state dump → IDENTICAL or every diff line ruled (the chaos Math.random→rng divergence is a RULED line).
- [ ] Perf: sim tick at 60 ents (creature target) measured headless (contention-immune cross-check per the M2 lesson) — budget: creature sim tick ≤ 2 ms on the dev machine; painter draw at 60 ents + player ≤ 4 ms frame budget on llvmpipe (document the rig caveat — real GPUs are faster).
- [ ] Spec §5.3 criteria checklist written into PARITY-M3.md: (a) feature list, (b) bot arc creature-leg ×seeds ×determinism, (c) econ probes TS-verbatim, (d) pixel-assert suite creature moments. Each with its evidence pointer.
- [ ] Full suite green: `-s` runner + all xvfb suites (`test_bot_creature.sh`, `test_bot.sh` (M2 still green), visual, editor).
- [ ] README wording tightened (carry-forward #6 from M2 final review: describe the game, not the port).
- [ ] ARCHITECTURE.md creature section (module map, hooks contract, camera rig ownership).
- [ ] Final whole-branch review (SDD final reviewer) → address findings → tag `creature-parity-m3` + spec §5.3 completion note.
- [ ] M4 deferred list recorded in spec §5.3 (whatever the final review parks).

**Verify:** `./tools/test.sh` full green; `git tag` shows `creature-parity-m3`.

**Steps:**
- [ ] ab_test.sh fix + failure-path test → commit `fix: ab_test fail-open hardening (M2 carry-forward)`.
- [ ] A-B run + perf + docs → commit `docs: M3 wrap (parity table, perf, architecture)`.
- [ ] Final review → fixes → tag.


