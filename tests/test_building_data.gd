extends RefCounted

const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const IDS := [
	"barn",
	"greenhouse",
	"waterwheel",
	"windmill",
	"chicken_coop",
	"beehive",
	"well",
	"workbench",
	"stone_kiln",
	"furnace",
	"food_workshop",
	"textile_machine",
	"lumberyard",
	"quarry",
	"mine",
	"lamp",
	"fence",
]
const PAINTED_PRODUCTION_IDS := [
	"stone_kiln",
	"furnace",
	"food_workshop",
	"textile_machine",
	"lumberyard",
	"quarry",
	"mine",
]


func run(assertions: TestAssert) -> void:
	var game_data = GameDataScript.new()
	for id in IDS:
		var source: Dictionary = game_data.get_building(id)
		var data = BuildingDataScript.from_dictionary(source)
		assertions.truthy(data.is_valid(), "%s converts to valid BuildingData" % id)
		assertions.equal(data.building_id, id, "%s preserves id" % id)
		assertions.equal(data.effect_type, str(source.get("effect", "")), "%s exposes effect type" % id)
		assertions.equal(data.effect, data.effect_type, "%s keeps effect compatibility alias" % id)
		assertions.equal(data.visual_width, data.visual_size.x, "%s exposes visual width" % id)
		assertions.equal(data.visual_height, data.visual_size.y, "%s exposes visual height" % id)
		assertions.equal(data.display_name, source.name, "%s preserves name" % id)
		assertions.equal(data.category, str(source.get("category", "basic")), "%s preserves category" % id)
		assertions.equal(data.palette_order, int(source.get("palette_order", 0)), "%s preserves palette order" % id)
		assertions.equal(data.cost, source.cost, "%s preserves cost" % id)
		assertions.equal(data.footprint, Vector2i(source.footprint_x, source.footprint_z), "%s preserves footprint" % id)
		assertions.equal(data.effect, source.effect, "%s preserves effect" % id)
		assertions.equal(data.effect_value, source.effect_value, "%s preserves effect value" % id)
		assertions.truthy(ResourceLoader.exists(data.scene_path), "%s scene exists" % id)
		assertions.truthy(data.visual_size.x > 0.0 and data.visual_size.y > 0.0, "%s has positive visual size" % id)

	var barn = BuildingDataScript.from_dictionary(game_data.get_building("barn"))
	assertions.equal(barn.footprint, Vector2i(2, 2), "barn footprint is 2x2")
	assertions.equal(barn.ground_anchor_uv, Vector2(0.5, 1.0), "existing art keeps bottom-edge anchor")
	for id in PAINTED_PRODUCTION_IDS:
		var production_data = BuildingDataScript.from_dictionary(game_data.get_building(id))
		assertions.equal(
			production_data.ground_anchor_uv,
			Vector2(0.5, 0.9375),
			"%s uses the shared ground anchor" % id
		)
		assertions.truthy(
			production_data.activity_fps >= 3.0 and production_data.activity_fps <= 6.0,
			"%s has restrained activity timing" % id
		)
	barn.cost.wood = 1
	assertions.equal(game_data.get_building("barn").cost.plank, 8, "cost is deep copied")

	var empty = BuildingDataScript.from_dictionary({})
	assertions.equal(empty.is_valid(), false, "empty dictionary is invalid")
	game_data.free()
