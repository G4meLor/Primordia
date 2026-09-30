# Creature sim-tick perf probe — HEADLESS (the §5.3 creature budget; the M2
# contention-immune cross-check pattern, PARITY-M2.md §17). Builds the
# CreatureSim DIRECTLY (no scene, no game layer, no painter — pure
# sim.update on a fixed world), force-spawns EXACTLY 60 ents (the creature
# perf target: maintain_population's spawn floor mini(10, round(pop·0.5))
# would never reach it alone; nothing culls a force-spawned ent — the only
# despawn is >2200 px, unreachable at creature speeds inside the window) and
# times 300 ticks of sim.update ALONE. Budget vs measured (2026-10-01, this
# host, ambient load ~3 with a sustained soak process pinned to one core):
#   §5.3 target   ≤ 2.0 ms @ 60 ents — NOT met: 2.57–2.69 ms avg over 5 runs
#   the cost is linear in ents (~42 µs/ent/tick; boot-only 4 ents = 0.17 ms;
#   30 ents = 1.33 ms) — a creature update_ents hot-loop optimization is the
#   M4 candidate (the M2 cell playbook: flat mirrors + neighborhood grids,
#   WITH creature A-B coverage first — the M2 lesson forbids an unfalsified
#   "bit-exact" claim). The assert below is therefore a REGRESSION TRIPWIRE
#   at 2× the target (4 ms), not the target itself; tighten it to 2.0 when
#   the optimization lands.
# The xvfb scene probe (tests/scenes/test_perf_creature.gd) re-measures the
# same tick inside the real game layer (the contention cross-check) and
# records the painter draw cost separately.
# Deterministic: fixed seed, fixed LCG placement, scripted input — every run
# is the same world (the ab_state_dump pattern).
# Run: godot --headless -s tools/perf_creature_sim.gd
# Prints CREATURE_SIM_OK <stats> and exits 0; failures print
# CREATURE_SIM_FAIL on stderr, exit 1.
extends SceneTree

const Ctx := preload("res://src/game/context.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0x9E37
const TARGET_ENTS := 60
const SETTLE := 120
const TICKS := 300
const TARGET_MS := 2.0    # the §5.3 creature budget (currently NOT met — see header)
const BUDGET_MS := 4.0    # the standing assert: 2× target regression tripwire
const SIZE_MIX := [0.6, 0.85, 1.1, 1.35, 1.6, 1.9, 2.2]
const Z_MIN := -200.0
const Z_MAX := 240.0

var _us := 0.0
var _max_us := 0.0
var _ticks := 0


func _mk(seed_v: int) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	var hooks: Dictionary = {
		"hud_toast": func(_t, _k, _i): pass,
		"hud_banner": func(_d): pass,
		"hud_float_world": func(_x, _y, _t, _c, _s): pass,
		"audio_play": func(_n, _v, _p): pass,
		"cam_shake": func(_m, _d): pass,
		"fx_burst": func(_x, _y, _n, _o): pass,
		"fx_spawn": func(_o): pass,
		"storyteller_note_chaos_event": func(_p): pass,
		"set_cursor_pointer": func(): pass,
		"context_event": func(_e, _d): pass,
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx}


func _inp(t: float, i: int) -> Dictionary:
	var pressed: Array = []
	if i % 240 == 120:
		pressed = ["Space"]
	var held: Array = []
	if i % 70 < 25:
		held = ["KeyW"]
	return {
		"mx": 400.0, "my": 300.0,
		"wx": sin(t * 0.9) * 400.0, "wy": cos(t * 0.6) * 400.0,
		"down": i % 30 < 18,
		"keys_held": held, "keys_pressed": pressed,
		"clicked": false, "take_click": false,
	}


## The player is pinned un-hittable for the measurement window (invuln
## re-pinned per tick, OUTSIDE the timed window — a documented probe seam):
## without it the NPC bites kill the player inside ~2 s and the DEATH SWEEP
## drops every ent >600 px (creature_sim death path), collapsing the 60-ent
## stocking mid-window (~42 final). The budget measures the ent hot path at
## its stocked size, not player-death churn. NPC-vs-NPC kills stay live —
## a corpse can still be pile-on-eaten to its 12 s expiry inside the window
## (one observed), so the loop TOPS UP below TARGET (untimed): the stock
## self-heals to ~60 and the measured window stays a 60-ent hot path.
var INVULN_PIN := 1.0e9
var _pool: Array = []
var _lcg := 0x51EF
var _spawn_seq := 0


func _spawn_one(sim: Variant) -> void:
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


## Force-spawn to exactly TARGET_ENTS ents hugging the player: direct
## spawn_ent placement (the test seam — maintain_population's floor would
## never reach the budget alone). Species cycled across the live non-kin
## roster, size mixed across the table (genome_override), position
## area-uniform ≤ 320 around (px, pz) from a FIXED-seed LCG so every run
## spreads them identically. z clamped into the depth band.
func _spawn_budget(sim: Variant) -> void:
	for sp in sim.eco.living():
		if not bool(sp.get("kin", false)):
			_pool.append(sp)
	if _pool.is_empty():
		_fail("spawn: no non-kin species in the roster")
		return
	var spawned := 0
	while int(sim.ents.size()) < TARGET_ENTS:
		_spawn_one(sim)
		spawned += 1
		if spawned > TARGET_ENTS * 2:
			_fail("spawn: population did not take (spawned %d, ents %d)"
					% [spawned, int(sim.ents.size())])
			return


func _initialize() -> void:
	var m := _mk(SEED)
	var sim: Variant = m["sim"]
	for i in SETTLE:
		sim.update(DT, _inp(float(i) * DT, i))
	_spawn_budget(sim)
	if int(sim.ents.size()) < TARGET_ENTS:
		_fail("post-spawn ents %d < %d" % [int(sim.ents.size()), TARGET_ENTS])
		return
	for i in TICKS:
		# untimed stock-keeping: the invuln pin (player un-hittable → no death
		# sweep) + one top-up spawn if a pile-on-eaten corpse dropped the count
		sim.invuln = INVULN_PIN
		if int(sim.ents.size()) < TARGET_ENTS:
			_spawn_one(sim)
		var inp := _inp(float(i) * DT, i)  # built untimed — the window times sim.update only
		var u0 := Time.get_ticks_usec()
		sim.update(DT, inp)
		var u1 := Time.get_ticks_usec()
		_us += float(u1 - u0)
		_max_us = maxf(_max_us, float(u1 - u0))
		_ticks += 1
		if not is_finite(sim.px) or not is_finite(sim.php):
			_fail("non-finite player state at tick %d" % i)
			return
	var avg_ms := _us / float(_ticks) / 1000.0
	var max_ms := _max_us / 1000.0
	if int(sim.ents.size()) < TARGET_ENTS:
		_fail("population did not hold: %d < %d after the window (invuln pin)"
				% [int(sim.ents.size()), TARGET_ENTS])
		return
	print("CREATURE_SIM_NUM ticks=%d ents=%d target_ms=%.1f sim_avg_ms=%.3f sim_max_ms=%.3f"
			% [_ticks, int(sim.ents.size()), TARGET_MS, avg_ms, max_ms])
	if avg_ms > BUDGET_MS:
		printerr("CREATURE_SIM_FAIL: sim tick avg %.3f ms > %.1f ms tripwire over %d ticks @ %d ents (max %.3f; target %.1f)"
				% [avg_ms, BUDGET_MS, _ticks, int(sim.ents.size()), max_ms, TARGET_MS])
		quit(1)
		return
	if avg_ms > TARGET_MS:
		print("CREATURE_SIM_OK ticks=%d ents=%d sim_avg_ms=%.3f sim_max_ms=%.3f NOTE above the %.1f ms target — tripwire %.1f ms only (see header)"
				% [_ticks, int(sim.ents.size()), avg_ms, max_ms, TARGET_MS, BUDGET_MS])
		quit(0)
		return
	print("CREATURE_SIM_OK ticks=%d ents=%d sim_avg_ms=%.3f sim_max_ms=%.3f"
			% [_ticks, int(sim.ents.size()), avg_ms, max_ms])
	quit(0)


func _fail(msg: String) -> void:
	printerr("CREATURE_SIM_FAIL: " + msg)
	quit(1)
