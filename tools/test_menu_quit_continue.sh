#!/bin/sh
# One-command entry for the quit-to-title → CONTINUE menu click test (QC r1 B2
# follow-up; xvfb + Compatibility renderer — the real input pipeline + the
# draw-pass button rects need a live SceneTree, Global Constraint 8).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_menu_quit_continue.tscn
