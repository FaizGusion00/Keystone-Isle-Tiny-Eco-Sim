class_name LandType
extends RefCounted
## Land type ids stored per tile in WorldState.land_type (PackedByteArray).

enum { DEEP_WATER, SHALLOW_WATER, BEACH, LOWLAND, GRASSLAND, FOREST, HILLS }

const COUNT := 7
const NAMES := ["Deep water", "Shallow water", "Beach", "Lowland", "Grassland", "Forest", "Hills"]


static func is_water(t: int) -> bool:
	return t <= SHALLOW_WATER


static func name_of(t: int) -> String:
	if t < 0 or t >= COUNT:
		return "Unknown"
	return NAMES[t]
