# Tests for game/space/space_stage.gd — the space stage's non-pixel surface
# (M6 task 4 + task 5 headless additions): the hook bindings (17 sim keys),
# the on_enter flow (objective + the cam-rig ownership pairing), the update()
# scene-side halves (the M2 snapshot → sim wiring, WASD thrust through the
# Input singleton, the camera feed numbers follow rate 5 / zoom 0.85, the
# toWorld feed, the fx pool steps), the take_click freshness + the wrapper
# mirror, the panel_rects write-back + the end-to-end rect-click dispatch
# (task 5 — the f1387fe contract), the abilities payload per frame, the
# ending fade math windows (task 5), the beam creature-vs-cell dispatch
# (legs), the ship visibility seam, the world-layer geometry seams (the
# planet shadow ladder, the beam quad, the ship hull), the fx hooks → the
# stage pool (Fx(1300)), the frozen seam, and the render guards pre/post
# restore. Pixel/visual behavior lives in the task-5 xvfb suite
# (tests/scenes/test_space_scene.gd + tools/visual_check_space_scene.py).
# TS source: Spore src/game/space/SpaceStage.ts (frozen), lines cited per pin.
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const SpaceStage := preload("res://src/game/space/space_stage.gd")
const SpaceSim := preload("res://src/game/space/space_sim.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")

const DT := 1.0 / 60.0
const SEED := 0x5EED5
const OBJECTIVE := "SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve"


# ---- fixtures ------------------------------------------------------------------

# A real Game (headless: not in the tree — cam.cam2d stays null, nothing
# draws; the stage's _ready ran manually, the civ/tribe-stage test pattern).
func _mk_stage(seed_v: int = SEED) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	var game: Variant = GameScript.new(ctx)
	var stage: Variant = SpaceStage.new(game)
	game.register(stage)
	stage._ready()  # the tree would normally fire this at register time
	return {"game": game, "stage": stage, "ctx": ctx, "sim": stage.sim}


# Held-key state polls the Input singleton — inject via parse_input_event +
# flush (test_input.gd's proven -s-mode path). PROCESS-GLOBAL: every user
# releases before returning.
func _flush_held(physical: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


# ---- hook bindings (the sim header's documented surface) -------------------------

func test_hooks_bind_all_sim_keys() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var hooks: Dictionary = stage._build_hooks()
	# every key the sim fires or reads (space_sim.gd's header list + the
	# parity-only go_to/save_all) resolves to a Callable on the stage
	var want := ["hud_toast", "hud_banner", "hud_show_objective", "hud_objective_counter",
			"hud_float_world",
			"hud_set_abilities", "audio_play", "audio_set_mood", "cam_shake",
			"fx_spawn", "fx_burst", "set_cursor", "get_gap_bias", "get_mood",
			"get_warn_scale", "storyteller_note_chaos_event", "go_to", "save_all",
			"death_debrief"]  # R4: the death debrief note/commit hook
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


# ---- on_enter: the hud objective + the cam-rig ownership (TS:188/:894) ------------

func test_on_enter_sets_objective_and_rig_ownership() -> void:
	var ctx: Variant = Ctx.new(SEED)
	var game: Variant = GameScript.new(ctx)
	var stage: Variant = SpaceStage.new(game)
	game.register(stage)
	var c2d := Camera2D.new()
	game.cam.cam2d = c2d  # headless the rig's _ready never ran — attach manually
	stage._ready()
	eq(c2d.enabled, false, "the rig boots disabled (the menu/cell screen-space default)")
	stage.on_enter()
	eq(String(stage.hud_inst.show_objective), OBJECTIVE, "showObjective set (TS:188 via the sim)")
	eq(c2d.enabled, true, "cam.begin armed on enter — the rig carries the world layer")
	stage.on_exit()
	eq(c2d.enabled, false, "cam.end released on exit — the rig restored")
	ok(String(ctx.flags.get("spaceWorld", "")).length() > 0,
			"on_exit persisted the system (TS:270-272)")
	stage.on_enter()
	eq(c2d.enabled, true, "re-enter re-arms the rig")


# ---- update(): the camera feed numbers (TS:616-621 — the SPACE constants) ---------

func test_camera_feed_numbers() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	# follow(sim.sx, sim.sy, dt, 5) + zoom 0.85 — NOT the tribe 4/0.95 or the
	# creature 5/1.15 (per-stage constants). The ship idles at (0, −900).
	stage.update(DT)
	eq(float(game.cam.zoom), 0.85, "zoom 0.85 (TS:617)")
	approx(float(game.cam.y), -900.0 * (1.0 - exp(-5.0 * DT)), "follow rate 5: first step", 1e-9)
	approx(float(game.cam.x), 0.0, "cam.x tracks the ship x 0", 1e-9)
	# the toWorld feed — TS:619-621 (the wrapper's world coords for NEXT frame)
	game.input.mx = 400.0
	game.input.my = 300.0
	stage.update(DT)
	var want: Vector2 = game.cam.to_world(400.0, 300.0, game.vw, game.vh)
	approx(float(game.input.wx), want.x, "setWorld x = toWorld(mx, my)", 1e-4)
	approx(float(game.input.wy), want.y, "setWorld y = toWorld(mx, my)", 1e-4)


# ---- update(): the M2 snapshot reaches the sim (keys_held → WASD thrust) ----------

func test_snapshot_wasd_thrust_reaches_the_sim() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var sim: Variant = m["sim"]
	stage.on_enter()
	_flush_held(KEY_W, true)
	ok(stage._build_input_snapshot()["keys_held"].has("KeyW"),
			"keys_held carries the flushed code")
	stage.update(DT)
	eq(float(sim.thrust), 1.0, "WASD thrust observed (the sim read keys_held)")
	ok(float(sim.svy) < 0.0, "the ship accelerated upward")
	approx(float(sim.shipAngle), -PI / 2.0, "shipAngle = atan2(−1, 0)", 1e-9)
	_flush_held(KEY_W, false)
	stage.update(DT)
	eq(float(sim.thrust), 0.0, "release → thrust 0")


# ---- take_click: the wrapper mirror + snapshot freshness (TS:486 the sim take) ----

func test_take_click_mirror_and_freshness() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	var sim: Variant = m["sim"]
	stage.on_enter()
	# a pirate parked 15px off the ship — inside the cursor-thrust deadzone
	# (d < 20 → no engine roll, the burst count stays deterministic); the
	# melee branch is invuln-gated off so ONLY the click lands
	sim.spawn_pirates(1)
	sim.pirates[0]["x"] = float(sim.sx)
	sim.pirates[0]["y"] = float(sim.sy) + 15.0
	sim.invuln = 1.0
	game.input.wx = float(sim.pirates[0]["x"])
	game.input.wy = float(sim.pirates[0]["y"])
	game.input.down = true
	game.input.clicked = true
	stage.update(DT)
	approx(float(sim.pirates[0]["hp"]), 106.0, "the clicked pirate took 34 (TS:484)")
	eq(game.input.clicked, false, "the consumed click cleared the wrapper one-shot (the mirror)")
	eq(stage.fx.active_count(), 8, "the click burst packed 8 rows into the stage pool")
	# freshness: no re-hit without a fresh click; a fresh snapshot's take_click
	# always starts false (the sim consumes via inp["take_click"] on ITS copy)
	var hp: float = float(sim.pirates[0]["hp"])
	game.input.down = false
	stage.update(DT)
	approx(float(sim.pirates[0]["hp"]), hp, "no re-hit without a fresh click")
	eq(stage._build_input_snapshot()["take_click"], false, "take_click starts false (fresh per frame)")


# ---- the panel_rects write-back + the rect-click dispatch (the f1387fe
# contract, TS:1192 + renderPlanetPanel :1195-1231) -----------------------------------

func test_panel_rects_write_back_and_dispatch() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	var sim: Variant = m["sim"]
	stage.on_enter()
	# one live step first: generate_system leaves the planets at (0,0) — the
	# orbit tick places them before the ship can park beside one
	stage.update(DT)
	# park the ship beside planet 0 (inside the r+130 panel range) with 2 cargo
	# rows and a damaged hull; dna 40 (< 50) keeps REPAIR disabled so the
	# hull-fraction label variant shows
	var p: Dictionary = sim.planets[0]
	sim.sx = float(p["x"]) + float(p["r"]) + 80.0
	sim.sy = float(p["y"])
	sim.cargo = [{"genome": GenomeLib.default_genome(), "name": "a"},
			{"genome": GenomeLib.default_genome(), "name": "b"}]
	sim.shp = 60.0
	stage.render()  # the render-side sync collects the button rows (TS:1195)
	stage.update(DT)  # the write-back lands BEFORE sim.update (TS:1192)
	var rows: Array = sim.panel_rects
	eq(rows.size(), 6, "6 button rows (JETTISON rides cargo > 0)")
	eq(String(rows[0]["action"]), "abduct", "row order: abduct first")
	ok(bool(rows[0]["enabled"]), "abduct enabled (eco, cargo < 4, beamT 0)")
	eq(bool(rows[1]["enabled"]), true, "seed enabled at cargo > 0")
	eq(String(rows[2]["action"]), "scan", "scan row third")
	eq(bool(rows[2]["enabled"]), true, "scan enabled at eco")
	eq(String(rows[3]["action"]), "repair", "repair row fourth")
	eq(bool(rows[3]["enabled"]), false, "repair disabled (dna 40 < 50)")
	eq(String(rows[3]["label"]), "🔧 REPAIR (60/100)",
			"the hull-fraction label when disabled (TS:1216)")
	eq(bool(rows[4]["enabled"]), true, "gene lab enabled at cargo ≥ 2")
	eq(String(rows[5]["action"]), "jettison", "jettison row last")
	ok(bool(rows[5]["enabled"]), "jettison always enabled")
	# the fixed frame geometry via the panel_frame/panel_button_rect seams
	# (vw/vh 800/600 headless: x = vw−270, h = 290 at cargo > 0, y = vh−h−150)
	var r0: Dictionary = rows[0]["r"]
	approx(float(r0["x"]), 800.0 - 270.0 + 14.0, "button x = frame x + 14", 1e-9)
	approx(float(r0["y"]), 600.0 - 290.0 - 150.0 + 70.0, "abduct at frame y + 70", 1e-9)
	approx(float(r0["w"]), 250.0 - 28.0, "button w = frame w − 28", 1e-9)
	approx(float(r0["h"]), 30.0, "button h 30", 1e-9)
	approx(float(rows[5]["r"]["y"]), 600.0 - 290.0 - 150.0 + 250.0,
			"jettison at frame y + 250", 1e-9)
	# a rect click through the snapshot dispatches the action end-to-end —
	# JETTISON pops a cargo row (the sim reads what the stage drew)
	var cr: Dictionary = rows[5]["r"]
	game.input.mx = float(cr["x"]) + float(cr["w"]) / 2.0
	game.input.my = float(cr["y"]) + float(cr["h"]) / 2.0
	game.input.wx = sim.sx  # park the world cursor in the thrust deadzone
	game.input.wy = sim.sy
	game.input.down = true
	game.input.clicked = true
	stage.update(DT)
	eq(sim.cargo.size(), 1, "the clicked jettison popped a cargo row")
	eq(game.input.clicked, false, "the consumed click cleared the wrapper one-shot")
	ok(bool(sim.uiHold), "uiHold written on the click frame (TS:431)")
	# out of range: the panel stops drawing (the view gate closes) while the
	# rows STALE-KEEP (TS panelRects keeps the last in-range rows; the sim's
	# own range gate no-ops them) — the write still lands every update
	sim.sx += 5000.0
	stage.render()
	stage.update(DT)
	eq(sim.panel_rects.size(), 6, "the rows stale-keep out of range (TS-verbatim)")
	eq(stage._panel_view, null, "the panel view gate closed (nothing draws)")


# ---- the abilities payload per frame (TS:626-631 via the hud hook) ------------------

func test_abilities_payload_per_frame() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	var sim: Variant = m["sim"]
	stage.on_enter()
	var seen: Array = []
	game.hud["set_abilities"] = func(list: Array) -> void: seen.append(list)
	sim.beamT = 1.0
	stage.update(DT)
	eq(seen.size(), 1, "the hook fires at the END of every update (TS:626-631)")
	var row: Array = seen[0]
	eq(row.size(), 4, "4 ability slots")
	eq(String(row[0]["key"]), "R", "slot key R")
	eq(String(row[0]["icon"]), "🛸", "slot icon 🛸")
	eq(float(row[0]["cd"]), 0.0, "no cooldowns on space")
	ok(bool(row[0]["active"]), "R active while the beam flies")
	eq(String(row[1]["key"]), "F", "slot key F")
	eq(String(row[1]["icon"]), "⏩", "slot icon ⏩")
	ok(not bool(row[1]["active"]), "F inactive (ffHold 0)")
	eq(String(row[2]["key"]), "G", "slot key G")
	eq(String(row[2]["icon"]), "🧪", "slot icon 🧪")
	ok(not bool(row[2]["active"]), "G inactive at cargo 0")
	eq(String(row[3]["key"]), "LMB", "slot key LMB")
	eq(String(row[3]["icon"]), "🔫", "slot icon 🔫")
	eq(row[3].has("active"), false, "the LMB row carries no active key (TS verbatim)")
	# next frame: the beam ended + cargo 2 → R inactive, G active
	sim.beamT = 0.0
	sim.cargo = [{"genome": GenomeLib.default_genome(), "name": "a"},
			{"genome": GenomeLib.default_genome(), "name": "b"}]
	stage.update(DT)
	eq(seen.size(), 2, "fires again next update (every frame)")
	ok(not bool(seen[1][0]["active"]), "R inactive once the beam ends")
	ok(bool(seen[1][2]["active"]), "G active at cargo ≥ 2")


# ---- the ending fade math (TS:1085-1088 — the 2 s in / 1.5 s out windows) -----------

func test_ending_fade_windows() -> void:
	# fade-in: min(1, endingT/2) while the ending plays
	approx(SpaceStage.ending_alpha(false, 0.0, 0.0), 0.0, "the veil opens at 0", 1e-9)
	approx(SpaceStage.ending_alpha(false, 1.0, 0.0), 0.5,
			"half-veiled at 1 s of the 2 s fade-in", 1e-9)
	approx(SpaceStage.ending_alpha(false, 2.0, 0.0), 1.0, "fully veiled at 2 s", 1e-9)
	approx(SpaceStage.ending_alpha(false, 9.0, 0.0), 1.0,
			"the veil holds while un-dismissed", 1e-9)
	# fade-out: max(0, 1 − (endingT − dismissT)/1.5) after dismissal
	approx(SpaceStage.ending_alpha(true, 2.0, 2.0), 1.0,
			"dismissal starts the fade from full", 1e-9)
	approx(SpaceStage.ending_alpha(true, 2.75, 2.0), 0.5,
			"half-clear 0.75 s into the 1.5 s fade-out", 1e-9)
	approx(SpaceStage.ending_alpha(true, 3.5, 2.0), 0.0,
			"fully clear 1.5 s after dismissal", 1e-9)
	approx(SpaceStage.ending_alpha(true, 9.0, 2.0), 0.0,
			"stays clear — the 86%-black-forever bug stays dead", 1e-9)


# ---- the beam draw dispatch: creature-vs-cell on legs (TS:1000-1014) --------------

func test_beam_dispatch_creature_vs_cell() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var sim: Variant = m["sim"]
	stage.on_enter()
	# gate closed → nothing to draw
	stage.render()
	ok(stage.beam_item.genome.is_empty(), "no beam → an empty genome (invisible item)")
	# a beam target with a legs > 0 species → the CREATURE branch
	var eco: Variant = EcoScript.new(m["ctx"].rng.branch())
	var g: Dictionary = GenomeLib.default_genome()
	g["legs"] = 3
	eco.add_species(g, 5.0)
	sim.beamTarget = {"x": 100.0, "y": -500.0, "r": 50.0, "eco": eco}
	sim.beamT = 1.4
	sim.time = 0.5
	stage.render()
	var item: Variant = stage.beam_item
	eq(item.is_cell, false, "legs > 0 → the creature painter branch")
	ok(item.genome == (eco.living()[0]["genome"] as Dictionary), "genome is the species'")
	approx(float(item.pose["x"]), 50.0, "bx = (sx + px)/2", 1e-9)
	approx(float(item.pose["y"]), -700.0, "by = (sy + py)/2 − t·30 (t = 0 at beamT 1.4)", 1e-9)
	approx(float(item.pose["gaitPhase"]), 4.0, "gaitPhase = time·8")
	approx(float(item.pose["scale"]), 1.2, "scale 1.2")
	eq(String(item.pose["mood"]), "afraid", "mood 'afraid'")
	approx(float(item.pose["airborne"]), 1.0, "airborne 1")
	approx(float(item.opts["t"]), 0.5, "opts.t = sim.time")
	# the beam countdown mid-flight: t = 1 − 0.7/1.4 = 0.5 → by −15 more
	sim.beamT = 0.7
	stage.render()
	approx(float(item.pose["y"]), -715.0, "by rides t = 1 − beamT/1.4", 1e-9)
	# legs == 0 → the CELL branch (the default genome has legs 0)
	(eco.living()[0]["genome"] as Dictionary)["legs"] = 0
	stage.render()
	eq(item.is_cell, true, "legs == 0 → the cell painter branch")
	approx(float(item.pose["scale"]), 1.6, "cell scale 1.6")
	approx(float(item.pose["seed"]), 4.0, "cell seed 4 (TS:1011 verbatim)")
	approx(float(item.pose["moveAngle"]), 0.0, "cell moveAngle 0")
	# the beam over (the unclamped decay lands negative — TS:503) → gate closed
	sim.beamT = -0.1
	stage.render()
	ok(item.genome.is_empty(), "beamT ≤ 0 → the dispatch closes again")


# ---- the ship visibility rule (TS:1017-1021) ---------------------------------------

func test_ship_visibility_rule() -> void:
	# the draw site consumes THIS seam; the truth table pins all four rows
	eq(SpaceStage.ship_visible(false, false), true, "flying: visible")
	eq(SpaceStage.ship_visible(true, false), false, "the core absorbs you: hidden")
	eq(SpaceStage.ship_visible(true, true), true, "after dismissal it returns HERE (TS:1017-1019)")
	eq(SpaceStage.ship_visible(false, true), true, "unreachable row: visible")


# ---- the world-layer geometry seams (the draw sites consume these) ----------------

func test_planet_shadow_seam_ladder() -> void:
	# TS:931-934 — three stops on the 0.2r → r span at 0 / 0.7 / 1, evaluated
	# from the OFFSET gradient center; the ladder clamps outside the span
	var hue := 120.0
	var r := 50.0
	var stop0 := RendererScript.hsl(hue, 0.55, 0.55)
	var stop1 := RendererScript.hsl(hue, 0.5, 0.32)
	var stop2 := RendererScript.hsl(hue, 0.5, 0.14)
	var c: Color = SpaceStage.planet_shadow_col(hue, 0.0, r)
	approx(c.r, stop0.r, "inside r0 reads stop 0", 1e-9)
	approx(c.g, stop0.g, "inside r0 reads stop 0", 1e-9)
	approx(c.b, stop0.b, "inside r0 reads stop 0", 1e-9)
	c = SpaceStage.planet_shadow_col(hue, 38.0, r)  # 10 + 0.7·40 = the mid stop
	approx(c.r, stop1.r, "d = mid reads stop 0.7", 1e-9)
	approx(c.g, stop1.g, "d = mid reads stop 0.7", 1e-9)
	approx(c.b, stop1.b, "d = mid reads stop 0.7", 1e-9)
	c = SpaceStage.planet_shadow_col(hue, 50.0, r)
	approx(c.r, stop2.r, "d = r reads stop 1", 1e-9)
	approx(c.b, stop2.b, "d = r reads stop 1", 1e-9)
	c = SpaceStage.planet_shadow_col(hue, 90.0, r)
	approx(c.r, stop2.r, "beyond r1 clamps to stop 1", 1e-9)
	# the interpolation midpoints: t = 0.5 on each span
	var mid_lo: Color = stop0.lerp(stop1, 0.5)
	c = SpaceStage.planet_shadow_col(hue, 24.0, r)
	approx(c.r, mid_lo.r, "span 1 midpoint lerps 0→0.7", 1e-9)
	approx(c.b, mid_lo.b, "span 1 midpoint lerps 0→0.7", 1e-9)
	var mid_hi: Color = stop1.lerp(stop2, 0.5)
	c = SpaceStage.planet_shadow_col(hue, 44.0, r)
	approx(c.r, mid_hi.r, "span 2 midpoint lerps 0.7→1", 1e-9)
	approx(c.b, mid_hi.b, "span 2 midpoint lerps 0.7→1", 1e-9)


func test_beam_quad_seam() -> void:
	# TS:989-997 — the gradient line ports as a vertex-colored quad: ± lw/2
	# perpendicular at both ends; verts 0/3 ship-side, 1/2 planet-side
	var q := SpaceStage.beam_quad(Vector2(0, 0), Vector2(0, -100), 10.0)
	eq(q.size(), 4, "a quad")
	approx(q[0].x, 5.0, "ship-side + perp", 1e-9)
	approx(q[0].y, 0.0, "ship-side + perp", 1e-9)
	approx(q[1].x, 5.0, "planet-side + perp", 1e-9)
	approx(q[1].y, -100.0, "planet-side + perp", 1e-9)
	approx(q[2].x, -5.0, "planet-side − perp", 1e-9)
	approx(q[3].x, -5.0, "ship-side − perp", 1e-9)
	# oblique: dir (0.6, 0.8), perp (−0.8, 0.6), lw 14 → hw 7
	q = SpaceStage.beam_quad(Vector2(0, 0), Vector2(30, 40), 14.0)
	approx(q[0].x, -5.6, "oblique perp x", 1e-6)
	approx(q[0].y, 4.2, "oblique perp y", 1e-6)
	approx(q[1].x, 24.4, "oblique far + perp x", 1e-6)
	approx(q[1].y, 44.2, "oblique far + perp y", 1e-6)


func test_ship_hull_seam() -> void:
	# TS:1132-1136 — moveTo(0,−18) → quad(12,2 → 8,14) → lineTo(−8,14) →
	# quad(−12,2 → 0,−18); the sampled path starts and closes at (0,−18)
	var hull := SpaceStage.hull_points()
	ok(hull.size() > 4, "the sampled path has body")
	approx(hull[0].x, 0.0, "starts at moveTo", 1e-9)
	approx(hull[0].y, -18.0, "starts at moveTo", 1e-9)
	approx(hull[hull.size() - 1].x, 0.0, "closes at moveTo", 1e-9)
	approx(hull[hull.size() - 1].y, -18.0, "closes at moveTo", 1e-9)
	# the first quad's u=0.5 sample: q0·(0,−18) + q1·(12,2) + q2·(8,14) → (8, 0)
	var found := false
	for p in hull:
		if absf(p.x - 8.0) < 1e-6 and absf(p.y) < 1e-6:
			found = true
	ok(found, "the quad(12,2) apex sample (8, 0) present")
	var has_right_wing_root := false
	for p2 in hull:
		if absf(p2.x - 8.0) < 1e-6 and absf(p2.y - 14.0) < 1e-6:
			has_right_wing_root = true
	ok(has_right_wing_root, "the lineTo anchor (8, 14) present")


# ---- the fx hooks → the STAGE pool (TS:53/:355/:478-494) ---------------------------

func test_fx_hooks_feed_the_stage_pool() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	# the stage pool cap — TS `private fx = new Fx(1300)` (:53)
	eq(int(stage.fx.pool.size()), 1300, "stage pool cap 1300")
	# fx_spawn → the stage pool (the engine trail, TS:355 spawns into this.fx)
	stage._h_fx_spawn({"x": 1.0, "y": 2.0, "vx": 3.0, "vy": 4.0, "ttl": 0.5,
			"size": 3.0, "kind": "dot", "color": "#fff", "drag": 3.0})
	eq(stage.fx.active_count(), 1, "fx_spawn landed on the stage pool")
	# fx_burst → the stage pool; the sim's sampled rows pack 1:1 (f1387fe)
	stage._h_fx_burst(0.0, 0.0, 3, {"parts": [
		{"ang": 0.0, "sp": 100.0, "color": "#fff", "ttl": 0.5, "size": 3.0},
		{"ang": 1.0, "sp": 90.0, "color": "#fff", "ttl": 0.5, "size": 3.0},
		{"ang": 2.0, "sp": 80.0, "color": "#fff", "ttl": 0.5, "size": 3.0}]})
	eq(stage.fx.active_count(), 4, "burst rows packed onto the stage pool")
	# the game-pool bridge — stage.update steps game.fx THEN the stage pool
	# (TS:622-623, the game pool first)
	var seen: Array = []
	m["game"].fx["update"] = func(dt: float) -> void: seen.append(dt)
	m["stage"].update(DT)
	eq(seen.size(), 1, "game.fx.update bridged once per update (TS:622)")


# ---- the frozen seam + render guards -----------------------------------------------

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
	var bare: Variant = SpaceStage.new(m["game"])
	bare.render()  # sky_canvas null → early return
	ok(true, "bare render() guarded")
	# a _ready'd stage renders headless (canvas sync + queue_redraw, no draw)
	stage.on_enter()
	stage.render()
	ok(stage.beam_item != null, "ready'd render() headless")
	# post-restore: a saved blob flows through on_enter's restore path and
	# the render keeps working off the restored board
	m["sim"].persist_colonies()
	var blob_v: Variant = JSON.parse_string(m["ctx"].flags["spaceWorld"])
	ok(blob_v is Dictionary, "the persisted blob parses")
	var blob: Dictionary = blob_v
	(blob["planets"][0] as Dictionary)["r"] = 80.0
	(blob["planets"][0] as Dictionary)["scanned"] = true
	(blob["planets"][0] as Dictionary)["colony"] = {"pop": 25.0, "generations": 2.0}
	m["ctx"].flags["spaceWorld"] = JSON.stringify(blob)
	stage.on_enter()
	approx(float(m["sim"].planets[0]["r"]), 80.0, "planet r restored")
	ok(bool(m["sim"].planets[0]["scanned"]), "scanned restored (the whitelist rider)")
	stage.render()
	ok(true, "render() post-restore guarded")
	# a won + dismissed run restores won — and the ship returns (the sandbox)
	(blob as Dictionary)["endingDone"] = true
	(blob as Dictionary)["endingDismissed"] = true
	m["ctx"].flags["spaceWorld"] = JSON.stringify(blob)
	stage.on_enter()
	ok(bool(m["sim"].endingDone) and bool(m["sim"].endingDismissed), "the ending state restored")
	eq(SpaceStage.ship_visible(bool(m["sim"].endingDone), bool(m["sim"].endingDismissed)),
			true, "the dismissed-ending ship is visible (TS:1019)")
	stage.render()
	ok(true, "render() post-ending-restore guarded")


# ---- the backdrop seed (TS:892 — the REAL cam, seed 7; civ used 42) ----------------

func test_backdrop_seed_const() -> void:
	eq(float(SpaceStage.BACKDROP_SEED), 7.0, "drawSpaceBackdrop seed 7 (TS:892)")
