class_name WorldChunk
extends Node2D
## Draws one CHUNK x CHUNK block of tiles. Redrawn only when WorldView marks it dirty;
## Godot caches the draw commands, so an unchanged chunk costs nothing per frame.

var view: WorldView
var x0 := 0
var y0 := 0
var x1 := 0
var y1 := 0


func _draw() -> void:
	if view == null or view.world == null:
		return
	var ws := view.world
	var colors := view.tile_colors
	var w := ws.width
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * w + x
			draw_colored_polygon(Iso.tile_polygon(x, y), colors[i])
			view.draw_tile_decor(self, x, y, i)
