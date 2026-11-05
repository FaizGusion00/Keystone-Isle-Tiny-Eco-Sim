extends TestCase
## The village is easy to find and alive: villagers walk routes over open ground (not through
## forest or water), and a pin marks the village when the island is zoomed out.


func _main() -> Node:
	DirAccess.make_dir_recursive_absolute("user://test_ui")
	SaveSystem.delete_all("user://test_ui/village.json")
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = "user://test_ui/village.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	open_main(main)
	return main


func _free(main: Node) -> void:
	main.get_parent().remove_child(main)
	main.free()


func test_walk_routes_stay_on_open_ground() -> void:
	var main := _main()
	var ws: WorldState = main.sim.world
	var wv: WorldView = main.world_view
	var amb: Ambience = main.ambience
	var v := ws.coords(ws.settlement_index)
	var a: Vector2 = wv.position + wv.top_center(v.x, v.y)
	var checked := 0
	for i in ws.tile_count():
		var p := ws.coords(i)
		var t := ws.land_type[i]
		if checked >= 12 or LandType.is_water(t) or t == LandType.FOREST or t == LandType.HILLS:
			continue
		if maxi(absi(p.x - v.x), absi(p.y - v.y)) > 6:
			continue
		var b: Vector2 = wv.position + wv.top_center(p.x, p.y)
		var route := amb._route(a, b)
		assert_true(route.size() >= 1)
		for k in route.size() - 1:
			var q: Vector2i = wv.pick(wv.to_local(route[k]))
			if ws.in_bounds(q.x, q.y):
				var lt := ws.land_type[ws.index(q.x, q.y)]
				assert_false(LandType.is_water(lt) or lt == LandType.FOREST, "route step on %s" % LandType.name_of(lt))
		checked += 1
	assert_true(checked > 0)
	_free(main)


func test_village_pin_when_zoomed_out_and_tap_flies_there() -> void:
	var main := _main()
	await main.get_tree().create_timer(0.8).timeout  # let the island framing tween finish
	main.camera._glide_to = Vector2.INF  # stop any glide / eased zoom still running
	main.camera._zoom_target = 0.0
	main.camera.zoom = Vector2(0.6, 0.6)
	var v: Vector2i = main.sim.world.coords(main.sim.world.settlement_index)
	main.camera.position = main.world_view.position + main.world_view.top_center(v.x, v.y)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	main._process(0.016)
	assert_true(main.hud._village_pin.visible, "pin shows over the village when zoomed out")
	assert_true(main.hud._village_pin.text.contains("10"), main.hud._village_pin.text)
	main.hud.village_pin_pressed.emit()
	assert_eq(main.selected, v, "tapping the pin selects the village")
	main.camera.zoom = Vector2(1.6, 1.6)
	main._process(0.016)
	assert_false(main.hud.village_pin_visible(), "no pin when the village is big enough to see")
	_free(main)
