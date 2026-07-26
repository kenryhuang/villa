class_name PlayerState
extends RefCounted

const LEVEL_THRESHOLDS := [0, 100, 250, 500, 850, 1300, 1900, 2600, 3500, 4600, 6000]

var stamina := 100
var max_stamina := 100
var level := 1
@warning_ignore("shadowed_global_identifier")
var exp := 0


func add_exp(amount: int) -> bool:
	if amount <= 0:
		return false
	exp += amount
	var old_level := level
	for i in range(LEVEL_THRESHOLDS.size() - 1, -1, -1):
		if exp >= LEVEL_THRESHOLDS[i]:
			level = i + 1
			break
	return level > old_level


func set_stamina(value: int) -> bool:
	var clamped := clampi(value, 0, max_stamina)
	if clamped == stamina:
		return false
	stamina = clamped
	return true


func get_exp_progress() -> float:
	if level >= LEVEL_THRESHOLDS.size():
		return 1.0
	var current_threshold: int = LEVEL_THRESHOLDS[level - 1]
	var next_threshold: int = LEVEL_THRESHOLDS[level]
	var range_size: int = next_threshold - current_threshold
	if range_size <= 0:
		return 1.0
	return float(exp - current_threshold) / float(range_size)


func get_exp_for_next_level() -> int:
	if level >= LEVEL_THRESHOLDS.size():
		return 0
	var current_threshold: int = LEVEL_THRESHOLDS[level - 1]
	var next_threshold: int = LEVEL_THRESHOLDS[level]
	return next_threshold - current_threshold
