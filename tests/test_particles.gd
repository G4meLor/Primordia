## Particles pool tests — TS gfx/particles.ts formulas pinned headless.
extends "res://tests/test_base.gd"

const ParticlesScript := preload("res://src/gfx/particles.gd")
const RngScript := preload("res://src/core/rng.gd")


func test_pool_cap_recycles_oldest() -> void:
	var fx = ParticlesScript.new(5)
	for i in 5:
		fx.spawn({"x": 0.0, "y": 0.0, "ttl": 10.0, "id": i})
	eq(fx.active_count(), 5, "pool fills to cap")
	# pressure: the 6th spawn recycles the oldest slot (ring cursor)
	fx.spawn({"x": 0.0, "y": 0.0, "ttl": 10.0})
	eq(fx.active_count(), 5, "spawn under pressure recycles, cap holds")


func test_spawn_defaults_ts_exact() -> void:
	var fx = ParticlesScript.new(2)
	fx.spawn({"x": 3.0, "y": 4.0})
	var p: Dictionary = fx.pool[0]
	eq(p["kind"], "dot", "default kind dot")
	eq(p["ttl"], 1.0, "default ttl 1")
	eq(p["life"], 1.0, "life = ttl")
	eq(p["size"], 3.0, "default size 3")
	eq(p["color"], "#ffffff", "default color")
	eq(p["drag"], 2.0, "default drag 2")
	eq(p["grav"], 0.0, "default grav 0")
	eq(p["grow"], 0.0, "default grow 0")
	eq(p["vx"], 0.0, "default vx 0")
	eq(p["x"], 3.0, "x set")


func test_update_drag_math_ts_exact() -> void:
	var fx = ParticlesScript.new(2)
	fx.spawn({"x": 10.0, "y": 0.0, "vx": 100.0, "vy": 0.0, "ttl": 1.0, "drag": 2.0})
	fx.update(0.1)
	var p: Dictionary = fx.pool[0]
	# d = exp(-drag*dt); vx *= d; THEN x += vx*dt (position uses damped v)
	var d := exp(-2.0 * 0.1)
	approx(float(p["vx"]), 100.0 * d, "vx damped exp(-drag*dt)", 1e-9)
	approx(float(p["x"]), 10.0 + 100.0 * d * 0.1, "x integrates the damped v", 1e-9)
	approx(float(p["life"]), 0.9, "life decays by dt", 1e-9)


func test_update_gravity_after_drag_order() -> void:
	var fx = ParticlesScript.new(2)
	fx.spawn({"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 10.0, "ttl": 1.0, "drag": 2.0, "grav": 50.0})
	fx.update(0.1)
	var p: Dictionary = fx.pool[0]
	# TS order: vy *= d; vy += grav*dt; y += vy*dt
	var d := exp(-2.0 * 0.1)
	var vy := 10.0 * d + 50.0 * 0.1
	approx(float(p["vy"]), vy, "grav added after drag", 1e-9)
	approx(float(p["y"]), vy * 0.1, "y integrates final vy", 1e-9)


func test_ttl_expiry_deactivates() -> void:
	var fx = ParticlesScript.new(2)
	fx.spawn({"x": 0.0, "y": 0.0, "ttl": 0.5})
	fx.update(0.3)
	eq(fx.active_count(), 1, "alive before ttl")
	fx.update(0.3)
	eq(fx.active_count(), 0, "life <= 0 deactivates")


func test_bubble_rises_26_per_sec() -> void:
	var fx = ParticlesScript.new(2)
	fx.spawn({"x": 0.0, "y": 100.0, "ttl": 5.0, "kind": "bubble", "drag": 0.0})
	# TS order: y integrates BEFORE the bubble rise — the first update only
	# changes vy; the position follows on the next update.
	fx.update(0.5)
	var p: Dictionary = fx.pool[0]
	approx(float(p["vy"]), -26.0 * 0.5, "bubble vy -= 26*dt", 1e-9)
	approx(float(p["y"]), 100.0, "y not yet moved (rise applied after integrate)", 1e-9)
	fx.update(0.5)
	approx(float(p["vy"]), -26.0, "vy accumulates", 1e-9)
	# update 2 integrates update 1's vy (-13): y = 100 - 13*0.5 = 93.5
	approx(float(p["y"]), 93.5, "y integrates the PREVIOUS update's vy", 1e-9)
	fx.update(0.5)
	approx(float(p["y"]), 80.5, "third update integrates vy = -26", 1e-9)


func test_ring_growth_formula() -> void:
	var fx = ParticlesScript.new(2)
	fx.spawn({"x": 0.0, "y": 0.0, "kind": "ring", "ttl": 0.8, "size": 30.0, "grow": 3.0})
	fx.update(0.4)  # t = life/ttl = 0.5
	var p: Dictionary = fx.pool[0]
	# radius = size*(1-t) + size*grow*(1-t) → 30*0.5 + 90*0.5 = 60
	approx(ParticlesScript.ring_radius(p, 0.5), 60.0, "ring radius grows with (1-t)", 1e-9)
	approx(ParticlesScript.ring_radius(p, 0.0), 30.0 * 4.0, "ring radius at t=0", 1e-9)


func test_burst_rows_packs_sim_payload() -> void:
	# cell_sim._fx_burst ships {ang, sp, color, ttl, size} rows — the packer
	# must consume ZERO rng draws (the sim already replayed the TS stream).
	var fx = ParticlesScript.new(4)
	fx.burst_rows(5.0, 7.0, 1, {
		"speed": 100.0, "ttl": 0.7,
		"colors": ["#aabbcc"],
		"parts": [{"ang": 0.0, "sp": 100.0, "color": "#ff0000", "ttl": 0.5, "size": 2.0}],
	})
	eq(fx.active_count(), 1, "one row → one particle")
	var p: Dictionary = fx.pool[0]
	eq(p["kind"], "spark", "burst default kind spark (TS)")
	approx(float(p["vx"]), 100.0, "vx = cos(ang)*sp", 1e-9)
	approx(float(p["vy"]), 0.0, "vy = sin(ang)*sp", 1e-9)
	eq(p["color"], "#ff0000", "row color used")
	eq(p["ttl"], 0.5, "row ttl used")
	eq(p["size"], 2.0, "row size used")
	eq(p["drag"], 2.4, "TS burst drag default 2.4")
	eq(p["x"], 5.0, "burst x")
	eq(p["y"], 7.0, "burst y")


func test_burst_consumes_rng_ts_order() -> void:
	# TS burst draw order per particle: ang (or dir±spread), speed, color pick,
	# ttl, size. Verify the packed fields against the same draws replayed.
	var fx = ParticlesScript.new(2)
	var rng = RngScript.new_from(12345)
	fx.burst(1.0, 2.0, 1, rng, {"colors": ["#111111", "#222222"], "speed": 90.0})
	var rng2 = RngScript.new_from(12345)
	var ang: float = rng2.next() * TAU
	var sp: float = rng2.range(0.3, 1.0) * 90.0
	var color: String = String(rng2.pick(["#111111", "#222222"]))
	var ttl: float = rng2.range(0.4, 1.0) * 0.7
	var size: float = rng2.range(0.6, 1.4) * 3.0
	var p: Dictionary = fx.pool[0]
	approx(float(p["vx"]), cos(ang) * sp, "burst vx follows the TS draw order", 1e-9)
	approx(float(p["vy"]), sin(ang) * sp, "burst vy", 1e-9)
	eq(p["color"], color, "color pick position in the stream")
	eq(p["ttl"], ttl, "ttl draw after color pick")
	eq(p["size"], size, "size draw after ttl")


func test_clear_resets_pool() -> void:
	var fx = ParticlesScript.new(3)
	fx.spawn({"x": 0.0, "y": 0.0})
	fx.clear()
	eq(fx.active_count(), 0, "clear deactivates everything")
	fx.spawn({"x": 1.0, "y": 1.0})
	eq(fx.active_count(), 1, "pool reusable after clear")
