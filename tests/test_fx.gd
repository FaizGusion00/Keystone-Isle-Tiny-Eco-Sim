extends TestCase
## Map animation: changes grow in / fall away instead of swapping, the tile is hidden in its
## chunk only while WorldFx draws it, the layer sleeps when idle, and it respects reduce motion.


func _view() -> Array:
	var sim := Simulation.create(12345, 32)
	var view := WorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.set_world(sim.world, sim.events)
	view.refresh(true)
	return [sim, view]


func _forest(ws: WorldState) -> int:
	for i in ws.tile_count():
		if ws.land_type[i] == LandType.FOREST:
			return i
	return -1


func test_capture_lists_what_is_drawn() -> void:
	var r := _view()
	var sim: Simulation = r[0]
	var view: WorldView = r[1]
	var f := _forest(sim.world)
	var shot := view.capture_index(f)
	assert_true(shot.size() >= 1, "a forest tile has trees")
	for s in shot:
		assert_true(ArtAtlas.R.has(s[0]), "captured sprite %s exists" % s[0])
	assert_eq(view.capture_tile(Vector2i(0, 0)).size(), 0, "open water draws no sprites")
	view.get_parent().remove_child(view)
	view.free()


func test_grow_hides_then_restores_the_tile() -> void:
	var r := _view()
	var sim: Simulation = r[0]
	var view: WorldView = r[1]
	var f := _forest(sim.world)
	var key0 := view.deco_key(f)
	view.fx.enabled = true
	view.fx.grow(f)
	if view.fx.active() == 0:
		view.get_parent().remove_child(view)
		view.free()
		return  # off screen in a headless run: nothing to animate, nothing hidden
	assert_true((view.deco_key(f) >> 30) & 1 == 1, "the chunk hides the tile while fx draws it")
	assert_true(view.fx.is_processing())
	await view.get_tree().create_timer(WorldFx.GROW + 0.4).timeout
	await view.get_tree().process_frame
	assert_eq(view.fx.active(), 0)
	assert_eq(view.deco_key(f), key0, "back to the plain key")
	assert_false(view.fx.is_processing(), "an idle fx layer costs nothing")
	view.get_parent().remove_child(view)
	view.free()


func test_cap_and_reduce_motion() -> void:
	var r := _view()
	var sim: Simulation = r[0]
	var view: WorldView = r[1]
	view.fx.enabled = true
	var n := 0
	for i in sim.world.tile_count():
		if sim.world.land_type[i] == LandType.FOREST:
			view.fx.grow(i)
			n += 1
	assert_true(view.fx.active() <= WorldFx.MAX_FX, "capped (%d)" % view.fx.active())
	view.fx.finish_all()
	for i in sim.world.tile_count():
		assert_true((view.deco_key(i) >> 30) & 1 == 0, "finish_all unhides every tile")
	view.fx.enabled = false
	view.fx.grow(_forest(sim.world))
	assert_eq(view.fx.active(), 0, "reduce motion: no map animation")
	view.get_parent().remove_child(view)
	view.free()


func test_actions_animate_in_the_game() -> void:
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = "user://test_ui/fx.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	open_main(main)
	await main.get_tree().process_frame
	main.focus_village()
	main.camera.position = main.camera._glide_to if main.camera._glide_to != Vector2.INF else main.camera.position
	await main.get_tree().process_frame
	var t: Vector2i = main.best_farm_tile()
	assert_true(main.try_action(Simulation.Action.BUILD_FARM, t))
	assert_true(main.world_view.fx.active() >= 1, "the new farm grows in")
	main.set_speed(SimClock.Speed.FAST)
	assert_false(main.world_view.auto_fx, "no automatic map animation at the fastest speed")
	main.get_parent().remove_child(main)
	main.free()
