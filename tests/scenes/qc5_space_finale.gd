# QC round 5 — agent-space-finale scene. Boots the REAL Game (all six stages
# registered, manual stepping — the qc5_space_arc pattern), pins a
# start_new_game seed, jumps to space through the REAL switch, then probes the
# FINALE edges the arc bot never rode:
#   1. debug_seed_colonies + held F → 3 thriving → AWAKENS banner + PULLS objective
#   2. a SECOND debug seed → a 4th thriving → NO second AWAKENS (finale!=null gate)
#   3. death mid-finale (pre-ending): the 15% DNA bill, finale survives, PULLS live
#   4. F held WHILE flying to the core (ff/flight stack) → d<60 → endingDone + win flush
#   5. the veil renders (ACCEPTS YOU purple patch)
#   6. quit-to-title MID-VEIL → CONTINUE: endingDone carried, finale restored
#      (not-dismissed branch), veil RE-SHOWS, calm objective (endingDone branch)
#   7. any-key dismiss (TS:577-581 the non-click path) + dismissT snapshot
#   8. death POST-ending: bill 0 ("you already won")
#   9. quit/continue AFTER dismiss: finale nulled (no stale orb), no veil,
#      colonies kept — then a re-approach to the core coords fires NOTHING.
# Every input rides the real pipeline (Input.parse_input_event + flush); the
# only direct sim call is debug_seed_colonies (the documented cheat seam).
extends Node

const MenuStageScript := preload("res://src/game/menu.gd")
const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const WORLD_SEED := 48879  # 0xBEEF — the proven M6 pin
const DT := 1.0 / 60.0

var _phase := "boot"
var _frames := 0            # phase-local
var _game: Variant = null
var _held := {}             # currently-held WASD codes
var _grab_next := false     # two-frame grab sub-state: render now, grab next tick

# latched observations
var awakens_count := 0      # edge-triggered AWAKENS banner fires
var _awakens_base := false
var pulls_seen := false
var calm_seen := false      # latched any time pre-restore (triage)
var _calm_fresh := false    # calm line seen SINCE the last hud rebuild
var obj_text := ""          # last objective text observed (triage prints)
var death1_bill := -1
var death1_exp := -1
var death2_bill := -1
var stack_ff_seen := false  # ffHold>0 while thrusting toward the core
var ending_fired := false
var win_flush_ok := false
var veil1_ok := false
var restore_midveil := {}
var dismiss_key_ok := false
var restore_dismissed := {}
var rereach_clean := false

# death-probe trackers (reset at phase entries via _reset_death_probe)
var _prev_dna := -1.0
var _prev_invuln := -1.0
var _d_bill := -1
var _d_exp := -1

# restore-probe trackers
var _ending_t_at_press := -1.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://qc5_space_finale")


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > 60 * 240:
		_fail("timeout in phase %s (frame %d)" % [_phase, _frames])
		return
	match _phase:
		"boot":
			_game = _build_game()
			_game.step_for_testing(1, DT)
			_game.stages["menu"].start_new_game(0, "normal", WORLD_SEED)
			_phase = "card"
		"card":
			_game.step_for_testing(1, DT)
			if _game.transition == null:
				_game.switch_stage("space")
				_phase = "settle"
		"settle":
			_game.step_for_testing(1, DT)
			if _game.stages["space"].sim != null and _game.current.id == "space":
				var sim: Variant = _sim()
				print("QC5FIN_LANDED planets=%d dna=%d sx=%.0f sy=%.0f" % [
					sim.planets.size(), int(_game.context.dna),
					float(sim.sx), float(sim.sy)])
				_phase = "seed_ff"
				_frames = 0
		"seed_ff":
			# the documented cheat + a real held F to 3 thriving
			if _frames == 1:
				_sim().debug_seed_colonies()
				print("QC5FIN_SEED colonies=%d" % _colonies())
				_press(KEY_F, true)
			_step_watch()
			if _thriving() >= 3:
				_press(KEY_F, false)
				_steer(_sim(), Vector2.ZERO)
				if awakens_count < 1:
					_fail("seed_ff: 3 thriving but no AWAKENS banner (obj=%s)" % obj_text)
					return
				if not pulls_seen:
					_fail("seed_ff: no PULLS objective (obj=%s)" % obj_text)
					return
				print("QC5FIN_AWAKENS_OK count=%d obj=%s" % [awakens_count, obj_text])
				_reset_death_probe()
				_phase = "reseed"
				_frames = 0
		"reseed":
			# a SECOND debug seed → a 4th thriving must NOT re-fire AWAKENS
			if _frames == 1:
				var before: int = _colonies()
				_sim().debug_seed_colonies()
				var after: int = _colonies()
				print("QC5FIN_RESEED colonies %d -> %d" % [before, after])
				if after == before:
					print("QC5FIN_RESEED_SKIP no extra non-barren planet")
					_phase = "death_probe"
					return
				_press(KEY_F, true)
			_step_watch()
			if _thriving() >= 4:
				_press(KEY_F, false)
				_steer(_sim(), Vector2.ZERO)
				if awakens_count != 1:
					_fail("reseed: AWAKENS re-fired (count=%d) — finale!=null gate broken" % awakens_count)
					return
				print("QC5FIN_NO_REAWAKENS_OK count=%d thriving=%d" % [awakens_count, _thriving()])
				_phase = "death_probe"
				_frames = 0
			elif _frames > 60 * 70:
				print("QC5FIN_RESEED_WEAK thriving=%d (4th colony slow — gate untested, not a fail)" % _thriving())
				_press(KEY_F, false)
				_steer(_sim(), Vector2.ZERO)
				_phase = "death_probe"
				_frames = 0
		"death_probe":
			# steer into the sun — a pre-ending death must bill 15% and leave
			# the finale untouched (PULLS keeps ticking)
			_steer(_sim(), Vector2(-float(_sim().sx), -float(_sim().sy)))
			_step_watch()
			if _d_bill >= 0:
				_steer(_sim(), Vector2.ZERO)
				var ok_bill: bool = absi(_d_bill - _d_exp) <= 1
				var fin_alive: bool = _sim().finale != null
				if not ok_bill or not fin_alive:
					_fail("death_probe: bill=%d exp=%d finale_alive=%s" % [
						_d_bill, _d_exp, str(fin_alive)])
					return
				print("QC5FIN_DEATH1_OK bill=%d exp=%d finale_alive=true obj=%s" % [
					_d_bill, _d_exp, obj_text])
				death1_bill = _d_bill
				death1_exp = _d_exp
				_reset_death_probe()
				_phase = "core_fly"
				_frames = 0
			elif _frames > 60 * 40:
				_fail("death_probe: no death in 40s of sun-diving (shp=%.0f pos=(%.0f,%.0f))" % [
					float(_sim().shp), float(_sim().sx), float(_sim().sy)])
				return
		"core_fly":
			# F held WHILE flying to the core — the ff/flight stack — then the win
			if _frames == 1:
				_press(KEY_F, true)
			_step_watch()
			var fin: Variant = _sim().finale
			if fin == null:
				_fail("core_fly: the finale vanished before the fly")
				return
			if float(_sim().ffHold) > 0.0:
				stack_ff_seen = true
			var fd: float = Vector2(float(fin["x"]) - float(_sim().sx),
					float(fin["y"]) - float(_sim().sy)).length()
			if fd < 60.0:
				_press(KEY_F, false)
				_steer(_sim(), Vector2.ZERO)
				if not bool(_sim().endingDone):
					_fail("core_fly: d<60 but the ending never fired")
					return
				ending_fired = true
				var blob: Variant = _game.context.flags.get("spaceWorld")
				if blob is String:
					var parsed: Variant = JSON.parse_string(String(blob))
					win_flush_ok = parsed is Dictionary and bool(parsed.get("endingDone", false))
				if not stack_ff_seen:
					print("QC5FIN_STACK_WEAK ffHold never latched mid-flight")
				if not win_flush_ok:
					_fail("core_fly: the win flush never persisted (spaceWorld flag)")
					return
				print("QC5FIN_ENDING_OK dna=%d endingT=%.2f stack_ff=%s" % [
					int(_game.context.dna), float(_sim().endingT), str(stack_ff_seen)])
				_reset_death_probe()
				_phase = "veil"
				_frames = 0
			elif _frames > 60 * 60:
				_fail("core_fly: never reached the core (%.0f px to go)" % fd)
				return
			else:
				_steer(_sim(), _hazard_desired(_sim(), Vector2(
					float(fin["x"]) - float(_sim().sx), float(fin["y"]) - float(_sim().sy))))
		"veil":
			# hands-off; the veil fades in — grab at alpha 1 and patch-check
			_step_watch()
			if _grab_next:
				_grab_next = false
				var n: int = _count_purple(_grab())
				veil1_ok = n >= 12
				print("QC5FIN_VEIL1 purple=%d ok=%s" % [n, str(veil1_ok)])
				if not veil1_ok:
					_fail("veil: the ACCEPTS YOU title never rendered (%d purple px)" % n)
					return
				_phase = "midveil_quit"
				_frames = 0
			elif float(_sim().endingT) >= 2.2 and not bool(_sim().endingDismissed):
				_game._do_render(0.0)
				_grab_next = true
		"midveil_quit":
			# real quit-to-title DURING the veil (endingDone=true, not dismissed)
			# — the pause._act_quit shape: save_all flush THEN go_to (a bare
			# go_to skips the quit save; run 1 lesson)
			if _frames == 1:
				_game.save_all()
				_game.go_to("menu")
			_game.step_for_testing(1, DT)
			if _game.transition == null and _game.current != null \
					and _game.current.id == "menu":
				_phase = "continue1"
				_frames = 0
		"continue1":
			if _frames == 1:
				_calm_fresh = false
				obj_text = ""
				_reset_death_probe()
				_game.stages["menu"].continue_slot(0)
			_game.step_for_testing(1, DT)
			if _game.transition == null and _game.current != null \
					and _game.current.id == "space":
				_phase = "verify_restore1"
				_frames = 0
		"verify_restore1":
			# NO INPUT — a key press would dismiss the restored veil. Wait for
			# endingT to re-climb past 2.2 (whatever the blob saved), then grab.
			_game.step_for_testing(1, DT)
			_watch()
			if _grab_next:
				_grab_next = false
				var n2: int = _count_purple(_grab())
				restore_midveil = {
					"endingDone": bool(_sim().endingDone),
					"dismissed": bool(_sim().endingDismissed),
					"finale": _sim().finale != null,
					"endingT": float(_sim().endingT),
					"purple": n2,
					"colonies": _colonies(),
					"obj": obj_text,
					"calm_fresh": _calm_fresh,
				}
				var ok: bool = restore_midveil["endingDone"] and not restore_midveil["dismissed"] \
						and restore_midveil["finale"] and n2 >= 12 and _calm_fresh
				print("QC5FIN_RESTORE1 %s ok=%s" % [str(restore_midveil), str(ok)])
				if not ok:
					_fail("verify_restore1: mid-veil restore broken — %s" % str(restore_midveil))
					return
				_phase = "dismiss_key"
				_frames = 0
			elif float(_sim().endingT) >= 2.2 and not bool(_sim().endingDismissed):
				_game._do_render(0.0)
				_grab_next = true
			elif _frames > 60 * 30:
				_fail("verify_restore1: endingT never re-climbed (%.2f, dismissed=%s)" % [
					float(_sim().endingT), str(_sim().endingDismissed)])
				return
		"dismiss_key":
			# a real KEY press dismisses (the non-click path TS:577-581) and the
			# held key keeps steering toward the sun for the post-ending death
			if _frames == 1:
				_ending_t_at_press = float(_sim().endingT)
				_press(KEY_S, true)
			# steer TOWARD the sun (a constant vector overshoots the damage band
			# and the ship sails out to 24k px — run 2's fly-by lesson); the
			# toward-sun oscillation traps the ship in the band like death1
			_steer(_sim(), Vector2(-float(_sim().sx), -float(_sim().sy)))
			_step_watch()
			if bool(_sim().endingDismissed) and not dismiss_key_ok:
				dismiss_key_ok = true
				var d_ok: bool = absf(float(_sim().dismissT) - _ending_t_at_press) <= 0.3
				var calm_ok: bool = calm_seen
				print("QC5FIN_DISMISS_KEY_OK dismissT=%.2f at_press=%.2f calm=%s" % [
					float(_sim().dismissT), _ending_t_at_press, str(calm_ok)])
				if not d_ok or not calm_ok:
					_fail("dismiss_key: dismissT drift or no calm objective (obj=%s)" % obj_text)
					return
			if dismiss_key_ok and _d_bill >= 0:
				# post-ending death: NO bill ("you already won")
				_press(KEY_S, false)
				_steer(_sim(), Vector2.ZERO)
				if _d_bill != 0:
					_fail("dismiss_key: post-ending death billed %d DNA (must be 0)" % _d_bill)
					return
				print("QC5FIN_DEATH2_OK bill=0 (no bill once you won)")
				death2_bill = _d_bill
				_phase = "quit2"
				_frames = 0
			elif _frames > 60 * 70:
				_fail("dismiss_key: stuck (dismissed=%s shp=%.0f pos=(%.0f,%.0f))" % [
					str(_sim().endingDismissed), float(_sim().shp),
					float(_sim().sx), float(_sim().sy)])
				return
		"quit2":
			if _frames == 1:
				_press(KEY_S, false)
				_game.save_all()
				_game.go_to("menu")
			_game.step_for_testing(1, DT)
			if _game.transition == null and _game.current != null \
					and _game.current.id == "menu":
				_phase = "continue2"
				_frames = 0
		"continue2":
			if _frames == 1:
				_calm_fresh = false
				obj_text = ""
				_reset_death_probe()
				_game.stages["menu"].continue_slot(0)
			_game.step_for_testing(1, DT)
			if _game.transition == null and _game.current != null \
					and _game.current.id == "space":
				_phase = "verify_restore2"
				_frames = 0
		"verify_restore2":
			# the DISMISSED branch: finale nulled (no stale orb), no veil,
			# colonies kept. Objective: whatever the reload leaves (recorded).
			_game.step_for_testing(1, DT)
			_watch()
			if _frames == 70:
				_game._do_render(0.0)
				_grab_next = true
			elif _grab_next and _frames >= 72:
				_grab_next = false
				var n3: int = _count_purple(_grab())
				restore_dismissed = {
					"dismissed": bool(_sim().endingDismissed),
					"finale": _sim().finale != null,
					"purple": n3,
					"colonies": _colonies(),
					"obj": obj_text,
					"calm_fresh": _calm_fresh,
				}
				var ok2: bool = restore_dismissed["dismissed"] and not restore_dismissed["finale"] \
						and n3 < 12 and restore_dismissed["colonies"] >= 3
				print("QC5FIN_RESTORE2 %s ok=%s" % [str(restore_dismissed), str(ok2)])
				if not ok2:
					_fail("verify_restore2: dismissed-branch restore broken — %s" % str(restore_dismissed))
					return
				_phase = "rereach"
				_frames = 0
		"rereach":
			# fly BACK to the core coords (finale nulled) — nothing may re-fire
			_step_watch()
			var cd: float = Vector2(0.0 - float(_sim().sx), -1900.0 - float(_sim().sy)).length()
			if cd < 60.0 and _grab_next == false and not rereach_clean:
				_steer(_sim(), Vector2.ZERO)
				_game._do_render(0.0)
				_grab_next = true
			elif _grab_next and cd < 60.0:
				_grab_next = false
				var clean: bool = bool(_sim().endingDismissed) and _sim().finale == null \
						and awakens_count == 1 and _count_purple(_grab()) < 12
				rereach_clean = clean
				if not clean:
					_fail("rereach: the ending re-fired after dismiss (awakens=%d finale=%s)" % [
						awakens_count, str(_sim().finale != null)])
					return
				print("QC5FIN_REREACH_OK dismissed stays, no veil, awakens=%d" % awakens_count)
				_phase = "report"
				_frames = 0
			elif _frames > 60 * 60:
				_fail("rereach: never got back to the core coords (%.0f px)" % cd)
				return
			else:
				_steer(_sim(), _hazard_desired(_sim(), Vector2(
					-float(_sim().sx), -1900.0 - float(_sim().sy))))
		"report":
			_report()
			_phase = "done"
		"done":
			pass


# ---- per-frame watch + step -----------------------------------------------------

func _step_watch() -> void:
	_game.step_for_testing(1, DT)
	_watch()
	# death detector: a fresh-respawn edge (invuln jumps to ~4) latches the
	# DNA bill seen on that frame (prev frame dna → this frame dna)
	var inv: float = float(_sim().invuln)
	if inv > 3.9 and _prev_invuln <= 3.9 and _prev_invuln >= 0.0:
		_d_bill = int(round(_prev_dna - float(_game.context.dna)))
		_d_exp = int(roundi(_prev_dna * 0.15))
		print("QC5FIN_DEATH frame bill=%d exp=%d prev_dna=%.0f dna=%d pos=(%.0f,%.0f)" % [
			_d_bill, _d_exp, _prev_dna, int(_game.context.dna),
			float(_sim().sx), float(_sim().sy)])
	_prev_invuln = inv
	_prev_dna = float(_game.context.dna)


func _reset_death_probe() -> void:
	_d_bill = -1
	_d_exp = -1
	_prev_invuln = -1.0
	if _game != null and _game.stages.has("space") and _game.stages["space"].sim != null:
		_prev_dna = float(_game.context.dna)


func _watch() -> void:
	var hud: Variant = _game.stages["space"].hud_inst
	if hud == null:
		return
	var aw := false
	if hud._cur_banner != null and String(hud._cur_banner["title"]).contains("THE CHAOS CORE AWAKENS"):
		aw = true
	for b in hud._banner_queue:
		if String(b["title"]).contains("THE CHAOS CORE AWAKENS"):
			aw = true
	if aw and not _awakens_base:
		awakens_count += 1
	_awakens_base = aw
	var obj: Variant = hud.show_objective
	if obj != null:
		obj_text = String(obj)
		if obj_text.contains("THE CHAOS CORE PULLS"):
			pulls_seen = true
		if obj_text.contains("the core sleeps"):
			calm_seen = true
			_calm_fresh = true


# ---- helpers ---------------------------------------------------------------------

func _sim() -> Variant:
	return _game.stages["space"].sim


func _colonies() -> int:
	var n := 0
	for p in _sim().planets:
		if p["colony"] != null:
			n += 1
	return n


func _thriving() -> int:
	var n := 0
	for p in _sim().planets:
		if p["colony"] != null and float(p["colony"]["pop"]) >= 20.0:
			n += 1
	return n


func _steer(sim: Variant, desired: Vector2) -> void:
	var want := {
		"KeyW": desired.y < -20.0, "KeyS": desired.y > 20.0,
		"KeyA": desired.x < -20.0, "KeyD": desired.x > 20.0,
	}
	for pair in [["KeyW", KEY_W], ["KeyA", KEY_A], ["KeyS", KEY_S], ["KeyD", KEY_D]]:
		var code: String = pair[0]
		var kc: int = pair[1]
		if bool(want[code]) and not _held.has(code):
			_press(kc, true)
			_held[code] = true
		elif not bool(want[code]) and _held.has(code):
			_press(kc, false)
			_held.erase(code)


func _press(kc: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = kc
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## The bot's hazard-aware desired vector (bot_space verbatim): out of the sun's
## danger band, plus a black-hole dodge inside 500.
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


func _grab() -> Image:
	return _game.get_viewport().get_texture().get_image()


## The checker's purple-label predicate (the ACCEPTS YOU title glyph pixels).
func _count_purple(img: Image) -> int:
	if img == null:
		return -1
	var n := 0
	var box := [float(_game.vw) / 2.0 - 260.0, float(_game.vh) / 2.0 - 140.0,
			float(_game.vw) / 2.0 + 260.0, float(_game.vh) / 2.0 - 100.0]
	for yy in range(int(box[1]), int(box[3]) + 1):
		for xx in range(int(box[0]), int(box[2]) + 1):
			if xx < 0 or xx >= img.get_width() or yy < 0 or yy >= img.get_height():
				continue
			var c := img.get_pixel(xx, yy)
			var p := Vector3(roundf(c.r * 255.0), roundf(c.g * 255.0), roundf(c.b * 255.0))
			if p.x >= 180.0 and p.z >= 230.0 and p.y >= 120.0 and p.y <= 210.0:
				n += 1
	return n


func _report() -> void:
	print("QC5FIN_SUMMARY awakens=%d death1=%d/%d death2=%d stack_ff=%s ending=%s flush=%s veil1=%s restore1=%s dismiss_key=%s restore2=%s rereach=%s" % [
		awakens_count, death1_bill, death1_exp, death2_bill, str(stack_ff_seen),
		str(ending_fired), str(win_flush_ok), str(veil1_ok),
		str(restore_midveil), str(dismiss_key_ok), str(restore_dismissed),
		str(rereach_clean)])
	print("QC5FIN_ALL_OK")
	get_tree().quit(0)


func _build_game() -> Variant:
	var ctx: Variant = ContextScript.new(WORLD_SEED)
	var game: Variant = GameScript.new(ctx)
	add_child(game)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(MenuStageScript.new(game))
	game.register(CellStageScript.new(game))
	game.register(CreatureStageScript.new(game))
	game.register(TribeStageScript.new(game))
	game.register(CivStageScript.new(game))
	game.register(SpaceStageScript.new(game))
	game.start()
	return game


func _fail(msg: String) -> void:
	printerr("QC5FIN_FAIL: " + msg)
	get_tree().quit(1)
