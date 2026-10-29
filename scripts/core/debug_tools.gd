class_name DebugTools
extends RefCounted
## Optional command-line hooks (after `--`), used for automated screenshots:
##   godot -- --select=12,14 --screenshot=/tmp/shot.png [--seed=N] [--zoom=1.5]
##            [--clear-rect=x0,y0,x1,y1] [--ticks=N] [--speed=0|1|2]
##            [--tutorial] [--restore] [--away=SECONDS]
##            [--farms=N] [--overlay=0..4] [--history[=EVENT_TYPE_NAME]]


static func handle_cmdline(main: Node) -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.is_empty():
		return
	if args.has("seed"):
		main.new_world(int(args["seed"]))
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
	if args.has("ticks"):
		main.sim.run(int(args["ticks"]))
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
		if String(args["focus"]) != "village":
			var fp: PackedStringArray = String(args["focus"]).split(",")
			fc = Vector2i(int(fp[0]), int(fp[1]))
		main.camera.position = main.world_view.position + main.world_view.top_center(fc.x, fc.y)
	if args.has("select"):
		var p: PackedStringArray = String(args["select"]).split(",")
		main.select_tile(Vector2i(int(p[0]), int(p[1])))
	if args.has("screenshot"):
		_screenshot(main, String(args["screenshot"]), int(args.get("frames", "30")))


static func _screenshot(main: Node, path: String, frames: int) -> void:
	for f in frames:
		await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := main.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("screenshot saved: ", path, " err=", err)
	main.get_tree().quit()
