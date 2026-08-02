class_name BuildingStatusPanel
extends VBoxContainer

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MAX_REQUEST_QUANTITY := 2147483647


class ViewData:
	extends RefCounted
	var building_id := ""
	var kind := ""
	var title := ""
	var state := ""
	var fields: Dictionary = {}
	var storage: Dictionary = {}
	var actions: Array[String] = []


@onready var summary_fields: VBoxContainer = $SummaryFields
@onready var input_actions: VBoxContainer = $InputActions
@onready var storage_list: VBoxContainer = $StorageList
@onready var collect_all_button: Button = $Actions/CollectAllButton
@onready var range_preview_button: Button = $Actions/RangePreviewButton
@onready var feedback_label: Label = $FeedbackLabel

var view_data := ViewData.new()
var snapshot: Dictionary = {}
var failure_reason := ""
var failure_message := ""

var _production: ProductionSystem
var _inventory: InventorySystem
var _range_overlay: WorldRangeOverlay
var _building_ref: WeakRef
var _range_preview_enabled := false


func _ready() -> void:
	if not collect_all_button.pressed.is_connected(request_collect_all):
		collect_all_button.pressed.connect(request_collect_all)
	if not range_preview_button.toggled.is_connected(set_range_preview):
		range_preview_button.toggled.connect(set_range_preview)
	_render()


func configure(
	production: ProductionSystem,
	inventory: InventorySystem,
	range_overlay: WorldRangeOverlay
) -> bool:
	if production == null or inventory == null or range_overlay == null:
		return false
	_production = production
	_inventory = inventory
	_range_overlay = range_overlay
	_connect_event_bus()
	refresh_snapshot()
	return true


func show_building(building: BuildingInstance) -> void:
	if building != _building():
		set_range_preview(false)
	if building == null or not is_instance_valid(building):
		_building_ref = null
		view_data = ViewData.new()
		_render()
		return
	_building_ref = weakref(building)
	failure_reason = ""
	failure_message = ""
	refresh_snapshot()


func request_add_input(item_id: String, quantity: int) -> void:
	var building := _building()
	if building == null or _production == null or _inventory == null:
		_set_failure("not_configured", "建筑状态未连接")
		return
	if item_id.is_empty() or quantity <= 0 or quantity > MAX_REQUEST_QUANTITY:
		_set_failure("invalid_quantity", "数量必须为正整数")
		refresh_snapshot()
		return
	var available := _inventory.get_item_count(item_id)
	if available < quantity:
		_set_failure("missing_input", "缺少%s ×%d" % [_item_name(item_id), quantity - available])
		refresh_snapshot()
		return
	if not _production.add_input(building, item_id, quantity, _inventory):
		_set_failure("input_rejected", "建筑无法接收这些物品")
		refresh_snapshot()
		return
	_clear_failure()
	refresh_snapshot()


func request_collect_all() -> void:
	var building := _building()
	if building == null or _production == null or _inventory == null:
		_set_failure("not_configured", "建筑状态未连接")
		return
	var has_output := not view_data.storage.is_empty()
	if building.building_id == "barn":
		has_output = int(view_data.fields.get("pending_outputs", 0)) > 0
	if not has_output:
		_set_failure("nothing_to_collect", "暂无可收取产物")
		refresh_snapshot()
		return
	var succeeded := (
		_production.collect_nearby_outputs(building, _inventory)
		if building.building_id == "barn"
		else _production.collect_all(building, _inventory)
	)
	if not succeeded:
		_set_failure("inventory_capacity", "背包空间不足，未移动任何物品")
		refresh_snapshot()
		return
	_clear_failure()
	refresh_snapshot()


func set_range_preview(enabled: bool) -> void:
	var building := _building()
	_range_preview_enabled = enabled and building != null and building.building_id == "waterwheel"
	if _range_overlay != null:
		if _range_preview_enabled and _production != null:
			_range_overlay.show_cells(_production.get_irrigated_cells(building))
		else:
			_range_overlay.clear()
	if is_node_ready():
		range_preview_button.set_pressed_no_signal(_range_preview_enabled)


func refresh_snapshot() -> void:
	var building := _building()
	if building == null or _production == null:
		snapshot = {}
		view_data = ViewData.new()
		_render()
		return
	snapshot = _production.get_building_snapshot(building)
	view_data = _view_data_for(building)
	if _range_preview_enabled:
		set_range_preview(true)
	_render()


func _view_data_for(building: BuildingInstance) -> ViewData:
	var result := ViewData.new()
	result.building_id = building.building_id
	result.title = building.data.display_name if building.data != null else building.building_id
	result.state = "maintenance-paused" if bool(snapshot.get("maintenance_paused", false)) else "active"
	result.storage = (snapshot.get("outputs", {}) as Dictionary).duplicate(true)
	var config: Dictionary = building.data.effect_config if building.data != null else {}
	match building.building_id:
		"beehive":
			result.kind = "hive"
			var flowers := _production.count_nearby_mature_flowers(building)
			var cap := maxi(1, int(config.get("flower_cap", 4)))
			result.fields = {
				"next_output": _next_even_day(),
				"mature_flowers": flowers,
				"bonus": float(mini(flowers, cap)) / float(cap),
				"storage": result.storage.duplicate(true),
			}
			result.actions = ["collect"]
		"chicken_coop":
			result.kind = "coop"
			var feed_item := str(config.get("feed_item", "animal_feed"))
			var feed_stock := int((snapshot.get("inputs", {}) as Dictionary).get(feed_item, 0))
			var feed_per_day := maxi(1, int(config.get("feed_per_day", 1)))
			result.fields = {
				"animal_count": maxi(1, int(config.get("animal_count", 2))),
				"feed_item": feed_item,
				"feed_stock": feed_stock,
				"feed_days": feed_stock / feed_per_day,
				"daily_egg_output": int(_production.passive_output_for("chicken_coop", _production.get_current_day(), 0).get("egg", 0)),
				"storage": result.storage.duplicate(true),
			}
			result.actions = ["add_input", "collect"]
		"waterwheel":
			result.kind = "waterwheel"
			var irrigated := _production.get_irrigated_cells(building)
			result.fields = {
				"water_connected": _production.is_water_connected(building),
				"irrigation_radius": float(config.get("radius", 4)),
				"covered_farmland": irrigated.size(),
				"covered_greenhouses": _covered_greenhouses(),
				"range_cells": irrigated.duplicate(),
			}
			result.actions = ["range_preview"]
		"greenhouse":
			result.kind = "greenhouse"
			result.fields = {
				"planting_cells": int(config.get("planting_cells", _production.get_greenhouse_cells(building).size())),
				"water_connected": _production.is_greenhouse_water_connected(building),
				"season_protection": true,
				"crop_maturity_days": _greenhouse_crop_maturity(building),
				"waterwheel_connected": _production.is_greenhouse_water_connected(building),
				"planting_hint": "温室只提供环境，仍需播种",
			}
		"barn":
			result.kind = "barn"
			var nearby := _nearby_output_groups(building)
			result.fields = {
				"nearby_buildings": nearby.buildings,
				"pending_outputs": nearby.quantity,
				"total_capacity": _inventory.max_slots if _inventory != null else 0,
				"grouped_outputs": nearby.groups,
			}
			result.actions = ["collect"]
		"lumberyard", "quarry", "mine":
			result.kind = "resource"
			var quantity := 0
			for value in result.storage.values():
				quantity += int(value)
			result.fields = {
				"output_table": _resource_output_table(config),
				"next_settlement": _production.get_current_day() + 1,
				"maintenance": {"due_day": int(snapshot.get("maintenance_due_day", -1)), "paused": bool(snapshot.get("maintenance_paused", false))},
				"stored_capacity": {"used": quantity, "maximum": int(snapshot.get("storage_quantity_capacity", 0))},
			}
			if building.building_id == "mine":
				result.fields["depth_tier"] = str(config.get("depth_tier", "shallow"))
			result.actions = ["collect"]
	return result


func _render() -> void:
	if not is_node_ready():
		return
	_clear_container(summary_fields)
	for field_name in view_data.fields:
		if field_name in ["storage", "grouped_outputs", "range_cells"]:
			continue
		var label := Label.new()
		label.name = "%sLabel" % _pascal_case(str(field_name))
		label.text = "%s：%s" % [str(field_name), str(view_data.fields[field_name])]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary_fields.add_child(label)
	_clear_container(input_actions)
	if "add_input" in view_data.actions:
		var feed_item := str(view_data.fields.get("feed_item", "animal_feed"))
		for quantity in [1, 5, 10]:
			var button := Button.new()
			button.text = "补充%s ×%d" % [_item_name(feed_item), quantity]
			button.disabled = _inventory == null or _inventory.get_item_count(feed_item) < quantity
			button.pressed.connect(request_add_input.bind(feed_item, quantity))
			input_actions.add_child(button)
	_clear_container(storage_list)
	var ids: Array[String] = []
	ids.assign(view_data.storage.keys())
	ids.sort()
	for item_id in ids:
		var label := Label.new()
		label.text = "%s ×%d" % [_item_name(item_id), int(view_data.storage[item_id])]
		storage_list.add_child(label)
	collect_all_button.visible = "collect" in view_data.actions
	collect_all_button.disabled = view_data.storage.is_empty() and view_data.kind != "barn"
	range_preview_button.visible = "range_preview" in view_data.actions
	range_preview_button.set_pressed_no_signal(_range_preview_enabled)
	feedback_label.text = failure_message


func _next_even_day() -> int:
	var day := _production.get_current_day()
	return day + 2 if day % 2 == 0 else day + 1


func _covered_greenhouses() -> int:
	var count := 0
	for candidate in _production.get_registered_buildings():
		if candidate != null and candidate.building_id == "greenhouse" and _production.is_greenhouse_water_connected(candidate):
			count += 1
	return count


func _greenhouse_crop_maturity(_building: BuildingInstance) -> Dictionary:
	# Production owns crop timing; this field remains empty until a crop snapshot is available.
	return {}


func _nearby_output_groups(barn: BuildingInstance) -> Dictionary:
	var groups := {}
	var quantity := 0
	var count := 0
	var radius := float(barn.data.effect_config.get("collection_radius", 6)) if barn.data != null else 6.0
	var center := _building_center(barn)
	for candidate in _production.get_registered_buildings():
		if candidate == barn or candidate == null or _building_center(candidate).distance_to(center) > radius + 0.0001:
			continue
		var candidate_snapshot := _production.get_building_snapshot(candidate)
		var outputs: Dictionary = candidate_snapshot.get("outputs", {})
		if outputs.is_empty():
			continue
		count += 1
		groups[ProductionSystem.building_key(candidate)] = outputs.duplicate(true)
		for value in outputs.values():
			quantity += int(value)
	return {"buildings": count, "quantity": quantity, "groups": groups}


func _building_center(building: BuildingInstance) -> Vector2:
	var footprint := building.data.footprint if building != null and building.data != null else Vector2i.ONE
	return Vector2(float(building.grid_x) + float(footprint.x - 1) * 0.5, float(building.grid_z) + float(footprint.y - 1) * 0.5)


func _resource_output_table(config: Dictionary) -> Dictionary:
	if config.has("depth_outputs"):
		return (config.get("depth_outputs", {}) as Dictionary).duplicate(true)
	var result: Dictionary = (config.get("daily_output", {}) as Dictionary).duplicate(true)
	if config.has("bonus_output"):
		result["bonus"] = (config.get("bonus_output", {}) as Dictionary).duplicate(true)
	return result


func _set_failure(code: String, message: String) -> void:
	failure_reason = code
	failure_message = message
	var building := _building()
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if building != null and event_bus != null and event_bus.has_signal("building_economy_action_failed"):
		event_bus.building_economy_action_failed.emit(building, "status", code)


func _clear_failure() -> void:
	failure_reason = ""
	failure_message = ""


func _building() -> BuildingInstance:
	if _building_ref == null:
		return null
	var value = _building_ref.get_ref()
	return value as BuildingInstance if value != null and is_instance_valid(value) else null


func _item_name(item_id: String) -> String:
	var item = GameDataScript.get_item(item_id)
	return str(item.get("name", item_id)) if item != null else item_id


func _pascal_case(value: String) -> String:
	var result := ""
	for part in value.split("_", false):
		result += part.capitalize().replace(" ", "")
	return result


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _connect_event_bus() -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus == null:
		return
	for signal_name in ["production_job_completed", "production_output_blocked", "production_output_changed", "production_input_changed", "production_maintenance_changed", "item_added", "item_removed", "day_changed"]:
		var callback := Callable(self, "_on_economy_state_changed")
		if event_bus.has_signal(signal_name) and not event_bus.is_connected(signal_name, callback):
			event_bus.connect(signal_name, callback)


func _on_economy_state_changed(a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	var building := _building()
	if building == null:
		return
	if a is BuildingInstance and a != building:
		return
	refresh_snapshot()
