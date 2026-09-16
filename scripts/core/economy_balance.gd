class_name EconomyBalance
extends RefCounted

const Data = preload("res://scripts/core/game_data.gd")
const Prices = preload("res://scripts/shared/market_math.gd")
const RENT_SHARE := 0.30
const TENANT_MARGIN := 0.15

# Reference quotes include the same spread and quantity slippage as market trades.
# They are stable catalog estimates, not guarantees of today's stock or sale price.
static func reference_value(items: Dictionary, buying: bool) -> int:
	var total := 0
	for id in items:
		var item: Dictionary = Data.get_item(str(id))
		total += Prices.quote_total(int(item.get("base_price",0)),int(items[id]),int(item.get("daily_liquidity",1)),buying)
	return total

static func rental_reference(recipe: Dictionary) -> Dictionary:
	var inputs: Dictionary = recipe.inputs.duplicate(true)
	for selector in recipe.get("input_selectors", []):
		# Use the most expensive eligible input, so a cheap fish is not required
		# merely to afford the standard rent. Actual inputs still come from preflight.
		var selected := ""
		var highest := -1
		for item in Data.get_market_items():
			if str(selector.tag) not in item.get("tags",[]): continue
			var value := reference_value({item.id:int(selector.quantity)},true)
			if value > highest: highest = value; selected = str(item.id)
		if not selected.is_empty(): inputs[selected] = int(inputs.get(selected,0)) + int(selector.quantity)
	var cost := reference_value(inputs,true)
	var revenue := reference_value(recipe.outputs,false)
	var added := revenue-cost
	var fee := maxi(1,mini(roundi(maxi(0,added)*RENT_SHARE),floori(revenue*(1.0-TENANT_MARGIN)-cost)))
	return {"pricing_basis":"catalog_reference_not_live_quote","input_cost":cost,"sale_value":revenue,"value_added":added,"default_fee":fee,"tenant_profit":revenue-cost-fee}

static func maintenance(building_id: String) -> Dictionary:
	var building := Data.get_building(building_id)
	if building.is_empty(): return {}
	var value := 0
	for id in building.cost: value += int(building.cost[id])*int(Data.get_item(id).get("base_price",0))
	var materials := {"wood":1,"stone":1}
	if building_id == "beehive": materials = {"wood":1}
	elif building_id in ["stone_kiln","furnace","quarry","mine"]: materials = {"stone":1}
	return {"gold_cost":maxi(2,ceili(value*0.02)),"materials":materials}
