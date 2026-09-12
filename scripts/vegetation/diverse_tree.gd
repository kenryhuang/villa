extends "res://scripts/vegetation/tree_pack_tree.gd"
## Original Blender models sharing the established wind, terrain fitting and LOD runtime.

const TREE_SPECIES := ["warm_oak", "forked_birch", "copper_maple", "golden_poplar", "blue_pine", "weeping_willow"]
const TREE_HEIGHTS := [6.2, 7.5, 5.4, 8.4, 8.0, 5.9]

static func choose_world_species(point: Vector3) -> int:
	return ("diverse-grove-v1:%d:%d" % [roundi(point.x * 100), roundi(point.z * 100)]).hash() % TREE_SPECIES.size()

func _species_catalog() -> Array:
	return TREE_SPECIES

func _choose_species(point: Vector3) -> int:
	return choose_world_species(point)

func _tree_height() -> float:
	return TREE_HEIGHTS[species_index]

func _model_path(level: int) -> String:
	return "res://assets/models/vegetation/diverse_trees/%s_lod%d.glb" % [species, level]

func _build_collisions() -> void:
	var trunk := CylinderShape3D.new()
	trunk.radius = .5
	trunk.height = 3.0
	_add_body("TrunkCollision", trunk, Vector3(0, 1.5, 0), 1)
	# Individual crown volumes follow the species silhouette; tall trees no longer
	# inherit a single low, wide crown collider from the old six-metre samples.
	var volumes: Array[Vector4] = []
	match species:
		"golden_poplar":
			volumes = [Vector4(0,3.9,0,1.25),Vector4(0,5.5,0,1.35),Vector4(.12,7.1,0,1.2)]
		"blue_pine":
			volumes = [Vector4(0,2.4,0,2.25),Vector4(0,4.1,0,1.9),Vector4(0,5.7,0,1.35),Vector4(0,7.2,0,.75)]
		"forked_birch":
			volumes = [Vector4(0,4.7,0,1.7),Vector4(.2,6.3,0,1.35),Vector4(-1.5,4.6,0,1),Vector4(1.5,4.6,0,1)]
		_:
			var crown_y := 4.2 if species == "warm_oak" else 3.7
			volumes = [Vector4(0,crown_y+.5,0,1.3),Vector4(-1.8,crown_y,0,1.3),Vector4(1.8,crown_y,0,1.3),Vector4(0,crown_y,-1.8,1.3),Vector4(0,crown_y,1.8,1.3)]
	for i in volumes.size():
		var volume := volumes[i]
		var shape := SphereShape3D.new()
		shape.radius = volume.w
		if i == 0:
			_add_body("CanopyCollision", shape, Vector3(volume.x,volume.y,volume.z), 4)
		else:
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = Vector3(volume.x,volume.y,volume.z)
			get_node("CanopyCollision").add_child(collider)
