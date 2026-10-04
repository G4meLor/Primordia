#!/bin/sh
# One-command entry for the M6 task-7 space play-bot (the full flow through
# the REAL input pipeline — the creature legs' landfall + founding, the tribe
# arc to the REAL victory, the civ arc to the REAL unification, then the
# space arc: fly + trail, abduct, the panel SEED/SCAN clicks, fast-forward,
# splice, the siege, the finale + ending + dismissal, determinism ×2 —
# Global Constraint 8). xvfb + Compatibility renderer: the parse_input_event
# → flush_buffered_events → _unhandled_input dispatch needs a live SceneTree,
# and xvfb is the parity gate's environment. Runtime ~25 min (the civ arc
# rides ~8 min/pass, the space legs add ~2-4 min/pass).
cd ~/Desktop/RD/primordia-native || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_bot_space.tscn
