extends Node2D
## Composition root: owns the Simulation, wires input -> picking -> actions/inspector,
## the fixed-tick clock -> view refresh, autosave and app-switch catch-up (see docs/TDD.md).

const DEFAULT_SEED := 12345
const MAP_SIZE := 32

@onready var world_view: WorldView = $WorldView
@onready var camera: CameraController = $Camera
@onready var hud: Hud = $HUD
@onready var clock: SimClock = $Clock
var ambience: Ambience
var settings := GameSettings.new()

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



func _ready() -> void:
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
	var args := OS.get_cmdline_user_args()
	persistence = args.is_empty() or args.has("--restore")
	if persistence:
		SaveSystem.migrate_v1_file()
		settings = GameSettings.load_from()
	if args.has("--reduce-motion"):
		settings.values["reduce_motion"] = true
	if args.has("--colorblind"):
		settings.values["colorblind"] = true
	apply_settings()
	set_speed(SimClock.Speed.NORMAL)
	if not (persistence and restore_from_disk()):
		if persistence or args.has("--tutorial"):
			start_tutorial()
		else:
			new_world(DEFAULT_SEED)
	DebugTools.handle_cmdline(self)


## Push visual/audio settings into the running game (called at start and whenever they change).
func apply_settings() -> void:
	var calm := bool(settings.get_value("reduce_motion"))
	world_view.set_motion(not calm)
	ambience.reduce_motion = calm
	if bool(settings.get_value("colorblind")) != world_view.colorblind:
		world_view.set_colorblind(bool(settings.get_value("colorblind")))
	settings.apply_audio()


func new_world(world_seed: int) -> void:
	set_simulation(Simulation.create(world_seed, MAP_SIZE))


func start_tutorial() -> void:
	var s := Simulation.create(Scenario.TUTORIAL_SEED, MAP_SIZE)
	s.scenario = Scenario.tutorial()
	set_simulation(s)
	set_speed(SimClock.Speed.NORMAL)
	hud.show_popup("Tutorial: " + s.scenario.title(), s.scenario.intro_text())
	autosave()


func set_simulation(s: Simulation) -> void:
	hud.clear_popups()
	sim = s
	catch_up = null
	clock.blocked = _suspended
	_scenario_status = sim.scenario.status if sim.scenario != null else -1
	hud.set_objective(sim.scenario.objective_text(sim.world) if sim.scenario != null else "")
	_seen_event_id = sim.events.next_id
	hud.hide_events()
	clock.sim = sim
	world_view.set_world(sim.world, sim.events)
	ambience.set_world(world_view)
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
	var t := pick_tile(screen_pos)
	if not sim.world.in_bounds(t.x, t.y):
		select_tile(Vector2i(-1, -1))
		return
	var action := _action_for_tool(hud.tool)
	if action != Simulation.Action.NONE:
		var why := sim.can_apply(action, t.x, t.y)
		if why != "":
			hud.toast(why)
		else:
			sim.apply_action(action, t.x, t.y)
			world_view.refresh()
			ambience.pop(t)
	select_tile(t)


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


func _toast_new_events() -> void:
	var newest := -1
	for id in range(maxi(_seen_event_id, sim.events.next_id - EventLog.CAPACITY), sim.events.next_id):
		if sim.events.type_of(id) in EventLog.NOTABLE:
			newest = id
	_seen_event_id = sim.events.next_id
	if newest >= 0:
		hud.toast(sim.events.describe(newest), 4.0)


func _on_ticked(count: int) -> void:
	_refresh_ui()
	_toast_new_events()
	_check_scenario()
	_ticks_since_save += count
	if _ticks_since_save >= AUTOSAVE_EVERY:
		autosave()


func _refresh_ui() -> void:
	world_view.refresh()
	ambience.update_from_world()
	hud.set_status(sim.world)
	hud.set_day(sim.world.tick)
	if sim.scenario != null:
		hud.set_objective(sim.scenario.objective_text(sim.world))
	if selected.x >= 0:
		hud.show_tile(sim, selected)


func _check_scenario() -> void:
	if sim.scenario == null or sim.scenario.status == _scenario_status:
		return
	_scenario_status = sim.scenario.status
	if _scenario_status == Scenario.Status.RUNNING:
		return
	set_speed(SimClock.Speed.PAUSED)
	if _scenario_status == Scenario.Status.WON:
		hud.show_popup("Tutorial complete!", sim.scenario.reason +
			"\n\nYou can keep playing this island, or press New island for a free sandbox.")
	else:
		var body := sim.scenario.reason
		for id in sim.events.recent(EventLog.CAPACITY):
			var t := sim.events.type_of(id)
			if t == EventLog.Type.POPULATION_LOSS or t == EventLog.Type.FOOD_SHORTAGE or t == EventLog.Type.WATER_SHORTAGE:
				body += "\n\nWhat happened:\n" + "\n".join(sim.events.explain(id))
				break
		hud.show_popup("Tutorial failed", body + "\n\nPress Tutorial to try again.")


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
	var err := SaveSystem.save_game(sim, save_path, {"saved_at": last_save_unix, "speed": clock.speed})
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
	start_catch_up(CatchUp.compute_ticks(_now() - float(r["saved_at"]), speed))
	return true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			suspend()
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
	start_catch_up(CatchUp.compute_ticks(_now() - _suspended_at, clock.speed))


func start_catch_up(ticks: int) -> void:
	if ticks <= 0:
		return
	catch_up = CatchUp.new()
	catch_up.begin(sim, ticks)
	clock.blocked = true
	if ticks >= CatchUp.SUMMARY_MIN_TICKS:
		hud.toast("Catching up %d days…" % ticks, 2.0)


func _process(_delta: float) -> void:
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
	autosave()
