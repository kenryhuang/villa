extends RefCounted

const AgentDebugWindowScene = preload("res://scenes/ui/agent_debug_window.tscn")
const AgentSessionTraceScript = preload("res://scripts/ai_agent/agent_session_trace.gd")
const DebugPanelScene = preload("res://scenes/ui/debug_panel.tscn")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var trace = AgentSessionTraceScript.new()
	trace.configure(false, "debug-window-test")
	tree.root.add_child(trace)
	var window = AgentDebugWindowScene.instantiate()
	tree.root.add_child(window)
	await tree.process_frame
	assertions.truthy(window.configure(trace), "Agent debug window accepts session trace")
	trace.accept_event(_event("stream.started", 1, {"trigger": "dialogue"}))
	trace.accept_event(_event("provider.input", 2, {"model": "test-model", "messages": [{"role": "user", "content": "你好"}]}))
	var list := window.get_node("Overlay/Center/Panel/Margin/Layout/Body/RequestList") as ItemList
	assertions.equal(list.item_count, 0, "hidden Agent debug window does not render streamed deltas")
	window.open()
	assertions.equal(list.item_count, 1, "opening Agent debug window renders accumulated trace")
	var reasoning := window.get_node("Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Reasoning") as TextEdit
	trace.accept_event(_event("reasoning.delta", 3, {"delta": "先查看农场。"}))
	trace.accept_event(_event("reasoning.delta", 4, {"delta": "再检查库存。"}))
	assertions.equal(reasoning.text, "", "visible Agent debug deltas wait for one coalesced frame refresh")
	await tree.process_frame
	assertions.equal(reasoning.text, "先查看农场。再检查库存。", "coalesced refresh materializes every reasoning delta")
	var long_content := ""
	for index in range(160):
		long_content += "第 %03d 行调试输出\n" % index
	trace.accept_event(_event("content.delta", 5, {"delta": long_content}))
	await tree.process_frame
	await tree.process_frame
	var input := window.get_node("Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Input") as TextEdit
	var output := window.get_node("Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Output") as TextEdit
	var tabs := window.get_node("Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs") as TabContainer
	tabs.current_tab = 2
	await tree.process_frame
	assertions.truthy(output.get_v_scroll_bar().max_value > 1.0, "long Agent output creates a vertical scroll range")
	output.scroll_vertical = 0
	await tree.process_frame
	trace.accept_event(_event("content.delta", 6, {"delta": "末尾新增一行\n"}))
	trace.accept_event(_event("provider.output", 7, {"message": {"content": "请求失败前的输出"}}))
	trace.accept_event(_event("stream.error", 8, {"code": "provider_too_many_read_calls"}))
	await tree.process_frame
	await tree.process_frame
	assertions.equal(list.item_count, 1, "Agent debug window lists one request")
	assertions.truthy(input.text.contains("test-model"), "Agent debug window shows raw input")
	assertions.equal(reasoning.text, "先查看农场。再检查库存。", "Agent debug window streams raw reasoning")
	assertions.equal(output.scroll_vertical, 0, "manual upward scroll survives streamed trace refreshes")
	assertions.truthy(output.text.contains("请求失败前的输出"), "Agent debug window shows raw output")
	assertions.truthy(output.text.contains("provider_too_many_read_calls"), "Agent debug window shows terminal error payload")
	assertions.truthy(list.get_item_text(0).contains("provider_too_many_read_calls"), "request row exposes terminal error code")
	var status := window.get_node("Overlay/Center/Panel/Margin/Layout/Body/Details/Status") as Label
	assertions.truthy(status.text.contains("provider_too_many_read_calls"), "request status exposes terminal error code")
	window.toggle()
	assertions.truthy(not window.visible, "Agent debug window toggle closes")
	window.toggle()
	assertions.truthy(window.visible, "Agent debug window toggle opens")
	await _test_chat_calls(assertions, tree, trace, window)

	var debug_panel = DebugPanelScene.instantiate()
	tree.root.add_child(debug_panel)
	await tree.process_frame
	var requests: Array[bool] = []
	debug_panel.agent_debug_requested.connect(func(): requests.append(true))
	(debug_panel.get_node("Overlay/Center/Panel/Layout/Footer/AgentDebugButton") as Button).pressed.emit()
	assertions.equal(requests.size(), 1, "runtime debug panel requests Agent debug window")

	debug_panel.queue_free()
	window.queue_free()
	trace.queue_free()
	await tree.process_frame


func _test_chat_calls(assertions: TestAssert, tree: SceneTree, trace: Node, window: CanvasLayer) -> void:
	trace.configure(false, "debug-calls")
	var ids: Array[String] = ["request-1"]
	window.show_requests(ids, "request-1")
	trace.accept_event(_event("stream.started", 1, {"trigger": "dialogue"}))
	trace.accept_event(_event("loop.trace", 2, {"event": "provider.route", "phase": "dialogue", "channel": "chat", "endpoint": "http://127.0.0.1:11434/v1/chat/completions"}))
	trace.accept_event(_event("provider.input", 3, {"model": "cydonia-requested", "stream": true, "messages": [{"role": "system", "content": "CHAT_PERSONA"}]}))
	trace.accept_event(_event("loop.trace", 4, {"event": "provider.response_model", "model": "cydonia-returned"}))
	await tree.process_frame
	assertions.truthy(window.model_label.text.contains("cydonia-requested") and window.model_label.text.contains("cydonia-returned"), "Shows requested and reported model while streaming")
	assertions.truthy(window.model_label.text.contains("11434/v1/chat/completions"), "Shows actual provider endpoint")
	trace.accept_event(_event("provider.output", 5, {"model": "cydonia-returned", "message": {"content": "hello"}}))
	trace.accept_event(_event("loop.trace", 6, {"event": "provider.route", "phase": "extract_actions", "channel": "chat"}))
	trace.accept_event(_event("provider.input", 7, {"model": "cydonia-requested", "messages": [{"role": "system", "content": "EXTRACT_ACTIONS"}]}))
	await tree.process_frame
	assertions.equal(window.call_picker.item_count, 2, "Both inputs appear before extraction finishes")
	assertions.truthy(window.input_view.text.contains("EXTRACT_ACTIONS"), "Follows current extraction input")
	window.call_picker.select(0)
	window.call_picker.item_selected.emit(0)
	assertions.truthy(window.input_view.text.contains("CHAT_PERSONA") and not window.input_view.text.contains("EXTRACT_ACTIONS"), "Earlier chat context is not overwritten by extraction")
	trace.accept_event(_event("loop.trace", 8, {"event": "chat.timing"}))
	await tree.process_frame
	assertions.equal(window.call_picker.selected, 0, "Manual call selection survives streaming updates")
	var other := _event("stream.started", 1, {"trigger": "schedule"})
	other.data.request_id = "action-request"
	trace.accept_event(other)
	await tree.process_frame
	assertions.equal(window.request_list.item_count, 1, "Chat debug filters unrelated action loops")
	trace.finish_cancelled("farmer_ahe", "request-1", "closed")
	var record: Dictionary = trace.get_request("request-1")
	assertions.equal(trace._disk_record(record).response.provider_calls.size(), 2, "Cancellation persists every input even without final output")


func _event(name: String, sequence: int, payload: Dictionary) -> Dictionary:
	return {
		"event": name,
		"data": {
			"protocol_version": 1,
			"stream_id": "request-1:stream",
			"request_id": "request-1",
			"agent_id": "farmer_ahe",
			"sequence": sequence,
			"timestamp_msec": 1000 + sequence,
			"payload": payload,
		},
	}
