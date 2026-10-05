# Tests for game/tribe/tribe_stage.gd — the tribe stage's non-pixel surface
# (M4 task 4): the hook bindings, the on_enter flow (pack conversion + the
# toastInset/objective hooks), the update() scene-side halves (input snapshot,
# camera follow rate 4 / zoom 0.95, the cam.toWorld feed, the ability slots),
# the hudRects render-side re-registration + the sim click round-trip, the
# z-sorted pool ordering and the main.gd registration pin. Pixel/visual
# behavior lives in tests/scenes/test_tribe_scene.gd (xvfb).
# TS source: Spore src/game/tribe/TribeStage.ts (frozen), lines cited per pin.
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const TribeStage := preload("res://src/game/tribe/tribe_stage.gd")
const TribeSim := preload("res://src/game/tribe/tribe_sim.gd")
const MainScript := preload("res://src/main.gd")

const DT := 1.0 / 60.0
const SEED := 0x7E12E
const Z_TO_Y := 0.62
const OBJECTIVE := "GATHER · BUILD · SURVIVE — raise the Great Totem"


# ---- fixtures ------------------------------------------------------------------

# A real Game (headless: cam.cam2d stays null until tree entry — guarded) +
# a tribe stage whose _ready ran manually (the game node is not in the tree in
# `-s` mode, so add_child fires no _ready; StageCanvas children attach fine
# outside the tree and nothing draws headless).
func _mk_stage(seed_v: int = SEED) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	var game: Variant = GameScript.new(ctx)
	var stage: Variant = TribeStage.new(game)
	game.register(stage)
	stage._ready()  # the tree would normally fire this at register time
	var st: Variant = stage.sim
	return {"game": game, "stage": stage, "ctx": ctx, "sim": st}


# ---- hook bindings (the task-3 carry-in: the storyteller seam) ------------------

func test_hooks_bind_all_sim_keys() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var hooks: Dictionary = stage._build_hooks()
	# every key the sim fires or reads (the carry-in's 4 storyteller reads +
	# hud_float_world included) resolves to a Callable on the stage
	var want := ["hud_toast", "hud_toast_gate", "hud_banner", "hud_toast_inset",
			"hud_show_objective",
			"hud_float_world", "audio_play", "audio_set_mood", "cam_shake",
			"fx_burst", "fx_spawn", "get_gap_bias", "get_mood", "get_warn_scale",
			"storyteller_note_chaos_event", "context_event", "go_to", "save_all"]
	for k in want:
		ok(hooks.get(k) is Callable, "hook %s bound" % k)
	eq(hooks.size(), want.size(), "no stray hooks")
	# the storyteller reads return the game storyteller's live values
	eq(float(hooks["get_gap_bias"].call()), float(m["game"].storyteller.gap_bias()),
			"get_gap_bias reads the storyteller")
	eq(String(hooks["get_mood"].call()), String(m["game"].storyteller.mood),
			"get_mood reads the storyteller")
	eq(float(hooks["get_warn_scale"].call()), float(m["game"].storyteller.warn_scale()),
			"get_warn_scale reads the storyteller")


# ---- on_enter: pack conversion + the hud hooks (TS:139-191) ----------------------

func test_on_enter_founds_pack_and_sets_hud() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var hud: Variant = stage.hud_inst
	stage.on_enter()
	# pack conversion ONCE (flags.packGenomes absent → minimum 3, TS:181)
	eq(m["sim"].tribe.size(), 3, "minimum 3 tribesmen founded")
	eq(String(m["ctx"].flags.get("packGenomes", "")), "[]", "packGenomes reset")
	for t in m["sim"].tribe:
		eq(String(t["role"]), "gather", "founders take the gather role")
	# the sim's hud hooks landed on the stage's hud instance
	eq(float(hud.toast_inset), 190.0, "hud_toast_inset 190 (TS:154 — first native setter)")
	eq(String(hud.show_objective), OBJECTIVE, "showObjective set (TS:190)")
	# the overlay dicts point at THIS stage's instances
	ok(m["game"].hud.get("toast") is Callable, "hud dict installed")
	ok(m["game"].pause.get("update") is Callable, "pause dict installed")


func test_on_enter_restore_sets_objective_only() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	# a saved village restores as it stood (the restore path short-circuits
	# BEFORE pack conversion — no 3-founder minimum)
	var blob := {
		"food": 42.0, "wood": 17.0,
		"huts": [{"x": 30.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0, "pop": 0.0, "buildT": 0.0}],
		"totemProg": 5.0, "totemActive": false,
		"tribe": [{"genome": m["ctx"].genome, "role": "warrior"}],
	}
	m["ctx"].flags["tribeState"] = JSON.stringify(blob)
	stage.on_enter()
	eq(m["sim"].tribe.size(), 1, "restored roster REPLACES (no founder minimum)")
	eq(String(m["sim"].tribe[0]["role"]), "warrior", "role restored")
	approx(float(m["sim"].food), 42.0, "food restored")
	eq(String(stage.hud_inst.show_objective), OBJECTIVE, "objective set on the restore path too")


# ---- update(): snapshot, camera, abilities (TS:278-418 scene halves) -------------

func test_update_camera_rate4_zoom095_and_world_feed() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	# displace the chief so the follow has ground to cover
	m["sim"].px = 500.0
	m["sim"].pz = 100.0
	game.input.mx = 200.0
	game.input.my = 150.0
	stage.update(DT)
	# TS:371-372 — follow rate 4 (creature 5), zoom 0.95 (creature 1.15)
	var k: float = 1.0 - exp(-4.0 * DT)
	approx(float(game.cam.x), 500.0 * k, "cam.x follow rate 4", 1e-9)
	approx(float(game.cam.y), (100.0 * Z_TO_Y) * k, "cam.y target pz·Z_TO_Y", 1e-9)
	approx(float(game.cam.zoom), 0.95, "zoom 0.95")
	# TS:373-377 — wx/wy from cam.to_world land on the input wrapper
	var wpt: Vector2 = game.cam.to_world(200.0, 150.0, game.vw, game.vh)
	approx(float(game.input.wx), wpt.x, "wx from cam.to_world")
	approx(float(game.input.wy), wpt.y, "wy from cam.to_world")


func test_update_feeds_role_abilities() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	stage.on_enter()
	stage.update(DT)
	var ab: Array = stage.hud_inst.abilities
	eq(ab.size(), 3, "three role slots")
	eq(String(ab[0]["key"]), "1", "slot 1 key")
	eq(String(ab[0]["icon"]), "🍒", "slot 1 icon")
	eq(String(ab[1]["icon"]), "🥩", "slot 2 icon")
	eq(String(ab[2]["icon"]), "⚔️", "slot 3 icon")
	# founders are all gather → slot 1 active only (TS:413)
	ok(bool(ab[0]["active"]), "all-gather lights slot 1")
	ok(not bool(ab[1]["active"]), "slot 2 dark")
	ok(not bool(ab[2]["active"]), "slot 3 dark")
	for t in m["sim"].tribe:
		t["role"] = "warrior"
	stage.update(DT)
	ab = stage.hud_inst.abilities
	ok(bool(ab[2]["active"]), "all-warrior lights slot 3")
	ok(not bool(ab[0]["active"]), "slot 1 dark")
	# an empty tribe lights nothing (TS:413's `&& this.tribe.length > 0`)
	m["sim"].tribe.clear()
	stage.update(DT)
	ab = stage.hud_inst.abilities
	ok(not bool(ab[0]["active"]) and not bool(ab[2]["active"]),
			"empty tribe: no slot active")


func test_update_frozen_seam_holds_the_sim() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	stage.on_enter()
	stage.frozen = true
	var t0: float = float(m["sim"].time)
	stage.update(DT)
	approx(float(m["sim"].time), t0, "frozen: the sim does not step")


# ---- hudRects: render-side registration + the sim click round-trip ---------------

func test_hudrects_registered_per_render() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	eq(m["sim"].hudRects.size(), 0, "no rects before the first render")
	stage.render()
	var rects: Array = m["sim"].hudRects
	eq(rects.size(), 2, "hut + totem registered")
	eq(String(rects[0]["action"]), "hut", "hut rect first")
	var r: Dictionary = rects[0]["r"]
	eq(int(float(r["x"])), 18, "hut rect x 18 (TS:1409)")
	eq(int(float(r["y"])), int(game.vh - 110.0), "hut rect y vh-110 (TS:1409)")
	eq(int(float(r["w"])), 170, "hut rect w 170 (TS:1408)")
	eq(int(float(r["h"])), 40, "hut rect h 40 (TS:1408)")
	var r2: Dictionary = rects[1]["r"]
	eq(String(rects[1]["action"]), "totem", "totem rect second")
	eq(int(float(r2["y"])), int(game.vh - 64.0), "totem rect y vh-64 (TS:1417)")
	# re-registration replaces, never stacks (the TS filter+push)
	stage.render()
	eq(m["sim"].hudRects.size(), 2, "re-render keeps exactly two rects")


func test_hudrect_click_dispatches_in_update() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	stage.render()
	# click the hut button with 30 wood → the wood toast, NO hut, click consumed
	var r: Dictionary = m["sim"].hudRects[0]["r"]
	game.input.mx = float(r["x"]) + 5.0
	game.input.my = float(r["y"]) + 5.0
	game.input.clicked = true
	stage.update(DT)
	ok(bool(stage.hud_inst._toasts.size() > 0), "wood toast fired")
	ok(String(stage.hud_inst._toasts[0]["text"]).find("40 wood") >= 0,
			"the Need-40-wood toast")
	eq(m["sim"].huts.size(), 1, "no hut built")
	ok(not game.input.was_clicked(), "click consumed (TS inp.takeClick shared-input mirror)")
	# afford the hut, re-render (rects fresh), click again → built
	m["sim"].wood = 80.0
	m["sim"].hutCd = 0.0
	stage.render()
	r = m["sim"].hudRects[0]["r"]
	game.input.mx = float(r["x"]) + 5.0
	game.input.my = float(r["y"]) + 5.0
	game.input.clicked = true
	stage.update(DT)
	eq(m["sim"].huts.size(), 2, "afforded hut built from the panel click")
	approx(float(m["sim"].wood), 40.0, "40 wood spent")


func test_hudrect_hover_upgrades_cursor() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	var game: Variant = m["game"]
	stage.on_enter()
	stage.render()
	# the frame base (crosshair) is game._do_update's job — seed it here; the
	# stage's TS-true surface is the hover UPGRADE only (TS:288-289)
	game.set_cursor("crosshair")
	var r: Dictionary = m["sim"].hudRects[0]["r"]
	game.input.mx = float(r["x"]) + 5.0
	game.input.my = float(r["y"]) + 5.0
	stage.update(DT)
	eq(String(game._cursor), "pointer", "panel hover upgrades the cursor (TS:288-289)")
	# off-panel hover issues no upgrade — the base survives (the game loop
	# re-resolves it at end of frame; the X11 cursor-swallow ruling)
	game.set_cursor("crosshair")
	game.input.mx = 500.0
	game.input.my = 50.0
	stage.update(DT)
	eq(String(game._cursor), "crosshair", "no spurious hover off-panel")


# ---- z-sorted pool ordering (Ruling 14 class, the ordering half) -----------------

func test_zsort_pool_order_tribesman_over_chief() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	stage.on_enter()
	# the scene fixture: a tribesman at z 100 over the chief at z 60 (the other
	# two founders pinned below so the order is fully determined)
	m["sim"].tribe[0]["z"] = 100.0
	m["sim"].tribe[1]["z"] = 20.0
	m["sim"].tribe[2]["z"] = 30.0
	m["sim"].pz = 60.0
	stage._sync_creature_items()
	eq(stage._body_pool.size(), 4, "3 tribesmen + chief pooled")
	# ascending z: 20 → 30 → chief 60 → 100 (the z-100 tribesman draws LAST,
	# over the chief)
	var chief: Variant = stage._body_pool[2]
	var tribesman: Variant = stage._body_pool[3]
	ok(chief.genome == m["ctx"].genome, "pool[2] is the chief (z 60)")
	ok(tribesman.genome == m["sim"].tribe[0]["genome"], "pool[3] is the z-100 tribesman")
	ok(stage._body_pool[0].genome == m["sim"].tribe[1]["genome"], "pool[0] is the z-20 tribesman")
	approx(float(chief.pose["scale"]), 2.1, "chief scale 2.1 (TS:1362)")
	approx(float(chief.pose["y"]), 60.0 * Z_TO_Y, "chief feet at pz·Z_TO_Y")
	approx(float(tribesman.pose["scale"]), 1.7, "tribesman scale 1.7 (TS:1312)")
	eq(String(chief.pose["mood"]), "happy", "chief mood happy")
	# the chief's 👑 rides the extras item; the tribesman's bar slots too
	eq(String(stage._extra_pool[2].icon), "👑", "chief crown on the chief's extras item")


func test_zsort_chief_hidden_in_death_fade() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	stage.on_enter()
	m["sim"].deathFade = 0.5  # > 0.4 hides the pair entirely (TS:1359)
	stage._sync_creature_items()
	var found := false
	for i in stage._body_pool.size():
		var b: Variant = stage._body_pool[i]
		if b.genome == m["ctx"].genome:
			found = true
	ok(not found, "no pool item carries the chief genome at deathFade > 0.4")


# ---- night window + render guards -------------------------------------------------

func test_is_night_window() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	m["sim"].dayPhase = 0.7
	ok(stage._is_night(), "0.7 inside the (0.55, 0.95) window")
	m["sim"].dayPhase = 0.5
	ok(not stage._is_night(), "0.5 day")
	m["sim"].dayPhase = 0.96
	ok(not stage._is_night(), "0.96 past the window")


## The TS:1292 round-of-fraction quirk pinned at the renderer seam (the
## task-7 review Minor 2): the label composes from the 0..1 FRACTION
## (progress/100), so the round reads 0% until the pole is half-built and 1%
## after — never the true percent. The draw site consumes the static
## totem_progress_label directly (no copy), so this string assert pins the
## live production path; the visual moments pin label PRESENCE at 45%/75%,
## this pins the NUMBER.
func test_totem_progress_label_round_of_fraction_quirk() -> void:
	eq(TribeStage.totem_progress_label(0.45), "TOTEM 0%", "45% built reads 0% (the quirk)")
	eq(TribeStage.totem_progress_label(0.5), "TOTEM 1%", "the half boundary rounds up like Math.round")
	eq(TribeStage.totem_progress_label(0.75), "TOTEM 1%", "75% built still reads 1% (the quirk)")
	eq(TribeStage.totem_progress_label(0.999), "TOTEM 1%",
			"a hair under done still reads 1% (the label hides at p ≥ 1)")


func test_render_guards() -> void:
	var m := _mk_stage()
	var stage: Variant = m["stage"]
	# a bare stage (no _ready) renders nothing and does not crash
	var bare: Variant = TribeStage.new(m["game"])
	bare.render()  # sky_canvas null → early return
	ok(true, "bare render() guarded")
	# a _ready'd stage renders headless (pool sync + rect registration, no draw)
	m["stage"].on_enter()
	m["stage"].render()
	ok(m["stage"]._body_pool.size() >= 4, "pool built on headless render")


# ---- main.gd registration (the M4 entry) -------------------------------------------

func test_main_registers_tribe_stage() -> void:
	var src: String = (MainScript as Script).source_code
	ok(src.find("res://src/game/tribe/tribe_stage.gd") >= 0, "main preloads the tribe stage")
	ok(src.find("game.register(TribeStageScript.new(game))") >= 0,
			"main registers TribeStage at boot")
	# M5: the factory list grew a civ tail — the tribe entry now trails into
	# CivStageScript (the M4 shape 'TribeStageScript.new(game)]' ended the
	# list). M6: the list grew a space tail on its own line, so the civ entry
	# now trails into a comma (the d7a5cb8 evolution, one step further).
	ok(src.find("TribeStageScript.new(game), CivStageScript.new(game),") >= 0,
			"the NEW LIFE factory rebuilds the tribe stage too")
