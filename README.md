# PRIMORDIA — Native

**Eat. Evolve. Survive the universe's worst ideas.** PRIMORDIA là evolution god-game lấy cảm hứng từ arc 5 stage của Spore — nhưng thế giới procedural hoàn toàn, food chain sống thật (overhunting phá vĩnh viễn chuỗi thức ăn), và một Chaos engine liên tục viết lại luật trong khi bạn chơi. Mọi thứ sinh từ seed lúc runtime: không art asset, không audio file, không dependency runtime nào bên thứ ba. *(Bản TS gốc: `~/Desktop/RD/Spore` — frozen; tài liệu thiết kế song ngữ nằm ở đó.)*

## Vì sao native?

Bản TypeScript/Canvas đã feature-complete nhưng trần kỹ thuật đã rõ. Repo này port sang **Godot 4** để đi đường production:

- **App desktop thật** — Windows/Linux/macOS, không phải trình duyệt.
- **Tích hợp platform sâu hơn** — Steam/mods là con đường mở.
- **Trần hiệu năng cao hơn** — multithread, GPU khi cần.
- Web export vẫn mở — Compatibility renderer dùng được cho cả hai.

Non-goal: không đổi gameplay design (5 stage, catalog, chaos philosophy giữ nguyên).

## Trạng thái hiện tại — Milestone 1: sim core hoàn tất

Toàn bộ sim layer đã port 1:1 từ TS và xanh 100% test parity (fixtures JSON sinh từ bản TS frozen):

| Module | Nội dung |
|---|---|
| `src/core/rng.gd` | Seeded RNG Mulberry32 bit-exact (uint32 masking) |
| `src/evo/genome.gd` | Genome — nguồn sự thật của sinh vật, bounds + clamp + hash |
| `src/evo/parts.gd` + `stats.gd` | Parts catalog (cost/graft) + stats derive |
| `src/evo/mutation.gd` | mutate/crossover, anomaly/defect, bias |
| `src/evo/names.gd` | Tên loài procedural |
| `src/evo/ecosystem.gd` | Hệ sinh thái sống thật (mods, grudge valve, bio_shift, corpse tide) |
| `src/evo/world_genome.gd` + `world_traits.gd` | Mỗi run một thế giới mới: traits/turns/combo/temperament |
| `src/game/storyteller.gd` | Mood engine bless/test/twist |
| `src/game/chaos.gd` | Chaos scheduler (warn/stacking/mirror) |
| `src/game/context.gd` | GameContext + save/load JSON v1 native |

Chiến lược kiến trúc (tách sim khỏi Godot, determinism contract, parity fixtures): [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Tech

- **Godot 4.2.2 stable** · GDScript typed · renderer **gl_compatibility** (GL 3.3)
- **Zero plugin** — test runner tự viết, headless
- Save JSON tại `user://saves/`, shape-validate, cùng seed → cùng thế giới

## Chạy test

```bash
cd ~/Desktop/RD/primordia-native
./tools/test.sh        # hoặc: ~/.local/bin/godot --headless -s tests/run.gd
```

Exit 0 = xanh. Chi tiết runner + ràng buộc `-s` mode: `docs/ARCHITECTURE.md` §4.

## Lộ trình

Kế hoạch milestone chi tiết (sim core → cell parity → creature → tribe/civ/space → CI/release): [`docs/specs/2026-09-29-native-migration-design.md`](docs/specs/2026-09-29-native-migration-design.md).
