# Native Sim Core Port — Implementation Plan (Milestone 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port toàn bộ sim layer của PRIMORDIA từ TypeScript sang GDScript (Godot 4.2.2) — 1:1 về logic, chứng minh parity bằng fixtures sinh từ bản TS — kèm scaffold repo + test runner headless zero-plugin.

**Architecture:** Sim layer = RefCounted classes thuần (không biết Node/scene), test được headless qua custom runner (`godot --headless -s tests/run.gd`, zero plugin). Parity pins: fixtures JSON sinh từ code TS (vitest chạy 1 lần ở repo TS, ghi sang repo native) — test native so kết quả với JSON. Repo: `~/Desktop/RD/primordia-native` (đã init, spec đã commit).

**Tech Stack:** Godot 4.2.2 stable (`~/.local/bin/godot`, renderer gl_compatibility), GDScript typed, zero plugin.

**Spec:** `docs/specs/2026-09-29-native-migration-design.md` (trong repo này) — plan argument từ spec; executors đọc cả hai.

## Global Constraints

- **Parity là luật:** logic port 1:1 từ file TS chỉ định (đọc file TS trước khi port); không "cải thiện" trong lúc port — mọi khác biệt phát hiện được ghi vào report, không sửa im lặng. Con số hằng giữ nguyên (26, 0.45, 12, 8%…).
- **Determinism:** cấm `randi()/randf()/randf_range()` global — mọi randomness qua `Rng` stream (port Mulberry32 bit-exact, verify bằng fixture). GDScript `int` là 64-bit: phép bitwise cần `& 0xFFFFFFFF` giữ hành vi uint32 (xem rng port ở Task 3).
- **GDScript typed:** static typing mọi where có thể (`var x: float`), `class_name` cho class dùng chéo, snake_case file, `##` doc comment.
- **Test convention:** mỗi task TDD — test file `tests/test_<module>.gd` extends `tests/test_base.gd`; chạy `godot --headless -s tests/run.gd` từ repo root; runner phải exit 0 khi xanh / 1 khi đỏ; test không được `push_error`/script-error (crash runner = fail).
- **TS source of truth:** `~/Desktop/RD/Spore/src/**` (READ-ONLY — repo TS frozen; không sửa file nào ở đó, kể cả fixtures generator chạy tools/).
- **Commit style:** conventional commits + `Co-Authored-By: Claude Code <noreply@anthropic.com>`; làm việc trực tiếp trên `main` của repo mới (repo riêng, chưa có GitHub remote — CI sau).

**User decisions (already made):**
- "Godot 4 + GDScript" engine; "làm trong repo riêng rồi sẽ xóa repo cũ, ghi đè lên"; TS "Freeze làm reference"; "Cell stage full parity" là slice đầu (plan sau — plan này chỉ sim core).
- Lộ trình production: "Native ngay" — chấp nhận phase đi ống nước trước khi có feature mới.

---

### Task 1: Scaffold + Test Runner

**Goal:** Repo Godot tối thiểu + custom test runner headless zero-plugin, chạy được test xanh/đỏ với exit code đúng.

**Files:**
- Create: `project.godot`, `.gitignore`, `tests/run.gd`, `tests/test_base.gd`, `tests/test_smoke.gd`

**Acceptance Criteria:**
- [ ] `cd ~/Desktop/RD/primordia-native && godot --headless -s tests/run.gd` → in summary `1 file, 1 test, 2 checks, 0 failures`, exit 0.
- [ ] Sửa tạm 1 assertion thành sai → chạy lại → FAIL được in rõ, exit 1 (chứng minh runner bắt được đỏ).
- [ ] `godot --headless -s tests/run.gd` không in script error/warning nào lên output.

**Verify:** lệnh trên → exit 0; phiên bản đỏ → exit 1.

**Steps:**

- [ ] **Step 1: Tạo project + runner.** `project.godot`:

```ini
; Engine configuration file.
config_version=5

[application]

config/name="PRIMORDIA"
config/features=PackedStringArray("4.2")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

`.gitignore`: `.godot/`, `*.tmp`.

`tests/run.gd`:

```gdscript
## Zero-plugin test runner. Usage: godot --headless -s tests/run.gd
## Discovers res://tests/test_*.gd, runs every method named test_*, exits 1 on failure.
extends SceneTree

func _initialize() -> void:
	var total_checks := 0
	var total_failures := 0
	var files := _discover()
	for path in files:
		var script: GDScript = load(path)
		var instance: RefCounted = script.new()
		var methods: PackedStringArray = []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_") and not methods.has(String(m.name)):
				methods.append(String(m.name))
		methods.sort()
		for method in methods:
			# fresh instance per test = state isolation
			var t: RefCounted = script.new()
			t.call(method)
			var f: int = t.failures.size()
			total_checks += t.checks
			total_failures += f
			var status := "ok" if f == 0 else "FAIL"
			print("%s %s.%s (%d checks, %d failures)" % [status, path.get_file(), method, t.checks, f])
			if f > 0:
				for msg in t.failures:
					print("    ✗ " + msg)
	print("---")
	print("%d files, %d tests, %d checks, %d failures" % [files.size(), _count_tests(files), total_checks, total_failures])
	quit(1 if total_failures > 0 else 0)

func _discover() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append("res://tests/" + f)
	out.sort()
	return out

func _count_tests(files: PackedStringArray) -> int:
	var n := 0
	for path in files:
		var script: GDScript = load(path)
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_"):
				n += 1
	return n
```

`tests/test_base.gd`:

```gdscript
## Base for test files: assertion helpers record failures instead of throwing
## (GDScript has no try/catch — a script error would kill the whole run).
class_name TestBase
extends RefCounted

var checks := 0
var failures: PackedStringArray = []

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)

func eq(a: Variant, b: Variant, msg: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])

func approx(a: float, b: float, msg: String, eps := 1e-9) -> void:
	ok(absf(a - b) <= eps, "%s (got %f, want %f)" % [msg, a, b])
```

`tests/test_smoke.gd`:

```gdscript
extends TestBase

func test_runner_works() -> void:
	ok(true, "runner executes test methods")
	eq(1 + 1, 2, "eq helper")
	approx(0.1 + 0.2, 0.3, "approx helper", 1e-9)
```

- [ ] **Step 2: Chạy xanh** `godot --headless -s tests/run.gd` → exit 0.
- [ ] **Step 3: Chạy đỏ (tự-kiểm runner):** thêm tạm `eq(1, 2, "deliberate")` vào test_smoke → chạy → thấy `FAIL` + `✗ deliberate` + exit 1. **Xóa assertion tạm** sau khi xác nhận.
- [ ] **Step 4: Commit** `chore: godot scaffold + zero-plugin test runner`.

---

### Task 2: Parity Fixtures từ bản TS

**Goal:** Sinh fixtures JSON từ code TS (nguồn sự thật) vào `tests/fixtures/` của repo native — mọi port test sau này so kết quả với chúng.

**Files:**
- Create (TS repo, tool): `~/Desktop/RD/Spore/tools/fixture-gen.test.ts`
- Create (native repo): `tests/fixtures/rng_stream.json`, `genome_stats.json`, `eco_tick.json`, `mutate_crossover.json`, `world_genome.json`, `storyteller_walk.json`, `fixtures.README.md`

**Acceptance Criteria:**
- [ ] 6 file JSON tồn tại trong `tests/fixtures/`, parse được, có key đúng schema mỗi loại (mô tả trong fixtures.README.md).
- [ ] `rng_stream.json` chứa: seeds `1`, `42`, `3735928559` — mỗi seed: 50 giá trị `next()`, 20 giá trị `int(2,8)`, 20 kết quả `chance(0.3)`, 10 kết quả `weighted([[1,"a"],[3,"b"],[0.5,"c"]])`, 10 giá trị `gauss()`, 3 seed con từ `branch()`.
- [ ] `genome_stats.json`: `computeCellStats` + `computeCreatureStats` cho 8 genome mẫu (default, min-everything, max-everything, legless size 2.2, plates coat, glow pattern, mỗi diet) — key là genomeHash.
- [ ] `eco_tick.json`: 1 sim 10 phút (dt 1s, roster 6 loài seed cố định qua Rng(7), mods rỗng) snapshot mỗi 60s: flora, mỗi loài pop/extinct, totalEaten.
- [ ] `mutate_crossover.json`: 20 mutate(defaultGenome, Rng(i)) + 10 crossover pairs + 5 crossover với bias `{rate_add: 0.15, dietPull: "carnivore"}`.
- [ ] `world_genome.json`: derive cho 20 seed (0..19) — traitIds + temperament + turnIds; tickWorldReveals walk script hóa cho seed 0.
- [ ] `storyteller_walk.json`: mood timeline cho script tín hiệu 120 tick (định nghĩa trong generator, ghi rõ pattern vào README).
- [ ] Generator là vitest file chạy bằng `npx vitest run tools/fixture-gen.test.ts` ở TS repo, GHI file thẳng vào `~/Desktop/RD/primordia-native/tests/fixtures/`. Không sửa bất kỳ file game TS nào.

**Verify:** `ls ~/Desktop/RD/primordia-native/tests/fixtures/*.json | wc -l` → 6; mỗi file parse JSON được.

**Steps:**

- [ ] **Step 1: Viết generator** ở TS repo (viết cả 6 loại fixture trong 1 file; import từ `../src/evo/*`, `../src/core/rng`).
- [ ] **Step 2: Chạy** `cd ~/Desktop/RD/Spore && npx vitest run tools/fixture-gen.test.ts` → kiểm tra 6 JSON xuất hiện đúng chỗ.
- [ ] **Step 3: Viết `fixtures.README.md`** — schema từng file + cách regenerate.
- [ ] **Step 4: Commit native repo** `test: parity fixtures generated from TS source` (TS repo: không commit gì — tools/ để nguyên, không thuộc frozen scope).

---

### Task 3: `core/rng.gd` — Mulberry32 bit-exact

**Goal:** Port Rng (Mulberry32) bit-exact — nền determinism của toàn bộ game.

**Files:**
- Create: `src/core/rng.gd`
- Test: `tests/test_rng.gd` (so fixture `rng_stream.json`)

**Acceptance Criteria:**
- [ ] Với 3 seed trong fixture: 50 `next()` khớp float EXACT (so từng giá trị, eps 0 vì cùng float64 — nếu lệch → port sai, không được nới eps).
- [ ] `int(2,8)`, `chance(0.3)`, `weighted`, `gauss`, `branch` khớp fixture.
- [ ] API đầy đủ như TS: `next/range/int/chance/pick/weighted/shuffled/gauss/gauss_clamp/branch/state/set_state`; `pick` trên mảng rảng throw (push_error + trả về null theo GDScript idiom — test assert null).
- [ ] Trạng thái nội bộ uint32: `_s` luôn `& 0xFFFFFFFF` sau mọi op.

**Verify:** `godot --headless -s tests/run.gd` → test_rng green.

**Steps:**

- [ ] **Step 1: Test trước** — `tests/test_rng.gd` load fixture, so từng giá trị:

```gdscript
extends TestBase

const Fixtures := preload("res://tests/fixtures.gd")

func test_next_matches_ts() -> void:
	var data := Fixtures.load_json("rng_stream.json")
	for seed_str in data.seeds.keys():
		var r := Rng.new_from(int(seed_str))
		for expected: float in data.seeds[seed_str].next:
			approx(r.next(), expected, "seed %s next" % seed_str, 0.0)
# ... tương tự int_2_8 (eq), chance_0p3 (eq bool), weighted (eq), gauss (approx 0.0), branch (eq seed)
```

`tests/fixtures.gd`:

```gdscript
class_name Fixtures

static func load_json(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/%s.json" % name, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary
```

- [ ] **Step 2: FAIL** (class Rng chưa có).
- [ ] **Step 3: Port `src/core/rng.gd`** — điểm bit-exact:

```gdscript
class_name Rng

var _s: int = 0

func _init(seed: int = 1) -> void:
	_s = seed & 0xFFFFFFFF
	if _s == 0:
		_s = 0x9e3779b9

static func new_from(seed: int) -> Rng:
	return Rng.new(seed)

func next() -> float:
	_s = (_s + 0x6d2b79f5) & 0xFFFFFFFF
	var t: int = _s
	t = _imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

# Math.imul: 32-bit multiply, giữ đúng 32 bit thấp (toán tử bitwise JS hoạt động
# trên bit-pattern nên giữ giá trị uint32-masked là bit-exact với TS).
static func _imul(a: int, b: int) -> int:
	return (a * b) & 0xFFFFFFFF
```

  Các hàm còn lại port thẳng theo `~/Desktop/RD/Spore/src/core/rng.ts` (range/int/chance/pick/weighted/shuffled/gauss/gauss_clamp/branch/state/set_state — `Math.floor` → `floori`, `arr.slice()` → `arr.duplicate()`, throw empty-pick → `push_error` + `return null`).
- [ ] **Step 4: PASS với eps 0.0** — nếu lệch dù 1 ulp: port sai, tìm chỗ thiếu mask.
- [ ] **Step 5: Commit** `feat: rng mulberry32 bit-exact port`.

---

### Task 4: `evo/genome.gd`

**Goal:** Port genome (source of truth của hình thể) — dict + bounds + clamp + hash.

**Files:**
- Create: `src/evo/genome.gd`
- Test: `tests/test_genome.gd`

**Acceptance Criteria:**
- [ ] `Genome` là Dictionary với đúng 22 key như TS (size, diet, hue, sat, pattern, 8 cell genes, legs/arms/eyes/horns/tail/wings/brain/coat, generation); `default_genome()` trả về đúng default TS (size 1, diet omnivore, hue 120, sat 0.55, flagella 2, jaw 1, eyes 1, generation 1...).
- [ ] `GENE_BOUNDS` đúng 15 entry; `clamp_genome`: garbage (NaN→dùng `is_finite`, string, null) snap về default đúng quy tắc TS (size→1, eyes→1, còn lại→0; hue→120; sat→0.55; diet/pattern/coat sai enum → default), hue wrap `% 360` với giá trị âm (GDScript `%` giữ dấu âm của dividend — dùng `@posmod` hoặc `(v % 360 + 360) % 360` — TEST case hue -30 → 330).
- [ ] `genome_hash` khớp chuỗi TS (dùng fixture genome_stats.json keys — hash của 8 genome mẫu phải khớp key trong fixture).
- [ ] `clone_genome` deep-enough (Dictionary duplicate()).

**Verify:** `godot --headless -s tests/run.gd` → test_genome green.

**Steps:**

- [ ] **Step 1: Test trước** — default_genome 22 key đúng giá trị; clamp các case garbage (dict với size: "abc", hue: NAN qua `NAN` literal, diet: "xyz", hue: -30 → 330); genome_hash khớp fixture keys.
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port** từ `~/Desktop/RD/Spore/src/evo/genome.ts` (toàn bộ file 119 dòng — đọc nó trước; genome là Dictionary, `class_name Genome` chứa static funcs: `default_genome() -> Dictionary`, `gene_bounds() -> Dictionary`, `clamp_genome(g: Dictionary) -> Dictionary`, `clone_genome`, `genome_hash`). GDScript không có enum literal — diet/pattern/coat giữ String, validate bằng mảng hằng.
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: genome port`.

---

### Task 5: `evo/parts.gd` + `evo/stats.gd`

**Goal:** Port parts catalog (shopping/identity) + derived stats (pure math).

**Files:**
- Create: `src/evo/parts.gd`, `src/evo/stats.gd`
- Test: `tests/test_parts.gd`, `tests/test_stats.gd`

**Acceptance Criteria:**
- [ ] `PARTS` đúng 15 part, mỗi phần đủ 8 field; `part_cost` = `round(baseCost * pow(costMult, currentLevel))`; `part_refund` có starter-baseline rule (DEFAULTS flagella 2, jaw 1, eyes 1; dưới baseline → 0; trên → `round(partCost(levelAfter) * 0.5)`).
- [ ] `standout_part` trả về part number-level cao nhất ≥2 (bool/categorical skip); `graft_value(cur, level, max) = max(cur, min(level, max))`.
- [ ] `compute_cell_stats` + `compute_creature_stats` + `would_win` khớp fixture `genome_stats.json` CHO ĐÚNG 8 GENOME (so từng field, eps 0 — cùng float64 công thức).
- [ ] Legless exemption: speed = `max(8, 24 + wings + coatSpeed)` khi legs 0 (không trừ size penalty) — test riêng case size 2.2 legless (fixture có genome này).

**Verify:** `godot --headless -s tests/run.gd` → test_parts + test_stats green.

**Steps:**

- [ ] **Step 1: Test trước** — fixture-driven: mỗi genome key trong `genome_stats.json` → `compute_stats(Genome port từ fixture genome, land)` so từng field stats; part_cost/refund table test tay (partCost(flagella, 0)=15, round(15*1.35)=20 at level 1...; refund flagella level 2→1: level_after=1 < dflt 2 → 0; refund jaw 1→0 → 0; refund legs 3→2: partCost(legs,2)=round(65*1.25^2)=102 → refund 51).
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port** từ `~/Desktop/RD/Spore/src/evo/parts.ts` (95 dòng) + `stats.ts` (74 dòng). GDScript: PARTS là Array[Dictionary]; `partById` → `part_by_id`; `Math.pow` → `pow`; `Math.round` → `roundi` (chú ý: JS Math.round(.5) rounds UP (toward +∞), Godot `roundi` cũng round half away from zero — same cho giá trị dương, OK; fixture sẽ pin).
- [ ] **Step 4: PASS** — lệch field nào → so công thức TS dòng đó.
- [ ] **Step 5: Commit** `feat: parts catalog + stats port`.

---

### Task 6: `evo/names.gd`

**Goal:** Port procedural naming (species name + epithet).

**Files:**
- Create: `src/evo/names.gd`
- Test: `tests/test_names.gd` (fixture mới sinh thêm nếu generator Task 2 chưa có — nếu chưa, sinh inline: ghi 10 output đầu của `species_name(Rng(9))` vào test như literal so sánh, lấy từ TS bằng cách chạy hàm đó trong generator)

**Acceptance Criteria:**
- [ ] `species_name(rng)` + `epithet(genome, rng)` port 1:1 từ `~/Desktop/RD/Spore/src/evo/names.ts` (60 dòng) — same syllable pools, same rng order.
- [ ] Determinism: 10 giá trị đầu cho seed cố định khớp TS (fixture hoặc literal pin).

**Verify:** `godot --headless -s tests/run.gd` → test_names green.

**Steps:**

- [ ] **Step 1: Sinh pin values** (nếu generator Task 2 chưa có names: chạy 1 script vitest nhỏ in 10 values; dán vào test làm literal —ghi rõ nguồn).
- [ ] **Step 2: Test trước** (literal pins).
- [ ] **Step 3: FAIL → Port → PASS.**
- [ ] **Step 4: Commit** `feat: procedural names port`.

---

### Task 7: `evo/mutation.gd` — kèm anomaly M1 + defect M2

**Goal:** Port mutate/crossover + MutationBias + bảng anomaly (latent_allele) + defect genes — đúng nguyên trạng sau tất cả các đợt review của bản TS.

**Files:**
- Create: `src/evo/mutation.gd`
- Test: `tests/test_mutation.gd`

**Acceptance Criteria:**
- [ ] `mutate(genome, rng, rate, bias)` port từ `~/Desktop/RD/Spore/src/evo/mutation.ts` hiện hành (đọc file — nó đã gồm rate_add/dietPull/coatPull + clamp 1.2 + INT_GENES list). 20 case fixture `mutate_crossover.json` khớp EXACT.
- [ ] `crossover(a, b, rng, opts)` port với `CrossoverOpts {mutate_rate, bias}`; 10 case fixture khớp; blend-hue 25% case có trong fixture.
- [ ] **M1 anomaly** (bảng post-hook sau clamp — đọc phần anomaly trong mutation.ts hiện hành): kinds recessive_echo/dormant/transposed, weights 45/35/20; dormant có `pendingAllele` wakeGen +2..+4; transposed ghi slot gene thường. Test hành vi: (a) anomaly stamp xuất hiện đúng kind-weights phân bố trên 200 rolls (kiểu statistical, chùng 20%); (b) transposed output luôn nằm trong GENE_BOUNDS; (c) recessive_echo carrier marker '?' (hoặc field `hidden_allele`) tồn tại trên genome dict.
- [ ] **M2 defect**: defectRate tổng (0.2 base / 0.3 wild) — test 600 splices incidence ≤ 0.35; frenzy/famine/glass_bones stamps tồn tại trong DEFECT_NAMES.
- [ ] Bias wiring: `bias.rate_add` thật sự tăng số gene đổi (test 0 → ít hơn 0.9 statistically).

**Verify:** `godot --headless -s tests/run.gd` → test_mutation green.

**Steps:**

- [ ] **Step 1: Test trước** (fixture + behavioral).
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port** — `~/Desktop/RD/Spore/src/evo/mutation.ts` là nguồn; đọc toàn bộ (file ~157 dòng sau các đợt fix). Chú ý: TS dùng string union kinds — GDScript String constants; anomaly table là const Array[Dictionary].
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: mutation + anomaly/defect port`.

---

### Task 8: `evo/ecosystem.gd` — core tick

**Goal:** Port eco sim phần lõi: flora logistic, herb drain, carrying caps, growth, background speciation, notifyKill pricing, EcoMods — nhận mods là Dictionary thuần (không biết world).

**Files:**
- Create: `src/evo/ecosystem.gd`
- Test: `tests/test_eco_core.gd`

**Acceptance Criteria:**
- [ ] Class `Ecosystem` (RefCounted): `species: Array[Dictionary]` (EcoSpecies: id/name/genome/pop/discovered/extinct/kills_by_player/kin + ledger fields), `flora: float`, `flora_cap: float = 100`, `total_eaten`.
- [ ] `add_species(genome, pop, opts)` — name từ Names, id `sp{n}_{rng-suffix}`; `tick(dt, player_species_id)` đúng 5 khối của TS: flora growth (0.8 logistic), herb drain (0.012*herb_drain_mult*m*10), **floor `max(12, ...)` sau drain**, per-species cap formulas (herbivore F*2.2, omnivore F*1.1+B*0.15*predation_mult, carnivore max(1, B*0.18*predation_mult) — chia size max(0.4)), growth `0.5*gm*pop*(1-pop/max(1,cap))`, decay 0.02, extinction pop<0.4, background speciation chance 0.004*speciation_mult*m cap 12 loài.
- [ ] `notify_kill(id, player_strength)` — meal = size*(1+spikes*0.1+jaw*0.1); scarcity sc (pop<6→0.6, >25→1.2) * meal_dna_mult; pop-1, killsByPlayer+1.
- [ ] **Bit-parity vs fixture `eco_tick.json`**: snapshot mỗi 60s khớp EXACT (eps 0 cho pop/flora — cùng công thức float64; nếu lệch → tìm thứ tự op).
- [ ] **Empty-mods = baseline**: `eco.mods = {}` và không set mods cho cùng kết quả bit-exact.
- [ ] Single-mod probes: herb_drain_mult 1.6 / growth_mult 1.25 / speciation_mult 1.5 / predation_mult 1.3 — mỗi cái 60-min sim: pop ≥ 0, flora ≥ 12, ≥2 loài sống (mirror TS econ-probe).

**Verify:** `godot --headless -s tests/run.gd` → test_eco_core green.

**Steps:**

- [ ] **Step 1: Test trước** (fixture-driven + probes — pattern giống TS `tests/econ-probe.test.ts`, đọc nó).
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port phần lõi** từ `~/Desktop/RD/Spore/src/evo/ecosystem.ts` (đọc file ~263 dòng hiện hành; port có chủ đích TRỪ các phần valve/bio_shift/corpse tide — đó là Task 9; để chỗ trống có comment `# Task 9: valves`). EcoMods là Dictionary với key snake_case như TS; mods là FIELD `mods: Dictionary = {}` set từ ngoài.
- [ ] **Step 4: PASS** — fixture là trọng tài tuyệt đối.
- [ ] **Step 5: Commit** `feat: ecosystem core tick port`.

---

### Task 9: `evo/ecosystem.gd` — valves & systems

**Goal:** Port phần eco nâng cao: grudge/harass valve, bio_shift reequilibrate + solvability, corpse tide, force_speciation, serialization.

**Files:**
- Modify: `src/evo/ecosystem.gd` (fill các chỗ trống Task 8)
- Test: `tests/test_eco_valves.gd`

**Acceptance Criteria:**
- [ ] **Grudge/harass** (port từ TS ecosystem.ts hiện hành): `grudge`/`grudge_t`/`harass`/`harass_t` trên EcoSpecies; decay `grudge = floor(grudge/2)` mỗi `GRUDGE_HALFLIFE_GEN(40) * GRUDGE_GEN_SECONDS(30)` giây — hằng số 40/30, int-clamp, xóa về 0; harassment cap 4/100 eco-min qua `effective_grudge(sp)` (capped → 0); cả hai chạy TRONG tick bằng số học dt/m thuần, KHÔNG consume rng.
- [ ] **bio_shift reequilibrate**: extinction push (loài !tideBorn) → `reequilibrate(out.extinctions)`: role-pair conversion theo seeded target + silent pair, dedupe shifts, **top-up `while living < 2` chạy TRƯỚC early-return khi added rỗng** (bài học I1), kin excluded, solvability giữ ≥2 loài sống.
- [ ] **Corpse tide**: `drop_corpse` ledger cap 8 → scavenger spawn 2-3 burst clamp 8% popSum; starvation ramp; auto-end ≤5.0 game-min khi kills dừng; **`tideBorn` excluded khỏi out.extinctions** (không ceremony); revive qua drop_corpse.
- [ ] **Serialization**: `to_json/from_json` — species fields incluyendo grudge/harass/tideBorn/pending_allele/defect; corrupt fields coerce (`num_or_undef` pattern → 0), genome clamp.
- [ ] Probes mirror TS econ-probe (đọc file): decay 8→4→0; cap 4 vs uncapped presses; P(ext|grudge) ≤2×; tide auto-end ≤5.0; double-dedupe → living ≥2.

**Verify:** `godot --headless -s tests/run.gd` → test_eco_valves green.

**Steps:**

- [ ] **Step 1: Test trước** — mirror từng case TS (đọc `tests/econ-probe.test.ts` phần valves — mọi case đã có số cụ thể).
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port** các phần còn lại của ecosystem.ts — GIỮ NGUYÊN hằng số và thứ tự op; seed cho bio_shift target = rng stream của eco (branch nếu cần — không đụng stream chính).
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: eco valves + bio_shift + corpse tide port`.

---

### Task 10: `evo/world_genome.gd` + catalog

**Goal:** Port world genome: derive (13 traits + temperament + 0-2 turns), accessors, tick_world_reveals (reveal/combo/turn + top-up ≥3), combo eco-side effects.

**Files:**
- Create: `src/evo/world_genome.gd`, `src/evo/world_traits.gd` (catalog data)
- Test: `tests/test_world_genome.gd`

**Acceptance Criteria:**
- [ ] Catalog port từ `~/Desktop/RD/Spore/src/evo/worldTraits.ts` hiện hành: 13 traits (8 seed + world_temperament/temperament_bands/kin_memory/prehistory... đọc file — đúng những gì đang có, gồm ecoSeed corners và turn-only defs false_wing/trophic_release), COMBO_DEFS 5, WORLD_TURN_DEFS 3, WORLD_ADJ/NOUN 10+10; PatchKey union → mảng hằng `PATCH_KEYS`.
- [ ] `derive_world_genome(seed)`: rng `seed ^ 0x57ef` (trong GDScript: `(seed ^ 0x57ef) & 0xFFFFFFFF`), 4-6 traits, symmetric exclusion (cả hai chiều lúc rút), temperament khi có world_temperament, turns 0-2 từ pool cạnh tranh (đọc TS derive hiện hành — nó đã gồm top-up ≥3); 1000-seed determinism test (cùng seed cùng trait set, không crash/NaN).
- [ ] `world_num/world_has/archetype_weights/eco_mods_from_world` — first-wins semantics cho num (giữ nguyên TS `numFrom`).
- [ ] `tick_world_reveals(w, signals)`: reveal từng trait đúng điều kiện 1 lần; combo khi cả hai legs revealed + trigger 1 lần; world-turn: replace + exclusion tại swap + **replacement pushed vào out.revealed** (extra bug đã fix ở TS); `w.timers` KHÔNG tăng trong hàm (Game sở hữu — signals.timer vào).
- [ ] Combo eco-side: rot_circle (extinction → flora +20 clamp cap + grazer, living<12 gate) và selection_sweep (cap ×0.78 ornamented while live) tồn tại trong eco_mods_from_world/eco integration ĐÚNG shape TS (đọc TS worldGenome.ts hiện hành — comboActive flow).
- [ ] Fixture `world_genome.json` khớp cho 20 seed; walk test reveal/combo/turn khớp.

**Verify:** `godot --headless -s tests/run.gd` → test_world_genome green.

**Steps:**

- [ ] **Step 1: Test trước** (fixture + determinism 1000 seed + behavioral walk).
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port** từ `~/Desktop/RD/Spore/src/evo/worldGenome.ts` + `worldTraits.ts` (đọc cả hai toàn bộ — ~206 + ~134 dòng).
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: world genome + catalog port`.

---

### Task 11: `game/storyteller.gd`

**Goal:** Port mood engine — nhỏ, fixture-driven.

**Files:**
- Create: `src/game/storyteller.gd`
- Test: `tests/test_storyteller.gd`

**Acceptance Criteria:**
- [ ] `Storyteller` (RefCounted): mood bless/test/twist; branch order bless → pacifist gate (karma ≥0.5 → test, TRƯỚC twist) → twist (chaos>0.55 or dnaRate>25, karma<0.5) → test; hysteresis hold 20s (clamp 0, re-arm chỉ khi flip); `gap_bias()` 1.2/1.0/0.78; `warn_scale()` bucket theo temperament (đọc TS storyteller.ts hiện hành — gồm warnScale cradle 1.6/lean 1.0/wildcard 0.8); `offer_beat` dedupe Set + `poll()` FIFO; `reset()` wipe mood/hold/beats/seen.
- [ ] Fixture `storyteller_walk.json` mood timeline khớp từng tick.
- [ ] 5 case TS verbatim: pacifist 200 tick không twist; bless struggling; twist aggressor sau hysteresis; hold 10 tick; FIFO dedupe.

**Verify:** `godot --headless -s tests/run.gd` → test_storyteller green.

**Steps:**

- [ ] **Step 1: Test trước** (fixture walk + 5 case port từ TS `tests/world.test.ts` block Storyteller — đọc nó).
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port** từ `~/Desktop/RD/Spore/src/game/storyteller.ts` (~133 dòng hiện hành).
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: storyteller port`.

---

### Task 12: `game/chaos.gd` — scheduler

**Goal:** Port ChaosScheduler + ChaosEventDef structure (weights/apply là Callables; applications cụ thể là stage-layer — không port ở đây).

**Files:**
- Create: `src/game/chaos.gd`
- Test: `tests/test_chaos.gd`

**Acceptance Criteria:**
- [ ] `ChaosEventDef` Dictionary shape: id/name/warn(optional String)/warn_s(optional float)/weight(Callable)/duration Vector2i-like [lo,hi]/cooldown/apply(Callable)/tick(Callable, optional)/end(Callable, optional)/mood_affinity(optional).
- [ ] `ChaosScheduler` (RefCounted): `update(dt, stage, ctx, hooks)` đúng TS flow — warn phase 2.5s * `ctx.warn_scale` (warn_s override clamp `max(WARN_WINDOW*0.8, warn_s)`), hold 1s retry khi max_active đầy, cooldown map decay, effective_gap = `gap * ctx.gap_mult * (1 - GAP_CHAOS_SCALE(0.45) * chaos)`, weighted pool (active/cooldown excluded, `max(0.01, weight(ctx))`), BASE_GAP 26, `trigger()` (không forward hooks — giữ TS behavior), `clear()`, `is_active`, `active_events`, `warn_remaining` getter (đã có ở TS sau bio_tell).
- [ ] Tests với scripted defs (fake stage = RefCounted, apply ghi log): warn→apply sequence, duration rng từ scheduler's rng, max_active hold, cooldown gate, weighted selection determinism (rng seeded), gap chaos scaling.

**Verify:** `godot --headless -s tests/run.gd` → test_chaos green.

**Steps:**

- [ ] **Step 1: Test trước** — đọc TS `tests/core.test.ts` phần chaos (có sẵn các case scheduler) + viết thêm cho warn_s/mood path.
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port** từ `~/Desktop/RD/Spore/src/game/chaos.ts` (~69 dòng hiện hành + warnS + warnRemaining). Callables: `def.weight.call(ctx)`.
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: chaos scheduler port`.

---

### Task 13: `game/context.gd` + save

**Goal:** Port GameContext + save/load JSON (v1 fresh native — không migrate save TS).

**Files:**
- Create: `src/game/context.gd`
- Test: `tests/test_context.gd`

**Acceptance Criteria:**
- [ ] `GameContext` (RefCounted): seed/rng (Rng từ seed)/genome/dna(40)/karma/chaos(0.15)/difficulty/slot/playtime/total_dna_earned/player_name/stage/bestiary (Array)/eco/flags/world (derive)/world_stats; `add_dna` (fractional accumulate + EV-free — signal qua Callable callbacks list hoặc đơn giản return info; port shape TS nhưng bus là Godot Signal trên class — dùng `signal dna_gained(amount, reason)`), `spend_dna`, `add_chaos/add_karma` clamp, `chaos_gap_mult`, `starting_chaos`, `discover` (bestiary dedupe qua genome_hash, toast qua signal), `mark_extinct`.
- [ ] `save(slot)` → `user://saves/slot{n}.json`: refuse stage 'menu'; blob = mọi field + world blob (trait_ids/turn_ids/revealed/combo_fired/fired_turns/world_stats/temperament — shape như TS v2).
- [ ] `load(slot)`: shape-validate từng field; corrupt → re-derive từ seed (world) + defaults; unknown traitIds drop; **không migrate save TS** (fresh v1 native).
- [ ] Tests: round-trip save→load (revealed/combo/fired_turns/world_stats sống); corrupt file (junk JSON) → load false + không crash; traitIds lạ → drop; save ở stage menu → false.

**Verify:** `godot --headless -s tests/run.gd` → test_context green.

**Steps:**

- [ ] **Step 1: Test trước.**
- [ ] **Step 2: FAIL.**
- [ ] **Step 3: Port** từ `~/Desktop/RD/Spore/src/game/context.ts` (228 dòng — bỏ phần liên quan Bus/EV TS, thay bằng Godot signals; bỏ migrateLegacy/save.ts envelope — FileAccess trực tiếp + shape validation inline). bestiary entry shape giữ nguyên.
- [ ] **Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: game context + save port`.

---

### Task 14: Milestone wrap — docs + full-suite green

**Goal:** Kết milestone 1: docs native + mọi test xanh + commit mốc.

**Files:**
- Create: `docs/ARCHITECTURE.md` (native — layer map + determinism + runner usage), `README.md` (repo intro: what/why/status/milestone plan), `tools/test.sh` (wrap `godot --headless -s tests/run.gd`)

**Acceptance Criteria:**
- [ ] Full suite: `godot --headless -s tests/run.gd` → 0 failures, exit 0, không script error.
- [ ] ARCHITECTURE.md ghi: layer tách sim/Godot, determinism contract (Rng stream, cấm global RNG), runner usage, parity fixture approach.
- [ ] README: giới thiệu repo native + status milestone + trỏ docs/specs.
- [ ] Commit + tag `sim-core-m1`.

**Verify:** `cd ~/Desktop/RD/primordia-native && ./tools/test.sh` → exit 0.

**Steps:**

- [ ] **Step 1: Viết docs** (ngắn, đúng giáng).
- [ ] **Step 2: Full suite run + fix residual.**
- [ ] **Step 3: Commit `docs: native architecture + milestone m1` + tag.**

---

## Self-Review

**Spec coverage:** §2 tech (Godot 4.2.2, Compatibility, GDScript typed, zero plugin) → T1 + Global Constraints; §3 layout → T1 structure + các task paths; §4 layer tách (RefCounted thuần, determinism, i18n) → constraints + T3/T13 (i18n TranslationServer là stage-milestone — sim tasks không cần; ghi chú này nằm trong spec §5.2+ nên không có task ở đây — chấp nhận vì milestone 1 không có UI); §5.1 sim core list → T3-T13 đủ từng module; §6 QC gates (TDD, probes, determinism) → mỗi task + T14; §7 risks — perf/creature/audio là milestone sau, không thuộc plan này. **Gap check:** i18n CSV không có task — đúng, vì không có user-facing string nào ở sim layer (names là procedural, không qua i18n). Events bus signal — T13 dùng Godot signal thay Bus/EV; các stage dùng sau.

**Placeholder scan:** T6 Step 1 "sinh pin values nếu generator chưa có" — có hành động cụ thể (chạy vitest in values, dán literal). T8/T9 "đọc TS file" — đó là nguồn nội dung port (file TS là spec thực), mỗi task pin hằng số + test cụ thể. Không có TBD.

**Type consistency:** `Rng.new_from(int)` (T3) — các task sau dùng `Rng.new_from(seed)` hoặc `Rng.new(seed)` — quy ước: constructor `_init(seed := 1)` nên `Rng.new(seed)` là chuẩn; `new_from` chỉ là alias cho fixture test — nhất quán OK. `Genome` là static funcs trên class (T4) ↔ T5/T7/T8 dùng `Genome.default_genome()` ✓. EcoMods Dictionary (T8) ↔ `eco_mods_from_world` trả Dictionary (T10) ✓. `EcoSpecies` Dictionary fields snake_case (T8) ↔ T9 ledger fields cùng dict ✓. Signals (T13 `dna_gained`) không đụng sim tasks khác ✓.
