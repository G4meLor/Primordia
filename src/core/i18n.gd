## Minimal i18n: tr_key(english_string) returns the translation for the
## current language, or the original string when no entry exists — English is
## the key space, call sites stay readable and untranslated strings degrade
## to EN. Port of Spore src/core/i18n.ts. The VI dictionary ships as
## assets/i18n/vi.csv (generated verbatim from the TS VI object by
## tools/gen_i18n_csv.js) and is registered into the TranslationServer at
## startup, so plain tr() call sites (the M1 convention, context.gd) resolve
## too. set_lang/get_lang/set_muted/get_muted port the settings API —
## TS localStorage primordia.settings.v1 becomes user://settings.cfg
## (ConfigFile, section "settings", keys lang/muted).
##
## RefCounted, NOT an autoload: Game._init constructs its cores (context/
## input/cam/loop/storyteller) exactly this way, and `-s` script-mode test
## runs never instantiate project autoloads — an autoload would make the
## i18n state untestable headless and double-boot with Game.
class_name I18n
extends RefCounted

const CSV_PATH := "res://assets/i18n/vi.csv"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
const LANG_EN := "en"
const LANG_VI := "vi"
const SECTION := "settings"

## Registration guard: repeated Game constructions (tests, bots) must not
## stack duplicate Translation resources into the process-global server.
static var _translation_registered := false

## Tests point this at a scratch cfg and wipe it around themselves — the
## suite shares one process and one user:// dir.
var settings_path := DEFAULT_SETTINGS_PATH

var _vi := {}          # EN key -> VI, kept alongside the Translation for
                       # vi_has()/vi_key_count() and the audit's membership
var _lang := LANG_EN
var _muted := false


func _init(override_settings_path: String = "") -> void:
	if override_settings_path != "":
		settings_path = override_settings_path
	_load_csv()
	load_settings()


func get_lang() -> String:
	return _lang


func get_muted() -> bool:
	return _muted


## Auto-detect Vietnamese systems; otherwise English (TS detectLang:
## navigator.language starts with 'vi').
func detect_lang() -> String:
	return LANG_VI if OS.get_locale_language() == "vi" else LANG_EN


func set_lang(lang: String) -> void:
	if lang != LANG_EN and lang != LANG_VI:
		return  # TS enforces the Lang union at compile time; runtime guard here
	_lang = lang
	_apply_locale()
	save_settings()


func set_muted(m: bool) -> void:
	_muted = m
	save_settings()


## TS loadSettings: a valid stored lang wins, else auto-detect; muted only
## when explicitly true; a missing file degrades to the defaults.
func load_settings() -> Dictionary:
	var lang := detect_lang()
	var muted := false
	if FileAccess.file_exists(settings_path):
		var cfg := ConfigFile.new()
		if cfg.load(settings_path) == OK:
			var raw_lang: Variant = cfg.get_value(SECTION, "lang", "")
			if raw_lang is String and (raw_lang == LANG_VI or raw_lang == LANG_EN):
				lang = raw_lang
			muted = cfg.get_value(SECTION, "muted", false) == true
	_lang = lang
	_muted = muted
	return {"lang": lang, "muted": muted}


## TS saveSettings — write to a temp file and rename over the target so a
## crash mid-write can't leave a torn cfg.
func save_settings() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "lang", _lang)
	cfg.set_value(SECTION, "muted", _muted)
	var tmp := settings_path + ".tmp"
	if cfg.save(tmp) != OK:
		push_error("i18n: cannot write %s" % tmp)
		return false
	if DirAccess.rename_absolute(tmp, settings_path) != OK:
		push_error("i18n: cannot finalize %s" % settings_path)
		return false
	return true


## Translate. Unknown keys (i.e. English strings) pass through unchanged.
## Ensures the process-global TranslationServer locale matches the setting
## first — tr() is a global lookup other code may have moved.
func tr_key(s: String) -> String:
	if TranslationServer.get_locale() != _lang:
		_apply_locale()
	return tr(s)


## Push the saved lang into the TranslationServer (Game boot calls this so
## plain tr() call sites resolve per the user's setting).
func apply_locale() -> void:
	_apply_locale()


func _apply_locale() -> void:
	TranslationServer.set_locale(_lang)


func vi_key_count() -> int:
	return _vi.size()


func vi_has(key: String) -> bool:
	return _vi.has(key)


## Parse assets/i18n/vi.csv (RFC-4180, header row `key,vi`) and register the
## messages as a "vi" Translation resource — EN degrades to the key itself
## because no "en" messages exist (TS t(): VI[s] ?? s).
func _load_csv() -> void:
	var text := FileAccess.get_file_as_string(CSV_PATH)
	if text == "":
		push_error("i18n: cannot read %s" % CSV_PATH)
		return
	var rows := _parse_csv(text)
	if rows.is_empty() or rows[0].size() != 2 or rows[0][0] != "key" or rows[0][1] != "vi":
		push_error("i18n: %s missing the key,vi header row" % CSV_PATH)
		return
	for i in range(1, rows.size()):
		if rows[i].size() != 2:
			push_error("i18n: %s row %d malformed" % [CSV_PATH, i])
			continue
		_vi[rows[i][0]] = rows[i][1]
	if _vi.is_empty() or _translation_registered:
		return
	var tr_res := Translation.new()
	tr_res.set_locale(LANG_VI)
	for key in _vi:
		tr_res.add_message(key, _vi[key])
	TranslationServer.add_translation(tr_res)
	_translation_registered = true


## Hand-rolled RFC-4180 parser — Godot's CSV handling is editor-side and the
## table has comma-containing keys/values, so quoted fields are load-bearing.
func _parse_csv(text: String) -> Array:
	var rows := []
	var row := []
	var field := ""
	var quoted := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if quoted:
			if c == "\"":
				if i + 1 < text.length() and text[i + 1] == "\"":
					field += "\""
					i += 1
				else:
					quoted = false
			else:
				field += c
		elif c == "\"" and field == "":
			quoted = true
		elif c == ",":
			row.append(field)
			field = ""
		elif c == "\n" or c == "\r":
			if c == "\r" and i + 1 < text.length() and text[i + 1] == "\n":
				i += 1
			row.append(field)
			field = ""
			rows.append(row)
			row = []
		else:
			field += c
		i += 1
	if field != "" or not row.is_empty():
		row.append(field)
		rows.append(row)
	return rows
