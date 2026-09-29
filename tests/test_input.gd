# Input wrapper tests. One-shots (keyPressed/click/wheel) are fed through
# handle_event directly — the Game node's _unheld_input forwarding is exercised
# end-to-end by tests/scenes/test_boot.gd under xvfb. Held-key state polls the
# Input singleton, so those tests inject via Input.parse_input_event +
# flush_buffered_events (proven to update is_physical_key_pressed in -s mode).
extends "res://tests/test_base.gd"

const InputScript := preload("res://src/core/input.gd")

var ev_counter := 0


func _key_ev(physical: int, pressed: bool, echo := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = pressed
	ev.echo = echo
	return ev


func _mouse_ev(button: int, pressed: bool, pos := Vector2(0.0, 0.0)) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	return ev


func _flush_held(physical: int, pressed: bool) -> void:
	Input.parse_input_event(_key_ev(physical, pressed))
	Input.flush_buffered_events()


func test_key_pressed_one_shot_via_event_path() -> void:
	var inp: Variant = InputScript.new()
	inp.handle_event(_key_ev(KEY_E, true))
	eq(inp.key_pressed("KeyE"), true, "handle_event press tracks keyPressed")
	eq(inp.any_key_pressed(), true, "any_key_pressed")
	inp.handle_event(_key_ev(KEY_E, true, true))
	# end_frame clears one-shots, NOT held state
	inp.end_frame()
	eq(inp.key_pressed("KeyE"), false, "end_frame clears one-shots")
	eq(inp.any_key_pressed(), false, "any_key_pressed after end_frame")


func test_echo_events_ignored() -> void:
	var inp: Variant = InputScript.new()
	inp.handle_event(_key_ev(KEY_E, true, true))
	eq(inp.key_pressed("KeyE"), false, "echo (key repeat) never fires one-shot")


func test_unmapped_key_ignored() -> void:
	var inp: Variant = InputScript.new()
	inp.handle_event(_key_ev(KEY_Q, true))
	eq(inp.key_pressed("KeyQ"), false, "unmapped code not tracked")
	eq(inp.any_key_pressed(), false, "no any_key_pressed for unmapped key")


func test_held_key_polls_input_singleton() -> void:
	var inp: Variant = InputScript.new()
	_flush_held(KEY_E, true)
	eq(inp.key("KeyE"), true, "key('KeyE') reads is_physical_key_pressed")
	# end_frame must not clear held state (TS keys set persists until keyup)
	inp.end_frame()
	eq(inp.key("KeyE"), true, "held state survives end_frame")
	_flush_held(KEY_E, false)
	eq(inp.key("KeyE"), false, "release clears held state")


func test_key_unmapped_code_is_false() -> void:
	var inp: Variant = InputScript.new()
	eq(inp.key("KeyQ"), false, "unmapped code reads false")
	eq(inp.key("Nope"), false, "unknown string reads false")


func test_mouse_click_and_position() -> void:
	var inp: Variant = InputScript.new()
	inp.handle_event(_mouse_ev(MOUSE_BUTTON_LEFT, true, Vector2(137.0, 42.0)))
	eq(inp.is_down(), true, "pointerdown sets down")
	eq(inp.was_clicked(), true, "pointerdown sets clicked")
	eq(inp.mx, 137.0, "mx from event position")
	eq(inp.my, 42.0, "my from event position")
	# takeClick consumes once
	eq(inp.take_click(), true, "take_click first")
	eq(inp.take_click(), false, "take_click consumed")
	# end_frame clears clicked but not down
	inp.handle_event(_mouse_ev(MOUSE_BUTTON_LEFT, true, Vector2(137.0, 42.0)))
	inp.end_frame()
	eq(inp.was_clicked(), false, "end_frame clears clicked")
	eq(inp.is_down(), true, "end_frame keeps down")
	inp.handle_event(_mouse_ev(MOUSE_BUTTON_LEFT, false, Vector2(137.0, 42.0)))
	eq(inp.is_down(), false, "release clears down")


func test_any_mouse_button_clicks() -> void:
	# TS pointerdown fires for ANY button (right included)
	var inp: Variant = InputScript.new()
	inp.handle_event(_mouse_ev(MOUSE_BUTTON_RIGHT, true, Vector2(1.0, 2.0)))
	eq(inp.was_clicked(), true, "right button also clicks")


func test_wheel_accumulates_and_resets() -> void:
	var inp: Variant = InputScript.new()
	inp.handle_event(_mouse_ev(MOUSE_BUTTON_WHEEL_DOWN, true))
	eq(inp.wheel(), 100.0, "wheel down notch = +100 (TS deltaY; divergence noted)")
	inp.handle_event(_mouse_ev(MOUSE_BUTTON_WHEEL_DOWN, true))
	eq(inp.wheel(), 200.0, "wheel accumulates")
	inp.handle_event(_mouse_ev(MOUSE_BUTTON_WHEEL_UP, true))
	eq(inp.wheel(), 100.0, "wheel up subtracts")
	inp.end_frame()
	eq(inp.wheel(), 0.0, "end_frame clears wheel")


func test_motion_moves_mouse() -> void:
	var inp: Variant = InputScript.new()
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(50.0, 60.0)
	inp.handle_event(mm)
	eq(inp.mx, 50.0, "mx from motion")
	eq(inp.my, 60.0, "my from motion")


func test_world_coords_and_defaults() -> void:
	var inp: Variant = InputScript.new()
	eq(inp.vw, 800.0, "vw default (TS)")
	eq(inp.vh, 600.0, "vh default (TS)")
	eq(inp.wx, 0.0, "wx default")
	inp.set_world(10.0, 20.0)
	eq(inp.wx, 10.0, "set_world x")
	eq(inp.wy, 20.0, "set_world y")


func test_code_map_round_trips_every_key() -> void:
	# every TS code string in the map must reverse-map from its physical key
	var inp: Variant = InputScript.new()
	var codes: Dictionary = InputScript.CODES
	ok(codes.size() >= 15, "map covers the keys the game uses")
	eq(codes.get("Space"), KEY_SPACE, "Space")
	eq(codes.get("KeyShift"), KEY_SHIFT, "KeyShift")
	eq(codes.get("Escape"), KEY_ESCAPE, "Escape")
	eq(codes.get("Enter"), KEY_ENTER, "Enter (placeholder menu)")
	eq(codes.get("Digit1"), KEY_1, "Digit1")
	eq(codes.get("Digit2"), KEY_2, "Digit2")
	eq(codes.get("KeyM"), KEY_M, "KeyM")
	eq(codes.get("KeyE"), KEY_E, "KeyE")
	for code in codes:
		var phys: int = codes[code]
		inp.handle_event(_key_ev(phys, true))
		eq(inp.key_pressed(code), true, "press %s → one-shot" % code)
	# release everything so the global Input state stays clean for later tests
	for code in codes:
		inp.handle_event(_key_ev(codes[code], false))
	inp.end_frame()
	eq(inp.any_key_pressed(), false, "all released")
