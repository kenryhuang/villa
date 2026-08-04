extends RefCounted

const TOOL_VISUAL_PATH := "res://scripts/visual/tool_swing_visual.gd"
const FEEDBACK_SCENE_PATH := "res://scenes/ui/gathering_feedback.tscn"
const ResourceNodeScript = preload("res://scripts/world/resource_node.gd")
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")


func run(assertions: TestAssert, scene_tree: SceneTree) -> void:
	assertions.truthy(FileAccess.file_exists(TOOL_VISUAL_PATH), "gathering has a hand-painted tool swing visual")
	assertions.truthy(FileAccess.file_exists(FEEDBACK_SCENE_PATH), "gathering has a feedback scene")
	if not FileAccess.file_exists(TOOL_VISUAL_PATH) or not FileAccess.file_exists(FEEDBACK_SCENE_PATH):
		return

	var tool_script := load(TOOL_VISUAL_PATH) as Script
	var tool_visual = tool_script.new()
	scene_tree.root.add_child(tool_visual)
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
	assertions.truthy(tool_visual.visible, "runtime cancel enters recovery before hiding")
	assertions.near(tool_visual.get_cancel_recovery_duration(), 0.14, 0.001, "runtime cancellation uses a short smooth recovery")
	await scene_tree.create_timer(0.30).timeout
	assertions.truthy(not tool_visual.visible, "cancel recovery hides the tool after its tween")
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
	var atlas_image := Image.create_empty(64, 24, false, Image.FORMAT_RGBA8)
	var atlas_texture := ImageTexture.create_from_image(atlas_image)
	var tree := TreeInstanceScript.new()
	tree.configure({
		"id": "visual-tree",
		"variant": "pine-small",
		"x": 0.0,
		"z": 0.0,
		"width": 2.0,
		"height": 3.0,
		"clearance": 1.0,
		"gatherable": true,
	}, texture, 0.0, atlas_texture)
	assertions.near(tree.get_gather_duration(), 2.0, 0.001, "tree exposes a two-second gather duration")
	var standing_sprite := tree.get_node("Sprite3D") as Sprite3D
	var standing_position := standing_sprite.position
	var cancellation_cases := [[0.10, 0], [0.50, 1], [0.85, 2]]
	for cancellation_case in cancellation_cases:
		assertions.truthy(tree.begin_felling(1), "eligible tree begins its felling presentation")
		tree.set_felling_progress(float(cancellation_case[0]))
		assertions.equal(tree.get_felling_frame(), int(cancellation_case[1]), "progress selects expected felling frame")
		standing_sprite.position += Vector3(0.1, 0.05, 0.0)
		tree.cancel_felling()
		assertions.equal(tree.get_felling_frame(), -1, "cancel restores standing art from every frame")
		assertions.equal(tree.remaining_units, 5, "visual cancellation never mutates tree units")
		assertions.truthy(standing_sprite.visible, "cancel makes original tree visible")
		assertions.equal(standing_sprite.position, standing_position, "cancel restores the standing tree position")
	tree.remaining_units = 0
	tree.call("_update_visual_stage")
	tree.call("_set_gather_active", false)
	assertions.truthy(tree.get_node("StumpVisual").visible, "depleted tree leaves a visible stump")
	assertions.truthy(not tree.get_node("Sprite3D").visible, "depleted tree hides its standing canopy")
	assertions.equal(tree.get_felling_frame(), 3, "depleted tree uses painted atlas stump cell")
	assertions.truthy(tree.get_node("StumpVisual") is Sprite3D, "stump is painted art instead of a cylinder mesh")
	assertions.equal(tree.get_node("TrunkBody").collision_layer, 0, "stump releases the tree obstacle")
	tree.free()

	var feedback_scene := load(FEEDBACK_SCENE_PATH) as PackedScene
	var feedback = feedback_scene.instantiate()
	scene_tree.root.add_child(feedback)
	for node_path in [
		"TargetRing",
		"TreeHoverRing",
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
	assertions.equal(feedback.error_message("tree_not_choppable"), "此树不可砍伐", "red tree click has readable text")
	var progress_ring := feedback.get_node("Canvas/ProgressRing")
	assertions.near(progress_ring.anchor_left, 0.0, 0.001, "progress ring uses projected target coordinates")
	var anchor: Vector3 = feedback.tree_axe_anchor(Vector3(4.0, 1.0, 2.0), Vector3(2.0, 1.0, 2.0))
	assertions.near(anchor.y, 1.20, 0.001, "axe pivot is 0.2m above ground")
	assertions.near(anchor.x, 3.55, 0.001, "axe pivot is 0.45m actor-side")
	var safe_progress_center: Vector2 = feedback.progress_center_with_label_clearance(
		Vector2(500.0, 430.0), Vector2(500.0, 450.0)
	)
	assertions.truthy(
		safe_progress_center.y <= 378.0,
		"progress ring keeps a readable screen-space gap above remaining text"
	)
	var status_label := feedback.get_node("Canvas/StatusLabel") as Control
	assertions.near(status_label.anchor_left, 0.5, 0.001, "error feedback is viewport-centered")
	progress_ring.set_progress(0.5)
	assertions.near(progress_ring.progress, 0.5, 0.001, "progress ring accepts a half-circle sweep")
	var impact_target := Node3D.new()
	scene_tree.root.add_child(impact_target)
	feedback.call("_play_impact_feedback", impact_target)
	assertions.truthy(impact_target.get_node_or_null("GatherImpact") != null, "tool impact creates wood-chip or stone-chip feedback")
	await scene_tree.create_timer(0.55).timeout
	assertions.truthy(impact_target.get_node_or_null("GatherImpact") == null, "one-shot impact particles clean themselves up")
	impact_target.free()
	feedback.free()
