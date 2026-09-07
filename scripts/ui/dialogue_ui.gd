class_name DialogueUI
extends Control

signal agent_message_submitted(villager_id: String, message: String)
signal agent_dialogue_opened(villager_id: String)
signal agent_dialogue_cancelled(villager_id: String, request_id: String)
signal agent_dialogue_closed(villager_id: String, request_id: String)
signal interaction_response_requested(agent_id: String, interaction_id: String, response: String, counter_terms: Dictionary)

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MAX_MESSAGE_LENGTH := 1000
const THINKING_TEXT := "正在思考……"
const FAILURE_TEXT := "Agent 服务暂时不可用，请稍后再试。"

@onready var panel: PanelContainer = $DialoguePanel
@onready var name_label: Label = $DialoguePanel/Margin/VBox/Header/NameLabel
@onready var history_view: RichTextLabel = $DialoguePanel/Margin/VBox/History
@onready var interaction_scroll: ScrollContainer = $DialoguePanel/Margin/VBox/InteractionScroll
@onready var interaction_cards: VBoxContainer = $DialoguePanel/Margin/VBox/InteractionScroll/InteractionCards
@onready var status_label: Label = $DialoguePanel/Margin/VBox/Status
@onready var message_input: TextEdit = $DialoguePanel/Margin/VBox/Composer/MessageInput
@onready var send_button: Button = $DialoguePanel/Margin/VBox/Composer/SendButton
@onready var close_button: Button = $DialoguePanel/Margin/VBox/Header/CloseButton

var _histories: Dictionary = {}
var _interaction_views: Dictionary = {}
var _display_names: Dictionary = {}
var _current_villager_id := ""
var _agent_request_id := ""
var _pending_history_index := -1
var _agent_stream_pending := false
var _is_open := false


# Shared binding used by the 3D farm; the original dialogue/history UI is retained.
func configure_agent_runtime(runtime: Node) -> void:
	agent_message_submitted.connect(func(id: String, message: String):
		if not runtime.trigger_dialogue(id, message): fail_agent_submission(id))
	runtime.dialogue_stream_started.connect(func(id: String, request_id: String):
		if _is_open and id == _current_villager_id: begin_agent_dialogue(id, request_id))
	runtime.dialogue_stream_delta.connect(func(_id: String, request_id: String, delta: String): append_agent_dialogue(request_id, delta))
	runtime.dialogue_ready.connect(func(id: String, request_id: String, speech: String):
		finish_agent_dialogue(request_id, speech)
		set_agent_interactions(id, runtime.get_player_interactions(id)))
	runtime.dialogue_stream_failed.connect(func(_id: String, request_id: String, _error: String): fail_agent_dialogue(request_id))
	agent_dialogue_cancelled.connect(func(id: String, request_id: String): runtime.cancel_dialogue(id, request_id))
	agent_dialogue_closed.connect(func(id: String, request_id: String): runtime.cancel_dialogue(id, request_id))
	interaction_response_requested.connect(func(id: String, interaction_id: String, response: String, terms: Dictionary):
		var result: Dictionary = runtime.respond_to_player_interaction(id, interaction_id, response, terms)
		set_agent_interactions(id, runtime.get_player_interactions(id))
		status_label.text = "操作已确认，请查看条款状态。" if result.get("ok", false) else "未能完成：" + _failure_reason(str(result.get("error", "transaction_failed"))))


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
	_render_interactions()
	agent_dialogue_opened.emit(villager_id)
	message_input.grab_focus()
	return true


func get_agent_history(villager_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in (_histories.get(villager_id, []) as Array):
		result.append((entry as Dictionary).duplicate(true))
	return result


func set_agent_interactions(villager_id: String, interactions: Array) -> void:
	var normalized: Array[Dictionary] = []
	for value in interactions:
		if value is Dictionary:
			normalized.append((value as Dictionary).duplicate(true))
	_interaction_views[villager_id] = normalized
	if _is_open and _current_villager_id == villager_id:
		_render_interactions()


func get_agent_interactions(villager_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _interaction_views.get(villager_id, []):
		result.append((value as Dictionary).duplicate(true))
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


func _render_interactions() -> void:
	for child in interaction_cards.get_children():
		interaction_cards.remove_child(child)
		child.queue_free()
	var records: Array = _interaction_views.get(_current_villager_id, []).duplicate()
	records.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_open := str(a.get("status", "")) in ["open", "proposed", "negotiating"]
		var b_open := str(b.get("status", "")) in ["open", "proposed", "negotiating"]
		return a_open and not b_open if a_open != b_open else str(a.get("offer_id", a.get("agreement_id", ""))) > str(b.get("offer_id", b.get("agreement_id", ""))))
	interaction_scroll.visible = not records.is_empty()
	for record_value in records:
		var record := record_value as Dictionary
		var interaction_id := str(record.get("interaction_id", record.get("offer_id", record.get("agreement_id", ""))))
		if interaction_id.is_empty():
			continue
		var card := PanelContainer.new()
		card.name = "InteractionCard"
		var content := VBoxContainer.new()
		card.add_child(content)
		var title := Label.new()
		title.name = "TermsLabel"
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.text = _interaction_title(record) + "\n" + _terms_text(record)
		content.add_child(title)
		var actions := HBoxContainer.new()
		actions.name = "Actions"
		content.add_child(actions)
		var actionable := str(record.get("status", "")) in ["open", "proposed", "negotiating"]
		var is_trade := record.has("offer_id")
		var player_is_recipient := not is_trade or str(record.get("recipient_id", "player")) == "player"
		var player_already_accepted := not is_trade and "player" in (record.get("accepted_by", []) as Array)
		for definition in [["AcceptButton", "接受", "accept"], ["RejectButton", "拒绝", "reject"]]:
			var button := Button.new()
			button.name = str(definition[0])
			button.text = str(definition[1])
			button.disabled = not actionable or (str(definition[2]) == "accept" and (not player_is_recipient or player_already_accepted))
			button.pressed.connect(_request_interaction_response.bind(interaction_id, str(definition[2]), {}))
			actions.add_child(button)
		var counter_button := Button.new()
		counter_button.name = "CounterButton"
		counter_button.text = "还价"
		counter_button.disabled = not actionable or not player_is_recipient
		actions.add_child(counter_button)
		var counter_editor := _build_counter_editor(interaction_id, record)
		content.add_child(counter_editor)
		counter_button.pressed.connect(func(): counter_editor.visible = not counter_editor.visible)
		interaction_cards.add_child(card)


func _interaction_title(record: Dictionary) -> String:
	var status := str(record.get("status", "unknown"))
	status = {"open": "待确认", "proposed": "待确认", "negotiating": "协商中", "accepted": "已接受", "settled": "已成交", "completed": "已完成", "cancelled": "已取消", "rejected": "已拒绝", "expired": "已过期", "active": "履行中"}.get(status, status)
	if record.has("offer_id"):
		return "交易报价 · %s" % status
	return "合作协议 · %s" % status


func _bundle_text(bundle: Dictionary) -> String:
	var parts: Array[String] = []
	for id in bundle.get("items", {}):
		var item: Variant = GameDataScript.get_item(str(id))
		parts.append("%s ×%d" % [str(item.get("name", id)) if item is Dictionary else str(id), int(bundle.items[id])])
	if int(bundle.get("gold", 0)) > 0:
		parts.append("金币 %d" % int(bundle.gold))
	return "、".join(parts) if not parts.is_empty() else "无"


func _terms_text(record: Dictionary) -> String:
	var lines: Array[String] = []
	if record.has("offer_id"):
		var own := str(record.get("proposer_id", "")) == "player"
		lines.append("你提供：" + _bundle_text(record.get("proposer_gives", {}) if own else record.get("proposer_receives", {})))
		lines.append("你获得：" + _bundle_text(record.get("proposer_receives", {}) if own else record.get("proposer_gives", {})))
		lines.append("有效时间：剩余 %d 游戏分钟" % maxi(0, int(record.get("expires_game_minute", 0)) - _current_game_minute(record)))
	else:
		for entry in record.get("commitments", []):
			var actor := str(entry.get("participant_id", ""))
			lines.append("%s投入：%s" % ["你" if actor == "player" else _display_names.get(actor, actor), _bundle_text(entry)])
		lines.append("截止：剩余 %d 游戏分钟" % maxi(0, int(record.get("deadline", 0)) - _current_game_minute(record)))
		for actor in record.get("reward_split", {}):
			lines.append("%s收益权重：%d" % ["你" if actor == "player" else _display_names.get(actor, actor), int(record.reward_split[actor])])
	if not str(record.get("note", "")).is_empty():
		lines.append(str(record.note))
	return "\n".join(lines)


func _failure_reason(code: String) -> String:
	return {"insufficient_resources": "物品或金币不足", "player_assets_changed": "你的物品或金币不足，交易未成交", "proposer_assets_changed": "对方资产已变化，交易未成交", "insufficient_gold": "金币不足", "offer_expired": "报价已过期", "offer_not_open": "报价已失效", "interaction_not_found": "该提案已不存在", "stale_terms": "条款已更新，请重新确认"}.get(code, "条款或资产状态已变化（%s）" % code)


func _request_interaction_response(interaction_id: String, response: String, terms: Dictionary) -> void:
	if not _is_open or _current_villager_id.is_empty():
		return
	interaction_response_requested.emit(_current_villager_id, interaction_id, response, terms if response == "counter" else {})


func _build_counter_editor(interaction_id: String, record: Dictionary) -> VBoxContainer:
	var editor := VBoxContainer.new()
	editor.name = "CounterEditor"
	editor.visible = false
	var fields: Dictionary = {}
	if record.has("offer_id"):
		var player_is_proposer := str(record.get("proposer_id", "")) == "player"
		var give: Dictionary = (record.get("proposer_gives", {}) if player_is_proposer else record.get("proposer_receives", {})).duplicate(true)
		var receive: Dictionary = (record.get("proposer_receives", {}) if player_is_proposer else record.get("proposer_gives", {})).duplicate(true)
		fields.give = {}
		fields.receive = {}
		_add_bundle_editor(editor, "你提供", "Give", give, fields.give)
		_add_bundle_editor(editor, "你获得", "Receive", receive, fields.receive)
		fields.expiry = _add_number_field(editor, "有效时间（游戏分钟）", "CounterExpiryMinutes", maxi(1, int(record.get("expires_game_minute", 1)) - _current_game_minute(record)), 1, 10080)
	else:
		var deadline_remaining := maxi(60, int(record.get("deadline", 60)) - _current_game_minute(record))
		fields.deadline = _add_number_field(editor, "截止时间（游戏分钟）", "CounterDeadlineMinutes", deadline_remaining, 60, 10080)
		fields.commitments = {}
		for commitment_value in record.get("commitments", []):
			var commitment := commitment_value as Dictionary
			var participant_id := str(commitment.get("participant_id", ""))
			var bundle_fields: Dictionary = {}
			_add_bundle_editor(editor, "%s 承诺" % participant_id, "Commitment_%s" % participant_id, {"items": commitment.get("items", {}), "gold": commitment.get("gold", 0)}, bundle_fields)
			fields.commitments[participant_id] = bundle_fields
		fields.rewards = {}
		for participant_id_value in (record.get("reward_split", {}) as Dictionary):
			var participant_id := str(participant_id_value)
			fields.rewards[participant_id] = _add_number_field(editor, "%s 奖励权重" % participant_id, "CounterReward_%s" % _safe_node_part(participant_id), int(record.reward_split[participant_id_value]), 1, 1000)
	var note := LineEdit.new()
	note.name = "CounterNote"
	note.placeholder_text = "还价说明（可选）"
	editor.add_child(note)
	fields.note = note
	var buttons := HBoxContainer.new()
	var submit := Button.new()
	submit.name = "SubmitCounterButton"
	submit.text = "提交还价"
	submit.pressed.connect(_submit_counter.bind(interaction_id, record.duplicate(true), fields, editor))
	buttons.add_child(submit)
	var cancel := Button.new()
	cancel.name = "CancelCounterButton"
	cancel.text = "取消"
	cancel.pressed.connect(func(): editor.visible = false)
	buttons.add_child(cancel)
	editor.add_child(buttons)
	return editor


func _add_bundle_editor(parent: VBoxContainer, label_text: String, prefix: String, bundle: Dictionary, fields: Dictionary) -> void:
	var heading := Label.new()
	heading.text = label_text
	parent.add_child(heading)
	fields.gold = _add_number_field(parent, "金币", "Counter%sGold" % prefix, int(bundle.get("gold", 0)), 0, 999999)
	fields.items = {}
	for item_id_value in (bundle.get("items", {}) as Dictionary):
		var item_id := str(item_id_value)
		var input := _add_number_field(parent, item_id, "Counter%sItem_%s" % [prefix, _safe_node_part(item_id)], int(bundle.items[item_id_value]), 0, 9999)
		input.set_meta("item_id", item_id)
		fields.items[item_id] = input


func _add_number_field(parent: VBoxContainer, label_text: String, node_name: String, initial: int, minimum: int, maximum: int) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var input := SpinBox.new()
	input.name = node_name
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.value = initial
	row.add_child(input)
	parent.add_child(row)
	return input


func _submit_counter(interaction_id: String, record: Dictionary, fields: Dictionary, editor: VBoxContainer) -> void:
	var terms: Dictionary
	if record.has("offer_id"):
		terms = {
			"give": _bundle_from_fields(fields.give),
			"receive": _bundle_from_fields(fields.receive),
			"expires_in_minutes": int((fields.expiry as SpinBox).value),
			"counter_note": str((fields.note as LineEdit).text),
		}
	else:
		var commitments: Array[Dictionary] = []
		for participant_id in fields.commitments:
			var bundle := _bundle_from_fields(fields.commitments[participant_id])
			commitments.append({"participant_id": str(participant_id), "items": bundle.items, "gold": bundle.gold})
		commitments.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.participant_id) < str(right.participant_id))
		var rewards: Dictionary = {}
		for participant_id in fields.rewards:
			rewards[str(participant_id)] = int((fields.rewards[participant_id] as SpinBox).value)
		var counter_note := str((fields.note as LineEdit).text)
		terms = {"revised_terms": {"commitments": commitments, "reward_split": rewards, "deadline_minutes": int((fields.deadline as SpinBox).value), "note": counter_note}, "counter_note": counter_note}
	editor.visible = false
	_request_interaction_response(interaction_id, "counter", terms)


func _bundle_from_fields(fields: Dictionary) -> Dictionary:
	var items: Dictionary = {}
	for item_id in fields.get("items", {}):
		var quantity := int((fields.items[item_id] as SpinBox).value)
		if quantity > 0:
			items[str(item_id)] = quantity
	return {"items": items, "gold": int((fields.gold as SpinBox).value)}


func _current_game_minute(_record: Dictionary) -> int:
	# The authority revalidates the submitted relative deadline. The UI does not
	# own the clock, so saved cards may optionally include their snapshot minute.
	return int(_record.get("snapshot_game_minute", 0))


func _safe_node_part(value: String) -> String:
	return value.replace("/", "_").replace(":", "_").replace(".", "_")


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
