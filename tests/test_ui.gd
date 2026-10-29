extends TestCase
## UI layer: screens, HUD costs/inspector/why-chain, coach marks, clock hold, camera easing.

const DIR := "user://test_ui"
const SCREENS := ["menu", "campaign", "challenges", "new_world", "settings", "pause", "load", "save", "achievements"]


func _main() -> Node:
	DirAccess.make_dir_recursive_absolute(DIR)
	var p := DIR + "/ui.json"
	SaveSystem.delete_all(p)
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = p
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	while main.hud.popup_text() != "":
		main.hud.dismiss_popup()
	if main.hud.coach_active():
		main.hud.end_coach()
	return main


func _free(main: Node) -> void:
	main.get_parent().remove_child(main)
	main.free()


func test_clock_hold_blocks_ticks() -> void:
	var c := SimClock.new()
	assert_true(c.can_tick())
	c.held = true
	assert_false(c.can_tick(), "held clock (menu open) never ticks")
	c.held = false
	c.blocked = true
	assert_false(c.can_tick())
	c.free()


func test_every_screen_builds_and_holds_the_game() -> void:
	var main := _main()
	var tick0: int = main.sim.world.tick
	for n in SCREENS:
		main.screens.open(n, {}, false)
		assert_true(main.screens.is_open(), n)
		assert_eq(main.screens.current, n)
		assert_true(main.screens._content != null and main.screens._content.get_child_count() > 0, "%s has content" % n)
		assert_true(main.clock.held, "%s holds the clock" % n)
		assert_false(main.hud.visible, "%s hides the HUD" % n)
		assert_false(main.camera.input_enabled, "%s blocks camera input" % n)
	for won in [true, false]:
		main._debug_screen("results_won" if won else "results_failed")
		assert_eq(main.screens.current, "results")
	main.screens.close()
	assert_false(main.screens.is_open())
	assert_false(main.clock.held, "closing resumes time")
	assert_true(main.hud.visible)
	assert_true(main.camera.input_enabled)
	for i in 20:
		main.clock._process(0.0)
	assert_eq(main.sim.world.tick, tick0, "no ticks ran while screens were open")
	_free(main)


func test_toolbar_shows_costs_and_inspector_and_why_chain() -> void:
	var main := _main()
	main.sim.run(150)
	main.hud.set_status(main.sim.world)
	for t in range(1, Hud.Tool.size()):
		var txt: String = main.hud._tool_cost[t].text
		assert_true(txt == "free" or txt.contains("labor") or txt.contains("wood"), "tool %d cost '%s'" % [t, txt])
	var v: Vector2i = main.sim.world.coords(main.sim.world.settlement_index)
	main.select_tile(v)
	assert_true(main.hud.inspector_visible(), "inspector slides in")
	assert_true(main.hud.tile_text(main.sim, v).contains("Village"), main.hud.tile_text(main.sim, v))
	main.select_tile(Vector2i(-1, -1))
	# why-chain: find any event with a recorded cause and explain it in the drawer
	var pick := -1
	for id in main.sim.events.recent(EventLog.CAPACITY):
		if main.sim.events.explain(id).size() > 1:
			pick = id
			break
	assert_true(pick >= 0, "150 ticks produce at least one caused event")
	main.hud.show_events(main.sim.events, pick)
	assert_true(main.hud.events_panel.visible)
	assert_true(main.hud.explanation_text().contains("because") or main.hud.explanation_text().contains("caused by"), main.hud.explanation_text())
	main.hud.hide_events()
	assert_false(main.hud.events_panel.visible)
	_free(main)


func test_coach_marks_walk_through_and_end() -> void:
	var main := _main()
	main.hud.start_coach()
	assert_true(main.hud.coach_active())
	var guard := 0
	while main.hud.coach_active() and guard < 20:
		main.hud._coach_next.pressed.emit()
		guard += 1
	assert_false(main.hud.coach_active(), "coach ends after the last tip")
	assert_true(guard >= 5 and guard <= 8, "about six tips (%d)" % guard)
	_free(main)


func test_toasts_are_capped() -> void:
	var main := _main()
	for i in 6:
		main.hud.toast("t%d" % i)
	assert_true(main.hud._toasts.get_child_count() <= 3, "at most three toasts on screen")
	assert_eq(main.hud.toast_text(), "t5")
	_free(main)


func test_camera_zoom_eases_to_target() -> void:
	var cam := CameraController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(cam)
	cam.zoom = Vector2.ONE
	cam.smooth = true
	cam.zoom_smooth(Vector2.ZERO, 2.0)
	cam._process(0.016)
	assert_true(cam.zoom.x > 1.0 and cam.zoom.x < 2.0, "eases, not jumps (%f)" % cam.zoom.x)
	for i in 120:
		cam._process(0.016)
	assert_near(cam.zoom.x, 2.0, 0.01)
	cam.smooth = false
	cam.zoom_smooth(Vector2.ZERO, 0.5)
	assert_near(cam.zoom.x, 1.0, 0.01, "reduce motion: instant")
	cam.get_parent().remove_child(cam)
	cam.free()


func test_every_event_type_has_an_icon() -> void:
	assert_eq(Hud.event_icon(EventLog.Type.FLOOD), "waves")
	for t in EventLog.TYPE_NAMES:
		var icon := Hud.event_icon(t)
		assert_true(ResourceLoader.exists("res://assets/icons/%s.svg" % icon), "icon %s for %s" % [icon, EventLog.TYPE_NAMES[t]])
