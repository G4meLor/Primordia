## Storyteller mood engine: reads stage signals and picks a narration mood
## (bless / test / twist) that shapes pacing. Moods hold for MIN_HOLD seconds
## (hysteresis) so the tone doesn't flicker; a gapBias scales the beat gap.
## The world_temperament trait layers ONE pacing personality on top (catalog
## rule 2 — no second hidden personality): Cradle grants post-threat grace,
## Lean Seasons tighten every ~3rd cycle, the Wildcard carries a streak cap.
## Port of Spore src/game/storyteller.ts. Moods and temperaments are the TS
## string-literal unions; the signal Dictionary uses snake_case keys
## (eco_health, dna_rate, deaths_in_stage, stage_time — stats.gd convention).
class_name Storyteller
extends RefCounted

const MOOD_BLESS := "bless"
const MOOD_TEST := "test"
const MOOD_TWIST := "twist"

const MIN_HOLD := 20.0
const TWIST_CHAOS := 0.55
const TWIST_DNA_RATE := 25.0
const PACIFIST_KARMA := 0.5
const BLESS_ECO := 0.35
const BLESS_DEATHS := 2.0

# temperament pacing (catalog I.b world_temperament)
const GRACE_SECONDS := 26.0  # Cradle: one base gap of post-threat calm
const LEAN_EVERY := 3        # Lean: every ~3rd cycle is a long hungry one
const STREAK_CAP := 3        # Wildcard: never >3 consecutive high-severity events
const STREAK_BRAKE := 3.0    # gap ×3 while capped — the next event lands past the calm window
# The calm window must sit UNDER the smallest braked gap any stage/difficulty
# can produce, or a 4th event arrives inside the window and the cap slips:
# 26 (base) × 0.7 (chaos difficulty) × 3 (brake) × (1 − 0.45) = 30.04s worst
# case (creature's wider gap/scale only grow it) → 28 keeps a margin.
const CALM_WINDOW := 28.0    # seconds without a high-severity event breaks a streak

var mood: String = MOOD_TEST
## The ONE pacing personality — Game.pumpWorldStory assigns it from the
## world genome every frame (re-derived worlds carry it for free). TS keeps
## it on the Storyteller instance, NOT in StSignals.
var temperament: String = "none"
# TS privates are compile-time only; GDScript underscores them. The fixture
# generator read `hold` after each update, and test_storyteller.gd pins it
# the same way — GDScript does not enforce the underscore.
var _hold: float = 0.0
var _beats: Array = []
var _seen: Dictionary = {}   # TS Set<string> — keys only
# temperament pacing state (runtime only, reset with the run)
var _grace: float = 0.0      # Cradle: post-threat calm remaining
var _cycles: int = 0         # Lean: high-severity event counter
var _hungry: bool = false    # Lean: the current cycle is tightened
var _streak: int = 0         # consecutive high-severity events (calm-window bounded)
var _last_event_at: float = -1e9


func offer_beat(id: String) -> void:
	if not _seen.has(id):
		_seen[id] = true
		_beats.append(id)


func poll() -> Variant:
	# TS `this.beats.shift() ?? null` — pop_front on an empty Array is null.
	return _beats.pop_front()


## Fresh-run reset: mood, hysteresis hold, the beat ledger and the
## temperament pacing state all clear.
func reset() -> void:
	mood = MOOD_TEST
	_hold = 0.0
	_beats = []
	_seen.clear()
	temperament = "none"
	_grace = 0.0
	_cycles = 0
	_hungry = false
	_streak = 0
	_last_event_at = -1e9


## Chaos onApply hook (the warn→active conversion = a high-severity event
## went live). Feeds the temperament pacing. Unwarned events carry no
## hook, so "consecutive" is bounded by the calm window: with the streak
## brake on, the next gap always exceeds CALM_WINDOW, which is what makes
## the cap stick.
func note_chaos_event(now: float) -> void:
	if temperament == "none":
		return
	_cycles += 1
	_hungry = temperament == "lean" and _cycles % LEAN_EVERY == 0
	if now - _last_event_at > CALM_WINDOW:
		_streak = 0
	_streak += 1
	if temperament == "cradle":
		_grace = GRACE_SECONDS
	_last_event_at = now


## Multiplier on the chaos-event gap: bless stretches the gap (fewer
## events), twist tightens it (more events); the temperament layers its
## own pacing on top (scheduler untouched — this rides gapMult).
func gap_bias() -> float:
	var b := 1.2 if mood == MOOD_BLESS else (0.78 if mood == MOOD_TWIST else 1.0)
	if temperament == "cradle" and _grace > 0.0:                    # grace: gap +50%
		b *= 1.5
	elif temperament == "lean" and _hungry:                         # hungry cycle: gap −20%
		b *= 0.8
	elif temperament == "wildcard" and _streak >= STREAK_CAP:
		b *= STREAK_BRAKE
	return b


## bio_tell (catalog III #11): temperament bucket scales the warn window —
## calm worlds warn long and spread thin, hot worlds warn short. The 0.8
## floor for hot worlds is the catalog factory rule (never under 0.8x base).
func warn_scale() -> float:
	match temperament:
		"cradle":
			return 1.6
		"wildcard":
			return 0.8
		_:
			return 1.0


## Signal defaults mirror the TS undefined comparisons: a missing eco_health
## never blesses, everything else never trips its branch.
func update(dt: float, s: Dictionary) -> void:
	_hold = maxf(0.0, _hold - dt)
	_grace = maxf(0.0, _grace - dt)
	var next: String
	if float(s.get("eco_health", 1.0)) < BLESS_ECO \
			or float(s.get("deaths_in_stage", 0.0)) >= BLESS_DEATHS:
		next = MOOD_BLESS
	elif float(s.get("karma", 0.0)) >= PACIFIST_KARMA:
		next = MOOD_TEST  # pacifist gate — never twist
	elif float(s.get("chaos", 0.0)) > TWIST_CHAOS \
			or float(s.get("dna_rate", 0.0)) > TWIST_DNA_RATE:
		next = MOOD_TWIST
	else:
		next = MOOD_TEST
	if next != mood and _hold <= 0.0:
		mood = next
		_hold = MIN_HOLD
