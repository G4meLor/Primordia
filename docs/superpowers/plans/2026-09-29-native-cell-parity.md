# Native Cell Stage Full Parity — Implementation Plan (Milestone 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the cell stage to Godot 4 native with FULL parity to the frozen TS version — measurable by the 4 criteria in the migration spec §5.2 (feature list, bot arc ×3 seeds through real UI, econ probes + determinism, pixel-assert).

**Architecture:** Two new layers on top of the M1 sim core: (1) a headless-testable cell sim port (spawn tables, NPC AI, eat/attack resolution, pellet field, DNA awards — RefCounted, same discipline as M1), and (2) the scene layer (Game orchestrator node, cell stage scene, Camera2D, procedural renderer via `_draw`, HUD/editor/pause Controls, synthetic-input bots, xvfb viewport-capture pixel asserts). Sim logic NEVER touches scene APIs; scenes never re-implement sim.

**Tech Stack:** Godot 4.2.2, GDScript typed, Compatibility renderer (GL 3.3 — llvmpipe under xvfb for CI/test), zero plugins.

**Spec:** docs/specs/2026-09-29-native-migration-design.md — §4 (layer architecture), §5.2 (cell parity definition — the binding acceptance contract).

## Global Constraints

**M1 carry-forwards (hard, every task):**
1. Test files use path-based `extends "res://tests/test_base.gd"`; class self-construction via `load("res://...")` — class_name self-reference fails in `-s` mode.
2. Float comparisons against TS-derived fixtures: NEVER eps 0.0 — `approx(..., eps >= 1e-9)`; RNG pins strongest as uint32-exact `roundi(v * 4294967296.0)`.
3. GDScript `%` is int-only → `fmod`; Mulberry32 port masks `& 0xFFFFFFFF` on every bitwise op, `_imul(a,b) = (a*b) & 0xFFFFFFFF`.
4. No `randi()/randf()/randomize()` in sim code (the one sanctioned exception stays `GameContext._init` seed-picker). Every randomness through `Rng` streams.
5. Dictionary keys TS-verbatim camelCase on save-wire surfaces (documented exception: eco species rows snake_case).
6. Always `cd ~/Desktop/RD/primordia-native &&` before shell commands (cwd resets).
7. Sim layer = RefCounted, zero scene-API references. Scene layer = thin: calls sim, draws, forwards input. No sim logic inside `_process`.

**M2 additions (binding):**
8. Bot parity law (bài học legs từ TS repo): every progression gate the bot passes must go through the REAL input pipeline (`Input.parse_input_event` with InputEventKey/MouseButton/Action) — never by calling sim methods directly. UI reading is allowed via debug getters only.
9. Visual asserts run under `xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3` and compare `get_viewport().get_texture().get_image()` pixels (PROVEN: spike 2026-09-29, center px exact (51,204,102), llvmpipe GL 4.5). Image reading in tests uses Python PIL via a helper script (match TS repo's visual-assert doctrine: trust pixel numbers, never image previews).
10. Determinism: bot arcs run with fixed seeds; same seed → same run path. Pixel-assert scenes also seed-pinned.
11. Cell sim constants 1:1 from TS `src/game/cell/CellStage.ts` + `cellEvents.ts` — no silent improvements. Where TS uses `Math.random` in cell stage (if any), port as Rng stream call and record the divergence in the task report.
12. i18n: `tr("English key")` (TranslationServer, falls back to key) replacing TS `t()`; keys stay the exact English sentences from TS `src/core/i18n.ts`.

**Provenance spikes (2026-09-29, both PASSED):**
- Viewport capture under xvfb: `get_viewport().get_texture().get_image().save_png()` works, pixels exact (circle color verified per-channel).
- Synthetic input: `InputEventKey` / `InputEventMouseButton` / `InputEventAction` via `Input.parse_input_event()` all reach `_unhandled_input`.

**User decisions (already made):** Native ngay (Godot 4 + GDScript); repo riêng rồi ghi đè repo cũ; TS freeze làm reference; Cell stage full parity trước; full delegation "hoàn thành repo đi" (goal 2026-09-29).

---

### Task 1: Core plumbing — math, input wrapper, loop, camera, game orchestrator skeleton

**Goal:** The scene-layer foundation every later task stands on: math helpers, the input wrapper (real-pipeline fed), the fixed-step loop, the camera rig, and the Game orchestrator with stage transitions — bootable to the menu under xvfb.

**Files:**
- Create: `src/core/math.gd`, `src/core/input.gd`, `src/core/loop.gd`, `src/game/cam.gd`, `src/game/game.gd`, `src/game/stage.gd` (Stage base), `main.tscn` + `src/main.gd` (boot scene)
- Test: `tests/test_math.gd`, `tests/test_input.gd`, `tests/test_loop.gd`, `tests/test_cam.gd` (all `-s` runner), plus `tests/scenes/test_boot.gd` (scene test under xvfb)

**Acceptance Criteria:**
- [ ] `math.gd`: port of TS `src/core/math.ts` — `damp(rate,dt) = 1-exp(-rate*dt)`, `smoothstep`, `ease_out_cubic/in_cubic/out_back` (c=1.70158 exact), `wrap_angle` via fmod (JS-semantics: fmod keeps sign, then the ±TAU shifts), `format_num` (1e9→B, 1e6→M, 1e4→k, else round), `TAU`. Vec helpers thin over Vector2 where equivalent (`vec_dist` = `Vector2.distance_to`), but `format_num`/easing formula-exact.
- [ ] `input.gd` (RefCounted): TS-code-string API (`key("KeyE")`, `key_pressed("Space")`, `is_down()`, `was_clicked()`, `take_click()`, `wheel()`, `mx/my/wx/wy`, `set_world(x,y)`, `vw/vh`) fed by reading the Godot `Input` singleton + a `_unhandled_input`-forwarded event path the Game node wires; physical_keycode ↔ TS code-string map covers every key the game uses (WASD, Arrows, Space, KeyE, KeyShift, Digit1, Digit2, ESC, mouse buttons, wheel). `end_frame()` clears one-shots, called once per frame by the loop. No debug* setters — bots drive `Input.parse_input_event` (Global Constraint 8).
- [ ] `loop.gd`: TS accumulator port — 60Hz fixed step, frameDt clamp 0.25s, max 8 steps/frame, `render(alpha)` after stepping, `tick_manual(n, dt)` for tests/bots. Godot node wraps it in `_process(delta)`.
- [ ] `cam.gd`: Camera2D-based rig — `follow(x, y, dt, rate)` (damp-based), `zoom` (default 1), `shake(mag, dur)` with per-frame decay, `to_world(mx, my, vw, vh) -> Vector2` screen→world inverse of the Camera2D transform, view bounds (`view_l/r/t/b`) for render culling.
- [ ] `game.gd` (Node): owns `context` (M1 GameContext), `input`, `cam`, `loop`, stage registry (`register(stage)`, keyed by `stage.id`), `go_to(stage_id, transition = {})` with the TS transition shape (fade-out → title card ~2.2s → fade-in; card fields title/sub), `step_for_testing(n, dt)` driving `loop.tick_manual`, stage lifecycle `on_enter(from)/on_exit()` called in TS order (exit old, transition, enter new), `storyteller` (M1), `hud`/`editor`/`fx` stubs (dictionaries of no-op Callables, replaced by later tasks), `save_all()` (context.save), `vw/vh` from viewport.
- [ ] Boot: `main.tscn` → Game node + Menu placeholder stage registered; running under xvfb shows the menu and quits via an env var after N frames (test-only).
- [ ] `tests/scenes/test_boot.gd`: scene test run under xvfb — boots, asserts stage == "menu", injects `InputEventKey` (Enter) → placeholder menu starts a new game → after transition frames `context.stage == "cell"` placeholder, quits 0. Failures print to stderr and exit 1.

**Verify:** `cd ~/Desktop/RD/primordia-native && ~/.local/bin/godot --headless -s tests/run.gd` → test_math/input/loop/cam green; `xvfb-run -a ~/.local/bin/godot --path . res://tests/scenes/test_boot.tscn` → exit 0.

**Steps:**
- [ ] Write `test_math.gd` (each helper: TS-exact values — `ease_out_back(0.5)`, `wrap_angle(3π/2)`, `format_num(12345)`), run → FAIL.
- [ ] Port `math.gd`; pass. Commit `feat: math toolbox port`.
- [ ] Write `test_input.gd` + `test_loop.gd` + `test_cam.gd` (loop accumulator: frameDt clamp + 8-step cap + tick_manual; cam: follow converges, shake decays to 0, to_world round-trips a point through a known camera transform) → FAIL.
- [ ] Port `input.gd` + `loop.gd` + `cam.gd`; pass. Commit `feat: input wrapper + fixed-step loop + camera rig`.
- [ ] Write `tests/scenes/test_boot.gd` + placeholder stage/main scene → run under xvfb → FAIL (no game.gd).
- [ ] Port `game.gd` + `stage.gd` + `main.tscn`; xvfb boot test passes. Commit `feat: game orchestrator skeleton + boot scene`.

### Task 2: i18n — VI/EN CSV + TranslationServer + settings + structural audit

**Goal:** The 454+ key Vietnamese dictionary lands as CSV, `tr()` replaces `t()`, language/mute settings persist, and the I-q1 structural audit (no unwrapped HUD literals; every key has a VI entry) ports as a real test.

**Files:**
- Create: `assets/i18n/vi.csv` (generated), `src/core/i18n.gd`, `tools/gen_i18n_csv.js` (runs in the TS repo, extracts the VI object → CSV)
- Test: `tests/test_i18n.gd`

**Acceptance Criteria:**
- [ ] `vi.csv` generated from TS `src/core/i18n.ts` VI object verbatim (script committed for re-generation; CSV-escaping checked — keys contain commas/emoji).
- [ ] `i18n.gd`: loads CSV into TranslationServer at startup (autoload or Game._init), `set_lang/get_lang`, `set_muted/get_muted`, `tr_key(s)` wrapper = `tr(s)` passthrough semantics (EN falls back to key itself), `vi_key_count() >= 454`, `vi_has(key)`.
- [ ] Settings persistence: TS `loadSettings/saveSettings` (localStorage) → `user://settings.cfg` via ConfigFile (`lang`, `muted`); `detect_lang()` = `OS.get_locale_language() == "vi"` (mirrors TS navigator auto-detect).
- [ ] Audit tests (I-q1 port): (a) the 24 flagged variant/warn/toast keys + the 3 nebula template keys translate in VI; (b) a GDScript test reads every `.gd` under `src/game/` + `src/ui/` with FileAccess and asserts no `hud.toast("literal")` / `float_world("literal")` / `banner("literal")` unwrapped call and every `tr_key(` literal exists in the VI table (regex ports of the TS audit).
- [ ] `key_pressed` keys stay English sentences (M1 convention) — no VI in code strings.

**Verify:** `godot --headless -s tests/run.gd` → test_i18n green (including count ≥ 454 and audit sweep).

**Steps:**
- [ ] Write + run `tools/gen_i18n_csv.js` in the TS repo (`node --experimental-vm-modules` not needed — plain node script importing the VI object via a tiny ESM shim or JSON dump); copy `vi.csv` into native repo. Commit `chore: vi translation table csv`.
- [ ] Write `test_i18n.gd` (EN passthrough, VI known keys — `SAVE SLOT` → `Ô LƯU`, unknown fallback, settings round-trip via ConfigFile in a temp dir, count ≥ 454, audit scan) → FAIL.
- [ ] Port `i18n.gd` + wire into Game boot; pass. Commit `feat: i18n translationserver + settings + audit`.

### Task 3: Cell sim core — state, spawn, player physics, pellets, zones

**Goal:** The cell stage's sim state and update math as a headless RefCounted (`CellSim`), driven through a hooks-Dictionary for scene effects (M1 chaos-hooks pattern): everything except NPC AI and chaos event bodies (Tasks 4-5).

**Files:**
- Create: `src/game/cell/cell_sim.gd`
- Test: `tests/test_cell_sim.gd`

**Acceptance Criteria:**
- [ ] Data structs as Dictionaries with TS-verbatim keys: CellEnt (eid, speciesId, genome, x, y, vx, vy, hp, maxHp, stats, stun, lastPlayerHit, hurtT, eatT, biteCd, seed, wanderT, tx, ty, big, swarm, lifespan, band, pressCd), Pellet (x, y, vx, vy, kind, ttl, val), Zone (x, y, r, kind, ttl, dps, heal, pulse, mine, source), Kelp.
- [ ] Constants exact: `WORLD_R = 2400`, `PRESS_COOLDOWN = 20`, kelp 40 × (r 300..WORLD_R*0.95, len 40..110, seed 0..10), starter pellets 30, pellet cap 260 (shift eviction), pellet ttl meat 25 / else 40, pellet val meat 5 / else 2, pellet spawn r 0..900 + vel ±8, despawn dist 1600, pop target `min(9, round(pop*0.6))` at 0.4 chance per eco.living (kin skipped), spawn timer 1.2s, eco tick batch 2s, discovery radius 420, eat radius `14*size + 5`, bite cd 0.55, enemy bite cd 0.8, dash cd 3 + pow `260 + jet*90` + dashT 0.35, toxin cd 6 + zone r `60 + toxin*22` ttl 6 dps `4 + toxin*4`, electro cd 10 + r `160 + electro*70` stun `1.8 + electro*0.7`, drag exp(-2.6dt) / exp(-1.2dt) while dashT, current `sin(y*0.004 + time*0.05)*14`, max speed `speed * (dashT>0 ? 2.6 : 1)`, soft boundary push 2.5×dt×10 beyond WORLD_R + hard clamp at WORLD_R+200, vent heal zone, invuln 3 on spawn / 4 on respawn, death: DNA loss round(12%), respawn at r=600 + threat clear 700, respawn fade 1.6s, nutrition decay 0.01/s +0.03 per plant.
- [ ] `seed_ecology()` port 1:1 — the 7 archetype genomes (exact field values), world-weighted diet flips (`herb_pull/carn_pull` formulas with `min(0.9, ...)`), `titan >= 1` bonus species (size 2.2, hue 330) and `swarm >= 1` bonus (size 0.55, flagella 5, cilia 3, glow) appended AFTER the roster, names via `species_name + epithet`, `add_species(pop 4..9)`, every species `context.discover(...)`.
- [ ] Player update port: mouse-hold-or-WASD desired dir (dead zone 12), dash/toxin/electro triggers keyed off an input-snapshot Dictionary (fields: `mx, my, wx, wy, down, key_pressed_keys: Array, keys_held: Array`) — sim never touches the Input singleton; contact-damage/proboscis-drain/auto-bite/enemy-bite resolution with the exact TS guards (alive-only, `defense` reductions, proboscis `size > player*0.9 && stun <= 0`, drain `proboscis*3*dt` hp + `*0.4` DNA); pellet pickup rules (plant: flora −0.4 karma +0.0005; meat: heal 5 karma −0.0005 tut.killed++, no posthumous farming); DNA pellet val payout.
- [ ] `kill_ent(e)` pay rules: meat pellets `1 + floor(size)` spread ±10, swarm DNA 8 + karma −0.004, else `eco.notify_kill` + `context.bump_kill` + karma (herbivore −0.002 / else −0.0005) + kin_memory grudge ledger (`grudge == 0` first-warning toast hook, `grudge += 1`), corpse_tide combo `drop_corpse(2 + chance(0.5))`, 6% mutant snack (lifespan 25), hp = −1 removal marker.
- [ ] Hooks Dictionary (all Callables, sim calls only through these): `hud_toast(text, kind, icon)`, `hud_banner(data)`, `hud_float_world(x, y, text, color, size)`, `audio_play(name, vol, pan := 0.0)`, `cam_shake(mag, dur)`, `fx_burst(x, y, n, opts)`, `fx_spawn(opts)`, `storyteller_note_chaos_event(playtime)`, `set_cursor_pointer()`, `context_event(ev_name, data)` (for playerDeath etc.). Headless tests inject recording Callables; assertions read the recording.
- [ ] Divergence note: TS `playerSeed = Math.random()*10` → drawn from the stage rng in `_init` (visual-only seed; recorded in the report).
- [ ] Headless determinism test: same seed → identical ents/pellets/kelp snapshot after 600 ticks; eco fixture walk (M1) stays green.

**Verify:** `godot --headless -s tests/run.gd` → test_cell_sim green.

**Steps:**
- [ ] Write failing tests (sanity invariants port of `assertSane`; pellet economy; kill pay; boundary push; death/respawn cycle; determinism 2×600-tick).
- [ ] Port `cell_sim.gd`; pass; full suite green. Commit `feat: cell sim core (state/spawn/player/pellets/zones)`.

### Task 4: NPC AI — hunt/flee/graze/panic state machine

**Goal:** `update_ents` ported 1:1: the AI decision order, movement physics, pellet-eating, toxin exposure — the behavioral heart of the stage.

**Files:**
- Modify: `src/game/cell/cell_sim.gd`
- Test: `tests/test_cell_ai.gd`

**Acceptance Criteria:**
- [ ] Decision order exact: sweep hp<=0 (lastPlayerHit pay-through-killEnt, else green burst) → lifespan expiry → per-ent cooldown decays → stun branch (drag exp(−3dt)) → AI: panic > hunt > flee > graze.
- [ ] Vision `340 * stats.vision`; `i_am_bigger` = `size > player*1.05 || (damage > player && size > 1.2)`; temperament bands `aggr/fear` (band Dictionary from M1 behaviorBand); kin grudge via `eco.grudge_of(world, speciesId)`; `grudge_press = grudge >= 2 && d < vision*0.9`; tideBold = `eco.tide_species().id`; hunt = swarm || (non-herbivore && d < vision*0.65*aggr && bigger) || grudgePress || tideBold(d < vision*0.5); flee = !swarm && grudge < 2 && d < vision*0.7*fear && !bigger; panic = warnDriftT > 0 && !swarm && d < 500.
- [ ] Panic: positional drift 48px/s directly away, speed capped 45, no accel; hunt: chase player or nearest smaller ent (squared-distance single pass, size < own*0.85), swarm speed ×1.25, grudge presses register via `eco.register_press` with pressCd; flee: speed `min(speed*0.95, (player_accel/2.6)*0.85)`; graze: wanderT re-roll 1.5..4s, pellet seek radius 300 (plant unless carnivore→meat), else random point 60..320, speed ×0.55.
- [ ] Separation loop (0.6 push within `14*(s1+s2)`), accel apply, current, drag exp(−2.4dt), speed cap, world containment push beyond WORLD_R+100, pellet eat (radius `14*size+5`, diet filter, heal 4, eatT 1), toxin zone dps + hurtT 0.2 + `mine` → lastPlayerHit 'toxin'.
- [ ] Headless scenario tests (scripted sim state, seeded rng): hunter closes on player; fleeing prey respects the achievable-speed cap; panic vacates ≥40% of scripted ents from a 320-radius zone in a 2.4s window; grazer seeks pellets; grudgePress registers a press and keeps chasing; swarm never flees.

**Verify:** `godot --headless -s tests/run.gd` → test_cell_ai green.

**Steps:**
- [ ] Write failing scenario tests (each bullet = one test).
- [ ] Port `update_ents`; pass; full suite green. Commit `feat: cell NPC AI state machine`.

### Task 5: Cell chaos events + storyteller/world wiring

**Goal:** `cellEvents.ts` defs ported as Dictionary-of-Callables defs (M1 ChaosScheduler shape), the chaos update loop wired into the sim with full ctx (gapMult = chaosGapMult × storyteller gapBias, mood, warnScale, mirrors), event helper methods, and the world-reveal pump.

**Files:**
- Create: `src/game/cell/cell_events.gd`
- Modify: `src/game/cell/cell_sim.gd`
- Test: `tests/test_cell_events.gd`

**Acceptance Criteria:**
- [ ] 8 baseline defs verbatim (ids, names, warn strings, weight formulas, durations, cooldowns, apply bodies): meteor (after 2.5 → impact: damage 60 falloff 200, player 45 falloff, 6 DNA pellets val 12, chaos +0.04), bloom (flora ×1.9+20 cap, 30 pellets r 100..700), redtide (3 zones r 90..150 dps 7 ttl 18..26), swarm (4 ents at (i/7)*TAU r 620, mutate 0.1, lifespan 30), bigbro (size max(2.0, player*1.6), jaw 5, lifespan 26, camShake 6/1), vents (2 zones r 80 ttl 240 heal 6, cap 6 FIFO), glitch (gap 10 during, BASE_GAP restore, end: DNA +40 tribute toast), mutationwave (2-3 mutants at 400..700, mutate 0.85, chaos +0.02).
- [ ] 3 world-parameterized defs with TS gating: toxin_clouds (weight 5 when chaos > 0.35, zones r 120..170 dps 3 ttl 26 source 'clouds', tick drifts 14px/s homing player, only its own clouds), algae_surge (flora surge + grazers pop min(90, ×1.8+3) + 20 pellets), bloom-mirror (mirrorOf 'bloom', weight 1.2 only when queued mirrors include bloom, apply = blight: flora max(12, ×0.35) + same 30-pellet sprinkle).
- [ ] Chaos update wiring per-tick: ctx = {chaos, karma, stageTime, gapMult: `chaosGapMult * storyteller.gap_bias()`, mood, warnScale: `storyteller.warn_scale()`, mirrors: `mirror_ledger.queued()`}; hooks: onWarn → banner(danger, ttl 2.4) + alarm; onApply → banner(name) + chaos +0.03 + mirrorLedger.on_fired + storyteller.note_chaos_event; onEnd → glitch tribute + maybeQueue(rng, id, 'bloom').
- [ ] C1 deck rebuild: deck-seed mismatch at enter rebuilds scheduler (rng.branch()) — test the rebuild path.
- [ ] `warn_drift_t = chaos.warn_remaining` consumed by AI panic (Task 4 reads it).
- [ ] Extinction/shift/speciation handling in the 2s eco batch: bumpExtinction + markExtinct + chaos +0.05 + banner; bio_shift toast (`The web re-equilibrates:` + diet names); speciation discover + toast; flora ≥ 12 → plant pellet top-up to 60.
- [ ] World reveal pump: stage pushes its per-tick signals (stageTime, kills via context.worldStats, extinctions, chaos level) into `tick_world_reveals` with `timers` increment + replacement-stage deck handling per M1 contract — headless test: a seeded walk where a reveal fires and the reveal card hook receives it.

**Verify:** `godot --headless -s tests/run.gd` → test_cell_events green.

**Steps:**
- [ ] Write failing tests (each def apply/end body scripted with recording hooks; glitch gap restore; mirror queue flow; C1 rebuild; reveal pump walk).
- [ ] Port `cell_events.gd` + wire `update_chaos` into sim; pass; full suite green. Commit `feat: cell chaos events + world wiring`.

### Task 6: Play-bot — the 2-minute messy arc through the REAL input pipeline

**Goal:** The TS bot.test.ts arc ported as scene tests: boot → menu → new game → transition → 120s of messy human-like play (move/dash/burst/editor) with the assertSane invariant sweep — driven exclusively via `Input.parse_input_event` (Global Constraint 8), on ≥3 seeds.

**Files:**
- Create: `tests/bots/bot_driver.gd` (RefCounted: step loop + input helpers + assert_sane), `tests/scenes/test_bot_arc.tscn` + `.gd`
- Test: the scene test itself (runs under xvfb; also runs headless for speed when rendering not asserted)

**Acceptance Criteria:**
- [ ] `assert_sane(game)` port: dna finite ≥ 0; chaos ∈ [0,1]; karma ∈ [−1,1]; in cell stage: player pos finite, hp ≤ maxHp + 0.001, ents < 300.
- [ ] Arc (per seed, seeds = [0xc0ffee, 0x51071, 0xabcdef]): boot → 10 steps → `menu.start_new_game()` direct call (TS-bot parity — the menu UI flow is Task 7's scene test) → poll until `context.stage == "cell"` (≤ 300 steps) → 180 steps through the card phase → 120s messy loop at DT = 1/60: every 90 frames pick a new random target (LCG seed 12345 port: `(seed*1103515245 + 12345) & 0x7fffffff`), drive a mouse button-press at the mapped screen position via `InputEventMouseButton` + `InputEventMouseMotion` (position = target − player + center), release 45 frames later; every 240 frames `InputEventKey` physical `KEY_SPACE` press+release; every 300/360 frames `KEY_1`/`KEY_2`; open+close editor via real `KEY_E` at f=1200/f=1230; every 600 frames `assert_sane`.
- [ ] Post-arc: ents > 0, assert_sane passes; NO NaN, no crash, deterministic across the 3 seeds (the arc's world state hash — ents count + player pos rounded — recorded per seed and asserted stable across two runs of the same seed).
- [ ] Editor buy/sell test (TS bot test 3 port): `editor.show("cell")` → `editor.click_part(part_row, "+")` → flagella +1 and DNA decreased → `click_part(..., "-")` → back → real `KEY_E` press closes the editor within 2 frames.
- [ ] Save→load round-trip (TS bot test 4 port): play, set dna 777 + spikes 3, `context.save()` true; fresh Game, `context.load(0)` true, values live.

**Verify:** `xvfb-run -a ~/.local/bin/godot --path . res://tests/scenes/test_bot_arc.tscn` → exit 0, all 4 arc tests green (bot prints per-seed PASS lines).

**Steps:**
- [ ] Port `bot_driver.gd` (LCG, input helpers, assert_sane).
- [ ] Write the 4 arc tests → run → fix against failures (each failure = a real port bug; do not weaken asserts).
- [ ] All 3 seeds green ×2 determinism runs. Commit `feat: play-bot cell arc (real input pipeline)`.

### Task 11: M2 wrap — parity checklist, perf probe, tag

**Goal:** Close the milestone: the §5.2 parity table filled with evidence links, a perf probe at the 200-ent budget, suite green, tagged.

**Files:**
- Create: `docs/PARITY-M2.md`, `tests/scenes/test_perf.tscn` + `.gd`
- Modify: `README.md` (status), `docs/specs/2026-09-29-native-migration-design.md` (§5.2 marked complete)

**Acceptance Criteria:**
- [ ] `PARITY-M2.md`: table mapping EVERY cell-stage feature from the TS contract (features.test.ts + bot.test.ts list, extracted during Tasks 1-10) → the native test that pins it → status. Any gap = the milestone is not done; gaps get fixed before this task closes, or get an explicit spec-sanctioned deferral note.
- [ ] Perf probe: a scene test spawning 200 ents (mix of sizes) near the player, stepping 600 ticks, asserting wall-clock ≤ 8ms/tick average on this machine (llvmpipe rendering ON — worst case) and no NaN drift. Result recorded in PARITY-M2.md.
- [ ] Full suite green (both runners: `-s tests/run.gd` + xvfb scene tests). Tag `cell-parity-m2` on HEAD.

**Verify:** `./tools/test.sh` + xvfb scene runner both exit 0; tag resolves to HEAD.

**Steps:**
- [ ] Build the feature→test table (grep both repos).
- [ ] Perf probe test → run → record.
- [ ] Docs + tag. Commit `docs: m2 parity checklist + perf probe` + tag.

### Task 7: Cell renderer — backdrop, cell painter, particles, overlays

**Goal:** The procedural visual layer: water backdrop, genome-driven cell painter, particle system, world-layer draw order — ported to Godot `_draw` calls, validated by pixel-asserts.

**Files:**
- Create: `src/gfx/renderer.gd` (draw-primitive helpers: disc, glow, panel, outlined text, vignette, hsl→Color), `src/gfx/cell_painter.gd` (draw_cell), `src/gfx/backdrop.gd` (water), `src/gfx/particles.gd` (Fx pool)
- Test: `tests/test_particles.gd` (`-s` headless), `tests/scenes/test_visual_cell.tscn` + `.gd` (xvfb pixel-assert)

**Acceptance Criteria:**
- [ ] `renderer.gd` helpers: `disc`, `glow` (radial falloff), `panel` (fill+stroke rounded rect), `vignette`, `outlined_text` (Godot font with outline — visual parity at presence/position level, not glyph-exact; recorded as accepted divergence), `hsl(h, s, l) -> Color` matching TS hsl math.
- [ ] `cell_painter.gd`: `draw_cell(canvas_item, genome, pose)` port of `src/gfx/cell.ts` — CellPose fields (x, y, moveAngle, speed, scale, hurt, eat, dash, seed, stun), body membrane + organelles + flagella/cilia/spikes/jaw visuals driven by the genome fields, hurt/eat/stun modulation, alpha option. Reads the TS file for every visual constant.
- [ ] `backdrop.gd`: water layers + depth tint (`depth01` from cam.y) + chaos tint, parallax with camera — port of `drawWaterBackdrop`.
- [ ] `particles.gd`: TS Particles port — pooled (cap 1200 stage / 1100 game), spawn/burst kinds (bubble, smoke, dot, ring w/ grow), update with drag/ttl, render.
- [ ] Pixel-assert (xvfb): a fixed genome (size 1.0, hue 120, spots, flagella 2, jaw 1) drawn at origin → capture → PIL asserts: body-disc center pixel ≈ hue-120 color (± tolerance per channel 12), membrane ring sampled on radius (alpha discontinuity), backdrop corner ≠ pure black, 2 flagella tails present as non-background pixels in expected sectors. Baselines recorded to `tests/fixtures/visual/` and diffed with tolerance (no exact-frame pinning — llvmpipe is deterministic but font/AA may shift across mesa versions; assert structural pixels, not byte equality).
- [ ] Draw order matches TS render(): backdrop → boundary ring → kelp → vent glows → zones → pellets → ents (culled to view bounds ±80) → hp bars → player (blink invuln alpha 0.45) → fx → vignette → glitch overlay (difference blend — Godot: a CanvasItem with blend_mode) → HP bar → death overlay → tutorial → shore button.

**Verify:** `godot --headless -s tests/run.gd` → test_particles green; xvfb visual scene exits 0 with PIL-verified pixels.

**Steps:**
- [ ] Read TS gfx files fully; port particles first (headless-testable) → test green → commit `feat: particle system port`.
- [ ] Port renderer helpers + cell painter + backdrop; visual scene test → capture → PIL check → iterate until green. Commit `feat: cell renderer + backdrop (pixel-asserted)`.

### Task 8: HUD, editor, pause, tutorial

**Goal:** The overlay UI set the cell stage drives: toast/floatWorld/banner queue, abilities bar, DNA counter, the cell editor (buy/sell through context.spend_dna), pause menu, tutorial engine.

**Files:**
- Create: `src/ui/hud.gd`, `src/ui/editor.gd`, `src/ui/pause.gd`, `src/ui/tutorial.gd`
- Test: `tests/test_tutorial.gd` (headless), `tests/scenes/test_editor.tscn` + `.gd` (xvfb: click a part button with a synthetic mouse event at its rect → DNA spent)

**Acceptance Criteria:**
- [ ] `hud.gd`: toast queue (kind styles info/bad/chaos/reward/world + icon + ttl), float_world (world-space rising text), banner (title/sub/kind + ttl 2.4 default + dismiss), objective line, abilities bar (key/icon/cd fraction/active — the 5 cell abilities from CellStage), pointer_down hit-routing for hud buttons (Game routes clicks hud-first).
- [ ] `editor.gd`: parts grid (PARTS from M1 with costs `part_cost`), buy (`+`) → `context.spend_dna` gate → genome bump → `sim.on_stats_changed()` refresh; sell (`-`) → `part_refund`; diet/pattern/coat rows for later stages shown per stage filter ('cell' shows cell parts); `show(stage)/close()/open`; KeyE/Escape close; click_part(row, btn) programmatic path (TS-test parity).
- [ ] `pause.gd`: open/close, resume/save-now/quit-to-title buttons (save-now via `game.save_all()`), muted toggle.
- [ ] `tutorial.gd`: step engine port (id/text/done-callback list, advance on done, finish, flags persist `tutCell`, fresh key starts inactive when flag == 'done'); cell stage's 5 steps wired (move > 140, eaten ≥ 3, editorOpened ≥ 1, killed ≥ 1, legs ≥ 1) with the exact TS step texts through tr().
- [ ] Editor interaction test: synthetic click on the flagella '+' button rect (found via the editor's own row-rect getter) spends DNA and bumps the gene — REAL input pipeline per Constraint 8.

**Verify:** `-s` runner green; xvfb editor scene exits 0.

**Steps:**
- [ ] Read TS ui files; port tutorial + test (headless) → commit `feat: tutorial engine`.
- [ ] Port hud + pause; wire into Game render/update path → commit `feat: hud + pause`.
- [ ] Port editor + xvfb click test → commit `feat: cell editor`.

### Task 9: Menu + game flow — transitions, difficulty, autosave, world story pump

**Goal:** The full orchestrator behavior from game.ts: stage machine with the 3-phase transition (out 0.55 / card 2.2 / in 0.6 + pendingGoTo queue with survivesQuit), resetStagesForNewRun + resetNarration, the menu UI (slots/difficulty/continue/lang/mute), autosave, chaos settle + karma drift, pumpWorldStory (reveals/combos/turns announcement + codex flag + storyteller signals + beats).

**Files:**
- Create: `src/game/menu.gd`
- Modify: `src/game/game.gd` (full pumpWorldStory + transitions + autosave port)
- Test: `tests/test_game_flow.gd` (headless — game.gd without rendering), `tests/scenes/test_menu.tscn` + `.gd` (xvfb click flow)

**Acceptance Criteria:**
- [ ] Transition system exact: out 0.55 → switchStage → card (2.2s, click skips + consumes the click) or in 0.6 when no title → in 0.6 → pendingGoTo re-fire; same-destination re-request dropped; queued otherwise; quit-to-title cancels non-surviving queued goTos.
- [ ] `reset_stages_for_new_run()` + `reset_narration()` port (storyteller.reset, deathsInStage/stageTime/gaiaDeathAt/dnaWindow/dyingUntil wiped; stageFactory re-instantiates stages).
- [ ] Menu UI: title, 3 slot cards (meta: stage/playtime/dna/playerName from the save JSON — TS slotMeta), NEW LIFE (difficulty pick peaceful/normal/chaos + slot), CONTINUE (loads slot), language toggle, mute; start_new_game(slot, difficulty, seed = -1) with the M1 contract (chaos starting values 0.08/0.15/0.45, gapMult, flags.difficulty, initial save written).
- [ ] Update loop exact: blocked = paused || editor.open (pause/editor update instead of stage); hud click routing hud-first; card phase freezes stage sim; autosave every 60s (never in menu/transition, through persist_state → save); chaos settle `+= (settleAt − chaos) * min(1, dt*0.03)` (settleAt 0.05/0.12/0.25); karma drift `+= −karma * min(1, dt*0.003)` only when negative; KeyM mute; Escape routing (editor close > pause close > pause open, never on menu/transition).
- [ ] `pump_world_story(dt)`: per-stage timers, beat offers (herd_remembers kin pop ≥ 15 after dyingUntil; gaia_redemption first-death + 3.5s once; gaia_wanderer herd crash < 10% peak with no active chaos and stage implements it), temperament assignment, storyteller.update signals (ecoHealth = living/6 capped 1, dnaRate 60s window), tick_world_reveals with announce trait/combo/turn (worldToast kind 'world' ttl 6, codex_world flag append), epoch_apex body naming, runBeat cases (herd DNA +25, gaia card, wanderer spawn).
- [ ] Headless flow test: seeded boot → menu → start_new_game(0, 'chaos', seed) → difficulty assertions (M1 values) → transition phases timed → autosave fires (clock advanced) → chaos settles toward 0.25 → karma drifts up from −0.5 → reveal announcement lands as a world toast on a trait-forcing seed.
- [ ] Menu scene test (xvfb): click NEW LIFE → difficulty → slot → reaches cell stage via real clicks.

**Verify:** `-s` runner + xvfb menu scene both exit 0.

**Steps:**
- [ ] Port transitions + reset/flow + headless flow test → commit `feat: stage machine + transitions + world story pump`.
- [ ] Port menu UI + xvfb click test → commit `feat: menu (slots/difficulty/continue/settings)`.

### Task 10: Pixel-assert visual suite + econ probes

**Goal:** The two remaining §5.2 parity criteria as repeatable tests: the visual QA sweep (multiple game moments, PIL-checked) and the cell-stage econ probes (per-trait + stacked effects through the REAL sim loop).

**Files:**
- Create: `tests/scenes/test_visual_suite.tscn` + `.gd`, `tools/visual_assert.py` (PIL checker), `tests/test_econ_probes.gd`
- Test: both

**Acceptance Criteria:**
- [ ] Visual suite (xvfb): captures at 6 pinned moments with fixed seeds — menu, early cell (t=3s), mid play (t=60s, forced chaos event via trigger), editor open, death overlay (forced hp 0), transition card. Each capture → PIL asserts (structural: backdrop gradient direction, HUD DNA text region non-empty, chaos banner present when triggered, editor grid rows visible, death overlay tint, card text present) with per-assert tolerance records. Baselines stored under `tests/fixtures/visual/`.
- [ ] Econ probes port (mirror the TS econ-probe test cases for the cell stage): scripted sim runs per trait (iron_gut carnivore ecoSeed, hungry_bloom flora drain, swift_world swarm, calm_veil predator thinning, corpse_tide scavenger budget, kin_memory grudge) asserting the population/DNA/flora outcomes match TS-derived pinned values (extract via scratch vitest in the TS repo, values verbatim into the test, provenance comment). Plus one stacked probe (2 traits) matching the TS stacked probe.
- [ ] 1000-seed determinism: seed → 600-tick cell sim → state hash; 1000 seeds all self-consistent across a second run (reuses the M1 determinism pattern at stage level).

**Verify:** xvfb suite + `-s` econ probes both exit 0.

**Steps:**
- [ ] Port `visual_assert.py` + capture scene; iterate asserts until honest-green. Commit `test: visual QA suite (pixel-asserted)`.
- [ ] Extract probe pins via scratch vitest; write econ probe tests → green. Commit `test: cell econ probes (per-trait + stacked)`.


