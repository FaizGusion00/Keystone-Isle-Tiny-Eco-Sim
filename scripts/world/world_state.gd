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


func _init(w: int = 32, h: int = 32, s: int = 0) -> void:
	width = w
	height = h
	world_seed = s
	var n := w * h
	elevation.resize(n)
	land_type.resize(n)
	soil_moisture.resize(n)
	vegetation_cover.resize(n)


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
	return ctx.finish().hex_encode()
