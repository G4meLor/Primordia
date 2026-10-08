#!/bin/sh
# One-command entry for the R11 card scene test (xvfb + Compatibility
# renderer, llvmpipe-deterministic sha256 pixel asserts). TWO SEQUENTIAL godot
# runs into one combined log — the single-instance law forbids concurrent
# godot processes on this project:
#   1. CARD_SCENARIO=pairs  — renders the same (genome, meta, rect) card twice;
#     the scene asserts the two sha256 pixel hashes byte-identical and different
#     from the empty frame (tests/scenes/test_card_render.gd).
#   2. CARD_SCENARIO=loop50 — 50 back-to-back clear + draw_into frames.
# RID-leak guard (the task ruling — delta 0 is mandatory either lifecycle):
# greps the exit 'WARNING: N RIDs of type "CanvasItem" were leaked' line of
# BOTH runs. Each draw_into frees the previous card's 3 sub-RIDs, so the
# 50× loop's exit telemetry must equal the single-card baseline's (both runs
# end with exactly one live card) — delta != 0 means the loop leaked.
cd "$(dirname "$0")/.." || exit 1

LOG1="$(mktemp)"
LOG2="$(mktemp)"
trap 'rm -f "$LOG1" "$LOG2"' EXIT

CARD_SCENARIO=pairs xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 \
	--path . res://tests/scenes/test_card_render.tscn > "$LOG1" 2>&1
CODE1=$?
CARD_SCENARIO=loop50 xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 \
	--path . res://tests/scenes/test_card_render.tscn > "$LOG2" 2>&1
CODE2=$?
cat "$LOG1" "$LOG2"

RID_LINE='WARNING: [0-9]+ RIDs of type "CanvasItem" were leaked'
L1="$(grep -E "$RID_LINE" "$LOG1" | tail -n 1)"
L2="$(grep -E "$RID_LINE" "$LOG2" | tail -n 1)"
if [ -z "$L1" ] || [ -z "$L2" ]; then
	echo "CARD_RID_GUARD_FAIL: missing the exit RID-warning line (pairs: '$L1' / loop50: '$L2')."
	exit 1
fi
N1="$(printf '%s' "$L1" | sed -E 's/.*WARNING: ([0-9]+) RIDs of type "CanvasItem".*/\1/')"
N2="$(printf '%s' "$L2" | sed -E 's/.*WARNING: ([0-9]+) RIDs of type "CanvasItem".*/\1/')"
if [ "$N1" -ne "$N2" ]; then
	echo "CARD_RID_GUARD_FAIL: pairs leaked $N1, loop50 leaked $N2 (delta $((N2 - N1)) != 0)."
	exit 1
fi
echo "CARD_RID_GUARD_OK: pairs $N1, loop50 $N2 — delta 0."

if [ "$CODE1" -ne 0 ] || [ "$CODE2" -ne 0 ]; then
	echo "CARD_SCENE_FAIL: pairs exit $CODE1, loop50 exit $CODE2."
	exit 1
fi
echo "CARD_SCENE_OK"
