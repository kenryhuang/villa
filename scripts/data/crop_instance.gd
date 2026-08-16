class_name CropInstance
extends RefCounted

const CropDataScript = preload("res://scripts/data/crop_data.gd")

enum LifecycleState { GROWING, MATURE, DORMANT, WITHERED }

var crop_data
var growth_progress := 0.0
var is_watered_today := false
var harvest_count := 0
var lifecycle_state: LifecycleState = LifecycleState.GROWING


func calculate_yield(gx: int, gz: int, world_seed: int = 42) -> int:
	if crop_data == null:
		return 0
	var minimum: int = maxi(1, int(crop_data.yield_min))
	var maximum: int = maxi(minimum, int(crop_data.yield_max))
	var key := "%d:%d:%s:%d:%d" % [gx, gz, crop_data.crop_id, harvest_count, world_seed]
	# Explicit 32-bit FNV-1a avoids salted String.hash() and engine RNG drift.
	var hash_value: int = 2166136261
	for byte in key.to_utf8_buffer():
		hash_value = hash_value ^ int(byte)
		hash_value = (hash_value * 16777619) & 0xffffffff
	return minimum + int(hash_value % (maximum - minimum + 1))


func to_dict() -> Dictionary:
	return {
		"crop_id": str(crop_data.crop_id) if crop_data else "",
		"growth_progress": growth_progress,
		"is_watered_today": is_watered_today,
		"harvest_count": harvest_count,
		"lifecycle_state": lifecycle_state,
	}


func from_dict(data: Dictionary) -> bool:
	if crop_data == null:
		return false
	for field in ["crop_id", "growth_progress", "is_watered_today", "harvest_count", "lifecycle_state"]:
		if not data.has(field):
			return false
	if typeof(data.crop_id) != TYPE_STRING or str(data.crop_id) != str(crop_data.crop_id):
		return false
	if typeof(data.is_watered_today) != TYPE_BOOL:
		return false
	if not _is_number(data.growth_progress) or not _is_number(data.harvest_count):
		return false
	if not _is_number(data.lifecycle_state):
		return false
	var progress := float(data.growth_progress)
	var count_number := float(data.harvest_count)
	var state_number := float(data.lifecycle_state)
	var maturity_progress := float(crop_data.growth_days)
	if not is_finite(progress) or progress < 0.0 or progress > maturity_progress:
		return false
	if not is_finite(count_number) or count_number < 0.0 or count_number != floorf(count_number):
		return false
	if not is_finite(state_number) or state_number != floorf(state_number):
		return false
	var next_state := int(state_number)
	if not _is_valid_lifecycle_state(next_state):
		return false
	if next_state == LifecycleState.GROWING and progress >= maturity_progress:
		return false
	if next_state == LifecycleState.MATURE and progress != maturity_progress:
		return false

	growth_progress = progress
	is_watered_today = data.is_watered_today
	harvest_count = int(count_number)
	lifecycle_state = next_state as LifecycleState
	return true


func set_lifecycle_state(next_state: int) -> bool:
	if not _is_valid_lifecycle_state(next_state):
		return false
	lifecycle_state = next_state as LifecycleState
	return true


func derive_active_state() -> int:
	if crop_data != null and growth_progress >= float(crop_data.growth_days):
		return LifecycleState.MATURE
	return LifecycleState.GROWING


func advance_growth() -> bool:
	if crop_data == null or lifecycle_state != LifecycleState.GROWING:
		return false
	var old_stage := get_current_stage()
	var old_state := lifecycle_state
	var advance := 1.0
	if is_watered_today:
		advance = 1.5
	growth_progress = minf(growth_progress + advance, float(crop_data.growth_days))
	is_watered_today = false
	if growth_progress >= float(crop_data.growth_days):
		lifecycle_state = LifecycleState.MATURE
	return old_stage != get_current_stage() or old_state != lifecycle_state


func is_mature() -> bool:
	return lifecycle_state == LifecycleState.MATURE


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_valid_lifecycle_state(value: int) -> bool:
	return value >= LifecycleState.GROWING and value <= LifecycleState.WITHERED


func get_current_stage() -> int:
	var num_stages := get_stage_count()
	if crop_data == null or num_stages <= 0:
		return 0
	if crop_data.growth_days <= 0:
		return 0
	var ratio: float = growth_progress / float(crop_data.growth_days)
	var stage: int = int(ratio * (num_stages - 1))
	return clampi(stage, 0, num_stages - 1)


func get_stage_count() -> int:
	if crop_data == null:
		return 0
	if not crop_data.stage_scenes.is_empty():
		return crop_data.stage_scenes.size()
	return crop_data.stage_textures.size()
