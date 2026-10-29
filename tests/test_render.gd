extends TestCase
## Diorama renderer: terraced heights, height-aware picking, stable dirty keys, art atlas,
## and that the purely visual ambience never touches simulation state.


func _view(sim: Simulation) -> WorldView:
	var view := WorldView.new()
	view._ready()
	view.set_world(sim.world, sim.events)
	return view


func test_heights_terraced_and_water_flat() -> void:
	var sim := Simulation.create(2024, 32)
	var view := _view(sim)
	var ws := sim.world
	var max_h := 0.0
	for i in ws.tile_count():
		var h: float = view.heights[i]
		if LandType.is_water(ws.land_type[i]):
			assert_eq(h, 0.0, "water is flat")
		else:
			assert_true(h >= WorldView.BASE_H, "land sits above water")
			assert_near(fmod(h - WorldView.BASE_H, WorldView.STEP), 0.0, 1e-3, "heights snap to terraces")
		max_h = maxf(max_h, h)
	assert_true(max_h <= WorldView.MAX_H, "MAX_H bounds every terrace")
	assert_true(max_h > WorldView.BASE_H, "the island has some relief")
	view.free()


func test_pick_hits_raised_top_and_flat_ground() -> void:
	var sim := Simulation.create(2024, 32)
	var view := _view(sim)
	var ws := sim.world
	var checked := 0
	for i in ws.tile_count():
		var c := ws.coords(i)
		# the centre of every visible top face must pick its own tile unless a taller tile in front covers it
		var p := view.top_center(c.x, c.y)
		var got := view.pick(p)
		if got != c:
			# must be a tile in front whose column covers the point
			assert_true(got.x + got.y > c.x + c.y, "picked %s for %s: only a tile in front may occlude" % [got, c])
		else:
			checked += 1
	assert_true(checked > ws.tile_count() * 0.8, "most tile tops pick themselves (%d)" % checked)
	assert_eq(view.pick(Vector2(-99999, -99999)), Iso.local_to_tile(Vector2(-99999, -99999)), "far outside => flat tile coords")
	view.free()


func test_refresh_is_stable_and_tracks_changes() -> void:
	var sim := Simulation.create(2024, 32)
	var view := _view(sim)
	assert_eq(view.refresh(), 0, "no change => no redraw")
	var s := sim.world.coords(sim.world.settlement_index)
	var built := false
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1)]:
		if not built and sim.apply_action(Simulation.Action.BUILD_FARM, s.x + d.x, s.y + d.y):
			built = true
	assert_true(built, "a farm can be built next to the village")
	assert_true(view.refresh() >= 1, "a new farm redraws its chunk")
	assert_eq(view.refresh(), 0, "and then settles")
	view.free()


func test_atlas_sprites_present() -> void:
	for n in ["pine_a", "oak_a", "cottage", "hall", "well", "dam_x", "dam_y", "goat", "fish", "boat",
			"crop_sprout", "crop_green", "crop_ripe", "crop_dry", "fire_a", "smoke"]:
		assert_true(ArtAtlas.R.has(n), "atlas has " + n)
		var r: Array = ArtAtlas.R[n]
		assert_true(r[0] + r[2] <= ArtAtlas.TEXTURE.get_width() and r[1] + r[3] <= ArtAtlas.TEXTURE.get_height(), n + " inside atlas")


func test_ambience_is_visual_only() -> void:
	var sim := Simulation.create(2024, 32)
	sim.run(150) # includes heavy rain days
	var view := _view(sim)
	var amb := Ambience.new()
	amb._ready()
	var before := sim.world.checksum()
	amb.set_world(view)
	amb.update_from_world(true)
	amb.pop(Vector2i(3, 3))
	assert_eq(sim.world.checksum(), before, "ambience never changes the simulation")
	assert_true(amb.rain >= 0.0 and amb.rain <= 1.0, "rain intensity normalised")
	amb.free()
	view.free()
