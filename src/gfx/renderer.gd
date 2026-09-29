## Canvas draw-primitive toolbox — port of the Spore src/gfx/renderer.ts DRAW
## HELPERS (the Camera class already lives in src/game/cam.gd). Static funcs
## issuing Godot CanvasItem draw calls with TS canvas semantics. All funcs
## draw in the CanvasItem's CURRENT draw transform — the caller sets it
## (screen space identity, or the camera transform the stage composes).
##
## Recorded divergences (task 7 report carries the full list):
##  - outlined_text: Godot fallback font (no Segoe UI, no weight 600/700
##    selection) — visual parity at presence/position level, NOT glyph-exact
##    (accepted divergence per the task ruling). canvas 'middle' baseline is
##    approximated by the font's ascent/descent midpoint. The maxWidth
##    shrink-to-fit loop ports (8px floor); the __textShrinks QC counter
##    stays TS-only (it fed the TS QC agents from window state).
##  - panel: canvas shadowBlur 18 is a gaussian blur; StyleBoxFlat's shadow
##    is a solid offset box — presence-level equivalent.
##  - glow/vignette: canvas interpolates gradients premultiplied; the cached
##    radial GradientTexture2D + modulate holds RGB while alpha falls, which
##    composites identically to canvas premultiplied color→transparent.
class_name RendererGfx
extends RefCounted

static var _glow_tex: GradientTexture2D = null
static var _vignette_cache: Dictionary = {}
static var _color_cache: Dictionary = {}


# ---- color helpers ----------------------------------------------------------

## CSS hsl(H S% L% / A) → sRGB Color — the browser's HSL→RGB math (NOT Godot's
## Color.from_hsv, which is HSV). Hue wraps mod 360; s/l clamp like CSS.
static func hsl(h: float, s: float, l: float, a: float = 1.0) -> Color:
	h = fmod(h, 360.0)
	if h < 0.0:
		h += 360.0
	s = clampf(s, 0.0, 1.0)
	l = clampf(l, 0.0, 1.0)
	var c := (1.0 - absf(2.0 * l - 1.0)) * s
	var hp := h / 60.0
	var x := c * (1.0 - absf(fmod(hp, 2.0) - 1.0))
	var r := 0.0
	var g := 0.0
	var b := 0.0
	if hp < 1.0:
		r = c
		g = x
	elif hp < 2.0:
		r = x
		g = c
	elif hp < 3.0:
		g = c
		b = x
	elif hp < 4.0:
		g = x
		b = c
	elif hp < 5.0:
		r = x
		b = c
	else:
		r = c
		b = x
	var m := l - c * 0.5
	return Color(r + m, g + m, b + m, a)


## TS mixHex (renderer.ts:73-81): 8-bit channel round-trip — the rounding is
## part of the ported behavior. (GDScript hex_to_int rejects the '#' prefix,
## unlike TS parseInt(hex, 16) — strip it first.)
static func mix_hex(a: String, b: String, t: float) -> Color:
	var pa := a.substr(1).hex_to_int() if a.begins_with("#") else int(a)
	var pb := b.substr(1).hex_to_int() if b.begins_with("#") else int(b)
	var ar := (pa >> 16) & 255
	var ag := (pa >> 8) & 255
	var ab := pa & 255
	var br := (pb >> 16) & 255
	var bg := (pb >> 8) & 255
	var bb := pb & 255
	var r := roundi(float(ar) + float(br - ar) * t)
	var g := roundi(float(ag) + float(bg - ag) * t)
	var bl := roundi(float(ab) + float(bb - ab) * t)
	return Color(float(r) / 255.0, float(g) / 255.0, float(bl) / 255.0, 1.0)


## Parse the frozen TS CSS color strings the sim ships in fx payloads:
## '#rgb'/'#rrggbb'/'#rrggbbaa', 'rgb(...)'/'rgba(...)', and 'hsl()' in both
## the modern space form (renderer hsl() output: "hsl(120 80% 50% / 1.00)")
## and the legacy comma form. Cached per string.
static func css_color(s: String) -> Color:
	if _color_cache.has(s):
		return _color_cache[s]
	var t := s.strip_edges()
	var out := Color(1, 1, 1, 1)
	if t.begins_with("#"):
		out = Color.html(t)
	elif t.begins_with("rgba(") or t.begins_with("rgb("):
		var inner := t.substr(t.find("(") + 1, t.length() - t.find("(") - 2)
		var parts := inner.split(",")
		var alpha := 1.0
		if parts.size() >= 4:
			alpha = float(parts[3])
		out = Color(float(parts[0]) / 255.0, float(parts[1]) / 255.0, float(parts[2]) / 255.0, alpha)
	elif t.begins_with("hsl("):
		var inner2 := t.substr(t.find("(") + 1, t.length() - t.find("(") - 2)
		var alpha2 := 1.0
		var body := inner2
		var slash := inner2.find("/")
		if slash >= 0:
			body = inner2.substr(0, slash).strip_edges()
			alpha2 = float(inner2.substr(slash + 1).strip_edges())
		var comps := body.split(",") if body.contains(",") else body.split(" ")
		var nums: Array[float] = []
		for c in comps:
			var txt := String(c).strip_edges().replace("%", "")
			if txt != "":
				nums.append(float(txt))
		if nums.size() >= 3:
			var col := hsl(nums[0], nums[1] / 100.0 if body.contains("%") else nums[1],
					nums[2] / 100.0 if body.contains("%") else nums[2], alpha2)
			out = col
	_color_cache[s] = out
	return out


static func as_color(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	# an absent key reads "" through .get(k, "") — "" must reach the fallback,
	# not css_color("") (which would return opaque white and swallow every
	# documented default: the text outline rgba(0,0,0,0.75), the panel fill
	# rgba(8,14,30,0.82), the #eaf2ff text fill)
	if v is String and v != "":
		return css_color(v)
	return fallback


# ---- draw helpers -----------------------------------------------------------

## TS disc(): performant pixel-circle fill used everywhere.
static func disc(ci: CanvasItem, x: float, y: float, r: float, fill: Color) -> void:
	ci.draw_circle(Vector2(x, y), r, fill)


## TS glow(): radial gradient color→transparent under globalAlpha. The white
## falloff texture is cached once; modulate supplies the color (RGB held,
## alpha fades — see the header divergence note).
static func glow(ci: CanvasItem, x: float, y: float, r: float, color: Color, alpha := 0.5) -> void:
	var tex := _get_glow_tex()
	var m := Color(color.r, color.g, color.b, color.a * alpha)
	ci.draw_texture_rect(tex, Rect2(x - r, y - r, r * 2.0, r * 2.0), false, m)


## Radial gradient DISC with a held inner radius (canvas
## createRadialGradient(x,y,r0 → x,y,r1): solid stop0 inside r0, falloff to
## stop1 at r1). Used by the cell painter auras and the toxin zones. The
## annulus is a vertex-colored ring polygon (Gouraud ≈ radial at these
## segment counts); the inner disc is a plain fill of stop0.
static func radial_disc(ci: CanvasItem, center: Vector2, r0: float, r1: float, col0: Color, col1: Color, segments := 36) -> void:
	if r1 <= r0:
		ci.draw_circle(center, r1, col0)
		return
	ci.draw_circle(center, r0, col0)
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
	ci.draw_polygon(pts, cols)


## Ellipse outline points (TS ctx.ellipse(x, y, rx, ry, rotation)) — shared by
## the cell painter organelles and the backdrop caustic bands.
static func ellipse_points(center: Vector2, rx: float, ry: float, rot: float, segments := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cr := cos(rot)
	var sr := sin(rot)
	for i in segments:
		var a := (float(i) / float(segments)) * TAU
		var ex := cos(a) * rx
		var ey := sin(a) * ry
		pts.append(center + Vector2(ex * cr - ey * sr, ex * sr + ey * cr))
	return pts


## Rounded-rect outline points (TS roundRectPath/arcTo shape) with per-corner
## arcs — used for the HP-bar gradient fill (vertex colors interpolate the
## TS linear gradient).
static func rounded_rect_points(x: float, y: float, w: float, h: float, r: float, segments := 5) -> PackedVector2Array:
	var rr := minf(r, minf(w / 2.0, h / 2.0))
	var pts := PackedVector2Array()
	# clockwise from the top-left arc, matching the TS path winding
	_corner_arc(pts, x + rr, y + rr, rr, PI, PI * 1.5, segments)
	_corner_arc(pts, x + w - rr, y + rr, rr, PI * 1.5, TAU, segments)
	_corner_arc(pts, x + w - rr, y + h - rr, rr, 0.0, PI * 0.5, segments)
	_corner_arc(pts, x + rr, y + h - rr, rr, PI * 0.5, PI, segments)
	return pts


static func _corner_arc(pts: PackedVector2Array, cx: float, cy: float, r: float, a0: float, a1: float, segments: int) -> void:
	for i in segments + 1:
		var a := a0 + (a1 - a0) * (float(i) / float(segments))
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))


## TS panel(): roundRect r=12 fill + optional stroke (lw default 1.5) +
## optional shadow (default fill rgba(8,14,30,0.82)). See the header note on
## the shadow divergence.
static func panel(ci: CanvasItem, x: float, y: float, w: float, h: float, style: Dictionary = {}) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = as_color(style.get("fill", ""), Color(8.0 / 255.0, 14.0 / 255.0, 30.0 / 255.0, 0.82))
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	if style.has("stroke") and style["stroke"] != null:
		var stroke := as_color(style["stroke"], Color(0, 0, 0, 0))
		sb.border_color = stroke
		var lw := float(style.get("lw", 1.5))
		sb.border_width_left = lw
		sb.border_width_right = lw
		sb.border_width_top = lw
		sb.border_width_bottom = lw
	if style.has("shadow") and style["shadow"] != null:
		sb.shadow_color = as_color(style["shadow"], Color(0, 0, 0, 0))
		sb.shadow_size = 18
	ci.draw_style_box(sb, Rect2(x, y, w, h))


## Horizontal-gradient rounded-rect fill (TS roundRectPathFill + a 2-stop
## linear gradient — the player HP bar). Vertex colors left/right interpolate
## the gradient through the polygon triangulation.
static func gradient_rounded_rect(ci: CanvasItem, rect: Rect2, r: float, col_left: Color, col_right: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var pts := rounded_rect_points(rect.position.x, rect.position.y, rect.size.x, rect.size.y, r)
	var cols := PackedColorArray()
	var right := rect.position.x + rect.size.x
	for p in pts:
		var u := clampf((p.x - rect.position.x) / rect.size.x, 0.0, 1.0)
		cols.append(col_left.lerp(col_right, u))
	ci.draw_polygon(pts, cols)


## TS outlinedText(): weight-600 sans, align center, baseline middle, outline
## lineWidth max(2, size/6), fill #eaf2ff. See the header divergence note.
static func outlined_text(ci: CanvasItem, text: String, x: float, y: float, opts: Dictionary = {}) -> void:
	var font: Font = ThemeDB.fallback_font
	var size := float(opts.get("size", 14.0))
	var max_w := float(opts.get("maxWidth", 0.0))
	if max_w > 0.0:
		# shrink-to-fit: long objectives/toasts used to spill out of their box
		# (the font must RE-MEASURE each iteration — TS comment verbatim)
		while size > 8.0:
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(maxf(1.0, roundf(size)))).x
			if w <= max_w:
				break
			size -= 0.5
	var draw_size := int(maxf(1.0, roundf(size)))
	var alpha := float(opts.get("alpha", 1.0))
	var fill := as_color(opts.get("fill", ""), Color("#eaf2ff"))
	var outline := as_color(opts.get("outline", ""), Color(0.0, 0.0, 0.0, 0.75))
	fill.a *= alpha
	outline.a *= alpha
	var asc := font.get_ascent(draw_size)
	var desc := font.get_descent(draw_size)
	# canvas textBaseline 'middle' ≈ the line-box midpoint → baseline sits
	# below y by (ascent − descent)/2
	var pos := Vector2(x, y + (asc - desc) * 0.5)
	var align := String(opts.get("align", "center"))
	if align == "center":
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, draw_size).x
		pos.x = x - tw * 0.5
	elif align == "right":
		var tw2 := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, draw_size).x
		pos.x = x - tw2
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, draw_size, int(maxf(2.0, size / 6.0)), outline)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, draw_size, fill)


## TS vignette(): radial transparent center → rgba(0,0,10,strength) at the
## outer radius; inner radius min(vw,vh)*0.36, outer max(vw,vh)*0.72 — cached
## per (vw,vh,strength) exactly like the TS gradient cache.
static func vignette(ci: CanvasItem, vw: float, vh: float, strength := 0.45) -> void:
	var tex := _get_vignette_tex(vw, vh, strength)
	var r := maxf(vw, vh) * 0.72
	ci.draw_texture_rect(tex, Rect2(vw / 2.0 - r, vh / 2.0 - r, r * 2.0, r * 2.0), false, Color(1, 1, 1, 1))


## Pure geometry of the vignette gradient — exposed for headless tests.
static func vignette_radii(vw: float, vh: float) -> Vector2:
	return Vector2(minf(vw, vh) * 0.36, maxf(vw, vh) * 0.72)


static func _get_glow_tex() -> GradientTexture2D:
	if _glow_tex != null:
		return _glow_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex = tex
	return tex


static func _get_vignette_tex(vw: float, vh: float, strength: float) -> GradientTexture2D:
	var key := "%dx%d:%.3f" % [int(vw), int(vh), strength]
	var tex: GradientTexture2D = _vignette_cache.get(key)
	if tex != null:
		return tex
	var radii := vignette_radii(vw, vh)
	var outer := radii.y
	var inner_frac := radii.x / outer
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, inner_frac, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.0, 0.0, 10.0 / 255.0, strength)])
	tex = GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_vignette_cache[key] = tex
	return tex
