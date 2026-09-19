extends SceneTree

const State = preload("res://scripts/ai_agent/agent_loop_state.gd")
var checks := 0
var failures := 0

class Registry extends RefCounted:
	func get_agent_ids() -> Array:
		return ["farmer_ahe", "lao_li", "xuezhe_lin", "ashui", "tiejiang", "village_public"]

class Runtime extends Node:
	signal dialogue_stream_started(actor: String, request_id: String)
	signal dialogue_stream_delta(actor: String, request_id: String, delta: String)
	signal dialogue_ready(actor: String, request_id: String, speech: String)
	signal dialogue_stream_failed(actor: String, request_id: String, error: String)
	var registry = Registry.new()
	var calls: Array = []
	var cancelled: Array = []
	var resets: Array = []
	var reset_callbacks: Array[Callable] = []
	func reset_chat_context(id: String, room: Dictionary, callback: Callable) -> bool:
		resets.append({"actor": id, "room": room.duplicate(true)})
		reset_callbacks.append(callback)
		return true
	var trace = preload("res://scripts/ai_agent/agent_session_trace.gd").new()
	func _ready() -> void:
		add_child(trace)
		trace.configure(false, "chat-ui-test")
	func get_session_trace() -> Node: return trace
	func get_agent_display_name(id: String) -> String: return id
	func trigger_dialogue(_id: String, _text: String) -> bool: return true
	func trigger_chat(id: String, text: String, room: Dictionary) -> bool:
		var request := "request-%d" % calls.size()
		calls.append({"actor":id,"text":text,"room":room,"request":request})
		dialogue_stream_started.emit(id, request)
		return true
	func get_player_interactions(_id: String) -> Array: return []
	func dialogue_unavailable_reason() -> String: return "unavailable"
	func cancel_chat_turn(id: String) -> void: cancelled.append(id)
	func cancel_dialogue(_id: String, _request: String) -> bool: return true
	func respond_to_player_interaction(_id: String, _interaction: String, _response: String, _terms: Dictionary) -> Dictionary: return {"ok":true}

func _initialize() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(30).timeout.connect(func(): push_error("Split chat tests timed out"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var runtime := Runtime.new()
	root.add_child(runtime)
	var ui = load("res://scenes/ui/dialogue_ui.tscn").instantiate()
	root.add_child(ui)
	ui.configure_agent_runtime(runtime)
	ui.open_agent_dialogue("farmer_ahe", "阿禾")
	check(ui.has_node("DialoguePanel/Margin/VBox/Header/ChatDebugButton"), "Dialogue header exposes model/context debug")
	ui.get_node("DialoguePanel/Margin/VBox/Header/ChatDebugButton").pressed.emit()
	check(ui._chat_debug.visible, "Debug opens from dialogue without cancelling chat")
	ui._append_history("farmer_ahe", "player", "PRIVATE_SENTINEL")
	var group = ui._group
	group.picker.select(0)
	group.add_selected()
	var room: String = group.key()
	check(group.members.size() == 2, "Picker adds a second NPC")
	check(ui._current_history().is_empty(), "Group does not copy private chat")
	ui.message_input.text = "大家好"
	ui.send_button.pressed.emit()
	check(runtime.calls.size() == 1 and group.active and ui.send_button.disabled, "Only first member starts; composer locked")
	check(group.add_button.disabled and group.private_button.disabled, "Membership cannot change in flight")
	var first: Dictionary = runtime.calls[0]
	check(first.request in ui._chat_debug._request_filter, "Debug follows first group speaker request")
	runtime.dialogue_stream_delta.emit(first.actor, first.request, "第一位回复")
	check(ui._current_history()[1].text == "第一位回复" and ui._agent_stream_pending, "Delta is visible before final reply")
	var full_reply := "第一位回复" + "完整句子。".repeat(150)
	runtime.dialogue_stream_delta.emit(first.actor, first.request, "完整句子。".repeat(150))
	runtime.dialogue_ready.emit(first.actor, first.request, full_reply)
	check(ui._current_history()[1].text == full_reply, "Final reply retains streamed text beyond 500 characters")
	await process_frame
	check(runtime.calls.size() == 2, "Next member starts after previous completion")
	var second: Dictionary = runtime.calls[1]
	check(second.request in ui._chat_debug._request_filter and first.request in ui._chat_debug._request_filter, "Debug retains both group speaker requests")
	check(second.actor != first.actor and second.room == first.room, "Members share room and turn IDs")
	runtime.dialogue_ready.emit(second.actor, second.request, "第二位回复")
	await process_frame
	check(not group.active and not ui.send_button.disabled, "Round finishes and releases composer")
	var history: Array = ui._current_history()
	check(history.size() == 3 and history[1].speaker_id == first.actor and history[2].speaker_id == second.actor, "One player entry and two independently named replies")
	group.add_selected()
	check(group.members.size() == 3 and group.key() == room and ui._current_history().size() == 3, "Adding participant preserves shared context")
	group.add_selected()
	check(group.members.size() == 4 and group.add_button.disabled, "Four NPC limit enforced")
	group.start("下一轮")
	var third: Dictionary = runtime.calls[-1]
	runtime.dialogue_stream_delta.emit(third.actor, third.request, "已收到的半句")
	runtime.dialogue_stream_failed.emit(third.actor, third.request, "chat_provider_http_503")
	check(ui._current_history()[-1].text.contains("已收到的半句"), "Failure retains partial streamed text")
	await process_frame
	check(runtime.calls.size() == 4, "A failed reply still advances to next member")
	var cancelling: String = group.speaker
	ui.close()
	check(not ui._chat_debug.visible, "Closing dialogue also closes its debug window")
	await process_frame
	check(not group.active and group.queue.is_empty() and cancelling in runtime.cancelled, "Close cancels actual speaker and all remaining turns")
	check(runtime.calls.size() == 4, "No queued member starts after close")
	ui.open_agent_dialogue("farmer_ahe", "阿禾")
	check(group.members.size() == 1 and ui._current_history()[0].text == "PRIVATE_SENTINEL", "Private history survives group conversation")
	ui.get_node("DialoguePanel/Margin/VBox/Header/RestartChatButton").pressed.emit()
	check(ui._chat_reset_pending and ui.send_button.disabled and runtime.resets[-1].room.is_empty(), "Private reset waits for backend acknowledgement and blocks sends")
	runtime.reset_callbacks.pop_front().call(false, {}, "offline")
	check(not ui._chat_reset_pending and ui._current_history()[0].text == "PRIVATE_SENTINEL", "Failed reset does not falsely clear local history")
	ui.restart_chat()
	runtime.reset_callbacks.pop_front().call(true, {"status":"reset"}, "")
	check(ui._current_history().is_empty() and not ui.send_button.disabled and ui._chat_debug._request_filter.is_empty(), "Confirmed private reset clears history/debug and allows a fresh message")
	group.add_selected()
	var reset_room: String = group.key()
	var reset_members: Array = group.members.duplicate()
	group.start("旧话题")
	var resetting: Dictionary = runtime.calls[-1]
	runtime.dialogue_ready.emit(resetting.actor, resetting.request, "旧回复")
	# A next-speaker callback is already queued when the user resets.
	ui.restart_chat()
	check(not group.active and group.queue.is_empty() and runtime.resets[-1].room.id == reset_room, "Group reset cancels queued speakers and resets the shared room")
	runtime.reset_callbacks.pop_front().call(true, {"status":"reset"}, "")
	check(group.members == reset_members and ui._current_history().is_empty(), "Group reset keeps participants but clears shared history")
	group.start("全新话题")
	var fresh_calls: int = runtime.calls.size()
	runtime.dialogue_ready.emit(resetting.actor, resetting.request, "迟到的旧回复")
	await process_frame
	check(runtime.calls.size() == fresh_calls and group.active, "Stale deferred speaker callbacks cannot advance the new round")
	check(not ui.history_view.text.contains("旧回复"), "Late old replies cannot repopulate reset conversation")
	ui.close()
	ui.free()
	runtime.free()
	var state = State.new()
	state.record_chat_handoffs("farmer_ahe", "hello", 10, [])
	check(state.dialogue_followups("farmer_ahe").is_empty() and state.feedback.is_empty(), "Ordinary chat does not wake the action loop")
	var handoff := {"kind":"date","status":"agreed","target_actor_id":"player","place_id":"south_lake","item_id":"","quantity":0,"gold":0,"delay_minutes":10,"trade_side":"none","building_type":"","plot":-1}
	state.record_chat_handoffs("farmer_ahe", "plan", 10, [handoff])
	state.record_chat_handoffs("farmer_ahe", "plan", 10, [handoff])
	check(state.dialogue_followups("farmer_ahe").size() == 1 and state.feedback.farmer_ahe.pending, "Validated plan wakes action loop exactly once")
	var saved: Dictionary = state.to_dict()
	check(State.validate(saved), "Structured handoffs serialize into valid save")
	var restored = State.new()
	restored.restore(saved)
	check(restored.dialogue_followups("farmer_ahe")[0].payload.handoffs == [handoff], "Reload retains action plan")
	check(restored.dialogue_followups("farmer_ahe")[0].payload.player_text.is_empty(), "Action handoff never stores player transcript")
	print("Split chat tests: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
