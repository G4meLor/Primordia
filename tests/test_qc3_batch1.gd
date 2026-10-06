# QC round 3 batch 1 fixes (SYNTHESIS-round3.md section 5, batch 1). One test
# cluster per item; each fix landed as its own commit with its cluster added
# here. Headless out-of-tree boots follow the test_creature_editor_stats
# pattern (the -s suite has no live tree — stage _ready runs manually).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")

const SEED := 0x9BEF
const SCRATCH_CFG := "user://test_qc3b1_settings.cfg"


func _wipe_cfg() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(SCRATCH_CFG)


## Out-of-tree -s boot: menu + cell + creature, the gameplay stages' _ready
## invoked manually (creates hud_inst + rebinds game.hud per stage).
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
	g.register(CellStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	g.stages["cell"]._ready()
	g.stages["creature"]._ready()
	g.start()
	g.switch_stage("cell")
	return g


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the recorder-Callable cycle into this test instance
		g.free()


# ---- item 1: stale toasts (synthesis 4A) ----------------------------------------
# Each stage kept a persistent hud_inst and Hud._init taps context.toast — a
# sim toast fanned out into ALL five huds, and a hidden hud never decays its
# ttl (only the live stage's hud gets hud["update"]), so frozen toasts revived
# when the stage became current again (3 agents: cell→creature landfall n=6,
# tribe→civ n=6, creature→tribe n=5).

func test_ctx_toast_lands_in_live_hud_only() -> void:
	var g: Variant = _boot()
	var cell_hud: Variant = g.stages["cell"].hud_inst
	var creature_hud: Variant = g.stages["creature"].hud_inst
	eq(int(cell_hud._toasts.size()), 0, "cell hud starts clean")
	eq(int(creature_hud._toasts.size()), 0, "creature hud starts clean")
	# a sim toast with cell current (the _on_ctx_toast guard path)
	g.context.toast.emit("cell discovery", "good", "📖")
	eq(int(cell_hud._toasts.size()), 1, "live hud receives the ctx toast")
	eq(int(creature_hud._toasts.size()), 0,
			"hidden hud receives NOTHING (the fan-out guard)")
	# the positive path on the other side: creature current → its hud
	g.switch_stage("creature")
	g.context.toast.emit("creature discovery", "info", "•")
	eq(int(creature_hud._toasts.size()), 1, "creature hud receives its own stage's toast")
	eq(int(cell_hud._toasts.size()), 0, "cell hud stays empty while hidden")
	_drop(g)


func test_switch_stage_migrates_live_toasts_and_drops_stale() -> void:
	var g: Variant = _boot()
	var cell_hud: Variant = g.stages["cell"].hud_inst
	var creature_hud: Variant = g.stages["creature"].hud_inst
	# a toast fired right before the transition (cell current, live ttl)
	g.context.toast.emit("just before landfall", "info", "•")
	eq(int(cell_hud._toasts.size()), 1, "pre-transition toast is live in the cell hud")
	# a FROZEN legacy toast in the entering hud (the pre-fix fan-out: a toast
	# that fanned in while creature was hidden and never decayed)
	creature_hud.toast("stale fan-out toast")
	eq(int(creature_hud._toasts.size()), 1, "legacy toast parked in the creature hud")
	# the ttl rides the migration — TS keeps one hud, the decay continues
	var ttl_before := float(cell_hud._toasts[0]["ttl"])
	g.switch_stage("creature")
	eq(int(creature_hud._toasts.size()), 1, "entering hud holds exactly the migrated toast")
	if creature_hud._toasts.size() == 1:
		eq(String(creature_hud._toasts[0]["text"]), "just before landfall",
				"the pre-transition toast shows in the new stage (TS shared-hud ttl)")
		ok(absf(float(creature_hud._toasts[0]["ttl"]) - ttl_before) < 1e-9,
				"the migrated toast keeps its remaining ttl (no revive-fresh)")
	eq(int(cell_hud._toasts.size()), 0, "leaving hud expires clean (no frozen revive)")
	# returning to cell later: nothing frozen comes back — the migrated toast
	# decayed in real time on the creature hud (TS shared-hud ttl)
	creature_hud.update(10.0)
	eq(int(creature_hud._toasts.size()), 0, "the migrated toast decays normally")
	g.switch_stage("cell")
	eq(int(cell_hud._toasts.size()), 0, "returning to cell revives no stale toast")
	eq(int(creature_hud._toasts.size()), 0, "leaving creature expires clean too")
	_drop(g)


func test_switch_stage_menu_leaving_hud_expires_without_target() -> void:
	# to menu: no hud_inst on the menu stage — the leaving list must still die
	# (the guard `next.get("hud_inst") != null` only skips the adopt)
	var g: Variant = _boot()
	var cell_hud: Variant = g.stages["cell"].hud_inst
	g.context.toast.emit("doomed at quit", "info", "•")
	g.switch_stage("menu")
	eq(int(cell_hud._toasts.size()), 0, "quit-to-menu expires the leaving hud too")
	_drop(g)


func test_expire_toasts_dict_key_routes_to_live_hud() -> void:
	# the overlay contract: the live stage's hud dict carries the expire key —
	# switch_stage's migrate reads it — and the game-level stub answers empty
	var g: Variant = _boot()
	g.context.toast.emit("contract probe", "info", "•")
	var carried: Array = g.hud["expire_toasts"].call()
	eq(int(carried.size()), 1, "the live hud dict expire_toasts hands the toast out")
	eq(String(carried[0]["text"]), "contract probe", "the carried entry is the toast")
	eq(int(g.stages["cell"].hud_inst._toasts.size()), 0, "the hud list emptied")
	g.stages["cell"].hud_inst.adopt_toasts(carried)
	eq(int(g.stages["cell"].hud_inst._toasts.size()), 1, "adopt restores the list")
	_drop(g)
