#!/bin/sh
# M6 wrap xvfb sweep — STRICTLY SEQUENTIAL (one godot instance at a time,
# the binding law). Each entry capped at 1200 s (>= the 900 s floor); the
# five BOTS get 2400 s (the brief's "caps >= 900 s (bots more)" — bot_space
# is documented ~25 min, the x2 bots need more than the M5 1200 s cap gave
# bot_civ). Rider 1 (the T6-review minor carried to the wrap): the sweep
# runs ALL entries incl. boot, EVERY stage's scene suite
# (creature/tribe/civ/space) and ALL bots — the register() hide change
# (38bf9fb) touches every stage's boot, so nothing may be skipped.
# bot_space runs LAST (the milestone bot; nothing follows it, the M5
# bot_civ-last pattern).
set -u
cd ~/Desktop/RD/primordia-native || exit 1
OUT=/tmp/wrap_xvfb_m6
mkdir -p "$OUT"
GODOT="$HOME/.local/bin/godot"

run_tscn() {  # name tscn-path
	local name="$1" tscn="$2"
	timeout 1200 xvfb-run -a "$GODOT" --rendering-driver opengl3 --path . "$tscn" > "$OUT/$name.log" 2>&1
	echo "$name rc=$?"
}
run_tool() {  # name tool-script [cap]
	local name="$1" script="$2" cap="${3:-1200}"
	timeout "$cap" "$script" > "$OUT/$name.log" 2>&1
	echo "$name rc=$?"
}

run_tscn  boot            res://tests/scenes/test_boot.tscn
run_tool  bot             tools/test_bot.sh 2400
run_tool  bot_creature    tools/test_bot_creature.sh 2400
run_tool  bot_tribe       tools/test_bot_tribe.sh 2400
run_tool  bot_civ         tools/test_bot_civ.sh 2400
run_tool  editor_click    tools/test_editor_click.sh
run_tool  menu            tools/test_menu.sh
run_tool  visual          tools/test_visual.sh
run_tool  visual_creature tools/test_visual_creature.sh
run_tool  visual_suite    tools/test_visual_suite.sh
run_tool  creature_scene  tools/test_creature_scene.sh
run_tool  tribe_scene     tools/test_tribe_scene.sh
run_tool  civ_scene       tools/test_civ_scene.sh
run_tool  space_scene     tools/test_space_scene.sh
run_tool  perf            tools/test_perf.sh
run_tool  perf_creature   tools/test_perf_creature.sh
run_tool  perf_tribe      tools/test_perf_tribe.sh
run_tool  perf_civ        tools/test_perf_civ.sh
run_tool  perf_space      tools/test_perf_space.sh
run_tool  bot_space       tools/test_bot_space.sh 2400
echo "SWEEP_DONE"
