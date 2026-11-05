extends TestCase
## Motion: shared timings, closes animate then hide, reduce motion jumps to the end state.


func _main() -> Node:
	DirAccess.make_dir_recursive_absolute("user://test_ui")
	SaveSystem.delete_all("user://test_ui/motion.json")
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = "user://test_ui/motion.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.hud.clear_popups()
	if main.hud.coach_active():
		main.hud.end_coach()
	open_main(main)
	return main


func _free(main: Node) -> void:
	UiKit.reduce_motion = false
	main.get_parent().remove_child(main)
	main.free()


func _wait(tree: SceneTree, secs: float) -> void:
	await tree.create_timer(secs).timeout
	await tree.process_frame


func test_popup_fades_out_after_dismiss() -> void:
	var main := _main()
	var tree: SceneTree = main.get_tree()
	main.hud.show_popup("Hello", "body")
	await tree.process_frame
	main.hud.dismiss_popup()
	assert_eq(main.hud.popup_text(), "", "logically closed at once")
	assert_true(main.hud.popup.visible, "still fading")
	await _wait(tree, Motion.FAST + 0.1)
	assert_false(main.hud.popup.visible, "hidden after the fade")
	assert_false(main.hud._scrim.visible)
	_free(main)


func test_reduce_motion_hides_at_once() -> void:
	var main := _main()
	UiKit.reduce_motion = true
	main.hud.show_popup("Hello", "body")
	main.hud.dismiss_popup()
	assert_false(main.hud.popup.visible)
	main.hud.show_events(main.sim.events)
	main.hud.hide_events()
	assert_false(main.hud.events_panel.visible)
	main.screens.open("settings")
	main.screens.close()
	assert_false(main.screens.visible)
	_free(main)


func test_screen_close_is_logically_immediate_then_fades() -> void:
	var main := _main()
	var tree: SceneTree = main.get_tree()
	main.screens.open("settings")
	await tree.process_frame
	main.screens.close()
	assert_false(main.screens.is_open(), "closed for the game at once")
	assert_eq(main.screens.root.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the fading sheet lets taps through")
	main.screens.open("help")
	assert_true(main.screens.is_open() and main.screens.root.modulate.a == 1.0, "reopening cancels the fade")
	main.screens.close()
	await _wait(tree, Motion.FAST + 0.1)
	assert_false(main.screens.visible)
	_free(main)


func test_popup_reopened_while_fading_stays_visible() -> void:
	var main := _main()
	var tree: SceneTree = main.get_tree()
	main.hud.show_popup("One", "a")
	await tree.process_frame
	main.hud.dismiss_popup()
	main.hud.show_popup("Two", "b")
	await _wait(tree, Motion.FAST + 0.15)
	assert_true(main.hud.popup.visible and main.hud.popup_text().begins_with("Two"))
	_free(main)


func test_meter_and_pulse_land_on_their_end_state() -> void:
	var main := _main()
	var tree: SceneTree = main.get_tree()
	var bar := UiKit.meter(0.2)
	main.hud.root.add_child(bar)
	Motion.meter_to(bar, 0.9, 0.05)
	var lab := UiKit.label("x")
	main.hud.root.add_child(lab)
	Motion.pulse(lab, 1.2, 0.05)
	Motion.count_to(lab, 0.0, 10.0, func(v: float) -> String: return "%d" % roundi(v), 0.05)
	await _wait(tree, 0.15)
	assert_near(bar.value, 0.9, 1e-3)
	assert_eq(lab.scale, Vector2.ONE)
	assert_eq(lab.text, "10")
	_free(main)
