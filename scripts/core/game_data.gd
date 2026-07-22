extends Node

const CropDataScript = preload("res://scripts/data/crop_data.gd")

var _crops = {}


func register_crop(data) -> bool:
	if data == null or data.crop_id.is_empty() or _crops.has(data.crop_id):
		push_error("Invalid or duplicate crop ID")
		return false
	_crops[data.crop_id] = data
	return true


func get_crop(id: String):
	return _crops.get(id, null)


func get_all_crops() -> Array:
	var result := []
	for crop in _crops.values():
		result.append(crop)
	return result
