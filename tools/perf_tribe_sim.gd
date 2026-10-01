# Tribe sim-tick perf probe — HEADLESS (the §5.4 tribe budget row; the M3
# contention-immune pattern, PARITY-M3.md §16). Builds the TribeSim DIRECTLY
# (no scene, no game layer, no painter — pure sim.update on a fixed world),
# force-stocks EXACTLY 60 tribesmen + 6 rival warriors (the §5.4 perf target
# stocking) and times 300 ticks of sim.update ALONE.
#
# Stocking (documented probe seams, the creature-probe shape):
#   - 60 tribesmen via the public add_tribesman seam, roles cycled
#     gather/hunt ONLY — no warrior-role tribesmen, so the fight-first AI
#     cannot converge the roster onto the war party and shred it (the
#     fight-DEATH churn is not the hot path under test; the FIGHT SCAN still
#     runs every tick — 6 warriors × 60 tribesmen distance checks). Deaths
#     from wander-by encounters stay live; the loop TOPS UP below target
#     (untimed), the M2/M3 self-healing-stock precedent.
#   - 6 rival warriors as launch-shaped dicts (the launch_rival_raid body
#     verbatim: genome clone + hue 5/carnivore/spikes 3/jaw 3, hp 60, march),
#     one parked 36 px from each of 6 huts (the starting hut + 5
#     fixture-appended) so every warrior SIEGES for the whole window —
#     −6/s + the economy's +5/s repair ≈ −1/s per hut: no destruction, no
#     flee churn, the siege hot path held at stocked size.
#   - the chief is pinned un-killable (invulnT re-pinned per tick, untimed —
#     the creature-probe seam): raid-touch deaths cannot fire mid-window.
#   - chaos silenced (gap 1e9 — the econ-probe seam): the deck's storms/
#     beasts would add uncontrolled work spikes; the deck itself is pinned
#     by test_tribe_events.gd.
# Deterministic: fixed seed, fixed fixture placement, scripted input — every
# run is the same world (the ab_state_dump pattern).
#
# Budget vs measured (2026-10-01, this host, ambient load ~3 — the M4 wrap
# runs): the §5.4 tribe target ≤ 2.0 ms @ 60 tribesmen + 6 rival warriors is
# MET: ~0.71–1.00 ms avg over 5 runs (max spikes 2.6–20 ms under ambient
# load) — the tribe job-AI hot path is far cheaper per-agent than the
# creature update_ents loop (no eco tick, no IK; the M3 2 ms lesson's target
# shape carries unchanged). The standing assert is the 2× regression tripwire
# (4 ms); tighten it only with a deliberate budget re-ruling, not silently.
# The xvfb scene probe (tests/scenes/test_perf_tribe.gd) re-measures the
# same tick inside the real game layer (the contention cross-check) and
# asserts the stage render-prep pass ≤ 4 ms.
# Run: godot --headless -s tools/perf_tribe_sim.gd
# Prints TRIBE_SIM_OK <stats> and exits 0; failures print TRIBE_SIM_FAIL on
# stderr, exit 1.
extends SceneTree

const Ctx := preload("res://src/game/context.gd")
const TribeSim := preload("res://src/game/tribe/tribe_sim.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const DT := 1.0 / 60.0
const SEED := 0x7E37
const TARGET_TRIBE := 60
const TARGET_WARRIORS := 6
const SETTLE := 60
const TICKS := 300
const TARGET_MS := 2.0    # the §5.4 tribe budget — met (see header)
const BUDGET_MS := 4.0    # the standing assert: 2× target regression tripwire
const ROLES := ["gather", "hunt"]

# 6 hut anchors (the starting hut + 5 fixture huts) and the matching war-party
# park offsets — each warrior lands 36 px from its hut (inside the 40 siege
# ring, TribeStage.ts:683).
const EXTRA_HUTS := [
	[250.0, 40.0], [-250.0, 40.0], [250.0, 160.0],
	[-250.0, 160.0], [0.0, 220.0],
]
const SIEGE_OFFSET := [30.0, -20.0]

var _us := 0.0
var _max_us := 0.0
var _ticks := 0


func _mk(seed_v: int) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	# hooks {} — every _fire key missing = silent no-op (the sim's contract);
	# the storyteller reads fall back to their neutral defaults (tribe_sim
	# update_chaos: gap 1.0 / mood "test" / warnScale 1.0).
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = TribeSim.new(ctx, rng, {})
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


func _stock_warrior(sim: Variant, hx: float, hz: float) -> void:
	var g: Dictionary = GenomeScript.clone_genome(sim.ctx.genome)
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


## Force-stock the §5.4 target: 60 tribesmen (add_tribesman — the public
## seam) + 6 huts with one sieging war party member each. Placement is FIXED
## (no rng — the warriors' park points are constants; the tribesmen ride
## add_tribesman's own seeded draws around the origin).
func _stock(sim: Variant) -> void:
	for i in TARGET_TRIBE:
		sim.add_tribesman(GenomeScript.clone_genome(sim.ctx.genome), ROLES[i % ROLES.size()])
	for h in EXTRA_HUTS:
		sim.huts.append({"x": h[0], "z": h[1], "hp": 100.0, "maxHp": 100.0,
				"pop": 0.0, "buildT": 0.0})
	for h in sim.huts:
		_stock_warrior(sim, float(h["x"]), float(h["z"]))


func _initialize() -> void:
	var m := _mk(SEED)
	var sim: Variant = m["sim"]
	_silence_chaos(sim)
	for i in SETTLE:
		sim.update(DT, _inp(float(i) * DT, i))
	_stock(sim)
	if int(sim.tribe.size()) != TARGET_TRIBE or int(sim.rivalWarriors.size()) != TARGET_WARRIORS:
		_fail("stock did not land (tribe %d, warriors %d)"
				% [int(sim.tribe.size()), int(sim.rivalWarriors.size())])
		return
	for i in TICKS:
		# untimed stock-keeping: the invuln pin (chief un-killable) + one
		# top-up per roster if a wander-by fight thinned it
		sim.invulnT = 1.0e9
		while int(sim.tribe.size()) < TARGET_TRIBE:
			sim.add_tribesman(GenomeScript.clone_genome(sim.ctx.genome),
					ROLES[int(sim.tribe.size()) % ROLES.size()])
		while int(sim.rivalWarriors.size()) < TARGET_WARRIORS:
			_stock_warrior(sim, float(sim.huts[int(sim.rivalWarriors.size())]["x"]),
					float(sim.huts[int(sim.rivalWarriors.size())]["z"]))
		var inp := _inp(float(i) * DT, i)  # built untimed — the window times sim.update only
		var u0 := Time.get_ticks_usec()
		sim.update(DT, inp)
		var u1 := Time.get_ticks_usec()
		_us += float(u1 - u0)
		_max_us = maxf(_max_us, float(u1 - u0))
		_ticks += 1
		if not is_finite(sim.px) or not is_finite(sim.pz) \
				or not is_finite(sim.food) or not is_finite(sim.wood):
			_fail("non-finite state at tick %d" % i)
			return
	var avg_ms := _us / float(_ticks) / 1000.0
	var max_ms := _max_us / 1000.0
	if int(sim.tribe.size()) < TARGET_TRIBE or int(sim.rivalWarriors.size()) < TARGET_WARRIORS \
			or int(sim.huts.size()) < 1 + EXTRA_HUTS.size():
		_fail("stocking did not hold (tribe %d, warriors %d, huts %d)"
				% [int(sim.tribe.size()), int(sim.rivalWarriors.size()), int(sim.huts.size())])
		return
	print("TRIBE_SIM_NUM ticks=%d tribe=%d warriors=%d huts=%d target_ms=%.1f sim_avg_ms=%.3f sim_max_ms=%.3f"
			% [_ticks, int(sim.tribe.size()), int(sim.rivalWarriors.size()),
			int(sim.huts.size()), TARGET_MS, avg_ms, max_ms])
	if avg_ms > BUDGET_MS:
		printerr("TRIBE_SIM_FAIL: sim tick avg %.3f ms > %.1f ms tripwire over %d ticks @ %d tribesmen + %d warriors (max %.3f; target %.1f)"
				% [avg_ms, BUDGET_MS, _ticks, int(sim.tribe.size()),
				int(sim.rivalWarriors.size()), max_ms, TARGET_MS])
		quit(1)
		return
	if avg_ms > TARGET_MS:
		print("TRIBE_SIM_OK ticks=%d tribe=%d warriors=%d sim_avg_ms=%.3f sim_max_ms=%.3f NOTE above the %.1f ms target — tripwire %.1f ms only (see header)"
				% [_ticks, int(sim.tribe.size()), int(sim.rivalWarriors.size()),
				avg_ms, max_ms, TARGET_MS, BUDGET_MS])
		quit(0)
		return
	print("TRIBE_SIM_OK ticks=%d tribe=%d warriors=%d sim_avg_ms=%.3f sim_max_ms=%.3f"
			% [_ticks, int(sim.tribe.size()), int(sim.rivalWarriors.size()), avg_ms, max_ms])
	quit(0)


func _silence_chaos(sim: Variant) -> void:
	sim.chaos.gap = 1.0e9


func _fail(msg: String) -> void:
	printerr("TRIBE_SIM_FAIL: " + msg)
	quit(1)
