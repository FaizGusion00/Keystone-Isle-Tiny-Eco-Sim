class_name Simulation
extends RefCounted
## Deterministic tick-based ecosystem simulation over a WorldState.
## - Never reads frame time; one call to step() == one in-game day.
## - All randomness comes from `rng` (seeded, state saved).
## - Systems run in a fixed order (see step()).
## - Water and sediment use two buffers (read current, write next, swap).
## - Tick loops iterate local aliases of Packed arrays and allocate nothing.

enum Action { NONE, CLEAR_TREES, PLANT_TREES, BUILD_FARM }

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
const POP_PERIOD := 30
const LIFE_CAUSE_WINDOW := 60

var world: WorldState
var rng := RandomNumberGenerator.new()
var events := EventLog.new()
var fish_capacity := FISH_CAP  ## derived each tick (not saved)

var _water_next := PackedFloat32Array()
var _sed_next := PackedFloat32Array()
var _nbr := PackedInt32Array()   ## 4 neighbour indices per tile, -1 outside the map
var _down := PackedInt32Array()  ## steepest-descent neighbour by terrain elevation (-1 = pit)
var upstream_area := PackedInt32Array() ## tiles draining through each tile (static, for rivers)
var _veg_cap := PackedFloat32Array()
var _erodibility := PackedFloat32Array()


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
	_erodibility.resize(LandType.COUNT)
	_erodibility.fill(1.0)
	_erodibility[LandType.BEACH] = 0.1 # coarse sand barely suspends


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
	_detect_events()
	_crops()
	_wildlife()
	_settlement()


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
		var move := wi * FLOW_MAX_FRACTION if best_h < 0.0 else minf(wi * FLOW_MAX_FRACTION, (hi - best_h) * 0.5)
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
			var bare_cause := lc if events.type_of(lc) == EventLog.Type.TREES_CLEARED else -1
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
		var c := crop[i] + (1.0 / CROP_DAYS) * clampf((m - CROP_DRY) / 0.25, 0.0, 1.0) * sf
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
				supply += flow[i] + water[i] * 0.5 + maxf(moist[i] - 0.2, 0.0) * 0.02
	world.water_supply = supply
	var wneed := v * WATER_PER_VILLAGER
	world.water_ema = world.water_ema * 0.9 + minf(supply / wneed, 1.0) * 0.1
	_life_events(tick)
	if tick % POP_PERIOD == 0:
		_population(tick)


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
		var at := events.pos_of(world.muddy_event) if mud >= 0 else c
		world.fish_event = events.record(tick, EventLog.Type.FISH_DECLINE, at.x, at.y, world.fish, mud, grow)
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
				world.goats_event, _recent(world.growth_event, tick, LIFE_CAUSE_WINDOW)]
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
		world.water_event = events.record(tick, EventLog.Type.WATER_SHORTAGE, c.x, c.y, world.water_ema, world.drought_event)
		world.last_event[si] = world.water_event
	elif world.water_event >= 0 and world.water_ema > SHORTAGE_EXIT:
		world.water_event = -1


func _population(tick: int) -> void:
	var si := world.settlement_index
	var c := world.coords(si)
	if world.food_ema < 0.6 or world.water_ema < 0.6:
		world.villagers -= 1
		var id := events.record(tick, EventLog.Type.POPULATION_LOSS, c.x, c.y, world.villagers,
				world.food_event if world.food_ema < 0.6 else -1, world.water_event if world.water_ema < 0.6 else -1)
		world.last_event[si] = id
	elif world.food_ema > 0.95 and world.water_ema > 0.95 and world.food_store >= world.villagers * 3.0:
		world.villagers += 1
		world.growth_event = events.record(tick, EventLog.Type.POPULATION_GROWTH, c.x, c.y, world.villagers)
		world.last_event[si] = world.growth_event


## Chebyshev distance from tile i to the settlement (large if none).
func distance_to_settlement(x: int, y: int) -> int:
	if world.settlement_index < 0:
		return 1 << 30
	var c := world.coords(world.settlement_index)
	return maxi(absi(c.x - x), absi(c.y - y))


# ---------------------------------------------------------------- actions

## Validates without mutating. Returns "" if allowed, else a short reason.
func can_apply(action: int, x: int, y: int) -> String:
	if not world.in_bounds(x, y):
		return "Outside the island"
	var i := world.index(x, y)
	var t := world.land_type[i]
	var st := world.structure[i]
	match action:
		Action.CLEAR_TREES:
			return "" if t == LandType.FOREST else "No trees here"
		Action.PLANT_TREES:
			if st != WorldState.Structure.NONE:
				return "Something is built here"
			if t in [LandType.LOWLAND, LandType.GRASSLAND, LandType.HILLS]:
				return ""
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
	return "Unknown action"


## Applies a player action between ticks. Returns true on success.
func apply_action(action: int, x: int, y: int) -> bool:
	if can_apply(action, x, y) != "":
		return false
	var i := world.index(x, y)
	var ev := -1
	match action:
		Action.CLEAR_TREES:
			world.land_type[i] = LandType.LOWLAND if world.elevation[i] < IslandGenerator.LOWLAND_MAX else LandType.GRASSLAND
			world.vegetation_cover[i] = 0.06
			ev = events.record(world.tick, EventLog.Type.TREES_CLEARED, x, y, 0.0)
		Action.PLANT_TREES:
			world.land_type[i] = LandType.FOREST
			world.vegetation_cover[i] = maxf(world.vegetation_cover[i], 0.25)
			ev = events.record(world.tick, EventLog.Type.TREES_PLANTED, x, y, 0.0)
		Action.BUILD_FARM:
			world.structure[i] = WorldState.Structure.FARM
			world.crop_growth[i] = 0.0
			world.crop_stress[i] = 0
			world.vegetation_cover[i] = 0.12
			world.farms_built += 1
			ev = events.record(world.tick, EventLog.Type.FARM_BUILT, x, y, 0.0)
	world.land_cause[i] = ev
	world.last_event[i] = ev
	return true


## World checksum plus the event log (full deterministic state minus the RNG).
func state_checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(world.checksum().to_utf8_buffer())
	ctx.update(events.checksum_bytes())
	ctx.update(var_to_bytes([rng.seed, rng.state]))
	return ctx.finish().hex_encode()
