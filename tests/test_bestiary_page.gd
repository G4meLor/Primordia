# Tests for R8 bestiary cheap — the extinction-moment card queue (one card per
# species extinction event, guarded at the bestiary entry; the live stage
# drains it), the named-packmate fell note on the entry, and the pause
# bestiary page (self entry via get_display_name, discovered rows with stage/
# fell/extinct stamp, "???" placeholders for unseen eco species, wheel scroll
# window, pause-nav reachability). Plus the R9 identity consumer on the civ
# city name. The page is TEXT ROWS ONLY in v1 — no thumbnails (RID discipline).
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const PauseUiScript := preload("res://src/ui/pause.gd")
const CivSim := preload("res://src/game/civ/civ_sim.gd")

const SEED := 0xBE5


# ---- fixtures ------------------------------------------------------------------

class StubI18n:
	func tr_key(k: String) -> String: return k
	func get_lang() -> String: return "en"


class StubInput:
	var mx := 0.0
	var my := 0.0
	var wheel_value := 0.0
	func was_clicked() -> bool: return false
	func take_click() -> void: pass
	func wheel() -> float: return wheel_value


class StubGame:
	var vw := 800.0
	var vh := 600.0
	var muted := false
	var i18n := StubI18n.new()
	var input := StubInput.new()
	var context: Variant = null
	func hover_cursor() -> void: pass


func _mk_page(seed_v: int = SEED) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	var game: Variant = StubGame.new()
	game.context = ctx
	var pause: Variant = PauseUiScript.new(game)
	return {"ctx": ctx, "game": game, "pause": pause}


# ---- extinction card queue ---------------------------------------------------------

# R8: mark_extinct queues exactly ONE card per species extinction event —
# a re-mark never re-fires, a second species does.
func test_extinction_card_queued_once() -> void:
	var ctx: Variant = Ctx.new(SEED)
	var g1: Dictionary = ctx.genome.duplicate()
	g1["hue"] = 10
	var g2: Dictionary = ctx.genome.duplicate()
	g2["hue"] = 200
	ctx.discover(g1, "Alpha", "creature")
	ctx.discover(g2, "Beta", "creature")
	eq(ctx.species_cards.size(), 0, "no cards queued by discovery")
	ctx.mark_extinct(g1)
	eq(ctx.species_cards.size(), 1, "the extinction queues one card")
	ctx.mark_extinct(g1)  # same species again — the entry guard blocks
	eq(ctx.species_cards.size(), 1, "a re-mark never re-fires")
	ctx.mark_extinct(g2)
	eq(ctx.species_cards.size(), 2, "a second species queues its own card")
	if ctx.species_cards.size() == 2:
		var first: Dictionary = ctx.species_cards[0]
		eq(String(first["name"]), "Alpha", "the card payload carries the species name")
		ok(first["genome"] is Dictionary and not (first["genome"] as Dictionary).is_empty(),
				"the card payload carries the genome")


# A species the book never saw: mark_extinct finds no entry — nothing queues
# (there is no moment for a species the player never met).
func test_extinction_card_needs_an_entry() -> void:
	var ctx: Variant = Ctx.new(SEED)
	var g: Dictionary = ctx.genome.duplicate()
	g["hue"] = 77
	ctx.mark_extinct(g)  # never discovered
	eq(ctx.species_cards.size(), 0, "no entry, no card")
	eq(ctx.bestiary.size(), 0, "no phantom entry either")


# ---- the fell note -----------------------------------------------------------------

# The bestiary note for a named packmate death: keyed by the species genome,
# carrying the packmate name + generation. Undiscovered species get an entry
# here (a packmate dying IS a sighting).
func test_note_pack_fell_records_and_discovers() -> void:
	var ctx: Variant = Ctx.new(SEED)
	var g: Dictionary = ctx.genome.duplicate()
	g["hue"] = 42
	ctx.note_pack_fell(g, "Fangington", 2)
	var key := Ctx.genome_hash_lite(g)
	var entry: Variant = ctx.bestiary.get(key)
	ok(entry != null, "an undiscovered species gains its entry")
	if entry != null:
		eq(String(entry["name"]), "Fangington", "the entry names the packmate's species (composed)")
		eq(String(entry["stage"]), "creature", "first seen in the creature stage")
		var fell := String(entry.get("fell", ""))
		ok(fell.contains("Fangington"), "the note carries the packmate name")
		ok(fell.contains("gen 2"), "the note carries the generation")
	# a second death of the same species overwrites (latest wins, v1 cheap)
	ctx.note_pack_fell(g, "Fangington II", 3)
	entry = ctx.bestiary.get(key)
	ok(String(entry.get("fell", "")).contains("Fangington II"), "the note is the latest one")


# ---- the pause bestiary page --------------------------------------------------------

# Rows: the SELF entry first (the chosen display name — Task 7 ruling), then
# the discovered entries in book order with stage / fell / extinct stamp.
func test_bestiary_rows_self_first_and_entries() -> void:
	var m := _mk_page()
	var ctx: Variant = m["ctx"]
	ctx.set_display_name("Zed")
	var g1: Dictionary = ctx.genome.duplicate()
	g1["hue"] = 10
	var g2: Dictionary = ctx.genome.duplicate()
	g2["hue"] = 200
	ctx.discover(g1, "Alpha the Spiky", "cell")
	ctx.discover(g2, "Beta", "creature")
	ctx.mark_extinct(g2)
	ctx.note_pack_fell(g1, "Alpha I", 2)
	var pause: Variant = m["pause"]
	var rows: Array = pause.bestiary_rows()
	ok(rows.size() >= 3, "self + 2 entries")
	if rows.size() >= 3:
		var self_row: Dictionary = rows[0]
		eq(String(self_row["text"]), "Zed · you", "the self entry reads get_display_name()")
		eq(String(self_row["kind"]), "self", "the self row is tagged")
		var alpha: Dictionary = rows[1]
		ok(String(alpha["text"]).contains("Alpha the Spiky"), "the discovered name rides the row")
		ok(String(alpha["text"]).contains("Cell"), "the first-stage name rides the row")
		ok(String(alpha["text"]).contains("Alpha I"), "the fell note rides the row")
		eq(String(alpha["kind"]), "normal", "a living species is a normal row")
		var beta: Dictionary = rows[2]
		ok(String(beta["text"]).contains("Beta"), "the extinct species name rides the row")
		ok(String(beta["text"]).contains("EXTINCT"), "the extinct stamp rides the row")
		eq(String(beta["kind"]), "gone", "an extinct species is a gone row")


# Undiscovered eco species render as "???" placeholders (world-codex shape).
func test_bestiary_rows_undiscovered_placeholders() -> void:
	var m := _mk_page()
	var ctx: Variant = m["ctx"]
	# the sim-less eco fixture: species the book has never seen
	ctx.eco = _mk_stub_eco([ctx.genome.duplicate(), ctx.genome.duplicate()])
	var pause: Variant = m["pause"]
	var rows: Array = pause.bestiary_rows()
	var unknown := 0
	for r in rows:
		if String(r["kind"]) == "unknown":
			unknown += 1
	eq(unknown, 2, "each unseen eco species is a ??? row")
	var known: Dictionary = ctx.genome.duplicate()
	known["hue"] = 5
	ctx.discover(known, "Seen", "cell")
	rows = pause.bestiary_rows()
	unknown = 0
	for r2 in rows:
		if String(r2["kind"]) == "unknown":
			unknown += 1
	eq(unknown, 2, "the discovered species leaves the ??? set")


# A null eco (fresh save, menu) degrades to no placeholder rows.
func test_bestiary_rows_null_eco() -> void:
	var m := _mk_page()
	var pause: Variant = m["pause"]
	var rows: Array = pause.bestiary_rows()
	eq(rows.size(), 1, "just the self row")
	eq(String(rows[0]["kind"]), "self", "the self row alone")


# Nav: the Bestiary button rides the main list; the page opens and Back
# returns — reachable from the existing pause nav.
func test_bestiary_nav_reachable() -> void:
	var m := _mk_page()
	var pause: Variant = m["pause"]
	pause.open()
	var labels: Array = []
	for it in pause.items:
		labels.append(String(it["label"]))
	ok(labels.has("📖  Bestiary"), "the Bestiary button is on the main list")
	eq(bool(pause.show_bestiary), false, "closed by default")
	pause._act_bestiary()
	eq(bool(pause.show_bestiary), true, "the page opens")
	eq(pause.items.size(), 1, "the page has its Back item")
	pause._act_back_bestiary()
	eq(bool(pause.show_bestiary), false, "Back returns to the main list")
	pause.open()
	eq(bool(pause.show_bestiary), false, "open() resets the page")


# Scroll: more rows than the 8-row window scrolls and clamps; the window is
# FIXED (the layout does not compress by row count).
func test_bestiary_scroll_window_clamps() -> void:
	var m := _mk_page()
	var ctx: Variant = m["ctx"]
	var pause: Variant = m["pause"]
	for i in 14:
		var g: Dictionary = ctx.genome.duplicate()
		# hue buckets at /12 in genome_hash_lite — stride 13 keeps every entry
		# in its own key
		g["hue"] = float(i + 1) * 13.0
		ctx.discover(g, "Species %d" % i, "cell")
	pause.open()
	pause._act_bestiary()
	var rows: Array = pause.bestiary_rows()
	eq(rows.size(), 15, "self + 14 entries")
	eq(int(pause.bestiary_window()), 8, "the window is a fixed 8 rows")
	var layout: Dictionary = pause.bestiary_layout(600.0)
	eq(float(layout["stride"]), 24.0, "the bestiary stride is fixed")
	# wheel down past the end clamps at the last window
	pause._scroll_bestiary(10000.0)
	ok(float(pause._bestiary_scroll) > 0.0, "wheel scrolls down")
	var max_scroll: float = float(pause.bestiary_max_scroll())
	eq(float(pause._bestiary_scroll), max_scroll, "the scroll clamps at the last window")
	pause._scroll_bestiary(-10000.0)
	eq(float(pause._bestiary_scroll), 0.0, "the scroll clamps at the top")


# ---- the R9 identity consumer on the civ side ---------------------------------------

# "{name}grad" reads the chosen creature name when set, the derived
# player_name otherwise (the WELCOME BACK consumer rides the same seam).
func test_civ_city_uses_chosen_name() -> void:
	var ctx: Variant = Ctx.new(SEED)
	ctx.player_name = "Chieftain"
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CivSim.new(ctx, rng, {})
	eq(String(sim.cities[0]["name"]), "Chieftaingrad", "fallback: the derived name")
	var ctx2: Variant = Ctx.new(SEED)
	ctx2.player_name = "Chieftain"
	ctx2.set_display_name("Zed")
	var sim2: Variant = CivSim.new(ctx2, ctx2.rng.branch(), {})
	eq(String(sim2.cities[0]["name"]), "Zedgrad", "the chosen name wins")


## Minimal eco stub: only what bestiary_rows reads (species genomes).
func _mk_stub_eco(genomes: Array) -> Variant:
	var eco: Variant = EcoStub.new(genomes)
	return eco


class EcoStub:
	var species: Array = []
	func _init(genomes: Array) -> void:
		for g in genomes:
			species.append({"genome": g, "name": "wild", "extinct": false})
