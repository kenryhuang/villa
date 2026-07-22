class_name CropInstance
extends RefCounted

const CropDataScript = preload("res://scripts/data/crop_data.gd")

var crop_data
var growth_progress := 0.0
var is_watered_today := false


func advance_growth() -> bool:
	if crop_data == null:
		return false
	var advance := 1.0
	if is_watered_today:
		advance = 1.5
	growth_progress += advance
	is_watered_today = false
	return growth_progress >= crop_data.growth_days


func get_current_stage() -> int:
	if crop_data == null or crop_data.stage_textures.is_empty():
		return 0
	if crop_data.growth_days <= 0:
		return 0
	var ratio: float = growth_progress / float(crop_data.growth_days)
	var num_stages: int = crop_data.stage_textures.size()
	var stage: int = int(ratio * (num_stages - 1))
	return clampi(stage, 0, num_stages - 1)
