extends RefCounted

## Whitelist projection. Never pass private inventories, plans, discoveries or dialogue.
static func build(system: RefCounted, request_id: String, trigger: String) -> Dictionary:
	var world: Node = system.world
	var runtime: Node = world.session.agent_runtime
	var minute: int = world.minute()
	var profile: Dictionary = system.registry.get_agent("village_public")
	var request := {"protocol_version": 2, "request_id": request_id, "session_id": runtime.session_id, "session_epoch": runtime.gateway.session_epoch,
		"agent_id": "village_public", "trigger": trigger, "game_minute": minute, "world_revision": system.revision, "projection_schema_version": 1,
		"active_role": "public_coordinator", "goals": profile.goals, "allowed_read_tools": [], "allowed_command_tools": profile.tools,
		"actor_context": {"public_coordination": {"social": world.social.context(), "environment": world.environment.context(), "mode": system.mode, "version": system.revision, "indicators": system.indicators(), "budget": system.budget(), "plans": system.public_plans(),
			"rules": "Use only authorized public funds. public_repair_plan can fund actual blocked-route materials procurement and up to 60 gold for 60 actual labor minutes, within the same daily 800 gold ceiling. Natural recovery is a valid alternative. public_activity_plan can sponsor a voluntary fishing/golf activity from actual funds, at most 500 gold and within the shared daily ceiling. No obligation to organize; unmet essential food takes priority. NPCs decide independently whether to spectate. No prices, private inventories, private knowledge or NPC orders are under your authority. For urgent food access with inadequate funded incoming supply, you may publish a limited bread purchase (1-12 units, unit reward 1-200, deadline 60-1080 game minutes) or explicitly wait. Use bread_market_sell_one and highest_open_bread_reward as public reference prices: private suppliers may choose those alternatives. If buying the full gap at a credible price exceeds the daily budget, buy a smaller affordable quantity or wait; do not invent willingness to accept an underpriced offer. There is no obligation to intervene. Respect the 800 gold daily ceiling, existing public escrow, 180-minute cooldown and available funds. Existing funded plans remain valid when new planning stops. Recipients receive actual procured bread by deterministic need checks. Observe mode records analysis only. expected_version must equal the supplied version. Explain why the chosen quantity and payment address the observed gap."}},
		"public_world_state": {"absolute_game_minute": minute}, "global_public_events": [], "known_actors": [], "own_event_delta": [],
		"market_summary": {"schema_version": 1, "role_id": "public_coordinator", "generated_game_minute": minute, "overview": {"item_count": 0, "shortage_count": 0, "surplus_count": 0, "rising_count": 0, "falling_count": 0}, "signals": []},
		"market_view": {}, "interaction_view": {}, "agreement_view": {}}
	return request
