## Analytic creature rig — port of Spore src/gfx/creature.ts (frozen) rig math:
## solveIK (creature.ts:33-44), derived metrics (54-61), spine (94-108),
## tail (137-150), legs (153-171). Pure static (genome, pose, t) → numbers;
## no drawing, no scene API — the prototype-first doctrine: this math is
## headless-green (tests/test_creature_rig.gd, TS-pinned) BEFORE
## creature_painter.gd (M3 task 6) draws any pixel.
##
## Pose/genome shapes: pose is the TS CreaturePose as a Dictionary (TS-verbatim
## keys — the rig reads only scale/speed/gaitPhase/attack/airborne); genome
## reads size/legs/tail. Coordinates are pose-local: TS computes them inside
## translate(pose.x, pose.y)·scale(facing, 1), so x/y/facing (and the dead-mood
## rotate) apply at draw time — the rig math is facing-blind.
##
## Storage discipline (M3 constraint 2 — IK math pure-float f64): every
## coordinate lives in f64 (Dictionary/Array Variants). Vector2 appears ONLY at
## solve_ik's brief-pinned return (float32 storage → its tests pin at 1e-5);
## the f64 core _ik_f64 feeds leg_draws and pins at 1e-9.
##
## Divergences (task 1):
##  - leg_draws takes (genome, pose, t): the brief's leg_draws(genome, pose) is
##    unsatisfiable TS-exact — hipY hangs off the spine, whose swim sway
##    sin(t·2.2 + u·2.4) needs t (the TS pose carries no t; t lives in opts).
##    Mirrors tail_points(genome, pose, t).
##  - TS inlines these blocks in drawCreature with spine in scope; here
##    tail_points/leg_draws re-derive the spine slice they need via spine_points
##    (pure → bit-identical to the painter's copy), and the shared metric locals
##    (TS:54-61) live in _metrics.
extends RefCounted

const SEG: int = 6


## TS:33-44 solveIK, op-for-op. Returns [kx, ky] as PackedFloat64Array (true
## f64 storage). Math.hypot → sqrt(dx·dx + dy·dy): glibc hypot is correctly
## rounded, the naive form differs ≤ ~1.5 ulp at these magnitudes (~1e-14),
## far under the 1e-9 test eps. The min-reach floor deliberately does NOT
## rescale dx/dy — TS doesn't either (ux/uy then stretch by d_old/d_new).
static func _ik_f64(hx: float, hy: float, fx: float, fy: float, l1: float, l2: float, bend: float) -> PackedFloat64Array:
	var dx: float = fx - hx
	var dy: float = fy - hy
	var d: float = sqrt(dx * dx + dy * dy)
	var reach: float = l1 + l2 - 0.01
	if d > reach:
		dx *= reach / d
		dy *= reach / d
		d = reach
	if d < absf(l1 - l2) + 0.01:
		d = absf(l1 - l2) + 0.01
	# law of cosines for knee offset
	var a: float = (d * d + l1 * l1 - l2 * l2) / (2.0 * d)
	var h: float = sqrt(maxf(0.0, l1 * l1 - a * a))
	var ux: float = dx / d
	var uy: float = dy / d
	return PackedFloat64Array([hx + ux * a - uy * h * bend, hy + uy * a + ux * h * bend])


## Brief-pinned public signature — the knee as a Vector2. NOTE: Vector2 stores
## float32, so this return quantizes (~2e-6 at |knee| ≈ 20); leg_draws rides
## _ik_f64 for the pure-float path, and solve_ik tests pin at 1e-5.
static func solve_ik(hx: float, hy: float, fx: float, fy: float, l1: float, l2: float, bend: float) -> Vector2:
	var k: PackedFloat64Array = _ik_f64(hx, hy, fx, fy, l1, l2, bend)
	return Vector2(k[0], k[1])


## TS:54-62 derived metrics, shared by the three rig blocks (TS computes them
## once as drawCreature locals — same formulas, same op order).
static func _metrics(g: Dictionary, pose: Dictionary) -> Dictionary:
	var s: float = float(pose.get("scale", 1.0))
	var size: float = float(g.get("size", 1.0)) * s
	var leg_h: float = _leg_h(int(g.get("legs", 0)), size)
	var body_r: float = 13.0 * size
	var body_len: float = 40.0 * size
	var body_y: float = -leg_h - body_r * 0.72 + float(pose.get("airborne", 0.0)) * -6.0 * size
	var gait_speed: float = float(pose.get("speed", 0.0))
	var gait_phase: float = float(pose.get("gaitPhase", 0.0))
	var bob: float = sin(gait_phase * 2.0) * 1.6 * size * gait_speed
	var stride: float = 12.0 * size * (0.25 + gait_speed)
	var lift: float = 7.0 * size * gait_speed
	return {
		"size": size, "leg_h": leg_h, "body_r": body_r, "body_len": body_len,
		"body_y": body_y, "gait_speed": gait_speed, "gait_phase": gait_phase,
		"bob": bob, "stride": stride, "lift": lift,
		"attack_lunge": float(pose.get("attack", 0.0))
	}


## TS:54 — leg height: (20 + min(legs, 6)·1.5)·size, 5·size when legs = 0 (the
## *size sits outside the ternary).
static func _leg_h(legs: int, size: float) -> float:
	if legs > 0:
		return (20.0 + minf(float(legs), 6.0) * 1.5) * size
	return 5.0 * size


## TS:99 — body profile curve sin(π·min(1, u·0.85 + 0.12)). The min never
## clamps on the u = i/(SEG−1) grid (u=1 → 0.97) but ports verbatim.
static func _spine_profile(u: float) -> float:
	return sin(PI * minf(1.0, u * 0.85 + 0.12))


## TS:94-108 — the 6 spine discs, pose-local. Entries are Dictionaries
## {x, y, r} (f64 Variants — a Vector2 would quantize to float32 and break the
## pure-float eps class). spine[SEG−1] carries the head lunge (TS:106-108).
static func spine_points(g: Dictionary, pose: Dictionary, t: float) -> Array:
	var m: Dictionary = _metrics(g, pose)
	var size: float = float(m["size"])
	var out: Array = []
	for i in SEG:
		var u: float = float(i) / float(SEG - 1)  # 0 = tail base … 1 = head
		var px: float = (u - 0.42) * float(m["body_len"])  # forward = +x
		var profile: float = _spine_profile(u)
		var pr: float = float(m["body_r"]) * (0.42 + profile * 0.62)
		var py: float = float(m["body_y"]) + float(m["bob"])
		py += sin(t * 2.2 + u * 2.4) * 1.1 * size * (0.3 + float(m["gait_speed"]))
		py += u * u * -2.0 * size  # neck rise toward head
		out.append({"x": px, "y": py, "r": pr})
	var head: Dictionary = out[SEG - 1]  # TS spine[spine.length - 1]
	head["x"] = float(head["x"]) + float(m["attack_lunge"]) * 6.0 * size
	head["y"] = float(head["y"]) + float(m["attack_lunge"]) * 3.0 * size
	return out


## TS:137-150 — 5 tail discs walking backward from spine[0] (re-derived via
## spine_points — pure, so bit-identical to the painter's copy) with a
## per-segment angle drift. Empty when the tail gene is off (TS gates on g.tail).
static func tail_points(g: Dictionary, pose: Dictionary, t: float) -> Array:
	if not bool(g.get("tail", false)):
		return []
	var m: Dictionary = _metrics(g, pose)
	var size: float = float(m["size"])
	var body_r: float = float(m["body_r"])
	var gait_speed: float = float(m["gait_speed"])
	var base: Dictionary = spine_points(g, pose, t)[0]
	var px: float = float(base["x"]) - float(base["r"]) * 0.6
	var py: float = float(base["y"])
	var ang: float = PI + 0.15  # pointing backward
	var seg_len: float = 6.0 * size
	var out: Array = []
	for k in 5:  # segs = 5
		ang += sin(t * 2.6 - float(k) * 0.9) * 0.22 * (0.4 + gait_speed) + 0.06
		px += cos(ang) * seg_len
		py += sin(ang) * seg_len * 0.6
		out.append({"x": px, "y": py, "r": body_r * (0.5 - float(k) * 0.08)})
	return out


## TS:153-171 — one draw struct per leg, TS LegDraw keys {hx, hy, kx, ky, fx, fy}
## (Dictionary Variants, f64). Knees ride _ik_f64, NOT solve_ik (float32 return).
## The spine is re-derived internally (pure → bit-identical to the painter's).
## The TS `?? spine[1]` attach fallback is unreachable: the index 1 +
## round(u·(SEG−3)) stays in [1, 4] for u ∈ [0, 1].
static func leg_draws(g: Dictionary, pose: Dictionary, t: float) -> Array:
	var m: Dictionary = _metrics(g, pose)
	var size: float = float(m["size"])
	var legs: int = int(g.get("legs", 0))
	var out: Array = []
	if legs <= 0:
		return out
	var leg_len: float = float(m["leg_h"]) * 0.58  # legLen1 = legLen2 (TS:156-157)
	var spine: Array = spine_points(g, pose, t)
	var gait: float = float(m["gait_phase"])
	for i in legs:
		var u: float = 0.5 if legs == 1 else float(i) / float(legs - 1)  # 0 back … 1 front
		# TS Math.round is half-up, GDScript roundi half-away — equal on this
		# non-negative range (u·(SEG−3) ∈ [0, 3])
		var attach: Dictionary = spine[1 + roundi(u * float(SEG - 3))]
		var hip_x: float = float(attach["x"]) + (u - 0.5) * float(m["body_len"]) * 0.3
		var hip_y: float = float(attach["y"]) + float(attach["r"]) * 0.45
		var phase: float = gait + float(i % 2) * PI + floor(float(i) / 2.0) * 1.1
		var rest_x: float = hip_x + (u - 0.5) * 6.0 * size
		var foot_x: float = rest_x + cos(phase) * float(m["stride"])
		var foot_lift: float = maxf(0.0, sin(phase)) * float(m["lift"])
		var foot_y: float = -foot_lift
		var bend: float = 1.0 if u < 0.45 else -1.0  # hind knees forward, front elbows back
		var knee: PackedFloat64Array = _ik_f64(hip_x, hip_y, foot_x, foot_y, leg_len, leg_len, bend)
		out.append({"hx": hip_x, "hy": hip_y, "kx": knee[0], "ky": knee[1], "fx": foot_x, "fy": foot_y})
	return out
