extends SceneTree

var checks := 0
var failures := 0
var folder := "res://tmp/npc-snapshot-tests/"

func _initialize() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args() or "--living-world-scenario=P12" not in OS.get_cmdline_user_args():
		push_error("Use --farm-test --living-world-scenario=P12"); quit(2); return
	create_timer(90, true, false, true).timeout.connect(func(): push_error("Snapshot timeout"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  ")); file.close()

func assets(s: Node) -> Dictionary:
	return {"economy": s.npc_economy.to_dict(), "inventory": s.inventory.slots.duplicate(true), "gold": root.get_node("GameState").gold, "buildings": s.buildings.get_all_buildings().map(func(b): return b.to_dict()), "projects": s.living_world.projects.to_dict(), "work": s.living_world.work.to_dict()}

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var farm: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var s: Node = farm.farm_session
	s.season.set_process(false); s.living_world.set_process(false)
	s.player.set_physics_process(false)
	var runtime: Node = s.agent_runtime
	check(not s.auto_save and not runtime.service_enabled, "Tests do not save player data or contact providers")
	s.save_path = folder + "source.json"
	check(s.save_game(), "Fresh farm writes current-state format")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(s.save_path))
	var legacy := source.duplicate(true)
	legacy.agents.version = runtime.VERSION
	legacy.agents.event_store = runtime.event_store.to_dict()
	legacy.agents.event_schema_version = runtime.EVENT_SCHEMA_VERSION
	legacy.agents.perception_inbox = runtime.perception_inbox.to_dict()
	legacy.agents.projection_checkpoint = runtime.world_projector.to_dict()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--legacy-save="):
			legacy = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--legacy-save=")))
	for field in ["actor_events", "roles", "receipts", "continuations"]:
		var bad: Dictionary = legacy.agents.duplicate(true)
		match field:
			"actor_events": bad.projection_checkpoint.actor_public_events = {}
			"roles": bad.roles.roles = {}
			"receipts": bad.interactions.idempotency_results = {}
			"continuations": bad.executor.continuations = []
		check(not runtime.validate_dict(bad), "Malformed legacy snapshot rejects safely: " + field)
	write_json(folder + "legacy.json", legacy)
	s.save_path = folder + "legacy.json"
	var started := Time.get_ticks_usec()
	check(s.load_game(), "Existing full-history save restores directly from its state checkpoint")
	print("SNAPSHOT legacy_load_ms=", (Time.get_ticks_usec()-started)/1000.0)
	if failures > 0: quit(1); return
	check(s.season.total_days == legacy.season.total_days and s.buildings.get_building_count() == legacy.buildings.size(), "Migration keeps day and every building")
	check(JSON.parse_string(JSON.stringify(s.npc_economy.to_dict())) == legacy.npc_economy, "Migration preserves all NPC gold and inventory")
	var before := assets(s)
	var sequence: int = runtime.world_projector.get_last_sequence()
	check(runtime.event_store.get_last_sequence() == sequence and runtime.event_store.get_events_after(0).is_empty(), "Checkpoint starts synchronized without historical event replay")
	check(runtime.perception_inbox._world_events_by_agent.values().all(func(v): return v.is_empty()), "No historical inbox is restored")
	var snapshot: Dictionary = runtime.to_dict()
	check(snapshot.version == runtime.CURRENT_STATE_VERSION and not snapshot.has("event_store") and not snapshot.has("perception_inbox"), "NPC save contains present state, not a journal or inbox")
	check(snapshot.projection_checkpoint.global_public_events.is_empty() and snapshot.projection_checkpoint.actor_public_events.all(func(r): return r.events.is_empty()), "Observed event history is absent from checkpoint")
	check(snapshot.roles.roles.all(func(r): return r.history == [r.active_role_id]), "Only the active occupation is retained")
	check(snapshot.interactions.idempotency_results.all(func(r): return r.result.get("events", []).is_empty()), "Trade receipts contain no duplicated historical events")
	s.save_path = folder + "current.json"
	started = Time.get_ticks_usec()
	check(s.save_game(), "Migrated farm writes snapshot")
	var save_ms := (Time.get_ticks_usec()-started)/1000.0
	var saved_bytes := FileAccess.get_file_as_bytes(s.save_path).size()
	print("SNAPSHOT bytes=", saved_bytes, " save_ms=", save_ms)
	check(FileAccess.get_file_as_string(s.save_path).contains("\n  "), "Human-readable indented JSON remains")
	started = Time.get_ticks_usec()
	check(s.load_game(), "Snapshot restores without its discarded history")
	print("SNAPSHOT current_load_ms=", (Time.get_ticks_usec()-started)/1000.0)
	check(assets(s) == before, "Reload keeps ownership, player/NPC assets, current projects and work")
	var protected_state: Dictionary = runtime.to_dict()
	for kind in ["sequence", "role", "actor", "executor", "extra"]:
		var bad: Dictionary = protected_state.duplicate(true)
		match kind:
			"sequence": bad.checkpoint_sequence += 1
			"role": bad.roles.roles[0].active_role_id = "not-a-role"
			"actor": bad.projection_checkpoint.actors[0].actor_id = "not-an-actor"
			"executor": bad.executor.world_revision = -1
			"extra": bad.event_store = {}
		check(not runtime.from_dict(bad), "Invalid snapshot rejected: " + kind)
		check(runtime.to_dict() == protected_state and assets(s) == before, "Rejected snapshot leaves state intact: " + kind)
	var minute: int = runtime._absolute_game_minute()
	for i in 400:
		check(runtime.world_fact_bridge.publish_time(s.season.hour, s.season.minute, minute, "snapshot-event-%d" % i), "Live event commits after snapshot: %d" % i)
	check(runtime.event_store.get_events_after(0).size() <= 128 and runtime.event_store._idempotency_results.size() <= 128, "Transient event store and event publication cache stay bounded")
	check(runtime.perception_inbox._world_events_by_agent.values().all(func(v): return v.size() <= 64), "Background residents cannot accumulate unbounded unread events")
	check(runtime.world_projector.get_last_sequence() == runtime.event_store.get_last_sequence(), "Bounded event delivery keeps projector synchronized")
	check(s.save_game() and s.load_game(), "Save/load still works after event ring wraps")
	check(assets(s) == before, "Transient event churn never changes saved ownership/assets")
	check(FileAccess.get_file_as_bytes(s.save_path).size() < saved_bytes + 4096, "400 transient events do not grow the snapshot")
	for i in 8: await process_frame
	farm.queue_free(); await process_frame; await process_frame
	print("NPC snapshots: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
