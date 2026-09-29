## Unified mouse/keyboard input. Port of Spore src/core/input.ts: the TS
## code-string API is kept verbatim ("KeyE", "Space") behind a physical-keycode
## map covering every key the game uses. Fed from two directions: the Game node
## forwards _unhandled_input events into handle_event (one-shot keyPressed
## tracking, click capture, wheel) and held-key state is polled live from the
## Input singleton each frame — UI-occluded keys still update it, which the TS
## window-listeners got for free. end_frame clears one-shots, called once per
## frame by the loop (the last line of Game's update, TS game.ts:322).
## NO debug* setters — headless bots drive Input.parse_input_event with real
## events (Global Constraint 8, spike-proven 2026-09-29).
## Divergence: Godot wheel is 1 event per notch, so wheel() accumulates ±100
## per notch where TS summed e.deltaY (sign-identical; editor zoom only reads
## the sign). TS 'KeyShift' is not a real browser KeyboardEvent.code (the dash-
## on-shift path was dead in TS) — native maps it to physical KEY_SHIFT so the
## frozen intent works; blur-clear of held keys is owned by the OS pipeline.
class_name GameInput
extends RefCounted

## TS code string -> Godot physical keycode. Enter serves the placeholder menu.
const CODES := {
	"KeyW": KEY_W, "KeyA": KEY_A, "KeyS": KEY_S, "KeyD": KEY_D,
	"ArrowUp": KEY_UP, "ArrowDown": KEY_DOWN,
	"ArrowLeft": KEY_LEFT, "ArrowRight": KEY_RIGHT,
	"Space": KEY_SPACE, "KeyShift": KEY_SHIFT,
	"KeyE": KEY_E, "Digit1": KEY_1, "Digit2": KEY_2, "Digit3": KEY_3,
	"KeyR": KEY_R, "KeyT": KEY_T, "Tab": KEY_TAB,
	"KeyM": KEY_M, "Escape": KEY_ESCAPE, "Enter": KEY_ENTER,
}

## Wheel deltaY per notch (see divergence note above).
const WHEEL_NOTCH := 100.0

## TS Set<string> keysPressed — TS code strings, keys only.
var keys_pressed := {}
## Screen coords (canvas-relative in TS; viewport coords here).
var mx := 0.0
var my := 0.0
## World coords (updated by the camera each frame, TS input.ts:82).
var wx := 0.0
var wy := 0.0
## Screen-space viewport size (set by the Game on resize).
var vw := 800.0
var vh := 600.0
var down := false
var clicked := false
var wheel_delta := 0.0

var _code_by_physical := {}


func _init() -> void:
	for code in CODES:
		_code_by_physical[CODES[code]] = code


## The Game node calls this from _unhandled_input — the real-pipeline feed.
func handle_event(e: InputEvent) -> void:
	if e is InputEventKey:
		if e.pressed and not e.echo:  # TS ignores e.repeat
			var code: String = _code_by_physical.get(e.physical_keycode, "")
			if code != "":
				keys_pressed[code] = true
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				wheel_delta -= WHEEL_NOTCH
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				wheel_delta += WHEEL_NOTCH
		else:
			# TS pointerdown fires for any button and pointerup clears down.
			mx = mb.position.x
			my = mb.position.y
			down = mb.pressed
			if mb.pressed:
				clicked = true
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		mx = mm.position.x
		my = mm.position.y


# --- polls (per frame) ------------------------------------------------------

## Call once at the end of each frame to clear one-shot state.
func end_frame() -> void:
	keys_pressed.clear()
	clicked = false
	wheel_delta = 0.0


# --- queries ----------------------------------------------------------------

## Held state — polled live from the Input singleton (not event-tracked).
func key(code: String) -> bool:
	var phys: int = CODES.get(code, 0)
	return phys != 0 and Input.is_physical_key_pressed(phys)


func key_pressed(code: String) -> bool:
	return keys_pressed.has(code)


func any_key_pressed() -> bool:
	return not keys_pressed.is_empty()


func is_down() -> bool:
	return down


func was_clicked() -> bool:
	return clicked


func take_click() -> bool:
	var c := clicked
	clicked = false
	return c


func wheel() -> float:
	return wheel_delta


func set_world(mxw: float, myw: float) -> void:
	wx = mxw
	wy = myw
