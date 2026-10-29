class_name Progress
extends RefCounted
## Persistent local progress: best stars per scenario, earned achievements, totals.
## Stored as JSON at user://progress.json, written atomically (tmp + rename).

const PATH := "user://progress.json"

var stars: Dictionary = {}          ## scenario id -> best stars (0 = played, not won)
var achievements: Array = []        ## earned achievement ids, in order earned
var games_won := 0
var path := PATH


static func load_from(p: String = PATH) -> Progress:
	var pr := Progress.new()
	pr.path = p
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			var st = parsed.get("stars", {})
			if st is Dictionary:
				for k in st:
					pr.stars[str(k)] = int(st[k])
			var ach = parsed.get("achievements", [])
			if ach is Array:
				for a in ach:
					pr.achievements.append(str(a))
			pr.games_won = int(parsed.get("games_won", 0))
	return pr


func save() -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "stars": stars, "achievements": achievements, "games_won": games_won}, "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, path)


func as_dict() -> Dictionary:
	return {"stars": stars, "achievements": achievements}


func best_stars(id: String) -> int:
	return int(stars.get(id, 0))


func is_unlocked(id: String) -> bool:
	return ScenarioCatalog.is_unlocked(id, as_dict())


## Records a finished scenario. Returns true if it improved the best result.
func record_result(id: String, won: bool, got_stars: int) -> bool:
	var best := best_stars(id)
	if won:
		games_won += 1
	if not stars.has(id):
		stars[id] = 0
	if won and got_stars > best:
		stars[id] = got_stars
		return true
	return false


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
