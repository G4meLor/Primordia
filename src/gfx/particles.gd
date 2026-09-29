## Pooled particle system — port of Spore src/gfx/particles.ts (frozen).
## RefCounted, zero scene-API state: render(canvas_item) issues draw calls on
## whatever CanvasItem it is handed (the stage canvas sets the camera
## transform first — particles live in WORLD space, as in TS).
##
## Feed paths (both TS spawn() shapes):
##  - spawn(opts): full TS Partial<Particle> payload (fx_spawn hook rows).
##  - burst(x, y, n, rng, opts): TS Particles.burst verbatim — consumes the
##    rng exactly like TS (per particle: dir/angle, speed, color pick, ttl,
##    size — gfx/particles.ts:70-84). For callers owning a stream.
##  - burst_rows(x, y, n, opts): the sim's fx_burst hook payload — the sim
##    already replayed the TS rng draws (cell_sim.gd _fx_burst) and ships the
##    sampled per-particle primitives under opts["parts"]; this only packs
##    them (NO rng consumption — Global Constraint 4).
## Colors stay TS CSS strings ('#fff', 'rgba(...)', sim _hsl(...) output) —
## parsed at render time through renderer.gd's css_color (cached per string).
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")

var pool: Array[Dictionary] = []
var cursor := 0


func _init(cap := 900) -> void:
	for i in cap:
		pool.append({
			"active": false, "kind": "dot", "x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0,
			"life": 0.0, "ttl": 1.0, "size": 2.0, "color": "#fff", "drag": 0.0,
			"grav": 0.0, "spin": 0.0, "rot": 0.0, "grow": 0.0,
		})


## Ring-buffer allocation; oldest particles get recycled under pressure
## (TS obtain()).
func _obtain() -> Dictionary:
	for i in pool.size():
		var p: Dictionary = pool[cursor]
		cursor = (cursor + 1) % pool.size()
		if not bool(p["active"]):
			return p
	var p2: Dictionary = pool[cursor]
	cursor = (cursor + 1) % pool.size()
	return p2


## TS spawn(opts) — opts keys TS-verbatim; x/y required in TS.
func spawn(opts: Dictionary) -> void:
	var p: Dictionary = _obtain()
	p["active"] = true
	p["kind"] = String(opts.get("kind", "dot"))
	p["x"] = float(opts.get("x", 0.0))
	p["y"] = float(opts.get("y", 0.0))
	p["vx"] = float(opts.get("vx", 0.0))
	p["vy"] = float(opts.get("vy", 0.0))
	var ttl := float(opts.get("ttl", 1.0))
	p["ttl"] = ttl
	p["life"] = ttl
	p["size"] = float(opts.get("size", 3.0))
	p["color"] = String(opts.get("color", "#ffffff"))
	p["drag"] = float(opts.get("drag", 2.0))
	p["grav"] = float(opts.get("grav", 0.0))
	p["spin"] = float(opts.get("spin", 0.0))
	p["rot"] = float(opts.get("rot", 0.0))
	p["grow"] = float(opts.get("grow", 0.0))


## TS burst (gfx/particles.ts:66-85) verbatim — draw order per particle:
## dir? → dir + rng.range(-spread, spread) : rng.next()*TAU, then speed,
## color pick (only when colors present), then ttl and size inside spawn.
func burst(x: float, y: float, n: int, rng_v: Variant, opts: Dictionary = {}) -> void:
	for i in n:
		var ang: float
		if opts.has("dir"):
			ang = float(opts["dir"]) + rng_v.range(-float(opts.get("spread", PI)), float(opts.get("spread", PI)))
		else:
			ang = rng_v.next() * PI * 2.0
		var sp: float = rng_v.range(0.3, 1.0) * float(opts.get("speed", 90.0))
		var color: String
		if opts.has("colors") and not (opts["colors"] as Array).is_empty():
			color = String(rng_v.pick(opts["colors"]))
		else:
			color = String(opts.get("color", "#ffffff"))
		spawn({
			"kind": String(opts.get("kind", "spark")),
			"x": x, "y": y,
			"vx": cos(ang) * sp, "vy": sin(ang) * sp,
			"ttl": rng_v.range(0.4, 1.0) * float(opts.get("ttl", 0.7)),
			"size": rng_v.range(0.6, 1.4) * float(opts.get("size", 3.0)),
			"color": color,
			"grav": float(opts.get("grav", 0.0)),
			"drag": float(opts.get("drag", 2.4)),
		})


## The sim's fx_burst hook payload (cell_sim.gd _fx_burst): opts carries the
## TS burst opts plus "parts" rows {ang, sp, color, ttl, size} the sim sampled
## from the TS stream. Packs them 1:1 — kind/drag/grav defaults as in TS burst.
func burst_rows(x: float, y: float, n: int, opts: Dictionary) -> void:
	var parts: Array = opts.get("parts", [])
	for row_v in parts:
		var row: Dictionary = row_v
		spawn({
			"kind": String(opts.get("kind", "spark")),
			"x": x, "y": y,
			"vx": cos(float(row["ang"])) * float(row["sp"]),
			"vy": sin(float(row["ang"])) * float(row["sp"]),
			"ttl": float(row["ttl"]),
			"size": float(row["size"]),
			"color": String(row["color"]),
			"grav": float(opts.get("grav", 0.0)),
			"drag": float(opts.get("drag", 2.4)),
		})


func clear() -> void:
	for p in pool:
		p["active"] = false


func active_count() -> int:
	var n := 0
	for p in pool:
		if bool(p["active"]):
			n += 1
	return n


## TS update(dt) verbatim: ttl decay, exp drag, gravity, integrate, spin,
## bubble rise (vy -= 26*dt).
func update(dt: float) -> void:
	for p in pool:
		if not bool(p["active"]):
			continue
		p["life"] = float(p["life"]) - dt
		if float(p["life"]) <= 0.0:
			p["active"] = false
			continue
		var d: float = exp(-float(p["drag"]) * dt)
		p["vx"] = float(p["vx"]) * d
		p["vy"] = float(p["vy"]) * d
		p["vy"] = float(p["vy"]) + float(p["grav"]) * dt
		p["x"] = float(p["x"]) + float(p["vx"]) * dt
		p["y"] = float(p["y"]) + float(p["vy"]) * dt
		p["rot"] = float(p["rot"]) + float(p["spin"]) * dt
		if String(p["kind"]) == "bubble":
			p["vy"] = float(p["vy"]) - 26.0 * dt  # bubbles rise


## TS render(dt) — per-kind draw with the fade a = t<0.25 ? t/0.25 : 1
## (t = life/ttl, 1 → 0). Colors fade their ALPHA with RGB held, which is
## what canvas premultiplied-gradient/globalAlpha compositing shows.
func render(ci: CanvasItem) -> void:
	for p in pool:
		if not bool(p["active"]):
			continue
		var t: float = float(p["life"]) / float(p["ttl"])  # 1 → 0
		var a: float = t / 0.25 if t < 0.25 else 1.0
		var col: Color = RendererScript.css_color(String(p["color"]))
		var kind := String(p["kind"])
		var pos := Vector2(float(p["x"]), float(p["y"]))
		match kind:
			"dot":
				ci.draw_circle(pos, float(p["size"]) * (0.5 + t * 0.5), _fade(col, a))
			"spark":
				var vl := Vector2(float(p["vx"]), float(p["vy"])).length()
				if vl <= 0.0:
					vl = 1.0  # TS hypot||1 guard
				var dir := Vector2(float(p["vx"]) / vl, float(p["vy"]) / vl)
				var l := float(p["size"]) * 2.2
				ci.draw_line(pos, pos - dir * l, _fade(col, a), maxf(1.0, float(p["size"]) * t), true)
			"bubble":
				var br := float(p["size"]) * (0.7 + t * 0.3)
				ci.draw_arc(pos, br, 0.0, TAU, 24, _fade(col, a), 1.2)
				ci.draw_circle(pos, br, _fade(col, a * 0.25))
			"ring":
				var rr := float(p["size"]) * (1.0 - t) + float(p["size"]) * float(p["grow"]) * (1.0 - t)
				ci.draw_arc(pos, rr, 0.0, TAU, 48, _fade(col, a), maxf(1.0, float(p["size"]) * 0.22 * t))
			"leaf":
				ci.draw_colored_polygon(
						RendererScript.ellipse_points(pos, float(p["size"]) * 1.6, float(p["size"]) * 0.7, float(p["rot"])),
						_fade(col, a))
			"star":
				_star(ci, pos, float(p["rot"]), float(p["size"]) * (0.5 + t * 0.8), _fade(col, a))
			"smoke":
				ci.draw_circle(pos, float(p["size"]) * (1.6 - t), _fade(col, a * 0.35))


## TS ring radius math, exposed for headless tests (render reads it too).
static func ring_radius(p: Dictionary, t: float) -> float:
	return float(p["size"]) * (1.0 - t) + float(p["size"]) * float(p["grow"]) * (1.0 - t)


static func _fade(c: Color, alpha: float) -> Color:
	var out := c
	out.a = c.a * alpha
	return out


## TS star: 10-point alternating r / r*0.45 polygon, rotated by p.rot.
static func _star(ci: CanvasItem, pos: Vector2, rot: float, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var ang := (float(i) / 10.0) * TAU + rot
		pts.append(pos + Vector2(cos(ang) * rr, sin(ang) * rr))
	ci.draw_colored_polygon(pts, col)
