class_name FishSchools
extends Node2D
## Fish you can see: small dark schools glide through the clear shallows around the island, one
## school per ~16 fish. They swim away from muddy water and thin out as the fish stock falls, so
## "the coast turned muddy, fish are declining" happens on the map, not only in a number.
## Drawn under the land (above the sea quad) as batched quads; ~40 tiny shapes at most.

const PER_SCHOOL := 12.0
const MAX_SCHOOLS := 8
const FISH_PER := 7

var view: WorldView
var _shallow := PackedInt32Array()
var _schools: Array = []   ## {pos, target, speed, alpha, phase}
var _rng := RandomNumberGenerator.new()
var NO_UV := PackedVector2Array()


func set_world() -> void:
	_rng.seed = 4242
	_shallow = PackedInt32Array()
	_schools.clear()
	var ws := view.world
	for i in ws.tile_count():
		if ws.land_type[i] == LandType.SHALLOW_WATER:
			_shallow.append(i)
	queue_redraw()


func count() -> int:
	return _schools.size()


func _want() -> int:
	return clampi(int(view.world.fish / PER_SCHOOL), 0, MAX_SCHOOLS) if not _shallow.is_empty() else 0


func _clear_spot() -> Vector2:
	var best := Vector2.ZERO
	for tries in 8:
		var i := _shallow[_rng.randi_range(0, _shallow.size() - 1)]
		var c := view.world.coords(i)
		best = Iso.tile_to_local(c.x, c.y) + Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-5, 5))
		if view.plume_at(i) < 0.12:
			return best
	return best


func _mud_at(p: Vector2) -> float:
	var t := view.pick(p)
	if not view.world.in_bounds(t.x, t.y):
		return 0.0
	return view.plume_at(view.world.index(t.x, t.y))


func _process(delta: float) -> void:
	if view == null or view.world == null:
		return
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	visible = zoom >= 0.5
	if not visible:
		return
	var want := _want()
	while _schools.size() < want:
		var p := _clear_spot()
		_schools.append({"pos": p, "target": _clear_spot(), "speed": _rng.randf_range(5.0, 9.0),
			"alpha": 0.0, "phase": _rng.randf() * TAU, "leaving": false})
	if _schools.size() > want:
		for k in range(want, _schools.size()):
			_schools[k]["leaving"] = true
	var calm := UiKit.reduce_motion
	for k in range(_schools.size() - 1, -1, -1):
		var s: Dictionary = _schools[k]
		var muddy := _mud_at(s["pos"]) > 0.3
		var fade_to := 0.0 if s["leaving"] or muddy else 1.0
		s["alpha"] = move_toward(float(s["alpha"]), fade_to, delta * (1.2 if muddy else 0.6))
		if s["leaving"] and float(s["alpha"]) <= 0.0:
			_schools.remove_at(k)
			continue
		if muddy and float(s["alpha"]) <= 0.0:
			s["pos"] = _clear_spot()  # it swam off to clearer water
			s["target"] = _clear_spot()
		if calm:
			continue
		var to: Vector2 = s["target"] - s["pos"]
		if to.length() < 4.0:
			s["target"] = _clear_spot()
		else:
			s["pos"] = s["pos"] + to.normalized() * float(s["speed"]) * delta
		s["phase"] = float(s["phase"]) + delta * 3.0
	queue_redraw()


func _draw() -> void:
	for s in _schools:
		var a := float(s["alpha"])
		if a <= 0.01:
			continue
		var p: Vector2 = s["pos"]
		var head: Vector2 = (s["target"] - p).normalized() if (s["target"] - p).length() > 0.1 else Vector2.RIGHT
		var side := Vector2(-head.y, head.x)
		var ph := float(s["phase"])
		for f in FISH_PER:
			var o := Vector2(cos(f * 2.3 + ph * 0.3) * 9.0, sin(f * 1.7 + ph * 0.4) * 4.5) + head * (f % 3) * -3.0
			var c := p + o + side * sin(ph + f) * 0.9
			var col := Color(0.04, 0.17, 0.22, 0.55 * a)
			var tail := c - head * 3.4
			draw_primitive(PackedVector2Array([c + head * 4.4, c + side * 1.6, tail, c - side * 1.6]),
				PackedColorArray([col, col, col, col]), NO_UV)
			# a forked tail that flicks as it swims
			var flick := side * sin(ph * 3.0 + f) * 1.2
			draw_primitive(PackedVector2Array([tail, tail - head * 2.2 + side * 1.8 + flick, tail - head * 1.4 + flick,
				tail - head * 2.2 - side * 1.8 + flick]), PackedColorArray([col, col, col, col]), NO_UV)
