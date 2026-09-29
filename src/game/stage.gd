## Stage base class — port of TS game.ts `interface Stage` (game.ts:20-26).
## Nodes so later stages can own child canvases/_draw; the Game registry keys
## by `id`. TS onEnter(from: StageId | null) ports with from = null on boot
## entry (GDScript keeps the null via Variant — stages never distinguish it
## from a real StageId today, same as TS's _from ignores it).
class_name Stage
extends Node

var id := ""
## Back-reference to the Game — Variant breaks the cyclic preload.
var game: Variant = null


func _init(game_v: Variant = null, id_v := "") -> void:
	game = game_v
	id = id_v


func update(dt: float) -> void:
	pass


## Per-frame draw hook (Game's render side; stages queue redraws here later).
func render() -> void:
	pass


func on_enter(from: Variant = null) -> void:
	pass


func on_exit() -> void:
	pass
