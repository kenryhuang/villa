class_name ShopUI
extends Control

const VALID_TABS := ["market", "orders", "contracts", "services"]
const EconomyModalCoordinatorScript = preload(
	"res://scripts/ui/economy_modal_coordinator.gd"
)
const MarketPanelScript = preload("res://scripts/ui/market_panel.gd")
const EconomyLayoutScript = preload("res://scripts/ui/economy_layout.gd")
const OPEN_DURATION := 0.16
const CONTENT_FADE_DURATION := 0.12

@onready var screen_layer: CanvasLayer = $ScreenLayer
@onready var modal_layer: ColorRect = $ScreenLayer/ModalLayer
@onready var hub_panel: PanelContainer = $ScreenLayer/ModalLayer/HubPanel
@onready var header_gold_label: Label = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/GoldLabel
@onready var date_label: Label = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/DateLabel
@onready var market_status_label: Label = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/MarketStatusLabel
@onready var close_button: Button = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/CloseButton
@onready var tab_buttons := {
	"market": $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/MarketTab,
	"orders": $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/OrdersTab,
	"contracts": $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/ContractsTab,
	"services": $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/ServicesTab,
}
@onready var pages := {
	"market": $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel,
	"orders": $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/OrderPanel,
	"contracts": $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/ContractPanel,
	"services": $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/ServicesPage,
}
@onready var market_panel = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel
@onready var service_panel = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/ServicesPage
@onready var order_panel = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/OrderPanel
@onready var contract_panel = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/ContractPanel
@onready var trade_modal_blocker: Control = $ScreenLayer/ModalLayer/TradeModalBlocker
@onready var trade_confirmation_layer: Control = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel/Columns/TradePanel/ConfirmationLayer
@onready var trade_confirm_button: Button = $ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel/Columns/TradePanel/ConfirmationLayer/Content/VBox/Buttons/ConfirmButton
@onready var sign_confirmation_layer: ColorRect = $ScreenLayer/ModalLayer/SignConfirmationLayer
@onready var sign_summary_label: Label = $ScreenLayer/ModalLayer/SignConfirmationLayer/Content/Margin/VBox/SummaryLabel
@onready var sign_error_label: Label = $ScreenLayer/ModalLayer/SignConfirmationLayer/Content/Margin/VBox/ErrorLabel
@onready var sign_cancel_button: Button = $ScreenLayer/ModalLayer/SignConfirmationLayer/Content/Margin/VBox/Actions/CancelButton
@onready var sign_confirm_button: Button = $ScreenLayer/ModalLayer/SignConfirmationLayer/Content/Margin/VBox/Actions/ConfirmButton

var selected_tab := "market"
var _is_open := false
var _has_opened := false
var _inventory_ref: InventorySystem
var _economy_ref: EconomySystem
var _market_ref: MarketSystem
var _npc_economy_ref: NpcEconomySystem
var _modal_coordinator = EconomyModalCoordinatorScript.new()
var _pending_contract_id := ""
var _pending_contract_snapshot: Dictionary = {}
var _sign_confirmation_in_progress := false
var _trade_modal_focus_modes: Dictionary = {}
var animations_enabled := true
var _panel_tween: Tween
var _content_tween: Tween


func _ready() -> void:
	visible = false
	screen_layer.visible = false
	if not visibility_changed.is_connected(_sync_screen_layer_visibility):
		visibility_changed.connect(_sync_screen_layer_visibility)
	close_button.pressed.connect(close)
	for tab_id in tab_buttons:
		tab_buttons[tab_id].pressed.connect(select_tab.bind(tab_id))
	if not contract_panel.sign_confirmation_requested.is_connected(_on_sign_confirmation_requested):
		contract_panel.sign_confirmation_requested.connect(_on_sign_confirmation_requested)
	if not sign_cancel_button.pressed.is_connected(dismiss_contract_sign):
		sign_cancel_button.pressed.connect(dismiss_contract_sign)
	if not sign_confirm_button.pressed.is_connected(confirm_contract_sign):
		sign_confirm_button.pressed.connect(confirm_contract_sign)
	if not trade_confirmation_layer.visibility_changed.is_connected(_on_trade_confirmation_visibility_changed):
		trade_confirmation_layer.visibility_changed.connect(_on_trade_confirmation_visibility_changed)
	if not resized.is_connected(_layout_trade_modal_blocker):
		resized.connect(_layout_trade_modal_blocker)
	if not get_viewport().size_changed.is_connected(_apply_compact_rect):
		get_viewport().size_changed.connect(_apply_compact_rect)
	trade_modal_blocker.visible = trade_confirmation_layer.visible
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		if not event_bus.gold_changed.is_connected(_on_gold_changed):
			event_bus.gold_changed.connect(_on_gold_changed)
		if not event_bus.day_changed.is_connected(_on_day_changed):
			event_bus.day_changed.connect(_on_day_changed)
	select_tab(selected_tab)
	_apply_compact_rect()


func configure(
	inventory: InventorySystem,
	economy: EconomySystem,
	market: MarketSystem,
	progression: EconomyProgressionSystem = null,
	tool_system: ToolSystem = null,
	production: ProductionSystem = null,
	npc_economy: NpcEconomySystem = null
) -> bool:
	_inventory_ref = inventory
	_economy_ref = economy
	_market_ref = market
	_npc_economy_ref = npc_economy
	if _inventory_ref == null or _economy_ref == null or _market_ref == null:
		return false
	var configured: bool = market_panel.configure(_inventory_ref, _economy_ref, _market_ref)
	configured = contract_panel.configure(_economy_ref) and configured
	if _npc_economy_ref != null:
		configured = order_panel.configure(_economy_ref, _npc_economy_ref) and configured
	var service_dependencies := [progression, tool_system, production]
	var has_any_service_dependency := service_dependencies.any(func(value: Variant) -> bool: return value != null)
	if has_any_service_dependency:
		if service_dependencies.any(func(value: Variant) -> bool: return value == null):
			return false
		configured = service_panel.configure(progression, tool_system, production) and configured
	market_panel.refresh_market()
	_refresh_header()
	return configured


func open(tab_id: String = "market", target_id: String = "") -> void:
	if _is_open:
		if tab_id != "market":
			select_tab(tab_id)
		_select_target(tab_id, target_id)
		return
	if not _modal_coordinator.acquire(self):
		return
	_is_open = true
	visible = true
	screen_layer.visible = true
	_apply_compact_rect()
	if not _has_opened:
		select_tab(tab_id if tab_id in VALID_TABS else "market")
	elif tab_id != "market" and tab_id in VALID_TABS:
		select_tab(tab_id)
	_has_opened = true
	_refresh_header()
	if selected_tab == "market":
		market_panel.refresh_market()
	elif selected_tab == "orders":
		order_panel.refresh_orders()
	elif selected_tab == "contracts":
		contract_panel.refresh_contracts()
	_select_target(selected_tab, target_id)
	_animate_open(hub_panel)


func _select_target(tab_id: String, target_id: String) -> bool:
	if target_id.is_empty():
		return true
	match tab_id:
		"market":
			market_panel.select_item(target_id)
			return true
		"orders":
			order_panel.select_order(target_id)
			return true
		"contracts":
			contract_panel.select_contract(target_id)
			return true
		"services":
			return service_panel != null and service_panel.select_service(target_id)
	return false


func select_tab(tab_id: String) -> bool:
	if tab_id not in VALID_TABS:
		return false
	if trade_confirmation_layer != null and trade_confirmation_layer.visible and tab_id != selected_tab:
		return false
	selected_tab = tab_id
	if not is_node_ready():
		return true
	for page_id in pages:
		pages[page_id].visible = page_id == selected_tab
	for button_id in tab_buttons:
		tab_buttons[button_id].button_pressed = button_id == selected_tab
	_apply_tab_styles()
	if selected_tab == "market" and _market_ref != null:
		market_panel.refresh_market()
	elif selected_tab == "orders" and _economy_ref != null:
		order_panel.refresh_orders()
	elif selected_tab == "contracts" and _economy_ref != null:
		contract_panel.refresh_contracts()
	elif selected_tab == "services" and service_panel != null:
		service_panel.refresh_services()
	if _is_open:
		_animate_content(pages[selected_tab] as Control)
	return true


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	if trade_confirmation_layer.visible:
		trade_confirmation_layer.get_parent().call("dismiss_confirmation")
	dismiss_contract_sign()
	_stop_transitions()
	screen_layer.visible = false
	visible = false
	_modal_coordinator.release(self)


func _on_trade_confirmation_visibility_changed() -> void:
	trade_modal_blocker.visible = trade_confirmation_layer.visible
	if trade_confirmation_layer.visible:
		_layout_trade_modal_blocker()
		_layout_trade_modal_blocker.call_deferred()
		_block_trade_modal_focus()
		trade_confirm_button.grab_focus()
	else:
		_restore_trade_modal_focus()


func _layout_trade_modal_blocker() -> void:
	if not is_node_ready() or not trade_modal_blocker.visible:
		return
	var blocker_size := trade_modal_blocker.size
	var blocker_origin := trade_modal_blocker.get_global_rect().position
	var trade_rect := trade_confirmation_layer.get_global_rect()
	var hole := Rect2(trade_rect.position - blocker_origin, trade_rect.size)
	_set_blocker_rect($ScreenLayer/ModalLayer/TradeModalBlocker/Top, Rect2(0.0, 0.0, blocker_size.x, maxf(0.0, hole.position.y)))
	_set_blocker_rect($ScreenLayer/ModalLayer/TradeModalBlocker/Bottom, Rect2(0.0, hole.end.y, blocker_size.x, maxf(0.0, blocker_size.y - hole.end.y)))
	_set_blocker_rect($ScreenLayer/ModalLayer/TradeModalBlocker/Left, Rect2(0.0, hole.position.y, maxf(0.0, hole.position.x), hole.size.y))
	_set_blocker_rect($ScreenLayer/ModalLayer/TradeModalBlocker/Right, Rect2(hole.end.x, hole.position.y, maxf(0.0, blocker_size.x - hole.end.x), hole.size.y))


func _apply_compact_rect() -> void:
	if not is_node_ready():
		return
	var rect := EconomyLayoutScript.panel_rect_for(
		get_viewport_rect().size,
		EconomyLayoutScript.MARKET_PANEL_MAX_SIZE
	)
	hub_panel.position = rect.position
	hub_panel.size = rect.size


func _apply_tab_styles() -> void:
	for tab_id in tab_buttons:
		var button := tab_buttons[tab_id] as Button
		button.theme_type_variation = (
			&"EconomyTabSelected" if tab_id == selected_tab else &"EconomyTab"
		)


func set_animations_enabled(enabled: bool) -> void:
	animations_enabled = enabled
	if not enabled:
		_stop_transitions()
		if is_node_ready():
			hub_panel.scale = Vector2.ONE
			hub_panel.modulate.a = 1.0
			for page in pages.values():
				(page as Control).modulate.a = 1.0


func _animate_open(panel: Control) -> void:
	if not animations_enabled:
		panel.scale = Vector2.ONE
		panel.modulate.a = 1.0
		return
	if _panel_tween != null:
		_panel_tween.kill()
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.985, 0.985)
	panel.modulate.a = 0.0
	_panel_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_panel_tween.set_parallel(true)
	_panel_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(panel, "scale", Vector2.ONE, OPEN_DURATION)
	_panel_tween.tween_property(panel, "modulate:a", 1.0, OPEN_DURATION)


func _animate_content(page: Control) -> void:
	if _content_tween != null:
		_content_tween.kill()
	for value in pages.values():
		(value as Control).modulate.a = 1.0
	if not animations_enabled:
		return
	page.modulate.a = 0.0
	_content_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_content_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_content_tween.tween_property(page, "modulate:a", 1.0, CONTENT_FADE_DURATION)


func _stop_transitions() -> void:
	if _panel_tween != null:
		_panel_tween.kill()
		_panel_tween = null
	if _content_tween != null:
		_content_tween.kill()
		_content_tween = null


func _sync_screen_layer_visibility() -> void:
	if is_node_ready():
		screen_layer.visible = visible


func _set_blocker_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _block_trade_modal_focus() -> void:
	_trade_modal_focus_modes.clear()
	for control in _all_controls(self):
		if (
			control == self
			or control == trade_modal_blocker
			or trade_confirmation_layer.is_ancestor_of(control)
		):
			continue
		if control.focus_mode != Control.FOCUS_NONE:
			_trade_modal_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE


func _restore_trade_modal_focus() -> void:
	for control_value in _trade_modal_focus_modes:
		if not is_instance_valid(control_value):
			continue
		var control := control_value as Control
		control.focus_mode = int(_trade_modal_focus_modes[control_value])
	_trade_modal_focus_modes.clear()


func _all_controls(root: Control) -> Array[Control]:
	var result: Array[Control] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			pending.append(child)
			if child is Control:
				result.append(child)
	return result


func confirm_contract_sign() -> bool:
	if (
		_sign_confirmation_in_progress
		or _pending_contract_id.is_empty()
		or _pending_contract_snapshot.is_empty()
	):
		return false
	_sign_confirmation_in_progress = true
	var contract_id := _pending_contract_id
	var snapshot := _pending_contract_snapshot.duplicate(true)
	var succeeded: bool = contract_panel.commit_confirmed_sign(contract_id, snapshot)
	_sign_confirmation_in_progress = false
	if succeeded:
		dismiss_contract_sign()
	else:
		sign_error_label.text = "合同状态已变化，请重新查看后确认"
		dismiss_contract_sign()
	return succeeded


func dismiss_contract_sign() -> void:
	if sign_confirmation_layer != null:
		sign_confirmation_layer.visible = false
	_pending_contract_id = ""
	_pending_contract_snapshot.clear()
	_sign_confirmation_in_progress = false


func _on_sign_confirmation_requested(contract_id: String, snapshot: Dictionary) -> void:
	if contract_id.is_empty() or snapshot.is_empty() or sign_confirmation_layer.visible:
		return
	_pending_contract_id = contract_id
	_pending_contract_snapshot = snapshot.duplicate(true)
	sign_error_label.text = ""
	sign_summary_label.text = "%s\n每日交付 %s ×%d，第 %d–%d 天。确认后会产生跨日义务。" % [
		contract_id,
		str(snapshot.get("item_id", "")),
		int(snapshot.get("quantity_per_day", 0)),
		int(snapshot.get("start_day", 0)),
		int(snapshot.get("end_day", 0)),
	]
	sign_confirmation_layer.visible = true


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
	if sign_confirmation_layer.visible:
		dismiss_contract_sign()
		get_viewport().set_input_as_handled()
		return
	if selected_tab == "market" and market_panel.handle_top_escape():
		get_viewport().set_input_as_handled()
		return
	close()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _modal_coordinator.is_owned_by(self):
		_modal_coordinator.release(self)
