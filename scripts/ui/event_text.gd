class_name EventText
extends RefCounted
## Player-facing event text, translated: plain sentences with no tile coordinates or raw indices
## ("Rain washed soil away in the north" instead of "Soil erosion at (14, 9) (3% topsoil lost)").
## EventLog.describe/explain stay as the English debug/test form; the UI uses this.

const T := EventLog.Type

## Sentence templates. "%s" = the value shown for that type (see _value).
const TITLES := {
	T.NONE: "Something happened",
	T.TREES_CLEARED: "You cut down forest",
	T.TREES_PLANTED: "You planted trees",
	T.FARM_BUILT: "You built a farm",
	T.HEAVY_RAIN: "Heavy rain",
	T.DROUGHT: "Drought: no rain for %d days",
	T.EROSION: "Rain washed soil away",
	T.MUDDY_WATER: "The coastal water turned muddy",
	T.WATER_CLEARED: "The coastal water is clear again",
	T.FISH_DECLINE: "Fish are declining (%d left)",
	T.HERBIVORE_DECLINE: "Wild goats are declining (%d left)",
	T.CROP_FAILURE: "A crop died: the soil was too dry",
	T.FOOD_SHORTAGE: "Food shortage: only %d%% of meals",
	T.WATER_SHORTAGE: "Water shortage: only %d%% of what's needed",
	T.POPULATION_GROWTH: "The village grew to %d people",
	T.POPULATION_LOSS: "Villagers left: %d remain",
	T.DROUGHT_ENDED: "The drought is over",
	T.LAND_CLEARED: "You cleared land",
	T.HOUSE_BUILT: "You built a house",
	T.DAM_BUILT: "You built a dam",
	T.LAND_RESTORED: "You restored damaged land",
	T.STRUCTURE_REMOVED: "You removed a building",
	T.DRY_SEASON: "The dry season began",
	T.WET_SEASON: "The rainy season began",
	T.WILDFIRE: "Wildfire!",
	T.FIRE_OUT: "The fire is out (%d tiles burned)",
	T.FLOOD: "Flood",
	T.HOUSING_FULL: "Every home is full - build houses",
	T.HARVEST_LOST: "A harvest was lost",
	T.LOCUSTS: "Locusts stripped %d farms",
	T.ALGAL_BLOOM: "Algal bloom: fish fell to %d",
	T.KING_TIDE: "A king tide flooded %d tiles",
	T.SPECIES_ARRIVED: "%s arrived on the island",
	T.SPECIES_LEFT: "%s left the island",
}
## Short names for lists / counts ("3 × Heavy rain").
const NAMES := {
	T.HEAVY_RAIN: "Heavy rain", T.EROSION: "Soil washed away",
}
## Where it happened matters for these (hazards on the map).
const PLACED := [T.EROSION, T.WILDFIRE, T.FLOOD, T.CROP_FAILURE, T.HARVEST_LOST, T.HEAVY_RAIN]
const PLACES := ["in the north", "in the north-east", "in the east", "in the south-east",
	"in the south", "in the south-west", "in the west", "in the north-west"]
const ROOTS := {
	"your action": "your action",
	"weather": "the weather",
	"plenty of food and water": "plenty of food and water",
	"the turning of the seasons": "the turning of the seasons",
	"every home being full - build houses": "every home being full",
	"the sea (a rare surge)": "the sea (a rare surge)",
	"a healthy habitat": "a healthy habitat",
}
const SPECIES := {1: "Wild bees", 2: "Seabirds", 4: "Tree frogs", 8: "Island wolves"}


## One event as a sentence, e.g. "Heavy rain near the village (55 mm)".
static func title(log_: EventLog, id: int, ws: WorldState = null) -> String:
	if not log_.has(id):
		return I18n.t("An older event (no longer in the history)")
	var t := log_.type_of(id)
	var v := log_.value_of(id)
	var s: String
	match t:
		T.TREES_CLEARED:
			s = I18n.f("You cut down forest (+%d wood)", int(v)) if v > 0.0 else I18n.t(TITLES[t])
		T.SPECIES_ARRIVED, T.SPECIES_LEFT:
			s = I18n.f(TITLES[t], I18n.t(SPECIES.get(int(v), "A species")))
		T.DROUGHT, T.FISH_DECLINE, T.HERBIVORE_DECLINE, T.POPULATION_GROWTH, T.POPULATION_LOSS, \
				T.FIRE_OUT, T.LOCUSTS, T.ALGAL_BLOOM, T.KING_TIDE:
			s = I18n.f(TITLES[t], int(v))
		T.FOOD_SHORTAGE, T.WATER_SHORTAGE:
			s = I18n.f(TITLES[t], roundi(v * 100.0))
		_:
			s = I18n.t(TITLES.get(t, TITLES[T.NONE]))
	if t in PLACED and ws != null:
		var place := place_of(ws, log_.pos_of(id))
		if place != "":
			s = I18n.f("%s %s", [s, place])
	match t:
		T.HEAVY_RAIN: s = I18n.f("%s (%d mm)", [s, roundi(v * 1000.0)])
		T.FLOOD: s = I18n.f("%s (%d cm deep)", [s, roundi(v * 100.0)])
	return s


## "Day 12: …"
static func line(log_: EventLog, id: int, ws: WorldState = null) -> String:
	return I18n.f("Day %d: %s", [log_.tick_of(id), title(log_, id, ws)])


static func short_name(t: int) -> String:
	return I18n.t(NAMES.get(t, EventLog.TYPE_NAMES.get(t, "Event")))


## "near the village" / "in the north-west" / "" for island-wide events.
static func place_of(ws: WorldState, p: Vector2i) -> String:
	if p.x < 0 or not ws.in_bounds(p.x, p.y):
		return ""
	if ws.settlement_index >= 0:
		var v := ws.coords(ws.settlement_index)
		if maxi(absi(p.x - v.x), absi(p.y - v.y)) <= 4:
			return I18n.t("near the village")
	# compass on screen: up = north (iso: screen x ~ x - y, screen y ~ x + y)
	var c := Vector2((ws.width - 1) * 0.5, (ws.height - 1) * 0.5)
	var d := Vector2((p.x - p.y) - (c.x - c.y), (p.x + p.y) - (c.x + c.y))
	if d.length() < ws.width * 0.3:
		return I18n.t("in the middle of the island")
	var a := fposmod(atan2(d.x, -d.y) + PI / 8.0, TAU)  # 0 = north, clockwise
	return I18n.t(PLACES[int(a / (TAU / 8.0)) % 8])


## The recorded cause chain as structured rows for the UI:
## {depth, kind: "event"|"root"|"none"|"more"|"lost", id, type, text}. Row 0 is the event itself.
static func chain(log_: EventLog, id: int, ws: WorldState = null) -> Array:
	var rows: Array = [{"depth": 0, "kind": "event", "id": id, "type": log_.type_of(id), "text": title(log_, id, ws)}]
	_chain_into(log_, id, 1, rows, ws)
	return rows


static func _chain_into(log_: EventLog, id: int, depth: int, rows: Array, ws: WorldState) -> void:
	if not log_.has(id):
		return
	var t := log_.type_of(id)
	var causes := log_.causes_of(id)
	if causes.is_empty():
		if EventLog.ROOT_KIND.has(t):
			var root := str(EventLog.ROOT_KIND[t])
			rows.append({"depth": depth, "kind": "root", "id": -1, "type": t,
				"text": I18n.f("caused by %s", I18n.t(ROOTS.get(root, root)))})
		else:
			rows.append({"depth": depth, "kind": "none", "id": -1, "type": t, "text": I18n.t("No recorded cause.")})
		return
	if depth > EventLog.MAX_DEPTH:
		rows.append({"depth": depth, "kind": "more", "id": -1, "type": t, "text": "…"})
		return
	for c in causes:
		if log_.has(c):
			rows.append({"depth": depth, "kind": "event", "id": c, "type": log_.type_of(c), "text": title(log_, c, ws)})
			_chain_into(log_, c, depth + 1, rows, ws)
		else:
			rows.append({"depth": depth, "kind": "lost", "id": -1, "type": T.NONE,
				"text": I18n.t("An older event (no longer in the history)")})


## The chain as indented text lines ("because …" before each cause), for results screens.
static func chain_lines(log_: EventLog, id: int, ws: WorldState = null) -> PackedStringArray:
	var out := PackedStringArray()
	for r in chain(log_, id, ws):
		var ind := "  ".repeat(int(r["depth"]))
		match str(r["kind"]):
			"event":
				out.append(ind + (I18n.f("because %s", lower_first(str(r["text"]))) if int(r["depth"]) > 0 else str(r["text"])))
			"root":
				out.append(ind + I18n.done("(" + str(r["text"]) + ")"))
			_:
				out.append(ind + str(r["text"]))
	return out


static func lower_first(s: String) -> String:
	return s.substr(0, 1).to_lower() + s.substr(1) if s.length() > 1 else s
