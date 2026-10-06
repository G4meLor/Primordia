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


# ---- item 2: handle_death ordering (synthesis 4E) --------------------------------
# The death penalty (DNA loss + its toast + the chaos bump) used to sit AFTER
# the _fire("context_event") dispatch — a throwing listener would eat the
# penalty. The penalty now lands BEFORE the dispatch (defensive deviation,
# commented at the site). Note on the letter of the spec ("listener ném"):
# the suite's two-pass runner fails the gate on ANY "SCRIPT ERROR" line, so a
# literally-throwing listener cannot run here — the ordering itself is the
# observable contract (penalty records strictly before the dispatch).

const Ctx := preload("res://src/game/context.gd")
const RngLib := preload("res://src/core/rng.gd")
const CellSim := preload("res://src/game/cell/cell_sim.gd")

const DT := 1.0 / 60.0


## ONE ordered ledger across BOTH channels: the ctx.dna_gained signal and the
## sim hooks — the exact interleaving the fix is about.
class DeathRec extends RefCounted:
	var order: Array = []
	var toasts: Array = []

	func on_dna(_amount, _reason, _x, _y) -> void:
		order.append("dna")

	func on_toast(text, kind, icon) -> void:
		order.append("toast")
		toasts.append([text, kind, icon])

	func on_event(ev, data) -> void:
		order.append("event:%s" % String(ev))


func _death_sim() -> Dictionary:
	var ctx: Variant = Ctx.new(0xC0FFEE)
	var rec := DeathRec.new()
	ctx.dna_gained.connect(rec.on_dna)
	var hooks: Dictionary = {
		"hud_toast": rec.on_toast,
		"context_event": rec.on_event,
		"audio_play": func(n, v, p): pass,
		"cam_shake": func(mag, dur): pass,
		"fx_burst": func(x, y, n, opts): pass,
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CellSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


func test_death_penalty_lands_before_dispatch() -> void:
	var m := _death_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: DeathRec = m["rec"]
	var dna0: int = ctx.dna
	sim.php = 0.0
	sim.update(DT, _inp())
	var lost := floori(float(dna0) * 0.12 + 0.5)
	eq(int(ctx.dna), dna0 - lost, "the DNA loss landed (round 12%)")
	eq(int(rec.order.size()), 3, "dna, toast and the dispatch all recorded")
	if rec.order.size() == 3:
		eq(String(rec.order[0]), "dna", "penalty first — a throwing listener cannot eat it")
		eq(String(rec.order[1]), "toast", "the loss toast fires with the penalty")
		eq(String(rec.order[2]), "event:playerDeath", "the storyteller dispatch comes last")
	if rec.toasts.size() == 1:
		eq(String(rec.toasts[0][0]), "You died — lost %d DNA" % lost,
				"toast carries the exact loss (EN identity)")
