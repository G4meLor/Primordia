# Task 16 — the binding pacifist proof: a 0-kill run through ALL FIVE stages
# must reach the harmony ending (the spec's red-team definition — "đường
# thuần pacifist (0 kill) phải ĐẠT harmony", gated karma > 0.3 AND the R15
# per-stage profile floor karma_min() >= -0.1, SpaceStage.ending_flavor).
#
# COMPOSITION (documented — no single bot covers the whole arc): the scene
# bots ride the attack route (test_bot_space's civ legs are the Q-transfer +
# honest-launch armada) and the pacifist civ bound (~989 s game-time) exceeds
# the scene bots' whole-arc frame budget (the task-15 documented deviation),
# so — per the established sim-level bot pattern (bot_civ_attach.gd's header:
# the M2 input-SNAPSHOT surface, one frame per tick) — this test drives the
# REAL per-stage sims of ONE real Game, on ONE context, crossing the REAL
# game.gd switch_stage seam between legs (record_stage_exit → run_shape snap
# → stage on_exit → rearm → next on_enter: the exact sequence at game.gd:308
# -336). The armed card transition each leg's REAL go_to hook produces is
# dropped at the seam (the hook DID fire — ascend audio, save_all, the card
# — the composition just walks past the fade).
#
# The legs, each riding its established pattern:
#   cell     — real CellSim: park every wild ent beyond the play space (the
#              test isolation seam — the automatic overlap bite must never
#              find a target, so 0 kills is structural, not lucky), eat
#              pellets through contact (plants + three REAL spawn_pellet
#              "meat" carrion = the scavenge channel), buy legs through the
#              REAL editor click_part buy (65 DNA — the forage pays for it),
#              leave through the REAL shore click (cell_sim fires the
#              shore_travel hook itself, cell_sim.gd:336-339).
#   creature — real CreatureSim: the test_charm beat-tick charm (F-hold init
#              + 3 in-zone beat presses, one befriend each), the bush graze
#              channel (the test_karma_profile hold-eat pattern), then the
#              REAL found_tribe() — whose REAL on_exit (via the seam) writes
#              the R14 ecoHealth snapshot the civ leg consumes.
#   tribe    — real TribeSim: the everyone-gathers economy up the REAL totem
#              gate (food 100 + wood 80), one REAL festival() (the chaos
#              event's apply path — the scheduler itself rides the silenced
#              probe rig), KeyT raise through try_totem, the totem-victory
#              path to victoryFired. NO warrior role is ever assigned and
#              the chief never marches — the drums -0.05 join (tribe_sim's
#              update_rival_warriors) must stay unfired; raid defense is the
#              villagers' own auto-fight (no karma write in the sim).
#   civ      — real CivSim: the task-15 pacifist_run policy VERBATIM (A ×4
#              drain, W ×7 culture, E ×7 econ, wait) — launches must stay 0
#              forever; completion rides the R14 output (the ecoHealth the
#              creature leg's REAL on_exit wrote) and the 0.014 hearts knob.
#   space    — real SpaceSim: the test_probe_space finale pattern (three
#              colonies seeded at 19.5 pop — the probe's direct-seam
#              precedent — grown through the REAL ff to the trigger, then
#              the core approach to endingDone).
#
# Chaos rides the probe rig (test_probe_space._silence_chaos): each leg's
# sim.chaos.gap = 1e9 after the switch — the pacifist proof pins the karma
# ROUTE, not the chaos stress; every leg stays deterministic per seed.
#
# Save slot 153 (the 90-152 test slots are spoken for — see their headers):
# the run's REAL saves (shore save_all, found_tribe flush, the tribe
# victory's save_all) land there, never on a player slot.

extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const DT := 1.0 / 60.0
const Z_TO_Y := 0.62  # creature_sim's depth squash (the bush wy anchor)

const SEED := 0xC1A55
const SLOT := 153
const SCRATCH_CFG := "user://test_pacifist_arc_settings.cfg"

# raw EN key — the ending draws it through tr() (the karma test's pin rule:
# pin the KEY, not a locale's output)
const FLAVOR_HARMONY := "The universe hums in harmony — you gardened the stars."

# the legs' budgets (game-time seconds; a stall dies the guard loudly)
const CELL_BUDGET := 420.0
const TRIBE_BUDGET := 1500.0
const CIV_BUDGET := 1500.0


# ---- harness -------------------------------------------------------------------

func _wipe_cfg() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_pacifist_arc_settings.cfg")
		dir.remove("test_pacifist_arc_settings.cfg.tmp")


## The test_karma_profile._flow_game shape: a real Game out of the tree
## (nothing draws — no canvas RIDs boot), all five REAL stages registered
## with manual _ready, booted straight into the cell stage.
func _boot() -> Dictionary:
	_wipe_cfg()
	var ctx: Variant = Ctx.new(SEED)
	ctx.slot = SLOT
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.loop.is_active_cb = func() -> bool: return false
	# pin the locale/mute defaults deterministically (the shared user cfg may
	# carry anything) and keep mute/lang writes out of it
	game.i18n.settings_path = SCRATCH_CFG
	_wipe_cfg()
	game.i18n.load_settings()
	game.i18n.set_lang("en")
	game.muted = game.i18n.get_muted()
	for id in ["cell", "creature", "tribe", "civ", "space"]:
		var stage: Variant = load("res://src/game/%s/%s_stage.gd" % [id, id]).new(game)
		game.register(stage)
		stage._ready()
	game.switch_stage("cell")
	return {"game": game, "ctx": ctx}


## The seam mirror of the card transition's tail: drop the armed card (the
## REAL go_to hook already fired — audio, save, the transition state) and
## walk the REAL switch_stage seam (karma record → shape snap → on_exit →
## rearm → on_enter).
func _cross(game: Variant, to: String) -> void:
	game.transition = null
	game.pending_go_to = null
	game.switch_stage(to)


func _silence(game: Variant, id: String) -> void:
	game.stages[id].sim.chaos.gap = 1.0e9


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


## WASD direction from a world-space delta (the cell sim normalizes the
## key axes itself) — keys_held steering never sets `down`, so the
## automatic overlap bite is the only kill channel and it has no targets.
func _inp_dir(dx: float, dy: float) -> Dictionary:
	var held: Array = []
	if dy < -1e-3:
		held.append("KeyW")
	if dy > 1e-3:
		held.append("KeyS")
	if dx < -1e-3:
		held.append("KeyA")
	if dx > 1e-3:
		held.append("KeyD")
	return _inp({"keys_held": held})


# ---- leg 1: cell — scavenge, forage, buy legs, shore travel --------------------

func _cell_leg(game: Variant, ctx: Variant, trace: Dictionary) -> void:
	_silence(game, "cell")
	var sim: Variant = game.stages["cell"].sim
	# isolation seam: every wild ent beyond the play space, velocity zeroed —
	# the automatic overlap bite (cell_sim's "our bite (automatic when
	# overlapping)") must never find a target
	for e in sim.ents:
		e["x"] = 1.0e6
		e["y"] = 1.0e6
		e["vx"] = 0.0
		e["vy"] = 0.0
	# the scavenge channel: three carcasses' worth dropped by the REAL
	# spawner beside the player (the carrion AI deaths would leave — the
	# isolation seam removes the deaths, not the carrion)
	for i in 3:
		sim.spawn_pellet("meat", float(sim.px) + 30.0 + 25.0 * float(i), float(sim.py))
	# forage: nearest-pellet contact eating until the legs buy is funded
	# (the REAL editor price, parts.gd legs base_cost 65)
	var guard := 0
	var budget := int(CELL_BUDGET / DT)
	while float(ctx.dna) < 65.0 and guard < budget:
		guard += 1
		var best: Variant = null
		var best_d := 1.0e18
		for p in sim.pellets:
			var d: float = Vector2(float(p["x"]) - float(sim.px),
					float(p["y"]) - float(sim.py)).length_squared()
			if d < best_d:
				best_d = d
				best = p
		if best != null and best_d < 900.0 * 900.0:
			sim.update(DT, _inp_dir(float(best["x"]) - float(sim.px),
					float(best["y"]) - float(sim.py)))
		else:
			sim.update(DT, _inp())  # wait for the flora-fed respawn
	ok(float(ctx.dna) >= 65.0,
			"cell: the forage funded the legs buy (dna %s)" % str(ctx.dna))
	# the REAL editor buy (test_editor's click_part path: spend_dna gate →
	# genome gene → refresh_stats → the sim's on_stats_changed recompute)
	var editor: Variant = game.stages["cell"].editor_inst
	editor.mode = "cell"
	var legs_row: Variant = null
	for r in editor.build_rows():
		# part rows carry def; diet/pattern/size rows are other shapes
		if r.has("def") and String(r["def"].get("id", "")) == "legs":
			legs_row = r
	ok(legs_row != null, "cell: the editor row set carries the legs part")
	if legs_row != null:
		editor.click_part(legs_row, "+")
	eq(float(ctx.genome.get("legs", 0.0)), 1.0, "cell: legs grafted (the shore gate's live-genome read)")
	# the REAL shore click — the sim fires the shore_travel hook itself
	# (cell_sim.gd:336-339: ascend audio + game_save_all + the armed card)
	var crossed := false
	for i in 12:
		sim.update(DT, _inp({"mx": 50.0, "my": 20.0, "clicked": true}))
		if game.transition != null:
			crossed = true
			break
	ok(crossed, "cell: the shore click opened the creature card (shore_travel hook)")
	eq(int(ctx.world_stats["kills"]), 0, "cell: ZERO kills (the world-story counter)")
	trace["cell_exit_karma"] = float(ctx.karma)
	trace["cell_time"] = float(sim.time)
	trace["cell_eaten"] = int(sim.tut["eaten"])
	_cross(game, "creature")


# ---- leg 2: creature — charm the pack, graze, found the tribe ------------------

func _charm_tick(sim_v: Variant, marker: float, press: bool) -> void:
	sim_v.charmMarker = marker
	var over: Dictionary = {"keys_held": ["KeyF"]}
	if press:
		over["keys_pressed"] = ["Space"]
	sim_v.update(DT, _inp(over))


func _creature_leg(game: Variant, ctx: Variant, trace: Dictionary) -> void:
	_silence(game, "creature")
	var sim: Variant = game.stages["creature"].sim
	# isolation seam: the arrival's wild ents out of charm/bite reach
	for e in sim.ents:
		e["x"] = 1.0e6
		e["z"] = 0.0
	# two charm targets beside the player (the test_charm spawn shape —
	# herbivores, small: the pacifist befriend, never a fight)
	var e1: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	var e2: Dictionary = sim.spawn_ent(null, float(sim.px) + 80.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	_charm_tick_sequence(sim)
	eq(bool(e1["pack"]), true, "creature: first befriend (charm beat 3-hit)")
	_charm_tick_sequence(sim)
	eq(bool(e2["pack"]), true, "creature: second befriend (the pack limit is 2 at the default arms/brain)")
	eq(int(ctx.world_stats["kills"]), 0, "creature: ZERO kills")
	# the graze channel (the test_karma_profile hold-eat pattern: a bush
	# under the player, hold-eat 12 s — the R15 +0.005/s halved rate)
	var b: Dictionary = sim.bushes[0]
	b["x"] = float(sim.px)
	b["z"] = float(sim.pz)
	b["food"] = 4.0
	b["regrow"] = 0.0
	for i in int(12.0 / DT):
		b["food"] = 4.0  # held full — the karma channel, not a hunger sim
		sim.update(DT, _inp({"down": true, "wx": float(sim.px),
				"wy": float(sim.pz) * Z_TO_Y}))
	# the REAL founding (the pack snapshot + the ascend + the armed card);
	# the mirror reads it so the tutorial-finish gate rides the evolve intent
	sim.transitionTarget = "tribe"
	sim.found_tribe()
	ok(game.transition != null, "creature: found_tribe opened the tribe card")
	trace["creature_exit_karma"] = float(ctx.karma)
	trace["creature_time"] = float(sim.time)
	# the REAL on_exit runs INSIDE _cross (the R14 ecoHealth snapshot write)
	_cross(game, "tribe")
	var eco_h: Variant = ctx.flags.get("ecoHealth", null)
	ok(eco_h is float and float(eco_h) > 0.0 and float(eco_h) <= 1.0,
			"creature: the REAL on_exit wrote ecoHealth (%s)" % str(eco_h))
	trace["eco_health"] = float(eco_h) if eco_h is float else -1.0


func _charm_tick_sequence(sim_v: Variant) -> void:
	# the test_charm.test_charm_sequence_befriends drive verbatim: F-hold
	# init, beat 1 (zone 0.35), re-arm, beat 2 (0.30), re-arm, beat 3 (0.25)
	sim_v.update(DT, _inp({"keys_held": ["KeyF"]}))
	_charm_tick(sim_v, 0.0, true)
	_charm_tick(sim_v, 0.5, false)
	_charm_tick(sim_v, 0.05, true)
	_charm_tick(sim_v, -0.6, false)
	_charm_tick(sim_v, -0.05, true)


# ---- leg 3: tribe — the gathering economy, the festival, the totem victory -----

func _tribe_leg(game: Variant, ctx: Variant, trace: Dictionary) -> void:
	_silence(game, "tribe")
	var sim: Variant = game.stages["tribe"].sim
	# the chief steps out of the raid path — the war party marches the
	# nearest HUT while the village stands (tribe_sim update_beast/march),
	# and the chief-cut roll needs the chief within 40px of a raider
	sim.px = float(sim.huts[0]["x"]) + 400.0
	sim.pz = float(sim.huts[0]["z"])
	var festival_done := false
	var totem_seen := false
	var karma_at_entry := float(ctx.karma)
	var guard := 0
	var budget := int(TRIBE_BUDGET / DT)
	while not bool(sim.victoryFired) and guard < budget:
		guard += 1
		var inp := _inp()
		# the REAL totem button on a 10 s cadence — try_totem's gate refuses
		# (the have-toast) until the stock holds 100 food + 80 wood. The
		# festival goes FIRST: its 20-food cost rides on top of the totem's
		# 100 (food ≥ 120), and raising the totem early would spend the fund
		# and starve the pacifist karma channel out of the leg.
		if festival_done and guard % int(10.0 / DT) == 0:
			inp["keys_pressed"] = ["KeyT"]
		sim.update(DT, inp)
		# the festival channel: the REAL festival action (the chaos event's
		# apply path) once the feast fund affords its 20 food
		if not festival_done and float(sim.food) >= 120.0 \
				and not bool(sim.totem["active"]):
			sim.festival()
			festival_done = true
		if bool(sim.totem["active"]):
			totem_seen = true
	ok(totem_seen, "tribe: the totem rose (the REAL try_totem gate passed)")
	ok(bool(sim.victoryFired), "tribe: the totem-victory path fired (TS:400-409)")
	ok(festival_done, "tribe: the festival channel fired (+0.08 karma)")
	# the drums-join must NEVER fire — no warrior role assigned, the chief
	# never marched: the -0.05 war unify (tribe_sim update_rival_warriors)
	# needs the player's warriors within 90px of a rival. Evidence: the leg's
	# karma only ever climbed (every karma write in the leg is a positive
	# add) and every rival still stands (their hp's only writer is that path).
	ok(float(ctx.karma) >= karma_at_entry - 1e-9,
			"tribe: karma never dropped (the -0.05 drums-join never fired)")
	var rivals_alive := true
	for r in sim.rivals:
		if float(r["hp"]) <= 0.0:
			rivals_alive = false
	ok(rivals_alive, "tribe: every rival village still stands (no war unify)")
	eq(int(ctx.world_stats["kills"]), 0, "tribe: ZERO kills")
	trace["tribe_exit_karma"] = float(ctx.karma)
	trace["tribe_time"] = float(sim.time)
	trace["tribe_food"] = float(sim.food)
	_cross(game, "civ")


# ---- leg 4: civ — the culture route (the task-15 pacifist policy verbatim) -----

func _civ_leg(game: Variant, ctx: Variant, trace: Dictionary) -> void:
	_silence(game, "civ")
	var sim: Variant = game.stages["civ"].sim
	# bot_civ_attach.pacifist_run's policy verbatim: drain mil (A ×4), fill
	# culture (W ×7) and econ (E ×7) — then wait on the hearts lane; the
	# launch counter must stay 0 forever (Digit1/2/3 never pressed)
	for i in 4:
		sim.update(DT, _inp({"keys_pressed": ["KeyA"]}))
	for i in 7:
		sim.update(DT, _inp({"keys_pressed": ["KeyW"]}))
	for i in 7:
		sim.update(DT, _inp({"keys_pressed": ["KeyE"]}))
	var guard := 0
	var budget := int(CIV_BUDGET / DT)
	while not bool(sim.victoryFired) and guard < budget:
		guard += 1
		sim.update(DT, _inp())
	ok(bool(sim.victoryFired),
			"civ: the culture route completed (%.0f s game-time, output %.0f)"
			% [float(sim.time), float(sim.output)])
	ok(float(sim.time) <= 1200.0,
			"civ: pacifist completion ≤ 1200 s (got %.0f)" % float(sim.time))
	eq(int(sim.launches), 0, "civ: ZERO launches (no armadas — Digit1 never pressed)")
	trace["civ_exit_karma"] = float(ctx.karma)
	trace["civ_time"] = float(sim.time)
	trace["civ_output"] = float(sim.output)
	trace["civ_culture"] = float(sim.culture)
	trace["civ_econ"] = float(sim.econ)
	_cross(game, "space")


# ---- leg 5: space — the finale, the ending, the harmony gate -------------------

func _space_leg(game: Variant, ctx: Variant, trace: Dictionary) -> Dictionary:
	_silence(game, "space")
	var sim: Variant = game.stages["space"].sim
	# the test_probe_space finale pattern: three colonies seeded at 19.5 pop
	# (the probe's direct-seam precedent), the REAL ff to the trigger
	for i in 3:
		sim.planets[i]["colony"] = {"pop": 19.5, "generations": 0.0}
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	sim.update(1.0, _inp({"keys_held": ["KeyF"]}))
	ok(sim.finale != null, "space: THE CHAOS CORE AWAKENS (the REAL 3-thriving trigger)")
	# the core approach — d 50 < 60 flips endingDone (TS:569-570)
	sim.sx = 0.0
	sim.sy = -1850.0
	sim.update(1.0, _inp())
	eq(bool(sim.endingDone), true, "space: the ending reached (endingDone)")
	# THE gate — the exact inputs _draw_ending feeds ending_flavor
	var karma_v := float(ctx.karma)
	var kmin := float(ctx.karma_min())
	var flavor := String(SpaceStageScript.ending_flavor(karma_v, kmin))
	trace["final_karma"] = karma_v
	trace["karma_min"] = kmin
	trace["flavor"] = flavor
	print("PACIFIST_ARC_TRACE %s" % JSON.stringify(trace))
	print("PACIFIST_ARC_PROFILE %s" % JSON.stringify(ctx.karma_by_stage))
	print("PACIFIST_ARC_KILLS %d" % int(ctx.world_stats["kills"]))
	print("PACIFIST_ARC_ENDING %s" % flavor)
	return {"karma": karma_v, "kmin": kmin, "flavor": flavor}


# ---- the binding test ------------------------------------------------------------

func test_pacifist_arc_end_to_end() -> void:
	var m := _boot()
	var game: Variant = m["game"]
	var ctx: Variant = m["ctx"]
	var trace: Dictionary = {}
	_cell_leg(game, ctx, trace)
	_creature_leg(game, ctx, trace)
	_tribe_leg(game, ctx, trace)
	_civ_leg(game, ctx, trace)
	var end_v: Dictionary = _space_leg(game, ctx, trace)
	# the binding definition: 0 kills through the whole arc, harmony reached
	eq(int(ctx.world_stats["kills"]), 0, "ARC: ZERO kills across all five stages")
	eq(String(end_v["flavor"]), FLAVOR_HARMONY,
			"ARC: the 0-kill run reaches the HARMONY ending")
	ok(float(end_v["karma"]) > 0.3,
			"ARC: the ending's live karma clears the 0.3 gate (%.3f)" % float(end_v["karma"]))
	ok(float(end_v["kmin"]) >= -0.1,
			"ARC: the per-stage profile floor holds (min %.3f ≥ -0.1)" % float(end_v["kmin"]))
	eq(ctx.karma_by_stage.size(), 4, "ARC: the profile carries all four sim-stage exits")
	# the heredity seam rode the same switches (the R12 run_shape snap)
	ok(String(ctx.run_shape) != "", "ARC: the run_shape seam snapped at the exits")
	# break the overlay Callable cycles before free (the test_game_flow pattern)
	game.hud = {}
	game.editor = {}
	game.pause = {}
	game.free()
