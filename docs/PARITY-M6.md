# PRIMORDIA Native — M6 parity checklist (space stage)

Datum: 2026-10-04 · Tag: `space-parity-m6` (wrap + review pending, task 9) · Spec: [`docs/specs/2026-09-29-native-migration-design.md`](specs/2026-09-29-native-migration-design.md) §5.4 (the §5.3 gate shape, space flavor)

**Status: task 8 complete (probes + the RID-leak rider + this list). Remaining:
the task-9 wrap (A-B, perf, ARCHITECTURE/README) and the controller's final
whole-branch review, then the `space-parity-m6` tag.** Every space-stage
feature of the frozen TS build has a native pin. One item is the explicit,
spec-sanctioned deferral (audio synth — the M1/M4/M5 ruling carries); it is
not a space-stage behavior gap.

**Source of truth:** the TS contract (the feature surface of
`Spore/src/game/space/SpaceStage.ts` 1288 lines + `spaceEvents.ts` 77 lines,
both frozen 2026-10-04). Native pins reference `tests/` test methods
(`file::test_name`), scene suites under `tests/scenes/`, the task-8 probes,
and the bot (`tests/bots/bot_space.gd`).

**Headline numbers (task 8, on the probes commit `de4f8b9` + docs):**
headless suite → **55 files, 814 tests, 21989 checks, 0 failures** (54/801/21697
at the task-7 gate + exactly this task's probe file: +1 file, +13 tests, +292
checks). Probes: `tools/probe_space.sh` → **13 tests / 292 checks / 0
failures** (also inside the full suite). Scene suite under xvfb:
`tools/test_space_scene.sh` → **VISUAL_TEST_OK + VISUAL_CHECK_OK, 46
structural asserts over 9 moments, exit 0** (§7). Bot:
`tools/test_bot_space.sh` → BOT_SPACE_ALL_OK ×2 (task 7; not re-run for this
docs/test-only task — no sim file changed). Audio hooks stay no-op with TS
call sites/params pinned (the standing deferral).

Legend: ✅ pinned · ⏸ spec-sanctioned deferral.

## 1. Space sim core — state, system generation, per-planet ecosystems, persist/restore, ship physics (task 1)

| Feature | TS | Native | Test |
|---|---|---|---|
| Constants: ship accel 420, drag exp(−1.1dt), sun r 130 / danger r+60, regen r+150 at +8dt, cargo cap 4, beam 1.4, resurvey cd 4 / +3, planet kind ring fixed, respawn (0,−900) | SpaceStage.ts:55-93, :344-347, :378-389, :1253 | `space_sim.gd` field blocks + seam constants | `test_space_sim.gd::test_constructor_seeding_pins`, `::test_ship_control_keys_and_integration` |
| Constructor: rng from the CALLER (the 5th boot-order branch), chaos scheduler on a SECOND rng.branch() (TS:98), deckSeed = world seed, generateSystem; ship {0,−900, hp 100, angle −π/2, invuln 2}; every state field TS-verbatim (pirates/blackHoles/beamT/finale/ending*/tributeDemand/uiHold/persistT) | TS:25-101 | `space_sim.gd::_init` | `test_space_sim.gd::test_constructor_seeding_pins` (the parallel-branch replay bit-exact + the second-branch state pin); boot-order branch `test_hud_civ.gd::test_boot_order_branch_pin` (exactly-5) |
| generateSystem: 6 planets, kinds ring verbatim (`kinds[i] ?? 'barren'` unreachable), every draw in TS order (orbitR 520+i·380±60 → speciesName → angle → orbitSpeed ±/(1+i·0.12) → r +10 lush → hue by kind → ring chance 0.25); barren → eco null | TS:103-132 | `space_sim.gd::generate_system` | `test_space_sim.gd::test_constructor_seeding_pins`; probe `test_probe_space.gd::test_diet_dial_pulls_closed_form_and_bonus_ordering` |
| makePlanetEco: eco on its OWN rng.branch(); floraCap 140/110/70 by kind, flora 0.7·cap; the DIET DIAL from the world genome's archetype weights (herbW, carnW = carnivore·predator; herbPull/carnPull = min(0.9, max(0,w−1)·0.5 + max(0,1−w)·0.5)); roster n = rng.int(2,4): clone+mutate(0.9), size rng(0.7,1.9), hue ±40, volcanic → carnivore+jaw≥2, ocean → flagella≥3, exactly ONE flip chance per species (the JS &&/else-if short-circuit — a volcanic carnivore CAN flip back); pop rng(4,10); titan/swarm bonus AFTER the roster (dial never touches them) | TS:134-179 | `space_sim.gd::make_planet_eco` | `test_space_sim.gd::test_make_planet_eco_diet_dial_and_bonuses`, `::test_make_planet_eco_neutral_world_flora_caps`; probe `test_probe_space.gd::test_diet_dial_pulls_closed_form_and_bonus_ordering` (closed-form pulls for two extreme worlds at a pinned stream + the volcanic flip-back OBSERVED + the bonus ordering) |
| on_enter: the C1 deck-rebuild gate (world seed ≠ deckSeed → scheduler rebuild + deckSeed update), audio_set_mood, showObjective (the SEED-3-WORLDS line verbatim), the restore whitelist. on_exit → persistColonies | TS:181-190, :270-272 | `space_sim.gd::on_enter/on_exit` | `test_space_sim.gd::test_on_enter_semantics`; scene `test_space_scene.gd::test_on_enter_sets_objective_and_rig_ownership` |
| Restore whitelist: EVERY guard — parse-null = the TS catch; shapesOk (typeof-object admits ARRAY rows; the gate stays open, an array row reads undefined); the length gate; num(v, min) type-check-then-float strict > min, NO max (hue 2000 restores); per-field r/orbitR/orbitSpeed/angle/hue/name/kind/ring; colony/scanned ride the whitelist (the 12-reports fix); eco instanceof → null + ALWAYS-take-saved + the colonist rebuild; cargo clamp merge (junk dropped, defaults, 'specimen'); the ledger + ending blocks nest INSIDE the shapes gate (a corrupt blob discards the WHOLE restore — the T1-review AST fact) | TS:190-267 | `space_sim.gd::_restore_world` | `test_space_sim.gd::test_restore_whitelist_field_guards`, `::test_restore_eco_always_taken_and_colonist_rebuild`, `::test_restore_cargo_clamp_merge`, `::test_restore_ledger_and_ending_inside_the_gate`; E2E `test_world_creature_pins.gd::test_space_save_continue_restores_system`, `::test_space_stale_blob_guards_e2e`, `::test_space_corrupt_r_guard_e2e` |
| persistColonies: the full world blob (per-planet id/name/orbit/geometry/kind/ring/scanned/colony/eco-toJSON, no x/y) + cargo + abductCount + endingDone/Dismissed → flags.spaceWorld; persistState = the saveAll splice-rollback seam | TS:274-297 | `space_sim.gd::persist_colonies/persist_state` | `test_space_sim.gd::test_persist_shape_and_roundtrip`; E2E `test_hud_space.gd::test_save_all_chain_and_on_exit_persist` |
| Ship control: cursor thrust (20 deadzone strict) + WASD/arrows, normalize, shipAngle atan2; accel 420, drag exp(−1.1dt), integrate | TS:327-351 | `space_sim.gd::update` | `test_space_sim.gd::test_ship_control_keys_and_integration`; scene `test_space_scene.gd::test_snapshot_wasd_thrust_reaches_the_sim` |
| Engine particles: thrust-gated chance(dt·40) — an idle frame draws NOTHING from the stage stream; back-of-ship spawn, hsl(200,1,0.7) CSS-string color | TS:352-361 | `space_sim.gd::update` | `test_space_sim.gd::test_engine_particles` (the forced-spawn payload pins + the stream cadence) |
| ff block: timeScale PRE-reads ffHold (:306 before the :307 decay — the first held frame ×1, the post-release frame still ×26); ONE ecoModsFromWorld snapshot feeds EVERY planet eco per frame (the wire that makes world-trait effects real); eco.tick(dt·ts); extinctions → ctx.bump_extinction + colony-gated toast; speciations → scanned-gated toast; generations += dt·ts/30 | TS:306-325 | `space_sim.gd::update` | `test_space_sim.gd::test_ff_timescale_and_wiring`, `::test_ff_e2e_real_eco_and_persist_cadence`; probe `test_probe_space.gd::test_ff_generations_and_eco_mods_wire_through_real_eco` (a growth_mult world trait observed through a REAL planet eco vs a probe-controlled twin at scale + the generations composition) |
| Orbits + colony logistic growth: angle += orbitSpeed·dt·(ff?0.4:1) (the ×0.4 POST-reads ffHold); pop += dt·ts·0.08·(1+pop·0.01)·max(0, 1−pop/120) — the cap-120 brake | TS:363-374 | `space_sim.gd::update` | `test_space_sim.gd::test_orbit_and_colony_growth`; probe `test_probe_space.gd::test_colony_logistic_brake_exact_over_330_frames` (the 331-frame composed recurrence across four drive phases incl. the post-release ×26 growth frame; 200 ff frames asymptote UNDER 120, never crossing) |
| Sun danger + hull regen: d < r+60 strict && invuln ≤ 0 → shp −30dt + hurtT + shake 4/0.2; regen: colony pop ≥ 5 && d < r+150 strict → min(shpMax, +8dt) — NO invuln gate | TS:376-389 | `space_sim.gd::update` | `test_space_sim.gd::test_sun_danger_and_hull_regen`; probe `test_probe_space.gd::test_sun_danger_and_regen_windows_composed` (both windows COMPOSED on one 240-frame hull curve incl. the invuln crossover: +8dt shielded then −22dt net) |
| Debug seams: debug_state (the read surface) + debug_seed_colonies (TS:1275-1287 — first three non-barren uncolonized in planet ORDER, the docstring's 'nearest' is wrong, pinned as coded) | — (native seam, documented in the header) | `space_sim.gd` tail | `test_space_sim.gd::test_debug_seams`, `::test_debug_state_part2_fields`; the bot-law audit in task-7-review.md |

## 2. Space sim core part 2 — interactions, gene lab, hazards, finale (task 2)

| Feature | TS | Native | Test |
|---|---|---|---|
| Panel dispatch: near-planet gate (d < r+130); hover pointer BEFORE any click; even a DISABLED button owns its click (no thrust fall-through); the first inside rect dispatches and stops; uiHold written ONLY on click frames, cleared on !isDown; panel clicks outrank pirate shooting (the block order) | TS:391-434 | `space_sim.gd::update` | `test_space_sim.gd::test_panel_dispatch_ladder`; scene `test_space_scene.gd::test_panel_rects_write_back_and_dispatch`, `::test_take_click_mirror_and_freshness` |
| Black holes: pull 24000/max(80,d) inside d < 600 strict (the 0.001 guard), damage −60dt inside d < 40 strict; drift + ttl UNGATED; the ttl filter; spawn: ring 1000, vx/vy rng(−12,12), ttl 45 | TS:436-452, :840-849 | `space_sim.gd::update/spawn_black_hole` | `test_space_sim.gd::test_black_holes`; probe `test_probe_space.gd::test_black_hole_pull_integration_and_cull_on_death` (the pull integrated over the ship's own drag for 20 frames from d 500 + the d-79 clamp; death-by-hole → the killer CULLED) |
| Pirates: spawn (5 cap, ring 700, hp 140, ttl 40, ONE alarm); chase: d > 30 → v += dir·300·dt, drag exp(−1.4dt), integrate, gait; the ttl `?? 40` fallback; damage window d < 60 && invuln ≤ 0 && !lull → −14dt + hurtT 0.5 + chance(dt·6) burst; click-to-shoot the pirate you clicked (clickD < 60 strict): hp −34, hp ≤ 0 → splice + toast + addDna(30) + the 20-particle death burst | TS:454-498, :794-810 | `space_sim.gd::update/spawn_pirates` | `test_space_sim.gd::test_pirates_lifecycle`; probe `test_probe_space.gd::test_pirate_chase_damage_math_at_scale` (the 120-frame composed chase recursion with the burst draws replayed; 34×5 click kill +30 DNA) |
| tryAbduct/finishAbduct: gates IN ORDER beamT (silent) → distance FIRST (the wrong-lesson comment) → cargo-4 → eco-null → living-empty; the beam arms with NO stage draw (beamT 1.4, NOT clamped on the countdown — lands negative); finish: candidates filter pop ≥ 1 (the infinite-DNA-faucet pin), rng.pick, pop −1, the 10/3 pay ledger keyed '{p.id}:{sp.id}', the LAST member → pop 0 + extinct + bump_extinction + the gone-from-this-world toast (counted HERE, never through eco.tick), cargo push, discover, the flush (the 60s-autosave lag) | TS:500-507, :644-707 | `space_sim.gd::try_abduct/finish_abduct` | `test_space_sim.gd::test_try_abduct_gates_and_ledger`; probe `test_probe_space.gd::test_abduct_pay_curve_ledger_at_scale` (five catches derived catch-by-catch from the cloned-stream picks across two species + the cross-planet key separation + the pop-1 extinction leg) |
| seedNearest: distance gate, spend 20, cargo pop_back, barren → lush + fresh eco (floraCap 60/100, flora 0.6·cap), addSpecies kin, colony ?? keeps an existing one, the SEEDED banner, persist | TS:709-733 | `space_sim.gd::seed_nearest` | `test_space_sim.gd::test_seed_nearest`; E2E `test_world_creature_pins.gd` (the seeded colony rides the round-trip) |
| mergeCargo: cargo < 2 gate, spend 15 (the AFK-faucet pin), crossover(a, b, rng, 0.3, {anomalyChance 0.15 wild/0.10, defectRate 0.3 wild/0.2, bias rate_add, info}) — the TOTAL per-splice budget, slice(2) + append, the info toasts in TS order, discover(kin false), the graft, persist | TS:735-770 | `space_sim.gd::merge_cargo` | `test_space_sim.gd::test_merge_cargo_pinned_stream` (the bit-exact replay + the wild divergence scan + the rate_add pair); probe `test_probe_space.gd::test_crossover_opts_wild_vs_normal_rate_add_chains` (three world-CONTROLLED 24-merge chains on cloned streams; the anomaly/defect fire counts derived from the replays match the real toasts) |
| borrowedFleshGraft: the combo guard precedes the shuffle (no draw when off); the once-per-run flag `=== true`; the shuffled extinct lineages; standout_part null → continue; a graft NEVER downgrades (raised ≤ cur → the next lineage); the graft write + flag + toast | TS:772-792 | `space_sim.gd::borrowed_flesh_graft` | `test_space_sim.gd::test_borrowed_flesh_graft`; probe `test_probe_space.gd::test_graft_never_downgrade_and_flag_in_splice_chain` (the visit-order-dependent outcome inside a real two-merge splice chain; the flag silences the second shuffle) |
| Tribute: demandTribute (60, the danger banner ttl 8, alarm); payTribute (the V key, dna ≥ demand → deduct + zero, else the raid-is-coming toast) | TS:514-517, :851-870 | `space_sim.gd::demand_tribute/pay_tribute` | `test_space_sim.gd::test_keys_and_tribute` |
| Chaos ctx WITH onEnd (the civ wiring lacks it): gapMult = chaosGapMult·gapBias, mood, warnScale; onWarn (effective_warn → danger banner ttl 2.4 + alarm 0.5); onApply (banner + addChaos 0.03 + the storyteller note); onEnd — THE TRIBUTE RULE: an UNPAID demand ends in spawnPirates(3) + the demand zeroed (the deck/ctx split — the def carries no end) | TS:519-548 | `space_sim.gd::update_chaos` | `test_space_sim.gd::test_chaos_ctx_and_on_end`; `test_space_events.gd::test_live_tribute_demand_pay_and_onend_raid`; probe `test_probe_space.gd::test_tribute_onend_unpaid_raid_through_real_update` (the whole timeline through the REAL update loop — the raid spawns IN the real frame, the pirates idle until the next frame's chase) |
| Finale/ending: the trigger (thriving ≥ 3 && !finale && !endingDone → the core at (0,−1900) + the AWAKENS banner + the per-frame bearing objective); the approach d < 60 → endingDone + the win flush immediately; endingT += dt; the dismiss (any unconsumed click/key → endingDismissed, dismissT = endingT — the += precedes the latch); endingDone blocks re-trigger/re-flip | TS:552-582 | `space_sim.gd::update` | `test_space_sim.gd::test_finale_and_ending`; E2E `test_hud_space.gd::test_ending_won_run_stays_won_continue`, `::test_ending_dismissed_sleeps_continue`; probe `test_probe_space.gd::test_finale_trigger_and_ending_fade_windows` (the trigger frame derived from the growth recurrence; the fade windows composed at the SIM's own endingT/dismissT timeline) |
| Ship death: shp ≤ 0 → respawn (0,−900) at shpMax·0.5; lost = endingDone ? 0 : round(dna·0.15) (the no-bill post-ending); cargo SURVIVES (the blocking-seeding pin); the black-hole cull radius 700 strict > (must exceed the 600 pull radius); pirates cleared; invuln 4 | TS:584-602 | `space_sim.gd::update` | `test_space_sim.gd::test_ship_death`; probe `test_probe_space.gd::test_black_hole_pull_integration_and_cull_on_death` (death-by-hole → the killer culled), `::test_ship_death_compound_curve_and_post_ending` (the four-death compound −15% curve 1000 → 850 → 722 → 614 → 522 with every round() step derived; the post-ending twin bills 0) |
| Cooldowns + the persist cadence: invuln/hurtT decays; persistT > 5 strict → persistColonies + reset | TS:604-613 | `space_sim.gd::update` | `test_space_sim.gd::test_ff_e2e_real_eco_and_persist_cadence`; scene `test_hud_space.gd::test_cadence_persists_without_save` |
| scanPlanet/repairHull: the fresh scan discovers every living species + pays 15 (the pacifist income); the lifeless branch still plays the dna audio; the RE-SURVEY trickle: cd 4, +3, the floatWorld text, persist — cooled by resurveyCd (the ~720 DNA/min mash pin) | TS:1233-1272 | `space_sim.gd::scan_planet/repair_hull` | `test_space_sim.gd::test_scan_and_repair`; probe `test_probe_space.gd::test_resurvey_cadence_cd4_plus3` (three cycles at the 0.5 s grain: the pay fires land EXACTLY every 4.0 s, +3 per cycle, the gated scans counted) |

## 3. Space chaos deck + scheduler wiring (task 3)

| Feature | TS | Native | Test |
|---|---|---|---|
| Baseline 4 defs verbatim: pirates 0.7+chaos, dur [30,30] cd 55, the ONE Math.random site (the count 2+floor(rng·2)) riding the scheduler's deck rng; blackhole 0.5+chaos·0.8 [45,45] cd 90; flare 0.6 [0.1,0.1] cd 60; tribute 0.5+max(0,−karma)·0.7 [12,12] cd 100 — the def DEMANDS only, no end (the deck/ctx split) | spaceEvents.ts:10-47 | `space_events.gd::_baseline` | `test_space_events.gd::test_traitless_deck_is_four_defs`, `::test_def_constants_verbatim`, `::test_weight_formulas`, `::test_pirate_count_draw_in_stream`, `::test_pirate_count_live_through_the_real_scheduler` |
| World-gated variants: nebula_flip (mutation_moon — two forced speciations on ONE rng.pick'd living world; both force calls always run); pirate_lull (calm_veil — begin sets pirateLull, END clears it — the space deck's first end hook) | spaceEvents.ts:49-77 | `space_events.gd::_nebula_flip/_pirate_lull` | `test_space_events.gd::test_gated_defs_gate_on_the_world`, `::test_nebula_flip_body`, `::test_nebula_flip_dead_rock_and_made_zero`, `::test_pirate_lull_begin_end_body`, `::test_pirate_lull_holds_fire` |
| The factory draws NOTHING from any rng stream (the gates fold at build time — the M5 draw-nothing ruling) | spaceEvents.ts:49 | `space_events.gd::make_space_chaos_events` | `test_space_events.gd::test_deck_factory_draws_nothing` |
| Sim holds the deck + the C1 rebuild gate; update drives the real deck (warn/apply banners + alarm through the hooks) | TS:98, :182-186, :519-548 | `space_sim.gd::_make_deck/on_enter/update_chaos` | `test_space_events.gd::test_sim_holds_deck_and_c1_rebuild`, `::test_update_drives_the_real_deck`, `::test_blackhole_apply_routes`, `::test_solar_flare_body` |
| solarFlare: hull max(10, −20), hurtT, shake 7/0.8, the toast, every living pop max(0.5, ·0.7) | TS:872-884 | `space_sim.gd::solar_flare` | `test_space_events.gd::test_solar_flare_body` |

## 4. Space stage scene — world render (task 4)

| Feature | TS | Native | Test |
|---|---|---|---|
| Draw order: sky (backdrop, seed 42) → world (sun discs → orbit arcs → planets (radial body + the OFFSET shadow gradient + rings) → the finale orb → pirates → black holes (core + the 2→90 purple profile + the rotating arc) → the beam line) + the beam specimen item → ship (hull + both fx pools) | TS:885-1014 | `space_stage.gd::_draw_sky/_draw_world/_draw_planet/_draw_finale/_draw_pirate/_draw_ship_layer` | scene moments §7 (system/pirates/blackhole/beam); `test_space_scene.gd::test_hooks_bind_all_sim_keys`, `::test_fx_hooks_feed_the_stage_pool` |
| Static seams (the draw-time math pinned headless): planet_shadow_col (the offset-light gradient), beam_quad (the vertex-quad ramp), hull_points (the 4-point pirate hull), ship_visible (not ending_done or dismissed), panel_frame/panel_button_rect (w 250 at vw−w−20, h 290/252), ending_alpha (min(1, endingT/2) in / max(0, 1−(endingT−dismissT)/1.5) out) | TS:928-958, :1000-1014, :1052-1080, :1083-1122, :1195-1231 | `space_stage.gd` statics | `test_space_scene.gd::test_planet_shadow_seam_ladder`, `::test_beam_quad_seam`, `::test_ship_hull_seam`, `::test_ship_visibility_rule`, `::test_ending_fade_windows`; probe `test_probe_space.gd::test_finale_trigger_and_ending_fade_windows` (the statics composed at the SIM's real timeline) |
| Hook bindings: all 17 sim keys (hud_toast/banner/objective/float/set_abilities, audio noop ×2 with the TS call sites pinned, cam_shake, fx_spawn/fx_burst, set_cursor, the storyteller triple, note_chaos_event, go_to/save_all) | — (native wiring) | `space_stage.gd::_build_hooks/_h_*` | `test_space_scene.gd::test_hooks_bind_all_sim_keys` (every key a Callable + the storyteller LIVE values) |
| Camera feed: follow(sx, sy, dt, 5) + zoom 0.85 (the SPACE constants) + the toWorld feed for NEXT frame; the fx pool steps after sim.update (the cell_sim precedent) | TS:616-623 | `space_stage.gd::update` | `test_space_scene.gd::test_camera_feed_numbers`, `::test_fx_hooks_feed_the_stage_pool` |
| The stage rng branch: the CALLER draws ctx.rng.branch() in _ready (the 5th boot-order branch) | TS:96-97 | `space_stage.gd::_ready` | `test_space_scene.gd::test_on_enter_sets_objective_and_rig_ownership`; the exactly-5 pin `test_hud_civ.gd::test_boot_order_branch_pin` |

## 5. Space stage scene — screen layer, panel, ending (task 5)

| Feature | TS | Native | Test |
|---|---|---|---|
| Screen layer: the colonies chip (🏳 N colonies · ★ k/3 thriving, green 0 vs gold 3), the ff tint (0.06 purple veil + the EVOLUTION ACCELERATING label), vignette, hull bar, the cargo panel (4 clipped slots — creature vs cell pixels by genome kind), the planet panel (the frame + 6 buttons enabled-blue vs disabled-grey + the labels), the ending overlay (the 0.86 veil, THE CHAOS CORE ACCEPTS YOU, the stat lines, the gold sandbox line, the dim keys line) | TS:1027-1122, :1195-1231 | `space_stage.gd::_draw_ui_layer/_draw_panel_layer/_draw_planet_panel/_draw_ending` + CargoSlot clip subtrees | scene moments §7 (cargo/panel/ff/chip/ending — 23 of the 46 asserts); the beam creature-vs-cell dispatch `test_space_scene.gd::test_beam_dispatch_creature_vs_cell` |
| panel_rects write-back: the stage writes sim.panel_rects EVERY frame before update (the T2/T5 cross-task interface); the sim only reads | TS:1192-1193 | `space_stage.gd::render` | `test_space_scene.gd::test_panel_rects_write_back_and_dispatch`; sim-side `test_space_sim.gd::test_panel_dispatch_ladder` |
| The ending veil math: ending_alpha reads endingT−dismissT (the dismissed-restore veil shows ~1.5 s after a dismissed CONTINUE — TS-verbatim, noted for the record) | TS:1083-1122 | `space_stage.gd::ending_alpha/_draw_ending` | `test_space_scene.gd::test_ending_fade_windows` (the 2 s in / 1.5 s out windows); probe `test_probe_space.gd::test_finale_trigger_and_ending_fade_windows` |
| The abilities payload: ONE list per update (R/F/G/LMB with the active flags) bridged to the hud | TS:626-631 | `space_stage.gd::_h_hud_set_abilities` | `test_space_sim.gd` (the payload pins) + `test_space_scene.gd::test_abilities_payload_per_frame` |
| Frozen seam + render guards pre/post restore | — (native test seam) | `space_stage.frozen` | `test_space_scene.gd::test_frozen_seam_holds_the_sim`, `::test_render_guards_pre_and_post_restore` |

## 6. Wiring — registration, civ handoff, spaceWorld save/continue, i18n (task 6)

| Feature | TS | Native | Test |
|---|---|---|---|
| Registration in BOTH lists (boot register + the resetStagesForNewRun factory), boot order cell → creature → tribe → civ → space (TS main.ts:33-39); the boot registry starts HIDDEN (the register-hide fix: the last-registered stage's opaque one-shot boot draw blacked out CONTINUE landings — proven TS-verbatim at the T6 review) | TS main.ts | `src/main.gd:32-36` + `src/game/game.gd::register` | `test_hud_civ.gd::test_main_registers_civ_stage` (grows to the space preload/register pins + the factory tail), `::test_boot_order_branch_pin` (exactly-5) |
| Civ → space landing: the REAL victory card lands the REGISTERED SpaceStage (the objective, the 6-planet kind ring, the C1 no-op, no inset); the brick-hardening CONTINUE lands space | TS:289-296, :123-128 | `game.gd::switch_stage` + `space_stage.on_enter` | `test_hud_civ.gd::test_victory_lands_registered_space`, `::test_brick_hardening_continue_auto_space` |
| spaceWorld save/continue E2E: the round-trip as it stood; the C1 deck rebuild on a new world; the stale-blob whole-restore discard; the corrupt-r per-field guard | TS:190-267 | `game.gd` persist seam + `space_sim._restore_world` | `test_world_creature_pins.gd::test_space_save_continue_restores_system`, `::test_space_continue_rebuilds_deck_on_new_world`, `::test_space_stale_blob_guards_e2e`, `::test_space_corrupt_r_guard_e2e` |
| The ending E2E: won-run-stays-won (the finale orb restored, no AWAKENS replay); dismissed-sleeps (finale null); the cadence persists without save_all; the toast-inset default (space arms NO inset — the civ 150 contrast) | TS:256-267, :609-613 | `space_stage.on_enter` + `game.gd` | `test_hud_space.gd` (8 tests: `test_direct_landing_and_constructor_system`, `test_ending_won_run_stays_won_continue`, `test_ending_dismissed_sleeps_continue`, `test_cadence_persists_without_save`, `test_toast_inset_default_on_switch`, `test_objective_bearing_rewrites_through_hud`, …) |
| i18n: the TS VI object's space strings 1:1 in vi.csv (53 t() sites + the raw-emit VI members + the normative absences) | TS VI object | `assets/i18n/vi.csv` | `test_hud_space.gd::test_space_i18n_mapping_1to1` (90 checks) |

## 7. Bot arc + determinism (the §5.4(b) gate — task 7)

| Feature | Native pin | Status |
|---|---|---|
| The full arc through the REAL input pipeline (bot law audited 1:1 — the only sim call is `debug_seed_colonies`, the documented cheat): the civ bot's real victory lands space → the constructor system read → the REAL R-key abducts through the beam path (cargo/ledger/DNA reconciliation exact) → the gene splice (G) → seeding → the REAL KeyF ff grows the colonies → the finale trigger → the core approach → endingDone → the ending card + the sandbox hand-back; the 62-key end fingerprint field-identical across all six walks (3 invocations ×2-pass) | scene `test_bot_space.gd` → BOT_SPACE_ALL_OK ×2 (the gate as briefed; the wall-clock 725s/733s) — `tools/test_bot_space.sh` | ✅ |
| Same seed → same run path: the 62-key fingerprint stage-named + exact; the sweep trace cadence 600; the station/hazard vectors pure field math; the nearest-living scan mirrors the abduct filter; the bot-law audit (the sim call surface is exactly the debug cheat) | `test_bot_space_pins.gd` (6 tests: `test_bot_composition_shares_one_lcg_stream`, `::test_space_fingerprint_is_stage_named_and_exact`, `::test_nearest_living_scan_mirrors_the_station_target`, `::test_station_and_hazard_vectors_are_pure_field_math`, `::test_sweep_trace_cadence_is_600`, `::test_bot_law_audit_the_sim_call_surface_is_the_debug_cheat`) | ✅ |

## 8. Probes (§5.4(c) — task 8)

`tests/test_probe_space.gd` (13 tests / 292 checks) + the one-command headless
entry `tools/probe_space.sh` (the targeted `tests/probe_runner.gd` runner; the
file also joins the full suite). Each probe boots the full Game + the REAL
SpaceStage out-of-tree (the M4/M5 probe shape) and drives the REAL sim through
its documented input-SNAPSHOT contract; formulas cited to the frozen TS lines
in each probe's provenance comment. Independent derivations: closed-form TS
formulas composed probe-side (the diet pulls, the colony recurrence, the
pirate chase recursion, the black-hole integration, the compound death curve),
draw-dependent pins replayed on CLONED streams (`Rng.new_from(sim.rng.state())`
— never the sim's own code), the eco-mods twin replayed at the ECO level, and
real-scheduler timelines through the REAL update loop. Seeds
0x5CAC1-0x5CACD. The red-check (a deliberately corrupted derivation — the
diet pull — fails loudly: 5 failures incl. 4 planets' diet matches) is
recorded here; the corruption was reverted before commit. Complement: the
unit suite (§1-§2) pins every mechanism at single-frame level — the probes add
the formula-at-scale derivations, stated per probe:

| Probe | Pins |
|---|---|
| diet dial | herbPull/carnPull closed-form for two crafted worlds (0.9/0.0 and 0.0/0.9, TS:147-148); every roster diet at 0x5CAC1 matches the probe's own constructor replay built FROM those pull values; the volcanic carnivore→herbivore flip-back OBSERVED (the short-circuit, TS:157-158); titan/swarm LAST with diet/size untouched (TS:161-177) |
| abduct ledger | five catches through the REAL beam path derived catch-by-catch from the cloned-stream picks (the 10/3 pay per '{planet}:{species}' key, TS:684-689), pops tracked to any derived extinction (bump_extinction HERE, TS:690-697); the cross-planet key separation (the same genome on planet 2 pays 10 again); the pop-1 last-member leg + no re-farm |
| colony brake | the logistic recurrence composed over 331 frames across four drive phases — normal DT, ff-hold ×26, the POST-RELEASE ×26 growth frame (the TS:306 pre-read quirk observed in the growth), the 200-frame soak — bit-exact at every checkpoint; the cap-120 brake exact (the soak asymptotes UNDER 120, never crossing) |
| ff + eco.mods | generations = Σ dt·ts/30 over the 40-frame ff window (TS:323); the eco.mods WIRE through a REAL planet eco: growth_mult 1.5 vs a traitless control at the same seed — each sim's eco matches a probe-controlled twin eco bit-exact per table and the tables DIVERGE (the trait is real, TS:309-315) |
| crossover opts | three world-CONTROLLED 24-merge chains on cloned streams (normal 0.10/0.2, wild 0.15/0.3, rate_add 0.5): every 24th child bit-exact, the anomaly/defect fire counts derived from the replays equal the real toasts (normal 2/24 + 5/24; wild 4/24 anomalies; rate_add 6/24 defects — the exact counts are the pins) |
| graft | the never-downgrade skip inside a real two-merge splice chain: the shuffle visit order derived from the clone (the cannot-raise lineage passed, the giver grafts — the derived GRAFTED child bit-exact), the SECOND merge draws NO shuffle (the once-per-run flag, TS:778-788) |
| pirate math | the chase recursion composed over 120 frames at DT (accel 300 while d > 30, drag exp(−1.4dt), integration, the −14dt window with the chance(dt·6) burst draws replayed) — bit-exact; the kill: 34×5 → dead +30 DNA with both bursts' draws replayed (TS:466-497) |
| black hole | the pull 24000/max(80,d) integrated over 20 frames from d 500 with the ship's own drag exp(−1.1dt) composed — bit-exact; the d-79 clamp (24000/80); death-by-hole → the killer CULLED at the respawn (700 strict >, the d-700 edge culled, d 750 kept) |
| ship death | the compound −15% curve: four deaths from 1000 DNA derived (150/128/108/92 — each applies to the ROUNDED remainder), cargo surviving each; the post-ending twin bills 0 four times (TS:584-602) |
| tribute raid | through the REAL update loop with a single-def tribute deck: warn → demand 60 (the banner through the REAL hud) → the UNPAID end spawns 3 pirates IN the real frame (the ctx onEnd, TS:539-547) → the first chase frame derived for all three (the chaos block runs AFTER the pirate loop — the spawn-frame idle pinned) |
| sun + regen | both windows COMPOSED on one 240-frame hull curve: the ship inside the sun window AND a thriving colony's regen window — the invuln crossover derived (regen has NO invuln gate: +8dt shielded, −22dt net after — the FP crossover lands 121 shielded + 119 drained frames, pinned) |
| finale + fade | three colonies grown through the REAL ff to the trigger (the trigger frame derived from the growth recurrence — the pre-read makes it frame 2); the AWAKENS banner + the bearing through the REAL hud; the fade windows (2 s in / 1.5 s out) composed at the SIM's own endingT/dismissT timeline vs the stage's static seam |
| resurvey | the cadence at scale: three cycles at the 0.5 s grain — the pay fires land EXACTLY every 4.0 s (the 8th half-step zeroes the cd), +3 per cycle (9 total), 7 gated scans per cycle counted through the REAL hud |

## 9. Visual moments (§5.4(d) pixel-assert — the task-5 inventory, counted honestly)

scene `tests/scenes/test_space_scene.gd` + `tools/visual_check_space_scene.py`
(xvfb + Compatibility renderer, llvmpipe-deterministic; probes.json carries
the live anchors re-derived from the stage's own geometry seams — no copies).
Freeze discipline: sim-state gates only, NO engine-frame counts (the M3
volcano lesson). The task-8 brief's visual inventory IS the task-5 suite —
the shared coverage is counted here verbatim (re-run for this task:
VISUAL_TEST_OK + VISUAL_CHECK_OK, exit 0). **9 moments / 46 structural
asserts** — the moment inventory found no < 3-assert moment, so no
probe-side additions were needed and none were duplicated:

| Moment | Asserts |
|---|---|
| System view (the warm sun discs, the 3 kind-dominant planet discs with the OFFSET shadow gradient, the faint orbit arc vs its control, planet 1's ring stroke) | 9 |
| Planet panel (the dark frame, the enabled-blue vs disabled-grey fills, the hull-fraction label vs the white enabled label) | 6 |
| Black hole (the black core, the purple radial profile with the 37.2 mid-stop band, the rotating arc vs its control) | 6 |
| Pirates (the r-dominant 4-point hulls, the ☠ markers, the red glow lift) | 5 |
| Ending overlay (the 0.86 veil over the sun, THE CHAOS CORE ACCEPTS YOU purple title, the stat lines, the gold sandbox line, the dim keys line) | 5 |
| Fast-forward tint (the 0.06 purple veil blue-shifted twin diff, the EVOLUTION ACCELERATING label) | 4 |
| Cargo bar (creature pixels in slot 0, cell pixels in slot 1, the empty slot 3) | 4 |
| Beam (the blue beam line with the ship-end-brighter gradient, the off-line control, the rising creature's green body) | 4 |
| Colonies chip (the green 0-colony label vs the gold 3-thriving label, text changed) | 3 |

## 10. Explicit deferrals (spec-sanctioned; none is a space-stage behavior gap)

| Item | Reason |
|---|---|
| Audio synth (WebAudio → AudioStreamGenerator) | Migration spec §7 risk-table item — the M1 ruling carries through M5; every space audio site is a no-op hook with the TS call site/params pinned in a comment (`audio_set_mood`, warp/dna/zap/boom/hit/alarm/levelup/heal/click/ascend). Its own task after parity. |

## 11. The exit RID-leak baseline comparison (the M5 ledger's MANDATORY first rider — task 8)

The M5 ledger (civ SDD progress.md + PARITY-M5 §9): full-suite exit warnings
grew 152 leaked CanvasItem RIDs (the M4 baseline) → 215 (with the civ painter
teardown pattern); the civ files construct zero nodes; the comparison was
RULED to M6. THIS task ran it — ONE clean-baseline pair, single instance,
strictly sequential. Capture basis: the M5 runner is single-pass (its exit
warnings print to its stderr); the M6 runner is the two-pass guard (the T1
upgrade) — the worker's stderr is captured and relayed to stdout, so the
warning lines are read from the relay. Either way the number is ONE suite
execution's exit telemetry — comparable:

| Run | Tree | Command | Suite result | Exit leak telemetry |
|---|---|---|---|---|
| Baseline | `civ-parity-m5` (af22996) in a TEMP worktree (`/tmp/m6-ridbase`, import cache warmed by a separate `--import` pass first — the capture run is clean) | `godot --headless -s res://tests/run.gd --path .` | 49 files / 721 tests / 19548 checks / 0 failures, exit 0 | **`WARNING: 215 RIDs of type "CanvasItem" were leaked.`** + 1× ObjectDB instances leaked + 1× Resources still in use + the known fixture noise (4× deliberate JSON-parse errors, 2× the headless drawing notice, 1× Rng.pick empty array, 1× Rng.weighted empty entries) |
| HEAD | this task's committed tree | idem | 55 files / 814 tests / 21989 checks / 0 failures, exit 0, script-error guard 0 | **`WARNING: 403 RIDs of type "CanvasItem" were leaked.`** + 1× ObjectDB instances leaked + 1× Resources still in use (+ the same fixture-noise families; stderr itself empty — the relay note above) |

**Verdict: the FAMILY is pinned pre-existing; the DELTA is the space TEST
surface's out-of-tree boots (the same teardown pattern, attributed).** The
family predates space entirely (152 at M4, before any civ/space file existed)
and reproduced at the baseline exactly as the M5 ledger pinned it (215). The
space milestone's +188 tracks the space test files' out-of-tree stage/hud
boots — the same pattern that took 152 → 215 at civ (+63 with the civ test
surface): every space test file boots real Games + stages + hud instances
out-of-tree, whose CanvasItems tear down only at the forced process exit
whenever a boot's teardown is missed. The MECHANISM is pinned empirically at
the probe level: a probe run whose bodies all complete frees every boot via
the `_drop` discipline and leaks ZERO CanvasItem RIDs (verified across three
consecutive `tools/probe_space.sh`-equivalent runs — ObjectDB/Resources
cycle noise only), while earlier runs of the same file whose bodies aborted
mid-way (the red-fix iterations' script errors) leaked 17-51 RIDs — the
aborted boot's stage canvases never reach `free()`. The RID count is
therefore the count of UN-FREED out-of-tree boots at exit, not a runtime
leak in any sim/stage file: the space sim is node-free
(RefCounted/Dictionaries — the M5 ruling's civ precedent, unchanged for
space) and the stage's canvases free with their Game. Owner: the
long-standing out-of-tree scene-test teardown family — not a sim or stage
behavior gap; carried as known noise (the M7 CI gate may assert a ceiling
rather than zero). Worktree removed after the capture.

## 12. M7 deferred (recorded at task 8)

| Item | Provenance |
|---|---|
| M7 = CI/release + the repo overwrite (the goal's terminal step — the old GitHub repo gets replaced per spec §5; plan to be written fresh) | the M6 plan's Completion section |
| Audio core (the synth port) | standing deferral §10 — its own task after parity |
| The M5 final-review ledgered minors, carried: the continents 3-of-7 anchor pin; the factory-list first-three order pin; the probe/sim overlap disclosure | final-review-m5.md (3 Minors + 3 Nits — none gate the tag) |
| The dismissed-restore veil note: a dismissed ending's CONTINUE shows the veil ~1.5 s before it fades (the endingT−dismissT restore math — TS-verbatim, disclosed at task 6) | task-6-report.md concern 2 |
| The creature painter `update_ents` hot-loop optimization (2 ms target) | M3 §16 carry-forward — still open |
| T10 moment pin-gaps ×2 (editor preview body, sun/moon disc) | M3 §17 carry-forward — cheap probe candidates |

## §5.4 criteria checklist

| Criterion | Evidence pointer | Verdict |
|---|---|---|
| (a) Every TS space feature present | §1–§6 — every row pinned or explicitly deferred with a spec citation (audio synth only, spec-sanctioned: §10) | ✅ |
| (b) Bot headless full space arc through the real UI, ×determinism | `tools/test_bot_space.sh` → BOT_SPACE_ALL_OK ×2, six walks across three invocations → ONE end state (the 62-key fingerprint identical; §7) — re-run at the task-9 wrap per the sweep | ✅ |
| (c) Econ probes TS-verbatim | `tools/probe_space.sh` → **13 tests / 292 checks / 0 failures** (§8; formulas cited to the frozen TS lines in each probe's provenance comment; cloned-stream + composed-recurrence + twin-eco derivations at pinned seeds 0x5CAC1-0x5CACD; the red-check recorded); also inside the full headless suite | ✅ |
| (d) Pixel-assert suite, space moments | the space scene suite under xvfb (**46 structural asserts over 9 moments**, `tools/visual_check_space_scene.py`, §9) — every moment ≥ 3 PIL-checked structural asserts over a live viewport capture | ✅ |
| Full suite green | headless suite → **55 files / 814 tests / 21989 checks / 0 failures** (the headline numbers, captured on this task's tree; the docs commit is docs-only — the task-8 verify re-runs the gate on the final committed tree and the task-9 wrap re-verifies again) | ✅ |
| A-B behavior-identity + perf budgets | the task-9 wrap: `tools/ab_test.sh civ-parity-m5` (the standing cell dump must not move — space is additive, the 5th boot branch joins the replay pin) + the split perf metrics (sim tick ≤ 2 ms at 6 planets, ff-hold AND normal rows; render ≤ 4 ms; the frame window recorded) | task-9 (the wrap's gate) |
