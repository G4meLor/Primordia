#!/bin/sh
# One-command entry for the civ perf probe (xvfb + Compatibility renderer —
# 4 constructor cities + 3 far-parked live armadas, 300 ticks, split
# metrics: the pure sim tick recorded (the asserted ≤ 2 ms budget lives in
# the headless tools/perf_civ_sim.gd), the stage render pass asserted
# ≤ 4 ms, the llvmpipe frame window recorded; see tests/scenes/test_perf_civ
# .gd).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_perf_civ.tscn
