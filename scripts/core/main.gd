extends Node2D
## Composition root: owns the Simulation, wires input -> picking -> actions/inspector,
## the fixed-tick clock -> view refresh, autosave and app-switch catch-up (see docs/TDD.md).

const DEFAULT_SEED := 12345
const MAP_SIZE := 32

@onready var world_view: WorldView = $WorldView
@onready var camera: CameraController = $Camera
var _menu_anchor := Vector2.INF  ## camera position framing the island beside the title menu
var _menu_pan_t := 0.0
var _menu_view := {}  ## camera pos/zoom saved while the title menu frames the island
@onready var hud: Hud = $HUD
@onready var clock: SimClock = $Clock
var ambience: Ambience
var guide: Guide
var _teaching := false  ## tutorial intro / coach tips still on screen: hold the clock
var audio: AudioDirector
var screens: Screens
var settings := GameSettings.new()
var progress := Progress.new()
## Online-ready seam (Play Games / Game Center / cloud saves later). Offline no-op today.
var services: PlatformServices = OfflinePlatformServices.new()

const AUTOSAVE_EVERY := 30 ## ticks

var sim: Simulation
var selected := Vector2i(-1, -1)
var _seen_event_id := 0

## Saving is on for normal launches; debug/screenshot runs (with user args) don't touch the
## player's save unless they pass --restore.
var persistence := true
var save_path := SaveSystem.DEFAULT_PATH
var catch_up: CatchUp = null
var last_save_unix := 0.0
var _suspended := false
var _suspended_at := 0.0
var _ticks_since_save := 0
var _scenario_status := -1
var _last_opts := {}            ## options of the running scenario/sandbox (for Restart)
var _menu_pan := 0.0
var _speed_before_pause := SimClock.Speed.NORMAL


signal action_done(action: int, tile: Vector2i)
signal action_failed(action: int, tile: Vector2i, why: String)


func _ready() -> void:
	# Desktop window close goes through quit_game() so audio is released cleanly first.
	get_tree().set_auto_accept_quit(false)
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	camera.tile_tapped.connect(_on_tile_tapped)
	hud.new_island_requested.connect(_on_new_island)
	hud.speed_requested.connect(set_speed)
	clock.ticked.connect(_on_ticked)
	hud.overlay_requested.connect(cycle_overlay)
	hud.events_requested.connect(func() -> void: hud.show_events(sim.events))
	hud.why_requested.connect(func(id: int) -> void: hud.show_events(sim.events, id))
	hud.tutorial_requested.connect(start_tutorial)
	hud.menu_requested.connect(pause_game)
	hud.tile_closed.connect(func() -> void: select_tile(Vector2i(-1, -1)))
	hud.tool_selected.connect(_on_tool_selected)
	hud.zoom_requested.connect(func(factor: float) -> void:
		camera.zoom_smooth(get_viewport().get_visible_rect().size * 0.5, factor))
	guide = Guide.new()
	guide.name = "Guide"
	guide.main = self
	add_child(guide)
	guide.finished.connect(_on_guide_finished)
	hud.guide_resolver = _guide_rect
	hud.village_pin_pressed.connect(func() -> void:
		focus_village()
		select_tile(sim.world.coords(sim.world.settlement_index)))
	hud.guide_next_requested.connect(func() -> void: guide.next())
	hud.guide_skip_requested.connect(skip_tutorial)
	hud.chip_explained.connect(func(key: String) -> void: guide.on_chip(key))
	hud.events_closed.connect(func() -> void: world_view.threads.clear())
	hud.chain_map_requested.connect(show_chain_on_map)
	hud.moment_show_requested.connect(_show_moment_on_map)
	action_done.connect(func(a: int, t: Vector2i) -> void: guide.on_action(a, t))
	camera.hover_moved.connect(_on_hover)
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)
	screens = Screens.new()
	screens.name = "Screens"
	screens.main = self
	add_child(screens)
	screens.opened.connect(_on_screen_changed)
	screens.closed.connect(_on_screen_changed.bind(""))
	get_viewport().size_changed.connect(_on_window_resized)
	var args := OS.get_cmdline_user_args()
	persistence = args.is_empty() or args.has("--restore")
	if persistence:
		SaveSystem.migrate_v1_file()
		settings = GameSettings.load_from()
		progress = Progress.load_from()
	if args.has("--reduce-motion"):
		settings.values["reduce_motion"] = true
	if args.has("--colorblind"):
		settings.values["colorblind"] = true
	for a in args:
		if a.begins_with("--lang="):
			settings.values["language"] = a.trim_prefix("--lang=")
		if a.begins_with("--ui-scale="):
			settings.values["ui_scale"] = float(a.trim_prefix("--ui-scale="))
	_on_window_resized()
	apply_settings()
	set_speed(SimClock.Speed.NORMAL)
	if persistence and restore_from_disk():
		open_menu()   # returning players land on the title screen with Continue
	elif persistence or args.has("--tutorial"):
		start_tutorial()
		if persistence and settings.first_run and I18n.locked == "":  # (tests lock the language)
			screens.open("language")  # very first launch: one tap for the language, then the guide
	else:
		var sid := ""
		for a in args:
			if a.begins_with("--scenario="):
				sid = a.trim_prefix("--scenario=")
		if sid != "":
			start_scenario(sid)
			hud.clear_popups()
		else:
			new_world(DEFAULT_SEED)
	if DisplayServer.get_name() != "headless":
		audio.start_loops()
	DebugTools.handle_cmdline(self)
	for a in args:
		if a.begins_with("--screen="):
			_debug_screen(a.trim_prefix("--screen="))
	if args.has("--coach"):
		hud.start_coach()


func _debug_screen(n: String) -> void:
	match n:
		"results_daily":
			start_scenario(ScenarioCatalog.daily_id({"year": 2026, "month": 10, "day": 30}))
			hud.clear_popups()
			clock.held = true
			sim.scenario.final_score = 1320
			sim.scenario.stars = 2
			sim.scenario.reason = I18n.f("Final score %d  ·  %s", [1320, I18n.t("silver")])
			progress.xp = 300
			screens.open("results", {"won": true, "stars": 2, "run": {"xp": 324, "level_up": true, "new_best": true}})
		"results_won", "results_failed":
			if sim.scenario == null:
				sim.scenario = Scenario.tutorial()
			_debug_results(n == "results_won")
		_:
			if n == "pause":
				clock.held = true
			screens.open(n)


func _debug_results(won: bool) -> void:
	clock.held = true
	if won:
		sim.scenario.reason = str(sim.scenario.def.get("win_text", "You did it."))
		screens.open("results", {"won": true, "stars": 2, "achievements": ["first_farm"]})
	else:
		sim.scenario.reason = "Too few villagers remain: the village could not feed itself."
		screens.open("results", {"won": false, "chain": _failure_chain()})


## Cosmetic banner chosen in the Journal: saved with the profile and shown over the village.
func set_banner(id: String) -> void:
	progress.banner = id
	progress.updated_at = _now()
	if persistence:
		progress.save()
	world_view.set_banner(progress.banner_color())


func prestige() -> bool:
	if not progress.do_prestige():
		return false
	progress.updated_at = _now()
	if persistence:
		progress.save()
	AudioDirector.sfx("win")
	return true


## Push visual/audio settings into the running game (called at start and whenever they change).
func apply_settings() -> void:
	if I18n.set_language(str(settings.get_value("language"))):
		_retranslate()
	var calm := bool(settings.get_value("reduce_motion"))
	world_view.set_motion(not calm)
	world_view.fx.enabled = not calm
	if calm:
		world_view.fx.finish_all()
	ambience.reduce_motion = calm
	UiKit.reduce_motion = calm
	UiKit.haptics = bool(settings.get_value("haptics"))
	camera.smooth = not calm
	if bool(settings.get_value("colorblind")) != world_view.colorblind:
		world_view.set_colorblind(bool(settings.get_value("colorblind")))
	hud.set_overlay(world_view.overlay, world_view.colorblind)
	var ui := float(settings.get_value("ui_scale"))
	hud.set_ui_scale(ui)
	if screens.ui_scale != ui:
		screens.set_ui_scale(ui)
	settings.apply_audio()


## The language changed: static labels re-translate themselves (auto-translate); rebuild what
## was formatted from templates (chips, goals, inspector, open screen).
func _retranslate() -> void:
	if screens != null and screens.current != "":
		screens._relayout()
	if hud == null or sim == null:
		return
	hud.set_day(sim.world.tick)
	hud.set_status(sim.world)
	hud.set_objective(sim.scenario.objective_text(sim.world) if sim.scenario != null else "")
	hud.update_objectives(sim)
	hud.retranslate()
	if guide.active():
		hud.show_guide(guide.current(), guide.i, guide.steps.size(), camera.last_was_touch)
	if hud._insp_tile.x >= 0 and hud._inspector.visible:
		hud.show_tile(sim, hud._insp_tile)


## Settings screen hook: store, persist and apply one value.
func change_setting(key: String, v) -> void:
	settings.set_value(key, v)
	if persistence:
		settings.save()
	apply_settings()


## Portrait windows get a portrait base resolution so the UI stays readable on phones.
func _on_window_resized() -> void:
	var win := get_window()
	if win == null:
		return
	var ws := win.size
	var want := Vector2i(720, 1280) if ws.y > ws.x else Vector2i(1280, 720)
	if win.content_scale_size != want:
		win.content_scale_size = want
	hud.relayout()
	frame_island.call_deferred()


func new_world(world_seed: int) -> void:
	set_simulation(Simulation.create(world_seed, MAP_SIZE))


func start_tutorial() -> void:
	var s := ScenarioCatalog.create_sim(ScenarioCatalog.get_def(Scenario.TUTORIAL_ID))
	_last_opts = {}
	screens.close()
	set_simulation(s)
	set_speed(SimClock.Speed.NORMAL)
	if bool(settings.get_value("show_tutorial")):
		# no wall of text: the guide opens on the map and teaches by doing, one step at a time
		camera.position = world_view.position + world_view.top_center(sim.world.width / 2, sim.world.height / 2)
		guide.start(GuideSteps.TUTORIAL)
		hud.show_title_card()  # the name and the promise while the camera flies in to the village
	else:
		hud.show_popup(I18n.f("Tutorial: %s", I18n.t(s.scenario.title())), I18n.t(s.scenario.intro_text()), "compass")
	autosave()


## When zoomed out, a pin marks the village (it is only a few pixels then); tap it to fly there.
const PIN_ZOOM := 0.95


func _place_village_pin() -> void:
	if sim == null or sim.world.settlement_index < 0 or screens.is_open() or camera.zoom.x >= PIN_ZOOM \
			or hud.guide_active() or world_view.threads.showing():
		hud.place_village_pin(Vector2.INF, 0)
		return
	var v := sim.world.coords(sim.world.settlement_index)
	var at := get_viewport().get_canvas_transform() * world_view.to_global(world_view.top_center(v.x, v.y))
	if not get_viewport().get_visible_rect().grow(-20).has_point(at):
		hud.place_village_pin(Vector2.INF, 0)
		return
	hud.place_village_pin(at, sim.world.villagers)


## Ease the camera onto the village (the guide's first stop).
func focus_village() -> void:
	if sim == null or sim.world.settlement_index < 0:
		return
	var v := sim.world.coords(sim.world.settlement_index)
	camera.user_moved = true
	camera.glide_to(world_view.position + world_view.top_center(v.x, v.y), maxf(camera.zoom.x, 1.6))


## The guide finished (or was skipped): everything the island offers opens up.
func _on_guide_finished(skipped: bool) -> void:
	_apply_island_tools(true)
	if skipped:
		hud.toast(I18n.t("Tutorial skipped. Tap People any time to see what the village needs."), 4.0, "compass")
	elif sim != null and sim.scenario != null:
		hud.award(I18n.t("Tutorial complete"), I18n.t("Well done"), "trophy")
	autosave()


## Tools / numbers this island opens (early campaign islands open fewer, see GuideSteps).
func _apply_island_tools(announce := false) -> void:
	var id := sim.scenario.id if sim != null and sim.scenario != null else ""
	var d: Dictionary = GuideSteps.ISLAND_TOOLS.get(id, {})
	if d.is_empty():
		hud.set_available([], [], [], true, announce)
	else:
		hud.set_available(d.get("tools", []), d.get("chips", Hud.ALL_CHIPS), d.get("extras", Hud.ALL_EXTRAS), false, announce)


## Screen rect (HUD root coords) of a guide target on the map, and the world marker on it.
func _guide_rect(target: String) -> Rect2:
	var t := _guide_tile(target)
	world_view.guide_marker.set_tile(t)
	if t.x < 0 or not is_inside_tree():
		return Rect2()
	var xf := get_viewport().get_canvas_transform()
	var pts := PackedVector2Array()
	for p in world_view.top_polygon(t.x, t.y):
		pts.append(xf * world_view.to_global(p))
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	r = r.grow_individual(0, 40.0, 0, 0)  # include the marker arrow above the tile
	var s := hud.root.get_global_transform_with_canvas().get_scale()
	return Rect2(r.position / s, r.size / s)


func _guide_tile(target: String) -> Vector2i:
	if sim == null or not target.begins_with("tile:"):
		return Vector2i(-1, -1)
	var ws := sim.world
	match target:
		"tile:village":
			return ws.coords(ws.settlement_index)
		"tile:farm":
			for i in ws.tile_count():
				if ws.structure[i] == WorldState.Structure.FARM:
					return ws.coords(i)
		"tile:best_farm":
			return best_farm_tile()
	return Vector2i(-1, -1)


## The farm site the guide suggests: allowed, not on a floodplain, moist, close to the village.
func best_farm_tile() -> Vector2i:
	var ws := sim.world
	var m := ValidTiles.compute(sim, Simulation.Action.BUILD_FARM)
	var v := ws.coords(ws.settlement_index)
	var best := Vector2i(-1, -1)
	var score := -INF
	for i in m.size():
		if m[i] != ValidTiles.OK and m[i] != ValidTiles.SHORT:
			continue
		var p := ws.coords(i)
		var sc := ws.soil_moisture[i] * 2.0 - float(maxi(absi(p.x - v.x), absi(p.y - v.y)))
		# open ground reads best: avoid tiles with forest around them (trees in front hide a farm)
		for o in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var q: Vector2i = p + o
			if ws.in_bounds(q.x, q.y) and ws.land_type[ws.index(q.x, q.y)] == LandType.FOREST:
				sc -= 1.5
		if sc > score:
			score = sc
			best = p
	return best


## Campaign / challenge entry point (also used by Next island and Restart).
func start_scenario(id: String, opts: Dictionary = {}) -> void:
	if id == Scenario.TUTORIAL_ID and opts.is_empty():
		start_tutorial()
		return
	var d := ScenarioCatalog.get_def(id)
	if d.is_empty():
		return
	_last_opts = opts
	screens.close()
	set_simulation(ScenarioCatalog.create_sim(d, opts))
	set_speed(SimClock.Speed.NORMAL)
	if str(d.get("intro", "")) != "":
		hud.show_popup(sim.scenario.title(), sim.scenario.intro_text(), "map")
	AudioDirector.sfx("ui_open")
	autosave()


func start_sandbox(opts: Dictionary) -> void:
	start_scenario("sandbox", opts)
	hud.toast(I18n.f("New island · seed %d", sim.world.world_seed), 3.0, "globe")


func has_game() -> bool:
	return sim != null


func restart_scenario() -> void:
	if sim.scenario == null:
		new_world(sim.world.world_seed)
		screens.close()
		return
	var opts := _last_opts.duplicate()
	if sim.scenario.is_sandbox() and opts.is_empty():
		opts = {"seed": sim.world.world_seed, "size": sim.world.width, "relaxed": sim.world.relaxed,
			"free_build": sim.world.free_build, "rare_events": sim.world.rare_events}
	start_scenario(sim.scenario.id, opts)


func next_scenario_id() -> String:
	if sim == null or sim.scenario == null:
		return ""
	var list: Array = ScenarioCatalog.CAMPAIGN if sim.scenario.def.get("kind", "") == "campaign" else ScenarioCatalog.CHALLENGES
	for k in list.size() - 1:
		if list[k]["id"] == sim.scenario.id and progress.is_unlocked(str(list[k + 1]["id"])):
			return str(list[k + 1]["id"])
	return ""


# ------------------------------------------------------------------ menus

func open_menu() -> void:
	screens.close()
	screens.open("menu")


func pause_game() -> void:
	if screens.is_open():
		return
	AudioDirector.sfx("ui_open")
	screens.open("pause")


func resume_game() -> void:
	screens.close()
	AudioDirector.sfx("ui_close")


func keep_playing() -> void:
	screens.close()
	set_speed(_speed_before_pause if _speed_before_pause != SimClock.Speed.PAUSED else SimClock.Speed.NORMAL)


func show_coach() -> void:
	screens.close()
	hud.start_coach()


## Skip button on the guide card.
func skip_tutorial() -> void:
	guide.stop(true)


func save_slot(slot: int) -> void:
	var err := SaveSystem.save_game(sim, SaveSystem.slot_path(slot), _meta())
	if err == OK:
		hud.toast(I18n.f("Saved to slot %d", slot + 1), 2.5, "save")
		AudioDirector.sfx("notify")
	else:
		hud.toast(I18n.f("Could not save: %s", error_string(err)), 3.0, "triangle-alert", true)


func load_slot(path: String) -> void:
	var r := SaveSystem.load_game(path)
	if r.is_empty():
		hud.toast("That save could not be read", 3.0, "triangle-alert", true)
		AudioDirector.sfx("ui_error")
		return
	_last_opts = {}
	screens.close()
	set_simulation(r["sim"])
	set_speed(int(r["meta"].get("speed", SimClock.Speed.NORMAL)))
	hud.toast(I18n.f("Loaded · day %d", sim.world.tick), 2.5, "folder-open")
	autosave()


func _meta() -> Dictionary:
	return {"saved_at": _now(), "speed": clock.speed, "held": clock.held or clock.teaching, "day": sim.world.tick, "villagers": sim.world.villagers,
		"keystone": roundi(sim.world.keystone),
		"title": sim.scenario.title() if sim.scenario != null else "Sandbox", "guide": guide.to_dict()}


func _on_screen_changed(screen_name: String) -> void:
	var open := screen_name != "" and screens.is_open()
	clock.held = open
	camera.input_enabled = not open
	hud.visible = not open
	if open:
		_clear_preview()
	if open and screen_name == "menu":
		select_tile(Vector2i(-1, -1))
	if not open and not _menu_view.is_empty():
		# back to play: return the camera to where the player left it
		var v := _menu_view
		_menu_view = {}
		if camera.smooth:
			var tw := camera.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(camera, "zoom", v["zoom"], 0.45)
			tw.tween_property(camera, "position", v["pos"], 0.45)
		else:
			camera.zoom = v["zoom"]
			camera.position = v["pos"]


## Fits the island's land (not the surrounding sea) into the screen area the HUD leaves free.
## Runs for a new island and on rotation / resize until the player pans or zooms.
func frame_island() -> void:
	if not is_inside_tree() or sim == null or camera.user_moved or not _menu_view.is_empty():
		return
	var free := hud.play_rect()
	if free.size.x < 40.0 or free.size.y < 40.0:
		return
	var land := _land_bounds()
	if free.size.y > free.size.x * 1.15:
		# Portrait: a whole iso diamond would be a thin strip. Let the far east/west tips
		# (mostly beach and sea) run off-screen so the island fills the screen's height.
		land = land.grow_individual(-land.size.x * 0.14, 0, -land.size.x * 0.14, 0)
	camera.frame_in(land, free, true)


## Called by the title menu once laid out: shows the whole island in the free space beside it.
func frame_menu_view(free: Rect2) -> void:
	if sim == null:
		return
	if _menu_view.is_empty():
		_menu_view = {"pos": camera.position, "zoom": camera.zoom}
	_menu_anchor = camera.frame_in(_land_bounds(), free)
	_menu_pan_t = 0.0


## Screen-space bounds of the island's land tiles (plus terrain height), for framing.
func _land_bounds() -> Rect2:
	var w := sim.world
	var r := Rect2()
	var any := false
	for y in w.height:
		for x in w.width:
			if LandType.is_water(w.land_type[y * w.width + x]):
				continue
			var c := Iso.tile_to_local(x, y)
			if not any:
				r = Rect2(c, Vector2.ZERO)
				any = true
			else:
				r = r.expand(c)
	if not any:
		return Iso.map_bounds(w.width, w.height)
	return r.grow_individual(Iso.HALF_W, Iso.HALF_H + WorldView.MAX_H, Iso.HALF_W, Iso.HALF_H + 12.0)


func set_simulation(s: Simulation) -> void:
	hud.clear_popups()
	if guide.active():
		guide.i = -1
		hud.hide_guide()
	if hud.coach_active():
		hud.end_coach()
	world_view.guide_marker.set_tile(Vector2i(-1, -1))
	_teaching = false
	clock.teaching = false
	sim = s
	catch_up = null
	_ach_tick = -100
	clock.blocked = _suspended
	_scenario_status = sim.scenario.status if sim.scenario != null else -1
	hud.set_objective(sim.scenario.objective_text(sim.world) if sim.scenario != null else "")
	hud.update_objectives(sim)
	_seen_event_id = sim.events.next_id
	hud.hide_events()
	clock.sim = sim
	world_view.banner_color = progress.banner_color()
	world_view.set_world(sim.world, sim.events)
	ambience.set_world(world_view)
	_menu_view = {}
	camera.set_bounds(Iso.map_bounds(sim.world.width, sim.world.height).grow_individual(0, WorldView.MAX_H, 0, 0))
	camera.user_moved = false
	frame_island.call_deferred()
	hud.set_seed(sim.world.world_seed)
	hud.set_day(sim.world.tick)
	hud.set_status(sim.world)
	select_tile(Vector2i(-1, -1))
	_apply_island_tools(false)
	_clear_preview()
	refresh_placement()
	_last_rain_toast = -1000
	_last_erosion_toast = -1000
	growth_blockers = {}
	_growth_check = sim.world.tick / Simulation.POP_PERIOD


func set_speed(s: int) -> void:
	clock.set_speed(s)
	hud.set_speed(s)
	_update_fx_gate()
	if guide != null:
		guide.on_speed(s)


func select_tile(t: Vector2i) -> void:
	if sim == null or not sim.world.in_bounds(t.x, t.y):
		t = Vector2i(-1, -1)
	selected = t
	world_view.highlight.set_tile(t)
	hud.show_tile(sim, t)
	if guide != null:
		guide.on_select(t)


func pick_tile(screen_pos: Vector2) -> Vector2i:
	var world_pos := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return world_view.pick(world_view.to_local(world_pos))


func _on_tile_tapped(screen_pos: Vector2) -> void:
	hud.world_touched()
	var t := pick_tile(screen_pos)
	if not sim.world.in_bounds(t.x, t.y):
		_clear_preview()
		select_tile(Vector2i(-1, -1))
		return
	var action := _action_for_tool(hud.tool)
	if action == Simulation.Action.NONE:
		AudioDirector.sfx("ui_click", 1.1, -6.0)
		select_tile(t)
		return
	# on a touch screen a big build is previewed first: tap once to see it, again to build
	if camera.last_was_touch and action in CONFIRM_ACTIONS and _preview != t:
		_show_preview(action, t, screen_pos)
		return
	_clear_preview()
	try_action(action, t)


## Applies `action` on tile `t` with all feedback (or explains why not). Returns true if done.
func try_action(action: int, t: Vector2i) -> bool:
	var why := placement_reason(action, t)
	if why != "":
		hud.toast(why, 2.5, "circle-x", true)
		hud.shake_place_tag()
		AudioDirector.sfx("ui_error")
		UiKit.haptic(40)
		action_failed.emit(action, t, why)
		select_tile(t)
		return false
	var labor0 := sim.world.labor
	var wood0 := sim.world.wood
	var before := world_view.capture_tile(t)
	sim.apply_action(action, t.x, t.y)
	world_view.refresh()
	world_view.animate_change(t, action, before)
	if action == Simulation.Action.CLEAR_TREES or action == Simulation.Action.DEMOLISH:
		ambience.dust(t)
	elif action == Simulation.Action.PLANT_TREES or action == Simulation.Action.RESTORE_LAND:
		ambience.bloom(t)  # life returning: a green burst of leaves
	ambience.pop(t)
	ambience.float_text(t, _delta_text(sim.world.labor - labor0, sim.world.wood - wood0),
		Color(1.0, 0.93, 0.80))
	AudioDirector.sfx(ACTION_SFX.get(action, "build"), randf_range(0.94, 1.06))
	UiKit.haptic(18)
	hud.set_status(sim.world)
	hud.update_objectives(sim)
	if action == Simulation.Action.BUILD_FARM and sim.world.count_structures(WorldState.Structure.FARM) == 1:
		hud.toast(I18n.f("Farm built! Its first harvest comes in about %d days.", int(Simulation.CROP_DAYS)), 4.0, "wheat")
	_warn_floodplain(action, t)
	action_done.emit(action, t)
	if action in REVERT_ACTIONS and not Input.is_key_pressed(KEY_SHIFT):
		hud.select_tool(Hud.Tool.INSPECT)  # one big build per pick: the next tap only looks
	else:
		refresh_placement()
	select_tile(t)
	return true


## Big, deliberate builds: previewed before building on touch, and the tool drops back to
## Inspect afterwards (hold Shift to keep it). Clear / Plant / Restore stay picked for painting.
const CONFIRM_ACTIONS := [Simulation.Action.BUILD_FARM, Simulation.Action.BUILD_HOUSE,
	Simulation.Action.BUILD_DAM, Simulation.Action.DEMOLISH]
const REVERT_ACTIONS := CONFIRM_ACTIONS

var _preview := Vector2i(-1, -1)
var _place_refresh_at := 0.0


func _show_preview(action: int, t: Vector2i, screen_pos: Vector2) -> void:
	_preview = t
	var info := place_info(action, t)
	world_view.placement.set_hover(t, info[0])
	hud.show_place_tag(screen_pos, I18n.f("Tap again to build · %s", info[1]) if info[0] else info[1], info[0])
	_preview_runoff(action, t)
	if not info[0]:
		hud.shake_place_tag()
		AudioDirector.sfx("ui_error", 1.0, -6.0)
	else:
		AudioDirector.sfx("ui_click", 1.2, -4.0)
	select_tile(t)


func _clear_preview() -> void:
	_preview = Vector2i(-1, -1)
	world_view.placement.set_hover(Vector2i(-1, -1), false)
	hud.hide_place_tag()
	_preview_runoff(Simulation.Action.NONE, Vector2i(-1, -1))


## [ok, text] for the placement tag: the cost if allowed, else the reason.
func place_info(action: int, t: Vector2i) -> Array:
	var why := placement_reason(action, t)
	if why != "":
		return [false, why]
	var c := sim.action_cost(action)
	var cost := hud.cost_text(c)
	if action in [Simulation.Action.BUILD_FARM, Simulation.Action.BUILD_HOUSE] \
			and sim.flood_risk(sim.world.index(t.x, t.y)) == 2:
		return [true, I18n.f("%s · may flood", cost)]
	return [true, cost]


## The mouse moved over the map: ghost + tag for the tile under it (build tools only).
func _on_hover(screen_pos: Vector2) -> void:
	if sim == null or screens.is_open():
		return
	var action := _action_for_tool(hud.tool)
	if action == Simulation.Action.NONE:
		return
	var t := pick_tile(screen_pos)
	if not sim.world.in_bounds(t.x, t.y):
		world_view.placement.set_hover(Vector2i(-1, -1), false)
		hud.hide_place_tag()
		return
	var info := place_info(action, t)
	world_view.placement.set_hover(t, info[0])
	hud.show_place_tag(screen_pos, info[1], info[0])
	_preview_runoff(action, t)


## Clearing or farming opens soil to the rain: show where it would wash (downhill to the sea).
func _preview_runoff(action: int, t: Vector2i) -> void:
	if action == Simulation.Action.CLEAR_TREES or action == Simulation.Action.BUILD_FARM:
		if t != _runoff_tile:
			_runoff_tile = t
			world_view.threads.preview_runoff(t)
	elif _runoff_tile.x >= 0:
		_runoff_tile = Vector2i(-1, -1)
		world_view.threads.preview_runoff(_runoff_tile)


var _runoff_tile := Vector2i(-1, -1)


## Recompute where the selected tool can be used (on tool change, after building, and as the
## island changes; throttled while time runs).
func refresh_placement() -> void:
	if sim == null:
		return
	var action := _action_for_tool(hud.tool)
	if action == Simulation.Action.NONE:
		world_view.placement.clear()
		hud.hide_place_tag()
		return
	world_view.placement.set_mask(action, ValidTiles.compute(sim, action))
	_place_refresh_at = Time.get_ticks_msec() / 1000.0


func _on_tool_selected(t: int) -> void:
	AudioDirector.sfx("ui_click")
	_clear_preview()
	refresh_placement()
	guide.on_tool(t)


## Why `action` can't be done on tile `t` ("" if it can), in the player's language.
## `can_apply` returns English: a whole key, or a cost sentence already filled with numbers.
func placement_reason(action: int, t: Vector2i) -> String:
	var why := sim.can_apply(action, t.x, t.y)
	if why == "":
		return ""
	var c := sim.action_cost(action)
	var ws: WorldState = sim.world
	if why.begins_with("Not enough labor:"):
		return I18n.f("Not enough labor: needs %d, you have %d", [ceili(c.x), floori(ws.labor)])
	if why.begins_with("Not enough wood:"):
		return I18n.f("Not enough wood: needs %d, you have %d (clear forest for wood)", [ceili(c.y), floori(ws.wood)])
	return I18n.t(why)


## "−1 labor  −2 wood" (or "+3 wood" when clearing forest) for the floater over a placed tile.
static func _delta_text(d_labor: float, d_wood: float) -> String:
	var parts: PackedStringArray = []
	var dl := roundi(d_labor)
	var dw := roundi(d_wood)
	if dl != 0:
		parts.append(I18n.f("%s%d labor", ["+" if dl > 0 else "−", absi(dl)]))
	if dw != 0:
		parts.append(I18n.f("%s%d wood", ["+" if dw > 0 else "−", absi(dw)]))
	return I18n.done("  ".join(parts))


## Building on a low river bank is allowed (fertile silt!) but the player should know the risk.
func _warn_floodplain(action: int, t: Vector2i) -> void:
	if action != Simulation.Action.BUILD_FARM and action != Simulation.Action.BUILD_HOUSE:
		return
	if sim.flood_risk(sim.world.index(t.x, t.y)) == 2:
		hud.toast(I18n.t("Built on a floodplain: the river may flood it in storms. Forests and dams upstream help."), 4.0, "waves", true)


const ACTION_SFX := {
	Simulation.Action.CLEAR_TREES: "chop", Simulation.Action.PLANT_TREES: "plant",
	Simulation.Action.BUILD_FARM: "build", Simulation.Action.BUILD_HOUSE: "build",
	Simulation.Action.BUILD_DAM: "water", Simulation.Action.RESTORE_LAND: "dig",
	Simulation.Action.DEMOLISH: "dig",
}


func _action_for_tool(t: int) -> int:
	match t:
		Hud.Tool.CLEAR_TREES: return Simulation.Action.CLEAR_TREES
		Hud.Tool.PLANT_TREES: return Simulation.Action.PLANT_TREES
		Hud.Tool.BUILD_FARM: return Simulation.Action.BUILD_FARM
		Hud.Tool.BUILD_HOUSE: return Simulation.Action.BUILD_HOUSE
		Hud.Tool.BUILD_DAM: return Simulation.Action.BUILD_DAM
		Hud.Tool.RESTORE_LAND: return Simulation.Action.RESTORE_LAND
		Hud.Tool.DEMOLISH: return Simulation.Action.DEMOLISH
	return Simulation.Action.NONE


func cycle_overlay() -> void:
	var o := (world_view.overlay + 1) % WorldView.OVERLAY_NAMES.size()
	world_view.set_overlay(o)
	hud.set_overlay_name(WorldView.OVERLAY_NAMES[o])
	hud.set_overlay(o, world_view.colorblind)
	AudioDirector.sfx("ui_click")


## New events worth telling the player about, most important first: bad news, then good news,
## then weather. At most TOAST_BATCH at once; heavy rain at most every RAIN_TOAST_GAP days;
## soil washing away (the first link of most chains) once a season.
const TOAST_BATCH := 2
const RAIN_TOAST_GAP := 10
const EROSION_TOAST_GAP := 30
const GOOD_NEWS := [EventLog.Type.POPULATION_GROWTH, EventLog.Type.WATER_CLEARED, EventLog.Type.DROUGHT_ENDED,
	EventLog.Type.FIRE_OUT, EventLog.Type.SPECIES_ARRIVED]
var _last_rain_toast := -1000
var _last_erosion_toast := -1000


func _toast_new_events() -> void:
	var picks: Array = []  # [priority, id]
	var ev := sim.events
	for id in range(maxi(_seen_event_id, ev.next_id - EventLog.CAPACITY), ev.next_id):
		var t := ev.type_of(id)
		var day := ev.tick_of(id)
		if t == EventLog.Type.EROSION:
			if day - _last_erosion_toast < EROSION_TOAST_GAP:
				continue
			_last_erosion_toast = day
			picks.append([2, id])
			continue
		if not (t in EventLog.NOTABLE):
			continue
		if t == EventLog.Type.HEAVY_RAIN:
			if day - _last_rain_toast < RAIN_TOAST_GAP:
				continue
			_last_rain_toast = day
		var pr := 3 if EventLog.is_bad(t) else (2 if t in GOOD_NEWS else 1)
		picks.append([pr, id])
		_maybe_moment(id)
	_seen_event_id = ev.next_id
	if picks.is_empty():
		return
	# keep the newest of each type, then the most important (newest first within a priority)
	var by_type := {}
	for p in picks:
		by_type[ev.type_of(p[1])] = p
	var best: Array = by_type.values()
	best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	var shown := 0
	for p in best:
		if shown >= TOAST_BATCH:
			break
		var id: int = p[1]
		var bad := EventLog.is_bad(ev.type_of(id))
		hud.toast(EventText.title(ev, id, sim.world), 4.5, Hud.event_icon(ev.type_of(id)), bad)
		if shown == 0:
			AudioDirector.sfx("warn" if bad else "notify", 1.0, -4.0)
			_auto_chain(id)
		shown += 1


## "Show on map": close History, frame the whole chain and let its threads play across the island.
func show_chain_on_map(id: int) -> void:
	hud.hide_events()
	if world_view.threads.show_chain(sim.events, id) == 0:
		return
	_chain_at = Time.get_ticks_msec() / 1000.0
	var r := world_view.threads.bounds()
	r.position += world_view.position
	var vs := get_viewport().get_visible_rect().size
	var z := clampf(minf(vs.x * 0.7 / maxf(r.size.x, 1.0), vs.y * 0.6 / maxf(r.size.y, 1.0)), 0.6, 2.2)
	camera.user_moved = true
	camera.glide_to(r.get_center(), z)


## The first time something big happens, explain it once (see Moments).
var _moment_event := -1


func _maybe_moment(id: int) -> void:
	var m := Moments.for_event(sim.events.type_of(id))
	if m.is_empty() or progress.moments.has(m[0]) or guide.active() or catch_up != null or hud.moment_open():
		return
	if not bool(settings.get_value("show_tutorial")):
		return
	if m[0] == "homes" and not hud.tool_available(Hud.Tool.BUILD_HOUSE):
		return
	progress.moments.append(m[0])
	if persistence:
		progress.save()
	_moment_event = id
	hud.show_moment(I18n.t(m[1]), I18n.t(m[2]), m[3])


func _show_moment_on_map() -> void:
	if _moment_event >= 0 and sim.events.has(_moment_event):
		if sim.events.causes_of(_moment_event).is_empty():
			var q := sim.events.pos_of(_moment_event)
			if sim.world.in_bounds(q.x, q.y):
				camera.user_moved = true
				camera.glide_to(world_view.position + world_view.top_center(q.x, q.y), maxf(camera.zoom.x, 1.4))
		else:
			show_chain_on_map(_moment_event)


## The most important new event lays its recorded causes on the map as glowing threads
## (at most every CHAIN_GAP seconds, and never over an open History drawer).
const CHAIN_GAP := 8.0
var _chain_at := -100.0


func _auto_chain(id: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _chain_at < CHAIN_GAP or hud.events_open() or catch_up != null or sim.events.causes_of(id).is_empty():
		return
	if world_view.threads.show_chain(sim.events, id) > 0:
		_chain_at = now


## Map animations: none while catching up or at the fastest speed (too much changes per second).
func _update_fx_gate() -> void:
	if world_view == null or world_view.fx == null:
		return
	world_view.auto_fx = world_view.fx.enabled and catch_up == null and clock.speed != SimClock.Speed.FAST


## How often each growth condition was missing at the village's growth checks this run.
var growth_blockers := {}
var _growth_check := 0


func _track_growth() -> void:
	var k := sim.world.tick / Simulation.POP_PERIOD
	if k == _growth_check:
		return
	_growth_check = k
	var g := sim.growth_status()
	if g["ready"] or g["leaving"]:
		return
	for c in ["fed_ok", "water_ok", "store_ok", "room_ok"]:
		if not g[c]:
			growth_blockers[c] = int(growth_blockers.get(c, 0)) + 1


## The condition that most often stopped the village growing, in words ("" if none).
func growth_blocker_text() -> String:
	var best := ""
	var n := 0
	for c in growth_blockers:
		if int(growth_blockers[c]) > n:
			n = int(growth_blockers[c])
			best = c
	match best:
		"fed_ok": return I18n.t("The village could not grow: not everyone was fed. Build farms near the village.")
		"water_ok": return I18n.t("The village could not grow: not enough fresh water near the village.")
		"store_ok": return I18n.t("The village could not grow: it needs 3 food stored per person. More farms fill the store.")
		"room_ok": return I18n.t("The village could not grow: every home was full. Build houses.")
	return ""


func _on_ticked(count: int) -> void:
	_track_growth()
	_update_fx_gate()
	_refresh_ui()
	guide.on_tick()
	if world_view.placement.visible and Time.get_ticks_msec() / 1000.0 - _place_refresh_at > 0.5:
		refresh_placement()  # the island changed under the overlay (labor regrew, trees grew…)
	_toast_new_events()
	_check_scenario()
	_check_achievements(false)
	audio.set_rain(sim.world.rain_today / Simulation.HEAVY_RAIN)
	_ticks_since_save += count
	if _ticks_since_save >= AUTOSAVE_EVERY:
		autosave()


var _ach_tick := -100

## Grants newly earned achievements (checked every few days, and at scenario end).
func _check_achievements(force: bool) -> Array:
	if sim == null or (not force and sim.world.tick - _ach_tick < 10):
		return []
	_ach_tick = sim.world.tick
	var fresh := progress.grant(Achievements.check(sim, progress.stars, progress.achievements))
	var found := progress.observe(sim)
	for t in found:
		hud.award(str(t), "New journal entry", "book-open")
	for id in fresh:
		services.unlock_achievement(str(id))
		var info := Achievements.get_info(str(id))
		hud.award(str(info.get("title", id)), "Achievement unlocked", str(info.get("icon", "award")))
	if not fresh.is_empty():
		AudioDirector.sfx("star")
	if (not fresh.is_empty() or not found.is_empty()) and persistence:
		progress.save()
	return fresh


func _refresh_ui() -> void:
	world_view.refresh()
	world_view.set_vitality_target(sim.world.keystone)
	ambience.update_from_world()
	hud.set_status(sim.world)
	hud.set_day(sim.world.tick)
	if sim.scenario != null:
		hud.set_objective(sim.scenario.objective_text(sim.world))
	hud.update_objectives(sim)
	if selected.x >= 0:
		hud.show_tile(sim, selected)


func _check_scenario() -> void:
	if sim.scenario == null or sim.scenario.status == _scenario_status:
		return
	_scenario_status = sim.scenario.status
	if _scenario_status == Scenario.Status.RUNNING:
		return
	_speed_before_pause = clock.speed
	set_speed(SimClock.Speed.PAUSED)
	var won := _scenario_status == Scenario.Status.WON
	var sc := sim.scenario
	var pts := sc.score(sim.world)
	var run := progress.record_run(sc.id, won, sc.stars if won else 0, pts, sc.days_elapsed(sim.world),
		sc.stars if sc.is_scored() else 0)
	progress.record_result(sc.id, won, sc.stars if won else 0)
	var mode := ScenarioCatalog.mode_of(sc.id)
	run["off_clock"] = mode in ["daily", "weekly"] and progress.observe_date(Progress.date_key())
	if sc.is_scored() and not sim.world.relaxed and not run["off_clock"]:
		services.submit_score(sc.id, pts)
	var fresh := _check_achievements(true)
	if persistence:
		progress.save()
	AudioDirector.sfx("win" if won else "lose")
	if screens.is_open() or catch_up != null or _suspended:
		# keep the old text popup path for background/catch-up endings
		hud.show_popup(I18n.f("Island complete! %s" if won else "Island lost: %s", I18n.t(sim.scenario.title())), I18n.t(sim.scenario.reason))
		return
	screens.open("results", {"won": won, "stars": sim.scenario.stars, "achievements": fresh,
		"chain": PackedStringArray() if won else _failure_chain(), "run": run,
		"blocker": "" if won else growth_blocker_text()})


## The cause chain behind the most recent population/food/water crisis.
func _failure_chain() -> PackedStringArray:
	for id in sim.events.recent(EventLog.CAPACITY):
		var t := sim.events.type_of(id)
		if t == EventLog.Type.POPULATION_LOSS or t == EventLog.Type.FOOD_SHORTAGE or t == EventLog.Type.WATER_SHORTAGE:
			return EventText.chain_lines(sim.events, id, sim.world)
	var fallback := PackedStringArray()
	for id in sim.events.recent(EventLog.CAPACITY):
		if EventLog.is_bad(sim.events.type_of(id)):
			var chain: PackedStringArray = sim.events.explain(id)
			if chain.size() > 1 and not chain[1].contains("No recorded cause"):
				return EventText.chain_lines(sim.events, id, sim.world)
			if fallback.is_empty():
				fallback = EventText.chain_lines(sim.events, id, sim.world)
	return fallback


func _on_new_island() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	new_world(rng.randi_range(1, 2147483646))
	autosave()


# ------------------------------------------------------------------ persistence & lifecycle

func _now() -> float:
	return Time.get_unix_time_from_system()


## Atomic autosave (temp file + verify + backup). Records the timestamp used for catch-up.
func autosave() -> Error:
	_ticks_since_save = 0
	if not persistence or sim == null:
		return ERR_UNAVAILABLE
	last_save_unix = _now()
	var meta := _meta()
	meta["saved_at"] = last_save_unix
	var err := SaveSystem.save_game(sim, save_path, meta)
	if err != OK:
		push_warning("autosave failed: %s" % error_string(err))
	return err


## Next launch (also after the OS killed the app): load the autosave, then catch up.
func restore_from_disk() -> bool:
	var r := SaveSystem.load_game(save_path)
	if r.is_empty():
		return false
	set_simulation(r["sim"])
	var speed := int(r["meta"].get("speed", SimClock.Speed.NORMAL))
	set_speed(speed)
	var gd: Dictionary = r["meta"].get("guide", {})
	if gd.has("i") and sim.scenario != null and sim.scenario.id == Scenario.TUTORIAL_ID:
		guide.start(GuideSteps.TUTORIAL, clampi(int(gd["i"]), 0, GuideSteps.TUTORIAL.size() - 1))
	if String(r["source"]).ends_with(".bak"):
		hud.toast("Main save was damaged: restored the backup", 4.0)
	# a game saved while a menu / pause screen held the clock was frozen: nothing to catch up
	if not bool(r["meta"].get("held", false)):
		start_catch_up(CatchUp.compute_ticks(_now() - float(r["saved_at"]), speed))
	return true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			suspend()
		NOTIFICATION_WM_CLOSE_REQUEST:
			suspend()
			quit_game()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			resume()


## Leaving the app: freeze the sim and save immediately (the OS may kill us at any time).
func suspend() -> void:
	if _suspended or sim == null or not is_node_ready():
		return
	_suspended = true
	clock.blocked = true
	if catch_up != null:
		catch_up.run_all()
		_finish_catch_up(false)
	autosave()
	_suspended_at = _now()


## Back in the app: catch up deterministically for the time we were away.
func resume() -> void:
	if not _suspended:
		return
	_suspended = false
	clock.blocked = false
	# time only passes for a running game: a pause or menu screen keeps the island frozen
	var speed := SimClock.Speed.PAUSED if clock.held or clock.teaching else clock.speed  # a tutorial step waiting to be read too
	start_catch_up(CatchUp.compute_ticks(_now() - _suspended_at, speed))


func start_catch_up(ticks: int) -> void:
	if ticks <= 0:
		return
	catch_up = CatchUp.new()
	catch_up.begin(sim, ticks)
	clock.blocked = true
	if ticks >= CatchUp.SUMMARY_MIN_TICKS:
		hud.toast(I18n.f("Catching up %d days…", ticks), 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_ESCAPE or k == KEY_BACK:
		if screens.is_open():
			if screens.current == "pause" or (screens.current == "menu" and sim != null):
				resume_game()
			elif screens.current != "results" and screens.current != "menu":
				screens.back()
		elif hud.coach_active() and not hud.guide_active():
			hud.end_coach()
		elif selected.x >= 0:
			select_tile(Vector2i(-1, -1))
		else:
			pause_game()
		get_viewport().set_input_as_handled()
	elif screens.is_open():
		return
	elif k == KEY_SPACE:
		set_speed(SimClock.Speed.NORMAL if clock.speed == SimClock.Speed.PAUSED else SimClock.Speed.PAUSED)
		get_viewport().set_input_as_handled()
	elif k >= KEY_1 and k <= KEY_8:
		if hud.tool_available(k - KEY_1):
			hud.select_tool(k - KEY_1)
		get_viewport().set_input_as_handled()
	elif k == KEY_L:
		cycle_overlay()
	elif k == KEY_H:
		hud.show_events(sim.events)


## Clean exit: silence audio first so its playbacks are released before the engine shuts down.
var _quitting := false
## Quits once the audio mixer has provably dropped every playback (no timer heuristic):
## stop all players, then wait until the mixer has run two passes after the stop (pass 1 fades
## the playbacks out, pass 2 marks them for deletion) plus two frames for the main thread to free
## them. `AudioServer.get_time_since_last_mix()` dropping between two polls proves a pass ran.
## A 3 s guard only matters if no audio thread runs at all (then nothing is pending anyway).
func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	if AudioDirector.current != null:
		AudioDirector.current.shutdown()
	await drain_audio()
	I18n.shutdown()
	get_tree().quit()


var drain_stats := {}

func drain_audio(guard_ms := 3000) -> void:
	var t0 := Time.get_ticks_msec()
	var mixes := 0
	var frames_after := 0
	var last := AudioServer.get_time_since_last_mix()
	while frames_after < 2 and Time.get_ticks_msec() - t0 < guard_ms:
		await get_tree().process_frame
		var now := AudioServer.get_time_since_last_mix()
		if now < last:
			mixes += 1
		last = now
		if mixes >= 2:
			frames_after += 1
	drain_stats = {"mixes": mixes, "ms": Time.get_ticks_msec() - t0, "guard_hit": frames_after < 2}
	if OS.get_cmdline_user_args().has("--log-exit"):
		print("exit drain: ", drain_stats)


func _process(delta: float) -> void:
	if _teaching:
		_teaching = hud.coach_active() or hud.popup_open() or hud._coach_pending
	# reading a guide step / tip holds time; "watch it happen" steps let it run
	clock.teaching = _teaching or guide.holds_clock() or (hud.coach_active() and not hud.guide_active()) \
		or hud.moment_open()  # a first-time explanation waits for the player to read it
	if guide.active():
		world_view.guide_marker.set_tile(_guide_tile(str(guide.current().get("target", ""))))
		hud.place_guide()
	elif world_view.guide_marker.visible:
		world_view.guide_marker.set_tile(Vector2i(-1, -1))
	_place_village_pin()
	if screens != null and screens.current == "menu" and not UiKit.reduce_motion and sim != null:
		# slow cinematic drift around the framed island behind the title screen (fades in after the framing tween)
		_menu_pan += delta * 0.12
		_menu_pan_t = minf(_menu_pan_t + delta, 1.6)
		if _menu_anchor != Vector2.INF and _menu_pan_t > 0.6:
			var amp := smoothstep(0.6, 1.6, _menu_pan_t)
			var drift := Vector2(sin(_menu_pan) * 22.0, sin(_menu_pan * 0.7) * 12.0) * amp / camera.zoom.x
			camera.position = _menu_anchor + drift
	if catch_up != null and not _suspended:
		if catch_up.process_batch():
			_finish_catch_up(true)
		else:
			world_view.refresh()
			hud.set_day(sim.world.tick)


func _finish_catch_up(show_summary: bool) -> void:
	var cu := catch_up
	catch_up = null
	clock.blocked = _suspended
	_seen_event_id = sim.events.next_id
	_refresh_ui()
	if show_summary and cu.total >= CatchUp.SUMMARY_MIN_TICKS:
		hud.show_popup(I18n.t("While you were away"), cu.summary(), "history")
	_check_scenario()
	_check_achievements(true)
	autosave()
