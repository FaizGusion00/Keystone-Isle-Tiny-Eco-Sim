extends SceneTree
## Dev tool: prints hazard/keystone statistics for every scenario under a simple
## "do nothing" and "build a couple of farms" policy. Not part of the game.

func _initialize() -> void:
	pass

var _done := false
func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	for d in ScenarioCatalog.all():
		for policy in ["idle", "farms"]:
			var sim := ScenarioCatalog.create_sim(d)
			var ws := sim.world
			var c := ws.coords(ws.settlement_index)
			var dam_sites := 0
			for i in ws.tile_count():
				var p := ws.coords(i)
				if sim.tile_rule(Simulation.Action.BUILD_DAM, p.x, p.y) == "":
					dam_sites += 1
			if policy == "farms":
				var built := 0
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						if built < 3 and sim.apply_action(Simulation.Action.BUILD_FARM, c.x + dx, c.y + dy):
							built += 1
			var k0 := ws.keystone
			var t0 := Time.get_ticks_usec()
			var ks := []
			for n in 4:
				sim.run(90)
				ks.append("%d" % ws.keystone)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 360.0
			print("%-18s %-5s dams_ok=%3d k0=%d k=%s vill=%d peak=%d food=%d fish=%d goats=%d harv=%d fires=%d burned=%d floods=%d lost=%d status=%d %s  %.2fms" % [
				d["id"], policy, dam_sites, k0, ",".join(ks), ws.villagers, ws.peak_villagers, ws.food_store, ws.fish, ws.goats,
				ws.harvests, ws.fires, ws.fire_burned, ws.floods, ws.villagers_lost, sim.scenario.status, sim.scenario.reason.left(40), ms])
	quit()
	return true
