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
##
## R6 experience redesign: the list splits into two tabs — BODY (parts + diet
## + size + graft: the DNA economy) and LOOK (hue/sat/pattern/coat + an inert
## name placeholder: free cosmetics — PATTERNS/COATS costs are zeroed in the
## parts.gd data — with no DNA display on the tab at all). The switch is
## session-local — every open starts on BODY and nothing rides the save wire.
## The world backdrop eases to 0.6 (hold-to-peek 0.2 via the on-screen
## hold-button bottom-right or Alt).
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
## R6 tab: 'body' | 'look' — session-local, every show() resets to 'body'.
var tab := "body"
var rows: Array = []          # TS private rows — public for the headless tests
var scroll := 0.0
var preview_t := 0.0
var gait := 0.0
var open_t := 0.0
var dirty_since_save := false
## R6 world peek — true while the on-screen hold-button or Alt is down.
var peeking := false
## TS private sliderDrag: 'hue' | 'sat' | null — "" natively.
var slider_drag := ""
var slider_rects := {"hue": null, "sat": null}
## TS private listRect/closeRect — draw-computed (update reads the last pass).
var list_rect := {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0}
var close_rect := {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0}
## R6 draw-computed rects — the tab pair (top of the parts panel) and the
## peek hold-button (bottom-right strip).
var tab_rects := {"body": {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0},
		"look": {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0}}
var peek_rect := {"x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0}
## R7 name picker — the draft buffer + recorded button rects (draw-populated
## like row_rects; the on-canvas grid replaces the LOOK rows while open).
var picker_open := false
var picker_buf := ""
var picker_rects: Array = []
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
	tab = "body"  # R6: the switch is session-local — every open starts on BODY
	picker_open = false  # R7: every open starts clean
	picker_buf = ""
	scroll = 0.0
	rows = build_rows()
	# TS audio.play('warp', 0.5) — audio core is its own task


func close() -> void:
	open = false
	picker_open = false
	_sync_open()
	free_preview_rids()
	# QC r8 batch2.1: a mouse button HELD while the editor closes used to leak
	# into the sim (input.down stayed true → the cell kept swimming toward the
	# cursor ~80 px/s until the next click). TS re-derives pointer state per
	# event, native must drop the stale latch here.
	_game.input.down = false
	_game.input.clicked = false
	# dirty-flag: E-spam used to write localStorage ~30×/s (~2700 saves in a
	# 90s session) — only persist when the genome actually changed
	if dirty_since_save:
		dirty_since_save = false
		# saveAll, not save — the genome write must carry the stage blob too
		if not _game.save_all():
			# QC r8 batch2.4 — desktop wording (see pause.gd twin)
			_game.hud["toast"].call(_game.i18n.tr_key("Save failed — could not write save file"), "bad", "💾")
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


## R6 look-tab price — a THIN ACCESSOR over the parts catalog, kept for the
## test pins. The freeness itself lives in the PATTERNS/COATS data (costs
## zeroed in parts.gd): the buy path and the display sites read the catalog
## directly, so the DNA accounting can never diverge from what the data says.
## Ids outside the LOOK catalog keep their standard catalog cost.
static func look_price(part_id: String) -> int:
	for p in PartsScript.PATTERNS:
		if String(p["id"]) == part_id:
			return int(p["cost"])
	for c in PartsScript.COATS:
		if String(c["id"]) == part_id:
			return int(c["cost"])
	var d: Dictionary = PartsScript.part_by_id(part_id)
	if not d.is_empty():
		return PartsScript.part_cost(d, 0)
	for diet in PartsScript.DIETS:
		if String(diet["id"]) == part_id:
			return int(diet["cost"])
	return 0


## R6 world peek — the backdrop alpha while the editor is open: 0.6 at rest
## (the old full-black wall eased down), 0.2 while the hold-button or Alt is
## down. Both constants live here, never at the draw site.
static func world_dim(peeking_v: bool) -> float:
	return 0.2 if peeking_v else 0.6


## R6 tab switch — session-local (show() resets to BODY; nothing is saved).
func switch_tab(t: String) -> void:
	if t == tab:
		return
	tab = t
	picker_open = false  # R7: leaving LOOK leaves the picker
	scroll = 0.0
	rows = build_rows()


## R6: the DNA economy display (the footer counter) exists on BODY only —
## LOOK is free cosmetics and hides ALL DNA display while on the tab.
func dna_visible() -> bool:
	return tab == "body"


func build_rows() -> Array:
	var out: Array = []
	if tab == "look":
		# ruling order: hue/sat/pattern/coat + the inert name row last
		out.append({"kind": "hue"})
		out.append({"kind": "sat"})
		out.append({"kind": "pattern"})
		if mode == "creature":
			out.append({"kind": "coat"})
		# R7 replaces this placeholder with the on-canvas name picker
		out.append({"kind": "name"})
		return out
	for def in PartsScript.PARTS:
		if String(def["stage"]) == mode or String(def["stage"]) == "both":
			out.append({"kind": "part", "def": def})
	out.append({"kind": "diet"})
	out.append({"kind": "size"})
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

	# R6 world peek — re-derived every frame from the held state (Alt through
	# the GameInput live poll, the button through the cursor over its rect)
	peeking = bool(input.key("Alt")) \
			or (bool(input.is_down()) and _hit(float(input.mx), float(input.my), peek_rect))

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
	# R6 peek hold-button — consume the press so a hold there never buys a
	# part or latches a slider; the held state itself is read at the top
	if _hit(mx, my, peek_rect):
		input.take_click()
		return
	# R6 tab bar
	for t in tab_rects:
		if _hit(mx, my, tab_rects[t]):
			input.take_click()
			switch_tab(String(t))
			return
	# R7 picker buttons — routed before the row path (the rows are not drawn
	# while the picker is open; row_rects is empty there)
	if picker_open:
		for pr in picker_rects:
			if _hit(mx, my, pr["r"]):
				input.take_click()
				_picker_click(pr)
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
		# creature-mode sell warning (QC round-1 carry, r2 B3): selling the
		# last LEG leaves a legless worm — survivable (no softlock, berries
		# still feed) but the sell was completely silent. Warn WITHOUT
		# blocking: unlike the cell guard above, the sell proceeds.
		if mode == "creature" and String(def["gene"]) == "legs" and level - 1 < 1:
			_game.hud["toast"].call(
					_game.i18n.tr_key("Selling your last LEG — you will only crawl."), "bad", "🦵")
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


## R7 — the LOOK name row opens the on-canvas picker; the draft starts at the
## current display name (the self_name suggestion when nothing is saved —
## "accept or edit").
func _open_picker() -> void:
	picker_open = true
	picker_buf = _game.context.get_display_name()


## R7 picker button dispatch — update() routes the recorded picker rects here
## (the headless tests drive it directly; the real click path is the same
## dispatch). Glyphs append up to the cap, backspace pops, accept routes
## through context.set_display_name (the central filter — an emptied draft
## accepts as not-set and the display falls back to the suggestion), cancel
## discards.
func _picker_click(pr: Dictionary) -> void:
	var kind := String(pr["kind"])
	if kind == "glyph":
		if picker_buf.length() < NamesScript.NAME_MAX_LEN:
			picker_buf += String(pr["ch"])
		return
	if kind == "backspace":
		picker_buf = picker_buf.substr(0, maxi(0, picker_buf.length() - 1))
		return
	if kind == "accept":
		var before: String = _game.context.creature_name
		var stored: String = _game.context.set_display_name(picker_buf)
		picker_buf = stored
		picker_open = false
		if stored != before:
			dirty_since_save = true  # a real name change persists (close() saves)
		return
	picker_open = false  # cancel — the draft is discarded


func click_row(row: Dictionary, mx: float, r: Dictionary) -> void:
	var g := _g()
	var c: Variant = _game.context
	if String(row["kind"]) == "graft":
		click_graft(row)
		return
	if String(row["kind"]) == "name":
		_open_picker()  # R7 — the picker entry point (replaces the R6 placeholder)
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
			# R6: the cost rides the catalog (PATTERNS costs are zeroed in
			# parts.gd) — free, re-switchable, no inline 0 at the call site
			var pidx := _pattern_index(String(g["pattern"]))
			var pnext: Dictionary = PartsScript.PATTERNS[(pidx + 1) % PartsScript.PATTERNS.size()]
			var pcost := int(pnext["cost"])
			if pcost > 0 and int(c.dna) < pcost:
				_game.hud["toast"].call(_game.i18n.tr_key("Not enough DNA"), "bad", "🧬")
				return
			if pcost > 0:
				c.spend_dna(pcost)
			g["pattern"] = String(pnext["id"])
		"coat":
			var cidx := _coat_index(String(g["coat"]))
			var cnext: Dictionary = PartsScript.COATS[(cidx + 1) % PartsScript.COATS.size()]
			var ccost := int(cnext["cost"])
			if ccost > 0 and int(c.dna) < ccost:
				_game.hud["toast"].call(_game.i18n.tr_key("Not enough DNA"), "bad", "🧬")
				return
			if ccost > 0:
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

	# backdrop — R6: the alpha rides world_dim (0.6 rest, 0.2 while peeking;
	# both constants live on the helper, never here)
	ci.draw_rect(Rect2(0.0, 0.0, vw, vh),
			Color(3.0 / 255.0, 6.0 / 255.0, 16.0 / 255.0, world_dim(peeking)))

	var pad := 24.0
	var top := 70.0
	# R6: 64 — the panels stop above a bottom strip so the peek hold-button
	# sits alone at the bottom-right (over the world when peeking)
	var bottom_pad := 64.0
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
	RendererScript.outlined_text(ci, c.get_display_name(), left_x + left_w / 2.0, left_y + 52.0,
			{"size": 22.0, "fill": RendererScript.hsl(float(g["hue"]), float(g["sat"]), 0.72),
					"weight": "700"})
	# F2 (QC r3): the raw diet id ("herbivore") misses the capitalized vi.csv
	# keyspace — resolve the display name through _diet_def, the same source
	# the diet-switch row uses. EN shows "Herbivore" (was the raw lowercase id;
	# TS editor.ts:312 leaks the id too — native polish, task-ruled).
	RendererScript.outlined_text(ci, "%s %d · %s" % [_game.i18n.tr_key("generation"),
			int(g["generation"]),
			_game.i18n.tr_key(String(_diet_def(String(g["diet"]))["name"]))],
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
	# R6 tab bar — the title goes left-aligned, the BODY/LOOK pair sits
	# top-right; the switch is session-local (never persisted)
	var tab_w := 78.0
	var look_x := right_x + right_w - 12.0 - tab_w
	tab_rects["look"] = {"x": look_x, "y": left_y + 9.0, "w": tab_w, "h": 30.0}
	tab_rects["body"] = {"x": look_x - 6.0 - tab_w, "y": left_y + 9.0, "w": tab_w, "h": 30.0}
	if tab == "look":
		RendererScript.outlined_text(ci, _game.i18n.tr_key("LOOK"), right_x + 16.0, left_y + 24.0,
				{"size": 13.0, "fill": Color("#8fd0ff"), "weight": "700", "align": "left"})
	else:
		RendererScript.outlined_text(ci,
				_game.i18n.tr_key("CELL PARTS") if mode == "cell" else _game.i18n.tr_key("BODY PARTS"),
				right_x + 16.0, left_y + 24.0,
				{"size": 13.0, "fill": Color("#8fd0ff"), "weight": "700", "align": "left"})
	for t in ["body", "look"]:
		var tb: Dictionary = tab_rects[String(t)]
		var active := tab == String(t)
		RendererScript.panel(ci, float(tb["x"]), float(tb["y"]), float(tb["w"]), float(tb["h"]), {
			"fill": RendererScript.css_color("rgba(50,110,220,0.9)") if active
					else RendererScript.css_color("rgba(20,34,64,0.85)"),
			"stroke": RendererScript.css_color("rgba(160,210,255,0.7)") if active
					else RendererScript.css_color("rgba(120,180,255,0.3)"),
		})
		RendererScript.outlined_text(ci,
				_game.i18n.tr_key("BODY") if String(t) == "body" else _game.i18n.tr_key("LOOK"),
				float(tb["x"]) + float(tb["w"]) / 2.0, float(tb["y"]) + 19.0,
				{"size": 13.0, "fill": Color("#fff") if active else Color("#9fc8ff")})

	# TS clips the rows to the right panel (ctx.rect+clip); Godot CanvasItem
	# has no draw-time rect clip — the visibility gate below keeps rows inside
	# the band, partial edge rows may spill a few px (documented divergence)
	row_rects = []
	if picker_open:
		# R7: the on-canvas picker replaces the rows (row_rects stays empty —
		# update() routes the picker's own rects instead)
		_draw_picker(ci)
	else:
		var y := left_y + 52.0 - scroll
		for row2 in rows:
			var rh := 44.0
			# QC r8 batch2.2: the gate keeps the row BOTTOM above the footer block
			# (fy = left_h − 52) — the old START-gate alone let the last visible
			# row spill 44px down over the hint + the DNA line at vh 648
			if y + rh > left_y and y + rh <= left_y + left_h - 52.0:
				render_row(ci, row2, right_x + 12.0, y, right_w - 24.0, rh)
			y += rh

	# scrollbar — SIZE/HUE/SAT used to hide below the fold with no visible
	# way to reach them. QC r8 batch2.2: the affordance hint moved under the
	# panel title — at the band bottom it sat ON the last row's glyphs.
	# R7: hidden while the picker is open (it draws no scrolling content).
	var content_h := float(rows.size()) * 44.0
	if not picker_open and content_h > float(list_rect["h"]):
		var bar_h := maxf(30.0, (float(list_rect["h"]) * float(list_rect["h"])) / content_h)
		var max_scroll := maxf(1.0, content_h - float(list_rect["h"]))
		var bar_y := float(list_rect["y"]) + (float(list_rect["h"]) - bar_h) * (scroll / max_scroll)
		ci.draw_rect(Rect2(right_x + right_w - 7.0, bar_y, 3.0, bar_h),
				RendererScript.css_color("rgba(140,180,230,0.4)"))
		RendererScript.outlined_text(ci, _game.i18n.tr_key("⟳ wheel scrolls more parts"),
				right_x + 16.0, left_y + 40.0,
				{"size": 10.0, "fill": RendererScript.css_color("rgba(150,190,235,0.55)"), "align": "left"})

	# footer: DNA + close — R6: the DNA counter draws on BODY only (LOOK
	# hides ALL DNA display while on the tab)
	var fy := left_y + left_h - 52.0
	if dna_visible():
		RendererScript.outlined_text(ci, "🧬 %s %s" % [PMathScript.format_num(float(c.dna)),
				_game.i18n.tr_key("DNA available")], right_x + 16.0, fy + 20.0,
				{"size": 16.0, "fill": Color("#bfe6ff"), "align": "left"})
	close_rect = {"x": right_x + right_w - 130.0, "y": fy + 2.0, "w": 116.0, "h": 40.0}
	RendererScript.panel(ci, float(close_rect["x"]), float(close_rect["y"]),
			float(close_rect["w"]), float(close_rect["h"]), {
				"fill": RendererScript.css_color("rgba(50,110,220,0.9)"),
				"stroke": RendererScript.css_color("rgba(160,210,255,0.7)"),
			})
	RendererScript.outlined_text(ci, _game.i18n.tr_key("DONE (E)"),
			float(close_rect["x"]) + float(close_rect["w"]) / 2.0,
			float(close_rect["y"]) + 20.0, {"size": 14.0, "fill": Color("#fff")})

	# R6 peek hold-button — alone in the bottom-right strip (below the panels);
	# lights up while the hold shows the world through the backdrop
	peek_rect = {"x": right_x + right_w - 130.0, "y": vh - 58.0, "w": 116.0, "h": 40.0}
	RendererScript.panel(ci, float(peek_rect["x"]), float(peek_rect["y"]),
			float(peek_rect["w"]), float(peek_rect["h"]), {
				"fill": RendererScript.css_color("rgba(80,160,255,0.95)") if peeking
						else RendererScript.css_color("rgba(50,110,220,0.9)"),
				"stroke": RendererScript.css_color("rgba(160,210,255,0.7)"),
			})
	RendererScript.outlined_text(ci, _game.i18n.tr_key("PEEK (hold)"),
			float(peek_rect["x"]) + float(peek_rect["w"]) / 2.0,
			float(peek_rect["y"]) + 20.0, {"size": 14.0, "fill": Color("#fff")})
	RendererScript.outlined_text(ci, _game.i18n.tr_key("hold to peek the world (Alt)"),
			float(peek_rect["x"]) - 12.0, float(peek_rect["y"]) + 20.0,
			{"size": 11.0, "fill": RendererScript.css_color("rgba(150,190,235,0.55)"),
					"align": "right"})
	update_editor_cursor()


## Pointer cursor over any interactive editor rect (TS updateEditorCursor).
func update_editor_cursor() -> void:
	var input: Variant = _game.input
	var mx := float(input.mx)
	var my := float(input.my)
	if _hit(mx, my, close_rect):
		_game.hover_cursor()
		return
	if _hit(mx, my, peek_rect):
		_game.hover_cursor()
		return
	for t in tab_rects:
		if _hit(mx, my, tab_rects[t]):
			_game.hover_cursor()
			return
	if picker_open:
		for pr in picker_rects:
			if _hit(mx, my, pr["r"]):
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
					"(%d %s)" % [int(diet["cost"]),
							_game.i18n.tr_key("DNA to switch")] if int(diet["cost"]) > 0 else "")
			var nxt: Dictionary = PartsScript.DIETS[(_diet_index(String(g["diet"])) + 1) % PartsScript.DIETS.size()]
			RendererScript.outlined_text(ci, "%s %s ▸" % [_game.i18n.tr_key("next:"),
					_game.i18n.tr_key(String(nxt["name"]))], x + w - 16.0, y + h / 2.0,
					{"size": 11.0, "fill": Color("#9fc8ff"), "align": "right"})
		"pattern":
			# R6: the price extra reads the catalog — a zeroed cost renders no
			# DNA text at all (LOOK shows no DNA display)
			var pat: Dictionary = _pattern_def(String(g["pattern"]))
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("SKIN PATTERN"),
					_game.i18n.tr_key(String(pat["name"])),
					"(%d DNA)" % int(pat["cost"]) if int(pat["cost"]) > 0 else "")
			RendererScript.outlined_text(ci, _game.i18n.tr_key("switch ▸"), x + w - 16.0, y + h / 2.0,
					{"size": 11.0, "fill": Color("#9fc8ff"), "align": "right"})
		"coat":
			var coat: Dictionary = _coat_def(String(g["coat"]))
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("COAT"),
					"%s — %s" % [_game.i18n.tr_key(String(coat["name"])),
							_game.i18n.tr_key(String(coat["effect"]))],
					"(%d DNA)" % int(coat["cost"]) if int(coat["cost"]) > 0 else "")
			RendererScript.outlined_text(ci, _game.i18n.tr_key("switch ▸"), x + w - 16.0, y + h / 2.0,
					{"size": 11.0, "fill": Color("#9fc8ff"), "align": "right"})
		"name":
			# R7 — the picker entry point: the value line shows the live display
			# name (the saved pick, else the self_name suggestion — a player
			# string, interpolated outside tr); the click rect is the trailing
			# full-row append below
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("NAME"),
					_game.context.get_display_name(), "")
			RendererScript.outlined_text(ci, _game.i18n.tr_key("edit ▸"),
					x + w - 16.0, y + h / 2.0,
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
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("COLOR"), "", "")
			var bx3 := x + 90.0
			var bw3 := w - 110.0
			# hue spectrum: 7 flat stops (TS draws a smooth gradient; vertex
			# color fans below segment count — presence-level, renderer notes).
			# QC r3 (synthesis 4H): seg was bw3/6.0 with a +1px overlap fudge —
			# 7 cells of 6 widths drew the red stop 1/6 of a band past the
			# panel edge, and clicks in the drawn-over margin fell through to
			# the full-row rect (hue from the wrong formula). 7 even cells
			# tile the band exactly; the hit rect below is unchanged.
			var seg := bw3 / 7.0
			for i in 7:
				RendererScript.gradient_rounded_rect(ci,
						Rect2(bx3 + float(i) * seg, y + 10.0, seg, 22.0), 8.0,
						RendererScript.hsl(float(i) * 60.0, 0.8, 0.55),
						RendererScript.hsl(float(i) * 60.0, 0.8, 0.55))
			var hpx := bx3 + (float(g["hue"]) / 360.0) * bw3
			ci.draw_circle(Vector2(hpx, y + 21.0), 6.0, Color("#fff"))
			slider_rects["hue"] = {"x": bx3, "y": y + 10.0, "w": bw3, "h": 22.0}
			row_rects.append({"row": row, "r": {"x": bx3, "y": y + 4.0, "w": bw3, "h": 34.0}, "btn": null})
		"sat":
			_row_label(ci, x, y, w, h, _game.i18n.tr_key("SATURATION"), "", "")
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


## R7 — the on-canvas character picker, drawn in place of the LOOK rows (no
## DOM/LineEdit — this IS the Godot port the spec rules 1:1). A grid of the
## exact NAME_CHARSET glyphs (the space key draws ␣ — a raw blank is invisible),
## backspace/cancel/accept buttons, the n/14 counter and the "Max 14 · accept
## or edit" helper line. Rects recorded for update()'s click path (the editor
## button-row pattern); draws only panel/outlined_text on the caller's item —
## no sub-RIDs (the suite RID ceiling is at datum).
func _draw_picker(ci: CanvasItem) -> void:
	var g := _g()
	picker_rects = []
	slider_rects = {"hue": null, "sat": null}
	var x: float = float(list_rect["x"])
	var w: float = float(list_rect["w"])
	var y: float = float(list_rect["y"])

	# the draft — the buffer in the creature's hue, the n/14 counter right
	RendererScript.outlined_text(ci, _game.i18n.tr_key("NAME"), x, y + 12.0,
			{"size": 11.0, "fill": Color("#8fd0ff"), "align": "left", "weight": "700"})
	RendererScript.outlined_text(ci, picker_buf if picker_buf != "" else "…",
			x, y + 40.0,
			{"size": 20.0, "fill": RendererScript.hsl(float(g["hue"]), float(g["sat"]), 0.72),
					"align": "left", "maxWidth": w - 56.0})
	RendererScript.outlined_text(ci,
			"%d/%d" % [picker_buf.length(), NamesScript.NAME_MAX_LEN], x + w, y + 40.0,
			{"size": 11.0, "fill": RendererScript.css_color("rgba(190,215,245,0.65)"),
					"align": "right"})

	# the glyph grid — 13 columns tile the panel width at any viewport
	var chars := PackedStringArray()
	for i in NamesScript.NAME_CHARSET.length():
		chars.append(NamesScript.NAME_CHARSET[i])
	var cols := 13
	var cw := floorf(w / float(cols))
	var ch_h := 30.0
	var gy := y + 54.0
	for gi in chars.size():
		var col := gi % cols
		var row_i := floori(float(gi) / float(cols))
		var r := {"x": x + float(col) * cw, "y": gy + float(row_i) * (ch_h + 6.0),
				"w": cw - 4.0, "h": ch_h}
		RendererScript.panel(ci, float(r["x"]), float(r["y"]), float(r["w"]), float(r["h"]), {
			"fill": RendererScript.css_color("rgba(20,34,64,0.85)"),
			"stroke": RendererScript.css_color("rgba(120,180,255,0.3)"),
		})
		RendererScript.outlined_text(ci, "␣" if chars[gi] == " " else String(chars[gi]),
				float(r["x"]) + float(r["w"]) / 2.0, float(r["y"]) + float(r["h"]) / 2.0,
				{"size": 13.0, "fill": Color("#dff0ff")})
		picker_rects.append({"kind": "glyph", "ch": String(chars[gi]), "r": r})

	# backspace / cancel / accept
	var aby := gy + 5.0 * (ch_h + 6.0)
	var bw := floorf((w - 12.0) / 3.0)
	var defs := [
		{"kind": "backspace", "label": "⌫ %s" % _game.i18n.tr_key("Backspace"),
				"fill": "rgba(120,70,70,0.8)"},
		{"kind": "cancel", "label": _game.i18n.tr_key("Cancel"),
				"fill": "rgba(60,70,90,0.6)"},
		{"kind": "accept", "label": _game.i18n.tr_key("Accept"),
				"fill": "rgba(60,150,90,0.9)"},
	]
	for bi in defs.size():
		var d3: Dictionary = defs[bi]
		var br := {"x": x + float(bi) * (bw + 6.0), "y": aby, "w": bw, "h": 34.0}
		RendererScript.panel(ci, float(br["x"]), float(br["y"]), float(br["w"]), float(br["h"]), {
			"fill": RendererScript.css_color(String(d3["fill"])),
			"stroke": RendererScript.css_color("rgba(255,255,255,0.2)"),
		})
		RendererScript.outlined_text(ci, String(d3["label"]),
				float(br["x"]) + float(br["w"]) / 2.0, float(br["y"]) + 17.0,
				{"size": 12.0, "fill": Color("#fff")})
		picker_rects.append({"kind": String(d3["kind"]), "ch": "", "r": br})

	# helper line — the ruled cap + the suggestion affordance ("·" is
	# typography, the R2 chip precedent: it stays out of vi.csv)
	RendererScript.outlined_text(ci,
			"%s · %s" % [_game.i18n.tr_key("Max 14"), _game.i18n.tr_key("accept or edit")],
			x + w / 2.0, aby + 52.0,
			{"size": 10.0, "fill": RendererScript.css_color("rgba(150,190,235,0.55)")})


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
