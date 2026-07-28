extends RefCounted

const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
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


func run(assertions: TestAssert) -> void:
	var game_data = GameDataScript.new()
	for id in IDS:
		var source: Dictionary = game_data.get_building(id)
		var data = BuildingDataScript.from_dictionary(source)
		assertions.truthy(data.is_valid(), "%s converts to valid BuildingData" % id)
		assertions.equal(data.building_id, id, "%s preserves id" % id)
		assertions.equal(data.display_name, source.name, "%s preserves name" % id)
		assertions.equal(data.cost, source.cost, "%s preserves cost" % id)
		assertions.equal(data.footprint, Vector2i(source.footprint_x, source.footprint_z), "%s preserves footprint" % id)
		assertions.equal(data.effect, source.effect, "%s preserves effect" % id)
		assertions.equal(data.effect_value, source.effect_value, "%s preserves effect value" % id)
		assertions.truthy(ResourceLoader.exists(data.scene_path), "%s scene exists" % id)
		assertions.truthy(data.visual_size.x > 0.0 and data.visual_size.y > 0.0, "%s has positive visual size" % id)

	var barn = BuildingDataScript.from_dictionary(game_data.get_building("barn"))
	assertions.equal(barn.footprint, Vector2i(2, 2), "barn footprint is 2x2")
	barn.cost.wood = 1
	assertions.equal(game_data.get_building("barn").cost.wood, 100, "cost is deep copied")

	var empty = BuildingDataScript.from_dictionary({})
	assertions.equal(empty.is_valid(), false, "empty dictionary is invalid")
	game_data.free()
