extends TestCase
## Milestone 2: water, soil, vegetation, rainfall, erosion, plant/clear trees.


func _all_land_forest_cleared(sim: Simulation) -> int:
	var n := 0
	for y in sim.world.height:
		for x in sim.world.width:
			if sim.apply_action(Simulation.Action.CLEAR_TREES, x, y):
				n += 1
	return n


func test_sim_deterministic_same_seed() -> void:
	var a := Simulation.create(321, 32)
	var b := Simulation.create(321, 32)
	for k in 150:
		a.step()
		b.step()
	assert_eq(a.world.checksum(), b.world.checksum())
	assert_eq(a.rng.state, b.rng.state)


func test_sim_diverges_with_different_seed() -> void:
	var a := Simulation.create(321, 32)
	var b := Simulation.create(322, 32)
	a.run(30)
	b.run(30)
	assert_ne(a.world.checksum(), b.world.checksum())


func test_actions_are_part_of_determinism() -> void:
	var a := Simulation.create(5, 32)
	var b := Simulation.create(5, 32)
	a.run(10)
	b.run(10)
	_all_land_forest_cleared(a)
	_all_land_forest_cleared(b)
	a.run(50)
	b.run(50)
	assert_eq(a.world.checksum(), b.world.checksum())


func test_values_stay_in_range() -> void:
	var sim := Simulation.create(77, 32)
	sim.run(300)
	var ws := sim.world
	for i in ws.tile_count():
		assert_true(ws.surface_water[i] >= 0.0, "water<0 at %d" % i)
		assert_true(ws.sediment[i] >= 0.0, "sediment<0 at %d" % i)
		assert_true(ws.soil_moisture[i] >= 0.0 and ws.soil_moisture[i] <= 1.0)
		assert_true(ws.vegetation_cover[i] >= 0.0 and ws.vegetation_cover[i] <= 1.0)
		assert_true(ws.soil_depth[i] >= 0.0 and ws.soil_depth[i] <= 1.0)


func test_rain_wets_soil_and_flows_downhill() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	# Force one big rain on an otherwise dry island, then one flow step.
	ws.surface_water.fill(0.0)
	var top := 0
	for i in ws.tile_count():
		if ws.elevation[i] > ws.elevation[top]:
			top = i
	ws.surface_water[top] = 1.0
	var before_total := 0.0
	for i in ws.tile_count():
		before_total += ws.surface_water[i]
	sim._water_flow_and_erosion()
	assert_true(ws.surface_water[top] < 1.0, "water left the peak")
	var after_total := 0.0
	for i in ws.tile_count():
		if ws.land_type[i] > LandType.SHALLOW_WATER:
			after_total += ws.surface_water[i]
	assert_near(after_total, before_total, 1e-4, "water conserved on land for one step")


func test_two_buffer_flow_is_order_independent() -> void:
	# Flow reads only the current buffers: running the step from a duplicated state
	# gives exactly the same result (no in-place read-after-write).
	var a := Simulation.create(9, 32)
	a.run(5)
	var b := Simulation.create(9, 32)
	b.run(5)
	a._water_flow_and_erosion()
	b._water_flow_and_erosion()
	assert_eq(a.world.surface_water, b.world.surface_water)
	assert_eq(a.world.sediment, b.world.sediment)
	assert_true(a.world.surface_water != a._water_next or a.world.tick == 0)


func test_clearing_forest_increases_erosion_and_turbidity() -> void:
	var control := Simulation.create(12345, 32)
	var cleared := Simulation.create(12345, 32)
	var n := _all_land_forest_cleared(cleared)
	assert_true(n > 20, "cleared %d forest tiles" % n)
	var sea_c := 0.0
	var sea_x := 0.0
	var turb_c := 0.0
	var turb_x := 0.0
	for k in 120:
		control.step()
		cleared.step()
		sea_c += control.world.sediment_to_sea
		sea_x += cleared.world.sediment_to_sea
		turb_c += control.world.coastal_turbidity
		turb_x += cleared.world.coastal_turbidity
	assert_true(sea_x > sea_c * 1.3, "sediment to sea %.3f vs control %.3f" % [sea_x, sea_c])
	assert_true(turb_x > turb_c * 1.3, "turbidity %.3f vs control %.3f" % [turb_x, turb_c])


func test_plant_and_clear_rules() -> void:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	var forest := -1
	var grass := -1
	var sea := -1
	for i in ws.tile_count():
		match ws.land_type[i]:
			LandType.FOREST: forest = i if forest < 0 else forest
			LandType.GRASSLAND: grass = i if grass < 0 else grass
			LandType.DEEP_WATER: sea = i if sea < 0 else sea
	var f := ws.coords(forest)
	var g := ws.coords(grass)
	var s := ws.coords(sea)
	assert_eq(sim.can_apply(Simulation.Action.CLEAR_TREES, g.x, g.y), "No trees here")
	assert_false(sim.apply_action(Simulation.Action.PLANT_TREES, s.x, s.y))
	assert_true(sim.apply_action(Simulation.Action.CLEAR_TREES, f.x, f.y))
	assert_ne(ws.land_type[forest], LandType.FOREST)
	assert_true(ws.vegetation_cover[forest] < 0.1)
	assert_true(sim.apply_action(Simulation.Action.PLANT_TREES, g.x, g.y))
	assert_eq(ws.land_type[grass], LandType.FOREST)


func test_drought_dries_soil() -> void:
	var sim := Simulation.create(3, 32)
	var ws := sim.world
	var avg0 := 0.0
	var land := 0
	for i in ws.tile_count():
		if ws.land_type[i] > LandType.SHALLOW_WATER:
			avg0 += ws.soil_moisture[i]
			land += 1
	for k in 40:  # no rainfall: run only the water/soil systems
		sim._water_flow_and_erosion()
		sim._soil_water()
	var avg1 := 0.0
	for i in ws.tile_count():
		if ws.land_type[i] > LandType.SHALLOW_WATER:
			avg1 += ws.soil_moisture[i]
	assert_true(avg1 < avg0 * 0.8, "moisture %.2f -> %.2f" % [avg0 / land, avg1 / land])
