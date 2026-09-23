extends RefCounted

# Public knowledge is updated separately. These rules select who needs a new
# autonomous decision, using authoritative state rather than an LLM classifier.
static func autonomous(runtime: Node, actor: String) -> bool:
	if not runtime.registry.is_agent_managed(actor): return false
	if not is_instance_valid(runtime.farm3d_session): return true
	var world: Node = runtime.farm3d_session.living_world
	return world != null and actor in world.society.focus

static func recipients(runtime: Node, topic: String, details: Dictionary, minute: int) -> Array:
	var result: Array = []
	for actor in runtime.registry.get_agent_ids():
		if not autonomous(runtime, actor): continue
		var role: String = runtime.registry.get_agent(actor).get("role_id", "")
		var interested := false
		match topic:
			"market_price", "market_stock", "market_pressure":
				interested = interested_in_item(runtime, actor, str(details.get("item_id", "")), minute)
			"weather":
				interested = role in ["farmer", "explorer"]
			"season":
				interested = role == "farmer"
			"environment":
				# Producers must name the affected actors; unknown conditions never broadcast.
				var affected: Variant = details.get("affected_actor_ids", [])
				interested = affected is Array and actor in affected
		if interested: result.append(actor)
	return result

static func interested_in_item(runtime: Node, actor: String, item: String, minute: int) -> bool:
	if item.is_empty(): return false
	var state = runtime._npc_economy.get_npc_state(actor)
	if state != null and (int(state.inventory.get(item, 0)) > 0 or int(state.reserve_targets.get(item, 0)) > 0): return true
	if is_instance_valid(runtime.farm3d_session):
		for request in runtime._market.merchant.get("requests", {}).values():
			if request.actor == actor and request.item_id == item and int(request.expires) > minute: return true
	for offer in runtime.interaction_system.list_offers(actor):
		if offer.status != "open" or int(offer.expires_game_minute) <= minute: continue
		if offer.proposer_gives.items.has(item) or offer.proposer_receives.items.has(item): return true
	# Typed goal conditions express an actual item dependency; do not match prose.
	for goal in runtime.loop_state.goals.values():
		if goal.actor_id != actor or goal.status not in ["active", "blocked"] or int(goal.expires_at) <= minute: continue
		var condition: Dictionary = goal.get("success_condition", {})
		if condition.get("kind") == "inventory_at_least" and condition.get("id") == item: return true
	return false

static func accepts(runtime: Node, actor: String, kind: String, source: String) -> bool:
	# Old world_event entries have no routing details; discard them for background
	# actors too. Directed obligations remain queued even if their actor is demoted.
	if kind == "clock" or source.begins_with("ambient:") or source == "world_event":
		return autonomous(runtime, actor)
	return true
