# PRIMORDIA Native — M5 parity checklist (civ stage)

Datum: 2026-10-03 · Tag: `civ-parity-m5` (controller review + tag pending) · Spec: [`docs/specs/2026-09-29-native-migration-design.md`](specs/2026-09-29-native-migration-design.md) §5.4 (the §5.3 gate shape, civ flavor)

**Status: WRAP COMPLETE (task 7) — the A-B behavior-identity run is
IDENTICAL (§10), the §5.4 perf budgets are measured and MET with the split
metrics (§11), ARCHITECTURE/README carry the civ surfaces, and the full
suite is green on the wrap tree (§5.4 checklist). Remaining: the
controller's final whole-branch review, then the `civ-parity-m5` tag.**
Every civ-stage feature of the frozen TS build has a native pin. One item is
the explicit, spec-sanctioned deferral (audio synth — the M1/M4 ruling
carries); it is not a civ-stage behavior gap.

**Source of truth:** the TS contract (the feature surface of
`Spore/src/game/civ/CivStage.ts` 663 lines + `civEvents.ts` 79 lines, both
frozen 2026-10-01). Native pins reference `tests/` test methods
(`file::test_name`), scene suites under `tests/scenes/`, the task-6 probes,
and the bot (`tests/bots/bot_civ.gd`).

**Headline numbers (the task-7 wrap, re-run on the wrap tree):** headless
suite → **49 files, 721 tests, 19548 checks, 0 failures** (the task-6 gate
numbers re-verified — the wrap commits are rider deletions/comment fixes,
perf probes and docs only; no sim or suite file changed the counts). Probes:
`tools/probe_civ.sh` → **14 tests / 133 checks / 0 failures** (also inside
the full suite). Scene suite under xvfb: `tools/test_civ_scene.sh` →
**VISUAL_TEST_OK, 40 structural asserts, exit 0** (§7). Bot:
`tools/test_bot_civ.sh` → **BOT_CIV_ALL_OK ×2 determinism per pass, three
recorded runs** (task 5 ×2; the task-7 wrap's third run after the
T6-review guard deletion). Audio hooks stay no-op with TS call sites/params
pinned (the standing deferral).

Legend: ✅ pinned · ⏸ spec-sanctioned deferral.

## 1. Civ sim core — state, sliders, armadas, tickSecond (task 1)

| Feature | TS | Native | Test |
|---|---|---|---|
| Constants: output 10, sliders clamp 0..10, regen 6 s, armada speed 220, resolve d < 14 / t > 14, launchCd 5, spend 2, power = stat + 4 SNAPSHOT, rivalDef matrix, net ×10, toastInset 150, planet r min(vw,vh)·0.42, toScreen ×0.62 | CivStage.ts:56-63, :235-236, :327, :344, :351-355, :368 | `civ_sim.gd` field blocks + `civ_stage.gd` geometry seams (`planet_radius`, `map_to_screen`) | `test_civ_sim.gd::test_constructor_seeding_pins`, `::test_rival_def_matrix`; scene `test_civ_scene.gd::test_geometry_seams` |
| Constructor: rng = context rng BRANCH (boot-order), rulerGenome = the context genome REFERENCE; capital {id 'you', `{player_name}grad`, x 0, y 120, hp 100, influence 100, pop 8}; 3 rivals verbatim (military 0.8 / culture 0.35 / economy 0.25 + colors); rival cities cos/sin ring + rng(−120,120)/rng(−90,90) − 60, names Khora/Vex/Ompa (Prime unused), influence −60, pop 6 — draw order x-then-y sacred; chaos scheduler on a SECOND branch with the civ deck; deckSeed = world seed | TS:79-111 | `civ_sim.gd::_init` | `test_civ_sim.gd::test_constructor_seeding_pins` (draw-order replay bit-exact); boot-order branch `test_hud_civ.gd::test_boot_order_branch_pin` |
| on_enter: C1 deck-rebuild gate (world.seed ≠ deckSeed), setMood('civ') hook, toastInset 150 (clears the portrait), showObjective 'UNIFY THE PLANET — …', restore_state, brick hardening (victoryFired + all owned → go_to('space') — the softlock pin). on_exit → persist_state | TS:113-130 | `civ_sim.gd::on_enter/on_exit` | `test_civ_sim.gd::test_on_enter_semantics`, `::test_brick_hardening`; headless stage `test_civ_scene.gd::test_on_enter_sets_inset150_and_objective` |
| persist/restore: blob {cities[id,owner,influence,hp,pop], mil/culture/econ, victoryFired, lastRaised} → flags.civState; restore guards — parse-fail/length-mismatch → false, owner sanitize ('you' or a live rival id), Number.isFinite type-check BEFORE float (the TS "50" quirk), clamps ±100 / 5..100 / 1..30 / 0..10, victoryFired STRICT ===true, lastRaised lane whitelist (the first-post-CONTINUE-drip pin) | TS:132-173 | `civ_sim.gd::persist_state/restore_state` | `test_civ_sim.gd::test_persist_restore_roundtrip`, `::test_restore_guards`; E2E `test_world_creature_pins.gd::test_civ_save_continue_restores_board`, `::test_civ_stale_blob_guards_e2e` |
| launchCds decay max(0, cd − dt) per kind | TS:182-184 | `civ_sim.gd::update` | `test_civ_sim.gd::test_update_abilities_and_camera`; probe ladder |
| Regen: regenT += dt; ≥ 6 → reset 0; only while total < output → lastRaised lane +1 | TS:186-195 | `civ_sim.gd::update` | `test_civ_sim.gd::test_regen_and_lastraised`; probe `test_probe_civ.gd::test_regen_lane_pin_cadence_exact` (4 exact fire ticks replayed, spent-lane identity) |
| Sliders: Q/W/E raise via the TS raise lambda — clamp +1; total > output → donate 1 from the largest OTHER (stable desc sort → the culture/econ tie keeps canonical order → CULTURE donates); donor-0 revert branch UNREACHABLE (kept dead, proof-pinned); A/S/D lower clamped, never touch lastRaised; every press latches lastRaised (even a clamped no-op) | TS:197-222 | `civ_sim.gd::_raise_lane` | `test_civ_sim.gd::test_slider_raise_transfer`; probe `test_probe_civ.gd::test_slider_transfer_full_board_tie_seeded` (the tie + the stream-blind pin + the clamped-press latch) |
| Launch: Digit1/2/3 → attack/charm/trade; gates IN ORDER cd (silent) → stat < 2 toast → no-targets toast → power SNAPSHOT stat + 4 → hopeless refuse (power ≤ rivalDef + 2, the `{5−stat}+ more output` toast); spend 2 (max(0, ·)); lastRaised = the SPENT lane (the pacifist-drain pin); cd 5; armada {capital pos, target, kind, t 0, alive, power}; toast `{KIND} armada → {name} (power {power})`; target = nearest enemy city (stable sort → strict-< minimum scan, first minimum wins ties) | TS:224-227, :310-349 | `civ_sim.gd::launch` | `test_civ_sim.gd::test_launch_gates_order`, `::test_launch_boundary_and_toast`, `::test_launch_spend_sets_lastraised`, `::test_launch_gate_difficulty_matrix`; probe `test_probe_civ.gd::test_launch_gate_ladder_and_power_snapshot` (every refusal toast + the SNAPSHOT surviving a mid-flight slider drop) |
| Flight: t += dt; d < 14 || t > 14 → resolve; else move (dx/d)·220·dt; trail fx chance(dt·30) → range(−8,8), ttl 0.5, size 2, dot, #9fd8ff, drag 1 at RAW map coords (the quirk); the filter quirk `alive || t < 0` (t advances first — the t<0 arm never keeps) | TS:229-250 | `civ_sim.gd::update` | `test_civ_sim.gd::test_armada_flight_timeout_and_trail` |
| rivalDefFor: (rival ? 6 : 3) + (chaos ? +3 : peaceful ? −1 : 0) — ONE source of truth for the gate AND the resolve (the drift pin) | TS:351-355 | `civ_sim.gd::rival_def_for` | `test_civ_sim.gd::test_rival_def_matrix`; probe net matrix (below) |
| resolveArmada: owned target → return BEFORE any effect; power = the SNAPSHOT; net = (power − rivalDef)·10; influence clamp ±100; floatWorld toScreen-corrected `{±}{round(net/10)} influence` (the _round_js tie quirk); camShakeFor(3, 0.2); ring fx ttl 0.7 size 30 grow 2 at RAW coords; attack: hp clamp(−12, 5, 100) + burning 6 @ chance(0.5) only while burning ≤ 0 (the && short-circuit consumes NO draw otherwise) + karma −0.02; charm +0.015 / trade +0.01; flip at ≥ 100: owner 'you' + hp max(hp, 40) + banner reward | TS:357-390 | `civ_sim.gd::resolve_armada` | `test_civ_sim.gd::test_armada_resolve_near_target`, `::test_armada_charm_flip`, `::test_armada_trade_karma`, `::test_resolve_owned_target_noop`; probe flip both directions + the burning stream pins (`test_probe_civ.gd::test_flip_hp_floor_both_directions`, `::test_burning_chance_seeded_stream`) + the net matrix across difficulties (`::test_resolve_net_math_difficulty_matrix`) |
| tickSecond gate: the float floor-cross `floor(time) ≠ floor(time − dt)` (NOT an accumulator) | TS:253 | `civ_sim.gd::update` | `test_civ_sim.gd::test_tick_second_floor_gate` |
| tickSecond per-city: yours → pop min(30, +0.02), hp min(100, +0.5), burning −= 1, unrest heal min(0, +0.12) while < 0; rival's → military shells capital max(20, − aggression·0.4) + toast @ 0.02, culture erodes each your-city max(−100, −1.5) @ 0.03, economy pop +0.05 UNCAPPED + buy @ 0.01: pick over cities not its own → −2 (the `=== owner ? 0` arm unreachable by construction); burning tail (any owner) hp max(5, −2), burning −= 0.5 (your city decrements TWICE — the :399 + :427 quirk) | TS:392-428 | `civ_sim.gd::tick_second` | `test_civ_sim.gd::test_tick_second_full_derivation`, `::test_tick_military_shell_floor`, `::test_tick_burning`; probe `test_probe_civ.gd::test_tick_second_personalities_over_real_seconds` (60 real seconds, the full draw chain replayed on a cloned stream, all three personalities firing, the UNCAPPED pop past 30, the buy never on its own city) |
| Hearts: every enemy city influence += culture·0.006 + econ·0.004 − 0.02, clamp ±100 | TS:430-436 | `civ_sim.gd::tick_second` | `test_civ_sim.gd::test_tick_second_full_derivation`; probe `test_probe_civ.gd::test_hearts_formula_over_real_seconds` (two 50 s phases isolate the two weights; the clamp → the tick-side flip with NO hp floor) |
| Karma drift: addKarma((culture − mil)·0.0004) per tickSecond | TS:438-439 | `civ_sim.gd::tick_second` | `test_civ_sim.gd::test_tick_second_full_derivation`; probe `test_probe_civ.gd::test_karma_drift_split_slopes` (the slope flips sign with the split; the 5/5 tie is exactly 0) |
| Flips/revolt: enemy ≥ 100 → 'you' + levelup + banner (NO hp floor here — the resolve/tick asymmetry); YOUR city ≤ −99.8 → revolt to the former owner BY CITY ID (the capital's 'you' falls back to rivals[0]) + banner + influence −100 — the threshold sits ABOVE the +0.12 heal step (a −100 city heals to −99.88 and still revolts) | TS:441-456 | `civ_sim.gd::tick_second` | `test_civ_sim.gd::test_tick_flips_and_revolt`; probe `test_probe_civ.gd::test_revolt_gate_sits_above_the_heal` (the −99.91 ordering discriminator + the float-boundary derivation), `::test_unrest_heal_toward_zero` (the min(0, ·) cap exact) |
| Victory: all owned && !victoryFired → latch + save_all flush + ascend + go_to('space', THE BLACK OCEAN) | TS:289-296 | `civ_sim.gd::update` | `test_civ_sim.gd::test_victory_path` |
| Camera drift toward the last armada (min(1, dt·1.2) / decay 0.5) — the sim owns camX/camY, the stage renders from them | TS:279-287 | `civ_sim.gd::update` | `test_civ_sim.gd::test_update_abilities_and_camera` |
| Abilities payload: 3 cd entries with NO active key (TS undefined semantics) + 3 slider entries active on lane > 0; cds render /5 | TS:298-305 | `civ_sim.gd::update` | `test_civ_sim.gd::test_update_abilities_and_camera`; stage `test_civ_scene.gd::test_set_abilities_payload_mirrors_sliders_each_frame` |
| Debug seams (the bot-law surface): debug_state (read), debug_set_influence (SET/absolute — the bot's victory grant), debug_clear_chaos (determinism legs) | — (native seam, documented in the header) | `civ_sim.gd` tail | `test_civ_sim.gd::test_debug_seams`; the bot-law audit in task-5-review.md |

## 2. Civ chaos deck + scheduler wiring (task 2)

| Feature | TS | Native | Test |
|---|---|---|---|
| Baseline 4 defs verbatim: quake 0.7 + chaos cd 55 (warn); rebellion 0.6 + max(0,−karma)·0.8 cd 45; goldenage 0.6 + max(0,karma)·0.9 cd 80 dur [14,20]; worldwar 0.6 + chaos cd 70 (warn) | civEvents.ts:10-45 | `civ_events.gd` baseline | `test_civ_events.gd::test_traitless_deck_is_four_defs`, `::test_def_constants_verbatim`, `::test_weight_formulas` |
| Gated variants: golden_rival (worldNum growth_mult > 1.2 — swift_world) dur [30,30] cd 90 apply/tick; trade_winds (calmProxy — calm_veil) dur [40,40] cd 100, the bless-mood ×1.3 rides INSIDE the weight fn | civEvents.ts:47-79 | `civ_events.gd::_golden_rival/_trade_winds` | `test_civ_events.gd::test_gated_defs_gate_on_the_world`, `::test_bless_mood_ratio_pin` |
| The factory draws NOTHING from any rng stream (the gates fold at build time) — the stage stream stays TS-aligned | civEvents.ts:47 | `civ_events.gd::make_civ_chaos_events` | `test_civ_events.gd::test_deck_factory_draws_nothing` |
| Scheduler wiring: second rng.branch(), C1 rebuild on enter, ctx {chaos, karma, stageTime, gapMult·gapBias, mood, warnScale}, onWarn (banner danger ttl 2.4 + alarm) + onApply (banner chaos + addChaos 0.03 + storyteller note), NO onEnd (the missing-hook no-op) | TS:109, :258-277 | `civ_sim.gd::update_chaos` + `civ_stage.gd::_build_hooks` | `test_civ_sim.gd::test_chaos_scheduler_wiring`; `test_civ_events.gd::test_update_drives_the_real_deck`, `::test_golden_rival_tick_wiring`, `::test_trade_winds_tick_wiring`, `::test_update_chaos_ctx_real_values`; the live-storyteller rider `test_civ_scene.gd::test_real_storyteller_values_reach_update_chaos` |
| Chaos hook methods exact: earthquake / rebellion (the BY-ID capital exclusion, empty → return BEFORE the draw) / goldenAge / rivalWar / rivalSurgeBegin+Tick / tradeWindsBegin+Tick | TS:459-526 | `civ_sim.gd` chaos hooks | `test_civ_sim.gd::test_chaos_hook_*` (six); probes `test_probe_civ.gd::test_golden_age_effects_exact`, `::test_trade_winds_regen_pace_and_pops` (the +20% regen pace observed vs the plain twin), `::test_rival_surge_rates_exact` (the capped economy pop vs the base tick's UNCAPPED quirk) |

## 3. Civ stage scene node (task 3)

| Feature | TS | Native | Test |
|---|---|---|---|
| Render order: backdrop(fakeCam x·0.3/y·0.3, seed 42) → ocean radial gradient (offset light center, inner r 0.2pr) → 7 continent blobs (a = i·2.4 + 0.7) → rim glow 1.18pr → armadas (disc 4 + glow + dashed [4,6] trail) → cities (disc 9 + glow + labels + influence/hp bars + burning glow) → portrait → sliders panel → launch hints → victory shimmer → vignette 0.5; `void disc;` NOT ported | TS:530-662 | `civ_stage.gd::_draw_planet/_draw_ui` | scene moments §7; headless `test_civ_scene.gd::test_render_guards_pre_and_post_restore` |
| Screen-space doctrine: NO Cam object — the canvases cancel the live canvas_transform in _draw; the portrait SUBTREE cancels at the NODE transform (the clip group needs it — the task-3 root-cause fix) | — (native render architecture) | `civ_stage.gd::_screen_inv/render` | `test_civ_scene.gd::test_geometry_seams`; the scene suite's camera-pinned trail asserts |
| Portrait: panel (18, vh−120, 96, 96) + clip rect (22, vh−116, 88, 88) via clip_children (the mask at FULL alpha — the divergence note) + draw_creature(rulerGenome, scale 1.4, mood happy, gait time·2) — the 3-RID painter contract | TS:616-626 | `civ_stage.gd::PortraitItem/PortraitCreature` | `test_civ_scene.gd::test_portrait_fixture_syncs_per_render`; scene moment §7 (the clip-holds ring assert) |
| Sliders panel: 3 labeled round-rect bars, fill max(3, 160·val/10), value labels; launch hints line; the victory shimmer reads the BOARD only (not victoryFired-gated) | TS:628-658 | `civ_stage.gd::_draw_ui` | scene moments §7 |
| Input snapshot: the stage builds the M2 snapshot (keys_pressed canonical — civ is keyboard-only; the mouse fields ride along unused, no hudRects) | TS:177-180 | `civ_stage.gd::update/_build_input_snapshot` | `test_civ_scene.gd::test_snapshot_keys_reach_the_sim`, `::test_snapshot_carries_mouse_fields_unused` |
| Frozen seam (render without stepping) | — (native test seam) | `civ_stage.frozen` | `test_civ_scene.gd::test_frozen_seam_holds_the_sim` |

## 4. Wiring — registration, handoff, save/continue, i18n (task 4)

| Feature | TS | Native | Test |
|---|---|---|---|
| Registration in BOTH lists (boot register + resetStagesForNewRun factory), boot order cell → creature → tribe → civ (the branch-order replay pin) | — (wiring) | `src/main.gd:29-42` | `test_hud_civ.gd::test_main_registers_civ_stage`, `::test_boot_order_branch_pin` |
| toast_inset 150: armed by civ on_enter over the game-level switch reset (game.ts:213) | TS:120 | `civ_stage.gd::_h_hud_toast_inset` + `game.gd` | `test_hud_civ.gd::test_switch_stage_resets_toast_inset` |
| Tribe → civ landing E2E: the tribe victory go_to('civ', THE FIRST CITY) lands the REGISTERED stage (inset 150, the 4-city constructor board) | TS:113-121 | `game.gd` + `civ_stage.on_enter` | `test_hud_civ.gd::test_tribe_victory_lands_registered_civ`; the bot's real victory card |
| civState save/continue E2E: the board AS IT STOOD; the stale length-mismatch blob → false → fresh board | TS:132-173 | `game.gd` persist seam + `civ_sim.restore_state` | `test_world_creature_pins.gd::test_civ_save_continue_restores_board`, `::test_civ_stale_blob_guards_e2e` |
| Victory → space placeholder: go_to('space', THE BLACK OCEAN) captured exact; space UNREGISTERED → the switch no-ops (TS-true), the civ stage remains | TS:289-296 | `game.gd::switch_stage` + `civ_sim` victory | `test_hud_civ.gd::test_victory_to_space_placeholder`; the bot's victory leg (§5) |
| Brick-hardening E2E: a unified CONTINUE lands civ → the space transition fires immediately | TS:123-128 | `civ_sim.on_enter` | `test_hud_civ.gd::test_brick_hardening_continue_auto_space` |
| i18n: the TS VI object's civ strings 1:1 in vi.csv (12 t() sites); the RAW sites stay raw (the objective line, refusals, JOINS/REVOLTS, the shell/quake/unrest toasts) | TS VI object | `assets/i18n/vi.csv` | `test_hud_civ.gd::test_civ_i18n_mapping_1to1` |

## 5. Bot arc + determinism (the §5.4(b) gate — task 5)

| Feature | Native pin | Status |
|---|---|---|
| The full arc through the REAL input pipeline (bot law audited 1:1 against the sim's documented debug surface — the only sim call is `debug_set_influence`, 3 sites): the REUSED bot_tribe legs' real victory lands civ → the Digit1 refuse rung observed (no armada) → the full-board Q transfer toast → 2+ honest launches (spend, SNAPSHOT, cd 5, lastRaised, the power-9 toast) each resolved on the REAL clock with the net-math read-back (+3 influence floaters) → the regen refills (lastRaised lane, exactly 2) → the cheat grants → the far flips through the REAL tick_second hearts path → ONE real Digit1 flips the nearest at the clamped resolve → victoryFired → the exact space card → the unregistered-space no-op with the civ stage remaining | scene `test_bot_civ.gd` → BOT_CIV_ALL_OK ×2 determinism per pass (LCG 777 / world 0xBEEF) — **three recorded green runs**: task 5 ×2, the task-7 wrap's third run after the T6-review guard deletion (the quantized end-fingerprint field-identical across all three: victory true, 4/4 cities 'you', dna 107900); the bot-law audit in `task-5-review.md` | ✅ |
| Same seed → same run path: quantized CIV end-state fingerprints field-identical across the two passes (exact key set pinned) + the per-600-frame sweep trace as first-divergence triage; the stage-named reads (the `game.current` decoy pin) | `test_bot_civ_pins.gd::test_bot_composition_shares_one_lcg_stream`, `::test_civ_fingerprint_is_stage_named_and_exact`, `::test_nearest_unowned_scan_mirrors_the_launch_filter`, `::test_sweep_trace_cadence_is_600` | ✅ |

## 6. Probes (§5.4(c) — task 6)

`tests/test_probe_civ.gd` (14 tests / 133 checks) + the one-command headless
entry `tools/probe_civ.sh` (the targeted `tests/probe_runner.gd` runner; the
file also joins the full suite). Each probe boots the full Game + the REAL
CivStage out-of-tree and drives the sim through its documented
input-SNAPSHOT contract; formulas cited to the frozen TS lines in each
probe's provenance comment. Independent derivations: closed-form TS-verbatim
formulas computed probe-side, fire ticks replayed from the same accumulation
regime, and draw-dependent pins replayed on a CLONED stream
(`Rng.new_from(sim.rng.state())` — never the sim's own code). Seeds
0xC171-0xC17E + 0xC180 (probe 7's tickSecond seed sits outside the run);
the red-check (a deliberately corrupted derivation fails
loudly) is recorded in the task-6 report:

| Probe | Pins |
|---|---|
| slider transfer | the full-board Q: mil +1, the culture/econ tie donates CULTURE (the stable-sort canonical order, TS:203-210); donor = the largest OTHER; under-output raises free; a clamped maxed-lane press is silent but still latches lastRaised (TS:219); lowering never touches lastRaised; the transfer path draws NOTHING from the stage stream |
| regen lane | the charm launch's spend latches lastRaised → 4 refills land in THAT lane at the derived 6 s fire ticks (every cycle restarts from exactly 0.0 — the cadence exact over ≥ 3 cycles, TS:186-195 + :340-343); the other lanes never move |
| launch ladder | cd silent → stat-2 toast → stat precedes targets → no-targets toast → the honest `{5−stat}+ more output` refuse → the launch (power 9 SNAPSHOT, spend, cd 5, lastRaised, the verbatim toast); the SNAPSHOT survives a mid-flight slider drop (mil 5→1 mid-flight, the resolve still nets (9−6)·10 = +30, NOT the would-be (5−6)·10) — the TS:326-327 pin |
| resolve net | (power − rivalDef)·10 exact across normal/chaos/peaceful (two honest launches per difficulty, distinct net pairs — TS:351-355 + :368); attack hp −12 ×2 |
| flip + hp floor | the resolve flip at the 100 clamp: owner 'you', hp max(20, 40) = 40 AND max(55, 40) = 55 (the floor lifts, never lowers — TS:386); the banner through the REAL hud; charm karma +0.015 |
| burning | the attack roll instrumented at its stream position (the first post-construction draw): the band + the 0xC176 literal 0.36190336477011442 (re-instrument on any draw-history change); a city already burning consumes NO draw (the && short-circuit, TS:378) |
| tickSecond personalities | 60 real seconds, the FULL draw chain replayed on a cloned stream (shell 0.02 → erosion 0.03 → buy 0.01 → pick over [cap, c1, c2]): capital hp = production −0.32/s composed, the erosion −1.5 per fired draw, economy pop +0.05 UNCAPPED (29.9 → 32.9 past 30), the buy never on its own city, one shell toast per fired draw (TS:392-428) |
| hearts | culture·0.006 + econ·0.004 − 0.02 per second exact: phase A culture 10 → +0.04/s, phase B econ 10 → +0.02/s (the weights distinguished); the 99.99 city clamps to 100 and flips the SAME tick with NO hp floor (the tick-side asymmetry, TS:430-447) |
| karma drift | (culture − mil)·0.0004 per second: +0.004/s at 0/10, −0.004/s at 10/0 (the sign flips with the split), exactly 0 at the 5/5 tie (TS:438-439) |
| revolt | the gate sits ABOVE the heal: −100 revolts (the healed −99.88 still ≤ −99.8); the −99.92 float-boundary case derived with the identical ops; −99.91 heals to −99.79 and survives — the ORDERING discriminator; the capital's rivals[0] fallback; the reset −100 + banner (TS:448-454) |
| unrest heal | +0.12/s toward 0 over 30 s (−50 → −46.4), the min(0, ·) cap EXACTLY 0, the < 0 gate holds 0 (TS:400); the owned-city production rode along |
| goldenAge | hp 100, influence +15 clamped at 100, pop +2 UNCAPPED (29.5 → 31.5 past 30 — the quirk), enemy cities untouched, the toast verbatim (TS:478-483) |
| tradeWinds | the +20% regen share COMPRESSES the cadence (the fire observed ~1 s early vs the plain twin at the same seed, both derived by replay); every city pop +0.008·dt composed with the production (TS:517-525) |
| rivalSurge | the ×1.3 rates over 100 ticks: military −aggression·0.12·dt with the 20 floor biting on the first tick, culture −1.5 @ 0.009·dt (replayed draws), economy pop min(30, +0.015·dt) CAPPED at exactly 30 — the pair with the base tick's UNCAPPED +0.05 (TS:494-515) |

## 7. Visual moments (§5.4(d) pixel-assert — task 6 inventory)

scene `tests/scenes/test_civ_scene.gd` + `tools/visual_check_civ_scene.py`
(xvfb + Compatibility renderer, llvmpipe-deterministic; probes.json carries
the live anchors re-derived from the stage's own geometry seams — no copies).
Freeze discipline: sim-state gates only, NO engine-frame counts (the M3
volcano lesson); the armada arms on a REAL Q press + a REAL Digit1 through
the input pipeline. The task-6 brief's six moments are ALL covered by the
task-3 suite — the shared coverage is counted here verbatim (40 structural
asserts, VISUAL_CHECK_OK, exit 0; the moment inventory found no < 3-assert
moment, so no probe-side additions were needed and none were duplicated):

| Moment | Asserts |
|---|---|
| Planet backdrop day (space base corner, stars, ocean blue, the offset-light gradient, continent blobs, the disc band vs space, the rim-glow falloff) | 8 |
| Cities + bars (4 owner-colored discs, the capital influence band full, the +30 green / −60 warm variants, the hp band, name + status labels) | 10 |
| Armada flight + trail (the ship disc through a REAL Digit1, the dashed [4,6] on/gap cadence vs the pre-launch twin, the launch toast band + text) | 5 |
| Sliders panel (panel + title, the full mil bar vs the 3px-floor twins, the ≥ 15× ratio pin, the value label) | 7 |
| Ruler portrait clip (creature pixels INSIDE the clip rect, the body anchor, the exclusion ring holds, the panel corner) | 4 |
| Victory shimmer (the gold title band vs its absence in the pre-victory twin, the band diff, the 3 discs gone green) | 6 |

## 8. Explicit deferrals (spec-sanctioned; none is a civ-stage behavior gap)

| Item | Reason |
|---|---|
| Audio synth (WebAudio → AudioStreamGenerator) | Migration spec §7 risk-table item — the M1 ruling carries through M4; every civ audio site is a no-op hook with the TS call site/params pinned in a comment (`audio_set_mood`, warp/boom/charm/levelup/ascend/alarm/quake). Its own task after parity. |

## 9. M6 deferred (recorded at task 6)

| Item | Provenance |
|---|---|
| SpaceStage registration + the victory 'THE BLACK OCEAN' transition LANDING | M6 scope (plan Completion: M6 = Space, SpaceStage.ts 52.2K + spaceEvents.ts 2.5K — the §5.4 gates at space flavor); until then go_to('space') no-ops safely by design (TS-true), pinned in `test_hud_civ.gd::test_victory_to_space_placeholder` and the bot's victory leg. |
| Space surface notes for the port: the civ persist blob (cities[{id,owner,influence,hp,pop}] / mil / culture / econ / victoryFired / lastRaised) is the space stage's founding input; the brick-hardening gate (victoryFired + all owned → straight to space on on_enter, TS:123-128) is the shape the space landing must keep respecting; the unregistered-'space' no-op with the civ stage remaining is the current placeholder behavior the M6 landing replaces | read off CivStage.ts during task 6 |
| The exit RID-leak baseline comparison (the task-1 rider: ONE clean-baseline suite run at tribe-parity-m4 vs HEAD, stderr diff, pin pre-existing or find the owner) | the SDD ledger task-1 rider — 152 → 215 leaked CanvasItem RIDs with the civ painter teardown pattern; the civ files construct zero nodes, so they cannot be the source; the out-of-tree probe boots reproduce it (the M4 probe precedent). Task 7 (the wrap) or the M6 plan picks it up. |
| Creature painter `update_ents` hot-loop optimization (2 ms target) | M3 §16 carry-forward — still open, gated on creature A-B coverage; now ALSO the M4-optimization prerequisite the creature painter's civ portrait service rides on |
| Audio core (the synth port) | standing deferral §8 — its own task after parity |
| T10 moment pin-gaps ×2 (editor preview body, sun/moon disc) | M3 §17 carry-forward — cheap probe candidates |

## 10. A-B behavior-identity (task 7 — the M5 window)

`tools/ab_test.sh tribe-parity-m4` → **IDENTICAL, 0 diff lines** (exit 0).
Both sides dump sha256 `ea35920b…` — the SAME sha the M2 gate first
recorded and the M3/M4 wraps re-verified: the standing cell+creature dump
did not move one bit from `cell-parity-m2` across the whole creature, tribe
AND civ windows (the civ stage is additive, as the M4 wrap predicted; the
boot-order rng branch joins the replay pin without touching the dump).
Ruled lines: none needed. Record: verdict=IDENTICAL, last_diff.txt 0 bytes,
base_commit=tribe-parity-m4, head_commit=c38c0e9 (the wrap's commits after
it are riders/instruments/tests/docs only, no sim file). The evidence
fixture (`tests/fixtures/ab/evidence.txt`) is harness SCRATCH — rewritten
on every harness run — and deliberately stays at its previous (M4)
snapshot at the wrap; the durable M5 record is this section + the task-7
report.

## 11. Perf (the M4 §12-analog — task 7, split metrics from day one)

**Metric integrity (the T10 lesson carried):** the civ probe was born SPLIT —
the pure sim tick carries the asserted budget (headless,
contention-immune), the stage render pass carries the painter-side budget
(scene-side), the full frame wall-window is recorded, never asserted.

**Civ sim tick @ 4 cities + 3 live armadas (the §5.4 civ budget: ≤ 2 ms,
asserted directly) — MET:**

| Measurement | Number |
|---|---|
| `tools/perf_civ_sim.gd` (headless, contention-immune — the primary instrument; the constructor board verbatim, 3 launch-shaped armadas parked ~8400 units out so the flight loop holds them alive the whole window — no resolve/flip churn; chaos silenced gap 1e9; 300 ticks) | **0.026–0.029 ms avg over 5 runs** (max spikes 0.047–0.170 ms) |
| Cost shape | 4 cities vs tribe's 60-sim job-AI world (M4: 0.71–1.00 ms) — the civ hot loop is the lightest of the arc (armada flight + tickSecond personalities on 5 in-window seconds + the abilities payload) |
| Scene-side cross-check (`tests/scenes/test_perf_civ.gd`, xvfb) | sim avg 1.163 / 1.190 ms over 2 runs — inflated by llvmpipe contention (the recorded number, not the asserted one) |

**Stage render pass @ 4 cities + 3 armadas + portrait + sliders panel (the
M3 painter-side budget shape: ≤ 4 ms) — MET, asserted in the scene probe:**

| Measurement | Number |
|---|---|
| Stage `render()` pass (portrait fixture re-sync + the canvas queue_redraw sweep — the GDScript-side render-prep cost the game controls; the deferred canvas `_draw` lands in the frame window) | **0.048 / 0.054 ms avg over 2 runs** (maxes 0.173/1.459) — asserted ≤ 4 ms |
| Full frame wall-window under llvmpipe (sim + render prep + deferred `_draw` + real rasterization) | **28.6 / 27.9 ms avg** (maxes 77.0/101.7) — rasterization-dominated; no GDScript-side change moves it |

The rig caveat (M2/M3/M4 precedent, restated): llvmpipe is the WORST-case
rasterizer the probe intentionally runs on — the frame budget targets a real
GPU, which is faster by orders of magnitude on this draw set; llvmpipe's
frame window is recorded informationally. The standing tripwires (cell 8 ms,
creature 4 ms, tribe 4 ms headless + 4 ms scene render) carry unchanged —
re-verified green in the wrap sweep (§5.4 checklist, full suite row).

## §5.4 criteria checklist

| Criterion | Evidence pointer | Verdict |
|---|---|---|
| (a) Every TS civ feature present | §1–§4 — every row pinned or explicitly deferred with a spec citation (audio synth only, spec-sanctioned: §8) | ✅ |
| (b) Bot headless full civ arc through the real UI, ×determinism | `tools/test_bot_civ.sh` → BOT_CIV_ALL_OK ×2 (LCG 777 / world 0xBEEF), **three green runs** (task 5 ×2 + the wrap's third run after the T6-review guard deletion): the real tribe victory landing → the refuse rung → the honest launches + flight captures + the net-math read-back → the regen refills → the cheat grants → the real flips → the victory card → the unregistered-space no-op; fingerprints field-identical across passes AND across all three runs (§5) | ✅ |
| (c) Econ probes TS-verbatim | `tools/probe_civ.sh` → **14 tests / 133 checks / 0 failures** (§6; formulas cited to the frozen TS lines in each probe's provenance comment; cloned-stream + replayed-accumulation derivations at pinned seeds); also inside the full headless suite | ✅ |
| (d) Pixel-assert suite, civ moments | the civ scene suite under xvfb (**40 structural asserts** over the six moments, `tools/visual_check_civ_scene.py`, §7) — every moment ≥ 3 PIL-checked structural asserts over a live viewport capture | ✅ |
| Full suite green | headless suite → **49 files / 721 tests / 19548 checks / 0 failures** re-verified on the wrap tree (the task-6 gate numbers exact — the wrap commits are rider deletions/comment fixes, perf instruments and docs only); the full xvfb sweep (17 entries incl. bot_civ and the new perf_civ) all rc=0 at the wrap — the per-entry table in the task-7 report and the completion note below | ✅ |
| A-B behavior-identity + perf budgets | **§10**: `tools/ab_test.sh tribe-parity-m4` → IDENTICAL, 0 diff lines (the standing dump sha `ea35920b…` unmoved since the M2 gate — the civ stage is additive); **§11**: civ sim tick ≤ 2 ms MET (0.026–0.029 ms headless @ 4 cities + 3 live armadas, asserted directly), stage render-prep ≤ 4 ms MET (0.048–0.054 ms, asserted in the scene probe), frame window recorded with the rig caveat | ✅ |

## Completion note (spec §5.4 — the task-7 wrap, 2026-10-03)

M5's seven tasks are complete. Milestone arc `e367148..HEAD` (plan → sim
core → chaos deck → stage scene → wiring → bot → probes + parity list →
the wrap's riders/perf/docs): the four §5.4 feature gates (a)–(d) hold
with the evidence above (§1–§7), the A-B behavior-identity gate is
IDENTICAL across the whole milestone window (§10 — the standing dump sha
`ea35920b…` unmoved since the M2 gate), the §5.4 civ perf budgets are
measured and MET with the split metrics (§11), and the full suite is green
on the wrap tree — headless **49 files / 721 tests / 19548 checks /
0 failures** plus the xvfb sweep **17/17 rc=0** (boot, bot, bot_creature,
bot_tribe, bot_civ, editor_click, menu, visual ×2, visual_suite,
creature_scene, tribe_scene, civ_scene, perf ×4 — the plan's "perf ×2"
predates the tribe/civ probes; the per-entry table lives in the task-7
report).

Wrap riders (the T6 review, landed first): the duplicated Q-tap guard pair
in bot_civ victory_prep is DELETED (`fix: drop duplicated Q-tap guard…`,
5587098 — restoring the task-5 report's comment-only claim) and the third
BOT_CIV_ALL_OK run landed post-deletion with the end fingerprint
field-identical across all three recorded runs (§5). The T6 minors folded
at the wrap (a76e98d): the probe header's "two stream-position literals"
is one (the 0xC176 burning draw — the task-6 report note corrected with a
wrap marker), and the §6 seed range includes 0xC180.

Accepted carry-forward: the exit RID-leak baseline comparison (§9 — the
clean-baseline suite run at tribe-parity-m4 vs HEAD, the 152 → 215
provenance) goes to the M6 plan per §9's sanctioned split ("task 7 or the
M6 plan picks it up") — the leak itself is already pinned pre-existing and
the civ files construct zero nodes (§9 row); the wrap's gate list (A-B,
perf, the 17-entry sweep on the committed tree) took the window.

Remaining: the controller's final whole-branch review, then the
`civ-parity-m5` tag per the binding scope split (not done at the wrap —
the tree is left tag-ready and clean).

## 13. Completion note

M5 is complete per spec §5.4: the four criteria gates pass ((a)–(d) above), the
A-B behavior-identity gate is IDENTICAL across the whole milestone window (dump
sha ea35920b unmoved since the M2 gate, diff_lines=0 at the final tree), all
perf budgets met (civ sim tick 0.026–0.029 ms vs the ≤ 2 ms target — ~70×
under; render-prep 0.048–0.054 ms vs ≤ 4 ms; frame window recorded with the
rig caveat), and the full suite is green (49 files / 721 tests / 19548 checks /
0 failures; the 17-entry xvfb sweep all exit 0 with the third BOT_CIV_ALL_OK).
The final whole-branch review (final-review-m5.md — independent; the frozen
CivStage.ts + civEvents.ts read in full, every load-bearing seam re-derived,
all seven rider chains confirmed, the gates re-run LIVE) returned **TAG-READY:
0 Critical / 0 Important**, 3 Minors + 3 Nits ledgered as follow-ups (the
continents 3-of-7 anchor pin, the factory-list first-three order pin, the
probe/sim overlap disclosure — none gate the tag). Milestone arc
e367148..this-commit. Tagged `civ-parity-m5`. Next milestone: M6 = Space
(SpaceStage.ts 52.2K + spaceEvents.ts 2.5K — the §5.4 gates at space flavor;
the largest TS file in the arc; the RID-leak baseline comparison is its first
rider), then M7 = CI/release + repo overwrite.
