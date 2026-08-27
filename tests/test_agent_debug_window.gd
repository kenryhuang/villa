extends RefCounted

const AgentDebugWindowScene = preload("res://scenes/ui/agent_debug_window.tscn")
const AgentSessionTraceScript = preload("res://scripts/ai_agent/agent_session_trace.gd")
const DebugPanelScene = preload("res://scenes/ui/debug_panel.tscn")
const DialogueScene = preload("res://scenes/ui/dialogue_ui.tscn")


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
	trace.accept_event(_event("content.delta", 5, {"delta": "你好，今天适合耕种。"}))
	trace.accept_event(_event("provider.output", 6, {"message": {"content": "你好，今天适合耕种。"}}))
	trace.accept_event(_event("stream.error", 7, {"code": "provider_error"}))
	await tree.process_frame
	var input := window.get_node("Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Input") as TextEdit
	var output := window.get_node("Overlay/Center/Panel/Margin/Layout/Body/Details/Tabs/Output") as TextEdit
	assertions.equal(list.item_count, 1, "Agent debug window lists one request")
	assertions.truthy(input.text.contains("test-model"), "Agent debug window shows raw input")
	assertions.equal(reasoning.text, "先查看农场。再检查库存。", "Agent debug window streams raw reasoning")
	assertions.truthy(output.text.contains("今天适合耕种"), "Agent debug window shows raw output")
	assertions.truthy(output.text.contains("provider_error"), "Agent debug window shows terminal error payload")
	window.toggle()
	assertions.truthy(not window.visible, "Agent debug window toggle closes")
	window.toggle()
	assertions.truthy(window.visible, "Agent debug window toggle opens")

	var debug_panel = DebugPanelScene.instantiate()
	tree.root.add_child(debug_panel)
	await tree.process_frame
	var requests: Array[bool] = []
	debug_panel.agent_debug_requested.connect(func(): requests.append(true))
	(debug_panel.get_node("Overlay/Center/Panel/Layout/Footer/AgentDebugButton") as Button).pressed.emit()
	assertions.equal(requests.size(), 1, "runtime debug panel requests Agent debug window")

	var dialogue = DialogueScene.instantiate()
	tree.root.add_child(dialogue)
	await tree.process_frame
	var cancelled: Array[String] = []
	dialogue.agent_dialogue_cancelled.connect(func(_agent_id: String, request_id: String): cancelled.append(request_id))
	dialogue.begin_agent_dialogue("farmer_ahe", "dialogue-1")
	assertions.equal(dialogue.text_label.text, "正在思考……", "streaming dialogue starts immediately")
	dialogue.append_agent_dialogue("dialogue-1", "你")
	dialogue.append_agent_dialogue("dialogue-1", "好")
	assertions.equal(dialogue.text_label.text, "你好", "dialogue appends content deltas")
	dialogue.close()
	assertions.equal(cancelled, ["dialogue-1"], "closing dialogue requests stream cancellation")

	dialogue.queue_free()
	debug_panel.queue_free()
	window.queue_free()
	trace.queue_free()
	await tree.process_frame


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
