extends SceneTree
var scene: Node
var s: Farm3DSession
var w: Node
var checks := 0
var failures := 0
class BudgetRegistry extends RefCounted:
	func get_agent_ids() -> Array: return ["a", "b", "c", "d", "e", "f"]
	func is_agent_managed(id: String) -> bool: return id in get_agent_ids()
	func get_agent(_id: String) -> Dictionary: return {"decision_interval_hours": [1, 1]}
class BudgetGateway extends RefCounted:
	var callbacks := {}
	var dispatched := []
	func request_decision(actor: String, request: Dictionary, done: Callable, _event: Callable) -> bool:
		callbacks[actor] = done; dispatched.append(actor); return not request.is_empty()
	func complete() -> void:
		var pending := callbacks.duplicate(); callbacks.clear()
		for callback in pending.values(): callback.call(true, {}, "")

func check_scheduler() -> void:
	var scheduler = preload("res://scripts/ai_agent/agent_scheduler.gd").new()
	var gateway := BudgetGateway.new()
	scheduler.configure(BudgetRegistry.new(), gateway, func(id, _trigger, minute, _text): return {"request_id": str(id) + str(minute)}, func(_id, _response): pass)
	scheduler.max_daily_requests = 6; scheduler.max_concurrent_requests = 2
	check(scheduler.advance_to(60) == 2 and scheduler._in_flight.size() == 2, "Private scheduling respects configured concurrency")
	gateway.complete(); scheduler.advance_to(61); gateway.complete(); scheduler.advance_to(62); gateway.complete()
	var unique := {}
	for actor in gateway.dispatched: unique[actor] = true
	check(unique.size() == 6 and scheduler.budget_calls == 6, "Rotation gives each eligible actor a daily turn")
	check(scheduler.advance_to(600) == 0, "Daily request cap delays additional planning")
	var saved: Dictionary = scheduler.budget_state(); scheduler.restore_budget(saved)
	check(scheduler.advance_to(0) == 0 and scheduler.budget_state() == saved, "Rewinding does not reopen the same day's budget")
	check(scheduler.advance_to(1080) == 2 and scheduler.budget_calls == 2, "Next game day resets the shared private allowance")
	gateway.complete()

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("P12 timeout"); quit(1))
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func run() -> void:
	check_scheduler()
	if "--living-world-scenario=P12" not in OS.get_cmdline_user_args(): push_error("P12 requires isolated expanded scenario flag"); quit(1); return
	scene = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	s = scene.farm_session; w = s.living_world
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	check(w.society.residents.size() == 36 and w.society.config.organizations.size() == 4, "Expanded scene has 36 residents and four original-ledger organizations")
	check(w.society.focus.size() == 6 and s.agent_runtime.farm3d_actors.size() == 6, "Six named actors are visible; population does not spawn 36 bodies")
	check(s.agent_runtime.registry.get_agent_ids().size() == 36, "All residents have eligible authored profiles without concurrent model calls")
	check(w.society.cooperative != null and w.society.cooperative.get_plot_count("village_coop") == 80, "Cooperative owns 80 actual map plots using original crop rules")
	var id := "resident_mei"
	var before: Dictionary = w.assets.snapshot(id)
	check(w.society.set_focus(id, true).ok and w.actor(id) != null, "Ordinary resident promotes using same actor identity")
	check(w.assets.snapshot(id) == before and w.society.residents.has(id), "Promotion does not mint or reset assets")
	check(w.society.set_focus(id, false).ok and w.actor(id) == null, "Idle resident demotes back to background simulation")
	check(w.assets.snapshot(id) == before, "Demotion preserves original account")
	check(reload_save(), "Expanded accounts, focus pool and original projects save/load")
	paused = true
	var paused_state: Dictionary = w.to_dict()
	w.advance()
	check(w.to_dict() == paused_state, "Modal pause stops all social work and consumption")
	paused = false
	s.season.advance_game_minutes(1080)
	check(not w.society.caught_up(w.minute()) and reload_save(), "Cross-day work saves and reloads while a bounded settlement batch is still pending")
	while not w.society.caught_up(w.minute()): w.advance(); await process_frame
	check(w.society.day_reports.has("1") and int(w.society.day_reports["1"].fed) + int(w.society.day_reports["1"].hungry) == 36, "All expanded residents consume or report shortfall once per day")
	check(reload_save(), "Expanded daily ledger persists")
	var paid: Array = w.society.shifts.values().filter(func(shift): return shift.employer_id == "village_coop" and shift.status == "completed")
	check(not paid.is_empty() and w.society.ledger.any(func(row): return row.kind == "seed_planted"), "Actual paid cooperative shifts consume seed and plant original crops")
	var planted := 0
	for plot in range(80):
		if w.society.cooperative.get_plot_cell("village_coop", plot).crop_instance != null: planted += 1
	check(planted > 0, "Background farming exists on the player's actual map")
	var bad: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(s.save_path))
	bad.living_world.planning.private.calls = 17
	check(not s._valid_save(bad), "Corrupt save cannot raise the configured daily request allowance")
	var legacy_path := "res://tmp/living-world/P12-legacy-fixture.json"
	check(FileAccess.file_exists(legacy_path), "Explicit isolated legacy migration fixture exists")
	if FileAccess.file_exists(legacy_path):
		var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
		var before_buildings: Array = legacy.buildings.duplicate(true)
		var original_gold: int = legacy.gold
		var corrupt := legacy.duplicate(true); corrupt.npc_economy.npc_states[0].gold = -1
		s._migrate_population(corrupt)
		check(corrupt.npc_economy.npc_states.size() == 14, "Corrupt old save is rejected before new endowments")
		s._migrate_population(legacy)
		if not s._valid_save(legacy): print("MIGRATION RESULT version=", legacy.version, " population=", legacy.living_world.society.residents.size(), " world=", w.validate_save(legacy), " agents=", s.agent_runtime.validate_dict(legacy.agents), " economy=", s.npc_economy.validate_dict(legacy.npc_economy))
		check(int(legacy.version) == 13 and legacy.living_world.society.residents.size() == 36 and s._valid_save(legacy), "Valid old event history migrates to expanded population")
		check(legacy.buildings == before_buildings and int(legacy.gold) == original_gold, "Migration preserves original buildings and player assets")
		var once := legacy.duplicate(true); s._migrate_population(legacy)
		check(legacy == once, "Population endowments cannot repeat")
		var f := FileAccess.open(s.save_path, FileAccess.WRITE); f.store_string(JSON.stringify(legacy, "  ")); f.close()
		check(s.load_game() and reload_save(), "Migrated full save loads and resaves without lost systems")
		await check_versions(JSON.parse_string(FileAccess.get_file_as_string(legacy_path)))
	print("P12: %d checks, %d failures" % [checks, failures])
	scene.queue_free(); await process_frame; quit(0 if failures == 0 else 1)

func reload_save() -> bool:
	if not s.save_game(): return false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(s.save_path))
	if not s._valid_save(data): print("P12 SAVE world=", w.validate_save(data), " society=", w.society.validate(data.living_world.society), " agents=", s.agent_runtime.validate_dict(data.agents), " economy=", s.npc_economy.validate_dict(data.npc_economy))
	return s.load_game()

func check_versions(fixture: Dictionary) -> void:
	# Project older envelopes onto the original twelve-person fixture. These
	# exercise every supported reader; they are not historical player save files.
	for version in range(1, 13):
		var old := fixture.duplicate(true); old.version = version
		old.living_world.erase("planning"); old.living_world.version = 6
		if version < 12: old.living_world.erase("social"); old.living_world.version = 5
		if version < 11: old.living_world.erase("environment"); old.living_world.version = 4
		if version < 10: old.living_world.erase("work"); old.living_world.version = 3
		if version < 9: old.living_world.erase("public_plans"); old.living_world.version = 2
		if version < 8: old.living_world.erase("interruptions"); old.living_world.version = 1
		if version < 7: old.erase("living_world")
		if version < 5: old.erase("agents")
		if version < 4: old.erase("golf")
		if version < 3:
			for key in ["market", "market_site", "npc_economy"]: old.erase(key)
		if version < 2:
			for key in ["gold", "paddy_cells", "production", "buildings"]: old.erase(key)
			old.grid.cells = old.grid.cells.filter(func(cell): return int(cell.state) != GridCell.State.BUILDING)
		s.save_path = "res://tmp/living-world/P12-migrate-v%d.json" % version
		var f := FileAccess.open(s.save_path, FileAccess.WRITE); f.store_string(JSON.stringify(old, "  ")); f.close()
		var loaded := s.load_game()
		check(loaded and w.society.residents.size() == 36 and s.npc_economy._states.size() == 40, "Version %d migrates to one expanded population" % version)
		if loaded:
			check(reload_save(), "Version %d migration saves and reloads once" % version)
		await process_frame
