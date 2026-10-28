class_name WorldState
extends RefCounted
## Pure tile data for one island. No visuals, no nodes.
## Every per-tile field is a compact Packed array indexed by `y * width + x`.

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
var erosion_accum := PackedFloat32Array()    ## soil lost since last erosion event (M3)
# --- Milestone 3: events ---
var last_event := PackedInt32Array()         ## latest event id at this tile (-1 none)
var land_cause := PackedInt32Array()         ## event that last changed this tile's land (clear/plant/farm)

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


func _init(w: int = 32, h: int = 32, s: int = 0) -> void:
	width = w
	height = h
	world_seed = s
	var n := w * h
	elevation.resize(n)
	land_type.resize(n)
	soil_moisture.resize(n)
	vegetation_cover.resize(n)
	surface_water.resize(n)
	sediment.resize(n)
	soil_depth.resize(n)
	flow.resize(n)
	erosion_accum.resize(n)
	last_event.resize(n)
	last_event.fill(-1)
	land_cause.resize(n)
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


## SHA-256 over all tile arrays; used by determinism tests and save checks.
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedInt32Array([width, height, world_seed]).to_byte_array())
	ctx.update(elevation.to_byte_array())
	ctx.update(land_type)
	ctx.update(soil_moisture.to_byte_array())
	ctx.update(vegetation_cover.to_byte_array())
	ctx.update(surface_water.to_byte_array())
	ctx.update(sediment.to_byte_array())
	ctx.update(soil_depth.to_byte_array())
	ctx.update(flow.to_byte_array())
	ctx.update(erosion_accum.to_byte_array())
	ctx.update(last_event.to_byte_array())
	ctx.update(land_cause.to_byte_array())
	ctx.update(recent_erosion.to_byte_array())
	ctx.update(var_to_bytes([tick, rain_today, dry_streak, sediment_to_sea, coastal_turbidity,
		coast_muddy, muddy_event, heavy_rain_event, drought_event]))
	return ctx.finish().hex_encode()

