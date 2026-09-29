#!/bin/sh
# One-command entry for the M2 perf probe (xvfb + Compatibility renderer —
# 200 force-spawned ents, 600 ticks, ≤ 8 ms/tick + the 60 fps frame budget,
# llvmpipe worst case; see tests/scenes/test_perf.gd).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_perf.tscn
