extends RefCounted

const Crops = preload("res://scripts/core/crop_catalog.gd")
const Buildings = preload("res://scripts/core/building_catalog.gd")
const Data = preload("res://scripts/core/game_data.gd")
static var _icons: Dictionary = {}

static func entries(category: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	match category:
		"farmland":
			rows.assign([{"id": "dry", "name": "旱地", "detail": "普通耕地"}, {"id": "paddy", "name": "水田", "detail": "持续灌溉"}])
		"seed":
			for crop in Crops.default_crop_definitions():
				var seasons: Array[String] = []
				for season in crop.seasons:
					seasons.append(["春", "夏", "秋", "冬"][season])
				rows.append({"id": crop.plant_item_id, "name": Data.get_item(crop.plant_item_id).name, "detail": "温室" if seasons.is_empty() else " / ".join(seasons), "icon": item_icon(crop.plant_item_id)})
		"building":
			for building_id in Buildings.all_building_ids():
				var data: Dictionary = Data.get_building(building_id)
				rows.append({"id": building_id, "name": data.name, "detail": "%d × %d 格" % [data.footprint_x, data.footprint_z], "icon": _load_icon("res://assets/buildings/painted/%s/%s_back.png" % [building_id, building_id])})
	return rows

static func item_icon(item_id: String) -> Texture2D:
	var item: Variant = Data.get_item(item_id)
	if item != null and item.get("category","") == "fish":
		return _load_icon("res://assets/ui/material_icons/fish.svg")
	var crop_id := item_id.trim_suffix("_seed").trim_suffix("_sapling")
	var path := "res://assets/crops/%s/painted/stage_3/variant_0_front.png" % crop_id
	if ResourceLoader.exists(path):
		return _load_icon(path)
	var material_id := "iron" if item_id == "iron_ingot" else item_id
	return _load_icon("res://assets/ui/material_icons/%s.svg" % material_id)

static func _load_icon(path: String) -> Texture2D:
	if not _icons.has(path):
		_icons[path] = load(path) if ResourceLoader.exists(path) else null
	return _icons[path]
