#!/bin/sh
# One-command entry for the task-5 space-stage scene test (xvfb +
# Compatibility renderer, llvmpipe-deterministic structural asserts — see
# tools/visual_check_space_scene.py for the assert families).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_space_scene.tscn
