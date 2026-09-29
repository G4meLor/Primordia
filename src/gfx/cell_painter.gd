## Procedural cell renderer — port of Spore src/gfx/cell.ts drawCell (frozen);
## every visual constant read off the TS file. Pure function of
## (genome, pose, t). Static; draws on a caller CanvasItem.
##
## Transform model: TS wraps sections in canvas save/translate/rotate/scale.
## Godot's draw_set_transform is T·R·S only, so the painter re-bases each
## section explicitly: pose-space sections use draw_set_transform(base_pos +
## base_zoom*(x,y), rotation, base_zoom*scale) and world-space sections use
## (base_pos, 0, base_zoom·one) — base_pos/base_zoom carry the enclosing
## camera transform the stage drew with (defaults = standalone identity).
##
## Recorded divergences (task 7 report):
##  - membrane radial gradient → vertex-colored fan over the 26-step wobble
##    rim + center vertex (Gouraud ≈ the canvas gradient; the fan CENTER
##    vertex is exact, which is what the pixel assert samples).
##  - the TS hurt-flash circle (R*1.2) is clipped to the membrane; the wobble
##    path refill covers the identical visible region (R*1.2 > max rim).
##  - flagella/cilia line caps: Godot draw_polyline/draw_line have no round
##    caps — 2px strokes, imperceptible at presence level.
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")


## TS CellPose: x, y, moveAngle, speed, scale, hurt, eat, dash, seed, stun.
## TS CellLookOpts: t, proboscisTarget ({x,y} or null), alpha.
static func draw_cell(ci: CanvasItem, g: Dictionary, pose: Dictionary, opts: Dictionary, base_pos := Vector2.ZERO, base_zoom := 1.0) -> void:
	var t := float(opts.get("t", 0.0))
	var alpha := float(opts.get("alpha", 1.0))
	var px := float(pose.get("x", 0.0))
	var py := float(pose.get("y", 0.0))
	var R := 14.0 * float(pose.get("scale", 1.0))
	var seed := float(pose.get("seed", 0.0))
	var w1 := sin(seed * 1.7)
	var w2 := sin(seed * 3.3)
	var hue := float(g.get("hue", 120))
	var sat := float(g.get("sat", 0.55))

	var base := RendererScript.hsl(hue, sat, 0.5)
	var inner := RendererScript.hsl(hue, sat * 0.8, 0.36)
	var edge := RendererScript.hsl(hue, sat, 0.72)
	var outline := RendererScript.hsl(hue, sat, 0.2)

	_set_world(ci, base_pos, base_zoom)

	# toxin aura (cell.ts:40-49)
	var toxin := float(g.get("toxin", 0.0))
	if toxin > 0.0:
		var ar := R * (1.7 + toxin * 0.12 + sin(t * 2.0) * 0.05)
		RendererScript.radial_disc(ci, Vector2(px, py), R * 0.8, ar,
				_fade(RendererScript.hsl(110.0, 0.9, 0.5, 0.22 + toxin * 0.04), alpha),
				_fade(Color(RendererScript.hsl(110.0, 0.9, 0.5, 0.22 + toxin * 0.04), 0.0), alpha))

	# glow pattern aura (cell.ts:52-60)
	if String(g.get("pattern", "plain")) == "glow":
		var aura := RendererScript.hsl(fmod(hue + 160.0, 360.0), 1.0, 0.7, 0.25)
		RendererScript.radial_disc(ci, Vector2(px, py), R * 0.5, R * 2.0,
				_fade(aura, alpha), _fade(Color(aura, 0.0), alpha))

	# ---- flagella (behind) (cell.ts:63-87) -------------------------------------
	var n_flag := int(g.get("flagella", 0))
	for f in n_flag:
		var spread := 0.0 if n_flag == 1 else (float(f) / float(n_flag - 1) - 0.5) * 1.2
		var anchor_ang := PI + spread
		var ax := px + cos(anchor_ang) * R * 0.92
		var ay := py + sin(anchor_ang) * R * 0.92
		var flen := R * (1.15 + fmod(0.12 * float(f), 0.4))
		var pts := PackedVector2Array([Vector2(ax, ay)])
		var steps := 7
		for i in range(1, steps + 1):
			var u := float(i) / float(steps)
			var wave := sin(t * 9.0 - u * 5.0 + float(f) * 1.4 + seed) * 0.5 * u
			var ang := anchor_ang + wave + spread * 0.4
			pts.append(Vector2(ax + cos(ang) * flen * u, ay + sin(ang) * flen * u))
		ci.draw_polyline(pts, _fade(edge, alpha), 2.1, true)

	# ---- cilia (cell.ts:90-106) -------------------------------------------------
	var cilia := int(g.get("cilia", 0))
	if cilia > 0:
		var n := 8 + cilia * 4
		for i in n:
			var a := (float(i) / float(n)) * TAU + t * 2.0
			var bx := px + cos(a) * R
			var by := py + sin(a) * R
			var l := 3.0 + absf(sin(t * 10.0 + float(i) * 2.0)) * 2.4
			ci.draw_line(Vector2(bx, by), Vector2(bx + cos(a) * l, by + sin(a) * l), _fade(edge, alpha), 1.1, true)

	# ---- spikes (cell.ts:109-126) ------------------------------------------------
	var spikes := int(g.get("spikes", 0))
	if spikes > 0:
		var n_sp := mini(spikes, 10)
		for i in n_sp:
			var a_s := (float(i) / float(n_sp)) * TAU + seed
			var sl := (5.0 + float(i % 3)) * float(pose.get("scale", 1.0))
			var bx_s := px + cos(a_s) * R * 0.92
			var by_s := py + sin(a_s) * R * 0.92
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(bx_s + cos(a_s + 1.7) * 2.4, by_s + sin(a_s + 1.7) * 2.4),
				Vector2(bx_s + cos(a_s) * (R * 0.92 + sl), by_s + sin(a_s) * (R * 0.92 + sl)),
				Vector2(bx_s + cos(a_s - 1.7) * 2.4, by_s + sin(a_s - 1.7) * 2.4),
			]), _fade(outline, alpha))

	# ---- membrane (cell.ts:129-188) ------------------------------------------------
	# TS: save → translate(x,y) → rotate(moveAngle) → scale(stretch, 1/stretch*1.06)
	var stretch := 1.0 + float(pose.get("speed", 0.0)) * 0.14 + float(pose.get("dash", 0.0)) * 0.12
	var move_angle := float(pose.get("moveAngle", 0.0))
	var mp := base_pos + base_zoom * Vector2(px, py)
	ci.draw_set_transform(mp, move_angle, Vector2(base_zoom * stretch, base_zoom * (1.0 / stretch * 1.06)))

	# the radial gradient (-R*0.25,-R*0.25, R*0.1 → 0,0, R*1.05; edge → base@0.35
	# → inner) becomes a vertex-colored fan over the wobble rim + center vertex
	var grad_c := Vector2(-R * 0.25, -R * 0.25)
	var r0 := R * 0.1
	var r1 := R * 1.05
	var steps_m := 26
	var rim := PackedVector2Array()
	var rim_col := PackedColorArray()
	for i in steps_m + 1:
		var a_m := (float(i) / float(steps_m)) * TAU
		var wob := 1.0 \
				+ 0.06 * sin(a_m * 3.0 + t * 2.4 + w1) \
				+ 0.045 * sin(a_m * 5.0 - t * 1.7 + w2) \
				+ 0.03 * sin(a_m * 8.0 + t * 3.1)
		var pv := Vector2(cos(a_m), sin(a_m)) * R * wob
		rim.append(pv)
		rim_col.append(_membrane_color(pv, grad_c, r0, r1, edge, base, inner))
	var center_col := _fade(_membrane_color(Vector2.ZERO, grad_c, r0, r1, edge, base, inner), alpha)
	for i in steps_m:
		ci.draw_primitive(
				PackedVector2Array([Vector2.ZERO, rim[i], rim[i + 1]]),
				PackedColorArray([center_col, _fade(rim_col[i], alpha), _fade(rim_col[i + 1], alpha)]),
				PackedVector2Array())
	# outline stroke over the same wobble path (lineWidth 1.6)
	var loop := PackedVector2Array(rim)
	loop.append(rim[0])
	ci.draw_polyline(loop, _fade(outline, alpha), 1.6, true)

	# ---- organelles (clipped inside in TS — extents stay under the rim) -----------
	var nuc_c := Vector2(
		-R * 0.16 + sin(t * 0.8 + w1) * R * 0.06,
		R * 0.1 + cos(t * 0.7 + w2) * R * 0.06)
	ci.draw_circle(nuc_c, R * 0.3, _fade(RendererScript.hsl(hue, sat * 0.7, 0.28, 0.9), alpha))
	ci.draw_circle(nuc_c + Vector2(-R * 0.06, -R * 0.05), R * 0.12,
			_fade(RendererScript.hsl(hue, sat * 0.5, 0.18, 0.9), alpha))
	for i in 5:
		var a_o := seed + float(i) * 2.4
		var rr_o := R * (0.35 + 0.4 * ((sin(seed * 7.0 + float(i) * 3.0) + 1.0) / 2.0))
		var op := Vector2(cos(a_o + t * 0.3) * rr_o, sin(a_o * 1.3 + t * 0.24) * rr_o)
		ci.draw_colored_polygon(
				RendererScript.ellipse_points(op, R * 0.1, R * 0.07, a_o),
				_fade(RendererScript.hsl(fmod(hue + 40.0 * float(i), 360.0), 0.6, 0.65, 0.5), alpha))
	var hurt := float(pose.get("hurt", 0.0))
	if hurt > 0.0:
		# TS: clipped white circle R*1.2 — the wobble fill covers the same
		# region (R*1.2 exceeds the max rim radius 1.135R)
		var rim_closed := PackedVector2Array()
		rim_closed.resize(steps_m)
		for i in steps_m:
			rim_closed[i] = rim[i]
		ci.draw_colored_polygon(rim_closed, Color(1.0, 1.0, 1.0, hurt * 0.8 * alpha))

	# ---- mouth (cell.ts:191-215) -----------------------------------------------------
	var jaw := int(g.get("jaw", 0))
	if jaw > 0 or String(g.get("diet", "omnivore")) == "herbivore":
		var open := float(pose.get("eat", 0.0)) * 0.8
		if open > 0.04:
			# pie wedge: moveTo(R*0.2, 0) → arc(0,0,R*0.62, -0.5open, 0.5open) → close
			var wedge := PackedVector2Array([Vector2(R * 0.2, 0.0)])
			var segs_w := 12
			for i in segs_w + 1:
				var a_w := -0.5 * open + (float(i) / float(segs_w)) * open
				wedge.append(Vector2(cos(a_w) * R * 0.62, sin(a_w) * R * 0.62))
			ci.draw_colored_polygon(wedge, _fade(RendererScript.hsl(350.0, 0.6, 0.3, 0.95), alpha))
			if jaw >= 2:
				var teeth := mini(5, jaw + 1)
				for i in teeth:
					var a_t := -0.45 * open + (float(i) / float(teeth - 1)) * 0.9 * open
					var bx_t := cos(a_t) * R * 0.6
					var by_t := sin(a_t) * R * 0.6
					ci.draw_colored_polygon(PackedVector2Array([
						Vector2(bx_t, by_t),
						Vector2(cos(a_t) * R * 0.42, sin(a_t) * R * 0.42),
						Vector2(bx_t - sin(a_t) * 2.0, by_t + cos(a_t) * 2.0),
					]), _fade(Color("#f5f2e8"), alpha))

	# eyes (cell.ts:218-233) — previews creature heritage
	var eyes := int(g.get("eyes", 1))
	var eye_r := maxf(2.2, R * 0.16)
	for e in mini(eyes, 4):
		var a_e := -0.5 + float(e) * 0.35 - (float(mini(eyes, 4)) - 1.0) * 0.17
		var ex := cos(a_e) * R * 0.62
		var ey := sin(a_e) * R * 0.62
		ci.draw_circle(Vector2(ex, ey), eye_r, _fade(Color("#f8f6ee"), alpha))
		ci.draw_arc(Vector2(ex, ey), eye_r, 0.0, TAU, 16, _fade(outline, alpha), 0.8)
		ci.draw_circle(Vector2(ex + eye_r * 0.3, ey), eye_r * 0.5, _fade(Color("#131313"), alpha))

	# back to world space (TS membrane save restore, cell.ts:235)
	_set_world(ci, base_pos, base_zoom)

	# ---- proboscis (cell.ts:238-256) ---------------------------------------------------
	var proboscis := int(g.get("proboscis", 0))
	var target: Variant = opts.get("proboscisTarget")
	if proboscis > 0 and target != null:
		var tx := float(target["x"])
		var ty := float(target["y"])
		var ang_p := atan2(ty - py, tx - px)
		var len_p := R * 1.5
		var mx_p := px + cos(ang_p) * R * 0.8
		var my_p := py + sin(ang_p) * R * 0.8
		var cx_p := mx_p + cos(ang_p) * len_p * 0.5
		var cy_p := my_p + sin(ang_p) * len_p * 0.5 - 4.0
		var curve := PackedVector2Array()
		var segs_p := 16
		for i in segs_p + 1:
			var u_p := float(i) / float(segs_p)
			var q0 := (1.0 - u_p) * (1.0 - u_p)
			var q1 := 2.0 * (1.0 - u_p) * u_p
			var q2 := u_p * u_p
			curve.append(Vector2(
				q0 * mx_p + q1 * cx_p + q2 * tx,
				q0 * my_p + q1 * cy_p + q2 * ty))
		ci.draw_polyline(curve, _fade(edge, alpha), 3.4, true)

	# ---- electro sparks (cell.ts:259-281) ------------------------------------------------
	var electro := int(g.get("electro", 0))
	if electro > 0:
		var phase := fmod(t * 0.9 + seed, 1.0)
		if phase < 0.22:
			var bolts := 2 + electro
			for b in bolts:
				var a_el := (float(b) / float(bolts)) * TAU + t * 6.0
				var cx_e := px + cos(a_el) * R * 0.9
				var cy_e := py + sin(a_el) * R * 0.9
				var pts_e := PackedVector2Array([Vector2(cx_e, cy_e)])
				for s in 3:
					cx_e += cos(a_el) * 4.0 + sin(t * 40.0 + float(s) + float(b)) * 5.0
					cy_e += sin(a_el) * 4.0 + cos(t * 37.0 + float(s)) * 5.0
					pts_e.append(Vector2(cx_e, cy_e))
				ci.draw_polyline(pts_e, _fade(RendererScript.hsl(200.0, 1.0, 0.75, 0.8), alpha), 1.4, true)

	# ---- stun arcs (cell.ts:283-296) ------------------------------------------------------
	var stun := float(pose.get("stun", 0.0))
	if stun > 0.0:
		for s2 in 3:
			var a_st := t * 7.0 + float(s2) * 2.1
			ci.draw_arc(Vector2(px, py), R * 1.25, a_st, a_st + 1.0, 12,
					_fade(RendererScript.hsl(55.0, 1.0, 0.8), stun * alpha), 1.6)

	# leave the transform in world space (TS global-alpha restore)
	_set_world(ci, base_pos, base_zoom)


## The membrane radial gradient sampled at p — TS stops edge(0) → base(0.35)
## → inner(1) over the normalized gradient coordinate.
static func _membrane_color(p: Vector2, gc: Vector2, r0: float, r1: float, edge: Color, base: Color, inner: Color) -> Color:
	var tt := clampf((p.distance_to(gc) - r0) / (r1 - r0), 0.0, 1.0)
	if tt <= 0.35:
		return edge.lerp(base, tt / 0.35)
	return base.lerp(inner, (tt - 0.35) / 0.65)


static func _set_world(ci: CanvasItem, base_pos: Vector2, base_zoom: float) -> void:
	ci.draw_set_transform(base_pos, 0.0, Vector2(base_zoom, base_zoom))


static func _fade(c: Color, alpha: float) -> Color:
	var out := c
	out.a = c.a * alpha
	return out
