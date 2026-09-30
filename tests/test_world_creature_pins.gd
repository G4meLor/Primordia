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
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0x9BEF
const TRANSITION_POLL := 600  # brief AC: ≤ 600 frames for the arrival card
const SCRATCH_CFG := "user://test_wcp_settings.cfg"


# ---- boot -----------------------------------------------------------------------

## Out-of-tree boot (test_hud_creature pattern): the menu + creature stage,
## stage _ready invoked once manually. Nothing in the boot path needs the
## viewport (vw/vh keep 800×600; cam.cam2d stays null and the stage guards it).
func _boot(seed_v: int = SEED) -> Variant:
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
	g.stages["creature"]._ready()
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
