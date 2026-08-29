extends RefCounted

const STAGE_PATHS := [
	"res://assets/crops/grain/grain_stage_0_seed.tscn",
	"res://assets/crops/grain/grain_stage_1_sprout.tscn",
	"res://assets/crops/grain/grain_stage_2_growing.tscn",
	"res://assets/crops/grain/grain_stage_3_mature.tscn",
]
const MINIMUM_MESH_COUNTS := [3, 4, 12, 25]
const ClusterScript = preload("res://scripts/visual/crop_sprite_cluster.gd")


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(_mesh_instances(child))
	return result


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var crop := CropData.new()
	var has_stage_scenes := _has_property(crop, "stage_scenes")
	assertions.truthy(has_stage_scenes, "CropData exposes stage_scenes")
	for index in STAGE_PATHS.size():
		var path: String = STAGE_PATHS[index]
		assertions.truthy(ResourceLoader.exists(path), "grain stage %d scene exists" % index)
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		var model := packed.instantiate() as Node3D
		var meshes := _mesh_instances(model)
		assertions.truthy(meshes.size() >= MINIMUM_MESH_COUNTS[index], "grain stage %d has expected model detail" % index)
		for mesh_instance in meshes:
			assertions.truthy(mesh_instance.mesh != null, "grain stage %d mesh is assigned" % index)
		assertions.truthy(
			model.get_script() == ClusterScript,
			"grain stage %d uses CropSpriteCluster" % index
		)
		if model.get_script() == ClusterScript:
			model.configure_variant_seed(7)
			tree.root.add_child(model)
			assertions.equal(
				model.get_variant_index(),
				1,
				"grain stage %d selects painted variant" % index
			)
			assertions.truthy(
				model.get_node("BackLayer").visible,
				"grain stage %d shows back layer" % index
			)
			assertions.truthy(
				model.get_node("FrontLayer").visible,
				"grain stage %d shows front layer" % index
			)
			for mesh_instance in meshes:
				assertions.equal(
					mesh_instance.visible,
					false,
					"grain stage %d hides fallback model" % index
				)
		model.free()
	if not has_stage_scenes:
		return

	crop.crop_id = "grain"
	crop.growth_days = 3
	crop.growth_duration_minutes = 3
	crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
	var stage_scenes: Array[String] = []
	for path in STAGE_PATHS:
		stage_scenes.append(path)
	crop.stage_scenes.assign(stage_scenes)
	var grid := GridSystem.new()
	var farming = load("res://scenes/systems/farming_system.tscn").instantiate()
	tree.root.add_child(farming)
	farming.configure(grid, null, null)
	grid.set_cell_state(8, 8, GridCell.State.FARMLAND)
	var cell := grid.get_cell(8, 8)
	farming.plant(cell, crop)
	var visual: Node3D = farming.get_crop_visual(cell)
	assertions.equal(visual.get_meta("stage_scene", ""), STAGE_PATHS[0], "plant uses grain seed model")
	if visual.has_method("get_variant_index"):
		var first_variant: int = visual.call("get_variant_index")
		farming.rebuild_visuals()
		visual = farming.get_crop_visual(cell)
		assertions.equal(
			visual.call("get_variant_index"),
			first_variant,
			"rebuild preserves grid-based variant"
		)
		assertions.equal(
			visual.get_meta("visual_seed"),
			FarmingSystem.crop_visual_seed(cell, crop.crop_id),
			"visual stores deterministic seed"
		)
	farming.advance_growth_minutes(1)
	visual = farming.get_crop_visual(cell)
	assertions.equal(visual.get_meta("stage_scene", ""), STAGE_PATHS[1], "growth replaces seed with sprout model")
	farming.free()
	grid.free()
