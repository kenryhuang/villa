class_name NpcEconomySystem
extends Node

const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")

const NpcEconomyStateScript = preload("res://scripts/data/npc_economy_state.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")

const IMPORT_DAY_THRESHOLD := 3
const IMPORT_QUANTITY_CAP := 5
const IMPORT_COST_MULTIPLIER := 1.25
const EMERGENCY_CARAVAN_ID := "lao_li_emergency_import"
const FACTOR_MIN := 0.0
const FACTOR_MAX := 3.0
const SYSTEM_FIELDS := [
	"last_simulated_day",
	"npc_states",
	"essential_zero_streaks",
	"demand_tags",
	"pending_caravan_departures",
]
const LEGACY_SYSTEM_FIELDS := [
	"last_simulated_day",
	"npc_states",
	"essential_zero_streaks",
	"demand_tags",
]

var last_simulated_day := 0

var _market_system: Variant
var _profiles: Dictionary = {}
var _states: Dictionary = {}
var _population_profiles: Array[Dictionary] = []
var _item_definitions: Dictionary = {}
var _essential_zero_streaks: Dictionary = {}
var _demand_tags: Dictionary = {}
var _pending_caravan_departures: Array[Dictionary] = []
var _is_configured := false
var _is_simulating := false
var _event_bus: Node


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")


func configure(
	market_system: Variant,
	npc_profiles: Array,
	population_profiles: Array
) -> bool:
	if not _has_methods(market_system, [
		"get_item_state", "get_stock", "quote_buy", "quote_sell",
		"can_buy", "commit_buy", "commit_sell", "add_external_demand",
		"to_dict", "from_dict", "begin_atomic_transaction", "end_atomic_transaction",
	]):
		return false
	var candidate_definitions := _market_definitions(market_system)
	if candidate_definitions.is_empty():
		return false
	var candidate_profiles: Dictionary = {}
	var candidate_states: Dictionary = {}
	for profile_value in npc_profiles:
		var profile := _normalize_npc_profile(profile_value)
		if profile.is_empty() or candidate_profiles.has(profile.id):
			return false
		var state := NpcEconomyStateScript.new()
		if not state.from_dict({
			"npc_id": profile.id,
			"gold": profile.gold,
			"inventory": profile.inventory,
			"reserve_targets": profile.reserve_targets,
			"production_recipes": profile.production_recipes,
			"sale_targets": profile.sale_targets,
			"last_simulated_day": 0,
			"investment_planned": false,
		}):
			return false
		candidate_profiles[profile.id] = profile
		candidate_states[profile.id] = state
	var candidate_population: Array[Dictionary] = []
	var group_ids: Dictionary = {}
	for population_value in population_profiles:
		var population := _normalize_population_profile(population_value)
		if population.is_empty() or group_ids.has(population.id):
			return false
		group_ids[population.id] = true
		candidate_population.append(population)

	_market_system = market_system
	_profiles = candidate_profiles
	_states = candidate_states
	_population_profiles = candidate_population
	_item_definitions = candidate_definitions
	_essential_zero_streaks.clear()
	for item_id in _essential_item_ids():
		_essential_zero_streaks[item_id] = 0
	_demand_tags.clear()
	_pending_caravan_departures.clear()
	last_simulated_day = 0
	_is_configured = true
	return true


func simulate_day(
	total_day: int,
	season_factors: Dictionary = {},
	event_factors: Dictionary = {}
) -> bool:
	if (
		_is_simulating
		or not _is_configured
		or not EconomyLimitsScript.is_safe_date(total_day, false)
		or total_day <= last_simulated_day
	):
		return false
	for state_value in _states.values():
		var state: NpcEconomyState = state_value
		if state.last_simulated_day >= total_day:
			return false
	_is_simulating = true
	for state_value in _states.values():
		(state_value as NpcEconomyState).last_simulated_day = total_day
	last_simulated_day = total_day
	var due_departures: Array[Dictionary] = []
	var future_departures: Array[Dictionary] = []
	for departure in _pending_caravan_departures:
		if int(departure.departure_day) <= total_day:
			due_departures.append(departure)
		else:
			future_departures.append(departure)
	_pending_caravan_departures = future_departures
	for departure in due_departures:
		_emit_event("market_caravan_changed", [
			str(departure.caravan_id),
			str(departure.item_id),
			int(departure.quantity),
			int(departure.departure_day),
			false,
		])

	_demand_tags.clear()
	for npc_id_value in _profiles.keys():
		var npc_id := str(npc_id_value)
		_simulate_npc(_states[npc_id], _profiles[npc_id])
	_apply_population_demand(season_factors, event_factors)
	_update_shortages_and_imports(total_day)
	_is_simulating = false
	return true


func sync_daily_cursor(total_day: int) -> bool:
	if not _is_configured or not EconomyLimitsScript.is_safe_date(total_day):
		return false
	if total_day != last_simulated_day:
		_pending_caravan_departures.clear()
	last_simulated_day = total_day
	for state_value in _states.values():
		(state_value as NpcEconomyState).last_simulated_day = total_day
	return true


func get_npc_state(npc_id: String) -> NpcEconomyState:
	return _states.get(npc_id) as NpcEconomyState


func has_npc(npc_id: String) -> bool:
	return _is_configured and _states.has(npc_id)


func has_item(item_id: String) -> bool:
	return _is_configured and _item_definitions.has(item_id)


func get_shortages() -> Array[Dictionary]:
	var shortages: Array[Dictionary] = []
	if not _is_configured:
		return shortages
	var npc_ids := _states.keys()
	npc_ids.sort()
	for npc_id_value in npc_ids:
		var npc_id := str(npc_id_value)
		var state: NpcEconomyState = _states[npc_id]
		var targets := _shortage_targets(state, _profiles[npc_id])
		var item_ids := targets.keys()
		item_ids.sort()
		for item_id_value in item_ids:
			var item_id := str(item_id_value)
			var quantity := int(targets[item_id]) - int(state.inventory.get(item_id, 0))
			if quantity > 0:
				shortages.append({
					"npc_id": npc_id,
					"item_id": item_id,
					"quantity": quantity,
				})
	return shortages


func can_receive_item(npc_id: String, item_id: String, quantity: int) -> bool:
	return quantity > 0 and has_npc(npc_id) and has_item(item_id)


func receive_item(npc_id: String, item_id: String, quantity: int) -> bool:
	if not can_receive_item(npc_id, item_id, quantity):
		return false
	var state: NpcEconomyState = _states[npc_id]
	var current := int(state.inventory.get(item_id, 0))
	if current > 9223372036854775807 - quantity:
		return false
	state.inventory[item_id] = current + quantity
	return true


func get_demand_tags() -> Dictionary:
	return _demand_tags.duplicate(true)


func get_essential_zero_streaks() -> Dictionary:
	return _essential_zero_streaks.duplicate(true)


func to_dict() -> Dictionary:
	var serialized_states: Array[Dictionary] = []
	var npc_ids := _states.keys()
	npc_ids.sort()
	for npc_id in npc_ids:
		serialized_states.append((_states[npc_id] as NpcEconomyState).to_dict())
	return {
		"last_simulated_day": last_simulated_day,
		"npc_states": serialized_states,
		"essential_zero_streaks": _essential_zero_streaks.duplicate(true),
		"demand_tags": _demand_tags.duplicate(true),
		"pending_caravan_departures": _pending_caravan_departures.duplicate(true),
	}


func from_dict(data: Dictionary) -> bool:
	var normalized: Variant = _normalize_system_data(data)
	if normalized == null:
		return false
	_states = normalized.states
	_essential_zero_streaks = normalized.streaks
	_demand_tags = normalized.tags
	_pending_caravan_departures.assign(normalized.departures)
	last_simulated_day = int(normalized.cursor)
	return true


func validate_dict(data: Dictionary) -> bool:
	return _normalize_system_data(data) != null


func reset_to_profile_defaults(total_day: int) -> bool:
	if not _is_configured or total_day < 0:
		return false
	var candidate_states: Dictionary = {}
	for npc_id_value in _profiles.keys():
		var npc_id := str(npc_id_value)
		var profile: Dictionary = _profiles[npc_id]
		var state := NpcEconomyStateScript.new()
		if not state.from_dict({
			"npc_id": npc_id,
			"gold": profile.gold,
			"inventory": profile.inventory,
			"reserve_targets": profile.reserve_targets,
			"production_recipes": profile.production_recipes,
			"sale_targets": profile.sale_targets,
			"last_simulated_day": total_day,
			"investment_planned": false,
		}):
			return false
		candidate_states[npc_id] = state
	var candidate_streaks: Dictionary = {}
	for item_id in _essential_zero_streaks:
		candidate_streaks[item_id] = 0
	_states = candidate_states
	_essential_zero_streaks = candidate_streaks
	_demand_tags.clear()
	_pending_caravan_departures.clear()
	last_simulated_day = total_day
	return true


func _normalize_system_data(data: Dictionary) -> Variant:
	if not _is_configured:
		return null
	var fields := SYSTEM_FIELDS if data.has("pending_caravan_departures") else LEGACY_SYSTEM_FIELDS
	if data.size() != fields.size():
		return null
	for field in fields:
		if not data.has(field):
			return null
	if not _is_nonnegative_integer(data.last_simulated_day):
		return null
	if not data.npc_states is Array or (data.npc_states as Array).size() != _states.size():
		return null
	var cursor := int(data.last_simulated_day)
	if not EconomyLimitsScript.is_safe_date(cursor):
		return null
	var candidate_states: Dictionary = {}
	for state_value in data.npc_states as Array:
		if not state_value is Dictionary:
			return null
		var state := NpcEconomyStateScript.new()
		if not state.from_dict(state_value):
			return null
		if (
			not _states.has(state.npc_id)
			or candidate_states.has(state.npc_id)
			or state.last_simulated_day != cursor
		):
			return null
		candidate_states[state.npc_id] = state
	var candidate_streaks: Variant = _normalize_streaks(data.essential_zero_streaks)
	if candidate_streaks == null:
		return null
	var candidate_tags: Variant = _normalize_tags(data.demand_tags)
	if candidate_tags == null:
		return null
	var candidate_departures: Variant = _normalize_pending_caravan_departures(
		data.get("pending_caravan_departures", []),
		cursor
	)
	if candidate_departures == null:
		return null
	return {
		"states": candidate_states,
		"streaks": candidate_streaks,
		"tags": candidate_tags,
		"departures": candidate_departures,
		"cursor": cursor,
	}


func _simulate_npc(state: NpcEconomyState, profile: Dictionary) -> void:
	if not _buy_targets(state, profile.essential_targets):
		state.investment_planned = false
		return
	_buy_production_inputs(state)
	_produce(state)
	if not _buy_targets(state, state.reserve_targets):
		state.investment_planned = false
		return
	_sell_excess(state)
	state.investment_planned = state.gold >= int(profile.investment_gold_threshold)


func _shortage_targets(state: NpcEconomyState, profile: Dictionary) -> Dictionary:
	var targets: Dictionary = {}
	for source_value in [profile.essential_targets, state.reserve_targets]:
		for item_id_value in (source_value as Dictionary).keys():
			var item_id := str(item_id_value)
			targets[item_id] = maxi(int(targets.get(item_id, 0)), int(source_value[item_id]))
	for recipe_id in state.production_recipes:
		var recipe: Dictionary = RecipeDatabaseScript.get_recipe(str(recipe_id))
		if recipe.is_empty():
			continue
		for item_id_value in (recipe.inputs as Dictionary).keys():
			var item_id := str(item_id_value)
			var production_target := _protected_quantity(state, item_id) + int(recipe.inputs[item_id])
			targets[item_id] = maxi(int(targets.get(item_id, 0)), production_target)
	return targets


func _buy_targets(state: NpcEconomyState, targets: Dictionary) -> bool:
	var purchases: Dictionary = {}
	for item_id_value in targets.keys():
		var item_id := str(item_id_value)
		var needed := int(targets[item_id]) - int(state.inventory.get(item_id, 0))
		if needed > 0:
			purchases[item_id] = needed
	if not _buy_bundle(state, purchases):
		return false
	for item_id_value in targets.keys():
		var item_id := str(item_id_value)
		if int(state.inventory.get(item_id, 0)) < int(targets[item_id]):
			return false
	return true


func _buy_production_inputs(state: NpcEconomyState) -> void:
	if not _protected_targets_met(state):
		return
	for recipe_id in state.production_recipes:
		var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
		var purchases: Dictionary = {}
		for item_id_value in (recipe.inputs as Dictionary).keys():
			var item_id := str(item_id_value)
			var protected := _protected_quantity(state, item_id)
			var required := int(recipe.inputs[item_id])
			var needed := protected + required - int(state.inventory.get(item_id, 0))
			if needed > 0:
				purchases[item_id] = needed
		_buy_bundle(state, purchases)


func _produce(state: NpcEconomyState) -> void:
	for recipe_id in state.production_recipes:
		var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
		if recipe.is_empty():
			continue
		var batches := 1
		for item_id_value in (recipe.inputs as Dictionary).keys():
			var item_id := str(item_id_value)
			var available := int(state.inventory.get(item_id, 0)) - _protected_quantity(state, item_id)
			var required := int(recipe.inputs[item_id])
			batches = mini(batches, available / required)
		if batches <= 0:
			continue
		for item_id_value in (recipe.inputs as Dictionary).keys():
			var item_id := str(item_id_value)
			state.inventory[item_id] = int(state.inventory.get(item_id, 0)) - int(recipe.inputs[item_id]) * batches
		for item_id_value in (recipe.outputs as Dictionary).keys():
			var item_id := str(item_id_value)
			state.inventory[item_id] = int(state.inventory.get(item_id, 0)) + int(recipe.outputs[item_id]) * batches


func _sell_excess(state: NpcEconomyState) -> void:
	var sales: Dictionary = {}
	for item_id_value in state.sale_targets.keys():
		var item_id := str(item_id_value)
		var sale_floor := maxi(
			int(state.sale_targets[item_id]),
			_protected_quantity(state, item_id)
		)
		var quantity := int(state.inventory.get(item_id, 0)) - sale_floor
		if quantity <= 0:
			continue
		var total := int(_market_system.call("quote_sell", item_id, quantity))
		if total > 0:
			sales[item_id] = quantity
	_sell_bundle(state, sales)


func _buy_exact(state: NpcEconomyState, item_id: String, quantity: int) -> bool:
	return _buy_bundle(state, {item_id: quantity})


func _buy_bundle(state: NpcEconomyState, purchases: Dictionary) -> bool:
	if purchases.is_empty():
		return true
	var total_cost := 0
	for item_id_value in purchases.keys():
		var item_id := str(item_id_value)
		var quantity := int(purchases[item_id])
		if quantity <= 0 or not bool(_market_system.call("can_buy", item_id, quantity)):
			return false
		var quote := int(_market_system.call("quote_buy", item_id, quantity))
		if quote <= 0:
			return false
		total_cost += quote
	if state.gold < total_cost:
		return false
	var market_before: Dictionary = _market_system.call("to_dict")
	if not bool(_market_system.call("begin_atomic_transaction")):
		return false
	for item_id_value in purchases.keys():
		var item_id := str(item_id_value)
		var quantity := int(purchases[item_id])
		if not bool(_market_system.call("commit_buy", item_id, quantity)):
			_market_system.call("from_dict", market_before)
			_market_system.call("end_atomic_transaction", false)
			return false
	state.gold -= total_cost
	for item_id_value in purchases.keys():
		var item_id := str(item_id_value)
		state.inventory[item_id] = int(state.inventory.get(item_id, 0)) + int(purchases[item_id])
	_market_system.call("end_atomic_transaction", true)
	return true


func _sell_bundle(state: NpcEconomyState, sales: Dictionary) -> bool:
	if sales.is_empty():
		return true
	var total_income := 0
	for item_id_value in sales.keys():
		var item_id := str(item_id_value)
		var quantity := int(sales[item_id])
		if quantity <= 0 or int(state.inventory.get(item_id, 0)) < quantity:
			return false
		var quote := int(_market_system.call("quote_sell", item_id, quantity))
		if quote <= 0:
			return false
		total_income += quote
	var market_before: Dictionary = _market_system.call("to_dict")
	if not bool(_market_system.call("begin_atomic_transaction")):
		return false
	for item_id_value in sales.keys():
		var item_id := str(item_id_value)
		var quantity := int(sales[item_id])
		if not bool(_market_system.call("commit_sell", item_id, quantity)):
			_market_system.call("from_dict", market_before)
			_market_system.call("end_atomic_transaction", false)
			return false
	state.gold += total_income
	for item_id_value in sales.keys():
		var item_id := str(item_id_value)
		state.inventory[item_id] = int(state.inventory.get(item_id, 0)) - int(sales[item_id])
	_market_system.call("end_atomic_transaction", true)
	return true


func _protected_targets_met(state: NpcEconomyState) -> bool:
	for item_id in state.reserve_targets:
		if int(state.inventory.get(item_id, 0)) < int(state.reserve_targets[item_id]):
			return false
	return true


func _protected_quantity(state: NpcEconomyState, item_id: String) -> int:
	var profile: Dictionary = _profiles.get(state.npc_id, {})
	return maxi(
		int(state.reserve_targets.get(item_id, 0)),
		int((profile.get("essential_targets", {}) as Dictionary).get(item_id, 0))
	)


func _apply_population_demand(season_factors: Dictionary, event_factors: Dictionary) -> void:
	for profile in _population_profiles:
		var group_id := str(profile.id)
		var factor := _safe_factor(season_factors.get(group_id, 1.0))
		factor *= _safe_factor(event_factors.get(group_id, 1.0))
		factor = clampf(factor, FACTOR_MIN, FACTOR_MAX)
		var total_quantity := 0
		for item_id_value in (profile.demands as Dictionary).keys():
			var item_id := str(item_id_value)
			var quantity := roundi(int(profile.demands[item_id]) * factor)
			if quantity > 0 and bool(_market_system.call("add_external_demand", item_id, quantity)):
				total_quantity += quantity
		_demand_tags[group_id] = "%s（需求 %d）" % [str(profile.demand_tag), total_quantity]


func _update_shortages_and_imports(total_day: int) -> void:
	for item_id_value in _essential_zero_streaks.keys():
		var item_id := str(item_id_value)
		if int(_market_system.call("get_stock", item_id)) > 0:
			_essential_zero_streaks[item_id] = 0
			continue
		var streak := int(_essential_zero_streaks[item_id]) + 1
		_essential_zero_streaks[item_id] = streak
		if streak >= IMPORT_DAY_THRESHOLD and _import_essential(item_id, total_day):
			_essential_zero_streaks[item_id] = 0


func _import_essential(item_id: String, total_day: int) -> bool:
	var importer := _importer_state()
	if importer == null:
		return false
	var definition: Dictionary = _item_definitions.get(item_id, {})
	if definition.is_empty() or _is_rare_definition(definition):
		return false
	var state: Dictionary = _market_system.call("get_item_state", item_id)
	var quantity := mini(
		IMPORT_QUANTITY_CAP,
		mini(int(state.get("daily_liquidity", 0)), int(state.get("target_stock", 0)))
	)
	if quantity <= 0:
		return false
	var local_quote := int(_market_system.call("quote_buy", item_id, quantity))
	var import_cost := ceili(local_quote * IMPORT_COST_MULTIPLIER)
	if local_quote <= 0 or importer.gold < import_cost:
		return false
	if not bool(_market_system.call("commit_sell", item_id, quantity)):
		return false
	importer.gold -= import_cost
	_demand_tags["import:%s" % item_id] = "老李商队高价补货 %s ×%d（成本 %d）" % [
		str(definition.get("name", item_id)), quantity, import_cost,
	]
	if total_day < EconomyLimitsScript.MAX_SAFE_DATE:
		_pending_caravan_departures.append({
			"caravan_id": EMERGENCY_CARAVAN_ID,
			"item_id": item_id,
			"quantity": quantity,
			"departure_day": total_day + 1,
		})
	_emit_event("market_caravan_changed", [
		EMERGENCY_CARAVAN_ID, item_id, quantity, total_day, true,
	])
	return true


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	if _event_bus == null:
		_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if _event_bus != null and _event_bus.has_signal(signal_name):
		_event_bus.callv("emit_signal", [signal_name] + arguments)


func _importer_state() -> NpcEconomyState:
	for npc_id in _profiles:
		if bool((_profiles[npc_id] as Dictionary).get("import_buffer", false)):
			return _states[npc_id] as NpcEconomyState
	return null


func _market_definitions(market_system: Variant) -> Dictionary:
	var definitions: Dictionary = {}
	for definition in GameDataScript.get_market_items():
		var item_id := str(definition.get("id", ""))
		var market_state: Variant = market_system.call("get_item_state", item_id)
		if market_state is Dictionary and not (market_state as Dictionary).is_empty():
			definitions[item_id] = definition.duplicate(true)
	return definitions


func _essential_item_ids() -> Array[String]:
	var result: Array[String] = []
	for item_id_value in _item_definitions.keys():
		var item_id := str(item_id_value)
		var definition: Dictionary = _item_definitions[item_id]
		if str(definition.get("volatility", "")) == "essential" and not _is_rare_definition(definition):
			result.append(item_id)
	result.sort()
	return result


func _is_rare_definition(definition: Dictionary) -> bool:
	return (
		str(definition.get("category", "")) == "rare"
		or str(definition.get("volatility", "")) == "rare"
	)


func _normalize_npc_profile(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var profile: Dictionary = value
	for field in [
		"id", "display_name", "gold", "inventory", "essential_targets",
		"reserve_targets", "production_recipes", "sale_targets",
		"investment_gold_threshold", "import_buffer",
	]:
		if not profile.has(field):
			return {}
	if (
		typeof(profile.id) != TYPE_STRING
		or str(profile.id).is_empty()
		or typeof(profile.display_name) != TYPE_STRING
		or str(profile.display_name).is_empty()
		or not _is_nonnegative_integer(profile.gold)
		or not _is_nonnegative_integer(profile.investment_gold_threshold)
		or typeof(profile.import_buffer) != TYPE_BOOL
	):
		return {}
	var normalized_state := NpcEconomyStateScript.new()
	if not normalized_state.from_dict({
		"npc_id": profile.id,
		"gold": profile.gold,
		"inventory": profile.inventory,
		"reserve_targets": profile.reserve_targets,
		"production_recipes": profile.production_recipes,
		"sale_targets": profile.sale_targets,
		"last_simulated_day": 0,
		"investment_planned": false,
	}):
		return {}
	var essentials: Variant = _normalize_item_targets(profile.essential_targets)
	if essentials == null:
		return {}
	return {
		"id": str(profile.id),
		"display_name": str(profile.display_name),
		"gold": int(profile.gold),
		"inventory": normalized_state.inventory.duplicate(true),
		"essential_targets": essentials,
		"reserve_targets": normalized_state.reserve_targets.duplicate(true),
		"production_recipes": normalized_state.production_recipes.duplicate(),
		"sale_targets": normalized_state.sale_targets.duplicate(true),
		"investment_gold_threshold": int(profile.investment_gold_threshold),
		"import_buffer": bool(profile.import_buffer),
	}


func _normalize_population_profile(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var profile: Dictionary = value
	for field in ["id", "display_name", "demands", "demand_tag"]:
		if not profile.has(field):
			return {}
	if (
		typeof(profile.id) != TYPE_STRING
		or str(profile.id).is_empty()
		or typeof(profile.display_name) != TYPE_STRING
		or str(profile.display_name).is_empty()
		or typeof(profile.demand_tag) != TYPE_STRING
		or str(profile.demand_tag).is_empty()
	):
		return {}
	var demands: Variant = _normalize_item_targets(profile.demands)
	if demands == null or (demands as Dictionary).is_empty():
		return {}
	return {
		"id": str(profile.id),
		"display_name": str(profile.display_name),
		"demands": demands,
		"demand_tag": str(profile.demand_tag),
	}


func _normalize_item_targets(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var normalized: Dictionary = {}
	for item_key in (value as Dictionary).keys():
		if typeof(item_key) != TYPE_STRING or GameDataScript.get_item(str(item_key)) == null:
			return null
		var quantity: Variant = (value as Dictionary)[item_key]
		if not _is_nonnegative_integer(quantity):
			return null
		normalized[str(item_key)] = int(quantity)
	return normalized


func _normalize_streaks(value: Variant) -> Variant:
	if not value is Dictionary or (value as Dictionary).size() != _essential_zero_streaks.size():
		return null
	var normalized: Dictionary = {}
	for item_id in _essential_zero_streaks:
		if not (value as Dictionary).has(item_id) or not _is_nonnegative_integer((value as Dictionary)[item_id]):
			return null
		normalized[item_id] = int((value as Dictionary)[item_id])
	return normalized


func _normalize_tags(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var normalized: Dictionary = {}
	for tag_key in (value as Dictionary).keys():
		if typeof(tag_key) != TYPE_STRING or typeof((value as Dictionary)[tag_key]) != TYPE_STRING:
			return null
		if str(tag_key).is_empty() or str((value as Dictionary)[tag_key]).is_empty():
			return null
		normalized[str(tag_key)] = str((value as Dictionary)[tag_key])
	return normalized


func _normalize_pending_caravan_departures(value: Variant, cursor: int) -> Variant:
	if not value is Array:
		return null
	var normalized: Array[Dictionary] = []
	var occurrence_keys: Dictionary = {}
	for departure_value in value as Array:
		if not departure_value is Dictionary:
			return null
		var departure := departure_value as Dictionary
		if departure.size() != 4:
			return null
		for field in ["caravan_id", "item_id", "quantity", "departure_day"]:
			if not departure.has(field):
				return null
		if (
			typeof(departure.caravan_id) != TYPE_STRING
			or str(departure.caravan_id) != EMERGENCY_CARAVAN_ID
			or typeof(departure.item_id) != TYPE_STRING
			or not _item_definitions.has(str(departure.item_id))
			or not _is_nonnegative_integer(departure.quantity)
			or int(departure.quantity) <= 0
			or int(departure.quantity) > IMPORT_QUANTITY_CAP
			or not EconomyLimitsScript.is_safe_date(departure.departure_day, false)
			or cursor >= EconomyLimitsScript.MAX_SAFE_DATE
			or int(departure.departure_day) != cursor + 1
		):
			return null
		var definition: Dictionary = _item_definitions[str(departure.item_id)]
		if str(definition.get("volatility", "")) != "essential" or _is_rare_definition(definition):
			return null
		var occurrence_key := "%s\n%s\n%d" % [
			str(departure.caravan_id),
			str(departure.item_id),
			int(departure.departure_day),
		]
		if occurrence_keys.has(occurrence_key):
			return null
		occurrence_keys[occurrence_key] = true
		normalized.append({
			"caravan_id": str(departure.caravan_id),
			"item_id": str(departure.item_id),
			"quantity": int(departure.quantity),
			"departure_day": int(departure.departure_day),
		})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (
			str(a.caravan_id) < str(b.caravan_id)
			or (
				str(a.caravan_id) == str(b.caravan_id)
				and str(a.item_id) < str(b.item_id)
			)
		)
	)
	return normalized


func _safe_factor(value: Variant) -> float:
	if (
		(typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT)
		or not is_finite(float(value))
	):
		return 1.0
	return clampf(float(value), FACTOR_MIN, FACTOR_MAX)


func _has_methods(target: Variant, methods: Array[String]) -> bool:
	if target == null:
		return false
	for method_name in methods:
		if not target.has_method(method_name):
			return false
	return true


func _is_nonnegative_integer(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) >= 0
	)
