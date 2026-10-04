#!/bin/sh
# One-command headless entry for the M6 task-8 space probes
# (tests/test_probe_space.gd — the M4/M5 probe shape: pinned seeds,
# TS-verbatim formulas, cloned-stream/independent-derivation asserts). No
# xvfb — the probes are sim-level runner-style (-s, the tests/probe_runner.gd
# targeted entry; the full suite stays tools/test.sh, the xvfb visual gates
# tools/test_*.sh).
cd ~/Desktop/RD/primordia-native || exit 1
exec ~/.local/bin/godot --headless --path . -s res://tests/probe_runner.gd -- \
	res://tests/test_probe_space.gd
