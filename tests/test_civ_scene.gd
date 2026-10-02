# Tests for game/civ/civ_stage.gd — the civ stage's non-pixel surface (M5
# task 3): the hook bindings (16 sim keys, the storyteller reads live), the
# on_enter flow (toast_inset 150 + objective through the hud instance), the
# update() snapshot → sim wiring (Q tap raise + transfer toast, Digit1
# launch), the per-frame set_abilities route, the portrait fixture sync, the
# geometry seams, the frozen seam, render guards pre/post restore, and THE
# T2-RIDER PIN: the storyteller's OWN mood/gap_bias/warn_scale reaching
# update_chaos through the stage's bound hooks (no injected lambdas).
# Pixel/visual behavior lives in tests/scenes/test_civ_scene.gd (xvfb).
# TS source: Spore src/game/civ/CivStage.ts (frozen), lines cited per pin.
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const CivStage := preload("res://src/game/civ/civ_stage.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC1FF3A


# ---- fixtures ------------------------------------------------------------------

# A real Game (headless: not in the tree — cam.cam2d stays null, nothing
# draws; the stage's _ready ran manually, the tribe-stage test pattern).
func _mk_stage(seed_v: int = SEED) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	var game: Variant = GameScript.new(ctx)
	var stage: Variant = CivStage.new(game)
	game.register(stage)
	stage._ready()  # the tree would normally fire this at register time
	return {"game": game, "stage": stage, "ctx": ctx, "sim": stage.sim}


# ---- hook bindings ---------------------------------------------------------------

func test_hooks_bind_all_sim_keys() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var hooks: Dictionary = stage._build_hooks()
	# every key the sim fires or reads (the sim header's documented surface)
	var want := ["hud_toast", "hud_banner", "hud_toast_inset", "hud_show_objective",
			"hud_float_world", "hud_set_abilities", "audio_play", "audio_set_mood",
			"cam_shake", "fx_spawn", "go_to", "save_all", "get_gap_bias",
			"get_mood", "get_warn_scale", "storyteller_note_chaos_event"]
	for k in want:
		ok(hooks.get(k) is Callable, "hook %s bound" % k)
	eq(hooks.size(), want.size(), "no stray hooks")
	# the storyteller reads return the game storyteller's LIVE values
	eq(float(hooks["get_gap_bias"].call()), float(m["game"].storyteller.gap_bias()),
			"get_gap_bias reads the storyteller")
	eq(String(hooks["get_mood"].call()), String(m["game"].storyteller.mood),
			"get_mood reads the storyteller")
	eq(float(hooks["get_warn_scale"].call()), float(m["game"].storyteller.warn_scale()),
			"get_warn_scale reads the storyteller")


# ---- on_enter: the hud hooks (TS:119-121 via the sim) ------------------------------

func test_on_enter_sets_inset150_and_objective() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var hud: Variant = stage.hud_inst
	stage.on_enter()
	# the sim's hud hooks landed on the stage's hud instance
	eq(float(hud.toast_inset), 150.0, "hud_toast_inset 150 (TS:120 — clears the portrait)")
	eq(String(hud.show_objective), CivSim.OBJECTIVE_LINE, "showObjective set (TS:121)")
	# the overlay dicts point at THIS stage's instances
	ok(m["game"].hud.get("toast") is Callable, "hud dict installed")
	ok(m["game"].hud.get("set_abilities") is Callable, "set_abilities in the hud dict")
	ok(m["game"].pause.get("update") is Callable, "pause dict installed")


# ---- update(): the M2 snapshot feeds the sim (TS:177-227 scene-side) ---------------

func test_snapshot_keys_reach_the_sim() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	# Q tap: mil 4 → 5, the full board transfers 1 from culture (3 → 2)
	# (TS:198-216 raise lambda) — the key rides the snapshot the stage builds
	game.input.keys_pressed["KeyQ"] = true
	stage.update(DT)
	approx(float(m["sim"].mil), 5.0, "KeyQ raised mil")
	approx(float(m["sim"].culture), 2.0, "the board transfer took 1 from culture")
	approx(float(m["sim"].econ), 3.0, "econ untouched")
	eq(String(m["sim"].lastRaised), "mil", "lastRaised mil")
	ok(stage.hud_inst._toasts.size() > 0, "the transfer toast fired")
	ok(String(stage.hud_inst._toasts[0]["text"]).find("+1 mil") >= 0,
			"the +1 mil ← culture toast text")
	# one-shot semantics: the next update consumes nothing more (end_frame
	# clears the wrapper in the real loop; here the dict stays until cleared)
	game.input.keys_pressed.clear()
	var mil: float = m["sim"].mil
	stage.update(DT)
	approx(float(m["sim"].mil), mil, "no repeat raise without a fresh press")
	# Digit1 with stat ≥ 2... the launch gate: mil 5 → power 9 > rivalDef 8
	# (TS:328-335) — the armada spawns through the same snapshot pipe
	game.input.keys_pressed["Digit1"] = true
	stage.update(DT)
	eq(m["sim"].armadas.size(), 1, "Digit1 launched the armada")
	approx(float(m["sim"].mil), 3.0, "the launch spent 2 from the lane (TS:337)")
	approx(float(m["sim"].launchCds["attack"]), 5.0, "route cooldown 5 (TS:344)")


func test_snapshot_carries_mouse_fields_unused() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	# the mouse fields ride the snapshot (M2 shape) — the sim reads
	# keys_pressed only; a pointer down + click must not disturb the board
	game.input.mx = 123.0
	game.input.my = 45.0
	game.input.down = true
	game.input.clicked = true
	game.input.wx = 10.0
	game.input.wy = 20.0
	var t0: float = float(m["sim"].time)
	var mil: float = m["sim"].mil
	stage.update(DT)
	approx(float(m["sim"].mil), mil, "no slider moved from mouse fields")
	ok(float(m["sim"].time) > t0, "the sim stepped")


# ---- set_abilities route (TS:298-305, fired by the sim every update) ---------------

func test_set_abilities_payload_mirrors_sliders_each_frame() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	stage.update(DT)
	var ab: Array = stage.hud_inst.abilities
	eq(ab.size(), 6, "6 ability entries (TS:298-305)")
	eq(String(ab[0]["key"]), "1", "slot 1 key")
	eq(String(ab[0]["icon"]), "⚔️", "slot 1 icon")
	eq(String(ab[1]["icon"]), "🎭", "slot 2 icon")
	eq(String(ab[2]["icon"]), "💰", "slot 3 icon")
	eq(String(ab[3]["key"]), "Q/A", "slot Q/A key")
	eq(String(ab[3]["icon"]), "🔫", "slot Q/A icon")
	eq(String(ab[4]["key"]), "W/S", "slot W/S key")
	eq(String(ab[5]["key"]), "E/D", "slot E/D key")
	ok(not ab[0].has("active"), "cd entries carry NO active key (TS:299-301)")
	# the slider actives mirror the lanes (mil/culture/econ default 4/3/3 > 0)
	ok(bool(ab[3]["active"]), "Q/A active while mil > 0")
	ok(bool(ab[4]["active"]), "W/S active while culture > 0")
	ok(bool(ab[5]["active"]), "E/D active while econ > 0")
	# drain the lanes → the actives go dark (mirrors the live sliders)
	m["sim"].mil = 0.0
	m["sim"].culture = 0.0
	m["sim"].econ = 0.0
	stage.update(DT)
	ab = stage.hud_inst.abilities
	ok(not bool(ab[3]["active"]), "Q/A dark at mil 0")
	ok(not bool(ab[4]["active"]), "W/S dark at culture 0")
	ok(not bool(ab[5]["active"]), "E/D dark at econ 0")
	# per-frame refresh: a launch cd decays between updates and the payload
	# follows (the sim fires hud_set_abilities at the END of every update)
	m["sim"].launchCds["attack"] = 5.0
	stage.update(DT)
	ab = stage.hud_inst.abilities
	ok(float(ab[0]["cd"]) < 1.0 and float(ab[0]["cd"]) > 0.9,
			"slot 1 cd mirrors launchCds/5 and decays per frame")


# ---- portrait fixture sync (TS:617-626 scene-side) ----------------------------------

func test_portrait_fixture_syncs_per_render() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	m["sim"].time = 3.5
	stage.render()
	var item: Variant = stage.portrait_item
	var creature: Variant = stage.portrait_creature
	# the panel + clip rects (TS:617/:620)
	var pr: Rect2 = item.panel_rect
	eq(int(pr.position.x), 18, "panel x 18")
	eq(int(pr.position.y), int(game.vh - 120.0), "panel y vh−120")
	eq(int(pr.size.x), 96, "panel 96×96")
	var cr: Rect2 = item.clip_rect
	eq(int(cr.position.x), 22, "clip x 22 (TS:620)")
	eq(int(cr.position.y), int(game.vh - 116.0), "clip y vh−116")
	eq(int(cr.size.x), 88, "clip 88×88")
	# the creature carries the ctx genome REFERENCE + the TS pose verbatim
	ok(creature.genome == m["ctx"].genome, "portrait genome is the ctx genome")
	approx(float(creature.pose["x"]), 66.0, "pose x 66 (TS:623)")
	approx(float(creature.pose["y"]), game.vh - 40.0, "pose y vh−40")
	approx(float(creature.pose["scale"]), 1.4, "portrait scale 1.4")
	eq(String(creature.pose["mood"]), "happy", "mood happy")
	approx(float(creature.pose["gaitPhase"]), 7.0, "gaitPhase = time·2")
	approx(float(creature.opts["t"]), 3.5, "opts.t = sim.time")


# ---- geometry seams (the draw sites + the scene probes consume these) ---------------

func test_geometry_seams() -> void:
	# TS:539-541 — the planet center/radius
	var pc: Vector2 = CivStage.planet_center(0.0, 0.0, 800.0, 600.0)
	approx(pc.x, 400.0, "pcx = vw/2 at cam 0")
	approx(pc.y, 340.0, "pcy = vh/2 + 40 at cam 0")
	var pc2: Vector2 = CivStage.planet_center(100.0, -40.0, 800.0, 600.0)
	approx(pc2.x, 350.0, "pcx = vw/2 − camX·0.5")
	approx(pc2.y, 360.0, "pcy = vh/2 − camY·0.5 + 40")
	approx(CivStage.planet_radius(800.0, 600.0), 252.0, "pr = min(vw,vh)·0.42")
	# TS:565-568 toScreen — 0.62 scale through the planet center (Vector2 is
	# float32 — the seam asserts carry a 1e-4 eps, the fixture-note law)
	var s: Vector2 = CivStage.map_to_screen(0.0, 120.0, 0.0, 0.0, 800.0, 600.0)
	approx(s.x, 400.0, "capital screen x", 1e-4)
	approx(s.y, 414.4, "capital screen y (pcy + my·0.62)", 1e-4)
	var s2: Vector2 = CivStage.map_to_screen(-300.0, 0.0, 100.0, 0.0, 800.0, 600.0)
	approx(s2.x, 164.0, "map_to_screen with drifted cam", 1e-4)
	approx(s2.y, 340.0, "map_to_screen y with drifted cam", 1e-4)


# ---- the frozen seam + render guards -------------------------------------------------

func test_frozen_seam_holds_the_sim() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	stage.on_enter()
	stage.frozen = true
	var t0: float = float(m["sim"].time)
	stage.update(DT)
	approx(float(m["sim"].time), t0, "frozen: the sim does not step")
	stage.frozen = false
	stage.update(DT)
	ok(float(m["sim"].time) > t0, "unfrozen: the sim steps")


func test_render_guards_pre_and_post_restore() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	# a bare stage (no _ready) renders nothing and does not crash
	var bare: Variant = CivStage.new(m["game"])
	bare.render()  # planet_canvas null → early return
	ok(true, "bare render() guarded")
	# a _ready'd stage renders headless (canvas sync + queue_redraw, no draw)
	stage.on_enter()
	stage.render()
	ok(stage.portrait_item != null, "ready'd render() headless")
	# post-restore: a saved blob flows through on_enter's restore path and
	# the render keeps working off the restored board
	var blob := {
		"cities": [
			{"id": "you", "owner": "you", "influence": 100.0, "hp": 90.0, "pop": 8.0},
			{"id": "r1", "owner": "you", "influence": 40.0, "hp": 70.0, "pop": 6.0},
			{"id": "r2", "owner": "r2", "influence": -60.0, "hp": 100.0, "pop": 6.0},
			{"id": "r3", "owner": "r3", "influence": -60.0, "hp": 100.0, "pop": 6.0},
		],
		"mil": 7.0, "culture": 2.0, "econ": 1.0,
		"victoryFired": false, "lastRaised": "econ",
	}
	m["ctx"].flags["civState"] = JSON.stringify(blob)
	stage.on_enter()
	approx(float(m["sim"].mil), 7.0, "mil restored")
	eq(String(m["sim"].cities[1]["owner"]), "you", "conquest restored")
	stage.render()
	ok(true, "render() post-restore guarded")


# ---- THE T2-RIDER PIN: real storyteller values through the stage's hooks -------------

# The T2 sim-level pin injected hook lambdas; THIS pin proves the STAGE's own
# bindings (game.storyteller.*) are the values update_chaos consumes. The
# probe def records the ctx the scheduler hands the weight fn at ROLL time.
func test_real_storyteller_values_reach_update_chaos() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	# retune the REAL storyteller + difficulty (no hook injection anywhere):
	# bless mood → gap_bias 1.2, chaos difficulty → chaos_gap_mult 0.7,
	# cradle temperament → warn_scale 1.6 (a pure match — _grace 0 keeps the
	# gap_bias at the bless 1.2)
	game.storyteller.mood = "bless"
	m["ctx"].difficulty = "chaos"
	game.storyteller.temperament = "cradle"
	var sim: Variant = m["sim"]
	var rec := {"ctx": null}
	# probe-only scheduler (the T2 hermeticity pattern); the weight records
	# the ctx (a bound method — the weight must return a float)
	sim.chaos.defs = [{
		"id": "probe", "name": "Probe", "warn": "the probe hums",
		"weight": _probe_weight.bind(rec),
		"duration": [1.0, 1.0],
		"apply": func(_s, _r): pass,
	}]
	for i in 60:
		stage.update(1.0)
		if rec["ctx"] != null:
			break
	ok(rec["ctx"] != null, "the probe rolled through the stage-driven flow")
	if rec["ctx"] == null:
		return
	var c: Dictionary = rec["ctx"]
	# the ctx values ARE the storyteller's own (the stage hooks' returns):
	eq(String(c["mood"]), String(game.storyteller.mood), "mood is the storyteller's")
	eq(String(c["mood"]), "bless", "the retuned mood reached the scheduler")
	approx(float(c["gapMult"]),
			float(m["ctx"].chaos_gap_mult()) * float(game.storyteller.gap_bias()),
			"gapMult = chaos_gap_mult × gap_bias (the stage hook composition)")
	approx(float(c["gapMult"]), 0.84, "concrete: 0.7 (chaos) × 1.2 (bless)")
	approx(float(c["warnScale"]), float(game.storyteller.warn_scale()),
			"warnScale is the storyteller's")
	approx(float(c["warnScale"]), 1.6, "cradle warn scale 1.6 reached the scheduler")
	approx(float(c["chaos"]), float(m["ctx"].chaos), "chaos meter from the ctx")
	approx(float(c["karma"]), float(m["ctx"].karma), "karma from the ctx")
	approx(float(c["stageTime"]), float(sim.time), "stageTime = sim.time")
	# the onWarn side ALSO rode the stage's real hud hook (no injected hooks):
	# the probe's warn banner landed on the hud instance
	if stage.hud_inst._cur_banner != null:
		eq(String(stage.hud_inst._cur_banner["title"]), "the probe hums",
				"onWarn banner through the stage's hud hook")
		eq(String(stage.hud_inst._cur_banner["kind"]), "danger", "onWarn kind danger")
		approx(float(stage.hud_inst._cur_banner["ttl"]), 2.4, "onWarn ttl 2.4")
	else:
		ok(false, "the warn banner never reached the hud instance")


## The rider probe's weight — records the roll ctx (the scheduler hands it
## verbatim) and wins the weighted pick. Callable.bind APPENDS its args after
## the call args, so the bound rec arrives SECOND.
func _probe_weight(c: Variant, rec: Dictionary) -> float:
	rec["ctx"] = (c as Dictionary).duplicate()
	return 10.0
