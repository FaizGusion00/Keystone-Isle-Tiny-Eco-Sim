class_name IslandGenerator
extends RefCounted
## Deterministic island generation. Same (seed, size) => bit-identical WorldState.
## Only seeded FastNoiseLite + seeded RandomNumberGenerator are used.

const DEEP_MAX := 0.16
const SHALLOW_MAX := 0.26
const BEACH_MAX := 0.31
const LOWLAND_MAX := 0.50
const GRASS_MAX := 0.76

## Biome presets (New World setup). TEMPERATE reproduces the original generator exactly.
enum Preset { TEMPERATE, LUSH, ARID, HIGHLANDS }
const PRESET_NAMES := ["Temperate", "Lush", "Arid", "Highlands"]
const PRESET_BLURBS := [
	"Balanced forests, meadows and a gentle rain cycle.",
	"Wet and green: dense forest, rich soil, plenty of rain.",
	"Dry grassland with few trees. Water is precious and fire is a danger.",
	"Taller, steeper island with fast streams. Good dam sites, more erosion.",
]


static func generate(world_seed: int, w: int = 32, h: int = 32, preset: int = Preset.TEMPERATE) -> WorldState:
	var ws := WorldState.new(w, h, world_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var ox := rng.randf_range(-4096.0, 4096.0)
	var oy := rng.randf_range(-4096.0, 4096.0)
	var cx := rng.randf_range(-0.08, 0.08)
	var cy := rng.randf_range(-0.08, 0.08)

	var shape := FastNoiseLite.new()
	shape.seed = world_seed & 0x7fffffff
	shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape.fractal_type = FastNoiseLite.FRACTAL_FBM
	shape.fractal_octaves = 4
	shape.frequency = 2.4 / float(w)

	var wet := FastNoiseLite.new()
	wet.seed = (world_seed + 7919) & 0x7fffffff
	wet.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wet.fractal_octaves = 2
	wet.frequency = 3.5 / float(w)

	for y in h:
		for x in w:
			var i := y * w + x
			var nx := ((x + 0.5) / w) * 2.0 - 1.0 - cx
			var ny := ((y + 0.5) / h) * 2.0 - 1.0 - cy
			var d := sqrt(nx * nx + ny * ny)
			var falloff := 1.0 - smoothstep(0.42, 1.0, d)
			var n := shape.get_noise_2d(x + ox, y + oy) * 0.5 + 0.5
			var e := clampf(falloff * (0.45 + 0.65 * n) - 0.04, 0.0, 1.0)
			var m := clampf(wet.get_noise_2d(x + ox, y + oy) * 0.5 + 0.5, 0.0, 1.0)
			match preset:
				Preset.LUSH: m = clampf(m + 0.12, 0.0, 1.0)
				Preset.ARID: m = clampf(m - 0.18, 0.0, 1.0)
				Preset.HIGHLANDS: e = clampf(e * 1.18 + 0.02 * falloff, 0.0, 1.0)
			ws.elevation[i] = e
			var t: int
			if e < DEEP_MAX:
				t = LandType.DEEP_WATER
			elif e < SHALLOW_MAX:
				t = LandType.SHALLOW_WATER
			elif e < BEACH_MAX:
				t = LandType.BEACH
			elif e < LOWLAND_MAX:
				t = LandType.FOREST if m > 0.60 else LandType.LOWLAND
			elif e < GRASS_MAX:
				t = LandType.FOREST if m > 0.52 else LandType.GRASSLAND
			else:
				t = LandType.HILLS
			ws.land_type[i] = t
			ws.soil_moisture[i] = 1.0 if LandType.is_water(t) else clampf(0.18 + 0.45 * m, 0.0, 1.0)
			ws.vegetation_cover[i] = _initial_vegetation(t, m)
			ws.soil_depth[i] = _initial_soil(t)
	_shape_drainage(ws)
	_place_settlement(ws)
	return ws


const CARVE_ITERS := 8
const CARVE_K := 0.012      ## valley incision per iteration per sqrt(catchment)
const VALLEY_PASSES := 2
const VALLEY_FALL := 0.6
const CARVE_MAX := 0.12     ## a valley never cuts deeper than this below the original ground
const FILL_EPS := 0.002     ## minimum fall per tile through a filled hollow (randomised per tile)


## Turns raw noise relief into a believable drainage network: hollows are filled so every land
## tile drains to the sea (priority-flood), then valleys are incised in proportion to sqrt(catchment)
## and re-filled, a few times over. Neighbouring runs get captured by the deeper valley, so the
## island ends up with one or two main rivers fed by tributaries instead of dozens of short parallel
## rills. Land types (coast, biomes) still come from the original relief, so the island's outline is
## unchanged; only the heights move. Deterministic: a per-tile hash, no RNG draws.
static func _shape_drainage(ws: WorldState) -> void:
	var e := ws.elevation
	var orig := e.duplicate()
	var w := ws.width
	var h := ws.height
	var salt := ws.world_seed & 0xffff
	_fill_hollows(e, w, h, salt)
	for it in CARVE_ITERS:
		var area := catchment(e, w, h)
		var cut := PackedFloat32Array()
		cut.resize(e.size())
		for i in e.size():
			cut[i] = CARVE_K * (sqrt(float(area[i])) - 1.0)
		# Widen each cut into a soft valley so neighbouring slopes lean into the channel (and
		# their runoff joins it) without leaving steep walls that would shed every drop of rain.
		for _p in VALLEY_PASSES:
			var wide := cut.duplicate()
			for y in h:
				for x in w:
					var i := y * w + x
					var m := cut[i]
					if x > 0: m = maxf(m, cut[i - 1] * VALLEY_FALL)
					if x < w - 1: m = maxf(m, cut[i + 1] * VALLEY_FALL)
					if y > 0: m = maxf(m, cut[i - w] * VALLEY_FALL)
					if y < h - 1: m = maxf(m, cut[i + w] * VALLEY_FALL)
					wide[i] = m
			cut = wide
		for i in e.size():
			if orig[i] < BEACH_MAX:
				continue
			e[i] = maxf(e[i] - cut[i], maxf(BEACH_MAX + 0.002, orig[i] - CARVE_MAX))
		_fill_hollows(e, w, h, salt)
	ws.elevation = e


## Lowest 4-neighbour each tile drains to (-1 = none lower), as used by the simulation.
static func drain_targets(e: PackedFloat32Array, w: int, h: int) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(w * h)
	for y in h:
		for x in w:
			var i := y * w + x
			var best := -1
			var be := e[i]
			if x > 0 and e[i - 1] < be: best = i - 1; be = e[i - 1]
			if x < w - 1 and e[i + 1] < be: best = i + 1; be = e[i + 1]
			if y > 0 and e[i - w] < be: best = i - w; be = e[i - w]
			if y < h - 1 and e[i + w] < be: best = i + w; be = e[i + w]
			d[i] = best
	return d


## Number of land tiles draining through each tile (1 = only itself).
static func catchment(e: PackedFloat32Array, w: int, h: int) -> PackedInt32Array:
	var d := drain_targets(e, w, h)
	var n := e.size()
	var a := PackedInt32Array()
	a.resize(n)
	a.fill(1)
	var order: Array = range(n)
	order.sort_custom(func(p: int, q: int) -> bool: return e[p] > e[q] or (e[p] == e[q] and p < q))
	for i in order:
		if d[i] >= 0 and e[i] >= SHALLOW_MAX:
			a[d[i]] += a[i]
	return a


## Priority-flood from the sea: raises every land hollow to just above its spill point, with a
## small randomised fall per tile so filled flats still drain along a natural-looking path.
static func _fill_hollows(e: PackedFloat32Array, w: int, h: int, salt: int) -> void:
	var n := e.size()
	var done := PackedByteArray()
	done.resize(n)
	var heap: Array = []
	for i in n:
		if e[i] < SHALLOW_MAX:
			done[i] = 1
			_heap_push(heap, e[i], i)
	while not heap.is_empty():
		var c: int = _heap_pop(heap)[1]
		var x := c % w
		@warning_ignore("integer_division")
		var y := c / w
		for k in 4:
			var xx := x + (-1 if k == 0 else (1 if k == 1 else 0))
			var yy := y + (-1 if k == 2 else (1 if k == 3 else 0))
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var j := yy * w + xx
			if done[j]:
				continue
			done[j] = 1
			var fall := FILL_EPS * (0.3 + 1.4 * float(((j + salt * 7919) * 2654435761) % 1000) / 1000.0)
			if e[j] < e[c] + fall:
				e[j] = e[c] + fall
			_heap_push(heap, e[j], j)


static func _heap_less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


static func _heap_push(hp: Array, v: float, i: int) -> void:
	hp.append([v, i])
	var k := hp.size() - 1
	while k > 0:
		@warning_ignore("integer_division")
		var p := (k - 1) / 2
		if not _heap_less(hp[k], hp[p]):
			break
		var t: Array = hp[k]
		hp[k] = hp[p]
		hp[p] = t
		k = p


static func _heap_pop(hp: Array) -> Array:
	var r: Array = hp[0]
	var last: Array = hp.pop_back()
	if hp.is_empty():
		return r
	hp[0] = last
	var k := 0
	while true:
		var l := 2 * k + 1
		var m := k
		if l < hp.size() and _heap_less(hp[l], hp[m]): m = l
		if l + 1 < hp.size() and _heap_less(hp[l + 1], hp[m]): m = l + 1
		if m == k:
			break
		var t: Array = hp[k]
		hp[k] = hp[m]
		hp[m] = t
		k = m
	return r


const START_VILLAGERS := 10
const START_FOOD := 20.0
const START_FISH := 80.0
const START_GOATS := 25.0


## Puts the village on the open lowland/grassland tile closest to the sea that has the most
## farmable land around it (deterministic: ties broken by lowest index).
static func _place_settlement(ws: WorldState) -> void:
	var w := ws.width
	var h := ws.height
	var best := -1
	var best_score := -1.0
	for y in h:
		for x in w:
			var i := y * w + x
			var t := ws.land_type[i]
			if t != LandType.LOWLAND and t != LandType.GRASSLAND:
				continue
			var near_sea := false
			var farmable := 0
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var xx := x + dx
					var yy := y + dy
					if not ws.in_bounds(xx, yy):
						continue
					var tt := ws.land_type[yy * w + xx]
					if absi(dx) <= 2 and absi(dy) <= 2 and LandType.is_water(tt):
						near_sea = true
					if tt == LandType.LOWLAND or tt == LandType.GRASSLAND or tt == LandType.FOREST:
						farmable += 1
			var score := farmable + (100.0 if near_sea else 0.0)
			if score > best_score:
				best_score = score
				best = i
	if best < 0:
		for i in ws.tile_count():
			if not LandType.is_water(ws.land_type[i]):
				best = i
				break
	ws.settlement_index = best
	if best >= 0:
		ws.structure[best] = WorldState.Structure.SETTLEMENT
		ws.vegetation_cover[best] = 0.2
	ws.villagers = START_VILLAGERS
	ws.food_store = START_FOOD
	ws.fish = START_FISH
	ws.goats = START_GOATS


static func _initial_vegetation(t: int, m: float) -> float:
	match t:
		LandType.FOREST: return 0.80 + 0.15 * m
		LandType.GRASSLAND: return 0.40 + 0.2 * m
		LandType.LOWLAND: return 0.30 + 0.2 * m
		LandType.HILLS: return 0.20 + 0.15 * m
		LandType.BEACH: return 0.05
	return 0.0


static func _initial_soil(t: int) -> float:
	match t:
		LandType.FOREST, LandType.LOWLAND: return 1.0
		LandType.GRASSLAND: return 0.85
		LandType.HILLS: return 0.5
		LandType.BEACH: return 0.25
	return 0.0
