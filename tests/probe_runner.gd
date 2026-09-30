## Targeted headless runner for ONE test file — the one-command probe entries
## (tools/probe_creature.sh) gate on this instead of the full tests/run.gd
## suite. Same contract as run.gd: every test_* method, fresh instance per
## test, exit 1 on any failure.
## Usage: godot --headless -s res://tests/probe_runner.gd -- res://tests/<file>.gd
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("PROBE_FAIL: need a res:// test file argument")
		quit(1)
		return
	var path: String = args[0]
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		# a test script that fails to load must be a visible red, not a hang
		printerr("PROBE_FAIL: %s failed to load or compile" % path)
		quit(1)
		return
	var methods: PackedStringArray = []
	for m in script.get_script_method_list():
		if String(m["name"]).begins_with("test_") and not methods.has(String(m["name"])):
			methods.append(String(m["name"]))
	methods.sort()
	if methods.is_empty():
		printerr("PROBE_FAIL: %s holds no test_ methods" % path)
		quit(1)
		return
	var total_checks := 0
	var total_failures := 0
	for method in methods:
		var t: RefCounted = script.new()
		t.call(method)
		var f: int = t.failures.size()
		total_checks += t.checks
		total_failures += f
		var status := "ok" if f == 0 else "FAIL"
		print("%s %s.%s (%d checks, %d failures)" % [status, path.get_file(), method, t.checks, f])
		if f > 0:
			for msg in t.failures:
				print("    ✗ " + msg)
	print("---")
	print("%d test%s, %d check%s, %d failure%s" % [
		methods.size(), "" if methods.size() == 1 else "s",
		total_checks, "" if total_checks == 1 else "s",
		total_failures, "" if total_failures == 1 else "s",
	])
	quit(1 if total_failures > 0 else 0)
