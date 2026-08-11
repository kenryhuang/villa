extends RefCounted

const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")

const REQUIRED_RECIPE_IDS := [
	"plank", "rope", "charcoal", "stone_brick", "brick",
	"glass", "copper_ingot", "iron_ingot", "steel", "cloth",
	"glass_jar", "glass_bottle",
	"flour", "animal_feed", "sunflower_oil", "fruit_jam", "pickles",
	"tomato_sauce", "fruit_juice", "bread", "honey_cake",
	"wooden_crate", "furniture", "farm_tools", "machine_parts", "lamp",
	"sachet", "candle", "perfume", "bouquet", "jewelry",
]
const MATERIAL_RECIPE_IDS := [
	"plank", "rope", "charcoal", "stone_brick", "brick",
	"glass", "copper_ingot", "iron_ingot", "steel", "cloth",
	"glass_jar", "glass_bottle",
]
const FOOD_RECIPE_IDS := [
	"flour", "animal_feed", "sunflower_oil", "fruit_jam", "pickles",
	"tomato_sauce", "fruit_juice", "bread", "honey_cake",
]
const DURABLE_RECIPE_IDS := [
	"wooden_crate", "furniture", "farm_tools", "machine_parts", "lamp",
	"sachet", "candle", "perfume", "bouquet", "jewelry",
]
const MATERIAL_DURATION_MINUTES := 18
const FOOD_DURATION_MINUTES := 27
const DURABLE_DURATION_MINUTES := 36
const GAME_MINUTES_PER_REAL_SECOND := 3.6


func run(assertions: TestAssert) -> void:
	assertions.equal(
		RecipeDatabaseScript.get_recipe("plank").inputs,
		{"wood": 2},
		"plank inputs"
	)
	assertions.equal(
		RecipeDatabaseScript.get_recipe("iron_ingot").inputs,
		{"iron_ore": 2, "coal": 1},
		"smelting inputs"
	)
	assertions.equal(
		RecipeDatabaseScript.get_recipe("fruit_jam").station,
		"food_workshop",
		"jam station"
	)
	assertions.equal(
		RecipeDatabaseScript.get_recipe("bread").station,
		"food_workshop",
		"bread has a real station"
	)
	assertions.equal(
		RecipeDatabaseScript.get_recipe("honey_cake").station,
		"food_workshop",
		"cake has a real station"
	)
	assertions.equal(
		RecipeDatabaseScript.get_recipe("glass_jar").outputs,
		{"glass_jar": 2},
		"jar recipe exists"
	)
	assertions.equal(
		RecipeDatabaseScript.get_recipe("glass_bottle").outputs,
		{"glass_bottle": 2},
		"bottle recipe exists"
	)
	assertions.equal(RecipeDatabaseScript.get_recipe("missing"), {}, "unknown recipe is empty")

	var all_recipes := RecipeDatabaseScript.get_all_recipes()
	for recipe_id in REQUIRED_RECIPE_IDS:
		var recipe: Dictionary = RecipeDatabaseScript.get_recipe(recipe_id)
		assertions.truthy(not recipe.is_empty(), "%s recipe registered" % recipe_id)
		for field in [
			"id", "display_name", "station", "inputs", "outputs",
			"duration_minutes", "unlock_tier",
		]:
			assertions.truthy(recipe.has(field), "%s has %s" % [recipe_id, field])
		assertions.equal(recipe.id, recipe_id, "%s has matching id" % recipe_id)
		assertions.truthy(recipe.inputs is Dictionary and not recipe.inputs.is_empty(), "%s has inputs" % recipe_id)
		assertions.truthy(recipe.outputs is Dictionary and not recipe.outputs.is_empty(), "%s has outputs" % recipe_id)
		assertions.truthy(int(recipe.unlock_tier) >= 0, "%s has nonnegative tier" % recipe_id)
		assertions.truthy(
			not GameDataScript.get_building(str(recipe.station)).is_empty(),
			"%s station exists" % recipe_id
		)
		for item_id in recipe.inputs:
			assertions.truthy(GameDataScript.get_item(str(item_id)) != null, "%s input %s is an inventory item" % [recipe_id, item_id])
		for item_id in recipe.outputs:
			assertions.truthy(GameDataScript.get_item(str(item_id)) != null, "%s output %s is collectible" % [recipe_id, item_id])
	assertions.truthy(all_recipes.size() >= REQUIRED_RECIPE_IDS.size(), "all approved recipes are returned")

	for recipe_id in MATERIAL_RECIPE_IDS:
		var duration := int(RecipeDatabaseScript.get_recipe(recipe_id).duration_minutes)
		assertions.equal(duration, MATERIAL_DURATION_MINUTES, "%s material duration" % recipe_id)
		assertions.near(float(duration) / GAME_MINUTES_PER_REAL_SECOND, 5.0, 0.01, "%s material real seconds" % recipe_id)
	for recipe_id in FOOD_RECIPE_IDS:
		var duration := int(RecipeDatabaseScript.get_recipe(recipe_id).duration_minutes)
		assertions.equal(duration, FOOD_DURATION_MINUTES, "%s food duration" % recipe_id)
		assertions.near(float(duration) / GAME_MINUTES_PER_REAL_SECOND, 7.5, 0.01, "%s food real seconds" % recipe_id)
	for recipe_id in DURABLE_RECIPE_IDS:
		var duration := int(RecipeDatabaseScript.get_recipe(recipe_id).duration_minutes)
		assertions.equal(duration, DURABLE_DURATION_MINUTES, "%s durable duration" % recipe_id)
		assertions.near(float(duration) / GAME_MINUTES_PER_REAL_SECOND, 10.0, 0.01, "%s durable real seconds" % recipe_id)

	var mutated := RecipeDatabaseScript.get_recipe("plank")
	mutated.inputs.wood = 999
	assertions.equal(
		RecipeDatabaseScript.get_recipe("plank").inputs.wood,
		2,
		"recipe reads are immutable deep copies"
	)
