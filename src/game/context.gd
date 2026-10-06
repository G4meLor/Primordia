## GameContext: everything that persists across stages — the player genome,
## DNA, karma/chaos meters, bestiary, world seed and per-stage progress.
## Port of Spore src/game/context.ts (round-11). SaveData / BestiaryEntry /
## WorldSaveBlob are plain Dictionaries with the TS wire keys verbatim
## (camelCase: totalDnaEarned / killsByPlayer / traitIds / comboFired / …).
## The native save format is fresh v1: TS v1/v2 saves are deliberately NOT
## migrated — load() accepts only version 1 and shape-validates every field,
## corrupt ones falling back to "starting fresh" (world re-derives from the
## seed). TS Bus/EV events port to Godot signals: dna_gained (EV.dna) and
## toast (EV.toast); the t() call becomes Object.tr (TranslationServer falls
## back to the key, matching the TS i18n fallback).
## Seed selection is meta-level, not a sim stream: the ONLY sanctioned global
## randi() use in the repo lives in _init's default picker.
## -s-mode constraint: this file never references its own class_name; all
## collaborators resolve via preload path consts (see ecosystem.gd).
class_name GameContext
extends RefCounted

const RngScript := preload("res://src/core/rng.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const StatsScript := preload("res://src/evo/stats.gd")
const EcoScript := preload("res://src/evo/ecosystem.gd")
const WorldGenomeScript := preload("res://src/evo/world_genome.gd")
const PartsScript := preload("res://src/evo/parts.gd")
const TraitsScript := preload("res://src/evo/world_traits.gd")

## StageId — plain strings validated by membership (TS string-literal union).
const STAGES := ["menu", "cell", "creature", "tribe", "civ", "space"]
## Stage gate inside load(): a save can never restore the menu itself.
const LOAD_STAGES := ["cell", "creature", "tribe", "civ", "space"]
## Difficulty — same.
const DIFFICULTIES := ["peaceful", "normal", "chaos"]
## Fresh native save format (deliberately not the TS v1/v2 wire).
const SAVE_VERSION := 1
## Editor cap on legs — corrupt/edited saves with more walk with phantom gait.
const LEGS_CAP := 6

signal dna_gained(amount, reason, x, y)
signal toast(text, kind, icon)

var rng: Variant = null  # TS new Rng(seed) — duck-typed like ecosystem.gd
var seed: int = 0

var genome: Dictionary = GenomeScript.default_genome()
var dna: int = 40
var karma := 0.0          # -1 aggressive … +1 harmonious
var chaos := 0.15         # 0 calm … 1 unhinged
var difficulty: String = "normal"
var slot := 0             # active save slot
var playtime := 0.0
var total_dna_earned := 0
var player_name: String = "Squish"
var stage: String = "menu"

## TS Map<string, BestiaryEntry> — Dictionary keyed by genome_hash_lite;
## insertion order is the TS Map iteration order (rare_gene reads it).
var bestiary: Dictionary = {}
var eco: Variant = null   # Ecosystem | null

## Per-stage progress blobs (tribe huts, civ cities, planets…).
var flags: Dictionary = {}

## Cached player stats, refreshed when the genome changes.
var stats: Dictionary = {}

## World genome derived from the seed — traits, turns, reveal state.
var world: Dictionary = {}
## World-level counters feeding reveal signals (persisted in the world blob).
var world_stats: Dictionary = {"kills": 0, "extinctions": 0}

var _dna_frac := 0.0  # TS private dnaFrac


func _init(seed_v: int = -1) -> void:
	# Seed selection is meta-level (outside every sim stream): the only
	# sanctioned global-RNG use in the repo. Tests always pass explicit seeds.
	if seed_v < 0:
		seed_v = randi()
	seed = seed_v
	rng = RngScript.new_from(seed)
	stats = StatsScript.compute_stats(genome, false)
	world = WorldGenomeScript.derive_world_genome(seed)


## The player ate one more creature somewhere in this world.
func bump_kill() -> void:
	world_stats["kills"] = int(world_stats["kills"]) + 1


## One more species died out somewhere in this world.
func bump_extinction() -> void:
	world_stats["extinctions"] = int(world_stats["extinctions"]) + 1


func refresh_stats(land: bool) -> Dictionary:
	stats = StatsScript.compute_stats(genome, land)
	return stats


func add_dna(amount: float, reason: Variant = null, x: Variant = null, y: Variant = null) -> void:
	if amount == 0:
		return
	# accumulate fractional gains (proboscis trickle) so slow income is not
	# rounded into nothing every tick
	_dna_frac += amount
	var whole := int(_dna_frac)  # Math.trunc: the GDScript int() cast truncates toward zero
	if whole != 0:
		_dna_frac -= float(whole)
		dna = maxi(0, dna + whole)
		if whole > 0:
			total_dna_earned += whole
		dna_gained.emit(whole, reason, x, y)


func spend_dna(amount: int) -> bool:
	if dna < amount:
		return false
	dna -= amount
	return true


## Chaos drifts up with wild acts, slowly settles.
func add_chaos(d: float) -> void:
	chaos = clampf(chaos + d, 0.0, 1.0)


func add_karma(d: float) -> void:
	karma = clampf(karma + d, -1.0, 1.0)


## Chaos event frequency multiplier per difficulty.
func chaos_gap_mult() -> float:
	return 1.5 if difficulty == "peaceful" else (0.7 if difficulty == "chaos" else 1.0)


func starting_chaos() -> float:
	return 0.08 if difficulty == "peaceful" else (0.45 if difficulty == "chaos" else 0.15)


func discover(genome_v: Dictionary, name: String, stage_v: String, kin := false) -> Dictionary:
	var key := genome_hash_lite(genome_v)
	var entry: Variant = bestiary.get(key)
	if entry == null:
		entry = {
			"key": key, "name": name,
			"genome": GenomeScript.clamp_genome(genome_v),
			"stage": stage_v, "seen": 0, "killsByPlayer": 0,
			"extinct": false, "kin": kin,
		}
		bestiary[key] = entry
		# stay quiet while the title screen seeds ecosystems (no toast spam)
		if stage != "menu":
			toast.emit("%s %s" % [tr("New species discovered:"), name], "good", "📖")
	entry["seen"] = _seen_plus_one(entry)
	return entry


## gaia_redemption tier 2: a part level the player's genome has never
## owned, drawn from the world bestiary (the wanderer's rare gene).
func rare_gene() -> Variant:
	for entry in bestiary.values():
		for def in PartsScript.PARTS:
			var v: Variant = entry["genome"].get(def["gene"])
			var mine: Variant = genome.get(def["gene"])
			if (v is float or v is int) and (mine is float or mine is int) \
					and float(v) > float(mine):
				return {"gene": def["gene"], "level": v}
	return null


## Stamp the bestiary entry whose genome matches an extinct species.
func mark_extinct(genome_v: Dictionary) -> void:
	var key := genome_hash_lite(genome_v)
	var e: Variant = bestiary.get(key)
	if e != null and not e["extinct"]:
		e["extinct"] = true
		toast.emit("%s has gone EXTINCT" % e["name"], "chaos", "💀")


# ---- persistence ---------------------------------------------------------

func to_save_data() -> Dictionary:
	var trait_ids := []
	for t in world["traits"]:
		trait_ids.append(t["id"])
	return {
		"version": SAVE_VERSION,
		"seed": seed,
		"stage": stage,
		"difficulty": difficulty,
		"genome": genome,
		"dna": dna,
		"karma": karma,
		"chaos": chaos,
		"playtime": playtime,
		"totalDnaEarned": total_dna_earned,
		"playerName": player_name,
		"bestiary": bestiary.values(),
		"eco": eco.to_json() if eco != null else null,
		"flags": flags,
		"world": {
			"traitIds": trait_ids,
			"turnIds": world["turns"],
			"revealed": world["revealed"],
			"comboFired": world["comboFired"],
			"firedTurns": world["firedTurns"],
			"worldStats": world_stats,
			"temperament": world["temperament"],
		},
	}


## Save into a slot (defaults to the active one). No SlotMeta envelope — the
## top-level SaveData fields are enough for the native format.
func save(slot_v: int = -1) -> bool:
	# QC r2 C2 crash-window breadcrumbs (silent quit-to-title death): bracket
	# every persist seam — serialize, write, verify — with a flush-per-write
	# file marker (stdout dies with the process, the file does not). ~4 lines
	# per save (autosave 60 s), silent when nothing crashes.
	_qc2_mark("save: enter stage=%s slot=%d" % [stage, slot_v])
	# never persist the MENU as a run state — a stray save path (pause over
	# the title screen) used to downgrade the slot to stage 'menu', and the
	# next CONTINUE loaded the cell stage over the finished run
	if stage == "menu":
		_qc2_mark("save: skip (menu)")
		return false
	if slot_v < 0:
		slot_v = slot
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open("user://saves/slot%d.json" % slot_v, FileAccess.WRITE)
	if f == null:
		_qc2_mark("save: open FAILED")
		return false
	# full_precision: TS JSON.stringify keeps full doubles — lossless round-trips
	var payload := JSON.stringify(to_save_data(), "", false, true)
	_qc2_mark("save: serialized len=%d" % payload.length())
	f.store_string(payload)
	f.flush()  # land the buffered bytes now, not at handle teardown
	# TS writeFileSync throws on a failed write = fail-loud; a silent success
	# here would report a save over a truncated file (disk full). Godot 4.2
	# quirk: a short fwrite ERR_FAILs but leaves the handle's error state OK,
	# so get_error() alone cannot see it — verify the payload landed complete.
	var ok := f.get_error() == OK and f.get_length() == payload.to_utf8_buffer().size()
	_qc2_mark("save: done ok=%s" % ok)
	return ok


## QC r2 C2 crash-window breadcrumb (shared shape with pause.gd's _qc2_mark).
func _qc2_mark(tag: String) -> void:
	var line := "C2Q[%d] %s" % [Time.get_ticks_msec(), tag]
	print(line)
	var f := FileAccess.open("user://crash_markers.log", FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
	else:
		f = FileAccess.open("user://crash_markers.log", FileAccess.WRITE)
	if f != null:
		f.store_string(line + "\n")
		f.flush()


func load(slot_v: int) -> bool:
	var data_v: Variant = _read_slot_json(slot_v)
	if not (data_v is Dictionary):
		return false
	var data: Dictionary = data_v
	# fresh native v1 only: TS v1/v2 saves are NOT migrated (deliberate)
	var ver: Variant = data.get("version")
	if not ((ver is float or ver is int) and is_finite(ver) and float(ver) == 1.0):
		return false
	# shape-validate: corrupt saves must fall back to "starting fresh"
	var seed_v: Variant = data.get("seed")
	var dna_v: Variant = data.get("dna")
	var genome_v: Variant = data.get("genome")
	var eco_v: Variant = data.get("eco")
	var flags_v: Variant = data.get("flags")
	var stage_v: Variant = data.get("stage")
	# (a JSON array genome passes the TS typeof-'object' gate and then spreads
	# no keys into the merge — parity for that quirk, not a silent tightening)
	var ok := (seed_v is float or seed_v is int) and is_finite(seed_v) \
			and (dna_v is float or dna_v is int) and is_finite(dna_v) \
			and (genome_v is Dictionary or genome_v is Array) \
			and (not _truthy(eco_v) or ((eco_v is Dictionary) and (eco_v.get("species") is Array))) \
			and (flags_v is Dictionary) \
			and (stage_v is String) and LOAD_STAGES.has(stage_v)
	if not ok:
		return false
	# bestiary must be an array of entries with key + genome — one bad apple
	# drops the whole list (TS .some()), entries otherwise ride verbatim
	var best_list: Array = []
	if data.get("bestiary") is Array:
		var all_ok := true
		for e in data["bestiary"]:
			if not (e is Dictionary) or not (e.get("key") is String) \
					or not (e.get("genome") is Dictionary):
				all_ok = false
				break
		if all_ok:
			best_list = data["bestiary"]
	slot = slot_v
	seed = int(seed_v)  # ToInt32 truncation for the fractional corruption edge
	rng = RngScript.new_from(seed)
	# TS {...defaultGenome(), ...data.genome}: shallow merge, saved keys win,
	# unknown keys ride; an array genome spreads nothing (defaults win)
	var merged: Dictionary = GenomeScript.default_genome()
	if genome_v is Dictionary:
		merged.merge(genome_v, true)
	genome = GenomeScript.clamp_genome(merged)
	# legs beyond the editor's cap (corrupt/edited saves) walk with phantom
	# gait legs — clamp to what the parts catalog actually allows
	var legs := minf(float(LEGS_CAP), float(genome["legs"]))
	genome["legs"] = int(legs) if legs == floorf(legs) else legs
	dna = maxi(0, int(dna_v))
	var karma_v: Variant = data.get("karma")
	karma = clampf(float(karma_v) if (karma_v is float or karma_v is int) and is_finite(karma_v) else 0.0, -1.0, 1.0)
	var chaos_v: Variant = data.get("chaos")
	chaos = clampf(float(chaos_v) if (chaos_v is float or chaos_v is int) and is_finite(chaos_v) else 0.15, 0.0, 1.0)
	var diff_v: Variant = data.get("difficulty")
	difficulty = diff_v if diff_v == "peaceful" or diff_v == "chaos" else "normal"
	stage = stage_v if stage_v != null and stage_v != "menu" else "cell"
	var pt_v: Variant = data.get("playtime")
	playtime = float(pt_v) if (pt_v is float or pt_v is int) and is_finite(pt_v) else 0.0
	var tde_v: Variant = data.get("totalDnaEarned")
	total_dna_earned = int(tde_v) if (tde_v is float or tde_v is int) and is_finite(tde_v) else 0
	var pn_v: Variant = data.get("playerName")
	player_name = pn_v if pn_v is String and not (pn_v as String).is_empty() else "Squish"
	bestiary = {}
	for e in best_list:
		bestiary[e["key"]] = e
	flags = flags_v
	# world genome: always re-derive from the seed first (deterministic, so
	# blob-less saves gain their world for free), then overlay the blob's
	# runtime state — shape-validate each field, corrupt ones keep the
	# re-derive
	world = WorldGenomeScript.derive_world_genome(seed)
	world_stats = {"kills": 0, "extinctions": 0}
	var wb: Variant = data.get("world")
	if wb is Dictionary:
		if wb.get("traitIds") is Array:
			var traits := []
			for id_v in wb["traitIds"]:
				var def: Variant = _trait_def_by_id(id_v)
				if def != null:
					traits.append(def)
			# all-unknown / empty lists keep the re-derived traits (never traitless)
			if traits.size() > 0:
				world["traits"] = traits
		if wb.get("turnIds") is Array:
			var turns := []
			for id_v in wb["turnIds"]:
				if id_v is String:
					turns.append(id_v)
			world["turns"] = turns
		var revealed: Variant = _bool_rec(wb.get("revealed"))
		if revealed != null:
			world["revealed"] = revealed
		var combo_fired: Variant = _bool_rec(wb.get("comboFired"))
		if combo_fired != null:
			world["comboFired"] = combo_fired
		var fired_turns: Variant = _bool_rec(wb.get("firedTurns"))
		if fired_turns != null:
			world["firedTurns"] = fired_turns
		# minor 2: the runtime temperament rides the blob (shape-validated)
		var temp_v: Variant = wb.get("temperament")
		if temp_v is String and ["none", "cradle", "lean", "wildcard"].has(temp_v):
			world["temperament"] = temp_v
		var ws: Variant = wb.get("worldStats")
		if ws is Dictionary:
			world_stats = {
				"kills": _ws_stat(ws.get("kills")),
				"extinctions": _ws_stat(ws.get("extinctions")),
			}
	if _truthy(eco_v):
		eco = EcoScript.from_json(eco_v, rng.branch())
	else:
		eco = null
	return true


# ---- context-local helpers -------------------------------------------------

## Read + parse a slot file. Any failure (missing, unreadable, junk) returns
## null so load() falls back to false without crashing.
func _read_slot_json(slot_v: int) -> Variant:
	var path := "user://saves/slot%d.json" % slot_v
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## TS entry.seen++ coerced at the boundary: corrupt non-numeric values read as
## 0 instead of poisoning the counter (native saves always write ints).
func _seen_plus_one(entry: Dictionary) -> int:
	var seen_v: Variant = entry.get("seen")
	var seen := int(seen_v) if seen_v is float or seen_v is int else 0
	return seen + 1


## Context-LOCAL lite fingerprint (context.ts bottom): joins 20 fields with
## "-", hue bucketed by /12, NO sat, tail truthy -> 1. NOT genome.gd's
## genome_hash (that one is hue/15 + sat — the breeding hash); bestiary keys
## must match the frozen TS bestiary semantics, so this stays separate.
## Math.round -> floori(x + 0.5) (JS rounds halves toward +infinity).
static func genome_hash_lite(g: Dictionary) -> String:
	var parts := [
		_round_js(float(g.get("size", 0)) * 10.0), g.get("diet", ""),
		_round_js(float(g.get("hue", 0)) / 12.0), g.get("pattern", ""),
		g.get("flagella", 0), g.get("cilia", 0), g.get("spikes", 0), g.get("jaw", 0),
		g.get("toxin", 0), g.get("proboscis", 0), g.get("electro", 0), g.get("jet", 0),
		g.get("legs", 0), g.get("arms", 0), g.get("eyes", 0), g.get("horns", 0),
		1 if g.get("tail", false) else 0, g.get("wings", 0), g.get("brain", 0),
		g.get("coat", ""),
	]
	var strs := PackedStringArray()
	for p in parts:
		strs.append(str(p))
	return "-".join(strs)


static func _round_js(x: float) -> int:
	return floori(x + 0.5)  # JS Math.round: ties toward +infinity


## JS truthiness for the load() gates (a falsy eco blob reads as absent).
static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is String:
		return not v.is_empty()
	if v is float or v is int:
		var f := float(v)
		return not is_nan(f) and f != 0.0
	return true


## TRAIT_DEFS lookup by id — a miss keeps the re-derived trait instead.
static func _trait_def_by_id(id_v: Variant) -> Variant:
	for d in TraitsScript.TRAIT_DEFS:
		if d["id"] == id_v:
			return d
	return null


## TS boolRec: object (not array) whose boolean-valued entries survive;
## anything else reads as null = "keep the re-derived record".
static func _bool_rec(v: Variant) -> Variant:
	if not (v is Dictionary):
		return null
	var out := {}
	for k in v:
		if v[k] is bool:
			out[k] = v[k]
	return out


## TS worldStats stat(): finite number -> max(0, floor(v)), anything else 0.
static func _ws_stat(v: Variant) -> int:
	if (v is float or v is int) and is_finite(v):
		return maxi(0, floori(float(v)))
	return 0
