extends SceneTree

const FRAME_SIZE := Vector2i(192, 192)
const SOURCE_FRAME_INDICES := [0, 2, 4, 5, 6, 8, 9, 10, 11]
const FRAME_COUNT := 9
const BASELINE_Y := 184
const TARGET_CHARACTER_HEIGHT := 151
const INPUT_DIR := "res://tmp/player-side-walk/revision/frames"
const OUTPUT_PATH := "res://assets/characters/player/player_farmer_side_walk.png"
const REFERENCE_ATLAS_PATH := "res://assets/characters/player/player_farmer_atlas.png"
const REFERENCE_EAST_ROW := 2
const REFERENCE_WALK_START_COLUMN := 2
const REFERENCE_WALK_FRAME_COUNT := 6
const MIN_DENIM_GAIN := 0.45
const MAX_DENIM_GAIN := 1.20
const FRAME_X_OFFSETS := [0, 0, 0, -3, 0, 0, 2, 0, 0]


func _init() -> void:
	var reference_atlas := Image.load_from_file(ProjectSettings.globalize_path(REFERENCE_ATLAS_PATH))
	if reference_atlas == null or reference_atlas.is_empty():
		_fail("Missing player reference atlas '%s'." % REFERENCE_ATLAS_PATH)
		return
	var reference_denim := _reference_denim_mean(reference_atlas)
	var sources: Array[Image] = []
	for output_index in FRAME_COUNT:
		var source_index: int = SOURCE_FRAME_INDICES[output_index]
		var source_path := INPUT_DIR.path_join("east-%02d.png" % source_index)
		var source := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		if source == null or source.is_empty() or not _has_transparent_corners(source):
			_fail("Missing or invalid east source frame %02d." % source_index)
			return
		var used := source.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			_fail("East source frame %02d is empty." % source_index)
			return
		source = source.duplicate()
		_match_denim(source, reference_denim)
		sources.append(source)

	var output := Image.create_empty(
		FRAME_SIZE.x * FRAME_COUNT,
		FRAME_SIZE.y * 2,
		false,
		Image.FORMAT_RGBA8
	)
	output.fill(Color.TRANSPARENT)
	for index in FRAME_COUNT:
		var frame := _fit_into_cell(sources[index])
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


func _fit_into_cell(source: Image) -> Image:
	var used := source.get_used_rect()
	var crop := source.get_region(used)
	var scale := float(TARGET_CHARACTER_HEIGHT) / float(crop.get_height())
	crop.resize(
		maxi(1, roundi(crop.get_width() * scale)),
		TARGET_CHARACTER_HEIGHT,
		Image.INTERPOLATE_LANCZOS
	)
	var cell := Image.create_empty(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	cell.fill(Color.TRANSPARENT)
	var origin := Vector2i(
		(FRAME_SIZE.x - crop.get_width()) / 2,
		BASELINE_Y - TARGET_CHARACTER_HEIGHT
	)
	cell.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), origin)
	return cell


func _is_denim_pixel(color: Color) -> bool:
	return (
		color.a > 0.10
		and color.b > 45.0 / 255.0
		and color.b - color.r > 15.0 / 255.0
		and color.g - color.r > 5.0 / 255.0
	)


func _denim_mean(image: Image, region: Rect2i) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var color := image.get_pixel(x, y)
			if _is_denim_pixel(color):
				total += Vector3(color.r, color.g, color.b)
				count += 1
	return total / float(maxi(1, count))


func _reference_denim_mean(atlas: Image) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for column in REFERENCE_WALK_FRAME_COUNT:
		var region := Rect2i(
			Vector2i(
				(REFERENCE_WALK_START_COLUMN + column) * FRAME_SIZE.x,
				REFERENCE_EAST_ROW * FRAME_SIZE.y
			),
			FRAME_SIZE
		)
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var color := atlas.get_pixel(x, y)
				if _is_denim_pixel(color):
					total += Vector3(color.r, color.g, color.b)
					count += 1
	return total / float(maxi(1, count))


func _match_denim(source: Image, target: Vector3) -> void:
	var source_mean := _denim_mean(source, Rect2i(Vector2i.ZERO, source.get_size()))
	var gains := Vector3(
		clampf(target.x / maxf(source_mean.x, 0.001), MIN_DENIM_GAIN, MAX_DENIM_GAIN),
		clampf(target.y / maxf(source_mean.y, 0.001), MIN_DENIM_GAIN, MAX_DENIM_GAIN),
		clampf(target.z / maxf(source_mean.z, 0.001), MIN_DENIM_GAIN, MAX_DENIM_GAIN)
	)
	for y in source.get_height():
		for x in source.get_width():
			var color := source.get_pixel(x, y)
			if not _is_denim_pixel(color):
				continue
			color.r = clampf(color.r * gains.x, 0.0, 1.0)
			color.g = clampf(color.g * gains.y, 0.0, 1.0)
			color.b = clampf(color.b * gains.z, 0.0, 1.0)
			source.set_pixel(x, y, color)


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
