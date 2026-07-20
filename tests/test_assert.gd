class_name TestAssert
extends RefCounted

var failures: Array[String] = []
var checks := 0

func equal(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, expected, actual])

func near(actual: float, expected: float, epsilon: float, message: String) -> void:
	checks += 1
	if absf(actual - expected) > epsilon:
		failures.append("%s: expected %.4f ± %.4f, got %.4f" % [message, expected, epsilon, actual])

func truthy(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append("%s: expected true" % message)
