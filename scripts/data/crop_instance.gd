class_name CropInstance
extends RefCounted

const CropDataScript = preload("res://scripts/data/crop_data.gd")

var crop_data
var growth_progress := 0.0
var is_watered_today := false


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
