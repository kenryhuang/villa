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
	await _test_handoff_trace(assertions, tree, trace, window)
	await _test_async_intents(assertions, tree, trace, window)

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


func _test_async_intents(assertions: TestAssert, tree: SceneTree, trace: Node, window: CanvasLayer) -> void:
	trace.configure(false, "async-intents")
	var ids: Array[String] = ["request-1"]
	window.show_requests(ids, "request-1")
	trace.accept_event(_event("stream.started", 1, {"trigger":"dialogue"}))
	trace.accept_event(_event("provider.input", 2, {"model":"chat", "messages":[{"role":"user","content":"去钓鱼吗？"}]}))
	trace.accept_event(_event("loop.trace", 3, {"event":"chat.intent_queued"}))
	trace.accept_event(_event("decision.final", 4, {"chat_isolated":true,"speech":"好。"}))
	trace.accept_event(_event("stream.completed", 5, {"status":"completed"}))
	assertions.truthy(trace.get_handoff_report("request-1").extraction_status.contains("排队"), "Queued async work is not reported as an empty model result")
	var messages := [{"role":"system","content":"EXTRACTION_PROMPT"},{"role":"user","content":"RAW_LATEST_PAIR"}]
	var accepted := [{"kind":"activity","status":"confirmed","place":"南湖","activity":"钓鱼","target":"玩家"}]
	var snapshot := {"request_id":"request-1","agent_id":"farmer_ahe","status":"completed","error":"","accepted":accepted,"archived":true,"consumed":false,
		"raw_messages":[{"role":"user","content":"RAW_PLAYER"},{"role":"assistant","content":"RAW_REPLY"}],"prepared_messages":messages,
		"validation":{"accepted":accepted,"error":null},"calls":[{"route":{"phase":"extract_intents","channel":"chat"},"input":{"model":"chat","messages":messages},"output":{"message":{"content":"RAW_EXTRACTED_JSON"}}}]}
	assertions.truthy(trace.accept_intent_debug("request-1", snapshot), "Extraction can update a terminal chat trace")
	await tree.process_frame
	assertions.equal(window.call_picker.item_count, 2, "Async extraction appears beside the original chat call")
	for text in ["EXTRACTION_PROMPT","RAW_PLAYER","RAW_REPLY","RAW_EXTRACTED_JSON","校验结果"]:
		assertions.truthy(window.handoff_view.text.contains(text), "Extraction tab displays " + text)
	assertions.equal(trace.get_request("request-1").final.speech,"好。","Diagnostics never overwrite the chat reply")
	assertions.equal(trace._disk_record(trace.get_request("request-1")).response.provider_calls.size(),2,"Materializing async trace is idempotent")
	var wrong: Dictionary = snapshot.duplicate(true)
	wrong.agent_id = "lao_li"
	assertions.truthy(not trace.accept_intent_debug("request-1",wrong),"Cross-actor diagnostics are rejected")
	var entry := {"event_id":"chat-intents:request-1","intents":accepted}
	var input := _event("provider.input", 1, {"model":"action", "messages":[{"role":"user","content":JSON.stringify({"turn":{"trigger":"schedule","confirmed_dialogue":[entry]}})}]})
	input.data.request_id = "async-action"
	trace.accept_event(input)
	assertions.truthy(trace.get_handoff_report("request-1").delivery_status.contains("已写入实际"),"Async intention links to actual action model context")
	var callbacks: Array[Callable] = []
	trace.intent_debug_fetcher = func(_actor: String, _request: String, callback: Callable) -> bool:
		callbacks.append(callback)
		return true
	trace.refresh_intent_debug("request-1")
	trace.refresh_intent_debug("request-1")
	assertions.equal(callbacks.size(),1,"Polling does not overlap requests")
	trace.clear()
	callbacks[0].call(true,snapshot,"")
	assertions.truthy(trace.get_requests().is_empty(),"Late diagnostic fetch cannot resurrect cleared traces")
	trace.intent_debug_fetcher = Callable()


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


func _test_handoff_trace(assertions: TestAssert, tree: SceneTree, trace: Node, window: CanvasLayer) -> void:
	trace.configure(false, "handoff-trace")
	var ids: Array[String] = ["request-1"]
	window.show_requests(ids, "request-1")
	var handoff := {"kind":"visit", "status":"agreed", "target_actor_id":"player", "place_id":"greenhouse:12:8", "item_id":"", "quantity":0, "gold":0, "delay_minutes":0, "trade_side":"none", "building_type":"", "plot":-1}
	trace.accept_event(_event("stream.started", 1, {"trigger":"dialogue"}))
	trace.accept_event(_event("loop.trace", 2, {"event":"provider.route", "phase":"extract_actions", "channel":"chat"}))
	trace.accept_event(_event("provider.input", 3, {"model":"chat-model", "messages":[]}))
	trace.accept_event(_event("provider.output", 4, {"message":{"content":JSON.stringify({"handoffs":[handoff]})}}))
	trace.accept_event(_event("loop.trace", 5, {"event":"chat.extraction_result", "candidates":[handoff], "accepted":[handoff], "rejected":[]}))
	trace.accept_event(_event("loop.trace", 6, {"event":"chat.handoff_archived", "source_event_id":"dialogue:request-1"}))
	trace.accept_event(_event("decision.final", 7, {"chat_isolated":true, "chat_handoffs":[handoff]}))
	trace.accept_event(_event("stream.completed", 8, {}))
	trace.record_action_event("request-1", "chat.handoff_pending", {"reason":"等待：自主规划每日额度已用尽（16/16）"})
	await tree.process_frame
	var report: Dictionary = trace.get_handoff_report("request-1")
	assertions.equal(report.accepted, [handoff], "Handoff report retains validated instructions")
	assertions.truthy(report.archived and report.context_evidence.is_empty(), "Archiving and queuing do not claim model context delivery")
	assertions.truthy(report.delivery_status.contains("16/16"), "Daily-budget blocking reason is visible")
	assertions.truthy(window.handoff_view.text.contains("greenhouse:12:8") and window.handoff_view.text.contains("chat-model"), "New tab shows extracted instruction and raw extraction output")
	var entry := {"event_id":"dialogue:request-1", "kind":"dialogue", "game_minute":10, "payload":{"handoff_version":1, "handoffs":[handoff]}}
	var started := _event("stream.started", 1, {"trigger":"event"})
	started.data.request_id = "action-1"
	trace.accept_event(started)
	var review := _event("loop.trace", 2, {"event":"dialogue.handoff_review", "source_event_ids":[entry.event_id]})
	review.data.request_id = "action-1"
	trace.accept_event(review)
	assertions.truthy(trace.get_handoff_report("request-1").context_evidence.is_empty(), "Review marker alone is not actual input evidence")
	var input := _event("provider.input", 3, {"model":"action-model", "messages":[{"role":"system", "content":"Rules"}, {"role":"user", "content":JSON.stringify({"turn":{"trigger":"event", "dialogue_followups":[entry]}})}]})
	input.data.request_id = "action-1"
	trace.accept_event(input)
	await tree.process_frame
	report = trace.get_handoff_report("request-1")
	assertions.equal(report.context_evidence.size(), 1, "Action input links back to the completed chat request")
	assertions.equal(report.context_evidence[0].context_entry, JSON.parse_string(JSON.stringify(entry)), "Evidence is the exact entry from the actual model messages")
	assertions.truthy(report.context_evidence[0].action_request_id == "action-1" and report.context_evidence[0].model == "action-model", "Evidence names destination request and model")
	assertions.truthy(report.delivery_status.contains("已写入实际"), "Delivered status requires provider input")
	assertions.equal(window.request_list.item_count, 1, "Chat-filtered debug does not need to expose other request rows")
	assertions.truthy(window.handoff_view.text.contains("action-1") and window.handoff_view.text.contains("turn.dialogue_followups"), "Filtered chat view refreshes when action context arrives")
	assertions.equal(trace.get_handoff_report("action-1").context_evidence[0].context_entry, JSON.parse_string(JSON.stringify(entry)), "Action request view exposes the same received evidence")
	if "--capture-handoff-ui" in OS.get_cmdline_user_args():
		(window.input_view.get_parent() as TabContainer).current_tab = 3
		window.handoff_view.scroll_vertical = 0
		for frame in 5: await tree.process_frame
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png("res://tmp/handoff-trace-ui.png")
	# Empty and invalid extractions must be distinguishable from waiting on dispatch.
	trace.configure(false, "handoff-empty")
	trace.accept_event(_event("stream.started", 1, {"trigger":"dialogue"}))
	trace.accept_event(_event("decision.final", 2, {"chat_isolated":true, "chat_handoffs":[], "chat_extraction_failed":false}))
	assertions.truthy(trace.get_handoff_report("request-1").extraction_status.contains("空数组"), "Empty extraction is explicitly identified")
	trace.accept_event(_event("loop.trace", 3, {"event":"chat.extraction_failed", "reason":"invalid_json"}))
	assertions.truthy(trace.get_handoff_report("request-1").extraction_status.contains("失败"), "Malformed JSON has a different status than no intention")
	var rejected := _event("loop.trace", 4, {"event":"chat.handoff_prepared", "accepted_event_ids":[], "rejected_event_ids":["dialogue:request-1"]})
	rejected.data.request_id = "rejected-action"
	trace.accept_event(rejected)
	assertions.truthy(trace.get_handoff_report("request-1").delivery_status.contains("拒绝"), "Server trust rejection is linked to the source chat")
