class_name BuildingData
extends Resource

const SCENE_PATHS := {
	"barn": "res://scenes/buildings/barn.tscn",
	"greenhouse": "res://scenes/buildings/greenhouse.tscn",
	"windmill": "res://scenes/buildings/windmill.tscn",
	"chicken_coop": "res://scenes/buildings/chicken_coop.tscn",
	"beehive": "res://scenes/buildings/beehive.tscn",
	"well": "res://scenes/buildings/well.tscn",
	"workbench": "res://scenes/buildings/workbench.tscn",
	"lamp": "res://scenes/buildings/lamp.tscn",
	"fence": "res://scenes/buildings/fence.tscn",
}

const VISUAL_SIZES := {
	"barn": Vector2(2.3, 2.2),
	"greenhouse": Vector2(3.2, 2.2),
	"windmill": Vector2(2.2, 3.4),
	"chicken_coop": Vector2(2.1, 1.8),
	"beehive": Vector2(0.9, 1.15),
	"well": Vector2(1.15, 1.35),
	"workbench": Vector2(1.1, 0.9),
	"lamp": Vector2(0.65, 1.8),
	"fence": Vector2(1.05, 0.85),
}

@export var building_id := ""
@export var display_name := ""
@export var footprint := Vector2i.ZERO
@export var cost: Dictionary = {}
@export_multiline var description := ""
@export var effect := ""
@export var effect_value := 0
@export_file("*.tscn") var scene_path := ""
@export var visual_size := Vector2.ZERO


static func from_dictionary(source: Dictionary) -> BuildingData:
	var data := BuildingData.new()
	if source.is_empty():
		return data
	data.building_id = str(source.get("id", ""))
	data.display_name = str(source.get("name", ""))
	data.footprint = Vector2i(
		int(source.get("footprint_x", 0)),
		int(source.get("footprint_z", 0))
	)
	data.cost = source.get("cost", {}).duplicate(true)
	data.description = str(source.get("description", ""))
	data.effect = str(source.get("effect", ""))
	data.effect_value = int(source.get("effect_value", 0))
	data.scene_path = str(SCENE_PATHS.get(data.building_id, ""))
	data.visual_size = VISUAL_SIZES.get(data.building_id, Vector2.ZERO)
	return data


func is_valid() -> bool:
	return (
		not building_id.is_empty()
		and not display_name.is_empty()
		and footprint.x > 0
		and footprint.y > 0
		and not scene_path.is_empty()
		and visual_size.x > 0.0
		and visual_size.y > 0.0
		and ResourceLoader.exists(scene_path)
	)

