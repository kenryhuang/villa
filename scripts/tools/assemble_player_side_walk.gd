extends SceneTree

const FRAME_SIZE := Vector2i(192, 192)
const FRAME_COUNT := 12
const BASELINE_Y := 184
const MAX_CHARACTER_SIZE := Vector2i(178, 178)
const INPUT_DIR := "res://tmp/player-side-walk/revision/frames"
const OUTPUT_PATH := "res://assets/characters/player/player_farmer_side_walk.png"
const ANCHOR_FRAMES := [0]
const FRAME_SCALE_ADJUSTMENTS := [1.0, 1.0, 1.0, 1.0, 1.0, 1.02, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
const FRAME_X_OFFSETS := [0, -7, 0, 0, 0, -4, 0, 0, 0, 2, 0, 0]


func _init() -> void:
	var sources: Array[Image] = []
	var maximum_bounds := Vector2i.ZERO
	for index in FRAME_COUNT:
		var source_path := INPUT_DIR.path_join("east-%02d.png" % index)
		var source := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		if source == null or source.is_empty() or not _has_transparent_corners(source):
			_fail("Missing or invalid east frame %02d." % index)
			return
		var used := source.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			_fail("East frame %02d is empty." % index)
			return
		if index in ANCHOR_FRAMES:
			if source.get_size() != FRAME_SIZE:
				_fail("Anchor frame %02d must remain an exact %s cell." % [index, FRAME_SIZE])
				return
		else:
			maximum_bounds = maximum_bounds.max(used.size)
		sources.append(source)

	var common_scale := minf(
		float(MAX_CHARACTER_SIZE.x) / float(maximum_bounds.x),
		float(MAX_CHARACTER_SIZE.y) / float(maximum_bounds.y)
	)
	var output := Image.create_empty(
		FRAME_SIZE.x * FRAME_COUNT,
		FRAME_SIZE.y * 2,
		false,
		Image.FORMAT_RGBA8
	)
	output.fill(Color.TRANSPARENT)
	for index in FRAME_COUNT:
		var frame := sources[index].duplicate() if index in ANCHOR_FRAMES else _fit_into_cell(
			sources[index],
			common_scale * FRAME_SCALE_ADJUSTMENTS[index]
		)
		frame = _shift_frame(frame, FRAME_X_OFFSETS[index])
		output.blit_rect(
			frame,
			Rect2i(Vector2i.ZERO, FRAME_SIZE),
			Vector2i(index * FRAME_SIZE.x, 0)
		)
		var west := frame.duplicate()
		west.flip_x()
		output.blit_rect(
			west,
			Rect2i(Vector2i.ZERO, FRAME_SIZE),
			Vector2i(index * FRAME_SIZE.x, FRAME_SIZE.y)
		)

	var save_error := output.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if save_error != OK:
		_fail("Could not save side-walk atlas (%d)." % save_error)
		return
	print(
		"PASS: assembled %d east frames and %d mirrored west frames at %s"
		% [FRAME_COUNT, FRAME_COUNT, OUTPUT_PATH]
	)
	quit(0)


func _fit_into_cell(source: Image, common_scale: float) -> Image:
	var used := source.get_used_rect()
	var crop := source.get_region(used)
	crop.resize(
		maxi(1, roundi(crop.get_width() * common_scale)),
		maxi(1, roundi(crop.get_height() * common_scale)),
		Image.INTERPOLATE_LANCZOS
	)
	var cell := Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	cell.fill(Color.TRANSPARENT)
	var origin := Vector2i(
		(FRAME_SIZE.x - crop.get_width()) / 2,
		BASELINE_Y - crop.get_height()
	)
	cell.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), origin)
	return cell


func _shift_frame(source: Image, offset_x: int) -> Image:
	if offset_x == 0:
		return source
	var shifted := Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	shifted.fill(Color.TRANSPARENT)
	var source_x := maxi(0, -offset_x)
	var destination_x := maxi(0, offset_x)
	var width := FRAME_SIZE.x - absi(offset_x)
	shifted.blit_rect(
		source,
		Rect2i(Vector2i(source_x, 0), Vector2i(width, FRAME_SIZE.y)),
		Vector2i(destination_x, 0)
	)
	return shifted


func _has_transparent_corners(source: Image) -> bool:
	for point in [
		Vector2i.ZERO,
		Vector2i(source.get_width() - 1, 0),
		Vector2i(0, source.get_height() - 1),
		source.get_size() - Vector2i.ONE,
	]:
		if source.get_pixelv(point).a > 0.05:
			return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
