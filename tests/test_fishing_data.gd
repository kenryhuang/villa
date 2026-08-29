extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")

const FISH_IDS := [
	"creek_crucian",
	"river_perch",
	"carp",
	"rainbow_trout",
	"night_catfish",
]


func run(assertions: TestAssert) -> void:
	_test_items_and_tags(assertions)
	_test_catch_table(assertions)
	_test_recipes(assertions)


func _test_items_and_tags(assertions: TestAssert) -> void:
	for item_id in FISH_IDS:
		var item: Dictionary = GameDataScript.get_item(item_id)
		assertions.truthy(not item.is_empty(), "%s is registered" % item_id)
		assertions.equal(item.get("category"), "fish", "%s uses fish category" % item_id)
		assertions.truthy(item.get("tags", []) is Array, "%s has declarative tags" % item_id)
		assertions.truthy(GameDataScript.item_matches_tag(item_id, "fish"), "%s matches fish tag" % item_id)
	assertions.truthy(GameDataScript.item_matches_tag("creek_crucian", "common_fish"), "creek crucian is a common recipe fish")
	assertions.truthy(GameDataScript.item_matches_tag("rainbow_trout", "rare_fish"), "rainbow trout is rare")
	assertions.truthy(not GameDataScript.item_matches_tag("rainbow_trout", "common_fish"), "rare fish cannot be consumed by common recipes")
	for item_id in ["drift_bottle", "grilled_fish", "pickled_fish"]:
		assertions.truthy(GameDataScript.get_item(item_id) != null, "%s is registered" % item_id)
	var market_ids: Array[String] = []
	for item in GameDataScript.get_market_items():
		market_ids.append(str(item.get("id", "")))
	assertions.truthy(not "drift_bottle" in market_ids, "drift bottles stay outside the ordinary market")
	for item_id in FISH_IDS + ["grilled_fish", "pickled_fish"]:
		assertions.equal(market_ids.count(item_id), 1, "%s has one market definition" % item_id)


func _test_catch_table(assertions: TestAssert) -> void:
	var table: Array = GameDataScript.FISHING_TABLES.get("creek", [])
	assertions.equal(table.size(), 6, "creek table defines five fish and one bottle")
	var table_ids: Array[String] = []
	for entry_value in table:
		var entry: Dictionary = entry_value
		table_ids.append(str(entry.get("item_id", "")))
		assertions.truthy(float(entry.get("weight", 0.0)) > 0.0, "%s has positive catch weight" % entry.get("item_id", ""))
		assertions.truthy(entry.get("seasons", []) is Array and not entry.seasons.is_empty(), "%s declares seasons" % entry.get("item_id", ""))
		assertions.truthy(entry.get("hour_ranges", []) is Array and not entry.hour_ranges.is_empty(), "%s declares hour ranges" % entry.get("item_id", ""))
		assertions.truthy(entry.get("unique", false) is bool, "%s declares uniqueness" % entry.get("item_id", ""))
	for item_id in FISH_IDS + ["drift_bottle"]:
		assertions.equal(table_ids.count(item_id), 1, "%s appears once in creek table" % item_id)


func _test_recipes(assertions: TestAssert) -> void:
	var grilled := RecipeDatabaseScript.get_recipe("grilled_fish")
	var pickled := RecipeDatabaseScript.get_recipe("pickled_fish")
	assertions.equal(grilled.get("station"), "food_workshop", "grilled fish uses food workshop")
	assertions.equal(grilled.get("inputs"), {"salt": 1}, "grilled fish keeps concrete salt input")
	assertions.equal(grilled.get("input_selectors"), [{"tag": "common_fish", "quantity": 2}], "grilled fish accepts any two common fish")
	assertions.equal(grilled.get("outputs"), {"grilled_fish": 2}, "grilled fish yields two meals")
	assertions.equal(pickled.get("station"), "food_workshop", "pickled fish uses food workshop")
	assertions.equal(pickled.get("inputs"), {"salt": 1, "glass_jar": 1}, "pickled fish keeps concrete inputs")
	assertions.equal(pickled.get("input_selectors"), [{"tag": "common_fish", "quantity": 2}], "pickled fish accepts any two common fish")
	assertions.equal(pickled.get("outputs"), {"pickled_fish": 1}, "pickled fish yields one preserved meal")
