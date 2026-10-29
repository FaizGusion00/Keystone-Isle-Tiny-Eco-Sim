extends TestCase
## UI layer: screens, HUD costs/inspector/why-chain, coach marks, clock hold, camera easing.

const DIR := "user://test_ui"
const SCREENS := ["menu", "campaign", "challenges", "new_world", "settings", "pause", "load", "save", "achievements",
	"modes", "journal", "codex", "help"]


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


func test_camera_flings_after_quick_drag_unless_reduced_motion() -> void:
	var cam := CameraController.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(cam)
	cam.bounds = Rect2(-5000, -5000, 10000, 10000)
	cam.zoom = Vector2.ONE
	cam.smooth = true
	cam._last_drag_us = Time.get_ticks_usec() - 16000
	cam.drag_by(Vector2(-20, 0))
	cam.release_drag()
	assert_true(cam.fling.x > 0.0, "a quick drag coasts on (%s)" % cam.fling)
	var x0 := cam.position.x
	for i in 90:
		cam._process(0.016)
	assert_true(cam.position.x > x0 + 5.0, "it keeps moving after release")
	assert_eq(cam.fling, Vector2.ZERO, "and comes to rest")
	cam.smooth = false
	cam._last_drag_us = Time.get_ticks_usec() - 16000
	cam.drag_by(Vector2(-20, 0))
	cam.release_drag()
	assert_eq(cam.fling, Vector2.ZERO, "reduce motion: stops dead")
	cam.get_parent().remove_child(cam)
	cam.free()


func test_every_event_type_has_an_icon() -> void:
	assert_eq(Hud.event_icon(EventLog.Type.FLOOD), "waves")
	for t in EventLog.TYPE_NAMES:
		var icon := Hud.event_icon(t)
		assert_true(ResourceLoader.exists("res://assets/icons/%s.svg" % icon), "icon %s for %s" % [icon, EventLog.TYPE_NAMES[t]])


func test_achievement_banners_queue_one_at_a_time() -> void:
	var main := _main()
	main.hud.award("First")
	main.hud.award("Second")
	main.hud.award("Third")
	assert_eq(main.hud.award_pending(), 3)
	assert_true(main.hud._award.visible, "first banner showing")
	assert_eq(main.hud._award_title.text, "First")
	assert_eq(main.hud._award_queue.size(), 2, "the rest wait their turn instead of stacking")
	_free(main)


func test_notifications_share_one_column_without_overlap() -> void:
	var main := _main()
	var vp := main.get_viewport()
	var old: Vector2i = vp.size
	main.hud.award("Overlap check")
	for i in 3:
		main.hud.toast("Day %d: Heavy rain (60 mm)" % i)
	for sz in [Vector2i(1280, 720), Vector2i(720, 1280), Vector2i(1920, 1080)]:
		vp.size = sz
		main.hud._layout(main.hud.root.size)
		main.hud._toasts.notification(Container.NOTIFICATION_SORT_CHILDREN)
		main.hud._stack.notification(Container.NOTIFICATION_SORT_CHILDREN)
		var rects: Array[Rect2] = main.hud.notification_rects()
		assert_eq(rects.size(), 4, "award + three toasts visible at %s" % sz)
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				assert_false(rects[a].grow(-1.0).intersects(rects[b].grow(-1.0)), "notices %d/%d overlap at %s" % [a, b, sz])
		assert_true(rects[0].position.y < rects[1].position.y, "the award banner heads the column")
		var goals: Rect2 = main.hud._obj_card.get_global_rect()
		if main.hud._obj_card.visible:
			for r in rects:
				assert_false(r.grow(-1.0).intersects(goals), "notices clear the goals card at %s" % sz)
	vp.size = old
	_free(main)


func test_goals_card_folds_to_a_pill() -> void:
	var main := _main()
	var sim: Simulation = ScenarioCatalog.create_sim(ScenarioCatalog.get_def("expanding_village"))
	main.set_simulation(sim)
	main.hud.update_objectives(sim)
	assert_false(main.hud.goals_collapsed(), "a new run shows the full checklist")
	var full_h: float = main.hud._obj_card.get_combined_minimum_size().y
	for i in Hud.OBJ_AUTO_DAYS + 1:
		sim.step()
		main.hud.update_objectives(sim)
	assert_true(main.hud.goals_collapsed(), "folds away after a few days")
	main.hud._layout(main.hud.root.size)
	assert_true(main.hud._obj_card.get_combined_minimum_size().y < full_h, "the pill is shorter than the card")
	assert_true(main.hud._obj_summary.visible and main.hud._obj_summary.text.contains("/"), "pill shows progress")
	main.hud._obj_chev.pressed.emit()
	assert_false(main.hud.goals_collapsed(), "the chevron opens it again")
	main.hud.world_touched()
	assert_true(main.hud.goals_collapsed(), "playing on the map tucks it away")
	_free(main)


func test_resource_chips_are_labelled_and_explain_on_tap() -> void:
	var main := _main()
	for key in main.hud._chips:
		var p: Control = main.hud._chips[key]["panel"]
		assert_true(p.tooltip_text != "", "%s has a tooltip" % key)
		var caps := p.find_children("*", "Label", true, false)
		assert_true(caps.size() >= 2, "%s chip has a value and a caption" % key)
	var food: Control = main.hud._chips["food"]["panel"]
	main.hud.explain_chip(food, "wheat")
	main.hud.explain_chip(food, "wheat")
	assert_eq(main.hud.toast_text(), "Food stored")
	var tips := 0
	for c in main.hud._toasts.get_children():
		if c.has_meta("chip_tip") and not c.is_queued_for_deletion():
			tips += 1
	assert_eq(tips, 1, "repeated taps replace the explanation")
	_free(main)


func test_juice_floaters_respect_reduce_motion() -> void:
	var main := _main()
	assert_eq(main._delta_text(-1.0, -2.0), "−1 labor  −2 wood")
	assert_eq(main._delta_text(0.0, 3.0), "+3 wood")
	assert_eq(main._delta_text(0.0, 0.0), "")
	var ws: WorldState = main.sim.world
	ws.free_build = false
	main.hud.set_status(ws)
	ws.food_store += 30.0
	main.hud.set_status(ws)
	var f: Control = main.hud._chips["food"]["panel"]
	var fl: Dictionary = main.hud._floaters
	assert_true(fl.has("food") and is_instance_valid(fl["food"]), "a harvest floats +N off the food chip")
	assert_eq((fl["food"] as Label).text, "+30")
	ws.food_store += 1.0
	var before: Label = fl["food"]
	main.hud.set_status(ws)
	assert_eq((fl["food"] as Label).text, "+30", "tiny changes stay quiet")
	assert_true(fl["food"] == before, "one floater per chip")
	# the badge stays on its own chip: never over the Health chip or a neighbour, in any layout
	var fr: Rect2 = before.get_global_rect()
	var cr: Rect2 = f.get_global_rect()
	assert_true(fr.position.x >= cr.position.x and fr.end.x <= cr.end.x + 0.5, "badge within its chip's width")
	assert_true(fr.end.y <= cr.end.y and fr.position.y >= cr.position.y - fr.size.y * 0.5, "badge on its chip's top edge")
	for k in main.hud._chips:
		var other: Control = main.hud._chips[k]["panel"]
		if other != f and other.is_visible_in_tree():
			assert_false(fr.grow(-1.0).intersects(other.get_global_rect()), "badge clear of the %s chip" % k)
	var old := UiKit.reduce_motion
	UiKit.reduce_motion = true
	main.ambience.reduce_motion = true
	var l: Label = main.ambience.float_text(Vector2i(5, 5), "−1 labor")
	assert_false(bool(l.get_meta("rises")), "reduce motion: floater fades in place")
	main.ambience.pop(Vector2i(5, 5))
	var ring: PopRing = main.ambience.get_child(main.ambience.get_child_count() - 1)
	assert_true(ring.still, "reduce motion: pop is a flash, not a ring")
	UiKit.reduce_motion = old
	main.ambience.reduce_motion = old
	_free(main)


func test_dam_and_flood_rows_are_accurate() -> void:
	var main := _main()
	var sim: Simulation = ScenarioCatalog.create_sim(ScenarioCatalog.get_def("floodplain"))
	sim.world.free_build = true
	main.set_simulation(sim)
	var ws := sim.world
	var river := -1
	var brook := -1
	for i in ws.tile_count():
		var c := ws.coords(i)
		if sim.tile_rule(Simulation.Action.BUILD_DAM, c.x, c.y) != "":
			continue
		if river < 0 and sim.dam_blocks_fish(c.x, c.y):
			river = i
		elif brook < 0 and not sim.dam_blocks_fish(c.x, c.y):
			brook = i
	assert_true(river >= 0 and brook >= 0, "both kinds of dam site exist")
	for i in [river, brook]:
		var c := ws.coords(i)
		assert_true(sim.apply_action(Simulation.Action.BUILD_DAM, c.x, c.y))
	var tr: String = main.hud.tile_text(sim, ws.coords(river))
	var tb: String = main.hud.tile_text(sim, ws.coords(brook))
	assert_true(tr.contains("River dam: blocks fish"), tr)
	assert_true(tb.contains("Small stream: fish pass"), tb)
	var fp := -1
	for i in ws.tile_count():
		if fp < 0 and sim.flood_risk(i) == 2 and ws.structure[i] == WorldState.Structure.NONE and not LandType.is_water(ws.land_type[i]):
			fp = i
	assert_true(main.hud.tile_text(sim, ws.coords(fp)).contains("Floodplain: river"), "floodplain tiles show the river level")
	_free(main)


func test_toolbar_fits_without_scrolling_at_every_layout() -> void:
	var main := _main()
	var vp := main.get_viewport()
	var old: Vector2i = vp.size
	for sz in [Vector2i(1280, 720), Vector2i(720, 1280), Vector2i(1170, 540), Vector2i(540, 1170)]:
		for sc in [0.85, 1.0, 1.3]:
			vp.size = sz
			main.hud.set_ui_scale(sc)
			main.hud._layout(main.hud.root.size)
			assert_true(main.hud.tools_fit_without_scroll(), "toolbar fits at %s x%.2f" % [sz, sc])
			var r: Rect2 = main.hud._toolbar.get_rect()
			assert_true(r.position.x >= 0.0 and r.end.x <= main.hud.root.size.x + 0.5, "toolbar on screen %s x%.2f" % [sz, sc])
			# every tool is reachable (on some page)
			main.hud.select_tool(7)
			assert_true(main.hud._tool_buttons[7].visible, "selecting a tool shows its page")
			main.hud.select_tool(0)
	vp.size = old
	main.hud.set_ui_scale(1.0)
	_free(main)


func test_history_is_master_detail_on_narrow_screens() -> void:
	var main := _main()
	var vp := main.get_viewport()
	var old: Vector2i = vp.size
	for i in 40:
		main.sim.step()
	assert_true(main.sim.events.count() > 0, "some events to show")
	var ev_id: int = main.sim.events.recent(1)[0]
	vp.size = Vector2i(720, 1280)
	main.hud.set_ui_scale(1.0)
	main.hud.show_events(main.sim.events)
	main.hud._layout(main.hud.root.size)
	assert_false(main.hud.history_showing_detail(), "portrait opens on the list")
	main.hud.show_explanation(ev_id)
	assert_true(main.hud.history_showing_detail(), "picking an event shows its causes")
	main.hud._hist_back.pressed.emit()
	assert_false(main.hud.history_showing_detail(), "All events goes back to the list")
	vp.size = Vector2i(1280, 720)
	main.hud._layout(main.hud.root.size)
	assert_true(main.hud._hist_two_col, "wide landscape shows list and causes side by side")
	assert_true(main.hud._hist_list_pane.visible and main.hud._hist_detail_pane.visible, "both panes visible")
	vp.size = old
	_free(main)


func test_title_menu_frames_island_and_restores_camera() -> void:
	var main := _main()
	main.camera.smooth = false
	var pos: Vector2 = main.camera.position
	var zoom: Vector2 = main.camera.zoom
	main.open_menu()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var free: Rect2 = main.screens.menu_free_rect
	assert_true(free.size.x > 100.0 and free.size.y > 100.0, "menu leaves room for the island")
	var vs: Vector2 = main.camera.get_viewport_rect().size
	var c: Vector2 = main._land_bounds().get_center()
	var on_screen: Vector2 = (c - main.camera.position) * main.camera.zoom.x + vs * 0.5
	assert_true(free.grow(4.0).has_point(on_screen), "island centred in the free space (%s in %s)" % [on_screen, free])
	main.screens.close()
	assert_true(main.camera.position.distance_to(pos) < 0.5 and main.camera.zoom.is_equal_approx(zoom), "closing the menu returns the camera")
	_free(main)


func test_scored_results_banner_prestige_and_sandbox_rare_events() -> void:
	var main := _main()
	main.persistence = false
	main.progress = Progress.new()
	main.progress.path = DIR + "/progress.json"
	main._debug_screen("results_daily")
	assert_eq(main.screens.current, "results")
	assert_true(main.sim.scenario.is_scored())
	# banners: a locked one is refused by banner_color, an unlocked one reaches the world view
	main.set_banner("coral")
	assert_eq(main.world_view.banner_color, Color.html("2f7d6d"), "locked banner falls back to Lagoon")
	main.progress.xp = Progress.xp_for_level(3)
	main.set_banner("coral")
	assert_eq(main.world_view.banner_color, Color.html("e0765a"))
	assert_false(main.prestige(), "prestige needs level 10")
	main.progress.xp = Progress.xp_for_level(10)
	assert_true(main.prestige())
	assert_eq(main.progress.prestige, 1)
	assert_eq(main.world_view.banner_color, Color.html("e0765a"), "level banners stay unlocked after prestige")
	main.screens.open("journal", {}, false)
	main.screens.open("modes", {}, false)
	# a finished scored run reaches the platform seam (offline: recorded only) and the bests
	var id := ScenarioCatalog.daily_id({"year": 2026, "month": 10, "day": 29})
	main.screens.close()
	main.start_scenario(id)
	main.sim.run(30)
	main.sim.scenario.status = Scenario.Status.FAILED
	main._check_scenario()
	var submitted := false
	for c in (main.services as OfflinePlatformServices).calls:
		if c[0] == "submit_score" and c[1][0] == id:
			submitted = true
	assert_true(submitted, str((main.services as OfflinePlatformServices).calls))
	assert_false(main.progress.best(id).is_empty())
	assert_eq(main.screens.current, "results")
	main.start_sandbox({"seed": 9, "size": 24, "preset": 0, "rare_events": true})
	assert_true(main.sim.world.rare_events)
	main.restart_scenario()
	assert_true(main.sim.world.rare_events, "restart keeps the rare-events option")
	_free(main)


## Accessibility floor on every screen and the HUD: touch targets >= 44 logical px, text >= 12 px.
func _a11y_walk(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is BaseButton:
		var s: Vector2 = (n as Control).get_combined_minimum_size()
		if s.x < 44.0 or s.y < 44.0:
			out.append("button %s %s" % [n.name, s])
	if n is Label and (n as Label).get_theme_font_size("font_size") < 12:
		out.append("label '%s' %d px" % [String((n as Label).text).left(24), (n as Label).get_theme_font_size("font_size")])
	for c in n.get_children():
		_a11y_walk(c, out)


func test_touch_targets_and_text_size_floor() -> void:
	var main := _main()
	for n in SCREENS:
		main.screens.open(n, {}, false)
		var out := []
		_a11y_walk(main.screens, out)
		assert_eq(out, [], n)
	main.screens.close()
	var hud_out := []
	_a11y_walk(main.hud, hud_out)
	assert_eq(hud_out, [], "hud")
	_free(main)


func test_exit_waits_for_the_mixer_not_a_timer() -> void:
	var main = _main()
	if AudioDirector.current != null:
		AudioDirector.current.shutdown()
	await main.drain_audio(3000)
	var st: Dictionary = main.drain_stats
	assert_true(st.has("mixes") and st.has("ms"))
	if AudioServer.get_mix_rate() > 0 and int(st["mixes"]) > 0:
		assert_true(int(st["mixes"]) >= 2, "two mixer passes observed: %s" % st)
		assert_false(bool(st["guard_hit"]), "drained by mixer progress, not the guard: %s" % st)
	else:
		print("    [exit] no audio thread mixing here; guard path only: ", st)
	for p in ([] if AudioDirector.current == null else AudioDirector.current.find_children("*", "AudioStreamPlayer", true, false)):
		assert_false((p as AudioStreamPlayer).playing, "every player stopped")
		assert_true((p as AudioStreamPlayer).stream == null, "every stream dropped")
	_free(main)


func test_new_island_is_framed_in_the_free_play_area() -> void:
	var main := _main()
	main.hud.relayout()
	main.camera.user_moved = false
	main.frame_island()
	var free: Rect2 = main.hud.play_rect()
	var land: Rect2 = main._land_bounds()
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	var z: float = main.camera.zoom.x
	var c: Vector2 = (land.get_center() - main.camera.position) * z + vs * 0.5
	assert_true(c.distance_to(free.get_center()) < 4.0, "island centred between the HUD rows and the toolbar")
	assert_true(land.size.y * z <= free.size.y + 0.5, "the whole island height fits")
	# once the player pans, rotation/resize no longer yanks the camera back
	main.camera.drag_by(Vector2(40, 0))
	var at: Vector2 = main.camera.position
	main.frame_island()
	assert_true(main.camera.position == at, "manual framing is kept")
	_free(main)
