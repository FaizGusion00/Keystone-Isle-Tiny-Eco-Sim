class_name TestCase
extends RefCounted
## Base class for headless tests. Methods named test_* are run by tests/run_tests.gd.

var failures: PackedStringArray = []
var current := ""
## Set by a test that deliberately triggers engine errors (the runner fails tests that log errors).
var expects_errors := false


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("%s: expected true. %s" % [current, msg])


func assert_false(cond: bool, msg: String = "") -> void:
	assert_true(not cond, msg)


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if typeof(a) != typeof(b) or a != b:
		failures.append("%s: expected %s == %s. %s" % [current, str(a), str(b), msg])


func assert_ne(a: Variant, b: Variant, msg: String = "") -> void:
	if typeof(a) == typeof(b) and a == b:
		failures.append("%s: expected %s != %s. %s" % [current, str(a), str(b), msg])


func assert_near(a: float, b: float, eps: float = 1e-4, msg: String = "") -> void:
	if absf(a - b) > eps:
		failures.append("%s: expected %f ~= %f. %s" % [current, a, b, msg])
