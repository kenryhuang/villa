class_name FarmingSystem
extends Node

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")

var grid_system
var season_system
var game_state
var _event_bus
var _crop_visuals := {}


func configure(gs, ss, gs_state) -> void:
	grid_system = gs
	season_system = ss
	game_state = gs_state
	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus:
		_event_bus.day_changed.connect(on_day_changed)


func plant(grid_cell, crop_data) -> CropInstance:
	if grid_system == null or crop_data == null:
		return null
	var instance = grid_system.plant_crop(grid_cell.gx, grid_cell.gz, crop_data)
	if instance:
		_create_visual(grid_cell, instance)
	return instance


func harvest(grid_cell) -> Dictionary:
	if grid_system == null:
		return {}
	var result = grid_system.harvest_crop(grid_cell.gx, grid_cell.gz)
	if not result.is_empty():
		if game_state:
			game_state.add_exp(result.exp)
		_remove_visual(grid_cell)
	return result


func water(grid_cell) -> bool:
	if grid_system == null:
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
		var instance = cell.crop_instance
		if not _can_grow(instance.crop_data):
			_clear_water(cell)
			continue
		var old_stage: int = instance.get_current_stage()
		var became_mature: bool = instance.advance_growth()
		_clear_water(cell)
		if _event_bus and instance.get_current_stage() != old_stage:
			_event_bus.crop_grew.emit(cell.gx, cell.gz, instance.get_current_stage())
			_update_visual(cell, instance)
		if _event_bus and became_mature:
			_event_bus.crop_matured.emit(cell.gx, cell.gz)


func _can_grow(data) -> bool:
	if season_system == null:
		return true
	return data.seasons.is_empty() or season_system.current_season in data.seasons


func _clear_water(cell) -> void:
	cell.watered = false
	if cell.crop_instance:
		cell.crop_instance.is_watered_today = false


func _create_visual(cell, instance) -> void:
	var visual = MeshInstance3D.new()
	visual.name = "CropVisual_%d_%d" % [cell.gx, cell.gz]
	visual.mesh = BoxMesh.new()
	visual.mesh.size = Vector3(0.3, 0.2, 0.3)
	var pos = cell.world_position_3d()
	visual.position = Vector3(pos.x, pos.y + 0.2, pos.z)
	var total_stages: int = instance.crop_data.stage_textures.size() if instance.crop_data else 4
	_update_visual_color(visual, instance.get_current_stage(), total_stages)
	_visual_parent().add_child(visual)
	var key: int = GridSystemScript.cell_key(cell.gx, cell.gz)
	_crop_visuals[key] = visual


func _update_visual(cell, instance) -> void:
	var key: int = GridSystemScript.cell_key(cell.gx, cell.gz)
	var visual = _crop_visuals.get(key)
	if visual:
		var total_stages: int = instance.crop_data.stage_textures.size() if instance.crop_data else 4
		_update_visual_color(visual, instance.get_current_stage(), total_stages)


func _remove_visual(cell) -> void:
	var key: int = GridSystemScript.cell_key(cell.gx, cell.gz)
	var visual = _crop_visuals.get(key)
	if visual:
		visual.queue_free()
		_crop_visuals.erase(key)


func _update_visual_color(visual: MeshInstance3D, stage: int, total_stages: int) -> void:
	var mat = StandardMaterial3D.new()
	if stage == 0:
		mat.albedo_color = Color(0.55, 0.35, 0.2)  # seed brown
	elif stage == 1:
		mat.albedo_color = Color(0.2, 0.7, 0.2)    # sprout green
	elif stage == total_stages - 1:
		mat.albedo_color = Color(1.0, 0.84, 0.0)   # mature gold
	else:
		mat.albedo_color = Color(0.6, 0.8, 0.2)    # growing yellow-green
	visual.material_override = mat


func _visual_parent() -> Node3D:
	var parent = get_node_or_null("CropVisuals")
	if parent == null:
		parent = Node3D.new()
		parent.name = "CropVisuals"
		add_child(parent)
	return parent
