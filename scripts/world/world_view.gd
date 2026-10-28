class_name WorldView
extends Node2D
## Visual layer for a WorldState. Owns no simulation data.
## Colors are cached per tile; refresh() recomputes them and only marks the chunks
## whose quantized color actually changed for redraw (no per-frame full-map redraw).

const CHUNK := 8

const BASE_COLORS := [
	Color(0.10, 0.25, 0.48), # deep water
	Color(0.20, 0.47, 0.66), # shallow water
	Color(0.86, 0.80, 0.56), # beach
	Color(0.52, 0.70, 0.36), # lowland
	Color(0.40, 0.64, 0.28), # grassland
	Color(0.18, 0.45, 0.20), # forest
	Color(0.55, 0.50, 0.40), # hills
]

var world: WorldState
var tile_colors := PackedColorArray()
var _keys := PackedInt64Array()
var _dirty := PackedByteArray()
var _chunks: Array[WorldChunk] = []
var _chunks_x := 0
var highlight: TileHighlight


func _ready() -> void:
	highlight = TileHighlight.new()
	highlight.z_index = 10
	add_child(highlight)


func set_world(ws: WorldState) -> void:
	world = ws
	for c in _chunks:
		c.queue_free()
	_chunks.clear()
	var n := ws.tile_count()
	tile_colors.resize(n)
	_keys.resize(n)
	_keys.fill(-1)
	_chunks_x = ceili(ws.width / float(CHUNK))
	var chunks_y := ceili(ws.height / float(CHUNK))
	_dirty.resize(_chunks_x * chunks_y)
	for cy in chunks_y:
		for cx in _chunks_x:
			var c := WorldChunk.new()
			c.view = self
			c.x0 = cx * CHUNK
			c.y0 = cy * CHUNK
			c.x1 = mini(c.x0 + CHUNK, ws.width)
			c.y1 = mini(c.y0 + CHUNK, ws.height)
			add_child(c)
			_chunks.append(c)
	move_child(highlight, -1)
	refresh(true)


## Recompute tile colors; returns how many chunks were queued for redraw.
func refresh(force: bool = false) -> int:
	if world == null:
		return 0
	_dirty.fill(0)
	var w := world.width
	var n := world.tile_count()
	for i in n:
		var c := color_for(i)
		var k := c.to_rgba32()
		if force or k != _keys[i]:
			_keys[i] = k
			tile_colors[i] = c
			@warning_ignore("integer_division")
			var ci := ((i / w) / CHUNK) * _chunks_x + (i % w) / CHUNK
			_dirty[ci] = 1
	var redrawn := 0
	for ci in _dirty.size():
		if _dirty[ci] == 1:
			_chunks[ci].queue_redraw()
			redrawn += 1
	return redrawn


const BARE_SOIL := Color(0.58, 0.45, 0.30)
const RIVER := Color(0.22, 0.52, 0.78)
const MUD := Color(0.55, 0.42, 0.25)


func color_for(i: int) -> Color:
	var t: int = world.land_type[i]
	var c: Color = BASE_COLORS[t]
	# Elevation shading, quantized to 16 steps so colors stay stable.
	var e := snappedf(world.elevation[i], 1.0 / 16.0)
	if LandType.is_water(t):
		c = c.lightened(clampf(e * 0.9, 0.0, 0.4))
		var mud := snappedf(clampf(world.sediment[i] * 12.0, 0.0, 0.85), 0.125)
		if mud > 0.0:
			c = c.lerp(MUD, mud)
		return c
	if t != LandType.BEACH:
		var bare := snappedf(clampf((0.35 - world.vegetation_cover[i]) / 0.35, 0.0, 1.0), 0.125)
		if bare > 0.0:
			c = c.lerp(BARE_SOIL, bare * 0.8)
	c = c.darkened(0.25 - e * 0.35) if e < 0.7 else c.lightened((e - 0.7) * 0.9)
	var wet := snappedf(clampf((world.flow[i] - 0.07) / 0.2, 0.0, 0.85), 0.1)
	if wet >= 0.1:
		var river := RIVER.lerp(MUD, snappedf(clampf(world.sediment[i] * 6.0, 0.0, 0.7), 0.1))
		c = c.lerp(river, wet)
	return c


## Small placeholder decorations drawn on top of a tile (trees on forest tiles).
func draw_tile_decor(canvas: CanvasItem, x: int, y: int, i: int) -> void:
	if world.land_type[i] == LandType.FOREST:
		var c := Iso.tile_to_local(x, y)
		var tree := Color(0.08, 0.28, 0.12)
		canvas.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-8, 4), c + Vector2(0, -12), c + Vector2(8, 4)]), tree)
