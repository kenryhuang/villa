extends RefCounted

const TOOL_VISUAL_PATH := "res://scripts/visual/tool_swing_visual.gd"
const FEEDBACK_SCENE_PATH := "res://scenes/ui/gathering_feedback.tscn"
const ResourceNodeScript = preload("res://scripts/world/resource_node.gd")
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")


func run(assertions: TestAssert) -> void:
	assertions.truthy(FileAccess.file_exists(TOOL_VISUAL_PATH), "gathering has a hand-painted tool swing visual")
	assertions.truthy(FileAccess.file_exists(FEEDBACK_SCENE_PATH), "gathering has a feedback scene")
	if not FileAccess.file_exists(TOOL_VISUAL_PATH) or not FileAccess.file_exists(FEEDBACK_SCENE_PATH):
		return

	var tool_script := load(TOOL_VISUAL_PATH) as Script
	var tool_visual = tool_script.new()
	assertions.truthy(tool_visual.has_node("Pivot"), "tool visual authors a handle-end pivot")
	assertions.truthy(tool_visual.has_node("Pivot/ToolSprite"), "tool sprite is offset from the pivot")
	assertions.truthy(tool_visual.play_tool("axe"), "tool visual plays the hand-painted axe")
	assertions.equal(tool_visual.get_phase_at(0.10), "prepare", "first 0.25 seconds prepare the swing")
	assertions.equal(tool_visual.get_phase_at(0.40), "strike", "next 0.30 seconds strike downward")
	assertions.equal(tool_visual.get_phase_at(0.65), "impact", "impact pauses for 0.15 seconds")
	assertions.equal(tool_visual.get_phase_at(1.00), "recover", "last 0.50 seconds recover")
	tool_visual.set_action_progress(0.0)
	var prepare_rotation: float = tool_visual.get_node("Pivot").rotation.z
	tool_visual.set_action_progress(0.46)
	var impact_rotation: float = tool_visual.get_node("Pivot").rotation.z
	assertions.truthy(impact_rotation < prepare_rotation, "tool head rotates downward around the handle end")
	tool_visual.cancel_tool()
	assertions.truthy(not tool_visual.visible, "cancel hides the detached tool visual")
	tool_visual.free()

	var ore := ResourceNodeScript.new()
	assertions.truthy(ore.configure_resource({
		"resource_id": "visual-copper",
		"resource_type": "copper_ore",
		"position": Vector3.ZERO,
	}), "visual ore fixture configures")
	ore.build_fallback_visual()
	assertions.truthy(ore.get_node("CrackMark") != null, "ore visual authors a crack overlay")
	ore.commit_gather("pickaxe", 1)
	assertions.equal(ore.visual_stage, 1, "damaged ore advances to stage one")
	assertions.truthy(ore.get_node("CrackMark").visible, "damaged ore shows cracks")
	while ore.remaining_units > 0:
		ore.commit_gather("pickaxe", 1)
	assertions.equal(ore.visual_stage, 3, "depleted ore uses rubble stage")
	assertions.truthy(ore.visible, "depleted ore remains visibly as rubble")
	assertions.equal(ore.get_node("Collision").collision_layer, 0, "rubble no longer blocks movement or clicks")
	assertions.truthy(ore.get_node("Visual").scale.y < ore.get_node("Visual").scale.x, "depleted ore is flattened into rubble")
	ore.free()

	var image := Image.create_empty(16, 24, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var tree := TreeInstanceScript.new()
	tree.configure({
		"id": "visual-tree",
		"x": 0.0,
		"z": 0.0,
		"width": 2.0,
		"height": 3.0,
		"clearance": 1.0,
		"gatherable": true,
	}, texture, 0.0)
	while tree.remaining_units > 0:
		tree.commit_gather("axe", 1)
	assertions.truthy(tree.get_node("StumpVisual").visible, "depleted tree leaves a visible stump")
	assertions.truthy(not tree.get_node("Sprite3D").visible, "depleted tree hides its standing canopy")
	assertions.equal(tree.get_node("TrunkBody").collision_layer, 0, "stump releases the tree obstacle")
	tree.free()

	var feedback_scene := load(FEEDBACK_SCENE_PATH) as PackedScene
	var feedback = feedback_scene.instantiate()
	for node_path in [
		"TargetRing",
		"PathPreview",
		"Canvas/ProgressRing",
		"Canvas/AutoEquipTip",
		"Canvas/StatusLabel",
		"RemainingLabel",
		"ResultLabel",
	]:
		assertions.truthy(feedback.has_node(node_path), "feedback scene contains %s" % node_path)
	assertions.equal(feedback.error_message("inventory_full"), "背包已满", "inventory error has readable text")
	assertions.equal(feedback.error_message("unreachable"), "无法到达", "path error has readable text")
	var progress_ring := feedback.get_node("Canvas/ProgressRing")
	progress_ring.set_progress(0.5)
	assertions.near(progress_ring.progress, 0.5, 0.001, "progress ring accepts a half-circle sweep")
	feedback.free()
