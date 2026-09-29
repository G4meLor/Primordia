## Fixed-timestep game loop: deterministic 60 Hz updates, render callback once
## per process frame. Port of Spore src/core/loop.ts — the rAF frame became
## tick(frame_dt), called from the Game node's _process; headless tests and
## bots drive tick_manual exactly as TS tickManual (play-bot tests do that).
class_name GameLoop
extends RefCounted

var update_cb: Callable
var render_cb: Callable
## Optional per-frame cap guard — returns false to pause stepping (TS isActive).
var is_active_cb: Callable

var step := 1.0 / 60.0
var acc := 0.0


func _init(update_cb_v: Callable, render_cb_v: Callable, hz := 60.0,
		is_active_cb_v := Callable()) -> void:
	update_cb = update_cb_v
	render_cb = render_cb_v
	is_active_cb = is_active_cb_v
	step = 1.0 / hz


## One process frame: clamp big tab-switch deltas so the sim never explodes,
## run up to 8 fixed steps, then hand the interpolator to the render side.
func tick(frame_dt: float) -> void:
	if is_active_cb.is_valid() and not is_active_cb.call():
		return
	var fd := frame_dt
	if fd > 0.25:
		fd = 0.25
	acc = minf(acc + fd, 0.25)
	var steps := 0
	while acc >= step and steps < 8:
		update_cb.call(step)
		acc -= step
		steps += 1
	render_cb.call(acc / step)


## Advance exactly n fixed steps — used by headless tests / bots (TS tickManual:
## its default dt = this.step is unreachable from GDScript signatures, so a
## dt <= 0 sentinel reads the step).
func tick_manual(n: int, dt := 0.0) -> void:
	var d := dt if dt > 0.0 else step
	for i in n:
		update_cb.call(d)
