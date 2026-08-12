extends RefCounted

const PlayerVisualScript = preload("res://scripts/visual/player_visual.gd")
const PlayerScene = preload("res://scenes/actors/player.tscn")
const ATLAS_PATH := "res://assets/characters/player/player_farmer_atlas.png"
const DIRECTIONS := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]


func run(assertions: TestAssert) -> void:
	_assert_direction_mapping(assertions)
	_assert_animation_contract(assertions)
	_assert_scene_contract(assertions)


func _assert_direction_mapping(assertions: TestAssert) -> void:
	var samples := {
		Vector2(0.0, -1.0): "n",
		Vector2(1.0, -1.0): "ne",
		Vector2(1.0, 0.0): "e",
		Vector2(1.0, 1.0): "se",
		Vector2(0.0, 1.0): "s",
		Vector2(-1.0, 1.0): "sw",
		Vector2(-1.0, 0.0): "w",
		Vector2(-1.0, -1.0): "nw",
	}
	for velocity in samples:
		assertions.equal(
			PlayerVisualScript.direction_from_velocity(velocity, "s"),
			samples[velocity],
			"player visual maps %s to %s" % [velocity, samples[velocity]]
		)
	assertions.equal(
		PlayerVisualScript.direction_from_velocity(Vector2.ZERO, "nw"),
		"nw",
		"zero velocity retains the previous direction"
	)
	assertions.equal(
		PlayerVisualScript.direction_from_velocity(Vector2.ZERO, "invalid"),
		"s",
		"invalid previous direction falls back south"
	)
	assertions.equal(PlayerVisualScript.idle_animation_name("ne"), "idle_ne", "idle animation names are stable")
	assertions.equal(PlayerVisualScript.walk_animation_name("sw"), "walk_sw", "walk animation names are stable")
	assertions.near(PlayerVisualScript.IDLE_FPS, 2.0, 0.001, "idle animation uses two fps")
	assertions.near(PlayerVisualScript.WALK_FPS, 8.0, 0.001, "walk animation uses eight fps")
	assertions.near(PlayerVisualScript.RUN_FPS, 12.0, 0.001, "run animation uses twelve fps")


func _assert_animation_contract(assertions: TestAssert) -> void:
	var atlas := load(ATLAS_PATH) as Texture2D
	assertions.truthy(atlas != null, "painted player atlas imports as Texture2D")
	if atlas == null:
		return
	assertions.equal(atlas.get_width() % 8, 0, "player atlas width divides into eight columns")
	assertions.equal(atlas.get_height() % 8, 0, "player atlas height divides into eight rows")
	var image := atlas.get_image()
	assertions.truthy(image != null and not image.is_empty(), "player atlas exposes imported pixels")
	if image != null and not image.is_empty():
		assertions.truthy(image.get_pixel(0, 0).a < 0.05, "player atlas has transparent corners")
	var visual := PlayerVisualScript.new()
	assertions.truthy(visual.configure(atlas), "valid player atlas configures")
	for direction in DIRECTIONS:
		var idle_name := PlayerVisualScript.idle_animation_name(direction)
		var walk_name := PlayerVisualScript.walk_animation_name(direction)
		assertions.truthy(visual.sprite_frames.has_animation(idle_name), "%s idle animation exists" % direction)
		assertions.truthy(visual.sprite_frames.has_animation(walk_name), "%s walk animation exists" % direction)
		assertions.equal(visual.sprite_frames.get_frame_count(idle_name), 2, "%s idle has two frames" % direction)
		assertions.equal(visual.sprite_frames.get_frame_count(walk_name), 6, "%s walk has six frames" % direction)
		for animation_name in [idle_name, walk_name]:
			for frame_index in visual.sprite_frames.get_frame_count(animation_name):
				var frame_texture := visual.sprite_frames.get_frame_texture(animation_name, frame_index) as AtlasTexture
				assertions.truthy(
					frame_texture != null and frame_texture.filter_clip,
					"%s frame %d clips texture filtering to its atlas cell" % [animation_name, frame_index]
				)
	assertions.equal(visual.get_last_direction(), "s", "player visual defaults to south")
	visual.sync_motion(Vector2(1.0, 0.0), false, true)
	assertions.equal(visual.animation, &"walk_e", "walking east selects east animation")
	assertions.near(visual.speed_scale, 1.0, 0.001, "walking uses base animation speed")
	visual.sync_motion(Vector2(1.0, 0.0), true, true)
	assertions.near(visual.speed_scale, 1.5, 0.001, "sprinting reuses walk frames at twelve fps")
	visual.sync_motion(Vector2.ZERO, false, true)
	assertions.equal(visual.animation, &"idle_e", "stopping retains the last facing direction")
	visual.sync_motion(Vector2(0.0, -1.0), false, false)
	assertions.equal(visual.animation, &"walk_n", "jumping preserves the current directional walk pose")
	assertions.truthy(not visual.is_playing(), "jumping pauses the directional animation")
	visual.free()


func _assert_scene_contract(assertions: TestAssert) -> void:
	var player := PlayerScene.instantiate() as CharacterBody3D
	assertions.truthy(player != null, "player scene instantiates")
	if player == null:
		return
	assertions.truthy(player.get_node_or_null("PlayerVisual") is AnimatedSprite3D, "player scene uses AnimatedSprite3D art")
	assertions.equal(player.get_node_or_null("Mesh"), null, "player scene removes the blue capsule mesh")
	for child in player.get_children():
		assertions.truthy(not (child is MeshInstance3D), "player has no direct geometric visual fallback")
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	assertions.truthy(capsule != null, "player retains its capsule collision")
	if capsule != null:
		assertions.near(capsule.radius, 0.35, 0.001, "player collision radius is unchanged")
		assertions.near(capsule.height, 1.3, 0.001, "player collision height is unchanged")
	assertions.equal(player.collision_layer, 2, "player collision layer is unchanged")
	assertions.equal(player.collision_mask, 21, "player collision mask is unchanged")
	assertions.truthy(player.get_node_or_null("ActionController") != null, "player action controller path is preserved")
	assertions.truthy(player.get_node_or_null("ToolSwingVisual") != null, "player tool visual path is preserved")
	player.free()
