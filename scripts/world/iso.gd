class_name Iso
extends RefCounted
## Isometric (2:1 diamond) math. Tile (x, y) has its CENTER at tile_to_local(x, y).
## Map x grows down-right on screen, map y grows down-left.

const TILE_W := 64.0
const TILE_H := 32.0
const HALF_W := TILE_W * 0.5
const HALF_H := TILE_H * 0.5


static func tile_to_local(x: int, y: int) -> Vector2:
	return Vector2((x - y) * HALF_W, (x + y) * HALF_H)


## Exact diamond picking: inverse of tile_to_local, then round to the nearest tile.
## A point is inside tile (x, y) iff |dx|/HALF_W + |dy|/HALF_H <= 1.
static func local_to_tile(p: Vector2) -> Vector2i:
	var fx := p.x / HALF_W
	var fy := p.y / HALF_H
	var tx := (fy + fx) * 0.5
	var ty := (fy - fx) * 0.5
	return Vector2i(floori(tx + 0.5), floori(ty + 0.5))


static func tile_polygon(x: int, y: int) -> PackedVector2Array:
	var c := tile_to_local(x, y)
	return PackedVector2Array([
		c + Vector2(0.0, -HALF_H), c + Vector2(HALF_W, 0.0),
		c + Vector2(0.0, HALF_H), c + Vector2(-HALF_W, 0.0)])


## Bounding rect of the whole map in local space.
static func map_bounds(w: int, h: int) -> Rect2:
	var left := tile_to_local(0, h - 1).x - HALF_W
	var right := tile_to_local(w - 1, 0).x + HALF_W
	var top := tile_to_local(0, 0).y - HALF_H
	var bottom := tile_to_local(w - 1, h - 1).y + HALF_H
	return Rect2(left, top, right - left, bottom - top)
