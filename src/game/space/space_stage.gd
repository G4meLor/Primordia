## SPACE STAGE scene node — the finale/sandbox system's visual layer over the
## SpaceSim sim core (headless, src/game/space/space_sim.gd). PART 1 (M6 task
## 4): the WORLD-SPACE render port — TS SpaceStage.ts :887-1025 verbatim order
## plus drawShip (:1124-1168) and drawPirate (:1170-1188) — and the scene-side
## update halves: the M2 input snapshot, the camera feed (TS :616-623) and the
## fx pool steps. Draw order (TS :887-1025): space backdrop (SCREEN, drawn
## with the REAL cam — not the civ fakeCam — seed 7) → [cam.begin] sun → orbit
## paths → black holes → planets → finale core → pirates → beam (the line on
## the world canvas + the rising specimen on its painter item) → ship → stage
## fx + game fx → [cam.end]. The T5 screen layer (colonies chip, ff tint,
## vignette, hull/cargo bars, the planet panel + its rect write-back, the
## ending veil/renderEnding) is NOT ported here (task 5).
##
## Draw architecture — the tribe_stage pattern (the rig doctrine): the
## Camera2D rig is ENABLED on enter and the VIEWPORT carries the camera
## transform, so the world canvases draw at identity in world coordinates and
## the sky canvas (the backdrop is screen-space) cancels the live viewport
## canvas_transform with affine_inverse(). Ownership: on_enter enables the
## rig, on_exit disables it again (menu/cell draw in absolute screen space).
## HEADER NOTE (the T3 doctrine scoping): everything in THIS task is
## world-space under the cam — NO node-transform cancellation is needed on
## the world layer; the cancellation doctrine (civ_stage._screen_inv) applies
## to T5's screen layer, which slots its ui canvas between the ship and veil
## canvases.
##
## Beam specimen draw protocol — the 3-RID painter contract (TS:1000-1014):
## the beam item is ONE CanvasItem per creature; the legs>0 branch repaints
## via the creature painter (three caller-owned sub-RIDs, freed at the top of
## every repaint and on teardown), the legs==0 branch paints via the cell
## painter directly on the item (a draw-call painter, no RIDs — the
## cell_painter contract). The item sits between the world and ship canvases
## so it draws after the beam line but under the ship/fx, exactly TS order.
##
## TWO FX POOLS (TS:53/:622-623/:1023-1024): the stage owns fx = Fx(1300) —
## the engine trail (TS:355 spawns into this.fx) and the pirate/zap bursts
## (TS:478/488/494) arrive through the sim's fx_spawn/fx_burst hooks into
## THIS pool (the sim replays the TS burst rng draws — the cell_sim
## precedent) — AND the shared game.fx pool rides along: updated per frame
## (TS:622, BEFORE the stage pool) and rendered after the ship (TS:1024).
##
## Camera numbers (TS SpaceStage.ts:616-617): follow(sx, sy, dt, 5) and
## zoom = 0.85 CONSTANT — the SPACE numbers, NOT the tribe's 4/0.95 or the
## creature's 5/1.15 (plan Global Constraints: per-stage constants, do not
## share).
##
## panel_rects (TS:1192): the planet-panel button rects are written by the
## STAGE each frame BEFORE sim.update — the write belongs to T5's
## renderPlanetPanel; T4 stubs it EMPTY every update so the sim's dispatch
## ladder no-ops gracefully (clicks pass through to the pirate shooting —
## the f1387fe contract).
##
## TS quirks ported AS-IS (parity-pin ledger, each commented at its site):
##  - the ship draws when !endingDone || endingDismissed INSIDE the cam scope
##    (:1017-1021) — the TS ending-block draw sat after cam.end() and never
##    showed; the placement comment is the pin.
##  - the black-hole gradient's mid stop rides at 0.4 OF THE SPAN (2→90):
##    radius 37.2, not 36 (TS:913-916).
##  - the hurt flash alpha REPLACES the blink alpha (a fresh globalAlpha
##    assignment, TS:1161), it does not multiply it.
##  - the colony '★ thriving' label is NOT t()-wrapped (TS:956) — raw.
##  - the beam specimen rides eco.living()[0] — the FIRST living species only
##    (TS:1000); an empty roster draws the line alone.
##  - the planet shadow gradient's center is OFFSET (−0.35r, −0.35r) from the
##    disc center — a two-circle canvas gradient ported as a vertex-colored
##    fan evaluated per vertex (the civ ocean Gouraud precedent; 48 segments).
##  - the game fx pool ticks TWICE per frame while a space stage runs (the
##    game loop's step + TS:622) — TS-verbatim (the tribe port kept the same
##    double step; game.ts:290 + the stage's own this.game.fx.update).
extends "res://src/game/stage.gd"

const SpaceSimScript := preload("res://src/game/space/space_sim.gd")
const ParticlesScript := preload("res://src/gfx/particles.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")
const BackdropScript := preload("res://src/gfx/backdrop.gd")
const CreaturePainter := preload("res://src/gfx/creature_painter.gd")
const CellPainterScript := preload("res://src/gfx/cell_painter.gd")
const HudScript := preload("res://src/ui/hud.gd")
const PauseScript := preload("res://src/ui/pause.gd")

## TS:892 — drawSpaceBackdrop's seed argument on the space call (civ used 42).
const BACKDROP_SEED := 7.0

var sim: Variant = null           # SpaceSim (RefCounted sim core)
var fx: Variant = null            # stage Particles pool (TS `new Fx(1300)`)
var frozen := false               # test seam: render without stepping the sim
## The overlay instances — installed into the game stub dicts at tree entry
## and re-installed on enter (the creature/tribe/civ stage pattern).
var hud_inst: Variant = null
var pause_inst: Variant = null

var sky_canvas: Node2D = null
var world_canvas: Node2D = null
var beam_item: BeamItem = null
var ship_canvas: Node2D = null
var veil_canvas: Node2D = null
var hud_canvas: Node2D = null
var pause_canvas: Node2D = null


class StageCanvas extends Node2D:
	var stage: Variant = null
	var layer := "world"
	func _draw() -> void:
		if stage != null:
			stage._draw_layer(layer, self)


## The beam's rising specimen (TS:998-1014) — one painter item per creature
## (the 3-RID contract): legs > 0 → the creature painter (three caller-owned
## sub-RIDs, freed per repaint + PREDELETE); legs == 0 → the cell painter
## draws directly on this item. genome empty = the beam gate is closed —
## nothing draws. Draws at identity in WORLD coordinates (the enabled rig
## carries the camera; the pose carries x/y).
class BeamItem extends Node2D:
	var genome: Dictionary = {}
	var pose: Dictionary = {}
	var opts: Dictionary = {}
	var is_cell := false
	var _rids: Array = []

	func _draw() -> void:
		for rid in _rids:
			RenderingServer.free_rid(rid)
		_rids = []
		if genome.is_empty():
			return
		if is_cell:
			CellPainterScript.draw_cell(self, genome, pose, opts)
		else:
			var res: Dictionary = CreaturePainter.draw_creature(self, genome, pose, opts)
			_rids = [res["clip_item"], res["pattern_item"], res["front_item"]]

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			for rid in _rids:
				RenderingServer.free_rid(rid)
			_rids = []


func _init(game_v: Variant) -> void:
	super(game_v, "space")


func _ready() -> void:
	_install_overlays()
	# stage pool cap 1300 (TS `private fx = new Fx(1300)`); the game pool
	# (1100) hangs off game.fx
	fx = ParticlesScript.new(1300)
	# the CALLER draws the stage rng branch (sim header contract, mirrors
	# TS `this.rng = game.context.rng.branch()` in the SpaceStage constructor)
	sim = SpaceSimScript.new(game.context, game.context.rng.branch(), _build_hooks())

	# TS draw-path parity (see header): world canvases draw at identity and the
	# enabled Camera2D carries the transform. The rig boots disabled (menu/cell
	# own the screen-space default) — THIS stage turns it on in on_enter and
	# off again in on_exit.
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = false

	# tree order = the TS draw order: sky (backdrop) → world (sun..beam line)
	# + the beam specimen item → ship (ship + both fx pools) → [T5 slots the
	# ui canvas HERE] → veil → hud → pause
	sky_canvas = StageCanvas.new()
	sky_canvas.stage = self
	sky_canvas.layer = "sky"
	sky_canvas.name = "SkyCanvas"
	add_child(sky_canvas)
	world_canvas = StageCanvas.new()
	world_canvas.stage = self
	world_canvas.layer = "world"
	world_canvas.name = "WorldCanvas"
	add_child(world_canvas)
	beam_item = BeamItem.new()
	beam_item.name = "BeamItem"
	world_canvas.add_child(beam_item)
	ship_canvas = StageCanvas.new()
	ship_canvas.stage = self
	ship_canvas.layer = "ship"
	ship_canvas.name = "ShipCanvas"
	add_child(ship_canvas)
	# the TS game-level transition overlay slots between the stage's UI and
	# the hud (native draw-order ruling — see cell_stage.gd's header)
	veil_canvas = StageCanvas.new()
	veil_canvas.stage = self
	veil_canvas.layer = "veil"
	veil_canvas.name = "VeilCanvas"
	add_child(veil_canvas)
	hud_canvas = StageCanvas.new()
	hud_canvas.stage = self
	hud_canvas.layer = "hud"
	hud_canvas.name = "HudCanvas"
	add_child(hud_canvas)
	pause_canvas = StageCanvas.new()
	pause_canvas.stage = self
	pause_canvas.layer = "pause"
	pause_canvas.name = "PauseCanvas"
	pause_canvas.visible = false
	add_child(pause_canvas)


## The overlay wiring (the tribe/civ stage's _install_overlays verbatim).
## Called from _ready (first build) AND on_enter (rebind).
func _install_overlays() -> void:
	if hud_inst == null:
		hud_inst = HudScript.new(game)
	game.hud = {
		"update": hud_inst.update,
		"dismiss_banner": hud_inst.dismiss_banner,
		"toast": hud_inst.toast,
		"banner": hud_inst.banner,
		"float_world": hud_inst.float_world,
		"pointer_down": hud_inst.pointer_down,
		"set_abilities": hud_inst.set_abilities,
		# TS game.ts:213 — the game-level switch reset routes through this key
		"set_toast_inset": hud_inst.set_toast_inset,
	}
	if pause_inst == null:
		pause_inst = PauseScript.new(game)
	pause_inst.actions = {
		"close_pause": game.close_pause,
		"save_all": game.save_all,
		"toggle_mute": game.toggle_mute,
		"go_to": game.go_to,
		"toast": _pause_toast,
	}
	game.pause = {
		"open": pause_inst.open,
		"update": pause_inst.update,
	}


func _pause_toast(text: String, kind: String, icon: String) -> void:
	game.hud["toast"].call(text, kind, icon)


## Per-layer draw dispatch (StageCanvas._draw).
func _draw_layer(kind: String, ci: CanvasItem) -> void:
	match kind:
		"sky":
			_draw_sky(ci)
		"world":
			_draw_world(ci)
		"ship":
			_draw_ship_layer(ci)
		"veil":
			# screen space under the enabled rig — cancel the camera transform
			ci.draw_set_transform_matrix(_screen_inv())
			game.draw_transition_veil(ci)
		"hud":
			if hud_inst != null:
				ci.draw_set_transform_matrix(_screen_inv())
				hud_inst.draw(ci, game.vw, game.vh)
		"pause":
			if pause_inst != null and bool(game.paused):
				ci.draw_set_transform_matrix(_screen_inv())
				pause_inst.draw(ci, game.vw, game.vh)


## The inverse of the LIVE viewport canvas transform: world-screen space maps
## 1:1 onto draw coordinates (TS screen space). Reads the applied transform
## instead of re-deriving it — exact for whatever the Camera2D does.
func _screen_inv() -> Transform2D:
	var vp := get_viewport()
	if vp == null:
		return Transform2D()
	return vp.canvas_transform.affine_inverse()


# ---- pure geometry seams (the draw sites consume these; the scene test pins
# the live production values — no copies) ---------------------------------------

## TS:931-934 — the planet shadow gradient evaluated at distance d from the
## OFFSET gradient center. Span r0 = 0.2r → r1 = r; stops 0 / 0.7 / 1:
## hsl(hue,0.55,0.55) / hsl(hue,0.5,0.32) / hsl(hue,0.5,0.14). Static seam —
## the draw site consumes this, the scene test pins the ladder.
static func planet_shadow_col(hue: float, d: float, r: float) -> Color:
	var r0 := r * 0.2
	var mid := r0 + 0.7 * (r - r0)
	if d <= r0:
		return RendererScript.hsl(hue, 0.55, 0.55)
	if d <= mid:
		return RendererScript.hsl(hue, 0.55, 0.55).lerp(
				RendererScript.hsl(hue, 0.5, 0.32), (d - r0) / (mid - r0))
	if d >= r:
		return RendererScript.hsl(hue, 0.5, 0.14)
	return RendererScript.hsl(hue, 0.5, 0.32).lerp(
			RendererScript.hsl(hue, 0.5, 0.14), (d - mid) / (r - mid))


## TS:989-997 — the beam's linear-gradient line ports as a vertex-colored
## quad (the Gouraud ≈ gradient precedent): perpendicular ± lw/2 at both
## ends. Vertex colors at the draw site: 0/3 ship-side, 1/2 planet-side.
## Static seam — the draw site consumes this.
static func beam_quad(s: Vector2, e: Vector2, lw: float) -> PackedVector2Array:
	var dir := (e - s).normalized() if s.distance_to(e) > 0.0001 else Vector2(0, -1)
	var perp := Vector2(-dir.y, dir.x)
	var hw := lw / 2.0
	return PackedVector2Array([
		s + perp * hw, e + perp * hw, e - perp * hw, s - perp * hw])


## TS:1132-1136 — the ship hull path: moveTo(0,−18) → quad(12,2 → 8,14) →
## lineTo(−8,14) → quad(−12,2 → 0,−18). Canvas quadraticCurveTo ports as a
## sampled polyline (the tribe trunk precedent). Static seam — the draw site
## consumes this.
static func hull_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(0, -18))
	_quad_into(pts, Vector2(0, -18), Vector2(12, 2), Vector2(8, 14))
	pts.append(Vector2(-8, 14))
	_quad_into(pts, Vector2(-8, 14), Vector2(-12, 2), Vector2(0, -18))
	return pts


## Quadratic-bezier samples for u ∈ (0, 1] appended — the caller owns the
## start point (the hull chains two quads off a moveTo/lineTo).
static func _quad_into(pts: PackedVector2Array, p0: Vector2, ctrl: Vector2,
		p1: Vector2, segs := 6) -> void:
	for k in range(1, segs + 1):
		var u := float(k) / float(segs)
		var q0 := (1.0 - u) * (1.0 - u)
		var q1 := 2.0 * (1.0 - u) * u
		var q2 := u * u
		pts.append(Vector2(
			q0 * p0.x + q1 * ctrl.x + q2 * p1.x,
			q0 * p0.y + q1 * ctrl.y + q2 * p1.y))


## TS:1019 — the ship draws while the ending hasn't fired, or after the
## dismissal handed the sandbox back. Static seam — the draw site consumes
## this; the scene test pins the truth table.
static func ship_visible(ending_done: bool, ending_dismissed: bool) -> bool:
	return not ending_done or ending_dismissed


# ---- TS render() world sections (:887-1025) ---------------------------------------

## TS:892 — drawSpaceBackdrop BEFORE cam.begin with the REAL cam (space has
## no drift camera — the civ fakeCam divergence does not apply) and seed 7.
## Screen space: the transform cancels the live rig (identity while the rig
## is parked, the inverse of the camera while it flies).
func _draw_sky(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_screen_inv())
	BackdropScript.draw_space_backdrop(ci, game.cam, game.vw, game.vh, sim.time,
			BACKDROP_SEED)


## TS:896-1015 world sections (inside cam.begin): sun → orbit paths → black
## holes → planets → finale core → pirates → the beam LINE. Draws at identity
## in WORLD coordinates (the enabled rig carries the camera). The beam's
## rising specimen rides the beam_item child — children render after this
## item's own commands but under the ship canvas, exactly TS order.
func _draw_world(ci: CanvasItem) -> void:
	# sun — TS:896-900 (pulse 1 + sin(time·2)·0.03; glow r·3·pulse; two discs)
	var sun: Dictionary = sim.sun
	var sun_x := float(sun["x"])
	var sun_y := float(sun["y"])
	var pulse := 1.0 + sin(sim.time * 2.0) * 0.03
	RendererScript.glow(ci, sun_x, sun_y, float(sun["r"]) * 3.0 * pulse,
			RendererScript.css_color("rgba(255,200,90,0.4)"), 0.7)
	RendererScript.disc(ci, sun_x, sun_y, float(sun["r"]), RendererScript.hsl(45.0, 1.0, 0.65))
	RendererScript.disc(ci, sun_x, sun_y, float(sun["r"]) * 0.85, RendererScript.hsl(50.0, 1.0, 0.8))

	# orbit paths — TS:902-909 (arcs at orbitR around the origin)
	for p in sim.planets:
		ci.draw_arc(Vector2.ZERO, float(p["orbitR"]), 0.0, TAU, 96,
				RendererScript.css_color("rgba(140,170,255,0.08)"), 1.0)

	# black holes — TS:911-926 (the 3-stop radial 2→90: the mid stop rides at
	# 0.4 OF THE SPAN → radius 37.2; the outer band paints first so the inner
	# band's solid core repaints over it — radial_disc is solid inside r0)
	for bh in sim.blackHoles:
		var bp := Vector2(float(bh["x"]), float(bh["y"]))
		var mid_r := 2.0 + 0.4 * (90.0 - 2.0)
		RendererScript.radial_disc(ci, bp, mid_r, 90.0,
				RendererScript.css_color("rgba(80,40,160,0.8)"), Color(0.0, 0.0, 0.0, 0.0))
		RendererScript.radial_disc(ci, bp, 2.0, mid_r,
				Color("#000000"), RendererScript.css_color("rgba(80,40,160,0.8)"))
		# the rotating arc — r 46 + sin(time·5)·5, from time to time+4
		ci.draw_arc(bp, 46.0 + sin(sim.time * 5.0) * 5.0, sim.time, sim.time + 4.0, 48,
				RendererScript.css_color("rgba(180,120,255,0.5)"), 2.0)

	# planets — TS:928-962
	for p in sim.planets:
		_draw_planet(ci, p)

	# finale core — TS:964-979
	if sim.finale != null:
		_draw_finale(ci, sim.finale)

	# pirates — TS:981-984
	for pir in sim.pirates:
		_draw_pirate(ci, pir)

	# beam — TS:986-997 (the rising specimen rides beam_item, synced in
	# render(); the LINE is a vertex-colored quad, ship-side 0.9 → planet 0.2)
	if sim.beamT > 0.0 and sim.beamTarget != null:
		var p2: Dictionary = sim.beamTarget
		var s := Vector2(sim.sx, sim.sy)
		var e := Vector2(float(p2["x"]), float(p2["y"]))
		if s.distance_to(e) > 0.0001:
			var lw := 10.0 + sin(sim.time * 30.0) * 4.0
			var c0 := RendererScript.css_color("rgba(150,220,255,0.9)")
			var c1 := RendererScript.css_color("rgba(150,220,255,0.2)")
			ci.draw_polygon(beam_quad(s, e, lw), PackedColorArray([c0, c1, c1, c0]))


## TS:929-962 — one planet: the shadow-side gradient fill (the gradient center
## is OFFSET (−0.35r, −0.35r) — a vertex-colored fan per the civ ocean
## precedent), the ring (rotate 0.4, ellipse 1.7r × 0.5r, lw 6), the
## atmosphere rim glow, the colony 🏳 bob + ★ thriving, the scanned label.
func _draw_planet(ci: CanvasItem, p: Dictionary) -> void:
	var px := float(p["x"])
	var py := float(p["y"])
	var r := float(p["r"])
	var hue := float(p["hue"])
	# shadow side — TS:930-938
	var pc := Vector2(px, py)
	var gc := pc + Vector2(-0.35, -0.35) * r
	var segs := 48
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.append(pc)
	cols.append(planet_shadow_col(hue, pc.distance_to(gc), r))
	for i in segs:
		var a := (float(i) / float(segs)) * TAU
		var v := pc + Vector2(cos(a), sin(a)) * r
		pts.append(v)
		cols.append(planet_shadow_col(hue, v.distance_to(gc), r))
	ci.draw_polygon(pts, cols)
	# ring — TS:939-949 (translate+rotate 0.4 → the ellipse points carry the rot)
	if bool(p["ring"]):
		var ring := RendererScript.ellipse_points(pc, r * 1.7, r * 0.5, 0.4, 48)
		ring.append(ring[0])  # a full-ellipse stroke closes the loop
		ci.draw_polyline(ring, RendererScript.hsl(hue + 30.0, 0.4, 0.6, 0.5), 6.0, true)
	# atmosphere rim — TS:951
	RendererScript.glow(ci, px, py, r * 1.3, RendererScript.hsl(hue, 0.7, 0.6, 0.4), 0.5)
	# colony marker — TS:953-957 (bob sin(time·2 + id)·3)
	if p["colony"] != null:
		var col: Dictionary = p["colony"]
		var bob := sin(sim.time * 2.0 + float(p["id"])) * 3.0
		RendererScript.outlined_text(ci, "🏳 %d" % roundi(float(col["pop"])),
				px, py - r - 16.0 + bob, {"size": 11.0, "fill": Color("#9fe89a")})
		if float(col["pop"]) >= 20.0:
			# '★ thriving' is NOT t()-wrapped in TS (:956) — raw
			RendererScript.outlined_text(ci, "★ thriving", px, py - r - 30.0 + bob,
					{"size": 9.0, "fill": Color("#ffe08a")})
	# scanned label — TS:959-961 (the name when scanned && !colony)
	if bool(p["scanned"]) and p["colony"] == null:
		RendererScript.outlined_text(ci, String(p["name"]), px, py - r - 14.0,
				{"size": 10.0, "fill": RendererScript.css_color("rgba(180,210,255,0.6)")})


## TS:965-978 — the chaos core: pulse glow + two discs + 3 orbit arcs
## (r 40+i·16, from a = t·(1+i·0.4)+i·2.1 spanning 2.4).
func _draw_finale(ci: CanvasItem, f: Dictionary) -> void:
	var fp := Vector2(float(f["x"]), float(f["y"]))
	var ft := float(f["t"])
	var pulse := 1.0 + sin(ft * 3.0) * 0.2
	RendererScript.glow(ci, fp.x, fp.y, 140.0 * pulse,
			RendererScript.css_color("rgba(255,90,200,0.5)"), 0.9)
	RendererScript.disc(ci, fp.x, fp.y, 26.0 * pulse, RendererScript.hsl(320.0, 1.0, 0.7))
	RendererScript.disc(ci, fp.x, fp.y, 14.0, Color("#fff"))
	for i in 3:
		var a := ft * (1.0 + float(i) * 0.4) + float(i) * 2.1
		ci.draw_arc(fp, 40.0 + float(i) * 16.0, a, a + 2.4, 48,
				RendererScript.hsl(300.0 + float(i) * 30.0, 1.0, 0.7, 0.7), 2.0)


## TS:1170-1188 — drawPirate: the 4-point hull aimed at the ship (atan2 + π/2),
## then — OUTSIDE the rotation (TS restore) — the glow + ☠ marker.
func _draw_pirate(ci: CanvasItem, p: Dictionary) -> void:
	var pp := Vector2(float(p["x"]), float(p["y"]))
	ci.draw_set_transform(pp, atan2(sim.sy - pp.y, sim.sx - pp.x) + PI / 2.0)
	var hull := PackedVector2Array([
		Vector2(0, -14), Vector2(11, 10), Vector2(0, 5), Vector2(-11, 10)])
	ci.draw_colored_polygon(hull, Color("#6a3a3a"))
	var closed := hull.duplicate()
	closed.append(hull[0])
	ci.draw_polyline(closed, Color("#3a1a1a"), 1.0, true)
	ci.draw_set_transform(Vector2.ZERO)  # TS restore
	RendererScript.glow(ci, pp.x, pp.y, 20.0,
			RendererScript.css_color("rgba(255,90,60,0.4)"), 0.6)
	RendererScript.outlined_text(ci, "☠", pp.x, pp.y - 22.0,
			{"size": 11.0, "fill": Color("#ffb0a0")})


## TS:1017-1024 — the ship (the visibility seam below; the TS placement
## comment is the parity pin: the ending-block draw sat after cam.end() and
## never showed — after dismissal it returns HERE), then BOTH fx pools in
## world space (the stage pool, then the shared game pool).
func _draw_ship_layer(ci: CanvasItem) -> void:
	if ship_visible(sim.endingDone, sim.endingDismissed):
		_draw_ship(ci)
	fx.render(ci)
	game.fx["render"].call(ci)


## TS:1124-1168 — drawShip: blink (invuln > 0 && floor(time·10)%2 — alpha
## 0.5), translate(sx, sy) rotate(shipAngle + π/2), the two-quad hull, the
## cockpit ellipse, the two wing triangles, the hurt flash disc (the flash
## alpha REPLACES the blink alpha — TS:1161).
func _draw_ship(ci: CanvasItem) -> void:
	var blink: bool = sim.invuln > 0.0 and floori(sim.time * 10.0) % 2 == 0
	var alpha := 0.5 if blink else 1.0
	ci.draw_set_transform(Vector2(sim.sx, sim.sy), sim.shipAngle + PI / 2.0)
	# hull — TS:1131-1140
	var hull := hull_points()
	var fill := Color("#cfe0f0")
	fill.a *= alpha
	ci.draw_colored_polygon(hull, fill)
	var closed := hull.duplicate()
	closed.append(hull[0])
	var stroke := Color("#5a7a9a")
	stroke.a *= alpha
	ci.draw_polyline(closed, stroke, 1.5, true)
	# cockpit — TS:1142-1145
	var cock := RendererScript.hsl(200.0, 0.8, 0.65)
	cock.a *= alpha
	ci.draw_colored_polygon(
			RendererScript.ellipse_points(Vector2(0, -4), 4.5, 6.0, 0.0, 16), cock)
	# wings — TS:1147-1158
	var wing := Color("#8fb0cc")
	wing.a *= alpha
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(-8, 6), Vector2(-17, 15), Vector2(-7, 13)]), wing)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(8, 6), Vector2(17, 15), Vector2(7, 13)]), wing)
	if sim.hurtT > 0.0:
		var flash := Color("#ff8a7a")
		flash.a = sim.hurtT * 0.7
		ci.draw_circle(Vector2.ZERO, 20.0, flash)
	ci.draw_set_transform(Vector2.ZERO)  # TS restore


## Per-frame draw hook (Game's render side): sync the beam specimen, queue
## all canvases.
func render() -> void:
	if sky_canvas == null or sim == null:
		return
	_sync_beam_item()
	sky_canvas.queue_redraw()
	world_canvas.queue_redraw()
	ship_canvas.queue_redraw()
	veil_canvas.queue_redraw()
	hud_canvas.queue_redraw()
	pause_canvas.visible = bool(game.paused)
	if pause_canvas.visible:
		pause_canvas.queue_redraw()


## TS:998-1014 — the beam's rising specimen syncs HERE (draw-time state): the
## FIRST living species of the beam target (TS `p.eco?.living[0]`), drawn at
## the beam midpoint minus t·30, t = 1 − beamT/1.4. legs > 0 → the creature
## pose (facing 1, gait time·8, airborne, mood 'afraid', scale 1.2); else the
## cell pose (scale 1.6, seed 4 — verbatim).
func _sync_beam_item() -> void:
	beam_item.genome = {}
	beam_item.pose = {}
	beam_item.opts = {}
	if sim.beamT > 0.0 and sim.beamTarget != null:
		var p: Dictionary = sim.beamTarget
		var living: Array = []
		if p["eco"] != null:
			living = p["eco"].living()
		if not living.is_empty():
			var sp: Dictionary = living[0]
			var g: Dictionary = sp["genome"]
			var t: float = 1.0 - float(sim.beamT) / 1.4
			var bx: float = (float(sim.sx) + float(p["x"])) / 2.0
			var by: float = (float(sim.sy) + float(p["y"])) / 2.0 - t * 30.0
			beam_item.genome = g
			beam_item.opts = {"t": sim.time}
			if int(g.get("legs", 0)) > 0:
				beam_item.is_cell = false
				beam_item.pose = {
					"x": bx, "y": by, "facing": 1.0, "speed": 0.2,
					"gaitPhase": sim.time * 8.0, "attack": 0.0, "hurt": 0.0,
					"eat": 0.0, "airborne": 1.0, "mood": "afraid", "scale": 1.2,
				}
			else:
				beam_item.is_cell = true
				beam_item.pose = {
					"x": bx, "y": by, "moveAngle": 0.0, "speed": 0.2,
					"scale": 1.6, "hurt": 0.0, "eat": 0.0, "dash": 0.0, "seed": 4.0,
				}
	beam_item.queue_redraw()


# ---- update (the TS:301-632 scene-side halves) ---------------------------------------

## The Game loop's fixed-step accumulator calls this. TS order verbatim: the
## panel_rects write-back lands BEFORE sim.update, then the M2 snapshot feeds
## sim.update, the consumed click mirrors to the wrapper, the camera feed
## follows (:616-621) and the fx pools step (:622-623).
func update(dt: float) -> void:
	if sim == null or frozen:
		return
	# panel_rects write-back — TS:1192 rides the RENDER side (renderPlanetPanel,
	# task 5): the write lands each frame BEFORE sim.update (one frame of
	# positional lag, TS-identical). T4 stubs it EMPTY so the sim's dispatch
	# ladder no-ops gracefully (clicks pass through to the pirate shooting —
	# the f1387fe contract; the T5 panel task completes the write).
	sim.panel_rects = []
	var inp: Dictionary = _build_input_snapshot()
	sim.update(dt, inp)
	# a sim-consumed click (panel/pirate) mirrors TS inp.takeClick() mutating
	# the SHARED input — the wrapper's one-shot clears so the next frame's
	# snapshot never re-sees it (the tribe precedent)
	if bool(inp.get("take_click", false)):
		game.input.take_click()
	# camera feed — TS:616-621 (the SPACE numbers: follow rate 5, zoom 0.85)
	game.cam.follow(sim.sx, sim.sy, dt, 5.0)
	game.cam.zoom = 0.85
	var wpt: Vector2 = game.cam.to_world(game.input.mx, game.input.my, game.vw, game.vh)
	game.input.set_world(wpt.x, wpt.y)
	# fx pools — TS:622-623 (the game pool first, then the stage pool)
	game.fx["update"].call(dt)
	fx.update(dt)


# ---- hooks (SpaceSim → scene/game/storyteller) ---------------------------------------

func _build_hooks() -> Dictionary:
	return {
		"hud_toast": _h_hud_toast,
		"hud_banner": _h_hud_banner,
		"hud_show_objective": _h_hud_show_objective,
		"hud_float_world": _h_hud_float_world,
		"hud_set_abilities": _h_hud_set_abilities,
		"audio_play": _h_audio_noop,
		"audio_set_mood": _h_audio_noop,
		"cam_shake": _h_cam_shake,
		"fx_spawn": _h_fx_spawn,
		"fx_burst": _h_fx_burst,
		"set_cursor": _h_set_cursor,
		"get_gap_bias": _h_gap_bias,
		"get_mood": _h_mood,
		"get_warn_scale": _h_warn_scale,
		"storyteller_note_chaos_event": _h_note_chaos_event,
		"go_to": _h_go_to,
		"save_all": _h_save_all,
	}


func _h_hud_toast(text: String, kind: String, icon: String) -> void:
	game.hud["toast"].call(text, kind, icon)


func _h_hud_banner(data: Variant) -> void:
	game.hud["banner"].call(data)


func _h_hud_show_objective(text: String) -> void:
	if hud_inst != null:
		hud_inst.show_objective = text


func _h_hud_float_world(x: float, y: float, text: String, color: Variant, size: float) -> void:
	game.hud["float_world"].call(x, y, text, color, size)


func _h_hud_set_abilities(list: Array) -> void:
	# TS:626-631 — the sim fires ONE list arg at the END of every update; the
	# stage only bridges it to the hud (the payload is the sim's, pinned there)
	game.hud["set_abilities"].call(list)


func _h_audio_noop(_name: String, _vol := 0.0, _pan := 0.0) -> void:
	pass  # audio core is its own task — the sim's audio hooks stay silent


func _h_cam_shake(mag: float, dur: float) -> void:
	game.cam_shake_for(mag, dur)


func _h_fx_spawn(opts: Variant) -> void:
	# TS:355 — the engine trail spawns into THIS stage's pool (world coords)
	fx.spawn(opts)


func _h_fx_burst(x: float, y: float, n: int, opts: Variant) -> void:
	# TS:478/488/494 — the pirate/zap bursts; the sim already replayed the TS
	# burst rng draws and ships the sampled rows (the cell_sim precedent)
	fx.burst_rows(x, y, n, opts)


func _h_set_cursor(state: String) -> void:
	# TS:399/410 — the sim's panel-hover pointer. The native base resolution
	# sits at the END of the frame (the X11 shape law), so the pointer must
	# ride the hover-marked path or the crosshair base overwrites it.
	if state == "pointer":
		game.hover_cursor()
	else:
		game.set_cursor(state)


func _h_gap_bias() -> float:
	return game.storyteller.gap_bias()


func _h_mood() -> String:
	return game.storyteller.mood


func _h_warn_scale() -> float:
	return game.storyteller.warn_scale()


func _h_note_chaos_event(playtime: float) -> void:
	game.storyteller.note_chaos_event(playtime)


## The fall/victory stage handoffs (parity — the sim fires neither today;
## the civ pattern binds them anyway). 'space' itself stays unregistered in
## main.gd until its milestone (switch_stage silently no-ops, TS-true).
func _h_go_to(id: String, card: Variant) -> void:
	game.go_to(id, card)


func _h_save_all() -> void:
	game.save_all()


func has_active_chaos() -> bool:
	return sim != null and sim.has_active_chaos()


func on_enter(from: Variant = null) -> void:
	_install_overlays()
	if sim == null:
		return
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = true  # cam.begin arms here — the rig carries the world layer
	sim.on_enter()


func on_exit() -> void:
	if sim != null:
		sim.on_exit()
	# rig ownership: restore the disabled default the other stages expect
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = false


## TS SpaceStage.onExit → persistState — the autosave flush seam
## (game.save_all()/the 60s autosave call current.persist_state()).
func persist_state() -> void:
	if sim != null:
		sim.persist_state()


# ---- input snapshot ----------------------------------------------------------------

## The M2 canonical snapshot (space_sim.update contract): keys_pressed/
## keys_held built from the GameInput wrapper — one-shots from the frame state
## (cleared by end_frame AFTER this in Game._do_update), held codes polled
## live. wx/wy were set by the PREVIOUS frame's cam.to_world (TS-identical:
## TS update reads the world coords the previous update wrote). take_click
## starts false on every FRESH dict — the sim consumes via inp["take_click"]
## on this by-reference copy (the f1387fe contract).
func _build_input_snapshot() -> Dictionary:
	var held: Array = []
	for code in game.input.CODES:
		if game.input.key(code):
			held.append(code)
	return {
		"mx": game.input.mx, "my": game.input.my,
		"wx": game.input.wx, "wy": game.input.wy,
		"down": game.input.down,
		"clicked": game.input.was_clicked(),
		"take_click": false,
		"keys_held": held,
		"keys_pressed": game.input.keys_pressed.keys(),
	}
