## CELL STAGE scene node — the visual layer over the CellSim sim core
## (headless, src/game/cell/cell_sim.gd). Port of Spore src/game/cell/
## CellStage.ts render() + the scene-side halves of update()/onEnter(): camera
## follow, fx pool stepping, the editor KeyE branch overlay, the input
## SNAPSHOT build (T3 canonical keys_pressed/keys_held) and the full TS draw
## order: backdrop → boundary ring → kelp → vent glows → zones → pellets →
## ents (culled ±80) → hp bars → player (blink invuln alpha 0.45) → fx →
## vignette → glitch overlay → HP bar → death overlay → tutorial → shore
## button → HUD layer.
##
## Draw architecture: the canvas transform is reproduced MANUALLY — TS
## cam.begin is translate(vw/2+shx, vh/2+shy)·scale(zoom)·translate(−x,−y),
## which as a draw_set_transform is (screen_center + shake − zoom·cam, rot 0,
## scale zoom). The Cam rig's Camera2D child is DISABLED here (same numbers
## would transform the canvas twice); to_world/view-bounds math stays on the
## rig. The stage owns six canvas items in tree order (= draw order):
##   world canvas  — backdrop (screen space) + world sections + vignette
##   BackBufferCopy— snapshots the screen for the glitch overlay
##   glitch item   — the 'difference' composite shader (chaos 'glitch' only)
##   ui canvas     — HP bar, death overlay, tutorial chip, shore button
##   hud canvas    — the Task 8 Hud (draw-order note: TS game.ts:548 renders
##                   the hud at GAME level after the stage + transition veil;
##                   natively the stage owns that slot as its last layer — the
##                   Task 9 transition veil must slot between ui and hud)
##   editor/pause  — overlay layers above the hud, visible only when open
##                   (TS game.ts:549-550 order: hud → editor → pauseMenu)
## The overlay INSTANCES (hud/editor/pause/tutorial) are built here and
## installed into the game's stub dicts (Task 8 ruling — the dict shapes and
## every existing call site stay identical); Escape routing (game.ts:314-320)
## stays Task 9's.
extends "res://src/game/stage.gd"

const CellSimScript := preload("res://src/game/cell/cell_sim.gd")
const ParticlesScript := preload("res://src/gfx/particles.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")
const BackdropScript := preload("res://src/gfx/backdrop.gd")
const CellPainterScript := preload("res://src/gfx/cell_painter.gd")
const GlitchShader := preload("res://src/gfx/glitch_overlay.gdshader")
const TutorialScript := preload("res://src/ui/tutorial.gd")
const HudScript := preload("res://src/ui/hud.gd")
const EditorUiScript := preload("res://src/ui/editor.gd")
const PauseScript := preload("res://src/ui/pause.gd")

var sim: Variant = null            # CellSim (RefCounted sim core)
var fx: Variant = null             # stage Particles pool (TS `new Fx(1200)`)
var frozen := false                # test seam: render without stepping the sim
var glitch_forced := false         # test seam: draw the glitch overlay w/o the event
## TS CellStage private tutorial (Task 8) — built once in on_enter from
## _build_tutorial_steps(); the engine itself is src/ui/tutorial.gd.
var tutorial: Variant = null
## The Task 8 overlay instances — installed into the game stub dicts at tree
## entry (see _install_overlays); the stage keeps direct refs for drawing.
var hud_inst: Variant = null
var editor_inst: Variant = null
var pause_inst: Variant = null

var world_canvas: Node2D = null
var _back_buffer: BackBufferCopy = null
var glitch_overlay: Node2D = null
var ui_canvas: Node2D = null
var hud_canvas: Node2D = null
var editor_canvas: Node2D = null
var pause_canvas: Node2D = null


class StageCanvas extends Node2D:
	var stage: Variant = null
	var layer := "world"
	func _draw() -> void:
		if stage != null:
			stage._draw_layer(layer, self)


func _init(game_v: Variant) -> void:
	super(game_v, "cell")


func _ready() -> void:
	_install_overlays()
	# stage pool cap 1200 (TS `private fx = new Fx(1200)`); the game pool
	# (1100) hangs off game.fx since this task.
	fx = ParticlesScript.new(1200)
	# the CALLER draws the stage rng branch (sim header contract, mirrors
	# TS `this.rng = ctx.rng.branch()` in the CellStage constructor)
	sim = CellSimScript.new(game.context, game.context.rng.branch(), _build_hooks())
	sim.ensure_deck(game.context.world.seed)
	# the editor's buy→feel-stronger loop calls back into the sim
	# (TS notifyStatsChanged → stage.onStatsChanged; the sim recompute is
	# on_stats_changed — bound once, the sim is fixed for the stage's life)
	editor_inst.on_stats_changed = sim.on_stats_changed

	# TS draw-path parity: manual canvas transform (see header). Disable the
	# Camera2D rig child — it would apply the SAME transform a second time.
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = false

	world_canvas = StageCanvas.new()
	world_canvas.stage = self
	world_canvas.layer = "world"
	world_canvas.name = "WorldCanvas"
	add_child(world_canvas)
	_back_buffer = BackBufferCopy.new()
	_back_buffer.name = "GlitchBackBuffer"
	add_child(_back_buffer)
	glitch_overlay = Node2D.new()
	glitch_overlay.name = "GlitchOverlay"
	var mat := ShaderMaterial.new()
	mat.shader = GlitchShader
	glitch_overlay.material = mat
	glitch_overlay.visible = false
	glitch_overlay.draw.connect(_draw_glitch)
	add_child(glitch_overlay)
	ui_canvas = StageCanvas.new()
	ui_canvas.stage = self
	ui_canvas.layer = "ui"
	ui_canvas.name = "UICanvas"
	add_child(ui_canvas)
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


## Task 8 wiring: the TS Game constructor owns hud/pauseMenu/editor
## (game.ts:89-91); natively the stage installs the real instances into the
## game's stub dicts at tree entry — the duck-typed dict SHAPES (and every
## existing call site, game.gd and cell_sim hooks alike) stay identical, only
## the Callables become real.
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
	# the pause acts through the hooks dict (Task 8 ruling — T9 re-wires
	# game-side); the stage wires the real game methods now
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


## The pause's toast hook — pre-translated text from the pause, forwarded to
## the hud dict (the pause wraps its own tr_key literals, audit-visible there).
func _pause_toast(text: String, kind: String, icon: String) -> void:
	game.hud["toast"].call(text, kind, icon)


## Per-layer draw dispatch (StageCanvas._draw).
func _draw_layer(kind: String, ci: CanvasItem) -> void:
	match kind:
		"world":
			_draw_world(ci)
		"ui":
			_draw_ui(ci)
		"hud":
			if hud_inst != null:
				hud_inst.draw(ci, game.vw, game.vh)
		"editor":
			if editor_inst != null and editor_inst.open:
				editor_inst.draw(ci, game.vw, game.vh)
		"pause":
			if pause_inst != null and bool(game.paused):
				pause_inst.draw(ci, game.vw, game.vh)


## TS render() (CellStage.ts:1024-1199) — world sections on the world canvas.
func _draw_world(ci: CanvasItem) -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	var cam: Variant = game.cam
	var depth01 := clampf((cam.y + 900.0) / 2200.0, 0.0, 1.0)

	# screen space (identity) — TS: drawWaterBackdrop BEFORE cam.begin
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	BackdropScript.draw_water_backdrop(ci, cam, vw, vh, sim.time, float(game.context.chaos), depth01)

	# TS cam.begin: translate(vw/2+shx, vh/2+shy) · scale(zoom) · translate(-x,-y)
	var base_pos: Vector2 = Vector2(vw / 2.0 + cam.shake_x, vh / 2.0 + cam.shake_y) \
			- Vector2(cam.x, cam.y) * cam.zoom
	ci.draw_set_transform(base_pos, 0.0, Vector2(cam.zoom, cam.zoom))

	# world boundary ring
	ci.draw_arc(Vector2.ZERO, CellSimScript.WORLD_R + 30.0, 0.0, TAU, 128,
			RendererScript.css_color("rgba(120,180,255,0.10)"), 60.0)

	# kelp silhouettes (culled ±100 x / ±150 y)
	for k in sim.kelp:
		var kx := float(k["x"])
		var ky := float(k["y"])
		if kx < cam.view_l - 100.0 or kx > cam.view_r + 100.0 or ky < cam.view_t - 150.0 or ky > cam.view_b + 150.0:
			continue
		var sway := sin(sim.time * 0.8 + float(k["seed"])) * 12.0
		var curve := PackedVector2Array()
		var segs := 12
		for i in segs + 1:
			var u := float(i) / float(segs)
			var q0 := (1.0 - u) * (1.0 - u)
			var q1 := 2.0 * (1.0 - u) * u
			var q2 := u * u
			# quadraticCurveTo(kx + sway*0.5, ky - len*0.5, kx + sway, ky - len)
			curve.append(Vector2(
				q0 * kx + q1 * (kx + sway * 0.5) + q2 * (kx + sway),
				q0 * ky + q1 * (ky - float(k["len"]) * 0.5) + q2 * (ky - float(k["len"]))))
		ci.draw_polyline(curve, RendererScript.css_color("rgba(30,70,60,0.5)"), 5.0, true)

	# vents (long-lived but bounded zones)
	for z in sim.zones:
		if String(z["kind"]) == "vent":
			RendererScript.glow(ci, float(z["x"]), float(z["y"]), float(z["r"]),
					RendererScript.css_color("rgba(255,180,90,0.35)"),
					0.5 + sin(float(z["pulse"]) * 2.0) * 0.1)

	# zones
	for z2 in sim.zones:
		var zx := float(z2["x"])
		var zy := float(z2["y"])
		var zr := float(z2["r"])
		if String(z2["kind"]) == "toxin":
			var tint := RendererScript.css_color("rgba(110,255,110,0.28)")
			RendererScript.radial_disc(ci, Vector2(zx, zy), 0.0, zr, tint, Color(tint, 0.0))
		elif String(z2["kind"]) == "meteorTarget":
			ci.draw_arc(Vector2(zx, zy), zr, 0.0, TAU, 48,
					Color(1.0, 90.0 / 255.0, 90.0 / 255.0, clampf(0.4 + sin(float(z2["pulse"]) * 10.0) * 0.3, 0.0, 1.0)), 3.0)

	# pellets (culled ±30)
	for p in sim.pellets:
		var pxx := float(p["x"])
		var pyy := float(p["y"])
		if pxx < cam.view_l - 30.0 or pxx > cam.view_r + 30.0 or pyy < cam.view_t - 30.0 or pyy > cam.view_b + 30.0:
			continue
		var pulse := 1.0 + sin(sim.time * 3.0 + pxx) * 0.12
		if String(p["kind"]) == "plant":
			RendererScript.disc(ci, pxx, pyy, 4.0 * pulse, Color("#8fe89a"))
		elif String(p["kind"]) == "meat":
			RendererScript.disc(ci, pxx, pyy, 5.0 * pulse, Color("#ffb08a"))
		else:
			RendererScript.glow(ci, pxx, pyy, 14.0, RendererScript.css_color("rgba(200,140,255,0.8)"), 0.8)
			RendererScript.disc(ci, pxx, pyy, 4.4 * pulse, Color("#e2c4ff"))

	# ents (culled ±80) + hp bar when damaged
	for e in sim.ents:
		var ex := float(e["x"])
		var ey := float(e["y"])
		if ex < cam.view_l - 80.0 or ex > cam.view_r + 80.0 or ey < cam.view_t - 80.0 or ey > cam.view_b + 80.0:
			continue
		var genome: Dictionary = e["genome"]
		var pose := {
			"x": ex, "y": ey,
			"moveAngle": atan2(float(e["vy"]), float(e["vx"])),
			"speed": minf(1.0, Vector2(float(e["vx"]), float(e["vy"])).length() / 120.0),
			"scale": float(genome.get("size", 1.0)) * 1.15,
			"hurt": float(e["hurtT"]),
			"eat": float(e["eatT"]),
			"dash": 0.0,
			"seed": float(e["seed"]),
			"stun": 1.0 if float(e["stun"]) > 0.0 else 0.0,
		}
		CellPainterScript.draw_cell(ci, genome, pose, {"t": sim.time}, base_pos, cam.zoom)
		var hp := float(e["hp"])
		var max_hp := float(e["maxHp"])
		var gsize := float(genome.get("size", 1.0))
		if hp < max_hp * 0.999:
			var w := 26.0 * gsize
			ci.draw_rect(Rect2(ex - w / 2.0, ey - 14.0 * gsize - 12.0, w, 3.5), Color(0.0, 0.0, 0.0, 0.4))
			var fill := Color("#8fe89a") if hp > max_hp * 0.35 else Color("#ff8a7a")
			ci.draw_rect(Rect2(ex - w / 2.0, ey - 14.0 * gsize - 12.0, w * clampf(hp / max_hp, 0.0, 1.0), 3.5), fill)

	# player (blink invuln alpha 0.45; hidden while the death fade runs)
	if sim.deathFade < 0.1:
		var blink_inv: bool = sim.invuln > 0.0 and floori(sim.time * 10.0) % 2 == 0
		var ctx_genome: Dictionary = game.context.genome
		var p_pose := {
			"x": sim.px, "y": sim.py,
			"moveAngle": sim.moveAngle,
			"speed": minf(1.0, Vector2(sim.pvx, sim.pvy).length() / 150.0),
			"scale": float(ctx_genome.get("size", 1.0)) * (1.0 + sim.nutrition * 0.35) * 1.15,
			"hurt": sim.hurtT,
			"eat": sim.eatT,
			"dash": 1.0 if sim.dashT > 0.0 else 0.0,
			"seed": sim.playerSeed,
		}
		CellPainterScript.draw_cell(ci, ctx_genome, p_pose, {
			"t": sim.time,
			"proboscisTarget": null,
			"alpha": 0.45 if blink_inv else 1.0,
		}, base_pos, cam.zoom)

	# particles — stage pool then game pool (CellStage.ts:1146-1147)
	fx.render(ci)
	game.fx["render"].call(ci)

	# TS cam.end → vignette (screen space)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	RendererScript.vignette(ci, vw, vh, 0.5)


## The glitch overlay fillRect (CellStage.ts:1155-1161): a 'difference'
## composite rgba(120,255,180, 0.06 + sin(t*12)*0.03) — exact W3C difference
## math in the shader; the animated alpha rides the strength uniform.
func _draw_glitch() -> void:
	glitch_overlay.draw_rect(Rect2(0, 0, game.vw, game.vh), Color.WHITE)


## TS render() screen-space tail (CellStage.ts:1163-1198).
func _draw_ui(ci: CanvasItem) -> void:
	var vw: float = game.vw
	var vh: float = game.vh

	# HP bar (player)
	var hp_w := minf(340.0, vw * 0.3)
	var hx := vw / 2.0 - hp_w / 2.0
	var hy := vh - 108.0
	RendererScript.panel(ci, hx - 6.0, hy - 6.0, hp_w + 12.0, 22.0, {
		"fill": RendererScript.css_color("rgba(6,10,24,0.75)"),
		"stroke": RendererScript.css_color("rgba(255,120,140,0.25)"),
	})
	var hp_p := clampf(sim.php / sim.pmaxHp, 0.0, 1.0)
	var c0 := Color("#5aff8a") if hp_p > 0.35 else Color("#ff5a5a")
	var c1 := Color("#a8ffcf") if hp_p > 0.35 else Color("#ff9a8a")
	RendererScript.gradient_rounded_rect(ci, Rect2(hx, hy, hp_w * hp_p, 10.0), 5.0, c0, c1)
	RendererScript.outlined_text(ci, "%d / %d" % [ceili(maxf(0.0, sim.php)), roundi(sim.pmaxHp)],
			vw / 2.0, hy + 5.0, {"size": 10.0, "fill": RendererScript.css_color("rgba(255,255,255,0.9)")})

	# death overlay
	if sim.deathFade > 0.0:
		ci.draw_rect(Rect2(0, 0, vw, vh), Color(60.0 / 255.0, 0.0, 10.0 / 255.0, minf(0.55, sim.deathFade * 0.4)))
		RendererScript.outlined_text(ci, "REBIRTH IS PAINFUL", vw / 2.0, vh / 2.0 - 10.0,
				{"size": 30.0, "fill": Color("#ff9a8a")})

	# tutorial overlay — the Task 8 engine (TS renders it here, above the
	# death overlay and below the shore button); inactive engines draw nothing
	if tutorial != null:
		tutorial.draw(ci, vw, vh)

	# shore button
	if sim.shoreAvailable:
		var r: Dictionary = sim.shoreRect
		r["x"] = vw - float(r["w"]) - 26.0
		r["y"] = vh - 150.0
		var hover: bool = sim.over_shore(game.input.mx, game.input.my)
		if hover:
			game.hover_cursor()
		RendererScript.panel(ci, float(r["x"]), float(r["y"]), float(r["w"]), float(r["h"]), {
			"fill": (RendererScript.css_color("rgba(90,160,90,0.95)") if hover
					else RendererScript.css_color("rgba(40,90,50,0.9)")),
			"stroke": RendererScript.css_color("rgba(180,255,180,0.6)"),
			"lw": 2.0,
			"shadow": RendererScript.css_color("rgba(120,255,120,0.3)"),
		})
		RendererScript.outlined_text(ci, tr("🐢 CRAWL ASHORE"),
				float(r["x"]) + float(r["w"]) / 2.0, float(r["y"]) + 19.0,
				{"size": 15.0, "fill": Color("#eaffea"), "weight": "700"})
		RendererScript.outlined_text(ci, tr("begin the creature era"),
				float(r["x"]) + float(r["w"]) / 2.0, float(r["y"]) + 36.0,
				{"size": 10.0, "fill": RendererScript.css_color("rgba(230,255,230,0.7)")})


## TS update() scene-side halves around sim.update. The editor branch
## (CellStage.ts:351-359) is scene-side by the T3 ruling — the sim keeps
## running through the frame (its comment records the TS early-return skip).
func update(dt: float) -> void:
	if sim == null or frozen:
		return
	if game.input.key_pressed("KeyE") and not bool(game.editor["open"]):
		if sim.php <= 0.0 or sim.deathFade > 0.0:
			game.hud["toast"].call(tr("Survive first — evolve while alive"), "info", "🧬")
		else:
			sim.tut["editorOpened"] = int(sim.tut["editorOpened"]) + 1
			var show_cb: Variant = game.editor.get("show")
			if show_cb is Callable:
				show_cb.call("cell")
		# TS returns here — natively the sim advances (T3 ruling comment).
	# tutorial (CellStage.ts:362 — after the editor branch)
	if tutorial != null:
		tutorial.update(dt)
	sim.update(dt, _build_input_snapshot())
	# camera (CellStage.ts:450-456)
	game.cam.follow(sim.px, sim.py, dt, 5.0)
	game.cam.zoom = 1.0
	var wpt: Vector2 = game.cam.to_world(game.input.mx, game.input.my, game.vw, game.vh)
	game.input.set_world(wpt.x, wpt.y)
	game.fx["update"].call(dt)
	fx.update(dt)
	# hud ability slots (CellStage.ts:487-494)
	_feed_hud_abilities()


## TS CellStage.ts:488-494 — the five ability slots with the exact cd
## fractions, recomputed every stage update.
func _feed_hud_abilities() -> void:
	var g: Dictionary = game.context.genome
	var toxin_l: int = int(g.get("toxin", 0))
	var electro_l: int = int(g.get("electro", 0))
	var jet_l: int = int(g.get("jet", 0))
	game.hud["set_abilities"].call([
		{"key": "LMB", "icon": "👄", "cd": 0.0, "hint": "bite"},
		{"key": "1", "icon": "☠️",
				"cd": float(sim.toxinCd) / 6.0 if toxin_l > 0 else 1.0,
				"active": toxin_l > 0 and sim.toxinCd <= 0.0},
		# TS `this.pStats.dashPower >= 0 &&` is a constant-true TS expression —
		# kept verbatim (dash_power = electro ≥ 0 by the stats math)
		{"key": "2", "icon": "⚡",
				"cd": float(sim.electroCd) / 10.0
						if float(sim.pStats.get("dash_power", 0.0)) >= 0.0 and electro_l > 0 else 1.0,
				"active": electro_l > 0 and sim.electroCd <= 0.0},
		{"key": "SPACE", "icon": "💨",
				"cd": float(sim.dashCd) / 3.0 if jet_l > 0 else 1.0,
				"active": jet_l > 0 and sim.dashCd <= 0.0},
		{"key": "E", "icon": "🧬", "cd": 0.0},
	])


## Per-frame draw hook (Game's render side): refresh overlay state and queue
## all canvases (Node2D._draw fires on the next draw pass).
func render() -> void:
	if world_canvas == null:
		return
	var glitch_on: bool = sim.chaos.is_active("glitch") or glitch_forced
	# the copy only runs while the overlay can consume it (hidden overlay =
	# no per-frame screen copy)
	_back_buffer.visible = glitch_on
	glitch_overlay.visible = glitch_on
	if glitch_on:
		(glitch_overlay.material as ShaderMaterial).set_shader_parameter(
				"strength", 0.06 + sin(sim.time * 12.0) * 0.03)
	world_canvas.queue_redraw()
	ui_canvas.queue_redraw()
	hud_canvas.queue_redraw()
	var editor_open: bool = bool(game.editor["open"])
	editor_canvas.visible = editor_open
	if editor_open:
		editor_canvas.queue_redraw()
	pause_canvas.visible = bool(game.paused)
	if pause_canvas.visible:
		pause_canvas.queue_redraw()


## C1 deck rebuild + the TS onEnter resets (CellStage.ts:221-233) — arrivals
## arrive healthy; the sim's rng branch is NOT re-drawn (the stage constructor
## owns it, as in TS).
func on_enter(from: Variant = null) -> void:
	if sim == null:
		return
	sim.ensure_deck(game.context.world.seed)
	sim.on_stats_changed()
	sim.php = sim.pmaxHp  # arrivals arrive healthy (mirrors creature)
	sim.invuln = 3.0
	sim.deathFade = 0.0
	sim.deathStarted = false
	# TS CellStage.ts:250 — the shore gate reads the live genome
	sim.shoreAvailable = float(game.context.genome.get("legs", 0)) >= 1.0
	# TS CellStage.ts:249 — the objective line (raw EN key; the hud translates
	# at draw)
	if hud_inst != null:
		hud_inst.show_objective = "EAT. GROW. EVOLVE. — press E to edit your genome"
	# TS CellStage.ts:252-261 — the first-run tutorial (per save slot)
	if tutorial == null:
		tutorial = TutorialScript.new(game, "tutCell", _build_tutorial_steps())


func on_exit() -> void:
	if sim != null:
		game.context.eco = sim.eco
	# TS onExit: the tutorial finishes on every exit EXCEPT a quit-to-title
	# (CellStage.ts:264-267) — the flag persists only on forward evolution.
	if game.transition_target != "menu":
		if tutorial != null:
			tutorial.finish()


## TS CellStage.ts:253-260 — the first-run tutorial table, verbatim. Step
## texts stay raw EN keys (translated at render by the engine); done lambdas
## poll the sim counters (and, for the legs step, the live genome).
func _build_tutorial_steps() -> Array:
	return [
		{"id": "move", "text": "Hold LEFT MOUSE — swim toward the cursor.",
			"done": func() -> bool: return float(sim.tut["moved"]) > 140.0},
		{"id": "eat", "text": "Bump into the green bits to EAT them. Food is DNA.",
			"done": func() -> bool: return int(sim.tut["eaten"]) >= 3},
		{"id": "editor", "text": "Press E — the EDITOR. Buy parts with DNA (try a Flagellum).",
			"done": func() -> bool: return int(sim.tut["editorOpened"]) >= 1},
		{"id": "kill", "text": "Smaller cells are FOOD — bite one (E first to upgrade if it fights back!).",
			"done": func() -> bool: return int(sim.tut["killed"]) >= 1},
		{"id": "legs", "text": "Buy a LEG (65 DNA), then press the 🐢 CRAWL ASHORE button.",
			"done": func() -> bool: return float(game.context.genome.get("legs", 0)) >= 1.0},
	]


# ---- hooks (CellSim → scene/game/storyteller) -------------------------------------

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
		"game_save_all": _h_game_save_all,
		"shore_travel": _h_shore_travel,
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
## storyteller pump listener lands with Task 9.
func _h_context_event(ev_name: String, from_stage: String) -> void:
	game.context_event.emit(ev_name, from_stage)


func _h_game_save_all() -> void:
	game.save_all()


## TS CellStage.ts:365-370 — consume the click (it must not leak into the
## next stage) then the goTo with the exact card.
func _h_shore_travel() -> void:
	game.input.take_click()
	game.go_to("creature", {"title": "THE LONG WALK",
			"sub": "400 million years of ambition, one nervous step onto land"})


# ---- input snapshot ----------------------------------------------------------------

## T3 canonical snapshot (cell_sim.update contract): keys_pressed/keys_held
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
