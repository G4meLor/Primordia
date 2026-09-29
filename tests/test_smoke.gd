# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

func test_runner_works() -> void:
	eq(1 + 1, 2, "eq helper")
	approx(0.1 + 0.2, 0.3, "approx helper", 1e-9)
