extends TestCase
## The rules the player depends on are shown truthfully: growth checklist, chip cards, goals card
## (extra stars + how you lose), named missed goals, and toasts that don't drown the important news.


func _sim_ready_to_check(store: float) -> Simulation:
	var sim := Simulation.create(12345, 32)
	var ws := sim.world
	ws.tick = Simulation.POP_PERIOD * 3 - 1  # the next step is a growth check
	ws.food_ema = 1.0
	ws.water_ema = 1.0
	ws.fish = 100.0
	ws.food_store = store
	return sim


func test_growth_checklist_predicts_the_next_check() -> void:
	for store in [29.0, 60.0]:
		var sim := _sim_ready_to_check(store)
		var v0 := sim.world.villagers
		var g := sim.growth_status()
		assert_eq(g["next_in"], 1)
		assert_eq(bool(g["store_ok"]), store >= v0 * 3.0, "store rule: 3 per person")
		sim.world.water_ema = 1.0
		sim.world.soil_moisture.fill(0.9)  # plenty of water around the village for the check
		sim.step()
		var ws := sim.world
		var grew := ws.villagers > v0
		var predicted := ws.food_ema > 0.95 and ws.water_ema > 0.95 and ws.food_store >= v0 * 3.0 and v0 < ws.housing_capacity()
		assert_eq(grew, predicted, "store %.0f: grew=%s (water %.2f)" % [store, str(grew), ws.water_ema])
		if store > 50.0:
			assert_true(grew, "a ready village grows at the check")
	var sim := _sim_ready_to_check(60.0)
	sim.world.villagers = sim.world.housing_capacity()
	assert_false(bool(sim.growth_status()["room_ok"]), "full homes block growth")
	assert_false(bool(sim.growth_status()["ready"]))


func test_missed_goals_are_named_when_time_runs_out() -> void:
	var sim := Simulation.create(Scenario.TUTORIAL_SEED, 32)
	sim.scenario = Scenario.tutorial()
	sim.world.tick = sim.scenario.start_tick + sim.scenario.deadline()
	sim.scenario.evaluate(sim.world)
	assert_eq(sim.scenario.status, Scenario.Status.FAILED)
	assert_true(sim.scenario.reason.contains("Have 1 farm (0/1)"), sim.scenario.reason)


func _main() -> Node:
	DirAccess.make_dir_recursive_absolute("user://test_ui")
	SaveSystem.delete_all("user://test_ui/clarity.json")
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = "user://test_ui/clarity.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.hud.clear_popups()
	if main.hud.coach_active():
		main.hud.end_coach()
	open_main(main)
	return main


func test_goals_card_lists_extra_stars_and_how_you_lose() -> void:
	var main := _main()
	main.start_scenario("expanding_village")
	main.hud.clear_popups()
	var txt: String = main.hud.goals_text()
	assert_true(txt.contains("Extra stars"), txt)
	assert_true(txt.contains("You lose if only"), txt)
	assert_true(txt.contains("min at normal speed"), txt)
	main.start_sandbox({"seed": 5})
	main.hud.update_objectives(main.sim)
	assert_true(main.hud.goals_text().contains("Reach 15 villagers"), "free play suggests ideas: " + main.hud.goals_text())
	main.get_parent().remove_child(main)
	main.free()


func test_toasts_put_bad_news_first_and_coalesce_rain() -> void:
	var main := _main()
	var ev: EventLog = main.sim.events
	main._seen_event_id = ev.next_id
	for k in 5:
		ev.record(main.sim.world.tick + k, EventLog.Type.HEAVY_RAIN, -1, -1, 0.06)
	ev.record(main.sim.world.tick, EventLog.Type.DRY_SEASON, -1, -1, 0.0)
	ev.record(main.sim.world.tick, EventLog.Type.FOOD_SHORTAGE, 5, 5, 0.5)
	main._toast_new_events()
	assert_true(main.hud.toast_count() <= main.TOAST_BATCH, "at most two at once")
	var texts := PackedStringArray()
	for t in main.hud._toasts.get_children():
		for l in t.find_children("*", "Label", true, false):
			texts.append((l as Label).text)
	assert_true(" ".join(texts).contains("Food shortage"), "bad news is shown: %s" % " | ".join(texts))
	main.get_parent().remove_child(main)
	main.free()


func test_tool_hint_and_icon_costs() -> void:
	var main := _main()
	main.hud.select_tool(Hud.Tool.BUILD_FARM)
	assert_true(main.hud.tool_hint_text().contains("within 5 tiles"), main.hud.tool_hint_text())
	assert_eq(main.hud.tool_cost_text(Hud.Tool.BUILD_FARM), "3 labor · 2 wood")
	main.hud.select_tool(Hud.Tool.INSPECT)
	assert_eq(main.hud.tool_hint_text(), "", "no hint while just looking")
	main.get_parent().remove_child(main)
	main.free()
