#!/bin/sh
# One-command entry for the task-6B creature pixel-assert (xvfb +
# Compatibility renderer, llvmpipe-deterministic structural asserts — see
# tools/visual_check_creature.py for the assert families and their provenance).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_visual_creature.tscn
