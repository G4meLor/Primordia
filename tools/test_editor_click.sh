#!/bin/sh
# One-command entry for the task-8 editor click test (xvfb + Compatibility
# renderer — the real input pipeline + draw pass need a live SceneTree,
# Global Constraint 8).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_editor_click.tscn
