class_name WorldView
extends Node2D
## Visual layer for a WorldState: a diorama of raised terrain blocks over one animated water
## quad. Owns no simulation data.
## refresh() recomputes a compact visual key per tile (top colour + decoration state) and
## only marks chunks whose key changed for redraw. Wind sway, flame flicker and water motion
## run on the GPU (shaders/world.gdshader, shaders/water.gdshader), so idle frames cost
## nothing on the CPU.

const CHUNK := 8
const WORLD_SHADER := preload("res://shaders/world.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

## Raised land: a smooth surface BASE_H px above the water line at the shore, rising with
## (smoothed) elevation by RELIEF px per unit. Every tile corner is shared by its four tiles,
## so neighbouring tops meet exactly and the island reads as soft rolling ground; only the
## shore gets a vertical bank down to the sea.
const BASE_H := 6.0
const RELIEF := 72.0
const MAX_H := BASE_H + RELIEF * (1.0 - IslandGenerator.SHALLOW_MAX)

const SWAY := Color(1, 1, 1, 254.0 / 255.0)
const FLICKER := Color(1, 1, 1, 253.0 / 255.0)

## Muted, soft palette (tops).
const BASE_COLORS := [
	Color("2e5e7a"), # deep water (overlay only)
	Color("5fa7b5"), # shallow water (overlay only)
	Color("e6d6ad"), # beach
	Color("a6bf78"), # lowland
	Color("8fb46a"), # grassland
	Color("6f9a58"), # forest floor
	Color("a3a684"), # hills
]
const SIDE_SOIL := Color("8a6a4c")
const SIDE_SAND := Color("c9b48a")
const SIDE_ROCK := Color("8f8676")
const BARE_SOIL := Color("b39673")
const ASH := Color("5a4f47")
const RIVER := Color("6fb2c2")
const MUD := Color("9c7a52")
const FIELD := Color("9a7650")
const FIELD_WET := Color("7f6142")
const PLAZA := Color("cdbf9f")

enum Overlay { NONE, MOISTURE, VEGETATION, SOIL, WATER }
const OVERLAY_NAMES := ["Normal", "Moisture", "Plants", "Soil", "Water & mud"]
const OVERLAY_LOW := Color(0.93, 0.89, 0.78)
const OVERLAY_HIGH := {
	Overlay.MOISTURE: Color(0.16, 0.42, 0.78),
	Overlay.VEGETATION: Color(0.20, 0.50, 0.24),
	Overlay.SOIL: Color(0.45, 0.30, 0.15),
	Overlay.WATER: Color(0.20, 0.50, 0.85),
}
## Colour-blind-safe ramps (viridis-like) used when the colour-blind setting is on.
const CB_LOW := Color(0.99, 0.91, 0.15)
const CB_HIGH := Color(0.27, 0.00, 0.33)

var world: WorldState
var events: EventLog
var overlay: int = Overlay.NONE
var colorblind := false
var banner_color := Color("2f7d6d")  ## cosmetic flag over the settlement (Journal → Banners)
var tile_colors := PackedColorArray()
var heights := PackedFloat32Array()
var down := PackedInt32Array()
var _keys := PackedInt64Array()
var _deco := PackedInt32Array()
var _dirty := PackedByteArray()
var _chunks: Array[WorldChunk] = []
var _chunks_x := 0
var _cottage_rank := PackedInt32Array()
var corner_h := PackedFloat32Array()   ## (w+1)*(h+1) surface heights at tile corners
var _shade := PackedFloat32Array()     ## per-corner light factor from the local slope
var _corner_fill := PackedByteArray()  ## per water tile: concave shore corners to fill
var _cur := PackedVector2Array()       ## top face of the tile being drawn
var highlight: TileHighlight
var water: Node2D
var _water_mat: ShaderMaterial
var _world_mat: ShaderMaterial
var _data_img: Image
var _data_tex: ImageTexture
var _data_bytes := PackedByteArray()


func _ready() -> void:
	_world_mat = ShaderMaterial.new()
	_world_mat.shader = WORLD_SHADER
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = WATER_SHADER
	water = Node2D.new()
	water.name = "Water"
	water.material = _water_mat
	water.z_index = -1
	water.draw.connect(_draw_water)
	add_child(water)
	highlight = TileHighlight.new()
	highlight.view = self
	highlight.z_index = 10
	add_child(highlight)


## Reduce-motion turns wind sway, flicker and wave motion off.
func set_motion(on: bool) -> void:
	if _world_mat != null:
		_world_mat.set_shader_parameter("sway_strength", 1.0 if on else 0.0)
		_water_mat.set_shader_parameter("motion", 1.0 if on else 0.0)


func set_wind(w: float) -> void:
	if _world_mat != null:
		_world_mat.set_shader_parameter("wind", w)


func set_world(ws: WorldState, ev: EventLog = null) -> void:
	world = ws
	events = ev
	for c in _chunks:
		c.queue_free()
	_chunks.clear()
	var n := ws.tile_count()
	tile_colors.resize(n)
	_keys.resize(n)
	_keys.fill(-1)
	_deco.resize(n)
	_compute_static()
	_chunks_x = ceili(ws.width / float(CHUNK))
	var chunks_y := ceili(ws.height / float(CHUNK))
	_dirty.resize(_chunks_x * chunks_y)
	for cy in chunks_y:
		for cx in _chunks_x:
			var c := WorldChunk.new()
			c.view = self
			c.material = _world_mat
			c.x0 = cx * CHUNK
			c.y0 = cy * CHUNK
			c.x1 = mini(c.x0 + CHUNK, ws.width)
			c.y1 = mini(c.y0 + CHUNK, ws.height)
			add_child(c)
			_chunks.append(c)
	move_child(highlight, -1)
	_data_img = Image.create(ws.width, ws.height, false, Image.FORMAT_RGBA8)
	_data_tex = ImageTexture.create_from_image(_data_img)
	_data_bytes.resize(n * 4)
	if _water_mat != null:
		_water_mat.set_shader_parameter("data", _data_tex)
		_water_mat.set_shader_parameter("map_size", Vector2(ws.width, ws.height))
		water.queue_redraw()
	refresh(true)


func _compute_static() -> void:
	var w := world.width
	var n := world.tile_count()
	heights.resize(n)
	down.resize(n)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = height_for(world.land_type[i], smoothed_elevation(i))
	var cw := w + 1
	var chh := world.height + 1
	corner_h.resize(cw * chh)
	for b in chh:
		for a in cw:
			var sum := 0.0
			var cnt := 0
			var shore := false
			for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var tx: int = a + o.x
				var ty: int = b + o.y
				if not world.in_bounds(tx, ty) or LandType.is_water(world.land_type[ty * w + tx]):
					shore = true
				else:
					sum += raw[ty * w + tx]
					cnt += 1
			corner_h[b * cw + a] = 0.0 if cnt == 0 else (BASE_H if shore else sum / cnt)
	_shade.resize(cw * chh)
	for b in chh:
		for a in cw:
			var hx := corner_h[b * cw + mini(a + 1, w)]
			var hy := corner_h[mini(b + 1, world.height) * cw + a]
			var hpx := corner_h[b * cw + maxi(a - 1, 0)]
			var hpy := corner_h[maxi(b - 1, 0) * cw + a]
			# light from the upper left (map -x, a little -y): slopes facing it are brighter
			_shade[b * cw + a] = clampf(1.0 + 0.018 * ((hx - hpx) * 0.5 + (hy - hpy) * 0.2), 0.84, 1.14)
	_corner_fill.resize(n)
	_corner_fill.fill(0)
	for i in n:
		if LandType.is_water(world.land_type[i]):
			heights[i] = 0.0
			_corner_fill[i] = _concave_corners(i)
		else:
			var x := i % w
			@warning_ignore("integer_division")
			var y := i / w
			heights[i] = (corner_h[y * cw + x] + corner_h[y * cw + x + 1] + corner_h[(y + 1) * cw + x] \
				+ corner_h[(y + 1) * cw + x + 1]) * 0.25
	for i in n:
		var x := i % w
		@warning_ignore("integer_division")
		var y := i / w
		var best := -1
		var be := world.elevation[i]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if world.in_bounds(nx, ny) and world.elevation[ny * w + nx] < be:
				be = world.elevation[ny * w + nx]
				best = ny * w + nx
		down[i] = best
	# village sprawl: free land around the settlement fills with cottages as people arrive
	_cottage_rank.resize(n)
	_cottage_rank.fill(-1)
	var s := world.settlement_index
	if s >= 0:
		var sc := world.coords(s)
		var ring: Array = []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var tx: int = sc.x + dx
				var ty: int = sc.y + dy
				if (dx != 0 or dy != 0) and world.in_bounds(tx, ty) and world.land_type[ty * w + tx] > LandType.SHALLOW_WATER:
					ring.append(ty * w + tx)
		ring.sort_custom(func(a: int, b: int) -> bool: return hash_of(a, 11) < hash_of(b, 11))
		for k in ring.size():
			_cottage_rank[ring[k]] = k


static func height_for(t: int, e: float) -> float:
	if LandType.is_water(t):
		return 0.0
	return BASE_H + clampf(e - IslandGenerator.SHALLOW_MAX, 0.0, 1.0) * RELIEF


## Elevation averaged with its land neighbours (3×3), which irons out one-tile bumps and pits.
func smoothed_elevation(i: int) -> float:
	var w := world.width
	var x := i % w
	@warning_ignore("integer_division")
	var y := i / w
	var sum := world.elevation[i] * 2.0
	var cnt := 2.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and world.in_bounds(x + dx, y + dy):
				var j := (y + dy) * w + x + dx
				if not LandType.is_water(world.land_type[j]):
					sum += world.elevation[j]
					cnt += 1.0
	return sum / cnt


## Water-tile corners that sit in a notch between two land neighbours (and the land diagonal
## between them): the saw-tooth of a diagonal coastline. Filling that half-tile with a low
## bank turns the saw-tooth into one straight shore.
## Bit 0: top half (x-1, y-1), 1: right (y-1, x+1), 2: bottom (x+1, y+1), 3: left (y+1, x-1).
func _concave_corners(i: int) -> int:
	var w := world.width
	var x := i % w
	@warning_ignore("integer_division")
	var y := i / w
	var l := _is_land(x - 1, y)
	var u := _is_land(x, y - 1)
	var r := _is_land(x + 1, y)
	var d := _is_land(x, y + 1)
	if int(l) + int(u) + int(r) + int(d) >= 3:
		return 0 # an inlet or lake end: leave the water visible
	var m := 0
	if l and u and _is_land(x - 1, y - 1):
		m |= 1
	if u and r and _is_land(x + 1, y - 1):
		m |= 2
	if r and d and _is_land(x + 1, y + 1):
		m |= 4
	if d and l and _is_land(x - 1, y + 1):
		m |= 8
	return m


func _is_land(x: int, y: int) -> bool:
	return world.in_bounds(x, y) and not LandType.is_water(world.land_type[y * world.width + x])


static func hash_of(i: int, salt: int) -> int:
	var h := (i * 73856093) ^ (salt * 19349663) ^ 0x5bd1e995
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return (h ^ (h >> 16)) & 0x7fffffff


## Recompute visuals; returns how many chunks were queued for redraw.
func refresh(force: bool = false) -> int:
	if world == null:
		return 0
	_dirty.fill(0)
	var w := world.width
	var n := world.tile_count()
	for i in n:
		var c := color_for(i)
		var d := deco_key(i)
		var k := (int(c.to_rgba32()) & 0xffffffff) | (d << 32)
		if force or k != _keys[i]:
			_keys[i] = k
			_deco[i] = d
			tile_colors[i] = c
			@warning_ignore("integer_division")
			var ci := ((i / w) / CHUNK) * _chunks_x + (i % w) / CHUNK
			_dirty[ci] = 1
			if _corner_fill.size() == n and LandType.is_water(world.land_type[i]) == false:
				# shore fills borrow a land neighbour's colour: redraw neighbouring chunks too
				for j in [i - 1, i + 1, i - w, i + w]:
					if j >= 0 and j < n and _corner_fill[j] != 0:
						@warning_ignore("integer_division")
						_dirty[((j / w) / CHUNK) * _chunks_x + (j % w) / CHUNK] = 1
	var redrawn := 0
	for ci in _dirty.size():
		if _dirty[ci] == 1:
			_chunks[ci].queue_redraw()
			redrawn += 1
	_update_water_data()
	return redrawn


func _update_water_data() -> void:
	if _data_img == null:
		return
	var n := world.tile_count()
	var lt := world.land_type
	var mud_boost := 1.6 if overlay == Overlay.WATER else 1.0
	for i in n:
		var t: int = lt[i]
		var o := i * 4
		var land := t > LandType.SHALLOW_WATER
		_data_bytes[o] = 255 if land else 0
		var mud := 0.0
		if not land:
			mud = clampf(world.sediment[i] * 10.0 * mud_boost, 0.0, 0.85)
		_data_bytes[o + 1] = int(mud * 255.0)
		_data_bytes[o + 2] = 0 if land else int(clampf(1.0 - world.elevation[i] / IslandGenerator.SHALLOW_MAX, 0.0, 1.0) * 255.0)
		_data_bytes[o + 3] = 255
	_data_img.set_data(world.width, world.height, false, Image.FORMAT_RGBA8, _data_bytes)
	_data_tex.update(_data_img)


func set_overlay(o: int) -> void:
	overlay = o
	if _water_mat != null:
		_water_mat.set_shader_parameter("overlay_mud", 1.0 if o == Overlay.WATER else 0.0)
	refresh()


func set_banner(c: Color) -> void:
	if c == banner_color:
		return
	banner_color = c
	if world != null:
		refresh(true)


func set_colorblind(on: bool) -> void:
	colorblind = on
	refresh(true)


## Heat-map colour for the active overlay (quantized to 10 steps).
func overlay_color(i: int) -> Color:
	var t: int = world.land_type[i]
	if LandType.is_water(t):
		var sea := Color(0.30, 0.45, 0.55)
		if overlay == Overlay.WATER:
			sea = sea.lerp(MUD, snappedf(clampf(world.sediment[i] * 12.0, 0.0, 1.0), 0.1))
		return sea
	var v := 0.0
	match overlay:
		Overlay.MOISTURE: v = world.soil_moisture[i]
		Overlay.VEGETATION: v = world.vegetation_cover[i]
		Overlay.SOIL: v = world.soil_depth[i]
		Overlay.WATER: v = clampf(world.flow[i] / 0.25, 0.0, 1.0)
	var lo := CB_LOW if colorblind else OVERLAY_LOW
	var hi: Color = CB_HIGH if colorblind else OVERLAY_HIGH[overlay]
	var c := lo.lerp(hi, snappedf(v, 0.1))
	if overlay == Overlay.WATER and not colorblind:
		c = c.lerp(MUD, snappedf(clampf(world.sediment[i] * 6.0, 0.0, 0.7), 0.1))
	return c


func is_burnt(i: int) -> bool:
	if events == null or world.land_cause[i] < 0:
		return false
	return events.type_of(world.land_cause[i]) == EventLog.Type.WILDFIRE and world.vegetation_cover[i] < 0.35


func color_for(i: int) -> Color:
	if overlay != Overlay.NONE:
		return overlay_color(i)
	var t: int = world.land_type[i]
	var c: Color = BASE_COLORS[t]
	if LandType.is_water(t):
		return c
	var st: int = world.structure[i]
	if st == WorldState.Structure.FARM:
		return FIELD_WET.lerp(FIELD, 0.5) if world.soil_moisture[i] > 0.5 else FIELD
	if st == WorldState.Structure.SETTLEMENT or st == WorldState.Structure.HOUSE:
		return PLAZA
	if is_burnt(i):
		return ASH.lerp(c, snappedf(clampf(world.vegetation_cover[i] / 0.35, 0.0, 1.0), 0.25) * 0.6)
	if t == LandType.HILLS:
		c = c.lerp(BASE_COLORS[LandType.GRASSLAND].darkened(0.05), snappedf(clampf(world.vegetation_cover[i], 0.0, 0.8), 0.1) * 0.75)
	elif t != LandType.BEACH:
		var bare := snappedf(clampf((0.4 - world.vegetation_cover[i]) / 0.4, 0.0, 1.0), 0.125)
		if bare > 0.0:
			c = c.lerp(BARE_SOIL, bare * 0.85)
		var lush := snappedf(clampf((world.vegetation_cover[i] - 0.6) / 0.4, 0.0, 1.0), 0.25)
		c = c.darkened(lush * 0.08)
	# higher ground is a touch lighter (soft aerial light)
	var lv := (heights[i] - BASE_H) / (MAX_H - BASE_H) if heights.size() > i else 0.0
	return c.lightened(lv * 0.10)


## Everything about a tile's decoration that can change at runtime, packed in 31 bits.
func deco_key(i: int) -> int:
	var t: int = world.land_type[i]
	if LandType.is_water(t):
		return 0
	var k := world.structure[i]                                   # 3 bits
	var crop := 0
	if k == WorldState.Structure.FARM:
		var g := world.crop_growth[i]
		crop = 0 if g < 0.06 else (1 if g < 0.35 else (2 if g < 0.8 else 3))
		if world.crop_stress[i] > 0 and crop > 0:
			crop = 4
	k |= crop << 3                                                 # 3 bits
	k |= mini(3, int(world.vegetation_cover[i] * 4.0)) << 6        # 2 bits
	k |= (1 if world.fire[i] != 0 else 0) << 8
	k |= (1 if is_burnt(i) else 0) << 9
	var fl := world.flow[i]
	var river := 0 if fl < 0.07 else (1 if fl < 0.15 else (2 if fl < 0.3 else 3))
	k |= river << 10                                               # 2 bits
	k |= int(clampf(world.sediment[i] * 6.0, 0.0, 0.7) * 10.0) << 12  # 3 bits
	k |= mini(3, int(world.reservoir[i] * 6.0)) << 15              # 2 bits
	var flooded := world.tick - world.flood_tick[i] < 6 \
		or (world.structure[i] != WorldState.Structure.NONE and world.structure[i] != WorldState.Structure.DAM \
		and world.surface_water[i] >= Simulation.FLOOD_DEPTH * 0.6)
	k |= (1 if flooded else 0) << 17
	if _cottage_rank.size() > i and _cottage_rank[i] >= 0:
		k |= (1 if _cottage_rank[i] < cottages_wanted() else 0) << 18
	if t == LandType.GRASSLAND or t == LandType.LOWLAND:
		k |= (1 if hash_of(i, 5) % 1000 < int(world.goats * 6.0) else 0) << 19
	k |= (1 if world.peak_villagers >= 20 else 0) << 20
	# inflowing streams from neighbours
	var w := world.width
	var bit := 21
	for j in [i - 1, i + 1, i - w, i + w]:
		if j >= 0 and j < world.tile_count() and down[j] == i and world.flow[j] >= 0.07:
			k |= 1 << bit
		bit += 1
	k |= (1 if overlay != Overlay.NONE else 0) << 25
	return k


func cottages_wanted() -> int:
	@warning_ignore("integer_division")
	return clampi((world.villagers - 6) / 3, 0, 8)


# ------------------------------------------------------------------ drawing

func _draw_water() -> void:
	if world == null:
		return
	var b := Iso.map_bounds(world.width, world.height).grow(4000.0)  # deep enough for the zoomed-out title-menu framing
	water.draw_rect(b, Color.WHITE)


func top_center(x: int, y: int) -> Vector2:
	return Iso.tile_to_local(x, y) - Vector2(0, heights[y * world.width + x])


## Screen position of tile corner (a, b) on the surface: corner (x, y) is the top (north)
## vertex of tile (x, y); its other vertices are corners (x+1, y), (x+1, y+1) and (x, y+1).
func corner_point(a: int, b: int) -> Vector2:
	return Iso.tile_to_local(a, b) - Vector2(0, Iso.HALF_H + _ch(a, b))


## The tile's top face as drawn (N, E, S, W), following the slope. Water tiles are flat.
func top_polygon(x: int, y: int) -> PackedVector2Array:
	if world == null or LandType.is_water(world.land_type[y * world.width + x]):
		return Iso.tile_polygon(x, y)
	return PackedVector2Array([corner_point(x, y), corner_point(x + 1, y), corner_point(x + 1, y + 1), corner_point(x, y + 1)])


func _ch(a: int, b: int) -> float:
	return corner_h[b * (world.width + 1) + a] if corner_h.size() > 0 else 0.0


func _lit(k: int) -> Color:
	var f := _shade[k]
	return Color(f, f, f, 1.0)


## Height-aware picking: the front-most tile whose raised block contains the point.
func pick(p: Vector2) -> Vector2i:
	var flat := Iso.local_to_tile(p)
	if world == null:
		return flat
	var best := Vector2i(-1, -1)
	var best_d := -1
	for k in range(0, 9):
		for off in [Vector2i(k, k), Vector2i(k + 1, k), Vector2i(k, k + 1)]:
			var t: Vector2i = flat + off
			if not world.in_bounds(t.x, t.y):
				continue
			var c := Iso.tile_to_local(t.x, t.y)
			var h := heights[t.y * world.width + t.x]
			var dx := absf(p.x - c.x)
			if dx > Iso.HALF_W:
				continue
			var top := c.y - h - Iso.HALF_H + dx * 0.5
			var bottom := c.y + Iso.HALF_H - dx * 0.5
			if p.y >= top and p.y <= bottom and t.x + t.y > best_d:
				best_d = t.x + t.y
				best = t
	if best.x < 0:
		return flat if not world.in_bounds(flat.x, flat.y) else best
	return best


func draw_tile(cv: CanvasItem, x: int, y: int) -> void:
	var w := world.width
	var i := y * w + x
	var t: int = world.land_type[i]
	if LandType.is_water(t):
		if overlay != Overlay.NONE:
			cv.draw_colored_polygon(Iso.tile_polygon(x, y), tile_colors[i] * Color(1, 1, 1, 0.55))
		elif _corner_fill.size() > i and _corner_fill[i] != 0:
			_draw_corner_fill(cv, x, y, i)
		return
	var h := heights[i]
	var c := Iso.tile_to_local(x, y)
	var top := c - Vector2(0, h)
	var cw := w + 1
	var nn := corner_point(x, y)
	var ne := corner_point(x + 1, y)
	var ns := corner_point(x + 1, y + 1)
	var nw := corner_point(x, y + 1)
	_cur = PackedVector2Array([nn, ne, ns, nw])
	var col := tile_colors[i]
	var side := SIDE_SAND if t == LandType.BEACH else (SIDE_ROCK if t == LandType.HILLS else SIDE_SOIL)
	# banks only at the shore and map edge; inland tiles share corners, so they meet seamlessly
	if y + 1 >= world.height or LandType.is_water(world.land_type[i + w]):
		cv.draw_polygon(PackedVector2Array([nw, ns, ns + Vector2(0, _ch(x + 1, y + 1)), nw + Vector2(0, _ch(x, y + 1))]),
			PackedColorArray([side.darkened(0.08), side.darkened(0.12), side.darkened(0.42), side.darkened(0.38)]))
		cv.draw_colored_polygon(PackedVector2Array([nw, ns, ns + Vector2(0, 2.0), nw + Vector2(0, 2.0)]), col.darkened(0.22))
	if x + 1 >= w or LandType.is_water(world.land_type[i + 1]):
		cv.draw_polygon(PackedVector2Array([ns, ne, ne + Vector2(0, _ch(x + 1, y)), ns + Vector2(0, _ch(x + 1, y + 1))]),
			PackedColorArray([side.darkened(0.30), side.darkened(0.26), side.darkened(0.55), side.darkened(0.58)]))
		cv.draw_colored_polygon(PackedVector2Array([ns, ne, ne + Vector2(0, 2.0), ns + Vector2(0, 2.0)]), col.darkened(0.36))
	# top: per-vertex colour variation and slope light, both shared with neighbours => seamless
	cv.draw_polygon(_cur, PackedColorArray([
		_vary(col, x, y) * _lit(y * cw + x), _vary(col, x + 1, y) * _lit(y * cw + x + 1),
		_vary(col, x + 1, y + 1) * _lit((y + 1) * cw + x + 1), _vary(col, x, y + 1) * _lit((y + 1) * cw + x)]))
	if overlay != Overlay.NONE:
		_draw_structure(cv, i, top)
		return
	var deco := _deco[i]
	var reservoir := (deco >> 15) & 3
	if reservoir > 0:
		var a := 0.35 + 0.18 * reservoir
		cv.draw_colored_polygon(_inset(top, 0.82), Color(RIVER, a).lerp(Color(MUD, a), world.sediment[i] * 4.0))
	_draw_streams(cv, x, y, i, top, deco)
	_draw_structure(cv, i, top)
	if (deco >> 17) & 1:
		_draw_floodwater(cv, i, top)
	_draw_nature(cv, x, y, i, top, deco)


## Fills a notch in a diagonal coastline with a low half-tile bank of the neighbour's ground,
## so shorelines read as straight runs instead of a saw-tooth of diamonds.
func _draw_corner_fill(cv: CanvasItem, x: int, y: int, i: int) -> void:
	var w := world.width
	var m := _corner_fill[i]
	var pairs := [i - 1, i - w, i + 1, i + w]
	var nn := corner_point(x, y)
	var ne := corner_point(x + 1, y)
	var ns := corner_point(x + 1, y + 1)
	var nw := corner_point(x, y + 1)
	for k in 4:
		if (m >> k) & 1 == 0:
			continue
		var col := tile_colors[pairs[k]]
		var tri: PackedVector2Array
		match k:
			0: tri = PackedVector2Array([nw, nn, ne])
			1: tri = PackedVector2Array([nn, ne, ns])
			2: tri = PackedVector2Array([ne, ns, nw])
			_: tri = PackedVector2Array([ns, nw, nn])
		if k == 0: # this long edge faces the viewer: a sandy bank down to the water
			var dv := Vector2(0, BASE_H)
			cv.draw_polygon(PackedVector2Array([nw, ne, ne + dv, nw + dv]), PackedColorArray([
				SIDE_SAND.darkened(0.10), SIDE_SAND.darkened(0.28), SIDE_SAND.darkened(0.5), SIDE_SAND.darkened(0.4)]))
			cv.draw_colored_polygon(PackedVector2Array([nw, ne, ne + Vector2(0, 2.0), nw + Vector2(0, 2.0)]), col.darkened(0.22))
		cv.draw_colored_polygon(tri, col)


## Standing floodwater: a murky sheet drawn over whatever is built here, with a few ripples.
func _draw_floodwater(cv: CanvasItem, i: int, top: Vector2) -> void:
	var muddy := Color(0.34, 0.66, 0.84, 0.86).lerp(Color(MUD, 0.86), clampf(world.sediment[i] * 3.0, 0.0, 0.6))
	cv.draw_colored_polygon(_inset(top, 0.94), muddy)
	var hi := Color(0.86, 0.93, 0.95, 0.55)
	for k in 3:
		var o := Vector2((hash_of(i, 11 + k) % 100 - 50) * 0.28, (hash_of(i, 21 + k) % 100 - 50) * 0.12)
		var c := top + o
		cv.draw_line(c - Vector2(7, 0), c + Vector2(7, 0), hi, 1.5, true)


func _vary(col: Color, vx: int, vy: int) -> Color:
	var v := (hash_of(vx * 977 + vy * 131, 3) % 1000) / 1000.0 - 0.5
	return col.lightened(v * 0.07) if v > 0.0 else col.darkened(-v * 0.07)


## The current tile's top face shrunk toward its centre (so it follows the slope).
func _inset(top: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _cur:
		out.append(top + (p - top) * s)
	return out


func _stream_color(i: int) -> Color:
	return RIVER.lerp(MUD, clampf(world.sediment[i] * 6.0, 0.0, 0.8))


## Streams are smooth ribbons through the tile centre (inflow edge -> centre -> outflow edge,
## bent as a quadratic Bezier) over a soft darker bank and under a thin glint, so a river reads
## as one continuous channel rather than straight dashes along the tile seams. Edge points sit
## on the sloped surface, so channels follow the ground.
func _draw_streams(cv: CanvasItem, x: int, y: int, i: int, top: Vector2, deco: int) -> void:
	var river := (deco >> 10) & 3
	var w := world.width
	var col := _stream_color(i)
	var width := 1.4 + river * 1.6
	var has_out := river > 0 and down[i] >= 0
	var out_pt := top
	var dj := Vector2i.ZERO
	if has_out:
		dj = world.coords(down[i]) - Vector2i(x, y)
		out_pt = _edge_mid(x, y, dj)
	var ins: Array[Vector2] = []
	var in_w: Array[float] = []
	var nb := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for k in 4:
		if (deco >> (21 + k)) & 1:
			var o: Vector2i = nb[k]
			var fl := world.flow[(y + o.y) * w + x + o.x]
			ins.append(_edge_mid(x, y, o))
			in_w.append(3.0 if fl < 0.15 else (4.6 if fl < 0.3 else 6.2))
	if not has_out and ins.is_empty():
		return
	# a gentle per-tile meander keeps long straight runs from looking ruled
	var bend := top + Vector2(float(hash_of(i, 31) % 13) - 6.0, float(hash_of(i, 37) % 7) - 3.0)
	var paths: Array[PackedVector2Array] = []
	var widths: Array[float] = []
	if ins.is_empty():
		paths.append(_bezier(top, bend, out_pt))
		widths.append(width)
	for k in ins.size():
		paths.append(_bezier(ins[k], bend, out_pt if has_out else top))
		widths.append(maxf(in_w[k], width) if has_out else in_w[k])
	var bank := Color(col.darkened(0.4), 0.28)
	if river <= 1 and ins.size() <= 1:
		col = Color(col, 0.8) # a seasonal rivulet: lighter than a real stream
	for k in paths.size():
		cv.draw_polyline(paths[k], bank, widths[k] + 3.0, true)
	for k in paths.size():
		cv.draw_polyline(paths[k], col, widths[k], true)
	for k in paths.size():
		cv.draw_polyline(paths[k], Color(1, 1, 1, 0.22), maxf(widths[k] * 0.3, 1.0), true)
	# a stream leaving over the shore bank falls into the sea with a little splash
	if has_out and (dj == Vector2i(1, 0) or dj == Vector2i(0, 1)) and LandType.is_water(world.land_type[down[i]]):
		var foot := out_pt + Vector2(0, BASE_H)
		cv.draw_line(out_pt, foot, col.lightened(0.15), width + 1.0)
		cv.draw_circle(foot, width * 0.7, Color(1, 1, 1, 0.45))


## Midpoint of the edge of tile (x, y) facing neighbour offset o, on the surface.
func _edge_mid(x: int, y: int, o: Vector2i) -> Vector2:
	var a: Vector2
	var b: Vector2
	if o == Vector2i(1, 0):
		a = corner_point(x + 1, y); b = corner_point(x + 1, y + 1)
	elif o == Vector2i(-1, 0):
		a = corner_point(x, y); b = corner_point(x, y + 1)
	elif o == Vector2i(0, 1):
		a = corner_point(x, y + 1); b = corner_point(x + 1, y + 1)
	else:
		a = corner_point(x, y); b = corner_point(x + 1, y)
	return (a + b) * 0.5


static func _bezier(a: Vector2, c: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for s in 7:
		var t := s / 6.0
		pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return pts


func sprite(cv: CanvasItem, name: String, at: Vector2, mod: Color = Color.WHITE, s: float = 1.0) -> void:
	var r: Array = ArtAtlas.R[name]
	var sz := Vector2(r[2], r[3]) / ArtAtlas.SCALE * s
	var anchor := Vector2(r[4], r[5]) / ArtAtlas.SCALE * s
	cv.draw_texture_rect_region(ArtAtlas.TEXTURE, Rect2(at - anchor, sz), Rect2(r[0], r[1], r[2], r[3]), mod)


func _draw_structure(cv: CanvasItem, i: int, top: Vector2) -> void:
	var st: int = world.structure[i]
	match st:
		WorldState.Structure.SETTLEMENT:
			sprite(cv, "well", top + Vector2(-14, 4))
			sprite(cv, "hall", top + Vector2(4, 0))
			sprite(cv, "stall", top + Vector2(-2, 11))
			# banner flag: a thin pole and pennant in the player's chosen colour
			var pole := top + Vector2(17, 2)
			cv.draw_line(pole, pole + Vector2(0, -24), Color("4a3b2c"), 1.5, true)
			cv.draw_colored_polygon(PackedVector2Array([pole + Vector2(0.5, -24), pole + Vector2(13, -20.5),
				pole + Vector2(0.5, -16)]), banner_color)
			cv.draw_polyline(PackedVector2Array([pole + Vector2(0.5, -24), pole + Vector2(13, -20.5),
				pole + Vector2(0.5, -16)]), banner_color.darkened(0.35), 1.0, true)
		WorldState.Structure.HOUSE:
			var big := world.peak_villagers >= 20 and hash_of(i, 2) % 2 == 0
			if big:
				sprite(cv, "house_big", top + Vector2(0, 2))
			else:
				sprite(cv, ["cottage", "cottage_b", "cottage_c"][hash_of(i, 2) % 3], top + Vector2(-8, -2))
				sprite(cv, ["cottage_c", "cottage", "cottage_b"][hash_of(i, 4) % 3], top + Vector2(8, 5))
		WorldState.Structure.DAM:
			var j := down[i]
			var along_x := j >= 0 and absi(j - i) == 1
			sprite(cv, "dam_x" if along_x else "dam_y", top + Vector2(0, 2))
		WorldState.Structure.FARM:
			_draw_farm(cv, i, top)


const CROPS := ["", "crop_sprout", "crop_green", "crop_ripe", "crop_dry"]


func _draw_farm(cv: CanvasItem, i: int, top: Vector2) -> void:
	var furrow := Color(0.32, 0.22, 0.13, 0.35)
	for k in range(-2, 3):
		var o := Vector2(k * 8.0, k * 4.0)
		cv.draw_line(top + o + Vector2(-13, -6.5) * (1.0 - absf(k) * 0.22), top + o + Vector2(13, 6.5) * (1.0 - absf(k) * 0.22), furrow, 1.6)
	var crop := (_deco[i] >> 3) & 7
	if crop == 0 or overlay != Overlay.NONE:
		return
	var nm: String = CROPS[crop]
	for b in range(-2, 3):
		for a in range(-2, 3):
			if absi(a) + absi(b) > 3:
				continue
			var p := top + Vector2((a - b) * 5.2, (a + b) * 2.6 + 1.0)
			sprite(cv, nm, p, SWAY)


## Slots for decoration inside a tile, back to front (top-relative).
const SLOTS := [Vector2(0, -8), Vector2(-12, -2), Vector2(12, -2), Vector2(-3, 1), Vector2(6, 5), Vector2(-7, 6), Vector2(1, 9)]


func _draw_nature(cv: CanvasItem, x: int, y: int, i: int, top: Vector2, deco: int) -> void:
	var st: int = world.structure[i]
	if st == WorldState.Structure.FARM or st == WorldState.Structure.DAM or st == WorldState.Structure.SETTLEMENT or st == WorldState.Structure.HOUSE:
		if (deco >> 8) & 1:
			sprite(cv, "fire_a", top + Vector2(0, 2), FLICKER)
		return
	var t: int = world.land_type[i]
	var veg := (deco >> 6) & 3
	var burning := (deco >> 8) & 1 == 1
	var burnt := (deco >> 9) & 1 == 1
	var cottage := (deco >> 18) & 1 == 1
	var goat := (deco >> 19) & 1 == 1
	var hsh := hash_of(i, 7)
	var items: Array = [] # [slot_index, name, modulate]
	if cottage:
		items.append([0, ["cottage", "cottage_b", "cottage_c"][hsh % 3], Color.WHITE])
		items.append([5, "tuft", SWAY])
	elif t == LandType.FOREST:
		var count := 1 + mini(veg, 2) + (1 if veg >= 3 else 0)
		var pine := world.elevation[i] > 0.55 or hsh % 3 == 0
		var names := ["pine_a", "pine_b", "pine_c"] if pine else ["oak_a", "oak_c", "oak_b"]
		for k in count:
			var slot := (hsh >> (k * 3)) % SLOTS.size()
			var nm: String = names[(hsh >> (k * 2 + 1)) % 3]
			if burnt or burning:
				nm = "snag"
			items.append([slot, nm, SWAY])
		if veg >= 2 and hsh % 4 == 0:
			items.append([(hsh >> 9) % SLOTS.size(), "bush", SWAY])
	elif t == LandType.HILLS:
		items.append([hsh % SLOTS.size(), "rock_a" if hsh % 2 == 0 else "rock_b", Color.WHITE])
		if veg >= 1:
			items.append([(hsh >> 4) % SLOTS.size(), "tuft", SWAY])
		if veg >= 2 and hsh % 3 == 0:
			items.append([(hsh >> 6) % SLOTS.size(), "pine_c", SWAY])
	elif t == LandType.BEACH:
		if hsh % 5 == 0:
			items.append([hsh % SLOTS.size(), "rock_b", Color.WHITE])
		elif (deco >> 10) & 3 > 0 or hsh % 7 == 0:
			items.append([(hsh >> 3) % SLOTS.size(), "reeds", SWAY])
	else:
		if burnt:
			pass
		elif veg >= 3 and hsh % 3 == 0:
			items.append([hsh % SLOTS.size(), "bush", SWAY])
		elif veg >= 2 and world.land_cause[i] >= 0 and events != null and events.type_of(world.land_cause[i]) == EventLog.Type.TREES_PLANTED:
			items.append([1, "sapling", SWAY])
			items.append([4, "sapling", SWAY])
		if veg >= 1:
			items.append([(hsh >> 5) % SLOTS.size(), "tuft", SWAY])
		if veg >= 2:
			items.append([(hsh >> 8) % SLOTS.size(), "flowers" if hsh % 2 == 0 else "tuft", SWAY])
		if (deco >> 10) & 3 > 0 and hsh % 2 == 0:
			items.append([6, "reeds", SWAY])
	if t == LandType.FOREST and world.land_cause[i] >= 0 and events != null and events.type_of(world.land_cause[i]) == EventLog.Type.TREES_PLANTED and veg < 2:
		items = [[1, "sapling", SWAY], [4, "sapling", SWAY], [6, "sapling", SWAY]]
	if goat:
		items.append([(hsh >> 11) % SLOTS.size(), "goat" if hsh % 3 else "goat_b", Color.WHITE])
	if burning:
		items.append([3, "fire_a", FLICKER])
		items.append([1, "fire_b", FLICKER])
	items.sort_custom(func(a: Array, b: Array) -> bool: return SLOTS[a[0]].y < SLOTS[b[0]].y)
	var used := {}
	for it in items:
		var s: int = it[0]
		var jitter := Vector2(((hsh >> s) % 5) - 2, 0)
		if used.has(s):
			jitter += Vector2(3, 1)
		used[s] = true
		sprite(cv, it[1], top + SLOTS[s] + jitter, it[2])
