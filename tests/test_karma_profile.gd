# Task 10 (R15) — karma profile per stage: pacifist integrity.
#   - karma_by_stage: one float per SIM-stage exit (cell/creature/tribe/civ),
#     recorded ONLY at game.gd's switch_stage choke point (quit-to-title and
#     evolution funnel through the same seam; menu/space record nothing).
#   - recover cap: positive karma gain in one stage tops out 0.15 above the
#     stage's ENTRY anchor (the previous stage's exit snapshot; a fresh cell
#     run starts at 0.0) — negative moves and the game.gd drift stay uncapped.
#   - the space ending's harmony tier additionally requires
#     karma_min() >= -0.1 (a bloody stage farmed back to pacifism reads
#     neutral); the fears path and the neutral line stay karma-only.
#   - the save wire carries karmaByStage (camelCase, TS-verbatim style);
#     pre-R15 saves derive the single-entry grace profile [karma].
# Old-save grace + the cap anchor derivation live in context.load(); the
# cluster updates pinned here mirror the ruling in task-10-brief.md verbatim.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const StageScript := preload("res://src/game/stage.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")
const SpaceStageScript := preload("res://src/game/space/space_stage.gd")

const DT := 1.0 / 60.0
const Z_TO_Y := 0.62  # creature_sim's depth squash (the bush wy anchor)

# dedicated slots (test slots 90-137 are spoken for — see the owners' headers)
const SLOT_RT := 140      # wire round-trip
const SLOT_OLD := 141     # pre-R15 save (no karmaByStage field)
const SLOT_CORRUPT := 142 # corrupt / oversized profile lists
const SLOT_EMPTY := 143   # legit empty profile (a mid-cell autosave)
const SLOT_ANCHOR := 144  # mid-creature save -> cap anchor derivation

# raw EN keys — the ending draws them through tr() (TranslationServer falls
# back to the key), the tier logic must pin the KEYS, not a locale's output
const FLAVOR_HARMONY := "The universe hums in harmony — you gardened the stars."
const FLAVOR_FEARS := "The universe fears your name — chaos was your harvest."
const FLAVOR_NEUTRAL := "The universe cannot decide what you are. It keeps watching."

const SCRATCH_CFG := "user://test_karma_settings.cfg"


## A stand-in sim stage: the switch seam needs registered ids to switch
## between, nothing else (stage.gd's surface is the update/enter/exit trio).
class FakeStage extends "res://src/game/stage.gd":
	func _init(g: Variant, id_v: String) -> void:
		super(g, id_v)


# ---- recover cap ---------------------------------------------------------------

func test_recover_cap_and_clamps() -> void:
	var ctx: Variant = Ctx.new(7)
	# the brief's pin: from entry 0.0, a +1.0 karma input clamps to +0.15
	ctx.add_karma(1.0)
	approx(float(ctx.karma), 0.15, "entry 0.0: +1.0 karma input clamps to +0.15 (R15 recover cap)", 1e-9)
	ctx.add_karma(0.5)
	approx(float(ctx.karma), 0.15, "further positive adds stay capped at the anchor")
	# negative moves are uncapped — only the ±1 meter clamp floors them
	ctx.add_karma(-1.0)
	approx(float(ctx.karma), -0.85, "negative moves uncapped", 1e-9)
	ctx.add_karma(-3.0)
	approx(float(ctx.karma), -1.0, "the ±1 clamp still floors negative adds")
	# recovery from a deep negative climbs only as far as the adds carry it,
	# then caps at entry+0.15 again (the cap is a LEVEL cap, not a per-add one)
	ctx.add_karma(1.0)
	approx(float(ctx.karma), 0.0, "recovery from -1.0 with a +1.0 add lands at 0.0", 1e-9)
	ctx.add_karma(1.0)
	approx(float(ctx.karma), 0.15, "...and the next +1.0 caps at entry+0.15", 1e-9)


func test_cap_rearm_and_run_reset() -> void:
	var ctx: Variant = Ctx.new(13)
	ctx.add_karma(0.15)
	approx(float(ctx.karma), 0.15, "preconditions: parked at the first stage's cap")
	# the switch seam re-arms the anchor at every stage entry (the standing
	# karma IS the previous stage's exit snapshot) — the next stage may earn
	# its own +0.15 above THAT anchor
	ctx.rearm_karma_stage()
	ctx.add_karma(1.0)
	approx(float(ctx.karma), 0.30, "a re-armed anchor allows a fresh +0.15 above the new standing", 1e-9)
	# a karma already ABOVE the anchor+cap (the negative-karma drift lifts an
	# aggressive player past it uncapped) must not be pulled down by adds
	ctx.karma = -0.3
	ctx._karma_entry = -0.5
	ctx.add_karma(0.01)
	approx(float(ctx.karma), -0.3, "a positive add above the cap window is blocked, never pulled down", 1e-9)
	# a NEW LIFE wipes the per-run profile and re-anchors at the cell 0.0
	# start (start_new_game resets the meter first, then the profile)
	ctx.karma_by_stage = [0.1, 0.2]
	ctx.karma = 0.9
	ctx.reset_karma_profile()
	ok(ctx.karma_by_stage.is_empty(), "NEW LIFE wipes the profile array")
	ctx.karma = 0.0  # (menu.gd resets the meter before the profile — mirrored)
	ctx.add_karma(1.0)
	approx(float(ctx.karma), 0.15, "NEW LIFE re-anchors the cap at the cell 0.0 start", 1e-9)


# ---- the switch seam -----------------------------------------------------------

## Seeded boot → menu, fake sim stages registered; the loop's kill-switch
## makes switch_stage the ONLY thing that runs (the test_game_flow pattern).
func _flow_game(seed_v: int) -> Variant:
	var ctx: Variant = Ctx.new(seed_v)
	var g: Variant = GameScript.new(ctx)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(g)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	# pin the locale/mute defaults deterministically (the shared user cfg may
	# carry anything) and keep mute/lang writes out of it
	g.i18n.settings_path = SCRATCH_CFG
	_wipe_cfg()
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.muted = g.i18n.get_muted()
	g.register(MenuStageScript.new(g))
	for id in ["cell", "creature", "tribe", "civ", "space"]:
		g.register(FakeStage.new(g, id))
	g.start()
	return g


func _wipe_cfg() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_karma_settings.cfg")
		dir.remove("test_karma_settings.cfg.tmp")


func _drop(g: Variant) -> void:
	if g != null:
		g.free()


## The full evolution walk (menu→cell→creature→tribe→civ→space→menu-quit):
## every sim-stage exit snapshots exactly once, menu/space record nothing,
## and each entry re-arms the cap anchor at the standing karma.
func test_seam_snapshots_profile() -> void:
	var g: Variant = _flow_game(0xC0FFEE)
	var ctx: Variant = g.context
	ok(ctx.karma_by_stage.is_empty(), "boot: the profile starts empty")
	# menu → cell: the MENU exit records nothing (no index for it)
	g.switch_stage("cell")
	ok(ctx.karma_by_stage.is_empty(), "leaving the menu records nothing")
	ctx.add_karma(0.125)  # under the 0.15 cap from the 0.0 cell anchor
	g.switch_stage("creature")
	eq(ctx.karma_by_stage.size(), 1, "cell exit recorded one entry")
	approx(float(ctx.karma_by_stage[0]), 0.125, "cell exit snapshot", 1e-9)
	ctx.add_karma(-0.5)  # negative: uncapped
	g.switch_stage("tribe")
	eq(ctx.karma_by_stage.size(), 2, "creature exit recorded")
	approx(float(ctx.karma_by_stage[1]), -0.375, "creature exit snapshot", 1e-9)
	# the creature ENTRY re-armed the anchor at the cell snapshot — positive
	# recovery in tribe caps 0.15 above THAT, not above 0.0
	ctx.add_karma(1.0)
	approx(float(ctx.karma), -0.225, "tribe recovery caps at entry(-0.375)+0.15", 1e-9)
	g.switch_stage("civ")
	approx(float(ctx.karma_by_stage[2]), -0.225, "tribe exit snapshot", 1e-9)
	ctx.add_karma(1.0)
	approx(float(ctx.karma), -0.075, "civ recovery caps at its own entry+0.15", 1e-9)
	g.switch_stage("space")
	eq(ctx.karma_by_stage.size(), 4, "civ exit recorded — the profile is full")
	approx(float(ctx.karma_by_stage[3]), -0.075, "civ exit snapshot", 1e-9)
	ctx.add_karma(1.0)
	approx(float(ctx.karma), 0.075, "space recovery caps at its own entry+0.15", 1e-9)
	# quit-to-title: the SPACE exit records nothing (no index) — the profile
	# is untouched, and nothing double-records through the same seam
	g.switch_stage("menu")
	eq(ctx.karma_by_stage.size(), 4, "quit-to-title: space records nothing, no 5th entry")
	approx(float(ctx.karma_by_stage[0]), 0.125, "quit-to-title left the profile intact (cell)", 1e-9)
	_drop(g)


## A menu RESUMPTION (quit-to-title → CONTINUE) must NOT re-arm the cap
## anchor at the loaded standing — the anchor stays the one load() derived
## from the profile (the stage's ORIGINAL entry snapshot), or every
## save-quit-continue cycle would mint a fresh +0.15 of headroom.
func test_seam_resumption_keeps_load_anchor() -> void:
	_wipe(SLOT_ANCHOR)
	var ctx: Variant = Ctx.new(91)
	ctx.karma = 0.125
	ctx.record_stage_exit("cell")
	ctx.karma = -0.375
	ctx.stage = "creature"
	ok(ctx.save(SLOT_ANCHOR), "mid-creature save with a cell exit on record")
	var g: Variant = _flow_game(0xC0FFEE)
	ok(g.context.load(SLOT_ANCHOR), "CONTINUE's load derives the anchor")
	g.switch_stage("creature")  # the menu→creature resumption switch
	# anchor = the cell exit (0.125), NOT the loaded standing (-0.375):
	# +1.0 of grazing caps at 0.275, not at -0.225
	g.context.add_karma(1.0)
	approx(float(g.context.karma), 0.275, "resumption keeps the load-derived anchor", 1e-9)
	_drop(g)


# ---- profile math ---------------------------------------------------------------

func test_karma_min_mean_math() -> void:
	var ctx: Variant = Ctx.new(11)
	ctx.karma_by_stage = [-0.4, 0.8]
	approx(ctx.karma_min(), -0.4, "min over the profile", 1e-9)
	approx(ctx.karma_mean(), 0.2, "mean over the profile", 1e-9)
	ctx.karma_by_stage = [0.1, 0.4]
	approx(ctx.karma_min(), 0.1, "min: clean profile", 1e-9)
	approx(ctx.karma_mean(), 0.25, "mean: clean profile", 1e-9)
	ctx.karma_by_stage = [0.0, -0.05, 0.4, 0.9]
	approx(ctx.karma_min(), -0.05, "min: four entries", 1e-9)
	approx(ctx.karma_mean(), 0.3125, "mean: four entries", 1e-9)
	# an empty profile (nothing has exited yet) reads the live standing —
	# the same graceful degradation the old-save grace relies on
	ctx.karma = -0.3
	ctx.karma_by_stage = []
	approx(ctx.karma_min(), -0.3, "empty profile: min falls back to the live karma", 1e-9)
	approx(ctx.karma_mean(), -0.3, "empty profile: mean falls back to the live karma", 1e-9)


# ---- the ending tier ------------------------------------------------------------

## The harmony gate: karma > 0.3 AND karma_min() >= -0.1. The [-0.4, 0.8]
## run (high standing, bloody stage) must read NEUTRAL; [0.1, 0.4] keeps
## harmony; the fears path stays karma-only. Pure static on the stage —
## _draw_ending feeds it (karma, ctx.karma_min()).
func test_ending_flavor_tiers() -> void:
	eq(SpaceStageScript.ending_flavor(0.8, -0.4), FLAVOR_NEUTRAL,
			"harmony refused: profile min -0.4 below the -0.1 floor (mean-high run)")
	eq(SpaceStageScript.ending_flavor(0.4, 0.1), FLAVOR_HARMONY,
			"harmony kept: karma > 0.3 and min >= -0.1")
	eq(SpaceStageScript.ending_flavor(0.8, -0.1), FLAVOR_HARMONY,
			"boundary: min == -0.1 keeps harmony")
	eq(SpaceStageScript.ending_flavor(0.8, -0.11), FLAVOR_NEUTRAL,
			"a hair below the floor loses harmony")
	eq(SpaceStageScript.ending_flavor(-0.5, -0.9), FLAVOR_FEARS,
			"fears path unchanged (karma-only, no profile gate)")
	eq(SpaceStageScript.ending_flavor(0.0, 0.0), FLAVOR_NEUTRAL,
			"middle run reads the neutral line")
	eq(SpaceStageScript.ending_flavor(0.3, 0.3), FLAVOR_NEUTRAL,
			"karma 0.3 is not > 0.3 — neutral (the TS edge, unchanged)")
	eq(SpaceStageScript.ending_flavor(-0.3, 0.0), FLAVOR_NEUTRAL,
			"karma -0.3 is not < -0.3 — neutral (the TS edge, unchanged)")


# ---- the graze rate (real write path) -------------------------------------------

## 1 second of bush-grazing pays exactly +0.005 karma (the R15 halving of the
## old dt*0.02 loophole rate). Real creature-sim hold-eat branch, the
## test_creature_sim bush pattern: every other bush/bone parked out of
## range, this one under the player, hold-eat for 60 ticks. (The sim's _fire
## hooks default to no-ops — an empty hooks dict stays silent.)
func test_graze_rate_pin_real_path() -> void:
	var ctx: Variant = Ctx.new(0xC0FFEE)
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, {})
	for b in sim.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0
	for bo in sim.bones:
		bo["x"] = 99999.0
		bo["z"] = 99999.0
	var b: Dictionary = sim.bushes[0]
	b["x"] = float(sim.px)
	b["z"] = float(sim.pz)
	b["food"] = 4.0  # 2.0/s burn — 4.0 outlasts the 1s pin without emptying
	b["regrow"] = 0.0
	for i in 60:
		sim.update(DT, {"mx": 0.0, "my": 0.0, "wx": float(sim.px),
				"wy": float(sim.pz) * Z_TO_Y, "down": true, "clicked": false,
				"take_click": false, "keys_held": [], "keys_pressed": []})
	approx(float(ctx.karma), 0.005, "1s of grazing = +0.005 karma (R15 pin, was 0.02)", 1e-9)


# ---- the save wire ----------------------------------------------------------------

func _path(n: int) -> String:
	return "user://saves/slot%d.json" % n


func _wipe(n: int) -> void:
	if FileAccess.file_exists(_path(n)):
		DirAccess.remove_absolute(_path(n))


func _write_json(n: int, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(_path(n), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))


## Minimal valid v1 blob (test_context's _base shape) with karma overrides.
func _base(karma_v: float) -> Dictionary:
	return {
		"version": 1, "seed": 555, "stage": "creature", "difficulty": "normal",
		"genome": {}, "dna": 10, "karma": karma_v, "chaos": 0.15, "playtime": 0.0,
		"totalDnaEarned": 0, "playerName": "Squish", "bestiary": [], "eco": null,
		"flags": {},
	}


func test_save_wire_round_trip() -> void:
	_wipe(SLOT_RT)
	var ctx: Variant = Ctx.new(77)
	ctx.karma = 0.125
	ctx.record_stage_exit("cell")
	ctx.karma = -0.375
	ctx.record_stage_exit("creature")
	ctx.stage = "creature"
	ok(ctx.save(SLOT_RT), "save with a two-entry profile")
	var f := FileAccess.open(_path(SLOT_RT), FileAccess.READ)
	ok(f != null, "slot file readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	ok(parsed is Dictionary, "slot file parses")
	if not (parsed is Dictionary):
		return
	ok((parsed as Dictionary).has("karmaByStage"), "wire key karmaByStage present")
	var prof: Variant = (parsed as Dictionary)["karmaByStage"]
	ok(prof is Array and (prof as Array).size() == 2, "wire carries both exits")
	if prof is Array and (prof as Array).size() == 2:
		eq((prof as Array)[0], 0.125, "wire exit 0 bit-exact (full-precision JSON)")
		eq((prof as Array)[1], -0.375, "wire exit 1 bit-exact")
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_RT), "load round-trips")
	eq(loader.karma_by_stage.size(), 2, "profile restored")
	eq(float(loader.karma_by_stage[0]), 0.125, "profile exit 0 restored")
	eq(float(loader.karma_by_stage[1]), -0.375, "profile exit 1 restored")
	approx(loader.karma_min(), -0.375, "karma_min reads the restored profile", 1e-9)
	approx(loader.karma_mean(), -0.125, "karma_mean reads the restored profile", 1e-9)


## Pre-R15 saves (field absent) derive the single-entry grace profile
## [karma] — karma_min()/karma_mean() degrade to the live standing (the
## harmony gate collapses to the old karma-only check) and the recover cap
## anchors at the loaded karma.
func test_load_grace_old_save() -> void:
	_wipe(SLOT_OLD)
	_write_json(SLOT_OLD, _base(-0.4))
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_OLD), "pre-R15 save loads")
	eq(loader.karma_by_stage.size(), 1, "grace: one derived entry")
	approx(float(loader.karma_by_stage[0]), -0.4, "grace entry is the loaded karma", 1e-9)
	approx(loader.karma_min(), -0.4, "grace: min reads the standing", 1e-9)
	approx(loader.karma_mean(), -0.4, "grace: mean reads the standing", 1e-9)
	loader.add_karma(1.0)
	approx(float(loader.karma), -0.25, "grace: the cap anchors at the loaded standing", 1e-9)


func test_load_profile_validation() -> void:
	# corrupt element → the whole list drops to the grace profile (the
	# bestiary's one-bad-apple rule)
	_wipe(SLOT_CORRUPT)
	var blob := _base(0.5)
	blob["karmaByStage"] = [0.1, "x", 0.3]
	_write_json(SLOT_CORRUPT, blob)
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_CORRUPT), "corrupt list loads with the grace fallback")
	eq(loader.karma_by_stage.size(), 1, "corrupt list → grace")
	approx(float(loader.karma_by_stage[0]), 0.5, "grace entry is the loaded karma", 1e-9)
	# a non-array field is the same grace path
	blob["karmaByStage"] = "garbage"
	_write_json(SLOT_CORRUPT, blob)
	var loader2: Variant = Ctx.new()
	ok(loader2.load(SLOT_CORRUPT), "non-array field loads with the grace fallback")
	eq(loader2.karma_by_stage.size(), 1, "non-array → grace")
	# more than 4 exits cannot happen (4 sim stages) — a longer list truncates
	blob["karmaByStage"] = [0.1, 0.2, 0.3, 0.4, 9.9, 8.8]
	_write_json(SLOT_CORRUPT, blob)
	var loader3: Variant = Ctx.new()
	ok(loader3.load(SLOT_CORRUPT), "oversized list loads")
	eq(loader3.karma_by_stage.size(), 4, "oversized list truncates to 4")
	approx(float(loader3.karma_by_stage[3]), 0.4, "truncation keeps the first 4 in order", 1e-9)
	# hand-edited ints coerce to floats; out-of-range values clamp to the meter
	blob["karmaByStage"] = [1, -2]
	_write_json(SLOT_CORRUPT, blob)
	var loader4: Variant = Ctx.new()
	ok(loader4.load(SLOT_CORRUPT), "int elements load")
	eq(float(loader4.karma_by_stage[0]), 1.0, "int coerces; +1 clamps")
	eq(float(loader4.karma_by_stage[1]), -1.0, "int coerces; -1 clamps")


## An EMPTY karmaByStage is legitimate (a mid-cell autosave — no stage has
## exited yet): it must be KEPT empty, not mistaken for the missing-field
## grace, and the cell anchor stays the 0.0 start. (The standing is negative
## so the anchor pin is behavioral: recovery from -0.2 caps at 0.0+0.15 — an
## anchor at the loaded standing would cap at -0.05 instead.)
func test_load_empty_profile_kept() -> void:
	_wipe(SLOT_EMPTY)
	var blob := _base(-0.2)
	blob["stage"] = "cell"
	blob["karmaByStage"] = []
	_write_json(SLOT_EMPTY, blob)
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_EMPTY), "empty-profile save loads")
	ok(loader.karma_by_stage.is_empty(), "empty profile kept empty (not the grace array)")
	approx(loader.karma_min(), -0.2, "empty profile: min reads the live karma", 1e-9)
	loader.add_karma(1.0)
	approx(float(loader.karma), 0.15, "mid-cell anchor stays the 0.0 start", 1e-9)


## The recover-cap anchor derives from the profile: a mid-creature save
## anchors at the CELL exit (the previous stage's snapshot), not at the
## current standing.
func test_load_entry_anchor() -> void:
	_wipe(SLOT_ANCHOR)
	var ctx: Variant = Ctx.new(91)
	ctx.karma = 0.125
	ctx.record_stage_exit("cell")
	ctx.karma = -0.375
	ctx.stage = "creature"
	ok(ctx.save(SLOT_ANCHOR), "mid-creature save with a cell exit on record")
	var loader: Variant = Ctx.new()
	ok(loader.load(SLOT_ANCHOR), "load")
	loader.add_karma(1.0)
	approx(float(loader.karma), 0.275, "anchor = the cell exit (0.125) + the 0.15 cap", 1e-9)
