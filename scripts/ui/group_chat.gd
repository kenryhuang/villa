extends RefCounted

var ui: Control
var runtime: Node
var members: Array[String] = []
var queue: Array[String] = []
var speaker := ""
var request_id := ""
var turn_id := ""
var text := ""
var room_id := ""
var active := false
var picker: OptionButton
var add_button: Button
var private_button: Button
var label: Label

func configure(owner_ui: Control, agent_runtime: Node) -> void:
	ui=owner_ui; runtime=agent_runtime
	var bar := HBoxContainer.new(); bar.name="GroupChatBar"
	picker=OptionButton.new(); picker.name="ParticipantPicker"; picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_button=Button.new(); add_button.text="加入群聊"; add_button.pressed.connect(add_selected)
	private_button=Button.new(); private_button.text="回到单聊"; private_button.pressed.connect(reset)
	label=Label.new(); label.name="ParticipantsLabel"; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(picker);bar.add_child(add_button);bar.add_child(private_button)
	var box: VBoxContainer=ui.get_node("DialoguePanel/Margin/VBox")
	box.add_child(bar);box.move_child(bar,1);box.add_child(label);box.move_child(label,2)

func reset() -> void:
	if active: return
	members.assign([ui._current_villager_id])
	room_id=""
	refresh()
	ui._render_history()

func key() -> String:
	if members.size()<2:return ui._current_villager_id
	return room_id

func refresh() -> void:
	if picker==null:return
	picker.clear()
	for id in runtime.registry.get_agent_ids():
		if id=="village_public" or id in members:continue
		picker.add_item(runtime.get_agent_display_name(id));picker.set_item_metadata(picker.item_count-1,id)
	add_button.disabled=active or ui._agent_stream_pending or members.size()>=4 or picker.item_count==0
	private_button.disabled=active or ui._agent_stream_pending or members.size()<2
	label.text="参与者："+"、".join(members.map(func(id):return runtime.get_agent_display_name(id)))
	ui.interaction_scroll.visible=members.size()<2
	ui.name_label.text="群聊" if members.size()>1 else runtime.get_agent_display_name(ui._current_villager_id)

func add_selected() -> void:
	if add_button.disabled or picker.selected<0:return
	if members.size()<2:room_id="group-%d-%d"%[Time.get_unix_time_from_system()*1000,Time.get_ticks_usec()]
	members.append(str(picker.get_item_metadata(picker.selected)))
	refresh();ui._render_history()

func start(message: String) -> void:
	if active or members.size()<2:return
	text=message;turn_id="chat-turn-%d-%d"%[Time.get_unix_time_from_system()*1000,Time.get_ticks_usec()]
	queue=members.duplicate();active=true
	ui._append_history(ui._current_villager_id,"player",message)
	ui.message_input.text=""
	next()

func next() -> void:
	if not active or not ui._is_open:return
	if queue.is_empty():
		active=false;speaker="";request_id="";ui._set_composer_enabled(true);refresh();return
	speaker=queue.pop_front();request_id=""
	ui._pending_speaker_id=speaker
	ui._pending_history_index=ui._append_history(ui._current_villager_id,"agent",ui.THINKING_TEXT)
	ui._agent_stream_pending=true;ui._agent_request_id="";ui._set_composer_enabled(false)
	ui.status_label.text=runtime.get_agent_display_name(speaker)+"正在思考……"
	ui._render_history();refresh()
	if not runtime.trigger_chat(speaker,text,{"id":key(),"participants":members.duplicate(),"turn_id":turn_id}):
		ui._set_pending_failure(runtime.dialogue_unavailable_reason());ui._set_composer_enabled(false)
		next.call_deferred()

func started(actor: String, id: String) -> bool:
	if not active:return false
	if actor==speaker:
		request_id=id;ui._agent_request_id=id
	return true

func finished(actor: String, id: String, speech: String, error := "") -> bool:
	if not active:return false
	if actor!=speaker or id!=request_id:return true
	if error.is_empty():ui.finish_agent_dialogue(id,speech)
	else:ui.fail_agent_dialogue(id,error)
	ui._set_composer_enabled(false)
	next.call_deferred()
	return true

func cancel() -> void:
	var cancelled=speaker
	active=false;queue.clear();speaker="";request_id=""
	if not cancelled.is_empty():runtime.cancel_chat_turn(cancelled)
