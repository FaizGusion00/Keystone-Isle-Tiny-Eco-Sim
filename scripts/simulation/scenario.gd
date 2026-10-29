class_name Scenario
extends RefCounted
## A scenario run: objectives, deadline, fail conditions and star rating for one definition
## from ScenarioCatalog. Pure logic, evaluated deterministically at the end of every tick and
## saved with the game. Objectives *latch* once reached, except "hold" objectives, which must
## still be true when everything else is done (e.g. "keep fish above 50").

enum Status { RUNNING, WON, FAILED }

const TUTORIAL_ID := "living_island"
const V1_TUTORIAL_ID := "feed_the_village"
const TUTORIAL_SEED := 12345

var id := TUTORIAL_ID
var def: Dictionary = {}
var status: int = Status.RUNNING
var ended_tick := -1
var reason := ""
var start_tick := 0
var stars := 0
var done := PackedByteArray()  ## latched objective flags


static func tutorial() -> Scenario:
	return Scenario.from_def(ScenarioCatalog.get_def(TUTORIAL_ID))


static func from_def(d: Dictionary) -> Scenario:
	if d.is_empty():
		return null
	var s := Scenario.new()
	s.id = str(d["id"])
	s.def = d
	s.done.resize(s.objectives().size())
	return s


func objectives() -> Array:
	return def.get("objectives", [])


func is_sandbox() -> bool:
	return def.get("kind", "") == "sandbox"


func deadline() -> int:
	return int(def.get("deadline", 0))


func days_elapsed(ws: WorldState) -> int:
	return ws.tick - start_tick


func title() -> String:
	return str(def.get("title", "Island"))


## Current value of an objective/star metric.
static func metric(kind: String, ws: WorldState, sc: Scenario) -> float:
	match kind:
		"villagers": return ws.villagers
		"farms": return ws.count_structures(WorldState.Structure.FARM)
		"houses": return ws.count_structures(WorldState.Structure.HOUSE)
		"dams": return ws.count_structures(WorldState.Structure.DAM)
		"keystone": return ws.keystone
		"fish": return ws.fish
		"goats": return ws.goats
		"trees_planted": return ws.trees_planted
		"restored": return ws.land_restored
		"harvests": return ws.harvests
		"food": return ws.food_store
		"survive": return sc.days_elapsed(ws) if sc != null else ws.tick
		"clear_water": return 1.0 if not ws.coast_muddy and ws.coastal_turbidity < Simulation.MUDDY_EXIT else 0.0
		"no_loss": return 1.0 if ws.villagers_lost == 0 else 0.0
		"no_fire_loss": return 1.0 if ws.fires == 0 else 0.0
		"by_day": return sc.days_elapsed(ws) if sc != null else ws.tick
	return 0.0


static func met(o: Dictionary, ws: WorldState, sc: Scenario) -> bool:
	var k := str(o["kind"])
	var v := metric(k, ws, sc)
	if k == "by_day":
		return v <= float(o["target"])
	return v >= float(o.get("target", 1))


static func label(o: Dictionary) -> String:
	var t := int(o.get("target", 1))
	match str(o["kind"]):
		"villagers": return "Reach %d villagers" % t
		"farms": return "Have %d farm%s" % [t, "" if t == 1 else "s"]
		"houses": return "Build %d house%s" % [t, "" if t == 1 else "s"]
		"dams": return "Build %d dam%s" % [t, "" if t == 1 else "s"]
		"keystone": return "Island health %d+" % t
		"fish": return ("Keep fish above %d" if o.get("hold", false) else "Grow fish to %d") % t
		"goats": return "Keep %d+ wild goats" % t
		"trees_planted": return "Plant %d trees" % t
		"restored": return "Restore %d damaged tiles" % t
		"harvests": return "Bring in %d harvests" % t
		"food": return "Store %d food" % t
		"survive": return "Last %d days" % t
		"clear_water": return "Clear coastal water"
		"no_loss": return "No villager leaves"
		"no_fire_loss": return "No wildfires"
		"by_day": return "Finish by day %d" % t
	return str(o["kind"])


## Progress text like "8/12" for the objectives panel.
static func progress_text(o: Dictionary, ws: WorldState, sc: Scenario) -> String:
	var k := str(o["kind"])
	var v := metric(k, ws, sc)
	match k:
		"clear_water", "no_loss", "no_fire_loss":
			return "yes" if v >= 1.0 else "no"
		"by_day":
			return "day %d" % int(v)
	return "%d/%d" % [int(v), int(o.get("target", 1))]


func objective_done(k: int, ws: WorldState) -> bool:
	var o: Dictionary = objectives()[k]
	if o.get("hold", false):
		return met(o, ws, self)
	return done[k] == 1


func evaluate(ws: WorldState) -> void:
	if status != Status.RUNNING or is_sandbox():
		return
	var all := true
	var objs := objectives()
	for k in objs.size():
		var o: Dictionary = objs[k]
		if not o.get("hold", false) and done[k] == 0 and met(o, ws, self):
			done[k] = 1
		if not objective_done(k, ws):
			all = false
	if all and objs.size() > 0:
		stars = 1
		for so in def.get("stars", []):
			if met(so, ws, self):
				stars += 1
		stars = mini(stars, 3)
		if ws.relaxed:
			stars = mini(stars, 1)
		_end(ws, Status.WON, str(def.get("win_text", "You did it!")))
		return
	if ws.relaxed:
		return
	if ws.villagers <= int(def.get("fail_villagers", 0)):
		_end(ws, Status.FAILED, "Too many villagers left the island.")
	elif def.has("fail_keystone") and days_elapsed(ws) > 30 and ws.keystone < float(def["fail_keystone"]):
		_end(ws, Status.FAILED, "The island's health collapsed below %d." % int(def["fail_keystone"]))
	elif deadline() > 0 and days_elapsed(ws) >= deadline():
		_end(ws, Status.FAILED, "Day %d came before every goal was met." % deadline())


func _end(ws: WorldState, s: int, why: String) -> void:
	status = s
	ended_tick = ws.tick
	reason = why


## One-line HUD summary.
func objective_text(ws: WorldState) -> String:
	if is_sandbox():
		return "Sandbox - free play"
	match status:
		Status.WON:
			return "Complete - %d of 3 stars (day %d)" % [stars, ended_tick - start_tick]
		Status.FAILED:
			return "Failed (day %d)" % (ended_tick - start_tick)
	var objs := objectives()
	for k in objs.size():
		if not objective_done(k, ws):
			var o: Dictionary = objs[k]
			var left := ("  ·  %d days left" % (deadline() - days_elapsed(ws))) if deadline() > 0 else ""
			return "%s  (%s)%s" % [label(o), progress_text(o, ws, self), left]
	return "All goals met"


func intro_text() -> String:
	return str(def.get("intro", ""))


func to_dict() -> Dictionary:
	return {"id": id, "status": status, "ended_tick": ended_tick, "reason": reason,
		"start_tick": start_tick, "stars": stars, "done": Array(done)}


static func from_dict(d: Dictionary) -> Scenario:
	var sid := str(d.get("id", ""))
	if sid == V1_TUTORIAL_ID:
		sid = TUTORIAL_ID # v1 save: the old tutorial became "A Living Island"
	var s := Scenario.from_def(ScenarioCatalog.get_def(sid))
	if s == null:
		return null
	s.status = int(d.get("status", Status.RUNNING))
	s.ended_tick = int(d.get("ended_tick", -1))
	s.reason = str(d.get("reason", ""))
	s.start_tick = int(d.get("start_tick", 0))
	s.stars = int(d.get("stars", 1 if s.status == Status.WON else 0))
	var dn: Array = d.get("done", [])
	for k in mini(dn.size(), s.done.size()):
		s.done[k] = 1 if int(dn[k]) != 0 else 0
	return s
