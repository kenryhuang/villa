extends RefCounted

const NpcScript = preload("res://scripts/actors/npc.gd")
const NpcScene = preload("res://scenes/actors/npc.tscn")

class SignalSpy:
	extends RefCounted
	var defeated_count := 0
	var dialogue_count := 0
	var last_villager_id := ""

	func on_defeated(_npc) -> void:
		defeated_count += 1

	func on_dialogue_started(villager_id: String) -> void:
		dialogue_count += 1
		last_villager_id = villager_id

func run(assertions, tree: SceneTree) -> void:
	var npc = NpcScript.new()
	var spy := SignalSpy.new()
	npc.defeated.connect(spy.on_defeated)
	npc.take_hit(2, Vector3.RIGHT)
	assertions.equal(npc.health, 1, "npc loses health")
	assertions.truthy(npc.knockback_velocity.x > 0.0, "npc receives knockback")
	npc.take_hit(1, Vector3.ZERO)
	npc.take_hit(1, Vector3.ZERO)
	assertions.equal(npc.health, 0, "npc health clamps at zero")
	assertions.equal(spy.defeated_count, 1, "npc emits defeated once")
	npc.free()

	var scene_npc = NpcScene.instantiate()
	var player := Node3D.new()
	tree.root.add_child(scene_npc)
	tree.root.add_child(player)
	assertions.truthy(scene_npc.has_method("configure_agent"), "npc exposes Agent binding")
	assertions.truthy(scene_npc.has_method("refresh_dialogue_prompt"), "npc exposes prompt refresh")
	assertions.truthy(scene_npc.has_method("set_dialogue_busy"), "npc exposes busy setter")
	assertions.truthy(scene_npc.has_method("is_dialogue_busy"), "npc exposes busy query")
	var prompt := scene_npc.get_node_or_null("DialoguePrompt")
	assertions.truthy(prompt != null, "npc scene authors dialogue prompt")
	var nameplate := scene_npc.get_node_or_null("Nameplate") as Label3D
	assertions.truthy(nameplate != null, "Agent NPC scene authors an always-visible nameplate")
	var configure_agent_argument_count := -1
	for method_record in scene_npc.get_method_list():
		if str(method_record.name) == "configure_agent":
			configure_agent_argument_count = (method_record.args as Array).size()
			break
	assertions.equal(configure_agent_argument_count, 3, "Agent NPC binding accepts a display name")
	if (
		not scene_npc.has_method("configure_agent")
		or not scene_npc.has_method("refresh_dialogue_prompt")
		or not scene_npc.has_method("set_dialogue_busy")
		or not scene_npc.has_method("is_dialogue_busy")
		or prompt == null
	):
		scene_npc.free()
		player.free()
		return

	var hit_area := scene_npc.get_node_or_null("DialoguePrompt/HitArea") as Area3D
	assertions.truthy(hit_area != null, "dialogue prompt authors one click area")
	scene_npc.global_position = Vector3(4.0, 1.0, -2.0)
	player.global_position = scene_npc.global_position + Vector3(3.0, 20.0, 0.0)
	var configured := (
		bool(scene_npc.call("configure_agent", player, "farmer_ahe", "阿禾"))
		if configure_agent_argument_count == 3
		else bool(scene_npc.call("configure_agent", player, "farmer_ahe"))
	)
	assertions.truthy(configured, "Agent binding succeeds")
	if nameplate != null:
		assertions.equal(nameplate.text, "阿禾", "Agent nameplate shows configured display name")
		assertions.truthy(nameplate.visible, "Agent nameplate is visible inside dialogue range")
	scene_npc.dialogue_started.connect(spy.on_dialogue_started)
	scene_npc.call("refresh_dialogue_prompt")
	assertions.truthy(bool(scene_npc.call("is_player_in_dialogue_range")), "XZ range ignores height")
	assertions.truthy(prompt.visible, "prompt appears at three metres")
	var prompt_icon := scene_npc.get_node_or_null("DialoguePrompt/Icon") as Sprite3D
	assertions.truthy(prompt_icon != null, "dialogue prompt authors a billboard icon")
	if prompt_icon != null:
		assertions.truthy(prompt_icon.modulate.a > 0.0, "clickable prompt is never fully invisible")
		assertions.truthy(prompt_icon.modulate.a < 1.0, "unchanged refresh preserves prompt fade-in")
	if hit_area != null:
		assertions.equal(hit_area.collision_layer, 64, "visible prompt is ray-pickable")
		assertions.truthy(hit_area.input_ray_pickable, "visible prompt accepts ray input")

	player.global_position.x += 0.01
	scene_npc.call("refresh_dialogue_prompt")
	assertions.truthy(not bool(scene_npc.call("is_player_in_dialogue_range")), "range rejects more than three metres")
	assertions.truthy(not prompt.visible, "prompt hides outside range")
	if nameplate != null:
		assertions.truthy(nameplate.visible, "Agent nameplate remains visible outside dialogue range")
	if hit_area != null:
		assertions.equal(hit_area.collision_layer, 0, "hidden prompt cannot intercept rays")
		assertions.truthy(not hit_area.input_ray_pickable, "hidden prompt disables ray input")
	assertions.truthy(not bool(scene_npc.call("start_dialogue")), "out-of-range NPC rejects direct dialogue")
	assertions.equal(spy.dialogue_count, 0, "rejected dialogue emits no signal")

	player.global_position = scene_npc.global_position
	scene_npc.call("refresh_dialogue_prompt")
	scene_npc.call("set_dialogue_busy", true)
	assertions.truthy(bool(scene_npc.call("is_dialogue_busy")), "NPC records dialogue busy state")
	assertions.truthy(not prompt.visible, "busy NPC hides prompt")
	assertions.truthy(not bool(scene_npc.call("start_dialogue")), "busy NPC rejects duplicate dialogue")
	assertions.equal(spy.dialogue_count, 0, "busy rejection emits no signal")

	scene_npc.call("set_dialogue_busy", false)
	assertions.truthy(prompt.visible, "unlock restores prompt while player remains nearby")
	assertions.truthy(bool(scene_npc.call("start_dialogue")), "available NPC starts dialogue")
	assertions.equal(spy.dialogue_count, 1, "accepted dialogue emits once")
	assertions.equal(spy.last_villager_id, "farmer_ahe", "dialogue intent carries Agent ID")
	assertions.truthy(not bool(scene_npc.call("start_dialogue")), "accepted dialogue becomes busy immediately")
	assertions.equal(spy.dialogue_count, 1, "repeat click cannot emit a second request")

	scene_npc.free()
	player.free()
