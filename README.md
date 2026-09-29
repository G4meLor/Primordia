# PRIMORDIA — Native

**Eat. Evolve. Survive the universe's worst ideas.** PRIMORDIA là evolution god-game lấy cảm hứng từ arc 5 stage của Spore — nhưng thế giới procedural hoàn toàn, food chain sống thật (overhunting phá vĩnh viễn chuỗi thức ăn), và một Chaos engine liên tục viết lại luật trong khi bạn chơi. Mọi thứ sinh từ seed lúc runtime: không art asset, không audio file, không dependency runtime nào bên thứ ba. *(Bản TS gốc: `~/Desktop/RD/Spore` — frozen; tài liệu thiết kế song ngữ nằm ở đó.)*

## Vì sao native?

Bản TypeScript/Canvas đã feature-complete nhưng trần kỹ thuật đã rõ. Repo này port sang **Godot 4** để đi đường production:

- **App desktop thật** — Windows/Linux/macOS, không phải trình duyệt.
- **Tích hợp platform sâu hơn** — Steam/mods là con đường mở.
- **Trần hiệu năng cao hơn** — multithread, GPU khi cần.
- Web export vẫn mở — Compatibility renderer dùng được cho cả hai.

Non-goal: không đổi gameplay design (5 stage, catalog, chaos philosophy giữ nguyên).

## Trạng thái hiện tại — Milestone 1 + 2 hoàn tất (sim core + cell stage full parity)

Toàn bộ sim layer và **cell stage đã port 1:1 từ TS** và xanh 100% test parity (fixtures JSON sinh từ bản TS frozen):

| Module | Nội dung |
|---|---|
| `src/core/rng.gd` | Seeded RNG Mulberry32 bit-exact (uint32 masking) |
| `src/evo/genome.gd` + `parts.gd` + `stats.gd` | Genome (bounds + clamp + hash), parts catalog, stats derive |
| `src/evo/mutation.gd` + `names.gd` | mutate/crossover, anomaly/defect, tên loài procedural |
| `src/evo/ecosystem.gd` | Hệ sinh thái sống thật (mods, grudge valve, bio_shift, corpse tide) |
| `src/evo/world_genome.gd` + `world_traits.gd` | Mỗi run một thế giới mới: traits/turns/combo/temperament |
| `src/game/storyteller.gd` + `chaos.gd` | Mood engine + chaos scheduler (warn/stacking/mirror) |
| `src/game/context.gd` | GameContext + save/load JSON v1 native |
| `src/game/cell/` | Cell sim (spawn tables, NPC AI, eat/attack, pellet field, DNA) + scene layer |
| `src/ui/` + `src/game/menu.gd` | HUD, editor, pause, tutorial, menu (slots/difficulty/continue/settings) |

**M2 parity đo được** (chi tiết: [`docs/PARITY-M2.md`](docs/PARITY-M2.md)):

- **381 tests / 15293 checks / 0 failures** headless (`./tools/test.sh`).
- **7 scene suites xanh dưới xvfb**: boot, bot arc ×3 seeds ×2 determinism passes (bot đi 2 phút "messy play" qua **real input pipeline** — `Input.parse_input_event`, không bao giờ gọi thẳng sim), menu real-click, editor real-click, 2 pixel-assert visual suites (8/8 + 32/32 asserts), perf probe.
- **4 tiêu chí §5.2 đều đạt**: (a) mọi cell-feature của bản TS có mặt + có test pin, (b) bot arc ×3 seeds, (c) econ probes + determinism 1000-seed, (d) pixel-assert viewport capture.
- **Perf probe 200 ents**: ≤ 8 ms/tick sim (đo 7.6–7.8 ms) — probe đã bắt và fix hot-loop O(N²) của sim (flat typed mirrors + neighborhood grids). Behavior-identity chứng minh bằng **A-B state-diff harness** (`tools/ab_state_dump.gd`): base ≡ HEAD với 2 distance site reverted = 0 diff; phần delta còn lại là sanctioned f64 class (chi tiết: PARITY-M2.md §17).

Chiến lược kiến trúc (tách sim khỏi Godot, determinism contract, parity fixtures): [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

**Tiếp theo: Milestone 3 — creature stage** (procedural creature renderer là port nặng nhất: IK 2-bone, gait cycles, coats — task riêng, prototype trước).

## Tech

- **Godot 4.2.2 stable** · GDScript typed · renderer **gl_compatibility** (GL 3.3)
- **Zero plugin** — test runner tự viết, headless
- Save JSON tại `user://saves/`, shape-validate, cùng seed → cùng thế giới

## Chạy test

```bash
cd ~/Desktop/RD/primordia-native
./tools/test.sh          # headless suite (zero-plugin runner, tests/run.gd)
./tools/test_bot.sh      # bot arc ×3 seeds ×2 determinism (xvfb, real input pipeline)
./tools/test_perf.sh     # perf probe: 200 ents × 600 ticks ≤ 8 ms/tick (xvfb)
./tools/test_menu.sh     # menu NEW LIFE flow qua real clicks (xvfb)
./tools/test_editor_click.sh   # editor purchase qua real clicks (xvfb)
./tools/test_visual.sh   # pixel-assert cell stage (xvfb)
./tools/test_visual_suite.sh   # six-moment pixel-assert suite (xvfb)
```

Headless exit 0 = xanh; scene suites in `*_OK` và exit 0. Chi tiết runner + ràng buộc `-s` mode: `docs/ARCHITECTURE.md` §4.

## Lộ trình

Kế hoạch milestone chi tiết (sim core → cell parity → creature → tribe/civ/space → CI/release): [`docs/specs/2026-09-29-native-migration-design.md`](docs/specs/2026-09-29-native-migration-design.md).
