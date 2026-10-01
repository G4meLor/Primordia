# Tribe perf probe — the §5.4 tribe budgets under the REAL game (xvfb,
# llvmpipe rendering ON — worst case; the contention cross-check to the
# headless tools/perf_tribe_sim.gd, which times the SAME 60-tribesman + 6
# warrior world with no game layer at all). Boots the real Game into the
# tribe stage directly (the test_creature_scene pattern: register +
# switch_stage), force-stocks EXACTLY 60 tribesmen (the founding 3 topped up
# through the public add_tribesman seam — roles cycled gather/hunt ONLY, so
# the fight-first AI cannot converge the roster onto the war party; the
# stocking seams are the headless probe's, documented there) + 6 rival
# warriors (launch-shaped dicts, one parked 36 px from each of 6 huts —
# sieging for the whole window) and steps 300 ticks. The TIMED METRICS ARE
# SPLIT (the T10 review minor 4 lesson, applied to tribe from day one):
#   sim_avg_ms    — the pure sim tick (step_for_testing(1): the stage update
#                   incl. sim.update + the camera/fx scene halves).
#                   RECORDED ONLY here: under llvmpipe the rasterizer process
#                   contends with the timed window — the ASSERTED sim budget
#                   lives in the contention-immune headless probe
#                   (tools/perf_tribe_sim.gd, the M2/M3 lesson),
#   render_avg_ms — the stage render() pass (the pooled creature-item sync +
#                   hudRects re-registration + canvas queues — the
#                   GDScript-side render-prep cost the game controls; the
#                   deferred canvas _draw lands in the frame window) —
#                   ASSERTED ≤ 4 ms (the M3 painter-side budget shape,
#                   tribe's own row),
#   frame_avg_ms  — the full engine-frame wall window (previous frame's
#                   measure → this one: sim + render prep + the deferred
#                   _draw + the real llvmpipe rasterization) — recorded
#                   only: rasterization dominates (66 procedural creatures +
#                   the ground pass) and no GDScript change moves it — the
#                   budget targets a real GPU, not the software rasterizer
#                   (the M2 rig caveat: llvmpipe is the worst case).
# The chief is pinned un-killable for the window (invulnT re-pinned per
# tick, untimed — the documented probe seam): the starting hut's siege
# warrior stands within the 40 px raid-touch ring of the idle chief.
# Deterministic: fixed seed, fixed fixture placement — every run is the same
# world.
# Run: tools/test_perf_tribe.sh
# Prints PERF_TRIBE_OK <stats> and exits 0; failures print PERF_TRIBE_FAIL
# on stderr, exit 1.
extends Node

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const BotDriverScript := preload("res://tests/bots/bot_driver.gd")

const SEED := 0x7E37
const DT := 1.0 / 60.0
const SETTLE := 60
const TARGET_TRIBE := 60
const TARGET_WARRIORS := 6
const TICKS := 300
const PAINTER_BUDGET_MS := 4.0  # the render-prep budget (the M3 painter-side shape)
const ROLES := ["gather", "hunt"]
# the headless probe's hut anchors + siege park offsets (one war-party member
# 36 px from each hut — inside the 40 siege ring, TribeStage.ts:683)
const EXTRA_HUTS := [
	[250.0, 40.0], [-250.0, 40.0], [250.0, 160.0],
	[-250.0, 160.0], [0.0, 220.0],
]
const SIEGE_OFFSET := [30.0, -20.0]
const TIMEOUT_FRAMES := 7200
const INVULN_PIN := 1.0e9

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
			_phase = "settle"
		"settle":
			if not _settle():
				return
			_phase = "spawn"
		"spawn":
			_stock()
			_frame_end_us = Time.get_ticks_usec()
			_phase = "measure"
		"measure":
			_measure()
		"done":
			pass


## Real Game → tribe stage directly (the test_creature_scene pattern:
## register + switch_stage; on_enter founds the minimum-3 pack roster).
## Manual stepping ONLY (the T6 trap pattern): set_process after tree entry,
## the loop's is_active_cb kills tick() — the probe alone drives the clock.
func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(TribeStageScript.new(game))
	game.switch_stage("tribe")
	return game


func _settle() -> bool:
	if not _stage_ok():
		return false
	_game.step_for_testing(SETTLE, DT)
	return true


func _stage_ok() -> bool:
	if _game.context.stage != "tribe":
		_fail("settle: tribe stage not reached (got %s)" % str(_game.context.stage))
		return false
	return true


## Force-stock the §5.4 target (the headless probe's seams verbatim): 60
## tribesmen (the 3 founders topped up via add_tribesman), 6 huts with one
## sieging warrior each, chaos silenced (gap 1e9 — the econ-probe seam).
func _stock() -> void:
	var sim: Variant = _game.current.sim
	sim.chaos.gap = 1.0e9
	while int(sim.tribe.size()) < TARGET_TRIBE:
		sim.add_tribesman(GenomeScript.clone_genome(_game.context.genome),
				ROLES[int(sim.tribe.size()) % ROLES.size()])
	for h in EXTRA_HUTS:
		sim.huts.append({"x": h[0], "z": h[1], "hp": 100.0, "maxHp": 100.0,
				"pop": 0.0, "buildT": 0.0})
	for h in sim.huts:
		_stock_warrior(sim, float(h["x"]), float(h["z"]))
	if int(sim.tribe.size()) != TARGET_TRIBE \
			or int(sim.rivalWarriors.size()) != TARGET_WARRIORS:
		_fail("stock did not land (tribe %d, warriors %d)"
				% [int(sim.tribe.size()), int(sim.rivalWarriors.size())])
		return
	var viol: PackedStringArray = _driver.assert_sane(_game)
	if not viol.is_empty():
		_fail("post-stock assert_sane: %s" % str(viol))
		return
	print("PERF_TRIBE_SPAWN tribe=%d warriors=%d huts=%d"
			% [int(sim.tribe.size()), int(sim.rivalWarriors.size()), int(sim.huts.size())])


func _stock_warrior(sim: Variant, hx: float, hz: float) -> void:
	var g: Dictionary = GenomeScript.clone_genome(_game.context.genome)
	g["hue"] = 5.0
	g["diet"] = "carnivore"
	g["spikes"] = 3.0
	g["jaw"] = 3.0
	sim.rivalWarriors.append({
		"x": hx + SIEGE_OFFSET[0], "z": hz + SIEGE_OFFSET[1],
		"vx": 0.0, "vz": 0.0,
		"hp": 60.0,
		"genome": g,
		"gait": 0.0,
		"facing": 1,
		"state": "march",
	})


## One sim tick per engine frame; the timed metrics are SPLIT (see header):
## the pure sim tick is recorded (the asserted tripwire lives headless), the
## stage render pass carries the ASSERTED painter-side budget, and the full
## wall window (previous frame end → this frame end — sim + render prep +
## the deferred _draw + the real llvmpipe rasterization) is recorded only.
func _measure() -> void:
	var sim: Variant = _game.current.sim
	# untimed stock-keeping (the headless probe's seam): chief un-killable →
	# no raid-touch death churn; top up if a wander-by fight thinned a roster
	sim.invulnT = INVULN_PIN
	while int(sim.tribe.size()) < TARGET_TRIBE:
		sim.add_tribesman(GenomeScript.clone_genome(_game.context.genome),
				ROLES[int(sim.tribe.size()) % ROLES.size()])
	while int(sim.rivalWarriors.size()) < TARGET_WARRIORS:
		_stock_warrior(sim, float(sim.huts[int(sim.rivalWarriors.size())]["x"]),
				float(sim.huts[int(sim.rivalWarriors.size())]["z"]))
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
	# the wall window CLOSES at the next frame's end — the deferred draw pass
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
	if int(sim.tribe.size()) < TARGET_TRIBE \
			or int(sim.rivalWarriors.size()) < TARGET_WARRIORS:
		_fail("stocking did not hold (tribe %d, warriors %d)"
				% [int(sim.tribe.size()), int(sim.rivalWarriors.size())])
		return
	print("PERF_TRIBE_NUM ticks=%d tribe=%d warriors=%d huts=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f"
			% [_ticks_done, int(sim.tribe.size()), int(sim.rivalWarriors.size()),
			int(sim.huts.size()), avg_tick_ms, max_tick_ms,
			avg_ren_ms, max_ren_ms, avg_frame_ms, max_frame_ms])
	# render_avg_ms is the ASSERTED budget (the stage render() pass — pooled
	# item sync + rect re-registration + queues, the GDScript-side render-prep
	# cost the game controls; the deferred canvas _draw + llvmpipe
	# rasterization land in the frame window). frame_avg_ms is recorded
	# informationally only: under llvmpipe the rasterization of 66 procedural
	# creatures + the ground pass dominates and no GDScript-side change moves
	# it — that budget targets a real GPU (the M2 rig-caveat precedent). The
	# sim tick is recorded here and ASSERTED in the headless probe
	# (contention-immune).
	if avg_ren_ms > PAINTER_BUDGET_MS:
		_fail("render-prep budget: render avg %.3f ms > %.1f ms over %d ticks @ %d tribesmen + %d warriors (max %.3f)"
				% [avg_ren_ms, PAINTER_BUDGET_MS, _ticks_done,
				int(sim.tribe.size()), int(sim.rivalWarriors.size()), max_ren_ms])
		return
	print("PERF_TRIBE_OK ticks=%d tribe=%d warriors=%d sim_avg_ms=%.3f sim_max_ms=%.3f render_avg_ms=%.3f render_max_ms=%.3f frame_avg_ms=%.3f frame_max_ms=%.3f painter_budget_ms=%.1f"
			% [_ticks_done, int(sim.tribe.size()), int(sim.rivalWarriors.size()),
			avg_tick_ms, max_tick_ms, avg_ren_ms, max_ren_ms,
			avg_frame_ms, max_frame_ms, PAINTER_BUDGET_MS])
	_phase = "done"
	_done = true
	get_tree().quit(0)


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("PERF_TRIBE_FAIL: " + msg)
	get_tree().quit(1)
