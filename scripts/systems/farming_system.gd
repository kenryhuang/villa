class_name FarmingSystem
extends Node

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")

var grid_system
var season_system
var game_state
var _event_bus
var _crop_visuals := {}
var _greenhouse_cells := {}


func configure(gs, ss, gs_state) -> bool:
	if gs == null:
		return false
	if _event_bus and _event_bus.day_changed.is_connected(on_day_changed):
		_event_bus.day_changed.disconnect(on_day_changed)
	grid_system = gs
	season_system = ss
	game_state = gs_state
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if _event_bus and not _event_bus.day_changed.is_connected(on_day_changed):
		_event_bus.day_changed.connect(on_day_changed)
	return true


func set_greenhouse_cells(cells: Array) -> void:
	_greenhouse_cells.clear()
	for position in cells:
		if position is Vector2i:
			_greenhouse_cells[GridSystemScript.cell_key(position.x, position.y)] = true


func is_greenhouse_cell(cell: GridCell) -> bool:
	return cell != null and _greenhouse_cells.has(GridSystemScript.cell_key(cell.gx, cell.gz))


func plant(grid_cell, crop_data) -> CropInstance:
	if grid_system == null or grid_cell == null or crop_data == null:
		return null
	var instance = grid_system.plant_crop(grid_cell.gx, grid_cell.gz, crop_data)
	if instance:
		_create_visual(grid_cell, instance)
	return instance


func harvest(grid_cell) -> Dictionary:
	if grid_system == null or grid_cell == null:
		return {}
	var result = grid_system.harvest_crop(grid_cell.gx, grid_cell.gz)
	if not result.is_empty():
		if game_state:
			game_state.add_exp(result.exp)
		_remove_visual(grid_cell)
	return result


func water(grid_cell) -> bool:
	if grid_system == null or grid_cell == null:
		return false
	return grid_system.water_cell(grid_cell.gx, grid_cell.gz)


func get_all_planted_cells() -> Array:
	if grid_system == null:
		return []
	var result := []
	for cell in grid_system._cells.values():
		if cell.state == GridCell.State.PLANTED and cell.crop_instance:
			result.append(cell)
	return result


func on_day_changed(_day: int) -> void:
	for cell in get_all_planted_cells():
		var instance: CropInstance = cell.crop_instance
		if instance.is_mature():
			_clear_water(cell)
			continue
		if not _can_grow(cell, instance.crop_data):
			_clear_water(cell)
			continue
		var old_stage: int = instance.get_current_stage()
		var became_mature: bool = instance.advance_growth()
		_clear_water(cell)
		var new_stage: int = instance.get_current_stage()
		if new_stage != old_stage:
			_update_visual(cell, instance)
			if _event_bus:
				_event_bus.crop_grew.emit(cell.gx, cell.gz, new_stage)
		if became_mature and _event_bus:
			_event_bus.crop_matured.emit(cell.gx, cell.gz)


func _can_grow(cell: GridCell, data) -> bool:
	if is_greenhouse_cell(cell) or season_system == null:
		return true
	return data.seasons.is_empty() or season_system.current_season in data.seasons


func _clear_water(cell: GridCell) -> void:
	cell.watered = false
	if cell.crop_instance:
		cell.crop_instance.is_watered_today = false


func _create_visual(cell: GridCell, instance: CropInstance) -> Node3D:
	var key: int = GridSystemScript.cell_key(cell.gx, cell.gz)
	_remove_visual(cell)
	var visual := _instantiate_stage_visual(cell, instance)
	if visual:
		_crop_visuals[key] = visual
	return visual


func _update_visual(cell: GridCell, instance: CropInstance) -> void:
	var key: int = GridSystemScript.cell_key(cell.gx, cell.gz)
	var visual := _crop_visuals.get(key) as Node3D
	var stage_scene := _stage_scene_path(instance)
	if not stage_scene.is_empty():
		if visual == null or str(visual.get_meta("stage_scene", "")) != stage_scene:
			if visual:
				visual.free()
			visual = _instantiate_stage_visual(cell, instance)
			if visual:
				_crop_visuals[key] = visual
		return
	if visual == null or not visual is MeshInstance3D:
		if visual:
			visual.free()
		visual = _instantiate_fallback_visual(cell, instance)
		_crop_visuals[key] = visual
	var mesh_visual := visual as MeshInstance3D
	var total_stages: int = instance.get_stage_count()
	var stage := instance.get_current_stage()
	var box := mesh_visual.mesh as BoxMesh
	if box:
		box.size = _visual_size_for_stage(stage, total_stages)
		mesh_visual.position.y = cell.terrain_height + box.size.y * 0.5 + 0.035
	_update_visual_color(mesh_visual, stage, total_stages)


func _stage_scene_path(instance: CropInstance) -> String:
	if instance == null or instance.crop_data == null or instance.crop_data.stage_scenes.is_empty():
		return ""
	var stage := instance.get_current_stage()
	if stage < 0 or stage >= instance.crop_data.stage_scenes.size():
		return ""
	var path: String = instance.crop_data.stage_scenes[stage]
	return path if ResourceLoader.exists(path) else ""


func _instantiate_stage_visual(cell: GridCell, instance: CropInstance) -> Node3D:
	var scene_path := _stage_scene_path(instance)
	if scene_path.is_empty():
		return _instantiate_fallback_visual(cell, instance)
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return _instantiate_fallback_visual(cell, instance)
	var visual := packed.instantiate() as Node3D
	visual.name = "CropVisual_%d_%d" % [cell.gx, cell.gz]
	visual.position = cell.world_position_3d() + Vector3(0.0, 0.035, 0.0)
	visual.set_meta("crop_id", instance.crop_data.crop_id)
	visual.set_meta("crop_stage", instance.get_current_stage())
	visual.set_meta("stage_scene", scene_path)
	_visual_parent().add_child(visual)
	return visual


func _instantiate_fallback_visual(cell: GridCell, instance: CropInstance) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = "CropVisual_%d_%d" % [cell.gx, cell.gz]
	visual.mesh = BoxMesh.new()
	var pos := cell.world_position_3d()
	visual.position = Vector3(pos.x, pos.y, pos.z)
	visual.set_meta("crop_id", instance.crop_data.crop_id if instance.crop_data else "")
	visual.set_meta("crop_stage", instance.get_current_stage())
	visual.set_meta("stage_scene", "")
	_visual_parent().add_child(visual)
	var total_stages := instance.get_stage_count()
	var box := visual.mesh as BoxMesh
	box.size = _visual_size_for_stage(instance.get_current_stage(), total_stages)
	visual.position.y = cell.terrain_height + box.size.y * 0.5 + 0.035
	_update_visual_color(visual, instance.get_current_stage(), total_stages)
	return visual


func _visual_size_for_stage(stage: int, total_stages: int) -> Vector3:
	if stage <= 0:
		return Vector3(0.28, 0.12, 0.28)
	if stage >= total_stages - 1:
		return Vector3(0.62, 0.9, 0.62)
	var ratio := float(stage) / float(maxi(1, total_stages - 1))
	return Vector3(0.32 + ratio * 0.2, 0.22 + ratio * 0.48, 0.32 + ratio * 0.2)


func _remove_visual(cell: GridCell) -> void:
	var key: int = GridSystemScript.cell_key(cell.gx, cell.gz)
	var visual := _crop_visuals.get(key) as Node3D
	if visual:
		visual.free()
	_crop_visuals.erase(key)


func _update_visual_color(visual: MeshInstance3D, stage: int, total_stages: int) -> void:
	var mat := StandardMaterial3D.new()
	if stage == 0:
		mat.albedo_color = Color(0.55, 0.35, 0.2)
	elif stage == 1:
		mat.albedo_color = Color(0.2, 0.7, 0.2)
	elif stage >= total_stages - 1:
		mat.albedo_color = Color(1.0, 0.84, 0.0)
	else:
		mat.albedo_color = Color(0.6, 0.8, 0.2)
	mat.roughness = 0.82
	visual.material_override = mat


func get_crop_visual(cell: GridCell) -> Node3D:
	if cell == null:
		return null
	return _crop_visuals.get(GridSystemScript.cell_key(cell.gx, cell.gz)) as Node3D


func get_visual_count() -> int:
	return _crop_visuals.size()


func clear_visuals() -> void:
	for visual in _crop_visuals.values():
		if is_instance_valid(visual):
			visual.free()
	_crop_visuals.clear()


func rebuild_visuals() -> void:
	clear_visuals()
	for cell in get_all_planted_cells():
		_create_visual(cell, cell.crop_instance)


func _visual_parent() -> Node3D:
	var parent := get_node_or_null("CropVisuals") as Node3D
	if parent == null:
		parent = Node3D.new()
		parent.name = "CropVisuals"
		add_child(parent)
	return parent
