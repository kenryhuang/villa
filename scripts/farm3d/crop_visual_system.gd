class_name Farm3DCropVisualSystem
extends Node3D

const SOIL_SCENE := preload("res://assets/models/farm3d/farmland_tile.glb")
const YOUNG_SCENE := preload("res://assets/models/farm3d/grain_young.glb")
const MATURE_SCENE := preload("res://assets/models/farm3d/grain_mature.glb")
const ROSE_STAGES := [
	preload("res://assets/models/crops/rose/rose_seed.glb"),
	preload("res://assets/models/crops/rose/rose_sprout.glb"),
	preload("res://assets/models/crops/rose/rose_growing.glb"),
	preload("res://assets/models/crops/rose/rose_mature.glb"),
]
const ROSE_WITHERED := preload("res://assets/models/crops/rose/rose_withered.glb")
const SOIL_SURFACE_Y := 0.045
const TWO_STAGE_CROPS := {
	"carrot": [preload("res://assets/models/crops/carrot/carrot_seed.glb"), preload("res://assets/models/crops/carrot/carrot_mature.glb")],
	"strawberry": [preload("res://assets/models/crops/strawberry/strawberry_seed.glb"), preload("res://assets/models/crops/strawberry/strawberry_mature.glb")],
	"blueberry": [preload("res://assets/models/crops/blueberry/blueberry_seed.glb"), preload("res://assets/models/crops/blueberry/blueberry_mature.glb")],
	"watermelon": [preload("res://assets/models/crops/watermelon/watermelon_seed.glb"), preload("res://assets/models/crops/watermelon/watermelon_mature.glb")],
	"sunflower": [preload("res://assets/models/crops/sunflower/sunflower_seed.glb"), preload("res://assets/models/crops/sunflower/sunflower_mature.glb")],
	"pumpkin": [preload("res://assets/models/crops/pumpkin/pumpkin_seed.glb"), preload("res://assets/models/crops/pumpkin/pumpkin_mature.glb")],
	"apple": [preload("res://assets/models/crops/apple/apple_seed.glb"), preload("res://assets/models/crops/apple/apple_mature.glb")],
	"peach": [preload("res://assets/models/crops/peach/peach_seed.glb"), preload("res://assets/models/crops/peach/peach_mature.glb")],
	"grape": [preload("res://assets/models/crops/grape/grape_seed.glb"), preload("res://assets/models/crops/grape/grape_mature.glb")],
	"lemon": [preload("res://assets/models/crops/lemon/lemon_seed.glb"), preload("res://assets/models/crops/lemon/lemon_mature.glb")],
	"potato": [preload("res://assets/models/crops/potato/potato_seed.glb"), preload("res://assets/models/crops/potato/potato_mature.glb")],
	"tomato": [preload("res://assets/models/crops/tomato/tomato_seed.glb"), preload("res://assets/models/crops/tomato/tomato_mature.glb")],
	"lavender": [preload("res://assets/models/crops/lavender/lavender_seed.glb"), preload("res://assets/models/crops/lavender/lavender_mature.glb")],
}

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
	if TWO_STAGE_CROPS.has(instance.crop_data.crop_id):
		_add_two_stage_crop(holder, cell)
		return
	if instance.crop_data.crop_id == "rose":
		_add_rose(holder, cell)
		return
	if instance.crop_data.crop_id != "grain":
		push_error("Missing 3D crop model: " + str(instance.crop_data.crop_id))
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


func _add_two_stage_crop(holder: Node3D, cell: GridCell) -> void:
	var instance: CropInstance = cell.crop_instance
	var crop_id: String = instance.crop_data.crop_id
	var withered := instance.lifecycle_state == CropInstance.LifecycleState.WITHERED
	var grown := instance.growth_progress >= float(instance.crop_data.growth_days)
	var packed: PackedScene = TWO_STAGE_CROPS[crop_id][1 if grown else 0]
	var crop := packed.instantiate() as Node3D
	crop.name = "Crop_" + crop_id
	crop.position.y = SOIL_SURFACE_Y
	crop.rotation.y = deg_to_rad(float(posmod(cell.gx * 37 + cell.gz * 19, 360)))
	holder.add_child(crop)
	for mesh_node in crop.find_children("*", "MeshInstance3D", true, false):
		if withered:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("78613c")
			material.roughness = 0.95
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_node.material_override = material


func _add_rose(holder: Node3D, cell: GridCell) -> void:
	var instance: CropInstance = cell.crop_instance
	var stage := clampi(instance.get_current_stage(), 0, ROSE_STAGES.size() - 1)
	var withered := instance.lifecycle_state == CropInstance.LifecycleState.WITHERED
	var packed: PackedScene = ROSE_WITHERED if withered and stage >= 2 else ROSE_STAGES[stage]
	var rose := packed.instantiate() as Node3D
	rose.name = "Crop_rose"
	# All exported stages share a root at zero; roots and seeds intersect the soil.
	# Never offset by image dimensions or face the camera.
	rose.position.y = SOIL_SURFACE_Y
	rose.rotation.y = deg_to_rad(float(posmod(cell.gx * 37 + cell.gz * 19, 360)))
	if withered and stage == 2:
		rose.scale = Vector3.ONE * 0.65
	holder.add_child(rose)
	if withered and stage < 2:
		for mesh_node in rose.find_children("*", "MeshInstance3D", true, false):
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("78613c")
			material.roughness = 0.95
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_node.material_override = material
