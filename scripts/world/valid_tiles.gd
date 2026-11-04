class_name ValidTiles
extends RefCounted
## Where a tool can be used right now, for the placement overlay. One byte per tile:
## NO (rule says no) · OK · SHORT (allowed, but not enough labor/wood) · RISKY (allowed, on a
## floodplain). The rules come only from Simulation.tile_rule, so the overlay can never disagree
## with what a tap will do; the bounding boxes below are only speed-ups.

enum { NO, OK, SHORT, RISKY }


static func compute(sim: Simulation, action: int) -> PackedByteArray:
	var ws := sim.world
	var out := PackedByteArray()
	out.resize(ws.tile_count())
	if action == Simulation.Action.NONE:
		return out
	var box := _box(sim, action)
	var c := sim.action_cost(action)
	var short := ws.labor + 1e-6 < c.x or ws.wood + 1e-6 < c.y
	var builds := action in [Simulation.Action.BUILD_FARM, Simulation.Action.BUILD_HOUSE]
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if sim.tile_rule(action, x, y) != "":
				continue
			var i := ws.index(x, y)
			if short:
				out[i] = SHORT
			elif builds and sim.flood_risk(i) >= 2:
				out[i] = RISKY
			else:
				out[i] = OK
	return out


## Tiles worth testing for an action (everything else is certainly NO).
static func _box(sim: Simulation, action: int) -> Rect2i:
	var ws := sim.world
	var full := Rect2i(0, 0, ws.width, ws.height)
	match action:
		Simulation.Action.BUILD_FARM:
			if ws.settlement_index < 0:
				return Rect2i()
			return Rect2i(ws.coords(ws.settlement_index), Vector2i.ONE).grow(Simulation.FARM_RADIUS).intersection(full)
		Simulation.Action.BUILD_HOUSE:
			return _settlement_box(ws).grow(maxi(Simulation.HOUSE_RADIUS, 1)).intersection(full)
	return full


## Bounding box of the village centre and every house.
static func _settlement_box(ws: WorldState) -> Rect2i:
	var r := Rect2i()
	var any := false
	for i in ws.tile_count():
		var s := ws.structure[i]
		if s == WorldState.Structure.SETTLEMENT or s == WorldState.Structure.HOUSE:
			var p := ws.coords(i)
			if not any:
				r = Rect2i(p, Vector2i.ONE)
				any = true
			else:
				r = r.expand(p).expand(p + Vector2i.ONE)
	return r if any else Rect2i(0, 0, ws.width, ws.height)


static func count(mask: PackedByteArray, kind: int = OK) -> int:
	var n := 0
	for b in mask:
		if b == kind:
			n += 1
	return n
