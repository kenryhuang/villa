extends Node3D

const BuildingDataScript := preload("res://scripts/data/building_data.gd")
const GameDataScript := preload("res://scripts/core/game_data.gd")
const ProducerStateScript := preload("res://scripts/data/producer_state.gd")

const BUILDING_IDS := [
	"stone_kiln",
	"furnace",
	"food_workshop",
	"textile_machine",
	"lumberyard",
	"quarry",
	"mine",
]
const GALLERY_POSITIONS := [
	Vector3(-8.4, 0.02, -3.4),
	Vector3(-2.8, 0.02, -3.4),
	Vector3(2.8, 0.02, -3.4),
	Vector3(8.4, 0.02, -3.4),
	Vector3(-6.0, 0.02, 2.4),
	Vector3(0.0, 0.02, 2.4),
	Vector3(6.0, 0.02, 2.4),
]
const CONSTRUCTION_POSITIONS := [
	Vector3(-5.5, 0.02, 1.0),
	Vector3(0.0, 0.02, 1.0),
	Vector3(5.5, 0.02, 1.0),
]
const CONSTRUCTION_STAGES := [
	BuildingInstance.ConstructionStage.FOUNDATION,
	BuildingInstance.ConstructionStage.FRAME,
	BuildingInstance.ConstructionStage.HALF_BUILT,
]

var completed_buildings: Array[BuildingInstance] = []
var staged_buildings: Array[BuildingInstance] = []


func _ready() -> void:
	_build_completed_gallery()
	_build_construction_gallery()
	set_capture_mode("complete")


func set_capture_mode(mode: String) -> void:
	var show_construction := mode == "construction"
	get_node("CompletedGallery").visible = not show_construction
	get_node("ConstructionGallery").visible = show_construction
	for building in completed_buildings:
		_set_building_active(building, mode == "active")
	var title := get_node("UI/Title") as Label
	title.text = {
		"complete": "生产建筑 · 完成形态",
		"construction": "石窑 · 三阶段建造",
		"idle": "生产建筑 · 待机",
		"active": "生产建筑 · 工作中",
	}.get(mode, "生产建筑")


func gallery_contract_passes() -> bool:
	if completed_buildings.size() != BUILDING_IDS.size() or staged_buildings.size() != 3:
		return false
	for building in completed_buildings:
		if building.construction_stage != BuildingInstance.ConstructionStage.COMPLETE:
			return false
		var back := building.get_node_or_null("VisualRoot/BackLayer") as Sprite3D
		var front := building.get_node_or_null("VisualRoot/FrontLayer") as Sprite3D
		var activity := building.get_node_or_null("VisualRoot/ActivityLayer") as BuildingActivityVisual
		var fallback_body := building.get_node_or_null("VisualRoot/FallbackBody") as MeshInstance3D
		var fallback_roof := building.get_node_or_null("VisualRoot/FallbackRoof") as MeshInstance3D
		if (
			back == null or back.texture == null or not back.visible
			or front == null or front.texture == null or not front.visible
			or activity == null or not activity.is_configured()
			or fallback_body == null or fallback_body.visible
			or fallback_roof == null or fallback_roof.visible
		):
			return false
	for index in staged_buildings.size():
		var staged := staged_buildings[index]
		var layer := staged.get_node_or_null("VisualRoot/ConstructionLayer") as Sprite3D
		if staged.construction_stage != CONSTRUCTION_STAGES[index]:
			return false
		if layer == null or layer.texture == null or not layer.visible:
			return false
	return true


func idle_activity_is_hidden() -> bool:
	for building in completed_buildings:
		var activity := building.get_node("VisualRoot/ActivityLayer") as BuildingActivityVisual
		if activity.visible or activity.is_active():
			return false
	return true


func active_activity_is_visible() -> bool:
	for building in completed_buildings:
		var activity := building.get_node("VisualRoot/ActivityLayer") as BuildingActivityVisual
		if not activity.visible or not activity.is_active() or activity.frame == 0:
			return false
	return true


func _build_completed_gallery() -> void:
	var parent := get_node("CompletedGallery") as Node3D
	for index in BUILDING_IDS.size():
		var building := _new_building(BUILDING_IDS[index])
		building.position = GALLERY_POSITIONS[index]
		parent.add_child(building)
		completed_buildings.append(building)
		_add_label(parent, building.data.display_name, building.position + Vector3(0.0, 0.15, 1.65))


func _build_construction_gallery() -> void:
	var parent := get_node("ConstructionGallery") as Node3D
	for index in CONSTRUCTION_STAGES.size():
		var building := _new_building("stone_kiln")
		building.position = CONSTRUCTION_POSITIONS[index]
		parent.add_child(building)
		building.start_construction()
		for _advance in index:
			building.advance_construction_stage()
		staged_buildings.append(building)
		_add_label(
			parent,
			["地基", "框架", "半成品"][index],
			building.position + Vector3(0.0, 0.15, 1.65)
		)


func _new_building(building_id: String) -> BuildingInstance:
	var definition := BuildingDataScript.from_dictionary(GameDataScript.get_building(building_id))
	var building := BuildingInstance.new()
	building.configure(definition, 0, 0, [])
	building.set_process(false)
	return building


func _set_building_active(building: BuildingInstance, active: bool) -> void:
	if not active:
		building.set_economy_indicator("")
		var idle_visual := building.get_node("VisualRoot/ActivityLayer") as BuildingActivityVisual
		idle_visual.set_active(false)
		idle_visual.advance_animation(0.2)
		return
	if building.producer_state == null:
		building.producer_state = ProducerStateScript.new(building.building_id)
	if building.data.effect_type == "crafting":
		building.producer_state.jobs.assign([{
			"recipe_id": "gallery_activity",
			"batches": 1,
			"remaining_minutes": 60,
			"status": "running",
		}])
	building.set_economy_indicator("")
	building.sync_activity_visual()
	var activity := building.get_node("VisualRoot/ActivityLayer") as BuildingActivityVisual
	activity.advance_animation(maxf(0.36, 1.1 / building.data.activity_fps))


func _add_label(parent: Node3D, text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 34
	label.modulate = Color(0.22, 0.16, 0.1)
	label.outline_size = 7
	label.outline_modulate = Color(0.96, 0.91, 0.77, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
