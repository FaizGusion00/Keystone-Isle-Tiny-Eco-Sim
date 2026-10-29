class_name CameraController
extends Camera2D
## Pan/zoom for mouse (drag + wheel), keyboard (arrows / +,-) and touch (drag + pinch).
## A press+release without moving past TAP_SLOP emits tile_tapped(screen_pos).

signal tile_tapped(screen_pos: Vector2)

const MIN_ZOOM := 0.35
const MAX_ZOOM := 4.0
const TAP_SLOP := 14.0
const KEY_PAN_SPEED := 700.0

var bounds := Rect2(-512, -16, 1024, 512)

var _mouse_down := false
var _mouse_dragged := false
var _press_pos := Vector2.ZERO
var _touches := {}
var _touch_dragged := false
var _pinch_dist := 0.0
var _pinch_zoom := 1.0
var input_enabled := true      ## false while a full-screen menu is open
var smooth := true             ## eased wheel/key zoom and glides (off with reduce motion)
var _zoom_target := 0.0        ## 0 = no zoom animation running
var _zoom_anchor := Vector2.ZERO
var _glide_to := Vector2.INF


func set_bounds(r: Rect2) -> void:
	bounds = r
	position = r.get_center()
	fit_to(r)
	_clamp()


## Zoom so the whole rect is visible (used for a new island).
func fit_to(r: Rect2) -> void:
	var vs := get_viewport_rect().size
	if r.size.x <= 0.0 or r.size.y <= 0.0 or vs.x <= 0.0:
		return
	var z := clampf(minf(vs.x / r.size.x, (vs.y - 120.0) / r.size.y) * 0.95, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)


## Eases the camera to a world position (and optionally a zoom level).
func glide_to(world_pos: Vector2, z := 0.0) -> void:
	if not smooth:
		position = world_pos
		if z > 0.0:
			zoom = Vector2(z, z)
		_clamp()
		return
	_glide_to = world_pos
	if z > 0.0:
		_zoom_target = clampf(z, MIN_ZOOM, MAX_ZOOM)
		_zoom_anchor = Vector2.INF


## Eased zoom toward screen_pos (wheel / keys). Falls back to zoom_at without smoothing.
func zoom_smooth(screen_pos: Vector2, factor: float) -> void:
	if not smooth:
		zoom_at(screen_pos, factor)
		return
	var base := _zoom_target if _zoom_target > 0.0 else zoom.x
	_zoom_target = clampf(base * factor, MIN_ZOOM, MAX_ZOOM)
	_zoom_anchor = screen_pos


func _process(delta: float) -> void:
	if _zoom_target > 0.0:
		var k := 1.0 - exp(-14.0 * delta)
		var nz := lerpf(zoom.x, _zoom_target, k)
		if absf(nz - _zoom_target) < 0.002:
			nz = _zoom_target
		if _zoom_anchor == Vector2.INF:
			zoom = Vector2(nz, nz)
		else:
			zoom_at(_zoom_anchor, nz / zoom.x)
		if nz == _zoom_target:
			_zoom_target = 0.0
	if _glide_to != Vector2.INF:
		position = position.lerp(_glide_to, 1.0 - exp(-6.0 * delta))
		if position.distance_to(_glide_to) < 0.5:
			position = _glide_to
			_glide_to = Vector2.INF
		_clamp()
	if not input_enabled:
		return
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dir != Vector2.ZERO:
		position += dir * KEY_PAN_SPEED * delta / zoom.x
		_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton or event is InputEventScreenDrag:
		_glide_to = Vector2.INF
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return # touch is handled via ScreenTouch/ScreenDrag
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_smooth(mb.position, 1.12)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_smooth(mb.position, 1.0 / 1.12)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_mouse_down = true
				_mouse_dragged = false
				_press_pos = mb.position
			else:
				if mb.button_index == MOUSE_BUTTON_LEFT and _mouse_down and not _mouse_dragged:
					tile_tapped.emit(mb.position)
				_mouse_down = false
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION or not _mouse_down:
			return
		var mm := event as InputEventMouseMotion
		if not _mouse_dragged and mm.position.distance_to(_press_pos) > TAP_SLOP:
			_mouse_dragged = true
		if _mouse_dragged:
			position -= mm.relative / zoom.x
			_clamp()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_touch_dragged = false
				_press_pos = st.position
			elif _touches.size() == 2:
				_touch_dragged = true
				_start_pinch()
		else:
			if _touches.size() == 1 and not _touch_dragged and st.position.distance_to(_press_pos) <= TAP_SLOP:
				tile_tapped.emit(st.position)
			_touches.erase(st.index)
			if _touches.size() == 2:
				_start_pinch()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			if not _touch_dragged and sd.position.distance_to(_press_pos) > TAP_SLOP:
				_touch_dragged = true
			if _touch_dragged:
				position -= sd.relative / zoom.x
				_clamp()
		elif _touches.size() >= 2 and _pinch_dist > 0.0:
			var pts: Array = _touches.values()
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[1]
			_zoom_target = 0.0
			var target := clampf(_pinch_zoom * a.distance_to(b) / _pinch_dist, MIN_ZOOM, MAX_ZOOM)
			zoom_at((a + b) * 0.5, target / zoom.x)
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			zoom_smooth(get_viewport_rect().size * 0.5, 1.15)
		elif k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			zoom_smooth(get_viewport_rect().size * 0.5, 1.0 / 1.15)


func _start_pinch() -> void:
	var pts: Array = _touches.values()
	_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
	_pinch_zoom = zoom.x


## Screen (viewport) position -> world position, independent of the cached canvas transform.
func screen_to_world(p: Vector2) -> Vector2:
	return position + (p - get_viewport_rect().size * 0.5) / zoom.x


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pos)
	var z := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	position += before - screen_to_world(screen_pos)
	_clamp()


func _clamp() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.y = clampf(position.y, bounds.position.y, bounds.end.y)
