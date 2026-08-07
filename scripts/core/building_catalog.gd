class_name BuildingCatalog
extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const CATEGORY_ORDER: Array[String] = [
	"basic", "production", "farming", "resource", "decoration",
]

static func categories() -> Array[String]:
	return CATEGORY_ORDER.duplicate()


static func building_ids_for_category(category_id: String) -> Array[String]:
	if category_id not in CATEGORY_ORDER:
		return []
	var rows: Array[Dictionary] = []
	for source in GameDataScript.get_all_buildings():
		if str(source.get("category", "basic")) == category_id:
			rows.append(source)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left_order := int(a.get("palette_order", 0))
		var right_order := int(b.get("palette_order", 0))
		return str(a.get("id", "")) < str(b.get("id", "")) if left_order == right_order else left_order < right_order
	)
	var ids: Array[String] = []
	for row in rows:
		ids.append(str(row.get("id", "")))
	return ids


static func all_building_ids() -> Array[String]:
	var ids: Array[String] = []
	for category_id in CATEGORY_ORDER:
		ids.append_array(building_ids_for_category(category_id))
	return ids
