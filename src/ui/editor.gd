## The Evolution Editor — Spore's signature feature. Live genome editing with
## DNA accounting, animated preview and instant visual feedback. Port of Spore
## src/ui/editor.ts (frozen). Works in cell mode (water parts) and creature
## mode (body plan — the creature preview paints through the task-6 creature
## painter, TS editor.ts:322-326 pose numbers; the row/stat flows are shared).
##
## Task 8 ruling: RefCounted (the TS class shape — no Control node); drawn by
## the owning scene as the layer above the hud (TS game.ts:549). Buy/sell runs
## through context.spend_dna/part_cost/part_refund (M1 parts); a successful
## change refreshes context stats AND fires the `on_stats_changed` hook — the
## native shape of TS notifyStatsChanged→stage.onStatsChanged, set by the cell
## stage to sim.on_stats_changed (buy→feel-stronger loop). The click path
## hit-tests row_rects recorded by draw() (TS records them in renderRow);
## click_part(row, btn) is the programmatic path (TS-test parity,
## bot.test.ts:132). All display literals ride tr_key INLINE (T2 audit).
class_name EditorUi
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")
const PMathScript := preload("res://src/core/math.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const PartsScript := preload("res://src/evo/parts.gd")
const StatsScript := preload("res://src/evo/stats.gd")
const NamesScript := preload("res://src/evo/names.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const CellPainterScript := preload("res://src/gfx/cell_painter.gd")
const CreaturePainter := preload("res://src/gfx/creature_painter.gd")

var open := false
var mode := "cell"            # 'cell' | 'creature' (TS Editor.mode)
var rows: Array = []          # TS private rows — public for the headless tests
var scroll := 0.0
var preview_t := 0.0
var gait := 0.0
var open_t := 0.0
var dirty_since_save := false
## TS private sliderDrag: 'hue' | 'sat' | null — "" natively.
var slider_drag := ""
var slider_rects := {"hue": null, "sat": null}
## TS private listRect/closeRect — draw-computed (update reads the last pass).
var list_rect := {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0}
var close_rect := {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0}
## {row, r, btn} records — rebuilt every draw pass (draw-populated, TS order).
var row_rects: Array = []
## TS notifyStatsChanged hook — the owning stage binds sim.on_stats_changed.
var on_stats_changed: Callable = func() -> void: pass

var _game: Variant = null
## The creature preview's caller-owned sub-RIDs (task 6 painter contract) —
## freed at the top of every redraw, on close() and via free_preview_rids()
## on stage teardown.
var _preview_rids: Array = []


func _init(game_v: Variant) -> void:
	_game = game_v


func show(mode_v: String) -> void:
	mode = mode_v
	open = true
	_sync_open()
	scroll = 0.0
	rows = build_rows()
	# TS audio.play('warp', 0.5) — audio core is its own task


func close() -> void:
	open = false
	_sync_open()
	free_preview_rids()
	# dirty-flag: E-spam used to write localStorage ~30×/s (~2700 saves in a
	# 90s session) — only persist when the genome actually changed
	if dirty_since_save:
		dirty_since_save = false
		# saveAll, not save — the genome write must carry the stage blob too
		if not _game.save_all():
			_game.hud["toast"].call(_game.i18n.tr_key("Save failed — browser storage full"), "bad", "💾")
	# TS audio.play('click') — audio core is its own task


## The game dict mirrors the live flag + mode: game.gd's blocked check and the
## stage's KeyE gate read `editor["open"]` (the stub-dict contract), a dict
## value would otherwise be a stale snapshot of the instance field, and the
## stage-switch adoption (creature_stage._install_overlays) carries `mode`.
func _sync_open() -> void:
	if _game != null and "editor" in _game and _game.editor is Dictionary:
		_game.editor["open"] = open
		_game.editor["mode"] = mode


func toggle(mode_v: String) -> void:
	if open:
		close()
	else:
		show(mode_v)


func build_rows() -> Array:
	var out: Array = []
	for def in PartsScript.PARTS:
		if String(def["stage"]) == mode or String(def["stage"]) == "both":
			out.append({"kind": "part", "def": def})
	if mode == "creature":
		out.append({"kind": "coat"})
	out.append({"kind": "diet"})
	out.append({"kind": "pattern"})
	out.append({"kind": "size"})
	out.append({"kind": "hue"})
	out.append({"kind": "sat"})
	# borrowed_flesh: the ONE graft slot — offer an extinct species' standout
	# part (standard DNA price, no discount). One graft per run.
	var c: Variant = _game.context
	if WorldGenomeScript.combo_active(c.world, "borrowed_flesh") \
			and c.flags.get("borrowed_flesh_graft", null) != true:
		var offered := 0
		for entry in c.bestiary.values():
			if not bool(entry["extinct"]) or offered >= 3:
				continue
			var part: Variant = PartsScript.standout_part(entry["genome"])
			if part == null or (String(part["def"]["stage"]) != mode and String(part["def"]["stage"]) != "both"):
				continue
			out.push_front({"kind": "graft", "def": part["def"],
					"level": mini(int(part["level"]), int(part["def"]["max"])),
					"species": String(entry["name"])})
			offered += 1
	return out


func _g() -> Dictionary:
	return _game.context.genome


func update(dt: float) -> void:
	preview_t += dt
	gait += dt * 6.0
	open_t += dt
	var input: Variant = _game.input

	if input.key_pressed("KeyE") or input.key_pressed("Tab"):
		close()
		return

	# wheel scroll (magnitude — T2 report correction: `scroll + w * 0.6`)
	var w := float(input.wheel())
	if w != 0.0:
		scroll = PMathScript.clamp(scroll + w * 0.6, 0.0,
				maxf(0.0, float(rows.size()) * 44.0 - float(list_rect["h"])))

	if slider_drag != "":
		var r: Variant = slider_rects[slider_drag]
		if bool(input.is_down()) and r != null:
			var tt := PMathScript.clamp((float(input.mx) - float(r["x"])) / float(r["w"]), 0.0, 1.0)
			if slider_drag == "hue":
				_g()["hue"] = tt * 360.0
			else:
				_g()["sat"] = 0.05 + tt * 0.95
		else:
			slider_drag = ""
		return

	if not input.was_clicked():
		return
	var mx := float(input.mx)
	var my := float(input.my)

	# close button
	if _hit(mx, my, close_rect):
		input.take_click()
		close()
		return
	# list interactions
	for rr in row_rects:
		if not _hit(mx, my, rr["r"]):
			continue
		input.take_click()
		if rr["btn"] != null:
			click_part(rr["row"], String(rr["btn"]))
			return
		click_row(rr["row"], mx, rr["r"])
		return


func click_part(row: Dictionary, btn: String) -> void:
	var def: Dictionary = row["def"]
	var g := _g()
	var level := int(g.get(def["gene"], 0))
	var bound: Variant = GenomeScript.GENE_BOUNDS.get(def["gene"], null)
	var min_level := int(bound["min"]) if bound != null else 0
	if btn == "+":
		if level >= int(def["max"]):
			return
		var cost: int = PartsScript.part_cost(def, level)
		if not _game.context.spend_dna(cost):
			_game.hud["toast"].call(_game.i18n.tr_key("Not enough DNA"), "bad", "🧬")
			# TS audio.play('hurt', 0.4)
			return
		g[def["gene"]] = level + 1
		# TS audio levelup/dna cue
	else:
		if level <= min_level:
			return
		# cell-stage exit guard: CRAWL ASHORE needs ≥1 leg — selling the last
		# pair used to lock the stage's sole exit with no warning
		if mode == "cell" and String(def["gene"]) == "legs" and level - 1 < 1:
			_game.hud["toast"].call(_game.i18n.tr_key("Your only way ashore! Keep at least one LEG."), "bad", "🐢")
			# TS audio.play('hurt', 0.4)
			return
		var refund: int = PartsScript.part_refund(def, level - 1)
		_game.context.add_dna(float(refund))
		g[def["gene"]] = level - 1
		# TS audio.play('click')
	_game.context.refresh_stats(mode == "creature")
	dirty_since_save = true
	on_stats_changed.call()


## Standard part price from the current level up to the graft target.
func graft_cost(def: Dictionary, target: int) -> int:
	var cur := int(_g().get(def["gene"], 0))
	var cost := 0
	for l in range(cur, target):
		cost += PartsScript.part_cost(def, l)
	return cost


## borrowed_flesh graft: raise one gene to the extinct species' level at the
## standard part price (no discount), once per run.
func click_graft(row: Dictionary) -> void:
	var c: Variant = _game.context
	if c.flags.get("borrowed_flesh_graft", null) == true:
		return
	var g := _g()
	var cur := int(g.get(row["def"]["gene"], 0))
	if cur >= int(row["level"]):
		return
	var cost := graft_cost(row["def"], int(row["level"]))
	if not c.spend_dna(cost):
		_game.hud["toast"].call(_game.i18n.tr_key("Not enough DNA"), "bad", "🧬")
		return
	g[row["def"]["gene"]] = int(row["level"])
	c.flags["borrowed_flesh_graft"] = true
	# TS audio.play('levelup', 0.9)
	# composed first (TS template literal) — the audit flags a literal-led
	# first arg on the hud call shape
	var graft_text := "%s %s ← %s" % [_game.i18n.tr_key("Borrowed flesh:"),
			_game.i18n.tr_key(String(row["def"]["name"])), String(row["species"])]
	_game.hud["toast"].call(graft_text, "good", "🫱")
	c.refresh_stats(mode == "creature")
	dirty_since_save = true
	on_stats_changed.call()
	rows = build_rows()  # the slot is spent — drop the graft rows


func click_row(row: Dictionary, mx: float, r: Dictionary) -> void:
	var g := _g()
	var c: Variant = _game.context
	if String(row["kind"]) == "graft":
		click_graft(row)
		return
	match String(row["kind"]):
		"diet":
			var idx := _diet_index(String(g["diet"]))
			var next: Dictionary = PartsScript.DIETS[(idx + 1) % PartsScript.DIETS.size()]
			var cost := int(next["cost"])
			if cost > 0 and int(c.dna) < cost:
				_game.hud["toast"].call(_game.i18n.tr_key("Not enough DNA"), "bad", "🧬")
				return
			if cost > 0:
				c.spend_dna(cost)
			g["diet"] = String(next["id"])
			# TS audio.play('dna', 0.7)
		"pattern":
			var pidx := _pattern_index(String(g["pattern"]))
			var pnext: Dictionary = PartsScript.PATTERNS[(pidx + 1) % PartsScript.PATTERNS.size()]
			var pcost := int(pnext["cost"])
			if int(c.dna) < pcost:
				_game.hud["toast"].call(_game.i18n.tr_key("Not enough DNA"), "bad", "🧬")
				return
			c.spend_dna(pcost)
			g["pattern"] = String(pnext["id"])
		"coat":
			var cidx := _coat_index(String(g["coat"]))
			var cnext: Dictionary = PartsScript.COATS[(cidx + 1) % PartsScript.COATS.size()]
			var ccost := int(cnext["cost"])
			if int(c.dna) < ccost:
				_game.hud["toast"].call(_game.i18n.tr_key("Not enough DNA"), "bad", "🧬")
				return
			c.spend_dna(ccost)
			g["coat"] = String(cnext["id"])
		"size":
			var half := float(r["x"]) + float(r["w"]) / 2.0
			var dir := -1 if mx < half else 1
			var b: Dictionary = GenomeScript.GENE_BOUNDS["size"]
			var level := _round_js((float(g["size"]) - float(b["min"])) / 0.2)
			var max_level := _round_js((float(b["max"]) - float(b["min"])) / 0.2)
			var nl := clampi(level + dir, 0, max_level)
			if nl == level:
				return
			var scost := 30 * maxi(0, nl - level)
			if dir > 0:
				if not c.spend_dna(scost):
					_game.hud["toast"].call(_game.i18n.tr_key("Not enough DNA"), "bad", "🧬")
					return
			# shrinking refunds nothing — a fresh size-1 genome minted +30 by
			# shrinking straight away (starter-refund faucet, round-3 family)
			g["size"] = float(String.num(float(b["min"]) + float(nl) * 0.2, 2))
			# TS audio.play('dna', 0.7)
		"hue":
			slider_drag = "hue"
			var tt := PMathScript.clamp((mx - float(r["x"]) - 14.0) / (float(r["w"]) - 28.0), 0.0, 1.0)
			g["hue"] = tt * 360.0
		"sat":
			slider_drag = "sat"
			var st := PMathScript.clamp((mx - float(r["x"]) - 14.0) / (float(r["w"]) - 28.0), 0.0, 1.0)
			g["sat"] = 0.05 + st * 0.95
		_:
			pass
	c.refresh_stats(mode == "creature")
	dirty_since_save = true
	on_stats_changed.call()


# ---- render -----------------------------------------------------------------

## TS render() — the editor overlay. Screen-space identity; the owning scene
## draws this layer above the hud (game.ts:549 order).
func draw(ci: CanvasItem, vw: float, vh: float) -> void:
	var c: Variant = _game.context
	var g := _g()

	# backdrop
	ci.draw_rect(Rect2(0.0, 0.0, vw, vh), RendererScript.css_color("rgba(3,6,16,0.88)"))

	var pad := 24.0
	var top := 70.0
	var bottom_pad := 24.0
	var left_w := minf(460.0, vw * 0.42)
	var left_x := pad
	var left_y := top
	var left_h := vh - top - bottom_pad
	var right_x := pad + left_w + 16.0
	var right_w := vw - right_x - pad

	# ---- left: preview -----------------------------------------------------------
	RendererScript.panel(ci, left_x, left_y, left_w, left_h, {
		"fill": RendererScript.css_color("rgba(8,14,32,0.92)"),
		"stroke": RendererScript.css_color("rgba(120,180,255,0.3)"),
		"shadow": RendererScript.css_color("rgba(40,120,255,0.2)"),
	})
	RendererScript.outlined_text(ci, _game.i18n.tr_key("SPECIES EDITOR"), left_x + left_w / 2.0, left_y + 26.0,
			{"size": 15.0, "fill": Color("#8fd0ff"), "weight": "700"})
	RendererScript.outlined_text(ci, NamesScript.self_name(g), left_x + left_w / 2.0, left_y + 52.0,
			{"size": 22.0, "fill": RendererScript.hsl(float(g["hue"]), float(g["sat"]), 0.72),
					"weight": "700"})
	RendererScript.outlined_text(ci, "%s %d · %s" % [_game.i18n.tr_key("generation"),
			int(g["generation"]), _game.i18n.tr_key(String(g["diet"]))],
			left_x + left_w / 2.0, left_y + 76.0,
			{"size": 12.0, "fill": RendererScript.css_color("rgba(200,220,255,0.6)")})

	# preview box (drop shadow ellipse) — compose with the caller's camera
	# cancellation (see the note in _draw_preview; the creature stage's enabled
	# Camera2D turns a bare draw_set_transform into an off-screen draw)
	var pv_x := left_x + left_w / 2.0
	var pv_y := left_y + 250.0
	var inv: Transform2D = _game.get_viewport().canvas_transform.affine_inverse()
	ci.draw_set_transform_matrix(inv * Transform2D(0.0, Vector2(pv_x, pv_y + 10.0)) \
			.scaled_local(Vector2(1.0, 0.1)))
	ci.draw_circle(Vector2.ZERO, 120.0, RendererScript.css_color("rgba(4,8,20,0.7)"))
	ci.draw_set_transform_matrix(inv)
	if mode == "cell":
		CellPainterScript.draw_cell(ci, g, {
			"x": pv_x, "y": pv_y, "moveAngle": 0.0, "speed": 0.06, "scale": 3.2,
			"hurt": 0.0, "eat": maxf(0.0, sin(preview_t * 1.4)) * 0.5, "dash": 0.0,
			"seed": 3.7,
		}, {"t": preview_t})
	else:
		_draw_preview(ci, pv_x, pv_y, inv)

	# stats readout
	var stats: Dictionary = StatsScript.compute_stats(g, mode == "creature")
	var sy := left_y + left_h - 150.0
	var readout := [
		["❤ HP", float(stats["max_hp"]), 0.0, 120.0],
		["⚔ DMG", float(stats["damage"]), 0.0, 40.0],
		["⚡ SPD", float(stats["speed"] if mode == "creature" else stats["swim_speed"]), 0.0, 200.0],
		["✦ CHARM", float(stats["charm"]), 0.0, 8.0],
		["🛡 DEF", float(stats["defense"]), 0.0, 0.7],
	]
	var ry := sy
	for row in readout:
		RendererScript.outlined_text(ci, String(row[0]), left_x + 20.0, ry,
				{"size": 12.0, "fill": RendererScript.css_color("rgba(200,225,255,0.8)"), "align": "left"})
		var bx := left_x + 90.0
		var bw := left_w - 130.0
		RendererScript.gradient_rounded_rect(ci, Rect2(bx, ry - 5.0, bw, 10.0), 5.0,
				RendererScript.css_color("rgba(255,255,255,0.08)"),
				RendererScript.css_color("rgba(255,255,255,0.08)"))
		var p := PMathScript.clamp((float(row[1]) - float(row[2])) / maxf(0.001, float(row[3]) - float(row[2])), 0.0, 1.0)
		RendererScript.gradient_rounded_rect(ci, Rect2(bx, ry - 5.0, maxf(4.0, bw * p), 10.0), 5.0,
				Color("#4f8fff"), Color("#9fe8ff"))
		ry += 22.0

	# ---- right: parts list ---------------------------------------------------------
	RendererScript.panel(ci, right_x, left_y, right_w, left_h, {
		"fill": RendererScript.css_color("rgba(8,14,32,0.92)"),
		"stroke": RendererScript.css_color("rgba(120,180,255,0.3)"),
	})
	list_rect = {"x": right_x + 12.0, "y": left_y + 46.0, "w": right_w - 24.0, "h": left_h - 110.0}
	RendererScript.outlined_text(ci,
			_game.i18n.tr_key("CELL PARTS") if mode == "cell" else _game.i18n.tr_key("BODY PARTS"),
			right_x + right_w / 2.0, left_y + 24.0,
			{"size": 13.0, "fill": Color("#8fd0ff"), "weight": "700"})

	# TS clips the rows to the right panel (ctx.rect+clip); Godot CanvasItem
	# has no draw-time rect clip — the visibility gate below keeps rows inside
	# the band, partial edge rows may spill a few px (documented divergence)
	row_rects = []
	var y := left_y + 52.0 - scroll
	for row2 in rows:
		var rh := 44.0
		if y + rh > left_y and y < left_y + left_h - 60.0:
			render_row(ci, row2, right_x + 12.0, y, right_w - 24.0, rh)
		y += rh

	# scrollbar + affordance hint — SIZE/HUE/SAT used to hide below the
	# fold with no visible way to reach them
	var content_h := float(rows.size()) * 44.0
	if content_h > float(list_rect["h"]):
		var bar_h := maxf(30.0, (float(list_rect["h"]) * float(list_rect["h"])) / content_h)
		var max_scroll := maxf(1.0, content_h - float(list_rect["h"]))
		var bar_y := float(list_rect["y"]) + (float(list_rect["h"]) - bar_h) * (scroll / max_scroll)
		ci.draw_rect(Rect2(right_x + right_w - 7.0, bar_y, 3.0, bar_h),
				RendererScript.css_color("rgba(140,180,230,0.4)"))
		RendererScript.outlined_text(ci, _game.i18n.tr_key("⟳ wheel scrolls more parts"),
				right_x + 16.0, left_y + left_h - 62.0,
				{"size": 10.0, "fill": RendererScript.css_color("rgba(150,190,235,0.55)"), "align": "left"})

	# footer: DNA + close
	var fy := left_y + left_h - 52.0
	RendererScript.outlined_text(ci, "🧬 %s %s" % [PMathScript.format_num(float(c.dna)),
			_game.i18n.tr_key("DNA available")], right_x + 16.0, fy + 20.0,
			{"size": 16.0, "fill": Color("#bfe6ff"), "align": "left"})
	close_rect = {"x": right_x + right_w - 130.0, "y": fy + 2.0, "w": 116.0, "h": 40.0}
	RendererScript.panel(ci, float(close_rect["x"]), float(close_rect["y"]),
			float(close_rect["w"]), float(close_rect["h"]), {
				"fill": RendererScript.css_color("rgba(50,110,220,0.9)"),
				"stroke": RendererScript.css_color("rgba(160,210,255,0.7)"),
			})
	RendererScript.outlined_text(ci, "DONE (E)", float(close_rect["x"]) + float(close_rect["w"]) / 2.0,
			float(close_rect["y"]) + 20.0, {"size": 14.0, "fill": Color("#fff")})
	update_editor_cursor()


## Pointer cursor over any interactive editor rect (TS updateEditorCursor).
func update_editor_cursor() -> void:
	var input: Variant = _game.input
	var mx := float(input.mx)
	var my := float(input.my)
	if _hit(mx, my, close_rect):
		_game.hover_cursor()
		return
	for rr in row_rects:
		if _hit(mx, my, rr["r"]):
			_game.hover_cursor()
			return
	for sr in slider_rects.values():
		if sr != null and _hit(mx, my, sr):
			_game.hover_cursor()
			return


func render_row(ci: CanvasItem, row: Dictionary, x: float, y: float, w: float, h: float) -> void:
	var g := _g()
	var c: Variant = _game.context

	RendererScript.panel(ci, x, y, w, h, {
		"fill": RendererScript.css_color("rgba(12,20,44,0.8)"),
		"stroke": RendererScript.css_color("rgba(120,160,220,0.16)"),
	})

	if String(row["kind"]) == "graft":
		var gcost := graft_cost(row["def"], int(row["level"]))
		RendererScript.panel(ci, x, y, w, h, {
			"fill": RendererScript.css_color("rgba(38,26,58,0.85)"),
			"stroke": RendererScript.css_color("rgba(200,150,255,0.45)"),
		})
		RendererScript.outlined_text(ci, _game.i18n.tr_key("BORROWED FLESH"), x + 12.0, y + 14.0,
				{"size": 12.0, "fill": Color("#dcc2ff"), "align": "left", "weight": "700"})
		RendererScript.outlined_text(ci, "%s → %d · %s" % [_game.i18n.tr_key(String(row["def"]["name"])),
				int(row["level"]), String(row["species"])], x + 12.0, y + 31.0,
				{"size": 10.0, "fill": RendererScript.css_color("rgba(210,190,245,0.7)"),
						"align": "left", "maxWidth": w - 118.0})
		RendererScript.outlined_text(ci, "%s %d" % [_game.i18n.tr_key("graft"), gcost],
				x + w - 16.0, y + h / 2.0, {"size": 12.0, "fill": Color("#e8d8ff"), "align": "right"})
		row_rects.append({"row": row, "r": {"x": x, "y": y, "w": w, "h": h}, "btn": null})
		return

	if String(row["kind"]) == "part":
		var def: Dictionary = row["def"]
		var level := int(g.get(def["gene"], 0))
		RendererScript.outlined_text(ci, _game.i18n.tr_key(String(def["name"])), x + 12.0, y + 14.0,
				{"size": 13.0, "fill": Color("#e8f2ff"), "align": "left", "weight": "700"})
		var d: String = _game.i18n.tr_key(String(def["desc"]))
		RendererScript.outlined_text(ci, "%s · %s" % [_game.i18n.tr_key(String(def["effect"])),
				d if d.length() <= 46 else d.substr(0, 46) + "…"], x + 12.0, y + 31.0,
				{"size": 10.0, "fill": RendererScript.css_color("rgba(190,215,245,0.55)"),
						"align": "left", "maxWidth": w - 118.0})
		# level pips
		for i in int(def["max"]):
			var px := x + w - 118.0 + float(i) * 8.0
			var pip := RendererScript.hsl(float(g["hue"]), 0.8, 0.6) if i < level \
					else RendererScript.css_color("rgba(255,255,255,0.12)")
			ci.draw_circle(Vector2(px, y + 14.0), 3.0, pip)
		# buttons
		var can_buy := level < int(def["max"])
		var cost: int = PartsScript.part_cost(def, level)
		var plus_rect := {"x": x + w - 44.0, "y": y + 6.0, "w": 34.0, "h": 32.0}
		RendererScript.panel(ci, float(plus_rect["x"]), float(plus_rect["y"]),
				float(plus_rect["w"]), float(plus_rect["h"]), {
					"fill": RendererScript.css_color("rgba(60,150,90,0.9)")
							if can_buy and int(c.dna) >= cost
							else RendererScript.css_color("rgba(60,70,90,0.6)"),
					"stroke": RendererScript.css_color("rgba(255,255,255,0.2)"),
				})
		row_rects.append({"row": row, "r": plus_rect, "btn": "+"})
		RendererScript.outlined_text(ci, "%d" % cost if can_buy else _game.i18n.tr_key("MAX"),
				float(plus_rect["x"]) + 17.0, float(plus_rect["y"]) + 16.0,
				{"size": 11.0, "fill": Color("#fff")})
		var bound: Variant = GenomeScript.GENE_BOUNDS.get(def["gene"], null)
		var min_level := int(bound["min"]) if bound != null else 0
		if level > min_level:
			var minus_rect := {"x": x + w - 84.0, "y": y + 6.0, "w": 34.0, "h": 32.0}
			RendererScript.panel(ci, float(minus_rect["x"]), float(minus_rect["y"]),
					float(minus_rect["w"]), float(minus_rect["h"]), {
						"fill": RendererScript.css_color("rgba(120,70,70,0.8)"),
						"stroke": RendererScript.css_color("rgba(255,255,255,0.2)"),
					})
			row_rects.append({"row": row, "r": minus_rect, "btn": "-"})
			RendererScript.outlined_text(ci, "−", float(minus_rect["x"]) + 17.0,
					float(minus_rect["y"]) + 16.0, {"size": 14.0, "fill": Color("#ffcfcf")})
		row_rects.append({"row": row, "r": {"x": x, "y": y, "w": w - 90.0, "h": h}, "btn": null})
		return

	match String(row["kind"]):
		"diet":
			var diet: Dictionary = _diet_def(String(g["diet"]))
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("DIET"),
					"%s — %s" % [_game.i18n.tr_key(String(diet["name"])),
							_game.i18n.tr_key(String(diet["desc"]))],
					"(%d DNA to switch)" % int(diet["cost"]) if int(diet["cost"]) > 0 else "")
			var nxt: Dictionary = PartsScript.DIETS[(_diet_index(String(g["diet"])) + 1) % PartsScript.DIETS.size()]
			RendererScript.outlined_text(ci, "%s %s ▸" % [_game.i18n.tr_key("next:"),
					_game.i18n.tr_key(String(nxt["name"]))], x + w - 16.0, y + h / 2.0,
					{"size": 11.0, "fill": Color("#9fc8ff"), "align": "right"})
		"pattern":
			var pat: Dictionary = _pattern_def(String(g["pattern"]))
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("SKIN PATTERN"),
					_game.i18n.tr_key(String(pat["name"])),
					"(%d DNA)" % int(pat["cost"]) if int(pat["cost"]) > 0 else "")
			RendererScript.outlined_text(ci, "switch ▸", x + w - 16.0, y + h / 2.0,
					{"size": 11.0, "fill": Color("#9fc8ff"), "align": "right"})
		"coat":
			var coat: Dictionary = _coat_def(String(g["coat"]))
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("COAT"),
					"%s — %s" % [_game.i18n.tr_key(String(coat["name"])),
							_game.i18n.tr_key(String(coat["effect"]))],
					"(%d DNA)" % int(coat["cost"]) if int(coat["cost"]) > 0 else "")
			RendererScript.outlined_text(ci, "switch ▸", x + w - 16.0, y + h / 2.0,
					{"size": 11.0, "fill": Color("#9fc8ff"), "align": "right"})
		"size":
			var b2: Dictionary = GenomeScript.GENE_BOUNDS["size"]
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("BODY SIZE"),
					"%s×" % String.num(float(g["size"]), 1),
					_game.i18n.tr_key("(click halves to shrink / grow — 30 DNA per step)"))
			# size bar
			var bx2 := x + w - 130.0
			var bw2 := 110.0
			var size_t := (float(g["size"]) - float(b2["min"])) / (float(b2["max"]) - float(b2["min"]))
			RendererScript.gradient_rounded_rect(ci, Rect2(bx2, y + 12.0, bw2, 20.0), 8.0,
					RendererScript.css_color("rgba(255,255,255,0.1)"),
					RendererScript.css_color("rgba(255,255,255,0.1)"))
			RendererScript.gradient_rounded_rect(ci, Rect2(bx2, y + 12.0, maxf(8.0, bw2 * size_t), 20.0), 8.0,
					RendererScript.hsl(float(g["hue"]), 0.7, 0.6),
					RendererScript.hsl(float(g["hue"]), 0.7, 0.6))
		"hue":
			_row_label(ci, x, y, w, h, "COLOR", "", "")
			var bx3 := x + 90.0
			var bw3 := w - 110.0
			# hue spectrum: 7 flat stops (TS draws a smooth gradient; vertex
			# color fans below segment count — presence-level, renderer notes)
			var seg := bw3 / 6.0
			for i in 7:
				RendererScript.gradient_rounded_rect(ci,
						Rect2(bx3 + float(i) * seg - (0.0 if i == 0 else 0.5), y + 10.0,
								seg + (0.0 if i == 0 else 1.0), 22.0), 8.0,
						RendererScript.hsl(float(i) * 60.0, 0.8, 0.55),
						RendererScript.hsl(float(i) * 60.0, 0.8, 0.55))
			var hpx := bx3 + (float(g["hue"]) / 360.0) * bw3
			ci.draw_circle(Vector2(hpx, y + 21.0), 6.0, Color("#fff"))
			slider_rects["hue"] = {"x": bx3, "y": y + 10.0, "w": bw3, "h": 22.0}
			row_rects.append({"row": row, "r": {"x": bx3, "y": y + 4.0, "w": bw3, "h": 34.0}, "btn": null})
		"sat":
			_row_label(ci, x, y, w, h, "SATURATION", "", "")
			var bx4 := x + 110.0
			var bw4 := w - 130.0
			RendererScript.gradient_rounded_rect(ci, Rect2(bx4, y + 10.0, bw4, 22.0), 8.0,
					RendererScript.hsl(float(g["hue"]), 0.05, 0.55),
					RendererScript.hsl(float(g["hue"]), 1.0, 0.55))
			var spx := bx4 + ((float(g["sat"]) - 0.05) / 0.95) * bw4
			ci.draw_circle(Vector2(spx, y + 21.0), 6.0, Color("#fff"))
			slider_rects["sat"] = {"x": bx4, "y": y + 10.0, "w": bw4, "h": 22.0}
			row_rects.append({"row": row, "r": {"x": bx4, "y": y + 4.0, "w": bw4, "h": 34.0}, "btn": null})
		_:
			pass
	row_rects.append({"row": row, "r": {"x": x, "y": y, "w": w, "h": h}, "btn": null})


## TS renderRow's `label()` helper — name over description (+optional extra).
func _row_label(ci: CanvasItem, x: float, y: float, w: float, h: float, name: String,
		value: String, extra := "") -> void:
	RendererScript.outlined_text(ci, name, x + 12.0, y + 14.0,
			{"size": 12.0, "fill": Color("#e8f2ff"), "align": "left", "weight": "700"})
	RendererScript.outlined_text(ci, value + ("" if extra == "" else "  %s" % extra),
			x + 12.0, y + 30.0,
			{"size": 10.0, "fill": RendererScript.css_color("rgba(190,215,245,0.65)"),
					"align": "left", "maxWidth": w - 24.0})


## TS editor.ts:322-326 — the creature-mode preview through the task-6 painter.
## Pose numbers verbatim (facing 1, speed 0.12, mood happy, scale 2.1). The
## painter's three sub-RIDs are CALLER-OWNED (task 6 contract): freed at the
## top of every redraw, on close() and via free_preview_rids() on stage
## teardown. Extracted from draw() so headless tests can drive it on a bare
## CanvasItem (the draw_* helpers would guard outside _draw).
func _draw_preview(ci: CanvasItem, pv_x: float, pv_y: float,
		inv: Transform2D = Transform2D()) -> void:
	free_preview_rids()
	# The owning stage draws this canvas in TS screen space by cancelling the
	# live viewport canvas_transform on its own draw calls — but the painter's
	# RenderingServer sub-items compose the RAW canvas transform (the enabled
	# Camera2D), and its main-item transform state does not inherit the
	# CanvasItem draw transform either. Feed the cancellation through the
	# painter's base_pos/base_zoom (screen_inv = Tr(origin)·Sc(scale) for the
	# camera's translate+zoom) and restore the item's draw transform after —
	# the painter leaves its last pose transform on it, which used to corrupt
	# every later draw on this canvas (stats/rows/footer) in creature mode.
	var res: Dictionary = CreaturePainter.draw_creature(ci, _g(), {
		"x": pv_x, "y": pv_y, "facing": 1, "speed": 0.12, "gaitPhase": gait,
		"attack": 0.0, "hurt": 0.0, "eat": 0.0, "airborne": 0.0,
		"mood": "happy", "scale": 2.1,
	}, {"t": preview_t}, inv.origin, absf(inv.get_scale().x))
	_preview_rids = [res["clip_item"], res["pattern_item"], res["front_item"]]
	ci.draw_set_transform_matrix(inv)


func free_preview_rids() -> void:
	for rid in _preview_rids:
		RenderingServer.free_rid(rid)
	_preview_rids = []


# ---- lookup helpers (TS DIETS.find / PATTERNS.find / COATS.find) --------------

func _diet_index(id: String) -> int:
	for i in PartsScript.DIETS.size():
		if String(PartsScript.DIETS[i]["id"]) == id:
			return i
	return 0


func _diet_def(id: String) -> Dictionary:
	return PartsScript.DIETS[_diet_index(id)]


func _pattern_index(id: String) -> int:
	for i in PartsScript.PATTERNS.size():
		if String(PartsScript.PATTERNS[i]["id"]) == id:
			return i
	return 0


func _pattern_def(id: String) -> Dictionary:
	return PartsScript.PATTERNS[_pattern_index(id)]


func _coat_index(id: String) -> int:
	for i in PartsScript.COATS.size():
		if String(PartsScript.COATS[i]["id"]) == id:
			return i
	return 0


func _coat_def(id: String) -> Dictionary:
	return PartsScript.COATS[_coat_index(id)]


## JS Math.round (ties toward +infinity) — GDScript roundi rounds halves away
## from zero, identical for every positive input this row math produces.
func _round_js(x: float) -> int:
	return floori(x + 0.5)


func _hit(mx: float, my: float, r: Dictionary) -> bool:
	return mx >= float(r["x"]) and mx <= float(r["x"]) + float(r["w"]) \
			and my >= float(r["y"]) and my <= float(r["y"]) + float(r["h"])
