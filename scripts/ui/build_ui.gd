class_name BuildUI
extends Control

## 建造界面 - 建筑选择面板

const GameDataScript = preload("res://scripts/core/game_data.gd")

@export var keyboard_shortcut_enabled := true

@onready var grid_container: GridContainer = $ScrollContainer/GridContainer
@onready var close_button: Button = $CloseButton

var building_system_ref
var _is_open := false


func _ready() -> void:
	visible = false
	if close_button:
		close_button.pressed.connect(close)


func configure(bs) -> void:
	building_system_ref = bs


func open() -> void:
	_is_open = true
	visible = true
	_refresh_building_list()


func close() -> void:
	_is_open = false
	visible = false
	if building_system_ref:
		building_system_ref.exit_preview_mode()


func _refresh_building_list() -> void:
	if grid_container == null:
		return

	for child in grid_container.get_children():
		child.queue_free()

	var game_data = GameDataScript.new()
	for building_data in game_data.get_all_buildings():
		var card = _create_building_card(building_data, game_data)
		grid_container.add_child(card)
	game_data.free()


func _create_building_card(data: Dictionary, game_data: Node) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(120, 100)

	var vbox = VBoxContainer.new()

	var name_label = Label.new()
	name_label.text = data.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var desc_label = Label.new()
	desc_label.text = data.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(desc_label)

	# 造价
	var cost_text = ""
	for item_id in data.cost:
		var item: Dictionary = game_data.get_item(item_id)
		cost_text += "%s:%d " % [item.name if not item.is_empty() else item_id, data.cost[item_id]]
	var cost_label = Label.new()
	cost_label.text = cost_text
	cost_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(cost_label)

	var button = Button.new()
	button.text = "建造"
	button.pressed.connect(_on_build_pressed.bind(data.id))
	vbox.add_child(button)

	panel.add_child(vbox)
	return panel


func _on_build_pressed(building_id: String) -> void:
	if building_system_ref and building_system_ref.enter_preview_mode(building_id):
		_is_open = false
		visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not keyboard_shortcut_enabled:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_B:
			if _is_open:
				close()
			else:
				open()
			get_viewport().set_input_as_handled()
