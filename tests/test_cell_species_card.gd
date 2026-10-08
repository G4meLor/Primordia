# The final-review fix wave — the R8 extinction card drains in the CELL stage
# (the creature stage keeps its drain for anything queued across a stage
# line). The cell sim's extinctions queued at the death instant with no
# cell-side drain: the card waited for the creature stage and surfaced
# minutes later mid-creature — the R8 moment must land in the stage that
# lost the species. Pins: the REAL cell stage headless (the test_econ_probes
# out-of-tree shape — no canvas RIDs), the queue seeded through the sim-level
# seam (mark_extinct's once-guard is the bestiary's, pinned in
# test_bestiary_page), the drain on the stage's own update(), the TTL hold,
# and the draw-site sync (the cell stage is the screen-space default — the
# camera rig disabled — so the card's frame IS its fixed screen rect).
extends "res://tests/test_base.gd"

const Ctx := preload("res://src/game/context.gd")
const GameScript := preload("res://src/game/game.gd")
const CellStageScript := preload("res://src/game/cell/cell_stage.gd")

const DT := 1.0 / 60.0
const SEED := 0xCACC


func _mk_cell() -> Dictionary:
	var ctx: Variant = Ctx.new(SEED)
	var game: Variant = GameScript.new(ctx)
	game.set_process(false)
	game.set_process_unhandled_input(false)
	game.loop.is_active_cb = func() -> bool: return false
	game.register(CellStageScript.new(game))
	var cell: Variant = game.stages["cell"]
	cell._ready()
	game.switch_stage("cell")
	return {"game": game, "ctx": ctx, "cell": cell}


func _drop(m: Dictionary) -> void:
	var game: Variant = m["game"]
	game.hud = {}
	game.editor = {}
	game.pause = {}
	game.free()


func test_cell_extinction_card_surfaces_in_cell() -> void:
	var m := _mk_cell()
	var cell: Variant = m["cell"]
	var ctx: Variant = m["ctx"]
	# the queue seeded (the sim-level seam): one extinction event's card
	var genome: Dictionary = {"size": 1.0, "diet": "herbivore", "legs": 0}
	ctx.species_cards = [{"genome": genome, "name": "Eelun"}]
	# ONE cell update surfaces the card and drains the queue — nothing left
	# to drift into the creature stage
	cell.update(DT)
	eq(bool(cell._species_card.visible), true, "the card surfaced in the cell stage")
	eq(bool(cell._species_card.genome.is_empty()), false, "the card carries the genome")
	eq(String(cell._species_card.meta["species"]), "Eelun", "the card carries the species name")
	eq(ctx.species_cards.size(), 0, "the queue drained — nothing drifts to the creature stage")
	# the TTL holds: the card stays up for its window, then releases
	var held := 0
	for i in 240:  # 4 s of the 6 s window
		cell.update(DT)
		if bool(cell._species_card.visible):
			held += 1
	eq(held, 240, "the card holds through the TTL window")
	# a second queued card appears only after the first expires (ONE at a
	# time — the creature drain's shape, mirrored)
	ctx.species_cards = [{"genome": genome, "name": "Second"}]
	cell.update(DT)
	eq(ctx.species_cards.size(), 1, "a queued card waits while one shows")
	for i in int(7.0 / DT):  # past the 6 s TTL
		cell.update(DT)
	eq(bool(cell._species_card.visible), true, "the next card surfaced after the release")
	eq(String(cell._species_card.meta["species"]), "Second", "the second card shows its species")
	eq(ctx.species_cards.size(), 0, "the queue drained again")
	_drop(m)


func test_cell_card_draw_site_syncs_screen_rect() -> void:
	var m := _mk_cell()
	var cell: Variant = m["cell"]
	var ctx: Variant = m["ctx"]
	ctx.species_cards = [{"genome": {"size": 1.0}, "name": "Eelun"}]
	cell.update(DT)
	# the draw site (render()): the cell stage owns the screen-space default
	# — the camera rig is disabled — so the card's frame IS its fixed screen
	# rect (the creature stage composes the live camera inverse)
	cell.render()
	eq(cell._species_card.frame, cell._species_card.screen_rect,
			"the draw site syncs the frame to the screen rect (identity camera)")
	var game: Variant = m["game"]
	eq(Rect2(cell._species_card.screen_rect), Rect2(float(game.vw) / 2.0 - 170.0, 160.0, 340.0, 140.0),
			"the fixed screen rect shape (the R8 card geometry)")
	_drop(m)
