## R11 — the deterministic creature card renderer: one pure draw of a genome
## (+ meta name parts) into a caller CanvasItem rect. Shared by the pack
## portrait row (R9), the extinction/bestiary cards (R8) and the later genome
## showcase (R10) — the redesign's EX5 KEEP: 3 consumers, 1 code. Geometry
## rides the frozen creature_painter/creature_rig pair, so a card creature is
## the same pixels the stage would draw for that genome. Static-only, like
## Names/Genome/Parts.
##
## DETERMINISM: everything the card draws is a pure function of (genome, meta,
## rect). The creature pose is pinned neutral (speed 0, gait 0, mood idle,
## attack 0, t = CARD_T = 0.0 — no randi/randf anywhere, the painter's pattern
## rnd is the TS seeded hash), text sizes/colors are constants or
## genome-derived, and the portrait fit is analytic rig math. Same inputs →
## byte-identical output (sha256-proven in the scene test; the pure functions
## are pinned in test_creature_card.gd). Alpha stays 1 inside cards — the
## painter's <1 group-mask compositing diverges from TS (task 6 report).
##
## RID LIFECYCLE (task ruling — chosen pattern: DEFERRED per-item cleanup).
## draw_creature's three sub-items (clip/pattern/front) are caller-owned and
## must outlive the draw_into call for their content to reach a rendered
## frame — freeing them inside the call would erase the card before it draws.
## So the card keeps a static per-item registry: draw_into frees the PREVIOUS
## card's triple on the same item (draw N frees card N-1; steady state is one
## card = 3 live RIDs), and release(ci) frees the current triple.
## CONSUMER CONTRACT — two MUSTs: (1) RenderingServer.canvas_item_clear the
## item before each draw_into — draw_into frees the previous card's sub-RIDs
## but never wipes the item's OWN command buffer (the name/bars are commands
## ON the item, not sub-items): no clear = every old card's text/bars ghost
## under the new one and the command list grows each redraw. (2) release(ci)
## on the teardown of EVERY CanvasItem that drew a card — the _live registry
## holds its entry for the process's lifetime, so an item freed without
## release leaks its last triple (3 sub-RIDs) plus one stale entry per
## never-released item (the scene runs' exit "3 leaked" line is exactly one
## held entry). Leak proof: the 50× draw loop leaves the exit RID-warning
## count unchanged vs a single-card run (tools/test_card_scene.sh greps both
## runs' lines).
##
## TEXT PATH: CanvasItem.draw_* is guarded to the _draw context (probed on
## 4.2.2: "Drawing is only allowed inside NOTIFICATION_DRAW, _draw() function
## or 'draw' signal" — even in-tree, outside _draw), and RenderingServer has
## no text primitive. The card therefore draws text via Font.draw_string /
## draw_string_outline straight on the item RID — context-free exactly like
## the painter's RS calls: valid headless on a bare item, inside real _draw
## frames, and from _process phase machines alike.
##
## I18N: the epithet (and the stat-bar labels) are EN catalog strings — they
## resolve through TranslationServer.translate at composition time and the
## composed result is what meta_label returns (the QC r6 rule: translate the
## PART, then compose — a plain tr of the composed string could never resolve
## a key; cell_sim/banner sites made the same correction). TranslationServer
## is the static-context equivalent of Object.tr: I18n registers the vi
## Translation into it and Game boot applies the locale, so every live draw
## site resolves identically to i18n.tr_key. The species name is a procedural
## proper noun (the self_name/autoName precedent) and passes through
## untranslated. meta carries {species: String, epithet: String} — the name
## parts the sims generate at charm time via names.gd (names need an rng; the
## card displays, it does not invent). Unknown keys degrade to "".
extends RefCounted

const Painter := preload("res://src/gfx/creature_painter.gd")
const RigScript := preload("res://src/gfx/creature_rig.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const PartsScript := preload("res://src/evo/parts.gd")

# pinned time for the card creature (gait/sway/blink all read it; 0 = rest)
const CARD_T := 0.0
# portrait: left 60% of the card rect, full height
const PORTRAIT_FRAC := 0.6
# fit margin — 6% padding each side inside the portrait rect
const FIT_MARGIN := 0.88
# zoom clamps: never blow a small creature up past editor-preview scale, and
# never shrink a huge genome into an unreadable speck (a MIN_ZOOM clamp
# deliberately overflows a pathologically small rect)
const MIN_ZOOM := 0.1
const MAX_ZOOM := 2.0

# deferred RID registry — item RID → that item's current card's 3 sub-RIDs
static var _live: Dictionary = {}


## The card's 3 stat bars (task ruling: size / legs / brain) as pure data:
## [{key, label, frac}] — label is the EN key the editor already ships
## (vi.csv: BODY SIZE / Leg / Brain), translated at draw. size normalizes
## over GENE_BOUNDS (the editor's level math: (size − min) / span), legs and
## brain over the parts-catalog buy maxes; values clamp to [0, 1] (the
## mutation caps can exceed the buy maxes).
static func stat_bars(g: Dictionary) -> Array:
	var b: Dictionary = GenomeScript.GENE_BOUNDS["size"]
	var smin: float = float(b["min"])
	var smax: float = float(b["max"])
	var legs_max: float = float(PartsScript.part_by_id("legs")["max"])
	var brain_max: float = float(PartsScript.part_by_id("brain")["max"])
	return [
		{"key": "size", "label": "BODY SIZE",
			"frac": clampf((float(g.get("size", 1.0)) - smin) / (smax - smin), 0.0, 1.0)},
		{"key": "legs", "label": "Leg",
			"frac": clampf(float(g.get("legs", 0)) / legs_max, 0.0, 1.0)},
		{"key": "brain", "label": "Brain",
			"frac": clampf(float(g.get("brain", 0)) / brain_max, 0.0, 1.0)},
	]


## The single-string meta label: species + epithet, the epithet translated
## BEFORE the composition returns (see the I18N header note). Empty parts
## degrade gracefully; species-only and epithet-only metas are legal.
static func meta_label(meta: Dictionary) -> String:
	var species := String(meta.get("species", ""))
	var ep := String(meta.get("epithet", ""))
	if ep.is_empty():
		return species
	var ep_tx := String(TranslationServer.translate(ep))
	if species.is_empty():
		return ep_tx  # epithet-only meta — no dangling separator space
	return "%s %s" % [species, ep_tx]


## Draw one card: creature portrait (left 60%), name + epithet (top of the
## right column), 3 stat bars (bottom of the right column). Context-free —
## see the TEXT PATH header note. RID lifecycle: frees the previous card's
## sub-RIDs on this item, registers its own triple; release(ci) tears it
## down. The consumer MUST canvas_item_clear the item first (header RID
## LIFECYCLE MUST 1) — the card's text/bars are commands on the caller item
## and only that clear removes them.
static func draw_into(ci: CanvasItem, genome: Dictionary, meta: Dictionary, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var item: RID = ci.get_canvas_item()
	release(ci)
	# identity transform: the painter leaves its cam transform on the caller
	# item (restore semantics) — the card's own geometry is in rect space
	RenderingServer.canvas_item_add_set_transform(item, Transform2D())
	var pad := 6.0
	var portrait_w: float = rect.size.x * PORTRAIT_FRAC
	var col_x: float = rect.position.x + portrait_w + pad
	var col_w: float = rect.size.x - portrait_w - pad * 2.0
	if col_w > 12.0:
		_draw_names(item, meta, col_x, col_w, rect.position.y + pad + 8.0)
		_draw_bars(item, genome, col_x, col_w, rect.position.y + rect.size.y - pad)
	if portrait_w > 12.0:
		var fit: Dictionary = _portrait_fit(genome, rect)
		var res: Dictionary = Painter.draw_creature(ci, genome, _card_pose(),
				{"t": CARD_T}, fit["pos"], fit["zoom"])
		_live[item] = [res["clip_item"], res["pattern_item"], res["front_item"]]


## Teardown contract: free the current card's 3 sub-RIDs on this item. Every
## consumer calls this when the card leaves the screen (stage/menu teardown)
## or before the item dies without a later redraw.
static func release(ci: CanvasItem) -> void:
	var key: RID = ci.get_canvas_item()
	if not _live.has(key):
		return
	for rid in _live[key]:
		RenderingServer.free_rid(rid)
	_live.erase(key)


# ---- private helpers -------------------------------------------------------------------

## Test seam: the live sub-RIDs registered for this item (empty when none).
static func _rids_for(ci: CanvasItem) -> Array:
	return (_live.get(ci.get_canvas_item(), []) as Array).duplicate()


## The pinned neutral card pose — fresh Dictionary per call (the rig reads it,
## and spine_points mutates its own output, not the pose; a shared const dict
## would be one refactor away from cross-call contamination).
static func _card_pose() -> Dictionary:
	return {
		"x": 0.0, "y": 0.0, "facing": 1, "speed": 0.0, "gaitPhase": 0.0,
		"attack": 0.0, "hurt": 0.0, "eat": 0.0, "airborne": 0.0,
		"mood": "idle", "scale": 1.0,
	}


## Analytic portrait fit: bound the creature's painted extent at the pinned
## pose/t from the SAME rig outputs the painter consumes, then place its bbox
## center at the portrait center at a uniform zoom that fits. Pure → the
## scene test's byte-identical hash covers the whole draw.
##
## Bounds sources (local units): spine/head/tail discs and leg points are the
## rig's exact outputs (+ stroke/foot margins); wings/horns are the quad
## control points (a quadratic stays inside its control hull; + stroke
## margin); spikes are their triangle corners; the snout/muzzle and shadow
## are their axis extremes; eyes/sclera/pupil live inside the head disc
## (fixed gene ratios: eye_r 3.4·size < the 13·size head radius) so the head
## disc carries a +4·size expansion for them plus the outline stroke.
static func _portrait_fit(genome: Dictionary, rect: Rect2) -> Dictionary:
	var pose := _card_pose()
	var m: Dictionary = RigScript._metrics(genome, pose)
	var size: float = float(m["size"])
	var body_r: float = float(m["body_r"])
	var body_len: float = float(m["body_len"])

	var discs: Array = []  # {c: Vector2, r: float} — exact painted discs
	var pts: Array = []    # [Vector2, margin] — significant points + per-point margin
	var spine: Array = RigScript.spine_points(genome, pose, CARD_T)
	for i in spine.size():
		var p: Dictionary = spine[i]
		var r: float = float(p["r"])
		if i == spine.size() - 1:
			r = r * 1.02 + 4.0 * size  # head: ×1.02 fill + eyes/blink/stroke margin
		discs.append({"c": Vector2(float(p["x"]), float(p["y"])), "r": r})
	for tp in RigScript.tail_points(genome, pose, CARD_T):
		discs.append({"c": Vector2(float(tp["x"]), float(tp["y"])), "r": float(tp["r"])})
	for ld in RigScript.leg_draws(genome, pose, CARD_T):
		var margin := 5.0 * size  # leg stroke half-width 2.2·size + foot disc 2.6·size
		pts.append([Vector2(float(ld["hx"]), float(ld["hy"])), margin])
		pts.append([Vector2(float(ld["kx"]), float(ld["ky"])), margin])
		pts.append([Vector2(float(ld["fx"]), float(ld["fy"])), margin])

	# shadow ellipse (painter default): axis extremes around (0, 1)
	pts.append([Vector2(-body_len * 0.55, 1.0), 0.0])
	pts.append([Vector2(body_len * 0.55, 1.0), 0.0])
	pts.append([Vector2(0.0, 1.0 - body_r * 0.34), 0.0])
	pts.append([Vector2(0.0, 1.0 + body_r * 0.34), 0.0])

	# wings: rotated frame at spine[2] — flap = sin(t·(6+gait·8))·(0.5+gait·0.5)
	# is 0 at CARD_T 0 + speed 0; the two quads stay inside their control hull
	var wings := int(genome.get("wings", 0))
	if wings > 0:
		var s2: Dictionary = spine[2]
		var anchor := Vector2(float(s2["x"]), float(s2["y"]) - float(s2["r"]) * 0.7)
		var rot := -0.5
		var wing_len: float = body_r * 2.6
		var wing_h: float = body_r * 1.5
		for lp in [Vector2(0.0, 0.0), Vector2(wing_len * 0.5, -wing_h),
				Vector2(wing_len, -wing_h * 0.4), Vector2(wing_len * 0.55, wing_h * 0.3)]:
			pts.append([anchor + Vector2(cos(rot) * lp.x - sin(rot) * lp.y,
					sin(rot) * lp.x + cos(rot) * lp.y), 2.0 * size])

	# back spikes: triangle corners at spine[1 + i%4] (painter math verbatim)
	var spikes := int(genome.get("spikes", 0))
	if spikes > 0:
		var n := mini(spikes, 7)
		for i in n:
			var p: Dictionary = spine[1 + (i % 4)]
			var side := floorf(float(i) / 4.0)
			var sx: float = float(p["x"]) + side * 2.0 - 2.0
			var sy: float = float(p["y"]) - float(p["r"]) * 0.8
			var sl: float = (5.0 + float(i % 3) * 2.0) * size
			pts.append([Vector2(sx - 2.4 * size, sy + 1.0), 1.0])
			pts.append([Vector2(sx + 0.5 * size, sy - sl), 1.0])
			pts.append([Vector2(sx + 2.8 * size, sy + 1.0), 1.0])

	# head extras: horns (quad control hull), snout/muzzle axis extremes
	var head: Dictionary = spine[spine.size() - 1]
	var hr: float = float(head["r"])
	var horns := int(genome.get("horns", 0))
	if horns > 0:
		for i in horns:
			var side_h := 1.0 if i % 2 == 0 else -1.0
			var row := floorf(float(i) / 2.0)
			var bx: float = float(head["x"]) - hr * 0.1 + row * 2.0
			var by: float = float(head["y"]) - hr * 0.75
			var hl: float = (6.0 + row * 1.5) * size
			var curve := side_h * (0.5 + row * 0.2)
			pts.append([Vector2(bx, by), 2.0 * size])
			pts.append([Vector2(bx + curve * hl * 0.5, by - hl * 0.8), 2.0 * size])
			pts.append([Vector2(bx + curve * hl, by - hl * 1.15), 2.0 * size])
	var diet := String(genome.get("diet", "omnivore"))
	if diet == "carnivore" or diet == "omnivore":
		var snout: float = hr * 0.85
		# rotated (−0.15) snout frame at head + (hr·0.35, hr·0.25): the frame
		# origin + the far tip bound the loop (teeth live inside it)
		var f := Vector2(float(head["x"]) + hr * 0.35, float(head["y"]) + hr * 0.25)
		pts.append([f, 1.5])
		pts.append([f + Vector2(cos(-0.15) * snout, sin(-0.15) * snout), 1.5])
	else:
		var muz := Vector2(float(head["x"]) + hr * 0.8, float(head["y"]) + hr * 0.3)
		pts.append([muz + Vector2(-hr * 0.5, -hr * 0.34), 1.0])
		pts.append([muz + Vector2(hr * 0.5, hr * 0.34), 1.0])

	# fold the bounds
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for d in discs:
		var c: Vector2 = d["c"]
		var r: float = d["r"]
		lo = Vector2(minf(lo.x, c.x - r), minf(lo.y, c.y - r))
		hi = Vector2(maxf(hi.x, c.x + r), maxf(hi.y, c.y + r))
	for pt in pts:
		var q: Vector2 = pt[0]
		var mg: float = pt[1]
		lo = Vector2(minf(lo.x, q.x - mg), minf(lo.y, q.y - mg))
		hi = Vector2(maxf(hi.x, q.x + mg), maxf(hi.y, q.y + mg))
	var bbox := Rect2(lo - Vector2(3.0, 3.0), hi - lo + Vector2(6.0, 6.0))

	var pw: float = rect.size.x * PORTRAIT_FRAC
	var zoom := clampf(minf(pw * FIT_MARGIN / maxf(bbox.size.x, 0.001),
			rect.size.y * FIT_MARGIN / maxf(bbox.size.y, 0.001)), MIN_ZOOM, MAX_ZOOM)
	var center: Vector2 = bbox.position + bbox.size * 0.5
	var portrait_center := rect.position + Vector2(pw * 0.5, rect.size.y * 0.5)
	return {"pos": portrait_center - center * zoom, "zoom": zoom, "bbox": bbox}


## Name + epithet, top of the right column (column-centered, shrink-to-fit).
static func _draw_names(item: RID, meta: Dictionary, col_x: float, col_w: float, y: float) -> void:
	var species := String(meta.get("species", ""))
	var ep := String(meta.get("epithet", ""))
	if not species.is_empty():
		_outlined_text(item, species, col_x + col_w * 0.5, y, 13.0, col_w,
				Color("#eaf2ff"), RendererScript._bold_font(), "center")
	if not ep.is_empty():
		_outlined_text(item, TranslationServer.translate(ep), col_x + col_w * 0.5,
				y + 14.0, 10.0, col_w, Color(0.72, 0.82, 1.0, 0.9), ThemeDB.fallback_font, "center")


## 3 stat bars, bottom of the right column: label line over a full-width
## track, genome-hue fill. Rows stack upward from the card bottom.
static func _draw_bars(item: RID, genome: Dictionary, col_x: float, col_w: float, bottom_y: float) -> void:
	var bars: Array = stat_bars(genome)
	var row_h := 20.0
	var hue := float(genome.get("hue", 120.0))
	var fill := RendererScript.hsl(hue, 0.55, 0.52)
	for i in bars.size():
		var y_top: float = bottom_y - float(bars.size() - i) * row_h
		_outlined_text(item, TranslationServer.translate(String(bars[i]["label"])),
				col_x, y_top + 5.0, 8.0, col_w, Color(0.72, 0.82, 1.0, 0.9),
				ThemeDB.fallback_font, "left")
		var track_cy: float = y_top + 14.0
		RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([
			Vector2(col_x, track_cy - 2.5), Vector2(col_x + col_w, track_cy - 2.5),
			Vector2(col_x + col_w, track_cy + 2.5), Vector2(col_x, track_cy + 2.5)]),
			PackedColorArray([Color(1.0, 1.0, 1.0, 0.14)]))
		var fw: float = maxf(0.0, col_w * float(bars[i]["frac"]))
		if fw > 0.5:
			RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([
				Vector2(col_x, track_cy - 2.5), Vector2(col_x + fw, track_cy - 2.5),
				Vector2(col_x + fw, track_cy + 2.5), Vector2(col_x, track_cy + 2.5)]),
				PackedColorArray([fill]))


## RID twin of RendererScript.outlined_text's essentials (the shared file is
## outside this task's touch set): shrink-to-fit, textBaseline-middle
## semantics (pos.y = y + (asc − desc)/2), 2px outline + fill. RID-level so
## it works outside _draw like every other card command.
static func _outlined_text(item: RID, text: String, x: float, y: float, size_px: float,
		max_w: float, fill: Color, font: Font, align := "center") -> void:
	var s := size_px
	if max_w > 0.0:
		# the font must RE-MEASURE each iteration (outlined_text comment verbatim)
		while s > 8.0:
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
					int(maxf(1.0, roundf(s)))).x
			if w <= max_w:
				break
			s -= 0.5
	var draw_size := int(maxf(1.0, roundf(s)))
	var asc := font.get_ascent(draw_size)
	var desc := font.get_descent(draw_size)
	var pos := Vector2(x, y + (asc - desc) * 0.5)
	if align == "center":
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, draw_size).x
		pos.x = x - tw * 0.5
	font.draw_string_outline(item, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, draw_size,
			int(maxf(2.0, s / 6.0)), Color(0.0, 0.0, 0.0, 0.75))
	font.draw_string(item, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, draw_size, fill)
