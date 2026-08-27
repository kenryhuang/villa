class_name DialogueUI
extends Control

signal agent_message_submitted(villager_id: String, message: String)
signal agent_dialogue_cancelled(villager_id: String, request_id: String)
signal agent_dialogue_closed(villager_id: String, request_id: String)

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MAX_MESSAGE_LENGTH := 1000
const THINKING_TEXT := "正在思考……"
const FAILURE_TEXT := "Agent 服务暂时不可用，请稍后再试。"

@onready var panel: PanelContainer = $DialoguePanel
@onready var name_label: Label = $DialoguePanel/Margin/VBox/Header/NameLabel
@onready var history_view: RichTextLabel = $DialoguePanel/Margin/VBox/History
@onready var status_label: Label = $DialoguePanel/Margin/VBox/Status
@onready var message_input: TextEdit = $DialoguePanel/Margin/VBox/Composer/MessageInput
@onready var send_button: Button = $DialoguePanel/Margin/VBox/Composer/SendButton
@onready var close_button: Button = $DialoguePanel/Margin/VBox/Header/CloseButton

var _histories: Dictionary = {}
var _display_names: Dictionary = {}
var _current_villager_id := ""
var _agent_request_id := ""
var _pending_history_index := -1
var _agent_stream_pending := false
var _is_open := false


func _ready() -> void:
	visible = false
	panel.visible = false
	send_button.pressed.connect(_submit_message)
	close_button.pressed.connect(close)
	message_input.gui_input.connect(_on_message_input_gui_input)


func open_agent_dialogue(villager_id: String, display_name: String) -> bool:
	if villager_id.strip_edges().is_empty():
		return false
	if _is_open and _current_villager_id != villager_id:
		close()
	_current_villager_id = villager_id
	_display_names[villager_id] = display_name if not display_name.strip_edges().is_empty() else villager_id
	if not _histories.has(villager_id):
		_histories[villager_id] = []
	_agent_request_id = ""
	_pending_history_index = -1
	_agent_stream_pending = false
	_is_open = true
	visible = true
	panel.visible = true
	name_label.text = str(_display_names[villager_id])
	_set_composer_enabled(true)
	status_label.text = "输入消息后按 Enter 发送，Shift+Enter 换行。"
	_render_history()
	message_input.grab_focus()
	return true


func get_agent_history(villager_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in (_histories.get(villager_id, []) as Array):
		result.append((entry as Dictionary).duplicate(true))
	return result


func start_dialogue(villager_id: String) -> void:
	var data := GameDataScript.get_villager(villager_id)
	open_agent_dialogue(villager_id, str(data.get("name", villager_id)))


func start_agent_dialogue(villager_id: String, speech: String) -> void:
	if not open_agent_dialogue(villager_id, villager_id):
		return
	_append_history(villager_id, "agent", speech.strip_edges())
	_render_history()


func begin_agent_dialogue(villager_id: String, request_id: String) -> void:
	if villager_id.is_empty() or request_id.is_empty():
		return
	if not _is_open or _current_villager_id != villager_id:
		open_agent_dialogue(villager_id, str(_display_names.get(villager_id, villager_id)))
	if not _agent_stream_pending:
		_pending_history_index = _append_history(villager_id, "agent", THINKING_TEXT)
		_agent_stream_pending = true
		_set_composer_enabled(false)
	_agent_request_id = request_id
	_render_history()


func append_agent_dialogue(request_id: String, delta: String) -> void:
	if request_id != _agent_request_id or not _agent_stream_pending or delta.is_empty():
		return
	var history := _current_history()
	if _pending_history_index < 0 or _pending_history_index >= history.size():
		return
	var entry := history[_pending_history_index] as Dictionary
	entry.text = delta if str(entry.text) == THINKING_TEXT else str(entry.text) + delta
	history[_pending_history_index] = entry
	_histories[_current_villager_id] = history
	_render_history()


func finish_agent_dialogue(request_id: String, speech: String) -> void:
	if request_id != _agent_request_id or not _agent_stream_pending:
		return
	var history := _current_history()
	if _pending_history_index >= 0 and _pending_history_index < history.size():
		var entry := history[_pending_history_index] as Dictionary
		var final_speech := speech.strip_edges()
		if final_speech.is_empty() or final_speech == "……":
			final_speech = str(entry.get("text", "")).strip_edges()
		if final_speech.is_empty() or final_speech == THINKING_TEXT:
			final_speech = "……"
		entry.text = final_speech
		history[_pending_history_index] = entry
		_histories[_current_villager_id] = history
	_finish_pending()
	_render_history()


func fail_agent_dialogue(request_id: String) -> bool:
	if request_id != _agent_request_id or not _agent_stream_pending:
		return false
	_set_pending_failure(FAILURE_TEXT)
	return true


func fail_agent_submission(villager_id: String, message: String = FAILURE_TEXT) -> bool:
	if villager_id != _current_villager_id or not _agent_stream_pending or not _agent_request_id.is_empty():
		return false
	_set_pending_failure(message)
	return true


func close() -> void:
	if not _is_open:
		return
	var closed_villager := _current_villager_id
	var closed_request := _agent_request_id
	var should_cancel := _agent_stream_pending and not closed_request.is_empty()
	_is_open = false
	visible = false
	panel.visible = false
	_current_villager_id = ""
	_agent_request_id = ""
	_pending_history_index = -1
	_agent_stream_pending = false
	message_input.text = ""
	_set_composer_enabled(true)
	if should_cancel:
		agent_dialogue_cancelled.emit(closed_villager, closed_request)
	agent_dialogue_closed.emit(closed_villager, closed_request)


func _submit_message() -> void:
	if not _is_open or _agent_stream_pending:
		return
	var message := message_input.text.strip_edges()
	if message.is_empty():
		status_label.text = "请输入消息。"
		return
	if message.length() > MAX_MESSAGE_LENGTH:
		status_label.text = "消息不能超过 %d 个字符。" % MAX_MESSAGE_LENGTH
		return
	_append_history(_current_villager_id, "player", message)
	_pending_history_index = _append_history(_current_villager_id, "agent", THINKING_TEXT)
	_agent_request_id = ""
	_agent_stream_pending = true
	message_input.text = ""
	_set_composer_enabled(false)
	status_label.text = THINKING_TEXT
	_render_history()
	agent_message_submitted.emit(_current_villager_id, message)


func _append_history(villager_id: String, role: String, text: String) -> int:
	var history := (_histories.get(villager_id, []) as Array).duplicate(true)
	history.append({"role": role, "text": text})
	_histories[villager_id] = history
	return history.size() - 1


func _current_history() -> Array:
	return (_histories.get(_current_villager_id, []) as Array).duplicate(true)


func _set_pending_failure(message: String) -> void:
	var history := _current_history()
	if _pending_history_index >= 0 and _pending_history_index < history.size():
		(history[_pending_history_index] as Dictionary).text = message
		_histories[_current_villager_id] = history
	_finish_pending()
	status_label.text = message
	_render_history()


func _finish_pending() -> void:
	_agent_stream_pending = false
	_agent_request_id = ""
	_pending_history_index = -1
	_set_composer_enabled(true)
	status_label.text = "可以继续交谈。"
	message_input.grab_focus()


func _set_composer_enabled(enabled: bool) -> void:
	message_input.editable = enabled
	send_button.disabled = not enabled


func _render_history() -> void:
	if _current_villager_id.is_empty():
		history_view.text = ""
		return
	var lines: PackedStringArray = []
	var display_name := str(_display_names.get(_current_villager_id, _current_villager_id))
	for entry_value in _histories.get(_current_villager_id, []):
		var entry := entry_value as Dictionary
		var speaker := "你" if str(entry.get("role", "")) == "player" else display_name
		lines.append("%s：%s" % [speaker, str(entry.get("text", ""))])
	history_view.text = "\n\n".join(lines)
	call_deferred("_scroll_history_to_end")


func _scroll_history_to_end() -> void:
	history_view.scroll_to_line(maxi(0, history_view.get_line_count() - 1))


func _on_message_input_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
		and not event.shift_pressed
	):
		_submit_message()
		message_input.accept_event()


func _input(event: InputEvent) -> void:
	if _is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
