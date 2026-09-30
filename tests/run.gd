## Zero-plugin test runner. Usage: godot --headless -s tests/run.gd
## Discovers res://tests/test_*.gd, runs every method named test_*, exits 1 on failure.
extends SceneTree

func _initialize() -> void:
	var total_checks := 0
	var total_failures := 0
	var files_with_tests := 0
	var files := _discover()
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			# a test script that fails to load must be a visible red, not a hang
			print("FAIL %s (script failed to load or compile)" % path.get_file())
			total_failures += 1
			continue
		var instance: RefCounted = script.new()
		var methods: PackedStringArray = []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_") and not methods.has(String(m.name)):
				methods.append(String(m.name))
		methods.sort()
		if methods.is_empty():
			# helper files (e.g. test_base.gd) match test_*.gd but hold no tests
			continue
		files_with_tests += 1
		for method in methods:
			# fresh instance per test = state isolation
			var t: RefCounted = script.new()
			t.call(method)
			var f: int = t.failures.size()
			# zero-check guard (M3 final review I-1): a body that aborts on a
			# runtime script error mid-way reports 0 checks / 0 failures and
			# would read as green — treat it as a failure instead (a healthy
			# test asserts at least once).
			if f == 0 and t.checks == 0:
				f = 1
				t.failures.append("zero checks recorded — the test body aborted before asserting (script error mid-way?)")
			total_checks += t.checks
			total_failures += f
			var status := "ok" if f == 0 else "FAIL"
			print("%s %s.%s (%d checks, %d failures)" % [status, path.get_file(), method, t.checks, f])
			if f > 0:
				for msg in t.failures:
					print("    ✗ " + msg)
	print("---")
	var n_tests := _count_tests(files)
	print("%d file%s, %d test%s, %d check%s, %d failure%s" % [
		files_with_tests, _plural(files_with_tests),
		n_tests, _plural(n_tests),
		total_checks, _plural(total_checks),
		total_failures, _plural(total_failures),
	])
	quit(1 if total_failures > 0 else 0)

func _plural(n: int) -> String:
	return "" if n == 1 else "s"

func _discover() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append("res://tests/" + f)
	out.sort()
	return out

func _count_tests(files: PackedStringArray) -> int:
	var n := 0
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			continue
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_"):
				n += 1
	return n
