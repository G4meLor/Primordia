# PRIMORDIA Native Migration — Design Spec

Ngày: 2026-09-29 · Repo: `~/Desktop/RD/primordia-native` · Trạng thái: user duyệt hướng (Godot 4 + GDScript, repo riêng, TS freeze, Cell stage parity trước)

## 1. Mục tiêu

Port PRIMORDIA từ TypeScript/Canvas sang **Godot 4 native** để hướng production: app desktop thật (Windows/Linux/macOS, web export vẫn mở sau này), trần hiệu năng cao hơn (multithread, GPU), tích hợp platform sâu hơn (Steam/mods/console là con đường mở).

**Non-goals:** không đổi gameplay design (5 stage, catalog, chaos philosophy giữ nguyên); không hỗ trợ save từ bản TS (save v1 fresh — game chưa release, chấp nhận); không viết plugin/lựa chọn ngoài Godot core ở giai đoạn đầu.

## 2. Tech stack

- **Godot 4.2.2 stable** (đã cài `~/.local/bin/godot`) — GDScript **typed** (`@warning` trên, tôn trọng static typing), **Compatibility renderer** (GL 3.3 — an toàn với máy hiện tại + web export sau này dùng cùng renderer).
- Zero plugin ở giai đoạn đầu: test runner tự viết (Godot headless `-s` script), không GUT/gdUnit4.
- Dev trên Ubuntu 20.04; CI sau này chạy `godot --headless` trên ubuntu runner, export cả 3 OS.

## 3. Repo layout

```
primordia-native/
  project.godot            # root Godot project (mở folder này bằng Godot)
  docs/
    DESIGN.md              # port từ bản TS + cập nhật native
    ARCHITECTURE.md        # kiến trúc native (viết khi sim core xong)
    specs/                 # catalog + specs copy từ bản TS (nguồn sự thật)
  src/
    core/                  # rng, i18n (TranslationServer CSV), events bus
    evo/                   # genome, mutation, ecosystem, world_genome, storyteller, parts, stats, names
    game/                  # game orchestrator, chaos scheduler, context/save
    cell/ creature/ tribe/ civ/ space/  # 5 stage (scenes + logic)
    gfx/                   # procedural painters (creature IK, cells, backdrop, particles)
  assets/
    i18n/vi.csv, en.csv
    icon/                  # icon procedural generate
  tests/
    run.gd                 # test runner entry (godot --headless -s tests/run.gd)
    test_*.gd              # unit tests (1 file/test module, mirror cấu trúc TS)
    bots/                  # headless play-bots đi đường UI thật
  tools/
    gen_icon.gd            # icon procedural
```

**Mang theo từ bản TS:** `docs/specs/` (catalog = nguồn sự thật cho mọi chất liệu), QC doctrine (bot đi đường UI thật, math probe số học, pixel-assert), naming conventions (snake_case file, patch key tập trung), bất biến §10 (pacifist, death one-way, one-kill-one-pay, restore replace, i18n VI/EN, determinism).

## 4. Layer architecture — tách sim khỏi Godot

Nguyên tắc cốt lõi: **sim layer là GDScript thuần (RefCounted), không biết Godot scene tồn tại** — test được hoàn toàn headless, port logic 1:1 từ TS:

- `src/evo/*.gd`, `src/game/chaos.gd`, `src/game/context.gd` — RefCounted classes, chỉ phụ thuộc `src/core/rng.gd`.
- Scene layer (Node2D/Control) chỉ gọi sim qua API công khai; không sim logic trong `_process` của node.
- Event bus: port `Bus/EV` pattern (Signals trên 1 autoload `Events`) thay cho chuỗi callback.

**Determinism:** port đúng thuật toán Mulberry32 (`rng.gd`) — cùng seed cùng thế giới; cấm `randi()/randf()` global; mọi randomness qua stream `Rng` (branch() như bản TS). Test determinism 1000 seed giữ nguyên.

**i18n:** Godot TranslationServer + CSV VI/EN (`assets/i18n/`) — `tr("English key")` thay `t()`; key vẫn là câu EN (giữ convention).

## 5. Migration order (mỗi bước = một milestone chơi được/test được)

1. **Sim core** ← *bắt đầu ở đây*: rng → genome → parts/stats → mutation (kèm anomaly M1/defect M2) → ecosystem (mods, grudge valve, bio_shift, corpse tide) → world_genome (derive/reveal/combo/turn/temperament) → storyteller → chaos scheduler → context/save. Mỗi module: unit tests headless + econ probes (mirror tests TS). **✅ Hoàn thành 2026-09-29, tag `sim-core-m1`.**
   - **Deferred từ final review M1 (nhặt khi đụng module):** eco revive-scan strict-read idiom (M2, khi đụng eco); `remaining_of(id)` inspect seam cho chaos (M2, khi stage wiring đụng chaos); injectable writer seam + test short-write failure (M2, khi save layer có stage-layer exercise); `GODOT="${GODOT:-...}"` override trong tools/test.sh (milestone CI §5.6).
2. **Cell stage full parity** — scene + input + camera + procedural cell renderer + NPC AI + DNA/HUD + chaos events cell + world reveal card + bot đi đường UI thật trong headless. **Parity được định nghĩa đo được:** (a) mọi cell-feature của bản TS có mặt (danh sách liệt kê trong plan từ tests/features.test.ts + bot.test.ts của TS), (b) bot headless đi full cell arc qua đường UI thật trên ≥3 seed, (c) econ probes + determinism 1000-seed xanh, (d) visual pixel-assert qua Godot viewport capture.
3. **Creature stage** — procedural creature renderer là port nặng nhất (IK 2-bone, gait cycles, coats): task riêng, prototype trước.
4. **Tribe → Civ → Space** — nhân pattern từ cell/creature.
5. **Catalog deferred items** (prehistory_scar, sense_defense_matrix, epoch_turn c/d, strange_mood…) — chỉ wire trên native sau khi parity.
6. **CI + release** — GitHub Actions: `godot --headless` test + export Windows/Linux (template export); release `v{version}` khi tag. Ghép repo GitHub + đè repo cũ theo đúng định nghĩa "ghi đè" khi đạt parity 5 stage.

## 6. Chất lượng & hiệu năng

- **Perf budget:** 200 entities @ 60fps trên máy mid (Compatibility renderer); sim tick giữ kiến trúc fixed-step 60Hz như TS.
- **QC gates giữ nguyên mức TS:** mọi task TDD; bot đi đường UI thật (bài học legs); econ probe per-trait + stacked; reviewer trio trước merge milestone.
- **Save:** JSON (Godot `FileAccess` + `JSON.stringify`) — shape-validate như v2 TS; `user://` path.

## 7. Rủi ro

| Rủi ro | Xử lý |
|---|---|
| Procedural creature renderer (IK, gait) là port nặng nhất | Task riêng ở milestone 3; prototype headless draw trước, so sánh pixel với bản TS |
| Audio synth (WebAudio → AudioStreamGenerator) | Port từng SFX; mood ambient crossfade dùng AudioStreamPlayer pool |
| Compatibility renderer khác biệt màu/particle so Canvas 2D | Calibrate palette qua scene test; particles dùng GPUParticles2D (hoặc CPUParticles2D nếu GPU yếu) |
| GDScript perf hot-loop | Typed + tránh allocation trong `_process`; nâng C# chỉ khi probe đo được |
| Godot 4.2 vs 4.3+ API churn | Khóa 4.2.2 cho đến khi parity, nâng version là task có chủ đích |
