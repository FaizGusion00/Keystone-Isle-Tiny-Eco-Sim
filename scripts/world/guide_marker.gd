class_name GuideMarker
extends Node2D
## A bouncing arrow and a pulsing ring on the tile the guide is talking about ("tap here").
## Lives in world space so it stays on the tile while the camera moves.

var view: WorldView
var tile := Vector2i(-1, -1)
var _t := 0.0


func set_tile(t: Vector2i) -> void:
	if t == tile:
		return
	tile = t
	visible = t.x >= 0
	_t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	if view == null or view.world == null or tile.x < 0 or not view.world.in_bounds(tile.x, tile.y):
		return
	var calm := UiKit.reduce_motion
	var poly := view.top_polygon(tile.x, tile.y)
	var k := 0.5 + 0.5 * sin(_t * 4.0) if not calm else 1.0
	var c := view.top_center(tile.x, tile.y)
	var ring := PackedVector2Array()
	var g := 1.0 + 0.18 * k
	for p in poly:
		ring.append(c + (p - c) * g)
	ring.append(ring[0])
	draw_polyline(ring, Color(0.1, 0.07, 0.03, 0.35), 5.0, true)
	draw_polyline(ring, Color(UiKit.AMBER, 0.6 + 0.4 * k), 2.5, true)
	var bob := (0.0 if calm else -6.0 * absf(sin(_t * 3.2)))
	var tip := c + Vector2(0, -26 + bob)
	var arrow := PackedVector2Array([tip, tip + Vector2(-9, -12), tip + Vector2(-4, -12), tip + Vector2(-4, -24),
		tip + Vector2(4, -24), tip + Vector2(4, -12), tip + Vector2(9, -12)])
	var shadow := PackedVector2Array()
	for p in arrow:
		shadow.append(p + Vector2(1.5, 2))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.25))
	draw_colored_polygon(arrow, UiKit.AMBER)
	var outline := arrow.duplicate()
	outline.append(arrow[0])
	draw_polyline(outline, Color(0.35, 0.22, 0.05), 1.5, true)
