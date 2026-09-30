#!/bin/sh
# One-command headless entry for the task-10 creature econ probes
# (tests/test_probe_creature.gd — the M2 test_econ_probes shape: pinned seeds,
# TS-verbatim formulas, statistical/procedural asserts). No xvfb — the probes
# are sim-level runner-style (-s, the tests/probe_runner.gd targeted entry;
# the full suite stays tools/test.sh, the xvfb visual gates tools/test_*.sh).
cd ~/Desktop/RD/primordia-native || exit 1
exec ~/.local/bin/godot --headless --path . -s res://tests/probe_runner.gd -- \
	res://tests/test_probe_creature.gd
