class_name CropCatalog
extends RefCounted

## Lightweight access to the original grain definition for standalone adapters.
static func grain_definition() -> CropData:
	return default_crop_definitions().front()


static func default_crop_definitions() -> Array[CropData]:
	var rows := [
		{"id":"grain","plant_item_id":"grain_seed","name":"谷物","days":3,"yield":[2,4],"regrow":0,"seasons":[0,1,2],"lifecycle_type":"annual","environment":"outdoor_or_greenhouse","exp":5},
		{"id":"carrot","plant_item_id":"carrot_seed","name":"胡萝卜","days":3,"yield":[2,3],"regrow":0,"seasons":[0,2],"lifecycle_type":"annual","environment":"outdoor_or_greenhouse","exp":4},
		{"id":"potato","plant_item_id":"potato_seed","name":"土豆","days":4,"yield":[3,5],"regrow":0,"seasons":[0,2],"lifecycle_type":"annual","environment":"outdoor_or_greenhouse","exp":6},
		{"id":"tomato","plant_item_id":"tomato_seed","name":"番茄","days":4,"yield":[2,3],"regrow":2,"seasons":[0,1],"lifecycle_type":"annual_regrow","environment":"outdoor_or_greenhouse","exp":5},
		{"id":"strawberry","plant_item_id":"strawberry_seed","name":"草莓","days":4,"yield":[2,3],"regrow":2,"seasons":[0],"lifecycle_type":"bush","environment":"outdoor_or_greenhouse","exp":5},
		{"id":"blueberry","plant_item_id":"blueberry_seed","name":"蓝莓","days":5,"yield":[2,3],"regrow":2,"seasons":[1],"lifecycle_type":"bush","environment":"outdoor_or_greenhouse","exp":6},
		{"id":"watermelon","plant_item_id":"watermelon_seed","name":"西瓜","days":5,"yield":[1,2],"regrow":0,"seasons":[1],"lifecycle_type":"annual","environment":"outdoor_or_greenhouse","exp":7},
		{"id":"sunflower","plant_item_id":"sunflower_seed","name":"向日葵","days":4,"yield":[2,3],"regrow":0,"seasons":[1,2],"lifecycle_type":"annual","environment":"outdoor_or_greenhouse","tags":["flower"],"category":"flower","exp":5},
		{"id":"lavender","plant_item_id":"lavender_seed","name":"薰衣草","days":4,"yield":[2,3],"regrow":0,"seasons":[1,2],"lifecycle_type":"annual","environment":"outdoor_or_greenhouse","tags":["flower"],"category":"flower","exp":5},
		{"id":"pumpkin","plant_item_id":"pumpkin_seed","name":"南瓜","days":5,"yield":[1,2],"regrow":0,"seasons":[2],"lifecycle_type":"annual","environment":"outdoor_or_greenhouse","exp":7},
		{"id":"rose","plant_item_id":"rose_seed","name":"玫瑰","days":4,"yield":[2,3],"regrow":0,"seasons":[0,1],"lifecycle_type":"annual","environment":"outdoor_or_greenhouse","tags":["flower"],"category":"flower","exp":5},
		{"id":"apple","plant_item_id":"apple_sapling","name":"苹果","days":5,"yield":[2,4],"regrow":3,"seasons":[2],"lifecycle_type":"tree","environment":"outdoor_or_greenhouse","tags":["fruit"],"category":"fruit","exp":8},
		{"id":"peach","plant_item_id":"peach_sapling","name":"桃子","days":5,"yield":[2,3],"regrow":3,"seasons":[1],"lifecycle_type":"tree","environment":"outdoor_or_greenhouse","tags":["fruit"],"category":"fruit","exp":8},
		{"id":"grape","plant_item_id":"grape_seed","name":"葡萄","days":4,"yield":[2,4],"regrow":2,"seasons":[1,2],"lifecycle_type":"vine","environment":"outdoor_or_greenhouse","tags":["fruit"],"category":"fruit","exp":7},
		{"id":"lemon","plant_item_id":"lemon_sapling","name":"柠檬","days":5,"yield":[2,3],"regrow":3,"seasons":[],"lifecycle_type":"tree","environment":"greenhouse_only","tags":["fruit","greenhouse_only"],"category":"fruit","exp":8},
	]
	var definitions: Array[CropData] = []
	for row in rows:
		var crop := CropData.new()
		crop.crop_id = str(row.id)
		crop.plant_item_id = str(row.plant_item_id)
		crop.name = str(row.name)
		crop.crop_name = str(row.name)
		crop.category = str(row.get("category", "crop"))
		crop.environment = str(row.environment)
		crop.lifecycle_type = str(row.lifecycle_type)
		crop.growth_days = int(row.days)
		crop.growth_duration_minutes = 108
		crop.regrow_duration_minutes = 108
		crop.yield_min = int(row.yield[0])
		crop.yield_max = int(row.yield[1])
		crop.regrow_days = int(row.get("regrow", 0))
		crop.seasons.assign(row.seasons)
		crop.growth_form = "annual" if crop.lifecycle_type == "annual_regrow" else crop.lifecycle_type
		crop.tags.assign(row.get("tags", []))
		crop.exp_reward = int(row.exp)
		var seed_scene := "res://assets/crops/%s/%s_stage_0_seed.tscn" % [crop.crop_id, crop.crop_id]
		var sprout_scene := "res://assets/crops/%s/%s_stage_1_sprout.tscn" % [crop.crop_id, crop.crop_id]
		var growing_scene := "res://assets/crops/%s/%s_stage_2_growing.tscn" % [crop.crop_id, crop.crop_id]
		var mature_scene := "res://assets/crops/%s/%s_stage_3_mature.tscn" % [crop.crop_id, crop.crop_id]
		if crop.crop_id in ["potato","tomato","lavender","rose","carrot","apple","peach","lemon","grape","blueberry","strawberry","watermelon","pumpkin","sunflower"]:
			var seed_texture := "res://assets/crops/%s/painted/stage_0/variant_0_front.png" % crop.crop_id
			var mature_texture := "res://assets/crops/%s/painted/stage_3/variant_0_front.png" % crop.crop_id
			crop.stage_textures.assign([seed_texture, seed_texture, seed_texture, mature_texture])
			crop.stage_scenes.assign([seed_scene, seed_scene, seed_scene, mature_scene])
		else:
			crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
			crop.stage_scenes.assign([seed_scene, sprout_scene, growing_scene, mature_scene])
		definitions.append(crop)
	return definitions
