extends TestCase


func test_same_seed_identical() -> void:
	var a := IslandGenerator.generate(42, 32, 32)
	var b := IslandGenerator.generate(42, 32, 32)
	assert_eq(a.elevation, b.elevation)
	assert_eq(a.land_type, b.land_type)
	assert_eq(a.soil_moisture, b.soil_moisture)
	assert_eq(a.vegetation_cover, b.vegetation_cover)
	assert_eq(a.checksum(), b.checksum())


func test_different_seeds_differ() -> void:
	var a := IslandGenerator.generate(1, 32, 32)
	var b := IslandGenerator.generate(2, 32, 32)
	assert_ne(a.checksum(), b.checksum())
	assert_ne(a.land_type, b.land_type)


func test_dimensions_and_ranges() -> void:
	for size in [32, 64]:
		var ws := IslandGenerator.generate(7, size, size)
		assert_eq(ws.tile_count(), size * size)
		assert_eq(ws.elevation.size(), size * size)
		assert_eq(ws.land_type.size(), size * size)
		for i in ws.tile_count():
			assert_true(ws.land_type[i] < LandType.COUNT)
			assert_true(ws.elevation[i] >= 0.0 and ws.elevation[i] <= 1.0)
			assert_true(ws.soil_moisture[i] >= 0.0 and ws.soil_moisture[i] <= 1.0)
			assert_true(ws.vegetation_cover[i] >= 0.0 and ws.vegetation_cover[i] <= 1.0)


func test_is_an_island() -> void:
	for s in [1, 99, 12345]:
		var ws := IslandGenerator.generate(s, 32, 32)
		var land := 0
		for i in ws.tile_count():
			if not LandType.is_water(ws.land_type[i]):
				land += 1
		assert_true(land > 150, "seed %d has %d land tiles" % [s, land])
		# Border ring is always water (radial falloff).
		for k in 32:
			assert_true(LandType.is_water(ws.land_type[ws.index(k, 0)]))
			assert_true(LandType.is_water(ws.land_type[ws.index(0, k)]))
			assert_true(LandType.is_water(ws.land_type[ws.index(k, 31)]))
			assert_true(LandType.is_water(ws.land_type[ws.index(31, k)]))


func test_index_math() -> void:
	var ws := WorldState.new(32, 20, 0)
	assert_eq(ws.index(0, 0), 0)
	assert_eq(ws.index(31, 0), 31)
	assert_eq(ws.index(0, 1), 32)
	assert_eq(ws.index(5, 7), 7 * 32 + 5)
	for i in ws.tile_count():
		var c := ws.coords(i)
		assert_eq(ws.index(c.x, c.y), i)
	assert_true(ws.in_bounds(31, 19))
	assert_false(ws.in_bounds(32, 0))
	assert_false(ws.in_bounds(0, 20))
	assert_false(ws.in_bounds(-1, 3))
