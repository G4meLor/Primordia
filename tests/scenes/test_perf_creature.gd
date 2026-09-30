# Creature perf probe — the §5.3 creature budgets under the REAL game (xvfb,
# llvmpipe rendering ON — worst case; the contention cross-check to the
# headless tools/perf_creature_sim.gd, which times the SAME 60-ent world with
# no game layer at all). Boots the real Game into the creature stage directly
# (the test_creature_scene pattern: register + switch_stage), force-spawns
# EXACTLY 60 ents (mixed sizes, cycled across the live non-kin roster,
# area-uniform ≤ 320 around the player from a fixed-seed LCG — direct
# spawn_ent placement, maintain_population's floor would never reach it) and
# steps 300 ticks. The TIMED METRICS ARE SPLIT (the T10 review minor 4
# lesson, applied to creature from day one):
#   sim_avg_ms    — the PURE sim step (step_for_testing), render-free window.
#                   RECORDED ONLY here: under llvmpipe the rasterizer process
#                   contends with the timed window (measured ~5.4 ms vs the
#                   2.5 ms headless cross-check) — the ASSERTED sim budget
#                   lives in the contention-immune headless probe
#                   (tools/perf_creature_sim.gd, the M2 lesson),
#   render_avg_ms — the stage render pass (_do_render: the painter's RS
#                   command build for 61 creatures) — ASSERTED ≤ 4 ms (the
#                   §5.3 painter draw budget; the GDScript-side cost the game
#                   controls),
#   frame_avg_ms  — the full engine-frame wall window (sim + draw + the real
#                   llvmpipe rasterization) — recorded only: rasterization
#                   dominates (~300+ ms at this stocking) and no GDScript
#                   change moves it — the §5.3 "≤ 4 ms" FRAME budget targets
#                   a real GPU, not the software rasterizer (the M2 rig
#                   caveat: llvmpipe is the worst case, real GPUs faster).
# The player is pinned un-hittable for the window (invuln re-pinned per tick,
# untimed — the documented probe seam from the headless probe): without it
# the NPC bites kill the player inside ~2 s and the death sweep drops the
# 60-ent stocking (~42 final).
# Deterministic: fixed seed, fixed LCG placement — every run is the same
# world.
# Run: tools/test_perf_creature.sh
# Prints PERF_CREATURE_OK <stats> and exits 0; failures print
# PERF_CREATURE_FAIL on stderr, exit 1.
extends Node

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")

const SEED := 0x9E37
const DT := 1.0 / 60.0
const SETTLE := 60
const TARGET_ENTS := 60
const TICKS := 300
const PAINTER_BUDGET_MS := 4.0  # the §5.3 painter draw budget (RS command build)
const SIZE_MIX := [0.6, 0.85, 1.1, 1.35, 1.6, 1.9, 2.2]
const Z_MIN := -200.0
const Z_MAX := 240.0
const TIMEOUT_FRAMES := 7200
const INVULN_PIN := 1.0e9

var _phase := "build"
var _frames := 0
var _game: Variant = null
var _driver: Variant = null
var _pool: Array = []
var _lcg := 0x51EF
var _spawn_seq := 0
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
			_phase = "settle"
		"settle":
			if not _settle():
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


## Real Game → creature stage directly (the test_creature_scene pattern:
## register + switch_stage; the cell leg adds nothing to the creature tick).
## Manual stepping ONLY (the T6 trap pattern): set_process after tree entry,
## the loop's is_active_cb kills tick() — the probe alone drives the clock.
func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(CreatureStageScript.new(game))
	game.switch_stage("creature")
	return game


func _settle() -> bool:
	if _game.context.stage != "creature":
		_fail("settle: creature stage not reached (got %s)" % str(_game.context.stage))
		return false
	_game.step_for_testing(SETTLE, DT)
	return true


## Force-spawn to exactly TARGET_ENTS ents hugging the player (the headless
## probe's placement verbatim: species cycled across the live non-kin roster,
## size mixed across the table, area-uniform ≤ 320 around (px, pz), z clamped
## into the depth band, fixed-seed LCG).
func _spawn_budget() -> void:
	var sim: Variant = _game.current.sim
	for sp in sim.eco.living():
		if not bool(sp.get("kin", false)):
			_pool.append(sp)
	if _pool.is_empty():
		_fail("spawn: no non-kin species in the roster")
		return
	var spawned := 0
	while int(sim.ents.size()) < TARGET_ENTS:
		_spawn_one()
		spawned += 1
		if spawned > TARGET_ENTS * 2:
			_fail("spawn: population did not take (spawned %d, ents %d)"
					% [spawned, int(sim.ents.size())])
			return
	var viol: PackedStringArray = _driver.assert_sane(_game)
	if not viol.is_empty():
		_fail("post-spawn assert_sane: %s" % str(viol))
		return
	print("PERF_CREATURE_SPAWN ents=%d" % int(sim.ents.size()))


func _spawn_one() -> void:
	var sim: Variant = _game.current.sim
	_lcg = (_lcg * 1103515245 + 12345) & 0x7fffffff
	var a := float(_lcg) / float(0x7fffffff) * TAU
	_lcg = (_lcg * 1103515245 + 12345) & 0x7fffffff
	var d := sqrt(float(_lcg) / float(0x7fffffff)) * 320.0
	var i: int = _spawn_seq % _pool.size()
	var g: Dictionary = _pool[i]["genome"].duplicate()
	g["size"] = SIZE_MIX[_spawn_seq % SIZE_MIX.size()]
	_spawn_seq += 1
	sim.spawn_ent(_pool[i], sim.px + cos(a) * d,
			clampf(sim.pz + sin(a) * d, Z_MIN, Z_MAX), g)


## One sim tick per engine frame; the timed metrics are SPLIT (see header):
## the pure sim step carries the asserted tripwire, the stage render pass and
## the full wall window (previous frame end → this frame end — sim + draw +
## the real llvmpipe rasterization) are recorded only.
func _measure() -> void:
	var sim: Variant = _game.current.sim
	# untimed stock-keeping (the headless probe's seam): player un-hittable →
	# no death sweep; top up if a pile-on-eaten corpse dropped the count
	sim.invuln = INVULN_PIN
	if int(sim.ents.size()) < TARGET_ENTS:
		_spawn_one()
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
	print("PERF_CREATURE_NUM ticks=%d ents=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f"
			% [_ticks_done, int(sim.ents.size()), avg_tick_ms, max_tick_ms,
			avg_ren_ms, max_ren_ms, avg_frame_ms, max_frame_ms])
	# render_avg_ms and frame_avg_ms relationships: the ASSERTED budget is the
	# painter's draw pass (render_avg ≤ 4 ms — the §5.3 painter budget, the
	# GDScript-side cost the game controls). frame_avg_ms is recorded
	# informationally only: under llvmpipe the rasterization of 61 procedural
	# creatures dominates the frame window and no GDScript-side change moves
	# it — that budget targets a real GPU, not the software rasterizer the
	# probe intentionally runs on (the M2 rig-caveat precedent). The sim step
	# is recorded here and ASSERTED in the headless probe (contention-immune).
	if avg_ren_ms > PAINTER_BUDGET_MS:
		_fail("painter draw budget: render avg %.3f ms > %.1f ms over %d ticks @ %d ents + player (max %.3f)"
				% [avg_ren_ms, PAINTER_BUDGET_MS, _ticks_done,
				int(sim.ents.size()), max_ren_ms])
		return
	print("PERF_CREATURE_OK ticks=%d ents=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f painter_budget_ms=%.1f"
			% [_ticks_done, int(sim.ents.size()), avg_tick_ms, max_tick_ms,
			avg_ren_ms, max_ren_ms, avg_frame_ms, max_frame_ms,
			PAINTER_BUDGET_MS])
	_phase = "done"
	_done = true
	get_tree().quit(0)


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("PERF_CREATURE_FAIL: " + msg)
	get_tree().quit(1)
