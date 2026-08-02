class_name NpcEconomyState
extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")

const SERIALIZED_FIELDS := [
	"npc_id",
	"gold",
	"inventory",
	"reserve_targets",
	"production_recipes",
	"sale_targets",
	"last_simulated_day",
	"investment_planned",
]

var npc_id := ""
var gold := 0
var inventory: Dictionary = {}
var reserve_targets: Dictionary = {}
var production_recipes: Array[String] = []
var sale_targets: Dictionary = {}
var last_simulated_day := 0
var investment_planned := false


func to_dict() -> Dictionary:
	return {
		"npc_id": npc_id,
		"gold": gold,
		"inventory": inventory.duplicate(true),
		"reserve_targets": reserve_targets.duplicate(true),
		"production_recipes": production_recipes.duplicate(),
		"sale_targets": sale_targets.duplicate(true),
		"last_simulated_day": last_simulated_day,
		"investment_planned": investment_planned,
	}


func from_dict(data: Dictionary) -> bool:
	if data.size() != SERIALIZED_FIELDS.size():
		return false
	for field in SERIALIZED_FIELDS:
		if not data.has(field):
			return false
	if typeof(data["npc_id"]) != TYPE_STRING or str(data["npc_id"]).is_empty():
		return false
	if not _is_nonnegative_integer(data["gold"]):
		return false
	if not _is_nonnegative_integer(data["last_simulated_day"]):
		return false
	if typeof(data["investment_planned"]) != TYPE_BOOL:
		return false
	var normalized_inventory: Variant = _normalize_item_quantities(data["inventory"])
	if normalized_inventory == null:
		return false
	var normalized_reserves: Variant = _normalize_item_quantities(data["reserve_targets"])
	if normalized_reserves == null:
		return false
	var normalized_sales: Variant = _normalize_item_quantities(data["sale_targets"])
	if normalized_sales == null:
		return false
	var normalized_recipes: Variant = _normalize_recipes(data["production_recipes"])
	if normalized_recipes == null:
		return false

	npc_id = str(data["npc_id"])
	gold = int(data["gold"])
	inventory = normalized_inventory
	reserve_targets = normalized_reserves
	production_recipes.assign(normalized_recipes)
	sale_targets = normalized_sales
	last_simulated_day = int(data["last_simulated_day"])
	investment_planned = bool(data["investment_planned"])
	return true


func _normalize_item_quantities(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var normalized: Dictionary = {}
	for item_key in (value as Dictionary).keys():
		if typeof(item_key) != TYPE_STRING:
			return null
		var item_id := str(item_key)
		if item_id.is_empty() or GameDataScript.get_item(item_id) == null:
			return null
		var quantity: Variant = (value as Dictionary)[item_key]
		if not _is_nonnegative_integer(quantity):
			return null
		normalized[item_id] = int(quantity)
	return normalized


func _normalize_recipes(value: Variant) -> Variant:
	if not value is Array:
		return null
	var normalized: Array[String] = []
	for recipe_value in value as Array:
		if typeof(recipe_value) != TYPE_STRING:
			return null
		var recipe_id := str(recipe_value)
		if (
			recipe_id.is_empty()
			or recipe_id in normalized
			or RecipeDatabaseScript.get_recipe(recipe_id).is_empty()
		):
			return null
		normalized.append(recipe_id)
	return normalized


func _is_nonnegative_integer(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) >= 0
	)
