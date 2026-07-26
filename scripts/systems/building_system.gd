class_name BuildingSystem
extends Node3D

## 建造系统 - 建筑预览、放置、拆除

signal build_mode_entered
signal build_mode_exited
signal building_placed(building_id: String, gx: int, gz: int)
signal building_removed(building_id: String)

var grid_system_ref
var economy_ref
var _in_build_mode := false
var _current_building_id: String = ""
var _preview_mesh: MeshInstance3D
var _buildings: Array[Dictionary] = []  # [{instance, building_id, gx, gz}, ...]
var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")


func configure(grid_sys, econ) -> void:
	grid_system_ref = grid_sys
	economy_ref = econ


# ============================================================
# 建造模式
# ============================================================

func enter_preview_mode(building_id: String) -> void:
	if building_id.is_empty():
		return
	_current_building_id = building_id
	_in_build_mode = true
	_create_preview()
	build_mode_entered.emit()


func exit_preview_mode() -> void:
	_in_build_mode = false
	_current_building_id = ""
	_destroy_preview()
	build_mode_exited.emit()


func is_in_build_mode() -> bool:
	return _in_build_mode


# ============================================================
# 预览
# ============================================================

func _create_preview() -> void:
	_destroy_preview()

	var building_data = GameData.get_building(_current_building_id)
	if building_data.is_empty():
		return

	_preview_mesh = MeshInstance3D.new()
	_preview_mesh.name = "BuildingPreview"

	# 创建 footprint 预览
	var size_x = float(building_data.footprint_x)
	var size_z = float(building_data.footprint_z)
	var mesh = BoxMesh.new()
	mesh.size = Vector3(size_x, 0.1, size_z)
	_preview_mesh.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)  # 绿色半透明
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_mesh.material_override = mat

	add_child(_preview_mesh)


func _destroy_preview() -> void:
	if _preview_mesh:
		_preview_mesh.queue_free()
		_preview_mesh = null


func update_preview_position(world_x: float, world_z: float) -> void:
	if _preview_mesh == null or grid_system_ref == null:
		return

	var building_data = GameData.get_building(_current_building_id)
	if building_data.is_empty():
		return

	var grid_pos = grid_system_ref.world_to_grid(world_x, world_z)
	var center = grid_system_ref.grid_to_world(grid_pos.x, grid_pos.y)
	var height = grid_system_ref.get_terrain_height_at_cell(grid_pos.x, grid_pos.y)

	_preview_mesh.position = Vector3(center.x, height + 0.05, center.y)

	# 更新颜色（绿=可放置，红=不可放置）
	var can_place = can_place_building(_current_building_id, grid_pos.x, grid_pos.y)
	var mat = _preview_mesh.material_override as StandardMaterial3D
	if mat:
		if can_place:
			mat.albedo_color = Color(0.0, 1.0, 0.0, 0.4)
		else:
			mat.albedo_color = Color(1.0, 0.0, 0.0, 0.4)


# ============================================================
# 建造验证与放置
# ============================================================

func can_place_building(building_id: String, gx: int, gz: int) -> bool:
	if grid_system_ref == null:
		return false

	var building_data = GameData.get_building(building_id)
	if building_data.is_empty():
		return false

	# 检查 footprint 内所有网格
	for dx in range(building_data.footprint_x):
		for dz in range(building_data.footprint_z):
			var cell = grid_system_ref.get_cell(gx + dx, gz + dz)
			if cell == null:
				return false
			if cell.state not in [GridCell.State.WASTELAND, GridCell.State.FARMLAND]:
				return false

	# 检查资源
	if economy_ref:
		return economy_ref.has_resources(building_data.cost)

	return true


func place_building(building_id: String, gx: int, gz: int) -> bool:
	if not can_place_building(building_id, gx, gz):
		return false

	var building_data = GameData.get_building(building_id)
	if building_data.is_empty():
		return false

	# 消耗资源
	if economy_ref:
		economy_ref.spend_resources(building_data.cost)

	# 标记网格
	for dx in range(building_data.footprint_x):
		for dz in range(building_data.footprint_z):
			grid_system_ref.set_cell_state(gx + dx, gz + dz, GridCell.State.BUILDING)

	# 创建建筑实例
	var instance = Node3D.new()
	instance.name = building_data.name

	var center = grid_system_ref.grid_to_world(gx, gz)
	var height = grid_system_ref.get_terrain_height_at_cell(gx, gz)
	instance.position = Vector3(center.x, height, center.y)

	# 添加碰撞体
	var static_body = StaticBody3D.new()
	var col_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(float(building_data.footprint_x), 2.0, float(building_data.footprint_z))
	col_shape.shape = box_shape
	static_body.add_child(col_shape)
	instance.add_child(static_body)

	# 添加视觉占位（Phase 5 替换为真实模型）
	var visual = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(float(building_data.footprint_x), 2.0, float(building_data.footprint_z))
	visual.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.4, 0.2)
	visual.material_override = mat
	instance.add_child(visual)

	add_child(instance)

	_buildings.append({
		"instance": instance,
		"building_id": building_id,
		"gx": gx,
		"gz": gz,
	})

	if _event_bus:
		_event_bus.gold_changed.emit(economy_ref.gold if economy_ref else 0)

	building_placed.emit(building_id, gx, gz)

	# 退出建造模式
	exit_preview_mode()

	return true


# ============================================================
# 拆除
# ============================================================

func remove_building(building_index: int) -> void:
	if building_index < 0 or building_index >= _buildings.size():
		return

	var b = _buildings[building_index]
	var building_data = GameData.get_building(b.building_id)

	# 恢复网格
	if grid_system_ref and not building_data.is_empty():
		for dx in range(building_data.footprint_x):
			for dz in range(building_data.footprint_z):
				grid_system_ref.set_cell_state(b.gx + dx, b.gz + dz, GridCell.State.FARMLAND)

	b.instance.queue_free()
	_buildings.remove_at(building_index)

	building_removed.emit(b.building_id)


func get_all_buildings() -> Array:
	return _buildings


func get_building_count() -> int:
	return _buildings.size()
