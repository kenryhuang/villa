extends RefCounted

## Validate that all 14 non-grain crops have painted textures and stage scenes.
## Follows the same pattern as test_grain_crop_art_assets.gd.

const STAGE_COUNT := 4
const VARIANT_COUNT := 3
const LAYERS := ["back", "front"]

const TWO_STAGE_CROP_IDS: Array[String] = [
	"potato", "tomato", "lavender", "rose", "carrot",
	"apple", "peach", "lemon", "grape",
]
const LEGACY_FOUR_STAGE_CROP_IDS: Array[String] = [
	"strawberry", "blueberry",
	"watermelon", "sunflower", "pumpkin",
]


static func texture_path(crop_id: String, stage: int, variant: int, layer: String) -> String:
	return "res://assets/crops/%s/painted/stage_%d/variant_%d_%s.png" % [
		crop_id, stage, variant, layer
	]


static func stage_scene_path(crop_id: String, stage: int) -> String:
	return "res://assets/crops/%s/%s_stage_%d_%s.tscn" % [
		crop_id, crop_id, stage, ["seed", "sprout", "growing", "mature"][stage]
	]


func run(assertions: TestAssert) -> void:
	for crop_id in LEGACY_FOUR_STAGE_CROP_IDS:
		_validate_painted_textures(crop_id, assertions)
		_validate_stage_scenes(crop_id, assertions)
	for crop_id in TWO_STAGE_CROP_IDS:
		_validate_two_stage_crop(crop_id, assertions)


func _validate_two_stage_crop(crop_id: String, assertions: TestAssert) -> void:
	for stage in STAGE_COUNT:
		for variant in VARIANT_COUNT:
			for layer in LAYERS:
				var path := texture_path(crop_id, stage, variant, layer)
				var required := stage in [0, 3] and variant == 0
				assertions.equal(ResourceLoader.exists(path), required, "%s exact two-stage texture contract: %s" % [crop_id, path])
				if not required or not ResourceLoader.exists(path):
					continue
				var texture := load(path) as Texture2D
				assertions.truthy(texture != null, "%s imports as Texture2D" % path)
				if texture != null:
					assertions.equal(texture.get_size(), Vector2(1024, 1024), "%s is 1024 square" % path)
					var image := texture.get_image()
					assertions.truthy(image.detect_alpha(), "%s contains alpha" % path)
					assertions.truthy(image.get_used_rect().has_area(), "%s contains visible painted pixels" % path)
					for corner in [
						Vector2i(0, 0),
						Vector2i(image.get_width() - 1, 0),
						Vector2i(0, image.get_height() - 1),
						Vector2i(image.get_width() - 1, image.get_height() - 1),
					]:
						assertions.truthy(
							image.get_pixelv(corner).a <= 0.01,
							"%s has a transparent corner at %s" % [path, corner]
						)
	for stage in STAGE_COUNT:
		assertions.equal(ResourceLoader.exists(stage_scene_path(crop_id, stage)), stage in [0, 3], "%s exact two-stage scene contract at logical stage %d" % [crop_id, stage])


func _validate_painted_textures(crop_id: String, assertions: TestAssert) -> void:
	for stage in STAGE_COUNT:
		for variant in VARIANT_COUNT:
			for layer in LAYERS:
				var path := texture_path(crop_id, stage, variant, layer)
				assertions.truthy(ResourceLoader.exists(path), "%s painted texture %s exists" % [crop_id, path])
				if not ResourceLoader.exists(path):
					continue
				var texture := load(path) as Texture2D
				assertions.truthy(texture != null, "%s painted texture %s imports as Texture2D" % [crop_id, path])
				if texture == null:
					continue
				assertions.equal(
					texture.get_size(),
					Vector2(1024, 1024),
					"%s painted texture %s is 1024 square" % [crop_id, path]
				)
				var image := texture.get_image()
				assertions.truthy(image.detect_alpha(), "%s painted texture %s contains alpha" % [crop_id, path])


func _validate_stage_scenes(crop_id: String, assertions: TestAssert) -> void:
	for stage in STAGE_COUNT:
		var path := stage_scene_path(crop_id, stage)
		assertions.truthy(ResourceLoader.exists(path), "%s stage %d scene exists" % [crop_id, stage])
