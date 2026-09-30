# Perf probe — the §6 budget: 200 entities @ 60fps (Compatibility renderer).
# Boots the REAL game (menu.start_new_game(seed), the T6 trap pattern), then
# force-spawns EXACTLY 200 ents (mix of sizes, cycled across the live roster)
# near the player via the sim's spawn_ent test seam with direct placement —
# maintain_population's visible-per-species caps would never reach that budget
# on its own. Then steps 600 ticks under xvfb (llvmpipe rendering ON — worst
# case) and asserts:
#   1. average wall-clock per PURE SIM STEP ≤ 8 ms (the tick budget) — the
#      timed window is `step_for_testing` ONLY. T10 review minor 4: the
#      window used to wrap `step_for_testing` AND `_do_render`, so a
#      draw-path change could fail the "sim" gate; the metrics are split
#      now and the render pass is RECORDED, never asserted,
#   2. no NaN drift — the bot's assert_sane invariants every 60 ticks.
# The stage render pass (_do_render) and the full engine-frame wall-clock
# (sim + draw + the real llvmpipe rasterization) are RECORDED
# informationally — see the note in _report().
# Placement is a fixed-seed LCG (area-uniform ≤ 320 around the player, the
# debug_spawn_near pattern) so every run spreads the ents identically.
#
# Run (xvfb, rendering on — llvmpipe is the worst-case rasterizer):
#   tools/test_perf.sh
#   xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 --path . \
#       res://tests/scenes/test_perf.tscn
# Prints PERF_OK <stats> and exits 0; failures print PERF_FAIL on stderr, exit 1.
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")

const SEED := 0x9E37
const DT := 1.0 / 60.0
const TRANSITION_POLL := 300
const CARD_STEPS := 180
const TARGET_ENTS := 200
const TICKS := 600
const TICK_BUDGET_MS := 8.0
const SIZE_MIX := [0.6, 0.85, 1.1, 1.35, 1.6, 1.9, 2.2]
const TIMEOUT_FRAMES := 7200

var _phase := "build"
var _frames := 0
var _game: Variant = null
var _driver: Variant = null
var _ticks_done := 0
var _sim_us := 0.0
var _sim_max_us := 0.0
var _ren_us := 0.0
var _ren_max_us := 0.0
var _wall_us := 0.0
var _wall_max_us := 0.0
var _frame_end_us := 0
var _done := false


func _ready() -> void:
	_driver = BotDriverScript.new()


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	if _done:
		return
	match _phase:
		"build":
			_game = _build_game()
			_phase = "prologue"
		"prologue":
			if not _prologue():
				return
			_phase = "spawn"
		"spawn":
			_spawn_budget()
			_frame_end_us = Time.get_ticks_usec()
			_phase = "measure"
		"measure":
			_measure()
		"done":
			pass


# ---- helpers (the T6 trap pattern, verbatim) -----------------------------------

## Boot → menu → new game → transition → card-slot (bot.test.ts:55-73).
func _prologue() -> bool:
	_game.step_for_testing(5)
	if _game.context.stage != "menu":
		_fail("prologue: expected menu after 5 steps, got %s" % str(_game.context.stage))
		return false
	var menu: Variant = _game.current
	menu.start_new_game(0, "normal", SEED)
	var steps := 0
	while _game.context.stage != "cell" and steps < TRANSITION_POLL:
		_game.step_for_testing(1, DT)
		steps += 1
	if _game.context.stage != "cell":
		_fail("prologue: cell stage not reached within %d steps" % TRANSITION_POLL)
		return false
	_game.step_for_testing(CARD_STEPS, DT)
	return true


## Force-spawn up to exactly TARGET_ENTS ents hugging the player: direct
## spawn_ent placement (the test seam — maintain_population caps visible ents
## per species at min(9, pop·0.6) and would never reach the budget alone).
## Species cycled across the live non-kin roster, size mixed across the table
## (genome_override), position area-uniform ≤ 320 (debug_spawn_near's shape)
## from a FIXED-seed LCG so every run spreads them identically.
func _spawn_budget() -> void:
	var sim: Variant = _game.current.sim
	var pool: Array = []
	for sp in sim.eco.living():
		if not bool(sp.get("kin", false)):
			pool.append(sp)
	if pool.is_empty():
		_fail("spawn: no non-kin species in the roster")
		return
	var lcg := 0x51EF
	var px: float = sim.px
	var py: float = sim.py
	var spawned := 0
	while int(sim.ents.size()) < TARGET_ENTS:
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var a := float(lcg) / float(0x7fffffff) * TAU
		lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
		var d := sqrt(float(lcg) / float(0x7fffffff)) * 320.0
		var i: int = spawned % pool.size()
		var g: Dictionary = pool[i]["genome"].duplicate()
		g["size"] = SIZE_MIX[spawned % SIZE_MIX.size()]
		sim.spawn_ent(pool[i], px + cos(a) * d, py + sin(a) * d, g)
		spawned += 1
		if spawned > TARGET_ENTS * 2:
			_fail("spawn: population did not take (spawned %d, ents %d)"
					% [spawned, sim.ents.size()])
			return
	var viol: PackedStringArray = _driver.assert_sane(_game)
	if not viol.is_empty():
		_fail("post-spawn assert_sane: %s" % str(viol))
		return
	print("PERF_SPAWN ents=%d" % int(sim.ents.size()))


## One sim tick per engine frame. The TIMED METRICS ARE SPLIT (T10 review
## minor 4): the PURE sim step (step_for_testing — carries the asserted 8 ms
## tick budget, render-free by construction) and the stage render pass
## (_do_render — the draw-path cost, recorded only so a draw-path change can
## never fail the sim gate). The frame's WALL window (previous frame end →
## this frame end) still carries sim + draw + the real llvmpipe
## rasterization, recorded informationally.
func _measure() -> void:
	var sim: Variant = _game.current.sim
	var u0 := Time.get_ticks_usec()
	_game.step_for_testing(1, DT)
	var u1 := Time.get_ticks_usec()
	_game._do_render(0.0)
	var u2 := Time.get_ticks_usec()
	_sim_us += float(u1 - u0)
	_sim_max_us = maxf(_sim_max_us, float(u1 - u0))
	_ren_us += float(u2 - u1)
	_ren_max_us = maxf(_ren_max_us, float(u2 - u1))
	_ticks_done += 1
	if _ticks_done % 60 == 0:
		var viol: PackedStringArray = _driver.assert_sane(_game)
		if not viol.is_empty():
			_fail("assert_sane at tick %d: %s" % [_ticks_done, str(viol)])
			return
	if _ticks_done >= TICKS:
		var now := Time.get_ticks_usec()
		_wall_us += float(now - _frame_end_us)
		_frame_end_us = now
		_report()
		return
	# the wall window CLOSES at the next frame's end — the current draw pass
	# must land inside it, so accumulate only here (one window per frame)
	var now := Time.get_ticks_usec()
	_wall_us += float(now - _frame_end_us)
	_wall_max_us = maxf(_wall_max_us, float(now - _frame_end_us))
	_frame_end_us = now


func _report() -> void:
	var sim: Variant = _game.current.sim
	var avg_tick_ms := _sim_us / float(_ticks_done) / 1000.0
	var max_tick_ms := _sim_max_us / 1000.0
	var avg_ren_ms := _ren_us / float(_ticks_done) / 1000.0
	var max_ren_ms := _ren_max_us / 1000.0
	var avg_frame_ms := _wall_us / float(_ticks_done) / 1000.0
	var max_frame_ms := _wall_max_us / 1000.0
	var viol: PackedStringArray = _driver.assert_sane(_game)
	if not viol.is_empty():
		_fail("final assert_sane: %s" % str(viol))
		return
	print("PERF_NUM ticks=%d ents=%d pellets=%d dna=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f"
			% [_ticks_done, int(sim.ents.size()), int(sim.pellets.size()),
			int(_game.context.dna), avg_tick_ms, max_tick_ms, avg_ren_ms,
			max_ren_ms, avg_frame_ms, max_frame_ms])
	# render_avg_ms and frame_avg_ms are recorded informationally only: under
	# llvmpipe the draw pass of ~200 on-screen procedural cells dominates the
	# frame and no GDScript-side change moves it — the §6 "200 ents @ 60fps"
	# budget targets a mid machine's real GPU, not the software rasterizer the
	# probe intentionally runs on. The asserted budget is the PURE sim tick
	# (≤ 8 ms, render-free window) plus the NaN-drift sweep.
	if avg_tick_ms > TICK_BUDGET_MS:
		_fail("tick budget: avg %.3f ms > %.1f ms over %d ticks (max %.3f)"
				% [avg_tick_ms, TICK_BUDGET_MS, _ticks_done, max_tick_ms])
		return
	print("PERF_OK ticks=%d ents=%d pellets=%d dna=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f"
			% [_ticks_done, int(sim.ents.size()), int(sim.pellets.size()),
			int(_game.context.dna), avg_tick_ms, max_tick_ms, avg_ren_ms,
			max_ren_ms, avg_frame_ms, max_frame_ms])
	_phase = "done"
	_done = true
	get_tree().quit(0)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	# Manual stepping ONLY (the bot-arc pattern): set_process must come AFTER
	# tree entry, and the loop's is_active_cb kills tick() even if a future
	# refactor re-enables processing — the probe alone drives the sim clock.
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.start()
	return game


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("PERF_FAIL: " + msg)
	get_tree().quit(1)
