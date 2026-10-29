class_name PopRing
extends Node2D
## One-shot iso ring that expands and fades (placement feedback).

var color := Color.WHITE
var _t := 0.0
const LIFE := 0.45


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / LIFE
	var s := 0.6 + 0.8 * ease(k, 0.4)
	var pts := PackedVector2Array()
	for a in 25:
		var ang := a / 24.0 * TAU
		pts.append(Vector2(cos(ang) * Iso.HALF_W * s, sin(ang) * Iso.HALF_H * s))
	draw_polyline(pts, Color(color, 1.0 - k), 3.0 * (1.0 - k) + 1.0, true)
