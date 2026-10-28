extends Node2D
## Composition root: owns the WorldState, wires input -> picking -> inspector.

const DEFAULT_SEED := 12345
const MAP_SIZE := 32

@onready var world_view: WorldView = $WorldView
@onready var camera: CameraController = $Camera
@onready var hud: Hud = $HUD

var world: WorldState
var selected := Vector2i(-1, -1)


func _ready() -> void:
	camera.tile_tapped.connect(_on_tile_tapped)
	hud.new_island_requested.connect(_on_new_island)
	new_world(DEFAULT_SEED)
	DebugTools.handle_cmdline(self)


func new_world(world_seed: int) -> void:
	world = IslandGenerator.generate(world_seed, MAP_SIZE, MAP_SIZE)
	world_view.set_world(world)
	camera.set_bounds(Iso.map_bounds(world.width, world.height))
	hud.set_seed(world_seed)
	select_tile(Vector2i(-1, -1))


func select_tile(t: Vector2i) -> void:
	if world == null or not world.in_bounds(t.x, t.y):
		t = Vector2i(-1, -1)
	selected = t
	world_view.highlight.set_tile(t)
	hud.show_tile(world, t)


func pick_tile(screen_pos: Vector2) -> Vector2i:
	var world_pos := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return Iso.local_to_tile(world_view.to_local(world_pos))


func _on_tile_tapped(screen_pos: Vector2) -> void:
	select_tile(pick_tile(screen_pos))


func _on_new_island() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	new_world(rng.randi_range(1, 2147483646))
