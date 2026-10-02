# Civ-stage scene test (xvfb, Compatibility renderer) — M5 task 3.
# Boots a REAL Game with a pinned seed + pinned ruler genome, enters the civ
# stage, and captures the moment suite via get_viewport().get_texture().
# Every moment freezes the sim (stage.frozen — render without stepping) at a
# SIM-STATE gate (NO engine-frame-count gates — the M3 volcano lesson) and is
# checked by ≥ 3 structural pixel asserts in tools/visual_check_civ_scene.py
# (probes.json carries the live anchors — the stage's own geometry seams):
#
#   civ_planet_day.png — planet-day: the space base + stars, the ocean disc
#                        (offset light center), continent blobs, the rim band
#   civ_cities.png     — 4 city discs owner-colored + name/status labels +
#                        influence/hp bars (fixtures repositioned in-view)
#   civ_armada.png     — the armada through a REAL Digit1 press (the slider
#                        raised by a REAL Q press first): ship disc + glow +
#                        the dashed [4,6] trail + the launch toast (inset 150)
#   civ_sliders.png    — the sliders panel with REAL key-press fixtures
#                        (S/D drain culture+econ, Q fills mil to 10): a full
#                        bar vs the 3px-floor empty bars (the ratio pin)
#   civ_portrait.png   — the ruler portrait: creature pixels INSIDE the clip
#                        rect, NONE in the panel ring outside it
#   civ_victory.png    — the victory shimmer (THE PLANET IS UNITED) vs its
#                        absence in civ_planet_day.png (the pre-victory twin)
#
# Freeze discipline: the pressing phases arm on the REAL input pipeline
# (game.input.handle_event → the wrapper one-shots → the stage snapshot →
# sim.update) gated on the resulting sim state; every other moment is a
# frozen-fixture mutation (city coords/owners via the sim, the drift camera
# zeroed to pin the trail against the cities twin). Run:
# tools/test_civ_scene.sh (one-command entry).
extends Node2D

const GameScript := preload("res://src/game/game.gd")
const ContextScript := preload("res://src/game/context.gd")
const CivStageScript := preload("res://src/game/civ/civ_stage.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const RigScript := preload("res://src/gfx/creature_rig.gd")

const SEED := 20261001
const OUT_DIR := "user://visual_capture_civ"
const TIMEOUT_FRAMES := 7200

var game: Variant = null
var _phase := "boot"
var _frames := 0
var _probe := {}
# the presser: {code, want: Callable} — one REAL press per frame until the
# wanted sim state holds (state gates, never frame counts)
var _press_queue: Array = []


func _ready() -> void:
	var ctx: Variant = ContextScript.new(SEED)
	# pinned ruler genome: big green herbivore (the portrait probe's GREEN side)
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
	game.register(CivStageScript.new(game))
	game.switch_stage("civ")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _fail(msg: String) -> void:
	printerr("VISUAL_TEST_FAIL: %s (phase %s, frame %d)" % [msg, _phase, _frames])
	get_tree().quit(1)


func _st() -> Variant:
	return game.current.sim


func _stage() -> Variant:
	return game.current


## One REAL key press through the input pipeline (the Game's
## _unhandled_input path is the live-window route; the wrapper feed is the
## same the OS events land in — handle_event → keys_pressed one-shot).
func _press(code: String) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = game.input.CODES[code]
	ev.pressed = true
	game.input.handle_event(ev)


## Queue a press: fire it next frame, wait until want() holds.
func _queue_press(code: String, want: Callable) -> void:
	_press_queue.append({"code": code, "want": want})


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout (phase %s mil=%s armadas=%d)" % [_phase,
				str(_st().mil), _st().armadas.size()])
		return
	var st: Variant = _st()
	var stage: Variant = _stage()
	match _phase:
		"boot":
			# sim-state gate: the sim has stepped (time > 0) and nothing has
			# drifted yet (no armadas, the drift camera still at 0)
			if float(st.time) > 0.0 and st.armadas.size() == 0:
				stage.frozen = true
				_planet_probes()
				_phase = "planet_arm"
		"planet_arm":
			_phase = "planet_shot"  # next frame's texture holds the drawn state
		"planet_shot":
			_capture("civ_planet_day.png")
			_phase = "cities_setup"
		"cities_setup":
			# the cities moment: the rivals repositioned IN VIEW (the TS
			# constructor's 700/480 ring mostly projects off-screen at 800×600
			# — a frozen sim-state fixture parks them on the disc); r2's
			# influence set to 30 for the green (>0.5) bar variant
			var coords := [Vector2(-300.0, 0.0), Vector2(300.0, -80.0), Vector2(0.0, -300.0)]
			for i in 3:
				st.cities[i + 1]["x"] = coords[i].x
				st.cities[i + 1]["y"] = coords[i].y
			st.cities[2]["influence"] = 30.0
			_cities_probes()
			_phase = "cities_arm"
		"cities_arm":
			_phase = "cities_shot"
		"cities_shot":
			_capture("civ_cities.png")
			_phase = "mil_press"
		"mil_press":
			# the armada needs stat ≥ 5 (power 9 > rivalDef 8): one REAL Q
			# press raises mil 4 → 5 (the board transfer takes 1 from culture)
			stage.frozen = false
			_queue_press("KeyQ", func(): return absf(float(st.mil) - 5.0) < 0.001)
			_phase = "mil_wait"
		"mil_wait":
			if _run_presser():
				_phase = "launch_press"
		"launch_press":
			# the REAL Digit1 press → the armada spawns (the launch toast rides
			# the hud hook; the drift camera starts tracking the armada)
			_queue_press("Digit1", func(): return st.armadas.size() == 1)
			_phase = "launch_wait"
		"launch_wait":
			if _run_presser():
				_phase = "flight"
		"flight":
			# sim-state freeze: the armada mid-flight (t ≥ 0.4 s — clear of the
			# capital's 22px glow), then the drift camera zeroes to pin the
			# trail against the cities twin (the drift itself is sim-tested)
			if st.armadas.size() == 1 and float(st.armadas[0]["t"]) >= 0.4:
				stage.frozen = true
				st.camX = 0.0
				st.camY = 0.0
				_armada_probes()
				_phase = "armada_arm"
			elif st.armadas.size() == 0:
				_fail("the armada resolved before the freeze window")
		"armada_arm":
			_phase = "armada_shot"
		"armada_shot":
			_capture("civ_armada.png")
			_phase = "drain_press"
		"drain_press":
			# the sliders fixtures via REAL presses: S drains culture, D drains
			# econ, then Q fills mil toward 10 (no transfers — the board is
			# under output until the last press)
			stage.frozen = false
			_drain_queue()
			_phase = "drain_wait"
		"drain_wait":
			if _run_presser():
				stage.frozen = true
				_sliders_probes()
				_phase = "sliders_arm"
		"sliders_arm":
			# isolate the pair: drop live toasts (the launch toast can still be
			# draining) so the panel/portrait asserts read clean bands
			stage.hud_inst._toasts.clear()
			_phase = "sliders_shot"
		"sliders_shot":
			_capture("civ_sliders.png")
			_phase = "portrait_arm"
		"portrait_arm":
			# still frozen (the portrait reads sim.time only — static pose)
			_portrait_probes()
			_phase = "portrait_shot"
		"portrait_shot":
			_capture("civ_portrait.png")
			_phase = "victory_setup"
		"victory_setup":
			# the victory shimmer: all owners set via the sim + victoryFired
			# (the render reads the board only, TS:655-658; the flag keeps the
			# update path's go_to/save_all from ever firing here)
			for c in st.cities:
				c["owner"] = "you"
			st.victoryFired = true
			_victory_probes()
			_phase = "victory_arm"
		"victory_arm":
			_phase = "victory_shot"
		"victory_shot":
			_capture("civ_victory.png")
			_phase = "check"
		"check":
			_phase = "done"
			_write_probes()
			_run_checker()


## Fire the queued presses one per frame; true when the queue is done.
func _run_presser() -> bool:
	if _press_queue.is_empty():
		return true
	var job: Dictionary = _press_queue[0]
	if bool(job["want"].call()):
		_press_queue.pop_front()
		return _press_queue.is_empty()
	if not job.has("fired"):
		job["fired"] = true
		_press(String(job["code"]))
	return false


func _drain_queue() -> void:
	# the fixtures via REAL presses: culture 2 → 0, econ 3 → 0, mil 3 → 10
	# (the launch spent 2). Each job = one press gated on the INTERMEDIATE
	# state it produces (the presser is head-blocking — a terminal gate would
	# deadlock a multi-press lane); one spare terminal-gate job per lane pops
	# free once the lane is done.
	var c0 := int(float(_st().culture))
	for i in c0:
		_queue_press("KeyS", func(): return float(_st().culture) <= float(c0 - 1 - i))
	_queue_press("KeyS", func(): return float(_st().culture) <= 0.0)
	var e0 := int(float(_st().econ))
	for i in e0:
		_queue_press("KeyD", func(): return float(_st().econ) <= float(e0 - 1 - i))
	_queue_press("KeyD", func(): return float(_st().econ) <= 0.0)
	var m0 := int(float(_st().mil))
	for i in 10 - m0:
		_queue_press("KeyQ", func(): return float(_st().mil) >= float(m0 + 1 + i))
	_queue_press("KeyQ", func(): return float(_st().mil) >= 10.0)


## The planet-day anchors (the stage's geometry seams — no copies). The ocean
## probes SEARCH for continent-free water: the 7 seeded blobs cover most
## fixed fractions of the disc, so the harness replays the stage's ellipse
## formulas and picks clean water deterministically.
func _planet_probes() -> void:
	var pc: Vector2 = CivStageScript.map_to_screen(0.0, 0.0, _st().camX, _st().camY,
			game.vw, game.vh)
	var pr: float = CivStageScript.planet_radius(game.vw, game.vh)
	var ells: Array = []
	var cont: Array = []
	for i in 7:
		var a := float(i) * 2.4 + 0.7
		var rr := pr * (0.25 + float(i % 3) * 0.18)
		var cc := pc + Vector2(cos(a) * pr * 0.55, sin(a) * pr * 0.5)
		ells.append({"c": cc, "rr": rr, "ry": rr * 0.7, "a": a})
		if i == 1 or i == 2 or i == 5:
			cont.append([cc.x, cc.y])
	# the gradient pair: the ocean point nearest the offset light center
	# (TS:543 — gc = pc − (0.3pr, 0.3pr), inner r 0.2pr) vs the farthest
	var gc := pc - Vector2(pr * 0.3, pr * 0.3)
	var ocean_a := _search_ocean(pc, pr, ells, func(p: Vector2) -> float:
		return p.distance_to(gc))
	var ocean_b := _search_ocean(pc, pr, ells, func(p: Vector2) -> float:
		return -p.distance_to(gc))
	# the radius-band direction: a continent-free cone (±0.12 rad) at 0.93pr
	var edge_dir := _search_edge_dir(pc, pr, ells)
	var edge_in := pc + edge_dir * pr * 0.93
	var edge_out := pc + edge_dir * pr * 1.06
	var tangent := Vector2(-edge_dir.y, edge_dir.x)
	var rim_in := pc + edge_dir * pr * 1.04
	var rim_out := pc + edge_dir * pr * 1.12
	_probe["planet"] = {
		"pc": [pc.x, pc.y],
		"pr": pr,
		"cont": cont,
		"ocean_a": [ocean_a.x, ocean_a.y],
		"ocean_b": [ocean_b.x, ocean_b.y],
		"corner": [24.0, game.vh * 0.5],
		"stars_box": [0.0, 80.0, 200.0, 260.0],
		"edge_in": [edge_in.x, edge_in.y],
		"edge_out": [edge_out.x, edge_out.y],
		"rim_in_seg": [[rim_in.x - tangent.x * 30.0, rim_in.y - tangent.y * 30.0],
				[rim_in.x + tangent.x * 30.0, rim_in.y + tangent.y * 30.0]],
		"rim_out_seg": [[rim_out.x - tangent.x * 30.0, rim_out.y - tangent.y * 30.0],
				[rim_out.x + tangent.x * 30.0, rim_out.y + tangent.y * 30.0]],
	}


func _outside_ells(p: Vector2, ells: Array) -> bool:
	for e in ells:
		var d: Vector2 = p - (e["c"] as Vector2)
		var ca := cos(-float(e["a"]))
		var sa := sin(-float(e["a"]))
		var lx := d.x * ca - d.y * sa
		var ly := d.x * sa + d.y * ca
		if pow(lx / float(e["rr"]), 2.0) + pow(ly / float(e["ry"]), 2.0) <= 1.1:
			return false
	return true


## The ocean candidate scoring best (the disc grid at 0.05pr radial steps).
func _search_ocean(pc: Vector2, pr: float, ells: Array, score: Callable) -> Vector2:
	var best := pc
	var best_s := INF
	var r := pr * 0.2
	while r <= pr * 0.9:
		for k in 48:
			var p := pc + Vector2(cos(TAU * float(k) / 48.0), sin(TAU * float(k) / 48.0)) * r
			if _outside_ells(p, ells):
				var s: float = score.call(p)
				if s < best_s:
					best_s = s
					best = p
		r += pr * 0.05
	return best


## A radial direction whose 0.93pr point AND ±0.12 rad cone are continent-free.
func _search_edge_dir(pc: Vector2, pr: float, ells: Array) -> Vector2:
	for k in 72:
		var a := TAU * float(k) / 72.0
		var free := true
		for da in [-0.12, -0.06, 0.0, 0.06, 0.12]:
			var p := pc + Vector2(cos(a + da), sin(a + da)) * pr * 0.93
			if not _outside_ells(p, ells):
				free = false
				break
		if free:
			return Vector2(cos(a), sin(a))
	return Vector2(0.0, -1.0)  # unreachable for the pinned seed — fails loudly


func _cities_probes() -> void:
	var st: Variant = _st()
	var spots: Array = []
	for c in st.cities:
		var s: Vector2 = CivStageScript.map_to_screen(float(c["x"]), float(c["y"]),
				st.camX, st.camY, game.vw, game.vh)
		var mine := String(c["owner"]) == "you"
		var col_key := "green"
		if not mine:
			for r in st.rivals:
				if String(r["id"]) == String(c["owner"]):
					col_key = {"#ff7a5a": "red", "#9a7aff": "purple",
							"#5ad0a8": "teal"}[String(r["color"])]
		spots.append({
			"disc": [s.x, s.y],
			"name": [s.x, s.y - 22.0],
			"status": [s.x, s.y + 22.0],
			"inf_band": [s.x - 32.0, s.y + 30.0, s.x + 32.0, s.y + 36.0],
			"hp_band": [s.x - 32.0, s.y + 39.0, s.x + 32.0, s.y + 43.0],
			"col": col_key,
		})
	_probe["cities"] = {"spots": spots}


func _armada_probes() -> void:
	var st: Variant = _st()
	var a: Dictionary = st.armadas[0]
	var ship: Vector2 = CivStageScript.map_to_screen(float(a["x"]), float(a["y"]),
			st.camX, st.camY, game.vw, game.vh)
	var target: Vector2 = CivStageScript.map_to_screen(float(a["tx"]), float(a["ty"]),
			st.camX, st.camY, game.vw, game.vh)
	_probe["armada"] = {
		"ship": [ship.x, ship.y],
		"route": [[target.x, target.y], [ship.x, ship.y]],
		"toast_band": [16.0, game.vh - 196.0, 330.0, game.vh - 164.0],
	}


func _sliders_probes() -> void:
	var st: Variant = _st()
	var vw: float = game.vw
	var vh: float = game.vh
	var sw := 300.0
	var sx := vw - sw - 18.0
	var sy := vh - 150.0
	var vals: Array = [st.mil, st.culture, st.econ]
	var cols := [[255, 122, 90], [201, 164, 255], [90, 208, 168]]
	var bars: Array = []
	for i in 3:
		var row: float = sy + 34.0 + float(i) * 30.0 + 6.0
		bars.append({
			"row": row,
			"x0": sx + 118.0,
			"w": maxf(3.0, 160.0 * float(vals[i]) / 10.0),
			"col": cols[i],
			"val": [sx + sw - 12.0, row - 4.0],
		})
	_probe["sliders"] = {
		"panel": [sx, sy, sx + sw, sy + 132.0],
		"title": [sx + sw / 2.0, sy + 16.0],
		"bars": bars,
		"mil": float(st.mil), "culture": float(st.culture), "econ": float(st.econ),
	}


func _portrait_probes() -> void:
	var vh: float = game.vh
	var g: Dictionary = game.context.genome
	# _metrics bakes pose.scale into body_y (size = genome size × scale), and
	# the painter's xf carries NO extra scale — the body center lands at
	# pose.y + body_y directly (one ×1.4, not two)
	var m: Dictionary = RigScript._metrics(g, {"scale": 1.4})
	var body := Vector2(66.0, vh - 40.0 + float(m["body_y"]))
	_probe["portrait"] = {
		"panel": [18.0, vh - 120.0, 114.0, vh - 24.0],
		"clip": [22.0, vh - 116.0, 110.0, vh - 28.0],
		"body": [body.x, body.y],
		"corner": [26.0, vh - 34.0],
	}


func _victory_probes() -> void:
	var st: Variant = _st()
	var spots: Array = []
	for i in [1, 2, 3]:
		var c: Dictionary = st.cities[i]
		var s: Vector2 = CivStageScript.map_to_screen(float(c["x"]), float(c["y"]),
				st.camX, st.camY, game.vw, game.vh)
		spots.append([s.x, s.y])
	_probe["victory"] = {
		"band": [game.vw / 2.0 - 220.0, game.vh / 2.0 - 206.0,
				game.vw / 2.0 + 220.0, game.vh / 2.0 - 154.0],
		"spots": spots,
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
	var checker := ProjectSettings.globalize_path("res://tools/visual_check_civ_scene.py")
	var args: Array = [checker, ProjectSettings.globalize_path(OUT_DIR + "/probes.json")]
	for name in ["civ_planet_day", "civ_cities", "civ_armada", "civ_sliders",
			"civ_portrait", "civ_victory"]:
		args.append(ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png"))
	var output: Array = []
	var code := OS.execute("python3", args, output, true)
	for line in output:
		print(String(line).strip_edges())
	if code != 0:
		printerr("VISUAL_TEST_FAIL: visual_check_civ_scene.py exited %d" % code)
		get_tree().quit(1)
	else:
		print("VISUAL_TEST_OK")
		get_tree().quit(0)
