#!/bin/sh
# One-command headless entry for the M5 task-6 civ probes
# (tests/test_probe_civ.gd — the M4 test_probe_tribe shape: pinned seeds,
# TS-verbatim formulas, cloned-stream/independent-derivation asserts). No
# xvfb — the probes are sim-level runner-style (-s, the tests/probe_runner.gd
# targeted entry; the full suite stays tools/test.sh, the xvfb visual gates
# tools/test_*.sh).
cd ~/Desktop/RD/primordia-native || exit 1
exec ~/.local/bin/godot --headless --path . -s res://tests/probe_runner.gd -- \
	res://tests/test_probe_civ.gd
