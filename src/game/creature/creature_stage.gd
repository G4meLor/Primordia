## CREATURE STAGE scene node — the side-view island's visual layer over the
## CreatureSim sim core (headless, src/game/creature/creature_sim.gd). Port of
## Spore src/game/creature/CreatureStage.ts render() + the scene-side halves of
## update()/onEnter(): the editor Tab/E branch, the found-tribe click routing,
## the input SNAPSHOT build, camera follow/zoom, fx stepping, the HUD
## objective/abilities push, and the full TS draw order: land backdrop (screen)
## → lawn band → dirt (drawGround) → world edge hints → decor trees → hazards
## → bushes → bones → nests → ents z-sorted with the player INSERTED BY z
## (TS:1446-1452 — the player is NOT special-cased; it draws when the first
## ent with z > pz is reached) → fx → night overlay + fireflies (screen) →
## vignette 0.42 → HP bar → tutorial slot → charm UI → death card → tribe
## button.
##
## Draw architecture — FIRST CAMERA2D-CONSUMING STAGE (design-spec carry-
## forward "Camera2D rig ownership"): the cell stage bakes the camera into
## draw_set_transform and DISABLES the rig; the creature stage instead re-
## enables game.cam.cam2d on entry and lets the VIEWPORT apply the camera
## transform to the default canvas. World canvases (ground/ents/fx) therefore
## draw at identity in world coordinates; the screen-space canvases (sky/ui/
## veil/hud/editor/pause) cancel the live viewport canvas_transform with
## affine_inverse() so TS screen-space sections stay pixel-anchored (and
## un-shaken, as in TS — the backdrop and HUD draw outside cam.begin/end).
## Ownership: on_enter enables the rig, on_exit disables it again — the menu
## and cell stage draw in absolute screen space and expect the rig off.
## Recorded camera numbers (TS CreatureStage.ts:571-572, verified against
## renderer.ts Camera): follow(px, pz·Z_TO_Y, dt, 5) and zoom = 1.15 CONSTANT
## — the plan's "1.15 − pz·0.0001 clamp 0.9..1.15" formula does not exist in
## the frozen TS; parity wins (recorded in the task report).
##
## Creature draw protocol (task 6 painter contract): one CreatureItem scene
## child PER DRAWABLE (never two creatures on one item — RS child items
## composite after ALL of the parent item's own commands, so a shared item
## would bury one creature's face under the next one's body). Each drawable
## gets a body item + an extras item (hp bar / pack marker) as ADJACENT tree
## siblings, re-ordered every frame into the z-sorted TS order — the extras
## interleave exactly like TS drawEnt's tail (ent i's bar draws before
## ent i+1's body). The painter's three sub-RIDs are caller-owned: freed at
## the top of every _draw and on node teardown.
##
## Scene-side divergences (recorded): the TS editor branch early-returns for
## the frame (CreatureStage.ts:467-475); natively the sim keeps advancing
## (the cell-stage T3 ruling). The tutorial engine slot exists but the engine
## build lands with task 8 (tutorial stays null; charm UI then uses the
## non-lifted y, TS `tutorial?.active ? vh-256 : vh-170`).
extends "res://src/game/stage.gd"

const CreatureSimScript := preload("res://src/game/creature/creature_sim.gd")
const ParticlesScript := preload("res://src/gfx/particles.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")
const BackdropScript := preload("res://src/gfx/backdrop.gd")
const CreaturePainter := preload("res://src/gfx/creature_painter.gd")
const HudScript := preload("res://src/ui/hud.gd")
const EditorUiScript := preload("res://src/ui/editor.gd")
const PauseScript := preload("res://src/ui/pause.gd")

var sim: Variant = null            # CreatureSim (RefCounted sim core)
var fx: Variant = null             # stage Particles pool (TS `new Fx(1300)`)
var frozen := false                # test seam: render without stepping the sim
## Task 8 slot — the TS tutorial engine (CreatureStage.ts:306-313); null until
## that task builds it. The draw/update paths already honor it.
var tutorial: Variant = null
## The overlay instances — installed into the game stub dicts at tree entry
## and re-installed on enter (the cell stage's Task 8 pattern).
var hud_inst: Variant = null
var editor_inst: Variant = null
var pause_inst: Variant = null

var sky_canvas: Node2D = null
var ground_canvas: Node2D = null
var ents_canvas: Node2D = null
var fx_canvas: Node2D = null
var ui_canvas: Node2D = null
var veil_canvas: Node2D = null
var hud_canvas: Node2D = null
var editor_canvas: Node2D = null
var pause_canvas: Node2D = null

# pooled per-drawable node pairs (body + extras), z-ordered every frame
var _body_pool: Array = []
var _extra_pool: Array = []


class StageCanvas extends Node2D:
	var stage: Variant = null
	var layer := "world"
	func _draw() -> void:
		if stage != null:
			stage._draw_layer(layer, self)


## One creature's body — genome/pose/opts are set by the stage's per-frame
## sync; _draw repaints via the painter. The painter's three sub-RIDs are
## CALLER-OWNED (task 6 contract): freed at the top of every repaint and on
## node teardown. Draws at identity in WORLD coordinates — the enabled
## Camera2D carries the camera transform.
class CreatureItem extends Node2D:
	const Painter := preload("res://src/gfx/creature_painter.gd")

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
		var res: Dictionary = Painter.draw_creature(self, genome, pose, opts)
		_rids = [res["clip_item"], res["pattern_item"], res["front_item"]]

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			for rid in _rids:
				RenderingServer.free_rid(rid)
			_rids = []


## TS drawEnt's tail (hp bar when damaged + pack paw marker) on its own item
## so it interleaves per-ent exactly like the TS command stream.
class CreatureExtraItem extends Node2D:
	var bar_frac := -1.0     # < 0 = no bar
	var bar_color := Color.WHITE
	var marker := false
	var marker_x := 0.0
	var marker_y := 0.0
	var marker_bob := 0.0

	func _draw() -> void:
		if bar_frac >= 0.0:
			draw_rect(Rect2(marker_x - 15.0, marker_y - 44.0, 30.0, 3.5), Color(0.0, 0.0, 0.0, 0.4))
			draw_rect(Rect2(marker_x - 15.0, marker_y - 44.0, 30.0 * bar_frac, 3.5), bar_color)
		if marker:
			RendererScript.outlined_text(self, "🐾", marker_x, marker_y - 52.0 + marker_bob,
					{"size": 11.0, "fill": Color("#cfe8ff")})


func _init(game_v: Variant) -> void:
	super(game_v, "creature")


func _ready() -> void:
	_install_overlays()
	# stage pool cap 1300 (TS `private fx = new Fx(1300)`); the game pool
	# (1100) hangs off game.fx
	fx = ParticlesScript.new(1300)
	# the CALLER draws the stage rng branch (sim header contract, mirrors
	# TS `this.rng = ctx.rng.branch()` in the CreatureStage constructor)
	sim = CreatureSimScript.new(game.context, game.context.rng.branch(), _build_hooks())

	# TS draw-path parity (see header): world canvases draw at identity and the
	# enabled Camera2D carries the transform. The rig boots disabled (menu/cell
	# own the screen-space default) — THIS stage turns it on in on_enter and
	# off again in on_exit. (At boot it is already off; setting it here too
	# would make the pre-enter world canvas draw one frame through the rig.)
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = false

	sky_canvas = StageCanvas.new()
	sky_canvas.stage = self
	sky_canvas.layer = "sky"
	sky_canvas.name = "SkyCanvas"
	add_child(sky_canvas)
	ground_canvas = StageCanvas.new()
	ground_canvas.stage = self
	ground_canvas.layer = "ground"
	ground_canvas.name = "GroundCanvas"
	add_child(ground_canvas)
	ents_canvas = StageCanvas.new()
	ents_canvas.stage = self
	ents_canvas.layer = "ents"
	ents_canvas.name = "EntsCanvas"
	add_child(ents_canvas)
	fx_canvas = StageCanvas.new()
	fx_canvas.stage = self
	fx_canvas.layer = "fx"
	fx_canvas.name = "FxCanvas"
	add_child(fx_canvas)
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
	editor_canvas = StageCanvas.new()
	editor_canvas.stage = self
	editor_canvas.layer = "editor"
	editor_canvas.name = "EditorCanvas"
	editor_canvas.visible = false
	add_child(editor_canvas)
	pause_canvas = StageCanvas.new()
	pause_canvas.stage = self
	pause_canvas.layer = "pause"
	pause_canvas.name = "PauseCanvas"
	pause_canvas.visible = false
	add_child(pause_canvas)


## Same overlay wiring as the cell stage (Task 8 ruling — the dict shapes and
## every existing call site stay identical; only the Callables become real).
## Re-installed on enter so cell → creature → cell keeps the live dicts
## pointing at the CURRENT stage's instances (cross-stage hud handoff note in
## the task report — the cell stage still draws its own instance).
func _install_overlays() -> void:
	hud_inst = HudScript.new(game)
	game.hud = {
		"update": hud_inst.update,
		"dismiss_banner": hud_inst.dismiss_banner,
		"toast": hud_inst.toast,
		"banner": hud_inst.banner,
		"float_world": hud_inst.float_world,
		"pointer_down": hud_inst.pointer_down,
		"set_abilities": hud_inst.set_abilities,
	}
	editor_inst = EditorUiScript.new(game)
	game.editor = {
		"open": false,
		"show": editor_inst.show,
		"close": editor_inst.close,
		"update": editor_inst.update,
	}
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
		"ground":
			_draw_ground(ci)
		"ents":
			pass  # the creatures are the canvas's pooled child items
		"fx":
			_draw_fx(ci)
		"ui":
			_draw_ui(ci)
		"veil":
			# screen space under the enabled rig — cancel the camera transform
			ci.draw_set_transform_matrix(_screen_inv())
			game.draw_transition_veil(ci)
		"hud":
			if hud_inst != null:
				ci.draw_set_transform_matrix(_screen_inv())
				hud_inst.draw(ci, game.vw, game.vh)
		"editor":
			if editor_inst != null and editor_inst.open:
				ci.draw_set_transform_matrix(_screen_inv())
				editor_inst.draw(ci, game.vw, game.vh)
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


## TS render() head (CreatureStage.ts:1343-1349): the land backdrop, screen
## space BEFORE cam.begin. horizonScreenY is the world y=0 line.
func _draw_sky(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_screen_inv())
	var cam: Variant = game.cam
	var horizon_y: float = game.vh / 2.0 + (0.0 - cam.y) * cam.zoom
	BackdropScript.draw_land_backdrop(ci, cam, game.vw, game.vh, sim.time,
			float(game.context.chaos), sim.dayPhase, horizon_y)


## TS render() world sections (CreatureStage.ts:1351-1443), in world
## coordinates (the enabled rig carries the camera).
func _draw_ground(ci: CanvasItem) -> void:
	var vw: float = game.vw
	var cam: Variant = game.cam
	var chaos := float(game.context.chaos)
	var lawn_h := _lawn_h()

	# lawn (pseudo-depth band) — TS:1354-1359
	var night: bool = sim.is_night()
	var top := RendererScript.hsl(105.0 - chaos * 30.0, 0.32, 0.30 - (0.12 if night else 0.0))
	var bottom := RendererScript.hsl(95.0 - chaos * 30.0, 0.38, 0.22 - (0.10 if night else 0.0))
	ci.draw_polygon(
			PackedVector2Array([
				Vector2(cam.view_l, 0), Vector2(cam.view_r, 0),
				Vector2(cam.view_r, lawn_h), Vector2(cam.view_l, lawn_h)]),
			PackedColorArray([top, top, bottom, bottom]))

	# dirt below — TS:1362
	BackdropScript.draw_ground(ci, cam.view_l, cam.view_r, lawn_h, 400.0, sim.time, chaos)

	# world edge hints — TS:1364-1369
	var edge := RendererScript.css_color("rgba(30,60,90,0.35)")
	ci.draw_rect(Rect2(-CreatureSimScript.WORLD_HALF - 400.0, 0.0, 400.0, lawn_h), edge)
	ci.draw_rect(Rect2(CreatureSimScript.WORLD_HALF, 0.0, 400.0, lawn_h), edge)

	# decorative trees/rocks (seeded, deterministic from x) — TS:1372
	_draw_decor(ci, lawn_h)

	# hazards — TS:1374-1384 (radial gradient clipped to an ellipse: a
	# vertex-colored elliptical fan reproduces the 2-stop radial exactly)
	for hz in sim.hazards:
		var hy: float = float(hz["z"]) * CreatureSimScript.Z_TO_Y
		var col0: Color = RendererScript.css_color("rgba(255,120,40,0.85)") \
				if String(hz["kind"]) == "lava" \
				else RendererScript.css_color("rgba(255,170,60,0.75)")
		_ellipse_radial(ci, Vector2(float(hz["x"]), hy), float(hz["r"]), float(hz["r"]) * 0.5,
				col0, Color(col0, 0.0))

	# bushes — TS:1386-1407
	for b in sim.bushes:
		var bx := float(b["x"])
		if bx < cam.view_l - 60.0 or bx > cam.view_r + 60.0:
			continue
		var by := float(b["z"]) * CreatureSimScript.Z_TO_Y
		var sway := sin(sim.time * 0.9 + float(b["seed"])) * 2.0
		ci.draw_colored_polygon(
				RendererScript.ellipse_points(Vector2(bx + sway * 0.3, by - 8.0), 14.0, 10.0, 0.0),
				RendererScript.hsl(120.0, 0.35, 0.25))
		ci.draw_colored_polygon(
				RendererScript.ellipse_points(Vector2(bx + sway * 0.5, by - 14.0), 12.0, 9.0, 0.0),
				RendererScript.hsl(125.0, 0.45, 0.32))
		var food := float(b["food"])
		if food > 0.5:
			var berries: int = mini(4, ceili(food))
			for i in berries:
				RendererScript.disc(ci, bx - 6.0 + float(i) * 4.0 + sin(float(b["seed"]) + float(i)) * 2.0,
						by - 16.0 - float(i % 2) * 4.0, 2.2, Color("#ff6a9a"))

	# bones — TS:1409-1426
	for bo in sim.bones:
		var box := float(bo["x"])
		if bool(bo["taken"]) or box < cam.view_l - 40.0 or box > cam.view_r + 40.0:
			continue
		var boy := float(bo["z"]) * CreatureSimScript.Z_TO_Y
		ci.draw_line(Vector2(box - 12.0, boy - 2.0), Vector2(box + 10.0, boy - 6.0),
				Color(Color("#e8e0cc"), 0.9), 4.0)
		RendererScript.disc(ci, box - 13.0, boy - 2.0, 3.4, Color(Color("#f2ead8"), 0.9))
		RendererScript.disc(ci, box + 11.0, boy - 6.0, 3.4, Color(Color("#f2ead8"), 0.9))
		if String(bo["kind"]) == "meteor":
			RendererScript.glow(ci, box, boy - 6.0, 26.0, RendererScript.css_color("rgba(255,180,90,0.5)"), 0.7)

	# nests (little hut markers) — TS:1428-1443
	for n in sim.nests:
		var nx := float(n["x"])
		if nx < cam.view_l - 60.0 or nx > cam.view_r + 60.0:
			continue
		var ny := float(n["z"]) * CreatureSimScript.Z_TO_Y
		var fill: Color = RendererScript.css_color("rgba(120,200,140,0.8)") \
				if String(n["speciesId"]) == "player" \
				else RendererScript.css_color("rgba(150,130,110,0.7)")
		fill.a *= 0.75  # TS globalAlpha 0.75
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(nx - 16.0, ny), Vector2(nx, ny - 18.0), Vector2(nx + 16.0, ny)]), fill)


## TS drawDecor (CreatureStage.ts:1604-1629) — deterministic trees every
## ~170px from a hash of the world x.
func _draw_decor(ci: CanvasItem, lawn_h: float) -> void:
	var cam: Variant = game.cam
	var start := floorf((cam.view_l - 100.0) / 170.0) * 170.0
	var x := start
	while x < cam.view_r + 100.0:
		var h: float = fmod(absf(sin(x * 12.9898) * 43758.5453), 1.0)
		if h >= 0.35:  # gaps
			var z := (h * (CreatureSimScript.Z_MAX - CreatureSimScript.Z_MIN) + CreatureSimScript.Z_MIN) * 0.9
			var y := z * CreatureSimScript.Z_TO_Y
			if y <= lawn_h - 10.0:
				var sway := sin(sim.time * 0.5 + x) * 3.0
				# trunk: quadraticCurveTo(x+sway, y-30, x+sway*1.5, y-52)
				var trunk := PackedVector2Array()
				var segs := 8
				for k in segs + 1:
					var u := float(k) / float(segs)
					var q0 := (1.0 - u) * (1.0 - u)
					var q1 := 2.0 * (1.0 - u) * u
					var q2 := u * u
					trunk.append(Vector2(
						q0 * x + q1 * (x + sway) + q2 * (x + sway * 1.5),
						q0 * y + q1 * (y - 30.0) + q2 * (y - 52.0)))
				ci.draw_polyline(trunk, RendererScript.hsl(28.0, 0.35, 0.28), 7.0, true)
				# crown
				ci.draw_colored_polygon(
						RendererScript.ellipse_points(Vector2(x + sway * 1.5, y - 62.0),
								24.0 + h * 10.0, 18.0 + h * 6.0, 0.0),
						RendererScript.hsl(120.0 - h * 40.0, 0.4, 0.28))
		x += 170.0


## 2-stop radial gradient over an ellipse — vertex-colored fan (used by the
## hazard blobs; TS createRadialGradient fills an ellipse path).
func _ellipse_radial(ci: CanvasItem, center: Vector2, rx: float, ry: float,
		col0: Color, col1: Color, segments := 36) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.append(center)
	cols.append(col0)
	for i in segments + 1:
		var a := (float(i) / float(segments)) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		cols.append(col1)
	ci.draw_polygon(pts, cols)


## TS render() tail (CreatureStage.ts:1454-1456): the particle pools, in
## world space (stage pool then game pool).
func _draw_fx(ci: CanvasItem) -> void:
	fx.render(ci)
	game.fx["render"].call(ci)


## TS render() screen-space tail (CreatureStage.ts:1460-1531): night overlay,
## fireflies, vignette, HP bar, tutorial slot, charm UI, death card, tribe
## button. Runs with the camera transform cancelled (drawn after cam.end).
func _draw_ui(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_screen_inv())
	var vw: float = game.vw
	var vh: float = game.vh

	# night overlay + fireflies — TS:1460-1477
	if sim.is_night():
		var depth: float = minf(1.0, minf((sim.dayPhase - 0.55) * 6.0, (0.95 - sim.dayPhase) * 6.0))
		ci.draw_rect(Rect2(0, 0, vw, vh), Color(10.0 / 255.0, 10.0 / 255.0, 40.0 / 255.0, depth * 0.42))
		for i in 20:
			var fx2: float = fmod(float(i) * 137.5 + sim.time * (8.0 + float(i % 5) * 3.0), vw + 40.0) - 20.0
			var fy := vh * 0.4 + sin(sim.time * 0.7 + float(i) * 2.4) * vh * 0.3
			var tw := 0.4 + 0.6 * absf(sin(sim.time * 2.0 + float(i)))
			RendererScript.disc(ci, fx2, fy, 1.6,
					Color(220.0 / 255.0, 255.0 / 255.0, 140.0 / 255.0, tw * depth * 0.8))

	# vignette — TS:1479
	RendererScript.vignette(ci, vw, vh, 0.42)

	# HP bar — TS:1481-1488
	var hp_w := minf(340.0, vw * 0.3)
	var hx := vw / 2.0 - hp_w / 2.0
	var hy := vh - 108.0
	RendererScript.panel(ci, hx - 6.0, hy - 6.0, hp_w + 12.0, 22.0, {
		"fill": RendererScript.css_color("rgba(6,10,24,0.75)"),
		"stroke": RendererScript.css_color("rgba(255,120,140,0.25)"),
	})
	var hp_p := clampf(sim.php / sim.pmaxHp, 0.0, 1.0)
	ci.draw_rect(Rect2(hx, hy, hp_w * hp_p, 10.0),
			Color("#5aff8a") if hp_p > 0.35 else Color("#ff5a5a"))
	RendererScript.outlined_text(ci, "%d / %d" % [ceili(maxf(0.0, sim.php)), roundi(sim.pmaxHp)],
			vw / 2.0, hy + 5.0, {"size": 10.0, "fill": RendererScript.css_color("rgba(255,255,255,0.9)")})

	# tutorial overlay (below the charm UI so the beat bar stays visible)
	if tutorial != null:
		tutorial.draw(ci, vw, vh)

	# charm minigame UI — TS:1493-1508
	if sim.charmActive:
		var bw := 260.0
		var bx := vw / 2.0 - bw / 2.0
		# lift above the tutorial card while it teaches the charm step
		var tut_active: bool = tutorial != null and bool(tutorial.active)
		var by := (vh - 256.0) if tut_active else (vh - 170.0)
		RendererScript.panel(ci, bx - 8.0, by - 22.0, bw + 16.0, 52.0, {
			"fill": RendererScript.css_color("rgba(10,16,36,0.9)"),
			"stroke": RendererScript.css_color("rgba(255,220,140,0.5)"),
		})
		RendererScript.outlined_text(ci, "PRESS SPACE IN THE ZONE", vw / 2.0, by - 8.0,
				{"size": 11.0, "fill": Color("#ffe08a")})
		ci.draw_rect(Rect2(bx, by, bw, 16.0), RendererScript.css_color("rgba(255,255,255,0.12)"))
		var zone := (0.35 - float(sim.charmHits) * 0.05) * (bw / 2.0)
		ci.draw_rect(Rect2(vw / 2.0 - zone, by, zone * 2.0, 16.0),
				RendererScript.css_color("rgba(120,230,140,0.7)"))
		var mx := vw / 2.0 + float(sim.charmMarker) * (bw / 2.0)
		ci.draw_rect(Rect2(mx - 2.0, by - 3.0, 4.0, 22.0), Color("#fff"))

	# death overlay — TS:1510-1516
	if sim.deathFade > 0.0:
		ci.draw_rect(Rect2(0, 0, vw, vh),
				Color(60.0 / 255.0, 0.0, 10.0 / 255.0, minf(0.55, sim.deathFade * 0.4)))
		RendererScript.outlined_text(ci, tr("THE ISLAND RECLAIMS YOU"), vw / 2.0, vh / 2.0 - 10.0,
				{"size": 28.0, "fill": Color("#ff9a8a")})
		RendererScript.outlined_text(ci, tr("the pack scattered — your DNA funds the rebirth"),
				vw / 2.0, vh / 2.0 + 22.0,
				{"size": 13.0, "fill": RendererScript.css_color("rgba(255,200,190,0.8)")})

	# found-tribe button — TS:1518-1531 (the rect lives in the sim's dict; the
	# scene re-positions it every frame, the sim only hit-tests it)
	if sim.tribeReady:
		var r: Dictionary = sim.tribeRect
		r["x"] = vw - float(r["w"]) - 26.0
		r["y"] = vh - 150.0
		var hover: bool = sim.over_tribe(game.input.mx, game.input.my)
		if hover:
			game.hover_cursor()
		RendererScript.panel(ci, float(r["x"]), float(r["y"]), float(r["w"]), float(r["h"]), {
			"fill": (RendererScript.css_color("rgba(220,170,60,0.95)") if hover
					else RendererScript.css_color("rgba(160,120,40,0.9)")),
			"stroke": RendererScript.css_color("rgba(255,230,150,0.7)"),
			"lw": 2.0,
			"shadow": RendererScript.css_color("rgba(255,220,120,0.3)"),
		})
		RendererScript.outlined_text(ci, tr("🔥 FOUND A TRIBE"),
				float(r["x"]) + float(r["w"]) / 2.0, float(r["y"]) + 19.0,
				{"size": 15.0, "fill": Color("#fff8e8"), "weight": "700"})
		RendererScript.outlined_text(ci, tr("your pack becomes your people"),
				float(r["x"]) + float(r["w"]) / 2.0, float(r["y"]) + 36.0,
				{"size": 10.0, "fill": RendererScript.css_color("rgba(255,248,232,0.75)")})


func _lawn_h() -> float:
	return (CreatureSimScript.Z_MAX + 120.0) * CreatureSimScript.Z_TO_Y


## Per-frame draw hook (Game's render side): rebuild the z-sorted creature
## item order and queue all canvases (Node2D._draw fires on the next pass).
func render() -> void:
	if sky_canvas == null:
		return
	_sync_creature_items()
	sky_canvas.queue_redraw()
	ground_canvas.queue_redraw()
	fx_canvas.queue_redraw()
	ui_canvas.queue_redraw()
	veil_canvas.queue_redraw()
	hud_canvas.queue_redraw()
	var editor_open: bool = bool(game.editor["open"])
	editor_canvas.visible = editor_open
	if editor_open:
		editor_canvas.queue_redraw()
	pause_canvas.visible = bool(game.paused)
	if pause_canvas.visible:
		pause_canvas.queue_redraw()


## TS render()'s entity pass (CreatureStage.ts:1445-1452): ents z-sorted, the
## player inserted the moment the first ent with z > pz is reached (equivalent
## of the TS ents.concat(player) sort — the player is NOT special-cased).
## Each drawable maps to a pooled (body, extras) node pair at adjacent tree
## indices; hidden pairs stay pooled for the next population swing.
func _sync_creature_items() -> void:
	var drawables: Array = []
	var drew_player := false
	var sorted_ents: Array = sim.ents.duplicate()
	sorted_ents.sort_custom(func(a, b) -> bool:
		return float(a["z"]) < float(b["z"]))
	for e in sorted_ents:
		if not drew_player and float(e["z"]) > sim.pz:
			drawables.append({})  # the player marker (empty dict)
			drew_player = true
		drawables.append(e)
	if not drew_player:
		drawables.append({})

	while _body_pool.size() < drawables.size():
		var body := CreatureItem.new()
		ents_canvas.add_child(body)
		_body_pool.append(body)
		var extra := CreatureExtraItem.new()
		ents_canvas.add_child(extra)
		_extra_pool.append(extra)

	for i in drawables.size():
		var body: CreatureItem = _body_pool[i]
		var extra: CreatureExtraItem = _extra_pool[i]
		ents_canvas.move_child(body, i * 2)
		ents_canvas.move_child(extra, i * 2 + 1)
		body.visible = true
		extra.visible = true
		var d: Variant = drawables[i]
		if d is Dictionary and (d as Dictionary).is_empty():
			_configure_player(body, extra)
		else:
			_configure_ent(body, extra, d)
		body.queue_redraw()
		extra.queue_redraw()
	for j in range(drawables.size(), _body_pool.size()):
		_body_pool[j].visible = false
		_extra_pool[j].visible = false


## TS drawPlayer (CreatureStage.ts:1540-1562). deathFade > 0.4 hides the
## player entirely (the pair just draws nothing).
func _configure_player(body: CreatureItem, extra: CreatureExtraItem) -> void:
	extra.bar_frac = -1.0
	extra.marker = false
	if sim.deathFade > 0.4:
		body.genome = {}
		body.visible = false
		return
	var blink_inv: bool = sim.invuln > 0.0 and floori(sim.time * 10.0) % 2 == 0
	body.genome = game.context.genome
	body.pose = {
		"x": sim.px,
		"y": sim.pz * CreatureSimScript.Z_TO_Y - sim.py,
		"facing": sim.facing,
		"speed": sim.speed01,
		"gaitPhase": sim.gait,
		"attack": sim.attackT,
		"hurt": sim.hurtT,
		"eat": sim.eatT,
		"airborne": clampf(sim.py / 80.0, 0.0, 1.0),
		"mood": "happy" if sim.charmActive else ("afraid" if sim.hurtT > 0.4 else "idle"),
		"scale": 2.1,
	}
	body.opts = {
		"t": sim.time,
		"lookDx": game.input.wx,
		"lookDy": game.input.wy / CreatureSimScript.Z_TO_Y,
		"alpha": 0.5 if blink_inv else 1.0,
	}


## TS drawEnt (CreatureStage.ts:1564-1602): the pose per ent state, the hp
## bar when damaged, the pack paw marker.
func _configure_ent(body: CreatureItem, extra: CreatureExtraItem, e: Dictionary) -> void:
	var y := float(e["z"]) * CreatureSimScript.Z_TO_Y - float(e.get("y", 0.0))
	if e.has("corpseT"):
		# lying corpse
		body.genome = e["genome"]
		body.pose = {
			"x": float(e["x"]), "y": y, "facing": float(e["facing"]),
			"speed": 0.0, "gaitPhase": 0.0, "attack": 0.0, "hurt": 0.0, "eat": 0.0,
			"airborne": 0.0, "mood": "dead", "scale": 2.1 * (0.5 if bool(e["baby"]) else 1.0),
		}
		body.opts = {"t": sim.time, "alpha": minf(1.0, float(e["corpseT"]) / 3.0)}
		extra.bar_frac = -1.0
		extra.marker = false
		return
	body.genome = e["genome"]
	body.pose = {
		"x": float(e["x"]), "y": y, "facing": float(e["facing"]),
		"speed": float(e["speed01"]), "gaitPhase": float(e["gait"]),
		"attack": float(e["attack"]), "hurt": float(e["hurtT"]), "eat": float(e["eatT"]),
		"airborne": clampf(float(e.get("y", 0.0)) / 80.0, 0.0, 1.0),
		"mood": String(e["mood"]),
		"scale": 2.1 * (0.5 if bool(e["baby"]) else 1.0),
	}
	body.opts = {"t": sim.time}
	var hp := float(e["hp"])
	var max_hp := float(e["maxHp"])
	if hp < max_hp * 0.999:
		extra.bar_frac = clampf(hp / max_hp, 0.0, 1.0)
		extra.bar_color = Color("#8fe89a") if hp > max_hp * 0.35 else Color("#ff8a7a")
	else:
		extra.bar_frac = -1.0
	extra.marker = bool(e["pack"])
	extra.marker_x = float(e["x"])
	extra.marker_y = y
	extra.marker_bob = sin(sim.time * 3.0 + float(e["seed"])) * 3.0


## TS update() scene-side halves (CreatureStage.ts:466-604) around sim.update.
func update(dt: float) -> void:
	if sim == null or frozen:
		return
	var editor_open: bool = bool(game.editor["open"])

	# editor (Tab or E) — charm is on F (TS:467-475). TS early-returns here;
	# natively the sim advances (the cell-stage T3 ruling) and the game's
	# editor-open gate freezes everything from the NEXT frame.
	if game.input.key_pressed("Tab") or (game.input.key_pressed("KeyE") and not editor_open):
		if sim.php <= 0.0 or sim.deathFade > 0.0:
			game.hud["toast"].call(tr("Survive first — evolve while alive"), "info", "🧬")
		else:
			sim.tut["editorOpened"] = int(sim.tut["editorOpened"]) + 1
			var show_cb: Variant = game.editor.get("show")
			if show_cb is Callable:
				show_cb.call("creature")

	# found-tribe button — TS:477-481 (click routing is scene-side)
	if _handle_tribe_click():
		sim.found_tribe()
		return

	# tutorial — TS:484 (the engine lands with task 8)
	if tutorial != null:
		tutorial.update(dt)

	# the sim mirrors game.transition_target for found_tribe's finish gate
	# (the sim cannot see the game — same shape as tribeRect)
	sim.transitionTarget = game.transition_target

	sim.update(dt, _build_input_snapshot())

	# camera — TS:571-576 (numbers verified against renderer.ts: rate 5,
	# zoom constant 1.15)
	game.cam.follow(sim.px, sim.pz * CreatureSimScript.Z_TO_Y, dt, 5.0)
	game.cam.zoom = 1.15
	var wpt: Vector2 = game.cam.to_world(game.input.mx, game.input.my, game.vw, game.vh)
	game.input.set_world(wpt.x, wpt.y)

	# fx pools — TS:577-578
	game.fx["update"].call(dt)
	fx.update(dt)

	# hud objective — TS:590-593 (the pack count recomputed here: the sim owns
	# tribeReady, the objective string is the scene's)
	var pop := 0
	for e in sim.ents:
		if bool(e["pack"]):
			pop += 1
	if hud_inst != null:
		if sim.tribeReady:
			hud_inst.show_objective = tr("FOUND A TRIBE — button bottom-right")
		else:
			hud_inst.show_objective = "%s %d/3 · %s %d/2 — %s" % [
				tr("EVOLVE: brain"), int(game.context.genome.get("brain", 0)),
				tr("pack"), pop,
				tr("hunt, charm (F), bones, meteor marrow")]

	# hud ability slots — TS:598-604
	_feed_hud_abilities()


## TS handleTribeClick (CreatureStage.ts:1631-1640): the alive gate, the hit
## test against the sim's screen-space rect, then the click consume.
func _handle_tribe_click() -> bool:
	if sim.php <= 0.0 or sim.deathFade > 0.0:
		return false
	if game.input.was_clicked() and sim.over_tribe(game.input.mx, game.input.my):
		game.input.take_click()
		return true
	return false


## TS CreatureStage.ts:598-604 — the four ability slots with the exact cd
## fractions, recomputed every stage update.
func _feed_hud_abilities() -> void:
	game.hud["set_abilities"].call([
		{"key": "LMB", "icon": "👄", "cd": 0.0},
		{"key": "F", "icon": "💚", "cd": 0.0, "active": true},
		{"key": "SPACE", "icon": "⤒",
				"cd": float(sim.jumpCd) / 1.2, "active": sim.jumpCd <= 0.0},
		{"key": "TAB", "icon": "🧬", "cd": 0.0},
	])


## TS onEnter (CreatureStage.ts:258-335) — the sim owns the body; the scene
## adds the objective line, the overlay re-install and the CAMERA RIG
## OWNERSHIP (this is the first stage that consumes the Camera2D — the menu
## and cell draw in absolute screen space and need it off again on exit).
func on_enter(from: Variant = null) -> void:
	if sim == null:
		return
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = true
	sim.on_enter()
	if hud_inst != null:
		hud_inst.show_objective = "HUNT or CHARM (hold F near a creature) — press TAB for editor"
	# the tutorial engine build lands with task 8 (TS:306-313)


func on_exit() -> void:
	if sim != null:
		sim.on_exit()
	# rig ownership: restore the disabled default the other stages expect
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = false


# ---- hooks (CreatureSim → scene/game/storyteller) -------------------------------

func _build_hooks() -> Dictionary:
	return {
		"hud_toast": _h_hud_toast,
		"hud_banner": _h_hud_banner,
		"hud_float_world": _h_hud_float_world,
		"audio_play": _h_audio_noop,
		"cam_shake": _h_cam_shake,
		"fx_burst": _h_fx_burst,
		"fx_spawn": _h_fx_spawn,
		"get_gap_bias": _h_gap_bias,
		"get_mood": _h_mood,
		"get_warn_scale": _h_warn_scale,
		"storyteller_note_chaos_event": _h_note_chaos_event,
		"context_event": _h_context_event,
		"go_to": _h_go_to,
		"tutorial_finish": _h_tutorial_finish,
	}


func _h_hud_toast(text: String, kind: String, icon: String) -> void:
	game.hud["toast"].call(text, kind, icon)


func _h_hud_banner(data: Variant) -> void:
	game.hud["banner"].call(data)


func _h_hud_float_world(x: float, y: float, text: String, color: Variant, size: float) -> void:
	game.hud["float_world"].call(x, y, text, color, size)


func _h_audio_noop(_name: String, _vol: float, _pan := 0.0) -> void:
	pass  # audio core is its own task — the sim's audio hooks stay silent


func _h_cam_shake(mag: float, dur: float) -> void:
	game.cam_shake_for(mag, dur)


func _h_fx_burst(x: float, y: float, n: int, opts: Variant) -> void:
	fx.burst_rows(x, y, n, opts)


func _h_fx_spawn(opts: Variant) -> void:
	fx.spawn(opts)


func _h_gap_bias() -> float:
	return game.storyteller.gap_bias()


func _h_mood() -> String:
	return game.storyteller.mood


func _h_warn_scale() -> float:
	return game.storyteller.warn_scale()


func _h_note_chaos_event(playtime: float) -> void:
	game.storyteller.note_chaos_event(playtime)


## TS ctx.bus.emit(EV.playerDeath, …) — routed to a Game signal; the
## storyteller pump listener is game-side (M2 T7).
func _h_context_event(ev_name: String, from_stage: String) -> void:
	game.context_event.emit(ev_name, from_stage)


## T4 carry-forward: found_tribe's stage handoff (the tribe stage itself is
## M4 — switch_stage silently no-ops on the unregistered id, TS-true).
func _h_go_to(id: String, card: Variant) -> void:
	game.go_to(id, card)


## T4 carry-forward: the founding handoff finishes the tutorial (the engine
## arrives with task 8 — absent engine = no-op).
func _h_tutorial_finish() -> void:
	if tutorial != null:
		tutorial.finish()


# ---- game-level beat gates (the pump checks the STAGE surface) ------------------

## gaia_redemption tier 2: the Lone Wanderer spawn (the sim's rare-gene quiet
## individual).
func gaia_wanderer() -> void:
	if sim != null:
		sim.gaia_wanderer()


func has_active_chaos() -> bool:
	return sim != null and sim.chaos.active_events().size() > 0


# ---- input snapshot ----------------------------------------------------------------

## T3 canonical snapshot (creature_sim.update contract): keys_pressed/keys_held
## built from the GameInput wrapper — one-shots from the frame state (cleared
## by end_frame AFTER this in Game._do_update), held codes polled live.
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
