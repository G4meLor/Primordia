# Tribe-stage scene test (xvfb, Compatibility renderer) — M4 task 4.
# Boots a REAL Game with a pinned world seed + pinned chief genome (size 1.0,
# hue 120, green herbivore), enters the REGISTERED tribe stage, and captures
# the moment suite via get_viewport().get_texture(). Every moment freezes the
# sim (stage.frozen — render without stepping) at a sim-time/state-conditioned
# gate (NO engine-frame-count gates — the M3 volcano lesson) and is checked by
# ≥ 3 structural pixel asserts in tools/visual_check_tribe_scene.py
# (probes.json carries the live-camera anchors — the TS manual transform
# formula — computed HERE):
#
#   tribe_village_day.png    — day village: lawn band, hut walls/roof/door,
#                              the great totem mid-build, stockpile panel +
#                              lit build buttons
#   tribe_raid.png           — the raid through the REAL raid clock
#                              (raidTimer → launchRivalRaid): the danger
#                              banner + the hue-5 war party bodies
#   tribe_night.png          — night dayPhase 0.7 (isNight window): the flat
#                              rgba(10,10,40,0.4) overlay dims the frame,
#                              festival campfire glows, backdrop stars
#   tribe_death.png          — the death card (red veil, THE CHIEF HAS
#                              FALLEN, the chief body gone at fade > 0.4)
#   tribe_zsort.png          — Ruling 14 class: the red tribesman at z 100
#                              draws OVER the green chief at z 60
#   tribe_totem.png          — totem raising at progress 75 (task 7): the
#                              progress-scaled pole, BOTH milestone discs
#                              (p > 0.3 red / p > 0.6 blue), the TOTEM label
#                              (the TS:1292 quirk — round(p) of the 0..1
#                              fraction reads 1%)
#   tribe_beast.png          — the great beast (task 7): the hue-300
#                              plates-coat body at scale 2.6, the 48×4 hp
#                              bar, the wide purple run
#   tribe_camp.png           — a rival camp (task 7): the translucent disc
#                              tint over the lawn, the 3 totem poles + caps,
#                              the camp name
#   tribe_hutcon.png         — hut construction (task 7): the buildT > 0 hut
#                              at globalAlpha 0.5 (dimmer wall + roof vs the
#                              built twin), its label at FULL alpha (the TS
#                              after-restore quirk)
#   tribe_toast_before/.png  — the toast-inset pair: a hud toast fired with
#                              toast_inset 190 draws at vh−30−190, clear of
#                              the stockpile panel + build buttons
#
# Anchors for the pixel probes are computed HERE from the rig metrics + the
# live camera (the TS manual transform formula) and passed to the checker via
# probes.json. Freeze discipline: the raid arms on the REAL raid clock (state
# gates: raidActive + the war party alive + anchors in view + a 0.5 SIM-second
# settle), every other moment is a frozen-fixture capture. RID hygiene: the
# painter's three caller-owned RIDs are freed by the CreatureItem each
# repaint/teardown (the pooled items never stack).
# Run: tools/test_tribe_scene.sh (one-command entry).
extends Node2D

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const TribeStageScript := preload("res://src/game/tribe/tribe_stage.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const RigScript := preload("res://src/gfx/creature_rig.gd")

const SEED := 20261001
const OUT_DIR := "user://visual_capture_tribe"
const TIMEOUT_FRAMES := 7200
const Z_TO_Y := 0.62

var game: Variant = null
var _phase := "boot"
var _frames := 0
var _probe := {}
var _day_time := 0.0
var _snap_sim := -1.0e9   # sim.time of the last raid camera snap
var _raid_state := 0      # 0 = waiting for the launch, 1 = puppet settled
var _toast_fired := false


func _ready() -> void:
	var ctx: Variant = ContextScript.new(SEED)
	# pinned chief genome: big green herbivore (the z-sort probe's GREEN side;
	# the raiders clone it with hue 5 — the RED war party)
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
	game.register(TribeStageScript.new(game))
	game.switch_stage("tribe")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _fail(msg: String) -> void:
	printerr("VISUAL_TEST_FAIL: %s (phase %s, frame %d)" % [msg, _phase, _frames])
	get_tree().quit(1)


func _st() -> Variant:
	return game.current.sim


func _stage() -> Variant:
	return game.current


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout (cam=%s raidActive=%s)" % [str(game.cam.x), str(_st().raidActive)])
		return
	var st: Variant = _st()
	var stage: Variant = _stage()
	match _phase:
		"boot":
			# converge onto the chief (follow rate 4 — no banner to catch, the
			# tribe stage fires no arrival card)
			var converged: bool = absf(game.cam.x - st.px) < 1.0 \
					and absf(game.cam.y - st.pz * Z_TO_Y) < 1.0
			if converged:
				stage.frozen = true
				_phase = "village_setup"
		"village_setup":
			# the day-village moment: a well-off village with the great totem
			# mid-build and both build buttons lit (wood ≥ 40, food ≥ 100 +
			# wood ≥ 80). The chief parks EAST of the hut so his green body
			# clears the hut/totem anchor column; the pack founders park out of
			# the frame (the moment asserts lawn/hut/totem/panels).
			st.food = 120.0
			st.wood = 90.0
			st.totem = {"progress": 45.0, "active": true}
			for i in st.tribe.size():
				st.tribe[i]["x"] = -700.0 + float(i) * 1400.0
				st.tribe[i]["z"] = 60.0
				st.tribe[i]["vx"] = 0.0
				st.tribe[i]["vz"] = 0.0
				st.tribe[i]["gait"] = 0.9
			st.px = 60.0
			st.pz = 60.0
			game.cam.snap(st.px, st.pz * Z_TO_Y)
			_village_probes()
			_phase = "village_arm"
		"village_arm":
			_phase = "village_shot"  # next frame's texture holds the drawn state
		"village_shot":
			_capture("tribe_village_day.png")
			_day_time = float(st.time)
			_phase = "raid_arm_live"
		"raid_arm_live":
			# the raid through the REAL clock: raidTimer 0.5 → the raid clock
			# fires launchRivalRaid (wave 2 + rng 0..2 warriors at the rival
			# camp, ~1300+ px away). Freeze gates on raid STATE + a 0.5
			# SIM-second settle (no engine-frame counts — the M3 lesson).
			stage.frozen = false
			st.raidTimer = 0.5
			_snap_sim = float(st.time)  # raid-window start (fail-safe clock)
			_raid_state = 0
			_phase = "raid_live"
		"raid_live":
			# the stampede lesson: the live follow (rate 4) unwinds any camera
			# snap back toward the chief — PUPPET the chief next to the war
			# party instead and let the follow carry the camera there. The
			# puppet keeps 130 world px (the raid-touch kill ring is 40).
			if _raid_state == 0:
				if bool(st.raidActive) and st.rivalWarriors.size() >= 2:
					var c := _raid_centroid(st)
					st.px = c.x + 130.0
					st.pz = clampf(c.y / Z_TO_Y, -190.0, 230.0)
					_snap_sim = float(st.time)
					_raid_state = 1
				elif float(st.time) - _snap_sim > 10.0:
					_fail("the raid clock never fired (raidActive=%s warriors=%d)"
							% [str(st.raidActive), st.rivalWarriors.size()])
					return
			elif _raid_state == 1:
				# the snap equals the converged follow state; hold it every
				# frame until the settle elapses, then freeze on in-view picks
				game.cam.snap(st.px, st.pz * Z_TO_Y)
				if float(st.time) - _snap_sim >= 0.5 \
						and _raid_picks(st).size() >= 2:
					stage.frozen = true
					_raid_probes(st)
					if stage.hud_inst._cur_banner == null:
						_fail("the raid banner expired before the freeze")
						return
					_phase = "raid_arm"
		"raid_arm":
			_phase = "raid_shot"
		"raid_shot":
			_capture("tribe_raid.png")
			_phase = "night_setup"
		"night_setup":
			# the night moment: dayPhase 0.7 inside the (0.55, 0.95) window +
			# three festival-style campfires around the hut (the festival
			# event's spread-999 shape). The war party parks far away (cleared
			# — their glows must not pollute the fire anchors).
			st.rivalWarriors.clear()
			st.raidActive = false
			st.dayPhase = 0.7
			st.time = _day_time
			st.fires.clear()
			for i in 3:
				st.fires.append({"x": -40.0 + float(i) * 40.0,
						"z": 88.0 + float(i % 2) * 8.0, "ttl": 12.0, "spread": 999.0})
			for i in st.tribe.size():
				st.tribe[i]["x"] = 220.0 + float(i) * 40.0
				st.tribe[i]["z"] = 100.0
			st.px = 150.0
			st.pz = 60.0
			# the raid banner drains on HUD time (frame delta) — dismiss it so
			# the night/death/zsort captures carry no stale overlay
			game.hud["dismiss_banner"].call()
			game.cam.snap(st.px, st.pz * Z_TO_Y)
			_night_probes(st)
			_phase = "night_arm"
		"night_arm":
			_phase = "night_shot"
		"night_shot":
			_capture("tribe_night.png")
			_phase = "death_setup"
		"death_setup":
			# the death-card moment: back to the day backdrop, the death fade
			# fixture-set mid-fade (the render side only reads deathFade —
			# TS:1389; the real raid-touch path is sim-tested)
			st.dayPhase = 0.2
			st.time = _day_time
			st.deathFade = 1.2
			st.px = 0.0
			st.pz = 60.0
			game.cam.snap(st.px, st.pz * Z_TO_Y)
			_death_probes()
			_phase = "death_arm"
		"death_arm":
			_phase = "death_shot"
		"death_shot":
			_capture("tribe_death.png")
			_phase = "zsort_setup"
		"zsort_setup":
			# Ruling 14 fixture: the chief revived at z 60, a RED tribesman
			# (hue 15) at z 100 parked on the chief's body column — the
			# tribesman draws OVER the chief (ascending z). The other two
			# founders park off the anchor column.
			st.deathFade = 0.0
			st.dayPhase = 0.2
			st.time = _day_time
			st.fires.clear()
			st.px = 0.0
			st.pz = 60.0
			st.tribe[0]["genome"] = _red_genome()
			st.tribe[0]["x"] = 2.0
			st.tribe[0]["z"] = 100.0
			st.tribe[0]["facing"] = 1
			st.tribe[0]["carrying"] = null
			for i in range(1, st.tribe.size()):
				st.tribe[i]["x"] = 400.0 + float(i) * 60.0
				st.tribe[i]["z"] = 60.0
			game.cam.snap(st.px, st.pz * Z_TO_Y)
			_zsort_probes(st)
			_phase = "zsort_arm"
		"zsort_arm":
			_phase = "zsort_shot"
		"zsort_shot":
			_capture("tribe_zsort.png")
			_phase = "totem_setup"
		"totem_setup":
			# the totem-raising moment (task 7): progress 75 → p 0.75 — the
			# pole mid-build plus BOTH milestone discs (p > 0.3, p > 0.6) and
			# the TOTEM label (the TS:1292 quirk: round(p) of the 0..1
			# fraction reads 1%). The chief + founders park out of the column.
			stage.hud_inst._toasts.clear()
			game.hud["dismiss_banner"].call()
			st.totem = {"progress": 75.0, "active": true}
			st.deathFade = 0.0
			st.dayPhase = 0.2
			st.time = _day_time
			st.px = 600.0
			st.pz = 60.0
			for i in st.tribe.size():
				st.tribe[i]["x"] = -600.0 + float(i) * 80.0
				st.tribe[i]["z"] = 60.0
			game.cam.snap(st.px, st.pz * Z_TO_Y)  # the follow target keeps the snap
			game.cam.x = 0.0
			game.cam.y = 5.0
			_totem_probes()
			_phase = "totem_arm"
		"totem_arm":
			_phase = "totem_shot"
		"totem_shot":
			_capture("tribe_totem.png")
			_phase = "beast_setup"
		"beast_setup":
			# the beast-attack moment (task 7): the REAL spawnBeast genome
			# (ctx clone, size 2.1 / hue 300 / plates / eyes 4) repositioned
			# beside the hut, hp 420 → the full 48×4 bar. The chief parks
			# clear of the body anchors.
			st.beast = null
			st.spawn_beast()
			st.beast["x"] = 60.0
			st.beast["z"] = 60.0
			st.beast["hp"] = 420.0
			st.px = -200.0
			st.pz = 60.0
			game.cam.snap(st.px, st.pz * Z_TO_Y)
			game.cam.x = 0.0
			game.cam.y = 60.0 * Z_TO_Y
			_beast_probes()
			_phase = "beast_arm"
		"beast_arm":
			_phase = "beast_shot"
		"beast_shot":
			_capture("tribe_beast.png")
			_phase = "camp_setup"
		"camp_setup":
			# the rival-camp moment (task 7): the camp at (200, 60) — the
			# translucent disc, 3 totem poles + caps, the camp name. Resources
			# parked so the lawn band is clean around the tint pair.
			st.beast = null
			_park_camp_world(st)
			st.rivals[0]["x"] = 200.0
			st.rivals[0]["z"] = 60.0
			st.rivals[0]["hp"] = 100.0
			st.rivals[1]["x"] = 9999.0
			st.px = 700.0
			st.pz = 60.0
			game.cam.snap(st.px, st.pz * Z_TO_Y)
			game.cam.x = 200.0
			game.cam.y = 60.0 * Z_TO_Y
			_camp_probes(st)
			_phase = "camp_arm"
		"camp_arm":
			_phase = "camp_shot"
		"camp_shot":
			_capture("tribe_camp.png")
			_phase = "hutcon_setup"
		"hutcon_setup":
			# the hut-construction moment (task 7): the built starting hut at
			# (0, 80) beside a buildT-3 twin at (150, 80) — the unbuilt hut
			# draws at globalAlpha 0.5 (dim wall + roof over the SAME lawn
			# band) while its hp label stays at FULL alpha (the TS
			# after-restore quirk). The totem drops out (its column would
			# cross the built hut's wall probe).
			st.totem = {"progress": 0.0, "active": false}
			st.huts[0]["x"] = 0.0
			st.huts[0]["z"] = 80.0
			if st.huts.size() < 2:
				st.huts.append({"x": 150.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0,
						"pop": 0.0, "buildT": 0.0})
			st.huts[1]["x"] = 150.0
			st.huts[1]["z"] = 80.0
			st.huts[1]["hp"] = 100.0
			st.huts[1]["maxHp"] = 100.0
			st.huts[1]["buildT"] = 3.0
			st.px = 700.0
			st.pz = 60.0
			game.cam.snap(st.px, st.pz * Z_TO_Y)
			game.cam.x = 75.0
			game.cam.y = 80.0 * Z_TO_Y
			_hutcon_probes()
			_phase = "hutcon_arm"
		"hutcon_arm":
			_phase = "hutcon_shot"
		"hutcon_shot":
			_capture("tribe_hutcon.png")
			_phase = "toast_before_arm"  # clears the hud toasts, then the twin
		"toast_before_arm":
			# isolate the pair: drop any live toasts (the raid hint can still
			# be draining its ttl — hud time runs on frame delta) so the before
			# twin is toast-free and the after twin holds exactly one
			stage.hud_inst._toasts.clear()
			_phase = "toast_before_shot"  # one frame for the draw to drop them
		"toast_before_shot":
			_capture("tribe_toast_before.png")
			# fire the toast through the REAL hud (the sim is frozen; the hud
			# clock advances with the frame) — the inset gate polls the hud's
			# own toast age (no engine-frame counts)
			game.hud["toast"].call("The elders demand more berries", "info", "🫐")
			_toast_fired = true
			_toast_probes()
			_phase = "toast_live"
		"toast_live":
			var hud: Variant = stage.hud_inst
			if _toast_fired and hud._toasts.size() > 0 \
					and float(hud._toasts[0]["t"]) >= 0.3:
				_phase = "toast_arm"
		"toast_arm":
			_phase = "toast_shot"
		"toast_shot":
			_capture("tribe_toast.png")
			_phase = "check"
		"check":
			_phase = "done"
			_write_probes()
			_run_checker()


## A red tribesman genome for the z-sort fixture (the hue-15 side).
func _red_genome() -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.0
	g["hue"] = 15
	g["sat"] = 0.9
	g["pattern"] = "stripes"
	g["coat"] = "plates"
	g["tail"] = false
	g["legs"] = 4
	g["arms"] = 0
	g["eyes"] = 2
	g["diet"] = "herbivore"
	g["jaw"] = 0
	g["spikes"] = 0
	g["horns"] = 0
	g["wings"] = 0
	return g


## Screen anchors for the checker's probes: the TS manual camera transform
## (cam.gd to_world's inverse) — (world − cam)·zoom + center. Shake is 0 at
## capture (frozen frames have none; no tribe window fires a shake).
func _world_to_screen(wx: float, wy: float) -> Vector2:
	return Vector2(
			(wx - game.cam.x) * game.cam.zoom + game.vw / 2.0,
			(wy - game.cam.y) * game.cam.zoom + game.vh / 2.0)


## Body-center screen anchor from the rig metrics (body_y = −leg_h −
## 0.72·body_r above the feet anchor).
func _body_center(genome: Dictionary, feet: Vector2, scale: float) -> Vector2:
	var m: Dictionary = RigScript._metrics(genome, {"scale": scale})
	return Vector2(feet.x, feet.y + float(m["body_y"]) * game.cam.zoom)


## The day-village anchors: hut wall/roof, totem pole, HUD panel + button
## rects (the tribe stage's own draw geometry, TribeStage.ts:1246-1423).
func _village_probes() -> void:
	var hut_feet := _world_to_screen(0.0, 80.0 * Z_TO_Y)
	var totem_feet := _world_to_screen(0.0, 60.0 * Z_TO_Y)
	var p := float(_st().totem["progress"]) / 100.0
	# the wall probe sits LEFT of the door (door world x −7..7) — pure wall
	var wall := _world_to_screen(-15.0, 80.0 * Z_TO_Y - 13.0)
	_probe["village"] = {
		"hut_wall": [wall.x, wall.y],
		"hut_roof": [hut_feet.x, hut_feet.y - 40.0 * game.cam.zoom],
		"hut_label": [hut_feet.x, hut_feet.y + 12.0],
		"totem_pole": [totem_feet.x, totem_feet.y - 20.0 * p * game.cam.zoom],
		"totem_label": [totem_feet.x, totem_feet.y - 90.0 * p * game.cam.zoom - 16.0],
		"stockpile": [18.0, game.vh - 172.0, 228.0, game.vh - 120.0],
		"hut_btn": [24.0, game.vh - 104.0, 180.0, game.vh - 76.0],
		"totem_btn": [24.0, game.vh - 58.0, 180.0, game.vh - 30.0],
	}


## The in-view raiders (nearest the screen center first): body + feet anchors.
func _raid_picks(st: Variant) -> Array:
	var picks: Array = []
	for w in st.rivalWarriors:
		var feet: Vector2 = _world_to_screen(float(w["x"]), float(w["z"]) * Z_TO_Y)
		var body := _body_center(w["genome"], feet, 1.7)
		if body.x < game.vw * 0.08 or body.x > game.vw * 0.92 \
				or body.y < 60.0 or body.y > game.vh - 60.0:
			continue
		picks.append([absf(body.x - game.vw / 2.0) + absf(body.y - game.vh / 2.0),
				body.x, body.y])
	picks.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	return picks


func _raid_centroid(st: Variant) -> Vector2:
	var sx := 0.0
	var sy := 0.0
	for w in st.rivalWarriors:
		sx += float(w["x"])
		sy += float(w["z"]) * Z_TO_Y
	var n := float(maxi(1, st.rivalWarriors.size()))
	return Vector2(sx / n, sy / n)


func _raid_probes(st: Variant) -> void:
	var picks: Array = _raid_picks(st)
	if picks.size() < 2:
		_fail("fewer than 2 raiders visible at the freeze (candidates %d)" % picks.size())
		return
	var bodies: Array = []
	for i in mini(2, picks.size()):
		bodies.append([float(picks[i][1]), float(picks[i][2])])
	var bw: float = minf(560.0, game.vw * 0.8)
	_probe["raid"] = {
		"bodies": bodies,
		"banner_panel": [game.vw / 2.0 - bw / 2.0, 70.0, game.vw / 2.0 + bw / 2.0, 144.0],
		"banner_title": [78.0, 112.0],
	}


## The night anchors: the three campfire glows (r 34 at y − 10 world).
func _night_probes(st: Variant) -> void:
	var fires: Array = []
	for f in st.fires:
		var s: Vector2 = _world_to_screen(float(f["x"]), float(f["z"]) * Z_TO_Y - 10.0)
		fires.append([s.x, s.y])
	_probe["night"] = {"fires": fires}


## The death card's bands (tribe_stage.gd _draw_ui, TribeStage.ts:1389-1393).
func _death_probes() -> void:
	var chief_feet := _world_to_screen(_st().px, _st().pz * Z_TO_Y)
	var chief_body := _body_center(game.context.genome, chief_feet, 2.1)
	_probe["death"] = {
		"title_band": [game.vh / 2.0 - 18.0, game.vh / 2.0 + 10.0],
		"chief_body": [chief_body.x, chief_body.y],
	}


## The z-sort fixture's anchors: the red tribesman's body + the chief's body,
## plus the overlap scan column (the chief's lower body under the tribesman).
func _zsort_probes(st: Variant) -> void:
	var chief_feet := _world_to_screen(float(st.px), float(st.pz) * Z_TO_Y)
	var tm_feet := _world_to_screen(float(st.tribe[0]["x"]), float(st.tribe[0]["z"]) * Z_TO_Y)
	var chief_body := _body_center(game.context.genome, chief_feet, 2.1)
	var tm_body := _body_center(st.tribe[0]["genome"], tm_feet, 1.7)
	_probe["zsort"] = {
		"chief_body": [chief_body.x, chief_body.y],
		"tm_body": [tm_body.x, tm_body.y],
		"tm_feet_y": tm_feet.y,
		"chief_feet_y": chief_feet.y,
		"tm_x": tm_feet.x,
		# the overlap scan column: down the tribesman's x from its body center
		# to its feet — that span crosses the chief's torso/legs zone
		"scan": [tm_body.x - 6.0, tm_body.y + 8.0, tm_body.x + 6.0,
				minf(tm_feet.y - 4.0, chief_feet.y + 14.0)],
	}


## The totem-raising anchors (tribe_stage.gd great-totem block, TS:1281-1294):
## the pole mid-mass, both milestone discs (r 10 at y = top + 8), the label.
func _totem_probes() -> void:
	var ty := 60.0 * Z_TO_Y
	var p: float = float(_st().totem["progress"]) / 100.0
	var top_y: float = ty - 90.0 * p
	_probe["totem"] = {
		"pole_mid": [_world_to_screen(0.0, top_y + 90.0 * p * 0.5).x,
				_world_to_screen(0.0, top_y + 90.0 * p * 0.5).y],
		"disc_red": [_world_to_screen(-10.0, top_y + 8.0).x,
				_world_to_screen(-10.0, top_y + 8.0).y],
		"disc_blue": [_world_to_screen(10.0, top_y + 8.0).x,
				_world_to_screen(10.0, top_y + 8.0).y],
		"label": [_world_to_screen(0.0, top_y - 16.0).x,
				_world_to_screen(0.0, top_y - 16.0).y],
	}


## The beast-attack anchors (TS:1338-1354): the body center (scale 2.6), the
## 48×4 hp bar band at y − 68.
func _beast_probes() -> void:
	var b: Dictionary = _st().beast
	var feet: Vector2 = _world_to_screen(float(b["x"]), float(b["z"]) * Z_TO_Y)
	var body := _body_center(b["genome"], feet, 2.6)
	var bar_y: float = _world_to_screen(float(b["x"]), float(b["z"]) * Z_TO_Y - 68.0).y
	_probe["beast"] = {
		"body": [body.x, body.y],
		"bar_y": bar_y,
		"bar_x0": _world_to_screen(float(b["x"]) - 24.0, 0.0).x,
		"bar_x1": _world_to_screen(float(b["x"]) + 24.0, 0.0).x,
	}


## The rival-camp anchors (TS:1196-1208): the middle pole, its cap disc,
## the name row, and the tint pair (inside the 60 disc vs the same-lawn
## patch outside it).
func _camp_probes(st: Variant) -> void:
	var rx: float = float(st.rivals[0]["x"])
	var ry: float = float(st.rivals[0]["z"]) * Z_TO_Y
	_probe["camp"] = {
		"pole_mid": [_world_to_screen(rx, ry - 17.0).x, _world_to_screen(rx, ry - 17.0).y],
		"pole_cap": [_world_to_screen(rx, ry - 38.0).x, _world_to_screen(rx, ry - 38.0).y],
		"name": [_world_to_screen(rx, ry - 56.0).x, _world_to_screen(rx, ry - 56.0).y],
		"tint_in": [_world_to_screen(rx - 20.0, ry + 8.0).x,
				_world_to_screen(rx - 20.0, ry + 8.0).y],
		"tint_out": [_world_to_screen(rx + 80.0, ry + 8.0).x,
				_world_to_screen(rx + 80.0, ry + 8.0).y],
	}


## Park every resource clear of the camp moment's lawn band.
func _park_camp_world(st: Variant) -> void:
	for b in st.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0
	for t in st.trees:
		t["x"] = 99999.0
		t["z"] = 99999.0
	for i in st.tribe.size():
		st.tribe[i]["x"] = -600.0 + float(i) * 80.0
		st.tribe[i]["z"] = 60.0


## The hut-construction anchors: both huts share z 80 so the lawn band is
## identical — wall (left of the door), roof apex mass, the FULL-alpha label.
func _hutcon_probes() -> void:
	var built := {
		"wall": _world_to_screen(-15.0, 80.0 * Z_TO_Y - 13.0),
		"roof": _world_to_screen(0.0, 80.0 * Z_TO_Y - 40.0),
		"label": _world_to_screen(0.0, 80.0 * Z_TO_Y + 12.0),
	}
	var con := {
		"wall": _world_to_screen(135.0, 80.0 * Z_TO_Y - 13.0),
		"roof": _world_to_screen(150.0, 80.0 * Z_TO_Y - 40.0),
		"label": _world_to_screen(150.0, 80.0 * Z_TO_Y + 12.0),
	}
	# an empty-lawn control band at the same row (the resources are parked) —
	# the size-9 label glyphs are AA-thin under llvmpipe, so the label assert
	# reads presence AGAINST this control rather than an absolute count
	var ctrl := _world_to_screen(300.0, 80.0 * Z_TO_Y + 12.0)
	_probe["hutcon"] = {
		"built_wall": [built["wall"].x, built["wall"].y],
		"con_wall": [con["wall"].x, con["wall"].y],
		"con_roof": [con["roof"].x, con["roof"].y],
		"con_label": [con["label"].x, con["label"].y],
		"built_label": [built["label"].x, built["label"].y],
		"label_ctrl": [ctrl.x, ctrl.y],
	}


## The toast-inset band (hud.gd draw: toasts at ty = vh − 30 − toast_inset,
## panel ty−14..ty+12, x 16..16+pw) + the panel-top gap band below it.
func _toast_probes() -> void:
	var ty: float = game.vh - 30.0 - 190.0
	_probe["toast"] = {
		"band": [16.0, ty - 16.0, 200.0, ty + 14.0],
		"rows": [ty - 12.0, ty + 10.0],
		"text_band": [ty - 10.0, ty + 6.0],
		"gap_band": [16.0, ty + 16.0, 200.0, game.vh - 174.0],
		"stockpile_top": game.vh - 172.0,
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
	var checker := ProjectSettings.globalize_path("res://tools/visual_check_tribe_scene.py")
	var args: Array = [checker, ProjectSettings.globalize_path(OUT_DIR + "/probes.json")]
	for name in ["tribe_village_day", "tribe_raid", "tribe_night", "tribe_death",
			"tribe_zsort", "tribe_totem", "tribe_beast", "tribe_camp",
			"tribe_hutcon", "tribe_toast_before", "tribe_toast"]:
		args.append(ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png"))
	var output: Array = []
	var code := OS.execute("python3", args, output, true)
	for line in output:
		print(String(line).strip_edges())
	if code != 0:
		printerr("VISUAL_TEST_FAIL: visual_check_tribe_scene.py exited %d" % code)
		get_tree().quit(1)
	else:
		print("VISUAL_TEST_OK")
		get_tree().quit(0)
