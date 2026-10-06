# Tribe game-level wiring — M4 task 5. The hud.toast_inset lifecycle
# (TribeStage.ts:154 arms 190 in on_enter; game.ts:213 zeroes it on every
# stage switch — the game-level reset rule the native game.gd now ports),
# the creature→tribe founding E2E through the REAL go_to transition (main.gd
# registers TribeStage, so the task-9 placeholder assert is upgraded: the
# founding LANDS, the pack conversion consumes packGenomes once, min 3), and
# the tribe-surface i18n 1:1 (the T8 standard: TS VI object ↔ vi.csv — the
# absences are 1:1 too, banner title/sub strings are absent from the TS VI
# object so both sides draw the EN fallback).
# Save/continue + fall-path pins live in test_world_creature_pins.gd (the
# worldStage pin file, per the task split).
# Headless -s boot: the test_world_creature_pins out-of-tree pattern (run.gd
# drives tests synchronously inside _initialize; stage _ready is invoked ONCE
# manually — the game node is not in the tree in -s mode).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const DT := 1.0 / 60.0
const SEED := 0x7E12E
const TRANSITION_POLL := 600  # brief AC: ≤ 600 frames for card + fade
const OBJECTIVE := "GATHER · BUILD · SURVIVE — raise the Great Totem"
const SCRATCH_CFG := "user://test_hud_tribe_settings.cfg"


# ---- boot -----------------------------------------------------------------------

## The real composition main.gd boots (menu + cell-family stages registered
## at boot), minus cell (this task's flows never visit it) and minus the
## factory (no NEW LIFE mid-run). Manual stepping only.
func _boot(seed_v: int = SEED) -> Variant:
	var ctx: Variant = ContextScript.new(seed_v)
	var g: Variant = GameScript.new(ctx)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	# pin the locale/mute defaults (the shared user cfg may carry anything)
	g.i18n.settings_path = SCRATCH_CFG
	_wipe_cfg()
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.muted = g.i18n.get_muted()
	g.register(MenuStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	g.register(TribeStageScript.new(g))
	g.stages["creature"]._ready()
	g.stages["tribe"]._ready()
	g.start()
	return g


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the hud-dict Callable cycle into this test instance
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


# ---- AC1: the toast inset lifecycle (TS:154 arm / game.ts:213 reset) ------------

## The game-level reset rule: switch_stage zeroes the inset through the live
## hud dict's set_toast_inset key (the native analog of TS writing the shared
## Hud field), BEFORE current.on_exit / next.on_enter — so the outgoing
## instance is zeroed and the incoming stage re-arms (tribe) or never arms
## (creature). The draw side reads it at vh − 30 − inset (hud.gd, TS:274).
func test_switch_stage_resets_toast_inset() -> void:
	var g: Variant = _boot()
	eq(float(g.stages["tribe"].hud_inst.toast_inset), 0.0, "fresh tribe hud inset 0")
	g.switch_stage("tribe")
	eq(String(g.context.stage), "tribe", "tribe entered")
	eq(float(g.current.hud_inst.toast_inset), 190.0, "on_enter armed 190 (TS:154, the first native setter)")
	# the switch reset lands on the OUTGOING (live-dict) instance
	g.switch_stage("creature")
	eq(String(g.context.stage), "creature", "creature entered")
	eq(float(g.stages["tribe"].hud_inst.toast_inset), 0.0,
			"game.ts:213 reset zeroed the outgoing tribe hud")
	eq(float(g.stages["creature"].hud_inst.toast_inset), 0.0, "creature hud never arms")
	# re-entry re-arms through the same persistent instance
	g.switch_stage("tribe")
	eq(String(g.context.stage), "tribe", "re-entered tribe")
	eq(float(g.current.hud_inst.toast_inset), 190.0, "re-entry re-arms 190")
	_drop(g)
	# a bare Game (stub hud dict only — no overlay install) switches clean
	var g2: Variant = GameScript.new(ContextScript.new(1))
	g2.set_process(false)
	g2.loop.is_active_cb = func() -> bool: return false
	g2.register(MenuStageScript.new(g2))
	g2.start()  # switch_stage('menu') rides the stub dict's set_toast_inset
	eq(String(g2.context.stage), "menu", "stub-dict boot switches without the real hud")
	g2.free()


# ---- AC2: the founding E2E ------------------------------------------------------

## The task-9 placeholder is gone: the founding go_to('tribe') LANDS on the
## registered TribeStage, the pack conversion consumes packGenomes once
## (max(3, pack) tribesmen, TribeStage.ts:176-189) and resets the flag, and
## the founding card comes only from the creature side (no tribe-side
## founding banner). The direct found_tribe() call is the TS bot's own cheat
## (bot-creature.test.ts:101 called foundTribe() after its debug cheats);
## the real-input founding leg lives in the bot scene (upgraded there too).
func test_founding_e2e_lands_registered_tribe() -> void:
	_wipe_saves()
	var g: Variant = _boot()
	g.switch_stage("creature")
	g.step_for_testing(10, DT)
	var sim: Variant = g.current.sim
	sim.debug_grant(999.0, 3)   # the documented debug cheats (bot law)
	sim.debug_spawn_pack(2)
	g.step_for_testing(3, DT)
	sim.found_tribe()           # fires the REAL go_to hook → game.go_to
	ok(g.transition != null, "founding started the transition")
	eq(String(g.transition["next"]), "tribe", "transition targets tribe")
	eq(String(g.transition["title"]), "THE FIRST FIRE", "the founding card is the creature side's")
	var steps := 0
	while not (String(g.context.stage) == "tribe" and g.transition == null) \
			and steps < TRANSITION_POLL:
		g.step_for_testing(1, DT)
		steps += 1
	eq(String(g.context.stage), "tribe", "the REGISTERED TribeStage landed (%d steps)" % steps)
	# pack conversion consumed the snapshot (TribeStage.ts:176-189)
	eq(String(g.context.flags.get("packGenomes", "")), "[]", "packGenomes reset after conversion")
	eq(g.current.sim.tribe.size(), 3, "max(3, pack 2) tribesmen founded")
	for t in g.current.sim.tribe:
		eq(String(t["role"]), "gather", "founders take the gather role")
	# the arrival hud hooks rode on_enter
	eq(float(g.current.hud_inst.toast_inset), 190.0, "arrival armed the inset")
	eq(String(g.current.hud_inst.show_objective), OBJECTIVE, "objective line set (TS:190)")
	# no tribe-side founding banner — the card came only from the creature
	ok(g.current.hud_inst._cur_banner == null, "no tribe-side founding banner")
	ok(g.current.hud_inst._banner_queue.is_empty(), "banner queue clean")
	_wipe_saves()
	_drop(g)


# ---- i18n 1:1 (the T8 verification standard) --------------------------------------

## The two stage-button tr() sites (i18n.ts:191-192) + the objective line +
## the dynamic death-cause keys translate in VI. The tribe BANNER title/sub
## strings are absent from the TS VI object (grepped src/core/i18n.ts,
## 2026-10-01) — banner payloads stay raw EN keys translated at draw
## (hud.gd), so both sides fall back to EN: the native vi.csv must not carry
## rows TS lacks (adding them would be a divergence, not a fix).
func test_tribe_i18n_mapping_1to1() -> void:
	_wipe_cfg()
	var i: Variant = I18nScript.new(SCRATCH_CFG)
	i.set_lang("vi")
	eq(i.tr_key("R · HUT (40🪵)"), "R · NHÀ (40🪵)", "hut button key translates (i18n.ts:191)")
	ok(i.vi_has("T · TOTEM (100🍒 80🪵)"), "totem button key maps (i18n.ts:192 — VI value == key)")
	ok(i.vi_has(OBJECTIVE), "objective line maps (draw-time tr_key, hud.gd)")
	ok(i.vi_has("Raiders rally beyond the ridge — press 3 to arm warriors!"),
			"first-raid hint maps (TS:336)")
	ok(i.vi_has("raiders cut you down") and i.vi_has("the great beast gored you"),
			"lastDeathCause keys map (TS:430 translate(this.lastDeathCause))")
	ok(i.vi_has("BACK TO THE WILDS") and i.vi_has("gather your strength and found a new people"),
			"fall card keys map (TS:396)")
	ok(i.vi_has("THE FIRST FIRE") and i.vi_has("THE FIRST CITY"),
			"founding/victory card titles map")
	# the absences are 1:1: no tribe banner string exists in the TS VI object
	for raw in ["THE TRIBE HAS FALLEN", "the wilds take you back — stronger",
			"THE GREAT TOTEM", "your people carve the sky", "defend the huts",
			"A HUT BURNS", "your people scatter", "unified by drums",
			"THE BEAST DESTROYS A HUT", "THE GREAT BEAST FALLS",
			"feast for a week (+60 food)", "LIGHTNING SPLITS A HUT"]:
		ok(not i.vi_has(raw), "banner key absent from VI like TS: %s" % raw)
		eq(i.tr_key(raw), raw, "EN fallback parity: %s" % raw)
	i.set_lang("en")
	TranslationServer.set_locale("en")
	_wipe_cfg()


# ---- composed/unwrapped TS sites stay unwrapped (the T8 exemption) ---------------

## TS:550 `Totem needs 100 food + 80 wood (have …)` and TS:1422
## `🗿 TOTEM ${p}%` are UNWRAPPED template literals in TS — the native sites
## compose raw too (no tr() around the literal). Pinned against a regression
## that "helpfully" wraps them (that would diverge from TS). TS:521
## `Everyone: ${role}` JOINED this family in QC r3 F6 — the TEMPLATE side now
## goes through tr() (the key ships in vi.csv; composed raw it was an
## orphan-key miss) while the role value stays raw.
func test_unwrapped_sites_stay_unwrapped() -> void:
	var src := FileAccess.get_file_as_string("res://src/game/tribe/tribe_sim.gd")
	ok(src.contains("tr(\"Everyone:\")"), "Everyone: template translated first (QC r3 F6)")
	ok(src.contains("\"Totem needs 100 food + 80 wood (have %d/%d)\""),
			"Totem needs… composed raw (TS:550 unwrapped)")
	var stage_src := FileAccess.get_file_as_string("res://src/game/tribe/tribe_stage.gd")
	ok(stage_src.contains("🗿 TOTEM %d%%"), "active-totem label composed raw (TS:1422 unwrapped)")
