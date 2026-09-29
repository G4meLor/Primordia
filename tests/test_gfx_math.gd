## GFX math tests — renderer.hsl vs the TS/CSS HSL→RGB math (pinned values),
## mix_hex, css_color parsing of the sim's CSS payload strings, vignette
## geometry bounds, membrane gradient stops.
extends "res://tests/test_base.gd"

const RendererScript := preload("res://src/gfx/renderer.gd")
const PainterScript := preload("res://src/gfx/cell_painter.gd")


func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func test_hsl_pinned_values() -> void:
	# CSS HSL→RGB (the browser math TS hsl() strings ride), NOT Godot HSV.
	# eps 1e-6: Color stores float32 channels (the Vector2-derived eps class).
	var c: Color = RendererScript.hsl(120.0, 0.55, 0.5)
	var v := _rgb(c)
	approx(v.x, 0.225, "hsl(120,.55,.5).r", 1e-6)
	approx(v.y, 0.775, "hsl(120,.55,.5).g", 1e-6)
	approx(v.z, 0.225, "hsl(120,.55,.5).b", 1e-6)
	approx(c.a, 1.0, "hsl alpha default 1", 1e-6)

	var c2 := _rgb(RendererScript.hsl(222.0, 0.65, 0.1355))
	approx(c2.x, 0.047425, "hsl(222,.65,.1355).r (water top)", 1e-6)
	approx(c2.y, 0.100270, "hsl(222,.65,.1355).g", 1e-6)
	approx(c2.z, 0.223575, "hsl(222,.65,.1355).b", 1e-6)

	var c3 := _rgb(RendererScript.hsl(0.0, 1.0, 0.5))
	approx(c3.x, 1.0, "hsl(0,1,.5).r", 1e-6)
	approx(c3.y, 0.0, "hsl(0,1,.5).g", 1e-6)
	approx(c3.z, 0.0, "hsl(0,1,.5).b", 1e-6)

	var c4 := _rgb(RendererScript.hsl(55.0, 1.0, 0.8))
	approx(c4.x, 1.0, "hsl(55,1,.8).r", 1e-6)
	approx(c4.y, 0.966667, "hsl(55,1,.8).g", 1e-6)
	approx(c4.z, 0.6, "hsl(55,1,.8).b", 1e-6)

	var c5 := _rgb(RendererScript.hsl(350.0, 0.6, 0.3))
	approx(c5.x, 0.48, "hsl(350,.6,.3).r (mouth)", 1e-6)
	approx(c5.y, 0.12, "hsl(350,.6,.3).g", 1e-6)
	approx(c5.z, 0.18, "hsl(350,.6,.3).b", 1e-6)

	var c6 := _rgb(RendererScript.hsl(110.0, 0.9, 0.5))
	approx(c6.x, 0.2, "hsl(110,.9,.5).r (toxin)", 1e-6)
	approx(c6.y, 0.95, "hsl(110,.9,.5).g", 1e-6)
	approx(c6.z, 0.05, "hsl(110,.9,.5).b", 1e-6)

	# alpha passthrough
	approx(RendererScript.hsl(110.0, 0.9, 0.5, 0.26).a, 0.26, "hsl alpha param", 1e-6)


func test_hsl_hue_wraps_and_clamps() -> void:
	var a := _rgb(RendererScript.hsl(480.0, 0.55, 0.5))
	var b := _rgb(RendererScript.hsl(120.0, 0.55, 0.5))
	approx(a.x, b.x, "hue wraps mod 360 (r)", 1e-6)
	approx(a.y, b.y, "hue wraps mod 360 (g)", 1e-6)
	approx(a.z, b.z, "hue wraps mod 360 (b)", 1e-6)
	# s/l clamp like CSS
	var g := _rgb(RendererScript.hsl(120.0, 1.5, -0.5))
	approx(g.x, 0.0, "l < 0 clamps to black (r)", 1e-6)
	approx(g.y, 0.0, "l < 0 clamps to black (g)", 1e-6)


func test_hue_120_axis_invariant_r_equals_b() -> void:
	# the pixel-assert's load-bearing property: at hue 120 every HSL stop has
	# r == b (X = 0 in the [120,180) sector) regardless of s/l
	for l in [0.2, 0.36, 0.5, 0.72]:
		for s in [0.5, 0.55, 0.8, 1.0]:
			var c := RendererScript.hsl(120.0, float(s), float(l))
			approx(c.r, c.b, "hue-120 axis r==b (s=%s l=%s)" % [s, l], 1e-9)


func test_mix_hex_ts_rounding() -> void:
	# TS rounds 8-bit channels: round(127.5) → 128 (half up)
	var c := RendererScript.mix_hex("#000000", "#ffffff", 0.5)
	approx(c.r, 128.0 / 255.0, "mix_hex channel rounding", 1e-6)
	var c2 := RendererScript.mix_hex("#000000", "#ffffff", 0.0)
	approx(c2.r, 0.0, "mix_hex t=0 → a", 1e-6)


func test_css_color_parse() -> void:
	var hex := RendererScript.css_color("#ff8a9a")
	approx(hex.r, 255.0 / 255.0, "css #rrggbb r", 1e-6)
	approx(hex.g, 138.0 / 255.0, "css #rrggbb g", 1e-6)
	approx(hex.b, 154.0 / 255.0, "css #rrggbb b", 1e-6)

	var rgba := RendererScript.css_color("rgba(190,230,255,0.8)")
	approx(rgba.r, 190.0 / 255.0, "css rgba r", 1e-6)
	approx(rgba.g, 230.0 / 255.0, "css rgba g", 1e-6)
	approx(rgba.b, 1.0, "css rgba b", 1e-6)
	approx(rgba.a, 0.8, "css rgba a", 1e-6)

	# the sim _hsl format: "hsl(%d %d%% %d%% / %.2f)" (cell_sim.gd:1370)
	var hsls := RendererScript.css_color("hsl(120 80% 50% / 1.00)")
	approx(hsls.r, 0.1, "sim _hsl r (hsl(120,0.8,0.5))", 1e-6)
	approx(hsls.g, 0.9, "sim _hsl g", 1e-6)
	approx(hsls.b, 0.1, "sim _hsl b", 1e-6)
	approx(hsls.a, 1.0, "sim _hsl a", 1e-6)

	var hsl_a := RendererScript.css_color("hsl(340 80% 20% / 0.06)")
	approx(hsl_a.r, 0.36, "chaos tint r", 1e-6)
	approx(hsl_a.g, 0.04, "chaos tint g", 1e-6)
	approx(hsl_a.b, 0.146667, "chaos tint b", 1e-6)
	approx(hsl_a.a, 0.06, "chaos tint a", 1e-6)


func test_vignette_radii_bounds() -> void:
	# TS vignette: inner min(vw,vh)*0.36, outer max(vw,vh)*0.72
	# (eps 1e-4 — Vector2 stores float32; ulp at ~800 magnitude ≈ 6e-5)
	var r := RendererScript.vignette_radii(1152.0, 648.0)
	approx(r.x, 233.28, "vignette inner radius", 1e-4)
	approx(r.y, 829.44, "vignette outer radius", 1e-4)
	var r2 := RendererScript.vignette_radii(640.0, 640.0)
	approx(r2.x, 230.4, "vignette inner (square)", 1e-4)
	approx(r2.y, 460.8, "vignette outer (square)", 1e-4)
	# the cache key geometry: inner sits inside outer, both cover the corner
	ok(r.x < r.y, "vignette inner < outer")


func test_membrane_gradient_stops() -> void:
	# the membrane fan's color function hits the TS stops exactly at the ends
	var edge := RendererScript.hsl(120.0, 0.55, 0.72)
	var base := RendererScript.hsl(120.0, 0.55, 0.5)
	var inner := RendererScript.hsl(120.0, 0.55 * 0.8, 0.36)
	var gc := Vector2(-3.5, -3.5)  # -R*0.25 at R=14
	var r0 := 1.4
	var r1 := 14.7
	var at := func(p: Vector2) -> Color:
		return PainterScript._membrane_color(p, gc, r0, r1, edge, base, inner)
	var c_in: Color = at.call(Vector2(gc))  # t = 0 → edge
	approx(c_in.r, edge.r, "membrane stop0 = edge", 1e-6)
	approx(c_in.g, edge.g, "membrane stop0 = edge (g)", 1e-6)
	var c_mid: Color = at.call(gc + Vector2(1.4 + 0.35 * 13.3, 0.0))  # t = 0.35 → base
	approx(c_mid.r, base.r, "membrane stop@0.35 = base", 1e-6)
	var c_out: Color = at.call(gc + Vector2(r1, 0.0))  # t = 1 → inner
	approx(c_out.r, inner.r, "membrane stop1 = inner", 1e-6)
	approx(c_out.g, inner.g, "membrane stop1 = inner (g)", 1e-6)


func test_ellipse_points_closed_shape() -> void:
	var pts := RendererScript.ellipse_points(Vector2(5, 6), 10.0, 3.0, 0.7)
	eq(pts.size(), 20, "default 20 segments")
	# first and would-be-last coincide (closed ring for draw_colored_polygon)
	approx(pts[0].distance_to(Vector2(5, 6) + Vector2(10.0, 0.0).rotated(0.7)), 0.0, "point 0 tracks the rotation", 1e-6)
	var all_on: bool = true
	for p in pts:
		var d := (p - Vector2(5, 6)).length()
		if d > 10.0 + 1e-6:
			all_on = false
	ok(all_on, "all points within the rx radius (ry < rx)")
