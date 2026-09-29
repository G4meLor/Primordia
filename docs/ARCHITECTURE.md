# PRIMORDIA Native — Kiến trúc (Milestone 1: sim core)

Ngày: 2026-09-29 · Trạng thái: sim core hoàn tất, mọi test xanh. Spec tổng: `docs/specs/2026-09-29-native-migration-design.md`.

## 1. Tách layer — sim không biết Godot scene tồn tại

Nguyên tắc cốt lõi của port: **sim layer là GDScript thuần trên `RefCounted`** — không Node, không scene, không `_process`; test được hoàn toàn headless.

- `src/core/`, `src/evo/`, `src/game/` — các class thuần, chỉ phụ thuộc lẫn nhau + `Rng`. GameContext phát event bằng **Godot signal** (`dna_gained`, `toast`) thay cho Bus/EV của TS — signal là API Godot duy nhất sim dùng, không đụng scene tree.
- Scene layer (Node2D/Control, input, camera, renderer procedural) vào ở **Milestone 2+** (cell stage full parity — xem spec §5). Scene chỉ gọi sim qua API công khai; không sim logic trong `_process` của node.
- Every def/data shape giữ wire của TS: Dictionary với key TS-verbatim (camelCase nơi cần parity save-wire: `totalDnaEarned`, `killsByPlayer`, `comboFired`…), gene/stats nội bộ snake_case.

## 2. Determinism contract

Cùng seed → cùng thế giới, bit-exact với bản TS:

- **Mọi randomness đi qua stream `Rng`** (`src/core/rng.gd`) — port bit-exact của Mulberry32 trong `src/core/rng.ts`. State luôn masked uint32 để GDScript `>>` trên int không âm khớp JS `>>>`; `_imul` khớp `Math.imul`. `branch()` sinh seed con như TS.
- **Cấm `randi()`/`randf()` global trong sim.** Ngoại lệ duy nhất được phép (sanctioned): `GameContext._init` — seed-picker mặc định là meta-level, nằm ngoài mọi stream sim. Test luôn truyền seed tường minh.
- World genome **derive lại từ seed** mỗi lần load (deterministic) — save chỉ mang runtime state overlay (revealed/comboFired/firedTurns/counters). Test determinism 1000-seed nằm trong `tests/test_world_genome.gd`.

## 3. Parity fixtures — trọng tài chống TS freeze

Fixtures JSON trong `tests/fixtures/` được sinh **một lần** từ repo TS frozen (`~/Desktop/RD/Spore`) bằng vitest (`tools/fixture-gen.test.ts` ở repo TS — tool không đụng game source). 6 file: `rng_stream`, `genome_stats`, `eco_tick`, `mutate_crossover`, `world_genome`, `storyteller_walk`; schema + recipe chi tiết trong `tests/fixtures/fixtures.README.md`.

- Test native so kết quả với JSON — **exactness hơn elegance**: float ghi full IEEE-754 double như `JSON.stringify`.
- Trong test GDScript, so float **không bao giờ dùng eps 0.0** — luôn `approx()` với eps ≥ 1e-9 (default của `tests/test_base.gd`) để né khác biệt parse/inRepresentation; fixture continuity được đảm bảo bởi chuỗi draw giống TS (cùng thứ tự consume).

## 4. Test runner — zero plugin

```bash
cd ~/Desktop/RD/primordia-native
~/.local/bin/godot --headless -s tests/run.gd   # hoặc ./tools/test.sh
```

`tests/run.gd` tự viết (không GUT/gdUnit4): discover `tests/test_*.gd`, chạy mọi method `test_*`, instance mới cho mỗi test (isolation state), in FAIL + message từng assertion, **exit 1 khi đỏ**. Chạy phải `cd` vào repo root trước (shell cwd reset).

Ràng buộc `-s` mode (không có editor script class cache — fresh clone/CI):

- Test file dùng **path-based extends**: `extends "res://tests/test_base.gd"`.
- Class resolve bằng `preload("res://...")`/`load("res://...")` — tự tham chiếu `class_name` của chính file đó cũng không resolve được (`rng.gd` dùng const `SELF_SCRIPT`).

## 5. Module map — 1:1 với TS frozen

| Native (Godot 4.2.2, GDScript typed) | TS counterpart | Nội dung |
|---|---|---|
| `src/core/rng.gd` | `src/core/rng.ts` | Mulberry32 bit-exact: next/range/int/chance/pick/weighted/shuffled/gauss/branch |
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

i18n: sim không có user-facing string qua i18n (names là procedural) — `tr()` (TranslationServer, key = câu EN) chỉ xuất hiện ở context toast; CSV VI/EN là stage-milestone sau. Save: JSON `FileAccess` + `JSON.stringify` full precision tại `user://saves/`, shape-validate chặt (corrupt → start fresh), không migrate save TS.
