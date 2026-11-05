extends TestCase
## Translation: every text the player can see has a Bahasa Melayu entry, templates keep their
## placeholders, and switching language live re-translates the open UI.


func _codes(s: String) -> Array:
	var rx := RegEx.new()
	rx.compile("%[-+0-9.]*[dfs%]")
	var out := []
	for m in rx.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out


func test_every_template_in_code_has_a_translation() -> void:
	var tab := I18n.table("ms")
	var rx := RegEx.new()
	rx.compile("I18n\\.(?:t|f)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var missing := PackedStringArray()
	for f in _scripts("res://scripts"):
		for m in rx.search_all(FileAccess.get_file_as_string(f)):
			var key: String = JSON.parse_string("\"" + m.get_string(1) + "\"")
			if I18n.wants_translation(key) and not tab.has(key):
				missing.append(key)
	assert_eq(missing.size(), 0, "untranslated templates: %s" % ", ".join(missing))


func test_tables_and_data_files_are_translated() -> void:
	var tab := I18n.table("ms")
	var missing := PackedStringArray()
	for s in I18nTables.all_texts():
		if not tab.has(s):
			missing.append(s)
	assert_eq(missing.size(), 0, "untranslated: %s" % ", ".join(missing))


func test_placeholders_match() -> void:
	var tab := I18n.table("ms")
	for k in tab:
		assert_eq(_codes(str(tab[k])), _codes(str(k)), "placeholders differ for '%s'" % k)


func test_whole_ui_sweep_has_no_untranslated_text() -> void:
	var misses: Dictionary = I18nSweep.run("ms")
	assert_eq(misses.size(), 0, "untranslated on screen: %s" % ", ".join(PackedStringArray(misses.keys())))
	assert_eq(I18n.current(), "en", "the sweep restores the test locale")


func test_switching_language_live() -> void:
	I18n.locked = ""
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = "user://test_i18n/live.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.hud.clear_popups()
	if main.hud.coach_active():
		main.hud.end_coach()
	await main.get_tree().process_frame
	var nodes0: int = main.get_tree().get_node_count()
	var tile: Vector2i = main.sim.world.coords(main.sim.world.settlement_index)
	main.select_tile(tile)
	var where := "tile %d, %d" % [tile.x, tile.y]
	assert_true(main.hud._insp_sub.text.ends_with(where), main.hud._insp_sub.text)
	main.settings.values["language"] = "ms"
	main.apply_settings()
	assert_eq(I18n.current(), "ms")
	assert_eq(main.hud.tr("Farm"), "Ladang", "tool label translated")
	assert_true(main.hud._day_label.text.begins_with("Hari"), main.hud._day_label.text)
	assert_true(main.hud._insp_sub.text.ends_with("petak %d, %d" % [tile.x, tile.y]), main.hud._insp_sub.text)
	main.pause_game()
	main.screens.open("settings")
	main.settings.values["language"] = "en"
	main.apply_settings()
	assert_eq(I18n.current(), "en")
	assert_true(main.hud._day_label.text.begins_with("Day"), main.hud._day_label.text)
	assert_true(main.hud._insp_sub.text.ends_with(where), main.hud._insp_sub.text)
	main.screens.close()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var grew: int = main.get_tree().get_node_count() - nodes0
	assert_true(grew < 40, "no node pile-up across switches (+%d)" % grew)
	main.get_parent().remove_child(main)
	main.free()
	I18n.locked = "en"
	I18n.set_language("en")


func test_cost_refusal_is_translated_once() -> void:
	I18n.locked = ""
	I18n.set_language("ms")
	var sim := Simulation.create(12345, 32)
	sim.world.labor = 0.0
	sim.world.wood = 0.0
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.sim = sim
	var shown := ""
	for y in sim.world.height:
		for x in sim.world.width:
			var raw := sim.can_apply(Simulation.Action.BUILD_FARM, x, y)
			if raw.begins_with("Not enough labor:"):
				shown = main.placement_reason(Simulation.Action.BUILD_FARM, Vector2i(x, y))
				assert_true(raw.begins_with("Not enough labor:"), raw)
				break
		if shown != "":
			break
	assert_true(shown.begins_with("Tenaga tak cukup:"), shown)
	assert_false(shown.contains("Not enough"), shown)
	main.free()
	I18n.locked = "en"
	I18n.set_language("en")


func test_first_launch_follows_the_device_language() -> void:
	assert_true(I18n.codes().has(I18n.default_language()))
	var gs := GameSettings.load_from("user://test_i18n/does_not_exist.cfg")
	assert_eq(str(gs.get_value("language")), I18n.default_language())


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out
