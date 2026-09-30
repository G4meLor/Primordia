## Procedural creature renderer — port of Spore src/gfx/creature.ts drawCreature
## (frozen; task 6 part A). Pure function of (genome, pose, opts.t): spine,
## legs and tail ride the T1 rig (creature_rig.gd — spine_points/leg_draws/
## tail_points, IK never re-implemented here); everything else ports the TS
## statement order verbatim. Static; draws via RenderingServer RID calls on the
## caller CanvasItem's item — the CanvasItem.draw_* helpers are guarded to
## _draw() context, RID calls work both inside real _draw frames (creature
## stage, part B) and in immediate headless tests (test_creature_painter.gd).
##
## Transform model (cell_painter precedent): every section draws in command
## space composed as cam · T(pose.x, pose.y) · scale(facing, 1) · [dead rotate],
## cam = T(base_pos)·Z(base_zoom) carries the enclosing camera transform the
## stage drew with (defaults = standalone identity). The item's own transform
## must be identity at the draw site (stage nodes draw at identity, camera
## baked into commands).
##
## Clip mechanism (Ruling 11 — API corrected, verified empirically, see the
## task report): the clipped layer lives on a SUB-canvas-item (clip_item,
## parented to the caller's item, group mode CLIP_AND_DRAW). The silhouette
## shapes are drawn on it FIRST (union fill + per-disc outline strokes — that
## content IS the mask), the patterns after on its CHILD item (pattern_item):
## children of a group-clipped item render only within the owner's drawn
## shape, which is exactly TS ctx.clip(bodyPath). RULING CORRECTION: the
## ruling names RenderingServer.canvas_item_set_clip, but in 4.2 that call
## clips children to the item's AXIS-ALIGNED BOUNDING RECT
## (renderer_canvas_cull.cpp:275-287 — scissor, not shape); under it pattern
## pixels survive outside the silhouette (the belly ellipse passes ~5px past
## the body bottom). canvas_item_set_canvas_group_mode(CANVAS_GROUP_MODE_
## CLIP_AND_DRAW) is the shape-accurate mechanism (llvmpipe/GLES3 probe:
## set_clip leaks pattern pixels outside the body, the group mode does not).
## Degenerate rings (T8 review minor 3): Geometry2D.merge_polygons can emit
## zero-area rings (a disc fully containing another, two nearly-coincident
## discs) — add_polygon then warns "Invalid polygon data, triangulation
## failed" on them under llvmpipe. They carry no pixels; _disc_union drops
## them before any consumer (the editor-preview warning is gone with it).
##
## Back/front split (task 6 part B, pixel-probed): RS child items composite
## after ALL of the parent item's own commands, so the body-fill child would
## bury anything drawn directly on the caller item after it — the part B
## capture showed the eye pupil only as a sliver above the head-disc edge,
## with teeth/sclera/muzzle fully covered. TS order (far legs → tail → spikes
## → BODY → near legs → arms → head → horns → eyes) therefore maps onto three
## layers: back content straight on the caller item, the fill+patterns on
## clip_item, and everything TS draws after the body on front_item — a THIRD
## sub-item, sibling of clip_item parented AFTER it (children render in
## parenting order). Each front section re-issues add_set_transform(front, ·)
## with the same composed transforms as before.
##
## Recorded divergences (task 6 report):
##  - alpha < 1 (death fade / UI thumbnails): the group mask multiplies the
##    pattern alpha and composites it over the background, where TS composites
##    patterns at their own alpha over the faded body. Opaque bodies are exact.
##  - the mask includes the 1.6px outline stroke ring, so a pattern shape
##    overshooting the fill may tint the outline ring by up to ~0.8px (TS
##    clips patterns to the bare path).
##  - curve fidelity: canvas draws true arcs/quadratics; Godot draw commands
##    get sampled polygons/polylines (discs 24 segments, curves 16) and
##    strokes have no round caps/joins (cell_painter divergence precedent).
##  - RID LIFECYCLE: the three sub-items (clip, pattern, front) are
##    caller-owned — free all three (RenderingServer.free_rid) before the next
##    redraw of the same CanvasItem; the painter is stateless and creates fresh
##    ones per call. For correct overlap ordering between multiple creatures a
##    stage should give each creature its own CanvasItem child (RID children
##    render after ALL of the parent item's own commands).
##  - pattern rnd is the TS seeded hash (fract of sin(n·127.1 + seed)·
##    43758.5453, seed = |round(hue·13.7)|) — no randi/randf anywhere: a
##    species always looks like itself.
## Returns {clip_item: RID, pattern_item: RID, front_item: RID, spine: Array}
## — spine is the rig output the draw consumed (headless smoke asserts count 6
## + equality with creature_rig.spine_points; part B pixel-asserts reuse it).
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")
const RigScript := preload("res://src/gfx/creature_rig.gd")

# curve tessellation (canvas draws true curves; Godot commands take samples)
const CURVE_SEGS: int = 16
const DISC_SEGS: int = 24


static func draw_creature(ci: CanvasItem, g: Dictionary, pose: Dictionary, opts: Dictionary, base_pos := Vector2.ZERO, base_zoom := 1.0) -> Dictionary:
	var t := float(opts.get("t", 0.0))
	var alpha := float(opts.get("alpha", 1.0))
	var facing := float(pose.get("facing", 1))
	var size: float = float(g.get("size", 1.0)) * float(pose.get("scale", 1.0))
	var item: RID = ci.get_canvas_item()

	# ---- derived metrics (TS:54-62, shared rig copy) ---------------------------
	var m: Dictionary = RigScript._metrics(g, pose)
	var body_r: float = float(m["body_r"])
	var body_len: float = float(m["body_len"])
	var body_y: float = float(m["body_y"])
	var gait_speed: float = float(m["gait_speed"])

	# ---- palette (TS:64-70) ------------------------------------------------------
	var hue := float(g.get("hue", 120))
	var sat := float(g.get("sat", 0.55))
	var base := RendererScript.hsl(hue, sat, 0.52)
	var base_dark := RendererScript.hsl(hue, sat, 0.52 - 0.16)
	var belly := RendererScript.hsl(hue, sat * 0.62, 0.52 + 0.16)
	var limb := RendererScript.hsl(hue, sat, 0.52 - 0.1)
	var outline := RendererScript.hsl(hue, sat * 1.1, 0.22)

	# ---- frame: TS:72-75 translate(pose.x, pose.y); scale(facing, 1) --------------
	var cam: Transform2D = Transform2D(0.0, base_pos).scaled_local(Vector2(base_zoom, base_zoom))
	var xf: Transform2D = cam * Transform2D(0.0, Vector2(float(pose.get("x", 0.0)), float(pose.get("y", 0.0))))
	xf = xf * Transform2D(Vector2(facing, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)

	# ---- shadow (TS:77-86) — before the dead rotate --------------------------------
	if opts.get("shadow", true) != false:
		RenderingServer.canvas_item_add_set_transform(item, xf)
		var sa := 0.28 / (1.0 + float(pose.get("airborne", 0.0)) * 1.5)
		RenderingServer.canvas_item_add_polygon(item,
				RendererScript.ellipse_points(Vector2(0.0, 1.0), body_len * 0.55, body_r * 0.34, 0.0, DISC_SEGS),
				PackedColorArray([Color(0.0, 0.0, 0.0, sa * alpha)]))

	# ---- dead rotate (TS:88-91) ------------------------------------------------------
	if String(pose.get("mood", "idle")) == "dead":
		xf = xf * Transform2D(PI * 0.5 * 0.9, Vector2.ZERO)  # ctx.rotate(π/2·0.9)
		xf = xf * Transform2D(0.0, Vector2(0.0, -body_r * 0.6))  # ctx.translate(0, −0.6·bodyR)

	# ---- spine (TS:94-108) — the T1 rig ---------------------------------------------
	var spine: Array = RigScript.spine_points(g, pose, t)
	var head: Dictionary = spine[spine.size() - 1]

	# ---- wings (TS:110-134, behind body) ----------------------------------------------
	var wing_flap := sin(t * (6.0 + gait_speed * 8.0)) * (0.5 + gait_speed * 0.5)
	var wings := int(g.get("wings", 0))
	if wings > 0:
		for w in wings:
			var flap := wing_flap * (1.0 if w == 0 else -0.6)
			var s2: Dictionary = spine[2]
			var wing_len := body_r * 2.6
			var wing_h := body_r * 1.5
			# ctx.translate(wx, wy); ctx.rotate(-0.5 + flap·0.7) — T(pos)·R(rot)
			RenderingServer.canvas_item_add_set_transform(item,
					xf * Transform2D(-0.5 + flap * 0.7, Vector2(float(s2["x"]), float(s2["y"]) - float(s2["r"]) * 0.7)))
			var tip := Vector2(wing_len, -wing_h * 0.4 + flap * 4.0)
			var wing_loop := PackedVector2Array()  # moveTo(0,0) → quad1 → quad2 → back at 0,0
			wing_loop.append_array(_quad_points(Vector2.ZERO, Vector2(wing_len * 0.5, -wing_h), tip, CURVE_SEGS))
			wing_loop.append_array(_quad_points(tip, Vector2(wing_len * 0.55, wing_h * 0.3), Vector2.ZERO, CURVE_SEGS))
			RenderingServer.canvas_item_add_polygon(item, wing_loop,
					PackedColorArray([_fade(RendererScript.hsl(hue, sat * 0.8, 0.62, 0.85), alpha)]))
			RenderingServer.canvas_item_add_polyline(item, wing_loop, PackedColorArray([_fade(outline, alpha)]), 1.2, true)

	# ---- tail points (TS:137-150, the rig) + leg draws (TS:153-171, the rig) ---------
	var tail_pts: Array = RigScript.tail_points(g, pose, t)
	var leg_draws: Array = RigScript.leg_draws(g, pose, t)

	# drawLeg (TS:174-194): strokeStyle far ? baseDark : limb (round caps — divergence)
	var draw_leg := func(ld: Dictionary, far: bool, target: RID) -> void:
		var stroke := _fade(base_dark if far else limb, alpha)
		RenderingServer.canvas_item_add_set_transform(target, xf)
		RenderingServer.canvas_item_add_line(target, Vector2(ld["hx"], ld["hy"]), Vector2(ld["kx"], ld["ky"]), stroke, 4.4 * size, true)
		RenderingServer.canvas_item_add_line(target, Vector2(ld["kx"], ld["ky"]), Vector2(ld["fx"], ld["fy"]), stroke, 3.2 * size, true)
		RenderingServer.canvas_item_add_polygon(target,
				RendererScript.ellipse_points(Vector2(float(ld["fx"]), float(ld["fy"]) - 1.0), 2.6 * size, 1.6 * size, 0.0, 12),
				PackedColorArray([_fade(base_dark if far else outline, alpha)]))
	# far-side legs first (TS:195, every 2nd)
	for i in leg_draws.size():
		if i % 2 == 1:
			draw_leg.call(leg_draws[i], true, item)

	# ---- body silhouette discs (TS:198-210): SEG spine discs + head ×1.02 + tail -----
	var discs: Array = []
	for p in spine:
		discs.append({"c": Vector2(float(p["x"]), float(p["y"])), "r": float(p["r"])})
	discs.append({"c": Vector2(float(head["x"]), float(head["y"])), "r": float(head["r"]) * 1.02})
	for tp in tail_pts:
		discs.append({"c": Vector2(float(tp["x"]), float(tp["y"])), "r": float(tp["r"])})
	# ONE path in TS = the nonzero-union fill; chain-merged rings (the disc list
	# is a connected chain — spine → head/tail — so the union stays one ring)
	var union: Array = _disc_union(discs)

	# tail behind body fill (TS:212-226) — NOTE TS order: this lands AFTER the
	# far legs (TS:195) and BEFORE the spikes; the brief's bullet list swaps the
	# first two — ported TS-verbatim
	if tail_pts.size() > 0:
		RenderingServer.canvas_item_add_set_transform(item, xf)
		var tail_line := PackedVector2Array([Vector2(float(spine[0]["x"]), float(spine[0]["y"]))])
		for tp in tail_pts:
			tail_line.append(Vector2(float(tp["x"]), float(tp["y"])))
		RenderingServer.canvas_item_add_polyline(item, tail_line, PackedColorArray([_fade(base_dark, alpha)]), body_r * 0.7, true)
		RenderingServer.canvas_item_add_polyline(item, tail_line, PackedColorArray([_fade(base, alpha)]), body_r * 0.4, true)

	# ---- back spikes (TS:229-247, before body so they poke out) -----------------------
	var spikes := int(g.get("spikes", 0))
	if spikes > 0:
		RenderingServer.canvas_item_add_set_transform(item, xf)
		var n := mini(spikes, 7)
		for i in n:
			var p: Dictionary = spine[1 + (i % 4)]
			var side := floorf(float(i) / 4.0)  # TS Math.floor(i / 4)
			var sx: float = float(p["x"]) + side * 2.0 - 2.0
			var sy: float = float(p["y"]) - float(p["r"]) * 0.8
			var sl: float = (5.0 + float(i % 3) * 2.0) * size
			RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([
				Vector2(sx - 2.4 * size, sy + 1.0),
				Vector2(sx + 0.5 * size, sy - sl),
				Vector2(sx + 2.8 * size, sy + 1.0),
			]), PackedColorArray([_fade(outline, alpha)]))

	# ---- body fill + clipped layer (TS:250-342) — Ruling 11 sub-items -----------------
	var clip_item: RID = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(clip_item, item)
	RenderingServer.canvas_item_set_transform(clip_item, xf)
	RenderingServer.canvas_item_set_canvas_group_mode(clip_item, RenderingServer.CanvasGroupMode.CANVAS_GROUP_MODE_CLIP_AND_DRAW)
	# silhouette fill (mask + visible) — the union in ONE alpha blend (TS fills
	# the whole Path2D once; separate discs would double-blend at alpha < 1)
	for ring in union:
		RenderingServer.canvas_item_add_polygon(clip_item, ring, PackedColorArray([_fade(base, alpha)]))
	# per-disc outline strokes — TS strokes every subpath of bodyPath (seams and
	# all), lw 1.6
	for d in discs:
		RenderingServer.canvas_item_add_polyline(clip_item,
				_closed_loop(RendererScript.ellipse_points(d["c"], float(d["r"]), float(d["r"]), 0.0, DISC_SEGS)), PackedColorArray([_fade(outline, alpha)]), 1.6, true)
	var pattern_item: RID = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(pattern_item, clip_item)
	# NO set_transform here: RS child items compose parent·local — clip_item
	# already carries xf, so a second xf here would double-apply it (invisible
	# at the origin probe where xf·xf = S(f²,1) ≈ identity for facing 1; wrong
	# at every real creature position). Patterns draw in pose-local coords and
	# inherit the mask frame.
	# RenderingServer.canvas_item_set_transform(pattern_item, xf)
	# front layer (TS:345-496): sibling of clip_item, parented AFTER it so it
	# composites after the fill+patterns group — see the header's back/front
	# split note. Front sections re-issue add_set_transform(front_item, ·) with
	# the same composed transforms as their TS statements.
	var front_item: RID = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(front_item, item)

	# belly (TS:261-264)
	RenderingServer.canvas_item_add_polygon(pattern_item,
			RendererScript.ellipse_points(Vector2(0.0, body_y + body_r * 0.55), body_len * 0.42, body_r * 0.62, 0.0, DISC_SEGS),
			PackedColorArray([_fade(belly, alpha)]))

	# seeded pattern rnd (TS:266-270)
	var pat_seed := absf(roundf(hue * 13.7))
	var rnd := func(n: float) -> float:
		var x := sin(n * 127.1 + pat_seed) * 43758.5453
		return x - floorf(x)

	# patterns (TS:271-300)
	var pattern := String(g.get("pattern", "plain"))
	if pattern == "spots":
		var spots_col := _fade(RendererScript.hsl(hue, sat * 0.9, 0.52 - 0.22, 0.8), alpha)
		for i in 8:
			var px: float = (rnd.call(float(i)) - 0.5) * body_len * 0.9
			var py: float = body_y + (rnd.call(float(i) + 40.0) - 0.5) * body_r * 1.4
			RenderingServer.canvas_item_add_circle(pattern_item, Vector2(px, py),
					(1.6 + rnd.call(float(i) + 80.0) * 2.2) * size, spots_col)
	elif pattern == "stripes":
		var stripes_col := _fade(RendererScript.hsl(hue, sat * 0.9, 0.52 - 0.24, 0.75), alpha)
		for i in 5:
			var px2: float = (rnd.call(float(i)) - 0.5) * body_len
			RenderingServer.canvas_item_add_polygon(pattern_item,
					RendererScript.ellipse_points(Vector2(px2, body_y - body_r * 0.3), 2.2 * size, body_r * 0.75, 0.3 * facing, 12),
					PackedColorArray([stripes_col]))
	elif pattern == "glow":
		for i in 7:
			var px3: float = (rnd.call(float(i)) - 0.5) * body_len * 0.85
			var py3: float = body_y + (rnd.call(float(i) + 30.0) - 0.5) * body_r
			# createRadialGradient(px, py, 0 → 5·size), stop0 → 'transparent' — the
			# vertex-colored fan twin of renderer.gd's radial_disc (that one takes
			# a CanvasItem node; headless RID calls need this copy)
			var glow_col := _fade(RendererScript.hsl(fmod(hue + 160.0, 360.0), 1.0, 0.75, 0.9), alpha)
			_radial_disc(pattern_item, Vector2(px3, py3), 0.0, 5.0 * size, glow_col, Color(glow_col, 0.0))

	# coat textures (TS:302-334)
	var coat := String(g.get("coat", "skin"))
	if coat == "scales":
		var scales_col := _fade(RendererScript.hsl(hue, sat, 0.52 - 0.12, 0.5), alpha)
		for row in 3:
			for c in 9:
				var px4: float = (float(c) / 8.0 - 0.5) * body_len * 0.85 + float(row % 2) * 3.0
				var py4: float = body_y - body_r * 0.4 + float(row) * body_r * 0.5
				# ctx.arc(px, py, 2.1·size, π·0.15, π·0.85) stroke
				RenderingServer.canvas_item_add_polyline(pattern_item,
						_arc_points(px4, py4, 2.1 * size, PI * 0.15, PI * 0.85, 10),
						PackedColorArray([scales_col]), 1.0, true)
	elif coat == "plates":
		var plates_col := _fade(RendererScript.hsl(hue, sat * 0.6, 0.52 - 0.26, 0.9), alpha)
		for c2 in 5:
			var px5: float = (float(c2) / 4.0 - 0.5) * body_len * 0.7
			# ctx.ellipse(px, py, rx, ry, 0, π, 0) — anticlockwise=false sweeps
			# π→2π (the upper half in y-down); fill closes the diameter chord
			var rx5: float = body_len * 0.09
			var ry5: float = body_r * 0.34
			var py5: float = body_y - body_r * 0.42
			var half := PackedVector2Array()
			for k in 13:
				var a5: float = PI + (float(k) / 12.0) * PI
				half.append(Vector2(px5 + cos(a5) * rx5, py5 + sin(a5) * ry5))
			RenderingServer.canvas_item_add_polygon(pattern_item, half, PackedColorArray([plates_col]))
	elif coat == "fur":
		var fur_col := _fade(RendererScript.hsl(hue, sat, 0.52 + 0.1, 0.7), alpha)
		for c3 in 16:
			var px6: float = (rnd.call(float(c3)) - 0.5) * body_len
			var py6: float = body_y - body_r * 0.75 + (rnd.call(float(c3) + 7.0) - 0.5) * body_r * 0.5
			RenderingServer.canvas_item_add_line(pattern_item, Vector2(px6, py6), Vector2(px6 + 2.0, py6 - 3.0), fur_col, 1.0, true)

	# hurt flash (TS:337-340) — fills bodyPath inside the clip
	var hurt := float(pose.get("hurt", 0.0))
	if hurt > 0.0:
		for ring in union:
			RenderingServer.canvas_item_add_polygon(pattern_item, ring,
					PackedColorArray([Color(1.0, 1.0, 1.0, hurt * 0.75 * alpha)]))

	# near-side legs on top (TS:345, even i) — the first FRONT-layer content
	for j in leg_draws.size():
		if j % 2 == 0:
			draw_leg.call(leg_draws[j], false, front_item)

	# ---- arms (TS:347-370) — front layer -------------------------------------------------
	var arms := int(g.get("arms", 0))
	if arms > 0:
		RenderingServer.canvas_item_add_set_transform(front_item, xf)
		var sh: Dictionary = spine[maxi(1, RigScript.SEG - 3)]  # TS Math.max(1, SEG-3)
		var sh_x: float = float(sh["x"]) + float(sh["r"]) * 0.3
		var sh_y: float = float(sh["y"]) + float(sh["r"]) * 0.1
		var gait_phase: float = float(m["gait_phase"])
		for a in arms:
			var swing := sin(gait_phase + float(a) * 2.1) * 0.35 * (0.3 + gait_speed)
			var al := 9.0 * size
			var hx: float = sh_x + cos(0.9 + swing) * al
			var hy: float = sh_y + sin(0.9 + swing) * al
			RenderingServer.canvas_item_add_line(front_item, Vector2(sh_x, sh_y), Vector2(hx, hy), _fade(limb, alpha), 3.4 * size, true)
			RenderingServer.canvas_item_add_circle(front_item, Vector2(hx, hy), 1.8 * size, _fade(outline, alpha))

	# ---- head details (TS:372-425) — front layer ------------------------------------------
	var hr: float = float(head["r"])
	RenderingServer.canvas_item_add_set_transform(front_item, xf)
	# jaw / snout by diet (TS:375)
	var mouth_open: float = maxf(float(pose.get("attack", 0.0)),
			float(pose.get("eat", 0.0)) * (0.5 + 0.5 * absf(sin(t * 9.0))))
	var diet := String(g.get("diet", "omnivore"))
	if diet == "carnivore" or diet == "omnivore":
		var snout := hr * 0.85
		var ang := -0.15 + mouth_open * 0.5
		# ctx.translate(head.x + hr·0.35, head.y + hr·0.25); ctx.rotate(ang)
		RenderingServer.canvas_item_add_set_transform(front_item,
				xf * Transform2D(ang, Vector2(float(head["x"]) + hr * 0.35, float(head["y"]) + hr * 0.25)))
		# moveTo(0,0) → quad1 → (snout, 0) → quad2 → (0, snout·0.3) → close
		var snout_loop := PackedVector2Array()
		snout_loop.append_array(_quad_points(Vector2.ZERO, Vector2(snout, -snout * 0.28), Vector2(snout, 0.0), CURVE_SEGS))
		snout_loop.append_array(_quad_points(Vector2(snout, 0.0), Vector2(snout * 0.6, snout * 0.22), Vector2(0.0, snout * 0.3), CURVE_SEGS))
		snout_loop.append(Vector2.ZERO)  # closePath (stroked chord)
		RenderingServer.canvas_item_add_polygon(front_item, snout_loop, PackedColorArray([_fade(base, alpha)]))
		RenderingServer.canvas_item_add_polyline(front_item, snout_loop, PackedColorArray([_fade(outline, alpha)]), 1.4, true)
		# teeth (TS:393-405) — inside the rotated frame
		var jaw := int(g.get("jaw", 0))
		if jaw >= 1:
			var teeth := mini(4, 1 + jaw)
			for i in teeth:
				var tx := snout * (0.3 + float(i) * 0.2)
				RenderingServer.canvas_item_add_polygon(front_item, PackedVector2Array([
					Vector2(tx - 1.5, snout * 0.06),
					Vector2(tx, snout * 0.26),
					Vector2(tx + 1.5, snout * 0.06),
				]), PackedColorArray([_fade(Color("#f5f2e8"), alpha)]))
	else:
		# herbivore rounded muzzle (TS:407-425) — plain pose frame (TS restore)
		RenderingServer.canvas_item_add_set_transform(front_item, xf)
		var muz := Vector2(float(head["x"]) + hr * 0.8, float(head["y"]) + hr * 0.3)
		RenderingServer.canvas_item_add_polygon(front_item,
				RendererScript.ellipse_points(muz, hr * 0.5, hr * 0.34, 0.0, 16),
				PackedColorArray([_fade(belly, alpha)]))
		RenderingServer.canvas_item_add_polyline(front_item,
				_closed_loop(RendererScript.ellipse_points(muz, hr * 0.5, hr * 0.34, 0.0, 16)), PackedColorArray([_fade(outline, alpha)]), 1.2, true)
		if mouth_open > 0.05:
			RenderingServer.canvas_item_add_polyline(front_item,
					_arc_points(float(head["x"]) + hr * 0.8, float(head["y"]) + hr * 0.45, hr * 0.24, 0.2, PI - 0.2, 12), PackedColorArray([_fade(outline, alpha)]), 1.6, true)

	# ---- horns (TS:427-444) — front layer ---------------------------------------------------
	var horns := int(g.get("horns", 0))
	if horns > 0:
		RenderingServer.canvas_item_add_set_transform(front_item, xf)
		for i in horns:
			var side_h := 1.0 if i % 2 == 0 else -1.0
			var row := floorf(float(i) / 2.0)  # TS Math.floor(i / 2)
			var bx: float = float(head["x"]) - hr * 0.1 + row * 2.0
			var by: float = float(head["y"]) - hr * 0.75
			var hl: float = (6.0 + row * 1.5) * size
			var curve := side_h * (0.5 + row * 0.2)
			RenderingServer.canvas_item_add_polyline(front_item,
					_quad_points(Vector2(bx, by),
							Vector2(bx + curve * hl * 0.5, by - hl * 0.8),
							Vector2(bx + curve * hl, by - hl * 1.15), CURVE_SEGS), PackedColorArray([_fade(outline, alpha)]), 2.6 * size, true)

	# ---- eyes (TS:446-496) — front layer ------------------------------------------------------
	RenderingServer.canvas_item_add_set_transform(front_item, xf)  # carnivore branch leaves the snout frame
	var blink := 0.15 if sin(t * 1.3 + hue) > 0.97 else 1.0
	var look_dx := float(opts.get("lookDx", 0.0)) * facing
	var look_dy := float(opts.get("lookDy", 0.0))
	var eye_r := 3.4 * size
	var eyes := int(g.get("eyes", 1))
	var sclera_col := _fade(
			RendererScript.hsl(fmod(hue + 160.0, 360.0), 1.0, 0.85) if pattern == "glow" else Color("#f8f6ee"), alpha)
	for e in eyes:
		var ex: float
		var ey: float
		if e == 0:
			ex = float(head["x"]) + hr * 0.42
			ey = float(head["y"]) - hr * 0.28
		else:
			var col := int(floorf(float(e - 1) / 2.0))  # TS Math.floor((e-1)/2)
			var side_e := 1.0 if (e - 1) % 2 == 0 else -1.0
			ex = float(head["x"]) + hr * 0.1 - float(col) * hr * 0.5
			ey = float(head["y"]) - hr * (0.62 + side_e * 0.35) + float(col) * hr * 0.12
		# sclera
		RenderingServer.canvas_item_add_polygon(front_item,
				RendererScript.ellipse_points(Vector2(ex, ey), eye_r, eye_r * blink, 0.0, 16),
				PackedColorArray([sclera_col]))
		RenderingServer.canvas_item_add_polyline(front_item,
				_closed_loop(RendererScript.ellipse_points(Vector2(ex, ey), eye_r, eye_r * blink, 0.0, 16)), PackedColorArray([_fade(outline, alpha)]), 1.0, true)
		if blink > 0.5:
			# pupil looks at target (TS:471-473)
			var pdx: float = look_dx - (float(pose.get("x", 0.0)) + ex * facing)
			var pdy: float = look_dy - (float(pose.get("y", 0.0)) + ey)
			var pl := sqrt(pdx * pdx + pdy * pdy)
			if pl > 0.001:
				pdx /= pl
				pdy /= pl
			else:
				pdx = 1.0
				pdy = 0.0
			# mood affects pupil size (TS:475)
			var mood := String(pose.get("mood", "idle"))
			var pup := 0.7 if mood == "afraid" else (1.25 if mood == "angry" else 1.0)
			RenderingServer.canvas_item_add_circle(front_item,
					Vector2(ex + pdx * eye_r * 0.34, ey + pdy * eye_r * 0.3), eye_r * 0.46 * pup, _fade(Color("#131313"), alpha))
			# highlight
			RenderingServer.canvas_item_add_circle(front_item,
					Vector2(ex - eye_r * 0.2, ey - eye_r * 0.28), eye_r * 0.14, Color(1.0, 1.0, 1.0, 0.85 * alpha))
		# angry brow (TS:487-494)
		if String(pose.get("mood", "idle")) == "angry":
			RenderingServer.canvas_item_add_line(front_item,
					Vector2(ex - eye_r, ey - eye_r * 1.15), Vector2(ex + eye_r * 0.8, ey - eye_r * 0.6),
					_fade(outline, alpha), 1.6, true)

	# leave the transform in the caller's frame (TS restore, cell_painter semantic)
	RenderingServer.canvas_item_add_set_transform(item, cam)
	return {"clip_item": clip_item, "pattern_item": pattern_item, "front_item": front_item, "spine": spine}


# ---- private helpers -------------------------------------------------------------------

static func _fade(c: Color, alpha: float) -> Color:
	var out := c
	out.a = c.a * alpha
	return out


## Closed-loop polyline points (canvas full-ellipse/arc strokes close the loop).
static func _closed_loop(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out


## Quadratic bezier samples (de Casteljau) — the ctx.quadraticCurveTo twin.
static func _quad_points(p0: Vector2, p1: Vector2, p2: Vector2, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs + 1:
		var u := float(i) / float(segs)
		var q0 := (1.0 - u) * (1.0 - u)
		var q1 := 2.0 * (1.0 - u) * u
		var q2 := u * u
		pts.append(Vector2(
			q0 * p0.x + q1 * p1.x + q2 * p2.x,
			q0 * p0.y + q1 * p1.y + q2 * p2.y))
	return pts


## ctx.arc(x, y, r, a0, a1) stroke samples (canvas sweeps a0 → a1 increasing).
static func _arc_points(cx: float, cy: float, r: float, a0: float, a1: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs + 1:
		var a := a0 + (a1 - a0) * (float(i) / float(segs))
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return pts


## Union of overlapping discs as outer rings — TS fills the whole bodyPath once
## (nonzero rule); chained Geometry2D.merge_polygons keeps a single alpha blend
## at any global alpha. The disc chain (spine → head/tail) is connected, so the
## union stays one ring; the fold keeps general multi-ring inputs correct anyway.
## Zero-area merge output (header note, T8 review minor 3) is dropped before any
## add_polygon consumer sees it.
static func _disc_union(discs: Array) -> Array:
	var acc: Array = []
	for d in discs:
		var poly: PackedVector2Array = RendererScript.ellipse_points(d["c"], float(d["r"]), float(d["r"]), 0.0, DISC_SEGS)
		if acc.is_empty():
			acc = [poly]
			continue
		var next_acc: Array = []
		for ring in acc:
			next_acc.append_array(Geometry2D.merge_polygons(ring, poly))
		acc = next_acc
	var out: Array = []
	for ring in acc:
		if absf(_ring_area(ring)) > 0.0001:
			out.append(ring)
	return out


## Signed shoelace area of a ring (px²) — the degenerate filter only needs the
## near-zero test; a real body ring is ≥ ~100 px², slivers under 1e-4 are
## invisible and trip the triangulator.
static func _ring_area(ring: PackedVector2Array) -> float:
	var n := ring.size()
	if n < 3:
		return 0.0
	var a := 0.0
	for i in n:
		var p := ring[i]
		var q := ring[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Radial gradient disc (col0 at r0 → col1 at r1) on a bare RID — the twin of
## renderer.gd radial_disc (that one takes a CanvasItem node and is guarded to
## _draw context; the glow pattern needs RID calls). Vertex-colored ring fan +
## inner disc, the cell_painter gradient equivalence.
static func _radial_disc(item: RID, center: Vector2, r0: float, r1: float, col0: Color, col1: Color, segments := 24) -> void:
	if r1 <= r0:
		RenderingServer.canvas_item_add_circle(item, center, r1, col0)
		return
	RenderingServer.canvas_item_add_circle(item, center, r0, col0)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in segments:
		var a0 := (float(i) / float(segments)) * TAU
		var a1 := (float(i + 1) / float(segments)) * TAU
		pts.append(center + Vector2(cos(a0), sin(a0)) * r0)
		pts.append(center + Vector2(cos(a1), sin(a1)) * r0)
		pts.append(center + Vector2(cos(a1), sin(a1)) * r1)
		pts.append(center + Vector2(cos(a0), sin(a0)) * r1)
		cols.append(col0)
		cols.append(col0)
		cols.append(col1)
		cols.append(col1)
	RenderingServer.canvas_item_add_polygon(item, pts, cols)
