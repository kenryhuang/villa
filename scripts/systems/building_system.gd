class_name BuildingSystem
extends Node3D

signal build_mode_entered
signal build_mode_exited
signal building_placed(building_id: String, gx: int, gz: int)
signal building_removed(building_id: String)
signal building_preview_moved(gx: int, gz: int, can_place: bool)
signal building_instance_placed(instance: BuildingInstance)
signal building_instance_removed(instance: BuildingInstance)
signal building_construction_started(instance: BuildingInstance)
signal building_construction_stage_changed(instance: BuildingInstance, stage: int)
signal building_construction_completed(instance: BuildingInstance)

const GameDataScript = preload("res://scripts/core/game_data.gd")
const BUILDABLE_STATES := [GridCell.State.WASTELAND, GridCell.State.FARMLAND]

var grid_system_ref: GridSystem
var economy_ref: Variant
var buildings_container: Node3D
var _event_bus: Node
var _in_build_mode := false
var _current_data: BuildingData
var _preview_grid := Vector2i(-1, -1)
var _preview_can_place := false
var _buildings: Array[BuildingInstance] = []

@onready var _preview_root: Node3D = get_node_or_null("BuildingPreview")
@onready var _visual_proxy: Node3D = get_node_or_null("BuildingPreview/VisualProxy")
@onready var _footprint_markers: Node3D = get_node_or_null("BuildingPreview/FootprintMarkers")
@onready var _default_buildings_container: Node3D = get_node_or_null("BuildingInstances")


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")
	add_to_group("building_system")
	_ensure_scene_nodes()
	_preview_root.visible = false
	if buildings_container == null:
		buildings_container = _default_buildings_container


func configure(grid_sys: GridSystem, economy: Variant, container: Node3D = null) -> bool:
	grid_system_ref = grid_sys
	economy_ref = economy
	_ensure_scene_nodes()
	buildings_container = container if container != null else _default_buildings_container
	return grid_system_ref != null and economy_ref != null and buildings_container != null


func enter_preview_mode(building: Variant) -> bool:
	var resolved := _resolve_data(building)
	if resolved == null or not resolved.is_valid() or not load(resolved.scene_path) is PackedScene:
		return false
	exit_preview_mode()
	_current_data = resolved
	_in_build_mode = true
	_preview_grid = Vector2i(-1, -1)
	_preview_can_place = false
	_create_preview_visual()
	_preview_root.visible = true
	build_mode_entered.emit()
	return true


func exit_preview_mode() -> void:
	var was_active := _in_build_mode
	_in_build_mode = false
	_current_data = null
	_preview_grid = Vector2i(-1, -1)
	_preview_can_place = false
	_clear_children(_visual_proxy)
	_clear_children(_footprint_markers)
	if _preview_root:
		_preview_root.visible = false
	if was_active:
		build_mode_exited.emit()


func is_in_build_mode() -> bool:
	return _in_build_mode


func get_selected_building_id() -> String:
	return _current_data.building_id if _current_data else ""


func get_preview_data() -> BuildingData:
	return _current_data


func update_preview_position(world_x: float, world_z: float) -> bool:
	if grid_system_ref == null:
		return false
	var grid_position := grid_system_ref.world_to_grid(world_x, world_z)
	return update_preview(grid_position.x, grid_position.y)


func update_preview(gx: int, gz: int) -> bool:
	return update_preview_grid(gx, gz)


func update_preview_grid(gx: int, gz: int) -> bool:
	if not _in_build_mode or _current_data == null or grid_system_ref == null:
		return false
	_preview_grid = Vector2i(gx, gz)
	_preview_can_place = can_place(_current_data, gx, gz)
	var position_3d := _world_position_for(_current_data, gx, gz)
	for child in _visual_proxy.get_children():
		if child is BuildingInstance:
			child.position = position_3d
			child.set_preview_valid(_preview_can_place)
	_update_markers(gx, gz)
	building_preview_moved.emit(gx, gz, _preview_can_place)
	if _event_bus and _event_bus.has_signal("building_preview_moved"):
		_event_bus.building_preview_moved.emit(gx, gz, _preview_can_place)
	return _preview_can_place


func get_preview_grid() -> Vector2i:
	return _preview_grid


func get_preview_can_place() -> bool:
	return _preview_can_place


func get_preview_marker_count() -> int:
	return _footprint_markers.get_child_count() if _footprint_markers else 0


func can_place(building: Variant, gx: int, gz: int) -> bool:
	return bool(diagnose_placement(building, gx, gz).allowed)


func diagnose_resources(building: Variant) -> Dictionary:
	var resolved := _resolve_data(building)
	if not _is_valid_building_data(resolved):
		return _diagnostic(false, "invalid_building", "无法建造：建筑数据无效")
	if economy_ref == null or not economy_ref.has_method("has_resources"):
		return _diagnostic(false, "system_unavailable", "建造系统尚未就绪")
	var report: Dictionary = (
		economy_ref.get_resource_report(resolved.cost)
		if economy_ref.has_method("get_resource_report")
		else {}
	)
	var missing := {}
	for item_id in report:
		var entry: Dictionary = report[item_id]
		if int(entry.get("missing", 0)) > 0:
			missing[item_id] = entry
	if missing.is_empty() and bool(economy_ref.has_resources(resolved.cost)):
		var allowed := _diagnostic(true, "ok", "")
		allowed.building_id = resolved.building_id
		return allowed
	var result := _diagnostic(
		false,
		"insufficient_resources",
		_resource_failure_message(resolved, missing)
	)
	result.building_id = resolved.building_id
	result.missing_resources = missing
	return result


func diagnose_placement(building: Variant, gx: int, gz: int) -> Dictionary:
	var resolved := _resolve_data(building)
	if not _is_valid_building_data(resolved):
		var invalid := _diagnostic(false, "invalid_building", "无法建造：建筑数据无效")
		invalid.grid = Vector2i(gx, gz)
		return invalid
	if grid_system_ref == null or economy_ref == null or buildings_container == null:
		var unavailable := _diagnostic(false, "system_unavailable", "建造系统尚未就绪")
		unavailable.building_id = resolved.building_id
		unavailable.grid = Vector2i(gx, gz)
		return unavailable
	for cell_data in _footprint_cells(resolved, gx, gz):
		var cell := grid_system_ref.get_cell(cell_data.x, cell_data.y)
		if cell == null:
			return _blocked_diagnostic(
				resolved,
				gx,
				gz,
				cell_data,
				-1,
				"out_of_bounds",
				"无法建造%s：目标区域超出地图范围" % resolved.display_name
			)
		if not is_finite(grid_system_ref.get_terrain_height_at_cell(cell_data.x, cell_data.y)):
			return _blocked_diagnostic(
				resolved,
				gx,
				gz,
				cell_data,
				cell.state,
				"invalid_terrain",
				"无法建造%s：目标地形无效" % resolved.display_name
			)
		if cell.state not in BUILDABLE_STATES:
			return _cell_state_diagnostic(resolved, gx, gz, cell_data, cell.state)
	var resources := diagnose_resources(resolved)
	resources.building_id = resolved.building_id
	resources.grid = Vector2i(gx, gz)
	return resources


func can_place_building(building_id: String, gx: int, gz: int) -> bool:
	return can_place(building_id, gx, gz)


func try_place_building(building: Variant, gx: int, gz: int) -> Dictionary:
	var resolved := _resolve_data(building)
	var diagnostic := diagnose_placement(resolved, gx, gz)
	if not bool(diagnostic.allowed):
		return _placement_result(null, diagnostic)

	var packed := load(resolved.scene_path) as PackedScene
	if packed == null:
		return _placement_result(
			null,
			_commit_diagnostic(resolved, gx, gz, "invalid_building", "无法建造：建筑场景无效")
		)
	var instance := packed.instantiate() as BuildingInstance
	if instance == null:
		return _placement_result(
			null,
			_commit_diagnostic(resolved, gx, gz, "invalid_building", "无法建造：建筑场景无效")
		)

	var snapshots: Array[Dictionary] = []
	for location in _footprint_cells(resolved, gx, gz):
		var cell := grid_system_ref.get_cell(location.x, location.y)
		snapshots.append({
			"gx": location.x,
			"gz": location.y,
			"previous_state": cell.state,
		})
	instance.configure(resolved, gx, gz, snapshots)
	instance.position = _world_position_for(resolved, gx, gz)

	var applied: Array[Dictionary] = []
	for snapshot in snapshots:
		if not grid_system_ref.set_cell_state(snapshot.gx, snapshot.gz, GridCell.State.BUILDING):
			_restore_snapshots(applied)
			instance.free()
			return _placement_result(
				null,
				_commit_diagnostic(
					resolved,
					gx,
					gz,
					"grid_commit_failed",
					"建造提交失败，请重试"
				)
			)
		applied.append(snapshot)

	if economy_ref != null:
		if not economy_ref.has_method("spend_resources") or not bool(economy_ref.spend_resources(resolved.cost)):
			_restore_snapshots(snapshots)
			instance.free()
			return _placement_result(
				null,
				_commit_diagnostic(
					resolved,
					gx,
					gz,
					"resource_commit_failed",
					"建造提交失败，请重试"
				)
			)

	buildings_container.add_child(instance)
	_buildings.append(instance)
	_connect_construction_signals(instance)
	instance.start_construction()
	building_placed.emit(resolved.building_id, gx, gz)
	building_instance_placed.emit(instance)
	building_construction_started.emit(instance)
	if _event_bus and _event_bus.has_signal("building_placed"):
		_event_bus.building_placed.emit(instance)
	if _event_bus and _event_bus.has_signal("building_construction_started"):
		_event_bus.building_construction_started.emit(instance)
	if _in_build_mode:
		exit_preview_mode()
	var success := _diagnostic(true, "ok", "")
	success.building_id = resolved.building_id
	success.grid = Vector2i(gx, gz)
	return _placement_result(instance, success)


func place_building(building: Variant, gx: int, gz: int) -> BuildingInstance:
	return try_place_building(building, gx, gz).get("instance") as BuildingInstance


func place_selected_building(gx: int, gz: int) -> BuildingInstance:
	if _current_data == null:
		return null
	return place_building(_current_data, gx, gz)


func try_place_selected_building(gx: int, gz: int) -> Dictionary:
	if _current_data == null:
		var diagnostic := _diagnostic(false, "invalid_building", "未选择建筑")
		diagnostic.grid = Vector2i(gx, gz)
		return _placement_result(null, diagnostic)
	return try_place_building(_current_data, gx, gz)


func place_building_by_id(building_id: String, gx: int, gz: int) -> BuildingInstance:
	return place_building(building_id, gx, gz)


func remove_building(building: Variant) -> bool:
	return _remove_building_internal(building, true)


func _remove_building_internal(building: Variant, restore_grid: bool) -> bool:
	var instance: BuildingInstance
	if building is BuildingInstance:
		instance = building
	elif building is int:
		var index := int(building)
		if index >= 0 and index < _buildings.size():
			instance = _buildings[index]
	if instance == null or not _buildings.has(instance):
		return false
	if restore_grid:
		for snapshot in instance.occupied_cells:
			var cell := grid_system_ref.get_cell(snapshot.gx, snapshot.gz) if grid_system_ref else null
			if cell != null and cell.state == GridCell.State.BUILDING:
				grid_system_ref.set_cell_state(snapshot.gx, snapshot.gz, int(snapshot.previous_state))
	_buildings.erase(instance)
	var id := instance.data.building_id if instance.data else instance.authored_building_id
	instance.deactivate()
	building_removed.emit(id)
	building_instance_removed.emit(instance)
	if _event_bus and _event_bus.has_signal("building_removed"):
		_event_bus.building_removed.emit(instance)
	instance.queue_free()
	return true


func clear_buildings(restore_grid := true) -> void:
	for instance in _buildings.duplicate():
		_remove_building_internal(instance, restore_grid)


func get_all_buildings() -> Array[BuildingInstance]:
	return _buildings.duplicate()


func get_building_count() -> int:
	return _buildings.size()


func restore_buildings(records: Array) -> int:
	clear_buildings(false)
	var restored := 0
	for record_value in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var resolved := _resolve_data(str(record.get("building_id", "")))
		var gx := int(record.get("gx", -1))
		var gz := int(record.get("gz", -1))
		if resolved == null or not resolved.is_valid() or grid_system_ref == null:
			continue
		var packed := load(resolved.scene_path) as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate() as BuildingInstance
		if instance == null:
			continue

		var saved_states := {}
		var saved_cells: Variant = record.get("occupied_cells", [])
		if saved_cells is Array:
			for saved_value in saved_cells:
				if saved_value is Dictionary:
					var saved := saved_value as Dictionary
					saved_states[Vector2i(int(saved.get("gx", -1)), int(saved.get("gz", -1)))] = int(
						saved.get("previous_state", GridCell.State.WASTELAND)
					)

		var snapshots: Array[Dictionary] = []
		var changed: Array[Dictionary] = []
		var valid := true
		for location in _footprint_cells(resolved, gx, gz):
			var cell := grid_system_ref.get_cell(location.x, location.y)
			var height := grid_system_ref.get_terrain_height_at_cell(location.x, location.y)
			if cell == null or not is_finite(height):
				valid = false
				break
			snapshots.append({
				"gx": location.x,
				"gz": location.y,
				"previous_state": saved_states.get(location, GridCell.State.WASTELAND),
			})
			if cell.state != GridCell.State.BUILDING:
				var previous_state := cell.state
				if cell.state not in BUILDABLE_STATES or not grid_system_ref.set_cell_state(
					location.x,
					location.y,
					GridCell.State.BUILDING
				):
					valid = false
					break
				changed.append({
					"gx": location.x,
					"gz": location.y,
					"previous_state": previous_state,
				})
		if not valid:
			_restore_snapshots(changed)
			instance.free()
			continue
		instance.configure(resolved, gx, gz, snapshots)
		if record.has("construction_stage") and record.has("construction_elapsed"):
			instance.restore_construction(
				int(record.construction_stage),
				float(record.construction_elapsed)
			)
		else:
			instance.restore_construction(
				BuildingInstance.ConstructionStage.COMPLETE,
				BuildingInstance.construction_duration_for(resolved.footprint)
			)
		instance.position = _world_position_for(resolved, gx, gz)
		buildings_container.add_child(instance)
		_buildings.append(instance)
		_connect_construction_signals(instance)
		restored += 1
	return restored


func get_building_at(gx: int, gz: int) -> BuildingInstance:
	for instance in _buildings:
		for snapshot in instance.occupied_cells:
			if int(snapshot.gx) == gx and int(snapshot.gz) == gz:
				return instance
	return null


func get_buildings_of_type(effect_type: String) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	for instance in _buildings:
		if instance.data and instance.data.effect_type == effect_type:
			result.append(instance)
	return result


func get_buildings_by_effect(effect: String) -> Array[BuildingInstance]:
	return get_buildings_of_type(effect)


func _connect_construction_signals(instance: BuildingInstance) -> void:
	if not instance.construction_stage_changed.is_connected(_on_construction_stage_changed):
		instance.construction_stage_changed.connect(_on_construction_stage_changed)
	if not instance.construction_completed.is_connected(_on_construction_completed):
		instance.construction_completed.connect(_on_construction_completed)


func _on_construction_stage_changed(
	instance: BuildingInstance,
	stage: BuildingInstance.ConstructionStage
) -> void:
	building_construction_stage_changed.emit(instance, int(stage))
	if _event_bus and _event_bus.has_signal("building_construction_stage_changed"):
		_event_bus.building_construction_stage_changed.emit(instance, int(stage))


func _on_construction_completed(instance: BuildingInstance) -> void:
	building_construction_completed.emit(instance)
	if _event_bus and _event_bus.has_signal("building_construction_completed"):
		_event_bus.building_construction_completed.emit(instance)


func _resolve_data(building: Variant) -> BuildingData:
	if building is BuildingData:
		return building
	if building is String:
		var game_data = GameDataScript.new()
		var result := BuildingData.from_dictionary(game_data.get_building(building))
		game_data.free()
		return result
	return null


func _is_valid_building_data(data: BuildingData) -> bool:
	return (
		data != null
		and data.is_valid()
		and load(data.scene_path) is PackedScene
	)


func _diagnostic(allowed: bool, code: String, message: String) -> Dictionary:
	return {
		"allowed": allowed,
		"code": code,
		"message": message,
		"building_id": "",
		"grid": Vector2i(-1, -1),
		"missing_resources": {},
		"blocked_cell": {},
	}


func _blocked_diagnostic(
	data: BuildingData,
	gx: int,
	gz: int,
	location: Vector2i,
	state: int,
	code: String,
	message: String
) -> Dictionary:
	var result := _diagnostic(false, code, message)
	result.building_id = data.building_id
	result.grid = Vector2i(gx, gz)
	result.blocked_cell = {
		"grid": location,
		"state": state,
	}
	return result


func _cell_state_diagnostic(
	data: BuildingData,
	gx: int,
	gz: int,
	location: Vector2i,
	state: int
) -> Dictionary:
	var code := "invalid_cell_state"
	var reason := "该地块不能建造"
	match state:
		GridCell.State.ROAD:
			code = "road"
			reason = "目标区域包含道路"
		GridCell.State.BUILDING:
			code = "occupied"
			reason = "这里已经有建筑"
		GridCell.State.PLANTED:
			code = "planted"
			reason = "地块上仍有作物"
		GridCell.State.WATER:
			code = "water"
			reason = "水域不能建造"
		GridCell.State.DECORATION:
			code = "decoration"
			reason = "目标区域被装饰占用"
	return _blocked_diagnostic(
		data,
		gx,
		gz,
		location,
		state,
		code,
		"无法建造%s：%s" % [data.display_name, reason]
	)


func _resource_failure_message(data: BuildingData, missing: Dictionary) -> String:
	if missing.is_empty():
		return "无法建造%s：材料不足" % data.display_name
	var parts: Array[String] = []
	for item_id in data.cost:
		if not missing.has(item_id):
			continue
		var item = GameDataScript.get_item(str(item_id))
		var item_name := str(item.get("name", item_id)) if item is Dictionary else str(item_id)
		parts.append("%s还缺 %d" % [item_name, int(missing[item_id].missing)])
	return "无法建造%s：%s" % [data.display_name, "、".join(parts)]


func _commit_diagnostic(
	data: BuildingData,
	gx: int,
	gz: int,
	code: String,
	message: String
) -> Dictionary:
	var result := _diagnostic(false, code, message)
	result.building_id = data.building_id if data else ""
	result.grid = Vector2i(gx, gz)
	return result


func _placement_result(instance: BuildingInstance, diagnostic: Dictionary) -> Dictionary:
	return {
		"placed": instance != null,
		"instance": instance,
		"diagnostic": diagnostic,
	}


func _footprint_cells(data: BuildingData, gx: int, gz: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dz in range(data.footprint.y):
		for dx in range(data.footprint.x):
			result.append(Vector2i(gx + dx, gz + dz))
	return result


func _world_position_for(data: BuildingData, gx: int, gz: int) -> Vector3:
	var first := grid_system_ref.grid_to_world(gx, gz)
	var last := grid_system_ref.grid_to_world(
		gx + data.footprint.x - 1,
		gz + data.footprint.y - 1
	)
	var height_total := 0.0
	var height_count := 0
	for location in _footprint_cells(data, gx, gz):
		var height := grid_system_ref.get_terrain_height_at_cell(location.x, location.y)
		if is_finite(height):
			height_total += height
			height_count += 1
	return Vector3(
		(first.x + last.x) * 0.5,
		height_total / float(height_count) if height_count > 0 else 0.0,
		(first.y + last.y) * 0.5
	)


func _restore_snapshots(snapshots: Array[Dictionary]) -> void:
	for snapshot in snapshots:
		var cell := grid_system_ref.get_cell(snapshot.gx, snapshot.gz)
		if cell != null and cell.state == GridCell.State.BUILDING:
			grid_system_ref.set_cell_state(snapshot.gx, snapshot.gz, int(snapshot.previous_state))


func _create_preview_visual() -> void:
	_clear_children(_visual_proxy)
	_clear_children(_footprint_markers)
	var packed := load(_current_data.scene_path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate() as BuildingInstance
	if instance == null:
		return
	_visual_proxy.add_child(instance)
	instance.configure(_current_data, 0, 0, [])
	instance.set_preview_mode(true)
	_ensure_marker_count(_current_data.footprint.x * _current_data.footprint.y)


func _ensure_marker_count(count: int) -> void:
	while _footprint_markers.get_child_count() < count:
		var marker := MeshInstance3D.new()
		marker.name = "CellMarker%d" % _footprint_markers.get_child_count()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(GridSystem.CELL_SIZE * 0.92, 0.035, GridSystem.CELL_SIZE * 0.92)
		marker.mesh = mesh
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_footprint_markers.add_child(marker)
	while _footprint_markers.get_child_count() > count:
		var child := _footprint_markers.get_child(-1)
		_footprint_markers.remove_child(child)
		child.free()


func _update_markers(gx: int, gz: int) -> void:
	if _current_data == null:
		return
	_ensure_marker_count(_current_data.footprint.x * _current_data.footprint.y)
	var locations := _footprint_cells(_current_data, gx, gz)
	var color := Color(0.22, 0.9, 0.35, 0.34) if _preview_can_place else Color(1.0, 0.2, 0.2, 0.34)
	for index in locations.size():
		var location := locations[index]
		var marker := _footprint_markers.get_child(index) as MeshInstance3D
		var point := grid_system_ref.grid_to_world(location.x, location.y)
		var height := grid_system_ref.get_terrain_height_at_cell(location.x, location.y)
		marker.position = Vector3(point.x, (height if is_finite(height) else 0.0) + 0.03, point.y)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color
		material.no_depth_test = true
		marker.material_override = material


func _ensure_scene_nodes() -> void:
	_preview_root = get_node_or_null("BuildingPreview")
	if _preview_root == null:
		_preview_root = Node3D.new()
		_preview_root.name = "BuildingPreview"
		add_child(_preview_root)
	_visual_proxy = _preview_root.get_node_or_null("VisualProxy")
	if _visual_proxy == null:
		_visual_proxy = Node3D.new()
		_visual_proxy.name = "VisualProxy"
		_preview_root.add_child(_visual_proxy)
	_footprint_markers = _preview_root.get_node_or_null("FootprintMarkers")
	if _footprint_markers == null:
		_footprint_markers = Node3D.new()
		_footprint_markers.name = "FootprintMarkers"
		_preview_root.add_child(_footprint_markers)
	_default_buildings_container = get_node_or_null("BuildingInstances")
	if _default_buildings_container == null:
		_default_buildings_container = Node3D.new()
		_default_buildings_container.name = "BuildingInstances"
		add_child(_default_buildings_container)


func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()
