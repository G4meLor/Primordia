## Land backdrop tests — the drawLandBackdrop/drawGround port (task 7).
## TS source: Spore src/gfx/backdrop.ts:100-295 (frozen). The pure helpers
## (mix_hsl/lerp_wrap/land_hill_h/land_star_pos/land_cloud_pos/hash2) pin the
## TS math headlessly; the draw functions need a CanvasItem and are covered by
## the xvfb scene asserts (tests/scenes/test_creature_scene.gd + the checker).
extends "res://tests/test_base.gd"

const Backdrop := preload("res://src/gfx/backdrop.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")


func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func test_lerp_wrap_pinned() -> void:
	# TS lerpWrap: shortest hue-path. 215→270 (d=55): t 0.8 → 259.0
	approx(Backdrop.lerp_wrap(215.0, 270.0, 0.8), 259.0, "lerp_wrap 215→270 t=.8", 1e-9)
	# 350→10 wraps forward through 0 (d = ((10-350+540)%360)-180 = 20)
	approx(Backdrop.lerp_wrap(350.0, 10.0, 0.5), 0.0, "lerp_wrap 350→10 crosses 0", 1e-9)
	approx(Backdrop.lerp_wrap(10.0, 350.0, 0.5), 0.0, "lerp_wrap 10→350 crosses 0", 1e-9)
	approx(Backdrop.lerp_wrap(100.0, 100.0, 0.3), 100.0, "lerp_wrap identity", 1e-9)
	# TS t<=0 short-circuits to hsl(h1…) before touching the lerp
	approx(Backdrop.lerp_wrap(215.0, 270.0, 0.0), 215.0, "lerp_wrap t=0", 1e-9)


func test_mix_hsl_pinned_stops() -> void:
	# skyTop at noon (dayPhase .25: day=1 night=0): mixHsl(215,.6,.38, 270,.5,.07, 0)
	# → plain hsl(215,.6,.38) — pinned to the literal CSS math
	var noon := Backdrop.mix_hsl(215.0, 0.6, 0.38, 270.0, 0.5, 0.07, 0.0)
	var v := _rgb(noon)
	approx(v.x, 0.152, "sky top noon r", 1e-6)
	approx(v.y, 0.342, "sky top noon g", 1e-6)
	approx(v.z, 0.608, "sky top noon b", 1e-6)
	# skyTop at midnight (night=1): mixes toward hsl(270,.5,.07) at t .8
	var mid := _rgb(Backdrop.mix_hsl(215.0, 0.6, 0.10, 270.0, 0.5, 0.07, 0.8))
	approx(mid.x, 0.061509, "sky top midnight r", 1e-6)
	approx(mid.y, 0.036480, "sky top midnight g", 1e-6)
	approx(mid.z, 0.115520, "sky top midnight b", 1e-6)
	# skyBottom at dusk (dusk=1): mixHsl(28,.55,.72, 345,.6,.35, .55)
	var dusk := _rgb(Backdrop.mix_hsl(28.0, 0.55, 0.72, 345.0, 0.6, 0.35, 0.55))
	approx(dusk.x, 0.795721, "sky bottom dusk r", 1e-6)
	approx(dusk.y, 0.277766, "sky bottom dusk g", 1e-6)
	approx(dusk.z, 0.237279, "sky bottom dusk b", 1e-6)
	# hill layer 0 noon vs midnight — the day lift and night desaturation
	var hill_noon := _rgb(Backdrop.mix_hsl(150.0, 0.30, 0.42, 250.0, 0.3, 0.10, 0.0))
	approx(hill_noon.x, 0.294, "hill0 noon r", 1e-6)
	approx(hill_noon.y, 0.546, "hill0 noon g", 1e-6)
	var hill_mid := _rgb(Backdrop.mix_hsl(150.0, 0.30, 0.30, 250.0, 0.3, 0.10, 0.75))
	approx(hill_mid.x, 0.105, "hill0 midnight r", 1e-6)
	approx(hill_mid.z, 0.195, "hill0 midnight b", 1e-6)


func test_land_hill_h_pinned() -> void:
	# TS backdrop.ts:179 — sin(wx*1.7+s)*.45 + sin(wx*3.9+s*2)*.3 + sin(wx*.6+s)*.55
	approx(Backdrop.land_hill_h(0.0, 31.0), -0.6257918543, "hill_h(0,31)", 1e-9)
	approx(Backdrop.land_hill_h(100.0, 57.0), 0.2375391188, "hill_h(100,57)", 1e-9)
	approx(Backdrop.land_hill_h(333.0, 83.0), 0.6494472323, "hill_h(333,83)", 1e-9)
	# bounded: the weighted sin sum stays within ±1.3 for any input
	var bounded := true
	for k in 200:
		var wx := float(k) * 37.7
		if absf(Backdrop.land_hill_h(wx, 31.0)) > 1.3:
			bounded = false
	ok(bounded, "hill heights bounded (ridge amplitude sane)")


func test_land_star_pos_pinned_and_wrapped() -> void:
	# TS backdrop.ts:122-125 at vw 1152 vh 648 cam.x 0 (pinned via the TS hash;
	# eps 2e-4 — Vector2 stores float32: one ulp ≈ 1.2e-4 at magnitude ~1354)
	var p0 := Backdrop.land_star_pos(0, 1152.0, 648.0, 0.0)
	approx(p0.x, 164.4627372664, "star 0 x", 2e-4)
	approx(p0.y, 386.1194037823, "star 0 y", 2e-4)
	var p2 := Backdrop.land_star_pos(2, 1152.0, 648.0, 0.0)
	approx(p2.x, 571.1451975351, "star 2 x", 2e-4)
	approx(p2.y, 74.7675375064, "star 2 y", 2e-4)
	# cam parallax wraps modulo vw: cam.x = vw/0.03 shifts x by exactly -vw*k
	var shifted := Backdrop.land_star_pos(0, 1152.0, 648.0, 1152.0 / 0.03)
	approx(shifted.x, p0.x, "star x wraps with cam parallax", 2e-4)
	ok(shifted.x >= 0.0 and shifted.x < 1152.0, "star x inside [0, vw)")
	# deterministic: same inputs, same star
	var again := Backdrop.land_star_pos(0, 1152.0, 648.0, 0.0)
	approx(again.x, p0.x, "star deterministic (x)", 1e-9)
	approx(again.y, p0.y, "star deterministic (y)", 1e-9)


func test_land_cloud_pos_pinned_and_drifts() -> void:
	# TS backdrop.ts:154-156 at t=0 cam.x=0 — cxp is the POST-wrap value minus
	# the 300px spawn margin (cloud 0 sits right of the seam, cloud 1 in-band)
	var c0 := Backdrop.land_cloud_pos(0, 1152.0, 648.0, 0.0, 0.0)
	approx(c0.x, 1354.3517185471, "cloud 0 x", 2e-4)
	approx(c0.y, 171.1520185849, "cloud 0 y", 2e-4)
	var c1 := Backdrop.land_cloud_pos(1, 1152.0, 648.0, 0.0, 0.0)
	approx(c1.x, 137.4375405667, "cloud 1 x", 2e-4)
	# drift: t=10 moves cloud 1 right by its spd (6+i*2 = 8 per second) — the
	# mod span keeps it in-band unless the drift itself crosses the seam
	var c1b := Backdrop.land_cloud_pos(1, 1152.0, 648.0, 10.0, 0.0)
	approx(c1b.x, c1.x + 80.0, "cloud drifts at spd 8 px/s (in-band)", 2e-4)


func test_ground_stop_colors() -> void:
	# TS drawGround stops (backdrop.ts:271-283) at chaos 0.2 — pinned to the
	# hsl formulas AND to one literal (dirt top) against formula regressions
	var dirt0 := _rgb(RendererScript.hsl(95.0 - 0.2 * 40.0, 0.35, 0.32))
	approx(dirt0.x, 0.3312, "dirt stop0 r", 1e-6)
	approx(dirt0.y, 0.432, "dirt stop0 g", 1e-6)
	approx(dirt0.z, 0.208, "dirt stop0 b", 1e-6)
	var dirt1 := _rgb(RendererScript.hsl(88.0, 0.30, 0.24))
	approx(dirt1.y, 0.312, "dirt stop1 g", 1e-6)
	var dirt2 := _rgb(RendererScript.hsl(30.0, 0.25, 0.14))
	approx(dirt2.x, 0.175, "dirt stop2 r", 1e-6)
	var fringe := _rgb(RendererScript.hsl(105.0 - 0.2 * 30.0, 0.45, 0.34))
	approx(fringe.y, 0.493, "fringe g", 1e-6)
	var tuft := _rgb(RendererScript.hsl(110.0 - 0.2 * 30.0, 0.5, 0.4))
	approx(tuft.y, 0.6, "tuft g", 1e-6)


func test_lawn_gradient_stops() -> void:
	# TS CreatureStage.ts:1355-1357 (isNight false) — the pseudo-depth band
	var top := _rgb(RendererScript.hsl(105.0 - 0.2 * 30.0, 0.32, 0.30))
	approx(top.x, 0.2712, "lawn top r", 1e-6)
	approx(top.y, 0.396, "lawn top g", 1e-6)
	approx(top.z, 0.204, "lawn top b", 1e-6)
	var bot := _rgb(RendererScript.hsl(95.0 - 0.2 * 30.0, 0.38, 0.22))
	approx(bot.y, 0.3036, "lawn bottom g", 1e-6)
	# night darkening: isNight subtracts 0.12/0.10 lightness (TS:1356-1357) —
	# same hue/sat, lower lightness ⇒ strictly lower luminance
	var day_l := RendererScript.hsl(99.0, 0.32, 0.30)
	var night_l := RendererScript.hsl(99.0, 0.32, 0.18)
	ok(night_l.r + night_l.g + night_l.b < day_l.r + day_l.g + day_l.b,
			"night lawn darker than day")


func test_sun_moon_gradient_stops() -> void:
	# TS backdrop.ts:137-148 — the radial stops the fan reproduces
	var core := RendererScript.hsl(45.0, 1.0, 0.85, 0.9)
	approx(core.r, 1.0, "sun core r", 1e-6)
	approx(core.g, 0.925, "sun core g", 1e-6)
	var mid := RendererScript.hsl(40.0, 1.0, 0.7, 0.55)
	approx(mid.g, 0.8, "sun mid-stop g", 1e-6)
	var moon := RendererScript.hsl(220.0, 0.2, 0.92, 0.8)
	approx(moon.b, 0.936, "moon b", 1e-6)


func test_day_night_curve_shapes() -> void:
	# TS backdrop.ts:105-109 — sunH = sin(dayPhase·2π); dusk peaks at the seam
	var sun_h_noon := sin(0.25 * TAU)
	approx(sun_h_noon, 1.0, "noon sun height", 1e-9)
	var dusk := maxf(0.0, 1.0 - absf(sin(0.5 * TAU)) * 3.0)
	approx(dusk, 1.0, "dusk peaks at dayPhase .5", 1e-9)
	var dusk_noon := maxf(0.0, 1.0 - absf(1.0) * 3.0)
	approx(dusk_noon, 0.0, "no dusk at noon", 1e-9)
	# isNight window (CreatureStage.ts:1318): dayPhase in (0.55, 0.95)
	ok(0.7 > 0.55 and 0.7 < 0.95, "dayPhase .7 is night")
	ok(not (0.5 > 0.55 and 0.5 < 0.95), "dayPhase .5 is day")
