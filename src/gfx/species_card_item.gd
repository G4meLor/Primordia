## R8 extinction-moment card item — ONE at a time on its own item (MUST 1/2
## as the pack row): doom panel + CreatureCard portrait + the EXTINCT stamp
## (vi: TỆT CHỦNG) + the island-silent line. The context queues one card per
## species extinction event (guarded at the bestiary entry — context.gd
## mark_extinct); a stage DRAINS the queue in its update() and shows it here.
## Shared by the creature stage (the R8 original) and the cell stage (the
## final-review fix wave: the cell sim's extinctions queued with no
## cell-stage drain, so the card surfaced minutes later mid-creature — the
## moment must land in the stage that lost the species). Same identity
## mapping as the pack row: node identity, the screen rect rides the live
## camera inverse (identity in the cell stage — the screen-space default).
extends Node2D

const Card := preload("res://src/gfx/creature_card.gd")
const RendererScript := preload("res://src/gfx/renderer.gd")

var genome: Dictionary = {}
var meta: Dictionary = {}
var screen_rect := Rect2()  # screen coords, fixed at show time
var frame := Rect2()        # screen_rect through the live camera inverse


func show_card(g: Dictionary, name: String, vw: float, vh: float) -> void:
	genome = g
	meta = {"species": name, "epithet": ""}
	screen_rect = Rect2(vw / 2.0 - 170.0, 160.0, 340.0, 140.0)
	visible = true


func _draw() -> void:
	RenderingServer.canvas_item_clear(get_canvas_item())  # MUST 1
	if genome.is_empty():
		return
	RendererScript.panel(self, frame.position.x, frame.position.y,
			frame.size.x, frame.size.y, {
		"fill": RendererScript.css_color("rgba(42,10,20,0.92)"),
		"stroke": RendererScript.css_color("#ff5a8a"),
		"lw": 2.0,
		"shadow": RendererScript.css_color("rgba(255,90,138,0.3)"),
	})
	Card.draw_into(self, genome, meta, Rect2(
			frame.position.x + 8.0, frame.position.y + 24.0,
			frame.size.x - 16.0, frame.size.y - 40.0))
	# draw_into left the painter's cam on the command stream — reset to
	# identity for the card's own text (the item node is identity, so the
	# command transform composes with the camera alone)
	draw_set_transform_matrix(Transform2D())
	var stamp: String = tr("EXTINCT")
	var stamp_pos := Vector2(frame.position.x + frame.size.x * 0.5,
			frame.position.y + frame.size.y * 0.5)
	draw_set_transform_matrix(Transform2D(-0.22, stamp_pos))
	RendererScript.outlined_text(self, stamp, 0.0, 0.0,
			{"size": 30.0, "fill": RendererScript.css_color("#ff5a8a"),
					"weight": "700", "alpha": 0.85})
	draw_set_transform_matrix(Transform2D())
	RendererScript.outlined_text(self, tr("the island falls silent…"),
			frame.position.x + frame.size.x / 2.0, frame.position.y + frame.size.y - 12.0,
			{"size": 11.0, "fill": RendererScript.css_color("rgba(255,200,190,0.8)")})


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Card.release(self)  # MUST 2
