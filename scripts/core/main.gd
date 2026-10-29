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
	hud.tool_selected.connect(func(_t: int) -> void: AudioDirector.sfx("ui_click"))
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
		if a.begins_with("--ui-scale="):
			settings.values["ui_scale"] = float(a.trim_prefix("--ui-scale="))
	_on_window_resized()
	apply_settings()
	set_speed(SimClock.Speed.NORMAL)
	if persistence and restore_from_disk():
		open_menu()   # returning players land on the title screen with Continue
	elif persistence or args.has("--tutorial"):
		start_tutorial()
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
			sim.scenario.reason = "Final score 1320  ·  silver"
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
	var calm := bool(settings.get_value("reduce_motion"))
	world_view.set_motion(not calm)
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


func new_world(world_seed: int) -> void:
	set_simulation(Simulation.create(world_seed, MAP_SIZE))


func start_tutorial() -> void:
	var s := Simulation.create(Scenario.TUTORIAL_SEED, MAP_SIZE)
	s.scenario = Scenario.tutorial()
	_last_opts = {}
	screens.close()
	set_simulation(s)
	set_speed(SimClock.Speed.NORMAL)
	hud.show_popup("Tutorial: " + s.scenario.title(), s.scenario.intro_text(), "compass")
	if bool(settings.get_value("show_tutorial")):
		hud.queue_coach()
	autosave()


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
	hud.toast("New island · seed %d" % sim.world.world_seed, 3.0, "globe")


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


func save_slot(slot: int) -> void:
	var err := SaveSystem.save_game(sim, SaveSystem.slot_path(slot), _meta())
	if err == OK:
		hud.toast("Saved to slot %d" % (slot + 1), 2.5, "save")
		AudioDirector.sfx("notify")
	else:
		hud.toast("Could not save: %s" % error_string(err), 3.0, "triangle-alert", true)


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
	hud.toast("Loaded · day %d" % sim.world.tick, 2.5, "folder-open")
	autosave()


func _meta() -> Dictionary:
	return {"saved_at": _now(), "speed": clock.speed, "held": clock.held, "day": sim.world.tick, "villagers": sim.world.villagers,
		"keystone": roundi(sim.world.keystone),
		"title": sim.scenario.title() if sim.scenario != null else "Sandbox"}


func _on_screen_changed(screen_name: String) -> void:
	var open := screen_name != "" and screens.is_open()
	clock.held = open
	camera.input_enabled = not open
	hud.visible = not open
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
	hud.set_seed(sim.world.world_seed)
	hud.set_day(sim.world.tick)
	hud.set_status(sim.world)
	select_tile(Vector2i(-1, -1))


func set_speed(s: int) -> void:
	clock.set_speed(s)
	hud.set_speed(s)


func select_tile(t: Vector2i) -> void:
	if sim == null or not sim.world.in_bounds(t.x, t.y):
		t = Vector2i(-1, -1)
	selected = t
	world_view.highlight.set_tile(t)
	hud.show_tile(sim, t)


func pick_tile(screen_pos: Vector2) -> Vector2i:
	var world_pos := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return world_view.pick(world_view.to_local(world_pos))


func _on_tile_tapped(screen_pos: Vector2) -> void:
	hud.world_touched()
	var t := pick_tile(screen_pos)
	if not sim.world.in_bounds(t.x, t.y):
		select_tile(Vector2i(-1, -1))
		return
	var action := _action_for_tool(hud.tool)
	if action != Simulation.Action.NONE:
		var why := sim.can_apply(action, t.x, t.y)
		if why != "":
			hud.toast(why, 2.5, "circle-x", true)
			AudioDirector.sfx("ui_error")
			UiKit.haptic(40)
		else:
			sim.apply_action(action, t.x, t.y)
			world_view.refresh()
			ambience.pop(t)
			AudioDirector.sfx(ACTION_SFX.get(action, "build"), randf_range(0.94, 1.06))
			UiKit.haptic(18)
			hud.set_status(sim.world)
			hud.update_objectives(sim)
			_warn_floodplain(action, t)
	else:
		AudioDirector.sfx("ui_click", 1.1, -6.0)
	select_tile(t)


## Building on a low river bank is allowed (fertile silt!) but the player should know the risk.
func _warn_floodplain(action: int, t: Vector2i) -> void:
	if action != Simulation.Action.BUILD_FARM and action != Simulation.Action.BUILD_HOUSE:
		return
	if sim.flood_risk(sim.world.index(t.x, t.y)) == 2:
		hud.toast("Built on a floodplain: the river may flood it in storms. Forests and dams upstream help.", 4.0, "waves", true)


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


func _toast_new_events() -> void:
	var newest := -1
	for id in range(maxi(_seen_event_id, sim.events.next_id - EventLog.CAPACITY), sim.events.next_id):
		if sim.events.type_of(id) in EventLog.NOTABLE:
			newest = id
	_seen_event_id = sim.events.next_id
	if newest >= 0:
		var bad := EventLog.is_bad(sim.events.type_of(newest))
		hud.toast(sim.events.describe(newest), 4.0, Hud.event_icon(sim.events.type_of(newest)), bad)
		AudioDirector.sfx("warn" if bad else "notify", 1.0, -4.0)


func _on_ticked(count: int) -> void:
	_refresh_ui()
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
		hud.show_popup(("Island complete! " if won else "Island lost: ") + sim.scenario.title(), sim.scenario.reason)
		return
	screens.open("results", {"won": won, "stars": sim.scenario.stars, "achievements": fresh,
		"chain": PackedStringArray() if won else _failure_chain(), "run": run})


## The cause chain behind the most recent population/food/water crisis.
func _failure_chain() -> PackedStringArray:
	for id in sim.events.recent(EventLog.CAPACITY):
		var t := sim.events.type_of(id)
		if t == EventLog.Type.POPULATION_LOSS or t == EventLog.Type.FOOD_SHORTAGE or t == EventLog.Type.WATER_SHORTAGE:
			return sim.events.explain(id)
	var fallback := PackedStringArray()
	for id in sim.events.recent(EventLog.CAPACITY):
		if EventLog.is_bad(sim.events.type_of(id)):
			var chain: PackedStringArray = sim.events.explain(id)
			if chain.size() > 1 and not chain[1].contains("No recorded cause"):
				return chain
			if fallback.is_empty():
				fallback = chain
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
	var speed := SimClock.Speed.PAUSED if clock.held else clock.speed
	start_catch_up(CatchUp.compute_ticks(_now() - _suspended_at, speed))


func start_catch_up(ticks: int) -> void:
	if ticks <= 0:
		return
	catch_up = CatchUp.new()
	catch_up.begin(sim, ticks)
	clock.blocked = true
	if ticks >= CatchUp.SUMMARY_MIN_TICKS:
		hud.toast("Catching up %d days…" % ticks, 2.0)


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
		elif hud.coach_active():
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
		hud.show_popup("While you were away", cu.summary())
	_check_scenario()
	_check_achievements(true)
	autosave()
