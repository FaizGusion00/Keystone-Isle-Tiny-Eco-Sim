extends TestCase
## Benchmark: ms per tick at 32x32 and 64x64 (headless). Prints results; asserts a loose budget.

const BUDGET_MS_64 := 25.0


func _bench(size: int, ticks: int) -> float:
	var sim := Simulation.create(2024, size)
	sim.run(10) # warm-up
	var t0 := Time.get_ticks_usec()
	sim.run(ticks)
	return (Time.get_ticks_usec() - t0) / 1000.0 / ticks


func test_tick_cost() -> void:
	var ms32 := _bench(32, 200)
	var ms64 := _bench(64, 100)
	print("    [perf] tick 32x32: %.3f ms   64x64: %.3f ms" % [ms32, ms64])
	assert_true(ms64 < BUDGET_MS_64, "64x64 tick %.2f ms over budget" % ms64)


func test_view_refresh_only_dirty_chunks() -> void:
	var sim := Simulation.create(2024, 32)
	var view := WorldView.new()
	view._ready()
	view.set_world(sim.world)
	assert_eq(view.refresh(), 0, "no change => no redraw")
	var t0 := Time.get_ticks_usec()
	sim.step()
	var redrawn := view.refresh()
	print("    [perf] view refresh 32x32: %.3f ms, %d/16 chunks redrawn" % [(Time.get_ticks_usec() - t0) / 1000.0, redrawn])
	view.free()
