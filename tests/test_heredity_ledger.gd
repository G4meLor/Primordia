# Task 14 (R12) — the heredity ledger cheap: Shape/Conduct snapshot + first
# consumers. Layers (mirrors task-14-brief.md verbatim):
#   1. the pure classifier shape_of(genome) -> predator|minder|wall —
#      predator = jaw + spikes + size_rank (the size gene normalized against
#      its GENE_BOUNDS into 0..2), minder = eyes + arms + brain, wall =
#      coat_score (the COATS defense order, skin 0 → plates 3) + horns;
#      highest score wins, ANY tie for the top → predator (controller ruling),
#   2. the switch seam recomputes context.run_shape at every stage exit
#      (LATEST-only — the civ consumers read the latest snapshot),
#   3. the civ consumers — rival_def_for ±1 by shape (predator −1 / wall +1),
#      the start output 10±2 by conduct_avg (> +0.15 → +2, < −0.15 → −2),
#      the minder charm/trade karma +0.01 extra, the wall city hp regen
#      +0.3/s at the existing regen site,
#   4. the card line — the civ-bound transition card names the national
#      trait, the space-bound card the fleet legacy (real perks deferred —
#      red-team cheap ruling); tr_key at draw (the R10 i18n ruling), other
#      destinations and a not-yet-snapped shape draw nothing,
#   5. the save wire — runShape round-trips (camelCase); an old save WITHOUT
#      the field computes from the (always-present) genome — no hardcoded
#      default; a corrupt value likewise; conduct is NOT persisted (it
#      derives from karmaByStage via conduct_avg()).
#   6. the balance probe — an armada-only predator+high-conduct civ bot run
#      must not complete below 60% of the neutral baseline's time (the
#      documented clamp: output bonus +2 → +1, applied only on violation).
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const ShapeScript := preload("res://src/evo/shape.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const GameScript := preload("res://src/game/game.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const StageScript := preload("res://src/game/stage.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const SEED := 0x5EED
const SCRATCH_CFG := "user://test_heredity_settings.cfg"

# dedicated slots (90-147 spoken for — see the owners' headers)
const SLOT_RT := 150      # runShape wire round-trip
const SLOT_OLD := 151     # pre-R12 save (no runShape field)
const SLOT_CORRUPT := 152 # corrupt runShape value


# ---- fixtures -------------------------------------------------------------------

# A clamped-shape genome: the defaults with the pinned overrides merged on.
func _g(over: Dictionary = {}) -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g.merge(over, true)
	return g


func _wipe_cfg() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(SCRATCH_CFG)


func _i18n(lang: String) -> Variant:
	_wipe_cfg()
	var i18n: Variant = I18nScript.new(SCRATCH_CFG)
	i18n.set_lang(lang)
	return i18n


# The test_civ_sim harness shape: real context (explicit seed), the stage rng
# branch, recording hooks, the sim. The heredity inputs (run_shape + the
# karma profile) ride the context directly — the wire/load path is pinned
# separately below.
func _mk_sim(seed_v: int, shape := "", profile: Array = []) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.difficulty = "normal"
	ctx.run_shape = shape
	ctx.karma_by_stage = profile
	var rec: Dictionary = {
		"toasts": [], "banners": [], "audio": [], "shakes": [], "spawns": [],
		"objectives": [], "insets": [], "moods": [], "floats": [], "abilities": [],
		"gotos": [], "saves": 0, "notes": [],
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_toast_inset": func(px): rec["insets"].append(px),
		"hud_show_objective": func(text): rec["objectives"].append(text),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"hud_set_abilities": func(list): rec["abilities"].append(list),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"audio_set_mood": func(name_v): rec["moods"].append(name_v),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"go_to": func(stage_v, data): rec["gotos"].append([stage_v, data]),
		"save_all": func(): rec["saves"] = int(rec["saves"]) + 1,
	}
	var sim: Variant = CivSim.new(ctx, ctx.rng.branch(), hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


# Idle input snapshot — the sim's documented contract shape (civ reads
# keys_pressed only).
func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"keys_held": [], "keys_pressed": []}
	d.merge(over, true)
	return d


# ---- 1. the classifier ----------------------------------------------------------

func test_classifier_pins_all_three_shapes() -> void:
	# default body: predator 1.5 (jaw 1 + spikes 0 + rank 0.5) vs minder 1
	# (eyes 1) vs wall 0 (skin 0, horns 0) → predator
	eq(ShapeScript.shape_of(_g()), "predator",
			"default genome: the jaw edge already reads predator-line")
	# predator-heavy: jaw 3 + spikes 2 + rank(2.0) = 1.75 → 6.75
	eq(ShapeScript.shape_of(_g({"jaw": 3, "spikes": 2, "size": 2.0})), "predator",
			"jaw+spikes+size dominance → predator")
	# minder: eyes 4 + arms 3 + brain 2 → 9 (offense 0, defense 0)
	eq(ShapeScript.shape_of(_g({"eyes": 4, "arms": 3, "brain": 2,
			"jaw": 0, "spikes": 0, "size": 0.6})), "minder",
			"eyes+arms+brain dominance → minder")
	# wall: plates (3) + horns 3 → 6 (offense 0, senses 1)
	eq(ShapeScript.shape_of(_g({"coat": "plates", "horns": 3,
			"jaw": 0, "spikes": 0, "size": 0.6})), "wall",
			"coat+horns dominance → wall")


func test_classifier_ties_break_predator() -> void:
	# the controller ruling verbatim: highest wins, tie → predator — ANY tie
	# for the top score, not only ties the predator itself takes part in
	eq(ShapeScript.shape_of(_g({"jaw": 2, "spikes": 1, "size": 0.6,
			"eyes": 1, "arms": 2, "brain": 0})), "predator",
			"predator 3 == minder 3 (wall 0) → predator")
	eq(ShapeScript.shape_of(_g({"eyes": 3, "arms": 0, "brain": 0,
			"jaw": 0, "spikes": 0, "size": 0.6, "coat": "plates", "horns": 0})),
			"predator", "minder 3 == wall 3 (predator 0) → predator")
	eq(ShapeScript.shape_of(_g({"jaw": 1, "spikes": 2, "size": 0.6,
			"coat": "fur", "horns": 2, "eyes": 1})), "predator",
			"predator 3 == wall 3 (minder 1) → predator")


func test_size_rank_pins() -> void:
	# the size gene normalized against GENE_BOUNDS["size"] {0.6..2.2} into 0..2
	approx(ShapeScript.size_rank(_g({"size": 0.6})), 0.0, "bound min → rank 0", 1e-9)
	approx(ShapeScript.size_rank(_g({"size": 2.2})), 2.0, "bound max → rank 2", 1e-9)
	approx(ShapeScript.size_rank(_g({"size": 1.0})), 0.5, "default size 1 → rank 0.5", 1e-9)
	approx(ShapeScript.size_rank(_g({"size": 3.0})), 2.0, "above the bound clamps to 2", 1e-9)
	approx(ShapeScript.size_rank(_g({"size": 0.1})), 0.0, "below the bound clamps to 0", 1e-9)


func test_coat_score_pins() -> void:
	# the coat gene is categorical — its score IS the COATS defense order
	eq(ShapeScript.coat_score(_g({"coat": "skin"})), 0, "skin → 0")
	eq(ShapeScript.coat_score(_g({"coat": "fur"})), 1, "fur → 1")
	eq(ShapeScript.coat_score(_g({"coat": "scales"})), 2, "scales → 2")
	eq(ShapeScript.coat_score(_g({"coat": "plates"})), 3, "plates → 3")
	var bad: Dictionary = _g()
	bad["coat"] = "diamond"
	eq(ShapeScript.coat_score(bad), 0, "garbage coat → 0")


func test_trait_names() -> void:
	eq(ShapeScript.trait_name("predator"), "Predator-line", "predator display name (raw EN key)")
	eq(ShapeScript.trait_name("minder"), "Minder-line", "minder display name")
	eq(ShapeScript.trait_name("wall"), "Wall-line", "wall display name")
	eq(ShapeScript.trait_name(""), "", "no shape yet → empty name")
	eq(ShapeScript.trait_name("big"), "", "unknown shape → empty name")


# ---- 2. the switch seam ---------------------------------------------------------

## Seeded boot → menu, fake sim stages registered; the loop's kill-switch
## makes switch_stage the ONLY thing that runs (the test_karma_profile
## pattern — the seam tests need registered ids, nothing else).
class FakeStage extends "res://src/game/stage.gd":
	func _init(g: Variant, id_v: String) -> void:
		super(g, id_v)


func _flow_game(seed_v: int) -> Variant:
	var ctx: Variant = Ctx.new(seed_v)
	var g: Variant = GameScript.new(ctx)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(g)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
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


func _drop(g: Variant) -> void:
	if g != null:
		g.free()


func test_seam_recomputes_run_shape_latest_wins() -> void:
	var g: Variant = _flow_game(SEED)
	var ctx: Variant = g.context
	ok(String(ctx.run_shape).is_empty(), "boot: no shape before any exit")
	# a wall-line genome: the next exit snaps it
	ctx.genome["coat"] = "plates"
	ctx.genome["horns"] = 3
	g.switch_stage("cell")
	eq(String(ctx.run_shape), "wall", "the exit seam recomputed the shape from the genome")
	# the genome changes mid-stage — the NEXT exit overwrites (LATEST-only)
	ctx.genome["coat"] = "skin"
	ctx.genome["horns"] = 0
	ctx.genome["eyes"] = 4
	ctx.genome["arms"] = 3
	ctx.genome["brain"] = 2
	g.switch_stage("creature")
	eq(String(ctx.run_shape), "minder", "the latest exit wins (stale snapshot overwritten)")
	g.switch_stage("tribe")
	eq(String(ctx.run_shape), "minder", "unchanged genome → the same shape re-snaps")
	_drop(g)
	_wipe_cfg()


# ---- 3. the civ consumers -------------------------------------------------------

func test_rival_def_shape_modifier() -> void:
	# the ONE defense source bends by shape: predator −1, wall +1, else 0
	eq(_mk_sim(0xA1, "predator")["sim"].rival_def_for(true), 5.0,
			"predator-line: rival def 6−1 (normal)")
	eq(_mk_sim(0xA1, "wall")["sim"].rival_def_for(true), 7.0,
			"wall-line: rival def 6+1 (normal)")
	eq(_mk_sim(0xA1, "minder")["sim"].rival_def_for(true), 6.0,
			"minder-line: rival def unchanged")
	eq(_mk_sim(0xA1, "")["sim"].rival_def_for(true), 6.0,
			"no shape yet (fresh boot) → neutral")
	eq(_mk_sim(0xA1, "predator")["sim"].rival_def_for(false), 2.0,
			"the non-rival branch carries the modifier too (single source)")
	var m: Dictionary = _mk_sim(0xA1, "predator")
	m["ctx"].difficulty = "chaos"
	eq(m["sim"].rival_def_for(true), 8.0, "chaos +3 stacks with the shape −1")


func test_start_output_conduct_bonus() -> void:
	# the conduct half: start output 10±2 by the karma profile's mean
	var m: Dictionary = _mk_sim(0xB2, "minder", [0.2, 0.2, 0.2, 0.2])
	m["sim"].on_enter()
	approx(float(m["sim"].output), 12.0, "conduct +0.2 > +0.15 → start output 12", 1e-9)
	var m2: Dictionary = _mk_sim(0xB2, "minder", [-0.2, -0.2, -0.2, -0.2])
	m2["sim"].on_enter()
	approx(float(m2["sim"].output), 8.0, "conduct −0.2 < −0.15 → start output 8", 1e-9)
	var m3: Dictionary = _mk_sim(0xB2, "minder", [0.15, 0.15, 0.15, 0.15])
	m3["sim"].on_enter()
	approx(float(m3["sim"].output), 10.0, "exactly +0.15 is NOT above the gate (strict >)", 1e-9)
	var m4: Dictionary = _mk_sim(0xB2, "minder", [])
	m4["ctx"].karma = 0.3
	m4["sim"].on_enter()
	approx(float(m4["sim"].output), 12.0,
			"empty profile reads the live karma (the Task 10 grace)", 1e-9)
	# the sim is a boot-time singleton — every entry recomputes, so a NEW LIFE
	# (the profile wiped) heals the bonus back to the 10 start
	m4["ctx"].karma = 0.0
	m4["sim"].on_enter()
	approx(float(m4["sim"].output), 10.0, "re-entry recomputes the start output", 1e-9)


func test_minder_charm_trade_karma_extra() -> void:
	# the minder-line's diplomatic bent: the charm/trade resolve pays +0.01
	# karma extra (0.015 → 0.025 charm, 0.01 → 0.02 trade)
	var m: Dictionary = _mk_sim(0xC3, "minder")
	var sim: Variant = m["sim"]
	sim.culture = 5.0
	sim.cities[2]["influence"] = 80.0
	sim.cities[2]["x"] = 5.0
	sim.cities[2]["y"] = 125.0
	sim.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit2"]}))
	approx(float(m["ctx"].karma), 0.025, "minder charm karma 0.015 + 0.01", 1e-9)
	var m2: Dictionary = _mk_sim(0xC3, "predator")
	var sim2: Variant = m2["sim"]
	sim2.culture = 5.0
	sim2.cities[2]["influence"] = 80.0
	sim2.cities[2]["x"] = 5.0
	sim2.cities[2]["y"] = 125.0
	sim2.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit2"]}))
	approx(float(m2["ctx"].karma), 0.015, "predator charm karma unchanged (TS parity)", 1e-9)
	var m3: Dictionary = _mk_sim(0xC3, "minder")
	var sim3: Variant = m3["sim"]
	sim3.econ = 5.0
	sim3.cities[3]["x"] = 5.0
	sim3.cities[3]["y"] = 115.0
	sim3.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit3"]}))
	approx(float(m3["ctx"].karma), 0.02, "minder trade karma 0.01 + 0.01", 1e-9)
	var m4: Dictionary = _mk_sim(0xC3, "")
	var sim4: Variant = m4["sim"]
	sim4.econ = 5.0
	sim4.cities[3]["x"] = 5.0
	sim4.cities[3]["y"] = 115.0
	sim4.update(1.0 / 60.0, _inp({"keys_pressed": ["Digit3"]}))
	approx(float(m4["ctx"].karma), 0.01, "no shape → the TS +0.01 unchanged", 1e-9)


func test_wall_city_hp_regen() -> void:
	# the wall-line's fortress doctrine: the existing your-city regen site
	# pays +0.3/s extra (one line, the constant lives at the site). The
	# military rival's shell rides the SAME tick_second (aggression·0.4) —
	# zeroed here so the pin reads the regen term alone.
	var m: Dictionary = _mk_sim(0xD4, "wall")
	var sim: Variant = m["sim"]
	for r in sim.rivals:
		r["aggression"] = 0.0
	sim.cities[0]["hp"] = 50.0
	sim.tick_second()
	approx(float(sim.cities[0]["hp"]), 50.8, "wall-line regen +0.5 + 0.3 per second", 1e-9)
	var m2: Dictionary = _mk_sim(0xD4, "predator")
	var sim2: Variant = m2["sim"]
	for r2 in sim2.rivals:
		r2["aggression"] = 0.0
	sim2.cities[0]["hp"] = 50.0
	sim2.tick_second()
	approx(float(sim2.cities[0]["hp"]), 50.5, "other shapes keep the TS +0.5", 1e-9)


# ---- 4. the card line -----------------------------------------------------------

func test_card_heredity_line_pins() -> void:
	# the ONE line per destination: civ-bound names the national trait,
	# space-bound the fleet legacy (real perks deferred); everything else
	# draws nothing. The shape reads the LIVE genome at draw (the R10
	# convention — never a stale snapshot; the exit seam recomputes the same
	# genome by the time the effects consume the snapshot).
	var i18n: Variant = _i18n("en")
	var c: Variant = Ctx.new(0xE5)
	eq(GameScript.card_heredity_draw_line("civ", c, i18n), "National trait: Predator-line",
			"civ card: the default body already names its trait (the genome is the truth)")
	c.genome["coat"] = "plates"
	c.genome["horns"] = 3
	eq(GameScript.card_heredity_draw_line("civ", c, i18n), "National trait: Wall-line",
			"civ card: the wall-line name")
	c.genome["coat"] = "skin"
	c.genome["horns"] = 0
	c.genome["eyes"] = 4
	c.genome["arms"] = 3
	c.genome["brain"] = 2
	eq(GameScript.card_heredity_draw_line("space", c, i18n), "Fleet legacy: Minder-line",
			"space card: the fleet legacy line (real perks deferred)")
	c.genome["coat"] = "fur"
	c.genome["eyes"] = 1
	c.genome["arms"] = 0
	c.genome["brain"] = 0
	eq(GameScript.card_heredity_draw_line("space", c, i18n), "Fleet legacy: Predator-line",
			"space card: a fresh predator genome names itself")
	for id in ["cell", "creature", "tribe", "menu", ""]:
		eq(GameScript.card_heredity_draw_line(String(id), c, i18n), "",
				"the '%s' destination draws nothing" % String(id))
	_wipe_cfg()


func test_card_heredity_line_vi() -> void:
	var i18n: Variant = _i18n("vi")
	var c: Variant = Ctx.new(0xE6)
	eq(GameScript.card_heredity_draw_line("civ", c, i18n), "Đặc tính quốc gia: Dòng săn mồi",
			"VI: the template AND the trait name translate at draw")
	c.genome["coat"] = "plates"
	c.genome["horns"] = 3
	eq(GameScript.card_heredity_draw_line("civ", c, i18n), "Đặc tính quốc gia: Dòng phòng tuyến",
			"VI: the wall-line name")
	c.genome["coat"] = "skin"
	c.genome["horns"] = 0
	c.genome["eyes"] = 4
	c.genome["arms"] = 3
	c.genome["brain"] = 2
	eq(GameScript.card_heredity_draw_line("space", c, i18n), "Di sản hạm đội: Dòng chăm sóc",
			"VI: the fleet legacy line")
	_wipe_cfg()
	TranslationServer.set_locale("en")


func test_heredity_vi_rows_ship() -> void:
	var i18n: Variant = _i18n("en")
	for key in ["National trait: %s", "Fleet legacy: %s",
			"Predator-line", "Minder-line", "Wall-line"]:
		ok(i18n.vi_has(String(key)), "vi.csv ships the '%s' row" % String(key))
	_wipe_cfg()


# ---- 5. the save wire -----------------------------------------------------------

func _path(n: int) -> String:
	return "user://saves/slot%d.json" % n


func _wipe(n: int) -> void:
	if FileAccess.file_exists(_path(n)):
		DirAccess.remove_absolute(_path(n))


func _write_json(n: int, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(_path(n), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))


func test_run_shape_wire_round_trip() -> void:
	_wipe(SLOT_RT)
	var ctx: Variant = Ctx.new(0xF6)
	ctx.stage = "creature"  # a menu stage never persists (the save() guard)
	ctx.genome["coat"] = "plates"
	ctx.genome["horns"] = 3
	ctx.run_shape = "wall"
	ok(ctx.to_save_data().has("runShape"), "the wire carries runShape (camelCase)")
	ok(ctx.save(SLOT_RT), "save with a run shape on the wire")
	var ctx2: Variant = Ctx.new(0xF6)
	ok(ctx2.load(SLOT_RT), "load")
	eq(String(ctx2.run_shape), "wall", "runShape round-trips")
	_wipe(SLOT_RT)


func test_run_shape_old_save_computes_from_genome() -> void:
	# the brief's NO ruling: a missing field must NOT read a hardcoded
	# "predator" — the genome is always present, so the shape computes
	_wipe(SLOT_OLD)
	var ctx: Variant = Ctx.new(0xF7)
	ctx.stage = "creature"
	ctx.genome["eyes"] = 4
	ctx.genome["arms"] = 3
	ctx.genome["brain"] = 2
	ctx.run_shape = "predator"  # a stale snapshot — NOT what this save carries
	var data: Dictionary = ctx.to_save_data()
	data.erase("runShape")  # the pre-R12 field absence
	_write_json(SLOT_OLD, data)
	var ctx2: Variant = Ctx.new(0xF7)
	ok(ctx2.load(SLOT_OLD), "old save loads")
	eq(String(ctx2.run_shape), "minder",
			"missing runShape → COMPUTED from the genome on load")
	_wipe(SLOT_OLD)


func test_run_shape_corrupt_value_computes() -> void:
	for bad: Variant in ["big", 123, true]:
		_wipe(SLOT_CORRUPT)
		var ctx: Variant = Ctx.new(0xF8)
		ctx.stage = "creature"
		ctx.genome["coat"] = "plates"
		ctx.genome["horns"] = 2
		var data: Dictionary = ctx.to_save_data()
		data["runShape"] = bad
		_write_json(SLOT_CORRUPT, data)
		var ctx2: Variant = Ctx.new(0xF8)
		ok(ctx2.load(SLOT_CORRUPT), "corrupt runShape %s loads" % str(bad))
		eq(String(ctx2.run_shape), "wall",
				"corrupt runShape (%s) → computed from the genome" % str(bad))
	_wipe(SLOT_CORRUPT)


func test_conduct_avg_is_the_karma_mean() -> void:
	# the conduct half of the ledger IS the Task 10 profile mean — derived,
	# never a second persisted field
	var ctx: Variant = Ctx.new(0xF9)
	ctx.karma_by_stage = [0.5, -0.1, 0.2, 0.2]
	approx(float(ctx.conduct_avg()), 0.2, "conduct_avg = the profile mean", 1e-9)
	ctx.karma_by_stage = []
	ctx.karma = 0.3
	approx(float(ctx.conduct_avg()), 0.3,
			"empty profile reads the live karma (the Task 10 grace)", 1e-9)


# ---- 6. the balance probe -------------------------------------------------------

## One headless armada-only civ drive to unification: the honest-launch gate,
## the 5s route cooldown, regen and the resolve math all run for real. Chaos
## silenced (gap 1e9) and the rival personalities defused to military (the
## test_probe_civ rig) so two same-seed runs differ ONLY by the ledger's
## effects. Policy: Digit1 whenever the lane can honestly launch, else raise
## mil — identical for both runs. Returns sim.time at victory, −1 on stall.
func _probe_time(seed_v: int, shape: String, profile: Array) -> float:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.difficulty = "normal"
	ctx.run_shape = shape
	ctx.karma_by_stage = profile
	var sim: Variant = CivSim.new(ctx, ctx.rng.branch(), {})  # silent hooks
	sim.on_enter()
	sim.chaos.gap = 1.0e9
	for r in sim.rivals:
		r["personality"] = "military"
	var dt := 1.0 / 60.0
	var frames := 0
	while not bool(sim.victoryFired) and frames < 60 * 900:
		var keys: Array = []
		if float(sim.launchCds["attack"]) <= 0.0 and float(sim.mil) >= 5.0:
			keys = ["Digit1"]
		elif float(sim.mil) < 10.0:
			keys = ["KeyQ"]
		sim.update(dt, _inp({"keys_pressed": keys}))
		frames += 1
	if not bool(sim.victoryFired):
		return -1.0
	return float(sim.time)


func test_balance_probe_predator_high_conduct_not_below_60pct() -> void:
	var base: float = _probe_time(0x9E5D, "minder", [0.0, 0.0, 0.0, 0.0])
	var fast: float = _probe_time(0x9E5D, "predator", [0.2, 0.2, 0.2, 0.2])
	ok(base > 0.0, "the baseline armada-only run completed (t=%s)" % str(base))
	ok(fast > 0.0, "the predator+conduct run completed (t=%s)" % str(fast))
	if base > 0.0 and fast > 0.0:
		# the ledger line: the probe's numbers print for the execution ledger
		print("R12 balance probe: baseline %.1fs, predator+conduct %.1fs, ratio %.3f (gate ≥ 0.600)"
				% [base, fast, fast / base])
		ok(fast >= 0.6 * base,
				"predator+high-conduct completion stays ≥ 60%% of baseline (%.1fs vs %.1fs)"
						% [fast, base])
