extends RefCounted

const BuildingCatalogScript = preload("res://scripts/core/building_catalog.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")

const EXPECTED_CATEGORIES: Array[String] = [
	"basic", "production", "farming", "resource", "decoration",
]
const EXPECTED_IDS: Array[String] = [
	"workbench", "stone_kiln", "barn", "well",
	"windmill", "furnace", "food_workshop", "textile_machine",
	"chicken_coop", "beehive", "greenhouse", "waterwheel",
	"lumberyard", "quarry", "mine", "lamp", "fence",
]
const EXPECTED_COSTS := {
	"workbench": {"wood": 20, "stone": 10},
	"stone_kiln": {"wood": 20, "stone": 30},
	"barn": {"plank": 8, "stone_brick": 6, "wooden_crate": 1},
	"well": {"wood": 10, "stone": 20},
	"windmill": {"plank": 12, "stone_brick": 8, "rope": 2},
	"furnace": {"stone_brick": 10, "brick": 6, "charcoal": 4},
	"food_workshop": {"plank": 12, "stone_brick": 8, "glass": 5, "iron_ingot": 2},
	"textile_machine": {"plank": 10, "iron_ingot": 4, "machine_parts": 1},
	"chicken_coop": {"plank": 8, "stone_brick": 4, "rope": 1},
	"beehive": {"wood": 15},
	"greenhouse": {"plank": 15, "stone_brick": 10, "glass": 12, "iron_ingot": 3},
	"waterwheel": {"plank": 12, "stone_brick": 8, "iron_ingot": 3, "rope": 2},
	"lumberyard": {"plank": 10, "stone_brick": 6, "rope": 2},
	"quarry": {"plank": 8, "stone_brick": 10, "farm_tools": 1},
	"mine": {"plank": 20, "stone_brick": 15, "steel": 3, "machine_parts": 2},
	"lamp": {"lamp": 1, "plank": 1},
	"fence": {"wood": 2},
}


func run(assertions: TestAssert) -> void:
	assertions.equal(
		BuildingCatalogScript.categories(),
		EXPECTED_CATEGORIES,
		"catalog exposes stable categories"
	)
	var ids := BuildingCatalogScript.all_building_ids()
	assertions.equal(ids.size(), 17, "catalog exposes all buildings")
	assertions.equal(ids, EXPECTED_IDS, "catalog order is stable")
	var seen := {}
	for building_id in ids:
		assertions.truthy(not seen.has(building_id), "%s appears once" % building_id)
		seen[building_id] = true
		var source: Dictionary = GameDataScript.get_building(building_id)
		assertions.equal(source.get("cost", {}), EXPECTED_COSTS[building_id], "%s uses target cost" % building_id)
		assertions.truthy(source.has("category"), "%s has category" % building_id)
		assertions.truthy(source.has("palette_order"), "%s has palette order" % building_id)
		for item_id in source.get("cost", {}):
			assertions.truthy(
				GameDataScript.get_item(str(item_id)) != null,
				"%s cost item exists" % item_id
			)
			assertions.truthy(
				int(source.cost[item_id]) > 0,
				"%s cost is positive" % item_id
			)
			assertions.truthy(
				str(item_id) != "iron",
				"%s does not use legacy iron" % building_id
			)

	for category_id in EXPECTED_CATEGORIES:
		assertions.truthy(
			BuildingCatalogScript.building_ids_for_category(category_id).size() > 0,
			"%s category is populated" % category_id
		)

	var available := {
		"wood": true, "fiber": true, "stone": true, "clay": true,
		"sand": true, "coal": true, "copper_ore": true, "iron_ore": true,
		"silver_ore": true, "gold_ore": true, "crystal": true,
		"grain": true, "sunflower": true, "strawberry": true,
		"honey": true, "beeswax": true, "egg": true, "salt": true,
		"carrot": true, "tomato": true, "lavender": true, "rose": true,
	}
	var changed := true
	while changed:
		changed = false
		for recipe in RecipeDatabaseScript.get_all_recipes():
			var inputs_ready := true
			for item_id in recipe.inputs:
				if not available.has(str(item_id)):
					inputs_ready = false
					break
			if not inputs_ready:
				continue
			for item_id in recipe.outputs:
				if not available.has(str(item_id)):
					available[str(item_id)] = true
					changed = true
	for recipe in RecipeDatabaseScript.get_all_recipes():
		for item_id in recipe.outputs:
			assertions.truthy(
				available.has(str(item_id)),
				"%s output is reachable" % item_id
			)
