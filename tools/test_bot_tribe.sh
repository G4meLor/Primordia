#!/bin/sh
# One-command entry for the M4 task-6 tribe play-bot (the full flow through
# the REAL input pipeline — the creature legs' landfall + founding, then the
# tribe arc: gather, build, raid survival, totem, the civ-placeholder victory,
# determinism ×2 — Global Constraint 8). xvfb + Compatibility renderer: the
# parse_input_event → flush_buffered_events → _unhandled_input dispatch needs
# a live SceneTree, and xvfb is the parity gate's environment.
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_bot_tribe.tscn
