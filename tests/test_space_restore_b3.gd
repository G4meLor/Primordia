# QC round 1 B3 — the space save/continue restore regression suite.
# The failing QC run: a REAL played space run (4 abducts → splice −15 → cargo 3
# with one "(spliced)" genome Dictionary, debug/panel-seeded colonies, LONG ff
# eco churn, finale spawned) → quit → CONTINUE restored dna/stage/bestiary but
# cargo=0 and colony=0 — the whole spaceWorld blob silently discarded while a
# simpler cargo-1 blob round-tripped fine through 3 CONTINUEs.
# This suite pins the restore across BOTH continue shapes (fresh-process disk
# load + the real boot-registered-stage in-place load) and the all-or-nothing
# gate's hostile inputs. The [space-restore] stdout logs (space_sim.gd) are the
# failure-cause telemetry — a silent gate fall must stay impossible to miss.
# TS source: Spore src/game/space/SpaceStage.ts (frozen), lines cited per pin.
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const MenuStage := preload("res://src/game/menu.gd")
const SpaceStage := preload("res://src/game/space/space_stage.gd")
const SpaceSim := preload("res://src/game/space/space_sim.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const MutationLib := preload("res://src/evo/mutation.gd")

const DT := 1.0 / 60.0
const SEED := 0xB33B3
# the title-card transition legs (test_game_flow.gd's constants)
const OUT_STEPS := 33
const CARD_STEPS := 132
const IN_STEPS := 36

# Dedicated disk slots: the context tests own 90-105, player slots are 0+ —
# this suite lives at 110+ so execution order / parallel agents never matter.
const SLOT_B3_DISK := 110
const SLOT_B3_E2E := 111
const SLOT_B3_FLOW := 112


func _path(n: int) -> String:
	return "user://saves/slot%d.json" % n


func _wipe(n: int) -> void:
	if FileAccess.file_exists(_path(n)):
		DirAccess.remove_absolute(_path(n))


# The QC run's splice write path verbatim (space_sim.merge_cargo): crossover
# with the anomaly/defect budget on the stage rng — the "kiểu splice" genome
# Dictionary that distinguished the failing blob from the working cargo-1 one.
func _splice_cargo_front_pair(sim_v: Variant) -> void:
	sim_v.merge_cargo()


# The M2 input snapshot shape (space_sim.update contract).
func _inp(held: Array = []) -> Dictionary:
	return {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": held, "keys_pressed": [],
	}


# The failing run's play shape, on a bare sim: long-ff eco churn FIRST (the
# run ff'd before/after seeding), then 4 specimens → one splice (cargo 3 with
# one spliced Dictionary genome), one seeded colony, a scan, a ledger entry.
func _play_failing_shape(sim_v: Variant) -> void:
	# the ff leg: 240 frames held-F — the eco/colony floats churn at dt·26
	for i in 240:
		sim_v.update(DT, _inp(["KeyF"]))
	# the arc leg (state written directly — the restore-under-test reads the
	# PERSISTED shapes, not the interaction that produced them)
	sim_v.cargo.append({"genome": GenomeLib.default_genome(), "name": "Specimen One"})
	sim_v.cargo.append({"genome": GenomeLib.default_genome(), "name": "Specimen Two"})
	sim_v.cargo.append({"genome": GenomeLib.default_genome(), "name": "Specimen Three"})
	sim_v.cargo.append({"genome": GenomeLib.default_genome(), "name": "Specimen Four"})
	_splice_cargo_front_pair(sim_v)  # → [Three, Four, "<name> (spliced)"], −15 DNA
	sim_v.planets[0]["colony"] = {"pop": 12.5, "generations": 3.0}
	sim_v.planets[1]["scanned"] = true
	sim_v.abductCount["Glorbus"] = 2
	sim_v.persist_colonies()


# ---- 1. the QC repro: fresh-process CONTINUE (disk round-trip) ------------------

func test_qc_repro_disk_roundtrip_keeps_cargo_and_colony() -> void:
	_wipe(SLOT_B3_DISK)
	var ctx: Variant = Ctx.new(SEED)
	ctx.stage = "space"
	var sim1: Variant = SpaceSim.new(ctx, ctx.rng.branch(), {})
	sim1.on_enter()  # no blob → the fresh generated board (premise)
	eq(sim1.cargo.size(), 0, "fresh sim starts cargo 0 (premise)")
	_play_failing_shape(sim1)
	sim1.on_exit()  # the quit-to-title persist (TS:270-272)
	# premise: the blob in flags has the failing run's shape
	var blob: Variant = JSON.parse_string(String(ctx.flags["spaceWorld"]))
	ok(blob is Dictionary, "persisted blob parses (premise)")
	if blob is Dictionary:
		eq((blob["planets"] as Array).size(), 6, "blob holds 6 planets (premise)")
		eq((blob["cargo"] as Array).size(), 3, "blob holds cargo 3 (premise)")
		eq(float(blob["planets"][0]["colony"]["pop"]), 12.5, "blob holds the colony (premise)")
		ok(blob["cargo"][2]["genome"] is Dictionary, "the spliced row's genome is a Dictionary (the QC's distinguishing mark, premise)")
		ok(String(blob["cargo"][2]["name"]).ends_with("(spliced)"), "the spliced row is the splice product (premise)")
	# the CONTINUE disk round-trip: save → fresh context load
	ok(ctx.save(SLOT_B3_DISK), "save into the slot")
	var loader: Variant = Ctx.new(1)
	ok(loader.load(SLOT_B3_DISK), "CONTINUE load succeeds")
	ok(loader.flags.has("spaceWorld"), "spaceWorld survives the flags round-trip")
	eq(String(loader.flags["spaceWorld"]), String(ctx.flags["spaceWorld"]),
			"spaceWorld string byte-identical across the disk round-trip")
	# land: a FRESH sim on the loaded context (the fresh-process continue shape)
	var sim2: Variant = SpaceSim.new(loader, loader.rng.branch(), {})
	sim2.on_enter()
	eq(sim2.cargo.size(), 3, "CONTINUE keeps cargo (QC r1 B3)")
	if sim2.cargo.size() == 3:
		var saved_blob: Dictionary = JSON.parse_string(String(loader.flags["spaceWorld"]))
		eq(String(sim2.cargo[2]["name"]), String(saved_blob["cargo"][2]["name"]),
				"the spliced specimen keeps its name")
		# gene-exact (per-gene: Dictionary == is insertion-order sensitive and
		# the restore rebuilds the dict onto the defaults; floats carry <=1 ulp
		# stringify/parse noise — fixtures.gd's eps law)
		var saved_genome: Dictionary = saved_blob["cargo"][2]["genome"]
		eq(sim2.cargo[2]["genome"].size(), saved_genome.size(), "the spliced genome keeps its gene count")
		for gene in saved_genome:
			var got: Variant = sim2.cargo[2]["genome"].get(gene)
			var want: Variant = saved_genome[gene]
			if want is float:
				approx(float(got), float(want), "the spliced genome keeps %s" % gene)
			else:
				eq(got, want, "the spliced genome keeps %s" % gene)
	ok(sim2.planets[0]["colony"] != null, "CONTINUE keeps the colony (QC r1 B3)")
	if sim2.planets[0]["colony"] != null:
		eq(float(sim2.planets[0]["colony"]["pop"]), 12.5, "colony pop restored (TS:222-223)")
		eq(float(sim2.planets[0]["colony"]["generations"]), 3.0, "colony generations restored")
	eq(bool(sim2.planets[1]["scanned"]), true, "scanned restored (TS:218-221)")
	eq(int(sim2.abductCount["Glorbus"]), 2, "abduct ledger restored (TS:252-255)")


# ---- 2. the QC repro: the REAL boot shape (in-place CONTINUE on the same stage)
#
# In the real game the space stage registers at BOOT — its sim (planets, rng
# branch, deck) predates the load. continue_slot loads IN PLACE on that same
# context and switch_stage re-enters the SAME stage instance. This is the
# shape the QC run actually drove; the disk test above cannot see it.

func _mk_booted_stage(seed_v: int) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	var game: Variant = GameScript.new(ctx)
	var stage: Variant = SpaceStage.new(game)
	game.register(stage)
	stage._ready()  # the tree would normally fire this at register time
	return {"game": game, "stage": stage, "ctx": ctx, "sim": stage.sim}


func test_qc_repro_inplace_continue_keeps_cargo_and_colony() -> void:
	_wipe(SLOT_B3_E2E)
	var m := _mk_booted_stage(SEED + 1)
	var game: Variant = m["game"]
	var stage: Variant = m["stage"]
	var sim1: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ctx.stage = "space"
	sim1.on_enter()
	_play_failing_shape(sim1)
	sim1.on_exit()
	ok(ctx.save(SLOT_B3_E2E), "quit-to-title flush saved the slot")
	# CONTINUE: load IN PLACE (the menu.continue_slot shape — same Game, same
	# context object, same stage instance), then the stage re-enters
	ok(game.context.load(SLOT_B3_E2E), "in-place CONTINUE load succeeds")
	ok(game.context.flags.has("spaceWorld"), "loaded flags carry spaceWorld")
	stage.on_enter()  # switch_stage("space") → the SAME sim instance re-enters
	var sim2: Variant = stage.sim
	ok(is_same(sim1, sim2), "the boot-built sim instance serves the CONTINUE (the real shape)")
	eq(sim2.cargo.size(), 3, "in-place CONTINUE keeps cargo (QC r1 B3)")
	ok(sim2.planets[0]["colony"] != null, "in-place CONTINUE keeps the colony (QC r1 B3)")
	if sim2.planets[0]["colony"] != null:
		eq(float(sim2.planets[0]["colony"]["pop"]), 12.5, "in-place colony pop restored")
	eq(int(sim2.abductCount["Glorbus"]), 2, "in-place ledger restored")
	m["game"].free()  # the RID-leak ceiling gate counts un-freed test boots


# ---- 3. the REAL menu CONTINUE flow — the QC r1 B3 artifact discriminator -----
#
# The QC3 probe measured cargo=0/colonies=0 right after continue_slot(0) — but
# continue_slot only LOADS the context (context.stage reads "space" at load
# time) while switch_stage — and with it sim.on_enter/_restore_world — fires
# only when the 0.55s+ title-card fade lands. Counting before the fade reads
# the FRESH boot sim (cargo 0, colonies 0, ship at the (0,-900) spawn, planets
# of the right kinds because the kind ring is constant) — the exact signature
# the QC reported on a blob that this suite proves restores correctly. The pin:
# a full menu.continue_slot flow MUST land restored after the fade.

func _booted_game(seed_v: int) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	var g: Variant = GameScript.new(ctx)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(g)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	g.register(MenuStage.new(g))
	var stage: Variant = SpaceStage.new(g)
	g.register(stage)
	if stage.sim == null:
		stage._ready()  # headless boots may not fire _ready inline — force it
	g.start()
	return {"game": g, "stage": stage, "ctx": ctx, "sim": stage.sim}


func test_menu_continue_flow_lands_restored_after_the_fade() -> void:
	_wipe(SLOT_B3_FLOW)
	# run: play the failing shape on a booted game, quit-flush, save
	var m := _booted_game(SEED + 6)
	var sim1: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	ctx.stage = "space"
	sim1.on_enter()
	_play_failing_shape(sim1)
	sim1.on_exit()
	ok(ctx.save(SLOT_B3_FLOW), "the run's quit flush saved")
	m["game"].free()  # drop the run's game (the QC3 fresh process follows)
	# CONTINUE: a FRESH booted game (the QC3 fresh process) → menu.continue_slot
	var m2 := _booted_game(SEED + 7)  # a DIFFERENT boot seed, like a real relaunch
	var g2: Variant = m2["game"]
	var stage2: Variant = m2["stage"]
	var sim2: Variant = m2["sim"]
	var menu: Variant = g2.stages["menu"]
	menu.continue_slot(SLOT_B3_FLOW)
	eq(String(g2.context.stage), "space", "context.stage reads space at LOAD time (the QC3 'landed' trap)")
	eq(g2.current.id, "menu", "the stage has NOT switched yet — the fade is pending")
	eq(sim2.cargo.size(), 0, "pre-fade the boot sim is still fresh (the QC3 reading, documented)")
	# walk the fade: out → title card → in → switch_stage fired mid-way
	g2.step_for_testing(OUT_STEPS + CARD_STEPS + IN_STEPS, DT)
	eq(String(g2.current.id), "space", "the fade lands in space")
	eq(sim2.cargo.size(), 3, "the landing restores cargo (QC r1 B3 resolved)")
	ok(sim2.planets[0]["colony"] != null, "the landing restores the colony")
	if sim2.planets[0]["colony"] != null:
		# the walk's remaining live frames tick the stage — the pop grows from
		# the restored 12.5, not from a fresh 1.0 (the restored-vs-fresh tell)
		var pop := float(sim2.planets[0]["colony"]["pop"])
		ok(pop >= 12.5 and pop < 13.5, "the landing restores the colony pop then grows live (got %f)" % pop)
	g2.free()


# ---- 3. hostile blobs: the gate's all-or-nothing contract stays (parity TS) -----

func test_corrupt_blob_falls_to_fresh_board_without_crash() -> void:
	var ctx: Variant = Ctx.new(SEED + 2)
	ctx.stage = "space"
	ctx.flags["spaceWorld"] = "{\"planets\": [oeps"  # truncated garbage
	var sim: Variant = SpaceSim.new(ctx, ctx.rng.branch(), {})
	eq(sim.planets.size(), 6, "constructor built the fresh system (premise)")
	sim.on_enter()  # must not crash — the parse fall reads as "no blob" (TS:266)
	eq(sim.planets.size(), 6, "no crash — the fresh board stands")
	eq(sim.cargo.size(), 0, "no cargo from a corrupt blob")
	ok(sim.planets[0]["colony"] == null, "no colony from a corrupt blob")


func test_wrong_length_blob_all_or_nothing_fall() -> void:
	var ctx: Variant = Ctx.new(SEED + 3)
	ctx.stage = "space"
	# a VALID-JSON blob whose planets array is 5 rows: the TS gate nest puts
	# cargo/ledger/ending INSIDE the shapes check (the trailing :265 closer) —
	# a wrong-length blob discards the WHOLE restore (fresh board stays)
	var rows: Array = []
	for i in 5:
		rows.append({"id": i, "name": "P%d" % i, "orbitR": 500.0, "angle": 1.0,
				"orbitSpeed": 0.01, "r": 50.0, "hue": 100.0, "kind": "lush",
				"ring": false, "scanned": false, "colony": null, "eco": null})
	ctx.flags["spaceWorld"] = JSON.stringify({
		"planets": rows,
		"cargo": [{"genome": GenomeLib.default_genome(), "name": "Lost"}],
		"abductCount": {"Glorbus": 9}, "endingDone": true, "endingDismissed": false,
	})
	var sim: Variant = SpaceSim.new(ctx, ctx.rng.branch(), {})
	sim.on_enter()
	eq(sim.cargo.size(), 0, "all-or-nothing: cargo does not restore from a 5-planet blob (TS:201-265)")
	ok(sim.planets[0]["colony"] == null, "all-or-nothing: colony does not restore")
	eq(sim.endingDone, false, "all-or-nothing: endingDone does not restore (same gate)")
	eq(int(sim.abductCount.get("Glorbus", 0)), 0, "all-or-nothing: ledger does not restore (same gate)")


# ---- 4. the non-finite hardening: a stray inf/nan degrades PER-FIELD (TS parity)
#
# TS JSON.stringify null-ifies non-finite floats; the native stringify writes
# the INVALID-JSON tokens `nan`/`inf` which parse_string rejects WHOLESALE —
# one stray float would brick the whole blob (fresh board) where TS keeps the
# rest. persist_colonies sanitizes; the guards then drop only the dead field.

func test_nonfinite_degrades_per_field_not_whole_blob() -> void:
	var ctx: Variant = Ctx.new(SEED + 5)
	ctx.stage = "space"
	var sim1: Variant = SpaceSim.new(ctx, ctx.rng.branch(), {})
	sim1.cargo.append({"genome": GenomeLib.default_genome(), "name": "Specimen One"})
	sim1.planets[0]["colony"] = {"pop": INF, "generations": 2.0}  # the stray float
	sim1.planets[1]["colony"] = {"pop": 14.0, "generations": 1.0}  # the healthy one
	sim1.persist_colonies()
	# the persisted blob must still PARSE (no `inf`/`nan` token anywhere)
	var blob: Variant = JSON.parse_string(String(ctx.flags["spaceWorld"]))
	ok(blob is Dictionary, "a non-finite colony pop must not brick the blob (the QC r1 B3 stringify suspicion)")
	if blob is Dictionary:
		eq((blob["planets"] as Array).size(), 6, "the planets survive the sanitized row")
		# the colony DICT survives with pop null — the TS stringify shape
		# ({ "generations": 2, "pop": null }), not a deleted row
		eq(blob["planets"][0]["colony"].get("pop"), null, "the non-finite pop writes null (the TS stringify shape)")
		eq(float(blob["planets"][0]["colony"]["generations"]), 2.0, "the sibling field rides untouched")
		eq(float(blob["planets"][1]["colony"]["pop"]), 14.0, "the healthy colony rides untouched")
		eq((blob["cargo"] as Array).size(), 1, "cargo survives beside the sanitized row")
	# the restore degrades per-field: the dead colony falls back to fresh, the
	# rest of the blob restores
	var sim2: Variant = SpaceSim.new(ctx, ctx.rng.branch(), {})
	sim2.on_enter()
	ok(sim2.planets[0]["colony"] == null, "the non-finite colony restore falls back to fresh (TS:222-225)")
	if sim2.planets[1]["colony"] != null:
		eq(float(sim2.planets[1]["colony"]["pop"]), 14.0, "the healthy colony restores")
	eq(sim2.cargo.size(), 1, "cargo restores beside the degraded field")


# ---- 5. the gate stays open for a blob that carries EVERYTHING at once ----------

func test_full_blob_restores_ending_and_cargo_together() -> void:
	var ctx: Variant = Ctx.new(SEED + 4)
	ctx.stage = "space"
	var sim1: Variant = SpaceSim.new(ctx, ctx.rng.branch(), {})
	sim1.cargo.append({"genome": GenomeLib.default_genome(), "name": "Specimen One"})
	sim1.abductCount["Glorbus"] = 3
	sim1.endingDone = true
	sim1.endingDismissed = true
	sim1.planets[0]["colony"] = {"pop": 20.0, "generations": 4.0}
	sim1.persist_colonies()
	var loader: Variant = Ctx.new(2)
	_wipe(SLOT_B3_DISK)  # reuse the disk slot (this file owns it)
	ok(ctx.save(SLOT_B3_DISK), "save")
	ok(loader.load(SLOT_B3_DISK), "load")
	var sim2: Variant = SpaceSim.new(loader, loader.rng.branch(), {})
	sim2.on_enter()
	eq(sim2.cargo.size(), 1, "cargo restored with the ending block present (TS:247)")
	eq(sim2.endingDone, true, "a won run stays won (TS:256-264)")
	eq(sim2.endingDismissed, true, "dismissed ending restored (TS:261)")
	eq(float(sim2.endingT), 99.0, "dismissed ending sleeps (endingT 99, TS:262)")
	ok(sim2.finale == null, "no stale orb after a dismissed ending (TS:262-263)")
	eq(float(sim2.planets[0]["colony"]["pop"]), 20.0, "colony restored beside the ending block")
