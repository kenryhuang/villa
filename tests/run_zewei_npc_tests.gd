extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("Flower girl (zewei) integration timeout"); quit(1))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func run() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args() or "--living-world-scenario=P12" not in OS.get_cmdline_user_args():
		push_error("Use --farm-test --living-world-scenario=P12 for isolated expanded population"); quit(1); return
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var s: Node = scene.farm_session
	var w: Node = s.living_world
	var r: Node = s.agent_runtime
	scene.set_process(false); s.season.set_process(false); w.set_process(false); r.set_process(false)
	s.player.set_physics_process(false)
	s.save_path = "user://flower_girl_npc_integration_test.json"
	check(not s.auto_save and not s.auto_restore, "Isolated from player save")
	check(w.society.residents.size() == 37 and r.registry.get_agent_ids().size() == 37, "37 residents and agents registered")
	check(w.society.focus.size() == 9 and r.farm3d_actors.size() == 9, "Flower girl added without displacing existing visible NPCs")
	var profile: Dictionary = w.character_profile("flower_girl")
	check(profile.display_name == "zewei" and profile.soul.social_profile.age == 22 and profile.soul.social_profile.gender == "female", "Adult female identity and authored personality")
	var npc: Node3D = w.actor("flower_girl")
	check(npc != null and npc.character_model != null and npc.character_animation != null, "Reference model with animations loaded")
	check(npc.nameplate.visible and npc.nameplate.text == "zewei" and not npc.placeholder_mesh.visible, "Visible nameplate and no placeholder body")
	check(s.grid.is_navigation_cell_walkable(s.grid.world_to_grid(npc.position.x,npc.position.z)), "Spawn is on walkable ground")
	s.player.position = npc.position + Vector3(1,0,0)
	npc.refresh_dialogue_prompt()
	check(npc.is_player_in_dialogue_range() and npc.dialogue_prompt.visible, "Proximity reveals clickable dialogue prompt")
	var emitted := []
	npc.dialogue_started.connect(func(id): emitted.append(id))
	check(npc.start_dialogue() and emitted == ["flower_girl"], "Body/prompt dialogue entry emits correct Agent identity")
	npc.set_dialogue_busy(false)
	s.player.position = npc.position + Vector3(10,0,0)
	npc.refresh_dialogue_prompt()
	check(not npc.start_dialogue(), "Distant interaction rejected")
	var request: Dictionary = r._build_request("flower_girl", "dialogue", w.minute(), "你好，今天过得怎么样？")
	check(request.agent_id == "flower_girl" and request.dialogue_input.begins_with("你好"), "Dialogue request targets flower_girl")
	check(request.chat_participants.any(func(p): return p.actor_id == "player" and p.relationship.status == w.relationships.view("flower_girl", "player").status), "Conversation contains actual player relationship")
	var scheduled: Dictionary = r._build_request("flower_girl", "scheduled", w.minute(), "")
	check(not scheduled.is_empty() and "propose_trade" in scheduled.allowed_command_tools and "move" in scheduled.allowed_command_tools, "Autonomous Agent has trade, movement and social tools")
	check(s.npc_economy.get_npc_state("flower_girl").gold == 3000 and int(s.npc_economy.get_npc_state("flower_girl").inventory.get("rose", 0)) == 12, "Own ledger and initial flower stock")
	check(s.save_game(), "New expanded save writes")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(s.save_path))
	check(s._valid_save(saved), "New expanded save validates")
	# Reverse-project the snapshot into the pre-rename "zewei" id space and
	# verify the rename migration rewrites every id token while keeping the
	# authored display name.
	var zewei_legacy: Dictionary = JSON.parse_string(JSON.stringify(saved).replace("flower_girl", "zewei"))
	check(zewei_legacy.living_world.society.residents.has("zewei"), "Fixture projects back to legacy zewei ids")
	s._migrate_rename_zewei(zewei_legacy)
	check(zewei_legacy.living_world.society.residents.has("flower_girl") and not zewei_legacy.living_world.society.residents.has("zewei"), "Rename migration moves the resident key to flower_girl")
	check(str(zewei_legacy.living_world.society.residents.flower_girl.name) == "zewei", "Authored display name survives the rename")
	check(zewei_legacy.living_world.society.focus.has("flower_girl") and not zewei_legacy.living_world.society.focus.has("zewei"), "Focus list follows the rename")
	check(s._valid_save(zewei_legacy), "Renamed legacy save validates against renamed config")
	var rename_once: Dictionary = zewei_legacy.duplicate(true)
	s._migrate_rename_zewei(zewei_legacy)
	check(zewei_legacy == rename_once, "Rename migration is idempotent")
	check(s.restore_save_data(zewei_legacy.duplicate(true), false) and w.actor("flower_girl") != null, "Renamed legacy save restores visible flower_girl")
	# Project the snapshot onto the immediately previous 36-resident roster.
	var legacy := saved.duplicate(true)
	legacy.npc_economy.npc_states = legacy.npc_economy.npc_states.filter(func(p): return p.npc_id != "flower_girl")
	legacy.living_world.society.residents.erase("flower_girl")
	legacy.living_world.society.focus.erase("flower_girl")
	legacy.living_world.society.initial_gold -= 3000
	legacy.living_world.positions.erase("flower_girl")
	legacy.agents.projection_checkpoint.actors = legacy.agents.projection_checkpoint.actors.filter(func(p): return p.actor_id != "flower_girl")
	legacy.agents.projection_checkpoint.actor_public_events = legacy.agents.projection_checkpoint.actor_public_events.filter(func(p): return p.actor_id != "flower_girl")
	legacy.agents.roles.roles = legacy.agents.roles.roles.filter(func(p): return p.agent_id != "flower_girl")
	var corrupt := legacy.duplicate(true)
	corrupt.npc_economy.npc_states[0].gold = -1
	var corrupt_before := corrupt.duplicate(true)
	s._migrate_flower_girl(corrupt)
	check(corrupt == corrupt_before and not s._valid_save(corrupt), "Corrupt legacy snapshot is untouched and rejected")
	var previous_accounts: Array = legacy.npc_economy.npc_states.duplicate(true)
	s._migrate_flower_girl(legacy)
	check(legacy.living_world.society.residents.has("flower_girl") and s._valid_save(legacy), "Legacy save migrates all account, role and projection state")
	check(legacy.npc_economy.npc_states.filter(func(p): return p.npc_id != "flower_girl") == previous_accounts and legacy.gold == saved.gold, "All previous accounts and player funds are unchanged")
	var once := legacy.duplicate(true)
	s._migrate_flower_girl(legacy)
	check(legacy == once, "Migration cannot grant resources twice")
	check(s.restore_save_data(legacy, false) and w.actor("flower_girl") != null, "Migrated save restores visible flower_girl")
	# Validate the user's real save read-only; do not restore or write it.
	if FileAccess.file_exists(s.DEFAULT_SAVE_PATH):
		var original_text := FileAccess.get_file_as_string(s.DEFAULT_SAVE_PATH)
		var actual: Dictionary = JSON.parse_string(original_text)
		s._migrate_rename_zewei(actual)
		s._migrate_flower_girl(actual)
		check(s._valid_save(actual), "Existing player save validates after additive migration")
		check(FileAccess.get_file_as_string(s.DEFAULT_SAVE_PATH) == original_text, "Player save file was not modified")
	if "--capture-zewei" in OS.get_cmdline_user_args():
		await capture(scene, w.actor("flower_girl"), s)
	check(w.society.set_focus("flower_girl", false).ok, "Focus remains configurable")
	check(s.save_game() and s.load_game() and "flower_girl" not in w.society.focus, "Later saves respect intentional focus changes")
	print("FLOWER_GIRL: %d checks, %d failures" % [checks, failures])
	scene.queue_free(); await process_frame
	quit(0 if failures == 0 else 1)

func capture(scene: Node, npc: Node3D, s: Node) -> void:
	for actor in s.agent_runtime.farm3d_actors.values(): actor.set_physics_process(false)
	for layer in root.find_children("*", "CanvasLayer", true, false): layer.hide()
	s.player.position = npc.position + Vector3(1.3,0,0)
	npc.refresh_dialogue_prompt()
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = npc.position + Vector3(.8, 1.7, 4.2)
	camera.look_at(npc.position + Vector3(.4, 1.1, 0), Vector3.UP)
	camera.fov = 45; camera.current = true
	for frame in range(20): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png("res://tmp/zewei-in-game.png") == OK, "Rendered in-game screenshot")
