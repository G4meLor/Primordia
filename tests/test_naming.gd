# Tests for the R7 experience-redesign task: creature naming. The LOOK name
# row opens the on-canvas picker (a grid of the exact ruled charset, 14 cap,
# backspace + accept/cancel — no DOM/LineEdit, the port IS the Godot target);
# context.set_display_name is the ONE write path (charset filter → edge
# strip → truncate-not-reject; empty/whitespace-only = not set);
# get_display_name() falls back to the self_name(genome) suggestion; the name
# rides the save wire as `creatureName` (type-checked, corrupt → fallback);
# the display sites (editor header, HUD arc, the two death toasts, the menu
# save-slot line) read through get_display_name. The on-canvas click-path
# grid interaction stays with the xvfb editor-click harness (Global
# Constraint 8) — headless, the picker's press dispatch is driven directly
# and the draw wiring is source-scanned (the MN-1 pattern).
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const Names := preload("res://src/evo/names.gd")
const EditorUi := preload("res://src/ui/editor.gd")
const GameInput := preload("res://src/core/input.gd")
const I18n := preload("res://src/core/i18n.gd")
const MenuStage := preload("res://src/game/menu.gd")

const SCRATCH := "user://test_naming_settings.cfg"
const SLOT := 907  # dedicated naming slot (test slots are 90+, real slots 0+)
const RECT := {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0}


func _en() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_naming_settings.cfg")
		dir.remove("test_naming_settings.cfg.tmp")
	TranslationServer.set_locale("en")


func _path(n: int) -> String:
	return "user://saves/slot%d.json" % n


func _wipe(n: int) -> void:
	if FileAccess.file_exists(_path(n)):
		DirAccess.remove_absolute(_path(n))


func _write_raw(n: int, text: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(_path(n), FileAccess.WRITE)
	f.store_string(text)


## Duck-typed game — the test_editor_look.gd MockGame shape (the editor reads
## context/input/i18n and calls save_all()/set_cursor(); on_stats_changed is
## the stage hook).
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
		context = Ctx.new(7)
		input = GameInput.new()
		i18n = I18n.new(SCRATCH)
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
	_ed = EditorUi.new(_g)
	_ed.on_stats_changed = _on_stats
	return _ed


## Press a picker button by kind (+char) — the headless shape of the xvfb
## click path (update() routes recorded rects to the same dispatch).
func _press(kind: String, ch := "") -> void:
	_ed._picker_click({"kind": kind, "ch": ch, "r": {}})


# ---- the charset const + the central sanitizer -------------------------------

func test_charset_const_is_exact() -> void:
	eq(String(Names.NAME_CHARSET),
			"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 '-",
			"the exact ruled charset (A-Z a-z 0-9 space apostrophe dash)")
	eq(int(Names.NAME_CHARSET.length()), 65, "26 + 26 + 10 + 3 glyphs")
	eq(int(Names.NAME_MAX_LEN), 14, "the ruled cap")


func test_sanitize_name_filters_strips_and_truncates() -> void:
	eq(String(Names.sanitize_name("Mèos特色产业")), "Mos", "non-charset glyphs strip")
	eq(String(Names.sanitize_name("abcdefghijklmnopqrst")), "abcdefghijklmn",
			"truncate-not-reject at 14")
	eq(String(Names.sanitize_name("  Bao-Bao O'Neil 2 ")).length(), 14,
			"apostrophe/dash/space/digits survive; over-length clamps")
	eq(String(Names.sanitize_name("Bao-Bao O'Neil 2")), "Bao-Bao O'Neil",
			"the 14-glyph prefix is kept verbatim")
	eq(String(Names.sanitize_name("   ")), "", "whitespace-only → empty (not set)")
	eq(String(Names.sanitize_name("")), "", "empty → empty")


# ---- context: the one write path + the display fallback ----------------------

func test_set_display_name_filters_and_stores() -> void:
	var ctx = Ctx.new(7)
	# the brief's exact probe: the filter strips è and the CJK run
	eq(String(ctx.set_display_name("Mèos特色产业")), "Mos",
			"set_display_name returns the filtered value")
	eq(String(ctx.creature_name), "Mos", "the filtered value stored")
	eq(String(ctx.get_display_name()), "Mos", "get_display_name returns the saved name")


func test_get_display_name_falls_back_to_suggestion() -> void:
	var ctx = Ctx.new(7)
	eq(String(ctx.get_display_name()), String(Names.self_name(ctx.genome)),
			"unset → the self_name(genome) suggestion")


func test_empty_or_whitespace_name_is_not_set() -> void:
	var ctx = Ctx.new(7)
	eq(String(ctx.set_display_name("")), "", "empty stores not-set")
	eq(String(ctx.get_display_name()), String(Names.self_name(ctx.genome)),
			"display falls back after an empty set")
	eq(String(ctx.set_display_name("   ")), "", "whitespace-only stores not-set")
	eq(String(ctx.get_display_name()), String(Names.self_name(ctx.genome)),
			"display falls back after a whitespace-only set")


# ---- save wire ----------------------------------------------------------------

func test_name_survives_save_load_round_trip() -> void:
	_wipe(SLOT)
	var ctx = Ctx.new(777)
	ctx.stage = "cell"
	ctx.set_display_name("Bao-Bao O'Neil")  # exactly 14 glyphs
	ok(ctx.save(SLOT), "save into the slot")
	var loader = Ctx.new(999)
	ok(loader.load(SLOT), "load succeeds")
	eq(String(loader.creature_name), "Bao-Bao O'Neil", "name survives the wire")
	eq(String(loader.get_display_name()), "Bao-Bao O'Neil", "display name after load")
	# the camelCase TS-verbatim wire key
	var parsed: Variant = JSON.parse_string(_read_slot(SLOT))
	ok(parsed is Dictionary and parsed.has("creatureName"), "wire key creatureName present")
	if parsed is Dictionary:
		eq(String(parsed["creatureName"]), "Bao-Bao O'Neil", "wire value verbatim")


func _read_slot(n: int) -> String:
	return FileAccess.get_file_as_string(_path(n))


func test_load_type_checks_creature_name() -> void:
	# a valid base save first, then corrupt the one field
	_wipe(SLOT)
	var ctx = Ctx.new(777)
	ctx.stage = "cell"
	ctx.set_display_name("Mosi")
	ok(ctx.save(SLOT), "base save")
	var suggestion: String = String(Names.self_name(ctx.genome))
	# non-string junk → not set → the display falls back (no crash)
	var d: Dictionary = JSON.parse_string(_read_slot(SLOT))
	d["creatureName"] = 42.0
	_write_raw(SLOT, JSON.stringify(d))
	var loader = Ctx.new(999)
	ok(loader.load(SLOT), "load survives a numeric creatureName")
	eq(String(loader.creature_name), "", "non-string → not set")
	eq(String(loader.get_display_name()), suggestion, "corrupt → the suggestion fallback")
	# whitespace junk → sanitized to not-set on the read path too
	d = JSON.parse_string(_read_slot(SLOT))
	d["creatureName"] = "   "
	_write_raw(SLOT, JSON.stringify(d))
	var loader2 = Ctx.new(999)
	ok(loader2.load(SLOT), "load survives a whitespace creatureName")
	eq(String(loader2.creature_name), "", "whitespace-only → not set")
	# a pre-R7 save without the key at all reads as not-set
	d = JSON.parse_string(_read_slot(SLOT))
	d.erase("creatureName")
	_write_raw(SLOT, JSON.stringify(d))
	var loader3 = Ctx.new(999)
	ok(loader3.load(SLOT), "load survives a missing creatureName")
	eq(String(loader3.get_display_name()), suggestion, "missing key → the suggestion fallback")


# ---- the editor picker (headless press dispatch; clicks stay with xvfb) ------

func test_name_row_opens_the_picker_with_the_suggestion_draft() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	ed.switch_tab("look")
	eq(bool(ed.picker_open), false, "closed until the row is clicked")
	ed.click_row({"kind": "name"}, 10.0, RECT)
	eq(bool(ed.picker_open), true, "the LOOK name row opens the picker")
	eq(String(ed.picker_buf), String(Names.self_name(_g.context.genome)),
			"the draft starts at the display name (the suggestion when unset)")
	eq(int(_g.context.dna), 500, "opening costs nothing")
	eq(_stats_hooks, 0, "no stats hook for opening")
	eq(bool(ed.dirty_since_save), false, "opening never dirties the save")
	_press("cancel")
	eq(bool(ed.picker_open), false, "cancel closes the picker")
	eq(String(_g.context.creature_name), "", "cancel stores nothing")


func test_picker_glyph_press_backspace_and_cap() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	ed.switch_tab("look")
	ed.click_row({"kind": "name"}, 10.0, RECT)
	var suggestion := String(Names.self_name(_g.context.genome))
	eq(String(ed.picker_buf), suggestion, "the draft starts at the suggestion")
	_press("backspace")  # drop the suggestion's last glyph
	eq(String(ed.picker_buf).length(), suggestion.length() - 1,
			"backspace pops the last glyph")
	for i in suggestion.length():
		_press("backspace")  # clear the draft entirely
	eq(String(ed.picker_buf), "", "the draft clears")
	# 16 presses of one glyph — the draft caps at 14 (the truncate-not-reject cap)
	for i in 16:
		_press("glyph", "a")
	eq(String(ed.picker_buf).length(), 14, "the draft gates at NAME_MAX_LEN")
	eq(String(ed.picker_buf), "aaaaaaaaaaaaaa", "the capped draft")
	_press("cancel")
	eq(String(_g.context.creature_name), "", "cancel after edits stores nothing")


func test_picker_accept_stores_via_the_central_filter() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	ed.switch_tab("look")
	ed.click_row({"kind": "name"}, 10.0, RECT)
	for i in String(ed.picker_buf).length():
		_press("backspace")  # clear the pre-filled suggestion draft
	for ch in ["M", "o", "s", "i"]:
		_press("glyph", String(ch))
	_press("accept")
	eq(bool(ed.picker_open), false, "accept closes the picker")
	eq(String(_g.context.creature_name), "Mosi", "accept stored through set_display_name")
	eq(String(_g.context.get_display_name()), "Mosi", "the display name follows")
	eq(bool(ed.dirty_since_save), true, "a real change dirties the save (close() persists)")


func test_picker_accept_is_dirty_only_on_a_real_change() -> void:
	var ed: Variant = _editor()
	_g.context.set_display_name("Mosi")
	ed.show("creature")
	ed.switch_tab("look")
	ed.click_row({"kind": "name"}, 10.0, RECT)
	eq(String(ed.picker_buf), "Mosi", "the draft starts at the saved name")
	_press("accept")  # unchanged
	eq(bool(ed.dirty_since_save), false, "re-accepting the same name does not dirty")
	_press("glyph", "2")
	_press("accept")
	eq(String(_g.context.creature_name), "Mosi2", "the edit stored")
	eq(bool(ed.dirty_since_save), true, "a real change dirties")


func test_picker_accept_empty_falls_back_to_the_suggestion() -> void:
	var ed: Variant = _editor()
	_g.context.set_display_name("Mosi")
	ed.show("creature")
	ed.switch_tab("look")
	ed.click_row({"kind": "name"}, 10.0, RECT)
	for i in 6:
		_press("backspace")  # clear the draft entirely
	eq(String(ed.picker_buf), "", "the draft cleared")
	_press("accept")
	eq(String(_g.context.creature_name), "", "empty accept = not set")
	eq(String(_g.context.get_display_name()), String(Names.self_name(_g.context.genome)),
			"display falls back to the suggestion")


func test_switch_tab_show_and_close_reset_the_picker() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	ed.switch_tab("look")
	ed.click_row({"kind": "name"}, 10.0, RECT)
	eq(bool(ed.picker_open), true, "open")
	ed.switch_tab("body")
	eq(bool(ed.picker_open), false, "a tab switch closes the picker")
	ed.switch_tab("look")
	ed.click_row({"kind": "name"}, 10.0, RECT)
	ed.close()
	eq(bool(ed.picker_open), false, "close() resets the picker")
	ed.show("cell")
	eq(bool(ed.picker_open), false, "every show() starts clean")


# ---- the menu save-slot line ---------------------------------------------------

func test_slot_line_prefers_the_creature_name() -> void:
	eq(String(MenuStage.slot_display_name({"creatureName": "Mosi", "playerName": "Fangpuff"})),
			"Mosi", "the chosen name wins")
	eq(String(MenuStage.slot_display_name({"playerName": "Fangpuff"})),
			"Fangpuff", "no creatureName → the auto-derived playerName")
	eq(String(MenuStage.slot_display_name({"creatureName": "", "playerName": "Fangpuff"})),
			"Fangpuff", "empty creatureName → the playerName")
	eq(String(MenuStage.slot_display_name({"playerName": "abcdefghijk"})), "abcdefghijk",
			"short names ride verbatim")
	eq(String(MenuStage.slot_display_name({"playerName": "abcdefghijklmnop"})),
			"abcdefghijklm…", "over-length truncates with the ellipsis (existing shape)")


# ---- display sites (draw is xvfb-only — the MN-1 source scan) ------------------

func test_display_sites_read_get_display_name() -> void:
	var ed_src := FileAccess.get_file_as_string("res://src/ui/editor.gd")
	eq(ed_src.count("get_display_name()"), 3,
			"editor: header + the name row + the picker draft read the display name")
	eq(ed_src.count("NamesScript.self_name"), 0,
			"no direct self_name call left in the editor (the fallback lives in context)")
	var hud_src := FileAccess.get_file_as_string("res://src/ui/hud.gd")
	ok(hud_src.contains("get_display_name()"), "hud: the arc draws the display name")
	var cell_src := FileAccess.get_file_as_string("res://src/game/cell/cell_sim.gd")
	ok(cell_src.contains("get_display_name()"), "cell sim: the death toast names the creature")
	var creature_src := FileAccess.get_file_as_string("res://src/game/creature/creature_sim.gd")
	ok(creature_src.contains("get_display_name()"), "creature sim: the death toast names the creature")
	var menu_src := FileAccess.get_file_as_string("res://src/game/menu.gd")
	ok(menu_src.contains("slot_display_name"), "menu: the slot line routes through the display-name pick")
	var ctx_src := FileAccess.get_file_as_string("res://src/game/context.gd")
	ok(ctx_src.contains("creatureName"), "context: the camelCase wire key")


# ---- i18n: the picker labels ship in both languages ----------------------------

func test_picker_labels_ship_vi_rows() -> void:
	_en()
	var i := I18n.new(SCRATCH)
	for k in ["Accept", "Cancel", "Backspace", "Max 14", "accept or edit", "edit ▸", "NAME"]:
		ok(i.vi_has(k), "vi.csv carries \"%s\"" % k)
