extends TestCase
## Milestone 6: scenario catalog, campaign winnability, stars & unlocks, save v2 + migration
## from v1, save slots, achievements, persistent progress and settings.

const AutoPlayer := preload("res://tests/auto_player.gd")
const KNOWN := ["villagers", "farms", "houses", "dams", "keystone", "fish", "goats", "trees_planted",
	"restored", "harvests", "food", "survive", "clear_water", "no_loss", "no_fire_loss", "by_day"]


func test_catalog_is_well_formed() -> void:
	assert_eq(ScenarioCatalog.CAMPAIGN.size(), 6)
	assert_true(ScenarioCatalog.CHALLENGES.size() >= 3 and ScenarioCatalog.CHALLENGES.size() <= 5)
	var ids := {}
	for d in ScenarioCatalog.all():
		assert_false(ids.has(d["id"]), "unique id " + d["id"])
		ids[d["id"]] = true
		for key in ["title", "blurb", "kind"]:
			assert_true(str(d.get(key, "")) != "", "%s has %s" % [d["id"], key])
		for o in d.get("objectives", []) + d.get("stars", []):
			assert_true(KNOWN.has(o["kind"]), "%s: known objective %s" % [d["id"], o["kind"]])
			assert_true(Scenario.label(o) != "", "label for " + o["kind"])
	assert_eq(ScenarioCatalog.CAMPAIGN[0]["id"], Scenario.TUTORIAL_ID)


func test_every_campaign_island_is_winnable() -> void:
	for d in ScenarioCatalog.CAMPAIGN:
		var sim := ScenarioCatalog.create_sim(d)
		var st: int = AutoPlayer.new(sim).play()
		assert_eq(st, Scenario.Status.WON, "%s: %s" % [d["id"], sim.scenario.reason])
		assert_true(sim.scenario.stars >= 1 and sim.scenario.stars <= 3, "stars in range")


func test_create_sim_is_deterministic_and_applies_setup() -> void:
	var d := ScenarioCatalog.get_def("dry_season")
	var a := ScenarioCatalog.create_sim(d)
	var b := ScenarioCatalog.create_sim(d)
	assert_eq(a.state_checksum(), b.state_checksum())
	assert_near(a.world.climate_rain, 0.6)
	assert_eq(a.world.tick, 50)
	assert_eq(a.scenario.start_tick, 50)
	assert_eq(a.scenario.days_elapsed(a.world), 0)
	var s := ScenarioCatalog.create_sim(ScenarioCatalog.SANDBOX, {"seed": 5, "size": 48, "preset": 1, "free_build": true})
	assert_eq(s.world.width, 48)
	assert_true(s.world.free_build)
	assert_true(s.scenario.is_sandbox())
	s.run(50)
	assert_eq(s.scenario.status, Scenario.Status.RUNNING, "sandbox never ends")


func test_fail_and_relaxed_mode() -> void:
	var d := ScenarioCatalog.get_def("living_island")
	var sim := ScenarioCatalog.create_sim(d)
	sim.world.villagers = int(d["fail_villagers"])
	sim.step()
	assert_eq(sim.scenario.status, Scenario.Status.FAILED)
	assert_true(sim.scenario.reason != "")
	var relaxed := ScenarioCatalog.create_sim(d, {"relaxed": true})
	relaxed.world.villagers = int(d["fail_villagers"])
	relaxed.world.food_ema = 0.0
	relaxed.run(300)
	assert_ne(relaxed.scenario.status, Scenario.Status.FAILED, "relaxed never fails")
	assert_eq(relaxed.world.villagers_lost, 0, "relaxed: nobody leaves")


func test_stars_and_hold_objectives() -> void:
	var d := ScenarioCatalog.get_def("dam_decision")
	var sim := ScenarioCatalog.create_sim(d)
	var ws := sim.world
	var sc := sim.scenario
	ws.dams_built = 1
	ws.structure[ws.settlement_index + 2] = WorldState.Structure.DAM if ws.structure[ws.settlement_index + 2] == 0 else ws.structure[ws.settlement_index + 2]
	ws.villagers = 16
	ws.fish = 30.0
	sc.evaluate(ws)
	assert_eq(sc.status, Scenario.Status.RUNNING, "fish below the hold target blocks the win")
	ws.fish = 60.0
	ws.keystone = 50.0
	sc.evaluate(ws)
	assert_eq(sc.status, Scenario.Status.WON)
	assert_eq(sc.stars, 2, "1 for winning + fish star, missed the health star")


func test_unlocks() -> void:
	var p := Progress.new()
	assert_true(p.is_unlocked("living_island"))
	assert_false(p.is_unlocked("expanding_village"))
	assert_false(p.is_unlocked("drought_year"))
	assert_true(p.is_unlocked("sandbox"))
	p.record_result("living_island", false, 0)
	assert_false(p.is_unlocked("expanding_village"), "a loss unlocks nothing")
	assert_true(p.record_result("living_island", true, 2))
	assert_true(p.is_unlocked("expanding_village"))
	assert_false(p.record_result("living_island", true, 1), "worse result keeps the best")
	assert_eq(p.best_stars("living_island"), 2)
	p.record_result("expanding_village", true, 3)
	assert_true(p.is_unlocked("drought_year"), "challenges unlock after island 2")
	assert_eq(p.total_stars(), 5)


func test_progress_and_settings_persist() -> void:
	var path := "user://test_progress.json"
	var p := Progress.load_from(path)
	p.reset()
	p.record_result("living_island", true, 3)
	assert_eq(p.grant(["first_farm", "first_farm"]), ["first_farm"])
	assert_eq(p.save(), OK)
	var q := Progress.load_from(path)
	assert_eq(q.best_stars("living_island"), 3)
	assert_eq(q.achievements, ["first_farm"])
	var sp := "user://test_settings.cfg"
	var s := GameSettings.load_from(sp)
	s.set_value("ui_scale", 1.25)
	s.set_value("reduce_motion", true)
	assert_eq(s.save(), OK)
	var t := GameSettings.load_from(sp)
	assert_near(float(t.get_value("ui_scale")), 1.25)
	assert_eq(t.get_value("reduce_motion"), true)
	assert_eq(t.get_value("haptics"), true, "defaults fill the rest")


func test_achievements() -> void:
	var sim := Simulation.create(12345, 32)
	sim.world.free_build = true
	assert_eq(Achievements.check(sim, {}, []), [])
	var c := sim.world.coords(sim.world.settlement_index)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			sim.apply_action(Simulation.Action.BUILD_FARM, c.x + dx, c.y + dy)
	var got := Achievements.check(sim, {}, [])
	assert_true(got.has("first_farm"))
	assert_false(Achievements.check(sim, {}, ["first_farm"]).has("first_farm"), "not granted twice")
	var all3 := {}
	for d in ScenarioCatalog.CAMPAIGN:
		all3[d["id"]] = 3
	var meta := Achievements.check(sim, all3, [])
	for id in ["campaign_complete", "three_stars", "all_stars"]:
		assert_true(meta.has(id), id)
	for a in Achievements.LIST:
		assert_true(FileAccess.file_exists("res://assets/icons/%s.svg" % a["icon"]), "icon for " + a["id"])


func test_v1_save_migrates() -> void:
	var r := SaveSystem.load_game("res://tests/fixtures/save_v1.json")
	assert_false(r.is_empty(), "v1 save loads")
	assert_eq(int(r["version"]), 1)
	var sim: Simulation = r["sim"]
	var ws := sim.world
	assert_eq(ws.world_seed, 12345)
	assert_eq(ws.villagers, 11)
	assert_eq(ws.tick, 60)
	assert_eq(sim.scenario.id, Scenario.TUTORIAL_ID, "old tutorial id maps to A Living Island")
	assert_eq(int(r["meta"]["speed"]), SimClock.Speed.FAST, "v1 FAST(2) -> 4x")
	assert_near(ws.labor, 10.0)
	assert_near(ws.wood, 12.0)
	assert_eq(ws.fire.count(0), ws.tile_count())
	assert_eq(ws.flood_tick[0], -1000)
	assert_true(ws.keystone > 0.0, "derived values recomputed")
	assert_eq(ws.peak_villagers, 11)
	sim.run(30)
	assert_true(ws.tick == 90 and ws.villagers > 0, "migrated game keeps running")
	# and it re-saves as v2, exactly
	var p := "user://test_saves/migrated.json"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	assert_eq(SaveSystem.save_game(sim, p, {}), OK)
	var r2 := SaveSystem.load_game(p)
	assert_eq(int(r2["version"]), SaveSystem.VERSION)
	assert_eq((r2["sim"] as Simulation).state_checksum(), sim.state_checksum())


func test_v2_rejects_missing_fields_and_newer_versions() -> void:
	var sim := Simulation.create(3, 24)
	var d := SaveSystem.to_dict(sim)
	(d["world"]["arrays"] as Dictionary).erase("reservoir")
	assert_eq(SaveSystem.from_dict(d), null, "v2 save missing a v2 array is corrupt")
	var d2 := SaveSystem.to_dict(sim)
	d2["version"] = SaveSystem.VERSION + 1
	var p := "user://test_saves/future.json"
	DirAccess.make_dir_recursive_absolute("user://test_saves")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d2))
	f.close()
	assert_true(SaveSystem.load_game(p).is_empty(), "saves from a newer game version are not loaded")


func test_save_slots_and_v1_file_migration() -> void:
	assert_eq(SaveSystem.slot_path(0), SaveSystem.DEFAULT_PATH)
	assert_eq(SaveSystem.slot_path(2), "user://saves/slot_2.json")
	var sim := ScenarioCatalog.create_sim(ScenarioCatalog.get_def("floodplain"))
	sim.run(12)
	var p := SaveSystem.slot_path(3)
	assert_eq(SaveSystem.save_game(sim, p, {"title": "The Floodplain", "day": 12, "villagers": sim.world.villagers}), OK)
	var info := SaveSystem.slot_info(p)
	assert_eq(info["title"], "The Floodplain")
	assert_eq(info["day"], 12)
	assert_eq(info["version"], SaveSystem.VERSION)
	SaveSystem.delete_all(p)
	assert_true(SaveSystem.slot_info(p).is_empty())
	# legacy single save file moves into the autosave slot
	SaveSystem.delete_all(SaveSystem.DEFAULT_PATH)
	DirAccess.copy_absolute("res://tests/fixtures/save_v1.json", SaveSystem.V1_PATH)
	assert_true(SaveSystem.migrate_v1_file())
	assert_false(FileAccess.file_exists(SaveSystem.V1_PATH))
	var r := SaveSystem.load_game(SaveSystem.DEFAULT_PATH)
	assert_eq((r["sim"] as Simulation).world.villagers, 11)
	assert_eq(int(r["meta"]["speed"]), SimClock.Speed.FAST)
	SaveSystem.delete_all(SaveSystem.DEFAULT_PATH)
