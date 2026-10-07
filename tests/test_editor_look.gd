# Tests for the R6 experience-redesign task: the editor's free LOOK tab + the
# world peek. The editor splits into BODY (parts + diet + size + graft — the
# DNA economy) and LOOK (hue/sat/pattern/coat + the inert name placeholder —
# no DNA display anywhere on the tab) tabs; the world backdrop eases
# 0.88 → 0.6 with a hold-to-peek 0.2 (on-screen hold-button bottom-right +
# keyboard Alt). The freeness lives in the parts.gd DATA (PATTERNS/COATS
# costs zeroed — single source of truth; the buy path reads the catalog), and
# EditorUi.look_price stays as the thin accessor the tests pin. Diet/parts
# prices and the refund logic stay untouched, so the only economy delta is
# the LOOK cosmetics — the cell sim dump is unchanged (A-B evidence
# sha-identical, re-verified by tools/ab_test.sh on this task).
extends "res://tests/test_base.gd"

const EditorUiScript := preload("res://src/ui/editor.gd")
const GameInputScript := preload("res://src/core/input.gd")
const ContextScript := preload("res://src/game/context.gd")
const PartsScript := preload("res://src/evo/parts.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const DT := 1.0 / 60.0
const SCRATCH := "user://test_editor_look_settings.cfg"
const RECT := {"x": 0.0, "y": 0.0, "w": 300.0, "h": 44.0}


func _en() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_editor_look_settings.cfg")
		dir.remove("test_editor_look_settings.cfg.tmp")
	TranslationServer.set_locale("en")


## Duck-typed game (the editor reads context/input/i18n/vw/vh/hud and calls
## save_all()/set_cursor(); on_stats_changed is the stage hook) — the
## test_editor.gd MockGame shape.
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


func _ids(rows: Array) -> Array:
	var ids := []
	for r in rows:
		ids.append(String(r["kind"]) if String(r["kind"]) != "part" else String(r["def"]["id"]))
	return ids


# ---- the two pure helpers (plan Step 2) --------------------------------------

func test_look_price_is_zero_for_the_whole_look_catalog() -> void:
	for p in PartsScript.PATTERNS:
		eq(EditorUiScript.look_price(String(p["id"])), 0, "pattern %s is free" % String(p["id"]))
	for c in PartsScript.COATS:
		eq(EditorUiScript.look_price(String(c["id"])), 0, "coat %s is free" % String(c["id"]))


func test_look_price_falls_back_outside_the_look_catalog() -> void:
	# the freeness is scoped to cosmetics: a part or diet id routed through
	# look_price keeps its standard catalog cost, so a future misuse can never
	# silently free a DNA sink
	eq(EditorUiScript.look_price("jaw"), PartsScript.part_cost(PartsScript.part_by_id("jaw"), 0),
			"part id keeps its catalog price")
	eq(EditorUiScript.look_price("carnivore"), 60, "diet id keeps its catalog price")


func test_world_dim_rest_and_peek() -> void:
	approx(EditorUiScript.world_dim(false), 0.6, "editor-open backdrop rests at 0.6 (was 0.88)", 1e-9)
	approx(EditorUiScript.world_dim(true), 0.2, "hold-to-peek drops the backdrop to 0.2", 1e-9)


# ---- tab state: default BODY, session-local, never persisted -----------------

func test_tab_defaults_to_body_on_open_and_never_persists() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	eq(String(ed.tab), "body", "BODY is the default tab on open")
	ed.switch_tab("look")
	eq(String(ed.tab), "look", "the switch holds for the open session")
	eq(float(ed.scroll), 0.0, "a tab switch resets the scroll (new content height)")
	ed.close()
	ed.show("cell")
	eq(String(ed.tab), "body", "reopening resets to BODY — the switch is not persisted")
	# the editor dict carries open+mode only (the sync contract) — no tab key
	ok(not _g.editor.has("tab"), "the tab never rides the editor dict (not saved)")


# ---- the row split ------------------------------------------------------------

func test_cell_body_rows_after_r6_split() -> void:
	var ed: Variant = _editor()
	ed.show("cell")
	var ids := _ids(ed.rows)
	# 9 cell/both parts + diet + size = 11 — the cosmetics moved to LOOK
	eq(ids, ["flagella", "cilia", "spikes", "jaw", "toxin", "proboscis", "electro",
			"jet", "legs", "diet", "size"], "cell BODY: parts + diet + size")
	ok(not ids.has("pattern") and not ids.has("hue") and not ids.has("sat")
			and not ids.has("coat") and not ids.has("name"), "no LOOK rows on BODY")


func test_creature_body_rows_after_r6_split() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	var ids := _ids(ed.rows)
	# 10 creature/both parts + diet + size = 12 — coat moved to LOOK
	eq(ids, ["spikes", "jaw", "toxin", "legs", "arms", "eyes", "horns", "tail",
			"wings", "brain", "diet", "size"], "creature BODY: parts + diet + size")
	ok(not ids.has("coat") and not ids.has("pattern") and not ids.has("hue")
			and not ids.has("sat") and not ids.has("name"), "no LOOK rows on BODY")


func test_look_rows_order_and_mode_scope() -> void:
	var ed: Variant = _editor()
	ed.show("creature")
	ed.switch_tab("look")
	# ruling order: hue/sat/pattern/coat + the inert name row last
	eq(_ids(ed.rows), ["hue", "sat", "pattern", "coat", "name"],
			"creature LOOK: hue/sat/pattern/coat + name placeholder")
	ed.show("cell")
	ed.switch_tab("look")
	eq(_ids(ed.rows), ["hue", "sat", "pattern", "name"],
			"cell LOOK: no coat row (coats are creature-only)")


# ---- LOOK purchases are free --------------------------------------------------

func test_look_purchases_cost_nothing_and_reswitch_free() -> void:
	var ed: Variant = _editor(500)
	ed.show("creature")
	ed.switch_tab("look")
	var rect := RECT
	# full coat cycle — every switch free, back to the starter
	for want in ["fur", "scales", "plates", "skin"]:
		ed.click_row({"kind": "coat"}, 10.0, rect)
		eq(String(_g.context.genome["coat"]), want, "coat → %s" % want)
	eq(int(_g.context.dna), 500, "the full coat cycle charged 0 DNA")
	# full pattern cycle — every switch free, back to the starter
	for want in ["spots", "stripes", "glow", "plain"]:
		ed.click_row({"kind": "pattern"}, 10.0, rect)
		eq(String(_g.context.genome["pattern"]), want, "pattern → %s" % want)
	eq(int(_g.context.dna), 500, "the full pattern cycle charged 0 DNA")
	eq(_stats_hooks, 8, "every look change still fires the stats hook")
	eq(_g.toasts.size(), 0, "no gate toast — cosmetics never charge")


func test_look_purchase_needs_no_dna_at_all() -> void:
	var ed: Variant = _editor(0)
	ed.show("creature")
	ed.switch_tab("look")
	ed.click_row({"kind": "pattern"}, 10.0, RECT)
	eq(String(_g.context.genome["pattern"]), "spots", "0 DNA still switches the pattern")
	eq(int(_g.context.dna), 0, "dna untouched")
	eq(_g.toasts.size(), 0, "no Not-enough-DNA toast on LOOK")


func test_hue_sat_sliders_still_work_on_look() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	ed.switch_tab("look")
	ed.click_row({"kind": "hue"}, 64.0, RECT)
	approx(float(_g.context.genome["hue"]), 50.0 / 272.0 * 360.0, "hue maps the click x", 1e-6)
	ed.click_row({"kind": "sat"}, 150.0, RECT)
	approx(float(_g.context.genome["sat"]), 0.05 + (136.0 / 272.0) * 0.95,
			"sat maps the click x into 0.05..1", 1e-6)
	eq(int(_g.context.dna), 500, "sliders stay free")


# ---- the inert name placeholder ------------------------------------------------

func test_name_row_is_inert() -> void:
	var ed: Variant = _editor(500)
	ed.show("creature")
	ed.switch_tab("look")
	var hooks_before: int = _stats_hooks
	ed.click_row({"kind": "name"}, 10.0, RECT)
	eq(String(_g.context.genome["diet"]), "omnivore", "genome untouched")
	eq(int(_g.context.dna), 500, "dna untouched")
	eq(_stats_hooks, hooks_before, "no stats refresh for an inert row")
	eq(bool(ed.dirty_since_save), false, "an inert row never dirties the save")
	eq(_g.toasts.size(), 0, "no toast")


# ---- DNA display gate ----------------------------------------------------------

func test_dna_display_hidden_on_look() -> void:
	var ed: Variant = _editor(500)
	ed.show("creature")
	eq(bool(ed.dna_visible()), true, "BODY shows the DNA footer")
	ed.switch_tab("look")
	eq(bool(ed.dna_visible()), false, "LOOK hides ALL DNA display (footer counter included)")
	ed.switch_tab("body")
	eq(bool(ed.dna_visible()), true, "back to BODY restores the footer")


# ---- BODY economy untouched ----------------------------------------------------

func test_body_prices_untouched() -> void:
	var ed: Variant = _editor(500)
	ed.show("cell")
	# diet: 40/60 through the BODY tab (TS diet prices)
	ed.click_row({"kind": "diet"}, 10.0, RECT)
	eq(String(_g.context.genome["diet"]), "carnivore", "omnivore → carnivore")
	eq(int(_g.context.dna), 500 - 60, "carnivore still costs 60")
	# part buy: standard part_cost
	var before := int(_g.context.genome["flagella"])
	var cost: int = PartsScript.part_cost(PartsScript.part_by_id("flagella"), before)
	ed.click_part({"kind": "part", "def": PartsScript.part_by_id("flagella")}, "+")
	eq(int(_g.context.genome["flagella"]), before + 1, "part buy on BODY")
	eq(int(_g.context.dna), 440 - cost, "part buy still charges part_cost")
	# the freeness lives in the parts.gd DATA (the re-ruled single source of
	# truth): the LOOK cosmetics' catalog costs are zeroed there, while every
	# diet/parts price and the refund logic stay untouched
	eq(int(PartsScript.PATTERNS[1]["cost"]), 0, "spots catalog cost zeroed in the data (R6)")
	eq(int(PartsScript.PATTERNS[3]["cost"]), 0, "glow catalog cost zeroed in the data (R6)")
	eq(int(PartsScript.COATS[1]["cost"]), 0, "fur catalog cost zeroed in the data (R6)")
	eq(int(PartsScript.COATS[3]["cost"]), 0, "plates catalog cost zeroed in the data (R6)")


# ---- graft rows stay on the DNA tab ---------------------------------------------

func test_graft_rows_stay_on_body_tab() -> void:
	var ed: Variant = _editor(500)
	var c: Variant = _g.context
	c.world["comboFired"]["borrowed_flesh"] = true
	c.bestiary["extinct1"] = {
		"key": "extinct1", "name": "Old Ripper", "stage": "cell",
		"genome": {"jaw": 4, "spikes": 3}, "extinct": true, "seen": 1, "killsByPlayer": 0,
	}
	ed.show("cell")
	eq(String(ed.rows[0]["kind"]), "graft", "graft row first on BODY")
	ed.switch_tab("look")
	var ids := _ids(ed.rows)
	ok(not ids.has("graft"), "no graft rows on LOOK (it is a DNA purchase)")


# ---- the peek input contract ----------------------------------------------------

func test_peek_alt_code_registered() -> void:
	# the keyboard peek polls the held Alt key through the GameInput map —
	# 4.2 has a single KEY_ALT (the KeyShift precedent: one pragmatic
	# modifier entry, no L/R split in this engine's Key enum)
	eq(int(GameInputScript.CODES.get("Alt", 0)), KEY_ALT, "Alt mapped")


func test_peek_and_tab_wiring_source_scan() -> void:
	# the draw/input wiring is unreachable headless (draw-integration stays
	# with the xvfb scene layer) — pin it at the source, the MN-1 pattern
	var src := FileAccess.get_file_as_string("res://src/ui/editor.gd")
	eq(src.count("world_dim(peeking)"), 1, "the backdrop alpha routes through world_dim")
	eq(src.count("0.88"), 0, "no 0.88 dim literal left")
	eq(src.count("key(\"Alt\")"), 1, "the keyboard peek polls the held Alt key")
	eq(src.count("if dna_visible()"), 1, "the footer DNA draw site gates on dna_visible()")
