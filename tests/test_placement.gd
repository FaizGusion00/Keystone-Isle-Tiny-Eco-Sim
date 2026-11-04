extends TestCase
## Placement feedback: the valid-tile overlay agrees exactly with the rules, is cheap to
## compute, big builds are previewed before building on touch, and the tool drops back to Inspect.

const A := Simulation.Action
const ACTIONS := [A.CLEAR_TREES, A.PLANT_TREES, A.BUILD_FARM, A.BUILD_HOUSE, A.BUILD_DAM, A.RESTORE_LAND, A.DEMOLISH]


func _main() -> Node:
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = "user://test_ui/placement.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.hud.clear_popups()
	if main.hud.coach_active():
		main.hud.end_coach()
	return main


func _free(main: Node) -> void:
	main.get_parent().remove_child(main)
	main.free()


func test_mask_matches_the_rules_exactly() -> void:
	for spec in [[12345, 32], [2024, 32], [77, 64]]:
		var sim := Simulation.create(spec[0], spec[1])
		sim.run(30)
		var ws := sim.world
		for a in ACTIONS:
			var m := ValidTiles.compute(sim, a)
			var bad := 0
			for y in ws.height:
				for x in ws.width:
					var allowed := sim.tile_rule(a, x, y) == ""
					if allowed != (m[ws.index(x, y)] != ValidTiles.NO):
						bad += 1
			assert_eq(bad, 0, "seed %d action %d: overlay disagrees with tile_rule on %d tiles" % [spec[0], a, bad])
		ws.labor = 0.0
		var m2 := ValidTiles.compute(sim, A.BUILD_FARM)
		assert_true(ValidTiles.count(m2, ValidTiles.OK) == 0 and ValidTiles.count(m2, ValidTiles.SHORT) > 0,
			"no labor: allowed tiles show as 'can't afford'")


func test_mask_is_cheap() -> void:
	for spec in [[12345, 32, 3.0], [77, 64, 12.0]]:
		var sim := Simulation.create(spec[0], spec[1])
		var t0 := Time.get_ticks_usec()
		for a in ACTIONS:
			ValidTiles.compute(sim, a)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / ACTIONS.size()
		print("    [perf] valid-tile mask %dx%d: %.2f ms" % [spec[1], spec[1], ms])
		assert_true(ms < spec[2], "mask %.2f ms over budget" % ms)


func _farm_tile(main: Node) -> Vector2i:
	var sim: Simulation = main.sim
	for y in sim.world.height:
		for x in sim.world.width:
			if sim.can_apply(A.BUILD_FARM, x, y) == "":
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _screen_of(main: Node, t: Vector2i) -> Vector2:
	var wv: WorldView = main.world_view
	return main.get_viewport().get_canvas_transform() * wv.to_global(wv.top_center(t.x, t.y) + Vector2(0, 2))


func test_touch_previews_then_builds_and_tool_reverts() -> void:
	var main := _main()
	main.start_tutorial()
	main.hud.clear_popups()
	if main.hud.coach_active():
		main.hud.end_coach()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	main.hud.select_tool(Hud.Tool.BUILD_FARM)
	assert_true(main.world_view.placement.visible, "overlay shows with a build tool")
	assert_true(ValidTiles.count(main.world_view.placement.mask, ValidTiles.OK) > 0, "valid farm tiles lit")
	var t := _farm_tile(main)
	assert_true(t.x >= 0)
	assert_eq(main.pick_tile(_screen_of(main, t)), t, "screen point maps back to the tile")
	main.camera.last_was_touch = true
	var farms0: int = main.sim.world.count_structures(WorldState.Structure.FARM)
	main._on_tile_tapped(_screen_of(main, t))
	assert_eq(main.sim.world.count_structures(WorldState.Structure.FARM), farms0, "first tap only previews")
	assert_true(main.hud.place_tag_text() != "", "the tag explains the cost")
	assert_eq(main.world_view.placement.hover, t, "ghost on the tile")
	main._on_tile_tapped(_screen_of(main, t))
	assert_eq(main.sim.world.count_structures(WorldState.Structure.FARM), farms0 + 1, "second tap builds")
	assert_eq(main.hud.tool, Hud.Tool.INSPECT, "back to Inspect after a farm")
	assert_false(main.world_view.placement.visible, "overlay gone with Inspect")
	_free(main)


func test_mouse_builds_directly_and_hover_explains() -> void:
	var main := _main()
	main.start_tutorial()
	main.hud.clear_popups()
	if main.hud.coach_active():
		main.hud.end_coach()
	await main.get_tree().process_frame
	main.hud.select_tool(Hud.Tool.BUILD_FARM)
	var t := _farm_tile(main)
	main.camera.last_was_touch = false
	main._on_hover(_screen_of(main, t))
	assert_true(main.hud.place_tag_text().contains("labor"), main.hud.place_tag_text())
	var water := Vector2i(0, 0)
	main._on_hover(_screen_of(main, water))
	assert_true(main.world_view.placement.hover == water and not main.world_view.placement.hover_ok)
	assert_eq(main.hud.place_tag_text(), "That's open water")
	assert_true(main.try_action(A.BUILD_FARM, t))
	assert_eq(main.hud.tool, Hud.Tool.INSPECT)
	main.hud.select_tool(Hud.Tool.CLEAR_TREES)
	var f := Vector2i(-1, -1)
	for y in main.sim.world.height:
		for x in main.sim.world.width:
			if f.x < 0 and main.sim.world.land_type[main.sim.world.index(x, y)] == LandType.FOREST:
				f = Vector2i(x, y)
	main.try_action(A.CLEAR_TREES, f)
	assert_eq(main.hud.tool, Hud.Tool.CLEAR_TREES, "clearing is a painting tool: stays picked")
	_free(main)
