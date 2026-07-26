class_name ShopUI
extends Control

## 商店界面 - 购买种子和材料

@onready var grid_container: GridContainer = $ScrollContainer/GridContainer
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var close_button: Button = $CloseButton

var _is_open := false
var _current_category: String = "seed"


func _ready() -> void:
	visible = false
	if close_button:
		close_button.pressed.connect(close)


func open() -> void:
	_is_open = true
	visible = true
	_refresh_shop()


func close() -> void:
	_is_open = false
	visible = false


func _refresh_shop() -> void:
	if grid_container == null:
		return

	for child in grid_container.get_children():
		child.queue_free()

	# 显示可购买物品（种子 + 材料）
	var items = GameData.get_items_by_category("seed")
	items.append_array(GameData.get_items_by_category("material"))

	for item in items:
		if item.buy_price <= 0:
			continue
		var card = _create_shop_card(item)
		grid_container.add_child(card)

	_update_gold_display()


func _create_shop_card(item: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(100, 80)

	var vbox = VBoxContainer.new()

	var name_label = Label.new()
	name_label.text = item.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var price_label = Label.new()
	price_label.text = "💰 %d" % item.buy_price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(price_label)

	var button = Button.new()
	button.text = "购买"
	button.pressed.connect(_on_buy_pressed.bind(item.id, item.buy_price))
	vbox.add_child(button)

	panel.add_child(vbox)
	return panel


func _on_buy_pressed(item_id: String, price: int) -> void:
	var economy = get_node_or_null("/root/EconomySystem")
	var inventory = get_node_or_null("/root/InventorySystem")

	if economy == null or inventory == null:
		return

	if not economy.spend_gold(price):
		return  # 金币不足

	inventory.add_item(item_id, 1)
	_update_gold_display()


func _update_gold_display() -> void:
	if gold_label == null:
		return
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		gold_label.text = "💰 %d" % game_state.gold


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _is_open:
		close()
		get_viewport().set_input_as_handled()
