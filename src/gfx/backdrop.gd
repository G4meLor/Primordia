## Stage backdrops — port of Spore src/gfx/backdrop.ts (frozen). Only
## drawWaterBackdrop (cell stage) is ported for this task; land/space arrive
## with their stages. Screen-space: call with the canvas transform at IDENTITY
## (TS draws it before cam.begin) — it parallaxes against cam.x/cam.y
## directly. Deterministic hash2 tiling, no per-frame allocation.
##
## Recorded divergence: the god-ray block uses canvas 'lighter' (additive)
## compositing; Godot blend modes are per-canvas-ITEM (one item cannot mix
## blend modes per draw call), so the rays composite normally at their TS
## alpha (≤ 0.10 − depth01·0.05 ≈ 0.08) — max channel error ≈ dst·α, below
## presence level. Recorded in the task report.
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
