class_name DailySimulationSystem
extends Node

var last_simulated_day: int = 0

var _production_system: Variant
var _farming_system: Variant
var _npc_economy_system: Variant
var _economy_system: Variant
var _market_system: Variant
var _save_manager: Variant
var _resource_system: Variant
var _event_bus: Node
var _is_configured := false


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	_connect_day_changed()


func configure(
	production_system: Variant,
	farming_system: Variant,
	npc_economy_system: Variant,
	economy_system: Variant,
	market_system: Variant,
	save_manager: Variant,
	resource_system: Variant = null
) -> bool:
	if not _has_methods(farming_system, ["on_day_changed"]):
		return false
	if not _has_methods(economy_system, ["advance_order_deadlines", "generate_demand_orders"]):
		return false
	if not _has_methods(market_system, ["can_settle_day", "settle_day"]):
		return false
	if not _is_market_state_ready(market_system):
		return false
	if not _has_methods(save_manager, ["save_game"]) or not _has_property(save_manager, "current_slot"):
		return false
	if production_system != null and not _has_methods(
		production_system,
		["begin_day", "apply_daily_effects", "finish_daily_outputs"]
	):
		return false
	if npc_economy_system != null and not _has_methods(npc_economy_system, ["simulate_day"]):
		return false
	if resource_system != null and not _has_methods(resource_system, ["advance_resource_day"]):
		return false
	_production_system = production_system
	_farming_system = farming_system
	_npc_economy_system = npc_economy_system
	_economy_system = economy_system
	_market_system = market_system
	_save_manager = save_manager
	_resource_system = resource_system
	_is_configured = true
	if is_inside_tree():
		_event_bus = get_node_or_null("/root/EventBus")
		_connect_day_changed()
	return true


func run_day(day: int) -> bool:
	if not _is_configured or day != last_simulated_day + 1:
		return false
	if not _market_cursor_is_coherent():
		return false
	if not bool(_market_system.call("can_settle_day", day)):
		return false
	if _production_system != null:
		if not bool(_production_system.call("begin_day", day)):
			return false
		_production_system.call("apply_daily_effects", day)
	_farming_system.call("on_day_changed", day)
	if _production_system != null:
		_production_system.call("finish_daily_outputs", day)
	if _npc_economy_system != null:
		_npc_economy_system.call("simulate_day", day)
	_economy_system.call("advance_order_deadlines", day)
	var settlement_result: Variant = _market_system.call("settle_day", day)
	if settlement_result is bool and not settlement_result:
		return false
	_economy_system.call("generate_demand_orders", day)
	if _resource_system != null:
		_resource_system.call("advance_resource_day", day)
	last_simulated_day = day
	_save_manager.call("save_game", int(_save_manager.get("current_slot")))
	return true


func _on_day_changed(day: int) -> void:
	run_day(day)


func _connect_day_changed() -> void:
	if not _is_configured or _event_bus == null or not _event_bus.has_signal("day_changed"):
		return
	var callback := Callable(self, "_on_day_changed")
	if not _event_bus.is_connected("day_changed", callback):
		_event_bus.connect("day_changed", callback)


func _has_methods(target: Variant, methods: Array[String]) -> bool:
	if target == null:
		return false
	for method_name in methods:
		if not target.has_method(method_name):
			return false
	return true


func _has_property(target: Variant, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _is_market_state_ready(market_system: Variant) -> bool:
	if not market_system.has_method("to_dict"):
		return true
	var state: Variant = market_system.call("to_dict")
	if not state is Dictionary:
		return false
	var items: Variant = state.get("items", null)
	return items is Dictionary and not items.is_empty()


func _market_cursor_is_coherent() -> bool:
	if not _has_property(_market_system, "last_settled_day"):
		return true
	var market_day: Variant = _market_system.get("last_settled_day")
	return (
		(typeof(market_day) == TYPE_INT or typeof(market_day) == TYPE_FLOAT)
		and is_finite(float(market_day))
		and floorf(float(market_day)) == float(market_day)
		and int(market_day) == last_simulated_day
	)
