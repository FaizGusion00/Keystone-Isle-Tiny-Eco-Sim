class_name TileHighlight
extends Node2D
## Selection marker on top of the selected tile's raised block, with a gentle pulse.

var tile := Vector2i(-1, -1)
var view: WorldView
var pulse := true
var color := Color(1.0, 0.93, 0.62)
var _t := 0.0


func set_tile(t: Vector2i) -> void:
	if t == tile:
		return
	tile = t
	_t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if tile.x < 0:
		return
	_t += delta
	var a := 0.75 + 0.25 * sin(_t * 4.0) if pulse else 1.0
	modulate = Color(1, 1, 1, a)


func _draw() -> void:
	if tile.x < 0:
		return
	var poly := Iso.tile_polygon(tile.x, tile.y)
	if view != null and view.world != null and view.world.in_bounds(tile.x, tile.y):
		poly = view.top_polygon(tile.x, tile.y) # follows the sloped ground
	draw_colored_polygon(poly, Color(color, 0.22))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(0.12, 0.10, 0.06, 0.45), 4.5, true)
	draw_polyline(outline, color, 2.0, true)
	# corner ticks
	for p in poly:
		draw_circle(p, 2.2, color)
