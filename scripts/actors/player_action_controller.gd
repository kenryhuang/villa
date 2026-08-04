class_name PlayerActionController
extends Node

signal selection_changed(index: int, label: String)
signal inventory_changed
signal mode_changed(mode: ActionMode)
signal palette_changed(mode: ActionMode, selected_index: int)
signal build_feedback_requested(message: String, details: Dictionary)
signal tree_hover_changed(target: Node, allowed: bool)
signal gather_rejected(target: Node, reason: String)

enum Action {
	NONE,
	BUILD,
	INTERACT,
	HARVEST,
	PLANT,
	TOOL,
}

enum ActionMode {
	FARMING,
	BUILDING,
}

const SEED_SLOT := 5
const SLOT_LABELS := ["锄头", "浇水壶", "斧头", "镐", "鱼竿", "种苗"]
const BUILDING_IDS: Array[String] = [
	"barn",
	"greenhouse",
	"windmill",
	"chicken_coop",
	"beehive",
	"well",
	"workbench",
	"lamp",
	"fence",
]
const BUILDING_LABELS: Array[String] = [
	"谷仓",
	"温室",
	"风车",
	"鸡舍",
	"蜂箱",
	"水井",
	"工作台",
	"路灯",
	"围栏",
]
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
var gathering_controller: Variant
var crop_data_override: CropData
var _event_bus: Node

var _action_mode := ActionMode.FARMING
var _selected_slot := 0
var _last_farming_slot := 0
var _last_building_slot := 0
var _pointer_position: Variant
var _hovered_tree: Node
var _hovered_tree_allowed := false


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
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	select_mode_slot(_selected_slot)


func configure_gathering(controller: Variant) -> bool:
	if (
		controller == null
		or not controller.has_method("request_gather")
		or not controller.has_method("cancel_current")
		or not controller.has_method("has_active_command")
	):
		return false
	gathering_controller = controller
	var callback := Callable(self, "_on_gathering_started")
	if controller.has_signal("gather_started") and not controller.is_connected(
		"gather_started", callback
	):
		controller.connect("gather_started", callback)
	return true


func sync_auto_equipped_tool(tool_id: String) -> bool:
	var slot := 2 if tool_id == "axe" else (3 if tool_id == "pickaxe" else -1)
	if slot < 0:
		return false
	_action_mode = ActionMode.FARMING
	_selected_slot = slot
	_last_farming_slot = slot
	if not should_show_cell_highlight() and grid_system != null:
		grid_system.clear_highlights()
	selection_changed.emit(slot, _farming_slot_label(slot))
	mode_changed.emit(_action_mode)
	palette_changed.emit(_action_mode, slot)
	return true


func _on_gathering_started(_target: Node, preview: Dictionary) -> void:
	_clear_tree_hover()
	sync_auto_equipped_tool(str(preview.get("tool_id", "")))


func select_slot(index: int) -> bool:
	if _action_mode != ActionMode.FARMING:
		switch_mode(ActionMode.FARMING)
	return select_mode_slot(index)


func switch_mode(mode: ActionMode) -> bool:
	_clear_tree_hover()
	if mode not in [ActionMode.FARMING, ActionMode.BUILDING]:
		return false
	_cancel_gathering("mode_changed")
	if building_system != null and building_system.is_in_build_mode():
		building_system.exit_preview_mode()
	if grid_system != null:
		grid_system.clear_highlights()
	_action_mode = mode
	_selected_slot = (
		_last_farming_slot
		if _action_mode == ActionMode.FARMING
		else _last_building_slot
	)
	var activated := _activate_current_slot()
	mode_changed.emit(_action_mode)
	palette_changed.emit(_action_mode, _selected_slot)
	return activated or (_action_mode == ActionMode.BUILDING and _selected_slot < 0)


func get_action_mode() -> ActionMode:
	return _action_mode


func select_mode_slot(index: int) -> bool:
	var labels := SLOT_LABELS if _action_mode == ActionMode.FARMING else BUILDING_LABELS
	if index < 0 or index >= labels.size():
		return false
	_cancel_gathering("tool_changed")
	_clear_tree_hover()
	if _action_mode == ActionMode.BUILDING:
		var diagnostic := get_building_resource_diagnostic(index)
		if not bool(diagnostic.get("allowed", false)):
			_emit_build_feedback(diagnostic, "BuildSelectionRejected")
			return false
	_selected_slot = index
	if _action_mode == ActionMode.FARMING:
		_last_farming_slot = index
		if not should_show_cell_highlight() and grid_system != null:
			grid_system.clear_highlights()
	else:
		_last_building_slot = index
	var activated := _activate_current_slot()
	if activated:
		palette_changed.emit(_action_mode, _selected_slot)
	return activated


func get_mode_selected_slot(mode: ActionMode) -> int:
	return _last_farming_slot if mode == ActionMode.FARMING else _last_building_slot


func should_show_cell_highlight() -> bool:
	return (
		_action_mode == ActionMode.FARMING
		and _selected_slot >= 0
		and _selected_slot != 2
	)


func get_building_resource_diagnostic(index: int) -> Dictionary:
	if index < 0 or index >= BUILDING_IDS.size() or building_system == null:
		return {
			"allowed": false,
			"code": "invalid_building",
			"message": "建筑不可用",
			"building_id": "",
			"missing_resources": {},
		}
	if building_system.has_method("diagnose_resources"):
		return building_system.diagnose_resources(BUILDING_IDS[index])
	return {
		"allowed": true,
		"code": "ok",
		"message": "",
		"building_id": BUILDING_IDS[index],
		"missing_resources": {},
	}


func cancel_current_selection() -> bool:
	_clear_tree_hover()
	var gathering_was_active := _gathering_is_active()
	_cancel_gathering("selection_cancelled")
	if _selected_slot < 0:
		return gathering_was_active
	if _action_mode == ActionMode.BUILDING:
		if building_system != null and building_system.is_in_build_mode():
			building_system.exit_preview_mode()
	else:
		if grid_system != null:
			grid_system.clear_highlights()
	_selected_slot = -1
	var empty_label := "未选择工具" if _action_mode == ActionMode.FARMING else "未选择建筑"
	selection_changed.emit(-1, empty_label)
	palette_changed.emit(_action_mode, -1)
	return true


func _activate_current_slot() -> bool:
	if _selected_slot < 0:
		return false
	if _action_mode == ActionMode.BUILDING:
		if grid_system != null:
			grid_system.clear_highlights()
		if building_system == null:
			return false
		var diagnostic := get_building_resource_diagnostic(_selected_slot)
		if not bool(diagnostic.get("allowed", false)):
			_selected_slot = -1
			selection_changed.emit(-1, "未选择建筑")
			_emit_build_feedback(diagnostic, "BuildSelectionRejected")
			return false
		var entered: bool = building_system.enter_preview_mode(BUILDING_IDS[_selected_slot])
		if entered:
			selection_changed.emit(
				_selected_slot,
				BUILDING_LABELS[_selected_slot]
			)
		return entered
	if building_system != null and building_system.is_in_build_mode():
		building_system.exit_preview_mode()
	if _selected_slot < TOOL_BY_SLOT.size() and tool_system != null:
		tool_system.switch_tool(TOOL_BY_SLOT[_selected_slot])
	selection_changed.emit(_selected_slot, _farming_slot_label(_selected_slot))
	return true


func _farming_slot_label(index: int) -> String:
	if index != SEED_SLOT:
		return SLOT_LABELS[index]
	var item_id := _get_active_plant_item_id()
	var game_data := get_node_or_null("/root/GameData") if is_inside_tree() else null
	var item_data = game_data.get_item(item_id) if game_data and not item_id.is_empty() else null
	return str(item_data.get("name", SLOT_LABELS[index])) if item_data else SLOT_LABELS[index]


func deselect_slot() -> bool:
	return cancel_current_selection()


func get_selected_slot() -> int:
	return _selected_slot


func slot_from_key(keycode: Key) -> int:
	var index := -1
	if keycode >= KEY_1 and keycode <= KEY_9:
		index = int(keycode - KEY_1)
	var maximum := SLOT_LABELS.size() if _action_mode == ActionMode.FARMING else BUILDING_IDS.size()
	return index if index >= 0 and index < maximum else -1


func perform_cell_action(cell: GridCell) -> bool:
	if _action_mode != ActionMode.FARMING or cell == null or _selected_slot < 0:
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
	var placed: BuildingInstance
	if building_system.has_method("try_place_selected_building"):
		var result: Dictionary = building_system.try_place_selected_building(gx, gz)
		placed = result.get("instance") as BuildingInstance
		if placed == null:
			var diagnostic: Dictionary = result.get("diagnostic", {})
			_emit_build_feedback(diagnostic, "BuildRejected")
			return null
	else:
		placed = building_system.place_selected_building(gx, gz)
		if placed == null:
			return null
	if (
		placed != null
		and _action_mode == ActionMode.BUILDING
		and _selected_slot >= 0
	):
		inventory_changed.emit()
		var next_diagnostic := get_building_resource_diagnostic(_selected_slot)
		if bool(next_diagnostic.get("allowed", false)):
			building_system.enter_preview_mode(BUILDING_IDS[_selected_slot])
		else:
			if building_system.is_in_build_mode():
				building_system.exit_preview_mode()
			_selected_slot = -1
			selection_changed.emit(-1, "未选择建筑")
			palette_changed.emit(_action_mode, -1)
			var exhausted := next_diagnostic.duplicate(true)
			exhausted.code = "continuous_build_exhausted"
			exhausted.message = "材料不足，已结束连续建造"
			_emit_build_feedback(exhausted, "BuildSelectionRejected")
	return placed


func perform_target_interaction(target: Node) -> bool:
	if target == null or _action_mode != ActionMode.FARMING:
		return false
	if target.has_method("can_gather"):
		if target.has_method("is_chop_eligible") and not bool(target.call("is_chop_eligible")):
			gather_rejected.emit(target, "tree_not_choppable")
			return false
		if gathering_controller == null:
			return false
		return bool(gathering_controller.call("request_gather", target))
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
		_clear_tree_hover()
		grid_system.clear_highlights()
		return
	_update_tree_hover_from_pointer()
	var ground_point = _raycast_to_ground(_effective_pointer_position())
	if _action_mode == ActionMode.BUILDING:
		grid_system.clear_highlights()
		if (
			_selected_slot >= 0
			and building_system != null
			and building_system.is_in_build_mode()
			and ground_point is Vector3
		):
			building_system.update_preview_position(ground_point.x, ground_point.z)
		return
	if not should_show_cell_highlight():
		grid_system.clear_highlights()
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
		if event.keycode == KEY_P and switch_mode(ActionMode.FARMING):
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B and switch_mode(ActionMode.BUILDING):
			get_viewport().set_input_as_handled()
			return
		var slot := slot_from_key(event.keycode)
		if slot >= 0:
			select_mode_slot(slot)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and cancel_current_selection():
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
	if _action_mode == ActionMode.BUILDING:
		if (
			_selected_slot < 0
			or building_system == null
			or not building_system.is_in_build_mode()
		):
			return false
		if not ground_point is Vector3 or grid_system == null:
			return false
		var grid_position = grid_system.world_to_grid(ground_point.x, ground_point.z)
		return perform_build_action(grid_position.x, grid_position.y) != null

	var interaction_hit := _raycast_to_interaction(pointer_position)
	if not interaction_hit.is_empty():
		var interaction_target: Node = interaction_hit.get("target")
		var hit_position: Vector3 = interaction_hit.get("position", Vector3.ZERO)
		if interaction_target != null and interaction_target.has_method("can_gather"):
			return perform_target_interaction(interaction_target)
		if _point_in_player_range(hit_position):
			return perform_target_interaction(interaction_target)

	if not ground_point is Vector3 or grid_system == null:
		return false
	_cancel_gathering("ground_clicked")
	if not _point_in_player_range(ground_point):
		return false
	if _selected_slot < 0:
		return false
	return perform_cell_action(
		grid_system.get_cell_at_world(ground_point.x, ground_point.z)
	)


func _update_tree_hover_from_pointer() -> void:
	if (
		_action_mode != ActionMode.FARMING
		or _selected_slot != 2
		or _gathering_is_active()
	):
		_clear_tree_hover()
		return
	var hit := _raycast_to_interaction(_effective_pointer_position())
	var target := hit.get("target") as Node
	if target == null or not target.has_method("is_chop_eligible"):
		_clear_tree_hover()
		return
	_update_tree_hover(target)


func _update_tree_hover(target: Node) -> void:
	if target == null or not target.has_method("is_chop_eligible"):
		_clear_tree_hover()
		return
	var allowed := bool(target.call("is_chop_eligible"))
	if _hovered_tree == target and _hovered_tree_allowed == allowed:
		return
	_hovered_tree = target
	_hovered_tree_allowed = allowed
	tree_hover_changed.emit(target, allowed)


func _clear_tree_hover() -> void:
	if _hovered_tree == null:
		return
	_hovered_tree = null
	_hovered_tree_allowed = false
	tree_hover_changed.emit(null, false)


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
			or current.has_method("can_gather")
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


func _emit_build_feedback(details: Dictionary, prefix: String) -> void:
	var normalized := details.duplicate(true)
	if normalized.is_empty():
		normalized = {
			"code": "unknown",
			"message": "无法建造",
			"building_id": "",
			"grid": Vector2i(-1, -1),
		}
	var message := str(normalized.get("message", "无法建造"))
	build_feedback_requested.emit(message, normalized)
	if OS.is_debug_build():
		print("[%s] building=%s grid=%s code=%s details=%s" % [
			prefix,
			str(normalized.get("building_id", "")),
			str(normalized.get("grid", Vector2i(-1, -1))),
			str(normalized.get("code", "unknown")),
			str(normalized),
		])


func _gathering_is_active() -> bool:
	return (
		gathering_controller != null
		and bool(gathering_controller.call("has_active_command"))
	)


func _cancel_gathering(reason: String) -> void:
	if _gathering_is_active():
		gathering_controller.call("cancel_current", reason)


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
		var plant_item_id := _get_active_plant_item_id()
		var crop_data := _get_crop_data(plant_item_id)
		var has_seed: bool = (
			inventory_system != null
			and not plant_item_id.is_empty()
			and inventory_system.has_item(plant_item_id, 1)
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
	var plant_item_id := _get_active_plant_item_id()
	var crop_data := _get_crop_data(plant_item_id)
	if crop_data == null or not farming_system.can_plant(cell, crop_data):
		return false
	var inventory_snapshot := {
		"slots": inventory_system.slots.duplicate(true),
		"quick_slot_mappings": inventory_system.quick_slot_mappings.duplicate(),
	}
	var owns_mapping_transaction := _begin_inventory_mapping_transaction()
	if not inventory_system.remove_item(plant_item_id, 1):
		_restore_inventory_snapshot(inventory_snapshot)
		_end_inventory_mapping_transaction(owns_mapping_transaction, false)
		return false
	var planted = farming_system.plant(cell, crop_data)
	if planted == null:
		inventory_system.add_item(plant_item_id, 1)
		_restore_inventory_snapshot(inventory_snapshot)
		_end_inventory_mapping_transaction(owns_mapping_transaction, false)
		return false
	_end_inventory_mapping_transaction(owns_mapping_transaction, true)
	inventory_changed.emit()
	return true


func _harvest(cell: GridCell) -> bool:
	if farming_system == null or inventory_system == null:
		return false
	var preview := _preview_harvest(cell)
	var items := _normalized_harvest_items(preview.get("items", {}))
	if preview.is_empty() or items.is_empty():
		return false
	for item_id in items:
		var quantity := int(items[item_id])
		if not inventory_system.can_add_item(str(item_id), quantity):
			return false
	var inventory_snapshot := {
		"slots": inventory_system.slots.duplicate(true),
		"quick_slot_mappings": inventory_system.quick_slot_mappings.duplicate(),
	}
	var owns_event_transaction := _begin_inventory_event_transaction()
	var owns_mapping_transaction := _begin_inventory_mapping_transaction()
	for item_id in items:
		if not inventory_system.add_item(str(item_id), int(items[item_id])):
			_restore_inventory_snapshot(inventory_snapshot)
			_end_inventory_mapping_transaction(owns_mapping_transaction, false)
			_end_inventory_event_transaction(owns_event_transaction)
			return false
	_end_inventory_event_transaction(owns_event_transaction)
	var result: Dictionary = farming_system.harvest(cell)
	if result.is_empty() or _normalized_harvest_items(result.get("items", {})) != items:
		_restore_inventory_snapshot(inventory_snapshot)
		_end_inventory_mapping_transaction(owns_mapping_transaction, false)
		return false
	_end_inventory_mapping_transaction(owns_mapping_transaction, true)
	_emit_committed_inventory_adds(items, owns_event_transaction)
	inventory_changed.emit()
	return true


func _preview_harvest(cell: GridCell) -> Dictionary:
	if grid_system != null and grid_system.has_method("preview_harvest"):
		return grid_system.preview_harvest(cell.gx, cell.gz)
	if cell == null or cell.crop_instance == null or not cell.crop_instance.is_mature():
		return {}
	var data = cell.crop_instance.crop_data
	if data == null:
		return {}
	return {
		"items": {str(data.crop_id): cell.crop_instance.calculate_yield(cell.gx, cell.gz, 42)},
		"exp": int(data.exp_reward),
		"regrowing": int(data.regrow_days) > 0 or str(data.growth_form) != "annual",
	}


func _normalized_harvest_items(value: Variant) -> Dictionary:
	var normalized := {}
	if value is Dictionary:
		for item_id in value:
			var quantity := int(value[item_id])
			if not str(item_id).is_empty() and quantity > 0:
				normalized[str(item_id)] = quantity
	elif value is Array:
		for item_id in value:
			var id := str(item_id)
			if not id.is_empty():
				normalized[id] = int(normalized.get(id, 0)) + 1
	return normalized


func _restore_inventory_snapshot(snapshot: Dictionary) -> void:
	inventory_system.restore_state(snapshot.slots, snapshot.quick_slot_mappings)


func _begin_inventory_event_transaction() -> bool:
	if _event_bus == null:
		_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if _event_bus == null or _event_bus.is_blocking_signals():
		return false
	_event_bus.set_block_signals(true)
	return true


func _end_inventory_event_transaction(owns_transaction: bool) -> void:
	if owns_transaction and _event_bus != null:
		_event_bus.set_block_signals(false)


func _end_inventory_mapping_transaction(
	owns_transaction: bool,
	commit_changes: bool
) -> void:
	if owns_transaction and inventory_system.has_method("end_mapping_transaction"):
		inventory_system.call("end_mapping_transaction", commit_changes)


func _begin_inventory_mapping_transaction() -> bool:
	return (
		inventory_system != null
		and inventory_system.has_method("begin_mapping_transaction")
		and bool(inventory_system.call("begin_mapping_transaction"))
	)


func _emit_committed_inventory_adds(items: Dictionary, owns_transaction: bool) -> void:
	if not owns_transaction or _event_bus == null:
		return
	for item_id in items:
		_event_bus.item_added.emit(str(item_id), int(items[item_id]))


func _is_mature(cell: GridCell) -> bool:
	return (
		cell.state == GridCell.State.PLANTED
		and cell.crop_instance != null
		and cell.crop_instance.is_mature()
	)


func _get_active_plant_item_id() -> String:
	if inventory_system == null or not inventory_system.has_method("get_quick_item"):
		return ""
	var item_id := str(inventory_system.get_quick_item(SEED_SLOT))
	return item_id if not crop_id_for_plant_item(item_id).is_empty() else ""


static func crop_id_for_plant_item(item_id: String) -> String:
	if item_id.ends_with("_sapling"):
		return item_id.trim_suffix("_sapling")
	if item_id.ends_with("_seed"):
		return item_id.trim_suffix("_seed")
	return ""


func _get_crop_data(plant_item_id: String = "") -> CropData:
	var crop_id := crop_id_for_plant_item(plant_item_id)
	if crop_id.is_empty():
		return null
	if crop_data_override != null:
		return crop_data_override if crop_data_override.crop_id == crop_id else null
	var game_data := get_node_or_null("/root/GameData")
	return game_data.get_crop(crop_id) if game_data else null
