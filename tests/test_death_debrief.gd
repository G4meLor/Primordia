# Task 12 (R4) — death debrief: cause + DNA lost + one counter-tip.
#   - a 1.4s display-only overlay inside the existing death fades (space has
#     no fade — its window is the component's own 1.4s age), drawn by the
#     stages that already draw death overlays; content = cause line / −N DNA
#     (omitted when the path bills nothing) / one tip from the registry.
#   - CAUSE RECORDING IS UI-SIDE BY RULING (controller preflight): the sims
#     pass the killer/source to the stage layer at the death instant through
#     ONE hook (`death_debrief`, [cause_id, killer, dna_lost] with dna < 0
#     meaning "not billed yet") and store NOTHING in sim state — the cell A-B
#     dump sha (ea35920b…) must stay stable. Payload convention:
#       cause_id != ""  → note (a killing blow; cell/creature carry the
#                         killer's SPECIES ID — the stage resolves the
#                         bestiary name; tribe/space pass "")
#       cause_id == ""  → commit (the death handler; dna_lost = the bill the
#                         path already computes)
#   - DEATH-PATH ENUMERATION (the registry count pins this list — one cause
#     per site where gated player damage can land the fatal blow; the civ sim
#     has NO player-death path: city hp clamps stay ≥ 5 and no death/respawn
#     exists, so it contributes no cause):
#       cell_sim.gd     :707  NPC bite (php -= dmg2, invuln-gated)  → cell_bite
#       cell_sim.gd     :1544 meteor blast (php -= 45·…, invuln)    → cell_meteor
#       creature_sim.gd :888  NPC bite (php -= dmg2, invuln-gated)  → creature_bite
#       creature_sim.gd :945  lava hazard dps (volcano)             → creature_lava
#       creature_sim.gd :1524 meteor scorch                         → creature_meteor
#       tribe_sim.gd    :733  raid roll (deathFade 0.0001 +         → tribe_raiders
#                             lastDeathCause "raiders cut you down")
#       tribe_sim.gd    :1279 beast gore roll (lastDeathCause       → tribe_beast
#                             "the great beast gored you")
#       space_sim.gd    :691  sun danger dps                        → space_sun
#       space_sim.gd    :761  black-hole core dps                   → space_blackhole
#       space_sim.gd    :799  pirate siege dps                      → space_pirates
#     Commits: cell_sim :439-area handle_death, creature_sim :731-area
#     handle_death, tribe_sim :613-area handle_chief_death, space_sim :897-area
#     ship-death block. 10 causes total; the test pins exactly this list.
extends "res://tests/test_base.gd"

const DeathDebrief := preload("res://src/ui/death_debrief.gd")
const I18nLib := preload("res://src/core/i18n.gd")
const Ctx := preload("res://src/game/context.gd")
const CellSim := preload("res://src/game/cell/cell_sim.gd")

const DT := 1.0 / 60.0
const SCRATCH := "user://test_death_debrief_settings.cfg"

## The pinned registry — ORDER-FREE list of every death cause (see the
## header enumeration; count == the gated death sites across the 5 sims).
const EXPECTED_CAUSES := [
	"cell_bite", "cell_meteor",
	"creature_bite", "creature_lava", "creature_meteor",
	"tribe_raiders", "tribe_beast",
	"space_sun", "space_blackhole", "space_pirates",
]


# ---- registry completeness -----------------------------------------------------

func test_registry_covers_every_death_path() -> void:
	var reg: Dictionary = DeathDebrief.CAUSES
	eq(reg.size(), EXPECTED_CAUSES.size(),
			"registry count == enumerated death sites (see the header list)")
	for id_v in EXPECTED_CAUSES:
		ok(reg.has(id_v), "registry has cause '%s'" % id_v)
	for id_v: String in reg:
		var entry: Dictionary = reg[id_v]
		ok(entry.has("text") and String(entry["text"]) != "",
				"cause '%s' has a text key" % id_v)
		ok(entry.has("tip") and String(entry["tip"]) != "",
				"cause '%s' has exactly one tip" % id_v)
		if String(entry["text"]).contains("%s"):
			ok(entry.has("no_killer") and String(entry["no_killer"]) != "",
					"template cause '%s' has a no-killer fallback line" % id_v)


func test_registry_keys_ship_in_vi_csv() -> void:
	var i18n: Variant = I18nLib.new(SCRATCH)
	var reg: Dictionary = DeathDebrief.CAUSES
	for id_v: String in reg:
		var entry: Dictionary = reg[id_v]
		ok(i18n.vi_has(String(entry["text"])),
				"vi.csv ships the cause line for '%s'" % id_v)
		ok(i18n.vi_has(String(entry["tip"])),
				"vi.csv ships the tip for '%s'" % id_v)
		if entry.has("no_killer"):
			ok(i18n.vi_has(String(entry["no_killer"])),
					"vi.csv ships the no-killer line for '%s'" % id_v)
	ok(i18n.vi_has("−%d DNA"), "vi.csv ships the DNA-loss line")


# ---- debrief build (pure) ------------------------------------------------------

func test_build_lines_killer_template_and_order() -> void:
	var d: Variant = DeathDebrief.new()
	# NPC kill: the killer name interpolates OUTSIDE tr (the template goes
	# through tr first — the QC r3 F6 precedent); EN headless returns the keys
	var lines: Array[String] = d.build_lines("cell_bite", 25, "Spine Snapper")
	eq(lines.size(), 3, "a billed bite death builds cause + DNA + tip")
	eq(lines[0], "The Spine Snapper got you", "killer name substituted into the template")
	eq(lines[1], "−25 DNA", "DNA line uses the minus-glyph format verbatim")
	eq(lines[2], String(DeathDebrief.CAUSES["cell_bite"]["tip"]), "tip comes last, from the registry")
	# a creature bite shares the template but carries its own tip
	var lines2: Array[String] = d.build_lines("creature_bite", 30, "Fang Herd")
	eq(lines2[0], "The Fang Herd got you", "creature bite uses the same template shape")


func test_build_lines_generic_dna_omission_and_unknown() -> void:
	var d: Variant = DeathDebrief.new()
	# NPC-killed but the bestiary name did not resolve → the generic line
	var lines: Array[String] = d.build_lines("cell_bite", 12, "")
	eq(lines[0], String(DeathDebrief.CAUSES["cell_bite"]["no_killer"]),
			"empty killer falls back to the generic cause line")
	eq(lines.size(), 3, "generic bite still carries the DNA + tip lines")
	# unbilled deaths (post-ending space ship death, a sub-1 DNA round-down)
	# omit the DNA line entirely — 2 lines, cause then tip
	var no_dna: Array[String] = d.build_lines("space_sun", 0, "")
	eq(no_dna.size(), 2, "dna_lost 0 omits the DNA line (post-ending ship death)")
	eq(no_dna[0], String(DeathDebrief.CAUSES["space_sun"]["text"]), "cause line unchanged")
	eq(no_dna[1], String(DeathDebrief.CAUSES["space_sun"]["tip"]), "tip follows the cause directly")
	var neg: Array[String] = d.build_lines("tribe_raiders", -1, "")
	eq(neg.size(), 2, "a negative dna_lost also omits the DNA line")
	# reused toast keys: the tribe causes ARE the existing lastDeathCause keys
	eq(String(DeathDebrief.CAUSES["tribe_raiders"]["text"]), "raiders cut you down",
			"tribe_raiders reuses the sim's lastDeathCause key verbatim")
	eq(String(DeathDebrief.CAUSES["tribe_beast"]["text"]), "the great beast gored you",
			"tribe_beast reuses the sim's lastDeathCause key verbatim")
	# an unknown id (a wiring bug) builds nothing — draw then shows no overlay
	eq(d.build_lines("nonexistent_cause", 25, "X").size(), 0,
			"unknown cause id builds no lines")


# ---- component window (pending → commit → age-out) -----------------------------

func test_window_pending_commit_and_age_out() -> void:
	var d: Variant = DeathDebrief.new()
	ok(not d.active(), "fresh component is idle")
	# a note alone starts nothing — the window opens only at the death commit
	d.note("cell_bite", "Spine Snapper")
	ok(not d.active(), "a killing-blow note holds pending without opening the window")
	# the commit (the death handler's DNA bill) starts the 1.4s window
	d.commit(25)
	ok(d.active(), "commit opens the debrief window")
	# half the window later the overlay still shows
	d.tick(0.7)
	ok(d.active(), "the window survives 0.7s of the 1.4s budget")
	d.tick(0.71)
	ok(not d.active(), "the window dismisses itself after 1.4s (before the 1.6s respawn)")
	# a re-death repeats cleanly
	d.note("tribe_beast", "")
	d.commit(9)
	ok(d.active(), "a second death re-arms the window")
	# a note arriving while a window is live is ignored (no mid-fade rewrite)
	d.note("space_pirates", "")
	d.commit(0)  # unbilled commit (post-ending shape) — still closes cleanly
	d.tick(1.5)
	ok(not d.active(), "an unbilled death also expires after its window")


func test_commit_without_note_stays_silent_and_reset_clears() -> void:
	var d: Variant = DeathDebrief.new()
	# defensive: the death handler firing without a killing-blow note (a
	# wiring gap) must not open a window on an unknown cause
	d.commit(25)
	ok(not d.active(), "commit without a pending note opens nothing")
	# reset clears pending + a live window (stage on_enter — no stale debrief
	# across a quit-to-title + CONTINUE round-trip)
	d.note("cell_meteor", "")
	d.commit(40)
	ok(d.active(), "precondition: window live before reset")
	d.reset()
	ok(not d.active(), "reset dismisses a live window")
	d.tick(0.1)
	ok(not d.active(), "reset leaves nothing to age back in")


# ---- record-then-fade through the REAL cell death path -------------------------

func _mk_sim() -> Dictionary:
	var ctx: Variant = Ctx.new(0xC0FFEE)
	var rec: Dictionary = {
		"toasts": [], "banners": [], "floats": [], "audio": [], "shakes": [],
		"bursts": [], "spawns": [], "notes": [], "events": [], "debrief": [],
		"pointer": 0, "shore": 0, "saves": 0,
	}
	var hooks: Dictionary = {
		"hud_toast": func(text, kind, icon): rec["toasts"].append([text, kind, icon]),
		"hud_banner": func(data): rec["banners"].append(data),
		"hud_float_world": func(x, y, text, color, size): rec["floats"].append([x, y, text, color, size]),
		"audio_play": func(n, v, p): rec["audio"].append([n, v, p]),
		"cam_shake": func(mag, dur): rec["shakes"].append([mag, dur]),
		"fx_burst": func(x, y, n, opts): rec["bursts"].append([x, y, n, opts]),
		"fx_spawn": func(opts): rec["spawns"].append(opts),
		"storyteller_note_chaos_event": func(playtime): rec["notes"].append(playtime),
		"set_cursor_pointer": func(): rec["pointer"] += 1,
		"context_event": func(ev, data): rec["events"].append([ev, data]),
		"shore_travel": func(): rec["shore"] += 1,
		"game_save_all": func(): rec["saves"] += 1,
		"death_debrief": func(cause, killer, dna): rec["debrief"].append([cause, killer, dna]),
	}
	var rng: Variant = ctx.rng.branch()
	var sim: Variant = CellSim.new(ctx, rng, hooks)
	return {"sim": sim, "ctx": ctx, "rec": rec}


func _inp() -> Dictionary:
	return {
		"mx": 0.0, "my": 0.0, "wx": 0.0, "wy": 0.0,
		"down": false, "clicked": false, "take_click": false,
		"keys_held": [], "keys_pressed": [],
	}


func test_cell_bite_death_records_cause_then_fades() -> void:
	var m := _mk_sim()
	var sim: Variant = m["sim"]
	var ctx: Variant = m["ctx"]
	var rec: Dictionary = m["rec"]
	# a tanky NPC jaw cell overlapping the player; one bite at php 5 kills
	sim.invuln = 0.0
	var sp: Dictionary = sim.eco.living()[0]
	var g: Dictionary = sp["genome"].duplicate()
	g["jaw"] = 5
	g["size"] = 1.5
	g["diet"] = "carnivore"
	var killer: Dictionary = sim.spawn_ent(sp, sim.px + 4.0, sim.py, g)
	killer["hp"] = 400.0  # outlives the player's reply bite
	sim.php = 5.0
	var dna0: int = ctx.dna
	var lost := floori(float(dna0) * 0.12 + 0.5)
	sim.update(DT, _inp())
	# the killing blow RECORDS (the note rides the bite site) and the death
	# handler COMMITS the bill — both this tick, note first (record-then-fade)
	eq(rec["debrief"].size(), 2, "one killing blow → exactly a note + a commit")
	if rec["debrief"].size() == 2:
		eq(rec["debrief"][0][0], "cell_bite", "the note names the bite cause")
		eq(rec["debrief"][0][1], String(sp["id"]),
				"the note carries the killer's species id (bestiary resolution is stage-side)")
		eq(int(rec["debrief"][0][2]), -1, "the note's dna is unbilled (-1)")
		eq(rec["debrief"][1][0], "", "the commit carries no cause (the pending note supplies it)")
		eq(int(rec["debrief"][1][2]), lost, "the commit bills exactly the path's round(12%) loss")
	eq(ctx.dna, dna0 - lost, "the DNA bill actually landed on ctx")
	eq(rec["events"].size(), 1, "the playerDeath storyteller signal still fires")
	# the fade runs to respawn; neither the during-fade corpse bites nor the
	# respawn re-record — the debrief stays a one-shot per death
	for i in 110:
		sim.update(DT, _inp())
	eq(rec["debrief"].size(), 2, "no re-record through the fade or the respawn")
	# the ruling's contract: the sim stores NOTHING — no cause fields leak
	# into sim state (the cell A-B dump sha stays stable)
	ok(sim.get("death_cause") == null and sim.get("death_dna_lost") == null
			and sim.get("lastDeathCause") == null,
			"the sim gains no death-cause state (UI-side recording by ruling)")
