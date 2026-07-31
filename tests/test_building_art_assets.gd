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
const LAYERS := ["back", "front"]
const CONSTRUCTION_STAGES := ["foundation", "frame", "half_built"]
const HAMMER_ICON_PATH := "res://assets/buildings/construction/construction_hammer.svg"


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
	assertions.truthy(ResourceLoader.exists(HAMMER_ICON_PATH), "construction hammer icon exists")
	if ResourceLoader.exists(HAMMER_ICON_PATH):
		var hammer_texture := load(HAMMER_ICON_PATH) as Texture2D
		assertions.truthy(hammer_texture != null, "construction hammer imports as Texture2D")


func _validate_texture(path: String, assertions: TestAssert) -> void:
	assertions.truthy(ResourceLoader.exists(path), "%s exists" % path)
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	assertions.truthy(texture != null, "%s imports as Texture2D" % path)
	if texture == null:
		return
	assertions.equal(texture.get_size(), Vector2(1024, 1024), "%s is 1024 square" % path)
	var image := texture.get_image()
	assertions.truthy(image.detect_alpha(), "%s contains alpha" % path)
	assertions.equal(image.get_pixel(0, 0).a, 0.0, "%s has a transparent corner" % path)
