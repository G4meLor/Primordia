#!/bin/sh
# M5 wrap xvfb sweep — STRICTLY SEQUENTIAL (one godot instance at a time,
# the binding law). Each entry capped at 1200 s (>= the 900 s floor; the
# x2 bots need >600 s). bot_civ runs LAST — it is the T6-review rider 2
# (the third BOT_CIV_ALL_OK on the final tree), so nothing follows it.
set -u
cd ~/Desktop/RD/primordia-native || exit 1
OUT=/tmp/wrap_xvfb
mkdir -p "$OUT"
GODOT="$HOME/.local/bin/godot"

run_tscn() {  # name tscn-path
	local name="$1" tscn="$2"
	timeout 1200 xvfb-run -a "$GODOT" --rendering-driver opengl3 --path . "$tscn" > "$OUT/$name.log" 2>&1
	echo "$name rc=$?"
}
run_tool() {  # name tool-script
	local name="$1" script="$2"
	timeout 1200 "$script" > "$OUT/$name.log" 2>&1
	echo "$name rc=$?"
}

run_tscn  boot            res://tests/scenes/test_boot.tscn
run_tool  bot             tools/test_bot.sh
run_tool  bot_creature    tools/test_bot_creature.sh
run_tool  bot_tribe       tools/test_bot_tribe.sh
run_tool  editor_click    tools/test_editor_click.sh
run_tool  menu            tools/test_menu.sh
run_tool  visual          tools/test_visual.sh
run_tool  visual_creature tools/test_visual_creature.sh
run_tool  visual_suite    tools/test_visual_suite.sh
run_tool  creature_scene  tools/test_creature_scene.sh
run_tool  tribe_scene     tools/test_tribe_scene.sh
run_tool  civ_scene       tools/test_civ_scene.sh
run_tool  perf            tools/test_perf.sh
run_tool  perf_creature   tools/test_perf_creature.sh
run_tool  perf_tribe      tools/test_perf_tribe.sh
run_tool  perf_civ        tools/test_perf_civ.sh
run_tool  bot_civ         tools/test_bot_civ.sh
echo "SWEEP_DONE"
