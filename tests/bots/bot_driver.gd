## Play-bot driver — Task 6. Port of Spore tests/bot.test.ts:28-107: the LCG,
## the messy-play step loop, the input helpers and the assertSane invariant
## sweep. Global Constraint 8 (bot parity law): every gate goes through the
## REAL input pipeline — InputEventKey/MouseButton/Motion fed via
## Input.parse_input_event, flushed synchronously with
## Input.flush_buffered_events (delivery proven by the arc scene's smoke
## phase) — no debug setters exist (T1 ruling) and no sim method is ever
## called directly.
##
## World→screen mapping: the bot targets WORLD points; the pipeline consumes
## SCREEN positions. The cell stage pins zoom 1.0 and maps screen→world each
## update via cam.to_world (cell_stage.gd:308) — inverting cam.gd:73
##   world = (screen − vw/2, vh/2)/zoom + cam.x/y
## gives  screen = (world − cam.x/y)·zoom + (vw/2, vh/2)
## computed from the same cam state the stage last stepped with, so the NEXT
## update's set_world lands the aim exactly on the target (TS pinned wx/wy
## via input.setWorld every frame — bot.test.ts:96 — the native bot gets the
## same effect through real per-frame motion events, one update stale like a
## real mouse riding a following camera).
extends RefCounted

## TS bot LCG (bot.test.ts:81): seed = (seed*1103515245 + 12345) & 0x7fffffff.
var lcg_seed := 12345
## Every assert_sane sweep appends here; the scene test asserts it empty.
var sane_violations: PackedStringArray = []
## Per-sweep (every 600 frames) quantized state trace — determinism failures
## print the first divergent sweep instead of just the end fingerprint.
var trace: Array = []
## Real-pipeline delivery proof: flipped false if any injected event failed to
## reach the GameInput wrapper (mx/my/down/keys_pressed) at injection time.
var delivery_ok := true
## Last injected screen position (mouse_up carries a real pointer position).
var last_screen := Vector2.ZERO


## TS rand() (bot.test.ts:82-85). GDScript int64 keeps the multiplication
## exact (max ≈ 2.37e18 < 2^63) — note: JS's float64 multiply loses low bits
## above 2^53, so the low-bit sequence may differ from the TS run; the arc's
## asserts are invariants, not exact walks, and determinism is native-vs-native.
func rand() -> float:
	lcg_seed = (lcg_seed * 1103515245 + 12345) & 0x7fffffff
	return float(lcg_seed) / float(0x7fffffff)


# ---- input helpers (the whole bot vocabulary) --------------------------------

func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()  # synchronous dispatch → Game._unhandled_input


func press_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode  # wrapper maps physical keycodes (input.gd:63)
	ev.pressed = true
	_send(ev)


func release_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = false
	_send(ev)


## A clean tap: press then release. The wrapper records the press one-shot
## (release events never clear keys_pressed — input.gd:61-65), the singleton
## held-state ends clean, so the next arc/run starts from a neutral Input.
func tap_key(keycode: int) -> void:
	press_key(keycode)
	release_key(keycode)


func move_mouse(screen_pos: Vector2) -> void:
	last_screen = screen_pos
	var ev := InputEventMouseMotion.new()
	ev.position = screen_pos
	ev.global_position = screen_pos
	_send(ev)


## TS debugDown: position + down + clicked (bot.test.ts:92). A real pointer
## produces a motion into the press — both events, in that order.
func mouse_down(screen_pos: Vector2) -> void:
	move_mouse(screen_pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = screen_pos
	ev.global_position = screen_pos
	_send(ev)


func mouse_up() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = last_screen
	ev.global_position = last_screen
	_send(ev)


## Inverse of Cam.to_world (cam.gd:73-74) — the stage's own mapping state.
func world_to_screen(game: Variant, wxx: float, wyy: float) -> Vector2:
	var cam: Variant = game.cam
	return Vector2(
			(wxx - float(cam.x)) * float(cam.zoom) + game.vw / 2.0,
			(wyy - float(cam.y)) * float(cam.zoom) + game.vh / 2.0)


# ---- invariant sweep (exact port of bot.test.ts:28-45) -----------------------

## Returns the list of violations (empty = sane); also accumulates into
## sane_violations. dna finite ≥ 0; chaos ∈ [0,1]; karma ∈ [−1,1]; in cell:
## player pos finite, php ≤ pmaxHp + 0.001, ents < 300.
func assert_sane(game: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	var c: Variant = game.context
	if not is_finite(float(c.dna)):
		out.append("dna not finite")
	elif float(c.dna) < 0.0:
		out.append("dna < 0: %s" % str(c.dna))
	# NaN-hardened: TS's toBeGreaterThanOrEqual/toBeLessThanOrEqual FAIL on
	# NaN, while GDScript's `x < 0 or x > 1` silently passes it (every NaN
	# comparison is false) — the range gate must reject non-finite like TS.
	if not is_finite(float(c.chaos)) or float(c.chaos) < 0.0 or float(c.chaos) > 1.0:
		out.append("chaos out of [0,1]: %s" % str(c.chaos))
	if not is_finite(float(c.karma)) or float(c.karma) < -1.0 or float(c.karma) > 1.0:
		out.append("karma out of [-1,1]: %s" % str(c.karma))
	if c.stage == "cell" and game.current != null and game.current.sim != null:
		var sim: Variant = game.current.sim
		if not is_finite(sim.px):
			out.append("px not finite")
		if not is_finite(sim.py):
			out.append("py not finite")
		if float(sim.pmaxHp) > 0.0 and float(sim.php) > float(sim.pmaxHp) + 0.001:
			out.append("php > pmaxHp + 0.001: %s > %s" % [str(sim.php), str(sim.pmaxHp)])
		if sim.ents.size() >= 300:
			out.append("ents >= 300: %d" % sim.ents.size())
	sane_violations += out
	return out


## Quantized world-state fingerprint (determinism gate): ents count +
## floor(pos·100) + floor(dna·100) + floor(chaos·1000) — exact equality on
## each quantized field across two runs of the same seed.
func fingerprint(game: Variant) -> Dictionary:
	var sim: Variant = game.current.sim
	var c: Variant = game.context
	return {
		"ents": sim.ents.size(),
		"px": floori(float(sim.px) * 100.0),
		"py": floori(float(sim.py) * 100.0),
		"dna": floori(float(c.dna) * 100.0),
		"chaos": floori(float(c.chaos) * 1000.0),
	}


# ---- the messy-play loop (bot.test.ts:88-107) --------------------------------

## `frames` steps of hold-move toward LCG-random points, random ability taps,
## editor open/close taps, assert_sane every 600 frames. TS frame order kept:
## retarget+down (f%90==0) → up (f%90==45) → aim pin (every frame, the TS
## setWorld) → Space (f%240==120) → Digit1 (f%300==200) → Digit2
## (f%360==300) → KeyE (f==1200, f==1230) → periodic render smoke (f%600==0)
## → step → sweep.
func step_loop(game: Variant, frames: int, dt: float) -> void:
	var sim: Variant = game.current.sim
	var target_x: float = sim.px + 100.0
	var target_y: float = sim.py + 100.0
	for f in range(frames):
		if f % 90 == 0:
			target_x = sim.px + (rand() - 0.5) * 900.0
			target_y = sim.py + (rand() - 0.5) * 900.0
			mouse_down(world_to_screen(game, target_x, target_y))
			delivery_ok = delivery_ok and game.input.is_down()
		elif f % 90 == 45:
			mouse_up()
			delivery_ok = delivery_ok and not game.input.is_down()
		else:
			# TS "keep world coords aligned with where the camera looks"
			# (bot.test.ts:95) — a real per-frame motion instead of setWorld.
			move_mouse(world_to_screen(game, target_x, target_y))
			delivery_ok = delivery_ok \
					and absf(game.input.mx - last_screen.x) <= 0.01 \
					and absf(game.input.my - last_screen.y) <= 0.01
		if f % 240 == 120:
			tap_key(KEY_SPACE)
			delivery_ok = delivery_ok and game.input.key_pressed("Space")
		if f % 300 == 200:
			tap_key(KEY_1)
			delivery_ok = delivery_ok and game.input.key_pressed("Digit1")
		if f % 360 == 300:
			tap_key(KEY_2)
			delivery_ok = delivery_ok and game.input.key_pressed("Digit2")
		# open + close editor every ~20 s (bot.test.ts:101-102) — the editor is
		# a Task 8 stub: assert only that the press rides the real pipeline
		# into the wrapper and nothing crashes.
		if f == 1200 or f == 1230:
			tap_key(KEY_E)
			delivery_ok = delivery_ok and game.input.key_pressed("KeyE")
		if f % 600 == 0:
			game._do_render(0.0)  # periodic render smoke (bot.test.ts:103)

		game.step_for_testing(1, dt)
		if f % 600 == 0:
			assert_sane(game)
			var held: Array = []
			for code in game.input.CODES:
				if game.input.key(code):
					held.append(code)
			held.sort()
			trace.append({"f": f, "fp": fingerprint(game), "held": held,
					"down": game.input.is_down(),
					"mx": floori(game.input.mx), "my": floori(game.input.my)})
