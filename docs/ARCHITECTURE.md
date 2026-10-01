# PRIMORDIA Native — Kiến trúc (Milestone 1–4: sim core + cell + creature + tribe stage)

Ngày: 2026-10-01 · Trạng thái: M1 (sim core) + M2 (cell stage parity) + M3 (creature stage parity) + M4 (tribe stage parity) hoàn tất, mọi test xanh — tags `cell-parity-m2`, `creature-parity-m3`, M4 wrap chờ tag `tribe-parity-m4`. Spec tổng: `docs/specs/2026-09-29-native-migration-design.md`. Parity checklist M2: `docs/PARITY-M2.md`; M3: `docs/PARITY-M3.md`; M4: `docs/PARITY-M4.md`.

## 1. Tách layer — sim không biết Godot scene tồn tại

Nguyên tắc cốt lõi của port: **sim layer là GDScript thuần trên `RefCounted`** — không Node, không scene, không `_process`; test được hoàn toàn headless.

- `src/core/`, `src/evo/`, `src/game/chaos.gd`, `src/game/context.gd`, `src/game/cell/cell_sim.gd`, `src/game/cell/cell_events.gd` — các class thuần, chỉ phụ thuộc lẫn nhau + `Rng`. GameContext phát event bằng **Godot signal** (`dna_gained`, `toast`, `context_event`) thay cho Bus/EV của TS. Điểm chung của sim: **không phụ thuộc scene tree** — ngoài signal, sim chỉ dùng các API Godot phi-scene: `tr()` (TranslationServer fallback), `push_error`, `FileAccess` (save/load).
- Scene layer (M2): Node2D/Control vẽ procedural qua `_draw`, **mỏng** — gọi sim, vẽ, forward input; không sim logic trong `_process`. Bot/tests đi mọi gate qua **real input pipeline** (`Input.parse_input_event` — bot parity law, M2 constraint 8).
- Every def/data shape giữ wire của TS: Dictionary với key TS-verbatim (camelCase nơi cần parity save-wire: `totalDnaEarned`, `killsByPlayer`, `comboFired`…), gene/stats nội bộ snake_case.

## 2. Determinism contract

Cùng seed → cùng thế giới, bit-exact với bản TS:

- **Mọi randomness đi qua stream `Rng`** (`src/core/rng.gd`) — port bit-exact của Mulberry32 trong `src/core/rng.ts`. State luôn masked uint32 để GDScript `>>` trên int không âm khớp JS `>>>`; `_imul` khớp `Math.imul`. `branch()` sinh seed con như TS.
- **Cấm `randi()`/`randf()` global trong sim.** Ngoại lệ duy nhất được phép (sanctioned): `GameContext._init` — seed-picker mặc định là meta-level, nằm ngoài mọi stream sim. Test luôn truyền seed tường minh.
- World genome **derive lại từ seed** mỗi lần load (deterministic) — save chỉ mang runtime state overlay (revealed/comboFired/firedTurns/counters). Test determinism 1000-seed nằm trong `tests/test_world_genome.gd`.
- Refactor sim → chạy gate behavior-identity: `tools/ab_test.sh` (A-B state-diff harness, `tools/ab_state_dump.gd`) — xem `docs/PARITY-M2.md` §17. Fail-closed trên failure path: run FAIL không đụng `tests/fixtures/ab/` (`tools/test_ab.sh` pin đường hỏng — carry-forward M2).
- **Vector2 class được sanction (T1 review, ghi tại M3 wrap):** toán học rig/creature dùng `Vector2` (f32 nội tại Godot) — mọi pin Vector2 so với eps **1e-5** (class riêng, rộng hơn eps 1e-9 của fixture f64); core f64 (IK solver, spine) giữ 1e-9. Đừng "siết" eps 1e-5 của Vector2 về 1e-9 — sẽ đỏ giả.

## 3. Parity fixtures — trọng tài chống TS freeze

Fixtures JSON trong `tests/fixtures/` được sinh **một lần** từ repo TS frozen (`~/Desktop/RD/Spore`) bằng vitest (`tools/fixture-gen.test.ts` ở repo TS — tool không đụng game source). 6 file: `rng_stream`, `genome_stats`, `eco_tick`, `mutate_crossover`, `world_genome`, `storyteller_walk`; schema + recipe chi tiết trong `tests/fixtures/fixtures.README.md`.

- Test native so kết quả với JSON — **exactness hơn elegance**: float ghi full IEEE-754 double như `JSON.stringify`.
- Trong test GDScript, so float **cho mọi so sánh fixture/parity không bao giờ dùng eps 0.0** — luôn `approx()` với eps ≥ 1e-9 (default của `tests/test_base.gd`) để né khác biệt parse/inRepresentation; fixture continuity được đảm bảo bởi chuỗi draw giống TS (cùng thứ tự consume). Ngoại lệ cố ý: so native-vs-native cùng công thức (vd. `tests/test_rng.gd:92,163` — hai stream cùng seed phải bằng bit) dùng eps 0.0 đúng, vì không có JSON parse nào xen vào.

## 4. Test runner — zero plugin

```bash
cd ~/Desktop/RD/primordia-native
./tools/test.sh              # headless suite (43 files / 641 tests)
./tools/ab_test.sh [BASE]    # A-B behavior-identity gate (xem §2; M3: base cell-parity-m2 → IDENTICAL; M4: base creature-parity-m3 → IDENTICAL)
./tools/test_ab.sh           # A-B fail-open hardening — failure-path test (shell-only)
./tools/test_bot.sh          # bot arc cell ×3 seeds ×2 determinism (xvfb)
./tools/test_bot_creature.sh # bot creature: landfall + chaos + founding ×2 determinism (xvfb)
./tools/test_bot_tribe.sh    # bot tribe: founding → roles → delivery → hut → raid → totem → victory ×2 determinism (xvfb)
./tools/probe_tribe.sh       # 9 econ probes tribe TS-verbatim (headless; cũng nằm trong test.sh)
./tools/test_perf.sh         # perf probe cell 200 ents ≤ 8 ms/tick pure-sim (xvfb)
./tools/test_perf_creature.sh # perf probe creature 60 ents: sim tripwire headless + painter draw ≤ 4 ms (xvfb)
./tools/test_perf_tribe.sh   # perf probe tribe 60 tribesmen + 6 warriors: sim tripwire headless + render-prep ≤ 4 ms (xvfb)
./tools/test_menu.sh         # menu real-click (xvfb)
./tools/test_editor_click.sh # editor purchase real-click (xvfb)
./tools/test_visual.sh       # pixel-assert cell stage (xvfb)
./tools/test_visual_suite.sh # six-moment pixel-assert suite cell (xvfb)
./tools/test_visual_creature.sh # pixel-assert creature painter (xvfb)
./tools/test_creature_scene.sh  # ten-moment creature visual suite (xvfb)
```

`tests/run.gd` tự viết (không GUT/gdUnit4): discover `tests/test_*.gd`, chạy mọi method `test_*`, instance mới cho mỗi test (isolation state), in FAIL + message từng assertion, **exit 1 khi đỏ**. Chạy phải `cd` vào repo root trước (shell cwd reset). Scene tests (`tests/scenes/*.tscn`) chạy dưới xvfb + Compatibility renderer — bot parity law: mọi progression gate đi qua real input pipeline, không gọi thẳng sim.

Ràng buộc `-s` mode (không có editor script class cache — fresh clone/CI):

- Test file dùng **path-based extends**: `extends "res://tests/test_base.gd"`.
- Class resolve bằng `preload("res://...")`/`load("res://...")` — tự tham chiếu `class_name` của chính file đó cũng không resolve được (`rng.gd` dùng const `SELF_SCRIPT`).

## 5. Module map — 1:1 với TS frozen

| Native (Godot 4.2.2, GDScript typed) | TS counterpart | Nội dung |
|---|---|---|
| `src/core/rng.gd` | `src/core/rng.ts` | Mulberry32 bit-exact: next/range/int/chance/pick/weighted/shuffled/gauss/branch |
| `src/core/input.gd` + `loop.gd` | `src/core/input.ts`, `loop.ts` | TS code-string input API + fixed-step 60Hz loop (tick_manual cho tests) |
| `src/core/math.gd` | `src/core/math.ts` | damp/ease/angle helpers (fmod = JS sign semantics) |
| `src/evo/genome.gd` | `src/evo/genome.ts` | Genome Dictionary, GENE_BOUNDS, clamp, genomeHash (breeding) |
| `src/evo/parts.gd` | `src/evo/parts.ts` | Parts catalog: cost/graft/refund, shop lists |
| `src/evo/stats.gd` | `src/evo/stats.ts` | Stats derive cell/creature, legless speed exemption |
| `src/evo/mutation.gd` | `src/evo/mutation.ts` | mutate/crossover, bias clamp 1.2, anomaly/defect/recessive echo |
| `src/evo/names.gd` | `src/evo/names.ts` | Tên loài procedural faux-Latin + epithet, deterministic per-seed |
| `src/evo/ecosystem.gd` | `src/evo/ecosystem.ts` | Eco tick: flora logistic, food chain, grudge valve, bio_shift, corpse tide |
| `src/evo/world_genome.gd` | `src/evo/worldGenome.ts` | Derive traits/turns/temperament từ seed; reveal/combo pump; eco mods |
| `src/evo/world_traits.gd` | `src/evo/worldTraits.ts` | Catalog 13 trait / 5 combo / 3 turn + title words + PatchKey |
| `src/game/storyteller.gd` | `src/game/storyteller.ts` | Mood engine bless/test/twist, hysteresis 20s, gapBias pacing |
| `src/game/chaos.gd` | `src/game/chaos.ts` | Chaos scheduler: warn→apply→tick→end, cooldown, stacking cap, MirrorLedger |
| `src/game/context.gd` | `src/game/context.ts` | GameContext: DNA/karma/chaos, bestiary, signals, save/load JSON v1 native |
| `src/game/game.gd` | `src/game/game.ts` | Stage machine + transitions (out/card/in), blocked-branch overlay dispatch, world-story pump, autosave |
| `src/game/cam.gd` | `src/gfx/renderer.ts` Camera | Damp follow, shake, to_world |
| `src/game/cell/cell_sim.gd` | `src/game/cell/CellStage.ts` | Cell sim thuần: spawn tables, player physics, NPC AI, pellet economy, zones, death — headless-testable |
| `src/game/cell/cell_events.gd` | `src/game/cell/cellEvents.ts` | 8 baseline chaos events + 3 world-gated variants + mirror face |
| `src/game/cell/cell_stage.gd` | `src/game/cell/CellStage.ts` (scene) | Scene node: layered canvases, hud/editor/pause wiring, shore button |
| `src/game/menu.gd` | `src/game/menu.ts` | Title / slots / NEW LIFE (difficulty) / CONTINUE / settings |
| `src/ui/hud.gd` | `src/ui/hud.ts` | DNA panel, chaos/karma meters, toasts/banners/floaters, ability bar |
| `src/ui/editor.gd` | `src/ui/editor.ts` | Part buy/sell rows, diet/pattern/size/hue/sat, grafts, row-rect records |
| `src/ui/pause.gd` | `src/ui/pause.ts` | Pause items, help view, world-genome view |
| `src/ui/tutorial.gd` | `src/ui/tutorial.ts` | Step engine + 0.4s skip chip |
| `src/gfx/renderer.gd` | `src/gfx/renderer.ts` (draw helpers) | hsl/panel/glow/disc/outlined text/vignette (CSS HSL math) |
| `src/gfx/cell_painter.gd` | `src/gfx/cell.ts` | Procedural cell painter (membrane/organelles/parts, CellPose) |
| `src/gfx/backdrop.gd` | `src/gfx/backdrop.ts` | Water (cell) + land (creature) backdrop: hills/stars/clouds/lawn + day-night curve |
| `src/gfx/particles.gd` | `src/gfx/particles.ts` | 7 particle kinds, ring-buffer pool, burst draw-order parity |
| `src/game/creature/creature_sim.gd` | `src/game/creature/CreatureStage.ts` (sim) | Creature sim thuần: shore boot, seedLandEcology (6 archetype genomes), movement x/z pseudo-depth, NPC AI `update_ents`, charm minigame, death/respawn, eco handoff — headless-testable |
| `src/game/creature/creature_events.gd` | `src/game/creature/creatureEvents.ts` | Creature chaos deck: 8 baseline + predator_convergence + world-gated (night_pack / titans_walk / rain mirror); earthquake blisters seeded in-stream (header divergence — TS Math.random) |
| `src/gfx/creature_rig.gd` | `src/gfx/creature.ts` (rig math) | 2-bone IK solver + spine/profile/head-lunge + leg draws + tail — f64 core, TS-printed pins 1e-9; headless-green trước painter (prototype-first) |
| `src/gfx/creature_painter.gd` | `src/gfx/creature.ts` (drawCreature) | Procedural creature painter: 3 sub-item clip (Ruling 11), coats/patterns, gait — three-RID contract (§6) |
| `src/game/creature/creature_stage.gd` | `src/game/creature/CreatureStage.ts` (scene) | Scene node: Camera2D rig ownership, screen-space canvases, z-sorted CreatureItem pool, hud/editor/pause wiring, debug cheats |
| `src/game/tribe/tribe_sim.gd` | `src/game/tribe/TribeStage.ts` (sim, :101-1171) | Tribe sim thuần: constructor world-seed (30 trees/26 bushes/1 hut/2 rivals), on_enter (restore/re-found/pack conversion), chief (click-move + WASD, role hotkeys, hut/totem, raid-touch death + respawn safest-of-8), tribesman AI (fight/job/arrive — wood quota even-shift), economy (delivery +8, regrow, sapling, hut build/repair/recruit, totem, festival passive), raid machine (clock, launch, siege, war_graves), beast, fires/lightning, fall/victory go_to — headless-testable |
| `src/game/tribe/tribe_events.gd` | `src/game/tribe/tribeEvents.ts` | Tribe chaos deck: 5 baseline + 4 gated defs (bold_raid ×1.5 remap, rival_festival bless ×1.3, siege_hoard two-wave, festival mirror face); storm's 2 ex-`Math.random` sites seeded in-stream (header divergence) |
| `src/game/tribe/tribe_stage.gd` | `src/game/tribe/TribeStage.ts` (:1176-1423 scene) | Scene node: Camera2D rig (rate 4 / zoom 0.95 — tribe numbers), z-sorted painter pool (3-RID contract tái sử dụng), hudRects update-dispatch, toastInset 190, fall/victory cards |

i18n: `tr()`/`tr_key()` (TranslationServer, key = câu EN) cho mọi user-facing string từ M2; CSV VI/EN (`assets/i18n/vi.csv`) đã land ở M2 (454+ key, structural audit trong `tests/test_i18n.gd`). Save: JSON `FileAccess` + `JSON.stringify` full precision tại `user://saves/`, shape-validate chặt (corrupt → start fresh), không migrate save TS. Lưu ý wire-key: **mọi bề mặt save-wire giữ key TS-verbatim camelCase** (`totalDnaEarned`, `killsByPlayer`, `comboFired`…) **trừ eco-species blob** — nó ride key native snake_case (`kills_by_player`, `grudge_t`, `harass_t` — seam naming từ Task 8, xem `ecosystem.gd` `from_json`), vì save native không bao giờ gặp save TS; công cụ save sau này đừng assum uniform camelCase.

## 6. Creature stage — Kiến trúc riêng (M3)

### Camera2D rig ownership (stage đầu tiên dùng Camera2D)

Cell stage bake camera vào `draw_set_transform` và **tắt rig**; creature stage
là stage đầu tiên **bật lại `game.cam.cam2d`** (`on_enter` bật, `on_exit` tắt
— menu/cell vẽ absolute screen space và kỳ vọng rig OFF). Hệ quả chia hai lớp
canvas:

- **World canvases** (ground/ents/fx): vẽ ở **identity transform** trong world
  coordinates — viewport áp camera transform cho default canvas.
- **Screen-space canvases** (sky/ui/veil/hud/editor/pause): **cancel live
  viewport canvas_transform bằng `affine_inverse()`** (đọc transform ĐÃ áp,
  không re-derive — đúng cho mọi thứ Camera2D làm) để các section TS
  screen-space stay pixel-anchored và un-shaken (TS vẽ backdrop/HUD ngoài
  cam.begin/end). Đây cũng là cơ chế của fix editor-preview (task 10): painter
  vẽ RS RID calls không kế thừa draw transform — base_pos/base_zoom ride cùng
  contract này.

Camera số liệu TS-verbatim: follow(px, pz·0.62, dt, 5), zoom 1.15 hằng số.

### Painter three-RID contract (creature_painter.gd)

Mỗi `draw_creature` tạo **3 sub-canvas-item caller-owned**: `clip_item` (mask
silhouette + pattern — `CANVAS_GROUP_MODE_CLIP_AND_DRAW`, mechanism shape-
chính xác của 4.2), `pattern_item` (con của clip — children render trong
shape), `front_item` (sibling sau clip — mọi thứ TS vẽ SAU body: near legs,
arms, head, horns, eyes). **Người gọi phải free cả 3 RID trước mỗi lần
redraw** của cùng CanvasItem (painter stateless, tạo mới mỗi call); stage
cho mỗi creature một CanvasItem riêng (pooled CreatureItem) để overlap order
đúng. Back/front split tồn tại vì RS child items composite sau TOÀN BỘ lệnh
của parent item.

### Hooks contract + debug cheats

Sim nhận **hooks dict** lúc construct (giống cell): `hud_toast / hud_banner /
hud_float_world / audio_play / cam_shake / fx_burst / fx_spawn /
storyteller_note_chaos_event / context_event` — scene cài instance thật vào
stub dicts của game ở `_ready` + rebind ở `on_enter` (task-7 review fix, cell
đối xứng). Sim không bao giờ đụng Input/scene; bot/tests đi mọi gate qua real
input pipeline. **Debug cheats surface** (bot parity law exception, TS-true):
các mutator `debug_*` là đường test duy nhất đụng thẳng sim — `debug_state`
(TS debugState shape), `debug_spawn_pack(n)` (pack thật quanh player) và
`debug_grant(dna, brain)` (cheat founding của bot — TS bot-creature.test.ts
mutate thẳng `c.genome.brain = 3; c.dna = 999`; native phải recompute derived
stats nên đi qua mutator); founding/click vẫn real-input.

### Perf instrument (mới ở M3 wrap)

- `tools/perf_creature_sim.gd` — **headless** (contention-immune, primary):
  60 ents × 300 ticks, timed window = `sim.update` thuần; standing tripwire
  4 ms (2× target — §5.3 target 2 ms hiện CHƯA đạt, ~2.5 ms @ 60 ents,
  ~42 µs/ent/tick tuyến tính; optimization là ứng viên M4 theo playbook M2).
- `tests/scenes/test_perf_creature.gd` — xvfb: real game, metrics SPLIT
  (bài học T10): pure sim step (recorded — llvmpipe contention làm phồng),
  painter draw pass ≤ **4 ms** assert (61 creatures RS command build đo
  ~1.1 ms), frame window recorded (~319 ms rasterization llvmpipe — rig
  caveat: GPU thật nhanh hơn nhiều; budget 4 ms nhắm GPU thật).
- Cell probe `tests/scenes/test_perf.gd` cũng split metric từ M3 wrap
  (T10 minor 4): sim_avg là cửa sổ `step_for_testing` thuần, render pass
  recorded riêng, không bao giờ assert.

## 7. Tribe stage — kiến trúc riêng (M4)

### Sim/scene tách + hằng số per-stage

`tribe_sim.gd` (RefCounted, hooks-Dictionary, `update(dt, inp)` M2 snapshot)
mirror creature_sim 1:1 — cùng patterns (lazy rng, fx_burst replay in-stream,
`_fire` no-op khi thiếu key, storyteller seam qua hooks với neutral defaults).
**Hằng số KHÔNG chia sẻ với creature** (plan Global Constraint: port
per-stage): WORLD_HALF **2400** (creature 2700), cam follow rate **4** zoom
**0.95** (creature 5/1.15), day cycle **240 s** (creature 180), night overlay
flat `rgba(10,10,40,0.4)` (creature depth·0.42), lawn 2-stop **không dim
isNight**. Chief CHÍNH là player creature — painter vẽ `ctx.genome` scale 2.1
mood 'happy'; creature painter phục vụ tribe nguyên trạng (3-RID contract §6
không đổi).

### hudRects — update-dispatch pattern

Sim SỞ HỮU rects (`sim.hudRects` — `{action: "hut"|"totem", r: {x,y,w,h}}`) và
hit-test + dispatch **trong update** (TS:284-303 — UI dispatch qua update như
mọi UI khác); scene re-position rects **mỗi render** (`_sync_hud_rects` —
TS renderHud filter+push). Click consume → snapshot's `take_click` flag
(by-reference snapshot — TS `inp.takeClick()`); stage mirror việc clear
one-shot của shared wrapper. Hover `setCursor` là scene-side. Hệ quả: một
`_do_render(0.0)` thủ công làm rects đọc được cùng tick (bot/tests dùng
cấu trúc này — xem bot_tribe header).

### Fall/victory go_to hooks

Sim không thấy game: fall path (TS:381-398 — village rỗng → banner 'THE TRIBE
HAS FALLEN' → 4 s latch → DELETE `flags.tribeState` + `save_all` hook +
`go_to('creature', 'BACK TO THE WILDS')`) và victory path (TS:400-409 — totem
100 → 2.5 s latch → `save_all` + ascend + `go_to('civ', 'THE FIRST CITY')`)
đều bắn qua hooks `go_to`/`save_all`. Latch `fallFired`/`victoryFired` chống
double-fire (~33 saves nếu không latch). Persist corpse-guard: không bao giờ
ghi blob làng chết (fall delete bị save_all viết đè — 3-bounce bug, pin ở
`test_world_creature_pins.gd`).

### Debug cheats surface (bot parity law exception, TS-true)

- `debug_state()` — read-only internal state (shape creature debugState).
- `debug_grant(food, wood)` — mutator DUY NHẤT của tribe (bot dùng để vượt
  gather round-trip cho gate thật: R · HUT cần wood ≥ 40, TOTEM cần 100
  food + 80 wood — TS bot-creature.test.ts mutate thẳng field; native đi
  mutator để recompute derived). Founding/click vẫn real-input.

### toast_inset reset rule

`hud.toastInset = 190` — tribe là native setter ĐẦU TIÊN (M3 ruling: civ 150
sau, tribe 190). on_enter bắn `hud_toast_inset(190)` (TS:154); **game-level
reset rule** (game.ts:213 — stage có UI góc dưới tự re-arm inset; game reset
về 0 ở MỌI stage switch, TRƯỚC on_exit/on_enter — port tại `game.gd`
`switch_stage`, pin `test_hud_tribe.gd::test_switch_stage_resets_toast_inset`).

### Perf instrument (M4 wrap)

- `tools/perf_tribe_sim.gd` — **headless** (contention-immune, primary):
  60 tribesmen + 6 rival warriors × 300 ticks, timed window = `sim.update`
  thuần; §5.4 target 2 ms **ĐẠT** (~0.71–1.00 ms avg @ 60+6, 5 runs); tripwire
  đứng 4 ms (2× target).
- `tests/scenes/test_perf_tribe.gd` — xvfb: real game, metrics SPLIT:
  sim tick recorded (llvmpipe contention), stage render-prep pass ≤ **4 ms**
  assert (pooled-item sync + hudRects + queues), frame window recorded
  (rasterization llvmpipe — rig caveat như §6).
