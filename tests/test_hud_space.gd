# Space game-level wiring — M6 task 6. The space-surface flows on a REAL
# main.gd-parity boot (menu + all five gameplay stages, manual stepping):
# the direct-landing pins (objective armed, the constructor 6-planet system,
# the C1 gate no-op, no landing banner), the game.save_all →
# space_stage.persist_state chain (the has_method seam) + the on_exit persist,
# the 5 s persist cadence through the REAL update loop (the sim-side cadence
# is T2's pin), the toast-inset rule (TS space has NO set_toast_inset — the
# game.ts:213 reset's default 0 holds on every switch, the civ 150 contrast),
# the objective dynamic-override through the REAL hud instance (the finale
# bearing rewrites per-frame — T2 pinned the sim's hook payload; here the hud
# instance RECEIVES it, two different bearings through one instance), the
# ending E2E (a won run via the real KeyF ff / the documented-cheat path →
# endingDone persists → CONTINUE → a-won-run-stays-won TS:256-264 with the
# finale orb restored; the DISMISSED ending sleeps — finale null, no AWAKENS
# replay, the restore timers 99), and the space-surface i18n 1:1 (the T8
# standard: every t() site of SpaceStage.ts ↔ vi.csv ↔ the TS VI object;
# the raw composed/unwrapped sites pinned absent — incl. the VI-member
# banner keys that translate at the hud draw, the M5 card-key precedent).
# The civ→space landing and the registration/branch-pin upgrades live in
# test_hud_civ.gd; the spaceWorld save/continue + the guards E2E live in
# test_world_creature_pins.gd (the M5 file split, d7a5cb8).
# Headless -s boot: the test_hud_civ out-of-tree pattern (run.gd drives tests
# synchronously inside _initialize; stage _ready is invoked ONCE manually).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const GenomeLib := preload("res://src/evo/genome.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const DT := 1.0 / 60.0
const SEED := 0x5ACE5
const TRANSITION_POLL := 900  # WELCOME BACK ride (~3.35 s) + margin
const FF_POLL := 1800  # pop 1 → 20 at 26× ≈ 9.2 s ≈ 555 frames + margin
const OBJECTIVE := "SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve"
const SPACE_KINDS := ["lush", "ocean", "volcanic", "barren", "lush", "barren"]
const CIV_OBJECTIVE := "UNIFY THE PLANET — slider keys Q/W/E · launch armadas with 1/2/3"
const SCRATCH_CFG := "user://test_hud_space_settings.cfg"


# ---- boot -----------------------------------------------------------------------

## The real composition main.gd boots (menu + the five gameplay stages in
## main.gd's register order — menu LAST), minus the factory (no NEW LIFE
## mid-run). Manual stepping only.
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
	for st in [CellStageScript.new(g), CreatureStageScript.new(g),
			TribeStageScript.new(g), CivStageScript.new(g),
			SpaceStageScript.new(g)]:
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


## Real InputEventKey through the OS Input singleton (test_space_scene's
## proven -s-mode path) — the held poll reads is_physical_key_pressed.
## PROCESS-GLOBAL: every user releases before returning.
func _hold_key(physical: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## A one-shot press through the game's own wrapper (test_hud_civ._feed_key
## precedent) — feeds keys_pressed only; the Input singleton held-state is
## untouched, so no thrust side effect.
func _tap_key(g: Variant, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = true
	g.input.handle_event(ev)


## Ride the live transition out to a settled stage (the civ-flow poll shape).
func _ride_to(g: Variant, id: String) -> int:
	var steps := 0
	while not (String(g.context.stage) == id and g.transition == null) \
			and steps < TRANSITION_POLL:
		g.step_for_testing(1, DT)
		steps += 1
	return steps


# ---- the direct landing (constructor system, objective, C1 no-op) ------------------

## Direct entry (the headless fall-path precedent — the civ→space victory
## handoff itself is test_hud_civ's landing flow). on_enter arms the
## objective, the constructor 6-planet system stands, the C1 gate no-ops on
## the boot's own world, no landing banner, and NO toast inset (TS space
## has no set_toast_inset — the game.ts:213 reset default holds).
func test_direct_landing_and_constructor_system() -> void:
	var g: Variant = _boot()
	g.switch_stage("space")
	eq(String(g.context.stage), "space", "space entered")
	g.step_for_testing(2, DT)
	eq(g.current.sim.planets.size(), 6, "the constructor system stands (6 planets, TS:106)")
	for i in 6:
		eq(String(g.current.sim.planets[i]["kind"]), SPACE_KINDS[i],
				"planet %d rides the fixed kind ring (TS:105)" % i)
		ok(g.current.sim.planets[i]["colony"] == null, "planet %d uncolonized (TS:124)" % i)
	eq(String(g.current.hud_inst.show_objective), OBJECTIVE,
			"objective armed (SpaceStage.ts:188)")
	eq(float(g.current.hud_inst.toast_inset), 0.0,
			"space arms NO inset — the reset default holds (no set_toast_inset in TS)")
	eq(int(g.current.sim.deckSeed), int(g.context.world["seed"]),
			"same world → no deck rebuild (C1 gate no-op, TS:183)")
	ok(g.current.hud_inst._cur_banner == null, "no landing banner")
	g.current.render()
	ok(true, "space render() headless")
	_drop(g)


# ---- game.save_all → space_stage.persist_state (the has_method chain) --------------

## game.save_all routes current.persist_state through the has_method gate
## (game.gd:710-713) → the space stage forwards to the sim (persist_colonies)
## → the spaceWorld blob rides the slot. The on_exit persist (TS:270)
## rewrites the flags blob when the stage is left.
func test_save_all_chain_and_on_exit_persist() -> void:
	_wipe_saves()
	var g: Variant = _boot()
	g.switch_stage("space")
	g.step_for_testing(2, DT)
	ok(g.current.has_method("persist_state"),
			"the space stage exposes persist_state (the game.save_all seam)")
	# a distinctive cargo row rides the chain into the blob + the slot
	var genome: Dictionary = GenomeLib.clone_genome(GenomeLib.default_genome())
	genome["size"] = 1.7
	g.current.sim.cargo.append({"genome": genome, "name": "Chainee"})
	ok(g.save_all(), "game.save_all with space current")
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("user://saves/slot0.json"))
	ok(parsed is Dictionary, "the slot parses")
	eq(String(parsed["stage"]), "space", "slot stage is space")
	var blob: Variant = JSON.parse_string(String(parsed["flags"]["spaceWorld"]))
	ok(blob is Dictionary, "the spaceWorld blob rides the slot")
	if blob is Dictionary:
		eq((blob["planets"] as Array).size(), 6, "the blob carries the 6-planet system")
		eq(String((blob["cargo"] as Array)[0]["name"]), "Chainee",
				"the blob carries the cargo row")
		eq(bool(blob["endingDone"]), false, "the blob carries endingDone false")
	# on_exit persists too (TS:270): leaving the stage rewrites the flags blob
	g.current.sim.cargo.append({"genome": genome, "name": "Second"})
	g.switch_stage("creature")
	var flags_blob: Variant = JSON.parse_string(String(g.context.flags["spaceWorld"]))
	ok(flags_blob is Dictionary, "the flags blob survives the switch")
	if flags_blob is Dictionary:
		eq((flags_blob["cargo"] as Array).size(), 2,
				"on_exit → persist_state (TS:270) — the second row rode")
	_wipe_saves()
	_drop(g)


# ---- the 5 s persist cadence through the REAL update loop --------------------------

## The sim-side cadence is T2's pin (test_space_sim test_ff_e2e...); here the
## cadence is witnessed through the GAME loop: a fresh landing persists
## nothing, then ~5 s of stepped updates write the spaceWorld blob WITHOUT
## any save_all (TS:609-613).
func test_cadence_persists_without_save() -> void:
	_wipe_saves()
	var g: Variant = _boot()
	g.switch_stage("space")
	g.step_for_testing(2, DT)
	ok(not g.context.flags.has("spaceWorld"),
			"a fresh landing persists nothing yet (restore-only on_enter)")
	var genome: Dictionary = GenomeLib.clone_genome(GenomeLib.default_genome())
	genome["size"] = 1.1
	g.current.sim.cargo.append({"genome": genome, "name": "Cadence"})
	g.step_for_testing(306, DT)  # 5.1 s — past the 5 s cadence (TS:610)
	ok(g.context.flags.has("spaceWorld"), "the cadence wrote the blob (no save_all)")
	var blob: Variant = JSON.parse_string(String(g.context.flags["spaceWorld"]))
	ok(blob is Dictionary and (blob["cargo"] as Array).size() == 1
			and String((blob["cargo"] as Array)[0]["name"]) == "Cadence",
			"the cadence blob carries the live cargo")
	_wipe_saves()
	_drop(g)


# ---- the toast-inset rule (TS space has NO set_toast_inset) ------------------------

## game.ts:213 zeroes the inset on EVERY switch; stages with bottom-left UI
## re-arm their own (civ 150, tribe 190). TS space arms none — the default 0
## holds on entry AND after leaving, and the outgoing civ's 150 stays zeroed.
func test_toast_inset_default_on_switch() -> void:
	var g: Variant = _boot()
	eq(float(g.stages["space"].hud_inst.toast_inset), 0.0, "fresh space hud inset 0")
	g.switch_stage("civ")
	eq(float(g.current.hud_inst.toast_inset), 150.0,
			"civ armed 150 (CivStage.ts:120 — the contrast)")
	g.switch_stage("space")
	eq(String(g.context.stage), "space", "space entered")
	eq(float(g.stages["civ"].hud_inst.toast_inset), 0.0,
			"the reset zeroed the outgoing civ hud")
	eq(float(g.current.hud_inst.toast_inset), 0.0,
			"space never re-arms (TS space has no set_toast_inset)")
	g.switch_stage("creature")
	eq(float(g.stages["space"].hud_inst.toast_inset), 0.0,
			"the outgoing space hud zeroed (stays 0 — it never armed)")
	_drop(g)


# ---- the objective dynamic-override (the finale bearing, REAL hud instance) --------

## T2 pinned the sim's per-update hook payload; this pins the HUD INSTANCE
## receiving it: 3 thriving colonies (the documented-cheat fixture) spawn the
## finale, the AWAKENS banner routes through the real hud, and the objective
## REWRITES per frame — two different bearings through one instance (the
## TS:566-568 write fires every update while the finale lives).
func test_objective_bearing_rewrites_through_hud() -> void:
	var g: Variant = _boot()
	g.switch_stage("space")
	g.step_for_testing(1, DT)
	var sim: Variant = g.current.sim
	for i in 3:
		sim.planets[i]["colony"] = {"pop": 20.0, "generations": 1.0}
	g.step_for_testing(1, DT)
	ok(sim.finale != null, "3 thriving → the finale spawned (TS:556)")
	var banner: Dictionary = g.current.hud_inst._cur_banner
	ok(banner != null, "the AWAKENS banner routed through the real hud")
	eq(String(banner["title"]), "THE CHAOS CORE AWAKENS", "banner title raw (TS:557)")
	eq(String(banner["sub"]), "something pulses beyond the outer light",
			"banner subtitle raw (TS:557; the hud payload key is 'sub')")
	# the ship sits at the constructor spawn (0,−900); the core at (0,−1900)
	eq(String(g.current.hud_inst.show_objective),
			"THE CHAOS CORE PULLS — fly 1000px up to the storm",
			"the bearing rewrote the objective (d 1000, up — TS:568)")
	# the rewrite is PER-FRAME: a moved ship yields a different line through
	# the SAME hud instance
	sim.sx = 0.0
	sim.sy = -2500.0  # d 600 below the core
	g.step_for_testing(1, DT)
	eq(String(g.current.hud_inst.show_objective),
			"THE CHAOS CORE PULLS — fly 600px down to the storm",
			"the bearing rewrote again (d 600, down — the per-frame override)")
	_drop(g)


# ---- the ending E2E: a won run stays won through CONTINUE (TS:256-264) -------------

## A WON run via the real KeyF ff (debug_seed_colonies → the colonies grow
## to thriving through the REAL ff key) → the core approach via the debug
## seam → endingDone persists (the win flush) → CONTINUE lands the saved
## space stage with the ending STAYS DONE, the finale orb restored (TS:263
## else-branch), no AWAKENS replay, and the calm post-ending objective.
func test_ending_won_run_stays_won_continue() -> void:
	_wipe_saves()
	# run 1: the honest win — seed the colonies, grow them with the REAL KeyF
	var g: Variant = _boot()
	g.switch_stage("space")
	g.step_for_testing(1, DT)
	var sim: Variant = g.current.sim
	sim.debug_seed_colonies()
	eq(float(sim.planets[0]["colony"]["pop"]), 1.0, "the debug seed (pop 1, TS:1281)")
	_hold_key(KEY_F, true)
	var steps := 0
	while sim.finale == null and steps < FF_POLL:
		g.step_for_testing(1, DT)
		steps += 1
	_hold_key(KEY_F, false)
	ok(sim.finale != null, "the real ff grew 3 thriving → the finale (%d steps)" % steps)
	if sim.finale == null:
		_wipe_saves()
		_drop(g)
		return
	var thriving := 0
	for p in sim.planets:
		if p["colony"] != null and float(p["colony"]["pop"]) >= 20.0:
			thriving += 1
	eq(thriving, 3, "all 3 seeded colonies thriving (the pop ≥ 20 gate)")
	# the core approach via the debug seam (d 50 < 60 → the win)
	sim.sx = 0.0
	sim.sy = -1850.0
	g.context.flags.erase("spaceWorld")  # isolate the WIN flush (TS:572)
	g.step_for_testing(1, DT)
	eq(bool(sim.endingDone), true, "d < 60 → endingDone (TS:569-570)")
	var win_blob: Variant = JSON.parse_string(String(g.context.flags["spaceWorld"]))
	ok(win_blob is Dictionary and bool(win_blob["endingDone"]),
			"the win flush persisted immediately (TS:572)")
	eq(bool(sim.endingDismissed), false, "not dismissed yet")
	# the flush is a REAL save: the slot rides the won state
	ok(g.save_all(), "the won save_all wrote the slot")
	_drop(g)
	# run 2: CONTINUE → the a-won-run-stays-won restore
	var g2: Variant = _boot()
	eq(String(g2.context.stage), "menu", "boot 2 sits on the menu")
	g2.current.continue_slot(0)
	eq(String(g2.transition["title"]), "WELCOME BACK", "continue card title")
	var steps2 := _ride_to(g2, "space")
	eq(String(g2.context.stage), "space", "CONTINUE landed the saved space stage (%d steps)" % steps2)
	var sim2: Variant = g2.current.sim
	eq(bool(sim2.endingDone), true, "a-won-run-stays-won (TS:256-258)")
	eq(bool(sim2.endingDismissed), false, "the un-dismissed ending restores un-dismissed")
	ok(sim2.finale != null and float(sim2.finale["y"]) == -1900.0,
			"the finale orb restored (TS:263 else-branch)")
	ok(g2.current.hud_inst._cur_banner == null, "no AWAKENS replay on the restore")
	# the thrival re-trigger stays blocked by the restored latch (no new
	# finale, no banner, across 2 s of ticking)
	var fin_t: float = float(sim2.finale["t"])
	g2.step_for_testing(120, DT)
	eq(bool(sim2.endingDone), true, "the latch holds after 2 s")
	ok(sim2.finale != null and float(sim2.finale["t"]) > fin_t,
			"the SAME finale lives on (t ticks — no re-spawn, endingDone gates TS:554)")
	ok(g2.current.hud_inst._cur_banner == null, "still no AWAKENS replay")
	# the restored finale keeps the calm post-ending objective (TS:566-567)
	eq(String(g2.current.hud_inst.show_objective),
			"the core sleeps — the sandbox is yours",
			"the calm line rides the restored finale (endingDone)")
	_wipe_saves()
	_drop(g2)


# ---- the ending E2E: the DISMISSED ending sleeps (TS:262-263) ----------------------

## A won run dismissed (any key hands the sandbox back, TS:578) → the blob
## carries endingDismissed → CONTINUE restores the SLEEP: finale null (no
## stale orb, no AWAKENS replay), the restore timers at 99, and the ending
## stays done (the win run is still won).
func test_ending_dismissed_sleeps_continue() -> void:
	_wipe_saves()
	# run 1: the win via the documented-cheat path (the brief's second option)
	var g: Variant = _boot()
	g.switch_stage("space")
	g.step_for_testing(1, DT)
	var sim: Variant = g.current.sim
	for i in 3:
		sim.planets[i]["colony"] = {"pop": 20.0, "generations": 1.0}
	g.step_for_testing(1, DT)
	ok(sim.finale != null, "the cheat path spawned the finale")
	sim.sx = 0.0
	sim.sy = -1850.0
	g.step_for_testing(1, DT)
	eq(bool(sim.endingDone), true, "the win fired")
	# the dismiss: any key hands the sandbox back (TS:578-581)
	_tap_key(g, KEY_W)
	g.step_for_testing(1, DT)
	eq(bool(sim.endingDismissed), true, "a key press dismissed the ending")
	ok(float(sim.dismissT) > 0.0, "dismissT = endingT at the dismiss frame (TS:580)")
	ok(g.save_all(), "the dismissed save_all wrote the slot")
	_drop(g)
	# run 2: CONTINUE → the sleep
	var g2: Variant = _boot()
	g2.current.continue_slot(0)
	var steps := _ride_to(g2, "space")
	eq(String(g2.context.stage), "space", "CONTINUE landed the saved space stage (%d steps)" % steps)
	var sim2: Variant = g2.current.sim
	eq(bool(sim2.endingDone), true, "the run is STILL won (TS:257-258)")
	eq(bool(sim2.endingDismissed), true, "endingDismissed restored (TS:259)")
	# endingT restored to 99, then it TICKS (endingDone += dt) — the fade math
	# reads the endingT − dismissT delta, so the restored base is the pin
	ok(float(sim2.endingT) >= 99.0 and float(sim2.endingT) < 100.0,
			"endingT restored to 99 (then ticks — TS:260; got %s)" % str(sim2.endingT))
	approx(float(sim2.dismissT), 99.0, "dismissT restored to 99 (TS:261)")
	eq(sim2.finale, null, "the dismissed ending sleeps — no stale orb (TS:262-263)")
	ok(g2.current.hud_inst._cur_banner == null, "no AWAKENS replay")
	# the sleep HOLDS: 3 thriving colonies restored, but the gate stays blocked
	var thriving := 0
	for p in sim2.planets:
		if p["colony"] != null and float(p["colony"]["pop"]) >= 20.0:
			thriving += 1
	eq(thriving, 3, "the thriving colonies restored (the whitelist rides)")
	g2.step_for_testing(120, DT)
	eq(sim2.finale, null, "still asleep after 2 s (no re-trigger, TS:554)")
	ok(g2.current.hud_inst._cur_banner == null, "still no AWAKENS replay")
	g2.current.render()
	ok(true, "the sleeping sandbox renders clean")
	_wipe_saves()
	_drop(g2)


# ---- i18n 1:1 (the T8 verification standard) ---------------------------------------

## Every t() site of the space surface maps in vi.csv (the TS VI object 1:1 —
## grepped src/core/i18n.ts 2026-10-04; the SpaceStage.ts line cited per
## group). The RAW composed/unwrapped sites stay raw — normative absences
## pinned vi_has == false with EN fallback parity. Two keys are VI MEMBERS
## whose space call site is raw (the banner titles draw through the hud's
## tr_key — hud.ts:325/hud.gd:363 — the M5 card-key precedent): pinned
## vi_has == true.
func test_space_i18n_mapping_1to1() -> void:
	_wipe_cfg()
	var i: Variant = I18nScript.new(SCRATCH_CFG)
	i.set_lang("vi")
	# the t() sites — sim toasts + the objective (SpaceStage.ts :461/:492/:567/
	# :591/:651/:655/:659/:664/:678/:697/:699/:713/:717/:739/:760/:763/:765/
	# :789/:817/:824/:827/:833/:865/:868/:876/:1236/:1241/:1250/:1256/:1267)
	var t_sites := [
		"SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve",
		"The siege lifts — pirates give up",
		"Pirate destroyed! +30 DNA",
		"the core sleeps — the sandbox is yours",
		"Ship destroyed! Lost",
		"Fly closer to a planet to abduct",
		"Cargo full — SEED a world, SPLICE genes (G), or JETTISON from the planet panel",
		"No life to abduct here",
		"Nothing left to abduct here",
		"Abducted:",
		"that species is now gone from this world",
		"Fly closer to seed",
		"Seeding costs 20 DNA",
		"Gene splice costs 15 DNA",
		"UNEXPECTED EXPRESSION",
		"Recessive Echo",
		"Sleeper Gene",
		"Transposon",
		"Defective splice:",
		"Glass Bones",
		"Frenzy",
		"Famine",
		"Gene splice:",
		"Borrowed flesh:",
		"The nebula washes only dead rock.",
		"The nebula passes over",
		"nothing takes hold.",
		"The nebula seeds",
		"new species on",
		"The pirates pull back — an uneasy quiet falls.",
		"Tribute paid. The Void Empire is satisfied… for now.",
		"Not enough DNA — the raid is coming!",
		"Solar flare scorches your hull!",
		"Not enough DNA",
		"Hull fully repaired",
		"Survey instruments recharging",
		"survey",
	]
	# the draw-side t() sites (the stage render, SpaceStage.ts :1038/:1050/
	# :1104/:1111/:1120/:1121/:1204/:1205 + the panel buttons :1221-1227)
	for draw_site in ["⏩ EVOLUTION ACCELERATING", "HULL", "THE CHAOS CORE ACCEPTS YOU",
			"The universe hums in harmony — you gardened the stars.",
			"The universe fears your name — chaos was your harvest.",
			"The universe cannot decide what you are. It keeps watching.",
			"the sandbox remains yours — keep flying, keep evolving",
			"(ESC to pause · M mute · F fast-forward · R abduct)",
			"lifeless rock", "species", "flora",
			"🛸 ABDUCT LIFE (R)", "🌱 SEED COLONY", "📋 RE-SURVEY (+3)", "📡 SCAN",
			"🧬 GENE LAB: merge 2 cargo (G)", "🗑 JETTISON 1 CARGO"]:
		t_sites.append(draw_site)
	for key in t_sites:
		ok(i.vi_has(String(key)), "t() site maps: %s" % key)
	# spot-check the values against the TS VI object (value drift would pass a
	# vi_has-only pin)
	eq(i.tr_key("THE CHAOS CORE ACCEPTS YOU"), "CHAOS CORE CHẤP NHẬN BẠN",
			"value parity (TS VI :167)")
	eq(i.tr_key("Pirate destroyed! +30 DNA"), "Đã diệt cướp! +30 DNA",
			"value parity (TS VI :361)")
	eq(i.tr_key("The siege lifts — pirates give up"), "Vây hãm tan biến — cướp biển từ bỏ",
			"value parity (TS VI :603)")
	eq(i.tr_key("🛸 ABDUCT LIFE (R)"), "🛸 BẮT SINH VẬT (R)", "value parity (TS VI :172)")
	eq(i.tr_key("HULL"), "VỎ", "value parity (TS VI :396)")
	eq(i.tr_key("the core sleeps — the sandbox is yours"), "lõi đã ngủ — khu chơi tự do là của bạn",
			"value parity (TS VI :166-167)")
	eq(i.tr_key("the sandbox remains yours — keep flying, keep evolving"),
			"cát vẫn thuộc về bạn — cứ bay, cứ tiến hóa", "value parity (TS VI :394-395)")
	eq(i.tr_key("(ESC to pause · M mute · F fast-forward · R abduct)"),
			"(ESC tạm dừng · M tắt tiếng · F tua nhanh · R bắt sinh vật)",
			"value parity (TS VI :149-150)")
	# the RAW emit sites that are VI MEMBERS — the banner keys translate at the
	# hud draw (TS hud.ts:325 t(b.title); the emit stays raw, SpaceStage.ts
	# :854/:1057) — the M5 transition-card precedent. 'CARGO' rides the TS VI
	# object (:201) although its draw site (:1062) emits it raw.
	for member in ["THE VOID EMPIRE DEMANDS TRIBUTE", "CARGO"]:
		ok(i.vi_has(String(member)), "raw-emit VI member maps (draw-time tr): %s" % member)
	# QC r6 sweep: the AWAKENS banner title+sub LEFT the raw list — fixed
	# keys the hud's draw-time tr resolves (TS:557 renders raw; native VI
	# completion, the r4 armada precedent). The composed strings below stay
	# raw: the native keys are '%s'/'%d' TEMPLATES, so the composed payloads
	# never match a key.
	for mapped in ["THE CHAOS CORE AWAKENS", "something pulses beyond the outer light"]:
		ok(i.vi_has(String(mapped)), "r6-completed banner key maps: %s" % mapped)
	# the RAW composed/unwrapped sites — normative absences, 1:1 with TS
	for raw in ["THE CHAOS CORE PULLS — fly 1000px up to the storm",  # TS:568 composed (the r6 key is the %dpx/%s template)
			"pay 30 DNA (press V) or face the raid",  # TS:855 composed (the 'pay'/'or face the raid' fragments ride VI; the composed subtitle never resolves)
			"Glip went extinct on Lush-1",  # TS:318 composed
			"Rl evolves on Ocean-2",  # TS:321 composed
			"Zed released back to the void",  # TS:426 composed
			"Lush-3 SEEDED",  # TS:1008 banner title composed
			"★ thriving",  # TS:956 — the colony label, raw
			"🏳 3 colonies · ★ 2/3 thriving",  # TS:1029 — the chip template, raw
			"Scan complete: 3 species on Lush-1",  # TS:1267 — the composed key never resolves (the 'Scan complete:' fragment rides VI)
			"Scan complete: Barren-4 is lifeless — bring life!",  # TS:1269 raw composed
			"lush · colony 12 · gen 3"]:  # TS:1203 — the panel kind line, raw
		ok(not i.vi_has(String(raw)), "raw site absent from VI like TS: %s" % raw)
		eq(i.tr_key(String(raw)), String(raw), "EN fallback parity: %s" % raw)
	i.set_lang("en")
	TranslationServer.set_locale("en")
	_wipe_cfg()
