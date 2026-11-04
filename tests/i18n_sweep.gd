class_name I18nSweep
extends RefCounted
## Walks the whole game UI in one language and returns every text that had no translation:
## every screen, every island's intro + HUD + goals, the tutorial, tools and their rules,
## the inspector on each kind of tile, history + why-chains, toasts, awards and results.
## Used by tests/test_i18n.gd and tools/i18n_misses.gd (prints the list to translate).

const SCREENS := ["menu", "campaign", "challenges", "new_world", "settings", "pause", "load", "save",
	"achievements", "modes", "journal", "codex", "help", "results_won", "results_failed", "results_daily"]


static func run(code: String) -> Dictionary:
	var was_locked := I18n.locked
	I18n.locked = ""
	I18n.set_language(code)
	I18n.misses.clear()
	I18n.produced.clear()
	I18n.record_misses = true
	var tree := Engine.get_main_loop() as SceneTree
	DirAccess.make_dir_recursive_absolute("user://test_i18n")
	var p := "user://test_i18n/sweep.json"
	SaveSystem.delete_all(p)
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = p
	tree.root.add_child(main)
	main.settings.values["language"] = code
	main.apply_settings()
	walk(main)
	# tutorial: intro popup, then each coach step
	main.start_tutorial()
	walk(main)
	while main.hud.popup_text() != "":
		main.hud.dismiss_popup()
	if main.hud.coach_active():
		for i in main.hud._coach_steps.size():
			main.hud._coach_go(i)
			walk(main)
		main.hud.end_coach()
	# every tool's label, cost and tooltip
	for t in Hud.Tool.values():
		main.hud.select_tool(t)
		walk(main)
	main.hud.select_tool(Hud.Tool.INSPECT)
	# every island: intro, goals, a long run with building, inspector on each tile kind, history
	var ids: Array = []
	for d in ScenarioCatalog.all():
		ids.append(str(d["id"]))
	ids.append(ScenarioCatalog.daily_id())
	ids.append(ScenarioCatalog.weekly_id())
	ids.append(ScenarioCatalog.endless_id(777))
	for id in ids:
		main.start_scenario(id)
		walk(main)
		main.hud.clear_popups()
		_play(main)
	main.new_world(31)
	_play(main)
	for s in SCREENS:
		main._debug_screen(s)
		walk(main)
		main.screens.close()
	main.pause_game()
	walk(main)
	main.screens.close()
	tree.root.remove_child(main)
	main.free()
	SaveSystem.delete_all(p)
	I18n.record_misses = false
	var out := filter_formatted(I18n.misses.duplicate(), I18n.table(code))
	I18n.misses.clear()
	I18n.produced.clear()
	I18n.locked = was_locked
	I18n.set_language(was_locked if was_locked != "" else "en")
	return out


## A busy stretch of play on the current island: build, run, look at things.
static func _play(main: Node) -> void:
	var sim: Simulation = main.sim
	var ws := sim.world
	ws.labor = 200.0
	ws.wood = 99.0
	var A := Simulation.Action
	var built := 0
	var cleared := 0
	for y in ws.height:
		for x in ws.width:
			if built < 3 and sim.can_apply(A.BUILD_FARM, x, y) == "":
				sim.apply_action(A.BUILD_FARM, x, y)
				built += 1
			elif cleared < 40 and ws.land_type[ws.index(x, y)] == LandType.FOREST and sim.can_apply(A.CLEAR_TREES, x, y) == "":
				sim.apply_action(A.CLEAR_TREES, x, y)
				cleared += 1
	for y in ws.height:
		for x in ws.width:
			if sim.can_apply(A.BUILD_DAM, x, y) == "":
				sim.apply_action(A.BUILD_DAM, x, y)
				break
	# every refusal reason the tools can give, as a toast
	ws.labor = 0.0
	ws.wood = 0.0
	for a in [A.CLEAR_TREES, A.PLANT_TREES, A.BUILD_FARM, A.BUILD_HOUSE, A.BUILD_DAM, A.RESTORE_LAND, A.DEMOLISH]:
		var seen := {}
		for y in range(0, ws.height, 2):
			for x in range(0, ws.width, 2):
				var why := main.placement_reason(a, Vector2i(x, y)) as String
				if why != "" and not seen.has(why):
					seen[why] = true
					main.hud.toast(why, 1.0, "circle-x", true)
	ws.labor = 50.0
	ws.wood = 50.0
	for k in 8:
		sim.run(50)
		main._on_ticked(50)
		walk(main)
	# inspector on one tile of each kind / structure
	var kinds := {}
	for y in ws.height:
		for x in ws.width:
			var i := ws.index(x, y)
			var key := "%d/%d/%d" % [ws.land_type[i], ws.structure[i], 1 if ws.fire[i] != 0 else 0]
			if not kinds.has(key):
				kinds[key] = true
				main.select_tile(Vector2i(x, y))
				walk(main)
	main.select_tile(Vector2i(-1, -1))
	main.hud.show_events(sim.events)
	walk(main)
	var n := 0
	for id in sim.events.recent(EventLog.CAPACITY):
		if n > 40:
			break
		n += 1
		main.hud.show_events(sim.events, id)
		walk(main)
	main.hud.hide_events()
	for t in [0, 1, 2, 3, 4]:
		main.world_view.set_overlay(t)
		main.hud.set_overlay_name(WorldView.OVERLAY_NAMES[t])
		walk(main)
	main.world_view.set_overlay(0)
	main._check_scenario()
	walk(main)
	main.hud.clear_popups()


## Drop "misses" that are really the output of a translated template ("Hari 3" from "Hari %d").
static func filter_formatted(misses: Dictionary, table: Dictionary) -> Dictionary:
	var res: Array[RegEx] = []
	for k in table:
		var v := str(table[k])
		if not v.contains("%"):
			continue
		var rx := "^"
		var i := 0
		while i < v.length():
			var c := v[i]
			if c == "%" and i + 1 < v.length():
				var j := i + 1
				while j < v.length() and "0123456789.+-".contains(v[j]):
					j += 1
				var code := v[j] if j < v.length() else ""
				match code:
					"d", "f": rx += "[-+]?[0-9.,]+"
					"s": rx += "(?s:.*)"
					"%": rx += "%"
				i = j + 1
				continue
			rx += _escape(c)
			i += 1
		var r := RegEx.new()
		if r.compile(rx + "$") == OK:
			res.append(r)
	var out := {}
	for m in misses:
		var hit := false
		for r in res:
			if r.search(str(m)) != null:
				hit = true
				break
		if not hit:
			out[m] = true
	return out


static func _escape(c: String) -> String:
	return "\\" + c if "\\^$.|?*+()[]{}".contains(c) else c


## Look every visible text up, the way auto-translate would.
static func walk(node: Node) -> void:
	if node is Control:
		var c := node as Control
		if c.can_auto_translate():
			if c is Label:
				TranslationServer.translate((c as Label).text)
			elif c is Button:
				TranslationServer.translate((c as Button).text)
			elif c is RichTextLabel:
				TranslationServer.translate((c as RichTextLabel).text)
			elif c is LineEdit:
				TranslationServer.translate((c as LineEdit).placeholder_text)
			if c.tooltip_text != "":
				TranslationServer.translate(c.tooltip_text)
	for ch in node.get_children():
		walk(ch)
