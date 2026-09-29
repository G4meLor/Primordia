# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path — a bare global name (Rng,
# Fixtures) would not resolve without the editor's class cache.
const Rng := preload("res://src/core/rng.gd")
const Fixtures := preload("res://tests/fixtures.gd")

# Fixture call arguments (see rng_stream.json consumptionOrder).
const WEIGHTED_ENTRIES := [[1, "a"], [3, "b"], [0.5, "c"]]

func _streams() -> Array:
	var data := Fixtures.load_json("rng_stream")
	ok(not data.is_empty(), "fixture rng_stream.json loads")
	return data.get("streams", [])


# Godot 4.2's decimal->float64 parse (literals, float(), and JSON all share it)
# mis-rounds some fixture decimals by 1 ulp: e.g. "0.19281403115019202" parses to
# 828129957/2^32 while TS's exact value is 828129958/2^32 (verified against node).
# Mulberry32's true output domain is the uint32 t = v * 2^32, and roundi(f * 2^32)
# recovers that integer exactly (a <=1 ulp parse error scales to <= 2^-22, far below
# 0.5), so next() parity is compared on those integers: zero tolerance, no eps.
func _next_u32(r: Variant) -> int:
	return roundi(r.next() * 4294967296.0)


func _expected_u32(f: float) -> int:
	return roundi(f * 4294967296.0)


# gauss() output is an arbitrary float64 — no integer domain to compare in, and the
# fixture's decimal text carries <= 1 ulp of Godot-parse noise (measured: max 0.71
# ulp across all 30 fixture gauss values). 4 ulps (~9e-16 relative) is the exactness
# limit of the comparison channel; a real port bug shows up at >= 2^-32 relative.
func _assert_ulp_close(a: float, b: float, msg: String) -> void:
	var scale: float = maxf(absf(a), absf(b)) * 2.220446049250313e-16
	if scale == 0.0:
		eq(a, b, msg)
		return
	ok(absf(a - b) <= scale * 4.0, msg)


func test_next_matches_ts() -> void:
	for stream in _streams():
		var seed := int(stream["seed"])
		var r: Variant = Rng.new_from(seed)
		var expected: Array = stream["next"]
		for i in expected.size():
			eq(_next_u32(r), _expected_u32(expected[i]),
					"seed %d next[%d] (as uint32 t)" % [seed, i])


func test_derived_ops_match_ts() -> void:
	for stream in _streams():
		var seed := int(stream["seed"])
		var r: Variant = Rng.new_from(seed)
		for _i in 50:
			r.next()  # documented prefix: next x50
		var ints: Array = stream["int_2_8"]
		for i in ints.size():
			eq(r.int(2, 8), ints[i], "seed %d int(2,8)[%d]" % [seed, i])
		var chances: Array = stream["chance_0_3"]
		for i in chances.size():
			eq(r.chance(0.3), chances[i], "seed %d chance(0.3)[%d]" % [seed, i])
		var picks: Array = stream["weighted"]
		for i in picks.size():
			eq(r.weighted(WEIGHTED_ENTRIES), picks[i], "seed %d weighted[%d]" % [seed, i])
		var gaussians: Array = stream["gauss"]
		for i in gaussians.size():
			_assert_ulp_close(r.gauss(), gaussians[i], "seed %d gauss[%d]" % [seed, i])
		var branches: Array = stream["branch_seeds"]
		for i in branches.size():
			eq(r.branch().state(), branches[i], "seed %d branch[%d]" % [seed, i])


func test_constructor_masking_matches_ts() -> void:
	eq(Rng.new(0).state(), 0x9e3779b9, "seed 0 -> golden fallback (s === 0)")
	eq(Rng.new(-1).state(), 0xFFFFFFFF, "negative seed masked like >>> 0")
	eq(Rng.new(4294967296).state(), 0x9e3779b9, "2^32 wraps to 0 -> fallback")
	eq(Rng.new(0xDEADBEEF).state(), 0xDEADBEEF, "seed kept as uint32")


func test_set_state_resumes_stream() -> void:
	var a: Variant = Rng.new_from(123)
	var b: Variant = Rng.new_from(123)
	for _i in 10:
		a.next()
	a.set_state(b.state())
	for i in 10:
		approx(a.next(), b.next(), "resumed stream equal [%d]" % i, 0.0)


func test_set_state_masking() -> void:
	var r: Variant = Rng.new_from(5)
	r.set_state(0)
	eq(r.state(), 0x9e3779b9, "set_state(0) -> golden fallback (>>> 0 || 0x9e3779b9)")
	r.set_state(-7)
	eq(r.state(), 4294967289, "set_state(-7) masked like >>> 0")


func test_range_int_bounds() -> void:
	var r: Variant = Rng.new_from(3)
	for _i in 300:
		var v: float = r.range(-3.5, 2.5)
		ok(v >= -3.5 and v < 2.5, "range(-3.5, 2.5) in [lo, hi): %f" % v)
		var n: int = r.int(2, 8)
		ok(n >= 2 and n <= 8, "int(2, 8) inclusive bounds: %d" % n)


func test_chance_edges() -> void:
	var r: Variant = Rng.new_from(2)
	for _i in 100:
		ok(r.chance(0.0) == false, "chance(0) always false")
	var r2: Variant = Rng.new_from(2)
	for _i in 100:
		ok(r2.chance(1.0) == true, "chance(1) always true")


func test_pick_empty_returns_null() -> void:
	var r: Variant = Rng.new_from(11)
	var arr := [10, 20, 30]
	ok(arr.has(r.pick(arr)), "pick returns an element")
	ok(r.pick([]) == null, "pick([]) -> null (push_error)")


func test_shuffled_behavior() -> void:
	var r: Variant = Rng.new_from(11)
	var source := [1, 2, 3, 4, 5, 6, 7]
	var out: Array = r.shuffled(source)
	eq(out.size(), 7, "shuffled keeps size")
	var sorted := out.duplicate()
	sorted.sort()
	eq(sorted, source, "shuffled is a permutation")
	eq(source, [1, 2, 3, 4, 5, 6, 7], "shuffled does not mutate input")
	var r1: Variant = Rng.new_from(11)
	var r2: Variant = Rng.new_from(11)
	eq(r1.shuffled([1, 2, 3, 4, 5, 6, 7]), r2.shuffled([1, 2, 3, 4, 5, 6, 7]),
			"shuffled deterministic per seed")


func test_weighted_semantics() -> void:
	var r: Variant = Rng.new_from(1)
	eq(r.weighted([[0, "x"], [0, "y"]]), "x", "zero total: r=0 hits first entry (r <= 0)")
	eq(r.weighted([[-5, "neg"], [1, "pos"]]), "pos", "negative weight clamped to 0")
	ok(r.weighted([]) == null, "weighted([]) -> null (push_error)")


func test_gauss_clamp_bounds() -> void:
	var r: Variant = Rng.new_from(4)
	for _i in 300:
		var v: float = r.gauss_clamp(10.0, 2.0)
		ok(v >= 6.0 and v <= 14.0, "gauss_clamp(10, 2) within mean ± k*sd: %f" % v)
		var v3: float = r.gauss_clamp(0.0, 1.0, 3.0)
		ok(v3 >= -3.0 and v3 <= 3.0, "gauss_clamp(0, 1, 3) within mean ± 3 sd: %f" % v3)


func test_new_from_matches_new() -> void:
	var a: Variant = Rng.new_from(42)
	var b: Variant = Rng.new(42)
	for i in 20:
		approx(a.next(), b.next(), "new_from == new [%d]" % i, 0.0)
