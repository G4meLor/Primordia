#!/usr/bin/env bash
# Full headless test suite — zero-plugin runner (tests/run.gd).
# Exit code propagates: 0 = green, 1 = failures (see tests/run.gd).
set -u
cd "$(dirname "$0")/.." || exit 1
exec ~/.local/bin/godot --headless -s tests/run.gd
