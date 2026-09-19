extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("Character editor timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func find_key(view: Dictionary, prefix: Array) -> String:
	for key in view.records:
		if view.records[key].path.slice(0,prefix.size()) == prefix: return key
	return ""

func press_key(code: int, unicode_value := 0, ctrl := false) -> void:
	var key := InputEventKey.new()
	key.keycode = code; key.unicode = unicode_value; key.ctrl_pressed = ctrl; key.pressed = true
	root.push_input(key,true)
	key = key.duplicate(); key.pressed = false
	root.push_input(key,true)

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var s: Node = scene.farm_session
	s.save_path = "user://character_state_editor_test.json"
	var world: Node = s.living_world
	var runtime: Node = s.agent_runtime
	scene.set_process(false); s.season.set_process(false); world.set_process(false)
	var panel: RuntimeDebugPanel = scene.get_node("FarmInteraction").hud.debug_panel
	var page: VBoxContainer = panel.character_state_panel
	panel.open(); panel.tabs.current_tab = page.get_index()
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		for frame in 4: await process_frame
		# Canvas controls use the stretch viewport coordinates, not window pixels.
		var bounds := root.get_visible_rect()
		check(bounds.encloses(page.apply_button.get_global_rect()) and bounds.encloses(page.selector.get_global_rect()),"Editor controls remain on screen at " + str(resolution))
	check(paused,"Opening the character editor pauses simulation")
	check(page.selector.item_count == world.society.residents.size()+1,"Dropdown includes player and all residents, including background residents")
	for i in page.selector.item_count:
		if page.selector.get_item_metadata(i) == "xiao_hua": page.selector.select(i)
	page.refresh_actor()
	var editor = page.editor
	var view: Dictionary = page.views.xiao_hua
	var resource_key := find_key(view,["npc_economy","npc_states"])
	var resident_key := JSON.stringify(["living_world","society","residents","xiao_hua"])
	var identity_key := JSON.stringify(["living_world","character_overrides","xiao_hua"])
	var affection_key := JSON.stringify(["living_world","relationships","pairs",world.relationships.pair_key("xiao_hua","player")])
	check(not resource_key.is_empty() and view.records.has(resident_key),"Editor exposes authoritative resources and needs")
	check(view.records.has(identity_key) and view.records.has(affection_key),"Personality and zero affection are editable before meeting")
	# Reproduce actual user typing through _input and GUI dispatch, not text assignment.
	for i in page.record_selector.item_count:
		if page.record_selector.get_item_metadata(i) == resource_key: page.record_selector.select(i)
	page._show_record()
	page.text.grab_focus()
	for line in page.text.get_line_count():
		var content: String = page.text.get_line(line)
		if content.contains("\"gold\":"):
			var start := content.find(":") + 2
			var end := content.find(",", start)
			page.text.select(line,start,line,end if end >= 0 else content.length())
			break
	for digit in "24680":
		press_key(digit.unicode_at(0),digit.unicode_at(0))
	await process_frame
	var typed: Variant = JSON.parse_string(page.text.text)
	check(typed is Dictionary and typed.get("gold") == 24680,"Real keyboard input edits the JSON while simulation is paused")
	check(page.drafts.xiao_hua.has(resource_key),"Typing records an applicable draft")
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT; click.pressed = pressed
		click.position = page.apply_button.get_global_rect().get_center()
		root.push_input(click,true)
	await process_frame
	check(s.npc_economy.get_npc_state("xiao_hua").gold == 24680,"Mouse click on Apply updates real resources")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(s.save_path)) if FileAccess.file_exists(s.save_path) else null
	var saved_resources: Variant = saved
	if saved is Dictionary:
		for part in view.records[resource_key].path: saved_resources = saved_resources[part]
	check(saved_resources is Dictionary and saved_resources.get("gold") == 24680,"Keyboard edit and mouse Apply persist to the isolated save")
	page.refresh_actor(true)
	view = page.views.xiao_hua
	var resources: Dictionary = view.records[resource_key].value.duplicate(true)
	resources.gold = 12345; resources.inventory.grain_seed = 88
	var resident: Dictionary = view.records[resident_key].value.duplicate(true)
	resident.needs.social = 77
	var identity: Dictionary = view.records[identity_key].value.duplicate(true)
	identity.display_name = "小花测试"
	identity.soul.traits = ["开朗","重视承诺"]
	identity.soul.social_profile.romance_interest = 90
	var affection: Dictionary = view.records[affection_key].value.duplicate(true)
	affection.affinity.xiao_hua = 66; affection.affinity.player = 71
	var changes := {resource_key:resources,resident_key:resident,identity_key:identity,affection_key:affection}
	var other_before: Dictionary = s.npc_economy.get_npc_state("lao_li").to_dict()
	var result: Dictionary = editor.apply(view,changes)
	check(result.ok,"Apply and persist multi-section draft: " + str(result.message))
	check(s.npc_economy.get_npc_state("xiao_hua").gold == 12345 and s.npc_economy.get_npc_state("xiao_hua").inventory.grain_seed == 88,"Resource edits update actual game authority")
	check(world.society.residents.xiao_hua.needs.social == 77,"Needs edit is applied")
	check(world.relationships.view("xiao_hua","player").affinity == 66 and world.relationships.view("player","xiao_hua").affinity == 71,"Directed affection values are preserved separately")
	check(world.relationships.profile("xiao_hua").romance_interest == 90,"Romance rules use edited saved profile")
	check(world.actor("xiao_hua").nameplate.text == "小花测试","In-world nameplate updates while editing is paused")
	check(s.npc_economy.get_npc_state("lao_li").to_dict() == other_before,"Unedited NPC resources remain unchanged")
	check(FileAccess.file_exists(s.save_path) and s.load_game(),"Applied state reloads from actual isolated save")
	check(world.character_profile("xiao_hua").soul.traits == ["开朗","重视承诺"] and runtime.get_agent_display_name("xiao_hua") == "小花测试","Name and personality persist across reload")
	var request: Dictionary = runtime._build_loop_request("xiao_hua","editor-profile","dialogue",world.minute(),"你好")
	check(request.identity_override.soul.social_profile.romance_interest == 90,"Next LLM request uses edited personality")
	runtime.loop_state.loops["editor-profile"].state = "cancelled"
	# Validation failure must not partially apply otherwise valid edits.
	view = editor.snapshot("xiao_hua")
	resource_key = find_key(view,["npc_economy","npc_states"])
	resources = view.records[resource_key].value.duplicate(true); resources.gold = 22222
	affection = view.records[affection_key].value.duplicate(true); affection.affinity.player = 101
	var hash_before := FileAccess.get_sha256(s.save_path)
	check(not editor.apply(view,{resource_key:resources,affection_key:affection}).ok,"Out-of-range affection rejects whole transaction")
	check(s.npc_economy.get_npc_state("xiao_hua").gold == 12345 and FileAccess.get_sha256(s.save_path) == hash_before,"Invalid draft changes neither live resources nor save file")
	check(not editor.apply(view,{resident_key:null}).ok,"Replacing a resident object with null is rejected without a runtime exception")
	s.npc_economy.get_npc_state("xiao_hua").gold += 1
	check(not editor.apply(view,{resource_key:resources}).ok,"Stale edited records cannot overwrite newer world state")
	# A broken destination exercises rollback after validation and live restoration.
	view = editor.snapshot("xiao_hua")
	resources = view.records[resource_key].value.duplicate(true); resources.gold = 33333
	var good_path: String = s.save_path
	s.save_path = "user://nonexistent-character-test-dir/invalid/save.json"
	check(not editor.apply(view,{resource_key:resources}).ok,"Failed save reports failure")
	check(s.npc_economy.get_npc_state("xiao_hua").gold == 12346,"Failed save rolls back live edits")
	s.save_path = good_path
	# UI drafts, parse feedback and normal pause restoration.
	page.refresh_actor(true)
	for i in page.record_selector.item_count:
		if page.record_selector.get_item_metadata(i) == resource_key: page.record_selector.select(i)
	page._show_record()
	page.text.grab_focus()
	press_key(KEY_A,0,true)
	check(page.text.has_selection(),"Ctrl+A reaches the JSON editor")
	press_key(KEY_BRACELEFT,123)
	press_key(KEY_I,105)
	press_key(KEY_G,103)
	await process_frame
	check(page.text.text == "{ig" and panel.visible and paused,"I/G type into JSON without opening inventory or map")
	press_key(KEY_BACKSPACE)
	await process_frame
	check(page.text.text == "{i","Backspace edits JSON normally")
	page.apply_changes()
	check(page.status.text.contains("JSON 错误"),"Invalid JSON gets a record and line error in the panel")
	panel.tabs.current_tab = 3
	check(not paused,"Leaving the editor restores previous simulation pause state")
	panel.tabs.current_tab = page.get_index(); panel.close()
	check(not paused,"Closing debug window also restores simulation")
	var old: Dictionary = world.to_dict(); old.version = 8; old.erase("character_overrides")
	check(world.validate(old),"Version 8 relationship saves remain valid without profile overrides")
	if "--capture-character-editor" in OS.get_cmdline_user_args():
		panel.open(); panel.tabs.current_tab = page.get_index(); page.refresh_actor(true)
		for i in page.record_selector.item_count:
			if page.record_selector.get_item_metadata(i) == identity_key: page.record_selector.select(i)
		page._show_record()
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/character-state-editor.png")
		panel.close()
	var renamed_save: Dictionary = world.to_dict()
	renamed_save.character_overrides.resident_yun = world.character_profile("resident_yun")
	var old_yun: Dictionary = renamed_save.character_overrides.resident_yun
	old_yun.display_name = "云姐"
	old_yun.soul.traits = ["旧设定"]
	old_yun.soul.values = ["保留的经营价值观"]
	old_yun.soul.social_profile.romance_interest = 40
	renamed_save.society.residents.resident_yun.name = "云姐"
	world.restore(renamed_save)
	check(world.actor_name("resident_yun") == "伊可" and world.society.residents.resident_yun.name == "伊可", "Authored rename migrates both saved override and resident name")
	check(world.character_profile("resident_yun").soul.traits.has("热情奔放") and world.relationships.profile("resident_yun").romance_interest == 90, "Old named override adopts new personality and relationship preferences")
	check(world.character_profile("resident_yun").soul.values == ["保留的经营价值观"] and world.relationships.to_dict() == renamed_save.relationships, "Rename preserves unrelated edits and relationship history")
	var later_edit: Dictionary = world.to_dict()
	later_edit.character_overrides.resident_yun.soul.speech_style = "之后的自定义说话风格"
	world.restore(later_edit)
	check(world.character_profile("resident_yun").soul.speech_style == "之后的自定义说话风格", "Renamed profile preserves future editor changes across reload")
	scene.free()
	print("CHARACTER EDITOR: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
