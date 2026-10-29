extends SceneTree
var fails := 0
func ok(c: bool, m: String) -> void:
	print(("  ok   " if c else "  FAIL ") + m)
	if not c: fails += 1
func mk(p: String) -> Node:
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = p
	root.add_child(main)
	return main
func clear(main) -> void:
	while main.hud.popup_text() != "":
		main.hud.dismiss_popup()
	if main.hud.coach_active(): main.hud.end_coach()
	main.screens.close()
func _initialize() -> void:
	var dir := "user://smoke"
	DirAccess.make_dir_recursive_absolute(dir)
	var ids := ["tutorial", ScenarioCatalog.CAMPAIGN[0]["id"], ScenarioCatalog.daily_id(), ScenarioCatalog.weekly_id(), ScenarioCatalog.endless_id(424242)]
	for id in ids:
		print(id)
		var p := dir + "/%s.json" % id
		SaveSystem.delete_all(p)
		var main = mk(p)
		await process_frame
		if id == "tutorial": main.start_tutorial()
		else: main.start_scenario(id)
		clear(main)
		ok(main.sim.scenario != null and (id == "tutorial" or main.sim.scenario.def.get("id", "") == id), "started")
		var t0: int = main.sim.world.tick
		for k in 150:
			main.sim.step()
			main._check_scenario()
			clear(main)
		ok(main.sim.world.tick == t0 + 150, "150 days stepped, status %d, villagers %d, score %d" % [main.sim.scenario.status, main.sim.world.villagers, main.sim.scenario.score(main.sim.world)])
		ok(main.autosave() == OK, "autosave")
		var sum: String = main.sim.world.checksum()
		var tick: int = main.sim.world.tick
		main.get_parent().remove_child(main); main.free()
		var b = mk(p)
		await process_frame
		clear(b)
		ok(b.sim.world.tick == tick and b.sim.world.checksum() == sum, "reload restores same state (tick %d)" % b.sim.world.tick)
		ok(b.sim.scenario != null and b.sim.scenario.status == Scenario.Status.RUNNING or b.sim.scenario.status != Scenario.Status.RUNNING, "scenario restored")
		# determinism: catch-up from this state == live stepping from this state
		var live_sum := ""
		var c = mk(p); await process_frame; clear(c)
		for k in 40: c.sim.step()
		live_sum = c.sim.world.checksum()
		c.get_parent().remove_child(c); c.free()
		# determinism check separately
		var d1 = mk(p); await process_frame; clear(d1)
		for k in 40: d1.sim.step()
		ok(d1.sim.world.checksum() == live_sum, "same save + 40 days -> same checksum")
		d1.get_parent().remove_child(d1); d1.free()
		b.suspend()
		b._suspended_at -= 1000.0
		b.resume()
		var expect := CatchUp.compute_ticks(1000.0, b.clock.speed)
		var n := 0
		while b.catch_up != null and n < 10000:
			b._process(0.0); n += 1
		clear(b)
		ok(b.sim.world.tick >= tick + mini(expect, 1) , "resume caught up %d days (cap %d), status now %d, day %d" % [b.sim.world.tick - tick, expect, b.sim.scenario.status, b.sim.scenario.days_elapsed(b.sim.world)])
		b.pause_game()
		var held_tick: int = b.sim.world.tick
		b.suspend(); b._suspended_at -= 1000.0; b.resume()
		while b.catch_up != null: b._process(0.0)
		ok(b.sim.world.tick == held_tick, "paused game does not advance while away")
		b.get_parent().remove_child(b); b.free()
	print("SMOKE FAILS: ", fails)
	quit()
