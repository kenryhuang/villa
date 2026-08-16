extends RefCounted

const PlayerVisualScript = preload("res://scripts/visual/player_visual.gd")
const PlayerScene = preload("res://scenes/actors/player.tscn")
const ATLAS_PATH := "res://assets/characters/player/player_farmer_atlas.png"
const SIDE_WALK_PATH := "res://assets/characters/player/player_farmer_side_walk.png"
const SIDE_WALK_FRAME_COUNT := 12
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
	assertions.near(PlayerVisualScript.WALK_FPS, 6.0, 0.001, "walk animation uses six fps")
	assertions.near(PlayerVisualScript.SIDE_WALK_FPS, 12.0, 0.001, "twelve-pose side walk completes in one second")
	assertions.near(PlayerVisualScript.RUN_FPS, 9.0, 0.001, "run animation uses nine fps")
	assertions.near(PlayerVisualScript.PIXEL_SIZE, 0.0068, 0.0001, "player art is scaled below building proportions")
	var just_inside_south := Vector2(sin(deg_to_rad(22.4)), cos(deg_to_rad(22.4)))
	var just_inside_southeast := Vector2(sin(deg_to_rad(22.6)), cos(deg_to_rad(22.6)))
	assertions.equal(
		PlayerVisualScript.direction_from_velocity(just_inside_south, "n"),
		"s",
		"direction quantization retains south immediately before its sector edge"
	)
	assertions.equal(
		PlayerVisualScript.direction_from_velocity(just_inside_southeast, "n"),
		"se",
		"direction quantization enters southeast immediately after its sector edge"
	)
	var camera_forward := Vector3(0.7071068, 0.0, -0.7071068)
	var camera_right := Vector3(0.7071068, 0.0, 0.7071068)
	assertions.equal(
		PlayerVisualScript.direction_from_velocity(
			PlayerVisualScript.facing_velocity_from_world(camera_forward, camera_forward, camera_right)
		),
		"n",
		"camera-forward movement selects the screen-up animation"
	)
	assertions.equal(
		PlayerVisualScript.direction_from_velocity(
			PlayerVisualScript.facing_velocity_from_world(camera_right, camera_forward, camera_right)
		),
		"e",
		"camera-right movement selects the screen-right animation"
	)


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
		_assert_frame_art_contract(image, assertions)
	_assert_side_walk_art_contract(assertions)
	var visual := PlayerVisualScript.new()
	var configured := visual.configure(atlas)
	assertions.truthy(configured, "valid player atlas configures")
	if not configured:
		visual.free()
		return
	for direction in DIRECTIONS:
		var idle_name := PlayerVisualScript.idle_animation_name(direction)
		var walk_name := PlayerVisualScript.walk_animation_name(direction)
		assertions.truthy(visual.sprite_frames.has_animation(idle_name), "%s idle animation exists" % direction)
		assertions.truthy(visual.sprite_frames.has_animation(walk_name), "%s walk animation exists" % direction)
		assertions.equal(visual.sprite_frames.get_frame_count(idle_name), 2, "%s idle has two frames" % direction)
		var expected_walk_frames := SIDE_WALK_FRAME_COUNT if direction in ["e", "w"] else 6
		assertions.equal(
			visual.sprite_frames.get_frame_count(walk_name),
			expected_walk_frames,
			"%s walk has enough frames for its viewing angle" % direction
		)
		assertions.near(
			visual.sprite_frames.get_animation_speed(walk_name),
			12.0 if direction in ["e", "w"] else 6.0,
			0.001,
			"%s walk preserves a one-second loop" % direction
		)
		_assert_walk_leg_alternation(visual.sprite_frames, walk_name, direction, assertions)
		if direction in ["e", "w"]:
			_assert_side_walk_temporal_continuity(visual.sprite_frames, walk_name, direction, assertions)
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
	assertions.near(
		visual.speed_scale,
		1.5,
		0.001,
		"side sprinting plays twelve poses at eighteen fps"
	)
	visual.sync_motion(Vector2.ZERO, false, true)
	assertions.equal(visual.animation, &"idle_e", "stopping retains the last facing direction")
	visual.sync_motion(Vector2(0.0, -1.0), false, false)
	assertions.equal(visual.animation, &"walk_n", "jumping preserves the current directional walk pose")
	assertions.truthy(not visual.is_playing(), "jumping pauses the directional animation")
	visual.sync_motion(Vector2(0.0, -1.0), false, true)
	assertions.truthy(visual.is_playing(), "landing resumes the current directional walk animation")
	visual.free()


func _assert_frame_art_contract(image: Image, assertions: TestAssert) -> void:
	var cell_size := Vector2i(image.get_width() / 8, image.get_height() / 8)
	var baselines: Array[int] = []
	for row in 8:
		for column in 8:
			var bounds := _frame_used_rect(image, cell_size, row, column)
			var frame_label := "player atlas frame %d,%d" % [row, column]
			assertions.truthy(bounds.size.x > 0 and bounds.size.y > 0, "%s contains painted pixels" % frame_label)
			if bounds.size.x <= 0 or bounds.size.y <= 0:
				continue
			assertions.truthy(bounds.position.x >= 6, "%s keeps a left gutter" % frame_label)
			assertions.truthy(bounds.position.y >= 6, "%s keeps a top gutter" % frame_label)
			assertions.truthy(bounds.end.x <= cell_size.x - 6, "%s keeps a right gutter" % frame_label)
			assertions.truthy(bounds.end.y <= cell_size.y - 6, "%s keeps a bottom gutter" % frame_label)
			assertions.equal(
				_count_visible_components(image, cell_size, row, column),
				1,
				"%s contains one connected painted character without fragments" % frame_label
			)
			baselines.append(bounds.end.y)
	if not baselines.is_empty():
		var minimum_baseline: int = baselines.min()
		var maximum_baseline: int = baselines.max()
		assertions.truthy(
			maximum_baseline - minimum_baseline <= 3,
			"player atlas keeps every frame on a stable foot baseline"
		)


func _assert_side_walk_art_contract(assertions: TestAssert) -> void:
	var texture := load(SIDE_WALK_PATH) as Texture2D
	assertions.truthy(texture != null, "twelve-frame side-walk atlas imports")
	if texture == null:
		return
	var image := texture.get_image()
	assertions.equal(image.get_size(), Vector2i(2304, 384), "side walk is a 12x2 atlas")
	var cell_size := Vector2i(192, 192)
	for row in 2:
		for column in SIDE_WALK_FRAME_COUNT:
			var frame := image.get_region(Rect2i(Vector2i(column, row) * cell_size, cell_size))
			var bounds := _frame_used_rect(frame, cell_size, 0, 0)
			assertions.truthy(
				bounds.size.x > 0 and bounds.size.y > 0,
				"side pose %d/%d is painted" % [row, column]
			)
			assertions.truthy(
				bounds.end.y in range(182, 187),
				"side pose %d/%d keeps the planted baseline" % [row, column]
			)
			var translucent_pixels := 0
			for y in cell_size.y:
				for x in cell_size.x:
					var alpha := frame.get_pixel(x, y).a
					if alpha > 0.08 and alpha < 0.85:
						translucent_pixels += 1
			assertions.truthy(
				translucent_pixels <= 1200,
				"side pose %d/%d limits translucent edge pixels (%d)"
				% [row, column, translucent_pixels]
			)
	for column in SIDE_WALK_FRAME_COUNT:
		var east := image.get_region(Rect2i(Vector2i(column * cell_size.x, 0), cell_size))
		var west := image.get_region(
			Rect2i(Vector2i(column * cell_size.x, cell_size.y), cell_size)
		)
		east.flip_x()
		assertions.truthy(_images_equal(east, west), "west pose %d exactly mirrors east" % column)


func _images_equal(first: Image, second: Image) -> bool:
	if first.get_size() != second.get_size():
		return false
	for y in first.get_height():
		for x in first.get_width():
			var first_color := first.get_pixel(x, y)
			var second_color := second.get_pixel(x, y)
			if absf(first_color.a - second_color.a) > 0.01:
				return false
			if first_color.a > 0.05 and Vector3(first_color.r, first_color.g, first_color.b).distance_squared_to(
				Vector3(second_color.r, second_color.g, second_color.b)
			) > 0.0005:
				return false
	return true


func _frame_used_rect(image: Image, cell_size: Vector2i, row: int, column: int) -> Rect2i:
	var origin := Vector2i(column * cell_size.x, row * cell_size.y)
	var frame_image := image.get_region(Rect2i(origin, cell_size))
	return frame_image.get_used_rect()


func _count_visible_components(
	image: Image,
	cell_size: Vector2i,
	row: int,
	column: int
) -> int:
	var origin := Vector2i(column * cell_size.x, row * cell_size.y)
	var frame_image := image.get_region(Rect2i(origin, cell_size))
	frame_image.resize(48, 48, Image.INTERPOLATE_NEAREST)
	var visited := PackedByteArray()
	visited.resize(48 * 48)
	var component_count := 0
	for y in 48:
		for x in 48:
			var start_index := y * 48 + x
			if visited[start_index] == 1 or frame_image.get_pixel(x, y).a <= 0.10:
				continue
			component_count += 1
			var queue := PackedInt32Array([start_index])
			visited[start_index] = 1
			var cursor := 0
			while cursor < queue.size():
				var current_index := queue[cursor]
				cursor += 1
				var current := Vector2i(current_index % 48, current_index / 48)
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = current + offset
					if next.x < 0 or next.y < 0 or next.x >= 48 or next.y >= 48:
						continue
					var next_index: int = next.y * 48 + next.x
					if visited[next_index] == 1 or frame_image.get_pixelv(next).a <= 0.10:
						continue
					visited[next_index] = 1
					queue.append(next_index)
	return component_count


func _assert_walk_leg_alternation(
	frames: SpriteFrames,
	animation_name: String,
	direction: String,
	assertions: TestAssert
) -> void:
	var silhouettes: Array[Image] = []
	var frame_count := frames.get_frame_count(animation_name)
	for frame_index in frame_count:
		var frame_texture := frames.get_frame_texture(animation_name, frame_index)
		var frame_image := _frame_image(frame_texture)
		frame_image.resize(48, 48, Image.INTERPOLATE_LANCZOS)
		silhouettes.append(frame_image)
	var half_cycle := frame_count / 2
	var first_half_difference := _lower_body_silhouette_difference(silhouettes[0], silhouettes[half_cycle])
	var left_stride_difference := _lower_body_silhouette_difference(silhouettes[0], silhouettes[half_cycle - 1])
	var right_stride_difference := _lower_body_silhouette_difference(
		silhouettes[half_cycle], silhouettes[frame_count - 1]
	)
	assertions.truthy(
		first_half_difference >= 20,
		"%s walk alternates to a visibly different opposite-leg stride" % direction
	)
	assertions.truthy(
		left_stride_difference >= 15 and right_stride_difference >= 15,
		"%s walk contains weight-transfer poses between leg contacts (%d/%d)"
		% [direction, left_stride_difference, right_stride_difference]
	)


func _lower_body_silhouette_difference(first: Image, second: Image) -> int:
	var difference := 0
	for y in range(27, 47):
		for x in range(8, 40):
			var first_color := first.get_pixel(x, y)
			var second_color := second.get_pixel(x, y)
			var first_opaque := first_color.a > 0.10
			var second_opaque := second_color.a > 0.10
			if first_opaque != second_opaque:
				difference += 1
	return difference


func _boot_silhouette_difference(first: Image, second: Image) -> int:
	var difference := 0
	for y in range(37, 48):
		for x in range(5, 43):
			var first_opaque := first.get_pixel(x, y).a > 0.10
			var second_opaque := second.get_pixel(x, y).a > 0.10
			if first_opaque != second_opaque:
				difference += 1
	return difference


func _assert_side_walk_temporal_continuity(
	frames: SpriteFrames,
	animation_name: String,
	direction: String,
	assertions: TestAssert
) -> void:
	var silhouettes: Array[Image] = []
	var frame_count := frames.get_frame_count(animation_name)
	if frame_count != SIDE_WALK_FRAME_COUNT:
		return
	for frame_index in frame_count:
		var frame_texture := frames.get_frame_texture(animation_name, frame_index)
		var frame_image := _frame_image(frame_texture)
		frame_image.resize(48, 48, Image.INTERPOLATE_LANCZOS)
		silhouettes.append(frame_image)
	var differences: Array[int] = []
	for frame_index in frame_count:
		differences.append(
			_lower_body_silhouette_difference(
				silhouettes[frame_index], silhouettes[(frame_index + 1) % frame_count]
			)
		)
	assertions.truthy(
		differences.min() >= 12,
		"%s walk has no duplicated adjacent pose: %s" % [direction, differences]
	)
	for frame_index in differences.size():
		var maximum_difference := 160 if frame_index == 8 else 115
		assertions.truthy(
			differences[frame_index] <= maximum_difference,
			"%s walk transition %d distributes motion within its phase (%d <= %d)"
			% [direction, frame_index, differences[frame_index], maximum_difference]
		)
	for frame_index in 6:
		assertions.truthy(
			_lower_body_silhouette_difference(silhouettes[frame_index], silhouettes[frame_index + 6]) >= 20,
			"%s pose %d has a distinct opposite-leg half-cycle partner" % [direction, frame_index]
		)
	var boot_differences: Array[int] = []
	for frame_index in SIDE_WALK_FRAME_COUNT:
		boot_differences.append(
			_boot_silhouette_difference(
				silhouettes[frame_index],
				silhouettes[(frame_index + 1) % SIDE_WALK_FRAME_COUNT]
			)
		)
	assertions.truthy(
		boot_differences.min() >= 18,
		"%s every side-walk frame advances a boot: %s" % [direction, boot_differences]
	)
	for frame_index in boot_differences.size():
		var maximum_boot_difference := 120 if frame_index == 8 else 80
		assertions.truthy(
			boot_differences[frame_index] <= maximum_boot_difference,
			"%s boot transition %d stays within its phase (%d <= %d)"
			% [direction, frame_index, boot_differences[frame_index], maximum_boot_difference]
		)
	for transition in [
		{"from": 1, "to": 2, "name": "left boot leaves the ground"},
		{"from": 3, "to": 4, "name": "left boot crosses the right support leg"},
		{"from": 5, "to": 6, "name": "left boot extends after crossing"},
		{"from": 6, "to": 7, "name": "left boot reaches contact"},
		{"from": 7, "to": 8, "name": "left boot loads after contact"},
		{"from": 8, "to": 9, "name": "right boot leaves the ground"},
		{"from": 9, "to": 10, "name": "right boot crosses the left support leg"},
		{"from": 10, "to": 11, "name": "right boot extends after crossing"},
	]:
		var from_frame := int(transition["from"])
		var to_frame := int(transition["to"])
		var change := _boot_silhouette_difference(silhouettes[from_frame], silhouettes[to_frame])
		assertions.truthy(
			change >= 18,
			"%s %s (%d)" % [direction, str(transition["name"]), change]
		)


func _frame_image(texture: Texture2D) -> Image:
	if texture is AtlasTexture:
		return texture.atlas.get_image().get_region(Rect2i(texture.region))
	return texture.get_image()


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
	assertions.near(player.speed, 3.0, 0.001, "player walking speed matches the painted stride")
	assertions.near(player.sprint_speed, 5.0, 0.001, "player sprint remains faster without outrunning the animation")
	assertions.near(
		(player.get_node("PlayerVisual") as AnimatedSprite3D).position.y,
		0.60,
		0.001,
		"smaller player art keeps its boots on the ground"
	)
	var controller_source := FileAccess.get_file_as_string("res://scripts/actors/player.gd")
	assertions.truthy(not "rotation.y" in controller_source, "player movement never rotates the root node")
	assertions.truthy("player_visual.sync_motion" in controller_source, "player movement drives its visual from resolved velocity")
	player.free()
