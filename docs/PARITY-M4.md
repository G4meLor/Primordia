# PRIMORDIA Native — M4 parity checklist (tribe stage)

Datum: 2026-10-01 · Tag: `tribe-parity-m4` (task-8 wrap) · Spec: [`docs/specs/2026-09-29-native-migration-design.md`](specs/2026-09-29-native-migration-design.md) §5.4 (the §5.3 gate shape, tribe flavor)

**Status: feature-complete through task 8 (the wrap — A-B, perf, docs);
final whole-branch review + the `tribe-parity-m4` tag are controller scope.**
Every tribe-stage feature of the frozen TS build has a native pin. Two items
are explicit, spec-sanctioned deferrals (audio synth — the M1 ruling carries;
the civ-stage landing — M5 scope); neither is a tribe-stage behavior gap.

**Source of truth:** the TS contract (the feature surface of
`Spore/src/game/tribe/TribeStage.ts` 1431 lines + `tribeEvents.ts` 156 lines,
both frozen 2026-10-01 incl. the war_graves/rival_festival wiring). Native
pins reference `tests/` test methods (`file::test_name`), scene suites under
`tests/scenes/`, and the task-7 probes.

**Headline numbers:** headless `./tools/test.sh` → **43 files, 641 tests,
18589 checks, 0 failures** (task-8 state — the task-7 rider pins add the
totem-label seam test + the two probe literals). Scene suites under xvfb
(all exit 0): bot arc, bot creature, **bot tribe** (full arc ×2 determinism —
BOT_TRIBE_ALL_OK; the task-7 hut-damage rider assert rides it), menu
real-click, editor real-click, tribe scene + tribe moments (one suite,
**43 structural asserts** — the 29 task-4 asserts verbatim-green inside it
plus the 14 task-7 moment asserts), **3 perf probes** (cell, creature,
tribe), boot, visual suite. Probes: `tools/probe_tribe.sh` → **9 tests /
89 checks / 0 failures** (also inside the full suite).

Legend: ✅ pinned · ⏸ spec-sanctioned deferral.

## 1. Tribe sim core — state, chief, tribesmen, economy (task 1)

| Feature | TS | Native | Test |
|---|---|---|---|
| Constants Z_TO_Y 0.62 / Z_MIN −200 / Z_MAX 240 / WORLD_HALF 2400 | TribeStage.ts:21-24 | `tribe_sim.gd:104-107` | `test_tribe_sim.gd::test_constructor_seeding_pins` |
| Constructor world-seed: 30 trees (wood 4..9, seed 0..9), 26 bushes (food 3..7), 1 starting hut, 2 named rivals (±1300..2000) — draw order sacred | TS:101-137 | `tribe_sim.gd::_init` | `test_constructor_seeding_pins`, `test_constructor_draw_order_bit_exact` |
| popCap = built huts × 3 + 1 | TS:272 | `tribe_sim.pop_cap()` | `test_pop_cap_formula`; econ `test_probe_tribe.gd::test_hut_recruit_45s_popcap_and_mid_siege` |
| on_enter: C1 deck-rebuild gate, fall/victory/death resets, toastInset 190, invulnT 3, restore short-circuit, hutless re-found reseed, pack conversion ONCE (max(3, pack), clamp_genome guard, packGenomes reset) | TS:139-191 | `tribe_sim.on_enter()` | `test_on_enter_pack_conversion`, `test_on_enter_pack_minimum_three_and_fallbacks`, `test_on_enter_pack_clamp_guard_and_one_genome`, `test_on_enter_restore_short_circuit`, `test_on_enter_deck_rebuild_gate_c1`, `test_on_enter_hutless_refound_resets` |
| persist_state (corpse guard) / restore_state: non-finite reject, empty-village corpse reject, REPLACE-not-append, cap slice max(12, huts·3+1), role sanitize, totem clamp | TS:195-244 | `tribe_sim.persist_state()/restore_state()` | `test_persist_blob_and_round_trip`, `test_persist_corpse_guard`, `test_restore_corrupt_guards`, `test_restore_cap_and_hut_filters` |
| Chief movement: click-move deadzone 12 + wy/Z_TO_Y projection, WASD, accel/drag exp(−6dt), vz ×0.8, speed clamp, gait | TS:456-516 | `tribe_sim.update_chief()` | `test_chief_click_move_and_wasd`, `test_chief_vz_accel_is_08` |
| Chief hut-proximity heal is a TS noop (`dna += 0`) | TS:487-491 | comment at `tribe_sim.gd:690-691` (header divergence note) | — (documented) |
| Role hotkeys Digit1/2/3 → assign_role ("Everyone: {role}") | TS:495-497, 518-522 | `tribe_sim.assign_role()` | `test_assign_role_and_hotkeys`; bot real taps `tests/bots/bot_tribe.gd` roles leg |
| try_build_hut: wood ≥ 40 checked BEFORE the 2 s cooldown arms; cost, placement, fx, toast | TS:526-541 | `tribe_sim.try_build_hut()` | `test_try_build_hut_gates`; bot's REAL R · HUT click (−40 exact) |
| try_totem: active/empty-tribe/100-food-80-wood gates, banner | TS:543-559 | `tribe_sim.try_totem()` | `test_try_totem_gates`; bot's REAL TOTEM click |
| Raid-touch death (dist < 40, chance dt·2 first in the && chain, invuln/deathFade gates, cam shake) | TS:504-515 | `tribe_sim.update_chief()` tail | `test_chief_raid_touch_death_pipeline` |
| handle_chief_death: 15% DNA tax once (deathHandled latch), toast with cause, respawn at 1.6 s to the SAFEST of 8 samples (farthest from beast/warriors/fires, minD 9999 fallback, strict-`>` tie keeps earliest), invuln 3, no tribesman loss (A08) | TS:422-454 | `tribe_sim.handle_chief_death()` | `test_chief_death_dna_tax_rounding`, `test_chief_respawn_safest_sample_geometry` |
| Tribesman decay hurtT/attack/eatT ×3/×2/×2; fight rivals < 44 (power warrior 1.6 / hunt 1 / gather 0.5, dmg 22·power·dt, self-dmg 10 @ dt·1.2, mood angry, stand-ground drag exp(−4dt)) | TS:586-653 | `tribe_sim.update_tribesmen()` | `test_tribesman_fight_power_per_role`, `test_tribesman_fight_self_damage_and_death` |
| Tribesman death splice + burst + toast | TS:648-652 | `tribe_sim.update_tribesmen()` | `test_tribesman_fight_self_damage_and_death` |
| Job AI: retarget cadence 0.5 s; gather WOOD QUOTA (under-80 → every EVEN-indexed tribesman chops, bush ignored), hunt bush-600-else-tree, warrior patrol ±90/±60 + rare rival march 0.005 | TS:747-812 | `tribe_sim.tribe_job_ai()` (index threaded — `indexOf` deep-compare divergence, header) | `test_job_ai_gather_wood_quota`, `test_job_ai_hunt_and_carry_delivery_target`, `test_job_ai_retarget_cadence`, `test_job_ai_warrior_patrol_and_march`; econ `test_probe_tribe.gd::test_wood_quota_even_gatherers_chop_and_delivery_legs` (attribution + conservation) |
| tribeArrive: delivery food/wood +8; pickup bush −1 + regrow 30 / tree −1 (burning excluded) | TS:815-843 | `tribe_sim.tribe_arrive()` | `test_arrive_pickup_and_delivery`, `test_arrive_hutless_delivery_at_chief`, `test_arrive_burning_tree_not_pickable`; probe quota (both currencies, +8/leg) |
| Economy arrivals block (atHut/atChief < 44 gates) | TS:1086-1102 | `tribe_sim.update_economy()` | `test_arrive_pickup_and_delivery`; probe quota |
| Bush regrow (empty → rng 3..7 after 30 s), sapling every 45 s while < 30 alive, tree burnout | TS:1104-1132 | `tribe_sim.update_economy()` | `test_economy_regrow_sapling_burnout`; econ `test_probe_tribe.gd::test_bush_regrow_30s_cycle` |
| Hut build 6 s (toast), repair +5·dt to maxHp, recruitT 45 s + mid-siege block (rivalWarriors 0) + popCap gate ('A child was born…') | TS:1134-1157 | `tribe_sim.update_economy()` | `test_economy_hut_build_complete_and_repair`, `test_economy_recruit_gates`; econ recruit probe (exact 45 s crossing, held clock, silent reset at cap) |
| Totem progress += workers·dt·1.6 clamp 100 | TS:1159-1163 | `tribe_sim.update_economy()` | `test_economy_totem_progress_rate`; econ `test_probe_tribe.gd::test_totem_progress_rate_worker_count` (48.0 exact, clamp, workers-0 freeze) |
| Festival passive (food > 80, dt·0.05: karma +0.01, food −5, mood happy) | TS:1166-1171 | `tribe_sim.update_economy()` | `test_economy_festival_passive` |
| mutateLike (hue ±40 wrap, size gauss·0.1 clamp 0.6..2.2) — ported locally | TS:1426-1431 | `tribe_sim.mutate_like()` (header note: M2 mutation.gd is a different operator) | exercised via `test_on_enter_pack_conversion` family |
| 600-tick determinism + long-run sanity | — (native pin) | — | `test_determinism_two_sims_identical`, `test_headless_sanity_long_run` |

## 2. Raids, beast, fires, transitions (task 2)

| Feature | TS | Native | Test |
|---|---|---|---|
| Raid clock: invuln decay, timer −dt; peaceful+hillless floor 30; fire at ≤ 0 → reset 80 + rng(−15, 25), peaceful +40; first-raid hint once | TS:327-339 | `tribe_sim.update()` raid block | `test_raid_clock_cadence_and_first_raid_hint`, `test_raid_clock_peaceful_gates`; econ `test_probe_tribe.gd::test_raid_cadence_reset_value_and_first_hint_once` (same-seed twin: reset +40 exact, wave −1), `::test_raid_cadence_peaceful_hutless_floor` |
| launchRivalRaid: rng.pick, dead-rival skip, party cap 5, wave 1/2, n = min(wave + floor(rng 0..2), 5−alive), spawn genome overrides (hue 5 / carnivore / spikes 3 / jaw 3), banner, raidActive | TS:561-584 | `tribe_sim.launch_rival_raid()` | `test_raid_party_wave_cap_and_genome`, `test_raid_party_cap_five`, `test_raid_skips_dead_rivals`; probe cadence (wave pins) |
| Rival warriors: hp ≤ 0 splice + food +8; march nearest BUILT hut (fallback nearest tribesman — pop-1 fix), flee → home; accel 240/190, drag exp(−5dt), gait dt·8 | TS:656-707 | `tribe_sim.update_tribesmen()` warrior block | `test_rival_warrior_death_feeds_food`; bot raid leg |
| Hut siege: dist < 40 + march → hp − 6·dt, crack fx, destruction splices + raidTimer floor 120 + 'A HUT BURNS' + boom | TS:683-695 | `tribe_sim.update_tribesmen()` | `test_siege_destroys_hut_and_floors_raid_timer`; the bot's hut takes real siege damage (the task-7 rider assert) |
| Hutless+tribeless → flee; flee home < 90 slip away | TS:696-706 | `tribe_sim.update_tribesmen()` | `test_warrior_flee_home_slip` |
| war_graves combo: raid emptied → raidActive false; combo on → +15 DNA 'war graves' + reward toast, ONCE per raid instance | TS:709-717 | `tribe_sim.update_tribesmen()` tail | `test_war_graves_combo_pays_once_per_raid`; econ `test_probe_tribe.gd::test_war_graves_dna_per_raid_combo_gated` (combo on/off twins, two instances, no double pay) |
| Rival camp assault: player warriors < 90 drain 4·dt each, anger +0.1·dt clamp 1; death → banner + food +60 + wood +40 + karma −0.05; dead camps skipped | TS:858-879 | `tribe_sim.update_rival_warriors()` | `test_camp_assault_rewards_and_karma`; econ `test_probe_tribe.gd::test_rival_camp_assault_drain_and_rewards` (exact drain/anger/reward on the death tick) |
| Beast spawn (genome overrides size 2.1/carnivore/jaw 5/spikes 4/horns 3/hue 300/plates/eyes 4, angle rng·TAU, dist 900/300 clamped, hp 420) / despawn toast | TS:1004-1021 | `tribe_sim.spawn_beast()/despawn_beast()` | `test_beast_spawn_pin`; scene moment `tribe_beast` (the REAL spawn genome drawn) |
| Beast: march nearest hut 90/70·dt (chief fallback), siege 6·dt + destruction, fighters < 60 → 9·dt each + chief near 14, gore chance dt·0.5 chief-proximity-gated (A08) + invuln gate, death → +60 food + 50 DNA + levelup | TS:881-935 | `tribe_sim.update_beast()` | `test_beast_march_siege_and_chief_fallback`, `test_beast_fighter_dps_and_gore_gate`, `test_beast_death_rewards`; econ `test_probe_tribe.gd::test_beast_dps_fighters_and_chief` (32/18/0 exact windows, invuln holds the gore) |
| Fires: ttl decay, extinguish 4·dt each nearby tribesman, smoke fx, spread (8 s, 0.25, first unburnt tree < 90), splice at 0; ignite_tree guards (stumps don't burn) | TS:937-967 | `tribe_sim.update_fires()/ignite_tree()` | `test_fires_decay_extinguish_and_splice`, `test_fires_smoke_and_spread_ignite`, `test_fire_spread_finds_nothing_and_ignite_guards` |
| lightning_strike: targets = unburnt trees + huts, empty → 'The storm crackles…'; hut branch hp − 35 (the TS duck-type ported as an explicit key check — header divergence), tree → ignite; shake 6/0.4 + zap | TS:971-993 | `tribe_sim.lightning_strike()` | `test_lightning_empty_targets_and_hut_branch`, `test_lightning_tree_branch_pick_pin` |
| Stage timers `{left, fn}` — splice then call (fn ALWAYS runs), same-tick reverse order | TS:306-313, 998-1002 | `tribe_sim.after()/update()` | `test_update_shell_timers_fn_runs_after_removal`, `test_timer_same_tick_order_is_reverse` |
| Fall path: empty village → banner ttl 6 + die audio; > 4 s latch → DELETE flags.tribeState + save_all hook + go_to('creature', 'BACK TO THE WILDS') | TS:381-398 | `tribe_sim.update()` fall block | `test_fall_path_blob_delete_and_go_to`; E2E `test_world_creature_pins.gd::test_fall_path_lands_creature_with_blob_deleted` |
| Victory path: totem ≥ 100 → victoryT; > 2.5 latch → save_all + ascend + go_to('civ', 'THE FIRST CITY') | TS:400-409 | `tribe_sim.update()` victory block | `test_victory_path_latches`; the bot's real victory card + unregistered-civ no-op |
| raidsBlocked / pauseRaids / launchRivalRaidNow (the chaos seam — hutless peaceful camps never get raided) | TS:1023-1039 | `tribe_sim` trio | `test_raids_blocked_pause_and_now`; `test_tribe_events.gd::test_rivalsurprise_refuse_keeps_warning_honest`, `::test_bold_raid_refuse_and_launch` |

## 3. Tribe chaos events deck + scheduler (task 3)

| Feature | TS | Native | Test |
|---|---|---|---|
| Baseline 5 defs verbatim (storm 0.7+chaos [14,22] cd 55; beast 0.6+chaos [25,25] cd 65; rivalsurprise 0.6−karma·0.3 cd 70; festival 0.8+max(0,karma) cd 80; gift 0.5 flat cd 90) | tribeEvents.ts:10-77 | `tribe_events.gd` | `test_tribe_events.gd::test_traitless_deck_is_six_defs` (5 + siege_hoard), `::test_def_constants_verbatim` |
| Storm apply/tick — the two ex-`Math.random` sites seeded in-stream (header divergence) | tribeEvents.ts:20/24 | `tribe_events.gd` + sim | `test_storm_apply_divergence_pin`, `test_storm_tick_roll_pin` |
| Gated 4: bold_raid (raider_bold/pirate_wind + rivalsurprise ×1.5 remap), rival_festival (calm_veil, bless ×1.3), siege_hoard (always in deck, severity weight), festival MIRROR face (one rule inverted — mood afraid; food −20 + 3 spread-999 fires stay) | tribeEvents.ts:79-155 | `tribe_events.gd` | `test_gated_defs_gate_on_the_world`, `test_weight_formulas` (1e-12), `test_festival_body`, `test_festival_body_hutless_falls_back_to_origin`, `test_festival_mirror_body` |
| Event bodies: star_shower (+80 DNA, float world, toast), festival/mirror fires | TS:1041-1084 | `tribe_sim.festival()/festival_mirror()/star_shower()` | `test_star_shower_body` |
| siege_hoard two waves via the stage timers (the ONE severity formula) | tribeEvents.ts | `tribe_events.gd` + `tribe_sim.after()` | `test_siege_hoard_two_waves_via_timers` |
| Scheduler wiring: full ctx (gapMult·gapBias, mood, warnScale, mirrors, dominance = wealthPressure min(1,(food+wood)/500)), onWarn/onApply (addChaos 0.03, mirrorOf, storyteller note)/onEnd | TS:341-369 | `tribe_sim.update_chaos()` | `test_update_chaos_no_warn_natural_spawn`, `test_update_chaos_warn_then_apply`, `test_update_chaos_storyteller_hooks_feed_the_ctx`, `test_update_chaos_beast_lifecycle_end_hook`, `test_update_calls_chaos`, `test_has_active_chaos_phase_gate`, `test_wealth_pressure_dominance_input` |
| Mirror rule once per run (shared ledger) | TS:365-368 | `tribe_sim.mirrorLedger` | `test_mirror_once_flow_tribe` |

## 4. Tribe stage scene node (task 4)

| Feature | TS | Native | Test |
|---|---|---|---|
| Render order: backdrop → lawn (2-stop hsl, NO night dim — tribe flavor) → dirt 500 → rival camps → bushes → huts → totem → trees → z-sorted ents → fire glows → fx → night overlay → vignette → HUD → death card | TS:1176-1394 | `tribe_stage.gd` canvas split (header) | scene moments exercising every band (§8); headless `test_tribe_scene.gd::test_render_guards` |
| Rival camp draw: disc 60 rgba(120,60,40,0.25), 3 poles 8×34 + cap discs, name outlinedText | TS:1196-1208 | `tribe_stage.gd::_draw_ground` | scene moment `tribe_camp` (4 asserts) |
| Bushes (ellipse + berries ceil(food/2) cap 4), huts (alpha built 1 : 0.5, walls/roof/door, cracks < 60%, '🏠{hp}' label FULL alpha — the after-restore quirk) | TS:1231-1278 | `tribe_stage.gd::_draw_ground` | scene moments `tribe_village_day`, `tribe_hutcon` (dim-wall pair + label presence vs control) |
| Great totem: progress-scaled 20×90·p pole, discs at p 0.3/0.6, glow at 1, 'TOTEM {round(p)}%' label (the round-of-fraction quirk reads 1%) | TS:1281-1294 | `tribe_stage.gd::_draw_ground` via the `totem_progress_label` seam | scene moments `tribe_village_day` (45%), `tribe_totem` (75%: pole + both discs + label); the NUMBER pinned headless `test_tribe_scene.gd::test_totem_progress_label_round_of_fraction_quirk` (0%/1% strings) |
| Trees: sway sin(time·0.6 + seed)·2.5, quadratic trunk lw 8, crown/burn glow | TS:1296-1300 | `tribe_stage.gd::_draw_ground` | village moment band + night fires |
| Z-sorted drawables (stable ties by insertion): tribesmen 1.7 + role/cargo icon + hp bar 28×3 when damaged; warriors 1.7 angry + ⚔️; beast 2.6 + 🦁 + hp bar 48×4 #ff5a5a; chief 2.1 happy + 👑 hidden at fade > 0.4; pooled RID pairs | TS:1303-1368 | `tribe_stage.gd::_sync_creature_items` + CreatureItem/TribeExtraItem | `test_zsort_pool_order_tribesman_over_chief`, `test_zsort_chief_hidden_in_death_fade`; scene moments `tribe_raid` (hue-5 bodies), `tribe_zsort`, `tribe_beast` |
| Night overlay FLAT rgba(10,10,40,0.4) at isNight (0.55, 0.95) + vignette 0.4 | TS:1380-1384, 1396-1398 | `tribe_stage.gd::_draw_ui` | `test_is_night_window`; scene moments `tribe_night` (dim vs day + campfire glows + stars), `tribe_death` |
| Death card: red veil min(0.55, fade·0.4) + 'THE CHIEF HAS FALLEN' 26 | TS:1389-1393 | `tribe_stage.gd::_draw_ui` | scene moment `tribe_death` |
| HUD: stockpile panel (18, vh−172) 210×52 + rows, hut button (canHut wood ≥ 40), totem button (canTotem 100/80; active %), hudRects re-registered EVERY render, clicks dispatched in UPDATE | TS:1400-1423 | `tribe_stage.gd::_render_hud/_sync_hud_rects` | `test_hudrects_registered_per_render`, `test_hudrect_click_dispatches_in_update`, `test_hudrect_hover_upgrades_cursor`; scene moment `tribe_village_day` (panel + both lit buttons) |
| Camera: follow rate 4, zoom 0.95, cam.toWorld world feed | TS:371-377 | `tribe_stage.gd::update()` | `test_update_camera_rate4_zoom095_and_world_feed` |
| Abilities: 1/2/3 active when ALL tribesmen hold the role | TS:411-417 | `tribe_stage.gd::update()` | `test_update_feeds_role_abilities` |
| Frozen seam (render without stepping) — the moment-suite gate | — (native test seam) | `tribe_stage.frozen` | `test_update_frozen_seam_holds_the_sim` |
| main.gd registers TribeStage (the founding lands the REAL stage) | — (wiring) | `src/main.gd` | `test_main_registers_tribe_stage` |

## 5. HUD wiring, founding handoff, save/continue (task 5)

| Feature | TS | Native | Test |
|---|---|---|---|
| toast_inset 190 armed by tribe on_enter; the game-level reset on every stage switch (game.ts:213) | TS:154 | `tribe_stage.on_enter` + `game.gd` | `test_hud_tribe.gd::test_switch_stage_resets_toast_inset`; scene toast-inset pair |
| Founding E2E: creature found_tribe → the REGISTERED TribeStage lands, pack conversion consumes packGenomes once (min 3), packGenomes '[]' after | TS:176-189 | `game.gd` go_to + `tribe_stage.on_enter` | `test_hud_tribe.gd::test_founding_e2e_lands_registered_tribe`; the bot's real founding leg |
| Save/continue: creature save CONTINUEs into a tribe refound; TRIBE save mid-progress CONTINUEs with the village as it stood | TS:195-244 | `game.gd` persist seam | `test_world_creature_pins.gd::test_continue_creature_save_refounds_into_tribe`, `::test_tribe_save_continue_restores_village` |
| Fall-path E2E: dead village → 'BACK TO THE WILDS' lands creature with the blob deleted (no resurrection) | TS:381-398 | `game.gd` + sim | `test_fall_path_lands_creature_with_blob_deleted` |
| Objective line on both on_enter paths | TS:163-164/190 | sim hook | `test_on_enter_restore_sets_objective_only`; the CONTINUE-leg pin in the pins file |
| i18n: tribe surface 1:1 with the TS VI object (absences 1:1 too) | TS VI object | `assets/i18n/vi.csv` | `test_hud_tribe.gd::test_tribe_i18n_mapping_1to1`, `::test_unwrapped_sites_stay_unwrapped` |

## 6. Bot arc + determinism (the §5.4(b) gate — task 6)

| Feature | Native pin | Status |
|---|---|---|
| The full tribe arc through the REAL input pipeline (bot law audit clean — the only sim mutator is the documented `debug_grant`): role hotkeys Digit1/2/3 real taps → a watched +8 delivery → a hut through the REAL drawn R · HUT button (−40 exact) → the recruit gate → the FIRST RAID survived on the REAL clock (hint toast + banner + raidActive true→false via the war_graves block, a real Digit3 arm, the chief parked through real held-mouse) → the Great Totem through the REAL drawn TOTEM button → the victory card → the unregistered-'civ' no-op with the tribe stage remaining | scene `test_bot_tribe.gd` → BOT_TRIBE_ALL_OK ×2; the task-7 rider upgraded the raid's `hut_damaged` latch to a scene-gate assert (the raid really damages a hut — 98.33/100 at close at 0xBEEF) | ✅ |
| Same seed → same run path: the full bot ×2 at LCG 777 / world 0xBEEF, quantized TRIBE fingerprints field-identical + the per-600-frame sweep trace as first-divergence triage (the fingerprint NAMES the stage — the task-5 aliasing lesson) | `test_bot_tribe.gd` determinism gate; stable across a third fresh-process invocation (task-6 review) | ✅ |
| The 0xBEEF pin documented as native-only (the TS bot's startNewGame takes no seed) | `tests/bots/bot_tribe.gd` header | ✅ |

## 7. Visual moments (§5.4(d) pixel-assert — tasks 4 + 7)

scene `tests/scenes/test_tribe_scene.gd` + `tools/visual_check_tribe_scene.py`
(probes.json carries the live-camera anchors — the TS manual transform
formula, computed in-harness) — **43 structural asserts**, VISUAL_CHECK_OK,
exit 0. Freeze discipline: sim-time/state-conditioned freeze arms (NO
engine-frame gates — the M3 volcano lesson); the raid arms on the REAL raid
clock.

| Moment | Asserts |
|---|---|
| Day village (lawn band ×2, hut wall/roof, totem pole, stockpile panel + text, both lit build buttons, totem label) | 10 |
| Raid through the REAL clock (banner panel + warm title, two hue-5 war-party bodies) | 4 |
| Campfire night (flat overlay dim, 3 fire glows, backdrop stars vs day) | 5 |
| Death card (dim vs day, title, the chief body gone at fade > 0.4) | 3 |
| Z-sort (Ruling 14: red tribesman over green chief + the overlap scan) | 3 |
| Totem raising at 75% (pole mass, red disc p>0.3, blue disc p>0.6, label) — task 7 | 4 |
| Beast attack (purple plates body, red 48×4 bar, the scale-2.6 purple run) — task 7 | 3 |
| Rival camp (disc tint vs the outside twin, pole mass, cap disc, warm name text) — task 7 | 4 |
| Hut construction (0.5-alpha wall dimmer/less-warm than the built twin over the SAME lawn band, roof mass, the FULL-alpha label vs an empty-lawn control) — task 7 | 3 |
| Toast inset pair (band diff, row position in the 190 band, light text, twin-clean gap band) | 4 |

## 8. Econ probes (§5.4(c) — task 7)

`tests/test_probe_tribe.gd` (9 tests / 89 checks — the two task-8 literal
pins included) + the one-command headless
entry `tools/probe_tribe.sh` (the targeted `tests/probe_runner.gd` runner; the
file also joins the full suite). Each probe boots the full Game + the REAL
TribeStage out-of-tree and drives the sim through its documented
input-SNAPSHOT contract; formulas cited to the frozen TS lines in each
probe's provenance comment:

| Probe | Pins |
|---|---|
| wood-quota income | the TS:757-768 shift: even-indexed gatherers chop while wood < 80 (bush within 600 ignored), quota-off stops the chop; per-tick Δ attribution + the conservation identity pickups = deliveries + in-flight carries at +8/leg BOTH currencies (TS:815-843/1088-1102); every pickup arms regrow 30 |
| bush regrow | no refill under the 30 s clock, the rng 3..7 band + the task-8 stream-position literal at 0x7E11 (5.082817288), the clock only runs while food ≤ 0 |
| hut recruit | the exact 45 s crossing (clock reads 0.0 on the birth tick), mid-siege hold past 45 without reset, the siege-lift birth next tick, popCap 7 fill + the silent gated reset (TS:1149 before 1150) |
| raid cadence | reset ∈ 80 + rng(−15,25) band + the task-8 stream-position literal at 0x7E14 (91.268423758), the same-seed peaceful twin: reset exactly +40 and wave exactly −1, the hint exactly once across two raids, the flag latched |
| peaceful-hutless | the floor lifts an overdue clock to 30 every tick, no launch while hutless, one standing hut re-arms wave-1 raids |
| war_graves | +15 DNA once per raid instance (two instances, no double pay, one toast each), the combo-off twin pays nothing |
| totem rate | 3 workers × 10 s × 1.6 = 48.0 exact, the 100 clamp, the workers-0 freeze |
| camp assault | anger clamp at 1.0, the 4·dt-per-attacker drain (1 vs 2 attackers), the death tick pays +60 food +40 wood −0.05 karma exactly, dead camps are skipped |
| beast DPS | dps = 9·fighters + 14 chief: 32/18/0 exact hp windows, the invuln gate holds the A08 gore off |

## 9. Explicit deferrals (spec-sanctioned, none are tribe-stage behavior gaps)

| Item | Reason |
|---|---|
| Audio synth (WebAudio → AudioStreamGenerator) | Migration spec §7 risk-table item — the sim's audio hooks stay no-op with TS call sites/params pinned (the M1 ruling carries); the synth port is its own task after parity. |
| Civ stage landing | The victory handoff is fully native and pinned (the real victory card + the unregistered-'civ' no-op with the tribe stage remaining — the M3 placeholder ruling pattern); the civ stage itself is milestone 5 scope. |

## 10. M5 deferred (recorded at task 7)

| Item | Provenance |
|---|---|
| CivStage registration + the victory 'THE FIRST CITY' transition LANDING | M5 scope (plan Completion: M5 = Civ, CivStage.ts 27.5K + civEvents 2.8K, the §5.4 gates at civ flavor); until then go_to('civ') no-ops safely by design. |
| Civ surface notes for the port: the tribe's persist blob (food/wood/huts/totemProg/totemActive/tribe) is the civ-stage's founding input; the pack-conversion `count = max(3, raw)` pattern and the REPLACE-not-append restore are the shapes CivStage's own roster restore must mirror | read off TribeStage.ts during task 7 |
| Creature `update_ents` hot-loop optimization (2 ms target) | M3 §16 carry-forward — still open, gated on creature A-B coverage |
| T10 moment pin-gaps ×2 (editor preview body, sun/moon disc) | M3 §17 carry-forward — cheap probe candidates |
| Founding-charm timing watch (~2 s at 0xBEEF) | M3 §17 carry-forward — bounded, ×2-proven deterministic |
| The pre-existing 'Invalid polygon data' xvfb render warning | task-6 review observation — fires before the tribe legs (cell/creature render path), pre-existing; grep someday |

## 11. A-B behavior-identity across the window (the M3 §15-analog — task 8)

`tools/ab_test.sh creature-parity-m3` (base tag → HEAD) → **IDENTICAL, 0 diff
lines** (exit 0). Both sides dump sha256 `ea35920b…` — the SAME sha the M2
gate first recorded and the M3 wrap re-verified: the standing cell+creature
dump did not move one bit from `cell-parity-m2` across the whole creature AND
tribe windows (the tribe stage is additive, as the M3 wrap predicted). Ruled
lines: none needed. Evidence committed (`evidence.txt`, `last_diff.txt`
0 bytes, verdict=IDENTICAL, base_commit=creature-parity-m3,
head_commit=3de7f29 — the wrap's commits are riders/instruments/tests/docs
only, no sim file).

## 12. Perf (the M3 §16-analog — task 8, split metrics from day one)

**Metric integrity (the T10 lesson carried):** both tribe probes were born
SPLIT — the pure sim tick carries the asserted budget (headless,
contention-immune), the stage render pass carries the painter-side budget
(scene-side), the full frame wall-window is recorded, never asserted.

**Tribe sim tick @ 60 tribesmen + 6 rival warriors + 6 huts (the §5.4 budget:
≤ 2 ms — the M3 target shape, tribe's own row) — MET:**

| Measurement | Number |
|---|---|
| `tools/perf_tribe_sim.gd` (headless, contention-immune — the primary instrument; fixed world via documented seams: 60 via `add_tribesman`, 6 sieging warriors, invuln pin, chaos silenced; 300 ticks) | **0.709–0.996 ms avg over 5 runs** (max spikes 2.6–20 ms under ambient load ~3 with a sustained soak process on one core) |
| Cost shape | the tribe job-AI hot path is far cheaper per-agent than the creature `update_ents` loop (no eco tick, no IK) — the M3 2 ms lesson's target carries unchanged and holds |
| Scene-side cross-check (`tests/scenes/test_perf_tribe.gd`, xvfb) | sim avg ~3.39–3.50 ms over 2 runs — inflated by llvmpipe contention (the recorded number, not the asserted one) |

**Stage render pass @ 66 creatures + the ground pass (the M3 painter-side
budget shape: ≤ 4 ms) — MET, asserted in the scene probe:**

| Measurement | Number |
|---|---|
| Stage `render()` pass (`_sync_creature_items` pooled-item sync + `_sync_hud_rects` re-registration + canvas queues — the GDScript-side render-prep cost the game controls; the deferred canvas `_draw` lands in the frame window) | **~1.51–1.52 ms avg over 2 runs** (maxes 7.1/9.7 under ambient load) — asserted ≤ 4 ms |
| Full frame wall-window under llvmpipe (sim + render prep + deferred `_draw` + real rasterization) | **~272–278 ms avg** (maxes ~364/372) — rasterization-dominated; no GDScript-side change moves it |

The rig caveat (M2/M3 precedent, restated): llvmpipe is the WORST-case
rasterizer the probe intentionally runs on — the frame budget targets a real
GPU, which is faster by orders of magnitude on this draw set; llvmpipe's
frame window is recorded informationally. The creature 2 ms target remains
the standing open item (M3 §16 carry-forward, §10).

## §5.4 criteria checklist

| Criterion | Evidence pointer | Verdict |
|---|---|---|
| (a) Every TS tribe feature present | §1–§6 — every row pinned or explicitly deferred with a spec citation (audio synth + civ landing only, both spec-sanctioned: §9) | ✅ |
| (b) Bot headless full tribe arc through the real UI, ×determinism | `tools/test_bot_tribe.sh` → **BOT_TRIBE_ALL_OK ×2 passes** (LCG 777 / world 0xBEEF): the real founding → roles → delivery → REAL hut button → recruit → the first raid survived on the REAL clock (hint + banner + war_graves closure + real hut damage) → REAL totem button → the victory card → the unregistered-civ no-op; fingerprints field-identical across passes (§6) | ✅ |
| (c) Econ probes TS-verbatim | `tools/probe_tribe.sh` → **9 tests / 89 checks / 0 failures** (§8; formulas cited to the frozen TS lines in each probe's provenance comment; exact-identity + same-seed-twin pins); also inside the full headless suite | ✅ |
| (d) Pixel-assert suite, tribe moments | the tribe scene suite under xvfb (**43 structural asserts** over 10 moments + the toast twin, `tools/visual_check_tribe_scene.py`, §7) — every moment ≥ 3 PIL-checked structural asserts over a live viewport capture | ✅ |
| Full suite green | headless `./tools/test.sh` → **43 files / 641 tests / 18589 checks / 0 failures** (task-8 state); all xvfb scene suites exit 0 (bot, bot creature, bot tribe, editor click, menu, visual ×2, creature scene, tribe scene, perf ×3, boot, visual suite) | ✅ |
| A-B behavior-identity + perf budgets | **§11**: `tools/ab_test.sh creature-parity-m3` → IDENTICAL, 0 diff lines (the standing cell+creature dump unmoved — the tribe stage is additive); **§12**: tribe sim tick 2 ms target MET (0.71–1.00 ms headless @ 60+6), stage render-prep ≤ 4 ms MET (~1.5 ms, asserted in the scene probe), frame window recorded with the rig caveat | ✅ |

## Completion note (spec §5.4)

Tasks 1–8 are complete: the four §5.4 feature gates (a)–(d) hold with the
evidence above, the A-B behavior-identity gate is IDENTICAL across the whole
milestone window (§11), the §5.4 tribe perf budgets are measured and MET with
the split metrics (§12), and the full suite is green (headless + every xvfb
entry). The task-7 review riders landed at the wrap (the two probe literals,
the totem-label seam assert, the out-of-tree provenance clause). Remaining:
the controller's final whole-branch review, then the `tribe-parity-m4` tag
per the binding scope split.


## Completion note (spec §5.4)

M4 is complete per spec §5.4: the four criteria gates pass ((a)–(d) above), the A-B behavior-identity gate is IDENTICAL across the whole milestone window (dump sha unmoved since the M2 gate), all perf budgets met (tribe sim tick 0.709–0.996 ms vs the ≤ 2 ms target — measured, tripwire standing), and the full suite is green (43 files / 641 tests / 18589 checks / 0 failures; all 14 xvfb entries exit 0). The final whole-branch review (final-review-m4.md — independent; tribe sim seams re-derived from a full TS read, cross-stage seams verified, A-B re-run LIVE at the tag head) returned **TAG-READY**: 0 Critical / 0 Important / 2 Minor (the probe-count doc row fixed in this commit; the perf-tripwire shape informational, consistent with M2/M3 practice). Tagged `tribe-parity-m4`. Next milestone: M5 = Civ (CivStage.ts + civEvents.ts, the §5.4 gates at civ flavor), then M6 = Space, then M7 = CI/release + repo overwrite.
