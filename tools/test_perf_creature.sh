#!/bin/sh
# One-command entry for the creature perf probe (xvfb + Compatibility
# renderer — 60 force-spawned ents + player, 300 ticks, split metrics: the
# pure sim step asserted at the 2×-target tripwire, the painter render pass
# and the llvmpipe frame window recorded; see tests/scenes/test_perf_creature
# .gd and the headless cross-check tools/perf_creature_sim.gd).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_perf_creature.tscn
