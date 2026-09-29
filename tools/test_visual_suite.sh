#!/bin/sh
# One-command entry for the task-10 six-moment visual suite (xvfb +
# Compatibility renderer — see tools/visual_assert.py for the structural
# per-moment assert table).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_visual_suite.tscn
