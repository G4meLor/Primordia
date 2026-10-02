## Stage backdrops — port of Spore src/gfx/backdrop.ts (frozen).
## drawWaterBackdrop (cell stage) + drawLandBackdrop/drawGround (creature
## stage) + drawSpaceBackdrop (civ stage; SpaceStage consumes it later).
## Screen-space: call with the canvas transform at IDENTITY (TS draws it
## before cam.begin) — it parallaxes against cam.x/cam.y directly.
## Deterministic hash2 tiling, no per-frame allocation.
##
## Recorded divergence: the god-ray block uses canvas 'lighter' (additive)
## compositing; Godot blend modes are per-canvas-ITEM (one item cannot mix
## blend modes per draw call), so the rays composite normally at their TS
## alpha (≤ 0.10 − depth01·0.05 ≈ 0.08) — max channel error ≈ dst·α, below
## presence level. Recorded in the task report.
##
## Land (task 7): the sky gradient/stars/sun-moon/clouds/hills draw in SCREEN
## space (the stage's sky canvas cancels the viewport camera transform); the
## sun/moon radial gradients are piecewise-linear radial stops reproduced as
## vertex-colored fans — canvas interpolates linearly between stops, so the
## fan is stop-exact at the rim, with one recorded sub-pixel divergence: TS
## createRadialGradient starts at inner radius 4 (backdrop.ts:137/144), which
## holds the core stop solid inside r=4 and pushes the mid-stop ring ~3px
## farther out than the fan's r=0 core. drawGround is WORLD-space (TS
## calls it inside cam.begin): its 3-stop vertical dirt gradient is two
## abutted vertex-colored quads (exact piecewise), the tuft quadratic strokes
## are sampled polylines (cell_painter divergence precedent).
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")


## TS hash2 (backdrop.ts:8-11) verbatim.
static func hash2(x: float, y: float, s: float) -> float:
	var h := sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453
	return h - floor(h)


## drawWaterBackdrop (backdrop.ts:17-94): depth gradient → god rays →
## plankton motes (two parallax layers) → caustic bands near the surface →
## chaos tint.
static func draw_water_backdrop(ci: CanvasItem, cam: Variant, vw: float, vh: float, t: float, chaos: float, depth01: float) -> void:
	# Vertical depth gradient (canvas linear gradient top→bottom = the exact
	# bilinear vertex-color interpolation of a full-screen quad)
	var top := RendererScript.hsl(222.0 - chaos * 30.0, 0.65, 0.16 - depth01 * 0.06)
	var bottom := RendererScript.hsl(230.0 - chaos * 40.0, 0.7, 0.05)
	ci.draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(vw, 0), Vector2(vw, vh), Vector2(0, vh)]),
			PackedColorArray([top, top, bottom, bottom]))

	# God rays (screen-space light shafts) — see the header divergence note
	for i in 5:
		var bx := fmod((float(i) * 0.37 + 0.1) * vw + sin(t * 0.05 + float(i) * 1.7) * 60.0 - cam.x * 0.05, vw + 400.0) - 200.0
		var sway := sin(t * 0.3 + float(i) * 2.1) * 0.08
		var w := 60.0 + hash2(float(i), 3.0, 7.0) * 90.0
		# translate(bx, -40) rotate(0.28+sway) fillRect(-w/2, 0, w, vh) with a
		# vertical color→transparent gradient (fade completes at vh*0.9)
		ci.draw_set_transform(Vector2(bx, -40.0), 0.28 + sway, Vector2.ONE)
		var ray_col := RendererScript.hsl(200.0, 0.8, 0.75, maxf(0.0, 0.10 - depth01 * 0.05))
		ci.draw_polygon(
				PackedVector2Array([
					Vector2(-w / 2.0, 0.0), Vector2(w / 2.0, 0.0),
					Vector2(w / 2.0, vh), Vector2(-w / 2.0, vh),
				]),
				PackedColorArray([ray_col, ray_col, Color(ray_col, 0.0), Color(ray_col, 0.0)]))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Drifting plankton motes (two parallax layers)
	for layer in 2:
		var p := 0.18 + float(layer) * 0.22
		var S := 220.0 - float(layer) * 60.0
		var ox: float = cam.x * p
		var oy: float = cam.y * p
		var i0 := floori((ox - vw / 2.0) / S)
		var i1 := ceili((ox + vw / 2.0) / S)
		var j0 := floori((oy - vh / 2.0) / S)
		var j1 := ceili((oy + vh / 2.0) / S)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var hx := hash2(float(i), float(j), 11.0 + float(layer) * 77.0)
				var hy := hash2(float(i), float(j), 23.0 + float(layer) * 77.0)
				var hp := hash2(float(i), float(j), 41.0 + float(layer) * 77.0)
				var sx: float = vw / 2.0 + (float(i) * S + hx * S) - ox
				var sy: float = vh / 2.0 + (float(j) * S + hy * S) - oy
				var sz := 1.0 + hp * (2.0 if layer == 0 else 3.4)
				var tw := 0.25 + 0.2 * sin(t * (0.6 + hp) + hp * 9.0)
				ci.draw_circle(Vector2(sx, sy), sz, RendererScript.hsl(190.0 + hp * 60.0, 0.5, 0.7, tw))

	# Faint caustic bands near the surface
	if depth01 < 0.55:
		for i in 6:
			var yy := (float(i) / 6.0) * vh + sin(t * 0.4 + float(i)) * 18.0
			var cxx := vw / 2.0 + sin(t * 0.3 + float(i) * 2.0) * vw * 0.3
			var rot := sin(t * 0.2 + float(i)) * 0.2
			var band := RendererScript.hsl(195.0, 0.7, 0.8, 0.5)
			band.a *= (0.55 - depth01) * 0.16
			ci.draw_colored_polygon(RendererScript.ellipse_points(Vector2(cxx, yy), 190.0, 5.0, rot), band)

	# Chaos tint
	if chaos > 0.55:
		ci.draw_rect(Rect2(0, 0, vw, vh), RendererScript.hsl(340.0, 0.8, 0.2, (chaos - 0.55) * 0.10))


# ---- SPACE (civ stage; SpaceStage later) — backdrop.ts:210-260 ------------------

## drawSpaceBackdrop (backdrop.ts:213-260): flat #02030a → 4 nebulae (radial
## gradients) → 3 parallax star layers. Reads ONLY cam.x/cam.y (backdrop.ts
## :227-228) — the civ stage passes a fakeCam whose other TS literal fields
## (zoom 1, view rect, shx/shy 0) are dead at this call site and are not
## ported. Nebulae used canvas 'lighter' (additive) compositing in TS — Godot
## blend modes are per-canvas-ITEM, so they composite normally at their TS
## alphas (≤ 0.10, the god-ray divergence precedent in this file's header);
## each nebula's 3-stop radial gradient is the _radial_stops_disc fan.
static func draw_space_backdrop(ci: CanvasItem, cam: Variant, vw: float, vh: float,
		t: float, seed: float) -> void:
	ci.draw_rect(Rect2(0, 0, vw, vh), Color("02030a"))

	# Nebulae (backdrop.ts:222-243)
	for i in 4:
		var hx := hash2(float(i), seed, 3.0)
		var hy := hash2(float(i), seed, 4.0)
		var hue: float = [265.0, 200.0, 320.0, 180.0][i % 4]
		# ((hx·3000 − cam.x·0.05) % 3000 + 3000) % 3000 − 500 + vw·0.2 — fmod
		# keeps the dividend's sign like JS %, so the +3000 re-wrap is exact
		var nx: float = fmod(fmod(hx * 3000.0 - cam.x * 0.05, 3000.0) + 3000.0, 3000.0) \
				- 500.0 + vw * 0.2
		var ny: float = fmod(fmod(hy * 2000.0 - cam.y * 0.05, 2000.0) + 2000.0, 2000.0) \
				- 300.0 + vh * 0.2
		var r: float = 300.0 + hash2(float(i), seed, 5.0) * 350.0
		_radial_stops_disc(ci, Vector2(nx, ny), [
			[0.0, RendererScript.hsl(hue, 0.75, 0.4, 0.10)],
			[r * 0.6, RendererScript.hsl(hue + 30.0, 0.7, 0.3, 0.05)],
			[r, Color(0.0, 0.0, 0.0, 0.0)],  # TS stop-1 'transparent'
		])

	# Star layers (backdrop.ts:245-260)
	for layer in 3:
		var p := 0.08 + float(layer) * 0.14
		var s_span := 260.0 - float(layer) * 70.0
		var ox: float = cam.x * p
		var oy: float = cam.y * p
		var i0 := floori((ox - vw / 2.0) / s_span) - 1
		var i1 := ceili((ox + vw / 2.0) / s_span) + 1
		var j0 := floori((oy - vh / 2.0) / s_span) - 1
		var j1 := ceili((oy + vh / 2.0) / s_span) + 1
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var hx2 := hash2(float(i), float(j), 11.0 + float(layer) * 31.0 + seed)
				var hy2 := hash2(float(i), float(j), 23.0 + float(layer) * 31.0 + seed)
				var hp2 := hash2(float(i), float(j), 47.0 + float(layer) * 31.0 + seed)
				var sx: float = vw / 2.0 + (float(i) * s_span + hx2 * s_span) - ox
				var sy: float = vh / 2.0 + (float(j) * s_span + hy2 * s_span) - oy
				var sz: float = 0.7 + hp2 * (float(layer) * 0.9 + 0.8)
				var tw: float = 0.35 + 0.5 * absf(sin(t * (0.4 + hp2 * 1.4) + hp2 * 20.0))
				ci.draw_rect(Rect2(sx, sy, sz, sz),
						RendererScript.hsl(hp2 * 40.0 + 200.0, 0.35 * hp2, 0.85, tw))


# ---- LAND (creature stage) — backdrop.ts:100-207 -------------------------------

## TS lerpWrap (backdrop.ts:204-207) — hue-path lerp (shortest wrap).
static func lerp_wrap(a: float, b: float, t: float) -> float:
	var d: float = fmod(b - a + 540.0, 360.0) - 180.0
	return fmod(a + d * t + 360.0, 360.0)


## TS mixHsl (backdrop.ts:196-202) — numeric HSL mix (no string round-trip).
static func mix_hsl(h1: float, s1: float, l1: float, h2: float, s2: float,
		l2: float, t: float) -> Color:
	if t <= 0.0:
		return RendererScript.hsl(h1, s1, l1)
	var h := lerp_wrap(h1, h2, t)
	var s := s1 + (s2 - s1) * t
	var l := l1 + (l2 - l1) * t
	return RendererScript.hsl(h, s, l)


## TS hills' 3-sin height sum (backdrop.ts:179) — exposed for the headless
## determinism test (the draw path reads it through the same function).
static func land_hill_h(wx: float, seed: float) -> float:
	return sin(wx * 1.7 + seed) * 0.45 + sin(wx * 3.9 + seed * 2.0) * 0.3 \
			+ sin(wx * 0.6 + seed) * 0.55


## TS star i position (backdrop.ts:122-128) — pure function of (i, viewport,
## cam.x), deterministic; factored out of the draw for the headless test.
static func land_star_pos(i: int, vw: float, vh: float, cam_x: float) -> Vector2:
	var hx := hash2(float(i), 1.0, 5.0)
	var hy := hash2(float(i), 2.0, 5.0)
	var sx: float = fmod(hx * vw * 2.0 - cam_x * 0.03, vw)
	if sx < 0.0:
		sx += vw
	return Vector2(sx, hy * vh * 0.6)


## TS cloud i anchor (backdrop.ts:152-156) — pure, deterministic.
static func land_cloud_pos(i: int, vw: float, vh: float, t: float, cam_x: float) -> Vector2:
	var span := vw + 600.0
	var cxp: float = fmod(hash2(float(i), 1.0, 9.0) * span + t * (6.0 + float(i) * 2.0) - cam_x * 0.06, span)
	if cxp < 0.0:
		cxp += span
	return Vector2(cxp - 300.0, vh * (0.1 + hash2(float(i), 2.0, 9.0) * 0.25))


## Piecewise-linear radial gradient disc — vertices at the stop radii, so the
## Gouraud fan is stop-exact at the rims (canvas interpolates linearly between
## stops; the fan interpolates linearly along each radius). TS's inner radius
## 4 (createRadialGradient r0) shifts its mid-stop ring ~3px outward vs this
## fan's r=0 core — see the header divergence note. stops: Array of
## [radius, Color] with stops[0][0] == 0.
## Emitted as ONE indexed triangle list (RenderingServer
## canvas_item_add_triangle_array): a single draw_polygon for the whole ring
## trips Geometry2D's triangulator into sliver/missing triangles that render
## position-dependently (under the creature stage's enabled Camera2D this left
## the sun and moon invisible — the task-10 scene captures; see
## creature_stage.gd _ellipse_radial), and one draw_polygon PER SEGMENT fixes
## the geometry but multiplies draw calls ~36×, which measured 8.03 ms vs the
## 8.0 ms perf-probe tick budget (the probe's timed window includes
## _do_render — tests/scenes/test_perf.gd:147-150). The triangle array is the
## exact primitive for a triangle list: no triangulator, one call.
static func _radial_stops_disc(ci: CanvasItem, center: Vector2, stops: Array,
		segments := 36) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for s in range(stops.size() - 1):
		var r0: float = stops[s][0]
		var r1: float = stops[s + 1][0]
		var c0: Color = stops[s][1]
		var c1: Color = stops[s + 1][1]
		if r1 <= r0:
			continue
		var base := pts.size()
		if r0 <= 0.0:
			# fan: center vertex (c0) + closed rim ring (c1)
			pts.append(center)
			cols.append(c0)
			for i in segments:
				var a := (float(i) / float(segments)) * TAU
				pts.append(center + Vector2(cos(a), sin(a)) * r1)
				cols.append(c1)
			for i in segments:
				idx.append(base)
				idx.append(base + 1 + i)
				idx.append(base + 1 + ((i + 1) % segments))
		else:
			# ring: inner ring (c0) then outer ring (c1); quads split exactly
			# as the band polygon [iA(c0), iB(c0), oB(c1), oA(c1)] tri split
			for i in segments:
				var a := (float(i) / float(segments)) * TAU
				pts.append(center + Vector2(cos(a), sin(a)) * r0)
				cols.append(c0)
			for i in segments:
				var a := (float(i) / float(segments)) * TAU
				pts.append(center + Vector2(cos(a), sin(a)) * r1)
				cols.append(c1)
			for i in segments:
				var j: int = (i + 1) % segments
				idx.append(base + i)
				idx.append(base + j)
				idx.append(base + segments + j)
				idx.append(base + i)
				idx.append(base + segments + j)
				idx.append(base + segments + i)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(),
			idx, pts, cols)


## drawLandBackdrop (backdrop.ts:100-193): sky gradient (day/night/dusk HSL
## mixes) → stars → sun/moon → clouds → 3 parallax hill layers → chaos haze.
## ground_y = the screen-space horizon anchor (TS CreatureStage.ts:1348
## passes the world y=0 line: vh/2 − cam.y·zoom).
static func draw_land_backdrop(ci: CanvasItem, cam: Variant, vw: float, vh: float,
		t: float, chaos: float, day_phase: float, ground_y: float) -> void:
	# dayPhase: 0 = dawn, 0.25 = noon, 0.5 = dusk, 0.75 = midnight
	var sun_angle := day_phase * TAU
	var sun_h := sin(sun_angle)  # >0 day
	var day := maxf(0.0, sun_h)
	var night := maxf(0.0, -sun_h)
	var dusk := maxf(0.0, 1.0 - absf(sun_h) * 3.0)

	var sky_top := mix_hsl(215.0, 0.6, 0.10 + day * 0.28, 270.0, 0.5, 0.07, night * 0.8)
	var sky_bottom := mix_hsl(28.0, 0.55, 0.72 - night * 0.55, 345.0, 0.6, 0.35, dusk * 0.55)
	ci.draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(vw, 0), Vector2(vw, vh), Vector2(0, vh)]),
			PackedColorArray([sky_top, sky_top, sky_bottom, sky_bottom]))

	# Stars at night
	if night > 0.05:
		for i in 60:
			var pos := land_star_pos(i, vw, vh, cam.x)
			var hx := hash2(float(i), 1.0, 5.0)
			var tw := 0.4 + 0.6 * absf(sin(t * (0.5 + hx) + float(i)))
			ci.draw_rect(Rect2(pos.x, pos.y, 1.6, 1.6), RendererScript.hsl(0.0, 0.0, 0.95, tw * night))

	# Sun / moon
	var cx := vw * 0.5 + cos(sun_angle + PI) * vw * 0.42
	var cy := vh * 0.72 - sun_h * vh * 0.6
	if day > 0.02 or dusk > 0.02:
		# radial stops 0 / 0.25 / 1 of r 130 (TS:137-141)
		_radial_stops_disc(ci, Vector2(cx, cy), [
			[0.0, RendererScript.hsl(45.0, 1.0, 0.85, 0.9)],
			[130.0 * 0.25, RendererScript.hsl(40.0, 1.0, 0.7, 0.55 * (day + dusk))],
			[130.0, Color(RendererScript.hsl(40.0, 1.0, 0.7), 0.0)],
		])
	else:
		_radial_stops_disc(ci, Vector2(cx, cy), [
			[0.0, RendererScript.hsl(220.0, 0.2, 0.92, 0.8 * night)],
			[90.0, Color(RendererScript.hsl(220.0, 0.2, 0.92), 0.0)],
		])

	# Clouds
	for i in 5:
		var cw := 120.0 + hash2(float(i), 3.0, 9.0) * 180.0
		var cpos := land_cloud_pos(i, vw, vh, t, cam.x)
		var col := RendererScript.hsl(0.0, 0.0, 0.9, 0.06 + day * 0.08)
		for b in 4:
			ci.draw_colored_polygon(
					RendererScript.ellipse_points(
							Vector2(cpos.x + float(b) * cw * 0.24, cpos.y + sin(float(b) * 2.0 + float(i)) * 7.0),
							cw * (0.3 - float(b) * 0.04), 17.0 - float(b) * 2.0, 0.0),
					col)

	# Parallax hills (3 layers) — anchored so the ground plane stays consistent
	var layers := [
		{"p": 0.12, "h": 0.34, "col": mix_hsl(150.0, 0.30, 0.30 + day * 0.12, 250.0, 0.3, 0.10, night * 0.75), "seed": 31.0},
		{"p": 0.25, "h": 0.27, "col": mix_hsl(140.0, 0.35, 0.24 + day * 0.12, 250.0, 0.35, 0.08, night * 0.75), "seed": 57.0},
		{"p": 0.45, "h": 0.20, "col": mix_hsl(130.0, 0.40, 0.18 + day * 0.12, 250.0, 0.4, 0.06, night * 0.75), "seed": 83.0},
	]
	var horizon := ground_y - vh * 0.22
	for L in layers:
		var p: float = L["p"]
		var hgt_h: float = L["h"]
		var seed: float = L["seed"]
		var pts := PackedVector2Array()
		pts.append(Vector2(0, vh))
		var off: float = cam.x * p
		var sx := 0.0
		while sx <= vw:
			var wx := (sx + off) * 0.004
			var hgt := land_hill_h(wx, seed)
			var y := horizon - hgt_h * vh * (0.55 + hgt * 0.45) - maxf(0.0, -cam.y) * p * 0.3
			pts.append(Vector2(sx, y))
			sx += 16.0
		pts.append(Vector2(vw, vh))
		ci.draw_colored_polygon(pts, L["col"])

	# Chaos: blood-red haze
	if chaos > 0.5:
		ci.draw_rect(Rect2(0, 0, vw, vh), RendererScript.hsl(0.0, 0.7, 0.25, (chaos - 0.5) * 0.16))


## drawGround (backdrop.ts:265-295) — WORLD-space ground strip for land
## stages: 3-stop dirt gradient, grass fringe, deterministic swaying tufts.
static func draw_ground(ci: CanvasItem, left: float, right: float, ground_y: float,
		depth: float, t: float, chaos: float) -> void:
	# Dirt — 3-stop vertical gradient (0 / 0.12 / 1) as two abutted quads
	var ca := RendererScript.hsl(95.0 - chaos * 40.0, 0.35, 0.32)
	var cb := RendererScript.hsl(88.0, 0.30, 0.24)
	var cc := RendererScript.hsl(30.0, 0.25, 0.14)
	var mid_y := ground_y + depth * 0.12
	ci.draw_polygon(
			PackedVector2Array([Vector2(left, ground_y), Vector2(right, ground_y), Vector2(right, mid_y), Vector2(left, mid_y)]),
			PackedColorArray([ca, ca, cb, cb]))
	ci.draw_polygon(
			PackedVector2Array([Vector2(left, mid_y), Vector2(right, mid_y), Vector2(right, ground_y + depth), Vector2(left, ground_y + depth)]),
			PackedColorArray([cb, cb, cc, cc]))

	# Grass fringe
	ci.draw_rect(Rect2(left, ground_y, right - left, 6.0), RendererScript.hsl(105.0 - chaos * 30.0, 0.45, 0.34))
	# tufts
	var step := 26.0
	var i0 := floori(left / step)
	var i1 := ceili(right / step)
	var tuft_col := RendererScript.hsl(110.0 - chaos * 30.0, 0.5, 0.4)
	for i in range(i0, i1 + 1):
		var h := hash2(float(i), 7.0, 3.0)
		var x := float(i) * step + h * 14.0
		var sway := sin(t * 1.2 + float(i) * 0.7) * 2.4
		var len := 5.0 + h * 7.0
		# quadraticCurveTo(x+sway, groundY - len*0.6, x+sway*2, groundY - len)
		var curve := PackedVector2Array()
		var segs := 8
		for k in segs + 1:
			var u := float(k) / float(segs)
			var q0 := (1.0 - u) * (1.0 - u)
			var q1 := 2.0 * (1.0 - u) * u
			var q2 := u * u
			curve.append(Vector2(
				q0 * x + q1 * (x + sway) + q2 * (x + sway * 2.0),
				q0 * (ground_y + 2.0) + q1 * (ground_y - len * 0.6) + q2 * (ground_y - len)))
		ci.draw_polyline(curve, tuft_col, 1.6, true)
