class_name TradePanel
extends VBoxContainer

const GameDataScript = preload("res://scripts/core/game_data.gd")

signal snapshot_changed

@onready var player_quantity_label: Label = $PlayerQuantityLabel
@onready var market_quantity_label: Label = $MarketQuantityLabel
@onready var quantity_spin: SpinBox = $QuantityRow/QuantitySpin
@onready var max_button: Button = $QuantityRow/MaxButton
@onready var reference_price_label: Label = $ReferencePriceLabel
@onready var buy_total_label: Label = $BuyTotalLabel
@onready var sell_total_label: Label = $SellTotalLabel
@onready var impact_label: Label = $ImpactLabel
@onready var disabled_reason_label: Label = $DisabledReasonLabel
@onready var buy_button: Button = $Actions/BuyButton
@onready var sell_button: Button = $Actions/SellButton
@onready var feedback_label: Label = $FeedbackLabel
@onready var feedback_timer: Timer = $FeedbackTimer
@onready var confirmation_layer: PanelContainer = $ConfirmationLayer
@onready var first_unit_label: Label = $ConfirmationLayer/Content/FirstUnitLabel
@onready var last_unit_label: Label = $ConfirmationLayer/Content/LastUnitLabel
@onready var confirmation_total_label: Label = $ConfirmationLayer/Content/TotalLabel
@onready var pressure_label: Label = $ConfirmationLayer/Content/PressureLabel

var inventory_ref: InventorySystem
var economy_ref: EconomySystem
var market_ref: MarketSystem
var item_id := ""
var _pending_action := ""


func _ready() -> void:
	quantity_spin.value_changed.connect(_on_quantity_changed)
	max_button.pressed.connect(_on_max_pressed)
	buy_button.pressed.connect(request_buy)
	sell_button.pressed.connect(request_sell)
	$ConfirmationLayer/Content/Buttons/ConfirmButton.pressed.connect(_confirm_pending_trade)
	$ConfirmationLayer/Content/Buttons/CancelButton.pressed.connect(dismiss_confirmation)
	feedback_timer.timeout.connect(_clear_feedback)
	confirmation_layer.visible = false


func configure(
	inventory: InventorySystem,
	economy: EconomySystem,
	market: MarketSystem
) -> bool:
	inventory_ref = inventory
	economy_ref = economy
	market_ref = market
	var configured := inventory_ref != null and economy_ref != null and market_ref != null
	refresh_quote()
	return configured


func set_item(next_item_id: String) -> void:
	item_id = next_item_id
	quantity_spin.value = 1.0
	dismiss_confirmation()
	refresh_quote()


func refresh_quote() -> void:
	if not is_node_ready():
		return
	var state := market_ref.get_item_state(item_id) if market_ref != null else {}
	var quantity := maxi(1, int(quantity_spin.value))
	var stock := int(state.get("stock", 0))
	var owned := inventory_ref.get_item_count(item_id) if inventory_ref != null else 0
	var mid := int(state.get("mid_price", 0))
	var liquidity := int(state.get("daily_liquidity", 0))
	var buy_total := market_ref.quote_buy(item_id, quantity) if market_ref != null else 0
	var sell_total := market_ref.quote_sell(item_id, quantity) if market_ref != null else 0
	quantity_spin.max_value = maxf(1.0, float(maxi(stock, owned)))
	player_quantity_label.text = "玩家持有：%d" % owned
	market_quantity_label.text = "市集可买：%d" % stock
	reference_price_label.text = "参考单价：%d" % mid
	buy_total_label.text = "买入实际总价：%d" % buy_total
	sell_total_label.text = "卖出实际总价：%d" % sell_total
	impact_label.text = "成交影响：%s" % impact_for(quantity, liquidity)
	var buy_reason := _buy_disabled_reason(state, quantity, buy_total)
	var sell_reason := _sell_disabled_reason(state, quantity)
	buy_button.disabled = not buy_reason.is_empty()
	buy_button.tooltip_text = buy_reason
	sell_button.disabled = not sell_reason.is_empty()
	sell_button.tooltip_text = sell_reason
	disabled_reason_label.text = buy_reason if not buy_reason.is_empty() else sell_reason


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


func request_buy() -> void:
	refresh_quote()
	if buy_button.disabled:
		_show_feedback(buy_button.tooltip_text)
		return
	var quantity := maxi(1, int(quantity_spin.value))
	var total := market_ref.quote_buy(item_id, quantity)
	var first := market_ref.quote_buy(item_id, 1)
	var last := total - market_ref.quote_buy(item_id, quantity - 1) if quantity > 1 else first
	if needs_confirmation(quantity, _liquidity(), total, _gold(), first, last):
		_open_confirmation("buy", quantity, first, last, total)
		return
	_execute_trade("buy", quantity)


func request_sell() -> void:
	refresh_quote()
	if sell_button.disabled:
		_show_feedback(sell_button.tooltip_text)
		return
	var quantity := maxi(1, int(quantity_spin.value))
	var total := market_ref.quote_sell(item_id, quantity)
	var first := market_ref.quote_sell(item_id, 1)
	var last := total - market_ref.quote_sell(item_id, quantity - 1) if quantity > 1 else first
	if needs_confirmation(quantity, _liquidity(), total, _gold(), first, last):
		_open_confirmation("sell", quantity, first, last, total)
		return
	_execute_trade("sell", quantity)


func dismiss_confirmation() -> void:
	_pending_action = ""
	if confirmation_layer != null:
		confirmation_layer.visible = false


func handle_top_escape() -> bool:
	if confirmation_layer != null and confirmation_layer.visible:
		dismiss_confirmation()
		return true
	return false


func _execute_trade(action: String, quantity: int) -> void:
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
	confirmation_layer.set_meta("quantity", quantity)
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
	if _pending_action.is_empty():
		return
	var action := _pending_action
	var quantity := int(confirmation_layer.get_meta("quantity", 1))
	dismiss_confirmation()
	_execute_trade(action, quantity)


func _on_quantity_changed(_value: float) -> void:
	refresh_quote()


func _on_max_pressed() -> void:
	if market_ref == null or inventory_ref == null:
		return
	var state := market_ref.get_item_state(item_id)
	var stock := int(state.get("stock", 0))
	var gold := _gold()
	var maximum := 0
	for quantity in range(1, stock + 1):
		if market_ref.quote_buy(item_id, quantity) > gold:
			break
		if not inventory_ref.can_add_item(item_id, quantity):
			break
		maximum = quantity
	quantity_spin.value = maxi(1, maximum)


func _buy_disabled_reason(state: Dictionary, quantity: int, total: int) -> String:
	if state.is_empty() or total <= 0:
		return "商品不可交易"
	var stock := int(state.get("stock", 0))
	if stock < quantity:
		return "市集库存仅剩 %d" % stock
	var missing_gold := total - _gold()
	if missing_gold > 0:
		return "金币不足 %d" % missing_gold
	if inventory_ref == null or not inventory_ref.can_add_item(item_id, quantity):
		return "背包需要 %d 个空位" % _required_empty_slots(quantity)
	return ""


func _sell_disabled_reason(state: Dictionary, quantity: int) -> String:
	if state.is_empty() or market_ref == null or market_ref.quote_sell(item_id, quantity) <= 0:
		return "商品不可交易"
	var owned := inventory_ref.get_item_count(item_id) if inventory_ref != null else 0
	if owned < quantity:
		return "持有量仅有 %d" % owned
	return ""


func _required_empty_slots(quantity: int) -> int:
	if inventory_ref == null:
		return 1
	var item_data = GameDataScript.get_item(item_id)
	var max_stack := int(item_data.get("max_stack", 99)) if item_data != null else 99
	var existing_capacity := 0
	for slot in inventory_ref.slots:
		if not slot.is_empty() and str(slot.get("item_id", "")) == item_id:
			existing_capacity += maxi(0, max_stack - int(slot.get("quantity", 0)))
	var remaining := maxi(0, quantity - existing_capacity)
	return maxi(1, ceili(float(remaining) / float(maxi(1, max_stack))))


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
