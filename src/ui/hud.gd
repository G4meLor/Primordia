## Shared HUD layer: DNA counter, chaos/karma meters, ability slots, toasts,
## event banners and world-anchored floating text. Port of Spore src/ui/hud.ts
## (frozen). Task 8 ruling: RefCounted (the TS class shape — no Control node);
## the owning scene draws it via draw() as the LAST screen-space layer (TS
## game.ts:548 renders the hud after the stage + transition veil — natively
## the cell stage owns that slot, see the cell_stage.gd draw-order note).
##
## Translation contract: DISPLAY call sites wrap their literals in tr_key (the
## T2 audit scans src/ui for the `hud["toast"].call(...)` shapes); banner
## title/sub stay raw EN keys inside the payload dicts and translate HERE at
## render time (T5 ruling). The context signal toasts (discover/extinct) carry
## pre-translated text from the sim hooks, matching the sim's own tr() calls.
class_name HudUi
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")
const PMathScript := preload("res://src/core/math.gd")

## TS TOAST_COLORS (hud.ts:26-33) — kind → CSS color.
const TOAST_COLORS := {
	"info": "#9fd8ff", "good": "#8fe39a", "bad": "#ff9a8a",
	"chaos": "#e2a4ff", "reward": "#ffe08a", "world": "#9fe8d8",
}
## TS banner kind colors [stroke, bg] (hud.ts:314-319).
const BANNER_COLORS := {
	"chaos": ["#ff5a8a", "#2a0a14"], "stage": ["#7fd4ff", "#0a1428"],
	"danger": ["#ff9a5a", "#28140a"], "reward": ["#ffe08a", "#28200a"],
}

## R3 progress arc — the journey order (menu is not a journey node).
const STAGE_ORDER := ["cell", "creature", "tribe", "civ", "space"]
## Next-milestone tooltip per stage — raw EN keys, translated at draw (the
## translation contract); vi.csv rows appended native-side (the r2 B3
## precedent). Gates mirror the sims: legs→shore (cell_sim), brain ×3 +
## pack 2 (creature_sim tribeReady), Great Totem (tribe_sim victory),
## unify the planet (civ OBJECTIVE_LINE), seed 3 worlds (space OBJECTIVE_LINE).
const HINT_KEYS := {
	"cell": "next: buy a LEG → shore",
	"creature": "next: brain ×3 + pack 2 → tribe",
	"tribe": "next: raise the Great Totem → civ",
	"civ": "next: unify the planet → space",
	"space": "next: seed 3 worlds → Chaos Core",
}
## Arc node labels — EN keys translated at draw like every hud string.
const ARC_LABELS := {
	"cell": "Cell", "creature": "Creature", "tribe": "Tribe",
	"civ": "Civ", "space": "Space",
}

## AbilitySlot dicts {key, icon, cd, active, hint} — the stage recomputes the
## cd fractions every update (CellStage.ts:488-494); the hud never mutates.
var abilities: Array = []
## TS showObjective: string | null — a raw EN key, translated at draw. R2
## chip contract: ANY (re)assignment arms a PLAIN line — the counter pair
## resets here, so the cell/creature direct sets and the 1-arg objective
## hook can never leak a previous stage's chip; the sims re-arm the live
## pair per tick through the hud_objective_counter hook.
var show_objective: Variant = null:
	set(v):
		show_objective = v
		show_objective_text = "" if v == null else String(v)
		show_objective_cur = -1
		show_objective_max = 0
## R2 chip: typed mirror of show_objective — what the objective slot renders
## ("" while hidden). The draw block reads this, never the Variant.
var show_objective_text: String = ""
## R2 chip: the live cur/max pair behind the objective line — cur<0 or
## max<=0 renders plain text (the sims fire the pair only while it tracks
## something real; see HudUi.objective_display).
var show_objective_cur := -1
var show_objective_max := 0
## Extra bottom inset so toasts clear stage-specific bottom-left UI (tribe
## build buttons, civ portrait). Stages set it in on_enter; cell leaves it 0.
var toast_inset := 0.0


## TS game.ts:213 — the game resets the inset to 0 on every stage switch
## ("stages with bottom-left UI re-arm their own inset": tribe re-arms 190 in
## on_enter, TS:154). Rides the hud dict as a key so the game-level reset
## reaches whichever stage instance owns the live dict.
func set_toast_inset(px: float) -> void:
	toast_inset = px

var _floaters: Array = []
var _toasts: Array = []
# QC r7 batch1.1 — gate-toast anchor OUTSIDE the live list. The r2 dedupe scan
# only saw toasts still in _toasts, so ttl-expire (4 s) and the 6-cap pop_front
# both destroyed the anchor and any window > ttl re-fired every ~4.1 s (the
# tribe gatherer dead-zone, window 10, measured 4 emissions in a 15 s hold
# against its promised 2). Two timestamps, both outside the list:
#   _gate_last_shown — hud-clock of the last actual panel (the fold band's
#     anchor), and _gate_arm — hud-clock of the last rate event (panel or
#     fold). The clock advances in update() so a hud that stops ticking
#     freezes its gate windows exactly like its toast ttls. Both dicts hold
#     only the handful of gate literals the sims fire — no growth path.
var _gate_last_shown: Dictionary = {}
var _gate_arm: Dictionary = {}
var _gate_clock := 0.0
# fold band edge: gate ttl (4.0) + a 0.1 s guard — a re-show landing inside
# the previous panel's decay+guard folds instead of stacking (fp-robust: the
# guard dwarfs the ulp jitter between the hud clock and the toast age)
const GATE_FOLD_GRACE := 4.1
var _cur_banner: Variant = null     # Banner dict | null
var _banner_queue: Array = []
var _dna_display := 0.0
var _dna_pulse := 0.0
# TS initial rects sit at (0,0) 36x36 — a pre-first-draw click still routes.
var _mute_rect := {"x": 0.0, "y": 0.0, "w": 36.0, "h": 36.0}
var _menu_rect := {"x": 0.0, "y": 0.0, "w": 36.0, "h": 36.0}

var _game: Variant = null


func _init(game_v: Variant) -> void:
	_game = game_v
	# TS constructor bus taps (hud.ts:51-60): context toasts + the dna pulse.
	# Banners ride the sim's hud_banner hook → game.hud["banner"] — the context
	# has no banner signal (M1 ported only EV.toast/EV.dna as signals).
	_game.context.toast.connect(_on_ctx_toast)
	_game.context.dna_gained.connect(_on_ctx_dna)
	# QC r6: the chip starts AT the context total. A hud created on the
	# CONTINUE path (civ/space — the stage's _install_overlays runs after
	# the slot load) used to lerp 0 → the saved total for ~1s, the chip
	# visibly lying on the first frame. TS keeps ONE hud per session whose
	# display has already converged by stage-entry time — this matches that.
	_dna_display = float(_game.context.dna)


func _on_ctx_toast(text: String, kind: String, icon: String) -> void:
	# QC r3 stale-toasts (synthesis 4A): every stage keeps a persistent hud_inst
	# and _init taps context.toast — a sim toast used to fan out into ALL five
	# huds, and a hidden hud never decays its ttl (only the live stage's hud
	# gets hud["update"], game.gd _do_update), so frozen toasts revived when
	# that stage became current again. Land the toast in the LIVE stage's hud
	# only (the menu has no hud_inst — nothing lands there, TS-true).
	if _game.current == null or _game.current.get("hud_inst") != self:
		return
	toast(text, kind if kind != "" else "info", icon if icon != "" else "•")


func _on_ctx_dna(_amount: int, _reason: Variant, _x: Variant, _y: Variant) -> void:
	# TS: this.dnaPulse = 1 (the amount>0 re-set is a no-op there too)
	_dna_pulse = 1.0


func set_abilities(a: Array) -> void:
	abilities = a


func toast(text: String, kind := "info", icon := "•", ttl := 4.0, card: Variant = null,
		dedupe := 1.5) -> void:
	# drop identical repeats within the dedupe window (rate-limit floods; the
	# TS window is 1.5 s — hud.ts:73). TS compares the TRANSLATED text (toast
	# translated internally); natively the call sites translate BEFORE the
	# call (audit shape), so the stored text is the identity — same dedup
	# behavior, one translation instead of two. toast_gate passes a longer
	# window for gate toasts (QC round-2 B3).
	for x in _toasts:
		if String(x["text"]) == text and float(x["t"]) < dedupe:
			return
	var t := {"text": text, "kind": kind, "icon": icon, "ttl": ttl, "t": 0.0,
			"title": null, "body": null}
	if card != null:
		t["title"] = card.get("title", "")
		t["body"] = card.get("body", "")
	_toasts.append(t)
	if _toasts.size() > 6:
		_toasts.pop_front()


## Gate-toast entry (QC round-2 B3): a gate condition persists while its key
## is held (F near a too-big target, a full pack), re-firing the gate toast
## every tick — the plain 1.5 s flood guard let the same message re-show 2-3x
## per hold. The longer window re-shows it at most once per `window` seconds
## while the condition lasts (squeak-ignore, pack-full, gatherer dead-zone).
func toast_gate(text: String, kind := "info", icon := "•", window := 4.0) -> void:
	# Rate check against the arm (last panel OR last fold) — the anchor lives
	# OUTSIDE the toast list, so ttl-expire and the 6-cap pop_front both leave
	# it intact (the r2 in-list anchor died with its toast and re-fired every
	# ~4.1 s on any window > ttl). Then the boundary fold: when the re-show
	# lands inside the previous panel's decay + grace (only possible when
	# window <= ttl — the pack-full gate, 4/4), it consumes the window WITHOUT
	# stacking a second identical panel — the toast age and the hud clock
	# accumulate the same dt through different float sums, so a strict-window
	# re-show races the ttl removal and duplicated half the time in-engine.
	# A 5.5 s pack-full hold therefore shows exactly 1 (next panel at arm 8),
	# while a sparse attempt past the decay (the r2 pin: a single attempt at
	# 4.2 against a panel gone at 4.0) still displays.
	var arm: Variant = _gate_arm.get(text)
	if arm != null and _gate_clock - float(arm) < window:
		return
	var shown: Variant = _gate_last_shown.get(text)
	if shown != null and _gate_clock - float(shown) < GATE_FOLD_GRACE:
		_gate_arm[text] = _gate_clock
		return
	_gate_arm[text] = _gate_clock
	_gate_last_shown[text] = _gate_clock
	toast(text, kind, icon, 4.0, null, window)


## Public API for big center banners (chaos events, stage cards).
func banner(m: Dictionary) -> void:
	show_banner(m)


## Drop live + queued banners (stage switches start a clean slate).
func dismiss_banner() -> void:
	_cur_banner = null
	_banner_queue.clear()


## QC r3 stale-toasts: clear this hud's toast list and hand the live entries
## back — switch_stage migrates them onto the hud of the stage it enters (TS
## keeps ONE hud across stages, so a toast fired just before a switch still
## shows in the next stage within its ttl). A toast left behind here would
## freeze — a hidden hud never decays — and revive when this stage returned.
func expire_toasts() -> Array:
	var out := _toasts
	_toasts = []
	return out


## Adopt a migrated toast list (switch_stage pairs this with expire_toasts on
## the leaving hud). Wholesale replace: under the _on_ctx_toast guard the
## entering hud holds nothing of its own at switch time.
func adopt_toasts(list: Array) -> void:
	_toasts = list


func show_banner(m: Dictionary) -> void:
	var b := {"title": String(m.get("title", "")), "sub": String(m.get("subtitle", "")),
			"kind": String(m.get("kind", "chaos")), "ttl": float(m.get("ttl", 3.4)), "t": 0.0}
	# one at a time on screen — concurrent banners queue instead of erasing
	# each other (raid no longer wipes the chaos warning it triggered)
	if _cur_banner != null and float(_cur_banner["ttl"]) > 0.5:
		# TS reads bannerQueue[len-1] → undefined on an empty queue; back()
		# errors on empty, so guard it (same null the branch below handles)
		var last: Variant = _banner_queue.back() if not _banner_queue.is_empty() else null
		if (last == null or String(last["title"]) != b["title"]) \
				and String(_cur_banner["title"]) != b["title"]:
			_banner_queue.append(b)
			if _banner_queue.size() > 5:
				_banner_queue.pop_front()  # don't drop warnings in event storms
		return
	_cur_banner = b


func float_world(x: float, y: float, text: String, color := "#fff", size := 13.0) -> void:
	_floaters.append({"x": x, "y": y, "vy": -34.0, "text": text, "color": color,
			"ttl": 1.1, "size": size})
	if _floaters.size() > 60:
		_floaters.pop_front()


func update(dt: float) -> void:
	_gate_clock += dt
	var i := _floaters.size() - 1
	while i >= 0:
		var f: Dictionary = _floaters[i]
		f["ttl"] = float(f["ttl"]) - dt
		f["y"] = float(f["y"]) + float(f["vy"]) * dt
		f["vy"] = float(f["vy"]) * 0.92
		if float(f["ttl"]) <= 0.0:
			_floaters.remove_at(i)
		i -= 1
	i = _toasts.size() - 1
	while i >= 0:
		var t: Dictionary = _toasts[i]
		t["ttl"] = float(t["ttl"]) - dt
		t["t"] = float(t["t"]) + dt
		if float(t["ttl"]) <= 0.0:
			_toasts.remove_at(i)
		i -= 1
	if _cur_banner != null:
		_cur_banner["ttl"] = float(_cur_banner["ttl"]) - dt
		_cur_banner["t"] = float(_cur_banner["t"]) + dt
		if float(_cur_banner["ttl"]) <= 0.0:
			_cur_banner = _banner_queue.pop_front() if not _banner_queue.is_empty() else null
	_dna_pulse = maxf(0.0, _dna_pulse - dt * 3.0)
	var target := float(_game.context.dna)
	_dna_display += (target - _dna_display) * minf(1.0, dt * 8.0)
	if absf(target - _dna_display) < 0.6:
		_dna_display = target


## Returns true if the click was consumed by a HUD button. game.ts:277-281
## routes clicks hud-first — the game.gd call site lands with Task 9.
func pointer_down(mx: float, my: float) -> bool:
	if _hit(mx, my, _mute_rect):
		_game.toggle_mute()
		return true
	if _hit(mx, my, _menu_rect):
		_game.open_pause()
		return true
	return false


func _hit(mx: float, my: float, r: Dictionary) -> bool:
	return mx >= float(r["x"]) and mx <= float(r["x"]) + float(r["w"]) \
			and my >= float(r["y"]) and my <= float(r["y"]) + float(r["h"])


## TS render() — the full screen-space HUD. The caller draws at identity.
func draw(ci: CanvasItem, vw: float, vh: float) -> void:
	var c: Variant = _game.context
	var cam: Variant = _game.cam

	# The caller cancels the live camera transform on its draw calls — but a
	# CanvasItem's draw transform is WRITE-ONLY, and the DNA pulse block below
	# clobbered it (and reset to identity), throwing the whole hud into raw
	# camera space. Under the creature stage's enabled Camera2D that pushed
	# every hud element off-screen (the cell stage's identity canvas masked
	# it). Compose with the cancellation instead.
	var inv: Transform2D = _game.get_viewport().canvas_transform.affine_inverse()

	# ---- DNA (top-left) -----------------------------------------------------
	var pulse := 1.0 + _dna_pulse * 0.18
	ci.draw_set_transform_matrix(inv * Transform2D(0.0, Vector2(18.0, 18.0)) \
			.scaled_local(Vector2(pulse, pulse)))
	RendererScript.panel(ci, 0.0, 0.0, 150.0, 40.0, {
		"fill": RendererScript.css_color("rgba(6,10,24,0.8)"),
		"stroke": RendererScript.css_color("rgba(120,200,255,0.35)"),
		"shadow": RendererScript.css_color("rgba(60,140,255,0.25)"),
	})
	# helix icon: two sine strands
	var strand := RendererScript.css_color("#7fd4ff")
	for h in 2:
		var pts := PackedVector2Array()
		for s in 9:
			var yy := 8.0 + float(s) * 3.0
			var xx := 14.0 + sin(float(s) * 0.9 + float(h) * PI) * 5.0
			pts.append(Vector2(xx, yy))
		ci.draw_polyline(pts, strand, 2.0, true)
	RendererScript.outlined_text(ci, "%s DNA" % PMathScript.format_num(_dna_display),
			34.0, 20.0, {"size": 16.0, "fill": Color("#bfe6ff"), "align": "left"})
	ci.draw_set_transform_matrix(inv)

	# ---- R3 progress arc (absorbs the old dim stage-name text: the current
	# node's label carries the name, bright) ------------------------------------
	_draw_arc(ci, String(c.stage))

	# ---- chaos + karma (top-right, left of buttons) ---------------------------
	var meters_x := vw - 190.0  # clear of the ❚❚/🔊 buttons (vw-82..vw-52)
	RendererScript.panel(ci, meters_x, 52.0, 86.0, 18.0, {
		"fill": RendererScript.css_color("rgba(6,10,24,0.8)"),
		"stroke": RendererScript.css_color("rgba(255,120,160,0.3)"),
	})
	var cw := 82.0 * clampf(float(c.chaos), 0.0, 1.0)
	if cw > 1.0:
		RendererScript.gradient_rounded_rect(ci, Rect2(meters_x + 2.0, 54.0, cw, 14.0), 6.0,
				Color("#5a3fa8"), Color("#ff5a7a"))
	RendererScript.outlined_text(ci, _game.i18n.tr_key("CHAOS"), meters_x + 43.0, 60.0,
			{"size": 9.0, "fill": RendererScript.css_color("rgba(255,190,210,0.9)")})

	# karma orb (TS diagonal gradient → the horizontal 2-stop rounded fill;
	# r=10 on a 20x20 rect IS the circle — presence-level, renderer notes)
	var kx := meters_x + 43.0
	var ky := 30.0
	RendererScript.panel(ci, meters_x, 12.0, 86.0, 32.0, {
		"fill": RendererScript.css_color("rgba(6,10,24,0.8)"),
		"stroke": RendererScript.css_color("rgba(255,255,255,0.12)"),
	})
	var k0 := Color("#ffe9a8") if float(c.karma) >= 0.0 else Color("#ff9a7a")
	var k1 := Color("#7fd4ff") if float(c.karma) >= 0.0 else Color("#7a2f4f")
	RendererScript.gradient_rounded_rect(ci, Rect2(kx - 10.0, ky - 10.0, 20.0, 20.0), 10.0, k0, k1)
	# tiny face: happy/skull-ish tilt by karma
	var face := RendererScript.css_color("rgba(0,0,0,0.7)")
	ci.draw_arc(Vector2(kx - 3.4, ky - 2.0), 1.6, 0.0, TAU, 12, face, 1.4, true)
	ci.draw_arc(Vector2(kx + 3.4, ky - 2.0), 1.6, 0.0, TAU, 12, face, 1.4, true)
	if float(c.karma) >= 0.0:
		ci.draw_arc(Vector2(kx, ky + 1.5), 5.0, 0.15, PI - 0.15, 12, face, 1.4, true)
	else:
		# TS arc(PI+0.3 → -0.3) wraps clockwise: normalize the end to TAU-0.3
		ci.draw_arc(Vector2(kx, ky + 6.0), 5.0, PI + 0.3, TAU - 0.3, 12, face, 1.4, true)

	# ---- buttons ---------------------------------------------------------------
	_mute_rect = {"x": vw - 44.0, "y": 14.0, "w": 30.0, "h": 30.0}
	_menu_rect = {"x": vw - 82.0, "y": 14.0, "w": 30.0, "h": 30.0}
	_button(ci, _menu_rect, "❚❚")
	_button(ci, _mute_rect, "🔇" if bool(_game.muted) else "🔊")
	if _hit(float(_game.input.mx), float(_game.input.my), _menu_rect) \
			or _hit(float(_game.input.mx), float(_game.input.my), _mute_rect):
		_game.hover_cursor()

	# ---- objective --------------------------------------------------------------
	if show_objective != null:
		# R2 chip: the prose translates, then the live pair appends OUTSIDE
		# tr_key (numbers are not prose — see objective_display)
		RendererScript.outlined_text(ci, objective_render_string(),
				vw / 2.0, 26.0, {"size": 13.0, "fill": Color("#ffe9b0"), "alpha": 0.9,
						"maxWidth": vw - 380.0})

	# ---- ability bar ---------------------------------------------------------------
	var n := abilities.size()
	if n > 0:
		var slot := 52.0
		var gap := 8.0
		var total := float(n) * slot + float(n - 1) * gap
		var ax := vw / 2.0 - total / 2.0
		var ay := vh - 66.0
		for ab in abilities:
			var active := bool(ab.get("active", false))
			RendererScript.panel(ci, ax, ay, slot, slot, {
				"fill": RendererScript.css_color("rgba(80,140,255,0.35)") if active
						else RendererScript.css_color("rgba(6,10,24,0.8)"),
				"stroke": RendererScript.css_color("rgba(150,200,255,0.7)") if active
						else RendererScript.css_color("rgba(255,255,255,0.12)"),
			})
			RendererScript.outlined_text(ci, String(ab["icon"]), ax + slot / 2.0, ay + slot / 2.0 - 4.0,
					{"size": 20.0, "fill": Color("#eaf4ff")})
			var cd := float(ab.get("cd", 0.0))
			if cd > 0.0:
				# veil drains top-anchored as it readies
				RendererScript.gradient_rounded_rect(ci,
						Rect2(ax + 2.0, ay + 2.0, slot - 4.0, (slot - 4.0) * cd), 8.0,
						RendererScript.css_color("rgba(0,0,10,0.65)"),
						RendererScript.css_color("rgba(0,0,10,0.65)"))
				RendererScript.outlined_text(ci,
						"" if cd >= 0.99 else String.num(ceilf(cd * 10.0) / 10.0, 1),
						ax + slot / 2.0, ay + slot / 2.0, {"size": 11.0, "fill": Color("#ffd7a8")})
			RendererScript.outlined_text(ci, String(ab["key"]), ax + slot / 2.0, ay + slot - 8.0,
					{"size": 9.0, "fill": RendererScript.css_color("rgba(200,220,255,0.7)")})
			ax += slot + gap

	# ---- toasts ---------------------------------------------------------------------
	var ty := vh - 30.0 - toast_inset
	var tidx := _toasts.size() - 1
	while tidx >= 0:
		var t2: Dictionary = _toasts[tidx]
		var a := minf(1.0, float(t2["t"]) * 4.0) * minf(1.0, float(t2["ttl"]) * 2.0)
		if String(t2["kind"]) == "world" and t2["body"] != null:
			# world reveal card: taller than a toast, accent border, big sigil,
			# bold title over a shrink-to-fit body line
			var cw2 := minf(324.0, vw - 32.0)
			var y0 := ty - 44.0
			RendererScript.panel(ci, 16.0, y0, cw2, 58.0, _faded({
				"fill": RendererScript.css_color("rgba(6,14,26,0.9)"),
				"stroke": RendererScript.css_color(String(TOAST_COLORS.get("world", "#9fe8d8"))),
				"lw": 2.0,
				"shadow": RendererScript.css_color("rgba(60,180,160,0.25)"),
			}, a))
			RendererScript.outlined_text(ci, String(t2["icon"]), 44.0, y0 + 20.0,
					{"size": 20.0, "fill": Color("#eaf8ff"), "alpha": a})
			var card_title: Variant = t2["title"]
			if card_title == null:
				card_title = t2["text"]
			RendererScript.outlined_text(ci, String(card_title), 62.0, y0 + 19.0,
					{"size": 14.0, "fill": RendererScript.css_color(String(TOAST_COLORS.get("world", "#9fe8d8"))),
							"align": "left", "maxWidth": cw2 - 62.0, "alpha": a, "weight": "700"})
			RendererScript.outlined_text(ci, String(t2["body"]), 62.0, y0 + 42.0,
					{"size": 12.0, "fill": RendererScript.css_color("rgba(230,246,240,0.92)"),
							"align": "left", "maxWidth": minf(260.0, cw2 - 62.0), "alpha": a})
			ty -= 64.0
		else:
			var label := "%s %s" % [String(t2["icon"]), String(t2["text"])]
			# TS hud.ts:300 measures the TEXT only (the icon overlaps the
			# panel's left padding) — not the combined label
			var tw := ThemeDB.fallback_font.get_string_size(String(t2["text"]),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
			# clamp clear of the centered bottom docks (ability bar etc.)
			var pw := minf(maxf(170.0, tw + 60.0), vw / 2.0 - 176.0)
			RendererScript.panel(ci, 16.0, ty - 14.0, pw, 26.0, _faded({
				"fill": RendererScript.css_color("rgba(6,10,24,0.85)"),
				"stroke": RendererScript.hsl(0.0, 0.0, 0.5, 0.2),
			}, a))
			RendererScript.outlined_text(ci, label, 30.0, ty,
					{"size": 12.0, "fill": _toast_color(String(t2["kind"])), "align": "left",
							"maxWidth": pw - 28.0, "alpha": a})
			ty -= 32.0
		tidx -= 1

	# ---- banner ------------------------------------------------------------------------
	if _cur_banner != null:
		var b: Dictionary = _cur_banner
		var in_t := minf(1.0, float(b["t"]) * 3.0)
		var out_t := minf(1.0, float(b["ttl"]) * 2.0)
		var ba := in_t * out_t
		var pair: Array = BANNER_COLORS.get(String(b["kind"]), BANNER_COLORS["chaos"])
		var col := RendererScript.css_color(String(pair[0]))
		var bg := RendererScript.css_color(String(pair[1]))
		var bw := minf(560.0, vw * 0.8)
		RendererScript.panel(ci, vw / 2.0 - bw / 2.0, 70.0, bw, 74.0, _faded({
			"fill": bg, "stroke": col, "lw": 2.0, "shadow": col,
		}, ba))
		# banner title/sub stay raw EN keys in the payload — translated HERE (T5)
		RendererScript.outlined_text(ci, _game.i18n.tr_key(String(b["title"])), vw / 2.0, 98.0,
				{"size": 22.0, "fill": col, "maxWidth": bw - 24.0, "alpha": ba, "weight": "700"})
		if String(b["sub"]) != "":
			RendererScript.outlined_text(ci, _game.i18n.tr_key(String(b["sub"])), vw / 2.0, 124.0,
					{"size": 13.0, "fill": RendererScript.css_color("rgba(255,255,255,0.85)"),
							"maxWidth": bw - 24.0, "alpha": ba})

	# ---- floaters (world → screen) ---------------------------------------------------
	for f2 in _floaters:
		var sx := (float(f2["x"]) - float(cam.x)) * float(cam.zoom) + vw / 2.0 + float(cam.shake_x)
		var sy := (float(f2["y"]) - float(cam.y)) * float(cam.zoom) + vh / 2.0 + float(cam.shake_y)
		if sx < -50.0 or sx > vw + 50.0 or sy < -50.0 or sy > vh + 50.0:
			continue
		RendererScript.outlined_text(ci, String(f2["text"]), sx, sy,
				{"size": float(f2["size"]) * float(cam.zoom),
						"fill": RendererScript.css_color(String(f2["color"])),
						"alpha": minf(1.0, float(f2["ttl"]) * 2.0)})


## R2 chip — the pure display join: "T · 34/100" while a counter is armed
## (cur >= 0 and max > 0), else the line as-is. The brief-pinned no-counter
## edges: cur<0 or max<=0 → plain text. The "·" is typography, not prose —
## it stays out of vi.csv; the fallback font's digits share one advance
## (tabular), so the live counter doesn't jitter as it ticks.
static func objective_display(text: String, cur: int, max: int) -> String:
	if cur < 0 or max <= 0:
		return text
	return "%s · %d/%d" % [text, cur, max]


## The exact string the objective slot renders: the prose translated, then
## the live pair appended OUTSIDE tr_key. Extracted from draw() for the
## headless suite (the arc_states/arc_next_hint seam — draw targets a live
## canvas, which only the xvfb scene harness exercises).
func objective_render_string() -> String:
	return objective_display(_game.i18n.tr_key(show_objective_text),
			show_objective_cur, show_objective_max)


## R3 arc state per journey node for `stage_id`: "done" before the current
## stage, "current" on it (renders bright — the accent node), "dim" after.
## menu (and any unknown id) dims every node — the menu owns no hud instance,
## so this is only ever the transition-frame safe default.
static func arc_states(stage_id: String) -> Array:
	var idx := STAGE_ORDER.find(stage_id)
	var out: Array = []
	for i in range(STAGE_ORDER.size()):
		out.append("current" if i == idx else ("done" if i < idx else "dim"))
	return out


## Next-milestone EN key for the tooltip under the arc (translated at draw);
## "" for menu/unknown — the draw skips the line. Space, the road's end,
## hints its own endgame milestone instead of a next stage.
static func arc_next_hint(stage_id: String) -> String:
	return String(HINT_KEYS.get(stage_id, ""))


## The arc itself: 5 numbered dots joined by a line (traveled path lit),
## labels under the dots, next-milestone line under that. Plain CanvasItem
## drawing on the caller's item — draw_line/draw_arc/disc/outlined_text only,
## no sub-RIDs (the suite RID ceiling is at datum). Draws under the `inv`
## screen-space transform the DNA block left set.
func _draw_arc(ci: CanvasItem, stage_id: String) -> void:
	var states := arc_states(stage_id)
	var x0 := 28.0
	var dx := 44.0
	var y := 74.0
	for i in range(states.size() - 1):
		# a segment glows once its left node is done — the traveled path
		var lit := String(states[i]) == "done"
		ci.draw_line(Vector2(x0 + i * dx, y), Vector2(x0 + (i + 1) * dx, y),
				RendererScript.css_color("rgba(127,212,255,0.55)") if lit
				else RendererScript.css_color("rgba(255,255,255,0.16)"), 2.0)
	for i in range(states.size()):
		var cx := x0 + i * dx
		var s := String(states[i])
		var num := str(i + 1)
		if s == "current":
			RendererScript.disc(ci, cx, y, 7.0, RendererScript.css_color("#7fd4ff"))
			ci.draw_arc(Vector2(cx, y), 9.5, 0.0, TAU, 24,
					RendererScript.css_color("rgba(191,230,255,0.9)"), 1.5, true)
			RendererScript.outlined_text(ci, num, cx, y,
					{"size": 9.0, "fill": RendererScript.css_color("rgba(6,14,30,0.9)")})
		elif s == "done":
			RendererScript.disc(ci, cx, y, 7.0, RendererScript.css_color("rgba(150,200,255,0.38)"))
			RendererScript.outlined_text(ci, num, cx, y,
					{"size": 9.0, "fill": RendererScript.css_color("rgba(20,34,60,0.95)")})
		else:
			ci.draw_arc(Vector2(cx, y), 7.0, 0.0, TAU, 20,
					RendererScript.css_color("rgba(255,255,255,0.30)"), 1.5, true)
			RendererScript.outlined_text(ci, num, cx, y,
					{"size": 9.0, "fill": RendererScript.css_color("rgba(160,200,255,0.5)")})
		var label: String = _game.i18n.tr_key(String(ARC_LABELS[String(STAGE_ORDER[i])]))
		RendererScript.outlined_text(ci, label, cx, y + 15.0,
				{"size": 9.0, "fill": RendererScript.css_color("#bfe6ff") if s == "current"
						else RendererScript.css_color("rgba(160,200,255,0.6)")})
	var hint := arc_next_hint(stage_id)
	if hint != "":
		RendererScript.outlined_text(ci, _game.i18n.tr_key(hint), x0 - 4.0, y + 31.0,
				{"size": 10.0, "align": "left",
						"fill": RendererScript.css_color("rgba(160,200,255,0.75)")})
	# R7 — the creature's display name rides next to the arc (small, dim). A
	# player string, not a key — drawn verbatim at draw time like the arc's
	# own labels (the discover() precedent: names interpolate outside tr).
	RendererScript.outlined_text(ci, _game.context.get_display_name(),
			x0 + (states.size() - 1) * dx + 32.0, y,
			{"size": 11.0, "align": "left",
					"fill": RendererScript.css_color("rgba(191,230,255,0.8)")})


func _button(ci: CanvasItem, r: Dictionary, glyph: String) -> void:
	RendererScript.panel(ci, float(r["x"]), float(r["y"]), float(r["w"]), float(r["h"]), {
		"fill": RendererScript.css_color("rgba(6,10,24,0.8)"),
		"stroke": RendererScript.css_color("rgba(255,255,255,0.14)"),
	})
	RendererScript.outlined_text(ci, glyph, float(r["x"]) + float(r["w"]) / 2.0,
			float(r["y"]) + float(r["h"]) / 2.0, {"size": 15.0, "fill": Color("#cfe6ff")})


func _toast_color(kind: String) -> Color:
	return RendererScript.css_color(String(TOAST_COLORS.get(kind, TOAST_COLORS["info"])))


## ctx.globalAlpha equivalent — scale every Color alpha in a panel style dict.
func _faded(style: Dictionary, a: float) -> Dictionary:
	var out := {}
	for k in style:
		var v: Variant = style[k]
		out[k] = Color(v, v.a * a) if v is Color else v
	return out
