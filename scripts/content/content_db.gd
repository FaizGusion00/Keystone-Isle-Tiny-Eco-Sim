class_name ContentDB
extends RefCounted
## Read-only access to the data-driven content files in res://data/*.json (mutators, game
## modes and scoring, species, codex text, cosmetics). Files are parsed once and cached.
## Adding content = editing JSON; see docs/LIVEOPS.md for the pipeline and validation rules.

const DIR := "res://data/"
static var _cache := {}


static func file(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var d := {}
	var p := DIR + name + ".json"
	if FileAccess.file_exists(p):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			d = parsed
		else:
			push_error("ContentDB: %s is not valid JSON" % p)
	else:
		push_error("ContentDB: missing %s" % p)
	_cache[name] = d
	return d


static func clear_cache() -> void:
	_cache.clear()


static func mutators() -> Array:
	return file("mutators").get("mutators", [])


static func mutator(id: String) -> Dictionary:
	for m in mutators():
		if str(m.get("id", "")) == id:
			return m
	return {}


static func mode(name: String) -> Dictionary:
	return file("modes").get(name, {})


static func species() -> Array:
	return file("species").get("species", [])


static func rare_events() -> Array:
	return file("codex").get("rare_events", [])


static func banners() -> Array:
	return file("cosmetics").get("banners", [])


## Validation used by tests and tools: returns a list of problems ("" entries never appear).
static func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var ids := {}
	var allowed := ["food", "wood", "labor", "fish", "goats", "villagers", "climate_rain", "climate_storm",
		"climate_fire", "degrade"]
	for m in mutators():
		var id := str(m.get("id", ""))
		if id == "" or ids.has(id):
			errs.append("mutator id missing or duplicate: '%s'" % id)
		ids[id] = true
		for sect in ["mul", "add", "set"]:
			for k in m.get(sect, {}):
				if not k in allowed:
					errs.append("mutator %s: unknown key %s.%s" % [id, sect, k])
		var from := str(m.get("from", ""))
		if from != "" and (from.length() != 8 or not from.is_valid_int()):
			errs.append("mutator %s: \"from\" must be YYYYMMDD" % id)
		if float(m.get("score_mult", 0.0)) <= 0.0:
			errs.append("mutator %s: score_mult must be > 0" % id)
	for mname in ["daily", "weekly", "endless"]:
		var md := mode(mname)
		var medals: Array = md.get("medals", [])
		if medals.size() != 3 or not (float(medals[0]) < float(medals[1]) and float(medals[1]) < float(medals[2])):
			errs.append("mode %s: medals must be 3 ascending thresholds" % mname)
	var bits := 0
	for s in species():
		var b := int(s.get("bit", 0))
		if b <= 0 or (b & (b - 1)) != 0 or (bits & b) != 0:
			errs.append("species %s: bit must be a unique power of two" % s.get("id", "?"))
		bits |= b
	for r in rare_events():
		if not EventLog.Type.has(str(r.get("type", ""))):
			errs.append("codex: unknown event type %s" % r.get("type", "?"))
	for b in banners():
		if not Color.html_is_valid(str(b.get("color", ""))):
			errs.append("banner %s: bad colour" % b.get("id", "?"))
	for entry in mutators() + species() + rare_events():
		var ic := str(entry.get("icon", ""))
		if ic == "" or not ResourceLoader.exists("res://assets/icons/%s.svg" % ic):
			errs.append("%s: icon '%s' not in assets/icons" % [entry.get("id", entry.get("type", "?")), ic])
	return errs
