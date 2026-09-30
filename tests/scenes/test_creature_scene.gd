# Creature-stage scene test (xvfb, Compatibility renderer) — task 7. Boots a
# REAL Game with a pinned world seed + pinned player genome (size 1.0, hue 120,
# legs 4, spots+fur, no tail), enters the creature stage, waits for the arrival
# invuln to decay AND the arrival banner to expire AND the camera follow to
# converge (all condition-based — deterministic per seed up to one step), then
# freezes the sim and captures three frames via get_viewport().get_texture():
#   creature_day.png   — the settled day frame (lawn/sky/vignette/HP-bar)
#   creature_zsort.png — Ruling 14: sim.ents cleared, player pinned at z 50, a
#                        hue-15 ent injected at (px+30, z 100) — the ent draws
#                        ABOVE the player where they overlap
#   creature_night.png — dayPhase forced to 0.7 (isNight window): the overlay
#                        dims the frame and the 20 deterministic fireflies show
# Anchors for the z-sort probes are computed HERE from the rig metrics + the
# live camera (the TS manual transform formula) and passed to
# tools/visual_check_creature_scene.py, which mirrors them onto the pixels.
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


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		printerr("VISUAL_TEST_FAIL: timeout in phase %s (invuln=%s cam=%s)" % [
			_phase, str(game.current.sim.invuln), str(game.cam.x)])
		get_tree().quit(1)
		return
	match _phase:
		"boot":
			# settle: arrival invuln decayed (player paints opaque), arrival
			# banner expired (no hud overlay over the sky), camera follow
			# converged onto the player (probe anchors exact)
			var st: Variant = game.current.sim
			var hud: Variant = game.current.hud_inst
			var cam_converged: bool = absf(game.cam.x - st.px) < 1.0 \
					and absf(game.cam.y - st.pz * Z_TO_Y) < 1.0
			if st.invuln <= 0.0 and cam_converged \
					and hud._cur_banner == null and hud._banner_queue.is_empty():
				_phase = "freeze"
		"freeze":
			game.current.frozen = true
			_phase = "fixture"
		"fixture":
			# Ruling 14 fixture: the player alone at z 50, a red ent at z 100.
			# The fixture world serves BOTH captures — day and zsort are then
			# the same frozen content (a free llvmpipe determinism twin) and
			# the lawn/sky/vignette/HP asserts run without wild-ent noise.
			var st: Variant = game.current.sim
			st.pz = 50.0
			st.ents.clear()
			st.bushes.clear()
			st.bones.clear()
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
			_probe = _compute_probes(st, ent)
			_phase = "day_arm"
		"day_arm":
			_phase = "day_shot"  # next frame's texture holds the drawn state
		"day_shot":
			_capture("creature_day.png")
			_phase = "zsort_arm"
		"zsort_arm":
			_phase = "zsort_shot"  # determinism twin: same commands, one frame on
		"zsort_shot":
			_capture("creature_zsort.png")
			_phase = "night_setup"
		"night_setup":
			game.current.sim.dayPhase = 0.7  # inside the (0.55, 0.95) window
			# the fireflies' twinkle phase rides sim.time — pinned to a value
			# where 8 of the 20 deterministic flies sit bright (tw >= 0.9) in
			# the checker's scanned bands (computed from the TS formulas)
			game.current.sim.time = 40.05
			_phase = "night_arm"
		"night_arm":
			_phase = "night_shot"
		"night_shot":
			_capture("creature_night.png")
			_phase = "check"
		"check":
			_phase = "done"
			_run_checker()


## Screen anchors for the checker's probes: the TS manual camera transform
## (cam.gd to_world's inverse) — (world − cam)·zoom + center. Shake is 0 at
## capture (no shake sources fire while frozen).
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
		# the ent's tapered tail end reaches ~66px left of its center on screen
		# (measured on the capture); the player's own body edge starts ~70px
		# left of its center — the probe sits in the visible green sliver
		"green_x": player_feet.x - 58.0,
	}


func _capture(file_name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("VISUAL_TEST_FAIL: save_png %s → %s" % [file_name, str(err)])
		get_tree().quit(1)
	else:
		print("captured %s/%s" % [OUT_DIR, file_name])


func _run_checker() -> void:
	var checker := ProjectSettings.globalize_path("res://tools/visual_check_creature_scene.py")
	var args: Array = [checker,
			ProjectSettings.globalize_path(OUT_DIR + "/creature_day.png"),
			ProjectSettings.globalize_path(OUT_DIR + "/creature_zsort.png"),
			ProjectSettings.globalize_path(OUT_DIR + "/creature_night.png"),
			str(_probe["px"]), str(_probe["player_cy"]),
			str(_probe["ent_cx"]), str(_probe["ent_cy"]), str(_probe["green_x"])]
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
