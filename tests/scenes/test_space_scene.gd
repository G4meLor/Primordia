# Space-stage scene test (xvfb, Compatibility renderer) — M6 task 5.
# Boots a REAL Game with a pinned seed, enters the REGISTERED space stage, and
# captures the moment suite via get_viewport().get_texture(). Every moment
# freezes the sim (stage.frozen — render without stepping) and is armed by
# SIM-STATE fixtures only (the freeze-arm doctrine — NO engine-frame-count
# gates, the M3 volcano lesson); each is checked by ≥ 3 structural pixel
# asserts in tools/visual_check_space_scene.py (probes.json carries the live
# anchors — the camera transform, the stage's own panel seams, the rig
# metrics):
#
#   space_system.png     — system view: the sun discs, the orbit arcs, 3
#                          planet discs with the offset shadow gradient + a
#                          ring (the planets' orbitR/angle are frozen fixtures
#                          so all three + the sun fit one 0.85-zoom frame)
#   space_pirates.png    — the 4-point pirate hulls + the ☠ markers + the red
#                          glows
#   space_blackhole.png  — the 3-stop gradient (the r 37.2 mid-stop band
#                          eyeball — the T4-review rider) + the rotating arc
#   space_beam.png       — the beam line (ship-bright → planet-faint) + the
#                          rising creature specimen
#   space_cargo.png      — the cargo bar: creature pixels in slot 0, cell
#                          pixels in slot 1, the empty slot 3
#   space_panel.png      — the planet panel: 6 buttons, enabled-blue vs
#                          disabled-grey fills, the hull-fraction label
#   space_ff_before/.png — the ff-tint pair: the 0.06 purple veil + the label
#   space_chip.png       — the colonies chip gold at 3 thriving (vs the green
#                          0-colony system twin) — debug_seed_colonies + pops
#   space_ending.png     — the ending veil at alpha 1 + THE CHAOS CORE ACCEPTS
#                          YOU + the stat/sandbox/keys lines
#
# Rider observations (the T4 review): the camera-zoom one-frame lag on stage
# entry (the cam.zoom field writes AFTER follow's _apply — inherited platform
# behavior, tribe/creature ship it too) is RECORDED in probes.json (zoom_obs)
# and printed by the checker — documented, NOT fixed, NOT asserted.
# Run: tools/test_space_scene.sh (one-command entry).
extends Node2D

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const RigScript := preload("res://src/gfx/creature_rig.gd")

const SEED := 20261004
const OUT_DIR := "user://visual_capture_space"
const TIMEOUT_FRAMES := 7200

var game: Variant = null
var _phase := "boot"
var _frames := 0
var _probe := {}
var _zoom_series: Array = []
var _sys_cam := Vector2(190.0, -250.0)   # the system centroid (the fixture below)
var _beam_mid := Vector2.ZERO


func _ready() -> void:
	var ctx: Variant = ContextScript.new(SEED)
	game = GameScript.new(ctx)
	add_child(game)
	game.register(SpaceStageScript.new(game))
	game.switch_stage("space")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _fail(msg: String) -> void:
	printerr("VISUAL_TEST_FAIL: %s (phase %s, frame %d)" % [msg, _phase, _frames])
	get_tree().quit(1)


func _st() -> Variant:
	return game.current.sim


func _stage() -> Variant:
	return game.current


## World → screen through the live rig (frozen frames carry no shake): the
## cam.gd to_world inverse — (world − cam)·zoom + center.
func _w2s(wx: float, wy: float) -> Vector2:
	return Vector2(
			(wx - game.cam.x) * game.cam.zoom + game.vw / 2.0,
			(wy - game.cam.y) * game.cam.zoom + game.vh / 2.0)


func _snap_cam(wx: float, wy: float) -> void:
	game.cam.zoom = 0.85  # the SPACE constant — set BEFORE snap so _apply carries both
	game.cam.snap(wx, wy)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout (phase %s, sim_time %s)" % [_phase, str(_st().time)])
		return
	# the zoom-lag observation (the T4 rider): record the first 6 frames —
	# cam.zoom (the field the stage writes) vs the Camera2D rig's applied zoom
	if _zoom_series.size() < 6:
		var rig: float = -1.0
		if game.cam.cam2d != null:
			rig = float(game.cam.cam2d.zoom.x)
		_zoom_series.append({"frame": _frames, "cam_zoom": float(game.cam.zoom),
				"rig_zoom": rig, "sim_time": float(_st().time)})
	var st: Variant = _st()
	var stage: Variant = _stage()
	match _phase:
		"boot":
			# sim-state gate: the sim has stepped (one update placed the
			# planets on their orbits)
			if float(st.time) > 0.0:
				stage.frozen = true
				_phase = "system_setup"
		"system_setup":
			# the three inner planets clustered UP of the sun so the discs,
			# the arcs and the sun share one 0.85-zoom frame (orbitR/angle are
			# sim-state fixtures — the civ city-coord precedent); p1 carries
			# the ring. The ship parks out of frame.
			var specs := [
				[0, 300.0, -PI / 2.0],
				[1, 380.0, -PI / 2.0 + 0.5],
				[2, 460.0, -PI / 2.0 + 1.0],
			]
			for s in specs:
				var p: Dictionary = st.planets[s[0]]
				p["orbitR"] = s[1]
				p["angle"] = s[2]
				p["x"] = cos(float(s[2])) * float(s[1])
				p["y"] = sin(float(s[2])) * float(s[1])
			st.planets[1]["ring"] = true
			st.sx = 0.0
			st.sy = -900.0
			_snap_cam(_sys_cam.x, _sys_cam.y)
			_system_probes(st)
			_phase = "system_arm"
		"system_arm":
			_phase = "system_shot"
		"system_shot":
			_capture("space_system.png")
			_phase = "pirates_setup"
		"pirates_setup":
			# two pirates parked in-frame (sim-state fixtures); the ship
			# farther out of frame (the hull rotation aims at it either way)
			st.pirates = [
				{"x": -150.0, "y": -660.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0},
				{"x": 180.0, "y": -540.0, "vx": 0.0, "vy": 0.0, "hp": 140.0, "gait": 0.0},
			]
			st.pirateTtl = [40.0, 40.0]
			st.sx = -800.0
			st.sy = -1200.0
			_snap_cam(0.0, -600.0)
			_pirate_probes(st)
			_phase = "pirates_arm"
		"pirates_arm":
			_phase = "pirates_shot"
		"pirates_shot":
			_capture("space_pirates.png")
			_phase = "hole_setup"
		"hole_setup":
			# the black hole parked above frame center; the pirates drop out
			st.pirates = []
			st.pirateTtl = []
			st.blackHoles = [{"x": 0.0, "y": -700.0, "vx": 0.0, "vy": 0.0, "ttl": 45.0}]
			_snap_cam(0.0, -600.0)
			_hole_probes(st)
			_phase = "hole_arm"
		"hole_arm":
			_phase = "hole_shot"
		"hole_shot":
			_capture("space_blackhole.png")
			_phase = "beam_setup"
		"beam_setup":
			# the beam from the ship to planet 0 (lush — a living roster); the
			# FIRST species' genome becomes a green legged creature so the
			# specimen paints the creature branch
			st.blackHoles = []
			var p0: Dictionary = st.planets[0]
			var sp: Dictionary = p0["eco"].living()[0]
			sp["genome"]["legs"] = 4
			sp["genome"]["hue"] = 120
			sp["genome"]["size"] = 1.2
			st.sx = float(p0["x"]) + float(p0["r"]) + 90.0
			st.sy = float(p0["y"])
			st.beamTarget = p0
			st.beamT = 1.4  # t = 0 — the specimen rides the beam midpoint
			_beam_mid = Vector2((st.sx + float(p0["x"])) / 2.0,
					(st.sy + float(p0["y"])) / 2.0)
			_snap_cam(_beam_mid.x, _beam_mid.y)
			_beam_probes(st, p0)
			_phase = "beam_arm"
		"beam_arm":
			_phase = "beam_shot"
		"beam_shot":
			_capture("space_beam.png")
			_phase = "cargo_setup"
		"cargo_setup":
			# the beam drops out; the cargo bar is SCREEN-space (the camera
			# stays where the beam left it): a legged green row, a hue-200
			# cell row, slots 2/3 empty
			st.beamT = 0.0
			st.beamTarget = null
			var g0: Dictionary = GenomeScript.default_genome()
			g0["legs"] = 4
			g0["hue"] = 120
			g0["size"] = 1.0
			var g1: Dictionary = GenomeScript.default_genome()
			g1["legs"] = 0
			g1["arms"] = 0
			g1["hue"] = 200
			st.cargo = [{"genome": g0, "name": "critter"},
					{"genome": g1, "name": "blob"}]
			_cargo_probes()
			_phase = "cargo_arm"
		"cargo_arm":
			_phase = "cargo_shot"
		"cargo_shot":
			_capture("space_cargo.png")
			_phase = "panel_setup"
		"panel_setup":
			# the planet panel: the ship back beside planet 0, cargo 2 (6
			# rows), hull 60 + dna 40 → REPAIR disabled with the hull-fraction
			# label (screen-space — the camera stays)
			var p0b: Dictionary = st.planets[0]
			st.sx = float(p0b["x"]) + float(p0b["r"]) + 80.0
			st.sy = float(p0b["y"])
			st.shp = 60.0
			_panel_probes()
			_phase = "panel_arm"
		"panel_arm":
			_phase = "panel_shot"
		"panel_shot":
			_capture("space_panel.png")
			_phase = "chip_setup"
		"chip_setup":
			# the chip goes gold at 3 thriving colonies: the documented debug
			# seam seeds the first three non-barren planets, the pops fixture
			# to 25 (≥ 20). The system camera returns (the ending twin needs
			# the sun in frame); the ship parks out of frame (the panel
			# gate closes).
			st.sx = 0.0
			st.sy = -900.0
			_snap_cam(_sys_cam.x, _sys_cam.y)
			st.debug_seed_colonies()
			for i in 3:
				st.planets[i]["colony"]["pop"] = 25.0
			_chip_probes()
			_phase = "chip_arm"
		"chip_arm":
			_phase = "chip_shot"
		"chip_shot":
			_capture("space_chip.png")
			_phase = "ff_before_arm"
		"ff_before_arm":
			_phase = "ff_before_shot"
		"ff_before_shot":
			_capture("space_ff_before.png")
			_phase = "ff_after_arm"
		"ff_after_arm":
			st.ffHold = 1.0
			_ff_probes()
			_phase = "ff_after_shot"
		"ff_after_shot":
			_capture("space_ff_after.png")
			_phase = "ending_setup"
		"ending_setup":
			# the ending overlay: alpha 1 (endingT 3 ≥ the 2 s fade-in), the
			# veil at 0.86 + renderEnding. The stats read the ctx fixtures.
			st.ffHold = 0.0
			st.endingDone = true
			st.endingDismissed = false
			st.endingT = 3.0
			game.context.playtime = 7200.0
			game.context.total_dna_earned = 1234
			game.context.karma = 0.5
			game.context.chaos = 0.42
			if game.context.bestiary.size() < 3:
				for i in 3:
					game.context.bestiary["sp%d" % i] = {"name": "sp%d" % i}
			_ending_probes(st)
			_phase = "ending_arm"
		"ending_arm":
			_phase = "ending_shot"
		"ending_shot":
			_capture("space_ending.png")
			_phase = "check"
		"check":
			_phase = "done"
			_write_probes()
			_run_checker()


## The system-view anchors: the sun patch (lifted 14px clear of the bottom
## HUD bands), the 3 planet discs (kind-keyed dominance + the shadow
## gradient's lit/dark pair), a clean arc window on planet 0's orbit (+ its
## radius-−40 control), the ring point on planet 1's ellipse + its control.
func _system_probes(st: Variant) -> void:
	var z: float = game.cam.zoom
	var sun := _w2s(0.0, 0.0)
	var planets: Array = []
	for i in 3:
		var p: Dictionary = st.planets[i]
		var c := _w2s(float(p["x"]), float(p["y"]))
		var r: float = float(p["r"]) * z
		planets.append({
			"c": [c.x, c.y], "kind": String(p["kind"]),
			"lit": [c.x - 0.35 * float(p["r"]) * z, c.y - 0.35 * float(p["r"]) * z],
			"dark": [c.x + 0.65 * float(p["r"]) * z, c.y + 0.65 * float(p["r"]) * z],
		})
	# the orbit-arc window: clear of planet 0's disc (+0.3..+0.9 rad ahead)
	var p0: Dictionary = st.planets[0]
	var ang: float = float(p0["angle"])
	var arc_pts: Array = []
	var arc_ctrl: Array = []
	for k in 16:
		var a: float = ang + 0.3 + 0.6 * float(k) / 15.0
		var on := _w2s(cos(a) * 300.0, sin(a) * 300.0)
		var off := _w2s(cos(a) * 260.0, sin(a) * 260.0)
		arc_pts.append([on.x, on.y])
		arc_ctrl.append([off.x, off.y])
	# the ring: planet 1's ellipse param-0 point (rx 1.7r along the rot-0.4
	# axis) + a control 2.3r along the same rotated direction
	var p1: Dictionary = st.planets[1]
	var pc1 := _w2s(float(p1["x"]), float(p1["y"]))
	var rr: float = float(p1["r"])
	var ring_dir := Vector2(cos(0.4), sin(0.4))
	var ring := pc1 + ring_dir * rr * 1.7 * z
	var ring_ctrl := pc1 + ring_dir * rr * 2.3 * z
	_probe["system"] = {
		"sun": [sun.x, sun.y - 14.0],
		"planets": planets,
		"arc_pts": arc_pts, "arc_ctrl_pts": arc_ctrl,
		"ring": [ring.x, ring.y], "ring_ctrl": [ring_ctrl.x, ring_ctrl.y],
	}


## The pirate anchors: the hull centers, the ☠ boxes (22 world px above), the
## glow in/out pair (+12 / +70 world px along +x).
func _pirate_probes(st: Variant) -> void:
	var z: float = game.cam.zoom
	var spots: Array = []
	for p in st.pirates:
		var c := _w2s(float(p["x"]), float(p["y"]))
		spots.append({
			"c": [c.x, c.y],
			"skull": [c.x - 13.0, c.y - 22.0 * z - 9.0, c.x + 13.0, c.y - 22.0 * z + 9.0],
			"glow_in": [c.x + 12.0 * z, c.y],
			"glow_out": [c.x + 70.0 * z, c.y],
		})
	_probe["pirates"] = {"spots": spots}


## The black-hole anchors: the core patch, the radial profile points (the
## 37.2 band eyeball — the purple peak brackets [36, 40]), the rotating-arc
## point (angle time+2.5, radius 46+sin(time·5)·5) + the control outside the
## [time, time+4] span at the same radius.
func _hole_probes(st: Variant) -> void:
	var z: float = game.cam.zoom
	var c := _w2s(0.0, -700.0)
	var profile := {}
	for r in [4.0, 20.0, 30.0, 36.0, 44.0, 50.0, 85.0]:
		var pt := c + Vector2(r * z, 0.0)
		profile["r%d" % int(r)] = [pt.x, pt.y]
	var t: float = float(st.time)
	var r_arc: float = 46.0 + sin(t * 5.0) * 5.0
	var arc := c + Vector2(cos(t + 2.5), sin(t + 2.5)) * r_arc * z
	var arc_ctrl := c + Vector2(cos(t + 5.5), sin(t + 5.5)) * r_arc * z
	_probe["hole"] = {
		"core": [c.x, c.y],
		"profile": profile,
		"arc": [arc.x, arc.y], "arc_ctrl": [arc_ctrl.x, arc_ctrl.y],
	}


## The beam anchors: the line triple (ship-end / mid / planet-end samples at
## t 0.15/0.5/0.85), the off-line control below the midpoint, the rising
## creature's body center (the rig metrics at the pose scale — the tribe
## _body_center precedent; the pose rides the beam midpoint at t = 0).
func _beam_probes(st: Variant, p0: Dictionary) -> void:
	var z: float = game.cam.zoom
	var ship := Vector2(float(st.sx), float(st.sy))
	var planet := Vector2(float(p0["x"]), float(p0["y"]))
	var mid := _beam_mid
	var ship_end := mid.lerp(ship, 0.35)
	var planet_end := mid.lerp(planet, 0.35)
	var off := _w2s(mid.x, mid.y + 60.0)
	var g: Dictionary = p0["eco"].living()[0]["genome"]
	var m: Dictionary = RigScript._metrics(g, {"scale": 1.2})
	var body := _w2s(mid.x, mid.y) + Vector2(0.0, float(m["body_y"]) * z)
	var mid_s := _w2s(mid.x, mid.y)
	var se_s := _w2s(ship_end.x, ship_end.y)
	var pe_s := _w2s(planet_end.x, planet_end.y)
	_probe["beam"] = {
		"mid": [mid_s.x, mid_s.y],
		"ship_end": [se_s.x, se_s.y],
		"planet_end": [pe_s.x, pe_s.y],
		"off": [off.x, off.y],
		"body": [body.x, body.y],
	}


## The cargo-bar anchors (screen-space, the stage's own geometry): the 4 slot
## rects + the inner probe boxes for slots 0 (creature), 1 (cell) and 3
## (empty).
func _cargo_probes() -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	var cargo_w := 4.0 * 54.0 + 3.0 * 8.0
	var cx0: float = vw / 2.0 - cargo_w / 2.0
	var cy: float = vh - 178.0
	var slots: Array = []
	var boxes: Array = []
	for i in 4:
		var x: float = cx0 + float(i) * 62.0
		slots.append([x, cy, x + 54.0, cy + 54.0])
		boxes.append([x + 6.0, cy + 6.0, x + 48.0, cy + 50.0])
	_probe["cargo"] = {"slots": slots, "green_box": boxes[0],
			"cell_box": boxes[1], "empty_box": boxes[3]}


## The planet-panel anchors (screen-space, the stage's own seams): the frame
## top band, the abduct/repair/gene-lab row centers, the abduct (white) and
## repair (fraction) label boxes.
func _panel_probes() -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	var frame: Rect2 = SpaceStageScript.panel_frame(2, vw, vh)
	var abduct := SpaceStageScript.panel_button_rect(frame, 0)
	var repair := SpaceStageScript.panel_button_rect(frame, 3)
	var merge := SpaceStageScript.panel_button_rect(frame, 4)
	_probe["panel"] = {
		"frame_top": [frame.position.x + 10.0, frame.position.y + 4.0,
				frame.position.x + frame.size.x - 10.0, frame.position.y + 10.0],
		"abduct_c": [abduct.get_center().x, abduct.get_center().y],
		"repair_c": [repair.get_center().x, repair.get_center().y],
		"merge_c": [merge.get_center().x, merge.get_center().y],
		"abduct_label": [abduct.get_center().x - 80.0, abduct.position.y + 8.0,
				abduct.get_center().x + 80.0, abduct.position.y + 22.0],
		"repair_label": [repair.get_center().x - 80.0, repair.position.y + 8.0,
				repair.get_center().x + 80.0, repair.position.y + 22.0],
	}


## The chip box (the stage's own geometry: panel vw/2−110, 44, 220×26; the
## label at y 57).
func _chip_probes() -> void:
	var vw: float = game.vw
	_probe["chip"] = {"box": [vw / 2.0 - 95.0, 47.0, vw / 2.0 + 95.0, 67.0]}


## The ff-tint anchors: a clean mid-left patch + the label band (y 160).
func _ff_probes() -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	_probe["ff"] = {
		"tint": [vw * 0.25 - 20.0, vh * 0.3 - 20.0, vw * 0.25 + 20.0, vh * 0.3 + 20.0],
		"label": [vw / 2.0 - 130.0, 150.0, vw / 2.0 + 130.0, 172.0],
	}


## The ending anchors: the sun patch (the veil drop against the chip twin),
## the title band, the stat-lines band, the sandbox + keys bands.
func _ending_probes(_st: Variant) -> void:
	var vw: float = game.vw
	var vh: float = game.vh
	var sun := _w2s(0.0, 0.0)
	# the renderEnding rows: title vh/2−120, stats from vh/2−60 stepping 30
	# (4 lines → the tail at vh/2+60), the sandbox line at +20, the keys at +46
	_probe["ending"] = {
		"sun": [sun.x, sun.y - 14.0],
		"title": [vw / 2.0 - 260.0, vh / 2.0 - 140.0, vw / 2.0 + 260.0, vh / 2.0 - 100.0],
		"stats": [vw / 2.0 - 290.0, vh / 2.0 - 68.0, vw / 2.0 + 290.0, vh / 2.0 + 68.0],
		"sandbox": [vw / 2.0 - 240.0, vh / 2.0 + 70.0, vw / 2.0 + 240.0, vh / 2.0 + 90.0],
		"keys": [vw / 2.0 - 240.0, vh / 2.0 + 96.0, vw / 2.0 + 240.0, vh / 2.0 + 116.0],
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
	_probe["zoom_obs"] = _zoom_series
	var f := FileAccess.open(OUT_DIR + "/probes.json", FileAccess.WRITE)
	if f == null:
		_fail("cannot write probes.json")
		return
	f.store_string(JSON.stringify(_probe))
	f.close()


func _run_checker() -> void:
	var checker := ProjectSettings.globalize_path("res://tools/visual_check_space_scene.py")
	var args: Array = [checker, ProjectSettings.globalize_path(OUT_DIR + "/probes.json")]
	for name in ["space_system", "space_pirates", "space_blackhole", "space_beam",
			"space_cargo", "space_panel", "space_ff_before", "space_ff_after",
			"space_chip", "space_ending"]:
		args.append(ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png"))
	var output: Array = []
	var code := OS.execute("python3", args, output, true)
	for line in output:
		print(String(line).strip_edges())
	if code != 0:
		printerr("VISUAL_TEST_FAIL: visual_check_space_scene.py exited %d" % code)
		get_tree().quit(1)
	else:
		print("VISUAL_TEST_OK")
		get_tree().quit(0)
