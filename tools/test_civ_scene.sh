#!/bin/sh
# One-command entry for the M5 task-3 civ-stage scene test (xvfb +
# Compatibility renderer, llvmpipe-deterministic structural asserts — see
# tools/visual_check_civ_scene.py for the assert families).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_civ_scene.tscn
