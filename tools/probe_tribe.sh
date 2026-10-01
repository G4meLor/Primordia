#!/bin/sh
# One-command headless entry for the task-7 tribe econ probes
# (tests/test_probe_tribe.gd — the M3 test_probe_creature shape: pinned seeds,
# TS-verbatim formulas, twin-replay/exact-identity asserts). No xvfb — the
# probes are sim-level runner-style (-s, the tests/probe_runner.gd targeted
# entry; the full suite stays tools/test.sh, the xvfb visual gates
# tools/test_*.sh).
cd ~/Desktop/RD/primordia-native || exit 1
exec ~/.local/bin/godot --headless --path . -s res://tests/probe_runner.gd -- \
	res://tests/test_probe_tribe.gd
