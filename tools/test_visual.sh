#!/bin/sh
# One-command entry for the task-7 pixel-assert (xvfb + Compatibility
# renderer, llvmpipe-deterministic structural asserts — see the checker).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_visual_cell.tscn
