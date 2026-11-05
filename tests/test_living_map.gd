extends TestCase
## The island tells its story on the map: muddy plumes linger and spread in the sea, fish
## schools thin out and avoid mud, recorded cause chains light up as threads, soil runoff can be
## previewed before clearing, health colours the island, and first-time moments explain once.


func _main() -> Node:
	DirAccess.make_dir_recursive_absolute("user://test_ui")
	SaveSystem.delete_all("user://test_ui/living.json")
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = "user://test_ui/living.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	open_main(main)
	return main


func _free(main: Node) -> void:
	main.get_parent().remove_child(main)
	main.free()


func _shallow(ws: WorldState) -> int:
	for i in ws.tile_count():
		if ws.land_type[i] == LandType.SHALLOW_WATER:
			return i
	return -1


func test_mud_plume_lingers_and_spreads() -> void:
	var main := _main()
	var ws: WorldState = main.sim.world
	var wv: WorldView = main.world_view
	var i := _shallow(ws)
	ws.sediment[i] = 0.2
	wv.refresh()
	assert_true(wv.plume_at(i) > 0.9, "fresh mud shows at once")
	ws.sediment[i] = 0.0
	for k in 20:
		wv.refresh(true)
	assert_true(wv.plume_at(i) > 0.2, "the plume lingers after the sediment settles (%.2f)" % wv.plume_at(i))
	var spread := false
	for j in [i - 1, i + 1, i - ws.width, i + ws.width]:
		if j >= 0 and j < ws.tile_count() and LandType.is_water(ws.land_type[j]) and wv.plume_at(j) > 0.05:
			spread = true
	assert_true(spread, "and drifts into neighbouring water")
	for k in 400:
		wv.refresh(true)
	assert_true(wv.plume_at(i) < 0.02, "then clears")
	_free(main)


func test_health_colours_the_island() -> void:
	assert_near(WorldView.vitality_for(95.0), 1.0, 1e-3)
	assert_near(WorldView.vitality_for(30.0), 0.0, 1e-3)
	assert_true(WorldView.vitality_for(65.0) > 0.3 and WorldView.vitality_for(65.0) < 0.7)


func test_cause_chains_become_threads() -> void:
	var main := _main()
	var sim: Simulation = main.sim
	var ws := sim.world
	ws.free_build = true
	for y in ws.height:
		for x in ws.width:
			if ws.land_type[ws.index(x, y)] == LandType.FOREST:
				sim.apply_action(Simulation.Action.CLEAR_TREES, x, y)
	var pick := -1
	for d in 200:
		sim.step()
		if ws.muddy_event >= 0:
			pick = ws.muddy_event
			break
	assert_true(pick >= 0, "clearing everything muddies the coast")
	main.world_view.refresh(true)
	var links: int = main.world_view.threads.show_chain(sim.events, pick)
	assert_true(links >= 1, "the muddy coast is threaded back to the land that washed away (%d links)" % links)
	assert_true(main.world_view.threads.bounds().size.x > 0)
	main.world_view.threads.clear()
	assert_false(main.world_view.threads.showing())
	_free(main)


func test_runoff_preview_reaches_the_water() -> void:
	var main := _main()
	var ws: WorldState = main.sim.world
	var wv: WorldView = main.world_view
	var f := Vector2i(-1, -1)
	for i in ws.tile_count():
		if ws.land_type[i] == LandType.FOREST:
			f = ws.coords(i)
			break
	main.hud.select_tool(Hud.Tool.CLEAR_TREES)
	main._preview_runoff(Simulation.Action.CLEAR_TREES, f)
	assert_true(wv.threads.runoff_points() >= 2, "a downhill path is drawn")
	main.hud.select_tool(Hud.Tool.INSPECT)
	assert_eq(wv.threads.runoff_points(), 0, "gone with the tool")
	_free(main)


func test_fish_schools_follow_the_stock() -> void:
	var main := _main()
	var ws: WorldState = main.sim.world
	var fish: FishSchools = main.world_view.fish
	await main.get_tree().process_frame
	fish._process(0.1)
	var full := fish.count()
	assert_true(full >= 4, "a healthy sea shows several schools (%d)" % full)
	ws.fish = 10.0
	for k in 60:
		fish._process(0.1)
	assert_true(fish.count() < full, "fewer fish, fewer schools (%d)" % fish.count())
	_free(main)


func test_first_time_moment_shows_once_and_holds_time() -> void:
	var main := _main()
	main.settings.values["show_tutorial"] = true
	main.progress.moments.clear()
	var ev: EventLog = main.sim.events
	main._seen_event_id = ev.next_id
	ev.record(main.sim.world.tick, EventLog.Type.FLOOD, 5, 5, 0.3)
	main._toast_new_events()
	assert_true(main.hud.moment_text().begins_with("Flood!"), main.hud.moment_text())
	await main.get_tree().create_timer(Motion.SLOW + 0.1).timeout
	main._process(0.016)
	assert_false(main.clock.can_tick(), "time waits while the moment is read")
	main.hud.close_moment()
	await main.get_tree().create_timer(Motion.FAST + 0.1).timeout
	main._process(0.016)
	assert_true(main.clock.can_tick())
	main._seen_event_id = ev.next_id
	ev.record(main.sim.world.tick, EventLog.Type.FLOOD, 6, 6, 0.3)
	main._toast_new_events()
	assert_eq(main.hud.moment_text(), "", "each moment only once")
	assert_true(main.progress.moments.has("flood"))
	_free(main)
