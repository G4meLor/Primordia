## Space play-bot — M6 task 7. Rides bot_civ's FULL arc (composition: ONE
## BotCiv instance → its bot_tribe → its bot_creature → ONE LCG driver across
## the whole run — the M5 shape, bot_civ.gd:134-137) through arrival →
## founding → tribe → the civ unification victory whose go_to('space') LANDS
## the REGISTERED SpaceStage (38bf9fb — the victory leg is bot_civ's, NEVER
## re-implemented here), then walks the space arc tick-per-frame on the REAL
## input pipeline (Global Constraint 8):
##   the FLY leg (real held W/A/S/D octant steering toward the arc's own
##   nearest-living planet — the sim's thrust field + the engine trail read
##   back from the stage fx pool, the ship-hull patch captured mid-flight:
##   numeric pixel asserts only, images never viewed) → the ABDUCT leg (a
##   real R tap at range — the beam latched on the sim's beamT, the cargo
##   slot fills, the +10 first catch proven by the abductCount ledger's
##   first row + the '+10' toast tail + the dna credit) → the SEED leg (the
##   drawn panel's SEED button clicked through the render-synced
##   panel_rects — the dispatch end-to-end: the colony born, the SEEDED
##   banner, the 20-DNA spend) → the SCAN leg (the panel SCAN click: +15
##   survey + the planet scanned) → two more R catches to cargo 2 → the
##   FAST-FORWARD leg (a real held F — ffHold latched, the hud's F ability
##   slot reads active, colony generations climb, the ecos churn, the ff
##   tint captured with a numeric patch gate) → the SPLICE leg (a real G tap
##   at cargo 2 — the child slot, the −15 spend, the '(spliced)' name) →
##   the SIEGE (wait for the pinned seed's chaos deck to deal pirates, then
##   click-to-shoot them dead — 5 real clicks per kill at 34 dmg vs 140 hp —
##   each kill +30 DNA; the 40 s ttl lift is the fallback exit, whichever
##   the seed deals) → the FINALE: debug_seed_colonies (the documented
##   cheat) + a real held F to 3 thriving → 'THE CHAOS CORE AWAKENS' → the
##   core fly (real thrust to the finale's own coordinates, the bearing
##   objective latched) → d < 60 → endingDone + the win flush read back from
##   the persisted spaceWorld flag → THE CHAOS CORE ACCEPTS YOU (the title
##   patch gated at the alpha-1 frame) → a real click dismisses → the
##   sandbox returns (the ship-visible seam true again, the calm objective
##   line).
##
## TS AUTHORITY: no space bot test exists in the frozen repo (Spore/tests/
## holds bot/bot-arc/bot-creature only). The cheat set mirrors the M4/M5
## family: direct start_new_game (bot.test.ts:62, ridden in the creature
## legs), debug_seed_colonies through its documented sim mutator
## (space_sim.gd:882-898 — the sim header's debug-seam surface: debug_state
## read + debug_seed_colonies; the header names it "the task-6 bot's colony
## leg"), everything else real input.
##
## TICK SHAPE: the scene calls space_tick once per _process frame AFTER the
## arrival/founding/tribe/civ phases (delegated to the bot_civ module — the
## victory→space landing rides it; NEVER re-implemented here). The capture
## sub-states ride IN the legs (render in tick T, the SceneTree flushes the
## draw between ticks, the image grabbed in tick T+1 — the bot_civ arm→shot
## shape); the probes are computed from the sim state AT THE RENDER TICK.
## Every watch is a plain field read: sim fields, the stage's render-synced
## _panel_rects rows, the stage fx pool's particle dicts, hud_inst._toasts/
## _cur_banner/_banner_queue/abilities/show_objective (the stage-NAMED hud —
## the d7a5cb8 lesson: the post-landing reads go through game.stages['space'],
## never game.current), game.transition, game.dna_window (the per-add DNA
## ledger the world-story beats ride — spend_dna is silent, so the leg cost
## asserts reconcile the window's new rows back). eco.living() reads are
## pure getters over the planet ecosystems (the hud-list precedent — no
## state mutation). Locale note: the run locale is EN (the i18n default —
## no settings.cfg overrides it in the gate environment), so the matched
## tr() fragments ('+10', '+15', 'the core sleeps') resolve to identity.
##
## BOT LAW AUDIT: every input rides the driver (Input.parse_input_event +
## flush) — W/A/S/D press+release pairs (the octant steerer), R taps ×3,
## F holds ×2 (press → held across frames → release), the G tap, the panel
## SEED/SCAN clicks, the pirate kill clicks, the ending dismiss click.
## Direct sim calls:
## debug_seed_colonies ONLY (the documented cheat above — the finale's 3
## colonies). Everything else is field reads: sim fields, the stage's
## _panel_rects, the fx pool dicts, the hud lists/abilities/objective,
## game.transition, game.dna_window, and the DRIVER's own world_to_screen
## seam (pure cam geometry — the bot_civ map_to_screen precedent). The
## scene asserts driver.sane_violations empty (the sweeps ride the 600-beats
## here AND in the reused legs) and driver.delivery_ok true.
##
## CHAOS NOTE: the pinned seed's chaos behavior is whatever it is (the M4
## bot lesson) — the siege leg exits on SIM-FIELD conditions (pirates seen →
## pirates gone, kill-or-ttl indeterminate), the ff legs exit on the
## generations/thriving fields so a fastened eco only moves the exit frame,
## and the pirate-click aims ride the live cam state (no shake in the fight:
## pirate bites fire no cam_shake). Determinism carries replay: the ×2 gate
## compares the quantized SPACE end-state fingerprints (game.stages['space']
## .sim — NEVER game.current.sim, which aliases) plus a per-600-frame sweep
## trace through the space legs; all leg exits are deterministic frames at
## the pinned seed.
extends RefCounted

const BotCivScript := preload("res://tests/bots/bot_civ.gd")

const DT := 1.0 / 60.0
const FLY_BUDGET := 60 * 40        # the WASD flight to the first living planet (~520-1400 px at ~381 px/s) + the capture
const STATION_BUDGET := 60 * 25    # the bang-bang park inside the panel ring
const BEAM_BUDGET := 60 * 8        # the 1.4 s beam + the catch + drift margin
const RECT_TICKS := 90             # a panel-click retry budget in scene ticks (the tribe precedent)
const CLICK_BUDGET := 60 * 8       # one panel click's effect window past the retries
const FF_FRAMES := 60 * 14         # the held-F duration (14 sim-seconds of 26x churn)
const FF_CAPTURE_AT := 60          # the tint capture arms 1 s into the hold
const SIEGE_WAIT_BUDGET := 60 * 200  # the deck's ~24-34 s event gaps + cooldowns
const SIEGE_FIGHT_BUDGET := 60 * 70  # the ttl is 40 s; 5 clicks kill at 34 dmg vs 140 hp
const FIN_FF_BUDGET := 60 * 45     # pop 1 → 20 under ff ≈ 10 s + event drift
const CORE_FLY_BUDGET := 60 * 40   # ~1400-2500 px at ~381 px/s + the hole dodge
const ENDING_BUDGET := 60 * 8      # the veil fade-in to alpha 1 (2 s) + the click + margin
## The engine-trail color string the sim spawns with (space_sim.gd:612 —
## _hsl(200, 1, 0.7)); read back from the stage fx pool's particle dicts.
const TRAIL_COLOR := "hsl(200 100% 70% / 1.00)"

var bc: Variant = null        # bot_civ — the arrival/founding/tribe/civ legs ride it
var driver: Variant = null    # bc.driver — ONE LCG stream across the whole run
## Per-600-frame quantized sweep trace through the SPACE legs (determinism
## triage; the hard gate is the end fingerprint).
var trace: Array = []

# latched observations (the scene asserts them at the arc's end)
var thrust_seen := false       # sim.thrust > 0 under the held WASD
var trail_seen := false        # engine-color particles live in the stage fx pool
var capture_ok := false        # the mid-flight ship-hull patch asserts passed
var beam_seen := false         # the abduction beam latched (beamT > 1.0)
var first_catch_pay10 := false # the '+10' first-catch toast tail
var ledger_first := false      # the abductCount ledger's first catch row == 1
var seeded_banner := false     # the '<planet> SEEDED' center banner
var colony_born := false       # the seed leg's planet grew a colony
var scan_pay15 := false        # the +15 survey credit latched
var scanned_seen := false      # the scanned flag flipped on the target
var ff_hold_seen := false      # ffHold > 0 under the held F
var ff_ability_active := false # the hud's F ability slot read active
var generations_climbed := false
var eco_churned := false
var ff_tint_ok := false        # the ff-tint patch gate passed
var splice_child := false      # the '(spliced)' child in the cargo
var siege_seen := false        # pirates on the scope
var siege_kills := 0           # click-to-shoot kills (+30 DNA each)
var siege_lift := false        # pirates gone again (kill-or-ttl, whichever)
var awakens_seen := false      # 'THE CHAOS CORE AWAKENS' banner
var pulls_seen := false        # the persistent bearing objective
var ending_fired := false      # d < 60 → endingDone
var win_flush_ok := false      # the persisted spaceWorld flag carries endingDone
var ending_seen := false       # the ACCEPTS YOU title patch gated at alpha 1
var dismissed_seen := false    # the real click dismissed
var calm_objective := false    # 'the core sleeps — the sandbox is yours'
var ship_returned := false     # the ship-visible seam true again

# state machine
var _leg := "fly"
var _frames := 0                  # leg-local budget counter (ticks; 1 sim frame each)
var _sp_f := 0                    # global space-frame counter (sweep trace phase)
var _target := -1                 # the fly leg's living-planet index (the arc's station)
var _held := {}                   # the currently-held WASD codes (the steerer's state)
var _cap := "none"                # the 2-tick capture sub-state: none|grab|done
var _probe := {}                  # the flight geometry recorded at the render tick
var _gen0 := -1.0                 # the ff leg's generations baseline
var _pop0 := -1.0                 # the ff leg's living-pop baseline (the churn watch)
var _pop_species0 := -1           # the ff leg's species-count baseline
var _dna_leg := 0                 # the leg-start dna (the cost asserts)
var _win0 := 0                    # the leg-start dna_window length (the adds accounting)
var _kill_dna := 0.0              # the siege fight's dna baseline (the +30 per kill)
var _ending_t_click := -1.0       # the endingT snapshot at the dismiss click


# ---- shared ---------------------------------------------------------------------

func _init() -> void:
	bc = BotCivScript.new()
	driver = bc.driver


func step(game: Variant, n: int) -> void:
	game.step_for_testing(n, DT)


func space_sim(game: Variant) -> Variant:
	# the d7a5cb8 lesson: NAME the stage — game.current.sim aliases whatever
	# stage is live (the civ sim in the early legs); the space legs read the
	# stage-named sim exclusively
	return game.stages["space"].sim


## Quantized space-state snapshot (the determinism gate + sweep rows): the
## ship, the machine fields, the whole system (angle/scanned/colony/eco per
## planet), the cargo, the ending state and the context's dna/karma/chaos —
## the stage-NAMED sim exclusively.
func space_fingerprint(game: Variant) -> Dictionary:
	var sim: Variant = game.stages["space"].sim
	var c: Variant = game.context
	var names := ""
	for it in sim.cargo:
		names += String(it["name"]) + "|"
	var out := {
		"time": floori(float(sim.time) * 100.0),
		"sx": floori(float(sim.sx) * 100.0),
		"sy": floori(float(sim.sy) * 100.0),
		"svx": floori(float(sim.svx) * 100.0),
		"svy": floori(float(sim.svy) * 100.0),
		"shp": floori(float(sim.shp) * 100.0),
		"shpMax": floori(float(sim.shpMax) * 100.0),
		"shipAngle": floori(fmod(float(sim.shipAngle) + PI, TAU) * 1000.0),
		"ffHold": floori(float(sim.ffHold) * 100.0),
		"beamT": floori(maxf(float(sim.beamT), 0.0) * 100.0),
		"cargo": sim.cargo.size(),
		"cargoNames": names,
		"abducts": sim.abductCount.size(),
		"resurvey": floori(float(sim.resurveyCd) * 100.0),
		"persistT": floori(float(sim.persistT) * 100.0),
		"deckSeed": int(sim.deckSeed),
		"pirates": sim.pirates.size(),
		"holes": sim.blackHoles.size(),
		"endingDone": bool(sim.endingDone),
		"endingDismissed": bool(sim.endingDismissed),
		"endingT": floori(float(sim.endingT) * 100.0),
		"dismissT": floori(float(sim.dismissT) * 100.0),
		"dna": int(c.dna),
		"karma": floori(float(c.karma) * 1000.0),
		"chaos": floori(float(c.chaos) * 1000.0),
		"extinct": int(c.world_stats["extinctions"]),
	}
	for i in sim.planets.size():
		var p: Dictionary = sim.planets[i]
		out["p%d_ang" % i] = floori(fmod(float(p["angle"]), TAU) * 1000.0)
		out["p%d_scan" % i] = bool(p["scanned"])
		var col: Variant = p["colony"]
		if col != null:
			out["p%d_pop" % i] = floori(float(col["pop"]) * 100.0)
			out["p%d_gen" % i] = floori(float(col["generations"]) * 100.0)
		else:
			out["p%d_pop" % i] = -1
			out["p%d_gen" % i] = -1
		if p["eco"] != null:
			var live: Array = p["eco"].living()
			out["p%d_live" % i] = live.size()
			var pop := 0.0
			for sp in live:
				pop += float(sp["pop"])
			out["p%d_epop" % i] = floori(pop * 100.0)
		else:
			out["p%d_live" % i] = -1
			out["p%d_epop" % i] = -1
	return out


## The per-frame watch every space leg rides: latches the toast/banner/
## objective observations (a field-read sweep — no sim calls, no input).
func _watch(game: Variant) -> void:
	var hud: Variant = game.stages["space"].hud_inst
	if hud == null:
		return
	for t in hud._toasts:
		var s := String(t["text"])
		if s.contains(" +10"):
			first_catch_pay10 = true
		if s.contains("+15"):
			scan_pay15 = true
	if hud._cur_banner != null:
		_latch_banner(String(hud._cur_banner["title"]))
	for b in hud._banner_queue:
		_latch_banner(String(b["title"]))
	var obj: Variant = hud.show_objective
	if obj != null:
		var o := String(obj)
		if o.contains("THE CHAOS CORE PULLS"):
			pulls_seen = true
		if o.contains("the core sleeps"):
			calm_objective = true


func _latch_banner(title: String) -> void:
	if title.contains(" SEEDED"):
		seeded_banner = true
	if title.contains("THE CHAOS CORE AWAKENS"):
		awakens_seen = true


## One stepped space frame inside a wait leg: the sweep trace rides the GLOBAL
## space-frame counter so rows align across passes; the driver's assert_sane
## rides the same 600-beats (it accumulates driver.sane_violations).
func _sp_wait_step(game: Variant) -> void:
	_sp_f += 1
	step(game, 1)
	_watch(game)
	if _sp_f % 600 == 0:
		trace.append({"f": _sp_f, "fp": space_fingerprint(game)})
		driver.assert_sane(game)


## A real tap + the delivery proof (the bot_civ wrapper convention).
func _tap(game: Variant, keycode: int, code: String) -> void:
	driver.tap_key(keycode)
	driver.delivery_ok = driver.delivery_ok and game.input.key_pressed(code)


## The octant steerer: hold the real W/A/S/D keys matching `desired`
## (re-evaluated every tick — the deadzone releases all keys). Deterministic:
## the press/release pairs are exact functions of the sim fields read.
func _steer(game: Variant, desired: Vector2) -> void:
	var want := {
		"KeyW": desired.y < -20.0,
		"KeyS": desired.y > 20.0,
		"KeyA": desired.x < -20.0,
		"KeyD": desired.x > 20.0,
	}
	var keys := [["KeyW", KEY_W], ["KeyA", KEY_A], ["KeyS", KEY_S], ["KeyD", KEY_D]]
	for pair in keys:
		var code: String = pair[0]
		var kc: int = pair[1]
		if bool(want[code]) and not _held.has(code):
			driver.press_key(kc)
			_held[code] = true
			driver.delivery_ok = driver.delivery_ok and game.input.key(code)
		elif not bool(want[code]) and _held.has(code):
			driver.release_key(kc)
			_held.erase(code)
			driver.delivery_ok = driver.delivery_ok and not game.input.key(code)


func _release_all(game: Variant) -> void:
	_steer(game, Vector2.ZERO)


## The hazard-aware desired vector: away from the sun's danger band (r 130 +
## 60) whenever inside 280 of it, plus a black-hole dodge within 500 (the
## pull radius 600 minus steering margin). Pure field math.
func _hazard_desired(sim: Variant, want: Vector2) -> Vector2:
	var pos := Vector2(float(sim.sx), float(sim.sy))
	var sun_d := pos.length()
	if sun_d < 280.0 and sun_d > 0.001:
		want = pos / sun_d * 300.0 + want * 0.3
	for bh in sim.blackHoles:
		var off := pos - Vector2(float(bh["x"]), float(bh["y"]))
		var bd := off.length()
		if bd < 500.0 and bd > 0.001:
			want = want + off / bd * (500.0 - bd) * 2.0
	return want


## The bang-bang station vector for the target planet: brake against the
## velocity once the predicted stop point (d + v²/2a at accel 420,
## space_sim.gd:344) would overshoot the r+90 ring, settle (brake) inside
## r+110, else thrust toward the planet. Converges to a parked ship inside
## the panel ring (r+130).
func _station_desired(sim: Variant, p: Dictionary) -> Vector2:
	var to_p := Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy))
	var d := to_p.length()
	var v := Vector2(float(sim.svx), float(sim.svy))
	var vlen := v.length()
	if d < float(p["r"]) + 110.0:
		return -v
	if vlen > 60.0 and d + vlen * vlen / 840.0 > float(p["r"]) + 90.0:
		return -v
	return to_p


func _parked(sim: Variant, p: Dictionary) -> bool:
	var d: float = Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length()
	var v := Vector2(float(sim.svx), float(sim.svy))
	return d < float(p["r"]) + 115.0 and v.length() < 40.0


## THIS bot's own nearest-living-planet scan — the fly/station target (the
## sim's nearest_planet shape computed independently from field reads, the
## bot_civ cross-check convention; eco != null excludes the barren rocks so
## the abduct leg has life to beam).
func nearest_living_index(sim: Variant) -> int:
	var best := -1
	var best_d := INF
	for i in sim.planets.size():
		var p: Dictionary = sim.planets[i]
		if p["eco"] == null:
			continue
		var d: float = Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length()
		if d < best_d:
			best_d = d
			best = i
	return best


## Grab the last completed viewport pass (the render tick queued it; the
## game node is in the tree under xvfb — the bot_civ pattern).
func _grab(game: Variant) -> Image:
	return game.get_viewport().get_texture().get_image()


func _px(img: Image, x: float, y: float) -> Vector3:
	var c := img.get_pixel(clampi(int(x), 0, img.get_width() - 1),
			clampi(int(y), 0, img.get_height() - 1))
	return Vector3(roundf(c.r * 255.0), roundf(c.g * 255.0), roundf(c.b * 255.0))


## The checker's patch_mean (visual_check_civ_scene.py:47) — a (2r+1)² mean.
func _patch_mean(img: Image, cx: float, cy: float, r: int) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for yy in range(int(cy) - r, int(cy) + r + 1):
		for xx in range(int(cx) - r, int(cx) + r + 1):
			if xx >= 0 and xx < img.get_width() and yy >= 0 and yy < img.get_height():
				acc += _px(img, xx, yy)
				n += 1
	return acc / float(maxi(n, 1))


## The checker's purple-label predicate (visual_check_space_scene.py's ff and
## ending sections — live-validated against this renderer): the #e2a4ff glyph
## pixels of the ff tint label and the ACCEPTS YOU title.
func _count_purple(img: Image, box: Array) -> int:
	var n := 0
	for yy in range(int(box[1]), int(box[3]) + 1):
		for xx in range(int(box[0]), int(box[2]) + 1):
			if xx < 0 or xx >= img.get_width() or yy < 0 or yy >= img.get_height():
				continue
			var c := img.get_pixel(xx, yy)
			var p := Vector3(roundf(c.r * 255.0), roundf(c.g * 255.0), roundf(c.b * 255.0))
			if p.x >= 180.0 and p.z >= 230.0 and p.y >= 120.0 and p.y <= 210.0:
				n += 1
	return n


## Live engine-trail particles in the stage fx pool (a plain field sweep over
## the pool dicts — the ring-buffer rows carry the sim's spawn color).
func _trail_count(stage: Variant) -> int:
	var n := 0
	for p in stage.fx.pool:
		if bool(p["active"]) and String(p["color"]) == TRAIL_COLOR:
			n += 1
	return n


## The leg-start DNA bookkeeping: dna + the dna_window length (the adds
## ledger — the world-story beats ride it; spend_dna is silent). The cost
## asserts reconcile: delta == spend + window adds.
func _dna_mark(game: Variant) -> void:
	_dna_leg = int(game.context.dna)
	_win0 = game.dna_window.size()


func _window_adds(game: Variant) -> float:
	var sum := 0.0
	for i in range(_win0, game.dna_window.size()):
		sum += float(game.dna_window[i]["amount"])
	return sum


## One real panel click on the row with `action` (the render-synced rows —
## game._do_render runs _sync_panel_view synchronously). Returns "" and
## leaves the click delivered, or the failure reason.
func _panel_click(game: Variant, action: String) -> String:
	game._do_render(0.0)  # _sync_panel_view runs synchronously in render
	var rows: Array = game.stages["space"]._panel_rects
	for b in rows:
		if String(b["action"]) == action and bool(b["enabled"]):
			var r: Dictionary = b["r"]
			var center := Vector2(float(r["x"]) + float(r["w"]) / 2.0,
					float(r["y"]) + float(r["h"]) / 2.0)
			driver.mouse_down(center)
			driver.delivery_ok = driver.delivery_ok and game.input.is_down()
			step(game, 1)
			driver.mouse_up()
			_watch(game)
			return ""
	return "no enabled %s row in the panel rows (%s)" % [action, str(_panel_rows(game))]


# ---- the space arc (one tick per scene frame, post bot_civ's OK) --------------------
## Returns "OK" when the full space arc completed (the finale flown, the
## ending dismissed, the sandbox handed back), "" while still walking, else
## the failure reason. _frames is the leg-local tick counter, incremented
## once per tick at the top.
func space_tick(game: Variant) -> String:
	_frames += 1
	var sim: Variant = space_sim(game)
	match _leg:
		"fly":
			var fail := _fly_tick(game, sim)
			if fail != "":
				return fail
		"abduct1":
			# the REAL R tap at range — the beam (beamT 1.4) then the catch:
			# the cargo slot fills, the +10 first catch (the ledger's first
			# row + the toast tail + the dna credit)
			var p: Dictionary = sim.planets[_target]
			if _frames == 1 and not _parked(sim, p):
				_leg = "station1"
				_frames = 0
				return ""
			if _frames == 1:
				_tap(game, KEY_R, "KeyR")
			_sp_wait_step(game)
			beam_seen = beam_seen or float(sim.beamT) > 1.0
			if sim.cargo.size() >= 1:
				if not first_catch_pay10:
					return "abduct1: the catch landed without the '+10' toast tail (%s)" % str(_toasts(game))
				var found := false
				for k in sim.abductCount:
					if float(sim.abductCount[k]) == 1.0:
						found = true
				if not found:
					return "abduct1: the abductCount ledger has no first-catch row (%s)" % str(sim.abductCount)
				ledger_first = true
				if int(game.context.dna) < _dna_leg + 10:
					return "abduct1: the +10 credit never landed (dna %d → %d)" % [
							_dna_leg, int(game.context.dna)]
				_frames = 0
				_dna_mark(game)
				_leg = "seed_click"
			elif _frames > BEAM_BUDGET:
				return "abduct1: no catch in %d frames (beamT %s, cargo %d, toasts %s)" % [
						BEAM_BUDGET, str(sim.beamT), sim.cargo.size(), str(_toasts(game))]
		"station1":
			var fs := _station_tick(game, sim, "abduct1")
			if fs != "":
				return fs
		"seed_click":
			# the drawn panel's SEED button — the render-synced panel_rects
			# dispatch end-to-end (a real mouse click on the row rect): the
			# colony born, the SEEDED banner, the 20-DNA spend. The click
			# retries while the colony is absent (a landed seed is guarded by
			# the colony check itself — the next click only fires on a miss).
			var p2: Dictionary = sim.planets[_target]
			if not _parked(sim, p2):
				_leg = "station2"
				_frames = 0
				return ""
			if p2["colony"] == null:
				if _frames > RECT_TICKS:
					return "seed_click: no SEED dispatch in %d frames (rows %s, toasts %s)" % [
							RECT_TICKS, str(_panel_rows(game)), str(_toasts(game))]
				var fail2 := _panel_click(game, "seed")
				if fail2 != "":
					return "seed_click: " + fail2
			_sp_wait_step(game)
			if p2["colony"] != null:
				colony_born = true
				if not seeded_banner:
					return "seed_click: the colony is born but the SEEDED banner never fired (%s)" % str(_banners(game))
				if int(game.context.dna) != _dna_leg - 20 + int(_window_adds(game)):
					return "seed_click: the 20-DNA spend did not reconcile (dna %d → %d, adds %s)" % [
							_dna_leg, int(game.context.dna), str(_window_adds(game))]
				if not sim.cargo.is_empty():
					return "seed_click: the cargo specimen was not consumed (%d left)" % sim.cargo.size()
				_gen0 = float(p2["colony"]["generations"])
				_frames = 0
				_dna_mark(game)
				_leg = "scan_click"
			elif _frames > RECT_TICKS + CLICK_BUDGET:
				return "seed_click: the SEED click did not seed (colony %s, toasts %s)" % [
						str(p2["colony"]), str(_toasts(game))]
		"station2":
			var fs2 := _station_tick(game, sim, "seed_click")
			if fs2 != "":
				return fs2
		"scan_click":
			# the panel SCAN click — the +15 survey pay + the scanned flag
			var p3: Dictionary = sim.planets[_target]
			if not _parked(sim, p3):
				_leg = "station3"
				_frames = 0
				return ""
			if not bool(p3["scanned"]):
				if _frames > RECT_TICKS:
					return "scan_click: no SCAN dispatch in %d frames (rows %s, toasts %s)" % [
							RECT_TICKS, str(_panel_rows(game)), str(_toasts(game))]
				var fail3 := _panel_click(game, "scan")
				if fail3 != "":
					return "scan_click: " + fail3
			_sp_wait_step(game)
			if bool(p3["scanned"]):
				scanned_seen = true
				if not scan_pay15:
					return "scan_click: the scan landed without the '+15' toast (%s)" % str(_toasts(game))
				if int(game.context.dna) < _dna_leg + 15:
					return "scan_click: the +15 survey credit never landed (dna %d → %d)" % [
							_dna_leg, int(game.context.dna)]
				_frames = 0
				_leg = "abduct2"
			elif _frames > RECT_TICKS + CLICK_BUDGET:
				return "scan_click: the SCAN click did not scan (scanned %s, toasts %s)" % [
						str(p3["scanned"]), str(_toasts(game))]
		"station3":
			var fs3 := _station_tick(game, sim, "scan_click")
			if fs3 != "":
				return fs3
		"abduct2":
			var fail4 := _catch_leg(game, sim, "station4", "abduct2")
			if fail4 != "":
				return fail4
		"station4":
			var fs4 := _station_tick(game, sim, "abduct2")
			if fs4 != "":
				return fs4
		"abduct3":
			var fail5 := _catch_leg(game, sim, "station5", "abduct3")
			if fail5 != "":
				return fail5
		"station5":
			var fs5 := _station_tick(game, sim, "abduct3")
			if fs5 != "":
				return fs5
		"ff_hold":
			# a real held F: ffHold latches, the hud's F ability slot reads
			# active, the colony generations climb, the ecos churn (pops move
			# under the 26x tick), the ff tint captured with a patch gate
			if _frames == 1:
				_pop0 = _living_pop(sim)
				_pop_species0 = _living_species(sim)
				_cap = "none"  # the fly leg's capture left the sub-state done
				driver.press_key(KEY_F)
				driver.delivery_ok = driver.delivery_ok and game.input.key("KeyF")
			_sp_wait_step(game)
			ff_hold_seen = ff_hold_seen or float(sim.ffHold) > 0.0
			ff_ability_active = ff_ability_active or _ff_ability_active(game)
			if _cap == "none" and ff_hold_seen and _frames == FF_CAPTURE_AT:
				game._do_render(0.0)
				_cap = "grab"
				return ""
			elif _cap == "grab":
				var img := _grab(game)
				if img == null:
					return "ff_hold: the viewport returned no image"
				# the tint label '⏩ EVOLUTION ACCELERATING' — the checker's
				# live-validated purple-count over its own label box
				# (test_space_scene._ff_probes: [vw/2±130, 150..172]; want ≥ 8)
				var n := _count_purple(img, [game.vw / 2.0 - 130.0, 150.0,
						game.vw / 2.0 + 130.0, 172.0])
				if n < 8:
					return "ff_hold: the ff tint label never rendered (%d purple px)" % n
				# QC r3: ensure-dir before each save — a clean HOME has no
				# capture dir (only the test scene wrapper pre-created it)
				DirAccess.make_dir_recursive_absolute("user://visual_capture_space_bot")
				var err2 := img.save_png("user://visual_capture_space_bot/bot_space_ff.png")
				if err2 != OK:
					return "ff_hold: cannot save the ff capture (%s)" % str(err2)
				ff_tint_ok = true
				_cap = "done"
			if _cap == "done" and _frames >= FF_FRAMES:
				var pc: Dictionary = sim.planets[_target]
				if pc["colony"] == null:
					return "ff_hold: the target colony vanished"
				var gens: float = float(pc["colony"]["generations"])
				if gens < _gen0 + 5.0:
					return "ff_hold: the colony generations never climbed (%s → %s)" % [
							str(_gen0), str(gens)]
				generations_climbed = true
				if _living_pop(sim) == _pop0 and _living_species(sim) == _pop_species0:
					return "ff_hold: the ecos never churned (pop %s species %d static)" % [
							str(_pop0), _pop_species0]
				eco_churned = true
				driver.release_key(KEY_F)
				driver.delivery_ok = driver.delivery_ok and not game.input.key("KeyF")
				_frames = 0
				_dna_mark(game)
				_leg = "splice"
			elif _frames > FF_FRAMES + 60 * 10 and _cap != "done":
				return "ff_hold: the tint capture never completed (%d frames)" % _frames
		"splice":
			# a real G tap at cargo 2 — the child slot: 2 cargo merge to the
			# '(spliced)' child, the −15 spend
			if _frames == 1:
				if sim.cargo.size() < 2:
					return "splice: the cargo gate is not met (%d)" % sim.cargo.size()
				_tap(game, KEY_G, "KeyG")
			_sp_wait_step(game)
			if sim.cargo.size() == 1:
				if not String(sim.cargo[0]["name"]).contains(" (spliced)"):
					return "splice: the child slot does not carry the spliced name (%s)" % [
							str(sim.cargo[0]["name"])]
				splice_child = true
				if int(game.context.dna) != _dna_leg - 15 + int(_window_adds(game)):
					return "splice: the 15-DNA spend did not reconcile (dna %d → %d, adds %s)" % [
							_dna_leg, int(game.context.dna), str(_window_adds(game))]
				_frames = 0
				_leg = "siege_wait"
			elif _frames > CLICK_BUDGET:
				return "splice: the G tap did not merge (cargo %d, toasts %s)" % [
						sim.cargo.size(), str(_toasts(game))]
		"siege_wait":
			# the pinned seed's chaos deck deals what it deals — wait for
			# pirates on the scope (the event gaps ride ~24-34 s beats)
			_sp_wait_step(game)
			if sim.pirates.size() > 0:
				siege_seen = true
				_kill_dna = float(game.context.dna)
				_frames = 0
				_leg = "siege_fight"
			elif _frames > SIEGE_WAIT_BUDGET:
				return "siege_wait: the deck never dealt a siege in %d frames" % SIEGE_WAIT_BUDGET
		"siege_fight":
			# click-to-shoot: each real click on a pirate's screen position
			# (the live cam state — the driver's world_to_screen seam) takes
			# 34 hp off its 140; the 5th click kills (+30 DNA). The exit is
			# the scope clearing — the kill path or the 40 s ttl lift,
			# whichever the seed deals.
			_sp_wait_step(game)
			if sim.pirates.is_empty():
				siege_lift = true
				_frames = 0
				_leg = "finale_seed"
			else:
				var pir: Dictionary = sim.pirates[0]
				var aim: Vector2 = driver.world_to_screen(game, float(pir["x"]), float(pir["y"]))
				driver.mouse_down(aim)
				driver.delivery_ok = driver.delivery_ok and game.input.is_down()
				step(game, 1)
				driver.mouse_up()
				_watch(game)
				if float(game.context.dna) >= _kill_dna + 30.0:
					siege_kills += 1
					_kill_dna = float(game.context.dna)
				if _frames > SIEGE_FIGHT_BUDGET:
					return "siege_fight: the siege never lifted in %d frames (%d pirates, %d kills)" % [
							SIEGE_FIGHT_BUDGET, sim.pirates.size(), siege_kills]
		"finale_seed":
			# the documented cheat: debug_seed_colonies (the sim header's
			# debug-seam surface) — the first three non-barren uncolonized
			# planets in ORDER get colonies (pinned as coded)
			sim.debug_seed_colonies()
			if _colonies_of(sim) < 3:
				return "finale_seed: the debug seed left only %d colonies" % _colonies_of(sim)
			_frames = 0
			_leg = "finale_ff"
		"finale_ff":
			# a real held F to 3 thriving — the logistic colony growth under
			# the 26x tick (~10 s from pop 1); the AWAKENS banner latches
			if _frames == 1:
				driver.press_key(KEY_F)
				driver.delivery_ok = driver.delivery_ok and game.input.key("KeyF")
			_sp_wait_step(game)
			ff_hold_seen = ff_hold_seen or float(sim.ffHold) > 0.0
			if sim.finale != null and _thriving_of(sim) >= 3:
				driver.release_key(KEY_F)
				driver.delivery_ok = driver.delivery_ok and not game.input.key("KeyF")
				if not awakens_seen:
					return "finale_ff: 3 thriving + the finale but no AWAKENS banner (%s)" % str(_banners(game))
				_frames = 0
				_leg = "core_fly"
			elif _frames > FIN_FF_BUDGET:
				return "finale_ff: never 3 thriving in %d frames (%d colonies, thriving %d)" % [
						FIN_FF_BUDGET, _colonies_of(sim), _thriving_of(sim)]
		"core_fly":
			# real thrust to the core's own coordinates — the persistent
			# bearing objective latches, d < 60 fires the ending
			_sp_wait_step(game)
			var fin: Variant = sim.finale
			if fin == null:
				return "core_fly: the finale vanished before the fly"
			var fd: float = Vector2(float(fin["x"]) - float(sim.sx),
					float(fin["y"]) - float(sim.sy)).length()
			if fd < 60.0:
				_release_all(game)
				if not bool(sim.endingDone):
					return "core_fly: d < 60 but the ending never fired"
				ending_fired = true
				var blob: Variant = game.context.flags.get("spaceWorld")
				if not (blob is String):
					return "core_fly: the win flush never persisted (no spaceWorld flag)"
				var parsed: Variant = JSON.parse_string(String(blob))
				if not (parsed is Dictionary) or not bool(parsed.get("endingDone", false)):
					return "core_fly: the persisted spaceWorld does not carry endingDone (%s)" % [
							str(parsed.get("endingDone", "?"))]
				win_flush_ok = true
				_frames = 0
				_cap = "none"  # the ff leg's capture left the sub-state done
				_leg = "ending"
			elif _frames > CORE_FLY_BUDGET:
				return "core_fly: never reached the core in %d frames (%.0f px to go)" % [
						CORE_FLY_BUDGET, fd]
			else:
				var want := _hazard_desired(sim, Vector2(float(fin["x"]) - float(sim.sx),
						float(fin["y"]) - float(sim.sy)))
				_steer(game, want)
		"ending":
			var fail6 := _ending_tick(game, sim)
			if fail6 != "":
				return fail6
	return ""


# ---- the fly leg (kept out of the match for readability) ------------------------

## WASD thrust toward the arc's own nearest-living planet — the engine trail
## latches off the sim's thrust field + the stage fx pool, the ship-hull
## patch is captured mid-flight (render T, grab T+1), the exit rides the
## parked gate (the panel ring).
func _fly_tick(game: Variant, sim: Variant) -> String:
	if _target < 0:
		_target = nearest_living_index(sim)
		if _target < 0:
			return "fly: no living planet on the board"
	var p: Dictionary = sim.planets[_target]
	# the capture waits out the landing invuln (2.0): draw_ship's blink draws
	# the hull at alpha 0.5 on alternating frames while it lives
	if _cap == "none" and thrust_seen and trail_seen and float(sim.thrust) > 0.0 \
			and float(sim.invuln) <= 0.0:
		# the mid-flight capture: the ship + its trail, the cam state
		# latched at the render tick (the bot_civ twin shape)
		_probe = {"sx": float(sim.sx), "sy": float(sim.sy),
				"cam": Vector2(float(game.cam.x), float(game.cam.y))}
		game._do_render(0.0)
		_cap = "grab"
		return ""
	elif _cap == "grab":
		var img := _grab(game)
		if img == null:
			return "fly: the viewport returned no image"
		# project with the LATCHED cam (the render's own state — the live cam
		# has not moved: no sim step sits between render and grab)
		var cam: Vector2 = _probe["cam"]
		var sp := Vector2((float(_probe["sx"]) - cam.x) * float(game.cam.zoom) + game.vw / 2.0,
				(float(_probe["sy"]) - cam.y) * float(game.cam.zoom) + game.vh / 2.0)
		var mean := _patch_mean(img, sp.x, sp.y, 3)
		# the hull fill #cfe0f0 over the dark backdrop reads bright blue-white
		# with b > g > r (the checker's disc shape, visual_check_civ_scene.py:221)
		if mean.x < 90.0 or mean.z < 110.0 or not (mean.z > mean.y and mean.y > mean.x):
			return "fly: the ship hull is not bright blue-white at its projection (%s)" % str(mean)
		DirAccess.make_dir_recursive_absolute("user://visual_capture_space_bot")
		var err := img.save_png("user://visual_capture_space_bot/bot_space_flight.png")
		if err != OK:
			return "fly: cannot save the flight capture (%s)" % str(err)
		capture_ok = true
		_cap = "done"
	if not _held.is_empty():
		thrust_seen = thrust_seen or float(sim.thrust) > 0.0
		trail_seen = trail_seen or _trail_count(game.stages["space"]) > 0
	if _parked(sim, p):
		_release_all(game)
		_frames = 0
		_dna_mark(game)
		_leg = "abduct1"
		return ""
	if _frames > FLY_BUDGET:
		var d: float = Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length()
		return "fly: never reached the living planet %d (%.0f px, thrust %s held %s)" % [
				_target, d, str(sim.thrust), str(_held.keys())]
	_sp_wait_step(game)
	# close range rides the bang-bang station vector (arrive parked, not
	# ballistic); far range rides the raw bearing
	var d2: float = Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy)).length()
	var want: Vector2 = Vector2(float(p["x"]) - float(sim.sx), float(p["y"]) - float(sim.sy))
	if d2 < 400.0:
		want = _station_desired(sim, p)
	_steer(game, _hazard_desired(sim, want))
	return ""


# ---- the shared catch leg (abduct2/abduct3) -----------------------------------

## One more R catch at the parked station — cargo climbs toward the splice
## gate. The pay is whatever the ledger says (the +10 FIRST catch was the
## abduct1 leg's proof; a repeat catch of the same species pays 3).
func _catch_leg(game: Variant, sim: Variant, station: String, leg_name: String) -> String:
	var p: Dictionary = sim.planets[_target]
	if not _parked(sim, p):
		_leg = station
		_frames = 0
		return ""
	var want_cargo := 2 if leg_name == "abduct3" else 1
	if _frames == 1:
		_tap(game, KEY_R, "KeyR")
	_sp_wait_step(game)
	if sim.cargo.size() >= want_cargo:
		_frames = 0
		if leg_name == "abduct3":
			_leg = "ff_hold"
		else:
			_leg = "abduct3"
		return ""
	elif _frames > BEAM_BUDGET:
		return "%s: no catch in %d frames (cargo %d, beamT %s, toasts %s)" % [
				leg_name, BEAM_BUDGET, sim.cargo.size(), str(sim.beamT), str(_toasts(game))]
	return ""


# ---- the shared station leg ------------------------------------------------------

## Park the ship inside the target's panel ring (the bang-bang station
## vector) — the interaction legs route here whenever the ship drifted out.
func _station_tick(game: Variant, sim: Variant, next: String) -> String:
	var p: Dictionary = sim.planets[_target]
	if _parked(sim, p):
		_release_all(game)
		_frames = 0
		_leg = next
		return ""
	if _frames > STATION_BUDGET:
		return "station: never parked inside the ring in %d frames (held %s)" % [
				STATION_BUDGET, str(_held.keys())]
	_sp_wait_step(game)
	_steer(game, _hazard_desired(sim, _station_desired(sim, p)))
	return ""


# ---- the ending leg ------------------------------------------------------------

## The veil fades IN (alpha 1 at endingT 2.0 — the ACCEPTS YOU title draws at
## a ≥ 1 && !dismissed): gate the title patch, then a real click dismisses,
## the sandbox hands back.
func _ending_tick(game: Variant, sim: Variant) -> String:
	if _cap == "none" and float(sim.endingT) >= 2.2 and not bool(sim.endingDismissed):
		game._do_render(0.0)
		_cap = "grab"
		return ""
	if _cap == "grab":
		var img := _grab(game)
		if img == null:
			return "ending: the viewport returned no image"
		# 'THE CHAOS CORE ACCEPTS YOU' 34px #e2a4ff — the checker's
		# live-validated purple-count over its own title box
		# (test_space_scene._ending_probes: [vw/2±260, vh/2−140..−100]; want ≥ 12)
		var n := _count_purple(img, [game.vw / 2.0 - 260.0, game.vh / 2.0 - 140.0,
				game.vw / 2.0 + 260.0, game.vh / 2.0 - 100.0])
		if n < 12:
			return "ending: the ACCEPTS YOU title never rendered (%d purple px)" % n
		DirAccess.make_dir_recursive_absolute("user://visual_capture_space_bot")
		var err := img.save_png("user://visual_capture_space_bot/bot_space_ending.png")
		if err != OK:
			return "ending: cannot save the ending capture (%s)" % str(err)
		ending_seen = true
		_cap = "done"
		_frames = 0
		return ""
	if _cap == "done" and _frames == 1 and not bool(sim.endingDismissed):
		# a real click on a neutral screen point (clear of the panel rows at
		# x ≥ vw−270 and of the hud's top-right buttons) dismisses the ending
		# — the sim reads the raw wasClicked (TS:577-581)
		driver.mouse_down(Vector2(200.0, 300.0))
		driver.delivery_ok = driver.delivery_ok and game.input.is_down()
		step(game, 1)
		driver.mouse_up()
		# the dismissT latch reads POST-step: the sim snapshots dismissT =
		# endingT on the dismiss frame itself (the endingT the click landed on)
		_ending_t_click = float(sim.endingT)
		_watch(game)
		return ""
	if bool(sim.endingDismissed):
		if absf(float(sim.dismissT) - _ending_t_click) > 0.001:
			return "ending: dismissT does not carry the click's endingT (%s vs %s)" % [
					str(sim.dismissT), str(_ending_t_click)]
		dismissed_seen = true
		if not calm_objective:
			return "ending: the calm objective never rendered (%s)" % str(
					game.stages["space"].hud_inst.show_objective)
		# the ship-visible seam reads true again (space_stage's static:
		# not endingDone or endingDismissed — computed from the fields)
		ship_returned = (not bool(sim.endingDone)) or bool(sim.endingDismissed)
		if not ship_returned:
			return "ending: the ship-visible seam stayed closed"
		_leg = "done"
		return "OK"
	if _frames > ENDING_BUDGET:
		return "ending: the click never dismissed (%d frames, endingT %s)" % [
				ENDING_BUDGET, str(sim.endingT)]
	_sp_wait_step(game)
	return ""


# ---- field-read helpers --------------------------------------------------------

func _toasts(game: Variant) -> Array:
	var out: Array = []
	var hud: Variant = game.stages["space"].hud_inst
	if hud != null:
		for t in hud._toasts:
			out.append(String(t["text"]))
	return out


func _banners(game: Variant) -> Array:
	var out: Array = []
	var hud: Variant = game.stages["space"].hud_inst
	if hud != null:
		if hud._cur_banner != null:
			out.append(String(hud._cur_banner["title"]))
		for b in hud._banner_queue:
			out.append(String(b["title"]))
	return out


func _panel_rows(game: Variant) -> Array:
	var out: Array = []
	for b in game.stages["space"]._panel_rects:
		out.append("%s:%s" % [str(b["action"]), str(b["enabled"])])
	return out


func _ff_ability_active(game: Variant) -> bool:
	var hud: Variant = game.stages["space"].hud_inst
	if hud == null:
		return false
	for ab in hud.abilities:
		if String(ab["key"]) == "F":
			return bool(ab["active"])
	return false


func _living_pop(sim: Variant) -> float:
	var pop := 0.0
	for p in sim.planets:
		if p["eco"] != null:
			for sp in p["eco"].living():
				pop += float(sp["pop"])
	return pop


func _living_species(sim: Variant) -> int:
	var n := 0
	for p in sim.planets:
		if p["eco"] != null:
			n += p["eco"].living().size()
	return n


func _colonies_of(sim: Variant) -> int:
	var n := 0
	for p in sim.planets:
		if p["colony"] != null:
			n += 1
	return n


func _thriving_of(sim: Variant) -> int:
	var n := 0
	for p in sim.planets:
		if p["colony"] != null and float(p["colony"]["pop"]) >= 20.0:
			n += 1
	return n
