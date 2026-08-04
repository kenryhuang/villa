class_name ResourceCatalog
extends RefCounted

const DEFINITIONS := {
	"tree": {
		"resource_type": "tree",
		"item_id": "wood",
		"required_tool": "axe",
		"max_units": 5,
		"respawn_days": 3,
		"display_name": "树木",
		"color": Color("6f8d45"),
		"visual_kind": "tree",
	},
	"stone": {
		"resource_type": "stone",
		"item_id": "stone",
		"required_tool": "pickaxe",
		"max_units": 4,
		"respawn_days": 3,
		"display_name": "石材",
		"color": Color("72777a"),
		"visual_kind": "stone",
	},
	"coal": {
		"resource_type": "coal",
		"item_id": "coal",
		"required_tool": "pickaxe",
		"max_units": 3,
		"respawn_days": 4,
		"display_name": "煤矿",
		"color": Color("34383a"),
		"visual_kind": "coal",
	},
	"copper_ore": {
		"resource_type": "copper_ore",
		"item_id": "copper_ore",
		"required_tool": "pickaxe",
		"max_units": 3,
		"respawn_days": 4,
		"display_name": "铜矿",
		"color": Color("a86543"),
		"visual_kind": "copper",
	},
	"iron_ore": {
		"resource_type": "iron_ore",
		"item_id": "iron_ore",
		"required_tool": "pickaxe",
		"max_units": 3,
		"respawn_days": 4,
		"display_name": "铁矿",
		"color": Color("626c75"),
		"visual_kind": "iron",
	},
	"silver_ore": {
		"resource_type": "silver_ore",
		"item_id": "silver_ore",
		"required_tool": "pickaxe",
		"max_units": 2,
		"respawn_days": 7,
		"display_name": "银矿",
		"color": Color("aebcc5"),
		"visual_kind": "silver",
	},
	"gold_ore": {
		"resource_type": "gold_ore",
		"item_id": "gold_ore",
		"required_tool": "pickaxe",
		"max_units": 2,
		"respawn_days": 7,
		"display_name": "金矿",
		"color": Color("d5a83f"),
		"visual_kind": "gold",
	},
	"crystal": {
		"resource_type": "crystal",
		"item_id": "crystal",
		"required_tool": "pickaxe",
		"max_units": 2,
		"respawn_days": 7,
		"display_name": "水晶矿",
		"color": Color("8f76c8"),
		"visual_kind": "crystal",
	},
}


static func definition(resource_type: String) -> Dictionary:
	if not DEFINITIONS.has(resource_type):
		return {}
	return (DEFINITIONS[resource_type] as Dictionary).duplicate(true)


static func all_types() -> Array[String]:
	var result: Array[String] = []
	for resource_type in DEFINITIONS:
		result.append(str(resource_type))
	result.sort()
	return result
