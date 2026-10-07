# Tests for the R3 progress arc on src/ui/hud.gd — the 5-stage journey widget
# (experience-redesign task 2, spec R3): pure state function for all 6 stage
# ids (menu = all dim), next-milestone hint keys, and the vi.csv rows both
# need. Pure-function file — no scene, no CanvasItem, headless-safe.
# Path-based extends + preload-by-path per the -s runner rules (class_name
# globals don't resolve on a fresh clone — test_i18n.gd header note).
extends "res://tests/test_base.gd"

const HudUi := preload("res://src/ui/hud.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const SCRATCH := "user://test_hud_arc_settings.cfg"

## The arc vocabulary (brief AC: bright | dim | done | current — "current"
## IS the bright node at render time; the state words are these three).
const STATES := ["current", "dim", "done"]
const ALL_STAGE_IDS := ["menu", "cell", "creature", "tribe", "civ", "space"]


func _wipe() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_hud_arc_settings.cfg")
		dir.remove("test_hud_arc_settings.cfg.tmp")


func _restore_locale() -> void:
	TranslationServer.set_locale("en")


# ---- arc_states: the brief's three pinned tests (verbatim bodies) -----------

func test_arc_states_cell() -> void:
	var st: Array = HudUi.arc_states("cell")
	eq(st.size(), 5, "5 nodes")
	eq(st[0], "current", "cell is current")
	for i in range(1, 5):
		eq(st[i], "dim", "later nodes dim")


func test_arc_states_space() -> void:
	var st: Array = HudUi.arc_states("space")
	for i in range(4):
		eq(st[i], "done", "earlier done")
	eq(st[4], "current", "space current")


func test_arc_next_hint_cell() -> void:
	ok(HudUi.arc_next_hint("cell").length() > 0, "hint text exists")


# ---- arc_states: full 6-id sweep (brief AC: unit-tested for all 6 ids) ------

func test_arc_states_menu_all_dim() -> void:
	var st: Array = HudUi.arc_states("menu")
	eq(st.size(), 5, "5 nodes on menu too")
	for i in range(5):
		eq(st[i], "dim", "menu dims every node")


func test_arc_states_mid_stages() -> void:
	var creature: Array = HudUi.arc_states("creature")
	eq(creature[0], "done", "cell done when creature current")
	eq(creature[1], "current", "creature is current")
	for i in range(2, 5):
		eq(creature[i], "dim", "later nodes dim")
	var civ: Array = HudUi.arc_states("civ")
	for i in range(3):
		eq(civ[i], "done", "earlier done")
	eq(civ[3], "current", "civ is current")
	eq(civ[4], "dim", "space still dim")


func test_arc_states_all_six_ids_shape() -> void:
	for id in ALL_STAGE_IDS:
		var st: Array = HudUi.arc_states(id)
		eq(st.size(), 5, "%s: 5 nodes" % id)
		var cur := 0
		for s in st:
			ok(STATES.has(s), "%s: state %s in vocabulary" % [id, str(s)])
			if s == "current":
				cur += 1
		if id == "menu":
			eq(cur, 0, "menu: no current node")
		else:
			eq(cur, 1, "%s: exactly one current node" % id)
			var idx: int = HudUi.STAGE_ORDER.find(id)
			ok(idx >= 0, "%s is in STAGE_ORDER" % id)
			eq(st[idx], "current", "%s: its own node is current" % id)


func test_arc_states_unknown_id_all_dim() -> void:
	var st: Array = HudUi.arc_states("bogus")
	eq(st.size(), 5, "5 nodes on unknown id")
	for i in range(5):
		eq(st[i], "dim", "unknown id dims every node (no crash)")


# ---- arc_next_hint: every stage carries a milestone line ---------------------

func test_arc_next_hints_all_stages() -> void:
	for id in HudUi.STAGE_ORDER:
		ok(HudUi.arc_next_hint(id).length() > 0, "%s hint text exists" % id)
	eq(HudUi.arc_next_hint("menu"), "", "menu has no next milestone (tooltip hidden)")


# ---- i18n: both languages (EN literal key + vi.csv row) ----------------------

func test_arc_hint_and_label_keys_translate_vi() -> void:
	_wipe()
	var i: Variant = I18nScript.new(SCRATCH)
	i.set_lang("vi")
	for id in HudUi.STAGE_ORDER:
		var hint := String(HudUi.HINT_KEYS[id])
		ok(i.vi_has(hint), "vi.csv row exists for the %s hint" % id)
		ok(i.tr_key(hint) != hint, "%s hint actually translates in VI" % id)
	for id in HudUi.STAGE_ORDER:
		var label := String(HudUi.ARC_LABELS[id])
		ok(i.vi_has(label), "vi.csv row exists for the %s arc label" % id)
	# EN degrades to the key itself (the key space IS English — i18n.gd)
	i.set_lang("en")
	eq(i.tr_key(String(HudUi.HINT_KEYS["cell"])), String(HudUi.HINT_KEYS["cell"]),
			"EN passthrough keeps the hint key")
	_wipe()
	_restore_locale()
