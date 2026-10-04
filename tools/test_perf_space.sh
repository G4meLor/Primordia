#!/bin/sh
# One-command entry for the space perf probe (xvfb + Compatibility renderer —
# 6 constructor planets + 3 colonies + 5 far-parked live pirates + 2 far
# black holes, 300 ticks, split metrics: the pure sim tick recorded (the
# asserted ≤ 2 ms budgets in BOTH modes — normal AND ff-hold — live in the
# headless tools/perf_space_sim.gd), the stage render pass asserted ≤ 4 ms,
# the llvmpipe frame window recorded; see tests/scenes/test_perf_space.gd).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_perf_space.tscn
