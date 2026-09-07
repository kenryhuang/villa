extends SceneTree

var checks := 0
var failures: Array[String] = []

class MemoryGateway extends Node:
	var session_epoch := 3
	var exported: Callable
	var imported: Dictionary = {}
	var resets := 0
	func export_checkpoint(_session: String, _checkpoint: String, callback: Callable) -> bool:
		exported = callback
		return true
	func import_checkpoint(record: Dictionary, callback: Callable) -> bool:
		imported = record.duplicate(true)
		callback.call(true, {}, "")
		return true
	func sync_session(_session: String, reset: bool) -> bool:
		if reset: resets += 1
		return true

func _initialize() -> void:
	create_timer(70).timeout.connect(func(): push_error("Agent integration timed out"); quit(1))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func key_event(code: Key, unicode_value := 0, pressed := true, echo := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode_value
	event.pressed = pressed
	event.echo = echo
	event.shift_pressed = shift
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	root.size = Vector2i(1440, 960)
	var scene := load("res://scenes/farm3d/main.tscn").instantiate() as Node
	root.add_child(scene)
	scene.set_process(false)
	var session: Farm3DSession = scene.get_node("FarmSession")
	var runtime: Node = session.agent_runtime
	var hud: Node = scene.get_node("FarmInteraction").hud
	session.season.set_process(false)
	session.player.set_physics_process(false)
	session.save_path = "user://farm3d_agent_integration_test.json"
	check(runtime != null and runtime.get_script().resource_path == "res://scripts/ai_agent/agent_runtime.gd", "Formal 3D scene reuses original runtime")
	check(not runtime.service_enabled, "Headless integration never contacts remote model")
	check(runtime.farm3d_actors.size() == 3, "All three original characters spawn")
	check(runtime.farm_registry is VisibleNpcFarmSystem, "Farmer uses original real-world farm executor")
	check(runtime.farm_registry.get_snapshot("farmer_ahe").size() == 20, "Twenty reserved real farm plots")
	var plot: GridCell = runtime.farm_registry.get_plot_cell("farmer_ahe", 0)
	check(not session.apply_target(plot, "farmland", "dry").ok, "Player cannot overwrite NPC farmland")
	check(hud.debug_panel != null and not hud.debug_panel.visible, "Debug hub starts closed")
	hud.debug_panel.open()
	check(hud.is_modal_open(), "Debug hub blocks world interaction")
	if "--capture-agent-ui" in OS.get_cmdline_user_args():
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tmp")
		root.get_texture().get_image().save_png("res://tmp/farm3d-agent-debug.png")
	hud.debug_panel.agent_trace_window.open()
	check(hud.debug_panel.agent_trace_window._trace == runtime.get_session_trace(), "Original trace window uses live runtime")
	hud.close_panels()
	check(not hud.is_modal_open(), "Closing debug hub closes nested trace view")
	session.player.position = session.grid.get_cell(32, 31).world_position_3d() + Vector3.LEFT * 1.2
	var placed: Dictionary = session.buildings.try_place_building("windmill", 32, 31)
	check(placed.placed, "Place a real player windmill")
	if not placed.placed:
		quit(1)
		return
	var building: BuildingInstance = placed.instance
	building.restore_construction(3, 9.0)
	building.set_process(false)
	var key := EconomyProgressionSystem.building_key(building)
	var fees: Array = session.production.get_rental_fee_table(building)
	check(fees.size() == 3 and int(fees[0].fee_per_batch) > 0, "Each windmill publishes complete rental schedule")
	var env: Dictionary = runtime.get_farm3d_environment()
	check(env.characters.size() == 13 and env.map.has("market") and env.map.has("lake"), "Environment includes player, twelve residents, real market and lake")
	check(env.buildings[0].building_id == key and env.buildings[0].owner_id == "player", "Environment identifies actual owned building instance")
	var request: Dictionary = runtime._build_request("farmer_ahe", "schedule", runtime._absolute_game_minute(), "")
	check("inspect_building" in request.allowed_read_tools and "rent_production" in request.allowed_command_tools, "Both sides of environment decision contract are advertised")
	check(request.actor_context.player_buildings[0].rental_fees == fees, "Agent sees authoritative live rental prices")
	var npc: NpcEconomyState = session.npc_economy.get_npc_state("farmer_ahe")
	npc.inventory = {"grain": 20}
	npc.gold = 1000
	var wallet: Node = root.get_node("GameState")
	var player_gold: int = wallet.gold
	var player_inventory := session.inventory.slots.duplicate(true)
	var intent := {"agent_id": "farmer_ahe", "decision_id": "rental-test", "action_id": "rental-action", "tool_name": "rent_production", "idempotency_key": "rental-test:1", "arguments": {"building_id": key, "recipe_id": "flour", "batches": 2, "max_fee": 100}}
	var rejected: Dictionary = session.production.start_rented_recipe(building, "farmer_ahe", "flour", 1, 0)
	check(not rejected.ok and npc.gold == 1000 and building.producer_state.jobs.is_empty(), "Price cap rejection does not consume assets or queue")
	var outcome: Dictionary = runtime.executor.execute(intent, runtime._absolute_game_minute())
	check(outcome.status == "in_progress", "Accepted rental stays in progress until goods are delivered")
	check(npc.gold == 992 and wallet.gold == player_gold + 8, "Rent transfers exactly from NPC to player")
	check(npc.inventory.grain == 16 and session.inventory.slots == player_inventory, "Only NPC supplies recipe ingredients")
	check(building.producer_state.jobs.size() == 1 and building.producer_state.jobs[0].tenant_id == "farmer_ahe", "Shared production queue retains owner")
	check(not session.buildings.remove_building(building), "Paid orders prevent demolition until delivered")
	runtime.executor.execute(intent, runtime._absolute_game_minute())
	check(npc.gold == 992 and wallet.gold == player_gold + 8 and building.producer_state.jobs.size() == 1, "Duplicate action never charges or queues twice")
	check(session.production.start_rented_recipe(building, "farmer_ahe", "animal_feed", 1, 100).ok, "Second shared queue slot accepts order")
	var before := npc.to_dict()
	check(not session.production.start_rented_recipe(building, "farmer_ahe", "flour", 1, 100).ok and npc.to_dict() == before, "Full queue failure is atomic")
	session.production.advance_minutes(10)
	check(session.save_game(), "Save queues, tenants and agent state with farm")
	check(session.load_game(), "Restore farm and event-sourced agents")
	building = session.buildings.get_all_buildings()[0]
	npc = session.npc_economy.get_npc_state("farmer_ahe")
	check(npc.to_dict() == before and building.producer_state.jobs[0].remaining_minutes == 44, "Reload preserves paid assets and remaining work")
	var gold_after_load: int = wallet.gold
	runtime.executor.execute(intent, runtime._absolute_game_minute())
	check(wallet.gold == gold_after_load and building.producer_state.jobs.size() == 2, "Idempotency survives reload")
	session.production.advance_minutes(44)
	check(int(npc.inventory.get("flour", 0)) == 2, "Rented flour delivered to NPC after time elapses")
	check(building.producer_state.outputs.is_empty(), "Rented goods never enter player output storage")
	session.production.advance_minutes(27)
	check(int(npc.inventory.get("animal_feed", 0)) == 2 and building.producer_state.jobs.is_empty(), "Next queued recipe delivers to its tenant")
	session.inventory.add_item("grain", 2)
	check(session.production.start_recipe(building, "flour", 1, session.inventory), "Player still uses original recipe flow")
	session.production.advance_minutes(27)
	check(building.producer_state.get_output_count("flour") == 1 and int(npc.inventory.flour) == 2, "Player and NPC outputs stay separate")
	npc.gold = 0
	check(not session.production.start_rented_recipe(building, "farmer_ahe", "flour", 1, 100).ok, "Insolvent NPC cannot rent")
	var actor: Node = runtime.farm3d_actors.farmer_ahe
	check(actor.begin_agent_work(plot.world_position_3d()), "Original actor can pathfind to 3D farm plot")
	actor.stop_agent_work()
	var interaction: Node = scene.get_node("FarmInteraction")
	session.player.global_position = actor.global_position + Vector3(0, 0, 2)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.global_position = actor.global_position + Vector3(0, 3, 5)
	camera.look_at(actor.global_position + Vector3.UP * 0.8)
	await physics_frame
	await physics_frame
	var pointer := camera.unproject_position(actor.global_position + Vector3.UP * 0.8)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	interaction._unhandled_input(motion)
	check(not hud.dialogue_ui.visible, "Hovering a nearby NPC never opens dialogue")
	var click := InputEventMouseButton.new()
	click.position = pointer
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	session.season.set_process(true)
	Input.action_press("move_right")
	session.player.velocity = Vector3.RIGHT
	interaction._unhandled_input(click)
	check(hud.dialogue_ui.visible and session.player.ui_blocked, "Clicking a nearby NPC opens shared dialogue and blocks walking")
	check(session.player.velocity == Vector3.ZERO and not Input.is_action_pressed("move_right"), "Opening dialogue stops existing movement immediately")
	check(paused and not session.season.can_process() and not actor.can_process(), "Dialogue pauses clock and NPC simulation")
	check(runtime.gateway.can_process() and hud.dialogue_ui.can_process(), "Network and dialogue remain active while world pauses")
	await process_frame
	var map_visible: bool = hud.minimap.visible
	var overview_before: bool = scene.overview_enabled
	var player_before: Vector3 = session.player.global_position
	for letter in "wasdiger123":
		key_event(OS.find_keycode_from_string(letter.to_upper()), letter.unicode_at(0))
		key_event(OS.find_keycode_from_string(letter.to_upper()), 0, false)
	key_event(KEY_NONE, "鱼".unicode_at(0))
	check(hud.dialogue_ui.message_input.text == "wasdiger123鱼", "TextEdit receives gameplay letters and Chinese text")
	check(hud.minimap.visible == map_visible and not hud.inventory_ui.visible, "Typing I/G never toggles gameplay HUD")
	key_event(KEY_TAB)
	key_event(KEY_TAB, 0, false)
	check(scene.overview_enabled == overview_before and session.player.global_position == player_before, "Camera and movement shortcuts do not run during dialogue")
	key_event(KEY_ENTER, 0, true, false, true)
	key_event(KEY_ENTER, 0, false)
	check(hud.dialogue_ui.message_input.text.contains("\n"), "Shift Enter inserts a newline")
	key_event(KEY_ENTER)
	key_event(KEY_ENTER, 0, false)
	check(hud.dialogue_ui.get_agent_history(actor.villager_id).size() >= 2 and hud.dialogue_ui.send_button.disabled == false, "Enter submits and offline failure returns text focus without hanging")
	hud.dialogue_ui.begin_agent_dialogue(actor.villager_id, "paused-reply")
	runtime.dialogue_stream_delta.emit(actor.villager_id, "paused-reply", "可以租用风车。")
	runtime.dialogue_ready.emit(actor.villager_id, "paused-reply", "可以租用风车。")
	check(paused and hud.dialogue_ui.get_agent_history(actor.villager_id)[-1].text == "可以租用风车。", "Agent replies continue updating dialogue during pause")
	Input.action_press("move_right")
	key_event(KEY_ESCAPE)
	key_event(KEY_ESCAPE, 0, false)
	check(not paused and not hud.dialogue_ui.visible and not session.player.ui_blocked, "Escape closes dialogue and restores simulation")
	check(session.season.can_process(), "Closing resumes the previously running game clock")
	session.season.set_process(false)
	check(not Input.is_action_pressed("move_right") and session.player.velocity == Vector3.ZERO, "Closing clears residual movement state immediately")
	key_event(KEY_D, 100, true, true)
	check(not Input.is_action_pressed("move_right"), "Held-key repeat cannot restart movement after closing")
	key_event(KEY_D, 0, false)
	key_event(KEY_D, 100)
	check(Input.is_action_pressed("move_right"), "A fresh movement key works after closing")
	key_event(KEY_D, 0, false)
	paused = true
	hud.dialogue_ui.open_agent_dialogue(actor.villager_id, "阿禾")
	hud.dialogue_ui.close_button.pressed.emit()
	check(paused, "Closing preserves an existing external pause")
	paused = false
	var original_gateway: Node = runtime.gateway
	var memory := MemoryGateway.new()
	runtime.add_child(memory)
	runtime.gateway = memory
	runtime.service_enabled = true
	runtime.save_farm3d_memory(session.save_path)
	var record := {"session_id": runtime.session_id, "path": "test-checkpoint.sqlite", "sha256": "a".repeat(64)}
	memory.exported.call(true, record, "")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.save_path + ".agent-memory.json"))
	check(manifest.world_sha256 == FileAccess.get_sha256(session.save_path), "Memory manifest is bound to exact world save")
	runtime.load_farm3d_memory(session.save_path)
	check(memory.imported == record and memory.resets == 0, "Matching world restores original service checkpoint")
	runtime.save_farm3d_memory(session.save_path)
	var file := FileAccess.open(session.save_path, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string("\n")
	file.close()
	memory.exported.call(true, record, "")
	check(FileAccess.get_file_as_string(session.save_path + ".agent-memory.json").contains(str(manifest.world_sha256)), "Stale async checkpoint cannot overwrite newer world manifest")
	runtime.load_farm3d_memory(session.save_path)
	check(memory.resets == 1, "Mismatched memory falls back without rejecting world save")
	runtime.service_enabled = false
	runtime.gateway = original_gateway
	scene.queue_free()
	await process_frame
	await process_frame
	for suffix in ["", ".bak", ".tmp", ".agent-memory.json", ".agent-memory.json.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://farm3d_agent_integration_test.json" + suffix))
	print("3D agents: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
