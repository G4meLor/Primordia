## First-run tutorial: passive step-by-step guidance drawn above the ability
## bar. Each stage owns one; conditions poll live game state so the tutorial
## reacts to however the player actually plays. Skippable; progress persists
## per save slot via context.flags. Port of Spore src/ui/tutorial.ts (frozen).
##
## Task 8 ruling: RefCounted (matches the TS class shape — no Control node);
## the owning scene draws it via draw() inside its screen-space UI layer (the
## cell stage calls it between the death overlay and the shore button, TS
## CellStage.ts render order). Steps are Arrays of {id, text, done} with done a
## zero-arg Callable polling live state (TS's done(g) closures bind the same
## state — the game reference rides the constructor). Step texts stay raw EN
## keys and translate at RENDER time (tr_key), matching the T5 banner ruling.
## The skip chip needs a 0.4 s HOLD — it sits inside the swim zone and one
## accidental mid-swim tap used to silently kill the whole tutorial (TS
## comment). Audio cues (TS audio.play 'click'/'dna') wait for the audio task.
class_name TutorialUi
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")

var active := true
## TS private idx/justAdvanced — read by tests through the step_index getter.
var idx := 0
var just_advanced := 0.0
## TS private skipRect — recomputed by draw(); update() hit-tests the last
## drawn chip (identical ordering to TS, where render mutates the rect).
var skip_rect := {"x": 0.0, "y": 0.0, "w": 92.0, "h": 30.0}
var skip_hold := 0.0

var _game: Variant = null
var _flag_key := ""
var _steps: Array = []


func _init(game_v: Variant, flag_key: String, steps: Array) -> void:
	_game = game_v
	_flag_key = flag_key
	_steps = steps
	if _game.context.flags.get(flag_key, null) == "done":
		active = false


var step_index: int:
	get:
		return idx


var step_count: int:
	get:
		return _steps.size()


## Mark complete (skip or natural end) and persist per slot — with a stage-
## state flush (game.save_all), or the skip itself could roll back on reload.
func finish() -> void:
	if not active:
		return
	active = false
	_game.context.flags[_flag_key] = "done"
	_game.save_all()


func update(dt: float) -> void:
	if not active:
		return
	just_advanced = maxf(0.0, just_advanced - dt)
	var input: Variant = _game.input

	# skip button requires a 0.4s HOLD (see class header)
	var r: Dictionary = skip_rect
	var over := float(input.mx) >= float(r["x"]) and float(input.mx) <= float(r["x"]) + float(r["w"]) \
			and float(input.my) >= float(r["y"]) and float(input.my) <= float(r["y"]) + float(r["h"])
	if over:
		_game.hover_cursor()
	if bool(input.is_down()) and over:
		skip_hold += dt
		if skip_hold > 0.4:
			input.take_click()
			# TS audio.play('click') — audio core is its own task
			finish()
			return
	else:
		skip_hold = 0.0

	# TS `if (!step) { this.finish(); return; }` — the exhausted table (a
	# custom steps list shorter than the advances) finishes defensively
	if idx >= _steps.size():
		finish()
		return
	var step: Dictionary = _steps[idx]
	var done: Variant = step["done"]
	if done.call():
		idx += 1
		just_advanced = 0.8
		# TS audio.play('dna', 0.5)
		if idx >= _steps.size():
			finish()
			_game.hud["toast"].call(
					_game.i18n.tr_key("Editor tutorial done — the rest is evolution. Good luck."),
					"good", "🎓")


## TS render(): the step chip above the ability bar. Screen-space — the owning
## scene draws at identity.
func draw(ci: CanvasItem, vw: float, vh: float) -> void:
	if not active:
		return
	if idx >= _steps.size():
		return
	var step: Dictionary = _steps[idx]

	var w := minf(560.0, vw - 40.0)
	var x := vw / 2.0 - w / 2.0
	var y := vh - 184.0
	var h := 62.0

	RendererScript.panel(ci, x, y, w, h, {
		"fill": RendererScript.css_color("rgba(10,18,40,0.92)"),
		"stroke": RendererScript.css_color("rgba(255,220,140,0.55)"),
		"lw": 1.6,
		"shadow": RendererScript.css_color("rgba(255,200,100,0.18)"),
	})

	# header: TUTORIAL · step x/y
	RendererScript.outlined_text(ci, "%s %d/%d" % [_game.i18n.tr_key("TUTORIAL"), idx + 1, _steps.size()],
			x + 14.0, y + 16.0, {
				"size": 10.0, "fill": Color("#ffd77a"), "align": "left",
			})
	# progress pips
	for i in _steps.size():
		var px := x + 108.0 + float(i) * 10.0
		var col := Color("#8fe89a") if i < idx else (Color("#ffd77a") if i == idx
				else RendererScript.css_color("rgba(255,255,255,0.15)"))
		ci.draw_circle(Vector2(px, y + 15.0), 3.0, col)

	# step text (raw EN key on the step dict → translated at render)
	RendererScript.outlined_text(ci, _game.i18n.tr_key(String(step["text"])),
			x + 14.0, y + 40.0, {
				"size": 13.0, "fill": Color("#fff3d8"), "align": "left", "maxWidth": w - 128.0,
			})

	# skip button
	skip_rect = {"x": x + w - 100.0, "y": y + 16.0, "w": 86.0, "h": 30.0}
	RendererScript.panel(ci, float(skip_rect["x"]), float(skip_rect["y"]),
			float(skip_rect["w"]), float(skip_rect["h"]), {
				"fill": RendererScript.css_color("rgba(30,40,70,0.9)"),
				"stroke": RendererScript.css_color("rgba(150,180,220,0.35)"),
			})
	RendererScript.outlined_text(ci, _game.i18n.tr_key("hold to skip"),
			float(skip_rect["x"]) + float(skip_rect["w"]) / 2.0,
			float(skip_rect["y"]) + 15.0, {
				"size": 10.0 if skip_hold > 0.0 else 11.0,
				"fill": Color("#ffe08a") if skip_hold > 0.0 else Color("#cfe2ff"),
			})
