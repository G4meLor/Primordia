## Tests for game/creature/creature_sim.gd update_ents — the z-band NPC AI:
## corpse lifecycle, baby growth, stampede lifetime, the panic/charmed/pack/
## hunt/flee/graze decision chain, bush/corpse grazing, hazard damage.
## TS source: Spore src/game/creature/CreatureStage.ts updateEnts (frozen,
## lines 835-1019). Path-based extends + preload-by-path: class_name globals
## don't resolve in `-s` mode. Expected values derived from the TS formulas
## (branch gates, radii, damp factors) — structural scenario pins plus
## closed-form float pins, same style as test_creature_sim.gd.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const StatsLib := preload("res://src/evo/stats.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE
const Z_TO_Y := 0.62


# ---- fixtures ------------------------------------------------------------------

func _mk_sim(seed_v: int = SEED, genome_mods: Dictionary = {},
		difficulty: String = "normal", world_override: Variant = null) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	if not genome_mods.is_empty():
		var g: Dictionary = ctx.genome
		g.merge(genome_mods, true)
	ctx.difficulty = difficulty
	if world_override != null:
		ctx.world = world_override
	var rec: Dictionary = {
		"toasts": [], "banners": [], "floats": [], "audio": [], "shakes": [],
		"bursts": [], "spawns": [], "notes": [], "events": [],
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
		"context_event": func(ev, data): rec["events"].append([ev, data]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


func _park_world_objects(m: Dictionary) -> void:
	var sim: Variant = m["sim"]
	for b in sim.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0
	for bo in sim.bones:
		bo["x"] = 99999.0
		bo["z"] = 99999.0


func _ent_by_eid(sim: Variant, eid: int) -> Variant:
	for e in sim.ents:
		if int(e["eid"]) == eid:
			return e
	return null


func _dist(sim: Variant, e: Dictionary) -> float:
	var dx: float = float(e["x"]) - float(sim.px)
	var dz: float = float(e["z"]) - float(sim.pz)
	return sqrt(dx * dx + dz * dz)


# ---- scenarios -----------------------------------------------------------------

# TS:841-856 — the corpse lifecycle: meat decays; a carnivore player holding
# down within 30 eats (heal 14dt, DNA 2.4dt — corpseT unaffected); on expiry
# 35% rolls a bone at the corpse's spot; the corpse splices out.
func test_corpse_lifecycle_meat_bone_removal() -> void:
	# removal at expiry
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 100.0, float(sim.pz))
	e["corpseT"] = 0.01
	sim.update_ents(DT)
	ok(_ent_by_eid(sim, int(e["eid"])) == null, "expired corpse removed from ents")
	# the 35% bone roll over 40 corpses: deterministic for the seed (14 pass)
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var xs: Array = []
	for i in 40:
		var c: Dictionary = sim2.spawn_ent(null, 100.0 + float(i) * 50.0, 0.0)
		c["corpseT"] = 0.01
		xs.append(100.0 + float(i) * 50.0)
	sim2.update_ents(DT)
	eq(sim2.ents.size(), 0, "all 40 corpses expired out of the loop")
	var newBones: Array = sim2.bones.slice(8)  # 8 seeded bones at construction
	eq(newBones.size(), 14, "35% bone roll: 14 of 40 corpses left bones (seed-pinned)")
	for bo in newBones:
		eq(String(bo["kind"]), "bone", "corpse bones are kind 'bone'")
		eq(bool(bo["taken"]), false, "corpse bones untaken")
		ok(xs.has(float(bo["x"])), "bone placed at the corpse's x")
	# player meat-eat: carnivore player holding down within 30
	var m3 := _mk_sim()
	var sim3: Variant = m3["sim"]
	var ctx3: Variant = m3["ctx"]
	_park_world_objects(m3)
	ctx3.genome["diet"] = "carnivore"
	var c3: Dictionary = sim3.spawn_ent(null, float(sim3.px), float(sim3.pz))
	c3["corpseT"] = 5.0
	sim3.php = 50.0
	var dna0: int = int(ctx3.dna)
	var eat_inp: Dictionary = _inp({"down": true, "wx": float(sim3.px),
			"wy": float(sim3.pz) * Z_TO_Y})
	for i in 50:
		sim3.update(DT, eat_inp)
	approx(float(sim3.php), 50.0 + 14.0 * 50.0 * DT, "meat-eat heals 14dt")
	eq(int(ctx3.dna) - dna0, 2, "meat-eat pays DNA 2.4dt (2 whole over 50 ticks)")
	approx(float(c3["corpseT"]), 5.0 - 50.0 * DT, "eating the meat does not burn corpseT")
	# gates: pointer up -> no meal; herbivore player -> no meal
	var m4 := _mk_sim()
	var sim4: Variant = m4["sim"]
	var ctx4: Variant = m4["ctx"]
	_park_world_objects(m4)
	ctx4.genome["diet"] = "carnivore"
	var c4: Dictionary = sim4.spawn_ent(null, float(sim4.px), float(sim4.pz))
	c4["corpseT"] = 5.0
	sim4.php = 50.0
	sim4.update(DT, _inp({"wx": float(sim4.px), "wy": float(sim4.pz) * Z_TO_Y}))
	approx(float(sim4.php), 50.0, "pointer up gates the corpse meal")
	var m5 := _mk_sim()
	var sim5: Variant = m5["sim"]
	var ctx5: Variant = m5["ctx"]
	_park_world_objects(m5)
	ctx5.genome["diet"] = "herbivore"
	var c5: Dictionary = sim5.spawn_ent(null, float(sim5.px), float(sim5.pz))
	c5["corpseT"] = 5.0
	sim5.php = 50.0
	sim5.update(DT, _inp({"down": true, "wx": float(sim5.px),
			"wy": float(sim5.pz) * Z_TO_Y}))
	approx(float(sim5.php), 50.0, "herbivore player cannot eat meat")


# TS:999-1008 — carnivore ents graze on corpses: corpseT burns 2dt per eater
# tick (plus the corpse's own 1dt), the eater heals 6dt up to maxHp.
func test_carnivore_ent_eats_corpses() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var corpse: Dictionary = sim.spawn_ent(null, 100.0, 20.0)
	corpse["corpseT"] = 5.0
	var hg: Dictionary = GenomeLib.default_genome()
	hg.merge({"diet": "carnivore", "legs": 4, "jaw": 3}, true)
	var hunter: Dictionary = sim.spawn_ent(null, 100.0, 25.0, hg)
	hunter["hp"] = 30.0
	for i in 3:
		sim.update_ents(DT)
	approx(float(corpse["corpseT"]), 5.0 - 3.0 * 3.0 * DT,
			"corpseT burns 3dt per tick (2dt eaten + 1dt own decay)")
	approx(float(hunter["hp"]), 30.0 + 6.0 * 3.0 * DT, "scavenger heals 6dt")
	approx(float(hunter["eatT"]), 1.0, "scavenger eatT set while eating")


# TS:927-935 — a carnivore big enough to not fear the player and out of the
# player's threat shadow hunts on sight: mood angry, closes the distance.
# Gate math (default player: damage 13, size 1): hunter damage
# 5+3*6+1*4+1.4*2 = 29.8 -> threat false; vision 360*1.3 = 468;
# sizeGap max(0.35, 1-(1.4-1)*0.6) = 0.76; band("mutant") aggression 0.94
# -> hunt radius 468*0.76*0.94 = 334.3 > 200.
func test_hunter_aggros_smaller_player() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 200.0, float(sim.pz),
			{"size": 1.4, "diet": "carnivore", "legs": 4, "jaw": 3, "horns": 1, "eyes": 2})
	sim.update(DT, _inp({}))
	eq(String(e["mood"]), "angry", "hunter mood angry (hunt branch)")
	eq(int(e["facing"]), -1, "hunter faces the player (dx < 0)")
	ok(_dist(sim, e) < 200.0, "hunter closed the distance")
	approx(float(sim.php), 70.0, "player untouched at 200px")


# TS:911-916 + 942-965 — the hunt radius shrinks with the size gap: a big
# carnivore IGNORES a hatchling at a range full vision would cover. Gate math
# (hatchling player: damage 12.2, size 0.6): titan damage
# 5+5*6+4*4+2.2*2 = 55.4 -> threat false; sizeGap max(0.35, 1-(2.2-0.6)*0.6)
# = 0.35 -> hunt radius 468*0.35*0.94 = 154. At 300px: graze (idle). At
# 100px (< 154): the same genome hunts — proves the gate is the radius.
func test_big_carnivore_ignores_hatchling_size_gap() -> void:
	var m := _mk_sim(SEED, {"size": 0.6})
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var far: Dictionary = sim.spawn_ent(null, float(sim.px) + 300.0, float(sim.pz),
			{"size": 2.2, "diet": "carnivore", "legs": 4, "jaw": 5, "horns": 4, "eyes": 2})
	for i in 60:
		sim.update(DT, _inp({}))
	ok(String(far["mood"]) != "angry", "big carnivore never aggros the hatchling at 300px")
	eq(String(far["mood"]), "idle", "far titan idles (graze branch)")
	ok(_dist(sim, far) > 154.0, "grazing wander cannot cross the shrunken radius in 1s")
	# contrast: inside the shrunken radius the same genome hunts
	var m2 := _mk_sim(SEED, {"size": 0.6})
	var sim2: Variant = m2["sim"]
	_park_world_objects(m2)
	var near: Dictionary = sim2.spawn_ent(null, float(sim2.px) + 100.0, float(sim2.pz),
			{"size": 2.2, "diet": "carnivore", "legs": 4, "jaw": 5, "horns": 4, "eyes": 2})
	sim2.update(DT, _inp({}))
	eq(String(near["mood"]), "angry", "inside the sizeGap radius it hunts")


# TS:921-932 — kin_memory grudgeHunt: a kin-tagged species with grudge >= 2
# presses when the player is weak (radius opens 1.4x when php < 0.4 pmaxHp)
# and every counted press rides the harassment valve. Gate math (sp0
# herbivore, eyes 2 -> vision 468): full-hp radius 468*0.9 = 421.2; hurt
# radius 468*0.9*1.4 = 589.7. At 500px: idle at full hp, hunts when hurt.
func test_grudge_hunt_opens_when_player_hurt() -> void:
	var worldKin: Dictionary = {"seed": SEED,
			"traits": [{"effects": [{"kind": "flag", "key": "kin_grudge"}]}]}
	var m := _mk_sim(SEED, {}, "normal", worldKin)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_park_world_objects(m)
	var sp: Dictionary = ctx.eco.species[0]
	sp["kin_tag"] = true
	sp["grudge"] = 2.0
	var e: Dictionary = sim.spawn_ent(sp, float(sim.px) + 500.0, float(sim.pz))
	# full hp: grudge radius not met, prey gate dead (herbivore), flee gate
	# dead (grudge >= 2 restores... blocks it) -> graze
	sim.update(DT, _inp({}))
	eq(String(e["mood"]), "idle", "grudge-2 kin idles while the player is healthy")
	eq(sp.get("harass", 0), 0, "no press counted at full hp")
	# hurt (20 < 0.4*70 = 28): the 1.4x radius opens, the press counts
	sim.php = 20.0
	sim.update(DT, _inp({}))
	eq(String(e["mood"]), "angry", "grudgeHunt hunts the hurt player")
	approx(float(sp["harass"]), 1.0, "registerPress counted once")
	approx(float(e["pressCd"]), 20.0, "pressCd armed at PRESS_COOLDOWN")
	# the valve: pressCd gates a second press inside the engagement
	sim.update(DT, _inp({}))
	approx(float(sp["harass"]), 1.0, "no second press while pressCd runs")


# TS:904-909 — pack follows at the 60px band: beyond 100px it closes in
# (sp x1.05), inside it holds still (sp 0), mood happy either way.
func test_pack_follows_at_the_60px_band() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 150.0, float(sim.pz),
			{}, {"pack": true})
	sim.update(DT, _inp({}))
	eq(String(e["mood"]), "happy", "pack follower happy")
	ok(float(e["x"]) < float(sim.px) + 150.0, "follower beyond the band closes in")
	# inside followD + 40 the follower holds position
	e["x"] = float(sim.px) + 90.0
	e["vx"] = 0.0
	e["vz"] = 0.0
	var held_x: float = float(e["x"])
	sim.update(DT, _inp({}))
	approx(float(e["x"]), held_x, "inside the band the follower holds still")


# TS:889-896 — bio_tell panic drift: while warnDriftT runs every non-pack,
# uncharmed ent drifts 120px away from the player's position (the strike
# epicenter) at sp 40, mood alert. Pack ents stay with the player.
func test_panic_drift_moves_herds_out() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var herd: Dictionary = sim.spawn_ent(null, float(sim.px) + 200.0, float(sim.pz))
	var ally: Dictionary = sim.spawn_ent(null, float(sim.px) + 90.0, float(sim.pz),
			{}, {"pack": true})
	sim.warnDriftT = 3.0  # set directly: update() re-derives it from the chaos warn phase
	sim.update_ents(DT)
	eq(String(herd["mood"]), "alert", "panicking herd alert")
	ok(float(herd["x"]) > float(sim.px) + 200.0, "herd drifted away from the epicenter")
	eq(String(ally["mood"]), "happy", "pack exempt from the drift (follow branch)")
	approx(float(ally["x"]), float(sim.px) + 90.0, "pack follower held position")


# TS:897-903 — the charm target holds still for the minigame: target = own
# position, sp 0, velocity damped exp(-8dt) (then the move block's exp(-5.5dt)
# drag: one tick lands exactly on exp(-13.5dt)), mood alert.
func test_charmed_target_holds_still() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz))
	e["vx"] = 100.0
	sim.charmActive = true
	sim.charmTarget = e
	sim.update_ents(DT)
	eq(String(e["mood"]), "alert", "charm target alert")
	approx(float(e["vx"]), 100.0 * exp(-13.5 * DT), "vx damped exp(-8dt) then exp(-5.5dt)", 1e-6)
	var x0: float = float(e["x"])
	for i in 60:
		sim.update_ents(DT)
	ok(absf(float(e["x"]) - x0) < 10.0, "charm target holds still (slide < 10px total)")


# TS:944-965 + 987-997 — a grazer seeks the nearest food bush within 420,
# depletes it (food -dt, regrow armed 25) and heals 3dt while eating.
func test_bush_depletion_regrows() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 300.0, float(sim.pz))
	e["hp"] = 30.0
	var b: Dictionary = sim.bushes[0]
	b["x"] = float(e["x"])
	b["z"] = float(e["z"]) + 5.0
	b["food"] = 1.0
	b["regrow"] = 0.0
	for i in 3:
		sim.update_ents(DT)
	ok(float(b["food"]) < 1.0, "grazer depleted the bush")
	approx(float(b["regrow"]), 25.0, "regrow armed at 25 on the eat tick")
	approx(float(e["hp"]), 30.0 + 3.0 * 3.0 * DT, "grazer healed 3dt per eat tick")
	ok(float(e["eatT"]) > 0.0, "grazer eatT set")
	# the update() regrow loop re-arms the food 2..5 once the timer lands
	# (walk the grazer off the bush first — an ent inside 26px re-eats the
	# moment the food re-arms, which re-arms regrow at 25 again)
	e["x"] = float(e["x"]) + 100.0
	b["regrow"] = 0.01
	sim.update(DT, _inp({}))
	approx(float(b["regrow"]), 0.0, "regrow counted down to 0")
	ok(float(b["food"]) >= 2.0 and float(b["food"]) <= 5.0, "regrow re-rolled food 2..5")


# TS:865-874 — a baby with eggT grows up: baby flag drops, stats recompute
# from the genome (dropping the wild-speed dampening — TS-true), full heal.
func test_baby_grows_at_eggT() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 400.0, float(sim.pz),
			{}, {"baby": true})
	approx(float(e["maxHp"]), 28.0, "baby maxHp 0.4x at spawn")
	approx(float(e["stats"]["speed"]), 14.4, "baby speed rides the wild dampening")
	e["eggT"] = 0.5
	e["hp"] = 10.0
	for i in 31:
		sim.update_ents(DT)
	eq(bool(e["baby"]), false, "baby flag dropped at eggT <= 0")
	approx(float(e["maxHp"]), 70.0, "maxHp refreshed from the recomputed stats")
	approx(float(e["hp"]), 70.0, "growth fully heals")
	approx(float(e["stats"]["speed"]),
			float(StatsLib.compute_creature_stats(e["genome"])["speed"]),
			"stats recomputed clean (dampening gone)")


# TS:876-880 — stampede lifetime: a non-pack ent despawns when the clock
# lands; a pack ent survives with the clock cleared (TS undefined).
func test_stampede_ent_despawns_at_lifetime_pack_exempt() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var runner: Dictionary = sim.spawn_ent(null, float(sim.px) + 400.0, float(sim.pz))
	runner["lifespanStampede"] = 0.25
	var ally: Dictionary = sim.spawn_ent(null, float(sim.px) + 350.0, float(sim.pz),
			{}, {"pack": true})
	ally["lifespanStampede"] = 0.05
	for i in 4:
		sim.update_ents(DT)
	ok(_ent_by_eid(sim, int(ally["eid"])) != null, "pack ent survives the stampede clock")
	ok(not ally.has("lifespanStampede"), "pack ent clock cleared (TS undefined)")
	for i in 15:
		sim.update_ents(DT)
	ok(_ent_by_eid(sim, int(runner["eid"])) == null, "non-pack stampede ent despawned at lifetime")
	ok(_ent_by_eid(sim, int(ally["eid"])) != null, "pack ally still present")
