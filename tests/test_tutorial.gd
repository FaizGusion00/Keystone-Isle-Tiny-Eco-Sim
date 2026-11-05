extends TestCase
## The guided first island: every step waits for the player to do its thing, time only runs on
## "watch" steps, tools open one at a time, and a scripted beginner finishes it in good time.

const A := Simulation.Action


func _main() -> Node:
	DirAccess.make_dir_recursive_absolute("user://test_ui")
	var p := "user://test_ui/tutorial.json"
	SaveSystem.delete_all(p)
	var main = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	main.save_path = p
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.persistence = true
	main.settings.values["show_tutorial"] = true
	main.start_tutorial()
	return main


func _free(main: Node) -> void:
	main.get_parent().remove_child(main)
	main.free()


func _id(main: Node) -> String:
	return str(main.guide.current().get("id", "")) if main.guide.active() else ""


## Advance the island one day the way the game does.
func _day(main: Node) -> void:
	main._process(0.016)
	if main.clock.can_tick() and main.clock.speed != SimClock.Speed.PAUSED:
		main.sim.step()
		main._on_ticked(1)


func _days_until(main: Node, id_after: String, limit: int) -> int:
	var n := 0
	while _id(main) != id_after and n < limit:
		_day(main)
		n += 1
	return n


func test_a_beginner_walks_through_the_tutorial() -> void:
	var main := _main()
	var ws: WorldState = main.sim.world
	assert_eq(_id(main), "village", "starts on the map at the village (no text wall)")
	assert_eq(main.hud.popup_text(), "", "no intro popup")
	main._process(0.016)
	assert_false(main.clock.can_tick(), "time waits while the player reads")
	assert_false(main.hud.tool_available(Hud.Tool.CLEAR_TREES), "tools open one at a time")
	assert_false(main.hud.chip_available("fish"), "numbers open one at a time")
	var t0: int = ws.tick
	# 1. tap the village
	main.select_tile(ws.coords(ws.settlement_index))
	assert_eq(_id(main), "food")
	main.guide.next()
	# 2. pick Farm (only Inspect + Farm exist)
	assert_eq(_id(main), "pick_farm")
	assert_true(main.hud.tool_available(Hud.Tool.BUILD_FARM))
	main.hud.select_tool(Hud.Tool.BUILD_FARM)
	assert_eq(_id(main), "place_farm")
	assert_true(main.world_view.placement.visible, "farm tiles light up")
	var best: Vector2i = main.best_farm_tile()
	assert_true(best.x >= 0, "the guide has a farm site to point at")
	# a wrong tap does not advance
	main.try_action(A.BUILD_FARM, Vector2i(0, 0))
	assert_eq(_id(main), "place_farm")
	assert_true(main.try_action(A.BUILD_FARM, best))
	assert_eq(_id(main), "play")
	assert_eq(main.clock.speed, SimClock.Speed.PAUSED, "Play is a real choice")
	assert_eq(ws.tick, t0, "no time passed while learning to build")
	main.set_speed(SimClock.Speed.NORMAL)
	assert_eq(_id(main), "grow")
	main._process(0.016)
	assert_true(main.clock.can_tick(), "watch steps let time run")
	var d1 := _days_until(main, "harvest", 80)
	assert_eq(_id(main), "harvest", "a harvest comes (%d days)" % d1)
	main.guide.next()
	assert_eq(_id(main), "checklist")
	main.hud.explain_chip(main.hud._chips["villagers"]["panel"], "users")
	assert_eq(_id(main), "second_farm", "tapping People opens its checklist")
	main.hud.close_rule_card()
	main.hud.select_tool(Hud.Tool.BUILD_FARM)
	assert_true(main.try_action(A.BUILD_FARM, main.best_farm_tile()), "second farm")
	var d2 := _days_until(main, "goals", 200)
	assert_eq(_id(main), "goals", "the village grows (%d more days)" % d2)
	main.guide.next()
	assert_eq(_id(main), "history")
	main.guide.next()
	assert_false(main.guide.active(), "done")
	assert_true(main.hud.extra_available("history") and main.hud.chip_available("fish"))
	var total: int = ws.tick - t0
	print("    [tutorial] first harvest after %d days, growth %d days later, %d days in all" % [d1, d2, total])
	assert_true(total <= 150, "a beginner sees the loop pay off quickly (%d days)" % total)
	_free(main)


func test_saved_mid_step_resumes_the_same_step() -> void:
	var main := _main()
	var ws: WorldState = main.sim.world
	main.select_tile(ws.coords(ws.settlement_index))
	main.guide.next()
	assert_eq(_id(main), "pick_farm")
	main.autosave()
	_free(main)
	var again = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	again.save_path = "user://test_ui/tutorial.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(again)
	assert_true(again.restore_from_disk())
	assert_eq(_id(again), "pick_farm", "restored on the same step")
	assert_false(again.hud.tool_available(Hud.Tool.BUILD_HOUSE), "and with the same tools")
	_free(again)


func test_skip_opens_the_island() -> void:
	var main := _main()
	main.hud.guide_skip_requested.emit()
	assert_false(main.guide.active())
	assert_true(main.hud.tool_available(Hud.Tool.BUILD_FARM))
	main._process(0.016)
	assert_true(main.clock.can_tick(), "time runs after skipping")
	_free(main)


func test_guide_card_points_at_its_target() -> void:
	var main := _main()
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	main.hud.place_guide()
	assert_true(main.hud.guide_text().begins_with("Your village"), main.hud.guide_text())
	assert_true(main.world_view.guide_marker.visible, "a marker bounces on the village")
	var ws: WorldState = main.sim.world
	main.select_tile(ws.coords(ws.settlement_index))
	main._process(0.016)
	var ring := Rect2(main.hud._coach_ring.position, main.hud._coach_ring.size)
	var card := Rect2(main.hud._coach_card.position, main.hud._coach_card.size)
	assert_true(main.hud._coach_ring.visible and ring.size.x > 0, "the food chip is ringed")
	assert_false(card.intersects(ring.grow(-4)), "the card doesn't cover what it explains")
	assert_false(main.world_view.guide_marker.visible, "no map marker for a HUD step")
	_free(main)
