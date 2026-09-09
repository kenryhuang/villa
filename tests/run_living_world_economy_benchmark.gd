extends SceneTree

var scene: Node
var s: Farm3DSession
var w: Node
var seed_value := 42
var group := "rules"
var rows := []
var replay := []
var errors := []
var ended := false
var opening_gold := 0
var strategy := "observer"
var player_plots: Array[Vector2i] = []
var player_actions := []
var player_market_net := 0

func _initialize() -> void:
	create_timer(900).timeout.connect(func(): finish(false, "Economic simulation timeout"))
	run.call_deferred()

func run() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args() or "--living-world-scenario=P12" not in OS.get_cmdline_user_args(): finish(false, "Isolation flags required"); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--group="): group = arg.trim_prefix("--group=")
		if arg.begins_with("--strategy="): strategy = arg.trim_prefix("--strategy=")
	if strategy not in ["observer", "farmer", "trader"]: finish(false, "Unknown player strategy"); return
	if group not in ["rules", "private", "public"]: finish(false, "Unknown group"); return
	if group != "rules":
		var source := "res://tmp/living-world/P12-live-2.json"
		if not FileAccess.file_exists(source): finish(false, "Real model replay evidence required"); return
		var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
		if not recorded.ok: finish(false, "Source observation incomplete"); return
		replay = recorded.trace
	scene = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	s = scene.farm_session; w = s.living_world
	scene.set_process(false); w.set_process(false); s.season.set_process(false); s.player.set_physics_process(false)
	s.agent_runtime.service_enabled = false
	s.save_path = "res://tmp/living-world/P12-economy-%s-%d-save.json" % [group, seed_value]
	if strategy != "observer": s.save_path = "res://tmp/living-world/P12-strategy-%s-%d-save.json" % [strategy, seed_value]
	w.environment.seed = seed_value; w.environment.days.clear(); w.environment.ensure_day(0)
	w.society.batch_times_us.clear(); w.society.batch_max_us = 0
	opening_gold = conserved_gold() - w.society.external_gold_net
	for actor in w.society.focus: w.actor(actor).move_speed = 40
	for day in 28:
		if strategy == "farmer": player_farm_day(day)
		if strategy == "trader": player_trade(day, "potato", 4, day % 2 == 0)
		if not replay.is_empty(): replay_day(day)
		for tick in 216:
			if strategy == "farmer" and tick == 215: s.rest()
			else: s.season.advance_game_minutes(5)
			while not w.society.caught_up(w.minute()): w.advance(); await process_frame
			w.advance()
			if group == "rules": await process_frame
			else: await physics_frame
		var balances := {}
		for actor in s.npc_economy._states:
			var state: NpcEconomyState = s.npc_economy.get_npc_state(actor)
			balances[actor] = state.gold
			if state.gold < 0 or state.inventory.values().any(func(n): return int(n) < 0): errors.append("negative assets: " + actor)
		var report: Dictionary = w.society.day_reports.get(str(day + 1), {}).duplicate(true)
		var difference: int = conserved_gold() - opening_gold - w.society.external_gold_net - player_market_net
		if difference != 0: errors.append("gold boundary mismatch day %d: %d" % [day + 1, difference])
		if int(report.get("fed", 0)) + int(report.get("hungry", 0)) != 36: errors.append("missing daily resident settlement")
		rows.append({"day": day + 1, "food": report, "gold_difference": difference, "balances": balances, "market": s.market.to_dict(), "route_open": w.environment.route_open(), "projects": w.projects.projects.size(), "public_plans": w.public_plans.plans.size()})
		if day % 7 == 6:
			print("P12 before weekly save day ", day + 1)
			if not s.save_game() or not s.load_game(): errors.append("save/reload day %d" % (day + 1))
			print("P12 economic %s seed %d day %d hungry=%d" % [group, seed_value, day + 1, int(report.get("hungry", 0))])
	finish(errors.is_empty(), "28 days measured; starvation and irrational choices remain explicit metrics")

func player_farm_day(day: int) -> void:
	if player_plots.is_empty():
		for cell in s.grid._cells.values():
			var point: Vector2 = cell.world_position()
			if point.length() > 8 or cell.state != GridCell.State.WASTELAND or cell.slope > .1 or not s.grid.can_actor_use_cell(cell.gx, cell.gz, "player"): continue
			player_plots.append(Vector2i(cell.gx, cell.gz))
			if player_plots.size() == 4: break
	for pos in player_plots:
		var cell := s.grid.get_cell(pos.x, pos.y)
		if s.inventory.get_item_count("carrot_seed") == 0: player_trade(day, "carrot_seed", 4, true)
		s.player.position = cell.world_position_3d() + Vector3.LEFT
		if cell.crop_instance != null and cell.crop_instance.is_harvestable():
			player_actions.append({"day": day + 1, "action": "harvest", "result": s.act(cell, "harvest")})
		if cell.state == GridCell.State.WASTELAND: player_actions.append({"day": day + 1, "action": "hoe", "result": s.act(cell, "hoe")})
		if cell.state == GridCell.State.FARMLAND: player_actions.append({"day": day + 1, "action": "seed", "result": s.act(cell, "seed", "carrot_seed")})
		if cell.crop_instance != null: player_actions.append({"day": day + 1, "action": "water", "result": s.act(cell, "water")})
	if s.inventory.get_item_count("carrot") > 8: player_trade(day, "carrot", 4, false)

func player_trade(day: int, item: String, count: int, buy: bool) -> void:
	s.player.position = Vector3(s.market_site.x, 0, s.market_site.y + 4)
	var before: int = root.get_node("GameState").gold
	var ok: bool = s.economy.buy_item(item, count) if buy else s.economy.sell_item(item, count)
	var net: int = root.get_node("GameState").gold - before
	player_market_net += net
	player_actions.append({"day": day + 1, "action": "buy" if buy else "sell", "item_id": item, "quantity": count, "external_market_gold": net, "result": {"ok": ok}})

func conserved_gold() -> int:
	var total: int = root.get_node("GameState").gold + w.society.total_gold() + w.society.wage_escrow()
	for table in [w.projects.projects, w.work.contracts, w.interruptions.tasks, w.knowledge.assignments]:
		for record in table.values(): total += int(record.get("gold", 0))
	for c in w.board.commissions.values(): total += int(c.escrow)
	for fund in w.environment.public_funding.values(): total += int(fund.escrow)
	for event in w.social.events.values(): total += int(event.cash)
	for transport in w.environment.transports.values(): total += int(transport.cost)
	for building in s.buildings.get_all_buildings():
		for job in building.producer_state.jobs:
			if job.get("payment_state") == "escrow": total += int(job.rental_fee)
	return total

func replay_day(day: int) -> void:
	for trace in replay:
		var decision: Dictionary = trace.get("final", {})
		if decision.is_empty(): continue
		var source_day := -1
		for message in trace.get("input", {}).get("messages", []):
			if message.get("role") != "user": continue
			var context: Variant = JSON.parse_string(str(message.get("content", "")))
			if context is Dictionary and context.get("public_world_state") is Dictionary:
				source_day = int(context.public_world_state.get("absolute_game_minute", -1080)) / 1080; break
		if source_day != day % 14: continue
		var actor := str(decision.get("agent_id", ""))
		if actor == "village_public":
			if group != "public": continue
			for a in decision.get("actions", []):
				var args: Dictionary = a.arguments.duplicate(true); args.expected_version = w.public_plans.revision
				w.public_plans.command(actor, a.tool_name, args, "replay-%d-%s" % [day, a.idempotency_key])
		else:
			var response := decision.duplicate(true)
			response.expected_revision = s.agent_runtime.executor.world_revision
			response.request_id = "replay-%d-%s" % [day, response.request_id]
			response.decision_id = response.request_id
			for a in response.actions: a.idempotency_key = "replay-%d-%s" % [day, a.idempotency_key]
			s.agent_runtime._handle_response(actor, response)

func finish(ok: bool, reason: String) -> void:
	if ended: return
	ended = true
	if w != null:
		var samples: Array = w.society.batch_times_us.duplicate(); samples.sort()
		var result_path := "res://tmp/living-world/P12-economy-%s-%d.json" % [group, seed_value] if strategy == "observer" else "res://tmp/living-world/P12-strategy-%s-%d.json" % [strategy, seed_value]
		if strategy == "farmer" and not player_actions.any(func(a): return a.action == "harvest" and a.result.ok): ok = false; errors.append("Player strategy never produced a real harvest")
		var f := FileAccess.open(result_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"ok": ok, "reason": reason, "errors": errors, "strategy": strategy, "player_actions": player_actions, "player_market_net": player_market_net, "seed": seed_value, "group": group, "rows": rows, "batch_p95_us": samples[int(samples.size() * .95)] if not samples.is_empty() else 0, "batch_max_us": w.society.batch_max_us, "frame_max_us": w.society_frame_max_us, "world": w.to_dict(), "outcomes": s.agent_runtime.executor.to_dict()}, "  ")); f.close()
	print("P12 economy: %s · %s" % [ok, reason]); quit(0 if ok else 1)
