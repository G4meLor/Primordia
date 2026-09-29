# PRIMORDIA — World Genome & Storyteller (Design Spec)

Ngày: 2026-09-28 · Nhánh: `feat/world-genome` · Trạng thái: được user duyệt hướng ("A làm xương sống, tự quyết phần còn lại")

## 1. Mục tiêu

Mỗi run của PRIMORDIA phải là **một thế giới mới**: chơi 3 run như 3 game khác nhau. Ba lớp chất liệu bất ngờ đan vào xương sống World Genome:

1. **Trait ẩn** — thế giới có "tính cách" sinh theo seed, người chơi gặp hậu quả trước, hiểu nguyên nhân sau.
2. **Combo reveal** — hai trait đụng nhau tạo hiệu ứng mới có cảnh báo tối thiểu; việc tìm ra combo là phần thưởng khám phá.
3. **Biến cố đổi thế giới + đột biến/lai loài** (hấp thu chất liệu B + C) — sự kiện lớn có hậu quả vĩnh viễn trong run, đột biến nghiêng theo tính cách thế giới.

Catalog cụ thể (trait nào, combo nào, event nào) **không nằm trong spec này** — nó là output của vòng nghiên cứu đa game (phần 9). Spec này khóa *cơ chế*, *điểm đan*, *ngân sách*, *tiêu chuẩn QC*.

## 2. Data model — `src/evo/worldGenome.ts`

Pure module, không depend vào game/ (test được độc lập):

```ts
interface WorldTraitDef {
  id: string;                    // 'predator_bloom'
  weight: number;                // xác suất được rút
  excludes: string[];            // trait loại trừ nhau
  effects: TraitEffect[];        // xem dưới
  reveal: RevealCondition;       // khi nào người chơi "biết"
  sigil: string;                 // icon 1 ký tự cho card/codex
}

type TraitEffect =
  | { kind: 'num';  key: string; value: number }   // patch số học
  | { kind: 'flag'; key: string; value: boolean }  // behavior flag
  | { kind: 'ecoSeed'; archetype: string; weight: number }; // lệch roster loài

type RevealCondition =
  | { kind: 'stageTime'; stage: StageId; seconds: number }
  | { kind: 'stageEnter'; stage: StageId }
  | { kind: 'extinct'; count: number }            // N loài tuyệt chủng
  | { kind: 'chaos'; above: number }
  | { kind: 'kill'; count: number };

interface WorldGenome {
  seed: number;                  // = run seed (derivation từ seed run)
  traits: WorldTraitDef[];       // 4–6 trait sau khi resolve loại trừ
  turns: WorldTurnDef[];         // 0–2 biến cố thế giới của run này (đủ điều kiện mới kích hoạt)
  revealed: Record<string, boolean>;   // runtime state, persist
  comboFired: Record<string, boolean>; // runtime state, persist
}
```

**Derivation determinism**: `deriveWorldGenome(seed: number): WorldGenome` dùng `new Rng(seed ^ 0x57ef)`. Cùng seed → cùng thế giới, mọi thứ khác trong run vẫn dùng `ctx.rng` riêng (không đụng chuỗi RNG của gameplay).

**API đọc** — mọi hệ hiện có đọc qua 2 hàm duy nhất, không import trait def trực tiếp:

```ts
world.num('predation_mult', 1): number   // patch số; thiếu trait → fallback
world.has('acid_rain'): boolean          // flag
world.archetypeWeights(): Record<string, number> // lệch roster eco
```

Trait key catalog tập trung ở `src/evo/worldTraits.ts` — mỗi integration point phải dùng key đã khai báo ở đây (không string rải rác).

## 3. Reveal & Combo

- Trait **áp dụng từ đầu run** dù chưa reveal. Reveal chỉ là *kiến thức*: toast card lớn (sigil + tên + mô tả 1 câu) + ghi vào Codex. Trải nghiệm mong muốn: hậu quả lạ xảy ra → vài phút sau card giải thích → "ờ ra là vậy".
- **Combo**: khai báo ở `worldTraits.ts` dạng `{ id, requires: [traitA, traitB], trigger: ComboTrigger, effect: TraitEffect[], title, body }`. Khi cả hai trait đã reveal + trigger xảy ra → card combo + effect bật **lúc đó** (combo là ngoại lệ duy nhất đổi hành vi giữa run, có chủ đích — nó là "moment"). `comboFired` đảm bảo 1 lần.
- ComboTrigger kinds ban đầu: `stageEnter`, `chaos`, `kill`, `stageTime` (dùng lại shape của RevealCondition).
- World-turn (biến cố vĩnh viễn, 0–2/run): event loại lớn do Storyteller thả khi điều kiện đúng; khi kích hoạt sẽ **ghi đè 1 trait** (tắt trait cũ, bật trait thay thế) + card "Thế giới đã đổi". Đây là chất liệu B — điểm đan vĩnh viễn chỉ qua cơ chế ghi đè này, không thêm cơ chế thứ hai. Shape: `{ id, replaces: traitId, replacement: traitId, title, body, trigger: RevealCondition }` — chỉ lưu id trong save, def tra từ catalog (trait `replacement` phải là trait hợp lệ của catalog, có thể là trait "chỉ đến từ world-turn").
- **Convention key patch**: snake_case token tập trung khai báo trong `worldTraits.ts` (VD `predation_mult`, `growth_mult`, `flora_cap_add`) — các file hệ import hằng từ đó, không gõ string lại.

## 4. Storyteller — `src/game/storyteller.ts`

Quan sát → chọn nhịp, **không đổi** cỗ máy ChaosScheduler:

- **Tín hiệu** (đọc từ GameContext + stage mỗi 5s game-time): `chaos`, `karma`, sức khỏe eco (số loài sống/flora), đà DNA gần đây, số lần chết của player trong stage, tiến độ stage (flags).
- **Moods**: `bless` (player chật vật: eco yếu, chết nhiều → quà: event hiền, DNA gió, speciation dễ), `test` (trung tính — hành xử như hiện tại), `twist` (player lấn át: chaos cao, giàu, sát phạt → phá nhịp: event variant lạ, gap ngắn hơn).
- **Tác động**: (a) nhân vào `ChaosContext.gapMult` tại call site (±30% theo mood — scheduler không sửa); (b) bias weight của event def qua map `bias: Record<eventId, number>` mà stage áp vào `weight()`; (c) giữ hàng đợi **story beats** một-lần (set-piece nhỏ, ví dụ "đàn vật nuôi nhớ bạn" sau chuỗi tha killed) — stage poll `storyteller.poll()` mỗi frame.
- Ràng buộc bất biến: pacifist ending không bao giờ bị storyteller phá (mood `twist` phải kiểm tra karma > 0.5 → hạ về `test`); maxConcurrent của scheduler vẫn đứng; warn window không bị bỏ qua (twist không dùng event không-warn khi chaos < 0.5).

## 5. Điểm đan vào hệ có sẵn (file → thay đổi)

| Hệ | File | Điểm đan |
|---|---|---|
| Context | `src/game/context.ts` | `world: WorldGenome` field; sinh trong constructor từ seed; **save v2** (thêm blob `world`), load v1 → re-derive từ seed (deterministic nên save cũ "nhận" world miễn phí); persist `revealed`/`comboFired` |
| Chaos | 5 file `*Events.ts` | event def chuyển thành **factory nhận world** → sinh variant theo trait (VD: meteor thành mưa axit khi có flag tương ứng); weight() đọc `world.num(key, 1)` |
| Ecosystem | `src/evo/ecosystem.ts` | `tick()` đọc patch: `growth_mult`, `predation_mult`, `speciation_mult`, `flora_cap_add` (fallback 0/1 — eco không biết world tồn tại nếu không có trait) |
| Mutation | `src/evo/mutation.ts` | `mutate(g, rng, rate, bias?: { diet?, coat?, hueShift? })` — bias từ world; crossover giữ nguyên (bất biến Gene Splicer) |
| Roster | nơi stage seed eco (Cell/Creature/Space) | lọc/ghi trọng số archetype theo `world.archetypeWeights()` |
| Storyteller | 5 stage `update()` | gọi `storyteller.update(dt, signals)` + nhân gapMult + poll beats |
| UI | `src/ui/hud.ts`, `src/ui/pause.ts` | card reveal (dùng toast system sẵn), mục "Gen Thế Giới" trong Codex/Bestiary, sigil thế giới cạnh tên trên menu/pause |
| Editor | `src/ui/editor.ts` | **không đụng** (bất biến cân bằng part/DNA trừ khi catalog chốt 1 twist part hiếm — phải qua QC số học riêng) |

## 6. Save & migration

- `SaveData.version = 2`; thêm `world: { seed, traitIds: string[], turnIds: string[], revealed: Record<string, boolean>, comboFired: Record<string, boolean> }` — chỉ persist **id + runtime state**, defs tra lại từ catalog (catalog thay đổi giữa các bản build không hỏng save cũ; trait id mất khỏi catalog → bỏ qua an toàn).
- `load()`: version 2 → cần `world` hợp lệ (thiếu/hỏng → re-derive từ seed, mất revealed chấp nhận được); version 1 → migrate như hiện tại + re-derive world từ seed.

## 7. i18n & ngôn ngữ trong game

Mọi text mới (tên trait, mô tả, card combo, world-turn, beat) đi qua `t()`: tiếng Anh là key, thêm đủ entry Việt. Sigil dùng 1 ký tự emoji/unicode, không phải asset.

## 8. Chiến lược test

- **Unit (`tests/world.test.ts`)**: determinism (cùng seed → cùng trait set, 1000 seed không crash); resolve loại trừ đúng; `num`/`has` fallback; serialize v2 + load v1 migration; storyteller mood state machine (pacifist không bao giờ gặp twist).
- **Math probe (`tests/econ-probe.test.ts` mở rộng)**: với từng trait bật đơn lẻ + từng cặp combo: chạy eco sim 60 phút game-time → không loài nào âm pop, flora không kẹt 0, ít nhất 2 loài sống sót (ngưỡng sinh tồn tối thiểu); DNA income mỗi trait nằm trong ±40% so baseline trừ trait thuộc type "rủi ro cao" (được phép lệch, phải ghi ngân sách trong catalog).
- **Bot arc × seed**: `bot-arc.test.ts` mở rộng chạy **3 world seed cố định** qua full arc (replay value test thật: cùng đường UI, thế giới khác nhau không được softlock — bài học legs).
- **Visual**: card reveal + codex world section qua `scripts/shots.mjs` + `visual-assert.mjs` (pixel-check, không tin preview).
- **QC loop cuối**: 3 agent review song song (bug / balance-số học / quality-i18n) — mô hình đã bắt được bot gian lận lần trước.

## 9. Quy trình nghiên cứu (Workflow) & ngân sách catalog

Pipeline 5 pha do user ủy quyền ("dùng 1 workflow lớn: nghiên cứu → phản biện → góp nhặt → triển khai → QC loop"):

1. **Nghiên cứu** (~8 agent song song, web): deconstruction theo lớp bất ngờ — Spore, Dwarf Fortress, RimWorld (traits/storyteller), Noita (chaos nổi), Caves of Qud (mutation), Rain World (ecosystem AI), Creatures (di truyền số), FTL + King of Dragon Pass (event design). Mỗi agent trả về: mechanic inventory + *cơ chế gây bất ngờ của nó* + khả năng map vào PRIMORDIA.
2. **Phản biện** (3 agent đối kháng): novelty (có mới không so với những gì game đã có: genetic memory, eco extinction, chaos meter) / fit (2D canvas, zero-dep, 5-stage, ràng buộc bất biến mục 10) / cost-QC (đo được không, probe số học viết được không). Mỗi ý tưởng sống sót phải được **thêu lại**: ghép ý tưởng từ ≥2 nguồn thành mechanic mang tên PRIMORDIA, không copy nguyên xi.
3. **Góp nhặt**: catalog cuối — **10–14 trait, 4–6 combo, 8–12 event variant, 2–3 mechanic mutation, 0–2 world-turn, 1–2 beat/storyteller** — mỗi mục: spec ngắn + integration key + reveal condition + ngân sách lệch cân bằng + probe tương ứng. Catalog ghi vào `docs/superpowers/specs/2026-09-28-world-catalog.md` và là nguồn sự thật khi implement.
4. **Triển khai**: task theo chủ sở hữu file (mỗi agent 1 cụm file, không đụng chéo), TDD trước. Thứ tự: worldGenome core → context/save v2 → eco/mutation patches → event factories → storyteller → UI/codex → catalog wire-in.
5. **QC loop**: như mục 8, lặp đến sạch, ghi `qc/LOG.md` (tiếp đếm round 11+).

## 10. Bất biến không được phá (từ ARCHITECTURE.md + QC 10 vòng)

1. Pacifist ending sống sót (karma harmony không bị xói — storyteller đã có gate).
2. Death là cửa một chiều mỗi fade; mọi heal mới gate `php > 0 && deathFade <= 0`.
3. One-kill-one-pay; restore replace không append; save-flush trước ghi disk.
4. Zero runtime deps; seeded determinism; i18n VI/EN đầy đủ.
5. Mọi gate progression phải bot đi qua **đường UI thật** (bot không được gán genome trực tiếp).

## 11. Rủi ro & xử lý

- **Trait nông (stat modifier nhàm)** → catalog bắt buộc mỗi trait có ít nhất 1 góc "hành vi" (flag/ecoSeed/reveal-story), không chỉ nhân số.
- **Cân bằng vỡ** → math probe per-trait + per-combo là điều kiện duyệt; trait vượt ngân sách ±40% phải khai báo "rủi ro cao" + có counter-play trong mô tả.
- **Save vỡ** → v2 chỉ persist id + state phẳng; mọi re-derive đều từ seed; shape-validate như v1.
- **Workflow trôi** → catalog là output khóa; nếu nghiên cứu cho ít hơn ngân sách dưới → lấy số dưới, không nhồi.
