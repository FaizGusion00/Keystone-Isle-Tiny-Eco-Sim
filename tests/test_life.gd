extends TestCase
## Milestone 4: farm/crops, herbivores (goats), fish, settlement food & water, cause chains.


func _clear_all_forest(sim: Simulation) -> void:
	for y in sim.world.height:
		for x in sim.world.width:
			if sim.world.land_type[sim.world.index(x, y)] == LandType.FOREST: sim.apply_action(Simulation.Action.CLEAR_TREES, x, y)


func _build_farms(sim: Simulation, n: int) -> int:
	var c := sim.world.coords(sim.world.settlement_index)
	var built := 0
	for r in range(1, Simulation.FARM_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if built < n and sim.apply_action(Simulation.Action.BUILD_FARM, c.x + dx, c.y + dy):
					built += 1
	return built


func _first_of_type(sim: Simulation, t: int) -> int:
	for id in range(maxi(0, sim.events.next_id - EventLog.CAPACITY), sim.events.next_id):
		if sim.events.type_of(id) == t:
			return id
	return -1


func test_settlement_placed_on_coastal_land() -> void:
	for s in [1, 12345, 777, 4242, 99]:
		var ws := IslandGenerator.generate(s, 32, 32)
		var si := ws.settlement_index
		assert_true(si >= 0, "seed %d has a village" % s)
		assert_false(LandType.is_water(ws.land_type[si]))
		assert_eq(ws.structure[si], WorldState.Structure.SETTLEMENT)
		assert_eq(ws.count_structures(WorldState.Structure.SETTLEMENT), 1)
		assert_eq(ws.villagers, IslandGenerator.START_VILLAGERS)
		assert_eq(IslandGenerator.generate(s, 32, 32).settlement_index, si, "deterministic")


func test_farm_build_rules() -> void:
	var sim := Simulation.create(12345, 32)
	var c := sim.world.coords(sim.world.settlement_index)
	assert_eq(sim.can_apply(Simulation.Action.BUILD_FARM, c.x, c.y), "Something is built here")
	# far away tile
	var far := Vector2i(-1, -1)
	for i in sim.world.tile_count():
		var p := sim.world.coords(i)
		var t := sim.world.land_type[i]
		if (t == LandType.LOWLAND or t == LandType.GRASSLAND) and sim.distance_to_settlement(p.x, p.y) > Simulation.FARM_RADIUS:
			far = p
			break
	assert_true(far.x >= 0)
	assert_eq(sim.can_apply(Simulation.Action.BUILD_FARM, far.x, far.y), "Too far from the village")
	assert_eq(_build_farms(sim, 2), 2)
	assert_eq(sim.world.count_structures(WorldState.Structure.FARM), 2)
	assert_eq(sim.events.type_of(sim.events.next_id - 1), EventLog.Type.FARM_BUILT)
	# forests must be cleared first
	for i in sim.world.tile_count():
		var p2 := sim.world.coords(i)
		if sim.world.land_type[i] == LandType.FOREST and sim.distance_to_settlement(p2.x, p2.y) <= Simulation.FARM_RADIUS:
			assert_eq(sim.can_apply(Simulation.Action.BUILD_FARM, p2.x, p2.y), "Clear the trees first")
			break


func test_farms_harvest_and_feed_growth() -> void:
	var base := Simulation.create(12345, 32)
	var farmed := Simulation.create(12345, 32)
	_build_farms(farmed, 2)
	base.run(240)
	farmed.run(240)
	assert_true(farmed.world.harvests >= 4, "harvests %d" % farmed.world.harvests)
	assert_true(farmed.world.villagers > base.world.villagers,
		"farms %d vs base %d villagers" % [farmed.world.villagers, base.world.villagers])
	assert_true(_first_of_type(farmed, EventLog.Type.POPULATION_GROWTH) >= 0)


func test_crop_failure_records_drought_cause() -> void:
	var sim := Simulation.create(12345, 32)
	_build_farms(sim, 1)
	var fi := sim.world.structure.find(WorldState.Structure.FARM)
	sim.world.crop_growth[fi] = 0.5
	var drought := sim.events.record(sim.world.tick, EventLog.Type.DROUGHT, -1, -1, 12)
	sim.world.drought_event = drought
	for k in Simulation.CROP_FAIL_DAYS:
		sim.world.soil_moisture[fi] = 0.0
		sim._crops()
	var fail := _first_of_type(sim, EventLog.Type.CROP_FAILURE)
	assert_true(fail >= 0, "crop failed")
	assert_eq(sim.world.crop_growth[fi], 0.0)
	assert_eq(sim.events.causes_of(fail), PackedInt32Array([drought]))
	# Without a drought the failure has no recorded cause (we never invent one).
	var sim2 := Simulation.create(12345, 32)
	_build_farms(sim2, 1)
	var fi2 := sim2.world.structure.find(WorldState.Structure.FARM)
	sim2.world.crop_growth[fi2] = 0.5
	for k in Simulation.CROP_FAIL_DAYS:
		sim2.world.soil_moisture[fi2] = 0.0
		sim2._crops()
	var fail2 := _first_of_type(sim2, EventLog.Type.CROP_FAILURE)
	assert_true(sim2.events.causes_of(fail2).is_empty())


func test_goats_graze_and_are_bounded() -> void:
	var sim := Simulation.create(12345, 32)
	sim.run(200)
	assert_true(sim.world.goats > 0.0 and sim.world.goats < 200.0, "goats %f" % sim.world.goats)
	assert_true(sim.world.fish > 0.0 and sim.world.fish <= Simulation.FISH_CAP, "fish %f" % sim.world.fish)


func test_full_chain_clearing_to_hunger() -> void:
	# The headline chain: cut trees -> erosion -> muddy coast -> fish decline -> food shortage.
	var sim := Simulation.create(12345, 32)
	sim.world.free_build = true
	_clear_all_forest(sim)
	sim.run(120)
	var fish_ev := _first_of_type(sim, EventLog.Type.FISH_DECLINE)
	assert_true(fish_ev >= 0, "fish declined")
	var fc := sim.events.causes_of(fish_ev)
	assert_true(fc.size() > 0 and sim.events.type_of(fc[0]) == EventLog.Type.MUDDY_WATER, "fish decline caused by muddy water")
	var food_ev := _first_of_type(sim, EventLog.Type.FOOD_SHORTAGE)
	assert_true(food_ev >= 0, "food shortage")
	assert_true(fish_ev in sim.events.causes_of(food_ev), "shortage cites fish decline")
	var text := "\n".join(sim.events.explain(food_ev))
	for needle in ["Food shortage", "Fish declining", "Coastal water turned muddy", "Soil erosion", "Trees cleared"]:
		assert_true(text.contains(needle), "explanation mentions %s:\n%s" % [needle, text])
	# and an untouched island has none of it
	var base := Simulation.create(12345, 32)
	base.run(120)
	assert_eq(_first_of_type(base, EventLog.Type.FISH_DECLINE), -1)
	assert_eq(_first_of_type(base, EventLog.Type.FOOD_SHORTAGE), -1)


func test_water_shortage_cites_active_drought_only() -> void:
	var sim := Simulation.create(12345, 32)
	var drought := sim.events.record(0, EventLog.Type.DROUGHT, -1, -1, 12)
	sim.world.drought_event = drought
	for k in 30:
		sim.world.flow.fill(0.0)
		sim.world.surface_water.fill(0.0)
		sim.world.soil_moisture.fill(0.0)
		sim._settlement()
	assert_true(sim.world.water_event >= 0)
	assert_eq(sim.events.causes_of(sim.world.water_event), PackedInt32Array([drought]))


func test_life_deterministic() -> void:
	var a := Simulation.create(4242, 32)
	var b := Simulation.create(4242, 32)
	_build_farms(a, 3)
	_build_farms(b, 3)
	a.run(200)
	b.run(200)
	assert_eq(a.state_checksum(), b.state_checksum())
	assert_eq(a.world.villagers, b.world.villagers)
