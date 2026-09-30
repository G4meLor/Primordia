## Pause overlay: resume, save, sound, help, world-genome codex, quit to title.
## Port of Spore src/ui/pause.ts (frozen). Task 8 ruling: RefCounted; button
## ACTIONS route through the `actions` hook dict (close_pause / save_all /
## toggle_mute / go_to / toast) — the owning stage wires the real game methods
## and Task 9 re-wires them game-side; the defaults are stub-safe no-ops, so a
## pause built before wiring only no-ops. Display reads (game.muted, i18n
## lang) are direct, as in TS. The tr_key literals stay INLINE (not aliased)
## so the T2 audit's membership scanner sees every display key.
class_name PauseMenuUi
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const TraitsScript := preload("res://src/evo/world_traits.gd")

## TS pause.ts:99-109 help lines — [key, value] pairs, both through t().
const HELP_LINES := [
	["MOVE", "Mouse: swim/walk toward cursor · WASD also works"],
	["BITE", "Hold Left Mouse near prey — or just bump into it"],
	["DASH", "Space — quick burst (needs Jet Bladder in cell stage)"],
	["TOXIN", "1 — poison burst (needs Toxin Sac)"],
	["ZAP", "2 — electro-stun nearby cells (needs Electro-organ)"],
	["EVOLVE", "E — open the editor and spend DNA on new parts"],
	["PAUSE", "Esc — this menu · M — mute"],
	["CHAOS", "The meter top-right grows when you play wild."],
	["", "Wild worlds give more DNA — and worse problems."],
]

var items: Array = []            # {label, action, w, h, x, y}
var show_help := false
var show_world := false

## Stub-safe defaults — the owner replaces this dict at install time.
var actions: Dictionary = {
	"close_pause": func() -> void: pass,
	"save_all": func() -> bool: return false,
	"toggle_mute": func() -> void: pass,
	"go_to": func(_id: String, _card: Variant) -> void: pass,
	"toast": func(_text: String, _kind: String, _icon: String) -> void: pass,
}

var _game: Variant = null


func _init(game_v: Variant) -> void:
	_game = game_v


func open() -> void:
	show_help = false
	show_world = false
	rebuild()


func rebuild() -> void:
	var vw := float(_game.vw)
	var vh := float(_game.vh)
	var cx := vw / 2.0
	items.clear()
	if show_world:
		# codex Back hit-testing shares the worldLayout math with the draw
		var wl: Dictionary = world_layout(vh, world_codex()["rows"].size())
		items.append(_mk(_game.i18n.tr_key("◀  Back"), _act_back_world, float(wl["backY"]), cx))
	elif show_help:
		var hl: Dictionary = help_layout(vh)
		items.append(_mk(_game.i18n.tr_key("◀  Back"), _act_back_help, float(hl["backY"]), cx))
	else:
		var ml: Dictionary = main_layout(vh)
		var y := float(ml["y0"])
		var stride := float(ml["stride"])
		items.append(_mk(_game.i18n.tr_key("▶  Resume"), _act_resume, y, cx))
		y += stride
		items.append(_mk(_game.i18n.tr_key("💾  Save now"), _save_now, y, cx))
		y += stride
		items.append(_mk(_game.i18n.tr_key("🔇  Sound: off") if bool(_game.muted)
				else _game.i18n.tr_key("🔊  Sound: on"), _act_sound, y, cx))
		y += stride
		items.append(_mk("🌐  %s: %s" % [_game.i18n.tr_key("LANGUAGE"),
				"Tiếng Việt" if String(_game.i18n.get_lang()) == "vi" else "English"],
				_act_language, y, cx))
		y += stride
		items.append(_mk(_game.i18n.tr_key("❓  How to play"), _act_help, y, cx))
		y += stride
		items.append(_mk(_game.i18n.tr_key("🌍  World Genome"), _act_world, y, cx))
		y += stride
		items.append(_mk(_game.i18n.tr_key("⌂  Quit to title"), _act_quit, y, cx))


func update(dt: float) -> void:
	var input: Variant = _game.input
	if not input.was_clicked():
		return
	var mx := float(input.mx)
	var my := float(input.my)
	for it in items:
		if mx >= float(it["x"]) and mx <= float(it["x"]) + float(it["w"]) \
				and my >= float(it["y"]) and my <= float(it["y"]) + float(it["h"]):
			input.take_click()
			# TS audio.play('click') — audio core is its own task
			var action: Callable = it["action"]
			action.call()
			return


## TS render() — the overlay chrome + one of the three views.
func draw(ci: CanvasItem, vw: float, vh: float) -> void:
	ci.draw_rect(Rect2(0.0, 0.0, vw, vh), RendererScript.css_color("rgba(2,4,12,0.72)"))
	RendererScript.outlined_text(ci, _game.i18n.tr_key("PAUSED"), vw / 2.0, vh / 2.0 - 180.0,
			{"size": 34.0, "fill": Color("#bfe6ff"), "weight": "700"})
	if show_world:
		_draw_world(ci, vw, vh)
	elif not show_help:
		for it in items:
			var hover := _hover(it)
			if hover:
				_game.hover_cursor()
			RendererScript.panel(ci, float(it["x"]), float(it["y"]), float(it["w"]), float(it["h"]), {
				"fill": RendererScript.css_color("rgba(40,70,140,0.9)") if hover
						else RendererScript.css_color("rgba(10,18,40,0.9)"),
				"stroke": RendererScript.css_color("rgba(140,200,255,0.8)") if hover
						else RendererScript.css_color("rgba(120,160,220,0.25)"),
				"lw": 1.5,
			})
			RendererScript.outlined_text(ci, String(it["label"]),
					float(it["x"]) + float(it["w"]) / 2.0, float(it["y"]) + float(it["h"]) / 2.0,
					{"size": 16.0, "fill": Color("#ffffff") if hover else Color("#cfe2ff"),
							"maxWidth": float(it["w"]) - 24.0})
	else:
		_draw_help(ci, vw, vh)


# ---- actions (route through the hooks; TS bodies verbatim) --------------------

func _act_resume() -> void:
	actions["close_pause"].call()


func _save_now() -> void:
	if bool(actions["save_all"].call()):
		actions["toast"].call(_game.i18n.tr_key("Game saved"), "good", "💾")
	else:
		actions["toast"].call(_game.i18n.tr_key("Save failed — browser storage full"), "bad", "💾")


func _act_sound() -> void:
	actions["toggle_mute"].call()
	rebuild()


func _act_language() -> void:
	var lang := String(_game.i18n.get_lang())
	_game.i18n.set_lang("en" if lang == "vi" else "vi")
	rebuild()


func _act_help() -> void:
	show_help = true
	rebuild()


func _act_world() -> void:
	show_world = true
	rebuild()


func _act_back_help() -> void:
	show_help = false
	rebuild()


func _act_back_world() -> void:
	show_world = false
	rebuild()


func _act_quit() -> void:
	actions["save_all"].call()
	actions["close_pause"].call()
	actions["go_to"].call("menu", {"title": "PRIMORDIA", "sub": "the soup remembers you"})


func _mk(label: String, action: Callable, y: float, cx: float) -> Dictionary:
	return {"label": label, "action": action, "w": 240.0, "h": 46.0, "x": cx - 120.0, "y": y}


func _hover(it: Dictionary) -> bool:
	var input: Variant = _game.input
	var mx := float(input.mx)
	var my := float(input.my)
	return mx >= float(it["x"]) and mx <= float(it["x"]) + float(it["w"]) \
			and my >= float(it["y"]) and my <= float(it["y"]) + float(it["h"])


# ---- layouts (TS rulings T8-I2 verbatim) --------------------------------------

## Main pause list: 7 items at stride 56 from vh/2−120; tight viewports
## compress the stride (floor 40) so Resume..Quit clear the bottom edge.
func main_layout(vh: float) -> Dictionary:
	var y0 := vh / 2.0 - 120.0
	if y0 + 6.0 * 56.0 + 46.0 <= vh - 8.0:
		return {"y0": y0, "stride": 56.0}
	return {"y0": y0, "stride": maxf(40.0, floorf((vh - 8.0 - y0 - 46.0) / 6.0))}


## Help view: 9 lines at stride ≤34 in a panel from vh/2−176; tight viewports
## compress the line stride and pull the Back band in.
func help_layout(vh: float) -> Dictionary:
	var y0 := vh / 2.0 - 176.0
	var stride := minf(34.0, maxf(26.0, floorf((vh - y0 - 116.0) / 9.0)))
	var panel_h := 26.0 + 9.0 * stride + 18.0
	var gap := minf(116.0, maxf(18.0, vh - 8.0 - 46.0 - (y0 + panel_h)))
	return {"y0": y0, "stride": stride, "panelH": panel_h, "backY": y0 + panel_h + gap}


## Codex layout shared by rebuild() (Back hit-testing) and the draw: the Back
## band sits one gap below the last row, so any row count clears it.
func world_layout(vh: float, row_count: int) -> Dictionary:
	var y0 := vh / 2.0 - 190.0
	var rows := maxi(row_count, 1)
	var budget := vh - 54.0 - 34.0 - (y0 + 110.0)
	var stride := minf(24.0, maxf(14.0, floorf(budget / float(rows))))
	var back_y := minf(y0 + 110.0 + float(rows - 1) * stride + 34.0, vh - 54.0)
	var panel_h := minf(back_y + 60.0, vh - 8.0) - y0
	return {"y0": y0, "backY": back_y, "panelH": panel_h, "stride": stride}


# ---- views --------------------------------------------------------------------

func _draw_help(ci: CanvasItem, vw: float, vh: float) -> void:
	var hl: Dictionary = help_layout(vh)
	var y := float(hl["y0"]) + 26.0
	RendererScript.panel(ci, vw / 2.0 - 270.0, float(hl["y0"]), 540.0, float(hl["panelH"]), {
		"fill": RendererScript.css_color("rgba(8,14,32,0.92)"),
		"stroke": RendererScript.css_color("rgba(120,180,255,0.3)"),
	})
	for line in HELP_LINES:
		var k := String(line[0])
		var v := String(line[1])
		if k != "":
			RendererScript.outlined_text(ci, _game.i18n.tr_key(k), vw / 2.0 - 250.0, y,
					{"size": 13.0, "fill": Color("#8fd0ff"), "align": "left", "maxWidth": 84.0})
			RendererScript.outlined_text(ci, _game.i18n.tr_key(v), vw / 2.0 - 160.0, y,
					{"size": 13.0, "fill": Color("#dfeaff"), "align": "left", "maxWidth": 424.0})
		else:
			RendererScript.outlined_text(ci, _game.i18n.tr_key(v), vw / 2.0, y,
					{"size": 12.0, "fill": Color("#ffd7a8")})
		y += float(hl["stride"])
	# visible Back for the help view — rebuild() keeps the item and update()
	# hit-tests it, but nothing used to render it (TS comment)
	_draw_back_band(ci)


## 'World Genome' view: world title + sigils already revealed, then the codex —
## revealed entries named, the rest '❓ ???' with no totals, so the world keeps
## its secrets.
func _draw_world(ci: CanvasItem, vw: float, vh: float) -> void:
	var w: Dictionary = _game.context.world
	var pw := minf(480.0, vw - 24.0)
	var px := vw / 2.0 - pw / 2.0
	var codex: Dictionary = world_codex()
	var wl: Dictionary = world_layout(vh, (codex["rows"] as Array).size())
	RendererScript.panel(ci, px, float(wl["y0"]), pw, float(wl["panelH"]), {
		"fill": RendererScript.css_color("rgba(8,14,32,0.92)"),
		"stroke": RendererScript.css_color("rgba(120,180,255,0.3)"),
	})
	RendererScript.outlined_text(ci, "🌍 %s" % _game.i18n.tr_key("World Genome"),
			vw / 2.0, float(wl["y0"]) + 26.0, {"size": 18.0, "fill": Color("#9fe8d8")})
	# world title line: compositional VI (noun first) or the EN composite
	var parts: Dictionary = WorldGenomeScript.world_title_parts(int(w["seed"]))
	var title := WorldGenomeScript.world_title(int(w["seed"]))
	if String(_game.i18n.get_lang()) == "vi":
		title = _cap_first("%s %s" % [_game.i18n.tr_key(String(parts["noun"])),
				_game.i18n.tr_key(String(parts["adj"]))])
	var sigils := String(codex["sigils"])
	var title_line := "%s  %s" % [title, sigils] if sigils != "" else title
	RendererScript.outlined_text(ci, title_line, vw / 2.0, float(wl["y0"]) + 54.0,
			{"size": 14.0, "fill": Color("#ffe9b0"), "maxWidth": pw - 24.0})
	RendererScript.outlined_text(ci, _game.i18n.tr_key("Codex"), px + 20.0, float(wl["y0"]) + 84.0,
			{"size": 11.0, "fill": RendererScript.css_color("rgba(160,200,255,0.6)"), "align": "left"})
	var ry := float(wl["y0"]) + 110.0
	for row in codex["rows"]:
		RendererScript.outlined_text(ci, String(row), px + 24.0, ry,
				{"size": 14.0, "fill": Color("#dfeaff"), "align": "left", "maxWidth": pw - 48.0})
		ry += float(wl["stride"])
	# visible Back for the world view — same pattern as the help view
	_draw_back_band(ci)


## The help/world Back band (the last rebuilt item), drawn like a main button.
func _draw_back_band(ci: CanvasItem) -> void:
	if items.is_empty():
		return
	var back: Dictionary = items[items.size() - 1]
	var hover := _hover(back)
	if hover:
		_game.hover_cursor()
	RendererScript.panel(ci, float(back["x"]), float(back["y"]), float(back["w"]), float(back["h"]), {
		"fill": RendererScript.css_color("rgba(40,70,140,0.9)") if hover
				else RendererScript.css_color("rgba(10,18,40,0.9)"),
		"stroke": RendererScript.css_color("rgba(140,200,255,0.8)") if hover
				else RendererScript.css_color("rgba(120,160,220,0.25)"),
		"lw": 1.5,
	})
	RendererScript.outlined_text(ci, String(back["label"]),
			float(back["x"]) + float(back["w"]) / 2.0, float(back["y"]) + float(back["h"]) / 2.0,
			{"size": 16.0, "fill": Color("#ffffff") if hover else Color("#cfe2ff")})


## Codex data for this world: the genome's traits (revealed ones named, the
## rest '❓ ???'), traits a world-turn swapped out but that stay on the record,
## then fired combos and turns.
func world_codex() -> Dictionary:
	var c: Variant = _game.context
	var w: Dictionary = c.world
	var sigils := PackedStringArray()
	var rows: Array = []
	var in_genome := {}
	for d in w.get("traits", []):
		in_genome[d["id"]] = true
	for d in w.get("traits", []):
		if bool(w.get("revealed", {}).get(d["id"], false)):
			rows.append("%s %s" % [String(d["sigil"]), _game.i18n.tr_key(String(d["name"]))])
			sigils.append(String(d["sigil"]))
		else:
			rows.append("❓ ???")
	var marked: Array = []
	var codex_flag: Variant = c.flags.get("codex_world", null)
	if codex_flag is String:
		marked = String(codex_flag).split(",")
	for id in marked:
		var d2: Variant = _trait_def(String(id))
		if d2 != null and not in_genome.has(d2["id"]):
			rows.append("%s %s" % [String(d2["sigil"]), _game.i18n.tr_key(String(d2["name"]))])
			sigils.append(String(d2["sigil"]))
	for d3 in TraitsScript.COMBO_DEFS:
		if bool(w.get("comboFired", {}).get(d3["id"], false)):
			rows.append("%s %s" % [String(d3["sigil"]), _game.i18n.tr_key(String(d3["title"]))])
	for d4 in TraitsScript.WORLD_TURN_DEFS:
		if bool(w.get("firedTurns", {}).get(d4["id"], false)):
			rows.append("%s %s" % [String(d4["sigil"]), _game.i18n.tr_key(String(d4["title"]))])
	return {"sigils": " ".join(sigils), "rows": rows}


func _trait_def(id: String) -> Variant:
	for d in TraitsScript.TRAIT_DEFS:
		if d["id"] == id:
			return d
	return null


func _cap_first(s: String) -> String:
	if s.is_empty():
		return s
	return s[0].to_upper() + s.substr(1)
