#!/bin/sh
# One-command entry for the task-6 play-bot arc (the 2-minute messy play
# through the REAL input pipeline, Global Constraint 8). xvfb + Compatibility
# renderer: the parse_input_event → flush_buffered_events → _unhandled_input
# dispatch needs a live SceneTree, and xvfb is the parity gate's environment.
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_bot_arc.tscn
