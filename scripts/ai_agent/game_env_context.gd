extends RefCounted

## Public actor has its own capabilities and only authorized public resources.
static func build(system: RefCounted, request_id: String, trigger: String) -> Dictionary:
	var runtime: Node = system.world.session.agent_runtime
	var profile: Dictionary = system.registry.get_agent("village_public")
	return {"protocol_version": 3, "request_id": request_id, "session_id": runtime.session_id, "session_epoch": runtime.gateway.session_epoch,
		"agent_id": "village_public", "trigger": trigger, "game_minute": system.world.minute(), "world_revision": system.revision,
		"active_role": "public_coordinator", "goals": profile.goals, "allowed_command_tools": profile.tools,
		"resources": runtime.loop_state.snapshot(runtime, "village_public"), "experience_events": runtime.loop_state.events("village_public"), "goal_refs": []}
