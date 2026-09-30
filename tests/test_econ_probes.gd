# Task 10 econ probes — the §5.2 econ-parity criterion through the REAL cell
# stage: each probe boots the full Game + real MenuStage + real CellStage on a
# pinned seed with FORCED world traits (start_new_game's world re-derive, then
# the trait list swapped in before the fresh stage registration), walks the
# real transition/card, and drives a scripted window whose eco observations are
# pinned to values extracted verbatim from the frozen TS repo (scratch vitest
# tools/econ-probe-pin.test.ts, extracted 2026-09-30; scenario shape identical
# on both sides — see _boot's header for the D1 stream-alignment contract).
#
# Probes (econ-probe.test.ts wave + task-10 brief):
#   iron_gut    — ecoSeed carnivore 1.4 roster bend + meal_dna_mult 1.2 kill DNA
#   hungry_bloom— herb_drain_mult 1.6 flora drain over 20 s
#   swift_world — swarm bonus species + growth 1.25 / speciation 1.5
#   calm_veil   — predator 0.6 pull + growth 1.05 / speciation 0.8
#   corpse_tide — the combo through the STAGE kill path (kill_ent → drop_corpse
#                 → the tide line), 8% population budget
#   kin_memory  — the ONE grudge ledger through real stage kills
#   stacked     — hungry_bloom + swift_world together (the TS stacked pair)
# Plus the 1000-seed determinism gate (T3 bot-arc A/B pattern at stage level:
# seed → 600-tick sim with the T6 scripted messy input → quantized hash; A == B
# per seed across a second build — sharded across child processes to keep the
# runtime near 2 min, tests/econ_det_shard.gd).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const RngLib := preload("res://src/core/rng.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const ChaosScript := preload("res://src/game/chaos.gd")
const CellEventsScript := preload("res://src/game/cell/cell_events.gd")
const TraitsScript := preload("res://src/evo/world_traits.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const DT := 1.0 / 60.0
const TRANSITION_POLL := 600
# out 0.55 → card 2.2 → in 0.6 in fixed steps; the poll lands inside the card
# (context.stage flips at the out→switch boundary), so walk card + in = 168.
const CARD_IN_STEPS := 168
const WINDOW := 1200  # 20 s of stage time — under the ~24.5 s first-chaos gap

# Extraction date for every TS-derived pin below: 2026-09-30, from
# Spore/tools/econ-probe-pin.test.ts (npx vitest run --config
# tools/vitest.config.ts tools/econ-probe-pin.test.ts). Scenario: see _boot.


# ---- scenario scaffold ---------------------------------------------------------

## Real boot: Game + menu → 5 title steps → start_new_game(seed) → force the
## world traits/combo flags AFTER the world re-derive → register a FRESH cell
## stage (single eco bootstrap on the fresh ctx stream, forced world) → D1
## stream repair → transition walk → the live stage just past its card.
##
## D1 stream repair (task-3 divergence): native CellSim._init spends the stage
## branch's FIRST draw on the cosmetic playerSeed where TS spends it on the
## eco branch (TS draws playerSeed from global Math.random). The repair rewinds
## the sim's rng to the branch's initial state (= floori(ctxFirstNext·0xffffffff),
## the branch() formula) and replays the bootstrap WITHOUT the playerSeed draw,
## so every subsequent draw — eco branch, roster, chaos branch, kelp, pellets,
## the whole runtime — is stream-aligned with a same-seed TS run. The stale
## playerSeed value stays (cosmetic painter seed only).
func _boot(seed_v: int, trait_ids: Array, combo_ids: Array = []) -> Variant:
	var ctx: Variant = ContextScript.new(seed_v)
	# OUT-OF-TREE boot: run.gd drives tests synchronously inside _initialize —
	# the main loop never reaches a frame, so tree-entered nodes never fire
	# _ready. The game stays unparented; the cell stage's _ready (the sim
	# bootstrap) is invoked ONCE manually below (the engine would never call it
	# here, so there is no double-build risk). Nothing in the boot path needs
	# the viewport: the sim never renders, and vw/vh keep the 800×600 defaults
	# (the TS fakeCanvas size — no clicks, so the mapping is never exercised).
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.set_process_unhandled_input(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.step_for_testing(5, DT)
	game.current.start_new_game(0, "normal", seed_v)
	var tdefs: Array = []
	for id in trait_ids:
		tdefs.append(_trait(id))
	ctx.world["traits"] = tdefs
	for cid in combo_ids:
		ctx.world["comboFired"][cid] = true
	game.register(CellStageScript.new(game))
	var cell: Variant = game.stages["cell"]
	cell._ready()  # the ONE sim bootstrap (single eco build on the fresh ctx stream)
	_repair_stream(cell.sim, ctx, seed_v)
	var steps := 0
	while ctx.stage != "cell" and steps < TRANSITION_POLL:
		game.step_for_testing(1, DT)
		steps += 1
	if ctx.stage != "cell":
		failures.append("boot: cell stage not reached within %d steps" % TRANSITION_POLL)
	game.step_for_testing(CARD_IN_STEPS, DT)
	return game


func _trait(id: String) -> Variant:
	for t in TraitsScript.TRAIT_DEFS:
		if String(t["id"]) == id:
			return t
	failures.append("no trait def '%s'" % id)
	return {}


func _repair_stream(sim: Variant, ctx: Variant, seed_v: int) -> void:
	var cr: Variant = RngLib.new_from(seed_v)
	var s0: int = floori(cr.next() * 4294967295.0)  # branch() multiplies 0xffffffff
	sim.rng.set_state(s0)
	sim.eco = EcoScript.new(sim.rng.branch())
	sim.seed_ecology()
	sim.eco.designate_kin_tag(ctx.world)
	ctx.eco = sim.eco
	sim.chaos = ChaosScript.new(sim.rng.branch(), CellEventsScript.make_cell_chaos_events(ctx.world))
	sim.deckSeed = ctx.world.seed
	sim.kelp.clear()
	for i in 40:
		var a: float = sim.rng.next() * TAU
		var r: float = sim.rng.range(300.0, 2400.0 * 0.95)
		sim.kelp.append({
			"x": cos(a) * r, "y": sin(a) * r,
			"len": sim.rng.range(40.0, 110.0), "seed": sim.rng.range(0.0, 10.0),
		})
	sim.pellets.clear()
	for i in 30:
		sim.spawn_pellet("plant")


## `steps` fixed steps with kill_ent seams at scripted window steps (the T4
## sanctioned kill path — kill_ent IS the stage kill: notify_kill, bumpKill,
## grudge, drop_corpse, meat, float text all fire inside).
func _run_window(game: Variant, steps: int, kills: Array = []) -> void:
	var kill_at := {}
	for k in kills:
		kill_at[int(k["step"])] = int(k["species_index"])
	var sim: Variant = game.current.sim
	for f in steps:
		if kill_at.has(f):
			var sp: Dictionary = sim.eco.living()[int(kill_at[f])]
			var e: Dictionary = sim.spawn_ent(sp, float(sim.px) + 500.0, float(sim.py), {}, {})
			e["hp"] = 0.5
			sim.kill_ent(e)
		game.step_for_testing(1, DT)


func _drop(game: Variant) -> void:
	# break the overlay Callable cycles before free (test_game_flow pattern)
	game.hud = {}
	game.editor = {}
	game.pause = {}
	game.free()
	var dir := DirAccess.open("user://saves")
	if dir != null:
		dir.remove("slot0.json")


func _diets(sim: Variant) -> Array:
	var out: Array = []
	for sp in sim.eco.species:
		out.append(String(sp["genome"]["diet"]))
	return out


func _pops1000(sim: Variant) -> Array:
	var out: Array = []
	for sp in sim.eco.species:
		out.append(floori(float(sp["pop"]) * 1000.0))
	return out


func _carnivores(sim: Variant) -> int:
	var n := 0
	for sp in sim.eco.species:
		if String(sp["genome"]["diet"]) == "carnivore":
			n += 1
	return n


# ---- probes --------------------------------------------------------------------

## Pin provenance: tools/econ-probe-pin.test.ts "iron_gut", seed 0x1E07,
## extracted 2026-09-30. ecoSeed carnivore 1.4 → carnPull 0.2 flips sp0+sp5;
## meal_dna_mult 1.2 lands on the same-seed meal (16 vs 13 baseline DNA).
func test_iron_gut_roster_bend_and_meal_dna() -> void:
	var g1: Variant = _boot(0x1E07, [])
	_run_window(g1, 130)
	eq(_diets(g1.current.sim), ["herbivore", "omnivore", "carnivore", "herbivore",
			"carnivore", "herbivore", "omnivore"], "baseline roster diets (TS verbatim)")
	eq(_pops1000(g1.current.sim), [7121, 4110, 4906, 9021, 8745, 5111, 9062],
			"baseline roster pops×1000 (TS verbatim)")
	approx(float(g1.current.sim.eco.flora), 60.130761656, "baseline flora (TS)", 1e-9)
	eq(_carnivores(g1.current.sim), 2, "baseline carnivore count")
	_drop(g1)
	var g2: Variant = _boot(0x1E07, ["iron_gut"])
	_run_window(g2, 130)
	eq(_diets(g2.current.sim), ["carnivore", "omnivore", "carnivore", "herbivore",
			"carnivore", "carnivore", "omnivore"], "iron_gut roster diets — sp0+sp5 flipped to carnivore (TS verbatim)")
	eq(_pops1000(g2.current.sim), [7068, 4110, 4906, 9021, 8745, 5088, 9062],
			"iron_gut roster pops×1000 (TS verbatim)")
	eq(g2.current.sim.eco.mods, {"meal_dna_mult": 1.2}, "eco mods refreshed from the world each batch (TS verbatim)")
	eq(_carnivores(g2.current.sim), 4, "hunter pressure: carnivores 2 → 4")
	approx(float(g2.current.sim.eco.flora), 60.162760469, "iron_gut flora (TS)", 1e-9)
	# meal DNA through the real kill path, after the first batch refreshed mods
	var sim: Variant = g2.current.sim
	var sp: Dictionary = sim.eco.living()[0]
	var e: Dictionary = sim.spawn_ent(sp, float(sim.px) + 500.0, float(sim.py), {}, {})
	e["hp"] = 0.5
	var dna0: int = int(g2.context.dna)
	sim.kill_ent(e)
	eq(int(g2.context.dna) - dna0, 16, "iron_gut kill DNA (TS 16 = meal 13 × 1.2)")
	_drop(g2)


## Pin provenance: tools/econ-probe-pin.test.ts "hungry_bloom", seed 0x1E08,
## extracted 2026-09-30. herb_drain_mult 1.6 strips flora faster over the same
## 20 s window; the grazer pop quantizes identically (the drain shows on flora).
func test_hungry_bloom_flora_drain() -> void:
	var g1: Variant = _boot(0x1E08, [])
	_run_window(g1, WINDOW)
	approx(float(g1.current.sim.eco.flora), 64.689237599, "baseline flora (TS)", 1e-9)
	eq(_pops1000(g1.current.sim), [6700, 7830, 4186, 7411, 6277, 6815, 6459],
			"baseline pops×1000 (TS verbatim)")
	eq(g1.current.sim.eco.mods, {}, "baseline mods empty")
	_drop(g1)
	var g2: Variant = _boot(0x1E08, ["hungry_bloom"])
	_run_window(g2, WINDOW)
	approx(float(g2.current.sim.eco.flora), 64.104022922, "hungry_bloom flora (TS)", 1e-9)
	eq(_pops1000(g2.current.sim), [6700, 7830, 4186, 7411, 6277, 6815, 6479],
			"trait pops×1000 (TS verbatim)")
	eq(g2.current.sim.eco.mods, {"herb_drain_mult": 1.6}, "herb_drain_mult wire (TS verbatim)")
	_drop(g2)


## Pin provenance: tools/econ-probe-pin.test.ts "swift_world", seed 0x1E09,
## extracted 2026-09-30. swarm weight 1.3 appends the small-fast bonus species
## (size clamped to the 0.6 floor); growth 1.25 lifts every pop.
func test_swift_world_swarm_species_survival() -> void:
	var g1: Variant = _boot(0x1E09, [])
	_run_window(g1, WINDOW)
	eq(g1.current.sim.eco.species.size(), 7, "baseline roster 7 species")
	eq(_pops1000(g1.current.sim), [8303, 8189, 7201, 8751, 5392, 7406, 7250],
			"baseline pops×1000 (TS verbatim)")
	_drop(g1)
	var g2: Variant = _boot(0x1E09, ["swift_world"])
	_run_window(g2, WINDOW)
	var sim: Variant = g2.current.sim
	eq(sim.eco.species.size(), 8, "swarm bonus species appended (TS verbatim)")
	eq(_pops1000(sim), [8588, 8466, 7286, 9050, 5450, 7663, 7497, 6073],
			"trait pops×1000 — the small-fast line alive at 20 s (TS verbatim)")
	var sp7: Dictionary = sim.eco.species[7]
	eq(String(sp7["id"]), "sp7_g1xdo9", "bonus species id (eco-stream aligned, TS verbatim)")
	eq(String(sp7["genome"]["diet"]), "herbivore", "bonus species grazer")
	approx(float(sp7["genome"]["size"]), 0.6, "bonus size at the 0.6 clamp floor", 1e-9)
	eq(int(sp7["genome"]["flagella"]), 5, "bonus flagella 5")
	eq(int(sp7["genome"]["cilia"]), 3, "bonus cilia 3")
	eq(int(sp7["genome"]["hue"]), 210, "bonus hue 210")
	eq(String(sp7["genome"]["pattern"]), "glow", "bonus pattern glow")
	eq(sim.eco.mods, {"growth_mult": 1.25, "speciation_mult": 1.5}, "swift mods (TS verbatim)")
	approx(float(sim.eco.flora), 63.657589586, "swift flora (TS)", 1e-9)
	_drop(g2)


## Pin provenance: tools/econ-probe-pin.test.ts "calm_veil", seed 0x1E0A,
## extracted 2026-09-30. predator 0.6 thins the carnivore pull (carnW 0.6 →
## herbPull 0.2 by the formula; carnPull is 0 — carnW < 1 and herbW = 1): at
## this seed the pulls miss every template (the
## diets match baseline — the honest pinned outcome), the quiet-world mods and
## the pop drift show instead.
func test_calm_veil_predator_thinning() -> void:
	var g1: Variant = _boot(0x1E0A, [])
	_run_window(g1, WINDOW)
	eq(_carnivores(g1.current.sim), 2, "baseline carnivores (TS verbatim)")
	eq(_diets(g1.current.sim), ["herbivore", "omnivore", "carnivore", "herbivore",
			"carnivore", "herbivore", "omnivore"], "baseline diets (TS verbatim)")
	eq(_pops1000(g1.current.sim), [7201, 6548, 6449, 9114, 6764, 5168, 7638],
			"baseline pops×1000 (TS verbatim)")
	_drop(g1)
	var g2: Variant = _boot(0x1E0A, ["calm_veil"])
	_run_window(g2, WINDOW)
	var sim: Variant = g2.current.sim
	eq(_diets(sim), ["herbivore", "omnivore", "carnivore", "herbivore",
			"carnivore", "herbivore", "omnivore"], "calm_veil diets — the 0.2 pulls miss at this seed (TS verbatim)")
	eq(_carnivores(sim), 2, "carnivore count unchanged (TS verbatim)")
	eq(sim.eco.mods, {"growth_mult": 1.05, "speciation_mult": 0.8}, "calm_veil mods (TS verbatim)")
	eq(_pops1000(sim), [7251, 6592, 6453, 9175, 6746, 5204, 7689],
			"calm_veil pops×1000 — the quiet-world drift (TS verbatim)")
	_drop(g2)


## Pin provenance: tools/econ-probe-pin.test.ts "corpse_tide", seed 0x1E0B,
## extracted 2026-09-30. The combo rides comboFired (the TS probe's own seam);
## six scripted kill_ent calls burst the tide line; the 8% budget holds.
func test_corpse_tide_scavenger_budget_through_stage_kills() -> void:
	var g: Variant = _boot(0x1E0B, ["iron_gut", "toxin_sea"], ["corpse_tide"])
	var sim: Variant = g.current.sim
	ok(WorldGenomeScript.combo_active(g.context.world, "corpse_tide"), "combo live")
	_run_window(g, WINDOW, [
		{"step": 5, "species_index": 0}, {"step": 15, "species_index": 0},
		{"step": 25, "species_index": 0}, {"step": 35, "species_index": 0},
		{"step": 45, "species_index": 0}, {"step": 55, "species_index": 0},
	])
	eq(int(g.context.world_stats["kills"]), 6, "six stage kills paid")
	var tide: Variant = sim.eco.tide_species()
	ok(tide != null, "the tide line exists")
	if tide != null:
		eq(String(tide["id"]), "sp7_1vy724", "tide line id (TS verbatim)")
		ok(bool(tide.get("tideBorn", false)), "tideBorn flag")
		approx(float(tide["pop"]), 3.797414, "tide pop after the drift window (TS)", 1e-6)
		var pop_sum := 0.0
		for sp in sim.eco.living():
			pop_sum += float(sp["pop"])
		ok(float(tide["pop"]) <= pop_sum * 0.08 + 1e-9,
				"budget: tide %.3f ≤ 8%% of popSum %.3f" % [float(tide["pop"]), pop_sum])
	eq(int(g.context.dna), 150, "kill DNA total (TS verbatim)")
	approx(float(sim.eco.corpses), 5.0925, "corpse ledger after 6 kills + decay (TS)", 1e-9)
	approx(float(sim.eco.flora), 64.664526307, "corpse_tide flora (TS)", 1e-9)
	eq(_pops1000(sim), [0, 10188, 8567, 8276, 7882, 5219, 5433, 3797],
			"roster pops×1000 — the hunted line extinct, the tide riding its cap (TS verbatim)")
	_drop(g)


## Pin provenance: tools/econ-probe-pin.test.ts "kin_memory", seed 0x1E0C,
## extracted 2026-09-30. designate_kin_tag tags the first herding non-kin line
## at bootstrap; three real stage kills write grudge 3 and exactly one
## 'the kin are watching' warning toast.
func test_kin_memory_grudge_through_stage_kills() -> void:
	var g: Variant = _boot(0x1E0C, ["kin_memory"])
	var sim: Variant = g.current.sim
	var host_i := -1
	for i in sim.eco.species.size():
		if bool(sim.eco.species[i].get("kin_tag", false)):
			host_i = i
	eq(host_i, 0, "kin host is the first herding line (TS verbatim)")
	# reroute the hud toast dict entry into a recorder (read at call time)
	var toasts: Array = []
	g.hud["toast"] = func(text: String, kind: String, icon: String) -> void:
		toasts.append([text, kind, icon])
	_run_window(g, 300, [
		{"step": 5, "species_index": host_i},
		{"step": 65, "species_index": host_i},
		{"step": 125, "species_index": host_i},
	])
	var host: Dictionary = sim.eco.species[host_i]
	eq(String(host["id"]), "sp0_dtg4io", "kin host id (TS verbatim)")
	eq(float(host.get("grudge", 0.0)), 3.0, "grudge 3 after three stage kills (TS verbatim)")
	eq(float(host.get("harass", 0.0)), 0.0, "no presses without AI engagement (TS verbatim)")
	var warnings := 0
	for t in toasts:
		if String(t[0]).contains("the kin are watching"):
			warnings += 1
	eq(warnings, 1, "exactly one warning precedes the ledger (catalog I.b)")
	_drop(g)


## Pin provenance: tools/econ-probe-pin.test.ts "stacked", seed 0x1E0D,
## extracted 2026-09-30. The TS stacked pair (hungry_bloom + swift_world):
## both mod sets land together and the swarm bonus is present.
func test_stacked_hungry_bloom_swift_world() -> void:
	var g: Variant = _boot(0x1E0D, ["hungry_bloom", "swift_world"])
	_run_window(g, WINDOW)
	var sim: Variant = g.current.sim
	eq(sim.eco.species.size(), 8, "stacked roster keeps the swarm bonus (TS verbatim)")
	eq(_pops1000(sim), [5770, 10270, 6744, 10275, 4374, 8446, 8479, 8238],
			"stacked pops×1000 (TS verbatim)")
	eq(sim.eco.mods, {"growth_mult": 1.25, "speciation_mult": 1.5, "herb_drain_mult": 1.6},
			"stacked mods (TS verbatim)")
	approx(float(sim.eco.flora), 62.712730211, "stacked flora — the worst-strip + growth stack (TS)", 1e-9)
	_drop(g)


## The adoption fix this task surfaced (TS CellStage.ts:237-248): a NEW LIFE
## re-seeds the eco at on_enter; a CONTINUE adopts the loaded roster as-is.
func test_on_enter_eco_adoption_and_new_life_reseed() -> void:
	var ctx: Variant = ContextScript.new(0x0BEF)
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.stages["cell"]._ready()  # out-of-tree boot — see _boot's header
	game.step_for_testing(5, DT)
	var sim: Variant = game.stages["cell"].sim
	var boot_eco: Variant = sim.eco
	# NEW LIFE: ctx.eco nulled by start_new_game → on_enter must re-seed
	game.current.start_new_game(0, "normal", 0x0BEF)
	ok(ctx.eco == null, "start_new_game nulled the eco")
	game.step_for_testing(TRANSITION_POLL + CARD_IN_STEPS, DT)
	ok(ctx.stage == "cell", "cell reached")
	ok(sim.eco != boot_eco, "NEW LIFE re-seeded the ecosystem at on_enter")
	ok(ctx.eco == sim.eco, "the re-seeded eco is wired onto the context")
	# CONTINUE: a loaded roster is adopted as-is (no silent resurrection).
	# The real flow leaves the cell stage first (its on_exit writes ctx.eco),
	# the load then replaces it, and the re-entry adopts — mirror exactly that.
	game.switch_stage("menu")
	var loaded: Variant = EcoScript.new(RngLib.new_from(77))
	loaded.add_species(GenomeScript.default_genome(), 3)
	ctx.eco = loaded
	game.switch_stage("cell")
	ok(sim.eco == loaded, "CONTINUE adopts the loaded roster as-is")
	ok(sim.eco.species.size() == 1 and float(sim.eco.species[0]["pop"]) == 3.0,
			"the loaded sterile roster stays dead — no free reseed exploit")
	_drop(game)


# ---- 1000-seed determinism (T3 pattern at stage level) -------------------------

## Seed → 600-tick cell sim (the T6 scripted messy input) → quantized state
## hash; every seed self-consistent across a second build (A == B). 1000 seeds
## sharded across child godot processes (tests/econ_det_shard.gd) to keep the
## wall time near 2 min on this box.
func test_determinism_1000_seeds_a_vs_b() -> void:
	var shards := 6
	var total := 1000
	var per := int(ceil(float(total) / float(shards)))
	var pids: Array = []
	var outs: Array = []
	for i in shards:
		var from_s := i * per
		var to_s := mini((i + 1) * per, total)
		if from_s >= to_s:
			break
		var out_path := "user://det_shard_%d_%d.json" % [OS.get_process_id(), i]
		var args: PackedStringArray = [
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", ProjectSettings.globalize_path("res://tests/econ_det_shard.gd"),
			"--", ProjectSettings.globalize_path(out_path), str(from_s), str(to_s),
		]
		var pid: int = OS.create_process(OS.get_executable_path(), args)
		if pid < 0:
			failures.append("determinism: failed to spawn shard %d" % i)
			return
		pids.append(pid)
		outs.append(out_path)
	var deadline := Time.get_ticks_msec() + 300_000
	for j in pids.size():
		var pid: int = pids[j]
		while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(250)
		if OS.is_process_running(pid):
			OS.kill(pid)
			failures.append("determinism: shard %d timed out" % j)
			return
	# collect: the shard's own gate is A==B per seed (its exit code + JSON);
	# the parent verifies coverage and re-checks the diverged list
	var covered := {}
	for j in pids.size():
		var out_path: String = outs[j]
		if not FileAccess.file_exists(out_path):
			failures.append("determinism: shard %d wrote no JSON (crashed?)" % j)
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_path))
		if not (parsed is Dictionary):
			failures.append("determinism: shard %d JSON unparsable" % j)
			continue
		var from_s: int = int(parsed["from"])
		var to_s: int = int(parsed["to"])
		var bad: Array = parsed["bad"]
		if not bad.is_empty():
			failures.append("determinism: shard %d diverged seeds %s" % [j, str(bad)])
		for s in range(from_s, to_s):
			covered[s] = true
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out_path))
	for s in total:
		if not covered.has(s):
			failures.append("determinism: seed %d not covered" % s)
			break
	eq(covered.size(), total, "1000 seeds covered across shards")
