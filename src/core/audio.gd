## R7b minimal audio core: the creature's voice. Port shape of Spore
## src/core/audio.ts (AudioEngine) scoped to the redesign's smallest viable
## layer — every non-call hook id stays a silent stub (no music, no mood
## crossfade: explicitly deferred), and synthesis is data-level so headless
## tests never touch an audio device.
##
## Ruling pins (task-8 brief, implemented verbatim):
##   call_pitch = 220 Hz x size_f x hue_f x jaw_f
##     size_f: gene 0.6..2.2 -> 1.6..0.6 linear (bigger = lower)
##     hue_f:  gene 0..360 deg normalized /360 -> 0.85..1.15 linear (+-15%)
##     jaw_f:  level 0..5 -> 1.0..1.3 linear (parts catalog jaw max = 5,
##             Genome.GENE_BOUNDS)
##   notes = [P, P x 1.5 if even fingerprint else P x 0.75, P x 1.25]; the
##     parity source is Genome.genome_hash (the 21-field breeding
##     fingerprint — the ruling names genome_hash; the /12 no-sat variant in
##     context.gd is the bestiary key, and src/core must not depend on
##     src/game). The joined string is 21 text fields, so parity goes through
##     Godot's built-in String.hash() — a fixed, unseeded algorithm, stable
##     across runs and platforms (pinned per genome in tests/test_audio_core).
##   Each tone 0.18 s with 20 ms linear attack + 120 ms linear decay, 50 ms
##     gap; AudioStreamWAV 22050 Hz mono 16-bit; sine carrier (the TS
##     friendly blips — heal/charm/ascend — are sine).
##   Volume: conservative -12 dB applied at DATA level (peak amplitude
##     10^(-12/20) ~= 0.251) rather than a mixer bus — keeps the synthesis
##     pure data (headless-safe) and the audio graph stock.
##
## Mute: AudioCore.muted is the single gate; the owning Game syncs it at boot
## (i18n settings) and in toggle_mute. A muted play_call synthesizes nothing.
## RefCounted, NOT a Node: the Game owns the instance and lends `host` so the
## lazy AudioStreamPlayer can enter the tree on first audible play (never in
## tests — host-less cores queue streams without playback).
class_name AudioCore
extends RefCounted

const GenomeScript := preload("res://src/evo/genome.gd")

const SAMPLE_RATE := 22050
const TONE_DUR := 0.18     # s, per tone
const ATTACK_DUR := 0.02   # s, linear 0 -> 1
const DECAY_DUR := 0.12    # s, linear 1 -> 0
const GAP_DUR := 0.05      # s, digital silence between tones
const BASE_HZ := 220.0
const PEAK_DB := -12.0     # data-level peak, dBFS

var muted := false
## Owning Node (the Game) — null keeps playback inert (tests queue streams
## without ever building a player or touching a device).
var host: Node = null
## Test/observability seam: the stream the last play_call queued (null when
## muted — "no buffer queued" is directly assertable).
var last_queued: AudioStreamWAV = null
var player: AudioStreamPlayer = null  # lazy — built on first audible play


## TS audio.play(name): named one-shots, unknown names silently ignored.
## R7b stub: every non-call id stays silent until its own task.
func play(_id: String) -> void:
	pass


## The creature call: synthesize + queue the 3-note voice for this genome.
## Returns the queued stream (null when muted) — the test seam.
func play_call(genome: Dictionary) -> AudioStreamWAV:
	if muted:
		last_queued = null
		return null
	var stream := make_call_stream(genome)
	last_queued = stream
	_ensure_player()
	if player != null and player.is_inside_tree():
		player.stream = stream
		player.play()  # single voice: a second call restarts on this player
	return stream


# ---- pure synthesis (no audio server anywhere below this line) ------------------

## Base pitch P in Hz from the genome (see the header ruling pins). Inputs
## re-clamped into gene bounds — corrupt values degrade to the same sane
## snaps clamp_genome uses, and the pin formulas read verbatim.
func call_pitch(genome: Dictionary) -> float:
	var size := clampf(float(genome.get("size", 1.0)), 0.6, 2.2)
	var size_f := 1.6 - (size - 0.6) / (2.2 - 0.6) * (1.6 - 0.6)
	# hue lives in degrees 0..360 in the genome; normalize before the +-15%
	# map and wrap like clamp_genome does (360 == 0)
	var hue := fposmod(float(genome.get("hue", 120.0)), 360.0) / 360.0
	var hue_f := 0.85 + hue * 0.3
	var jaw := clampf(float(genome.get("jaw", 0)), 0.0, 5.0)
	var jaw_f := 1.0 + jaw / 5.0 * 0.3
	return BASE_HZ * size_f * hue_f * jaw_f


## The pinned 3-note pattern: [P, P x 1.5 | P x 0.75, P x 1.25].
func call_notes(genome: Dictionary) -> Array:
	var p := call_pitch(genome)
	var second := p * 1.5 if GenomeScript.genome_hash(genome).hash() % 2 == 0 \
			else p * 0.75
	return [p, second, p * 1.25]


## Render the call into a fresh AudioStreamWAV — pure byte math, no device.
func make_call_stream(genome: Dictionary) -> AudioStreamWAV:
	var notes := call_notes(genome)
	var tone_n := _samples(TONE_DUR)      # 3969
	var gap_n := _samples(GAP_DUR)        # 1103
	var attack_n := _samples(ATTACK_DUR)  # 441
	var decay_n := _samples(DECAY_DUR)    # 2646
	var peak := pow(10.0, PEAK_DB / 20.0)
	var bytes := PackedByteArray()
	for ni in notes.size():
		var f: float = notes[ni]
		for i in tone_n:
			var env := 1.0
			if i < attack_n:
				env = float(i) / float(attack_n)
			elif i >= tone_n - decay_n:
				env = float(tone_n - i) / float(decay_n)
			var s := sin(TAU * f * float(i) / float(SAMPLE_RATE)) * env * peak
			# 16-bit little-endian (WAV byte order, matches FORMAT_16_BITS)
			var v := roundi(clampf(s, -1.0, 1.0) * 32767.0)
			bytes.append(v & 0xFF)
			bytes.append((v >> 8) & 0xFF)
		if ni < notes.size() - 1:
			for i in gap_n:
				bytes.append(0)
				bytes.append(0)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## Duration -> sample count on the 22050 Hz grid (round-to-nearest; 0.05 s
## lands on 1103 — the half-sample goes to the gap, the tones are exact).
func _samples(dur: float) -> int:
	return int(dur * float(SAMPLE_RATE) + 0.5)


func _ensure_player() -> void:
	if player != null or host == null:
		return
	player = AudioStreamPlayer.new()
	host.add_child(player)
