# Tests for game/context.gd — the GameContext spine + JSON save/load.
# TS source: Spore src/game/context.ts (round-11, 322 lines). The native save
# format is fresh v1: TS v1/v2 saves are deliberately NOT migrated, so a
# version-2 blob must be rejected.
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const Genome := preload("res://src/evo/genome.gd")
const Stats := preload("res://src/evo/stats.gd")
const Rng := preload("res://src/core/rng.gd")
const Eco := preload("res://src/evo/ecosystem.gd")
const WorldGenome := preload("res://src/evo/world_genome.gd")

# Dedicated test slots (90+): each test wipes its own slot files at start so
# execution order / leftovers never matter. Real player slots (0+) untouched.
const SLOT_RT := 90      # round trip + wire keys
const SLOT_MENU := 91    # menu-save refusal + default slot
const SLOT_JUNK := 92    # junk / malformed files
const SLOT_VER := 93     # version gate
const SLOT_WORLD := 94   # world blob overlay
const SLOT_CORRUPT := 95 # corrupt-field defaults
const SLOT_LEGS := 96    # legs clamp
const SLOT_WS := 97      # worldStats reset-then-overlay
const SLOT_ISO_A := 100
const SLOT_ISO_B := 101
const SLOT_ISO_C := 102
const SLOT_BEST := 103   # bestiary list gate
const SLOT_ABSENT := 104 # never written
const SLOT_DIR := 105    # write failure: a DIRECTORY squatting on the slot path


func _g(mods: Dictionary = {}) -> Dictionary:
	var g: Dictionary = Genome.default_genome()
	g.merge(mods, true)
	return g


func _path(n: int) -> String:
	return "user://saves/slot%d.json" % n


func _wipe(n: int) -> void:
	if FileAccess.file_exists(_path(n)):
		DirAccess.remove_absolute(_path(n))


func _write_raw(n: int, text: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(_path(n), FileAccess.WRITE)
	f.store_string(text)


func _write_json(n: int, data: Dictionary) -> void:
	_write_raw(n, JSON.stringify(data))


## Full valid minimal SaveData blob (TS wire keys) for corruption cases.
func _base() -> Dictionary:
	return {
		"version": 1, "seed": 555, "stage": "cell", "difficulty": "normal",
		"genome": {}, "dna": 10, "karma": 0.0, "chaos": 0.15, "playtime": 0.0,
		"totalDnaEarned": 0, "playerName": "Squish", "bestiary": [], "eco": null,
		"flags": {},
	}


func _capture_toast(ctx) -> Array:
	var toasts: Array = []
	ctx.toast.connect(func(text, kind, icon): toasts.append([text, kind, icon]))
	return toasts


func _capture_dna(ctx) -> Array:
	var evs: Array = []
	ctx.dna_gained.connect(func(amount, reason, x, y): evs.append([amount, reason, x, y]))
	return evs


func test_construction_defaults() -> void:
	var ctx = Ctx.new(42)
	eq(ctx.seed, 42, "seed kept")
	eq(ctx.dna, 40, "dna starts 40")
	eq(ctx.karma, 0.0, "karma starts 0")
	approx(ctx.chaos, 0.15, "chaos starts 0.15")
	eq(ctx.difficulty, "normal", "difficulty starts normal")
	eq(ctx.slot, 0, "slot starts 0")
	eq(ctx.playtime, 0.0, "playtime starts 0")
	eq(ctx.total_dna_earned, 0, "totalDnaEarned starts 0")
	eq(ctx.player_name, "Squish", "playerName starts Squish")
	eq(ctx.stage, "menu", "stage starts menu")
	ok(ctx.bestiary.is_empty(), "bestiary starts empty")
	ok(ctx.eco == null, "eco starts null")
	ok(ctx.flags.is_empty(), "flags start empty")
	eq(ctx.world_stats["kills"], 0, "worldStats.kills starts 0")
	eq(ctx.world_stats["extinctions"], 0, "worldStats.extinctions starts 0")
	ok(ctx.rng != null, "rng built from seed")
	# stats cached at construction with land=false -> cell stats
	approx(float(ctx.stats["max_hp"]), 53.0, "stats cached at construction (cell maxHp)")
	# world genome derived from the seed
	eq(ctx.world["seed"], 42, "world derives from the seed")
	ok(ctx.world["traits"].size() >= 4 and ctx.world["traits"].size() <= 6, "world derives 4-6 traits")
	ok(ctx.world["turns"].size() <= 2, "world derives 0-2 turns")
	ok(["none", "cradle", "lean", "wildcard"].has(ctx.world["temperament"]), "temperament in whitelist")
	var again: Dictionary = WorldGenome.derive_world_genome(42)
	eq(ctx.world["traits"].size(), again["traits"].size(), "derive is deterministic (trait count)")


func test_seed_picker_default() -> void:
	var a = Ctx.new()
	ok(a.seed >= 0, "negative default draws the sanctioned global randi()")
	eq(a.world["seed"], a.seed, "world derives from the picked seed")
	var b = Ctx.new(-5)
	ok(b.seed >= 0, "explicit negative seed also draws")


func test_add_dna_fractional_accumulate_and_signal() -> void:
	var ctx = Ctx.new(7)
	var evs := _capture_dna(ctx)
	ctx.add_dna(0, "zero")
	eq(ctx.dna, 40, "add_dna(0) is a no-op")
	eq(evs.size(), 0, "no signal on zero")
	ctx.add_dna(0.5)
	eq(ctx.dna, 40, "fractional gain stays in the accumulator")
	eq(evs.size(), 0, "no whole part -> no signal")
	ctx.add_dna(0.5)
	eq(ctx.dna, 41, "0.5+0.5 crosses one whole DNA")
	eq(evs.size(), 1, "one dna_gained emit")
	eq(ctx.total_dna_earned, 1, "totalDnaEarned tracks positive whole gains")
	eq(evs[0][0], 1, "signal carries the whole amount")
	eq(evs[0][1], null, "reason rides null when absent")
	ctx.add_dna(0.25)
	ctx.add_dna(-1.0)  # frac -0.75 -> whole 0
	eq(ctx.dna, 41, "negative gain below a whole DNA does nothing")
	eq(evs.size(), 1, "no emit when the whole part is 0")
	ctx.add_dna(-0.5)  # frac -1.25 -> whole -1
	eq(ctx.dna, 40, "negative whole drains dna")
	eq(evs.size(), 2, "negative whole emits too")
	eq(evs[1][0], -1, "negative emit amount")
	eq(ctx.total_dna_earned, 1, "negative gains never bump totalDnaEarned")
	# fresh context for the payload pin (the accumulator carries residue)
	var ctx2 = Ctx.new(8)
	var evs2 := _capture_dna(ctx2)
	ctx2.add_dna(2.0, "meal", 5.0, 6.0)
	eq(ctx2.dna, 42, "whole gain adds directly")
	eq(evs2.size(), 1, "whole gain emits once")
	eq(evs2[0][0], 2, "payload amount")
	eq(evs2[0][1], "meal", "payload reason")
	eq(evs2[0][2], 5.0, "payload x")
	eq(evs2[0][3], 6.0, "payload y")
	eq(ctx2.total_dna_earned, 2, "totalDnaEarned += whole")


func test_add_dna_floor_at_zero() -> void:
	var ctx = Ctx.new(7)
	ctx.dna = 1
	var evs := _capture_dna(ctx)
	ctx.add_dna(-5.0)
	eq(ctx.dna, 0, "dna floors at 0")
	eq(ctx.total_dna_earned, 0, "floor keeps totalDnaEarned")
	eq(evs.size(), 1, "floor still emits the drain")
	eq(evs[0][0], -5, "floor emits the negative whole")


func test_spend_dna() -> void:
	var ctx = Ctx.new(7)  # dna 40
	ok(ctx.spend_dna(10), "affordable spend returns true")
	eq(ctx.dna, 30, "spend deducts")
	ok(not ctx.spend_dna(31), "unaffordable spend returns false")
	eq(ctx.dna, 30, "failed spend leaves dna untouched")
	ok(ctx.spend_dna(30), "exact spend succeeds")
	eq(ctx.dna, 0, "exact spend drains to zero")
	ok(not ctx.spend_dna(1), "nothing left to spend")
	eq(ctx.dna, 0, "refused spend at zero keeps 0")


func test_chaos_karma_clamps() -> void:
	var ctx = Ctx.new(7)
	ctx.add_chaos(0.5)
	approx(ctx.chaos, 0.65, "chaos drifts up")
	ctx.add_chaos(0.5)
	approx(ctx.chaos, 1.0, "chaos clamps at 1")
	ctx.add_chaos(-2.0)
	approx(ctx.chaos, 0.0, "chaos clamps at 0")
	ctx.add_karma(0.4)
	approx(ctx.karma, 0.4, "karma drifts up")
	ctx.add_karma(2.0)
	approx(ctx.karma, 1.0, "karma clamps at +1")
	ctx.add_karma(-3.0)
	approx(ctx.karma, -1.0, "karma clamps at -1")


func test_difficulty_getters() -> void:
	for row in [["peaceful", 1.5, 0.08], ["chaos", 0.7, 0.45], ["normal", 1.0, 0.15]]:
		var ctx = Ctx.new(7)
		ctx.difficulty = row[0]
		approx(ctx.chaos_gap_mult(), row[1], "%s chaos gap mult" % row[0])
		approx(ctx.starting_chaos(), row[2], "%s starting chaos" % row[0])


func test_bestiary_dedupe_lite_hash() -> void:
	var ctx = Ctx.new(7)
	# sat is NOT in the lite hash: genomes differing only in sat collide
	var e1: Dictionary = ctx.discover(_g({"sat": 0.55}), "A", "cell")
	var e2: Dictionary = ctx.discover(_g({"sat": 0.9}), "B", "cell")
	eq(ctx.bestiary.size(), 1, "sat-only difference collides into one entry")
	eq(e1["seen"], 2, "seen increments on every discover (same entry)")
	eq(e1["name"], "A", "first name wins")
	eq(e1["key"], Ctx.genome_hash_lite(_g({"sat": 0.55})), "entry key is the lite hash")
	eq(e1.size(), 8, "entry carries exactly the 8 TS keys (no note)")
	for k in ["key", "name", "genome", "stage", "seen", "killsByPlayer", "extinct", "kin"]:
		ok(e1.has(k), "entry key %s present" % k)
	# hue-12 bucket: 120 and 125 share bucket round(x/12)=10; 126 hits 11
	var hb = Ctx.new(11)
	var k120: String = hb.discover(_g({"hue": 120.0}), "a", "cell")["key"]
	var k125: String = hb.discover(_g({"hue": 125.0}), "b", "cell")["key"]
	eq(k120, k125, "hue 120 and 125 share the /12 bucket")
	eq(hb.bestiary.size(), 1, "same-bucket hues dedupe")
	var hc = Ctx.new(12)
	hc.discover(_g({"hue": 125.0}), "c", "cell")
	hc.discover(_g({"hue": 126.0}), "d", "cell")
	eq(hc.bestiary.size(), 2, "hue 125 vs 126 crosses the /12 bucket")
	# entry genome is clamped, caller's genome untouched
	var src := _g({"size": 99.0})
	var big = Ctx.new(13)
	var eb: Dictionary = big.discover(src, "Big", "cell")
	approx(float(src["size"]), 99.0, "caller genome not mutated")
	approx(float(eb["genome"]["size"]), 2.2, "entry genome clamped")
	# kin flag rides
	var k: Dictionary = big.discover(_g({"jaw": 4}), "KinGuy", "cell", true)
	eq(k["kin"], true, "kin true when flagged")
	var nk: Dictionary = big.discover(_g({"jaw": 5}), "NotKin", "cell")
	eq(nk["kin"], false, "kin false by default")


func test_discover_toast_menu_gate() -> void:
	var ctx = Ctx.new(7)
	var toasts := _capture_toast(ctx)
	ctx.discover(_g({"jaw": 2}), "MenuGuy", "menu")
	eq(toasts.size(), 0, "no toast spam while the title screen seeds ecosystems")
	ctx.stage = "cell"
	var e: Dictionary = ctx.discover(_g({"jaw": 3}), "CellGuy", "cell")
	eq(toasts.size(), 1, "toast on the first discovery off the menu")
	eq(toasts[0][0], "New species discovered: CellGuy", "t() falls back to the key")
	eq(toasts[0][1], "good", "discovery toast kind")
	eq(toasts[0][2], "📖", "discovery toast icon")
	var again: Dictionary = ctx.discover(_g({"jaw": 3}), "CellGuy", "cell")
	eq(toasts.size(), 1, "re-discovering a known species stays quiet")
	eq(again["seen"], 2, "seen still increments")


func test_mark_extinct() -> void:
	var ctx = Ctx.new(7)
	var toasts := _capture_toast(ctx)
	var e: Dictionary = ctx.discover(_g({"jaw": 2}), "Doomed", "cell")
	ctx.mark_extinct(_g({"jaw": 2}))
	eq(e["extinct"], true, "entry flips extinct")
	eq(toasts.size(), 1, "extinction toast")
	eq(toasts[0][0], "Doomed has gone EXTINCT", "extinction text")
	eq(toasts[0][1], "chaos", "extinction kind")
	eq(toasts[0][2], "💀", "extinction icon")
	ctx.mark_extinct(_g({"jaw": 2}))
	eq(toasts.size(), 1, "already-extinct entry stays quiet")
	ctx.mark_extinct(_g({"jaw": 4}))
	eq(toasts.size(), 1, "unknown genome stamps nothing")


func test_rare_gene() -> void:
	var ctx = Ctx.new(7)
	eq(ctx.rare_gene(), null, "empty bestiary -> null")
	# insertion order: the FIRST entry carrying a greater part wins
	var e1: Dictionary = ctx.discover(_g({"jaw": 3}), "J", "cell")
	ctx.discover(_g({"flagella": 4}), "F", "cell")
	var r: Variant = ctx.rare_gene()
	ok(r != null, "a greater part level is found")
	eq(r["gene"], "jaw", "bestiary insertion order wins over later entries")
	eq(r["level"], 3, "rare gene level rides")
	eq(e1["key"], ctx.bestiary.keys()[0], "sanity: e1 inserted first")
	# null when no entry part exceeds the player's
	var ctx2 = Ctx.new(7)
	ctx2.genome = _g({"flagella": 6, "jaw": 5})
	ctx2.discover(_g({"jaw": 3, "flagella": 4}), "X", "cell")
	eq(ctx2.rare_gene(), null, "nothing greater -> null")
	# bool genes never count (TS typeof guard)
	var ctx3 = Ctx.new(7)
	ctx3.genome = _g({"flagella": 6, "jaw": 5})
	ctx3.discover(_g({"tail": true}), "T", "cell")
	eq(ctx3.rare_gene(), null, "tail is a bool, not a number")


func test_bump_counters() -> void:
	var ctx = Ctx.new(7)
	ctx.bump_kill()
	ctx.bump_kill()
	eq(ctx.world_stats["kills"], 2, "kills accumulate")
	eq(ctx.world_stats["extinctions"], 0, "extinctions untouched by kills")
	ctx.bump_extinction()
	eq(ctx.world_stats["extinctions"], 1, "extinctions accumulate")


func test_refresh_stats_cached() -> void:
	var ctx = Ctx.new(7)
	approx(float(ctx.stats["max_hp"]), float(Stats.compute_stats(ctx.genome, false)["max_hp"]),
			"cached stats == compute_stats(genome, land=false)")
	approx(float(ctx.stats["max_hp"]), 53.0, "cell maxHp pin")
	var s: Dictionary = ctx.refresh_stats(true)
	approx(float(s["max_hp"]), float(Stats.compute_stats(ctx.genome, true)["max_hp"]),
			"refresh returns the fresh stats")
	approx(float(s["max_hp"]), 70.0, "creature maxHp pin")
	approx(float(ctx.stats["max_hp"]), 70.0, "cache updated in place")
	ctx.refresh_stats(false)
	approx(float(ctx.stats["max_hp"]), 53.0, "cache flips back to cell")


func test_save_load_round_trip() -> void:
	_wipe(SLOT_RT)
	var ctx = Ctx.new(777)
	ctx.genome = _g({"jaw": 2, "hue": 200.0})
	ctx.stage = "cell"
	ctx.difficulty = "chaos"
	ctx.dna = 123
	ctx.karma = 0.4
	ctx.chaos = 0.6
	ctx.playtime = 60.5
	ctx.player_name = "Hero"
	ctx.total_dna_earned = 200
	ctx.slot = SLOT_RT
	ctx.flags = {"huts": 3, "won": true, "tag": "x"}
	var g1 := _g({"jaw": 2})
	var e1: Dictionary = ctx.discover(g1, "Alpha", "cell")
	e1["killsByPlayer"] = 4
	var g2 := _g({"hue": 200.0})
	var e2: Dictionary = ctx.discover(g2, "Beta", "cell", true)
	ctx.mark_extinct(g2)
	var eco = Eco.new(Rng.new_from(5))
	eco.add_species(_g({"diet": "herbivore", "size": 0.8}), 12.0)
	eco.add_species(_g({"diet": "carnivore", "jaw": 2}), 5.0)
	eco.flora = 44.5
	eco.flora_cap = 80.0
	ctx.eco = eco
	var tid: String = ctx.world["traits"][0]["id"]
	ctx.world["revealed"][tid] = true
	ctx.world["comboFired"]["rot_circle"] = true
	ctx.world["firedTurns"]["great_frost"] = true
	ctx.bump_kill()
	ctx.bump_kill()
	ctx.bump_extinction()
	ok(ctx.save(SLOT_RT), "save into the slot")

	var loader = Ctx.new(999)
	ok(loader.load(SLOT_RT), "load succeeds")
	eq(loader.seed, 777, "seed survives")
	eq(loader.slot, SLOT_RT, "load adopts the slot")
	eq(loader.stage, "cell", "stage survives")
	eq(loader.difficulty, "chaos", "difficulty survives")
	eq(loader.dna, 123, "dna survives")
	approx(loader.karma, 0.4, "karma survives")
	approx(loader.chaos, 0.6, "chaos survives")
	approx(loader.playtime, 60.5, "playtime survives")
	eq(loader.player_name, "Hero", "playerName survives")
	eq(loader.total_dna_earned, 200, "totalDnaEarned survives")
	ok(loader.flags.get("huts") == 3 and loader.flags.get("won") == true \
			and loader.flags.get("tag") == "x", "flags survive")
	# genome
	approx(float(loader.genome["jaw"]), 2.0, "player genome survives")
	approx(float(loader.genome["hue"]), 200.0, "player hue survives")
	eq(loader.genome["flagella"], 2, "default genes intact")
	# bestiary
	eq(loader.bestiary.size(), 2, "bestiary survives")
	var le1: Dictionary = loader.bestiary[e1["key"]]
	eq(le1["name"], "Alpha", "entry name survives")
	eq(le1["killsByPlayer"], 4, "killsByPlayer survives")
	eq(le1["seen"], 1, "seen survives")
	eq(le1["extinct"], false, "living entry not extinct")
	var le2: Dictionary = loader.bestiary[e2["key"]]
	eq(le2["extinct"], true, "extinct flag survives")
	eq(le2["kin"], true, "kin survives")
	# eco
	ok(loader.eco != null, "eco restores when saved")
	eq(loader.eco.species.size(), 2, "eco species survive")
	eq(loader.eco.species[0]["id"], eco.species[0]["id"], "species id survives")
	eq(loader.eco.species[0]["name"], eco.species[0]["name"], "species name survives")
	approx(float(loader.eco.species[0]["pop"]), 12.0, "species pop survives")
	approx(loader.eco.flora, 44.5, "flora survives")
	approx(loader.eco.flora_cap, 80.0, "floraCap survives")
	# world blob
	eq(loader.world["revealed"].get(tid, false), true, "revealed survives")
	eq(loader.world["comboFired"].get("rot_circle", false), true, "comboFired survives")
	eq(loader.world["firedTurns"].get("great_frost", false), true, "firedTurns survives")
	eq(loader.world["temperament"], ctx.world["temperament"], "temperament survives")
	eq(loader.world["traits"].size(), ctx.world["traits"].size(), "traits rebuilt from ids")
	for i in ctx.world["traits"].size():
		eq(loader.world["traits"][i]["id"], ctx.world["traits"][i]["id"], "trait %d id survives" % i)
	eq(loader.world["turns"].size(), ctx.world["turns"].size(), "turns survive")
	for i in ctx.world["turns"].size():
		eq(loader.world["turns"][i], ctx.world["turns"][i], "turn %d survives" % i)
	eq(loader.world_stats["kills"], 2, "worldStats.kills survives")
	eq(loader.world_stats["extinctions"], 1, "worldStats.extinctions survives")
	# rng is rebuilt from the seed; eco restore consumed exactly one branch draw
	var ref_rng = Rng.new_from(777)
	ref_rng.branch()
	eq(loader.rng.state(), ref_rng.state(), "rng rebuilt from seed + one eco branch draw")
	# wire format: TS-verbatim keys, fresh native version 1
	var f := FileAccess.open(_path(SLOT_RT), FileAccess.READ)
	ok(f != null, "slot file readable")
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		ok(parsed is Dictionary, "slot file parses as JSON")
		if parsed is Dictionary:
			var d: Dictionary = parsed
			eq(d["version"], 1, "native save version is 1")
			for k in ["version", "seed", "stage", "difficulty", "genome", "dna", "karma",
					"chaos", "playtime", "totalDnaEarned", "playerName", "bestiary",
					"eco", "flags", "world"]:
				ok(d.has(k), "SaveData key %s present" % k)
			var wb: Dictionary = d["world"]
			for k in ["traitIds", "turnIds", "revealed", "comboFired", "firedTurns",
					"worldStats", "temperament"]:
				ok(wb.has(k), "world blob key %s present" % k)
			var be: Dictionary = d["bestiary"][0]
			for k in ["key", "name", "genome", "stage", "seen", "killsByPlayer", "extinct", "kin"]:
				ok(be.has(k), "bestiary entry key %s present" % k)


func test_slot_isolation() -> void:
	for n in [SLOT_ISO_A, SLOT_ISO_B, SLOT_ISO_C]:
		_wipe(n)
	var a = Ctx.new(111)
	a.stage = "cell"
	a.dna = 100
	ok(a.save(SLOT_ISO_A), "slot A saves")
	var b = Ctx.new(222)
	b.stage = "creature"
	b.dna = 200
	ok(b.save(SLOT_ISO_B), "slot B saves")
	var loader = Ctx.new()
	ok(loader.load(SLOT_ISO_A), "load A")
	eq(loader.dna, 100, "slot A dna")
	eq(loader.stage, "cell", "slot A stage")
	ok(loader.load(SLOT_ISO_B), "load B")
	eq(loader.dna, 200, "slot B dna")
	eq(loader.stage, "creature", "slot B stage")
	ok(not loader.load(SLOT_ISO_C), "untouched slot loads false")


func test_save_refuses_menu_and_default_slot() -> void:
	_wipe(SLOT_MENU)
	var c = Ctx.new(9)
	ok(not c.save(SLOT_MENU), "save refuses stage 'menu' (title-screen guard)")
	ok(not FileAccess.file_exists(_path(SLOT_MENU)), "no file written for a refused save")
	c.stage = "cell"
	c.slot = SLOT_MENU
	ok(c.save(), "save() defaults to the active slot")
	ok(FileAccess.file_exists(_path(SLOT_MENU)), "file written to the default slot")


func test_save_reports_write_failure() -> void:
	# a DIRECTORY squatting on the slot path makes the open/write fail — TS
	# writeFileSync throws = fail-loud, so the native save must report false
	# instead of returning true over a truncated/missing file
	if DirAccess.dir_exists_absolute(_path(SLOT_DIR)):
		DirAccess.remove_absolute(_path(SLOT_DIR))
	DirAccess.make_dir_recursive_absolute(_path(SLOT_DIR))  # directory AS the slot path
	ok(not FileAccess.file_exists(_path(SLOT_DIR)), "pre: no file at the slot path")
	var ctx = Ctx.new(7)
	ctx.stage = "cell"
	ctx.dna = 55
	eq(ctx.save(SLOT_DIR), false, "save over a directory path reports false")
	# the context is untouched by the failed save
	eq(ctx.stage, "cell", "failed save leaves the context untouched")
	eq(ctx.dna, 55, "failed save leaves dna untouched")
	# and nothing readable appeared at the slot (load falls back to fresh)
	var loader = Ctx.new(1)
	ok(not loader.load(SLOT_DIR), "nothing loads from the failed slot")
	ok(DirAccess.dir_exists_absolute(_path(SLOT_DIR)), "directory still there (nothing replaced it)")
	DirAccess.remove_absolute(_path(SLOT_DIR))
	ok(not DirAccess.dir_exists_absolute(_path(SLOT_DIR)), "cleanup at test end")


func test_junk_and_malformed_files() -> void:
	_wipe(SLOT_JUNK)
	var loader = Ctx.new(1)
	_write_raw(SLOT_JUNK, "not json {{{")
	ok(not loader.load(SLOT_JUNK), "junk text loads false")
	_write_raw(SLOT_JUNK, "")
	ok(not loader.load(SLOT_JUNK), "empty file loads false")
	_write_raw(SLOT_JUNK, "[1,2,3]")
	ok(not loader.load(SLOT_JUNK), "top-level array loads false")
	_write_raw(SLOT_JUNK, "42")
	ok(not loader.load(SLOT_JUNK), "top-level number loads false")
	ok(not loader.load(SLOT_ABSENT), "missing file loads false")
	eq(loader.seed, 1, "failed loads leave the context untouched")


func test_version_gate() -> void:
	_wipe(SLOT_VER)
	var loader = Ctx.new(1)
	var d := _base()
	d["version"] = 2
	_write_json(SLOT_VER, d)
	ok(not loader.load(SLOT_VER), "TS v2 blob rejected (fresh native format)")
	d = _base()
	d.erase("version")
	_write_json(SLOT_VER, d)
	ok(not loader.load(SLOT_VER), "missing version rejected")
	d = _base()
	d["version"] = "1"
	_write_json(SLOT_VER, d)
	ok(not loader.load(SLOT_VER), "string version rejected")
	d = _base()
	d["version"] = 1.5
	_write_json(SLOT_VER, d)
	ok(not loader.load(SLOT_VER), "fractional version rejected")
	d = _base()
	d["version"] = 1.0
	_write_json(SLOT_VER, d)
	ok(loader.load(SLOT_VER), "1.0 equals 1 like in JS")


func test_world_blob_overlay() -> void:
	_wipe(SLOT_WORLD)
	var d := _base()
	d["seed"] = 555
	d["world"] = {
		"traitIds": ["hungry_bloom", "no_such_trait"],
		"turnIds": ["great_frost"],
		"revealed": {"hungry_bloom": true, "junk": "yes", "num": 1},
		"comboFired": {"rot_circle": true},
		"firedTurns": {"great_frost": false},
		"worldStats": {"kills": 3, "extinctions": -4.7},
		"temperament": "lean",
	}
	_write_json(SLOT_WORLD, d)
	var loader = Ctx.new(1)
	ok(loader.load(SLOT_WORLD), "blob save loads")
	var ids: Array = []
	for t in loader.world["traits"]:
		ids.append(t["id"])
	eq(ids, ["hungry_bloom"], "unknown traitIds dropped, known kept by order")
	eq(loader.world["temperament"], "lean", "temperament overlay when whitelisted")
	eq(loader.world["revealed"], {"hungry_bloom": true}, "boolRec drops non-bool values")
	eq(loader.world["comboFired"], {"rot_circle": true}, "comboFired overlays")
	eq(loader.world["firedTurns"], {"great_frost": false}, "false is a bool and survives")
	eq(loader.world["turns"], ["great_frost"], "turnIds filter non-strings")
	eq(loader.world_stats["kills"], 3, "worldStats.kills overlays")
	eq(loader.world_stats["extinctions"], 0, "stat(-4.7) floors to max(0, -5) -> 0")
	# all-unknown traitIds keep the re-derive; junk records keep the re-derive
	d = _base()
	d["world"] = {
		"traitIds": ["bogus"],
		"revealed": "junk",
		"worldStats": {"kills": "x"},
		"temperament": "bogus",
	}
	_write_json(SLOT_WORLD, d)
	var loader2 = Ctx.new(1)
	ok(loader2.load(SLOT_WORLD), "second blob save loads")
	ok(loader2.world["traits"].size() >= 4, "all-unknown traitIds keep the re-derived traits")
	ok(loader2.world["revealed"].is_empty(), "junk revealed keeps the re-derived (empty) record")
	eq(loader2.world_stats["kills"], 0, "non-numeric stat reads as 0")
	eq(loader2.world_stats["extinctions"], 0, "missing stat reads as 0")
	ok(loader2.world["temperament"] != "bogus", "off-whitelist temperament keeps the re-derive")
	var derived: Dictionary = WorldGenome.derive_world_genome(555)
	eq(loader2.world["temperament"], derived["temperament"], "temperament equals the re-derive")


func test_load_corrupt_fields_fall_back_to_defaults() -> void:
	_wipe(SLOT_CORRUPT)
	var loader = Ctx.new(1)
	var d := _base()
	d["stage"] = "menu"
	_write_json(SLOT_CORRUPT, d)
	ok(not loader.load(SLOT_CORRUPT), "stage 'menu' fails the stage gate")
	d = _base()
	d.erase("stage")
	_write_json(SLOT_CORRUPT, d)
	ok(not loader.load(SLOT_CORRUPT), "missing stage fails the gate")
	d = _base()
	d["dna"] = "12"
	_write_json(SLOT_CORRUPT, d)
	ok(not loader.load(SLOT_CORRUPT), "non-numeric dna fails the gate")
	d = _base()
	d["seed"] = "x"
	_write_json(SLOT_CORRUPT, d)
	ok(not loader.load(SLOT_CORRUPT), "non-numeric seed fails the gate")
	d = _base()
	d["genome"] = 5
	_write_json(SLOT_CORRUPT, d)
	ok(not loader.load(SLOT_CORRUPT), "non-object genome fails the gate")
	d = _base()
	d["eco"] = {}
	_write_json(SLOT_CORRUPT, d)
	ok(not loader.load(SLOT_CORRUPT), "eco without a species array fails the gate")
	d = _base()
	d["flags"] = []
	_write_json(SLOT_CORRUPT, d)
	ok(not loader.load(SLOT_CORRUPT), "array flags fail the gate")
	# genome arrays pass the TS typeof-object gate and merge no keys (parity quirk)
	d = _base()
	d["genome"] = [1, 2]
	_write_json(SLOT_CORRUPT, d)
	ok(loader.load(SLOT_CORRUPT), "array genome passes the object gate")
	eq(loader.genome["flagella"], 2, "array genome merges nothing -> defaults")
	# defaults when fields are missing
	d = _base()
	d.erase("karma")
	d.erase("chaos")
	d.erase("difficulty")
	d.erase("playerName")
	d.erase("playtime")
	d.erase("totalDnaEarned")
	_write_json(SLOT_CORRUPT, d)
	ok(loader.load(SLOT_CORRUPT), "sparse save loads")
	eq(loader.karma, 0.0, "karma defaults to 0")
	approx(loader.chaos, 0.15, "chaos defaults to 0.15")
	eq(loader.difficulty, "normal", "difficulty defaults to normal")
	eq(loader.player_name, "Squish", "playerName defaults to Squish")
	eq(loader.playtime, 0.0, "playtime defaults to 0")
	eq(loader.total_dna_earned, 0, "totalDnaEarned defaults to 0")
	ok(loader.eco == null, "missing eco loads as null")
	eq(loader.genome["jaw"], 1, "empty genome merges with defaults")
	eq(loader.genome["eyes"], 1, "default eyes")
	approx(float(loader.genome["hue"]), 120.0, "default hue")
	approx(float(loader.genome["sat"]), 0.55, "default sat")
	# difficulty whitelist
	d = _base()
	d["difficulty"] = "bogus"
	_write_json(SLOT_CORRUPT, d)
	ok(loader.load(SLOT_CORRUPT), "bogus difficulty still loads")
	eq(loader.difficulty, "normal", "bogus difficulty -> normal")
	d = _base()
	d["difficulty"] = "peaceful"
	_write_json(SLOT_CORRUPT, d)
	ok(loader.load(SLOT_CORRUPT), "whitelisted difficulty loads")
	eq(loader.difficulty, "peaceful", "whitelisted difficulty rides")
	# playerName truthiness
	d = _base()
	d["playerName"] = ""
	_write_json(SLOT_CORRUPT, d)
	ok(loader.load(SLOT_CORRUPT), "empty playerName loads")
	eq(loader.player_name, "Squish", "empty playerName -> Squish")
	d = _base()
	d["playerName"] = "Zed"
	_write_json(SLOT_CORRUPT, d)
	ok(loader.load(SLOT_CORRUPT), "named playerName loads")
	eq(loader.player_name, "Zed", "named playerName rides")
	# meter clamps on load
	d = _base()
	d["karma"] = 5.0
	d["chaos"] = -3
	_write_json(SLOT_CORRUPT, d)
	ok(loader.load(SLOT_CORRUPT), "out-of-range meters load")
	approx(loader.karma, 1.0, "karma clamps on load")
	approx(loader.chaos, 0.0, "chaos clamps on load")
	# genome shallow merge with defaults, unknown keys ride
	d = _base()
	d["genome"] = {"jaw": 4, "custom": 5}
	_write_json(SLOT_CORRUPT, d)
	ok(loader.load(SLOT_CORRUPT), "partial genome loads")
	eq(loader.genome["jaw"], 4, "saved gene overrides the default")
	eq(loader.genome["flagella"], 2, "unsaved gene keeps the default")
	eq(loader.genome.get("custom"), 5, "unknown genome keys ride the merge (TS spread)")


func test_load_bestiary_gate() -> void:
	_wipe(SLOT_BEST)
	var loader = Ctx.new(1)
	var d := _base()
	d["bestiary"] = [{"key": "k1", "genome": {"jaw": 2}, "note": "hi"}]
	_write_json(SLOT_BEST, d)
	ok(loader.load(SLOT_BEST), "valid bestiary loads")
	eq(loader.bestiary.size(), 1, "valid entry kept")
	eq(loader.bestiary["k1"].get("note"), "hi", "optional note rides")
	d = _base()
	d["bestiary"] = [{"key": 5, "genome": {}}]
	_write_json(SLOT_BEST, d)
	ok(loader.load(SLOT_BEST), "non-string key still loads")
	eq(loader.bestiary.size(), 0, "non-string key drops the whole list")
	d = _base()
	d["bestiary"] = [{"key": "k", "genome": "x"}]
	_write_json(SLOT_BEST, d)
	ok(loader.load(SLOT_BEST), "non-object genome still loads")
	eq(loader.bestiary.size(), 0, "non-object genome drops the whole list")
	d = _base()
	d["bestiary"] = "junk"
	_write_json(SLOT_BEST, d)
	ok(loader.load(SLOT_BEST), "non-array bestiary still loads")
	eq(loader.bestiary.size(), 0, "non-array bestiary drops the whole list")
	d = _base()
	d["bestiary"] = [{"key": "k1"}, {"key": "k2", "genome": {}}]
	_write_json(SLOT_BEST, d)
	ok(loader.load(SLOT_BEST), "mixed validity bestiary still loads")
	eq(loader.bestiary.size(), 0, "one bad apple drops the whole list (TS some)")


func test_legs_clamp_on_load() -> void:
	_wipe(SLOT_LEGS)
	for row in [[7, 6], [4, 4], [8, 6], ["x", 0]]:
		var d := _base()
		d["genome"] = {"legs": row[0]}
		_write_json(SLOT_LEGS, d)
		var loader = Ctx.new(1)
		ok(loader.load(SLOT_LEGS), "legs %s loads" % str(row[0]))
		eq(int(loader.genome["legs"]), row[1], "legs %s clamps to %d" % [str(row[0]), row[1]])


func test_world_stats_reset_then_overlay() -> void:
	_wipe(SLOT_WS)
	# no world blob: the unconditional reset wipes pre-existing counters
	var d := _base()
	_write_json(SLOT_WS, d)
	var loader = Ctx.new(3)
	loader.bump_kill()
	loader.bump_kill()
	loader.bump_extinction()
	ok(loader.load(SLOT_WS), "blob-less save loads")
	eq(loader.world_stats["kills"], 0, "reset runs even without a blob")
	eq(loader.world_stats["extinctions"], 0, "reset clears extinctions too")
	# with a blob: reset happens BEFORE the overlay (never accumulates)
	d = _base()
	d["world"] = {"worldStats": {"kills": 7, "extinctions": 9}}
	_write_json(SLOT_WS, d)
	var loader2 = Ctx.new(3)
	loader2.bump_kill()
	loader2.bump_extinction()
	ok(loader2.load(SLOT_WS), "blob save loads")
	eq(loader2.world_stats["kills"], 7, "overlay wins over the reset, no accumulation")
	eq(loader2.world_stats["extinctions"], 9, "overlay wins over the reset, no accumulation")
