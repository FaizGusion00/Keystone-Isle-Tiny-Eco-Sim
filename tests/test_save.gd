extends TestCase
## Milestone 5: versioned atomic save/load, backup fallback, deterministic catch-up,
## tutorial scenario, and the app lifecycle (suspend → resume → catch-up; kill → restore).

const DIR := "user://test_saves"


func _path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var p := DIR + "/" + name + ".json"
	SaveSystem.delete_all(p)
	return p


func _busy_sim(world_seed: int = 4242) -> Simulation:
	var sim := Simulation.create(world_seed, 32)
	var c := sim.world.coords(sim.world.settlement_index)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			sim.apply_action(Simulation.Action.BUILD_FARM, c.x + dx, c.y + dy)
	for y in range(0, 12):
		for x in range(0, 12):
			if sim.world.land_type[sim.world.index(x, y)] == LandType.FOREST: sim.apply_action(Simulation.Action.CLEAR_TREES, x, y)
	sim.scenario = Scenario.tutorial()
	sim.run(57)
	return sim


func test_round_trip_exact_and_continues_identically() -> void:
	var p := _path("roundtrip")
	var a := _busy_sim()
	assert_eq(SaveSystem.save_game(a, p, {"speed": 1}), OK)
	var r := SaveSystem.load_game(p)
	assert_false(r.is_empty(), "loaded")
	var b: Simulation = r["sim"]
	assert_eq(b.state_checksum(), a.state_checksum(), "identical state after load")
	assert_eq(b.events.explain(b.events.next_id - 1), a.events.explain(a.events.next_id - 1))
	assert_eq(int(r["meta"]["speed"]), 1)
	a.run(80)
	b.run(80)
	assert_eq(b.state_checksum(), a.state_checksum(), "RNG + state restored: futures match")
	assert_false(FileAccess.file_exists(p + ".tmp"), "no temp file left behind")


func test_backup_and_corruption_fallback() -> void:
	var p := _path("backup")
	var a := _busy_sim()
	SaveSystem.save_game(a, p)
	var first := a.state_checksum()
	a.run(10)
	SaveSystem.save_game(a, p)
	assert_true(FileAccess.file_exists(p + ".bak"), "previous save kept as backup")
	assert_eq(SaveSystem.load_game(p)["sim"].state_checksum(), a.state_checksum())
	# simulate a torn write / corruption of the main file
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"world\": {\"wid")
	f.close()
	var r := SaveSystem.load_game(p)
	assert_false(r.is_empty(), "fell back")
	assert_true(String(r["source"]).ends_with(".bak"))
	assert_eq(r["sim"].state_checksum(), first)
	SaveSystem.delete_all(p)
	assert_true(SaveSystem.load_game(p).is_empty(), "nothing to load")


func test_rejects_bad_saves() -> void:
	var a := _busy_sim()
	var d := SaveSystem.to_dict(a)
	var newer := d.duplicate(true)
	newer["version"] = SaveSystem.VERSION + 1
	assert_eq(SaveSystem.from_dict(newer), null, "future version refused")
	var short := d.duplicate(true)
	short["world"]["arrays"]["soil_depth"] = Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))
	assert_eq(SaveSystem.from_dict(short), null, "wrong array size refused")
	var missing := d.duplicate(true)
	missing["world"]["scalars"].erase("villagers")
	assert_eq(SaveSystem.from_dict(missing), null, "missing field refused")
	# JSON text round trip (floats at full precision) is exact
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d, "", false, true))
	assert_eq(SaveSystem.from_dict(parsed).state_checksum(), a.state_checksum())


func test_compute_catch_up_ticks() -> void:
	assert_eq(CatchUp.compute_ticks(100.0, SimClock.Speed.NORMAL), 100)
	assert_eq(CatchUp.compute_ticks(10.0, SimClock.Speed.FAST), 40)
	assert_eq(CatchUp.compute_ticks(3600.0, SimClock.Speed.FAST), CatchUp.MAX_TICKS, "capped")
	assert_eq(CatchUp.compute_ticks(3600.0, SimClock.Speed.PAUSED), 0, "paused never catches up")
	assert_eq(CatchUp.compute_ticks(-50.0, SimClock.Speed.NORMAL), 0, "clock went backwards")
	assert_eq(CatchUp.compute_ticks(0.4, SimClock.Speed.NORMAL), 0)


func test_catch_up_equals_normal_ticks() -> void:
	for n in [1, 39, 40, 41, 250]:
		var a := _busy_sim(777)
		var b := _busy_sim(777)
		b.scenario = null
		a.scenario = null
		a.run(n)
		var cu := CatchUp.new()
		cu.begin(b, n)
		var batches := 0
		while not cu.process_batch(17):
			batches += 1
		assert_eq(b.world.tick, a.world.tick)
		assert_eq(b.state_checksum(), a.state_checksum(), "N=%d catch-up == normal" % n)


func test_killed_app_restore_then_catch_up_matches() -> void:
	# The OS kills the app after the autosave; next launch loads it and catches up.
	var p := _path("killed")
	var live := _busy_sim()
	live.scenario = null
	SaveSystem.save_game(live, p, {"speed": SimClock.Speed.NORMAL})
	live.run(30) # what would have happened had the app kept running for 30 s at 1x
	var restored: Simulation = SaveSystem.load_game(p)["sim"]
	var cu := CatchUp.new()
	cu.begin(restored, CatchUp.compute_ticks(30.0, SimClock.Speed.NORMAL))
	cu.run_all()
	assert_eq(restored.state_checksum(), live.state_checksum())


func test_away_summary_from_event_log() -> void:
	var sim := Simulation.create(12345, 32)
	sim.world.free_build = true
	for y in 32:
		for x in 32:
			if sim.world.land_type[sim.world.index(x, y)] == LandType.FOREST: sim.apply_action(Simulation.Action.CLEAR_TREES, x, y)
	var cu := CatchUp.new()
	cu.begin(sim, 120)
	cu.run_all()
	var text := cu.summary()
	assert_true(text.begins_with("120 days passed."), text)
	assert_true(text.contains("The coastal water turned muddy"), text)
	assert_true(text.contains("Food shortage"), text)
	assert_true(text.contains("× Soil washed away"), "minor events are counted, not listed")
	var quiet := Simulation.create(12345, 32)
	quiet.run(5)
	var cu2 := CatchUp.new()
	cu2.begin(quiet, 0)
	assert_true(cu2.summary().contains("0 days passed."))


func test_tutorial_win_and_fail() -> void:
	var win := Simulation.create(Scenario.TUTORIAL_SEED, 32)
	win.scenario = Scenario.tutorial()
	var c := win.world.coords(win.world.settlement_index)
	var built := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if built < 2 and win.apply_action(Simulation.Action.BUILD_FARM, c.x + dx, c.y + dy):
				built += 1
	win.run(240)
	assert_eq(win.scenario.status, Scenario.Status.WON, "farms grow the village: " + win.scenario.reason)
	assert_true(win.scenario.ended_tick < 240)
	var idle := Simulation.create(Scenario.TUTORIAL_SEED, 32)
	idle.scenario = Scenario.tutorial()
	idle.run(240)
	assert_eq(idle.scenario.status, Scenario.Status.FAILED, "no farms → deadline missed")
	assert_eq(idle.scenario.ended_tick, 240)
	var starve := Simulation.create(Scenario.TUTORIAL_SEED, 32)
	starve.scenario = Scenario.tutorial()
	starve.world.villagers = 6
	starve.step()
	assert_eq(starve.scenario.status, Scenario.Status.FAILED)
	assert_true(starve.scenario.reason.contains("left"))
	var round := Scenario.from_dict(starve.scenario.to_dict())
	assert_eq(round.status, Scenario.Status.FAILED)
	assert_eq(round.ended_tick, starve.scenario.ended_tick)


func test_app_lifecycle_suspend_resume_and_relaunch() -> void:
	var p := _path("lifecycle")
	var tree := Engine.get_main_loop() as SceneTree
	var scene: PackedScene = load("res://scenes/world/main.tscn")
	var main = scene.instantiate()
	main.save_path = p
	tree.root.add_child(main)
	assert_true(main.sim.scenario != null, "first launch starts the tutorial")
	assert_true(main.guide.active(), "the guided tutorial opens on the map (no wall of text)")
	main._process(0.016)
	main.suspend()
	main._suspended_at -= 100.0
	main.resume()
	assert_eq(main.catch_up, null, "a tutorial step waiting to be read keeps the island frozen while away")
	main.guide.stop(true)
	main._process(0.016)
	var start_sum: String = main.sim.state_checksum()
	# app goes to background: immediate atomic autosave + frozen clock
	main._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_true(FileAccess.file_exists(p), "autosaved on pause")
	assert_true(main.clock.blocked)
	assert_eq(SaveSystem.load_game(p)["sim"].state_checksum(), start_sum)
	# 100 s pass in the background at 1x → 100 catch-up ticks on resume
	main._suspended_at -= 100.0
	main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_true(main.catch_up != null and main.catch_up.total == 100, "catch-up scheduled")
	while main.catch_up != null:
		main._process(0.016)
	var ref := ScenarioCatalog.create_sim(ScenarioCatalog.get_def(Scenario.TUTORIAL_ID))
	ref.run(100)
	assert_eq(main.sim.state_checksum(), ref.state_checksum(), "catch-up == normal play")
	assert_true(main.hud.popup_text().begins_with("While you were away"), main.hud.popup_text())
	# a popup raised meanwhile (e.g. tutorial won during catch-up) queues behind the summary
	main.hud.show_popup("Second", "queued")
	assert_true(main.hud.popup_text().begins_with("While you were away"), "summary stays on top")
	main.hud.dismiss_popup()
	assert_eq(main.hud.popup_text(), "Second\nqueued")
	main.hud.dismiss_popup()
	assert_eq(main.hud.popup_text(), "")
	assert_false(main.clock.blocked)
	var after_sum: String = main.sim.state_checksum()
	# app killed: new instance restores the autosave written after catch-up
	main.queue_free()
	tree.root.remove_child(main)
	var main2 = scene.instantiate()
	main2.save_path = p
	tree.root.add_child(main2)
	assert_eq(main2.sim.state_checksum(), after_sum, "restored after kill")
	assert_eq(main2.sim.world.tick, 100)
	# paused games never catch up
	main2.set_speed(SimClock.Speed.PAUSED)
	main2.suspend()
	main2._suspended_at -= 1000.0
	main2.resume()
	assert_eq(main2.catch_up, null)
	tree.root.remove_child(main2)
	main2.free()
	SaveSystem.delete_all(p)


func test_catch_up_keeps_running_after_a_won_island() -> void:
	var sim := Simulation.create(Scenario.TUTORIAL_SEED, 32)
	sim.scenario = Scenario.tutorial()
	sim.scenario.status = Scenario.Status.WON  # player chose "Keep playing"
	var cu := CatchUp.new()
	cu.begin(sim, 50)
	cu.run_all()
	assert_eq(sim.world.tick, 50, "a finished island still lives on while you are away")


func test_menu_or_pause_screen_freezes_time_away() -> void:
	var p := _path("held")
	var tree := Engine.get_main_loop() as SceneTree
	var scene: PackedScene = load("res://scenes/world/main.tscn")
	var main = scene.instantiate()
	main.save_path = p
	tree.root.add_child(main)
	main.hud.dismiss_popup()
	main.pause_game()
	assert_true(main.clock.held)
	main.suspend()
	assert_true(bool(SaveSystem.load_game(p)["meta"].get("held", false)), "held state saved in meta")
	main._suspended_at -= 100.0
	main.resume()
	assert_eq(main.catch_up, null, "pause screen open: no time passes")
	main.resume_game()
	main.suspend()
	main._suspended_at -= 10.0
	main.resume()
	assert_true(main.catch_up != null and main.catch_up.total == 10, "running game catches up")
	tree.root.remove_child(main)
	main.free()
	SaveSystem.delete_all(p)
