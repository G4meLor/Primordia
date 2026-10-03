#!/bin/sh
# One-command entry for the M5 task-5 civ play-bot (the full flow through
# the REAL input pipeline — the creature legs' landfall + founding, the
# tribe arc to the REAL victory, then the civ arc: sliders, honest launches,
# armada flight capture, resolves, regen, the unification victory + the
# space placeholder, determinism ×2 — Global Constraint 8). xvfb +
# Compatibility renderer: the parse_input_event → flush_buffered_events →
# _unhandled_input dispatch needs a live SceneTree, and xvfb is the parity
# gate's environment.
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_bot_civ.tscn
