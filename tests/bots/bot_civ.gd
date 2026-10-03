## Civ play-bot — M5 task 5. Rides bot_tribe's now-real legs (composition:
## ONE BotTribe instance → its bot_creature → ONE LCG driver across the whole
## run — the M4 shape, bot_tribe.gd:68-69) through the FULL tribe arc to the
## REAL tribe victory (the founding→totem leg whose go_to('civ') LANDS the
## registered CivStage — d7a5cb8), then walks the civ arc tick-per-frame on
## the REAL input pipeline (Global Constraint 8):
##   the honest-launch gate observed FIRST (a real Digit1 at mil 4 → power 8
##   ≤ rivalDef 8 → the hopeless-refuse toast, NO armada — civ_sim.gd:490-497)
##   → a real Q tap raising mil 4→5 on the FULL board (output 10: the
##   '+1 mil ← culture' transfer toast; the culture/econ 3-3 tie broken
##   toward culture by the canonical lane order, civ_sim.gd:441-452) → the
##   pre-launch ROUTE TWIN capture → the FIRST honest attack launch (mil ≥ 5:
##   power 9 > rivalDef 8) → the armada FLIES (a mid-flight viewport capture:
##   the ship disc red-dominant + the [4,6] dashed trail cadence vs the twin
##   — numeric pixel asserts only, images never viewed) → the resolve
##   observed (the influence jump on the target + the sim's OWN net math read
##   back: the '+3 influence' floatWorld text IS net/10 rendered, and the
##   jump equals (power − rivalDef)·10 with the power SNAPSHOT read off the
##   armada, civ_sim.gd:489/:532) → regen refills the lastRaised lane (mil
##   3→4→5 at the 6 s beats, culture and econ untouched — total < output,
##   civ_sim.gd:309-316) between TWO honest launches → the victory leg:
##   debug_set_influence to the flip threshold on the two far cities (the
##   documented cheat — the tick_second hearts→flip path flips them,
##   civ_sim.gd:634-639), the nearest city to just under (98: one honest
##   resolve's +30 crosses; an economy-rival −2 buy proc cannot starve it),
##   real Q taps refilling mil to 5 (whatever the seed's regen already did),
##   then ONE real Digit1 launch flips it → all owned → victoryFired → the
##   space placeholder transition captured ({next 'space', 'THE BLACK OCEAN',
##   'a planet was never going to be enough'} — the unregistered-space switch
##   no-ops, the civ stage remains, the test_hud_civ.gd:301 premise).
##
## TS AUTHORITY: no civ bot test exists in the frozen repo (Spore/tests/
## holds bot/bot-arc/bot-creature only). The cheat set mirrors the M4 family:
## direct start_new_game (bot.test.ts:62, ridden in the creature legs),
## debug_set_influence through its documented sim mutator (civ_sim.gd:791-795
## — the sim header's debug-seam surface: debug_state read,
## debug_set_influence, debug_clear_chaos), everything else real input.
##
## TICK SHAPE: the scene calls civ_tick once per _process frame AFTER the
## arrival/founding/tribe phases (delegated to the bot_tribe module — the
## founding→totem arc lands civ through the REAL go_to; NEVER re-implemented
## here). The capture sub-states ride IN the legs (render in tick T, the
## SceneTree flushes the draw between ticks, the image grabbed in tick T+1 —
## the test_civ_scene arm→shot shape); the probes are computed from the sim
## state AT THE RENDER TICK (the grab reads the previous completed pass).
## Every watch is a plain field read: sim fields, hud_inst._toasts/
## _floaters/_cur_banner/_banner_queue (the stage-NAMED hud — the d7a5cb8
## lesson: the post-landing reads go through game.stages['civ'], never
## game.current), game.transition. The launch target is cross-checked against
## THIS bot's own nearest-unowned scan (the sim's stable-selection shape
## computed independently from field reads).
##
## BOT LAW AUDIT: every input rides the driver (Input.parse_input_event +
## flush) — Digit1 taps ×4 (the gate refusal + three launches), Q taps (the
## full-board raise + the victory-leg refill, one per tick while mil < 5).
## Direct sim calls:
## debug_set_influence ONLY (the documented cheat above — the far cities'
## flip-threshold grant, the eco-buy repair re-grants, the nearest city's
## 98 grant). Everything else is field reads: sim fields, hud lists,
## game.transition, game.input (the per-tap delivery proof), and the civ
## stage's static map_to_screen seam (pure geometry, no state). The scene
## asserts driver.sane_violations empty (the sweeps ride the 600-beats here
## AND in the creature legs) and driver.delivery_ok true.
##
## CHAOS NOTE: the pinned seed's chaos behavior is whatever it is (the M4
## bot lesson) — every leg exits on SIM-FIELD conditions (the regen watch
## rides the mil field, so trade_winds' faster regenT only moves the exit
## frame; rebellion no-ops while the bot owns only the capital — the id
## exclusion, civ_sim.gd:668-676; a post-flip rebellion hit cannot un-own —
## the revolt gate is influence ≤ −99.8), the flip watch re-grants through
## the documented cheat when an economy-rival buy procs a granted city back
## below the threshold, and the pixel-assert thresholds carry star-parallax
## and chaos-glow tails. Determinism carries replay: the ×2 gate compares
## the quantized CIV end-state fingerprints (game.stages['civ'].sim — NEVER
## game.current.sim, which aliases) plus a per-600-frame sweep trace through
## the civ legs; all leg exits are deterministic frames at the pinned seed.
extends RefCounted

const BotTribeScript := preload("res://tests/bots/bot_tribe.gd")

const DT := 1.0 / 60.0
const RESOLVE_BUDGET := 60 * 10   # the flight: 220 px/s over a ~360-900 px route (1.6-4.1 s) + capture ticks
const REGEN_BUDGET := 60 * 22     # two 6 s regen beats + trade-winds drift margin
const FLIPS_BUDGET := 60 * 10     # the tick_second flip ≤ 1 s after the grant + repair margin
const CD_BUDGET := 60 * 10        # the 5 s route cooldown decay
const VICTORY_BUDGET := 60 * 12   # out 0.55 + card 2.2 + in 0.6 + drift
const TOAST_BUDGET := 60 * 3      # a tapped key lands its toast within a frame or two
## The victory-leg grants: the two far cities AT the flip threshold (100 —
## the tick_second flip is influence ≥ 100, civ_sim.gd:635); the nearest just
## under (98 — still a launch target: the gate needs influence < 100 — and
## one honest resolve's net +30 crosses it; an economy-rival −2 buy proc
## between grant and resolve cannot starve the flip: 98 − 2k + 30 ≥ 100 for
## k ≤ 14).
const GRANT_FAR := 100.0
const GRANT_NEAR := 98.0

var tb: Variant = null        # bot_tribe — the arrival/founding/tribe legs ride it
var driver: Variant = null    # tb.cb.driver — ONE LCG stream across the whole run
## Per-600-frame quantized sweep trace through the CIV legs (determinism
## triage; the hard gate is the end fingerprint).
var trace: Array = []

# latched observations (the scene asserts them at the arc's end)
var transfer_toast_seen := false  # '+1 mil ← culture' on the full board
var gate_refusal_seen := false    # the honest-launch gate's hopeless-refuse toast at mil 4
var launches_honest := 0          # Digit1 launches that passed the gate at mil ≥ 5
var resolves_seen := 0            # resolve influence-jumps latched (the honest flights)
var floater_reads := 0            # '+3 influence' floatWorld reads (the sim's own net math)
var regen_refills := 0            # lastRaised-lane refills observed (mil 3→4→5)
var join_names := {}              # the 'JOINS YOUR PLANETARY STATE' banner titles seen
var victory_card := {}            # the captured space transition {next,title,sub}
var capture_ok := false           # the mid-flight pixel asserts passed (ship + trail)

# state machine
var _leg := "gate"
var _frames := 0                  # leg-local budget counter (ticks; 1 sim frame each)
var _civ_f := 0                   # global civ-frame counter (sweep trace phase)
var _nearest := -1                # THIS bot's nearest-unowned scan (the cross-check)
var _mil_before := 0.0            # launch-leg spend proof
var _power := 0.0                 # the armada's power SNAPSHOT field (the net read-back)
var _rival_def := 0.0             # derived from ctx.difficulty (rival_def_for's formula)
var _inf_prev := 0.0              # per-frame Δinfluence detector (the resolve watch)
var _jump := -1.0                 # the latched resolve jump
var _regen_mil := 0.0             # the regen watch's last milestone
var _cap := "none"                # the 2-tick capture sub-state: none|grab
var _twin_img: Image = null
var _twin_cam := Vector2.ZERO
var _probe := {}                  # the flight geometry recorded at the render tick
var _flight_img: Image = null


func _init() -> void:
	tb = BotTribeScript.new()
	driver = tb.driver


# ---- shared ---------------------------------------------------------------------

func step(game: Variant, n: int) -> void:
	game.step_for_testing(n, DT)


func civ_sim(game: Variant) -> Variant:
	# the d7a5cb8 lesson: NAME the stage — game.current.sim aliases whatever
	# stage is live (the creature sim in the early legs); the civ legs read
	# the stage-named sim exclusively
	return game.stages["civ"].sim


## rival_def_for(true) (civ_sim.gd:521-523) derived from the CONTEXT field —
## a pure function of difficulty, recomputed here rather than calling the
## sim method (the bot law: field reads; only the debug cheats are calls).
func _rival_def_of(game: Variant) -> float:
	var d := String(game.context.difficulty)
	return 6.0 + (3.0 if d == "chaos" else (-1.0 if d == "peaceful" else 0.0))


## THIS bot's own nearest-unowned scan — the launch-target cross-check. The
## sim's exact filter (owner != 'you' AND influence < 100, civ_sim.gd:469-472)
## with the sim's stable selection shape: a strict-< minimum scan, first
## minimum wins ties (the sort ledger, civ_sim.gd:476-487).
func nearest_unowned_index(sim: Variant) -> int:
	var best := -1
	var best_d := INF
	var cap: Dictionary = sim.cities[0]
	for i in sim.cities.size():
		var c: Dictionary = sim.cities[i]
		if String(c["owner"]) == "you" or float(c["influence"]) >= 100.0:
			continue
		var dx: float = float(c["x"]) - float(cap["x"])
		var dy: float = float(c["y"]) - float(cap["y"])
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = i
	return best


## Quantized civ-state snapshot (the determinism gate + sweep rows): the
## national sliders, the regen/cd clocks, the drift camera, the whole board
## (owner/influence/hp/pop/burning per city) and the context's karma/chaos/
## dna — the stage-NAMED sim exclusively.
func civ_fingerprint(game: Variant) -> Dictionary:
	var sim: Variant = game.stages["civ"].sim
	var c: Variant = game.context
	var out := {
		"mil": floori(float(sim.mil) * 100.0),
		"culture": floori(float(sim.culture) * 100.0),
		"econ": floori(float(sim.econ) * 100.0),
		"output": floori(float(sim.output) * 100.0),
		"lastRaised": String(sim.lastRaised),
		"regenT": floori(float(sim.regenT) * 100.0),
		"time": floori(float(sim.time) * 100.0),
		"cdA": floori(float(sim.launchCds["attack"]) * 100.0),
		"camX": floori(float(sim.camX) * 100.0),
		"camY": floori(float(sim.camY) * 100.0),
		"armadas": sim.armadas.size(),
		"victory": bool(sim.victoryFired),
		"karma": floori(float(c.karma) * 1000.0),
		"chaos": floori(float(c.chaos) * 1000.0),
		"dna": floori(float(c.dna) * 100.0),
	}
	for i in sim.cities.size():
		var ci: Dictionary = sim.cities[i]
		out["c%d_own" % i] = String(ci["owner"])
		out["c%d_inf" % i] = floori(float(ci["influence"]) * 100.0)
		out["c%d_hp" % i] = floori(float(ci["hp"]) * 100.0)
		out["c%d_pop" % i] = floori(float(ci["pop"]) * 100.0)
		out["c%d_burn" % i] = floori(float(ci["burning"]) * 100.0)
	return out


## The per-frame watch every civ leg rides: latches the toast/banner
## observations (a field-read sweep — no sim calls, no input). The toast
## latches are locale-invariant: every matched substring is a RAW composed
## string in the sim (the transfer/refuse templates and the '(power %s)'
## suffix carry no tr() — only the 'armada →' middle does).
func _watch(game: Variant) -> void:
	var hud: Variant = game.stages["civ"].hud_inst
	if hud == null:
		return
	for t in hud._toasts:
		var s := String(t["text"])
		if s.contains("+1 mil ← culture"):
			transfer_toast_seen = true
		if s.contains("more output in its lane"):
			gate_refusal_seen = true
	for b in hud._banner_queue:
		_latch_join(String(b["title"]))
	if hud._cur_banner != null:
		_latch_join(String(hud._cur_banner["title"]))


func _latch_join(title: String) -> void:
	if title.contains("JOINS YOUR PLANETARY STATE"):
		join_names[title] = true


## One stepped civ frame inside a wait leg: the sweep trace rides the GLOBAL
## civ-frame counter so rows align across passes; the driver's assert_sane
## rides the same 600-beats (it accumulates driver.sane_violations).
func _civ_wait_step(game: Variant) -> void:
	_civ_f += 1
	step(game, 1)
	_watch(game)
	if _civ_f % 600 == 0:
		trace.append({"f": _civ_f, "fp": civ_fingerprint(game)})
		driver.assert_sane(game)


## A real tap + the delivery proof: the wrapper one-shot must hold at
## injection time (the driver's step_loop precedent — the REAL-pipeline
## evidence per tap, not just the creature legs').
func _tap(game: Variant, keycode: int, code: String) -> void:
	driver.tap_key(keycode)
	driver.delivery_ok = driver.delivery_ok and game.input.key_pressed(code)


# ---- the capture seam -------------------------------------------------------------

## The civ stage's own toScreen seam (a pure static — no copies, no state).
func _proj(game: Variant, cam: Vector2, mx: float, my: float) -> Vector2:
	return game.stages["civ"].map_to_screen(mx, my, cam.x, cam.y, game.vw, game.vh)


## Grab the last completed viewport pass (the render tick queued it; the
## game node is in the tree under xvfb — the test_civ_scene pattern).
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


## The twin + flight route check — the checker's run_along shape
## (visual_check_civ_scene.py:94-105) made camera-drift-proof: both captures
## sample the SAME MAP span (target → the ship's map position at the flight
## render tick) through EACH capture's own camera. The ocean color at a map
## point is camera-invariant (the whole planet drawing is a rigid translate
## of the offset-from-planet-center; a map point keeps its offset), so the
## per-sample red delta isolates the dash (alpha 0.25 of the attack color).
## 20 samples at t = 0.12..0.88 clear the city glow (22 px) and the ship
## glow (10 px) at both ends.
func _trail_asserts(game: Variant) -> String:
	var tx := float(_probe["tx"])
	var ty := float(_probe["ty"])
	var sx := float(_probe["sx"])
	var sy := float(_probe["sy"])
	var tgt_t: Vector2 = _proj(game, _twin_cam, tx, ty)
	var ship_t: Vector2 = _proj(game, _twin_cam, sx, sy)
	var tgt_f: Vector2 = _proj(game, _probe["cam"], tx, ty)
	var ship_f: Vector2 = _proj(game, _probe["cam"], sx, sy)
	var on := 0
	var gap := 0
	var n := 20
	for k in n:
		var t := 0.12 + (0.88 - 0.12) * float(k) / float(n - 1)
		var a := _px(_flight_img, tgt_f.x + (ship_f.x - tgt_f.x) * t,
				tgt_f.y + (ship_f.y - tgt_f.y) * t)
		var b := _px(_twin_img, tgt_t.x + (ship_t.x - tgt_t.x) * t,
				tgt_t.y + (ship_t.y - tgt_t.y) * t)
		var delta := a.x - b.x
		if delta >= 12.0:
			on += 1
		if delta <= 4.0:
			gap += 1
	# the checker counts ≥4/20 on and ≥4/20 gap with both cameras EXACTLY
	# zeroed; the bot's twin rides the pre-launch cam (0.0 — no armada ever
	# flew) and the flight cam moves, so the star field's 0.3-parallax can
	# tail a sample or two — the cadence gate trims to 3 and still proves
	# the [4,6] dashes (the ocean underneath is camera-invariant, gap ≈ 0).
	if on < 3 or gap < 3:
		return "trail cadence %d/%d on, %d/%d gap (want on>=3 gap>=3)" % [on, n, gap, n]
	return ""


# ---- the civ arc (one tick per scene frame, post bot_tribe's OK) --------------------
## Returns "OK" when the full civ arc completed (the unification victory
## fired the space transition, it ran its course, and the civ stage
## remained), "" while still walking, else the failure reason. _frames is
## the leg-local tick counter, incremented once per tick at the top.
func civ_tick(game: Variant) -> String:
	_frames += 1
	var sim: Variant = civ_sim(game)
	match _leg:
		"gate":
			# the honest-launch gate's hopeless-refuse rung through a REAL
			# key: at mil 4 the attack power is 8 ≤ rivalDef 8 (normal) →
			# refuse + toast, NO armada (civ_sim.gd:490-497). ONE tap on the
			# first tick, then watch.
			if _frames == 1:
				_tap(game, KEY_1, "Digit1")
			step(game, 1)
			_watch(game)
			if gate_refusal_seen and sim.armadas.is_empty():
				_frames = 0
				_leg = "sliders"
			elif _frames > TOAST_BUDGET:
				return "gate: the mil-4 Digit1 tap neither refused nor launched (%s, armadas %d)" % [
						str(sim.mil), sim.armadas.size()]
		"sliders":
			# one real Q tap on the FULL board (4/3/3 = output 10): mil 5 +
			# the transfer toast; the culture/econ tie donates culture
			if _frames == 1:
				_tap(game, KEY_Q, "KeyQ")
			step(game, 1)
			_watch(game)
			if absf(float(sim.mil) - 5.0) < 0.001 and absf(float(sim.culture) - 2.0) < 0.001 \
					and transfer_toast_seen:
				_nearest = nearest_unowned_index(sim)
				if _nearest < 0:
					return "sliders: no un-owned under-100 target on the constructor board"
				_frames = 0
				_leg = "twin_render"
			elif _frames > TOAST_BUDGET:
				return "sliders: the Q tap did not raise mil to 5 with the transfer toast (mil %s culture %s toast %s)" % [
						str(sim.mil), str(sim.culture), str(transfer_toast_seen)]
		"twin_render":
			# the pre-launch ROUTE TWIN: the board without armadas, the drift
			# camera still at 0 (no armada has ever flown). Render in tick T,
			# grab in tick T+1 (the SceneTree flushes the draw between ticks).
			_civ_wait_step(game)
			game._do_render(0.0)
			_twin_cam = Vector2(float(sim.camX), float(sim.camY))
			_leg = "twin_grab"
		"twin_grab":
			_civ_wait_step(game)
			_twin_img = _grab(game)
			if _twin_img == null:
				return "twin_grab: the viewport returned no image"
			var err := _twin_img.save_png("user://visual_capture_civ_bot/bot_civ_route.png")
			if err != OK:
				return "twin_grab: cannot save the route twin (%s)" % str(err)
			_frames = 0
			_leg = "launch1"
		"launch1":
			var fail := _launch_check(game, sim)
			if fail != "":
				return fail
			_leg = "flight1"
		"flight1":
			var fail2 := _flight_tick(game, sim, "regen", true)
			if fail2 != "":
				return fail2
		"regen":
			# regen refills the LASTRAISED lane (launch 1 armed it to mil) at
			# the 6 s beats while total < output — culture and econ untouched
			# (civ_sim.gd:309-316); the exit rides the mil FIELD so a
			# trade-winds-fastened regen only moves the exit frame
			_civ_wait_step(game)
			if float(sim.mil) >= _regen_mil + 1.0:
				regen_refills += 1
				_regen_mil = float(sim.mil)
			if float(sim.mil) >= 5.0:
				if absf(float(sim.culture) - 2.0) > 0.001 or absf(float(sim.econ) - 3.0) > 0.001:
					return "regen: the refills left the lastRaised lane (mil %s culture %s econ %s)" % [
							str(sim.mil), str(sim.culture), str(sim.econ)]
				if String(sim.lastRaised) != "mil":
					return "regen: lastRaised drifted (%s)" % str(sim.lastRaised)
				_frames = 0
				_leg = "launch2"
			elif _frames > REGEN_BUDGET:
				return "regen: mil never refilled to 5 (%s after %d frames)" % [
						str(sim.mil), _frames]
		"launch2":
			var fail3 := _launch_check(game, sim)
			if fail3 != "":
				return fail3
			_leg = "flight2"
		"flight2":
			var fail4 := _flight_tick(game, sim, "victory_grant", false)
			if fail4 != "":
				return fail4
		"victory_grant":
			# the documented cheat: the two FAR cities to the flip threshold
			# (100) — the tick_second hearts→flip path owns the flip; the
			# nearest stays un-granted until the prep leg (below threshold,
			# so it stays the ONE launch target)
			for i in sim.cities.size():
				if i > 0 and i != _nearest:
					sim.debug_set_influence(i, GRANT_FAR)
			_frames = 0
			_leg = "flips_wait"
		"flips_wait":
			_civ_wait_step(game)
			# the eco-buy repair: a −2 influence buy proc between the grant
			# and the flip would park a city below the threshold forever —
			# re-grant through the same documented cheat (SET semantics)
			for j in sim.cities.size():
				if j > 0 and j != _nearest and String(sim.cities[j]["owner"]) != "you" \
						and float(sim.cities[j]["influence"]) < 100.0:
					sim.debug_set_influence(j, GRANT_FAR)
			var all_far := true
			for k in sim.cities.size():
				if k > 0 and k != _nearest and String(sim.cities[k]["owner"]) != "you":
					all_far = false
			if all_far:
				_frames = 0
				_leg = "cd_wait"
			elif _frames > FLIPS_BUDGET:
				var owners: Array = []
				for c4 in sim.cities:
					owners.append(String(c4["owner"]))
				return "flips_wait: the far cities never flipped (%s)" % str(owners)
		"cd_wait":
			# the launch-2 route cooldown must be clear before the victory
			# launch (a silent cd return would no-op the REAL tap)
			_civ_wait_step(game)
			if float(sim.launchCds["attack"]) <= 0.0:
				_frames = 0
				_leg = "victory_prep"
			elif _frames > CD_BUDGET:
				return "cd_wait: the attack cooldown never cleared (%s)" % str(sim.launchCds["attack"])
		"victory_prep":
			# mil back to 5 through REAL Q taps — one per tick, stopping the
			# frame mil reaches 5. Regen may already have refilled partway
			# through the intervening legs (the beats keep firing while
			# total < output), so the tap COUNT is whatever the seed says —
			# but the climb stops EXACTLY at 5 (each Q adds 1, each regen
			# beat adds 1, and total = 5+2+3 = output never overflows), so a
			# transfer toast can never fire here and the honest-launch
			# precondition (mil ≥ 5) is re-proven by the launch leg itself.
			if float(sim.mil) < 5.0:
				_tap(game, KEY_Q, "KeyQ")
			step(game, 1)
			_watch(game)
			if float(sim.mil) >= 5.0:
				sim.debug_set_influence(_nearest, GRANT_NEAR)
				_frames = 0
				_leg = "victory_launch"
			elif _frames > CD_BUDGET:
				return "victory_prep: mil never reached 5 (%s)" % str(sim.mil)
		"victory_launch":
			var fail5 := _launch_check(game, sim)
			if fail5 != "":
				return fail5
			_leg = "victory_flight"
		"victory_flight":
			# the flight whose resolve COMPLETES unification: the clamped
			# resolve (98 + 30 → 100) flips the nearest, the victory check at
			# the tail of the SAME update fires go_to('space') — watch the
			# FLIP (not a jump: the clamp caps the delta at +2)
			_civ_wait_step(game)
			var near_c: Dictionary = sim.cities[_nearest]
			if String(near_c["owner"]) == "you":
				if game.transition != null:
					victory_card = {
						"next": String(game.transition["next"]),
						"title": String(game.transition["title"]),
						"sub": String(game.transition["sub"]),
					}
					_frames = 0
					_leg = "victory_land"
				elif _frames > TOAST_BUDGET:
					return "victory_flight: the board unified but no transition fired (%s)" % str(victory_card)
			elif _frames > RESOLVE_BUDGET:
				return "victory_flight: the nearest city never flipped (owner %s influence %s armadas %d)" % [
						str(near_c["owner"]), str(near_c["influence"]), sim.armadas.size()]
		"victory_land":
			# the transition runs its course (out 0.55 + card 2.2 + in 0.6 —
			# no clicks injected, the card auto-advances); space is
			# UNREGISTERED: the switch no-ops and the civ stage remains
			_civ_wait_step(game)
			if game.transition == null:
				if String(game.context.stage) != "civ" or game.current.id != "civ":
					return "victory_land: the civ stage did not remain (stage %s current %s)" % [
							str(game.context.stage), str(game.current.id)]
				if not bool(sim.victoryFired):
					return "victory_land: victoryFired never latched"
				if String(victory_card.get("next", "")) != "space" \
						or String(victory_card.get("title", "")) != "THE BLACK OCEAN" \
						or String(victory_card.get("sub", "")) != "a planet was never going to be enough":
					return "victory_land: wrong card (%s)" % str(victory_card)
				_leg = "done"
				return "OK"
			elif _frames > VICTORY_BUDGET:
				return "victory_land: the transition never completed (%d frames, phase %s)" % [
						_frames, str(game.transition.get("phase", "?"))]
	return ""


## One honest launch leg (shared by launch1/launch2/victory_launch): records
## the pre-state, fires the REAL Digit1 tap, and asserts the gate ladder's
## PASS side — mil ≥ 5 (power = mil + 4 > rivalDef 8 at normal), the spend,
## the armada on THIS bot's independently computed nearest, the power
## SNAPSHOT, the cooldown arming, the launch toast's locale-invariant tail.
func _launch_check(game: Variant, sim: Variant) -> String:
	_mil_before = float(sim.mil)
	_rival_def = _rival_def_of(game)
	if _mil_before < 5.0:
		return "launch: the honest gate precondition missing (mil %s)" % str(_mil_before)
	_nearest = nearest_unowned_index(sim)
	if _nearest < 0:
		return "launch: no eligible target"
	_inf_prev = float(sim.cities[_nearest]["influence"])
	_jump = -1.0
	_tap(game, KEY_1, "Digit1")
	step(game, 1)
	_watch(game)
	if absf(float(sim.mil) - (_mil_before - 2.0)) > 0.001:
		return "launch: the 2-mil spend did not land (%s → %s)" % [str(_mil_before), str(sim.mil)]
	_regen_mil = float(sim.mil)  # the regen watch's baseline: the POST-spend lane
	if sim.armadas.size() != 1:
		return "launch: the honest Digit1 tap did not launch (mil %s, armadas %d)" % [
				str(_mil_before), sim.armadas.size()]
	var a: Dictionary = sim.armadas[0]
	_power = float(a["power"])
	if absf(_power - (_mil_before + 4.0)) > 0.001:
		return "launch: the power snapshot is not mil+4 (%s vs mil %s)" % [str(_power), str(_mil_before)]
	var target: Dictionary = a["target"]
	if String(target["id"]) != String(sim.cities[_nearest]["id"]):
		return "launch: the armada's target is not the nearest un-owned city (%s vs %s)" % [
				str(target["id"]), str(sim.cities[_nearest]["id"])]
	if absf(float(sim.launchCds["attack"]) - 5.0) > 0.001:
		return "launch: the route cooldown did not arm (%s)" % str(sim.launchCds["attack"])
	if String(sim.lastRaised) != "mil":
		return "launch: lastRaised did not arm to the spent lane (%s)" % str(sim.lastRaised)
	var want_power := str(_mil_before + 4.0)  # "9" — the raw toast tail (locale-invariant)
	var toast_ok := false
	var hud: Variant = game.stages["civ"].hud_inst
	if hud != null:
		for t in hud._toasts:
			if String(t["text"]).contains("(power %s)" % want_power):
				toast_ok = true
	if not toast_ok:
		return "launch: the launch toast never fired with (power %s)" % want_power
	launches_honest += 1
	_frames = 0
	_cap = "none"
	return ""


## One flight leg (shared by flight1/flight2): the armada FLIES (flight1
## captures the ship disc + trail mid-flight), the resolve is observed (the
## target's influence jump + the sim's own net math: the '+N influence'
## floatWorld text IS net/10 rendered), then control passes to `next`. The
## capture sub-state rides INSIDE the leg (render tick T, grab tick T+1)
## without breaking the uniform step cadence.
func _flight_tick(game: Variant, sim: Variant, next: String, want_capture: bool) -> String:
	_civ_wait_step(game)
	# the mid-flight capture: armadas.size() == 1 is guaranteed here (the
	# route cooldown spaces launches; the resolve ends this leg)
	if want_capture and _cap == "none" and _probe.is_empty() \
			and sim.armadas.size() == 1 and float(sim.armadas[0]["t"]) >= 0.4:
		# clear of the capital's 22 px glow (the test_civ_scene freeze gate)
		var a0: Dictionary = sim.armadas[0]
		_probe = {
			"tx": float(a0["tx"]), "ty": float(a0["ty"]),
			"sx": float(a0["x"]), "sy": float(a0["y"]),
			"cam": Vector2(float(sim.camX), float(sim.camY)),
		}
		game._do_render(0.0)
		_cap = "grab"
		return ""
	elif _cap == "grab":
		_flight_img = _grab(game)
		if _flight_img == null:
			return "flight: the viewport returned no image"
		var cam: Vector2 = _probe["cam"]
		var ship: Vector2 = _proj(game, cam, float(_probe["sx"]), float(_probe["sy"]))
		var mean := _patch_mean(_flight_img, ship.x, ship.y, 2)
		# the checker's armada-ship thresholds (visual_check_civ_scene.py:221):
		# the attack disc #ff7a5a over the blue ocean reads red-dominant
		if mean.x < 140.0 or mean.x - mean.z < 40.0:
			return "flight: the ship disc is not red-dominant at its projection (%s)" % str(mean)
		var trail_fail := _trail_asserts(game)
		if trail_fail != "":
			return "flight: " + trail_fail
		var err := _flight_img.save_png("user://visual_capture_civ_bot/bot_civ_armada.png")
		if err != OK:
			return "flight: cannot save the armada capture (%s)" % str(err)
		capture_ok = true
		_cap = "done"
	# the resolve watch: the target's per-frame influence jump — a resolve
	# adds net = (power − rivalDef)·10 in one frame; an economy-rival −2 buy
	# proc can ride the same tick_second (≤ 2.0 off), the hearts drift ≤ 0.01
	# over a flight — hence the 25.0 latch floor
	var target: Dictionary = sim.cities[_nearest]
	var inf_now := float(target["influence"])
	var delta := inf_now - _inf_prev
	_inf_prev = inf_now
	if delta > 25.0 and _jump < 0.0:
		_jump = delta
	if sim.armadas.is_empty():
		if _jump < 0.0:
			return "flight: the armada resolved without a latched influence jump"
		var net := (_power - _rival_def) * 10.0
		if _jump < net - 2.001 or _jump > net + 0.5:
			return "flight: the influence jump is not the net math (%s vs net %s = (%s − %s)·10)" % [
					str(_jump), str(net), str(_power), str(_rival_def)]
		var floater_ok := false
		var hud: Variant = game.stages["civ"].hud_inst
		if hud != null:
			for f in hud._floaters:
				# the sim's OWN net/10 rendered (civ_sim.gd:546-549): net 30
				# → '+3 influence' — the read-back straight from the sim
				if String(f["text"]) == "+3 influence":
					floater_ok = true
		if not floater_ok:
			return "flight: the '+3 influence' floatWorld never rendered (the net math read-back)"
		floater_reads += 1
		resolves_seen += 1
		_probe = {}
		_frames = 0
		_leg = next
	elif _frames > RESOLVE_BUDGET:
		return "flight: no resolve in %d frames (armadas %d, target influence %s)" % [
				RESOLVE_BUDGET, sim.armadas.size(), str(target["influence"])]
	return ""

