# Tests for the R1 micro-tutorials (Task 4): the three tutorial-less stages
# (tribe/civ/space) get a ≤3-step reactive tutorial each on the Task 8 engine
# (src/ui/tutorial.gd). Ports the test_tutorial.gd pattern: a duck-typed
# MockGame, the stage built headless (the scene layer never enters the tree),
# the sim handed in directly, and the done-callables driven through the sims'
# REAL action sites where cheap (civ slider keys + armada launch through the
# input snapshot, the gene-lab merge, the F fast-forward generation tick, the
# tick_second conquest flip) or direct state writes where the action site
# needs a full scene (the cell precedent: "the test drives sim.tut /
# context.genome and watches step_index move"). The on_enter build site and
# the on_exit finish rule ride the same wiring shape as the cell stage's
# (build once per stage instance, finish on every exit except quit-to-menu,
# the done flag keeps a re-entered engine inactive).
extends "res://tests/test_base.gd"

const TutorialScript := preload("res://src/ui/tutorial.gd")
const GameInputScript := preload("res://src/core/input.gd")
const ContextScript := preload("res://src/game/context.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const TribeSimScript := preload("res://src/game/tribe/tribe_sim.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const CivSimScript := preload("res://src/game/civ/civ_sim.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const SpaceSimScript := preload("res://src/game/space/space_sim.gd")
const RngScript := preload("res://src/core/rng.gd")
const I18nScript := preload("res://src/core/i18n.gd")
const ParticlesScript := preload("res://src/gfx/particles.gd")

const DT := 1.0 / 60.0
const SCRATCH := "user://test_tutorials_new_settings.cfg"


# EN locale must be forced: tr_key falls back to the key only in EN, and the
# suite shares one process (test_i18n.gd may have left another locale).
func _en() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_tutorials_new_settings.cfg")
		dir.remove("test_tutorials_new_settings.cfg.tmp")
	TranslationServer.set_locale("en")


## Duck-typed game for the headless tests — the test_tutorial.gd MockGame plus
## the members the stages' _install_overlays/on_enter/update touch
## (close_pause/toggle_mute/go_to for the pause wiring, cam follow/zoom/
## to_world for the tribe update loop, the fx pool dict, transition_target
## for the on_exit finish rule, current for the hud's context-toast guard).
class MockCam extends RefCounted:
	var cam2d: Variant = null
	var zoom := 1.0

	func follow(_x: float, _y: float, _dt: float, _rate: float) -> void:
		pass

	func to_world(mx: float, my: float, _vw: float, _vh: float) -> Vector2:
		return Vector2(mx, my)


class MockGame extends RefCounted:
	var context: Variant
	var input: Variant
	var i18n: Variant
	var vw := 800.0
	var vh := 600.0
	var toasts: Array = []
	var saves := 0
	var cursors: PackedStringArray = []
	var hud: Dictionary = {}
	var pause: Dictionary = {}
	var fx: Dictionary = {"update": func(_dt: float) -> void: pass}
	var transition_target := ""
	var current: Variant = null
	var cam: Variant = MockCam.new()

	func _init() -> void:
		context = ContextScript.new(77)
		context.stage = "menu"  # discover() stays quiet while the boot seeds
		input = GameInputScript.new()
		i18n = I18nScript.new(SCRATCH)
		i18n.set_lang("en")
		hud = {
			"toast": func(text: String, kind: String, icon: String) -> void:
				toasts.append([text, kind, icon]),
		}

	func save_all() -> bool:
		saves += 1
		return true

	func set_cursor(c: String) -> void:
		cursors.append(c)

	func hover_cursor() -> void:
		cursors.append("pointer")

	func close_pause() -> void:
		pass

	func toggle_mute() -> void:
		pass

	func go_to(_id: String, _card: Variant = null) -> void:
		pass


# ---- the tribe tutorial (flag tutTribe) ----------------------------------------

func test_tribe_steps_exact_table() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = TribeStageScript.new(g)
	stage.sim = TribeSimScript.new(g.context, RngScript.new_from(11), {})
	var steps: Array = stage._build_tutorial_steps()
	eq(steps.size(), 3, "the tribe stage ships exactly 3 steps")
	eq(String(steps[0]["id"]), "gather", "step ids")
	eq(String(steps[1]["id"]), "hut", "step ids")
	eq(String(steps[2]["id"]), "totem", "step ids")
	# exact step texts (the tutorial draws them through tr_key)
	eq(String(steps[0]["text"]), "Walk to a tree — a tribesman gathers it", "step 1 text")
	eq(String(steps[1]["text"]), "Press R — build a hut", "step 2 text")
	eq(String(steps[2]["text"]), "Hold T — raise the Great Totem", "step 3 text")


func test_tribe_steps_react_to_state() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = TribeStageScript.new(g)
	stage.sim = TribeSimScript.new(g.context, RngScript.new_from(11), {})
	# the stage's update loop steps the real sim economy (the cell test drove
	# sim.tut directly; the tribe hut step's snapshot rides the ADVANCE, so the
	# test must drive the real stage loop — the sim's gather deliveries are
	# overridden by the explicit stockpile writes below)
	stage.fx = ParticlesScript.new(1000)
	stage.on_enter()
	var tut: Variant = stage.tutorial
	ok(tut != null, "on_enter builds the tribe tutorial")
	ok(tut.active, "fresh flag → active")
	eq(int(tut.step_index), 0, "starts on the gather step")

	# step 1 'gather': the wood stockpile increases >= 1 since the step became
	# active (the snapshot rides the build — step 0's entry IS the build, the
	# founding stock is 30)
	eq(float(stage.tut_wood_snap), 30.0, "the wood snapshot rides step entry")
	stage.sim.wood = 30.5
	stage.update(DT)
	eq(int(tut.step_index), 0, "+0.5 wood does not advance (needs >= 1)")
	stage.sim.wood = 31.0
	stage.update(DT)
	eq(int(tut.step_index), 1, "+1 wood advances")

	# step 2 'hut': the snapshot lands at ITS OWN step entry (the task-4
	# ruling — not at tutorial start): a hut built while the wood step was
	# active must not auto-complete the hut step
	eq(int(stage.tut_hut_snap), 1, "the hut snapshot landed at step entry (the founding hut)")
	stage.update(DT)
	eq(int(tut.step_index), 1, "the founding hut alone does not advance")
	stage.sim.huts.append({"x": 0.0, "z": 90.0, "hp": 100.0, "maxHp": 100.0,
			"pop": 0.0, "buildT": 6.0})
	stage.update(DT)
	eq(int(tut.step_index), 2, "a NEW hut advances")

	# step 3 'totem': totem progress > 0
	stage.update(DT)
	eq(int(tut.step_index), 2, "progress 0 holds")
	stage.sim.totem["progress"] = 0.5
	stage.update(DT)
	eq(int(tut.step_index), 3, "progress > 0 completes the table")
	eq(bool(tut.active), false, "natural end finishes the tutorial")
	eq(String(g.context.flags.get("tutTribe", "")), "done", "tutTribe flag persists")
	eq(int(g.saves), 1, "finish flushed one save")


# ---- the civ tutorial (flag tutCiv) ---------------------------------------------

func test_civ_steps_exact_table() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = CivStageScript.new(g)
	stage.sim = CivSimScript.new(g.context, RngScript.new_from(12), {})
	var steps: Array = stage._build_tutorial_steps()
	eq(steps.size(), 3, "the civ stage ships exactly 3 steps")
	eq(String(steps[0]["id"]), "mil", "step ids")
	eq(String(steps[1]["id"]), "launch", "step ids")
	eq(String(steps[2]["id"]), "conquer", "step ids")
	eq(String(steps[0]["text"]), "Press Q/A — raise military output", "step 1 text")
	eq(String(steps[1]["text"]), "Press 1 — launch an armada", "step 2 text")
	eq(String(steps[2]["text"]), "Touch an enemy city — conquer it", "step 3 text")


func test_civ_steps_react_to_state() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = CivStageScript.new(g)
	stage.sim = CivSimScript.new(g.context, RngScript.new_from(12), {})
	stage.on_enter()
	var tut: Variant = stage.tutorial
	ok(tut != null, "on_enter builds the civ tutorial")
	eq(int(tut.step_index), 0, "starts on the mil step")

	# step 1 'mil': mil output > 4 (the start value) — driven through the REAL
	# slider site (the KeyQ branch of sim.update)
	tut.update(DT)
	eq(int(tut.step_index), 0, "mil 4 holds (strict >)")
	stage.sim.update(DT, {"keys_pressed": ["KeyQ"]})
	eq(float(stage.sim.mil), 5.0, "KeyQ raised mil through the real slider site")
	tut.update(DT)
	eq(int(tut.step_index), 1, "mil > 4 advances")

	# step 2 'launch': launch count >= 1 — the REAL launch site (Digit1 with
	# mil 5: power 9 clears the normal-difficulty gate 6+2, an armada flies)
	stage.sim.update(DT, {"keys_pressed": ["Digit1"]})
	eq(int(stage.sim.launches), 1, "the launch counter rides the launch success site")
	eq(stage.sim.armadas.size(), 1, "one armada in flight")
	tut.update(DT)
	eq(int(tut.step_index), 2, "launch count >= 1 advances")

	# step 3 'conquer': any city owner flips to 'you' — the REAL flip site
	# (tick_second's hearts gate); the capital is not a conquest
	eq(int(stage.sim.conquest_count()), 0, "no conquest at entry")
	stage.sim.cities[1]["influence"] = 100.0
	stage.sim.tick_second()
	eq(int(stage.sim.conquest_count()), 1, "the flip landed")
	tut.update(DT)
	eq(int(tut.step_index), 3, "conquest completes the table")
	eq(bool(tut.active), false, "natural end finishes the tutorial")
	eq(String(g.context.flags.get("tutCiv", "")), "done", "tutCiv flag persists")
	eq(int(g.saves), 1, "finish flushed one save")


# ---- the space tutorial (flag tutSpace) -----------------------------------------

func test_space_steps_exact_table() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = SpaceStageScript.new(g)
	stage.sim = SpaceSimScript.new(g.context, RngScript.new_from(13), {})
	var steps: Array = stage._build_tutorial_steps()
	eq(steps.size(), 3, "the space stage ships exactly 3 steps")
	eq(String(steps[0]["id"]), "abduct", "step ids")
	eq(String(steps[1]["id"]), "genelab", "step ids")
	eq(String(steps[2]["id"]), "evolve", "step ids")
	eq(String(steps[0]["text"]), "Fly near a planet — press R to abduct a species", "step 1 text")
	eq(String(steps[1]["text"]), "Press G — open the gene lab", "step 2 text")
	eq(String(steps[2]["text"]), "Press F — evolve a seeded world a generation", "step 3 text")


func test_space_steps_react_to_state() -> void:
	_en()
	var g: Variant = MockGame.new()
	var stage: Variant = SpaceStageScript.new(g)
	stage.sim = SpaceSimScript.new(g.context, RngScript.new_from(13), {})
	stage.on_enter()
	var tut: Variant = stage.tutorial
	ok(tut != null, "on_enter builds the space tutorial")
	eq(int(tut.step_index), 0, "starts on the abduct step")

	# step 1 'abduct': abduct count >= 1 — the REAL ledger site (beam up a
	# species; the beam resolves through sim.update like the real game). The
	# ship anchors EXACTLY on planet 0 (a lush world — eco guaranteed; the
	# position is re-read before each interaction, the planets orbit).
	var p: Dictionary = stage.sim.planets[0]
	ok(p["eco"] != null, "the first planet carries an ecosystem")
	stage.sim.sx = float(p["x"])
	stage.sim.sy = float(p["y"])
	stage.sim.try_abduct()
	ok(stage.sim.beamTarget != null, "the beam armed")
	for i in 100:
		if stage.sim.abduct_total() >= 1.0:
			break
		stage.sim.update(DT, {})
	eq(float(stage.sim.abduct_total()), 1.0, "the abduct ledger counts one")
	eq(stage.sim.cargo.size(), 1, "one specimen in cargo")
	tut.update(DT)
	eq(int(tut.step_index), 1, "abduct >= 1 advances")

	# step 2 'genelab': gene lab opened >= 1 — the REAL merge site (the G key
	# and the panel button both land in merge_cargo)
	stage.sim.sx = float(p["x"])
	stage.sim.sy = float(p["y"])
	stage.sim.try_abduct()
	for i in 100:
		if stage.sim.cargo.size() >= 2:
			break
		stage.sim.update(DT, {})
	eq(stage.sim.cargo.size(), 2, "two specimens in cargo")
	stage.sim.merge_cargo()
	eq(int(stage.sim.gene_lab_opens), 1, "the gene-lab counter rides the merge site")
	tut.update(DT)
	eq(int(tut.step_index), 2, "gene lab opened >= 1 advances")

	# step 3 'evolve': evolve count >= 1 — seed a world through the REAL seed
	# site, then hold F (the REAL ff tick: generations advance at 26x/30s)
	var near: Variant = stage.sim.nearest_planet()
	stage.sim.sx = float(near["x"])
	stage.sim.sy = float(near["y"])
	stage.sim.seed_nearest()
	var seeded := false
	for q in stage.sim.planets:
		if q["colony"] != null:
			seeded = true
	ok(seeded, "a world was seeded")
	for i in 90:
		if stage.sim.max_colony_generations() >= 1.0:
			break
		stage.sim.update(DT, {"keys_held": ["KeyF"]})
	ok(stage.sim.max_colony_generations() >= 1.0, "a held F evolves a generation")
	tut.update(DT)
	eq(int(tut.step_index), 3, "evolve >= 1 completes the table")
	eq(bool(tut.active), false, "natural end finishes the tutorial")
	eq(String(g.context.flags.get("tutSpace", "")), "done", "tutSpace flag persists")
	eq(int(g.saves), 1, "finish flushed one save")


# ---- the stage wiring (build once / finish rule / done flag) ---------------------

## The cell-stage wiring shape on all three stages: on_enter builds once (the
## instance survives re-entry), a forward exit finishes (the flag persists),
## a quit-to-menu exit does NOT, and the done flag keeps a re-entered engine
## inactive (fire once per run).
func test_wiring_build_once_finish_rules() -> void:
	_en()
	var cfgs: Array = [
		["tribe", TribeStageScript, TribeSimScript, RngScript.new_from(11), "tutTribe"],
		["civ", CivStageScript, CivSimScript, RngScript.new_from(12), "tutCiv"],
		["space", SpaceStageScript, SpaceSimScript, RngScript.new_from(13), "tutSpace"],
	]
	for cfg in cfgs:
		var g: Variant = MockGame.new()
		var stage: Variant = cfg[1].new(g)
		stage.sim = cfg[2].new(g.context, cfg[3], {})
		stage.on_enter()
		var t1: Variant = stage.tutorial
		ok(t1 != null and t1.active, "%s: first entry builds an active tutorial" % cfg[0])
		stage.on_enter()
		ok(stage.tutorial == t1, "%s: re-entry keeps the instance (built once)" % cfg[0])
		# forward exit finishes — the flag persists only on forward evolution
		g.transition_target = cfg[0]
		stage.on_exit()
		eq(String(g.context.flags.get(cfg[4], "")), "done",
				"%s: forward exit finishes the tutorial" % cfg[0])
		eq(int(g.saves), 1, "%s: finish flushed a save" % cfg[0])
		# re-entry after done: build-once keeps the (now inactive) instance
		stage.on_enter()
		ok(stage.tutorial == t1, "%s: re-entry never rebuilds" % cfg[0])
		eq(bool(stage.tutorial.active), false, "%s: the done flag keeps the engine inactive" % cfg[0])
		g.transition_target = cfg[0]
		stage.on_exit()
		eq(int(g.saves), 1, "%s: finish on an inactive engine is a no-op" % cfg[0])
		# quit-to-menu does NOT finish — the tutorial returns next entry
		var g2: Variant = MockGame.new()
		var stage2: Variant = cfg[1].new(g2)
		stage2.sim = cfg[2].new(g2.context, cfg[3], {})
		stage2.on_enter()
		g2.transition_target = "menu"
		stage2.on_exit()
		eq(g2.context.flags.get(cfg[4], ""), "",
				"%s: quit-to-menu leaves the flag (the cell rule)" % cfg[0])
		eq(int(g2.saves), 0, "%s: no save flushed on the menu exit" % cfg[0])


# ---- the i18n rows ----------------------------------------------------------------

func test_step_texts_ship_in_vi() -> void:
	var i: Variant = I18nScript.new(SCRATCH)
	var rows: Dictionary = {
		"Walk to a tree — a tribesman gathers it":
				"Đến gần một cái cây — người bộ tộc sẽ thu hoạch nó",
		"Press R — build a hut": "Nhấn R — xây một túp lều",
		"Hold T — raise the Great Totem": "Giữ T — dựng Great Totem",
		"Press Q/A — raise military output": "Nhấn Q/A — tăng sản lượng quân sự",
		"Press 1 — launch an armada": "Nhấn 1 — phóng hạm đội",
		"Touch an enemy city — conquer it": "Tiếp cận thành phố địch — chinh phục nó",
		"Fly near a planet — press R to abduct a species":
				"Bay gần hành tinh — nhấn R để bắt một loài",
		"Press G — open the gene lab": "Nhấn G — mở Xưởng Gen",
		"Press F — evolve a seeded world a generation":
				"Nhấn F — tiến hóa hành tinh đã gieo mầm thêm một thế hệ",
	}
	for k in rows:
		ok(i.vi_has(k), "vi.csv ships the step text: %s" % k)
	# the draw-time tr resolves in VI (the cell precedent: raw EN key on the
	# step dict, translated at render)
	i.set_lang("vi")
	for k in rows:
		eq(i.tr_key(k), rows[k], "VI translation live: %s" % k)
	i.set_lang("en")
	TranslationServer.set_locale("en")
