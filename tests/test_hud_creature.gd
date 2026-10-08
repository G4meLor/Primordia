# Tests for the creature stage's HUD receiver side (task 8): the sim's hud_*
# hooks must land in the game.hud dict through the stage's hook routing
# (creature_stage._build_hooks → game.hud[...]) for scripted sim events —
# bone pickups (float_world + toast), the first charm hint, the pack-full
# gate, glorp rewards, death (toast + pack scatter + cam shake + the
# playerDeath context event) — plus the arrival banner/objective/tutorial
# build on enter, the Escape/editor routing against the REAL editor dict,
# the death input gate, the found-tribe tutorial finish and the game.gd
# stage routing (cell → creature handoff reaches the creature stage; the
# editor-open adoption across a direct switch).
#
# TS source: Spore src/game/creature/CreatureStage.ts (frozen) — onEnter
# 258-335 (arrival card 286-294, tutorial table 306-313), the hud call sites
# (bone 778-784, charm hint 1054-1057, pack full 1037, death 616-632, glorp
# 1245-1252), foundTribe's tutorial finish 1645, and main.ts:33-41 (stages
# registered at boot). Out-of-tree boot (test_econ_probes precedent); input
# feeds through input.handle_event directly (headless drops
# parse_input_event — test_game_flow header).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const DT := 1.0 / 60.0
const SEED := 0x8BADF00D
# out 0.55 (33) → card 2.2 (132) → in 0.6 (36) fixed steps
const WALK_STEPS := 33 + 132 + 36


# ---- hud recorder dict (method Callables — defaults absorb the 5-arg shape) ---

var _toasts: Array = []
var _banners: Array = []
var _floats: Array = []
var _abilities: Array = []


func _rec_update(_dt: float) -> void:
	pass


func _rec_dismiss() -> void:
	pass


func _rec_toast(text: String, kind: String, icon: String, _ttl := 4.0,
		_card: Variant = null) -> void:
	_toasts.append([text, kind, icon])


func _rec_banner(m: Variant) -> void:
	_banners.append(m)


func _rec_float(x: float, y: float, text: String, color: Variant, size: float) -> void:
	_floats.append([x, y, text, color, size])


func _rec_pointer(_x: float, _y: float) -> bool:
	return false


func _rec_set_abilities(a: Array) -> void:
	_abilities = a


func _install_recorder_hud(g: Variant) -> void:
	_toasts = []
	_banners = []
	_floats = []
	_abilities = []
	g.hud = {
		"update": _rec_update,
		"dismiss_banner": _rec_dismiss,
		"toast": _rec_toast,
		"banner": _rec_banner,
		"float_world": _rec_float,
		"pointer_down": _rec_pointer,
		"set_abilities": _rec_set_abilities,
		"set_toast_inset": func(_px: float) -> void: pass,  # TS:213 reset routes here
	}


func _toast_texts() -> Array:
	var out := []
	for t in _toasts:
		out.append(String(t[0]))
	return out


# ---- boot ---------------------------------------------------------------------

## Out-of-tree boot: run.gd drives tests synchronously inside _initialize —
## the main loop never reaches a frame, so tree-entered nodes never fire
## _ready; each stage's _ready is invoked ONCE manually (no double-build).
## Nothing in the boot path needs the viewport (vw/vh keep 800×600).
func _boot(with_cell := false) -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.set_process_unhandled_input(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	if with_cell:
		game.register(CellStageScript.new(game))
		game.stages["cell"]._ready()
	game.register(CreatureStageScript.new(game))
	game.stages["creature"]._ready()
	game.step_for_testing(5, DT)  # boot → menu
	return game


func _to_creature(g: Variant) -> void:
	g.switch_stage("creature")


func _feed_key(g: Variant, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	g.input.handle_event(ev)


func _park_world_objects(sim: Variant) -> void:
	for b in sim.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0
	for bo in sim.bones:
		bo["x"] = 99999.0
		bo["z"] = 99999.0


## One sim tick with KeyF held — the T3 canonical snapshot built by hand (the
## wrapper's held-state polls the Input singleton, which headless feeds never
## reach; test_charm precedent). The hooks still route through the stage.
func _hold_f_step(sim: Variant) -> void:
	sim.update(DT, {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": ["KeyF"], "keys_pressed": [],
	})


# ---- on_enter: arrival banner, objective, tutorial ------------------------------

func test_arrival_banner_renames_and_shows_objective() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	# the banner fires DURING on_enter — the real hud dict is live there, so
	# the receiver-side assertion reads the real HudUi state
	var hud: Variant = g.current.hud_inst
	ok(hud._cur_banner != null, "the arrival banner shows")
	if hud._cur_banner != null:
		var ctx: Variant = g.context
		ok(String(ctx.player_name) != "Squish",
				"the creature named itself from its traits (TS:286-289)")
		eq(String(hud._cur_banner["title"]),
				"THE PACK WILL CALL YOU %s" % String(ctx.player_name).to_upper(),
				"arrival banner title (TS:290)")
		eq(String(hud._cur_banner["sub"]),
				"drag yourself forward — the ocean is done with you", "arrival sub")
		eq(String(hud._cur_banner["kind"]), "stage", "arrival kind")
		eq(float(hud._cur_banner["ttl"]), 5.0, "arrival ttl 5")
	eq(String(hud.show_objective),
			"HUNT or CHARM (hold F near a creature) — press TAB for editor",
			"the objective line (TS:305)")
	g.free()


func test_tutorial_builds_ts_table_on_enter() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	var tut: Variant = g.current.tutorial
	ok(tut != null, "the tutorial engine built on enter (TS:306-313)")
	if tut != null:
		eq(String(tut._flag_key), "tutCreature", "per-save-slot flag key")
		eq(int(tut.step_count), 3, "three creature steps")
		eq(String(tut._steps[0]["text"]),
				"Walk with the mouse. 🦴 bones = free DNA. Danger has teeth here.", "step 1 text")
		eq(String(tut._steps[1]["text"]),
				"Hold F next to a creature → press SPACE on the beat ×3 → friend!", "step 2 text")
		eq(String(tut._steps[2]["text"]),
				"Press TAB — the editor works on land too. Brain ×3 unlocks the tribe.", "step 3 text")
		eq(int(tut.step_index), 0, "starts on step 1")
		ok(bool(tut.active), "active on a fresh slot")
	g.free()


func test_found_tribe_finishes_the_tutorial() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_install_recorder_hud(g)
	var sim: Variant = g.current.sim
	ok(bool(g.current.tutorial.active), "tutorial active before founding")
	# the stage mirrors game.transition_target into the sim every update; a
	# forward founding (not quit-to-title) fires the tutorial_finish hook the
	# stage routes into the engine's finish() (TS CreatureStage.ts:1645)
	sim.transitionTarget = "tribe"
	sim.found_tribe()
	var tut: Variant = g.current.tutorial
	eq(bool(tut.active), false, "the founding handoff finished the tutorial")
	eq(String(g.context.flags.get("tutCreature", "")), "done", "the flag persisted per slot")
	ok(g.transition != null, "the tribe handoff transition started")
	# found_tribe's ctx.save() wrote a real slot — test hygiene
	var dir := DirAccess.open("user://saves")
	if dir != null:
		dir.remove("slot0.json")
	g.free()


# ---- hud routing: scripted sim events → the stub dict ---------------------------

func test_bone_pickup_routes_float_toast_and_tut_step() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_install_recorder_hud(g)
	var sim: Variant = g.current.sim
	_park_world_objects(sim)
	# bones[0] is the meteor (TS constructor i===0) — use bones[1], a plain bone
	var bone: Dictionary = sim.bones[1]
	bone["x"] = float(sim.px) + 1.0
	bone["z"] = float(sim.pz)
	var dna_before := int(g.context.dna)
	g.step_for_testing(1, DT)
	eq(_floats.size(), 1, "bone float routed through float_world")
	if _floats.size() == 1:
		eq(String(_floats[0][2]), "+45 DNA 🦴", "bone float text (TS:778)")
		eq(String(_floats[0][3]), "#ffe08a", "bone float color")
		eq(float(_floats[0][4]), 15.0, "bone float size")
	ok(_toast_texts().has("Ancient bones: +45 DNA"), "bone toast routed (TS:783)")
	eq(int(g.context.dna), dna_before + 45, "bone DNA credited")
	# the tutorial's first step polls tut.actioned — the pickup advances it one
	# step later (the tutorial ticks before the sim in stage.update, TS:484)
	g.step_for_testing(1, DT)
	eq(int(g.current.tutorial.step_index), 1, "tutorial advanced past step 1")
	g.free()


func test_charm_hint_fires_exactly_once() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_install_recorder_hud(g)
	var sim: Variant = g.current.sim
	_park_world_objects(sim)
	sim.spawn_ent(null, float(sim.px) + 10.0, float(sim.pz), {}, {})
	_hold_f_step(sim)
	_hold_f_step(sim)
	var hints := 0
	for t in _toasts:
		if String(t[0]).contains("Wait for the beat marker"):
			hints += 1
	eq(hints, 1, "the first charmsSeen hint routes once (TS:1054-1057)")
	eq(int(sim.charmsSeen), 1, "charmsSeen latched")
	g.free()


func test_pack_full_gate_routes_toast() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_install_recorder_hud(g)
	var sim: Variant = g.current.sim
	_park_world_objects(sim)
	# default genome (arms 0, brain 0) → packLimit 2 (TS:182)
	sim.spawn_ent(null, float(sim.px) + 30.0, float(sim.pz), {}, {"pack": true})
	sim.spawn_ent(null, float(sim.px) + 60.0, float(sim.pz), {}, {"pack": true})
	sim.spawn_ent(null, float(sim.px) + 10.0, float(sim.pz), {}, {})
	_hold_f_step(sim)
	ok(_toast_texts().has("Your pack is full (2) — evolve Arms/Brain for more"),
			"pack-full gate toast routed (TS:1037)")
	eq(int(sim.charmActive), 0, "no charm started against a full pack")
	g.free()


func test_glorp_routes_reward_toast_and_float() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_install_recorder_hud(g)
	var sim: Variant = g.current.sim
	var dna_before := int(g.context.dna)
	sim.glorp()
	eq(int(g.context.dna), dna_before + 60, "glorp DNA credited (TS:1247-1248)")
	eq(_floats.size(), 1, "glorp float routed")
	if _floats.size() == 1:
		eq(String(_floats[0][2]), "GLORP! +60", "glorp float text (TS:1250)")
		eq(String(_floats[0][3]), "#e2a4ff", "glorp float color")
		eq(float(_floats[0][4]), 16.0, "glorp float size")
	ok(_toast_texts().has("A Glorp wanders by and shares its plasma."),
			"glorp toast routed (TS:1251)")
	g.free()


func test_death_routes_toast_scatter_shake_and_context_event() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_install_recorder_hud(g)
	var sim: Variant = g.current.sim
	_park_world_objects(sim)
	sim.spawn_ent(null, float(sim.px) + 30.0, float(sim.pz), {}, {"pack": true})
	g.context.set_display_name("Mosi")  # R7: the death toast names the creature
	sim.php = 0.0
	var dna_before := int(g.context.dna)
	g.step_for_testing(1, DT)
	var died := 0
	for t in _toasts:
		if String(t[0]).begins_with("Mosi, You died — lost "):
			died += 1
	eq(died, 1, "death toast routed with the display name (TS:625)")
	var lost := dna_before - int(g.context.dna)
	ok(lost > 0, "the 12% DNA tithe was taken")
	ok(_toast_texts().has("The pack scattered (1 fled)"),
			"pack scatter toast routed (TS:631)")
	ok(float(g.cam._shake_t) > 0.0, "cam shake routed through cam_shake_for")
	eq(int(g.deaths_in_stage), 1, "playerDeath context event reached the game listener")
	ok(float(sim.deathFade) > 0.0, "the death card overlay is live")
	g.free()


func test_death_gates_editor_and_tribe_input() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_install_recorder_hud(g)
	var sim: Variant = g.current.sim
	_park_world_objects(sim)
	sim.php = 0.0
	g.step_for_testing(1, DT)  # death fires; deathFade live
	# the death card ignores stage input until respawn: Tab shows the survive
	# toast instead of opening the editor (TS:468-469)
	_feed_key(g, KEY_TAB)
	g.step_for_testing(1, DT)
	eq(bool(g.editor["open"]), false, "Tab does not open the editor while dead")
	ok(_toast_texts().has("Survive first — evolve while alive"),
			"the survive-first gate toast routes")
	# the found-tribe click is gated the same way (alive gate, TS:1633): a real
	# click ON the button does nothing while dead
	sim.tribeReady = true
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(674.0, 473.0)  # the button rect's center (vw 800)
	click.global_position = click.position
	g.input.handle_event(click)
	g.step_for_testing(1, DT)
	eq(g.transition_target, null, "no tribe handoff fires while dead")
	eq(bool(g.editor["open"]), false, "still no editor")
	g.free()


func test_escape_closes_the_editor_through_the_real_dict() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_install_recorder_hud(g)
	var sim: Variant = g.current.sim
	_park_world_objects(sim)
	# alive gate open: real Tab opens the creature editor through the dict
	_feed_key(g, KEY_TAB)
	g.step_for_testing(1, DT)
	eq(bool(g.editor["open"]), true, "Tab opened the creature editor")
	eq(String(g.editor["mode"]), "creature", "creature mode")
	eq(int(sim.tut["editorOpened"]), 1, "the tutorial editor counter bumped (TS:471)")
	# game.gd Escape routing: editor close wins over the pause
	_feed_key(g, KEY_ESCAPE)
	g.step_for_testing(1, DT)
	eq(bool(g.editor["open"]), false, "Escape closed the editor")
	eq(bool(g.paused), false, "Escape did not open the pause")
	g.free()


# ---- stage routing (game.gd + main.gd registration contract) --------------------

func test_cell_to_creature_handoff_reaches_the_creature_stage() -> void:
	var g: Variant = _boot(true)
	g.switch_stage("cell")
	eq(String(g.context.stage), "cell", "booted into the cell stage")
	# the shore_travel hook shape (cell_stage._h_shore_travel → game.go_to)
	g.go_to("creature", {"title": "THE LONG WALK", "sub": "legs work on land"})
	g.step_for_testing(WALK_STEPS, DT)
	eq(String(g.context.stage), "creature", "the handoff landed on the creature stage")
	eq(String(g.current.id), "creature", "the live stage is the creature stage")
	# overlay dict ownership rides the CURRENT stage (task-7 review fix)
	var inst: Variant = g.stages["creature"].editor_inst
	ok(g.editor["show"].get_object() == inst,
			"the editor dict points at the creature stage's instance")
	g.free()


func test_editor_open_adopts_across_a_direct_stage_switch() -> void:
	var g: Variant = _boot(true)
	g.switch_stage("cell")
	# open the cell editor (real KeyE through the cell stage's editor branch)
	_feed_key(g, KEY_E)
	g.step_for_testing(1, DT)
	eq(bool(g.editor["open"]), true, "cell editor opened")
	# TS shared-Editor semantics: switchStage never closes the editor — a
	# direct switch adopts the open state into the arriving stage's instance
	g.switch_stage("creature")
	eq(bool(g.editor["open"]), true, "the editor stays open across the switch")
	var inst: Variant = g.stages["creature"].editor_inst
	ok(g.editor["show"].get_object() == inst,
			"the adopted dict points at the arriving stage's instance")
	eq(bool(inst.open), true, "the arriving instance carries the open state")
	# Escape closes it through the arriving instance (E-spam guard intact)
	_feed_key(g, KEY_ESCAPE)
	g.step_for_testing(1, DT)
	eq(bool(g.editor["open"]), false, "Escape closes the adopted editor")
	g.free()
