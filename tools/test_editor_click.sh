#!/bin/sh
# One-command entry for the task-8 editor click test (xvfb + Compatibility
# renderer — the real input pipeline + draw pass need a live SceneTree,
# Global Constraint 8). The root is SCRIPT-DERIVED (the tools/ab_test.sh
# pattern) so the wrapper always tests the tree it lives in — a hardcode to
# the main checkout made the quoted evidence test the wrong tree when the
# script ran from a worktree (task-6 review finding).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
exec xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
	res://tests/scenes/test_editor_click.tscn
