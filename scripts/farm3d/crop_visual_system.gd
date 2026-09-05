class_name Farm3DCropVisualSystem
extends Node3D

const SOIL_SCENE := preload("res://assets/models/farm_preview/farmland_tile.glb")
const YOUNG_SCENE := preload("res://assets/models/farm_preview/grain_young.glb")
const MATURE_SCENE := preload("res://assets/models/farm_preview/grain_mature.glb")

var _visuals := {}
var paddy_cells: Dictionary = {}


func rebuild(cells: Array) -> void:
	for child in get_children():
		child.queue_free()
	_visuals.clear()
	for cell in cells:
		if cell is GridCell:
			sync_cell(cell as GridCell)


func sync_cell(cell: GridCell) -> void:
	if cell == null:
		return
	var key := GridSystem.cell_key(cell.gx, cell.gz)
	var existing: Node = _visuals.get(key)
	if existing != null:
		remove_child(existing)
		existing.queue_free()
		_visuals.erase(key)
	if cell.state not in [GridCell.State.FARMLAND, GridCell.State.PLANTED]:
		return
	var holder := Node3D.new()
	holder.name = "FarmCell_%d_%d" % [cell.gx, cell.gz]
	holder.position = cell.world_position_3d()
	add_child(holder)
	_visuals[key] = holder
	var soil := SOIL_SCENE.instantiate() as Node3D
	soil.name = "Soil"
	soil.scale = Vector3(1.0 / 2.8, 0.35, 1.0 / 2.8)
	# The imported 2.8m tile has a shallow raised top; its scaled top sits near .05.
	soil.position.y = 0.0
	holder.add_child(soil)
	var collider := StaticBody3D.new()
	collider.name = "FarmlandCollision"
	collider.collision_layer = 1
	collider.collision_mask = 1
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.045, 1.0)
	collision_shape.shape = box
	collider.position.y = 0.0225
	collider.add_child(collision_shape)
	holder.add_child(collider)
	if paddy_cells.has(key):
		var water := MeshInstance3D.new()
		water.name = "PaddyWater"
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.87, 0.87)
		water.mesh = plane
		water.position.y = 0.059
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.46, 0.41, 0.75)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.18
		water.material_override = material
		holder.add_child(water)
	if cell.crop_instance != null:
		_add_crop(holder, cell)


func _add_crop(holder: Node3D, cell: GridCell) -> void:
	var instance: CropInstance = cell.crop_instance
	if instance.crop_data.crop_id != "grain":
		var paths: Array[String] = instance.crop_data.stage_scenes
		var stage := clampi(instance.get_current_stage(), 0, paths.size() - 1)
		var packed := load(paths[stage]) as PackedScene
		if packed != null:
			var crop := packed.instantiate() as Node3D
			crop.name = "Crop_" + instance.crop_data.crop_id
			crop.position.y = 0.06
			holder.add_child(crop)
			if instance.lifecycle_state == CropInstance.LifecycleState.WITHERED:
				for sprite in crop.find_children("*", "Sprite3D", true, false):
					sprite.modulate = Color("91794e")
		return
	var progress := instance.growth_progress
	var maturity := maxf(1.0, float(instance.crop_data.growth_days))
	var stage := instance.get_current_stage()
	var withered := instance.lifecycle_state == CropInstance.LifecycleState.WITHERED
	if stage == 0:
		var seed_material := StandardMaterial3D.new()
		seed_material.albedo_color = Color("8c7346") if withered else Color("b5985d")
		seed_material.roughness = 0.95
		var kernel := SphereMesh.new()
		kernel.radius = 0.024
		kernel.height = 0.048
		kernel.radial_segments = 8
		kernel.rings = 4
		for ix in 3:
			for iz in 3:
				var seed := MeshInstance3D.new()
				seed.name = "SownKernel"
				seed.mesh = kernel
				seed.material_override = seed_material
				seed.scale = Vector3(0.65, 0.5, 1.45)
				seed.position = Vector3((ix - 1) * 0.25, 0.051, (iz - 1) * 0.25)
				holder.add_child(seed)
		return
	var grown := progress >= maturity
	var scene := MATURE_SCENE if grown else YOUNG_SCENE
	var crop_scale := Vector3(0.58, 0.88, 0.58) if grown else Vector3(0.62, 0.8 if stage == 1 else 1.6, 0.62)
	for offset in [Vector3(-0.22, 0, -0.18), Vector3(0.2, 0, -0.12), Vector3(-0.1, 0, 0.2), Vector3(0.22, 0, 0.22)]:
		var crop := scene.instantiate() as Node3D
		crop.name = "WitheredGrain" if withered else ("MatureGrain" if grown else "YoungGrain")
		crop.position = offset + Vector3(0, 0.045, 0)
		crop.rotation.y = float(cell.gx * 13 + cell.gz * 7) * 0.13
		crop.scale = crop_scale
		holder.add_child(crop)
		if withered:
			crop.rotation.z = 0.22
			for mesh_node in crop.find_children("*", "MeshInstance3D", true, false):
				for surface in mesh_node.mesh.get_surface_count():
					var material := mesh_node.get_active_material(surface).duplicate() as StandardMaterial3D
					material.albedo_color = Color("91794e")
					mesh_node.set_surface_override_material(surface, material)
