# R7b audio core tests — the creature call. Every assertion is in-memory
# data: AudioStreamWAV buffers are plain byte arrays (no AudioServer, no
# device, no playback — AudioCore.host stays null in this file so the lazy
# player never materializes). Tone shape mirrors TS audio.ts's friendly blips
# (sine carriers; heal/charm/ascend) with the ruling's pinned LINEAR envelope
# instead of WebAudio's exponential ramps.
#
# Pins (controller ruling, task-8 brief):
#   P = 220 x size_f x hue_f x jaw_f
#   size_f: 0.6 -> 1.6 .. 2.2 -> 0.6 linear (bigger = lower)
#   hue_f:  hue 0..360 deg -> 0.85..1.15 linear, wrapping at 360
#   jaw_f:  level 0..5 -> 1.0..1.3 linear (parts catalog jaw max = 5)
#   notes = [P, P x 1.5 | P x 0.75 (Genome.genome_hash parity), P x 1.25]
#   envelope per tone: 0.18 s, 20 ms linear attack, 120 ms linear decay,
#   50 ms gap; 22050 Hz mono 16-bit; -12 dBFS data-level peak.
extends "res://tests/test_base.gd"

const AudioScript := preload("res://src/core/audio.gd")
const GenomeScript := preload("res://src/evo/genome.gd")
const ContextScript := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const MenuStageScript := preload("res://src/game/menu.gd")
const CreatureStageScript := preload("res://src/game/creature/creature_stage.gd")
const CreatureSimScript := preload("res://src/game/creature/creature_sim.gd")

const DT := 1.0 / 60.0
const SEED := 0xA0D10
const SCRATCH_CFG := "user://test_audio_settings.cfg"
const SAMPLE_RATE := 22050
# Sample-grid counts (round-to-nearest): 0.18 s -> 3969, 50 ms -> 1103,
# so 3 tones + 2 gaps = 14113 samples.
const TONE_N := 3969
const GAP_N := 1103

# Pinned call genomes (partial dicts — call_pitch reads size/hue/jaw with
# genome defaults) and their parities (Genome.genome_hash(g).hash() % 2,
# probed 2026-10-07): small/mid odd -> note2 x0.75, big/default even -> x1.5.
const G_SMALL := {"size": 0.6, "hue": 0, "jaw": 0}    # P = 299.2
const G_MID := {"size": 1.4, "hue": 180, "jaw": 2}    # P = 271.04
const G_BIG := {"size": 2.2, "hue": 300, "jaw": 5}    # P = 188.76


# ---- call_pitch: pure pitch derivation ----------------------------------------

func test_call_pitch_pinned_genomes() -> void:
	var core: Variant = AudioScript.new()
	approx(core.call_pitch(G_SMALL), 299.2, "small (0.6,0,0): 220x1.6x0.85x1.0", 1e-6)
	approx(core.call_pitch(G_MID), 271.04, "mid (1.4,180,2): 220x1.1x1.0x1.12", 1e-6)
	approx(core.call_pitch(G_BIG), 188.76, "big (2.2,300,5): 220x0.6x~1.1x1.3", 1e-6)
	approx(core.call_pitch(GenomeScript.default_genome()), 299.079,
			"default genome (1,120,1): 220x1.35x0.95x1.06", 1e-6)


func test_call_pitch_factor_axes() -> void:
	var core: Variant = AudioScript.new()
	# ratios cancel the other two factors — the axis mapping is what's pinned
	approx(_pitch(core, {"size": 0.6}) / _pitch(core, {"size": 2.2}), 1.6 / 0.6,
			"size axis: 0.6 -> x1.6, 2.2 -> x0.6 (bigger = lower)", 1e-6)
	approx(_pitch(core, {"jaw": 5}) / _pitch(core, {"jaw": 0}), 1.3,
			"jaw axis: level 5 -> x1.3", 1e-6)
	approx(_pitch(core, {"hue": 0}) / _pitch(core, {"hue": 180}), 0.85,
			"hue 0 -> -15%", 1e-6)
	approx(_pitch(core, {"hue": 359}) / _pitch(core, {"hue": 180}),
			1.1491666666666667, "hue 359 -> +15% edge", 1e-6)
	approx(_pitch(core, {"hue": 360}) / _pitch(core, {"hue": 180}), 0.85,
			"hue wraps at 360", 1e-6)
	# missing fields fall back to the genome defaults, not zeroes
	ok(core.call_pitch({}) > 0.0, "empty genome still pitches")


func _pitch(core: Variant, mods: Dictionary) -> float:
	var g: Dictionary = {"size": 1.0, "hue": 180, "jaw": 0}
	g.merge(mods, true)
	return float(core.call_pitch(g))


# ---- call_notes: the pinned 3-note pattern -------------------------------------

func test_call_notes_pattern() -> void:
	var core: Variant = AudioScript.new()
	var pins := [
		[G_SMALL, false], [G_MID, false], [G_BIG, true],
		[GenomeScript.default_genome(), true],
	]
	for pin_v in pins:
		var pin: Array = pin_v
		var g: Dictionary = pin[0]
		var even: bool = pin[1]
		var p: float = core.call_pitch(g)
		var notes: Array = core.call_notes(g)
		eq(notes.size(), 3, "three notes (%s)" % str(g))
		approx(notes[0], p, "note1 = P (%s)" % str(g), 1e-9)
		if even:
			eq(notes[1], p * 1.5, "note2 = P x 1.5 (even genome_hash) (%s)" % str(g))
		else:
			eq(notes[1], p * 0.75, "note2 = P x 0.75 (odd genome_hash) (%s)" % str(g))
		approx(notes[2], p * 1.25, "note3 = P x 1.25 (%s)" % str(g), 1e-9)


# ---- make_call_stream: buffer shape, RMS, gaps, per-tone frequency --------------

func test_call_stream_shape() -> void:
	var core: Variant = AudioScript.new()
	var s: AudioStreamWAV = core.make_call_stream(G_MID)
	eq(int(s.mix_rate), SAMPLE_RATE, "mix rate 22050")
	eq(int(s.format), AudioStreamWAV.FORMAT_16_BITS, "16-bit PCM")
	eq(bool(s.stereo), false, "mono")
	eq(s.data.size(), (3 * TONE_N + 2 * GAP_N) * 2, "buffer bytes: 3x0.18s + 2x50ms")


func test_call_stream_tones_have_energy_and_gaps_are_silent() -> void:
	var core: Variant = AudioScript.new()
	var s: AudioStreamWAV = core.make_call_stream(G_MID)
	var samples: Array = _decode16(s.data)
	eq(samples.size(), 3 * TONE_N + 2 * GAP_N, "sample count")
	for seg in 3:
		var start: int = seg * (TONE_N + GAP_N)
		ok(_rms(samples, start, TONE_N) > 0.01, "tone %d has non-zero samples (RMS)" % seg)
		if seg < 2:
			var silent := true
			for i in GAP_N:
				if float(samples[start + TONE_N + i]) != 0.0:
					silent = false
					break
			ok(silent, "gap %d is digital silence" % seg)


func test_call_stream_frequencies_follow_the_genome() -> void:
	var core: Variant = AudioScript.new()
	var notes: Array = core.call_notes(G_MID)
	var s: AudioStreamWAV = core.make_call_stream(G_MID)
	var samples: Array = _decode16(s.data)
	for seg in 3:
		var start: int = seg * (TONE_N + GAP_N)
		# zero-crossing estimate: crossings ~= 2 x f x duration for a sine
		var crossings := 0
		var prev: float = samples[start]
		for i in range(1, TONE_N):
			var v: float = samples[start + i]
			if (prev >= 0.0) != (v >= 0.0):
				crossings += 1
			prev = v
		var est: float = float(crossings) / (2.0 * float(TONE_N) / float(SAMPLE_RATE))
		approx(est, float(notes[seg]), "tone %d frequency" % seg,
				float(notes[seg]) * 0.03)


func _decode16(bytes: PackedByteArray) -> Array:
	var out: Array = []
	for i in bytes.size() / 2:
		var v: int = int(bytes[i * 2]) | (int(bytes[i * 2 + 1]) << 8)
		if v >= 32768:
			v -= 65536
		out.append(float(v) / 32767.0)
	return out


func _rms(samples: Array, start: int, n: int) -> float:
	var acc := 0.0
	for i in n:
		var v: float = samples[start + i]
		acc += v * v
	return sqrt(acc / float(n))


# ---- mute gate + lazy player ----------------------------------------------------

func test_mute_gate_blocks_the_buffer_and_unmute_restores() -> void:
	var core: Variant = AudioScript.new()
	core.muted = true
	eq(core.play_call(G_MID), null, "muted play_call queues nothing")
	eq(core.last_queued, null, "muted leaves nothing queued")
	core.muted = false
	var s: AudioStreamWAV = core.play_call(G_MID)
	ok(s != null, "unmute restores the call")
	ok(s.data.size() > 0, "the restored call carries samples")
	eq(core.last_queued, s, "last_queued mirrors the queued stream")


func test_lazy_player_and_non_call_ids_stay_inert() -> void:
	var core: Variant = AudioScript.new()
	core.play("click")
	core.play("levelup")
	core.play("zap")
	eq(core.player, null, "no AudioStreamPlayer without an audible play")
	eq(core.last_queued, null, "non-call ids queue nothing (R7b silent stubs)")
	# even an audible play never builds the player without a host node
	core.play_call(G_MID)
	eq(core.player, null, "host-less play_call stays device-free")


# ---- game-level dispatch (hook seam + toggle_mute) -------------------------------

func _wipe_cfg() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(SCRATCH_CFG)


func _boot(write_muted_cfg := false) -> Variant:
	_wipe_cfg()
	if write_muted_cfg:
		var cfg := ConfigFile.new()
		cfg.set_value("settings", "muted", true)
		cfg.save(SCRATCH_CFG)
	var ctx: Variant = ContextScript.new(SEED)
	var g: Variant = GameScript.new(ctx)
	g.set_process(false)
	g.set_process_unhandled_input(false)
	g.loop.is_active_cb = func() -> bool: return false
	# pin the locale/mute defaults (the shared user cfg may carry anything)
	g.i18n.settings_path = SCRATCH_CFG
	g.i18n.load_settings()
	g.i18n.set_lang("en")
	g.muted = g.i18n.get_muted()
	g.audio.muted = g.muted
	g.register(MenuStageScript.new(g))
	g.register(CreatureStageScript.new(g))
	g.stages["creature"]._ready()
	g.start()
	return g


func _drop(g: Variant) -> void:
	if g != null:
		g.hud = {}  # break the recorder-Callable cycle into this test instance
		g.free()


func test_settings_muted_true_queues_nothing() -> void:
	var g: Variant = _boot(true)
	ok(bool(g.muted), "settings muted=true reads into game.muted")
	ok(bool(g.audio.muted), "game boot syncs the core's mute")
	g.audio_play("call", G_MID, 0.0)
	eq(g.audio.last_queued, null, "muted boot: the call queues no buffer")
	_drop(g)


func test_game_dispatch_routes_call_and_keeps_other_ids_silent() -> void:
	var g: Variant = _boot()
	g.audio_play("click", 1.0, 0.0)
	eq(g.audio.last_queued, null, "non-call id stays a silent stub")
	g.audio_play("call", G_MID, 0.0)
	ok(g.audio.last_queued != null, "the call id reaches the AudioCore")
	# the stage hook seam forwards through game dispatch
	var h: Dictionary = g.stages["creature"]._build_hooks()
	h["audio_play"].call("call", G_BIG, 0.0)
	ok(g.audio.last_queued != null, "stage audio_play hook reaches the core")
	var via_hook: AudioStreamWAV = g.audio.last_queued
	h["audio_play"].call("zap", 0.7, 0.0)
	eq(g.audio.last_queued, via_hook, "other hook ids change nothing")
	_drop(g)


func test_toggle_mute_gates_and_persists() -> void:
	var g: Variant = _boot()
	g.audio_play("call", G_MID, 0.0)
	ok(g.audio.last_queued != null, "unmuted: the call queues")
	g.toggle_mute()
	ok(bool(g.muted), "toggle_mute flips game.muted")
	ok(bool(g.audio.muted), "toggle_mute syncs the core")
	g.audio_play("call", G_MID, 0.0)
	eq(g.audio.last_queued, null, "muted: no buffer queued")
	var readback: Dictionary = g.i18n.load_settings()
	eq(bool(readback["muted"]), true, "mute persisted to the settings cfg")
	g.toggle_mute()
	ok(not bool(g.audio.muted), "unmute re-opens the gate")
	g.audio_play("call", G_MID, 0.0)
	ok(g.audio.last_queued != null, "unmute restores the call")
	_drop(g)


# ---- sim wiring: charm win + pack greet ------------------------------------------

func _mk_sim() -> Dictionary:
	var ctx: Variant = ContextScript.new(SEED)
	var rec: Array = []
	var sim: Variant = CreatureSimScript.new(ctx, ctx.rng.branch(),
			{"audio_play": func(n, v, p): rec.append([n, v, p])})
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


func test_charm_win_fires_the_call_with_the_target_genome() -> void:
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
	eq(bool(e["pack"]), true, "befriended (the win happened)")
	var calls: Array = []
	for a_v in m["rec"]:
		var a: Array = a_v
		if String(a[0]) == "call":
			calls.append(a)
	eq(calls.size(), 1, "the win fires exactly one call")
	if calls.size() == 1:
		ok(calls[0][1] is Dictionary, "the vol slot carries the genome dict")
		eq(int(calls[0][1].get("legs", -1)), 4, "the payload is the target's genome")


func test_pack_restore_greets_once_with_a_call() -> void:
	var m := _mk_sim()
	var genome: Dictionary = GenomeScript.default_genome()
	m["ctx"].flags["packGenomes"] = JSON.stringify([{"genome": genome, "baby": false}])
	m["sim"].on_enter()
	eq(m["sim"].ents.size(), 1, "the pack member restored")
	var calls: Array = []
	for a_v in m["rec"]:
		var a: Array = a_v
		if String(a[0]) == "call":
			calls.append(a)
	eq(calls.size(), 1, "the restored pack greets exactly once")
	if calls.size() == 1:
		ok(calls[0][1] is Dictionary, "the greet carries the member's genome")
		eq(float(calls[0][1].get("size", -1.0)), 1.0, "greet genome rides verbatim")
