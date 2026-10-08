# Task 13 (R10) — genome showcase on transition cards (text-first): the 2.2s
# card gains 3 stat lines (size/legs/brain) + 1 karma line so the player sees
# what they BUILT before the new stage begins. Four headless-safe layers (the
# objective-chip pattern — the draw itself renders under the xvfb harness):
#   1. card_showcase_lines(ctx): the static pure builder — exactly 3 genome
#      lines read with the stats module's .get conventions (the card numbers
#      are the editor's numbers) + 1 karma line, signed 2-decimals,
#   2. the gate ruling — gameplay-bound targets only (cell/creature/tribe/
#      civ/space == context.LOAD_STAGES); menu-bound cards draw nothing new,
#   3. the draw composition — the label word translates AT DRAW (tr_key), the
#      value rides OUTSIDE tr (the R2/QC-r3 translate-the-prose precedent);
#      EN degrades to the raw line, VI swaps the label word only,
#   4. vi.csv ships the four bare label rows (size/legs/brain/karma).
# The karma sign is the death-debrief display convention (Task 12): explicit
# + for non-negative, the U+2212 minus GLYPH for negatives (glyph verified
# present in the fallback font by that task's headless probe).
extends "res://tests/test_base.gd"

const GameScript := preload("res://src/game/game.gd")
const Ctx := preload("res://src/game/context.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const I18nScript := preload("res://src/core/i18n.gd")

const SEED := 0x0A
const SCRATCH_CFG := "user://test_card_showcase_settings.cfg"

# U+2212 MINUS SIGN — the display glyph for negative karma (NOT the ASCII
# hyphen %.2f would emit; see the header note).
const MINUS_GLYPH := "−"


func _wipe_cfg() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(SCRATCH_CFG)


# A pinned context: fresh context (seeded), then the genome/karma the test
# means to read — the builder must touch ONLY these two fields.
func _ctx(genome_overrides: Dictionary, karma_v: float) -> Variant:
	var c: Variant = Ctx.new(SEED)
	c.genome.merge(genome_overrides, true)
	c.karma = karma_v
	return c


# ---- 1. card_showcase_lines: the pure builder ----------------------------------

func test_showcase_lines_pinned_genome_exact_strings() -> void:
	var c: Variant = _ctx({"size": 1.5, "legs": 4, "brain": 3}, 0.42)
	var want: Array[String] = ["size 1.5", "legs 4", "brain 3", "karma +0.42"]
	eq(GameScript.card_showcase_lines(c), want,
			"pinned genome: exactly the 3 stat lines + the signed karma line, in order")


func test_showcase_lines_default_genome_and_zero_karma() -> void:
	var c: Variant = _ctx({}, 0.0)
	var want: Array[String] = ["size 1", "legs 0", "brain 0", "karma +0.00"]
	eq(GameScript.card_showcase_lines(c), want,
			"default genome: size via String.num like the editor's row (trailing "
			+ "zeros strip — the editor shows 1×), levels as ints, +0.00 karma")


func test_showcase_karma_sign_and_rounding() -> void:
	# the sign convention is the pinned surface: explicit + for non-negative,
	# the U+2212 glyph for negatives, always 2 decimals
	var cases := [[0.42, "karma +0.42"], [-0.15, "karma %s0.15" % MINUS_GLYPH],
			[0.0, "karma +0.00"], [-1.0, "karma %s1.00" % MINUS_GLYPH],
			[1.0, "karma +1.00"], [0.999, "karma +1.00"], [0.154, "karma +0.15"]]
	for case_v in cases:
		var c: Variant = _ctx({}, float(case_v[0]))
		eq(GameScript.card_showcase_lines(c)[3], String(case_v[1]),
				"karma %.3f formats signed 2-decimals" % float(case_v[0]))


func test_showcase_gene_reads_match_stats_module_conventions() -> void:
	# stats.gd reads float(g.get("size", 1)) / float(g.get("legs", 0)) /
	# float(g.get("brain", 0)) — a missing gene falls back the same way, and
	# fractional part LEVELS display truncating like the editor's pip count
	var c: Variant = _ctx({}, -0.5)
	c.genome.erase("size")  # corrupt-save shape: the gene itself missing
	c.genome["legs"] = 2.5
	c.genome["brain"] = 1
	var lines: Array[String] = GameScript.card_showcase_lines(c)
	eq(lines[0], "size 1", "missing size gene falls back to the stats default 1")
	eq(lines[1], "legs 2", "fractional legs truncates like the editor's level read")
	eq(lines[2], "brain 1", "integral brain reads as its level")
	eq(lines[3], "karma %s0.50" % MINUS_GLYPH, "negative karma carries the glyph")


func test_showcase_lines_shape_and_purity() -> void:
	var c: Variant = _ctx({"size": 2.2, "legs": 6, "brain": 5}, -0.15)
	var lines: Array[String] = GameScript.card_showcase_lines(c)
	eq(lines.size(), 4, "exactly 4 lines (brief: 3 stat + 1 karma)")
	# the draw's split contract: "label value" — one space separates a bare EN
	# label key from the value, so the label word can translate at draw
	var labels := []
	for line in lines:
		var parts := String(line).split(" ", true, 1)
		eq(parts.size(), 2, "line '%s' splits into label + value" % String(line))
		labels.append(String(parts[0]))
	eq(labels, ["size", "legs", "brain", "karma"], "labels are the bare EN keys, in order")
	# pure: the same context reads back identical
	eq(GameScript.card_showcase_lines(c), lines, "pure: repeated call identical")


# ---- 2. the gate ruling ----------------------------------------------------------

func test_showcase_gate_gameplay_targets_only() -> void:
	# the controller ruling verbatim: lines when the transition targets a
	# GAMEPLAY stage; menu-bound transitions (quit-to-title's PRIMORDIA card)
	# draw nothing new. cell/creature/tribe/civ/space == context.LOAD_STAGES.
	for id in ["cell", "creature", "tribe", "civ", "space"]:
		eq(GameScript.card_has_showcase(String(id)), true, "gate opens for '%s'" % String(id))
	eq(GameScript.card_has_showcase("menu"), false, "menu-bound card draws nothing new")
	eq(GameScript.card_has_showcase(""), false, "empty target gates shut")
	eq(GameScript.card_has_showcase("garbage"), false, "unknown target gates shut")


# ---- 3. the draw composition -----------------------------------------------------

func test_showcase_draw_lines_en_degrades_to_the_raw_lines() -> void:
	_wipe_cfg()
	var i18n: Variant = I18nScript.new(SCRATCH_CFG)
	i18n.set_lang("en")
	var c: Variant = _ctx({"size": 1.5, "legs": 4, "brain": 3}, 0.42)
	eq(GameScript.card_showcase_draw_lines(c, i18n), GameScript.card_showcase_lines(c),
			"EN: label passthrough — the draw strings are the raw lines verbatim")
	_wipe_cfg()


func test_showcase_draw_lines_vi_label_translates_value_rides_outside() -> void:
	_wipe_cfg()
	var i18n: Variant = I18nScript.new(SCRATCH_CFG)
	i18n.set_lang("vi")
	var c: Variant = _ctx({"size": 1.5, "legs": 4, "brain": 3}, 0.42)
	var want: Array[String] = ["kích cỡ 1.5", "chân 4", "não 3", "karma +0.42"]
	eq(GameScript.card_showcase_draw_lines(c, i18n), want,
			"VI: the label word translates at draw, the value (+0.42) stays raw")
	# the value must NOT ride through tr: a translated label + untranslated
	# value is the whole ruling — pin the label side actually maps
	ok(i18n.vi_has("size") and i18n.vi_has("legs") and i18n.vi_has("brain"),
			"vi.csv ships the stat label rows")
	_wipe_cfg()
	TranslationServer.set_locale("en")


# ---- 4. vi.csv membership ---------------------------------------------------------

func test_showcase_label_rows_ship_in_vi_csv() -> void:
	_wipe_cfg()
	var i18n: Variant = I18nScript.new(SCRATCH_CFG)
	for key in ["size", "legs", "brain", "karma"]:
		ok(i18n.vi_has(String(key)), "vi.csv ships the '%s' label row" % String(key))
	_wipe_cfg()
