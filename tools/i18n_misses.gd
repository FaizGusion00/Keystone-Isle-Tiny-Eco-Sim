extends SceneTree
## Prints every UI text with no translation in a language (default ms), as JSON keys ready to
## paste into i18n/<code>.json:   godot --headless --path . -s tools/i18n_misses.gd -- --lang=ms

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var code := "ms"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			code = a.trim_prefix("--lang=")
	var misses: Dictionary = I18nSweep.run(code)
	var tab := I18n.table(code)
	for k in I18nTables.all_texts():
		if not tab.has(k):
			misses[k] = true
	var keys := misses.keys()
	keys.sort()
	var out := {}
	for k in keys:
		out[k] = ""
	print("MISSES_JSON_BEGIN")
	print(JSON.stringify(out, "  ", false))
	print("MISSES_JSON_END")
	print("%d untranslated texts in '%s'" % [keys.size(), code])
	I18n.shutdown()
	quit(0)
	return false
