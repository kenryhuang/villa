extends "res://scripts/ui/building_production_panel.gd"

## Reuse original request/preflight/collection state; the 3D shell renders it.
var session: Farm3DSession

func configure_farm(farm_session: Farm3DSession) -> void:
	session = farm_session
	_production = session.production
	_inventory = session.inventory
	_progression = null # The 3D catalog already exposes these building recipes.
	_connect_event_bus()

func _render() -> void:
	pass

func _maximum_batches(building: BuildingInstance, recipe: Dictionary) -> int:
	var maximum := MAX_UI_BATCHES
	var per_batch := 0
	for id in recipe.inputs:
		maximum = mini(maximum, _inventory.get_item_count(id) / int(recipe.inputs[id]))
		per_batch += int(recipe.inputs[id])
	for selector in recipe.get("input_selectors",[]):
		per_batch += int(selector.quantity)
	var capacity := int(building.data.effect_config.get("input_capacity", DEFAULT_INPUT_CAPACITY))
	maximum = mini(maximum, capacity / maxi(1, per_batch))
	if not recipe.get("input_selectors",[]).is_empty():
		var low := 0
		var high := maximum
		while low < high:
			var mid := (low+high+1)/2
			var resolution := _production._resolve_recipe_inputs(recipe,mid,_inventory)
			if resolution.valid and resolution.missing.is_empty():
				low = mid
			else:
				high = mid-1
		maximum = low
	return maximum

func set_batches(value: int) -> void:
	# Let the preflight explain insufficient materials instead of silently clamping.
	failure_reason = ""
	failure_message = ""
	batches = clampi(value, 1, MAX_UI_BATCHES)
	refresh_snapshot()

func select_recipe(id: String) -> void:
	failure_reason = ""
	failure_message = ""
	super.select_recipe(id)

func _build_recipe_detail(building: BuildingInstance) -> void:
	var requested := batches
	super._build_recipe_detail(building)
	if requested != batches:
		batches = requested
		var recipe := RecipeDatabaseScript.get_recipe(selected_recipe_id)
		preflight = _production.preflight_recipe(building, selected_recipe_id, batches, _inventory)
		recipe_detail.inputs = _multiply(recipe.inputs, batches)
		recipe_detail.outputs = _multiply(recipe.outputs, batches)
		recipe_detail.duration_minutes = int(recipe.duration_minutes) * batches
		var pricing := _pricing(recipe, batches)
		recipe_detail.merge({"input_value": pricing.input_value, "output_value": pricing.output_value, "margin": pricing.margin}, true)
		disabled_reason = _reason_text(preflight)
	var selected := RecipeDatabaseScript.get_recipe(selected_recipe_id)
	if not selected.get("input_selectors",[]).is_empty():
		var resolution := _production._resolve_recipe_inputs(selected,batches,_inventory)
		recipe_detail.inputs = resolution.inputs.duplicate()
		for key in resolution.missing:
			if str(key).begins_with("tag:"):
				recipe_detail.inputs[key] = resolution.missing[key]

func _pricing(recipe: Dictionary, multiplier: int) -> Dictionary:
	var input_value := 0
	var output_value := 0
	var required: Dictionary = _production._resolve_recipe_inputs(recipe,multiplier,_inventory).inputs
	for id in required:
		input_value += session.market.quote_sell(id, int(required[id]))
	for id in recipe.outputs:
		output_value += session.market.quote_sell(id, int(recipe.outputs[id]) * multiplier)
	var margin := output_value - input_value
	return {"input_value": input_value, "output_value": output_value, "margin": margin, "status": "profit" if margin > 0 else "loss" if margin < 0 else "even"}

func _reason_text(result: Dictionary) -> String:
	if str(result.get("reason", "")) == "maintenance_in_progress":
		return "维护中，请稍候"
	return super._reason_text(result)

func _item_name(id: String) -> String:
	return "普通鱼" if id == "tag:common_fish" else super._item_name(id)
