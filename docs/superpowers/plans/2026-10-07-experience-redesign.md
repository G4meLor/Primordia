# Experience Redesign (Batches 1–3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved experience redesign — 16 proposals (R1–R16) across 3 batches: onboarding trio, "creature identity", cross-stage continuity — in the Godot native repo, suite green at every step.

**Architecture:** Godot 4.2.2 + typed GDScript. Sim layer = headless-testable RefCounted sims driven by thin stage Nodes; HUD/editor/tutorial are per-stage overlay Uis. TS repo `/home/misa/Desktop/RD/Spore/src/` is the frozen behavioral reference (parity law). New systems attach through existing seams: `hud.gd` overlay dict, `context.gd` flags/persist_state, stage `on_exit`, chaos deck fold (`make_*_chaos_events(world)`), `audio_play` hook (currently a noop), `draw_creature` painter (caller-owned RIDs).

**Tech Stack:** Godot 4.2.2 (Compatibility renderer, zero plugins), GDScript typed, custom TestBase harness (`tests/test_base.gd`), two-pass runner (`tests/run.gd`), xvfb for scene/pixel tests.

**Spec:** `/home/misa/Desktop/RD/Spore/docs/superpowers/specs/2026-10-07-experience-redesign-design.md` (commit c7376c5 in the TS repo). The plan argues from the spec; implementers read both. Where this plan deviates from the spec (9 parity corrections found by exploration), the plan is authoritative and the deviation is stated inline.

## Global Constraints (every task)

1. **Shell cwd resets to `/home/misa/Desktop/RD/Spore` between commands.** Always prefix: `cd /home/misa/Desktop/RD/primordia-native && …`.
2. **Single Godot instance law:** never run the suite while an editor/other godot process has this project open (project cache collision).
3. **Suite gate per task:** `./tools/test.sh` → must print `0 failures`, RID leak line ≤ 411, exit 0. Suite currently 61 files / 856 tests / 22446 checks / RID 411 (= ceiling). If your task's tests legitimately add CanvasItem boots and RID count rises, do NOT ignore it — bisect and re-datum with evidence (see Task 16 procedure); a silently raised leak count is a failure.
4. **Tests:** every test file `extends "res://tests/test_base.gd"` (referenced by path, not class_name), methods `test_*`, no throws (record failure via `ok()/eq()/approx()`), fresh instance per test. Float fixtures: `approx(a, b, eps >= 1e-9)` — never eps 0.0. RNG pinning = uint32-exact `roundi(v * 4294967296.0)`.
5. **Sim purity:** no `randi()/randf()` in sim code — Mulberry32 only, mask `& 0xFFFFFFFF` on every bitwise op, `_imul(a,b) = (a*b) & 0xFFFFFFFF`; GDScript `%` is int-only → use `fmod` for floats.
6. **Save wire:** dict keys TS-verbatim camelCase. New persisted fields: write in `to_save_data`, read in `load` with `.get(key, default)` + type check — native save is fresh v1 (no TS tombstone), this pattern is backward-safe.
7. **i18n contract:** display literals wrapped `tr_key(...)` inline at draw; sim composes text → `tr` BEFORE the call; new user-facing strings need both EN literal + `assets/i18n/vi.csv` row.
8. **X11 cursor-shape swallow quirk:** do not modify `hover_cursor()` / cursor-change flow in `game.gd` (sticky-flag fix is load-bearing).
9. **RID lifecycle:** `creature_painter.draw_creature()` returns caller-owned RIDs `{clip_item, pattern_item, front_item}` — every consumer MUST `RenderingServer.free_rid()` all three when done. Any new draw path in tests must free RIDs or the CI RID gate fails.
10. **A-B dump (`tools/ab_test.sh`) covers cell sim ONLY.** Cell-sim-behavior changes must keep `tests/fixtures/ab/evidence.txt` sha stable unless the task says otherwise; other stages rely on unit tests + bots.
11. **TS repo is frozen** — read-only reference; never edit files there.
12. **i18n bug "cồn cát": already fixed in native** (`vi.csv:75` is correct) — no task for it; do not touch `vi.csv` line.
13. **R5 notification-channel discipline (standing rule):** no NEW narrative content through toasts — toasts are for micro-acknowledgment only; content the player must remember (warn details, death lessons, guidance) goes through banners/cards/overlays. World/species cards are the pattern.
14. **Spec §6 cuts are binding non-investment rules:** no new editor part-stats/levels, no new storyteller beats, no new eco-touching traits (new traits target civ/space only), no multi-planet sim deepening, no charm-rhythm tuning, no PNG-embed/seed-sharing.

**User decisions (already made):**
- "Chốt rồi, bạn làm toàn bộ đi" (2026-10-07) — all 3 batches approved as spec v1.0.
- Spec verdicts binding: 9 KEEP, 6 MODIFY, R16 CUT/defer; cuts list (§6 of spec) stands; no civ DNA sink; no new UI before its text version; cheap-first for R12/R13.
- Approved deviations found during planning (recorded here, don't re-litigate):
  (a) i18n fix dropped — already correct in native;
  (b) R14 output formula rescaled: TS start output is 10 (not 8) → bonus `+ round(ecoHealth × 2)` capped +12 (total ≤ 22), balance probe mandatory;
  (c) "Chief death" adjustment re-targeted to the real one-way door — tribe-fall gets a rebirth floor (chief death already taxes 15% + respawns in place);
  (d) R7 split: naming (7a) is pure UI/state; the creature call (7b) builds a minimal audio core from scratch (no audio layer exists in native; the `audio_play` hook seam is a noop).

---

### Task 1: Baseline — clean tree, green suite, evidence captured

**Goal:** Start every later task from a verified-clean state: untracked QC litter removed, suite proven green at HEAD, RID datum captured.

**Files:**
- Delete (untracked): `tests/scenes/qc8_*.gd`, `tests/scenes/qc8_*.tscn`, `tests/scenes/qc9_*.gd`, and any other untracked `qc*` files (19 untracked, none touch `src/` — verify with `git status --short` first).

**Acceptance Criteria:**
- [ ] `git status --short` shows no untracked files (working tree clean at `6754bae`).
- [ ] Suite green: `61 files / 856 tests / 22446 checks / 0 failures`, RID ≤ 411, exit 0.
- [ ] Baseline evidence saved: suite tail + RID line pasted into the execution ledger.

**Verify:** `cd /home/misa/Desktop/RD/primordia-native && git status --short | wc -l` → `0`, and `./tools/test.sh` → green tail.

**Steps:**
- [ ] Step 1: `cd /home/misa/Desktop/RD/primordia-native && git status --short` — confirm every untracked path matches `qc8_*`/`qc9_*` probe patterns under `tests/scenes/`. If ANY other path is untracked or modified, STOP and report to coordinator instead of cleaning.
- [ ] Step 2: `git clean -f tests/scenes/qc8_* tests/scenes/qc9_*` (and matching qc9 .gd files). Re-run `git status --short | wc -l` → `0`.
- [ ] Step 3: `./tools/test.sh` — capture the last ~15 lines (counts + RID + exit) into the ledger as the baseline.
- [ ] Step 4: No commit (nothing tracked changed).

---

### Task 2: R3 — Progress Arc 5-stage HUD widget

**Goal:** A 5-node arc (Cell → Space) on every stage's HUD: current stage node bright, later nodes dim, next-milestone tooltip line — the player always sees where they are in the journey.

**Files:**
- Modify: `src/ui/hud.gd` (add arc section; stage list at :24; render entry near stage-name draw :301-302)
- Modify: `assets/i18n/vi.csv` + EN literals inline (2 new keys)
- Test: `tests/test_hud_arc.gd` (create)

**Acceptance Criteria:**
- [ ] Pure function `arc_states(stage_id) -> Array` (5 entries, each `bright | dim | done | current`) exists and is unit-tested for all 6 stage ids (menu = all dim).
- [ ] Arc renders on every stage HUD: 5 numbered dots + labels Cell/Creature/Tribe/Civ/Space connected by a line; current stage bright (accent color), stages after current dim, before-current drawn as done.
- [ ] Tooltip line under arc: next milestone text per stage, i18n'd (e.g. cell → "next: buy a LEG → shore", creature → "next: brain ×3 + pack 2 → tribe"). Both languages.
- [ ] Stage name label (old dim 10px text at :301-302) is absorbed into the arc (removed or restyled as part of it — no duplicate stage name).
- [ ] Suite green; no new leaked RIDs (arc is plain CanvasItem drawing in the existing hud `_draw`, no sub-RIDs).

**Verify:** `./tools/test.sh` → green; `grep -c "arc" src/ui/hud.gd` ≥ 4.

**Steps:**
- [ ] Step 1: Read `src/ui/hud.gd` fully and `src/game/stage.gd` (stage ids). Read TS `src/ui/hud.ts:184` + spec R3.
- [ ] Step 2: Write failing tests in `tests/test_hud_arc.gd`:
  ```gdscript
  extends "res://tests/test_base.gd"
  func test_arc_states_cell() -> void:
      var st: Array = HudUi.arc_states("cell")
      eq(st.size(), 5, "5 nodes")
      eq(st[0], "current", "cell is current")
      for i in range(1, 5): eq(st[i], "dim", "later nodes dim")
  func test_arc_states_space() -> void:
      var st: Array = HudUi.arc_states("space")
      for i in range(4): eq(st[i], "done", "earlier done")
      eq(st[4], "current", "space current")
  func test_arc_next_hint_cell() -> void:
      ok(HudUi.arc_next_hint("cell").length() > 0, "hint text exists")
  ```
- [ ] Step 3: Implement `static func arc_states(stage_id: String) -> Array` + `static func arc_next_hint(stage_id: String) -> String` (const arrays STAGE_ORDER, HINT_KEYS) + `_draw_arc()` called from the hud render path, reusing `outlined_text`/`panel` from `src/gfx/renderer.gd`. EN literals wrapped in `tr_key` at draw; add 5 hint keys + "ARC_NEXT" prefix rows to `vi.csv`.
- [ ] Step 4: `./tools/test.sh` → green. Commit: `feat(hud): R3 progress arc 5 stages + next-milestone hints`.

---

### Task 3: R2 — Objective chip with live counter

**Goal:** Objective line gains an optional live `cur/max` counter ("34/100"), bound to state stages already track; Space's dynamic objective behavior is preserved.

**Files:**
- Modify: `src/ui/hud.gd` (`show_objective` var :33, render :347-352 — add optional counter fields)
- Modify: `src/game/tribe/tribe_sim.gd` (:110/:262 hook — pass totem food/wood), `src/game/civ/civ_sim.gd` (:88), `src/game/space/space_sim.gd` (:168 — worlds seeded count appended to existing dynamic line)
- Test: `tests/test_objective_chip.gd` (create)

**Acceptance Criteria:**
- [ ] `hud.show_objective_text: String`, `show_objective_cur: int`, `show_objective_max: int` (cur<0 or max<=0 → no counter rendered — plain text as today).
- [ ] Counter renders as `text · 34/100` in the same centered objective slot; tabular numerals; i18n-safe (numbers outside `tr_key`).
- [ ] Tribe objective shows totem progress counter (food toward 100 while food-limited, wood toward 80 after — pick whichever constraint is unmet, both if partially met: use food first, matching gate order at `tribe_sim.gd:775-780`).
- [ ] Civ objective unchanged text (no natural counter — leave without counter, documented).
- [ ] Space objective keeps its dynamic updates (`space_sim.gd:168` + ending swaps) and gains "worlds seeded cur/3" counter component.
- [ ] Existing objective tests (if any) still green; suite green.

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read `hud.gd` objective render + the 3 sim hook sites + TS `hud.ts:49,238-240`, `SpaceStage.ts:566`.
- [ ] Step 2: Failing tests: set `show_objective_text/cur/max`, render into a bare CanvasItem under headless (follow `tests/test_hud_arc.gd` pattern from Task 2), assert no crash + counter string format helper `objective_display(text, cur, max)` pure-tested: `eq(HudUi.objective_display("T", 34, 100), "T · 34/100")`, `eq(HudUi.objective_display("T", -1, 0), "T")`.
- [ ] Step 3: Implement fields + render + update the 3 sims' hook calls to fill cur/max from state they already compute (totem progress, worlds seeded with pop≥20 count).
- [ ] Step 4: Suite green. Commit: `feat(hud): R2 objective chip live counter`.

---

### Task 4: R1 — Micro-tutorials for Tribe, Civ, Space (≤3 steps each)

**Goal:** The three tutorial-less stages get a ≤3-step reactive tutorial each, reusing the existing TutorialUi framework — casual players walk the core loop by hand in ~90s.

**Files:**
- Modify: `src/game/tribe/tribe_stage.gd` (+ `tribe_sim.gd` expose read-only counters), `src/game/civ/civ_stage.gd` (+ `civ_sim.gd`), `src/game/space/space_stage.gd` (+ `space_sim.gd`)
- Modify: `assets/i18n/vi.csv` (9 step texts + headers)
- Test: `tests/test_tutorials_new.gd` (create)

**Acceptance Criteria:**
- [ ] Tribe steps (flag `tutTribe`): 1) "Walk to a tree — a tribesman gathers it" (done: wood stockpile increases by ≥1 since step start) → 2) "Press R — build a hut" (done: hut count ≥1) → 3) "Hold T — raise the Great Totem" (done: totem progress > 0).
- [ ] Civ steps (flag `tutCiv`): 1) "Press Q/A — raise military output" (done: mil output > start 4) → 2) "Press 1 — launch an armada" (done: launch count ≥1) → 3) "Touch an enemy city — conquer it" (done: any city owner flips to 'you' — reuse conquest state).
- [ ] Space steps (flag `tutSpace`): 1) "Fly near a planet — press R to abduct a species" (done: abduct count ≥1) → 2) "Press G — open the gene lab" (done: gene lab opened ≥1) → 3) "Press F — evolve a seeded world a generation" (done: evolve count ≥1).
- [ ] All step texts EN literal + `vi.csv` rows; skip-hold 0.4s works (existing framework); fire once per run (flag persists via `context.flags` + `save_all` on finish — framework already does this).
- [ ] Tutorials never block the update loop (they only poll state via existing sims — done-callables are pure reads).
- [ ] Suite green.

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read `src/ui/tutorial.gd` fully, `cell_stage.gd:537-566` (how steps + state counters wire), and the three stage/sim pairs' relevant state (tribe wood/hut/totem, civ output/launch/conquest, space abduct/genelab/evolve counters — add plain `var` counters incremented at the existing action sites if missing).
- [ ] Step 2: Failing tests: construct each stage in headless mode (follow how `tests/test_tutorial_cell.gd`-style existing tests build stages — if none exist, follow `tests/test_hud_arc.gd` pattern + directly instantiate the sim with a test context); simulate state (e.g. `sim.wood += 5`) → assert `tutorial.stepIndex` advances per done-callable; assert `context.flags["tutTribe"] == "done"` after finish.
- [ ] Step 3: Implement the three step arrays + builder wiring (copy the cell_stage pattern verbatim: `TutorialUi.new(game, "tutTribe", steps)` in `_build_overlays`, `on_exit` finish rules same as cell :544-548).
- [ ] Step 4: Suite green. Commit: `feat(tutorial): R1 micro-tutorials tribe/civ/space`.

---

### Task 5: R11 — Deterministic creature card renderer (shared, RID-safe)

**Goal:** One pure renderer: genome (+meta) → drawn card content, used by pack portraits (R9), extinction/bestiary cards (R8), and later full genome showcase — deterministic (same genome+seed = same output) and RID-leak-free.

**Files:**
- Create: `src/gfx/creature_card.gd` (static class `CreatureCard`)
- Test: `tests/test_creature_card.gd` (create); scene test `tests/scenes/test_card_render.gd/.tscn` (create, runs under xvfb like `tests/scenes/test_visual_creature.gd`)

**Acceptance Criteria:**
- [ ] `CreatureCard.draw_into(ci: CanvasItem, genome: Dictionary, meta: Dictionary, rect: Rect2) -> void` — draws name + epithet + up to 3 stat bars (size/legs/brain — or diet-appropriate) + the creature via `creature_painter.draw_creature`, then FREES all 3 returned RIDs (leak-checked).
- [ ] Deterministic: two draws of the same (genome, meta, rect) produce byte-identical card content (pixel-hash test under xvfb via the scene test, comparing `img.get_data().sha256_text()`).
- [ ] Leak guard test: calling `draw_into` 50× in a loop leaves RID leak count unchanged (grep the RID warning line before/after in the scene test log).
- [ ] Headless smoke test passes without xvfb (draw into bare CanvasItem, no crash — mirrors `tests/test_creature_painter.gd`).
- [ ] Suite green + RID ceiling intact.

**Verify:** `./tools/test.sh` → green; `./tools/test_card_scene.sh` (create this wrapper under xvfb if the scenes suite has one — follow `tools/test_*.sh` naming) → green.

**Steps:**
- [ ] Step 1: Read `src/gfx/creature_painter.gd:85+` (draw_creature contract + opts), `src/evo/names.gd`, `tests/test_creature_painter.gd` + `tests/scenes/test_visual_creature.gd` + `tools/visual_check_creature.py` (scene-test pattern).
- [ ] Step 2: Failing headless test: `CreatureCard.stat_bars(genome)` pure function returns expected 3-bar array; `meta_label(genome)` returns `species_name` + `epithet` composed via `tr` before return.
- [ ] Step 3: Implement `draw_into` — layout: portrait rect (left 60%), name/epithet top, bars bottom; scale creature via painter's `base_zoom` param to fit rect; **free the 3 RIDs in a deferred cleanup** if the caller keeps the CanvasItem alive, else immediately after draw when drawing to an ephemeral item — document the chosen lifecycle on the class.
- [ ] Step 4: Scene test under xvfb: render twice, pixel-hash equal; render 50×, grep RID warning delta == 0.
- [ ] Step 5: Suite green. Commit: `feat(gfx): R11 deterministic creature card renderer (RID-safe)`.

---

### Task 6: R6 — Free LOOK tab + editor world peek

**Goal:** Editor splits into BODY (parts + diet + DNA) and LOOK (hue/sat/pattern/coat + name slot placeholder) tabs; LOOK items cost 0 DNA and the tab shows no DNA economy; world dim eases 0.88 → 0.6 with hold-to-peek at 0.2.

**Files:**
- Modify: `src/ui/editor.gd` (rows build :106-134, tab UI, dim :347, hue/sat :157-167/:323-330/:611-642, footer :463-475)
- Modify: `src/evo/parts.gd` (PATTERNS :70-75, COATS :77-82 → price 0; keep refund logic untouched for parts)
- Modify: `assets/i18n/vi.csv` (tab labels + peek hint)
- Test: `tests/test_editor_look.gd` (create)

**Acceptance Criteria:**
- [ ] Two tabs, default BODY on open; Tab switch persists within the open session (not saved).
- [ ] LOOK tab lists: pattern (3), coat (3), hue slider, sat slider, name placeholder row ("naming comes with R7" — row visible but inert in this task), each priced 0 / no DNA display in this tab.
- [ ] Buying pattern/coat costs 0 DNA (DNA unchanged after purchase) and remains free to re-switch (TS refund path for cosmetics no longer applies — cosmetics never charge).
- [ ] BODY tab unchanged prices (diet 40/60, size ±30, part_cost curve, starter no-refund rule intact).
- [ ] World dim: default 0.6 while editor open; holding the peek control (Space bar is taken by dash — use a dedicated on-screen hold-button "peek" bottom-right + keyboard `Alt`) drops to 0.2; releasing restores 0.6. Documented in the editor footer hint.
- [ ] Cell leg-sale guard (:212-215) and creature warn (:220-223) unaffected; suite green; cell A-B evidence sha unchanged (editor is UI-only, no sim change).

**Verify:** `./tools/test.sh` → green; `cd /home/misa/Desktop/RD/primordia-native && git diff --stat HEAD | grep parts.gd` shows only PATTERNS/COATS price lines changed.

**Steps:**
- [ ] Step 1: Read `editor.gd` fully (735 lines — it is the whole surface), TS `editor.ts` LOOK rows + spec R6 + red-team adjudication (alpha 0.6 / peek 0.2).
- [ ] Step 2: Failing tests: pure helpers on the editor Ui class (check its actual `class_name` in `editor.gd` — hud's is `HudUi`; use whatever the file declares) — `look_price(part_id) -> int` (all LOOK ids → 0) and `world_dim(peeking: bool) -> float` (→ 0.2/0.6); editor-dump test: open editor in creature stage, assert rows split by tab and DNA label hidden on LOOK.
- [ ] Step 3: Implement tab bar (two buttons top of panel), split `build_rows` per tab, zero prices via the `look_price` helper (not inline literals), dim constant swap + peek hold handling in `_input`-equivalent of editor, `vi.csv` rows.
- [ ] Step 4: Suite green. Commit: `feat(editor): R6 free LOOK tab + world peek`.

---

### Task 7: R7a — Creature naming (picker + display everywhere)

**Goal:** The player names their creature: on-canvas character picker in the LOOK tab; the name replaces `self_name()` everywhere it displays; persists on the save wire.

**Files:**
- Modify: `src/ui/editor.gd` (LOOK tab: name row becomes the picker)
- Modify: `src/game/context.gd` (persist `creatureName` — write in `to_save_data`, read with `.get` + type check, default "")
- Modify: `src/evo/names.gd` (`self_name` → returns saved name when non-empty)
- Modify: display sites: `hud.gd` (arc area or stage-name slot), `menu.gd` (save-slot line if genome is shown), bestiary self entry
- Modify: `assets/i18n/vi.csv` (picker labels)
- Test: `tests/test_naming.gd` (create)

**Acceptance Criteria:**
- [ ] Picker: on-canvas grid of allowed glyphs (A–Z, a–z, 0–9, space, apostrophe, dash — the exact charset as a const), max length 14, backspace + accept/cancel; no DOM/LineEdit (port 1:1 to Godot later per spec).
- [ ] `context.get_display_name() -> String`: saved name if set, else `names.gd self_name()` suggestion; suggestion shown in the picker as "accept or edit".
- [ ] Name displays in: editor header, HUD (next to arc, small), bestiary self entry, charm-success toast ("Bristle joins your pack!" — wait, that's the PACKMATE name (Task 9); self name displays in toasts about the player creature death/salvage — implement the two death/salvage toast sites to use display name).
- [ ] Save round-trip: name survives save→load (type-checked; corrupt → falls back to suggestion, no crash).
- [ ] Empty/whitespace-only name = not set (falls back). Length clamped at 14 with truncation, not rejection.
- [ ] Suite green.

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read `names.gd` (`self_name` :70-87), `context.gd` save/load, `editor.gd` LOOK rows from Task 6, TS `names.ts:47-60` + spec R7.
- [ ] Step 2: Failing tests: `ctx.set_display_name("Mèos特色产业")` → charset filter strips non-allowed glyphs (assert result is filtered + truncated ≤14); `get_display_name()` returns saved; after `to_save_data`→`load` round-trip name returns; empty → `self_name()` fallback.
- [ ] Step 3: Implement picker UI in editor LOOK tab (grid buttons + backspace — reuse editor button-row pattern), context persistence, display sites.
- [ ] Step 4: Suite green. Commit: `feat(editor): R7a creature naming — picker, persistence, display`.

---

### Task 8: R7b — Creature call (minimal audio core)

**Goal:** Smallest viable audio layer: the creature's voice — a 2–3 note synth call, pitch derived from genome — plays on charm success and pack greet; mute toggle respected. No music, no mood crossfade (explicitly deferred).

**Files:**
- Create: `src/core/audio.gd` (RefCounted `AudioCore`: lazy AudioStreamPlayer + generator; `play_call(genome)`, `play(id: String)` stub mapping existing hook ids → silence)
- Modify: the 5 stages' `_build_hooks` `audio_play` noop → route through a shared `AudioCore` instance owned by `game.gd` (respects `game.toggle_mute` persistence `game.gd:852-855`)
- Modify: `src/game/creature/creature_sim.gd` (charm win :1258-1271 fires `audio_play("call", genome_ref)`)
- Test: `tests/test_audio_core.gd` (create)

**Acceptance Criteria:**
- [ ] `AudioCore.call_pitch(genome) -> float` pure: base 220Hz × pitch factor from size (↓ with size, range ×0.6–×1.6), hue (±15%), jaw (↑ with jaw ×1.0–1.3) — unit-tested with pinned genomes (exact expected Hz within 1e-6).
- [ ] `play_call` generates exactly 3 tones with attack/decay envelopes; pattern pinned: base pitch P from `call_pitch(genome)`, note1 = P, note2 = P × 1.5 if `genome_hash(genome) % 2 == 0` else P × 0.75, note3 = P × 1.25; each tone 0.18s with 20ms attack / 120ms decay; buffer has non-zero samples (headless-safe: generate AudioStreamWAV data, assert data length > 0 and RMS > 0 — no actual output device needed).
- [ ] Hook seam: existing `audio_play` hook id "call" reaches AudioCore; other existing ids remain silent noops (no behavior change anywhere else).
- [ ] Muted (settings `muted=true`) → no buffer queued; unmute restores. Volume conservative (−12 dB default).
- [ ] Suite green (audio test never touches an audio device).

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read the 5 stages' `_build_hooks` noop seams + `game.gd:852-855` (mute persistence) + TS `core/audio.ts` (tone/envelope shapes to mimic) + spec R7.
- [ ] Step 2: Failing tests for `call_pitch` (3 pinned genomes → exact Hz) + buffer RMS > 0 + mute gate.
- [ ] Step 3: Implement AudioCore (AudioStreamWAV synthesis, 22050Hz mono 16-bit, ~0.6s for 3 notes) + game-owned instance + hook routing; wire charm-win + pack-greet calls.
- [ ] Step 4: Suite green. Commit: `feat(audio): R7b minimal audio core — creature call`.

---

### Task 9: R9+R8 — Packmate identity + bestiary cheap

**Goal:** Charmed packmates get names, nameplates, HUD portraits (via Task 5 card renderer), and named death records; species get an extinction-moment card and a text bestiary page in pause. No gallery screen.

**Files:**
- Modify: `src/game/creature/creature_sim.gd` (charm :1258-1271 → assign name; pack persist :393-400 schema `{genome, baby}` → `{genome, baby, name}` — read with `.get("name", "")` for old saves; packmate death site → named toast + bestiary `fell at gen N`)
- Modify: `src/game/creature/creature_stage.gd` (nameplate draw above packmates; pack portrait row via `CreatureCard`)
- Modify: `src/ui/pause.gd` (bestiary page: text rows — name + epithet + stage-seen + TỆT CHỦNG stamp; no thumbnails in v1)
- Modify: extinction moment: wherever `extinct` flips in `context.gd` bestiary (`discover` :147-162 / kill path) → queue a one-time species card (hud banner kind="species" using CreatureCard on the stage's HUD layer)
- Modify: `assets/i18n/vi.csv`
- Test: `tests/test_packmate_identity.gd`, `tests/test_bestiary_page.gd` (create)

**Acceptance Criteria:**
- [ ] Charm success assigns a unique name (`species_name` + `epithet` via `names.gd`, deduped against current pack); nameplate renders above each packmate; pack portraits row (packLimit slots) shows only living members, drawn through `CreatureCard` with RIDs freed each frame redraw (or cached texture per member — implementer documents which, leak test mandatory either way).
- [ ] Pack persist: old saves without `name` load fine (fallback empty → name assigned lazily on next charm or display).
- [ ] Packmate death: toast "«name» fell — gen N" + bestiary entry records it; extant pack untouched.
- [ ] Extinction card: fires ONCE per species extinction event, shows CreatureCard + "TỆT CHỦNG" stamp, i18n'd; does not fire for player-caused vs natural differently (same card).
- [ ] Pause bestiary page: all discovered species listed (name + epithet + first stage + stamp if extinct), undiscovered = "???"; scrollable if >8 rows; reachable from existing pause nav.
- [ ] Suite green; RID ceiling intact (portrait row is the risky draw — leak-checked).

**Verify:** `./tools/test.sh` → green; scene test for portraits under xvfb (reuse Task 5 wrapper).

**Steps:**
- [ ] Step 1: Read `creature_sim.gd` charm/pack/persist/restore, `context.gd` bestiary, `pause.gd` page structure, `hud.gd` banner/kind system (:165-208, :391-413 as the "world" kind pattern to copy for "species").
- [ ] Step 2: Failing tests: charm assigns distinct names to 2 packmates; persist/restore round-trip keeps names; old-schema entry (no name) restores without crash; extinction card queued flag once; bestiary page rows built from a seeded context.
- [ ] Step 3: Implement sim + stage draw + pause page + extinction card; wire portraits through CreatureCard.
- [ ] Step 4: Scene/leak test for portraits. Suite green. Commit: `feat(creature): R9+R8 packmate identity + bestiary cheap`.

---

### Task 10: R15 — Karma profile per stage (pacifist integrity)

**Goal:** Karma becomes stage-anchored: per-stage exit snapshots gate the pacifist ending; bush-graze loophole closed. Drift protection and storyteller gate untouched.

**Files:**
- Modify: `src/game/context.gd` (`karmaByStage` array persist — write `.get`-read; helper `karma_mean()`, `karma_min()`)
- Modify: `src/game/game.gd` (stage switch seam :265-311 → snapshot karma into `karma_by_stage[stage_index]` at exit)
- Modify: `src/game/creature/creature_sim.gd` (graze :840 → 0.005/s; add per-stage recover cap)
- Modify: `src/game/space/space_stage.gd` (ending flavor :810-814: harmony tier additionally requires `ctx.karma_min() >= -0.1`)
- Modify: `assets/i18n/vi.csv` (1 ending line variant if needed)
- Test: `tests/test_karma_profile.gd` (create)

**Acceptance Criteria:**
- [ ] `karma_by_stage` (4 entries: cell/creature/tribe/civ) recorded at stage exit via the switch seam; old saves (no field) → derived as `[ctx.karma]` single entry (graceful).
- [ ] Harmony ending ("gardened the stars") requires BOTH `karma > 0.3` AND `karma_min() >= -0.1`; "fears your name" path unchanged; middle runs get the existing neutral line (no new tier text in this task).
- [ ] Graze +0.005/s; **recover cap**: karma gained within one stage cannot exceed +0.15 above the karma recorded at that stage's entry (cap applies to positive recovery only — negative moves uncapped).
- [ ] Bite −0.008, charm +0.03, festival +0.08, feast +0.01, civ attack −0.02 etc. unchanged.
- [ ] Drift (game.gd:444-445) and storyteller PACIFIST_KARMA gate (0.5) unchanged.
- [ ] Karma-cluster tests updated where constants changed; suite green. Cell A-B: graze is creature-sim (not cell) — A-B evidence sha unchanged expected; if it changes, stop and report (indicates cell-sim touch).

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read `context.gd` karma (:46-47, :130-135), `game.gd` drift :444-445 + switch :265-311, `creature_sim.gd` graze/bite sites, `space_stage.gd` ending, TS `SpaceStage.ts:1111-1112` + spec R15.
- [ ] Step 2: Failing tests: snapshot array filled by simulated switches; `karma_min()` math; harmony gate refuses `[-0.4, 0.8]` run (mean high, min low) and accepts `[0.1, 0.4]`; graze rate pinned: 1s of grazing adds approx 0.005 (eps 1e-9); recover cap: from entry 0.0, +1.0 karma input in-stage clamps to +0.15.
- [ ] Step 3: Implement. Care: snapshot on exit uses the switch seam (not `on_exit` of stage — quit-to-menu must not double-record; use `switch_stage` which is the single choke point :292-293).
- [ ] Step 4: Suite green. Commit: `feat(karma): R15 per-stage karma profile + graze cap`.

---

### Task 11: R13 — Chaos scar (cheap) + cosmetic hue mutation

**Goal:** Chaos peaks leave permanent run-long scars (world tint + toast, no reveal ceremony); one chaos event family gains the power to shift the player's cosmetic hue — with omen before the hit and free revert via the LOOK tab.

**Files:**
- Modify: `src/game/context.gd` (`chaosPeak` + `scarTier` + `scarBenign` persist)
- Modify: `src/game/game.gd` (chaos update :438-445 → track peak, fire threshold crossings once per run)
- Modify: `src/ui/hud.gd` (scar toast via existing toast/banner; world tint hook)
- Modify: stage backdrops (all 5: read a `world_tint` from ctx — one tint slot, tier-colored, subtle)
- Modify: `src/game/chaos.gd` + one stage deck (creature_events.gd) → new event "transposon" (warn 2.5s omen → apply hue shift ±30 to `ctx.genome.hue` clamped; toast explains free revert in LOOK)
- Modify: `src/ui/editor.gd` (LOOK tab hue row: "revert" button restoring pre-shift hue stored in ctx `hueBeforeTransposon`)
- Modify: `assets/i18n/vi.csv`
- Test: `tests/test_chaos_scar.gd` (create)

**Acceptance Criteria:**
- [ ] Threshold formula (per difficulty, always reachable): `th_i = rest + (1 − rest) × {0.40, 0.65, 0.85}` where `rest` = difficulty settle floor (0.12 normal / 0.05 peaceful / 0.25 chaos). Each crossing fires ONCE per run; toast names the scar ("Vết nứt trăng" tier names i18n'd).
- [ ] `chaos_peak` persists (save wire); old save without it → 0.0.
- [ ] Karma ≥ 0.3 at the crossing moment → scar is benign (tint green-shift, toast wording benign); else harsh (tint chaos-orange). Karma read is the value AT the crossing, not current.
- [ ] World tint: single slot, applied as a subtle full-screen overlay color (alpha ≤ 0.08) — must not touch sim math; tier 3 strongest.
- [ ] Transposon event: gated into the creature deck (weight modest), omen warn phase mentions the hue shift BEFORE apply (chaos law), apply shifts hue ±30 (either direction, seeded), revert button in LOOK restores exactly the stored pre-shift hue; revert is free; event never fires twice in one run.
- [ ] Suite green; cell A-B sha unchanged (creature-deck change doesn't touch cell sim).

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read `game.gd` chaos settle block, `chaos.gd` event lifecycle (:102-120 warn→apply→end), `world_traits.gd` patch-key pattern, `creature_events.gd` fold + TS `worldTraits.ts:119` great_frost precedent + spec R13.
- [ ] Step 2: Failing tests (pure): threshold formula for 3 difficulties (exact values, eps 1e-9); crossing fires once (simulate chaos sequence 0.1→0.5→0.7→0.9 → 3 scars, not 5); benign/harsh choice pinned by karma-at-crossing; transposon apply/revert round-trip restores hue exactly (float eq eps 1e-9).
- [ ] Step 3: Implement context fields + game loop peak tracking + tints + event + revert.
- [ ] Step 4: Suite green. Commit: `feat(chaos): R13 chaos scars + transposon hue event`.

---

### Task 12: R4 — Death debrief (cause + loss + counter-tip)

**Goal:** Every player death shows a 1.4s non-blocking overlay during the existing death fade: what killed you, DNA lost, one counter-tip. Display-only — the one-way door invariant is untouched.

**Files:**
- Create: `src/ui/death_debrief.gd` (RefCounted overlay component, drawn by stages that already draw death fades)
- Modify: `src/game/cell/cell_sim.gd` (death site :738-area → record cause id), `creature_sim.gd`, `tribe_sim.gd` (reuse `last_death_cause` :173), `civ_sim.gd`, `space_sim.gd` — each death path records `death_cause` + `death_dna_lost`
- Modify: per-stage fade draw sites → render debrief when cause set
- Modify: `assets/i18n/vi.csv` (cause names + tip lines — enumerate ALL causes found in code, typically 6–10)
- Test: `tests/test_death_debrief.gd` (create)

**Acceptance Criteria:**
- [ ] Cause registry: const map `CAUSES = {id → {text_key, tip_key}}` covering EVERY death path found in the 5 sims (implementer enumerates them; the test asserts the registry count == the count of death sites found by grep of the heal/offense-gated death branches — document the list in the test).
- [ ] Debrief content: cause line ("The spine-tooth got you"), DNA lost ("−25 DNA"), tip ("grow SPIKES" / "dash to escape" — each cause has exactly one tip).
- [ ] Overlay: 1.4s within the existing death fade timing, non-blocking (no input consumed, no heal path added — invariant 1 gates untouched), dismisses into the existing respawn.
- [ ] Cell death reports the killer species name when killed by an NPC (uses bestiary name), generic cause otherwise.
- [ ] No death path changes behavior — only records. Suite green.

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read each sim's death branch (cell :738-area, creature, tribe :599-658 + :1218, civ, space hazards), the fade draw sites, `tribe_sim.gd` lastDeathCause pattern + TS `CellStage.ts:497-521`.
- [ ] Step 2: Failing tests: registry completeness (hardcoded expected id list from Step 1's enumeration); debrief build pure fn `(cause_id, dna_lost, killer_name) -> {lines}`; record-then-fade order for one cell death simulated in headless.
- [ ] Step 3: Implement recording (one line per site) + overlay component + draw wiring + i18n.
- [ ] Step 4: Suite green. Commit: `feat(ui): R4 death debrief overlay`.

---

### Task 13: R10 — Genome showcase on transition cards (text-first)

**Goal:** The 2.2s transition card gains 3 stat lines + 1 karma line (text) so the player sees what they BUILT before the new stage begins. Image render via Task 5 renderer is explicitly NOT in this task (red-team: text first).

**Files:**
- Modify: `src/game/game.gd` (transition card draw :513-546 — card content gains stat lines when the incoming stage is a gameplay stage)
- Modify: `assets/i18n/vi.csv` (labels: "legs/brain/size/karma")
- Test: `tests/test_card_showcase.gd` (create)

**Acceptance Criteria:**
- [ ] `card_showcase_lines(ctx) -> Array[String]` pure: exactly 3 stat lines (size, legs, brain — from `ctx.genome` via the stats module) + 1 karma line ("karma +0.42" signed, 2 decimals) — unit-tested with pinned genomes/karma.
- [ ] Card render draws the lines under the existing title/sub when `pending card` targets a gameplay stage; menu-bound transitions draw nothing new.
- [ ] Timing unchanged (0.55/2.2/0.6); skip-by-click unchanged; i18n'd labels.
- [ ] Suite green.

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read `game.gd` transition block + TS `game.ts:530-547` + spec R10.
- [ ] Step 2: Failing tests for the pure line builder (pinned genome → exact strings; karma sign formatting).
- [ ] Step 3: Implement draw + wiring.
- [ ] Step 4: Suite green. Commit: `feat(transition): R10 genome showcase text lines`.

---

### Task 14: R12 — Heredity Ledger cheap (Shape/Conduct snapshot + first consumers)

**Goal:** At each stage exit, snapshot Shape (body plan → predator/minder/wall-line) and Conduct (karma); civ shows its national trait line and gets a ±1 rival-defense / ±2 start-output effect; space shows its line. No new UI beyond text lines.

**Files:**
- Modify: `src/game/context.gd` (`runShape: String`, `karmaByStage` already from Task 10 → `conduct_avg()`; persist both)
- Modify: `src/game/game.gd` (switch seam from Task 10 → also compute Shape from current genome)
- Modify: `src/game/civ/civ_sim.gd` (`rival_def_for` :523-526 ±1 by Shape; start output ±2 by conduct avg; intro line const from Shape)
- Modify: `src/game/space/space_stage.gd` (intro/HUD line only — real perks deferred)
- Modify: `src/evo/genome.gd` or a new `src/evo/shape.gd` (pure classifier)
- Modify: `assets/i18n/vi.csv`
- Test: `tests/test_heredity_ledger.gd` (create)

**Acceptance Criteria:**
- [ ] Pure classifier `shape_of(genome) -> "predator" | "minder" | "wall"`: score predator = jaw + spikes + size_rank; minder = eyes + arms + brain; wall = coat + horns; highest score wins; tie → predator. Pinned-genome unit tests (exact outputs, ≥6 genomes covering all 3 + 2 ties).
- [ ] Shape recomputed at each stage exit (switch seam); civ consumes the LATEST shape at its on_enter.
- [ ] Civ effects: predator-line → `rival_def_for` −1; minder-line → +0 (charm/trade +0.015→+0.025 karma per trade — pick: minder = trade karma +0.01 extra); wall-line → +1 rival_def but city hp regen +0.3/s (constant exists or added at the hp regen site — one line). Start output: `10 ± 2` by conduct_avg sign (conduct_avg > 0.15 → +2; < −0.15 → −2; else 0). **Balance probe mandatory:** with predator-line + high conduct, full-armada completion time must not drop below 60% of baseline measured in the probe test — if it does, clamp output bonus to +1 and note in ledger.
- [ ] Civ intro card (existing intro text site) gains ONE line: "National trait: <trait>" i18n'd; space gains its one line at enter.
- [ ] Old saves: missing shape → "predator" default? NO — missing → compute from genome on load (genome is always present). Conduct missing → 0.0.
- [ ] Suite green.

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read `genome.gd` fields, `civ_sim.gd` rival_def_for + start + regen sites, stage-enter intro sites, TS `CivStage.ts:82,352` + spec R12.
- [ ] Step 2: Failing tests: classifier pins; civ effect pins (`rival_def_for` with mocked shape); conduct output modifier pins; intro line presence.
- [ ] Step 3: Implement classifier + seam + consumers.
- [ ] Step 4: Balance probe test (bot: predator+high-conduct civ run, armada-only, measure completion time vs neutral baseline run; assert ≥ 60% — if violated, apply the documented clamp and record). Suite green. Commit: `feat(progression): R12 heredity ledger cheap`.

---

### Task 15: R14 — Civ attaches to the world (trait-gates + eco snapshot) + pacifist civ viable + tribe-fall floor

**Goal:** The empty civ column of the memory matrix gets filled: 3 world-trait-gated chaos events, eco health at creature-exit boosts start output, pacifist civ passive becomes viable (≤20 min), and tribe-fall gets a rebirth DNA floor.

**Files:**
- Modify: `src/game/civ/civ_events.gd` (deck fold :113 → +3 trait-gated events)
- Modify: `src/game/creature/creature_sim.gd` or stage persist (creature exit → `ctx.flags["ecoHealth"] = living_species_count / 6.0` — reuse the eco API that counts living species)
- Modify: `src/game/civ/civ_sim.gd` (start output: `10 + roundi(eco_health * 12)` capped at 22 — i.e. +0..12; culture regen lane constant buff; note: current regen :628-632)
- Modify: `src/game/tribe/tribe_sim.gd` (tribe-fall path :535-548 → after erasing tribeState, set `ctx.dna = max(ctx.dna, 50)` before go_to creature)
- Modify: `assets/i18n/vi.csv` (3 event names/warns + effect lines)
- Test: `tests/test_civ_world_attach.gd` (create); bot test in `tests/bots/` for the pacifist civ timing

**Acceptance Criteria:**
- [ ] Deck fold: toxin_sea trait → "Acid monsoon" (city hp drain over 6s, warn phase first — chaos law); hungry_bloom → "Famine" (econ regen paused 20s); mutation_moon → "Moon cult" (culture burst +15% of current, once). Each gated by `world_has(...)` — fold test asserts presence with trait, absence without (fold twice with two seeded worlds).
- [ ] ecoHealth snapshot: recorded at creature stage exit (living species / total roster, 0..1); civ start output `10 + roundi(eco_health * 12)`, hard cap 22; eco-collapsed world (ecoHealth ≤ 0.2) still completes armada route (bot proves: needs ~6 launches at baseline — assert ≤ 10 launches at ecoHealth 0).
- [ ] Pacifist civ viable: bot-run culture-only route (no armadas) completes in ≤ 1200s game-time with the buffed regen constant (probe current time first; raise the culture-regen constant or the hearts lane minimally to hit the bound — record before/after values in the ledger).
- [ ] Tribe-fall floor: falling tribe → arriving creature stage with DNA ≥ 50 (deterministic, no loop: bot proves fall→creature→regrow→re-found works).
- [ ] Suite green; bot suite green.

**Verify:** `./tools/test.sh` → green.

**Steps:**
- [ ] Step 1: Read `civ_events.gd` fold + trait-gate patterns in `cell_events.gd` (toxin_clouds precedent), `civ_sim.gd` start/regen/launch/resolve, `tribe_sim.gd` fall path, eco living-species API, spec R14 + adjudications.
- [ ] Step 2: Failing tests: fold gating (2 worlds); output formula pins (ecoHealth 0 → 10, 0.5 → 16, 1.0 → 22 cap); famine pauses econ regen exactly 20s (sim clock assert, eps 1e-9); acid monsoon drains city hp only after warn; tribe-fall floor.
- [ ] Step 3: Implement events (follow the warn→apply→end ChaosScheduler event struct — do NOT hand-roll timing), snapshot, buffs, floor.
- [ ] Step 4: Bot probes (pacifist timing, eco-collapsed armada, tribe-fall loop). Suite green. Commit: `feat(civ): R14 world attach + pacifist viability + tribe-fall floor`.

---

### Task 16: Final verification, datum re-check, ledger + docs

**Goal:** Close the redesign: whole-suite green with every batch's features in, RID datum re-verified (re-datumed with evidence if legitimately grown), bot pacifist route proven end-to-end, execution ledger written, TS-repo spec updated with implementation notes pointer.

**Files:**
- Modify: `/home/misa/Desktop/RD/Spore/docs/superpowers/specs/2026-10-07-experience-redesign-design.md` (append "Implementation" section: native commit range + any deviations hit during build)
- Create: `docs/superpowers/plans/2026-10-07-experience-redesign-ledger.md` (per-task commit list + evidence: suite tails, RID lines, probe numbers)

**Acceptance Criteria:**
- [ ] Full suite: `0 failures`; file/test/check counts reported (will exceed 61/856 — growth is expected and fine).
- [ ] RID: if leak count > 411 → bisect which new test boots leak, fix the leak (free RIDs) rather than raise the datum; ONLY if the growth is legitimate irreducible boots (like the 403→411 precedent: datum depends on suite content) → re-datum commit with both-rigs ×3 evidence per the M7/QC procedure. Prefer fixing leaks.
- [ ] Bot proof: pacifist full run (0 kills, cell scavenge → creature charm → tribe festival → civ culture → space) reaches harmony ending (this is the spec's binding pacifist definition).
- [ ] A-B: cell-sim evidence sha unchanged from baseline (Task 1) — any drift is a bug to fix, not to bless.
- [ ] Ledger complete (every task: commit sha + suite tail + notes); spec implementation section appended (in the frozen TS repo — a docs-only commit there is allowed and expected).
- [ ] Push to remote happens ONLY on explicit user command (do not push in this task).

**Verify:** `./tools/test.sh` → green tail; `tools/ab_test.sh 6754bae` → sha match.

**Steps:**
- [ ] Step 1: Full suite + RID check (procedure above).
- [ ] Step 2: Pacifist bot end-to-end run; capture ending line.
- [ ] Step 3: A-B compare vs Task 1 baseline sha.
- [ ] Step 4: Write ledger; append spec implementation notes; commit both (`docs: experience redesign implementation ledger` in native; docs commit in TS repo).
- [ ] Step 5: Report to coordinator: final counts, RID datum state, deviations list.
