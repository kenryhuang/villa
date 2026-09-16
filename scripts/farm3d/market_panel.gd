extends "res://scripts/ui/market_panel.gd"

const Icons = preload("res://scripts/farm3d/target_catalog.gd")
var merchant_supply_label: Label
var supply_button: Button
var _supply_elapsed := 0.0

func _ready() -> void:
	super._ready()
	merchant_supply_label = Label.new()
	merchant_supply_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trade_panel.get_node("Content").add_child(merchant_supply_label)
	supply_button = Button.new()
	supply_button.text = "登记补货需求（不扣款）"
	trade_panel.get_node("Content").add_child(supply_button)
	supply_button.pressed.connect(func():
		if market_ref == null or market_ref.merchant_service == null or selected_item_id.is_empty(): return
		var result: Dictionary = market_ref.merchant_service.request_supply("player", {"item_id": selected_item_id, "quantity": clampi(int(trade_panel.quantity_spin.value), 1, 100)}, "player-supply:%d" % Time.get_ticks_usec())
		merchant_supply_label.text = str(result.get("message", result.get("error", "")))
	)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_supply_elapsed += delta
	if _supply_elapsed >= 1:
		_supply_elapsed = 0
		_refresh_supply()

func refresh_snapshot() -> void:
	super.refresh_snapshot()
	_refresh_supply()

func _refresh_supply() -> void:
	if merchant_supply_label == null or market_ref == null or market_ref.merchant_service == null or selected_item_id.is_empty(): return
	var supply: Dictionary = market_ref.merchant_service.supply_view(selected_item_id)
	var reasons := {"route_blocked": "商道暂时中断", "supplier_empty": "供应商暂时无货", "freight_capacity": "今日运力已满", "merchant_insufficient_cash": "商行采购资金不足"}
	var message := "在途 %d · 商行最多收购 %d 件" % [int(supply.get("incoming", 0)), market_ref.maximum_sale(selected_item_id)]
	for shipment in supply.get("shipments", []):
		message += "\n预计 %d 游戏分钟后到货%s" % [maxi(0, int(shipment.arrival) - int(market_ref.merchant.minute)), "（道路延误中）" if not market_ref.merchant_service.world.environment.route_open() else ""]
	if not str(supply.get("reason", "")).is_empty(): message += "\n" + str(reasons.get(supply.reason, supply.reason))
	merchant_supply_label.text = message

func _item_icon_info(definition: Dictionary) -> Dictionary:
	var texture := Icons.item_icon(str(definition.get("id", "")))
	if texture != null:
		return {"texture": texture, "fallback": false}
	# A neutral goods crate replaces the original debug checkerboard texture.
	return {"texture": preload("res://assets/ui/material_icons/goods.svg"), "fallback": true}
