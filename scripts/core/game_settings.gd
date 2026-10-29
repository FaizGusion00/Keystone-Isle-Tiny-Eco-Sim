class_name GameSettings
extends RefCounted
## Player settings stored in user://settings.cfg. Pure data + apply() for audio buses.

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"master_volume": 0.8, "music_volume": 0.6, "sfx_volume": 0.8,
	"ui_scale": 1.0, "reduce_motion": false, "colorblind": false, "haptics": true,
	"language": "en", "show_tutorial": true,
}

var values: Dictionary = DEFAULTS.duplicate()
var path := PATH


static func load_from(p: String = PATH) -> GameSettings:
	var s := GameSettings.new()
	s.path = p
	var cfg := ConfigFile.new()
	if cfg.load(p) == OK:
		for k in DEFAULTS:
			var v = cfg.get_value("settings", k, DEFAULTS[k])
			if typeof(v) == typeof(DEFAULTS[k]) or (DEFAULTS[k] is float and v is int):
				s.values[k] = v
	s.values["ui_scale"] = clampf(float(s.values["ui_scale"]), 0.75, 1.5)
	return s


func save() -> Error:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	return cfg.save(path)


func get_value(key: String):
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v) -> void:
	values[key] = v


## Linear 0..1 volume to dB for a bus (creates nothing; missing buses are skipped).
func apply_audio() -> void:
	for pair in [["Master", "master_volume"], ["Music", "music_volume"], ["SFX", "sfx_volume"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx < 0:
			continue
		var lin := clampf(float(values[pair[1]]), 0.0, 1.0)
		AudioServer.set_bus_mute(idx, lin <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(lin, 0.001)))
