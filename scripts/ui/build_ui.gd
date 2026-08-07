class_name BuildUI
extends Control

## 建造界面 - 建筑选择面板

signal building_selection_rejected(building_id: String, diagnostic: Dictionary)

const GameDataScript = preload("res://scripts/core/game_data.gd")
const BuildingCatalogScript = preload("res://scripts/core/building_catalog.gd")

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
	for building_id in BuildingCatalogScript.all_building_ids():
		var building_data: Dictionary = game_data.get_building(building_id)
		var card = _create_building_card(building_data, game_data)
		grid_container.add_child(card)
	game_data.free()


func _create_building_card(data: Dictionary, game_data: Node) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(120, 100)
	panel.set_meta("building_id", str(data.get("id", "")))
	var diagnostic: Dictionary = (
		building_system_ref.diagnose_availability(str(data.get("id", "")))
		if building_system_ref != null and building_system_ref.has_method("diagnose_availability")
		else {"allowed": false, "code": "invalid_building", "message": "建筑数据不可用"}
	)
	var state := _state_for_diagnostic(diagnostic)
	panel.set_meta("availability_state", state)
	panel.tooltip_text = str(diagnostic.get("message", ""))
	match state:
		"locked":
			panel.modulate = Color(0.68, 0.68, 0.68, 1.0)
		"missing_resources":
			panel.modulate = Color(1.0, 0.78, 0.72, 1.0)
		"invalid":
			panel.modulate = Color(0.72, 0.35, 0.35, 1.0)

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
	button.text = {
		"ready": "建造",
		"missing_resources": "材料不足",
		"locked": "查看解锁",
		"invalid": "数据异常",
	}.get(state, "数据异常")
	button.disabled = state == "invalid"
	button.pressed.connect(_on_build_pressed.bind(data.id))
	vbox.add_child(button)

	panel.add_child(vbox)
	return panel


func _on_build_pressed(building_id: String) -> void:
	if building_system_ref == null:
		return
	var diagnostic: Dictionary = (
		building_system_ref.diagnose_availability(building_id)
		if building_system_ref.has_method("diagnose_availability")
		else {"allowed": false, "code": "system_unavailable", "message": "建造系统尚未就绪"}
	)
	if not bool(diagnostic.get("allowed", false)):
		building_selection_rejected.emit(building_id, diagnostic)
		return
	if building_system_ref.enter_preview_mode(building_id):
		_is_open = false
		visible = false


func _state_for_diagnostic(diagnostic: Dictionary) -> String:
	if bool(diagnostic.get("allowed", false)):
		return "ready"
	match str(diagnostic.get("code", "")):
		"blueprint_locked":
			return "locked"
		"insufficient_resources":
			return "missing_resources"
	return "invalid"


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
