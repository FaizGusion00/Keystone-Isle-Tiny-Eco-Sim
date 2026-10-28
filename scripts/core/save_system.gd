class_name SaveSystem
extends RefCounted
## Versioned local JSON saves with atomic writes and a backup.
##
## Format (version 1):
##   { version, saved_at (unix s), meta{...}, world{width,height,seed,arrays{name: base64},
##     scalars{name: value}}, events{...EventLog.to_dict()}, rng{seed,state} (strings, 64-bit safe),
##     scenario{...} | null }
## Arrays are raw little-endian bytes and float scalars raw float64 bytes → exact round-trip.
##
## Atomic write: write <path>.tmp → re-read + parse + validate → <path> becomes <path>.bak →
## <path>.tmp renamed to <path>. A crash at any point leaves either the old save, the backup,
## or the new save intact. load_game() falls back to the .bak if the main file is missing/corrupt.

const VERSION := 1
const DEFAULT_PATH := "user://keystone_save.json"


static func to_dict(sim: Simulation, meta: Dictionary = {}) -> Dictionary:
	var ws := sim.world
	var arrays := {}
	for f in WorldState.ARRAY_FIELDS:
		var a = ws.get(f)
		var bytes: PackedByteArray = a if a is PackedByteArray else a.to_byte_array()
		arrays[f] = Marshalls.raw_to_base64(bytes)
	var scalars := {}
	for f in WorldState.SCALAR_FIELDS:
		var v: Variant = ws.get(f)
		# Godot's JSON parser can lose the last bit of a double, so floats are stored as raw
		# float64 bytes (base64) to keep loads bit-exact (determinism after load is tested).
		scalars[f] = Marshalls.raw_to_base64(PackedFloat64Array([v]).to_byte_array()) if v is float else v
	return {
		"version": VERSION,
		"saved_at": meta.get("saved_at", Time.get_unix_time_from_system()),
		"meta": meta,
		"world": {"width": ws.width, "height": ws.height, "seed": ws.world_seed, "arrays": arrays, "scalars": scalars},
		"events": sim.events.to_dict(),
		"rng": {"seed": str(sim.rng.seed), "state": str(sim.rng.state)},
		"scenario": sim.scenario.to_dict() if sim.scenario != null else null,
	}


## Rebuilds a Simulation from a save dictionary; null if invalid or from a newer version.
static func from_dict(d: Dictionary) -> Simulation:
	var ver := int(d.get("version", -1))
	if ver < 1 or ver > VERSION:
		return null
	var wd: Dictionary = d.get("world", {})
	var w := int(wd.get("width", 0))
	var h := int(wd.get("height", 0))
	if w <= 0 or h <= 0 or w > 512 or h > 512:
		return null
	var ws := WorldState.new(w, h, int(wd.get("seed", 0)))
	var arrays: Dictionary = wd.get("arrays", {})
	for f in WorldState.ARRAY_FIELDS:
		if not arrays.has(f):
			return null
		var raw := Marshalls.base64_to_raw(str(arrays[f]))
		if WorldState.ARRAY_FIELDS[f] != TYPE_PACKED_BYTE_ARRAY and raw.size() % 4 != 0:
			return null
		var v: Variant
		match WorldState.ARRAY_FIELDS[f]:
			TYPE_PACKED_FLOAT32_ARRAY: v = raw.to_float32_array()
			TYPE_PACKED_INT32_ARRAY: v = raw.to_int32_array()
			_: v = raw
		var expected: int = ws.get(f).size()
		if v.size() != expected:
			return null
		ws.set(f, v)
	var scalars: Dictionary = wd.get("scalars", {})
	for f in WorldState.SCALAR_FIELDS:
		if not scalars.has(f):
			return null
		var cur: Variant = ws.get(f)
		match typeof(cur):
			TYPE_INT: ws.set(f, int(scalars[f]))
			TYPE_BOOL: ws.set(f, bool(scalars[f]))
			_:
				var fb := Marshalls.base64_to_raw(str(scalars[f]))
				if fb.size() != 8:
					return null
				ws.set(f, fb.decode_double(0))
	var el := EventLog.from_dict(d.get("events", {}))
	if el == null:
		return null
	var sim := Simulation.new(ws)
	sim.events = el
	var r: Dictionary = d.get("rng", {})
	sim.rng.seed = str(r.get("seed", "0")).to_int()
	sim.rng.state = str(r.get("state", "0")).to_int()
	var sc = d.get("scenario")
	if sc is Dictionary:
		sim.scenario = Scenario.from_dict(sc)
	return sim


## Atomic save. Returns OK or an error code; never leaves a half-written main file.
static func save_game(sim: Simulation, path: String = DEFAULT_PATH, meta: Dictionary = {}) -> Error:
	var text := JSON.stringify(to_dict(sim, meta), "", false, true)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()
	# verify what actually reached the disk before replacing anything
	if read_dict(tmp).is_empty():
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	var bak := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var e1 := DirAccess.rename_absolute(path, bak)
		if e1 != OK:
			return e1
	return DirAccess.rename_absolute(tmp, path)


static func read_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK: # quiet: a torn file is an expected case, not an engine error
		return {}
	var parsed: Variant = json.data
	if parsed is Dictionary and int(parsed.get("version", -1)) >= 1:
		return parsed
	return {}


## Loads the save (falling back to the backup). Returns {} when nothing usable exists, else
## {"sim": Simulation, "saved_at": float, "meta": Dictionary, "source": path}.
static func load_game(path: String = DEFAULT_PATH) -> Dictionary:
	for p in [path, path + ".bak"]:
		var d := read_dict(p)
		if d.is_empty():
			continue
		var sim := from_dict(d)
		if sim == null:
			continue
		var meta: Dictionary = d.get("meta", {})
		return {"sim": sim, "saved_at": float(d.get("saved_at", 0.0)), "meta": meta, "source": p}
	return {}


static func delete_all(path: String = DEFAULT_PATH) -> void:
	for p in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
