## Game orchestrator: owns the stage machine, cinematic transitions and the
## global tick. Port of Spore src/game/game.ts — THIS TASK is the plumbing:
## goTo/updateTransition ported 1:1 including the pendingGoTo + survivesQuit
## semantics (game.ts:190-359), the stage registry, and input/cam/loop wiring.
## NOT this task (Task 9): autosave, chaos settle, karma drift, pumpWorldStory,
## narration latches, pause/editor bodies, resetStagesForNewRun. HUD click
## routing and KeyM/Escape handling land with the HUD/audio tasks — the stub
## dicts below keep the TS call sites greppable until then.
## Cross-class references ride preload consts with duck-typed vars (M1 -s-mode
## rule: global class_name resolution needs the editor's script class cache).
class_name Game
extends Node

const InputScript := preload("res://src/core/input.gd")
const LoopScript := preload("res://src/core/loop.gd")
const CamScript := preload("res://src/game/cam.gd")
const ContextScript := preload("res://src/game/context.gd")
const StorytellerScript := preload("res://src/game/storyteller.gd")
const I18nScript := preload("res://src/core/i18n.gd")

signal stage_changed(stage_id: String)

var context: Variant = null      # M1 GameContext
var input: Variant = null        # GameInput wrapper (src/core/input.gd)
var cam: Variant = null          # Cam rig (src/game/cam.gd)
var loop: Variant = null         # GameLoop (src/core/loop.gd)
var storyteller: Variant = null  # M1 Storyteller
var i18n: Variant = null         # I18n core (src/core/i18n.gd)

var vw := 800.0
var vh := 600.0
var muted := false
var paused := false

var stages := {}                  # StageId -> Stage (TS private stages Map)
var current: Variant = null       # live Stage (TS private current)
var transition: Variant = null    # {phase, t, dur, next, title, sub} | null
var pending_go_to: Variant = null # {id, card, survivesQuit} | null

## Stubs of the TS overlays, dictionaries of no-op Callables replaced by their
## tasks (hud/editor: UI tasks; fx: particles task). editor keeps an "open"
## flag because the update loop reads it.
var hud: Dictionary = {}
var editor: Dictionary = {"open": false}
var fx: Dictionary = {}


func _init(context_v: Variant = null) -> void:
	context = context_v if context_v != null else ContextScript.new()
	input = InputScript.new()
	cam = CamScript.new()
	storyteller = StorytellerScript.new()
	# i18n (Task 2): vi.csv -> TranslationServer + user://settings.cfg (lang/
	# muted). apply_locale pushes the saved lang so plain tr() call sites
	# (context.gd) resolve per the user's setting; muted mirrors TS getMuted().
	i18n = I18nScript.new()
	muted = i18n.get_muted()
	i18n.apply_locale()
	hud = {
		"update": func(_dt: float) -> void: pass,
		"dismiss_banner": func() -> void: pass,
		"toast": func(_text: String, _kind: String, _icon: String) -> void: pass,
		"banner": func(_data: Variant) -> void: pass,
		"float_world": func(_x: float, _y: float, _text: String, _color: Variant,
				_size: float) -> void: pass,
		"pointer_down": func(_x: float, _y: float) -> bool: return false,
	}
	editor["update"] = func(_dt: float) -> void: pass
	editor["close"] = func() -> void: pass
	fx = {
		"clear": func() -> void: pass,
		"update": func(_dt: float) -> void: pass,
		"burst": func(_x: float, _y: float, _n: int, _opts: Variant = null) -> void: pass,
		"spawn": func(_opts: Variant = null) -> void: pass,
	}
	# TS GameLoop(deps) — update per fixed step, render once per process frame.
	loop = LoopScript.new(_do_update, _do_render)


func _ready() -> void:
	add_child(cam)  # cam._ready creates + currents its Camera2D child
	_resize()
	get_viewport().size_changed.connect(_resize)


## The real input pipeline feed (TS window listeners): one-shots + clicks land
## in the wrapper; held keys poll the singleton inside queries.
func _unhandled_input(event: InputEvent) -> void:
	input.handle_event(event)


func _process(delta: float) -> void:
	loop.tick(delta)


# ---- stage management --------------------------------------------------------

func register(stage: Variant) -> void:
	stages[stage.id] = stage
	add_child(stage)  # stages are Nodes — tree entry for later draw work


## TS goTo (game.ts:190). `card` = {title, sub} Dictionary or null; `opts` may
## carry survivesQuit for the quit-cancels-stale-queues rule.
func go_to(id: String, card: Variant = null, opts: Variant = null) -> void:
	if transition != null:
		# same-destination re-requests during the fade are the stage's exit
		# button re-firing every tick — drop them (double cards, 33 saves)
		if transition["next"] == id and pending_go_to == null:
			return
		# queue instead of dropping — a victory/ascension firing mid-transition
		# must not be silently lost (civ → space softlock)
		pending_go_to = {
			"id": id, "card": card,
			"survivesQuit": opts != null and opts.get("survivesQuit", false) == true,
		}
		return
	transition = {
		"phase": "out", "t": 0.0, "dur": 0.55,
		"next": id,
		"title": card.get("title", "") if card != null else "",
		"sub": card.get("sub", "") if card != null else "",
	}
	# TS also plays the 'warp' audio cue here (audio core: its own task).


## TS switchStage (game.ts:208): an unregistered target silently returns —
## TS-true behavior.
func switch_stage(id: String) -> void:
	var next: Variant = stages.get(id)
	if next == null:
		return
	fx["clear"].call()
	hud["dismiss_banner"].call()
	if current != null:
		current.on_exit()
	var from: Variant = current.id if current != null else null
	current = next
	context.stage = id
	# per-stage storyteller signals reset here in TS (narration: Task 9)
	next.on_enter(from)
	stage_changed.emit(id)  # TS context.bus.emit(EV.stageChanged) — M1 signal port


## Where the live transition is heading (null when idle) — stages use it to
## distinguish forward evolutions from quit-to-title (TS transitionTarget).
var transition_target: Variant:
	get:
		return transition["next"] if transition != null else null


var stage: Variant:
	get:
		return current


## Test hook: advance the game by n fixed update steps without rendering
## (TS stepForTesting) — the bot/loop-manual path.
func step_for_testing(n := 1, dt := 1.0 / 60.0) -> void:
	if current == null:
		switch_stage("menu")
	loop.tick_manual(n, dt)


## TS start() also loop.start()s the rAF; here _process drives the loop.
func start() -> void:
	if current == null:
		switch_stage("menu")


## TS stop() cancels the rAF; nothing to do with a _process-driven loop.
func stop() -> void:
	pass


func _resize() -> void:
	var rs := get_viewport().get_visible_rect().size
	vw = rs.x
	vh = rs.y
	input.vw = vw
	input.vh = vh


# ---- frame -------------------------------------------------------------------

## The loop's update side — TS Game.update(dt) with this task's scope (see
## class header for what lands in Task 9 / later tasks).
func _do_update(dt: float) -> void:
	var c: Variant = context
	c.playtime += dt
	# editor & pause freeze gameplay
	var blocked: bool = paused or editor["open"]
	if not blocked:
		_update_transition(dt)
		# TS routes hud clicks first here (hud is a stub until the UI task)
		# freeze the stage sim during the story card — the WELCOME BACK card
		# used to burn the arrival invuln and spawn-ambush the player (TS:285)
		if transition == null or transition["phase"] != "card":
			if current != null:
				current.update(dt)
		cam.update(dt)
		cam.update_view_bounds(vw, vh)
		fx["update"].call(dt)
		# autosave / chaos settle / karma drift / pumpWorldStory: Task 9
	# KeyM mute (Task 2 audio) and Escape→pause (pause menu task) route here
	# in TS game.ts:313-320.
	hud["update"].call(dt)
	input.end_frame()


## The loop's render side — once per process frame.
func _do_render(_alpha: float) -> void:
	if current != null:
		current.render()


## TS updateTransition (game.ts:325-359) — ported 1:1 including the click
## consume and the quit-cancels-stale-queues rule.
func _update_transition(dt: float) -> void:
	var tr: Variant = transition
	if tr == null:
		return
	tr["t"] += dt
	if tr["phase"] == "out" and tr["t"] >= tr["dur"]:
		if tr["next"] != null:
			switch_stage(tr["next"])
		tr["phase"] = "card" if tr["title"] != "" else "in"
		tr["t"] = 0.0
		tr["dur"] = 2.2 if tr["title"] != "" else 0.6
		if tr["title"] != "" and input.was_clicked():
			tr["t"] = tr["dur"]
	elif tr["phase"] == "card":
		if tr["t"] >= tr["dur"] or input.was_clicked():
			# consume the dismissing click — it used to leak into the newly
			# entered stage and accidentally re-found a tribe / crawl ashore
			input.take_click()
			tr["phase"] = "in"
			tr["t"] = 0.0
			tr["dur"] = 0.6
	elif tr["phase"] == "in" and tr["t"] >= tr["dur"]:
		var finished_to: Variant = tr["next"]
		transition = null
		# a QUIT to the title cancels stale queued goTos (civ victory
		# auto-space hijacked the title) but a CONTINUE clicked during the
		# fade is a live request, not stale — only survivors pass
		if finished_to == "menu":
			if pending_go_to == null or not pending_go_to["survivesQuit"]:
				pending_go_to = null
		if pending_go_to != null:
			var p: Dictionary = pending_go_to
			pending_go_to = null
			go_to(p["id"], p.get("card"))


## Flush the live stage's volatile state, THEN write the save (TS saveAll).
## Stages expose persist_state() as they land.
func save_all() -> bool:
	if current != null and current.has_method("persist_state"):
		current.persist_state()
	return context.save()


## Convenience for stages: shake the main camera (TS camShakeFor).
func cam_shake_for(mag: float, dur: float) -> void:
	cam.shake(mag, dur)
