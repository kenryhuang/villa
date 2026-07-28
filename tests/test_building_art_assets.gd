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


static func texture_path(id: String, layer: String) -> String:
	return "res://assets/buildings/painted/%s/%s_%s.png" % [id, id, layer]


func run(assertions: TestAssert) -> void:
	for id in IDS:
		for layer in LAYERS:
			var path := texture_path(id, layer)
			assertions.truthy(ResourceLoader.exists(path), "%s exists" % path)
			if not ResourceLoader.exists(path):
				continue
			var texture := load(path) as Texture2D
			assertions.truthy(texture != null, "%s imports as Texture2D" % path)
			if texture == null:
				continue
			assertions.equal(texture.get_size(), Vector2(1024, 1024), "%s is 1024 square" % path)
			var image := texture.get_image()
			assertions.truthy(image.detect_alpha(), "%s contains alpha" % path)
			assertions.equal(image.get_pixel(0, 0).a, 0.0, "%s has a transparent corner" % path)

