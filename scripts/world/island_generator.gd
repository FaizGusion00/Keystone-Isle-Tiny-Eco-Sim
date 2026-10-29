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
	_place_settlement(ws)
	return ws


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
