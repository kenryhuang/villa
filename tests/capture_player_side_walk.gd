extends SceneTree

const PlayerVisualScript = preload("res://scripts/visual/player_visual.gd")
const ATLAS_PATH := "res://assets/characters/player/player_farmer_atlas.png"
const OUTPUT_DIR := "res://.godot/player-side-walk-validation"
const FRAME_SIZE := Vector2i(192, 192)
const FRAME_COUNT := 12
const BACKGROUND := Color("26303d")
const PANEL_BACKGROUND := Color("17202b")


func _init() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("player side-walk capture requires a display driver")
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("cannot create player side-walk capture directory: %s" % error_string(directory_error))
		return
	var visual := PlayerVisualScript.new()
	if not visual.configure(load(ATLAS_PATH) as Texture2D):
		visual.free()
		_fail("cannot configure player visual for capture")
		return
	visual.position = Vector3(-1000, -1000, -1000)
	root.add_child(visual)
	var captures := 0
	if await _capture_strip(visual.sprite_frames, &"walk_e", "EAST - 12 sequential walk frames", "east-strip.png"):
		captures += 1
	if await _capture_strip(visual.sprite_frames, &"walk_w", "WEST - exact horizontal mirrors", "west-strip.png"):
		captures += 1
	if await _capture_half_cycle_pairs(visual.sprite_frames):
		captures += 1
	if await _capture_runtime_states(visual):
		captures += 1
	visual.free()
	if captures != 4:
		_fail("player side-walk capture count mismatch: %d" % captures)
		return
	print("PASS: %d deterministic player side-walk captures in %s" % [captures, output_path])
	quit(0)


func _capture_strip(
	frames: SpriteFrames,
	animation_name: StringName,
	title: String,
	file_name: String
) -> bool:
	var size := Vector2i(FRAME_SIZE.x * FRAME_COUNT, FRAME_SIZE.y + 48)
	var canvas := _new_canvas(size)
	_add_label(canvas, title, Rect2(12, 6, size.x - 24, 32), 22, HORIZONTAL_ALIGNMENT_CENTER)
	for index in FRAME_COUNT:
		_add_frame(
			canvas,
			frames.get_frame_texture(animation_name, index),
			Vector2(index * FRAME_SIZE.x, 48),
			FRAME_SIZE
		)
		_add_label(
			canvas,
			"%02d" % index,
			Rect2(index * FRAME_SIZE.x + 8, 52, 42, 28),
			18,
			HORIZONTAL_ALIGNMENT_LEFT
		)
	return await _save_canvas(canvas, size, file_name)


func _capture_half_cycle_pairs(frames: SpriteFrames) -> bool:
	var size := Vector2i(FRAME_SIZE.x * 6, FRAME_SIZE.y * 2 + 54)
	var canvas := _new_canvas(size)
	_add_label(
		canvas,
		"HALF-CYCLE PAIRS - opposite supporting legs",
		Rect2(12, 6, size.x - 24, 32),
		22,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	for pair_index in 6:
		for row in 2:
			var frame_index := pair_index + row * 6
			var origin := Vector2(pair_index * FRAME_SIZE.x, 54 + row * FRAME_SIZE.y)
			_add_frame(
				canvas,
				frames.get_frame_texture(&"walk_e", frame_index),
				origin,
				FRAME_SIZE
			)
			_add_label(
				canvas,
				"%02d" % frame_index,
				Rect2(origin + Vector2(8, 4), Vector2(42, 28)),
				18,
				HORIZONTAL_ALIGNMENT_LEFT
			)
	return await _save_canvas(canvas, size, "half-cycle-pairs.png")


func _capture_runtime_states(visual: PlayerVisual) -> bool:
	const SAMPLE_COUNT := 6
	const SAMPLE_INTERVAL := 1.0 / 6.0
	var states := [
		{"direction": Vector2.RIGHT, "sprinting": false, "label": "EAST WALK - walk_e - 12 FPS"},
		{"direction": Vector2.RIGHT, "sprinting": true, "label": "EAST SPRINT - walk_e - 18 FPS"},
		{"direction": Vector2.LEFT, "sprinting": false, "label": "WEST WALK - walk_w - 12 FPS"},
		{"direction": Vector2.LEFT, "sprinting": true, "label": "WEST SPRINT - walk_w - 18 FPS"},
	]
	var row_height := FRAME_SIZE.y + 38
	var size := Vector2i(FRAME_SIZE.x * SAMPLE_COUNT, row_height * states.size())
	var canvas := _new_canvas(size)
	var captured_sequences: Array[Array] = []
	for row in states.size():
		var state: Dictionary = states[row]
		visual.sync_motion(state.direction as Vector2, bool(state.sprinting), true)
		visual.set_frame_and_progress(0, 0.0)
		var expected_speed := 1.5 if bool(state.sprinting) else 1.0
		if absf(visual.speed_scale - expected_speed) > 0.001:
			canvas.queue_free()
			_fail("runtime capture found unexpected speed scale: %.3f" % visual.speed_scale)
			return false
		var row_origin := row * row_height
		_add_label(
			canvas,
			str(state.label),
			Rect2(10, row_origin + 4, size.x - 20, 30),
			20,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		var sequence: Array[int] = []
		for column in SAMPLE_COUNT:
			if column > 0:
				await create_timer(SAMPLE_INTERVAL).timeout
			var frame_index := visual.frame
			sequence.append(frame_index)
			_add_frame(
				canvas,
				visual.sprite_frames.get_frame_texture(visual.animation, frame_index),
				Vector2(column * FRAME_SIZE.x, row_origin + 38),
				FRAME_SIZE
			)
			_add_label(
				canvas,
				"t%03d f%02d" % [roundi(column * SAMPLE_INTERVAL * 1000.0), frame_index],
				Rect2(column * FRAME_SIZE.x + 8, row_origin + 42, 100, 26),
				16,
				HORIZONTAL_ALIGNMENT_LEFT
			)
		captured_sequences.append(sequence)
	if captured_sequences[0] == captured_sequences[1] or captured_sequences[2] == captured_sequences[3]:
		canvas.queue_free()
		_fail("runtime capture did not distinguish 12 FPS walk from 18 FPS sprint")
		return false
	return await _save_canvas(canvas, size, "runtime-walk-sprint.png")


func _new_canvas(size: Vector2i) -> Control:
	root.content_scale_size = size
	root.size = size
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	return canvas


func _add_frame(parent: Control, texture: Texture2D, origin: Vector2, size: Vector2i) -> void:
	var panel := ColorRect.new()
	panel.color = PANEL_BACKGROUND
	panel.position = origin + Vector2(3, 3)
	panel.size = Vector2(size - Vector2i(6, 6))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var view := TextureRect.new()
	view.texture = texture
	view.position = origin
	view.size = Vector2(size)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(view)


func _add_label(
	parent: Control,
	text: String,
	rect: Rect2,
	font_size: int,
	alignment: HorizontalAlignment
) -> void:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color("111821"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


func _save_canvas(canvas: Control, size: Vector2i, file_name: String) -> bool:
	for _frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != size:
		canvas.queue_free()
		_fail("invalid player side-walk capture '%s': %s" % [file_name, image.get_size()])
		return false
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))
	var save_error := image.save_png(path)
	canvas.queue_free()
	await process_frame
	if save_error != OK:
		_fail("cannot save player side-walk capture '%s': %s" % [file_name, error_string(save_error)])
		return false
	print("CAPTURE: %s (%dx%d)" % [path, size.x, size.y])
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
