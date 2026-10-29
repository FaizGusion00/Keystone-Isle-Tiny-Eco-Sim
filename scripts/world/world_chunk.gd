class_name WorldChunk
extends Node2D
## Draws one CHUNK x CHUNK block of tiles in painter's order (row-major inside a chunk, and
## chunks row-major, which is a valid back-to-front order for this isometric layout).
## Redrawn only when WorldView marks it dirty; Godot caches the draw commands.

var view: WorldView
var x0 := 0
var y0 := 0
var x1 := 0
var y1 := 0


func _draw() -> void:
	if view == null or view.world == null:
		return
	for y in range(y0, y1):
		for x in range(x0, x1):
			view.draw_tile(self, x, y)
