# Tests for src/ui/editor.gd — the editor port (Tasks 8/M2). Ports the editor
# bot-test block of Spore tests/bot.test.ts:119-143 (buy → sell → E-close)
# plus the scope/layout/gate behavior reachable headless: the 'cell' row set,
# part_cost/part_refund DNA math through context.spend_dna, the spend gate +
# legs floor guard, diet/pattern/size/hue row flows, scroll bounds, the
# on_stats_changed hook, the dirty-save on close — and (task 8) the creature
# row scope, land-stat refresh, coat cycles and the preview painter's
# caller-owned RIDs. The REAL-pipeline click path is
# tests/scenes/test_editor_click.gd (xvfb, Constraint 8).
extends "res://tests/test_base.gd"

const EditorUiScript := preload("res://src/ui/editor.gd")
const GameInputScript := preload("res://src/core/input.gd")
const ContextScript := preload("res://src/game/context.gd")
const PartsScript := preload("res://src/evo/parts.gd")
const StatsScript := preload("res://src/evo/stats.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const DT := 1.0 / 60.0
const SCRATCH := "user://test_editor_settings.cfg"


func _en() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_editor_settings.cfg")
		dir.remove("test_editor_settings.cfg.tmp")
	TranslationServer.set_locale("en")


## Duck-typed game (the editor reads context/input/i18n/vw/vh/hud and calls
## save_all()/set_cursor(); on_stats_changed is the stage hook).
class MockGame extends RefCounted:
	var context: Variant
	var input: Variant
	var i18n: Variant
	var vw := 1024.0
	var vh := 600.0
	var toasts: Array = []
	var saves := 0
	var cursors: PackedStringArray = []
	var hud: Dictionary = {}
	var editor: Dictionary = {}

	func _init() -> void:
		context = ContextScript.new(7)
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


var _g: Variant = null
var _ed: Variant = null
var _stats_hooks := 0


func _on_stats() -> void:
	_stats_hooks += 1


func _editor(dna: int = 500) -> Variant:
	_en()
	_g = MockGame.new()
	_g.context.dna = dna
	_ed = EditorUiScript.new(_g)
	_ed.on_stats_changed = _on_stats
	return _ed


func _part_def(id: String) -> Dictionary:
	return PartsScript.part_by_id(id)


func _row(def: Dictionary) -> Dictionary:
	return {"kind": "part", "def": def}


func _flagella_level() -> int:
	return int(_g.context.genome["flagella"])


# ---- bot.test.ts:119-143 port ------------------------------------------------

func test_show_cell_opens_and_resets_scroll() -> void:
	var ed: Variant = _editor()
	eq(bool(ed.open), false, "starts closed")
	ed.list_rect = {"x": 0.0, "y": 0.0, "w": 100.0, "h": 110.0}
	ed.scroll = 33.0
	ed.show("cell")
	eq(bool(ed.open), true, "show opens")
	eq(String(ed.mode), "cell", "mode cell")
	eq(float(ed.scroll), 0.0, "show resets scroll")


func test_cell_row_scope_matches_ts() -> void:
	var ed: Variant = _editor()
	ed.show("cell")
	var rows: Array = ed.rows
	# 9 cell/both parts + diet + pattern + size + hue + sat = 14 (coat is
	# creature-only, editor.ts:86-87)
	eq(rows.size(), 14, "cell editor shows 14 rows")
	var ids := []
	for r in rows:
		ids.append(String(r["kind"]) if r["kind"] != "part" else String(r["def"]["id"]))
	var want := ["flagella", "cilia", "spikes", "jaw", "toxin", "proboscis", "electro",
			"jet", "legs", "diet", "pattern", "size", "hue", "sat"]
	eq(ids, want, "row order is PARTS-filtered then the five special rows")
	ok(not ids.has("arms") and not ids.has("eyes") and not ids.has("brain"),
			"creature-only parts filtered out")
	ok(not ids.has("coat"), "coat row is creature-only")


func test_buy_flagella_spends_part_cost_and_bumps_gene() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	var before := _flagella_level()
	var dna_before := int(_g.context.dna)
	var cost: int = PartsScript.part_cost(_part_def("flagella"), before)
	ed.click_part(_row(_part_def("flagella")), "+")
	eq(_flagella_level(), before + 1, "flagella +1 (bot.test.ts:136)")
	eq(int(_g.context.dna), dna_before - cost, "dna decreased by part_cost (level 2 → 27)")
	eq(_stats_hooks, 1, "on_stats_changed hook fired")
	eq(int(_g.context.stats["speed"]), 60 + 3 * 26, "context stats refreshed for the new level")


func test_sell_flagella_refunds_half() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	ed.click_part(_row(_part_def("flagella")), "+")
	var dna_mid := int(_g.context.dna)
	ed.click_part(_row(_part_def("flagella")), "-")
	eq(_flagella_level(), 2, "sold back to the starter level (bot.test.ts:141)")
	var refund: int = PartsScript.part_refund(_part_def("flagella"), 2)
	eq(int(_g.context.dna), dna_mid + refund, "partial refund credited (starter baseline never paid)")


func test_spend_gate_toasts_and_blocks() -> void:
	var ed: Variant = _editor(5)
	ed.show("cell")
	ed.click_part(_row(_part_def("flagella")), "+")
	eq(_flagella_level(), 2, "dna too low → no buy")
	eq(int(_g.context.dna), 5, "dna untouched")
	eq(_stats_hooks, 0, "no refresh on a blocked buy")
	eq(_g.toasts.size(), 1, "gate toast")
	eq(String(_g.toasts[0][0]), "Not enough DNA", "toast key")
	eq(String(_g.toasts[0][1]), "bad", "toast kind bad")
	eq(String(_g.toasts[0][2]), "🧬", "toast icon")


func test_max_gate_blocks_buy() -> void:
	var ed: Variant = _editor(9999)
	_g.context.genome["flagella"] = 6
	ed.show("cell")
	ed.click_part(_row(_part_def("flagella")), "+")
	eq(_flagella_level(), 6, "at max → no buy")


func test_legs_floor_guard_keeps_the_shore_exit() -> void:
	var ed: Variant = _editor(9999)
	_g.context.genome["legs"] = 1
	ed.show("cell")
	ed.click_part(_row(_part_def("legs")), "-")
	eq(int(_g.context.genome["legs"]), 1, "selling the last LEG is blocked (TS:172-175)")
	eq(_g.toasts.size(), 1, "guard toast")
	eq(String(_g.toasts[0][0]), "Your only way ashore! Keep at least one LEG.", "guard toast key")
	# a second leg sells fine
	_g.context.genome["legs"] = 2
	ed.click_part(_row(_part_def("legs")), "-")
	eq(int(_g.context.genome["legs"]), 1, "above the floor the sell proceeds")
	# min-level bound: no legs → the '-' button is a no-op (no toast)
	var toast_count: int = _g.toasts.size()
	_g.context.genome["legs"] = 0
	ed.click_part(_row(_part_def("legs")), "-")
	eq(int(_g.context.genome["legs"]), 0, "at minLevel → no-op")
	eq(_g.toasts.size(), toast_count, "min-level no-op is silent (TS returns before the toast)")


# QC round-1 carry (r2 B3): creature mode sells the last LEG freely (the
# worm survives on berries — no softlock) but the sell was completely
# silent. A one-line warning mirrors the cell guard's text style WITHOUT
# blocking the sell.
func test_creature_last_leg_sell_warns_but_proceeds() -> void:
	var ed: Variant = _editor(9999)
	_g.context.genome["legs"] = 1
	ed.show("creature")
	ed.click_part(_row(_part_def("legs")), "-")
	eq(int(_g.context.genome["legs"]), 0, "creature mode lets the last LEG sell")
	eq(_g.toasts.size(), 1, "warning toast fired")
	eq(String(_g.toasts[0][0]), "Selling your last LEG — you will only crawl.", "warning text")
	eq(String(_g.toasts[0][1]), "bad", "warning kind")
	# above the floor: sell proceeds without a warning
	_g.context.genome["legs"] = 2
	ed.click_part(_row(_part_def("legs")), "-")
	eq(int(_g.context.genome["legs"]), 1, "legs 2→1 sells")
	eq(_g.toasts.size(), 1, "no warning above the floor")


# ---- the special rows (clickRow programmatic path) ---------------------------

func test_diet_row_cycles_with_cost_gate() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	eq(String(_g.context.genome["diet"]), "omnivore", "starter diet")
	var rect := {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0}
	ed.click_row({"kind": "diet"}, 10.0, rect)
	eq(String(_g.context.genome["diet"]), "carnivore", "omnivore → carnivore (DIETS order)")
	eq(int(_g.context.dna), 500 - 60, "carnivore costs 60")
	ed.click_row({"kind": "diet"}, 10.0, rect)
	eq(String(_g.context.genome["diet"]), "herbivore", "carnivore → herbivore")
	eq(int(_g.context.dna), 440, "herbivore is free")
	ed.click_row({"kind": "diet"}, 10.0, rect)
	eq(String(_g.context.genome["diet"]), "omnivore", "herbivore → omnivore")
	eq(int(_g.context.dna), 400, "omnivore costs 40")


func test_diet_gate_blocks_without_dna() -> void:
	var ed: Variant = _editor(20)
	ed.show("cell")
	ed.click_row({"kind": "diet"}, 10.0, {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0})
	eq(String(_g.context.genome["diet"]), "omnivore", "dna below the next cost → no change")
	eq(String(_g.toasts[0][0]), "Not enough DNA", "gate toast")


func test_pattern_row_buys_next() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	ed.click_row({"kind": "pattern"}, 10.0, {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0})
	eq(String(_g.context.genome["pattern"]), "spots", "plain → spots")
	eq(int(_g.context.dna), 500 - 15, "spots cost 15")


func test_size_row_shrinks_free_grows_30() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	var rect := {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0}
	# left half = shrink — refunds nothing (starter-refund faucet, TS:263-265)
	ed.click_row({"kind": "size"}, 10.0, rect)
	approx(float(_g.context.genome["size"]), 0.8, "size 1.0 → 0.8 (one 0.2 step)", 1e-9)
	eq(int(_g.context.dna), 500, "shrinking refunds nothing and costs nothing")
	# right half = grow — 30 DNA per step
	ed.click_row({"kind": "size"}, 290.0, rect)
	approx(float(_g.context.genome["size"]), 1.0, "back to 1.0 (toFixed2 snap)", 1e-9)
	eq(int(_g.context.dna), 470, "grow costs 30")


func test_hue_sat_rows_drag_sliders() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	var rect := {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0}
	ed.click_row({"kind": "hue"}, 64.0, rect)
	# tt = clamp((64 - 0 - 14) / (300 - 28), 0, 1) = 50/272
	approx(float(_g.context.genome["hue"]), 50.0 / 272.0 * 360.0, "hue maps the click x", 1e-6)
	eq(String(ed.slider_drag), "hue", "hue drag latched (sliderDrag state)")
	ed.click_row({"kind": "sat"}, 150.0, rect)
	approx(float(_g.context.genome["sat"]), 0.05 + (136.0 / 272.0) * 0.95,
			"sat maps the click x into 0.05..1", 1e-6)


# ---- scroll ------------------------------------------------------------------

func test_scroll_clamps_to_content() -> void:
	var ed: Variant = _editor()
	ed.show("cell")
	ed.list_rect = {"x": 0.0, "y": 0.0, "w": 100.0, "h": 110.0}
	var max_scroll: float = 14.0 * 44.0 - 110.0
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	_g.input.handle_event(wheel_down)
	_g.input.handle_event(wheel_down)  # two notches → delta 200
	ed.update(DT)
	approx(float(ed.scroll), minf(200.0 * 0.6, max_scroll), "scroll + w*0.6 clamped to the content", 1e-9)
	_g.input.end_frame()  # the loop clears one-shots between frames
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	_g.input.handle_event(wheel_up)
	_g.input.handle_event(wheel_up)
	_g.input.handle_event(wheel_up)
	ed.update(DT)
	approx(float(ed.scroll), 0.0, "scroll floors at 0", 1e-9)


# ---- KeyE close (editor.ts:112-115) ------------------------------------------

func test_keye_close_saves_when_dirty() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	ed.click_part(_row(_part_def("flagella")), "+")  # dirty
	eq(int(_g.saves), 0, "no save while open")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.pressed = true
	_g.input.handle_event(ev)
	ed.update(DT)
	eq(bool(ed.open), false, "KeyE closes (editor.ts:112)")
	eq(int(_g.saves), 1, "the dirty flag flushes one save on close")


func test_close_without_changes_skips_save() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	ed.close()
	eq(bool(ed.open), false, "close closes")
	eq(int(_g.saves), 0, "not dirty → no save (E-spam write storm guard)")


# ---- creature mode (task 8 — the TS editor.ts creature branch) ---------------

func test_creature_row_scope_matches_ts() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	var rows: Array = ed.rows
	# 10 creature/both parts + coat + diet + pattern + size + hue + sat = 16
	# (editor.ts:83-87 — coat is creature-only)
	eq(rows.size(), 16, "creature editor shows 16 rows")
	var ids := []
	for r in rows:
		ids.append(String(r["kind"]) if r["kind"] != "part" else String(r["def"]["id"]))
	var want := ["spikes", "jaw", "toxin", "legs", "arms", "eyes", "horns", "tail",
			"wings", "brain", "coat", "diet", "pattern", "size", "hue", "sat"]
	eq(ids, want, "row order is PARTS-filtered then coat + the five special rows")
	ok(not ids.has("flagella") and not ids.has("cilia") and not ids.has("proboscis")
			and not ids.has("electro") and not ids.has("jet"),
			"cell-only parts filtered out of creature mode")


func test_creature_buy_arm_refreshes_land_stats() -> void:
	var ed: Variant = _editor(500)
	ed.show("creature")
	var before := int(_g.context.genome["arms"])
	var dna_before := int(_g.context.dna)
	var cost: int = PartsScript.part_cost(_part_def("arms"), before)
	ed.click_part(_row(_part_def("arms")), "+")
	eq(int(_g.context.genome["arms"]), before + 1, "arms +1 in creature mode")
	eq(int(_g.context.dna), dna_before - cost, "dna decreased by part_cost")
	eq(_stats_hooks, 1, "on_stats_changed hook fired")
	# refresh_stats(land=true) — the CREATURE stat shape (compute_creature_stats)
	eq(_g.context.stats, StatsScript.compute_stats(_g.context.genome, true),
			"creature-mode refresh computes the land stat shape")


func test_creature_coat_row_cycles_with_cost_gate() -> void:
	var ed: Variant = _editor(30)
	ed.show("creature")
	eq(String(_g.context.genome["coat"]), "skin", "starter coat")
	ed.click_row({"kind": "coat"}, 10.0, {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0})
	eq(String(_g.context.genome["coat"]), "fur", "skin → fur (COATS order)")
	eq(int(_g.context.dna), 5, "fur costs 25")
	ed.click_row({"kind": "coat"}, 10.0, {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0})
	eq(String(_g.context.genome["coat"]), "fur", "insufficient DNA for scales (35) — blocked")
	eq(int(_g.context.dna), 5, "blocked cycle leaves the DNA untouched")
	eq(_g.toasts.size(), 1, "gate toast")
	eq(String(_g.toasts[0][0]), "Not enough DNA", "coat gate toast key")


func test_creature_preview_paints_and_frees_caller_rids() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	var ci := Node2D.new()  # offscreen bare canvas item (painter-test pattern)
	ed._draw_preview(ci, 100.0, 300.0)
	eq(ed._preview_rids.size(), 3, "preview stores the three caller-owned sub-RIDs")
	for rid in ed._preview_rids:
		ok((rid as RID).is_valid(), "preview sub-RID valid")
	# redraw frees the previous frame's RIDs first (steady-state contract)
	ed._draw_preview(ci, 100.0, 300.0)
	eq(ed._preview_rids.size(), 3, "redraw keeps exactly one RID triple")
	ed.free_preview_rids()
	eq(ed._preview_rids.size(), 0, "free clears the pool")
	ci.free()


func test_editor_dict_mirrors_mode() -> void:
	var ed: Variant = _editor()
	var g: Variant = _g
	g.editor = {"open": false}
	ed.show("creature")
	eq(bool(g.editor["open"]), true, "dict open flag synced")
	eq(String(g.editor["mode"]), "creature", "dict mode synced (stage-switch adoption)")
	ed.close()
	eq(bool(g.editor["open"]), false, "dict open flag cleared on close")


# ---- borrowed_flesh graft rows (buildRows unshift) ---------------------------

func test_graft_rows_for_fired_combo_and_extinct_bestiary() -> void:
	var ed: Variant = _editor(500)
	var c: Variant = _g.context
	c.world["comboFired"]["borrowed_flesh"] = true
	var extinct := {
		"key": "extinct1", "name": "Old Ripper", "stage": "cell",
		"genome": {"jaw": 4, "spikes": 3}, "extinct": true, "seen": 1, "killsByPlayer": 0,
	}
	c.bestiary["extinct1"] = extinct
	ed.show("cell")
	var rows: Array = ed.rows
	eq(rows.size(), 15, "one graft row unshifted in front")
	eq(String(rows[0]["kind"]), "graft", "graft row first")
	eq(String(rows[0]["def"]["id"]), "jaw", "the standout part of the extinct genome")
	eq(int(rows[0]["level"]), 4, "graft target level")
	eq(String(rows[0]["species"]), "Old Ripper", "species name rides the row")
	# buying the graft raises the gene to the target at standard price
	var dna_before := int(c.dna)
	ed.click_row(rows[0], 10.0, {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0})
	eq(int(c.genome["jaw"]), 4, "graft bumps the gene to the target")
	eq(bool(c.flags.get("borrowed_flesh_graft", false)), true, "graft flag latches")
	# cost = partCost(jaw, cur=1 → target 4) summed: 30*1.45 + 30*1.45^2 + 30*1.45^3
	var want_cost := 0
	for l in range(1, 4):
		want_cost += PartsScript.part_cost(_part_def("jaw"), l)
	eq(int(c.dna), dna_before - want_cost, "standard part price, no discount")
	eq(ed.rows.size(), 14, "the slot is spent — the graft rows drop immediately (TS:216)")
