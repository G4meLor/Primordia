## Base for test files: assertion helpers record failures instead of throwing
## (GDScript has no try/catch — a script error would kill the whole run).
class_name TestBase
extends RefCounted

var checks := 0
var failures: PackedStringArray = []

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)

func eq(a: Variant, b: Variant, msg: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])

func approx(a: float, b: float, msg: String, eps := 1e-9) -> void:
	ok(absf(a - b) <= eps, "%s (got %f, want %f)" % [msg, a, b])
