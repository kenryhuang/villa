class_name CropInstance
extends RefCounted

const CropDataScript = preload("res://scripts/data/crop_data.gd")

var crop_data
var growth_progress := 0.0
var is_watered_today := false
var harvest_count := 0


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
	}


func from_dict(data: Dictionary) -> bool:
	if crop_data == null or str(data.get("crop_id", "")) != str(crop_data.crop_id):
		return false
	var progress_value: Variant = data.get("growth_progress", 0.0)
	var count_value: Variant = data.get("harvest_count", 0)
	if not progress_value is int and not progress_value is float:
		return false
	if not count_value is int and not count_value is float:
		return false
	var progress := float(progress_value)
	var count_number := float(count_value)
	if not is_finite(progress) or progress < 0.0:
		return false
	if not is_finite(count_number) or count_number < 0.0 or count_number != floorf(count_number):
		return false
	growth_progress = minf(progress, float(crop_data.growth_days))
	is_watered_today = bool(data.get("is_watered_today", false))
	harvest_count = int(count_number)
	return true


func advance_growth() -> bool:
	if crop_data == null or is_mature():
		return false
	var advance := 1.0
	if is_watered_today:
		advance = 1.5
	growth_progress = minf(growth_progress + advance, float(crop_data.growth_days))
	is_watered_today = false
	return is_mature()


func is_mature() -> bool:
	return crop_data != null and growth_progress >= float(crop_data.growth_days)


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
