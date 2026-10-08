## DEATH DEBRIEF — the R4 overlay component: what killed you, the DNA it
## cost, one counter-tip. RefCounted, stage-owned (built in each stage's
## _ready like the tutorial engine); the stages that already draw death
## overlays call draw() inside their death block, space (no fade) in its ui
## layer. Display-only: nothing here consumes input or touches a gate — the
## one-way-door invariant (every player action gated on php > 0 / fade <= 0)
## is untouched.
##
## CAUSE RECORDING IS UI-SIDE (controller ruling): the sims fire ONE hook —
## `death_debrief` [cause_id, killer, dna_lost] — at the death instant and
## store nothing (the cell A-B dump sha stays stable). The stage handler
## routes the two payload shapes here:
##   cause_id != ""  → note(): a killing blow held as pending (cell/creature
##                      pass the killer's SPECIES ID — the stage resolves the
##                      bestiary name; the component keeps display strings)
##   cause_id == ""  → commit(): the death handler's bill (dna_lost = what
##                      the path already computes) — opens the 1.4s window
##                      on the pending cause and clears the pending pair.
## The window self-dismisses before the 1.6-1.8s fades end, so the overlay
## dissolves into the existing respawn (no new state, no dismiss input).
extends RefCounted

const RendererScript := preload("res://src/gfx/renderer.gd")

## The overlay's own budget inside the existing fades (1.6s cell/tribe,
## 1.8s creature); space has no fade — this window is the whole life there.
const WINDOW := 1.4

## Every player-death cause across the 5 sims — the registry pins the
## death-path enumeration (the site list lives in tests/test_death_debrief.gd;
## the civ sim has no player-death path, so it contributes nothing). One
## concrete, short tip per cause. Text keys holding %s take the killer's
## bestiary name — the name interpolates OUTSIDE tr (template first, the
## R2/QC-r3 precedent) — and pair with a no_killer generic line for a
## missed bestiary lookup. tribe_* reuses the sim's lastDeathCause keys
## verbatim (the same strings the death toasts draw).
const CAUSES := {
	"cell_bite": {
		"text": "The %s got you",
		"no_killer": "Something in the deep got you",
		"tip": "grow SPIKES and dash away",
	},
	"cell_meteor": {
		"text": "The meteor got you",
		"tip": "outrun the blast ring",
	},
	"creature_bite": {
		"text": "The %s got you",
		"no_killer": "Something on the island got you",
		"tip": "hold F to charm or pack up",
	},
	"creature_lava": {
		"text": "The lava got you",
		"tip": "keep off the red pools",
	},
	"creature_meteor": {
		"text": "The meteor got you",
		"tip": "stay clear of the impact ring",
	},
	"tribe_raiders": {
		"text": "raiders cut you down",
		"tip": "arm warriors before the next raid",
	},
	"tribe_beast": {
		"text": "the great beast gored you",
		"tip": "gang up on the beast together",
	},
	"space_sun": {
		"text": "The sun got you",
		"tip": "bank away from the star",
	},
	"space_blackhole": {
		"text": "The black hole got you",
		"tip": "thrust away before the pull wins",
	},
	"space_pirates": {
		"text": "The pirates got you",
		"tip": "click to shoot or outrun them",
	},
}

var _pending_cause := ""
var _pending_killer := ""
var _cause_id := ""
var _killer := ""
var _dna := 0
var _age := -1.0  # <0 idle; 0..WINDOW showing


## Stage on_enter — no stale debrief across a quit-to-title round-trip.
func reset() -> void:
	_pending_cause = ""
	_pending_killer = ""
	_cause_id = ""
	_killer = ""
	_dna = 0
	_age = -1.0


## A killing blow named its cause (the sim's note fire). Held until the
## death handler commits; the last blow in a tick wins. Ignored mid-window —
## a fade's corpse blows must not rewrite a showing debrief.
func note(cause_id: String, killer := "") -> void:
	if _age >= 0.0:
		return
	_pending_cause = cause_id
	_pending_killer = killer


## The death handler's bill lands (the commit fire): open the window on the
## pending cause. Without a pending note there is nothing to show (defensive
## — every wired path notes first).
func commit(dna_lost: int) -> void:
	if _pending_cause.is_empty():
		return
	_cause_id = _pending_cause
	_killer = _pending_killer
	_dna = dna_lost
	_pending_cause = ""
	_pending_killer = ""
	_age = 0.0


## The stage update drains the window (the sim's fade owns the respawn;
## this only ages the overlay — a paused stage freezes both in step).
func tick(dt: float) -> void:
	if _age < 0.0:
		return
	_age += dt
	if _age >= WINDOW:
		reset()


func active() -> bool:
	return _age >= 0.0 and not _cause_id.is_empty()


## Pure build (cause_id, dna_lost, killer) -> the overlay lines: cause,
## DNA (omitted when the path bills nothing — post-ending ship deaths, a
## sub-1 DNA round-down), tip. An unknown id builds nothing.
func build_lines(cause_id: String, dna_lost: int, killer: String) -> Array[String]:
	var entry: Variant = CAUSES.get(cause_id)
	if entry == null:
		return []
	var row: Dictionary = entry
	var template := String(row["text"])
	var cause_line := ""
	if template.contains("%s"):
		cause_line = (tr(template) % killer) if not killer.is_empty() \
				else tr(String(row["no_killer"]))
	else:
		cause_line = tr(template)
	var lines: Array[String] = [cause_line]
	if dna_lost > 0:
		lines.append(tr("−%d DNA") % dna_lost)
	lines.append(tr(String(row["tip"])))
	return lines


## Stacked under the stage's own death headline (the anchor is the stage's
## call site — each respawn hint sits at a different depth). Quick in,
## slower out; gone before the fade hands over to the respawn.
func draw(ci: CanvasItem, vw: float, anchor_y: float) -> void:
	if not active():
		return
	var lines := build_lines(_cause_id, _dna, _killer)
	if lines.is_empty():
		return
	var a := clampf(minf(_age / 0.12, (WINDOW - _age) / 0.25), 0.0, 1.0)
	var y := anchor_y
	for i in lines.size():
		var size := 14.0 if i == 0 else (12.0 if i == 1 else 11.0)
		var col := Color("#ffc9b8") if i == 0 \
				else (Color("#9fd8ff") if i == 1 else Color(1.0, 0.88, 0.8, 0.85))
		col.a *= a
		RendererScript.outlined_text(ci, lines[i], vw / 2.0, y, {"size": size, "fill": col})
		y += 20.0 if i == 0 else 16.0
