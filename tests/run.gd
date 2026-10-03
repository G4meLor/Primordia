## Zero-plugin test runner. Usage: godot --headless -s tests/run.gd
## Discovers res://tests/test_*.gd, runs every method named test_*, exits 1 on failure.
##
## TWO-PASS script-error guard (the M3 zero-check-guard family): a mid-body
## runtime error is FRAME-LOCAL in GDScript — the errored function aborts but
## every caller resumes (probed empirically), so the runner loop cannot see a
## truncated test body and its partial checks would read green (the T1
## persist-test bug: 36 checks / 0 failures over a dead body). GDScript has no
## in-process error hook, so the DEFAULT pass re-executes this same suite as a
## SEQUENTIAL worker subprocess (OS.execute is blocking — the two godot
## processes never overlap, the project-cache single-instance law holds) with
## the combined output captured, relays it verbatim (the totals line stays the
## suite's own), and fails the gate on ANY "SCRIPT ERROR" line — the error's
## `at:` line names the erroring function + file:line, so the FAIL names the
## site. Known double-count: a test file that fails to COMPILE is already one
## worker failure (the loader's "script failed to load") and its Parse Error
## SCRIPT ERROR line adds a second here — the gate is binary, so this only
## makes red suites noisier, never a green one.
extends SceneTree

const WORKER_ENV := "PRIMORDIA_SUITE_WORKER"


func _initialize() -> void:
	if OS.get_environment(WORKER_ENV) != "":
		_run_suite()
	else:
		_run_guard()


# ---- guard pass (default): capture + relay + the script-error scan ------------

func _run_guard() -> void:
	OS.set_environment(WORKER_ENV, "1")
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), OS.get_cmdline_args(), output, true, true)
	var captured: String = String(output[0]) if output.size() > 0 else ""
	print(captured)
	if code != 0 and captured.is_empty():
		print("GUARD: the worker exited with code %d and produced no output" % code)
	var errors := _script_errors(captured)
	var failures := 0
	for e in errors:
		failures += 1
		print("FAIL %s (script error mid-body — a truncated test body must not read green)" % e)
	print("script-error guard: %d script error(s) in the suite log" % errors.size())
	quit(1 if failures > 0 or code != 0 else 0)


## Every "SCRIPT ERROR" line with its `at:` attribution ("fn (res://…:line)");
## an error with no at: line falls back to the raw error text.
func _script_errors(log: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var pending := ""
	for raw_line in log.split("\n"):
		var line := raw_line.strip_edges(true, false)  # leading indent off — the at: lines are indented
		if line.begins_with("SCRIPT ERROR"):
			pending = line
		elif pending != "" and line.begins_with("at: "):
			out.append(String(line.substr(4)).strip_edges())
			pending = ""
	if pending != "":
		out.append(pending)  # an error whose at: never came
	return out


# ---- worker pass: the suite itself ----------------------------------------------

func _run_suite() -> void:
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
			# test asserts at least once). The mid-body PARTIAL case (checks >
			# 0) is invisible here — the two-pass guard pass catches it.
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
