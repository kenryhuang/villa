class_name BuildingData
extends Resource

const SCENE_PATHS := {
	"barn": "res://scenes/buildings/barn.tscn",
	"greenhouse": "res://scenes/buildings/greenhouse.tscn",
	"waterwheel": "res://scenes/buildings/waterwheel.tscn",
	"windmill": "res://scenes/buildings/windmill.tscn",
	"chicken_coop": "res://scenes/buildings/chicken_coop.tscn",
	"beehive": "res://scenes/buildings/beehive.tscn",
	"well": "res://scenes/buildings/well.tscn",
	"workbench": "res://scenes/buildings/workbench.tscn",
	"stone_kiln": "res://scenes/buildings/stone_kiln.tscn",
	"furnace": "res://scenes/buildings/furnace.tscn",
	"food_workshop": "res://scenes/buildings/food_workshop.tscn",
	"textile_machine": "res://scenes/buildings/textile_machine.tscn",
	"lumberyard": "res://scenes/buildings/lumberyard.tscn",
	"quarry": "res://scenes/buildings/quarry.tscn",
	"mine": "res://scenes/buildings/mine.tscn",
	"lamp": "res://scenes/buildings/lamp.tscn",
	"fence": "res://scenes/buildings/fence.tscn",
}

const VISUAL_SIZES := {
	"barn": Vector2(2.3, 2.2),
	"greenhouse": Vector2(3.2, 2.2),
	"waterwheel": Vector2(2.2, 2.0),
	"windmill": Vector2(2.2, 3.4),
	"chicken_coop": Vector2(2.1, 1.8),
	"beehive": Vector2(0.9, 1.15),
	"well": Vector2(1.15, 1.35),
	"workbench": Vector2(1.1, 0.9),
	"stone_kiln": Vector2(1.8, 1.7),
	"furnace": Vector2(2.0, 2.0),
	"food_workshop": Vector2(2.4, 2.0),
	"textile_machine": Vector2(1.8, 1.6),
	"lumberyard": Vector2(2.6, 2.0),
	"quarry": Vector2(2.6, 1.8),
	"mine": Vector2(2.8, 2.2),
	"lamp": Vector2(0.65, 1.8),
	"fence": Vector2(1.05, 0.85),
}
const PAINTED_PRODUCTION_IDS := [
	"stone_kiln",
	"furnace",
	"food_workshop",
	"textile_machine",
	"lumberyard",
	"quarry",
	"mine",
]
const GROUND_ANCHORS := {
	"stone_kiln": Vector2(0.5, 0.9375),
	"furnace": Vector2(0.5, 0.9375),
	"food_workshop": Vector2(0.5, 0.9375),
	"textile_machine": Vector2(0.5, 0.9375),
	"lumberyard": Vector2(0.5, 0.9375),
	"quarry": Vector2(0.5, 0.9375),
	"mine": Vector2(0.5, 0.9375),
}
const ACTIVITY_FPS := {
	"stone_kiln": 4.0,
	"furnace": 5.0,
	"food_workshop": 4.0,
	"textile_machine": 6.0,
	"lumberyard": 6.0,
	"quarry": 3.0,
	"mine": 3.0,
}
const PRODUCTION_YARD_STYLES := ["timber", "masonry", "industrial"]

@export var building_id := ""
@export var display_name := ""
@export var category := "basic"
@export var palette_order := 0
@export var footprint := Vector2i.ZERO
@export var cost: Dictionary = {}
@export_multiline var description := ""
@export var effect_type := ""
@export var effect_value := 0
@export var station_id := ""
@export var effect_config: Dictionary = {}
@export_file("*.tscn") var scene_path := ""
@export var visual_size := Vector2.ZERO
@export var ground_anchor_uv := Vector2(0.5, 1.0)
@export var activity_fps := 4.0
@export var production_yard: Dictionary = {}

var effect: String:
	get:
		return effect_type
	set(value):
		effect_type = value

var visual_width: float:
	get:
		return visual_size.x
	set(value):
		visual_size.x = value

var visual_height: float:
	get:
		return visual_size.y
	set(value):
		visual_size.y = value


static func from_dictionary(source: Dictionary) -> BuildingData:
	var data := BuildingData.new()
	if source.is_empty():
		return data
	data.building_id = str(source.get("id", ""))
	data.display_name = str(source.get("name", ""))
	data.category = str(source.get("category", "basic"))
	data.palette_order = int(source.get("palette_order", 0))
	data.footprint = Vector2i(
		int(source.get("footprint_x", 0)),
		int(source.get("footprint_z", 0))
	)
	data.cost = source.get("cost", {}).duplicate(true)
	data.description = str(source.get("description", ""))
	data.effect_type = str(source.get("effect", ""))
	data.effect_value = int(source.get("effect_value", 0))
	data.station_id = str(source.get("station", ""))
	data.effect_config = source.get("effect_config", {}).duplicate(true)
	data.scene_path = str(SCENE_PATHS.get(data.building_id, ""))
	data.visual_size = VISUAL_SIZES.get(data.building_id, Vector2.ZERO)
	data.ground_anchor_uv = GROUND_ANCHORS.get(
		data.building_id,
		Vector2(0.5, 1.0)
	)
	data.activity_fps = float(ACTIVITY_FPS.get(data.building_id, 4.0))
	data.production_yard = source.get("production_yard", {}).duplicate(true)
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
		and _is_valid_production_yard()
	)


func has_production_yard() -> bool:
	return not production_yard.is_empty()


func production_yard_size() -> Vector2i:
	return production_yard.get("size", footprint) as Vector2i


func structure_footprint() -> Vector2i:
	return production_yard.get("structure_footprint", footprint) as Vector2i


func production_yard_style() -> String:
	return str(production_yard.get("style", ""))


func production_yard_offset() -> Vector3:
	return Vector3(0.0, 0.0, float(production_yard.get("building_offset_z", 0.0)))


func production_yard_output_capacity() -> int:
	return int(production_yard.get("output_capacity", 0))


func _is_valid_production_yard() -> bool:
	if production_yard.is_empty():
		return true
	var yard_size: Variant = production_yard.get("size")
	var structure_size: Variant = production_yard.get("structure_footprint")
	var offset: Variant = production_yard.get("building_offset_z")
	var output_capacity: Variant = production_yard.get("output_capacity")
	if not yard_size is Vector2i or not structure_size is Vector2i:
		return false
	if yard_size != footprint or yard_size.x not in [3, 4] or yard_size.y != yard_size.x:
		return false
	if structure_size.x <= 0 or structure_size.y <= 0:
		return false
	if structure_size.x > yard_size.x or structure_size.y > yard_size.y:
		return false
	if production_yard_style() not in PRODUCTION_YARD_STYLES:
		return false
	if typeof(offset) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(offset)):
		return false
	if float(offset) > 0.0 or float(offset) < -2.0:
		return false
	if typeof(output_capacity) != TYPE_INT or int(output_capacity) <= 0:
		return false
	return true
