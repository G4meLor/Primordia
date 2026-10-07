## Title screen + front-end flow: new game (difficulty + save slot), continue
## (slot picker + two-click trash), settings (language, sound). Port of Spore
## src/game/menu.ts — canvas-drawn on one MenuCanvas child (the cell stage's
## StageCanvas pattern); buttons are (re)built during the draw pass — update()
## routes clicks against the previous frame's rects (TS comment verbatim:
## imperceptible for a menu).
##
## Save-slot display reads the native save JSONs directly (context.save writes
## every field top-level — the TS meta envelope has no native analog);
## savedAt is the file's mtime (native saves carry no timestamp). Audio cues
## are comment-stubs (audio core: its own task) — every TS audio.play site is
## marked. Drifter genomes render through the cell painter only (the creature
## painter is a later milestone — documented divergence, TS draws kind
## 'creature' every 4th drifter with drawCreature).
extends "res://src/game/stage.gd"

const ContextScript := preload("res://src/game/context.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const MutationScript := preload("res://src/evo/mutation.gd")
const RngScript := preload("res://src/core/rng.gd")
const CellPainterScript := preload("res://src/gfx/cell_painter.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")

const SLOT_COUNT := 3
## TS menu.ts:72 — the drifter stream seed.
const DRIFT_SEED := 0x51ead1
const DRIFT_COUNT := 14

var drifters: Array = []
var t := 0.0
## {label, action: Callable, x, y, w, h, primary, danger, disabled, small, hover}
var buttons: Array = []
var view := "title"  # title | new | continue | settings

# ---- new-game panel state (TS menu.ts:64-70) ----------------------------------
var sel_difficulty := "normal"
var sel_slot := 0
var overwrite_armed := false
var trash_armed := -1
## TS Set<number> — keys only.
var corrupt_slots := {}
var occupied: Array = []
var slot_metas: Array = []

var rng: Variant = null
var canvas: Node2D = null
var veil_canvas: Node2D = null

## The menu's own toast surface — {text, kind, icon, t0, ttl} | null. Recorded
## by continue_slot's load-fail path and drawn by _draw_menu: the live hud
## draws only inside the gameplay stages, so a hud-recorded toast never paints
## while the menu is current (TS's immediate-mode hud rendered on EVERY stage,
## so its corrupt-slot toast displayed — QC r1 B2 nit). Cleared on re-entry.
var menu_toast: Variant = null
## hud TOAST_COLORS subset for the kinds the menu records (hud.gd "bad").
const MENU_TOAST_COLORS := {"bad": "#ff9a8a", "info": "#9fd8ff",
		"good": "#8fe39a", "chaos": "#e2a4ff"}


## One full-screen canvas the menu repaints every frame (cell-stage pattern).
class MenuCanvas extends Node2D:
	var stage: Variant = null
	func _draw() -> void:
		if stage != null:
			stage._draw_menu(self)


## The transition veil layer — drawn above the menu UI (the cell stage's
## reserved-slot pattern: the TS game-level overlay slots between the stage's
## UI and the hud; the menu has no hud, so the veil is simply its top layer).
## game.draw_transition_veil draws nothing while no transition is live.
class MenuVeil extends Node2D:
	var stage: Variant = null
	func _draw() -> void:
		if stage != null:
			stage.game.draw_transition_veil(self)


func _init(game_v: Variant = null) -> void:
	super(game_v, "menu")
	rng = RngScript.new(DRIFT_SEED)
	for i in DRIFT_COUNT:
		drifters.append({
			"genome": MutationScript.mutate(GenomeScript.default_genome(), rng, 0.8),
			"x": rng.range(0.0, 1.0), "y": rng.range(0.0, 1.0),
			"a": rng.range(0.0, TAU),
			"sp": rng.range(4.0, 14.0),
			"seed": rng.range(0.0, 100.0),
			"kind": "creature" if i % 4 == 0 else "cell",
		})


func _ready() -> void:
	canvas = MenuCanvas.new()
	canvas.stage = self
	canvas.name = "MenuCanvas"
	add_child(canvas)
	veil_canvas = MenuVeil.new()
	veil_canvas.stage = self
	veil_canvas.name = "MenuVeil"
	add_child(veil_canvas)
	# T7 hand-off (cam.gd rig ownership): the Camera2D rig boots enabled +
	# current with the DRAG_CENTER anchor, which shifts the whole default
	# canvas by (+vw/2, +vh/2) — the menu draws in absolute screen space, so
	# disable it here exactly like the cell stage does (DISABLE-only: nothing
	# native ever re-enables the rig; the cell stage re-asserts its own state
	# at tree entry).
	var c2d: Variant = game.cam.cam2d
	if c2d != null:
		c2d.enabled = false


func on_enter(_from: Variant = null) -> void:
	# TS audio.setMood('menu') — audio core: its own task. TS also clears
	# hud.showObjective here; natively the hud draws only inside the cell
	# stage's layer, so nothing stale can paint over the menu (and the cell
	# re-sets the line on every entry).
	view = "title"
	# stale confirm states must never survive a visit — one abandoned
	# arm-click used to silently wipe the next slot you loaded
	overwrite_armed = false
	trash_armed = -1
	menu_toast = null
	refresh_slots()


func on_exit() -> void:
	pass


## Every view change flows through here — confirm latches must never
## survive a panel switch (armed trash on NEW used to wipe slots in
## CONTINUE; armed overwrite used to jump slots with the row click).
func _set_view(v: String) -> void:
	view = v
	trash_armed = -1
	overwrite_armed = false


func refresh_slots() -> void:
	occupied = []
	slot_metas = []
	for i in SLOT_COUNT:
		var m: Variant = slot_meta(i)
		slot_metas.append(m)
		occupied.append(m != null)
	# tombstoned rows get a corrupt-tinted meta check via playerName '⚠'


func first_free_slot() -> int:
	for i in SLOT_COUNT:
		if not bool(occupied[i]):
			return i
	return 0


func update(dt: float) -> void:
	t += dt
	var inp: Variant = game.input
	var vw: float = game.vw
	var vh: float = game.vh
	for d in drifters:
		d["x"] += cos(d["a"]) * float(d["sp"]) * dt / vw
		d["y"] += sin(d["a"]) * float(d["sp"]) * dt / vh
		d["a"] += sin(t * 0.3 + float(d["seed"])) * 0.002
		if float(d["x"]) < -0.1:
			d["x"] = 1.1
		if float(d["x"]) > 1.1:
			d["x"] = -0.1
		if float(d["y"]) < -0.1:
			d["y"] = 1.1
		if float(d["y"]) > 1.1:
			d["y"] = -0.1

	# NOTE: buttons are (re)built during the draw pass — update routes clicks
	# against the previous frame's rects (imperceptible for a menu).
	if inp.was_clicked():
		for b in buttons:
			var hit: bool = not bool(b["disabled"]) \
					and inp.mx >= float(b["x"]) and inp.mx <= float(b["x"]) + float(b["w"]) \
					and inp.my >= float(b["y"]) and inp.my <= float(b["y"]) + float(b["h"])
			if hit:
				inp.take_click()
				# TS audio.play('click') + audio.unlock() — audio core: its own task
				var action: Callable = b["action"]
				action.call()
				return
		# TS audio.unlock() on a click that hit nothing — audio core: its own task


## Per-frame draw hook (Game's render side): refresh the whole menu.
func render() -> void:
	if canvas != null:
		canvas.queue_redraw()
	if veil_canvas != null:
		veil_canvas.queue_redraw()


# ---- actions -----------------------------------------------------------------

## TS continueSlot (menu.ts:380-398).
func continue_slot(slot: int) -> void:
	var ok: bool = game.context.load(slot)
	if not ok:
		# a corrupt slot must NOT be silently overwritten by a fresh run —
		# the row showed 'CELL · 12 min · 500 DNA' one click earlier. Mark it
		# and let the player delete (trash) or start over deliberately.
		corrupt_slots[slot] = true
		# TS's immediate-mode hud drew its toast on EVERY stage, so the
		# corrupt-slot toast displayed over the menu too. Natively the hud
		# renders only inside the gameplay stages — the hud record below keeps
		# the hud-state parity for the quit-to-title path, and menu_toast is
		# the menu's own draw of the same toast (the visible one; _draw_menu).
		var text: String = game.i18n.tr_key(
				"This slot is corrupted — delete it in CONTINUE, or use NEW LIFE")
		game.hud["toast"].call(text, "bad", "⚠️")
		menu_toast = {"text": text, "kind": "bad", "icon": "⚠️",
				"t0": t, "ttl": 4.0}
		return
	# TS audio.play('levelup') — audio core: its own task
	# the loaded run starts its narration clean — the quitting run's latches
	# (death-window blackout, gaia ledger, DNA window, instant bless) live on
	# the Game and must not ride into the continued run
	game.reset_narration()
	var stage_id: String = game.context.stage
	if stage_id == "menu":
		stage_id = "cell"
	# survivesQuit: a CONTINUE clicked during the quit fade is live, not stale
	game.go_to(stage_id, {
		"title": "WELCOME BACK",
		# R9 identity ruling: the chosen creature name reads here when set
		"sub": "%s %s" % [game.i18n.tr_key("the soup remembers"), game.context.get_player_display()],
	}, {"survivesQuit": true})


## Begin a fresh run (also used by tests) — TS MenuStage.startNewGame
## (menu.ts:401-434) with the M1 difficulty contract. seed_v < 0 rolls the
## context's one sanctioned global randi() (tests pin seeds).
func start_new_game(slot := 0, difficulty := "normal", seed_v := -1) -> void:
	var c: Variant = game.context
	# optional seed: tests pin the world they mean to probe (a bare
	# new GameContext() rolls Math.random — the probe's seed would be clobbered)
	var fresh: Variant = ContextScript.new(seed_v)
	# the NEW seed/world must land on the context BEFORE the stage rebuild —
	# the stage constructors fold ctx.world into their chaos decks, so
	# swapping afterwards built run 2's decks from run 1's world (C1)
	c.seed = fresh.seed
	c.rng = fresh.rng
	c.genome = fresh.genome
	# the world genome derives from the seed — a NEW LIFE on a new seed used
	# to inherit run-1's world traits, reveals and kill/extinction counters
	c.world = fresh.world
	c.world_stats = {"kills": 0, "extinctions": 0}
	# fresh stage instances — run-1 latches (totem 100, civ victoryFired,
	# space finale) must not leak into this run
	game.reset_stages_for_new_run()
	c.dna = 100  # Flagellum suggestion (27) + LEG (65) both affordable in the tutorial
	c.karma = 0.0
	c.reset_karma_profile()  # R15: the profile + cap anchor are per-run state
	c.reset_chaos_scar()  # R13: the peak + fired scar tiers are per-run too
	c.run_shape = ""  # R12: the heredity shape re-snaps at this run's first exit
	c.difficulty = difficulty
	c.chaos = c.starting_chaos()
	c.playtime = 0.0
	c.total_dna_earned = 0
	c.bestiary.clear()
	c.eco = null
	c.flags = {"difficulty": difficulty}
	c.stage = "cell"
	c.slot = slot
	c.player_name = "Squish"
	c.save()  # create the slot immediately
	# TS audio.play('ascend') — audio core: its own task
	game.go_to("cell", {
		"title": "CELL STAGE",
		"sub": "you are one hungry dot in an ancient ocean",
	})


# ---- save-slot display (TS core/save.ts slotMeta/deleteSlot, native format) --

## TS slotMeta: the meta fields read straight off the save JSON's top level
## (the native format has no meta envelope). A file that exists but fails to
## parse is a TOMBSTONE so the UI shows the corrupt mark and offers trash,
## instead of a silent ghost slot that NEW LIFE overwrites without a confirm.
## QC r8 batch2.6: a file that PARSES but is not save-shaped (wrong keys,
## non-numeric dna/playtime) used to render a very loadable-looking row with
## lying numbers ("CIV · 6 min · 777 DNA · Phantom") — it tombstones up front
## now, before any click.
const SAVE_STAGES := ["cell", "creature", "tribe", "civ", "space"]


func _save_shaped(d: Dictionary) -> bool:
	if not SAVE_STAGES.has(String(d.get("stage", ""))):
		return false
	var dna: Variant = d.get("dna", null)
	if not (dna is float or dna is int) or is_nan(float(dna)) or float(dna) < 0.0 \
			or not is_finite(float(dna)):
		return false
	var pt: Variant = d.get("playtime", null)
	if not (pt is float or pt is int) or is_nan(float(pt)) or float(pt) < 0.0 \
			or not is_finite(float(pt)):
		return false
	if not (d.get("playerName", null) is String):
		return false
	var sd: Variant = d.get("seed", null)
	return (sd is float or sd is int) and is_finite(float(sd)) and not is_nan(float(sd))


func slot_meta(slot: int) -> Variant:
	var path := "user://saves/slot%d.json" % slot
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not _save_shaped(parsed):
		return {"stage": "corrupt", "playtime": 0.0, "dna": 0,
				"playerName": "⚠", "savedAt": 0.0}
	var d: Dictionary = parsed
	# savedAt: TS Date.now() at write — native saves carry no timestamp, the
	# file's mtime stands in (relTime granularity is minutes either way)
	return {
		"stage": d.get("stage", "cell"),
		"playtime": float(d.get("playtime", 0.0)),
		"dna": int(d.get("dna", 0)),
		"playerName": String(d.get("playerName", "Squish")),
		"creatureName": String(d.get("creatureName", "")),
		"savedAt": float(FileAccess.get_modified_time(path)),
	}


## R7 — the save-slot line's name: the creature's chosen display name when
## set, else the playerName the run auto-derived. The meta is the raw slot
## JSON read (no live context here to ask get_display_name), so the fallback
## rides the stored playerName. Pure + static for the headless suite.
static func slot_display_name(meta: Dictionary) -> String:
	var pname := String(meta.get("creatureName", ""))
	if pname.is_empty():
		pname = String(meta.get("playerName", "Squish"))
	if pname.length() > 14:
		pname = pname.substr(0, 13) + "…"
	return pname


## TS deleteSlot: remove the save; a missing file is ignored.
func delete_slot(slot: int) -> void:
	var dir := DirAccess.open("user://saves")
	if dir != null and dir.file_exists("slot%d.json" % slot):
		dir.remove("slot%d.json" % slot)


## TS relTime (menu.ts:38-53) — the TS hardcodes both languages in a lang
## branch (NOT t() keys), so the port keeps the branch shape verbatim.
func _rel_time(ts: float) -> String:
	var d: float = float(Time.get_unix_time_from_system()) - ts
	var m := floori(d / 60.0)
	if game.i18n.get_lang() == "vi":
		if m < 1:
			return "vừa xong"
		if m < 60:
			return "%d phút trước" % m
		var hv := floori(float(m) / 60.0)
		if hv < 24:
			return "%d giờ trước" % hv
		return "%d ngày trước" % floori(float(hv) / 24.0)
	if m < 1:
		return "just now"
	if m < 60:
		return "%dm ago" % m
	var h := floori(float(m) / 60.0)
	if h < 24:
		return "%dh ago" % h
	return "%dd ago" % floori(float(h) / 24.0)


# ---- view builders -------------------------------------------------------------
# (geometry TS-verbatim, menu.ts:155-376; called from the draw pass so every
# panel label survives to the screen — round-2 fix #4)

func _btn(label: String, action: Callable, x: float, y: float, w: float, h: float,
		primary := false, danger := false, disabled := false) -> void:
	buttons.append({"label": label, "action": action, "x": x, "y": y, "w": w, "h": h,
			"primary": primary, "danger": danger, "disabled": disabled,
			"small": false, "hover": false})


func _build_title(vw: float, vh: float) -> void:
	var bw := 300.0
	var bh := 54.0
	var cx: float = vw / 2.0 - bw / 2.0
	var by: float = vh * 0.55
	_btn(game.i18n.tr_key("✦  NEW LIFE"), func() -> void:
		sel_difficulty = "normal"
		sel_slot = first_free_slot()
		_set_view("new")
	, cx, by, bw, bh, true)
	by += bh + 14.0
	_btn(game.i18n.tr_key("▶  CONTINUE"), func() -> void:
		refresh_slots()
		_set_view("continue")
	, cx, by, bw, bh)
	by += bh + 14.0
	_btn(game.i18n.tr_key("⚙  SETTINGS"), func() -> void:
		_set_view("settings")
	, cx, by, bw, bh)


func _build_new(vw: float, vh: float, ci: CanvasItem) -> void:
	var pw: float = minf(620.0, vw - 40.0)
	var px: float = vw / 2.0 - pw / 2.0
	var py := 90.0
	var ph: float = maxf(vh - py - 40.0, 480.0)  # slot row 3 ends py+406 — short viewports clipped it under the buttons
	RendererScript.panel(ci, px, py, pw, ph, {
		"fill": RendererScript.css_color("rgba(8,14,32,0.94)"),
		"stroke": RendererScript.css_color("rgba(120,180,255,0.4)"),
		"shadow": RendererScript.css_color("rgba(40,120,255,0.2)"),
	})

	RendererScript.outlined_text(ci, game.i18n.tr_key("BEGIN A NEW LIFE"),
			vw / 2.0, py + 34.0, {"size": 22.0, "fill": Color("#bfe6ff")})

	# difficulty cards
	RendererScript.outlined_text(ci, game.i18n.tr_key("DIFFICULTY"), px + 30.0, py + 76.0,
			{"size": 12.0, "fill": RendererScript.css_color("#8fd0ff"), "align": "left"})
	var diff_defs := [
		{"d": "peaceful", "name": game.i18n.tr_key("Peaceful"),
				"desc": game.i18n.tr_key("fewer, gentler chaos events")},
		{"d": "normal", "name": game.i18n.tr_key("Normal"),
				"desc": game.i18n.tr_key("the ocean as intended")},
		{"d": "chaos", "name": game.i18n.tr_key("Chaos"),
				"desc": game.i18n.tr_key("events come fast and angry")},
	]
	var cw: float = (pw - 60.0 - 20.0) / 3.0
	for i in diff_defs.size():
		var def: Dictionary = diff_defs[i]
		var x: float = px + 30.0 + float(i) * (cw + 10.0)
		var y: float = py + 90.0
		var h := 74.0
		var sel: bool = sel_difficulty == def["d"]
		_btn("", func() -> void:
			sel_difficulty = def["d"]
			# TS audio.play('hover') — audio core: its own task
		, x, y, cw, h, sel)
		RendererScript.panel(ci, x, y, cw, h, {
			"fill": RendererScript.css_color("rgba(60,120,220,0.9)") if sel
					else RendererScript.css_color("rgba(14,24,52,0.9)"),
			"stroke": RendererScript.css_color("rgba(170,215,255,0.9)") if sel
					else RendererScript.css_color("rgba(110,160,220,0.25)"),
			"lw": 2.0 if sel else 1.2,
		})
		RendererScript.outlined_text(ci, def["name"], x + cw / 2.0, y + 22.0,
				{"size": 15.0, "fill": Color("#ffffff") if sel else Color("#cfe2ff")})
		# wrap desc into two lines
		var words: PackedStringArray = String(def["desc"]).split(" ")
		var mid := ceili(words.size() / 2.0)
		var line_a := " ".join(words.slice(0, mid))
		var line_b := " ".join(words.slice(mid))
		RendererScript.outlined_text(ci, line_a, x + cw / 2.0, y + 42.0,
				{"size": 9.5, "fill": RendererScript.css_color("rgba(200,225,255,0.65)")})
		RendererScript.outlined_text(ci, line_b, x + cw / 2.0, y + 56.0,
				{"size": 9.5, "fill": RendererScript.css_color("rgba(200,225,255,0.65)")})

	# slot rows
	RendererScript.outlined_text(ci, game.i18n.tr_key("SAVE SLOT"), px + 30.0, py + 196.0,
			{"size": 12.0, "fill": RendererScript.css_color("#8fd0ff"), "align": "left"})
	RendererScript.outlined_text(ci, game.i18n.tr_key("Pick a save slot — your run autosaves here."),
			px + 30.0, py + 214.0,
			{"size": 10.0, "fill": RendererScript.css_color("rgba(200,225,255,0.5)"), "align": "left"})
	for i in SLOT_COUNT:
		var y2: float = py + 228.0 + float(i) * 62.0
		var x2: float = px + 30.0
		var w2: float = pw - 60.0
		var sel2: bool = sel_slot == i
		var slot_i := i
		_btn("", func() -> void:
			if sel_slot != slot_i:
				overwrite_armed = false
			sel_slot = slot_i
			# TS audio.play('hover') — audio core: its own task
		, x2, y2, w2, 54.0, sel2)
		RendererScript.panel(ci, x2, y2, w2, 54.0, {
			"fill": RendererScript.css_color("rgba(50,100,190,0.85)") if sel2
					else RendererScript.css_color("rgba(12,20,44,0.9)"),
			"stroke": RendererScript.css_color("rgba(170,215,255,0.85)") if sel2
					else RendererScript.css_color("rgba(110,160,220,0.22)"),
		})
		var meta: Variant = slot_metas[i]
		RendererScript.outlined_text(ci, "slot%d" % (i + 1), x2 + 18.0, y2 + 26.0,
				{"size": 16.0, "fill": Color("#ffffff") if sel2 else Color("#9fc8ff"),
				"align": "left"})
		if meta != null:
			var stage_name: String = String(meta["stage"]).to_upper() if String(meta["stage"]) != "" else "CELL"
			var pname: String = slot_display_name(meta)
			var line: String = "%s · %d %s · %d DNA · %s" % [
				stage_name, roundi(float(meta["playtime"]) / 60.0),
				game.i18n.tr_key("min"), int(meta["dna"]), pname]
			RendererScript.outlined_text(ci, line, x2 + 110.0, y2 + 20.0,
					{"size": 11.0, "fill": Color("#dfeaff"), "align": "left", "maxWidth": w2 - 130.0})
			RendererScript.outlined_text(ci, _rel_time(float(meta["savedAt"])), x2 + 110.0, y2 + 38.0,
					{"size": 10.0, "fill": RendererScript.css_color("rgba(180,210,240,0.55)"), "align": "left"})
			if sel2:
				RendererScript.outlined_text(ci, game.i18n.tr_key("overwrite?"), x2 + w2 - 16.0, y2 + 26.0,
						{"size": 11.0, "fill": Color("#ffb0a0"), "align": "right"})
		else:
			RendererScript.outlined_text(ci, game.i18n.tr_key("empty"), x2 + 110.0, y2 + 26.0,
					{"size": 11.0, "fill": RendererScript.css_color("rgba(170,200,235,0.45)"), "align": "left"})

	# begin + back (overwrite requires a second confirming click)
	var by: float = py + ph - 66.0
	var overwriting: bool = bool(occupied[sel_slot])
	var begin_label: String = game.i18n.tr_key("overwrite") + "?" \
			if overwriting and not overwrite_armed else game.i18n.tr_key("▶ BEGIN")
	_btn(begin_label, func() -> void:
		if overwriting and not overwrite_armed:
			overwrite_armed = true
			# TS audio.play('alarm', 0.4) — audio core: its own task
			return
		start_new_game(sel_slot, sel_difficulty)
	, px + pw - 250.0, by, 220.0, 48.0, true)
	_btn(game.i18n.tr_key("◀ Back"), func() -> void:
		_set_view("title")
	, px + 30.0, by, 140.0, 48.0)


func _build_continue(vw: float, vh: float, ci: CanvasItem) -> void:
	var pw: float = minf(620.0, vw - 40.0)
	var px: float = vw / 2.0 - pw / 2.0
	var py := 120.0
	var ph := 380.0
	RendererScript.panel(ci, px, py, pw, ph, {
		"fill": RendererScript.css_color("rgba(8,14,32,0.94)"),
		"stroke": RendererScript.css_color("rgba(120,180,255,0.4)"),
	})
	RendererScript.outlined_text(ci, game.i18n.tr_key("CONTINUE A RUN"), vw / 2.0, py + 34.0,
			{"size": 22.0, "fill": Color("#bfe6ff")})
	RendererScript.outlined_text(ci, game.i18n.tr_key("PICK A SLOT"), px + 30.0, py + 66.0,
			{"size": 11.0, "fill": RendererScript.css_color("#8fd0ff"), "align": "left"})

	# delete buttons FIRST so they win the hit test over the slot rows
	# (two-click confirm — an instant permanent delete this close to the
	# load row ate saves by accident)
	for i in SLOT_COUNT:
		if slot_metas[i] == null:
			continue
		var y: float = py + 84.0 + float(i) * 66.0
		var slot_i := i
		_btn("❗" if trash_armed == i else "🗑", func() -> void:
			if trash_armed != slot_i:
				trash_armed = slot_i
				# TS audio.play('alarm', 0.4) — audio core: its own task
				return
			delete_slot(slot_i)
			trash_armed = -1
			refresh_slots()
		, px + pw - 76.0, y + 10.0, 40.0, 36.0, false, true)

	for i in SLOT_COUNT:
		var y2: float = py + 84.0 + float(i) * 66.0
		var meta: Variant = slot_metas[i]
		var slot_i2 := i
		_btn("", func() -> void:
			continue_slot(slot_i2)
		, px + 30.0, y2, pw - 60.0, 56.0, meta != null, false, meta == null)
		RendererScript.panel(ci, px + 30.0, y2, pw - 60.0, 56.0, {
			"fill": RendererScript.css_color("rgba(50,100,190,0.8)") if meta != null
					else RendererScript.css_color("rgba(12,20,44,0.9)"),
			"stroke": RendererScript.css_color("rgba(170,215,255,0.8)") if meta != null
					else RendererScript.css_color("rgba(110,160,220,0.18)"),
		})
		var label: String = "slot%d ⚠" % (i + 1) if corrupt_slots.has(i) else "slot%d" % (i + 1)
		RendererScript.outlined_text(ci, label, px + 48.0, y2 + 28.0,
				{"size": 15.0, "fill": Color("#ffffff") if meta != null
				else RendererScript.css_color("rgba(160,190,225,0.4)"), "align": "left"})
		if meta != null:
			var pname: String = meta["playerName"]
			if pname.length() > 14:
				pname = pname.substr(0, 13) + "…"
			var line: String = "%s · %d %s · %d DNA · %s" % [
				String(meta["stage"]).to_upper() if String(meta["stage"]) != "" else "CELL",
				roundi(float(meta["playtime"]) / 60.0),
				game.i18n.tr_key("min"), int(meta["dna"]), pname]
			RendererScript.outlined_text(ci, line, px + 130.0, y2 + 22.0,
					{"size": 11.0, "fill": Color("#dfeaff"), "align": "left", "maxWidth": pw - 170.0})
			RendererScript.outlined_text(ci, _rel_time(float(meta["savedAt"])), px + 130.0, y2 + 40.0,
					{"size": 10.0, "fill": RendererScript.css_color("rgba(180,210,240,0.55)"), "align": "left"})
		else:
			RendererScript.outlined_text(ci, game.i18n.tr_key("no save in this slot"), px + 130.0, y2 + 28.0,
					{"size": 11.0, "fill": RendererScript.css_color("rgba(170,200,235,0.4)"), "align": "left"})

	_btn(game.i18n.tr_key("◀ Back"), func() -> void:
		_set_view("title")
	, px + 30.0, py + ph - 58.0, 140.0, 44.0)


func _build_settings(vw: float, vh: float, ci: CanvasItem) -> void:
	var pw: float = minf(560.0, vw - 40.0)
	var px: float = vw / 2.0 - pw / 2.0
	var py := 140.0
	var ph := 330.0
	RendererScript.panel(ci, px, py, pw, ph, {
		"fill": RendererScript.css_color("rgba(8,14,32,0.94)"),
		"stroke": RendererScript.css_color("rgba(120,180,255,0.4)"),
	})
	RendererScript.outlined_text(ci, game.i18n.tr_key("SETTINGS"), vw / 2.0, py + 34.0,
			{"size": 22.0, "fill": Color("#bfe6ff")})

	# language
	RendererScript.outlined_text(ci, game.i18n.tr_key("LANGUAGE"), px + 30.0, py + 80.0,
			{"size": 12.0, "fill": RendererScript.css_color("#8fd0ff"), "align": "left"})
	var lang_defs := [["English", "en"], ["Tiếng Việt", "vi"]]
	for i in lang_defs.size():
		var def: Array = lang_defs[i]
		var x: float = px + 30.0 + float(i) * 170.0
		var sel: bool = game.i18n.get_lang() == def[1]
		var lang_code: String = def[1]
		_btn(def[0], func() -> void:
			game.i18n.set_lang(lang_code)
			# TS audio.play('dna', 0.6) — audio core: its own task
		, x, py + 94.0, 150.0, 40.0, sel)
		RendererScript.panel(ci, x, py + 94.0, 150.0, 40.0, {
			"fill": RendererScript.css_color("rgba(60,120,220,0.9)") if sel
					else RendererScript.css_color("rgba(14,24,52,0.9)"),
			"stroke": RendererScript.css_color("rgba(170,215,255,0.9)") if sel
					else RendererScript.css_color("rgba(110,160,220,0.25)"),
		})
		RendererScript.outlined_text(ci, def[0], x + 75.0, py + 114.0,
				{"size": 14.0, "fill": Color("#ffffff") if sel else Color("#cfe2ff")})
	RendererScript.outlined_text(ci, game.i18n.tr_key("Applies instantly. Names of species stay faux-Latin."),
			px + 30.0, py + 152.0,
			{"size": 10.0, "fill": RendererScript.css_color("rgba(200,225,255,0.45)"), "align": "left"})

	# sound
	RendererScript.outlined_text(ci, game.i18n.tr_key("SOUND"), px + 30.0, py + 190.0,
			{"size": 12.0, "fill": RendererScript.css_color("#8fd0ff"), "align": "left"})
	var sound_on: bool = not bool(game.muted)
	# the button label IS the drawn text (QC round-2 B3: the hit-text read
	# "On"/"Off" while the panel drew "🔊 On"/"🔇 Off" — mismatched for label
	# readers/accessibility; the hit area is rect-based and unchanged)
	var sound_label: String = ("🔊 %s" % game.i18n.tr_key("On")) if sound_on \
			else ("🔇 %s" % game.i18n.tr_key("Off"))
	_btn(sound_label, func() -> void:
		game.toggle_mute()
	, px + 30.0, py + 204.0, 150.0, 40.0, sound_on)
	RendererScript.panel(ci, px + 30.0, py + 204.0, 150.0, 40.0, {
		"fill": RendererScript.css_color("rgba(60,140,90,0.9)") if sound_on
				else RendererScript.css_color("rgba(90,50,50,0.9)"),
		"stroke": RendererScript.css_color("rgba(170,215,255,0.4)"),
	})
	RendererScript.outlined_text(ci, sound_label, px + 105.0, py + 224.0,
			{"size": 14.0, "fill": Color("#ffffff")})

	_btn(game.i18n.tr_key("◀ Back"), func() -> void:
		_set_view("title")
	, px + 30.0, py + ph - 58.0, 140.0, 44.0)


# ---- draw ------------------------------------------------------------------------

## TS MenuStage.render (menu.ts:438-529) — the full draw order: deep soup
## gradient → drifting life → god rays → title glow → title text → the active
## view's UI (buttons rebuilt here) → footer.
func _draw_menu(ci: CanvasItem) -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	if vw <= 1.0 or vh <= 1.0:
		return  # degenerate viewport (headless -s tree entry) — nothing to draw

	# deep soup gradient (two stacked quads, per-vertex colors — the TS
	# 3-stop createLinearGradient 0 / 0.5 / 1)
	var c0 := Color("#071230")
	var c1 := Color("#0a1c3f")
	var c2 := Color("#040a1c")
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pts_top := PackedVector2Array([Vector2(0, 0), Vector2(vw, 0), Vector2(vw, vh / 2.0), Vector2(0, vh / 2.0)])
	var cols_top := PackedColorArray([c0, c0, c1, c1])
	ci.draw_polygon(pts_top, cols_top)
	var pts_bot := PackedVector2Array([Vector2(0, vh / 2.0), Vector2(vw, vh / 2.0), Vector2(vw, vh), Vector2(0, vh)])
	var cols_bot := PackedColorArray([c1, c1, c2, c2])
	ci.draw_polygon(pts_bot, cols_bot)

	# drifting life (all kinds through the cell painter — see the header note)
	for d in drifters:
		var s: float = 0.8 + fmod(float(d["seed"]), 1.0)
		var pose := {
			"x": float(d["x"]) * vw, "y": float(d["y"]) * vh,
			"moveAngle": float(d["a"]), "speed": 0.2, "scale": 1.6 * s,
			"hurt": 0.0, "eat": 0.0, "dash": 0.0, "seed": float(d["seed"]),
		}
		CellPainterScript.draw_cell(ci, d["genome"], pose,
				{"t": t, "alpha": 0.4 if String(d["kind"]) == "cell" else 0.35},
				Vector2.ZERO, 1.0)

	# god rays (TS 'lighter' composite columns — vertical per-vertex fade,
	# documented visual approximation)
	for i in 3:
		var rx: float = vw * (0.2 + float(i) * 0.3) + sin(t * 0.2 + float(i) * 2.0) * 40.0
		var pts := PackedVector2Array([Vector2(rx - 60.0, 0.0), Vector2(rx + 160.0, 0.0),
				Vector2(rx + 160.0, vh), Vector2(rx - 60.0, vh)])
		var col := Color(90.0 / 255.0, 160.0 / 255.0, 1.0, 0.05)
		ci.draw_polygon(pts, PackedColorArray([col, col, Color(col, 0.0), Color(col, 0.0)]))

	RendererScript.glow(ci, vw / 2.0, vh * 0.26, 240.0,
			RendererScript.css_color("rgba(70,140,255,0.16)"), 1.0)

	if view == "title":
		var title_size: float = minf(84.0, vw / 9.0)
		RendererScript.outlined_text(ci, "PRIMORDIA", vw / 2.0, vh * 0.24,
				{"size": title_size, "fill": Color("#dfeeff")})
		RendererScript.outlined_text(ci, "A  C H A O S   E V O L U T I O N",
				vw / 2.0, vh * 0.24 + title_size * 0.7,
				{"size": 14.0, "fill": RendererScript.css_color("rgba(150,200,255,0.65)")})
		RendererScript.outlined_text(ci, game.i18n.tr_key("eat · evolve · survive the universe's worst ideas"),
				vw / 2.0, vh * 0.44,
				{"size": 15.0, "fill": RendererScript.css_color("rgba(190,220,255,0.55)")})

	# rebuild the active view's UI here — AFTER the canvas clear — so every
	# panel label actually survives to the screen (round-2 fix #4)
	buttons = []
	if view == "title":
		_build_title(vw, vh)
	elif view == "new":
		_build_new(vw, vh, ci)
	elif view == "continue":
		_build_continue(vw, vh, ci)
	else:
		_build_settings(vw, vh, ci)

	# hover upgrades (TS setCursor('pointer') — the X11-safe hover path)
	var inp: Variant = game.input
	var any_hover := false
	for b in buttons:
		var hov: bool = not bool(b["disabled"]) \
				and inp.mx >= float(b["x"]) and inp.mx <= float(b["x"]) + float(b["w"]) \
				and inp.my >= float(b["y"]) and inp.my <= float(b["y"]) + float(b["h"])
		b["hover"] = hov
		if hov:
			any_hover = true
	if any_hover:
		game.hover_cursor()

	# buttons (label:'' rows/cards paint their own visuals in the builders —
	# re-drawing a panel here WIPE their custom text: slot rows and
	# difficulty cards were unreadable)
	for b in buttons:
		if String(b["label"]) == "":
			continue
		var hov2: bool = bool(b["hover"])
		var danger: bool = bool(b["danger"])
		var primary: bool = bool(b["primary"])
		var disabled: bool = bool(b["disabled"])
		RendererScript.panel(ci, float(b["x"]), float(b["y"]), float(b["w"]), float(b["h"]), {
			"fill": RendererScript.css_color("rgba(30,38,58,0.9)") if disabled
					else (RendererScript.css_color("rgba(190,70,70,0.95)") if hov2 and danger
					else (RendererScript.css_color("rgba(70,130,230,0.95)") if hov2
					else (RendererScript.css_color("rgba(40,80,170,0.9)") if primary
					else (RendererScript.css_color("rgba(120,45,45,0.9)") if danger
					else RendererScript.css_color("rgba(14,24,52,0.9)"))))),
			"stroke": RendererScript.css_color("rgba(170,215,255,0.9)") if hov2
					else RendererScript.css_color("rgba(110,160,220,0.35)"),
			"lw": 1.6,
			"shadow": RendererScript.css_color("rgba(80,150,255,0.35)") if hov2 else null,
		})
		RendererScript.outlined_text(ci, b["label"],
				float(b["x"]) + float(b["w"]) / 2.0, float(b["y"]) + float(b["h"]) / 2.0,
				{"size": 13.0 if bool(b["small"]) else 17.0,
				"fill": RendererScript.css_color("rgba(200,220,255,0.35)") if disabled
						else (Color("#ffffff") if hov2 else Color("#cfe2ff"))})

	# footer
	RendererScript.outlined_text(ci, "%s %s · M %s · %s" % [
		game.i18n.tr_key("seed"), String.num_int64(int(game.context.seed), 16),
		game.i18n.tr_key("mute"),
		game.i18n.tr_key("everything procedural, nothing scripted")],
		vw / 2.0, vh - 24.0,
		{"size": 11.0, "fill": RendererScript.css_color("rgba(140,180,230,0.4)")})

	# the menu's own toast (continue_slot's load-fail record — see menu_toast):
	# hud-toast shape (bottom-left panel, icon + kind-colored text, hud fade
	# math), parked above the footer so the two never overlap
	if menu_toast != null:
		var age: float = t - float(menu_toast["t0"])
		var ttl: float = float(menu_toast["ttl"])
		if age >= 0.0 and age < ttl:
			var a: float = minf(1.0, age * 4.0) * minf(1.0, (ttl - age) * 2.0)
			var mtw: float = ThemeDB.fallback_font.get_string_size(
					String(menu_toast["text"]),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
			var mpw: float = minf(maxf(170.0, mtw + 60.0), vw - 32.0)
			RendererScript.panel(ci, 16.0, vh - 78.0, mpw, 26.0, {
				"fill": RendererScript.css_color("rgba(6,10,24,0.85)"),
				"stroke": RendererScript.css_color("rgba(120,160,220,0.25)"),
			})
			RendererScript.outlined_text(ci, "%s %s" % [String(menu_toast["icon"]),
					String(menu_toast["text"])], 30.0, vh - 64.0,
					{"size": 12.0, "fill": RendererScript.css_color(String(
							MENU_TOAST_COLORS.get(String(menu_toast["kind"]), "#ff9a8a"))),
					"align": "left", "maxWidth": mpw - 28.0, "alpha": a})
