# Tests for R9 packmate identity — charm-time names (species_name + epithet
# via names.gd, tr-composed, deduped against the current pack with roman
# suffixes), the pack-persist name field ({genome, baby, name} — old saves
# without "name" restore clean and get a name lazily), the named packmate
# death (toast + bestiary fell note, extant pack untouched), the R9 identity
# ruling (the chosen creature_name becomes the arrival identity) and the
# pack-row member filter (living members only). TS source: Spore
# CreatureStage.ts charm win (1088-1099) + persistState (346) — names are a
# native R9 addition (the card renderer displays them, it does not invent).
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")
const NamesScript := preload("res://src/evo/names.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE


# ---- fixtures (the test_charm shapes) ------------------------------------------

func _mk_sim(seed_v: int = SEED, genome_mods: Dictionary = {}) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	if not genome_mods.is_empty():
		var g: Dictionary = ctx.genome
		g.merge(genome_mods, true)
	var rec: Dictionary = {
		"toasts": [], "banners": [], "floats": [], "audio": [], "shakes": [],
		"bursts": [], "spawns": [], "notes": [], "events": [],
		"tutorial": [], "go_to": [],
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_toast_gate": func(text, kind, icon, _window): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(playtime): rec["notes"].append(playtime),
		"context_event": func(ev, data): rec["events"].append([ev, data]),
		"tutorial_finish": func(): rec["tutorial"].append(true),
		"go_to": func(id, card): rec["go_to"].append([id, card]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CreatureSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


func _park_world_objects(m: Dictionary) -> void:
	var sim: Variant = m["sim"]
	for b in sim.bushes:
		b["x"] = 99999.0
		b["z"] = 99999.0
	for bo in sim.bones:
		bo["x"] = 99999.0
		bo["z"] = 99999.0


func _charm_tick(m: Dictionary, marker: float, press: bool) -> void:
	var sim: Variant = m["sim"]
	sim.charmMarker = marker
	var over: Dictionary = {"keys_held": ["KeyF"]}
	if press:
		over["keys_pressed"] = ["Space"]
	sim.update(DT, _inp(over))


## Full befriend: init + 3 beats with the re-arm steps between. The genome
## override REPLACES the ent genome (spawn_ent semantics) — size/diet ride
## every fixture (the sim hard-indexes both on the charm/AI paths).
func _befriend(m: Dictionary, genome: Dictionary = {}) -> Dictionary:
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var full: Dictionary = genome
	full["size"] = float(genome.get("size", 1.0))
	full["diet"] = String(genome.get("diet", "omnivore"))
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz), full)
	e["lifespanStampede"] = 14.0
	sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	_charm_tick(m, 0.0, true)
	_charm_tick(m, 0.5, false)
	_charm_tick(m, 0.05, true)
	_charm_tick(m, -0.6, false)
	_charm_tick(m, -0.05, true)
	return e


func _pack_ents(sim: Variant) -> Array:
	var out: Array = []
	for e in sim.ents:
		if bool(e["pack"]):
			out.append(e)
	return out


# ---- charm-time names ------------------------------------------------------------

# R9: the befriend block assigns a unique name (species_name + epithet via
# names.gd) — two packmates never share one.
func test_charm_assigns_distinct_names() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var e1: Dictionary = _befriend(m, {"spikes": 4, "diet": "herbivore"})
	eq(bool(e1["pack"]), true, "first befriend landed")
	var e2: Dictionary = _befriend(m, {"diet": "carnivore", "jaw": 3})
	eq(bool(e2["pack"]), true, "second befriend landed")
	var pack := _pack_ents(sim)
	eq(pack.size(), 2, "two packmates")
	var n1 := String(pack[0].get("packName", ""))
	var n2 := String(pack[1].get("packName", ""))
	ok(n1 != "", "packmate 1 named")
	ok(n2 != "", "packmate 2 named")
	ok(n1 != n2, "pack names are deduped (distinct)")
	ok(n1.length() <= 40, "name bounded (species + epithet + suffix)")


# R9 composition: the name is names.gd's species + epithet — a qualifying
# genome carries the (tr-composed) epithet, a plain one degrades to the
# species alone.
func test_pack_name_shape_species_plus_epithet() -> void:
	var m := _mk_sim()
	var e: Dictionary = _befriend(m, {"spikes": 4})
	var nm := String(e.get("packName", ""))
	ok(nm != "", "named")
	ok(nm.contains("the Spiky") or nm.contains("Pincushion") or nm.contains("Sharpbodied"),
			"the spikes epithet rides the name (tr-composed at assignment): %s" % nm)
	var m2 := _mk_sim()
	var e2: Dictionary = _befriend(m2, {"size": 1.0, "legs": 0})
	var nm2 := String(e2.get("packName", ""))
	ok(nm2 != "", "plain genome still named")
	eq(nm2.split(" ").size(), 1, "plain genome: species-only name (no epithet)")


# Deterministic dedup (the pure seam the compose path calls): a collision
# appends the roman numeral — II, III — and a free base passes through.
func test_pack_name_dedup_roman_suffix() -> void:
	eq(String(CreatureSim.pack_name_deduped("Zed", [])), "Zed", "free base passes")
	eq(String(CreatureSim.pack_name_deduped("Zed", ["Zed"])), "Zed II", "collision II")
	eq(String(CreatureSim.pack_name_deduped("Zed", ["Zed", "Zed II"])), "Zed III", "collision III")
	eq(String(CreatureSim.pack_name_deduped("Zed", ["Other"])), "Zed", "unrelated names never dedupe")
	eq(String(CreatureSim.pack_name_deduped("Zed", ["Zed", "Zed II", "Zed III", "Zed IV", "Zed V"])),
			"Zed VI", "the suffix ladder caps at VI (packLimit ≤ 6)")


# ---- persist round-trip ------------------------------------------------------------

# R9 schema {genome, baby, name}: the name rides the snapshot and restores.
func test_pack_persist_round_trip_keeps_names() -> void:
	var m := _mk_sim()
	var e: Dictionary = _befriend(m, {"spikes": 4})
	var saved_name := String(e["packName"])
	ok(saved_name != "", "named before persist")
	var wire: String = String(m["ctx"].flags["packGenomes"])
	var parsed: Variant = JSON.parse_string(wire)
	ok(parsed is Array and (parsed as Array).size() == 1, "snapshot has 1 member")
	if parsed is Array and (parsed as Array).size() == 1:
		var item: Dictionary = parsed[0]
		eq(String(item.get("name", "<missing>")), saved_name, "the name rides the snapshot")
	# a fresh sim on the same ctx restores the named friend
	var m2 := _mk_sim()
	m2["ctx"].flags["packGenomes"] = wire
	m2["sim"].on_enter()
	eq(m2["sim"].ents.size(), 1, "the friend survives the reload")
	if m2["sim"].ents.size() == 1:
		var r: Dictionary = m2["sim"].ents[0]
		eq(String(r.get("packName", "")), saved_name, "restored ent keeps its name")


# Old saves (schema without "name") restore without crash; the unnamed
# member gets a name on the next sim tick, deduped against the loaded names.
func test_old_schema_restores_and_names_lazily() -> void:
	var m := _mk_sim()
	var genome: Dictionary = {"size": 1.0, "spikes": 4, "diet": "herbivore", "legs": 4}
	var list: Array = [
		{"genome": genome, "baby": false, "name": "Keeper"},
		{"genome": genome, "baby": false},  # old schema — no name
	]
	var m2 := _mk_sim()
	m2["ctx"].flags["packGenomes"] = JSON.stringify(list)
	m2["sim"].on_enter()
	eq(m2["sim"].ents.size(), 2, "both members restore")
	if m2["sim"].ents.size() == 2:
		var named := 0
		for e in m2["sim"].ents:
			if String(e.get("packName", "")) == "Keeper":
				named += 1
		eq(named, 1, "the saved name restores verbatim")
	# the lazy pass names the unnamed one without disturbing the loaded one
	m2["sim"].update(DT, _inp())
	var names: Array = []
	for e in m2["sim"].ents:
		names.append(String(e.get("packName", "")))
	ok(names.has("Keeper"), "the loaded name survives the lazy pass")
	var unnamed := 0
	for n in names:
		if n == "":
			unnamed += 1
	eq(unnamed, 0, "every packmate carries a name after the lazy pass")
	var fresh: Array = []
	for n in names:
		if n != "Keeper":
			fresh.append(n)
	eq(fresh.size(), 1, "exactly one lazily named member")
	ok(String(fresh[0]) != "Keeper", "the lazy name dedupes against the loaded one")


# ---- packmate death ----------------------------------------------------------------

# R9: a named packmate dies -> toast "<name> fell — gen N" + a bestiary fell
# note on the species entry; the extant pack is untouched.
func test_packmate_death_toast_and_bestiary_note() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	sim.debug_spawn_pack(2)
	sim._lazy_pack_names()
	var pack := _pack_ents(sim)
	eq(pack.size(), 2, "two packmates")
	var victim: Dictionary = pack[0]
	var survivor: Dictionary = pack[1]
	var vname := String(victim["packName"])
	var sname := String(survivor["packName"])
	ok(vname != "" and sname != "", "both named")
	ok(vname != sname, "names distinct")
	var gen := int(victim["genome"].get("generation", 1))
	sim.kill_ent(victim)
	eq(bool(victim.has("corpseT")), true, "the victim is a corpse")
	var texts: Array = []
	for t in m["rec"]["toasts"]:
		texts.append(String(t[0]))
	var want := vname + " fell — gen " + str(gen)
	ok(texts.has(want), "named death toast: %s" % want)
	# bestiary note keyed by the species genome
	var entry: Variant = m["ctx"].bestiary.get(Ctx.genome_hash_lite(victim["genome"]))
	ok(entry != null, "the species entry exists")
	if entry != null:
		var fell := String(entry.get("fell", ""))
		ok(fell.contains(vname), "the fell note carries the packmate name: %s" % fell)
		ok(fell.contains("gen " + str(gen)), "the fell note carries the generation")
	# extant pack untouched
	eq(bool(survivor.has("corpseT")), false, "the survivor is untouched")
	eq(String(survivor["packName"]), sname, "the survivor keeps its name")
	# the dead member never persists
	sim.persist_state()
	var parsed: Variant = JSON.parse_string(String(m["ctx"].flags["packGenomes"]))
	var count := 0
	if parsed is Array:
		for item in parsed:
			if String(item.get("name", "")) == sname:
				count += 1
	eq(count, 1, "persist keeps only the extant member")


# ---- identity ruling ----------------------------------------------------------------

# R9 identity: the chosen creature_name IS the arrival identity — the banner
# announces it and player_name takes it; autoName stays the fallback.
func test_arrival_identity_uses_chosen_name() -> void:
	var m := _mk_sim()
	var ctx: Variant = m["ctx"]
	ctx.set_display_name("Zed")
	m["sim"].on_enter()
	eq(String(ctx.player_name), "Zed", "the chosen name becomes the identity")
	var titles: Array = []
	for b in m["rec"]["banners"]:
		titles.append(String(b.get("title", "")))
	ok(titles.has("THE PACK WILL CALL YOU ZED"), "the arrival banner announces the chosen name")


func test_arrival_identity_autoname_fallback() -> void:
	var m := _mk_sim()
	var ctx: Variant = m["ctx"]
	eq(String(ctx.creature_name), "", "no chosen name")
	m["sim"].on_enter()
	var auto: String = NamesScript.self_name(ctx.genome)
	eq(String(ctx.player_name), auto, "autoName fallback unchanged")


# The consumer seam: get_player_display reads the chosen name when set and
# the derived player_name otherwise (civ "{name}grad", WELCOME BACK).
func test_get_player_display_identity_seam() -> void:
	var ctx: Variant = Ctx.new(SEED)
	ctx.player_name = "Chieftain"
	eq(String(ctx.get_player_display()), "Chieftain", "fallback is the derived player_name")
	ctx.set_display_name("Zed")
	eq(String(ctx.get_player_display()), "Zed", "the chosen name wins")


# ---- pack row data -----------------------------------------------------------------

# The portrait row shows LIVING pack members only (corpses leave the row).
func test_pack_row_members_living_only() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	sim.debug_spawn_pack(3)
	sim.ents[1]["corpseT"] = 12.0
	var wild: Dictionary = sim.spawn_ent(null, float(sim.px) + 300.0, float(sim.pz), {})
	eq(bool(wild["pack"]), false, "the wild ent is not pack")
	var members: Array = CreatureStageScript.pack_row_members(sim.ents)
	eq(members.size(), 2, "the corpse and the wild ent are excluded")
	for e in members:
		eq(bool(e["pack"]), true, "members are pack")
		eq(bool(e.has("corpseT")), false, "members are alive")
