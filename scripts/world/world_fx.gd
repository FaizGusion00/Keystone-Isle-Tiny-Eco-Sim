class_name WorldFx
extends Node2D
## Short animations of things changing on the map, so nothing just "swaps" in one frame:
## new buildings / trees / crops grow in with a little overshoot, felled trees tip over and
## fade, removed buildings sink and fade, with a puff of dust. While an effect runs, the tile's
## own decoration is hidden in its chunk and drawn here instead (same atlas, so it batches).
## No effects running = no processing and no drawing. Off under reduce motion, while catching
## up, at the fastest speed and for tiles off screen.

const MAX_FX := 24
const GROW := 0.30
const FALL := 0.42
const POP := 0.22

var view: WorldView
var enabled := true
var _fx: Array = []  ## {i, kind, t, dur, sprites, hide, delay}


func _ready() -> void:
	set_process(false)


func active() -> int:
	return _fx.size()


## New things on tile i grow in from their base (build, plant, a new cottage, a crop stage).
func grow(i: int, kind := "grow") -> void:
	if not _can(i):
		return
	var sprites := view.capture_index(i)
	var farm := view.world.structure[i] == WorldState.Structure.FARM
	if sprites.is_empty() and not farm:
		return
	_finish_tile(i)
	if farm and kind == "grow":
		kind = "plough"  # a new field: the furrows are drawn in, then any crop pops up
	_add({"i": i, "kind": kind, "t": 0.0, "dur": GROW if kind != "pop" else POP, "sprites": sprites, "hide": true})


## What stood on tile i before an action goes away (`sprites` captured before the change).
func fall(i: int, sprites: Array, kind := "fall") -> void:
	if not _can(i) or sprites.is_empty():
		return
	_add({"i": i, "kind": kind, "t": 0.0, "dur": FALL, "sprites": sprites, "hide": false})


func _can(i: int) -> bool:
	if not enabled or view == null or view.world == null or not is_inside_tree():
		return false
	if _fx.size() >= MAX_FX:
		_finish(_fx[0])
		_fx.remove_at(0)
	var p := view.world.coords(i)
	var sp := get_global_transform_with_canvas() * view.top_center(p.x, p.y)
	return get_viewport_rect().grow(80).has_point(sp)


func _add(f: Dictionary) -> void:
	if f["hide"]:
		view.set_fx_hide(int(f["i"]), true)
	_fx.append(f)
	set_process(true)
	queue_redraw()


## A tile that already has an effect: finish that one first (no double drawing).
func _finish_tile(i: int) -> void:
	for k in range(_fx.size() - 1, -1, -1):
		if int(_fx[k]["i"]) == i and bool(_fx[k]["hide"]):
			_finish(_fx[k])
			_fx.remove_at(k)


func _finish(f: Dictionary) -> void:
	if f["hide"]:
		view.set_fx_hide(int(f["i"]), false)


## End everything at once (a tick landed, the island changed, motion was turned off).
func finish_all() -> void:
	for f in _fx:
		_finish(f)
	_fx.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	for k in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[k]
		f["t"] = float(f["t"]) + delta
		if float(f["t"]) >= float(f["dur"]) + 0.03 * (f["sprites"] as Array).size():
			_finish(f)
			_fx.remove_at(k)
	if _fx.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for f in _fx:
		var sprites: Array = f["sprites"]
		var kind: String = f["kind"]
		if kind == "plough":
			_draw_furrows(int(f["i"]), clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0))
		var n := sprites.size()
		for k in n:
			var s: Array = sprites[k]  # [name, at, mod, scale, flip]
			var at: Vector2 = s[1]
			var mod: Color = s[2]
			var stagger := 0.03 * k if kind == "grow" else 0.0
			var u := clampf((float(f["t"]) - stagger) / float(f["dur"]), 0.0, 1.0)
			var sc := Vector2.ONE
			var rot := 0.0
			var off := Vector2.ZERO
			var a := 1.0
			match kind:
				"grow":
					var e := _back_out(u)
					sc = Vector2(e, e)
					if u <= 0.0:
						continue
				"pop":
					var e2 := 0.82 + 0.18 * _back_out(u)
					sc = Vector2(e2, e2)
				"fall":
					# trees tip away from the viewer's left/right (by sprite position), then fade
					var dir := -1.0 if (k % 2 == 0) else 1.0
					rot = dir * 1.35 * u * u
					off = Vector2(dir * 4.0 * u, 2.0 * u)
					a = 1.0 - smoothstep(0.45, 1.0, u)
				"sink":
					sc = Vector2(1.0 + 0.12 * u, 1.0 - 0.55 * u)
					a = 1.0 - smoothstep(0.3, 1.0, u)
			draw_set_transform(at + off, rot, sc)
			view.sprite(self, s[0], Vector2.ZERO, Color(mod.r, mod.g, mod.b, a), s[3], s[4])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The farm's furrows, drawn from the middle out (u = 0..1).
func _draw_furrows(i: int, u: float) -> void:
	var p := view.world.coords(i)
	var top := view.top_center(p.x, p.y)
	var furrow := Color(0.32, 0.22, 0.13, 0.35 + 0.25 * (1.0 - u))
	var e := 1.0 - pow(1.0 - u, 3.0)
	for k in range(-2, 3):
		var o := Vector2(k * 8.0, k * 4.0)
		var a := Vector2(-13, -6.5) * (1.0 - absf(k) * 0.22)
		var b := Vector2(13, 6.5) * (1.0 - absf(k) * 0.22)
		var d := clampf(e * 1.4 - absf(k) * 0.1, 0.0, 1.0)
		draw_line(top + o + a * d, top + o + b * d, furrow, 1.6)


static func _back_out(u: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var v := u - 1.0
	return 1.0 + c3 * v * v * v + c1 * v * v
