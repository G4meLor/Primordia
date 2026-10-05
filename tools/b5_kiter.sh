#!/bin/sh
# QC r1 B5 measurement entry — kiter-bot death-spiral probe. Headless: the
# sim-level run needs no draw pass (buys ride editor.click_part, the
# documented programmatic path); gameplay inputs ride the REAL pipeline.
# Usage: tools/b5_kiter.sh [seed ...]   (default: 0xBEEF 0xC0FFEE 0x5EED5EED)
cd "$(dirname "$0")/.." || exit 1
exec "${GODOT:-$HOME/.local/bin/godot}" --headless --path . \
	res://tests/scenes/test_b5_kiter.tscn -- "$@"
