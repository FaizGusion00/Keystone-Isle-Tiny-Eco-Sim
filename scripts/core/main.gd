extends Node2D
## Composition root: owns the Simulation, wires input -> picking -> actions/inspector,
## and the fixed-tick clock -> view refresh.

const DEFAULT_SEED := 12345
const MAP_SIZE := 32

@onready var world_view: WorldView = $WorldView
@onready var camera: CameraController = $Camera
@onready var hud: Hud = $HUD
@onready var clock: SimClock = $Clock

var sim: Simulation
var selected := Vector2i(-1, -1)
var _seen_event_id := 0

## Event types worth a toast when they happen.
const NOTABLE := [EventLog.Type.MUDDY_WATER, EventLog.Type.WATER_CLEARED, EventLog.Type.DROUGHT,
	EventLog.Type.DROUGHT_ENDED, EventLog.Type.FISH_DECLINE, EventLog.Type.HERBIVORE_DECLINE,
	EventLog.Type.CROP_FAILURE, EventLog.Type.FOOD_SHORTAGE, EventLog.Type.WATER_SHORTAGE,
	EventLog.Type.POPULATION_GROWTH, EventLog.Type.POPULATION_LOSS]


func _ready() -> void:
	camera.tile_tapped.connect(_on_tile_tapped)
	hud.new_island_requested.connect(_on_new_island)
	hud.speed_requested.connect(set_speed)
	clock.ticked.connect(_on_ticked)
	hud.overlay_requested.connect(cycle_overlay)
	hud.events_requested.connect(func() -> void: hud.show_events(sim.events))
	hud.why_requested.connect(func(id: int) -> void: hud.show_events(sim.events, id))
	new_world(DEFAULT_SEED)
	set_speed(SimClock.Speed.NORMAL)
	DebugTools.handle_cmdline(self)


func new_world(world_seed: int) -> void:
	set_simulation(Simulation.create(world_seed, MAP_SIZE))


func set_simulation(s: Simulation) -> void:
	sim = s
	_seen_event_id = sim.events.next_id
	hud.hide_events()
	clock.sim = sim
	world_view.set_world(sim.world)
	camera.set_bounds(Iso.map_bounds(sim.world.width, sim.world.height))
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
	return Iso.local_to_tile(world_view.to_local(world_pos))


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
	select_tile(t)


func _action_for_tool(t: int) -> int:
	match t:
		Hud.Tool.CLEAR_TREES: return Simulation.Action.CLEAR_TREES
		Hud.Tool.PLANT_TREES: return Simulation.Action.PLANT_TREES
		Hud.Tool.BUILD_FARM: return Simulation.Action.BUILD_FARM
	return Simulation.Action.NONE


func cycle_overlay() -> void:
	var o := (world_view.overlay + 1) % WorldView.OVERLAY_NAMES.size()
	world_view.set_overlay(o)
	hud.set_overlay_name(WorldView.OVERLAY_NAMES[o])


func _toast_new_events() -> void:
	var newest := -1
	for id in range(maxi(_seen_event_id, sim.events.next_id - EventLog.CAPACITY), sim.events.next_id):
		if sim.events.type_of(id) in NOTABLE:
			newest = id
	_seen_event_id = sim.events.next_id
	if newest >= 0:
		hud.toast(sim.events.describe(newest), 4.0)


func _on_ticked(_count: int) -> void:
	world_view.refresh()
	_toast_new_events()
	hud.set_status(sim.world)
	hud.set_day(sim.world.tick)
	if selected.x >= 0:
		hud.show_tile(sim, selected)


func _on_new_island() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	new_world(rng.randi_range(1, 2147483646))
