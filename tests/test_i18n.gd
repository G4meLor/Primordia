# Tests for src/core/i18n.gd — the i18n layer port (Spore src/core/i18n.ts +
# the i18n describe block of tests/features.test.ts, including the I-q1
# structural audit). Path-based extends + preload-by-path per the -s runner
# rules; class_name globals don't resolve on a fresh clone.
# Order-independence: every test points the settings file at a scratch cfg
# (wiped at the start) and restores the process-global TranslationServer
# locale it changed — the suite shares one Godot process.
extends "res://tests/test_base.gd"

const I18n := preload("res://src/core/i18n.gd")

const SCRATCH := "user://test_i18n_settings.cfg"


func _wipe() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("test_i18n_settings.cfg")
		dir.remove("test_i18n_settings.cfg.tmp")


func _i18n() -> Variant:
	return I18n.new(SCRATCH)


func _restore_locale() -> void:
	TranslationServer.set_locale("en")


# ---- EN passthrough (features.test.ts: 'English passes strings through') ---

func test_en_passthrough() -> void:
	_wipe()
	var i: Variant = _i18n()
	i.set_lang("en")
	eq(i.tr_key("SAVE SLOT"), "SAVE SLOT", "EN passthrough keeps the key")
	eq(i.tr_key("totally unknown string"), "totally unknown string",
			"EN passthrough is unconditional")
	eq(i.get_lang(), "en", "get_lang reflects set_lang")
	eq(i.get_muted(), false, "muted defaults to false (TS muted = false)")
	_restore_locale()


# ---- VI known keys + unknown fallback (features.test.ts second test) -------

func test_vi_known_keys_and_unknown_fallback() -> void:
	_wipe()
	var i: Variant = _i18n()
	i.set_lang("vi")
	eq(i.tr_key("SAVE SLOT"), "Ô LƯU", "SAVE SLOT translates")
	eq(i.tr_key("✦  NEW LIFE"), "✦  SỐNG MỚI", "double-space + emoji key translates")
	eq(i.tr_key("totally unknown string"), "totally unknown string",
			"unknown keys fall back to themselves (EN key space)")
	# CSV round-trip: quoted fields (commas), emoji, em-dashes survive the file
	eq(i.tr_key("hunt, charm (F), bones, meteor marrow"), "săn, quyến rũ (F), xương, tủy sao băng",
			"comma key survives CSV quoting")
	eq(i.tr_key("This world has a temper — Cradle softens every blow, Lean Seasons starve in long cycles, the Wildcard streaks without mercy."),
			"Thế giới này có tính khí — Cradle dịu mọi đòn đánh, Lean Seasons đói theo chu kỳ dài, Wildcard cuồng nộ không thương.",
			"comma-heavy value survives CSV quoting")
	eq(i.tr_key("🛸 ABDUCT LIFE (R)"), "🛸 BẮT SINH VẬT (R)", "emoji key survives CSV")
	eq(i.tr_key("R̶e̶a̶l̶i̶t̶y̶ ̶b̶u̶f̶f̶e̶r̶i̶n̶g̶…"), "Đ̶a̶n̶g̶ ̶đ̶ệ̶m̶ ̶t̶h̶ự̶c̶ ̶t̶ạ̶i̶…̶",
			"combining-strikethrough key survives CSV")
	ok(i.vi_has("SAVE SLOT"), "vi_has true for a table key")
	ok(not i.vi_has("totally unknown string"), "vi_has false for unknown keys")
	i.set_lang("en")
	_restore_locale()


# ---- settings persistence (TS loadSettings/saveSettings semantics) ---------

func test_settings_round_trip() -> void:
	_wipe()
	var i: Variant = _i18n()
	i.set_lang("vi")
	eq(_i18n().get_lang(), "vi", "lang choice persists via the cfg")
	i.set_lang("en")
	eq(_i18n().get_lang(), "en", "lang choice persists back")
	i.set_muted(true)
	eq(_i18n().get_muted(), true, "muted persists")
	eq(i.save_settings(), true, "save_settings reports success")

	# invalid lang value → detect_lang() (TS: raw?.lang valid ? raw.lang : detectLang())
	_wipe()
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "lang", "fr")
	cfg.set_value("settings", "muted", true)
	eq(cfg.save(SCRATCH), OK, "scratch cfg fixture written")
	var f: Variant = _i18n()
	eq(f.get_lang(), f.detect_lang(), "invalid lang falls back to detect_lang()")
	eq(f.get_muted(), true, "muted=true survives an invalid lang")

	# missing file → defaults: muted false, lang = detect (TS loadSettings)
	_wipe()
	var g: Variant = _i18n()
	eq(g.get_muted(), false, "missing cfg -> muted false (raw?.muted === true)")
	eq(g.get_lang(), g.detect_lang(), "missing cfg -> lang = detect_lang()")
	ok(g.get_lang() == "en" or g.get_lang() == "vi", "detected lang is in the Lang union")
	eq(g.detect_lang(), "vi" if OS.get_locale_language() == "vi" else "en",
			"detect_lang mirrors OS.get_locale_language() == \"vi\"")
	_restore_locale()


# ---- I-q1 part 1: the flagged keys translate (features.test.ts:62-94) ------

func test_iq1_flagged_keys_translate() -> void:
	_wipe()
	var i: Variant = _i18n()
	i.set_lang("vi")
	var keys := [
		# 10 variant names
		"☣ TOXIN CLOUDS", "🌿 RUNAWAY BLOOM", "🏆 RIVAL GOLDEN AGE", "⛵ TRADE WINDS",
		"🐺 NIGHT PACK", "🗿 A TITAN WALKS", "🌌 MUTATION NEBULA", "🕊 PIRATE LULL",
		"🏴 BOLD SAILS", "🎊 RIVAL FESTIVAL",
		# 6 warns
		"Foreign banners gleam — their forges never cool…",
		"Sails crowd every horizon — markets hum…",
		"Something moves between the trees…",
		"The ground trembles in a slow rhythm…",
		"A rainbow wall of charged gas rolls in…",
		"Sails where no sails should be…",
		# 6 flat toasts
		"A pack moves as one — eyes close in from the dark!",
		"The ground trembles — a titan walks past.",
		"A rival golden age! Their forges and fleets swell.",
		"Trade winds! Every market on the planet hums.",
		"The nebula washes only dead rock.",
		"The pirates pull back — an uneasy quiet falls.",
		# the 2 nebula templates compose from prefix keys (no mid-sentence tr_key())
	]
	var missing := []
	for k in keys:
		if i.tr_key(k) == k:
			missing.append(k)
	eq(missing, [], "every flagged variant/warn/toast key translates in VI")
	eq(i.tr_key("The nebula passes over"), "Tinh vân quét qua", "nebula template prefix 1")
	eq(i.tr_key("The nebula seeds"), "Tinh vân gieo", "nebula template prefix 2")
	eq(i.tr_key("nothing takes hold."), "không gì đậu được.", "nebula template suffix 1")
	eq(i.tr_key("new species on"), "loài mới trên", "nebula template suffix 2")
	# key-count: the dictionary never shrinks below the audited wave
	ok(i.vi_key_count() >= 454, "vi_key_count() >= 454 (got %d)" % i.vi_key_count())
	i.set_lang("en")
	_restore_locale()


# ---- I-q1 part 2: the structural sweep (features.test.ts:96-122) -----------
# Scanners are ports of the TS audit regexes, with the receiver shapes native
# code actually uses: `hud.toast(` (a typed HUD object, TS shape) and
# `hud["toast"].call(` (the M2 stub-dict shape, game.gd). Only the DISPLAY
# argument (first arg) is scanned — kind/icon literals ('chaos', '🧬') are
# not display text, and floatWorld/banner texts are composed in TS (the
# `+${dna}` style), exactly as the TS first-arg regex scoped it.

const SCAN_DIRS := ["res://src/game", "res://src/ui"]

var _re_unwrapped_dot: RegEx
var _re_unwrapped_call: RegEx
var _re_tr_key: RegEx
var _re_tr: RegEx
var _re_field: RegEx

func _scanners() -> void:
	_re_unwrapped_dot = RegEx.create_from_string(
			"hud\\.(toast|float_world|banner)\\s*\\(\\s*(\"((?:[^\"\\\\]|\\\\.)+)\"|'((?:[^'\\\\]|\\\\.)+)')")
	_re_unwrapped_call = RegEx.create_from_string(
			"hud\\[\"(toast|float_world|banner)\"\\]\\s*\\.\\s*call\\s*\\(\\s*(\"((?:[^\"\\\\]|\\\\.)+)\"|'((?:[^'\\\\]|\\\\.)+)')")
	_re_tr_key = RegEx.create_from_string(
			"(?<![A-Za-z0-9_])tr_key\\(\\s*(\"((?:[^\"\\\\]|\\\\.)+)\"|'((?:[^'\\\\]|\\\\.)+)')\\s*\\)")
	_re_tr = RegEx.create_from_string(
			"(?<![A-Za-z0-9_])tr\\(\\s*(\"((?:[^\"\\\\]|\\\\.)+)\"|'((?:[^'\\\\]|\\\\.)+)')\\s*\\)")
	_re_field = RegEx.create_from_string(
			"(?:\"warn\"|\"name\"|\"sub\"|\"body\")\\s*:\\s*(\"((?:[^\"\\\\]|\\\\.)+)\"|'((?:[^'\\\\]|\\\\.)+)')")


## Naive unescape of the captured literal — port of the TS audit's
## unesc (raw.replace(/\\(.)/g, '$1')): source literals carry \", \\ etc.
func _unesc(raw: String) -> String:
	var out := ""
	var i := 0
	while i < raw.length():
		if raw[i] == "\\" and i + 1 < raw.length():
			i += 1
		out += raw[i]
		i += 1
	return out


func _literal_of(m: RegExMatch, quote_group: int) -> String:
	# group layout in every scanner: quote_group = the ("..."|'...') alternative,
	# +1 = double-quoted body, +2 = single-quoted body
	var body := m.get_string(quote_group + 1)
	if body == "":
		body = m.get_string(quote_group + 2)
	return _unesc(body)


func _scan_all(text: String, re: RegEx) -> Array:
	var out := []
	var from := 0
	while true:
		var m: RegExMatch = re.search(text, from)
		if m == null:
			break
		out.append(m)
		from = m.get_end()
	return out


func _collect_gd_files(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return  # src/ui doesn't exist yet — activates when the UI tasks land
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			_collect_gd_files(dir_path + "/" + f, out)
		elif f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()


func test_audit_scanner_selfcheck() -> void:
	# The repo sweep below is vacuous until the HUD/UI tasks land — prove the
	# scanners themselves catch what the TS audit caught.
	_scanners()
	var vi: Variant = _i18n()
	var unwrapped := _scan_all('hud.toast("raw text")\n', _re_unwrapped_dot)
	eq(unwrapped.size(), 1, "selfcheck: dot-shape unwrapped toast literal flagged")
	eq(_literal_of(unwrapped[0], 2), "raw text", "selfcheck: flagged literal captured")
	eq(_scan_all('hud["toast"].call("raw two")', _re_unwrapped_call).size(), 1,
			"selfcheck: stub-dict call shape flagged")
	eq(_scan_all('hud["toast"].call(tr_key("fine"), "info", "📖")', _re_unwrapped_call).size(), 0,
			"selfcheck: tr_key-wrapped call not flagged")
	eq(_scan_all('hud.toast(x, "warn", "📖")', _re_unwrapped_dot).size(), 0,
			"selfcheck: non-display kind/icon args not flagged (first-arg scope)")
	eq(_scan_all('hud.float_world(e.x, e.y, "+%d DNA" % v, "#fff", 13.0)', _re_unwrapped_dot).size(), 0,
			"selfcheck: composed float text not flagged (TS floatWorld texts are composed)")
	var missing := _scan_all('var s := game.i18n.tr_key("NOT IN TABLE 123")', _re_tr_key)
	eq(missing.size(), 1, "selfcheck: tr_key literal captured")
	ok(not vi.vi_has(_literal_of(missing[0], 1)), "selfcheck: unknown tr_key literal fails vi_has")
	eq(_scan_all('hud.toast(tr_key("SAVE SLOT"), "info", "📖")', _re_tr_key).size(), 1,
			"selfcheck: wrapped literal captured for membership check")
	ok(vi.vi_has(_unesc("SAVE SLOT")), "selfcheck: known key passes vi_has")
	eq(_scan_all('strs.append(str(p))', _re_tr).size(), 0, "selfcheck: str( is not tr(")
	eq(_scan_all('toast.emit("%s %s" % [tr("New species discovered:"), name], "good", "📖")',
			_re_tr).size(), 1, "selfcheck: tr( literal in a composed toast captured")
	var fields := _scan_all('{"warn": "raw warn"}', _re_field)
	eq(fields.size(), 1, "selfcheck: event field literal captured")
	eq(_unesc(_literal_of(fields[0], 1)), "raw warn", "selfcheck: field literal captured")
	_restore_locale()


func test_structural_audit() -> void:
	_scanners()
	var vi: Variant = _i18n()
	var files := PackedStringArray()
	for d in SCAN_DIRS:
		_collect_gd_files(d, files)
	ok(files.size() >= 6, "audit sweep found the src/game sources (got %d files)" % files.size())
	var unwrapped := []
	var untranslated := []
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			continue
		var rel := path.replace("res://", "")
		for m in _scan_all(src, _re_unwrapped_dot):
			unwrapped.append("%s: hud.%s(\"%s\")" % [rel, m.get_string(1),
					_literal_of(m, 2).left(50)])
		for m in _scan_all(src, _re_unwrapped_call):
			unwrapped.append("%s: hud[\"%s\"].call(\"%s\")" % [rel, m.get_string(1),
					_literal_of(m, 2).left(50)])
		for m in _scan_all(src, _re_tr_key):
			var k := _literal_of(m, 1)
			if not vi.vi_has(k):
				untranslated.append("%s: tr_key(\"%s\")" % [rel, k.left(50)])
		for m in _scan_all(src, _re_tr):
			var k := _literal_of(m, 1)
			if not vi.vi_has(k):
				untranslated.append("%s: tr(\"%s\")" % [rel, k.left(50)])
		# TS port: event-definition files' warn/name/sub/body field literals
		# must be VI keys too (composed "%"-format values are exempt — the
		# analog of the TS audit skipping ${} templates).
		if path.get_file().to_lower().contains("event"):
			for m in _scan_all(src, _re_field):
				var k := _literal_of(m, 1)
				if not k.contains("%") and not vi.vi_has(k):
					untranslated.append("%s (field): \"%s\"" % [rel, k.left(50)])
	eq(unwrapped, [], "no unwrapped hud.toast/float_world/banner display literals")
	eq(untranslated, [], "every tr_key()/tr() literal in src/game+src/ui has a VI entry")
	_restore_locale()
