# QC round 1 B1 — the creature editor's buy/sell must refresh the LIVE sim's
# derived stats (TS notifyStatsChanged → CreatureStage.onStatsChanged,
# CreatureStage.ts:1321 — pStats/pmaxHp/packLimit recompute immediately).
# The cell stage binds editor_inst.on_stats_changed → sim.on_stats_changed
# (cell_stage.gd:92); the creature stage shipped without the bind — the hook
# stayed the editor's no-op default (editor.gd:46), so a buy/sell refreshed
# the context stats and the editor preview but sim.pStats/packLimit stayed
# stale until the stage was re-entered. Drives the REAL editor instance of
# the REAL creature stage through the programmatic click path (editor.gd
# header: click_part is the bot.test.ts:132 parity surface) and asserts the
# sim reflects each change NOW, no re-enter. Headless out-of-tree boot
# (test_world_creature_pins pattern).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const PartsScript := preload("res://src/evo/parts.gd")

const DT := 1.0 / 60.0
const SEED := 0x9BEF
const SCRATCH_CFG := "user://test_ces_settings.cfg"


func _wipe_cfg() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(SCRATCH_CFG)


## Out-of-tree -s boot: menu + creature stage, the creature _ready invoked
## once manually (test_world_creature_pins._boot, minus the later stages).
func _boot() -> Variant:
	var ctx: Variant = ContextScript.new(SEED)
	var g: Variant = GameScript.new(ctx)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	# pin the locale/mute defaults (the shared user cfg may carry anything)
	g.i18n.settings_path = SCRATCH_CFG
	_wipe_cfg()
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.register(MenuStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	g.stages["creature"]._ready()
	g.start()
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


func test_editor_buy_sell_updates_sim_stats_immediately() -> void:
	var g: Variant = _boot()
	var st: Variant = g.stages["creature"]
	# the B1 bind itself: the editor hook must be the sim's recompute
	eq(st.editor_inst.on_stats_changed, st.sim.on_stats_changed,
			"editor on_stats_changed is bound to the creature sim's recompute")

	# cross the shore: legs 1, and DNA to spend freely (bot.test.ts:98 primer —
	# the TS bot mutates ctx.dna directly; the genome edits below stay on the
	# editor's own click path)
	g.context.genome["legs"] = 1
	g.context.dna = 9999
	g.switch_stage("creature")
	eq(String(g.context.stage), "creature", "creature stage entered")
	var sim: Variant = st.sim
	var ed: Variant = st.editor_inst
	# on_enter recomputed from the legs-1 genome: 40 + 1*14, size 1 → 54
	eq(float(sim.pStats["speed"]), 54.0, "sim pStats.speed is the legs-1 value on entry")

	ed.show("creature")
	eq(bool(ed.open), true, "editor opens in creature mode")
	eq(ed.mode, "creature", "editor mode is creature")

	# ---- sell legs 1 → 0 through the REAL editor click path -------------------
	ed.click_part(_part_row(ed, "legs"), "-")
	eq(int(g.context.genome["legs"]), 0, "editor sold the leg (creature mode has no shore guard)")
	# THE B1 PIN: the sim's derived stats reflect the sale NOW — no re-enter.
	# legs 0 → the legless worm baseline 24 (size penalty exempt, stats.gd:37).
	eq(float(sim.pStats["speed"]), 24.0, "sim pStats.speed is the legs-0 value immediately")
	eq(float(g.context.stats["speed"]), 24.0, "context stats agree (the pre-fix path that already worked)")

	# ---- buy jaw → damage rises immediately -----------------------------------
	var dmg_before := float(sim.pStats["damage"])
	ed.click_part(_part_row(ed, "jaw"), "+")
	eq(int(g.context.genome["jaw"]), 2, "editor bought a jaw (1 → 2)")
	eq(float(sim.pStats["damage"]), dmg_before + 6.0, "sim pStats.damage rose immediately (jaw 1→2 = +6)")

	# ---- buy arms → packLimit rises immediately --------------------------------
	eq(int(sim.packLimit), 2, "starter pack limit (arms 0, brain 0)")
	ed.click_part(_part_row(ed, "arms"), "+")
	ed.click_part(_part_row(ed, "arms"), "+")
	eq(int(g.context.genome["arms"]), 2, "two arms bought")
	eq(int(sim.packLimit), 3, "sim packLimit rose immediately (2 + arms/2)")

	# ---- buy brain → the brain term too ----------------------------------------
	ed.click_part(_part_row(ed, "brain"), "+")
	ed.click_part(_part_row(ed, "brain"), "+")
	eq(int(sim.packLimit), 4, "sim packLimit follows the brain term too (2 + 1 + 1)")

	_drop(g)
