class_name FarmingSystem
extends Node

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")
const GameStateScript = preload("res://scripts/core/game_state.gd")

var grid_system
var season_system
var game_state
var _event_bus
var _crop_visuals := {}
var _greenhouse_cells := {}
var _paused_greenhouse_cells := {}
var _game_data


static func crop_visual_seed(cell: GridCell, crop_id: String) -> int:
	if cell == null:
		return crop_id.hash()
	return GridSystemScript.cell_key(cell.gx, cell.gz) + crop_id.hash()


func configure(gs, ss, gs_state) -> bool:
	if gs == null:
		return false
	grid_system = gs
	season_system = ss
	game_state = gs_state
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if _event_bus == null and gs is GridSystem:
		_event_bus = (gs as GridSystem)._event_bus
	_game_data = get_node_or_null("/root/GameData") if is_inside_tree() else null
	return true


func set_greenhouse_cells(cells: Array, paused_cells: Array = []) -> void:
	var active := {}
	var paused := {}
	for position in cells:
		if position is Vector2i:
			active[GridSystemScript.cell_key(position.x, position.y)] = true
	for position in paused_cells:
		if position is Vector2i:
			var key := GridSystemScript.cell_key(position.x, position.y)
			if not active.has(key):
				paused[key] = true
	if active == _greenhouse_cells and paused == _paused_greenhouse_cells:
		return
	_greenhouse_cells = active
	_paused_greenhouse_cells = paused
	_reassess_all_environments()


func is_greenhouse_cell(cell: GridCell) -> bool:
	return cell != null and _greenhouse_cells.has(GridSystemScript.cell_key(cell.gx, cell.gz))


func is_paused_greenhouse_cell(cell: GridCell) -> bool:
	return cell != null and _paused_greenhouse_cells.has(GridSystemScript.cell_key(cell.gx, cell.gz))


func preview_plant(cell: GridCell, plant_item_id: String) -> Dictionary:
	var result := {"ok": false, "reason": "invalid_seed_mapping", "crop_data": null}
	var data_source = _resolve_game_data()
	var crop_data: CropData = (
		data_source.get_crop_for_plant_item(plant_item_id)
		if data_source != null and data_source.has_method("get_crop_for_plant_item")
		else null
	)
	if crop_data == null:
		return result
	result.crop_data = crop_data
	if cell == null or cell.state != GridCell.State.FARMLAND or cell.crop_instance != null:
		result.reason = "plot_unavailable"
		return result
	var covered := is_greenhouse_cell(cell) or is_paused_greenhouse_cell(cell)
	if crop_data.environment == "greenhouse_only" and not covered:
		result.reason = "greenhouse_required"
		return result
	if not covered and not _is_current_season_allowed(crop_data):
		result.reason = "wrong_season"
		return result
	result.ok = true
	result.reason = ""
	return result


func _resolve_game_data() -> Node:
	if _game_data != null and is_instance_valid(_game_data):
		return _game_data
	var main_loop := Engine.get_main_loop() as SceneTree
	if main_loop != null:
		_game_data = main_loop.root.get_node_or_null("GameData")
	return _game_data


func can_plant(cell: GridCell, crop_data: CropData) -> bool:
	if cell == null or crop_data == null or cell.state != GridCell.State.FARMLAND:
		return false
	if cell.crop_instance != null:
		return false
	if is_greenhouse_cell(cell) or is_paused_greenhouse_cell(cell):
		return true
	if crop_data.environment == "greenhouse_only":
		return false
	return _is_current_season_allowed(crop_data)


func plant(grid_cell, crop_data) -> CropInstance:
	if grid_system == null or grid_cell == null or crop_data == null:
		return null
	return _commit_plant_data(grid_cell, crop_data)


func commit_plant(
	cell: GridCell,
	plant_item_id: String,
	expected_preview: Dictionary
) -> CropInstance:
	if grid_system == null or cell == null or expected_preview.is_empty():
		return null
	var current := preview_plant(cell, plant_item_id)
	if current != expected_preview or not bool(current.get("ok", false)):
		return null
	return _commit_plant_data(cell, current.get("crop_data") as CropData)


func _commit_plant_data(cell: GridCell, crop_data: CropData) -> CropInstance:
	var instance: CropInstance = grid_system.apply_crop_plant(cell.gx, cell.gz, crop_data)
	if instance == null:
		return null
	_create_visual(cell, instance)
	_emit_cell_state(cell)
	if _event_bus and _event_bus.has_signal("crop_planted"):
		_event_bus.emit_signal("crop_planted", cell.gx, cell.gz, crop_data.crop_id)
	return instance


func harvest(grid_cell, expected_preview: Dictionary = {}) -> Dictionary:
	if grid_system == null or grid_cell == null:
		return {}
	var preview := (
		expected_preview
		if not expected_preview.is_empty()
		else preview_harvest(grid_cell)
	)
	var result := commit_harvest(grid_cell, preview)
	return result


func preview_harvest(cell: GridCell) -> Dictionary:
	if grid_system == null or cell == null or cell.crop_instance == null:
		return {}
	var instance: CropInstance = cell.crop_instance
	var data: CropData = instance.crop_data
	if cell.state != GridCell.State.PLANTED or data == null or not instance.is_mature():
		return {}
	if instance.harvest_count >= EconomyLimitsScript.MAX_SAFE_INTEGER:
		return {}
	var before: Dictionary = grid_system.get_crop_snapshot(cell.gx, cell.gz)
	if before.is_empty():
		return {}
	if data.lifecycle_type not in ["annual", "annual_regrow", "bush", "tree", "vine"]:
		return {}
	var regrowing := data.lifecycle_type in ["annual_regrow", "bush", "tree", "vine"]
	var post_progress := 0.0
	var post_lifecycle: Variant = null
	var post_cell_state := GridCell.State.FARMLAND
	var post_crop: Variant = null
	if regrowing:
		post_lifecycle = CropInstance.LifecycleState.GROWING
		post_progress = maxf(0.0, float(data.growth_days - data.regrow_days))
		if post_progress >= float(data.growth_days):
			return {}
		post_cell_state = GridCell.State.PLANTED
		post_crop = before.crop.duplicate(true)
		post_crop.growth_progress = post_progress
		post_crop.lifecycle_state = post_lifecycle
		post_crop.harvest_count = instance.harvest_count + 1
		post_crop.is_watered_today = false
	var harvest_seed := _harvest_seed()
	return {
		"items": {str(data.crop_id): instance.calculate_yield(cell.gx, cell.gz, harvest_seed)},
		"exp": int(data.exp_reward),
		"harvest_seed": harvest_seed,
		"regrowing": regrowing,
		"post_growth_progress": post_progress,
		"post_lifecycle_state": post_lifecycle,
		"post_cell_state": post_cell_state,
		"post_harvest_count": instance.harvest_count + 1,
		"post_crop": post_crop,
		"before": before,
	}


func _harvest_seed() -> int:
	if game_state != null:
		for property in game_state.get_property_list():
			if str(property.get("name", "")) != "harvest_seed":
				continue
			var value: Variant = game_state.get("harvest_seed")
			if GameStateScript.is_valid_harvest_seed(value):
				return int(value)
			break
	return GameStateScript.LEGACY_HARVEST_SEED


func commit_harvest(cell: GridCell, preview: Dictionary) -> Dictionary:
	if grid_system == null or cell == null or preview.is_empty():
		return {}
	var expected := preview_harvest(cell)
	if expected.is_empty() or expected != preview:
		return {}
	var after := {
		"gx": cell.gx,
		"gz": cell.gz,
		"cell_state": int(preview.post_cell_state),
		"watered": false,
		"crop": preview.post_crop.duplicate(true) if preview.post_crop is Dictionary else null,
	}
	if not grid_system.apply_crop_harvest(preview.before, after):
		return {}
	if bool(preview.regrowing) and cell.crop_instance != null:
		_update_visual(cell, cell.crop_instance)
	else:
		_remove_visual(cell)
	if game_state:
		game_state.add_exp(int(preview.exp))
	_emit_cell_state(cell)
	if _event_bus and _event_bus.has_signal("crop_harvested"):
		_event_bus.emit_signal(
			"crop_harvested",
			cell.gx,
			cell.gz,
			str((preview.before.crop as Dictionary).get("crop_id", ""))
		)
	return preview.duplicate(true)


func clear_withered(cell: GridCell) -> bool:
	if (
		grid_system == null
		or cell == null
		or cell.crop_instance == null
		or cell.crop_instance.lifecycle_state != CropInstance.LifecycleState.WITHERED
	):
		return false
	var before: Dictionary = grid_system.get_crop_snapshot(cell.gx, cell.gz)
	var after := {
		"gx": cell.gx,
		"gz": cell.gz,
		"cell_state": GridCell.State.FARMLAND,
		"watered": false,
		"crop": null,
	}
	if not grid_system.apply_crop_clear(before, after):
		return false
	_remove_visual(cell)
	_emit_cell_state(cell)
	return true


func _emit_cell_state(cell: GridCell) -> void:
	if _event_bus and cell != null and _event_bus.has_signal("cell_state_changed"):
		_event_bus.emit_signal("cell_state_changed", cell.gx, cell.gz, cell.state)


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
		if is_paused_greenhouse_cell(cell):
			_clear_water(cell)
			continue
		var old_stage: int = instance.get_current_stage()
		var old_lifecycle: int = instance.lifecycle_state
		var environment_changed := _apply_environment_transition(cell)
		if instance.lifecycle_state == CropInstance.LifecycleState.GROWING:
			instance.advance_growth()
		_clear_water(cell)
		var new_stage: int = instance.get_current_stage()
		if environment_changed or new_stage != old_stage:
			_update_visual(cell, instance)
		if new_stage != old_stage:
			if _event_bus:
				_event_bus.crop_grew.emit(cell.gx, cell.gz, new_stage)
		if (
			old_lifecycle == CropInstance.LifecycleState.GROWING
			and instance.lifecycle_state == CropInstance.LifecycleState.MATURE
			and _event_bus
		):
			_event_bus.crop_matured.emit(cell.gx, cell.gz)


func _is_current_season_allowed(data: CropData) -> bool:
	if data == null:
		return false
	if season_system == null:
		return true
	return data.seasons.is_empty() or season_system.current_season in data.seasons


func _reassess_all_environments() -> void:
	for cell in get_all_planted_cells():
		if is_paused_greenhouse_cell(cell):
			continue
		if _apply_environment_transition(cell):
			_update_visual(cell, cell.crop_instance)


func _apply_environment_transition(cell: GridCell) -> bool:
	if cell == null or cell.crop_instance == null or cell.crop_instance.crop_data == null:
		return false
	if is_paused_greenhouse_cell(cell):
		return false
	var instance: CropInstance = cell.crop_instance
	var data: CropData = instance.crop_data
	var next_state := instance.lifecycle_state
	if is_greenhouse_cell(cell):
		if instance.lifecycle_state == CropInstance.LifecycleState.DORMANT:
			next_state = instance.derive_active_state()
	elif data.environment == "greenhouse_only":
		next_state = CropInstance.LifecycleState.WITHERED
	elif _is_current_season_allowed(data):
		if instance.lifecycle_state == CropInstance.LifecycleState.DORMANT:
			next_state = instance.derive_active_state()
	elif data.lifecycle_type in ["annual", "annual_regrow"]:
		next_state = CropInstance.LifecycleState.WITHERED
	elif data.lifecycle_type in ["bush", "tree", "vine"]:
		next_state = CropInstance.LifecycleState.DORMANT
	if next_state == instance.lifecycle_state:
		return false
	return instance.set_lifecycle_state(next_state)


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
		elif visual:
			visual.set_meta("crop_stage", _visual_stage(instance))
			_apply_visual_state(visual, instance.lifecycle_state)
		return
	if visual == null or not visual is MeshInstance3D:
		if visual:
			visual.free()
		visual = _instantiate_fallback_visual(cell, instance)
		_crop_visuals[key] = visual
	var mesh_visual := visual as MeshInstance3D
	var total_stages: int = instance.get_stage_count()
	var stage := _visual_stage(instance)
	visual.set_meta("crop_stage", stage)
	visual.set_meta("lifecycle_state", instance.lifecycle_state)
	var box := mesh_visual.mesh as BoxMesh
	if box:
		box.size = _visual_size_for_stage(stage, total_stages)
		mesh_visual.position.y = cell.terrain_height + box.size.y * 0.5 + 0.035
	_update_visual_color(mesh_visual, stage, total_stages, instance.lifecycle_state)
	_apply_visual_state(visual, instance.lifecycle_state)


func _stage_scene_path(instance: CropInstance) -> String:
	if instance == null or instance.crop_data == null or instance.crop_data.stage_scenes.is_empty():
		return ""
	var stage := _visual_stage(instance)
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
	var visual_seed := crop_visual_seed(cell, instance.crop_data.crop_id)
	if visual.has_method("configure_variant_seed"):
		visual.call("configure_variant_seed", visual_seed)
	visual.set_meta("crop_id", instance.crop_data.crop_id)
	visual.set_meta("crop_stage", _visual_stage(instance))
	visual.set_meta("lifecycle_state", instance.lifecycle_state)
	visual.set_meta("stage_scene", scene_path)
	visual.set_meta("visual_seed", visual_seed)
	_visual_parent().add_child(visual)
	_apply_visual_state(visual, instance.lifecycle_state)
	return visual


func _instantiate_fallback_visual(cell: GridCell, instance: CropInstance) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = "CropVisual_%d_%d" % [cell.gx, cell.gz]
	visual.mesh = BoxMesh.new()
	var pos := cell.world_position_3d()
	visual.position = Vector3(pos.x, pos.y, pos.z)
	visual.set_meta("crop_id", instance.crop_data.crop_id if instance.crop_data else "")
	visual.set_meta("crop_stage", _visual_stage(instance))
	visual.set_meta("lifecycle_state", instance.lifecycle_state)
	visual.set_meta("stage_scene", "")
	_visual_parent().add_child(visual)
	var total_stages := instance.get_stage_count()
	var box := visual.mesh as BoxMesh
	var stage := _visual_stage(instance)
	box.size = _visual_size_for_stage(stage, total_stages)
	visual.position.y = cell.terrain_height + box.size.y * 0.5 + 0.035
	_update_visual_color(visual, stage, total_stages, instance.lifecycle_state)
	_apply_visual_state(visual, instance.lifecycle_state)
	return visual


func _visual_stage(instance: CropInstance) -> int:
	if instance == null:
		return 0
	var stage := instance.get_current_stage()
	if instance.lifecycle_state == CropInstance.LifecycleState.DORMANT:
		return mini(2, maxi(0, instance.get_stage_count() - 1))
	return stage


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


func _update_visual_color(
	visual: MeshInstance3D,
	stage: int,
	total_stages: int,
	_lifecycle_state: int = CropInstance.LifecycleState.GROWING
) -> void:
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
	visual.remove_meta("crop_state_base_override_color")


func _apply_visual_state(visual: Node, lifecycle_state: int) -> void:
	if visual == null:
		return
	visual.set_meta("lifecycle_state", lifecycle_state)
	var tint := Color.WHITE
	if lifecycle_state == CropInstance.LifecycleState.DORMANT:
		tint = Color(0.68, 0.72, 0.65, 1.0)
	elif lifecycle_state == CropInstance.LifecycleState.WITHERED:
		tint = Color(0.82, 0.68, 0.38, 1.0)
	if visual is Sprite3D:
		var sprite := visual as Sprite3D
		if not sprite.has_meta("crop_state_base_modulate"):
			sprite.set_meta("crop_state_base_modulate", sprite.modulate)
		sprite.modulate = (sprite.get_meta("crop_state_base_modulate") as Color) * tint
	elif visual is MeshInstance3D:
		_apply_mesh_visual_state(visual as MeshInstance3D, tint)
	for child in visual.get_children():
		_apply_visual_state(child, lifecycle_state)


func _apply_mesh_visual_state(visual: MeshInstance3D, tint: Color) -> void:
	if visual.material_override is StandardMaterial3D:
		if not visual.has_meta("crop_state_base_override_color"):
			var owned_override := visual.material_override.duplicate() as StandardMaterial3D
			visual.material_override = owned_override
			visual.set_meta("crop_state_base_override_color", owned_override.albedo_color)
		var override := visual.material_override as StandardMaterial3D
		override.albedo_color = (
			visual.get_meta("crop_state_base_override_color") as Color
		) * tint
		return
	if visual.mesh == null:
		return
	if not visual.has_meta("crop_state_base_surface_colors"):
		var owned_mesh := visual.mesh.duplicate() as Mesh
		var base_colors: Array[Color] = []
		for surface in range(owned_mesh.get_surface_count()):
			var source := owned_mesh.surface_get_material(surface)
			if source is StandardMaterial3D:
				var owned_material := source.duplicate() as StandardMaterial3D
				owned_mesh.surface_set_material(surface, owned_material)
				base_colors.append(owned_material.albedo_color)
			else:
				base_colors.append(Color.TRANSPARENT)
		visual.mesh = owned_mesh
		visual.set_meta("crop_state_base_surface_colors", base_colors)
	var colors := visual.get_meta("crop_state_base_surface_colors") as Array
	for surface in range(visual.mesh.get_surface_count()):
		var material := visual.mesh.surface_get_material(surface) as StandardMaterial3D
		if material != null and surface < colors.size():
			material.albedo_color = (colors[surface] as Color) * tint


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


func finalize_environment_restore() -> void:
	_reassess_all_environments()
	rebuild_visuals()


func _visual_parent() -> Node3D:
	var parent := get_node_or_null("CropVisuals") as Node3D
	if parent == null:
		parent = Node3D.new()
		parent.name = "CropVisuals"
		add_child(parent)
	return parent
