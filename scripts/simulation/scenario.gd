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
const MEDAL_NAMES := ["no medal", "bronze", "silver", "gold"]

var id := TUTORIAL_ID
var def: Dictionary = {}
var status: int = Status.RUNNING
var ended_tick := -1
var reason := ""
var start_tick := 0
var stars := 0       ## campaign/challenge: 1-3 stars. Daily/weekly/endless: medal 0-3
var final_score := 0 ## daily/weekly/endless: score when the run ended
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


func kind() -> String:
	return str(def.get("kind", ""))


## Daily / weekly / endless: scored runs with medals instead of stars.
func is_scored() -> bool:
	return kind() in ScenarioCatalog.MODES


func is_endless() -> bool:
	return kind() == "endless"


func score(ws: WorldState) -> int:
	if status != Status.RUNNING and is_scored():
		return final_score
	return ScenarioCatalog.score(def, ws, days_elapsed(ws))


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
		"villagers": return I18n.t("Reach %d villagers") % t
		"farms": return I18n.t("Have 1 farm") if t == 1 else I18n.f("Have %d farms", t)
		"houses": return I18n.t("Build 1 house") if t == 1 else I18n.f("Build %d houses", t)
		"dams": return I18n.t("Build 1 dam") if t == 1 else I18n.f("Build %d dams", t)
		"keystone": return I18n.t("Island health %d+") % t
		"fish": return I18n.f("Keep fish above %d" if o.get("hold", false) else "Grow fish to %d", t)
		"goats": return I18n.t("Keep %d+ wild goats") % t
		"trees_planted": return I18n.t("Plant %d trees") % t
		"restored": return I18n.t("Restore %d damaged tiles") % t
		"harvests": return I18n.t("Bring in %d harvests") % t
		"food": return I18n.t("Store %d food") % t
		"survive": return I18n.t("Last %d days") % t
		"clear_water": return I18n.t("Clear coastal water")
		"no_loss": return I18n.t("No villager leaves")
		"no_fire_loss": return I18n.t("No wildfires")
		"by_day": return I18n.t("Finish by day %d") % t
	return str(o["kind"])


## Progress text like "8/12" for the objectives panel.
static func progress_text(o: Dictionary, ws: WorldState, sc: Scenario) -> String:
	var k := str(o["kind"])
	var v := metric(k, ws, sc)
	match k:
		"clear_water", "no_loss", "no_fire_loss":
			return I18n.t("yes") if v >= 1.0 else I18n.t("no")
		"by_day":
			return I18n.t("day %d") % int(v)
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
		if is_scored():
			_score_medal(ws)
		_end(ws, Status.WON, I18n.t(str(def.get("win_text", "You did it!"))))
		return
	if ws.relaxed:
		return
	if ws.villagers <= int(def.get("fail_villagers", 0)):
		_end(ws, Status.FAILED, I18n.t("Too many villagers left the island."))
	elif def.has("census") and days_elapsed(ws) > 0 and days_elapsed(ws) % int(Simulation.YEAR_LENGTH) == 0 \
			and ws.villagers < census_target(ws):
		_end(ws, Status.FAILED, I18n.t("The year-%d census counted %d villagers; the island needed %d.") % [
			days_elapsed(ws) / int(Simulation.YEAR_LENGTH), ws.villagers, census_target(ws)])
	elif def.has("fail_keystone") and days_elapsed(ws) > 30 and ws.keystone < float(def["fail_keystone"]):
		_end(ws, Status.FAILED, I18n.t("The island's health collapsed below %d.") % int(def["fail_keystone"]))
	elif deadline() > 0 and days_elapsed(ws) >= deadline():
		var missed := PackedStringArray()
		for k in objs.size():
			if not objective_done(k, ws):
				missed.append(I18n.done("%s (%s)" % [label(objs[k]), progress_text(objs[k], ws, self)]))
		_end(ws, Status.FAILED, I18n.f("Day %d came and these goals were not met: %s.", [deadline(), ", ".join(missed)]))


## Endless: villagers required at the next year-end census.
func census_target(ws: WorldState) -> int:
	var c: Array = def.get("census", [])
	if c.size() < 3:
		return 0
	var year := maxi((days_elapsed(ws) - 1) / int(Simulation.YEAR_LENGTH), 0)
	return mini(int(c[0]) + int(c[1]) * year, int(c[2]))


func _score_medal(ws: WorldState) -> void:
	final_score = ScenarioCatalog.score(def, ws, days_elapsed(ws))
	stars = 0 if ws.relaxed else ScenarioCatalog.medal_for(def, final_score)


func _end(ws: WorldState, s: int, why: String) -> void:
	if s == Status.FAILED and is_scored():
		_score_medal(ws)
		if is_endless():
			why = I18n.t("The village held on for %d days. %s") % [days_elapsed(ws), why]
	status = s
	ended_tick = ws.tick
	reason = why


## One-line HUD summary.
func objective_text(ws: WorldState) -> String:
	if is_sandbox():
		return I18n.t("Sandbox - free play")
	if is_scored():
		var d := days_elapsed(ws)
		match status:
			Status.RUNNING:
				if is_endless():
					var left := int(Simulation.YEAR_LENGTH) - d % int(Simulation.YEAR_LENGTH)
					return I18n.t("Day %d  ·  census in %d days: %d/%d villagers  ·  score %d") % [d, left, ws.villagers,
						census_target(ws), score(ws)]
				return I18n.t("Day %d/%d  ·  score %d") % [d, int(objectives()[0].get("target", 0)), score(ws)]
			_:
				return I18n.t("Final score %d  ·  %s") % [final_score, I18n.t(MEDAL_NAMES[clampi(stars, 0, 3)])]
	match status:
		Status.WON:
			return I18n.t("Complete - %d of 3 stars (day %d)") % [stars, ended_tick - start_tick]
		Status.FAILED:
			return I18n.t("Failed (day %d)") % (ended_tick - start_tick)
	var objs := objectives()
	for k in objs.size():
		if not objective_done(k, ws):
			var o: Dictionary = objs[k]
			var left := I18n.f("  ·  %d days left", deadline() - days_elapsed(ws)) if deadline() > 0 else ""
			return I18n.done("%s  (%s)%s" % [label(o), progress_text(o, ws, self), left])
	return I18n.t("All goals met")


func intro_text() -> String:
	return str(def.get("intro", ""))


func to_dict() -> Dictionary:
	return {"id": id, "status": status, "ended_tick": ended_tick, "reason": reason,
		"start_tick": start_tick, "stars": stars, "done": Array(done), "score": final_score}


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
	s.final_score = int(d.get("score", 0))
	var dn: Array = d.get("done", [])
	for k in mini(dn.size(), s.done.size()):
		s.done[k] = 1 if int(dn[k]) != 0 else 0
	return s
