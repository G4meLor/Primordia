#!/bin/sh
# One-command entry for the task-9 menu click test (xvfb + Compatibility
# renderer — the real input pipeline + the draw-pass button rects need a live
# SceneTree, Global Constraint 8).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_menu.tscn
