class_name WorldState
extends RefCounted
## Pure tile data for one island. No visuals, no nodes.
## Every per-tile field is a compact Packed array indexed by `y * width + x`.
## ARRAY_FIELDS / SCALAR_FIELDS list everything that is simulation state; the checksum and
## the save system iterate these lists, so new state cannot silently escape either.

enum Structure { NONE, SETTLEMENT, FARM, HOUSE, DAM }

## name -> Variant.Type of the packed array
const ARRAY_FIELDS := {
	"elevation": TYPE_PACKED_FLOAT32_ARRAY,
	"land_type": TYPE_PACKED_BYTE_ARRAY,
	"soil_moisture": TYPE_PACKED_FLOAT32_ARRAY,
	"vegetation_cover": TYPE_PACKED_FLOAT32_ARRAY,
	"surface_water": TYPE_PACKED_FLOAT32_ARRAY,
	"sediment": TYPE_PACKED_FLOAT32_ARRAY,
	"soil_depth": TYPE_PACKED_FLOAT32_ARRAY,
	"flow": TYPE_PACKED_FLOAT32_ARRAY,
	"erosion_accum": TYPE_PACKED_FLOAT32_ARRAY,
	"last_event": TYPE_PACKED_INT32_ARRAY,
	"land_cause": TYPE_PACKED_INT32_ARRAY,
	"structure": TYPE_PACKED_BYTE_ARRAY,
	"crop_growth": TYPE_PACKED_FLOAT32_ARRAY,
	"crop_stress": TYPE_PACKED_BYTE_ARRAY,
	"recent_erosion": TYPE_PACKED_INT32_ARRAY, # 6 entries, not per tile
	# --- v2 (M6) ---
	"fire": TYPE_PACKED_BYTE_ARRAY,
	"reservoir": TYPE_PACKED_FLOAT32_ARRAY,
	"flood_tick": TYPE_PACKED_INT32_ARRAY,
}

## Array fields added after save version 1 (filled with defaults when migrating old saves).
const V2_ARRAYS := ["fire", "reservoir", "flood_tick"]

const SCALAR_FIELDS := [
	"tick", "rain_today", "dry_streak", "sediment_to_sea", "coastal_turbidity",
	"coast_muddy", "muddy_event", "heavy_rain_event", "drought_event",
	"settlement_index", "villagers", "food_store", "fish", "goats",
	"food_ema", "water_ema", "water_supply", "fish_event", "goats_event",
	"food_event", "water_event", "crop_failure_event", "growth_event",
	"farms_built", "harvests",
	# --- v2 (M6) ---
	"labor", "wood", "free_build", "relaxed", "climate_rain", "climate_storm", "climate_fire",
	"season_event", "fire_event", "fires_burning", "flood_event", "dam_event", "river_dams",
	"houses_built", "dams_built", "trees_planted", "land_restored", "fires", "floods",
	"villagers_lost", "peak_villagers", "keystone", "k_plants", "k_soil", "k_water", "k_fish",
	"k_wildlife", "k_village", "housing_event", "fire_burned",
]

## Scalars added after save version 1, with their defaults for migrated saves.
const V2_SCALAR_DEFAULTS := {
	"labor": 10.0, "wood": 12.0, "free_build": false, "relaxed": false,
	"climate_rain": 1.0, "climate_storm": 1.0, "climate_fire": 1.0,
	"season_event": -1, "fire_event": -1, "fires_burning": 0, "flood_event": -1, "dam_event": -1,
	"river_dams": 0, "houses_built": 0, "dams_built": 0, "trees_planted": 0, "land_restored": 0,
	"fires": 0, "floods": 0, "villagers_lost": 0, "peak_villagers": 0, "keystone": 0.0,
	"k_plants": 0.0, "k_soil": 0.0, "k_water": 0.0, "k_fish": 0.0, "k_wildlife": 0.0,
	"k_village": 0.0, "housing_event": -1, "fire_burned": 0,
}

var width: int = 0
var height: int = 0
var world_seed: int = 0

var elevation := PackedFloat32Array()        ## 0..1
var land_type := PackedByteArray()           ## LandType id
var soil_moisture := PackedFloat32Array()    ## 0..1
var vegetation_cover := PackedFloat32Array() ## 0..1
# --- Milestone 2: water & soil ---
var surface_water := PackedFloat32Array()    ## water depth on the surface (sea tiles: inflow sink)
var sediment := PackedFloat32Array()         ## suspended sediment carried by water / turbidity at sea
var soil_depth := PackedFloat32Array()       ## 0..1 fertile topsoil
var flow := PackedFloat32Array()             ## smoothed outflow (rivers/streams)
var erosion_accum := PackedFloat32Array()    ## decaying soil-loss sum that triggers EROSION events
# --- Milestone 3: events ---
var last_event := PackedInt32Array()         ## latest event id at this tile (-1 none)
var land_cause := PackedInt32Array()         ## event that last changed this tile's land (clear/plant/farm)
# --- Milestone 4: life & settlement ---
var structure := PackedByteArray()           ## Structure id
var crop_growth := PackedFloat32Array()      ## farm tiles: 0..1 until harvest
var crop_stress := PackedByteArray()         ## farm tiles: consecutive too-dry days
# --- v2 (M6): hazards & water works ---
var fire := PackedByteArray()                ## days this tile keeps burning (0 = not on fire)
var reservoir := PackedFloat32Array()        ## dam tiles: water held behind the dam
var flood_tick := PackedInt32Array()         ## last day a FLOOD was recorded on this tile

# --- Global (non-tile) state ---
var tick: int = 0
var rain_today: float = 0.0
var dry_streak: int = 0
var sediment_to_sea: float = 0.0   ## sediment entering the sea during the last tick
var coastal_turbidity: float = 0.0 ## mean sediment over shallow-water tiles
var coast_muddy: bool = false      ## hysteresis state for MUDDY_WATER events
var muddy_event: int = -1          ## id of the event that made the coast muddy
var heavy_rain_event: int = -1
var drought_event: int = -1
## [0..2] latest erosion events that have recorded causes, [3..5] latest of any erosion
var recent_erosion := PackedInt32Array([-1, -1, -1, -1, -1, -1])
var settlement_index: int = -1
var villagers: int = 0
var food_store: float = 0.0
var fish: float = 0.0
var goats: float = 0.0
var food_ema: float = 1.0          ## smoothed fraction of food need met
var water_ema: float = 1.0         ## smoothed fraction of water need met
var water_supply: float = 0.0      ## fresh water reachable by the village today
var fish_event: int = -1           ## active FISH_DECLINE (-1 = fish are fine)
var goats_event: int = -1
var food_event: int = -1           ## active FOOD_SHORTAGE
var water_event: int = -1          ## active WATER_SHORTAGE
var crop_failure_event: int = -1   ## latest CROP_FAILURE
var growth_event: int = -1         ## latest POPULATION_GROWTH
var farms_built: int = 0
var harvests: int = 0
# --- v2 (M6) ---
var labor: float = 10.0            ## villagers' spare work, regenerates daily, spent by tools
var wood: float = 12.0             ## timber from clearing forest, spent on buildings
var free_build: bool = false       ## sandbox "unlimited resources" (tools cost nothing)
var relaxed: bool = false          ## relaxed mode: half costs, villagers never leave
var climate_rain: float = 1.0      ## scenario climate: rain chance multiplier
var climate_storm: float = 1.0     ## scenario climate: wet-season storm intensity
var climate_fire: float = 1.0      ## scenario climate: wildfire ignition multiplier
var season_event: int = -1         ## latest DRY_SEASON / WET_SEASON event
var fire_event: int = -1           ## active WILDFIRE (-1 = none burning)
var fires_burning: int = 0
var flood_event: int = -1          ## latest FLOOD
var dam_event: int = -1            ## latest DAM_BUILT
var river_dams: int = 0            ## dams standing on streams (block fish runs)
var houses_built: int = 0
var dams_built: int = 0
var trees_planted: int = 0
var land_restored: int = 0
var fires: int = 0
var floods: int = 0
var villagers_lost: int = 0
var peak_villagers: int = 0
var keystone: float = 0.0          ## island health 0..100 (see Simulation._keystone)
var k_plants: float = 0.0
var k_soil: float = 0.0
var k_water: float = 0.0
var k_fish: float = 0.0
var k_wildlife: float = 0.0
var k_village: float = 0.0
var housing_event: int = -1        ## active HOUSING_FULL
var fire_burned: int = 0           ## tiles burned by the current fire


func _init(w: int = 32, h: int = 32, s: int = 0) -> void:
	width = w
	height = h
	world_seed = s
	var n := w * h
	for f in ARRAY_FIELDS:
		if f == "recent_erosion":
			continue
		var a = get(f)
		a.resize(n)
		set(f, a)
	last_event.fill(-1)
	land_cause.fill(-1)
	flood_tick.fill(-1000)


func tile_count() -> int:
	return width * height


func index(x: int, y: int) -> int:
	return y * width + x


@warning_ignore("integer_division")
func coords(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func count_land(t: int) -> int:
	return land_type.count(t)


func count_structures(s: int) -> int:
	return structure.count(s)


## People the village can house: the village centre plus every house.
func housing_capacity() -> int:
	if settlement_index < 0:
		return 0
	return Simulation.HOUSING_BASE + Simulation.HOUSE_CAPACITY * structure.count(Structure.HOUSE)


## SHA-256 over all state fields; used by determinism tests and save checks.
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedInt32Array([width, height, world_seed]).to_byte_array())
	for f in ARRAY_FIELDS:
		var a = get(f)
		ctx.update(a if a is PackedByteArray else a.to_byte_array())
	var scalars := []
	for f in SCALAR_FIELDS:
		scalars.append(get(f))
	ctx.update(var_to_bytes(scalars))
	return ctx.finish().hex_encode()
