# Tests for game/tribe/tribe_sim.gd — the tribe stage sim core (M4 task 1):
# constructor world-seeding, onEnter semantics (restore / re-found / pack
# conversion), chief movement + death/respawn, tribesman AI (fight/job/arrive),
# economy (deliveries, regrow, saplings, hut build/repair/recruit, totem,
# festival passive), popCap, persist/restore guards.
# TS source: Spore src/game/tribe/TribeStage.ts (frozen), lines cited per pin.
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const RngLib := preload("res://src/core/rng.gd")
const TribeSim := preload("res://src/game/tribe/tribe_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE
const Z_TO_Y := 0.62
const Z_MIN := -200.0
const Z_MAX := 240.0
const WORLD_HALF := 2400.0
const OBJECTIVE := "GATHER · BUILD · SURVIVE — raise the Great Totem"


# ---- fixtures ------------------------------------------------------------------

# Builds a GameContext (explicit seed), the stage rng branch, a recording
# hooks set, and the sim. genome_mods merge into ctx.genome BEFORE sim
# construction (chiefStats is a construction-time snapshot, TS-verbatim).
func _mk_sim(seed_v: int = SEED, genome_mods: Dictionary = {},
		difficulty: String = "normal") -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	if not genome_mods.is_empty():
		var g: Dictionary = ctx.genome
		g.merge(genome_mods, true)
	ctx.difficulty = difficulty
	var rec: Dictionary = {
		"toasts": [], "banners": [], "audio": [], "shakes": [], "bursts": [],
		"spawns": [], "events": [], "objectives": [], "insets": [], "moods": [],
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"audio_set_mood": func(name_v): rec["moods"].append(name_v),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"context_event": func(ev, data): rec["events"].append([ev, data]),
		"hud_show_objective": func(text): rec["objectives"].append(text),
		"hud_toast_inset": func(px): rec["insets"].append(px),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = TribeSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


# Input snapshot with the ruling's field shape; `over` merges overrides.
func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


# The TS constructor's exact draw sequence from a parallel branch of a fresh
# same-seed context — pins draw ORDER + formulas bit-exactly (TS:107-133).
func _expected_world(seed_v: int) -> Dictionary:
	var pr: Variant = Ctx.new(seed_v).rng.branch()
	var trees: Array = []
	for i in 30:
		trees.append({"x": pr.range(-WORLD_HALF, WORLD_HALF), "z": pr.range(Z_MIN, Z_MAX),
				"wood": pr.range(4.0, 9.0), "seed": pr.range(0.0, 9.0)})
	var bushes: Array = []
	for i in 26:
		bushes.append({"x": pr.range(-WORLD_HALF, WORLD_HALF),
				"z": pr.range(Z_MIN, Z_MAX), "food": pr.range(3.0, 7.0)})
	var rivals: Array = []
	for i in 2:
		rivals.append({"x": (-1.0 if i == 0 else 1.0) * pr.range(1300.0, 2000.0),
				"z": pr.range(-120.0, 160.0)})
	return {"trees": trees, "bushes": bushes, "rivals": rivals}


func _heard(rec: Dictionary, name_v: String) -> bool:
	for a in rec["audio"]:
		if a[0] == name_v:
			return true
	return false


func _toasted(rec: Dictionary, fragment: String) -> bool:
	for t in rec["toasts"]:
		if String(t[0]).find(fragment) >= 0:
			return true
	return false


# A tribesman dict built like add_tribesman, appended directly (test seam).
func _add_t(sim: Variant, x: float, z: float, role_v: String = "gather") -> Dictionary:
	var genome: Dictionary = sim.ctx.genome.duplicate()
	sim.add_tribesman(genome, role_v)
	var t: Dictionary = sim.tribe[sim.tribe.size() - 1]
	t["x"] = x
	t["z"] = z
	t["vx"] = 0.0
	t["vz"] = 0.0
	return t


# ---- constructor seeding (TS:101-137) --------------------------------------------

func test_constructor_seeding_pins() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	eq(sim.trees.size(), 30, "30 trees seeded")
	eq(sim.bushes.size(), 26, "26 bushes seeded")
	eq(sim.huts.size(), 1, "1 starting hut")
	eq(sim.rivals.size(), 2, "2 rivals")
	eq(float(sim.food), 60.0, "food 60 (TS:62)")
	eq(float(sim.wood), 30.0, "wood 30 (TS:63)")
	eq(float(sim.dayPhase), 0.2, "dayPhase 0.2 (TS:82)")
	eq(float(sim.raidTimer), 75.0, "raidTimer 75 (TS:88)")
	eq(float(sim.px), 0.0, "px 0 (TS:66)")
	eq(float(sim.pz), 60.0, "pz 60 (TS:66)")
	eq(float(sim.time), 0.0, "time 0")
	eq(bool(sim.raidActive), false, "raidActive false (TS:91)")
	eq(float(sim.deathFade), 0.0, "deathFade 0 (TS:92)")
	eq(float(sim.totem["progress"]), 0.0, "totem progress 0 (TS:93)")
	eq(bool(sim.totem["active"]), false, "totem inactive (TS:93)")
	eq(sim.beast, null, "beast null (TS:996)")
	eq(float(sim.fallenT), 0.0, "fallenT 0 (TS:94)")
	eq(float(sim.invulnT), 0.0, "invulnT 0 (TS:97)")
	eq(float(sim.saplingT), 60.0, "saplingT 60 (TS:969)")
	eq(sim.deckSeed, int(ctx.world["seed"]), "deckSeed = world seed (TS:136)")
	eq(sim.chaos != null, true, "chaos scheduler constructed (TS:135)")
	# starting hut (TS:121)
	var h: Dictionary = sim.huts[0]
	eq(float(h["x"]), 0.0, "starting hut x 0")
	eq(float(h["z"]), 80.0, "starting hut z 80")
	eq(float(h["hp"]), 100.0, "starting hut hp 100")
	eq(float(h["maxHp"]), 100.0, "starting hut maxHp 100")
	eq(float(h["pop"]), 0.0, "starting hut pop 0")
	eq(float(h["buildT"]), 0.0, "starting hut built (buildT 0)")
	ok(not h.has("recruitT"), "recruitT absent until set (TS optional field)")
	# rivals (TS:124-133)
	var names: Array = ["Gnash", "Ruk"]
	for i in 2:
		var r: Dictionary = sim.rivals[i]
		eq(String(r["name"]), names[i], "rival name %d" % i)
		eq(float(r["hp"]), 100.0, "rival hp 100")
		eq(float(r["anger"]), 0.0, "rival anger 0")
		if i == 0:
			ok(float(r["x"]) < 0.0, "rival 0 on the -x side")
		else:
			ok(float(r["x"]) > 0.0, "rival 1 on the +x side")
		ok(absf(float(r["x"])) >= 1300.0 and absf(float(r["x"])) <= 2000.0,
				"rival |x| in [1300, 2000]")
		ok(float(r["z"]) >= -120.0 and float(r["z"]) <= 160.0, "rival z in [-120, 160]")
	# range pins on the seeded world (values already covered by the parallel draw)
	for tr in sim.trees:
		ok(float(tr["wood"]) >= 4.0 and float(tr["wood"]) < 9.0, "tree wood in [4, 9)")
		ok(float(tr["seed"]) >= 0.0 and float(tr["seed"]) < 9.0, "tree seed in [0, 9)")
		ok(float(tr["burn"]) == 0.0, "tree burn 0")
	for b in sim.bushes:
		ok(float(b["food"]) >= 3.0 and float(b["food"]) < 7.0, "bush food in [3, 7)")
		ok(float(b["regrow"]) == 0.0, "bush regrow 0")


func test_constructor_draw_order_bit_exact() -> void:
	# the sim's world must equal the parallel branch's draws EXACTLY (same
	# engine, same seed → bit-equal), pinning the stream order trees → bushes
	# → rivals → chaos branch (TS:107-136)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var exp_w: Dictionary = _expected_world(SEED)
	eq(sim.trees.size(), exp_w["trees"].size(), "tree count match")
	for i in 30:
		var got: Dictionary = sim.trees[i]
		var want: Dictionary = exp_w["trees"][i]
		eq(float(got["x"]), float(want["x"]), "tree %d x bit-exact" % i)
		eq(float(got["z"]), float(want["z"]), "tree %d z bit-exact" % i)
		eq(float(got["wood"]), float(want["wood"]), "tree %d wood bit-exact" % i)
		eq(float(got["seed"]), float(want["seed"]), "tree %d seed bit-exact" % i)
	for i in 26:
		var got: Dictionary = sim.bushes[i]
		var want: Dictionary = exp_w["bushes"][i]
		eq(float(got["x"]), float(want["x"]), "bush %d x bit-exact" % i)
		eq(float(got["z"]), float(want["z"]), "bush %d z bit-exact" % i)
		eq(float(got["food"]), float(want["food"]), "bush %d food bit-exact" % i)
	for i in 2:
		var got: Dictionary = sim.rivals[i]
		var want: Dictionary = exp_w["rivals"][i]
		eq(float(got["x"]), float(want["x"]), "rival %d x bit-exact" % i)
		eq(float(got["z"]), float(want["z"]), "rival %d z bit-exact" % i)


# ---- popCap (TS:272) -------------------------------------------------------------

func test_pop_cap_formula() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	eq(sim.pop_cap(), 4, "1 built hut → cap 4 (1*3+1)")
	sim.huts.append({"x": 10.0, "z": 10.0, "hp": 100.0, "maxHp": 100.0,
			"pop": 0.0, "buildT": 3.0})
	eq(sim.pop_cap(), 4, "building hut (buildT > 0) does not count")
	sim.huts[1]["buildT"] = 0.0
	eq(sim.pop_cap(), 7, "built hut counts (2*3+1)")
	sim.huts[1]["buildT"] = -1.0
	eq(sim.pop_cap(), 7, "buildT <= 0 counts (TS <= 0)")
	sim.huts.pop_back()
	eq(sim.pop_cap(), 4, "hut removal lowers the cap")
	sim.huts.clear()
	eq(sim.pop_cap(), 1, "hutless → cap 1")


# ---- onEnter: pack conversion (TS:175-189) ----------------------------------------

func test_on_enter_pack_conversion() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# 5 pack genomes → 5 tribesmen (count = max(3, raw.length))
	var pack: Array = []
	for i in 5:
		var g: Dictionary = {"hue": 10.0 + float(i), "legs": 2}
		pack.append({"genome": g, "baby": false})
	ctx.flags["packGenomes"] = JSON.stringify(pack)
	sim.on_enter()
	eq(sim.tribe.size(), 5, "5 pack genomes → 5 tribesmen")
	for i in 5:
		eq(float(sim.tribe[i]["genome"]["hue"]), 10.0 + float(i), "pack hue %d carried" % i)
		eq(String(sim.tribe[i]["role"]), "gather", "founding role gather")
		eq(float(sim.tribe[i]["hp"]), float(sim.tribe[i]["maxHp"]), "tribesman at full hp")
	eq(String(ctx.flags["packGenomes"]), "[]", "packGenomes reset after conversion")
	eq(String(m["rec"]["objectives"][0]), OBJECTIVE, "objective set on founding")
	eq(m["rec"]["moods"][0], "tribe", "audio.setMood('tribe') hook (TS:146)")
	eq(m["rec"]["insets"][0], 190, "hud.toastInset 190 hook (TS:154)")
	eq(float(sim.invulnT), 3.0, "reload-ambush grace invulnT 3 (TS:159)")


func test_on_enter_pack_minimum_three_and_fallbacks() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# empty pack → 3 mutants of the chief genome (mutateLike: hue ±40, size ±0.3)
	ctx.flags["packGenomes"] = "[]"
	sim.on_enter()
	eq(sim.tribe.size(), 3, "empty pack → minimum 3 tribesmen")
	var hue0: float = float(ctx.genome["hue"])
	var size0: float = float(ctx.genome["size"])
	for i in 3:
		var g: Dictionary = sim.tribe[i]["genome"]
		var dh: float = fposmod(float(g["hue"]) - hue0, 360.0)
		ok(dh <= 40.0 or dh >= 320.0, "mutant hue within ±40 (wrap) of the chief")
		ok(absf(float(g["size"]) - size0) <= 0.3001, "mutant size within gauss·0.1·3 of the chief")
	# missing flag → same minimum-3 path
	var m2 := _mk_sim()
	sim = m2["sim"]
	sim.on_enter()
	eq(sim.tribe.size(), 3, "missing packGenomes → 3 tribesmen")
	# corrupt (non-JSON) flag → try/catch → empty pack → 3
	var m3 := _mk_sim()
	sim = m3["sim"]
	m3["ctx"].flags["packGenomes"] = "not json at all"
	sim.on_enter()
	eq(sim.tribe.size(), 3, "corrupt flag → 3 tribesmen")
	eq(String(m3["ctx"].flags["packGenomes"]), "[]", "corrupt flag reset to '[]'")


func test_on_enter_pack_clamp_guard_and_one_genome() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# 1 clamped genome + 2 mutants = 3 (count = max(3, 1))
	var pack: Array = [{"genome": {"size": 99.0, "hue": "garbage", "legs": 99}, "baby": false}]
	m["ctx"].flags["packGenomes"] = JSON.stringify(pack)
	sim.on_enter()
	eq(sim.tribe.size(), 3, "1 pack genome → 3 founders")
	var g0: Dictionary = sim.tribe[0]["genome"]
	eq(float(g0["size"]), 2.2, "pack size 99 clamped to 2.2 (never NaN)")
	eq(float(g0["legs"]), 8.0, "pack legs clamped to bounds")
	ok(float(g0["hue"]) >= 0.0 and float(g0["hue"]) < 360.0, "garbage hue snapped into [0, 360)")
	# stats sane: hp is a finite number derived from the clamped genome
	ok(is_finite(float(sim.tribe[0]["maxHp"])), "clamped founder maxHp finite")
	# a member whose genome is a truthy non-object: TS spread no-ops → default
	# genome (port matches); a missing genome → mutateLike fallback
	var pack2: Array = [{"genome": 5}, {"genome": {"hue": 200.0}}]
	m["ctx"].flags["packGenomes"] = JSON.stringify(pack2)
	sim.on_enter()  # second on_enter: tribe non-empty → conversion skipped
	eq(sim.tribe.size(), 3, "conversion runs ONCE (tribe already populated)")


# ---- onEnter: restore short-circuit + hutless re-found (TS:139-173) ---------------

func _village_blob() -> String:
	return JSON.stringify({
		"food": 123.0, "wood": 45.0,
		"huts": [
			{"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0, "pop": 0.0, "buildT": 0.0},
			{"x": 30.0, "z": 90.0, "hp": 80.0, "maxHp": 100.0, "pop": 0.0, "buildT": 0.0},
		],
		"totemProg": 40.0, "totemActive": true,
		"tribe": [
			{"genome": {"hue": 11.0}, "role": "hunt"},
			{"genome": {"hue": 22.0}, "role": "warrior"},
			{"genome": {"hue": 33.0}, "role": "boss"},
		],
	})


func test_on_enter_restore_short_circuit() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ctx.flags["tribeState"] = _village_blob()
	ctx.flags["packGenomes"] = JSON.stringify([{"genome": {"hue": 1.0}}])
	sim.on_enter()
	# restored as it stood
	eq(float(sim.food), 123.0, "food restored")
	eq(float(sim.wood), 45.0, "wood restored")
	eq(sim.huts.size(), 2, "huts restored")
	eq(float(sim.huts[1]["hp"]), 80.0, "hut hp restored")
	eq(float(sim.totem["progress"]), 40.0, "totem progress restored")
	eq(bool(sim.totem["active"]), true, "totem active restored")
	eq(sim.tribe.size(), 3, "tribe restored (REPLACED, not appended)")
	eq(String(sim.tribe[0]["role"]), "hunt", "role hunt kept")
	eq(String(sim.tribe[1]["role"]), "warrior", "role warrior kept")
	eq(String(sim.tribe[2]["role"]), "gather", "unknown role sanitized to gather")
	# short-circuit: the pack was NOT consumed
	ok(ctx.flags["packGenomes"] != "[]", "packGenomes untouched on the restore path")
	eq(String(m["rec"]["objectives"][0]), OBJECTIVE, "objective set on the restore path")


func test_on_enter_deck_rebuild_gate_c1() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var chaos0: Variant = sim.chaos
	sim.on_enter()
	ok(sim.chaos == chaos0, "same world → deck NOT rebuilt")
	var ctx: Variant = m["ctx"]
	ctx.world["seed"] = int(ctx.world["seed"]) + 1
	sim.on_enter()
	ok(sim.chaos != chaos0, "different world → deck rebuilt (C1)")
	eq(sim.deckSeed, int(ctx.world["seed"]), "deckSeed tracks the new world")


func test_on_enter_hutless_refound_resets() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# a collapsed village + no blob → the same fresh-start as the constructor
	sim.huts.clear()
	sim.food = 5.0
	sim.wood = 1.0
	sim.fallenT = 2.0
	sim.fallFired = true
	sim.victoryFired = true
	sim.deathHandled = true
	sim.deathFade = 0.5
	sim.on_enter()
	eq(sim.huts.size(), 1, "re-found reseeds the starting hut")
	eq(float(sim.huts[0]["z"]), 80.0, "re-founded hut at z 80")
	eq(float(sim.food), 60.0, "re-found reseeds food 60")
	eq(float(sim.wood), 30.0, "re-found reseeds wood 30")
	eq(float(sim.fallenT), 0.0, "fallenT reset (the 3-bounce fix)")
	eq(bool(sim.fallFired), false, "fallFired reset")
	eq(bool(sim.victoryFired), false, "victoryFired reset")
	eq(bool(sim.deathHandled), false, "deathHandled reset")
	eq(float(sim.deathFade), 0.0, "deathFade reset")


# ---- persist / restore (TS:197-244) ----------------------------------------------

func test_persist_blob_and_round_trip() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# build village progress
	sim.food = 77.5
	sim.wood = 33.0
	sim.totem = {"progress": 40.0, "active": true}
	sim.huts.append({"x": 25.0, "z": 95.0, "hp": 80.0, "maxHp": 100.0,
			"pop": 0.0, "buildT": 0.0})
	sim.add_tribesman({"hue": 11.0}, "hunt")
	sim.add_tribesman({"hue": 22.0}, "warrior")
	sim.persist_state()
	var raw: Variant = ctx.flags.get("tribeState")
	ok(raw is String, "flags.tribeState written (camelCase key)")
	var blob: Dictionary = JSON.parse_string(raw)
	eq(float(blob["food"]), 77.5, "blob food")
	eq(float(blob["wood"]), 33.0, "blob wood")
	eq(blob["huts"].size(), 2, "blob huts")
	eq(float(blob["huts"][1]["hp"]), 80.0, "blob hut hp")
	eq(float(blob["huts"][1]["buildT"]), 0.0, "blob hut buildT")
	eq(float(blob["totemProg"]), 40.0, "blob totemProg (camelCase)")
	eq(bool(blob["totemActive"]), true, "blob totemActive (camelCase)")
	eq(blob["tribe"].size(), 2, "blob tribe")
	eq(String(blob["tribe"][0]["role"]), "hunt", "blob tribe role")
	# round-trip: a fresh sim over the SAME ctx restores the village
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	m2["ctx"].flags["tribeState"] = raw
	sim2.on_enter()
	eq(float(sim2.food), 77.5, "round-trip food")
	eq(float(sim2.wood), 33.0, "round-trip wood")
	eq(sim2.huts.size(), 2, "round-trip huts")
	eq(float(sim2.totem["progress"]), 40.0, "round-trip totem progress")
	eq(bool(sim2.totem["active"]), true, "round-trip totem active")
	eq(sim2.tribe.size(), 2, "round-trip tribe size")
	eq(String(sim2.tribe[1]["role"]), "warrior", "round-trip role")


func test_persist_corpse_guard() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ctx.flags["tribeState"] = "keep-me"
	# a corpse (fallen + nobody + hutless) must never overwrite the delete
	sim.fallenT = 5.0
	sim.tribe.clear()
	sim.huts.clear()
	sim.persist_state()
	eq(String(ctx.flags["tribeState"]), "keep-me", "corpse guard: nothing written")
	# alive again (someone survived) → writes normally
	sim.add_tribesman({"hue": 9.0}, "gather")
	sim.persist_state()
	ok(ctx.flags["tribeState"] != "keep-me", "non-corpse persists")


func test_restore_corrupt_guards() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# guard 1: non-finite food/wood (TS:222) — a string is not a number
	ctx.flags["tribeState"] = JSON.stringify({"food": "50", "wood": 30.0,
			"huts": [{"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0}], "tribe": []})
	eq(bool(sim.restore_state()), false, "string food → blob rejected")
	ctx.flags["tribeState"] = JSON.stringify({"food": 50.0, "wood": null,
			"huts": [{"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0}], "tribe": []})
	eq(bool(sim.restore_state()), false, "missing wood → blob rejected")
	ctx.flags["tribeState"] = "definitely not json"
	eq(bool(sim.restore_state()), false, "unparseable blob rejected")
	# guard 2: an EMPTY village (0 huts AND 0 tribe) is a corpse (TS:226)
	ctx.flags["tribeState"] = JSON.stringify({"food": 50.0, "wood": 30.0,
			"huts": [], "tribe": []})
	eq(bool(sim.restore_state()), false, "empty village blob rejected")
	# tribe-only (hutless) village RESTORES (only the huts0+tribe0 pair is dead)
	ctx.flags["tribeState"] = JSON.stringify({"food": 50.0, "wood": 30.0, "huts": [],
			"tribe": [{"genome": {"hue": 5.0}, "role": "hunt"}]})
	eq(bool(sim.restore_state()), true, "hutless tribe blob restores")
	# guard 3: REPLACE the roster, never append (the 3→6→12 doubling bug, TS:236)
	var m3 := _mk_sim()
	var sim3: Variant = m3["sim"]
	sim3.add_tribesman({"hue": 1.0}, "gather")
	sim3.add_tribesman({"hue": 2.0}, "gather")
	sim3.add_tribesman({"hue": 3.0}, "gather")
	sim3.add_tribesman({"hue": 4.0}, "gather")
	m3["ctx"].flags["tribeState"] = JSON.stringify({"food": 50.0, "wood": 30.0,
			"huts": [{"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0}],
			"tribe": [{"genome": {"hue": 7.0}, "role": "warrior"},
					{"genome": {"hue": 8.0}, "role": "gather"}]})
	sim3.on_enter()
	eq(sim3.tribe.size(), 2, "roster REPLACED (2), not appended (6)")
	eq(float(sim3.tribe[0]["genome"]["hue"]), 7.0, "restored genome wins")


func test_restore_cap_and_hut_filters() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var big_tribe: Array = []
	for i in 20:
		big_tribe.append({"genome": {"hue": float(i)}, "role": "gather"})
	# 20 members but cap = max(12, 1*3+1) = 12
	ctx.flags["tribeState"] = JSON.stringify({"food": 50.0, "wood": 30.0,
			"huts": [{"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0}],
			"tribe": big_tribe})
	sim.on_enter()
	eq(sim.tribe.size(), 12, "roster capped at max(12, huts*3+1)")
	# corrupt huts: non-finite coords dropped, hp clamped to >= 1, pop/buildT defaulted
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	m2["ctx"].flags["tribeState"] = JSON.stringify({"food": 50.0, "wood": 30.0,
			"huts": [
				{"x": "abc", "z": 80.0, "hp": 100.0, "maxHp": 100.0},
				{"x": 5.0, "z": 80.0, "hp": -20.0, "maxHp": 100.0},
				{"x": 6.0, "z": 81.0, "hp": 50.0, "maxHp": 100.0, "pop": "x", "buildT": -4.0},
			],
			"tribe": [{"genome": {"hue": 5.0}, "role": "hunt"}]})
	sim2.on_enter()
	eq(sim2.huts.size(), 2, "corrupt-coordinate hut dropped (TS:230 filter)")
	eq(float(sim2.huts[0]["hp"]), 1.0, "hp clamped to >= 1")
	eq(float(sim2.huts[1]["pop"]), 0.0, "garbage pop reads 0")
	eq(float(sim2.huts[1]["buildT"]), 0.0, "negative buildT clamped to 0")
	# totem clamp 0..100 (TS:232)
	var m3 := _mk_sim()
	var sim3: Variant = m3["sim"]
	m3["ctx"].flags["tribeState"] = JSON.stringify({"food": 50.0, "wood": 30.0,
			"huts": [{"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0}],
			"totemProg": 140.0, "tribe": []})
	eq(bool(sim3.restore_state()), true, "tribe-bearing blob restores")
	eq(float(sim3.totem["progress"]), 100.0, "totemProg 140 clamps to 100")


# ---- chief movement (TS:456-516) ---------------------------------------------------

func test_chief_click_move_and_wasd() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# click-move: hold pointer at world (200, pz*Z_TO_Y) → chief accelerates +x
	var inp := _inp({"down": true, "wx": 200.0, "wy": float(sim.pz) * Z_TO_Y})
	sim.update(DT, inp)
	ok(float(sim.px) > 0.0, "chief moves toward the click target")
	eq(int(sim.facing), 1, "facing +1 moving right")
	# deadzone 12 (TS:464-465): a target within 12px produces no acceleration
	# (zero the residual velocity first — the deadzone kills accel, not motion)
	sim.pvx = 0.0
	sim.pvz = 0.0
	var px_before: float = float(sim.px)
	var inp_dz := _inp({"down": true, "wx": px_before + 5.0, "wy": float(sim.pz) * Z_TO_Y})
	sim.update(DT, inp_dz)
	eq(float(sim.px), px_before, "click-move deadzone: |dx| < 12 → no move")
	# WASD (TS:467-470)
	px_before = float(sim.px)
	var inp_a := _inp({"keys_held": ["KeyA"]})
	sim.update(DT, inp_a)
	ok(float(sim.px) < px_before, "KeyA moves left")
	eq(int(sim.facing), -1, "facing -1 moving left")
	var pz_before: float = float(sim.pz)
	var inp_w := _inp({"keys_held": ["KeyW"]})
	sim.update(DT, inp_w)
	ok(float(sim.pz) < pz_before, "KeyW moves up (−z)")
	# speed clamp from chiefStats (TS:479-480)
	for i in 240:
		sim.update(DT, _inp({"keys_held": ["KeyD"]}))
	var sp: float = sqrt(float(sim.pvx) * float(sim.pvx) + float(sim.pvz) * float(sim.pvz))
	var cap: float = float(sim.chiefStats["speed"])
	ok(sp <= cap + 1e-6, "chief speed clamped to stats.speed")
	# z clamp (TS:482)
	for i in 600:
		sim.update(DT, _inp({"keys_held": ["KeyS"]}))
	eq(float(sim.pz), Z_MAX, "pz clamps to Z_MAX")
	# gait advances with speed01 (TS:484)
	ok(float(sim.gait) > 0.0, "gait advanced")


func test_chief_vz_accel_is_08() -> void:
	# TS:475-477 — pvz accel ×0.8 vs the x accel; both eat the same-frame
	# drag exp(−6dt) (a quirk worth pinning)
	var m1 := _mk_sim()
	var m2 := _mk_sim()
	var s1: Variant = m1["sim"]
	var s2: Variant = m2["sim"]
	s1.update(DT, _inp({"keys_held": ["KeyD"]}))
	s2.update(DT, _inp({"keys_held": ["KeyS"]}))
	var accel: float = float(s1.chiefStats["accel"])
	var drag: float = exp(-6.0 * DT)
	approx(absf(float(s1.pvx)), accel * DT * drag, "1-frame x vel = accel*dt·drag")
	approx(absf(float(s2.pvz)), accel * 0.8 * DT * drag, "1-frame z vel = accel*0.8*dt·drag")


# ---- chief death / respawn (TS:422-454, raid touch TS:504-515) ---------------------

func _warrior_at(x: float, z: float, hp: float = 60.0) -> Dictionary:
	return {"x": x, "z": z, "vx": 0.0, "vz": 0.0, "hp": hp, "genome": {"hue": 5.0},
			"gait": 0.0, "facing": 1, "state": "march"}


func test_chief_raid_touch_death_pipeline() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ctx.dna = 100
	# park a raider between the chief (0, 60) and the hut (0, 80)
	sim.rivalWarriors.append(_warrior_at(0.0, 70.0))
	sim.invulnT = 0.0
	var died_frame := -1
	for i in 900:
		sim.update(DT, _inp())
		if float(sim.deathFade) > 0.0:
			died_frame = i
			break
	ok(died_frame >= 0, "raid touch kills the chief (chance dt*2 per frame)")
	if died_frame < 0:
		return
	eq(String(sim.lastDeathCause), "raiders cut you down", "death cause recorded")
	# the tax lands on the NEXT frame's handle_chief_death pass (the death is
	# detected mid-update_chief; handle_chief_death runs at the top of update)
	sim.update(DT, _inp())
	# the 15% DNA tax fires exactly once (deathHandled latch, TS:424-432)
	eq(int(ctx.dna), 85, "15% DNA tax (100 → 85)")
	for i in 20:
		sim.update(DT, _inp())
	eq(int(ctx.dna), 85, "tax does NOT repeat before respawn")
	eq(bool(m["rec"]["events"].has(["playerDeath", "tribe"])), true,
			"context_event playerDeath fired")
	ok(_heard(m["rec"], "die"), "die audio")
	var toast: Array = m["rec"]["toasts"][0]
	eq(String(toast[0]), "The chief fell — lost 15 DNA — raiders cut you down",
			"death toast text (TS:430)")
	eq(String(toast[1]), "bad", "death toast kind bad")
	eq(String(toast[2]), "💀", "death toast icon")
	# respawn after 1.6 s (TS:433)
	eq(m["rec"]["shakes"].size() >= 1, true, "cam shake on the killing blow")
	for i in 600:
		sim.update(DT, _inp())
		if float(sim.deathFade) <= 0.0 and i > 0:
			break
	eq(float(sim.deathFade), 0.0, "deathFade reset on respawn")
	# invulnT 3 at respawn, then the same frame's decay tick reads 3 − dt
	ok(float(sim.invulnT) > 2.9 and float(sim.invulnT) <= 3.0,
			"respawn grace invulnT 3 (TS:450)")
	# the grace gates re-death even with a raider ON the chief
	sim.px = 0.0
	sim.pz = 60.0
	sim.pvx = 0.0
	sim.pvz = 0.0
	for w in sim.rivalWarriors:
		w["x"] = 0.0
		w["z"] = 70.0
	sim.update(DT, _inp())
	eq(float(sim.deathFade), 0.0, "no re-death while invulnT > 0")
	# grace expires → the raider kills again → the tax repeats (85 → 72)
	sim.invulnT = 0.0
	var died2 := false
	for i in 900:
		for w in sim.rivalWarriors:
			w["x"] = float(sim.px)
			w["z"] = float(sim.pz) + 10.0  # re-park on the chief each frame
		sim.update(DT, _inp())
		if float(sim.deathFade) > 0.0:
			died2 = true
			break
	ok(died2, "re-death after the grace expires")
	if died2:
		sim.update(DT, _inp())
		eq(int(ctx.dna), 72, "second death taxes again (85 → 72)")


func test_chief_respawn_safest_sample_geometry() -> void:
	# handle_chief_death draws 8 (cx, cz) samples and keeps the one farthest
	# from beast + warriors + fires (minD 9999 fallback, TS:437-447). With the
	# stage rng state pinned, the winner is computable in parallel.
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# no threats → every minD reads 9999 → the FIRST sample wins (later 9999s
	# fail the strict `>`)
	var pr: Variant = RngLib.new_from(4242)
	sim.rng.set_state(pr.state())
	var exp_x: float = pr.range(-WORLD_HALF * 0.5, WORLD_HALF * 0.5)
	var exp_z: float = pr.range(Z_MIN + 30.0, Z_MAX - 30.0)
	for i in 7:  # samples 1..7 are drawn too, but never win
		pr.range(-WORLD_HALF * 0.5, WORLD_HALF * 0.5)
		pr.range(Z_MIN + 30.0, Z_MAX - 30.0)
	sim.deathHandled = true  # skip the tax path; isolate the geometry
	sim.deathFade = 1.5
	sim.handle_chief_death(0.2)  # deathFade 1.7 > 1.6 → respawn
	eq(float(sim.px), exp_x, "respawn x = first sample (no threats)")
	eq(float(sim.pz), exp_z, "respawn z = first sample (no threats)")
	eq(float(sim.invulnT), 3.0, "respawn grace set")
	# with ONE warrior parked at (500, 0): winner = the sample farthest from it
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	sim2.rivalWarriors.append(_warrior_at(500.0, 0.0))
	pr = RngLib.new_from(777)
	sim2.rng.set_state(pr.state())
	var best_d := -1.0
	var bx := 0.0
	var bz := 80.0
	for i in 8:
		var cx: float = pr.range(-WORLD_HALF * 0.5, WORLD_HALF * 0.5)
		var cz: float = pr.range(Z_MIN + 30.0, Z_MAX - 30.0)
		var dx: float = 500.0 - cx
		var dy: float = 0.0 - cz
		var d: float = sqrt(dx * dx + dy * dy)
		if d > best_d:
			best_d = d
			bx = cx
			bz = cz
	sim2.deathHandled = true
	sim2.deathFade = 1.5
	sim2.handle_chief_death(0.2)
	eq(float(sim2.px), bx, "respawn x = sample farthest from the raider")
	eq(float(sim2.pz), bz, "respawn z = sample farthest from the raider")


func test_chief_death_dna_tax_rounding() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ctx.dna = 7
	sim.deathFade = 0.0001
	sim.deathHandled = false
	sim.lastDeathCause = ""
	sim.handle_chief_death(0.1)
	eq(int(ctx.dna), 6, "Math.round(7*0.15)=1 → dna 7→6")
	eq(String(m["rec"]["toasts"][0][0]), "The chief fell — lost 1 DNA",
			"toast without a cause suffix")


# ---- tribesmen: fight (TS:592-653) -------------------------------------------------

func test_tribesman_fight_power_per_role() -> void:
	# w.hp drain is the ONLY deterministic line: 22 * power * dt per frame
	var powers: Dictionary = {"gather": 0.5, "hunt": 1.0, "warrior": 1.6}
	for role_v in powers:
		var m := _mk_sim()
		var sim: Variant = m["sim"]
		var t := _add_t(sim, 0.0, 60.0, role_v)
		sim.rivalWarriors.append(_warrior_at(3.0, 60.0))
		var frames := 60
		for i in frames:
			sim.update(DT, _inp())
		var want: float = 60.0 - 22.0 * float(powers[role_v]) * DT * float(frames)
		approx(float(sim.rivalWarriors[0]["hp"]), want,
				"rival hp drain at power %s" % role_v)
		eq(String(t["mood"]), "angry", "fighting tribesman is angry (%s)" % role_v)
		eq(float(t["attack"]), 1.0, "attack pose set while fighting")


func test_tribesman_fight_self_damage_and_death() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var t := _add_t(sim, 0.0, 60.0, "warrior")
	var w := _warrior_at(3.0, 60.0)
	sim.rivalWarriors.append(w)
	var hurt_frames := 0
	for i in 1200:
		w["hp"] = 60.0  # keep the fight alive (the drain would end it ~frame 102)
		var hp_before: float = float(t["hp"])
		sim.update(DT, _inp())
		if float(t["hp"]) < hp_before:
			hurt_frames += 1
	ok(hurt_frames > 0, "self-damage 10 @ chance dt*1.2 landed")
	# a tribesman death splices the roster + bursts + toast (TS:648-652)
	t["hp"] = 0.0
	sim.update(DT, _inp())
	eq(sim.tribe.size(), 0, "dead tribesman spliced")
	ok(m["rec"]["bursts"].size() > 0, "death burst")
	ok(_toasted(m["rec"], "A tribesman has fallen…"), "death toast")


func test_rival_warrior_death_feeds_food() -> void:
	# TS:658-662 — hp <= 0 → splice + food +8
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.rivalWarriors.append(_warrior_at(9999.0, 0.0, 0.0))  # dead on arrival
	sim.food = 10.0
	sim.update(DT, _inp())
	eq(sim.rivalWarriors.size(), 0, "dead warrior spliced")
	eq(float(sim.food), 18.0, "food +8 per kill")


# ---- tribesmen: job AI (TS:747-856) ------------------------------------------------

func _clean_world(sim: Variant) -> void:
	# park the seeded field far away so resource pins are deterministic
	for tr in sim.trees:
		tr["x"] = 99999.0
		tr["z"] = 99999.0
	for b in sim.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0


func test_job_ai_gather_wood_quota() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_clean_world(sim)
	var tree: Dictionary = {"x": 100.0, "z": 60.0, "wood": 5.0, "burn": 0.0, "seed": 1.0}
	var bush: Dictionary = {"x": -50.0, "z": 60.0, "food": 4.0, "regrow": 0.0}
	sim.trees.append(tree)
	sim.bushes.append(bush)
	# under quota (wood < 80): EVEN-indexed tribesmen chop, odd ones gather berries
	sim.wood = 79.0
	var t0 := _add_t(sim, 0.0, 60.0, "gather")   # index 0 → wood shift
	var t1 := _add_t(sim, 0.0, 60.0, "gather")   # index 1 → berries
	sim.update(DT, _inp())
	eq(float(t0["targetX"]), 100.0, "even gatherer targets the tree under quota")
	eq(bool(t0["hasTarget"]), true, "target acquired")
	eq(float(t1["targetX"]), -50.0, "odd gatherer targets the nearest bush")
	# quota met (wood >= 80): everyone gathers berries
	sim.wood = 80.0
	for t in sim.tribe:
		t["hasTarget"] = false
		t["retargetT"] = 0.0
	sim.update(DT, _inp())
	eq(float(t0["targetX"]), -50.0, "quota met → even gatherer back to berries")
	eq(float(t1["targetX"]), -50.0, "quota met → odd gatherer berries")
	# no bush within 600 → tree fallback for both (TS:766-768)
	bush["x"] = 99999.0
	bush["z"] = 99999.0
	for t in sim.tribe:
		t["hasTarget"] = false
		t["retargetT"] = 0.0
	sim.update(DT, _inp())
	eq(float(t0["targetX"]), 100.0, "bushless → tree fallback (even)")
	eq(float(t1["targetX"]), 100.0, "bushless → tree fallback (odd)")


func test_job_ai_hunt_and_carry_delivery_target() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_clean_world(sim)
	var bush: Dictionary = {"x": -50.0, "z": 60.0, "food": 4.0, "regrow": 0.0}
	var tree: Dictionary = {"x": 100.0, "z": 60.0, "wood": 5.0, "burn": 0.0, "seed": 1.0}
	sim.trees.append(tree)
	sim.bushes.append(bush)
	# hunt prefers bush 600 else tree (TS:778-783) — no quota gate
	var t := _add_t(sim, 0.0, 60.0, "hunt")
	sim.update(DT, _inp())
	eq(float(t["targetX"]), -50.0, "hunt targets the nearest bush in 600")
	# carrying → deliver to the nearest BUILT hut (TS:769-774)
	t["carrying"] = "wood"
	t["hasTarget"] = false
	t["retargetT"] = 0.0
	sim.update(DT, _inp())
	eq(float(t["targetX"]), 0.0, "carrying → nearest hut target")
	eq(float(t["targetZ"]), 80.0, "carrying → hut z")
	# hutless village → drop at the chief
	sim.huts.clear()
	t["hasTarget"] = false
	t["retargetT"] = 0.0
	sim.update(DT, _inp())
	eq(float(t["targetX"]), float(sim.px), "hutless delivery targets the chief")
	eq(float(t["targetZ"]), float(sim.pz), "hutless delivery targets chief z")


func test_job_ai_retarget_cadence() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_clean_world(sim)
	var t := _add_t(sim, 0.0, 60.0, "gather")
	sim.update(DT, _inp())
	eq(bool(t["hasTarget"]), true, "initial retarget")
	# within the 0.5 s cadence the target is NOT re-chosen (hasTarget stays)
	t["retargetT"] = 0.4
	t["hasTarget"] = false  # force: without a target the AI must refuse to retarget
	sim.update(DT, _inp())
	eq(bool(t["hasTarget"]), false, "retarget cadence: 0.4 s < 0.5 s → no retarget")
	t["retargetT"] = 0.0
	sim.update(DT, _inp())
	eq(bool(t["hasTarget"]), true, "cadence expired → retargets")


func test_job_ai_warrior_patrol_and_march() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_clean_world(sim)
	var t := _add_t(sim, 0.0, 60.0, "warrior")
	# patrol around the home hut ±90/±60 (TS:801-807)
	sim.update(DT, _inp())
	eq(bool(t["hasTarget"]), true, "warrior patrols")
	var tx: float = float(t["targetX"])
	var tz: float = float(t["targetZ"])
	ok(absf(tx - 0.0) <= 90.0 + 12.0, "patrol x within hut ±90 (+epsilon drift)")
	ok(absf(tz - 80.0) <= 60.0 + 12.0, "patrol z within hut ±60 (+epsilon drift)")
	# a living rival + the 0.005 march chance → target near the rival camp
	var rival: Dictionary = {"x": 1500.0, "z": 0.0, "hp": 100.0, "anger": 0.0, "name": "Gnash"}
	sim.rivals.append(rival)
	var marched := false
	for i in 6000:
		t["hasTarget"] = false
		t["retargetT"] = 0.0
		sim.update(DT, _inp())
		if absf(float(t["targetX"]) - 1500.0) <= 80.0 and absf(float(t["targetZ"]) - 0.0) <= 60.0:
			marched = true
			break
	ok(marched, "warrior marches on the rival camp @ chance 0.005")
	if marched:
		eq(t["carrying"], null, "march drops the cargo (TS:800)")


# ---- tribeArrive + economy arrivals (TS:815-843, 1088-1102) ------------------------

func test_arrive_pickup_and_delivery() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_clean_world(sim)
	# spread the field: bush/tree/hut pairwise > 30 apart so a pickup at one
	# cannot spill into the other (the TS pickup loops are radius-30 each)
	var bush: Dictionary = {"x": -120.0, "z": 60.0, "food": 4.0, "regrow": 0.0}
	var tree: Dictionary = {"x": 200.0, "z": 60.0, "wood": 5.0, "burn": 0.0, "seed": 1.0}
	sim.trees.append(tree)
	sim.bushes.append(bush)
	sim.wood = 79.0  # keep the even-indexed gatherer on the wood shift
	# index 0 works the wood shift from afar; the BUSH PICKER must be index 1
	_add_t(sim, -800.0, 100.0, "gather")
	var t := _add_t(sim, -120.0, 60.0, "gather")  # index 1 → berries, ON the bush
	t["retargetT"] = 0.0
	sim.update(DT, _inp())
	eq(String(t["carrying"]), "food", "standing at a bush picks up food")
	eq(float(bush["food"]), 3.0, "bush food −1")
	eq(float(bush["regrow"]), 30.0, "bush regrow timer 30")
	# deliver within 44 of the hut (TS:816-820 + 1088-1097) — walk there first
	t["carrying"] = "food"
	t["hasTarget"] = false
	t["retargetT"] = 0.0
	sim.food = 10.0
	for i in 900:
		sim.update(DT, _inp())
		if t["carrying"] == null:
			break
	eq(t["carrying"], null, "cargo delivered")
	eq(float(sim.food), 18.0, "delivery +8 food")
	ok(m["rec"]["spawns"].size() > 0, "delivery fx dot")
	# tree pickup: drop the filler so the picker becomes index 0 (wood shift)
	sim.tribe.remove_at(0)
	t["carrying"] = null
	t["x"] = 200.0
	t["z"] = 60.0
	t["vx"] = 0.0
	t["vz"] = 0.0
	t["hasTarget"] = false
	t["retargetT"] = 0.0
	sim.wood = 79.0
	sim.update(DT, _inp())
	eq(String(t["carrying"]), "wood", "standing at a tree picks up wood")
	eq(float(tree["wood"]), 4.0, "tree wood −1")


func test_arrive_hutless_delivery_at_chief() -> void:
	# TS:1093 — atChief gate when the village is GONE
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_clean_world(sim)
	sim.huts.clear()
	var t := _add_t(sim, float(sim.px) + 10.0, float(sim.pz), "gather")
	t["carrying"] = "wood"
	t["hasTarget"] = false
	t["retargetT"] = 0.0
	sim.wood = 0.0
	sim.update(DT, _inp())
	eq(float(sim.wood), 8.0, "hutless delivery +8 wood at the chief")


func test_arrive_burning_tree_not_pickable() -> void:
	# direct tribe_arrive pins the pickup gate itself (TS:836: burn <= 0)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_clean_world(sim)
	var burning: Dictionary = {"x": 0.0, "z": 60.0, "wood": 5.0, "burn": 3.0, "seed": 1.0}
	sim.trees.append(burning)
	var t := _add_t(sim, 0.0, 60.0, "gather")
	sim.tribe_arrive(t)
	eq(t["carrying"], null, "burning tree is not pickable")
	eq(float(burning["wood"]), 5.0, "burning tree keeps its wood")
	burning["burn"] = 0.0  # the fire dies → the tree becomes pickable
	sim.tribe_arrive(t)
	eq(String(t["carrying"]), "wood", "extinguished tree picks up")
	eq(float(burning["wood"]), 4.0, "tree wood −1")


# ---- economy: regrow / sapling / burnout (TS:1104-1132) ----------------------------

func test_economy_regrow_sapling_burnout() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# bush regrow: empty bush refills to rng 3..7 after its 30 s timer (TS:1105-1110)
	var b: Dictionary = sim.bushes[0]
	b["food"] = 0.0
	b["regrow"] = 0.05
	sim.update(0.1, _inp())
	ok(float(b["food"]) >= 3.0 and float(b["food"]) < 7.0, "regrown food in [3, 7)")
	var refilled: float = float(b["food"])
	sim.update(0.1, _inp())
	eq(float(b["food"]), refilled, "no re-refill while food > 0")
	# sapling every 45 s while alive trees < 30 (TS:1112-1125)
	for tr in sim.trees:
		tr["wood"] = 0.0
	sim.saplingT = 0.05
	sim.update(0.1, _inp())
	eq(sim.trees.size(), 31, "sapling added while alive < 30")
	eq(float(sim.saplingT), 45.0, "sapling clock reset to 45")
	var young: Dictionary = sim.trees[30]
	ok(float(young["wood"]) >= 4.0 and float(young["wood"]) < 9.0, "sapling wood in [4, 9)")
	# a full stand grows nothing
	for tr in sim.trees:
		tr["wood"] = 5.0
	sim.saplingT = 0.05
	sim.update(0.1, _inp())
	eq(sim.trees.size(), 31, "30 alive trees → no sapling")
	# tree burnout: burn expires → wood 0 (TS:1127-1132)
	var tr0: Dictionary = sim.trees[0]
	tr0["burn"] = 0.05
	tr0["wood"] = 5.0
	sim.update(0.1, _inp())
	eq(float(tr0["wood"]), 0.0, "burnt-out tree loses its wood")
	ok(float(tr0["burn"]) <= 0.0, "burn timer expired")


# ---- economy: hut build / repair / recruit (TS:1134-1157) --------------------------

func test_economy_hut_build_complete_and_repair() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var h: Dictionary = sim.huts[0]
	h["buildT"] = 0.05
	sim.update(0.1, _inp())
	eq(float(h["buildT"]), 0.0, "build completes (clamped to 0)")
	ok(_toasted(m["rec"], "A new hut raises the roof!"), "completion toast")
	ok(_heard(m["rec"], "build"), "build audio")
	# repair +5·dt to maxHp (TS:1143)
	h["hp"] = 50.0
	sim.update(0.1, _inp())
	approx(float(h["hp"]), 50.5, "hut repairs at 5/s")
	# repair clamps AT maxHp (TS:1143 min)
	h["hp"] = 99.95
	sim.update(0.1, _inp())
	eq(float(h["hp"]), 100.0, "repair clamps to maxHp")


func test_economy_recruit_gates() -> void:
	# happy path: 45 s on a built hut + no siege + under cap → birth (TS:1145-1156)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var h: Dictionary = sim.huts[0]
	h["recruitT"] = 44.99
	eq(sim.pop_cap(), 4, "cap 4 with one hut")
	eq(sim.tribe.size(), 0, "no tribesmen yet")
	sim.update(DT, _inp())
	eq(sim.tribe.size(), 1, "a child was born")
	eq(float(h["recruitT"]), 0.0, "recruit clock reset")
	ok(_toasted(m["rec"], "A child was born in the hut! (+1 tribesman)"), "birth toast")
	ok(_heard(m["rec"], "spawn"), "spawn audio")
	# mid-siege block: NO births while rival warriors stand (TS:1148)
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var h2: Dictionary = sim2.huts[0]
	h2["recruitT"] = 44.99
	sim2.rivalWarriors.append(_warrior_at(500.0, 0.0))
	sim2.update(DT, _inp())
	eq(sim2.tribe.size(), 0, "no births mid-siege")
	approx(float(h2["recruitT"]), 44.99 + DT, "siege holds the clock (no reset)")
	# popCap gate: full village waits (clock still resets, TS:1149-1151)
	var m3 := _mk_sim()
	var sim3: Variant = m3["sim"]
	var h3: Dictionary = sim3.huts[0]
	h3["recruitT"] = 44.99
	for i in 4:
		_add_t(sim3, float(i) * 30.0, 100.0, "gather")
	sim3.update(DT, _inp())
	eq(sim3.tribe.size(), 4, "no birth at popCap")
	eq(float(h3["recruitT"]), 0.0, "clock resets even when the cap blocks")
	# an unbuilt hut never recruits (TS:1145 gate)
	var m4 := _mk_sim()
	var sim4: Variant = m4["sim"]
	sim4.huts[0]["buildT"] = 3.0
	sim4.update(DT, _inp())
	ok(not sim4.huts[0].has("recruitT"), "building hut does not accumulate recruitT")


# ---- economy: totem progress + festival passive (TS:1160-1171) ---------------------

func test_economy_totem_progress_rate() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	for i in 3:
		_add_t(sim, float(i) * 20.0, 60.0, "gather")
	sim.totem = {"progress": 0.0, "active": true}
	sim.update(DT, _inp())
	approx(float(sim.totem["progress"]), 3.0 * DT * 1.6, "progress += workers*dt*1.6")
	# inactive totem never grows
	sim.totem = {"progress": 10.0, "active": false}
	sim.update(DT, _inp())
	eq(float(sim.totem["progress"]), 10.0, "inactive totem frozen")
	# clamp at 100 (TS:1160 gate — no growth past 100)
	sim.totem = {"progress": 100.0, "active": true}
	sim.update(DT, _inp())
	eq(float(sim.totem["progress"]), 100.0, "totem progress clamps at 100")


func test_economy_festival_passive() -> void:
	# festival fires at chance dt*0.05 while food > 80 — pin it deterministically
	# by setting the stage rng to a state whose next draw is below the chance
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var t := _add_t(sim, 0.0, 60.0, "gather")
	sim.food = 200.0
	sim.wood = 200.0  # quota off → no interference
	var fire_state := -1
	var calm_state := -1
	var probe: Variant = RngLib.new_from(1)
	for s in range(1, 200000):
		probe.set_state(s)
		var v: float = probe.next()
		if fire_state < 0 and v < DT * 0.05:
			fire_state = s
		if calm_state < 0 and v > 0.5 and v < 0.6:
			calm_state = s
		if fire_state > 0 and calm_state > 0:
			break
	ok(fire_state > 0, "probe found a fire state")
	t["mood"] = "idle"
	sim.rng.set_state(fire_state)
	sim.update(DT, _inp())
	approx(float(ctx.karma), 0.01, "festival: karma +0.01")
	eq(float(sim.food), 195.0, "festival costs 5 food")
	eq(String(t["mood"]), "happy", "everyone mood happy")
	ok(_toasted(m["rec"], "The tribe feasts! (+harmony)"), "feast toast")
	# calm state → no fire
	var karma_before: float = float(ctx.karma)
	sim.food = 200.0
	sim.rng.set_state(calm_state)
	sim.update(DT, _inp())
	eq(float(ctx.karma), karma_before, "chance miss → no festival")
	eq(float(sim.food), 200.0, "no food spent")


# ---- tryBuildHut / tryTotem gates (TS:526-559) --------------------------------------

func test_try_build_hut_gates() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# wood < 40 → toast + NO cooldown arm (the A-rank fix, TS:529-534)
	sim.try_build_hut()
	ok(_toasted(m["rec"], "Need 40 wood for a hut"), "insufficient wood toast")
	eq(sim.huts.size(), 1, "no hut on failure")
	eq(float(sim.hutCd), 0.0, "cooldown NOT armed on the wood failure")
	# dead chief cannot build
	sim.wood = 40.0
	sim.deathFade = 0.5
	sim.try_build_hut()
	eq(sim.huts.size(), 1, "dead chief cannot build")
	sim.deathFade = 0.0
	# success: 40 wood → buildT 6 hut near the chief
	sim.try_build_hut()
	eq(sim.huts.size(), 2, "hut added")
	var h: Dictionary = sim.huts[1]
	eq(float(h["buildT"]), 6.0, "buildT 6 s")
	eq(float(h["hp"]), 100.0, "hut hp 100")
	eq(float(sim.wood), 0.0, "40 wood spent")
	eq(float(sim.hutCd), 2.0, "cooldown armed AFTER the checks")
	ok(absf(float(h["x"]) - float(sim.px)) <= 50.0, "hut x within chief ±50")
	eq(float(h["z"]), clampf(float(sim.pz) + 30.0, Z_MIN, Z_MAX), "hut z = pz+30 clamped")
	ok(_heard(m["rec"], "build"), "build audio 0.9")
	ok(_toasted(m["rec"], "Hut construction started"), "started toast")
	eq(m["rec"]["bursts"].size() > 0, true, "construction dust burst")
	# cooldown blocks the immediate retry (wood re-granted)
	sim.wood = 40.0
	sim.try_build_hut()
	eq(sim.huts.size(), 2, "hutCd blocks the second build")


func test_try_totem_gates() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# nobody left to raise it (TS:545-548)
	sim.try_totem()
	ok(_toasted(m["rec"], "No one left to raise the totem — keep your people alive"),
			"empty-tribe toast")
	eq(bool(sim.totem["active"]), false, "totem not started")
	_add_t(sim, 0.0, 60.0, "gather")
	_add_t(sim, 20.0, 60.0, "gather")
	# short on food (TS:549-552) — exact template with Math.round have-values
	sim.food = 99.0
	sim.wood = 80.0
	sim.try_totem()
	ok(_toasted(m["rec"], "Totem needs 100 food + 80 wood (have 99/80)"),
			"cost toast with have-values")
	eq(bool(sim.totem["active"]), false, "totem not started (food gate)")
	# short on wood
	sim.food = 100.0
	sim.wood = 79.0
	sim.try_totem()
	eq(bool(sim.totem["active"]), false, "totem not started (wood gate)")
	# success: −100 food −80 wood, banner + levelup (TS:553-558)
	sim.food = 130.0
	sim.wood = 90.0
	sim.try_totem()
	eq(bool(sim.totem["active"]), true, "totem active")
	eq(float(sim.totem["progress"]), 0.0, "progress starts 0")
	eq(float(sim.food), 30.0, "100 food spent")
	eq(float(sim.wood), 10.0, "80 wood spent")
	var banner: Dictionary = m["rec"]["banners"][0]
	eq(String(banner["title"]), "THE GREAT TOTEM", "banner title")
	eq(String(banner["subtitle"]), "your people carve the sky", "banner subtitle")
	eq(String(banner["kind"]), "reward", "banner kind reward")
	ok(_heard(m["rec"], "levelup"), "levelup audio")
	# already active → no-op (no double spend)
	sim.try_totem()
	eq(float(sim.food), 30.0, "no double spend while active")


# ---- assignRole + hotkeys (TS:495-502, 518-522) -------------------------------------

func test_assign_role_and_hotkeys() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_add_t(sim, 0.0, 60.0, "gather")
	_add_t(sim, 20.0, 60.0, "hunt")
	sim.assign_role("warrior")
	eq(String(sim.tribe[0]["role"]), "warrior", "role applied (0)")
	eq(String(sim.tribe[1]["role"]), "warrior", "role applied (1)")
	ok(_toasted(m["rec"], "Everyone: warrior"), "assign toast (TS:521)")
	ok(_heard(m["rec"], "click"), "click audio")
	# Digit2 → hunt for everyone (TS:496)
	sim.update(DT, _inp({"keys_pressed": ["Digit2"]}))
	eq(String(sim.tribe[0]["role"]), "hunt", "Digit2 assigns hunt")
	# KeyR builds a hut when affordable (TS:500)
	sim.wood = 40.0
	sim.update(DT, _inp({"keys_pressed": ["KeyR"]}))
	eq(sim.huts.size(), 2, "KeyR built a hut")
	# KeyT raises the totem when affordable (TS:502)
	sim.food = 100.0
	sim.wood = 80.0
	sim.update(DT, _inp({"keys_pressed": ["KeyT"]}))
	eq(bool(sim.totem["active"]), true, "KeyT raised the totem")


# ---- update shell: dayPhase / timers / HUD clicks (TS:278-318) ----------------------

func test_update_shell_day_phase() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.update(DT, _inp())
	approx(float(sim.dayPhase), fmod(0.2 + DT / 240.0, 1.0), "dayPhase += dt/240")
	approx(float(sim.time), DT, "time += dt")
	sim.dayPhase = 0.999999
	sim.update(DT, _inp())
	ok(float(sim.dayPhase) < 1.0, "dayPhase wraps mod 1")


func test_update_shell_timers_fn_runs_after_removal() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var fired: Array = []
	sim.after(0.05, func():
		fired.append(sim.timers.size())  # must ALREADY be removed (volcano seam)
	)
	sim.update(0.02, _inp())
	eq(fired.size(), 0, "timer not yet fired")
	sim.update(0.02, _inp())
	eq(fired.size(), 0, "timer not yet fired (0.04)")
	sim.update(0.02, _inp())
	eq(fired.size(), 1, "timer fired at 0.06")
	eq(int(fired[0]), 0, "fn ran AFTER removal (timers empty at call time)")


func test_update_shell_hud_click_dispatch() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.hudRects.append({"action": "hut", "r": {"x": 10.0, "y": 10.0, "w": 100.0, "h": 40.0}})
	sim.hudRects.append({"action": "totem", "r": {"x": 10.0, "y": 60.0, "w": 100.0, "h": 40.0}})
	# hut click with funds
	var inp := _inp({"clicked": true, "mx": 50.0, "my": 30.0})
	sim.wood = 40.0
	sim.update(DT, inp)
	eq(bool(inp["take_click"]), true, "click consumed (takeClick)")
	eq(sim.huts.size(), 2, "hut action dispatched → tryBuildHut")
	ok(_heard(m["rec"], "click"), "click audio")
	# totem click with nobody to raise it → the try_totem refusal path
	var inp2 := _inp({"clicked": true, "mx": 50.0, "my": 80.0})
	sim.tribe.clear()
	sim.food = 100.0
	sim.wood = 80.0
	sim.huts.remove_at(1)  # keep the world clean
	sim.update(DT, inp2)
	eq(bool(inp2["take_click"]), true, "totem click consumed")
	ok(_toasted(m["rec"], "No one left to raise the totem — keep your people alive"),
			"totem action dispatched → tryTotem")
	# click outside every rect → untouched
	var inp3 := _inp({"clicked": true, "mx": 900.0, "my": 900.0})
	sim.update(DT, inp3)
	eq(bool(inp3["take_click"]), false, "missed click not taken")
	# pre-taken click not re-dispatched
	var inp4 := _inp({"clicked": true, "take_click": true, "mx": 50.0, "my": 30.0})
	sim.wood = 40.0
	sim.update(DT, inp4)
	eq(sim.huts.size(), 1, "pre-taken click ignored")


# ---- on_exit → persist (TS:193) ----------------------------------------------------

func test_on_exit_persists() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_add_t(sim, 0.0, 60.0, "hunt")
	ok(not ctx.flags.has("tribeState"), "nothing persisted before exit")
	sim.on_exit()
	ok(ctx.flags.has("tribeState"), "on_exit persists the village")


# ---- determinism + sanity -----------------------------------------------------------

func _village_snapshot(sim: Variant) -> Array:
	var tribe_snap: Array = []
	for t in sim.tribe:
		tribe_snap.append([snappedf(float(t["x"]), 1e-6), snappedf(float(t["z"]), 1e-6),
				snappedf(float(t["hp"]), 1e-6), snappedf(float(t["gait"]), 1e-6),
				String(t["role"]),
				String(t["carrying"]) if t["carrying"] != null else ""])
	return [snappedf(float(sim.px), 1e-6), snappedf(float(sim.pz), 1e-6),
			snappedf(float(sim.food), 1e-6), snappedf(float(sim.wood), 1e-6),
			snappedf(float(sim.dayPhase), 1e-9), snappedf(float(sim.gait), 1e-6),
			tribe_snap, sim.rng.state()]


func test_determinism_two_sims_identical() -> void:
	var runs: Array = []
	for r in 2:
		var m := _mk_sim(SEED)
		var sim: Variant = m["sim"]
		sim.on_enter()
		for i in 240:
			var over: Dictionary = {
				"down": true,
				"wx": sin(float(i) * 0.05) * 800.0,
				"wy": cos(float(i) * 0.05) * 100.0 * Z_TO_Y + 100.0,
				"keys_held": ["KeyD"] if i % 60 < 30 else [],
			}
			sim.update(DT, _inp(over))
		runs.append(_village_snapshot(sim))
	eq(str(runs[0]), str(runs[1]), "two seeded runs identical (founder village)")


func test_headless_sanity_long_run() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	sim.on_enter()
	for i in 1200:
		var pressed: Array = []
		if i == 100:
			pressed = ["Digit3"]       # everyone wars
		if i == 200:
			pressed = ["KeyR"]         # build (wood 30 → refusal path)
		if i == 300:
			pressed = ["KeyT"]         # totem refusal path
		if i == 400:
			pressed = ["Digit1"]       # everyone gathers
		sim.update(DT, _inp({"keys_pressed": pressed, "down": i % 2 == 0,
				"wx": sin(float(i) * 0.03) * 600.0, "wy": cos(float(i) * 0.03) * 100.0}))
	ok(is_finite(float(sim.food)) and float(sim.food) >= 0.0, "food sane")
	ok(is_finite(float(sim.wood)) and float(sim.wood) >= 0.0, "wood sane")
	ok(is_finite(float(sim.px)) and is_finite(float(sim.pz)), "chief position sane")
	ok(is_finite(float(ctx.karma)), "karma sane")
	ok(is_finite(float(sim.totem["progress"])), "totem sane")
	for t in sim.tribe:
		ok(is_finite(float(t["hp"])) and is_finite(float(t["x"])), "tribesman sane")
		ok(is_finite(float(t["stats"]["speed"])), "tribesman stats sane")


# ---- task 2: raids, beast, fires, transitions ---------------------------------------
# (TS:327-339 raid clock, 561-584 launch, 709-717 war graves, 858-879 camp
# assault, 881-935 + 1004-1021 beast, 937-993 fires/lightning, 1023-1039
# chaos raid seam, 381-409 fall/victory)

# A parallel branch replayed PAST the constructor's full draw sequence (120
# tree + 78 bush + 4 rival draws + the chaos-scheduler branch draw) — its
# next draws line up 1:1 with the sim's post-construction stream.
func _post_ctor_pr(seed_v: int = SEED) -> Variant:
	var pr: Variant = Ctx.new(seed_v).rng.branch()
	for i in 30:
		pr.range(-WORLD_HALF, WORLD_HALF)
		pr.range(Z_MIN, Z_MAX)
		pr.range(4.0, 9.0)
		pr.range(0.0, 9.0)
	for i in 26:
		pr.range(-WORLD_HALF, WORLD_HALF)
		pr.range(Z_MIN, Z_MAX)
		pr.range(3.0, 7.0)
	for i in 2:
		pr.range(1300.0, 2000.0)
		pr.range(-120.0, 160.0)
	pr.branch()  # the ChaosScheduler child seed (TribeStage.ts:135)
	return pr


# Register the transition-recording hooks the fall/victory paths fire
# (missing hook keys are silent no-ops, so tests opt in).
func _watch_transitions(sim: Variant, rec: Dictionary) -> void:
	rec["go_to"] = []
	rec["saves"] = []
	sim._hooks["go_to"] = func(stage, data): rec["go_to"].append([stage, data])
	sim._hooks["save_all"] = func(): rec["saves"].append(1)


func _toasted_count(rec: Dictionary, fragment: String) -> int:
	var n := 0
	for t in rec["toasts"]:
		if String(t[0]).find(fragment) >= 0:
			n += 1
	return n


func _banners_with(rec: Dictionary, fragment: String) -> int:
	var n := 0
	for b in rec["banners"]:
		if String(b["title"]).find(fragment) >= 0:
			n += 1
	return n


func test_raid_clock_cadence_and_first_raid_hint() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	# tick 1 from a fresh (no on_enter) sim: the ONLY rng draws are the raid
	# clock's reset roll + the raid launch — pin them against a parallel
	# branch replayed past the constructor (TS:331-338).
	sim.raidTimer = 0.0001
	sim.update(DT, _inp())
	var pr: Variant = _post_ctor_pr()
	eq(float(sim.raidTimer), 80.0 + pr.range(-15.0, 25.0), "raidTimer = 80 + rng(-15,25) (TS:332)")
	eq(_banners_with(rec, "RAIDS!"), 1, "raid banner fired (TS:581)")
	eq(bool(sim.raidActive), true, "raidActive true (TS:583)")
	ok(_heard(rec, "alarm"), "alarm audio (TS:582)")
	eq(String(ctx.flags["firstRaidHint"]), "seen", "firstRaidHint latched (TS:335)")
	eq(_toasted_count(rec, "Raiders rally"), 1, "first-raid hint toasted")
	# the hint NEVER re-fires (TS:334 gate)
	sim.raidTimer = 0.0001
	sim.update(DT, _inp())
	eq(_toasted_count(rec, "Raiders rally"), 1, "hint fires only on the first raid")
	eq(_banners_with(rec, "RAIDS!"), 2, "second raid still banners")


func test_raid_clock_peaceful_gates() -> void:
	# peaceful + hutless: the clock never fires and the timer floors at 30
	var m := _mk_sim(SEED, {}, "peaceful")
	var sim: Variant = m["sim"]
	sim.huts.clear()
	sim.raidTimer = 0.0001
	sim.update(DT, _inp())
	eq(float(sim.raidTimer), 30.0, "peaceful hutless floors raidTimer at 30 (TS:330)")
	eq(_banners_with(m["rec"], "RAIDS!"), 0, "no raid while peaceful hutless")
	eq(bool(sim.raidActive), false, "raidActive untouched")
	# a >30 timer is preserved (Math.max, not a reset)
	sim.raidTimer = 50.0
	sim.update(DT, _inp())
	eq(float(sim.raidTimer), 50.0 - DT, "existing timer preserved")
	# peaceful WITH a hut: raids fire at half cadence (+40, TS:333)
	var m2 := _mk_sim(SEED, {}, "peaceful")
	var sim2: Variant = m2["sim"]
	sim2.raidTimer = 0.0001
	sim2.update(DT, _inp())
	var pr: Variant = _post_ctor_pr()
	eq(float(sim2.raidTimer), 80.0 + pr.range(-15.0, 25.0) + 40.0,
			"peaceful reset = 80 + roll + 40")
	eq(_banners_with(m2["rec"], "RAIDS!"), 1, "peaceful raids once a hut stands")


func test_raid_party_wave_cap_and_genome() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.raidTimer = 0.0001
	sim.update(DT, _inp())
	# full parallel replay of the launch (TS:561-584): clock roll → pick →
	# wave roll → per-warrior x/z
	var pr: Variant = _post_ctor_pr()
	pr.range(-15.0, 25.0)  # clock reset roll
	var idx := floori(pr.next() * 2.0)  # rng.pick(rivals)
	var waven := 2 + floori(pr.range(0.0, 2.0))  # wave 2 + floor(rng(0,2))
	var rivals_ref: Array = _expected_world(SEED)["rivals"]
	eq(sim.rivalWarriors.size(), waven, "wave size = 2 + floor(rng(0,2)) (TS:567-568)")
	eq(_banners_with(rec, "RAIDS!"), 1, "one raid banner")
	eq(String(rec["banners"][0]["title"]), String(["GNASH", "RUK"][idx]) + " RAIDS!",
			"banner names the picked rival")
	for i_w in waven:
		var w: Dictionary = sim.rivalWarriors[i_w]
		eq(float(w["x"]), float(rivals_ref[idx]["x"]) + pr.range(-60.0, 60.0),
				"warrior x spawn offset (TS:571)")
		eq(float(w["z"]), float(rivals_ref[idx]["z"]) + pr.range(-40.0, 40.0),
				"warrior z spawn offset (TS:572)")
		eq(float(w["hp"]), 60.0, "warrior hp 60 (TS:574)")
		eq(String(w["state"]), "march", "warrior state march (TS:578)")
		eq(float(w["genome"]["hue"]), 5.0, "raider hue 5 (TS:575)")
		eq(String(w["genome"]["diet"]), "carnivore", "raider carnivore")
		eq(float(w["genome"]["spikes"]), 3.0, "raider spikes 3")
		eq(float(w["genome"]["jaw"]), 3.0, "raider jaw 3")


func test_raid_party_cap_five() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	for i in 5:
		sim.rivalWarriors.append(_warrior_at(1500.0 + float(i) * 10.0, 0.0))
	sim.raidTimer = 0.0001
	sim.update(DT, _inp())
	eq(sim.rivalWarriors.size(), 5, "party capped at 5 (TS:565-566)")
	eq(_banners_with(rec, "RAIDS!"), 0, "no banner when the cap refuses")
	eq(bool(sim.raidActive), false, "raidActive untouched by a refused launch")


func test_raid_skips_dead_rivals() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	for r in sim.rivals:
		r["hp"] = 0.0
	sim.raidTimer = 0.0001
	sim.update(DT, _inp())
	eq(sim.rivalWarriors.size(), 0, "no warriors from a dead rival (TS:563)")
	eq(_banners_with(rec, "RAIDS!"), 0, "no banner")
	eq(bool(sim.raidActive), false, "raidActive untouched")


func test_siege_destroys_hut_and_floors_raid_timer() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.raidTimer = 50.0
	# hut at (0, 80): dist 31.6 < 40 — but 42.4 from the chief (0, 60), so the
	# raid-touch block never flips the marcher to 'fight' before the siege
	var w: Dictionary = _warrior_at(30.0, 90.0)
	sim.rivalWarriors.append(w)
	sim.huts[0]["hp"] = 0.05
	sim.update(DT, _inp())
	eq(sim.huts.size(), 0, "hut destroyed (TS:688-694)")
	eq(float(sim.raidTimer), 120.0 - DT, "raidTimer floored at 120 (TS:690)")
	eq(_banners_with(rec, "A HUT BURNS"), 1, "A HUT BURNS banner")
	ok(_heard(rec, "boom"), "boom audio")
	eq(String(w["state"]), "flee", "empty village flips the war party to flee (TS:699-701)")
	eq(bool(sim.raidActive), false, "no raid launched — raidActive stays false")


func test_warrior_flee_home_slip() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# a fleeing warrior within 90 of home slips away (TS:702-705)
	var w: Dictionary = _warrior_at(float(sim.rivals[0]["x"]), float(sim.rivals[0]["z"]))
	w["state"] = "flee"
	sim.rivalWarriors.append(w)
	sim.update(DT, _inp())
	eq(sim.rivalWarriors.size(), 0, "flee + home < 90 → slipped away")
	# a marching party with NOTHING left to siege goes home (TS:696-701)
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var w2: Dictionary = _warrior_at(100.0, 100.0)
	sim2.rivalWarriors.append(w2)
	sim2.huts.clear()  # tribe already empty without on_enter
	sim2.update(DT, _inp())
	eq(String(w2["state"]), "flee", "hutless + tribeless → state flee")


func test_camp_assault_rewards_and_karma() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	var r: Dictionary = sim.rivals[0]
	_add_t(sim, float(r["x"]), float(r["z"]), "warrior")
	r["hp"] = 0.05
	sim.update(DT, _inp())
	eq(_banners_with(rec, "JOINS YOUR PEOPLE"), 1, "rival absorbed (TS:870-876)")
	eq(String(rec["banners"][0]["title"]), "GNASH JOINS YOUR PEOPLE", "banner names the rival")
	ok(_heard(rec, "levelup"), "levelup audio")
	eq(float(sim.food), 120.0, "food +60 (TS:873)")
	eq(float(sim.wood), 70.0, "wood +40 (TS:874)")
	approx(float(ctx.karma), -0.05, "karma -0.05 (TS:875)")
	ok(float(r["hp"]) <= 0.0, "rival dead")
	eq(float(r["anger"]), DT * 0.1, "anger += dt*0.1 (TS:866)")
	# non-warriors do not assault
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var r2: Dictionary = sim2.rivals[0]
	_add_t(sim2, float(r2["x"]), float(r2["z"]), "gather")
	sim2.update(DT, _inp())
	eq(float(r2["hp"]), 100.0, "gatherers never chip the camp (TS:862-863)")
	eq(float(r2["anger"]), 0.0, "anger untouched")


func test_war_graves_combo_pays_once_per_raid() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	ctx.world["comboFired"] = {"war_graves": true}
	sim.raidActive = true
	sim.update(DT, _inp())
	eq(int(ctx.dna), 55, "war graves +15 DNA (TS:713-715)")
	eq(_toasted_count(rec, "War graves yield DNA."), 1, "reward toast")
	eq(bool(sim.raidActive), false, "raidActive cleared (TS:712)")
	sim.update(DT, _inp())
	eq(int(ctx.dna), 55, "one payment per raid instance")
	# combo off: the raid still closes, no DNA
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var ctx2: Variant = m2["ctx"]
	sim2.raidActive = true
	sim2.update(DT, _inp())
	eq(bool(sim2.raidActive), false, "raid closes without the combo")
	eq(int(ctx2.dna), 40, "no DNA without the combo")
	eq(_toasted_count(m2["rec"], "War graves"), 0, "no toast without the combo")
	# a live war party holds the raid open
	var m3 := _mk_sim()
	var sim3: Variant = m3["sim"]
	sim3.raidActive = true
	sim3.rivalWarriors.append(_warrior_at(1500.0, 0.0))
	sim3.update(DT, _inp())
	eq(bool(sim3.raidActive), true, "party in the field keeps raidActive")


func test_beast_spawn_pin() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.spawn_beast()
	var pr: Variant = _post_ctor_pr()
	var a: float = pr.next() * TAU
	var b: Dictionary = sim.beast
	eq(float(b["hp"]), 420.0, "beast hp 420 (TS:1018)")
	eq(float(b["x"]), cos(a) * 900.0, "x = px + cos(a)*900 (TS:1016)")
	eq(float(b["z"]), clampf(60.0 + sin(a) * 300.0, Z_MIN, Z_MAX), "z = clamp(pz + sin(a)*300) (TS:1017)")
	var g: Dictionary = b["genome"]
	eq(float(g["size"]), 2.1, "beast size 2.1 (TS:1013)")
	eq(String(g["diet"]), "carnivore", "beast carnivore")
	eq(float(g["jaw"]), 5.0, "beast jaw 5")
	eq(float(g["spikes"]), 4.0, "beast spikes 4")
	eq(float(g["horns"]), 3.0, "beast horns 3")
	eq(float(g["hue"]), 300.0, "beast hue 300")
	eq(String(g["coat"]), "plates", "beast coat plates")
	eq(float(g["eyes"]), 4.0, "beast eyes 4")
	# despawn seam (TS:1004-1010)
	sim.despawn_beast()
	eq(sim.beast, null, "despawn clears the beast")
	ok(_toasted(m["rec"], "wanders away"), "despawn toast")
	sim.despawn_beast()
	eq(_toasted_count(m["rec"], "wanders away"), 1, "despawn is a no-op without a beast")


func test_beast_march_siege_and_chief_fallback() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# march: x rate 90, z rate 70 (TS:888-889)
	sim.beast = {"x": 500.0, "z": -150.0, "hp": 420.0, "genome": {}}
	sim.update(DT, _inp())
	var dx: float = (0.0 - 500.0)
	var dz: float = (80.0 - (-150.0))
	var d: float = maxf(1.0, sqrt(dx * dx + dz * dz))
	eq(float(sim.beast["x"]), 500.0 + (dx / d) * 90.0 * DT, "beast x rate 90")
	eq(float(sim.beast["z"]), -150.0 + (dz / d) * 70.0 * DT, "beast z rate 70")
	# siege: hp -= 6*dt, destruction banner (TS:890-896)
	sim.beast = {"x": 0.0, "z": 80.0, "hp": 420.0, "genome": {}}
	sim.huts[0]["hp"] = 0.05
	sim.update(DT, _inp())
	eq(sim.huts.size(), 0, "beast destroys the hut")
	eq(_banners_with(rec, "THE BEAST DESTROYS A HUT"), 1, "destruction banner")
	ok(_heard(rec, "boom"), "boom audio")
	# hutless: the beast prowls toward the CHIEF (TS:885)
	sim.beast = {"x": 500.0, "z": 60.0, "hp": 420.0, "genome": {}}
	sim.update(DT, _inp())
	eq(float(sim.beast["x"]), 500.0 - 90.0 * DT, "chief-fallback march (dx/d = 1)")


func test_beast_fighter_dps_and_gore_gate() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# fighters 9/s each + chief 14/s (TS:899-902)
	sim.beast = {"x": 0.0, "z": 60.0, "hp": 420.0, "genome": {}}
	_add_t(sim, 0.0, 60.0, "gather")
	sim.update(DT, _inp())
	eq(float(sim.beast["hp"]), 420.0 - (9.0 + 14.0) * DT, "dps = fighters*9 + chief 14")
	# the gore roll is chief-proximity-gated (A08) — drive it deterministically
	sim.beast["hp"] = 100000.0  # test seam: keep it alive for the drive
	var gored := false
	for i in 5000:
		sim.update(DT, _inp())
		if sim.deathFade > 0.0:
			gored = true
			break
	ok(gored, "beast gored the chief (chance dt*0.5, TS:906)")
	eq(String(sim.lastDeathCause), "the great beast gored you", "death cause recorded")
	# invuln blocks the gore (TS:906 gate)
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	sim2.beast = {"x": 0.0, "z": 60.0, "hp": 100000.0, "genome": {}}
	sim2.invulnT = 99999.0
	var gored2 := false
	for i in 1500:
		sim2.update(DT, _inp())
		if sim2.deathFade > 0.0:
			gored2 = true
			break
	eq(gored2, false, "invulnT blocks the gore")


func test_beast_death_rewards() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	sim.beast = {"x": 0.0, "z": 60.0, "hp": 0.05, "genome": {}}
	_add_t(sim, 0.0, 60.0, "gather")  # a fighter makes dps > 0
	sim.update(DT, _inp())
	eq(sim.beast, null, "beast falls (TS:914-921)")
	eq(_banners_with(rec, "THE GREAT BEAST FALLS"), 1, "falls banner")
	eq(float(sim.food), 120.0, "feast +60 food (TS:917)")
	eq(int(ctx.dna), 90, "+50 DNA (TS:918)")
	ok(_heard(rec, "levelup"), "levelup audio")


func test_fires_decay_extinguish_and_splice() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.fires.append({"x": 0.0, "z": 0.0, "ttl": 5.0, "spread": 999.0})
	sim.update(DT, _inp())
	eq(float(sim.fires[0]["ttl"]), 5.0 - DT, "ttl -= dt (TS:940)")
	# two tribesmen nearby: -4*dt each (TS:942-943)
	_add_t(sim, 0.0, 0.0, "gather")
	_add_t(sim, 10.0, 0.0, "gather")
	sim.update(DT, _inp())
	eq(float(sim.fires[0]["ttl"]), 5.0 - 2.0 * DT - 8.0 * DT,
			"nearby tribesmen extinguish -4*dt each")
	# splice at 0
	sim.fires[0]["ttl"] = 0.001
	sim.update(DT, _inp())
	eq(sim.fires.size(), 0, "fire splices out at ttl <= 0 (TS:958)")


func test_fires_smoke_and_spread_ignite() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# smoke fx at chance dt*10 (TS:944-950)
	sim.fires.append({"x": 0.0, "z": 0.0, "ttl": 100.0, "spread": 999.0})
	var smoked := false
	for i in 300:
		sim.update(DT, _inp())
		if not rec["spawns"].is_empty():
			smoked = true
			break
	ok(smoked, "smoke fx spawned")
	var s: Dictionary = rec["spawns"][0]
	eq(String(s["kind"]), "smoke", "smoke kind")
	eq(String(s["color"]), "rgba(255,150,60,0.6)", "smoke color")
	# spread: first unburnt tree within 90 ignites (TS:952-957)
	sim.trees[0]["x"] = 0.0
	sim.trees[0]["z"] = 0.0
	sim.fires[0]["spread"] = 0.001
	var spread := false
	for i in 300:
		sim.update(DT, _inp())
		if sim.fires.size() >= 2:
			spread = true
			break
	ok(spread, "fire spread to a tree")
	eq(float(sim.trees[0]["burn"]), 8.0 - DT,
			"tree burn 8, decayed one tick by the burnout block (TS:964 + 1127-1131)")
	eq(float(sim.fires[1]["ttl"]), 10.0, "new fire ttl 10 (TS:965)")
	eq(float(sim.fires[1]["spread"]), 8.0, "new fire spread 8")
	ok(_heard(rec, "fire"), "fire audio (TS:966)")


func test_fire_spread_finds_nothing_and_ignite_guards() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# every tree parked far away — the spread roll hits but ignites nothing
	for tr in sim.trees:
		tr["x"] = -2400.0
	sim.fires.append({"x": 2400.0, "z": 0.0, "ttl": 100.0, "spread": 0.001})
	var rolled := false
	for i in 300:
		sim.update(DT, _inp())
		if float(sim.fires[0]["spread"]) >= 8.0:
			rolled = true
			break
	ok(rolled, "spread roll consumed, timer reset (TS:954)")
	eq(sim.fires.size(), 1, "no ignition without a tree within 90")
	# ignite_tree guards: stumps do not burn, burning trees do not double (TS:963)
	var stump := {"x": 0.0, "z": 0.0, "wood": 0.0, "burn": 0.0, "seed": 0.0}
	sim.trees.append(stump)
	sim.ignite_tree(stump)
	eq(sim.fires.size(), 1, "stump does not burn")
	eq(float(stump["burn"]), 0.0, "stump burn untouched")
	var burning := {"x": 10.0, "z": 0.0, "wood": 5.0, "burn": 8.0, "seed": 0.0}
	sim.trees.append(burning)
	sim.ignite_tree(burning)
	eq(sim.fires.size(), 1, "already-burning tree does not double")


func test_lightning_empty_targets_and_hut_branch() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# no targets: crackles only (TS:974-977)
	for tr in sim.trees:
		tr["wood"] = 0.0
	sim.huts.clear()
	sim.lightning_strike()
	eq(_toasted_count(rec, "storm crackles"), 1, "empty-targets toast")
	eq(rec["shakes"].size(), 0, "no shake without a strike")
	# hut branch: hp -35 per strike, destruction at 0 (TS:979-986)
	sim.huts.append({"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0, "pop": 0.0, "buildT": 0.0})
	sim.lightning_strike()
	eq(float(sim.huts[0]["hp"]), 65.0, "hut hp -35 (TS:982)")
	eq(rec["shakes"].size(), 1, "shake recorded")
	eq(rec["shakes"][0], [6.0, 0.4], "shake 6/0.4 (TS:990)")
	ok(_heard(rec, "zap"), "zap audio (TS:991)")
	eq(_toasted_count(rec, "Lightning! Fire spreads"), 1, "lightning toast (TS:992)")
	sim.lightning_strike()
	eq(float(sim.huts[0]["hp"]), 30.0, "hut hp -35 again")
	sim.lightning_strike()
	eq(sim.huts.size(), 0, "LIGHTNING SPLITS A HUT destroys it")
	eq(_banners_with(rec, "LIGHTNING SPLITS A HUT"), 1, "destruction banner (TS:985)")


func test_lightning_tree_branch_pick_pin() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# single candidate → deterministic ignite (TS:987-988)
	for i in sim.trees.size():
		if i != 3:
			sim.trees[i]["wood"] = 0.0
	sim.huts.clear()
	sim.lightning_strike()
	eq(float(sim.trees[3]["burn"]), 8.0, "the only candidate ignited")
	eq(sim.fires.size(), 1, "one fire from the strike")
	eq(float(sim.fires[0]["x"]), float(sim.trees[3]["x"]), "fire sits at the tree")
	ok(_heard(rec, "fire"), "fire audio")
	# multi-candidate pick pinned bit-exact against the parallel stream
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	sim2.huts.clear()
	sim2.lightning_strike()
	var pr: Variant = _post_ctor_pr()
	var idx := floori(pr.next() * 30.0)  # rng.pick over the 30 unburnt trees
	eq(float(sim2.trees[idx]["burn"]), 8.0, "picked tree (stream-pinned index) ignited")
	eq(float(sim2.fires[0]["x"]), float(sim2.trees[idx]["x"]), "fire at the picked tree")


func test_timer_same_tick_order_is_reverse() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var order: Array = []
	sim.after(0.05, func(): order.append("a"))
	sim.after(0.05, func(): order.append("b"))
	for i in 6:
		sim.update(DT, _inp())
	eq(order, ["b", "a"], "same-tick timers drain last-added-first (TS:306 reverse loop)")


func test_fall_path_blob_delete_and_go_to() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	_watch_transitions(sim, rec)
	ctx.flags["tribeState"] = "{\"food\":50,\"huts\":[],\"tribe\":[]}"
	sim.huts.clear()
	# tick 1: the fall banner arms the timer (TS:382-386)
	sim.update(DT, _inp())
	eq(float(sim.fallenT), 0.0001 + DT, "fallenT armed at 0.0001 then += dt")
	eq(_banners_with(rec, "THE TRIBE HAS FALLEN"), 1, "fall banner")
	ok(_heard(rec, "die"), "die audio")
	ok(ctx.flags.has("tribeState"), "blob not yet deleted")
	# drive past 4 s: latch, delete, save, go_to (TS:389-397)
	for i in 300:
		sim.update(DT, _inp())
	eq(bool(sim.fallFired), true, "fallFired latch")
	eq(rec["go_to"], [["creature", {"title": "BACK TO THE WILDS",
			"sub": "gather your strength and found a new people"}]], "go_to('creature') payload (TS:396)")
	eq(rec["saves"].size(), 1, "save_all fired once")
	eq(ctx.flags.has("tribeState"), false, "dead blob deleted (TS:394)")
	eq(_banners_with(rec, "THE TRIBE HAS FALLEN"), 1, "banner fires once")
	for i in 10:
		sim.update(DT, _inp())
	eq(rec["go_to"].size(), 1, "go_to latched")
	eq(rec["saves"].size(), 1, "save_all latched")
	# the corpse guard keeps save_all from resurrecting the blob (TS:200)
	sim.persist_state()
	eq(ctx.flags.has("tribeState"), false, "persist never re-writes a corpse")


func test_victory_path_latches() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	_watch_transitions(sim, rec)
	# progress < 100 never arms the timer (TS:401)
	sim.totem["progress"] = 99.9
	for i in 200:
		sim.update(DT, _inp())
	eq(float(sim.victoryT), 0.0, "victoryT only accumulates at progress >= 100")
	eq(rec["go_to"].size(), 0, "no transition below 100")
	# at 100: victoryT accrues, transition after 2.5 s (TS:401-408)
	sim.totem["progress"] = 100.0
	sim.update(DT, _inp())
	eq(float(sim.victoryT), DT, "victoryT += dt")
	eq(rec["go_to"].size(), 0, "not before 2.5 s")
	for i in 300:
		sim.update(DT, _inp())
	eq(rec["go_to"], [["civ", {"title": "THE FIRST CITY",
			"sub": "drums become laws; laws become empires"}]], "go_to('civ') payload (TS:407)")
	eq(rec["saves"].size(), 1, "save_all before the transition")
	ok(_heard(rec, "ascend"), "ascend audio")
	eq(bool(sim.victoryFired), true, "victoryFired latch")
	for i in 10:
		sim.update(DT, _inp())
	eq(rec["go_to"].size(), 1, "victory latched")


func test_raids_blocked_pause_and_now() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	eq(bool(sim.raids_blocked()), false, "normal never blocked (TS:1025)")
	ctx.difficulty = "peaceful"
	sim.huts.clear()
	eq(bool(sim.raids_blocked()), true, "peaceful + hutless blocked")
	sim.huts.append({"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0, "pop": 0.0, "buildT": 0.0})
	eq(bool(sim.raids_blocked()), false, "a standing hut unblocks")
	# pauseRaids floors the clock (TS:1030-1032)
	sim.raidTimer = 10.0
	sim.pause_raids(45.0)
	eq(float(sim.raidTimer), 45.0, "paused to 45")
	sim.pause_raids(5.0)
	eq(float(sim.raidTimer), 45.0, "shorter pause never shortens")
	# launchRivalRaidNow refuses when blocked (TS:1034-1039)
	sim.huts.clear()
	sim.launch_rival_raid_now()
	eq(sim.rivalWarriors.size(), 0, "blocked launch refuses")
	eq(_banners_with(m["rec"], "RAIDS!"), 0, "no banner when refused")
	sim.huts.append({"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0, "pop": 0.0, "buildT": 0.0})
	sim.launch_rival_raid_now()
	ok(sim.rivalWarriors.size() >= 1, "unblocked launch raids")
	eq(_banners_with(m["rec"], "RAIDS!"), 1, "banner on the real launch")
