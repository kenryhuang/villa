class_name BuildingProductionPanel
extends VBoxContainer

const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const EconomyLayoutScript = preload("res://scripts/ui/economy_layout.gd")
const MAX_UI_BATCHES := 9999
const DEFAULT_INPUT_CAPACITY := 99
const PROCESS_CARD_WIDTH := 520.0
const ACTIVITY_CARD_WIDTH := 300.0

signal snapshot_changed(state: String)
signal unlock_requested(service_id: String)

@onready var sections: HBoxContainer = $Sections
@onready var recipe_card: Control = $Sections/RecipeColumn
@onready var process_card: Control = $Sections/ProcessColumn
@onready var activity_card: Control = $Sections/RightColumn
@onready var recipe_list: VBoxContainer = $Sections/RecipeColumn/Content/RecipeScroll/RecipeList
@onready var queue_slots_container: VBoxContainer = $Sections/RightColumn/Content/QueueCard/QueueScroll/QueueSlots
@onready var storage_list: VBoxContainer = $Sections/RightColumn/Content/StorageCard/StorageList
@onready var storage_empty_label: Label = $Sections/RightColumn/Content/StorageCard/EmptyLabel
@onready var storage_capacity_label: Label = $Sections/RightColumn/Content/StorageCard/CapacityLabel
@onready var collect_all_button: Button = $Sections/RightColumn/Content/StorageCard/CollectAllButton
@onready var input_label: Label = $Sections/ProcessColumn/Content/Flow/InputItems/InputLabel
@onready var output_label: Label = $Sections/ProcessColumn/Content/Flow/OutputItems/OutputLabel
@onready var fuel_label: Label = $Sections/ProcessColumn/Content/Metrics/FuelLabel
@onready var duration_label: Label = $Sections/ProcessColumn/Content/Metrics/DurationLabel
@onready var pricing_label: Label = $Sections/ProcessColumn/Content/Metrics/PricingLabel
@onready var missing_label: Label = $Sections/ProcessColumn/Content/MissingLabel
@onready var batch_spin_box: SpinBox = $Sections/ProcessColumn/Content/BatchControls/BatchSpinBox
@onready var max_button: Button = $Sections/ProcessColumn/Content/BatchControls/MaxButton
@onready var start_button: Button = $Sections/ProcessColumn/Content/BatchControls/StartButton
@onready var narrow_detail_scroll: ScrollContainer = $NarrowDetailScroll
@onready var narrow_detail_stack: VBoxContainer = $NarrowDetailScroll/NarrowDetailStack
@onready var feedback_label: Label = $FeedbackLabel

var recipe_rows: Array[Dictionary] = []
var queue_slot_nodes: Array[PanelContainer] = []
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
var failure_message := ""
var _layout_mode := "three_column"
var _drawer_open := false
var _logical_layout_size := Vector2.ZERO

var _production: ProductionSystem
var _inventory: InventorySystem
var _progression: EconomyProgressionSystem
var _building_ref: WeakRef
var _selected_by_building: Dictionary = {}
var _snapshot_refresh_queued := false


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
	failure_reason = ""
	failure_message = ""
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
	open_details_drawer()


func apply_responsive_layout(logical_size: Vector2) -> void:
	_logical_layout_size = logical_size
	var next_mode: String = EconomyLayoutScript.mode_for_size(logical_size)
	if next_mode != _layout_mode:
		_layout_mode = next_mode
		if _layout_mode == "three_column":
			_drawer_open = false
	_apply_drawer_visibility()


func get_layout_mode() -> String:
	return _layout_mode


func open_details_drawer() -> void:
	if _layout_mode != "drawer":
		return
	_drawer_open = true
	_apply_drawer_visibility()
	if start_button != null and start_button.is_visible_in_tree():
		start_button.call_deferred("grab_focus")


func handle_top_escape() -> bool:
	if _layout_mode != "drawer" or not _drawer_open:
		return false
	_drawer_open = false
	_apply_drawer_visibility()
	return true


func _apply_drawer_visibility() -> void:
	if not is_node_ready():
		return
	if _layout_mode == "three_column":
		_restore_cards_to_sections()
		recipe_card.visible = true
		process_card.visible = true
		activity_card.visible = true
		return
	if not _drawer_open:
		_restore_cards_to_sections()
		recipe_card.visible = true
		process_card.visible = false
		activity_card.visible = false
		return
	if _logical_layout_size.x < EconomyLayoutScript.NARROW_STACK_BREAKPOINT:
		process_card.visible = true
		activity_card.visible = true
		_move_card(process_card, narrow_detail_stack)
		_move_card(activity_card, narrow_detail_stack)
		var process_height: float = process_card.get_combined_minimum_size().y
		var activity_height: float = activity_card.get_combined_minimum_size().y
		process_card.custom_minimum_size.x = 0.0
		activity_card.custom_minimum_size.x = 0.0
		process_card.custom_minimum_size.y = process_height
		activity_card.custom_minimum_size.y = activity_height
		process_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		activity_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		recipe_card.visible = false
		sections.visible = false
		narrow_detail_scroll.visible = true
	else:
		_restore_cards_to_sections()
		recipe_card.visible = false
		process_card.visible = true
		activity_card.visible = true


func _restore_cards_to_sections() -> void:
	_move_card(process_card, sections)
	_move_card(activity_card, sections)
	sections.move_child(process_card, 1)
	sections.move_child(activity_card, 2)
	process_card.custom_minimum_size.x = PROCESS_CARD_WIDTH
	activity_card.custom_minimum_size.x = ACTIVITY_CARD_WIDTH
	process_card.custom_minimum_size.y = 0.0
	activity_card.custom_minimum_size.y = 0.0
	process_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activity_card.size_flags_horizontal = Control.SIZE_FILL
	sections.visible = true
	narrow_detail_scroll.visible = false


func _move_card(card: Control, target: Container) -> void:
	if card.get_parent() == target:
		return
	card.reparent(target, false)


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
	failure_message = ""
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
	var result := _production.collect_outputs(building, _inventory)
	if not bool(result.get("ok", false)):
		_set_collection_failure(result, "collect_all")
		refresh_snapshot()
		return
	failure_reason = ""
	failure_message = ""
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
	var result := _production.collect_outputs(building, _inventory, item_id)
	if not bool(result.get("ok", false)):
		_set_collection_failure(result, "collect_item")
		refresh_snapshot()
		return
	failure_reason = ""
	failure_message = ""
	refresh_snapshot()


func refresh_snapshot() -> void:
	_snapshot_refresh_queued = false
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
	snapshot_changed.emit(str(queue_slots[0].get("state", "idle")) if not queue_slots.is_empty() else "idle")


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
			"unlock_service_id": "" if unlocked else _progression.get_recipe_service_id(str(recipe.id)),
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
	var maximum := maxi(int(snapshot.get("max_queue_slots", 2)), jobs.size())
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
		button.custom_minimum_size = Vector2(0.0, EconomyLayoutScript.LIST_ROW_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s  %s  %d分钟  %s" % [str(row.display_name), "可生产" if bool(row.materials_sufficient) else "缺材料", int(row.duration_minutes), _margin_status_text(str(row.margin_status))]
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.toggle_mode = true
		button.button_pressed = str(row.recipe_id) == selected_recipe_id
		button.disabled = false
		button.tooltip_text = str(row.lock_reason)
		button.pressed.connect(_on_recipe_pressed.bind(str(row.recipe_id)))
		recipe_list.add_child(button)
	_sync_queue_slot_nodes(queue_slots.size())
	for index in range(queue_slot_nodes.size()):
		var slot: Dictionary = queue_slots[index] if index < queue_slots.size() else {"state": "idle", "recipe_id": "", "batches": 0, "remaining_minutes": 0, "progress": 0.0}
		queue_slot_nodes[index].get_node("Content/Header/RecipeLabel").text = "空闲" if str(slot.state) == "idle" else "%s ×%d" % [str(slot.get("display_name", slot.recipe_id)), int(slot.batches)]
		queue_slot_nodes[index].get_node("Content/Header/StateLabel").text = _queue_state_text(str(slot.state))
		queue_slot_nodes[index].get_node("Content/Header/RemainingLabel").text = "剩余 %d 分钟" % int(slot.remaining_minutes)
		queue_slot_nodes[index].get_node("Content/ProgressBar").value = float(slot.progress) * 100.0
	_clear_container(storage_list)
	var ids: Array[String] = []
	ids.assign(storage.keys())
	ids.sort()
	for item_id in ids:
		var row := HBoxContainer.new()
		row.name = "Output_%s" % item_id
		row.custom_minimum_size = Vector2(0.0, EconomyLayoutScript.LIST_ROW_HEIGHT)
		var label := Label.new()
		label.name = "OutputLabel"
		label.text = "%s ×%d" % [_item_name(item_id), int(storage[item_id])]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var button := Button.new()
		button.name = "CollectButton"
		button.custom_minimum_size = Vector2(72.0, EconomyLayoutScript.CONTROL_HEIGHT)
		button.text = "收取"
		button.pressed.connect(request_collect_item.bind(item_id))
		row.add_child(label)
		row.add_child(button)
		storage_list.add_child(row)
	storage_empty_label.visible = storage.is_empty()
	var stored_quantity := 0
	for quantity in storage.values():
		stored_quantity += int(quantity)
	var quantity_capacity := int(snapshot.get("storage_quantity_capacity", 0))
	storage_capacity_label.text = (
		"容量 %d/%d" % [stored_quantity, quantity_capacity]
		if quantity_capacity > 0
		else "产物种类 %d/%d" % [storage.size(), int(snapshot.get("output_capacity", 0))]
	)
	collect_all_button.disabled = storage.is_empty()
	input_label.text = _count_text(recipe_detail.get("inputs", {}))
	output_label.text = _count_text(recipe_detail.get("outputs", {}))
	fuel_label.text = "无"
	duration_label.text = "%d 分钟" % int(recipe_detail.get("duration_minutes", 0))
	pricing_label.text = "投入 %d · 产出 %d · %s" % [int(recipe_detail.get("input_value", 0)), int(recipe_detail.get("output_value", 0)), _margin_status_text(str(recipe_detail.get("margin_status", "even")))]
	missing_label.text = disabled_reason
	batch_spin_box.max_value = maxi(1, max_batches)
	batch_spin_box.set_value_no_signal(batches)
	max_button.disabled = max_batches <= 0
	start_button.disabled = not bool(preflight.get("ok", false))
	start_button.tooltip_text = disabled_reason
	feedback_label.text = failure_message


func _queue_state_text(state: String) -> String:
	return {
		"idle": "空闲",
		"waiting": "等待中",
		"running": "生产中",
		"completed-awaiting-storage": "等待入库",
		"output-full": "产物已满",
		"maintenance-paused": "维护暂停",
	}.get(state, "状态未知")


func _margin_status_text(status: String) -> String:
	return {"profit": "盈利", "even": "持平", "loss": "亏损"}.get(status, "持平")


func _sync_queue_slot_nodes(target_count: int) -> void:
	while queue_slot_nodes.size() > target_count:
		var stale: PanelContainer = queue_slot_nodes.pop_back()
		queue_slots_container.remove_child(stale)
		stale.free()
	while queue_slot_nodes.size() < target_count:
		var slot: PanelContainer = _create_queue_slot_node(queue_slot_nodes.size())
		queue_slot_nodes.append(slot)
		queue_slots_container.add_child(slot)


func _create_queue_slot_node(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Slot%d" % (index + 1)
	slot.custom_minimum_size = Vector2(0, EconomyLayoutScript.LIST_ROW_HEIGHT)
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color("#FFF7E6")
	slot_style.corner_radius_top_left = 10
	slot_style.corner_radius_top_right = 10
	slot_style.corner_radius_bottom_left = 10
	slot_style.corner_radius_bottom_right = 10
	slot_style.content_margin_left = 10.0
	slot_style.content_margin_top = 4.0
	slot_style.content_margin_right = 10.0
	slot_style.content_margin_bottom = 4.0
	slot.add_theme_stylebox_override("panel", slot_style)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 4)
	slot.add_child(content)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)
	var recipe_label := Label.new()
	recipe_label.name = "RecipeLabel"
	recipe_label.text = "空闲"
	recipe_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_label.clip_text = true
	recipe_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var state_label := Label.new()
	state_label.name = "StateLabel"
	state_label.text = "idle"
	state_label.add_theme_color_override("font_color", Color("#5F8755"))
	var remaining_label := Label.new()
	remaining_label.name = "RemainingLabel"
	remaining_label.text = "剩余 0 分钟"
	var progress_bar := ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.custom_minimum_size = Vector2(0.0, 8.0)
	progress_bar.show_percentage = false
	header.add_child(recipe_label)
	header.add_child(state_label)
	header.add_child(remaining_label)
	content.add_child(progress_bar)
	return slot


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
	snapshot_changed.emit("idle")


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


func _on_recipe_pressed(recipe_id: String) -> void:
	if _progression == null or _progression.is_recipe_unlocked(recipe_id):
		select_recipe(recipe_id)
		return
	var service_id := _progression.get_recipe_service_id(recipe_id)
	if not service_id.is_empty():
		unlock_requested.emit(service_id)


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
		child.queue_free()


func _set_failure(code: String, action: String) -> void:
	failure_reason = code
	failure_message = _reason_text(preflight) if action == "start" and not preflight.is_empty() else "操作失败：%s" % code
	var building := _building()
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if building != null and event_bus != null and event_bus.has_signal("building_economy_action_failed"):
		event_bus.building_economy_action_failed.emit(building, action, code)


func _set_collection_failure(result: Dictionary, action: String) -> void:
	var code := str(result.get("reason", "transaction_failed"))
	_set_failure(code, action)
	if code != "inventory_capacity":
		failure_message = "暂无可收取产物" if code == "nothing_to_collect" else "收取条件已变化，未移动任何物品"
		return
	var missing: Dictionary = result.get("missing", {})
	var ids: Array[String] = []
	ids.assign(missing.keys())
	ids.sort()
	var parts: Array[String] = []
	for item_id in ids:
		parts.append("%s ×%d" % [_item_name(item_id), int(missing[item_id])])
	failure_message = "背包还需%d格空间，无法容纳%s" % [int(result.get("missing_slots", 0)), "、".join(parts)]


func _connect_event_bus() -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus == null:
		return
	for signal_name in ["production_job_started", "production_job_completed", "production_output_blocked", "production_output_changed", "production_input_changed", "production_maintenance_changed", "item_added", "item_removed", "day_changed"]:
		var callback := Callable(self, "_on_economy_state_changed")
		if event_bus.has_signal(signal_name) and not event_bus.is_connected(signal_name, callback):
			event_bus.connect(signal_name, callback)


func _on_economy_state_changed(a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	var building := _building()
	if building == null:
		return
	if a is BuildingInstance and a != building:
		return
	_queue_snapshot_refresh()


func _queue_snapshot_refresh() -> void:
	if not is_visible_in_tree() or _snapshot_refresh_queued:
		return
	_snapshot_refresh_queued = true
	call_deferred("_flush_snapshot_refresh")


func _flush_snapshot_refresh() -> void:
	if not _snapshot_refresh_queued:
		return
	_snapshot_refresh_queued = false
	if is_visible_in_tree():
		refresh_snapshot()
