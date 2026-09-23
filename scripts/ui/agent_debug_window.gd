class_name AgentDebugWindow
extends CanvasLayer
signal closed

@onready var close_button: Button = $Overlay/Center/Panel/Margin/Layout/Header/CloseButton
@onready var clear_button: Button = $Overlay/Center/Panel/Margin/Layout/Header/ClearButton
@onready var request_list: ItemList = $Overlay/Center/Panel/Margin/Layout/Body/RequestList
@onready var status_label: Label = $Overlay/Center/Panel/Margin/Layout/Body/Details/Status
@onready var input_view: TextEdit = $Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Input
@onready var reasoning_view: TextEdit = $Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Reasoning
@onready var output_view: TextEdit = $Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Output
@onready var handoff_view: TextEdit = $Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Handoffs

var _trace: Node
var _selected_request_id := ""
var _refresh_pending := false
var _reset_scroll_on_refresh := false
var _render_generation := 0
var _request_filter_enabled := false
var _request_filter: Array[String] = []
var _call_index := -1
var _follow_latest_call := true
var call_picker: OptionButton
var model_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	close_button.pressed.connect(close)
	clear_button.pressed.connect(clear)
	request_list.item_selected.connect(_on_request_selected)
	input_view.editable = false
	reasoning_view.editable = false
	output_view.editable = false
	handoff_view.editable = false
	handoff_view.add_theme_color_override("font_readonly_color", Color("d8e9df"))
	var details := status_label.get_parent()
	var call_bar := HBoxContainer.new()
	call_picker = OptionButton.new()
	call_picker.name = "CallPicker"
	call_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	call_picker.item_selected.connect(func(index: int):
		_call_index = index
		_follow_latest_call = false
		if _trace != null: _render_request(_trace.get_request(_selected_request_id), true))
	call_bar.add_child(call_picker)
	var copy := Button.new()
	copy.text = "复制请求"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(input_view.text))
	call_bar.add_child(copy)
	details.add_child(call_bar)
	details.move_child(call_bar, 1)
	model_label = Label.new()
	model_label.name = "ModelRoute"
	model_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(model_label)
	details.move_child(model_label, 2)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(input_view.get_parent() as TabContainer).set_tab_title(0, "Context / 原始请求")
	(input_view.get_parent() as TabContainer).set_tab_title(3, "行动指示")
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.timeout.connect(func():
		if visible and _trace != null and _trace.has_method("refresh_intent_debug"):
			_trace.refresh_intent_debug(_selected_request_id))
	add_child(timer)
	timer.start()


func show_requests(request_ids: Array[String], preferred_request_id: String = "") -> void:
	_request_filter_enabled = true
	_request_filter = request_ids.duplicate()
	clear_button.hide()
	if not preferred_request_id.is_empty() and preferred_request_id != _selected_request_id:
		_selected_request_id = preferred_request_id
		_call_index = -1
		_follow_latest_call = true
		_reset_scroll_on_refresh = true
	_schedule_refresh()


func configure(trace: Node) -> bool:
	if (
		trace == null
		or not trace.has_signal("trace_updated")
		or not trace.has_signal("trace_cleared")
		or not trace.has_method("get_requests")
	):
		return false
	if _trace != null and is_instance_valid(_trace):
		var update_callback := Callable(self, "_on_trace_updated")
		if _trace.is_connected("trace_updated", update_callback):
			_trace.disconnect("trace_updated", update_callback)
		var clear_callback := Callable(self, "_on_trace_cleared")
		if _trace.is_connected("trace_cleared", clear_callback):
			_trace.disconnect("trace_cleared", clear_callback)
	_trace = trace
	_trace.connect("trace_updated", Callable(self, "_on_trace_updated"))
	_trace.connect("trace_cleared", Callable(self, "_on_trace_cleared"))
	if visible:
		_refresh_list()
	return true


func open() -> void:
	visible = true
	_reset_scroll_on_refresh = true
	_refresh_list()
	if _trace != null and _trace.has_method("refresh_intent_debug"): _trace.refresh_intent_debug(_selected_request_id)


func close() -> void:
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func clear() -> void:
	if _trace != null and _trace.has_method("clear"):
		_trace.call("clear")


func _on_trace_updated(request_id: String) -> void:
	if _selected_request_id.is_empty():
		_selected_request_id = request_id
	_schedule_refresh()


func _on_trace_cleared() -> void:
	_selected_request_id = ""
	_schedule_refresh()


func _schedule_refresh() -> void:
	if not visible or _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_flush_trace_refresh")


func _flush_trace_refresh() -> void:
	_refresh_pending = false
	if visible:
		_refresh_list()


func _refresh_list() -> void:
	if request_list == null:
		return
	var requests: Array = [] if _trace == null else _trace.call("get_requests")
	if _request_filter_enabled:
		requests = requests.filter(func(record: Dictionary): return str(record.get("request_id", "")) in _request_filter)
	request_list.clear()
	var selected_index := -1
	for index in range(requests.size()):
		var record := requests[index] as Dictionary
		var request_id := str(record.get("request_id", ""))
		var label := _request_label(record)
		request_list.add_item(label)
		request_list.set_item_metadata(index, request_id)
		if request_id == _selected_request_id:
			selected_index = index
	if selected_index < 0 and not requests.is_empty():
		selected_index = requests.size() - 1
		_selected_request_id = str((requests[selected_index] as Dictionary).request_id)
		_call_index = -1
		_follow_latest_call = true
		_reset_scroll_on_refresh = true
	if selected_index >= 0:
		request_list.select(selected_index)
		_render_request(requests[selected_index], _reset_scroll_on_refresh)
	else:
		_render_request({}, _reset_scroll_on_refresh)
	_reset_scroll_on_refresh = false


func _on_request_selected(index: int) -> void:
	_selected_request_id = str(request_list.get_item_metadata(index))
	_call_index = -1
	_follow_latest_call = true
	if _trace != null and _trace.has_method("get_request"):
		_render_request(_trace.call("get_request", _selected_request_id), true)


func _render_request(record: Dictionary, reset_scroll: bool = false) -> void:
	var scroll_state := _capture_scroll_state(reset_scroll)
	# Read-only TextEdit.clear() resets the cached first visible line even when
	# the tab is hidden. Changing scroll_vertical alone does not reset that cache.
	for view: TextEdit in [input_view, reasoning_view, output_view, handoff_view]:
		view.clear()
	_render_generation += 1
	var generation := _render_generation
	if record.is_empty():
		status_label.text = "尚无 Agent 请求"
		input_view.text = ""
		reasoning_view.text = ""
		output_view.text = ""
		handoff_view.text = "尚无行动提取记录。"
		call_picker.clear()
		model_label.text = "等待实际模型请求；尚未发送的 context 不作预估。"
		call_deferred("_restore_scroll_state", scroll_state, generation)
		return
	status_label.text = _status_text(record)
	var calls: Array = record.get("provider_calls", [])
	if calls.is_empty() and not (record.get("input", {}) as Dictionary).is_empty():
		calls = [{"input": record.input, "output": record.get("output", {}), "route": {}}]
	call_picker.clear()
	for index in range(calls.size()):
		var call: Dictionary = calls[index]
		var phase := str(call.get("route", {}).get("phase", ""))
		var phase_name := str({"dialogue": "聊天回复", "extract_actions": "行动提取", "extract_intents":"异步意图提取", "summarize_chat": "聊天摘要"}.get(phase, "模型调用"))
		call_picker.add_item("%d · %s · %s" % [index + 1, phase_name, call.get("input", {}).get("model", "未提供模型")])
	if _follow_latest_call: _call_index = calls.size() - 1
	_call_index = mini(_call_index, calls.size() - 1)
	var selected: Dictionary = calls[_call_index] if _call_index >= 0 else {}
	if _call_index >= 0: call_picker.select(_call_index)
	var body: Dictionary = selected.get("input", {})
	var route: Dictionary = selected.get("route", {})
	var reported := str(selected.get("output", {}).get("model", selected.get("response_model", "")))
	model_label.text = "请求模型：%s    接口返回模型：%s\n目标地址：%s\n通道：%s    stream：%s    messages：%d" % [
		body.get("model", "等待发送"), reported if not reported.is_empty() else "尚未返回 / 接口未提供",
		route.get("endpoint", "此记录未提供地址"), route.get("channel", "未标记"), str(body.get("stream", false)), (body.get("messages", []) as Array).size()]
	if not reported.is_empty() and reported != str(body.get("model", "")):
		model_label.text += "\n注意：请求名与返回名不同，请核对服务端的模型别名或路由。"
	input_view.text = JSON.stringify(body, "\t")
	reasoning_view.text = str(record.get("reasoning", ""))
	output_view.text = JSON.stringify({
		"content": str(record.get("content", "")),
		"tool_call_deltas": record.get("tool_deltas", []),
		"provider_output": record.get("output", {}),
		"selected_call_output": selected.get("output", {}),
		"action_intent": record.get("final", {}),
		"error": record.get("error", {}),
		"cancellation": record.get("cancellation", {}),
		"loop_events": record.get("loop_events", []),
	}, "\t")
	if _trace.has_method("get_handoff_report"):
		var handoff: Dictionary = _trace.get_handoff_report(str(record.request_id))
		var summary: Array[String] = ["提取：" + str(handoff.get("extraction_status", "")), "交接：" + str(handoff.get("delivery_status", ""))]
		for instruction in handoff.get("accepted", []):
			summary.append("行动：%s · 地点 %s · 对象 %s · %s" % [instruction.get("activity", instruction.get("kind", "")), instruction.get("place", instruction.get("place_id", "")), instruction.get("target", instruction.get("target_actor_id", "")), instruction.get("status", "")])
		var destinations := {}
		for evidence in handoff.get("context_evidence", []):
			var destination := "%s · %s" % [evidence.get("action_request_id", ""), evidence.get("model", "")]
			if not destinations.has(destination): summary.append("已送入：" + destination)
			destinations[destination] = true
		var diagnostics: Dictionary = handoff.get("async_extraction", {})
		var details := ""
		if not diagnostics.is_empty():
			details += "\n\n原始聊天 messages\n" + _debug_messages(diagnostics.get("raw_messages", []))
			details += "\n\n准备的提取 prompt / messages（不代表请求已发出）\n" + _debug_messages(diagnostics.get("prepared_messages", []))
			for call in diagnostics.get("calls", []):
				details += "\n\n实际发送的提取 prompt / messages\n" + _debug_messages(call.get("input", {}).get("messages", []))
				details += "\n\n模型原始提取结果\n" + str(call.get("output", {}).get("message", {}).get("content", "尚未返回"))
			details += "\n\n校验结果\n" + JSON.stringify(diagnostics.get("validation"), "\t")
		handoff_view.text = "\n".join(summary) + details + "\n\n完整提取与交接记录（含错误和重试）\n" + JSON.stringify(handoff, "\t")
	call_deferred("_restore_scroll_state", scroll_state, generation)


func _debug_messages(messages: Array) -> String:
	var lines: Array[String] = []
	for message in messages:
		lines.append("[" + str(message.get("role", "")) + "]")
		var content := str(message.get("content", ""))
		var parser := JSON.new()
		var valid := parser.parse(content) == OK
		lines.append(JSON.stringify(parser.data, "\t") if valid and (parser.data is Dictionary or parser.data is Array) else content)
	return "\n".join(lines)


func _capture_scroll_state(reset_scroll: bool) -> Dictionary:
	var result := {}
	for view_value in [input_view, reasoning_view, output_view, handoff_view]:
		var view := view_value as TextEdit
		var scroll_bar := view.get_v_scroll_bar()
		if reset_scroll and view in [input_view, handoff_view]:
			result[view.name] = {"follow": false, "position": 0.0}
			continue
		result[view.name] = {
			"follow": reset_scroll or scroll_bar.value >= scroll_bar.max_value - scroll_bar.page - 0.5,
			"position": view.scroll_vertical,
		}
	return result


func _restore_scroll_state(state: Dictionary, generation: int) -> void:
	if generation != _render_generation:
		return
	for view_value in [input_view, reasoning_view, output_view, handoff_view]:
		var view := view_value as TextEdit
		var view_state := state.get(view.name, {}) as Dictionary
		var bar := view.get_v_scroll_bar()
		# Hidden tabs can still expose the previous scrollbar range before layout.
		var maximum := maxf(0.0, minf(bar.max_value - bar.page, float(view.get_total_visible_line_count() - 1)))
		if bool(view_state.get("follow", true)):
			view.scroll_vertical = maximum
		else:
			view.scroll_vertical = clampf(float(view_state.get("position", 0.0)), 0.0, maximum)


func _request_label(record: Dictionary) -> String:
	var parts := [
		str(record.get("agent_id", "Agent")),
		str(record.get("trigger", "request")),
		str(record.get("status", "streaming")),
	]
	var error_code := _error_code(record)
	if not error_code.is_empty():
		parts.append(error_code)
	return " · ".join(PackedStringArray(parts))


func _status_text(record: Dictionary) -> String:
	var parts := [
		str(record.get("agent_id", "Agent")),
		str(record.get("request_id", "")),
		str(record.get("status", "streaming")),
	]
	if record.get("status", "streaming") == "streaming":
		var events: Array = record.get("loop_events", [])
		for index in range(events.size() - 1, -1, -1):
			var event: Dictionary = events[index]
			if event.get("event") != "provider.status": continue
			var phase := str(event.get("phase", ""))
			parts.append("第 %d 轮 · %s" % [int(event.get("round", 0)), {"queued": "等待模型调用名额", "waiting_provider": "等待模型首条输出", "receiving": "正在接收模型输出", "round_completed": "本轮结束，处理工具结果"}.get(phase, phase)])
			break
	var error_code := _error_code(record)
	if not error_code.is_empty():
		parts.append(error_code)
	return " · ".join(PackedStringArray(parts))


func _error_code(record: Dictionary) -> String:
	var error: Variant = record.get("error", {})
	return str((error as Dictionary).get("code", "")) if error is Dictionary else ""


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
