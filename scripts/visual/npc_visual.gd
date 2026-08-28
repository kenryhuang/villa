class_name NpcVisual
extends Sprite3D

const DEFAULT_DIRECTION := "s"
const GRID_SIZE := Vector2i(2, 2)
const TARGET_CELL_WORLD_HEIGHT := 1.35
const MOVEMENT_THRESHOLD_SQUARED := 0.0025
const DIRECTION_CELLS := {
	"n": Vector2i(0, 0),
	"e": Vector2i(1, 0),
	"s": Vector2i(0, 1),
	"w": Vector2i(1, 1),
}

var _configured := false
var _last_direction := DEFAULT_DIRECTION
var _cell_size := Vector2i.ZERO


func configure(atlas: Texture2D) -> bool:
	_configured = false
	visible = false
	texture = null
	if atlas == null or atlas.get_width() <= 0 or atlas.get_height() <= 0:
		return false
	if atlas.get_width() % GRID_SIZE.x != 0 or atlas.get_height() % GRID_SIZE.y != 0:
		return false
	_cell_size = Vector2i(
		atlas.get_width() / GRID_SIZE.x,
		atlas.get_height() / GRID_SIZE.y
	)
	texture = atlas
	region_enabled = true
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaded = false
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	pixel_size = TARGET_CELL_WORLD_HEIGHT / float(_cell_size.y)
	centered = true
	_last_direction = DEFAULT_DIRECTION
	_apply_direction()
	_configured = true
	visible = true
	return true


func sync_motion(planar_velocity: Vector2) -> void:
	if not _configured or planar_velocity.length_squared() <= MOVEMENT_THRESHOLD_SQUARED:
		return
	if absf(planar_velocity.x) > absf(planar_velocity.y):
		_last_direction = "e" if planar_velocity.x > 0.0 else "w"
	else:
		_last_direction = "s" if planar_velocity.y > 0.0 else "n"
	_apply_direction()


func get_last_direction() -> String:
	return _last_direction


func is_configured() -> bool:
	return _configured


func _apply_direction() -> void:
	var cell := DIRECTION_CELLS[_last_direction] as Vector2i
	region_rect = Rect2(Vector2(cell * _cell_size), Vector2(_cell_size))
