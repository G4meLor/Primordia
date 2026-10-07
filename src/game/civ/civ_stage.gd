## CIV STAGE scene node — the grand-strategy layer's visual binding over the
## CivSim sim core (headless, src/game/civ/civ_sim.gd). Port of Spore
## src/game/civ/CivStage.ts render() (:530-662) + the scene-side halves of
## the update flow: the M2 input SNAPSHOT feeding sim.update, the hook dict
## bridging the sim to the real game/hud seams, and the full TS draw order:
## space backdrop (fakeCam x = camX·0.3, y = camY·0.3, strength/seed 42) →
## planet ocean radial gradient (offset light center (−pr·0.3, −pr·0.3),
## inner r pr·0.2, hsl(200,0.5,0.35) → hsl(220,0.55,0.16)) at
## (vw/2 − camX·0.5, vh/2 − camY·0.5 + 40), r = min(vw,vh)·0.42 → 7 continent
## blobs (a = i·2.4 + 0.7, rr = pr·(0.25 + (i%3)·0.18), ellipse rr × rr·0.7
## rotated a, hsl(100 + i·14, 0.3, 0.3)) → atmosphere rim glow(pr·1.18,
## rgba(120,190,255,0.35), 0.55) → armadas (disc 4 kind-colored + glow 10 0.6
## + dashed trail [4,6] alpha 0.25 target-screen → ship-screen) → cities
## (disc 9 + glow 22 0.5 owner-colored + name + 👑 yours/rival name +
## influence bar 64×6 + hp bar 64×4 + burning glow 26) → ruler portrait
## (panel (18, vh−120, 96, 96) + clip rect (22, vh−116, 88, 88) +
## draw_creature(scale 1.4, mood 'happy') — the 3-RID painter contract) →
## sliders panel ((vw−318, vh−150) 300×132, three Q/A·W/S·E/D bars with
## round-rect tracks) → launch hints → victory shimmer (all owned →
## 'THE PLANET IS UNITED') → vignette 0.5.
##
## Draw architecture — the drift camera (TS:279-287) lives IN THE SIM
## (camX/camY sim floats, advanced in update); the stage renders FROM them.
## There is NO Cam object and NO cam.begin/end: the whole render is
## screen-space (TS never enters a camera scope on this stage), so the
## canvases cancel the live viewport canvas_transform with affine_inverse()
## (the M3 Part B doctrine, the tribe/creature screen-canvas pattern). The
## cam rig's Camera2D IS current on this stage (the game owns it from boot,
## anchor drag-center → canvas_transform = translate(vw/2, vh/2) even with
## the rig parked at (0,0) zoom 1), so the cancellation is LOAD-BEARING:
## every screen-space subtree must go through it — the canvases via
## draw_set_transform_matrix in _draw, the portrait node subtree via its
## node transform (render()).
##
## The ruler portrait clip: TS ctx.clip(rect) ports as the node-level
## clip_children group (PortraitItem.clip_children = CLIP_CHILDREN_AND_DRAW,
## its own _draw content — the mask rect — IS the clip shape; the creature
## rides a CHILD painter item so the whole painter subtree (back content +
## clip/pattern/front RIDs) clips). The mask rect fills with the panel color
## at FULL alpha — the group mask multiplies child alpha (the task-6
## divergence note), so a 0.9 mask would dim the creature to 90%; the cost is
## the clip region compositing the panel fill once more (over the 0.9 panel
## the delta is the 10% backdrop bleed through an 88×88 window of near-black
## vignette'd space — presence-invisible; the 4px inset ring keeps the TS 0.9).
##
## The update flow (TS:177-305 order): the stage builds the M2 snapshot each
## fixed step (the Game loop's accumulator calls update(dt); civ reads
## keys_pressed ONLY — Q/A/W/S/E/D sliders, Digit1/2/3 launches; the mouse
## fields ride along unused — the sim has no hudRects), calls
## sim.update(dt, inp), and the sim's hud_set_abilities hook (TS:298-305,
## fired at the END of update) lands on the hud via the stage's binding.
##
## TS quirks ported AS-IS (parity-pin ledger, each commented at its site):
##  - the fakeCam zeroes shx/shy (TS:535) — cam_shake_for calls are VISUALLY
##    INERT on this stage: the hook still forwards to game.cam_shake_for (the
##    live Cam shakes), but no rig carries the viewport and the backdrop's
##    fakeCam reads only x/y. Kept, commented.
##  - the sim's fx_spawn payloads carry RAW map coords (the trail dots and
##    the resolve ring) while hud_float_world IS toScreen-corrected — the
##    asymmetry is the sim's (TS:243/:374 spawn into game.fx; TS:372 corrects
##    the float by hand). The stage only passes the hook through to the game
##    fx pool (TS civ spawns into game.fx — there is NO stage-level pool).
##  - the game fx pool is NEVER rendered on this stage (TS CivStage.render
##    has no fx.render call — game.ts updates the pool, only stages that call
##    fx.render draw it; tribe does, civ does not). Spawns stay invisible.
##  - TS `void disc;` (:661) is a lint artifact — NOT ported.
##  - the TS fakeCam's unread fields (zoom 1, view rect, shx/shy 0) are dead
##    at the backdrop call site (backdrop.ts reads cam.x/cam.y only) — not
##    ported; the x·0.3/y·0.3 values are.
##  - TS Array sort is not involved in the render; the launch-target stable
##    selection lives in the sim (recorded there).
extends "res://src/game/stage.gd"

const CivSimScript := preload("res://src/game/civ/civ_sim.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")
const BackdropScript := preload("res://src/gfx/backdrop.gd")
const CreaturePainter := preload("res://src/gfx/creature_painter.gd")
const HudScript := preload("res://src/ui/hud.gd")
const PauseScript := preload("res://src/ui/pause.gd")
const TutorialScript := preload("res://src/ui/tutorial.gd")

## TS:536 — the space backdrop's seed/strength argument on the civ call.
const BACKDROP_SEED := 42.0

var sim: Variant = null           # CivSim (RefCounted sim core)
var frozen := false               # test seam: render without stepping the sim
## R1 micro-tutorial (Task 4; the cell-stage T8 pattern) — built once in
## on_enter from _build_tutorial_steps(); the engine is src/ui/tutorial.gd.
var tutorial: Variant = null
## The overlay instances — installed into the game stub dicts at tree entry
## and re-installed on enter (the creature/tribe stage pattern).
var hud_inst: Variant = null
var pause_inst: Variant = null

var planet_canvas: Node2D = null
var ui_canvas: Node2D = null
var veil_canvas: Node2D = null
var hud_canvas: Node2D = null
var pause_canvas: Node2D = null
var portrait_item: PortraitItem = null
var portrait_creature: PortraitCreature = null

# TS:535 fakeCam — the backdrop reads x/y only (see the header quirk note).
var _fake_cam: RefCounted = null


class StageCanvas extends Node2D:
	var stage: Variant = null
	var layer := "world"
	func _draw() -> void:
		if stage != null:
			stage._draw_layer(layer, self)


## The fakeCam shape (TS:535 `as never`): duck-typed x/y for the backdrop.
class FakeCam extends RefCounted:
	var x := 0.0
	var y := 0.0


## The ruler portrait — panel + clip mask in _draw, the creature on a CHILD
## painter item (the 3-RID contract: one painter item per creature,
## caller-owned, freed per repaint + PREDELETE). clip_children turns this
## item's drawn content into the clip shape for its whole subtree (see the
## header). render() sets this node's transform to the canvas-transform
## cancellation (see the note there) so the subtree — panel, mask, child
## painter RIDs — draws in true screen coords whatever the live camera does.
class PortraitItem extends Node2D:
	var genome: Dictionary = {}
	var pose: Dictionary = {}
	var opts: Dictionary = {}
	## The clip rect (TS:620 — (22, vh−116, 88, 88)), refreshed per frame.
	var clip_rect := Rect2()
	## TS:617 — the panel rect (18, vh−120, 96, 96).
	var panel_rect := Rect2()

	func _draw() -> void:
		# TS:617 — the panel draws BEFORE the clip + creature
		RendererScript.panel(self, panel_rect.position.x, panel_rect.position.y,
				panel_rect.size.x, panel_rect.size.y, {
					"fill": RendererScript.css_color("rgba(8,14,32,0.9)"),
					"stroke": RendererScript.css_color("rgba(140,190,255,0.4)"),
				})
		# the clip mask — the PANEL color at FULL alpha, FILLED: the group
		# clip masks children by this content's alpha (the task-6 divergence
		# note — a 0.9 mask would dim the creature to 90%); the cost is the
		# clip region compositing the panel fill once more (the 10% backdrop
		# bleed through the 0.9 panel — presence-invisible in the dark corner;
		# the 4px inset ring keeps the TS 0.9)
		draw_rect(clip_rect, Color(8.0 / 255.0, 14.0 / 255.0, 32.0 / 255.0, 1.0), true)

	func _notification(what: int) -> void:
		# no RIDs here — the child painter item owns its own (below)
		pass


## The creature painter item (the tribe_stage CreatureItem contract verbatim):
## the painter's three sub-RIDs are CALLER-OWNED — freed at the top of every
## repaint and on node teardown. A child of PortraitItem, so the portrait's
## clip_children group clips the whole painter subtree.
class PortraitCreature extends Node2D:
	var genome: Dictionary = {}
	var pose: Dictionary = {}
	var opts: Dictionary = {}
	var _rids: Array = []

	func _draw() -> void:
		for rid in _rids:
			RenderingServer.free_rid(rid)
		_rids = []
		if genome.is_empty():
			return
		var res: Dictionary = CreaturePainter.draw_creature(self, genome, pose, opts)
		_rids = [res["clip_item"], res["pattern_item"], res["front_item"]]

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			for rid in _rids:
				RenderingServer.free_rid(rid)
			_rids = []


func _init(game_v: Variant) -> void:
	super(game_v, "civ")


func _ready() -> void:
	_install_overlays()
	# the CALLER draws the stage rng branch (sim header contract, mirrors
	# TS `this.rng = game.context.rng.branch()` in the CivStage constructor)
	sim = CivSimScript.new(game.context, game.context.rng.branch(), _build_hooks())
	_fake_cam = FakeCam.new()

	# screen-space canvases (the M3 Part B doctrine) — tree order is the TS
	# draw order: planet (backdrop..cities) → portrait → ui (sliders..vignette)
	# → veil → hud → pause
	planet_canvas = StageCanvas.new()
	planet_canvas.stage = self
	planet_canvas.layer = "planet"
	planet_canvas.name = "PlanetCanvas"
	add_child(planet_canvas)
	portrait_item = PortraitItem.new()
	portrait_item.name = "PortraitItem"
	# the clip: this item's drawn content (the mask rect) clips its subtree
	portrait_item.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(portrait_item)
	portrait_creature = PortraitCreature.new()
	portrait_creature.name = "PortraitCreature"
	portrait_item.add_child(portrait_creature)
	ui_canvas = StageCanvas.new()
	ui_canvas.stage = self
	ui_canvas.layer = "ui"
	ui_canvas.name = "UICanvas"
	add_child(ui_canvas)
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


## The overlay wiring (the tribe stage's _install_overlays verbatim). Called
## from _ready (first build) AND on_enter (rebind).
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
		# QC r3 stale-toasts: switch_stage expires the leaving hud's list here
		"expire_toasts": hud_inst.expire_toasts,
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
		"planet":
			_draw_planet(ci)
		"ui":
			_draw_ui(ci)
		"veil":
			# screen space — cancel the (identity) viewport camera transform
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


# ---- pure geometry seams (the draw sites consume these; the scene test's
# probes.json re-derives its anchors from them — no copies) ----------------------

## TS:539-540 — the planet center: (vw/2 − camX·0.5, vh/2 − camY·0.5 + 40).
static func planet_center(cam_x: float, cam_y: float, vw: float, vh: float) -> Vector2:
	return Vector2(vw / 2.0 - cam_x * 0.5, vh / 2.0 - cam_y * 0.5 + 40.0)


## TS:541 — the planet radius: min(vw, vh)·0.42.
static func planet_radius(vw: float, vh: float) -> float:
	return minf(vw, vh) * 0.42


## TS:565-568 toScreen — cities/armadas draw through the planet center at
## scale 0.62 (map 0,0 → screen pcx,pcy).
static func map_to_screen(mx: float, my: float, cam_x: float, cam_y: float,
		vw: float, vh: float) -> Vector2:
	var pc := planet_center(cam_x, cam_y, vw, vh)
	return Vector2(pc.x + mx * 0.62, pc.y + my * 0.62)


# ---- TS render() (:530-662) -------------------------------------------------------

## TS:534-614 — backdrop → planet → armadas → cities. All screen space.
func _draw_planet(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_screen_inv())
	var vw: float = game.vw
	var vh: float = game.vh

	# TS:535-536 — the fakeCam zeroes shx/shy and reads x = camX·0.3,
	# y = camY·0.3 (its zoom/view/shx/shy fields are dead at the callee —
	# see the header quirk note)
	_fake_cam.x = sim.camX * 0.3
	_fake_cam.y = sim.camY * 0.3
	BackdropScript.draw_space_backdrop(ci, _fake_cam, vw, vh, sim.time, BACKDROP_SEED)

	# planet (TS:538-562)
	var pc := planet_center(sim.camX, sim.camY, vw, vh)
	var pr := planet_radius(vw, vh)
	# ocean — TS createRadialGradient(pcx − pr·0.3, pcy − pr·0.3, pr·0.2 →
	# pcx, pcy, pr): the light center is OFFSET from the disc center, so the
	# two-stop gradient ports as a vertex-colored fan evaluated per vertex
	# (the land sun/moon fan precedent — Gouraud ≈ radial at 48 segments)
	var gc := Vector2(pc.x - pr * 0.3, pc.y - pr * 0.3)
	var r0 := pr * 0.2
	var c0 := RendererScript.hsl(200.0, 0.5, 0.35)  # TS:544
	var c1 := RendererScript.hsl(220.0, 0.55, 0.16)  # TS:545
	var segs := 48
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.append(pc)
	cols.append(c0.lerp(c1, clampf((pc.distance_to(gc) - r0) / (pr - r0), 0.0, 1.0)))
	for i in segs:
		var a := (float(i) / float(segs)) * TAU
		var v := pc + Vector2(cos(a), sin(a)) * pr
		pts.append(v)
		cols.append(c0.lerp(c1, clampf((v.distance_to(gc) - r0) / (pr - r0), 0.0, 1.0)))
	ci.draw_polygon(pts, cols)
	# continents (seeded blobs) — TS:550-560
	for i in 7:
		var a2 := float(i) * 2.4 + 0.7
		var rr := pr * (0.25 + float(i % 3) * 0.18)
		var cc := pc + Vector2(cos(a2) * pr * 0.55, sin(a2) * pr * 0.5)
		ci.draw_colored_polygon(
				RendererScript.ellipse_points(cc, rr, rr * 0.7, a2),
				RendererScript.hsl(100.0 + float(i) * 14.0, 0.3, 0.3))
	# atmosphere rim — TS:562
	RendererScript.glow(ci, pc.x, pc.y, pr * 1.18,
			RendererScript.css_color("rgba(120,190,255,0.35)"), 0.55)

	# armadas — TS:570-587 (toScreen IS the map_to_screen seam)
	for ar in sim.armadas:
		if not bool(ar["alive"]):
			continue
		var s := map_to_screen(float(ar["x"]), float(ar["y"]), sim.camX, sim.camY, vw, vh)
		var kind := String(ar["kind"])
		var col := Color("#ff7a5a") if kind == "attack" \
				else (Color("#c9a4ff") if kind == "charm" else Color("#5ad0a8"))
		RendererScript.disc(ci, s.x, s.y, 4.0, col)
		RendererScript.glow(ci, s.x, s.y, 10.0, col, 0.6)
		# trail — from the TARGET screen point to the ship (TS:577-586),
		# setLineDash([4,6]) alpha 0.25
		var s0 := map_to_screen(float(ar["tx"]), float(ar["ty"]), sim.camX, sim.camY, vw, vh)
		_dashed_line(ci, s0, s, Color(col.r, col.g, col.b, 0.25))

	# cities — TS:589-614
	for c in sim.cities:
		var s2 := map_to_screen(float(c["x"]), float(c["y"]), sim.camX, sim.camY, vw, vh)
		var mine := String(c["owner"]) == "you"
		var rival: Variant = null
		for r in sim.rivals:
			if String(r["id"]) == String(c["owner"]):
				rival = r
				break
		var col2 := Color("#8fe89a") if mine \
				else (Color(String(rival["color"])) if rival != null else Color("#aaaaaa"))
		# city disc + label
		RendererScript.disc(ci, s2.x, s2.y, 9.0, col2)
		RendererScript.glow(ci, s2.x, s2.y, 22.0, col2, 0.5)
		RendererScript.outlined_text(ci, String(c["name"]), s2.x, s2.y - 22.0,
				{"size": 12.0, "fill": col2, "weight": "700"})
		# '👑 yours' is raw in TS (:598) — native translates it (QC round-2 B3
		# VI-completeness sweep; the tag is the disc's only fixed UI string)
		var status := tr("👑 yours")
		if not mine:
			status = String(rival["name"]) if rival != null else ""
		RendererScript.outlined_text(ci, status, s2.x, s2.y + 22.0,
				{"size": 9.0, "fill": RendererScript.css_color("rgba(255,255,255,0.6)")})
		# influence bar — TS:599-605
		var bw := 64.0
		ci.draw_rect(Rect2(s2.x - bw / 2.0, s2.y + 30.0, bw, 6.0),
				RendererScript.css_color("rgba(0,0,0,0.5)"))
		var inf: float = (float(c["influence"]) + 100.0) / 200.0
		ci.draw_rect(Rect2(s2.x - bw / 2.0, s2.y + 30.0, bw * inf, 6.0),
				Color("#8fe89a") if inf > 0.5 else Color("#ff9a8a"))
		# hp bar — TS:607-610
		ci.draw_rect(Rect2(s2.x - bw / 2.0, s2.y + 39.0, bw, 4.0),
				RendererScript.css_color("rgba(0,0,0,0.5)"))
		ci.draw_rect(Rect2(s2.x - bw / 2.0, s2.y + 39.0, bw * (float(c["hp"]) / 100.0), 4.0),
				Color("#9fd8ff"))
		if float(c["burning"]) > 0.0:
			RendererScript.glow(ci, s2.x, s2.y, 26.0,
					RendererScript.css_color("rgba(255,140,50,0.8)"), 0.8)


## TS setLineDash([4, 6]) — 4 on, 6 off from the START point, lineWidth 1.
func _dashed_line(ci: CanvasItem, from: Vector2, to: Vector2, col: Color) -> void:
	var total := from.distance_to(to)
	if total <= 0.001:
		return
	var dir := (to - from) / total
	var d := 0.0
	while d < total:
		var e := minf(d + 4.0, total)
		ci.draw_line(from + dir * d, from + dir * e, col, 1.0)
		d = e + 6.0


## TS render() screen-space tail (:628-660): sliders panel → launch hints →
## victory shimmer → vignette. Runs with the camera transform cancelled.
func _draw_ui(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_screen_inv())
	var vw: float = game.vw
	var vh: float = game.vh

	# sliders panel — TS:628-649
	var sw := 300.0
	var sx := vw - sw - 18.0
	var sy := vh - 150.0
	RendererScript.panel(ci, sx, sy, sw, 132.0, {
		"fill": RendererScript.css_color("rgba(6,10,24,0.88)"),
		"stroke": RendererScript.css_color("rgba(140,190,255,0.35)"),
	})
	RendererScript.outlined_text(ci, tr("NATIONAL OUTPUT"), sx + sw / 2.0, sy + 16.0,
			{"size": 11.0, "fill": Color("#9fd8ff"), "weight": "700"})
	var bars: Array = [
		[tr("Q/A Military"), sim.mil, Color("#ff7a5a")],
		[tr("W/S Culture"), sim.culture, Color("#c9a4ff")],
		[tr("E/D Economy"), sim.econ, Color("#5ad0a8")],
	]
	var by := sy + 34.0
	for bar in bars:
		RendererScript.outlined_text(ci, String(bar[0]), sx + 12.0, by + 8.0,
				{"size": 11.0, "fill": RendererScript.css_color("rgba(220,235,255,0.8)"),
						"align": "left"})
		var bx := sx + 118.0
		var bw2 := sw - 140.0
		ci.draw_colored_polygon(
				RendererScript.rounded_rect_points(bx, by, bw2, 12.0, 6.0),
				RendererScript.css_color("rgba(255,255,255,0.1)"))
		ci.draw_colored_polygon(
				RendererScript.rounded_rect_points(bx, by, maxf(3.0, bw2 * (float(bar[1]) / 10.0)), 12.0, 6.0),
				bar[2])
		RendererScript.outlined_text(ci, str(bar[1]), sx + sw - 12.0, by + 6.0,
				{"size": 11.0, "fill": bar[2], "align": "right"})
		by += 30.0

	# launch hints — TS:652
	RendererScript.outlined_text(ci, tr("1 attack · 2 charm caravan · 3 trade caravan"),
			vw / 2.0, vh - 130.0,
			{"size": 12.0, "fill": RendererScript.css_color("rgba(200,225,255,0.6)")})

	# victory shimmer — TS:655-658 (all owned, NOT victoryFired-gated — the
	# shimmer reads the board only)
	var all_yours := true
	for c in sim.cities:
		if String(c["owner"]) != "you":
			all_yours = false
			break
	if all_yours:
		RendererScript.outlined_text(ci, tr("THE PLANET IS UNITED"), vw / 2.0, vh / 2.0 - 180.0,
				{"size": 30.0, "fill": Color("#ffe08a")})

	# vignette — TS:660 (draws over the portrait too — the TS order keeps it
	# last on the stage; the hud layers draw after it, as in TS's game stack)
	RendererScript.vignette(ci, vw, vh, 0.5)
	# TS:661 `void disc;` is a lint artifact — NOT ported.

	# tutorial overlay — the Task 8 engine (the cell-stage draw slot: topmost
	# of the stage's screen-space tail); inactive engines draw nothing
	if tutorial != null:
		tutorial.draw(ci, vw, vh)


## Per-frame draw hook (Game's render side): re-sync the portrait fixture and
## queue all canvases.
func render() -> void:
	if planet_canvas == null or sim == null:
		return
	var vh: float = game.vh
	# the portrait subtree draws at TRUE screen coords: the live Camera2D (the
	# cam rig's is current from boot — anchor drag-center) puts a translate(
	# vw/2, vh/2) on the default canvas; the StageCanvases cancel it inside
	# _draw, but a node SUBTREE (portrait + its child painter RIDs) can only
	# cancel it at the node transform — the RIDs' own transforms compose below
	# this item, so the whole portrait stack renders through it (the M3 Part B
	# screen-space doctrine, node-level)
	portrait_item.transform = _screen_inv()
	portrait_item.panel_rect = Rect2(18.0, vh - 120.0, 96.0, 96.0)  # TS:617
	portrait_item.clip_rect = Rect2(22.0, vh - 116.0, 88.0, 88.0)  # TS:620
	portrait_creature.genome = sim.rulerGenome
	# TS:622-625 — the pose is verbatim (screen coords; gait rides time·2)
	portrait_creature.pose = {
		"x": 66.0, "y": vh - 40.0, "facing": 1.0, "speed": 0.05,
		"gaitPhase": sim.time * 2.0, "attack": 0.0, "hurt": 0.0, "eat": 0.0,
		"airborne": 0.0, "mood": "happy", "scale": 1.4,
	}
	portrait_creature.opts = {"t": sim.time}
	portrait_item.queue_redraw()
	portrait_creature.queue_redraw()
	planet_canvas.queue_redraw()
	ui_canvas.queue_redraw()
	veil_canvas.queue_redraw()
	hud_canvas.queue_redraw()
	pause_canvas.visible = bool(game.paused)
	if pause_canvas.visible:
		pause_canvas.queue_redraw()


# ---- update (the TS:177-305 scene-side flow) ---------------------------------------

## The Game loop's fixed-step accumulator calls this; the stage feeds the M2
## snapshot to sim.update. No camera work: the drift camera is sim-owned
## (civ_sim.update, TS:279-287), the fx pool steps game-side (TS game.ts:290),
## and the ability slots ride the sim's hud_set_abilities hook (TS:298-305).
func update(dt: float) -> void:
	if sim == null or frozen:
		return
	# tutorial (the cell-stage slot: the engine polls before the sim steps)
	if tutorial != null:
		tutorial.update(dt)
	sim.update(dt, _build_input_snapshot())


# ---- hooks (CivSim → scene/game/storyteller) ----------------------------------------

func _build_hooks() -> Dictionary:
	return {
		"hud_toast": _h_hud_toast,
		"hud_banner": _h_hud_banner,
		"hud_toast_inset": _h_hud_toast_inset,
		"hud_show_objective": _h_hud_show_objective,
		"hud_objective_counter": _h_hud_objective_counter,
		"hud_float_world": _h_hud_float_world,
		"hud_set_abilities": _h_hud_set_abilities,
		"audio_play": _h_audio_noop,
		"audio_set_mood": _h_audio_noop,
		"cam_shake": _h_cam_shake,
		"fx_spawn": _h_fx_spawn,
		"go_to": _h_go_to,
		"save_all": _h_save_all,
		"get_gap_bias": _h_gap_bias,
		"get_mood": _h_mood,
		"get_warn_scale": _h_warn_scale,
		"storyteller_note_chaos_event": _h_note_chaos_event,
	}


func _h_hud_toast(text: String, kind: String, icon: String) -> void:
	game.hud["toast"].call(text, kind, icon)


func _h_hud_banner(data: Variant) -> void:
	game.hud["banner"].call(data)


func _h_hud_toast_inset(px: float) -> void:
	# TS:120 — game.hud.toastInset = 150 (clears the ruler portrait; hud.gd
	# reads toast_inset at draw)
	if hud_inst != null:
		hud_inst.toast_inset = float(px)


func _h_hud_show_objective(text: String) -> void:
	if hud_inst != null:
		hud_inst.show_objective = text


## R2 chip — the sim's live cur/max pair behind the centered objective (the
## hud's setter clears the pair whenever the line itself (re)arms, so the
## two hooks compose in either order). Civ's sim never fires it (the no-chip
## ruling), but the binding keeps the three stage hud seams uniform.
func _h_hud_objective_counter(cur: int, max: int) -> void:
	if hud_inst != null:
		hud_inst.show_objective_cur = cur
		hud_inst.show_objective_max = max


func _h_hud_float_world(x: float, y: float, text: String, color: Variant, size: float) -> void:
	game.hud["float_world"].call(x, y, text, color, size)


func _h_hud_set_abilities(list: Array) -> void:
	# TS:298-305 — the sim fires this at the END of every update; the stage
	# only bridges it to the hud (the payload is the sim's, pinned there)
	game.hud["set_abilities"].call(list)


func _h_audio_noop(_name: String, _vol := 0.0, _pan := 0.0) -> void:
	pass  # audio core is its own task — the sim's audio hooks stay silent


func _h_cam_shake(mag: float, dur: float) -> void:
	# TS:373/:410/:465/:491 — game.camShakeFor kept verbatim; VISUALLY INERT
	# on this stage (the fakeCam zeroes shx/shy and no rig carries the
	# viewport — see the header quirk note)
	game.cam_shake_for(mag, dur)


func _h_fx_spawn(opts: Variant) -> void:
	# TS:243/:374 spawn into game.fx (NO stage pool on civ); the payloads
	# carry RAW map coords — and the pool is never RENDERED on this stage
	# (TS CivStage.render has no fx.render call). Pass-through verbatim.
	game.fx["spawn"].call(opts)


func _h_gap_bias() -> float:
	return game.storyteller.gap_bias()


func _h_mood() -> String:
	return game.storyteller.mood


func _h_warn_scale() -> float:
	return game.storyteller.warn_scale()


func _h_note_chaos_event(playtime: float) -> void:
	game.storyteller.note_chaos_event(playtime)


## The fall/victory stage handoffs (TS:127/:295) — 'space' stays unregistered
## until its milestone (switch_stage silently no-ops, TS-true).
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
	sim.on_enter()
	# the first-run tutorial (per save slot; the cell-stage build-once rule)
	if tutorial == null:
		tutorial = TutorialScript.new(game, "tutCiv", _build_tutorial_steps())


func on_exit() -> void:
	if sim != null:
		sim.on_exit()
	# the cell-stage finish rule (CellStage.ts:264-267): the tutorial finishes
	# on every exit EXCEPT a quit-to-title — the flag persists only on forward
	# evolution
	if game.transition_target != "menu" and tutorial != null:
		tutorial.finish()


## Task 4 R1 — the civ tutorial table (3 steps). Step texts stay raw EN keys
## (translated at render by the engine, the cell precedent); done lambdas
## poll the sim directly — pure reads (mil vs the 4.0 start value, the launch
## counter, the conquest accessor).
func _build_tutorial_steps() -> Array:
	return [
		{"id": "mil", "text": "Press Q/A — raise military output",
			"done": func() -> bool: return sim.mil > 4.0},
		{"id": "launch", "text": "Press 1 — launch an armada",
			"done": func() -> bool: return sim.launches >= 1},
		{"id": "conquer", "text": "Touch an enemy city — conquer it",
			"done": func() -> bool: return sim.conquest_count() >= 1},
	]


## TS CivStage.onExit → persistState (CivStage.ts:130) — the autosave flush
## seam (game.save_all()/the 60s autosave call current.persist_state()).
func persist_state() -> void:
	if sim != null:
		sim.persist_state()


# ---- input snapshot ------------------------------------------------------------------

## The M2 canonical snapshot (civ_sim.update contract): keys_pressed/keys_held
## built from the GameInput wrapper — one-shots from the frame state (cleared
## by end_frame AFTER this in Game._do_update), held codes polled live. The
## mouse fields ride along unused (the sim reads keys_pressed only — no
## hudRects on civ).
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
