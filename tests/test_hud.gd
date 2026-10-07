# Tests for src/ui/hud.gd + src/ui/pause.gd — Task 8 overlay state machines
# (port of the TS hud.ts/pause.ts behavior reachable without a canvas; the
# draw paths render under xvfb in tests/scenes/test_editor_click.gd).
# Covers: toast queue aging/ttl/dedup/cap, banner queue + ttl 2.4 default
# 3.4 + dismiss + same-title dedup, float_world rise, dna display smoothing +
# pulse via the context dna signal, abilities payload passthrough, the
# pointer_down hit zones; pause: item layout, click routing through the
# actions hook dict (save feedback toasts, quit chain), help/world views.
extends "res://tests/test_base.gd"

const HudScript := preload("res://src/ui/hud.gd")
const PauseScript := preload("res://src/ui/pause.gd")
const GameInputScript := preload("res://src/core/input.gd")
const ContextScript := preload("res://src/game/context.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const DT := 1.0 / 60.0
const SCRATCH := "user://test_hud_settings.cfg"


func _en() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_hud_settings.cfg")
		dir.remove("test_hud_settings.cfg.tmp")
	TranslationServer.set_locale("en")


## Duck-typed game for the headless overlay tests. The hud reads
## context/input/i18n/muted + calls toggle_mute()/open_pause(); the pause
## reads vw/vh/muted/context/i18n/input + acts through the actions hook dict
## (the seam the cell stage wires — see the PauseUi header).
class MockGame extends RefCounted:
	var context: Variant
	var input: Variant
	var i18n: Variant
	var vw := 1024.0
	var vh := 600.0
	var muted := false
	var toasts: Array = []          # [text, kind, icon] recordings
	var mute_toggles := 0
	var pause_opens := 0
	var hud: Dictionary = {}

	func _init() -> void:
		context = ContextScript.new(99)
		input = GameInputScript.new()
		i18n = I18nScript.new(SCRATCH)
		i18n.set_lang("en")
		hud = {
			"toast": func(text: String, kind: String, icon: String) -> void:
				toasts.append([text, kind, icon]),
		}

	func toggle_mute() -> void:
		muted = not muted
		mute_toggles += 1

	func open_pause() -> void:
		pause_opens += 1

	func set_cursor(_c: String) -> void:
		pass

	func hover_cursor() -> void:
		pass


func _hud(g: Variant) -> Variant:
	return HudScript.new(g)


# ---- toast queue ------------------------------------------------------------

func test_toast_push_age_and_expiry() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.toast("hello", "info", "•")
	eq(hud._toasts.size(), 1, "toast pushed")
	eq(String(hud._toasts[0]["text"]), "hello", "text stored verbatim (call sites translate)")
	eq(String(hud._toasts[0]["kind"]), "info", "kind stored")
	eq(String(hud._toasts[0]["icon"]), "•", "icon stored")
	eq(float(hud._toasts[0]["ttl"]), 4.0, "default ttl 4")
	hud.update(4.1)
	eq(hud._toasts.size(), 0, "expired toasts drop")


func test_toast_dedup_within_1_5s_then_allows_again() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.toast("dup", "info", "•")
	hud.toast("dup", "info", "•")
	eq(hud._toasts.size(), 1, "identical repeat within 1.5s drops (rate-limit)")
	hud.update(1.6)
	hud.toast("dup", "info", "•")
	eq(hud._toasts.size(), 2, "after 1.5s the same text pushes again")


# QC round-2 B3 — gate toasts (squeak-ignore, pack-full) opt into a longer
# dedupe window: while the gate condition persists (a held key re-fires the
# gate every tick) the message re-shows at most once per window. The plain
# toast keeps the TS 1.5 s flood guard untouched.
func test_toast_gate_window_dedupes_longer() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.toast_gate("gate!", "info", "🐾")  # window defaults 4.0
	eq(hud._toasts.size(), 1, "gate toast pushed")
	eq(float(hud._toasts[0]["ttl"]), 4.0, "gate toast keeps the default ttl")
	hud.update(2.0)
	hud.toast_gate("gate!", "info", "🐾")
	eq(hud._toasts.size(), 1, "re-fire inside the 4s window drops")
	hud.update(2.2)  # the first instance ages past ttl and drops
	eq(hud._toasts.size(), 0, "expired gate toast drops like any toast")
	hud.toast_gate("gate!", "info", "🐾")
	eq(hud._toasts.size(), 1, "after the window lapses the gate toast re-fires")
	eq(float(hud._toasts[0]["t"]), 0.0, "the re-fire is a fresh instance")
	# the plain toast path keeps the 1.5 s window
	hud.toast("plain", "info", "•")
	hud.update(1.6)
	hud.toast("plain", "info", "•")
	eq(hud._toasts.size(), 3, "plain toast still re-fires after 1.5 s (TS flood guard)")


# QC r7 batch1.1 — the r2 anchor (a live-toast age scan inside toast()) died
# with its toast: ttl-expire and the 6-cap pop_front both lost it, so a window
# > ttl re-fired every ~4.1 s. The anchor is now a timestamp dict outside the
# list, checked before the append. The two acceptance shapes from the r7
# synthesis, tick-ordered like the real frame (the stage fires the gate, THEN
# hud.update ages the list):
func test_gate_anchor_deadzone_15s_window10_max_two() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	var fires := 0
	for i in 900:  # a 15 s dead-zone hold, the condition re-fires every tick
		hud.toast_gate("idle!", "info", "🌿", 10.0)
		for t in hud._toasts:
			if String(t["text"]) == "idle!" and float(t["t"]) == 0.0:
				fires += 1  # a fresh instance — one count per append
				break
		hud.update(DT)
	eq(fires, 2, "15 s hold, window 10: exactly 2 emissions (t=0 + t=10), old bug gave 4")
	eq(hud._toasts.size(), 0, "the second emission expired at t=14 (hold ran to 15)")


func test_gate_anchor_pack_full_5_5s_window4_exactly_one() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	var fires := 0
	for i in 330:  # a 5.5 s pack-full hold, window 4, ttl 4
		hud.toast_gate("full!", "info", "🐾", 4.0)
		for t in hud._toasts:
			if String(t["text"]) == "full!" and float(t["t"]) == 0.0:
				fires += 1
				break
		hud.update(DT)
	eq(fires, 1, "5.5 s hold, window 4: exactly 1 (the t=4 re-fire lands while the t=0 toast is still on screen and folds into it)")


func test_gate_anchor_survives_pop_front() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.toast_gate("gate!", "info", "🐾", 10.0)
	for i in 8:
		hud.toast("noise%d" % i, "info", "•")
	eq(hud._toasts.size(), 6, "cap 6 shifted the gate toast out")
	var popped := true
	for t in hud._toasts:
		if String(t["text"]) == "gate!":
			popped = false
	ok(popped, "gate toast really left the list")
	hud.update(3.0)
	hud.toast_gate("gate!", "info", "🐾", 10.0)
	var refired := false
	for t in hud._toasts:
		if String(t["text"]) == "gate!":
			refired = true
	ok(not refired, "anchor survives the pop — no re-fire inside the window (old code re-fired here)")
	hud.update(7.2)  # clock 10.2 — window lapsed
	hud.toast_gate("gate!", "info", "🐾", 10.0)
	var back := false
	for t in hud._toasts:
		if String(t["text"]) == "gate!" and float(t["t"]) == 0.0:
			back = true
	ok(back, "after the window the gate fires again")


func test_toast_cap_six_shifts_oldest() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	for i in 7:
		hud.toast("t%d" % i, "info", "•")
	eq(hud._toasts.size(), 6, "cap 6 (TS shift)")
	eq(String(hud._toasts[0]["text"]), "t1", "oldest dropped")


func test_toast_world_card_stores_title_body() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.toast("composed line", "world", "🌊", 6.0, {"title": "A Title", "body": "A body"})
	eq(String(hud._toasts[0]["title"]), "A Title", "card title stored (Task 9 call sites pass tr'd pieces)")
	eq(String(hud._toasts[0]["body"]), "A body", "card body stored")
	eq(float(hud._toasts[0]["ttl"]), 6.0, "card ttl honored")


# ---- banner queue -----------------------------------------------------------

func test_banner_defaults_and_ttl_override() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.banner({"title": "☄ METEOR STRIKE"})
	eq(String(hud._cur_banner["title"]), "☄ METEOR STRIKE", "banner shows")
	eq(String(hud._cur_banner["sub"]), "", "missing subtitle reads empty")
	eq(String(hud._cur_banner["kind"]), "chaos", "default kind chaos")
	eq(float(hud._cur_banner["ttl"]), 3.4, "default ttl 3.4")
	hud.dismiss_banner()
	# the sim's warn shape: ttl 2.4 override + danger kind
	hud.banner({"title": "The water turns warm…", "kind": "danger", "ttl": 2.4})
	eq(String(hud._cur_banner["kind"]), "danger", "kind override")
	eq(float(hud._cur_banner["ttl"]), 2.4, "ttl override (chaos warn shape)")


func test_banner_queues_and_dedupes_titles() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.banner({"title": "A"})
	hud.banner({"title": "B"})   # cur A alive (ttl 3.4 > 0.5) → B queues
	eq(hud._banner_queue.size(), 1, "concurrent banner queues")
	hud.banner({"title": "A"})   # duplicate of the live banner → dropped
	eq(hud._banner_queue.size(), 1, "same-title as live banner dropped")
	hud.banner({"title": "B"})   # duplicate of the last queued → dropped
	eq(hud._banner_queue.size(), 1, "same-title as last queued dropped")
	hud.banner({"title": "C"})
	eq(hud._banner_queue.size(), 2, "distinct title queues")
	hud.update(3.5)              # A expires → B promotes
	eq(String(hud._cur_banner["title"]), "B", "queue promotes after expiry")
	eq(hud._banner_queue.size(), 1, "C still queued")


func test_banner_queue_cap_five() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.banner({"title": "live"})
	for i in 7:
		hud.banner({"title": "q%d" % i})
	eq(hud._banner_queue.size(), 5, "queue cap 5 — warnings never pile past it (TS shift)")
	eq(String(hud._banner_queue[0]["title"]), "q2", "oldest queued dropped")


func test_dismiss_banner_clears_live_and_queued() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.banner({"title": "A"})
	hud.banner({"title": "B"})
	hud.dismiss_banner()
	ok(hud._cur_banner == null, "live banner dropped")
	eq(hud._banner_queue.size(), 0, "queue emptied (stage switch clean slate)")


# ---- float_world ------------------------------------------------------------

func test_float_world_rise_and_expiry() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	hud.float_world(10.0, 20.0, "+5 DNA", "#c9a4ff", 13.0)
	eq(hud._floaters.size(), 1, "floater pushed")
	eq(float(hud._floaters[0]["vy"]), -34.0, "TS rise speed")
	eq(float(hud._floaters[0]["ttl"]), 1.1, "TS ttl")
	hud.update(0.5)
	approx(float(hud._floaters[0]["y"]), 20.0 - 17.0, "rises vy*dt in the first step", 1e-9)
	approx(float(hud._floaters[0]["vy"]), -34.0 * 0.92, "vy decays 0.92", 1e-9)
	hud.update(0.7)
	eq(hud._floaters.size(), 0, "ttl 1.1 expiry removes")


func test_float_world_cap_sixty() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	for i in 61:
		hud.float_world(0.0, 0.0, "f%d" % i)
	eq(hud._floaters.size(), 60, "cap 60 (TS shift)")


# ---- dna display + pulse ------------------------------------------------------

func test_dna_display_smoothing_toward_context() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	eq(float(g.context.dna), 40, "fresh context dna")
	# QC r6: the display starts AT the context total — a hud created on the
	# CONTINUE path (civ/space) used to lerp 0 → the saved total over ~1s,
	# the chip lying on the first frame (i18n-1 r6 caught 144 mid-lerp).
	approx(float(hud._dna_display), 40.0, "display inits synced to the context dna", 1e-9)
	# the damp pull still smooths later gains (TS hud.ts dnaDisplay lerp)
	g.context.add_dna(60)
	hud.update(DT)
	approx(float(hud._dna_display), 40.0 + 60.0 * (8.0 / 60.0), "one step of the damp pull", 1e-9)
	for i in 600:
		hud.update(DT)
	approx(float(hud._dna_display), 100.0, "converges on the context dna", 1e-6)


func test_dna_pulse_from_context_signal_and_decay() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	eq(float(hud._dna_pulse), 0.0, "pulse idle")
	g.context.add_dna(7)  # dna_gained fires → the hud's bus tap (TS EV.dna)
	eq(float(hud._dna_pulse), 1.0, "context dna event pulses")
	hud.update(0.2)
	approx(float(hud._dna_pulse), 1.0 - 0.2 * 3.0, "pulse decays 3/s", 1e-9)
	hud.update(1.0)
	eq(float(hud._dna_pulse), 0.0, "pulse floors at 0")


# ---- abilities ----------------------------------------------------------------

func test_abilities_payload_passthrough() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	var slots: Array = [
		{"key": "LMB", "icon": "👄", "cd": 0.0, "hint": "bite"},
		{"key": "1", "icon": "☠️", "cd": 0.5, "active": true},
	]
	hud.set_abilities(slots)
	eq(hud.abilities.size(), 2, "slots stored")
	eq(float(hud.abilities[1]["cd"]), 0.5, "cd fraction rides the payload (the stage computes TS:488-494)")
	eq(bool(hud.abilities[1]["active"]), true, "active flag rides")
	hud.update(DT)
	eq(float(hud.abilities[1]["cd"]), 0.5, "hud never mutates the payload")


# ---- pointer_down hit routing -------------------------------------------------

func test_pointer_down_default_rects_and_hooks() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	# TS initial rects sit at (0,0) 36x36 — a pre-first-draw click still routes
	eq(bool(hud.pointer_down(10.0, 10.0)), true, "default mute rect hit consumes")
	eq(int(g.mute_toggles), 1, "mute button toggles via game.toggle_mute")
	eq(bool(hud.pointer_down(-5.0, -5.0)), false, "outside → not consumed (game routes on)")


func test_pointer_down_drawn_button_rects() -> void:
	_en()
	var g: Variant = MockGame.new()
	var hud: Variant = _hud(g)
	# the draw pass re-arms the rects at the TS screen slots — simulate it
	hud._mute_rect = {"x": 980.0, "y": 14.0, "w": 30.0, "h": 30.0}
	hud._menu_rect = {"x": 942.0, "y": 14.0, "w": 30.0, "h": 30.0}
	eq(bool(hud.pointer_down(995.0, 29.0)), true, "mute rect hit")
	eq(int(g.mute_toggles), 1, "mute toggled")
	eq(bool(hud.pointer_down(957.0, 29.0)), true, "menu rect hit")
	eq(int(g.pause_opens), 1, "menu button opens pause via game.open_pause")
	eq(bool(hud.pointer_down(960.0, 60.0)), false, "between buttons → not consumed")


# ---- pause menu ----------------------------------------------------------------

var _g: Variant = null
var _rec := {"saves": 0, "closed": 0, "toasts": [], "gos": []}


func _act_close() -> void:
	_rec["closed"] = int(_rec["closed"]) + 1


## Odd calls succeed — exercises both toast arms (TS save-fail path).
func _act_save() -> bool:
	_rec["saves"] = int(_rec["saves"]) + 1
	return int(_rec["saves"]) % 2 == 1


func _act_mute() -> void:
	_g.toggle_mute()


func _act_toast(text: String, kind: String, icon: String) -> void:
	_rec["toasts"].append([text, kind, icon])


func _act_go(id: String, card: Variant) -> void:
	_rec["gos"].append([id, card])


func _wired_pause(g: Variant) -> Variant:
	# the seam the cell stage wires (Task 8) — recording hooks
	_g = g
	_rec = {"saves": 0, "closed": 0, "toasts": [], "gos": []}
	var p: Variant = PauseScript.new(g)
	p.actions = {
		"close_pause": _act_close,
		"save_all": _act_save,
		"toggle_mute": _act_mute,
		"go_to": _act_go,
		"toast": _act_toast,
	}
	return p


func _click(g: Variant, x: float, y: float) -> void:
	# real wrapper feed — a mouse press at (x, y) then pause.update consumes it
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(x, y)
	ev.global_position = Vector2(x, y)
	g.input.handle_event(ev)


func test_pause_open_builds_main_items() -> void:
	_en()
	var g: Variant = MockGame.new()
	var p: Variant = _wired_pause(g)
	p.open()
	eq(p.items.size(), 8, "main view: resume/save/sound/language/help/world/bestiary/quit")
	eq(String(p.items[0]["label"]), "▶  Resume", "labels are the TS keys (EN passthrough)")
	eq(String(p.items[1]["label"]), "💾  Save now", "save label")
	eq(String(p.items[6]["label"]), "📖  Bestiary", "bestiary label")
	eq(String(p.items[7]["label"]), "⌂  Quit to title", "quit label")


func test_pause_resume_and_save_toasts() -> void:
	_en()
	var g: Variant = MockGame.new()
	var p: Variant = _wired_pause(g)
	p.open()
	_click(g, 512.0, float(p.items[0]["y"]) + 23.0)  # Resume (vw/2 = 512)
	p.update(DT)
	eq(int(_rec["closed"]), 1, "resume routes the close_pause hook")
	eq(int(_rec["saves"]), 0, "resume does not save")
	p.open()
	_click(g, 512.0, float(p.items[1]["y"]) + 23.0)  # Save now
	p.update(DT)
	eq(int(_rec["saves"]), 1, "save-now routes the save_all hook")
	eq(_rec["toasts"].size(), 1, "save feedback toast")
	eq(String(_rec["toasts"][0][0]), "Game saved", "success toast key")
	eq(String(_rec["toasts"][0][1]), "good", "success kind")
	p.open()
	_click(g, 512.0, float(p.items[1]["y"]) + 23.0)
	p.update(DT)  # second save fails (even call) → the failure arm
	eq(int(_rec["saves"]), 2, "second save attempted")
	eq(String(_rec["toasts"][0][0]), "Game saved", "first toast unchanged")
	eq(_rec["toasts"].size(), 2, "second toast recorded")
	eq(String(_rec["toasts"][1][0]), "Save failed — could not write save file", "failure toast key")
	eq(String(_rec["toasts"][1][1]), "bad", "failure kind")


func test_pause_mute_item_flips_and_relabels() -> void:
	_en()
	var g: Variant = MockGame.new()
	var p: Variant = _wired_pause(g)
	p.open()
	eq(String(p.items[2]["label"]), "🔊  Sound: on", "unmuted label (TS game.muted read)")
	_click(g, 512.0, float(p.items[2]["y"]) + 23.0)
	p.update(DT)
	eq(g.muted, true, "toggle_mute hook fired")
	eq(String(p.items[2]["label"]), "🔇  Sound: off", "rebuild relabels from muted")


func test_pause_language_item_flips_i18n() -> void:
	_en()
	var g: Variant = MockGame.new()
	var p: Variant = _wired_pause(g)
	p.open()
	eq(String(p.items[3]["label"]).begins_with("🌐  LANGUAGE: English"), true, "EN label")
	_click(g, 512.0, float(p.items[3]["y"]) + 23.0)
	p.update(DT)
	eq(String(g.i18n.get_lang()), "vi", "language toggles through i18n (Task 2 API)")
	eq(String(p.items[3]["label"]).begins_with("🌐  NGÔN NGỮ: Tiếng Việt"), true, "VI label")
	g.i18n.set_lang("en")
	TranslationServer.set_locale("en")


func test_pause_help_view_round_trip() -> void:
	_en()
	var g: Variant = MockGame.new()
	var p: Variant = _wired_pause(g)
	p.open()
	_click(g, 512.0, float(p.items[4]["y"]) + 23.0)  # How to play
	p.update(DT)
	eq(p.items.size(), 1, "help view shows only Back")
	eq(String(p.items[0]["label"]), "◀  Back", "back label")
	_click(g, 512.0, float(p.items[0]["y"]) + 23.0)
	p.update(DT)
	eq(p.items.size(), 8, "back returns to the main view")


func test_pause_world_view_round_trip() -> void:
	_en()
	var g: Variant = MockGame.new()
	var p: Variant = _wired_pause(g)
	p.open()
	_click(g, 512.0, float(p.items[5]["y"]) + 23.0)  # World Genome
	p.update(DT)
	eq(p.items.size(), 1, "world view shows only Back")
	eq(String(p.items[0]["label"]), "◀  Back", "back label")
	_click(g, 512.0, float(p.items[0]["y"]) + 23.0)
	p.update(DT)
	eq(p.items.size(), 8, "back returns to the main view")


func test_pause_quit_chain() -> void:
	_en()
	var g: Variant = MockGame.new()
	var p: Variant = _wired_pause(g)
	p.open()
	_click(g, 512.0, float(p.items[7]["y"]) + 23.0)  # Quit to title
	p.update(DT)
	eq(int(_rec["saves"]), 1, "quit saves first (TS order)")
	eq(int(_rec["closed"]), 1, "quit closes the pause")
	eq(_rec["gos"].size(), 1, "quit navigates")
	eq(String(_rec["gos"][0][0]), "menu", "quit goes to the title")
	eq(String(_rec["gos"][0][1].get("title", "")), "PRIMORDIA", "quit card title")
	eq(String(_rec["gos"][0][1].get("sub", "")), "the soup remembers you", "quit card sub")


func test_pause_click_miss_does_nothing() -> void:
	_en()
	var g: Variant = MockGame.new()
	var p: Variant = _wired_pause(g)
	p.open()
	_click(g, 20.0, 20.0)
	p.update(DT)
	eq(int(_rec["closed"]), 0, "a miss consumes nothing")
	eq(bool(g.input.was_clicked()), true, "the click stays live for the stage layers (TS no-take path)")
