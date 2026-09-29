## Small 2D math toolbox — everything is plain data + pure functions so it is
## trivially testable and allocation-friendly. Port of Spore src/core/math.ts.
## The TS Vec2 helpers collapse into Vector2 (value semantics make vec/vecClone/
## vecAdd/vecSub/vecScale redundant — call sites use operators); vec_dist stays
## as the TS-named alias over Vector2.distance_to. format_num and the easings
## are formula-exact, including JS toFixed(1)'s ties-pick-larger rule (glibc
## %.1f would round-half-even the 12.25k case the other way).
class_name PMath
extends RefCounted

const TAU: float = PI * 2.0


static func clamp(v: float, lo: float, hi: float) -> float:
	return lo if v < lo else (hi if v > hi else v)


static func lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


## Frame-rate independent smoothing factor (for dt-based lerps).
static func damp(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)


static func smoothstep(t: float) -> float:
	# explicit float: unqualified clamp() binds the UNTYPED global utility in
	# this context (warning-as-error kills the inferred Variant under -s), and
	# global clamp is value-identical to the TS ternary below for finite input
	var x: float = clamp(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


static func ease_in_cubic(t: float) -> float:
	return t * t * t


static func ease_out_back(t: float) -> float:
	var c := 1.70158
	# explicit float — see smoothstep's clamp resolution note
	var x: float = clamp(t, 0.0, 1.0) - 1.0
	return 1.0 + x * x * ((c + 1.0) * x + c)


## Angle in radians of a vector (0 = +x).
static func angle_of(v: Vector2) -> float:
	return atan2(v.y, v.x)


## Shortest signed difference between two angles (-PI..PI).
static func angle_diff(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)  # JS % keeps the sign — GDScript fmod too
	if d > PI:
		d -= TAU
	if d < -PI:
		d += TAU
	return d


static func vec_dist(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


static func vec_dist2(a: Vector2, b: Vector2) -> float:
	return a.distance_squared_to(b)


static func vec_len(v: Vector2) -> float:
	return v.length()


static func vec_len2(v: Vector2) -> float:
	return v.length_squared()


static func vec_dot(a: Vector2, b: Vector2) -> float:
	return a.dot(b)


static func vec_normalize(v: Vector2) -> Vector2:
	var l := v.length()
	if l < 1e-9:
		return Vector2.ZERO
	return v / l


## Wrap angle into -PI..PI.
static func wrap_angle(a: float) -> float:
	var x := fmod(a, TAU)
	if x > PI:
		x -= TAU
	if x < -PI:
		x += TAU
	return x


## Random point on a circle edge around `center` (angle picked by the caller's
## Rng stream — this helper itself is pure).
static func on_circle(center: Vector2, r: float, angle: float) -> Vector2:
	return center + Vector2(cos(angle), sin(angle)) * r


static func shortest_vec_on_circle(center: Vector2, r: float, angle: float) -> Vector2:
	return center + Vector2(cos(angle), sin(angle)) * r


## TS toFixed(1): pick n minimizing |n/10 − x|, ties pick the larger n
## (ECMA-262 rule), then one decimal digit. The comparison MUST divide the
## candidates back (n/10), not round the product: _round_js(x*10) double-
## rounds — fl(12.35) sits BELOW the .35 tie (−3.55e-16) but fl(12.35)*10
## lands exactly on 123.5 and rounds up to 124, printing "12.4k" over TS's
## "12.3k" (re-review finding, fix round 3). Ties compare with <= so an exact
## float tie (e.g. 12.25) takes the larger n; false ties cannot occur in this
## domain — inputs are integer quotients, whose exact distance to a
## one-decimal tie is ≥ 5e-11 while float compare noise is ~1e-15. format_num
## only reaches this for n ≥ 1e4, so n > 0 and the GDScript % (rounds toward
## -inf, unlike JS) never sees a negative.
static func _to_fixed1(x: float) -> String:
	var n := floori(x * 10.0)
	if float(n + 1) / 10.0 - x <= x - float(n) / 10.0:
		n += 1
	return "%d.%d" % [n / 10, n % 10]


## 1e9→B, 1e6→M, 1e4→k, else Math.round — TS-exact thresholds and format.
static func format_num(n: float) -> String:
	if n >= 1e9:
		return _to_fixed1(n / 1e9) + "B"
	if n >= 1e6:
		return _to_fixed1(n / 1e6) + "M"
	if n >= 1e4:
		return _to_fixed1(n / 1e3) + "k"
	return str(_round_js(n))


## JS Math.round: ties toward +infinity (GDScript roundi is ties-away-from-zero
## on negatives — context.gd carries the same helper).
static func _round_js(x: float) -> int:
	return floori(x + 0.5)
