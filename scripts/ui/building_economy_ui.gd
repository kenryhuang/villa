class_name BuildingEconomyUI
extends Control

signal unlock_requested(service_id: String)

const PRODUCTION_BUILDINGS := [
	"windmill", "workbench", "stone_kiln", "furnace", "food_workshop", "textile_machine",
]
const STATUS_BUILDINGS := [
	"beehive", "chicken_coop", "waterwheel", "greenhouse", "barn", "lumberyard", "quarry", "mine", "well",
]
const EconomyLayoutScript = preload("res://scripts/ui/economy_layout.gd")
const OPEN_DURATION := 0.16

@onready var screen_layer: CanvasLayer = $ScreenLayer
@onready var modal_layer: ColorRect = $ScreenLayer/ModalLayer
@onready var building_panel: PanelContainer = $ScreenLayer/ModalLayer/BuildingPanel
@onready var title_label: Label = $ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/Header/TitleLabel
@onready var state_label: Label = $ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/Header/StateLabel
@onready var close_button: Button = $ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/Header/CloseButton
@onready var production_tab: Button = $ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/Tabs/ProductionTab
@onready var status_tab: Button = $ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/Tabs/StatusTab
@onready var production_panel: BuildingProductionPanel = $ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/PageHost/ProductionPanel
@onready var status_panel: BuildingStatusPanel = $ScreenLayer/ModalLayer/BuildingPanel/Margin/Shell/PageHost/StatusPanel
@onready var range_overlay: WorldRangeOverlay = $WorldRangeOverlay

var _production: ProductionSystem
var _inventory: InventorySystem
var _progression: EconomyProgressionSystem
var _grid: GridSystem
var _modal: EconomyModalCoordinator
var _building_ref: WeakRef
var _is_open := false
var animations_enabled := true
var _panel_tween: Tween


func _ready() -> void:
	add_to_group(EconomyLayoutScript.RESPONSIVE_GROUP)
	visible = false
	screen_layer.visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if not visibility_changed.is_connected(_sync_screen_layer_visibility):
		visibility_changed.connect(_sync_screen_layer_visibility)
	if not close_button.pressed.is_connected(close):
		close_button.pressed.connect(close)
	if not production_tab.pressed.is_connected(_on_production_tab_pressed):
		production_tab.pressed.connect(_on_production_tab_pressed)
	if not status_tab.pressed.is_connected(_on_status_tab_pressed):
		status_tab.pressed.connect(_on_status_tab_pressed)
	if not get_viewport().size_changed.is_connected(_apply_compact_rect):
		get_viewport().size_changed.connect(_apply_compact_rect)
	_apply_compact_rect()
	_connect_panel_signals()
	if is_configured():
		production_panel.configure(_production, _inventory, _progression)
		status_panel.configure(_production, _inventory, _progression, _grid, range_overlay)


static func panel_kind_for(building_id: String, effect_type: String) -> String:
	if building_id in PRODUCTION_BUILDINGS and effect_type == "crafting":
		return "production"
	if building_id in STATUS_BUILDINGS and effect_type in ["honey", "animal", "irrigation", "ignore_season", "farm_storage", "resource_output"]:
		return "status"
	return ""


func configure(
	production: ProductionSystem,
	inventory: InventorySystem,
	progression: EconomyProgressionSystem,
	grid: GridSystem,
	modal: EconomyModalCoordinator
) -> bool:
	if production == null or inventory == null or progression == null or grid == null or modal == null:
		return false
	_production = production
	_inventory = inventory
	_progression = progression
	_grid = grid
	_modal = modal
	if not is_node_ready():
		return true
	_connect_panel_signals()
	return production_panel.configure(production, inventory, progression) and status_panel.configure(production, inventory, progression, grid, range_overlay)


func open_for(building: BuildingInstance) -> bool:
	if not is_configured() or building == null or not is_instance_valid(building) or not building.is_construction_complete():
		return false
	var kind := panel_kind_for(building.building_id, building.economy_effect_type())
	if kind.is_empty():
		return false
	var previous := current_building()
	if previous != building:
		_disconnect_current_building()
		status_panel.set_range_preview(false)
		_building_ref = weakref(building)
		if not building.tree_exiting.is_connected(_on_current_building_tree_exiting):
			building.tree_exiting.connect(_on_current_building_tree_exiting)
	var was_closed := not _is_open
	if was_closed:
		if not _modal.acquire(self):
			return false
		_is_open = true
		visible = true
		screen_layer.visible = true
		_apply_compact_rect()
	title_label.text = building.data.display_name if building.data != null else building.building_id
	if kind == "production":
		production_panel.show_building(building)
	status_panel.show_building(building)
	var maintenance_state := _production.get_maintenance_state(building)
	var page_kind := "status" if maintenance_state != "normal" else kind
	_apply_page_kind(page_kind)
	if was_closed:
		_animate_open(building_panel)
	_emit_event("building_economy_opened", [building, kind])
	return true


func close() -> void:
	status_panel.set_range_preview(false)
	if not _is_open:
		return
	var building := current_building()
	_is_open = false
	_stop_transition()
	screen_layer.visible = false
	visible = false
	_disconnect_current_building()
	if _modal != null:
		_modal.release(self)
	_emit_event("building_economy_closed", [building])


func on_build_mode_entered() -> void:
	close()
	range_overlay.clear()


func is_open() -> bool:
	return _is_open


func is_configured() -> bool:
	return _production != null and _inventory != null and _progression != null and _grid != null and _modal != null


func current_building() -> BuildingInstance:
	if _building_ref == null:
		return null
	var value = _building_ref.get_ref()
	return value as BuildingInstance if value != null and is_instance_valid(value) else null


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if production_panel.visible and production_panel.handle_top_escape():
		get_viewport().set_input_as_handled()
		return
	close()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	range_overlay.clear()
	if _modal != null and _modal.is_owned_by(self):
		_modal.release(self)
	_is_open = false
	_disconnect_current_building()


func _on_current_building_tree_exiting() -> void:
	close()


func _disconnect_current_building() -> void:
	var building := current_building()
	if building != null and building.tree_exiting.is_connected(_on_current_building_tree_exiting):
		building.tree_exiting.disconnect(_on_current_building_tree_exiting)
	_building_ref = null


func _apply_compact_rect() -> void:
	if not is_node_ready():
		return
	var rect := EconomyLayoutScript.panel_rect_for(
		get_viewport_rect().size,
		EconomyLayoutScript.BUILDING_PANEL_MAX_SIZE
	)
	building_panel.position = rect.position
	building_panel.size = rect.size
	production_panel.apply_responsive_layout(
		EconomyLayoutScript.logical_size_for(rect.size, EconomyLayoutScript.get_ui_scale())
	)


func apply_economy_ui_scale(_ui_scale: float) -> void:
	_apply_compact_rect()


func _sync_screen_layer_visibility() -> void:
	if is_node_ready():
		screen_layer.visible = visible


func _apply_page_kind(kind: String) -> void:
	var building := current_building()
	var supports_production := (
		building != null
		and panel_kind_for(building.building_id, building.economy_effect_type()) == "production"
	)
	if kind == "production" and not supports_production:
		kind = "status"
	production_panel.visible = kind == "production"
	status_panel.visible = kind == "status"
	production_tab.button_pressed = kind == "production"
	status_tab.button_pressed = kind == "status"
	production_tab.disabled = not supports_production
	status_tab.disabled = false
	production_tab.theme_type_variation = (
		&"EconomyTabSelected" if kind == "production" else &"EconomyTab"
	)
	status_tab.theme_type_variation = (
		&"EconomyTabSelected" if kind == "status" else &"EconomyTab"
	)
	if kind == "production":
		production_panel.refresh_snapshot()
	else:
		status_panel.refresh_snapshot()
	state_label.text = (
		_production_state_text()
		if kind == "production"
		else _status_state_text(status_panel.view_data.state)
	)


func _on_production_tab_pressed() -> void:
	_apply_page_kind("production")


func _on_status_tab_pressed() -> void:
	_apply_page_kind("status")


func set_animations_enabled(enabled: bool) -> void:
	animations_enabled = enabled
	if not enabled:
		_stop_transition()
		if is_node_ready():
			building_panel.scale = Vector2.ONE
			building_panel.modulate.a = 1.0


func _animate_open(panel: Control) -> void:
	if not animations_enabled:
		panel.scale = Vector2.ONE
		panel.modulate.a = 1.0
		return
	_stop_transition()
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.985, 0.985)
	panel.modulate.a = 0.0
	_panel_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_panel_tween.set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(panel, "scale", Vector2.ONE, OPEN_DURATION)
	_panel_tween.tween_property(panel, "modulate:a", 1.0, OPEN_DURATION)


func _stop_transition() -> void:
	if _panel_tween != null:
		_panel_tween.kill()
		_panel_tween = null


func _production_state_text(state: String = "") -> String:
	var current_state := state
	if current_state.is_empty():
		current_state = str(production_panel.queue_slots[0].get("state", "idle")) if not production_panel.queue_slots.is_empty() else "idle"
	match current_state:
		"running": return "运行中"
		"waiting": return "等待中"
		"output-full": return "仓满暂停"
		"maintenance-paused": return "维护暂停"
		"completed-awaiting-storage": return "完成待入库"
	return "空闲"


func _status_state_text(state: String) -> String:
	return "维护暂停" if state == "maintenance-paused" else "运行中"


func _connect_panel_signals() -> void:
	var production_callback := Callable(self, "_on_production_snapshot_changed")
	if not production_panel.snapshot_changed.is_connected(production_callback):
		production_panel.snapshot_changed.connect(production_callback)
	var unlock_callback := Callable(self, "_on_unlock_requested")
	if not production_panel.unlock_requested.is_connected(unlock_callback):
		production_panel.unlock_requested.connect(unlock_callback)
	var status_callback := Callable(self, "_on_status_snapshot_changed")
	if not status_panel.snapshot_changed.is_connected(status_callback):
		status_panel.snapshot_changed.connect(status_callback)


func _on_production_snapshot_changed(state: String) -> void:
	if _is_open and production_panel.visible:
		state_label.text = _production_state_text(state)


func _on_status_snapshot_changed(state: String) -> void:
	if _is_open and status_panel.visible:
		state_label.text = _status_state_text(state)


func _on_unlock_requested(service_id: String) -> void:
	if not service_id.is_empty():
		unlock_requested.emit(service_id)


func _emit_event(signal_name: StringName, arguments: Array) -> void:
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus != null and event_bus.has_signal(signal_name):
		event_bus.emit_signal(signal_name, arguments[0], arguments[1]) if arguments.size() == 2 else event_bus.emit_signal(signal_name, arguments[0])
