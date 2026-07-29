class_name PlayerActionController
extends Node

signal selection_changed(index: int, label: String)
signal inventory_changed

enum Action {
	NONE,
	BUILD,
	INTERACT,
	HARVEST,
	PLANT,
	TOOL,
}

const SEED_SLOT := 5
const SEED_ITEM_ID := "grain_seed"
const CROP_ID := "grain"
const SLOT_LABELS := ["锄头", "浇水壶", "斧头", "镐", "鱼竿", "谷物种子"]
const TOOL_BY_SLOT := [
	ToolSystem.ToolType.HOE,
	ToolSystem.ToolType.WATERING_CAN,
	ToolSystem.ToolType.AXE,
	ToolSystem.ToolType.PICKAXE,
	ToolSystem.ToolType.FISHING_ROD,
]
const INTERACTION_MASK := 4 | 64 | 128
const GROUND_MASK := 1
const VALID_COLOR := Color(0.25, 0.9, 0.38, 0.5)
const INVALID_COLOR := Color(0.95, 0.2, 0.18, 0.5)
const MATURE_COLOR := Color(1.0, 0.72, 0.08, 0.58)
const WATER_COLOR := Color(0.2, 0.58, 1.0, 0.52)

var player_ref: Variant
var grid_system: Variant
var farming_system: Variant
var building_system: Variant
var tool_system: Variant
var inventory_system: Variant
var crop_data_override: CropData

var _selected_slot := 0
var _pointer_position: Variant


static func resolve_action(
	build_mode: bool,
	has_interaction_target: bool,
	has_cell: bool,
	crop_mature: bool,
	selected_slot: int
) -> Action:
	if build_mode:
		return Action.BUILD
	if has_interaction_target:
		return Action.INTERACT
	if not has_cell:
		return Action.NONE
	if crop_mature:
		return Action.HARVEST
	if selected_slot == SEED_SLOT:
		return Action.PLANT
	if selected_slot >= 0 and selected_slot < TOOL_BY_SLOT.size():
		return Action.TOOL
	return Action.NONE


func configure(
	player: Variant,
	grid: Variant,
	farming: Variant,
	building: Variant,
	tools: Variant,
	inventory: Variant
) -> void:
	player_ref = player
	grid_system = grid
	farming_system = farming
	building_system = building
	tool_system = tools
	inventory_system = inventory
	select_slot(_selected_slot)


func select_slot(index: int) -> bool:
	if index < 0 or index >= SLOT_LABELS.size():
		return false
	_selected_slot = index
	if index < TOOL_BY_SLOT.size() and tool_system != null:
		tool_system.switch_tool(TOOL_BY_SLOT[index])
	selection_changed.emit(index, SLOT_LABELS[index])
	return true


func deselect_slot() -> bool:
	if _selected_slot < 0:
		return false
	_selected_slot = -1
	if grid_system != null:
		grid_system.clear_highlights()
	selection_changed.emit(-1, "未选择工具")
	return true


func get_selected_slot() -> int:
	return _selected_slot


func slot_from_key(keycode: Key) -> int:
	match keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		KEY_6:
			return 5
	return -1


func perform_cell_action(cell: GridCell) -> bool:
	if cell == null or _selected_slot < 0:
		return false
	if _is_mature(cell):
		return _harvest(cell)
	if _selected_slot == SEED_SLOT:
		return _plant(cell)
	if _selected_slot in [0, 1] and tool_system != null:
		return bool(tool_system.use_tool_on(cell))
	return false


func perform_build_action(gx: int, gz: int) -> BuildingInstance:
	if building_system == null or not building_system.is_in_build_mode():
		return null
	return building_system.place_selected_building(gx, gz)


func perform_target_interaction(target: Node) -> bool:
	if target == null:
		return false
	if target.has_method("start_dialogue"):
		target.start_dialogue()
		return true
	if target.has_method("interact"):
		target.interact(player_ref)
		return true
	if target.has_method("collect"):
		target.collect()
		return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer_position = event.position


func _process(_delta: float) -> void:
	if grid_system == null:
		return
	if _pointer_over_ui():
		grid_system.clear_highlights()
		return
	var ground_point = _raycast_to_ground(_effective_pointer_position())
	if building_system != null and building_system.is_in_build_mode():
		grid_system.clear_highlights()
		if ground_point is Vector3:
			building_system.update_preview_position(ground_point.x, ground_point.z)
		return
	if _selected_slot < 0:
		grid_system.clear_highlights()
		return
	if not ground_point is Vector3:
		grid_system.clear_highlights()
		return
	var cell = grid_system.get_cell_at_world(ground_point.x, ground_point.z)
	if cell == null:
		grid_system.clear_highlights()
		return
	grid_system.highlight_cell(cell.gx, cell.gz, _highlight_color(cell, ground_point))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := slot_from_key(event.keycode)
		if slot >= 0 and select_slot(slot):
			get_viewport().set_input_as_handled()
			return
		if (
			event.keycode == KEY_ESCAPE
			and building_system != null
			and building_system.is_in_build_mode()
		):
			building_system.exit_preview_mode()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and deselect_slot():
			get_viewport().set_input_as_handled()
			return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and _perform_pointer_action(event.position)
	):
		get_viewport().set_input_as_handled()


func _perform_pointer_action(pointer_position: Variant = null) -> bool:
	if _pointer_over_ui():
		return false
	var ground_point = _raycast_to_ground(pointer_position)
	if building_system != null and building_system.is_in_build_mode():
		if not ground_point is Vector3 or grid_system == null:
			return false
		var grid_position = grid_system.world_to_grid(ground_point.x, ground_point.z)
		return perform_build_action(grid_position.x, grid_position.y) != null

	var interaction_hit := _raycast_to_interaction(pointer_position)
	if not interaction_hit.is_empty():
		var hit_position: Vector3 = interaction_hit.get("position", Vector3.ZERO)
		if _point_in_player_range(hit_position):
			return perform_target_interaction(interaction_hit.get("target"))

	if not ground_point is Vector3 or grid_system == null:
		return false
	if not _point_in_player_range(ground_point):
		return false
	if _selected_slot < 0:
		return false
	return perform_cell_action(
		grid_system.get_cell_at_world(ground_point.x, ground_point.z)
	)


func _raycast_to_interaction(pointer_position: Variant = null) -> Dictionary:
	var ray := _camera_ray(pointer_position)
	if ray.is_empty() or get_viewport().world_3d == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(ray.origin, ray.finish)
	query.collision_mask = INTERACTION_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = true
	if player_ref is CollisionObject3D:
		query.exclude = [player_ref.get_rid()]
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var target := _find_interaction_target(hit.get("collider"))
	if target == null:
		return {}
	return {
		"target": target,
		"position": hit.get("position", Vector3.ZERO),
	}


func _raycast_to_ground(pointer_position: Variant = null) -> Variant:
	var ray := _camera_ray(pointer_position)
	if ray.is_empty():
		return null
	if get_viewport().world_3d != null:
		var query := PhysicsRayQueryParameters3D.create(ray.origin, ray.finish)
		query.collision_mask = GROUND_MASK
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if player_ref is CollisionObject3D:
			query.exclude = [player_ref.get_rid()]
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			return hit.get("position")
	var direction: Vector3 = ray.direction
	if is_zero_approx(direction.y):
		return null
	var ratio: float = -float(ray.origin.y) / direction.y
	return ray.origin + direction * ratio if ratio >= 0.0 else null


func _camera_ray(pointer_position: Variant = null) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var mouse_position: Vector2 = _effective_pointer_position(pointer_position)
	var origin := camera.project_ray_origin(mouse_position)
	var direction := camera.project_ray_normal(mouse_position)
	return {
		"origin": origin,
		"direction": direction,
		"finish": origin + direction * maxf(camera.far, 100.0),
	}


func _effective_pointer_position(override_position: Variant = null) -> Vector2:
	if override_position is Vector2:
		return override_position
	if _pointer_position is Vector2:
		return _pointer_position
	return get_viewport().get_mouse_position()


func _find_interaction_target(node: Node) -> Node:
	var current := node
	while current != null:
		if (
			current.has_method("interact")
			or current.has_method("start_dialogue")
			or current.has_method("collect")
		):
			return current
		current = current.get_parent()
	return null


func _point_in_player_range(point: Vector3) -> bool:
	if player_ref == null:
		return false
	var maximum_range := float(player_ref.interaction_range)
	return Vector2(player_ref.global_position.x, player_ref.global_position.z).distance_to(
		Vector2(point.x, point.z)
	) <= maximum_range


func _pointer_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _highlight_color(cell: GridCell, ground_point: Vector3) -> Color:
	if not _point_in_player_range(ground_point):
		return INVALID_COLOR
	if _is_mature(cell):
		return MATURE_COLOR
	if _selected_slot == 1:
		return (
			WATER_COLOR
			if cell.state in [GridCell.State.FARMLAND, GridCell.State.PLANTED]
			else INVALID_COLOR
		)
	if _selected_slot == SEED_SLOT:
		var crop_data := _get_crop_data()
		var has_seed: bool = (
			inventory_system != null
			and inventory_system.has_item(SEED_ITEM_ID, 1)
		)
		return (
			VALID_COLOR
			if has_seed
			and crop_data != null
			and farming_system != null
			and farming_system.can_plant(cell, crop_data)
			else INVALID_COLOR
		)
	if _selected_slot == 0:
		return (
			VALID_COLOR
			if grid_system.can_farm_at(cell.gx, cell.gz)
			else INVALID_COLOR
		)
	return INVALID_COLOR


func _plant(cell: GridCell) -> bool:
	if farming_system == null or inventory_system == null:
		return false
	var crop_data := _get_crop_data()
	if crop_data == null or not farming_system.can_plant(cell, crop_data):
		return false
	if not inventory_system.remove_item(SEED_ITEM_ID, 1):
		return false
	var planted = farming_system.plant(cell, crop_data)
	if planted == null:
		inventory_system.add_item(SEED_ITEM_ID, 1)
		return false
	inventory_changed.emit()
	return true


func _harvest(cell: GridCell) -> bool:
	if farming_system == null or inventory_system == null:
		return false
	if not inventory_system.can_add_item(CROP_ID, 1):
		return false
	var result: Dictionary = farming_system.harvest(cell)
	if result.is_empty():
		return false
	for item_id in result.get("items", []):
		if not inventory_system.add_item(str(item_id), 1):
			return false
	inventory_changed.emit()
	return true


func _is_mature(cell: GridCell) -> bool:
	return (
		cell.state == GridCell.State.PLANTED
		and cell.crop_instance != null
		and cell.crop_instance.is_mature()
	)


func _get_crop_data() -> CropData:
	if crop_data_override != null:
		return crop_data_override
	var game_data := get_node_or_null("/root/GameData")
	return game_data.get_crop(CROP_ID) if game_data else null
