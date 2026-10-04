# Task 8 space probes — the §5.4 space-parity criteria through the REAL stage:
# each probe boots the full Game + the real SpaceStage (out-of-tree, the
# M4/M5 test_probe_civ boot shape) on a pinned seed and drives the REAL sim
# through its documented input-SNAPSHOT contract (space_sim.update), with
# observations pinned to the TS-verbatim formulas (each probe's provenance
# comment cites the frozen TS line; the probe IS the pin — divergence =
# documented here + in the report).
#
# Complement (what the unit suite already pins): tests/test_space_sim.gd pins
# every mechanism at UNIT level (single frames, gate ladders, replay helpers).
# THESE probes add the FORMULA-AT-SCALE derivations: multi-cycle/multi-frame
# accumulations composed probe-side with the identical TS ops (the colony
# logistic trajectory over 330 frames, the pirate 120-frame chase recursion,
# the black-hole pull integration, the compound death curve), real-scheduler
# timelines through the REAL update loop (the tribute raid), 24-merge
# cloned-stream draw chains, and closed-form world-trait effects observed
# through REAL planet ecos (the eco.mods wire).
#
# Probes (task-8 brief AC + TS SpaceStage.ts):
#   diet dial      — herbPull/carnPull closed-form for two crafted worlds
#                    (herb-heavy 3.0 → 0.9/0.0; carn-heavy → 0.0/0.9,
#                    TS:147-148) + the FULL constructor draw chain replayed on
#                    a parallel branch at seed 0x5CAC1: every roster species'
#                    diet must match the replay built FROM those pull values;
#                    the dial's flips OBSERVED in the derived data (including
#                    the volcanic carnivore→herbivore flip-back, TS:157-158);
#                    titan/swarm appended AFTER the roster, their diet/size
#                    untouched by the dial (TS:161-177)
#   abduct ledger  — the pay curve at scale through the REAL beam path: five
#                    catches derived catch-by-catch from the cloned-stream
#                    rng.pick (10 first / 3 repeat per '{planet}:{species}'
#                    key, TS:684-689), pops tracked to any derived extinction
#                    (bump_extinction counted HERE, TS:690-697); the pop-1
#                    deterministic last-member leg + no re-farm; the same
#                    genome on a second planet pays 10 again (a fresh key)
#   colony brake   — the logistic recurrence composed over 330 frames across
#                    four drive phases (normal DT, ff-hold ×26, the
#                    POST-RELEASE ×26 frame — the TS:306 pre-read quirk
#                    observed in the growth itself — and the 200-frame brake
#                    soak), every checkpoint bit-exact; the cap-120 brake
#                    exact: the soak asymptotes UNDER 120, never crossing
#                    (TS:370-372)
#   ff + eco.mods  — generations += dt·ts/30 composed over the ff window
#                    (TS:323); the eco.mods WIRE observed through a REAL
#                    planet eco: growth_mult 1.5 vs traitless at the same
#                    seed — each sim's eco must match a probe-controlled twin
#                    eco bit-exact per table, and the two tables must DIVERGE
#                    (the trait is real through the wire, TS:309-315)
#   crossover opts — 24-merge chains on cloned streams: wild (0.15/0.3) vs
#                    normal (0.10/0.2) vs rate_add 0.5 — every child
#                    bit-exact, the anomaly/defect fire COUNTS derived from
#                    the replays match the real toasts (TS:744-755)
#   graft          — the never-downgrade skip inside a REAL splice chain: the
#                    first merge's shuffle visit order derived from the clone
#                    (the cannot-raise lineage passed, the giver grafts), the
#                    SECOND merge draws NO shuffle (the once-per-run flag,
#                    TS:778-788) — the whole two-merge stream replayed
#   pirate math    — the chase recursion composed over 120 frames at DT:
#                    accel 300 toward the ship while d > 30, drag
#                    exp(−1.4dt), position integration, the −14dt damage
#                    window with its chance(dt·6) burst draws replayed —
#                    bit-exact at every checkpoint (TS:466-481); the click
#                    kill: 34×5 → dead +30 DNA with both bursts' draws
#                    replayed (TS:482-497)
#   black hole     — the pull 24000/max(80,d) integrated over 20 frames from
#                    d 500 (the ship's own drag exp(−1.1dt) composed into the
#                    recursion) and the d-79 CLAMP leg (24000/80) — bit-exact
#                    (TS:438-443); death-by-hole → the killer CULLED at the
#                    respawn (radius 700 strict >, the chain-kill guard,
#                    TS:584-597)
#   ship death     — the compound −15% curve: four deaths from 1000 DNA with
#                    the round() steps derived (150/128/108/92), the cargo
#                    surviving each; the post-ending twin bills 0 four times
#                    (TS:584-602)
#   tribute raid   — through the REAL update loop with a single-def tribute
#                    deck: warn → demand 60 → the UNPAID end spawns 3 pirates
#                    IN the real frame (the ctx onEnd, TS:539-547), then the
#                    first chase frame derived for all three (TS:454-473)
#   sun + regen    — the two windows COMPOSED on one hull curve: the ship
#                    inside the sun window AND a thriving colony's regen
#                    window — the invuln crossover derived (regen has NO
#                    invuln gate: +8dt while shielded, −22dt net after), 240
#                    frames bit-exact (TS:376-389)
#   finale + fade  — three colonies grown through the REAL ff to the trigger
#                    (thriving ≥ 3, the trigger frame derived from the growth
#                    recurrence, TS:552-559); the core approach → endingDone;
#                    the ending fade windows composed at the SIM's own
#                    timeline — the probe's formula min(1, endingT/2) in /
#                    max(0, 1−(endingT−dismissT)/1.5) out vs the stage's
#                    static seam at the real endingT/dismissT values
#                    (TS:576-581 + the :1083-1122 alpha)
#   resurvey       — the cadence at scale: cd 4 armed per re-survey, the
#                    decay max(0, cd−dt) replayed at the 0.5 s grain — the
#                    pay fires land EXACTLY every 4.0 s (8 half-second
#                    frames), +3 DNA per cycle composed over 3 cycles with
#                    the gated-scan toasts counted (TS:1244-1259)
#
# Method notes: the chaos scheduler is either silenced (gap 1e9 — it never
# reaches a fire, the M4/M5 precedent) or substituted (the tribute raid's
# single-def deck); the stage stream carries ONLY the draws the probe's own
# drive makes. Probe fixture writes go straight at sim fields (the M3/M4
# precedent, each commented at its site). Draw-dependent pins replay the TS
# draw chain on a CLONED stream (Rng.new_from(sim.rng.state()) — the
# derivation never calls the sim's own code); the eco-mods twin replays at
# the ECO level (the twin eco is probe-constructed and probe-modded — the
# wire under test is the sim's assignment, not the eco valves). Seeds
# 0x5CAC1-0x5CACD.
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const RngLib := preload("res://src/core/rng.gd")
const ChaosLib := preload("res://src/game/chaos.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const MutationLib := preload("res://src/evo/mutation.gd")
const NamesLib := preload("res://src/evo/names.gd")
const PartsLib := preload("res://src/evo/parts.gd")
const WorldGenomeLib := preload("res://src/evo/world_genome.gd")
const SpaceEventsLib := preload("res://src/game/space/space_events.gd")

const DT := 1.0 / 60.0
const KINDS: Array = ["lush", "ocean", "volcanic", "barren", "lush", "barren"]  # TS:105


# ---- scenario scaffold ---------------------------------------------------------

## Real boot: Game + the REAL space stage, out-of-tree (run.gd drives tests
## synchronously inside _initialize — the main loop never reaches a frame, so
## tree-entered nodes never fire _ready; the stage's _ready is invoked ONCE
## manually, the M2-M5 probe shape). switch_stage fires the real on_enter
## (the fresh constructor system — no blob — + the objective). world_over
## merges into ctx.world BEFORE the stage constructs (the crafted-trait seam
## — the unit suite's shape).
func _boot(seed_v: int, world_over: Dictionary = {}) -> Dictionary:
	var ctx: Variant = ContextScript.new(seed_v)
	for k in world_over:
		ctx.world[k] = world_over[k]
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(SpaceStageScript.new(game))
	game.stages["space"]._ready()
	game.switch_stage("space")
	return {"game": game, "sim": game.current.sim, "ctx": ctx, "stage": game.current}


func _drop(m: Dictionary) -> void:
	# break the overlay Callable cycles before free (the test_game_flow pattern)
	var game: Variant = m["game"]
	game.hud = {}
	game.editor = {}
	game.pause = {}
	game.free()


## Eventless world for clean accounting: the chaos scheduler's natural path
## never reaches a fire (gap 1e9), so the stage stream carries ONLY the draws
## the probe's own drive makes.
func _silence_chaos(sim: Variant) -> void:
	sim.chaos.gap = 1.0e9


## Idle input snapshot — the sim's documented contract shape (space reads
## keys_held + wx/wy/down + mx/my + clicked; the probe fills only what it
## drives).
func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


## A probe Rng cloned from the sim's stream state — replaying the TS draw
## order on it derives expected outcomes without calling the sim (the
## independent derivations; the test_space_sim _probe shape).
func _probe_rng(sim: Variant) -> Variant:
	return RngLib.new_from(sim.rng.state())


## Scan the REAL hud's toast list for `fragment`, then clear the list: the
## out-of-tree hud's toast age never advances (hud.update is never driven),
## so the 1.5 s identical-repeat rate-limit would swallow every repeat
## forever, and the 6-deep list evicts — scan-per-step counts every fire
## exactly once (the M4 war-graves precedent).
func _scan_toasts(m: Dictionary, fragment: String) -> int:
	var n := 0
	for t in m["stage"].hud_inst._toasts:
		if String(t["text"]).find(fragment) >= 0:
			n += 1
	m["stage"].hud_inst._toasts.clear()
	return n


## Drain the hud toast list without counting (keeps the 6-deep list from
## evicting between counted scans).
func _drain_toasts(m: Dictionary) -> void:
	m["stage"].hud_inst._toasts.clear()


## Find a banner by title (cur OR queue — concurrent banners queue headless,
## the ttl never advancing): returns the banner dict or null.
func _find_banner(m: Dictionary, title: String) -> Variant:
	var hud: Variant = m["stage"].hud_inst
	if hud._cur_banner != null and String(hud._cur_banner["title"]) == title:
		return hud._cur_banner
	for b in hud._banner_queue:
		if String(b["title"]) == title:
			return b
	return null


## Fixture write (the M4 precedent — probe rigs go straight at sim fields):
## park planet i at (x, y) with radius r and FREEZE its orbit (orbitSpeed 0).
func _place_planet(sim: Variant, i: int, x: float, y: float, r: float = 50.0) -> Dictionary:
	var p: Dictionary = sim.planets[i]
	p["angle"] = atan2(y, x)
	p["orbitR"] = sqrt(x * x + y * y)
	p["orbitSpeed"] = 0.0
	p["r"] = r
	p["x"] = x
	p["y"] = y
	return p


## Push every planet except `keep` out to orbit 5000 so nearest_planet is
## unambiguous (the unit suite's shape).
func _isolate_planet(sim: Variant, keep: int) -> void:
	for i in 6:
		if i != keep:
			sim.planets[i]["orbitR"] = 5000.0
			sim.planets[i]["orbitSpeed"] = 0.0


## Craft a hermetic eco on planet i: species with the given pops riding
## CLONED default genomes (each distinguished by one int gene so the species
## identities stay distinct). `kin` freezes the pops (kin lines skip the eco
## dynamics — hand-driven), so ledger derivations are exact. The eco rides
## its own fixed rng — the STAGE stream stays untouched (only rng.pick in
## finishAbduct draws from the stage stream).
func _craft_eco(sim: Variant, i: int, pops: Array, kin := true) -> Variant:
	var eco: Variant = EcoScript.new(RngLib.new_from(4242 + i))
	var genes: Array = ["jaw", "spikes", "toxin", "flagella"]
	for j in pops.size():
		var g: Dictionary = GenomeLib.clone_genome(GenomeLib.default_genome())
		g[genes[j % 4]] = 2 + j
		eco.add_species(g, float(pops[j]), {"kin": kin})
	sim.planets[i]["eco"] = eco
	return eco


# ---- probes --------------------------------------------------------------------

## Pin provenance: the diet dial TS:138-158 verbatim —
##   herbW = weights.herbivore ?? 1; carnW = (carnivore ?? 1)·(predator ?? 1)
##   herbPull = min(0.9, max(0, herbW−1)·0.5 + max(0, 1−carnW)·0.5)   (TS:147)
##   carnPull = min(0.9, max(0, carnW−1)·0.5 + max(0, 1−herbW)·0.5)   (TS:148)
## one flip chance per roster species with the JS &&/else-if short-circuit
## (TS:157-158 — a volcanic carnivore CAN flip back); the bonus species
## appended AFTER the roster so the dial never touches them (TS:161-177).
## Seed 0x5CAC1, TWO boots (the same seed, two crafted worlds): the
## closed-form pull values feed the probe's own constructor replay (a
## parallel branch of a fresh same-seed context) and the sim's every roster
## diet must match it. Complement: test_space_sim pins the mechanism at SEED
## with one crafted world + its replay helper; THIS probe derives BOTH
## extreme worlds' pull values closed-form, counts the DIAL-caused flips in
## the derived data (the volcanic flip-back included), and re-pins the bonus
## ordering under a live dial.
func test_diet_dial_pulls_closed_form_and_bonus_ordering() -> void:
	var herb_world: Dictionary = {"traits": [{"effects": [
		{"kind": "ecoSeed", "archetype": "herbivore", "weight": 3.0},
		{"kind": "ecoSeed", "archetype": "titan", "weight": 1.0},
		{"kind": "ecoSeed", "archetype": "swarm", "weight": 1.0},
	]}]}
	var carn_world: Dictionary = {"traits": [{"effects": [
		{"kind": "ecoSeed", "archetype": "carnivore", "weight": 3.0},
		{"kind": "ecoSeed", "archetype": "predator", "weight": 1.0},
	]}]}
	# the closed-form pulls, derived here from the TS formulas — never from
	# the sim's code
	var herb_pull_a: float = minf(0.9, maxf(0.0, 3.0 - 1.0) * 0.5 + maxf(0.0, 1.0 - 1.0) * 0.5)
	var carn_pull_a: float = minf(0.9, maxf(0.0, 1.0 - 1.0) * 0.5 + maxf(0.0, 1.0 - 3.0) * 0.5)
	approx(herb_pull_a, 0.9, "world A herbPull = min(0.9, (3−1)·0.5 + max(0,1−1)·0.5) = 0.9 (TS:147)")
	approx(carn_pull_a, 0.0, "world A carnPull = min(0.9, 0 + max(0,1−3)·0.5) = 0 (TS:148)")
	var herb_pull_b: float = minf(0.9, maxf(0.0, 1.0 - 1.0) * 0.5 + maxf(0.0, 1.0 - 3.0) * 0.5)
	var carn_pull_b: float = minf(0.9, maxf(0.0, 3.0 - 1.0) * 0.5 + maxf(0.0, 1.0 - 1.0) * 0.5)
	approx(herb_pull_b, 0.0, "world B herbPull = 0 (TS:147)")
	approx(carn_pull_b, 0.9, "world B carnPull = min(0.9, (3−1)·0.5 + 0) = 0.9 (TS:148)")

	# the probe's own constructor replay (a parallel branch of a fresh
	# same-seed context): the chaos-branch draw FIRST (TS:98), then
	# generateSystem + makePlanetEco in TS draw order. Returns per planet the
	# derived roster diets + the count of DIAL-caused flips (a chance that
	# actually fired — mutate's own diet rolls don't count).
	var replay_diets := func(seed_v: int, world: Dictionary, hpull: float, cpull: float) -> Dictionary:
		var pr: Variant = ContextScript.new(seed_v).rng.branch()
		pr.branch()  # TS:98 — the chaos scheduler's second branch draw
		var out: Array = []
		var dial_flips := 0
		for i in 6:
			var kind: String = KINDS[i]
			pr.range(-60.0, 60.0)  # TS:108 orbitR
			NamesLib.species_name(pr)  # TS:112 name
			pr.range(0.0, TAU)  # TS:114 angle
			pr.range(0.008, 0.02)  # TS:115 orbitSpeed (sign/divide are pure)
			pr.range(0.0, 34.0)  # TS:116 r (the +46 base and lush +10 are pure)
			if kind == "lush":
				pr.range(90.0, 140.0)  # TS:117
			elif kind == "ocean":
				pr.range(190.0, 220.0)  # TS:118
			elif kind == "volcanic":
				pr.range(5.0, 30.0)  # TS:119
			else:
				pr.range(30.0, 60.0)  # TS:120
			pr.chance(0.25)  # TS:122 ring
			if kind == "barren":
				out.append([])
				continue
			pr.branch()  # TS:135 — the eco's own branch (its draws ride the child)
			var weights: Dictionary = WorldGenomeLib.archetype_weights(world)
			var n: int = pr.int(2, 4)  # TS:149
			var diets: Array = []
			for k in n:
				var base: Dictionary = GenomeLib.clone_genome(GenomeLib.default_genome())
				var arch: Dictionary = MutationLib.mutate(base, pr, 0.9)  # TS:152
				pr.range(0.7, 1.9)  # TS:153 size
				pr.range(-40.0, 40.0)  # TS:154 hue
				if kind == "volcanic":  # TS:155 — forced carnivore (pure)
					arch["diet"] = "carnivore"
				if kind == "ocean":  # TS:156 (pure)
					arch["flagella"] = maxi(3, int(arch["flagella"]))
				# exactly ONE chance draw per species (TS:157-158)
				if String(arch["diet"]) == "herbivore":
					if pr.chance(cpull):
						arch["diet"] = "carnivore"
						dial_flips += 1
				elif pr.chance(hpull):
					arch["diet"] = "herbivore"
					dial_flips += 1
				diets.append(String(arch["diet"]))
				pr.range(4.0, 10.0)  # TS:159 pop
			# the bonus species ride the same streams; their diet is FORCED —
			# the dial never touches them (TS:161-177)
			if float(weights.get("titan", 0.0)) >= 1.0:
				MutationLib.mutate(GenomeLib.clone_genome(GenomeLib.default_genome()), pr, 0.9)
				pr.range(4.0, 10.0)
				diets.append("carnivore")
			if float(weights.get("swarm", 0.0)) >= 1.0:
				MutationLib.mutate(GenomeLib.clone_genome(GenomeLib.default_genome()), pr, 0.9)
				pr.range(4.0, 10.0)
				diets.append("herbivore")
			out.append(diets)
		return {"diets": out, "flips": dial_flips}

	# world A: herb-heavy (titan + swarm along for the ordering pin)
	var ma := _boot(0x5CAC1, herb_world)
	var sim_a: Variant = ma["sim"]
	_silence_chaos(sim_a)
	var rep_a: Dictionary = replay_diets.call(0x5CAC1, ma["ctx"].world, herb_pull_a, carn_pull_a)
	var exp_a: Array = rep_a["diets"]
	for i in 6:
		if KINDS[i] == "barren":
			eq(sim_a.planets[i]["eco"], null, "A: planet %d barren → no eco (TS:128)" % i)
			continue
		var sp_list: Array = sim_a.planets[i]["eco"].species
		var got: Array = []
		for sp in sp_list:
			got.append(String(sp["genome"]["diet"]))
		eq(got, exp_a[i], "A: planet %d roster diets match the pull-fed replay (TS:147-158)" % i)
		# the bonus ordering: titan + swarm LAST, their diet/size untouched
		if exp_a[i].size() >= 2:
			var titan: Dictionary = sp_list[sp_list.size() - 2]
			var swarm: Dictionary = sp_list[sp_list.size() - 1]
			approx(float(titan["genome"]["size"]), 2.2, "A: planet %d titan size 2.2 (TS:165)" % i)
			eq(String(titan["genome"]["diet"]), "carnivore", "A: planet %d titan diet SURVIVED the dial (TS:166)" % i)
			approx(float(swarm["genome"]["size"]), 0.6, "A: planet %d swarm 0.55 stored 0.6 (the addSpecies clamp, TS:172)" % i)
			eq(String(swarm["genome"]["diet"]), "herbivore", "A: planet %d swarm diet SURVIVED the dial (TS:173)" % i)
			approx(float(swarm["genome"]["hue"]), fmod(float(sim_a.planets[i]["hue"]) + 60.0, 360.0),
				"A: planet %d swarm hue +60 (TS:175)" % i)
	# the volcanic flip-back OBSERVED: any herbivore on the volcanic planet
	# got there ONLY through the dial (the kind forces carnivore first)
	var volc_a: Array = exp_a[2]
	var flips_back := 0
	for d in volc_a:
		if d == "herbivore":
			flips_back += 1
	ok(flips_back >= 1, "A: the volcanic carnivore→herbivore flip-back OBSERVED at 0x5CAC1 (%d of %d)" % [flips_back, volc_a.size()])
	ok(int(rep_a["flips"]) >= flips_back, "the replay counted the dial-caused flips (%d)" % int(rep_a["flips"]))
	_drop(ma)

	# world B: carn-heavy — the rosters land wherever the pinned stream puts
	# them (mutate at rate 0.9 is carnivore-dominated here, so the dial's own
	# flips may be 0 — the count is RECORDED, the diet match above is the pin)
	var mb := _boot(0x5CAC1, carn_world)
	var sim_b: Variant = mb["sim"]
	_silence_chaos(sim_b)
	var rep_b: Dictionary = replay_diets.call(0x5CAC1, mb["ctx"].world, herb_pull_b, carn_pull_b)
	var exp_b: Array = rep_b["diets"]
	for i in 6:
		if KINDS[i] == "barren":
			continue
		var sp_list_b: Array = sim_b.planets[i]["eco"].species
		var got_b: Array = []
		for sp in sp_list_b:
			got_b.append(String(sp["genome"]["diet"]))
		eq(got_b, exp_b[i], "B: planet %d roster diets match the pull-fed replay (TS:147-158)" % i)
	eq(int(rep_b["flips"]) >= 0, true, "B: the dial's flip count recorded (%d — the diets above are the pin)" % int(rep_b["flips"]))
	_drop(mb)


## Pin provenance: the abduct pay curve TS:672-707 verbatim — candidates
## filter pop ≥ 1 (:675-676); sp = rng.pick(candidates) (:681); pop −1
## (:682); repeats = abductCount['{p.id}:{sp.id}'] ?? 0 (:686-688); pay = 10
## if repeats == 0 else 3 (:689); the LAST member (pop < 1 after −1) → pop 0
## + extinct + bumpExtinction + the gone-from-this-world toast (:690-697);
## addDna(pay) (:702). Seed 0x5CAC2. The drive rides the REAL beam path (R
## press + dt 2.0 > 1.4 → arm + finish in the same frame — TS:501-507; the
## beamT gate :645 passes next frame since beamT lands negative). The
## five-catch sequence is derived catch-by-catch from the cloned stream's
## pick draws over the roster-ordered candidate list. Complement:
## test_space_sim pins one species' 10/3/3 + the last member; THIS probe
## composes the ledger across two species (whichever the pinned stream
## picks, tracked to any derived extinction) and pins the cross-planet key
## separation.
func test_abduct_pay_curve_ledger_at_scale() -> void:
	var m := _boot(0x5CAC2)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_silence_chaos(sim)
	# planet 0: two species at pop 5 each (kin — the pops move ONLY by abduct)
	var eco0: Variant = _craft_eco(sim, 0, [5.0, 5.0])
	_place_planet(sim, 0, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 0)
	sim.sx = 900.0
	sim.sy = 0.0
	sim.invuln = 0.0
	var sp_a: Dictionary = eco0.species[0]
	var sp_b: Dictionary = eco0.species[1]
	ctx.dna = 0
	ctx.world_stats["extinctions"] = 0
	ctx.flags.erase("spaceWorld")

	# the derivation: five catches, each derived from the cloned stream —
	# pick → candidate (roster order) → pay by the key ledger → pop tracking
	var probe: Variant = _probe_rng(sim)
	var pops := {String(sp_a["id"]): 5.0, String(sp_b["id"]): 5.0}
	var extinct := {}
	var ledger := {}
	var exp_dna := 0
	var exp_bumps := 0
	var exp_pays: Array = []
	for catch_i in 5:
		var candidates: Array = []
		for sp in eco0.species:  # the roster order IS the candidate order
			if not extinct.has(String(sp["id"])) and float(pops[String(sp["id"])]) >= 1.0:
				candidates.append(sp)
		var picked: Dictionary = candidates[floori(probe.next() * candidates.size())]  # TS:681
		var key := "0:%s" % String(picked["id"])
		var repeats: float = float(ledger.get(key, 0.0))
		ledger[key] = repeats + 1.0
		var pay: int = 10 if repeats == 0.0 else 3  # TS:689
		exp_dna += pay
		exp_pays.append(pay)
		var pid := String(picked["id"])
		pops[pid] = float(pops[pid]) - 1.0  # TS:682
		if pops[pid] < 1.0:  # TS:691 — the last member
			extinct[pid] = true
			exp_bumps += 1  # TS:696
	# the drive: five REAL beam frames (arm + finish at dt 2.0, TS:501-507).
	# The cargo-4 gate (TS:654) would block the 5th catch — the hold is
	# EMPTIED after catch 3 (a fixture write; the picks don't read cargo).
	for catch_i in 5:
		if catch_i == 3:
			sim.cargo.clear()
		sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
		_drain_toasts(m)  # keep the 6-deep hud list from evicting
	eq(int(ctx.dna), exp_dna,
		"the five-catch DNA total matches the derived pay composition (TS:689/702)")
	eq(int(ctx.world_stats["extinctions"]), exp_bumps,
		"bump_extinction counted exactly for the derived last-member catches (TS:696)")
	eq(int(sim.abductCount.get("0:%s" % String(sp_a["id"]), 0)), int(ledger.get("0:%s" % String(sp_a["id"]), 0.0)),
		"species A's ledger count matches the derivation (TS:686-688)")
	eq(int(sim.abductCount.get("0:%s" % String(sp_b["id"]), 0)), int(ledger.get("0:%s" % String(sp_b["id"]), 0.0)),
		"species B's ledger count matches the derivation (TS:686-688)")
	eq(int(ledger.get("0:%s" % String(sp_a["id"]), 0.0)) + int(ledger.get("0:%s" % String(sp_b["id"]), 0.0)), 5,
		"the two keys partition the five catches (the key scheme)")
	eq(int(sim.rng.state()), int(probe.state()),
		"the five catches consumed exactly the five pick draws (TS:681)")
	ok(exp_pays.has(10) and exp_pays.has(3),
		"the derived sequence carries both pay rungs (%s)" % str(exp_pays))
	# pops: the derived extinct species reads 0; survivors read their counts
	for sp in [sp_a, sp_b]:
		var want_pop: float = float(pops[String(sp["id"])])
		if extinct.has(String(sp["id"])):
			eq(float(sp["pop"]), 0.0, "the derived last-member species clamped to 0 (TS:691)")
			eq(bool(sp["extinct"]), true, "the derived last-member species is extinct (TS:692)")
		else:
			eq(float(sp["pop"]), want_pop, "the survivor's pop matches the derivation (TS:682)")
	# the cross-planet key separation: the SAME GENOME on planet 2 pays 10
	# again — a fresh '{p.id}:{sp.id}' key (TS:686)
	var eco2: Variant = EcoScript.new(RngLib.new_from(77))
	var g_twin: Dictionary = GenomeLib.clone_genome(sp_a["genome"])
	eco2.add_species(g_twin, 3.0, {"kin": true})
	sim.planets[2]["eco"] = eco2
	_place_planet(sim, 2, -1000.0, 0.0, 50.0)
	sim.sx = -1100.0
	sim.sy = 0.0
	var probe2: Variant = _probe_rng(sim)
	probe2.next()  # the pick draw
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(int(ctx.dna), exp_dna + 10,
		"the twin genome on planet 2 pays 10 — a FRESH key (TS:686/689)")
	eq(int(sim.abductCount["2:%s" % String(eco2.species[0]["id"])]), 1, "the planet-2 key opened at 1")
	# the deterministic LAST-MEMBER leg on planet 1: pop 1 → extinct + bump,
	# the gone-from-this-world toast, and NO re-farm (TS:690-697 + :664).
	# Planets 0 and 2 are pushed OUT so nearest_planet is unambiguous (a
	# same-distance tie would hand the catch to planet 0 — the strict-min
	# scan takes the first minimum).
	var eco1: Variant = _craft_eco(sim, 1, [1.0])
	var sp_last: Dictionary = eco1.species[0]
	_place_planet(sim, 1, 1000.0, 0.0, 50.0)
	_place_planet(sim, 0, 8000.0, 0.0, 50.0)
	_place_planet(sim, 2, -8000.0, 0.0, 50.0)
	sim.sx = 900.0
	sim.sy = 0.0
	sim.cargo.clear()  # the cargo-4 gate must not shadow the living-empty gate
	sim.abductCount = {}
	ctx.dna = 0
	ctx.world_stats["extinctions"] = 0
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(float(sp_last["pop"]), 0.0, "the last member's pop clamped to 0 (TS:691)")
	eq(bool(sp_last["extinct"]), true, "the last member extinct (TS:692)")
	eq(int(ctx.world_stats["extinctions"]), 1, "bump_extinction for the last member (TS:696)")
	eq(int(ctx.dna), 10, "the pay curve PRECEDES the pop check: the first catch pays 10 (TS:689)")
	eq(_scan_toasts(m, "that species is now gone from this world"), 1,
		"the gone-from-this-world toast verbatim (TS:697)")
	sim.update(2.0, _inp({"keys_pressed": ["KeyR"]}))
	eq(_scan_toasts(m, "No life to abduct here"), 1,
		"the extinct species cannot be re-farmed (the living-empty gate, TS:664)")
	_drop(m)


## Pin provenance: the colony logistic growth TS:370-372 verbatim —
## pop += dt·timeScale·0.08·(1 + pop·0.01)·max(0, 1 − pop/120) every frame
## (the orbit loop, NOT gated on ff); timeScale pre-reads ffHold (:306
## before the :307 decay — the first held frame ticks ×1, the frame after
## release STILL ticks ×26). Seed 0x5CAC3. The probe composes the recurrence
## over 331 frames across four drive phases with its own ts-sequence replay
## and requires the sim's colony to match bit-exact at every checkpoint; the
## cap-120 brake exact: the 200-frame ff soak asymptotes UNDER 120 (the
## max(0, 1−pop/120) factor), never crossing. Complement: test_space_sim
## pins 1-3 frames + the static 120/130 brakes; THIS probe pins the
## multi-phase trajectory including the post-release ×26 growth frame.
func test_colony_logistic_brake_exact_over_330_frames() -> void:
	var m := _boot(0x5CAC3)
	var sim: Variant = m["sim"]
	_silence_chaos(sim)
	sim.planets[0]["colony"] = {"pop": 1.0, "generations": 0.0}
	sim.invuln = 0.0

	# the probe's own ts-sequence replay: timeScale reads ffHold BEFORE the
	# KeyF write (:306/:307). The ONLY pop source is the growth (the ship
	# parks at (0,−900); the nearest colony orbit ≥ 460 keeps d > r+150 for
	# every generated radius; the sun sits 900 away).
	var ff_hold := 0.0
	var pop := 1.0

	# phase 1: 120 normal frames at DT — ts 1 throughout
	for f in 120:
		var ts: float = 26.0 if ff_hold > 0.0 else 1.0  # the PRE-read (TS:306)
		ff_hold = maxf(0.0, ff_hold - DT)  # released — stays 0
		pop += DT * ts * 0.08 * (1.0 + pop * 0.01) * maxf(0.0, 1.0 - pop / 120.0)  # TS:372
		sim.update(DT, _inp())
		if (f + 1) % 30 == 0:
			approx(float(sim.planets[0]["colony"]["pop"]), pop,
				"phase 1 frame %d: the recurrence composed at ts 1 (TS:372)" % (f + 1))
	# phase 2: 8 ff-hold frames at dt 1.0 — ts [1, 26×7] (the pre-read)
	for i in 8:
		var ts2: float = 26.0 if ff_hold > 0.0 else 1.0
		ff_hold = 1.0  # KeyF held
		pop += 1.0 * ts2 * 0.08 * (1.0 + pop * 0.01) * maxf(0.0, 1.0 - pop / 120.0)
		sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
		approx(float(sim.planets[0]["colony"]["pop"]), pop,
			"phase 2 frame %d: the ff growth (frame 1 ×1 then ×26 — the pre-read, TS:306/372)" % (i + 1))
	# phase 3: 3 RELEASED frames at dt 1.0 — the FIRST still grows ×26 (the
	# pre-read saw the held ffHold; the ff BLOCK itself skips — no eco tick)
	for i in 3:
		var ts3: float = 26.0 if ff_hold > 0.0 else 1.0
		ff_hold = maxf(0.0, ff_hold - 1.0)  # released
		pop += 1.0 * ts3 * 0.08 * (1.0 + pop * 0.01) * maxf(0.0, 1.0 - pop / 120.0)
		sim.update(1.0, _inp())
		approx(float(sim.planets[0]["colony"]["pop"]), pop,
			"phase 3 frame %d: the release-frame growth follows the pre-read (TS:306)" % (i + 1))
	# phase 4: the brake soak — 200 more ff frames asymptote UNDER 120
	var crossed := false
	var prev_pop := pop
	for i in 200:
		var ts4: float = 26.0 if ff_hold > 0.0 else 1.0
		ff_hold = 1.0
		pop += 1.0 * ts4 * 0.08 * (1.0 + pop * 0.01) * maxf(0.0, 1.0 - pop / 120.0)
		if pop >= 120.0:
			crossed = true
		sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
		if i % 50 == 49:
			approx(float(sim.planets[0]["colony"]["pop"]), pop,
				"soak frame %d: the recurrence holds bit-exact (TS:372)" % (i + 1))
			ok(pop > prev_pop, "the population still climbs at soak frame %d" % (i + 1))
			prev_pop = pop
	eq(crossed, false, "200 ff frames NEVER cross 120 — the max(0, 1−pop/120) brake exact (TS:372)")
	approx(float(sim.planets[0]["colony"]["pop"]), pop, "the final pop matches the composed recurrence", 1e-9)
	ok(pop < 120.0 and pop > 100.0, "the asymptote sits under the cap (%f)" % pop)
	_drop(m)


## Pin provenance: the ff block TS:306-323 verbatim — generations +=
## dt·timeScale/30 per colonized planet INSIDE the ff block (:323); the
## eco.mods wire (:309-311): ONE eco_mods_from_world snapshot assigned to
## EVERY planet eco per frame, then eco.tick(dt·timeScale) (:315) — the wire
## that makes world-trait effects real. Seed 0x5CAC4, TWO same-seed boots
## (growth_mult 1.5 vs traitless) with IDENTICAL crafted planet-0 ecos. The
## derivation: probe-controlled TWIN ecos built from the same cloned rng —
## twin_hot.mods = {growth_mult: 1.5} composed by the probe from its own
## reading of the crafted trait (one num effect → the key rides),
## twin_cold.mods = {} — ticked with the probe's own ts sequence. Each sim's
## eco must match its twin bit-exact (the wire delivered exactly the derived
## mods), and the two tables must DIVERGE with the trait real. Complement:
## test_space_sim pins the wire with a RECORDER eco (canned ticks) +
## generations at 2 frames; THIS probe observes a world trait's effect
## through a REAL eco at scale and composes the generations across the
## whole window.
func test_ff_generations_and_eco_mods_wire_through_real_eco() -> void:
	var hot_world: Dictionary = {"traits": [{"effects": [
		{"kind": "num", "key": "growth_mult", "value": 1.5}]}]}
	var ma := _boot(0x5CAC4, hot_world)
	# the COLD twin needs a genuinely traitless world: a derived world seed
	# carries its own traits (0x5CAC4's default wires growth_mult 1.05 etc.)
	# — the empty-traits override is the control
	var mb := _boot(0x5CAC4, {"traits": []})
	var sim_a: Variant = ma["sim"]
	var sim_b: Variant = mb["sim"]
	_silence_chaos(sim_a)
	_silence_chaos(sim_b)
	# identical crafted planet-0 ecos (the eco's own rng cloned from 777 —
	# identical rosters, identical speciation rolls). NON-kin on purpose:
	# kin lines skip the growth valve — the trait must reach a line the
	# valve actually drives.
	var build_eco := func() -> Variant:
		var eco: Variant = EcoScript.new(RngLib.new_from(777))
		eco.flora_cap = 140.0
		eco.flora = 60.0
		eco.add_species(GenomeLib.clone_genome(GenomeLib.default_genome()), 8.0)
		return eco
	var eco_a: Variant = build_eco.call()
	var eco_b: Variant = build_eco.call()
	var twin_hot: Variant = build_eco.call()
	var twin_cold: Variant = build_eco.call()
	twin_hot.mods = {"growth_mult": 1.5}  # the probe's OWN closed form of
	# eco_mods_from_world for the crafted world (one num effect → the key)
	twin_cold.mods = {}
	sim_a.planets[0]["eco"] = eco_a
	sim_b.planets[0]["eco"] = eco_b
	# colonies on planet 1 for the generations leg
	sim_a.planets[1]["colony"] = {"pop": 1.0, "generations": 0.0}
	sim_b.planets[1]["colony"] = {"pop": 1.0, "generations": 0.0}
	sim_a.invuln = 0.0
	sim_b.invuln = 0.0

	# the probe's ts replay (the pre-read: frame 1 ×1, frames 2+ ×26)
	var ff_hold := 0.0
	var gens := 0.0
	for f in 40:
		var ts: float = 26.0 if ff_hold > 0.0 else 1.0  # TS:306
		ff_hold = 1.0  # KeyF held every frame
		gens += 1.0 * ts / 30.0  # TS:323 — dt 1.0
		sim_a.update(1.0, _inp({"keys_held": ["KeyF"]}))
		sim_b.update(1.0, _inp({"keys_held": ["KeyF"]}))
		twin_hot.tick(1.0 * ts)   # TS:315 at the probe's derived timescale
		twin_cold.tick(1.0 * ts)
		if f == 9 or f == 19 or f == 39:
			approx(float(eco_a.flora), float(twin_hot.flora),
				"frame %d: the wired eco matches the growth_mult 1.5 twin bit-exact (the wire, TS:309-315)" % (f + 1), 1e-9)
			approx(float(eco_b.flora), float(twin_cold.flora),
				"frame %d: the traitless eco matches the cold twin (TS:309-315)" % (f + 1), 1e-9)
			approx(float(eco_a.species[0]["pop"]), float(twin_hot.species[0]["pop"]),
				"frame %d: the species pop matches the hot twin (the valve rode gm)" % (f + 1), 1e-9)
	# the wire delivered EXACTLY the probe's derived mods dict
	eq(eco_a.mods, {"growth_mult": 1.5},
		"the sim's eco.mods equals the probe-derived dict (TS:309-311)")
	eq(eco_b.mods, {}, "the traitless world wires an empty mods dict")
	# the trait is REAL: the two tables diverged
	var gap_now: float = absf(float(twin_hot.flora) - float(twin_cold.flora)) \
			+ absf(float(twin_hot.species[0]["pop"]) - float(twin_cold.species[0]["pop"]))
	ok(gap_now > 1e-6, "the growth_mult tables DIVERGED through the real ecos (gap %f)" % gap_now)
	# the generations composition over the whole window (TS:323)
	approx(float(sim_a.planets[1]["colony"]["generations"]), gens,
		"generations = Σ dt·ts/30 over the ff window (1/30 + 39·26/30) (TS:323)", 1e-9)
	approx(float(sim_b.planets[1]["colony"]["generations"]), gens, "the twin sim's generations match")
	_drop(ma)
	_drop(mb)


## Pin provenance: mergeCargo's crossover opts TS:744-755 verbatim —
## anomalyChance 0.15 wild / 0.10 normal (:750), defectRate 0.3 wild / 0.2
## normal (:751), bias.rate_add = worldNum(mutation_rate_add, 0) (:752-753);
## the splice table rolls ONE anomaly chance + ONE defect chance per merge
## (the TOTAL per-splice budget, never additive). Seed 0x5CAC5, THREE
## same-seed boots (normal / wild / rate_add 0.5). The derivation: 24-merge
## chains replayed on ONE cloned stream per boot (crossover + species_name
## per merge), every child bit-exact, and the anomaly/defect FIRE COUNTS
## derived from the replays' SpliceInfo must equal the real toast counts —
## the at-scale rate observation. Complement: test_space_sim pins ONE merge
## bit-exact + the wild divergence scan + the rate_add pair at one merge;
## THIS probe pins three 24-merge chains with composed fire counts.
func test_crossover_opts_wild_vs_normal_rate_add_chains() -> void:
	var ga: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	ga.merge({"size": 1.2, "jaw": 3, "diet": "herbivore", "hue": 100.0}, true)
	var gb: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	gb.merge({"size": 1.8, "spikes": 2, "diet": "carnivore", "hue": 200.0}, true)
	var n_merges := 24
	# EVERY table is world-CONTROLLED: a derived world seed carries its own
	# traits (0x5CAC5's default wires wild_mutations + rate_add 0.15 — an
	# uncontrolled "normal" boot would run the wild table while the replay
	# composed the normal one: children can survive an anomaly rewrite that
	# clamps to a no-op, but the streams diverge at the name draw)
	var worlds := [
		{"name": "normal", "over": {"traits": []}, "anom": 0.10, "def": 0.2},
		{"name": "wild", "over": {"traits": [{"effects": [{"kind": "flag", "key": "wild_mutations"}]}]}, "anom": 0.15, "def": 0.3},
		{"name": "rate_add", "over": {"traits": [{"effects": [{"kind": "num", "key": "mutation_rate_add", "value": 0.5}]}]}, "anom": 0.10, "def": 0.2},
	]
	var fire_report: Array = []
	for w in worlds:
		var m := _boot(0x5CAC5, w["over"])
		var sim: Variant = m["sim"]
		var ctx: Variant = m["ctx"]
		_silence_chaos(sim)
		ctx.dna = 1000
		# the probe's opts — the TABLE composed from the probe's own reading
		# (0.15/0.3 wild vs 0.10/0.2 — the pin), the bias read the same way
		# the sim reads it (the shared-lib call is the established shape)
		var opts: Dictionary = {
			"anomalyChance": w["anom"],
			"defectRate": w["def"],
			"bias": {"rate_add": WorldGenomeLib.world_num(ctx.world, "mutation_rate_add", 0.0)},
		}
		var probe: Variant = _probe_rng(sim)
		var last_child: Dictionary = {}
		var exp_anom := 0
		var exp_def := 0
		for i in n_merges:
			var info: Dictionary = {"anomaly": null, "defect": null}
			var o: Dictionary = opts.duplicate()
			o["info"] = info
			last_child = MutationLib.crossover(ga, gb, probe, 0.3, o)  # TS:749-755
			NamesLib.species_name(probe)  # TS:756
			if info["anomaly"] != null:
				exp_anom += 1
			if info["defect"] != null:
				exp_def += 1
		# the drive: 24 REAL merges (the pair re-stocked each time — the
		# chain rides ONE stream). The toasts are counted from ONE drain per
		# merge (a second _scan_toasts would find an empty list — the first
		# scan clears it)
		var got_anom := 0
		var got_def := 0
		for i in n_merges:
			sim.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
			sim.merge_cargo()
			var toasts: Array = m["stage"].hud_inst._toasts
			for t in toasts:
				if String(t["text"]).find("UNEXPECTED EXPRESSION") >= 0:
					got_anom += 1
				if String(t["text"]).find("Defective splice:") >= 0:
					got_def += 1
			toasts.clear()
		eq(sim.cargo[0]["genome"], last_child,
			"%s: the 24th child bit-matches the chain replay (TS:749-755)" % w["name"])
		eq(got_anom, exp_anom, "%s: the anomaly fire count matches the derived rolls (%d/%d)" % [w["name"], exp_anom, n_merges])
		eq(got_def, exp_def, "%s: the defect fire count matches the derived rolls (%d/%d)" % [w["name"], exp_def, n_merges])
		eq(int(sim.rng.state()), int(probe.state()),
			"%s: the chain consumed exactly crossover+name per merge" % w["name"])
		eq(int(ctx.dna), 1000 - n_merges * 15, "%s: 24 splices spent 15 each (TS:738)" % w["name"])
		fire_report.append("%s anom %d/%d def %d/%d" % [w["name"], exp_anom, n_merges, exp_def, n_merges])
		_drop(m)
	# the rate observation is RECORDED (the exact counts are the pins — the
	# relationships are not asserted since the counts are whatever the pinned
	# streams roll; the report carries the table)
	eq(fire_report.size(), 3, "three chains derived: %s" % " | ".join(fire_report))


## Pin provenance: borrowedFleshGraft TS:772-792 verbatim — the combo guard
## precedes the shuffle (:778, no draw when off); the once-per-run flag
## guard `=== true` (:778); the shuffled extinct lineages (:780); a lineage
## whose raised ≤ cur is SKIPPED (never downgrades, :786 — try the next);
## the graft writes child[gene] = raised + sets the flag (:787-788). Seed
## 0x5CAC6 on a combo-fired world. The chain: merge 1's shuffle visit order
## derived from the clone (the cannot-raise lineage passed — raised == cur —
## the giver grafts); merge 2 draws NO shuffle (the flag). The whole
## two-merge stream replayed on one probe clone. Complement: test_space_sim
## pins both guards in isolation; THIS probe pins the visit-order-dependent
## outcome inside a real splice chain plus the flag silencing the second
## merge's shuffle.
func test_graft_never_downgrade_and_flag_in_splice_chain() -> void:
	var m := _boot(0x5CAC6, {"traits": [], "comboFired": {"borrowed_flesh": true}})
	# traits [] = the CONTROLLED normal table (a derived world seed carries
	# its own — the replay below composes the normal 0.10/0.2 rates, so the
	# boot must not inherit a wild_mutations flag)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_silence_chaos(sim)
	ctx.dna = 1000
	var ga: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	ga.merge({"jaw": 3, "diet": "herbivore", "hue": 100.0}, true)
	var gb: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	gb.merge({"size": 1.8, "spikes": 2, "diet": "carnivore", "hue": 200.0}, true)

	# pre-derive merge 1's child on a SCRATCH clone (its consumption is
	# throwaway — the MAIN clone below must start at the pre-merge state so
	# the full two-merge replay stays stream-aligned)
	var scratch: Variant = _probe_rng(sim)
	var child1: Dictionary = MutationLib.crossover(ga, gb, scratch, 0.3, {
		"anomalyChance": 0.10, "defectRate": 0.2, "bias": {"rate_add": 0.0},
		"info": {"anomaly": null, "defect": null}})
	NamesLib.species_name(scratch)
	# the SKIP source: a part gene where the child's value ≥ 2 (standout-able)
	# — raised == cur skips (TS:786); the GIVER: a ZEROED part gene (raised
	# 3 > 0 grafts). The crafted bestiary genomes zero every OTHER part gene
	# so standout_part lands exactly on the crafted gene (premise-asserted).
	var skip_gene := ""
	var skip_v := 0.0
	var graft_gene := ""
	for pdef in PartsLib.PARTS:
		var gene := String(pdef["gene"])
		var cv: float = float(child1.get(gene, 0))
		if cv >= 2.0 and skip_gene == "":
			skip_gene = gene
			skip_v = cv
		if cv == 0.0 and graft_gene == "":
			graft_gene = gene
	ok(skip_gene != "", "the probe child has a part gene ≥ 2 to build the skip source (premise)")
	ok(graft_gene != "", "the probe child has a zeroed part gene to graft (premise)")
	var ks_genome: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	var kg_genome: Dictionary = GenomeLib.clamp_genome(GenomeLib.default_genome())
	for pdef in PartsLib.PARTS:
		ks_genome[String(pdef["gene"])] = 0
		kg_genome[String(pdef["gene"])] = 0
	ks_genome[skip_gene] = int(skip_v)
	kg_genome[graft_gene] = 3
	var ks_standout: Variant = PartsLib.standout_part(ks_genome)
	var kg_standout: Variant = PartsLib.standout_part(kg_genome)
	ok(ks_standout != null and String(ks_standout["def"]["gene"]) == skip_gene,
		"the skip source's standout lands on %s (premise)" % skip_gene)
	ok(kg_standout != null and String(kg_standout["def"]["gene"]) == graft_gene,
		"the giver's standout lands on %s (premise)" % graft_gene)
	ctx.bestiary = {
		"ks": {"key": "ks", "name": "Skipper", "genome": ks_genome,
			"stage": "cell", "seen": 1, "killsByPlayer": 0, "extinct": true, "kin": false},
		"kg": {"key": "kg", "name": "Giver", "genome": kg_genome,
			"stage": "cell", "seen": 1, "killsByPlayer": 0, "extinct": true, "kin": false},
	}

	# the FULL two-merge replay on a FRESH clone (the stream is continuous
	# from the pre-merge state): merge 1 = crossover + name + shuffled
	# ([ks, kg]); merge 2 = crossover + name ONLY (the flag silences the
	# shuffle)
	var probe: Variant = _probe_rng(sim)
	var child1_exp: Dictionary = MutationLib.crossover(ga, gb, probe, 0.3, {
		"anomalyChance": 0.10, "defectRate": 0.2, "bias": {"rate_add": 0.0},
		"info": {"anomaly": null, "defect": null}})
	var child1_name: String = NamesLib.species_name(probe) + " (spliced)"
	var order: Array = probe.shuffled([ctx.bestiary["ks"], ctx.bestiary["kg"]])  # TS:780
	var child2_exp: Dictionary = MutationLib.crossover(ga, gb, probe, 0.3, {
		"anomalyChance": 0.10, "defectRate": 0.2, "bias": {"rate_add": 0.0},
		"info": {"anomaly": null, "defect": null}})
	var child2_name: String = NamesLib.species_name(probe) + " (spliced)"

	# the drive
	sim.cargo = [{"genome": ga, "name": "Al"}, {"genome": gb, "name": "Bo"}]
	sim.merge_cargo()
	var graft_toast := _scan_toasts(m, "Borrowed flesh:")
	# the derived GRAFTED child: whichever visit order the shuffle chose, the
	# giver grafts (the skipper cannot raise) — the cargo row carries the
	# graft write (the graft mutates the child dict in place)
	var child1_grafted: Dictionary = child1_exp.duplicate()
	child1_grafted[graft_gene] = 3.0
	eq(sim.cargo[0]["genome"], child1_grafted, "merge 1's child bit-matches the chain replay + the derived graft (TS:749-755/787)")
	eq(String(sim.cargo[0]["name"]), child1_name, "merge 1's name matches the replay")
	eq(bool(ctx.flags["borrowed_flesh_graft"]), true, "the graft set the once-per-run flag (TS:788)")
	eq(graft_toast, 1, "exactly one borrowed-flesh toast (TS:789)")
	# the never-downgrade skip INSIDE the derived visit order: whichever
	# lineage came first, the outcome is the giver's gene raised and the
	# skipper's gene untouched
	eq(float(sim.cargo[0]["genome"][graft_gene]), 3.0,
		"the giver's gene raised to 3 (TS:785/787)")
	eq(float(sim.cargo[0]["genome"][skip_gene]), skip_v,
		"the skip lineage never moved its gene (raised == cur → next, TS:786)")
	var first_name: String = String(order[0]["name"])
	ok(first_name == "Skipper" or first_name == "Giver",
		"the derived visit order starts with %s (the pinned shuffle)" % first_name)
	sim.cargo = [{"genome": ga, "name": "Cy"}, {"genome": gb, "name": "Dy"}]
	sim.merge_cargo()
	eq(sim.cargo[0]["genome"], child2_exp, "merge 2's child bit-matches the no-shuffle replay")
	eq(String(sim.cargo[0]["name"]), child2_name, "merge 2's name matches the replay")
	eq(_scan_toasts(m, "Borrowed flesh:"), 0,
		"the flag silenced merge 2's graft entirely (TS:778 === true)")
	eq(int(sim.rng.state()), int(probe.state()),
		"the two-merge chain consumed exactly the derived draws (shuffle once, then none)")
	_drop(m)


## Pin provenance: the pirate loop TS:454-498 verbatim — pd = dist
## (pre-move); d > 30 → v += (dir)·300·dt (:466-469); drag exp(−1.4dt)
## (:470-471); x += v·dt (:472); the damage window d < 60 && invuln ≤ 0 &&
## !lull → shp −14dt, hurtT 0.5, chance(dt·6) → the 4-particle burst
## (:474-481); the click hit clickD < 60 → hp −34, the 8-particle burst, hp
## ≤ 0 → splice + toast + addDna(30) + the 20-particle death burst
## (:482-497). Seed 0x5CAC7. The chase: 120 frames at DT with the FULL
## recursion composed probe-side (including the chance/burst draws replayed
## per frame) — bit-exact at every checkpoint. The kill: 5 clicks at 34
## (140 → −30) with both bursts' draws replayed; +30 DNA. Complement:
## test_space_sim pins single frames + the ladder; THIS probe composes the
## 120-frame trajectory and the kill economics at the pinned stream.
func test_pirate_chase_damage_math_at_scale() -> void:
	var m := _boot(0x5CAC7)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_silence_chaos(sim)
	sim.invuln = 0.0
	sim.sx = 0.0
	sim.sy = -900.0
	sim.pirates = [{"x": 200.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	sim.shp = 100.0
	sim.hurtT = 0.0

	# the probe's own per-frame replay (the identical TS ops + draw order)
	var probe: Variant = _probe_rng(sim)
	var px := 200.0
	var py := -900.0
	var pvx := 0.0
	var pvy := 0.0
	var shp := 100.0
	var in_window := 0
	var burst_frames := 0
	for f in 120:
		var pd: float = sqrt(px * px + (py + 900.0) * (py + 900.0))
		if pd > 30.0:  # TS:466
			pvx += ((0.0 - px) / pd) * 300.0 * DT
			pvy += ((-900.0 - py) / pd) * 300.0 * DT
		var drag: float = exp(-1.4 * DT)  # TS:470
		pvx *= drag
		pvy *= drag
		px += pvx * DT  # TS:472
		py += pvy * DT
		if pd < 60.0:  # TS:474 (invuln 0, no lull)
			in_window += 1
			shp -= 14.0 * DT  # TS:475
			if probe.chance(DT * 6.0):  # TS:477 — the burst draw
				burst_frames += 1
				for i in 4:
					probe.next()
					probe.range(0.3, 1.0)
					probe.pick(["#ff8a5a"])
					probe.range(0.4, 1.0)
					probe.range(0.6, 1.4)
		sim.update(DT, _inp())
		if f == 29 or f == 59 or f == 89 or f == 119:
			var got: Dictionary = sim.pirates[0]
			approx(float(got["x"]), px, "frame %d: pirate x matches the composed chase (TS:466-472)" % (f + 1))
			approx(float(got["y"]), py, "frame %d: pirate y matches" % (f + 1))
			approx(float(got["vx"]), pvx, "frame %d: vx matches (accel 300 + drag exp(−1.4dt))" % (f + 1))
			approx(float(sim.shp), shp, "frame %d: the hull curve matches (−14dt per in-window frame)" % (f + 1))
	eq(int(sim.rng.state()), int(probe.state()),
		"the chase consumed exactly the in-window chance (+burst) draws (TS:477)")
	ok(in_window >= 30, "the pirate entered the damage window (%d of 120 frames)" % in_window)
	ok(burst_frames >= 1, "the chance(dt·6) bursts OBSERVED (%d frames)" % burst_frames)
	eq(sim.pirates.size(), 1, "the pirate survived the chase phase (chase frames never touch hp)")

	# the click kill: the pirate re-parked ON the ship, hp 140 → 5 clicks
	sim.pirates = [{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0}]
	sim.pirateTtl = [40.0]
	ctx.dna = 0  # the kill's +30 must land on a zeroed ledger
	probe = _probe_rng(sim)
	var hp := 140.0
	var dead_at := -1
	for click_i in 5:
		# the damage branch fires first (d 0 < 60): the chance draw (+ burst)
		if probe.chance(DT * 6.0):
			for i in 4:
				probe.next()
				probe.range(0.3, 1.0)
				probe.pick(["#ff8a5a"])
				probe.range(0.4, 1.0)
				probe.range(0.6, 1.4)
		# the click: the 8-particle hit burst, then the death check
		hp -= 34.0  # TS:485
		for i in 8:
			probe.next()
			probe.range(0.3, 1.0)
			probe.pick(["#ffe97a", "#9fd8ff"])
			probe.range(0.4, 1.0)
			probe.range(0.6, 1.4)
		if hp <= 0.0 and dead_at < 0:
			dead_at = click_i
			for i in 20:  # TS:494 — the death burst
				probe.next()
				probe.range(0.3, 1.0)
				probe.pick(["#ff8a5a", "#ffd08a"])
				probe.range(0.4, 1.0)
				probe.range(0.6, 1.4)
		sim.update(DT, _inp({"clicked": true, "wx": 0.0, "wy": -900.0}))
		if dead_at >= 0 and sim.pirates.is_empty():
			break
	eq(dead_at, 4, "140 hp dies on the 5th 34-dmg click (140 − 34·5 = −30, TS:485/489)")
	eq(sim.pirates.size(), 0, "the kill spliced the pirate out (TS:490)")
	eq(int(ctx.dna), 30, "addDna(30) on the kill (TS:493)")
	eq(_scan_toasts(m, "Pirate destroyed! +30 DNA"), 1, "the kill toast verbatim (TS:492)")
	eq(int(sim.rng.state()), int(probe.state()),
		"the kill phase consumed exactly the derived burst draws (TS:478/487/494)")
	_drop(m)


## Pin provenance: the black-hole block TS:436-452 verbatim — bd = dist;
## bd < 600 && bd > 0.001 && invuln ≤ 0 → pull = 24000/max(80, bd); sv +=
## ((h−s)/bd)·pull·dt (:439-443); bd < 40 → shp −60dt (:444-446); the drift
## + ttl ungated (:448-450); the death block's cull: holes within 700 of the
## RESPAWN (0,−900) are culled, strict > (:595-597 — the radius must exceed
## the 600 pull radius or the killer chain-kills the fresh respawn). Seed
## 0x5CAC8. The pull: 20 frames at dt 0.5 from d 500 with the FULL recursion
## composed (the ship drag exp(−1.1dt) acts on the pull-built velocity; d
## recomputes each frame) — bit-exact; the d-79 clamp leg (24000/80). The
## cull: death-by-hole → the killer culled, the d-750 hole kept, the d-700
## edge culled. Complement: test_space_sim pins single-frame pulls at static
## distances + the cull with a fixture death; THIS probe integrates the
## pull over the ship's own drag and derives the death-by-hole cull.
func test_black_hole_pull_integration_and_cull_on_death() -> void:
	var m := _boot(0x5CAC8)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_silence_chaos(sim)
	sim.invuln = 0.0
	sim.sx = 0.0
	sim.sy = -900.0

	# leg 1: the free pull from d 500 (the hole static, ttl long)
	sim.blackHoles = [{"x": 500.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.svx = 0.0
	sim.svy = 0.0
	var probe: Variant = _probe_rng(sim)  # a no-draw guard for the whole leg
	var sx := 0.0
	var svx := 0.0
	for f in 20:
		svx *= exp(-1.1 * 0.5)  # the ship drag acts first (TS:347)
		sx += svx * 0.5         # then the position integrate (TS:349-351)
		var bd: float = absf(500.0 - sx)
		if bd < 600.0 and bd > 0.001:  # TS:439
			var pull: float = 24000.0 / maxf(80.0, bd)  # TS:440
			svx += ((500.0 - sx) / bd) * pull * 0.5  # TS:441-442
		sim.update(0.5, _inp())
		if f == 4 or f == 9 or f == 19:
			approx(float(sim.svx), svx, "frame %d: svx matches the integrated pull (TS:440-442)" % (f + 1))
			approx(float(sim.sx), sx, "frame %d: the ship position matches (drag + integrate + pull)" % (f + 1))
	eq(int(sim.rng.state()), int(probe.state()), "the pull legs consumed NO stage draws")
	ok(svx > 0.0, "the pull accelerated the ship toward the hole (svx %f)" % svx)

	# leg 2: the max(80, d) clamp from d 79 — the FIRST frame's pull is
	# exactly 24000/80 = 300 (d 79 < 80 clamps)
	sim.blackHoles = [{"x": 79.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
	sim.sx = 0.0
	sim.svx = 0.0
	sx = 0.0
	svx = 0.0
	var first_svx := -1.0
	for f in 3:
		svx *= exp(-1.1 * 0.5)
		sx += svx * 0.5
		var bd2: float = absf(79.0 - sx)
		if bd2 < 600.0 and bd2 > 0.001:
			svx += ((79.0 - sx) / bd2) * (24000.0 / maxf(80.0, bd2)) * 0.5
		if f == 0:
			first_svx = svx
		sim.update(0.5, _inp())
	approx(first_svx, (79.0 / 79.0) * (24000.0 / 80.0) * 0.5,
		"the first frame's svx = (24000/80)·dt — the d-79 CLAMP (TS:440)")
	approx(float(sim.svx), svx, "the clamp leg's 3-frame composition matches (TS:440)")

	# leg 3: death-by-hole → the killer culled at the respawn (TS:595-597)
	ctx.dna = 200
	sim.blackHoles = [
		{"x": 0.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0},     # the killer AT the respawn
		{"x": -750.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0},  # d 750 → kept
		{"x": -700.0, "y": -900.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0},  # d 700 → culled (strict >)
	]
	sim.sx = 0.0
	sim.sy = -900.0
	sim.svx = 0.0
	sim.svy = 0.0
	sim.shp = 5.0
	sim.invuln = 0.0
	ctx.flags.erase("spaceWorld")
	# the derivation: frame 1 — the killer's d 0 fails the 0.001 pull guard
	# but passes the d < 40 damage gate → shp 5 − 60·1.0 < 0 → the death
	# block: respawn (0,−900), the bill round(200·0.15) = 30, the cull
	sim.update(1.0, _inp())
	eq(int(ctx.dna), 170, "the death bill round(200·0.15) = 30 (TS:587-588)")
	eq(sim.blackHoles.size(), 1, "the killer (d 0) AND the d-700 edge CULLED — only d 750 kept (TS:595-597)")
	approx(float(sim.blackHoles[0]["x"]), -750.0, "the d-750 hole survived the cull")
	eq(float(sim.shp), 50.0, "the respawn restored shpMax·0.5 (TS:586)")
	_drop(m)


## Pin provenance: ship death TS:584-602 verbatim — shp = shpMax·0.5;
## lost = endingDone ? 0 : round(dna·0.15); addDna(−lost); the respawn
## (0,−900); cargo SURVIVES (:589-590). Seed 0x5CAC9. The compound curve:
## FOUR deaths from 1000 DNA with every round() step derived (150 → 128 →
## 108 → 92 — each −15% applies to the ROUNDED remainder); the post-ending
## twin bills 0 four times. Complement: test_space_sim pins one death + the
## 4.5→5 rounding + the post-ending zero; THIS probe composes the
## multi-death curve.
func test_ship_death_compound_curve_and_post_ending() -> void:
	var m := _boot(0x5CAC9)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_silence_chaos(sim)
	sim.invuln = 0.0
	var dna := 1000
	ctx.dna = dna
	var cargo_row: Dictionary = {"genome": GenomeLib.default_genome(), "name": "Keeper"}
	sim.cargo = [cargo_row, cargo_row]
	# the probe's own compound derivation (the identical ops)
	var exp_lost: Array = []
	var exp_dna: Array = []
	for i in 4:
		var lost: int = roundi(float(dna) * 0.15)  # TS:587 — JS Math.round
		exp_lost.append(lost)
		dna -= lost
		exp_dna.append(dna)
	eq(exp_lost, [150, 128, 108, 92],
		"the derived compound curve 1000 → 850 → 722 → 614 → 522 (round half up)")
	for i in 4:
		sim.sx = 500.0  # away from the respawn — the death block moves it back
		sim.sy = 500.0
		sim.shp = 0.0
		sim.update(0.1, _inp())
		eq(int(ctx.dna), int(exp_dna[i]), "death %d: the DNA matches the derived curve (lost %d, TS:587-588)" % [i + 1, exp_lost[i]])
		eq(float(sim.shp), 50.0, "death %d: the respawn restored 50 (TS:586)" % (i + 1))
		eq(float(sim.sx), 0.0, "death %d: respawn sx (TS:592)" % (i + 1))
		eq(sim.cargo.size(), 2, "death %d: cargo SURVIVES (TS:589-590)" % (i + 1))
	# the post-ending twin: four more deaths bill ZERO
	sim.endingDone = true
	for i in 4:
		sim.shp = 0.0
		sim.update(0.1, _inp())
		eq(int(ctx.dna), int(exp_dna[3]), "post-ending death %d: NO bill — you already won (TS:587 ternary)" % (i + 1))
		eq(float(sim.shp), 50.0, "post-ending death %d: the respawn still runs (TS:586)" % (i + 1))
	sim.endingDone = false
	_drop(m)


## Pin provenance: the tribute rule TS:539-547 (the STAGE ctx's onEnd — the
## deck def carries no end, space_events.gd's split) + demandTribute
## TS:851-859 (demand 60, the danger banner) + the def's duration [12,12]
## and the 2.5 s warn window (spaceEvents.ts:45). Seed 0x5CACA. The REAL
## update loop drives the whole timeline (not update_chaos directly — the
## test_space_events shape): warn → demand → the UNPAID end spawns 3 pirates
## IN the real frame (spawnPirates(3), TS:543) → the first chase frame
## derived for all three from the replayed ring draws. Complement:
## test_space_events drives update_chaos with a substituted deck + the hook
## callable pin; THIS probe rides the REAL frame order (the chaos block runs
## AFTER the pirate loop — the spawned pirates idle until the NEXT frame)
## and composes the chase.
func test_tribute_onend_unpaid_raid_through_real_update() -> void:
	var m := _boot(0x5CACA)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	# substitute a single-def tribute deck on a tuned rng (the deck/ctx split
	# means the def itself only DEMANDS; the onEnd lives in update_chaos)
	var tribute_def: Dictionary = {}
	for d in SpaceEventsLib.make_space_chaos_events(ctx.world):
		if String(d["id"]) == "tribute":
			tribute_def = d
	ok(not tribute_def.is_empty(), "the factory deck carries the tribute def (premise)")
	ok(tribute_def.get("end") == null, "the def carries NO end of its own (the deck/ctx split)")
	sim.chaos = ChaosLib.new(RngLib.new(5), [tribute_def])
	sim.chaos.gap = 0.0
	ctx.dna = 40  # UNPAID: the demand 60 stands (the V path never pressed)
	sim.invuln = 0.0
	# warn (the 2.5 window opens)
	sim.update(1.0, _inp())
	ok(sim.chaos.warn_remaining() > 0.0 or sim.chaos.is_active("tribute"),
		"the tribute event spawned (warn or live)")
	eq(float(sim.tributeDemand), 0.0, "warn demands nothing yet (TS:45 — apply only demands)")
	# apply (the warn window closed): demand 60 + the banner through the REAL hud
	sim.update(3.0, _inp())
	eq(float(sim.tributeDemand), 60.0, "apply demanded 60 (TS:852)")
	var b: Variant = _find_banner(m, "THE VOID EMPIRE DEMANDS TRIBUTE")
	ok(b != null, "the demand banner rode the REAL hud (TS:853-857)")
	if b != null:
		# the hud's banner shape renames subtitle → sub (hud.gd show_banner)
		eq(String(b.get("sub", "")), "pay 60 DNA (press V) or face the raid", "the subtitle verbatim")
	# the end: duration [12,12] elapses → onEnd → UNPAID → spawnPirates(3)
	var probe: Variant = _probe_rng(sim)
	var exp_ring: Array = []
	for i in 3:
		var a: float = probe.next() * TAU  # TS:799 — the 3 ring draws
		exp_ring.append({"x": sim.sx + cos(a) * 700.0, "y": sim.sy + sin(a) * 700.0})
	sim.update(13.0, _inp())
	eq(sim.pirates.size(), 3, "the UNPAID tribute's end spawned 3 pirates (TS:543)")
	eq(float(sim.tributeDemand), 0.0, "the demand zeroed after the raid (TS:544)")
	eq(int(sim.rng.state()), int(probe.state()), "the raid consumed exactly the 3 ring draws")
	for i in 3:
		approx(float(sim.pirates[i]["x"]), float(exp_ring[i]["x"]), "pirate %d ring x 700 (TS:800)" % i)
		approx(float(sim.pirates[i]["y"]), float(exp_ring[i]["y"]), "pirate %d ring y 700 (TS:801)" % i)
	# the spawned pirates idled through the spawn frame (the chaos block runs
	# AFTER the pirate loop, TS:519 > :454) — the NEXT frame chases: the
	# closed-form first chase frame for each (d 700 > 30 → accel 300·dt, drag,
	# integrate; d 700 NOT < 60 → no damage branch, no draws)
	probe = _probe_rng(sim)
	sim.update(DT, _inp())
	for i in 3:
		var evx: float = ((sim.sx - float(exp_ring[i]["x"])) / 700.0) * 300.0 * DT * exp(-1.4 * DT)
		approx(float(sim.pirates[i]["vx"]), evx,
			"pirate %d's first chase vx = accel(300·dt toward the ship) then drag exp(−1.4dt) (TS:467-471)" % i)
	eq(int(sim.rng.state()), int(probe.state()), "the chase frame drew nothing (d 700 > 60: no damage branch)")
	_drop(m)


## Pin provenance: sun danger TS:376-382 (d < r+60 strict && invuln ≤ 0 →
## shp −30dt, hurtT 1, cam_shake 4/0.2) + hull regen TS:384-389 (colony pop
## ≥ 5 && d < r+150 strict → shp = min(shpMax, shp + 8dt) — NO invuln gate).
## Seed 0x5CACB. The COMPOSED curve: the ship parked inside BOTH windows (sun
## d 100 < 190; colony window d 150 < r 50 + 150) — the probe derives the
## full 240-frame hull trajectory including the invuln crossover (the start
## invuln 2 shields the sun for the first 120 frames while the regen RUNS:
## +8dt; then −22dt net) — bit-exact at every checkpoint. Complement:
## test_space_sim pins each window separately at single frames; THIS probe
## composes both windows and the invuln decay on one curve.
func test_sun_danger_and_regen_windows_composed() -> void:
	var m := _boot(0x5CACB)
	var sim: Variant = m["sim"]
	_silence_chaos(sim)
	# the colony planet: (250, 0) r 50, FROZEN orbit, pop 20 (≥ 5)
	var p: Dictionary = _place_planet(sim, 0, 250.0, 0.0, 50.0)
	_isolate_planet(sim, 0)
	p["colony"] = {"pop": 20.0, "generations": 0.0}
	# the ship at (100, 0): sun d 100 < 190 ✓; colony d 150 < 200 ✓
	sim.sx = 100.0
	sim.sy = 0.0
	sim.svx = 0.0
	sim.svy = 0.0
	sim.shp = 60.0
	# invuln rides its CONSTRUCTOR value 2.0 — the crossover is the point
	# (no fixture write). The probe replicates the TS per-frame order: the
	# sun gate reads the invuln as decayed by PRIOR frames (:605 runs at the
	# frame END), the regen has no gate (:387).
	var shp := 60.0
	var invuln := 2.0
	var shake_frames := 0
	for f in 240:
		if invuln <= 0.0:  # TS:378 — the frame's gate value
			shp -= 30.0 * DT  # TS:379
			shake_frames += 1
		shp = minf(100.0, shp + 8.0 * DT)  # TS:387 — no invuln gate
		invuln = maxf(0.0, invuln - DT)  # TS:605 — the frame-end decay
		sim.update(DT, _inp())
		if f == 59 or f == 119 or f == 179 or f == 239:
			approx(float(sim.shp), shp, "frame %d: the composed hull curve matches (TS:379/387)" % (f + 1))
	# the FP crossover: the iterated 2 − k/60 decay lands the first damage
	# frame at 122 (121 shielded frames) — the split is derived by the loop
	# above and pinned here; the checkpoints carry the trajectory
	eq(shake_frames, 119, "the derived damage-frame split (121 shielded + 119 drained — the FP crossover, TS:378)")
	approx(shp, 60.0 + (240.0 - shake_frames) * 8.0 * DT - shake_frames * 22.0 * DT,
		"the closed form from the derived split: shielded ×(+8dt) then drained ×(−22dt)", 1e-9)
	_drop(m)


## Pin provenance: the finale trigger TS:552-559 (thriving = colonies with
## pop ≥ 20; ≥ 3 && !finale && !endingDone → the core at (0,−1900) + the
## AWAKENS banner + the bearing objective); the approach d < 60 →
## endingDone (:569-573); endingT += dt post-ending (:576); the dismiss:
## any unconsumed click/key → endingDismissed + dismissT = endingT
## (:577-580, the += precedes the latch); the ending alpha TS:1083-1122
## (the stage's static seam): fade-in min(1, endingT/2) — 2 s; fade-out
## max(0, 1 − (endingT−dismissT)/1.5) — 1.5 s. Seed 0x5CACC. The colonies
## grow through the REAL ff (the trigger frame derived from the growth
## recurrence); the fade windows are evaluated at the SIM's own
## endingT/dismissT timeline values against the probe's own formula.
## Complement: test_space_sim pins the machine frames + the scene test pins
## the static at synthetic values; THIS probe composes the real timeline
## (grown colonies → trigger → approach → dismiss → alpha).
func test_finale_trigger_and_ending_fade_windows() -> void:
	var m := _boot(0x5CACC)
	var sim: Variant = m["sim"]
	_silence_chaos(sim)
	sim.invuln = 0.0
	for i in 3:
		sim.planets[i]["colony"] = {"pop": 19.5, "generations": 0.0}
	# the probe's growth derivation: the trigger frame is the first frame
	# where all three pops ≥ 20 (identical pops → one recurrence)
	var ff_hold := 0.0
	var pop := 19.5
	var trigger_frame := -1
	var f_i := 0
	while trigger_frame < 0 and f_i < 10:
		f_i += 1
		var ts: float = 26.0 if ff_hold > 0.0 else 1.0
		ff_hold = 1.0
		pop += 1.0 * ts * 0.08 * (1.0 + pop * 0.01) * maxf(0.0, 1.0 - pop / 120.0)
		if pop >= 20.0:
			trigger_frame = f_i
	eq(trigger_frame, 2, "the derived trigger frame (the ff PRE-READ: frame 1 ticks ×1 → 19.58; frame 2 ×26 crosses 20)")
	# the drive: two REAL ff frames → the trigger fires ON the derived frame
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	eq(sim.finale, null, "ff frame 1 (×1 by the pre-read): 19.58 < 20 — no trigger yet (TS:306)")
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	ok(sim.finale != null, "the finale spawned at the derived frame (TS:556)")
	var fin: Dictionary = sim.finale
	eq(float(fin["x"]), 0.0, "finale x 0 (TS:556)")
	eq(float(fin["y"]), -1900.0, "finale y −1900 (TS:556)")
	approx(float(fin["t"]), 1.0, "finale.t = dt after the spawn frame (TS:561)")
	ok(_find_banner(m, "THE CHAOS CORE AWAKENS") != null, "the AWAKENS banner rode the REAL hud (TS:557)")
	eq(String(m["stage"].hud_inst.show_objective), "THE CHAOS CORE PULLS — fly 1000px up to the storm",
		"the bearing objective (d 1000 rounded, up, TS:566-568)")
	# the fade-IN at the REAL timeline: the approach frame fires the ending
	sim.sx = 0.0
	sim.sy = -1850.0  # d 50 < 60
	sim.update(1.0, _inp())
	eq(bool(sim.endingDone), true, "d < 60 → endingDone (TS:569-570)")
	approx(float(sim.endingT), 1.0, "endingT started on the flip frame (the same-frame +=, TS:576)")
	# the alpha composed at the SIM's own values — the probe's formula vs the
	# stage's static seam (2 s in)
	var alpha_in: float = minf(1.0, float(sim.endingT) / 2.0)
	approx(alpha_in, 0.5, "the probe's fade-in formula at endingT 1.0 (min(1, e/2))")
	approx(SpaceStageScript.ending_alpha(false, float(sim.endingT), float(sim.dismissT)), alpha_in,
		"the stage's static agrees at the REAL endingT (the 2 s window)")
	# three idle frames → endingT 4.0; the veil holds while un-dismissed
	for i in 3:
		sim.update(1.0, _inp())
	approx(float(sim.endingT), 4.0, "endingT composed to 4.0 (TS:576)")
	approx(SpaceStageScript.ending_alpha(false, float(sim.endingT), float(sim.dismissT)), 1.0,
		"fully veiled at endingT ≥ 2 (the 2 s window closed)")
	# the dismiss: a key press → dismissT = endingT AT the dismiss frame
	# (the += precedes the latch: 4 → 5, dismissT 5)
	sim.update(1.0, _inp({"keys_pressed": ["KeyW"]}))
	eq(bool(sim.endingDismissed), true, "anyKeyPressed dismisses (TS:578)")
	approx(float(sim.dismissT), 5.0, "dismissT = endingT at the dismiss frame (TS:580)")
	# the fade-OUT at the real timeline (1.5 s out): two more frames
	sim.update(1.0, _inp())
	sim.update(1.0, _inp())
	approx(float(sim.endingT), 7.0, "endingT composed to 7.0")
	var alpha_out: float = maxf(0.0, 1.0 - (float(sim.endingT) - float(sim.dismissT)) / 1.5)
	approx(alpha_out, 0.0, "the probe's fade-out formula at Δ 2.0 s — fully clear past 1.5 s")
	approx(SpaceStageScript.ending_alpha(true, float(sim.endingT), float(sim.dismissT)), alpha_out,
		"the stage's static agrees at the REAL dismissal delta (the 1.5 s window)")
	# the midpoint: Δ 0.75 → half-clear (the 1.5 s window's shape)
	approx(maxf(0.0, 1.0 - 0.75 / 1.5), 0.5, "the fade-out's midpoint shape (0.75 s → 0.5)")
	_drop(m)


## Pin provenance: scanPlanet's re-survey TS:1244-1259 verbatim — scanned &&
## resurveyCd > 0 → the recharge toast, no pay (:1249-1251); else
## resurveyCd = 4 (:1253), addDna(3) (:1254-1255), the floatWorld text
## (:1256), persist (:1258); the decay max(0, cd − dt) every update (:550).
## Seed 0x5CACD. The cadence at scale: three cycles driven at the 0.5 s
## grain — the pay fires land EXACTLY every 4.0 s (the 8th half-second
## frame zeroes the cd), the gated scans counted per cycle, the DNA curve
## composed (+3 per cycle). Complement: test_space_sim pins one re-survey +
## the cd gate; THIS probe composes the multi-cycle timeline.
func test_resurvey_cadence_cd4_plus3() -> void:
	var m := _boot(0x5CACD)
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_silence_chaos(sim)
	var p: Dictionary = _place_planet(sim, 0, 1000.0, 0.0, 50.0)
	_isolate_planet(sim, 0)
	p["scanned"] = true
	ctx.dna = 0
	ctx.flags.erase("spaceWorld")

	# the probe's own cadence replay at the 0.5 s grain: cd = max(0, cd−0.5)
	# per update (TS:550); the scan pays only when cd == 0 (and re-arms 4.0)
	var cd := 0.0
	var dna := 0.0
	var gated_per_cycle: Array = []
	for cycle in 3:
		# FIRE: the cd is 0 (cycle 0: fresh; later cycles: the walk zeroed it)
		eq(cd, 0.0, "cycle %d opens at cd 0 (the derived state)" % (cycle + 1))
		sim.scan_planet(p)
		dna += 3.0  # TS:1254-1255
		cd = 4.0    # TS:1253
		eq(float(sim.resurveyCd), 4.0, "cycle %d: the fire armed cd 4 (TS:1253)" % (cycle + 1))
		eq(int(ctx.dna), int(dna), "cycle %d: the fire paid +3 (TS:1254)" % (cycle + 1))
		# the gated walk: 7 halves gated, the 8th zeroes the cd exactly
		var gated := 0
		for half in 8:
			cd = maxf(0.0, cd - 0.5)  # TS:550
			sim.update(0.5, _inp())
			if cd > 0.0:
				gated += 1
				sim.scan_planet(p)
				eq(_scan_toasts(m, "Survey instruments recharging"), 1,
					"cycle %d half-step %d: the recharge toast (TS:1250)" % [cycle + 1, half + 1])
				eq(int(ctx.dna), int(dna), "no pay under the cooldown")
			else:
				eq(cd, 0.0, "cycle %d: the 8th half-step zeroes the cd EXACTLY (4.0 − 8·0.5)" % (cycle + 1))
				break
		gated_per_cycle.append(gated)
	eq(gated_per_cycle, [7, 7, 7], "each cycle gated exactly 7 half-steps (the 0.5 s grain under a 4 s cd)")
	eq(int(ctx.dna), 9, "three cycles paid 3 each: 9 DNA total (TS:1254-1255)")
	ok(ctx.flags.has("spaceWorld"), "each re-survey persisted (TS:1258)")
	_drop(m)
