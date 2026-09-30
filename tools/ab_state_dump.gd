# A-B state-diff harness — permanent regression instrument for sim-behavior
# refactors. Dumps the FULL unquantized sim state (every ent/pellet/zone
# field at 17 decimals, eco species rows, rng stream states, discovered set,
# tutorial counters) for three fixed crowded scenarios:
#   s1  probe-shape    — 180-step settle, force-spawn to 200 ents (mixed
#                        sizes, area-uniform ≤320), 300 ticks
#   s2  crowded-panic  — s1 + a scripted warned chaos def riding a 2.5 s
#                        warn window (the bio_tell panic path + downstream
#                        separation/eat gathers)
#   s3  kin-kill       — kin_grudge world, 6 kin ents on the player, two
#                        tagged contact-dying (the death sweep pays them at
#                        the top of update_ents → grudge 0→2 mid-tick → the
#                        later same-species ents' grudge reads)
#   s4  lifespan-crowd — 100-ent crowd + 20 ents with 2–4 s lifespans mixed
#                        in; the expiry sweeps fire mid-crowd across 600
#                        ticks (ent-grid dirty flags under removal pressure)
# Uses ONLY the public sim surface that predates the M2 perf work, so the
# same script runs at any commit:
#   godot --headless -s tools/ab_state_dump.gd > ab_<label>.txt
# A/B procedure: dump at the base commit and at HEAD, then diff — an empty
# diff (or one whose every diverging first-cause is an enumerated sanctioned
# numeric class) is the behavior-identity evidence. See PARITY-M2.md §17.
extends SceneTree

const CellSim := preload("res://src/game/cell/cell_sim.gd")
const ContextScript := preload("res://src/game/context.gd")
const ChaosScript := preload("res://src/game/chaos.gd")

const DT := 1.0 / 60.0
const SIZE_MIX := [0.6, 0.85, 1.1, 1.35, 1.6, 1.9, 2.2]
const SETTLE := 180
const S12_TICKS := 300
const S3_TICKS := 6


func _mk(seed_v: int, kin_world := false) -> Dictionary:
	var ctx: Variant = ContextScript.new(seed_v)
	if kin_world:
		# inject the kin_grudge flag BEFORE the sim constructor designates
		# the kin tag (seed_ecology → designate_kin_tag reads the world)
		var traits: Array = []
		if ctx.world.get("traits") is Array:
			traits = ctx.world["traits"]
		traits.append({"effects": [{"kind": "flag", "key": "kin_grudge"}]})
		ctx.world["traits"] = traits
	var hooks: Dictionary = {
		"hud_toast": func(_t, _k, _i): pass,
		"hud_banner": func(_d): pass,
		"hud_float_world": func(_x, _y, _t, _c, _s): pass,
		"audio_play": func(_n, _v, _p): pass,
		"cam_shake": func(_m, _d): pass,
		"fx_burst": func(_x, _y, _n, _o): pass,
		"fx_spawn": func(_o): pass,
		"storyteller_note_chaos_event": func(_p): pass,
		"set_cursor_pointer": func(): pass,
		"context_event": func(_e, _d): pass,
		"shore_travel": func(): pass,
		"game_save_all": func(): pass,
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CellSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx}


func _inp(t: float, i: int) -> Dictionary:
	var pressed: Array = []
	if i % 240 == 120:
		pressed = ["Space"]
	elif i % 300 == 200:
		pressed = ["Digit1"]
	elif i % 360 == 300:
		pressed = ["Digit2"]
	var held: Array = []
	if i % 70 < 25:
		held = ["KeyW"]
	return {
		"mx": 400.0, "my": 300.0,
		"wx": sin(t * 0.9) * 400.0, "wy": cos(t * 0.6) * 400.0,
		"down": i % 30 < 18,
		"keys_held": held, "keys_pressed": pressed,
		"clicked": false, "take_click": false,
	}


func _spawn_budget(sim: Variant, target := 200) -> void:
	var pool: Array = []
	for sp in sim.eco.living():
		if not bool(sp.get("kin", false)):
			pool.append(sp)
	var lcg := 0x51EF
	var spawned := 0
	while int(sim.ents.size()) < target:
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var a := float(lcg) / float(0x7fffffff) * TAU
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var d := sqrt(float(lcg) / float(0x7fffffff)) * 320.0
		var g: Dictionary = pool[spawned % pool.size()]["genome"].duplicate()
		g["size"] = SIZE_MIX[spawned % SIZE_MIX.size()]
		sim.spawn_ent(pool[spawned % pool.size()], sim.px + cos(a) * d, sim.py + sin(a) * d, g)
		spawned += 1


func f(v: float) -> String:
	return String.num(v, 17)


func b(v: bool) -> String:
	return "1" if v else "0"


func _rng_state(r: Variant) -> String:
	return "-" if r == null else str(int(r._s))


func _dump(tag: String, tick: int, sim: Variant) -> void:
	print("SC %s tick=%d px=%s py=%s pvx=%s pvy=%s php=%s pmaxHp=%s invuln=%s biteCd=%s toxinCd=%s electroCd=%s dashCd=%s hurtT=%s eatT=%s dashT=%s nutrition=%s playerSeed=%s moveAngle=%s time=%s ecoTimer=%s spawnTimer=%s nextEid=%d warnDriftT=%s shore=%s" % [
		tag, tick, f(sim.px), f(sim.py), f(sim.pvx), f(sim.pvy), f(sim.php),
		f(sim.pmaxHp), f(sim.invuln), f(sim.biteCd), f(sim.toxinCd),
		f(sim.electroCd), f(sim.dashCd), f(sim.hurtT), f(sim.eatT),
		f(sim.dashT), f(sim.nutrition), f(sim.playerSeed), f(sim.moveAngle),
		f(sim.time), f(sim.ecoTimer), f(sim.spawnTimer), int(sim.nextEid),
		f(sim.warnDriftT), b(sim.shoreAvailable)])
	for j in sim.ents.size():
		var e: Dictionary = sim.ents[j]
		var band: Dictionary = e.get("band", {})
		print("EN %s %d %d eid=%d sp=%s x=%s y=%s vx=%s vy=%s hp=%s maxHp=%s stun=%s lph=%s hurtT=%s eatT=%s biteCd=%s seed=%s wanderT=%s tx=%s ty=%s big=%s sw=%s life=%s press=%s aggr=%s fear=%s" % [
			tag, tick, j, int(e["eid"]), String(e["speciesId"]), f(e["x"]),
			f(e["y"]), f(e["vx"]), f(e["vy"]), f(e["hp"]), f(e["maxHp"]),
			f(e["stun"]), String(e["lastPlayerHit"]), f(e["hurtT"]),
			f(e["eatT"]), f(e["biteCd"]), f(e["seed"]), f(e["wanderT"]),
			f(e["tx"]), f(e["ty"]), b(e["big"]),
			b(e["swarm"]) if e.has("swarm") else "-",
			f(e["lifespan"]) if e.has("lifespan") else "-",
			f(e["pressCd"]) if e.has("pressCd") else "-",
			f(float(band.get("aggression", 1.0))), f(float(band.get("fear", 1.0)))])
	for j in sim.pellets.size():
		var p: Dictionary = sim.pellets[j]
		print("PE %s %d %d x=%s y=%s vx=%s vy=%s kind=%s ttl=%s val=%s" % [
			tag, tick, j, f(p["x"]), f(p["y"]), f(p["vx"]), f(p["vy"]),
			String(p["kind"]), f(p["ttl"]), f(p["val"])])
	for j in sim.zones.size():
		var z: Dictionary = sim.zones[j]
		print("ZO %s %d %d x=%s y=%s r=%s kind=%s ttl=%s dps=%s pulse=%s heal=%s mine=%s src=%s" % [
			tag, tick, j, f(z["x"]), f(z["y"]), f(z["r"]), String(z["kind"]),
			f(z["ttl"]), f(z["dps"]), f(z["pulse"]),
			f(z.get("heal", -1.0)),
			"-" if not z.has("mine") else b(z["mine"]),
			"-" if not z.has("source") else String(z["source"])])
	for j in sim.eco.species.size():
		var sp: Dictionary = sim.eco.species[j]
		print("ECO %s %d %d id=%s pop=%s ext=%s grudge=%s harass=%s kin=%s kinTag=%s tide=%s" % [
			tag, tick, j, String(sp["id"]), f(sp["pop"]), b(sp["extinct"]),
			f(sp.get("grudge", -1.0)), f(sp.get("harass", -1.0)),
			b(sp["kin"]), b(sp.get("kin_tag", false)),
			b(sp.get("tideBorn", false))])
	var mods: PackedStringArray = []
	for k in sim.eco.mods:
		mods.append("%s=%s" % [String(k), f(float(sim.eco.mods[k]))])
	mods.sort()
	print("ECO2 %s %d flora=%s corpses=%s totalEaten=%s mods=%s" % [
		tag, tick, f(sim.eco.flora), f(sim.eco.corpses),
		f(sim.eco.total_eaten), ",".join(mods)])
	var disc: PackedStringArray = []
	for k in sim.discovered:
		disc.append(String(k))
	disc.sort()
	print("RNG %s %d sim=%s eco=%s chaos=%s disc=%s" % [
		tag, tick, _rng_state(sim.rng), _rng_state(sim.eco.rng),
		_rng_state(sim.chaos._rng), ",".join(disc)])
	print("TUT %s %d moved=%s eaten=%d killed=%d editor=%d" % [
		tag, tick, f(sim.tut["moved"]), int(sim.tut["eaten"]),
		int(sim.tut["killed"]), int(sim.tut["editorOpened"])])


func _run_s1() -> void:
	var m := _mk(0x9E37)
	var sim: Variant = m["sim"]
	for i in SETTLE:
		sim.update(DT, _inp(float(i) * DT, i))
		if i % 30 == 29:
			_dump("s1", i, sim)
	_spawn_budget(sim)
	_dump("s1", -1, sim)
	for i in S12_TICKS:
		sim.update(DT, _inp(float(i) * DT, i))
		if i % 10 == 9:
			_dump("s1", i, sim)


func _run_s2() -> void:
	var m := _mk(0x9E37)
	var sim: Variant = m["sim"]
	for i in SETTLE:
		sim.update(DT, _inp(float(i) * DT, i))
	_spawn_budget(sim)
	# scripted warned def (the test_warn_drift_live pattern): a 2.5 s warn
	# window over the crowd → 150 ticks of panic drift + downstream gathers
	var wdef: Dictionary = {
		"id": "abpanic", "name": "AB PANIC", "warn": "incoming…",
		"weight": func(_c): return 1.0,
		"duration": [30.0, 30.0], "cooldown": 999,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [wdef])
	sim.chaos._since_last = 1000.0
	_dump("s2", -1, sim)
	for i in 160:
		sim.update(DT, _inp(float(i) * DT, i))
		if i % 10 == 9:
			_dump("s2", i, sim)


func _run_s3() -> void:
	var m := _mk(0x51EE, true)
	var sim: Variant = m["sim"]
	var kin: Dictionary = {}
	for sp in sim.eco.species:
		if bool(sp.get("kin_tag", false)):
			kin = sp
			break
	print("HEAD s3 kin=%s" % String(kin["id"]))
	for i in 60:
		sim.update(DT, _inp(float(i) * DT, i))
	# 6 kin ents on the player; two tagged contact-dying → the death sweep
	# pays both at the top of update_ents (grudge 0→2 mid-tick) → the later
	# same-species ents' grudge reads decide hunt vs graze for the tick
	var spawned: Array = []
	for j in 6:
		var ang := float(j) * 0.9
		spawned.append(sim.spawn_ent(kin, sim.px + cos(ang) * 40.0,
				sim.py + sin(ang) * 40.0))
	spawned[0]["hp"] = -0.5
	spawned[0]["lastPlayerHit"] = "contact"
	spawned[1]["hp"] = -0.5
	spawned[1]["lastPlayerHit"] = "contact"
	_dump("s3", -1, sim)
	for i in S3_TICKS:
		sim.update(DT, _inp(float(i) * DT, i))
		_dump("s3", i, sim)


func _run_s4() -> void:
	var m := _mk(0x51F0)
	var sim: Variant = m["sim"]
	for i in SETTLE:
		sim.update(DT, _inp(float(i) * DT, i))
	_spawn_budget(sim, 100)
	# 20 temporary ents (lifespan 2–4 s) mixed into the crowd — they expire
	# between ticks 120 and 240, each expiry sweeping the ent arrays under
	# full grid/mirror load
	var pool: Array = []
	for sp in sim.eco.living():
		if not bool(sp.get("kin", false)):
			pool.append(sp)
	var lcg := 0xBEEF
	for j in 20:
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var a := float(lcg) / float(0x7fffffff) * TAU
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var d := sqrt(float(lcg) / float(0x7fffffff)) * 320.0
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var g: Dictionary = pool[j % pool.size()]["genome"].duplicate()
		g["size"] = SIZE_MIX[j % SIZE_MIX.size()]
		sim.spawn_ent(pool[j % pool.size()], sim.px + cos(a) * d,
				sim.py + sin(a) * d, g, {"lifespan": 2.0 + float(j % 3)})
	_dump("s4", -1, sim)
	for i in 600:
		sim.update(DT, _inp(float(i) * DT, i))
		if i % 30 == 29:
			_dump("s4", i, sim)


func _initialize() -> void:
	print("AB_DUMP_BEGIN")
	_run_s1()
	_run_s2()
	_run_s3()
	_run_s4()
	print("AB_DUMP_END")
	quit(0)
