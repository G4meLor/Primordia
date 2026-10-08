# Creature-card pixel scene (xvfb, Compatibility renderer) — R11 task 5. No
# Game — the card draws straight onto this Node2D at a fixed rect (60,40,
# 220×160). Scenario via the CARD_SCENARIO env (the tools/test_card_scene.sh
# wrapper runs BOTH, sequentially — the single-instance law forbids concurrent
# godot processes):
#   pairs  (default) — capture the empty viewport, draw the card, capture,
#           redraw the SAME (genome, meta, rect), capture again: the two
#           card hashes (img.get_data().sha256_text()) must be byte-identical
#           and differ from the empty frame (content actually drew). Saves
#           card_pairs.png for eyeballing.
#   loop50 — 50 back-to-back clear + draw_into frames. The RID-leak guard is
#           the WRAPPER's: it greps the exit 'RIDs of type "CanvasItem" were
#           leaked' line of both runs — the 50× loop must leave the count
#           unchanged vs the pairs baseline (each draw_into frees the previous
#           card's 3 sub-RIDs; steady state = one card, so both runs exit with
#           identical card state and the delta must be 0).
# Phase machine as test_visual_creature.gd (the texture lags one frame, hence
# the arm/shot alternation). Run: tools/test_card_scene.sh (one-command entry).
extends Node2D

const Card := preload("res://src/gfx/creature_card.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const OUT_DIR := "user://visual_capture"
const TIMEOUT_FRAMES := 1800
const RECT := Rect2(60.0, 40.0, 220.0, 160.0)
const LOOP_N := 50

var _scenario := "pairs"
var _phase := "settle"
var _frames := 0
var _loop_i := 0
var _sha_empty := ""
var _sha_1 := ""


# the card fixture: the painter smoke's genome (size 1.2, legs 4, spots + fur
# + tail, carnivore jaw 3) + brain 2 — all three bars carry a value
func _genome() -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.2
	g["legs"] = 4
	g["hue"] = 120
	g["sat"] = 0.55
	g["pattern"] = "spots"
	g["coat"] = "fur"
	g["tail"] = true
	g["arms"] = 2
	g["eyes"] = 2
	g["diet"] = "carnivore"
	g["jaw"] = 3
	g["spikes"] = 3
	g["horns"] = 2
	g["brain"] = 2
	return g


func _meta() -> Dictionary:
	return {"species": "Glorbus", "epithet": "the Spiky"}


func _draw_card() -> void:
	RenderingServer.canvas_item_clear(get_canvas_item())
	Card.draw_into(self, _genome(), _meta(), RECT)


func _capture() -> String:
	var img: Image = get_viewport().get_texture().get_image()
	return _sha256(img.get_data())


# 4.2 has no PackedByteArray.sha256_text (that API is 4.4+) — HashingContext
# is the engine-native sha256: byte-identical frames → identical digest text.
func _sha256(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


func _fail(msg: String) -> void:
	printerr("CARD_TEST_FAIL: %s" % msg)
	get_tree().quit(1)


func _ready() -> void:
	_scenario = OS.get_environment("CARD_SCENARIO")
	if _scenario != "loop50":
		_scenario = "pairs"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout in phase %s" % _phase)
		return
	match _scenario:
		"pairs":
			_pairs_step()
		"loop50":
			_loop50_step()


func _pairs_step() -> void:
	match _phase:
		"settle":
			_phase = "shot_empty"  # let the viewport reach its steady clear
		"shot_empty":
			_sha_empty = _capture()
			_draw_card()
			_phase = "arm_1"
		"arm_1":
			_phase = "shot_1"  # next frame's texture holds the drawn state
		"shot_1":
			_sha_1 = _capture()
			var img: Image = get_viewport().get_texture().get_image()
			var err := img.save_png(OUT_DIR + "/card_pairs.png")
			if err != OK:
				_fail("save_png card_pairs.png → %s" % str(err))
				return
			print("card sha256 = %s" % _sha_1)
			_draw_card()
			_phase = "arm_2"
		"arm_2":
			_phase = "shot_2"
		"shot_2":
			var sha_2 := _capture()
			print("card sha256 (repeat) = %s" % sha_2)
			print("empty sha256 = %s" % _sha_empty)
			if _sha_1 == "":
				_fail("first capture produced an empty hash")
			elif sha_2 != _sha_1:
				_fail("determinism: the two draws differ\n  %s\n  %s" % [_sha_1, sha_2])
			elif sha_2 == _sha_empty:
				_fail("the card hash equals the empty frame — nothing drew")
			else:
				print("CARD_TEST_OK determinism: two draws byte-identical, content non-empty")
				get_tree().quit(0)


func _loop50_step() -> void:
	match _phase:
		"settle":
			_phase = "loop"
		"loop":
			_draw_card()
			_loop_i += 1
			if _loop_i >= LOOP_N:
				_phase = "done"
		"done":
			print("CARD_TEST_OK loop50: %d draws completed" % _loop_i)
			get_tree().quit(0)
