# Play-bot arc scene test — Task 6, the load-bearing M2 parity gate. Port of
# Spore tests/bot.test.ts (arc scope per pre-flight ruling: the editor
# buy/sell test belongs to Task 8, the save→load round-trip to Task 9).
# Boots the real Game per seed, starts a new life via the menu stage's
# start_new_game DIRECTLY (TS-bot parity, bot.test.ts:62 — the menu UI click
# flow is Task 9's scene test), walks the transition, then simulates two
# messy minutes of human-like play — move/dash/burst/editor taps — driven
# EXCLUSIVELY through Input.parse_input_event (Global Constraint 8; the bot
# parity law). Any NaN drift, invariant violation, crash or nondeterminism
# fails the build.
#
# Phases: input-delivery smoke (PROOF that parse+flush lands in
# _unhandled_input: KeyE reaches the stage's editor branch, mouse reaches
# the wrapper) → per seed in [0xC0FFEE, 0x51071, 0xABCDEF]: arc run 1 →
# fresh Game → arc run 2 → quantized fingerprint equality (determinism) →
# BOT_ARC_OK line → next seed. All pass → BOT_ARC_ALL_OK, exit 0; else
# BOT_ARC_FAIL on stderr, exit 1.
#
# Run (xvfb, rendering on — the real pipeline needs a live SceneTree):
#   tools/test_bot.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_bot_arc.tscn
# xvfb REQUIRED: Input.flush_buffered_events dispatches into the SceneTree
# only with a real display server — headless silently drops the delivery
# (the smoke phase fails there, by design).
extends Node

const MainScript := preload("res://src/main.gd")  # kept for the boot-path doc; the menu is the REAL MenuStage since Task 9
const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")

const SEEDS := [0xC0FFEE, 0x51071, 0xABCDEF]
const DT := 1.0 / 60.0
const TRANSITION_POLL := 300  # ≤ 300 steps until stage == "cell" (brief AC)
const CARD_STEPS := 180       # TS: card phase ~2.2s → 180-step slot (bot.test.ts:72)
const MESSY_FRAMES := 60 * 120  # 120 simulated seconds (bot.test.ts:88)
const TIMEOUT_FRAMES := 7200  # real-frame guard for the WHOLE run

var _phase := "smoke_build"
var _seed_i := 0
var _pass_i := 0
var _fps: Dictionary = {}  # seed hex → first-arc fingerprint (determinism)
var _pro_fps: Array = []   # per-pass post-prologue fingerprint (divergence triage)
var _frames := 0
var _done := false
var _game: Variant = null
var _driver: Variant = null


func _ready() -> void:
	_driver = BotDriverScript.new()


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	if _done:
		return
	match _phase:
		"smoke_build":
			_game = _build_game(SEEDS[0])
			_phase = "smoke_run"
		"smoke_run":
			_smoke_run()
		"arc_build":
			_driver = BotDriverScript.new()  # fresh LCG (seed 12345) per run
			_pro_fps = []                    # per-seed triage data
			_game = _build_game(SEEDS[_seed_i])
			_phase = "arc_prologue"
		"arc_prologue":
			if not _prologue(_game):
				return
			if not _driver.assert_sane(_game).is_empty():
				_fail("post-card assert_sane: %s" % str(_driver.sane_violations))
				return
			_pro_fps.append(_driver.fingerprint(_game))
			_phase = "arc_messy"
		"arc_messy":
			_driver.step_loop(_game, MESSY_FRAMES, DT)
			_phase = "arc_post"
		"arc_post":
			_arc_post()
		"done":
			pass


# ---- phases -------------------------------------------------------------------

## The input-delivery PROOF (team-lead binding: prove pipeline delivery in a
## smoke test before trusting the arc). Fresh arrival: php = pmaxHp > 0, so
## the stage's KeyE branch consumes the press — sim.tut.editorOpened is the
## seam that only increments there (cell_stage.gd:298).
func _smoke_run() -> void:
	if not _prologue(_game):
		return
	if not _driver.assert_sane(_game).is_empty():
		_fail("post-card assert_sane: %s" % str(_driver.sane_violations))
		return
	var sim: Variant = _game.current.sim
	if int(sim.tut["editorOpened"]) != 0:
		_fail("smoke: editorOpened should start 0, got %s" % str(sim.tut["editorOpened"]))
		return
	_driver.tap_key(KEY_E)
	if not _game.input.key_pressed("KeyE"):
		_fail("smoke: KeyE press did not reach the input wrapper via _unhandled_input")
		return
	_game.step_for_testing(1, DT)
	if int(sim.tut["editorOpened"]) != 1:
		_fail("smoke: the stage's editor branch did not consume KeyE (editorOpened=%s)"
				% str(sim.tut["editorOpened"]))
		return
	_game.step_for_testing(1, DT)
	if int(sim.tut["editorOpened"]) != 1:
		_fail("smoke: KeyE one-shot leaked across frames (end_frame hygiene)")
		return
	# mouse: wrapper receives the real motion/button position + down state
	var aim: Vector2 = _driver.world_to_screen(_game, sim.px + 120.0, sim.py - 80.0)
	_driver.move_mouse(aim)
	if absf(_game.input.mx - aim.x) > 0.01 or absf(_game.input.my - aim.y) > 0.01:
		_fail("smoke: mouse motion not delivered (mx/my %s/%s want %s/%s)" % [
				str(_game.input.mx), str(_game.input.my), str(aim.x), str(aim.y)])
		return
	_driver.mouse_down(aim)
	if not _game.input.is_down() or not _game.input.was_clicked():
		_fail("smoke: mouse down not delivered (down=%s clicked=%s)" % [
				str(_game.input.is_down()), str(_game.input.was_clicked())])
		return
	_driver.mouse_up()
	if _game.input.is_down():
		_fail("smoke: mouse up not delivered")
		return
	print("BOT_SMOKE_OK pipeline=parse_input_event editorOpened=1")
	_drop_game()
	_phase = "arc_build"


## Boot → menu → new game → transition → card-slot (bot.test.ts:55-73).
func _prologue(game: Variant) -> bool:
	game.step_for_testing(5)
	if game.context.stage != "menu":
		_fail("prologue: expected menu after 5 steps, got %s" % str(game.context.stage))
		return false
	# start_new_game DIRECTLY — TS-true (bot.test.ts:61-62 comment: menu logic
	# smoke-tested separately; the UI click flow is Task 9's scene test). The
	# seed rides along (menu.ts startNewGame's own comment: a bare new
	# GameContext() rolls the meta randi() and the probe's seed would be
	# clobbered) — the real menu replaces the context world, so the pinned
	# world must be re-pinned through it for the native determinism gate.
	var menu: Variant = game.current
	menu.start_new_game(0, "normal", game.context.seed)
	var steps := 0
	while game.context.stage != "cell" and steps < TRANSITION_POLL:
		game.step_for_testing(1, DT)
		steps += 1
	if game.context.stage != "cell":
		_fail("prologue: cell stage not reached within %d steps" % TRANSITION_POLL)
		return false
	# the card-slot: the REAL menu fires the 'CELL STAGE' title card
	# (out 0.55 → card 2.2 → in 0.6 = 2.8s < CARD_STEPS 180), so this walks
	# the in-fade plus the first live seconds of the run
	game.step_for_testing(CARD_STEPS, DT)
	return true


func _arc_post() -> void:
	var sim: Variant = _game.current.sim
	if sim.ents.is_empty():
		_fail("arc: world did not respond to play — ents empty (bot.test.ts:110)")
		return
	if not _driver.sane_violations.is_empty():
		_fail("arc assert_sane violations: %s" % str(_driver.sane_violations))
		return
	if not _driver.delivery_ok:
		_fail("arc: an injected input event failed to reach the wrapper")
		return
	var fp: Dictionary = _driver.fingerprint(_game)
	var hex := String.num_int64(SEEDS[_seed_i], 16)
	if _pass_i == 0:
		_fps[hex] = {"fp": fp, "trace": _driver.trace}
		_pass_i = 1
		_drop_game()
		_phase = "arc_build"  # same seed again, fresh Game (determinism run)
		return
	# second pass: quantized exacts must match field-for-field
	for k in fp:
		if _fps[hex]["fp"].get(k) != fp[k]:
			var p0: String = str(_pro_fps[0]) if _pro_fps.size() > 0 else "?"
			var p1: String = str(_pro_fps[1]) if _pro_fps.size() > 1 else "?"
			_fail("determinism seed=%s: fingerprint %s differs (run1=%s run2=%s) prologue=%s vs %s first-divergence=%s" % [
					hex, k, str(_fps[hex]["fp"].get(k)), str(fp[k]),
					p0, p1,
					_first_trace_divergence(hex)])
			return
	print("BOT_ARC_OK seed=%s ents=%d dna=%d fp=%s" % [
			hex, fp["ents"], fp["dna"], str(fp)])
	_pass_i = 0
	_seed_i += 1
	_drop_game()
	if _seed_i >= SEEDS.size():
		_phase = "done"
		print("BOT_ARC_ALL_OK")
		_done = true
		get_tree().quit(0)
		return
	_phase = "arc_build"


# ---- helpers ------------------------------------------------------------------

## First divergent sweep between the two runs of a seed (determinism diagnosis).
## String-compares the sweep rows — Variant-op safe (a raw float/int compare
## through Variant evaluators has bitten this diagnosis once already).
func _first_trace_divergence(hex: String) -> String:
	var t1: Array = _fps[hex]["trace"]
	var t2: Array = _driver.trace
	for i in range(mini(t1.size(), t2.size())):
		var r1s: String = str(t1[i])
		var r2s: String = str(t2[i])
		if r1s != r2s:
			return "sweep[%d] run1=%s run2=%s" % [i, r1s, r2s]
	return "none (divergence outside sweep points)"

func _build_game(seed_v: int) -> Variant:
	var ctx: Variant = ContextScript.new(seed_v)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	# Manual stepping ONLY — the real _process would add loop.tick(real-dt)
	# steps at heavy-frame boundaries (wall-clock clamped → nondeterministic;
	# this bit us: 6 phantom steps after the prologue frame moved the player).
	# set_process must come AFTER tree entry (pre-tree flags don't survive
	# registration), and the loop's is_active_cb kills tick() even if a future
	# refactor re-enables processing — tick_manual ignores it, so the bot's
	# step_for_testing path is untouched.
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	# the REAL MenuStage since Task 9 — start_new_game keeps the TS method
	# name the bot calls (TS-bot parity, bot.test.ts:62); its card-slot below
	# now walks the full out → card('CELL STAGE') → in shape
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.start()
	return game


## Free the finished Game before the next one — the Input singleton is shared,
## so a live second Game would double-consume every injected event.
func _drop_game() -> void:
	if _game != null:
		_game.free()
		_game = null


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("BOT_ARC_FAIL: " + msg)
	get_tree().quit(1)
