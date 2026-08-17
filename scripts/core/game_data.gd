extends Node

## GameData - 集中管理所有游戏静态数据
## 包括：作物、物品、建筑、村民、收集品定义

const CropDataScript = preload("res://scripts/data/crop_data.gd")
const DEFAULT_MAX_STACK := 99

var _crops = {}
var _crops_by_plant_item = {}

# ============================================================
# 作物注册（保留已有功能）
# ============================================================

func register_crop(data: CropData) -> bool:
	if (
		data == null
		or not data.is_valid()
		or _crops.has(data.crop_id)
		or _crops_by_plant_item.has(data.plant_item_id)
	):
		return false
	_crops[data.crop_id] = data
	_crops_by_plant_item[data.plant_item_id] = data
	return true

func get_crop(id: String):
	return _crops.get(id, null)

func get_crop_for_plant_item(item_id: String) -> CropData:
	return _crops_by_plant_item.get(item_id, null) as CropData

func get_all_crops() -> Array:
	var result := []
	for crop in _crops.values():
		result.append(crop)
	return result

# ============================================================
# 物品定义
# ============================================================

const ITEMS := {
	# 种子
	"tomato_seed": {"id": "tomato_seed", "name": "番茄种子", "category": "seed", "sell_price": 0, "buy_price": 5, "base_price": 5, "target_stock": 50, "initial_stock": 45, "daily_liquidity": 20, "volatility": "essential", "max_stack": 99},
	"carrot_seed": {"id": "carrot_seed", "name": "胡萝卜种子", "category": "seed", "sell_price": 0, "buy_price": 4, "base_price": 4, "target_stock": 50, "initial_stock": 45, "daily_liquidity": 20, "volatility": "essential", "max_stack": 99},
	"potato_seed": {"id": "potato_seed", "name": "土豆种子", "category": "seed", "sell_price": 0, "buy_price": 3, "base_price": 3, "target_stock": 50, "initial_stock": 45, "daily_liquidity": 20, "volatility": "essential", "max_stack": 99},
	"strawberry_seed": {"id": "strawberry_seed", "name": "草莓种子", "category": "seed", "sell_price": 0, "buy_price": 10, "base_price": 10, "target_stock": 35, "initial_stock": 30, "daily_liquidity": 12, "volatility": "seasonal", "max_stack": 99},
	"blueberry_seed": {"id": "blueberry_seed", "name": "蓝莓种子", "category": "seed", "sell_price": 0, "buy_price": 12, "base_price": 12, "target_stock": 30, "initial_stock": 25, "daily_liquidity": 10, "volatility": "seasonal", "max_stack": 99},
	"watermelon_seed": {"id": "watermelon_seed", "name": "西瓜种子", "category": "seed", "sell_price": 0, "buy_price": 15, "base_price": 15, "target_stock": 25, "initial_stock": 20, "daily_liquidity": 8, "volatility": "seasonal", "max_stack": 99},
	"sunflower_seed": {"id": "sunflower_seed", "name": "向日葵种子", "category": "seed", "sell_price": 0, "buy_price": 8, "base_price": 8, "target_stock": 35, "initial_stock": 30, "daily_liquidity": 12, "volatility": "seasonal", "max_stack": 99},
	"rose_seed": {"id": "rose_seed", "name": "玫瑰种子", "category": "seed", "sell_price": 0, "buy_price": 10, "base_price": 10, "target_stock": 30, "initial_stock": 25, "daily_liquidity": 10, "volatility": "seasonal", "max_stack": 99},
	"lavender_seed": {"id": "lavender_seed", "name": "薰衣草种子", "category": "seed", "sell_price": 0, "buy_price": 8, "base_price": 8, "target_stock": 30, "initial_stock": 25, "daily_liquidity": 10, "volatility": "seasonal", "max_stack": 99},
	"pumpkin_seed": {"id": "pumpkin_seed", "name": "南瓜种子", "category": "seed", "sell_price": 0, "buy_price": 12, "base_price": 12, "target_stock": 30, "initial_stock": 25, "daily_liquidity": 10, "volatility": "seasonal", "max_stack": 99},
	"grain_seed": {"id": "grain_seed", "name": "谷物种子", "category": "seed", "sell_price": 0, "buy_price": 4, "base_price": 4, "target_stock": 60, "initial_stock": 50, "daily_liquidity": 25, "volatility": "essential", "max_stack": 99},
	"apple_sapling": {"id": "apple_sapling", "name": "苹果树苗", "category": "seed", "sell_price": 0, "buy_price": 35, "base_price": 35, "target_stock": 15, "initial_stock": 12, "daily_liquidity": 5, "volatility": "seasonal", "max_stack": 99},
	"peach_sapling": {"id": "peach_sapling", "name": "桃树苗", "category": "seed", "sell_price": 0, "buy_price": 35, "base_price": 35, "target_stock": 15, "initial_stock": 12, "daily_liquidity": 5, "volatility": "seasonal", "max_stack": 99},
	"grape_seed": {"id": "grape_seed", "name": "葡萄种苗", "category": "seed", "sell_price": 0, "buy_price": 18, "base_price": 18, "target_stock": 20, "initial_stock": 16, "daily_liquidity": 7, "volatility": "seasonal", "max_stack": 99},
	"lemon_sapling": {"id": "lemon_sapling", "name": "柠檬树苗", "category": "seed", "sell_price": 0, "buy_price": 40, "base_price": 40, "target_stock": 12, "initial_stock": 9, "daily_liquidity": 4, "volatility": "seasonal", "max_stack": 99},
	# 作物
	"tomato": {"id": "tomato", "name": "番茄", "category": "crop", "sell_price": 8, "buy_price": 0, "base_price": 9, "target_stock": 50, "initial_stock": 45, "daily_liquidity": 22, "volatility": "perishable", "max_stack": 99},
	"carrot": {"id": "carrot", "name": "胡萝卜", "category": "crop", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 55, "initial_stock": 50, "daily_liquidity": 24, "volatility": "perishable", "max_stack": 99},
	"potato": {"id": "potato", "name": "土豆", "category": "crop", "sell_price": 6, "buy_price": 0, "base_price": 7, "target_stock": 60, "initial_stock": 55, "daily_liquidity": 25, "volatility": "stable", "max_stack": 99},
	"strawberry": {"id": "strawberry", "name": "草莓", "category": "crop", "sell_price": 15, "buy_price": 0, "base_price": 18, "target_stock": 30, "initial_stock": 25, "daily_liquidity": 12, "volatility": "seasonal", "max_stack": 99},
	"blueberry": {"id": "blueberry", "name": "蓝莓", "category": "crop", "sell_price": 18, "buy_price": 0, "base_price": 21, "target_stock": 25, "initial_stock": 20, "daily_liquidity": 10, "volatility": "seasonal", "max_stack": 99},
	"watermelon": {"id": "watermelon", "name": "西瓜", "category": "crop", "sell_price": 25, "buy_price": 0, "base_price": 29, "target_stock": 20, "initial_stock": 16, "daily_liquidity": 8, "volatility": "seasonal", "max_stack": 99},
	"sunflower": {"id": "sunflower", "name": "向日葵", "category": "crop", "sell_price": 12, "buy_price": 0, "base_price": 14, "target_stock": 35, "initial_stock": 30, "daily_liquidity": 14, "volatility": "seasonal", "max_stack": 99},
	"rose": {"id": "rose", "name": "玫瑰", "category": "crop", "sell_price": 16, "buy_price": 0, "base_price": 19, "target_stock": 25, "initial_stock": 20, "daily_liquidity": 10, "volatility": "seasonal", "max_stack": 99},
	"lavender": {"id": "lavender", "name": "薰衣草", "category": "crop", "sell_price": 14, "buy_price": 0, "base_price": 17, "target_stock": 25, "initial_stock": 20, "daily_liquidity": 10, "volatility": "seasonal", "max_stack": 99},
	"pumpkin": {"id": "pumpkin", "name": "南瓜", "category": "crop", "sell_price": 20, "buy_price": 0, "base_price": 23, "target_stock": 22, "initial_stock": 18, "daily_liquidity": 8, "volatility": "seasonal", "max_stack": 99},
	"grain": {"id": "grain", "name": "谷物", "category": "crop", "sell_price": 24, "buy_price": 31, "base_price": 28, "target_stock": 70, "initial_stock": 60, "daily_liquidity": 30, "volatility": "essential", "max_stack": 99},
	"apple": {"id": "apple", "name": "苹果", "category": "crop", "sell_price": 17, "buy_price": 21, "base_price": 19, "target_stock": 30, "initial_stock": 24, "daily_liquidity": 12, "volatility": "seasonal", "max_stack": 99},
	"peach": {"id": "peach", "name": "桃子", "category": "crop", "sell_price": 18, "buy_price": 0, "base_price": 21, "target_stock": 25, "initial_stock": 20, "daily_liquidity": 10, "volatility": "seasonal", "max_stack": 99},
	"grape": {"id": "grape", "name": "葡萄", "category": "crop", "sell_price": 17, "buy_price": 0, "base_price": 20, "target_stock": 28, "initial_stock": 22, "daily_liquidity": 11, "volatility": "seasonal", "max_stack": 99},
	"lemon": {"id": "lemon", "name": "柠檬", "category": "crop", "sell_price": 20, "buy_price": 0, "base_price": 24, "target_stock": 20, "initial_stock": 14, "daily_liquidity": 8, "volatility": "seasonal", "max_stack": 99},
	# 材料
	"wood": {"id": "wood", "name": "木材", "category": "material", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 80, "initial_stock": 60, "daily_liquidity": 30, "volatility": "essential", "max_stack": 99},
	"stone": {"id": "stone", "name": "石头", "category": "material", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 80, "initial_stock": 60, "daily_liquidity": 30, "volatility": "essential", "max_stack": 99},
	"iron": {"id": "iron", "name": "铁", "category": "legacy", "sell_price": 0, "buy_price": 0, "base_price": 0, "migrate_to": "iron_ingot", "max_stack": 99},
	"fiber": {"id": "fiber", "name": "纤维", "category": "material", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 70, "initial_stock": 55, "daily_liquidity": 28, "volatility": "essential", "max_stack": 99},
	"glass": {"id": "glass", "name": "玻璃", "category": "material", "sell_price": 45, "buy_price": 57, "base_price": 51, "target_stock": 40, "initial_stock": 30, "daily_liquidity": 15, "volatility": "industrial", "max_stack": 99},
	"clay": {"id": "clay", "name": "黏土", "category": "material", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 65, "initial_stock": 50, "daily_liquidity": 24, "volatility": "essential", "max_stack": 99},
	"sand": {"id": "sand", "name": "沙子", "category": "material", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 65, "initial_stock": 50, "daily_liquidity": 24, "volatility": "essential", "max_stack": 99},
	"coal": {"id": "coal", "name": "煤", "category": "material", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 55, "initial_stock": 40, "daily_liquidity": 20, "volatility": "industrial", "max_stack": 99},
	"copper_ore": {"id": "copper_ore", "name": "铜矿", "category": "material", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 40, "initial_stock": 30, "daily_liquidity": 14, "volatility": "industrial", "max_stack": 99},
	"iron_ore": {"id": "iron_ore", "name": "铁矿", "category": "material", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 40, "initial_stock": 30, "daily_liquidity": 14, "volatility": "industrial", "max_stack": 99},
	"silver_ore": {"id": "silver_ore", "name": "银矿", "category": "rare", "sell_price": 15, "buy_price": 22, "base_price": 18, "target_stock": 16, "initial_stock": 10, "daily_liquidity": 5, "volatility": "rare", "max_stack": 99},
	"gold_ore": {"id": "gold_ore", "name": "金矿", "category": "rare", "sell_price": 44, "buy_price": 56, "base_price": 50, "target_stock": 12, "initial_stock": 8, "daily_liquidity": 4, "volatility": "rare", "max_stack": 99},
	"crystal": {"id": "crystal", "name": "水晶", "category": "rare", "sell_price": 62, "buy_price": 78, "base_price": 70, "target_stock": 10, "initial_stock": 6, "daily_liquidity": 3, "volatility": "rare", "max_stack": 99},
	# 加工材料
	"plank": {"id": "plank", "name": "木板", "category": "processed_material", "sell_price": 30, "buy_price": 38, "base_price": 34, "target_stock": 45, "initial_stock": 35, "daily_liquidity": 18, "volatility": "industrial", "max_stack": 99},
	"charcoal": {"id": "charcoal", "name": "木炭", "category": "processed_material", "sell_price": 45, "buy_price": 57, "base_price": 51, "target_stock": 40, "initial_stock": 30, "daily_liquidity": 16, "volatility": "industrial", "max_stack": 99},
	"stone_brick": {"id": "stone_brick", "name": "石砖", "category": "processed_material", "sell_price": 30, "buy_price": 38, "base_price": 34, "target_stock": 40, "initial_stock": 30, "daily_liquidity": 16, "volatility": "industrial", "max_stack": 99},
	"brick": {"id": "brick", "name": "砖块", "category": "processed_material", "sell_price": 23, "buy_price": 29, "base_price": 26, "target_stock": 35, "initial_stock": 25, "daily_liquidity": 14, "volatility": "industrial", "max_stack": 99},
	"rope": {"id": "rope", "name": "绳索", "category": "processed_material", "sell_price": 45, "buy_price": 57, "base_price": 51, "target_stock": 45, "initial_stock": 35, "daily_liquidity": 18, "volatility": "industrial", "max_stack": 99},
	"cloth": {"id": "cloth", "name": "布料", "category": "processed_material", "sell_price": 60, "buy_price": 76, "base_price": 68, "target_stock": 30, "initial_stock": 22, "daily_liquidity": 12, "volatility": "crafted", "max_stack": 99},
	"copper_ingot": {"id": "copper_ingot", "name": "铜锭", "category": "processed_material", "sell_price": 45, "buy_price": 57, "base_price": 51, "target_stock": 25, "initial_stock": 18, "daily_liquidity": 10, "volatility": "industrial", "max_stack": 99},
	"iron_ingot": {"id": "iron_ingot", "name": "铁锭", "category": "processed_material", "sell_price": 45, "buy_price": 57, "base_price": 51, "target_stock": 25, "initial_stock": 18, "daily_liquidity": 10, "volatility": "industrial", "max_stack": 99},
	"steel": {"id": "steel", "name": "钢材", "category": "processed_material", "sell_price": 137, "buy_price": 175, "base_price": 156, "target_stock": 12, "initial_stock": 8, "daily_liquidity": 4, "volatility": "crafted", "max_stack": 99},
	# 被动产出
	"honey": {"id": "honey", "name": "蜂蜜", "category": "output", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 30, "initial_stock": 22, "daily_liquidity": 12, "volatility": "seasonal", "max_stack": 99},
	"beeswax": {"id": "beeswax", "name": "蜂蜡", "category": "output", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 25, "initial_stock": 18, "daily_liquidity": 9, "volatility": "crafted", "max_stack": 99},
	"egg": {"id": "egg", "name": "鸡蛋", "category": "output", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 40, "initial_stock": 32, "daily_liquidity": 18, "volatility": "perishable", "max_stack": 99},
	"feather": {"id": "feather", "name": "羽毛", "category": "output", "sell_price": 12, "buy_price": 16, "base_price": 14, "target_stock": 35, "initial_stock": 28, "daily_liquidity": 14, "volatility": "stable", "max_stack": 99},
	# 容器与调味品
	"glass_jar": {"id": "glass_jar", "name": "玻璃罐", "category": "container", "sell_price": 12, "buy_price": 16, "base_price": 13, "target_stock": 30, "initial_stock": 22, "daily_liquidity": 11, "volatility": "industrial", "max_stack": 99},
	"glass_bottle": {"id": "glass_bottle", "name": "玻璃瓶", "category": "container", "sell_price": 13, "buy_price": 17, "base_price": 14, "target_stock": 30, "initial_stock": 22, "daily_liquidity": 11, "volatility": "industrial", "max_stack": 99},
	"salt": {"id": "salt", "name": "盐", "category": "container", "sell_price": 4, "buy_price": 7, "base_price": 5, "target_stock": 45, "initial_stock": 40, "daily_liquidity": 20, "volatility": "essential", "max_stack": 99},
	# 食品和成品
	"flour": {"id": "flour", "name": "面粉", "category": "product", "sell_price": 62, "buy_price": 78, "base_price": 70, "target_stock": 35, "initial_stock": 28, "daily_liquidity": 16, "volatility": "essential", "max_stack": 99},
	"animal_feed": {"id": "animal_feed", "name": "动物饲料", "category": "product", "sell_price": 16, "buy_price": 20, "base_price": 18, "target_stock": 40, "initial_stock": 32, "daily_liquidity": 18, "volatility": "essential", "max_stack": 99},
	"sunflower_oil": {"id": "sunflower_oil", "name": "葵花油", "category": "product", "sell_price": 55, "buy_price": 71, "base_price": 63, "target_stock": 18, "initial_stock": 12, "daily_liquidity": 7, "volatility": "seasonal", "max_stack": 99},
	"fruit_jam": {"id": "fruit_jam", "name": "水果果酱", "category": "product", "sell_price": 94, "buy_price": 120, "base_price": 107, "target_stock": 20, "initial_stock": 14, "daily_liquidity": 8, "volatility": "crafted", "max_stack": 99},
	"pickles": {"id": "pickles", "name": "腌菜", "category": "product", "sell_price": 79, "buy_price": 101, "base_price": 90, "target_stock": 22, "initial_stock": 16, "daily_liquidity": 9, "volatility": "crafted", "max_stack": 99},
	"tomato_sauce": {"id": "tomato_sauce", "name": "番茄酱", "category": "product", "sell_price": 53, "buy_price": 67, "base_price": 60, "target_stock": 20, "initial_stock": 14, "daily_liquidity": 8, "volatility": "crafted", "max_stack": 99},
	"fruit_juice": {"id": "fruit_juice", "name": "果汁", "category": "product", "sell_price": 90, "buy_price": 114, "base_price": 102, "target_stock": 18, "initial_stock": 12, "daily_liquidity": 7, "volatility": "perishable", "max_stack": 99},
	"bread": {"id": "bread", "name": "面包", "category": "product", "sell_price": 102, "buy_price": 130, "base_price": 116, "target_stock": 30, "initial_stock": 24, "daily_liquidity": 14, "volatility": "essential", "max_stack": 99},
	"honey_cake": {"id": "honey_cake", "name": "蜂蜜蛋糕", "category": "product", "sell_price": 222, "buy_price": 282, "base_price": 252, "target_stock": 14, "initial_stock": 10, "daily_liquidity": 5, "volatility": "luxury", "max_stack": 99},
	# 稀有
	"moonflower": {"id": "moonflower", "name": "月光花", "category": "rare", "sell_price": 50, "buy_price": 0, "base_price": 60, "target_stock": 8, "initial_stock": 5, "daily_liquidity": 2, "volatility": "rare", "max_stack": 1},
	"stardust_fruit": {"id": "stardust_fruit", "name": "星尘果", "category": "rare", "sell_price": 80, "buy_price": 0, "base_price": 95, "target_stock": 6, "initial_stock": 4, "daily_liquidity": 2, "volatility": "rare", "max_stack": 1},
}

# Section 7.2 craft outputs all participate in the finite market. Their base
# values follow the documented processing ladders, so every recipe can be
# evaluated by the same market and arbitrage simulation.
const INVENTORY_ONLY_ITEMS := {
	"wooden_crate": {"id": "wooden_crate", "name": "木箱", "category": "crafted_good", "sell_price": 136, "buy_price": 172, "base_price": 154, "target_stock": 16, "initial_stock": 9, "daily_liquidity": 7, "volatility": "crafted", "max_stack": 99},
	"furniture": {"id": "furniture", "name": "家具", "category": "crafted_good", "sell_price": 407, "buy_price": 517, "base_price": 462, "target_stock": 7, "initial_stock": 3, "daily_liquidity": 3, "volatility": "crafted", "max_stack": 99},
	"farm_tools": {"id": "farm_tools", "name": "农具", "category": "crafted_good", "sell_price": 192, "buy_price": 244, "base_price": 218, "target_stock": 12, "initial_stock": 6, "daily_liquidity": 5, "volatility": "crafted", "max_stack": 99},
	"machine_parts": {"id": "machine_parts", "name": "机械零件", "category": "crafted_good", "sell_price": 310, "buy_price": 394, "base_price": 352, "target_stock": 8, "initial_stock": 4, "daily_liquidity": 3, "volatility": "crafted", "max_stack": 99},
	"lamp": {"id": "lamp", "name": "灯具", "category": "crafted_good", "sell_price": 153, "buy_price": 195, "base_price": 174, "target_stock": 10, "initial_stock": 5, "daily_liquidity": 4, "volatility": "crafted", "max_stack": 99},
	"sachet": {"id": "sachet", "name": "香包", "category": "crafted_good", "sell_price": 153, "buy_price": 195, "base_price": 174, "target_stock": 10, "initial_stock": 5, "daily_liquidity": 4, "volatility": "crafted", "max_stack": 99},
	"candle": {"id": "candle", "name": "蜡烛", "category": "crafted_good", "sell_price": 63, "buy_price": 81, "base_price": 72, "target_stock": 14, "initial_stock": 7, "daily_liquidity": 6, "volatility": "crafted", "max_stack": 99},
	"perfume": {"id": "perfume", "name": "香水", "category": "crafted_good", "sell_price": 91, "buy_price": 117, "base_price": 104, "target_stock": 8, "initial_stock": 4, "daily_liquidity": 3, "volatility": "luxury", "max_stack": 99},
	"bouquet": {"id": "bouquet", "name": "花束", "category": "crafted_good", "sell_price": 106, "buy_price": 134, "base_price": 120, "target_stock": 12, "initial_stock": 6, "daily_liquidity": 5, "volatility": "luxury", "max_stack": 99},
	"jewelry": {"id": "jewelry", "name": "珠宝", "category": "crafted_good", "sell_price": 299, "buy_price": 381, "base_price": 340, "target_stock": 5, "initial_stock": 2, "daily_liquidity": 2, "volatility": "luxury", "max_stack": 99},
}

static func get_item(item_id: String):
	return ITEMS.get(item_id, INVENTORY_ONLY_ITEMS.get(item_id, null))

static func get_all_items() -> Array:
	var result := []
	for item in ITEMS.values():
		result.append(item)
	for item in INVENTORY_ONLY_ITEMS.values():
		result.append(item)
	return result

static func get_market_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in ITEMS.values():
		if item.get("base_price", 0) > 0 and item.get("category", "") != "legacy":
			result.append(item.duplicate(true))
	for item in INVENTORY_ONLY_ITEMS.values():
		if item.get("base_price", 0) > 0:
			result.append(item.duplicate(true))
	return result

static func get_items_by_category(category: String) -> Array:
	var result := []
	for item in ITEMS.values():
		if item.get("category") == category:
			result.append(item)
	for item in INVENTORY_ONLY_ITEMS.values():
		if item.get("category") == category:
			result.append(item)
	return result

static func get_sell_price(item_id: String) -> int:
	var item = ITEMS.get(item_id)
	if item:
		return item.get("sell_price", 0)
	return 0

static func get_buy_price(item_id: String) -> int:
	var item = ITEMS.get(item_id)
	if item:
		return item.get("buy_price", 0)
	return 0

# ============================================================
# 建筑定义
# ============================================================

const BUILDINGS := {
	"barn": {
		"id": "barn", "name": "谷仓",
		"category": "basic", "palette_order": 30,
		"footprint_x": 2, "footprint_z": 2,
		"cost": {"plank": 8, "stone_brick": 6, "wooden_crate": 1},
		"description": "中央仓库容量 +200；可收集半径内建筑产物",
		"effect": "farm_storage", "effect_value": 200,
		"effect_config": {"nearby_output_collection": {"radius": 6}},
	},
	"greenhouse": {
		"id": "greenhouse", "name": "温室",
		"category": "farming", "palette_order": 30,
		"footprint_x": 3, "footprint_z": 3,
		"cost": {"plank": 15, "stone_brick": 10, "glass": 12, "iron_ingot": 3},
		"description": "无视季节种植作物",
		"effect": "ignore_season", "effect_value": 0,
		"effect_config": {"planting_cells": 8},
	},
	"waterwheel": {
		"id": "waterwheel", "name": "水车",
		"category": "farming", "palette_order": 40,
		"footprint_x": 2, "footprint_z": 2,
		"cost": {"plank": 12, "stone_brick": 8, "iron_ingot": 3, "rope": 2},
		"description": "邻接水域，为半径 4 格内农田自动灌溉",
		"effect": "irrigation", "effect_value": 4,
		"effect_config": {"radius": 4, "requires_water": true},
	},
	"windmill": {
		"id": "windmill", "name": "风车",
		"category": "production", "palette_order": 10,
		"footprint_x": 3, "footprint_z": 3,
		"cost": {"plank": 12, "stone_brick": 8, "rope": 2},
		"description": "加工作物（面粉、果酱等）",
		"effect": "crafting", "effect_value": 0, "station": "windmill",
		"production_yard": {"size": Vector2i(3, 3), "structure_footprint": Vector2i(2, 2), "style": "timber", "building_offset_z": -0.35, "output_capacity": 6},
	},
	"chicken_coop": {
		"id": "chicken_coop", "name": "鸡舍",
		"category": "farming", "palette_order": 10,
		"footprint_x": 3, "footprint_z": 3,
		"cost": {"plank": 8, "stone_brick": 4, "rope": 1},
		"description": "养鸡产蛋",
		"effect": "animal", "effect_value": 0,
		"effect_config": {"feed_item": "animal_feed", "feed_per_day": 1, "output_capacity": 3, "storage_quantity_capacity": 6},
		"production_yard": {"size": Vector2i(3, 3), "structure_footprint": Vector2i(2, 2), "style": "timber", "building_offset_z": -0.35, "output_capacity": 6},
	},
	"beehive": {
		"id": "beehive", "name": "蜂箱",
		"category": "farming", "palette_order": 20,
		"footprint_x": 3, "footprint_z": 3,
		"cost": {"wood": 15},
		"description": "产蜂蜜，加速附近花卉生长",
		"effect": "honey", "effect_value": 0,
		"effect_config": {"flower_radius": 4, "flower_cap": 4, "output_capacity": 3, "storage_quantity_capacity": 6},
		"production_yard": {"size": Vector2i(3, 3), "structure_footprint": Vector2i(1, 1), "style": "timber", "building_offset_z": -0.35, "output_capacity": 6},
	},
	"well": {
		"id": "well", "name": "水井",
		"category": "basic", "palette_order": 40,
		"footprint_x": 1, "footprint_z": 1,
		"cost": {"wood": 10, "stone": 20},
		"description": "提供灌溉水源",
		"effect": "water_source", "effect_value": 0,
	},
	"workbench": {
		"id": "workbench", "name": "工作台",
		"category": "basic", "palette_order": 10,
		"footprint_x": 3, "footprint_z": 3,
		"cost": {"wood": 20, "stone": 10},
		"description": "制作工具和装饰",
		"effect": "crafting", "effect_value": 0, "station": "workbench",
		"production_yard": {"size": Vector2i(3, 3), "structure_footprint": Vector2i(1, 1), "style": "timber", "building_offset_z": -0.35, "output_capacity": 6},
	},
	"stone_kiln": {
		"id": "stone_kiln", "name": "石窑",
		"category": "basic", "palette_order": 20,
		"footprint_x": 3, "footprint_z": 3,
		"cost": {"wood": 20, "stone": 30},
		"description": "烧制石砖、砖块和木炭",
		"effect": "crafting", "effect_value": 0, "station": "stone_kiln",
		"production_yard": {"size": Vector2i(3, 3), "structure_footprint": Vector2i(2, 2), "style": "masonry", "building_offset_z": -0.35, "output_capacity": 6},
	},
	"furnace": {
		"id": "furnace", "name": "熔炉",
		"category": "production", "palette_order": 20,
		"footprint_x": 3, "footprint_z": 3,
		"cost": {"stone_brick": 10, "brick": 6, "charcoal": 4},
		"description": "熔炼矿石、钢材和玻璃",
		"effect": "crafting", "effect_value": 0, "station": "furnace",
		"production_yard": {"size": Vector2i(3, 3), "structure_footprint": Vector2i(2, 2), "style": "industrial", "building_offset_z": -0.35, "output_capacity": 6},
	},
	"food_workshop": {
		"id": "food_workshop", "name": "食品工坊",
		"category": "production", "palette_order": 30,
		"footprint_x": 4, "footprint_z": 4,
		"cost": {"plank": 12, "stone_brick": 8, "glass": 5, "iron_ingot": 2},
		"description": "加工果酱、腌菜、酱料和果汁",
		"effect": "crafting", "effect_value": 0, "station": "food_workshop",
		"production_yard": {"size": Vector2i(4, 4), "structure_footprint": Vector2i(3, 2), "style": "timber", "building_offset_z": -0.55, "output_capacity": 8},
	},
	"textile_machine": {
		"id": "textile_machine", "name": "纺织机",
		"category": "production", "palette_order": 40,
		"footprint_x": 3, "footprint_z": 3,
		"cost": {"plank": 10, "iron_ingot": 4, "machine_parts": 1},
		"description": "将纤维加工为布料和纺织品",
		"effect": "crafting", "effect_value": 0, "station": "textile_machine",
		"production_yard": {"size": Vector2i(3, 3), "structure_footprint": Vector2i(2, 2), "style": "timber", "building_offset_z": -0.35, "output_capacity": 6},
	},
	"lumberyard": {
		"id": "lumberyard", "name": "伐木场",
		"category": "resource", "palette_order": 10,
		"footprint_x": 4, "footprint_z": 4,
		"cost": {"plank": 10, "stone_brick": 6, "rope": 2},
		"description": "每日稳定产出木材",
		"effect": "resource_output", "effect_value": 0,
		"effect_config": {"daily_output": {"wood": 3}, "output_capacity": 3, "storage_quantity_capacity": 9},
		"production_yard": {"size": Vector2i(4, 4), "structure_footprint": Vector2i(3, 2), "style": "timber", "building_offset_z": -0.55, "output_capacity": 8},
	},
	"quarry": {
		"id": "quarry", "name": "采石场",
		"category": "resource", "palette_order": 20,
		"footprint_x": 4, "footprint_z": 4,
		"cost": {"plank": 8, "stone_brick": 10, "farm_tools": 1},
		"description": "每日产出石材，定期发现煤",
		"effect": "resource_output", "effect_value": 0,
		"effect_config": {"daily_output": {"stone": 3}, "bonus_every_days": 3, "bonus_output": {"coal": 1}, "output_capacity": 3, "storage_quantity_capacity": 10},
		"production_yard": {"size": Vector2i(4, 4), "structure_footprint": Vector2i(3, 3), "style": "masonry", "building_offset_z": -0.55, "output_capacity": 8},
	},
	"mine": {
		"id": "mine", "name": "矿场",
		"category": "resource", "palette_order": 30,
		"footprint_x": 4, "footprint_z": 4,
		"cost": {"plank": 20, "stone_brick": 15, "steel": 3, "machine_parts": 2},
		"description": "按开采深度每日产出不同矿石",
		"effect": "resource_output", "effect_value": 0,
		"effect_config": {
			"depth_tier": "shallow",
			"depth_outputs": {
				"shallow": {"copper_ore": 2},
				"middle": {"iron_ore": 2, "coal": 1},
				"deep": {"silver_ore": 1},
			},
			"deep_bonus_every_days": 3,
			"deep_bonus_output": {"gold_ore": 1, "crystal": 1},
			"output_capacity": 4,
			"storage_quantity_capacity": 9,
		},
		"production_yard": {"size": Vector2i(4, 4), "structure_footprint": Vector2i(3, 3), "style": "industrial", "building_offset_z": -0.55, "output_capacity": 8},
	},
	"lamp": {
		"id": "lamp", "name": "路灯",
		"category": "decoration", "palette_order": 10,
		"footprint_x": 1, "footprint_z": 1,
		"cost": {"lamp": 1, "plank": 1},
		"description": "夜间照明，装饰",
		"effect": "light", "effect_value": 0,
	},
	"fence": {
		"id": "fence", "name": "围栏",
		"category": "decoration", "palette_order": 20,
		"footprint_x": 1, "footprint_z": 1,
		"cost": {"wood": 2},
		"description": "划分区域，装饰",
		"effect": "decoration", "effect_value": 0,
	},
}

static func get_building(building_id: String) -> Dictionary:
	return BUILDINGS.get(building_id, {})

static func get_all_buildings() -> Array:
	var result := []
	for b in BUILDINGS.values():
		result.append(b)
	return result

# ============================================================
# 村民定义
# ============================================================

const VILLAGERS := {
	"lao_li": {
		"id": "lao_li", "name": "老李", "role": "杂货商",
		"schedule": {6: "home", 8: "shop", 12: "shop", 13: "shop", 17: "wander", 19: "home", 21: "home", "8-12": "shop"},
		"affinity_rewards": {"order": 10, "gift": 5, "chat": 1},
	},
	"xiao_hua": {
		"id": "xiao_hua", "name": "小花", "role": "花艺师",
		"schedule": {6: "home", 8: "garden", 12: "garden", 13: "shop", 17: "wander", 19: "home", 21: "home"},
		"affinity_rewards": {"order": 10, "gift": 8, "chat": 2},
	},
	"tiejiang_zhang": {
		"id": "tiejiang_zhang", "name": "铁匠张", "role": "工匠",
		"schedule": {6: "home", 8: "forge", 12: "forge", 13: "forge", 17: "wander", 19: "home", 21: "home"},
		"affinity_rewards": {"order": 12, "gift": 5, "chat": 1},
	},
	"afu_shui": {
		"id": "afu_shui", "name": "渔夫阿水", "role": "渔夫",
		"schedule": {6: "creek", 8: "creek", 12: "creek", 13: "creek", 17: "wander", 19: "home", 21: "home"},
		"affinity_rewards": {"order": 10, "gift": 6, "chat": 2},
	},
	"xuezhe_lin": {
		"id": "xuezhe_lin", "name": "学者林", "role": "学者",
		"schedule": {6: "home", 8: "library", 12: "library", 13: "library", 17: "wander", 19: "home", 21: "home"},
		"affinity_rewards": {"order": 8, "gift": 10, "chat": 3},
	},
}

static func get_villager(villager_id: String) -> Dictionary:
	return VILLAGERS.get(villager_id, {})

static func get_all_villagers() -> Array:
	var result := []
	for v in VILLAGERS.values():
		result.append(v)
	return result


const NPC_ECONOMY_PROFILES := [
	{
		"id": "lao_li", "display_name": "老李", "gold": 800,
		"inventory": {"salt": 8, "grain_seed": 6},
		"essential_targets": {"grain": 4, "bread": 2},
		"reserve_targets": {"salt": 8, "grain_seed": 6},
		"production_recipes": [], "sale_targets": {"salt": 4, "grain_seed": 3},
		"investment_gold_threshold": 1200, "import_buffer": true,
	},
	{
		"id": "xiao_hua", "display_name": "小花", "gold": 420,
		"inventory": {"rose": 5, "honey": 2, "fiber": 2},
		"essential_targets": {"grain": 2},
		"reserve_targets": {"rose": 3, "honey": 2, "fiber": 1},
		"production_recipes": ["bouquet"], "sale_targets": {"bouquet": 1, "honey": 2},
		"investment_gold_threshold": 800, "import_buffer": false,
	},
	{
		"id": "tiejiang_zhang", "display_name": "铁匠张", "gold": 650,
		"inventory": {"iron_ore": 6, "coal": 4, "iron_ingot": 2, "plank": 1},
		"essential_targets": {"grain": 2},
		"reserve_targets": {"iron_ore": 4, "coal": 3, "iron_ingot": 2},
		"production_recipes": ["iron_ingot", "farm_tools"],
		"sale_targets": {"iron_ingot": 2, "farm_tools": 1},
		"investment_gold_threshold": 1100, "import_buffer": false,
	},
	{
		"id": "afu_shui", "display_name": "阿水", "gold": 360,
		"inventory": {"grain": 6, "flour": 2, "egg": 2},
		"essential_targets": {"grain": 3},
		"reserve_targets": {"grain": 4, "flour": 2, "egg": 1},
		"production_recipes": ["flour", "bread"],
		"sale_targets": {"flour": 2, "bread": 2},
		"investment_gold_threshold": 700, "import_buffer": false,
	},
	{
		"id": "xuezhe_lin", "display_name": "学者林", "gold": 900,
		"inventory": {"gold_ore": 2, "crystal": 1, "honey_cake": 1},
		"essential_targets": {"bread": 2},
		"reserve_targets": {"crystal": 1, "honey_cake": 1},
		"production_recipes": ["jewelry"], "sale_targets": {"jewelry": 1},
		"investment_gold_threshold": 1500, "import_buffer": false,
	},
]

const POPULATION_DEMAND_PROFILES := [
	{
		"id": "residents", "display_name": "居民",
		"demands": {"grain": 4, "bread": 2}, "demand_tag": "居民基础食品需求",
	},
	{
		"id": "builders", "display_name": "建筑工人",
		"demands": {"plank": 3, "brick": 2}, "demand_tag": "建设材料需求",
	},
	{
		"id": "artisans", "display_name": "工匠",
		"demands": {"iron_ingot": 2, "copper_ingot": 1}, "demand_tag": "工匠金属锭需求",
	},
	{
		"id": "tourists", "display_name": "游客",
		"demands": {"honey_cake": 1}, "demand_tag": "游客奢侈品需求",
	},
]


static func get_npc_economy_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile in NPC_ECONOMY_PROFILES:
		result.append(profile.duplicate(true))
	return result


static func get_population_demand_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile in POPULATION_DEMAND_PROFILES:
		result.append(profile.duplicate(true))
	return result

# ============================================================
# 收集品定义
# ============================================================

const COLLECTIBLES := {
	# 日记碎片
	"diary_fragment_1": {"id": "diary_fragment_1", "name": "日记碎片 #1", "category": "diary", "description": "植物学家的日记第一页"},
	"diary_fragment_2": {"id": "diary_fragment_2", "name": "日记碎片 #2", "category": "diary", "description": "植物学家的日记第二页"},
	"diary_fragment_3": {"id": "diary_fragment_3", "name": "日记碎片 #3", "category": "diary", "description": "植物学家的日记第三页"},
	"diary_fragment_4": {"id": "diary_fragment_4", "name": "日记碎片 #4", "category": "diary", "description": "植物学家的日记第四页"},
	"diary_fragment_5": {"id": "diary_fragment_5", "name": "日记碎片 #5", "category": "diary", "description": "植物学家的日记第五页"},
	"diary_fragment_6": {"id": "diary_fragment_6", "name": "日记碎片 #6", "category": "diary", "description": "植物学家的日记第六页"},
	"diary_fragment_7": {"id": "diary_fragment_7", "name": "日记碎片 #7", "category": "diary", "description": "植物学家的日记第七页"},
	"diary_fragment_8": {"id": "diary_fragment_8", "name": "日记碎片 #8", "category": "diary", "description": "植物学家的日记第八页"},
	"diary_fragment_9": {"id": "diary_fragment_9", "name": "日记碎片 #9", "category": "diary", "description": "植物学家的日记第九页"},
	"diary_fragment_10": {"id": "diary_fragment_10", "name": "日记碎片 #10", "category": "diary", "description": "植物学家的日记第十页"},
	"diary_fragment_11": {"id": "diary_fragment_11", "name": "日记碎片 #11", "category": "diary", "description": "植物学家的日记第十一页"},
	"diary_fragment_12": {"id": "diary_fragment_12", "name": "日记碎片 #12", "category": "diary", "description": "植物学家的日记第十二页"},
	# 化石
	"fossil_1": {"id": "fossil_1", "name": "化石 #1", "category": "fossil", "description": "远古植物化石"},
	"fossil_2": {"id": "fossil_2", "name": "化石 #2", "category": "fossil", "description": "远古植物化石"},
	"fossil_3": {"id": "fossil_3", "name": "化石 #3", "category": "fossil", "description": "远古植物化石"},
	"fossil_4": {"id": "fossil_4", "name": "化石 #4", "category": "fossil", "description": "远古植物化石"},
	"fossil_5": {"id": "fossil_5", "name": "化石 #5", "category": "fossil", "description": "远古植物化石"},
	"fossil_6": {"id": "fossil_6", "name": "化石 #6", "category": "fossil", "description": "远古植物化石"},
	"fossil_7": {"id": "fossil_7", "name": "化石 #7", "category": "fossil", "description": "远古植物化石"},
	"fossil_8": {"id": "fossil_8", "name": "化石 #8", "category": "fossil", "description": "远古植物化石"},
	# 古代遗物
	"relic_1": {"id": "relic_1", "name": "古代遗物 #1", "category": "relic", "description": "神秘的古代遗物"},
	"relic_2": {"id": "relic_2", "name": "古代遗物 #2", "category": "relic", "description": "神秘的古代遗物"},
	"relic_3": {"id": "relic_3", "name": "古代遗物 #3", "category": "relic", "description": "神秘的古代遗物"},
	"relic_4": {"id": "relic_4", "name": "古代遗物 #4", "category": "relic", "description": "神秘的古代遗物"},
	"relic_5": {"id": "relic_5", "name": "古代遗物 #5", "category": "relic", "description": "神秘的古代遗物"},
	"relic_6": {"id": "relic_6", "name": "古代遗物 #6", "category": "relic", "description": "神秘的古代遗物"},
	# 植物标本
	"specimen_1": {"id": "specimen_1", "name": "植物标本 #1", "category": "specimen", "description": "稀有植物标本"},
	"specimen_2": {"id": "specimen_2", "name": "植物标本 #2", "category": "specimen", "description": "稀有植物标本"},
	"specimen_3": {"id": "specimen_3", "name": "植物标本 #3", "category": "specimen", "description": "稀有植物标本"},
	"specimen_4": {"id": "specimen_4", "name": "植物标本 #4", "category": "specimen", "description": "稀有植物标本"},
	"specimen_5": {"id": "specimen_5", "name": "植物标本 #5", "category": "specimen", "description": "稀有植物标本"},
	"specimen_6": {"id": "specimen_6", "name": "植物标本 #6", "category": "specimen", "description": "稀有植物标本"},
	"specimen_7": {"id": "specimen_7", "name": "植物标本 #7", "category": "specimen", "description": "稀有植物标本"},
	"specimen_8": {"id": "specimen_8", "name": "植物标本 #8", "category": "specimen", "description": "稀有植物标本"},
	"specimen_9": {"id": "specimen_9", "name": "植物标本 #9", "category": "specimen", "description": "稀有植物标本"},
	"specimen_10": {"id": "specimen_10", "name": "植物标本 #10", "category": "specimen", "description": "稀有植物标本"},
	"specimen_11": {"id": "specimen_11", "name": "植物标本 #11", "category": "specimen", "description": "稀有植物标本"},
	"specimen_12": {"id": "specimen_12", "name": "植物标本 #12", "category": "specimen", "description": "稀有植物标本"},
	"specimen_13": {"id": "specimen_13", "name": "植物标本 #13", "category": "specimen", "description": "稀有植物标本"},
	"specimen_14": {"id": "specimen_14", "name": "植物标本 #14", "category": "specimen", "description": "稀有植物标本"},
	"specimen_15": {"id": "specimen_15", "name": "植物标本 #15", "category": "specimen", "description": "稀有植物标本"},
	"specimen_16": {"id": "specimen_16", "name": "植物标本 #16", "category": "specimen", "description": "稀有植物标本"},
	"specimen_17": {"id": "specimen_17", "name": "植物标本 #17", "category": "specimen", "description": "稀有植物标本"},
	"specimen_18": {"id": "specimen_18", "name": "植物标本 #18", "category": "specimen", "description": "稀有植物标本"},
	"specimen_19": {"id": "specimen_19", "name": "植物标本 #19", "category": "specimen", "description": "稀有植物标本"},
	"specimen_20": {"id": "specimen_20", "name": "植物标本 #20", "category": "specimen", "description": "稀有植物标本"},
}

static func get_collectible(collectible_id: String) -> Dictionary:
	return COLLECTIBLES.get(collectible_id, {})

static func get_all_collectibles() -> Array:
	var result := []
	for c in COLLECTIBLES.values():
		result.append(c)
	return result

static func get_collectibles_by_category(category: String) -> Array:
	var result := []
	for c in COLLECTIBLES.values():
		if c.get("category") == category:
			result.append(c)
	return result

static func get_collectible_count_by_category(category: String) -> int:
	var count := 0
	for c in COLLECTIBLES.values():
		if c.get("category") == category:
			count += 1
	return count
