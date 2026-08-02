class_name BuildingProductionPanel
extends VBoxContainer

const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MAX_UI_BATCHES := 9999
const DEFAULT_INPUT_CAPACITY := 99

@onready var recipe_list: VBoxContainer = $ThreeColumns/RecipeColumn/RecipeList
@onready var queue_slot_nodes := [
	$ThreeColumns/QueueColumn/QueueSlots/Slot1,
	$ThreeColumns/QueueColumn/QueueSlots/Slot2,
]
@onready var storage_list: VBoxContainer = $ThreeColumns/StorageColumn/StorageList
@onready var storage_empty_label: Label = $ThreeColumns/StorageColumn/EmptyLabel
@onready var storage_capacity_label: Label = $ThreeColumns/StorageColumn/CapacityLabel
@onready var collect_all_button: Button = $ThreeColumns/StorageColumn/CollectAllButton
@onready var input_label: Label = $RecipeDetails/InputLabel
@onready var output_label: Label = $RecipeDetails/OutputLabel
@onready var fuel_label: Label = $RecipeDetails/FuelLabel
@onready var duration_label: Label = $RecipeDetails/DurationLabel
@onready var pricing_label: Label = $RecipeDetails/PricingLabel
@onready var missing_label: Label = $RecipeDetails/MissingLabel
@onready var batch_spin_box: SpinBox = $RecipeDetails/BatchControls/BatchSpinBox
@onready var max_button: Button = $RecipeDetails/BatchControls/MaxButton
@onready var start_button: Button = $RecipeDetails/BatchControls/StartButton

var recipe_rows: Array[Dictionary] = []
var recipe_detail: Dictionary = {}
var queue_slots: Array[Dictionary] = []
var storage: Dictionary = {}
var snapshot: Dictionary = {}
var preflight: Dictionary = {}
var selected_recipe_id := ""
var batches := 1
var max_batches := 0
var disabled_reason := ""
var failure_reason := ""

var _production: ProductionSystem
var _inventory: InventorySystem
var _progression: EconomyProgressionSystem
var _building_ref: WeakRef
var _selected_by_building: Dictionary = {}


func _ready() -> void:
	if not collect_all_button.pressed.is_connected(request_collect_all):
		collect_all_button.pressed.connect(request_collect_all)
	if not max_button.pressed.is_connected(_select_max_batches):
		max_button.pressed.connect(_select_max_batches)
	if not start_button.pressed.is_connected(request_start):
		start_button.pressed.connect(request_start)
	if not batch_spin_box.value_changed.is_connected(_on_batch_value_changed):
		batch_spin_box.value_changed.connect(_on_batch_value_changed)
	_render()


func configure(
	production: ProductionSystem,
	inventory: InventorySystem,
	progression: EconomyProgressionSystem
) -> bool:
	if production == null or inventory == null or progression == null:
		return false
	_production = production
	_inventory = inventory
	_progression = progression
	_connect_event_bus()
	refresh_snapshot()
	return true


func show_building(building: BuildingInstance) -> void:
	if building == null or not is_instance_valid(building):
		_clear_view()
		return
	_building_ref = weakref(building)
	batches = 1
	var recipes := RecipeDatabaseScript.get_recipes_for_station(building.building_id)
	var remembered := str(_selected_by_building.get(_building_key(building), ""))
	selected_recipe_id = remembered if recipes.any(func(recipe: Dictionary) -> bool: return str(recipe.id) == remembered) else (str(recipes[0].id) if not recipes.is_empty() else "")
	refresh_snapshot()


func select_recipe(recipe_id: String) -> void:
	var building := _building()
	if building == null:
		return
	var recipe := RecipeDatabaseScript.get_recipe(recipe_id)
	if recipe.is_empty() or str(recipe.get("station", "")) != building.building_id:
		return
	selected_recipe_id = recipe_id
	_selected_by_building[_building_key(building)] = recipe_id
	batches = 1
	refresh_snapshot()


func set_batches(next_batches: int) -> void:
	if max_batches <= 0:
		batches = clampi(next_batches, 1, MAX_UI_BATCHES)
	else:
		batches = clampi(next_batches, 1, max_batches)
	refresh_snapshot()


func request_start() -> void:
	var building := _building()
	if building == null or _production == null or _inventory == null:
		_set_failure("not_configured", "start")
		return
	preflight = _production.preflight_recipe(building, selected_recipe_id, batches, _inventory)
	if not bool(preflight.get("ok", false)):
		_set_failure(str(preflight.get("reason", "invalid_request")), "start")
		refresh_snapshot()
		return
	if not _production.start_recipe(building, selected_recipe_id, batches, _inventory):
		_set_failure("transaction_failed", "start")
		refresh_snapshot()
		return
	failure_reason = ""
	refresh_snapshot()


func request_collect_all() -> void:
	var building := _building()
	if building == null or _production == null or _inventory == null:
		_set_failure("not_configured", "collect_all")
		return
	if storage.is_empty():
		_set_failure("nothing_to_collect", "collect_all")
		refresh_snapshot()
		return
	if not _production.collect_all(building, _inventory):
		_set_failure("inventory_capacity", "collect_all")
		refresh_snapshot()
		return
	failure_reason = ""
	refresh_snapshot()


func request_collect_item(item_id: String) -> void:
	var building := _building()
	if building == null or _production == null or _inventory == null:
		_set_failure("not_configured", "collect_item")
		return
	if int(storage.get(item_id, 0)) <= 0:
		_set_failure("nothing_to_collect", "collect_item")
		refresh_snapshot()
		return
	if not _production.collect_item(building, item_id, _inventory):
		_set_failure("inventory_capacity", "collect_item")
		refresh_snapshot()
		return
	failure_reason = ""
	refresh_snapshot()


func refresh_snapshot() -> void:
	var building := _building()
	if building == null or _production == null or _inventory == null:
		_clear_view()
		return
	snapshot = _production.get_building_snapshot(building)
	storage = (snapshot.get("outputs", {}) as Dictionary).duplicate(true)
	_build_recipe_rows(building)
	_build_recipe_detail(building)
	_build_queue_slots()
	_render()


func _build_recipe_rows(building: BuildingInstance) -> void:
	recipe_rows.clear()
	var recipes := RecipeDatabaseScript.get_recipes_for_station(building.building_id)
	recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	for recipe in recipes:
		var unlocked := _progression.is_recipe_unlocked(str(recipe.id)) if _progression != null else true
		var missing := {}
		for item_id in recipe.inputs:
			var shortfall := int(recipe.inputs[item_id]) - _inventory.get_item_count(str(item_id))
			if shortfall > 0:
				missing[item_id] = shortfall
		var pricing := _pricing(recipe, 1)
		recipe_rows.append({
			"recipe_id": str(recipe.id),
			"display_name": str(recipe.display_name),
			"unlocked": unlocked,
			"lock_reason": "" if unlocked else "需要解锁%s配方" % str(recipe.display_name),
			"materials_sufficient": missing.is_empty(),
			"missing": missing,
			"duration_minutes": int(recipe.duration_minutes),
			"margin": pricing.margin,
			"margin_status": pricing.status,
		})


func _build_recipe_detail(building: BuildingInstance) -> void:
	var recipe := RecipeDatabaseScript.get_recipe(selected_recipe_id)
	if recipe.is_empty():
		recipe_detail = {}
		preflight = {}
		max_batches = 0
		disabled_reason = "选择左侧配方开始生产"
		return
	max_batches = _maximum_batches(building, recipe)
	if max_batches > 0:
		batches = clampi(batches, 1, max_batches)
	else:
		batches = clampi(batches, 1, MAX_UI_BATCHES)
	preflight = _production.preflight_recipe(building, selected_recipe_id, batches, _inventory)
	var pricing := _pricing(recipe, batches)
	recipe_detail = {
		"recipe_id": selected_recipe_id,
		"inputs": _multiply(recipe.inputs, batches),
		"outputs": _multiply(recipe.outputs, batches),
		"fuel": {},
		"duration_minutes": int(recipe.duration_minutes) * batches,
		"input_value": pricing.input_value,
		"output_value": pricing.output_value,
		"margin": pricing.margin,
		"margin_status": pricing.status,
	}
	disabled_reason = _reason_text(preflight)


func _build_queue_slots() -> void:
	queue_slots.clear()
	var jobs: Array = snapshot.get("jobs", [])
	var maximum := 2
	for index in range(maximum):
		if index >= jobs.size():
			queue_slots.append({"state": "idle", "recipe_id": "", "batches": 0, "remaining_minutes": 0, "progress": 0.0})
			continue
		var job: Dictionary = jobs[index]
		var recipe := RecipeDatabaseScript.get_recipe(str(job.get("recipe_id", "")))
		var total := maxi(1, int(recipe.get("duration_minutes", 1)) * int(job.get("batches", 1)))
		var remaining := maxi(0, int(job.get("remaining_minutes", 0)))
		queue_slots.append({
			"state": _queue_state(job, index),
			"recipe_id": str(job.get("recipe_id", "")),
			"display_name": str(recipe.get("display_name", job.get("recipe_id", ""))),
			"batches": int(job.get("batches", 1)),
			"remaining_minutes": remaining,
			"progress": clampf(1.0 - float(remaining) / float(total), 0.0, 1.0),
		})
	while queue_slots.size() < 2:
		queue_slots.append({"state": "idle", "recipe_id": "", "batches": 0, "remaining_minutes": 0, "progress": 0.0})


func _queue_state(job: Dictionary, index: int) -> String:
	var status := str(job.get("status", "queued"))
	if status == "maintenance_paused" or bool(snapshot.get("maintenance_paused", false)) and index == 0:
		return "maintenance-paused"
	if status == "output_full":
		return "output-full"
	if int(job.get("remaining_minutes", 0)) <= 0:
		return "completed-awaiting-storage"
	if status == "running":
		return "running"
	return "waiting"


func _maximum_batches(building: BuildingInstance, recipe: Dictionary) -> int:
	if not _progression.is_recipe_unlocked(str(recipe.id)):
		return 0
	var queue_free := int(snapshot.get("max_queue_slots", 2)) - (snapshot.get("jobs", []) as Array).size()
	if queue_free <= 0:
		return 0
	var inventory_limit := MAX_UI_BATCHES
	for item_id in recipe.inputs:
		var quantity := int(recipe.inputs[item_id])
		if quantity <= 0:
			return 0
		inventory_limit = mini(inventory_limit, _inventory.get_item_count(str(item_id)) / quantity)
	var input_capacity := DEFAULT_INPUT_CAPACITY
	if building.data != null:
		input_capacity = maxi(1, int(building.data.effect_config.get("input_capacity", DEFAULT_INPUT_CAPACITY)))
	var per_batch := 0
	for quantity in recipe.inputs.values():
		per_batch += int(quantity)
	var capacity_limit := input_capacity / maxi(1, per_batch)
	return clampi(mini(inventory_limit, capacity_limit), 0, MAX_UI_BATCHES)


func _pricing(recipe: Dictionary, multiplier: int) -> Dictionary:
	var input_value := 0
	for item_id in recipe.inputs:
		var item = GameDataScript.get_item(str(item_id))
		input_value += int(recipe.inputs[item_id]) * multiplier * int(item.get("base_price", item.get("buy_price", 0)))
	var output_value := 0
	for item_id in recipe.outputs:
		var item = GameDataScript.get_item(str(item_id))
		output_value += int(recipe.outputs[item_id]) * multiplier * int(item.get("base_price", item.get("sell_price", 0)))
	var margin := output_value - input_value
	return {"input_value": input_value, "output_value": output_value, "margin": margin, "status": "profit" if margin > 0 else ("loss" if margin < 0 else "even")}


func _reason_text(result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return ""
	match str(result.get("reason", "invalid_request")):
		"missing_inputs":
			var parts: Array[String] = []
			var missing: Dictionary = result.get("missing", {})
			var ids: Array[String] = []
			ids.assign(missing.keys())
			ids.sort()
			for item_id in ids:
				parts.append("缺少%s ×%d" % [_item_name(item_id), int(missing[item_id])])
			return "，".join(parts)
		"recipe_locked": return "配方尚未解锁"
		"queue_full": return "生产队列已满"
		"maintenance_overdue": return "建筑维护已到期"
		"building_incomplete": return "建筑尚未完工"
	return "生产条件已变化，请重试"


func _render() -> void:
	if not is_node_ready():
		return
	_clear_container(recipe_list)
	for row in recipe_rows:
		var button := Button.new()
		button.name = "Recipe_%s" % str(row.recipe_id)
		button.text = "%s  %s  %d分钟  %s" % [str(row.display_name), "可生产" if bool(row.materials_sufficient) else "缺材料", int(row.duration_minutes), str(row.margin_status)]
		button.toggle_mode = true
		button.button_pressed = str(row.recipe_id) == selected_recipe_id
		button.disabled = not bool(row.unlocked)
		button.tooltip_text = str(row.lock_reason)
		button.pressed.connect(select_recipe.bind(str(row.recipe_id)))
		recipe_list.add_child(button)
	for index in range(queue_slot_nodes.size()):
		var slot: Dictionary = queue_slots[index] if index < queue_slots.size() else {"state": "idle", "recipe_id": "", "batches": 0, "remaining_minutes": 0, "progress": 0.0}
		queue_slot_nodes[index].get_node("RecipeLabel").text = "空闲" if str(slot.state) == "idle" else "%s ×%d" % [str(slot.get("display_name", slot.recipe_id)), int(slot.batches)]
		queue_slot_nodes[index].get_node("StateLabel").text = str(slot.state)
		queue_slot_nodes[index].get_node("RemainingLabel").text = "剩余 %d 分钟" % int(slot.remaining_minutes)
		queue_slot_nodes[index].get_node("ProgressBar").value = float(slot.progress) * 100.0
	_clear_container(storage_list)
	var ids: Array[String] = []
	ids.assign(storage.keys())
	ids.sort()
	for item_id in ids:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s ×%d" % [_item_name(item_id), int(storage[item_id])]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := Button.new()
		button.text = "收取"
		button.pressed.connect(request_collect_item.bind(item_id))
		row.add_child(label)
		row.add_child(button)
		storage_list.add_child(row)
	storage_empty_label.visible = storage.is_empty()
	var stored_quantity := 0
	for quantity in storage.values():
		stored_quantity += int(quantity)
	storage_capacity_label.text = "容量 %d/%d" % [stored_quantity, int(snapshot.get("storage_quantity_capacity", snapshot.get("output_capacity", 0)))]
	collect_all_button.disabled = storage.is_empty()
	input_label.text = "投入：%s" % _count_text(recipe_detail.get("inputs", {}))
	output_label.text = "产出：%s" % _count_text(recipe_detail.get("outputs", {}))
	fuel_label.text = "燃料：无"
	duration_label.text = "耗时：%d 分钟" % int(recipe_detail.get("duration_minutes", 0))
	pricing_label.text = "投入现值 %d　产出参考价 %d　预计%s" % [int(recipe_detail.get("input_value", 0)), int(recipe_detail.get("output_value", 0)), str(recipe_detail.get("margin_status", "even"))]
	missing_label.text = disabled_reason
	batch_spin_box.max_value = maxi(1, max_batches)
	batch_spin_box.set_value_no_signal(batches)
	max_button.disabled = max_batches <= 0
	start_button.disabled = not bool(preflight.get("ok", false))
	start_button.tooltip_text = disabled_reason


func _clear_view() -> void:
	snapshot = {}
	recipe_rows.clear()
	recipe_detail = {}
	queue_slots.clear()
	storage = {}
	preflight = {}
	selected_recipe_id = ""
	batches = 1
	max_batches = 0
	disabled_reason = "选择左侧配方开始生产"
	_render()


func _building() -> BuildingInstance:
	if _building_ref == null:
		return null
	var value = _building_ref.get_ref()
	return value as BuildingInstance if value != null and is_instance_valid(value) else null


func _building_key(building: BuildingInstance) -> String:
	return "%s:%d:%d" % [building.building_id, building.grid_x, building.grid_z]


func _select_max_batches() -> void:
	set_batches(max_batches)


func _on_batch_value_changed(value: float) -> void:
	set_batches(int(value))


func _multiply(source: Dictionary, multiplier: int) -> Dictionary:
	var result := {}
	for item_id in source:
		result[item_id] = int(source[item_id]) * multiplier
	return result


func _item_name(item_id: String) -> String:
	var item = GameDataScript.get_item(item_id)
	return str(item.get("name", item_id)) if item != null else item_id


func _count_text(counts: Dictionary) -> String:
	if counts.is_empty():
		return "无"
	var ids: Array[String] = []
	ids.assign(counts.keys())
	ids.sort()
	var parts: Array[String] = []
	for item_id in ids:
		parts.append("%s ×%d" % [_item_name(item_id), int(counts[item_id])])
	return "，".join(parts)


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _set_failure(code: String, action: String) -> void:
	failure_reason = code
	var building := _building()
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if building != null and event_bus != null and event_bus.has_signal("building_economy_action_failed"):
		event_bus.building_economy_action_failed.emit(building, action, code)


func _connect_event_bus() -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus == null:
		return
	for signal_name in ["production_job_started", "production_job_completed", "production_output_blocked", "production_output_changed", "production_input_changed", "production_maintenance_changed", "item_added", "item_removed"]:
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
