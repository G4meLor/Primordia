## TRIBE STAGE scene node — the RTS-lite village's visual layer over the
## TribeSim sim core (headless, src/game/tribe/tribe_sim.gd). Port of Spore
## src/game/tribe/TribeStage.ts render() + renderHud (1176-1423) and the
## scene-side halves of update()/onEnter(): the camera follow/zoom, the
## cam.toWorld input feed, the fx pool steps, the HUD ability slots, the
## hudRects hover cursor and the full TS draw order: land backdrop (screen)
## → cam.begin → lawn gradient (two stops hsl(105−chaos·30, 0.3, 0.28) /
## hsl(95−chaos·30, 0.36, 0.2), NO isNight dim — tribe flavor) → dirt
## (drawGround, depth 500 — creature used 400) → rival camps (disc + 3 totem
## poles + name) → bushes (berries) → huts (walls/roof/door + damage cracks +
## 🏠hp label) → great totem (progress-scaled pole + discs + glow + label)
## → trees AFTER the totem (sway quadratic trunk + crown, burn recolor) →
## entities z-sorted (tribesmen scale 1.7 + role/cargo icon + hp bar 28×3,
## rival warriors scale 1.7 + ⚔️, beast scale 2.6 + 🦁 + hp bar 48×4, the
## chief — the player creature — scale 2.1 mood 'happy' + 👑, hidden while
## deathFade > 0.4) → fire glows on top → fx pools → cam.end → flat night
## overlay rgba(10,10,40,0.4) at isNight (0.55, 0.95) → vignette 0.4 → HUD
## panels (stockpile + hut/totem buttons) → death card.
##
## Draw architecture — the creature_stage pattern verbatim: the Camera2D rig
## is enabled on enter and the VIEWPORT carries the camera transform, so the
## world canvases (ground/ents/fx) draw at identity in world coordinates and
## the screen-space canvases (sky/ui/veil/hud/pause) cancel the live viewport
## canvas_transform with affine_inverse() (TS screen-space sections stay
## pixel-anchored and un-shaken). Ownership: on_enter enables the rig,
## on_exit disables it again (menu/cell draw in absolute screen space).
##
## Creature draw protocol — the 3-RID painter contract (task 6): one
## CreatureItem scene child PER CREATURE (never two creatures on one item —
## RS child items composite after ALL of the parent item's own commands), each
## with a body item + an extras item (role/cargo icon + hp bar) as ADJACENT
## tree siblings, re-ordered every frame into the z-sorted TS order — the
## icons/bars interleave exactly like the TS drawables' tails. The painter's
## three sub-RIDs are caller-owned: freed at the top of every _draw and on
## node teardown. Pool cap 1000 (TS `private fx = new Fx(1000)`, TS:58).
##
## Camera numbers (TS TribeStage.ts:371-372): follow(px, pz·Z_TO_Y, dt, 4)
## and zoom = 0.95 CONSTANT — the TRIBE numbers, NOT the creature's 5/1.15
## (plan Global Constraints: per-stage constants, do not share).
##
## hudRects (the creature tribeRect pattern): the SIM owns the rects and
## hit-tests + dispatches them in update (TS:291-303); the stage re-positions
## them every render (_sync_hud_rects — the TS renderHud filter+push,
## TS:1411-1412/1419-1420). A consumed click sets the snapshot's take_click
## flag; the stage then mirrors TS inp.takeClick() by clearing the shared
## wrapper's one-shot (TS mutated the shared input object).
##
## Recorded divergences / TS-verbatim quirks (parity-pin ledger):
##  - the entity z-sort ties break by INSERTION ORDER (an index tiebreak) —
##    JS Array.sort is stable (ES2019), GDScript sort_custom is not; the
##    insertion order replicates the TS list build (tribe → rivalWarriors →
##    beast → chief) exactly.
##  - isNight is a stage-side helper reading sim.dayPhase (TS:1396-1398 is a
##    TribeStage method in TS too); the sim stays render-free.
##  - the totem PROGRESS label is `TOTEM ${Math.round(p)}%` with
##    p = progress/100 (TS:1292) — it literally reads 0% until the pole is
##    half built and 1% after (a TS quirk); ported verbatim. The totem BUTTON
##    label uses Math.round(progress) (TS:1422) and reads sensibly.
##  - no editor overlay: TS TribeStage has no editor surface (no Tab/E
##    handler) — the game.editor dict keeps whatever the last creature
##    install left (closed; the editor blocks gameplay so a founding click
##    can never fire under it). The PAUSE overlay is installed (the game
##    pauses in tribe like anywhere else).
##  - the land backdrop's god-ray block composites normally (backdrop.gd
##    header divergence — one canvas item cannot mix blend modes per call).
extends "res://src/game/stage.gd"

const TribeSimScript := preload("res://src/game/tribe/tribe_sim.gd")
const ParticlesScript := preload("res://src/gfx/particles.gd")

const RendererScript := preload("res://src/gfx/renderer.gd")
const BackdropScript := preload("res://src/gfx/backdrop.gd")
const CreaturePainter := preload("res://src/gfx/creature_painter.gd")
const HudScript := preload("res://src/ui/hud.gd")
const PauseScript := preload("res://src/ui/pause.gd")

## Below this a viewport dimension cannot be a real playable window (the QC r1
## B4 collapse reported 0–300 px against an 1152×648 window) — a transient
## X11/llvmpipe size glitch; keep the last frame instead of recording it.
const MIN_RENDER_VW := 64.0
const MIN_RENDER_VH := 64.0


## QC r1 B4 — the frame-size sanity check behind render()'s freeze: the game's
## vw/vh mirror the root viewport's visible rect, which equals the OS window
## size by construction (no stretch/content scale is configured). A game size
## far below the real window (or simply tiny) is the collapsed-report glitch,
## not a real resize; rendering it produced the flat gray captures. Headless
## servers report a degenerate window, so there the check degrades to the
## plain MIN_RENDER floor (headless tests never render these stages anyway).
## game.gd's `_resize`/`_resize_ok` runs the same check at the vw/vh latch —
## this per-stage freeze stays as the second line of defense.
func _frame_size_sane() -> bool:
	if game.vw < MIN_RENDER_VW or game.vh < MIN_RENDER_VH:
		return false
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x < MIN_RENDER_VW or win.y < MIN_RENDER_VH:
		return true  # no trustworthy window reference — accept the game size
	return game.vw >= float(win.x) * 0.5 and game.vh >= float(win.y) * 0.5

var sim: Variant = null            # TribeSim (RefCounted sim core)
var fx: Variant = null             # stage Particles pool (TS `new Fx(1000)`)
var frozen := false                # test seam: render without stepping the sim
## The overlay instances — installed into the game stub dicts at tree entry
## and re-installed on enter (the creature stage's pattern).
var hud_inst: Variant = null
var pause_inst: Variant = null

var sky_canvas: Node2D = null
var ground_canvas: Node2D = null
var ents_canvas: Node2D = null
var fx_canvas: Node2D = null
var ui_canvas: Node2D = null
var veil_canvas: Node2D = null
var hud_canvas: Node2D = null
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


## The TS drawables' tails (role/cargo icon + hp bar) on their own item so
## they interleave per-drawable exactly like the TS command stream: entity i's
## icon/bar draws before entity i+1's body.
class TribeExtraItem extends Node2D:
	var icon := ""            # "" = no icon
	var icon_x := 0.0
	var icon_y := 0.0
	var icon_size := 9.0
	var icon_color := Color.WHITE
	var bar_frac := -1.0      # < 0 = no bar
	var bar_x := 0.0
	var bar_y := 0.0
	var bar_w := 0.0
	var bar_h := 0.0
	var bar_color := Color.WHITE

	func _draw() -> void:
		if icon != "":
			RendererScript.outlined_text(self, icon, icon_x, icon_y,
					{"size": icon_size, "fill": icon_color})
		if bar_frac >= 0.0:
			draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.0, 0.0, 0.0, 0.4))
			draw_rect(Rect2(bar_x, bar_y, bar_w * bar_frac, bar_h), bar_color)


func _init(game_v: Variant) -> void:
	super(game_v, "tribe")


func _ready() -> void:
	_install_overlays()
	# stage pool cap 1000 (TS `private fx = new Fx(1000)`); the game pool
	# (1100) hangs off game.fx
	fx = ParticlesScript.new(1000)
	# the CALLER draws the stage rng branch (sim header contract, mirrors
	# TS `this.rng = game.context.rng.branch()` in the TribeStage constructor)
	sim = TribeSimScript.new(game.context, game.context.rng.branch(), _build_hooks())

	# TS draw-path parity (see header): world canvases draw at identity and the
	# enabled Camera2D carries the transform. The rig boots disabled (menu/cell
	# own the screen-space default) — THIS stage turns it on in on_enter and
	# off again in on_exit.
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
	pause_canvas = StageCanvas.new()
	pause_canvas.stage = self
	pause_canvas.layer = "pause"
	pause_canvas.name = "PauseCanvas"
	pause_canvas.visible = false
	add_child(pause_canvas)


## The overlay wiring (the creature stage's _install_overlays, minus the
## editor — TS TribeStage has no editor surface; see the header). Called from
## _ready (first build) AND on_enter (rebind): the instances are created once
## and reused, so the live dicts always point at the CURRENT stage's
## instances.
func _install_overlays() -> void:
	if hud_inst == null:
		hud_inst = HudScript.new(game)
	game.hud = {
		"update": hud_inst.update,
		"dismiss_banner": hud_inst.dismiss_banner,
		"toast": hud_inst.toast,
		"toast_gate": hud_inst.toast_gate,
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


## TS render() head (TribeStage.ts:1176-1183): the land backdrop, screen
## space BEFORE cam.begin. horizonScreenY is the world y=0 line.
func _draw_sky(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_screen_inv())
	var cam: Variant = game.cam
	var horizon_y: float = game.vh / 2.0 + (0.0 - cam.y) * cam.zoom
	BackdropScript.draw_land_backdrop(ci, cam, game.vw, game.vh, sim.time,
			float(game.context.chaos), sim.dayPhase, horizon_y)


## TS render() world sections (TribeStage.ts:1185-1300), in world
## coordinates (the enabled rig carries the camera): lawn → dirt → rival
## camps → bushes → huts → totem → trees (after the totem for layering).
func _draw_ground(ci: CanvasItem) -> void:
	var cam: Variant = game.cam
	var chaos := float(game.context.chaos)
	var lawn_h := _lawn_h()

	# lawn (pseudo-depth band) — TS:1187-1192 (two-stop vertical gradient,
	# NO isNight dim — tribe flavor; the creature stage dims 0.12/0.10)
	var top := RendererScript.hsl(105.0 - chaos * 30.0, 0.3, 0.28)
	var bottom := RendererScript.hsl(95.0 - chaos * 30.0, 0.36, 0.2)
	ci.draw_polygon(
			PackedVector2Array([
				Vector2(cam.view_l, 0), Vector2(cam.view_r, 0),
				Vector2(cam.view_r, lawn_h), Vector2(cam.view_l, lawn_h)]),
			PackedColorArray([top, top, bottom, bottom]))

	# dirt below — TS:1193 (depth 500 — creature used 400)
	BackdropScript.draw_ground(ci, cam.view_l, cam.view_r, lawn_h, 500.0, sim.time, chaos)

	# rival camps — TS:1196-1208
	for r in sim.rivals:
		if float(r["hp"]) <= 0.0:
			continue
		var rx := float(r["x"])
		var ry := float(r["z"]) * TribeSimScript.Z_TO_Y
		RendererScript.disc(ci, rx, ry, 60.0, RendererScript.css_color("rgba(120,60,40,0.25)"))
		# totem poles
		for i in 3:
			var px := rx - 24.0 + float(i) * 24.0
			ci.draw_rect(Rect2(px - 4.0, ry - 34.0, 8.0, 34.0), RendererScript.hsl(30.0, 0.3, 0.35))
			RendererScript.disc(ci, px, ry - 38.0, 6.0, RendererScript.hsl(10.0, 0.5, 0.45))
		RendererScript.outlined_text(ci, String(r["name"]), rx, ry - 56.0,
				{"size": 12.0, "fill": RendererScript.css_color("rgba(255,200,160,0.8)")})

	# bushes — TS:1231-1243
	for b in sim.bushes:
		var bx := float(b["x"])
		if bx < cam.view_l - 60.0 or bx > cam.view_r + 60.0:
			continue
		var by := float(b["z"]) * TribeSimScript.Z_TO_Y
		ci.draw_colored_polygon(
				RendererScript.ellipse_points(Vector2(bx, by - 9.0), 15.0, 10.0, 0.0),
				RendererScript.hsl(120.0, 0.36, 0.24))
		var food := float(b["food"])
		if food > 0.5:
			var berries: int = mini(4, ceili(food / 2.0))
			for i in berries:
				RendererScript.disc(ci, bx - 7.0 + float(i) * 5.0,
						by - 12.0 - float(i % 2) * 4.0, 2.4, Color("#ff6a9a"))

	# huts — TS:1246-1278
	for h in sim.huts:
		var hx := float(h["x"])
		var hy := float(h["z"]) * TribeSimScript.Z_TO_Y
		var built: bool = float(h["buildT"]) <= 0.0
		var alpha := 1.0 if built else 0.5  # TS globalAlpha
		# walls
		var wall := RendererScript.hsl(30.0, 0.32, 0.4 if built else 0.3)
		wall.a *= alpha
		ci.draw_rect(Rect2(hx - 22.0, hy - 26.0, 44.0, 26.0), wall)
		# roof
		var roof := RendererScript.hsl(18.0, 0.42, 0.34)
		roof.a *= alpha
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(hx - 30.0, hy - 24.0), Vector2(hx, hy - 52.0), Vector2(hx + 30.0, hy - 24.0)]), roof)
		# door
		var door := RendererScript.hsl(28.0, 0.3, 0.2)
		door.a *= alpha
		ci.draw_rect(Rect2(hx - 7.0, hy - 14.0, 14.0, 14.0), door)
		# damage cracks — inside the TS save/globalAlpha context (TS:1250-1275),
		# so an unbuilt hut's cracks stroke at 0.6·0.5
		if float(h["hp"]) < float(h["maxHp"]) * 0.6:
			var crack := RendererScript.css_color("rgba(20,10,5,0.6)")
			crack.a *= alpha
			ci.draw_polyline(
					PackedVector2Array([
						Vector2(hx - 12.0, hy - 20.0), Vector2(hx - 4.0, hy - 8.0),
						Vector2(hx - 10.0, hy - 2.0)]),
					crack, 2.0, true)
		# TS draws the label AFTER restore — full alpha regardless of buildT
		RendererScript.outlined_text(ci, "🏠%d" % roundi(float(h["hp"])), hx, hy + 12.0,
				{"size": 9.0, "fill": RendererScript.css_color("rgba(255,255,255,0.5)")})

	# totem (great) — TS:1281-1294
	if bool(sim.totem["active"]) or float(sim.totem["progress"]) > 0.0:
		var ty := 60.0 * TribeSimScript.Z_TO_Y
		var p: float = float(sim.totem["progress"]) / 100.0
		ci.draw_rect(Rect2(-10.0, ty - 90.0 * p, 20.0, 90.0 * p), RendererScript.hsl(40.0, 0.4, 0.4))
		if p > 0.3:
			RendererScript.disc(ci, -10.0, ty - 90.0 * p + 8.0, 10.0, RendererScript.hsl(10.0, 0.5, 0.5))
		if p > 0.6:
			RendererScript.disc(ci, 10.0, ty - 90.0 * p + 8.0, 10.0, RendererScript.hsl(200.0, 0.5, 0.5))
		if p >= 1.0:
			RendererScript.glow(ci, 0.0, ty - 100.0, 60.0,
					RendererScript.css_color("rgba(255,220,120,0.6)"), 0.9)
		if bool(sim.totem["active"]) and p < 1.0:
			# TS:1292 quirk — `TOTEM ${Math.round(p)}%` with p the 0..1
			# fraction: the label reads 0% until half-built, then 1%. Verbatim.
			# (string via the totem_progress_label seam — pinned headless)
			RendererScript.outlined_text(ci, totem_progress_label(p), 0.0, ty - 90.0 * p - 16.0,
					{"size": 11.0, "fill": Color("#ffe08a")})

	# trees (after totem for layering, TS:1296-1300; drawTree TS:1211-1228)
	for tr in sim.trees:
		var tx := float(tr["x"])
		if tx < cam.view_l - 80.0 or tx > cam.view_r + 80.0:
			continue
		var y := float(tr["z"]) * TribeSimScript.Z_TO_Y
		var sway := sin(sim.time * 0.6 + float(tr["seed"])) * 2.5
		# trunk: quadraticCurveTo(x+sway, y-34, x+sway*1.6, y-58), lw 8
		var trunk := PackedVector2Array()
		var segs := 8
		for k in segs + 1:
			var u := float(k) / float(segs)
			var q0 := (1.0 - u) * (1.0 - u)
			var q1 := 2.0 * (1.0 - u) * u
			var q2 := u * u
			trunk.append(Vector2(
				q0 * tx + q1 * (tx + sway) + q2 * (tx + sway * 1.6),
				q0 * y + q1 * (y - 34.0) + q2 * (y - 58.0)))
		ci.draw_polyline(trunk, RendererScript.hsl(28.0, 0.32, 0.26), 8.0, true)
		# crown
		var leaf := RendererScript.hsl(20.0, 0.8, 0.45) if float(tr["burn"]) > 0.0 \
				else RendererScript.hsl(120.0, 0.38, 0.26)
		ci.draw_colored_polygon(
				RendererScript.ellipse_points(Vector2(tx + sway * 1.6, y - 68.0), 26.0, 20.0, 0.0), leaf)
		if float(tr["burn"]) > 0.0:
			RendererScript.glow(ci, tx, y - 40.0, 40.0,
					RendererScript.css_color("rgba(255,150,50,0.6)"), 0.8)


## TS render() tail (TribeStage.ts:1371-1377): the fire glows ON TOP of the
## z-sorted entities, then the particle pools, in world space.
func _draw_fx(ci: CanvasItem) -> void:
	for f in sim.fires:
		var y: float = float(f["z"]) * TribeSimScript.Z_TO_Y
		RendererScript.glow(ci, float(f["x"]), y - 10.0, 34.0,
				RendererScript.css_color("rgba(255,140,40,0.65)"), 0.8)
	fx.render(ci)
	game.fx["render"].call(ci)


## TS render() screen-space tail (TribeStage.ts:1380-1393) + renderHud
## (1400-1423): flat night overlay, vignette, HUD panels/buttons, death card.
## Runs with the camera transform cancelled (drawn after cam.end).
func _draw_ui(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_screen_inv())
	var vw: float = game.vw
	var vh: float = game.vh

	# night overlay — TS:1380-1383 (FLAT rgba(10,10,40,0.4) full canvas; the
	# creature stage ramps depth·0.42 instead — tribe flavor)
	if _is_night():
		ci.draw_rect(Rect2(0, 0, vw, vh), Color(10.0 / 255.0, 10.0 / 255.0, 40.0 / 255.0, 0.4))

	# vignette — TS:1384
	RendererScript.vignette(ci, vw, vh, 0.4)

	# resources + buttons — TS:1387
	_render_hud(ci, vh)

	# death card — TS:1389-1393 (the title is NOT translate-wrapped in TS —
	# unwrapped stays unwrapped)
	if sim.deathFade > 0.0:
		ci.draw_rect(Rect2(0, 0, vw, vh),
				Color(60.0 / 255.0, 0.0, 10.0 / 255.0, minf(0.55, sim.deathFade * 0.4)))
		RendererScript.outlined_text(ci, "THE CHIEF HAS FALLEN", vw / 2.0, vh / 2.0,
				{"size": 26.0, "fill": Color("#ff9a8a")})


## TS renderHud (TribeStage.ts:1400-1423) — the stockpile panel + the hut and
## totem build buttons. The RECTS are re-registered every render by
## _sync_hud_rects (the sim hit-tests them in update).
func _render_hud(ci: CanvasItem, vh: float) -> void:
	# stockpile panel — TS:1403-1405
	RendererScript.panel(ci, 18.0, vh - 172.0, 210.0, 52.0, {
		"fill": RendererScript.css_color("rgba(6,10,24,0.85)"),
		"stroke": RendererScript.css_color("rgba(255,220,150,0.3)"),
	})
	RendererScript.outlined_text(ci, "🍒 %d   🪵 %d" % [roundi(sim.food), roundi(sim.wood)],
			28.0, vh - 146.0, {"size": 16.0, "fill": Color("#ffe8c0"), "align": "left"})
	RendererScript.outlined_text(ci, "👥 %d/%d   🏠 %d"
			% [sim.tribe.size(), sim.pop_cap(), sim.huts.size()],
			28.0, vh - 128.0, {"size": 13.0,
					"fill": RendererScript.css_color("rgba(255,232,192,0.7)"), "align": "left"})

	# build hut button — TS:1408-1414
	var bw := 170.0
	var bh := 40.0
	var bx := 18.0
	var by := vh - 110.0
	var can_hut: bool = sim.wood >= 40.0
	RendererScript.panel(ci, bx, by, bw, bh, {
		"fill": RendererScript.css_color("rgba(60,120,80,0.9)") if can_hut
				else RendererScript.css_color("rgba(50,55,65,0.9)"),
		"stroke": RendererScript.css_color("rgba(180,255,190,0.4)"),
	})
	RendererScript.outlined_text(ci, tr("R · HUT (40🪵)"), bx + bw / 2.0, by + 20.0,
			{"size": 13.0, "fill": Color("#eaffea")})

	# totem button — TS:1417-1422
	var tx := 18.0
	var ty := vh - 64.0
	var active: bool = bool(sim.totem["active"])
	var can_totem: bool = not active and sim.food >= 100.0 and sim.wood >= 80.0
	RendererScript.panel(ci, tx, ty, bw, bh, {
		"fill": RendererScript.css_color("rgba(150,120,40,0.9)") if active
				else (RendererScript.css_color("rgba(160,120,40,0.95)") if can_totem
				else RendererScript.css_color("rgba(50,55,65,0.9)")),
		"stroke": RendererScript.css_color("rgba(255,230,150,0.5)"),
	})
	RendererScript.outlined_text(ci,
			("🗿 TOTEM %d%%" % roundi(float(sim.totem["progress"]))) if active
					else tr("T · TOTEM (100🍒 80🪵)"),
			tx + bw / 2.0, ty + 20.0, {"size": 12.0, "fill": Color("#fff8e8")})


func _lawn_h() -> float:
	return (TribeSimScript.Z_MAX + 120.0) * TribeSimScript.Z_TO_Y


## The TS:1292 progress-label seam — `TOTEM ${Math.round(p)}%` with p the
## 0..1 fraction (progress/100), NOT the percent: Math.round(0.75) is 1, so
## the label literally reads 0% until the pole is half-built and 1% after
## (the TS quirk; the totem BUTTON label at TS:1422 rounds the percent and
## reads sensibly). Static so the renderer-seam assert
## (tests/test_tribe_scene.gd) pins the live production string — the draw
## site below consumes this, never a copy.
static func totem_progress_label(p: float) -> String:
	return "TOTEM %d%%" % roundi(p)


## TS isNight (TribeStage.ts:1396-1398) — stage-side in TS too.
func _is_night() -> bool:
	return sim.dayPhase > 0.55 and sim.dayPhase < 0.95


## Per-frame draw hook (Game's render side): rebuild the z-sorted creature
## item order, re-register the hudRects, queue all canvases.
func render() -> void:
	if sky_canvas == null or sim == null:
		return
	# QC r1 B4 — same degenerate-viewport guard as the creature stage: the
	# X11/llvmpipe viewport can transiently report a collapsed size while the
	# window keeps its real extent, and recording that frame crams every
	# vw-anchored draw into a left sliver over the clear color. Keep the LAST
	# recorded frame until the viewport reports a usable size again.
	if not _frame_size_sane():
		return
	_sync_creature_items()
	_sync_hud_rects()
	sky_canvas.queue_redraw()
	ground_canvas.queue_redraw()
	fx_canvas.queue_redraw()
	ui_canvas.queue_redraw()
	veil_canvas.queue_redraw()
	hud_canvas.queue_redraw()
	pause_canvas.visible = bool(game.paused)
	if pause_canvas.visible:
		pause_canvas.queue_redraw()


## TS renderHud's rect registration (TribeStage.ts:1411-1412/1419-1420):
## filter+push per action, re-registered EVERY render with the live viewport
## geometry. The sim hit-tests + dispatches them in update (TS:291-303) — one
## frame of positional lag, TS-identical (TS update also reads the rects the
## previous render wrote).
func _sync_hud_rects() -> void:
	sim.hudRects = sim.hudRects.filter(func(b) -> bool:
		return String(b["action"]) != "hut" and String(b["action"]) != "totem")
	var bw := 170.0
	var bh := 40.0
	sim.hudRects.append({"action": "hut",
			"r": {"x": 18.0, "y": game.vh - 110.0, "w": bw, "h": bh}})
	sim.hudRects.append({"action": "totem",
			"r": {"x": 18.0, "y": game.vh - 64.0, "w": bw, "h": bh}})


## TS render()'s entity pass (TribeStage.ts:1303-1368): the drawables build in
## TS insertion order (tribe → rivalWarriors → beast → chief) and sort by z —
## ties break by insertion index (JS sort is stable; GDScript's is not).
## Each drawable maps to a pooled (body, extras) node pair at adjacent tree
## indices; hidden pairs stay pooled for the next population swing.
func _sync_creature_items() -> void:
	var drawables: Array = []
	var ord := 0
	for t in sim.tribe:
		drawables.append({"kind": "tribesman", "e": t, "z": float(t["z"]), "ord": ord})
		ord += 1
	for w in sim.rivalWarriors:
		drawables.append({"kind": "warrior", "e": w, "z": float(w["z"]), "ord": ord})
		ord += 1
	if sim.beast != null:
		drawables.append({"kind": "beast", "e": sim.beast, "z": float(sim.beast["z"]), "ord": ord})
		ord += 1
	drawables.append({"kind": "chief", "e": null, "z": sim.pz, "ord": ord})
	drawables.sort_custom(func(a, b) -> bool:
		if float(a["z"]) != float(b["z"]):
			return float(a["z"]) < float(b["z"])
		return int(a["ord"]) < int(b["ord"]))

	while _body_pool.size() < drawables.size():
		var body := CreatureItem.new()
		ents_canvas.add_child(body)
		_body_pool.append(body)
		var extra := TribeExtraItem.new()
		ents_canvas.add_child(extra)
		_extra_pool.append(extra)

	for i in drawables.size():
		var body: CreatureItem = _body_pool[i]
		var extra: TribeExtraItem = _extra_pool[i]
		ents_canvas.move_child(body, i * 2)
		ents_canvas.move_child(extra, i * 2 + 1)
		body.visible = true
		extra.visible = true
		var d: Dictionary = drawables[i]
		match String(d["kind"]):
			"tribesman":
				_configure_tribesman(body, extra, d["e"])
			"warrior":
				_configure_warrior(body, extra, d["e"])
			"beast":
				_configure_beast(body, extra, d["e"])
			"chief":
				_configure_chief(body, extra)
		body.queue_redraw()
		extra.queue_redraw()
	for j in range(drawables.size(), _body_pool.size()):
		_body_pool[j].visible = false
		_extra_pool[j].visible = false


## TS tribesman drawable (TribeStage.ts:1305-1325): pose, role/cargo icon,
## hp bar 28×3 when damaged.
func _configure_tribesman(body: CreatureItem, extra: TribeExtraItem, t: Dictionary) -> void:
	var y := float(t["z"]) * TribeSimScript.Z_TO_Y
	body.genome = t["genome"]
	body.pose = {
		"x": float(t["x"]), "y": y, "facing": float(t["facing"]),
		"speed": float(t["speed01"]), "gaitPhase": float(t["gait"]),
		"attack": float(t["attack"]), "hurt": float(t["hurtT"]), "eat": float(t["eatT"]),
		"airborne": 0.0, "mood": String(t["mood"]), "scale": 1.7,
	}
	body.opts = {"t": sim.time}
	# role + cargo markers (TS:1315) — carrying is null | "food" | "wood"
	# (match on the raw Variant: String(null) has no constructor)
	var icon: String
	match t["carrying"]:
		"food":
			icon = "🍒"
		"wood":
			icon = "🪵"
		_:
			match String(t["role"]):
				"warrior":
					icon = "⚔️"
				"hunt":
					icon = "🥩"
				_:
					icon = "🍒"
	extra.icon = icon
	extra.icon_x = float(t["x"])
	extra.icon_y = y - 46.0
	extra.icon_size = 9.0
	extra.icon_color = Color("#fff")
	var hp := float(t["hp"])
	var max_hp := float(t["maxHp"])
	if hp < max_hp * 0.99:
		extra.bar_frac = hp / max_hp  # TS:1321 — unclamped (hp ≤ maxHp invariant)
		extra.bar_x = float(t["x"]) - 14.0
		extra.bar_y = y - 40.0
		extra.bar_w = 28.0
		extra.bar_h = 3.0
		extra.bar_color = Color("#8fe89a")
	else:
		extra.bar_frac = -1.0


## TS rival-warrior drawable (TribeStage.ts:1326-1337).
func _configure_warrior(body: CreatureItem, extra: TribeExtraItem, w: Dictionary) -> void:
	var y := float(w["z"]) * TribeSimScript.Z_TO_Y
	body.genome = w["genome"]
	body.pose = {
		"x": float(w["x"]), "y": y, "facing": float(w["facing"]),
		"speed": 0.8, "gaitPhase": float(w["gait"]),
		"attack": 0.0, "hurt": 0.0, "eat": 0.0,
		"airborne": 0.0, "mood": "angry", "scale": 1.7,
	}
	body.opts = {"t": sim.time}
	extra.icon = "⚔️"
	extra.icon_x = float(w["x"])
	extra.icon_y = y - 46.0
	extra.icon_size = 9.0
	extra.icon_color = Color("#ffb0a0")
	extra.bar_frac = -1.0


## TS beast drawable (TribeStage.ts:1338-1354): facing flips by chief side,
## gait rides the stage clock, hp bar 48×4 #ff5a5a.
func _configure_beast(body: CreatureItem, extra: TribeExtraItem, b: Dictionary) -> void:
	var y := float(b["z"]) * TribeSimScript.Z_TO_Y
	body.genome = b["genome"]
	body.pose = {
		"x": float(b["x"]), "y": y,
		"facing": -1.0 if float(b["x"]) > sim.px else 1.0,
		"speed": 0.6, "gaitPhase": sim.time * 5.0,
		"attack": 0.0, "hurt": 0.0, "eat": 0.0,
		"airborne": 0.0, "mood": "angry", "scale": 2.6,
	}
	body.opts = {"t": sim.time}
	extra.icon = "🦁"
	extra.icon_x = float(b["x"])
	extra.icon_y = y - 76.0
	extra.icon_size = 12.0
	extra.icon_color = Color("#ffb0a0")
	extra.bar_frac = clampf(float(b["hp"]) / 420.0, 0.0, 1.0)
	extra.bar_x = float(b["x"]) - 24.0
	extra.bar_y = y - 68.0
	extra.bar_w = 48.0
	extra.bar_h = 4.0
	extra.bar_color = Color("#ff5a5a")


## TS chief drawable (TribeStage.ts:1355-1366): the chief IS the player
## creature (ctx genome, scale 2.1, mood 'happy'); deathFade > 0.4 hides the
## pair entirely.
func _configure_chief(body: CreatureItem, extra: TribeExtraItem) -> void:
	extra.icon = ""
	extra.bar_frac = -1.0
	if sim.deathFade > 0.4:
		body.genome = {}
		body.visible = false
		return
	body.genome = game.context.genome
	body.pose = {
		"x": sim.px, "y": sim.pz * TribeSimScript.Z_TO_Y, "facing": float(sim.facing),
		"speed": sim.speed01, "gaitPhase": sim.gait,
		"attack": 0.0, "hurt": 0.0, "eat": 0.0,
		"airborne": 0.0, "mood": "happy", "scale": 2.1,
	}
	body.opts = {"t": sim.time}
	extra.icon = "👑"
	extra.icon_x = sim.px
	extra.icon_y = sim.pz * TribeSimScript.Z_TO_Y - 62.0
	extra.icon_size = 11.0
	extra.icon_color = Color("#ffe08a")


## TS update() scene-side halves (TribeStage.ts:278-418) around sim.update:
## the hudRects hover cursor, the input SNAPSHOT, camera follow/zoom, the
## cam.toWorld feed, fx pool steps and the HUD ability slots.
func update(dt: float) -> void:
	if sim == null or frozen:
		return

	# HUD panel hover (TS:284-290 — setCursor('pointer') is scene-side; the
	# sim owns the click dispatch)
	for b in sim.hudRects:
		if _inside(game.input.mx, game.input.my, b["r"]):
			game.hover_cursor()

	var inp: Dictionary = _build_input_snapshot()
	sim.update(dt, inp)
	# a hud-panel click the sim consumed sets the snapshot's take_click flag —
	# mirror TS inp.takeClick() mutating the SHARED input (the wrapper's
	# one-shot clears so nothing else re-sees the click this frame)
	if bool(inp.get("take_click", false)):
		game.input.take_click()

	# camera — TS:371-377 (the TRIBE numbers: follow rate 4, zoom 0.95)
	game.cam.follow(sim.px, sim.pz * TribeSimScript.Z_TO_Y, dt, 4.0)
	game.cam.zoom = 0.95
	var wpt: Vector2 = game.cam.to_world(game.input.mx, game.input.my, game.vw, game.vh)
	game.input.set_world(wpt.x, wpt.y)

	# fx pools — TS:378-379
	game.fx["update"].call(dt)
	fx.update(dt)

	# hud ability slots — TS:412-417
	_feed_hud_abilities()


func _inside(mx: float, my: float, r: Dictionary) -> bool:
	return mx >= float(r["x"]) and mx <= float(r["x"]) + float(r["w"]) \
			and my >= float(r["y"]) and my <= float(r["y"]) + float(r["h"])


## TS TribeStage.ts:412-417 — the three role slots, active when EVERY
## tribesman holds that role (and the tribe is not empty), cd 0.
func _feed_hud_abilities() -> void:
	var all_gather: bool = not sim.tribe.is_empty()
	var all_hunt: bool = not sim.tribe.is_empty()
	var all_war: bool = not sim.tribe.is_empty()
	for t in sim.tribe:
		var role := String(t["role"])
		if role != "gather":
			all_gather = false
		if role != "hunt":
			all_hunt = false
		if role != "warrior":
			all_war = false
	game.hud["set_abilities"].call([
		{"key": "1", "icon": "🍒", "cd": 0.0, "active": all_gather},
		{"key": "2", "icon": "🥩", "cd": 0.0, "active": all_hunt},
		{"key": "3", "icon": "⚔️", "cd": 0.0, "active": all_war},
	])


## TS onEnter (TribeStage.ts:139-191) — the sim owns the body (restore /
## re-found / pack conversion + the toastInset/objective hooks); the scene
## adds the overlay re-install and the CAMERA RIG OWNERSHIP.
func on_enter(from: Variant = null) -> void:
	_install_overlays()
	if sim == null:
		return
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = true
	sim.on_enter()


func on_exit() -> void:
	if sim != null:
		sim.on_exit()
	# rig ownership: restore the disabled default the other stages expect
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = false


## TS TribeStage.onExit → persistState (TribeStage.ts:193) — the autosave
## flush seam: game.save_all()/the 60s autosave call current.persist_state()
## (game.ts:239/296 optional call, like the creature stage).
func persist_state() -> void:
	if sim != null:
		sim.persist_state()


# ---- hooks (TribeSim → scene/game/storyteller) -----------------------------------

func _build_hooks() -> Dictionary:
	return {
		"hud_toast": _h_hud_toast,
		"hud_toast_gate": _h_hud_toast_gate,
		"hud_banner": _h_hud_banner,
		"hud_toast_inset": _h_hud_toast_inset,
		"hud_show_objective": _h_hud_show_objective,
		"hud_float_world": _h_hud_float_world,
		"audio_play": _h_audio_noop,
		"audio_set_mood": _h_audio_noop,
		"cam_shake": _h_cam_shake,
		"fx_burst": _h_fx_burst,
		"fx_spawn": _h_fx_spawn,
		"get_gap_bias": _h_gap_bias,
		"get_mood": _h_mood,
		"get_warn_scale": _h_warn_scale,
		"storyteller_note_chaos_event": _h_note_chaos_event,
		"context_event": _h_context_event,
		"go_to": _h_go_to,
		"save_all": _h_save_all,
	}


func _h_hud_toast(text: String, kind: String, icon: String) -> void:
	game.hud["toast"].call(text, kind, icon)


## QC round-2 B3: gate toasts (conditions that persist across retarget ticks —
## the gatherer dead-zone) ride hud.toast's longer dedupe window. Recorder
## huds (tests) and the boot stubs only implement the plain 3-arg "toast" —
## fall back so routing tests and bots keep working unchanged.
func _h_hud_toast_gate(text: String, kind: String, icon: String, window: float) -> void:
	if game.hud.has("toast_gate"):
		game.hud["toast_gate"].call(text, kind, icon, window)
	else:
		game.hud["toast"].call(text, kind, icon)


func _h_hud_banner(data: Variant) -> void:
	game.hud["banner"].call(data)


func _h_hud_toast_inset(px: float) -> void:
	# TS:154 — game.hud.toastInset = 190 (clears the stockpile panel + buttons;
	# toasts draw at vh − 30 − inset, hud.gd reads toast_inset)
	if hud_inst != null:
		hud_inst.toast_inset = float(px)


func _h_hud_show_objective(text: String) -> void:
	if hud_inst != null:
		hud_inst.show_objective = text


func _h_hud_float_world(x: float, y: float, text: String, color: Variant, size: float) -> void:
	game.hud["float_world"].call(x, y, text, color, size)


func _h_audio_noop(_name: String, _vol := 0.0, _pan := 0.0) -> void:
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


## The fall/victory stage handoffs (TS:396/407) — 'creature' is registered;
## 'civ' stays unregistered until M5 (switch_stage silently no-ops, TS-true).
func _h_go_to(id: String, card: Variant) -> void:
	game.go_to(id, card)


func _h_save_all() -> void:
	game.save_all()


func has_active_chaos() -> bool:
	return sim != null and sim.has_active_chaos()


# ---- input snapshot ----------------------------------------------------------------

## The M2 canonical snapshot (tribe_sim.update contract): keys_pressed/
## keys_held built from the GameInput wrapper — one-shots from the frame state
## (cleared by end_frame AFTER this in Game._do_update), held codes polled
## live. wx/wy were set by the PREVIOUS frame's cam.to_world (TS-identical:
## TS update reads the world coords the previous update wrote).
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
