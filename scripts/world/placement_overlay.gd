class_name PlacementOverlay
extends Node2D
## While a build tool is selected: tints every tile where it can be used (green = OK,
## amber = allowed but you can't afford it yet, blue = allowed but on a floodplain), and shows a
## see-through "ghost" of what would be built on the hovered / previewed tile, with a green or
## red outline. All quads go through draw_primitive so the whole layer batches into a few calls.

const OK_COL := Color(0.55, 0.95, 0.55, 0.30)
const SHORT_COL := Color(1.0, 0.78, 0.35, 0.26)
const RISKY_COL := Color(0.45, 0.75, 1.0, 0.30)
const GOOD_EDGE := Color(0.70, 1.0, 0.62)
const BAD_EDGE := Color(1.0, 0.45, 0.38)

var view: WorldView
var action := Simulation.Action.NONE
var mask := PackedByteArray()
var hover := Vector2i(-1, -1)
var hover_ok := false
var pulse := true
var _t := 0.0
var NO_UV := PackedVector2Array()


func set_mask(a: int, m: PackedByteArray) -> void:
	action = a
	mask = m
	visible = a != Simulation.Action.NONE
	queue_redraw()


func set_hover(t: Vector2i, ok: bool) -> void:
	if t == hover and ok == hover_ok:
		return
	hover = t
	hover_ok = ok
	queue_redraw()


func clear() -> void:
	set_mask(Simulation.Action.NONE, PackedByteArray())
	set_hover(Vector2i(-1, -1), false)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	modulate.a = 0.82 + 0.18 * sin(_t * 3.0) if pulse else 1.0


func _draw() -> void:
	if view == null or view.world == null or action == Simulation.Action.NONE:
		return
	var ws := view.world
	for i in mini(mask.size(), ws.tile_count()):
		var k := mask[i]
		if k == ValidTiles.NO:
			continue
		var p := ws.coords(i)
		var col := OK_COL if k == ValidTiles.OK else (SHORT_COL if k == ValidTiles.SHORT else RISKY_COL)
		draw_primitive(view.top_polygon(p.x, p.y), PackedColorArray([col, col, col, col]), NO_UV)
	if hover.x >= 0 and ws.in_bounds(hover.x, hover.y):
		var poly := view.top_polygon(hover.x, hover.y)
		var edge := poly.duplicate()
		edge.append(poly[0])
		var c := GOOD_EDGE if hover_ok else BAD_EDGE
		draw_polyline(edge, Color(0.1, 0.08, 0.05, 0.4), 4.0, true)
		draw_polyline(edge, c, 2.0, true)
		_ghost(hover, hover_ok)


## A see-through preview of the result on tile t.
func _ghost(t: Vector2i, ok: bool) -> void:
	var top := view.top_center(t.x, t.y)
	var a := Color(1, 1, 1, 0.72) if ok else Color(1.0, 0.55, 0.5, 0.55)
	var A := Simulation.Action
	match action:
		A.BUILD_FARM:
			var furrow := Color(0.32, 0.22, 0.13, 0.35 * a.a)
			for k in range(-2, 3):
				var o := Vector2(k * 8.0, k * 4.0)
				draw_line(top + o + Vector2(-13, -6.5) * (1.0 - absf(k) * 0.22), top + o + Vector2(13, 6.5) * (1.0 - absf(k) * 0.22), furrow, 1.6)
			for b in range(-2, 3):
				for aa in range(-2, 3):
					if absi(aa) + absi(b) <= 3:
						view.sprite(self, "crop_green", top + Vector2((aa - b) * 5.2, (aa + b) * 2.6 + 1.0), a)
		A.BUILD_HOUSE:
			view.sprite(self, "cottage", top + Vector2(-8, -2), a)
			view.sprite(self, "cottage_b", top + Vector2(8, 5), a)
		A.BUILD_DAM:
			var i := view.world.index(t.x, t.y)
			var j := view.down[i] if i < view.down.size() else -1
			view.sprite(self, "dam_x" if j >= 0 and absi(j - i) == 1 else "dam_y", top + Vector2(0, 2), a)
		A.PLANT_TREES:
			view.sprite(self, "pine_a", top + Vector2(-7, 0), a)
			view.sprite(self, "oak_a", top + Vector2(7, 4), a)
		A.RESTORE_LAND:
			view.sprite(self, "crop_green", top + Vector2(-6, 1), a)
			view.sprite(self, "crop_green", top + Vector2(6, 3), a)
		A.CLEAR_TREES, A.DEMOLISH:
			var r := Color(1.0, 0.42, 0.35, 0.85 if ok else 0.5)
			draw_line(top + Vector2(-9, -5), top + Vector2(9, 5), r, 3.0, true)
			draw_line(top + Vector2(-9, 5), top + Vector2(9, -5), r, 3.0, true)
