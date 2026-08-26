class_name DialogueUI
extends Control

## 对话界面 - NPC 对话面板

const GameDataScript = preload("res://scripts/core/game_data.gd")

@onready var panel: PanelContainer = $DialoguePanel
@onready var name_label: Label = $DialoguePanel/Margin/VBox/NameLabel
@onready var text_label: Label = $DialoguePanel/Margin/VBox/TextContainer/TextLabel
@onready var choices_container: VBoxContainer = $DialoguePanel/Margin/VBox/Choices

var _current_villager_id: String = ""
var _current_dialogue_index: int = 0
var _dialogues: Array = []
var _is_open := false


func _ready() -> void:
	visible = false
	if panel:
		panel.visible = false


func start_dialogue(villager_id: String) -> void:
	var villager_system = get_node_or_null("/root/VillagerSystem")
	if villager_system == null:
		return

	var game_state = get_node_or_null("/root/GameState")
	var player_level = game_state.player_state.level if game_state else 1

	_dialogues = villager_system.get_dialogue(villager_id, player_level)
	if _dialogues.is_empty():
		return

	_current_villager_id = villager_id
	_current_dialogue_index = 0
	_is_open = true
	visible = true
	if panel:
		panel.visible = true

	_show_current_dialogue()


func start_agent_dialogue(villager_id: String, speech: String) -> void:
	var clean_speech := speech.strip_edges()
	if clean_speech.is_empty():
		return
	_current_villager_id = villager_id
	_current_dialogue_index = 0
	_dialogues = [{"text": clean_speech, "choices": []}]
	_is_open = true
	visible = true
	if panel:
		panel.visible = true
	_show_current_dialogue()


func _show_current_dialogue() -> void:
	if _current_dialogue_index >= _dialogues.size():
		close()
		return

	var dialogue = _dialogues[_current_dialogue_index]

	if name_label:
		var v_data = GameDataScript.get_villager(_current_villager_id)
		name_label.text = v_data.name if not v_data.is_empty() else _current_villager_id

	if text_label:
		text_label.text = dialogue.get("text", "...")

	# 显示选项
	if choices_container:
		for child in choices_container.get_children():
			child.queue_free()

		var choices = dialogue.get("choices", [])
		for choice in choices:
			var button = Button.new()
			button.text = choice.text
			button.pressed.connect(_on_choice_selected.bind(choice))
			choices_container.add_child(button)


func _on_choice_selected(choice: Dictionary) -> void:
	# 应用效果
	var effect = choice.get("effect", {})
	if effect.has("affinity"):
		var villager_system = get_node_or_null("/root/VillagerSystem")
		if villager_system:
			villager_system.add_affinity(_current_villager_id, effect.affinity)

	# 下一条对话
	_current_dialogue_index += 1
	_show_current_dialogue()


func close() -> void:
	_is_open = false
	visible = false
	if panel:
		panel.visible = false


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
