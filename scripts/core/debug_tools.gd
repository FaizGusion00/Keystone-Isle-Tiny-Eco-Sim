class_name DebugTools
extends RefCounted
## Optional command-line hooks (after `--`), used for automated screenshots:
##   godot -- --select=12,14 --screenshot=/tmp/shot.png [--seed=N] [--zoom=1.5]
##            [--clear-rect=x0,y0,x1,y1] [--ticks=N] [--speed=0|1|2]
##            [--tutorial] [--restore] [--away=SECONDS]
##            [--farms=N] [--farms-at=x,y;x,y] [--dams=N] [--until=EVENT_TYPE_NAME] [--no-results] [--overlay=0..4] [--history[=EVENT_TYPE_NAME]]
##            [--focus=village|dam|event|x,y] [--select=village|dam|event|x,y]  (dam = last --dams tile, event = the --until hit)
##            [--perf=FRAMES]  (render FRAMES frames while the sim plays, print frame/render timings, quit)


static func handle_cmdline(main: Node) -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.is_empty():
		return
	if args.has("seed"):
		main.new_world(int(args["seed"]))
	if args.has("zoom") or args.has("focus"):
		main.camera.user_moved = true  # an explicit framing wins over the automatic island fit
	if args.has("zoom"):
		var z := float(args["zoom"])
		main.camera.zoom = Vector2(z, z)
	if args.has("clear-rect"):
		var r: PackedStringArray = String(args["clear-rect"]).split(",")
		for y in range(int(r[1]), int(r[3]) + 1):
			for x in range(int(r[0]), int(r[2]) + 1):
				main.sim.apply_action(Simulation.Action.CLEAR_TREES, x, y)
	if args.has("farms"):
		# --farms=N : build up to N farms next to the village (for screenshots/tests)
		var c: Vector2i = main.sim.world.coords(main.sim.world.settlement_index)
		var left := int(args["farms"])
		for r in range(1, Simulation.FARM_RADIUS + 1):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if left > 0 and main.sim.apply_action(Simulation.Action.BUILD_FARM, c.x + dx, c.y + dy):
						left -= 1
	if args.has("farms-at"):
		# --farms-at=x,y;x,y : build farms on exact tiles (e.g. low river banks, to stage a flood)
		for pair in String(args["farms-at"]).split(";"):
			var fp2 := pair.split(",")
			if fp2.size() == 2:
				main.sim.apply_action(Simulation.Action.BUILD_FARM, int(fp2[0]), int(fp2[1]))
	var marks := {}  # named tiles for --focus / --select: "dam", "event"
	if args.has("dams"):
		# --dams=N : build up to N dams on the river tiles closest to the village
		var vc: Vector2i = main.sim.world.coords(main.sim.world.settlement_index)
		var spots: Array = []
		for y in main.sim.world.height:
			for x in main.sim.world.width:
				if main.sim.tile_rule(Simulation.Action.BUILD_DAM, x, y) == "":
					spots.append(Vector2i(x, y))
		spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(vc) < b.distance_squared_to(vc))
		var n := int(args["dams"])
		main.sim.world.wood += 12.0 * n  # screenshot helper: pay for the dams
		main.sim.world.labor += 8.0 * n
		for sp in spots:
			if n <= 0:
				break
			if main.sim.apply_action(Simulation.Action.BUILD_DAM, sp.x, sp.y):
				n -= 1
				marks["dam"] = sp
	if args.has("ticks") or args.has("until"):
		main.sim.run(int(args.get("ticks", "0")))
		if args.has("until"):
			# --until=EVENT_TYPE : keep running (max 2000 ticks) until that event is recorded
			var want: int = EventLog.Type.get(String(args["until"]), -1)
			var start: int = main.sim.events.recent(1)[0] if main.sim.events.recent(1).size() > 0 else -1
			for i in 2000:
				main.sim.step()
				var hit := false
				for id in main.sim.events.recent(8):
					if id > start and main.sim.events.type_of(id) == want:
						hit = true
						marks["event"] = main.sim.events.pos_of(id)
				if hit:
					print("until: hit ", args["until"], " at tick ", main.sim.world.tick, " tile ", marks["event"])
					break
		if args.has("no-results") and main.sim.scenario != null:
			main._scenario_status = main.sim.scenario.status  # keep the results sheet closed for gameplay shots
		main.world_view.refresh()
		main.hud.set_day(main.sim.world.tick)
		main.hud.set_status(main.sim.world)
		main.ambience.update_from_world(true)
	if args.has("away"):
		# simulate leaving the app for N seconds: suspend → (time passes) → resume → catch-up
		main.hud.clear_popups() # the player dismissed the intro before leaving
		main.suspend()
		main._suspended_at -= float(args["away"])
		main.resume()
		if main.catch_up != null:
			main.catch_up.run_all()
			main._finish_catch_up(true)
	if args.has("speed"):
		main.set_speed(int(args["speed"]))
	if args.has("overlay"):
		main.world_view.set_overlay(int(args["overlay"]))
		main.hud.set_overlay_name(WorldView.OVERLAY_NAMES[int(args["overlay"])])
	if args.has("history"):
		var sel := -1
		var tname := String(args["history"])
		if tname != "" and EventLog.Type.has(tname):
			for id in main.sim.events.recent(EventLog.CAPACITY):
				if main.sim.events.type_of(id) == EventLog.Type[tname]:
					sel = id
					break
		main.hud.show_events(main.sim.events, sel)
	if args.has("focus"):
		var fc: Vector2i = main.sim.world.coords(main.sim.world.settlement_index)
		if marks.has(String(args["focus"])):
			fc = marks[String(args["focus"])]
		elif String(args["focus"]).contains(","):
			var fp: PackedStringArray = String(args["focus"]).split(",")
			fc = Vector2i(int(fp[0]), int(fp[1]))
		main.camera.position = main.world_view.position + main.world_view.top_center(fc.x, fc.y)
	if args.has("select"):
		var st: Vector2i = main.sim.world.coords(main.sim.world.settlement_index)
		if marks.has(String(args["select"])):
			st = marks[String(args["select"])]
		elif String(args["select"]).contains(","):
			var p: PackedStringArray = String(args["select"]).split(",")
			st = Vector2i(int(p[0]), int(p[1]))
		main.select_tile(st)
	if args.has("perf"):
		_perf(main, int(args["perf"]))
	elif args.has("screenshot"):
		_screenshot(main, String(args["screenshot"]), int(args.get("frames", "30")))


## Frame timing on a real renderer (run under a display, e.g. xvfb; the headless driver draws
## nothing). Reports wall-clock frame time and the viewport's measured CPU/GPU
## render time as median and 95th percentile, skipping the first 60 warm-up frames.
static func _perf(main: Node, frames: int) -> void:
	var vp: RID = main.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var wall: Array[float] = []
	var rcpu: Array[float] = []
	var rgpu: Array[float] = []
	for f in 60:
		await main.get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var tick0: int = main.sim.world.tick
	for f in frames:
		await main.get_tree().process_frame
		var t := Time.get_ticks_usec()
		wall.append((t - t0) / 1000.0)
		t0 = t
		rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		rgpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	var line := "perf: %d frames  %dx%d tiles  sim ticks %d  draw calls %d  |" % [frames, main.sim.world.width,
		main.sim.world.height, main.sim.world.tick - tick0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
	for pair in [["frame", wall], ["render_cpu", rcpu], ["render_gpu", rgpu]]:
		var a: Array[float] = pair[1]
		a.sort()
		line += "  %s med %.2f p95 %.2f ms" % [pair[0], a[a.size() / 2], a[int(a.size() * 0.95)]]
	print(line)
	main.quit_game()


static func _screenshot(main: Node, path: String, frames: int) -> void:
	for f in frames:
		await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("screenshot saved: ", path, " err=", err)
	main.quit_game()
