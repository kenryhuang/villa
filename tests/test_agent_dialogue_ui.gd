extends RefCounted

const DialogueScene = preload("res://scenes/ui/dialogue_ui.tscn")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var dialogue = DialogueScene.instantiate()
	tree.root.add_child(dialogue)
	await tree.process_frame
	var required_paths := [
		"DialoguePanel/Margin/VBox/History",
		"DialoguePanel/Margin/VBox/Composer/MessageInput",
		"DialoguePanel/Margin/VBox/Composer/SendButton",
		"DialoguePanel/Margin/VBox/Header/CloseButton",
	]
	var complete := true
	for path in required_paths:
		var present := dialogue.has_node(path)
		assertions.truthy(present, "Agent dialogue UI authors %s" % path)
		complete = complete and present
	var has_open := dialogue.has_method("open_agent_dialogue")
	var has_history := dialogue.has_method("get_agent_history")
	assertions.truthy(has_open, "Agent dialogue UI exposes conversation opening")
	assertions.truthy(has_history, "Agent dialogue UI exposes per-Agent history")
	assertions.truthy(dialogue.has_signal("agent_message_submitted"), "Agent dialogue UI exposes player message submission")
	if not complete or not has_open or not has_history or not dialogue.has_signal("agent_message_submitted"):
		dialogue.queue_free()
		await tree.process_frame
		return
	var panel := dialogue.get_node("DialoguePanel") as PanelContainer
	assertions.equal(panel.custom_minimum_size, Vector2(760, 420), "Agent dialogue panel has a fixed readable size")
	var input := dialogue.get_node("DialoguePanel/Margin/VBox/Composer/MessageInput") as TextEdit
	var send := dialogue.get_node("DialoguePanel/Margin/VBox/Composer/SendButton") as Button
	var close_button := dialogue.get_node("DialoguePanel/Margin/VBox/Header/CloseButton") as Button
	var history_view := dialogue.get_node("DialoguePanel/Margin/VBox/History") as RichTextLabel
	assertions.truthy(not history_view.bbcode_enabled, "Agent dialogue history renders player and Provider text literally")
	assertions.truthy(history_view.custom_minimum_size.y <= 220.0, "Agent dialogue controls fit inside the fixed panel height")
	var submitted: Array[Array] = []
	var cancelled: Array[Array] = []
	var closed: Array[Array] = []
	dialogue.agent_message_submitted.connect(func(agent_id: String, message: String): submitted.append([agent_id, message]))
	dialogue.agent_dialogue_cancelled.connect(func(agent_id: String, request_id: String): cancelled.append([agent_id, request_id]))
	dialogue.agent_dialogue_closed.connect(func(agent_id: String, request_id: String): closed.append([agent_id, request_id]))
	dialogue.open_agent_dialogue("farmer_ahe", "阿禾")
	assertions.truthy(dialogue.visible, "click flow opens Agent dialogue immediately")
	assertions.equal((dialogue.get_node("DialoguePanel/Margin/VBox/Header/NameLabel") as Label).text, "阿禾", "Agent dialogue header shows display name")
	input.text = "   "
	send.pressed.emit()
	assertions.equal(submitted.size(), 0, "blank Agent dialogue input starts no request")
	input.text = "今天胡萝卜价格怎么样？"
	send.pressed.emit()
	assertions.equal(submitted, [["farmer_ahe", "今天胡萝卜价格怎么样？"]], "send emits exact player dialogue")
	assertions.truthy(not input.editable and send.disabled, "composer disables while Agent reply is pending")
	assertions.equal(dialogue.get_agent_history("farmer_ahe").size(), 2, "send creates player and pending Agent history entries")
	dialogue.begin_agent_dialogue("farmer_ahe", "dialogue-request-1")
	dialogue.append_agent_dialogue("dialogue-request-1", "今天价格")
	dialogue.append_agent_dialogue("dialogue-request-1", "稳定。")
	dialogue.finish_agent_dialogue("dialogue-request-1", "今天价格稳定。")
	assertions.truthy(input.editable and not send.disabled, "composer re-enables after Agent reply")
	assertions.truthy(history_view.text.contains("今天价格稳定。"), "streamed Agent reply appears in scrollable history")
	close_button.pressed.emit()
	assertions.truthy(not dialogue.visible, "Agent dialogue close button hides the panel")
	dialogue.open_agent_dialogue("farmer_ahe", "阿禾")
	assertions.truthy(history_view.text.contains("今天胡萝卜价格怎么样？"), "reopening restores player history")
	assertions.truthy(history_view.text.contains("今天价格稳定。"), "reopening restores Agent history")
	input.text = "那土豆呢？"
	send.pressed.emit()
	dialogue.begin_agent_dialogue("farmer_ahe", "dialogue-request-2")
	close_button.pressed.emit()
	assertions.equal(cancelled, [["farmer_ahe", "dialogue-request-2"]], "closing pending reply cancels exact request")
	assertions.equal(closed[-1], ["farmer_ahe", "dialogue-request-2"], "closing pending reply unlocks exact NPC")
	assertions.equal(dialogue.get_agent_history("farmer_ahe").size(), 4, "closing preserves current Agent history")
	dialogue.queue_free()
	await tree.process_frame
