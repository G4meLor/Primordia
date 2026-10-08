# Pack-portrait-row + extinction-card pixel scene (xvfb, Compatibility
# renderer) — R9/R8 task 9. The card items are the STAGE's own inner classes
# (creature_stage.gd PackCardItem / SpeciesCardItem) drawn onto this bare
# Node2D — no Game, no camera, so screen coords are local coords. Scenario via
# the PACK_ROW_SCENARIO env (the tools/test_pack_row.sh wrapper runs BOTH,
# sequentially — the single-instance law forbids concurrent godot processes):
#   pairs  (default) — capture the empty viewport, draw a 2-slot pack row +
#           the extinction card, capture, redraw the SAME state, capture
#           again: the two hashes must be byte-identical and differ from the
#           empty frame. Then the teardown contract: Card.release on every
#           item empties its registry entry, the items free, and the card's
#           static _live registry is left EMPTY (MUST 2 evidence — no stale
#           entries, no leaked sub-RIDs).
#   loop50 — 50 back-to-back full redraws of row + card (clear per redraw =
#           the MUST-1 contract). The RID-leak guard is the WRAPPER's: it
#           greps the exit 'RIDs of type "CanvasItem" were leaked' line of
#           both runs — the 50x loop must leave the count unchanged vs the
#           pairs baseline (delta != 0 means the redraw churn leaks).
# Phase machine as test_card_render.gd (the texture lags one frame, hence
# the arm/shot alternation). Run: tools/test_pack_row.sh.
extends Node2D

const StageScript := preload("res://src/game/creature/creature_stage.gd")
const Card := preload("res://src/gfx/creature_card.gd")
const GenomeScript := preload("res://src/evo/genome.gd")

const OUT_DIR := "user://visual_capture"
const TIMEOUT_FRAMES := 1800
const LOOP_N := 50

var _scenario := "pairs"
var _phase := "settle"
var _frames := 0
var _loop_i := 0
var _sha_empty := ""
var _sha_1 := ""
var _slots: Array = []
var _card: Variant = null
var _plate: Variant = null


# the painter-smoke genome (the card scene's fixture) — legs/spots/fur/tail +
# carnivore jaw + brain, so all three stat bars carry a value
func _genome(hue: float) -> Dictionary:
	var g: Dictionary = GenomeScript.default_genome()
	g["size"] = 1.2
	g["legs"] = 4
	g["hue"] = hue
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


func _capture() -> String:
	var img: Image = get_viewport().get_texture().get_image()
	return _sha256(img.get_data())


# 4.2 has no PackedByteArray.sha256_text (4.4+ API) — HashingContext is the
# engine-native sha256 (the card scene's precedent).
func _sha256(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


func _fail(msg: String) -> void:
	printerr("PACK_ROW_TEST_FAIL: %s" % msg)
	get_tree().quit(1)


func _build_row() -> void:
	# two pooled slots exactly as the stage syncs them (identity camera —
	# the slot rect IS the screen rect here)
	var metas := [{"species": "Glorbus the Spiky", "epithet": ""},
			{"species": "Zib II", "epithet": ""}]
	for i in 2:
		var slot: Variant = StageScript.PackCardItem.new()
		slot.genome = _genome(120.0 + 140.0 * float(i))
		slot.meta = metas[i]
		slot.slot = Rect2(40.0 + float(i) * 62.0, 60.0, 52.0, 58.0)
		add_child(slot)
		_slots.append(slot)
	_card = StageScript.SpeciesCardItem.new()
	add_child(_card)
	_card.show_card(_genome(300.0), "Titan unicus", 800.0, 600.0)
	_card.frame = _card.screen_rect  # identity camera: the inverse is identity
	# the R9 nameplate — the stage's own extras item with a plate set (the
	# world-anchored draw above the paw marker)
	_plate = StageScript.CreatureExtraItem.new()
	_plate.plate = "Glorbus the Spiky"
	_plate.marker = false
	_plate.marker_x = 160.0
	_plate.marker_y = 300.0
	add_child(_plate)
	_plate.queue_redraw()


func _redraw_all() -> void:
	for s in _slots:
		s.queue_redraw()
	if _card != null:
		_card.queue_redraw()
	if _plate != null:
		_plate.queue_redraw()


func _ready() -> void:
	_scenario = OS.get_environment("PACK_ROW_SCENARIO")
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
			_build_row()
			_redraw_all()
			_phase = "arm_1"
		"arm_1":
			_phase = "shot_1"  # next frame's texture holds the drawn state
		"shot_1":
			_sha_1 = _capture()
			var img: Image = get_viewport().get_texture().get_image()
			var err := img.save_png(OUT_DIR + "/pack_row_pairs.png")
			if err != OK:
				_fail("save_png pack_row_pairs.png → %s" % str(err))
				return
			print("pack row sha256 = %s" % _sha_1)
			_redraw_all()
			_phase = "arm_2"
		"arm_2":
			_phase = "shot_2"
		"shot_2":
			var sha_2 := _capture()
			print("pack row sha256 (repeat) = %s" % sha_2)
			print("empty sha256 = %s" % _sha_empty)
			if _sha_1 == "":
				_fail("first capture produced an empty hash")
			elif sha_2 != _sha_1:
				_fail("determinism: the two draws differ\n  %s\n  %s" % [_sha_1, sha_2])
			elif sha_2 == _sha_empty:
				_fail("the row hash equals the empty frame — nothing drew")
			else:
				print("PACK_ROW_TEST_OK determinism: two draws byte-identical, content non-empty")
				_teardown_check()
		"teardown":
			pass  # _teardown_check quits inside the deferred free


func _teardown_check() -> void:
	# the release contract, per item (MUST 2): each registry entry empties
	for s in _slots:
		Card.release(s)
		if Card._rids_for(s).size() != 0:
			_fail("release left sub-RIDs on a pack slot")
			return
	Card.release(_card)
	if Card._rids_for(_card).size() != 0:
		_fail("release left sub-RIDs on the species card")
		return
	# free the items — PREDELETE must not resurrect anything; the static
	# registry must end EMPTY (no stale entries held by freed items)
	for s in _slots:
		s.free()
	_card.free()
	_plate.free()
	_slots = []
	_card = null
	_plate = null
	var live: int = Card._live.size()
	if live != 0:
		_fail("the card registry holds %d stale entries after teardown" % live)
		return
	print("PACK_ROW_TEST_OK teardown: registry empty, zero stale entries")
	get_tree().quit(0)


func _loop50_step() -> void:
	match _phase:
		"settle":
			_build_row()
			_phase = "loop"
		"loop":
			_redraw_all()
			_loop_i += 1
			if _loop_i >= LOOP_N:
				_phase = "done"
		"done":
			print("PACK_ROW_TEST_OK loop50: %d redraws completed" % _loop_i)
			get_tree().quit(0)
