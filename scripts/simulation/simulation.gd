class_name Simulation
extends RefCounted
## Deterministic tick-based ecosystem simulation over a WorldState.
## - Never reads frame time; one call to step() == one in-game day.
## - All randomness comes from `rng` (seeded, state saved).
## - Systems run in a fixed order (see step()).
## - Water and sediment use two buffers (read current, write next, swap).
## - Tick loops iterate local aliases of Packed arrays and allocate nothing.

enum Action { NONE, CLEAR_TREES, PLANT_TREES }

const YEAR_LENGTH := 120.0
# Rainfall
const RAIN_BASE_CHANCE := 0.38
const RAIN_SEASON_SWING := 0.22
const RAIN_MIN := 0.010
const RAIN_MAX := 0.050
const OROGRAPHIC := 0.6
const HEAVY_RAIN := 0.055
# Water flow & erosion
const FLOW_MAX_FRACTION := 0.85
const ERODE_K := 0.25
const DEPOSIT_RATE := 0.25
const SEA_SED_KEEP := 0.80
const SEA_SED_SPREAD := 0.10
# Soil water
const INFILTRATION := 0.25
const SURFACE_EVAP := 0.10
const SOIL_EVAP := 0.020
const PLANT_USE := 0.003
# Vegetation
const VEG_GROWTH := 0.032
const DROUGHT_MOISTURE := 0.08

var world: WorldState
var rng := RandomNumberGenerator.new()

var _water_next := PackedFloat32Array()
var _sed_next := PackedFloat32Array()
var _nbr := PackedInt32Array()   ## 4 neighbour indices per tile, -1 outside the map
var _down := PackedInt32Array()  ## steepest-descent neighbour by terrain elevation (-1 = pit)
var upstream_area := PackedInt32Array() ## tiles draining through each tile (static, for rivers)
var _veg_cap := PackedFloat32Array()


static func create(world_seed: int, size: int = 32) -> Simulation:
	return Simulation.new(IslandGenerator.generate(world_seed, size, size))


static func rng_seed_for(world_seed: int) -> int:
	return world_seed * 7919 + 104729


func _init(ws: WorldState) -> void:
	world = ws
	rng.seed = rng_seed_for(ws.world_seed)
	_allocate()


func _allocate() -> void:
	var n := world.tile_count()
	var w := world.width
	var h := world.height
	_water_next.resize(n)
	_sed_next.resize(n)
	_nbr.resize(n * 4)
	for y in h:
		for x in w:
			var i := y * w + x
			_nbr[i * 4 + 0] = i - w if y > 0 else -1
			_nbr[i * 4 + 1] = i + 1 if x < w - 1 else -1
			_nbr[i * 4 + 2] = i + w if y < h - 1 else -1
			_nbr[i * 4 + 3] = i - 1 if x > 0 else -1
	_compute_drainage()
	_veg_cap.resize(LandType.COUNT)
	_veg_cap[LandType.DEEP_WATER] = 0.0
	_veg_cap[LandType.SHALLOW_WATER] = 0.0
	_veg_cap[LandType.BEACH] = 0.12
	_veg_cap[LandType.LOWLAND] = 0.60
	_veg_cap[LandType.GRASSLAND] = 0.70
	_veg_cap[LandType.FOREST] = 1.0
	_veg_cap[LandType.HILLS] = 0.45


## Static drainage network from terrain: each land tile drains to its lowest 4-neighbour.
## Elevation never changes at runtime, so this is computed once.
func _compute_drainage() -> void:
	var n := world.tile_count()
	var elev := world.elevation
	_down.resize(n)
	upstream_area.resize(n)
	upstream_area.fill(1)
	for i in n:
		var best := -1
		var best_e := elev[i]
		for k in 4:
			var j := _nbr[i * 4 + k]
			if j >= 0 and elev[j] < best_e:
				best_e = elev[j]
				best = j
		_down[i] = best
	# Accumulate from high to low (stable sort by elevation desc, then index).
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		return elev[a] > elev[b] or (elev[a] == elev[b] and a < b))
	for i in order:
		var d := _down[i]
		if d >= 0 and world.land_type[i] > LandType.SHALLOW_WATER:
			upstream_area[d] += upstream_area[i]


## Advance exactly one tick. Fixed system order.
func step() -> void:
	world.tick += 1
	_rainfall()
	_water_flow_and_erosion()
	_soil_water()
	_vegetation()


func run(ticks: int) -> void:
	for k in ticks:
		step()


# ---------------------------------------------------------------- systems

func _rainfall() -> void:
	var season := sin(world.tick * TAU / YEAR_LENGTH)
	var chance := RAIN_BASE_CHANCE + RAIN_SEASON_SWING * season
	var roll := rng.randf()
	var amount := rng.randf_range(RAIN_MIN, RAIN_MAX) * (1.0 + 0.5 * maxf(season, 0.0))
	if roll >= chance:
		amount = 0.0
	world.rain_today = amount
	world.dry_streak = world.dry_streak + 1 if amount == 0.0 else 0
	if amount == 0.0:
		return
	var water := world.surface_water
	var elev := world.elevation
	var lt := world.land_type
	for i in water.size():
		if lt[i] > LandType.SHALLOW_WATER:
			water[i] += amount * (1.0 + OROGRAPHIC * elev[i])


func _water_flow_and_erosion() -> void:
	var water := world.surface_water
	var sed := world.sediment
	var elev := world.elevation
	var lt := world.land_type
	var veg := world.vegetation_cover
	var soil := world.soil_depth
	var flow := world.flow
	var eacc := world.erosion_accum
	var nbr := _nbr
	var down := _down
	var wn := _water_next
	var sn := _sed_next
	wn.fill(0.0)
	sn.fill(0.0)
	var to_sea := 0.0
	var n := water.size()
	for i in n:
		var wi := water[i]
		var si := sed[i]
		if lt[i] <= LandType.SHALLOW_WATER:
			# Sea: incoming water drains away; sediment lingers, decays and spreads.
			var keep := si * SEA_SED_KEEP
			var b := i * 4
			for k in 4:
				var j := nbr[b + k]
				if j >= 0 and lt[j] <= LandType.SHALLOW_WATER:
					sn[j] += si * SEA_SED_SPREAD * 0.25
				else:
					keep += si * SEA_SED_SPREAD * 0.25
			sn[i] += keep
			continue
		var hi := elev[i] + wi
		var best := down[i]
		var best_h := -1.0
		if best < 0:
			# Pit: spill over to the lowest neighbour once the pond's surface is higher.
			best_h = hi
			var b := i * 4
			for k in 4:
				var j := nbr[b + k]
				if j < 0:
					continue
				var hj := elev[j] if lt[j] <= LandType.SHALLOW_WATER else elev[j] + water[j]
				if hj < best_h:
					best_h = hj
					best = j
		if best < 0 or wi <= 0.0:
			wn[i] += wi
			var dep := si * DEPOSIT_RATE
			soil[i] = minf(soil[i] + dep, 1.0)
			sn[i] += si - dep
			flow[i] *= 0.9
			continue
		var move := wi * FLOW_MAX_FRACTION if best_h < 0.0 else minf(wi * FLOW_MAX_FRACTION, (hi - best_h) * 0.5)
		var slope := clampf((elev[i] - elev[best]) * 12.0, 0.0, 1.0) + 0.1
		var bare := 1.0 - veg[i]
		var detach := minf(ERODE_K * move * slope * bare * bare, soil[i])
		soil[i] -= detach
		eacc[i] += detach
		var carried := si + detach
		var frac := move / wi
		var sed_move := carried * frac
		var dep2 := (carried - sed_move) * DEPOSIT_RATE
		soil[i] = minf(soil[i] + dep2, 1.0)
		wn[i] += wi - move
		wn[best] += move
		sn[best] += sed_move
		sn[i] += carried - sed_move - dep2
		flow[i] = flow[i] * 0.9 + move * 0.1
		if lt[best] <= LandType.SHALLOW_WATER:
			to_sea += sed_move
	world.sediment_to_sea = to_sea
	# swap buffers
	world.surface_water = wn
	world.sediment = sn
	_water_next = water
	_sed_next = sed
	# coastal turbidity = mean sediment over shallow water
	var total := 0.0
	var count := 0
	for i in n:
		if lt[i] == LandType.SHALLOW_WATER:
			total += sn[i]
			count += 1
	world.coastal_turbidity = total / count if count > 0 else 0.0


func _soil_water() -> void:
	var water := world.surface_water
	var moist := world.soil_moisture
	var veg := world.vegetation_cover
	var soil := world.soil_depth
	var lt := world.land_type
	for i in water.size():
		if lt[i] <= LandType.SHALLOW_WATER:
			continue
		var w := water[i]
		var m := moist[i]
		var infil := minf(w, INFILTRATION * (1.0 - m) * (0.4 + 0.6 * soil[i]))
		w -= infil
		m += infil
		water[i] = w * (1.0 - SURFACE_EVAP)
		m -= m * SOIL_EVAP * (1.0 - 0.5 * veg[i]) + veg[i] * PLANT_USE
		moist[i] = clampf(m, 0.0, 1.0)


func _vegetation() -> void:
	var veg := world.vegetation_cover
	var moist := world.soil_moisture
	var soil := world.soil_depth
	var lt := world.land_type
	var caps := _veg_cap
	for i in veg.size():
		var t := lt[i]
		if t <= LandType.SHALLOW_WATER:
			continue
		var cap := caps[t]
		var v := veg[i]
		var m := moist[i]
		var mf := clampf((m - DROUGHT_MOISTURE) / 0.3, 0.0, 1.0)
		var sf := clampf(soil[i] / 0.6, 0.1, 1.0)
		var g := VEG_GROWTH * mf * sf * (v + 0.008) * (1.0 - v / cap) if v < cap else -(v - cap) * 0.05
		if m < DROUGHT_MOISTURE:
			g -= 0.004
		veg[i] = clampf(v + g, 0.0, 1.0)


# ---------------------------------------------------------------- actions

## Validates without mutating. Returns "" if allowed, else a short reason.
func can_apply(action: int, x: int, y: int) -> String:
	if not world.in_bounds(x, y):
		return "Outside the island"
	var i := world.index(x, y)
	var t := world.land_type[i]
	match action:
		Action.CLEAR_TREES:
			return "" if t == LandType.FOREST else "No trees here"
		Action.PLANT_TREES:
			if t in [LandType.LOWLAND, LandType.GRASSLAND, LandType.HILLS]:
				return ""
			return "Trees can't grow here"
	return "Unknown action"


## Applies a player action between ticks. Returns true on success.
func apply_action(action: int, x: int, y: int) -> bool:
	if can_apply(action, x, y) != "":
		return false
	var i := world.index(x, y)
	match action:
		Action.CLEAR_TREES:
			world.land_type[i] = LandType.LOWLAND if world.elevation[i] < IslandGenerator.LOWLAND_MAX else LandType.GRASSLAND
			world.vegetation_cover[i] = 0.06
		Action.PLANT_TREES:
			world.land_type[i] = LandType.FOREST
			world.vegetation_cover[i] = maxf(world.vegetation_cover[i], 0.25)
	return true
