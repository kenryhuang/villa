class_name TradePanel
extends Control

const MAX_UI_QUANTITY := 999

signal snapshot_changed

@onready var player_quantity_label: Label = $Content/SummaryGrid/PlayerQuantityLabel
@onready var market_quantity_label: Label = $Content/SummaryGrid/MarketQuantityLabel
@onready var quantity_spin: SpinBox = $Content/QuantityRow/QuantitySpin
@onready var max_button: Button = $Content/MaxActions/MaxButton
@onready var sell_max_button: Button = $Content/MaxActions/SellMaxButton
@onready var reference_price_label: Label = $Content/SummaryGrid/ReferencePriceLabel
@onready var buy_total_label: Label = $Content/SummaryGrid/BuyTotalLabel
@onready var sell_total_label: Label = $Content/SummaryGrid/SellTotalLabel
@onready var impact_label: Label = $Content/SummaryGrid/ImpactLabel
@onready var disabled_reason_label: Label = $Content/StatusArea/DisabledReasonLabel
@onready var buy_button: Button = $Content/Actions/BuyButton
@onready var sell_button: Button = $Content/Actions/SellButton
@onready var feedback_label: Label = $Content/StatusArea/FeedbackLabel
@onready var feedback_timer: Timer = $FeedbackTimer
@onready var confirmation_layer: ColorRect = $ConfirmationLayer
@onready var confirmation_confirm_button: Button = $ConfirmationLayer/Content/VBox/Buttons/ConfirmButton
@onready var first_unit_label: Label = $ConfirmationLayer/Content/VBox/FirstUnitLabel
@onready var last_unit_label: Label = $ConfirmationLayer/Content/VBox/LastUnitLabel
@onready var confirmation_total_label: Label = $ConfirmationLayer/Content/VBox/TotalLabel
@onready var pressure_label: Label = $ConfirmationLayer/Content/VBox/PressureLabel

var inventory_ref: InventorySystem
var economy_ref: EconomySystem
var market_ref: MarketSystem
var item_id := ""
var _pending_action := ""
var _confirmation_snapshot: Dictionary = {}
var _event_bus: Node
var _refreshing_quote := false
var _quote_refresh_queued := false
var _underlying_focus_modes: Dictionary = {}
var _focus_before_confirmation: Control


func _enter_tree() -> void:
	_connect_authoritative_signals()


func _ready() -> void:
	quantity_spin.value_changed.connect(_on_quantity_changed)
	quantity_spin.gui_input.connect(_on_quantity_gui_input)
	max_button.pressed.connect(_on_buy_max_pressed)
	sell_max_button.pressed.connect(_on_sell_max_pressed)
	buy_button.pressed.connect(request_buy)
	sell_button.pressed.connect(request_sell)
	confirmation_confirm_button.pressed.connect(_confirm_pending_trade)
	$ConfirmationLayer/Content/VBox/Buttons/CancelButton.pressed.connect(dismiss_confirmation)
	confirmation_layer.visibility_changed.connect(_on_confirmation_visibility_changed)
	feedback_timer.timeout.connect(_clear_feedback)
	confirmation_layer.visible = false
	_connect_authoritative_signals()


func configure(
	inventory: InventorySystem,
	economy: EconomySystem,
	market: MarketSystem
) -> bool:
	if is_node_ready():
		dismiss_confirmation()
	_disconnect_authoritative_signals()
	inventory_ref = inventory
	economy_ref = economy
	market_ref = market
	var configured := inventory_ref != null and economy_ref != null and market_ref != null
	if configured:
		_connect_authoritative_signals()
	refresh_quote()
	return configured


func set_item(next_item_id: String) -> void:
	item_id = next_item_id
	quantity_spin.value = 1.0
	dismiss_confirmation()
	refresh_quote()


func refresh_quote() -> void:
	if not is_node_ready() or _refreshing_quote:
		return
	_refreshing_quote = true
	var state := market_ref.get_item_state(item_id) if market_ref != null else {}
	var stock := int(state.get("stock", 0))
	var owned := _owned_quantity()
	var safe_limit := maxi(1, mini(MAX_UI_QUANTITY, maxi(stock, owned)))
	quantity_spin.max_value = float(safe_limit)
	var quantity := safe_quantity(quantity_spin.value, stock, owned)
	if quantity <= 0:
		_set_invalid_quantity_state(stock, owned)
		_refreshing_quote = false
		return
	if not is_equal_approx(quantity_spin.value, float(quantity)):
		quantity_spin.value = float(quantity)
	var mid := int(state.get("mid_price", 0))
	var liquidity := int(state.get("daily_liquidity", 0))
	var buy_total := market_ref.quote_buy(item_id, quantity) if market_ref != null else 0
	var sell_total := market_ref.quote_sell(item_id, quantity) if market_ref != null else 0
	quantity_spin.max_value = float(safe_limit)
	player_quantity_label.text = str(owned)
	market_quantity_label.text = str(stock)
	reference_price_label.text = str(mid)
	buy_total_label.text = str(buy_total)
	sell_total_label.text = str(sell_total)
	impact_label.text = localized_impact(impact_for(quantity, liquidity))
	var buy_reason := _localized_trade_failure(_trade_preflight(quantity, true))
	var sell_reason := _localized_trade_failure(_trade_preflight(quantity, false))
	buy_button.disabled = not buy_reason.is_empty()
	buy_button.tooltip_text = buy_reason
	sell_button.disabled = not sell_reason.is_empty()
	sell_button.tooltip_text = sell_reason
	disabled_reason_label.text = buy_reason if not buy_reason.is_empty() else sell_reason
	_refreshing_quote = false


static func needs_confirmation(
	quantity: int,
	liquidity: int,
	total: int,
	gold: int,
	first_unit: int,
	last_unit: int
) -> bool:
	return (
		(liquidity > 0 and quantity >= liquidity)
		or (gold > 0 and total * 2 > gold)
		or (first_unit > 0 and last_unit * 10 <= first_unit * 9)
	)


static func impact_for(quantity: int, liquidity: int) -> String:
	if quantity <= 0 or liquidity <= 0:
		return "none"
	var ratio := float(quantity) / float(liquidity)
	if ratio <= 0.10:
		return "none"
	if ratio <= 0.25:
		return "light"
	if ratio < 1.0:
		return "clear"
	return "severe"


static func localized_impact(level: String) -> String:
	match level:
		"none":
			return "无明显影响"
		"light":
			return "轻微"
		"clear":
			return "明显"
		"severe":
			return "剧烈"
		_:
			return "未知"


static func needs_sell_confirmation(
	quantity: int,
	liquidity: int,
	first_unit: int,
	last_unit: int
) -> bool:
	return (
		(liquidity > 0 and quantity >= liquidity)
		or (first_unit > 0 and last_unit * 10 <= first_unit * 9)
	)


static func safe_quantity(raw_quantity: float, stock: int, owned: int) -> int:
	if not is_finite(raw_quantity):
		return 0
	var available := mini(MAX_UI_QUANTITY, maxi(0, maxi(stock, owned)))
	if available <= 0:
		return 0
	return clampi(floori(clampf(raw_quantity, 1.0, float(available))), 1, available)


func request_buy() -> void:
	refresh_quote()
	var state := market_ref.get_item_state(item_id) if market_ref != null else {}
	var quantity := _safe_current_quantity(state)
	if quantity <= 0:
		_show_feedback("数量无效")
		return
	if buy_button.disabled:
		_show_feedback(buy_button.tooltip_text)
		return
	var total := market_ref.quote_buy(item_id, quantity)
	var first := market_ref.quote_buy(item_id, 1)
	var last := total - market_ref.quote_buy(item_id, quantity - 1) if quantity > 1 else first
	if needs_confirmation(quantity, _liquidity(), total, _gold(), first, last):
		_open_confirmation("buy", quantity, first, last, total)
		return
	_execute_trade("buy", quantity)


func request_sell() -> void:
	refresh_quote()
	var state := market_ref.get_item_state(item_id) if market_ref != null else {}
	var quantity := _safe_current_quantity(state)
	if quantity <= 0:
		_show_feedback("数量无效")
		return
	if sell_button.disabled:
		_show_feedback(sell_button.tooltip_text)
		return
	var total := market_ref.quote_sell(item_id, quantity)
	var first := market_ref.quote_sell(item_id, 1)
	var last := total - market_ref.quote_sell(item_id, quantity - 1) if quantity > 1 else first
	if needs_sell_confirmation(quantity, _liquidity(), first, last):
		_open_confirmation("sell", quantity, first, last, total)
		return
	_execute_trade("sell", quantity)


func dismiss_confirmation() -> void:
	_pending_action = ""
	_confirmation_snapshot.clear()
	if confirmation_layer != null:
		confirmation_layer.visible = false


func handle_top_escape() -> bool:
	if confirmation_layer != null and confirmation_layer.visible:
		dismiss_confirmation()
		return true
	return false


func _on_confirmation_visibility_changed() -> void:
	if confirmation_layer.visible:
		_block_underlying_focus()
		confirmation_confirm_button.grab_focus()
	else:
		_restore_underlying_focus()


func _block_underlying_focus() -> void:
	_underlying_focus_modes.clear()
	_focus_before_confirmation = get_viewport().gui_get_focus_owner()
	for control in _all_controls(self):
		if control == self or confirmation_layer.is_ancestor_of(control):
			continue
		if control.focus_mode != Control.FOCUS_NONE:
			_underlying_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE


func _restore_underlying_focus() -> void:
	for control_value in _underlying_focus_modes:
		if not is_instance_valid(control_value):
			continue
		var control := control_value as Control
		control.focus_mode = int(_underlying_focus_modes[control_value])
	_underlying_focus_modes.clear()
	if is_instance_valid(_focus_before_confirmation) and _focus_before_confirmation.is_visible_in_tree():
		_focus_before_confirmation.call_deferred("grab_focus")
	_focus_before_confirmation = null


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


func _execute_trade(action: String, quantity: int) -> void:
	var preflight := _trade_preflight(quantity, action == "buy")
	if not bool(preflight.get("ok", false)):
		refresh_quote()
		_show_feedback(_localized_trade_failure(preflight))
		return
	var succeeded := (
		economy_ref.buy_item(item_id, quantity)
		if action == "buy"
		else economy_ref.sell_item(item_id, quantity)
	)
	refresh_quote()
	if succeeded:
		_show_feedback("买入成功" if action == "buy" else "卖出成功")
	else:
		_show_feedback("状态已变化")
	snapshot_changed.emit()


func _open_confirmation(
	action: String,
	quantity: int,
	first: int,
	last: int,
	total: int
) -> void:
	_pending_action = action
	var state := market_ref.get_item_state(item_id)
	_confirmation_snapshot = {
		"action": action,
		"item_id": item_id,
		"quantity": quantity,
		"total": total,
		"first_unit": first,
		"last_unit": last,
		"wallet_gold": _gold(),
		"market_stock": int(state.get("stock", 0)),
		"mid_price": int(state.get("mid_price", 0)),
		"daily_liquidity": int(state.get("daily_liquidity", 0)),
		"player_owned": _owned_quantity(),
		"preflight": _trade_preflight(quantity, action == "buy"),
	}
	first_unit_label.text = "首件价格：%d" % first
	last_unit_label.text = "末件价格：%d" % last
	confirmation_total_label.text = "实际总价：%d" % total
	pressure_label.text = (
		"预计次日供给压力：需求 +%d" % quantity
		if action == "buy"
		else "预计次日供给压力：供给 +%d" % quantity
	)
	confirmation_layer.visible = true


func _confirm_pending_trade() -> void:
	if _pending_action.is_empty() or _confirmation_snapshot.is_empty():
		return
	var snapshot := _confirmation_snapshot.duplicate(true)
	var action := str(snapshot.get("action", ""))
	var quantity := int(snapshot.get("quantity", 0))
	var preflight := _trade_preflight(quantity, action == "buy")
	if not bool(preflight.get("ok", false)):
		dismiss_confirmation()
		_show_feedback(_localized_trade_failure(preflight))
		refresh_quote()
		return
	if not _confirmation_is_current(snapshot):
		dismiss_confirmation()
		_show_feedback("状态已变化，请重新确认")
		refresh_quote()
		return
	dismiss_confirmation()
	_execute_trade(action, quantity)


func _on_quantity_changed(_value: float) -> void:
	if confirmation_layer != null and confirmation_layer.visible:
		_invalidate_confirmation("数量已变化，请重新确认")
	if is_instance_valid(market_ref) and is_instance_valid(economy_ref):
		refresh_quote()


func _on_quantity_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		quantity_spin.value = minf(quantity_spin.max_value, quantity_spin.value + quantity_spin.step)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		quantity_spin.value = maxf(quantity_spin.min_value, quantity_spin.value - quantity_spin.step)
		accept_event()


func _on_buy_max_pressed() -> void:
	if not is_instance_valid(economy_ref) or not is_instance_valid(market_ref):
		return
	var stock := int(market_ref.get_item_state(item_id).get("stock", 0))
	quantity_spin.value = maxi(
		1,
		_maximum_preflight_quantity(mini(MAX_UI_QUANTITY, stock), true)
	)


func _on_sell_max_pressed() -> void:
	if not is_instance_valid(economy_ref):
		return
	quantity_spin.value = maxi(
		1,
		_maximum_preflight_quantity(mini(MAX_UI_QUANTITY, _owned_quantity()), false)
	)


func _maximum_preflight_quantity(limit: int, is_buy: bool) -> int:
	var maximum := 0
	var low := 1
	var high := maxi(0, limit)
	while low <= high:
		var quantity := floori(float(low + high) / 2.0)
		if bool(_trade_preflight(quantity, is_buy).get("ok", false)):
			maximum = quantity
			low = quantity + 1
		else:
			high = quantity - 1
	return maximum


func _safe_current_quantity(state: Dictionary) -> int:
	var stock := int(state.get("stock", 0))
	var owned := _owned_quantity()
	return safe_quantity(quantity_spin.value, stock, owned)


func _set_invalid_quantity_state(stock: int, owned: int) -> void:
	player_quantity_label.text = str(owned)
	market_quantity_label.text = str(stock)
	reference_price_label.text = "—"
	buy_total_label.text = "0"
	sell_total_label.text = "0"
	impact_label.text = "无明显影响"
	disabled_reason_label.text = "数量无效"
	buy_button.disabled = true
	buy_button.tooltip_text = "数量无效"
	sell_button.disabled = true
	sell_button.tooltip_text = "数量无效"


func _confirmation_is_current(snapshot: Dictionary) -> bool:
	if str(snapshot.get("item_id", "")) != item_id:
		return false
	var action := str(snapshot.get("action", ""))
	if action != "buy" and action != "sell":
		return false
	var state := market_ref.get_item_state(item_id) if market_ref != null else {}
	if state.is_empty():
		return false
	var quantity := _safe_current_quantity(state)
	if quantity <= 0 or quantity != int(snapshot.get("quantity", 0)):
		return false
	var total := (
		market_ref.quote_buy(item_id, quantity)
		if action == "buy"
		else market_ref.quote_sell(item_id, quantity)
	)
	var first := market_ref.quote_buy(item_id, 1) if action == "buy" else market_ref.quote_sell(item_id, 1)
	var prior_total := (
		market_ref.quote_buy(item_id, quantity - 1)
		if action == "buy" and quantity > 1
		else market_ref.quote_sell(item_id, quantity - 1)
		if quantity > 1
		else 0
	)
	var last := total - prior_total if quantity > 1 else first
	return (
		total == int(snapshot.get("total", -1))
		and first == int(snapshot.get("first_unit", -1))
		and last == int(snapshot.get("last_unit", -1))
		and _gold() == int(snapshot.get("wallet_gold", -1))
		and int(state.get("stock", -1)) == int(snapshot.get("market_stock", -2))
		and int(state.get("mid_price", -1)) == int(snapshot.get("mid_price", -2))
		and int(state.get("daily_liquidity", -1)) == int(snapshot.get("daily_liquidity", -2))
		and _owned_quantity() == int(snapshot.get("player_owned", -1))
	)


func _connect_authoritative_signals() -> void:
	if not is_instance_valid(market_ref):
		return
	var stock_callable := Callable(self, "_on_market_stock_changed")
	if not market_ref.market_stock_changed.is_connected(stock_callable):
		market_ref.market_stock_changed.connect(stock_callable)
	var price_callable := Callable(self, "_on_market_price_changed")
	if not market_ref.market_price_changed.is_connected(price_callable):
		market_ref.market_price_changed.connect(price_callable)
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if _event_bus != null:
		for signal_name in [&"gold_changed", &"item_added", &"item_removed"]:
			var callback := (
				Callable(self, "_on_gold_changed")
				if signal_name == &"gold_changed"
				else Callable(self, "_on_inventory_changed")
			)
			if not _event_bus.is_connected(signal_name, callback):
				_event_bus.connect(signal_name, callback)
		var storage_callback := Callable(self, "_on_storage_changed")
		if not _event_bus.farm_storage_changed.is_connected(storage_callback):
			_event_bus.farm_storage_changed.connect(storage_callback)
		var capacity_callback := Callable(self, "_on_storage_capacity_changed")
		if not _event_bus.farm_storage_capacity_changed.is_connected(capacity_callback):
			_event_bus.farm_storage_capacity_changed.connect(capacity_callback)


func _disconnect_authoritative_signals() -> void:
	if is_instance_valid(market_ref):
		var stock_callable := Callable(self, "_on_market_stock_changed")
		var price_callable := Callable(self, "_on_market_price_changed")
		if market_ref.market_stock_changed.is_connected(stock_callable):
			market_ref.market_stock_changed.disconnect(stock_callable)
		if market_ref.market_price_changed.is_connected(price_callable):
			market_ref.market_price_changed.disconnect(price_callable)
	if is_instance_valid(_event_bus):
		for signal_name in [&"gold_changed", &"item_added", &"item_removed"]:
			var callback := (
				Callable(self, "_on_gold_changed")
				if signal_name == &"gold_changed"
				else Callable(self, "_on_inventory_changed")
			)
			if _event_bus.is_connected(signal_name, callback):
				_event_bus.disconnect(signal_name, callback)
		var storage_callback := Callable(self, "_on_storage_changed")
		if _event_bus.farm_storage_changed.is_connected(storage_callback):
			_event_bus.farm_storage_changed.disconnect(storage_callback)
		var capacity_callback := Callable(self, "_on_storage_capacity_changed")
		if _event_bus.farm_storage_capacity_changed.is_connected(capacity_callback):
			_event_bus.farm_storage_capacity_changed.disconnect(capacity_callback)
	_event_bus = null


func _on_market_stock_changed(changed_item_id: String, _stock: int) -> void:
	if changed_item_id == item_id:
		_on_authoritative_snapshot_changed()


func _on_market_price_changed(changed_item_id: String, _price: int) -> void:
	if changed_item_id == item_id:
		_on_authoritative_snapshot_changed()


func _on_gold_changed(_gold_value: int) -> void:
	_on_authoritative_snapshot_changed()


func _on_inventory_changed(changed_item_id: String, _quantity: int) -> void:
	if changed_item_id == item_id:
		_on_authoritative_snapshot_changed()


func _on_storage_changed(changes: Dictionary) -> void:
	if changes.has(item_id):
		_on_authoritative_snapshot_changed()


func _on_storage_capacity_changed(_used: int, _total: int) -> void:
	_on_authoritative_snapshot_changed()


func _on_authoritative_snapshot_changed() -> void:
	if confirmation_layer != null and confirmation_layer.visible:
		var pending_is_buy := _pending_action == "buy"
		var pending_quantity := int(_confirmation_snapshot.get("quantity", 0))
		var preflight := _trade_preflight(pending_quantity, pending_is_buy)
		var reason := _localized_trade_failure(preflight)
		_invalidate_confirmation(reason if not reason.is_empty() else "状态已变化，请重新确认")
	if _quote_refresh_queued:
		return
	_quote_refresh_queued = true
	call_deferred("_do_queued_quote_refresh")


func _do_queued_quote_refresh() -> void:
	_quote_refresh_queued = false
	refresh_quote()


func _invalidate_confirmation(message: String) -> void:
	dismiss_confirmation()
	_show_feedback(message)


func _trade_preflight(quantity: int, is_buy: bool) -> Dictionary:
	if not is_instance_valid(economy_ref) or not economy_ref.has_method("quote_trade_failure"):
		return {"ok": false, "reason": "not_configured", "item_id": item_id}
	return economy_ref.quote_trade_failure(item_id, quantity, is_buy)


func _localized_trade_failure(result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return ""
	match str(result.get("reason", "")):
		"market_stock":
			return "市集库存仅剩 %d" % int(result.get("available_quantity", 0))
		"insufficient_gold":
			return "金币不足 %d" % maxi(
				0,
				int(result.get("required_gold", 0)) - int(result.get("available_gold", 0))
			)
		"storage_capacity":
			return "农场仓库缺少 %d 容量" % int(result.get("missing_capacity", 0))
		"inventory_capacity":
			return "背包容量不足 %d 件" % int(result.get("missing_quantity", 0))
		"insufficient_crop", "insufficient_seed", "insufficient_resources":
			return "持有量仅有 %d" % _owned_quantity()
		"wallet_overflow":
			return "金币已达上限"
		"not_configured":
			return "交易系统未就绪"
		"transaction_failed":
			return "交易暂不可用"
		_:
			return "商品不可交易"


func _owned_quantity() -> int:
	return economy_ref.get_owned_quantity(item_id) if is_instance_valid(economy_ref) else 0


func _liquidity() -> int:
	return int(market_ref.get_item_state(item_id).get("daily_liquidity", 0)) if market_ref != null else 0


func _gold() -> int:
	var wallet := get_node_or_null("/root/GameState") if is_inside_tree() else null
	return int(wallet.get("gold")) if wallet != null else 0


func _show_feedback(message: String) -> void:
	feedback_label.text = message
	feedback_label.visible = true
	feedback_timer.start(1.5)


func _clear_feedback() -> void:
	feedback_label.visible = false


func _exit_tree() -> void:
	_disconnect_authoritative_signals()
