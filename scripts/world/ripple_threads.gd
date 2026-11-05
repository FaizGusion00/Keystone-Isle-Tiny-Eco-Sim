class_name RippleThreads
extends Node2D
## Keystone Isle's signature: when something happens, glowing threads run across the map from
## its recorded causes to it - the cleared hill, to the soil washing away, to the muddy coast, to
## the fish. Each link is one the simulation actually recorded (EventLog causes), so the map
## itself tells the story. Threads draw in, a spark travels cause -> effect, then they fade.
## Also previews where soil from a tile would wash to (downhill to the sea) while a tool hovers it.

const LIFE := 5.5          ## seconds a chain stays on the map
const DRAW_IN := 0.5       ## per link, staggered from the root cause outwards
const COLS := {            ## link colour by the effect's kind
	"bad": Color(0.97, 0.52, 0.35), "good": Color(0.55, 0.88, 0.55), "plain": Color(1.0, 0.82, 0.42),
}

var view: WorldView
var _links: Array = []     ## [from, to, delay, col]
var _nodes: Array = []     ## [pos, delay, col, icon_kind]
var _t := 0.0
var _hold := false         ## true while the History drawer keeps a chain on the map
var _path := PackedVector2Array()  ## downhill preview
var _path_t := 0.0


func _ready() -> void:
	set_process(false)


func showing() -> bool:
	return not _links.is_empty() or not _nodes.is_empty()


## Lay the recorded chain behind event `id` on the map. `hold` keeps it until clear().
func show_chain(log_: EventLog, id: int, hold := false) -> int:
	clear()
	if view == null or view.world == null or not log_.has(id):
		return 0
	var seen := {}
	_add_event(log_, id, 0, seen)
	if _links.is_empty() and _nodes.size() <= 1:
		_nodes.clear()
		return 0
	# root causes draw first: reverse the delays so the story reads cause -> effect
	var deepest := 0.0
	for l in _links:
		deepest = maxf(deepest, float(l[2]))
	for l in _links:
		l[2] = deepest - float(l[2])
	for nd in _nodes:
		nd[1] = maxf(0.0, deepest - float(nd[1]) + DRAW_IN * 0.5)
	_t = 0.0
	_hold = hold
	set_process(true)
	queue_redraw()
	return _links.size()


func _add_event(log_: EventLog, id: int, depth: int, seen: Dictionary) -> Vector2:
	var p := _pos_of(log_, id)
	if seen.has(id) or depth > 5:
		return p
	seen[id] = true
	var t := log_.type_of(id)
	var col: Color = COLS["bad"] if EventLog.is_bad(t) else (COLS["good"] if t in [EventLog.Type.TREES_PLANTED,
		EventLog.Type.LAND_RESTORED, EventLog.Type.WATER_CLEARED, EventLog.Type.POPULATION_GROWTH] else COLS["plain"])
	if p != Vector2.INF:
		_nodes.append([p, depth * DRAW_IN, col])
	for c in log_.causes_of(id):
		if not log_.has(c):
			continue
		var cp := _add_event(log_, c, depth + 1, seen)
		if cp != Vector2.INF and p != Vector2.INF and cp.distance_to(p) > 6.0:
			_links.append([cp, p, depth * DRAW_IN, col])
	return p


## Where an event sits on the map (island-wide events at the village).
func _pos_of(log_: EventLog, id: int) -> Vector2:
	var ws := view.world
	var q := log_.pos_of(id)
	if q.x < 0 or not ws.in_bounds(q.x, q.y):
		if ws.settlement_index < 0:
			return Vector2.INF
		q = ws.coords(ws.settlement_index)
	return view.top_center(q.x, q.y) + Vector2(0, -6)


## World rect around everything in the chain (for framing it on screen).
func bounds() -> Rect2:
	if _nodes.is_empty():
		return Rect2()
	var r := Rect2(_nodes[0][0], Vector2.ZERO)
	for nd in _nodes:
		r = r.expand(nd[0])
	return r.grow(40.0)


func clear() -> void:
	_links.clear()
	_nodes.clear()
	_hold = false
	if _path.is_empty():
		set_process(false)
	queue_redraw()


## Downhill route from tile t to the sea (where its soil would go), or nothing.
func preview_runoff(t: Vector2i) -> void:
	_path = PackedVector2Array()
	if view != null and view.world != null and view.world.in_bounds(t.x, t.y):
		var ws := view.world
		var i := ws.index(t.x, t.y)
		var guard := 0
		while i >= 0 and guard < 64:
			var c := ws.coords(i)
			_path.append(view.top_center(c.x, c.y) + Vector2(0, -2))
			if LandType.is_water(ws.land_type[i]):
				break
			i = view.down[i] if i < view.down.size() else -1
			guard += 1
		if _path.size() < 2:
			_path = PackedVector2Array()
	_path_t = 0.0
	set_process(not _path.is_empty() or showing())
	queue_redraw()


func runoff_points() -> int:
	return _path.size()


func _process(delta: float) -> void:
	_t += delta
	_path_t += delta
	if not _hold and showing() and _t > LIFE + _max_delay():
		_links.clear()
		_nodes.clear()
	if not showing() and _path.is_empty():
		set_process(false)
	queue_redraw()


func _max_delay() -> float:
	var m := 0.0
	for l in _links:
		m = maxf(m, float(l[2]))
	return m


func _draw() -> void:
	var calm := UiKit.reduce_motion
	var fade := 1.0 if _hold else clampf((LIFE + _max_delay() - _t) / 1.2, 0.0, 1.0)
	for l in _links:
		var a: Vector2 = l[0]
		var b: Vector2 = l[1]
		var col: Color = l[3]
		var u := 1.0 if calm else clampf((_t - float(l[2])) / DRAW_IN, 0.0, 1.0)
		if u <= 0.0:
			continue
		var mid := (a + b) * 0.5 + Vector2(0, -clampf(a.distance_to(b) * 0.35, 18.0, 90.0))
		var pts := PackedVector2Array()
		var n := 18
		for k in int(n * u) + 1:
			var s := float(k) / n
			pts.append(a.lerp(mid, s).lerp(mid.lerp(b, s), s))
		if pts.size() >= 2:
			draw_polyline(pts, Color(col, 0.22 * fade), 7.0, true)
			draw_polyline(pts, Color(col.lightened(0.2), 0.95 * fade), 2.2, true)
		if u >= 1.0 and not calm:
			# a spark runs along the thread, cause -> effect
			var s2 := fposmod((_t - float(l[2])) * 0.7, 1.0)
			var sp := a.lerp(mid, s2).lerp(mid.lerp(b, s2), s2)
			draw_circle(sp, 3.4, Color(1, 1, 0.9, 0.9 * fade))
			draw_circle(sp, 6.5, Color(col, 0.25 * fade))
	for nd in _nodes:
		var p: Vector2 = nd[0]
		var col2: Color = nd[2]
		var v := 1.0 if calm else clampf((_t - float(nd[1])) / 0.3, 0.0, 1.0)
		if v <= 0.0:
			continue
		var pulse := 1.0 if calm else 1.0 + 0.15 * sin(_t * 5.0)
		draw_circle(p, 9.0 * v * pulse, Color(col2, 0.22 * fade))
		draw_arc(p, 7.0 * v, 0.0, TAU, 20, Color(col2.lightened(0.25), 0.95 * fade), 2.0, true)
		draw_circle(p, 2.6 * v, Color(1, 1, 0.95, fade))
	if _path.size() >= 2:
		# runoff preview: brown dashes flowing downhill, ending in a little splash at the water
		var mudc := Color(0.62, 0.45, 0.26, 0.9)
		var total := 0.0
		for k in _path.size() - 1:
			total += _path[k].distance_to(_path[k + 1])
		var off := 0.0 if calm else fposmod(_path_t * 22.0, 12.0)
		var dist := 0.0
		for k in _path.size() - 1:
			var a2 := _path[k]
			var b2 := _path[k + 1]
			var seg := a2.distance_to(b2)
			var d := -off
			while d < seg:
				var s0 := clampf(d / seg, 0.0, 1.0)
				var s1 := clampf((d + 6.0) / seg, 0.0, 1.0)
				if s1 > s0:
					draw_line(a2.lerp(b2, s0), a2.lerp(b2, s1), mudc, 2.4, true)
				d += 12.0
			dist += seg
		var end := _path[_path.size() - 1]
		var r := 6.0 + (0.0 if calm else 3.0 * sin(_path_t * 4.0))
		draw_arc(end, r, 0.0, TAU, 18, Color(0.62, 0.45, 0.26, 0.8), 2.0, true)
