extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")

const REQUIRED_MARKET_IDS := [
	"wood", "clay", "sand", "coal", "copper_ore", "iron_ore",
	"iron_ingot", "glass", "honey", "egg", "flour", "fruit_jam",
]

const NEW_CATALOG_IDS := [
	"clay", "sand", "coal", "copper_ore", "iron_ore", "silver_ore", "gold_ore", "crystal",
	"plank", "charcoal", "stone_brick", "brick", "rope", "cloth", "copper_ingot", "iron_ingot", "steel",
	"honey", "beeswax", "egg", "feather",
	"glass_jar", "glass_bottle", "salt",
	"flour", "animal_feed", "sunflower_oil", "fruit_jam", "pickles", "tomato_sauce", "fruit_juice", "bread", "honey_cake",
]

const WOOD_METADATA := {
	"id": "wood",
	"name": "木材",
	"category": "material",
	"sell_price": 1,
	"buy_price": 2,
	"base_price": 3,
	"target_stock": 80,
	"initial_stock": 60,
	"daily_liquidity": 30,
	"volatility": "essential",
	"max_stack": 99,
}


func run(assertions: TestAssert) -> void:
	_assert_catalog_invariants(assertions)
	for item_id in REQUIRED_MARKET_IDS:
		_assert_market_metadata(assertions, item_id)
	for item_id in NEW_CATALOG_IDS:
		_assert_market_metadata(assertions, item_id)

	assertions.equal(GameDataScript.get_item("wood"), WOOD_METADATA, "wood metadata is exact")
	var legacy_iron: Dictionary = GameDataScript.get_item("iron")
	assertions.equal(legacy_iron.get("migrate_to"), "iron_ingot", "legacy iron migrates")
	assertions.equal(legacy_iron.get("category"), "legacy", "legacy iron is excluded from trading")
	assertions.truthy(legacy_iron.get("base_price", 0) <= 0, "legacy iron has no market price")

	var market_items: Array[Dictionary] = GameDataScript.get_market_items()
	for item in market_items:
		assertions.truthy(item.get("base_price", 0) > 0, item.get("id", "unknown") + " has a market price")
		assertions.truthy(item.get("target_stock", 0) > 0, item.get("id", "unknown") + " has a stock target")
		assertions.truthy(item.get("initial_stock", 0) > 0, item.get("id", "unknown") + " has initial stock")
		assertions.truthy(item.get("daily_liquidity", 0) > 0, item.get("id", "unknown") + " has liquidity")
		assertions.truthy(not item.get("volatility", "").is_empty(), item.get("id", "unknown") + " has volatility")
		assertions.truthy(item.get("category", "") != "legacy", item.get("id", "unknown") + " is not legacy")
	for item_id in REQUIRED_MARKET_IDS:
		assertions.truthy(_market_contains(market_items, item_id), item_id + " appears in market items")
	assertions.truthy(not _market_contains(market_items, "iron"), "legacy iron is not a market item")
	_test_market_items_are_snapshots(assertions)


func _assert_catalog_invariants(assertions: TestAssert) -> void:
	for item_key in GameDataScript.ITEMS:
		var item: Dictionary = GameDataScript.ITEMS[item_key]
		assertions.equal(item_key, item.get("id", ""), item_key + " key matches item id")
		assertions.truthy(not item.get("id", "").is_empty(), item_key + " has an id")
		assertions.truthy(not item.get("name", "").is_empty(), item_key + " has a name")
		assertions.truthy(not item.get("category", "").is_empty(), item_key + " has a category")
		assertions.truthy(typeof(item.get("max_stack")) == TYPE_INT and item.get("max_stack", 0) > 0, item_key + " has a positive integer stack limit")
		if item.get("category") != "legacy":
			assertions.truthy(typeof(item.get("base_price")) == TYPE_INT and item.get("base_price", 0) > 0, item_key + " has a positive integer base price")
			assertions.truthy(typeof(item.get("target_stock")) == TYPE_INT and item.get("target_stock", 0) > 0, item_key + " has a positive integer stock target")
			assertions.truthy(typeof(item.get("initial_stock")) == TYPE_INT and item.get("initial_stock", 0) > 0, item_key + " has positive integer initial stock")
			assertions.truthy(typeof(item.get("daily_liquidity")) == TYPE_INT and item.get("daily_liquidity", 0) > 0, item_key + " has positive integer liquidity")
			assertions.truthy(item.get("volatility", "") is String and not item.get("volatility", "").is_empty(), item_key + " has string volatility")


func _test_market_items_are_snapshots(assertions: TestAssert) -> void:
	var first_market_items: Array[Dictionary] = GameDataScript.get_market_items()
	var returned_wood := _find_market_item(first_market_items, "wood")
	assertions.truthy(not returned_wood.is_read_only(), "market items are mutable snapshots")
	if returned_wood.is_read_only():
		return
	returned_wood["name"] = "mutated market wood"
	assertions.equal(GameDataScript.ITEMS["wood"].get("name"), "木材", "market mutation leaves catalog unchanged")
	var subsequent_market_items: Array[Dictionary] = GameDataScript.get_market_items()
	assertions.equal(_find_market_item(subsequent_market_items, "wood").get("name"), "木材", "market mutation leaves later snapshot unchanged")


func _assert_market_metadata(assertions: TestAssert, item_id: String) -> void:
	var item: Dictionary = GameDataScript.get_item(item_id)
	assertions.truthy(not item.is_empty(), item_id + " registered")
	assertions.truthy(item.get("base_price", 0) > 0, item_id + " priced")
	assertions.truthy(item.get("target_stock", 0) > 0, item_id + " stock target")
	assertions.truthy(item.get("initial_stock", 0) > 0, item_id + " initial stock")
	assertions.truthy(item.get("daily_liquidity", 0) > 0, item_id + " liquidity")
	assertions.truthy(not item.get("volatility", "").is_empty(), item_id + " volatility")


func _market_contains(items: Array[Dictionary], item_id: String) -> bool:
	return not _find_market_item(items, item_id).is_empty()


func _find_market_item(items: Array[Dictionary], item_id: String) -> Dictionary:
	for item in items:
		if item.get("id", "") == item_id:
			return item
	return {}
