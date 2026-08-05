extends RefCounted

const TOOL_VISUAL_PATH := "res://scripts/visual/tool_swing_visual.gd"
const FEEDBACK_SCENE_PATH := "res://scenes/ui/gathering_feedback.tscn"
const ORE_MINING_ATLAS_PATH := "res://assets/resources/mining/ore-mining-sheet.png"
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
	assertions.truthy(tool_visual.has_node("Pivot/ToolSprite"), "tool visual authors a sprite under the pivot")
	assertions.truthy(tool_visual.play_tool("axe"), "tool visual plays the hand-painted axe")
	var axe_sprite := tool_visual.get_node("Pivot/ToolSprite") as Sprite3D
	assertions.equal(axe_sprite.position, Vector3.ZERO, "axe texture is anchored directly at its handle pivot")
	assertions.near(axe_sprite.pixel_size, 0.00175, 0.00001, "axe is rendered at half of its previous size")
	var axe_material := axe_sprite.material_override as ShaderMaterial
	assertions.truthy(axe_material != null, "axe uses the same painted-pivot shader approach as the hammer")
	if axe_material != null:
		var handle_uv: Vector2 = axe_material.get_shader_parameter("pivot_uv")
		assertions.truthy(handle_uv.x > 0.65, "axe pivot follows the painted handle end on the right")
		assertions.truthy(handle_uv.y > 0.85, "axe pivot follows the painted handle end at the bottom")
		var reflection_axis_value = axe_material.get_shader_parameter("reflection_axis")
		assertions.truthy(
			reflection_axis_value is Vector2,
			"axe shader exposes a handle-axis reflection for blade orientation"
		)
		if reflection_axis_value is Vector2:
			assertions.truthy(
				(reflection_axis_value as Vector2).length() > 0.9,
				"axe artwork is reflected across its handle axis so the blade faces down"
			)
	assertions.truthy(
		tool_visual.has_method("get_axe_head_screen_offset"),
		"axe exposes its painted head arc for direction verification"
	)
	assertions.equal(tool_visual.get_phase_at(0.05), "prepare", "axe begins with a short preparation")
	assertions.equal(tool_visual.get_phase_at(0.18), "strike", "axe quickly strikes toward the right")
	assertions.equal(tool_visual.get_phase_at(0.28), "impact", "axe briefly holds at impact")
	assertions.equal(tool_visual.get_phase_at(0.60), "recover", "axe recovers within one short cycle")
	assertions.equal(tool_visual.get_phase_at(0.78), "prepare", "axe starts a new swing every 0.72 seconds")
	tool_visual.set_action_progress(0.0)
	var prepare_rotation: float = tool_visual.get_node("Pivot").rotation.z
	var raised_head := Vector2.ZERO
	if tool_visual.has_method("get_axe_head_screen_offset"):
		raised_head = tool_visual.call("get_axe_head_screen_offset")
	tool_visual.set_action_progress(0.10)
	var impact_rotation: float = tool_visual.get_node("Pivot").rotation.z
	assertions.truthy(
		impact_rotation <= deg_to_rad(-108.0),
		"axe reaches its rightward downward impact within the first 0.3 seconds"
	)
	if tool_visual.has_method("get_axe_head_screen_offset"):
		var impact_head: Vector2 = tool_visual.call("get_axe_head_screen_offset")
		assertions.truthy(raised_head.x < impact_head.x, "axe head sweeps from left to right")
		assertions.near(impact_head.x, 0.0, 0.04, "impact places the axe head on the cut horizontally")
		assertions.near(impact_head.y, 0.0, 0.04, "impact places the axe head on the cut vertically")
	tool_visual.set_action_progress(0.26)
	var repeated_prepare_rotation: float = tool_visual.get_node("Pivot").rotation.z
	assertions.truthy(
		repeated_prepare_rotation > impact_rotation,
		"three-second axe action recovers quickly enough to begin another swing"
	)
	assertions.truthy(tool_visual.play_tool("pickaxe"), "tool visual plays the hand-painted pickaxe")
	var pickaxe_sprite := tool_visual.get_node("Pivot/ToolSprite") as Sprite3D
	assertions.equal(pickaxe_sprite.position, Vector3.ZERO, "pickaxe texture is anchored at its handle pivot")
	assertions.near(pickaxe_sprite.pixel_size, 0.00175, 0.00001, "pickaxe matches the axe display scale")
	var pickaxe_material := pickaxe_sprite.material_override as ShaderMaterial
	assertions.truthy(pickaxe_material != null, "pickaxe uses the painted handle-pivot shader")
	if pickaxe_material != null:
		var pickaxe_handle_uv: Vector2 = pickaxe_material.get_shader_parameter("pivot_uv")
		assertions.truthy(pickaxe_handle_uv.x < 0.35, "pickaxe pivot follows the painted handle end on the left")
		assertions.truthy(pickaxe_handle_uv.y > 0.85, "pickaxe pivot follows the painted handle end at the bottom")
	assertions.truthy(
		tool_visual.has_method("get_pickaxe_head_screen_offset"),
		"pickaxe exposes its painted head arc for contact verification"
	)
	tool_visual.set_action_progress(0.0)
	var raised_pickaxe_head := Vector2.ZERO
	if tool_visual.has_method("get_pickaxe_head_screen_offset"):
		raised_pickaxe_head = tool_visual.call("get_pickaxe_head_screen_offset")
	tool_visual.set_action_progress(0.46)
	if tool_visual.has_method("get_pickaxe_head_screen_offset"):
		var impact_pickaxe_head: Vector2 = tool_visual.call("get_pickaxe_head_screen_offset")
		assertions.truthy(raised_pickaxe_head.x < impact_pickaxe_head.x, "pickaxe head sweeps toward the ore")
		assertions.near(impact_pickaxe_head.x, 0.0, 0.04, "pickaxe head lands on the ore horizontally")
		assertions.near(impact_pickaxe_head.y, 0.0, 0.04, "pickaxe head lands on the ore vertically")
	tool_visual.cancel_tool()
	assertions.truthy(tool_visual.visible, "runtime cancel enters recovery before hiding")
	assertions.near(tool_visual.get_cancel_recovery_duration(), 0.14, 0.001, "runtime cancellation uses a short smooth recovery")
	await scene_tree.create_timer(0.30).timeout
	assertions.truthy(not tool_visual.visible, "cancel recovery hides the tool after its tween")
	tool_visual.free()

	assertions.truthy(FileAccess.file_exists(ORE_MINING_ATLAS_PATH), "ore uses a hand-painted four-cell mining atlas")
	var offset_mining_image := Image.create_empty(40, 20, false, Image.FORMAT_RGBA8)
	offset_mining_image.fill(Color.TRANSPARENT)
	for y in range(2, 10):
		for x in range(1, 9):
			offset_mining_image.set_pixel(x, y, Color.WHITE)
	for x in range(7, 9):
		offset_mining_image.set_pixel(x, 10, Color.WHITE)
	var offset_mining_texture := ImageTexture.create_from_image(offset_mining_image)
	assertions.near(
		ResourceNodeScript.mining_ground_anchor(offset_mining_texture, 0).x,
		7.5,
		0.01,
		"ore ground registration samples the painted base despite transparent atlas padding"
	)
	var ore := ResourceNodeScript.new()
	assertions.truthy(ore.configure_resource({
		"resource_id": "visual-copper",
		"resource_type": "copper_ore",
		"position": Vector3.ZERO,
	}), "visual ore fixture configures")
	ore.build_fallback_visual()
	var ore_visual := ore.get_node("Visual") as Node3D
	var ore_authored_scale := ore_visual.scale
	var ore_atlas := load(ORE_MINING_ATLAS_PATH) as Texture2D
	assertions.truthy(ore_atlas != null and ore_atlas.get_width() % 4 == 0, "mining atlas has four equal-width cells")
	var ore_cell_size := Vector2.ZERO
	var ore_registered_anchor := Vector2.ZERO
	if ore_visual is Sprite3D and ore_atlas != null:
		ore_cell_size = Vector2(float(ore_atlas.get_width()) / 4.0, float(ore_atlas.get_height()))
		ore_registered_anchor = _rendered_ground_anchor(
			ore_visual as Sprite3D,
			ore_cell_size,
			_painted_mining_ground_anchor(ore_atlas, 0)
		)
	assertions.truthy(ore_visual is Sprite3D, "ore replaces the geometric sphere with painted sprite art")
	assertions.truthy(ore.get_node_or_null("MiningBlendVisual") is Sprite3D, "ore provides a second sprite for frame crossfade")
	assertions.truthy(ore.has_method("begin_mining"), "ore exposes a mining presentation lifecycle")
	assertions.truthy(ore.has_method("set_mining_progress"), "ore accepts mining action progress")
	assertions.truthy(ore.has_method("cancel_mining"), "ore can restore its persistent stage after cancellation")
	if ore.has_method("begin_mining") and ore.has_method("set_mining_progress"):
		assertions.truthy(ore.call("begin_mining"), "ore begins its three-frame mining presentation")
		ore.call("set_mining_progress", 0.10)
		assertions.equal(ore.call("get_mining_frame"), 0, "early mining progress shows the intact frame")
		ore.call("set_mining_progress", 0.50)
		assertions.equal(ore.call("get_mining_frame"), 1, "middle mining progress shows the cracked frame")
		if ore_visual is Sprite3D and ore_atlas != null:
			var cracked_anchor := _rendered_ground_anchor(
				ore_visual as Sprite3D,
				ore_cell_size,
				_painted_mining_ground_anchor(ore_atlas, 1)
			)
			assertions.near(cracked_anchor.x, ore_registered_anchor.x, 0.002, "cracked ore keeps the horizontal ground anchor")
			assertions.near(cracked_anchor.y, ore_registered_anchor.y, 0.002, "cracked ore keeps the ground baseline")
		ore.call("set_mining_progress", 0.90)
		assertions.equal(ore.call("get_mining_frame"), 2, "late mining progress shows the broken frame")
		if ore_visual is Sprite3D and ore_atlas != null:
			var broken_anchor := _rendered_ground_anchor(
				ore_visual as Sprite3D,
				ore_cell_size,
				_painted_mining_ground_anchor(ore_atlas, 2)
			)
			assertions.near(broken_anchor.x, ore_registered_anchor.x, 0.002, "broken ore keeps the horizontal ground anchor")
			assertions.near(broken_anchor.y, ore_registered_anchor.y, 0.002, "broken ore keeps the ground baseline")
		ore.call("set_mining_progress", 1.0 / 3.0)
		var ore_outgoing := ore.get_node("Visual") as Sprite3D
		var ore_incoming := ore.get_node("MiningBlendVisual") as Sprite3D
		assertions.truthy(ore_outgoing.visible and ore_incoming.visible, "ore crossfades adjacent mining frames")
		assertions.near(ore_outgoing.modulate.a, 0.5, 0.08, "ore outgoing mining frame fades out")
		assertions.near(ore_incoming.modulate.a, 0.5, 0.08, "ore incoming mining frame fades in")
		ore.call("cancel_mining")
		assertions.equal(ore.call("get_mining_frame"), -1, "cancel clears transient mining frame state")
	ore.commit_gather("pickaxe", 1)
	assertions.equal(ore.visual_stage, 1, "damaged ore advances to stage one")
	if ore_visual is Sprite3D:
		assertions.truthy((ore_visual as Sprite3D).texture is AtlasTexture, "damaged ore keeps painted atlas art")
	while ore.remaining_units > 0:
		ore.commit_gather("pickaxe", 1)
	assertions.equal(ore.visual_stage, 3, "depleted ore uses rubble stage")
	assertions.truthy(ore.visible, "depleted ore remains visibly as rubble")
	assertions.equal(ore.get_node("Collision").collision_layer, 0, "rubble no longer blocks movement or clicks")
	assertions.equal(ore.get_node("Visual").scale, ore_authored_scale, "painted rubble keeps authored proportions instead of mesh flattening")
	if ore_visual is Sprite3D and ore_atlas != null:
		var rubble_anchor := _rendered_ground_anchor(
			ore_visual as Sprite3D,
			ore_cell_size,
			_painted_mining_ground_anchor(ore_atlas, 3)
		)
		assertions.near(rubble_anchor.x, ore_registered_anchor.x, 0.002, "rubble keeps the original horizontal ground anchor")
		assertions.near(rubble_anchor.y, ore_registered_anchor.y, 0.002, "rubble keeps the original ground baseline")
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
	assertions.near(tree.get_gather_duration(), 3.0, 0.001, "tree exposes a three-second gather duration")
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
	assertions.truthy(tree.begin_felling(-1), "felling direction fixture begins")
	assertions.truthy(not tree.get_node("StumpVisual").flip_h, "every tree uses the authored right-falling frames")
	tree.set_felling_progress(1.0 / 3.0)
	assertions.truthy(tree.has_node("FellingBlendVisual"), "tree provides a second sprite for frame crossfade")
	if tree.has_node("FellingBlendVisual"):
		var outgoing := tree.get_node("StumpVisual") as Sprite3D
		var incoming := tree.get_node("FellingBlendVisual") as Sprite3D
		assertions.truthy(outgoing.visible and incoming.visible, "both felling frames overlap during crossfade")
		assertions.near(outgoing.modulate.a, 0.5, 0.08, "outgoing frame fades toward transparent")
		assertions.near(incoming.modulate.a, 0.5, 0.08, "incoming frame fades in from transparent")
	tree.cancel_felling()
	tree.remaining_units = 0
	tree.call("_update_visual_stage")
	tree.call("_set_gather_active", false)
	assertions.truthy(tree.get_node("StumpVisual").visible, "depleted tree leaves a visible stump")
	assertions.truthy(not tree.get_node("Sprite3D").visible, "depleted tree hides its standing canopy")
	assertions.equal(tree.get_felling_frame(), 3, "depleted tree uses painted atlas stump cell")
	assertions.truthy(tree.get_node("StumpVisual") is Sprite3D, "stump is painted art instead of a cylinder mesh")
	assertions.equal(tree.get_node("TrunkBody").collision_layer, 0, "stump releases the tree obstacle")
	tree.free()

	var registered_tree_texture := load("res://assets/vegetation/tree-pine-small.png") as Texture2D
	var registered_felling_atlas := load(
		"res://assets/vegetation/felling/pine-small-felling-sheet.png"
	) as Texture2D
	var registered_tree := TreeInstanceScript.new()
	registered_tree.configure({
		"id": "registered-visual-tree",
		"variant": "pine-small",
		"x": 0.0,
		"z": 0.0,
		"width": 1.05,
		"height": 1.45,
		"clearance": 1.0,
		"gatherable": true,
	}, registered_tree_texture, 0.0, registered_felling_atlas)
	var registered_standing := registered_tree.get_node("Sprite3D") as Sprite3D
	var standing_anchor := _rendered_ground_anchor(
		registered_standing,
		registered_tree_texture.get_size(),
		_painted_ground_anchor(registered_tree_texture)
	)
	var standing_bounds := registered_tree_texture.get_image().get_used_rect()
	var standing_painted_size := Vector2(
		float(standing_bounds.size.x) * registered_standing.pixel_size * registered_standing.scale.x,
		float(standing_bounds.size.y) * registered_standing.pixel_size * registered_standing.scale.y
	)
	assertions.truthy(registered_tree.begin_felling(1), "registered tree begins felling")
	for frame_case in [[0.10, 0], [0.50, 1], [0.85, 2]]:
		registered_tree.set_felling_progress(float(frame_case[0]))
		var frame := int(frame_case[1])
		var registered_frame_sprite := registered_tree.get_node("StumpVisual") as Sprite3D
		var cell_size := Vector2(
			float(registered_felling_atlas.get_width()) / 4.0,
			float(registered_felling_atlas.get_height())
		)
		var frame_anchor := _painted_ground_anchor(registered_felling_atlas, frame)
		var rendered_anchor := _rendered_ground_anchor(
			registered_frame_sprite, cell_size, frame_anchor
		)
		assertions.near(
			rendered_anchor.x,
			standing_anchor.x,
			0.002,
			"felling frame %d keeps the original horizontal root anchor" % frame
		)
		assertions.near(
			rendered_anchor.y,
			standing_anchor.y,
			0.002,
			"felling frame %d keeps the original ground baseline" % frame
		)
		if frame == 0:
			var frame_bounds := TreeInstanceScript.felling_frame_used_rect(
				registered_felling_atlas, frame
			)
			var frame_painted_size := Vector2(
				float(frame_bounds.size.x) * registered_frame_sprite.pixel_size * registered_frame_sprite.scale.x,
				float(frame_bounds.size.y) * registered_frame_sprite.pixel_size * registered_frame_sprite.scale.y
			)
			assertions.near(
				frame_painted_size.x,
				standing_painted_size.x,
				0.002,
				"first felling frame preserves the standing tree painted width"
			)
			assertions.near(
				frame_painted_size.y,
				standing_painted_size.y,
				0.002,
				"first felling frame preserves the standing tree painted height"
			)
	registered_tree.remaining_units = 0
	registered_tree.call("_update_visual_stage")
	var registered_stump := registered_tree.get_node("StumpVisual") as Sprite3D
	var stump_anchor := _rendered_ground_anchor(
		registered_stump,
		Vector2(
			float(registered_felling_atlas.get_width()) / 4.0,
			float(registered_felling_atlas.get_height())
		),
		_painted_ground_anchor(registered_felling_atlas, 3)
	)
	assertions.near(stump_anchor.x, standing_anchor.x, 0.002, "painted stump keeps the original horizontal root anchor")
	assertions.near(stump_anchor.y, standing_anchor.y, 0.002, "painted stump keeps the original ground baseline")
	registered_tree.free()

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
	assertions.near(anchor.y, 1.12, 0.001, "axe contact is lowered to the felling-frame notch")
	assertions.near(anchor.x, 3.88, 0.001, "axe contact sits just left of the trunk center")
	var opposite_actor_anchor: Vector3 = feedback.tree_axe_anchor(
		Vector3(4.0, 1.0, 2.0), Vector3(6.0, 1.0, 2.0)
	)
	assertions.near(opposite_actor_anchor.x, 3.88, 0.001, "axe contact remains left even when the actor approaches from the right")
	assertions.truthy(feedback.has_method("ore_pickaxe_anchor"), "feedback exposes a stable ore contact anchor")
	if feedback.has_method("ore_pickaxe_anchor"):
		var ore_anchor: Vector3 = feedback.call(
			"ore_pickaxe_anchor", Vector3(4.0, 1.0, 2.0), Vector3(2.0, 1.0, 2.0)
		)
		assertions.near(ore_anchor.x, 3.88, 0.001, "pickaxe contact sits on the ore's left shoulder")
		assertions.near(ore_anchor.y, 1.38, 0.001, "pickaxe contact sits above the ore base")
		assertions.near(ore_anchor.z, 2.06, 0.001, "pickaxe contact follows the locked camera's screen-right axis")
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


static func _painted_ground_anchor(texture: Texture2D, frame: int = -1) -> Vector2:
	var image := texture.get_image()
	var cell_width := image.get_width() if frame < 0 else image.get_width() / 4
	var source_x := 0 if frame < 0 else cell_width * frame
	var region := image.get_region(Rect2i(source_x, 0, cell_width, image.get_height()))
	var used_rect := region.get_used_rect()
	var band_start := maxi(used_rect.position.y, floori(float(region.get_height()) * 0.90))
	var weighted_x := 0.0
	var total_alpha := 0.0
	for y in range(band_start, used_rect.end.y):
		for x in range(used_rect.position.x, used_rect.end.x):
			var alpha := region.get_pixel(x, y).a
			if alpha <= 0.10:
				continue
			weighted_x += float(x) * alpha
			total_alpha += alpha
	return Vector2(
		weighted_x / total_alpha if total_alpha > 0.0 else float(used_rect.get_center().x),
		float(used_rect.end.y)
	)


static func _painted_mining_ground_anchor(texture: Texture2D, frame: int) -> Vector2:
	var image := texture.get_image()
	var cell_width := image.get_width() / 4
	var region := image.get_region(Rect2i(cell_width * frame, 0, cell_width, image.get_height()))
	var used_rect := region.get_used_rect()
	var band_start := used_rect.position.y + floori(float(used_rect.size.y) * 0.90)
	var weighted_x := 0.0
	var total_alpha := 0.0
	for y in range(band_start, used_rect.end.y):
		for x in range(used_rect.position.x, used_rect.end.x):
			var alpha := region.get_pixel(x, y).a
			if alpha <= 0.10:
				continue
			weighted_x += float(x) * alpha
			total_alpha += alpha
	return Vector2(
		weighted_x / total_alpha if total_alpha > 0.0 else float(used_rect.get_center().x),
		float(used_rect.end.y)
	)


static func _rendered_ground_anchor(
	sprite_node: Sprite3D,
	texture_size: Vector2,
	anchor_pixel: Vector2
) -> Vector2:
	return Vector2(
		sprite_node.position.x
			+ (anchor_pixel.x - texture_size.x * 0.5)
			* sprite_node.pixel_size
			* sprite_node.scale.x,
		sprite_node.position.y
			+ (texture_size.y * 0.5 - anchor_pixel.y)
			* sprite_node.pixel_size
			* sprite_node.scale.y
	)
