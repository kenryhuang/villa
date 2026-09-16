extends RefCounted

const GOAL_TOOLS := ["adopt_short_term_goal", "revise_short_term_goal", "abandon_short_term_goal"]
var goals: Dictionary = {}
var pending: Dictionary = {}
var resources: Dictionary = {}
var loops: Dictionary = {}
var feedback: Dictionary = {}
var queued_triggers: Dictionary = {}

func snapshot(runtime: Node, actor: String) -> Dictionary:
	var state = runtime._npc_economy.get_npc_state(actor)
	if state == null: return {}
	var value: Dictionary = state.to_dict()
	var fingerprint := JSON.stringify(value).sha256_text()
	var previous: Dictionary = resources.get(actor, {})
	var revision := int(previous.get("resource_revision", 0))
	if previous.get("fingerprint", "") != fingerprint: revision += 1
	value.resource_revision = revision
	value.observed_game_minute = runtime._absolute_game_minute()
	resources[actor] = {"resource_revision": revision, "fingerprint": fingerprint}
	return value

func record(actor: String, event: Dictionary) -> void:
	if actor.is_empty() or not event.has("event_id"): return
	if not pending.has(actor): pending[actor] = {}
	pending[actor][str(event.event_id)] = event.duplicate(true)

func capture(runtime: Node) -> void:
	runtime.perception_inbox.transient_event_limit = 0
	for actor in runtime.registry.get_agent_ids():
		var key := "loop-capture:" + str(actor)
		var events: Array = runtime.perception_inbox.freeze_delta(actor, key)
		for event in events:
			if event.get("event_type") == "TimeChanged": continue
			var payload: Dictionary = event.get("payload", {}).duplicate(true)
			# Market histories belong to the market reader, not every event message.
			for field in ["price_history", "depth", "market_summary", "market_view"]: payload.erase(field)
			record(actor, {"event_id": event.event_id, "kind": event.get("event_type", "world"), "game_minute": event.game_minute, "payload": payload})
		runtime.perception_inbox.acknowledge_delta(actor, key)

func acknowledge(actor: String, ids: Array) -> void:
	for id in ids: pending.get(actor, {}).erase(str(id))

func events(actor: String) -> Array:
	return pending.get(actor, {}).values().duplicate(true)

func goal_refs(actor: String, minute: int) -> Array:
	var result: Array = []
	for goal in goals.values():
		if goal.actor_id != actor or goal.status not in ["active", "blocked"]: continue
		if int(goal.expires_at) <= minute:
			goal.status = "expired"
			goal.version += 1
			record(actor, {"event_id": "%s:%d" % [goal.goal_id, goal.version], "kind": "GoalExpired", "game_minute": minute, "payload": goal.duplicate(true)})
			continue
		result.append({"goal_id": goal.goal_id, "description": goal.description, "status": goal.status, "review_at": goal.review_at})
	return result.slice(0, 3)

static func valid_goal(tool: String, a: Dictionary) -> bool:
	if tool == "adopt_short_term_goal":
		return a.size() == (5 if a.has("success_condition") else 4) and valid_condition(a.get("success_condition", {})) and a.get("description") is String and a.description.length() in range(1, 501) and a.get("source_event_ids") is Array and a.source_event_ids.size() <= 8 and a.source_event_ids.all(func(id): return id is String and id.length() in range(1, 161)) and a.get("ttl_minutes") is int and int(a.ttl_minutes) in range(1, 10081) and a.get("review_in_minutes") is int and int(a.review_in_minutes) in range(1, 1081)
	if tool == "revise_short_term_goal":
		return a.size() == 5 and a.get("goal_id") is String and a.get("version") is int and a.version > 0 and a.get("description") is String and a.description.length() in range(1, 501) and a.get("status") in ["active", "blocked"] and a.get("review_in_minutes") is int and int(a.review_in_minutes) in range(1, 1081)
	return tool == "abandon_short_term_goal" and a.size() == 3 and a.get("goal_id") is String and a.get("version") is int and a.version > 0 and a.get("reason") is String and a.reason.length() in range(1, 501)

static func valid_condition(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	return value.size() == 3 and value.get("kind") in ["inventory_at_least", "project_completed", "discovery_known"] and value.get("id") is String and value.id.length() in range(1, 161) and value.get("quantity") is int and value.quantity in range(1, 10001)

func evaluate_goals(runtime: Node, minute: int) -> void:
	# Expiry is checked before success; a late receipt cannot revive an expired goal.
	for actor in runtime.registry.get_agent_ids(): goal_refs(actor, minute)
	for goal in goals.values():
		if goal.status not in ["active", "blocked"]: continue
		var condition: Dictionary = goal.get("success_condition", {})
		if condition.is_empty(): continue
		var completed := false
		match condition.kind:
			"inventory_at_least":
				var state = runtime._npc_economy.get_npc_state(goal.actor_id)
				completed = state != null and int(state.inventory.get(condition.id, 0)) >= int(condition.quantity)
			"project_completed":
				var project: Dictionary = runtime.farm3d_session.living_world.projects.projects.get(condition.id, {})
				completed = project.get("actor_id") == goal.actor_id and project.get("status") == "completed"
			"discovery_known": completed = runtime.knowledge_registry.get_private(goal.actor_id).has(condition.id) or runtime.knowledge_registry.is_public(condition.id)
		if completed:
			goal.status = "completed"
			goal.version += 1
			record(goal.actor_id, {"event_id": "%s:%d" % [goal.goal_id, goal.version], "kind": "GoalCompleted", "game_minute": minute, "payload": {"goal_id": goal.goal_id, "condition": condition, "status": "completed"}})

func command(actor: String, tool: String, a: Dictionary, key: String, minute: int) -> Dictionary:
	if not valid_goal(tool, a): return {"ok": false, "error": "invalid_goal_arguments"}
	var goal: Dictionary
	if tool == "adopt_short_term_goal":
		goal_refs(actor, minute)
		if goals.values().filter(func(g): return g.actor_id == actor and g.status in ["active", "blocked"]).size() >= 3: return {"ok": false, "error": "goal_capacity"}
		var id := "goal-" + key.sha256_text().substr(0, 24)
		goal = {"goal_id": id, "actor_id": actor, "version": 1, "description": a.description, "status": "active", "source_event_ids": a.source_event_ids.duplicate(), "success_condition": a.get("success_condition", {}).duplicate(true), "created_at": minute, "expires_at": minute + int(a.ttl_minutes), "review_at": minute + int(a.review_in_minutes)}
		goals[id] = goal
	else:
		goal = goals.get(a.goal_id, {})
		if goal.is_empty() or goal.actor_id != actor or goal.version != a.version or goal.status not in ["active", "blocked"]: return {"ok": false, "error": "goal_changed"}
		goal.version += 1
		if tool == "abandon_short_term_goal":
			goal.status = "abandoned"
			goal.reason = a.reason
		else:
			goal.description = a.description
			goal.status = a.status
			goal.review_at = minute + int(a.review_in_minutes)
	var event := {"event_id": "%s:%d" % [goal.goal_id, goal.version], "kind": "GoalChanged", "game_minute": minute, "payload": goal.duplicate(true)}
	record(actor, event)
	return {"ok": true, "goal_id": goal.goal_id, "goal_status": goal.status, "mutated": true, "changed_entities": ["goal:" + str(goal.goal_id)]}

func finish_batches(runtime: Node, minute: int) -> void:
	for id in loops.keys():
		var loop: Dictionary = loops[id]
		if loop.state != "executing": continue
		var results: Array = []
		for action_id in loop.action_ids:
			if loop.get("receipts", {}).has(action_id):
				results.append(loop.receipts[action_id])
				continue
			for outcome in runtime.executor._outcomes.values():
				if outcome.action_id == action_id: results.append(outcome)
		if results.any(func(o): return o.status == "in_progress"): continue
		if results.size() < loop.action_ids.size() and not results.any(func(o): return o.status in ["failed", "rejected"]): continue
		loop.state = "closed"
		loop.finished = minute
		var skipped: Array = loop.action_ids.filter(func(action_id): return not results.any(func(o): return o.action_id == action_id))
		record(loop.agent_id, {"event_id": "batch:" + str(id), "kind": "BatchFinished", "game_minute": minute, "payload": {"loop_id": id, "results": results.map(func(o): return {"action_id": o.action_id, "status": o.status}), "skipped": skipped}})
		var terminal_problem: bool = results.any(func(o): return o.status in ["failed", "rejected"])
		var useful: bool = results.any(func(o): return o.tool_name not in ["wait", "speak", "send_message"] and o.tool_name not in GOAL_TOOLS)
		if terminal_problem or (useful and not goal_refs(loop.agent_id, minute).is_empty()):
			var previous: Dictionary = feedback.get(loop.agent_id, {})
			var count := int(previous.get("count", 0)) + 1
			feedback[loop.agent_id] = {"ready_at": minute + (60 if count >= 3 else 1), "count": 0 if count >= 3 else count, "pending": true}
		if loop.trigger != "dialogue": runtime.scheduler._last_dispatched[loop.agent_id] = minute
	var closed: Array = loops.keys().filter(func(id): return loops[id].state in ["closed", "cancelled", "failed"])
	for id in closed.slice(0, maxi(0, closed.size()-64)): loops.erase(id)

func has_execution(actor: String) -> bool:
	return loops.values().any(func(loop): return loop.agent_id == actor and loop.state == "executing" and not loop.action_ids.is_empty())

func to_dict() -> Dictionary:
	return {"version": 1, "goals": goals.duplicate(true), "pending": pending.duplicate(true), "resources": resources.duplicate(true), "loops": loops.duplicate(true), "feedback": feedback.duplicate(true), "queued_triggers": queued_triggers.duplicate(true)}

func restore(value: Dictionary) -> void:
	goals = value.get("goals", {}).duplicate(true)
	pending = value.get("pending", {}).duplicate(true)
	resources = value.get("resources", {}).duplicate(true)
	loops = value.get("loops", {}).duplicate(true)
	feedback = value.get("feedback", {}).duplicate(true)
	queued_triggers = value.get("queued_triggers", {}).duplicate(true)
	for loop in loops.values():
		if loop.state == "reasoning":
			loop.state = "cancelled"
			if loop.trigger != "dialogue": queued_triggers[loop.agent_id] = {"trigger": "event", "game_minute": int(loop.get("started", 0)), "dialogue": "", "priority": 2}

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.get("version") != 1: return false
	for key in ["goals", "pending", "resources", "loops", "feedback"]:
		if not value.get(key) is Dictionary: return false
	if not value.get("queued_triggers", {}) is Dictionary: return false
	for queued in value.get("queued_triggers", {}).values():
		if not queued is Dictionary or queued.get("trigger") not in ["event", "schedule", "catch_up"] or not queued.get("game_minute") is int or not queued.get("dialogue") is String or not queued.get("priority") is int: return false
	for snapshot_value in value.resources.values():
		if not snapshot_value is Dictionary or not snapshot_value.get("resource_revision") is int or snapshot_value.resource_revision < 0 or not snapshot_value.get("fingerprint") is String: return false
	for entry in value.feedback.values():
		if not entry is Dictionary or not entry.get("ready_at") is int or entry.ready_at < 0 or not entry.get("count") is int or entry.count < 0 or not entry.get("pending") is bool: return false
	for goal in value.goals.values():
		if not goal is Dictionary or not goal.get("goal_id") is String or not goal.get("actor_id") is String or not goal.get("description") is String or goal.get("status") not in ["active", "blocked", "completed", "abandoned", "expired"]: return false
		if not valid_condition(goal.get("success_condition", {})): return false
		for key in ["version", "created_at", "expires_at", "review_at"]:
			if not goal.get(key) is int or goal[key] < 0: return false
	for actor in value.pending:
		if not actor is String or not value.pending[actor] is Dictionary: return false
		for event in value.pending[actor].values():
			if not event is Dictionary or not event.get("event_id") is String or not event.get("kind") is String or not event.get("game_minute") is int or not event.get("payload") is Dictionary: return false
	for loop in value.loops.values():
		if not loop is Dictionary or not loop.get("agent_id") is String or loop.get("state") not in ["reasoning", "executing", "closed", "failed", "cancelled"] or not loop.get("action_ids") is Array or not loop.get("trigger") is String: return false
	return true
