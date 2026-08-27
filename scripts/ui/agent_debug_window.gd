class_name AgentDebugWindow
extends CanvasLayer

@onready var close_button: Button = $Overlay/Center/Panel/Margin/Layout/Header/CloseButton
@onready var clear_button: Button = $Overlay/Center/Panel/Margin/Layout/Header/ClearButton
@onready var request_list: ItemList = $Overlay/Center/Panel/Margin/Layout/Body/RequestList
@onready var status_label: Label = $Overlay/Center/Panel/Margin/Layout/Body/Details/Status
@onready var input_view: TextEdit = $Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Input
@onready var reasoning_view: TextEdit = $Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Reasoning
@onready var output_view: TextEdit = $Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Output

var _trace: Node
var _selected_request_id := ""


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	clear_button.pressed.connect(clear)
	request_list.item_selected.connect(_on_request_selected)
	input_view.editable = false
	reasoning_view.editable = false
	output_view.editable = false


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
	_refresh_list()
	return true


func open() -> void:
	visible = true
	_refresh_list()


func close() -> void:
	visible = false


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
	_refresh_list()


func _on_trace_cleared() -> void:
	_selected_request_id = ""
	_refresh_list()


func _refresh_list() -> void:
	if request_list == null:
		return
	var requests: Array = [] if _trace == null else _trace.call("get_requests")
	request_list.clear()
	var selected_index := -1
	for index in range(requests.size()):
		var record := requests[index] as Dictionary
		var request_id := str(record.get("request_id", ""))
		var label := "%s · %s · %s" % [
			str(record.get("agent_id", "Agent")),
			str(record.get("trigger", "request")),
			str(record.get("status", "streaming")),
		]
		request_list.add_item(label)
		request_list.set_item_metadata(index, request_id)
		if request_id == _selected_request_id:
			selected_index = index
	if selected_index < 0 and not requests.is_empty():
		selected_index = requests.size() - 1
		_selected_request_id = str((requests[selected_index] as Dictionary).request_id)
	if selected_index >= 0:
		request_list.select(selected_index)
		_render_request(requests[selected_index])
	else:
		_render_request({})


func _on_request_selected(index: int) -> void:
	_selected_request_id = str(request_list.get_item_metadata(index))
	if _trace != null and _trace.has_method("get_request"):
		_render_request(_trace.call("get_request", _selected_request_id))


func _render_request(record: Dictionary) -> void:
	if record.is_empty():
		status_label.text = "尚无 Agent 请求"
		input_view.text = ""
		reasoning_view.text = ""
		output_view.text = ""
		return
	status_label.text = "%s · %s · %s" % [
		str(record.get("agent_id", "Agent")),
		str(record.get("request_id", "")),
		str(record.get("status", "streaming")),
	]
	input_view.text = JSON.stringify(record.get("input", {}), "\t")
	reasoning_view.text = str(record.get("reasoning", ""))
	output_view.text = JSON.stringify({
		"content": str(record.get("content", "")),
		"tool_call_deltas": record.get("tool_deltas", []),
		"provider_output": record.get("output", {}),
		"action_intent": record.get("final", {}),
		"error": record.get("error", {}),
	}, "\t")
	call_deferred("_scroll_views_to_end")


func _scroll_views_to_end() -> void:
	for view in [input_view, reasoning_view, output_view]:
		var scroll_bar := (view as TextEdit).get_v_scroll_bar()
		(view as TextEdit).scroll_vertical = scroll_bar.max_value


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
