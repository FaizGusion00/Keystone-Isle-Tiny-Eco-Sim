extends TestCase
## Milestone 6: tools & costs, dams, floods, wildfire, seasons, housing, island health.

const A := Simulation.Action


func _find(sim: Simulation, pred: Callable) -> Vector2i:
	var ws := sim.world
	var c := ws.coords(ws.settlement_index)
	for r in range(0, ws.width):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := Vector2i(c.x + dx, c.y + dy)
				if ws.in_bounds(p.x, p.y) and pred.call(p):
					return p
	return Vector2i(-1, -1)


func test_costs_and_reasons() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	assert_eq(sim.action_cost(A.BUILD_HOUSE), Vector2(3, 6))
	var p := _find(sim, func(q: Vector2i) -> bool: return sim.tile_rule(A.BUILD_HOUSE, q.x, q.y) == "")
	assert_true(p.x >= 0, "a house site exists next to the village")
	ws.wood = 2.0
	assert_true(sim.can_apply(A.BUILD_HOUSE, p.x, p.y).begins_with("Not enough wood"), "wood is checked")
	assert_false(sim.apply_action(A.BUILD_HOUSE, p.x, p.y))
	ws.wood = 20.0
	ws.labor = 1.0
	assert_true(sim.can_apply(A.BUILD_HOUSE, p.x, p.y).begins_with("Not enough labor"))
	ws.labor = 10.0
	assert_true(sim.apply_action(A.BUILD_HOUSE, p.x, p.y))
	assert_near(ws.wood, 14.0)
	assert_near(ws.labor, 7.0)
	ws.relaxed = true
	assert_eq(sim.action_cost(A.BUILD_DAM), Vector2(3, 5), "relaxed halves costs")
	ws.free_build = true
	assert_eq(sim.action_cost(A.BUILD_DAM), Vector2.ZERO)


func test_clearing_forest_yields_wood_and_labor_regenerates() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	var f := _find(sim, func(q: Vector2i) -> bool: return ws.land_type[ws.index(q.x, q.y)] == LandType.FOREST)
	var w0 := ws.wood
	assert_true(sim.apply_action(A.CLEAR_TREES, f.x, f.y))
	assert_near(ws.wood, w0 + Simulation.WOOD_PER_FOREST)
	ws.labor = 0.0
	sim.step()
	assert_near(ws.labor, ws.villagers * Simulation.LABOR_PER_VILLAGER, 1e-3)


func test_planting_then_clearing_gives_no_wood() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	var g := _find(sim, func(q: Vector2i) -> bool:
		var i := ws.index(q.x, q.y)
		return ws.land_type[i] == LandType.GRASSLAND and ws.structure[i] == 0 and sim.tile_rule(A.PLANT_TREES, q.x, q.y) == "")
	assert_true(sim.apply_action(A.PLANT_TREES, g.x, g.y))
	var w0 := ws.wood
	assert_true(sim.apply_action(A.CLEAR_TREES, g.x, g.y), "young forest can still be cleared")
	assert_near(ws.wood, w0, 1e-6, "no wood from a sapling stand")
	assert_eq(Simulation.wood_yield(0.9), Simulation.WOOD_PER_FOREST)
	assert_eq(Simulation.wood_yield(0.60), 0.0, "not yet mature")
	assert_eq(Simulation.wood_yield(0.65), 1.0)
	assert_eq(Simulation.wood_yield(0.70), 2.0, "halfway must not floor down to 1")
	assert_eq(Simulation.wood_yield(0.75), 3.0)
	assert_eq(Simulation.wood_yield(0.79), 3.0, "still short of a full stand")
	assert_eq(Simulation.wood_yield(0.80), Simulation.WOOD_PER_FOREST)


func test_tool_rules() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	ws.free_build = true
	var c := ws.coords(ws.settlement_index)
	var far := _find(sim, func(q: Vector2i) -> bool:
		var t := ws.land_type[ws.index(q.x, q.y)]
		return (t == LandType.GRASSLAND or t == LandType.LOWLAND) and sim.distance_to_settlement(q.x, q.y) > Simulation.FARM_RADIUS)
	assert_eq(sim.can_apply(A.BUILD_FARM, far.x, far.y), "Too far from the village")
	assert_eq(sim.can_apply(A.BUILD_HOUSE, far.x, far.y), "Houses must join the village")
	assert_eq(sim.can_apply(A.DEMOLISH, c.x, c.y), "The village centre can't be removed")
	assert_eq(sim.can_apply(A.DEMOLISH, far.x, far.y), "Nothing built here")
	var dry := _find(sim, func(q: Vector2i) -> bool:
		var i := ws.index(q.x, q.y)
		return ws.land_type[i] > LandType.BEACH and ws.structure[i] == 0 and sim.upstream_area[i] < Simulation.DAM_MIN_AREA)
	assert_eq(sim.can_apply(A.BUILD_DAM, dry.x, dry.y), "Dams need a stream - pick a tile where water gathers")
	var forest := _find(sim, func(q: Vector2i) -> bool: return ws.land_type[ws.index(q.x, q.y)] == LandType.FOREST)
	assert_eq(sim.can_apply(A.BUILD_FARM, forest.x, forest.y), "Clear the trees first")
	assert_eq(sim.can_apply(A.PLANT_TREES, forest.x, forest.y), "Already a forest")
	# build, then remove: structure goes, an event explains it, half the wood comes back
	var site := _find(sim, func(q: Vector2i) -> bool: return sim.tile_rule(A.BUILD_FARM, q.x, q.y) == "")
	assert_true(sim.apply_action(A.BUILD_FARM, site.x, site.y))
	assert_true(sim.apply_action(A.DEMOLISH, site.x, site.y))
	assert_eq(ws.structure[ws.index(site.x, site.y)], WorldState.Structure.NONE)
	assert_eq(sim.events.type_of(sim.events.next_id - 1), EventLog.Type.STRUCTURE_REMOVED)


func test_restore_land_heals_cleared_tile() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	ws.free_build = true
	var f := _find(sim, func(q: Vector2i) -> bool: return ws.land_type[ws.index(q.x, q.y)] == LandType.FOREST)
	var i := ws.index(f.x, f.y)
	assert_ne(sim.can_apply(A.RESTORE_LAND, f.x, f.y), "", "healthy forest needs no restoring")
	sim.apply_action(A.CLEAR_TREES, f.x, f.y)
	ws.soil_depth[i] = 0.2
	assert_eq(sim.can_apply(A.RESTORE_LAND, f.x, f.y), "")
	assert_true(sim.apply_action(A.RESTORE_LAND, f.x, f.y))
	assert_true(ws.soil_depth[i] > 0.4 and ws.vegetation_cover[i] >= 0.3, "soil and cover restored")
	assert_eq(ws.land_restored, 1)


func test_houses_raise_housing_capacity() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	ws.free_build = true
	ws.villagers = Simulation.HOUSING_BASE
	ws.food_ema = 1.0
	ws.water_ema = 1.0
	ws.food_store = 100.0
	sim._population(ws.tick)
	assert_eq(ws.villagers, Simulation.HOUSING_BASE, "no room to grow")
	assert_eq(sim.events.type_of(ws.housing_event), EventLog.Type.HOUSING_FULL)
	var p := _find(sim, func(q: Vector2i) -> bool: return sim.tile_rule(A.BUILD_HOUSE, q.x, q.y) == "")
	assert_true(sim.apply_action(A.BUILD_HOUSE, p.x, p.y))
	assert_eq(ws.housing_capacity(), Simulation.HOUSING_BASE + Simulation.HOUSE_CAPACITY)
	sim._population(ws.tick)
	assert_eq(ws.villagers, Simulation.HOUSING_BASE + 1, "a new house lets the village grow")


func test_dam_stores_water_irrigates_and_traps_mud() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	ws.free_build = true
	var p := _find(sim, func(q: Vector2i) -> bool:
		return sim.tile_rule(A.BUILD_DAM, q.x, q.y) == "" and not sim.dam_blocks_fish(q.x, q.y))
	assert_true(p.x >= 0, "a small-stream dam site exists")
	assert_true(sim.apply_action(A.BUILD_DAM, p.x, p.y))
	var i := ws.index(p.x, p.y)
	assert_eq(sim.events.type_of(ws.dam_event), EventLog.Type.DAM_BUILT)
	var best := 0.0
	for t in 60:
		sim.step()
		best = maxf(best, ws.reservoir[i])
	assert_true(best > 0.2, "reservoir fills in the rainy season (%.2f)" % best)
	assert_true(best <= Simulation.DAM_CAPACITY + 1e-4, "never above capacity")
	assert_eq(ws.river_dams, 0, "small stream: fish runs not blocked")


func test_river_dam_costs_fish_habitat_with_cause() -> void:
	var a := Simulation.create(12345, 32)
	var b := Simulation.create(12345, 32)
	b.world.free_build = true
	var p := _find(b, func(q: Vector2i) -> bool:
		return b.tile_rule(A.BUILD_DAM, q.x, q.y) == "" and b.dam_blocks_fish(q.x, q.y))
	assert_true(p.x >= 0, "a river dam site exists")
	assert_true(b.apply_action(A.BUILD_DAM, p.x, p.y))
	assert_eq(b.world.river_dams, 1)
	a.step()
	b.step()
	assert_near(b.fish_capacity, a.fish_capacity * (1.0 - Simulation.DAM_FISH_PENALTY), 0.5)
	b.world.fish = Simulation.FISH_LOW - 1.0
	b.world.fish_event = -1
	b.step()
	assert_eq(b.events.type_of(b.world.fish_event), EventLog.Type.FISH_DECLINE)
	assert_true(b.events.causes_of(b.world.fish_event).has(b.world.dam_event), "the dam is a recorded cause")


func test_flood_hits_farm_and_cites_upstream_clearing() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	ws.free_build = true
	var farm := _find(sim, func(q: Vector2i) -> bool:
		var i := ws.index(q.x, q.y)
		return sim.tile_rule(A.BUILD_FARM, q.x, q.y) == "" and sim.upstream_area[i] >= 3)
	assert_true(sim.apply_action(A.BUILD_FARM, farm.x, farm.y))
	var fi := ws.index(farm.x, farm.y)
	var up := -1
	for k in 4:
		var j: int = sim._nbr[fi * 4 + k]
		if j >= 0 and sim._down[j] == fi and ws.land_type[j] > LandType.BEACH:
			up = j
	assert_true(up >= 0, "an upstream neighbour")
	var u := ws.coords(up)
	ws.land_type[up] = LandType.GRASSLAND
	ws.vegetation_cover[up] = 0.5
	assert_true(sim.apply_action(A.CLEAR_TREES, u.x, u.y))
	var clear_id := sim.events.next_id - 1
	ws.crop_growth[fi] = 0.6
	ws.surface_water[fi] = Simulation.FLOOD_DEPTH + 0.2
	sim._floods()
	assert_eq(sim.events.type_of(ws.flood_event), EventLog.Type.FLOOD)
	assert_true(sim.events.causes_of(ws.flood_event).has(clear_id), "upstream clearing is a cause")
	assert_near(ws.crop_growth[fi], 0.0)
	assert_eq(sim.events.type_of(ws.crop_failure_event), EventLog.Type.HARVEST_LOST)
	var n := ws.floods
	sim._floods()
	assert_eq(ws.floods, n, "cooldown: one flood per spell")


func test_wildfire_ignites_in_drought_spreads_and_burns_out() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	ws.drought_event = sim.events.record(ws.tick, EventLog.Type.DROUGHT, -1, -1, 12.0)
	for i in ws.tile_count():
		if ws.land_type[i] > LandType.BEACH and ws.structure[i] == 0:
			ws.vegetation_cover[i] = 0.8
			ws.soil_moisture[i] = 0.01
	ws.climate_fire = 400.0
	sim._wildfire()
	assert_eq(ws.fires, 1, "dry land ignites during a drought")
	var fire_id := ws.fire_event
	assert_true(sim.events.causes_of(fire_id).has(ws.drought_event), "fire cites the drought")
	ws.rain_today = 0.0
	for k in 200:
		if ws.fires_burning == 0:
			break
		sim._wildfire()
	assert_eq(ws.fires_burning, 0, "fire burns out")
	assert_true(ws.fire_burned > 1, "fire spread (%d tiles)" % ws.fire_burned)
	var burned := 0
	for i in ws.tile_count():
		if ws.land_cause[i] == fire_id:
			burned += 1
			assert_true(ws.vegetation_cover[i] <= 0.04 + 1e-6)
			assert_ne(ws.land_type[i], LandType.FOREST)
	assert_eq(burned, ws.fire_burned)
	var out := sim.events.next_id - 1
	assert_eq(sim.events.type_of(out), EventLog.Type.FIRE_OUT)
	assert_true(sim.events.causes_of(out).has(fire_id))


func test_rain_puts_out_fire_and_homes_do_not_burn() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	var si := ws.settlement_index
	for i in ws.tile_count():
		if ws.land_type[i] > LandType.BEACH:
			ws.vegetation_cover[i] = 0.8
			ws.soil_moisture[i] = 0.01
	var nb: int = sim._nbr[si * 4]
	ws.fire_event = sim.events.record(ws.tick, EventLog.Type.WILDFIRE, 0, 0, 0.8)
	ws.fire[nb] = Simulation.FIRE_DAYS
	ws.fires_burning = 1
	for k in 5:
		sim._wildfire()
	assert_eq(ws.fire[si], 0, "the village centre never burns")
	ws.rain_today = 0.05
	sim._wildfire()
	assert_eq(ws.fires_burning, 0, "rain puts the fire out")


func test_seasons_and_season_events() -> void:
	assert_eq(Simulation.season_of(0), Simulation.Season.SPRING)
	assert_eq(Simulation.season_of(30), Simulation.Season.WET)
	assert_eq(Simulation.season_of(60), Simulation.Season.SUMMER)
	assert_eq(Simulation.season_of(90), Simulation.Season.DRY)
	assert_eq(Simulation.season_of(120), Simulation.Season.SPRING)
	var sim := Simulation.create(12345, 32)
	sim.run(80)
	var wet := -1
	var dry := -1
	for id in sim.events.recent(EventLog.CAPACITY):
		match sim.events.type_of(id):
			EventLog.Type.WET_SEASON: wet = sim.events.tick_of(id)
			EventLog.Type.DRY_SEASON: dry = sim.events.tick_of(id)
	assert_eq(wet, 15)
	assert_eq(dry, 75)


func test_climate_defaults_keep_v1_weather() -> void:
	var a := Simulation.create(777, 32)
	var b := Simulation.create(777, 32)
	b.world.climate_rain = 0.5
	var ra := 0.0
	var rb := 0.0
	for t in 120:
		a.step()
		b.step()
		ra += a.world.rain_today
		rb += b.world.rain_today
	assert_true(rb < ra * 0.7, "less rain with a dry climate (%.2f vs %.2f)" % [rb, ra])


func test_keystone_reflects_island_health() -> void:
	var healthy := ScenarioCatalog.create_sim(ScenarioCatalog.get_def("living_island"))
	var logged := ScenarioCatalog.create_sim(ScenarioCatalog.get_def("recovery"))
	assert_true(healthy.world.keystone > 0.0 and healthy.world.keystone <= 100.0)
	assert_true(logged.world.keystone < healthy.world.keystone - 15.0,
			"a logged island is less healthy (%.0f vs %.0f)" % [logged.world.keystone, healthy.world.keystone])
	assert_true(logged.world.coast_muddy, "recovery starts with muddy water")
	assert_true(logged.events.causes_of(logged.world.muddy_event).size() > 0, "and the mud is explained")


func test_presets_shape_the_island() -> void:
	var base := IslandGenerator.generate(99, 32, 32)
	var temperate := IslandGenerator.generate(99, 32, 32, IslandGenerator.Preset.TEMPERATE)
	assert_eq(base.land_type, temperate.land_type, "temperate is the original generator")
	var lush := IslandGenerator.generate(99, 32, 32, IslandGenerator.Preset.LUSH)
	var arid := IslandGenerator.generate(99, 32, 32, IslandGenerator.Preset.ARID)
	assert_true(lush.count_land(LandType.FOREST) > arid.count_land(LandType.FOREST), "lush has more forest than arid")


func test_hazard_runs_are_deterministic() -> void:
	var d := ScenarioCatalog.get_def("tinderbox")
	var a := ScenarioCatalog.create_sim(d)
	var b := ScenarioCatalog.create_sim(d)
	a.run(360)
	b.run(360)
	assert_eq(a.state_checksum(), b.state_checksum())
	assert_true(a.world.fires > 0, "tinderbox had a fire")


func test_river_overbank_floods_floodplain_farms() -> void:
	var sim := ScenarioCatalog.create_sim(ScenarioCatalog.get_def("floodplain"))
	var ws := sim.world
	ws.free_build = true
	# high ground away from rivers never floods from a river
	var safe := 0
	var low := -1
	for i in ws.tile_count():
		if ws.land_type[i] <= LandType.SHALLOW_WATER:
			continue
		if sim.floodplain[i] < 0:
			safe += 1
			assert_eq(sim.flood_risk(i), 0)
		elif low < 0 and sim.flood_risk(i) == 2 and sim.upstream_area[i] < Simulation.FLOODPLAIN_AREA:
			var c := ws.coords(i)
			if sim.apply_action(A.BUILD_FARM, c.x, c.y):
				low = i
	assert_true(safe > 0, "most of the island is not floodplain")
	assert_true(low >= 0, "a low-bank farm site exists")
	var r := sim.floodplain[low]
	assert_true(sim.flood_stage_for(low) >= Simulation.FLOOD_STAGE, "banks need at least bankfull")
	# force a big flow down the river: the low bank floods with a cause, drops silt
	ws.flow[r] = (sim.flood_stage_for(low) + 0.1) * sqrt(float(sim.upstream_area[r]))
	ws.soil_depth[low] = 0.5
	var soil := ws.soil_depth[low]
	ws.crop_growth[low] = 0.6
	sim._floods()
	assert_eq(ws.flood_tick[low], ws.tick, "overbank flood recorded on the farm")
	assert_true(ws.soil_depth[low] > soil, "flood leaves silt")
	assert_true(ws.crop_growth[low] < 0.6 and ws.crop_growth[low] > 0.0, "river flood damages, not wipes, the crop")
	assert_true(ws.surface_water[low] >= Simulation.FLOOD_WATER - 0.001, "flood water is visible")
	# a year on the floodplain with farms on the low banks sees real floods
	var more := 3
	for i in ws.tile_count():
		if more > 0 and sim.flood_risk(i) == 2:
			var c := ws.coords(i)
			if sim.apply_action(A.BUILD_FARM, c.x, c.y):
				more -= 1
	sim.run(360)
	assert_true(ws.floods >= 2, "floodplain farms flood several times a year (%d)" % ws.floods)


func test_forest_slows_runoff() -> void:
	var a := ScenarioCatalog.create_sim(ScenarioCatalog.get_def("floodplain"))
	var b := ScenarioCatalog.create_sim(ScenarioCatalog.get_def("floodplain"))
	for i in b.world.tile_count():
		if b.world.land_type[i] > LandType.SHALLOW_WATER:
			b.world.vegetation_cover[i] = 0.0
	var pa := 0.0
	var pb := 0.0
	for t in 120:
		a.step()
		b.step()
		for i in a.world.tile_count():
			if a.upstream_area[i] >= 40:
				pa = maxf(pa, a.river_stage(i))
				pb = maxf(pb, b.river_stage(i))
	assert_true(pa < pb, "a forested island's rivers peak lower (%.3f vs bare %.3f)" % [pa, pb])
