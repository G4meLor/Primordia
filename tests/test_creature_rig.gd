## Creature rig math vs TS pins — Spore src/gfx/creature.ts (frozen), M3 task 1.
## TS reference: `npx vitest run --config tools/vitest.config.ts
## tools/print-rig-values.test.ts` in ~/Desktop/RD/Spore (throwaway printer,
## output copied 2026-09-30; JSON.stringify literals = exact f64).
## eps classes (ARCHITECTURE.md §3): 1e-9 for the pure-float rig outputs
## (Dictionary/Array Variants hold f64) and the f64 IK core; solve_ik's Vector2
## return round-trips float32 storage → 1e-5 there (ulp 1.9e-6 at |knee| ≈ 20).
extends "res://tests/test_base.gd"

const Rig := preload("res://src/gfx/creature_rig.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

# pinned fixture: genome (size 1.2, legs 4, tail true) at pose
# (speed .6, gaitPhase 1.3, attack .25, airborne .15, scale 1) and t = 3.7


func _genome(legs: int, tail: bool) -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.2
	g["legs"] = legs
	g["tail"] = tail
	return g


func _pose(gait := 1.3) -> Dictionary:
	return {
		"x": 100.0, "y": 300.0, "facing": 1, "speed": 0.6, "gaitPhase": gait,
		"attack": 0.25, "hurt": 0.0, "eat": 0.0, "airborne": 0.15,
		"mood": "idle", "scale": 1.0
	}


func _pose_with(over: Dictionary) -> Dictionary:
	var p := _pose()
	p.merge(over, true)
	return p


func test_solve_ik_ts_pins() -> void:
	# Vector2 return = float32 storage (eps class, see header); the f64 core
	# pins at 1e-9 in test_ik_core_ts_pins below.
	var k: Vector2 = Rig.solve_ik(0.0, 0.0, 30.0, 0.0, 20.0, 15.0, 1.0)
	approx(k.x, 17.916666666666668, "ik straight bend+ kx", 1e-5)
	approx(k.y, 8.887803753208972, "ik straight bend+ ky", 1e-5)
	k = Rig.solve_ik(0.0, 0.0, 30.0, 0.0, 20.0, 15.0, -1.0)
	approx(k.x, 17.916666666666668, "ik straight bend- kx unchanged", 1e-5)
	approx(k.y, -8.887803753208972, "ik straight bend- mirrors ky", 1e-5)
	k = Rig.solve_ik(0.0, 0.0, 100.0, 0.0, 20.0, 15.0, 1.0)
	approx(k.x, 19.995714489854244, "ik over-reach clamps d to l1+l2-0.01 (kx)", 1e-5)
	approx(k.y, 0.41400729490316157, "ik over-reach ky", 1e-5)
	k = Rig.solve_ik(0.0, 0.0, 1.0, 0.0, 20.0, 15.0, 1.0)
	approx(k.x, 3.9860418882793294, "ik folded floors d at |l1-l2|+0.01 (kx)", 1e-5)
	approx(k.y, 0.21831526323070713, "ik folded ky", 1e-5)
	k = Rig.solve_ik(0.0, 0.0, 34.99, 0.0, 20.0, 15.0, -1.0)
	approx(k.x, 19.995714489854244, "ik exactly-at-reach kx (no clamp)", 1e-5)
	approx(k.y, -0.41400729490316157, "ik exactly-at-reach ky", 1e-5)
	k = Rig.solve_ik(2.0, 3.0, -20.0, 14.0, 18.0, 22.0, -1.0)
	approx(k.x, 0.868566285917896, "ik diagonal kx", 1e-5)
	approx(k.y, 20.96440529910852, "ik diagonal ky", 1e-5)


func test_ik_core_ts_pins() -> void:
	# the f64 core leg_draws rides — full double precision vs TS (eps 1e-9)
	var k: PackedFloat64Array = Rig._ik_f64(0.0, 0.0, 24.0, 0.0, 15.0, 15.0, 1.0)
	# hand-checked: d = 24, a = (576+225-225)/48 = 12, h = sqrt(225-144) = 9
	approx(k[0], 12.0, "ik hand case kx (l1=l2, a=d/2)", 1e-9)
	approx(k[1], 9.0, "ik hand case ky", 1e-9)
	k = Rig._ik_f64(0.0, 0.0, 30.0, 0.0, 20.0, 15.0, 1.0)
	approx(k[0], 17.916666666666668, "core straight kx", 1e-9)
	approx(k[1], 8.887803753208972, "core straight ky", 1e-9)
	k = Rig._ik_f64(0.0, 0.0, 100.0, 0.0, 20.0, 15.0, 1.0)
	approx(k[0], 19.995714489854244, "core over-reach kx", 1e-9)
	approx(k[1], 0.41400729490316157, "core over-reach ky", 1e-9)
	k = Rig._ik_f64(0.0, 0.0, 1.0, 0.0, 20.0, 15.0, 1.0)
	approx(k[0], 3.9860418882793294, "core folded kx", 1e-9)
	approx(k[1], 0.21831526323070713, "core folded ky", 1e-9)
	k = Rig._ik_f64(2.0, 3.0, -20.0, 14.0, 18.0, 22.0, -1.0)
	approx(k[0], 0.868566285917896, "core diagonal kx", 1e-9)
	approx(k[1], 20.96440529910852, "core diagonal ky", 1e-9)


func test_spine_points_ts_pins() -> void:
	var spine: Array = Rig.spine_points(_genome(4, true), _pose(), 3.7)
	eq(spine.size(), 6, "spine has SEG=6 points")
	var sx := [-20.16, -10.559999999999999, -0.9599999999999982, 8.64, 18.240000000000002, 29.640000000000004]
	var sy := [-41.77840511699695, -42.1579784675746, -42.92305356519064, -43.9658065933527, -45.1590496532535, -45.48497652042332]
	var sr := [10.112500673566204, 14.194379279697678, 16.14773339111363, 15.428522739615467, 12.237058960172801, 7.46221560641667]
	for i in 6:
		approx(spine[i]["x"], sx[i], "spine[%d].x" % i, 1e-9)
		approx(spine[i]["y"], sy[i], "spine[%d].y (bodyY+bob+swim+neck+lunge)" % i, 1e-9)
		approx(spine[i]["r"], sr[i], "spine[%d].r (profile radius)" % i, 1e-9)


func test_spine_profile_u0_half_1() -> void:
	# profile = sin(π·min(1, u·0.85+0.12)) at the brief's u = 0 / 0.5 / 1;
	# the min() never clamps on the u grid (u=1 → 0.97 < 1)
	approx(Rig._spine_profile(0.0), 0.3681245526846779, "profile u=0 (sin(π·0.12))", 1e-9)
	approx(Rig._spine_profile(0.5), 0.9900236577165576, "profile u=0.5 (sin(π·0.545))", 1e-9)
	approx(Rig._spine_profile(1.0), 0.09410831331851435, "profile u=1 (sin(π·0.97))", 1e-9)


func test_head_lunge_offset() -> void:
	var lunged: Array = Rig.spine_points(_genome(4, true), _pose(), 3.7)
	var still: Array = Rig.spine_points(_genome(4, true), _pose_with({"attack": 0.0}), 3.7)
	# attack .25 · 6·size = 1.8 on x, .25 · 3·size = 0.9 on y — head only
	approx(lunged[5]["x"] - still[5]["x"], 1.8, "head lunge dx", 1e-9)
	approx(lunged[5]["y"] - still[5]["y"], 0.9, "head lunge dy", 1e-9)
	approx(still[5]["x"], 27.840000000000003, "unlunged head x", 1e-9)
	approx(still[5]["y"], -46.384976520423315, "unlunged head y", 1e-9)
	for i in 5:
		eq(lunged[i], still[i], "lunge touches the head only (i=%d)" % i)


func test_spine_legless_body_y() -> void:
	var with_legs: Array = Rig.spine_points(_genome(4, true), _pose(), 3.7)
	var legless: Array = Rig.spine_points(_genome(0, false), _pose(), 3.7)
	# legH (20+4·1.5)·1.2 = 31.2 vs the 5·size = 6 branch → every y drops 25.2
	for i in 6:
		approx(legless[i]["y"] - with_legs[i]["y"], 25.2, "legless bodyY drops 25.2 (i=%d)" % i, 1e-9)
	approx(legless[0]["y"], -16.578405116996947, "legs=0 spine[0].y pin", 1e-9)
	approx(legless[5]["y"], -20.28497652042332, "legs=0 spine[5].y pin", 1e-9)
	eq(Rig.leg_draws(_genome(0, false), _pose(), 3.7), [], "legs=0 → no leg draws")


func test_leg_h_branches() -> void:
	# (20 + min(legs,6)·1.5)·size, 5·size when legs = 0 (TS:54)
	approx(Rig._leg_h(0, 1.2), 6.0, "legH legs=0 → 5·size", 1e-9)
	approx(Rig._leg_h(1, 1.2), 25.8, "legH legs=1", 1e-9)
	approx(Rig._leg_h(4, 1.2), 31.2, "legH legs=4", 1e-9)
	approx(Rig._leg_h(6, 1.2), 34.8, "legH legs=6 (clamp edge)", 1e-9)
	approx(Rig._leg_h(8, 1.2), 34.8, "legH legs=8 clamped to 6", 1e-9)


func test_leg_draws_ts_pins() -> void:
	var legs: Array = Rig.leg_draws(_genome(4, true), _pose(), 3.7)
	eq(legs.size(), 4, "4 leg draws")
	var hx := [-17.759999999999998, -3.359999999999998, 11.04, 25.44]
	var hy := [-35.77050779171064, -35.65657353918951, -37.022971360525744, -39.652373121175735]
	var kx := [-27.330738974218423, -7.728129775537754, 12.426215740152566, 31.33413809092018]
	var ky := [-20.412572660731072, -18.09568921453033, -18.980143923514845, -22.543184006399905]
	var fx := [-18.08581433763505, -7.83418566236495, 3.214300921775152, 38.065699078224846]
	var fy := [-4.856333254502653, 0.0, -3.404334429977799, 0.0]
	for i in 4:
		approx(legs[i]["hx"], hx[i], "leg %d hip x" % i, 1e-9)
		approx(legs[i]["hy"], hy[i], "leg %d hip y" % i, 1e-9)
		approx(legs[i]["kx"], kx[i], "leg %d knee x (bend)" % i, 1e-9)
		approx(legs[i]["ky"], ky[i], "leg %d knee y" % i, 1e-9)
		approx(legs[i]["fx"], fx[i], "leg %d foot x (stride)" % i, 1e-9)
		approx(legs[i]["fy"], fy[i], "leg %d foot y (lift)" % i, 1e-9)
	# bend u<0.45 → 1 else −1: legs 0/1 hind (knee forward of hip: kx < hx),
	# legs 2/3 front (elbow back: kx > hx) — visible in the pinned knees
	ok(legs[0]["kx"] < legs[0]["hx"], "hind knee forward (leg 0)")
	ok(legs[3]["kx"] > legs[3]["hx"], "front elbow back (leg 3)")


func test_gait_phase_parity() -> void:
	# the gait cycle is exactly 2π-periodic: same feet at phase 0 and 2π
	var g0: Array = Rig.leg_draws(_genome(4, true), _pose(0.0), 3.7)
	var g2pi: Array = Rig.leg_draws(_genome(4, true), _pose(2.0 * PI), 3.7)
	eq(g0.size(), 4, "gait 0: 4 legs")
	eq(g2pi.size(), 4, "gait 2π: 4 legs")
	for i in 4:
		for f in ["fx", "fy", "kx", "ky"]:
			approx(g2pi[i][f], g0[i][f], "gait 2π ≡ 0 (leg %d %s)" % [i, f], 1e-9)
	# phase π mirrors each leg's stride around its rest x (cos(φ+π) = −cos φ);
	# restX = hipX + (u−0.5)·6·size recomputed here from the pinned hips
	var gpi: Array = Rig.leg_draws(_genome(4, true), _pose(PI), 3.7)
	var rest0: float = gpi[0]["hx"] + (0.0 - 0.5) * 6.0 * 1.2
	approx(gpi[0]["fx"], 2.0 * rest0 - g0[0]["fx"], "phase π mirrors leg 0 stride", 1e-9)
	var rest1: float = gpi[1]["hx"] + (1.0 / 3.0 - 0.5) * 6.0 * 1.2
	approx(gpi[1]["fx"], 2.0 * rest1 - g0[1]["fx"], "phase π mirrors leg 1 stride", 1e-9)
	# TS pins at phase 0 — lift zero on the planted pair, stride split ±12.24·…
	approx(g0[0]["fx"], -9.120000000000001, "gait 0 leg 0 fx", 1e-9)
	approx(g0[0]["fy"], 0.0, "gait 0 leg 0 fy (sin 0 → no lift)", 1e-9)
	approx(g0[1]["fy"], -6.17221986770266e-16, "gait 0 leg 1 fy (sin(π) float noise)", 1e-9)
	approx(gpi[0]["fx"], -33.599999999999994, "gait π leg 0 fx pin", 1e-9)
	approx(gpi[3]["fy"], -4.4916850947096325, "gait π leg 3 fy pin", 1e-9)


func test_leg_draws_single_leg() -> void:
	var one: Array = Rig.leg_draws(_genome(1, false), _pose(), 3.7)
	eq(one.size(), 1, "single leg")
	# u = 0.5 special case (TS:159): attach spine[1+round(1.5)] = spine[3],
	# bend −1 (u < 0.45 false)
	approx(one[0]["hx"], 8.64, "legs=1 hip x (attach spine[3], u−0.5 = 0)", 1e-9)
	approx(one[0]["hy"], -31.62297136052574, "legs=1 hip y", 1e-9)
	approx(one[0]["kx"], 16.71967970805333, "legs=1 knee x (bend −1)", 1e-9)
	approx(one[0]["ky"], -19.027731314569046, "legs=1 knee y", 1e-9)
	approx(one[0]["fx"], 11.91418566236495, "legs=1 foot x", 1e-9)
	approx(one[0]["fy"], -4.856333254502653, "legs=1 foot y", 1e-9)


func test_tail_points_ts_pins() -> void:
	var tail: Array = Rig.tail_points(_genome(4, true), _pose(), 3.7)
	eq(tail.size(), 5, "5 tail segments")
	var tx := [-33.326945655150446, -40.040083445820365, -45.77307759365126, -50.5758769785602, -55.363824510610215]
	var ty := [-42.497874203229614, -44.05946350943422, -46.672928664422365, -49.891363455527284, -53.11775478872309]
	var tr := [7.8, 6.552, 5.303999999999999, 4.056, 2.808]
	for k in 5:
		approx(tail[k]["x"], tx[k], "tail %d x (ang drift walk)" % k, 1e-9)
		approx(tail[k]["y"], ty[k], "tail %d y (0.6·segLen vertical squash)" % k, 1e-9)
		approx(tail[k]["r"], tr[k], "tail %d r (bodyR·(0.5−k·0.08) decay)" % k, 1e-9)


func test_tail_absent_when_gene_off() -> void:
	eq(Rig.tail_points(_genome(4, false), _pose(), 3.7), [], "tail gene off → no tail points")
