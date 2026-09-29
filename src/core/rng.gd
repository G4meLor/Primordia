## Seeded RNG (Mulberry32) so every generated world/species/texture is
## reproducible from a seed — a hard requirement for the save system and tests.
## Bit-exact port of Spore src/core/rng.ts: all internal state stays masked to
## uint32 so GDScript `>>` on non-negative ints matches JS `>>>` (logical).
class_name Rng
extends RefCounted

# Global class_name resolution needs the editor's script class cache, which
# doesn't exist in `-s` mode (fresh clone/CI), so this file never uses its own
# class name as an identifier — it loads its own res:// path instead. That also
# keeps TS `new Rng(...)` semantics (always constructs the base class).
const SELF_SCRIPT := "res://src/core/rng.gd"

var _s: int = 0

func _init(seed: int = 1) -> void:
	_s = seed & 0xFFFFFFFF  # JS `seed >>> 0`
	if _s == 0:
		_s = 0x9e3779b9

static func new_from(seed: int) -> Rng:
	return load(SELF_SCRIPT).new(seed)

## Core: float in [0, 1).
func next() -> float:
	_s = (_s + 0x6d2b79f5) & 0xFFFFFFFF
	var t: int = _s
	t = _imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

# Math.imul: 32-bit multiply keeping the low 32 bits. JS bitwise ops work on
# bit patterns, so masking the uint32 operands keeps this bit-exact with TS;
# int64 overflow wraps mod 2^64, which cannot change the low 32 bits.
static func _imul(a: int, b: int) -> int:
	return (a * b) & 0xFFFFFFFF

## Float in [lo, hi).
func range(lo: float, hi: float) -> float:
	return lo + next() * (hi - lo)

## Integer in [lo, hi] inclusive.
func int(lo: int, hi: int) -> int:
	# self. prefix: a bare `range(...)` would hit the global built-in, not this method
	return floori(self.range(lo, hi + 1))

func chance(p: float) -> bool:
	return next() < p

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		push_error("Rng.pick: empty array")
		return null
	return arr[floori(next() * arr.size())]

## Weighted pick: entries are [weight, item].
func weighted(entries: Array) -> Variant:
	if entries.is_empty():
		push_error("Rng.weighted: empty entries")
		return null
	var total := 0.0
	for e in entries:
		total += maxf(0.0, e[0])
	var r: float = next() * total
	for e in entries:
		r -= maxf(0.0, e[0])
		if r <= 0.0:
			return e[1]
	return entries[entries.size() - 1][1]

## Shallow shuffle (Fisher-Yates), returns a copy.
func shuffled(arr: Array) -> Array:
	var a: Array = arr.duplicate()
	var i: int = a.size() - 1
	while i > 0:
		var j: int = floori(next() * (i + 1))
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
		i -= 1
	return a

## Approximately normal distribution (mean 0, sd 1) via Irwin-Hall.
func gauss() -> float:
	return (next() + next() + next() - 1.5) * 2

## Gaussian clamped to [mean - sd*k, mean + sd*k].
func gauss_clamp(mean: float, sd: float, k: float = 2.0) -> float:
	return maxf(mean - sd * k, minf(mean + sd * k, mean + gauss() * sd))

## Generate a new child seed (deterministic from current state).
func branch() -> Rng:
	return load(SELF_SCRIPT).new(floori(next() * 0xffffffff))

func state() -> int:
	return _s

func set_state(s: int) -> void:
	_s = s & 0xFFFFFFFF  # JS `s >>> 0 || 0x9e3779b9`
	if _s == 0:
		_s = 0x9e3779b9
