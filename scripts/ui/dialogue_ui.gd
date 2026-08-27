class_name DialogueUI
extends Control

## 对话界面 - NPC 对话面板

signal agent_dialogue_cancelled(villager_id: String, request_id: String)
signal agent_dialogue_closed(villager_id: String, request_id: String)

const GameDataScript = preload("res://scripts/core/game_data.gd")

@onready var panel: PanelContainer = $DialoguePanel
@onready var name_label: Label = $DialoguePanel/Margin/VBox/NameLabel
@onready var text_label: Label = $DialoguePanel/Margin/VBox/TextContainer/TextLabel
@onready var choices_container: VBoxContainer = $DialoguePanel/Margin/VBox/Choices

var _current_villager_id: String = ""
var _current_dialogue_index: int = 0
var _dialogues: Array = []
var _is_open := false
var _agent_request_id := ""
var _agent_buffer := ""
var _agent_stream_pending := false


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
	_agent_request_id = ""
	_agent_buffer = ""
	_agent_stream_pending = false
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
	begin_agent_dialogue(villager_id, "legacy-agent-dialogue")
	finish_agent_dialogue("legacy-agent-dialogue", clean_speech)


func begin_agent_dialogue(villager_id: String, request_id: String) -> void:
	if villager_id.is_empty() or request_id.is_empty():
		return
	if _is_open and not _agent_request_id.is_empty():
		if request_id == _agent_request_id:
			return
		close()
	_current_villager_id = villager_id
	_current_dialogue_index = 0
	_agent_request_id = request_id
	_agent_buffer = ""
	_agent_stream_pending = true
	_dialogues = [{"text": "正在思考……", "choices": []}]
	_is_open = true
	visible = true
	if panel:
		panel.visible = true
	_show_current_dialogue()


func append_agent_dialogue(request_id: String, delta: String) -> void:
	if request_id != _agent_request_id or not _agent_stream_pending or delta.is_empty():
		return
	_agent_buffer += delta
	if not _dialogues.is_empty():
		(_dialogues[0] as Dictionary)["text"] = _agent_buffer
	if text_label:
		text_label.text = _agent_buffer


func finish_agent_dialogue(request_id: String, speech: String) -> void:
	if request_id != _agent_request_id or not _agent_stream_pending:
		return
	var final_speech := speech.strip_edges()
	if final_speech.is_empty():
		final_speech = _agent_buffer.strip_edges()
	if final_speech.is_empty():
		final_speech = "……"
	_agent_buffer = final_speech
	_agent_stream_pending = false
	if not _dialogues.is_empty():
		(_dialogues[0] as Dictionary)["text"] = final_speech
	if text_label:
		text_label.text = final_speech


func fail_agent_dialogue(request_id: String) -> bool:
	if request_id != _agent_request_id or not _agent_stream_pending:
		return false
	var failed_villager := _current_villager_id
	_clear_agent_dialogue_state()
	agent_dialogue_closed.emit(failed_villager, request_id)
	return true


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
	var closed_request := _agent_request_id
	var closed_villager := _current_villager_id
	var should_cancel := _agent_stream_pending and not closed_request.is_empty()
	_clear_agent_dialogue_state()
	if should_cancel:
		agent_dialogue_cancelled.emit(closed_villager, closed_request)
	if not closed_request.is_empty():
		agent_dialogue_closed.emit(closed_villager, closed_request)


func _clear_agent_dialogue_state() -> void:
	_agent_request_id = ""
	_agent_buffer = ""
	_agent_stream_pending = false
	_current_villager_id = ""
	_dialogues.clear()
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
