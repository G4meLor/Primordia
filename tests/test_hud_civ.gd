# Civ game-level wiring — M5 task 4, M6 task 6 upgrades. The registration
# contract (main.gd BOTH lists, boot order cell → creature → tribe → civ →
# space, the constructor's context-rng branch joining the boot-order pin —
# the exactly-5 draw), the hud.toast_inset 150 lifecycle (CivStage.ts:120
# arms 150 in on_enter; game.ts:213 zeroes it on every stage switch —
# game.gd:262), the M4 bot test's placeholder assert UPGRADED (with civ
# registered, the tribe victory go_to('civ', THE FIRST CITY) lands the REAL
# CivStage — no double banner: the title comes from the tribe side), the
# M5 victory → space placeholder UPGRADED in turn (with space REGISTERED the
# civ victory lands the REAL SpaceStage — the M6 task-6 landing flow), the
# brick-hardening CONTINUE E2E (a unified save auto-fires the space
# transition — the old silent softlock, TS:123-128 — and now LANDS space),
# and the civ-surface i18n 1:1 (the T8 standard: the 12 t() sites of
# CivStage.ts ↔ vi.csv ↔ the TS VI object; the raw composed/unwrapped sites
# pinned absent from BOTH). civState save/continue + the guards E2E live in
# test_world_creature_pins.gd; the space-surface flows (ending, spaceWorld
# continue, i18n) live in test_hud_space.gd (the M6 task-6 file split).
# Headless -s boot: the test_hud_tribe out-of-tree pattern (run.gd drives
# tests synchronously inside _initialize; stage _ready is invoked ONCE
# manually — the game node is not in the tree in -s mode).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const MainScript := preload("res://src/main.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const DT := 1.0 / 60.0
const SEED := 0xC1AB4
const TRANSITION_POLL := 600  # brief AC: ≤ 600 frames for card + fade
const VICTORY_POLL := 2400  # the honest totem ride ~21 s + victoryT 2.5 s
const OBJECTIVE := "UNIFY THE PLANET — slider keys Q/W/E · launch armadas with 1/2/3"
const SPACE_TITLE := "THE BLACK OCEAN"
const SPACE_SUB := "a planet was never going to be enough"
const SPACE_OBJECTIVE := "SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve"
const SPACE_KINDS := ["lush", "ocean", "volcanic", "barren", "lush", "barren"]
const SCRATCH_CFG := "user://test_hud_civ_settings.cfg"


# ---- boot -----------------------------------------------------------------------

## The real composition main.gd boots (menu + the five gameplay stages in
## main.gd's register order — menu LAST, exactly main.gd), minus cell for the
## flows that never visit it (test_hud_tribe precedent) and minus the factory
## (no NEW LIFE mid-run). Manual stepping only. `order` reshuffles the
## gameplay-stage register order for the boot-order branch pin.
func _boot(seed_v: int = SEED, with_cell := false, order: Array = []) -> Variant:
	var gameplay: Array = order if not order.is_empty() \
			else ["cell", "creature", "tribe", "civ", "space"]
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
	for id_v in gameplay:
		var id := String(id_v)
		var st: Variant = null
		match id:
			"cell":
				st = CellStageScript.new(g)
			"creature":
				st = CreatureStageScript.new(g)
			"tribe":
				st = TribeStageScript.new(g)
			"civ":
				st = CivStageScript.new(g)
			"space":
				st = SpaceStageScript.new(g)
		g.register(st)
		st._ready()  # the tree would normally fire this at register time
	g.register(MenuStageScript.new(g))
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


## A real InputEventKey through the wrapper (test_hud_creature precedent) —
## the stage snapshot the stage's update() builds reads keys_pressed.
func _feed_key(g: Variant, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	g.input.handle_event(ev)


# ---- registration contract (main.gd, both lists) ---------------------------------

## The M4 task-5 pin shape (test_tribe_scene.test_main_registers_tribe_stage):
## source-text pins on main.gd — the preload, the boot register AND the
## quit-to-title fresh-instance list (the drifter rule: gameplay stages only,
## the menu persists), in the boot order cell → creature → tribe → civ →
## space (the M6 task-6 growth — space in BOTH lists, the drifter rule).
func test_main_registers_civ_stage() -> void:
	var src: String = (MainScript as Script).source_code
	ok(src.find("res://src/game/civ/civ_stage.gd") >= 0, "main preloads the civ stage")
	ok(src.find("game.register(CivStageScript.new(game))") >= 0,
			"main registers CivStage at boot")
	ok(src.find("res://src/game/space/space_stage.gd") >= 0, "main preloads the space stage")
	ok(src.find("game.register(SpaceStageScript.new(game))") >= 0,
			"main registers SpaceStage at boot (M6)")
	# the M6 factory tail: the list wraps, so the space entry ends it on its
	# own line (the M5 'TribeStageScript.new(game), CivStageScript.new(game)]'
	# shape grew a tail — see test_tribe_scene's matching update)
	ok(src.find("SpaceStageScript.new(game)]") >= 0,
			"the NEW LIFE factory rebuilds the space stage too (after civ)")
	# the boot register order cell → creature → tribe → civ → space (the
	# branch-draw order every stage constructor's context-rng branch follows)
	var i_cell := src.find("game.register(CellStageScript.new(game))")
	var i_creature := src.find("game.register(CreatureStageScript.new(game))")
	var i_tribe := src.find("game.register(TribeStageScript.new(game))")
	var i_civ := src.find("game.register(CivStageScript.new(game))")
	var i_space := src.find("game.register(SpaceStageScript.new(game))")
	ok(i_cell >= 0 and i_cell < i_creature and i_creature < i_tribe
			and i_tribe < i_civ and i_civ < i_space,
			"boot register order cell → creature → tribe → civ → space")


## The constructor's context-rng branch joins the boot-order pin (every stage
## constructor `this.rng = game.context.rng.branch()`): the boot draws EXACTLY
## five branches — cell, creature, tribe, civ, space, in register order — the
## same order a fresh same-seed context replays. Pinned behaviorally: same
## order → identical branch states (determinism); a reshuffled order shifts
## exactly the stages whose branch POSITION moved.
func test_boot_order_branch_pin() -> void:
	var g1: Variant = _boot(SEED, true)
	var states := {}
	for id in ["cell", "creature", "tribe", "civ", "space"]:
		var st: Variant = g1.stages[id]
		ok(st.sim != null, "%s stage built its sim at boot" % id)
		states[id] = int(st.sim.rng.state())
	# the boot consumed EXACTLY five context branches (the 5th is the space
	# constructor's — one per gameplay stage _ready, nothing else draws; the
	# space sim's INTERNAL draws — chaos deck, planet ecos — ride the STAGE
	# branch, not the context stream)
	var ref: Variant = ContextScript.new(SEED)
	for i in 5:
		ref.rng.branch()
	eq(int(g1.context.rng.state()), int(ref.rng.state()),
			"boot drew exactly 5 context branches (cell/creature/tribe/civ/space)")
	_drop(g1)
	# same order, same seed → identical branch states
	var g2: Variant = _boot(SEED, true)
	for id in ["cell", "creature", "tribe", "civ", "space"]:
		eq(int(g2.stages[id].sim.rng.state()), states[id],
				"same boot order → identical %s branch state" % id)
	_drop(g2)
	# the order is LOAD-BEARING: swapping civ and tribe moves exactly their
	# two branches (cell stays 1st, creature stays 2nd, space keeps the 5th —
	# cell-first in BOTH boots on purpose: the creature sim bootstraps ctx.eco
	# on its first construction, so a civ-first boot would change its
	# constructor PATH, not just its branch position — a confound, not the pin)
	var g3: Variant = _boot(SEED, true, ["cell", "creature", "civ", "tribe", "space"])
	ok(int(g3.stages["civ"].sim.rng.state()) != states["civ"],
			"the civ/tribe swap shifts the civ branch (3rd, not 4th)")
	ok(int(g3.stages["tribe"].sim.rng.state()) != states["tribe"],
			"the civ/tribe swap shifts the tribe branch (4th, not 3rd)")
	eq(int(g3.stages["cell"].sim.rng.state()), states["cell"],
			"cell keeps the 1st branch under the swap")
	eq(int(g3.stages["creature"].sim.rng.state()), states["creature"],
			"creature keeps the 2nd branch under the swap")
	eq(int(g3.stages["space"].sim.rng.state()), states["space"],
			"space keeps the 5th branch under the swap")
	_drop(g3)
	# and the 5th position itself is load-bearing: swapping civ and space
	# moves exactly their two branches (tribe keeps the 3rd)
	var g4: Variant = _boot(SEED, true, ["cell", "creature", "tribe", "space", "civ"])
	ok(int(g4.stages["space"].sim.rng.state()) != states["space"],
			"the civ/space swap shifts the space branch (4th, not 5th)")
	ok(int(g4.stages["civ"].sim.rng.state()) != states["civ"],
			"the civ/space swap shifts the civ branch (5th, not 4th)")
	eq(int(g4.stages["tribe"].sim.rng.state()), states["tribe"],
			"tribe keeps the 3rd branch under the swap")
	_drop(g4)


# ---- AC2: the toast inset lifecycle (TS:120 arm / game.ts:213 reset) -------------

## The game-level reset rule with the civ values: switch_stage zeroes the
## inset through the live hud dict's set_toast_inset key BEFORE the outgoing
## on_exit, and the civ stage re-arms 150 in on_enter (CivStage.ts:120 —
## "clear the ruler portrait"). The draw side reads it at vh − 30 − inset
## (hud.gd:303, the seam the tribe/creature tests already pin at hud level).
func test_switch_stage_resets_toast_inset() -> void:
	var g: Variant = _boot()
	eq(float(g.stages["civ"].hud_inst.toast_inset), 0.0, "fresh civ hud inset 0")
	g.switch_stage("civ")
	eq(String(g.context.stage), "civ", "civ entered")
	# the save_all seam exists on the stage (game.save_all →
	# current.persist_state → the sim — the chain the flows below drive)
	ok(g.current.has_method("persist_state"), "the civ stage exposes persist_state")
	eq(float(g.current.hud_inst.toast_inset), 150.0,
			"on_enter armed 150 (CivStage.ts:120, clears the ruler portrait)")
	eq(String(g.current.hud_inst.show_objective), OBJECTIVE,
			"objective set (CivStage.ts:121)")
	# the switch reset lands on the OUTGOING (live-dict) instance
	g.switch_stage("creature")
	eq(String(g.context.stage), "creature", "creature entered")
	eq(float(g.stages["civ"].hud_inst.toast_inset), 0.0,
			"game.ts:213 reset zeroed the outgoing civ hud")
	eq(float(g.stages["creature"].hud_inst.toast_inset), 0.0, "creature hud never arms")
	# re-entry re-arms through the same persistent instance
	g.switch_stage("civ")
	eq(String(g.context.stage), "civ", "re-entered civ")
	eq(float(g.current.hud_inst.toast_inset), 150.0, "re-entry re-arms 150")
	_drop(g)
	# a bare Game (stub hud dict only — no overlay install) switches clean
	var g2: Variant = GameScript.new(ContextScript.new(1))
	g2.set_process(false)
	g2.loop.is_active_cb = func() -> bool: return false
	g2.register(MenuStageScript.new(g2))
	g2.start()  # switch_stage('menu') rides the stub dict's set_toast_inset
	eq(String(g2.context.stage), "menu", "stub-dict boot switches without the real hud")
	g2.free()


# ---- AC3: the tribe → civ landing (the M4 placeholder assert, upgraded) ----------

## The M4 bot test's placeholder (civ unregistered → the victory switch
## no-ops, the tribe stage remains) is UPGRADED: with civ REGISTERED, the
## tribe victory go_to('civ', {THE FIRST CITY / drums become laws…}) lands
## the REAL CivStage — on_enter fires through the real hooks (toast_inset
## 150, objective set), the constructor-seeded board stands (4 cities), and
## there is NO double banner (the card title comes from the tribe side's
## go_to — the M4 task-4 ruling, the founding card precedent).
func test_tribe_victory_lands_registered_civ() -> void:
	_wipe_saves()
	var g: Variant = _boot()
	g.switch_stage("tribe")  # direct entry (headless pattern — the fall-path precedent)
	g.step_for_testing(5, DT)
	var tsim: Variant = g.current.sim
	eq(tsim.tribe.size(), 3, "fresh village founded (the totem workers)")
	# hermeticity: the scheduler's effective gap (~24 s at the boot chaos
	# 0.15) sits INSIDE the honest totem ride — swap the deck out (the T3
	# probe-swap idiom, emptied) so no tribe chaos event can steal the leg
	tsim.chaos.defs = []
	# the honest victory ride: stockpile via the documented debug_grant cheat
	# (the task-6 bot's stockpile cheat), the totem raised through the REAL
	# KeyT path (the bot's xvfb click drives the same sim entry point)
	tsim.debug_grant(400.0, 400.0)
	_feed_key(g, KEY_T)
	g.step_for_testing(1, DT)
	eq(bool(tsim.totem["active"]), true, "KeyT raised the totem (food/wood granted)")
	# workers 3 × 1.6/s → ~21 s to 100, then victoryT > 2.5 s → save_all +
	# go_to('civ') (TribeStage.ts:400-409)
	var card: Variant = null
	var steps := 0
	while steps < VICTORY_POLL:
		g.step_for_testing(1, DT)
		steps += 1
		if g.transition != null:
			card = g.transition
			break
	ok(card != null, "the tribe victory fired its transition (%d steps)" % steps)
	if card == null:
		_wipe_saves()
		_drop(g)
		return
	eq(String(card["next"]), "civ", "the victory go_to targets civ")
	eq(String(card["title"]), "THE FIRST CITY", "the victory card is the tribe side's (TS:407)")
	eq(String(card["sub"]), "drums become laws; laws become empires", "the victory card sub")
	eq(bool(tsim.victoryFired), true, "victoryFired latched (TS:405)")
	# the victory flush rode the go_to (TS:406 — save_all BEFORE go_to; the
	# game.save_all → current.persist_state chain reached the tribe stage)
	ok(g.context.flags.has("tribeState"), "the victory save_all flushed the tribe blob")
	# land the card + fade
	var steps2 := 0
	while not (String(g.context.stage) == "civ" and g.transition == null) \
			and steps2 < TRANSITION_POLL:
		g.step_for_testing(1, DT)
		steps2 += 1
	eq(String(g.context.stage), "civ", "the REGISTERED CivStage landed (%d steps)" % steps2)
	eq(String(g.current.id), "civ", "the live stage is the civ stage")
	# the arrival hud hooks rode on_enter through the REAL stage hooks
	eq(float(g.current.hud_inst.toast_inset), 150.0,
			"arrival armed the civ inset 150 (CivStage.ts:120)")
	eq(String(g.current.hud_inst.show_objective), OBJECTIVE,
			"arrival set the objective (CivStage.ts:121)")
	# the outgoing tribe hud was zeroed by the game-level switch reset
	eq(float(g.stages["tribe"].hud_inst.toast_inset), 0.0,
			"game.ts:213 zeroed the outgoing tribe hud before civ re-armed")
	# the constructor-seeded board stands
	eq(g.current.sim.cities.size(), 4, "the constructor-seeded board stands (capital + 3 rivals)")
	eq(String(g.current.sim.cities[0]["owner"]), "you", "the capital is yours")
	# NO double banner — the title came only from the tribe side's card
	ok(g.current.hud_inst._cur_banner == null, "no civ-side landing banner")
	ok(g.current.hud_inst._banner_queue.is_empty(), "banner queue clean")
	_wipe_saves()
	_drop(g)


# ---- AC5: the civ victory → the REAL space landing (the M5 placeholder ------
# ---- assert, upgraded in M6 task 6) ---------------------------------------------

## Unify through the documented cheat surface (debug_set_influence grants + a
## tick — the sim header's documented bot victory leg), the victory fires
## save_all + go_to('space', {THE BLACK OCEAN …}); with space REGISTERED the
## card lands the REAL SpaceStage — on_enter arms the objective, the C1 gate
## no-ops on the same world, the constructor 6-planet system stands, and the
## outgoing civ hud was zeroed by the game-level switch reset (space never
## re-arms an inset — TS space has no set_toast_inset).
func test_victory_lands_registered_space() -> void:
	_wipe_saves()
	var g: Variant = _boot()
	ok(g.stages.has("space"), "space is REGISTERED (the landing premise)")
	g.switch_stage("civ")
	g.step_for_testing(5, DT)
	var sim: Variant = g.current.sim
	# the grants + a tick drive the REAL hearts → flip → victory path
	sim.debug_set_influence(1, 100.0)
	sim.debug_set_influence(2, 100.0)
	sim.debug_set_influence(3, 100.0)
	var card: Variant = null
	var steps := 0
	while steps < 600:
		g.step_for_testing(1, DT)
		steps += 1
		if g.transition != null:
			card = g.transition
			break
	ok(card != null, "the victory fired its transition (%d steps)" % steps)
	if card == null:
		_wipe_saves()
		_drop(g)
		return
	eq(String(card["next"]), "space", "the victory go_to targets space (TS:295)")
	eq(String(card["title"]), SPACE_TITLE, "victory title")
	eq(String(card["sub"]), SPACE_SUB, "victory sub")
	eq(bool(sim.victoryFired), true, "victoryFired latched (TS:291)")
	# the flush rode FIRST (TS:293): game.save_all → current.persist_state →
	# sim.persist_state — the wiring chain this task verifies end to end
	var blob: Variant = JSON.parse_string(String(g.context.flags["civState"]))
	ok(blob is Dictionary, "the flush wrote the civ blob")
	if blob is Dictionary:
		eq(bool(blob["victoryFired"]), true, "the flush carried victoryFired")
		eq((blob["cities"] as Array).size(), 4, "the flush carried the board")
	# the flush is a REAL save: the slot on disk carries the blob too
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("user://saves/slot0.json"))
	ok(parsed is Dictionary, "the victory save_all wrote the slot")
	if parsed is Dictionary:
		eq(String(parsed["stage"]), "civ", "slot stage is civ")
		var disk: Variant = JSON.parse_string(String(parsed["flags"]["civState"]))
		ok(disk is Dictionary and bool(disk["victoryFired"]),
				"the disk blob carries victoryFired")
	# ride the card + fade out: the REGISTERED SpaceStage lands
	var steps2 := 0
	while not (String(g.context.stage) == "space" and g.transition == null) \
			and steps2 < TRANSITION_POLL:
		g.step_for_testing(1, DT)
		steps2 += 1
	eq(String(g.context.stage), "space", "the REGISTERED SpaceStage landed (%d steps)" % steps2)
	eq(String(g.current.id), "space", "the live stage is the space stage")
	eq(bool(sim.victoryFired), true, "the civ latch holds after the ride")
	# the arrival hooks rode on_enter through the REAL stage hooks
	eq(String(g.current.hud_inst.show_objective), SPACE_OBJECTIVE,
			"arrival armed the space objective (SpaceStage.ts:188)")
	eq(float(g.current.hud_inst.toast_inset), 0.0,
			"space arms NO inset (TS space has no set_toast_inset — the reset default holds)")
	eq(float(g.stages["civ"].hud_inst.toast_inset), 0.0,
			"game.ts:213 zeroed the outgoing civ hud (its 150 never comes back)")
	# the constructor 6-planet system stands (no spaceWorld blob on a first
	# landing → nothing restored)
	eq(g.current.sim.planets.size(), 6, "the constructor system stands (6 planets, TS:106)")
	for i in 6:
		eq(String(g.current.sim.planets[i]["kind"]), SPACE_KINDS[i],
				"planet %d kind rides the fixed ring (TS:105)" % i)
	# the C1 gate no-ops on the boot's own world (same seed → no deck rebuild)
	eq(int(g.current.sim.deckSeed), int(g.context.world["seed"]),
			"same world → deckSeed unchanged (C1 gate no-op, TS:183)")
	ok(g.current.hud_inst._cur_banner == null, "no space-side landing banner")
	# the landed sandbox draws clean right after the handoff (no crash)
	g.current.render()
	ok(true, "space render() right after the civ victory landing")
	_wipe_saves()
	_drop(g)


# ---- AC6: brick hardening (the old silent softlock, TS:123-128) ------------------

## A CONTINUE that restores an ALREADY-UNIFIED board (victoryFired true + all
## owned) must fire the space transition immediately — on_enter's brick gate —
## with the exact title/sub, instead of the old silent softlock.
func test_brick_hardening_continue_auto_space() -> void:
	_wipe_saves()
	# run 1: author the unified save — the sim's own persist writes the blob
	# (victoryFired true, all owned) through the REAL save_all seam
	var g1: Variant = _boot()
	g1.switch_stage("civ")
	g1.step_for_testing(2, DT)
	var sim1: Variant = g1.current.sim
	for i in 4:
		sim1.cities[i]["owner"] = "you"  # test-fixture write (the TS I-bal family drives the sim surface)
	sim1.victoryFired = true
	sim1.mil = 7.0  # a distinctive lane for the restore pin below
	ok(g1.save_all(), "the unified civ save wrote the slot")
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("user://saves/slot0.json"))
	eq(String(parsed["stage"]), "civ", "slot stage is civ")
	var blob: Variant = JSON.parse_string(String(parsed["flags"]["civState"]))
	ok(blob is Dictionary and bool(blob["victoryFired"]),
			"the slot blob carries victoryFired true")
	_drop(g1)
	# run 2: CONTINUE → the WELCOME BACK ride lands civ → on_enter restores
	# the unified board → the brick gate fires go_to('space') behind the card
	var g2: Variant = _boot()
	eq(String(g2.context.stage), "menu", "boot 2 sits on the menu")
	g2.current.continue_slot(0)
	eq(String(g2.transition["title"]), "WELCOME BACK", "continue card title")
	var space_card: Variant = null
	var steps := 0
	while steps < 1200:
		g2.step_for_testing(1, DT)
		steps += 1
		if g2.transition != null and String(g2.transition["next"]) == "space":
			space_card = g2.transition
			break
	ok(space_card != null,
			"the space transition fired behind the CONTINUE ride (%d steps)" % steps)
	if space_card == null:
		_wipe_saves()
		_drop(g2)
		return
	eq(String(space_card["title"]), SPACE_TITLE, "brick title exact (TS:127)")
	eq(String(space_card["sub"]), SPACE_SUB, "brick sub exact (TS:127)")
	# the restore happened first: the unified board is what stood
	eq(String(g2.context.stage), "civ", "the restore landed civ before the space card")
	eq(float(g2.current.sim.mil), 7.0, "restore_state true (the unified board restored)")
	# ride it out: with space REGISTERED the brick card lands the REAL
	# SpaceStage — the sandbox of the unified run (M6 task 6 upgrade; the
	# M5 placeholder tail asserted the civ stage remained)
	var steps2 := 0
	while not (String(g2.context.stage) == "space" and g2.transition == null) \
			and steps2 < TRANSITION_POLL:
		g2.step_for_testing(1, DT)
		steps2 += 1
	eq(g2.transition, null, "the brick space card completed (%d steps)" % steps2)
	eq(String(g2.context.stage), "space", "the brick card landed the space stage")
	eq(String(g2.current.id), "space", "the live stage is space")
	# the space save never visited space: the constructor system stands
	eq(g2.current.sim.planets.size(), 6, "the constructor system stands after the brick landing")
	eq(String(g2.current.hud_inst.show_objective), SPACE_OBJECTIVE,
			"the objective armed on the brick landing")
	_wipe_saves()
	_drop(g2)


# ---- i18n 1:1 (the T8 verification standard) --------------------------------------

## Every t() site of the civ surface maps in vi.csv (the TS VI object 1:1 —
## grepped src/core/i18n.ts 2026-10-03: the 12 keys below at :183/:193/:197-202/
## :294-295/:538-539/:588-589). The RAW composed/unwrapped sites stay raw —
## normative absences pinned vi_has == false with EN fallback parity. The
## objective line is the draw-time case (raw assignment at CivStage.ts:121,
## translated at draw — hud.gd:266 tr_key). The transition card keys are the
## game-level draw translation (game.gd draw_transition_veil).
func test_civ_i18n_mapping_1to1() -> void:
	_wipe_cfg()
	var i: Variant = I18nScript.new(SCRATCH_CFG)
	i.set_lang("vi")
	# the 12 t() sites (CivStage.ts:213/:319/:348/:482/:497/:520/:631/:633/
	# :634/:635/:652/:657)
	var t_sites := [
		"Board full — lower another slider first",
		"No city left to persuade — build output!",
		"armada →",
		"Golden age! Your cities flourish.",
		"A rival golden age! Their forges and fleets swell.",
		"Trade winds! Every market on the planet hums.",
		"NATIONAL OUTPUT",
		"Q/A Military",
		"W/S Culture",
		"E/D Economy",
		"1 attack · 2 charm caravan · 3 trade caravan",
		"THE PLANET IS UNITED",
	]
	for key in t_sites:
		ok(i.vi_has(String(key)), "t() site maps: %s" % key)
	# spot-check the values against the TS VI object (value drift would pass
	# a vi_has-only pin)
	eq(i.tr_key("NATIONAL OUTPUT"), "SỨC MẠNH QUỐC GIA", "value parity (TS VI :193)")
	eq(i.tr_key("armada →"), "hạm đội →", "value parity (TS VI :295)")
	eq(i.tr_key("THE PLANET IS UNITED"), "HÀNH TINH ĐÃ THỐNG NHẤT",
			"value parity (TS VI :202)")
	# the objective line: raw at the emit site (CivStage.ts:121), translated
	# at DRAW (hud.gd:266) — it maps (TS VI :183)
	ok(i.vi_has(OBJECTIVE), "objective line maps (draw-time tr_key, hud.gd)")
	# the transition card keys (tribe victory + the space/brick cards) map —
	# translated at the game-level card draw (TS VI :408-411)
	ok(i.vi_has("THE FIRST CITY") and i.vi_has("drums become laws; laws become empires"),
			"the tribe victory card keys map")
	ok(i.vi_has(SPACE_TITLE) and i.vi_has(SPACE_SUB), "the space card keys map")
	# the RAW composed/unwrapped sites — normative absences, 1:1 with TS
	# (QC round-2 B3: '👑 yours' LEFT this list — native translates the
	# ownership tag, TS:598 renders it raw; see the mapped pin below)
	for raw in ["+1 %s ← %s",  # TS:210 — composed raw
			"%s needs 2 output in its lane (raise with Q/W/E)",  # TS:314 raw
			"%s needs %s+ more output in its lane (5+ total) — raise with Q/W/E, or lower a full slider",  # TS:333 raw
			"%s %s %s (power %s)",  # TS:348 — raw template AROUND the t('armada →')
			"JOINS YOUR PLANETARY STATE",  # TS:387/:446 banner suffix, raw
			"REVOLTS!",  # TS:453 banner suffix, raw
			"%s shells your capital!",  # TS:409 raw
			"Earthquake damages %s!",  # TS:467 raw
			"Unrest in %s! (-40 influence)",  # TS:475 raw
			"%s DECLARES WAR",  # TS:489 raw
			"your capital is shelled"]:  # TS:489 raw
		ok(not i.vi_has(String(raw)), "raw site absent from VI like TS: %s" % raw)
		eq(i.tr_key(String(raw)), String(raw), "EN fallback parity: %s" % raw)
	# the ownership tag: raw in TS (:598), translated natively (QC r2 B3)
	ok(i.vi_has("👑 yours"), "ownership tag maps (native-only wrap, TS:598 renders raw)")
	eq(i.tr_key("👑 yours"), "👑 của bạn", "ownership tag value")
	i.set_lang("en")
	TranslationServer.set_locale("en")
	_wipe_cfg()
