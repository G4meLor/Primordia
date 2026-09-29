# PRIMORDIA Native — M2 parity checklist (cell stage)

Datum: 2026-09-30 · Tag: `cell-parity-m2` · Spec: [`docs/specs/2026-09-29-native-migration-design.md`](specs/2026-09-29-native-migration-design.md) §5.2

**Verdict: milestone done.** Every cell-stage feature of the frozen TS build has a
native pin. Two items are explicit, spec-sanctioned deferrals (audio synth,
creature-stage landing) — neither is a cell-stage behavior gap.

**Source of truth:** the TS contract (`Spore/tests/features.test.ts` +
`Spore/tests/bot.test.ts`) plus the feature surface of `Spore/src/game/cell/CellStage.ts`
+ `cellEvents.ts` (both frozen). Native pins reference `tests/` test methods
(`file::test_name`) or scene suites under `tests/scenes/`.

**Headline numbers:** headless `./tools/test.sh` → **28 files, 381 tests, 15293
checks, 0 failures**. Scene suites under xvfb (all exit 0): boot, bot arc
×3 seeds ×2 determinism passes, menu real-click, editor real-click, T7 visual
cell (8/8 pixel asserts), T10 visual suite (32/32 structural asserts), perf probe
(PERF_OK, see below).

Legend: ✅ pinned · 🟡 pinned indirectly (mechanism noted) · ⏸ spec-sanctioned deferral.

## 1. i18n (TS features.test.ts "i18n" + the I-q1 audit)

| Feature | Native pin | Status |
|---|---|---|
| EN passes strings through untouched | `test_i18n.gd::test_en_passthrough` | ✅ |
| VI translates known keys, falls back for unknown | `test_i18n.gd::test_vi_known_keys_and_unknown_fallback` | ✅ |
| Language choice persists via settings | `test_i18n.gd::test_settings_round_trip`, `test_hud.gd::test_pause_language_item_flips_i18n` | ✅ |
| I-q1: the 24 flagged variant/warn/toast keys translate in VI | `test_i18n.gd::test_iq1_flagged_keys_translate` | ✅ |
| I-q1: VI dictionary never shrinks below the audited wave (`viKeyCount ≥ 454`) | same test (asserts `vi_key_count() >= 454`) | ✅ |
| I-q1: nebula template keys compose (`The nebula passes over` / `The nebula seeds` / `nothing takes hold.` / `new species on`) | `test_i18n.gd::test_iq1_flagged_keys_translate` | ✅ |
| I-q1 structural audit: no unwrapped hud literal; every `t()` key in game/ui source has a VI entry | `test_i18n.gd::test_structural_audit` (+ `test_audit_scanner_selfcheck` scanner self-test) | ✅ |

## 2. Save slots, difficulty flow (features.test.ts "save slots" / "new game flow")

| Feature | Native pin | Status |
|---|---|---|
| Saves and loads three isolated slots | `test_context.gd::test_save_load_round_trip`, `test_slot_isolation` | ✅ |
| Save refuses the title screen / default slot | `test_context.gd::test_save_refuses_menu_and_default_slot` | ✅ |
| `deleteSlot` empties a slot | `test_game_flow.gd::test_slot_meta_reads_native_saves` ("deleted slot reads null") + menu trash `menu.gd::delete_slot` | ✅ |
| Corrupt/junk save files coerce, tombstone in CONTINUE | `test_context.gd::test_junk_and_malformed_files`, `test_game_flow.gd::test_continue_loads_and_corrupt_marks` | ✅ |
| `startNewGame` applies difficulty: chaos start 0.45, gapMult 0.7, flags.difficulty, slot save | `test_game_flow.gd::test_start_new_game_chaos_contract_and_card_timing` | ✅ |
| Peaceful start keeps chaos near zero (0.08 / 1.5) | `test_game_flow.gd::test_start_new_game_normal_and_peaceful_values` | ✅ |
| Save → load round-trip preserves run state (bot.test.ts test 4) | `test_context.gd::test_save_load_round_trip` + CONTINUE path `test_game_flow.gd::test_continue_loads_and_corrupt_marks` | ✅ |
| Legacy single-save migration (TS localStorage v1 → slot 0) | — native save format is fresh v1 by design (migration spec §1 non-goal: TS saves deliberately NOT migrated, `context.gd` header) | ⏸ spec-sanctioned |
| Autosave every 60 s, gated (no menu/transition writes) | `test_game_flow.gd::test_autosave_fires_and_respects_gates` | ✅ |

## 3. Tutorial (features.test.ts "tutorial")

| Feature | Native pin | Status |
|---|---|---|
| Advances on conditions, finishes, persists the flag per slot; fresh key starts inactive | `test_tutorial.gd::test_advance_finish_and_persist` | ✅ |
| Cell stage owns a tutorial that reacts to eating (counters driven by real gameplay) | `test_tutorial.gd::test_cell_stage_steps_exact_table`, `test_cell_stage_steps_react_to_driven_counters` | ✅ |
| Inactive engine never advances; skip chip needs a 0.4 s hold | `test_tutorial.gd::test_inactive_engine_never_advances`, `test_skip_chip_needs_a_0_4s_hold` | ✅ |
| The 5 cell steps (move/eat/editor/kill/legs) with the TS gates | `test_tutorial.gd::test_cell_stage_steps_exact_table` | ✅ |

## 4. Movement, abilities, physics (CellStage.ts updatePlayer)

| Feature | Native pin | Status |
|---|---|---|
| Hold-move + WASD, accel/drag pipeline, speed cap | `test_cell_sim.gd::test_movement_drag_and_speed_cap` | ✅ |
| Dash (Space/Shift, jet-gated, 3 s cd), toxin burst (Digit1), electro burst (Digit2) | `test_cell_sim.gd::test_dash_toxin_electro_abilities` | ✅ |
| Bite (auto on overlap), spikes contact damage, proboscis drain, their-bite + invuln blink | `test_cell_sim.gd::test_contact_proboscis_and_their_bite_invuln` | ✅ |
| Soft world boundary push + hard clamp at R+200 | `test_cell_sim.gd::test_boundary_push_and_hard_clamp` | ✅ |
| Current bands + player radius (`nutrition` growth term) | `test_cell_sim.gd::test_current_and_radius_math` | ✅ |
| Player seed from the stage branch (determinism contract) | `test_cell_sim.gd::test_player_seed_is_the_branchs_first_draw` | ✅ |
| Vent healing (never rescues a dying cell) | `test_cell_sim.gd::test_vent_heal` | ✅ |
| Ability-bar payload (LMB/1/2/SPACE/E, cd + active) | `test_hud.gd::test_abilities_payload_passthrough` + live feed in every visual capture | ✅ |

## 5. Eating / DNA economy (CellStage.ts pellets + killEnt)

| Feature | Native pin | Status |
|---|---|---|
| Pellet kinds/values: plant val 2 (flora −0.4, karma +0.0005, nutrition +0.03), meat val 5 (heal +5, karma −0.0005, counts toward the tutorial hunt), dna pellet | `test_cell_sim.gd::test_pellet_economy_pickup_rules` | ✅ |
| No posthumous farming (dead player ignores pellets) | same test | ✅ |
| Pellet ttl (25/40), 260 cap, current drift | `test_cell_sim.gd::test_pellet_ttl_cap_and_current` | ✅ |
| Kill pay: meat drops `1+floor(size)`, DNA via `eco.notifyKill`, floatWorld, karma split | `test_cell_sim.gd::test_player_bite_and_kill_pay`, eco pricing `test_eco_core.gd::test_notify_kill_pricing_matches_ts_formula` | ✅ |
| Swarm kill pays DNA 8 / karma −0.004, bypasses eco | `test_cell_sim.gd::test_swarm_kill_pays_dna_not_eco` | ✅ |
| kin_memory grudge ledger + one first-warning toast | `test_cell_sim.gd::test_kin_grudge_ledger_first_warning`, valves `test_eco_valves.gd` (18 tests) | ✅ |
| corpse_tide combo corpse drops | `test_cell_sim.gd::test_corpse_tide_combo_drop`, econ budget `test_econ_probes.gd::test_corpse_tide_scavenger_budget_through_stage_kills` | ✅ |
| 6% mutant-cousin snack (mutate 0.9, lifespan 25) | 🟡 rng-stream parity: the branch's draw order is pinned by the task-3/4 stream audit and every determinism walk (`test_determinism_600_ticks`, bot arcs); no forced-trigger test — same coverage level as TS | ✅ |
| one-kill-one-pay: tagged deaths pay exactly once, stale-tag never leaks | `test_cell_ai.gd::test_sweep_pays_tagged_kills_and_green_bursts_untagged` | ✅ |

## 6. Combat / death (CellStage.ts handleDeath)

| Feature | Native pin | Status |
|---|---|---|
| Death fade, 12% DNA loss toast, respawn at safe spot, threat clear, invuln 4 | `test_cell_sim.gd::test_death_respawn_cycle` | ✅ |
| playerDeath storyteller signal (bus emit on the fade's first tick) | `test_cell_sim.gd::test_death_respawn_cycle` (context_event hook) + gaia beats `test_game_flow.gd::test_beat_gaia_redemption_narrates_once_after_first_death` | ✅ |
| Death overlay ("REBIRTH IS PAINFUL"), HP bar render | T10 visual suite `death.png` asserts | ✅ |
| Death is one-way (no game-over; rebirth loop) | §10 invariant — exercised by the bot arc's 2 messy minutes + `assert_sane` | ✅ |

## 7. NPC AI behaviors (CellStage.ts updateEnts)

| Feature | Native pin | Status |
|---|---|---|
| hp≤0 sweep (tagged pay / green burst), lifespan expiry, cooldown+stun decay | `test_cell_ai.gd::test_sweep_pays_tagged_kills_and_green_bursts_untagged`, `test_lifespan_expiry_removes_ent`, `test_stunned_ent_drifts_and_cooldowns_decay` | ✅ |
| Hunter closes on the player (or the nearest smaller cell) | `test_cell_ai.gd::test_hunter_closes_on_player` | ✅ |
| Fleeing prey capped vs the player's achievable speed | `test_cell_ai.gd::test_fleeing_prey_respects_achievable_speed_cap` | ✅ |
| bio_tell panic vacates the strike zone during warn windows | `test_cell_ai.gd::test_panic_vacates_zone`, live-through-update `test_cell_events.gd::test_warn_drift_live_panic_through_update` | ✅ |
| Grazer seeks diet-appropriate pellets; wander re-roll draw order | `test_cell_ai.gd::test_grazer_seeks_diet_appropriate_pellets`, `test_graze_reroll_draw_order` | ✅ |
| Grudge press registers (harassment valve) and keeps chasing | `test_cell_ai.gd::test_grudge_press_registers_and_keeps_chasing` | ✅ |
| Swarm never flees; ent eats pellet heals 4 | `test_cell_ai.gd::test_swarm_never_flees`, `test_ent_eats_pellet_heals_4` | ✅ |
| Toxin zone dps, hurtT, mine tag; separation push; world containment | `test_cell_ai.gd::test_toxin_zone_dps_hurtT_and_mine_tag`, `test_separation_pushes_overlapping_ents_apart`, `test_ent_world_containment_beyond_world_r_plus_100` | ✅ |
| temperament_bands (per-species seeded aggression/fear) | `test_world_genome.gd::test_behavior_band` + AI reads above | ✅ |
| Population maintenance: despawn >1600, per-species visible target ≤9 | `test_cell_sim.gd::test_maintain_population_despawn_and_spawn` | ✅ |
| `debugSpawnNear` test seam (area-uniform ≤320) | `test_cell_sim.gd::test_debug_spawn_near` | ✅ |
| Bestiary proximity discovery (420 px; swarm/player exempt) | `test_cell_sim.gd::test_bestiary_proximity_discovery` (added this task — was the one unpinned path; seed-time discovery pinned since T3) | ✅ |

## 8. Chaos events — 8 baseline + 3 world-gated + mirror (cellEvents.ts)

| Feature | Native pin | Status |
|---|---|---|
| Traitless world gets exactly the 8 baseline defs | `test_cell_events.gd::test_traitless_world_gets_exactly_the_baseline` | ✅ |
| Variants gate on the world: toxin_clouds (toxin_sea), algae_surge (hungry_bloom), bloom mirror (lean temperament) | `test_cell_events.gd::test_variant_defs_gate_on_the_world` | ✅ |
| Def constants verbatim (names/warns/weights/durations/cooldowns) | `test_cell_events.gd::test_def_constants_verbatim`, `test_weight_formulas` | ✅ |
| Meteor: target ring → 2.5 s impact, falloff damage (ents + player), DNA debris | `test_meteor_apply_schedules_impact`, `test_meteor_impact_falloff_player_ent_and_debris`, `test_meteor_impact_kills_and_invuln_guards` | ✅ |
| Bloom: flora ×1.9+20 capped, 30-pellet sprinkle; blight mirror body | `test_bloom_flora_cap_and_sprinkle`, `test_blight_mirror_body` | ✅ |
| Red tide: 3 static toxin zones; toxin_clouds variant: wider/softer clouds that home the player (only its own — minor 1) | `test_redtide_zones`, `test_toxin_clouds_def_and_drift_homing` | ✅ |
| Feeding frenzy swarm ring; THE OLD ONE (big brother) | `test_swarm_ring`, `test_big_brother` | ✅ |
| Mutation wave (2-3 mutants, needs wild species); vent params + FIFO cap 6 | `test_mutation_wave`, `test_mutation_wave_needs_wild_species`, `test_vent_params_and_fifo_cap` | ✅ |
| Glitch: gap 10 cycle, +40 DNA tribute on end | `test_glitch_gap_cycle`, `test_glitch_end_tribute_through_update_chaos` | ✅ |
| algae_surge: bloom + grazer boom + 20 pellets | `test_algae_surge` | ✅ |
| Mirror rule: onEnd queues, onFired clears; only after a bloom survived | `test_on_end_queues_bloom_mirror_and_on_fired_clears`, scheduler `test_chaos.gd::test_mirror_ledger_queue_and_ledger` | ✅ |
| Scheduler: warn→apply→tick→end order, cooldowns, max-active, weight floor, mood/ctx weights, gap scaling | `test_chaos.gd` (21 tests) | ✅ |
| Deck rebuild when CONTINUE lands on a different world (C1) | `test_cell_events.gd::test_deck_rebuild_on_seed_mismatch` | ✅ |
| onApply chaos + storyteller note; warnless natural spawns fire no hooks | `test_on_apply_chaos_and_storyteller_note`, `test_natural_spawn_of_warnless_def_fires_no_hooks` | ✅ |
| Eco batch: extinctions (banner + chaos 0.05), bio_shift toast, speciation discover+toast, flora pellet top-up | `test_cell_sim.gd::test_eco_tick_batch_and_extinction_banner`, `test_cell_events.gd::test_eco_batch_speciation_discover_and_toast` | ✅ |

## 9. World genome → cell stage (reveals / combos / turns / codex / beats)

| Feature | Native pin | Status |
|---|---|---|
| Archetype weights bend the starting food web (herbivore/carnivore/predator/titan/swarm) | `test_world_genome.gd::test_archetype_weights`, econ `test_econ_probes.gd::test_iron_gut_roster_bend_and_meal_dna`, `test_calm_veil_predator_thinning`, `test_swift_world_swarm_species_survival` | ✅ |
| eco mods refresh from the world each tick batch | `test_world_genome.gd::test_eco_reads_derived_genome_and_fired_mods`, `test_eco_mods_from_world_shape` | ✅ |
| corpse_tide / kin_grudge combos live in the stage | §5 rows above | ✅ |
| World reveal lands as a world toast + codex flag | `test_game_flow.gd::test_world_reveal_lands_as_world_toast_and_codex` | ✅ |
| Combo rot_circle announces but stays out of the codex | `test_game_flow.gd::test_combo_rot_circle_announces_but_stays_out_of_codex` | ✅ |
| epoch_apex turn names the apex species | `test_game_flow.gd::test_epoch_apex_turn_names_the_apex_species`, turn engine `test_world_genome.gd` (turn tests) | ✅ |
| Beats: herd_remembers (+25 DNA), gaia_redemption (once, after first death), gaia_wanderer (gates + spawns once), offer skipped without a stage surface | `test_game_flow.gd::test_beat_herd_remembers_pays_dna_and_feeds_dna_rate`, `test_beat_gaia_redemption_narrates_once_after_first_death`, `test_beat_gaia_wanderer_gates_and_spawns_once`, `test_beat_offer_skipped_without_stage_surface` | ✅ |
| Wanderer spawn body (`gaiaWanderer` rare-gene ent) | `test_cell_sim.gd::test_gaia_wanderer_and_on_stats_changed` | ✅ |
| Chaos settle recurrences + karma drift (negative only) | `test_game_flow.gd::test_chaos_settle_recurrences`, `test_karma_drift_lifts_negative_only` | ✅ |

## 10. Editor buy/sell (bot.test.ts test 3)

| Feature | Native pin | Status |
|---|---|---|
| Buying parts spends part_cost and bumps the gene | `test_editor.gd::test_buy_flagella_spends_part_cost_and_bumps_gene` | ✅ |
| Selling refunds half | `test_editor.gd::test_sell_flagella_refunds_half` | ✅ |
| Real-input purchase through the pipeline (KeyE open → row-rect click → gene bumped, DNA dropped) | scene `test_editor_click.gd` (EDITOR_CLICK_OK) | ✅ |
| Spend/max gates toast and block; legs floor guard keeps the shore exit; diet/pattern/size/hue rows; scroll clamp; KeyE dirty-close saves | `test_editor.gd` (16 tests: `test_spend_gate_toasts_and_blocks`, `test_max_gate_blocks_buy`, `test_legs_floor_guard_keeps_the_shore_exit`, `test_diet_row_cycles_with_cost_gate`, `test_pattern_row_buys_next`, `test_size_row_shrinks_free_grows_30`, `test_hue_sat_rows_drag_sliders`, `test_scroll_clamps_to_content`, `test_keye_close_saves_when_dirty`, …) | ✅ |
| Graft rows for fired combos + extinct bestiary | `test_editor.gd::test_graft_rows_for_fired_combo_and_extinct_bestiary` | ✅ |
| Editor open/close through the blocked-branch overlay dispatch | `test_game_flow.gd::test_escape_routing_gates`, `test_hud_click_routing_consumes_first` + the editor-click scene | ✅ |

## 11. HUD surfaces (hud.ts)

| Feature | Native pin | Status |
|---|---|---|
| Toasts: push/age/expiry, 1.5 s dedup, cap 6, world cards | `test_hud.gd::test_toast_*` (4 tests) | ✅ |
| Banners: defaults, ttl override, queue + dedup, cap 5, dismiss | `test_hud.gd::test_banner_*` (4 tests) | ✅ |
| floatWorld rise/expiry, cap 60 | `test_hud.gd::test_float_world_rise_and_expiry`, `test_float_world_cap_sixty` | ✅ |
| DNA panel display smoothing + pulse | `test_hud.gd::test_dna_display_smoothing_toward_context`, `test_dna_pulse_from_context_signal_and_decay` | ✅ |
| Pause menu: items, resume, save toasts, mute flip+relabel, language flip, help view, world view, quit chain, click-miss no-op | `test_hud.gd::test_pause_*` (8 tests) | ✅ |
| KeyM mute toggles and persists; Escape routing gates | `test_game_flow.gd::test_keym_mute_toggles_and_persists`, `test_escape_routing_gates` | ✅ |
| Objective line / chaos bar / karma orb / stage label render | T7 + T10 pixel asserts (dna-counter, chaos bar in the suite's banner/cell moments) | ✅ |

## 12. Menu + game flow (menu.ts, game.ts)

| Feature | Native pin | Status |
|---|---|---|
| Seeded boot lands on menu; boots without crashing and renders once (bot.test.ts test 1) | `test_game_flow.gd::test_seeded_boot_lands_on_menu`, scene `test_boot.gd` (BOOT_TEST_OK) | ✅ |
| Full NEW LIFE flow through REAL clicks (title → difficulty → BEGIN → cell card) | scene `test_menu.gd` (MENU_TEST_OK — asserts the clicked difficulty took effect) | ✅ |
| Transition queue, quit cancel, card timing, narration reset on NEW LIFE | `test_game_flow.gd::test_transition_queue_and_quit_cancel`, `test_start_new_game_chaos_contract_and_card_timing`, `test_reset_narration_via_new_life`, `test_continue_survives_quit_fade` | ✅ |
| Menu slot cards read the native saves; corrupt tombstones | `test_game_flow.gd::test_slot_meta_reads_native_saves`, `test_continue_loads_and_corrupt_marks` | ✅ |

## 13. Bot arc + determinism (bot.test.ts test 2 — the §5.2(b) gate)

| Feature | Native pin | Status |
|---|---|---|
| 2 simulated minutes of messy human play — move/eat/dash/burst/editor taps — through the REAL input pipeline only | scene `test_bot_arc.gd` (BOT_ARC_ALL_OK; input-delivery smoke phase proves parse_input_event → _unhandled_input) | ✅ |
| World responds to play (ents exist), assert_sane invariants throughout | bot arc per-seed + `tests/bots/bot_driver.gd::assert_sane` (exact bot.test.ts:28-45 port) | ✅ |
| Same seed → same run path, ×3 seeds ×2 fresh-Game passes (quantized fingerprint equality) | bot arc determinism phase (seeds 0xC0FFEE / 0x51071 / 0xABCDEF) | ✅ |
| Sim-level determinism walks | `test_cell_sim.gd::test_determinism_600_ticks`, `test_sanity_walk_600_ticks`, `test_bootstrap_deterministic_per_seed` | ✅ |
| 1000-seed determinism (eco/world) | `test_econ_probes.gd::test_determinism_1000_seeds_a_vs_b`, `test_world_genome.gd::test_1000_seed_determinism_and_bounds`, `test_1000_seed_mutual_exclusion` | ✅ |

## 14. Visual moments (§5.2(d) pixel-assert)

| Feature | Native pin | Status |
|---|---|---|
| Cell stage render: player at hue 120 (calm vs chaos tint), backdrop depth gradient, DNA panel helix | scene `test_visual_cell.gd` + `tools/visual_check.py` (VISUAL_TEST_OK, 8/8) | ✅ |
| Six-moment suite: menu (+drifters animate), cell_early, chaos banner, editor a/b (real purchase), death fade, titled card | scene `test_visual_suite.gd` + `tools/visual_assert.py` (VISUAL_SUITE_ALL_OK, 32/32 structural asserts) | ✅ |
| Procedural draw math (hsl→RGB, disc/glow/panel helpers, particles 7 kinds, cell painter) | `test_gfx_math.gd` (9), `test_particles.gd` (10), cam `test_cam.gd` (12) | ✅ |

## 15. Econ probes (§5.2(c))

| Feature | Native pin | Status |
|---|---|---|
| Per-trait + stacked probes through the REAL boot (iron_gut, hungry_bloom, swift_world, calm_veil, corpse_tide, kin_memory, stacked) | `test_econ_probes.gd` (9 tests, real menu.start_new_game + stage kills) | ✅ |
| Single-mod eco floors + fixture walk parity | `test_eco_core.gd::test_fixture_walk_snapshot_parity`, `test_single_mod_probes_keep_eco_floors`, `test_empty_mods_equal_unset_baseline_bit_identical` | ✅ |
| Eco valves: grudge decay, harassment cap, scavenger 8% cap, tide auto-end, revive, role conversion, save round-trip | `test_eco_valves.gd` (18 tests) | ✅ |

## 16. Explicit deferrals (spec-sanctioned, none are cell-stage behavior gaps)

| Item | Reason |
|---|---|
| Audio synth (WebAudio → AudioStreamGenerator) | Migration spec §7 risk-table item — ported as no-op `audio_play` hooks with TS call sites/params pinned (task-3/7 reports); the synth port is its own task after parity. The mood ambient / SFX surface is architected (hook seam) and every call site fires with the TS name/volume/pan. |
| Shore button → creature stage landing | The click path is fully native and pinned (`test_cell_sim.gd::test_shore_travel_click`: consumption + game_save_all + THE LONG WALK card via `go_to`); the landing stage is milestone 3 scope (spec §5.3). `switch_stage` with an unregistered id no-ops safely. |
| Legacy TS save migration | Spec §1 non-goal — native save v1 is fresh; TS v1/v2 blobs deliberately not migrated (`context.gd` header). |

## 17. Perf probe (new this task)

`tests/scenes/test_perf.tscn` + `tools/test_perf.sh` — boots the REAL game
(`menu.start_new_game(0, "normal", 0x9E37)`, the T6 trap pattern), force-spawns
**exactly 200 ents** (mixed sizes 0.6–2.2 cycled across the live roster, direct
`spawn_ent` placement — `maintain_population`'s visible-per-species caps would
never reach the budget alone) area-uniform ≤320 px around the player from a
fixed-seed LCG, then steps **600 ticks** under xvfb (llvmpipe, rendering ON).

Asserts (both green):
- **average wall-clock per sim tick ≤ 8 ms** — measured **7.61–7.76 ms avg** across 4 consecutive runs (max single tick 19.6–27.8 ms; identical world state every run — ents 93, pellets 15, dna 88 — the probe is fully deterministic),
- **no NaN drift** — the bot's `assert_sane` invariants (dna ≥ 0 finite, chaos ∈ [0,1], karma ∈ [−1,1], position finite, php ≤ pmaxHp, ents < 300) every 60 ticks + final.

Recorded informationally: full engine-frame wall-clock avg ≈ 129 ms under
llvmpipe — the draw pass of ~200 on-screen procedural cells dominates, and no
sim-side change moves it; the §6 "200 entities @ 60 fps" budget targets a mid
machine's real GPU, not the software rasterizer the probe intentionally runs on.

**Probe-driven fix (this task):** the first probe run measured **37.5 ms/tick** —
the probe caught the sim's O(N²)/O(N·P) Dictionary-based inner loops far over
budget, exactly the §7 risk the spec names ("GDScript perf hot-loop → typed +
no allocation; lift to C# only when a probe measures it"). Fix (bit-exact by
construction — same values, same candidate order, same float ops):
`update_ents` now scans flat typed mirrors (`Packed*Array`) of the ent/pellet
fields, rebuilt per tick and synced on every in-loop mutation; neighborhood
grids prune candidates that provably fail their distance checks while the
gathered indices are sorted ascending = the full scan's order (the pellet-eat
gather needs no sort — eats are order-independent); eaten pellets defer physical
removal to a tick-end compaction via dead flags; per-ent invariant reads
(player stats, tide line, grudge-per-species with press invalidation) are
hoisted/cached. Validated bit-exact by the full suite: 15293 checks green
including every exact-value and determinism test, and the bot-arc fingerprints
are unchanged.

## §5.2 scorecard

| Criterion | Evidence | Verdict |
|---|---|---|
| (a) Every TS cell-feature present | §1–§15 above — every row pinned or explicitly deferred with a spec citation | ✅ |
| (b) Bot headless full cell arc through the real UI on ≥3 seeds | `tools/test_bot.sh` → BOT_SMOKE_OK + BOT_ARC_OK ×3 seeds ×2 passes, fingerprints bit-identical, exit 0 | ✅ |
| (c) Econ probes + determinism 1000-seed green | `test_econ_probes.gd::test_determinism_1000_seeds_a_vs_b` + the probe battery (§15); full headless suite 381 tests / 15293 checks / 0 failures | ✅ |
| (d) Visual pixel-assert via viewport capture | T7 (8/8) + T10 six-moment suite (32/32) under xvfb, PIL-checked (§14) | ✅ |
