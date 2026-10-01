# Task 9 game-flow tests — the FULL orchestrator behavior headless (-s, no
# rendering): transition phases timed, resetStagesForNewRun/resetNarration,
# start_new_game difficulty contract (M1 values + initial save), autosave
# (60s, never menu/transition), chaos settle + karma drift recurrences,
# pumpWorldStory (world reveal toasts → hud card toasts, codex flag, combos,
# epoch_apex turn naming, temperament assignment, beat offers herd/gaia
# redemption/gaia wanderer + runBeat cases, dnaRate 60s window), KeyM/Escape
# routing, hud-first click routing, menu slot metas + continue.
#
# The real MenuStage is booted headless (its draw pass never runs without
# Game._do_render, so click routing stays inert — the REAL click flow is
# tests/scenes/test_menu.tscn under xvfb); the cell stage is a scripted fake
# (the bot arc already covers the real one) exposing exactly the surface
# game.gd reads: update/persist_state/gaia_wanderer/has_active_chaos.
#
# Input feeds go through input.handle_event directly (the same entry
# _unhandled_input forwards to) — headless drops parse_input_event delivery
# by design (see test_bot_arc.gd's header); the pipeline itself is
# proven under xvfb there and in the editor-click test.
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const StageScript := preload("res://src/game/stage.gd")
const GameInputScript := preload("res://src/core/input.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const TraitsScript := preload("res://src/evo/world_traits.gd")

const DT := 1.0 / 60.0
# World-genome pins (scanned 2026-09-30, derive_world_genome):
#   seed 1 → hungry_bloom (stageTime cell 90) + toxin_sea (chaos > 0.45) →
#            the rot_circle combo pair
#   seed 4 → old_blood + the epoch_apex turn + a derived temperament
const SEED_COMBO := 1
const SEED_APEX := 4
const SCRATCH_CFG := "user://test_flow_settings.cfg"

# out 0.55 → card 2.2 → in 0.6, in fixed steps (33 / 132 / 36)
const OUT_STEPS := 33
const CARD_STEPS := 132
const IN_STEPS := 36


## Scripted cell stage: the exact surface game.gd's pump + save paths read.
class FakeCellStage extends "res://src/game/stage.gd":
	var updates := 0.0
	var entered := 0
	var exited := 0
	var persisted := 0
	var wanderer_spawns := 0
	var chaos_active := false
	var saw_click := false

	func _init(g: Variant) -> void:
		super(g, "cell")

	func update(dt: float) -> void:
		updates += dt
		if game.input.was_clicked():
			saw_click = true

	func on_enter(_from: Variant = null) -> void:
		entered += 1

	func on_exit() -> void:
		exited += 1

	func persist_state() -> void:
		persisted += 1

	func gaia_wanderer() -> void:
		wanderer_spawns += 1

	func has_active_chaos() -> bool:
		return chaos_active


## Bare stage with no beat surface (the offer gate must skip it — TS typeof
## gaiaWanderer === 'function' reads undefined).
class BareStage extends "res://src/game/stage.gd":
	func _init(g: Variant, id_v: String) -> void:
		super(g, id_v)


# ---- hud recorder (method Callables — defaults apply on short calls) ----------

var _toasts: Array = []
var _pointer_calls: Array = []
var _pointer_consume := false


func _rec_update(_dt: float) -> void:
	pass


func _rec_dismiss() -> void:
	pass


func _rec_toast(text: String, kind: String, icon: String, ttl := 4.0, card: Variant = null) -> void:
	_toasts.append({"text": text, "kind": kind, "icon": icon, "ttl": ttl, "card": card})


func _rec_banner(_m: Variant) -> void:
	pass


func _rec_float(_x: float, _y: float, _t: String, _c: Variant, _s: float) -> void:
	pass


func _rec_pointer(x: float, y: float) -> bool:
	_pointer_calls.append([x, y])
	return _pointer_consume


func _install_recorder_hud(g: Variant) -> void:
	_toasts = []
	_pointer_calls = []
	_pointer_consume = false
	g.hud = {
		"update": _rec_update,
		"dismiss_banner": _rec_dismiss,
		"toast": _rec_toast,
		"banner": _rec_banner,
		"float_world": _rec_float,
		"pointer_down": _rec_pointer,
		"set_toast_inset": func(_px: float) -> void: pass,  # TS:213 reset routes here
	}


func _wipe_saves() -> void:
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for i in 3:
			if dir.file_exists("slot%d.json" % i):
				dir.remove("slot%d.json" % i)


func _wipe_cfg() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_flow_settings.cfg")
		dir.remove("test_flow_settings.cfg.tmp")


## Seeded boot → menu, with the T6 trap pattern (processing killed AFTER tree
## entry; the loop's is_active_cb kill-switch) so step_for_testing is the ONLY
## clock. with_factory injects the composition-root factory like main.gd.
func _flow_game(seed_v: int, with_factory := false) -> Variant:
	var ctx: Variant = ContextScript.new(seed_v)
	var g: Variant = GameScript.new(ctx)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(g)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	# pin the locale/mute defaults deterministically (the shared user cfg may
	# carry anything, and detect_lang() reads the OS locale — a VI machine
	# would translate the continue-sub assert) and keep mute/lang writes out
	# of it — game.muted was read at construction, before the redirect, so
	# re-sync it
	g.i18n.settings_path = SCRATCH_CFG
	_wipe_cfg()
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.muted = g.i18n.get_muted()
	if with_factory:
		# TS main.ts shape: gameplay stages only — the menu persists in the map
		g.stage_factory = func() -> Array:
			return [FakeCellStage.new(g)]
	g.register(MenuStageScript.new(g))
	g.register(FakeCellStage.new(g))
	g.register(BareStage.new(g, "creature"))
	g.start()
	return g


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the recorder-Callable cycle into this test instance
		g.free()


## Walk the no-title transition (out 0.55 → in 0.6) onto the target stage.
func _walk_plain(g: Variant) -> void:
	g.step_for_testing(OUT_STEPS + IN_STEPS, DT)


## Walk the FULL title-card transition (out → card → in).
func _walk_card(g: Variant) -> void:
	g.step_for_testing(OUT_STEPS + CARD_STEPS + IN_STEPS, DT)


func _toast_titles() -> Array:
	var out := []
	for t in _toasts:
		if t["card"] != null:
			out.append(String(t["card"]["title"]))
	return out


# ---- boot ---------------------------------------------------------------------


func test_seeded_boot_lands_on_menu() -> void:
	var g: Variant = _flow_game(777)
	eq(g.context.stage, "menu", "boot stage")
	eq(g.current.id, "menu", "current stage is the real menu")
	eq(g.current.view, "title", "menu opens on the title view")
	eq(g.context.seed, 777, "seeded context")
	_drop(g)


# ---- start_new_game + transition timing ---------------------------------------


func test_start_new_game_chaos_contract_and_card_timing() -> void:
	_wipe_saves()
	var g: Variant = _flow_game(0xC0FFEE, true)
	var old_cell: Variant = g.stages["cell"]
	var old_menu: Variant = g.current
	g.current.start_new_game(0, "chaos", 0xC0FFEE)
	# M1 difficulty contract
	eq(g.context.difficulty, "chaos", "difficulty")
	approx(g.context.chaos, 0.45, "starting chaos (chaos)")
	approx(g.context.chaos_gap_mult(), 0.7, "gap multiplier (chaos)")
	eq(g.context.flags, {"difficulty": "chaos"}, "flags.difficulty")
	eq(g.context.dna, 100, "tutorial-affordable starting DNA")
	approx(g.context.karma, 0.0, "karma reset")
	approx(g.context.playtime, 0.0, "playtime reset")
	eq(g.context.slot, 0, "slot")
	eq(g.context.player_name, "Squish", "player name")
	eq(g.context.stage, "cell", "context stage pre-transition")
	eq(g.context.bestiary.size(), 0, "bestiary wiped")
	eq(g.context.eco, null, "eco wiped")
	# initial save written
	ok(FileAccess.file_exists("user://saves/slot0.json"), "initial save written")
	# world re-derived from the pinned seed
	eq(g.context.world["seed"], 0xC0FFEE, "world seed")
	# stage factory rebuild
	ok(old_cell.is_queued_for_deletion(), "old non-current stage freed on rebuild")
	ok(g.stages["cell"] != old_cell, "fresh cell instance in the registry")
	eq(g.current, old_menu, "the live menu stays current during the out-fade")
	# transition shape
	eq(String(g.transition["phase"]), "out", "transition opens in out")
	eq(g.transition["next"], "cell", "transition target")
	eq(String(g.transition["title"]), "CELL STAGE", "card title key")
	# phase timing: out 0.55
	g.step_for_testing(OUT_STEPS - 1, DT)
	eq(String(g.transition["phase"]), "out", "still out at t=0.5333")
	for i in 3:  # the exact 33×dt float sum can sit an ulp under 0.55
		g.step_for_testing(1, DT)
		if String(g.transition["phase"]) != "out":
			break
	eq(String(g.transition["phase"]), "card", "card at t=0.55")
	eq(g.context.stage, "cell", "stage switched at the out→card boundary")
	eq(g.current.id, "cell", "current is the fresh cell")
	eq(int(g.current.entered), 1, "fresh cell entered once")
	# card 2.2 — the stage sim is FROZEN during the card
	var frozen_at: float = g.current.updates
	g.step_for_testing(CARD_STEPS - 1, DT)
	eq(String(g.transition["phase"]), "card", "still card at t=2.1833")
	eq(g.current.updates, frozen_at, "stage sim frozen during the card")
	for i in 3:
		g.step_for_testing(1, DT)
		if String(g.transition["phase"]) != "card":
			break
	eq(String(g.transition["phase"]), "in", "in at card end")
	# in 0.6
	g.step_for_testing(IN_STEPS - 1, DT)
	eq(String(g.transition["phase"]), "in", "still in at t=0.5833")
	for i in 3:
		g.step_for_testing(1, DT)
		if g.transition == null:
			break
	eq(g.transition, null, "transition complete")
	# the pump runs once the card clears — playtime advanced by the sim steps
	ok(g.context.playtime > 0.0, "playtime advanced")
	_drop(g)


func test_start_new_game_normal_and_peaceful_values() -> void:
	_wipe_saves()
	var g: Variant = _flow_game(7)
	g.current.start_new_game(1, "normal", 7)
	approx(g.context.chaos, 0.15, "starting chaos (normal)")
	approx(g.context.chaos_gap_mult(), 1.0, "gap multiplier (normal)")
	eq(g.context.slot, 1, "slot 1")
	ok(FileAccess.file_exists("user://saves/slot1.json"), "initial save in slot 1")
	g.current.start_new_game(2, "peaceful", 7)
	approx(g.context.chaos, 0.08, "starting chaos (peaceful)")
	approx(g.context.chaos_gap_mult(), 1.5, "gap multiplier (peaceful)")
	_drop(g)


# ---- pendingGoTo queue semantics (T1 port, exercised through the real flow) ---


func test_transition_queue_and_quit_cancel() -> void:
	_wipe_saves()
	var g: Variant = _flow_game(5)
	g.current.start_new_game(0, "normal", 5)  # T1: cell + 'CELL STAGE' card
	g.step_for_testing(10, DT)  # mid-out
	# same-destination re-request during the fade is DROPPED (double cards)
	g.go_to("cell", {"title": "CELL STAGE", "sub": ""})
	eq(g.pending_go_to, null, "same-destination re-request dropped")
	# a different destination QUEUES (a victory firing mid-transition must not
	# be silently lost)
	g.go_to("creature", {"title": "THE LONG WALK", "sub": ""})
	ok(g.pending_go_to != null and String(g.pending_go_to["id"]) == "creature",
			"different destination queues")
	_walk_card(g)  # T1 finishes → the queued go_to re-fires
	eq(String(g.transition["phase"]), "out", "queued go_to re-fires")
	eq(g.transition["next"], "creature", "queued target")
	_walk_card(g)
	eq(g.current.id, "creature", "reached the queued stage")
	# quit-to-title cancels a STALE non-surviving queue (a civ victory
	# auto-space must not hijack the title)
	g.go_to("menu")  # T3 quit, no card
	g.step_for_testing(OUT_STEPS + 10, DT)  # menu live mid-fade (in phase)
	g.go_to("creature")  # stale queue, non-surviving
	_walk_plain(g)  # T3's in-end drops it; the rest idles
	eq(g.current.id, "menu", "quit finished on the title")
	eq(g.transition, null, "stale non-surviving queue canceled at the in-end")
	# ...but a CONTINUE clicked during the quit fade is LIVE (survivesQuit)
	g.go_to("cell")  # T4, leave the title
	_walk_plain(g)
	ok(g.context.stage == "cell", "live on cell again")
	g.go_to("menu")  # T5 quit
	g.step_for_testing(OUT_STEPS + 10, DT)  # menu live mid-fade
	g.current.continue_slot(0)  # slot0 save exists from start_new_game
	_walk_plain(g)  # the quit's in-end fires the survivor
	eq(g.context.stage, "cell", "surviving continue fired after the quit")
	eq(String(g.transition["title"]), "WELCOME BACK", "with the continue card")
	_drop(g)


# ---- reset narration -----------------------------------------------------------


func test_reset_narration_via_new_life() -> void:
	_wipe_saves()
	var g: Variant = _flow_game(11, true)
	# run-1 narration latches
	g.context_event.emit("playerDeath", "cell")
	g.context.dna_gained.emit(10, "probe", null, null)
	g.storyteller.mood = "twist"
	g.storyteller.temperament = "wildcard"
	g.stage_time = 99.0
	g.storyteller.offer_beat("herd_remembers")
	g.current.start_new_game(0, "normal", 12)
	eq(int(g.deaths_in_stage), 0, "deathsInStage wiped")
	approx(g.stage_time, 0.0, "stageTime wiped")
	approx(g.gaia_death_at, -1.0, "gaia ledger wiped")
	eq(int(g.dna_window.size()), 0, "dna window wiped")
	approx(g.dying_until, 0.0, "death blackout wiped")
	eq(String(g.storyteller.mood), "test", "storyteller mood reset")
	eq(String(g.storyteller.temperament), "none", "temperament reset")
	eq(int(g.storyteller._beats.size()), 0, "beat queue wiped")
	_drop(g)


# ---- autosave -------------------------------------------------------------------


func test_autosave_fires_and_respects_gates() -> void:
	_wipe_saves()
	var g: Variant = _flow_game(21)
	g.current.start_new_game(0, "normal", 21)
	_walk_card(g)  # ~3.35s of autosave_t accrued through the transition
	eq(int(g.current.persisted), 0, "no save during the transition")
	ok(FileAccess.file_exists("user://saves/slot0.json"), "initial save present")
	_wipe_saves()
	# past the edge on a LIVE stage: flush + write (the fake cell is current)
	g.autosave_t = 59.99
	g.step_for_testing(1, DT)
	eq(int(g.current.persisted), 1, "persist_state flushed before the write")
	ok(FileAccess.file_exists("user://saves/slot0.json"), "autosave wrote the slot")
	# force the timer to the edge DURING a transition: gated, no write
	_wipe_saves()
	g.go_to("creature")
	g.autosave_t = 59.99
	g.step_for_testing(1, DT)
	ok(not FileAccess.file_exists("user://saves/slot0.json"),
			"no autosave mid-transition (timer reset, write skipped)")
	_walk_plain(g)
	eq(g.current.id, "creature", "arrived")
	# on the menu: never (it would downgrade the slot)
	g.go_to("menu")
	_walk_plain(g)
	eq(g.context.stage, "menu", "back on the menu")
	_wipe_saves()
	g.autosave_t = 59.99
	g.step_for_testing(1, DT)
	ok(not FileAccess.file_exists("user://saves/slot0.json"), "no autosave on the title")
	_drop(g)


# ---- chaos settle + karma drift (exact recurrences) ------------------------------


func test_chaos_settle_recurrences() -> void:
	var g: Variant = _flow_game(31)
	g.go_to("cell")
	_walk_plain(g)
	for diff in [["chaos", 0.25], ["normal", 0.12], ["peaceful", 0.05]]:
		g.context.difficulty = diff[0]
		g.context.chaos = 0.8
		var expected := 0.8
		for i in 600:
			expected += (float(diff[1]) - expected) * minf(1.0, DT * 0.03)
			g.step_for_testing(1, DT)
		approx(g.context.chaos, expected,
				"chaos settles toward %s resting level" % diff[0])
	_drop(g)


func test_karma_drift_lifts_negative_only() -> void:
	var g: Variant = _flow_game(32)
	g.go_to("cell")
	_walk_plain(g)
	g.context.karma = -0.5
	var expected := -0.5
	for i in 600:
		expected += (0.0 - expected) * minf(1.0, DT * 0.003)
		g.step_for_testing(1, DT)
	approx(g.context.karma, expected, "negative karma drifts up")
	# a HARMONIOUS score never erodes
	g.context.karma = 0.5
	g.step_for_testing(600, DT)
	approx(g.context.karma, 0.5, "positive karma untouched")
	_drop(g)


# ---- pumpWorldStory: reveals / combos / turns ------------------------------------


func test_world_reveal_lands_as_world_toast_and_codex() -> void:
	var g: Variant = _flow_game(SEED_COMBO)
	_install_recorder_hud(g)
	g.go_to("cell")
	_walk_plain(g)
	g.context.chaos = 0.5  # toxin_sea reveals above 0.45
	g.step_for_testing(1, DT)
	eq(int(_toasts.size()), 1, "one reveal toast")
	var t: Dictionary = _toasts[0]
	eq(String(t["kind"]), "world", "kind world")
	approx(float(t["ttl"]), 6.0, "ttl 6")
	eq(String(t["icon"]), "☣️", "trait sigil")
	eq(String(t["card"]["title"]), "Toxin Sea", "trait name")
	var def: Variant = null
	for d in TraitsScript.TRAIT_DEFS:
		if d["id"] == "toxin_sea":
			def = d
	eq(String(t["card"]["body"]), String(def["body"]), "trait body")
	eq(String(t["text"]), "%s — %s" % [String(def["name"]), String(def["body"])],
			"toast text composes name — body")
	eq(String(g.context.flags.get("codex_world", "")), "toxin_sea", "codex flag append")
	# the reveal ledger pins — no duplicate announce
	g.step_for_testing(30, DT)
	eq(int(_toasts.size()), 1, "no duplicate reveal")
	eq(bool(g.context.world["revealed"]["toxin_sea"]), true, "revealed flag")
	_drop(g)


func test_combo_rot_circle_announces_but_stays_out_of_codex() -> void:
	var g: Variant = _flow_game(SEED_COMBO)
	_install_recorder_hud(g)
	g.go_to("cell")
	_walk_plain(g)
	# hungry_bloom reveals at 90s of cell time — walk the pump there
	g.step_for_testing(5401, DT)
	var titles := _toast_titles()
	ok(titles.has("Hungry Bloom"), "timer-driven trait revealed (%s)" % str(titles))
	# toxin_sea via chaos, then one extinction fires the combo
	g.context.chaos = 0.5
	g.step_for_testing(1, DT)
	ok(_toast_titles().has("Toxin Sea"), "chaos-driven trait revealed")
	g.context.bump_extinction()
	g.step_for_testing(1, DT)
	ok(_toast_titles().has("Rot Circle"), "combo announced")
	eq(bool(g.context.world["comboFired"]["rot_circle"]), true, "combo fired record")
	var codex: String = String(g.context.flags.get("codex_world", ""))
	ok(codex.contains("hungry_bloom") and codex.contains("toxin_sea"),
			"codex carries the traits (%s)" % codex)
	ok(not codex.contains("rot_circle"), "combos render from their own fired records")
	_drop(g)


func test_epoch_apex_turn_names_the_apex_species() -> void:
	var g: Variant = _flow_game(SEED_APEX)
	_install_recorder_hud(g)
	g.go_to("cell")
	_walk_plain(g)
	# the seed's derived temperament rides the pump every frame
	ok(String(g.context.world["temperament"]) != "none", "seed has a temperament")
	eq(String(g.storyteller.temperament), String(g.context.world["temperament"]),
			"storyteller temperament assigned from the world genome")
	# script the reveal state (the timer path is proven above) + a staged eco
	g.context.world["revealed"]["old_blood"] = true
	var eco: Variant = EcoScript.new(g.context.rng.branch())
	var small: Dictionary = eco.add_species(GenomeScript.default_genome(), 4.0, {})
	small["genome"]["size"] = 1.0
	var big: Dictionary = eco.add_species(GenomeScript.default_genome(), 10.0, {})
	big["genome"]["size"] = 2.0
	g.context.eco = eco
	g.context.bump_extinction()
	g.step_for_testing(1, DT)
	var titles := _toast_titles()
	ok(titles.has("An Epoch Begins"), "turn announced (%s)" % str(titles))
	ok(titles.has("Trophic Release"), "the replacement trait announced too")
	# the apex body names the strongest survivor by pop × size (big: 20 > small: 4)
	var turn_toast: Dictionary = {}
	for t in _toasts:
		if t["card"] != null and String(t["card"]["title"]) == "An Epoch Begins":
			turn_toast = t
	ok(String(turn_toast["card"]["body"]).contains("the age of"), "apex body names the age")
	ok(String(turn_toast["card"]["body"]).contains(String(big["name"])),
			"body names the biggest species (%s)" % String(turn_toast["card"]["body"]))
	ok(not String(turn_toast["card"]["body"]).contains(String(small["name"])),
			"the smaller line is not named")
	eq(bool(g.context.world["firedTurns"]["epoch_apex"]), true, "turn fired record")
	var ids := []
	for tr in g.context.world["traits"]:
		ids.append(tr["id"])
	ok(ids.has("trophic_release") and not ids.has("old_blood"),
			"the turn replaced the trait (%s)" % str(ids))
	_drop(g)


# ---- pumpWorldStory: beats --------------------------------------------------------


func _script_kin(g: Variant, pop: float, peak := -1.0) -> Dictionary:
	var eco: Variant = EcoScript.new(g.context.rng.branch())
	var s: Dictionary = eco.add_species(GenomeScript.default_genome(), pop, {"kin": true})
	if peak >= 0.0:
		s["peak"] = peak
	g.context.eco = eco
	return s


func test_beat_herd_remembers_pays_dna_and_feeds_dna_rate() -> void:
	var g: Variant = _flow_game(41)
	_install_recorder_hud(g)
	g.go_to("cell")
	_walk_plain(g)
	g.context.dna = 100
	_script_kin(g, 16.0)
	g.step_for_testing(1, DT)
	eq(int(g.context.dna), 125, "homage DNA +25")
	var titles := _toast_titles()
	ok(titles.has("The herd remembers"), "herd beat toast (%s)" % str(titles))
	# the dna_gained signal fed the 60s window
	approx(g.dna_rate_per_min(), 25.0, "dnaRate window sum")
	# once per run: the ledger dedupes
	g.step_for_testing(120, DT)
	eq(int(g.context.dna), 125, "no repeat payment")
	# the window slides: after 70s the entry is trimmed
	g.step_for_testing(4200 - 120, DT)
	approx(g.dna_rate_per_min(), 0.0, "60s window trimmed")
	_drop(g)


func test_beat_offer_blackout_across_death_fade() -> void:
	var g: Variant = _flow_game(42)
	_install_recorder_hud(g)
	g.go_to("cell")
	_walk_plain(g)
	g.context.dna = 100
	_script_kin(g, 16.0)
	g.context_event.emit("playerDeath", "cell")
	var p: float = g.context.playtime
	approx(g.dying_until, p + 2.0, "blackout set to playtime + 2")
	# inside the window the thriving kin does NOT offer
	g.step_for_testing(60, DT)
	eq(int(g.context.dna), 100, "no beat payment while blacked out")
	# past the window the offer lands
	g.step_for_testing(61, DT)
	eq(int(g.context.dna), 125, "beat offered after the fade")
	_drop(g)


func test_beat_gaia_redemption_narrates_once_after_first_death() -> void:
	var g: Variant = _flow_game(43)
	_install_recorder_hud(g)
	g.go_to("cell")
	_walk_plain(g)
	g.context_event.emit("playerDeath", "cell")
	var p: float = g.context.playtime
	eq(int(g.deaths_in_stage), 1, "deathsInStage bumped")
	approx(g.gaia_death_at, p, "gaia ledger opened at the first death")
	# ~3.5s later the beat narrates (and only once)
	g.step_for_testing(int((3.5 - (g.context.playtime - p)) * 60.0) + 2, DT)
	var count := 0
	for t in _toasts:
		if t["card"] != null and String(t["card"]["title"]) == "Gaia's Redemption":
			count += 1
	eq(count, 1, "redemption narrated exactly once")
	approx(g.gaia_death_at, -1.0, "ledger closed — no re-offer")
	g.step_for_testing(300, DT)
	count = 0
	for t in _toasts:
		if t["card"] != null and String(t["card"]["title"]) == "Gaia's Redemption":
			count += 1
	eq(count, 1, "still exactly once")
	_drop(g)


func test_beat_gaia_wanderer_gates_and_spawns_once() -> void:
	var g: Variant = _flow_game(44)
	_install_recorder_hud(g)
	g.go_to("cell")
	_walk_plain(g)
	# kin bloodline crashed below 10% of its peak — but chaos is ACTIVE first
	_script_kin(g, 1.5, 20.0)
	g.current.chaos_active = true
	g.step_for_testing(60, DT)
	eq(int(g.current.wanderer_spawns), 0, "no wanderer while a chaos event runs")
	# the gate opens → the stage's gaia_wanderer spawns exactly once
	g.current.chaos_active = false
	g.step_for_testing(1, DT)
	eq(int(g.current.wanderer_spawns), 1, "wanderer spawned via the beat case")
	g.step_for_testing(120, DT)
	eq(int(g.current.wanderer_spawns), 1, "once per run")
	_drop(g)


func test_beat_offer_skipped_without_stage_surface() -> void:
	var g: Variant = _flow_game(45)
	g.stages["cell"] = BareStage.new(g, "cell")  # no gaia_wanderer method
	g.go_to("cell")
	_walk_plain(g)
	_script_kin(g, 1.5, 20.0)
	g.step_for_testing(60, DT)
	eq(int(g.storyteller._beats.size()), 0,
			"no offer when the stage does not implement the spawn")
	_drop(g)


# ---- KeyM / Escape routing ---------------------------------------------------------


func _feed_key(g: Variant, code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	g.input.handle_event(ev)


func _feed_click(g: Variant, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	g.input.handle_event(ev)


func test_keym_mute_toggles_and_persists() -> void:
	var g: Variant = _flow_game(51)
	eq(bool(g.muted), false, "unmuted at boot")
	_feed_key(g, KEY_M)
	g.step_for_testing(1, DT)
	eq(bool(g.muted), true, "KeyM mutes")
	eq(bool(g.i18n.get_muted()), true, "muted mirrors the persisted setting")
	_feed_key(g, KEY_M)
	g.step_for_testing(1, DT)
	eq(bool(g.muted), false, "KeyM again unmutes")
	_drop(g)


func test_escape_routing_gates() -> void:
	var g: Variant = _flow_game(52)
	# on the menu: NEVER opens the in-game pause (its 'Save now' would write
	# stage:'menu' over a real save slot)
	_feed_key(g, KEY_ESCAPE)
	g.step_for_testing(1, DT)
	eq(bool(g.paused), false, "no pause on the menu")
	# live cell stage: pause opens, then closes
	g.go_to("cell")
	_walk_plain(g)
	_feed_key(g, KEY_ESCAPE)
	g.step_for_testing(1, DT)
	eq(bool(g.paused), true, "pause opens on Escape")
	_feed_key(g, KEY_ESCAPE)
	g.step_for_testing(1, DT)
	eq(bool(g.paused), false, "pause closes on Escape")
	# editor open wins the first branch (close, never pause-toggle)
	var closed := [false]
	g.editor["open"] = true
	g.editor["close"] = func() -> void: closed[0] = true
	_feed_key(g, KEY_ESCAPE)
	g.step_for_testing(1, DT)
	ok(bool(closed[0]), "editor closed on Escape")
	eq(bool(g.paused), false, "pause untouched by the editor close")
	g.editor["open"] = false
	# mid-transition: Escape does nothing
	g.go_to("creature")
	_feed_key(g, KEY_ESCAPE)
	g.step_for_testing(1, DT)
	eq(bool(g.paused), false, "no pause mid-transition")
	_walk_plain(g)
	_drop(g)


# ---- hud-first click routing --------------------------------------------------------


func test_hud_click_routing_consumes_first() -> void:
	var g: Variant = _flow_game(61)
	_install_recorder_hud(g)
	g.go_to("cell")
	_walk_plain(g)
	# hud hit consumes the click — the stage never sees it
	_pointer_consume = true
	_feed_click(g, Vector2(40, 30))
	g.step_for_testing(1, DT)
	eq(int(_pointer_calls.size()), 1, "pointer_down consulted once")
	approx(float(_pointer_calls[0][0]), 40.0, "pointer x")
	approx(float(_pointer_calls[0][1]), 30.0, "pointer y")
	eq(bool(g.current.saw_click), false, "consumed click never reached the stage")
	# hud miss passes the click through to the stage
	_pointer_consume = false
	_feed_click(g, Vector2(40, 30))
	g.step_for_testing(1, DT)
	eq(int(_pointer_calls.size()), 2, "consulted again")
	eq(bool(g.current.saw_click), true, "unconsumed click reached the stage")
	# mid-transition: NO hud-first routing (the card consumes its own click)
	g.go_to("creature")
	_feed_click(g, Vector2(40, 30))
	g.step_for_testing(1, DT)
	eq(int(_pointer_calls.size()), 2, "no hud routing mid-transition")
	_walk_plain(g)
	_drop(g)


# ---- menu slot metas + continue ------------------------------------------------------


func _write_save(slot: int, seed_v: int, stage_v: String, playtime: float,
		dna: int, pname: String) -> void:
	var ctx: Variant = ContextScript.new(seed_v)
	ctx.stage = stage_v
	ctx.playtime = playtime
	ctx.dna = dna
	ctx.player_name = pname
	ctx.slot = slot
	ctx.genome["spikes"] = 3  # the bot.test.ts round-trip marker (T6 hand-off)
	ok(ctx.save(), "fixture save slot %d written" % slot)


func test_slot_meta_reads_native_saves() -> void:
	_wipe_saves()
	var g: Variant = _flow_game(71)
	_write_save(2, 72, "cell", 123.4, 555, "TestPilot")
	var m: Variant = g.current.slot_meta(2)
	ok(m != null, "meta read")
	eq(String(m["stage"]), "cell", "meta stage")
	approx(float(m["playtime"]), 123.4, "meta playtime")
	eq(int(m["dna"]), 555, "meta dna")
	eq(String(m["playerName"]), "TestPilot", "meta player name")
	ok(float(m["savedAt"]) > 0.0, "savedAt from the file mtime")
	# missing slot → null; junk file → tombstone
	eq(g.current.slot_meta(0), null, "empty slot reads null")
	var f := FileAccess.open("user://saves/slot1.json", FileAccess.WRITE)
	f.store_string("this is not json {{{")
	f = null
	var tomb: Variant = g.current.slot_meta(1)
	eq(String(tomb["playerName"]), "⚠", "corrupt tombstone player name")
	eq(String(tomb["stage"]), "corrupt", "corrupt tombstone stage")
	# occupied flags + delete
	g.current.refresh_slots()
	eq(bool(g.current.occupied[2]), true, "occupied slot 2")
	eq(bool(g.current.occupied[0]), false, "slot 0 free")
	g.current.delete_slot(2)
	eq(g.current.slot_meta(2), null, "deleted slot reads null")
	_drop(g)


func test_continue_loads_and_corrupt_marks() -> void:
	_wipe_saves()
	var g: Variant = _flow_game(81)
	_install_recorder_hud(g)
	_write_save(0, 82, "cell", 456.0, 777, "Pilot")
	# a quitting run's narration latches must not ride into the loaded run
	g.deaths_in_stage = 5
	g.stage_time = 33.0
	g.current.continue_slot(0)
	eq(int(g.deaths_in_stage), 0, "narration reset on continue")
	eq(g.transition["next"], "cell", "continue targets the saved stage")
	eq(String(g.transition["title"]), "WELCOME BACK", "continue card title")
	eq(String(g.transition["sub"]), "the soup remembers Pilot", "continue card sub")
	eq(int(g.context.dna), 777, "loaded dna")
	eq(String(g.context.player_name), "Pilot", "loaded player name")
	eq(int(g.context.slot), 0, "loaded slot")
	eq(g.context.stage, "cell", "loaded stage")
	eq(int(g.context.genome["spikes"]), 3, "genome round-trips (T6 hand-off)")
	# a corrupt slot: marked, never silently overwritten, no transition
	var f := FileAccess.open("user://saves/slot1.json", FileAccess.WRITE)
	f.store_string("{{{ junk")
	f = null
	g.current.continue_slot(1)
	ok(g.current.corrupt_slots.has(1), "corrupt slot marked")
	eq(g.transition["next"], "cell", "no new transition for the corrupt slot")
	eq(int(_toasts.size()), 1, "corruption toast pushed")
	eq(String(_toasts[0]["kind"]), "bad", "toast kind bad")
	_drop(g)


func test_continue_survives_quit_fade() -> void:
	_wipe_saves()
	var g: Variant = _flow_game(91)
	_write_save(0, 92, "cell", 10.0, 50, "LateClicker")
	g.go_to("cell")
	_walk_plain(g)  # live on the fake cell
	g.go_to("menu")  # quit-to-title fade begins
	g.step_for_testing(OUT_STEPS + 10, DT)  # menu live mid-fade (in phase)
	eq(g.current.id, "menu", "menu is live mid-fade")
	# a CONTINUE clicked DURING the fade is live, not stale
	g.current.continue_slot(0)
	_walk_plain(g)  # the quit's in-end fires the survivor
	eq(g.context.stage, "cell", "the surviving continue fired after the quit")
	eq(String(g.transition["title"]), "WELCOME BACK", "with the continue card")
	_drop(g)
