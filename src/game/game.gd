## Game orchestrator: owns the stage machine, cinematic transitions and the
## global tick. Port of Spore src/game/game.ts — full orchestrator parity
## (Task 9): goTo/updateTransition with the pendingGoTo + survivesQuit
## semantics (game.ts:190-359), the stage registry + stageFactory rebuild,
## resetStagesForNewRun/resetNarration, autosave (60s, never menu/transition),
## chaos settle + karma drift, KeyM mute, Escape routing, hud-first click
## routing, and pumpWorldStory (world reveal toasts, storyteller signals,
## beat offers/cases — game.ts:361-521). The transition veil renders through
## draw_transition_veil() on each stage's veil layer (native draw-order
## ruling — the TS game-level overlay became a per-stage layer between UI
## and hud; see cell_stage.gd's header).
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
const ParticlesScript := preload("res://src/gfx/particles.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const TraitsScript := preload("res://src/evo/world_traits.gd")

signal stage_changed(stage_id: String)
## TS ctx.bus.emit(EV.playerDeath, …) shape (M2 T7): the cell sim's
## context_event hook routes here; the pump's listener (game.ts:80-88) lives
## in _on_context_event below.
signal context_event(ev_name: String, from_stage: String)

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

# ---- Task 9 narration/flow state (TS game.ts privates, verbatim names) --------
## TS autosaveT (game.ts:59) — accumulates every unblocked frame; the WRITE is
## gated on stage != menu && no transition, the timer reset is not.
var autosave_t := 0.0
## Per-stage storyteller signals (game.ts:60-61) — reset on every switch_stage
## and by reset_narration.
var deaths_in_stage := 0
var stage_time := 0.0
## gaia_redemption tier 1: playtime of the run's FIRST death (-1 = none).
## The death itself stays one-way; the beat only narrates 3.5s later.
var gaia_death_at := -1.0
## Sliding window of DNA events for the 60s dnaRate mood signal (game.ts:67).
var dna_window: Array = []
## Beat offers are blacked out until this playtime (death fade ~1.8s, TS uses
## a 2s gate) — game.ts:69.
var dying_until := 0.0
## Composition root injects its stage constructors here (TS game.ts:124
## stageFactory). Callable() == TS null: reset_stages_for_new_run degrades to
## a narration-only wipe in boots that never injected one (the manual-stage
## tests).
var stage_factory: Callable = Callable()

## TS `_cursor` (game.ts:153) — dedupes the per-frame cursor writes.
var _cursor := "default"
## A UI layer requested the pointer cursor this frame (hover_cursor). The
## frame resolution keeps it without re-touching the DisplayServer — every
## X11 cursor-shape CHANGE swallows the next queued motion event, so the
## TS per-frame base-set + hover-override pattern must not flap natively.
var _hover_seen := false
## The game-level Particles pool (TS `fx = new Particles(1100)`) behind the
## stub-dict Callables — cap per the M2 T7 ruling.
var _fx_pool: Variant = null

## Stubs of the TS overlays, dictionaries of no-op Callables replaced by their
## tasks (hud/editor/pause: Task 8 UI; fx: particles task). editor keeps an
## "open" flag because the update loop reads it.
var hud: Dictionary = {}
var editor: Dictionary = {"open": false}
var pause: Dictionary = {}
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
		"toast": _stub_toast,  # method Callable: the world-toast call passes 5 args
		"banner": func(_data: Variant) -> void: pass,
		"float_world": func(_x: float, _y: float, _text: String, _color: Variant,
				_size: float) -> void: pass,
		"pointer_down": func(_x: float, _y: float) -> bool: return false,
		"set_toast_inset": func(_px: float) -> void: pass,
	}
	editor["update"] = func(_dt: float) -> void: pass
	editor["close"] = func() -> void: pass
	pause = {
		"open": func() -> void: pass,
		"update": func(_dt: float) -> void: pass,
	}
	# TS `fx = new Particles(1100)` — the real pool under the stub-dict shape;
	# bursts stay no-ops until their callers land, render/update are live.
	_fx_pool = ParticlesScript.new(1100)
	fx = {
		"clear": _fx_clear,
		"update": _fx_update,
		"burst": _fx_burst,
		"spawn": _fx_spawn,
		"render": _fx_render,
	}
	# TS GameLoop(deps) — update per fixed step, render once per process frame.
	loop = LoopScript.new(_do_update, _do_render)
	# world-story signal taps (game.ts:77-88): the net-DNA ledger feeds the
	# 60s dnaRate window; player deaths bump the per-stage counter, open the
	# gaia ledger and start the beat-offer blackout.
	context.dna_gained.connect(_on_dna_gained)
	context_event.connect(_on_context_event)


func _ready() -> void:
	add_child(cam)  # cam._ready creates + currents its Camera2D child
	_resize()
	get_viewport().size_changed.connect(_resize)


## Pre-hud stub (real hud replaces this dict at the cell stage's tree entry).
## A method (not a lambda) so the world-toast shape's 5-arg call applies the
## defaults — lambdas error on an argument-count mismatch.
func _stub_toast(_text: String, _kind: String, _icon: String, _ttl := 4.0,
		_card: Variant = null) -> void:
	pass


## Stage visibility for the native tree model (switch_stage / factory rebuild):
## stage NODES are plain Nodes (stage.gd) — the drawables are their CanvasItem
## children (the cell stage's six canvases, the menu's MenuCanvas). A
## CanvasItem stage hides directly. The cell stage re-derives its overlay
## canvases' visibility every render(), so re-showing is clean.
func _set_stage_visible(st: Variant, vis: bool) -> void:
	if st is CanvasItem:
		st.visible = vis
		return
	for ch in st.get_children():
		if ch is CanvasItem:
			ch.visible = vis


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
	# the boot registry starts HIDDEN — the factory-rebuild doctrine applied to
	# the boot instances (a visible stage draws ONCE on tree entry, and that
	# one-shot layer composites ABOVE every stage registered before it
	# forever: the M6 space registration find — the last-registered stage's
	# opaque backdrop covered the live stage's output, and would cover a
	# CONTINUE's landed stage in the real boot the same way). add_child fires
	# the stage _ready inline when the Game is in the tree, so the canvases
	# exist here; in the out-of-tree -s boots nothing hides yet and nothing
	# draws. switch_stage shows the stage it makes current.
	_set_stage_visible(stage, false)


## TS resetStagesForNewRun (game.ts:109-121): rebuild every gameplay stage
## with fresh instances — a NEW LIFE must not inherit run-1 volatile state
## latched in the singletons (totem progress 100 auto-won tribe in 3s,
## victoryFired bricked civ, stale cities/system, surviving black holes).
## Called by MenuStage.start_new_game(). The narration wipe sits ABOVE the
## factory guard (TS order): a new run must wipe it even in boots that never
## injected a stageFactory.
func reset_stages_for_new_run() -> void:
	reset_narration()
	if not stage_factory.is_valid():
		return
	for st in stage_factory.call():
		# native tree-model note (TS GC has no analog): the replaced instance's
		# node must not leak — non-current ones free immediately; the CURRENT
		# one stays live until it is switched away from (switch_stage frees
		# the orphan there). Fresh instances hide until they become current —
		# a visible stage draws once on tree entry, which would flash the new
		# run's world under the menu during the out-fade.
		var old: Variant = stages.get(st.id)
		if old != null and old != current:
			old.queue_free()
		stages[st.id] = st
		add_child(st)
		_set_stage_visible(st, false)
	# current stays whatever is live (menu) — the next go_to() switch_stage
	# picks the fresh instance out of the map


## TS resetNarration (game.ts:130-139): wipe every run-scoped narration latch
## — mood/beats, the death-window blackout, the gaia ledger, the DNA window.
## Called by NEW LIFE and by CONTINUE (a loaded save must not inherit the
## quitting run's narration state — blacked-out offers, a ghost gaia card, an
## instant bless).
func reset_narration() -> void:
	storyteller.reset()
	deaths_in_stage = 0
	stage_time = 0.0
	gaia_death_at = -1.0
	dna_window = []
	# playtime resets to 0 on a fresh run — a dead run's window left anchored
	# at the old playtime would black out every beat offer for ~T+2
	dying_until = 0.0


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
	# TS:213 — a new stage starts with the inset the TS game zeroes; stages
	# with bottom-left UI re-arm their own inset in on_enter (tribe 190)
	hud["set_toast_inset"].call(0.0)
	if current != null:
		current.on_exit()
		# native tree-model note (TS immediate-mode redraws only the live
		# stage): stages are persistent children, so the node we leave hides.
		# An orphaned instance (a factory rebuild replaced its map entry while
		# it was current) frees here — TS drops the dead reference to the GC.
		var orphan: bool = not stages.values().has(current)
		_set_stage_visible(current, false)
		if orphan:
			current.queue_free()
	var from: Variant = current.id if current != null else null
	current = next
	context.stage = id
	# per-stage storyteller signals start clean on every switch (TS:219-221)
	deaths_in_stage = 0
	stage_time = 0.0
	_set_stage_visible(next, true)
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
	# TS game.ts:262 sets the frame's base cursor here and lets UI layers
	# upgrade it on hover; natively the base resolves at the END of the frame
	# (see the tail of this func) so a steady hover never flaps the OS shape.
	var base_cursor := "crosshair"
	if current == null or current.id == "menu" or paused:
		base_cursor = "default"
	elif transition != null and transition["phase"] == "card":
		base_cursor = "pointer"
	var c: Variant = context
	c.playtime += dt
	# editor & pause freeze gameplay
	var blocked: bool = paused or editor["open"]
	if not blocked:
		_update_transition(dt)
		# route clicks: hud buttons first (TS game.ts:276-281) — a hud hit
		# consumes the click so the stage never sees it
		if input.was_clicked() and transition == null:
			if hud["pointer_down"].call(input.mx, input.my):
				input.take_click()
		# freeze the stage sim during the story card — the WELCOME BACK card
		# used to burn the arrival invuln and spawn-ambush the player (TS:285)
		if transition == null or transition["phase"] != "card":
			if current != null:
				current.update(dt)
			pump_world_story(dt)
		cam.update(dt)
		cam.update_view_bounds(vw, vh)
		fx["update"].call(dt)
		# autosave (never on the title screen — it would downgrade the slot;
		# never mid-transition — the stage switch would half-flush volatile
		# state). The TIMER accumulates unconditionally (TS:292-299).
		autosave_t += dt
		if autosave_t > 60.0:
			autosave_t = 0.0
			if context.stage != "menu" and transition == null:
				save_all()
		# chaos slowly settles toward the difficulty's resting level —
		# peaceful promised calm and used to climb to normal's floor anyway
		# (TS:302-303; raw adds like TS — the settle target never overflows)
		var settle_at: float = 0.05 if context.difficulty == "peaceful" \
				else (0.25 if context.difficulty == "chaos" else 0.12)
		context.chaos += (settle_at - context.chaos) * minf(1.0, dt * 0.03)
		# karma drift lifts an 'aggressive' player back toward neutral (ambient
		# contact kills used to floor passivity at -1) but never erodes a
		# HARMONIOUS score — the drift used to delete the pacifist ending
		if context.karma < 0.0:
			context.karma += (0.0 - context.karma) * minf(1.0, dt * 0.003)
	else:
		# TS game.ts:308-311 — while an overlay blocks gameplay the overlay
		# menus tick instead of the stage (pause first, then the editor).
		pause["update"].call(dt)
		editor["update"].call(dt)
	# KeyM mute (TS:313 — the pause help line advertises it) and Escape routing
	# (TS:314-320): editor close > pause close > pause open — Esc on the title
	# screen never opens the IN-GAME pause (its 'Save now' would write
	# stage:'menu' over a real save slot), and never mid-transition.
	if input.key_pressed("KeyM"):
		toggle_mute()
	if input.key_pressed("Escape"):
		if bool(editor["open"]):
			editor["close"].call()
		elif paused:
			close_pause()
		elif context.stage != "menu" and transition == null:
			open_pause()
	hud["update"].call(dt)
	# frame cursor resolution (TS game.ts:262 moved here): UI hover upgrades
	# win — and a steady hover re-applies nothing (each X11 shape change
	# swallows the next queued motion event, so idle frames stay silent)
	if _hover_seen:
		_hover_seen = false
	else:
		set_cursor(base_cursor)
	input.end_frame()


## The loop's render side — once per process frame.
func _do_render(_alpha: float) -> void:
	if current != null:
		current.render()


## TS game.render()'s transition overlay (game.ts:529-547), drawn by each
## stage's veil layer — native draw-order ruling (cell_stage.gd header): the
## TS game-level overlay became a per-stage canvas slotting between the
## stage's UI and the hud (hud → editor → pause still render above it).
## Card titles/subs are raw EN keys, translated at draw (TS i18nT at render).
func draw_transition_veil(ci: CanvasItem) -> void:
	var tr: Variant = transition
	if tr == null:
		return
	var veil := Color(2.0 / 255.0, 3.0 / 255.0, 10.0 / 255.0)
	if tr["phase"] == "out":
		veil.a = minf(1.0, float(tr["t"]) / float(tr["dur"]))
		ci.draw_rect(Rect2(0, 0, vw, vh), veil)
	elif tr["phase"] == "card":
		ci.draw_rect(Rect2(0, 0, vw, vh), Color(veil, 1.0))
		if String(tr["title"]) != "":
			RendererScript.outlined_text(ci, i18n.tr_key(String(tr["title"])),
					vw / 2.0, vh / 2.0 - 16.0,
					{"size": 40.0, "fill": Color("#bfe6ff"), "weight": "700"})
			RendererScript.outlined_text(ci, i18n.tr_key(String(tr["sub"])),
					vw / 2.0, vh / 2.0 + 26.0,
					{"size": 15.0, "fill": RendererScript.css_color("rgba(200,225,255,0.75)")})
			RendererScript.outlined_text(ci, i18n.tr_key("click to continue"),
					vw / 2.0, vh / 2.0 + 64.0,
					{"size": 11.0, "fill": RendererScript.css_color("rgba(160,190,230,0.4)")})
	else:
		veil.a = maxf(0.0, 1.0 - float(tr["t"]) / float(tr["dur"]))
		ci.draw_rect(Rect2(0, 0, vw, vh), veil)


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


## ---- world story: reveal pump, mood, beats (TS game.ts:361-521) ---------------

## Runs every gameplay frame right after the stage sim: advances the world
## reveal timers, feeds the storyteller its signals, and announces anything
## the world genome decided (trait reveals, combos, turns, beats).
func pump_world_story(dt: float) -> void:
	var c: Variant = context
	if c.stage == "menu":
		return  # the title screen has no world to pump
	c.world["timers"][c.stage] = float(c.world["timers"].get(c.stage, 0.0)) + dt
	stage_time += dt

	# seed beat offer: a thriving kin bloodline (pop ≥ 15) offers its beat.
	# offer_beat dedupes on its own ledger, so this can only ever land once.
	# Skipped during the death window: DNA-paying beat cases in run_beat are
	# then safe by construction (a beat can only poll if offered while alive).
	if c.playtime >= dying_until and c.eco != null:
		for s in c.eco.living():
			if bool(s.get("kin", false)) and float(s["pop"]) >= 15.0:
				storyteller.offer_beat("herd_remembers")
				break

	# gaia_redemption tier 1 (catalog VI): the run's first death opens its
	# beat ~3.5s later — the fade proceeded untouched (death is one-way) and
	# the 12% tithe the death took IS the payment; the beat only narrates.
	if gaia_death_at >= 0.0 and c.playtime >= gaia_death_at + 3.5 \
			and c.playtime >= dying_until:
		gaia_death_at = -1.0  # offer exactly once
		storyteller.offer_beat("gaia_redemption")

	# gaia_redemption tier 2 — the herd tier: a kin bloodline crashed below
	# 10% of its peak (≥1 alive) while no chaos event runs → the Lone
	# Wanderer migrates in. offer_beat dedupes: once per run. The offer is
	# gated on the stage actually implementing the spawn — a latch burned in
	# tribe/civ/space would lose the wanderer for the whole run.
	var herd_crashed := false
	if c.eco != null:
		for s in c.eco.living():
			if bool(s.get("kin", false)) and float(s["pop"]) >= 1.0 \
					and float(s.get("peak", 0.0)) >= 10.0 \
					and float(s["pop"]) < float(s.get("peak", 0.0)) * 0.1:
				herd_crashed = true
				break
	if herd_crashed and c.playtime >= dying_until \
			and current != null and current.has_method("gaia_wanderer") \
			and (not current.has_method("has_active_chaos")
					or not current.has_active_chaos()):
		# TS `!(current as {hasActiveChaos?}).hasActiveChaos?.()` — the optional
		# call reads "no active chaos" when the stage implements the wanderer
		# without the chaos probe.
		storyteller.offer_beat("gaia_wanderer")

	# world_temperament: the ONE pacing personality, assigned every frame
	# from the world genome (worlds without the trait read 'none')
	storyteller.temperament = String(c.world.get("temperament", "none"))
	storyteller.update(dt, {
		"chaos": float(c.chaos),
		"karma": float(c.karma),
		"eco_health": 1.0 if c.eco == null \
				else minf(1.0, float(c.eco.living().size()) / 6.0),
		"dna_rate": dna_rate_per_min(),
		"deaths_in_stage": float(deaths_in_stage),
		"stage_time": stage_time,
	})

	var out: Dictionary = WorldGenomeScript.tick_world_reveals(c.world, {
		"stage": c.stage,
		"timer": float(c.world["timers"].get(c.stage, 0.0)),
		"chaos": float(c.chaos),
		"kills": float(c.world_stats["kills"]),
		"extinctions": float(c.world_stats["extinctions"]),
	})
	for id in out["revealed"]:
		announce_trait(String(id))
	for id in out["combos"]:
		announce_combo(String(id))
	if out.has("turn"):
		announce_turn(String(out["turn"]))

	var beat: Variant = storyteller.poll()
	if beat != null:
		run_beat(String(beat))


## Net DNA earned over the last 60 s (the window sum IS the per-minute rate).
func dna_rate_per_min() -> float:
	var cutoff: float = float(context.playtime) - 60.0
	while dna_window.size() > 0 and float(dna_window[0]["t"]) < cutoff:
		dna_window.pop_front()
	var sum := 0.0
	for e in dna_window:
		sum += float(e["amount"])
	return sum


## World cards ride the hud DIRECTLY (T8 minor-3 ruling): the context toast
## signal is 3-arg (text/kind/icon) and cannot carry ttl/title/card, so the
## TS EV.toast world shape (game.ts:437-446) ports as a direct hud.toast call
## with the card param — the hud draws kind 'world' as its reveal card.
## Call sites translate before the call (audit shape — the hud stores text
## verbatim); ttl 6 per TS.
func world_toast(sigil: String, name_key: String, body_key: String) -> void:
	var title_tx: String = i18n.tr_key(name_key)
	var body_tx: String = i18n.tr_key(body_key)
	var text: String = "%s — %s" % [title_tx, body_tx]
	hud["toast"].call(text, "world", sigil, 6.0, {"title": title_tx, "body": body_tx})


func announce_trait(id: String) -> void:
	for d in TraitsScript.TRAIT_DEFS:
		if d["id"] == id:
			world_toast(String(d["sigil"]), String(d["name"]), String(d["body"]))
			mark_codex(id)
			return


func announce_combo(id: String) -> void:
	for d in TraitsScript.COMBO_DEFS:
		if d["id"] == id:
			world_toast(String(d["sigil"]), String(d["title"]), String(d["body"]))
			mark_codex(id)
			return


func announce_turn(id: String) -> void:
	for d in TraitsScript.WORLD_TURN_DEFS:
		if d["id"] == id:
			var body: String = d["body"]
			if id == "epoch_apex":
				# catalog V(b): the epoch is named after the strongest
				# surviving species (by pop × size)
				var apex: Variant = _apex_species()
				if apex != null:
					body = "%s %s %s." % [body, i18n.tr_key("the age of"), apex["name"]]
			world_toast(String(d["sigil"]), String(d["title"]), body)
			mark_codex(id)
			return


## TS epoch_apex apex pick (game.ts:467-471): non-kin survivors, descending
## pop × genome.size. null with no eco / no non-kin species (body stays base).
func _apex_species() -> Variant:
	if context.eco == null:
		return null
	var pool: Array = []
	for s in context.eco.living():
		if not bool(s.get("kin", false)):
			pool.append(s)
	if pool.is_empty():
		return null
	pool.sort_custom(func(a, b) -> bool:
		return float(a["pop"]) * float(a["genome"]["size"]) \
				> float(b["pop"]) * float(b["genome"]["size"])
	)
	return pool[0]


## Bestiary-like codex of everything this world has shown (comma-joined ids
## in flags — flag values are string|number|boolean). Only trait ids ride
## the flag: the codex view resolves traits from it; combos and turns render
## from their own fired records. (TS ''.split(',') quirk yields [''] —
## unreachable in practice; the native split of '' is [], same visible result.)
func mark_codex(id: String) -> void:
	var found := false
	for d in TraitsScript.TRAIT_DEFS:
		if d["id"] == id:
			found = true
			break
	if not found:
		return
	var cur: Variant = context.flags.get("codex_world")
	var list: Array = []
	if cur is String:
		list = (cur as String).split(",")
	if not list.has(id):
		list.append(id)
		context.flags["codex_world"] = ",".join(list)


## Storyteller beats — a poll-queued narration cue. The switch stays
## deliberately minimal; the beat catalog appends its cases here (TS:493-521).
func run_beat(beat: String) -> void:
	match beat:
		"herd_remembers":
			# Seed beat: a spared bloodline walks closer — pay homage DNA.
			# Dormant until something adds kin species to the shared eco; the
			# offer check above lights up the moment that happens.
			var herd: Variant = null
			if context.eco != null:
				for s in context.eco.living():
					if bool(s.get("kin", false)) and float(s["pop"]) >= 10.0:
						herd = s
						break
			if herd == null:
				return
			context.add_dna(25.0, "the herd remembers")
			world_toast("🐾", "The herd remembers", "Those you spared walk closer today.")
		"gaia_redemption":
			# B1 tier 1 — the world swallows the fallen back. The death already
			# happened one-way and the existing 12% tithe IS the payment: this
			# beat never refunds and never re-sizes it.
			world_toast("🌍", "Gaia's Redemption",
					"The ocean folds the fallen back into itself — the tithe becomes part of the world again.")
		"gaia_wanderer":
			# B1 tier 2 — the Lone Wanderer: the current stage spawns one quiet
			# individual carrying a gene this run never owned (no gift announce;
			# the bestiary notes it once via discover()).
			if current != null and current.has_method("gaia_wanderer"):
				current.gaia_wanderer()


# ---- signal taps (TS game.ts:77-88 bus listeners) ------------------------------

func _on_dna_gained(amount: int, _reason: Variant, _x: Variant, _y: Variant) -> void:
	dna_window.append({"t": float(context.playtime), "amount": float(amount)})


func _on_context_event(ev_name: String, _from_stage: String) -> void:
	if ev_name != "playerDeath":
		return
	deaths_in_stage += 1
	# gaia tier 1: the run's first death opens the redemption beat later
	if gaia_death_at < 0.0:
		gaia_death_at = float(context.playtime)
	# 2s offer blackout across the death fade — beats must be offered
	# while the player is alive (no respawn event exists, so gating the
	# OFFER side keeps DNA-paying beats safe without a permanent latch)
	dying_until = float(context.playtime) + 2.0


## Flush the live stage's volatile state, THEN write the save (TS saveAll).
## Stages expose persist_state() as they land.
func save_all() -> bool:
	if current != null and current.has_method("persist_state"):
		current.persist_state()
	return context.save()


# ---- overlay controls (TS game.ts:228-251 — the API the hud buttons, the
# pause actions and Task 9's Escape routing call) ----------------------------

func open_pause() -> void:
	paused = true
	pause["open"].call()
	# TS also plays the 'click' audio cue (audio core: its own task).


func close_pause() -> void:
	paused = false


func toggle_mute() -> void:
	muted = not muted
	# TS audio.setMuted(this.muted) — audio core: its own task
	i18n.set_muted(muted)  # persist across sessions (TS setMuted)


## Convenience for stages: shake the main camera (TS camShakeFor).
func cam_shake_for(mag: float, dur: float) -> void:
	cam.shake(mag, dur)


## TS Game.setCursor (game.ts:150): 'default' | 'pointer' | 'crosshair'.
## UI layers upgrade to pointer over their hover rects; gameplay defaults to
## a crosshair. Native mapping via the OS cursor shape.
func set_cursor(c: String) -> void:
	if _cursor == c:
		return
	_cursor = c
	match c:
		"pointer":
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		"crosshair":
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
		_:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	# X11/Godot quirk (probed 2026-09-30): a cursor-shape CHANGE swallows the
	# next queued InputEventMouseMotion — the TS canvas cursor style has no
	# such side effect. Feed a sacrificial no-op motion (the wrapper's current
	# position, so the dispatch is a state no-op) that absorbs the swallow and
	# keeps the real input stream intact for bots and players alike.
	var dummy := InputEventMouseMotion.new()
	dummy.position = Vector2(input.mx, input.my)
	dummy.global_position = dummy.position
	Input.parse_input_event(dummy)
	Input.flush_buffered_events()


## The UI-layer hover upgrade (TS setCursor('pointer') over a hover rect).
## Marks the frame so the end-of-frame base resolution keeps the pointer —
## a steady hover issues NO further DisplayServer calls (see _hover_seen:
## every X11 cursor-shape CHANGE swallows the next queued motion event).
func hover_cursor() -> void:
	_hover_seen = true
	set_cursor("pointer")


# ---- game fx pool forwards (the dict Callables bind these) ------------------------

func _fx_clear() -> void:
	_fx_pool.clear()


func _fx_update(dt: float) -> void:
	_fx_pool.update(dt)


func _fx_burst(x: float, y: float, n: int, rng_v: Variant, opts: Variant = null) -> void:
	_fx_pool.burst(x, y, n, rng_v, {} if opts == null else opts)


func _fx_spawn(opts: Variant = null) -> void:
	_fx_pool.spawn({} if opts == null else opts)


func _fx_render(ci: Variant) -> void:
	_fx_pool.render(ci)
