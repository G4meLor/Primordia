# Tests for game/cell/cell_sim.gd — the cell stage sim core: state structs,
# spawn tables, player physics/interactions, pellet economy, zones, death.
# TS source: Spore src/game/cell/CellStage.ts (frozen). Path-based extends +
# preload-by-path: class_name globals don't resolve in `-s` mode on a clone.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const RngLib := preload("res://src/core/rng.gd")
const WorldGenome := preload("res://src/evo/world_genome.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const CellSim := preload("res://src/game/cell/cell_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE
const WORLD_R := 2400.0


# ---- fixtures ------------------------------------------------------------------

# Builds a GameContext (explicit seed), the stage rng branch, a recording
# hooks set, and the sim. genome_mods merge into ctx.genome BEFORE sim
# construction (pStats is a construction-time snapshot, TS-verbatim).
func _mk_sim(seed_v: int = SEED, genome_mods: Dictionary = {}) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	if not genome_mods.is_empty():
		var g: Dictionary = ctx.genome
		g.merge(genome_mods, true)
	var rec: Dictionary = {
		"toasts": [], "banners": [], "floats": [], "audio": [], "shakes": [],
		"bursts": [], "spawns": [], "notes": [], "events": [],
		"pointer": 0, "shore": 0, "saves": 0,
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(playtime): rec["notes"].append(playtime),
		"set_cursor_pointer": func(): rec["pointer"] += 1,
		"context_event": func(ev, data): rec["events"].append([ev, data]),
		"shore_travel": func(): rec["shore"] += 1,
		"game_save_all": func(): rec["saves"] += 1,
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CellSim.new(ctx, rng, hooks)
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


func _snap(sim: Variant) -> Dictionary:
	var ents: Array = []
	for e in sim.ents:
		ents.append([e["eid"], snappedf(e["x"], 1e-4), snappedf(e["y"], 1e-4),
				roundi(e["hp"]), e["speciesId"]])
	var pel: Array = []
	for p in sim.pellets:
		pel.append([snappedf(p["x"], 1e-4), snappedf(p["y"], 1e-4), p["kind"]])
	var kelp: Array = []
	for k in sim.kelp:
		kelp.append([snappedf(k["x"], 1e-9), snappedf(k["y"], 1e-9),
				snappedf(k["len"], 1e-9), snappedf(k["seed"], 1e-9)])
	return {
		"px": snappedf(sim.px, 1e-4), "py": snappedf(sim.py, 1e-4),
		"php": snappedf(sim.php, 1e-6),
		"pvx": snappedf(sim.pvx, 1e-4), "pvy": snappedf(sim.pvy, 1e-4),
		"ents": ents, "pellets": pel, "kelp": kelp,
		"rng": sim.rng.state(),
	}


func _heard(rec: Dictionary, name: String) -> bool:
	for a in rec["audio"]:
		if a[0] == name:
			return true
	return false


# ---- constructor bootstrap / seedEcology ----------------------------------------


func test_boot_state_and_structs() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ok(ctx.eco != null, "eco bootstrapped onto ctx when absent")
	ok(sim.eco == ctx.eco, "sim eco is the ctx eco")
	eq(sim.kelp.size(), 40, "40 kelp strands")
	for k in sim.kelp:
		var r := sqrt(k["x"] * k["x"] + k["y"] * k["y"])
		ok(r >= 300.0 - 1e-6 and r <= WORLD_R * 0.95 + 1e-6, "kelp radius 300..WORLD_R*0.95")
		ok(k["len"] >= 40.0 and k["len"] <= 110.0, "kelp len 40..110")
		ok(k["seed"] >= 0.0 and k["seed"] <= 10.0, "kelp seed 0..10")
	eq(sim.pellets.size(), 30, "30 starter pellets")
	for p in sim.pellets:
		eq(p["kind"], "plant", "starter pellets are plant")
		eq(p["val"], 2, "plant pellet val 2")
		eq(p["ttl"], 40, "plant pellet ttl 40")
	eq(sim.ents.size(), 0, "no ents at boot")
	eq(sim.zones.size(), 0, "no zones at boot")
	approx(sim.invuln, 3.0, "spawn invuln 3")
	# default genome stats: max_hp = 30 + 20 + 0 + 3 = 53
	approx(sim.pmaxHp, 53.0, "pmaxHp from computeCellStats")
	approx(sim.php, sim.pmaxHp, "arrive at full hp")
	approx(sim.player_radius(), 14.0, "playerRadius 14*size*(1+nutrition*0.35)")
	# debugState shape mirrors TS
	var ds: Dictionary = sim.debug_state()
	ok(ds.has_all(["px", "py", "php", "ents", "pellets"]), "debugState keys TS-verbatim")
	# roster: 7 archetypes + world bonuses, pop 4..9, all discovered
	var weights: Dictionary = WorldGenome.archetype_weights(ctx.world)
	var expected := 7
	if float(weights.get("titan", 0.0)) >= 1.0:
		expected += 1
	if float(weights.get("swarm", 0.0)) >= 1.0:
		expected += 1
	eq(ctx.eco.species.size(), expected, "roster = 7 archetypes + titan/swarm bonuses")
	var sizes := {}
	for sp in ctx.eco.species:
		ok(float(sp["pop"]) >= 4.0 and float(sp["pop"]) <= 9.0, "add_species pop 4..9")
		ok(not String(sp["name"]).is_empty(), "species named")
		var key: String = Ctx.genome_hash_lite(sp["genome"])
		ok(ctx.bestiary.has(key), "every species discovered at seed")
		if ctx.bestiary.has(key):
			eq(ctx.bestiary[key]["name"], sp["name"], "bestiary name matches")
		sizes[float(sp["genome"]["size"])] = true
	# archetype sizes survive the diet dial untouched
	for s in [0.7, 1.0, 1.3, 0.8, 1.8, 0.6, 1.1]:
		ok(sizes.has(s), "archetype size %.1f present" % s)
	# world-weighted bonuses appended AFTER the roster when the weights ask
	if float(weights.get("titan", 0.0)) >= 1.0:
		var found := false
		for sp in ctx.eco.species:
			if float(sp["genome"]["size"]) == 2.2 and int(sp["genome"]["hue"]) == 330:
				found = true
		ok(found, "titan bonus species (size 2.2, hue 330)")
	if float(weights.get("swarm", 0.0)) >= 1.0:
		var found2 := false
		for sp in ctx.eco.species:
			# size 0.55 hits the genome floor in add_species's clampGenome
			# (TS-verbatim: TS addSpecies clamps too) → 0.6; hue survives
			if float(sp["genome"]["size"]) == 0.6 and int(sp["genome"]["hue"]) == 210:
				found2 = true
		ok(found2, "swarm bonus species (size 0.55 clamped to 0.6, hue 210)")


func test_bootstrap_deterministic_per_seed() -> void:
	var a := _mk_sim(1234)
	var b := _mk_sim(1234)
	var ea: Array = a["ctx"].eco.species
	var eb: Array = b["ctx"].eco.species
	eq(ea.size(), eb.size(), "same seed → same roster size")
	for i in ea.size():
		eq(ea[i]["name"], eb[i]["name"], "species name %d deterministic" % i)
		approx(float(ea[i]["pop"]), float(eb[i]["pop"]), "pop %d deterministic" % i, 1e-9)
	eq(_snap(a["sim"])["kelp"], _snap(b["sim"])["kelp"], "kelp deterministic")
	var c := _mk_sim(1235)
	ok(String(a["ctx"].eco.species[0]["name"]) != String(c["ctx"].eco.species[0]["name"]),
			"different seeds diverge")


func test_player_seed_is_the_branchs_first_draw() -> void:
	# D1: playerSeed = Math.random()*10 in TS → the stage branch's FIRST draw
	# natively. Prove order by replicating the draw off a state-copy of the
	# branch taken BEFORE the sim consumes it.
	var ctx: Variant = Ctx.new(SEED)
	var rng: Variant = ctx.rng.branch()
	var probe: Variant = RngLib.new_from(rng.state())  # stream copy, pre-draw
	var expected: float = probe.range(0.0, 10.0)
	var sim: Variant = CellSim.new(ctx, rng, {})
	approx(float(sim.playerSeed), expected, "playerSeed is the branch's first draw", 1e-9)
	ok(float(sim.playerSeed) >= 0.0 and float(sim.playerSeed) < 10.0,
			"playerSeed in [0, 10)")
	# same seed → same seed value AND same post-construction stream position
	var b := _mk_sim(SEED)
	var c := _mk_sim(SEED)
	approx(float(b["sim"].playerSeed), float(c["sim"].playerSeed),
			"playerSeed deterministic per seed", 1e-9)
	eq(b["sim"].rng.state(), c["sim"].rng.state(), "stream position deterministic")
	# a different seed lands elsewhere (continuous [0,10) — collision is ~2^-32)
	var d := _mk_sim(SEED + 1)
	ok(float(b["sim"].playerSeed) != float(d["sim"].playerSeed),
			"different seeds → different playerSeed")


# ---- player movement / drag / boundary -------------------------------------------


func test_movement_drag_and_speed_cap() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var inp := _inp({"down": true, "wx": 300.0, "wy": 0.0})
	sim.update(DT, inp)
	ok(sim.pvx > 0.0, "accelerated toward the held cursor")
	for i in 240:
		sim.update(DT, inp)
	var sp := sqrt(sim.pvx * sim.pvx + sim.pvy * sim.pvy)
	ok(sp <= float(sim.pStats["speed"]) * (1.0 + 1e-9) + 1e-6,
			"speed capped at stats.speed (no dash)")
	ok(sim.tut["moved"] > 0.0, "tut.moved accumulates")
	# dead zone: cursor on the player → no desired dir, only drag + current
	inp["wx"] = sim.px
	inp["wy"] = sim.py
	var vx0: float = sim.pvx
	sim.update(DT, inp)
	ok(absf(sim.pvx) < absf(vx0), "dead zone: no re-acceleration, drag decays")
	# WASD held keys
	sim.update(DT, _inp({"keys_held": ["KeyW"]}))
	ok(sim.pvy < 0.0, "KeyW pushes up")
	# release → drag decays; the ±14 current tide keeps a small vx ripple
	# (the tide itself grows over the test's 9 s, so the floor is ~4)
	for i in 300:
		sim.update(DT, _inp())
	ok(absf(sim.pvx) < 4.0, "vx decays to O(current tide)")
	approx(sim.pvy, 0.0, "drag decays vy (no current on y)", 1e-3)


func test_boundary_push_and_hard_clamp() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.time = -DT  # zero the current term for an exact push read
	sim.px = WORLD_R + 100.0
	sim.py = 0.0
	sim.pvx = 0.0
	sim.pvy = 0.0
	sim.update(DT, _inp())
	ok(sim.pvx < 0.0, "soft boundary pushes inward")
	# push = (dOrigin - WORLD_R) * 2.5, applied pvx -= (px/d)*push*dt*10
	approx(sim.pvx, -100.0 * 2.5 * DT * 10.0, "push formula exact", 1e-9)
	# hard clamp at WORLD_R + 200
	sim.px = WORLD_R + 500.0
	sim.py = 0.0
	sim.update(DT, _inp())
	var d := sqrt(sim.px * sim.px + sim.py * sim.py)
	ok(d <= WORLD_R + 200.0 + 1e-6, "hard clamp at WORLD_R+200")
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	sim2.time = -DT
	sim2.update(DT, _inp())
	approx(sim2.pvx, 0.0, "no push inside the world ring", 1e-12)


# ---- dash / toxin / electro -------------------------------------------------------


func test_dash_toxin_electro_abilities() -> void:
	var m := _mk_sim(SEED, {"jet": 2, "toxin": 1, "electro": 2})
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var e: Dictionary = sim.spawn_ent(null, 30.0, 0.0, {}, {})  # inside electro range
	e["stats"]["damage"] = 0.0  # silence their bite
	sim.update(DT, _inp({"keys_pressed": ["Space"]}))
	approx(sim.dashCd, 3.0 - DT, "dashCd 3")
	approx(sim.dashT, 0.35 - DT, "dashT 0.35")
	ok(sim.pvx > 0.0, "dash impulse applied")
	ok(_heard(rec, "dash"), "dash audio")
	# toxin burst — zone with TS-verbatim numbers
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(sim.zones.size(), 1, "toxin zone pushed")
	if sim.zones.size() == 1:
		var z: Dictionary = sim.zones[0]
		approx(float(z["r"]), 82.0, "zone r = 60 + toxin*22")
		approx(float(z["ttl"]), 6.0 - DT, "zone ttl 6 (decays same tick)")
		approx(float(z["dps"]), 8.0, "zone dps = 4 + toxin*4")
		eq(z["kind"], "toxin", "zone kind")
		eq(z["mine"], true, "player zone is mine")
	approx(sim.toxinCd, 6.0 - DT, "toxinCd 6")
	# electro burst — stuns ents in range
	sim.update(DT, _inp({"keys_pressed": ["Digit2"]}))
	approx(sim.electroCd, 10.0 - DT, "electroCd 10")
	approx(float(e["stun"]), 3.2, "stun = 1.8 + electro*0.7 (electro 2)")
	ok(_heard(rec, "zap"), "zap audio")
	var zapped := false
	for s in rec["shakes"]:
		if s[0] == 4.0 and s[1] == 0.3:
			zapped = true
	ok(zapped, "electro shake (4, 0.3)")
	# abilities dead when the gene is absent
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	sim2.update(DT, _inp({"keys_pressed": ["Digit1", "Digit2", "Space"]}))
	eq(sim2.zones.size(), 0, "no toxin zone without the gene")
	approx(sim2.dashCd, 0.0, "no dash without jet")
	# cooldowns gate re-fires
	sim.update(DT, _inp({"keys_pressed": ["Digit1"]}))
	eq(sim.zones.size(), 1, "toxinCd blocks a second burst")


# ---- bites / contact / proboscis / kill pay ---------------------------------------


func test_player_bite_and_kill_pay() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	ctx.world = {}  # isolate: no kin_grudge / corpse_tide on this seed's world
	var sp: Dictionary = sim.eco.living()[0]
	var e: Dictionary = sim.spawn_ent(sp, sim.px + 5.0, sim.py, {}, {})
	e["stats"]["damage"] = 0.0  # silence their bite for a clean read
	var hp0: float = e["hp"]
	sim.update(DT, _inp())
	var defense: float = minf(0.5, float(e["stats"]["defense"]))
	approx(float(e["hp"]), hp0 - float(sim.pStats["damage"]) * (1.0 - defense),
			"auto-bite dmg = damage * (1 - min(0.5, defense))", 1e-9)
	# ent hurtT decays in updateEnts (Task 4) — it holds until then
	approx(float(e["hurtT"]), 0.6, "hurtT set on bite", 1e-9)
	# finish it off — kill_ent called directly on an ent parked AWAY from the
	# player: at the bite site the dropped meat lands inside pickup radius and
	# update_pellets eats it the same tick (TS-verbatim — the pay assertions
	# below need the pellets to survive the tick)
	var e2: Dictionary = sim.spawn_ent(sp, sim.px + 500.0, sim.py, {}, {})
	e2["hp"] = 0.5
	var dna0: int = ctx.dna
	var kills0: int = ctx.world_stats["kills"]
	var karma0: float = ctx.karma
	var pel0: int = sim.pellets.size()
	sim.kill_ent(e2)
	eq(e2["hp"], -1, "killEnt marks hp=-1 for removal")
	eq(e2["lastPlayerHit"], "", "paid once — tag cleared")
	var n_meat := 1 + floori(float(e2["genome"]["size"]))
	eq(sim.pellets.size(), pel0 + n_meat, "meat pellets 1 + floor(size)")
	for i in range(pel0, sim.pellets.size()):
		var p: Dictionary = sim.pellets[i]
		eq(p["kind"], "meat", "kill drops meat")
		eq(p["ttl"], 30, "kill meat ttl 30")
		eq(p["val"], 3, "kill meat val 3")
	# DNA pays like eco.notifyKill: meal pricing from the species genome
	var g: Dictionary = e2["genome"]
	var meal: float = float(g["size"]) * (1.0 + float(g["spikes"]) * 0.1 + float(g["jaw"]) * 0.1)
	var pop_after: float = maxf(0.0, float(sp["pop"]) - 1.0)
	var sc: float = 0.6 if pop_after < 6.0 else (1.2 if pop_after > 25.0 else 1.0)
	var expected_dna := floori((9.0 + meal * 6.0 + maxf(0.0, meal - float(ctx.genome["size"])) * 6.0) * sc + 0.5)
	eq(ctx.dna, dna0 + expected_dna, "kill DNA = notifyKill pricing")
	eq(ctx.world_stats["kills"], kills0 + 1, "bumpKill on kill")
	approx(ctx.karma, karma0 + (-0.002 if g["diet"] == "herbivore" else -0.0005),
			"karma -0.002 herbivore / -0.0005 else", 1e-12)
	var fl := false
	for f in rec["floats"]:
		if f[2] == "+%d" % expected_dna:
			fl = true
	ok(fl, "float_world +dna text")
	ok(_heard(rec, "die"), "kill audio")


func test_swarm_kill_pays_dna_not_eco() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# parked away from the player (see test_player_bite_and_kill_pay)
	var e: Dictionary = sim.spawn_ent(null, sim.px + 500.0, sim.py, {}, {"swarm": true, "lifespan": 30})
	e["hp"] = 0.5
	var dna0: int = ctx.dna
	var karma0: float = ctx.karma
	var kills0: int = ctx.world_stats["kills"]
	var pel0: int = sim.pellets.size()
	sim.kill_ent(e)
	eq(e["hp"], -1, "swarm killed")
	eq(ctx.dna, dna0 + 8, "swarm DNA 8")
	approx(ctx.karma, karma0 - 0.004, "swarm karma -0.004", 1e-12)
	eq(ctx.world_stats["kills"], kills0, "swarm kills bypass the eco counter")
	var n_meat := 1 + floori(float(e["genome"]["size"]))
	eq(sim.pellets.size(), pel0 + n_meat, "swarm still drops meat")


func _kin_warnings(m: Dictionary) -> int:
	var n := 0
	for t in m["rec"]["toasts"]:
		if t[0] == "the kin are watching":
			n += 1
	return n


func test_kin_grudge_ledger_first_warning() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# minimal world blob: kin_grudge flag live (world_has walks traits/effects)
	ctx.world = {"seed": 7, "traits": [{"effects": [{"kind": "flag", "key": "kin_grudge"}]}]}
	var sp: Dictionary = sim.eco.species[0]
	sp["kin_tag"] = true
	for round_i in 2:
		var e: Dictionary = sim.spawn_ent(sp, sim.px + 5.0, sim.py, {}, {})
		e["stats"]["damage"] = 0.0
		e["hp"] = 0.5
		sim.biteCd = 0.0
		var before: int = _kin_warnings(m)
		sim.update(DT, _inp())
		if round_i == 0:
			eq(_kin_warnings(m), before + 1, "first kin kill warns exactly once")
		else:
			eq(_kin_warnings(m), before, "second kill stays silent")
	eq(float(sp["grudge"]), 2.0, "grudge ledger +1 per kill")


func test_corpse_tide_combo_drop() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ctx.world = {"seed": 3, "traits": [], "comboFired": {"corpse_tide": true}}
	var e: Dictionary = sim.spawn_ent(sim.eco.living()[0], sim.px + 5.0, sim.py, {}, {})
	e["stats"]["damage"] = 0.0
	e["hp"] = 0.5
	sim.biteCd = 0.0
	sim.update(DT, _inp())
	approx(sim.eco.corpses, 1.0, "corpse joins the ledger")
	ok(sim.eco.tide_species() != null, "scavenger line founded")
	var pop: float = sim.eco.tide_species()["pop"]
	ok(pop >= 2.0 and pop <= 3.0, "drop_corpse(2 + chance(0.5)), pop-capped")


func test_contact_proboscis_and_their_bite_invuln() -> void:
	var m := _mk_sim(SEED, {"spikes": 3, "proboscis": 2})
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	# a BIGGER mutant overlaps the player: contact spikes + proboscis drain
	var big: Dictionary = GenomeLib.default_genome()
	big["size"] = 1.5
	var e: Dictionary = sim.spawn_ent(null, sim.px + 5.0, sim.py, big, {})
	var hp0: float = e["hp"]
	var contact_dmg: float = float(sim.pStats["contact_damage"]) * DT * 2.0
	var drain: float = 2.0 * 3.0 * DT
	var bite_dmg: float = float(sim.pStats["damage"]) * (1.0 - minf(0.5, float(e["stats"]["defense"])))
	# spawn invuln swallows their bite this tick
	sim.update(DT, _inp())
	approx(float(e["hp"]), hp0 - contact_dmg - drain * 2.0 - bite_dmg,
			"contact + drain + our bite all land in one overlap tick", 1e-9)
	eq(e["lastPlayerHit"], "drain", "last tag wins (drain after contact)")
	approx(sim.php, sim.pmaxHp, "spawn invuln blocks their bite")
	# dna trickle: 0.04/tick accumulates in the frac register — no whole DNA yet
	eq(ctx.dna, 40, "proboscis trickle stays fractional")
	# their bite lands once invuln is gone (tick 1 already armed e.biteCd=0.8
	# — TS sets the cd regardless of invuln — so re-arm the read)
	sim.invuln = 0.0
	e["biteCd"] = 0.0
	var php0: float = sim.php
	sim.update(DT, _inp())
	var their_dmg: float = float(e["stats"]["damage"]) * (1.0 - float(sim.pStats["defense"]))
	approx(sim.php, php0 - their_dmg, "their bite dmg = damage * (1 - defense)", 1e-9)
	approx(sim.hurtT, 1.0 - DT * 3.0, "hurtT set on their bite", 1e-9)
	var shaken := false
	for s in rec["shakes"]:
		if s[0] == 3.0 and s[1] == 0.2:
			shaken = true
	ok(shaken, "their bite shakes (3, 0.2)")
	ok(_heard(rec, "hurt"), "hurt audio")
	# a DEAD ent cannot be re-bitten or re-drained (alive-only guards)
	e["hp"] = -1.0
	var hp_dead: float = e["hp"]
	sim.biteCd = 0.0
	sim.update(DT, _inp())
	approx(float(e["hp"]), hp_dead, "no contact/drain/bite on a corpse")


func test_after_timers_fire_on_the_stage_clock() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var fired: Array = []
	sim.after(0.5, func(): fired.append("a"))
	sim.after(0.2, func(): fired.append("b"))
	for i in 40:
		sim.update(DT, _inp())
		if i == 12:
			eq(fired, ["b"], "shorter timer first (13 ticks > 0.2 s in float)")
	eq(fired, ["b", "a"], "both timers fired in left-order")
	for i in 40:
		sim.update(DT, _inp())
	eq(fired.size(), 2, "timers fire exactly once")


func test_fx_burst_replays_five_draws_in_ts_order() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var s0: int = sim.rng.state()
	sim._fx_burst(1.0, 2.0, 1, ["#aaa", "#bbb"], {"speed": 100.0, "ttl": 0.8, "size": 4.0})
	# the replay must consume EXACTLY the TS draw sequence: ang(next), sp
	# (range 0.3..1), color pick, ttl (range 0.4..1), size (range 0.6..1.4
	# × opts.size) — verified by replaying 5 draws on a state-copy
	var probe: Variant = RngLib.new_from(s0)
	var ang: float = probe.next() * PI * 2.0
	var sp: float = probe.range(0.3, 1.0) * 100.0
	var color: String = probe.pick(["#aaa", "#bbb"])
	var ttl: float = probe.range(0.4, 1.0) * 0.8
	var psz: float = probe.range(0.6, 1.4) * 4.0
	eq(sim.rng.state(), probe.state(), "one burst particle = exactly 5 draws, TS order")
	eq(rec["bursts"].size(), 1, "burst recorded")
	var parts: Array = rec["bursts"][0][3]["parts"]
	eq(parts.size(), 1, "one parts row per particle")
	approx(float(parts[0]["ang"]), ang, "parts.ang", 1e-9)
	approx(float(parts[0]["sp"]), sp, "parts.sp", 1e-9)
	eq(parts[0]["color"], color, "parts.color")
	approx(float(parts[0]["ttl"]), ttl, "parts.ttl", 1e-9)
	approx(float(parts[0]["size"]), psz, "parts.size (0.6..1.4 × opts.size)", 1e-9)


# ---- pellets -----------------------------------------------------------------------


func test_pellet_economy_pickup_rules() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# plant: DNA + val, flora -0.4, karma +0.0005, nutrition +0.03
	sim.pellets.append({"x": sim.px, "y": sim.py, "vx": 0.0, "vy": 0.0,
			"kind": "plant", "ttl": 10.0, "val": 2})
	var dna0: int = ctx.dna
	var flora0: float = sim.eco.flora
	var karma0: float = ctx.karma
	var nut0: float = sim.nutrition
	var eaten0: int = sim.tut["eaten"]
	sim.update(DT, _inp())
	eq(sim.pellets.size(), 30, "plant pellet eaten")
	eq(ctx.dna, dna0 + 2, "plant pays its val")
	approx(sim.eco.flora, flora0 - 0.4, "flora -0.4 per plant", 1e-9)
	approx(ctx.karma, karma0 + 0.0005, "plant karma +0.0005", 1e-12)
	# the same tick's cooldown block decays nutrition by dt*0.01 afterwards
	approx(sim.nutrition, minf(1.0, nut0 + 0.03) - DT * 0.01,
			"nutrition +0.03 per plant (net of the same-tick decay)", 1e-12)
	eq(sim.tut["eaten"], eaten0 + 1, "tut.eaten++")
	# meat: heal 5, karma -0.0005, scavenge counts toward the hunt step
	sim.php = 40.0
	sim.pellets.append({"x": sim.px, "y": sim.py, "vx": 0.0, "vy": 0.0,
			"kind": "meat", "ttl": 10.0, "val": 5})
	karma0 = ctx.karma
	var killed0: int = sim.tut["killed"]
	sim.update(DT, _inp())
	approx(sim.php, 45.0, "meat scavenge heals 5")
	approx(ctx.karma, karma0 - 0.0005, "scavenge karma -0.0005", 1e-12)
	eq(sim.tut["killed"], killed0 + 1, "scavenge counts toward the hunt step")
	# dna pellet: val payout + float text
	sim.pellets.append({"x": sim.px, "y": sim.py, "vx": 0.0, "vy": 0.0,
			"kind": "dna", "ttl": 10.0, "val": 12})
	dna0 = ctx.dna
	sim.update(DT, _inp())
	eq(ctx.dna, dna0 + 12, "dna pellet pays val")
	var fl := false
	for f in m["rec"]["floats"]:
		if f[2] == "+12 DNA":
			fl = true
	ok(fl, "dna float text '+12 DNA'")
	# no posthumous farming
	sim.php = 0.0
	sim.pellets.append({"x": sim.px, "y": sim.py, "vx": 0.0, "vy": 0.0,
			"kind": "plant", "ttl": 10.0, "val": 2})
	var n0: int = sim.pellets.size()
	sim.update(DT, _inp())
	eq(sim.pellets.size(), n0, "a dying cell cannot farm pellets")


func test_pellet_ttl_cap_and_current() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# cap 260 with shift eviction
	for i in 300:
		sim.spawn_pellet("plant")
	eq(sim.pellets.size(), 260, "pellet cap 260, shift eviction")
	# park the player away from the field so nothing gets EATEN mid-read
	# (pellet spawns concentrate near the origin: r is uniform, not area)
	sim.px = 2000.0
	sim.py = 2000.0
	# ttl expiry
	sim.pellets[0]["ttl"] = 0.05
	var n: int = sim.pellets.size()
	sim.update(0.1, _inp())
	eq(sim.pellets.size(), n - 1, "expired pellet removed")
	# pellet drag + current (time = DT when updatePellets runs)
	var q: Dictionary = sim.pellets[0]
	q["x"] = 2000.0
	q["y"] = 2100.0
	q["vx"] = 10.0
	q["vy"] = 0.0
	q["ttl"] = 10.0
	sim.time = 0.0
	sim.update(DT, _inp())
	var cur: float = sin(2100.0 * 0.004 + DT * 0.05) * 14.0
	approx(float(q["vx"]), 10.0 * exp(-1.5 * DT) + cur * DT,
			"pellet drag exp(-1.5dt) + current", 1e-9)


# ---- zones / current / radius -------------------------------------------------------


func test_zones_tick_drift_and_expiry() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.zones.append({"x": 0.0, "y": 0.0, "r": 50.0, "kind": "toxin", "ttl": 6.0,
			"dps": 8.0, "pulse": 0.0, "mine": true})
	sim.zones.append({"x": 10.0, "y": 10.0, "r": 80.0, "kind": "vent", "ttl": 240.0,
			"dps": 0.0, "heal": 6.0, "pulse": 0.0})
	sim.update(DT, _inp())
	var z: Dictionary = sim.zones[0]
	approx(float(z["pulse"]), DT, "pulse += dt", 1e-12)
	approx(float(z["x"]), sin(DT * 0.7) * 14.0 * DT, "toxin x drift", 1e-15)
	approx(float(z["y"]), cos(DT * 0.5) * 14.0 * DT, "toxin y drift", 1e-15)
	approx(float(sim.zones[1]["ttl"]), 240.0 - DT, "vent ttl decays")
	# expiry
	z["ttl"] = 0.05
	sim.update(0.1, _inp())
	eq(sim.zones.size(), 1, "expired toxin zone removed")
	eq(sim.zones[0]["kind"], "vent", "vent survives")


func test_vent_heal() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.zones.append({"x": 0.0, "y": 0.0, "r": 80.0, "kind": "vent", "ttl": 240.0,
			"dps": 0.0, "heal": 6.0, "pulse": 0.0})
	sim.php = 50.0
	sim.update(DT, _inp())
	approx(sim.php, 50.0 + 6.0 * DT, "vent heals heal*dt inside r", 1e-9)
	# a dead cell gets nothing (never rescues the dying)
	sim.php = 0.0
	var before: float = sim.php
	sim.update(DT, _inp())
	ok(sim.php <= before + 1e-9, "no vent rescue while dying")


func test_current_and_radius_math() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.time = 0.0
	approx(sim.current_at(0.0), 0.0, "current at origin is 0", 1e-12)
	approx(sim.current_at(250.0), sin(1.0) * 14.0, "current sin(y*0.004 + t*0.05)*14", 1e-9)
	sim.nutrition = 0.5
	var size: float = float(m["ctx"].genome["size"])
	approx(sim.player_radius(), 14.0 * size * 1.175,
			"radius 14*size*(1+nutrition*0.35)", 1e-9)


# ---- shore click ---------------------------------------------------------------------


func test_shore_travel_click() -> void:
	var m := _mk_sim(SEED, {"legs": 1})
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.shoreRect = {"x": 100.0, "y": 100.0, "w": 190.0, "h": 46.0}
	ok(not sim.shoreAvailable, "not armed before the first update (TS arms in onEnter)")
	# arm via the end-of-update rule (legs >= 1)
	sim.update(DT, _inp())
	ok(sim.shoreAvailable, "armed after an update with legs >= 1")
	# over_shore hit-test includes the armed flag (TS-verbatim)
	ok(sim.over_shore(150.0, 120.0), "hit inside the rect")
	ok(not sim.over_shore(500.0, 120.0), "miss outside")
	# click inside → save + travel + ascend audio, update returns early
	sim.update(DT, _inp({"mx": 150.0, "my": 120.0, "clicked": true}))
	eq(rec["saves"], 1, "game_save_all before travel")
	eq(rec["shore"], 1, "shore_travel hook fired")
	ok(_heard(rec, "ascend"), "ascend audio")
	# pre-taken click does not re-trigger
	sim.update(DT, _inp({"mx": 150.0, "my": 120.0, "clicked": true, "take_click": true}))
	eq(rec["shore"], 1, "pre-taken click ignored")
	# no legs → never
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	sim2.shoreRect = {"x": 100.0, "y": 100.0, "w": 190.0, "h": 46.0}
	sim2.update(DT, _inp())
	sim2.update(DT, _inp({"mx": 150.0, "my": 120.0, "clicked": true}))
	eq(m2["rec"]["shore"], 0, "no legs, no shore")


# ---- population maintenance / despawn ------------------------------------------------


func test_maintain_population_despawn_and_spawn() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var far: Dictionary = sim.spawn_ent(sim.eco.living()[0], 2000.0, 0.0, {}, {})
	var near: Dictionary = sim.spawn_ent(sim.eco.living()[0], 100.0, 0.0, {}, {})
	sim.spawnTimer = 1.19
	sim.update(DT, _inp())
	ok(not sim.ents.has(far), "ents beyond 1600 despawn on the spawn tick")
	ok(sim.ents.has(near), "nearby ents stay")
	# non-kin species respawn toward min(9, round(pop*0.6)) at 0.4/tick — over
	# several spawn windows something must crawl in
	for i in 400:
		sim.update(DT, _inp())
	ok(sim.ents.size() >= 2, "population maintenance spawned ents")
	for e in sim.ents:
		ok(sqrt(e["x"] * e["x"] + e["y"] * e["y"]) < 1600.0, "all ents within 1600")
		ok(e["band"].has_all(["aggression", "fear"]), "spawned ents carry a behavior band")
		ok(int(e["eid"]) > 0, "eids monotonic")
	var living_ids := {}
	for sp in sim.eco.living():
		living_ids[sp["id"]] = true
	var hit := false
	for e in sim.ents:
		if living_ids.has(e["speciesId"]):
			hit = true
	ok(hit, "spawned ents belong to living species")


func test_debug_spawn_near() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.debug_spawn_near(3)
	eq(sim.ents.size(), 3, "3 ents spawned near the player")
	for e in sim.ents:
		ok(sqrt(e["x"] * e["x"] + e["y"] * e["y"]) <= 320.0 + 1e-6,
				"area-uniform strike zone r <= 320")


# ---- death / respawn ------------------------------------------------------------------


func test_death_respawn_cycle() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	var dna0: int = ctx.dna
	var chaos0: float = ctx.chaos
	sim.php = 0.0
	sim.update(DT, _inp())
	eq(rec["events"].size(), 1, "playerDeath emitted exactly once on the first frame")
	if rec["events"].size() == 1:
		eq(rec["events"][0][0], "playerDeath", "event name")
	var lost := floori(float(dna0) * 0.12 + 0.5)
	eq(ctx.dna, dna0 - lost, "DNA loss round(12%)")
	approx(ctx.chaos, minf(1.0, chaos0 + 0.03), "death chaos +0.03", 1e-12)
	ok(sim.deathStarted, "death fade running")
	ok(_heard(rec, "die"), "death audio")
	# ents for the respawn sweep: the origin is always within 700 of the r=600
	# respawn ring (cleared); (1400, 0) is >700 from every ring point yet
	# <1600 from the dying player, so the despawn valve leaves it alone
	var near_a: Dictionary = sim.spawn_ent(null, 0.0, 0.0, {}, {})
	var far_b: Dictionary = sim.spawn_ent(null, 1400.0, 0.0, {}, {})
	# fade > 1.6 lands on update 97 (1.2s spawn ticks: 72 and 144 — 97 sits
	# between them, no despawn interferes with the sweep read)
	for i in 95:
		sim.update(DT, _inp())
	eq(rec["events"].size(), 1, "death event fires once per death")
	ok(sim.php <= sim.pmaxHp + 0.001, "sane hp during the fade")
	sim.update(DT, _inp())  # fade crosses 1.6 → respawn this tick
	approx(sim.php, sim.pmaxHp, "respawned at full hp")
	approx(sim.invuln, 4.0, "respawn invuln 4")
	approx(sqrt(sim.px * sim.px + sim.py * sim.py), 600.0, "respawn at r=600")
	approx(sim.pvx, 0.0, "velocity cleared on respawn", 1e-9)
	ok(not sim.ents.has(near_a), "threats within 700 of the respawn cleared")
	ok(sim.ents.has(far_b), "distant ents survive the sweep")
	ok(not sim.deathStarted, "fade flag reset for the next death")
	# second death re-fires the event (the TS deathFade === dt idiom resets)
	sim.php = 0.0
	sim.update(DT, _inp())
	eq(rec["events"].size(), 2, "playerDeath fires again on the next death")


# ---- eco tick batch --------------------------------------------------------------------


func test_eco_tick_batch_and_extinction_banner() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	var victim: Variant = null
	for sp in sim.eco.living():
		victim = sp
		break
	victim["pop"] = 0.05  # below the 0.4 floor after the batch
	# park the player away from the starter field so no pellet is eaten
	# mid-read (spawns concentrate near the origin)
	sim.px = 2000.0
	sim.py = 2000.0
	var ext0: int = ctx.world_stats["extinctions"]
	var chaos0: float = ctx.chaos
	var pel0: int = sim.pellets.size()
	sim.ecoTimer = 1.9
	sim.update(0.2, _inp())  # batch = 2.1 >= 2 → tick
	# mods refreshed from the world genome right before the batch
	eq(sim.eco.mods, WorldGenome.eco_mods_from_world(ctx.world), "eco mods refreshed")
	eq(victim["extinct"], true, "starved species went extinct")
	eq(ctx.world_stats["extinctions"], ext0 + 1, "bumpExtinction")
	approx(ctx.chaos, minf(1.0, chaos0 + 0.05), "extinction chaos +0.05", 1e-12)
	eq(rec["banners"].size(), 1, "extinction banner")
	if rec["banners"].size() == 1:
		var b: Dictionary = rec["banners"][0]
		eq(b["title"], "%s is extinct" % victim["name"], "banner title")
		eq(b["kind"], "chaos", "banner kind")
	# bio_shift toast rides the same batch
	var shift_toast := false
	for t in rec["toasts"]:
		if String(t[0]).begins_with("The web re-equilibrates:"):
			shift_toast = true
	ok(shift_toast, "bio_shift re-equilibrates toast")
	# flora >= 12 and < 60 plant pellets → the batch feeds one plant pellet
	eq(sim.pellets.size(), pel0 + 1, "flora-fed plant pellet per batch")
	eq(sim.pellets.back()["kind"], "plant", "fed pellet is plant")


# ---- chaos helpers: stubbed, no-op, zero rng draws (Task 5 fills bodies) ---------------


func test_chaos_helpers_are_deterministically_absent() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var s0: int = sim.rng.state()
	var ent0: int = sim.ents.size()
	var pel0: int = sim.pellets.size()
	sim.spawn_meteor_target(10.0, 10.0)
	sim.meteor_impact(10.0, 10.0)
	sim.add_toxin_zone(0.0, 0.0, 50.0, 4.0, 6.0)
	sim.add_toxin_zone(0.0, 0.0, 50.0, 4.0, 6.0, "clouds")
	sim.drift_toxin_clouds(DT)
	sim.algae_surge()
	sim.add_vent(0.0, 0.0)
	sim.bloom()
	sim.blight()
	sim.spawn_swarm()
	ok(sim.spawn_big_brother() == null, "big brother stub returns null")
	eq(sim.spawn_mutant_wave(), 0, "mutant wave stub returns 0")
	eq(sim.rng.state(), s0, "stubbed chaos helpers draw no rng")
	eq(sim.ents.size(), ent0, "no ents spawned by stubs")
	eq(sim.pellets.size(), pel0, "no pellets pushed by stubs")
	eq(sim.zones.size(), 0, "no zones pushed by stubs")


# ---- gaia wanderer / onStatsChanged -----------------------------------------------------


func test_gaia_wanderer_and_on_stats_changed() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rare: Variant = ctx.rare_gene()
	ok(rare != null, "the seeded roster offers a gene the player lacks")
	sim.gaia_wanderer()
	eq(sim.ents.size(), 1, "one wanderer spawned")
	if sim.ents.size() == 1:
		var e: Dictionary = sim.ents[0]
		eq(e["speciesId"], "mutant", "wanderer is a mutant individual")
		approx(float(e["lifespan"]), 120.0, "wanderer lifespan 120")
		eq(float(e["genome"][rare["gene"]]), float(rare["level"]), "carries the rare gene")
	# onStatsChanged recomputes from the live genome
	ctx.genome["jaw"] = 5
	sim.on_stats_changed()
	approx(float(sim.pStats["damage"]), 4.0 + 25.0 + float(ctx.genome["size"]) * 2.0,
			"pStats recomputed", 1e-9)
	approx(sim.pmaxHp, float(sim.pStats["max_hp"]), "pmaxHp follows")
	# an overhealed hp clamps down; a dying hp is left alone
	sim.php = 999.0
	sim.on_stats_changed()
	approx(sim.php, sim.pmaxHp, "overheal clamps to pmaxHp")
	sim.php = -1.0
	sim.on_stats_changed()
	approx(sim.php, -1.0, "the dead are not resurrected by the editor")


# ---- assertSane walk + headless determinism ---------------------------------------------


func _assert_sane(m: Dictionary, msg: String) -> void:
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ok(is_finite(ctx.dna) and ctx.dna >= 0, msg + ": dna finite >= 0")
	ok(ctx.chaos >= 0.0 and ctx.chaos <= 1.0, msg + ": chaos in [0,1]")
	ok(ctx.karma >= -1.0 and ctx.karma <= 1.0, msg + ": karma in [-1,1]")
	ok(is_finite(sim.px) and is_finite(sim.py), msg + ": position finite")
	ok(sim.php <= sim.pmaxHp + 0.001, msg + ": php <= pmaxHp")
	ok(sim.ents.size() < 300, msg + ": ents < 300")


func test_sanity_walk_600_ticks() -> void:
	var m := _mk_sim(SEED, {"jet": 2, "toxin": 1, "electro": 1})
	var sim: Variant = m["sim"]
	for f in 600:
		var t := float(f) * DT
		var pressed: Array = []
		if f == 100:
			pressed = ["Space"]
		elif f == 200:
			pressed = ["Digit1"]
		elif f == 300:
			pressed = ["Digit2"]
		var held: Array = ["KeyW"] if f % 90 < 40 else []
		var inp := _inp({
			"wx": sin(t * 0.7) * 300.0, "wy": cos(t * 0.5) * 300.0,
			"down": f % 20 < 12,
			"keys_held": held, "keys_pressed": pressed,
		})
		sim.update(DT, inp)
		if f % 60 == 0:
			_assert_sane(m, "tick %d" % f)
	_assert_sane(m, "end")
	ok(sim.pellets.size() <= 260, "pellet cap holds through the walk")


func test_determinism_600_ticks() -> void:
	var a := _mk_sim(SEED, {"jet": 2, "toxin": 1, "electro": 1})
	var b := _mk_sim(SEED, {"jet": 2, "toxin": 1, "electro": 1})
	for f in 600:
		var t := float(f) * DT
		var pressed: Array = []
		if f == 120:
			pressed = ["Space"]
		elif f == 240:
			pressed = ["Digit1"]
		elif f == 360:
			pressed = ["Digit2"]
		var held: Array = ["KeyA"] if f % 70 < 25 else []
		var inp := _inp({
			"mx": 400.0, "my": 300.0,
			"wx": sin(t * 0.9) * 400.0, "wy": cos(t * 0.6) * 400.0,
			"down": f % 30 < 18,
			"keys_held": held, "keys_pressed": pressed,
		})
		a["sim"].update(DT, inp)
		b["sim"].update(DT, inp)
	eq(_snap(a["sim"]), _snap(b["sim"]), "same seed → identical 600-tick snapshot")
	var c := _mk_sim(SEED + 1, {"jet": 2, "toxin": 1, "electro": 1})
	for f in 60:
		c["sim"].update(DT, _inp({"down": true, "wx": 100.0, "wy": 0.0}))
	ok(_snap(c["sim"])["kelp"] != _snap(a["sim"])["kelp"], "different seed diverges")
