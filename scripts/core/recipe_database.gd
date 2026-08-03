class_name RecipeDatabase
extends RefCounted

static var _recipes: Dictionary = {
	"plank": _recipe("plank", "木板", "workbench", {"wood": 2}, {"plank": 1}, 120, 0),
	"rope": _recipe("rope", "绳索", "workbench", {"fiber": 3}, {"rope": 1}, 120, 0),
	"charcoal": _recipe("charcoal", "木炭", "stone_kiln", {"wood": 3}, {"charcoal": 1}, 180, 0),
	"stone_brick": _recipe("stone_brick", "石砖", "stone_kiln", {"stone": 2}, {"stone_brick": 1}, 180, 0),
	"brick": _recipe("brick", "砖块", "stone_kiln", {"clay": 2, "coal": 1}, {"brick": 2}, 240, 0),
	"glass": _recipe("glass", "玻璃", "furnace", {"sand": 2, "coal": 1}, {"glass": 1}, 240, 1),
	"copper_ingot": _recipe("copper_ingot", "铜锭", "furnace", {"copper_ore": 2, "coal": 1}, {"copper_ingot": 1}, 240, 1),
	"iron_ingot": _recipe("iron_ingot", "铁锭", "furnace", {"iron_ore": 2, "coal": 1}, {"iron_ingot": 1}, 300, 1),
	"steel": _recipe("steel", "钢材", "furnace", {"iron_ingot": 2, "coal": 2}, {"steel": 1}, 360, 2),
	"cloth": _recipe("cloth", "布料", "textile_machine", {"fiber": 4}, {"cloth": 1}, 240, 2),
	"flour": _recipe("flour", "面粉", "windmill", {"grain": 2}, {"flour": 1}, 360, 1),
	"animal_feed": _recipe("animal_feed", "动物饲料", "windmill", {"grain": 1}, {"animal_feed": 2}, 360, 1),
	"sunflower_oil": _recipe("sunflower_oil", "葵花油", "windmill", {"sunflower": 3}, {"sunflower_oil": 1}, 480, 1),
	"fruit_jam": _recipe("fruit_jam", "水果果酱", "food_workshop", {"strawberry": 2, "honey": 1, "glass_jar": 1}, {"fruit_jam": 1}, 480, 1),
	"pickles": _recipe("pickles", "腌菜", "food_workshop", {"carrot": 3, "salt": 1, "glass_jar": 1}, {"pickles": 1}, 480, 1),
	"tomato_sauce": _recipe("tomato_sauce", "番茄酱", "food_workshop", {"tomato": 3, "glass_jar": 1}, {"tomato_sauce": 1}, 480, 1),
	"fruit_juice": _recipe("fruit_juice", "果汁", "food_workshop", {"strawberry": 3, "glass_bottle": 1}, {"fruit_juice": 1}, 420, 1),
	"bread": _recipe("bread", "面包", "kitchen", {"flour": 2, "egg": 1}, {"bread": 2}, 360, 1),
	"honey_cake": _recipe("honey_cake", "蜂蜜蛋糕", "kitchen", {"flour": 2, "egg": 1, "honey": 1}, {"honey_cake": 1}, 720, 2),
	"wooden_crate": _recipe("wooden_crate", "木箱", "workbench", {"plank": 2, "rope": 1}, {"wooden_crate": 1}, 1080, 1),
	"furniture": _recipe("furniture", "家具", "workbench", {"plank": 4, "cloth": 2}, {"furniture": 1}, 2160, 2),
	"farm_tools": _recipe("farm_tools", "农具", "workbench", {"iron_ingot": 2, "plank": 1}, {"farm_tools": 1}, 1440, 1),
	"machine_parts": _recipe("machine_parts", "机械零件", "workbench", {"steel": 1, "copper_ingot": 1}, {"machine_parts": 1}, 1800, 2),
	"lamp": _recipe("lamp", "灯具", "workbench", {"copper_ingot": 1, "glass": 1}, {"lamp": 1}, 1440, 1),
	"sachet": _recipe("sachet", "香包", "textile_machine", {"lavender": 2, "cloth": 1}, {"sachet": 1}, 1080, 2),
	"candle": _recipe("candle", "蜡烛", "workbench", {"beeswax": 2, "fiber": 1}, {"candle": 1}, 1080, 1),
	"perfume": _recipe("perfume", "香水", "food_workshop", {"rose": 2, "glass_bottle": 1}, {"perfume": 1}, 1800, 3),
	"bouquet": _recipe("bouquet", "花束", "food_workshop", {"rose": 3, "fiber": 1}, {"bouquet": 1}, 1080, 1),
	"jewelry": _recipe("jewelry", "珠宝", "workbench", {"gold_ore": 2, "crystal": 1}, {"jewelry": 1}, 2160, 3),
}


static func _recipe(
	id: String,
	display_name: String,
	station: String,
	inputs: Dictionary,
	outputs: Dictionary,
	duration_minutes: int,
	unlock_tier: int
) -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"station": station,
		"inputs": inputs,
		"outputs": outputs,
		"duration_minutes": duration_minutes,
		"unlock_tier": unlock_tier,
	}


static func get_recipe(recipe_id: String) -> Dictionary:
	var recipe: Variant = _recipes.get(recipe_id)
	if not recipe is Dictionary:
		return {}
	return (recipe as Dictionary).duplicate(true)


static func get_all_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in _recipes.values():
		result.append((recipe as Dictionary).duplicate(true))
	return result


static func get_recipes_for_station(station_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in _recipes.values():
		if str((recipe as Dictionary).get("station", "")) == station_id:
			result.append((recipe as Dictionary).duplicate(true))
	return result


static func has_station(station_id: String) -> bool:
	if station_id.is_empty():
		return false
	for recipe in _recipes.values():
		if str((recipe as Dictionary).get("station", "")) == station_id:
			return true
	return false
