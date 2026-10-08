# Experience redesign — implementation ledger

Branch `experience-redesign`, worktree `/home/misa/Desktop/RD/primordia-native-redesign`.
Base `6754bae` (`ci: re-datum RID ceiling 403→411` — the Task 1 baseline).
Plan: `2026-10-07-experience-redesign.md`; spec: TS repo
`docs/superpowers/specs/2026-10-07-experience-redesign-design.md` (its
"Implementation" section carries the deviation digest).

## Final verification (Task 16)

| gate | result |
|---|---|
| Full suite | **77 files, 1033 tests, 23627 checks, 0 failures** — exit 0, `script-error guard: 0 script error(s)` (`timeout 900 ./tools/test.sh`, foreground) |
| RID datum | `WARNING: 411 RIDs of type "CanvasItem" were leaked.` — **411 = the standing ceiling, ZERO growth** (the new pacifist-arc test boots the five real stages OUT of the tree — no canvas RIDs boot — so no leak fix and no re-datum was needed) |
| A-B | `tools/ab_test.sh 6754bae` → **`AB_TEST_OK verdict=IDENTICAL`**, diff_lines=0, base dump sha = head dump sha = `ea35920ba80ee7553ed056797680ebc95cc6224fe2d1fd9074c8911ef83ddfcf` — bit-identical to the Task 1 baseline |
| BOT_SPACE scene gate (deferred from Task 15) | **`BOT_SPACE_ALL_OK`, `BOT_SPACE_EXIT=0`** — the two passes' end fingerprints matched field-for-field (the scene prints `BOT_SPACE_OK` only on a field-exact determinism match): `endingDone: true`, karma 61, extinct 0, three thriving seeded planets (p0/p1/p2 pops 2256/5177/2256, live 6/5/5), abducts 3, spliced cargo, dna 1179, `time: 5041`; `timeout 1800`, foreground, the wrapper's godot invocation against THIS worktree (its script hardcodes the main checkout) |
| Pacifist end-to-end | **HARMONY reached, ZERO kills** — `tests/test_pacifist_arc.gd` (see below) |

## Per-task commits + suite tails

Suite tail format `files/tests/checks/failures`; every batch's RID line is
`411` (the standing ceiling) unless noted. Verbatim tails live in each
task's report under `.superpowers/sdd/2026-10-07-experience-redesign/`.

| task | commits (6754bae →) | suite tail | notes |
|---|---|---|---|
| T1 baseline | (none — clean tree at `6754bae`) | 61 / 856 / 22446 / 0 | RID 411 = ceiling, no headroom; A-B baseline sha `ea35920b…` |
| T2 R3 progress arc | `ebd3f57` | 62 / 865 / 22554 / 0 | arc states static; RID 411 |
| T3 R2 objective chip | `eed23de` | 63 / 875 / 22597 / 0 | RID 411 |
| T4 R1 micro-tutorials | `7be31e3` | 64 / 883 / 22707 / 0 | hut step = snapshot-at-step-entry ruling; RID 411 |
| T5 R11 creature card renderer | `d7a7ff5` + `df94b53` (doc-only fix round) | 65 / 891 / 22764 / 0 | RID-safe registry; consumer contract (clear-before-draw + release(ci)); RID delta 0 ×3 |
| T6 R6 free LOOK tab | `f33154b` + `1cd27b7` (re-rule reconcile) + `2242c6e` (cd fix) | 66 / 907 / 22831 / 0 | zero PATTERNS/COATS prices in parts.gd data (re-rule); A-B dump sha IDENTICAL `ea35920b…`; editor-click wrapper cd script-derived |
| T7 R7a creature naming | `3a2626b` + `012ca0b` (docs) | 67 / 923 / 22911 / 0 | picker chain green under xvfb, name=Mosi; RID 411 |
| T8 R7b audio core | `f7950fa` | 68 / 936 / 22980 / 0 | built from scratch (the frozen TS repo has no audio graph); genome rides the vol slot; RID 411 |
| T9 R9+R8 packmate identity + bestiary | `25021df` | 70 / 955 / 23073 / 0 | extinction-card transient contract; PACK_ROW_SCENE_OK registry-empty teardown; RID 411 |
| T10 R15 karma profile | `e964eeb` | 71 / 967 / 23157 / 0 | per-stage profile at the switch seam; graze 0.02→0.005/s; cap centralized in add_karma; A-B IDENTICAL |
| T11 R13 chaos scars + transposon | `2d22a78` | 72 / 986 / 23296 / 0 | transposon latch in ctx.flags; A-B IDENTICAL |
| T12 R4 death debrief | `8c0037b` + `77b0244` (i18n fix round) | 73 / 993 / 23389 / 0 | 10 causes from every death codepath; vi rows "quyến rũ"/"đàn"; civ no-death-path verified |
| T13 R10 genome showcase | `a4c751f` | 74 / 1002 / 23424 / 0 | card lines on the transition card; U+2212 glyph; RID 411 |
| T14 R12 heredity ledger | `7f935da` | 75 / 1020 / 23501 / 0 | balance probe **baseline 43.6 s, predator+conduct 33.5 s, ratio 0.769** (gate ≥ 0.600 — no clamp applied); RID 411 |
| T15 R14 world attach + pacifist viability | `88b91f4` | 76 / 1032 / 23600 / 0 | pacifist probe **989.0 s ≤ 1200** under the hearts-regen culture knob **0.006 → 0.014**; armada ecoHealth-0 = 4 launches; tribe-fall DNA floor 50, no loop; `test_bot_space` scene gate DEFERRED to Task 16 (ruled) |
| T16 final verification | `1e4be3e` (pacifist-arc test + A-B evidence refresh) + the ledger commit | 77 / 1033 / 23627 / 0 | see the Final verification table above |

**Probe-drift note (Task 16, disclosed — no code touched):** the standing
suite at HEAD prints `R12 balance probe: baseline 33.5s, predator+conduct
33.5s, ratio 1.000 (gate ≥ 0.600)` — the gate still passes, but the
differential collapsed vs T14's 0.769. Mechanism: the probe
(`test_heredity_ledger.gd _probe_time`) builds its ctx inline without the
file's own R14 `ecoHealth = 0.0` pin (`_mk_sim` has it; the probe does not),
so BOTH legs ride the R14 missing-snapshot neutral (+6 output) — the
baseline's extra regen waits vanish and both runs land on the same
launch-cooldown/flight floor (33.5 s, the predator leg's T14 time,
unchanged). The gate's binding claim (the predator line must never be the
SLOWER route) holds at equality; the diagnostic headroom is a rig artifact,
not a balance regression. Re-pinning the probe to the file's declared rig
(output 10 vs 12, the T14 comparison) is a one-line follow-up left to the
controller — Task 16 does not re-open reviewed rigs unilaterally.

## Task 16 — the pacifist end-to-end proof

The spec's binding definition: the pure 0-kill route must REACH the harmony
ending (karma > 0.3 AND the R15 profile floor `karma_min() ≥ −0.1`). No
single bot covers the whole arc (the scene bots ride the attack route; the
pacifist civ bound exceeds the scene frame budget — the task-15 documented
deviation), so the run is COMPOSED: the five REAL stage sims of one real
Game on one context, each leg riding its established sim-level pattern
(`tests/test_pacifist_arc.gd` header documents the composition), crossing
the REAL `switch_stage` seam between legs.

Composition per leg: cell = park-the-wild-ents isolation + contact-eat
forage + three REAL `spawn_pellet("meat")` carrion (the scavenge channel) +
the REAL editor `click_part` legs buy (65 DNA) + the REAL shore click;
creature = the test_charm beat-tick charm ×2 + the graze channel + the REAL
`found_tribe()` (whose REAL on_exit writes the R14 ecoHealth snapshot);
tribe = the REAL gathering economy up the REAL totem gate (festival FIRST —
the REAL `festival()` action; no warrior role ever assigned; raid defense is
the villagers' own auto-fight), totem-victory to `victoryFired`; civ = the
task-15 `pacifist_run` policy verbatim (A×4/W×7/E×7, wait; launches must
stay 0); space = the test_probe_space finale pattern (3 colonies seeded at
19.5 pop — the probe's direct-seam precedent — REAL ff to the trigger, the
core approach → `endingDone`).

Verbatim evidence (`PACIFIST_ARC_*` lines in the suite log):

```
PACIFIST_ARC_TRACE {"cell_eaten":8,"cell_exit_karma":0.001,"cell_time":5.88,"civ_culture":10,"civ_econ":12,"civ_exit_karma":0.373,"civ_output":22,"civ_time":989.016,"creature_exit_karma":0.113,"creature_time":12.2,"eco_health":1,"final_karma":0.373,"flavor":"The universe hums in harmony — you gardened the stars.","karma_min":0.001,"tribe_exit_karma":0.223,"tribe_time":59.36}
PACIFIST_ARC_PROFILE [0.001,0.113,0.223,0.373]
PACIFIST_ARC_KILLS 0
PACIFIST_ARC_ENDING The universe hums in harmony — you gardened the stars.
```

The civ leg's 989.0 s at output 22 reproduces the task-15 probe exactly;
ecoHealth 1.0 came from the REAL creature-leg on_exit (not a seed). The
profile's four exits all clear the −0.1 floor; the final karma clears the
0.3 gate with margin (0.373).

## Deviations (standing, reviewer-ruled)

1. **i18n charm fix already-native** — the TS spec's vi terminology debt
   ("thu phục" → "quyến rũ", "bầy" → "đàn") was fixed natively in the T12
   fix round (`77b0244`); the TS repo carries no code change for it.
2. **Output-formula rescale ×2 cap 22** (R14) — the civ start output stacks
   conduct ±2 (T14) AND the ecoHealth snapshot (×12 of health) on the TS
   base 10, hard cap 22 on the SUM (`civ_sim.on_enter`); the TS spec's
   "±2 on rivalDefFor" note is the T14 conduct half only.
3. **Tribe-fall retarget** — the fall path floors DNA at 50 and re-founds
   through the REAL `on_enter` (the restore-resurrection loop stays dead);
   the TS restore path is not the re-entry vehicle.
4. **Audio core built from scratch** (R7b) — the frozen TS repo has no
   audio graph; a minimal core (creature call first) ships with the genome
   -in-vol-slot payload and queue-time mute.
5. **Intro lines on the transition card** (T14 ruling, controller-ratified) —
   the objective channel is single-slot and its whole string goes through
   `tr_key` at draw; the R10 showcase is the precedent.
6. **Coat catalog-order scoring** (T14 ruling, controller-ratified) — the
   categorical coat gene scores as its position in the COATS defense order
   (skin 0 → plates 3); the default genome stays predator, wall rarest by
   construction.
7. **`has_trait` accessor** (T15) — the trait gates read the trait ID via a
   new `WorldGenome.has_trait` (hungry_bloom carries no flag effect, so
   `world_has` cannot see it); a traitless world folds byte-identical to
   the TS baseline.
8. **Pacifist bots are sim-level** (T15 + T16) — the 1200 s game-time bound
   makes the xvfb scene gate infeasible (the scene bots cap TIMEOUT_FRAMES
   for the whole arc); the drivers step `sim.update(dt, inp)` on the M2
   input-SNAPSHOT surface, no debug seams during play.

## Task-16 composition rulings (this task's own disclosures)

- The pacifist arc drops each leg's armed card transition at the seam (the
  REAL `go_to` hook DID fire — ascend audio, the real save_all, the card —
  the composition walks past the fade and calls the REAL `switch_stage`).
- Chaos rides the probe rig (`sim.chaos.gap = 1e9` per leg — the pacifist
  proof pins the karma ROUTE, not the chaos stress); every leg
  deterministic per seed `0xC1A55`.
- The cell leg's carrion is spawned by the REAL `spawn_pellet("meat")`
  (the wild-ent isolation removes AI deaths, not the carrion channel); the
  scavenge karma (−0.0005 × 3) rode the real pellet path.
- The run's REAL saves (shore `save_all`, `found_tribe` flush, the tribe
  victory's `save_all`) land on test slot 153 (90-152 spoken for).
- The deferred `test_bot_space` gate ran via its exact godot invocation
  against THIS worktree — the wrapper script's `cd ~/Desktop/RD/
  primordia-native` hardcode names the main checkout (the task-6 deferred
  honest-cd pass; no plan task had used those wrappers).
