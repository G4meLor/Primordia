# WorldStage creature pins — Task 9. The worldStage.test.ts creature-facing
# bits, verified against the CURRENT TS tests (the frozen repo's war_graves /
# narration-reset / bio_tell work is wired there as of 2026-09-30) and ported
# where they touch the creature stage:
#   - creature-stage SAVE round-trip: persist_state → slot JSON → load →
#     flags.packGenomes rides (the autosave-flush seam — TS CreatureStage
#     .persistState:344 reaches game.saveAll/autosave through the optional
#     call, game.ts:239/296; the native stage forwards it as of this task).
#   - CONTINUE with a creature save boots the creature stage and RESTORES the
#     pack from flags (sim on_enter livePack == 0 path).
#   - I-bug1 (worldStage.test.ts:429): quit → CONTINUE wipes the run-scoped
#     narration latches — creature-flavored replay.
#   - bio_tell vacate band, creature refs (worldStage.test.ts:219 shape): a
#     warned chaos event opens the panic window, ambient ents drift OUT of
#     the strike zone, close-in ents stay (a gradient, not a teleport) —
#     the creature sim's 40px/s drift (cell is 48px/s; the scripted spread
#     mirrors the landed cell pin, test_cell_ai.gd test_panic_vacates_zone).
# NOT ported (verified against TS, does not touch creature): the I-bal
# war_graves raid pins (worldStage.test.ts:451) drive the TRIBE stage's
# launchRivalRaidNow/rivalWarriors — M4 scope, noted in the task report.
#
# M4 task 5 additions: the TRIBE save/continue + fall-path pins (the
# game-level surface the task wires). `with_tribe` boots register the
# TribeStage like main.gd now does; the flows ride REAL transitions
# (found_tribe's go_to / the fall's go_to hook), not switch_stage shortcuts,
# except where a leg's entry point IS the direct switch (documented inline).
#
# M5 task 4 additions: the CIV save/continue pins — a civ-stage save_all
# CONTINUEs into the civ stage with the board AS IT STOOD (the TS:132-134
# doctrine: CONTINUE mid-civ used to reset sliders, conquests and rival
# influence), and the stale-blob guard E2E (a length-mismatch blob → false →
# the fresh constructor board). `with_civ` boots register the CivStage like
# main.gd now does. The landing/placeholder/brick/i18n flows live in
# tests/test_hud_civ.gd (the task-4 file split, the M4 task-5 precedent).
#
# M6 task 6 additions: the SPACE save/continue pins — a space-stage save_all
# CONTINUEs into the space stage with the system AS IT STOOD (the restore
# whitelist: planets incl. the eco rosters + colonies + scanned, cargo, the
# abduct ledger), the on_exit persist, the C1 deck-rebuild gate on a
# different-world CONTINUE, and the corrupt-blob guards E2E (a wrong-length
# blob → the fresh constructor system incl. the gate placement — the ledger
# and the ending discard too; a non-finite r → the field keeps the
# constructor value while valid fields in the same blob ride).
# `with_space` boots register the SpaceStage like main.gd now does. The
# ending-continue flows + the space i18n live in tests/test_hud_space.gd.
#
# Headless -s boot: test_hud_creature's out-of-tree pattern (run.gd drives
# tests synchronously inside _initialize; stage _ready is invoked ONCE
# manually). The cell→creature shore transition's REAL-input proof lives in
# the task-9 bot scene (tools/test_bot_creature.sh, xvfb); here the creature
# stage is entered directly (switch_stage — the headless pattern).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const SpaceEventsLib := preload("res://src/game/space/space_events.gd")

const DT := 1.0 / 60.0
const SEED := 0x9BEF
const TRANSITION_POLL := 600  # brief AC: ≤ 600 frames for the arrival card
const SCRATCH_CFG := "user://test_wcp_settings.cfg"


# ---- boot -----------------------------------------------------------------------

## Out-of-tree boot (test_hud_creature pattern): the menu + creature stage,
## stage _ready invoked once manually. Nothing in the boot path needs the
## viewport (vw/vh keep 800×600; cam.cam2d stays null and the stage guards it).
## with_tribe registers the TribeStage too (main.gd parity) — the tribe
## flows below need a REAL landing target for go_to('tribe'). with_civ
## registers the CivStage too (M5: main.gd parity) — the civ flows need the
## REAL landing target for the saved stage id. with_space registers the
## SpaceStage too (M6: main.gd parity) — the space flows need the REAL
## landing target for the saved stage id.
func _boot(seed_v: int = SEED, with_tribe := false, with_civ := false,
		with_space := false) -> Variant:
	var ctx: Variant = ContextScript.new(seed_v)
	var g: Variant = GameScript.new(ctx)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	# pin the locale/mute defaults (the shared user cfg may carry anything;
	# test_game_flow precedent) and keep mute/lang writes out of it
	g.i18n.settings_path = SCRATCH_CFG
	_wipe_cfg()
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.muted = g.i18n.get_muted()
	g.register(MenuStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	if with_tribe:
		g.register(TribeStageScript.new(g))
	if with_civ:
		g.register(CivStageScript.new(g))
	if with_space:
		g.register(SpaceStageScript.new(g))
	g.stages["creature"]._ready()
	if with_tribe:
		g.stages["tribe"]._ready()
	if with_civ:
		g.stages["civ"]._ready()
	if with_space:
		g.stages["space"]._ready()
	g.start()
	return g


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the recorder-Callable cycle into this test instance
		g.free()


func _wipe_cfg() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(SCRATCH_CFG)


func _wipe_saves() -> void:
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for i in 3:
			if dir.file_exists("slot%d.json" % i):
				dir.remove("slot%d.json" % i)


func _to_creature(g: Variant) -> void:
	g.switch_stage("creature")
	eq(String(g.context.stage), "creature", "creature stage entered")
	g.step_for_testing(10, DT)


## A creature-stage save with a live 2-pack, written through the REAL
## save_all path (the autosave/shore flush seam this task wires).
func _write_creature_save(g: Variant) -> void:
	_wipe_saves()
	var sim: Variant = g.current.sim
	sim.debug_spawn_pack(2)
	ok(g.save_all(), "save_all wrote the creature slot")
	var raw: String = FileAccess.get_file_as_string("user://saves/slot0.json")
	var parsed: Variant = JSON.parse_string(raw)
	ok(parsed is Dictionary, "slot parses")
	eq(String(parsed["stage"]), "creature", "slot stage is creature")
	var flags: Dictionary = parsed["flags"]
	ok(String(flags.get("packGenomes", "")).length() > 0, "packGenomes flag present")
	var pack: Variant = JSON.parse_string(String(flags["packGenomes"]))
	ok(pack is Array and (pack as Array).size() >= 2,
			"the flush carried the live 2-pack (got %s)" % str(pack))


# ---- save round-trip ------------------------------------------------------------

func test_creature_save_round_trips_pack() -> void:
	var g: Variant = _boot()
	_to_creature(g)
	_write_creature_save(g)
	# the wire: a FRESH context loads the same slot — stage + pack flag ride
	var ctx2: Variant = ContextScript.new(1)
	ok(ctx2.load(0), "fresh context loads the creature save")
	eq(String(ctx2.stage), "creature", "loaded stage is creature")
	var pack2: Variant = JSON.parse_string(String(ctx2.flags["packGenomes"]))
	ok(pack2 is Array and (pack2 as Array).size() >= 2, "pack flag round-trips")
	_drop(g)


# ---- continue -------------------------------------------------------------------

func test_continue_boots_creature_and_restores_pack() -> void:
	# run 1: make the save
	var g1: Variant = _boot()
	_to_creature(g1)
	_write_creature_save(g1)
	_drop(g1)
	# run 2: a fresh boot CONTINUEs — the menu routes the loaded stage id and
	# the creature stage's on_enter restores the pack (livePack == 0 path)
	var g2: Variant = _boot()
	eq(String(g2.context.stage), "menu", "boot 2 sits on the menu")
	g2.current.continue_slot(0)
	eq(String(g2.transition["title"]), "WELCOME BACK", "continue card title")
	var steps := 0
	while not (String(g2.context.stage) == "creature" and g2.transition == null) \
			and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "creature",
			"CONTINUE with a creature save boots the creature stage (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	var pack_n := 0
	for e in sim2.ents:
		if bool(e["pack"]):
			pack_n += 1
	ok(pack_n >= 2, "pack restored from flags (got %d)" % pack_n)
	# arrivals arrive healthy + invulnerable (the on_enter reload-grace pins)
	ok(float(sim2.php) > 0.0, "arrived alive")
	eq(int(g2.deaths_in_stage), 0, "narration started clean")
	_wipe_saves()
	_drop(g2)


## I-bug1 (worldStage.test.ts:429) — the dying run's narration latches must
## not ride into the continued run. Creature-flavored: the save is a creature
## run and the latched game is the one that CONTINUEs.
func test_narration_reset_on_continue_creature() -> void:
	var g1: Variant = _boot()
	_to_creature(g1)
	_write_creature_save(g1)
	_drop(g1)
	var g2: Variant = _boot()
	# the quitting run latches everything: death blackout + gaia ledger +
	# DNA window + a queued beat
	g2.deaths_in_stage = 5
	g2.stage_time = 33.0
	g2.dying_until = 999.0
	g2.gaia_death_at = 42.0
	g2.dna_window.append({"t": 1.0, "amount": 9.0})
	g2.storyteller.offer_beat("herd_remembers")
	g2.current.continue_slot(0)
	var steps := 0
	while not (String(g2.context.stage) == "creature" and g2.transition == null) \
			and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "creature", "continued into creature")
	eq(int(g2.deaths_in_stage), 0, "deaths_in_stage wiped")
	# stage_time: the wipe ran at continue_slot; the arrival's in-fade steps
	# re-accumulate a fraction of a second — the 33s latch is what must be gone
	ok(float(g2.stage_time) < 1.0, "stage_time latch wiped (got %s)" % str(g2.stage_time))
	eq(float(g2.dying_until), 0.0, "death-window blackout wiped")
	eq(float(g2.gaia_death_at), -1.0, "gaia ledger wiped")
	eq(g2.dna_window.size(), 0, "dna window wiped")
	eq(g2.storyteller.poll(), null, "queued beats wiped")
	_wipe_saves()
	_drop(g2)


# ---- bio_tell vacate band (creature refs) ----------------------------------------

## worldStage.test.ts:219 shape on the CREATURE sim: trigger a warned event,
## ride the 2.5s warn window to 2.4s, and measure the strike-zone vacate.
## Creature differences vs the cell pin (documented): the drift speed is 40
## (cell 48) AND the movement integrates accel + exp(−5.5dt) drag with a 40
## speed cap — a 120px drift target lands ~91px in the 2.4s window (measured
## 91-92 across the whole spread, probe 2026-09-30) — so ents seeded beyond
## ~250px vacate the 340 band. The spread below is x-dominant on purpose:
## the creature z-band is narrow ([-200, 240]) and a z-ward flee clamps,
## which both shrinks the displacement and can move an ent back INWARD.
## Scripted radii 150..330 put the fraction at 4/9 ≈ 44% — inside the
## catalog's 40-60% band with margin both ways.
func test_bio_tell_vacate_band_creature() -> void:
	var ctx: Variant = ContextScript.new(SEED)
	var rec: Dictionary = {"toasts": [], "banners": [], "floats": [], "audio": [],
			"shakes": [], "bursts": [], "spawns": [], "notes": [], "events": []}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(playtime): rec["notes"].append(playtime),
		"context_event": func(ev, from_stage): rec["events"].append([ev, from_stage]),
	}
	var sim: Variant = CreatureSim.new(ctx, ctx.rng.branch(), hooks)
	var inp: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	for b in sim.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0
	for bo in sim.bones:
		bo["x"] = 99999.0
		bo["z"] = 99999.0
	# 9 wild ents around the player (wild: pack false — the drift branch
	# excludes pack ents), x-dominant flee angles, radii 150..330
	var angs := [0.3, PI - 0.3, -0.3, PI + 0.3, 0.5, PI - 0.5, -0.5, PI + 0.5, 0.35]
	var radii := [150.0, 170.0, 190.0, 210.0, 230.0, 255.0, 280.0, 305.0, 330.0]
	var eids: Array = []
	for i in 9:
		var e: Dictionary = sim.spawn_ent(null,
				float(sim.px) + cos(angs[i]) * radii[i],
				float(sim.pz) + sin(angs[i]) * radii[i])
		eids.append(int(e["eid"]))
	# a warned event: the scheduler parks it in the warn phase (window 2.5s)
	ok(sim.chaos.trigger("earthquake", sim), "warned event triggered")
	ok(float(sim.chaos.warn_remaining()) > 0.0, "warn window is open")
	var saw_drift := false
	var moods := {}
	for t in 144:  # 2.4s of the 2.5s window (the TS measurement point)
		sim.update(DT, inp)
		if float(sim.warnDriftT) > 0.0:
			saw_drift = true
		for eid_v in eids:
			for e in sim.ents:
				if int(e["eid"]) == int(eid_v):
					moods[String(e["mood"])] = true
	ok(saw_drift, "warnDriftT tracked the live warn phase (the TS:498 wire)")
	ok(bool(moods.get("alert", false)), "the panicking ambient reads mood alert")
	var gone := 0
	var inside := 0
	var moved_out := 0
	for j in eids.size():
		for e in sim.ents:
			if int(e["eid"]) != int(eids[j]):
				continue
			var dx: float = float(e["x"]) - float(sim.px)
			var dz: float = float(e["z"]) - float(sim.pz)
			var d: float = sqrt(dx * dx + dz * dz)
			# closed-form drift pin: the 120px target integrates to ~91px in
			# the window (cap 40/s + drag ramp − the 8px target dead-zone)
			if absf(d - float(radii[j])) >= 80.0 and absf(d - float(radii[j])) <= 105.0:
				moved_out += 1
			if d > 340.0:
				gone += 1
			else:
				inside += 1
			break
	eq(moved_out, 9, "every wild ent rode the panic drift ~91px outward")
	ok(float(gone) >= 0.4 * 9.0 and float(gone) <= 0.6 * 9.0,
			"vacate lands in the 40-60%% band (%d/9)" % gone)
	ok(inside >= 1, "close-in ents stay (a real vacate gradient, not a teleport)")


# ---- M4 task 5: tribe save/continue + fall path (REAL transitions) --------------

## A creature-stage save_all CONTINUEs into the creature stage (the saved
## stage id — found_tribe's ctx.save rides BEFORE the landing, TS
## CreatureStage.ts:1647), the pack restores, and the founding path re-runs
## into the REGISTERED tribe stage with the pack conversion consuming the
## snapshot again (TribeStage.ts:176-189). The task-9 placeholder assert's
## real-flow upgrade, headless.
func test_continue_creature_save_refounds_into_tribe() -> void:
	_wipe_saves()
	# run 1: creature save → found → land tribe (pack consumed in memory)
	var g1: Variant = _boot(SEED, true)
	_to_creature(g1)
	var sim1: Variant = g1.current.sim
	sim1.debug_spawn_pack(2)
	ok(g1.save_all(), "creature-stage save_all wrote the slot")
	sim1.found_tribe()  # the TS bot cheat — fires the REAL go_to hook
	var steps := 0
	while not (String(g1.context.stage) == "tribe" and g1.transition == null) \
			and steps < TRANSITION_POLL:
		g1.step_for_testing(1, DT)
		steps += 1
	eq(String(g1.context.stage), "tribe", "run 1 landed the registered tribe stage")
	eq(String(g1.context.flags.get("packGenomes", "")), "[]", "run 1 consumed the pack")
	_drop(g1)
	# run 2: CONTINUE boots the SAVED stage (creature) with the pack, and the
	# re-found lands tribe with the conversion re-run
	var g2: Variant = _boot(SEED, true)
	g2.current.continue_slot(0)
	var steps2 := 0
	while not (String(g2.context.stage) == "creature" and g2.transition == null) \
			and steps2 < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps2 += 1
	eq(String(g2.context.stage), "creature", "CONTINUE booted the saved creature stage")
	var sim2: Variant = g2.current.sim
	var pack_n := 0
	for e in sim2.ents:
		if bool(e["pack"]):
			pack_n += 1
	ok(pack_n >= 2, "pack restored from the founding save (got %d)" % pack_n)
	sim2.found_tribe()
	var steps3 := 0
	while not (String(g2.context.stage) == "tribe" and g2.transition == null) \
			and steps3 < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps3 += 1
	eq(String(g2.context.stage), "tribe", "the re-found landed the registered tribe stage")
	eq(g2.current.sim.tribe.size(), 3, "pack conversion re-ran (min 3)")
	eq(String(g2.context.flags.get("packGenomes", "")), "[]", "packGenomes consumed again")
	_wipe_saves()
	_drop(g2)


## A TRIBE-stage save mid-progress CONTINUEs back into the village AS IT
## STOOD: game.save_all routes current.persist_state (game.gd:706 — the
## creature precedent) → the tribeState blob rides the slot → the arrival's
## restoreState() returns true and REPLACEs the roster (TribeStage.ts:212-244,
## never appending to a fresh founding).
func test_tribe_save_continue_restores_village() -> void:
	_wipe_saves()
	# run 1: direct tribe entry (headless pattern — the founding legs cover
	# the real transition; this pin is about the SAVE side), grow the village,
	# save through the real game.save_all seam
	var g1: Variant = _boot(SEED, true)
	g1.switch_stage("tribe")
	g1.step_for_testing(5, DT)
	var sim1: Variant = g1.current.sim
	eq(sim1.huts.size(), 1, "fresh village: starting hut")
	sim1.wood = 120.0
	sim1.try_build_hut()  # the real build path (wood ≥ 40 → hut, buildT 6)
	eq(sim1.huts.size(), 2, "second hut started")
	sim1.food = 75.0
	ok(g1.save_all(), "tribe-stage save_all (the persist_state seam)")
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("user://saves/slot0.json"))
	ok(parsed is Dictionary, "slot parses")
	eq(String(parsed["stage"]), "tribe", "slot stage is tribe")
	var blob: Variant = JSON.parse_string(String(parsed["flags"]["tribeState"]))
	ok(blob is Dictionary, "tribeState blob present in the slot")
	eq((blob["huts"] as Array).size(), 2, "blob carries both huts")
	_drop(g1)
	# run 2: CONTINUE lands tribe; the village comes back as it stood
	var g2: Variant = _boot(SEED, true)
	g2.current.continue_slot(0)
	var steps := 0
	while not (String(g2.context.stage) == "tribe" and g2.transition == null) \
			and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "tribe",
			"CONTINUE with a tribe save boots the tribe stage (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	eq(sim2.huts.size(), 2, "village restored as it stood (2 huts — restore, not re-found)")
	# the band, not an exact pin: two +8 deliveries can land in 70..95 during
	# the boot steps. The assert still proves RESTORE-not-refound — a fresh
	# founding reads exactly 60, outside the band.
	var food_v := float(sim2.food)
	ok(food_v >= 70.0 and food_v <= 95.0,
			"food restored in the 70..95 band (saved 75 + up to two +8 deliveries, got %s)" % str(food_v))
	eq(sim2.tribe.size(), 3, "roster restored (REPLACE — no founding minimum on top)")
	eq(float(sim2.totem["progress"]), 0.0, "totem progress restored")
	var bt := float(sim2.huts[1]["buildT"])
	ok(bt > 0.0 and bt <= 6.0, "mid-build hut preserved (buildT %s)" % str(bt))
	eq(String(g2.current.hud_inst.show_objective),
			"GATHER · BUILD · SURVIVE — raise the Great Totem",
			"objective line re-armed on the restored village (TS:164)")
	_wipe_saves()
	_drop(g2)


## The fall path E2E: a dead village walks back to the wilds through the REAL
## go_to transition, the tribeState blob is deleted BEFORE the fall's own
## save_all (TS:393-395) and persist_state's corpse guard never re-writes it
## — so a re-found builds FRESH (the 3-bounce resurrection bug's pin).
func test_fall_path_lands_creature_with_blob_deleted() -> void:
	_wipe_saves()
	var g: Variant = _boot(SEED, true)
	g.switch_stage("tribe")  # direct entry — the fall itself is the real flow
	g.step_for_testing(5, DT)
	var sim: Variant = g.current.sim
	eq(sim.tribe.size(), 3, "village founded for the fall leg")
	# kill the village (test-fixture state write — the TS I-bal family drives
	# the sim surface directly, worldStage.test.ts:451)
	sim.tribe.clear()
	sim.huts.clear()
	# the fall: the next tick arms fallenT; > 4 s later the go_to hook fires
	# 'BACK TO THE WILDS' (the sim cannot see the game — the hook is the wire)
	var card_seen := false
	var steps := 0
	while steps < 1200:
		g.step_for_testing(1, DT)
		steps += 1
		if g.transition != null and not card_seen:
			card_seen = true
			eq(String(g.transition["next"]), "creature", "fall go_to targets creature")
			eq(String(g.transition["title"]), "BACK TO THE WILDS", "fall card title (TS:396)")
		if String(g.context.stage) == "creature" and g.transition == null:
			break
	ok(card_seen, "the fall transition fired (%d steps)" % steps)
	eq(String(g.context.stage), "creature", "BACK TO THE WILDS landed creature")
	# the blob is dead in memory AND on disk: the fall deleted flags.tribeState
	# before save_all, and the corpse guard kept persist_state silent
	ok(not g.context.flags.has("tribeState"), "flags.tribeState deleted (TS:393)")
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("user://saves/slot0.json"))
	ok(parsed is Dictionary, "the fall's own save_all wrote the slot")
	eq(String(parsed["stage"]), "tribe", "the fall's save ran while tribe was current (TS:395 order)")
	var flags: Dictionary = parsed["flags"]
	ok(not flags.has("tribeState"), "the disk save carries NO tribe blob")
	_drop(g)
	# re-found: restoreState finds no blob → the fresh founding — no
	# resurrection, and the old fall timer does not ride (the 3-bounce bug)
	var g2: Variant = _boot(SEED, true)
	g2.switch_stage("creature")
	g2.step_for_testing(5, DT)
	g2.switch_stage("tribe")
	g2.step_for_testing(5, DT)
	var sim2: Variant = g2.current.sim
	eq(sim2.huts.size(), 1, "re-found built the fresh starting hut")
	eq(float(sim2.food), 60.0, "fresh-start economy (no blob resurrection)")
	eq(float(sim2.fallenT), 0.0, "the old fall timer did not ride")
	g2.step_for_testing(360, DT)  # 6 s — well past the old 4 s fall trigger
	eq(sim2.huts.size(), 1, "no bounce: the fresh village still stands")
	eq(sim2.tribe.size(), 3, "fresh roster intact")
	_wipe_saves()
	_drop(g2)


# ---- M5 task 4: civ save/continue + the stale-blob guard (REAL transitions) ------

## A CIV-stage save mid-progress CONTINUEs back into the planet AS IT STOOD:
## game.save_all routes current.persist_state (game.gd:708 — the creature/
## tribe precedent) → the civState blob rides the slot → the arrival's
## restoreState() returns true and restores influences, owners, sliders,
## lastRaised and the victoryFired latch (CivStage.ts:132-134 — CONTINUE
## mid-civ used to reset sliders, conquests and rival influence; the menu row
## said 'CIV · 15 min' but you got a fresh cold war).
func test_civ_save_continue_restores_board() -> void:
	_wipe_saves()
	# run 1: direct civ entry (headless pattern — the save side is the pin;
	# the landing legs cover the real transition), conquer through the honest
	# grant+tick path (the sim header's documented bot leg), fixture slider
	# writes, save through the REAL game.save_all seam
	var g1: Variant = _boot(SEED, true, true)
	g1.switch_stage("civ")
	g1.step_for_testing(2, DT)
	var sim1: Variant = g1.current.sim
	sim1.debug_set_influence(1, 100.0)
	var flip_steps := 0
	while String(sim1.cities[1]["owner"]) != "you" and flip_steps < 240:
		g1.step_for_testing(1, DT)  # the tick_second flip at the next floor-cross
		flip_steps += 1
	eq(String(sim1.cities[1]["owner"]), "you",
			"the grant drove the real flip (%d steps)" % flip_steps)
	# the flip leg crossed the 1 s tick floor once — the untouched rivals
	# drifted one hearts-step off the constructor −60; capture what stood
	var inf3 := float(sim1.cities[3]["influence"])
	sim1.cities[2]["influence"] = 55.0  # fixture write: a half-won rival stays rival
	sim1.mil = 9.0
	sim1.culture = 2.0
	sim1.econ = 1.0
	sim1.lastRaised = "econ"
	ok(g1.save_all(), "civ-stage save_all (the persist_state seam)")
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("user://saves/slot0.json"))
	ok(parsed is Dictionary, "slot parses")
	eq(String(parsed["stage"]), "civ", "slot stage is civ")
	var blob: Variant = JSON.parse_string(String(parsed["flags"]["civState"]))
	ok(blob is Dictionary, "civState blob present in the slot")
	eq((blob["cities"] as Array).size(), 4, "blob carries the 4-city board")
	eq(String(blob["cities"][1]["owner"]), "you", "blob carries the conquest")
	eq(float(blob["cities"][2]["influence"]), 55.0, "blob carries the half-won influence")
	eq(float(blob["mil"]), 9.0, "blob carries the sliders")
	eq(String(blob["lastRaised"]), "econ", "blob carries lastRaised")
	eq(bool(blob["victoryFired"]), false, "blob victoryFired false")
	# on_exit persists too (TS:130): leaving the stage rewrites the flags blob.
	# Task 4 R1: the ACTIVE first-run tutorial also finishes on a forward exit
	# (the cell rule, CellStage.ts:264-267) and its finish() flushes the SLOT —
	# so the slot's civState now carries the exit-time sliders (mil 5), not the
	# :536 snapshot (mil 9); run 2 pins the exit-time value below.
	sim1.mil = 5.0
	g1.switch_stage("creature")
	eq(float(JSON.parse_string(String(g1.context.flags["civState"]))["mil"]), 5.0,
			"on_exit → persist_state (TS:130)")
	_drop(g1)
	# run 2: CONTINUE lands the SAVED stage (civ); the board comes back as it
	# stood — the sim runs < 1 s of in-fade before the asserts (no tick_second
	# before time 1.0), so the restored values hold exactly
	var g2: Variant = _boot(SEED, true, true)
	g2.current.continue_slot(0)
	var steps := 0
	while not (String(g2.context.stage) == "civ" and g2.transition == null) \
			and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "civ",
			"CONTINUE with a civ save boots the civ stage (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	ok(sim2.restore_state(), "restore_state true re-read (the blob still rides)")
	eq(String(sim2.cities[1]["owner"]), "you", "conquest restored")
	eq(float(sim2.cities[1]["influence"]), 100.0, "conquered influence restored")
	eq(String(sim2.cities[2]["owner"]), "r2", "the half-won city STAYS rival")
	eq(float(sim2.cities[2]["influence"]), 55.0, "half-won influence restored")
	eq(float(sim2.cities[3]["influence"]), inf3,
			"the untouched rival restored as it stood (one drift tick off −60)")
	eq(float(sim2.mil), 5.0,
			"sliders restored as they stood at exit — CONTINUE mid-civ no longer resets them")
	eq(float(sim2.culture), 2.0, "culture restored")
	eq(float(sim2.econ), 1.0, "econ restored")
	eq(String(sim2.lastRaised), "econ", "lastRaised restored (the TS:169-170 first-drip pin)")
	eq(bool(sim2.victoryFired), false, "victoryFired false restored")
	eq(String(g2.current.hud_inst.show_objective),
			"UNIFY THE PLANET — slider keys Q/W/E · launch armadas with 1/2/3",
			"objective re-armed on the restored board (TS:121)")
	eq(float(g2.current.hud_inst.toast_inset), 150.0, "inset re-armed (TS:120)")
	_wipe_saves()
	_drop(g2)


## The guards E2E: a STALE save whose civState predates the current board
## shape (3 cities vs the constructor's 4) → restore_state false (the
## TS:154 length gate) → the FRESH constructor board stands — no blob values
## ride, no brick fires, no crash.
func test_civ_stale_blob_guards_e2e() -> void:
	_wipe_saves()
	var g1: Variant = _boot(SEED, true, true)
	g1.switch_stage("civ")
	g1.step_for_testing(2, DT)
	# the stale blob: a 3-city board from an older save shape (hand-authored —
	# the corruption scenario the guard exists for cannot come from the sim)
	g1.context.flags["civState"] = JSON.stringify({
		"cities": [
			{"id": "you", "owner": "you", "influence": 100.0, "hp": 100.0, "pop": 8.0},
			{"id": "r1", "owner": "you", "influence": 99.0, "hp": 100.0, "pop": 6.0},
			{"id": "r2", "owner": "you", "influence": 99.0, "hp": 100.0, "pop": 6.0},
		],
		"mil": 8.0, "culture": 1.0, "econ": 1.0,
		"victoryFired": false, "lastRaised": "mil",
	})
	ok(g1.context.save(), "the stale-blob slot wrote (stage civ)")
	_drop(g1)
	var g2: Variant = _boot(SEED, true, true)
	g2.current.continue_slot(0)
	var steps := 0
	while not (String(g2.context.stage) == "civ" and g2.transition == null) \
			and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "civ", "CONTINUE booted the civ stage (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	ok(not sim2.restore_state(), "the stale blob rejects (TS:154 — direct guard re-read)")
	# the FRESH constructor board: no stale value rode
	eq(String(sim2.cities[1]["owner"]), "r1", "fresh board — the stale conquest did not ride")
	eq(float(sim2.cities[1]["influence"]), -60.0, "fresh rival influence")
	eq(float(sim2.mil), 4.0, "fresh sliders (4/3/3)")
	eq(bool(sim2.victoryFired), false, "no latch on the fresh board")
	eq(g2.pending_go_to, null, "no brick go_to (victoryFired false + rivals hold)")
	_wipe_saves()
	_drop(g2)


# ---- M6 task 6: space save/continue + the corrupt-blob guards (REAL transitions) --

## A SPACE-stage save mid-flight CONTINUEs back into the system AS IT STOOD:
## game.save_all routes current.persist_state (the creature/civ precedent) →
## the spaceWorld blob rides the slot → on_enter's restore whitelist restores
## planets (scanned, colonies), the eco rosters, the cargo and the abduct
## pay-curve ledger (SpaceStage.ts:190-267 — a reload used to re-roll every
## seeded roster and re-pay the abduct "firsts").
func test_space_save_continue_restores_system() -> void:
	_wipe_saves()
	# run 1: direct space entry (headless pattern — the landing legs cover the
	# real transition), fixture the system through the sim surface, save
	# through the REAL game.save_all seam
	var g1: Variant = _boot(SEED, false, false, true)
	g1.switch_stage("space")
	g1.step_for_testing(2, DT)
	var sim1: Variant = g1.current.sim
	sim1.planets[0]["scanned"] = true
	sim1.planets[1]["colony"] = {"pop": 12.5, "generations": 3.0}
	sim1.planets[2]["colony"] = {"pop": 20.0, "generations": 7.0}  # a thriving one
	sim1.abductCount = {"0:4": 2.0, "1:7": 1.0}
	var roster_names: Array = []
	var roster_pops: Array = []
	for sp in sim1.planets[0]["eco"].species:
		roster_names.append(String(sp["name"]))
		roster_pops.append(float(sp["pop"]))
	var genome: Dictionary = GenomeLib.clone_genome(GenomeLib.default_genome())
	genome["size"] = 1.7
	sim1.cargo.append({"genome": genome, "name": "Zeta-9"})
	ok(g1.save_all(), "space-stage save_all (the persist_state seam)")
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("user://saves/slot0.json"))
	ok(parsed is Dictionary, "slot parses")
	eq(String(parsed["stage"]), "space", "slot stage is space")
	var blob: Variant = JSON.parse_string(String(parsed["flags"]["spaceWorld"]))
	ok(blob is Dictionary, "spaceWorld blob present in the slot")
	if blob is Dictionary:
		eq((blob["planets"] as Array).size(), 6, "blob carries the 6-planet system")
		eq(bool((blob["planets"] as Array)[0]["scanned"]), true, "blob carries scanned")
		eq(float(((blob["planets"] as Array)[1]["colony"] as Dictionary)["pop"]), 12.5,
				"blob carries the colony pop")
		eq((blob["abductCount"] as Dictionary).size(), 2, "blob carries the ledger")
		eq(String((blob["cargo"] as Array)[0]["name"]), "Zeta-9", "blob carries the cargo row")
		eq(bool(blob["endingDone"]), false, "blob carries endingDone false")
	# on_exit persists too (TS:270): leaving the stage rewrites the flags blob
	sim1.planets[3]["scanned"] = true
	g1.switch_stage("creature")
	var flags_blob: Variant = JSON.parse_string(String(g1.context.flags["spaceWorld"]))
	eq(bool(((flags_blob["planets"] as Array)[3]["scanned"])), true,
			"on_exit → persist_state (TS:270)")
	_drop(g1)
	# run 2: CONTINUE lands the SAVED stage (space). The exact-restored asserts
	# run at the FIRST WELCOME-BACK card frame — on_enter (the restore) fired
	# at the out→card boundary and the card phase FREEZES the stage sim
	# (game.gd's card gate), so zero sim ticks separate restore from assert
	# (the in-fade afterwards grows the colonies ~0.05 — the civ test's
	# <1 s-of-ticks caveat, one frame sooner here).
	var g2: Variant = _boot(SEED, false, false, true)
	g2.current.continue_slot(0)
	var steps := 0
	while not (String(g2.context.stage) == "space" and g2.transition != null \
			and String(g2.transition["phase"]) == "card") and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "space",
			"CONTINUE with a space save boots the space stage (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	eq(bool(sim2.planets[0]["scanned"]), true, "scanned restored (the whitelist rides)")
	eq(float(sim2.planets[1]["colony"]["pop"]), 12.5, "colony pop restored")
	eq(float(sim2.planets[1]["colony"]["generations"]), 3.0, "colony generations restored")
	eq(float(sim2.planets[2]["colony"]["pop"]), 20.0, "the thriving colony restored")
	eq(sim2.abductCount, {"0:4": 2.0, "1:7": 1.0},
			"the abduct ledger restored — no re-paid firsts (TS:252-255)")
	eq(sim2.cargo.size(), 1, "cargo restored")
	if sim2.cargo.size() == 1:
		eq(String(sim2.cargo[0]["name"]), "Zeta-9", "cargo name restored")
		eq(float(sim2.cargo[0]["genome"]["size"]), 1.7, "cargo genome gene restored")
	eq(bool(sim2.endingDone), false, "endingDone false restored")
	# the eco roster rebuilt from the save — seeded genes survive the reload
	# (TS:232-240; the from_json roster rides name/pop/genome). The pops ride
	# the JSON wire: the stringify shortest-repr can drop the last ulp, so the
	# pops pin at 1e-9 (the sim-side whitelist pins are exact).
	var restored_names: Array = []
	var restored_pops: Array = []
	for sp in sim2.planets[0]["eco"].species:
		restored_names.append(String(sp["name"]))
		restored_pops.append(float(sp["pop"]))
	eq(restored_names, roster_names, "the eco roster names round-trip (TS:239)")
	eq(restored_pops.size(), roster_pops.size(), "the eco roster SIZE round-trips")
	for j in mini(restored_pops.size(), roster_pops.size()):
		approx(restored_pops[j], roster_pops[j],
				"the eco roster pop %d round-trips (the JSON wire, 1e-9)" % j, 1e-9)
	eq(float(sim2.planets[0]["eco"].flora_cap), 140.0, "the lush floraCap rides (TS:137)")
	# ride the card + fade out, then the settle pins
	var steps2 := 0
	while not (String(g2.context.stage) == "space" and g2.transition == null) \
			and steps2 < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps2 += 1
	eq(g2.transition, null, "the WELCOME BACK ride completed (%d steps)" % steps2)
	# the arrival hud hooks + the C1 no-op on the same world
	eq(String(g2.current.hud_inst.show_objective),
			"SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve",
			"objective re-armed on the restored system (TS:188)")
	eq(float(g2.current.hud_inst.toast_inset), 0.0, "no inset armed (space arms none)")
	eq(int(sim2.deckSeed), int(g2.context.world["seed"]),
			"same world → no deck rebuild (C1 no-op, TS:183)")
	_wipe_saves()
	_drop(g2)


## The C1 gate E2E: a CONTINUE that loads a DIFFERENT world than the boot's
## rebuilds the space chaos deck folding the LOADED world in (TS:182-186) —
## boot 2's constructor folded its own world (deckSeed B); the landing must
## re-fold the save's world (deckSeed A).
func test_space_continue_rebuilds_deck_on_new_world() -> void:
	_wipe_saves()
	# run 1: a space save under seed A (a distinctive marker rides too)
	var g1: Variant = _boot(SEED, false, false, true)
	g1.switch_stage("space")
	g1.step_for_testing(2, DT)
	g1.current.sim.planets[0]["scanned"] = true
	ok(g1.save_all(), "the seed-A space save wrote the slot")
	_drop(g1)
	# run 2: a boot on a DIFFERENT world — the space stage constructor folded
	# its own world (deckSeed B ≠ A)
	var g2: Variant = _boot(SEED + 0x2B1, false, false, true)
	eq(int(g2.stages["space"].sim.deckSeed), int(g2.context.world["seed"]),
			"boot 2 folded its own world (deckSeed B)")
	ok(int(g2.context.world["seed"]) != SEED, "the boot world really differs")
	g2.current.continue_slot(0)
	var steps := 0
	while not (String(g2.context.stage) == "space" and g2.transition == null) \
			and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "space", "CONTINUE landed space (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	eq(int(sim2.deckSeed), SEED,
			"the deck REBUILT folding the LOADED world in (deckSeed A, C1 TS:184-185)")
	eq(sim2.chaos.defs.size(),
			SpaceEventsLib.make_space_chaos_events(g2.context.world).size(),
			"the rebuilt deck folds the loaded world in (task 3)")
	# the restore still ran on the same landing (scanned rides)
	eq(bool(sim2.planets[0]["scanned"]), true, "the whitelist restore rode with the rebuild")
	_wipe_saves()
	_drop(g2)


## The guards E2E: a STALE save whose spaceWorld predates the current system
## shape (3 planets vs the constructor's 6) → the TS:201 length gate rejects
## the WHOLE restore (the gate placement: the cargo, the abduct ledger AND
## the ending state discard too) → the FRESH constructor system stands — no
## blob value rides, no stale orb, no crash.
func test_space_stale_blob_guards_e2e() -> void:
	_wipe_saves()
	# the FRESH constructor baseline (same seed → boot 2 rebuilds it exactly)
	var g1: Variant = _boot(SEED, false, false, true)
	var sim1: Variant = g1.stages["space"].sim
	var gen_name0 := String(sim1.planets[0]["name"])
	var gen_r0 := float(sim1.planets[0]["r"])
	var gen_kind0 := String(sim1.planets[0]["kind"])
	# the slot must carry stage 'space' (the M5 stale-blob shape): enter before
	# authoring — on_enter restores nothing (no blob yet), then the hand blob
	g1.switch_stage("space")
	# the stale blob: a 3-planet system from an older save shape (hand-authored
	# — the corruption scenario the gate exists for cannot come from the sim)
	g1.context.flags["spaceWorld"] = JSON.stringify({
		"planets": [
			{"name": "Ghost", "scanned": true, "colony": {"pop": 30.0, "generations": 9.0}},
			{"name": "Ghost2"},
			{"name": "Ghost3"},
		],
		"cargo": [{"genome": {"size": 2.5}, "name": "Phantom"}],
		"abductCount": {"9:9": 9.0},
		"endingDone": true,
		"endingDismissed": true,
	})
	ok(g1.context.save(), "the stale-blob slot wrote (stage space)")
	_drop(g1)
	var g2: Variant = _boot(SEED, false, false, true)
	g2.current.continue_slot(0)
	var steps := 0
	while not (String(g2.context.stage) == "space" and g2.transition == null) \
			and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "space", "CONTINUE booted the space stage (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	# the FRESH constructor system: no stale value rode
	eq(String(sim2.planets[0]["name"]), gen_name0, "fresh system — the ghost name did not ride")
	eq(float(sim2.planets[0]["r"]), gen_r0, "fresh radius")
	eq(String(sim2.planets[0]["kind"]), gen_kind0, "fresh kind")
	eq(bool(sim2.planets[0]["scanned"]), false, "fresh scanned")
	eq(sim2.planets[0]["colony"], null, "fresh uncolonized")
	# the gate placement: cargo, the ledger and the WON state discarded too
	eq(sim2.cargo, [], "the phantom cargo discarded (inside the gate, TS:247)")
	eq(sim2.abductCount, {}, "the phantom ledger discarded (inside the gate, TS:253)")
	eq(bool(sim2.endingDone), false, "the phantom endingDone discarded (inside the gate, TS:257)")
	eq(sim2.finale, null, "no stale orb (the dismissed blob never restored)")
	g2.stages["space"].render()
	ok(true, "the fresh system renders clean")
	_wipe_saves()
	_drop(g2)


## The corrupt-field guard E2E (right length): row 0's r carries `1e999` —
## JSON parses it to inf, the JSON analog of TS Number.isFinite — and the
## num(v, 0) guard rejects it (TS:208/210); the CONSTRUCTOR r keeps the orbit
## loop finite while VALID fields in the same blob ride (per-field guards).
func test_space_corrupt_r_guard_e2e() -> void:
	_wipe_saves()
	var g1: Variant = _boot(SEED, false, false, true)
	var sim1: Variant = g1.stages["space"].sim
	var gen_r0 := float(sim1.planets[0]["r"])
	# the slot must carry stage 'space' (the M5 stale-blob shape)
	g1.switch_stage("space")
	# hand-authored: 6 rows (right length), row 0 inf r, row 1 valid fields
	g1.context.flags["spaceWorld"] = "{\"planets\":[{\"r\": 1e999}, " \
			+ "{\"name\": \"Corruptus\", \"scanned\": true}, {}, {}, {}, {}], " \
			+ "\"cargo\": [], \"abductCount\": {}, \"endingDone\": false, " \
			+ "\"endingDismissed\": false}"
	ok(g1.context.save(), "the corrupt-r slot wrote (stage space)")
	_drop(g1)
	var g2: Variant = _boot(SEED, false, false, true)
	g2.current.continue_slot(0)
	var steps := 0
	while not (String(g2.context.stage) == "space" and g2.transition == null) \
			and steps < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps += 1
	eq(String(g2.context.stage), "space", "CONTINUE booted the space stage (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	eq(float(sim2.planets[0]["r"]), gen_r0,
			"the inf r rejected → the constructor r kept (the NaN-r guard, TS:208-210)")
	eq(String(sim2.planets[1]["name"]), "Corruptus", "the valid name rode (the gate opened)")
	eq(bool(sim2.planets[1]["scanned"]), true, "the valid scanned rode")
	# the orbit loop stays finite: a render pass over the corrupt-adjacent system
	g2.stages["space"].render()
	ok(true, "render clean with the guarded r")
	_wipe_saves()
	_drop(g2)
