# Tests for game/creature/creature_sim.gd try_charm/update_charm/found_tribe —
# the charm rhythm minigame (target pick, gates, beat bar, befriend), the
# pack-persistence link (befriend -> persist_state -> on_enter restore) and
# the tribe-founding handoff. TS source: Spore src/game/creature/
# CreatureStage.ts tryCharm/updateCharm (frozen, 1023-1115), the F-hold wiring
# (486-493), persistState (344-347), onEnter pack restore (319-334) and
# foundTribe (1643-1652). Path-based extends + preload-by-path: class_name
# globals don't resolve in `-s` mode.
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const CreatureSim := preload("res://src/game/creature/creature_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE
# Dedicated test slot (90+ convention): the found_tribe save-flush pin.
const SLOT_FT := 110


# ---- fixtures ------------------------------------------------------------------

func _mk_sim(seed_v: int = SEED, genome_mods: Dictionary = {},
		difficulty: String = "normal") -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	if not genome_mods.is_empty():
		var g: Dictionary = ctx.genome
		g.merge(genome_mods, true)
	ctx.difficulty = difficulty
	var rec: Dictionary = {
		"toasts": [], "banners": [], "floats": [], "audio": [], "shakes": [],
		"bursts": [], "spawns": [], "notes": [], "events": [],
		"tutorial": [], "go_to": [],
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		# QC round-2 B3: the sim's gate toasts (pack-full, squeak-ignore) ride
		# the 4th window arg — recorded like a plain toast here
		"hud_toast_gate": func(text, kind, icon, _window): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(playtime): rec["notes"].append(playtime),
		"context_event": func(ev, data): rec["events"].append([ev, data]),
		# Task 4 hooks: tutorial finish (the sim gates on the mirrored
		# transitionTarget; the scene owns the tutorial object) and the stage
		# transition (the scene routes to game.go_to).
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


func _audio_names(rec: Dictionary) -> Array:
	var out: Array = []
	for a in rec["audio"]:
		out.append(String(a[0]))
	return out


func _toast_texts(rec: Dictionary) -> Array:
	var out: Array = []
	for t in rec["toasts"]:
		out.append(String(t[0]))
	return out


func _path(n: int) -> String:
	return "user://saves/slot%d.json" % n


# One beat of the minigame: park the marker at a chosen position (beat
# simulation — the per-tick oscillation is dir*speed*DT <= 0.027) and tick
# update() with F held (+ Space when `press`).
func _charm_tick(m: Dictionary, marker: float, press: bool) -> void:
	var sim: Variant = m["sim"]
	sim.charmMarker = marker
	var over: Dictionary = {"keys_held": ["KeyF"]}
	if press:
		over["keys_pressed"] = ["Space"]
	sim.update(DT, _inp(over))


# ---- try_charm: target pick + init ----------------------------------------------

# TS:1023-1058 — nearest eligible ent within 120 (pack/corpse/baby/packCd
# excluded), init state (hits 0, marker 0.75 OUTSIDE the zone, dir coin,
# mustExit false), mood alert, click audio, first-time charmsSeen hint.
func test_try_charm_picks_nearest_eligible() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_park_world_objects(m)
	# excluded candidates, all CLOSER than the real one
	sim.spawn_ent(null, float(sim.px) + 10.0, float(sim.pz), {}, {"pack": true})
	var corpse: Dictionary = sim.spawn_ent(null, float(sim.px) + 12.0, float(sim.pz))
	corpse["corpseT"] = 5.0
	sim.spawn_ent(null, float(sim.px) + 14.0, float(sim.pz), {}, {"baby": true})
	var cd: Dictionary = sim.spawn_ent(null, float(sim.px) + 16.0, float(sim.pz))
	cd["packCd"] = 3.0
	# eligible: the nearest at 50px, plus a farther one beyond the 120 radius
	var near: Dictionary = sim.spawn_ent(null, float(sim.px) + 50.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim.spawn_ent(null, float(sim.px) + 130.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	# direct call so the init state is exact (an update tick would already
	# advance the marker by dir*speed*dt)
	sim.try_charm()
	ok(sim.charmTarget != null and is_same(sim.charmTarget, near),
			"charmTarget is the nearest eligible ent")
	eq(bool(sim.charmActive), true, "charmActive set")
	eq(int(sim.charmHits), 0, "charmHits 0")
	approx(float(sim.charmMarker), 0.75, "marker starts 0.75 (outside the zone)")
	ok(sim.charmDir == 1 or sim.charmDir == -1, "dir coin is +-1")
	eq(bool(sim.charmMustExit), false, "mustExit false")
	eq(String(near["mood"]), "alert", "target mood alert")
	ok(_audio_names(m["rec"]).has("click"), "click audio")
	var hints: Array = []
	for t in m["rec"]["toasts"]:
		if String(t[0]).begins_with("Wait for the beat marker"):
			hints.append(t)
	eq(hints.size(), 1, "first-time charmsSeen hint fired once")
	eq(int(sim.charmsSeen), 1, "charmsSeen latched")
	# re-charm after release: the hint does NOT fire again
	sim.update(DT, _inp({}))  # F released -> charm cleared
	eq(bool(sim.charmActive), false, "F release clears the charm")
	sim.update(DT, _inp({"keys_held": ["KeyF"]}))  # re-charm (no hint)
	eq(int(sim.charmsSeen), 1, "charmsSeen stays 1")
	var hints2: Array = []
	for t in m["rec"]["toasts"]:
		if String(t[0]).begins_with("Wait for the beat marker"):
			hints2.append(t)
	eq(hints2.size(), 1, "hint fires only the first time")
	ok(ctx != null, "ctx reachable")


# The coin draw happens ONLY on the init path: an empty try_charm consumes
# no rng draw (stream order is sacred), the init path exactly one.
func test_try_charm_rng_draw_order() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var s0: int = sim.rng.state()
	sim.try_charm()  # no eligible ents -> early return before the coin
	eq(sim.rng.state(), s0, "empty-path try_charm consumed no rng draw")
	sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	var s1: int = sim.rng.state()
	sim.try_charm()  # init path: exactly one chance(0.5) draw
	ok(sim.rng.state() != s1, "init-path try_charm consumed the dir coin")
	eq(bool(sim.charmActive), true, "charmed")


# TS:1047-1049 — a marker born at 0 made F-hold + Space-mash an instant win
# (mash-to-win exploit): 0.75 starts OUTSIDE the zone, so an immediate press
# is a MISS (target annoyed, charm over). Direct update_charm calls: the AI
# tick would overwrite the transient angry mood the same frame (TS-true —
# updateEnts runs after updateCharm there too).
func test_charm_marker_starts_outside_zone() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim.try_charm()
	eq(bool(sim.charmActive), true, "charmed")
	# immediate Space (marker still 0.75, zone 0.35) -> miss
	sim.update_charm(DT, _inp({"keys_pressed": ["Space"]}))
	eq(bool(sim.charmActive), false, "immediate press misses")
	eq(String(e["mood"]), "angry", "missed target angry")
	approx(float(e["packCd"]), 6.0, "miss arms packCd 6")
	var texts: Array = _toast_texts(m["rec"])
	ok(texts.has("It did not like your rhythm."), "miss toast")
	ok(_audio_names(m["rec"]).has("hurt"), "miss audio hurt")


# TS:1035-1039 — pack full: toast with the live packLimit, no charm.
func test_try_charm_pack_full_gate() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	sim.debug_spawn_pack(2)  # packLimit 2 at the default genome
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	eq(bool(sim.charmActive), false, "pack full: no charm")
	ok(sim.charmTarget == null, "no charmTarget")
	var texts: Array = _toast_texts(m["rec"])
	ok(texts.has("Your pack is full (2) — evolve Arms/Brain for more"),
			"pack-full toast with the live packLimit")
	ok(String(e["mood"]) != "alert", "target never alerted (no charm init)")


# TS:1040-1043 — size gate: a much bigger target ignores a small-brained
# player; brain 2 opens the charm.
func test_try_charm_size_gate() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var big: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 2.0, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim.try_charm()  # 2.0 > 1.0*1.6 and brain 0 < 2 -> ignores
	eq(bool(sim.charmActive), false, "size gate blocks a brain-0 player")
	var texts: Array = _toast_texts(m["rec"])
	ok(texts.has("It ignores your squeaking. Grow bigger or smarter."),
			"size-gate toast")
	ok(sim.charmTarget == null, "no charmTarget")
	# brain 2 passes the gate
	var m2 := _mk_sim(SEED, {"brain": 2})
	var sim2: Variant = m2["sim"]
	_park_world_objects(m2)
	sim2.spawn_ent(null, float(sim2.px) + 40.0, float(sim2.pz),
			{"size": 2.0, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim2.try_charm()
	eq(bool(sim2.charmActive), true, "brain 2 charms the big one")
	ok(sim2.charmTarget != null, "charmTarget set")


# ---- update_charm: the beat bar --------------------------------------------------

# TS:1060-1115 — the full 3-beat rhythm: each hit must EXIT the zone (|m|
# >= 0.4 re-arms mustExit) before the next press counts; in-zone spam does
# nothing; 3 hits befriend (pack, happy, karma +0.03, lifespanStampede
# cleared, persist_state, burst, toast).
func test_charm_sequence_befriends() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	e["lifespanStampede"] = 14.0
	# init
	sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	eq(bool(sim.charmActive), true, "charmed")
	# beat 1 (zone 0.35)
	_charm_tick(m, 0.0, true)
	eq(int(sim.charmHits), 1, "beat 1 hit")
	# in-zone spam: mustExit guard ignores it
	_charm_tick(m, 0.0, true)
	eq(int(sim.charmHits), 1, "in-zone spam ignored")
	# re-arm (|m| >= 0.4)
	_charm_tick(m, 0.5, false)
	eq(bool(sim.charmMustExit), false, "mustExit re-armed outside the zone")
	# beat 2 (zone 0.30)
	_charm_tick(m, 0.05, true)
	eq(int(sim.charmHits), 2, "beat 2 hit")
	# re-arm on the negative side
	_charm_tick(m, -0.6, false)
	eq(bool(sim.charmMustExit), false, "mustExit re-armed (negative side)")
	# beat 3 (zone 0.25) -> befriend
	_charm_tick(m, -0.05, true)
	eq(int(sim.charmHits), 3, "beat 3 hit")
	eq(bool(sim.charmActive), false, "charm over")
	ok(sim.charmTarget == null, "charmTarget cleared")
	eq(bool(e["pack"]), true, "befriended: pack true")
	eq(String(e["mood"]), "happy", "befriended: happy")
	ok(not e.has("lifespanStampede"), "befriend clears the despawn clock")
	approx(float(ctx.karma), 0.03 + DT * 0.002, "karma +0.03 (+ the pack drift tick)")
	# persist_state fired on befriend (A02: the autosave keeps the pack)
	ok(ctx.flags.has("packGenomes"), "befriend persisted the pack")
	var parsed: Variant = JSON.parse_string(String(ctx.flags["packGenomes"]))
	ok(parsed is Array and (parsed as Array).size() == 1, "pack snapshot has 1 member")
	if parsed is Array and (parsed as Array).size() == 1:
		var item: Dictionary = parsed[0]
		eq(bool(item["baby"]), false, "persist_state baby false verbatim")
	# the star fx per hit + the befriend burst
	var stars := 0
	for s in m["rec"]["spawns"]:
		if String(s["kind"]) == "star":
			stars += 1
	eq(stars, 3, "one star fx per hit")
	eq(m["rec"]["bursts"].size(), 1, "befriend burst fired")
	if m["rec"]["bursts"].size() == 1:
		var b: Array = m["rec"]["bursts"][0]
		eq(int(b[2]), 14, "burst count 14")
	var charmCount := 0
	var levelups := 0
	for a in m["rec"]["audio"]:
		if String(a[0]) == "charm":
			charmCount += 1
		if String(a[0]) == "levelup":
			levelups += 1
	eq(charmCount, 3, "charm audio per hit")
	eq(levelups, 1, "levelup audio on befriend")
	var texts: Array = _toast_texts(m["rec"])
	ok(texts.has("A new friend joins your pack!"), "befriend toast")
	eq(int(sim.tut["actioned"]), 3, "tut.actioned +1 per beat")


# TS:1079-1081 — spamming Space inside the zone plays the soft hurt cue and
# changes nothing else (no hit, no star, no miss).
func test_charm_mash_in_zone_ignored() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	_charm_tick(m, 0.0, true)  # hit 1, mustExit armed
	var spawnsBefore: int = m["rec"]["spawns"].size()
	var audioBefore: int = m["rec"]["audio"].size()
	_charm_tick(m, 0.0, true)  # spam
	_charm_tick(m, 0.1, true)  # spam
	eq(int(sim.charmHits), 1, "spam adds no hits")
	eq(bool(sim.charmActive), true, "spam does not miss")
	eq(m["rec"]["spawns"].size(), spawnsBefore, "spam spawns no stars")
	var newAudio: int = m["rec"]["audio"].size() - audioBefore
	eq(newAudio, 2, "spam: the ignored-press cue per tick (jump blocked by cd)")
	var softHurts := 0
	for i in range(audioBefore, m["rec"]["audio"].size()):
		var a: Array = m["rec"]["audio"][i]
		if String(a[0]) == "hurt":
			softHurts += 1
	eq(softHurts, 2, "spam ticks play the ignored-press cue")


# TS:1103-1113 — a press outside the zone is a miss: charm over, target
# angry with packCd 6, rhythm toast. Direct calls keep the transient angry
# mood visible (the AI tick would re-mood the same frame, TS-true).
# QC round-2 B3: natively the angry mood now SURVIVES the AI tick while the
# miss's packCd window runs (the wander branch no longer clobbers it the
# same frame — cosmetic-only divergence, TS:964 still re-moods idle).
func test_charm_miss_annoyance() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim.try_charm()
	sim.charmMarker = 0.0
	sim.charmDir = 1
	sim.update_charm(DT, _inp({"keys_pressed": ["Space"]}))  # beat 1
	eq(int(sim.charmHits), 1, "beat 1 hit")
	sim.charmMarker = 0.9
	sim.update_charm(DT, _inp({"keys_pressed": ["Space"]}))  # outside zone 0.30
	eq(bool(sim.charmActive), false, "miss ends the charm")
	eq(String(e["mood"]), "angry", "target angry")
	approx(float(e["packCd"]), 6.0, "packCd 6")
	eq(bool(e["pack"]), false, "not befriended")
	approx(float(ctx.karma), 0.0, "no karma on a miss")
	var texts: Array = _toast_texts(m["rec"])
	ok(texts.has("It did not like your rhythm."), "rhythm toast")
	# the angry mood survives the AI tick (the wander branch's idle re-mood
	# is guarded while the miss's packCd runs — QC round-2 B3)
	sim.update(DT, _inp({}))
	eq(String(e["mood"]), "angry", "angry survives the same-tick wander re-mood")
	e["packCd"] = 0.0
	sim.update(DT, _inp({}))
	eq(String(e["mood"]), "idle", "once the charm cooldown lapses the wander re-mood returns")


# TS:1060-1069 — escape conditions: a target removed from ents toasts 'It got
# away'; a corpse or a >200px target clears SILENTLY; a valid target stays.
func test_charm_escape_conditions() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz))
	sim.charmActive = true
	sim.charmTarget = e
	# removed from ents (despawned/culled) -> got-away toast
	sim.ents.remove_at(0)
	sim.update_charm(DT, _inp({}))
	eq(bool(sim.charmActive), false, "gone target: charm cleared")
	ok(sim.charmTarget == null, "gone target: charmTarget cleared")
	var texts: Array = _toast_texts(m["rec"])
	ok(texts.has("It got away — chase it into a corner, or grow faster."),
			"got-away toast on a removed target")
	# corpse target (still in ents) -> silent clear
	var e2: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz))
	e2["corpseT"] = 5.0
	sim.charmActive = true
	sim.charmTarget = e2
	sim.update_charm(DT, _inp({}))
	eq(bool(sim.charmActive), false, "corpse target: charm cleared")
	eq(_toast_texts(m["rec"]).size(), texts.size(), "corpse escape is silent")
	# >200px target -> silent clear
	var e3: Dictionary = sim.spawn_ent(null, float(sim.px) + 250.0, float(sim.pz))
	sim.charmActive = true
	sim.charmTarget = e3
	sim.update_charm(DT, _inp({}))
	eq(bool(sim.charmActive), false, "far target: charm cleared")
	eq(_toast_texts(m["rec"]).size(), texts.size(), "distance escape is silent")
	# a valid target keeps the minigame running (marker oscillates)
	sim.charmActive = true
	sim.charmTarget = e3
	e3["x"] = float(sim.px) + 40.0
	sim.charmMarker = 0.0
	sim.charmDir = 1
	sim.update_charm(DT, _inp({}))
	eq(bool(sim.charmActive), true, "valid target: charm continues")
	approx(float(sim.charmMarker), 1.6 * DT, "marker advanced by dir*speed*dt")


# TS:486-493 — the F-hold wiring: releasing F mid-charm aborts silently.
func test_charm_release_clears() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	eq(bool(sim.charmActive), true, "charmed")
	sim.update(DT, _inp({}))  # release
	eq(bool(sim.charmActive), false, "release clears charmActive")
	ok(sim.charmTarget == null, "release clears charmTarget")
	approx(float(e["packCd"]), 0.0, "no miss penalty on a release")
	ok(String(e["mood"]) != "angry", "release is not a miss (no angry latch)")


# ---- pack persistence (A02) ------------------------------------------------------

# befriend -> persist_state -> a fresh on_enter restores the friend.
func test_befriend_persist_then_restore() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	_park_world_objects(m)
	var e: Dictionary = sim.spawn_ent(null, float(sim.px) + 40.0, float(sim.pz),
			{"size": 1, "diet": "herbivore", "legs": 4, "eyes": 2})
	sim.update(DT, _inp({"keys_held": ["KeyF"]}))
	_charm_tick(m, 0.0, true)
	_charm_tick(m, 0.5, false)
	_charm_tick(m, 0.05, true)
	_charm_tick(m, -0.6, false)
	_charm_tick(m, -0.05, true)
	eq(bool(e["pack"]), true, "befriended")
	var wire: String = String(m["ctx"].flags["packGenomes"])
	# a fresh sim restoring from that flag (the reload ate-your-friends fix)
	var m2 := _mk_sim()
	m2["ctx"].flags["packGenomes"] = wire
	m2["sim"].on_enter()
	eq(m2["sim"].ents.size(), 1, "the friend survives the reload")
	if m2["sim"].ents.size() == 1:
		var r: Dictionary = m2["sim"].ents[0]
		eq(bool(r["pack"]), true, "restored ent is pack")
		eq(String(r["mood"]), "happy", "restored ent happy")
		eq(int(r["genome"]["legs"]), 4, "restored genome rides verbatim")


# ---- found_tribe -----------------------------------------------------------------

# TS:1645 — the tutorial finish is gated on transitionTarget != 'menu' (a
# quit-to-title fade must not persist tutorial-done). The sim mirrors the
# game's transitionTarget (scene-written, like tribeRect); ctx.stage stays
# 'menu' here so the ctx.save() flush no-ops (no slot writes).
func test_found_tribe_menu_gate_skips_tutorial_finish() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.debug_spawn_pack(1)
	sim.transitionTarget = "menu"
	sim.found_tribe()
	eq(m["rec"]["tutorial"].size(), 0, "menu transition skips the finish")
	eq(m["rec"]["go_to"].size(), 1, "the founding itself still fires")
	sim.transitionTarget = null
	sim.found_tribe()
	eq(m["rec"]["tutorial"].size(), 1, "idle transitionTarget finishes")


# TS:1643-1652 — tutorial finish hook, pack snapshot (slice 6, genome+baby
# JSON), playerSpeciesName, ctx.save flush, ascend audio, then the go_to
# hook with the 'tribe' card. The tribe stage itself is M4 (Constraint 15).
func test_found_tribe_snapshot_and_transition() -> void:
	if FileAccess.file_exists(_path(SLOT_FT)):
		DirAccess.remove_absolute(_path(SLOT_FT))
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	_park_world_objects(m)
	# 7 pack members (slice 6), one of them a baby; a wild ent must not ride
	sim.debug_spawn_pack(7)
	sim.ents[0]["baby"] = true
	var wild: Dictionary = sim.spawn_ent(null, float(sim.px) + 300.0, float(sim.pz),
			{"size": 9.0, "diet": "herbivore", "legs": 4, "eyes": 2})
	wild["mood"] = "idle"
	ctx.player_name = "Chieftain"
	ctx.stage = "creature"
	ctx.slot = SLOT_FT
	sim.found_tribe()
	# flags snapshot
	eq(String(ctx.flags["playerSpeciesName"]), "Chieftain", "playerSpeciesName saved")
	var parsed: Variant = JSON.parse_string(String(ctx.flags["packGenomes"]))
	ok(parsed is Array, "packGenomes is a JSON array")
	if parsed is Array:
		eq(parsed.size(), 6, "pack snapshot sliced to 6")
		var babySeen := false
		var wildSeen := false
		for item in parsed:
			if bool(item["baby"]):
				babySeen = true
			if int(item["genome"]["legs"]) == 4 and float(item["genome"]["size"]) == 9.0:
				wildSeen = true
		ok(babySeen, "baby flag rides verbatim (TS foundTribe)")
		ok(not wildSeen, "wild ents never ride the snapshot")
	# ctx.save flushed the slot
	ok(FileAccess.file_exists(_path(SLOT_FT)), "ctx.save wrote the slot")
	var f := FileAccess.open(_path(SLOT_FT), FileAccess.READ)
	ok(f != null, "slot readable")
	if f != null:
		var data: Variant = JSON.parse_string(f.get_as_text())
		ok(data is Dictionary, "slot parses")
		if data is Dictionary:
			var flags: Dictionary = data["flags"]
			eq(String(flags["playerSpeciesName"]), "Chieftain", "slot carries playerSpeciesName")
			eq(String(flags["packGenomes"]), String(ctx.flags["packGenomes"]),
					"slot carries the pack snapshot")
	# hooks: tutorial finish + ascend + the tribe card
	eq(m["rec"]["tutorial"].size(), 1, "tutorial finish fired (scene gates on transitionTarget)")
	var ascend := false
	for a in m["rec"]["audio"]:
		if String(a[0]) == "ascend":
			ascend = true
	ok(ascend, "ascend audio")
	eq(m["rec"]["go_to"].size(), 1, "go_to hook fired once")
	if m["rec"]["go_to"].size() == 1:
		var call: Array = m["rec"]["go_to"][0]
		eq(String(call[0]), "tribe", "go_to targets 'tribe'")
		var card: Dictionary = call[1]
		eq(String(card["title"]), "THE FIRST FIRE", "card title")
		eq(String(card["sub"]), "Chieftain looks at the stars and decides to stay",
				"card sub")
	if FileAccess.file_exists(_path(SLOT_FT)):
		DirAccess.remove_absolute(_path(SLOT_FT))
