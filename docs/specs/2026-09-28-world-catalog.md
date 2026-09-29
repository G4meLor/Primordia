# PRIMORDIA — World Catalog (bản chốt vòng nghiên cứu)

Ngày: 2026-09-29. Nguồn sự thật khi implement. Dẫn liệu: spec `2026-09-28-world-genome-design.md` (mục 2, 9, 11) + seed catalog `src/evo/worldTraits.ts` + 48 mechanic deconstruct từ 8 game (Spore/EVO, Dwarf Fortress, RimWorld, Noita, Caves of Qud, Rain World, Creatures 1-3, FTL×King of Dragon Pass) + 3×48 verdict phản biện (novelty / fit / cost-QC).

Quy ước: id + integration key tiếng Anh snake_case; mô tả tiếng Việt; reveal condition chỉ dùng kinds có sẵn (`stageTime` / `stageEnter` / `extinct` / `chaosAbove` / `kill`); mọi text qua `t()` (VI/EN). `[WOVEN: A × B]` = ghép ≥2 nguồn thành mechanic mang tên PRIMORDIA.

---

## I. Traits

**Lớp trình bày chung cho mọi reveal (Retroactive Myth — Caves of Qud, keep×3, áp cho toàn bộ mục I):** reveal card trích sự kiện THẬT của run (timestamp extinction/kill đã track trong bestiary) thay vì lore generic; world name (WORLD_ADJ + NOUN) ghép từ trait đã lộ; sigil hiện cạnh tên trên pause/menu. Reveal sau ≥2 quan sát trực tiếp hiệu ứng, băng mục tiêu 45–150s từ quan sát đầu → card.

### I.a Seed traits (8 — đã implement trong `worldTraits.ts`)

| id | hiệu ứng | reveal | góc hành vi |
|---|---|---|---|
| `hungry_bloom` | herb_drain×1.6 + ecoSeed herbivore×1.5 | stageTime cell 90s | ecoSeed |
| `iron_gut` | meal_dna×1.2 | kill 15 | num |
| `toxin_sea` | flag `toxin_rain_cell` | chaosAbove 0.45 | flag |
| `swift_world` | growth×1.25 + speciation×1.5 | stageEnter creature | num |
| `old_blood` | meal_dna×0.9 + ecoSeed titan×2 | stageTime cell 180s | ecoSeed |
| `pirate_wind` | flag `raider_bold` | stageEnter tribe | flag |
| `calm_veil` | growth 1.05 + speciation 0.8 | stageEnter civ | num |
| `mutation_moon` | mutation_rate_add 0.15 + flag `wild_mutations` | chaosAbove 0.6 | flag |

### I.b Trait mới (5 — tổng 13/14)

| id | sigil | spec (hành vi người chơi thấy) | integration key | reveal | ngân sách + probe | nguồn |
|---|---|---|---|---|---|---|
| `prehistory_scar` | ⌛ | **[WOVEN: Deep-Time Ledger (DF) × Sterile Heart (Spore/EVO)]** `deriveWorldGenome` sinh 1 sự kiện tiền sử có tên (VD "Thủy mực Đỏ — loài apex cũ tuyệt chủng 3 kỷ trước"). Roster hiện tại lệch theo di sản: ít apex, thừa herbivore; bestiary loài tuyệt chủng đầu tiên ghi dòng nguyên nhân trỏ về sự kiện; một lineage kế thừa bị kẹp pop quanh mức sàn. Người chơi thấy hệ sinh thái đang sống là hậu duệ của một câu chuyện xảy ra trước mình. | ecoSeed `{apex: −0.4, herbivore: +0.5}`; flag `prehistory_line` (dòng bestiary + pop-floor 1 lineage) | stageEnter creature — card "Vì sao thế giới này yếu về đỉnh chuỗi thức ăn" | DNA income ±40% so baseline; econ-probe 1000 seed × 60' eco sim: ≥2 loài sống, flora không kẹt 0, lineage kẹp pop ≥0. Vượt → khai báo rủi ro cao + counter-play. | DF, Spore/EVO (atom vùng-cấm, bỏ claim không gian vì eco sim population-level) |
| `world_temperament` | ☯ | **[WOVEN: Storyteller Personality Split (RimWorld) × Seeded Alchemy flavor-bias (Noita)]** Mỗi seed sinh 1 temperament ẩn (Cradle / Lean Seasons / Wildcard) là tham số DUY NHẤT điều nhịp ChaosScheduler: Cradle luôn có grace sau threat, Lean chu kỳ đói dài nhàng, Wildcard không grace nhưng streak cap ≥3. Sau ~10–15 tick event, codex mở dòng "Thế giới này có tính khí…", bestiary bắt đầu dán nhãn event theo archetype. Cấm lập tính cách ẩn thứ hai — mọi hệ variant/pacing đọc từ trường này. | `temperament_gap_mult` (±30% qua gapMult, scheduler không sửa), `streak_cap`, `grace_window`; bias map event | stageTime cell 300s | % run chết trước tick N per archetype ≤ baseline +15%; log max consecutive high-severity events (hard cap ≥3 cho archetype có grace). | RimWorld, Noita (chỉ lớp bẻ flavor — bảng recipe triad đã bỏ, xem VII) |
| `temperament_bands` | ◐ | Mỗi loài trong roster mang dải hành vi theo seed (bold↔shy, aggression band): hai seed cho cùng loài nhưng một bầy rình rồi bỏ chạy, bầy kia dồn ưu tiên cả khi bị đuổi. Bestiary tự điền hồ sơ tính cách sau vài lần chạm trán; cá thể sống sót qua nhiều lần gặp được đặt tên riêng — kẻ thù cũ người chơi tự nhận diện. Dùng chung primitive "cá thể được đánh dấu" với beat `strange_mood`. | flag `behavior_band` (nhân aggression/fear đã là stat); bestiary profile counter | kill ≥3 trên cùng loài | survival theo decile: chênh stage-X survival giữa seed percentile 10 và 90 >25% → siết dải về giữa; track first-encounter death rate theo decile. | Rain World |
| `sense_defense_matrix` | ◍ | Bật ma trận phát hiện theo cặp trong arena: sense gene (thị giác chuyển động, khứu máu, thính âm) × defense gene (camo, sinh quang, im lặng) — camo ăn thị giác nhưng khứu máu bỏ qua; sinh quang dụ loài săn bằng mắt nhưng dẫn con mồi. Editor vẽ mờ cone giác quan của predator (read-only). Người chơi compose genome để trả lời "thế giới này nhìn tôi bằng gì" và đổi câu trả lời khi sang vùng có loài săn khác. Một ô đặc biệt của ma trận là **mimicry** (Mang mặt kẻ săn mồi — Rain World): gene appearance/pheromone đảo reaction — con mồi bỏ chạy, rival predator nhắm bạn; decay theo lần bị cắn, là lời nói dối hai lưỡi có giá. | flag `detection_matrix` (lookup nhân cặp mỗi encounter, không per-frame); `mimicry_cell` (decay theo bite) | stageEnter creature | bot 1000 encounter/cặp: một cặp >2× median hoặc <0.5× → chỉnh hệ số sense; entropy defense-pick theo stage tụt đột ngột = tín hiệu combo độc tôn; mimicry-share 20–30% encounter (A/B giá), track backfire deaths riêng. | Rain World (Ma trận giác quan × ngụy trang + Mimicry Splice dệt vào) |
| `kin_memory` | ⚱ | **[WOVEN: Hereditary Grudge (RimWorld) × Grudge Ledger (Rain World) × Ledger Payback (KoDP) × The Law (Noita)]** Một loài social trong roster mang kin-tag; sổ thù species-state (MỘT ledger duy nhất) ghi mọi kill của player lên network: chúng chuyển từ trốn tránh sang áp sát theo đàn, ưu tiên mục tiêu yếu, badge grudge trên bestiary. Trước lần ghi đầu có đúng 1 cảnh báo ("kin của con này đang nhìn" — bài học harsh & opaque). Đường chuộc: hiến biomaterial hoặc giải cứu khỏi predator; decay half-life ~30–50 thế hệ ngắn. Mặt karma-cao: beat không-lặp trích loài ĐƯỢC tha (Ledger Payback). Valence âm sâu nhất (taboo: ăn con, diệt sạch, phá nest) cash-in đúng 1 lần thành Mourning Swarm qua pipeline chaos — warn-less CHỈ khi chaos ≥0.5, KHÔNG ghi ngược loài đã tuyệt chủng vào eco. | flag `kin_grudge` (state trên EcoSpecies — `killsByPlayer` đã track); behavior weight shift; `appeasement_cost` | kill ≥1 trên loài kin-tag | P(extinction \| grudge) <2× baseline — vượt thì bắt buộc appeasement hoặc decay khi loài yếu đi; harassment cap per 100 ticks; probe timestamp-first-grudge vs abandonment; ledger-hit 100% cho beat trích dẫn. | RimWorld, Rain World, KoDP, Noita |

---

## II. Combos

Combo khai báo ở `worldTraits.ts` (`{ id, requires, trigger, effect, title, body }`), cả hai trait đã reveal + trigger xảy ra → card + effect bật lúc đó; `comboFired` đảm bảo 1 lần. Ngân sách 4–6, hiện có 5.

### II.a Seed combos (2 — đã implement)

| id | legs | trigger | effect |
|---|---|---|---|
| `rot_circle` | hungry_bloom + toxin_sea | extinct ≥1 | death→flora (chiều hiền; đếm extinct TỰ NHIÊN) |
| `war_graves` | old_blood + pirate_wind | stageTime tribe 60s | tribe pressure |

### II.b Combo mới (3)

**`corpse_tide`** — legs: `iron_gut` × `toxin_sea`; trigger: `kill` ≥15. Nguồn: DF (Thủy triều Xác).
Spec: mỗi kill của player trong scope turn để lại xác không phân hủy thành hazard nằm lại; xác nổ thành 2–3 scavenger nhỏ hung hãn (cap tổng sống đồng thời ≤8% tổng pop). Competence inversion: diệt mối đe dọa chính là máy sinh mối đe dọa — "ở đây cái chết không kết thúc". Tách điều kiện với `rot_circle`: tide đếm `killsByPlayer`, rot đếm extinct tự nhiên. Counter-play ghi trên trait: dọn xác tốn DNA.
Ngân sách: **rủi ro cao** (cascade) — khai báo trong catalog; assert tự tắt ≤5' game-time khi nguồn kill dừng; scavenger sống ≤8% pop; DNA income trait đơn giữ ±40% (econ-probe ma trận trait đơn × combo).

**`selection_sweep`** — legs: `mutation_moon` × `toxin_sea`; trigger: `chaosAbove` 0.45. **[WOVEN: Beauty Is Not Fitness (Creatures) × Self-Harm Tactics (FTL×KoDP) × Material-signature entry (Noita)]**
Spec: cá thể nhiều ornament (hue/pattern cao) tốn metabolic hơn trong đợt độc tố — selection sweep xảy ra trước mắt người chơi: histogram màu của cả hệ dịch rõ sau đúng một event, bestiary ghi "sự chọn lọc tự nhiên vừa xảy ra". Red-tide độc cả carrier buộc player chọn: cull chính đàn mình yêu thích, hoặc dọn vùng tốn phí để cứu hệ.
Ngân sách: survival differential ornate vs plain 15–30% (cap 50% — không thành trap stat); hue-histogram dịch 15–30%/event; ornament-frequency hồi phục 5–10 gen; Monte Carlo pair on/off — lệch >2σ từ baseline thì hand-tune.

**`borrowed_flesh`** — legs: `swift_world` × `old_blood` (cặp cross-stage); trigger: `stageEnter` tribe. **[WOVEN: Intersect Archetypes (Spore/EVO) × Anatomy Is the Inventory (Qud)]**
Spec: kết quả run không cộng màu card mà GIAO — cặp trait từ 2 stage khác nhau khi cả hai đã reveal mở đúng MỘT graft slot: mượn 1 part của loài đã tuyệt chủng (bestiary có hồ sơ) vào genome qua crossover Gene Splicer. Hiệu ứng không nằm trong danh sách công bố → không có trên wiki, discovery là tài sản riêng; comboFired đảm bảo 1 lần; các cặp còn lại của catalog vô hình để còn thứ để tìm. Hình thể là giới hạn build — KHÔNG mở hệ graft/slot riêng, không limb-loss.
Ngân sách: nằm trong ngân sách combo 4–6; part giá DNA chuẩn (không giảm giá — không đụng DNA scarcity pricing); Monte Carlo 500 seed: Gini <0.4, win-rate lệch <1.5σ; assert % combo không thể fire = 0; probe chống stack (không ai đạt quá 1 slot vì chỉ có 1).

---

## III. Event variants theo stage

**Factory (Temperament Variants — Spore/EVO, keep×3):** mọi variant là bảng tham số trên `ChaosEventDef` đã parameter hóa (warn/apply/active) — event def là factory nhận world genome (pure theo seed). Warn floor ≥0.8× gốc (không rút ngắn dưới ngưỡng); karma >0.5 vẫn bảo pacifist; maxConcurrent scheduler đứng yên; shape warn→apply→end giữ nguyên. Cấm dựng pipeline variant thứ hai song song — mirror / resonance / bio-tell / scourge là CLASS của cùng factory.

| # | id | stage | spec | integration key | ngân sách + probe | nguồn |
|---|---|---|---|---|---|---|
| 1 | `algae_brittle` | cell | Cùng "Bùng nổ tảo" nhưng thế giới Brittle: bùng rồi tự sụp trong 20s, warn ngắn (≥0.8× gốc). | tham số `warn_s`, `active_s` trên def | mỗi variant fire ≥1 lần trong ≥15% run (không dead variant); exposure 2–4 variant/run | Spore/EVO |
| 2 | `algae_symbiotic` | cell | Thế giới Symbiotic: warn dài hơn; ai chủ động ăn tảo nhận trait miễn dịch (bias twist, karma gate giữ). | flag `immunity_trait` | ±40% DNA income so event gốc | Spore/EVO |
| 3 | `predator_convergence` | creature | **Punish the Hoard (RimWorld, keep×3):** severity khóa dominance — loài player chiếm >60% biomass vùng → nhiều loài săn mồi hội tụ, lớn hơn event chuẩn; chủ động xả biomass (thả prey ăn, đẩy bầy con di cư) → dịu. "Giữ nghèo" của RimWorld thành "giữ thưa". | `dominance_severity` trong weight() của threat event | Spearman(biomass-rank, severity) dương rõ ở early rồi taper; % người dưới median biomass >70% thời gian → hạ coupling | RimWorld |
| 4 | `nemesis_hunter` | creature | **[WOVEN: Glimmer Nemesis (Qud) × Defense Read-Back (RimWorld)]** Gene bị lạm dụng (spikes, speed…) qua ngưỡng dominance ≥60% trong ≥30 ticks → forceSpeciation sinh loài thợ săn CÓ TÊN, kit counter đúng gene đó ("spam spikes → săn mồi mọc mỏ xuyên giáp"). Hạ được trả DNA hiếm đúng 1 lần (one-kill-one-pay); phớt lờ thì nó sinh sản. Bestiary: "Toxic-resistant Strain — the world answered". | hook `forceSpeciation()` với genome phản gene trội; entropy defense-mix | hunter-vs-player win rate 40–55%; median ngưỡng→spawn ≥ warn window; time-to-counter 20–40 ticks; % đổi strategy trong 10 ticks sau counter ≥40% | Qud, RimWorld |
| 5 | `procedural_scourge` | creature | **[WOVEN: Procedural Scourge (DF) × Temperament Variants factory]** Chaos event "xâm nhập" sinh beast tên từ seed (names.ts), thân + syndrome ghép từ 2 trait đang bật (mưa axit × bùng nổ săn mồi → "Ubul Dịch Chua": trail chua hao HP + gọi scavenger). Cùng event id nhưng mỗi thế giới gặp một con khác. | composite tên + syndrome từ 2 trait; Bestiary mục "Dị bản" đóng dấu khi hạ | CHỈ cặp nằm trong combo catalog (liệt kê hết trong test, assert dodge-path tồn tại per cặp qua warn window — bài học steel+dust); damage ≤ budget %HP trừ khi counter hiện trên warn card; collision tên ≈0 trên 1000 seed | DF |
| 6 | `caravan_crossing` | creature | **[WOVEN: Caravan Set-piece (Rain World) × eco-event "Many Hooves"]** Vệt di cư lộ trước (xác, dấu mùi) rồi đoàn loài X băng ngang, kẻ rình bám sau cũng hiện; đoàn dừng, định cư. Hậu quả = pop-transfer trong cùng pool + species mới ghé (gene lạ). Bias thả gần camera. | eco-event hiện có; `pop_transfer` | >60% caravan visible trong bán kính camera; đo turnover pool sau caravan — >1 pool đổi dominant species → giảm herd size; cắt claim vùng-nguồn/vùng-đích (eco sim không có region) | Rain World |
| 7 | `resonance_path` | tribe | **[WOVEN: Resonance Path (FTL) × Council of Voices (KoDP)]** Warn card hiện option thứ 3 "blue" chỉ khi worldHas trait khớp; kèm 2–3 giọng whisper mâu thuẫn suy từ 2 trait đã reveal (apex-lineage nói cull, symbiotic-lineage nói shelter), accuracy = seeded noise, không label. Người chơi reverse-read tính cách thế giới qua cố vấn của nó. | warn-decision UI (mỘT layer mới dùng chung); template advice; `resonance_trait` gate | ≤20–35% events có blue path; pick-rate >90% → gắn cost; Gini accepted-advice <0.6; nếu không duyệt warn-decision UI → hạ cấp nhánh hiệu ứng ẩn trong factory | FTL, KoDP |
| 8 | `siege_hoard` | tribe | Cùng coupling hệ số với #3: đợt vây hãm severity khóa herd wealth/biomass percentile — herd giàu nhất gánh đợt to nhất đúng lúc giàu nhất. | `dominance_severity` (chia sẻ công thức #3) | như #3, đo riêng tribe stage | RimWorld |
| 9 | `red_tide_civ` | civ | Bùng độc tố quy mô civ — cùng số học combo `selection_sweep`, warn dài; histogram hue dịch đo được sau event; danh tính sweep gắn vào card. | chia sẻ trigger combo `selection_sweep` | như `selection_sweep`, đo ở civ | Creatures, FTL×KoDP |
| 10 | `mirror_rule` | all | **The edge is a door (Noita):** event đã từng sống sót 1 lần có thể chạy bản mirror — cùng event id, đảo ĐÚNG 1 quy tắc (châu chấu quay lại nhưng chỉ ăn predator; hạn hán quay lại nhưng nước độc thay vì cạn), chọn bởi temperament ẩn. Veteran gặp set-piece quen hành xử khác — bất ngờ mà không unfair-novelty. | chọn variant theo `world_temperament` | mọi mirror ±15% severity so base event (bot đo); log mirror-pick frequency — không inversion nào thống trị | Noita |
| 11 | `bio_tell` | all | **[WOVEN: Bio-tell (Rain World) × Temperament Variants]** Pacing overlay: WARN_WINDOW parameterize per-def (hiện hằng 2.5s trong chaos.ts) theo temperament bucket — thế giới hung có warn ngắn đợt mạnh, thế giới trầm warn dài rải mỏng. Trong warn window, quần thể ambient bỏ chạy khỏi vùng sắp bị đập theo trait của chúng (hook `onWarn` sẵn) — người chơi không thấy meter mới, thấy đàn bỏ chạy. | parameterize `WARN_WINDOW`; hook `onWarn` di chuyển quần thể | KHÔNG thêm meter; dodge-rate 40–60% theo bucket (bot rời vùng trước apply); <15% hoặc >85% → siết biên window bucket đó | Rain World |

Phủ stage: cell (1–2), creature (3–6), tribe (7–8), civ (9), all (10–11). Tổng 11 variant.

---

## IV. Mutation mechanics

Ràng buộc (rule 8 + bất biến Gene Splicer): chỉ mở rộng `MutationBias { rate_add, dietPull, coatPull }` hoặc thêm tham số cho crossover — không hệ gene mới. Crossover giữ nguyên là bất biến; mọi "surprise" là bảng hậu-xử-lý trên hook crossover, không phải lây nhiễm.

**M1 — `latent_allele`** — **[WOVEN: Recessive Echo (Creatures) × Sleeper Gene (DF) × Transposon (Noita)]**
MỘT bảng anomaly duy nhất trên hook crossover, kinds `{recessive_echo, dormant, transposed}`:
- *recessive_echo*: mỗi locus có thể mang 1 allele bị che (carrier hiển '?' nhỏ trên bestiary); hai carrier giao nhau → con bung phenotype tổ tiên, bestiary vẽ lại phả hệ và đóng dấu "hồi âm" nối con với cá thể tổ.
- *dormant*: allele ngủ dong — hue/size lệch nhẹ từ thế hệ 1 (anomaly đủ fair-play), thức sau N thế hệ hoặc khi chaos vượt ngưỡng (bias theo world trait); bestiary ghi "đã ngủ dong 12 thế hệ". KHÔNG lây qua crossover (cắt của bản DF — bất biến crossover; rewrite là hành vi của kind `transposed`, không phải lây nhiễm).
- *transposed*: crossover rewrite MỘT gene khác (genome không có slot có thứ tự — giả lập "nhảy sang láng giềng"); output chiếm slot gene thường nên gate math nguyên vẹn. Stamp "UNEXPECTED EXPRESSION" + bestiary ghi cá thể đầu tiên biểu hiện.
Integration: mở rộng MutationBias `allele_hidden` + tham số crossover `anomaly_kind`. Probe: expression 10–25% thế hệ N không có mặt ở 2 cha mẹ; 3–8 "hồi âm"/100 splice; dormant không thức trước thế hệ 3, ≥90% thức trước hết stage; % pool mang gene sau 10 lần lai ≤50%; DOA <15%; expression >+20% win delta hoặc >60% presence trong winning runs → nerf. Nguồn: Creatures, DF, Noita.

**M2 — `defect_genes`** — **[WOVEN: Defective Splices (Qud) × Liability Genes (RimWorld)]**
MỘT hệ defect duy nhất: crossover có xác suất sinh allele lỗi chạy nửa lực kèm defect nhìn thấy được (Glass Bones: nhanh hơn nhưng chết ở 30% HP) + 1–2 defect stress-triggered làm bộ đầu (frenzy đánh đồng loại khi crowd dày; đói gấp đôi, khi đói khẩn có thể ăn đồng loại). Bestiary stamp defect riêng + lần "nổi loạn" đầu thành entry có tên cá thể; purge line = lai tiếp nhiều thế hệ qua chính `mutate()` — trại lai gene thành bài toán di học quần thể. Frenzy cascade cap ≤30% pack mỗi lần trigger.
Integration: MutationBias `defect_rate`; condition check stress trong stage update. Probe: defect_rate 20–35% là TỔNG cả bảng (không cộng dồn hệ riêng); median purge ≤3 gen; pick-rate gene 10–30% run có ≥1; win-rate delta chọn-vs-không >10% → re-tune. Nguồn: Qud, RimWorld.

**M3 — `sacred_loci`** — Creatures (Sacred Loci)
Genome chia locus "thiêng" (~30% theo seed, miễn nhiễm `mutate()` / mutation-bias / `forceSpeciation` / chaos hook) và "nóng" — mỗi seed có khu cấm khác nhau: tính cách thế giới thể hiện qua cái nó KHÔNG cho đổi. Khi vùng thiêng đổi là địa chấn (expectation violation mạnh hơn random cùng độ lớn).
Integration: flag `holy_locus` per gene per seed (derived map rẻ); `mutate()` skip. Probe: Shannon entropy trait pool theo % thiêng (curve dốc về 0 khi thiêng >50%); DOA <10%. **Ghi chú QC:** lỗ hổng "bản sao qua crossover" (hai cá thể cùng mang locus thiêng → bản sao con KHÔNG thiêng) — critic1 cắt vì đụng bất biến Gene Splicer, critic2/3 giữ; chỉ giữ nếu QC vòng góp nhặt duyệt riêng, mặc định CẮT. Nguồn: Creatures.

---

## V. World-turns

Shape sẵn có (spec mục 3): `{ id, replaces, replacement, title, body, trigger }` — ghi đè 1 trait + card "Thế giới đã đổi". Catalog giữ 3 def; **run-cap 0–2 turn đã kích hoạt gồm cả `great_frost`** (mọi def cạnh nhau trong catalog, đủ điều kiện mới fire).

| id | trigger | spec | ngân sách + probe | nguồn |
|---|---|---|---|---|
| `great_frost` *(seed)* | chaosAbove 0.75 | hungry_bloom → calm_veil. Đã implement. | như đã test | seed catalog |
| `epoch_turn` | 4 nhánh trigger, cùng MỘT machinery replace-trait | **[WOVEN: Vestigial Rebirth (Spore/EVO) × Age Relabel (DF) × Desecrate the Sigil (Qud) × The Pain Audit (Creatures) × Irreversible Drift (FTL×KoDP)]** (a) *stageEnter gate*: qua gate, 1 trait cũ tắt, replacement "chỉ đến từ world-turn" sourced từ genetic memory — "Vây lưng → Cánh giả (lướt ngắn)", kèm dòng bestiary nhân chủng học ("năm triệu năm sau, vây của tổ tiên thành tai"); (b) *extinct ≥1 apex*: card "Kỷ nguyên <loài thống trị> bắt đầu" — tên ghép từ loài sống sót mạnh nhất, hiện cạnh sigil (names.ts); replace apex_dominance → trophic_release (growth+, predation−); hysteresis hold 10 ticks (bài học test storyteller); (c) *player sigil action*: trait đang bật có sigil vật lý trong arena — desecrate: windfall DNA một lần + replace trait vĩnh viễn; venerate: bonus nhỏ vĩnh viễn, trait giữ. Disposition allele ẩn (Pain Audit — "chúng chưa từng khoẻ") purge qua chính action desecrate; (d) *chaosAbove 0.6 + karma thấp*: sundance — force-extinct 1 loài nối-xích + trait overwrite (bỏ claim biome-map vì eco sim không có map). | tổng genome power sau turn ≥85% trước turn (assert test gate); econ-probe cửa sổ ±30': không pop âm, flora không kẹt 0, ≥2 loài sống; bot-arc ×3 qua gate đường UI thật; replacement trong ±40% DNA income hoặc khai báo rủi ro cao + counter-play; desecration rate mục tiêu 30–60% (ngoài băng = hết dilemma); windfall ≤15% DNA income stage; delta stage-completion ±5%; ≤2 turn/run | Spore/EVO, DF, Qud, Creatures, FTL×KoDP |
| `bio_shift` | extinct ≥1 (player-caused atom hạ cấp thành bias) | **Fungal Reality Shift (Noita, keep×3):** khi 1 loài tuyệt chủng, hệ re-equilibrate — 1 loại dinh dưỡng/vai trò chuyển thành loại khác cho phần còn lại của run (tất cả plankton → rust algae) + cặp thứ hai im lặng chọn bởi seeded rng. Karma ghi đây là hậu quả hệ; chaos meter untouched. Diet buffer 2 món gần nhất của player bias cặp chuyển (bóng của "ăn 2 chất liền"). Người chơi thấy food web re-equilibrate: blooms, starvations, migrations. | conversion là biến đổi loài/vai trò dinh dưỡng trong eco sim (species+diet đã có), KHÔNG material sim; re-check solvability sau mỗi shift (bài học gate civ −100-needed/90-available); exclude loài load-bearing khỏi pool shift; probe recovery-time band | Noita |

---

## VI. Story beats

Ngân sách run 1–2 beat; stage poll `storyteller.poll()`; one-shot flag kiểu `comboFired`; pacifist ending không bao giờ bị phá (mood gate karma >0.5).

**B1 — `gaia_redemption`** — **[WOVEN: Gaia's Redemption (Spore/EVO) × The Lone Wanderer (RimWorld)]** — họ beat cứu một-lần, hai tầng, mỗi run tối đa 1 lần/tầng:
- *Tầng cá thể*: lần đầu HP về 0 trong run — death fade giữ nguyên (bất biến death một chiều không phá), storyteller poll() thả beat 3–4s: thế giới "nuốt" sinh vật về nest, card verdict đặt tên tình huống, bestiary ghi "Gaia trả giá thay bạn". Tithe GHÉP với 12% DNA hiện có của `CellStage.handleDeath` (không thay bằng 25%/50%). Từ lần chết thứ hai chỉ còn tithe phẳng — set-piece đúng 1 lần, ưu tiên mood bless.
- *Tầng quần đàn*: pop <10% peak (còn ≥1 con) và không event đang chạy → Lone Wanderer di cư vào: cá thể mang gene hiếm rút từ bestiary thế giới (chưa từng sở hữu). Không announce kiểu gift — người chơi chỉ thấy một cá thể lạ tiến vào, bestiary chú thích một lần rồi im lặng. Relief là hope chứ không phải safety net.
Probe: rescue conversion 20–35% (dưới → dead content; trên → wipe-baiting — nếu % chọn risky tăng >20% sau lần đầu thấy rescue, wanderer mang theo disease/mối thù thay vì hạ tần suất); determinism 1000-seed assert flag không fire lần 2; đếm "chết có chủ ý" (<5s rời nest, không threat trong vùng) trước/sau; DNA-hoarding delta quanh cửa tử. Nguồn: Spore/EVO, RimWorld.

**B2 — `strange_mood`** — **[WOVEN: Strange Mood (DF) × Temperament Bands (Rain World)]** — 1 lần/run:
Một cá thể đột nhiên "mê" — bỏ bầy, bám theo một nguồn tài nguyên cụ thể (bias theo world trait); toast "⟡ Một cá thể đang dệt gì đó…". Chạm nguồn trong X giây → sinh đúng 1 cá thể đột biến mang tên riêng + 1 part hiếm KHÔNG mua được bằng DNA (duy nhất qua QC editor allowance — spec mục 5: 1 twist part hiếm, phải qua QC số học riêng). Bị chết/cạn nguồn trước đó → nó chết thật, bestiary "đã chết khi đang dệt" (một lần, vĩnh viễn). Sản phẩm mang tên sinh thủ tục — thế giới tác giả, không phải hệ phát thưởng.
Probe: tại thời điểm trigger, nguồn tồn tại trong bán kính R ≥90% (bot arc ×3 seed); thất bại ≤1/run; không kích khi karma >0.5 đang chờ pacifist ending (reuse gate mood twist); assert poll() chỉ phát beat 1 lần. Nguồn: DF, Rain World (primitive cá thể đánh dấu dùng chung với `temperament_bands`).

---

## VII. Keep-kill log (48 mechanic → quyết định)

Không có mục nào bị CẢ 3 critic kill. 4 mục drop dưới đây là drop vì ngân sách/tiền đề (verdict split 1 kill — 2 keep/weave), chi tiết từng verdict lưu trong log vòng phản biện.

| Mechanic (nguồn) | Tally (c1/c2/c3) | Quyết định |
|---|---|---|
| Body Debt (Spore/EVO) | kill/keep/keep | **DROP (reserve #1):** re-buy 30% là giảm giá trên DNA pricing + đụng editor đóng băng (c1); stamp "đã cắn bạn" đã nhập cụm grudge. Xem lại nếu QC mở part-state. |
| Gaia's Redemption | keep/keep/keep | → B1 |
| Vestigial Rebirth | weave/keep/keep | → `epoch_turn` (a) |
| Intersect Archetypes | keep/keep/keep | → `borrowed_flesh` |
| Sterile Heart | keep/weave/weave | → `prehistory_scar` (bỏ claim không gian) |
| Temperament Variants | keep/keep/keep | → factory, preamble mục III |
| Deep-Time Ledger | weave/keep/keep | → `prehistory_scar` |
| Corpse Tide | keep/keep/keep | → `corpse_tide` |
| Sleeper Gene | weave/weave/weave | → M1 `latent_allele` |
| Age Relabel | weave/keep/keep | → `epoch_turn` (b) |
| Procedural Scourge | weave/weave/weave | → variant #5 |
| Strange Mood | keep/weave/weave | → B2 |
| Storyteller Personality Split | weave/keep/keep | → `world_temperament` |
| Punish the Hoard | keep/keep/keep | → variant #3 + #8 |
| Liability Genes | keep/keep/weave | → M2 `defect_genes` |
| Defense Read-Back | weave/weave/keep | → variant #4 `nemesis_hunter` |
| The Lone Wanderer | weave/keep/weave | → B1 tầng quần đàn |
| Hereditary Grudge | keep/weave/weave | → `kin_memory` |
| Fungal Reality Shift | keep/keep/keep | → `bio_shift` |
| The Law | weave/weave/weave | → `kin_memory` (Mourning Swarm, valence âm) |
| Transposon | weave/weave/weave | → M1 kind `transposed` |
| Seeded alchemy triads | weave/weave/kill | **Woven vào `world_temperament`:** chỉ giữ lớp bẻ flavor; bảng recipe bỏ (metric 3–8h không bot đo được, "region" không tồn tại) |
| Material-signature chain | keep/kill/weave | **Woven vào `selection_sweep` + `corpse_tide`:** entry combo có trần, KHÔNG ma trận all-trait (n² untested + material sim không tồn tại) |
| The edge is a door | weave/weave/weave | → variant #10 `mirror_rule` |
| Defective Splices | weave/weave/keep | → M2 |
| Glimmer Nemesis | keep/keep/weave | → variant #4 (form chính: hunter có tên) |
| Anatomy Is the Inventory | weave/weave/weave | → `borrowed_flesh` (bỏ slot economy + limb-loss) |
| Water-Bound Memory Trade | weave/keep/keep | **DROP beat (reserve #2):** Envoy trùng DNA pricing; atom "gene bạn từ bỏ quay lại thành loài hoang" dệt vào forceSpeciation flavor |
| Retroactive Myth | keep/keep/keep | → lớp trình bày chung, preamble mục I |
| Desecrate the Sigil | keep/keep/keep | → `epoch_turn` (c) |
| Temperament Bands | keep/keep/keep | → trait `temperament_bands` |
| Sense×Camo matrix | keep/keep/keep | → trait `sense_defense_matrix` |
| Bio-tell | weave/keep/weave | → variant #11 |
| Grudge Ledger | weave/weave/keep | → `kin_memory` (form chuẩn) |
| Mimicry Splice | weave/keep/keep | → ô mimicry của `sense_defense_matrix` |
| Caravan | kill/weave/weave | → variant #6 `caravan_crossing` (re-scope pop-transfer, cắt region) |
| Recessive Echo | keep/weave/keep | → M1 (anchor) |
| Immortality Jackpot | kill/keep/kill | **DROP:** eco sim không có aging — phải đẻ hệ aging mới chỉ để phá; mutation budget 2–3 đã đầy |
| Sacred Loci | weave/keep/keep | → M3 (exploit bản-sao mặc định cắt, chờ QC riêng) |
| Pain Audit | weave/weave/keep | → `epoch_turn` (c) |
| Dark Generations | kill/keep/keep | **DROP (reserve #3):** thế giới tự sống đã là xương sống 5-stage (genetic memory + eco xuyên stage); beat slot hết |
| Beauty Is Not Fitness | weave/keep/keep | → `selection_sweep` |
| Resonance Path | keep/weave/weave | → variant #7 |
| Ledger Payback | weave/weave/keep | → `kin_memory` mặt karma-cao (beat cạnh tranh cùng cap 1–2, không lập ledger thứ hai) |
| Irreversible Drift | kill/weave/weave | → `epoch_turn` (d) sundance (cắt biome map) |
| Council of Voices | weave/weave/weave | → variant #7 (giọng = render trait/bias, không hệ council riêng) |
| Self-Harm Tactics | weave/keep/keep | → `selection_sweep` |
| Backcross Amnesia | kill/keep/keep | **DROP (reserve #4):** inviable offspring chưa tồn tại — phải đẻ cái-chết-khi-sinh chỉ để có thứ để cứu; 2 atom bị cụm khác phục vụ |

---

## VIII. Ngân sách tổng

| Nhóm | Ngân sách | Catalog | Đạt |
|---|---|---|---|
| Traits | 10–14 tổng (mới 2–6) | 8 seed + 5 mới = **13** | ✓ |
| Combos | 4–6 tổng (mới 2–4) | 2 seed + 3 mới = **5** | ✓ |
| Event variants | 8–12, phủ mọi stage | **11** (cell 2, creature 4, tribe 2, civ 1, all 2) | ✓ |
| Mutation mechanics | 2–3 | **3** (chỉ mở rộng MutationBias + tham số crossover) | ✓ |
| World-turns | run-cap 0–2 | 3 def catalog (1 seed + 2 mới), cạnh nhau cạnh tranh cap | ✓ |
| Story beats | 1–2 | **2** slot run (`gaia_redemption`, `strange_mood`) + 4 reserve ghi ở VII | ✓ |
| `[WOVEN]` | ≥3 entry | **15**: `prehistory_scar`, `world_temperament`, `kin_memory`, `selection_sweep`, `borrowed_flesh`, `nemesis_hunter`, `procedural_scourge`, `caravan_crossing`, `resonance_path`, `bio_tell`, `epoch_turn`, `bio_shift`(nguồn đơn). Lưu ý: `bio_shift` và `corpse_tide` là mechanic đơn-nguồn được giữ nguyên hình gốc có chủ đích (anchor hệ turn / combo), còn lại 15 mục đều là ghép ≥2 nguồn.

**Cross-cutting bắt buộc khi implement:**
1. Mọi reveal card áp chuẩn Retroactive Myth (preamble mục I) — một cơ chế đặt tên duy nhất, không hệ lore thứ hai.
2. MỘT trường `world_temperament` duy nhất điều mọi pacing/variant — cấm tính cách ẩn song song.
3. MỘT sổ thù duy nhất (`kin_memory`) — grudge/ledger/the-law/payback đều là mặt của nó.
4. Sacred-loci exploit: mặc định cắt, chỉ ship nếu QC vòng góp nhặt duyệt riêng.
5. Part hiếm "không mua bằng DNA" (B2) là duy nhất qua QC editor allowance — phải qua QC số học riêng trước khi wire-in.
6. Ngân sách lệch cân bằng: trait/combo vượt ±40% DNA income so baseline phải khai báo "rủi ro cao" + counter-play trong mô tả (hiện khai báo: `corpse_tide`).
7. Mỗi gate progression vẫn bot đi qua đường UI thật với 3 world seed cố định (`bot-arc` mở rộng) — replay value test thật.

Hết catalog. Nguồn sự thật khi implement: mọi key patch tập trung khai báo trong `src/evo/worldTraits.ts`, không string rải rác.

