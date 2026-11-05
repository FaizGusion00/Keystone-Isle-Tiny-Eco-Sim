class_name Ambience
extends Node2D
## Atmosphere around the island, all purely visual and driven by sim state:
## season/weather colour grading (CanvasModulate), drifting cloud shadows, rain particles,
## leaping fish (more fish => more leaps, muddy water => fewer), a bobbing boat by the village,
## smoke and embers over wildfires, a golden burst over a farm when it is harvested, villagers
## strolling between the hall, houses and fields, a low-sun light grade that warms through the
## year, and one-shot "pop" rings when the player changes a tile.
## Uses its own RandomNumberGenerator so it never touches simulation randomness.

const CLOUD_TEX := preload("res://assets/art/cloud.png")
const DROP_TEX := preload("res://assets/art/raindrop.png")

## Colour grade per season (Spring, Rainy, Summer, Dry).
const SEASON_TINT := [Color(1.0, 1.0, 1.0), Color(0.93, 0.97, 1.0), Color(1.0, 0.99, 0.95), Color(1.0, 0.95, 0.86)]
const RAIN_TINT := Color(0.80, 0.85, 0.90)
const DOT_TEX := preload("res://assets/art/soft_dot.png")
const GRADE_SHADER := preload("res://shaders/grade.gdshader")
## Low-sun light per season (warm glow colour + strength): fresh spring, grey rains, bright
## summer, golden dry season. Rain mutes it.
const SEASON_SUN := [Color(1.0, 0.92, 0.74, 0.10), Color(0.86, 0.92, 1.0, 0.05),
	Color(1.0, 0.88, 0.62, 0.13), Color(1.0, 0.74, 0.42, 0.18)]
const MAX_WALKERS := 10

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
var _grade: ColorRect
var _sun := Color(1, 1, 1, 0)
var _sun_target := Color(1, 1, 1, 0)
var _walkers: Array = []        ## [Sprite2D, from, to, progress, pause, speed]
var bursts := 0                ## particle bursts fired (harvest/embers), for tests and stats
var _farm_growth := {}          ## farm tile -> last crop growth (harvest detection)


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
	_grade = ColorRect.new()
	_grade.name = "Grade"
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = GRADE_SHADER
	_grade.material = gm
	_rain_layer.add_child(_grade)
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
	_farm_growth.clear()
	for w in _walkers:
		w[0].queue_free()
	_walkers.clear()
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
	var sun: Color = SEASON_SUN[season]
	_sun_target = Color(sun.r, sun.g, sun.b, sun.a * (1.0 - 0.75 * _rain_target))
	_check_harvests(snap)
	_sync_walkers()
	if snap:
		rain = _rain_target
		_tint = _tint_target
		_modulate.color = _tint
		_sun = _sun_target
		_apply_grade()


func _apply_grade() -> void:
	var m := _grade.material as ShaderMaterial
	var data_view := view != null and view.overlay != WorldView.Overlay.NONE
	_grade.visible = not data_view
	m.set_shader_parameter("warm", _sun)
	m.set_shader_parameter("cool", Color(0.07, 0.12, 0.18, 0.16 + 0.08 * rain))


## A farm whose crop went from ripe to bare since the last tick was just harvested: a burst of
## golden chaff over it.
func _check_harvests(snap: bool) -> void:
	var ws := view.world
	var seen := {}
	for i in ws.tile_count():
		if ws.structure[i] != WorldState.Structure.FARM:
			continue
		var g := ws.crop_growth[i]
		seen[i] = true
		if not snap and _farm_growth.get(i, 0.0) >= 0.7 and g < 0.25 and not reduce_motion:
			var c := ws.coords(i)
			burst(view.position + view.top_center(c.x, c.y) + Vector2(0, 14), Color(1.0, 0.86, 0.38), Color(0.95, 0.66, 0.22), 18, 1.1)
		_farm_growth[i] = g
	for k in _farm_growth.keys():
		if not seen.has(k):
			_farm_growth.erase(k)


## One-shot particle burst (harvest chaff, fire embers). Frees itself.
func burst(at: Vector2, c0: Color, c1: Color, n: int, life: float, rise := 46.0) -> void:
	bursts += 1
	if not is_inside_tree():
		return
	var p := CPUParticles2D.new()
	p.texture = DOT_TEX
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = n
	p.lifetime = life
	p.position = at
	p.z_index = 25
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 9.0
	p.direction = Vector2(0, -1)
	p.spread = 55.0
	p.initial_velocity_min = rise * 0.5
	p.initial_velocity_max = rise
	p.gravity = Vector2(0, 40)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.22
	var ramp := Gradient.new()
	ramp.set_color(0, c0)
	ramp.set_color(1, Color(c1.r, c1.g, c1.b, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## Villagers out and about: about one walker per two people (up to 10), strolling between the
## hall, houses and fields. Purely cosmetic and seeded from the ambience RNG.
func _walk_spots() -> PackedVector2Array:
	var ws := view.world
	var out := PackedVector2Array()
	for i in ws.tile_count():
		var st := ws.structure[i]
		if st == WorldState.Structure.SETTLEMENT or st == WorldState.Structure.HOUSE or st == WorldState.Structure.FARM:
			var c := ws.coords(i)
			out.append(view.position + view.top_center(c.x, c.y) + Vector2(0, 16))
	return out


func walker_count() -> int:
	return _walkers.size()


func _sync_walkers() -> void:
	var ws := view.world
	var want := mini(MAX_WALKERS, int(ws.villagers / 2.0)) if ws.settlement_index >= 0 else 0
	if want == _walkers.size():
		return
	var spots := _walk_spots()
	if spots.size() < 2:
		want = 0
	while _walkers.size() > want:
		_walkers.pop_back()[0].queue_free()
	while _walkers.size() < want:
		var sp := Sprite2D.new()
		sp.texture = ArtAtlas.TEXTURE
		sp.region_enabled = true
		var nm: String = ["villager_a", "villager_b", "villager_c"][_walkers.size() % 3]
		var r: Array = ArtAtlas.R[nm]
		sp.region_rect = Rect2(r[0], r[1], r[2], r[3])
		sp.scale = Vector2.ONE / ArtAtlas.SCALE
		sp.offset = Vector2(r[2] * 0.5 - r[4], r[3] * 0.5 - r[5])
		sp.z_index = 1
		add_child(sp)
		var a := spots[_rng.randi_range(0, spots.size() - 1)] + _jitter()
		sp.position = a
		_walkers.append([sp, a, a, 1.0, _rng.randf_range(0.0, 2.5), _rng.randf_range(7.0, 11.0)])


func _jitter() -> Vector2:
	return Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-5, 5))


func _move_walkers(delta: float) -> void:
	if _walkers.is_empty() or reduce_motion:
		return
	var spots: PackedVector2Array
	for w in _walkers:
		var sp: Sprite2D = w[0]
		if w[3] >= 1.0:
			w[4] -= delta
			sp.position = w[2]
			if w[4] > 0.0:
				continue
			if spots.is_empty():
				spots = _walk_spots()
				if spots.is_empty():
					return
			w[1] = w[2]
			w[2] = spots[_rng.randi_range(0, spots.size() - 1)] + _jitter()
			w[3] = 0.0
			w[4] = _rng.randf_range(1.0, 4.0)
			sp.flip_h = w[2].x < w[1].x
		var dist := maxf(1.0, (w[2] - w[1]).length())
		w[3] = minf(1.0, w[3] + delta * w[5] / dist)
		sp.position = w[1].lerp(w[2], w[3]) + Vector2(0, -absf(sin(w[3] * dist * 0.45)) * 0.9)


func _process(delta: float) -> void:
	if view == null or view.world == null:
		return
	_t += delta
	var k := 1.0 - exp(-delta * 1.5)
	rain = lerpf(rain, _rain_target, k)
	_tint = _tint.lerp(_tint_target, k)
	_modulate.color = _tint
	_sun = _sun.lerp(_sun_target, k)
	_apply_grade()
	_move_walkers(delta)
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
					var at := view.position + view.top_center(c2.x, c2.y)
					_spawn_sprite("smoke", at + Vector2(_rng.randf_range(-8, 8), -10), 30, 2.4, Vector2(_rng.randf_range(4, 14), -40))
					if not reduce_motion:
						burst(at + Vector2(0, 2), Color(1.0, 0.82, 0.36), Color(0.95, 0.32, 0.12), 6, 1.0, 60.0)
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
	ring.still = reduce_motion
	ring.z_index = 30
	add_child(ring)


## A puff of dust where trees came down or a building was taken apart.
func dust(tile: Vector2i) -> void:
	if view == null or reduce_motion:
		return
	burst(view.position + view.top_center(tile.x, tile.y) + Vector2(0, -4), Color(0.80, 0.70, 0.55, 0.85),
		Color(0.62, 0.52, 0.40, 0.0), 12, 0.7, 30.0)


## "−2 labor" style text that rises off a tile and fades (cost / gain feedback).
## With reduce motion it fades in place instead of rising.
func float_text(tile: Vector2i, text: String, color: Color = Color(1, 1, 1)) -> Label:
	if view == null or text == "":
		return null
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiKit.font(false, 700))
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.10, 0.14, 0.16, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 40
	add_child(l)
	l.reset_size()
	var at := view.position + view.top_center(tile.x, tile.y) - Vector2(l.size.x * 0.5, 34.0)
	l.position = at
	var tw := l.create_tween().set_parallel(true)
	l.set_meta("rises", not reduce_motion)
	if not reduce_motion:
		tw.tween_property(l, "position", at + Vector2(0, -26), 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.75)
	tw.chain().tween_callback(l.queue_free)
	return l
