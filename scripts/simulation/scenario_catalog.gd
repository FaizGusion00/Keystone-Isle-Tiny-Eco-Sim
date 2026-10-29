class_name ScenarioCatalog
extends RefCounted
## All scenario definitions (campaign, challenges, sandbox) as plain data, plus the
## deterministic setup that turns a definition into a fresh Simulation.

const CAMPAIGN := [
	{
		"id": "living_island", "kind": "campaign", "index": 1, "title": "A Living Island",
		"blurb": "Learn the island: feed a small village with its first farm.",
		"intro": "Ten villagers have settled on this island. Everything here is connected - forests hold soil and water, clear water feeds fish, and fish feed people.\n\nBuild a farm near the village and help it grow to 12 people.",
		"win_text": "The village is thriving and the island is still healthy.",
		"seed": 12345, "size": 32, "preset": 0,
		"objectives": [{"kind": "farms", "target": 1}, {"kind": "villagers", "target": 12}],
		"deadline": 240, "fail_villagers": 6,
		"stars": [{"kind": "keystone", "target": 85}, {"kind": "by_day", "target": 150}],
	},
	{
		"id": "expanding_village", "kind": "campaign", "index": 2, "title": "The Expanding Village",
		"blurb": "Grow to 20 villagers. Homes need wood; wood needs forest.",
		"intro": "More families want to live here, but every home is full.\n\nClear some forest for wood, build houses and farms, and grow the village to 20 - without stripping the hills bare.",
		"win_text": "Twenty people now call the island home.",
		"seed": 2024, "size": 32, "preset": 0,
		"objectives": [{"kind": "houses", "target": 2}, {"kind": "villagers", "target": 20}],
		"deadline": 360, "fail_villagers": 6,
		"stars": [{"kind": "keystone", "target": 75}, {"kind": "no_loss"}],
	},
	{
		"id": "dry_season", "kind": "campaign", "index": 3, "title": "The Dry Season",
		"blurb": "A long drought is coming. Keep the village fed and watered.",
		"intro": "The rains are failing this year. Dry soil means failed crops, thirsty villagers - and dry forests can catch fire.\n\nForests keep soil moist; a dam stores water and irrigates nearby farms. Last 180 days with at least 8 harvests.",
		"win_text": "You brought the village through the drought.",
		"seed": 777, "size": 32, "preset": 2,
		"setup": {"start_tick": 50, "climate_rain": 0.6, "climate_fire": 1.5, "food": 35.0, "wood": 16.0},
		"objectives": [{"kind": "survive", "target": 180}, {"kind": "harvests", "target": 8}],
		"deadline": 0, "fail_villagers": 6,
		"stars": [{"kind": "no_fire_loss"}, {"kind": "no_loss"}],
	},
	{
		"id": "floodplain", "kind": "campaign", "index": 4, "title": "The Floodplain",
		"blurb": "Storms swell the river. Protect the farms in the valley.",
		"intro": "This village farms a river valley. Rich soil - but the rainy season brings storms, and bare slopes upstream send the water straight down.\n\nKeep forests on the slopes, build a dam to catch the peak, and bring in 10 harvests.",
		"win_text": "The valley's farms survived the storms.",
		"seed": 4096, "size": 32, "preset": 3,
		"setup": {"climate_storm": 2.2, "climate_rain": 1.15, "wood": 20.0, "labor": 14.0},
		"objectives": [{"kind": "farms", "target": 3}, {"kind": "harvests", "target": 10}],
		"deadline": 360, "fail_villagers": 6,
		"stars": [{"kind": "dams", "target": 1}, {"kind": "keystone", "target": 75}],
	},
	{
		"id": "dam_decision", "kind": "campaign", "index": 5, "title": "The Dam Decision",
		"blurb": "A dam brings water - and blocks the fish. Find the balance.",
		"intro": "A dam would give the village steady water and irrigate farms. But dams on a stream block the fish that feed the village.\n\nBuild a dam, grow to 16 villagers, and keep at least 45 fish in the sea when you're done. Big rivers are fish highways - a dam on a small stream does less harm.",
		"win_text": "Water for the village, and fish in the sea.",
		"seed": 31337, "size": 32, "preset": 0,
		"setup": {"wood": 24.0, "labor": 16.0},
		"objectives": [{"kind": "dams", "target": 1}, {"kind": "villagers", "target": 16},
			{"kind": "fish", "target": 45, "hold": true}],
		"deadline": 420, "fail_villagers": 6,
		"stars": [{"kind": "keystone", "target": 80}, {"kind": "fish", "target": 55}],
	},
	{
		"id": "recovery", "kind": "campaign", "index": 6, "title": "Recovery",
		"blurb": "Loggers stripped this island. Bring it back to life.",
		"intro": "Before you arrived, most of this island's forest was logged. The soil is washing into the sea, the water is muddy and the fish are gone.\n\nPlant trees, restore damaged land and nurse island health back up to 80.",
		"win_text": "The island is alive again.",
		"seed": 9001, "size": 32, "preset": 0,
		"setup": {"degrade": 0.75, "fish": 30.0, "goats": 10.0, "wood": 30.0, "labor": 20.0},
		"objectives": [{"kind": "trees_planted", "target": 15}, {"kind": "clear_water"}, {"kind": "keystone", "target": 80}],
		"deadline": 480, "fail_villagers": 4,
		"stars": [{"kind": "fish", "target": 60}, {"kind": "by_day", "target": 240}],
	},
]

const CHALLENGES := [
	{
		"id": "drought_year", "kind": "challenge", "index": 1, "title": "Drought Year",
		"blurb": "Almost no rain for a whole year.",
		"intro": "Rain falls at a third of the usual rate. Bring in 8 harvests and keep 8 villagers alive for 240 days.",
		"win_text": "You outlasted the drought.",
		"seed": 555, "size": 32, "preset": 2,
		"setup": {"climate_rain": 0.35, "climate_fire": 2.0, "food": 40.0},
		"objectives": [{"kind": "survive", "target": 240}, {"kind": "harvests", "target": 8},
			{"kind": "villagers", "target": 8, "hold": true}],
		"deadline": 0, "fail_villagers": 5,
		"stars": [{"kind": "villagers", "target": 10}, {"kind": "no_fire_loss"}],
	},
	{
		"id": "monsoon", "kind": "challenge", "index": 2, "title": "Monsoon",
		"blurb": "Endless storms. Farm anyway.",
		"intro": "Storms are three times as fierce. Bring in 15 harvests within 300 days.",
		"win_text": "Fifteen harvests through the storms.",
		"seed": 808, "size": 32, "preset": 1,
		"setup": {"climate_storm": 3.0, "climate_rain": 1.3, "wood": 20.0},
		"objectives": [{"kind": "harvests", "target": 15}],
		"deadline": 300, "fail_villagers": 5,
		"stars": [{"kind": "keystone", "target": 75}, {"kind": "by_day", "target": 220}],
	},
	{
		"id": "tinderbox", "kind": "challenge", "index": 3, "title": "Tinderbox",
		"blurb": "Dry forests, frequent fires. Keep the island healthy.",
		"intro": "Wildfires start four times as easily. Grow to 14 villagers and last 240 days - if island health drops below 60, you lose.",
		"win_text": "The island survived fire season.",
		"seed": 1312, "size": 32, "preset": 2,
		"setup": {"climate_fire": 4.0, "climate_rain": 0.8},
		"objectives": [{"kind": "survive", "target": 240}, {"kind": "villagers", "target": 14}],
		"deadline": 0, "fail_villagers": 5, "fail_keystone": 60,
		"stars": [{"kind": "keystone", "target": 80}, {"kind": "no_fire_loss"}],
	},
	{
		"id": "boomtown", "kind": "challenge", "index": 4, "title": "Boomtown",
		"blurb": "Thirty villagers. One small island.",
		"intro": "Grow the village to 30 people within 600 days, on a bigger, lusher island.",
		"win_text": "A bustling island town!",
		"seed": 6060, "size": 40, "preset": 1,
		"setup": {"wood": 20.0},
		"objectives": [{"kind": "villagers", "target": 30}],
		"deadline": 600, "fail_villagers": 5,
		"stars": [{"kind": "keystone", "target": 80}, {"kind": "fish", "target": 50}],
	},
]

const SANDBOX := {
	"id": "sandbox", "kind": "sandbox", "index": 0, "title": "Sandbox",
	"blurb": "Your island, your rules. No goals, no deadline.",
	"intro": "", "seed": 0, "size": 32, "preset": 0, "objectives": [],
}

const SIZES := [24, 32, 48, 64]


static func all() -> Array:
	return CAMPAIGN + CHALLENGES + [SANDBOX]


static func get_def(id: String) -> Dictionary:
	for d in all():
		if d["id"] == id:
			return d
	return {}


## Campaign entry n is unlocked once n-1 is won; challenges unlock after campaign 2.
static func is_unlocked(id: String, progress: Dictionary) -> bool:
	var d := get_def(id)
	if d.is_empty():
		return false
	var stars: Dictionary = progress.get("stars", {})
	match d["kind"]:
		"campaign":
			var idx := int(d["index"])
			return idx == 1 or int(stars.get(CAMPAIGN[idx - 2]["id"], 0)) > 0
		"challenge":
			return int(stars.get(CAMPAIGN[1]["id"], 0)) > 0
	return true


## Builds the starting simulation for a definition. `options` (New World / sandbox) may set
## seed, size, preset, relaxed, free_build. Fully deterministic.
static func create_sim(d: Dictionary, options: Dictionary = {}) -> Simulation:
	var world_seed := int(options.get("seed", d.get("seed", 0)))
	var size := int(options.get("size", d.get("size", 32)))
	var preset := int(options.get("preset", d.get("preset", 0)))
	var sim := Simulation.new(IslandGenerator.generate(world_seed, size, size, preset))
	var ws := sim.world
	var setup: Dictionary = d.get("setup", {})
	ws.villagers = int(setup.get("villagers", ws.villagers))
	ws.food_store = float(setup.get("food", ws.food_store))
	ws.wood = float(setup.get("wood", ws.wood))
	ws.labor = float(setup.get("labor", ws.labor))
	ws.fish = float(setup.get("fish", ws.fish))
	ws.goats = float(setup.get("goats", ws.goats))
	ws.climate_rain = float(setup.get("climate_rain", 1.0))
	ws.climate_storm = float(setup.get("climate_storm", 1.0))
	ws.climate_fire = float(setup.get("climate_fire", 1.0))
	ws.tick = int(setup.get("start_tick", 0))
	ws.relaxed = bool(options.get("relaxed", false))
	ws.free_build = bool(options.get("free_build", false))
	ws.peak_villagers = ws.villagers
	var degrade := float(setup.get("degrade", 0.0))
	if degrade > 0.0:
		_degrade(sim, degrade)
	sim.scenario = Scenario.from_def(d)
	sim.scenario.start_tick = ws.tick
	sim.update_derived()
	return sim


## Pre-game logging: clears a fraction of forest (and thins soil) and records it as one
## LAND_CLEARED event so the erosion it causes has a recorded cause.
static func _degrade(sim: Simulation, fraction: float) -> void:
	var ws := sim.world
	var c := ws.coords(ws.settlement_index)
	var ev := sim.events.record(ws.tick, EventLog.Type.LAND_CLEARED, c.x, c.y, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = ws.world_seed * 31 + 7
	for i in ws.tile_count():
		var t := ws.land_type[i]
		if t == LandType.FOREST and rng.randf() < fraction:
			ws.land_type[i] = LandType.LOWLAND if ws.elevation[i] < IslandGenerator.LOWLAND_MAX else LandType.GRASSLAND
			ws.vegetation_cover[i] = 0.06
			ws.soil_depth[i] *= 0.45
			ws.land_cause[i] = ev
		elif (t == LandType.GRASSLAND or t == LandType.HILLS or t == LandType.LOWLAND) and ws.structure[i] == 0:
			ws.vegetation_cover[i] *= 0.5
			ws.soil_depth[i] *= 0.8
	# the sea is already muddy from years of runoff
	for i in ws.tile_count():
		if ws.land_type[i] == LandType.SHALLOW_WATER:
			ws.sediment[i] = 0.07
	ws.coastal_turbidity = 0.07
	ws.coast_muddy = true
	ws.muddy_event = sim.events.record(ws.tick, EventLog.Type.MUDDY_WATER, -1, -1, 0.07, ev)
