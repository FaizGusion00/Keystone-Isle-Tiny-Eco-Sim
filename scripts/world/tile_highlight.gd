class_name TileHighlight
extends Node2D
## Outline + translucent fill over the selected tile. Redraws only on selection change.

var tile := Vector2i(-1, -1)


func set_tile(t: Vector2i) -> void:
	if t == tile:
		return
	tile = t
	queue_redraw()


func _draw() -> void:
	if tile.x < 0:
		return
	var poly := Iso.tile_polygon(tile.x, tile.y)
	draw_colored_polygon(poly, Color(1.0, 0.95, 0.35, 0.35))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(0.05, 0.05, 0.05, 0.9), 6.0, true)
	draw_polyline(outline, Color(1.0, 0.86, 0.15, 1.0), 3.0, true)
