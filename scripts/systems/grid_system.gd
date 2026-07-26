class_name GridSystem
extends Node3D

const GRID_WIDTH := 36
const GRID_DEPTH := 28
const CELL_SIZE := 1.0
const WORLD_ORIGIN_X := -18.0
const WORLD_ORIGIN_Z := -14.0
const SLOPE_THRESHOLD := 0.35
const GRID_LINE_LIFT := 0.035
const HIGHLIGHT_LIFT := 0.045

var terrain: TerrainBuilder
var _cells := {}
var _base_states := {}
var _event_bus
var _road_route: Array[Dictionary] = []
var _blocked_regions: Array[Dictionary] = []


static func cell_key(gx: int, gz: int) -> int:
	return gx * 1000 + gz


func configure(
	terrain_node: TerrainBuilder,
	road_route: Array[Dictionary] = [],
	blocked_regions: Array[Dictionary] = []
) -> bool:
	if terrain_node == null or terrain_node.height_image == null or terrain_node.height_image.is_empty():
		push_error("GridSystem requires a built TerrainBuilder")
		set_grid_visible(false)
		return false
	terrain = terrain_node
	_road_route.assign(road_route)
	_blocked_regions.assign(blocked_regions)
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	_initialize_cells()
	_build_grid_overlay()
	clear_highlights()
	return true


func world_to_grid(wx: float, wz: float) -> Vector2i:
	return Vector2i(
		floori((wx - WORLD_ORIGIN_X) / CELL_SIZE),
		floori((wz - WORLD_ORIGIN_Z) / CELL_SIZE)
	)


func grid_to_world(gx: int, gz: int) -> Vector2:
	return Vector2(
		WORLD_ORIGIN_X + (float(gx) + 0.5) * CELL_SIZE,
		WORLD_ORIGIN_Z + (float(gz) + 0.5) * CELL_SIZE
	)


func _is_in_bounds(gx: int, gz: int) -> bool:
	return gx >= 0 and gx < GRID_WIDTH and gz >= 0 and gz < GRID_DEPTH


func _initialize_cells() -> void:
	_cells.clear()
	_base_states.clear()
	for gz in GRID_DEPTH:
		for gx in GRID_WIDTH:
			var cell := _create_cell(gx, gz)
			cell.state = _initial_state_for(cell.world_position())
			var key := cell_key(gx, gz)
			_cells[key] = cell
			_base_states[key] = cell.state


func _create_cell(gx: int, gz: int) -> GridCell:
	var cell := GridCell.new()
	cell.gx = gx
	cell.gz = gz
	if terrain:
		var point := grid_to_world(gx, gz)
		cell.terrain_height = terrain.get_height_at(point.x, point.y)
		cell.slope = _calc_slope(gx, gz)
	return cell


func _ensure_cell(gx: int, gz: int) -> GridCell:
	var key := cell_key(gx, gz)
	if _cells.has(key):
		return _cells[key]
	var cell := _create_cell(gx, gz)
	_cells[key] = cell
	_base_states[key] = cell.state
	return cell


func _initial_state_for(point: Vector2) -> GridCell.State:
	for region in _blocked_regions:
		var rect = region.get("rect")
		var state := int(region.get("state", -1))
		if rect is Rect2 and rect.has_point(point) and state in [
			GridCell.State.WATER,
			GridCell.State.BUILDING,
			GridCell.State.DECORATION,
		]:
			return state as GridCell.State
	if _is_point_on_road(point):
		return GridCell.State.ROAD
	return GridCell.State.WASTELAND


func _is_point_on_road(point: Vector2) -> bool:
	if _road_route.size() < 2:
		return false
	var cell_padding := CELL_SIZE * sqrt(2.0) * 0.5
	for index in range(_road_route.size() - 1):
		var start_data := _road_route[index]
		var end_data := _road_route[index + 1]
		if not start_data.has("x") or not start_data.has("z") or not end_data.has("x") or not end_data.has("z"):
			continue
		var start := Vector2(float(start_data.x), float(start_data.z))
		var finish := Vector2(float(end_data.x), float(end_data.z))
		var segment := finish - start
		var length_squared := segment.length_squared()
		var ratio := 0.0
		if length_squared > 0.000001:
			ratio = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
		var closest := start + segment * ratio
		var start_width := float(start_data.get("width", CELL_SIZE))
		var end_width := float(end_data.get("width", start_width))
		var half_width := lerpf(start_width, end_width, ratio) * 0.5
		if point.distance_to(closest) <= half_width + cell_padding:
			return true
	return false


func _calc_slope(gx: int, gz: int) -> float:
	if terrain == null:
		return 0.0
	var point := grid_to_world(gx, gz)
	var center := terrain.get_height_at(point.x, point.y)
	var sx := absf(terrain.get_height_at(point.x + 0.5, point.y) - center) / 0.5
	var sz := absf(terrain.get_height_at(point.x, point.y + 0.5) - center) / 0.5
	return sqrt(sx * sx + sz * sz)


func get_cell(gx: int, gz: int) -> GridCell:
	if not _is_in_bounds(gx, gz):
		return null
	return _ensure_cell(gx, gz)


func get_cell_at_world(wx: float, wz: float) -> GridCell:
	var grid_pos := world_to_grid(wx, wz)
	return get_cell(grid_pos.x, grid_pos.y)


func get_cells_in_rect(gx: int, gz: int, w: int, h: int) -> Array:
	var result := []
	for z in range(gz, gz + h):
		for x in range(gx, gx + w):
			if _is_in_bounds(x, z):
				result.append(_ensure_cell(x, z))
	return result


func get_terrain_height_at_cell(gx: int, gz: int) -> float:
	var cell := get_cell(gx, gz)
	return cell.terrain_height if cell else NAN


func get_slope_at_cell(gx: int, gz: int) -> float:
	var cell := get_cell(gx, gz)
	return cell.slope if cell else NAN


func can_farm_at(gx: int, gz: int) -> bool:
	var cell := get_cell(gx, gz)
	if cell == null or cell.slope > SLOPE_THRESHOLD:
		return false
	return cell.state == GridCell.State.WASTELAND


func is_cell_available(gx: int, gz: int, required_state: int) -> bool:
	var cell := get_cell(gx, gz)
	return cell != null and cell.state == required_state


func set_cell_state(gx: int, gz: int, next_state: int) -> bool:
	var cell := get_cell(gx, gz)
	if cell == null:
		return false
	if cell.state == GridCell.State.WASTELAND and next_state == GridCell.State.FARMLAND:
		if not can_farm_at(gx, gz):
			return false
	if not _transition_allowed(cell.state, next_state):
		return false
	cell.state = next_state
	_emit_cell_state_changed(cell)
	return true


func _transition_allowed(current: int, next: int) -> bool:
	if current == next:
		return true
	if current == GridCell.State.WASTELAND:
		return next == GridCell.State.FARMLAND or next == GridCell.State.BUILDING
	if current == GridCell.State.FARMLAND:
		return next == GridCell.State.BUILDING
	if current == GridCell.State.PLANTED:
		return next == GridCell.State.FARMLAND
	if current == GridCell.State.BUILDING:
		return next == GridCell.State.WASTELAND or next == GridCell.State.FARMLAND
	return false


func plant_crop(gx: int, gz: int, crop_data) -> CropInstance:
	if crop_data == null or not is_cell_available(gx, gz, GridCell.State.FARMLAND):
		return null
	var cell := get_cell(gx, gz)
	var instance := CropInstance.new()
	instance.crop_data = crop_data
	cell.crop_instance = instance
	cell.state = GridCell.State.PLANTED
	_emit_cell_state_changed(cell)
	if _event_bus:
		_event_bus.crop_planted.emit(gx, gz, crop_data.crop_id)
	return instance


func harvest_crop(gx: int, gz: int) -> Dictionary:
	var cell := get_cell(gx, gz)
	if cell == null or cell.state != GridCell.State.PLANTED or cell.crop_instance == null:
		return {}
	if cell.crop_instance.growth_progress < cell.crop_instance.crop_data.growth_days:
		return {}
	var crop_id: String = cell.crop_instance.crop_data.crop_id
	var exp_reward: int = cell.crop_instance.crop_data.exp_reward
	if _event_bus:
		_event_bus.crop_harvested.emit(gx, gz, crop_id)
	cell.crop_instance = null
	cell.watered = false
	cell.state = GridCell.State.FARMLAND
	_emit_cell_state_changed(cell)
	return {"items": [crop_id], "exp": exp_reward}


func water_cell(gx: int, gz: int) -> bool:
	var cell := get_cell(gx, gz)
	if cell == null or cell.state not in [GridCell.State.FARMLAND, GridCell.State.PLANTED]:
		return false
	cell.watered = true
	if cell.crop_instance:
		cell.crop_instance.is_watered_today = true
	if _event_bus:
		_event_bus.cell_watered.emit(gx, gz)
	return true


func _emit_cell_state_changed(cell: GridCell) -> void:
	if _event_bus:
		_event_bus.cell_state_changed.emit(cell.gx, cell.gz, cell.state)


func set_grid_visible(value: bool) -> void:
	var overlay := get_node_or_null("GridOverlay") as MeshInstance3D
	if overlay:
		overlay.visible = value


func _build_grid_overlay() -> void:
	var overlay := get_node_or_null("GridOverlay") as MeshInstance3D
	if overlay == null or terrain == null:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for gx in range(GRID_WIDTH + 1):
		var world_x := WORLD_ORIGIN_X + float(gx) * CELL_SIZE
		for gz in GRID_DEPTH:
			var z0 := WORLD_ORIGIN_Z + float(gz) * CELL_SIZE
			var z1 := z0 + CELL_SIZE
			surface.add_vertex(Vector3(world_x, terrain.get_height_at(world_x, z0) + GRID_LINE_LIFT, z0))
			surface.add_vertex(Vector3(world_x, terrain.get_height_at(world_x, z1) + GRID_LINE_LIFT, z1))
	for gz in range(GRID_DEPTH + 1):
		var world_z := WORLD_ORIGIN_Z + float(gz) * CELL_SIZE
		for gx in GRID_WIDTH:
			var x0 := WORLD_ORIGIN_X + float(gx) * CELL_SIZE
			var x1 := x0 + CELL_SIZE
			surface.add_vertex(Vector3(x0, terrain.get_height_at(x0, world_z) + GRID_LINE_LIFT, world_z))
			surface.add_vertex(Vector3(x1, terrain.get_height_at(x1, world_z) + GRID_LINE_LIFT, world_z))
	var mesh := surface.commit()
	overlay.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.95, 0.94, 0.78, 0.62)
	material.no_depth_test = true
	overlay.material_override = material


func highlight_cell(gx: int, gz: int, color: Color) -> bool:
	var highlight := get_node_or_null("GridCells/CellHighlight") as MeshInstance3D
	if highlight == null or terrain == null or not _is_in_bounds(gx, gz):
		clear_highlights()
		return false
	var x0 := WORLD_ORIGIN_X + float(gx) * CELL_SIZE
	var z0 := WORLD_ORIGIN_Z + float(gz) * CELL_SIZE
	var x1 := x0 + CELL_SIZE
	var z1 := z0 + CELL_SIZE
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [
		Vector3(x0, terrain.get_height_at(x0, z0) + HIGHLIGHT_LIFT, z0),
		Vector3(x1, terrain.get_height_at(x1, z0) + HIGHLIGHT_LIFT, z0),
		Vector3(x1, terrain.get_height_at(x1, z1) + HIGHLIGHT_LIFT, z1),
		Vector3(x0, terrain.get_height_at(x0, z1) + HIGHLIGHT_LIFT, z1),
	]
	for point in points:
		surface.add_vertex(point)
	for index in [0, 2, 1, 0, 3, 2]:
		surface.add_index(index)
	highlight.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, minf(color.a, 0.58))
	material.no_depth_test = true
	highlight.material_override = material
	highlight.visible = true
	return true


func clear_highlights() -> void:
	var highlight := get_node_or_null("GridCells/CellHighlight") as MeshInstance3D
	if highlight:
		highlight.visible = false


func to_dict() -> Dictionary:
	var changed_cells: Array[Dictionary] = []
	for key in _cells:
		var cell: GridCell = _cells[key]
		if cell.state == _base_states.get(key, GridCell.State.WASTELAND) and not cell.watered and cell.crop_instance == null:
			continue
		var entry := {
			"gx": cell.gx,
			"gz": cell.gz,
			"state": cell.state,
			"watered": cell.watered,
		}
		if cell.crop_instance and cell.crop_instance.crop_data:
			entry["crop"] = {
				"crop_id": cell.crop_instance.crop_data.crop_id,
				"growth_progress": cell.crop_instance.growth_progress,
				"is_watered_today": cell.crop_instance.is_watered_today,
			}
		changed_cells.append(entry)
	return {"version": 1, "cells": changed_cells}


func from_dict(data: Dictionary) -> bool:
	if not data.has("cells") or not data.cells is Array:
		return false
	for entry in data.cells:
		if not entry is Dictionary:
			continue
		var gx := int(entry.get("gx", -1))
		var gz := int(entry.get("gz", -1))
		var cell := get_cell(gx, gz)
		if cell == null:
			continue
		var state := int(entry.get("state", cell.state))
		if state < GridCell.State.WASTELAND or state > GridCell.State.DECORATION:
			continue
		cell.state = state
		cell.watered = bool(entry.get("watered", false))
		cell.crop_instance = null
		if entry.has("crop"):
			var crop_entry: Dictionary = entry.crop
			var game_data = get_node_or_null("/root/GameData") if is_inside_tree() else null
			var crop_data = game_data.get_crop(str(crop_entry.get("crop_id", ""))) if game_data else null
			if crop_data:
				var instance := CropInstance.new()
				instance.crop_data = crop_data
				instance.growth_progress = float(crop_entry.get("growth_progress", 0.0))
				instance.is_watered_today = bool(crop_entry.get("is_watered_today", false))
				cell.crop_instance = instance
	return true
