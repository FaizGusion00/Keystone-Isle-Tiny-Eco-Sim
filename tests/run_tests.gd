extends SceneTree
## Headless test runner:  godot --headless -s tests/run_tests.gd [-- --filter=name]
## Discovers tests/test_*.gd, runs every method named test_*, exits 1 on any failure.


func _init() -> void:
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
		var inst: TestCase = script.new()
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			inst.current = "%s::%s" % [f.get_basename(), mname]
			var before := inst.failures.size()
			inst.call(mname)
			if inst.failures.size() == before:
				passed += 1
				print("  PASS ", inst.current)
			else:
				failed += 1
				print("  FAIL ", inst.current)
				for i in range(before, inst.failures.size()):
					print("       ", inst.failures[i])
	print("\n%d passed, %d failed (%d ms)" % [passed, failed, Time.get_ticks_msec() - t0])
	quit(1 if failed > 0 else 0)
