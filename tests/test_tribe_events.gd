# Tests for game/tribe/tribe_events.gd (the tribe chaos deck) + the scheduler
# wiring in tribe_sim.gd (update_chaos, TS:341-369) + the festival /
# festivalMirror / starShower bodies (TS:1041-1084, deferred by task 2).
# TS sources: Spore src/game/tribe/tribeEvents.ts + TribeStage.ts (frozen).
# Path-based extends + preload-by-path: class_name globals don't resolve in
# `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

const Chaos := preload("res://src/game/chaos.gd")
const RngLib := preload("res://src/core/rng.gd")
const TribeEvents := preload("res://src/game/tribe/tribe_events.gd")
const Ctx := preload("res://src/game/context.gd")
const TribeSim := preload("res://src/game/tribe/tribe_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xC0FFEE
const Z_TO_Y := 0.62


# Synthetic worlds (a real derive draws 4-6 traits — tests pin exact decks).
# temperament is set explicitly so mirror_bucket never surprises.
const W_TRAITLESS := {"seed": 31, "traits": [], "turns": [], "firedTurns": {},
		"revealed": {}, "comboFired": {}, "timers": {}, "temperament": "lean"}
const W_BOLD := {"seed": 32, "traits": [{"effects": [{"kind": "flag", "key": "raider_bold"}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "lean"}
const W_CALM := {"seed": 33, "traits": [{"effects": [
		{"kind": "num", "key": "speciation_mult", "value": 0.8}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "lean"}
const W_CRADLE := {"seed": 34, "traits": [], "turns": [], "firedTurns": {},
		"revealed": {}, "comboFired": {}, "timers": {}, "temperament": "cradle"}
const W_ALL := {"seed": 35, "traits": [{"effects": [{"kind": "flag", "key": "raider_bold"},
		{"kind": "num", "key": "speciation_mult", "value": 0.8}]}],
		"turns": [], "firedTurns": {}, "revealed": {}, "comboFired": {}, "timers": {},
		"temperament": "cradle"}


# Tribe-sim fixture: recording hooks (missing key = silent no-op in the sim).
func _mk_sim(world: Dictionary = W_TRAITLESS, seed_v: int = SEED,
		hooks_extra: Dictionary = {}) -> Dictionary:
	var ctx: Variant = Ctx.new(seed_v)
	ctx.world = world.duplicate(true)
	var rec: Dictionary = {"toasts": [], "banners": [], "floats": [], "audio": [],
			"shakes": [], "bursts": [], "spawns": [], "notes": [], "events": []}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(playtime): rec["notes"].append(playtime),
		"context_event": func(ev, data): rec["events"].append([ev, data]),
	}
	hooks.merge(hooks_extra, true)
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = TribeSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _def(deck: Array, id: String) -> Variant:
	for d in deck:
		if String(d["id"]) == id and not d.has("mirrorOf"):
			return d
	return null


func _mirror_def(deck: Array) -> Variant:
	for d in deck:
		if d.has("mirrorOf"):
			return d
	return null


func _audio_vols(rec: Dictionary, name_v: String) -> Array:
	var out: Array = []
	for a in rec["audio"]:
		if String(a[0]) == name_v:
			out.append(float(a[1]))
	return out


func _audio_count(rec: Dictionary, name_v: String) -> int:
	return _audio_vols(rec, name_v).size()


func _banners_with(rec: Dictionary, fragment: String) -> int:
	var n := 0
	for b in rec["banners"]:
		if String(b["title"]).find(fragment) >= 0:
			n += 1
	return n


# A tribesman dict built like add_tribesman, appended directly (test seam).
func _add_t(sim: Variant, x: float, z: float, role_v: String = "gather") -> Dictionary:
	sim.add_tribesman(sim.ctx.genome.duplicate(), role_v)
	var t: Dictionary = sim.tribe[sim.tribe.size() - 1]
	t["x"] = x
	t["z"] = z
	return t


func _inp(over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}
	d.merge(over, true)
	return d


# ---- the deck (tribeEvents.ts): defs + world gating ------------------------------

func test_traitless_deck_is_six_defs() -> void:
	var deck: Array = TribeEvents.make_tribe_chaos_events(W_TRAITLESS)
	eq(deck.size(), 6, "factory: traitless = 5 baseline + siege_hoard")
	var ids: Array = []
	for d in deck:
		ids.append(d["id"])
	eq(ids, ["storm", "beast", "rivalsurprise", "festival", "gift", "siege_hoard"],
			"TS deck order")
	# the sim constructor folds ctx.world into the same deck (TS:135)
	var m := _mk_sim()
	eq(m["sim"].chaos.defs.size(), 6, "sim constructor deck: traitless = 6")
	# the tribe keeps the factory gap defaults — no TS override (the creature
	# 40/0.35 tuning is per-stage)
	approx(float(m["sim"].chaos.gap), 26.0, "tribe gap stays BASE_GAP 26", 1e-12)
	approx(float(m["sim"].chaos.gap_chaos_scale), 0.45, "gap chaos scale 0.45", 1e-12)


func test_gated_defs_gate_on_the_world() -> void:
	# raider_bold: adds bold_raid AND keens rivalsurprise (spread copy — same
	# identity, wrapped weight)
	var bdeck: Array = TribeEvents.make_tribe_chaos_events(W_BOLD)
	eq(bdeck.size(), 7, "raider_bold adds bold_raid")
	var br: Dictionary = _def(bdeck, "bold_raid")
	ok(br != null, "bold_raid present")
	eq(String(br["name"]), "🏴 BOLD SAILS", "bold_raid name")
	eq(String(br["warn"]), "Sails where no sails should be…", "bold warn verbatim")
	eq(int(br["cooldown"]), 55, "bold_raid cooldown 55")
	ok(_def(TribeEvents.make_tribe_chaos_events(W_TRAITLESS), "bold_raid") == null,
			"traitless world has no bold_raid")
	var plain: Dictionary = _def(TribeEvents.make_tribe_chaos_events(W_TRAITLESS), "rivalsurprise")
	var keen: Dictionary = _def(bdeck, "rivalsurprise")
	ok(keen != null, "remapped rivalsurprise keeps its id")
	eq(String(keen["name"]), String(plain["name"]), "remap keeps the name")
	eq(String(keen["warn"]), String(plain["warn"]), "remap keeps the warn")
	eq(int(keen["duration"][0]), int(plain["duration"][0]), "remap keeps duration lo")
	eq(int(keen["duration"][1]), int(plain["duration"][1]), "remap keeps duration hi")

	var cdeck: Array = TribeEvents.make_tribe_chaos_events(W_CALM)
	eq(cdeck.size(), 7, "calm_veil (speciation_mult < 1) adds rival_festival")
	var rf: Dictionary = _def(cdeck, "rival_festival")
	ok(rf != null, "rival_festival present")
	eq(String(rf["name"]), "🎊 RIVAL FESTIVAL", "rival_festival name")
	ok(not rf.has("warn"), "rival_festival is a surprise hit (TS verbatim)")
	ok(_def(TribeEvents.make_tribe_chaos_events(W_TRAITLESS), "rival_festival") == null,
			"traitless world has no rival_festival")

	var wdeck: Array = TribeEvents.make_tribe_chaos_events(W_CRADLE)
	eq(wdeck.size(), 7, "cradle adds the festival mirror face")
	var mirrors: Array = []
	for d in wdeck:
		if d.has("mirrorOf"):
			mirrors.append(d)
	eq(mirrors.size(), 1, "exactly one mirror face")
	if mirrors.size() == 1:
		eq(String(mirrors[0]["mirrorOf"]), "festival", "mirrorOf festival")
		eq(String(mirrors[0]["id"]), "festival", "mirror keeps the base id")
		eq(String(mirrors[0]["name"]), "🔥 FESTIVAL NIGHT", "mirror keeps the base name")
		ok(not mirrors[0].has("warn"), "the mirror face is a surprise hit (TS verbatim)")
	for d in TribeEvents.make_tribe_chaos_events(W_TRAITLESS):
		ok(not d.has("mirrorOf"), "traitless lean carries no mirror face")

	eq(TribeEvents.make_tribe_chaos_events(W_ALL).size(), 9,
			"bold + calm + cradle = 9 defs")


func test_def_constants_verbatim() -> void:
	var deck: Array = TribeEvents.make_tribe_chaos_events(W_ALL)
	# id → [duration, cooldown, name, warn?]
	var want := {
		"storm": {"dur": [14.0, 22.0], "cd": 55, "name": "⚡ STORM FRONT",
				"warn": "The wind dies. Clouds boil green-black…"},
		"beast": {"dur": [25.0, 25.0], "cd": 65, "name": "🦁 A GREAT BEAST HUNTS",
				"warn": "Birds go silent in every direction…"},
		"rivalsurprise": {"dur": [10.0, 10.0], "cd": 70, "name": "🗡 SURPRISE ATTACK",
				"warn": "Drums answer from beyond the ridge…"},
		"festival": {"dur": [16.0, 22.0], "cd": 80, "name": "🔥 FESTIVAL NIGHT"},
		"gift": {"dur": [10.0, 14.0], "cd": 90, "name": "🌠 STAR SHOWER"},
		"bold_raid": {"dur": [0.1, 0.1], "cd": 55, "name": "🏴 BOLD SAILS",
				"warn": "Sails where no sails should be…"},
		"rival_festival": {"dur": [16.0, 22.0], "cd": 90, "name": "🎊 RIVAL FESTIVAL"},
		"siege_hoard": {"dur": [16.0, 24.0], "cd": 100, "name": "🏹 THE HOARD DRAWS SIEGE",
				"warn": "Torches mass beyond the ridge — they smell your stores…"},
	}
	for id in want:
		var d: Dictionary = _def(deck, id)
		ok(d != null, "def %s present" % id)
		if d == null:
			continue
		var w: Dictionary = want[id]
		var dur: Array = d["duration"]
		eq(dur.size(), 2, "%s duration pair" % id)
		approx(float(dur[0]), float(w["dur"][0]), "%s duration lo" % id, 1e-9)
		approx(float(dur[1]), float(w["dur"][1]), "%s duration hi" % id, 1e-9)
		eq(int(d["cooldown"]), int(w["cd"]), "%s cooldown" % id)
		eq(String(d["name"]), String(w["name"]), "%s name verbatim" % id)
		if w.has("warn"):
			eq(String(d["warn"]), String(w["warn"]), "%s warn verbatim" % id)
		else:
			ok(not d.has("warn"), "%s has no warn" % id)
		ok(d["weight"] is Callable, "%s weight is a Callable" % id)
		ok(d["apply"] is Callable, "%s apply is a Callable" % id)
	# the festival MIRROR face carries the same discipline
	var fm: Dictionary = _mirror_def(deck)
	ok(fm != null, "festival mirror present in the all-gates deck")
	if fm != null:
		var fmdur: Array = fm["duration"]
		approx(float(fmdur[0]), 16.0, "mirror duration lo", 1e-9)
		approx(float(fmdur[1]), 22.0, "mirror duration hi", 1e-9)
		eq(int(fm["cooldown"]), 80, "mirror cooldown 80")
		ok(fm["weight"] is Callable, "mirror weight is a Callable")
		ok(fm["apply"] is Callable, "mirror apply is a Callable")
	# storm carries a tick Callable (the periodic strike roll)
	ok(_def(deck, "storm")["tick"] is Callable, "storm carries tick")
	ok(_def(deck, "beast")["end"] is Callable, "beast carries end")
	ok(not _def(deck, "storm").has("end"), "storm has no end")


func test_weight_formulas() -> void:
	var deck: Array = TribeEvents.make_tribe_chaos_events(W_TRAITLESS)
	var c := {"chaos": 0.2, "karma": 0.5, "stageTime": 0.0}
	approx(float(_def(deck, "storm")["weight"].call(c)), 0.9, "storm 0.7+chaos", 1e-12)
	approx(float(_def(deck, "beast")["weight"].call(c)), 0.8, "beast 0.6+chaos", 1e-12)
	approx(float(_def(deck, "rivalsurprise")["weight"].call(c)), 0.45,
			"rivalsurprise 0.6 + karma*-0.3", 1e-12)
	approx(float(_def(deck, "rivalsurprise")["weight"].call({"chaos": 0.0, "karma": -1.0})),
			0.9, "rivalsurprise negative karma pushes UP", 1e-12)
	approx(float(_def(deck, "festival")["weight"].call(c)), 1.3,
			"festival 0.8 + max(0,karma)", 1e-12)
	approx(float(_def(deck, "festival")["weight"].call({"chaos": 0.0, "karma": -1.0})),
			0.8, "festival negative karma clamps to 0", 1e-12)
	approx(float(_def(deck, "gift")["weight"].call(c)), 0.5, "gift flat 0.5", 1e-12)
	# siege_hoard: the ONE dominanceSeverity formula, strict threshold
	var sh: Dictionary = _def(deck, "siege_hoard")
	approx(float(sh["weight"].call({"chaos": 0.0})), 0.0, "no dominance key -> 0", 1e-12)
	approx(float(sh["weight"].call({"dominance": 0.5})), 0.0, "below threshold -> 0", 1e-12)
	approx(float(sh["weight"].call({"dominance": 0.6})), 0.0,
			"AT the threshold -> 0 (strict >)", 1e-12)
	approx(float(sh["weight"].call({"dominance": 0.61})), 0.612,
			"just above: 0.6*severity", 1e-12)
	approx(float(sh["weight"].call({"dominance": 1.0})), 1.08,
			"capped severity x 0.6", 1e-12)
	# bold_raid: 0.5+chaos*0.6 on the gated def
	var br: Dictionary = _def(TribeEvents.make_tribe_chaos_events(W_BOLD), "bold_raid")
	approx(float(br["weight"].call(c)), 0.62, "bold_raid 0.5+chaos*0.6", 1e-12)
	# the ×1.5 keener remap wraps the ORIGINAL weight (TS:86-88)
	var keen: Dictionary = _def(TribeEvents.make_tribe_chaos_events(W_BOLD), "rivalsurprise")
	approx(float(keen["weight"].call(c)), 0.675, "keener: (0.6+karma*-0.3)*1.5", 1e-12)
	approx(float(keen["weight"].call({"chaos": 0.0, "karma": -1.0})), 1.35,
			"keener multiplies the negative-karma weight too", 1e-12)
	# rival_festival: (0.7 + max(0,karma)*0.5) * (bless ? 1.3 : 1)
	var rf: Dictionary = _def(TribeEvents.make_tribe_chaos_events(W_CALM), "rival_festival")
	approx(float(rf["weight"].call(c)), 0.95, "rival_festival 0.7+karma*0.5", 1e-12)
	var bless := {"chaos": 0.2, "karma": 0.5, "mood": "bless"}
	approx(float(rf["weight"].call(bless)), 1.235, "rival_festival bless x1.3", 1e-12)
	approx(float(rf["weight"].call({"chaos": 0.0, "karma": -1.0, "mood": "bless"})),
			0.91, "rival_festival negative karma clamps, bless still leans", 1e-12)
	# festival mirror: 0.9 only when the queued mirrors include festival
	var fm: Dictionary = _mirror_def(TribeEvents.make_tribe_chaos_events(W_CRADLE))
	approx(float(fm["weight"].call({"mirrors": ["festival"]})), 0.9,
			"mirror queued 0.9", 1e-12)
	approx(float(fm["weight"].call({"mirrors": []})), 0.0, "mirror unqueued 0", 1e-12)
	approx(float(fm["weight"].call({})), 0.0, "missing mirrors key reads 0", 1e-12)


# ---- the storm's two former Math.random sites (divergence replay pins) -----------

func test_storm_apply_divergence_pin() -> void:
	# DIVERGENCE (tribeEvents.ts:20): TS `2 + Math.random() * 4` — the port
	# draws the delay from the deck rng inside apply. Replay both draws from a
	# pinned seed: native-vs-native bit-exact (TS was unseeded there).
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "storm")
	def["apply"].call(sim, RngLib.new(7))
	eq(_audio_vols(rec, "quake"), [0.6], "quake 0.6")
	eq(sim.timers.size(), 1, "one delayed lightning strike")
	var want: float = 2.0 + RngLib.new(7).next() * 4.0
	approx(float(sim.timers[0]["left"]), want, "delay = 2 + deck_rng.next()*4", 0.0)
	ok(want >= 2.0 and want < 6.0, "delay domain [2, 6)")
	eq(sim.fires.size(), 0, "nothing burns yet")
	sim.timers[0]["fn"].call()
	ok(_audio_count(rec, "zap") > 0, "the strike fires lightning (zap)")


func test_storm_tick_roll_pin() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var def: Dictionary = _def(sim.chaos.defs, "storm")
	# elapsed <= 6: NO draw at all (the TS && short-circuits, TS-true)
	var s0: int = sim.rng.state()
	def["tick"].call(sim, 6.0, DT)
	eq(sim.rng.state(), s0, "no roll while elapsed <= 6")
	eq(_audio_count(rec, "zap"), 0, "no strike while elapsed <= 6")
	# find deterministic states (no rng in the scan): first calm and first
	# striking first-draw states
	var strike_state := -1
	var calm_state := -1
	for i in range(1, 100000):
		var rr: Variant = RngLib.new(i)
		if rr.next() < 0.01:
			if strike_state < 0:
				strike_state = i
		elif calm_state < 0:
			calm_state = i
		if strike_state > 0 and calm_state > 0:
			break
	ok(strike_state > 0 and calm_state > 0, "scan found both branches")
	# draw-count pin on a known-calm state: exactly one stage-rng draw
	sim.rng.set_state(calm_state)
	var parallel: Variant = RngLib.new(calm_state)
	def["tick"].call(sim, 7.0, DT)
	var roll: float = parallel.next()  # replay the tick's single draw
	eq(sim.rng.state(), parallel.state(), "the tick drew exactly one stage-rng draw")
	ok(roll >= 0.01, "the calm state rolled >= 0.01")
	eq(_audio_count(rec, "zap"), 0, "roll >= 0.01 stays quiet")
	# the strike branch actually strikes
	sim.rng.set_state(strike_state)
	def["tick"].call(sim, 7.0, DT)
	ok(_audio_count(rec, "zap") > 0, "roll < 0.01 strikes")
	eq(rec["shakes"][-1], [6.0, 0.4], "the strike shakes the cam (TS:991)")


# ---- the raid-refuse branches (tribeEvents.ts:50/102) -----------------------------

func test_rivalsurprise_refuse_keeps_warning_honest() -> void:
	# peaceful + hutless: raidsBlocked() true — apply refuses (no alarm with
	# no raid); the scheduler still opened the warn phase BEFORE apply, which
	# is TS-verbatim (the def refuses INSIDE apply)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	m["ctx"].difficulty = "peaceful"
	sim.huts.clear()
	var rs: Dictionary = _def(sim.chaos.defs, "rivalsurprise")
	rs["apply"].call(sim, sim.rng)
	eq(sim.rivalWarriors.size(), 0, "refuse: no raiders")
	eq(bool(sim.raidActive), false, "refuse: raidActive untouched")
	eq(_audio_vols(rec, "alarm"), [], "no alarm with no raid")
	eq(_banners_with(rec, "RAIDS"), 0, "no raid banner")
	# unblocking flips it live: launch alarm 0.9 + the event's own alarm 1.0
	sim.huts.append({"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0,
			"pop": 0.0, "buildT": 0.0})
	rs["apply"].call(sim, sim.rng)
	ok(sim.rivalWarriors.size() > 0, "launches once a hut stands")
	eq(bool(sim.raidActive), true, "raidActive true")
	eq(_audio_vols(rec, "alarm"), [0.9, 1.0], "launch alarm 0.9 then event alarm 1.0")


func test_bold_raid_refuse_and_launch() -> void:
	var m := _mk_sim(W_BOLD)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	m["ctx"].difficulty = "peaceful"
	sim.huts.clear()
	var br: Dictionary = _def(sim.chaos.defs, "bold_raid")
	br["apply"].call(sim, sim.rng)
	eq(sim.rivalWarriors.size(), 0, "same refuse as rivalsurprise")
	eq(_audio_vols(rec, "alarm"), [], "no alarm")
	sim.huts.append({"x": 0.0, "z": 80.0, "hp": 100.0, "maxHp": 100.0,
			"pop": 0.0, "buildT": 0.0})
	br["apply"].call(sim, sim.rng)
	ok(sim.rivalWarriors.size() > 0, "bold raid sails once a hut stands")
	eq(_audio_vols(rec, "alarm"), [0.9, 0.9], "launch alarm 0.9 then bold alarm 0.9")


func test_siege_hoard_two_waves_via_timers() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var sh: Dictionary = _def(sim.chaos.defs, "siege_hoard")
	sh["apply"].call(sim, sim.rng)
	var wave1: int = sim.rivalWarriors.size()
	ok(wave1 > 0, "first wave marches")
	eq(_audio_vols(rec, "alarm"), [0.9, 1.0], "launch alarm + siege alarm 1.0")
	eq(sim.timers.size(), 1, "the second wave rides a stage timer")
	eq(float(sim.timers[0]["left"]), 9.0, "wave 2 delay 9 (TS:137)")
	sim.timers[0]["fn"].call()
	ok(sim.rivalWarriors.size() > wave1, "second wave pressed while the hoard is fat")


# ---- the festival / festivalMirror / starShower bodies (TS:1041-1084) -------------

func test_festival_body() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	m["ctx"].karma = 0.0
	sim.food = 50.0
	var t: Dictionary = _add_t(sim, 10.0, 60.0)
	t["hp"] = 3.0
	t["mood"] = "idle"
	var dna0: int = int(m["ctx"].dna)
	var st: int = sim.rng.state()
	sim.festival()
	approx(float(m["ctx"].karma), 0.08, "karma +0.08", 1e-12)
	approx(float(sim.food), 30.0, "food -20", 1e-12)
	approx(float(t["hp"]), float(t["maxHp"]), "the feast heals to full")
	eq(String(t["mood"]), "happy", "mood happy")
	eq(int(m["ctx"].dna), dna0, "festival pays no DNA")
	eq(sim.fires.size(), 3, "3 bonfires")
	for f in sim.fires:
		eq(float(f["ttl"]), 12.0, "bonfire ttl 12")
		eq(float(f["spread"]), 999.0, "bonfires never spread (999)")
	eq(String(rec["toasts"][-1][0]), "Drums all night! The tribe is one.", "toast verbatim")
	eq(String(rec["toasts"][-1][1]), "good", "toast good")
	# draw order pin: per fire x (±80) then z (±40) around huts[0] — a parallel
	# stream replays the 6 draws (festival's only rng consumption); the sim's
	# starting hut anchors at (0, 80) so the z replay carries the hz offset
	var pr: Variant = RngLib.new(st)
	for i in 3:
		approx(float(sim.fires[i]["x"]), pr.range(-80.0, 80.0), "fire %d x draw" % i, 0.0)
		approx(float(sim.fires[i]["z"]), 80.0 + pr.range(-40.0, 40.0), "fire %d z draw" % i, 0.0)


func test_festival_body_hutless_falls_back_to_origin() -> void:
	# TS:1046-1047 `this.huts[0]?.x ?? 0` — the hutless fallback anchors the
	# bonfires at (0, 80)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.huts.clear()
	sim.festival()
	eq(sim.fires.size(), 3, "bonfires still land")
	for f in sim.fires:
		ok(absf(float(f["x"])) <= 80.0 + 1e-6, "x around 0 (the ?? fallback)")
		ok(absf(float(f["z"]) - 80.0) <= 40.0 + 1e-6, "z around 80 (the ?? fallback)")


func test_festival_mirror_body() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	m["ctx"].karma = 0.0
	sim.food = 50.0
	var t: Dictionary = _add_t(sim, 10.0, 60.0)
	t["hp"] = 3.0
	t["mood"] = "idle"
	var karma0: float = float(m["ctx"].karma)
	var st: int = sim.rng.state()
	sim.festival_mirror()
	approx(float(sim.food), 30.0, "food -20 (the cost stays)", 1e-12)
	eq(String(t["mood"]), "afraid", "the ONE inverted rule: mood afraid")
	approx(float(t["hp"]), 3.0, "NO heal (the mirror drops it, TS:1057)")
	approx(float(m["ctx"].karma), karma0, "NO karma (the mirror drops it)")
	eq(sim.fires.size(), 3, "3 spread-999 fires stay")
	for f in sim.fires:
		eq(float(f["ttl"]), 12.0, "bonfire ttl 12")
		eq(float(f["spread"]), 999.0, "bonfires never spread (999)")
	eq(String(rec["toasts"][-1][0]), "The feast sours — the tribe bickers all night.",
			"toast verbatim")
	eq(String(rec["toasts"][-1][1]), "bad", "toast bad")
	# the fire draws are IDENTICAL to festival's (x then z, ±80/±40 around
	# the starting hut's (0, 80) anchor)
	var pr: Variant = RngLib.new(st)
	for i in 3:
		approx(float(sim.fires[i]["x"]), pr.range(-80.0, 80.0), "fire %d x draw" % i, 0.0)
		approx(float(sim.fires[i]["z"]), 80.0 + pr.range(-40.0, 40.0), "fire %d z draw" % i, 0.0)


func test_star_shower_body() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	var dna0: int = int(m["ctx"].dna)
	sim.star_shower()
	eq(int(m["ctx"].dna), dna0 + 80, "DNA +80")
	eq(rec["floats"].size(), 1, "float_world fired (TS:1082)")
	if rec["floats"].size() == 1:
		var fl: Array = rec["floats"][0]
		approx(float(fl[0]), 0.0, "float x = px", 1e-12)
		approx(float(fl[1]), 60.0 * Z_TO_Y - 60.0, "float y = pz*Z_TO_Y - 60", 1e-12)
		eq(String(fl[2]), "+80 DNA", "float text")
		eq(String(fl[3]), "#c9a4ff", "float color")
		eq(float(fl[4]), 16.0, "float size 16")
	eq(String(rec["toasts"][-1][0]), "Falling stars seed the sky with DNA.", "toast verbatim")
	eq(String(rec["toasts"][-1][1]), "reward", "toast reward")
	eq(String(rec["toasts"][-1][2]), "🌠", "toast icon")


# ---- the scheduler wiring (TribeStage.ts:341-369) ---------------------------------

func test_wealth_pressure_dominance_input() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	approx(float(sim.wealth_pressure()), 90.0 / 500.0, "min(1,(food+wood)/500)", 1e-12)
	sim.food = 300.0
	sim.wood = 250.0
	approx(float(sim.wealth_pressure()), 1.0, "caps at 1", 1e-12)
	# TS Math.min has NO lower clamp — the port stays verbatim; the strict
	# weight gate (dominance > 0.6) is what keeps negatives harmless
	sim.food = -5000.0
	sim.wood = 30.0
	approx(float(sim.wealth_pressure()), (-5000.0 + 30.0) / 500.0,
			"no extra clamp (TS Math.min only)", 1e-12)
	approx(float(_def(sim.chaos.defs, "siege_hoard")["weight"].call(
			{"dominance": sim.wealth_pressure()})), 0.0,
			"negative dominance never passes the strict gate", 1e-12)


func test_update_chaos_no_warn_natural_spawn() -> void:
	# the natural path on a no-warn def (festival): apply runs, NO onApply
	# banner and no storyteller note (TS chaos.ts:146 — the surprise-hit rule
	# the cell/creature decks pin)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	m["ctx"].karma = 0.0
	sim.food = 50.0
	sim.chaos = Chaos.new(RngLib.new(6), [_def(sim.chaos.defs, "festival")])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.is_active("festival"), "festival live (no warn -> immediate)")
	eq(rec["banners"], [], "no-warn natural spawn: no apply banner")
	eq(rec["notes"], [], "no storyteller note on a natural no-warn spawn")
	eq(sim.fires.size(), 3, "the festival body ran")


func test_update_chaos_warn_then_apply() -> void:
	# warned def (storm): onWarn banner at spawn (danger ttl 2.4 + alarm 0.5);
	# the conversion applies + onApply banner (kind chaos) + addChaos(0.03) +
	# storyteller noteChaosEvent
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.chaos = Chaos.new(RngLib.new(5), [_def(sim.chaos.defs, "storm")])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.warn_remaining() > 0.0, "storm in warn phase")
	var wb: Array = []
	for b in rec["banners"]:
		if String(b.get("title", "")) == "The wind dies. Clouds boil green-black…":
			wb.append(b)
	eq(wb.size(), 1, "onWarn banner carries the static warn")
	if wb.size() == 1:
		eq(String(wb[0]["kind"]), "danger", "warn kind danger")
		eq(float(wb[0]["ttl"]), 2.4, "warn ttl 2.4")
	eq(_audio_vols(rec, "alarm"), [0.5], "warn alarm 0.5")
	eq(sim.timers.size(), 0, "no strike while warned")
	sim.update_chaos(3.0)  # the 2.5 window closes -> conversion
	ok(sim.chaos.is_active("storm"), "storm converts to active")
	eq(sim.timers.size(), 1, "apply scheduled the first strike")
	eq(_banners_with(rec, "STORM FRONT"), 1, "onApply banner carries the def name")
	approx(float(m["ctx"].chaos), 0.15 + 0.03, "ctx.addChaos(0.03)", 1e-12)
	eq(rec["notes"].size(), 1, "storyteller noteChaosEvent fired on apply")


func test_update_chaos_storyteller_hooks_feed_the_ctx() -> void:
	# the hook seam: gap_bias scales the gap, mood feeds the weight ctx
	# (rival_festival reads bless), warn_scale scales the warn window
	var m := _mk_sim(W_CALM, SEED, {
		"get_gap_bias": func() -> float: return 0.5,
		"get_mood": func() -> String: return "bless",
		"get_warn_scale": func() -> float: return 2.0,
	})
	var sim: Variant = m["sim"]
	# single warned def with warnS unset: window = 2.5 * warnScale (the spawn
	# frame does not tick the fresh entry — it decrements from next frame)
	sim.chaos = Chaos.new(RngLib.new(5), [_def(sim.chaos.defs, "storm")])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	approx(float(sim.chaos.warn_remaining()), 5.0,
			"window = 2.5 * warnScale 2.0", 1e-12)
	# the mood rode the ctx: a bless world sharpens rival_festival's weight
	var rf: Dictionary = _def(TribeEvents.make_tribe_chaos_events(W_CALM), "rival_festival")
	approx(float(rf["weight"].call({"chaos": 0.0, "karma": 0.0, "mood": "bless"})),
			0.91, "bless ctx reaches the weight formula", 1e-12)


func test_update_chaos_beast_lifecycle_end_hook() -> void:
	# beast WARNS ("Birds go silent…"): warn phase spawns nothing; the
	# conversion applies (spawn + alarm 0.8); end despawns; onEnd still rolls
	# the mirror ledger (no-op for non-festival ids — no draw)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.chaos = Chaos.new(RngLib.new(5), [_def(sim.chaos.defs, "beast")])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.warn_remaining() > 0.0, "beast in warn phase")
	eq(sim.beast, null, "no beast while warned")
	sim.update_chaos(3.0)  # the 2.5 window closes -> apply
	ok(sim.beast != null, "the beast walks")
	ok(sim.chaos.is_active("beast"), "beast active")
	eq(_audio_vols(rec, "alarm"), [0.5, 0.8], "warn alarm 0.5 then beast alarm 0.8")
	sim.update_chaos(30.0)  # duration [25,25] elapses -> end -> despawn
	eq(sim.beast, null, "end despawned the beast")
	ok(_toasted(rec, "wanders away"), "despawn toast")


func _toasted(rec: Dictionary, fragment: String) -> bool:
	for t in rec["toasts"]:
		if String(t[0]).find(fragment) >= 0:
			return true
	return false


func test_update_calls_chaos() -> void:
	# the sim's update() runs the scheduler at its TS position (TS:342) —
	# gap 0 makes the first frame spawn (warn or immediate) from the full
	# traitless deck; the raid clock (raidTimer 75) stays quiet meanwhile
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	sim.chaos.gap = 0.0
	sim.update(DT, _inp())
	var spawned: bool = sim.chaos.active_events().size() > 0 \
			or sim.chaos.warn_remaining() > 0.0
	ok(spawned, "update() drove the scheduler (a def spawned or warned)")
	eq(sim.rivalWarriors.size(), 0, "the raid clock did not fire")


func test_has_active_chaos_phase_gate() -> void:
	# TS hasActiveChaos counts the ACTIVE phase only — a warn-phase event
	# does not count (TS:1075-1077)
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	eq(bool(sim.has_active_chaos()), false, "empty scheduler: false")
	sim.chaos = Chaos.new(RngLib.new(5), [_def(sim.chaos.defs, "storm")])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	eq(bool(sim.has_active_chaos()), false, "warn phase does not count")
	sim.update_chaos(3.0)
	eq(bool(sim.has_active_chaos()), true, "active phase counts")


# ---- the mirror-once flow (the task-5 test shape) ----------------------------------

func test_mirror_once_flow_tribe() -> void:
	# The base festival survives -> the onEnd roll queues the mirror return ->
	# the mirror face fires. The mirror face is a NO-WARN surprise hit —
	# spawn() runs apply but fires NO onApply hook, so the queue entry
	# SURVIVES and the fired-ledger stays empty (the once-guard only engages
	# on the warn-conversion path; cooldown 80 gates the re-fire).
	var m := _mk_sim(W_CRADLE)
	var sim: Variant = m["sim"]
	var rec: Dictionary = m["rec"]
	sim.food = 50.0
	var base: Dictionary = _def(sim.chaos.defs, "festival")
	sim.chaos = Chaos.new(RngLib.new(6), [base])
	sim.chaos.gap = 0.0
	sim.update_chaos(1.0)
	ok(sim.chaos.is_active("festival"), "base festival live (no warn -> immediate)")
	eq(rec["banners"], [], "no-warn natural spawn: no apply banner (TS chaos.ts:146)")
	sim.update_chaos(30.0)  # festival ends -> onEnd -> maybe_queue(rng, festival, festival)
	var guard := 0
	while sim.mirrorLedger.queued().is_empty() and guard < 200:
		sim.mirrorLedger.maybe_queue(sim.rng, "festival", "festival")
		guard += 1
	ok(guard < 200, "mirror return queued")
	eq(sim.mirrorLedger.has_fired("festival"), false, "nothing fired yet")
	var mirror: Array = TribeEvents.make_tribe_chaos_events(m["ctx"].world).filter(
			func(d): return d.has("mirrorOf"))
	eq(mirror.size(), 1, "the cradle world carries the mirror face")
	sim.chaos = Chaos.new(RngLib.new(7), mirror)
	sim.chaos.gap = 0.0
	sim.food = 50.0
	sim.update_chaos(1.0)
	ok(sim.chaos.is_active("festival"), "mirror face live (queued -> weight 0.9)")
	approx(float(sim.food), 30.0, "the food cost stays", 1e-12)
	var sour := false
	for t in rec["toasts"]:
		if String(t[0]) == "The feast sours — the tribe bickers all night.":
			sour = true
	ok(sour, "the mirror body ran (bad toast)")
	# the no-warn spawn fired no hooks: the queue entry survives, the ledger
	# stays empty — TS-verbatim (contrast a warned conversion, which DOES
	# fire onApply and would clear the queue via onFired)
	eq(sim.mirrorLedger.queued(), ["festival"], "queue entry survived")
	eq(sim.mirrorLedger.has_fired("festival"), false, "fired-ledger stays empty")
