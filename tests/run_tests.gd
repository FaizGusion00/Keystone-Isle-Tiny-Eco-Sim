extends SceneTree
## Headless test runner:  godot --headless -s tests/run_tests.gd [-- --filter=name]
## Discovers tests/test_*.gd, runs every method named test_*, exits 1 on any failure.


## Counts engine/script errors so a test that crashes mid-way (SCRIPT ERROR aborts the
## method without failing an assertion) is reported as FAIL, not PASS.
class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1
	func _log_message(_message: String, _error: bool) -> void:
		pass


var _ran := false
var _errors := ErrorCounter.new()


## Tests run on the first frame, once the root window is in the tree (scene tests need it).
func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		OS.add_logger(_errors)
		I18n.locked = "en"  # tests assert English text whatever the device / saved language
		TranslationServer.set_locale("en")
		_run_all()
	return false


func _run_all() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
	var files: PackedStringArray = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var passed := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		if filter != "" and not f.contains(filter):
			continue
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL ", f, " (script failed to load / parse)")
			continue
		var inst: TestCase = script.new()
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			inst.current = "%s::%s" % [f.get_basename(), mname]
			var before := inst.failures.size()
			var errs_before := _errors.count
			await inst.call(mname)  # tests may await frames
			if _errors.count > errs_before and not inst.expects_errors:
				inst.failures.append("%s: %d engine/script error(s) logged (see above)" % [inst.current, _errors.count - errs_before])
			inst.expects_errors = false
			if inst.failures.size() == before:
				passed += 1
				print("  PASS ", inst.current)
			else:
				failed += 1
				print("  FAIL ", inst.current)
				for i in range(before, inst.failures.size()):
					print("       ", inst.failures[i])
	print("\n%d passed, %d failed (%d ms)" % [passed, failed, Time.get_ticks_msec() - t0])
	I18n.shutdown()
	quit(1 if failed > 0 else 0)
