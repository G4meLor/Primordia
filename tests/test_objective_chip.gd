# Tests for the R2 objective chip (experience-redesign task 3): the live
# cur/max counter behind the centered objective line. Four layers, all
# headless-safe (no scene, no canvas — the draw integration itself renders
# under the xvfb scene harness, the tests/scenes/test_editor_click.gd
# precedent; native draw-method overrides are parse-errors under this
# project's warning config and the `-s` runner is strictly synchronous):
#   1. the pure display join — the brief-pinned "T · 34/100" + the
#      cur<0 / max<=0 no-counter edges,
#   2. the hud field contract — show_objective_text/cur/max and the setter
#      reset: ANY plain (re)assignment clears the pair, so the cell/creature
#      direct sets and the 1-arg objective hook can never leak a stale chip,
#   3. the render composition via objective_render_string() — the exact
#      string the draw block passes to outlined_text (translate the prose,
#      THEN append the pair OUTSIDE tr_key — the arc_states/arc_next_hint
#      testable-extract seam task 2 used),
#   4. the sim wiring — tribe (totem gate, food first, matching try_totem's
#      order), space (worlds seeded toward the thriving gate, silent once the
#      finale's dynamic swaps own the line — the red-team rule), civ (no
#      chip — the ruling: no natural cur/max state tracks unification).
extends "res://tests/test_base.gd"

const HudUi := preload("res://src/ui/hud.gd")
const I18nScript := preload("res://src/core/i18n.gd")
const ContextScript := preload("res://src/game/context.gd")
const InputScript := preload("res://src/core/input.gd")
const TribeSim := preload("res://src/game/tribe/tribe_sim.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")
const SpaceSim := preload("res://src/game/space/space_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0x0B7EC4
const SCRATCH := "user://test_objective_chip.cfg"

const CELL_OBJECTIVE := "EAT. GROW. EVOLVE. — press E to edit your genome"
const TRIBE_OBJECTIVE := "GATHER · BUILD · SURVIVE — raise the Great Totem"
const CIV_OBJECTIVE := "UNIFY THE PLANET — slider keys Q/W/E · launch armadas with 1/2/3"
const SPACE_OBJECTIVE := "SEED 3 WORLDS, GROW EACH TO POP 20 — awaken the Chaos Core · R abduct · F evolve"


# Duck-typed game for the hud tests (the test_hud.gd MockGame shape — the
# render-string read needs context + i18n only).
class MockGame extends RefCounted:
	var context: Variant
	var input: Variant
	var i18n: Variant

	func _init() -> void:
		context = ContextScript.new(99)
		input = InputScript.new()
		i18n = I18nScript.new(SCRATCH)
		i18n.set_lang("en")


func _wipe() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_objective_chip.cfg")
		dir.remove("test_objective_chip.cfg.tmp")


func _restore_locale() -> void:
	TranslationServer.set_locale("en")


# Input snapshot with the M2 field shape (the sims read subsets via .get).
func _inp() -> Dictionary:
	return {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}


# ---- 1. objective_display: the pure join --------------------------------------

func test_objective_display_pinned() -> void:
	eq(HudUi.objective_display("T", 34, 100), "T · 34/100", "counter join (brief verbatim)")
	eq(HudUi.objective_display("T", -1, 0), "T", "no counter (brief verbatim)")


func test_objective_display_no_counter_edges() -> void:
	eq(HudUi.objective_display("T", -1, 100), "T", "cur<0 → plain")
	eq(HudUi.objective_display("T", 0, 0), "T", "max 0 → plain")
	eq(HudUi.objective_display("T", 12, -1), "T", "max<0 → plain")
	eq(HudUi.objective_display("T", 0, 100), "T · 0/100", "cur 0 still renders")
	eq(HudUi.objective_display("done", 100, 100), "done · 100/100", "at-goal renders")


# ---- 2. the hud field contract -------------------------------------------------

func test_chip_fields_default_plain() -> void:
	_wipe()
	var hud: Variant = HudUi.new(MockGame.new())
	eq(hud.show_objective, null, "no objective by default")
	eq(String(hud.show_objective_text), "", "text mirror empty")
	eq(int(hud.show_objective_cur), -1, "cur<0 → no counter")
	eq(int(hud.show_objective_max), 0, "max 0 → no counter")
	_wipe()
	_restore_locale()


func test_assignment_mirrors_and_resets_the_pair() -> void:
	_wipe()
	var hud: Variant = HudUi.new(MockGame.new())
	hud.show_objective = TRIBE_OBJECTIVE
	eq(String(hud.show_objective_text), TRIBE_OBJECTIVE, "text mirrors the assignment")
	# arm the live pair (what the hud_objective_counter hook path writes)
	hud.show_objective_cur = 34
	hud.show_objective_max = 100
	# ANY plain (re)assignment re-arms a PLAIN line — the cell/creature direct
	# sets (cell_stage/creature_stage write show_objective with no pair) and
	# the 1-arg hook path can never leak a previous stage's chip
	hud.show_objective = CELL_OBJECTIVE
	eq(int(hud.show_objective_cur), -1, "reassignment clears cur")
	eq(int(hud.show_objective_max), 0, "reassignment clears max")
	eq(String(hud.show_objective_text), CELL_OBJECTIVE, "text mirrors the new line")
	hud.show_objective = null
	eq(String(hud.show_objective_text), "", "null clears the mirror")
	eq(int(hud.show_objective_cur), -1, "null clears cur")
	eq(int(hud.show_objective_max), 0, "null clears max")
	_wipe()
	_restore_locale()


# ---- 3. the render string (what draw passes to outlined_text) -------------------

func test_render_string_en_plain_and_with_counter() -> void:
	_wipe()
	var g: Variant = MockGame.new()
	var hud: Variant = HudUi.new(g)
	hud.show_objective = TRIBE_OBJECTIVE
	eq(hud.objective_render_string(), TRIBE_OBJECTIVE,
			"EN passthrough — the plain line exactly as today")
	hud.show_objective_cur = 34
	hud.show_objective_max = 100
	eq(hud.objective_render_string(), "%s · 34/100" % TRIBE_OBJECTIVE,
			"the chip appends to the translated line")
	_wipe()
	_restore_locale()


func test_render_string_vi_numbers_outside_tr() -> void:
	_wipe()
	var g: Variant = MockGame.new()
	var hud: Variant = HudUi.new(g)
	g.i18n.set_lang("vi")
	var key := CELL_OBJECTIVE
	ok(g.i18n.vi_has(key), "vi.csv row exists for the objective key")
	ok(g.i18n.tr_key(key) != key, "VI actually translates (not a vacuous EN pin)")
	hud.show_objective = key
	hud.show_objective_cur = 34
	hud.show_objective_max = 100
	eq(hud.objective_render_string(), "%s · 34/100" % g.i18n.tr_key(key),
			"VI: prose translates, the pair rides OUTSIDE tr_key")
	hud.show_objective_cur = -1
	eq(hud.objective_render_string(), g.i18n.tr_key(key),
			"VI: no counter → the plain translated line")
	_wipe()
	_restore_locale()


# ---- 4a. tribe: the totem stockpile chip (food first, matching try_totem) -------

func _mk_tribe() -> Dictionary:
	var ctx: Variant = ContextScript.new(SEED)
	var rec: Dictionary = {"objectives": [], "chips": []}
	var hooks: Dictionary = {
		"hud_show_objective": func(text): rec["objectives"].append(text),
		"hud_objective_counter": func(cur, mx): rec["chips"].append([int(cur), int(mx)]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = TribeSim.new(ctx, rng, hooks)
	return {"sim": sim, "rec": rec}


func test_tribe_chip_counts_totem_stockpile_food_first() -> void:
	var m: Dictionary = _mk_tribe()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.on_enter()
	sim.update(DT, _inp())
	# fresh village: 60 food / 30 wood — food-limited (try_totem's first arm)
	eq(rec["chips"].back(), [60, 100], "food toward 100 while food-limited")
	# both constraints unmet → food first (the gate's own order)
	sim.debug_grant(50.0, 10.0)
	sim.update(DT, _inp())
	eq(rec["chips"].back(), [50, 100], "both unmet → food first")
	# food gate satisfied → wood toward 80
	sim.debug_grant(100.0, 10.0)
	sim.update(DT, _inp())
	eq(rec["chips"].back(), [10, 80], "food met → wood toward 80")
	# the whole gate satisfied → no chip (the plain line, totem raisable)
	sim.debug_grant(100.0, 80.0)
	sim.update(DT, _inp())
	eq(rec["chips"].back(), [-1, 0], "gate satisfied → no counter")
	# the totem already rising → the stockpile gate is moot, no chip
	sim.debug_grant(20.0, 5.0)
	sim.totem["active"] = true
	sim.update(DT, _inp())
	eq(rec["chips"].back(), [-1, 0], "totem active → no stockpile chip")
	eq(String(rec["objectives"].back()), TRIBE_OBJECTIVE, "objective text unchanged")


# ---- 4b. space: worlds seeded toward the thriving gate ---------------------------

func _mk_space() -> Dictionary:
	var ctx: Variant = ContextScript.new(SEED)
	var rec: Dictionary = {"objectives": [], "chips": [], "banners": []}
	var hooks: Dictionary = {
		"hud_show_objective": func(text): rec["objectives"].append(text),
		"hud_objective_counter": func(cur, mx): rec["chips"].append([int(cur), int(mx)]),
		"hud_banner": func(data): rec["banners"].append(data),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = SpaceSim.new(ctx, rng, hooks)
	return {"sim": sim, "rec": rec}


func test_space_chip_counts_worlds_seeded() -> void:
	var m: Dictionary = _mk_space()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.on_enter()
	sim.update(DT, _inp())
	# the 6-planet system, no colonies — the seeding objective owns the line
	eq(rec["chips"].back(), [0, 3], "0 worlds seeded → 0/3")
	# one colony past the pop-20 thriving gate (TS:553)
	sim.planets[0]["colony"] = {"pop": 20.0, "generations": 0.0}
	sim.update(DT, _inp())
	eq(rec["chips"].back(), [1, 3], "1 thriving world → 1/3")
	# below the gate does not count
	sim.planets[1]["colony"] = {"pop": 19.9, "generations": 0.0}
	sim.update(DT, _inp())
	eq(rec["chips"].back(), [1, 3], "pop<20 does not count")
	eq(String(rec["objectives"].back()), SPACE_OBJECTIVE, "static line unchanged")


func test_space_chip_goes_silent_when_the_finale_owns_the_line() -> void:
	var m: Dictionary = _mk_space()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.on_enter()
	sim.update(DT, _inp())
	eq(rec["chips"].size(), 1, "one chip fire so far")
	# complete the gate: 3 thriving worlds spawn the finale on this tick
	sim.planets[0]["colony"] = {"pop": 20.0, "generations": 0.0}
	sim.planets[1]["colony"] = {"pop": 21.0, "generations": 0.0}
	sim.planets[2]["colony"] = {"pop": 22.0, "generations": 0.0}
	sim.update(DT, _inp())
	eq(rec["banners"].size(), 1, "finale spawned (3 thriving)")
	ok(String(rec["objectives"].back()).begins_with("THE CHAOS CORE PULLS"),
			"the dynamic swap fired — the red-team condition holds")
	eq(rec["chips"].size(), 1, "no chip fire once the finale owns the line — the core-approach line renders plain")


# ---- 4c. civ: no chip (the ruling) ------------------------------------------------

func _mk_civ() -> Dictionary:
	var ctx: Variant = ContextScript.new(SEED)
	var rec: Dictionary = {"objectives": [], "chips": []}
	var hooks: Dictionary = {
		"hud_show_objective": func(text): rec["objectives"].append(text),
		"hud_objective_counter": func(cur, mx): rec["chips"].append([int(cur), int(mx)]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CivSim.new(ctx, rng, hooks)
	return {"sim": sim, "rec": rec}


func test_civ_never_fires_the_chip() -> void:
	# the ruling: no natural cur/max state tracks unification — the plain
	# line renders, documented at the fire site
	var m: Dictionary = _mk_civ()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.on_enter()
	sim.update(DT, _inp())
	eq(rec["chips"], [], "civ never fires the chip hook")
	eq(rec["objectives"], [CIV_OBJECTIVE], "objective text unchanged")
