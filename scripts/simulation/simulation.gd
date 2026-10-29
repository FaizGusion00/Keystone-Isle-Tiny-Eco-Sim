class_name Simulation
extends RefCounted
## Deterministic tick-based ecosystem simulation over a WorldState.
## - Never reads frame time; one call to step() == one in-game day.
## - All randomness comes from `rng` (seeded, state saved).
## - Systems run in a fixed order (see step()).
## - Water and sediment use two buffers (read current, write next, swap).
## - Tick loops iterate local aliases of Packed arrays and allocate nothing.

enum Action { NONE, CLEAR_TREES, PLANT_TREES, BUILD_FARM, BUILD_HOUSE, BUILD_DAM, RESTORE_LAND, DEMOLISH }
## CLEAR_TREES clears any vegetation (forest gives wood); kept under its v1 name.
const CLEAR_VEGETATION := Action.CLEAR_TREES

## Seasons are quarters of the 120-day year, aligned with the rainfall cycle below.
enum Season { SPRING, WET, SUMMER, DRY }
const SEASON_NAMES := ["Spring", "Rainy season", "Summer", "Dry season"]
const SEASON_WEATHER := ["Normal rain", "Heavy rain & storms", "Normal rain", "Dry - drought & fire risk"]

## [labor, wood] per action. Relaxed mode halves these; free_build (sandbox) zeroes them.
const ACTION_COST := {
	Action.CLEAR_TREES: [1.0, 0.0],
	Action.PLANT_TREES: [1.0, 0.0],
	Action.BUILD_FARM: [3.0, 2.0],
	Action.BUILD_HOUSE: [3.0, 6.0],
	Action.BUILD_DAM: [6.0, 10.0],
	Action.RESTORE_LAND: [2.0, 0.0],
	Action.DEMOLISH: [1.0, 0.0],
}
const ACTION_NAMES := {
	Action.CLEAR_TREES: "Clear vegetation", Action.PLANT_TREES: "Plant trees", Action.BUILD_FARM: "Build farm",
	Action.BUILD_HOUSE: "Build house", Action.BUILD_DAM: "Build dam", Action.RESTORE_LAND: "Restore land",
	Action.DEMOLISH: "Remove building",
}

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
# Events (M3)
const DROUGHT_DAYS := 12
const EROSION_EVENT := 0.08      ## soil lost (decaying sum) that triggers an EROSION event
const EROSION_DECAY := 0.97
const MUDDY_ENTER := 0.045       ## coastal turbidity hysteresis
const MUDDY_EXIT := 0.030
const CAUSE_WINDOW := 40         ## days an event stays eligible as a cause
const RAIN_CAUSE_WINDOW := 3
# Life & settlement (M4)
const FISH_CAP := 100.0
const FISH_GROWTH := 0.04
const FISH_TURB_START := 0.015   ## turbidity above which fish habitat shrinks
const FISH_TURB_RANGE := 0.06
const FISH_LOW := 45.0           ## FISH_DECLINE hysteresis
const FISH_OK := 65.0
const GOAT_GROWTH := 0.03
const GOAT_PER_VEG := 0.15       ## carrying capacity per unit of pasture vegetation
const GRAZE := 0.004             ## vegetation eaten per goat per day
const GOATS_LOW := 12.0
const GOATS_OK := 18.0
const CROP_DAYS := 30.0
const CROP_DRY := 0.10           ## soil moisture below which crops stall and stress
const CROP_FAIL_DAYS := 10
const HARVEST_FOOD := 8.0
const HARVEST_SOIL_COST := 0.02
const FARM_RADIUS := 5           ## farms must be this close (Chebyshev) to the village
const FOOD_PER_VILLAGER := 0.10
const WATER_PER_VILLAGER := 0.05
const FISH_CATCH_RATE := 0.02
const FISH_CATCH_PER_VILLAGER := 0.06
const HUNT_RATE := 0.01
const HUNT_PER_VILLAGER := 0.03
const FOOD_STORE_MAX := 150.0
const WATER_RADIUS := 3
const SHORTAGE_ENTER := 0.70
const SHORTAGE_EXIT := 0.90
const POP_PERIOD := 20
const LIFE_CAUSE_WINDOW := 60
# Resources & building (M6)
const LABOR_PER_VILLAGER := 0.1   ## labor regenerated per villager per day
const LABOR_CAP_BASE := 10.0
const WOOD_PER_FOREST := 4.0      ## wood gained by clearing a forest tile
const WOOD_MAX := 99.0
const HOUSE_RADIUS := 2           ## houses: within this of the village centre, or next to a house
const DAM_MIN_AREA := 12          ## tiles that must drain through a dam site (a stream)
const DAM_CAPACITY := 2.0
const DAM_RELEASE := 0.03         ## water let through per day once the reservoir holds some
const DAM_EVAP := 0.004
const DAM_IRRIGATION := 0.30      ## soil moisture floor next to a full-ish reservoir
const DAM_FISH_PENALTY := 0.12    ## fish habitat lost per dam on a stream (blocked fish runs)
const RIVER_DAM_AREA := 20       ## a dam on a stream this big blocks fish runs
# Hazards (M6)
const FLOOD_DEPTH := 0.6         ## surface water on a built tile that counts as a flood
const FLOOD_STAGE := 0.22        ## river stage (flow / sqrt(catchment)) at which a river overtops its banks
const FLOODPLAIN_AREA := 12      ## streams with at least this catchment have a floodplain
const FLOODPLAIN_RISE := 0.035   ## banks up to this much higher than the river can flood
const FLOODPLAIN_STAGE_PER_RISE := 0.15 ## extra stage needed per FLOODPLAIN_RISE of bank height
const FLOOD_WATER := 0.35        ## water spread over a flooded floodplain tile (visible, soaks soil)
const FLOOD_SILT := 0.03         ## topsoil a river flood leaves behind
const VEG_RUNOFF_SLOW := 0.1     ## dense vegetation holds back this share of runoff each day
const FLOOD_COOLDOWN := 15
const FLOOD_FOOD_LOSS := 0.15
const FLOOD_CAUSE_WINDOW := 120
const FIRE_DAYS := 3
const FIRE_NEW := 0x80
const FIRE_VEG := 0.5             ## vegetation needed to ignite
const FIRE_MOIST := 0.08          ## soil moisture below which plants are tinder
const FIRE_SPREAD_MOIST := 0.15
const FIRE_CHANCE := 0.0015       ## per tinder tile per day during a drought
const FIRE_SPREAD := 0.45
const FIRE_RAIN_OUT := 0.02
# Population (M6)
const HOUSING_BASE := 12
const HOUSE_CAPACITY := 4
const GROWTH_DIVISOR := 8
var world: WorldState
var rng := RandomNumberGenerator.new()
var events := EventLog.new()
var fish_capacity := FISH_CAP  ## derived each tick (not saved)
var scenario: Scenario = null  ## optional goal, evaluated after every tick (saved)
## Save identity (v3): {id, created_at, revision}. Not simulation state: never in checksums.
var save_info := {}

var _water_next := PackedFloat32Array()
var _sed_next := PackedFloat32Array()
var _nbr := PackedInt32Array()   ## 4 neighbour indices per tile, -1 outside the map
var _down := PackedInt32Array()  ## steepest-descent neighbour by terrain elevation (-1 = pit)
var upstream_area := PackedInt32Array() ## tiles draining through each tile (static, for rivers)
## Static floodplain map: the river tile whose overflow reaches this tile (-1 = never floods from a river).
var floodplain := PackedInt32Array()
var _veg_cap := PackedFloat32Array()
var _erodibility := PackedFloat32Array()
var _dams := PackedInt32Array()  ## derived: indices of dam tiles (rebuilt on structure change)


static func create(world_seed: int, size: int = 32, preset: int = 0) -> Simulation:
	var sim := Simulation.new(IslandGenerator.generate(world_seed, size, size, preset))
	sim.world.peak_villagers = sim.world.villagers
	sim._keystone()
	return sim


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
	_erodibility.resize(LandType.COUNT)
	_erodibility.fill(1.0)
	_erodibility[LandType.BEACH] = 0.1 # coarse sand barely suspends
	_rebuild_dams()


func _rebuild_dams() -> void:
	_dams.clear()
	var river := 0
	for i in world.structure.size():
		if world.structure[i] == WorldState.Structure.DAM:
			_dams.append(i)
			if upstream_area[i] >= RIVER_DAM_AREA:
				river += 1
	world.river_dams = river


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
	_compute_floodplain()


## Low land beside a sizeable stream floods when the stream overtops its banks. Static.
func _compute_floodplain() -> void:
	var n := world.tile_count()
	var w := world.width
	var h := world.height
	var elev := world.elevation
	var lt := world.land_type
	floodplain.resize(n)
	floodplain.fill(-1)
	for i in n:
		if lt[i] <= LandType.SHALLOW_WATER:
			continue
		if upstream_area[i] >= FLOODPLAIN_AREA:
			floodplain[i] = i
			continue
		var x := i % w
		@warning_ignore("integer_division")
		var y := i / w
		var best := -1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := x + dx
				var yy := y + dy
				if (dx == 0 and dy == 0) or xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var j := yy * w + xx
				if lt[j] > LandType.SHALLOW_WATER and upstream_area[j] >= FLOODPLAIN_AREA \
						and elev[i] <= elev[j] + FLOODPLAIN_RISE \
						and (best < 0 or upstream_area[j] > upstream_area[best]):
					best = j
		floodplain[i] = best


## River stage at a stream tile: smoothed flow relative to what its channel normally carries.
func river_stage(r: int) -> float:
	if r < 0:
		return 0.0
	return world.flow[r] / sqrt(float(upstream_area[r]))


## Stage at which floodplain tile i goes under (higher banks need a bigger flood). INF if never.
func flood_stage_for(i: int) -> float:
	var r := floodplain[i] if i >= 0 and i < floodplain.size() else -1
	if r < 0:
		return INF
	var rise := maxf(world.elevation[i] - world.elevation[r], 0.0)
	return FLOOD_STAGE + FLOODPLAIN_STAGE_PER_RISE * rise / FLOODPLAIN_RISE


## 0 = safe, 1 = low risk (only big storms), 2 = floods in a normal rainy season.
func flood_risk(i: int) -> int:
	var need := flood_stage_for(i)
	if need == INF:
		return 0
	return 2 if need < FLOOD_STAGE + 0.09 else 1


## Advance exactly one tick. Fixed system order.
func step() -> void:
	world.tick += 1
	_rainfall()
	_water_flow_and_erosion()
	_soil_water()
	_vegetation()
	_wildfire()
	_detect_events()
	_floods()
	_crops()
	_wildlife()
	if world.rare_events:
		_rare()
	if world.escalate and world.tick % int(YEAR_LENGTH) == 0:
		_escalate()
	_settlement()
	_keystone()
	if scenario != null:
		scenario.evaluate(world)


func run(ticks: int) -> void:
	for k in ticks:
		step()


# ---------------------------------------------------------------- systems

## Season index for a day: 0 Spring, 1 Rainy (wettest, centred on day 30), 2 Summer, 3 Dry (day 90).
@warning_ignore("integer_division")
static func season_of(tick: int) -> int:
	return (posmod(tick + 15, int(YEAR_LENGTH))) / 30


static func season_day(tick: int) -> int:
	return posmod(tick + 15, 30)


func _rainfall() -> void:
	if season_day(world.tick) == 0:
		var sn := season_of(world.tick)
		if sn == Season.WET:
			world.season_event = events.record(world.tick, EventLog.Type.WET_SEASON, -1, -1, sn)
		elif sn == Season.DRY:
			world.season_event = events.record(world.tick, EventLog.Type.DRY_SEASON, -1, -1, sn)
	var season := sin(world.tick * TAU / YEAR_LENGTH)
	var chance := (RAIN_BASE_CHANCE + RAIN_SEASON_SWING * season) * world.climate_rain
	var roll := rng.randf()
	var amount := rng.randf_range(RAIN_MIN, RAIN_MAX) * (1.0 + 0.5 * maxf(season, 0.0) * world.climate_storm)
	if roll >= chance:
		amount = 0.0
	world.rain_today = amount
	if amount == 0.0:
		world.dry_streak += 1
		if world.dry_streak == DROUGHT_DAYS:
			world.drought_event = events.record(world.tick, EventLog.Type.DROUGHT, -1, -1, DROUGHT_DAYS)
		return
	if world.dry_streak >= DROUGHT_DAYS and world.drought_event >= 0:
		events.record(world.tick, EventLog.Type.DROUGHT_ENDED, -1, -1, world.dry_streak)
		world.drought_event = -1
	world.dry_streak = 0
	if amount >= HEAVY_RAIN:
		world.heavy_rain_event = events.record(world.tick, EventLog.Type.HEAVY_RAIN, -1, -1, amount)
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
	var erod := _erodibility
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
		var frac_max := FLOW_MAX_FRACTION * (1.0 - VEG_RUNOFF_SLOW * veg[i])
		var move := wi * frac_max if best_h < 0.0 else minf(wi * frac_max, (hi - best_h) * 0.5)
		var slope := clampf((elev[i] - elev[best]) * 12.0, 0.0, 1.0) + 0.1
		var bare := 1.0 - veg[i]
		var detach := minf(ERODE_K * erod[lt[i]] * move * slope * bare * bare * bare, soil[i])
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
	# Dams: hold incoming water in the reservoir, release a steady trickle, trap sediment.
	var res := world.reservoir
	for d in _dams:
		var r := res[d]
		var inflow := wn[d]
		var store := minf(inflow, DAM_CAPACITY - r)
		r += store
		var release := minf(r, DAM_RELEASE)
		r -= release
		r -= r * DAM_EVAP
		res[d] = r
		wn[d] = inflow - store + release
		sn[d] *= 0.3
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
	# Reservoirs seep into the land around them (irrigation).
	var res := world.reservoir
	for d in _dams:
		if res[d] < 0.2:
			continue
		var floor_m := DAM_IRRIGATION * minf(res[d] / 1.0, 1.0)
		moist[d] = maxf(moist[d], floor_m)
		for k in 4:
			var j := _nbr[d * 4 + k]
			if j >= 0 and lt[j] > LandType.SHALLOW_WATER:
				moist[j] = maxf(moist[j], floor_m)


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


@warning_ignore("integer_division")
## Turns state changes into events, linking only the causes the rules below actually used.
func _detect_events() -> void:
	var tick := world.tick
	var eacc := world.erosion_accum
	var lt := world.land_type
	var last := world.last_event
	var lcause := world.land_cause
	var recent := world.recent_erosion
	var rain_ev := world.heavy_rain_event if tick - events.tick_of(world.heavy_rain_event) <= RAIN_CAUSE_WINDOW else -1
	var w := world.width
	for i in eacc.size():
		var a := eacc[i] * EROSION_DECAY
		if a >= EROSION_EVENT and lt[i] > LandType.SHALLOW_WATER:
			# Cause 1: this tile's land was cleared (bare soil). Cause 2: heavy rain just fell.
			var lc := lcause[i]
			var lct := events.type_of(lc)
			var bare_cause := lc if (lct == EventLog.Type.TREES_CLEARED or lct == EventLog.Type.LAND_CLEARED
					or lct == EventLog.Type.WILDFIRE or lct == EventLog.Type.FARM_BUILT) else -1
			var id := events.record(tick, EventLog.Type.EROSION, i % w, i / w, a, bare_cause, rain_ev)
			last[i] = id
			if bare_cause >= 0:
				recent[2] = recent[1]
				recent[1] = recent[0]
				recent[0] = id
			recent[5] = recent[4]
			recent[4] = recent[3]
			recent[3] = id
			a = 0.0
		eacc[i] = a
	# Coastal mud with hysteresis.
	var turb := world.coastal_turbidity
	if not world.coast_muddy and turb >= MUDDY_ENTER:
		var c0 := -1
		var c1 := -1
		var c2 := -1
		var base := 0 if _recent_ok(recent[0], tick) else 3
		if _recent_ok(recent[base], tick):
			c0 = recent[base]
		if _recent_ok(recent[base + 1], tick):
			c1 = recent[base + 1]
		if _recent_ok(recent[base + 2], tick):
			c2 = recent[base + 2]
		var at := _muddiest_shallow()
		world.muddy_event = events.record(tick, EventLog.Type.MUDDY_WATER,
				at % w if at >= 0 else -1, at / w if at >= 0 else -1, turb, c0, c1, c2)
		if at >= 0:
			last[at] = world.muddy_event
		world.coast_muddy = true
	elif world.coast_muddy and turb < MUDDY_EXIT:
		events.record(tick, EventLog.Type.WATER_CLEARED, -1, -1, turb, world.muddy_event)
		world.coast_muddy = false
		world.muddy_event = -1


func _recent_ok(id: int, tick: int) -> bool:
	return events.has(id) and tick - events.tick_of(id) <= CAUSE_WINDOW


func _muddiest_shallow() -> int:
	var sed := world.sediment
	var lt := world.land_type
	var best := -1
	var best_s := -1.0
	for i in sed.size():
		if lt[i] == LandType.SHALLOW_WATER and sed[i] > best_s:
			best_s = sed[i]
			best = i
	return best


# ---------------------------------------------------------------- life (M4)

@warning_ignore("integer_division")
func _crops() -> void:
	var st := world.structure
	var crop := world.crop_growth
	var stress := world.crop_stress
	var moist := world.soil_moisture
	var soil := world.soil_depth
	var veg := world.vegetation_cover
	var w := world.width
	var pollination := BEE_POLLINATION if (world.species & SP_BEES) != 0 else 1.0
	for i in st.size():
		if st[i] != WorldState.Structure.FARM:
			continue
		var m := moist[i]
		var sf := clampf(soil[i] / 0.5, 0.2, 1.0)
		if m < CROP_DRY:
			stress[i] = mini(stress[i] + 1, 255)
			if stress[i] == CROP_FAIL_DAYS and crop[i] > 0.0:
				crop[i] = 0.0
				var dr := world.drought_event if world.drought_event >= 0 else -1
				var id := events.record(world.tick, EventLog.Type.CROP_FAILURE, i % w, i / w, 0.0, dr)
				world.crop_failure_event = id
				world.last_event[i] = id
		else:
			stress[i] = 0
		var c := crop[i] + (1.0 / CROP_DAYS) * clampf((m - CROP_DRY) / 0.25, 0.0, 1.0) * sf * pollination
		if c >= 1.0:
			world.food_store = minf(world.food_store + HARVEST_FOOD * sf, FOOD_STORE_MAX)
			soil[i] = maxf(soil[i] - HARVEST_SOIL_COST, 0.0)
			world.harvests += 1
			c = 0.0
		crop[i] = c
		veg[i] = 0.12 + 0.5 * c # crops give little ground cover: farms can erode


func _wildlife() -> void:
	# Fish: logistic growth; muddy water shrinks the habitat (carrying capacity).
	var cap := FISH_CAP * (1.0 - clampf((world.coastal_turbidity - FISH_TURB_START) / FISH_TURB_RANGE, 0.0, 0.85))
	cap *= 1.0 - DAM_FISH_PENALTY * mini(world.river_dams, 3)
	var f := world.fish
	world.fish = maxf(f + FISH_GROWTH * f * (1.0 - f / cap), 0.0)
	# Goats graze open pasture (lowland, grassland, hills without structures).
	var veg := world.vegetation_cover
	var lt := world.land_type
	var st := world.structure
	var pasture := 0.0
	for i in veg.size():
		var t := lt[i]
		if st[i] == 0 and (t == LandType.LOWLAND or t == LandType.GRASSLAND or t == LandType.HILLS):
			pasture += veg[i]
	var g := world.goats
	var gcap := maxf(pasture * GOAT_PER_VEG, 0.001)
	world.goats = maxf(g + GOAT_GROWTH * g * (1.0 - g / gcap), 0.0)
	if (world.species & SP_WOLVES) != 0:
		world.goats *= 1.0 - WOLF_PREDATION
	if pasture > 0.0 and g > 0.0:
		var eaten := minf(g * GRAZE / pasture, 0.5)
		for i in veg.size():
			var t := lt[i]
			if st[i] == 0 and (t == LandType.LOWLAND or t == LandType.GRASSLAND or t == LandType.HILLS):
				veg[i] *= 1.0 - eaten
	fish_capacity = cap


@warning_ignore("integer_division")
func _settlement() -> void:
	var si := world.settlement_index
	if si < 0 or world.villagers <= 0:
		return
	var tick := world.tick
	var v := float(world.villagers)
	# Gather food: fishing and hunting, then eat from the store.
	var catch := minf(world.fish * FISH_CATCH_RATE, v * FISH_CATCH_PER_VILLAGER)
	world.fish -= catch
	var hunt := minf(world.goats * HUNT_RATE, v * HUNT_PER_VILLAGER)
	world.goats -= hunt
	world.food_store = minf(world.food_store + catch + hunt, FOOD_STORE_MAX)
	var need := v * FOOD_PER_VILLAGER
	var eat := minf(world.food_store, need)
	world.food_store -= eat
	world.food_ema = world.food_ema * 0.9 + (eat / need) * 0.1
	# Fresh water from streams, ponds and wet soil around the village.
	var w := world.width
	var sx := si % w
	var sy := si / w
	var flow := world.flow
	var water := world.surface_water
	var moist := world.soil_moisture
	var lt := world.land_type
	var supply := 0.0
	for y in range(maxi(sy - WATER_RADIUS, 0), mini(sy + WATER_RADIUS + 1, world.height)):
		for x in range(maxi(sx - WATER_RADIUS, 0), mini(sx + WATER_RADIUS + 1, w)):
			var i := y * w + x
			if lt[i] > LandType.SHALLOW_WATER:
				supply += flow[i] + water[i] * 0.5 + maxf(moist[i] - 0.2, 0.0) * 0.02 + world.reservoir[i] * 0.1
	world.water_supply = supply
	var wneed := v * WATER_PER_VILLAGER
	world.water_ema = world.water_ema * 0.9 + minf(supply / wneed, 1.0) * 0.1
	world.labor = minf(world.labor + v * LABOR_PER_VILLAGER, labor_cap())
	_life_events(tick)
	if tick % POP_PERIOD == 0:
		_population(tick)
	world.peak_villagers = maxi(world.peak_villagers, world.villagers)


func _recent(id: int, tick: int, window: int) -> int:
	return id if events.has(id) and tick - events.tick_of(id) <= window else -1


func _life_events(tick: int) -> void:
	var si := world.settlement_index
	var c := world.coords(si)
	# Fish decline: cite muddy water only if it is actually shrinking the habitat now,
	# and recent village growth (more mouths fishing).
	if world.fish_event < 0 and world.fish < FISH_LOW:
		var mud := world.muddy_event if world.coast_muddy and world.coastal_turbidity > FISH_TURB_START else -1
		var grow := _recent(world.growth_event, tick, LIFE_CAUSE_WINDOW)
		var dam := world.dam_event if world.river_dams > 0 else -1
		var at := events.pos_of(world.muddy_event) if mud >= 0 else c
		world.fish_event = events.record(tick, EventLog.Type.FISH_DECLINE, at.x, at.y, world.fish, mud, dam, grow)
	elif world.fish_event >= 0 and world.fish > FISH_OK:
		world.fish_event = -1
	if world.goats_event < 0 and world.goats < GOATS_LOW:
		world.goats_event = events.record(tick, EventLog.Type.HERBIVORE_DECLINE, -1, -1, world.goats,
				world.drought_event, _recent(world.growth_event, tick, LIFE_CAUSE_WINDOW))
	elif world.goats_event >= 0 and world.goats > GOATS_OK:
		world.goats_event = -1
	# Food shortage: cite the food sources that are actually failing.
	if world.food_event < 0 and world.food_ema < SHORTAGE_ENTER:
		var cands := [world.fish_event, _recent(world.crop_failure_event, tick, LIFE_CAUSE_WINDOW),
				_recent(world.flood_event, tick, LIFE_CAUSE_WINDOW), world.goats_event,
				_recent(world.growth_event, tick, LIFE_CAUSE_WINDOW)]
		var cs := PackedInt32Array([-1, -1, -1])
		var k := 0
		for id in cands:
			if id >= 0 and k < 3:
				cs[k] = id
				k += 1
		world.food_event = events.record(tick, EventLog.Type.FOOD_SHORTAGE, c.x, c.y, world.food_ema, cs[0], cs[1], cs[2])
		world.last_event[si] = world.food_event
	elif world.food_event >= 0 and world.food_ema > SHORTAGE_EXIT:
		world.food_event = -1
	if world.water_event < 0 and world.water_ema < SHORTAGE_ENTER:
		var dry := world.season_event if season_of(tick) == Season.DRY else -1
		world.water_event = events.record(tick, EventLog.Type.WATER_SHORTAGE, c.x, c.y, world.water_ema, world.drought_event, dry)
		world.last_event[si] = world.water_event
	elif world.water_event >= 0 and world.water_ema > SHORTAGE_EXIT:
		world.water_event = -1


func _population(tick: int) -> void:
	var si := world.settlement_index
	var c := world.coords(si)
	if (world.food_ema < 0.6 or world.water_ema < 0.6) and not world.relaxed:
		world.villagers -= 1
		world.villagers_lost += 1
		var id := events.record(tick, EventLog.Type.POPULATION_LOSS, c.x, c.y, world.villagers,
				world.food_event if world.food_ema < 0.6 else -1, world.water_event if world.water_ema < 0.6 else -1)
		world.last_event[si] = id
	elif world.food_ema > 0.95 and world.water_ema > 0.95 and world.food_store >= world.villagers * 3.0:
		var cap := world.housing_capacity()
		if world.villagers >= cap:
			if world.housing_event < 0:
				world.housing_event = events.record(tick, EventLog.Type.HOUSING_FULL, c.x, c.y, cap)
				world.last_event[si] = world.housing_event
			return
		world.housing_event = -1
		@warning_ignore("integer_division")
		var add := mini(maxi(1, world.villagers / GROWTH_DIVISOR), cap - world.villagers)
		world.villagers += add
		world.growth_event = events.record(tick, EventLog.Type.POPULATION_GROWTH, c.x, c.y, world.villagers)
		world.last_event[si] = world.growth_event


# ---------------------------------------------------------------- rare events & species (v3)

const SP_BEES := 1
const SP_SEABIRDS := 2
const SP_FROGS := 4
const SP_WOLVES := 8
const BEE_POLLINATION := 1.15
const WOLF_PREDATION := 0.004
const SEABIRD_EGGS := 0.25          ## food per day while seabirds nest
const SPECIES_PERIOD := 10          ## days between habitat checks
const LOCUST_CHANCE := 0.01         ## per dry day
const BLOOM_CHANCE := 0.012         ## per summer day with muddy, farmed coasts
const TIDE_CHANCE := 0.008          ## per rainy-season day
const RARE_COOLDOWN := 30           ## minimum days between rare events


## Which species the island's habitat supports right now (pure function of state).
func species_supported() -> int:
	var lt := world.land_type
	var land := 0
	var forest := 0
	var wet := 0
	for i in lt.size():
		var t := lt[i]
		if t > LandType.BEACH:
			land += 1
			if t == LandType.FOREST:
				forest += 1
			if world.surface_water[i] > 0.02 or world.reservoir[i] > 0.05:
				wet += 1
	var m := 0
	if land > 0 and forest * 6 >= land and world.count_structures(WorldState.Structure.FARM) > 0:
		m |= SP_BEES
	if world.fish >= 70.0 and world.coastal_turbidity < 0.03:
		m |= SP_SEABIRDS
	if wet >= 4:
		m |= SP_FROGS
	if land > 0 and world.goats >= 22.0 and forest * 4 >= land:
		m |= SP_WOLVES
	return m


func _rare() -> void:
	var tick := world.tick
	if tick % SPECIES_PERIOD == 0:
		var now := species_supported()
		var c := world.coords(maxi(world.settlement_index, 0))
		for b in [SP_BEES, SP_SEABIRDS, SP_FROGS, SP_WOLVES]:
			if (now & b) != 0 and (world.species & b) == 0:
				events.record(tick, EventLog.Type.SPECIES_ARRIVED, c.x, c.y, b)
			elif (now & b) == 0 and (world.species & b) != 0:
				events.record(tick, EventLog.Type.SPECIES_LEFT, c.x, c.y, b)
		world.species = now
		world.species_seen |= now
	if (world.species & SP_SEABIRDS) != 0 and world.settlement_index >= 0:
		world.food_store = minf(world.food_store + SEABIRD_EGGS, FOOD_STORE_MAX)
	if events.has(world.rare_event):
		var since := tick - events.tick_of(world.rare_event)
		if since == RARE_COOLDOWN and world.villagers > 0:
			world.rare_weathered += 1 # outlasted: only now does it count toward the score
		if since < RARE_COOLDOWN:
			return
	var sn := season_of(tick)
	var roll := _chance(0, 101)
	if (sn == Season.DRY or world.drought_event >= 0) and roll < LOCUST_CHANCE:
		_locusts()
	elif sn == Season.SUMMER and roll < BLOOM_CHANCE and world.coastal_turbidity > 0.025 \
			and world.count_structures(WorldState.Structure.FARM) >= 3:
		_algal_bloom()
	elif sn == Season.WET and roll < TIDE_CHANCE:
		_king_tide()


func _forest_within(i: int, r: int) -> bool:
	var c := world.coords(i)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := c.x + dx
			var y := c.y + dy
			if world.in_bounds(x, y) and world.land_type[world.index(x, y)] == LandType.FOREST:
				return true
	return false


## Locusts strip every farm that has no forest within 2 tiles. Frogs prevent swarms.
func _locusts() -> void:
	if (world.species & SP_FROGS) != 0:
		return
	var stripped := PackedInt32Array()
	for i in world.structure.size():
		if world.structure[i] == WorldState.Structure.FARM and world.crop_growth[i] > 0.05 and not _forest_within(i, 2):
			world.crop_growth[i] = 0.0
			stripped.append(i)
	if stripped.is_empty():
		return
	var c := world.coords(stripped[0])
	var dr := world.drought_event if world.drought_event >= 0 else world.season_event
	world.rare_event = events.record(world.tick, EventLog.Type.LOCUSTS, c.x, c.y, stripped.size(), dr)
	world.rare_hits += 1
	for i in stripped: # only the farms the swarm actually stripped point at it
		world.last_event[i] = world.rare_event


## Farm runoff + muddy water: a bloom kills a third of the fish.
func _algal_bloom() -> void:
	world.fish *= 0.65
	var sea := _muddiest_shallow()
	var c := world.coords(sea) if sea >= 0 else Vector2i(-1, -1)
	var mud := world.muddy_event if world.coast_muddy else -1
	world.rare_event = events.record(world.tick, EventLog.Type.ALGAL_BLOOM, c.x, c.y, world.fish, mud)
	world.rare_hits += 1


## Sea surge over low coastal tiles without forest next to them.
func _king_tide() -> void:
	var w := world.width
	var lt := world.land_type
	var hit := 0
	var first := -1
	for i in lt.size():
		var t := lt[i]
		if t != LandType.BEACH and t != LandType.LOWLAND:
			continue
		var c := world.coords(i)
		var coastal := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x: int = c.x + d.x
			var y: int = c.y + d.y
			if world.in_bounds(x, y) and LandType.is_water(lt[y * w + x]):
				coastal = true
		if not coastal or _forest_within(i, 1):
			continue
		world.vegetation_cover[i] *= 0.5
		world.soil_moisture[i] = 1.0
		if world.structure[i] == WorldState.Structure.FARM:
			world.crop_growth[i] = 0.0
		hit += 1
		if first < 0:
			first = i
	if hit == 0:
		return
	var fc := world.coords(first)
	world.rare_event = events.record(world.tick, EventLog.Type.KING_TIDE, fc.x, fc.y, hit)
	world.rare_hits += 1


## Endless mode: each new year storms and fire risk grow 8% fiercer and rain 5% scarcer (capped).
func _escalate() -> void:
	world.climate_storm = minf(world.climate_storm * 1.08, 3.0)
	world.climate_fire = minf(world.climate_fire * 1.08, 4.0)
	world.climate_rain = maxf(world.climate_rain * 0.95, 0.45)


# ---------------------------------------------------------------- hazards (M6)

## Deterministic per-tile chance in [0, 1) without touching the shared RNG stream: hazards
## then never shift the weather sequence, and need no extra saved state.
func _chance(i: int, salt: int) -> float:
	var h := (i * 73856093) ^ (world.tick * 19349663) ^ (world.world_seed * 83492791) ^ (salt * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65536.0


@warning_ignore("integer_division")
## Wildfire: during a drought or the dry season, dry dense vegetation can ignite; fire spreads
## to dry neighbours, burns for a few days, and leaves bare land (which then erodes).
func _wildfire() -> void:
	var fire := world.fire
	var veg := world.vegetation_cover
	var moist := world.soil_moisture
	var lt := world.land_type
	var st := world.structure
	var w := world.width
	var tick := world.tick
	if world.fires_burning > 0:
		var rain_out := world.rain_today >= FIRE_RAIN_OUT
		var burning := 0
		for i in fire.size():
			var f := fire[i]
			if f == 0 or f >= FIRE_NEW:
				continue
			if rain_out:
				fire[i] = 0
				continue
			veg[i] *= 0.4
			moist[i] *= 0.7
			if st[i] == WorldState.Structure.FARM and world.crop_growth[i] > 0.0:
				_lose_harvest(i, world.fire_event)
			var b := i * 4
			for k in 4:
				var j := _nbr[b + k]
				if j < 0 or fire[j] != 0 or lt[j] <= LandType.BEACH:
					continue
				if st[j] == WorldState.Structure.SETTLEMENT or st[j] == WorldState.Structure.HOUSE:
					continue # villagers defend their homes
				if veg[j] > 0.3 and moist[j] < FIRE_SPREAD_MOIST and _chance(j, 7) < FIRE_SPREAD:
					fire[j] = FIRE_NEW | FIRE_DAYS
			f -= 1
			fire[i] = f
			if f == 0:
				_burn_out(i)
			else:
				burning += 1
		for i in fire.size():
			if fire[i] >= FIRE_NEW:
				fire[i] = fire[i] & 0x7f
				world.fire_burned += 1
				burning += 1
		world.fires_burning = burning
		if burning == 0:
			var rain_cause := world.heavy_rain_event if rain_out and tick - events.tick_of(world.heavy_rain_event) <= 1 else -1
			events.record(tick, EventLog.Type.FIRE_OUT, -1, -1, world.fire_burned, world.fire_event, rain_cause)
			world.fire_event = -1
		return
	var dry_season := season_of(tick) == Season.DRY
	if world.drought_event < 0 and not dry_season:
		return
	var p := FIRE_CHANCE * world.climate_fire * (1.0 if world.drought_event >= 0 else 0.3)
	for i in veg.size():
		if veg[i] < FIRE_VEG or moist[i] >= FIRE_MOIST or lt[i] <= LandType.BEACH:
			continue
		if st[i] != WorldState.Structure.NONE and st[i] != WorldState.Structure.FARM:
			continue
		if _chance(i, 3) < p:
			var season_cause := world.season_event if dry_season else -1
			var id := events.record(tick, EventLog.Type.WILDFIRE, i % w, i / w, veg[i], world.drought_event, season_cause)
			world.fire_event = id
			world.last_event[i] = id
			fire[i] = FIRE_DAYS
			world.fires_burning = 1
			world.fire_burned = 1
			world.fires += 1
			return


func _burn_out(i: int) -> void:
	var lt := world.land_type
	if lt[i] == LandType.FOREST:
		lt[i] = LandType.LOWLAND if world.elevation[i] < IslandGenerator.LOWLAND_MAX else LandType.GRASSLAND
	world.vegetation_cover[i] = minf(world.vegetation_cover[i], 0.04)
	world.land_cause[i] = world.fire_event
	world.last_event[i] = world.fire_event


## A river flood knocks a growing crop back by `share` (records HARVEST_LOST if it was well grown).
func _damage_harvest(i: int, cause: int, share: float) -> void:
	var c := world.coords(i)
	if world.crop_growth[i] > 0.25:
		var id := events.record(world.tick, EventLog.Type.HARVEST_LOST, c.x, c.y, world.crop_growth[i] * share, cause)
		world.last_event[i] = id
		world.crop_failure_event = id
	world.crop_growth[i] *= 1.0 - share


func _lose_harvest(i: int, cause: int) -> void:
	var c := world.coords(i)
	if world.crop_growth[i] > 0.25:
		var id := events.record(world.tick, EventLog.Type.HARVEST_LOST, c.x, c.y, world.crop_growth[i], cause)
		world.last_event[i] = id
		world.crop_failure_event = id
	world.crop_growth[i] = 0.0


@warning_ignore("integer_division")
## Floods hit farms, houses and the village when (a) deep runoff pools on the tile, or (b) the
## stream it sits beside overtops its banks: river stage (flow / sqrt(catchment)) above the
## tile's flood stage. Forests upstream slow runoff and dams store the peak, so both lower the
## stage. Causes: the heavy rain that just fell and bare/cleared land upstream.
func _floods() -> void:
	var st := world.structure
	var water := world.surface_water
	var ft := world.flood_tick
	var tick := world.tick
	var w := world.width
	var fp := floodplain
	for i in st.size():
		var s := st[i]
		if s == WorldState.Structure.NONE or s == WorldState.Structure.DAM:
			continue
		if tick - ft[i] < FLOOD_COOLDOWN:
			continue
		var r := fp[i]
		var overbank := r >= 0 and river_stage(r) >= flood_stage_for(i)
		if water[i] < FLOOD_DEPTH and not overbank:
			continue
		ft[i] = tick
		var depth := water[i]
		if overbank:
			depth = maxf(depth, FLOOD_WATER + (river_stage(r) - flood_stage_for(i)))
			water[i] = maxf(water[i], FLOOD_WATER)
		var rain := _recent(world.heavy_rain_event, tick, RAIN_CAUSE_WINDOW)
		var bare := _upstream_bare(r if overbank else i, tick)
		var id := events.record(tick, EventLog.Type.FLOOD, i % w, i / w, depth, rain, bare)
		world.flood_event = id
		world.last_event[i] = id
		world.floods += 1
		if overbank:
			# floodwater drops fresh silt: floodplains are fertile, which is why people farm them
			world.soil_depth[i] = minf(world.soil_depth[i] + FLOOD_SILT, 1.0)
		if s == WorldState.Structure.FARM:
			if overbank and water[i] < FLOOD_DEPTH:
				_damage_harvest(i, id, 0.5)
			else:
				_lose_harvest(i, id)
		else:
			world.food_store *= 1.0 - FLOOD_FOOD_LOSS


## Most recent clearing / burn event among tiles draining into i (up to 6 steps upstream).
func _upstream_bare(i: int, tick: int) -> int:
	var best := -1
	var best_t := -1
	var frontier := [i]
	for depth in 6:
		var next := []
		for t in frontier:
			for k in 4:
				var j := _nbr[t * 4 + k]
				if j < 0 or _down[j] != t:
					continue
				next.append(j)
				var lc := world.land_cause[j]
				var ty := events.type_of(lc)
				if ty == EventLog.Type.TREES_CLEARED or ty == EventLog.Type.LAND_CLEARED or ty == EventLog.Type.WILDFIRE:
					var et := events.tick_of(lc)
					if tick - et <= FLOOD_CAUSE_WINDOW and et > best_t:
						best = lc
						best_t = et
		frontier = next
	return best


# ---------------------------------------------------------------- island health (M6)

## Keystone meter 0..100: a weighted blend of plant cover, topsoil, clear coastal water, fish,
## wild goats and how well the village is fed and watered. Pure function of current state.
func _keystone() -> void:
	var veg := world.vegetation_cover
	var soil := world.soil_depth
	var lt := world.land_type
	var vs := 0.0
	var ss := 0.0
	var land := 0
	for i in veg.size():
		if lt[i] > LandType.BEACH:
			vs += veg[i]
			ss += soil[i]
			land += 1
	if land == 0:
		return
	world.k_plants = clampf(vs / land / 0.55, 0.0, 1.0)
	world.k_soil = clampf(ss / land / 0.75, 0.0, 1.0)
	world.k_water = 1.0 - clampf((world.coastal_turbidity - 0.01) / 0.05, 0.0, 1.0)
	world.k_fish = clampf(world.fish / FISH_CAP, 0.0, 1.0)
	world.k_wildlife = clampf(world.goats / 25.0, 0.0, 1.0)
	world.k_village = minf(world.food_ema, world.water_ema) if world.villagers > 0 else 0.0
	world.keystone = 100.0 * (0.2 * world.k_plants + 0.2 * world.k_soil + 0.15 * world.k_water
			+ 0.15 * world.k_fish + 0.1 * world.k_wildlife + 0.2 * world.k_village)


## Chebyshev distance from tile i to the settlement (large if none).
func distance_to_settlement(x: int, y: int) -> int:
	if world.settlement_index < 0:
		return 1 << 30
	var c := world.coords(world.settlement_index)
	return maxi(absi(c.x - x), absi(c.y - y))


## Recomputes derived (unsaved) values after setup or load, without advancing time.
func update_derived() -> void:
	_rebuild_dams()
	_keystone()


## True if a dam at (x, y) would sit on a main river and block fish runs.
func dam_blocks_fish(x: int, y: int) -> bool:
	return world.in_bounds(x, y) and upstream_area[world.index(x, y)] >= RIVER_DAM_AREA


func labor_cap() -> float:
	return LABOR_CAP_BASE + world.villagers


# ---------------------------------------------------------------- actions

## [labor, wood] this action costs now (relaxed halves, sandbox free build zeroes).
func action_cost(action: int) -> Vector2:
	if world.free_build or not ACTION_COST.has(action):
		return Vector2.ZERO
	var c: Array = ACTION_COST[action]
	var k := 0.5 if world.relaxed else 1.0
	return Vector2(c[0] * k, c[1] * k)


func _near_village_or_house(x: int, y: int) -> bool:
	if distance_to_settlement(x, y) <= HOUSE_RADIUS:
		return true
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var xx := x + dx
			var yy := y + dy
			if world.in_bounds(xx, yy) and world.structure[world.index(xx, yy)] == WorldState.Structure.HOUSE:
				return true
	return false


## Validates the tile rule only (no cost check). Returns "" if allowed, else a short reason.
func tile_rule(action: int, x: int, y: int) -> String:
	if not world.in_bounds(x, y):
		return "Outside the island"
	var i := world.index(x, y)
	var t := world.land_type[i]
	var st := world.structure[i]
	if LandType.is_water(t) and action != Action.NONE:
		return "That's open water"
	match action:
		Action.CLEAR_TREES:
			if st != WorldState.Structure.NONE:
				return "Something is built here"
			if t == LandType.FOREST:
				return ""
			if t == LandType.BEACH or world.vegetation_cover[i] < 0.2:
				return "No trees here" if t != LandType.BEACH else "Nothing to clear on the beach"
			return ""
		Action.PLANT_TREES:
			if st != WorldState.Structure.NONE:
				return "Something is built here"
			if t == LandType.FOREST:
				return "Already a forest"
			if t in [LandType.LOWLAND, LandType.GRASSLAND, LandType.HILLS]:
				return "" if world.fire[i] == 0 else "It's on fire!"
			return "Trees can't grow here"
		Action.BUILD_FARM:
			if st != WorldState.Structure.NONE:
				return "Something is built here"
			if t == LandType.FOREST:
				return "Clear the trees first"
			if t != LandType.LOWLAND and t != LandType.GRASSLAND:
				return "Farms need lowland or grassland"
			if distance_to_settlement(x, y) > FARM_RADIUS:
				return "Too far from the village"
			return ""
		Action.BUILD_HOUSE:
			if st != WorldState.Structure.NONE:
				return "Something is built here"
			if t == LandType.FOREST:
				return "Clear the trees first"
			if t == LandType.HILLS:
				return "Too steep to build a house"
			if not _near_village_or_house(x, y):
				return "Houses must join the village"
			return ""
		Action.BUILD_DAM:
			if st != WorldState.Structure.NONE:
				return "Something is built here"
			if t == LandType.BEACH:
				return "Dams need solid ground"
			if upstream_area[i] < DAM_MIN_AREA:
				return "Dams need a stream - pick a tile where water gathers"
			return ""
		Action.RESTORE_LAND:
			if st != WorldState.Structure.NONE:
				return "Something is built here"
			if t == LandType.BEACH:
				return "Nothing to restore on the beach"
			if world.fire[i] != 0:
				return "It's on fire!"
			var lct := events.type_of(world.land_cause[i])
			var damaged := lct == EventLog.Type.WILDFIRE or lct == EventLog.Type.TREES_CLEARED or lct == EventLog.Type.LAND_CLEARED
			if world.soil_depth[i] >= 0.6 and world.vegetation_cover[i] >= 0.25 and not damaged:
				return "This land is healthy already"
			return ""
		Action.DEMOLISH:
			if st == WorldState.Structure.SETTLEMENT:
				return "The village centre can't be removed"
			if st == WorldState.Structure.NONE:
				return "Nothing built here"
			return ""
	return "Unknown action"


## Validates without mutating. Returns "" if allowed, else a short reason (tile rule or cost).
func can_apply(action: int, x: int, y: int) -> String:
	var r := tile_rule(action, x, y)
	if r != "":
		return r
	var c := action_cost(action)
	if world.labor + 1e-6 < c.x:
		return "Not enough labor: needs %d, you have %d" % [ceili(c.x), floori(world.labor)]
	if world.wood + 1e-6 < c.y:
		return "Not enough wood: needs %d, you have %d (clear forest for wood)" % [ceili(c.y), floori(world.wood)]
	return ""


## Applies a player action between ticks. Returns true on success.
func apply_action(action: int, x: int, y: int) -> bool:
	if can_apply(action, x, y) != "":
		return false
	var i := world.index(x, y)
	var c := action_cost(action)
	world.labor -= c.x
	world.wood -= c.y
	var ev := -1
	match action:
		Action.CLEAR_TREES:
			var was_forest := world.land_type[i] == LandType.FOREST
			if was_forest:
				world.land_type[i] = LandType.LOWLAND if world.elevation[i] < IslandGenerator.LOWLAND_MAX else LandType.GRASSLAND
				world.wood = minf(world.wood + WOOD_PER_FOREST, WOOD_MAX)
			world.vegetation_cover[i] = 0.06
			ev = events.record(world.tick, EventLog.Type.TREES_CLEARED if was_forest else EventLog.Type.LAND_CLEARED,
					x, y, WOOD_PER_FOREST if was_forest else 0.0)
		Action.PLANT_TREES:
			world.land_type[i] = LandType.FOREST
			world.vegetation_cover[i] = maxf(world.vegetation_cover[i], 0.25)
			world.trees_planted += 1
			ev = events.record(world.tick, EventLog.Type.TREES_PLANTED, x, y, 0.0)
		Action.BUILD_FARM:
			world.structure[i] = WorldState.Structure.FARM
			world.crop_growth[i] = 0.0
			world.crop_stress[i] = 0
			world.vegetation_cover[i] = 0.12
			world.farms_built += 1
			ev = events.record(world.tick, EventLog.Type.FARM_BUILT, x, y, 0.0)
		Action.BUILD_HOUSE:
			world.structure[i] = WorldState.Structure.HOUSE
			world.vegetation_cover[i] = minf(world.vegetation_cover[i], 0.15)
			world.houses_built += 1
			world.housing_event = -1
			ev = events.record(world.tick, EventLog.Type.HOUSE_BUILT, x, y, world.housing_capacity())
		Action.BUILD_DAM:
			world.structure[i] = WorldState.Structure.DAM
			world.reservoir[i] = 0.0
			world.dams_built += 1
			ev = events.record(world.tick, EventLog.Type.DAM_BUILT, x, y, upstream_area[i])
			world.dam_event = ev
			_rebuild_dams()
		Action.RESTORE_LAND:
			world.soil_depth[i] = minf(world.soil_depth[i] + 0.25, 1.0)
			world.vegetation_cover[i] = maxf(world.vegetation_cover[i], 0.3)
			world.soil_moisture[i] = minf(world.soil_moisture[i] + 0.1, 1.0)
			world.land_restored += 1
			ev = events.record(world.tick, EventLog.Type.LAND_RESTORED, x, y, 0.0)
		Action.DEMOLISH:
			var old := world.structure[i]
			world.structure[i] = WorldState.Structure.NONE
			world.crop_growth[i] = 0.0
			world.reservoir[i] = 0.0
			var refund: float = 0.0 if world.free_build else float(ACTION_COST.get(_action_for_structure(old), [0.0, 0.0])[1]) * 0.5
			world.wood = minf(world.wood + refund, WOOD_MAX)
			ev = events.record(world.tick, EventLog.Type.STRUCTURE_REMOVED, x, y, old)
			if old == WorldState.Structure.DAM:
				_rebuild_dams()
	world.land_cause[i] = ev
	world.last_event[i] = ev
	return true


static func _action_for_structure(s: int) -> int:
	match s:
		WorldState.Structure.FARM: return Action.BUILD_FARM
		WorldState.Structure.HOUSE: return Action.BUILD_HOUSE
		WorldState.Structure.DAM: return Action.BUILD_DAM
	return Action.NONE


## World checksum plus the event log (full deterministic state minus the RNG).
func state_checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(world.checksum().to_utf8_buffer())
	ctx.update(events.checksum_bytes())
	ctx.update(var_to_bytes([rng.seed, rng.state]))
	if scenario != null:
		ctx.update(var_to_bytes(scenario.to_dict()))
	return ctx.finish().hex_encode()
