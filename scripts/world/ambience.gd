class_name Ambience
extends Node2D
## Atmosphere around the island, all purely visual and driven by sim state:
## season/weather colour grading (CanvasModulate), drifting cloud shadows, rain particles,
## leaping fish (more fish => more leaps, muddy water => fewer), a bobbing boat by the village,
## smoke over wildfires, and one-shot "pop" rings when the player changes a tile.
## Uses its own RandomNumberGenerator so it never touches simulation randomness.

const CLOUD_TEX := preload("res://assets/art/cloud.png")
const DROP_TEX := preload("res://assets/art/raindrop.png")

## Colour grade per season (Spring, Rainy, Summer, Dry).
const SEASON_TINT := [Color(1.0, 1.0, 1.0), Color(0.93, 0.97, 1.0), Color(1.0, 0.99, 0.95), Color(1.0, 0.95, 0.86)]
const RAIN_TINT := Color(0.80, 0.85, 0.90)

var view: WorldView
var reduce_motion := false
var rain := 0.0           ## 0..1 current rain intensity (smoothed)
var _rain_target := 0.0
var _tint := Color.WHITE
var _tint_target := Color.WHITE
var _modulate: CanvasModulate
var _clouds: Array[Sprite2D] = []
var _rain_layer: CanvasLayer
var _rain: CPUParticles2D
var _rng := RandomNumberGenerator.new()
var _water_tiles := PackedInt32Array()
var _fish_timer := 0.0
var _smoke_timer := 0.0
var _boat: Sprite2D
var _boat_base := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	_rng.seed = 424242
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	for k in 7:
		var s := Sprite2D.new()
		s.texture = CLOUD_TEX
		s.z_index = 20
		s.modulate = Color(0.10, 0.16, 0.20, 0.10)
		s.scale = Vector2.ONE * _rng.randf_range(2.6, 4.2)
		add_child(s)
		_clouds.append(s)
	_rain_layer = CanvasLayer.new()
	_rain_layer.layer = 1
	add_child(_rain_layer)
	_rain = CPUParticles2D.new()
	_rain.texture = DROP_TEX
	_rain.emitting = false
	_rain.amount = 260
	_rain.lifetime = 0.9
	_rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain.direction = Vector2(0.18, 1.0)
	_rain.spread = 2.0
	_rain.initial_velocity_min = 900.0
	_rain.initial_velocity_max = 1150.0
	_rain.gravity = Vector2.ZERO
	_rain.scale_amount_min = 1.2
	_rain.scale_amount_max = 2.0
	_rain.color = Color(0.9, 0.95, 1.0, 0.7)
	_rain.rotation = -0.18
	_rain_layer.add_child(_rain)
	_boat = Sprite2D.new()
	_boat.texture = ArtAtlas.TEXTURE
	_boat.region_enabled = true
	var r: Array = ArtAtlas.R["boat"]
	_boat.region_rect = Rect2(r[0], r[1], r[2], r[3])
	_boat.scale = Vector2.ONE / ArtAtlas.SCALE
	_boat.offset = Vector2(r[2] * 0.5 - r[4], r[3] * 0.5 - r[5])
	_boat.z_index = -1
	_boat.visible = false
	add_child(_boat)


func set_world(v: WorldView) -> void:
	view = v
	var ws := v.world
	_water_tiles.clear()
	var best := -1
	var best_d := 1e9
	var sc := ws.coords(ws.settlement_index) if ws.settlement_index >= 0 else Vector2i(-99, -99)
	for i in ws.tile_count():
		if ws.land_type[i] != LandType.SHALLOW_WATER:
			continue
		_water_tiles.append(i)
		var d := Vector2(ws.coords(i) - sc).length()
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		var bc := ws.coords(best)
		_boat_base = view.position + Iso.tile_to_local(bc.x, bc.y)
		_boat.position = _boat_base
		_boat.visible = true
	var b := Iso.map_bounds(ws.width, ws.height)
	for s in _clouds:
		s.position = view.position + Vector2(_rng.randf_range(b.position.x, b.end.x), _rng.randf_range(b.position.y, b.end.y))
	update_from_world(true)


## Called after every simulation tick.
func update_from_world(snap := false) -> void:
	if view == null or view.world == null:
		return
	var ws := view.world
	_rain_target = clampf(ws.rain_today / Simulation.HEAVY_RAIN, 0.0, 1.0) if ws.rain_today > 0.0 else 0.0
	var season := Simulation.season_of(ws.tick)
	_tint_target = (SEASON_TINT[season] as Color).lerp(RAIN_TINT, _rain_target * 0.7)
	view.set_wind(1.0 + _rain_target * 1.5)
	if snap:
		rain = _rain_target
		_tint = _tint_target
		_modulate.color = _tint


func _process(delta: float) -> void:
	if view == null or view.world == null:
		return
	_t += delta
	var k := 1.0 - exp(-delta * 1.5)
	rain = lerpf(rain, _rain_target, k)
	_tint = _tint.lerp(_tint_target, k)
	_modulate.color = _tint
	# rain particles cover the screen
	var vs := get_viewport_rect().size
	_rain.position = Vector2(vs.x * 0.5, -40)
	_rain.emission_rect_extents = Vector2(vs.x * 0.65, 10)
	var want := rain > 0.08
	if _rain.emitting != want:
		_rain.emitting = want
	_rain.modulate.a = clampf(0.25 + rain, 0.0, 1.0)
	# clouds drift and darken with rain
	var b := Iso.map_bounds(view.world.width, view.world.height).grow(300)
	b.position += view.position
	for s in _clouds:
		if not reduce_motion:
			s.position.x += delta * (10.0 + 18.0 * rain)
		if s.position.x > b.end.x:
			s.position.x = b.position.x
		s.modulate.a = 0.08 + 0.12 * rain
	# boat bob
	if _boat.visible:
		_boat.position = _boat_base + (Vector2(0, sin(_t * 1.3) * 1.2) if not reduce_motion else Vector2.ZERO)
		_boat.rotation = sin(_t * 0.9) * 0.04 if not reduce_motion else 0.0
	_fish_timer -= delta
	if _fish_timer <= 0.0 and not _water_tiles.is_empty():
		var ws := view.world
		var rate := clampf(ws.fish / 80.0, 0.05, 1.2)
		_fish_timer = _rng.randf_range(0.8, 2.4) / rate
		var i := _water_tiles[_rng.randi_range(0, _water_tiles.size() - 1)]
		if ws.sediment[i] < 0.03:
			var c := ws.coords(i)
			_spawn_sprite("fish", view.position + Iso.tile_to_local(c.x, c.y) + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-5, 5)), -1, 1.1, Vector2(0, -5))
	_smoke_timer -= delta
	if _smoke_timer <= 0.0:
		_smoke_timer = 0.35
		var ws2 := view.world
		if ws2.fires_burning > 0:
			for tries in 6:
				var j := _rng.randi_range(0, ws2.tile_count() - 1)
				if ws2.fire[j] != 0:
					var c2 := ws2.coords(j)
					_spawn_sprite("smoke", view.position + view.top_center(c2.x, c2.y) + Vector2(_rng.randf_range(-8, 8), -10), 30, 2.4, Vector2(_rng.randf_range(4, 14), -40))
					break


func _spawn_sprite(name: String, at: Vector2, z: int, life: float, drift: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = ArtAtlas.TEXTURE
	s.region_enabled = true
	var r: Array = ArtAtlas.R[name]
	s.region_rect = Rect2(r[0], r[1], r[2], r[3])
	s.scale = Vector2.ONE / ArtAtlas.SCALE
	s.offset = Vector2(r[2] * 0.5 - r[4], r[3] * 0.5 - r[5])
	s.position = at
	s.z_index = z
	s.modulate.a = 0.0
	add_child(s)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "modulate:a", 1.0, life * 0.25)
	tw.tween_property(s, "position", at + drift, life).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(s, "modulate:a", 0.0, life * 0.3)
	tw.chain().tween_callback(s.queue_free)


## Expanding ring on a tile the player just changed (juice).
func pop(tile: Vector2i, color: Color = Color(1, 0.95, 0.75)) -> void:
	if view == null:
		return
	var ring := PopRing.new()
	ring.position = view.position + view.top_center(tile.x, tile.y)
	ring.color = color
	ring.z_index = 30
	add_child(ring)
