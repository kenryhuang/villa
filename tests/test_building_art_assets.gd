extends RefCounted

const BuildingOutputPileScript := preload(
	"res://scripts/buildings/building_output_pile.gd"
)
const RecipeDatabaseScript := preload("res://scripts/core/recipe_database.gd")

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
	"stone_kiln",
	"furnace",
	"food_workshop",
	"textile_machine",
	"lumberyard",
	"quarry",
	"mine",
]
const PAINTED_ONLY_IDS := ["waterwheel"]
const PAINTED_PRODUCTION_IDS := [
	"stone_kiln",
	"furnace",
	"food_workshop",
	"textile_machine",
	"lumberyard",
	"quarry",
	"mine",
]
const LAYERS := ["back", "front"]
const CONSTRUCTION_STAGES := ["foundation", "frame", "half_built"]
const HAMMER_ICON_PATH := "res://assets/buildings/construction/construction_hammer_painted.png"
const HAMMER_SHADER_PATH := "res://assets/buildings/construction/construction_hammer.gdshader"
const PROGRESS_SHADER_PATH := "res://assets/buildings/construction/construction_progress.gdshader"
const OUTPUT_PILE_FAMILIES := [
	"wood",
	"stone",
	"ore",
	"metal",
	"sack",
	"bottle",
	"textile",
	"food",
	"crate",
	"small",
	"brick",
	"charcoal",
]
const PASSIVE_OUTPUT_IDS := [
	"wood",
	"stone",
	"coal",
	"copper_ore",
	"iron_ore",
	"silver_ore",
	"gold_ore",
	"crystal",
	"honey",
	"beeswax",
	"egg",
	"feather",
]


static func texture_path(id: String, layer: String) -> String:
	return "res://assets/buildings/painted/%s/%s_%s.png" % [id, id, layer]


static func construction_texture_path(id: String, stage: String) -> String:
	return "res://assets/buildings/construction/%s/%s_%s.png" % [id, id, stage]


static func activity_texture_path(id: String) -> String:
	return "res://assets/buildings/painted/%s/%s_activity.png" % [id, id]


func run(assertions: TestAssert) -> void:
	for id in IDS:
		for layer in LAYERS:
			_validate_texture(texture_path(id, layer), assertions)
		for stage in CONSTRUCTION_STAGES:
			_validate_texture(construction_texture_path(id, stage), assertions)
	for id in PAINTED_ONLY_IDS:
		for layer in LAYERS:
			_validate_texture(texture_path(id, layer), assertions, Vector2(1254, 1254))
	for id in PAINTED_PRODUCTION_IDS:
		_validate_layer_pair_ground_anchor(id, assertions)
		for stage in CONSTRUCTION_STAGES:
			_validate_ground_anchor(construction_texture_path(id, stage), assertions)
		_validate_activity_atlas(activity_texture_path(id), assertions)
	for family in OUTPUT_PILE_FAMILIES:
		_validate_output_pile_atlas(family, assertions)
	for recipe in RecipeDatabaseScript.get_all_recipes():
		for output_id_value in (recipe.outputs as Dictionary).keys():
			var output_id := str(output_id_value)
			assertions.truthy(
				BuildingOutputPileScript.FAMILY_BY_ITEM.has(output_id),
				"recipe output %s has an explicit pile family" % output_id
			)
	for output_id in PASSIVE_OUTPUT_IDS:
		assertions.truthy(
			BuildingOutputPileScript.FAMILY_BY_ITEM.has(output_id),
			"passive output %s has an explicit pile family" % output_id
		)
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


func _validate_ground_anchor(path: String, assertions: TestAssert) -> void:
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	if texture == null:
		return
	var image := texture.get_image()
	var touches_anchor := false
	for y in range(944, 977):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.05:
				touches_anchor = true
				break
		if touches_anchor:
			break
	assertions.truthy(touches_anchor, "%s touches the shared ground-anchor band" % path)


func _validate_layer_pair_ground_anchor(id: String, assertions: TestAssert) -> void:
	var touches_anchor := false
	for layer in LAYERS:
		var path := texture_path(id, layer)
		if not ResourceLoader.exists(path):
			continue
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		var image := texture.get_image()
		for y in range(944, 977):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.05:
					touches_anchor = true
					break
			if touches_anchor:
				break
		if touches_anchor:
			break
	assertions.truthy(
		touches_anchor,
		"%s painted layer pair touches the shared ground-anchor band" % id
	)


func _validate_activity_atlas(path: String, assertions: TestAssert) -> void:
	_validate_texture(path, assertions, Vector2(2048, 512))
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	if texture == null or texture.get_size() != Vector2(2048, 512):
		return
	var image := texture.get_image()
	for frame in range(4):
		var visible_pixels := 0
		for y in range(512):
			for x in range(frame * 512, (frame + 1) * 512):
				if image.get_pixel(x, y).a > 0.05:
					visible_pixels += 1
		assertions.truthy(visible_pixels > 0, "%s frame %d contains activity art" % [path, frame])
		assertions.truthy(
			visible_pixels < int(512 * 512 * 0.35),
			"%s frame %d only redraws moving parts" % [path, frame]
		)


func _validate_output_pile_atlas(family: String, assertions: TestAssert) -> void:
	var path := "res://assets/items/output_piles/%s.svg" % family
	assertions.truthy(ResourceLoader.exists(path), "%s pile atlas exists" % family)
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	assertions.truthy(texture != null, "%s pile atlas imports" % family)
	if texture == null:
		return
	assertions.equal(texture.get_size(), Vector2(576, 192), "%s pile atlas has three frames" % family)
	var image := texture.get_image()
	assertions.truthy(image.detect_alpha(), "%s pile atlas contains alpha" % family)
	assertions.equal(image.get_pixel(0, 0).a, 0.0, "%s pile atlas has a transparent corner" % family)
	for frame in range(3):
		var frame_rect := Rect2i(frame * 192, 0, 192, 192)
		assertions.truthy(
			image.get_region(frame_rect).get_used_rect().has_area(),
			"%s pile density frame %d contains art" % [family, frame]
		)
		if family in ["brick", "charcoal"]:
			var right_gutter_clear := true
			for y in range(192):
				for x in range(frame * 192 + 189, frame * 192 + 192):
					if image.get_pixel(x, y).a > 0.01:
						right_gutter_clear = false
			assertions.truthy(
				right_gutter_clear,
				"%s pile density frame %d keeps a transparent right gutter" % [family, frame]
			)
