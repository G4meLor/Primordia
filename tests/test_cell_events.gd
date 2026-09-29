# Tests for game/cell/cell_events.gd + the chaos wiring in game/cell/cell_sim.gd
# (Task 5): the 8 baseline defs + 3 world-parameterized variants (TS
# cellEvents.ts), the event helper bodies (TS CellStage.ts:1203-1381), the
# update_chaos ctx/hooks, the C1 deck rebuild, the live warn_drift_t seam and
# the eco-batch outcome handling. Path-based extends + preload-by-path per the
# -s runner.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const RngLib := preload("res://src/core/rng.gd")
const ChaosScript := preload("res://src/game/chaos.gd")
const CellEvents := preload("res://src/game/cell/cell_events.gd")
const CellSim := preload("res://src/game/cell/cell_sim.gd")
const GenomeLib := preload("res://src/evo/genome.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE

# Synthetic worlds (a real derive draws 4-6 traits — tests pin exact decks).
# temperament is set explicitly: a traitless world still falls back to the
# seed's hidden bucket (mirror_bucket), which must not be "lean" here.
const W_TRAITLESS := {"seed": 11, "traits": [], "turns": [], "firedTurns": {},
		"revealed": {}, "comboFired": {}, "timers": {}, "temperament": "cradle"}
const W_TOXIN := {"seed": 12, "traits": [{"effects": [{"kind": "flag", "key": "toxin_rain_cell"}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "cradle"}
const W_SURGE := {"seed": 14, "traits": [{"effects": [{"kind": "num", "key": "herb_drain_mult", "value": 1.5}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "cradle"}
const W_LEAN := {"seed": 15, "traits": [], "turns": [], "firedTurns": {}, "revealed": {},
		"comboFired": {}, "timers": {}, "temperament": "lean"}
const W_SPEC := {"seed": 16, "traits": [{"effects": [{"kind": "num", "key": "speciation_mult", "value": 250.0}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "cradle"}


# ---- fixtures ------------------------------------------------------------------

func _mk_sim(world: Dictionary = W_TRAITLESS, hooks_extra: Dictionary = {},
		seed_v: int = SEED) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.world = world.duplicate(true)  # synthetic world BEFORE sim construction
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
	hooks.merge(hooks_extra, true)
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CellSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


func _def(deck: Array, id: String) -> Variant:
	for d in deck:
		if String(d["id"]) == id:
			return d
	return null


func _heard(rec: Dictionary, name: String) -> bool:
	for a in rec["audio"]:
		if a[0] == name:
			return true
	return false


func _audio_vols(rec: Dictionary, name: String) -> Array:
	var out: Array = []
	for a in rec["audio"]:
		if a[0] == name:
			out.append(a[1])
	return out


# ---- the deck: make_cell_chaos_events -------------------------------------------


func test_traitless_world_gets_exactly_the_baseline() -> void:
	eq(CellEvents.make_cell_chaos_events(W_TRAITLESS).size(), 8, "factory: traitless = 8 defs")
	var m := _mk_sim()
	var deck: Array = m["sim"].chaos.defs
	eq(deck.size(), 8, "sim constructor deck: traitless = 8 defs")
	var ids: Array = []
	for d in deck:
		ids.append(d["id"])
	eq(ids, ["meteor", "bloom", "redtide", "swarm", "bigbro", "vents", "glitch", "mutationwave"],
			"TS baseline order")


func test_variant_defs_gate_on_the_world() -> void:
	var tdeck: Array = CellEvents.make_cell_chaos_events(W_TOXIN)
	eq(tdeck.size(), 9, "toxin world adds toxin_clouds")
	var tc: Dictionary = _def(tdeck, "toxin_clouds")
	ok(tc != null, "toxin_clouds present")
	eq(String(tc["name"]), "☣ TOXIN CLOUDS", "toxin_clouds name")
	ok(tc.has("tick"), "toxin_clouds carries a tick")
	ok(not tc.has("warn"), "toxin_clouds is a surprise hit (no warn)")
	eq(CellEvents.make_cell_chaos_events(W_TRAITLESS).size(), 8, "traitless has no toxin_clouds")

	var sdeck: Array = CellEvents.make_cell_chaos_events(W_SURGE)
	eq(sdeck.size(), 9, "hungry_bloom world adds algae_surge")
	var asg: Dictionary = _def(sdeck, "algae_surge")
	ok(asg != null, "algae_surge present")
	eq(String(asg["name"]), "🌿 RUNAWAY BLOOM", "algae_surge name")
	ok(not asg.has("warn"), "algae_surge has no warn")

	var ldeck: Array = CellEvents.make_cell_chaos_events(W_LEAN)
	eq(ldeck.size(), 9, "lean world adds the bloom mirror face")
	var mirrors: Array = []
	for d in ldeck:
		if String(d["id"]) == "bloom" and d.has("mirrorOf"):
			mirrors.append(d)
	eq(mirrors.size(), 1, "exactly one bloom mirror def")
	if mirrors.size() == 1:
		eq(String(mirrors[0]["mirrorOf"]), "bloom", "mirrorOf bloom")
		eq(String(mirrors[0]["name"]), "🌿 ALGAL BLOOM", "mirror keeps the base name")
		ok(not mirrors[0].has("warn"), "the mirror face is a surprise hit (TS verbatim)")
	var none: Array = CellEvents.make_cell_chaos_events(W_TRAITLESS)
	for d in none:
		ok(not d.has("mirrorOf"), "traitless world carries no mirror face")


func test_def_constants_verbatim() -> void:
	var deck: Array = CellEvents.make_cell_chaos_events(W_TRAITLESS)
	# id → [duration, cooldown, name, warn?]
	var want := {
		"meteor": {"dur": [0.1, 0.1], "cd": 35, "name": "☄ METEOR STRIKE",
				"warn": "The water flickers. Something falls from the sky…"},
		"bloom": {"dur": [8.0, 14.0], "cd": 30, "name": "🌿 ALGAL BLOOM"},
		"redtide": {"dur": [18.0, 26.0], "cd": 40, "name": "🩸 RED TIDE",
				"warn": "The water turns warm and smells of iron…"},
		"swarm": {"dur": [30.0, 30.0], "cd": 45, "name": "🦈 FEEDING FRENZY",
				"warn": "Tiny teeth glint in the dark…"},
		"bigbro": {"dur": [26.0, 26.0], "cd": 70, "name": "👁 THE OLD ONE WAKES",
				"warn": "The seafloor trembles beneath something vast…"},
		"vents": {"dur": [12.0, 20.0], "cd": 50, "name": "🌋 VENT ERUPTION"},
		"glitch": {"dur": [12.0, 16.0], "cd": 90, "name": "🌀 THE GLITCH",
				"warn": "R̶e̶a̶l̶i̶t̶y̶ ̶b̶u̶f̶f̶e̶r̶i̶n̶g̶…"},
		"mutationwave": {"dur": [0.1, 0.1], "cd": 60, "name": "🧪 MUTATION WAVE",
				"warn": "DNA hums at a frequency you feel in your membrane…"},
	}
	for id in want:
		var d: Dictionary = _def(deck, id)
		ok(d != null, "def %s present" % id)
		if d == null:
			continue
		var w: Dictionary = want[id]
		var dur: Array = d["duration"]
		eq(dur.size(), 2, "%s duration pair" % id)
		approx(float(dur[0]), float(w["dur"][0]), "%s duration lo" % id, 1e-9)
		approx(float(dur[1]), float(w["dur"][1]), "%s duration hi" % id, 1e-9)
		eq(int(d["cooldown"]), int(w["cd"]), "%s cooldown" % id)
		eq(String(d["name"]), String(w["name"]), "%s name verbatim" % id)
		if w.has("warn"):
			eq(String(d["warn"]), String(w["warn"]), "%s warn verbatim" % id)
		else:
			ok(not d.has("warn"), "%s has no warn" % id)
		ok(d["weight"] is Callable, "%s weight is a Callable" % id)
		ok(d["apply"] is Callable, "%s apply is a Callable" % id)
	# glitch carries the end body (BASE_GAP restore)
	ok(_def(deck, "glitch").has("end"), "glitch has end")
	ok(not _def(deck, "meteor").has("end"), "meteor has no end")


func test_weight_formulas() -> void:
	var deck: Array = CellEvents.make_cell_chaos_events(W_TRAITLESS)
	var c := {"chaos": 0.2, "karma": 0.5, "stageTime": 0.0}
	approx(float(_def(deck, "meteor")["weight"].call(c)), 0.8, "meteor 0.6+chaos", 1e-12)
	approx(float(_def(deck, "bloom")["weight"].call(c)), 0.7, "bloom 0.8-karma*0.2", 1e-12)
	approx(float(_def(deck, "swarm")["weight"].call(c)), 0.9, "swarm 0.7+chaos", 1e-12)
	approx(float(_def(deck, "mutationwave")["weight"].call(c)), 0.72, "mutationwave 0.6+chaos*0.6", 1e-12)
	approx(float(_def(deck, "vents")["weight"].call(c)), 0.5, "vents const 0.5", 1e-12)
	var hot := {"chaos": 0.4, "karma": 0.0, "stageTime": 0.0}
	approx(float(_def(deck, "bigbro")["weight"].call(hot)), 0.9, "bigbro hot 0.5+chaos", 1e-12)
	approx(float(_def(deck, "bigbro")["weight"].call(c)), 0.05, "bigbro cold 0.05", 1e-12)
	var wild := {"chaos": 0.6, "karma": 0.0, "stageTime": 0.0}
	approx(float(_def(deck, "glitch")["weight"].call(wild)), 1.3, "glitch hot 0.7+chaos", 1e-12)
	approx(float(_def(deck, "glitch")["weight"].call(c)), 0.02, "glitch cold 0.02", 1e-12)
	var rt := {"chaos": 0.5, "karma": 0.0, "stageTime": 0.0}
	approx(float(_def(deck, "redtide")["weight"].call(rt)), 0.9, "redtide 0.5+chaos*0.8", 1e-12)

	# toxin_clouds: weight 5 only when the (toxin-gated) def exists AND chaos > 0.35
	var tdeck: Array = CellEvents.make_cell_chaos_events(W_TOXIN)
	var tc: Dictionary = _def(tdeck, "toxin_clouds")
	approx(float(tc["weight"].call({"chaos": 0.4, "karma": 0.0})), 5.0, "toxin_clouds hot 5", 1e-12)
	approx(float(tc["weight"].call({"chaos": 0.35, "karma": 0.0})), 0.0, "toxin_clouds at 0.35 is 0 (strict >)", 1e-12)

	# algae_surge: 0.9 - karma*0.2
	var sdeck: Array = CellEvents.make_cell_chaos_events(W_SURGE)
	approx(float(_def(sdeck, "algae_surge")["weight"].call({"chaos": 0.0, "karma": 0.5})),
			0.8, "algae_surge 0.9-karma*0.2", 1e-12)

	# bloom mirror: 1.2 only when the queued mirrors include bloom
	var ldeck: Array = CellEvents.make_cell_chaos_events(W_LEAN)
	var bm = null
	for d in ldeck:
		if String(d["id"]) == "bloom" and d.has("mirrorOf"):
			bm = d
	approx(float(bm["weight"].call({"mirrors": ["bloom"]})), 1.2, "mirror queued 1.2", 1e-12)
	approx(float(bm["weight"].call({"mirrors": []})), 0.0, "mirror unqueued 0", 1e-12)
	approx(float(bm["weight"].call({})), 0.0, "missing mirrors key reads 0", 1e-12)


# ---- meteor ---------------------------------------------------------------------


func test_meteor_apply_schedules_impact() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "meteor")
	def["apply"].call(sim, sim.rng)
	# the target ring
	eq(sim.zones.size(), 1, "one meteorTarget zone")
	var z: Dictionary = sim.zones[0]
	eq(String(z["kind"]), "meteorTarget", "zone kind")
	approx(float(z["r"]), 150.0, "ring r 150", 1e-9)
	approx(float(z["ttl"]), 2.5, "ring ttl 2.5", 1e-9)
	approx(float(z["dps"]), 0.0, "ring dps 0", 1e-9)
	# the strike lands 80..420 out of the player
	var d: float = Vector2(z["x"], z["y"]).distance_to(Vector2(sim.px, sim.py))
	ok(d >= 80.0 - 1e-6 and d < 420.0 + 1e-6, "strike distance 80..420 (%f)" % d)
	# the impact rides the stage clock (after(2.5, ...))
	eq(sim.timers.size(), 1, "impact scheduled")
	approx(float(sim.timers[0]["left"]), 2.5, "impact at 2.5s", 1e-9)
	# advance past 2.5s of stage time — the impact fires
	var chaos0: float = float(ctx.chaos)
	var dna_pellets := 0
	for p in sim.pellets:
		if String(p["kind"]) == "dna":
			dna_pellets += 1
	for i in 151:
		sim.update(DT, _inp())
	ok(_heard(rec, "boom"), "impact plays boom")
	var ring := false
	for s in rec["spawns"]:
		if String(s.get("kind", "")) == "ring":
			ring = true
	ok(ring, "impact spawns the ring fx")
	for p in sim.pellets:
		if String(p["kind"]) == "dna":
			dna_pellets += 1
	eq(dna_pellets, 6, "6 DNA debris pellets")
	approx(float(ctx.chaos), chaos0 + 0.04, "impact chaos +0.04", 1e-12)


func test_meteor_impact_falloff_player_ent_and_debris() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	# scripted geometry: strike at px+150; ent A at px+50 (d=100 → 30 dmg),
	# ent B at px+400 (d=250 → untouched); player d=150 → 11.25 dmg
	sim.invuln = 0.0
	var ea: Dictionary = sim.spawn_ent(null, sim.px + 50.0, sim.py)
	var eb: Dictionary = sim.spawn_ent(null, sim.px + 400.0, sim.py)
	var hp_a: float = float(ea["hp"])
	var hp_b: float = float(eb["hp"])
	var php0: float = sim.php
	var pel0: int = sim.pellets.size()
	var chaos0: float = float(m["ctx"].chaos)
	sim.meteor_impact(sim.px + 150.0, sim.py)
	approx(hp_a - float(ea["hp"]), 30.0, "ent falloff 60*(1-d/200)", 1e-6)
	approx(hp_b - float(eb["hp"]), 0.0, "ent beyond 200 untouched", 1e-9)
	approx(float(ea["hurtT"]), 1.0, "ent hurtT 1", 1e-9)
	approx(php0 - sim.php, 11.25, "player falloff 45*(1-d/200)", 1e-6)
	approx(float(sim.hurtT), 1.0, "player hurtT 1", 1e-9)
	# audio/camera/fx hook routing
	eq(_audio_vols(rec, "boom"), [1.0], "boom at vol 1")
	ok([14.0, 0.8] in rec["shakes"], "camShake 14/0.8")
	var burst50 := false
	for b in rec["bursts"]:
		if int(b[2]) == 50:
			burst50 = true
	ok(burst50, "fx burst of 50")
	# DNA debris: 6 pellets, val 12, ttl 45, vel 0, r 10..90 of the strike
	eq(sim.pellets.size(), pel0 + 6, "6 debris pellets")
	var sx: float = sim.px + 150.0
	for i in range(sim.pellets.size() - 6, sim.pellets.size()):
		var p: Dictionary = sim.pellets[i]
		eq(String(p["kind"]), "dna", "debris kind")
		eq(int(p["val"]), 12, "debris val 12")
		approx(float(p["ttl"]), 45.0, "debris ttl 45", 1e-9)
		approx(float(p["vx"]), 0.0, "debris vx 0", 1e-9)
		approx(float(p["vy"]), 0.0, "debris vy 0", 1e-9)
		var dd: float = Vector2(p["x"], p["y"]).distance_to(Vector2(sx, sim.py))
		ok(dd >= 10.0 - 1e-6 and dd < 90.0 + 1e-6, "debris radius 10..90 (%f)" % dd)
	approx(float(m["ctx"].chaos), chaos0 + 0.04, "impact chaos +0.04", 1e-12)


func test_meteor_impact_kills_and_invuln_guards() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# a dying ent in the blast radius is finished (kill_ent pays)
	var e: Dictionary = sim.spawn_ent(null, sim.px + 150.0, sim.py)
	e["hp"] = 10.0
	var pel0: int = sim.pellets.size()
	sim.invuln = 0.0
	sim.meteor_impact(sim.px + 150.0, sim.py)
	approx(float(e["hp"]), -1.0, "kill_ent marked hp -1", 1e-9)
	eq(String(e["lastPlayerHit"]), "", "kill_ent cleared the pay tag")
	# meat pellets 1 + floor(size=1) = 2, plus 6 dna debris
	var meat := 0
	for p in sim.pellets:
		if String(p["kind"]) == "meat":
			meat += 1
	eq(meat, 2, "corpse pays its meat")
	eq(sim.pellets.size(), pel0 + 8, "2 meat + 6 dna")
	# invuln shields the player
	sim.php = 100.0
	sim.hurtT = 0.0
	sim.invuln = 1.0
	sim.meteor_impact(sim.px + 10.0, sim.py)
	approx(sim.php, 100.0, "invuln blocks meteor damage", 1e-9)


# ---- bloom / blight --------------------------------------------------------------


func test_bloom_flora_cap_and_sprinkle() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.eco.flora = 10.0
	var pel0: int = sim.pellets.size()
	sim.bloom()
	approx(float(sim.eco.flora), 39.0, "flora *1.9+20", 1e-9)
	eq(sim.pellets.size(), pel0 + 30, "30 pellet sprinkle")
	for i in range(pel0, sim.pellets.size()):
		var p: Dictionary = sim.pellets[i]
		eq(String(p["kind"]), "plant", "sprinkle is plant")
		eq(int(p["val"]), 2, "sprinkle val 2")
		approx(float(p["ttl"]), 60.0, "sprinkle ttl 60", 1e-9)
		ok(absf(float(p["vx"])) < 10.0 and absf(float(p["vy"])) < 10.0, "sprinkle vel ±10")
		var dd: float = Vector2(p["x"], p["y"]).distance_to(Vector2(sim.px, sim.py))
		ok(dd >= 100.0 - 1e-6 and dd < 700.0 + 1e-6, "sprinkle radius 100..700 (%f)" % dd)
	# the cap holds
	sim.eco.flora = 90.0
	sim.bloom()
	approx(float(sim.eco.flora), float(sim.eco.flora_cap), "flora capped at floraCap", 1e-9)


func test_blight_mirror_body() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.eco.flora = 80.0
	var pel0: int = sim.pellets.size()
	sim.blight()
	approx(float(sim.eco.flora), 28.0, "blight *0.35", 1e-9)
	eq(sim.pellets.size(), pel0 + 30, "same 30-pellet sprinkle")
	# the floor: a collapsed flora rests at 12
	sim.eco.flora = 5.0
	sim.blight()
	approx(float(sim.eco.flora), 12.0, "blight floor 12", 1e-9)


# ---- redtide / toxin clouds ------------------------------------------------------


func test_redtide_zones() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "redtide")
	def["apply"].call(sim, sim.rng)
	eq(sim.zones.size(), 3, "3 red tide zones")
	for z in sim.zones:
		eq(String(z["kind"]), "toxin", "zone kind")
		eq(String(z["source"]), "redtide", "source redtide")
		approx(float(z["dps"]), 7.0, "dps 7", 1e-9)
		ok(float(z["r"]) >= 90.0 - 1e-6 and float(z["r"]) < 150.0 + 1e-6,
				"r 90..150 (%f)" % float(z["r"]))
		ok(float(z["ttl"]) >= 18.0 - 1e-6 and float(z["ttl"]) < 26.0 + 1e-6,
				"ttl 18..26 (%f)" % float(z["ttl"]))
		ok(not z.has("mine"), "not the player's zone")
		var dd: float = Vector2(z["x"], z["y"]).distance_to(Vector2(sim.px, sim.py))
		ok(dd >= 150.0 - 1e-6 and dd < 500.0 + 1e-6, "zone 150..500 out (%f)" % dd)
	eq(_audio_vols(rec, "toxin"), [0.7], "toxin audio 0.7")


func test_toxin_clouds_def_and_drift_homing() -> void:
	var m := _mk_sim(W_TOXIN)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "toxin_clouds")
	def["apply"].call(sim, sim.rng)
	eq(sim.zones.size(), 2, "2 clouds")
	for z in sim.zones:
		eq(String(z["source"]), "clouds", "source clouds")
		approx(float(z["dps"]), 3.0, "soft dps 3", 1e-9)
		approx(float(z["ttl"]), 26.0, "long-lived ttl 26", 1e-9)
		ok(float(z["r"]) >= 120.0 - 1e-6 and float(z["r"]) < 170.0 + 1e-6,
				"wide r 120..170 (%f)" % float(z["r"]))
	eq(_audio_vols(rec, "toxin"), [0.5], "toxin audio 0.5")

	# drift homing: ONLY the variant's own clouds move — redtide and mine stay
	sim.zones.clear()
	sim.add_toxin_zone(sim.px + 100.0, sim.py, 120.0, 3.0, 26.0, "clouds")
	sim.add_toxin_zone(sim.px + 100.0, sim.py + 50.0, 100.0, 7.0, 20.0, "redtide")
	sim.zones.append({"x": sim.px + 30.0, "y": sim.py, "r": 60.0, "kind": "toxin",
			"ttl": 6.0, "dps": 8.0, "pulse": 0.0, "mine": true})
	sim.zones.append({"x": sim.px + 20.0, "y": sim.py, "r": 60.0, "kind": "toxin",
			"ttl": 6.0, "dps": 8.0, "pulse": 0.0, "mine": true, "source": "clouds"})
	var dt := 0.5
	sim.drift_toxin_clouds(dt)
	var cloud: Dictionary = sim.zones[0]
	approx(float(cloud["x"]), sim.px + 93.0, "cloud homes 14px/s x", 1e-6)
	approx(float(cloud["y"]), sim.py, "cloud homes 14px/s y", 1e-6)
	var rt: Dictionary = sim.zones[1]
	approx(float(rt["x"]), sim.px + 100.0, "redtide keeps its static zones x", 1e-9)
	approx(float(rt["y"]), sim.py + 50.0, "redtide keeps its static zones y", 1e-9)
	var mine: Dictionary = sim.zones[2]
	approx(float(mine["x"]), sim.px + 30.0, "mine never homes x", 1e-9)
	var mine_cloud: Dictionary = sim.zones[3]
	approx(float(mine_cloud["x"]), sim.px + 20.0, "my own cloud never homes x", 1e-9)
	# inside the 60px floor: no move
	sim.zones.clear()
	sim.add_toxin_zone(sim.px + 60.0, sim.py, 120.0, 3.0, 26.0, "clouds")
	sim.drift_toxin_clouds(1.0)
	approx(float(sim.zones[0]["x"]), sim.px + 60.0, "d <= 60 holds position", 1e-9)
	# the def's tick routes to drift_toxin_clouds
	sim.zones.clear()
	sim.add_toxin_zone(sim.px + 100.0, sim.py, 120.0, 3.0, 26.0, "clouds")
	def["tick"].call(sim, 0.0, dt)
	approx(float(sim.zones[0]["x"]), sim.px + 93.0, "def tick drifts the clouds", 1e-6)


# ---- swarm / bigbro / mutation wave ------------------------------------------------


func test_swarm_ring() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.spawn_swarm()
	eq(sim.ents.size(), 4, "4 swarm ents")
	var genomes: Array = []
	for i in 4:
		var e: Dictionary = sim.ents[i]
		var a: float = (float(i) / 7.0) * TAU
		approx(float(e["x"]), sim.px + cos(a) * 620.0, "swarm x (i/7)*TAU r 620", 1e-6)
		approx(float(e["y"]), sim.py + sin(a) * 620.0, "swarm y (i/7)*TAU r 620", 1e-6)
		ok(bool(e.get("swarm", false)), "swarm flagged")
		approx(float(e["lifespan"]), 30.0, "lifespan 30", 1e-9)
		genomes.append(e["genome"])
	for i in range(1, genomes.size()):
		eq(genomes[i], genomes[0], "all four share one mutated genome")
	# the def routes audio
	var def: Dictionary = _def(sim.chaos.defs, "swarm")
	def["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "alarm"), [0.6], "swarm apply plays alarm 0.6")
	eq(sim.ents.size(), 8, "a second ring spawned")


func test_big_brother() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var e: Dictionary = sim.spawn_big_brother()
	ok(e != null, "returns the spawned ent")
	approx(float(e["lifespan"]), 26.0, "lifespan 26", 1e-9)
	# float64 distance (Vector2 rounds at this magnitude)
	var ddx: float = float(e["x"]) - sim.px
	var ddy: float = float(e["y"]) - sim.py
	approx(sqrt(ddx * ddx + ddy * ddy), 900.0, "spawns 900 out", 1e-9)
	# size max(2.0, player*1.6) — seed-pinned: the 1.5% size mutation does not
	# roll on this stream (deterministic per seed either way)
	approx(float(e["genome"]["size"]), 2.0, "size max(2.0, player*1.6)", 1e-9)
	eq(rec["toasts"].size(), 1, "one toast")
	if rec["toasts"].size() == 1:
		eq(String(rec["toasts"][0][0]), "SOMETHING HUGE has noticed you", "toast text")
		eq(String(rec["toasts"][0][1]), "bad", "toast kind")
		eq(String(rec["toasts"][0][2]), "👁", "toast icon")
	# the def's apply adds the camShake 6/1
	var def: Dictionary = _def(sim.chaos.defs, "bigbro")
	def["apply"].call(sim, sim.rng)
	ok([6.0, 1.0] in rec["shakes"], "camShake 6/1 via def apply")


func test_mutation_wave() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	var chaos0: float = float(ctx.chaos)
	var n: int = sim.spawn_mutant_wave()
	ok(n >= 2 and n <= 3, "2-3 mutants (got %d)" % n)
	eq(sim.ents.size(), n, "one ent per mutant")
	eq(rec["toasts"].size(), n, "one toast per mutant")
	for t in rec["toasts"]:
		ok(String(t[0]).begins_with("A mutant ") and String(t[0]).ends_with(" crawls out of the noise"),
				"mutant toast shape (%s)" % String(t[0]))
		eq(String(t[1]), "chaos", "toast kind")
		eq(String(t[2]), "🧪", "toast icon")
	for e in sim.ents:
		approx(float(e["lifespan"]), 40.0, "lifespan 40", 1e-9)
		var dd: float = Vector2(e["x"], e["y"]).distance_to(Vector2(sim.px, sim.py))
		ok(dd >= 400.0 - 1e-6 and dd <= 700.0 + 1e-6, "mutant ring 400..700 (%f)" % dd)
	approx(float(ctx.chaos), chaos0 + 0.02, "chaos +0.02", 1e-12)
	# the def routes audio and spawns its own wave
	var def: Dictionary = _def(sim.chaos.defs, "mutationwave")
	var ents0: int = sim.ents.size()
	def["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "spawn"), [0.8], "mutationwave apply plays spawn 0.8")
	ok(sim.ents.size() > ents0, "the apply spawned its own wave")


func test_mutation_wave_needs_wild_species() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	for sp in sim.eco.living():
		sp["kin"] = true  # kin lines are exempt
	eq(sim.spawn_mutant_wave(), 0, "kin-only eco → no wave")
	eq(sim.ents.size(), 0, "nothing spawned")


# ---- vents -----------------------------------------------------------------------


func test_vent_params_and_fifo_cap() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	for i in 7:
		sim.add_vent(float(i) * 10.0, 0.0)
	eq(sim.zones.size(), 6, "vent cap 6")
	var xs: Array = []
	for z in sim.zones:
		eq(String(z["kind"]), "vent", "zone kind")
		approx(float(z["r"]), 80.0, "r 80", 1e-9)
		approx(float(z["ttl"]), 240.0, "ttl 240", 1e-9)
		approx(float(z["heal"]), 6.0, "heal 6", 1e-9)
		approx(float(z["dps"]), 0.0, "dps 0", 1e-9)
		ok(float(z["pulse"]) >= 0.0 and float(z["pulse"]) < 9.0, "pulse 0..9")
		xs.append(float(z["x"]))
	eq(xs, [10.0, 20.0, 30.0, 40.0, 50.0, 60.0], "FIFO eviction (oldest vent cools first)")
	# the def's apply drops 2 vents and plays boom 0.5 — at the cap the two
	# oldest cool out (FIFO), so the total stays 6
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "vents")
	def["apply"].call(sim, sim.rng)
	eq(sim.zones.size(), 6, "the cap holds under apply")
	var xs2: Array = []
	for z in sim.zones:
		xs2.append(float(z["x"]))
	eq(xs2.slice(0, 4), [30.0, 40.0, 50.0, 60.0], "the two oldest vents cooled out")
	eq(_audio_vols(rec, "boom"), [0.5], "vents apply plays boom 0.5")


# ---- algae surge -------------------------------------------------------------------


func test_algae_surge() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var eco: Variant = sim.eco
	var g: Dictionary = GenomeLib.default_genome()
	g["diet"] = "herbivore"
	var h1: Dictionary = eco.add_species(g, 10.0)
	var h2: Dictionary = eco.add_species(g.duplicate(), 60.0)
	h2["kin"] = true
	var h3: Dictionary = eco.add_species(g.duplicate(), 55.0)
	var gc: Dictionary = g.duplicate()
	gc["diet"] = "carnivore"
	var c1: Dictionary = eco.add_species(gc, 50.0)
	eco.flora = 10.0
	var pel0: int = sim.pellets.size()
	sim.algae_surge()
	approx(float(h1["pop"]), 21.0, "grazer boom min(90, *1.8+3)", 1e-9)
	approx(float(h3["pop"]), 90.0, "grazer boom caps at 90", 1e-9)
	approx(float(h2["pop"]), 60.0, "kin lines are exempt", 1e-9)
	approx(float(c1["pop"]), 50.0, "carnivores untouched", 1e-9)
	approx(float(eco.flora), 39.0, "the base bloom ran first", 1e-9)
	eq(sim.pellets.size(), pel0 + 50, "30 bloom + 20 surge pellets")
	# the surge pellets: vel 0 (the windfall settles), plant, ttl 60, val 2
	for i in range(sim.pellets.size() - 20, sim.pellets.size()):
		var p: Dictionary = sim.pellets[i]
		eq(String(p["kind"]), "plant", "surge pellet kind")
		eq(int(p["val"]), 2, "surge pellet val")
		approx(float(p["ttl"]), 60.0, "surge pellet ttl", 1e-9)
		approx(float(p["vx"]), 0.0, "surge vx 0", 1e-9)
		approx(float(p["vy"]), 0.0, "surge vy 0", 1e-9)
		var dd: float = Vector2(p["x"], p["y"]).distance_to(Vector2(sim.px, sim.py))
		ok(dd >= 100.0 - 1e-6 and dd < 700.0 + 1e-6, "surge radius 100..700 (%f)" % dd)
	# the def routes audio
	var sdeck: Array = CellEvents.make_cell_chaos_events(W_SURGE)
	var rec: Dictionary = m["rec"]
	_def(sdeck, "algae_surge")["apply"].call(sim, sim.rng)
	eq(_audio_vols(rec, "spawn"), [0.8], "algae_surge apply plays spawn 0.8")


# ---- glitch gap + tribute ----------------------------------------------------------


func test_glitch_gap_cycle() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var def: Dictionary = _def(sim.chaos.defs, "glitch")
	def["apply"].call(sim, sim.rng)
	approx(float(sim.chaos.gap), 10.0, "gap 10 during the glitch", 1e-9)
	def["end"].call(sim)
	approx(float(sim.chaos.gap), float(ChaosScript.BASE_GAP), "BASE_GAP restore", 1e-9)


func test_glitch_end_tribute_through_update_chaos() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	# a dedicated scheduler carrying only the real glitch def
	var gdef: Dictionary = _def(CellEvents.make_cell_chaos_events(ctx.world), "glitch")
	sim.chaos = ChaosScript.new(sim.rng.branch(), [gdef])
	sim.chaos._since_last = 1000.0
	var dna0: float = float(ctx.dna)
	sim.update_chaos(DT)  # spawns into the warn phase
	# onWarn: danger banner (ttl 2.4) + alarm — only because def.warn exists
	ok(rec["banners"].size() >= 1, "warn banner")
	var wb: Dictionary = rec["banners"][0]
	eq(String(wb["title"]), "R̶e̶a̶l̶i̶t̶y̶ ̶b̶u̶f̶f̶e̶r̶i̶n̶g̶…", "warn text verbatim")
	eq(String(wb["kind"]), "danger", "warn kind")
	approx(float(wb["ttl"]), 2.4, "warn ttl 2.4", 1e-9)
	ok(_heard(rec, "alarm"), "alarm audio")
	# ride out the warn window + duration; the tribute lands on end
	var tributed := false
	for i in 1300:
		sim.update_chaos(DT)
		for t in rec["toasts"]:
			if String(t[0]) == "The Glitch pays tribute: +40 DNA":
				tributed = true
		if tributed:
			break
	ok(tributed, "glitch end tribute toast")
	ok(_heard(rec, "warp"), "glitch apply plays warp 0.9")
	eq(_audio_vols(rec, "warp"), [0.9], "warp vol 0.9")
	approx(float(ctx.dna), dna0 + 40.0, "+40 DNA tribute", 1e-9)
	var tb = null
	for t in rec["toasts"]:
		if String(t[0]) == "The Glitch pays tribute: +40 DNA":
			tb = t
	if tb != null:
		eq(String(tb[1]), "reward", "tribute kind")
		eq(String(tb[2]), "🌀", "tribute icon")
	approx(float(sim.chaos.gap), float(ChaosScript.BASE_GAP), "BASE_GAP restored after end", 1e-9)
	# the glitch is not mirrorable: its end never queues a mirror
	eq(sim.mirrorLedger.queued(), [], "glitch end does not queue")
	# onApply rode the conversion: banner + chaos +0.03 + storyteller note
	var applied := false
	for b in rec["banners"]:
		if String(b.get("title", "")) == "🌀 THE GLITCH" and String(b.get("kind", "")) == "chaos":
			applied = true
	ok(applied, "apply banner {title, kind chaos}")
	eq(rec["notes"].size(), 1, "one storyteller note at apply")
	approx(float(rec["notes"][0]), float(ctx.playtime), "note carries playtime", 1e-9)


# ---- update_chaos hook wiring ------------------------------------------------------


func test_on_end_queues_bloom_mirror_and_on_fired_clears() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# a scripted bloom-like def: ends → maybe_queue(rng, "bloom", "bloom")
	var bloomish: Dictionary = {
		"id": "bloom", "name": "🌿 ALGAL BLOOM",
		"weight": func(_c): return 1.0,
		"duration": [0.1, 0.1], "cooldown": 30,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [bloomish])
	sim.chaos._since_last = 1000.0
	sim.update_chaos(DT)  # spawn tick (draws the duration)
	# pin the maybe_queue roll: find a state whose first next() < 0.25
	var q_state := -1
	for s in range(1, 100000):
		var probe_rng: Variant = RngLib.new_from(s)
		if probe_rng.next() < 0.25:
			q_state = s
			break
	ok(q_state > 0, "probe state found")
	# the 0.1s duration ends on tick ~6 — re-pin the roll every tick until the
	# end tick consumes exactly one draw (chance(0.25)) from the stage rng
	var queued := false
	for i in 12:
		sim.rng.set_state(q_state)
		sim.update_chaos(DT)
		if not sim.mirrorLedger.queued().is_empty():
			queued = true
			break
	ok(queued, "bloom end queued its mirror return")
	eq(sim.mirrorLedger.queued(), ["bloom"], "queue holds bloom")
	# fire the mirror face through update_chaos: the conversion path fires
	# onApply → on_fired clears the queue (a no-warn spawn would not — TS
	# fires the onApply hook only when a warned event goes live)
	var mirror: Dictionary = {
		"id": "bloom", "mirrorOf": "bloom", "name": "🌿 ALGAL BLOOM",
		"warn": "mirror incoming…", "warnS": 2.0,
		"weight": func(c): return 1.2 if c.get("mirrors", []).has("bloom") else 0.0,
		"duration": [0.1, 0.1], "cooldown": 30,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [mirror])
	sim.chaos._since_last = 1000.0
	for i in 140:
		sim.update_chaos(DT)
	eq(sim.mirrorLedger.queued(), [], "on_fired cleared the queue")
	ok(sim.mirrorLedger.has_fired("bloom"), "the fired base is on the ledger")
	# the apply banner fired with the def name
	var bannered := false
	for b in m["rec"]["banners"]:
		if String(b.get("title", "")) == "🌿 ALGAL BLOOM" and String(b.get("kind", "")) == "chaos":
			bannered = true
	ok(bannered, "apply banner with def name + kind chaos")


func test_natural_spawn_of_warnless_def_fires_no_hooks() -> void:
	# TS parity pin: spawn() runs apply for a surprise hit but fires NO
	# onApply — banner/chaos/note ride the warn→active conversion only.
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	var probe: Dictionary = {
		"id": "probe", "name": "probe",
		"weight": func(_c): return 1.0,
		"duration": [0.1, 0.1], "cooldown": 999,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [probe])
	sim.chaos._since_last = 1000.0
	var chaos0: float = float(ctx.chaos)
	sim.update_chaos(DT)
	ok(sim.chaos.active_events().size() == 1, "the surprise hit spawned")
	approx(float(ctx.chaos), chaos0, "no chaos bump without onApply", 1e-12)
	eq(rec["banners"], [], "no banner without onApply")
	eq(rec["notes"], [], "no storyteller note without onApply")


func test_on_apply_chaos_and_storyteller_note() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	# a WARNED def: the onApply hook rides the warn→active conversion
	# (warnS 2.0 pins the window at the 0.8x factory floor)
	var probe: Dictionary = {
		"id": "probe", "name": "probe", "warn": "incoming…", "warnS": 2.0,
		"weight": func(_c): return 1.0,
		"duration": [0.1, 0.1], "cooldown": 999,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [probe])
	sim.chaos._since_last = 1000.0
	var chaos0: float = float(ctx.chaos)
	sim.update_chaos(DT)  # spawn into warn: onWarn banner + alarm
	eq(rec["banners"].size(), 1, "warn banner at spawn")
	eq(String(rec["banners"][0]["kind"]), "danger", "warn banner kind")
	ok(_heard(rec, "alarm"), "alarm audio on warn")
	for i in 130:
		sim.update_chaos(DT)  # ride the 2.0s window → conversion
	approx(float(ctx.chaos), chaos0 + 0.03, "onApply chaos +0.03", 1e-12)
	eq(rec["notes"].size(), 1, "storyteller note hook fired")
	approx(float(rec["notes"][0]), float(ctx.playtime), "note carries ctx.playtime", 1e-9)
	eq(rec["banners"].size(), 2, "warn + apply banners")
	eq(String(rec["banners"][1]["kind"]), "chaos", "apply banner kind chaos")
	eq(String(rec["banners"][1]["title"]), "probe", "apply banner title")


# ---- ctx composition (the storyteller arrives via hooks) ----------------------------


func test_ctx_fields_and_storyteller_hooks() -> void:
	var m := _mk_sim(W_TRAITLESS, {
		"get_gap_bias": func(): return 0.8,
		"get_mood": func(): return "twist",
		"get_warn_scale": func(): return 1.3,
	})
	var sim: Variant = m["sim"]
	var seen: Array = []
	var w := func(c) -> float:
		seen.append(c.duplicate())
		return 1.0
	var probe: Dictionary = {
		"id": "probe", "name": "probe",
		"weight": w,
		"duration": [0.1, 0.1], "cooldown": 999,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [probe])
	sim.chaos._since_last = 1000.0
	sim.time = 3.5
	sim.update_chaos(DT)
	eq(seen.size(), 1, "the weight callable saw the ctx once")
	if seen.size() == 1:
		var c: Dictionary = seen[0]
		approx(float(c["stageTime"]), 3.5, "ctx.stageTime = stage clock", 1e-12)
		approx(float(c["chaos"]), float(sim.ctx.chaos), "ctx.chaos", 1e-12)
		approx(float(c["karma"]), float(sim.ctx.karma), "ctx.karma", 1e-12)
		approx(float(c["gapMult"]), float(sim.ctx.chaos_gap_mult()) * 0.8,
				"gapMult = chaosGapMult * storyteller gapBias", 1e-12)
		eq(String(c["mood"]), "twist", "ctx.mood from the hook")
		approx(float(c["warnScale"]), 1.3, "ctx.warnScale from the hook", 1e-12)
		ok(c["mirrors"] is Array, "ctx.mirrors is the ledger queue")
	# warnScale scales the warn window (2.5 * 1.3 — no per-def warnS)
	var wdef: Dictionary = {
		"id": "w", "name": "w", "warn": "incoming…",
		"weight": func(_c): return 1.0,
		"duration": [1.0, 1.0], "cooldown": 999,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [wdef])
	sim.chaos._since_last = 1000.0
	sim.update_chaos(DT)
	approx(float(sim.chaos.warn_remaining()), 2.5 * 1.3, "bio_tell window scales with warnScale", 1e-9)


# ---- C1 deck rebuild ----------------------------------------------------------------


func test_deck_rebuild_on_seed_mismatch() -> void:
	var m := _mk_sim(W_TRAITLESS)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	eq(int(sim.deckSeed), 11, "deckSeed from the constructor world")
	eq(sim.chaos.defs.size(), 8, "initial deck")
	var s0: int = sim.rng.state()
	ok(not sim.ensure_deck(11), "same seed → no rebuild")
	eq(sim.rng.state(), s0, "the no-op path draws nothing")
	# CONTINUE landed on a different world
	ctx.world = W_TOXIN.duplicate(true)
	ok(sim.ensure_deck(77), "seed mismatch rebuilds")
	ok(sim.rng.state() != s0, "the rebuild consumed a stage-rng branch")
	eq(int(sim.deckSeed), 77, "deckSeed updated")
	eq(sim.chaos.defs.size(), 9, "the rebuilt deck folds the new world in")
	ok(_def(sim.chaos.defs, "toxin_clouds") != null, "toxin_clouds in the rebuilt deck")


# ---- has_active_chaos ----------------------------------------------------------------


func test_has_active_chaos_lifecycle() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	ok(not sim.has_active_chaos(), "nothing active at boot")
	var probe: Dictionary = {
		"id": "probe", "name": "probe",
		"weight": func(_c): return 1.0,
		"duration": [0.5, 0.5], "cooldown": 999,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [probe])
	sim.chaos._since_last = 1000.0
	sim.update_chaos(DT)
	ok(sim.has_active_chaos(), "active-phase event counts")
	for i in 60:
		sim.update_chaos(DT)
	ok(not sim.has_active_chaos(), "ended event leaves the set")


# ---- warn_drift_t live wiring (bio_tell → AI panic) ----------------------------------


func test_warn_drift_live_panic_through_update() -> void:
	var m := _mk_sim(W_TRAITLESS)
	var sim: Variant = m["sim"]
	# a scripted warned event: the default warn window is 2.5s (warnScale 1.0)
	var wdef: Dictionary = {
		"id": "w", "name": "w", "warn": "incoming…",
		"weight": func(_c): return 1.0,
		"duration": [30.0, 30.0], "cooldown": 999,
		"apply": func(_s, _rng): pass,
	}
	sim.chaos = ChaosScript.new(sim.rng.branch(), [wdef])
	sim.chaos._since_last = 1000.0
	# 10 ents over radii 100..320 — the T4 panic geometry
	var eids: Array = []
	for i in 10:
		var ang: float = 0.3 + float(i) * 0.7
		var r: float = 100.0 + float(i) * (220.0 / 9.0)
		var e: Dictionary = sim.spawn_ent(null, sim.px + cos(ang) * r, sim.py + sin(ang) * r)
		eids.append(int(e["eid"]))
	# tick 1: the warn spawns at the END of update — warnDriftT still reads 0
	sim.update(DT, _inp())
	approx(sim.warnDriftT, 0.0, "warnDriftT before the first spawn", 1e-9)
	ok(not sim.has_active_chaos(), "warn phase is not an active event (TS activeEvents)")
	# tick 2: the window is live
	sim.update(DT, _inp())
	ok(sim.warnDriftT > 0.0, "warnDriftT tracks the live warn phase")
	# ride the 2.4s window — the herd vacates the strike zone
	for i in 142:
		sim.update(DT, _inp())
	var vacated := 0
	var inside := 0
	for eid in eids:
		for e in sim.ents:
			if int(e["eid"]) == eid:
				if Vector2(e["x"], e["y"]).distance_to(Vector2(sim.px, sim.py)) > 320.0:
					vacated += 1
				else:
					inside += 1
	ok(float(vacated) >= 0.4 * 10.0, "panic vacates >= 40%% of the zone (%d/10)" % vacated)
	ok(inside >= 1, "close-in ents stay (a real vacate gradient)")
	# past the window: converted to active — warnDriftT falls back to 0
	for i in 30:
		sim.update(DT, _inp())
	approx(sim.warnDriftT, 0.0, "no warn phase → no panic window", 1e-9)
	ok(sim.has_active_chaos(), "the converted event is active")


# ---- eco batch outcomes (speciation branch; extinction/shift live in test_cell_sim) --


func test_eco_batch_speciation_discover_and_toast() -> void:
	var m := _mk_sim(W_SPEC)  # speciation_mult 250 → the 0.004 roll always fires
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	for sp in sim.eco.living():
		sp["pop"] = 20.0  # every line speciation-eligible (pop > 6)
	var living0: int = sim.eco.living().size()
	sim.ecoTimer = 1.9
	sim.update(0.2, _inp())  # batch = 2.1 >= 2 → tick
	var living1: int = sim.eco.living().size()
	ok(living1 > living0, "speciation added species (%d → %d)" % [living0, living1])
	var toasts := 0
	for t in rec["toasts"]:
		if String(t[0]).begins_with("A new species emerges: "):
			toasts += 1
			eq(String(t[1]), "chaos", "toast kind")
			eq(String(t[2]), "🧬", "toast icon")
	eq(toasts, living1 - living0, "one toast per speciation")


# ---- replaced stub pin (test_cell_sim's deterministically-absent guard) --------------


func test_chaos_helpers_draw_and_push_state() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var s0: int = sim.rng.state()
	var ent0: int = sim.ents.size()
	var pel0: int = sim.pellets.size()
	sim.spawn_meteor_target(10.0, 10.0)
	eq(sim.zones.size(), 1, "meteor target pushed")
	sim.add_toxin_zone(0.0, 0.0, 50.0, 4.0, 6.0)
	sim.add_toxin_zone(0.0, 0.0, 50.0, 4.0, 6.0, "clouds")
	sim.add_vent(0.0, 0.0)
	eq(sim.zones.size(), 4, "toxin/vent zones pushed")
	sim.bloom()
	eq(sim.pellets.size(), pel0 + 30, "bloom sprinkle pushed")
	sim.spawn_swarm()
	eq(sim.ents.size(), ent0 + 4, "swarm spawned")
	ok(sim.rng.state() != s0, "the helpers draw the stage rng")
	ok(sim.spawn_big_brother() != null, "big brother returns its ent")
	var n: int = sim.spawn_mutant_wave()
	ok(n >= 2 and n <= 3, "mutant wave count 2-3")
