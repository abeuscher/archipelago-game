## Headless test runner. Usage:
##   godot --headless --path . -s tests/run_tests.gd [-- filter]
## Runs every test_* method in tests/test_*.gd. Exit code 0 when all pass.
extends SceneTree


class ErrorCounter extends Logger:
	var errors: int = 0
	var last: String = ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors += 1
		last = "%s:%d %s %s %s" % [file, line, function, code, rationale]

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]

	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()

	var passed := 0
	var failed := 0
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var n: String = m["name"]
			if n.begins_with("test_") and (filter == "" or (f + ":" + n).contains(filter)):
				methods.append(n)
		for n in methods:
			var inst = script.new()
			var before := counter.errors
			inst.call(n)
			var errs := counter.errors - before
			if inst.failures.is_empty() and errs == 0:
				passed += 1
			else:
				failed += 1
				print("FAIL %s:%s" % [f, n])
				for msg in inst.failures:
					print("    ", msg)
				if errs > 0:
					print("    script error: ", counter.last)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
