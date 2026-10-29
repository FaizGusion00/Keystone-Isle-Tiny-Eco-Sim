class_name EventLog
extends RefCounted
## Fixed-capacity ring buffer of simulation events with recorded causes.
## Events are stored in parallel Packed arrays so recording during a tick allocates nothing.
## An event's causes are the ids of earlier events that the simulation *actually used*
## when deciding to emit it; explanations only ever walk these recorded links.

enum Type {
	NONE,
	TREES_CLEARED, TREES_PLANTED, FARM_BUILT,          # player actions (roots)
	HEAVY_RAIN, DROUGHT,                               # weather (roots)
	EROSION, MUDDY_WATER, WATER_CLEARED,               # landscape
	FISH_DECLINE, HERBIVORE_DECLINE, CROP_FAILURE,     # living things (M4)
	FOOD_SHORTAGE, WATER_SHORTAGE, POPULATION_GROWTH, POPULATION_LOSS, # settlement (M4)
	DROUGHT_ENDED,
	# --- v2 (M6): appended only, so ids stored in v1 saves keep their meaning ---
	LAND_CLEARED, HOUSE_BUILT, DAM_BUILT, LAND_RESTORED, STRUCTURE_REMOVED, # player actions
	DRY_SEASON, WET_SEASON,                            # seasons (roots)
	WILDFIRE, FIRE_OUT, FLOOD, HOUSING_FULL, HARVEST_LOST,
}

const TYPE_NAMES := {
	Type.NONE: "Nothing",
	Type.TREES_CLEARED: "Trees cleared",
	Type.TREES_PLANTED: "Trees planted",
	Type.FARM_BUILT: "Farm built",
	Type.HEAVY_RAIN: "Heavy rain",
	Type.DROUGHT: "Drought",
	Type.EROSION: "Soil erosion",
	Type.MUDDY_WATER: "Coastal water turned muddy",
	Type.WATER_CLEARED: "Coastal water cleared",
	Type.FISH_DECLINE: "Fish declining",
	Type.HERBIVORE_DECLINE: "Wild goats declining",
	Type.CROP_FAILURE: "Crop failure",
	Type.FOOD_SHORTAGE: "Food shortage",
	Type.WATER_SHORTAGE: "Water shortage",
	Type.POPULATION_GROWTH: "Village grew",
	Type.POPULATION_LOSS: "Villagers left",
	Type.DROUGHT_ENDED: "Drought ended",
	Type.LAND_CLEARED: "Land cleared",
	Type.HOUSE_BUILT: "House built",
	Type.DAM_BUILT: "Dam built",
	Type.LAND_RESTORED: "Land restored",
	Type.STRUCTURE_REMOVED: "Building removed",
	Type.DRY_SEASON: "Dry season began",
	Type.WET_SEASON: "Wet season began",
	Type.WILDFIRE: "Wildfire",
	Type.FIRE_OUT: "Fire burned out",
	Type.FLOOD: "Flood",
	Type.HOUSING_FULL: "Village out of homes",
	Type.HARVEST_LOST: "Harvest lost",
}

## Types that start a causal chain by definition (player actions, weather, recoveries).
const ROOT_KIND := {
	Type.TREES_CLEARED: "your action",
	Type.TREES_PLANTED: "your action",
	Type.FARM_BUILT: "your action",
	Type.HEAVY_RAIN: "weather",
	Type.DROUGHT: "weather",
	Type.DROUGHT_ENDED: "weather",
	Type.POPULATION_GROWTH: "plenty of food and water",
	Type.LAND_CLEARED: "your action",
	Type.HOUSE_BUILT: "your action",
	Type.DAM_BUILT: "your action",
	Type.LAND_RESTORED: "your action",
	Type.STRUCTURE_REMOVED: "your action",
	Type.DRY_SEASON: "the turning of the seasons",
	Type.WET_SEASON: "the turning of the seasons",
	Type.HOUSING_FULL: "every home being full - build houses",
}

## Category of each type, used by the UI for icons/colours and history filters.
enum Kind { ACTION, WEATHER, LAND, LIFE, VILLAGE, HAZARD }
const TYPE_KIND := {
	Type.TREES_CLEARED: Kind.ACTION, Type.TREES_PLANTED: Kind.ACTION, Type.FARM_BUILT: Kind.ACTION,
	Type.LAND_CLEARED: Kind.ACTION, Type.HOUSE_BUILT: Kind.ACTION, Type.DAM_BUILT: Kind.ACTION,
	Type.LAND_RESTORED: Kind.ACTION, Type.STRUCTURE_REMOVED: Kind.ACTION,
	Type.HEAVY_RAIN: Kind.WEATHER, Type.DROUGHT: Kind.WEATHER, Type.DROUGHT_ENDED: Kind.WEATHER,
	Type.DRY_SEASON: Kind.WEATHER, Type.WET_SEASON: Kind.WEATHER,
	Type.EROSION: Kind.LAND, Type.MUDDY_WATER: Kind.LAND, Type.WATER_CLEARED: Kind.LAND,
	Type.FISH_DECLINE: Kind.LIFE, Type.HERBIVORE_DECLINE: Kind.LIFE, Type.CROP_FAILURE: Kind.LIFE,
	Type.HARVEST_LOST: Kind.LIFE,
	Type.FOOD_SHORTAGE: Kind.VILLAGE, Type.WATER_SHORTAGE: Kind.VILLAGE,
	Type.POPULATION_GROWTH: Kind.VILLAGE, Type.POPULATION_LOSS: Kind.VILLAGE, Type.HOUSING_FULL: Kind.VILLAGE,
	Type.WILDFIRE: Kind.HAZARD, Type.FIRE_OUT: Kind.HAZARD, Type.FLOOD: Kind.HAZARD,
}

## Events worth a toast when they happen (bad news and milestones; not routine actions).
const NOTABLE := [Type.HEAVY_RAIN, Type.DROUGHT, Type.DROUGHT_ENDED, Type.DRY_SEASON, Type.WET_SEASON,
	Type.MUDDY_WATER, Type.WATER_CLEARED, Type.FISH_DECLINE, Type.HERBIVORE_DECLINE, Type.CROP_FAILURE,
	Type.FOOD_SHORTAGE, Type.WATER_SHORTAGE, Type.POPULATION_GROWTH, Type.POPULATION_LOSS,
	Type.WILDFIRE, Type.FIRE_OUT, Type.FLOOD, Type.HOUSING_FULL, Type.HARVEST_LOST]


static func kind_of_type(t: int) -> int:
	return TYPE_KIND.get(t, Kind.LAND)


static func is_bad(t: int) -> bool:
	return t in [Type.DROUGHT, Type.EROSION, Type.MUDDY_WATER, Type.FISH_DECLINE, Type.HERBIVORE_DECLINE,
		Type.CROP_FAILURE, Type.FOOD_SHORTAGE, Type.WATER_SHORTAGE, Type.POPULATION_LOSS, Type.WILDFIRE,
		Type.FLOOD, Type.HOUSING_FULL, Type.HARVEST_LOST]

const CAPACITY := 512
const MAX_CAUSES := 3
const MAX_DEPTH := 6

var next_id: int = 0
var _tick := PackedInt32Array()
var _type := PackedInt32Array()
var _x := PackedInt32Array()
var _y := PackedInt32Array()
var _value := PackedFloat32Array()
var _causes := PackedInt32Array()


func _init() -> void:
	_tick.resize(CAPACITY)
	_type.resize(CAPACITY)
	_x.resize(CAPACITY)
	_y.resize(CAPACITY)
	_value.resize(CAPACITY)
	_causes.resize(CAPACITY * MAX_CAUSES)


## Records an event; causes that are -1 or no longer in the log are dropped. Returns its id.
func record(tick: int, type: int, x: int, y: int, value: float, c0: int = -1, c1: int = -1, c2: int = -1) -> int:
	var id := next_id
	var s := id % CAPACITY
	_tick[s] = tick
	_type[s] = type
	_x[s] = x
	_y[s] = y
	_value[s] = value
	var b := s * MAX_CAUSES
	_causes[b] = c0 if has(c0) else -1
	_causes[b + 1] = c1 if has(c1) and c1 != c0 else -1
	_causes[b + 2] = c2 if has(c2) and c2 != c0 and c2 != c1 else -1
	next_id = id + 1
	return id


func has(id: int) -> bool:
	return id >= 0 and id < next_id and id >= next_id - CAPACITY


func count() -> int:
	return mini(next_id, CAPACITY)


func type_of(id: int) -> int:
	return _type[id % CAPACITY] if has(id) else Type.NONE


func tick_of(id: int) -> int:
	return _tick[id % CAPACITY] if has(id) else -1


func pos_of(id: int) -> Vector2i:
	return Vector2i(_x[id % CAPACITY], _y[id % CAPACITY]) if has(id) else Vector2i(-1, -1)


func value_of(id: int) -> float:
	return _value[id % CAPACITY] if has(id) else 0.0


## Recorded cause ids (may include ids that have since fallen out of the ring buffer).
func causes_of(id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not has(id):
		return out
	var b := (id % CAPACITY) * MAX_CAUSES
	for k in MAX_CAUSES:
		if _causes[b + k] >= 0:
			out.append(_causes[b + k])
	return out


## Newest-first ids, at most `limit`.
func recent(limit: int = 50) -> PackedInt32Array:
	var out := PackedInt32Array()
	var id := next_id - 1
	while id >= 0 and has(id) and out.size() < limit:
		out.append(id)
		id -= 1
	return out


## Oldest-first ids of events recorded strictly after `after_tick`.
func since_tick(after_tick: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var id := maxi(0, next_id - CAPACITY)
	while id < next_id:
		if _tick[id % CAPACITY] > after_tick:
			out.append(id)
		id += 1
	return out


func describe(id: int) -> String:
	if not has(id):
		return "(an older event no longer in the history)"
	var t := type_of(id)
	var p := pos_of(id)
	var s := "Day %d: %s" % [tick_of(id), TYPE_NAMES.get(t, "Event")]
	if p.x >= 0:
		s += " at (%d, %d)" % [p.x, p.y]
	var v := value_of(id)
	match t:
		Type.HEAVY_RAIN: s += " (%.0f mm)" % (v * 1000.0)
		Type.DROUGHT: s += " (%d dry days)" % int(v)
		Type.EROSION: s += " (%.0f%% topsoil lost)" % (v * 100.0)
		Type.MUDDY_WATER: s += " (mud index %.0f)" % (v * 1000.0)
		Type.FISH_DECLINE, Type.HERBIVORE_DECLINE: s += " (now %d)" % int(v)
		Type.FOOD_SHORTAGE, Type.WATER_SHORTAGE: s += " (%.0f%% of need met)" % (v * 100.0)
		Type.POPULATION_GROWTH, Type.POPULATION_LOSS: s += " (now %d villagers)" % int(v)
		Type.FIRE_OUT: s += " (%d tiles burned)" % int(v)
		Type.FLOOD: s += " (%.0f cm deep)" % (v * 100.0)
		Type.LAND_CLEARED, Type.TREES_CLEARED:
			if v > 0.0:
				s += " (+%d wood)" % int(v)
		Type.HOUSING_FULL: s += " (all %d places taken)" % int(v)
	return s


## Human-readable causal chain built only from recorded cause links.
func explain(id: int) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(describe(id))
	_explain_into(id, 1, lines)
	return lines


func _explain_into(id: int, depth: int, lines: PackedStringArray) -> void:
	var indent := "  ".repeat(depth)
	if not has(id):
		return
	var t := type_of(id)
	var causes := causes_of(id)
	if causes.is_empty():
		if ROOT_KIND.has(t):
			lines.append(indent + "(caused by %s)" % ROOT_KIND[t])
		else:
			lines.append(indent + "No recorded cause.")
		return
	if depth > MAX_DEPTH:
		lines.append(indent + "…")
		return
	for c in causes:
		if has(c):
			lines.append(indent + "because " + describe(c))
			_explain_into(c, depth + 1, lines)
		else:
			lines.append(indent + "because of an older event no longer in the history")


# ------------------------------------------------------------ persistence (M5)

func to_dict() -> Dictionary:
	return {
		"next_id": next_id,
		"tick": Marshalls.raw_to_base64(_tick.to_byte_array()),
		"type": Marshalls.raw_to_base64(_type.to_byte_array()),
		"x": Marshalls.raw_to_base64(_x.to_byte_array()),
		"y": Marshalls.raw_to_base64(_y.to_byte_array()),
		"value": Marshalls.raw_to_base64(_value.to_byte_array()),
		"causes": Marshalls.raw_to_base64(_causes.to_byte_array()),
	}


static func from_dict(d: Dictionary) -> EventLog:
	var el := EventLog.new()
	el.next_id = int(d.get("next_id", 0))
	var t := Marshalls.base64_to_raw(str(d.get("tick", ""))).to_int32_array()
	var ty := Marshalls.base64_to_raw(str(d.get("type", ""))).to_int32_array()
	var x := Marshalls.base64_to_raw(str(d.get("x", ""))).to_int32_array()
	var y := Marshalls.base64_to_raw(str(d.get("y", ""))).to_int32_array()
	var v := Marshalls.base64_to_raw(str(d.get("value", ""))).to_float32_array()
	var c := Marshalls.base64_to_raw(str(d.get("causes", ""))).to_int32_array()
	if t.size() != CAPACITY or ty.size() != CAPACITY or x.size() != CAPACITY or y.size() != CAPACITY \
			or v.size() != CAPACITY or c.size() != CAPACITY * MAX_CAUSES:
		return null
	el._tick = t
	el._type = ty
	el._x = x
	el._y = y
	el._value = v
	el._causes = c
	return el


func checksum_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array(PackedInt32Array([next_id]).to_byte_array())
	b.append_array(_tick.to_byte_array())
	b.append_array(_type.to_byte_array())
	b.append_array(_x.to_byte_array())
	b.append_array(_y.to_byte_array())
	b.append_array(_value.to_byte_array())
	b.append_array(_causes.to_byte_array())
	return b
