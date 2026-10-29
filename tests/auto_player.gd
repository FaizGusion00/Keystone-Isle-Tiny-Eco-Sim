extends RefCounted
## A simple, deterministic "reasonable player" used to prove every campaign scenario can be
## won with the real rules and costs. Greedy: farms for food, houses when the village is
## full, a little logging for wood, dams / tree planting / restoration when the scenario asks.

const A := Simulation.Action

var sim: Simulation
var _ring: Array[Vector2i] = []


func _init(s: Simulation) -> void:
	sim = s
	var ws := sim.world
	var c := ws.coords(ws.settlement_index)
	for r in range(1, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and ws.in_bounds(c.x + dx, c.y + dy):
					_ring.append(Vector2i(c.x + dx, c.y + dy))


func _target(kind: String) -> float:
	for o in sim.scenario.objectives():
		if o["kind"] == kind:
			return float(o.get("target", 1))
	return 0.0


func _try(action: int, max_r: int = 99, filter: Callable = Callable()) -> bool:
	var ws := sim.world
	var c := ws.coords(ws.settlement_index)
	for p in _ring:
		if maxi(absi(p.x - c.x), absi(p.y - c.y)) > max_r:
			break
		if filter.is_valid() and not filter.call(p):
			continue
		if sim.can_apply(action, p.x, p.y) == "" and sim.apply_action(action, p.x, p.y):
			return true
	return false


func act() -> void:
	var ws := sim.world
	var cost_house := sim.action_cost(A.BUILD_HOUSE)
	var cost_dam := sim.action_cost(A.BUILD_DAM)
	var farms := ws.count_structures(WorldState.Structure.FARM)
	@warning_ignore("integer_division")
	var want_farms := maxi(int(_target("farms")), 2 + ws.villagers / 3)
	if farms < want_farms:
		_try(A.BUILD_FARM)
	if ws.count_structures(WorldState.Structure.DAM) < int(_target("dams")):
		if ws.wood >= cost_dam.y:
			if not _try(A.BUILD_DAM, 8, func(p: Vector2i) -> bool: return not sim.dam_blocks_fish(p.x, p.y)):
				_try(A.BUILD_DAM, 8)
		elif ws.labor >= 2:
			_try(A.CLEAR_TREES, 99, func(p: Vector2i) -> bool: return ws.land_type[ws.index(p.x, p.y)] == LandType.FOREST)
	var houses_wanted := maxi(int(_target("houses")), 0)
	var cap := ws.housing_capacity()
	var wants_growth := _target("villagers") > cap or houses_wanted > ws.count_structures(WorldState.Structure.HOUSE)
	if wants_growth and ws.villagers >= cap - 1:
		if ws.wood >= cost_house.y:
			_try(A.BUILD_HOUSE)
		elif ws.labor >= 2:
			_try(A.CLEAR_TREES, 99, func(p: Vector2i) -> bool: return ws.land_type[ws.index(p.x, p.y)] == LandType.FOREST)
	if ws.wood < 8 and ws.labor >= 6:
		_try(A.CLEAR_TREES, 99, func(p: Vector2i) -> bool:
			return ws.land_type[ws.index(p.x, p.y)] == LandType.FOREST and sim.distance_to_settlement(p.x, p.y) > 2)
	if ws.trees_planted < int(_target("trees_planted")) or (_target("keystone") > 0 and ws.labor > 6):
		_try(A.PLANT_TREES, 99, func(p: Vector2i) -> bool:
			return sim.distance_to_settlement(p.x, p.y) > 3 and ws.vegetation_cover[ws.index(p.x, p.y)] < 0.3)
	if _target("keystone") > 0 and ws.labor > 6:
		_try(A.RESTORE_LAND)


## Plays until the scenario ends (or max_days). Returns the final status.
func play(max_days: int = 600) -> int:
	for d in max_days:
		if d % 3 == 0:
			act()
		sim.step()
		if sim.scenario.status != Scenario.Status.RUNNING:
			break
	return sim.scenario.status
