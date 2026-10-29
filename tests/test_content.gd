extends TestCase
## Long-term content: data files, seeded daily/weekly/endless islands, mutators, rare events
## and species, scores & medals, save v3 identity + migration, progress v2 (bests, XP,
## prestige, codex, cosmetics, merge) and the offline PlatformServices seam.


func _icon_ok(n: String) -> bool:
	return ResourceLoader.exists("res://assets/icons/%s.svg" % n)


func test_content_files_validate() -> void:
	var errs := ContentDB.validate()
	assert_eq(errs.size(), 0, "content errors: %s" % ", ".join(errs))
	assert_true(ContentDB.mutators().size() >= 8, "mutators loaded")
	assert_eq(ContentDB.species().size(), 4)
	var bits := {"bees": Simulation.SP_BEES, "seabirds": Simulation.SP_SEABIRDS, "frogs": Simulation.SP_FROGS,
		"wolves": Simulation.SP_WOLVES}
	for s in ContentDB.species():
		assert_eq(int(s["bit"]), int(bits[s["id"]]), "species bit matches sim: " + str(s["id"]))
		assert_eq(EventLog.SPECIES_NAMES[int(s["bit"])], str(s["title"]))
	for list in [ContentDB.mutators(), ContentDB.species(), ContentDB.rare_events()]:
		for e in list:
			assert_true(_icon_ok(str(e["icon"])), "icon exists: " + str(e["icon"]))


func test_generated_ids_are_deterministic() -> void:
	var a := ScenarioCatalog.get_def("daily_20261030")
	var b := ScenarioCatalog.get_def("daily_20261030")
	assert_eq(a, b, "same id, same def")
	assert_eq(a["kind"], "daily")
	assert_eq((a["mutators"] as Array).size(), 2)
	assert_true(str(a["title"]).contains("30 Oct 2026"), str(a["title"]))
	assert_ne(ScenarioCatalog.get_def("daily_20261031")["seed"], a["seed"], "different day, different island")
	assert_eq(ScenarioCatalog.stable_hash("daily_20261030"), int(a["seed"]))
	assert_eq(ScenarioCatalog.weekly_id({"year": 2026, "month": 10, "day": 28}), "weekly_20261026")
	assert_eq(ScenarioCatalog.weekly_id({"year": 2026, "month": 11, "day": 1}), "weekly_20261026", "Sunday ends the week")
	assert_eq(ScenarioCatalog.weekly_id({"year": 2026, "month": 11, "day": 2}), "weekly_20261102")
	assert_eq(ScenarioCatalog.daily_id({"year": 2026, "month": 1, "day": 5}), "daily_20260105")
	assert_eq((ScenarioCatalog.get_def("weekly_20261026")["mutators"] as Array).size(), 3)
	var e := ScenarioCatalog.get_def(ScenarioCatalog.endless_id(4242))
	assert_eq(int(e["seed"]), 4242)
	assert_true(bool(e["escalate"]) and (e["objectives"] as Array).is_empty())
	assert_true(ScenarioCatalog.get_def("daily_garbage").is_empty(), "bad id refused")
	assert_true(ScenarioCatalog.get_def("bogus_1").is_empty())


func test_seeded_runs_are_deterministic() -> void:
	var d := ScenarioCatalog.get_def("weekly_20261026")
	var s1 := ScenarioCatalog.create_sim(d)
	var s2 := ScenarioCatalog.create_sim(d)
	s1.run(300)
	s2.run(300)
	assert_eq(s1.world.checksum(), s2.world.checksum())
	assert_true(s1.world.rare_events, "rare events on in seeded modes")


func test_mutators_change_the_start() -> void:
	var base := {"id": "t", "kind": "sandbox", "seed": 99, "size": 24, "preset": 0, "objectives": []}
	var plain := ScenarioCatalog.create_sim(base)
	var d := base.duplicate()
	d["mutators"] = ["crowded", "fish_boom", "dry_spell", "lean_start"]
	var m := ScenarioCatalog.create_sim(d)
	assert_eq(m.world.villagers, plain.world.villagers + 4)
	assert_near(m.world.fish, 95.0)
	assert_near(m.world.climate_rain, 0.75)
	assert_near(m.world.climate_fire, 1.6)
	assert_near(m.world.food_store, maxf(plain.world.food_store - 14.0, 0.0))
	var lg := base.duplicate()
	lg["mutators"] = ["logged"]
	assert_true(ScenarioCatalog.create_sim(lg).world.coast_muddy, "logged = pre-game degradation")


func test_campaign_is_untouched_by_rare_events() -> void:
	for d in ScenarioCatalog.CAMPAIGN + ScenarioCatalog.CHALLENGES:
		var sim := ScenarioCatalog.create_sim(d)
		assert_false(sim.world.rare_events or sim.world.escalate, d["id"])


func _farm_sim() -> Simulation:
	var d := {"id": "t", "kind": "sandbox", "seed": 321, "size": 32, "preset": 2, "objectives": [], "rare_events": true}
	var sim := ScenarioCatalog.create_sim(d)
	return sim


func test_locusts_spare_farms_near_forest_and_frogs_stop_them() -> void:
	var sim := _farm_sim()
	var ws := sim.world
	var near := -1
	var far := -1
	for i in ws.tile_count():
		if ws.land_type[i] != LandType.GRASSLAND and ws.land_type[i] != LandType.LOWLAND:
			continue
		if sim._forest_within(i, 2):
			if near < 0: near = i
		elif far < 0:
			far = i
	assert_true(near >= 0 and far >= 0, "test island has both kinds of tile")
	for i in [near, far]:
		ws.structure[i] = WorldState.Structure.FARM
		ws.crop_growth[i] = 0.6
	ws.species = Simulation.SP_FROGS
	sim._locusts()
	assert_near(ws.crop_growth[far], 0.6, 1e-4, "frogs stop the swarm")
	ws.species = 0
	sim._locusts()
	assert_near(ws.crop_growth[near], 0.6, 1e-4, "farm near forest spared")
	assert_near(ws.crop_growth[far], 0.0, 1e-4, "exposed farm stripped")
	assert_eq(sim.events.type_of(ws.rare_event), EventLog.Type.LOCUSTS)
	assert_eq(ws.rare_hits, 1)
	assert_true(sim.events.explain(ws.rare_event).size() >= 1)


func test_king_tide_spares_coast_beside_forest() -> void:
	var sim := _farm_sim()
	var ws := sim.world
	var veg0 := ws.vegetation_cover.duplicate()
	sim._king_tide()
	assert_true(ws.rare_event >= 0, "this island has exposed low coast")
	assert_eq(sim.events.type_of(ws.rare_event), EventLog.Type.KING_TIDE)
	var hit := 0
	for i in ws.tile_count():
		if ws.vegetation_cover[i] != veg0[i]:
			hit += 1
			assert_false(sim._forest_within(i, 1), "tile beside forest was flooded")
	assert_true(hit > 0 and hit <= int(sim.events.value_of(ws.rare_event)), "flooded %d" % hit)


func test_bloom_cuts_fish_and_species_follow_habitat() -> void:
	var sim := _farm_sim()
	var ws := sim.world
	var f0 := ws.fish
	sim._algal_bloom()
	assert_near(ws.fish, f0 * 0.65, 1e-3)
	assert_eq(sim.events.type_of(ws.rare_event), EventLog.Type.ALGAL_BLOOM)
	ws.fish = 90.0
	ws.coastal_turbidity = 0.0
	assert_true((sim.species_supported() & Simulation.SP_SEABIRDS) != 0, "seabirds need fish + clear water")
	ws.fish = 20.0
	assert_true((sim.species_supported() & Simulation.SP_SEABIRDS) == 0)


func test_long_endless_run_sees_rare_life_and_ends_scored() -> void:
	var sim := ScenarioCatalog.create_sim(ScenarioCatalog.get_def(ScenarioCatalog.endless_id(777)))
	var storm0 := sim.world.climate_storm
	var arrivals := 0
	for k in 1500:
		sim.step()
		if sim.scenario.status != Scenario.Status.RUNNING:
			break
	for id in sim.events.recent(EventLog.CAPACITY):
		if sim.events.type_of(id) == EventLog.Type.SPECIES_ARRIVED:
			arrivals += 1
	assert_true(sim.world.species_seen != 0 or arrivals > 0, "some species settled in %d days" % sim.world.tick)
	print("    endless_777: %d days, status %d, species %d, rare hits %d, score %d" % [sim.world.tick,
		sim.scenario.status, sim.world.species_seen, sim.world.rare_hits, sim.scenario.score(sim.world)])
	if sim.world.tick >= 120:
		assert_true(sim.world.climate_storm > storm0, "endless escalates each year")
	var sc := sim.scenario
	assert_true(sc.score(sim.world) > 0)
	assert_true(sc.objective_text(sim.world).length() > 0)
	if sc.status == Scenario.Status.FAILED:
		assert_eq(sc.score(sim.world), sc.final_score, "score frozen at the end")
		assert_true(sc.stars >= 0 and sc.stars <= 3)


func test_scores_and_medals() -> void:
	var d := ScenarioCatalog.get_def("daily_20261030")
	var ws := WorldState.new(4, 4, 1)
	ws.keystone = 80.0
	ws.peak_villagers = 15
	ws.harvests = 20
	ws.species_seen = Simulation.SP_BEES | Simulation.SP_FROGS
	ws.rare_hits = 1
	var expect := int(round((240 + 6 * 80 + 12 * 15 + 3 * 20 + 40 * 2 + 25) * float(d["score_mult"])))
	assert_eq(ScenarioCatalog.score(d, ws, 240), expect)
	assert_eq(ScenarioCatalog.medal_for(d, 0), 0)
	assert_eq(ScenarioCatalog.medal_for(d, int(d["medals"][0])), 1)
	assert_eq(ScenarioCatalog.medal_for(d, int(d["medals"][0]) - 1), 0)
	assert_eq(ScenarioCatalog.medal_for(d, 99999), 3)
	# a finished daily run gives a medal instead of stars
	var sim := ScenarioCatalog.create_sim(d)
	sim.scenario.done[0] = 1
	sim.scenario.start_tick = sim.world.tick - 240
	sim.scenario.evaluate(sim.world)
	assert_eq(sim.scenario.status, Scenario.Status.WON)
	assert_eq(sim.scenario.stars, ScenarioCatalog.medal_for(d, sim.scenario.final_score))


func test_save_v3_identity_and_roundtrip() -> void:
	var sim := ScenarioCatalog.create_sim(ScenarioCatalog.get_def("daily_20261030"))
	sim.run(80)
	var d1 := SaveSystem.to_dict(sim, {"saved_at": 100.0})
	var d2 := SaveSystem.to_dict(sim, {"saved_at": 200.0})
	assert_eq(d1["version"], 3)
	assert_eq(d1["save"]["id"], d2["save"]["id"], "lineage id is stable")
	assert_eq(int(d2["save"]["revision"]), int(d1["save"]["revision"]) + 1)
	var back := SaveSystem.from_dict(JSON.parse_string(JSON.stringify(d2)))
	assert_true(back != null)
	assert_eq(back.world.checksum(), sim.world.checksum())
	assert_eq(back.scenario.id, "daily_20261030")
	assert_eq(back.scenario.def["mutators"], sim.scenario.def["mutators"], "def regenerated from id")
	assert_eq(back.save_info["id"], d2["save"]["id"])
	sim.run(50)
	back.run(50)
	assert_eq(back.world.checksum(), sim.world.checksum(), "deterministic after reload")


func test_v2_save_migrates_and_stays_deterministic() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save_v2.json"))
	assert_eq(int(d["version"]), 2)
	var sim := SaveSystem.from_dict(d)
	assert_true(sim != null, "v2 loads")
	assert_false(sim.world.rare_events)
	assert_eq(sim.world.rare_event, -1)
	assert_true(str(sim.save_info.get("id", "")).length() == 32, "v2 save gets a lineage id")
	# the fixture is dry_season after 60 ticks, written by the v2 build (commit 1ca7c0f)
	var fresh := ScenarioCatalog.create_sim(ScenarioCatalog.get_def("dry_season"))
	fresh.run(60)
	assert_eq(sim.world.checksum(), fresh.world.checksum(), "migrated state equals a v3 replay")
	sim.run(40)
	fresh.run(40)
	assert_eq(sim.world.checksum(), fresh.world.checksum())
	var newer := SaveSystem.to_dict(sim)
	newer["version"] = SaveSystem.VERSION + 1
	assert_eq(SaveSystem.from_dict(newer), null, "future version refused")


func test_save_conflict_resolution() -> void:
	var a := {"saved_at": 100.0, "save": {"id": "x", "revision": 5}}
	var b := {"saved_at": 300.0, "save": {"id": "x", "revision": 4}}
	assert_eq(SaveSystem.resolve_conflict(a, b), a, "same lineage: higher revision wins")
	var c := {"saved_at": 300.0, "save": {"id": "y", "revision": 1}}
	assert_eq(SaveSystem.resolve_conflict(a, c), c, "different lineage: newer wins")
	assert_eq(SaveSystem.resolve_conflict({}, a), a)


func test_progress_v2_migration_runs_levels_and_merge() -> void:
	var p := "user://test_progress_v1.json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "stars": {"living_island": 2}, "achievements": ["first_farm"], "games_won": 1}))
	f.close()
	var pr := Progress.load_from(p)
	assert_eq(pr.best_stars("living_island"), 2)
	assert_eq(pr.level(), 1)
	assert_true(pr.profile_id.length() == 32)
	var r := pr.record_run("daily_20261030", true, 2, 1000, 240, 2)
	assert_true(r["new_best"])
	assert_eq(int(r["xp"]), 200 + 120)
	assert_eq(pr.stars.has("daily_20261030"), false, "seeded runs keep bests, not stars")
	pr.record_result("daily_20261030", true, 2)
	assert_eq(pr.stars.has("daily_20261030"), false)
	assert_false(pr.record_run("daily_20261030", true, 1, 500, 240, 1)["new_best"], "lower score is not a best")
	assert_eq(int(pr.best("daily_20261030")["score"]), 1000)
	assert_eq(pr.level(), 2, "xp %d" % pr.xp)
	assert_eq(Progress.xp_for_level(2), 250)
	assert_eq(Progress.xp_for_level(3), 750)
	assert_eq(pr.save(), OK)
	var again := Progress.load_from(p)
	assert_eq(int(again.best("daily_20261030")["score"]), 1000)
	assert_eq(int(again.best("daily_20261030")["medal"]), 2)
	assert_eq(again.xp, pr.xp)
	assert_eq(again.profile_id, pr.profile_id)
	# merge: union / max
	var other := Progress.new()
	other.stars = {"living_island": 3, "monsoon": 1}
	other.achievements = ["first_dam"]
	other.bests = {"daily_20261030": {"score": 1500, "days": 240, "medal": 3, "at": 5.0},
		"weekly_20261026": {"score": 10, "days": 1, "medal": 0, "at": 6.0}}
	other.codex_species = Simulation.SP_WOLVES
	other.codex_events = ["LOCUSTS"]
	other.prestige = 1
	pr.merge(other)
	assert_eq(pr.best_stars("living_island"), 3)
	assert_eq(pr.best_stars("monsoon"), 1)
	assert_true(pr.achievements.has("first_farm") and pr.achievements.has("first_dam"))
	assert_eq(int(pr.best("daily_20261030")["score"]), 1500)
	assert_true(pr.bests.has("weekly_20261026"))
	assert_eq(pr.prestige, 1)
	assert_eq(pr.codex_events, ["LOCUSTS"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_prestige_and_cosmetics() -> void:
	var pr := Progress.new()
	assert_false(pr.can_prestige())
	var teal: Dictionary = ContentDB.banners()[0]
	assert_true(pr.banner_unlocked(teal))
	var coral: Dictionary = {}
	var ink: Dictionary = {}
	for b in ContentDB.banners():
		if b["id"] == "coral": coral = b
		if b["id"] == "ink": ink = b
	assert_false(pr.banner_unlocked(coral))
	pr.xp = Progress.xp_for_level(10)
	assert_eq(pr.level(), 10)
	assert_true(pr.banner_unlocked(coral))
	assert_true(pr.can_prestige())
	assert_true(pr.do_prestige())
	assert_eq(pr.level(), 1)
	assert_true(pr.banner_unlocked(coral), "level unlocks survive prestige")
	assert_true(pr.banner_unlocked(ink))
	pr.banner = "ink"
	assert_eq(pr.banner_color(), Color.html("2c4a7a"))
	pr.banner = "rose" # locked: falls back to the default
	assert_eq(pr.banner_color(), Color.html("2f7d6d"))
	var gained: int = pr.record_run("endless_5", false, 0, 100, 50, 0)["xp"]
	assert_eq(gained, int(round(20 * 1.1)), "prestige boosts XP")


func test_codex_observes_rare_events_and_species() -> void:
	var sim := _farm_sim()
	sim._algal_bloom()
	sim.world.species_seen = Simulation.SP_BEES
	var pr := Progress.new()
	var fresh := pr.observe(sim)
	assert_true(fresh.has("Algal bloom") and fresh.has("Wild bees"), str(fresh))
	assert_eq(pr.observe(sim).size(), 0, "only new entries")


func test_offline_services_are_inert() -> void:
	var s := OfflinePlatformServices.new()
	assert_eq(s.backend(), "offline")
	assert_false(s.is_online_capable() or s.is_signed_in())
	assert_eq(s.player_id(), "")
	s.sign_in()
	s.submit_score("daily_20261030", 10)
	s.cloud_push("progress", {})
	assert_false(s.is_signed_in())
	assert_eq(s.calls.size(), 3)


func test_rare_event_modes_keep_the_perf_bar() -> void:
	for size in [32, 64]:
		var d := ScenarioCatalog.get_def(ScenarioCatalog.endless_id(99)).duplicate()
		d["size"] = size
		var sim := ScenarioCatalog.create_sim(d)
		sim.run(20)
		var t0 := Time.get_ticks_usec()
		var n := 120 if size == 32 else 60
		sim.run(n)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		print("    [perf] endless (rare events on) %dx%d: %.3f ms/tick" % [size, size, ms])
		assert_true(ms < (4.0 if size == 32 else 16.0), "budget")


func test_endless_census_grows_each_year() -> void:
	var sim := ScenarioCatalog.create_sim(ScenarioCatalog.get_def(ScenarioCatalog.endless_id(5)))
	var sc := sim.scenario
	assert_eq(sc.census_target(sim.world), 6)
	sim.world.tick = sc.start_tick + 121
	assert_eq(sc.census_target(sim.world), 7)
	sim.world.tick = sc.start_tick + 240
	sim.world.villagers = 6
	sc.evaluate(sim.world)
	assert_eq(sc.status, Scenario.Status.FAILED)
	assert_true(sc.reason.contains("census"), sc.reason)
	assert_true(sc.final_score > 0)
