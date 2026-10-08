#!/bin/sh
# One-command entry for the R9/R8 card scene test (xvfb + Compatibility
# renderer, llvmpipe-deterministic sha256 pixel asserts). TWO SEQUENTIAL godot
# runs into one combined log — the single-instance law forbids concurrent
# godot processes on this project:
#   1. PACK_ROW_SCENARIO=pairs  — renders a 2-slot pack row + the extinction
#     card (the stage's own PackCardItem/SpeciesCardItem classes), asserts the
#     two sha256 pixel hashes byte-identical and different from the empty
#     frame, then walks the release/free teardown and asserts the card's
#     static registry ends EMPTY (tests/scenes/test_pack_row.gd).
#   2. PACK_ROW_SCENARIO=loop50 — 50 back-to-back full redraws (clear per
#     redraw = the MUST-1 contract).
# RID-leak guard (the task ruling — delta 0 is mandatory):
# greps the exit 'WARNING: N RIDs of type "CanvasItem" were leaked' line of
# BOTH runs. Each redraw frees the previous card's 3 sub-RIDs per item, so
# the 50x loop's exit telemetry must equal the pairs baseline's — delta != 0
# means the redraw churn leaks.
cd "$(dirname "$0")/.." || exit 1

LOG1="$(mktemp)"
LOG2="$(mktemp)"
trap 'rm -f "$LOG1" "$LOG2"' EXIT

PACK_ROW_SCENARIO=pairs xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 \
	--path . res://tests/scenes/test_pack_row.tscn > "$LOG1" 2>&1
CODE1=$?
PACK_ROW_SCENARIO=loop50 xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 \
	--path . res://tests/scenes/test_pack_row.tscn > "$LOG2" 2>&1
CODE2=$?
cat "$LOG1" "$LOG2"

RID_LINE='WARNING: [0-9]+ RIDs of type "CanvasItem" were leaked'
L1="$(grep -E "$RID_LINE" "$LOG1" | tail -n 1)"
L2="$(grep -E "$RID_LINE" "$LOG2" | tail -n 1)"
# A MISSING line means Godot printed no leak warning = 0 leaked CanvasItems —
# the CLEAN exit this scene is designed for (every card is released before
# quit, unlike the task-5 card scene whose one live card leaks 3 in both
# runs). The guard is the DELTA: pairs vs loop50 must agree whatever the abs.
N1=0
N2=0
if [ -n "$L1" ]; then
	N1="$(printf '%s' "$L1" | sed -E 's/.*WARNING: ([0-9]+) RIDs of type "CanvasItem".*/\1/')"
fi
if [ -n "$L2" ]; then
	N2="$(printf '%s' "$L2" | sed -E 's/.*WARNING: ([0-9]+) RIDs of type "CanvasItem".*/\1/')"
fi
if [ "$N1" -ne "$N2" ]; then
	echo "PACK_ROW_RID_GUARD_FAIL: pairs leaked $N1, loop50 leaked $N2 (delta $((N2 - N1)) != 0)."
	exit 1
fi
echo "PACK_ROW_RID_GUARD_OK: pairs $N1, loop50 $N2 — delta 0 (missing line = 0 leaked)."

if [ "$CODE1" -ne 0 ] || [ "$CODE2" -ne 0 ]; then
	echo "PACK_ROW_SCENE_FAIL: pairs exit $CODE1, loop50 exit $CODE2."
	exit 1
fi
echo "PACK_ROW_SCENE_OK"
