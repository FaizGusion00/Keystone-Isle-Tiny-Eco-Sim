class_name Progress
extends RefCounted
## Persistent local progress (user://progress.json, written atomically: tmp + rename):
## best stars per scenario, personal bests and medals per seeded island, achievements,
## XP / level / prestige, codex discoveries and cosmetics.
##
## Version 3 (v1/v2 files are migrated on load; v3 adds date_seen for clock-change handling). Designed to be conflict-mergeable for a future
## cloud sync: every field merges by union or max (see merge()), and the file carries a
## profile_id and updated_at.

const PATH := "user://progress.json"
const VERSION := 3
const MAX_BESTS := 120   ## keep the file small: oldest daily/weekly bests are pruned

var stars: Dictionary = {}          ## campaign/challenge id -> best stars (0 = played, not won)
var achievements: Array = []        ## earned achievement ids, in order earned
var games_won := 0
var bests: Dictionary = {}          ## any scenario id -> {score, days, medal, at}
var xp := 0                         ## XP within the current prestige
var prestige := 0
var codex_events: Array = []        ## EventLog type names seen (rare events)
var codex_species := 0              ## species bitmask ever seen
var banner := "teal"                ## selected cosmetic banner
var moments: Array = []             ## "first time" explanations already shown (Moments ids)
var date_seen := ""                 ## newest local date (YYYYMMDD) this profile has seen; see observe_date()
var profile_id := ""
var updated_at := 0.0
var path := PATH


static func load_from(p: String = PATH) -> Progress:
	var pr := Progress.new()
	pr.path = p
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			pr.load_dict(parsed)
	if pr.profile_id == "":
		pr.profile_id = SaveSystem.new_save_id()
	return pr


## Reads v1 or v2 data (unknown/missing fields keep their defaults).
func load_dict(d: Dictionary) -> void:
	var st = d.get("stars", {})
	if st is Dictionary:
		for k in st:
			stars[str(k)] = int(st[k])
	var ach = d.get("achievements", [])
	if ach is Array:
		for a in ach:
			if not achievements.has(str(a)):
				achievements.append(str(a))
	games_won = int(d.get("games_won", 0))
	var b = d.get("bests", {})
	if b is Dictionary:
		for k in b:
			if b[k] is Dictionary:
				bests[str(k)] = {"score": int(b[k].get("score", 0)), "days": int(b[k].get("days", 0)),
					"medal": int(b[k].get("medal", 0)), "at": float(b[k].get("at", 0.0))}
	xp = maxi(int(d.get("xp", 0)), 0)
	prestige = maxi(int(d.get("prestige", 0)), 0)
	var cx = d.get("codex", {})
	if cx is Dictionary:
		var ev = cx.get("events", [])
		if ev is Array:
			for e in ev:
				if not codex_events.has(str(e)):
					codex_events.append(str(e))
		codex_species = int(cx.get("species", 0))
	banner = str(d.get("banner", "teal"))
	profile_id = str(d.get("profile_id", ""))
	updated_at = float(d.get("updated_at", 0.0))
	moments = (d.get("moments", []) as Array).duplicate() if d.get("moments", []) is Array else []
	date_seen = str(d.get("date_seen", ""))
	if not _valid_key(date_seen):
		date_seen = ""
	if int(d.get("version", 1)) < 3: # migrate: the newest daily/weekly you played is a date you saw
		for k in bests:
			var key := str(k).get_slice("_", 1)
			if ScenarioCatalog.mode_of(str(k)) in ["daily", "weekly"] and _valid_key(key) and key > date_seen:
				date_seen = key


func to_dict() -> Dictionary:
	return {"version": VERSION, "profile_id": profile_id, "updated_at": updated_at, "stars": stars,
		"achievements": achievements, "games_won": games_won, "bests": bests, "xp": xp,
		"prestige": prestige, "codex": {"events": codex_events, "species": codex_species}, "banner": banner,
		"date_seen": date_seen, "moments": moments}


func save() -> Error:
	updated_at = Time.get_unix_time_from_system()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, path)


func as_dict() -> Dictionary:
	return {"stars": stars, "achievements": achievements}


func best_stars(id: String) -> int:
	return int(stars.get(id, 0))


func best(id: String) -> Dictionary:
	return bests.get(id, {})


func is_unlocked(id: String) -> bool:
	return ScenarioCatalog.is_unlocked(id, as_dict())


## Records a finished campaign/challenge. Returns true if it improved the best result.
func record_result(id: String, won: bool, got_stars: int) -> bool:
	var best_s := best_stars(id)
	if won:
		games_won += 1
	if ScenarioCatalog.mode_of(id) != "":
		return false # seeded modes keep score bests instead (record_run)
	if not stars.has(id):
		stars[id] = 0
	if won and got_stars > best_s:
		stars[id] = got_stars
		return true
	return false


## Records any finished run for bests and XP. Returns {xp, level_up, new_best, medal, score, replay}.
## XP is improvement-only, so replaying the same seeded island (or campaign map) cannot farm levels:
## seeded runs earn per_score × (score above your best) + per_medal × (medal tiers above your best);
## campaign/challenge maps earn per_star × (stars above your best) plus score XP on the first win only.
## Call before record_result() (which raises the star best).
func record_run(id: String, won: bool, got_stars: int, points: int, days: int, medal: int) -> Dictionary:
	var xc: Dictionary = ContentDB.mode("xp")
	var per_score := float(xc.get("per_score", 0.2))
	var scored := ScenarioCatalog.mode_of(id) != ""
	var gained := 0
	var replay := false
	if scored:
		var prev := best(id)
		replay = not prev.is_empty()
		gained = int(round(per_score * maxi(points - int(prev.get("score", 0)), 0)))
		gained += int(xc.get("per_medal", 60)) * maxi(medal - int(prev.get("medal", 0)), 0)
	elif won:
		var prev_stars := best_stars(id)
		replay = prev_stars > 0
		gained = int(xc.get("per_star", 40)) * maxi(got_stars - prev_stars, 0)
		if not replay:
			gained += int(round(per_score * points))
	gained = int(round(gained * (1.0 + 0.1 * prestige)))
	var before := level()
	xp += gained
	var new_best := false
	if scored:
		var b := best(id)
		if b.is_empty() or points > int(b.get("score", 0)) or medal > int(b.get("medal", 0)):
			bests[id] = {"score": maxi(points, int(b.get("score", 0))), "days": days if points >= int(b.get("score", 0)) else int(b.get("days", days)),
				"medal": maxi(medal, int(b.get("medal", 0))), "at": Time.get_unix_time_from_system()}
			new_best = points > int(b.get("score", 0)) or b.is_empty()
		_prune_bests()
	return {"xp": gained, "level_up": level() > before, "new_best": new_best, "medal": medal, "score": points,
		"replay": replay}


func _prune_bests() -> void:
	if bests.size() <= MAX_BESTS:
		return
	var ids := bests.keys()
	ids.sort_custom(func(a, b): return float(bests[a].get("at", 0.0)) < float(bests[b].get("at", 0.0)))
	for k in ids.size() - MAX_BESTS:
		bests.erase(ids[k])


# ------------------------------------------------------------------ levels & prestige

static func xp_for_level(lv: int) -> int:
	var base := int(ContentDB.mode("xp").get("level_base", 250))
	return base * lv * (lv - 1) / 2    # total XP needed to reach level lv (level 1 = 0)


func level() -> int:
	var lv := 1
	while xp >= xp_for_level(lv + 1) and lv < 99:
		lv += 1
	return lv


## 0..1 progress through the current level.
func level_progress() -> float:
	var lv := level()
	var a := xp_for_level(lv)
	var b := xp_for_level(lv + 1)
	return clampf(float(xp - a) / float(maxi(b - a, 1)), 0.0, 1.0)


func can_prestige() -> bool:
	return level() >= int(ContentDB.mode("xp").get("prestige_level", 10))


## Starts a new prestige: XP back to level 1, +10% XP gain per prestige, new cosmetics.
func do_prestige() -> bool:
	if not can_prestige():
		return false
	prestige += 1
	xp = 0
	return true


func medal_count() -> int:
	var n := 0
	for k in bests:
		if int(bests[k].get("medal", 0)) > 0:
			n += 1
	return n


func species_count() -> int:
	var n := 0
	var b := codex_species
	while b > 0:
		n += b & 1
		b >>= 1
	return n


# ------------------------------------------------------------------ codex & cosmetics

## Adds rare events / species seen in this sim to the codex. Returns new entry titles.
func observe(sim: Simulation) -> Array:
	var fresh := []
	for r in ContentDB.rare_events():
		var tname := str(r["type"])
		if codex_events.has(tname):
			continue
		for id in sim.events.recent(EventLog.CAPACITY):
			if EventLog.Type.find_key(sim.events.type_of(id)) == tname:
				codex_events.append(tname)
				fresh.append(str(r.get("title", tname)))
				break
	for s in ContentDB.species():
		var b := int(s["bit"])
		if (sim.world.species_seen & b) != 0 and (codex_species & b) == 0:
			codex_species |= b
			fresh.append(str(s.get("title", s["id"])))
	return fresh


## Level unlocks stay unlocked after prestige (the player has passed them once).
func banner_unlocked(b: Dictionary) -> bool:
	var u: Dictionary = b.get("unlock", {})
	if u.has("level") and level() < int(u["level"]) and prestige == 0:
		return false
	return medal_count() >= int(u.get("medals", 0)) and prestige >= int(u.get("prestige", 0)) \
		and species_count() >= int(u.get("species", 0))


func banner_color() -> Color:
	for b in ContentDB.banners():
		if str(b["id"]) == banner and banner_unlocked(b):
			return Color.html(str(b["color"]))
	return Color.html("2f7d6d")


## Conflict merge with another copy of the profile (e.g. cloud): unions and maxima, so no
## device ever loses progress. The selected banner follows the most recently updated copy.
func merge(o: Progress) -> void:
	for k in o.stars:
		stars[k] = maxi(int(stars.get(k, 0)), int(o.stars[k]))
	for a in o.achievements:
		if not achievements.has(a):
			achievements.append(a)
	games_won = maxi(games_won, o.games_won)
	for k in o.bests:
		var mine := best(k)
		var theirs: Dictionary = o.bests[k]
		var medal := maxi(int(theirs.get("medal", 0)), int(mine.get("medal", 0)))
		if mine.is_empty() or int(theirs.get("score", 0)) > int(mine.get("score", 0)):
			bests[k] = theirs.duplicate()
		bests[k]["medal"] = medal   # the best medal ever earned survives either way
	if o.prestige > prestige or (o.prestige == prestige and o.xp > xp):
		prestige = o.prestige
		xp = o.xp
	for e in o.codex_events:
		if not codex_events.has(e):
			codex_events.append(e)
	codex_species |= o.codex_species
	if o.date_seen > date_seen:
		date_seen = o.date_seen
	for m in o.moments:
		if not moments.has(m):
			moments.append(m)
	if o.updated_at > updated_at:
		banner = o.banner
		updated_at = o.updated_at
	_prune_bests()


## Daily/weekly islands follow the device's local calendar date (no network time). Call with
## today's date key: moving forward (normal days, time zones, DST, a clock set ahead) just
## advances date_seen. A date earlier than one already seen means the clock went back: the
## island for the clock's date is still offered (nobody is locked out), but this returns true
## (beyond one day of slack) so the run is marked off-clock and its score is not submitted to any leaderboard.
## Garbage dates (e.g. a reset clock reading 1970) also count as off-clock.
func observe_date(key: String) -> bool:
	if not _valid_key(key) or key < "20240101":
		return true
	if key >= date_seen:
		date_seen = key
		return false
	# one day of slack: flying west across the date line can legitimately step back a day
	return _unix(date_seen) - _unix(key) > 86400


static func _unix(k: String) -> int:
	return Time.get_unix_time_from_datetime_dict({"year": int(k.substr(0, 4)), "month": int(k.substr(4, 2)),
		"day": int(k.substr(6, 2)), "hour": 12, "minute": 0, "second": 0})


static func _valid_key(k: String) -> bool:
	return k.length() == 8 and k.is_valid_int()


static func date_key(date: Dictionary = {}) -> String:
	if date.is_empty():
		date = Time.get_date_dict_from_system()
	return "%04d%02d%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


## Adds newly earned achievements; returns the ids that were new.
func grant(ids: Array) -> Array:
	var fresh := []
	for id in ids:
		if not achievements.has(id):
			achievements.append(id)
			fresh.append(id)
	return fresh


func total_stars() -> int:
	var t := 0
	for k in stars:
		t += int(stars[k])
	return t


func reset() -> void:
	stars.clear()
	achievements.clear()
	games_won = 0
	bests.clear()
	xp = 0
	prestige = 0
	codex_events.clear()
	codex_species = 0
	banner = "teal"
