## Camera rig wrapping a Camera2D child node. Port of Spore src/gfx/renderer.ts
## Camera class (follow/snap/shake/toWorld/view bounds) — the canvas save/
## translate/scale draw helpers became the Camera2D transform itself, so the
## rig only feeds it position/zoom/offset. toWorld keeps the TS explicit
## inverse formula (shake ignored, as in TS — mouse aiming must not jitter).
## Divergence: TS shake jitter drew from Math.random; native draws from a
## private seeded Rng stream (Global Constraint 4 — all randomness in seeded
## streams; visual-only). TS applies shake in screen pixels (translate before
## scale); Camera2D offset is world-space, so the sync divides by zoom.
class_name Cam
extends Node

const RngScript := preload("res://src/core/rng.gd")
const SHAKE_SEED := 0x5EED

var x := 0.0
var y := 0.0
var zoom := 1.0
var _shake_t := 0.0
var _shake_mag := 0.0
## Screen-pixel jitter, TS shx/shy (public — the renderer reads them).
var shake_x := 0.0
var shake_y := 0.0
## World bounds of the current viewport (updated by update_view_bounds).
var view_l := 0.0
var view_t := 0.0
var view_r := 0.0
var view_b := 0.0

## The Camera2D child; null until _ready (math is testable headless without it).
var cam2d: Camera2D = null

var _rng: Variant = null


func _ready() -> void:
	cam2d = Camera2D.new()
	cam2d.name = "Cam2D"
	add_child(cam2d)
	cam2d.make_current()
	_apply()


func _apply() -> void:
	if cam2d == null:
		return
	cam2d.position = Vector2(x, y)
	cam2d.zoom = Vector2(zoom, zoom)
	cam2d.offset = Vector2(shake_x / zoom, shake_y / zoom)


func follow(target_x: float, target_y: float, dt: float, rate := 6.0) -> void:
	var k := 1.0 - exp(-rate * dt)
	x += (target_x - x) * k
	y += (target_y - y) * k
	_apply()


## Teleport without smoothing.
func snap(sx: float, sy: float) -> void:
	x = sx
	y = sy
	_apply()


func shake(mag: float, dur := 0.4) -> void:
	if mag >= _shake_mag or _shake_t <= 0.0:
		_shake_mag = mag
		_shake_t = dur


## Screen → world: inverse of the camera transform, TS formula exact.
func to_world(sx: float, sy: float, vw: float, vh: float) -> Vector2:
	return Vector2((sx - vw / 2.0) / zoom + x, (sy - vh / 2.0) / zoom + y)


## Per-frame shake decay (TS Camera.update) + Camera2D sync.
func update(dt: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= dt
		var m := _shake_mag * maxf(0.0, _shake_t * 2.5)
		if _rng == null:
			_rng = RngScript.new_from(SHAKE_SEED)
		shake_x = (_rng.next() * 2.0 - 1.0) * m
		shake_y = (_rng.next() * 2.0 - 1.0) * m
		if _shake_t <= 0.0:
			shake_x = 0.0
			shake_y = 0.0
			_shake_mag = 0.0
	else:
		shake_x = 0.0
		shake_y = 0.0
	_apply()


## World bounds of the viewport for render culling (TS begin()'s tail).
func update_view_bounds(vw: float, vh: float) -> void:
	var hw := vw / 2.0 / zoom
	var hh := vh / 2.0 / zoom
	view_l = x - hw
	view_t = y - hh
	view_r = x + hw
	view_b = y + hh
