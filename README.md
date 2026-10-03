# PRIMORDIA — Native

**Eat. Evolve. Survive the universe's worst ideas.** PRIMORDIA là evolution god-game lấy cảm hứng từ arc 5 stage của Spore — nhưng thế giới procedural hoàn toàn, food chain sống thật (overhunting phá vĩnh viễn chuỗi thức ăn), và một Chaos engine liên tục viết lại luật trong khi bạn chơi. Mọi thứ sinh từ seed lúc runtime: không art asset, không audio file, không dependency runtime nào bên thứ ba. *(Bản TS gốc: `~/Desktop/RD/Spore` — frozen; tài liệu thiết kế song ngữ nằm ở đó.)*

## Trò chơi

- **Cell** — ăn, đeo organ, chạy khỏi thứ to hơn bạn. Mỗi phần mua bằng DNA đổi thân hình thật: membrane, spike, electro, jaw.
- **Creature** — lên bờ: thân 2-bone IK, gait cycles, coat procedural; dụ đủ bầy đàn bằng beat-bar charm rồi **thành lập bộ tộc**.
- **Tribe** — RTS-lite: gather/build/roles, rival raids, beast, sét gây cháy, lễ hội; nâng **Great Totem** lên 100% để bàn giao sang Civ.
- **Civ** — grand-strategy-lite: 3 slider đầu ra quốc gia (military/culture/economy), armada attack/charm/trade với power snapshot, lật thành phố rival bằng influence, chaos deck riêng (động đất, nổi dậy, thời kỳ hoàng kim, chiến tranh thế giới); thống nhất hành tinh → Space (M6).
- Giữa các stage: **world genome** riêng mỗi seed (traits/temperament), **storyteller** điều nhịp bless/twist, **chaos engine** (volcano, stampede, night raid, mutation storm…) nghe theo tính cách thế giới chứ không theo script.

## Vì sao native?

Bản TypeScript/Canvas đã feature-complete nhưng trần kỹ thuật đã rõ. Repo này port sang **Godot 4** để đi đường production:

- **App desktop thật** — Windows/Linux/macOS, không phải trình duyệt.
- **Tích hợp platform sâu hơn** — Steam/mods là con đường mở.
- **Trần hiệu năng cao hơn** — multithread, GPU khi cần.
- Web export vẫn mở — Compatibility renderer dùng được cho cả hai.

Non-goal: không đổi gameplay design (5 stage, catalog, chaos philosophy giữ nguyên).

## Trạng thái — Milestone 1 → 5 hoàn tất (sim core + cell + creature + tribe + civ stage full parity)

Toàn bộ sim layer, **cell stage**, **creature stage**, **tribe stage** và **civ stage** đã port 1:1 từ TS và xanh 100% test parity (fixtures JSON sinh từ bản TS frozen):

| Module | Nội dung |
|---|---|
| `src/core/rng.gd` | Seeded RNG Mulberry32 bit-exact (uint32 masking) |
| `src/evo/genome.gd` + `parts.gd` + `stats.gd` | Genome (bounds + clamp + hash), parts catalog, stats derive cell + creature |
| `src/evo/mutation.gd` + `names.gd` | mutate/crossover, anomaly/defect, tên loài procedural |
| `src/evo/ecosystem.gd` | Hệ sinh thái sống thật (mods, grudge valve, bio_shift, corpse tide) |
| `src/evo/world_genome.gd` + `world_traits.gd` | Mỗi run một thế giới mới: traits/turns/combo/temperament |
| `src/game/storyteller.gd` + `chaos.gd` | Mood engine + chaos scheduler (warn/stacking/mirror) |
| `src/game/context.gd` | GameContext + save/load JSON v1 native |
| `src/game/cell/` | Cell sim + scene layer (spawn tables, NPC AI, eat/attack, pellet field, DNA) |
| `src/game/creature/` | Creature sim + scene (shore boot, land ecology, NPC AI, charm minigame, founding) |
| `src/game/tribe/` | Tribe sim + events + scene (chief + tribesmen AI, economy, rival raids, beast, fires, festivals, Great Totem, fall/victory handoff) |
| `src/game/civ/` | Civ sim + events + scene (national sliders + regen, armada machine với power snapshot, rival personalities, hearts/karma/revolt, chaos deck civ, planet render screen-space không-Cam, portrait, victory → space placeholder) |
| `src/gfx/creature_rig.gd` + `creature_painter.gd` | Renderer creature procedural: IK 2-bone, spine/gait, coats — ba sub-item clip (tribe tái sử dụng nguyên trạng) |
| `src/ui/` + `src/game/menu.gd` | HUD, editor, pause, tutorial, menu (slots/difficulty/continue/settings) |

**Parity đo được** (chi tiết: [`docs/PARITY-M2.md`](docs/PARITY-M2.md) + [`docs/PARITY-M3.md`](docs/PARITY-M3.md) + [`docs/PARITY-M4.md`](docs/PARITY-M4.md) + [`docs/PARITY-M5.md`](docs/PARITY-M5.md)):

- **721 tests / 19548 checks / 0 failures** headless (`./tools/test.sh`).
- **Scene suites xanh dưới xvfb**: bot arc cell ×3 seeds ×2 determinism passes, bot creature (landfall thật + 2 phút chaos + founding) ×2 determinism, bot tribe (founding → roles → delivery → hut thật → raid trên clock thật → totem thật → victory) ×2 determinism, bot civ (tribe victory thật → refuse rung → sliders → launches thật → flips thật → thống nhất → space placeholder) ×2 determinism, menu real-click, editor real-click, pixel-assert suites (8/8 cell + 32/32 moments cell + 12 asserts creature painter + 40 asserts creature moments + 43 asserts tribe moments + 40 asserts civ moments), 4 perf probes.
- **§5.2 + §5.3 + §5.4 đạt**: (a) mọi feature của bản TS có mặt + có test pin, (b) bot arc qua real input pipeline, (c) econ probes TS-verbatim, (d) pixel-assert viewport capture.
- **A-B state-diff harness** (`tools/ab_test.sh`): M3 base `cell-parity-m2` → HEAD **IDENTICAL** (0 diff); M4 base `creature-parity-m3` → HEAD **IDENTICAL** (0 diff); M5 base `tribe-parity-m4` → HEAD **IDENTICAL** (0 diff) — các cửa sổ milestone không lay động standing dump (sha `ea35920b…` không đổi từ M2); harness fail-closed trên failure path (`tools/test_ab.sh`).
- **Perf**: cell sim tick 200 ents ≤ 8 ms (đo 7.6); creature sim tick 60 ents đo 2.5–2.7 ms vs target 2 ms (chưa đạt — candidate optimization, `docs/PARITY-M3.md` §16); creature painter draw 61 bodies ~1.1 ms (≤ 4 ms budget); tribe sim tick 60 tribesmen + 6 warriors ~0.7–1.0 ms (≤ 2 ms target **đạt**), tribe render-prep ≤ 4 ms; civ sim tick 4 cities + 3 armadas ~0.03 ms (≤ 2 ms target **đạt**, assert trực tiếp), civ render-prep ≤ 4 ms.

Chiến lược kiến trúc (tách sim khỏi Godot, determinism contract, parity fixtures, camera rig): [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Tech

- **Godot 4.2.2 stable** · GDScript typed · renderer **gl_compatibility** (GL 3.3)
- **Zero plugin** — test runner tự viết, headless
- Save JSON tại `user://saves/`, shape-validate, cùng seed → cùng thế giới

## Chạy test

```bash
cd ~/Desktop/RD/primordia-native
./tools/test.sh                 # headless suite (zero-plugin runner, tests/run.gd)
./tools/ab_test.sh              # A-B behavior-identity gate (xem docs/ARCHITECTURE.md §2)
./tools/test_ab.sh              # A-B fail-open hardening — failure-path test
./tools/test_bot.sh             # bot arc cell ×3 seeds ×2 determinism (xvfb)
./tools/test_bot_creature.sh    # bot creature: landfall + chaos + founding (xvfb)
./tools/test_bot_tribe.sh       # bot tribe: founding → hut → raid → totem → victory (xvfb)
./tools/test_bot_civ.sh         # bot civ: tribe victory → sliders → launches → thống nhất → space (xvfb)
./tools/probe_tribe.sh          # 9 econ probes tribe TS-verbatim (headless)
./tools/probe_civ.sh            # 14 econ probes civ TS-verbatim (headless)
./tools/test_menu.sh            # menu NEW LIFE flow qua real clicks (xvfb)
./tools/test_editor_click.sh    # editor purchase qua real clicks (xvfb)
./tools/test_visual.sh          # pixel-assert cell stage (xvfb)
./tools/test_visual_suite.sh    # six-moment pixel-assert suite cell (xvfb)
./tools/test_visual_creature.sh # pixel-assert creature painter (xvfb)
./tools/test_creature_scene.sh  # ten-moment creature visual suite (xvfb)
./tools/test_tribe_scene.sh     # ten-moment tribe visual suite (xvfb)
./tools/test_civ_scene.sh       # civ visual suite: planet, portrait clip, sliders, victory shimmer (xvfb)
./tools/test_perf.sh            # perf probe cell: 200 ents × 600 ticks ≤ 8 ms/tick (xvfb)
./tools/test_perf_creature.sh   # perf probe creature: 60 ents, painter draw ≤ 4 ms (xvfb)
./tools/test_perf_tribe.sh      # perf probe tribe: 60 tribesmen + 6 warriors, render-prep ≤ 4 ms (xvfb)
./tools/test_perf_civ.sh        # perf probe civ: 4 cities + 3 armadas, sim ≤ 2 ms + render-prep ≤ 4 ms (xvfb)
```

Headless exit 0 = xanh; scene suites in `*_OK` và exit 0. Chi tiết runner + ràng buộc `-s` mode: `docs/ARCHITECTURE.md` §4.

## Lộ trình

Kế hoạch milestone chi tiết (sim core → cell parity → creature → tribe/civ/space → CI/release): [`docs/specs/2026-09-29-native-migration-design.md`](docs/specs/2026-09-29-native-migration-design.md). **Tiếp theo: Milestone 6 — Space stage** (SpaceStage.ts 52.2K + spaceEvents.ts 2.5K — file TS lớn nhất của arc, gates §5.4 at space flavor; civ persist blob là founding input) (+ creature sim hot-loop optimization, `docs/PARITY-M3.md` §17).
