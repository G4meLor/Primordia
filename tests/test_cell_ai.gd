# Tests for game/cell/cell_sim.gd update_ents — the NPC AI state machine:
# hp<=0 sweep, lifespan expiry, cooldown/stun decay, panic > hunt > flee >
# graze steering, separation, integration, containment, pellet eating, toxin
# exposure. TS source: Spore src/game/cell/CellStage.ts updateEnts (frozen).
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode on a clone.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const RngLib := preload("res://src/core/rng.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const CellSim := preload("res://src/game/cell/cell_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE
const WORLD_R := 2400.0


# ---- fixtures ------------------------------------------------------------------

# Same shape as test_cell_sim.gd's fixture: explicit-seed GameContext, stage
# rng branch, recording hooks, sim.
func _mk_sim(seed_v: int = SEED) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
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


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


# Default genome + overrides — spawn_ent(null, …) ents are speciesId "mutant".
func _genome(mods: Dictionary = {}) -> Dictionary:
	var g: Dictionary = GenomeLib.default_genome()
	g.merge(mods, true)
	return g


# A quiet grazer far from the player: no hunt/flee reads at 1600px, and no
# starter pellets within the 300 seek radius (they stay within 900 of origin).
func _grazer(sim: Variant, x: float, y: float, mods: Dictionary = {},
		opts: Dictionary = {}) -> Dictionary:
	var m: Dictionary = {"size": 0.7, "diet": "herbivore", "flagella": 3}
	m.merge(mods, true)
	return sim.spawn_ent(null, x, y, _genome(m), opts)


func _ent_dist(sim: Variant, e: Dictionary) -> float:
	return Vector2(e["x"], e["y"]).distance_to(Vector2(sim.px, sim.py))


func _has_eid(sim: Variant, eid: int) -> bool:
	for e in sim.ents:
		if int(e["eid"]) == eid:
			return true
	return false


func _pellet(kind: String, x: float, y: float) -> Dictionary:
	return {"x": x, "y": y, "vx": 0.0, "vy": 0.0, "kind": kind,
			"ttl": 40.0 if kind == "plant" else 25.0, "val": 2 if kind == "plant" else 5}


# ---- sweep (top of the loop) -----------------------------------------------------

func test_sweep_pays_tagged_kills_and_green_bursts_untagged() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var a: Dictionary = sim.spawn_ent(sim.eco.living()[0], 300.0, 0.0, {}, {})
	a["hp"] = 0.0
	a["lastPlayerHit"] = "contact"  # tagged → pays through kill_ent
	var b: Dictionary = sim.spawn_ent(null, -300.0, 0.0, _genome(), {})  # untagged corpse
	b["hp"] = 0.0
	var pellets_before: int = sim.pellets.size()
	var killed_before: int = int(sim.tut["killed"])
	sim.update(DT, _inp())
	ok(not _has_eid(sim, int(a["eid"])), "tagged kill swept")
	ok(not _has_eid(sim, int(b["eid"])), "untagged corpse swept")
	var die_count := 0
	for snd in rec["audio"]:
		if snd[0] == "die":
			die_count += 1
	eq(die_count, 1, "tagged death pays the killEnt audio exactly once")
	var green := 0
	for br in rec["bursts"]:
		if int(br[2]) == 8 and br[3]["colors"] == ["#9fff9f", "#8fff4f"]:
			green += 1
	eq(green, 1, "untagged death bursts green (8 particles)")
	eq(sim.pellets.size(), pellets_before + 1, "tagged pay drops meat pellets (1 + floor(0.7))")
	eq(int(sim.tut["killed"]), killed_before + 1, "tut.killed counts the tagged pay")


func test_lifespan_expiry_removes_ent() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var e: Dictionary = _grazer(sim, 1600.0, 0.0, {}, {"lifespan": 0.5})
	for i in 25:
		sim.update(DT, _inp())
	eq(sim.ents.size(), 1, "still alive before expiry")
	approx(float(e["lifespan"]), 0.5 - 25.0 * DT, "lifespan decays", 1e-9)
	for i in 6:
		sim.update(DT, _inp())
	eq(sim.ents.size(), 0, "expired ent removed (lifespan <= 0)")


# ---- cooldown decays + stun branch ------------------------------------------------

func test_stunned_ent_drifts_and_cooldowns_decay() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var e: Dictionary = _grazer(sim, 1600.0, 0.0)
	e["stun"] = 1.0
	e["vx"] = 100.0
	e["vy"] = 40.0
	e["hurtT"] = 0.9
	e["eatT"] = 0.9
	e["biteCd"] = 0.5
	e["pressCd"] = 10.0
	sim.update(DT, _inp())
	approx(float(e["stun"]), 1.0 - DT, "stun decays", 1e-9)
	approx(float(e["hurtT"]), 0.9 - DT * 3.0, "hurtT decays ×3", 1e-9)
	approx(float(e["eatT"]), 0.9 - DT * 2.0, "eatT decays ×2", 1e-9)
	approx(float(e["biteCd"]), 0.5 - DT, "biteCd decays", 1e-9)
	approx(float(e["pressCd"]), 10.0 - DT, "pressCd decays", 1e-9)
	var drag: float = exp(-3.0 * DT)
	approx(float(e["vx"]), 100.0 * drag, "stun drag exp(-3dt) on vx", 1e-9)
	approx(float(e["vy"]), 40.0 * drag, "stun drag exp(-3dt) on vy", 1e-9)
	approx(float(e["x"]), 1600.0 + 100.0 * drag * DT, "stun drift x (post-drag v)", 1e-9)
	approx(float(e["y"]), 40.0 * drag * DT, "stun drift y (post-drag v)", 1e-9)
	# AI skipped: no current contaminates vx (current applies only below the
	# stun branch) and wanderT stays untouched
	approx(float(e["wanderT"]), 0.0, "AI skipped while stunned", 1e-9)


# ---- hunt -------------------------------------------------------------------------

func test_hunter_closes_on_player() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# non-herbivore, bigger than the player (size 1.5 > 1*1.05), within vision
	var e: Dictionary = _grazer(sim, 150.0, 0.0,
			{"size": 1.5, "diet": "carnivore", "jaw": 3, "flagella": 2})
	var d0: float = _ent_dist(sim, e)
	for i in 60:
		sim.update(DT, _inp())
	ok(sim.ents.size() >= 1, "hunter survives the window")
	ok(_ent_dist(sim, e) < d0 - 25.0, "hunter closes on the player (%f → %f)" % [d0, _ent_dist(sim, e)])


# ---- flee -------------------------------------------------------------------------

func test_fleeing_prey_respects_achievable_speed_cap() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# small herbivore: !iAmBigger, grudge 0, within vision*0.7*fear — would flee
	var e: Dictionary = _grazer(sim, 60.0, 0.0, {"size": 0.6, "diet": "herbivore", "flagella": 5})
	var prey_speed: float = float(e["stats"]["speed"])
	var cap: float = minf(prey_speed * 0.95, (float(sim.pStats["accel"]) / 2.6) * 0.85)
	ok(cap < prey_speed * 0.95 - 1.0, "achievable-speed clause binds the cap (not the stat sheet)")
	var prev_x: float = float(e["x"])
	var prev_y: float = float(e["y"])
	var total := 0.0
	for i in 60:
		sim.update(DT, _inp())
		# f64 displacement — Vector2.distance_to is float32 (M2 carry-forward)
		# and its ulp at this position magnitude exceeds the margin being assert
		var ddx: float = float(e["x"]) - prev_x
		var ddy: float = float(e["y"]) - prev_y
		var step_disp: float = sqrt(ddx * ddx + ddy * ddy)
		ok(step_disp <= cap * DT + 1e-9,
				"tick %d displacement %f within cap*dt %f" % [i, step_disp, cap * DT])
		total += step_disp
		prev_x = float(e["x"])
		prev_y = float(e["y"])
	ok(total <= 60.0 * cap * DT + 1e-9, "total displacement bounded by the cap")
	ok(_ent_dist(sim, e) > 60.0, "prey actually fled away from the player")


# ---- panic (bio_tell) --------------------------------------------------------------

func test_panic_vacates_zone() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# 10 scripted ents spread over radii 100..320 — panic drift is 48px/s, so
	# 2.4s carries an ent 115.2px: ents beyond ~205 vacate, the catalog's
	# 40-60% band. update() zeroes warnDriftT (Task 5 wires the scheduler),
	# so the test drives update_ents directly with the field set per tick —
	# exactly the seam Task 5 will fill.
	var eids: Array[int] = []
	for i in 10:
		var ang: float = 0.3 + float(i) * 0.7
		var r: float = 100.0 + float(i) * (220.0 / 9.0)
		var e: Dictionary = _grazer(sim, sim.px + cos(ang) * r, sim.py + sin(ang) * r)
		eids.append(int(e["eid"]))
	for t in 144:  # the 2.4s window
		sim.warnDriftT = 2.4
		sim.update_ents(DT)
	var vacated := 0
	var inside := 0
	for eid in eids:
		for e in sim.ents:
			if int(e["eid"]) == eid:
				if _ent_dist(sim, e) > 320.0:
					vacated += 1
				else:
					inside += 1
	ok(float(vacated) >= 0.4 * 10.0,
			"panic vacates >= 40%% of the zone (%d/10)" % vacated)
	ok(inside >= 1, "close-in ents stay (a real vacate gradient, not a teleport)")


# ---- graze ------------------------------------------------------------------------

func test_grazer_seeks_diet_appropriate_pellets() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# herbivore seeks the plant 150px away (starter pellets are 700+px away)
	var e1: Dictionary = _grazer(sim, 1600.0, 0.0)
	sim.pellets.append(_pellet("plant", 1750.0, 0.0))
	sim.update(DT, _inp())
	approx(float(e1["tx"]), 1750.0, "herbivore tx locks the plant", 1e-9)
	approx(float(e1["ty"]), 0.0, "herbivore ty locks the plant", 1e-9)
	var d0: float = Vector2(e1["x"], e1["y"]).distance_to(Vector2(1750.0, 0.0))
	for i in 55:
		sim.update(DT, _inp())
	var d1: float = Vector2(e1["x"], e1["y"]).distance_to(Vector2(1750.0, 0.0))
	ok(d1 < d0 - 25.0, "grazer approaches the pellet (%f → %f)" % [d0, d1])
	# carnivore ignores the plant and seeks meat
	var e2: Dictionary = _grazer(sim, -1600.0, 0.0, {"size": 1.0, "diet": "carnivore", "jaw": 2})
	sim.pellets.append(_pellet("plant", -1650.0, 0.0))
	sim.pellets.append(_pellet("meat", -1750.0, 0.0))
	sim.update(DT, _inp())
	approx(float(e2["tx"]), -1750.0, "carnivore tx locks the meat", 1e-9)
	approx(float(e2["ty"]), 0.0, "carnivore ty locks the meat", 1e-9)


func test_graze_reroll_draw_order() -> void:
	# Ruling 1: the wanderT re-roll draws range(1.5,4) first, then — only when
	# no pellet target — next() + range(60,320). The pellet-seek loop draws
	# nothing. Pinned by replaying the expected draws on a state-copy.
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var e: Dictionary = _grazer(sim, 1600.0, 0.0)  # no pellet within 300 → random point
	var s0: int = sim.rng.state()
	var probe: Variant = RngLib.new_from(s0)
	var exp_wander: float = probe.range(1.5, 4.0)
	var exp_a: float = probe.next() * TAU
	var exp_r: float = probe.range(60.0, 320.0)
	sim.update(DT, _inp())
	eq(sim.rng.state(), probe.state(), "no-target re-roll = exactly 3 draws, TS order")
	approx(float(e["wanderT"]), exp_wander, "wanderT re-roll drawn first", 1e-9)
	approx(float(e["tx"]), 1600.0 + cos(exp_a) * exp_r, "tx from next()*TAU then range(60,320)", 1e-9)
	approx(float(e["ty"]), sin(exp_a) * exp_r, "ty from next()*TAU then range(60,320)", 1e-9)
	# with a pellet target: exactly ONE draw (wanderT), no angle/radius draws
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var e2: Dictionary = _grazer(sim2, 1600.0, 0.0)
	sim2.pellets.append(_pellet("plant", 1750.0, 0.0))
	var s0b: int = sim2.rng.state()
	var probe2: Variant = RngLib.new_from(s0b)
	var exp_wander2: float = probe2.range(1.5, 4.0)
	sim2.update(DT, _inp())
	eq(sim2.rng.state(), probe2.state(), "pellet-target re-roll = exactly 1 draw")
	approx(float(e2["wanderT"]), exp_wander2, "wanderT drawn, seek loop draws nothing", 1e-9)
	approx(float(e2["tx"]), 1750.0, "tx locks the pellet", 1e-9)


# ---- kin grudge press --------------------------------------------------------------

func test_grudge_press_registers_and_keeps_chasing() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# minimal world blob: kin_grudge flag live (world_has walks traits/effects)
	ctx.world = {"seed": 7, "traits": [{"effects": [{"kind": "flag", "key": "kin_grudge"}]}]}
	var sp: Dictionary = sim.eco.species[0]
	sp["kin_tag"] = true
	sp["grudge"] = 2.0  # the kin_memory ledger, as kill_ent writes it
	eq(float(sim.eco.grudge_of(ctx.world, sp["id"])), 2.0, "grudge reads 2 through the eco API")
	# a small herbivore would flee — grudge >= 2 makes it press instead
	var e: Dictionary = sim.spawn_ent(sp, sim.px + 150.0, sim.py, {}, {})
	var d0: float = _ent_dist(sim, e)
	for i in 40:
		sim.update(DT, _inp())
	eq(float(sp.get("harass", 0.0)), 1.0, "grudge press registers exactly once (one engagement)")
	ok(float(e["pressCd"]) > 19.0, "press cooldown armed at 20 and still running")
	eq(float(sim.eco.grudge_of(ctx.world, sp["id"])), 2.0, "grudge holds through the window")
	ok(_ent_dist(sim, e) < d0 - 25.0, "grudging ent keeps chasing (%f → %f)" % [d0, _ent_dist(sim, e)])


# ---- swarm -------------------------------------------------------------------------

func test_swarm_never_flees() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# smaller than the player and within flee radius — only the swarm flag
	# keeps it hunting (fleeing requires !swarm)
	var e: Dictionary = _grazer(sim, 150.0, 0.0,
			{"size": 0.55, "diet": "herbivore", "flagella": 5, "cilia": 3}, {"swarm": true})
	ok(float(e["genome"]["size"]) < 1.0, "precondition: smaller than the player")
	var d0: float = _ent_dist(sim, e)
	for i in 30:
		sim.update(DT, _inp())
	ok(float(e["hp"]) > 0.0, "swarm ent alive")
	ok(_ent_dist(sim, e) < d0 - 40.0, "swarm closes on the player instead of fleeing (%f → %f)" % [d0, _ent_dist(sim, e)])


# ---- pellet eating -----------------------------------------------------------------

func test_ent_eats_pellet_heals_4() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var e: Dictionary = _grazer(sim, 1600.0, 0.0)
	e["hp"] = float(e["maxHp"]) - 10.0
	sim.pellets.append(_pellet("plant", 1600.0, 0.0))
	var before: int = sim.pellets.size()
	sim.update(DT, _inp())
	eq(sim.pellets.size(), before - 1, "pellet consumed by the ent")
	approx(float(e["hp"]), float(e["maxHp"]) - 6.0, "eating heals 4 (capped at maxHp)", 1e-9)
	approx(float(e["eatT"]), 1.0, "eatT set to 1", 1e-9)


# ---- toxin zones -------------------------------------------------------------------

func test_toxin_zone_dps_hurtT_and_mine_tag() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var e: Dictionary = _grazer(sim, 1600.0, 0.0)
	var hp0: float = float(e["hp"])
	sim.zones.append({"x": 1600.0, "y": 0.0, "r": 100.0, "kind": "toxin",
			"ttl": 6.0, "dps": 8.0, "pulse": 0.0, "mine": true})
	sim.update(DT, _inp())
	approx(float(e["hp"]), hp0 - 8.0 * DT, "toxin zone dps ticks hp", 1e-9)
	approx(float(e["hurtT"]), 0.2, "hurtT floored at 0.2", 1e-9)
	eq(String(e["lastPlayerHit"]), "toxin", "mine zone tags lastPlayerHit 'toxin'")
	# a red-tide zone (not mine) hurts but never tags the player
	var m2 := _mk_sim()
	var sim2: Variant = m2["sim"]
	var e2: Dictionary = _grazer(sim2, 1600.0, 0.0)
	sim2.zones.append({"x": 1600.0, "y": 0.0, "r": 100.0, "kind": "toxin",
			"ttl": 6.0, "dps": 8.0, "pulse": 0.0})
	sim2.update(DT, _inp())
	ok(float(e2["hp"]) < float(e2["maxHp"]), "untagged zone still hurts")
	eq(String(e2["lastPlayerHit"]), "", "non-mine zone leaves lastPlayerHit empty")


# ---- separation ----------------------------------------------------------------------

func test_separation_pushes_overlapping_ents_apart() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# two ents 3px apart (d2 9 > 0.01, within 14*(0.7+0.7)); wanderT pinned
	# high + tx/ty on themselves so ONLY the separation loop steers — no rng
	var e1: Dictionary = _grazer(sim, 1600.0, 0.0)
	var e2: Dictionary = _grazer(sim, 1600.0, 3.0)
	for e in [e1, e2]:
		e["wanderT"] = 100.0
	var gap0: float = Vector2(e1["x"], e1["y"]).distance_to(Vector2(e2["x"], e2["y"]))
	for i in 3:
		sim.update(DT, _inp())
	var gap1: float = Vector2(e1["x"], e1["y"]).distance_to(Vector2(e2["x"], e2["y"]))
	ok(gap1 > gap0 + 0.1, "overlapping ents push apart (%f → %f)" % [gap0, gap1])
	ok(float(e1["y"]) < 0.0 - 0.05, "ent 1 pushed to its side")
	ok(float(e2["y"]) > 3.0 + 0.05, "ent 2 pushed to its side")


# ---- world containment ----------------------------------------------------------------

func test_ent_world_containment_beyond_world_r_plus_100() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	# wanderT pinned: zero AI accel, so the full pipeline is hand-checkable
	var e: Dictionary = _grazer(sim, 2600.0, 0.0)
	e["wanderT"] = 100.0
	sim.update(DT, _inp())
	# exact replay of the TS pipeline: graze (no accel) → current → drag →
	# integrate → push (40*dt*10 inward, applied to vx for the next tick)
	var cur: float = sin(DT * 0.05) * 14.0  # current_at(y=0) with time == DT
	var vx_pre: float = cur * DT * exp(-2.4 * DT)
	var x1: float = 2600.0 + vx_pre * DT
	approx(float(e["x"]), x1, "position integrates pre-push velocity", 1e-9)
	approx(float(e["vx"]), vx_pre - 400.0 * DT, "containment push 40*dt*10 inward", 1e-9)
	ok(float(e["vx"]) < 0.0, "pushed back toward the world")
