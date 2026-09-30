# Creature-stage scene test (xvfb, Compatibility renderer) — tasks 7 + 10.
# Boots a REAL Game with a pinned world seed + pinned player genome (size 1.0,
# hue 120, legs 4, spots+fur, no tail), enters the creature stage, and captures
# the task-10 moment suite plus the task-7 fixtures via get_viewport()
# .get_texture(). Every moment freezes the sim (or polls a live window to its
# pinned instant) and is checked by ≥ 3 structural pixel asserts in
# tools/visual_check_creature_scene.py (probes.json carries the live-camera
# anchors — the TS manual transform formula — computed HERE):
#
#   creature_arrival.png         — the shore arrival banner card over the day
#                                  spawn (hud banner panel/title/sub)
#   creature_meadow_a/b.png      — day meadow, the full creature mid-gait:
#                                  gait pinned A vs A+π/2 (feet move, torso twin)
#   creature_day.png             — the settled day frame (task 7: lawn/sky/
#                                  vignette/HP-bar)
#   creature_zsort.png           — Ruling 14 fixture: the hue-15 ent at z 100
#                                  draws ABOVE the player at z 50 (task 7)
#   creature_charm.png           — the charm minigame UI mid-hits (beat bar
#                                  panel/zone/marker/title, hits pinned at 1)
#   creature_night.png           — night raid moment: dayPhase 0.7 (isNight
#                                  window) — overlay dim, fireflies, stars
#   creature_death.png           — the death card (overlay dim vs day, THE
#                                  ISLAND RECLAIMS YOU, the player gone)
#   creature_volcano.png         — volcano aftermath through the REAL
#                                  scheduler warn→apply: lava hazards + smoke
#   creature_stampede.png        — the stampede herd through the REAL
#                                  scheduler: ≥ 2 herd bodies + ground shadows
#   creature_editor_before/.png  — the editor open in creature (dim vs before,
#                                  panels, blue DONE, DNA footer)
#
# Anchors for the pixel probes are computed HERE from the rig metrics + the
# live camera (the TS manual transform formula) and passed to the checker via
# probes.json. The 12 task-7 asserts stay verbatim-green. Chaos moments drive
# real chaos events through the sim's scheduler (trigger → warn window →
# apply) and freeze the frame AFTER apply. RID hygiene: the painter's three
# caller-owned RIDs are freed by the CreatureItem each repaint/teardown (the
# pooled items never stack).
# Run: tools/test_creature_scene.sh (one-command entry).
extends Node2D

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const RigScript := preload("res://src/gfx/creature_rig.gd")

const SEED := 20260930
const OUT_DIR := "user://visual_capture"
const TIMEOUT_FRAMES := 3600
const Z_TO_Y := 0.62

var game: Variant = null
var _phase := "boot"
var _frames := 0
var _probe := {}
var _day_time := 0.0
var _death_start := 0.0
var _herd_seen := false
var _tp_sim := -1.0e9   # sim.time of the last player-to-the-lane fixture teleport


func _ready() -> void:
	var ctx: Variant = ContextScript.new(SEED)
	# pinned player genome: big green herbivore (the z-sort probe's GREEN side)
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.0
	g["hue"] = 120
	g["sat"] = 0.55
	g["pattern"] = "spots"
	g["coat"] = "fur"
	g["tail"] = false
	g["legs"] = 4
	g["arms"] = 0
	g["eyes"] = 2
	g["diet"] = "herbivore"
	g["jaw"] = 0
	g["spikes"] = 0
	g["horns"] = 0
	g["wings"] = 0
	ctx.genome = g
	game = GameScript.new(ctx)
	add_child(game)
	game.register(CreatureStageScript.new(game))
	game.switch_stage("creature")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _fail(msg: String) -> void:
	printerr("VISUAL_TEST_FAIL: %s (phase %s, frame %d)" % [msg, _phase, _frames])
	get_tree().quit(1)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout (invuln=%s cam=%s)" % [str(game.current.sim.invuln), str(game.cam.x)])
		return
	var st: Variant = game.current.sim
	var hud: Variant = game.current.hud_inst
	match _phase:
		"boot":
			# converge onto the spawn while the arrival banner is still up
			# (ttl 5 s from on_enter; the follow converges in ~1 s)
			var cam_converged: bool = absf(game.cam.x - st.px) < 1.0 \
					and absf(game.cam.y - st.pz * Z_TO_Y) < 1.0
			if cam_converged:
				if hud._cur_banner == null:
					_fail("the arrival banner expired before the card capture")
					return
				_phase = "arrival_arm"
		"arrival_arm":
			# the banner card's own geometry (hud.gd draw: panel min(560,
			# vw·0.8) at y 70..144, title baseline 98, sub baseline 124)
			var bw: float = minf(560.0, game.vw * 0.8)
			_probe["arrival"] = {
				"panel": [game.vw / 2.0 - bw / 2.0, 70.0, game.vw / 2.0 + bw / 2.0, 144.0],
				"title": [78.0, 104.0],
				"sub": [112.0, 132.0],
			}
			_phase = "arrival_shot"  # next frame's texture holds the drawn state
		"arrival_shot":
			_capture("creature_arrival.png")
			_phase = "settle"
		"settle":
			# settle: banner gone, arrival invuln decayed (player paints
			# opaque), camera converged onto the player
			var cam2: bool = absf(game.cam.x - st.px) < 1.0 \
					and absf(game.cam.y - st.pz * Z_TO_Y) < 1.0
			if st.invuln <= 0.0 and cam2 \
					and hud._cur_banner == null and hud._banner_queue.is_empty():
				game.current.frozen = true
				_phase = "meadow_setup"
		"meadow_setup":
			# the day-meadow moment: the player ALONE in the live spawn world,
			# gait pinned mid-swing (frozen sim → the pose reads the pinned
			# gait; speed01 stays 0 so the torso is a determinism twin)
			st.ents.clear()
			st.gait = 0.9
			_meadow_probes(st)
			_phase = "meadow_a_arm"
		"meadow_a_arm":
			_phase = "meadow_a_shot"
		"meadow_a_shot":
			_capture("creature_meadow_a.png")
			st.gait = 0.9 + PI / 2.0
			_phase = "meadow_b_arm"
		"meadow_b_arm":
			_phase = "meadow_b_shot"
		"meadow_b_shot":
			_capture("creature_meadow_b.png")
			_phase = "fixture"
		"fixture":
			# Ruling 14 fixture: the player alone at z 50, a red ent at z 100.
			# The fixture world serves the day/zsort/night/charm/death captures
			# (a free llvmpipe determinism twin) and the lawn/sky/vignette/HP
			# asserts run without wild-ent noise. Nests park beyond the despawn
			# ring so the LIVE windows below (death/volcano/stampede) stay
			# free of maintainer spawns; the red ent is defanged (damage 0 —
			# damage is never rendered) so its bites cannot shake the death
			# window.
			st.pz = 50.0
			st.ents.clear()
			st.bushes.clear()
			st.bones.clear()
			for n in st.nests:
				n["x"] = 99999.0
				n["z"] = 20.0
			var eg: Dictionary = GenomeScript.default_genome()
			eg["size"] = 1.3
			eg["hue"] = 15
			eg["sat"] = 0.9
			eg["tail"] = false
			eg["legs"] = 4
			eg["pattern"] = "stripes"
			eg["coat"] = "plates"
			var ent: Dictionary = st.spawn_ent(null, st.px + 30.0, 100.0, eg)
			ent["facing"] = 1  # head away from the green probe
			ent["stats"]["damage"] = 0.0
			_probe["day_zsort"] = _compute_probes(st, ent)
			_phase = "day_arm"
		"day_arm":
			_phase = "day_shot"  # next frame's texture holds the drawn state
		"day_shot":
			_capture("creature_day.png")
			_day_time = float(st.time)
			_phase = "zsort_arm"
		"zsort_arm":
			_phase = "zsort_shot"  # determinism twin: same commands, one frame on
		"zsort_shot":
			_capture("creature_zsort.png")
			_phase = "charm_setup"
		"charm_setup":
			# the charm-UI moment mid-hits: the fixture ent is the live charm
			# target (58 px < 120, no size gate), the beat bar pinned at 1 hit
			# with the marker inside the zone
			st.try_charm()
			if not bool(st.charmActive) or st.charmTarget == null:
				_fail("try_charm did not arm on the fixture ent")
				return
			st.charmHits = 1
			st.charmMarker = 0.1
			st.charmMustExit = true
			_charm_probes()
			_phase = "charm_arm"
		"charm_arm":
			_phase = "charm_shot"
		"charm_shot":
			_capture("creature_charm.png")
			st.charmActive = false
			st.charmTarget = null
			_phase = "night_setup"
		"night_setup":
			st.dayPhase = 0.7  # inside the (0.55, 0.95) window
			# the fireflies' twinkle phase rides sim.time — pinned to a value
			# where 8 of the 20 deterministic flies sit bright (tw >= 0.9) in
			# the checker's scanned bands (computed from the TS formulas)
			st.time = 40.05
			_phase = "night_arm"
		"night_arm":
			_phase = "night_shot"
		"night_shot":
			_capture("creature_night.png")
			_phase = "death_setup"
		"death_setup":
			# the death-card moment: back to the day backdrop, then let the
			# REAL death path run (handle_death's fade + overlay) — the freeze
			# lands mid-fade (shake decayed, respawn at 1.8 not reached)
			st.dayPhase = 0.15
			st.time = _day_time
			st.php = 0.0
			_death_start = float(st.time)
			game.current.frozen = false
			_phase = "death_live"
		"death_live":
			if float(st.deathFade) >= 1.2:
				game.current.frozen = true
				_death_probes()
				_phase = "death_arm"
		"death_arm":
			_phase = "death_shot"
		"death_shot":
			_capture("creature_death.png")
			_phase = "volcano_setup"
		"volcano_setup":
			# revive + guard, then drive the REAL volcano through the
			# scheduler's warn→apply flow: trigger opens the 2.5 s warn, the
			# live sim converts it, apply schedules the 5 lava strikes on the
			# stage clock, the freeze lands after ≥ 3 hazards + the shake
			st.php = float(st.pmaxHp)
			st.deathFade = 0.0
			st.deathStarted = false
			st.invuln = 9999.0
			st.dayPhase = 0.15
			st.time = _day_time
			st.hazards.clear()
			st.timers.clear()
			if not bool(st.chaos.trigger("volcano", st,
					{"chaos": 0.15, "karma": 0.0, "stageTime": 0.0})):
				_fail("the volcano trigger failed")
				return
			game.current.frozen = false
			_phase = "volcano_live"
		"volcano_live":
			# freeze once TWO lava hazards are alive AND both in view: the
			# moment's asserts need exactly two anchored glows + the warm mass
			# + the smoke — not the full strike set. (The stricter "all five
			# landed" gates flaked on engine-frame pacing, and an early DIAG
			# read of "a strike timer vanished without firing" was an
			# INTERPRETATION error — the final M3 review traced the state to
			# the ttl-14 s hazard expiry landing while a hung gate kept
			# simulating (timers drain → fn always runs; hazards expire at
			# ttl exactly like TS CreatureStage.ts:504-506). No parity bug.
			# Any two of the five delays are ≤ 11 s apart inside the 14 s ttl,
			# so a 2-alive window ≥ 3 s ALWAYS exists — freezing on it is
			# race-free. Meteors are 'fire' kind — see _volcano_probes.)
			var lava_alive := 0
			for hz in st.hazards:
				if String(hz["kind"]) == "lava":
					lava_alive += 1
			if lava_alive >= 2 and _volcano_anchors_ready(st):
				game.current.frozen = true
				_volcano_probes(st)
				_phase = "volcano_arm"
		"volcano_arm":
			_phase = "volcano_shot"
		"volcano_shot":
			_capture("creature_volcano.png")
			_phase = "stampede_setup"
		"stampede_setup":
			st.hazards.clear()
			st.timers.clear()
			if not bool(st.chaos.trigger("stampede", st,
					{"chaos": 0.15, "karma": 0.0, "stageTime": 0.0})):
				_fail("the stampede trigger failed")
				return
			game.current.frozen = false
			_phase = "stampede_live"
		"stampede_live":
			# the herd (6 ents, applied after the warn) must close within
			# 450 px; a grazer herd wanders off its lane, so the harness
			# puppets the player next to the nearest herd ent every 2 SIM
			# seconds (a fixture move; the live cam follows). Both gates run on
			# sim.time — at this host's llvmpipe pacing (~5 sim-steps per
			# engine frame) an engine-frame settle of 100 would span 8+ sim
			# seconds and outlive the herd's 14 s lifespan; the 0.5 s sim
			# settle after the snap is pacing-free (task-10 review, Important 1).
			var count := 0
			var herd_i := -1
			var best := 1e9
			for i in st.ents.size():
				var e: Dictionary = st.ents[i]
				if e.has("lifespanStampede"):
					count += 1
					var d: float = absf(float(e["x"]) - float(st.px))
					if d < best:
						best = d
						herd_i = i
			if not _herd_seen:
				# the apply spawns exactly 6; the player's auto-bite may claim
				# one while the herd piles on (the real event interplay) — the
				# gate is ≥ 4 so a hunted herd still captures
				if count >= 4:
					_herd_seen = true
				elif count > 0:
					_fail("stampede herd count %d < 4" % count)
					return
			if _herd_seen and herd_i < 0:
				# the whole herd expired before two anchors were visible — a
				# clean triage line instead of ents[-1] spam (guard also keeps
				# the teleport branch below index-safe)
				_fail("the herd expired before the freeze (candidates %d)"
						% _herd_picks(st).size())
				return
			if _herd_seen and best < 500.0 and st.time - _tp_sim > 0.5 \
					and _herd_picks(st).size() >= 2:
				# 500 px: at the world edge the herd parks at ±2900 while the
				# puppet's clamp holds exactly 350 away — a strict 350 gate
				# never fires (timeout). Visibility is the anchors-ready
				# gate's job, not the distance gate's.
				game.current.frozen = true
				_herd_probes(st)
				_phase = "stampede_arm"
			elif _herd_seen and herd_i >= 0 and st.time - _tp_sim > 2.0:
				# teleport AHEAD of the herd (in its running path) and SNAP the
				# camera (the follow would take ~1.7 s to reconverge — a
				# running herd outruns it; the snap equals the converged state,
				# so the anchors computed next frame are exact). AHEAD, not
				# behind: the herd covers ~300 px during the 100-frame settle,
				# so a puppet parked behind watches the herd run away and best
				# never re-enters the gate (the east-edge timeout signature).
				var lane: Dictionary = st.ents[herd_i]
				var dir_s: float = signf(float(lane["tx"]))
				# 250 ahead, not 350: the second herd ent trails 90 px, and at
				# zoom 1.15 a 350 gap put its body anchor at screen x ~70 —
				# outside the 92 px anchor band — so a slow-crawling herd never
				# brought a second candidate in view inside its 14 s lifespan.
				st.px = clampf(float(lane["x"]) + dir_s * 250.0, -2900.0, 2900.0)
				st.pz = clampf(float(lane["z"]), -200.0, 240.0)
				game.cam.snap(st.px, st.pz * Z_TO_Y)
				_tp_sim = st.time
		"stampede_arm":
			_phase = "stampede_shot"
		"stampede_shot":
			_capture("creature_stampede.png")
			_phase = "editor_before_arm"
		"editor_before_arm":
			_phase = "editor_before_shot"
		"editor_before_shot":
			_capture("creature_editor_before.png")
			game.editor["show"].call("creature")
			_phase = "editor_open"
		"editor_open":
			# the deferred draw populates row_rects — wait one draw pass
			if game.current.editor_inst.row_rects.size() > 0 \
					and game.current.editor_inst.close_rect.get("x", 0.0) > 0.0:
				_editor_probes()
				_phase = "editor_arm"
		"editor_arm":
			_phase = "editor_shot"
		"editor_shot":
			_capture("creature_editor.png")
			game.editor["close"].call()
			_phase = "check"
		"check":
			_phase = "done"
			_write_probes()
			_run_checker()


## Screen anchors for the checker's probes: the TS manual camera transform
## (cam.gd to_world's inverse) — (world − cam)·zoom + center. Shake is 0 at
## capture (the death/volcano windows wait out their shakes; frozen frames
## have none).
func _world_to_screen(wx: float, wy: float) -> Vector2:
	return Vector2(
			(wx - game.cam.x) * game.cam.zoom + game.vw / 2.0,
			(wy - game.cam.y) * game.cam.zoom + game.vh / 2.0)


## Body-center screen anchors for the fixture pair: the rig metrics give
## body_y = −leg_h − 0.72·body_r above the pose (feet) anchor.
func _compute_probes(st: Variant, ent: Dictionary) -> Dictionary:
	var eg: Dictionary = ent["genome"]
	var pg: Dictionary = game.context.genome
	# the ent is offset +30 world x from the player
	var player_feet := _world_to_screen(st.px, st.pz * Z_TO_Y)
	var ent_feet := _world_to_screen(st.px + 30.0, 100.0 * Z_TO_Y)
	var p_m: Dictionary = RigScript._metrics(pg, {"scale": 2.1})
	var e_m: Dictionary = RigScript._metrics(eg, {"scale": 2.1})
	var player_cy: float = player_feet.y + float(p_m["body_y"]) * game.cam.zoom
	var ent_cx: float = ent_feet.x
	var ent_cy: float = ent_feet.y + float(e_m["body_y"]) * game.cam.zoom
	return {
		"px": player_feet.x,
		"player_cy": player_cy,
		"ent_cx": ent_cx,
		"ent_cy": ent_cy,
		# the ent's tapered tail end reaches ~66px left of its center on
		# screen; the player's own body edge starts ~70px left of its
		# center — the probe sits in the visible green sliver
		"green_x": player_feet.x - 58.0,
	}


## The day-meadow moment's anchors: the player's body center + the gait
## differential boxes (feet swing, torso still) from the rig metrics.
func _meadow_probes(st: Variant) -> void:
	var pg: Dictionary = game.context.genome
	var feet := _world_to_screen(st.px, st.pz * Z_TO_Y)
	var p_m: Dictionary = RigScript._metrics(pg, {"scale": 2.1})
	var body: Vector2 = Vector2(feet.x, feet.y + float(p_m["body_y"]) * game.cam.zoom)
	_probe["meadow"] = {
		"body": [body.x, body.y],
		"feet": [feet.x, feet.y],
		# the leg/foot swing zone (stride ±3px world ≈ ±3.5px screen at
		# speed01 0, plus the hoof caps) and the gait-invariant torso band
		# (above the hip attaches at +0.45·body_r — the knees/legs stay out)
		"feet_box": [feet.x - 26.0, feet.y - 30.0, feet.x + 26.0, feet.y + 5.0],
		"torso_box": [body.x - 20.0, body.y - 14.0, body.x + 20.0, body.y + 2.0],
	}


## The charm beat-bar geometry — the scene's own draw numbers
## (creature_stage.gd _draw_ui, TS CreatureStage.ts:1493-1508).
func _charm_probes() -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	var st: Variant = game.current.sim
	var tut: Variant = game.current.tutorial
	var tut_active: bool = tut != null and bool(tut.active)
	var by: float = (vh - 256.0) if tut_active else (vh - 170.0)
	var zone: float = (0.35 - float(st.charmHits) * 0.05) * 130.0
	_probe["charm"] = {
		# the panel's left-edge padding strip (the centered title glyphs cross
		# the middle of the bar)
		"panel": [vw / 2.0 - 134.0, by + 8.0],
		"zone": [vw / 2.0 - zone, by, vw / 2.0 + zone, by + 16.0],
		"marker_x": vw / 2.0 + float(st.charmMarker) * 130.0,
		"marker_band": [by - 3.0, by + 19.0],
		"title_band": [by - 24.0, by - 10.0],
	}


## The death card's bands (creature_stage.gd _draw_ui, TS:1510-1516).
func _death_probes() -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	_probe["death"] = {
		"title_band": [vh / 2.0 - 42.0, vh / 2.0 + 2.0],
		"sub_band": [vh / 2.0 + 8.0, vh / 2.0 + 34.0],
		"green_probe": [_probe["day_zsort"]["green_x"], _probe["day_zsort"]["player_cy"]],
	}


## True once two LAVA hazards project in-view (the freeze gate + the anchor
## pick share this). LAVA-only: the live phases before the trigger run the
## real chaos deck, so an earthquake's fire hazards (r 46, dimmer orange) can
## be alive too — a fire pick failed the warm-box assert run-to-run.
func _volcano_lava_picks(st: Variant) -> Array:
	var picks: Array = []
	for hz in st.hazards:
		if String(hz["kind"]) != "lava":
			continue
		var s: Vector2 = _world_to_screen(float(hz["x"]), float(hz["z"]) * Z_TO_Y)
		# in-view gate (the herd anchors' shape): the box is 11 px wide, keep
		# the center ≥ 8% inside both axes so patch_mean never reads off-screen
		if s.x < game.vw * 0.08 or s.x > game.vw * 0.92 \
				or s.y < 24.0 or s.y > game.vh - 24.0:
			continue
		picks.append([absf(s.x - game.vw / 2.0), s.x, s.y])
	picks.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	return picks


func _volcano_anchors_ready(st: Variant) -> bool:
	return _volcano_lava_picks(st).size() >= 2


## The volcano aftermath's anchors: the two in-view LAVA hazards nearest the
## screen center (the glow ellipse rx = r = 64, ry = 32 world → screen).
func _volcano_probes(st: Variant) -> void:
	var picks: Array = _volcano_lava_picks(st)
	if picks.size() < 2:
		_fail("fewer than 2 visible lava hazards at the freeze")
		return
	var hazards: Array = []
	for i in mini(2, picks.size()):
		hazards.append([float(picks[i][1]), float(picks[i][2])])
	_probe["volcano"] = {
		"hazards": hazards,
		"smoke": {"x": float(hazards[0][0]), "y0": float(hazards[0][1]) - 64.0,
				"y1": float(hazards[0][1]) - 12.0, "half_w": 38.0},
	}


## The stampede herd's anchors: the two herd ents nearest the screen center
## that are actually IN VIEW (the herd trails 90 world-px apart — the tail
## ents sit off-screen), each with its body center + feet anchor.
## The live in-view herd candidates (the freeze gate and the anchor pick
## share one scan): live herd ents only — a killed member lies rotated/fading,
## not a body pin — with the body anchor inside the visible band.
func _herd_picks(st: Variant) -> Array:
	var picks: Array = []
	for e in st.ents:
		if not e.has("lifespanStampede"):
			continue
		if e.has("corpseT") or float(e["hp"]) <= 0.0:
			continue
		var feet: Vector2 = _world_to_screen(float(e["x"]), float(e["z"]) * Z_TO_Y)
		var e_m: Dictionary = RigScript._metrics(e["genome"], {"scale": 2.1})
		var body := Vector2(feet.x, feet.y + float(e_m["body_y"]) * game.cam.zoom)
		if body.x < game.vw * 0.08 or body.x > game.vw * 0.92 \
				or body.y < 60.0 or body.y > game.vh - 60.0:
			continue
		picks.append([absf(body.x - game.vw / 2.0), body.x, body.y, feet.x, feet.y])
	picks.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	return picks


func _herd_probes(st: Variant) -> void:
	var picks: Array = _herd_picks(st)
	if picks.size() < 2:
		_fail("fewer than 2 herd ents visible at the freeze (candidates %d)" % picks.size())
		return
	# the second anchor must be a DISTINCT ent — a hunting herd piles onto the
	# player and two bodies can overlap; fall back to the nearest pair when no
	# separated ent exists
	var second := 1
	for i in range(1, picks.size()):
		if absf(float(picks[i][1]) - float(picks[0][1])) >= 40.0:
			second = i
			break
	var ents: Array = []
	for i in [0, second]:
		ents.append([float(picks[i][1]), float(picks[i][2]),
				float(picks[i][3]), float(picks[i][4])])
	_probe["stampede"] = {"ents": ents}


## The editor overlay's anchors (editor.gd draw geometry, read live).
func _editor_probes() -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	var ed: Variant = game.current.editor_inst
	var left_w: float = minf(460.0, vw * 0.42)
	var left_h: float = vh - 70.0 - 24.0
	var right_x: float = 24.0 + left_w + 16.0
	var fy: float = 70.0 + left_h - 52.0
	var close: Dictionary = ed.close_rect
	_probe["editor"] = {
		# the left panel's bottom-left corner — the preview creature (drawn at
		# the panel's center) and the stats readout stay clear of it
		"panel": [24.0 + 40.0, 70.0 + left_h - 24.0],
		"close": [(float(close["x"]) + float(close["w"]) / 2.0),
				float(close["y"]) + float(close["h"]) / 2.0],
		"footer": [right_x + 14.0, fy + 6.0, right_x + 320.0, fy + 32.0],
	}


func _capture(file_name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		_fail("save_png %s → %s" % [file_name, str(err)])
	else:
		print("captured %s/%s" % [OUT_DIR, file_name])


func _write_probes() -> void:
	_probe["vw"] = game.vw
	_probe["vh"] = game.vh
	var f := FileAccess.open(OUT_DIR + "/probes.json", FileAccess.WRITE)
	if f == null:
		_fail("cannot write probes.json")
		return
	f.store_string(JSON.stringify(_probe))
	f.close()


func _run_checker() -> void:
	var checker := ProjectSettings.globalize_path("res://tools/visual_check_creature_scene.py")
	var args: Array = [checker, ProjectSettings.globalize_path(OUT_DIR + "/probes.json")]
	for name in ["creature_arrival", "creature_meadow_a", "creature_meadow_b",
			"creature_day", "creature_zsort", "creature_charm", "creature_night",
			"creature_death", "creature_volcano", "creature_stampede",
			"creature_editor_before", "creature_editor"]:
		args.append(ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png"))
	var output: Array = []
	var code := OS.execute("python3", args, output, true)
	for line in output:
		print(String(line).strip_edges())
	if code != 0:
		printerr("VISUAL_TEST_FAIL: visual_check_creature_scene.py exited %d" % code)
		get_tree().quit(1)
	else:
		print("VISUAL_TEST_OK")
		get_tree().quit(0)
