extends RefCounted

const IDS := [
	"barn",
	"greenhouse",
	"windmill",
	"chicken_coop",
	"beehive",
	"well",
	"workbench",
	"lamp",
	"fence",
]
const PAINTED_ONLY_IDS := ["waterwheel"]
const LAYERS := ["back", "front"]
const CONSTRUCTION_STAGES := ["foundation", "frame", "half_built"]
const HAMMER_ICON_PATH := "res://assets/buildings/construction/construction_hammer_painted.png"
const HAMMER_SHADER_PATH := "res://assets/buildings/construction/construction_hammer.gdshader"
const PROGRESS_SHADER_PATH := "res://assets/buildings/construction/construction_progress.gdshader"


static func texture_path(id: String, layer: String) -> String:
	return "res://assets/buildings/painted/%s/%s_%s.png" % [id, id, layer]


static func construction_texture_path(id: String, stage: String) -> String:
	return "res://assets/buildings/construction/%s/%s_%s.png" % [id, id, stage]


func run(assertions: TestAssert) -> void:
	for id in IDS:
		for layer in LAYERS:
			_validate_texture(texture_path(id, layer), assertions)
		for stage in CONSTRUCTION_STAGES:
			_validate_texture(construction_texture_path(id, stage), assertions)
	for id in PAINTED_ONLY_IDS:
		for layer in LAYERS:
			_validate_texture(texture_path(id, layer), assertions, Vector2(1254, 1254))
	assertions.truthy(ResourceLoader.exists(HAMMER_ICON_PATH), "construction hammer icon exists")
	if ResourceLoader.exists(HAMMER_ICON_PATH):
		var hammer_texture := load(HAMMER_ICON_PATH) as Texture2D
		assertions.truthy(hammer_texture != null, "construction hammer imports as Texture2D")
		if hammer_texture != null:
			assertions.equal(
				hammer_texture.get_size(),
				Vector2(512, 512),
				"painted hammer is 512 square"
			)
			var hammer_image := hammer_texture.get_image()
			assertions.truthy(hammer_image.detect_alpha(), "painted hammer contains alpha")
			for corner in [
				Vector2i(0, 0),
				Vector2i(511, 0),
				Vector2i(0, 511),
				Vector2i(511, 511),
			]:
				assertions.equal(
					hammer_image.get_pixelv(corner).a,
					0.0,
					"painted hammer corner is transparent"
				)
	assertions.truthy(
		ResourceLoader.exists(PROGRESS_SHADER_PATH),
		"construction progress shader exists"
	)
	if ResourceLoader.exists(PROGRESS_SHADER_PATH):
		var progress_shader := load(PROGRESS_SHADER_PATH) as Shader
		assertions.truthy(progress_shader != null, "construction progress imports as Shader")
		if progress_shader != null:
			assertions.truthy(
				progress_shader.code.contains("MODELVIEW_MATRIX"),
				"construction progress shader billboards its custom material"
			)
			assertions.truthy(
				progress_shader.code.contains("depth_test_disabled"),
				"construction progress remains readable over building art"
			)
	assertions.truthy(ResourceLoader.exists(HAMMER_SHADER_PATH), "construction hammer shader exists")
	if ResourceLoader.exists(HAMMER_SHADER_PATH):
		var hammer_shader := load(HAMMER_SHADER_PATH) as Shader
		assertions.truthy(hammer_shader != null, "construction hammer shader imports")
		if hammer_shader != null:
			assertions.truthy(
				hammer_shader.code.contains("depth_test_disabled"),
				"construction hammer remains readable over building art"
			)
			assertions.truthy(
				hammer_shader.code.contains("pivot_uv"),
				"construction hammer shader supports the painted handle endpoint"
			)
			assertions.truthy(
				hammer_shader.code.contains("VERTEX.xy += screen_offset"),
				"construction hammer applies screen offset after pivot rotation"
			)


func _validate_texture(
	path: String,
	assertions: TestAssert,
	expected_size := Vector2(1024, 1024)
) -> void:
	assertions.truthy(ResourceLoader.exists(path), "%s exists" % path)
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	assertions.truthy(texture != null, "%s imports as Texture2D" % path)
	if texture == null:
		return
	assertions.equal(texture.get_size(), expected_size, "%s has the authored square dimensions" % path)
	var image := texture.get_image()
	assertions.truthy(image.detect_alpha(), "%s contains alpha" % path)
	assertions.truthy(image.get_used_rect().has_area(), "%s contains visible painted pixels" % path)
	assertions.equal(image.get_pixel(0, 0).a, 0.0, "%s has a transparent corner" % path)
