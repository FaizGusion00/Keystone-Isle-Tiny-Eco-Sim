extends SceneTree
## Compare idle vs a simple "steward" policy on seeded modes.
func steward(sim: Simulation) -> void:
	var ws := sim.world
	var c := ws.coords(ws.settlement_index)
	# 1) enough farms for the village, off the floodplain, near the village
	var farms := ws.count_structures(WorldState.Structure.FARM)
	var want := 2 + ws.villagers / 4
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := c.x + dx
				var y := c.y + dy
				if farms >= want or not ws.in_bounds(x, y) or sim.flood_risk(ws.index(x, y)) == 2:
					continue
				if sim.apply_action(Simulation.Action.BUILD_FARM, x, y):
					farms += 1
	# 2) a house when food is comfortable (clear one forest tile for wood if needed)
	if ws.food_store > 25.0 and ws.villagers >= ws.housing_capacity() - 1:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if sim.apply_action(Simulation.Action.BUILD_HOUSE, c.x + dx, c.y + dy):
					return
		for r in range(4, 9):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var x := c.x + dx
					var y := c.y + dy
					if ws.in_bounds(x, y) and ws.land_type[ws.index(x, y)] == LandType.FOREST \
							and sim.apply_action(Simulation.Action.CLEAR_TREES, x, y):
						return
	# 3) spare labor: restore bare land, then forest bare hills
	for i in ws.tile_count():
		var p := ws.coords(i)
		sim.apply_action(Simulation.Action.RESTORE_LAND, p.x, p.y)
	for i in ws.tile_count():
		var p := ws.coords(i)
		if ws.land_type[i] == LandType.HILLS and ws.vegetation_cover[i] < 0.3:
			sim.apply_action(Simulation.Action.PLANT_TREES, p.x, p.y)


func play(id: String, active: bool, max_days := 2400) -> Array:
	var sim := ScenarioCatalog.create_sim(ScenarioCatalog.generated_def(id))
	while sim.scenario.status == Scenario.Status.RUNNING and sim.scenario.days_elapsed(sim.world) < max_days:
		if active and sim.world.tick % 20 == 0: steward(sim)
		sim.step()
	return [sim.scenario.score(sim.world), sim.scenario.stars, sim.scenario.days_elapsed(sim.world), sim.world.peak_villagers, sim.world.harvests, roundi(sim.world.keystone)]

func _initialize() -> void:
	for mode in ["daily", "weekly", "endless"]:
		for active in [false, true]:
			var res := []
			for k in 10:
				var id := "daily_202611%02d" % (k + 1) if mode == "daily" else ("weekly_2026%02d02" % (k + 1) if mode == "weekly" else "endless_%d" % (k + 1))
				if mode == "weekly" and ScenarioCatalog.generated_def(id).is_empty(): continue
				res.append(play(id, active))
			var sc := res.map(func(r): return r[0]); sc.sort()
			var med := [0,0,0,0]
			for r in res: med[r[1]] += 1
			print("%s %s scores %s medals %s days %s peak %s harv %s ks %s" % [mode, "steward" if active else "idle", sc, med, res.map(func(r): return r[2]), res.map(func(r): return r[3]), res.map(func(r): return r[4]), res.map(func(r): return r[5])])
	quit()
