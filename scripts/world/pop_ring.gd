class_name PopRing
extends Node2D
## One-shot iso ring that expands and fades (placement feedback).

var color := Color.WHITE
var still := false   ## reduce motion: a soft flash in place, no expanding ring
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
	# soft flash of the tile top, gone by mid-life
	var flash := PackedVector2Array([Vector2(0, -Iso.HALF_H), Vector2(Iso.HALF_W, 0), Vector2(0, Iso.HALF_H), Vector2(-Iso.HALF_W, 0)])
	draw_colored_polygon(flash, Color(color, 0.42 * maxf(0.0, 1.0 - k * 1.8)))
	if still:
		return
	var s := 0.6 + 0.8 * ease(k, 0.4)
	var pts := PackedVector2Array()
	for a in 25:
		var ang := a / 24.0 * TAU
		pts.append(Vector2(cos(ang) * Iso.HALF_W * s, sin(ang) * Iso.HALF_H * s))
	draw_polyline(pts, Color(color, 1.0 - k), 3.0 * (1.0 - k) + 1.0, true)
