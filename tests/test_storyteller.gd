# Path-based extends (not `extends TestBase`): global class_name resolution needs
# the editor's script class cache, which doesn't exist in `-s` mode on a fresh clone.
extends "res://tests/test_base.gd"

# Same -s-mode constraint: resolve scripts by path.
const Storyteller := preload("res://src/game/storyteller.gd")
const Fixtures := preload("res://tests/fixtures.gd")

# TS world.test.ts "Storyteller" block base signal set (camelCase there,
# snake_case here — see KEY_MAP below).
const BASE := {
	"chaos": 0.2, "karma": 0.0, "eco_health": 0.7,
	"dna_rate": 5.0, "deaths_in_stage": 0.0, "stage_time": 100.0,
}

# Fixture signal keys are TS camelCase; the port's signal Dictionary uses
# snake_case (stats.gd mapping convention).
const KEY_MAP := {
	"chaos": "chaos", "ecoHealth": "eco_health", "karma": "karma",
	"dnaRate": "dna_rate", "deathsInStage": "deaths_in_stage", "stageTime": "stage_time",
}


func _signals(over: Dictionary) -> Dictionary:
	var s: Dictionary = BASE.duplicate()
	s.merge(over, true)
	return s


func _fixture_signals(raw: Dictionary) -> Dictionary:
	var out := {}
	for k in KEY_MAP:
		if raw.has(k):
			out[KEY_MAP[k]] = raw[k]
	return out


# --- fixture walk -----------------------------------------------------------


func test_fixture_walk_mood_timeline() -> void:
	# One fresh Storyteller (mood test, temperament none), update(1, signals)
	# x 120 ticks across four 30-tick phases; every tick pins mood AND the
	# hysteresis hold AFTER the update (see fixtures.README.md).
	var data := Fixtures.load_json("storyteller_walk")
	ok(not data.is_empty(), "fixture storyteller_walk.json loads")
	var dt: float = float(data.get("dt", 1.0))
	var timeline: Array = data.get("timeline", [])
	eq(timeline.size(), int(data.get("ticks", 0)), "timeline covers the documented tick count")
	var st: Variant = Storyteller.new()
	for entry in timeline:
		var t: int = int(entry["t"])
		st.update(dt, _fixture_signals(entry["signals"]))
		eq(st.mood, entry["mood"], "walk t=%d mood" % t)
		# fixture floats carry <=1 ulp Godot-parse noise vs node (see fixtures.gd)
		approx(float(st._hold), float(entry["hold"]), "walk t=%d hold" % t, 1e-9)


# --- the 5 TS cases, verbatim ------------------------------------------------


func test_never_twists_a_pacifist() -> void:
	var st: Variant = Storyteller.new()
	for i in 200:
		st.update(1.0, _signals({"chaos": 0.9, "dna_rate": 50.0, "karma": 0.6}))
	ok(st.mood != "twist", "pacifist never twists (karma 0.6 >= 0.5 gates twist)")
	eq(st.mood, "test", "pacifist sits in test (bless never triggers)")


func test_blesses_the_struggling() -> void:
	var st: Variant = Storyteller.new()
	for i in 30:
		st.update(1.0, _signals({"eco_health": 0.2}))
	eq(st.mood, "bless", "struggling eco 0.2 -> bless")
	approx(st.gap_bias(), 1.2, "bless gap bias 1.2")


func test_twists_a_dominant_aggressor_after_hysteresis() -> void:
	var st: Variant = Storyteller.new()
	for i in 30:
		st.update(1.0, _signals({"chaos": 0.7, "dna_rate": 30.0, "karma": -0.4}))
	eq(st.mood, "twist", "chaos 0.7 / dnaRate 30 / karma -0.4 -> twist after hold")
	approx(st.gap_bias(), 0.78, "twist gap bias 0.78")


func test_holds_mood_for_20s() -> void:
	var st: Variant = Storyteller.new()
	for i in 10:
		st.update(1.0, _signals({"eco_health": 0.2}))  # bless, ~11s of hold left
	st.update(1.0, _signals({}))  # signals stop being strained but hold remains
	eq(st.mood, "bless", "still bless — hold not expired (MIN_HOLD 20)")


func test_poll_is_fifo_and_offer_beat_dedupes() -> void:
	var st: Variant = Storyteller.new()
	st.offer_beat("herd_remembers")
	st.offer_beat("herd_remembers")
	st.offer_beat("great_migration")
	eq(st.poll(), "herd_remembers", "first poll returns the first offered beat")
	eq(st.poll(), "great_migration", "duplicate offer not queued; FIFO order holds")
	ok(st.poll() == null, "drained queue polls null")


# --- gap_bias / warn_scale buckets (temperament layering) --------------------


func test_gap_bias_test_mood_is_neutral() -> void:
	var st: Variant = Storyteller.new()
	for i in 30:
		st.update(1.0, _signals({}))
	eq(st.mood, "test", "neutral signals -> test")
	approx(st.gap_bias(), 1.0, "test gap bias 1.0")


func test_gap_bias_temperament_layers() -> void:
	# TS gapBias(): the temperament layers ON TOP of the mood bias via
	# noteChaosEvent state. Grace (cradle): gap +50%; hungry (lean): -20%;
	# streak cap (wildcard): x3 brake.
	var cradle: Variant = Storyteller.new()
	cradle.temperament = "cradle"
	for i in 10:
		cradle.update(1.0, _signals({"eco_health": 0.2}))  # bless mood, 1.2 base
	cradle.note_chaos_event(100.0)  # grace 26 > 0 after the next update's decrement
	approx(cradle.gap_bias(), 1.2 * 1.5, "cradle grace: bless 1.2 * 1.5")
	# test-mood grace pinned on a fresh instance (the one above still holds
	# bless hysteresis, so a neutral tick would not flip it)
	var cradle2: Variant = Storyteller.new()
	cradle2.temperament = "cradle"
	cradle2.note_chaos_event(0.0)
	approx(cradle2.gap_bias(), 1.0 * 1.5, "cradle grace: test 1.0 * 1.5")

	var lean: Variant = Storyteller.new()
	lean.temperament = "lean"
	lean.note_chaos_event(0.0)  # cycle 1: not hungry (3 % 3 != 0)
	approx(lean.gap_bias(), 1.0, "lean cycle 1: normal gap")
	lean.note_chaos_event(0.0)
	lean.note_chaos_event(0.0)  # cycle 3: hungry
	approx(lean.gap_bias(), 0.8, "lean hungry cycle: gap * 0.8")

	var wildcard: Variant = Storyteller.new()
	wildcard.temperament = "wildcard"
	for i in 3:
		wildcard.note_chaos_event(float(i))  # same instant: streak builds to 3
	approx(wildcard.gap_bias(), 3.0, "wildcard streak >= 3: gap * STREAK_BRAKE 3")


func test_note_chaos_event_ignores_none_temperament() -> void:
	var st: Variant = Storyteller.new()
	st.note_chaos_event(50.0)
	approx(st.gap_bias(), 1.0, "temperament none: no pacing state, plain mood bias")
	st.reset()


func test_note_chaos_event_streak_breaks_after_calm_window() -> void:
	# streak only counts consecutive events within CALM_WINDOW 28s: a 29s gap
	# resets it, so the wildcard cap can never re-arm from stale events.
	var st: Variant = Storyteller.new()
	st.temperament = "wildcard"
	st.note_chaos_event(0.0)
	st.note_chaos_event(1.0)
	st.note_chaos_event(2.0)
	approx(st.gap_bias(), 3.0, "streak 3 -> braked")
	st.note_chaos_event(31.0)  # 31 - 2 = 29 > 28 -> streak resets to 1
	approx(st.gap_bias(), 1.0, "calm window broke the streak")


func test_warn_scale_buckets() -> void:
	# TS warnScale() reads the temperament FIELD (no argument) — Game
	# assigns it from the world genome every frame.
	var cases := {"cradle": 1.6, "wildcard": 0.8, "lean": 1.0, "none": 1.0}
	for t in cases:
		var st: Variant = Storyteller.new()
		st.temperament = t
		approx(st.warn_scale(), cases[t], "warn_scale %s" % t)


# --- reset / re-arm semantics ------------------------------------------------


func test_reset_wipes_mood_hold_beats_seen_and_pacing() -> void:
	var st: Variant = Storyteller.new()
	st.temperament = "cradle"
	for i in 10:
		st.update(1.0, _signals({"eco_health": 0.2}))
	st.offer_beat("a")
	st.note_chaos_event(0.0)
	st.reset()
	eq(st.mood, "test", "reset: mood back to test")
	approx(float(st._hold), 0.0, "reset: hold cleared")
	approx(float(st._grace), 0.0, "reset: grace cleared")
	eq(st._beats, [], "reset: beat queue empty")
	eq(st._seen, {}, "reset: seen ledger empty")
	eq(st.temperament, "none", "reset: temperament back to none")
	ok(st.poll() == null, "reset: poll drains null")
	# re-arm only on an actual flip: hold is re-set to MIN_HOLD when the mood
	# flips (the flipping tick re-arms AFTER its own decrement, so 10 ticks
	# leave 20 - 9 = 11), and the NEXT flip must wait for it to decay again.
	for i in 10:
		st.update(1.0, _signals({"eco_health": 0.2}))
	approx(float(st._hold), 11.0, "flip re-arms hold to MIN_HOLD (decayed to 11 after 10s)")


func test_hold_re_arms_only_on_actual_flip() -> void:
	var st: Variant = Storyteller.new()
	for i in 25:
		st.update(1.0, _signals({"eco_health": 0.2}))
	# flip happened at t=1 (hold 20); by t=25 hold is 0 and mood stays bless
	approx(float(st._hold), 0.0, "hold decays to 0 while mood unchanged")
	# a SECOND bless-relevant tick must NOT re-arm: next == mood, no flip
	st.update(1.0, _signals({"eco_health": 0.1}))
	approx(float(st._hold), 0.0, "no re-arm when next mood equals current")
	eq(st.mood, "bless", "mood unchanged")
	# only a real change flips now (hold is 0) and re-arms
	st.update(1.0, _signals({}))
	eq(st.mood, "test", "hold expired: mood flips to test")
	approx(float(st._hold), 20.0, "flip re-arms hold to MIN_HOLD")
