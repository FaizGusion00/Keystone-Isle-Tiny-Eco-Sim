class_name IslandGenerator
extends RefCounted
## Deterministic island generation. Same (seed, size) => bit-identical WorldState.
## Only seeded FastNoiseLite + seeded RandomNumberGenerator are used.

const DEEP_MAX := 0.16
const SHALLOW_MAX := 0.26
const BEACH_MAX := 0.31
const LOWLAND_MAX := 0.50
const GRASS_MAX := 0.76


static func generate(world_seed: int, w: int = 32, h: int = 32) -> WorldState:
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
	return ws


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
