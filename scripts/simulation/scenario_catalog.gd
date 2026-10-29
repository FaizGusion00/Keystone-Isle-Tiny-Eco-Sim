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
	if id.begins_with("daily_") or id.begins_with("weekly_") or id.begins_with("endless_"):
		return generated_def(id)
	return {}


# ------------------------------------------------------------ seeded modes (data-driven)
## Daily / Weekly / Endless islands are not stored anywhere: the whole definition (seed, island
## type, mutators, medals) is regenerated from the id, so a save only needs the id and every
## player gets the same island for the same day/week. Mode settings live in data/modes.json and
## mutators in data/mutators.json.

const MODES := ["daily", "weekly", "endless"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


## Stable 31-bit FNV-1a hash (independent of engine version / platform).
static func stable_hash(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h & 0x7FFFFFFF


static func _ymd(date: Dictionary) -> String:
	return "%04d%02d%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


## Id of the daily island for a local date dict (defaults to today).
static func daily_id(date: Dictionary = {}) -> String:
	if date.is_empty():
		date = Time.get_date_dict_from_system()
	return "daily_" + _ymd(date)


## Id of the weekly expedition: keyed by the Monday that starts the week.
static func weekly_id(date: Dictionary = {}) -> String:
	if date.is_empty():
		date = Time.get_date_dict_from_system()
	var unix := Time.get_unix_time_from_datetime_dict({"year": date["year"], "month": date["month"],
		"day": date["day"], "hour": 12, "minute": 0, "second": 0})
	var wd := int(Time.get_date_dict_from_unix_time(unix)["weekday"]) # 0 = Sunday
	var back := (wd + 6) % 7
	return "weekly_" + _ymd(Time.get_date_dict_from_unix_time(unix - back * 86400))


static func endless_id(world_seed: int) -> String:
	return "endless_%d" % absi(world_seed)


static func mode_of(id: String) -> String:
	for m in MODES:
		if id.begins_with(m + "_"):
			return m
	return ""


static func _pretty_date(ymd: String) -> String:
	if ymd.length() != 8 or not ymd.is_valid_int():
		return ymd
	var mo := clampi(int(ymd.substr(4, 2)), 1, 12)
	return "%d %s %s" % [int(ymd.substr(6, 2)), MONTHS[mo - 1], ymd.substr(0, 4)]


## Picks `count` distinct mutators with a seeded RNG (deterministic for a given seed).
## `date_key` (YYYYMMDD of the daily/weekly) limits the pool to mutators whose optional "from"
## date has arrived, so adding content never changes an island that already exists (saved
## runs, bests, players on the same day). New mutators must be appended with a future "from".
static func pick_mutators(world_seed: int, count: int, date_key := "") -> Array:
	var pool: Array = []
	for m in ContentDB.mutators():
		var from := str(m.get("from", ""))
		if from == "" or (date_key != "" and from <= date_key):
			pool.append(str(m["id"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + 17
	var out: Array = []
	while out.size() < count and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


static func generated_def(id: String) -> Dictionary:
	var mode := mode_of(id)
	var md := ContentDB.mode(mode)
	var key := id.substr(mode.length() + 1)
	if mode == "" or md.is_empty() or key == "" or not key.is_valid_int():
		return {}
	var world_seed := int(key) if mode == "endless" else stable_hash(id)
	var muts: Array = [] if mode == "endless" else pick_mutators(world_seed, int(md.get("mutators", 0)), key)
	var mult := 1.0
	for mid in muts:
		mult *= float(ContentDB.mutator(mid).get("score_mult", 1.0))
	var d := {
		"id": id, "kind": mode, "index": 0, "seed": world_seed, "size": int(md.get("size", 32)),
		"preset": world_seed % 4, "mutators": muts, "score_mult": snappedf(mult, 0.01),
		"medals": md.get("medals", [1, 2, 3]), "fail_villagers": int(md.get("fail_villagers", 5)),
		"rare_events": true, "escalate": bool(md.get("escalate", false)), "deadline": 0,
	}
	match mode:
		"daily":
			d["title"] = "%s · %s" % [md.get("title", "Daily Island"), _pretty_date(key)]
		"weekly":
			d["title"] = "%s · week of %s" % [md.get("title", "Weekly Expedition"), _pretty_date(key)]
		"endless":
			d["title"] = "%s · island %d" % [md.get("title", "Endless"), world_seed]
	if mode == "endless":
		d["objectives"] = []
		d["census"] = [int(md.get("census_start", 6)), int(md.get("census_step", 1)), int(md.get("census_max", 20))]
		d["blurb"] = "No last day. Every year the weather grows harsher and the census asks for a bigger village."
		d["intro"] = d["blurb"] + "\n\nAt the end of each year (120 days) the village must count at least %d villagers, then one more each year. Rare events and new species can appear; your score grows with every day survived." % int(md.get("census_start", 6))
		d["win_text"] = ""
	else:
		var days := int(md.get("days", 240))
		d["objectives"] = [{"kind": "survive", "target": days}]
		d["blurb"] = "Same island for everyone %s. Last %d days and score as high as you can." % [
			"today" if mode == "daily" else "this week", days]
		d["intro"] = d["blurb"] + "\n\nMutators: %s.\nRare events and new species can appear." % ", ".join(
			muts.map(func(m): return str(ContentDB.mutator(m).get("title", m))))
		d["win_text"] = "You saw the island through %d days." % days
	return d


## Score for a seeded-mode run (or any run): weights from data/modes.json x mutator multiplier.
static func score(d: Dictionary, ws: WorldState, days: int) -> int:
	var w: Dictionary = ContentDB.file("modes").get("score", {})
	var species := 0
	var b := ws.species_seen
	while b > 0:
		species += b & 1
		b >>= 1
	var raw := float(w.get("per_day", 1.0)) * days + float(w.get("keystone", 0.0)) * ws.keystone \
		+ float(w.get("peak_villagers", 0.0)) * ws.peak_villagers + float(w.get("harvests", 0.0)) * ws.harvests \
		+ float(w.get("village_growth", 0.0)) * maxi(ws.peak_villagers - IslandGenerator.START_VILLAGERS, 0) \
		+ float(w.get("species", 0.0)) * species + float(w.get("rare_survived", 0.0)) * ws.rare_hits \
		+ float(w.get("villagers_lost", 0.0)) * ws.villagers_lost
	return maxi(int(round(raw * float(d.get("score_mult", 1.0)))), 0)


## 0 = none, 1 bronze, 2 silver, 3 gold.
static func medal_for(d: Dictionary, points: int) -> int:
	var m := 0
	for t in d.get("medals", []):
		if points >= int(t):
			m += 1
	return m


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
		"daily", "weekly", "endless":
			return int(stars.get(CAMPAIGN[0]["id"], 0)) > 0
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
	var degrade := float(setup.get("degrade", 0.0))
	for mid in d.get("mutators", []):
		degrade = _apply_mutator(ws, ContentDB.mutator(str(mid)), degrade)
	ws.rare_events = bool(d.get("rare_events", false)) or bool(options.get("rare_events", false))
	ws.escalate = bool(d.get("escalate", false))
	ws.peak_villagers = ws.villagers
	if degrade > 0.0:
		_degrade(sim, degrade)
	sim.scenario = Scenario.from_def(d)
	sim.scenario.start_tick = ws.tick
	sim.update_derived()
	return sim


const _MUT_FIELDS := {"food": "food_store", "wood": "wood", "labor": "labor", "fish": "fish",
	"goats": "goats", "villagers": "villagers", "climate_rain": "climate_rain",
	"climate_storm": "climate_storm", "climate_fire": "climate_fire"}


## Applies a mutator's mul / add / set to the starting state. Returns the (possibly new) degrade.
static func _apply_mutator(ws: WorldState, m: Dictionary, degrade: float) -> float:
	for sect in ["mul", "add", "set"]:
		var ops: Dictionary = m.get(sect, {})
		for k in ops:
			var v := float(ops[k])
			if k == "degrade":
				degrade = v if sect == "set" else (degrade * v if sect == "mul" else degrade + v)
				continue
			if not _MUT_FIELDS.has(k):
				continue
			var f: String = _MUT_FIELDS[k]
			var cur := float(ws.get(f))
			var nv := cur * v if sect == "mul" else (cur + v if sect == "add" else v)
			nv = maxf(nv, 0.0)
			if f == "villagers":
				ws.villagers = maxi(int(round(nv)), 1)
			else:
				ws.set(f, nv)
	return degrade


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
