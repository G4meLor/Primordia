# Menu front-end flow round-trips (QC r1 B2 follow-up) — the quit-to-title →
# CONTINUE loop headless, with the REAL PauseMenuUi on the click path:
#   pause open → real click on the rebuilt 'Quit to title' item → save_all →
#   the PRIMORDIA card walk → menu re-entered (slot metas refreshed by
#   on_enter) → continue_slot → lands in the SAVED stage — ×2 full cycles.
#   Plus the corrupt-slot path: tombstone meta, hud toast recorded, and the
#   menu's OWN toast record (menu_toast — drawn by _draw_menu; the live hud
#   renders only inside gameplay stages, so without the menu-side draw the
#   load-fail toast never painted over the menu — QC r1 B2 nit).
#
# House shape (test_game_flow.gd): the real MenuStage is booted headless (the
# draw pass never runs — click routing over the menu canvas stays inert; the
# REAL click flow is tests/scenes/test_menu_quit_continue.tscn under xvfb),
# the cell stage is the scripted fake, input feeds ride input.handle_event
# (the _unhandled_input entry) and the loop clock is step_for_testing only.
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const PauseUiScript := preload("res://src/ui/pause.gd")

const DT := 1.0 / 60.0
# out 0.55 → card 2.2 → in 0.6, in fixed steps (33 / 132 / 36)
const OUT_STEPS := 33
const CARD_STEPS := 132
const IN_STEPS := 36
const SCRATCH_CFG := "user://test_menuqc_settings.cfg"

const CORRUPT_TEXT := "This slot is corrupted — delete it in CONTINUE, or use NEW LIFE"


## Scripted cell stage — the exact surface game.gd's pump + save paths read
## (test_game_flow's FakeCell).
class FakeCellStage extends "res://src/game/stage.gd":
	var updates := 0.0

	func _init(g: Variant) -> void:
		super(g, "cell")

	func update(dt: float) -> void:
		updates += dt


# ---- hud toast recorder --------------------------------------------------------

var _toasts: Array = []


func _rec_toast(text: String, kind: String, icon: String, ttl := 4.0,
		card: Variant = null) -> void:
	_toasts.append({"text": text, "kind": kind, "icon": icon, "ttl": ttl})


# ---- boot ----------------------------------------------------------------------

func _wipe_saves() -> void:
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for i in 3:
			if dir.file_exists("slot%d.json" % i):
				dir.remove("slot%d.json" % i)


## Boot with the REAL PauseMenuUi wired game-side (the cell stage's Task 8
## wiring shape — the FakeCell installs no overlays) and the returned instance
## kept by the caller for the item-rect clicks.
func _menuqc_game(seed_v: int) -> Array:
	var ctx: Variant = ContextScript.new(seed_v)
	var g: Variant = GameScript.new(ctx)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(g)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	g.i18n.settings_path = SCRATCH_CFG
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_menuqc_settings.cfg")
		dir.remove("test_menuqc_settings.cfg.tmp")
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.muted = g.i18n.get_muted()
	var pause_inst: Variant = PauseUiScript.new(g)
	pause_inst.actions = {
		"close_pause": g.close_pause,
		"save_all": g.save_all,
		"toggle_mute": g.toggle_mute,
		"go_to": g.go_to,
		"toast": func(_t: String, _k: String, _i: String) -> void: pass,
	}
	g.pause = {"open": pause_inst.open, "update": pause_inst.update}
	g.hud = {
		"update": func(_dt: float) -> void: pass,
		"dismiss_banner": func() -> void: pass,
		"toast": _rec_toast,
		"banner": func(_m: Variant) -> void: pass,
		"float_world": func(_x: float, _y: float, _t: String, _c: Variant,
				_s: float) -> void: pass,
		"pointer_down": func(_x: float, _y: float) -> bool: return false,
		"set_toast_inset": func(_px: float) -> void: pass,
	}
	g.register(MenuStageScript.new(g))
	g.register(FakeCellStage.new(g))
	g.start()
	return [g, pause_inst]


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the recorder-Callable cycle into this test instance
		g.free()


## Walk the FULL title-card transition (out → card → in) onto the target.
func _walk_card(g: Variant) -> void:
	g.step_for_testing(OUT_STEPS + CARD_STEPS + IN_STEPS + 3, DT)


## Real click into the wrapper (the _unhandled_input entry) — the pause routes
## it from the game's blocked update branch.
func _feed_click(g: Variant, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.input.handle_event(ev)


## Quit to title through the REAL pause path: open → click the Quit item →
## the pause's own _act_quit (save_all + close_pause + the PRIMORDIA card).
func _quit_to_title(g: Variant, pause_inst: Variant) -> void:
	g.open_pause()
	eq(bool(g.paused), true, "pause opened")
	var quit: Dictionary = {}
	for it in pause_inst.items:
		if String(it["label"]).contains("Quit"):
			quit = it
			break
	ok(not quit.is_empty(), "quit item rebuilt while paused")
	_feed_click(g, Vector2(float(quit["x"]) + float(quit["w"]) / 2.0,
			float(quit["y"]) + float(quit["h"]) / 2.0))
	g.step_for_testing(2, DT)  # the blocked branch routes the click to the pause
	eq(g.transition != null, true, "quit transition started")
	eq(g.transition["next"], "menu", "quit targets the menu")
	eq(String(g.transition["title"]), "PRIMORDIA", "quit carries the title card")
	_walk_card(g)
	eq(g.transition, null, "quit transition finished")
	eq(g.current.id, "menu", "menu is current after the quit")
	eq(g.context.stage, "menu", "context stage is menu after the quit")


# ---- tests ---------------------------------------------------------------------

## QC r1 B2 main flow ×2 cycles: quit-to-title → CONTINUE → land in the SAVED
## stage. The pause side rides a REAL click on the rebuilt Quit item; the
## continue side is the menu's own continue_slot (the real-click continue is
## the scene test). on_enter's refresh_slots must present the FRESH metas —
## the QC's stale-metas suspicion, pinned here as a regression guard.
func test_quit_to_title_continue_lands_twice() -> void:
	_wipe_saves()
	var boot: Array = _menuqc_game(0xB2002)
	var g: Variant = boot[0]
	var pause_inst: Variant = boot[1]
	var menu: Variant = g.current
	eq(menu.id, "menu", "boot on the menu")
	# cycle 1: a fresh run autosaves into slot 0
	menu.start_new_game(0, "normal", 0xB2002)
	_walk_card(g)
	eq(g.current.id, "cell", "cycle 1 run is live in the cell")
	eq(g.context.stage, "cell", "cycle 1 context stage")
	ok(FileAccess.file_exists("user://saves/slot0.json"), "cycle 1 save written")
	# quit to title, then CONTINUE back into the saved run
	_quit_to_title(g, pause_inst)
	eq((menu.slot_metas as Array).size(), 3, "metas refreshed on re-enter")
	eq(bool(menu.occupied[0]), true, "the just-saved slot shows occupied")
	eq(menu.view, "title", "menu re-enters on the title view")
	eq(menu.menu_toast, null, "no stale toast on re-enter")
	menu.continue_slot(0)
	eq(g.transition["next"], "cell", "continue targets the SAVED stage")
	eq(String(g.transition["title"]), "WELCOME BACK", "continue card")
	_walk_card(g)
	eq(g.context.stage, "cell", "cycle 1 CONTINUE landed in the saved stage")
	eq(g.current.id, "cell", "cycle 1 landed on the cell stage")
	# cycle 2 — the same loop again on the loaded run
	_quit_to_title(g, pause_inst)
	eq(bool(menu.occupied[0]), true, "cycle 2 metas still fresh")
	menu.continue_slot(0)
	_walk_card(g)
	eq(g.context.stage, "cell", "cycle 2 CONTINUE landed in the saved stage")
	eq(int(g.context.slot), 0, "slot 0 stays the active slot")
	_drop(g)


## Corrupt slot: tombstone meta, hud toast recorded (parity), and the menu's
## OWN toast record set — the load-fail feedback the menu now DRAWS (the live
## hud renders only inside gameplay stages, so the record alone never painted).
func test_corrupt_slot_tombstone_and_menu_toast() -> void:
	_wipe_saves()
	var boot: Array = _menuqc_game(0xB2003)
	var g: Variant = boot[0]
	var menu: Variant = g.current
	var f := FileAccess.open("user://saves/slot1.json", FileAccess.WRITE)
	f.store_string("{{{ junk not json")
	f = null
	# the tombstone row (⚠ name, corrupt stage) is what the menu SHOWS
	var tomb: Variant = menu.slot_meta(1)
	eq(String(tomb["playerName"]), "⚠", "tombstone player name")
	eq(String(tomb["stage"]), "corrupt", "tombstone stage")
	menu.refresh_slots()
	eq(bool(menu.occupied[1]), true, "tombstone occupies the row")
	# the load-fail click: marked, no transition, toast recorded AND menu-drawn
	menu.continue_slot(1)
	ok(menu.corrupt_slots.has(1), "corrupt slot marked")
	eq(g.transition, null, "no transition for the corrupt slot")
	eq(_toasts.size(), 1, "hud toast recorded (state parity)")
	eq(String(_toasts[0]["kind"]), "bad", "hud toast kind bad")
	ok(menu.menu_toast != null, "menu toast record set — _draw_menu paints it")
	eq(String(menu.menu_toast["text"]), CORRUPT_TEXT, "menu toast text")
	eq(String(menu.menu_toast["kind"]), "bad", "menu toast kind")
	eq(String(menu.menu_toast["icon"]), "⚠️", "menu toast icon")
	approx(float(menu.menu_toast["t0"]), menu.t, "menu toast anchored at now")
	approx(float(menu.menu_toast["ttl"]), 4.0, "menu toast ttl")
	# a fresh visit starts clean (no toast from a previous session leaks in)
	menu.on_enter()
	eq(menu.menu_toast, null, "menu toast cleared on re-enter")
	_drop(g)
