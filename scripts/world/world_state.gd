class_name WorldState
extends RefCounted
## Pure tile data for one island. No visuals, no nodes.
## Every per-tile field is a compact Packed array indexed by `y * width + x`.
## ARRAY_FIELDS / SCALAR_FIELDS list everything that is simulation state; the checksum and
## the save system iterate these lists, so new state cannot silently escape either.

enum Structure { NONE, SETTLEMENT, FARM }

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
}

const SCALAR_FIELDS := [
	"tick", "rain_today", "dry_streak", "sediment_to_sea", "coastal_turbidity",
	"coast_muddy", "muddy_event", "heavy_rain_event", "drought_event",
	"settlement_index", "villagers", "food_store", "fish", "goats",
	"food_ema", "water_ema", "water_supply", "fish_event", "goats_event",
	"food_event", "water_event", "crop_failure_event", "growth_event",
	"farms_built", "harvests",
]

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


func tile_count() -> int:
	return width * height


func index(x: int, y: int) -> int:
	return y * width + x


@warning_ignore("integer_division")
func coords(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func count_structures(s: int) -> int:
	return structure.count(s)


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
