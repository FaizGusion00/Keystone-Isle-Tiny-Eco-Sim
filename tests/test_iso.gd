extends TestCase


func test_tile_centers() -> void:
	assert_eq(Iso.tile_to_local(0, 0), Vector2(0, 0))
	assert_eq(Iso.tile_to_local(1, 0), Vector2(32, 16))
	assert_eq(Iso.tile_to_local(0, 1), Vector2(-32, 16))
	assert_eq(Iso.tile_to_local(3, 2), Vector2(32, 80))


func test_known_pick_points() -> void:
	assert_eq(Iso.local_to_tile(Vector2(0, 0)), Vector2i(0, 0))
	assert_eq(Iso.local_to_tile(Vector2(31, 0)), Vector2i(0, 0))   # just inside right corner
	assert_eq(Iso.local_to_tile(Vector2(33, 0)), Vector2i(1, -1))  # just past it
	assert_eq(Iso.local_to_tile(Vector2(0, 15)), Vector2i(0, 0))   # inside bottom corner
	assert_eq(Iso.local_to_tile(Vector2(0, 17)), Vector2i(1, 1))   # tile below
	assert_eq(Iso.local_to_tile(Vector2(17, 8.5)), Vector2i(1, 0)) # across the down-right edge
	assert_eq(Iso.local_to_tile(Vector2(15, 7.0)), Vector2i(0, 0))
	assert_eq(Iso.local_to_tile(Vector2(-17, 8.5)), Vector2i(0, 1))
	assert_eq(Iso.local_to_tile(Vector2(32, 80)), Vector2i(3, 2))


func test_pick_round_trip_inside_diamond() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for y in 32:
		for x in 32:
			var c := Iso.tile_to_local(x, y)
			assert_eq(Iso.local_to_tile(c), Vector2i(x, y))
			for k in 4:
				# random point strictly inside the diamond
				var u := rng.randf_range(-0.98, 0.98)
				var v := rng.randf_range(-(0.98 - absf(u)), 0.98 - absf(u))
				var p := c + Vector2(u * Iso.HALF_W, v * Iso.HALF_H)
				assert_eq(Iso.local_to_tile(p), Vector2i(x, y), "point %s" % p)


func test_map_bounds_contains_all_tiles() -> void:
	var r := Iso.map_bounds(32, 32)
	for p in [Iso.tile_to_local(0, 0), Iso.tile_to_local(31, 0), Iso.tile_to_local(0, 31), Iso.tile_to_local(31, 31)]:
		assert_true(r.has_point(p))
