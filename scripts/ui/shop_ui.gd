class_name ShopUI
extends Control

const VALID_TABS := ["market", "orders", "contracts", "services"]
const EconomyModalCoordinatorScript = preload(
	"res://scripts/ui/economy_modal_coordinator.gd"
)
const MarketPanelScript = preload("res://scripts/ui/market_panel.gd")

@onready var modal_layer: ColorRect = $ModalLayer
@onready var header_gold_label: Label = $ModalLayer/HubPanel/Margin/Shell/Header/GoldLabel
@onready var date_label: Label = $ModalLayer/HubPanel/Margin/Shell/Header/DateLabel
@onready var market_status_label: Label = $ModalLayer/HubPanel/Margin/Shell/Header/MarketStatusLabel
@onready var close_button: Button = $ModalLayer/HubPanel/Margin/Shell/Header/CloseButton
@onready var tab_buttons := {
	"market": $ModalLayer/HubPanel/Margin/Shell/Tabs/MarketTab,
	"orders": $ModalLayer/HubPanel/Margin/Shell/Tabs/OrdersTab,
	"contracts": $ModalLayer/HubPanel/Margin/Shell/Tabs/ContractsTab,
	"services": $ModalLayer/HubPanel/Margin/Shell/Tabs/ServicesTab,
}
@onready var pages := {
	"market": $ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel,
	"orders": $ModalLayer/HubPanel/Margin/Shell/PageHost/OrdersPage,
	"contracts": $ModalLayer/HubPanel/Margin/Shell/PageHost/ContractsPage,
	"services": $ModalLayer/HubPanel/Margin/Shell/PageHost/ServicesPage,
}
@onready var market_panel = $ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel
@onready var service_panel = $ModalLayer/HubPanel/Margin/Shell/PageHost/ServicesPage

var selected_tab := "market"
var _is_open := false
var _has_opened := false
var _inventory_ref: InventorySystem
var _economy_ref: EconomySystem
var _market_ref: MarketSystem
var _modal_coordinator = EconomyModalCoordinatorScript.new()


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	for tab_id in tab_buttons:
		tab_buttons[tab_id].pressed.connect(select_tab.bind(tab_id))
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		if not event_bus.gold_changed.is_connected(_on_gold_changed):
			event_bus.gold_changed.connect(_on_gold_changed)
		if not event_bus.day_changed.is_connected(_on_day_changed):
			event_bus.day_changed.connect(_on_day_changed)
	select_tab(selected_tab)


func configure(
	inventory: InventorySystem,
	economy: EconomySystem,
	market: MarketSystem,
	progression: EconomyProgressionSystem = null,
	tool_system: ToolSystem = null,
	production: ProductionSystem = null
) -> bool:
	_inventory_ref = inventory
	_economy_ref = economy
	_market_ref = market
	if _inventory_ref == null or _economy_ref == null or _market_ref == null:
		return false
	var configured: bool = market_panel.configure(_inventory_ref, _economy_ref, _market_ref)
	var service_dependencies := [progression, tool_system, production]
	var has_any_service_dependency := service_dependencies.any(func(value: Variant) -> bool: return value != null)
	if has_any_service_dependency:
		if service_dependencies.any(func(value: Variant) -> bool: return value == null):
			return false
		configured = service_panel.configure(progression, tool_system, production) and configured
	_refresh_header()
	return configured


func open(tab_id: String = "market") -> void:
	if _is_open:
		if tab_id != "market":
			select_tab(tab_id)
		return
	if not _modal_coordinator.acquire(self):
		return
	_is_open = true
	visible = true
	if not _has_opened:
		select_tab(tab_id if tab_id in VALID_TABS else "market")
	elif tab_id != "market" and tab_id in VALID_TABS:
		select_tab(tab_id)
	_has_opened = true
	_refresh_header()
	if selected_tab == "market":
		market_panel.refresh_snapshot()


func select_tab(tab_id: String) -> bool:
	if tab_id not in VALID_TABS:
		return false
	selected_tab = tab_id
	if not is_node_ready():
		return true
	for page_id in pages:
		pages[page_id].visible = page_id == selected_tab
	for button_id in tab_buttons:
		tab_buttons[button_id].button_pressed = button_id == selected_tab
	if selected_tab == "market" and _market_ref != null:
		market_panel.refresh_snapshot()
	elif selected_tab == "services" and service_panel != null:
		service_panel.refresh_services()
	return true


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_modal_coordinator.release(self)


func _refresh_header() -> void:
	_on_gold_changed(_gold())
	market_status_label.text = "市场总体：%s" % _overall_market_status()
	var season_system := _season_system()
	if season_system != null:
		var season_names := ["春", "夏", "秋", "冬"]
		var season_index := int(season_system.get("current_season"))
		var day := int(season_system.get("current_day"))
		if day <= 0:
			day = int(season_system.get("day"))
		date_label.text = "%s %d/7" % [season_names[clampi(season_index, 0, 3)], maxi(1, day)]
	else:
		date_label.text = "春 1/7"


func _overall_market_status() -> String:
	if _market_ref == null:
		return "未连接"
	var shortage_count := 0
	for definition in preload("res://scripts/core/game_data.gd").get_market_items():
		var state := _market_ref.get_item_state(str(definition.get("id", "")))
		if (
			not state.is_empty()
			and int(state.get("stock", 0)) * 3 < int(state.get("target_stock", 1))
		):
			shortage_count += 1
	return "平稳" if shortage_count == 0 else "%d 项紧缺" % shortage_count


func _season_system() -> Node:
	var current_scene := get_tree().current_scene if is_inside_tree() else null
	return current_scene.get_node_or_null("SeasonSystem") if current_scene != null else null


func _gold() -> int:
	var wallet := get_node_or_null("/root/GameState") if is_inside_tree() else null
	return int(wallet.get("gold")) if wallet != null else 0


func _on_gold_changed(value: int) -> void:
	if header_gold_label != null:
		header_gold_label.text = "金币 %d" % value


func _on_day_changed(_total_day: int) -> void:
	_refresh_header()


func _unhandled_input(event: InputEvent) -> void:
	if (
		not _is_open
		or not event is InputEventKey
		or not event.pressed
		or event.echo
		or event.keycode != KEY_ESCAPE
	):
		return
	if selected_tab == "market" and market_panel.handle_top_escape():
		get_viewport().set_input_as_handled()
		return
	close()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _modal_coordinator.is_owned_by(self):
		_modal_coordinator.release(self)
