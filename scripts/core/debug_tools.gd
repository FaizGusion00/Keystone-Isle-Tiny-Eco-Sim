class_name DebugTools
extends RefCounted
## Optional command-line hooks (after `--`), used for automated screenshots:
##   godot -- --select=12,14 --screenshot=/tmp/shot.png [--seed=N] [--zoom=1.5]
##            [--clear-rect=x0,y0,x1,y1] [--ticks=N] [--speed=0|1|2]


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
	if args.has("ticks"):
		main.sim.run(int(args["ticks"]))
		main.world_view.refresh()
		main.hud.set_day(main.sim.world.tick)
	if args.has("speed"):
		main.set_speed(int(args["speed"]))
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
