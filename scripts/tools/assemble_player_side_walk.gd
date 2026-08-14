extends SceneTree

const FRAME_SIZE := Vector2i(192, 192)
const FRAME_COUNT := 12
const SOURCE_COLUMNS := 4
const SOURCE_ROWS := 3
const BASELINE_Y := 184
const MAX_CHARACTER_SIZE := Vector2i(178, 178)
const CONTACT_SHEET_PATH := "res://tmp/player-side-walk/east-contact-sheet-transparent.png"
const EXTRACTED_FRAME_DIR := "res://tmp/player-side-walk/frames"
const OUTPUT_PATH := "res://assets/characters/player/player_farmer_side_walk.png"


func _init() -> void:
	var contact_sheet := Image.load_from_file(ProjectSettings.globalize_path(CONTACT_SHEET_PATH))
	if contact_sheet == null or contact_sheet.is_empty():
		_fail("Missing transparent contact sheet '%s'." % CONTACT_SHEET_PATH)
		return
	if contact_sheet.get_width() % SOURCE_COLUMNS != 0 or contact_sheet.get_height() % SOURCE_ROWS != 0:
		_fail(
			"Contact sheet must divide into a %dx%d grid; got %dx%d."
			% [SOURCE_COLUMNS, SOURCE_ROWS, contact_sheet.get_width(), contact_sheet.get_height()]
		)
		return

	var sources: Array[Image] = []
	var maximum_bounds := Vector2i.ZERO
	var source_cell_size := Vector2i(
		contact_sheet.get_width() / SOURCE_COLUMNS,
		contact_sheet.get_height() / SOURCE_ROWS
	)
	for index in FRAME_COUNT:
		var source_origin := Vector2i(index % SOURCE_COLUMNS, index / SOURCE_COLUMNS) * source_cell_size
		var source := contact_sheet.get_region(Rect2i(source_origin, source_cell_size))
		var used := source.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			_fail("Contact-sheet frame %02d is empty." % index)
			return
		if not _has_transparent_corners(source):
			_fail("Contact-sheet frame %02d does not have transparent corners." % index)
			return
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
	var frame_dir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(EXTRACTED_FRAME_DIR)
	)
	if frame_dir_error != OK:
		_fail("Could not create extracted-frame directory (%d)." % frame_dir_error)
		return
	for index in FRAME_COUNT:
		var frame := _fit_into_cell(sources[index], common_scale)
		var frame_error := frame.save_png(ProjectSettings.globalize_path(
			EXTRACTED_FRAME_DIR.path_join("east-%02d.png" % index)
		))
		if frame_error != OK:
			_fail("Could not save extracted frame %02d (%d)." % [index, frame_error])
			return
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
