class_name Scenario
extends RefCounted
## Tutorial scenario "Feed the Village": grow the village with farms before the deadline.
## Pure logic, evaluated deterministically at the end of every tick and saved with the game.

enum Status { RUNNING, WON, FAILED }

const TUTORIAL_ID := "feed_the_village"
const TUTORIAL_SEED := 12345

var id := TUTORIAL_ID
var goal_villagers := 12
var min_farms := 1
var deadline := 240
var fail_villagers := 6
var status: int = Status.RUNNING
var ended_tick := -1
var reason := ""


static func tutorial() -> Scenario:
	return Scenario.new()


func evaluate(ws: WorldState) -> void:
	if status != Status.RUNNING:
		return
	if ws.villagers >= goal_villagers and ws.count_structures(WorldState.Structure.FARM) >= min_farms:
		_end(ws, Status.WON, "The village has grown to %d people." % ws.villagers)
	elif ws.villagers <= fail_villagers:
		_end(ws, Status.FAILED, "Too many villagers left the island.")
	elif ws.tick >= deadline:
		_end(ws, Status.FAILED, "Day %d came and the village had only %d people." % [deadline, ws.villagers])


func _end(ws: WorldState, s: int, why: String) -> void:
	status = s
	ended_tick = ws.tick
	reason = why


func title() -> String:
	return "Feed the Village"


func objective_text(ws: WorldState) -> String:
	match status:
		Status.WON:
			return "Goal complete! (day %d)" % ended_tick
		Status.FAILED:
			return "Goal failed (day %d)" % ended_tick
	var farms := ws.count_structures(WorldState.Structure.FARM)
	return "Goal: %d villagers with a farm by day %d   (%d/%d, farms %d)" % [
		goal_villagers, deadline, ws.villagers, goal_villagers, farms]


func intro_text() -> String:
	return ("Your village needs more food to grow.\n\n" +
		"• Build at least %d farm next to the village (lowland or grassland, clear trees first).\n" +
		"• Reach %d villagers before day %d.\n" +
		"• Careful: bare soil erodes, muddy water drives fish away, and hungry villagers leave.\n\n" +
		"Tap History or Why? to see what caused what.") % [min_farms, goal_villagers, deadline]


func to_dict() -> Dictionary:
	return {"id": id, "status": status, "ended_tick": ended_tick, "reason": reason}


static func from_dict(d: Dictionary) -> Scenario:
	if str(d.get("id", "")) != TUTORIAL_ID:
		return null
	var s := Scenario.tutorial()
	s.status = int(d.get("status", Status.RUNNING))
	s.ended_tick = int(d.get("ended_tick", -1))
	s.reason = str(d.get("reason", ""))
	return s
