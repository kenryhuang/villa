extends RefCounted

## Validate that all 14 non-grain crops have stage scenes with CropSpriteCluster
## and appropriate 3D mesh children. Follows test_grain_crop_models.gd pattern.

const TWO_STAGE_CROP_IDS: Array[String] = ["potato", "tomato", "lavender", "rose"]
const LEGACY_FOUR_STAGE_CROP_IDS: Array[String] = [
	"carrot", "strawberry", "blueberry",
	"watermelon", "sunflower", "pumpkin",
	"apple", "peach", "grape", "lemon",
]
const CROP_IDS: Array[String] = TWO_STAGE_CROP_IDS + LEGACY_FOUR_STAGE_CROP_IDS

const MINIMUM_MESH_COUNTS := [2, 3, 3, 3]
const ClusterScript = preload("res://scripts/visual/crop_sprite_cluster.gd")


static func stage_scene_path(crop_id: String, stage: int) -> String:
	return "res://assets/crops/%s/%s_stage_%d_%s.tscn" % [
		crop_id, crop_id, stage, ["seed", "sprout", "growing", "mature"][stage]
	]


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(_mesh_instances(child))
	return result


func run(assertions: TestAssert, tree: SceneTree) -> void:
	for crop_id in LEGACY_FOUR_STAGE_CROP_IDS:
		for stage in 4:
			var path := stage_scene_path(crop_id, stage)
			assertions.truthy(ResourceLoader.exists(path), "%s stage %d scene exists" % [crop_id, stage])
			if not ResourceLoader.exists(path):
				continue
			var packed := load(path) as PackedScene
			var model := packed.instantiate() as Node3D
			var meshes := _mesh_instances(model)
			assertions.truthy(
				meshes.size() >= MINIMUM_MESH_COUNTS[stage],
				"%s stage %d has at least %d mesh instances (got %d)" % [
					crop_id, stage, MINIMUM_MESH_COUNTS[stage], meshes.size()
				]
			)
			for mesh_instance in meshes:
				assertions.truthy(mesh_instance.mesh != null, "%s stage %d mesh is assigned" % [crop_id, stage])
			assertions.truthy(
				model.get_script() == ClusterScript,
				"%s stage %d uses CropSpriteCluster" % [crop_id, stage]
			)
			if model.get_script() == ClusterScript:
				model.configure_variant_seed(7)
				tree.root.add_child(model)
				assertions.truthy(
					model.get_variant_index() >= 0,
					"%s stage %d selects a painted variant" % [crop_id, stage]
				)
				model.free()
			else:
				model.free()
	for crop_id in TWO_STAGE_CROP_IDS:
		for stage in [0, 3]:
			var path := stage_scene_path(crop_id, stage)
			assertions.truthy(ResourceLoader.exists(path), "%s two-stage scene exists" % path)
			if not ResourceLoader.exists(path):
				continue
			var model := (load(path) as PackedScene).instantiate() as Node3D
			assertions.truthy(model.get_script() == ClusterScript, "%s uses CropSpriteCluster" % path)
			assertions.equal(_mesh_instances(model).size(), 0, "%s has no procedural crop meshes" % path)
			assertions.equal(model.back_texture_paths.size(), 1, "%s owns one back sprite" % path)
			assertions.equal(model.front_texture_paths.size(), 1, "%s owns one front sprite" % path)
			model.configure_variant_seed(7)
			tree.root.add_child(model)
			assertions.equal(model.get_variant_index(), 0, "%s always selects variant zero" % path)
			var back := model.get_node_or_null("BackLayer") as Sprite3D
			var front := model.get_node_or_null("FrontLayer") as Sprite3D
			assertions.truthy(back != null and back.visible and back.texture != null, "%s renders its back layer" % path)
			assertions.truthy(front != null and front.visible and front.texture != null, "%s renders its front layer" % path)
			model.free()

	# Verify that default_crop_definitions assigns stage_scenes for all crops
	# Only when Main script is accessible (not in isolated test context)
	var main_script = load("res://main.gd") if ResourceLoader.exists("res://main.gd") else null
	if main_script != null and main_script.has_method("default_crop_definitions"):
		var definitions = main_script.default_crop_definitions()
		if definitions != null:
			var crop_ids_found: Array[String] = []
			for crop in definitions:
				crop_ids_found.append(crop.crop_id)
			for expected_id in CROP_IDS:
				assertions.truthy(expected_id in crop_ids_found, "default_crop_definitions includes %s" % expected_id)
			for crop in definitions:
				if crop.crop_id in CROP_IDS or crop.crop_id == "grain":
					assertions.truthy(
						not crop.stage_scenes.is_empty(),
						"%s has stage_scenes assigned" % crop.crop_id
					)
