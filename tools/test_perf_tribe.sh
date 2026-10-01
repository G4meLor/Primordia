#!/bin/sh
# One-command entry for the tribe perf probe (xvfb + Compatibility renderer —
# 60 force-stocked tribesmen + 6 rival warriors + 6 huts, 300 ticks, split
# metrics: the pure sim tick recorded (the asserted tripwire lives in the
# headless tools/perf_tribe_sim.gd), the stage render pass asserted ≤ 4 ms,
# the llvmpipe frame window recorded; see tests/scenes/test_perf_tribe.gd).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_perf_tribe.tscn
