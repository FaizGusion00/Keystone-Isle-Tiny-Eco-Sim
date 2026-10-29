class_name Achievements
extends RefCounted
## Local achievements. check() is pure: it reads a simulation (and the progress record) and
## returns the ids that are now earned. Progress stores them; the UI shows a toast once.

const LIST := [
	{"id": "first_farm", "title": "First Furrow", "text": "Build your first farm.", "icon": "wheat"},
	{"id": "first_harvest", "title": "Harvest Home", "text": "Bring in a harvest.", "icon": "sprout"},
	{"id": "builder", "title": "Homemaker", "text": "Build a house.", "icon": "house"},
	{"id": "village_20", "title": "Growing Village", "text": "Reach 20 villagers.", "icon": "users"},
	{"id": "village_30", "title": "Island Town", "text": "Reach 30 villagers.", "icon": "users"},
	{"id": "reforester", "title": "Reforester", "text": "Plant 25 trees in one game.", "icon": "trees"},
	{"id": "dam_builder", "title": "Water Keeper", "text": "Build a dam.", "icon": "brick-wall"},
	{"id": "restorer", "title": "Healer of Land", "text": "Restore 10 tiles in one game.", "icon": "shovel"},
	{"id": "clear_waters", "title": "Clear Waters", "text": "Turn muddy coastal water clear again.", "icon": "waves"},
	{"id": "keystone_90", "title": "Keystone", "text": "Reach island health 90 with 15+ villagers.", "icon": "heart-pulse"},
	{"id": "fire_survivor", "title": "Through the Fire", "text": "See a wildfire burn out without losing a villager.", "icon": "flame"},
	{"id": "flood_survivor", "title": "High Water", "text": "Live through a flood.", "icon": "droplets"},
	{"id": "campaign_complete", "title": "Island Steward", "text": "Complete all six campaign islands.", "icon": "map"},
	{"id": "three_stars", "title": "Perfect Island", "text": "Earn 3 stars on any scenario.", "icon": "star"},
	{"id": "all_stars", "title": "Master Steward", "text": "Earn 3 stars on every campaign island.", "icon": "trophy"},
]


static func get_info(id: String) -> Dictionary:
	for a in LIST:
		if a["id"] == id:
			return a
	return {}


## Ids earned by the current game state (ignores ones already in `have`).
static func check(sim: Simulation, stars: Dictionary, have: Array) -> Array:
	var ws := sim.world
	var out := []
	var cond := {
		"first_farm": ws.farms_built > 0,
		"first_harvest": ws.harvests > 0,
		"builder": ws.houses_built > 0,
		"village_20": ws.villagers >= 20,
		"village_30": ws.villagers >= 30,
		"reforester": ws.trees_planted >= 25,
		"dam_builder": ws.dams_built > 0,
		"restorer": ws.land_restored >= 10,
		"clear_waters": _cleared_mud(sim),
		"keystone_90": ws.keystone >= 90.0 and ws.villagers >= 15,
		"fire_survivor": ws.fires > 0 and ws.fires_burning == 0 and ws.villagers_lost == 0,
		"flood_survivor": ws.floods > 0 and ws.villagers > 0,
		"campaign_complete": _campaign_done(stars, 1),
		"three_stars": _any_three(stars),
		"all_stars": _campaign_done(stars, 3),
	}
	for a in LIST:
		var id: String = a["id"]
		if not have.has(id) and cond.get(id, false):
			out.append(id)
	return out


## The coast recently turned clear again (a WATER_CLEARED event among the latest events).
static func _cleared_mud(sim: Simulation) -> bool:
	if sim.world.coast_muddy:
		return false
	for id in sim.events.recent(64):
		if sim.events.type_of(id) == EventLog.Type.WATER_CLEARED:
			return true
	return false


static func _campaign_done(stars: Dictionary, need: int) -> bool:
	for d in ScenarioCatalog.CAMPAIGN:
		if int(stars.get(d["id"], 0)) < need:
			return false
	return true


static func _any_three(stars: Dictionary) -> bool:
	for k in stars:
		if int(stars[k]) >= 3:
			return true
	return false
