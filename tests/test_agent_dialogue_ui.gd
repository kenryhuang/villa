extends RefCounted

const DialogueScene = preload("res://scenes/ui/dialogue_ui.tscn")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var dialogue = DialogueScene.instantiate()
	tree.root.add_child(dialogue)
	await tree.process_frame
	var required_paths := [
		"DialoguePanel/Margin/VBox/History",
		"DialoguePanel/Margin/VBox/InteractionScroll/InteractionCards",
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
	assertions.truthy(dialogue.has_signal("interaction_response_requested"), "Agent dialogue UI exposes explicit structured interaction response")
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
	var interaction_responses: Array[Array] = []
	var cancelled: Array[Array] = []
	var closed: Array[Array] = []
	dialogue.agent_message_submitted.connect(func(agent_id: String, message: String): submitted.append([agent_id, message]))
	dialogue.interaction_response_requested.connect(func(agent_id: String, interaction_id: String, response: String, counter_terms: Dictionary): interaction_responses.append([agent_id, interaction_id, response, counter_terms]))
	dialogue.agent_dialogue_cancelled.connect(func(agent_id: String, request_id: String): cancelled.append([agent_id, request_id]))
	dialogue.agent_dialogue_closed.connect(func(agent_id: String, request_id: String): closed.append([agent_id, request_id]))
	dialogue.open_agent_dialogue("farmer_ahe", "阿禾")
	dialogue.set_agent_interactions("farmer_ahe", [{"offer_id": "offer-1", "status": "open", "proposer_id": "farmer_ahe", "recipient_id": "player", "proposer_gives": {"items": {"carrot": 2}, "gold": 0}, "proposer_receives": {"items": {"salt": 1}, "gold": 0}, "expires_game_minute": 900}])
	var cards := dialogue.get_node("DialoguePanel/Margin/VBox/InteractionScroll/InteractionCards") as VBoxContainer
	assertions.equal(cards.get_child_count(), 1, "pending interaction renders one authority-backed card")
	var first_card := cards.get_child(0)
	var terms_label := first_card.find_child("TermsLabel", true, false) as Label
	assertions.truthy(terms_label.text.contains("offer-1") and terms_label.text.contains("carrot"), "card renders exact current structured terms")
	(first_card.find_child("AcceptButton", true, false) as Button).pressed.emit()
	assertions.equal(interaction_responses.size(), 1, "accept button emits one explicit Player command")
	assertions.equal(interaction_responses[0].slice(0, 3), ["farmer_ahe", "offer-1", "accept"], "accept identifies Agent and interaction")
	(first_card.find_child("RejectButton", true, false) as Button).pressed.emit()
	(first_card.find_child("CounterButton", true, false) as Button).pressed.emit()
	assertions.equal(interaction_responses.size(), 2, "counter opens an editor without submitting unchanged terms")
	var counter_editor := first_card.find_child("CounterEditor", true, false) as VBoxContainer
	assertions.truthy(counter_editor.visible, "counter button reveals the structured term editor")
	var give_gold := first_card.find_child("CounterGiveGold", true, false) as SpinBox
	var expiry := first_card.find_child("CounterExpiryMinutes", true, false) as SpinBox
	give_gold.value = 7
	expiry.value = 180
	(first_card.find_child("SubmitCounterButton", true, false) as Button).pressed.emit()
	assertions.equal(interaction_responses.size(), 3, "submitting edited counter terms emits one Player command")
	assertions.equal(interaction_responses[2][2], "counter", "counter submit uses counter response")
	var submitted_terms := interaction_responses[2][3] as Dictionary
	assertions.equal(submitted_terms.give.gold, 7, "counter carries edited Player give gold")
	assertions.equal(submitted_terms.expires_in_minutes, 180, "counter carries edited expiry")
	assertions.equal(dialogue.get_agent_interactions("farmer_ahe")[0].status, "open", "UI button emission alone does not mutate interaction state")
	dialogue.set_agent_interactions("farmer_ahe", [{"offer_id": "offer-outgoing", "status": "open", "proposer_id": "player", "recipient_id": "farmer_ahe", "proposer_gives": {"items": {"salt": 1}, "gold": 0}, "proposer_receives": {"items": {"carrot": 1}, "gold": 0}, "expires_game_minute": 900}])
	var outgoing_card := cards.get_child(0)
	assertions.truthy((outgoing_card.find_child("AcceptButton", true, false) as Button).disabled, "Player cannot accept an outgoing counteroffer before the NPC")
	assertions.truthy((outgoing_card.find_child("CounterButton", true, false) as Button).disabled, "Player cannot counter their own outgoing offer")
	dialogue.set_agent_interactions("farmer_ahe", [{"agreement_id": "agreement-1", "status": "proposed", "proposer_id": "farmer_ahe", "participants": ["farmer_ahe", "player"], "accepted_by": ["farmer_ahe"], "commitments": [{"participant_id": "farmer_ahe", "items": {}, "gold": 0}, {"participant_id": "player", "items": {"salt": 1}, "gold": 0}], "reward_split": {"farmer_ahe": 1, "player": 1}, "deadline": 900, "note": "合作"}])
	var agreement_card := cards.get_child(0)
	(agreement_card.find_child("CounterButton", true, false) as Button).pressed.emit()
	(agreement_card.find_child("CounterNote", true, false) as LineEdit).text = "需要更多时间"
	(agreement_card.find_child("CounterDeadlineMinutes", true, false) as SpinBox).value = 240
	(agreement_card.find_child("SubmitCounterButton", true, false) as Button).pressed.emit()
	var cooperation_terms := interaction_responses[-1][3] as Dictionary
	assertions.equal(cooperation_terms.revised_terms.deadline_minutes, 240, "cooperation counter carries edited deadline")
	assertions.equal(cooperation_terms.revised_terms.note, "需要更多时间", "cooperation counter includes the required inner note")
	assertions.truthy(dialogue.visible, "click flow opens Agent dialogue immediately")
	assertions.equal(dialogue.get_viewport().gui_get_focus_owner(), input, "opening Agent dialogue focuses its text editor")
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
	assertions.equal(interaction_responses.size(), 4, "closing dialogue never accepts or rejects an interaction")
	assertions.truthy(dialogue.get_viewport().gui_get_focus_owner() != input, "closing Agent dialogue releases text input focus")
	dialogue.open_agent_dialogue("farmer_ahe", "阿禾")
	assertions.equal(cards.get_child_count(), 1, "reopening preserves pending structured cards")
	assertions.truthy(history_view.text.contains("今天胡萝卜价格怎么样？"), "reopening restores player history")
	assertions.truthy(history_view.text.contains("今天价格稳定。"), "reopening restores Agent history")
	input.text = "那土豆呢？"
	send.pressed.emit()
	dialogue.begin_agent_dialogue("farmer_ahe", "dialogue-request-2")
	close_button.pressed.emit()
	assertions.equal(cancelled, [["farmer_ahe", "dialogue-request-2"]], "closing pending reply cancels exact request")
	assertions.equal(closed[-1], ["farmer_ahe", "dialogue-request-2"], "closing pending reply unlocks exact NPC")
	assertions.equal(dialogue.get_agent_history("farmer_ahe").size(), 4, "closing preserves current Agent history")
	dialogue.open_agent_dialogue("farmer_ahe", "阿禾")
	dialogue.set_agent_interactions("farmer_ahe", [{"offer_id": "offer-expired", "status": "expired", "expires_game_minute": 1}])
	var expired_card := cards.get_child(0)
	assertions.truthy((expired_card.find_child("AcceptButton", true, false) as Button).disabled, "expired interaction cannot be accepted")
	dialogue.queue_free()
	await tree.process_frame
