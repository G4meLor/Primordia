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


# ---- item 3: editor hue band (synthesis 4H) ---------------------------------------
# seg was bw3/6.0 with a +1px overlap fudge: 7 cells of 6 widths drew the red
# stop 1/6 of a band past the panel edge, and clicks in the drawn-over margin
# fell through to the full-row rect (hue from the wrong formula). 7 even cells
# now tile the band exactly; the hit rect is unchanged. The draw path runs
# against a recording fake CanvasItem (the renderer only calls draw_* methods,
# no RIDs — headless-safe).

const EditorUi := preload("res://src/ui/editor.gd")

class FakeCi extends RefCounted:
	var polys: Array = []
	var circles: Array = []

	func draw_polygon(points: PackedVector2Array, _colors: PackedColorArray) -> void:
		polys.append(points)

	func draw_circle(position: Vector2, radius: float, _color: Color) -> void:
		circles.append([position, radius])

	func draw_style_box(_style_box: StyleBox, _rect: Rect2) -> void:
		pass

	func draw_string(_font: Font, _pos: Vector2, _text: String, _alignment: int,
			_width: float, _font_size: int, _modulate: Color) -> void:
		pass

	func draw_string_outline(_font: Font, _pos: Vector2, _text: String, _alignment: int,
			_width: float, _font_size: int, _size: int, _color: Color) -> void:
		pass


func _hue_editor() -> Dictionary:
	var ctx: Variant = Ctx.new(SEED)
	var g: Variant = GameScript.new(ctx)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	var ed: Variant = EditorUi.new(g)
	ed.show("cell")
	var hue_row := {}
	for r in ed.rows:
		if String(r["kind"]) == "hue":
			hue_row = r
	return {"ed": ed, "g": g, "hue_row": hue_row}


func test_hue_band_draws_inside_its_hit_rect() -> void:
	var m := _hue_editor()
	var ed: Variant = m["ed"]
	ok(not m["hue_row"].is_empty(), "the hue row exists in cell mode")
	var ci := FakeCi.new()
	var x := 40.0
	var y := 100.0
	var w := 400.0
	ed.render_row(ci, m["hue_row"], x, y, w, 44.0)
	var band: Variant = ed.slider_rects["hue"]
	ok(band != null, "the hue hit rect is registered")
	if band != null:
		var bx: float = float(band["x"])
		var bw: float = float(band["w"])
		eq(bx, x + 90.0, "hit band starts at the label gutter")
		eq(bw, w - 110.0, "hit band width unchanged (spec: slider_rects as before)")
		ok(ci.polys.size() >= 7, "7 spectrum stops drawn (got %d)" % ci.polys.size())
		var max_x := -INF
		var min_x := INF
		for pts in ci.polys:
			for p in pts:
				max_x = maxf(max_x, p.x)
				min_x = minf(min_x, p.x)
		# THE FIX: the drawn band ends AT the hit band's edge (the old 7/6
		# overflow drew the last stop ~48px past bx+bw on this geometry)
		ok(max_x <= bx + bw + 0.01,
				"drawn band stays inside the hit band (max %.2f vs %.2f)" % [max_x, bx + bw])
		ok(max_x >= bx + bw - 1.0, "the last stop still reaches the band edge")
		ok(min_x >= bx - 0.01, "drawn band starts at the hit band's left edge")
	_drop_game(m["g"])


func test_hue_click_at_band_end_maps_360() -> void:
	var m := _hue_editor()
	var ed: Variant = m["ed"]
	var ci := FakeCi.new()
	ed.render_row(ci, m["hue_row"], 40.0, 100.0, 400.0, 44.0)
	var band: Dictionary = ed.slider_rects["hue"]
	# the click path maps through the row rect with a 14px thumb inset —
	# a click at the drawn band's far edge lands hue 360, at its near edge 0
	var r := {"x": float(band["x"]), "y": float(band["y"]) - 6.0,
			"w": float(band["w"]), "h": 34.0}
	ed.click_row(m["hue_row"], float(band["x"]) + float(band["w"]) - 14.0, r)
	eq(float(m["g"].context.genome["hue"]), 360.0, "click at the band's far end → hue 360")
	ed.click_row(m["hue_row"], float(band["x"]) + 14.0, r)
	eq(float(m["g"].context.genome["hue"]), 0.0, "click at the band's near end → hue 0")
	_drop_game(m["g"])


# ---- item 4: walk-back hint threshold (synthesis 4D) ------------------------------
# The respawn hint fired only past 1200 px, but tribe-edge measured REAL
# respawns at home_d 1178.6 and 1017 with no hint through 10-15 s of walking.
# Threshold 900. Respawn geometry pinned like test_tribe_sim's walkback test
# (no threats → the FIRST safest-sample wins).

const TribeSim := preload("res://src/game/tribe/tribe_sim.gd")

const Z_MIN := -200.0
const Z_MAX := 240.0
const WORLD_HALF := 2400.0


func _tribe_sim() -> Dictionary:
	var ctx: Variant = Ctx.new(0xC0FFEE)
	var rec := {"toasts": []}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_toast_gate": func(text, kind, icon, window): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): pass,
		"audio_play": func(n, v, p): pass,
		"audio_set_mood": func(name_v): pass,
		"cam_shake": func(mag, dur): pass,
		"fx_burst": func(x, y, n, opts): pass,
		"fx_spawn": func(opts): pass,
		"context_event": func(ev, data): pass,
		"hud_show_objective": func(text): pass,
		"hud_toast_inset": func(px): pass,
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = TribeSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func test_walkback_hint_covers_the_900_band() -> void:
	# camp ~1050 px from the pinned respawn → the hint fires now (silent at the
	# old 1200); a camp inside 900 stays silent
	for case in [[1050.0, true], [800.0, false]]:
		var m := _tribe_sim()
		var sim: Variant = m["sim"]
		var pr: Variant = RngLib.new_from(4242)
		sim.rng.set_state(pr.state())
		var exp_x: float = pr.range(-WORLD_HALF * 0.5, WORLD_HALF * 0.5)
		var exp_z: float = pr.range(Z_MIN + 30.0, Z_MAX - 30.0)
		# the constructor seeds a starting hut at (0, 80) — replace with the
		# probe camp at the wanted home distance
		sim.huts.clear()
		sim.huts.append({"x": exp_x + float(case[0]), "z": exp_z,
				"buildT": 0.0, "hp": 100.0})
		sim.deathHandled = true  # isolate the respawn path (no tax side effects)
		sim.deathFade = 1.5
		sim.handle_chief_death(0.2)  # deathFade 1.7 > 1.6 → respawn
		eq(float(sim.px), exp_x, "respawn = the pinned first sample")
		eq(float(sim.pz), exp_z, "respawn z pinned")
		var hint := false
		for t in m["rec"]["toasts"]:
			if String(t[0]) == "Your chief is far — walk back":
				hint = true
		if bool(case[1]):
			ok(hint, "camp %d px out → walk-back hint fires" % int(case[0]))
		else:
			ok(not hint, "camp %d px out → silent (below 900)" % int(case[0]))


# ---- item 5: bot capture ensure-dir (synthesis 4H) ---------------------------------
# bot_civ twin_grab saved its PNG into user://visual_capture_civ_bot/ without
# ensure-dir — only the scene wrapper pre-created it, so the full-arc gate
# died on a clean HOME (every fresh QC slot + the M6 gate). The bots now
# mkdir before each save.

func test_bot_captures_ensure_dir_before_save() -> void:
	for pair in [["res://tests/bots/bot_civ.gd", "user://visual_capture_civ_bot"],
			["res://tests/bots/bot_space.gd", "user://visual_capture_space_bot"]]:
		var src := FileAccess.get_file_as_string(String(pair[0]))
		ok(src != "", "%s readable" % String(pair[0]))
		var saves := 0
		var covered := 0
		var from := 0
		while true:
			var save_at := src.find("save_png(", from)
			if save_at < 0:
				break
			saves += 1
			var dir_at := src.rfind("make_dir_recursive_absolute(\"%s\")" % String(pair[1]),
					save_at)
			if dir_at >= 0:
				covered += 1
			from = save_at + 1
		eq(saves, 2 if String(pair[0]).ends_with("bot_civ.gd") else 3,
				"%s capture-save count" % String(pair[0]))
		eq(covered, saves, "%s: every capture save is preceded by its ensure-dir" % String(pair[0]))


func test_save_png_into_a_fresh_dir_works() -> void:
	# the mechanism the bot legs rely on, exercised on a clean dir
	var probe := "user://qc3b1_capture_probe"
	if FileAccess.file_exists(probe + "/.keep"):
		DirAccess.remove_absolute(probe + "/.keep")
	if DirAccess.dir_exists_absolute(probe):
		DirAccess.remove_absolute(probe)
	ok(not DirAccess.dir_exists_absolute(probe), "probe dir starts absent (clean HOME)")
	DirAccess.make_dir_recursive_absolute(probe)
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	var err := img.save_png(probe + "/probe.png")
	eq(err, OK, "save_png into the just-created dir succeeds")
	ok(FileAccess.file_exists(probe + "/probe.png"), "the capture landed")
	DirAccess.remove_absolute(probe + "/probe.png")
	DirAccess.remove_absolute(probe)


# ---- item 6: i18n compose-after-translate (F6/F7, keys already in vi.csv) ---------
# Both sites composed the name INTO the string before any tr() — the whole
# sentence became an orphan lookup key at the display site and EN leaked into
# VI. The template side now goes through tr() FIRST, the name composes after
# (menu.gd:231 pattern); EN output is byte-identical (the keys pass through).

const I18nLib := preload("res://src/core/i18n.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")

const SLOT_QC3B1 := 137


func _slot_path(n: int) -> String:
	return "user://saves/slot%d.json" % n


func test_f6_everyone_toast_en_identity_and_vi_key() -> void:
	var i: Variant = I18nLib.new(SCRATCH_CFG)
	_wipe_cfg()
	ok(i.vi_has("Everyone:"), "the Everyone: key ships in vi.csv (no orphan)")
	# EN: the composed toast is byte-identical to the old raw composition
	var m := _tribe_sim()
	var sim: Variant = m["sim"]
	sim.assign_role("gather")
	var found := ""
	for t in m["rec"]["toasts"]:
		if String(t[0]).begins_with("Everyone:"):
			found = String(t[0])
	eq(found, "Everyone: gather", "EN toast unchanged (Everyone: gather)")
	# VI: the restored translation reaches the toast
	i.set_lang("vi")
	eq(String(TranslationServer.get_locale()), "vi", "locale switched to vi")
	var m2 := _tribe_sim()
	m2["sim"].assign_role("hunt")
	found = ""
	for t in m2["rec"]["toasts"]:
		if String(t[0]).contains("hunt"):
			found = String(t[0])
	eq(found, "Tất cả: hunt", "VI toast carries the restored Everyone: translation")
	i.set_lang("en")
	TranslationServer.set_locale("en")
	_wipe_cfg()


func test_f7_tribe_entry_card_sub_en_identity_and_vi() -> void:
	var i: Variant = I18nLib.new(SCRATCH_CFG)
	_wipe_cfg()
	var key := "looks at the stars and decides to stay"
	ok(i.vi_has(key), "the stars-tail key ships in vi.csv (no orphan)")
	# the source composes the translated tail AFTER the name (menu pattern)
	var src := FileAccess.get_file_as_string("res://src/game/creature/creature_sim.gd")
	ok(src.contains("tr(\"looks at the stars and decides to stay\")"),
			"the card tail goes through tr first (QC r3 F7)")
	# EN: drive the real found_tribe path — the card sub is byte-identical
	if FileAccess.file_exists(_slot_path(SLOT_QC3B1)):
		DirAccess.remove_absolute(_slot_path(SLOT_QC3B1))
	var card := _found_tribe_card("Chieftain")
	eq(String(card.get("sub", "")), "Chieftain looks at the stars and decides to stay",
			"EN card sub unchanged")
	# VI: the same path with the vi locale — name first, translated tail after
	i.set_lang("vi")
	card = _found_tribe_card("Chieftain")
	eq(String(card.get("sub", "")), "Chieftain nhìn các vì sao và quyết định ở lại",
			"VI card sub composes the translated tail after the name")
	i.set_lang("en")
	TranslationServer.set_locale("en")
	_wipe_cfg()
	if FileAccess.file_exists(_slot_path(SLOT_QC3B1)):
		DirAccess.remove_absolute(_slot_path(SLOT_QC3B1))


func _found_tribe_card(player_name: String) -> Dictionary:
	var ctx: Variant = Ctx.new(SEED)
	ctx.player_name = String(player_name)
	ctx.stage = "creature"
	ctx.slot = SLOT_QC3B1
	var rec := {"go_to": []}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): pass,
		"hud_banner": func(data): pass,
		"audio_play": func(n, v, p): pass,
		"cam_shake": func(mag, dur): pass,
		"fx_burst": func(x, y, n, opts): pass,
		"fx_spawn": func(opts): pass,
		"context_event": func(ev, data): pass,
		"tutorial_finish": func(): pass,
		"go_to": func(id, card): rec["go_to"].append([id, card]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, hooks)
	sim.debug_spawn_pack(7)
	sim.found_tribe()
	eq(int(rec["go_to"].size()), 1, "found_tribe fired exactly one go_to")
	if rec["go_to"].size() == 1:
		eq(String(rec["go_to"][0][0]), "tribe", "go_to targets tribe")
		var card: Variant = rec["go_to"][0][1]
		return card if card is Dictionary else {}
	return {}


func _drop_game(g: Variant) -> void:
	if g != null:
		g.hud = {}
		g.free()
