extends SceneTree
## Headless runner: godot --headless --path . --script res://tests/run_tests.gd
## Optional filter: ... -- --only=<substring of file::test>. Exit code 1 if any test fails.

const TEST_DIR := "res://tests"


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var files: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
				files.append(f)
	files.sort()
	var passed := 0
	var failed := 0
	for f in files:
		var script: GDScript = load(TEST_DIR + "/" + f)
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL %s: script did not load" % f)
			continue
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			var label := "%s::%s" % [f, mname]
			if only != "" and not label.contains(only):
				continue
			var inst: TestCase = script.new()
			inst.call(mname)
			if not inst.finished:
				inst.failures.append("did not reach done() (runtime error?)")
			if inst.failures.is_empty():
				passed += 1
				print("PASS %s" % label)
			else:
				failed += 1
				for msg in inst.failures:
					print("FAIL %s: %s" % [label, msg])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or passed == 0 else 0)
