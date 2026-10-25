class_name TestCase
extends RefCounted
## Base for tests/test_*.gd. Each test_* method must end with done(); a test that never reaches
## done() (e.g. aborted by a runtime script error) counts as failed.

var failures: Array[String] = []
var finished := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


func done() -> void:
	finished = true
