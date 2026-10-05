# QC round 2 M2 — the creature's first jump after an editor close must read
# the LIVE genome (TS CreatureStage.ts:670 `this.pvy = 320 + ctx.genome.wings
# * 60` reads genome at jump; native creature_sim.gd:732-736 is verbatim, and
# the editor's click_part writes the SAME shared context.genome dict —
# editor.gd:131 `_g()`). The QC2 report (wings bought → KeyE close → first
# jump peaked at the wings-0 apex 51.25 = pvy 320) did not survive the round-2
# probe: three arms (real-pipeline buy+close+jump, mid-air editor freeze
# resume, isolated click_part+sim.update) all fired the first post-close jump
# at pvy 380 with the genome identity- and hash-stable throughout — the
# reported 51.25 is the sampled apex of a PRE-buy wings-0 arc caught by the
# harness's py-max window (the editor freeze can park a pre-buy arc in it).
# These tests pin the live read so a stale-read regression cannot land
# silently: the wings-0 baseline jump discriminates (pvy 304.17 vs 364.17 on
# the fire frame, gravity-first sampled), and the mid-air test pins the
# freeze-resume shape the artifact rides on. Drives the REAL editor instance
# and the REAL stage update through the wrapper-stuffed one-shot key
# (test_civ_scene.test_snapshot_keys_reach_the_sim pattern — headless stands
# in for parse_input_event, which needs a display server) and the programmatic
# click path (editor.gd header: click_part is the bot.test.ts:132 parity
# surface). Headless out-of-tree boot (test_creature_editor_stats._boot
# pattern).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")

const DT := 1.0 / 60.0
const SEED := 0x9BEF
const SCRATCH_CFG := "user://test_cwj_settings.cfg"
# pvy on the FIRE frame (jump sets 320 + wings*60, then the same update's
# gravity-first block subtracts 950*dt before py integrates):
const PVY_NO_WINGS := 320.0 - 950.0 * DT      # 304.1667
const PVY_WINGS := 380.0 - 950.0 * DT         # 364.1667
const CD_FRAMES := 80                          # jumpCd 1.2 s = 72 f, +margin


func _wipe_scratch() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(SCRATCH_CFG)
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for i in 3:
			if dir.file_exists("slot%d.json" % i):
				dir.remove("slot%d.json" % i)


## Out-of-tree -s boot: menu + creature stage, the creature _ready invoked
## once manually; legs 1 (the landfall genome) and DNA to spend freely
## (bot.test.ts:98 primer — the TS bot mutates ctx.dna directly; the genome
## edit stays on the editor's own click path).
func _boot() -> Variant:
	_wipe_scratch()
	var ctx: Variant = ContextScript.new(SEED)
	var g: Variant = GameScript.new(ctx)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	g.i18n.settings_path = SCRATCH_CFG
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.register(MenuStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	g.stages["creature"]._ready()
	g.start()
	g.context.genome["legs"] = 1
	g.context.dna = 9999.0
	g.switch_stage("creature")
	return g


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the recorder-Callable cycle into this test instance
		g.free()


func _part_row(ed: Variant, part_id: String) -> Dictionary:
	for r in ed.rows:
		if String(r["kind"]) == "part" and String(r["def"]["id"]) == part_id:
			return r
	return {}


## One REAL loop step with Space as the frame's one-shot (the wrapper state
## handle_event would have produced; end_frame clears it inside the step).
func _space_step(g: Variant) -> void:
	g.input.keys_pressed["Space"] = true
	g.step_for_testing(1, DT)


## Grounded quiet frames: no keys, the sim runs (jumpCd drains, arcs land).
func _idle_steps(g: Variant, n: int) -> void:
	for i in n:
		g.step_for_testing(1, DT)


# ---- test 1: buy → close → the FIRST jump already reads the live genome -------

func test_first_jump_after_editor_close_reads_live_genome() -> void:
	var g: Variant = _boot()
	var st: Variant = g.stages["creature"]
	var sim: Variant = st.sim
	var ed: Variant = st.editor_inst
	eq(sim.ctx, g.context, "the sim's ctx IS the game context (identity)")
	eq(int(g.context.genome.get("wings", 0)), 0, "wings start at 0")

	# wings-0 baseline through the REAL loop routing (blocked gate → stage
	# update → T3 snapshot → sim): the discriminator the QC2 window blurred.
	_space_step(g)
	approx(float(sim.pvy), PVY_NO_WINGS,
			"baseline jump fires at the wings-0 pvy (fire frame, gravity-first)")
	_idle_steps(g, CD_FRAMES)  # drain jumpCd, land
	eq(float(sim.py), 0.0, "baseline jumper landed")
	ok(float(sim.jumpCd) <= 0.0, "jumpCd drained before the buy")

	# REAL editor buy: show → click_part('+') on the wings row
	ed.show("creature")
	ok(bool(ed.open), "editor opens in creature mode")
	var row := _part_row(ed, "wings")
	ok(not row.is_empty(), "the wings row exists in the editor rows")
	ed.click_part(row, "+")
	eq(int(g.context.genome.get("wings", 0)), 1, "the buy bumped genome.wings")
	eq(int(g.context.dna), 9939, "the buy charged 60 DNA (9999 → 9939)")
	eq(float(sim.pStats["speed"]), 80.0, "sim pStats.speed is the wings-1 value (54 → 80)")

	# REAL dirty close (the QC2 flow): close() runs the dirty-save path
	ed.close()
	eq(bool(ed.open), false, "the editor closed")
	ok(FileAccess.file_exists("user://saves/slot0.json"),
			"the dirty close persisted the save (dirty_since_save path)")
	eq(int(g.context.genome.get("wings", 0)), 1, "genome.wings still 1 after close")
	eq(sim.ctx, g.context, "the sim's ctx is still the game context after close")

	# THE M2 PIN: jump ×5 through the REAL loop routing — every fire,
	# starting with the FIRST after the close, reads wings live.
	for i in 5:
		_space_step(g)
		approx(float(sim.pvy), PVY_WINGS,
				"jump %d after close fired at the wings-1 pvy (first post-close jump included)" % (i + 1))
		_idle_steps(g, CD_FRAMES)
		eq(float(sim.py), 0.0, "jump %d landed back on the ground" % (i + 1))
	eq(int(g.context.genome.get("wings", 0)), 1, "genome.wings unchanged by the jumps")
	_drop(g)
	_wipe_scratch()


# ---- test 2: the freeze-resume shape the QC2 artifact rode on ------------------
# A pre-buy jump arc, the editor opened mid-arc (the sim freezes — game.gd's
# blocked branch skips current.update), the wings bought while frozen, the
# editor closed: the resumed arc descends from the FROZEN pre-buy py (a py-max
# window over the close reads the wings-0 apex — the QC2 51.25 signature),
# while the first jump that actually FIRES after the close reads wings live.

func test_midair_editor_freeze_resume_then_first_fire_reads_live_genome() -> void:
	var g: Variant = _boot()
	var st: Variant = g.stages["creature"]
	var sim: Variant = st.sim
	var ed: Variant = st.editor_inst
	eq(int(g.context.genome.get("wings", 0)), 0, "wings start at 0 (mid-air test)")

	# the PRE-buy wings-0 jump: fire, then coast to just past the apex
	_space_step(g)
	approx(float(sim.pvy), PVY_NO_WINGS, "pre-buy jump fired (wings-0 pvy)")
	_idle_steps(g, 19)  # k=19: py 51.04, still ascending pvy — mid-arc
	var py_frozen := float(sim.py)
	ok(py_frozen > 40.0, "the arc is mid-flight when the editor opens (py %f)" % py_frozen)

	# editor open + buy + close with NO sim steps between: the real blocked
	# branch runs the editor menus instead of the stage, so the arc freezes
	ed.show("creature")
	ed.click_part(_part_row(ed, "wings"), "+")
	eq(int(g.context.genome.get("wings", 0)), 1, "the mid-arc buy bumped genome.wings")
	ed.close()
	eq(bool(ed.open), false, "the editor closed mid-arc")
	eq(float(sim.py), py_frozen, "the sim froze mid-arc while the editor was open")
	approx(float(sim.pvy), 320.0 - 20.0 * 950.0 * DT,
			"frozen pvy is the pre-buy arc's frame-20 value (fire frame's own gravity step already ran)")

	# resume: the arc descends from the frozen pre-buy py; wait out the landing
	# AND the jumpCd (frozen mid-count, drains only while the sim runs)
	var landed := false
	for i in 120:
		g.step_for_testing(1, DT)
		if float(sim.py) <= 0.0 and float(sim.jumpCd) <= 0.0:
			landed = true
			break
	ok(landed, "the resumed pre-buy arc landed and jumpCd drained")
	ok(float(sim.py) <= py_frozen, "the resumed arc never exceeded the frozen apex")

	# THE PIN: the first fire after the close reads the LIVE genome even when
	# it resumes a pre-buy arc
	_space_step(g)
	approx(float(sim.pvy), PVY_WINGS,
			"the first post-close fire reads wings live (resumed-arc shape)")
	eq(int(g.context.genome.get("wings", 0)), 1, "genome.wings still 1")
	_drop(g)
	_wipe_scratch()
