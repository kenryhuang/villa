class_name WorldRangeOverlay
extends Node3D

const CELL_COLOR := Color(0.16, 0.72, 0.66, 0.36)
const CELL_SIZE := 0.92
const CELL_LIFT := 0.055

var cells: Array[Vector2i] = []


func show_cells(next_cells: Array[Vector2i], grid_system: GridSystem = null) -> void:
	clear()
	for cell in next_cells:
		if cell not in cells:
			cells.append(cell)
	for cell in cells:
		add_child(_cell_mesh(cell, grid_system))


func clear() -> void:
	cells.clear()
	for child in get_children():
		remove_child(child)
		child.free()


func _exit_tree() -> void:
	clear()


func _cell_mesh(cell: Vector2i, grid_system: GridSystem) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RangeCell_%d_%d" % [cell.x, cell.y]
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(CELL_SIZE, CELL_SIZE)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = CELL_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	mesh.material = material
	mesh_instance.mesh = mesh
	var point := (
		grid_system.grid_to_world(cell.x, cell.y)
		if grid_system != null
		else Vector2(
			GridSystem.WORLD_ORIGIN_X + (float(cell.x) + 0.5) * GridSystem.CELL_SIZE,
			GridSystem.WORLD_ORIGIN_Z + (float(cell.y) + 0.5) * GridSystem.CELL_SIZE
		)
	)
	var height := 0.0
	if grid_system != null:
		var sampled := grid_system.get_terrain_height_at_cell(cell.x, cell.y)
		if is_finite(sampled):
			height = sampled
	mesh_instance.position = Vector3(point.x, height + CELL_LIFT, point.y)
	mesh_instance.set_meta("grid_cell", cell)
	return mesh_instance
