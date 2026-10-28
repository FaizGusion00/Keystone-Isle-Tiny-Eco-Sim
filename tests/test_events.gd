extends TestCase
## Milestone 3: event recording, causal explanations, history, overlays.


func _clear_all_forest(sim: Simulation) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for y in sim.world.height:
		for x in sim.world.width:
			if sim.apply_action(Simulation.Action.CLEAR_TREES, x, y):
				ids.append(sim.events.next_id - 1)
	return ids


func test_record_and_ring_eviction() -> void:
	var log_ := EventLog.new()
	var first := log_.record(1, EventLog.Type.HEAVY_RAIN, -1, -1, 0.06)
	assert_eq(first, 0)
	assert_true(log_.has(0))
	var second := log_.record(2, EventLog.Type.EROSION, 3, 4, 0.1, first, -1, 999)
	assert_eq(log_.causes_of(second), PackedInt32Array([first]), "invalid/future causes dropped")
	assert_eq(log_.pos_of(second), Vector2i(3, 4))
	for k in EventLog.CAPACITY:
		log_.record(3 + k, EventLog.Type.DROUGHT, -1, -1, 12)
	assert_false(log_.has(first), "oldest evicted")
	assert_eq(log_.count(), EventLog.CAPACITY)
	assert_eq(log_.recent(5).size(), 5)
	assert_eq(log_.recent(1)[0], log_.next_id - 1, "recent is newest-first")


func test_explain_only_uses_recorded_causes() -> void:
	var log_ := EventLog.new()
	var cut := log_.record(0, EventLog.Type.TREES_CLEARED, 5, 5, 0.0)
	var rain := log_.record(3, EventLog.Type.HEAVY_RAIN, -1, -1, 0.07)
	var ero := log_.record(4, EventLog.Type.EROSION, 5, 5, 0.1, cut, rain)
	var mud := log_.record(6, EventLog.Type.MUDDY_WATER, 1, 1, 0.05, ero)
	var orphan := log_.record(7, EventLog.Type.EROSION, 9, 9, 0.1)
	var text := "\n".join(log_.explain(mud))
	assert_true(text.contains("Coastal water turned muddy"), text)
	assert_true(text.contains("because Day 4: Soil erosion at (5, 5)"), text)
	assert_true(text.contains("because Day 0: Trees cleared at (5, 5)"), text)
	assert_true(text.contains("(caused by your action)"), text)
	assert_true(text.contains("Heavy rain"), text)
	var orphan_text := "\n".join(log_.explain(orphan))
	assert_true(orphan_text.contains("No recorded cause."), orphan_text)
	assert_false(orphan_text.contains("because"), "never invents a cause")


func test_clearing_trees_records_action_and_links_erosion() -> void:
	var sim := Simulation.create(12345, 32)
	var cut_ids := _clear_all_forest(sim)
	assert_true(cut_ids.size() > 20)
	assert_eq(sim.events.type_of(cut_ids[0]), EventLog.Type.TREES_CLEARED)
	var p := sim.events.pos_of(cut_ids[0])
	assert_eq(sim.world.land_cause[sim.world.index(p.x, p.y)], cut_ids[0])
	sim.run(120)
	var linked := 0
	for id in sim.events.recent(EventLog.CAPACITY):
		if sim.events.type_of(id) == EventLog.Type.EROSION:
			for c in sim.events.causes_of(id):
				if sim.events.type_of(c) == EventLog.Type.TREES_CLEARED:
					assert_eq(sim.events.pos_of(c), sim.events.pos_of(id), "clearing cause is the same tile")
					linked += 1
	assert_true(linked > 0, "some erosion is explained by clearing")


func test_causes_precede_effects() -> void:
	var sim := Simulation.create(12345, 32)
	_clear_all_forest(sim)
	sim.run(200)
	var checked := 0
	for id in sim.events.recent(EventLog.CAPACITY):
		for c in sim.events.causes_of(id):
			assert_true(c < id, "cause id older")
			if sim.events.has(c):
				assert_true(sim.events.tick_of(c) <= sim.events.tick_of(id), "cause not in the future")
				checked += 1
	assert_true(checked > 0)


func test_muddy_coast_needs_clearing_and_is_explained() -> void:
	var base := Simulation.create(12345, 32)
	base.run(240)
	var cleared := Simulation.create(12345, 32)
	_clear_all_forest(cleared)
	cleared.run(240)
	var base_muddy := 0
	for id in base.events.recent(EventLog.CAPACITY):
		if base.events.type_of(id) == EventLog.Type.MUDDY_WATER:
			base_muddy += 1
	assert_eq(base_muddy, 0, "untouched island stays clear")
	var muddy := -1
	for id in cleared.events.recent(EventLog.CAPACITY):
		if cleared.events.type_of(id) == EventLog.Type.MUDDY_WATER:
			muddy = id
	assert_true(muddy >= 0, "clearing forest muddies the coast")
	var causes := cleared.events.causes_of(muddy)
	assert_true(causes.size() > 0)
	for c in causes:
		assert_eq(cleared.events.type_of(c), EventLog.Type.EROSION)
	var text := "\n".join(cleared.events.explain(muddy))
	assert_true(text.contains("Trees cleared"), text)


func test_muddy_hysteresis_no_flapping() -> void:
	var sim := Simulation.create(12345, 32)
	_clear_all_forest(sim)
	var last_type := EventLog.Type.WATER_CLEARED
	sim.run(240)
	for id in range(maxi(0, sim.events.next_id - EventLog.CAPACITY), sim.events.next_id):
		var t := sim.events.type_of(id)
		if t == EventLog.Type.MUDDY_WATER or t == EventLog.Type.WATER_CLEARED:
			assert_ne(t, last_type, "muddy/cleared alternate")
			last_type = t


func test_events_deterministic() -> void:
	var a := Simulation.create(77, 32)
	var b := Simulation.create(77, 32)
	_clear_all_forest(a)
	_clear_all_forest(b)
	a.run(150)
	b.run(150)
	assert_eq(a.events.next_id, b.events.next_id)
	assert_eq(a.state_checksum(), b.state_checksum())


func test_event_log_dict_round_trip() -> void:
	var sim := Simulation.create(12345, 32)
	_clear_all_forest(sim)
	sim.run(60)
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.events.to_dict()))
	var back := EventLog.from_dict(d)
	assert_true(back != null)
	assert_eq(back.checksum_bytes(), sim.events.checksum_bytes())
	assert_eq(EventLog.from_dict({"next_id": 3}), null, "rejects malformed data")


func test_overlay_changes_colors() -> void:
	var sim := Simulation.create(12345, 32)
	sim.run(30)
	var view := WorldView.new()
	view._ready()
	view.set_world(sim.world)
	var normal := view.tile_colors.duplicate()
	for o in [WorldView.Overlay.MOISTURE, WorldView.Overlay.VEGETATION, WorldView.Overlay.SOIL, WorldView.Overlay.WATER]:
		view.overlay = o
		assert_true(view.refresh() > 0, "overlay %d redraws" % o)
	view.overlay = WorldView.Overlay.NONE
	view.refresh()
	assert_eq(view.tile_colors, normal, "back to normal colors")
	view.free()
