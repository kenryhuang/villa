class_name MapUI
extends Control

## 地图界面 - 显示探索状态和玩家位置

signal blocking_opened

@onready var map_texture: TextureRect = $MapTexture
@onready var player_marker: Sprite2D = $MapTexture/PlayerMarker

var _is_open := false
var _player_ref


func _ready() -> void:
	visible = false


func configure(player: Node3D) -> void:
	_player_ref = player


func open() -> void:
	var was_open := _is_open
	_is_open = true
	visible = true
	_update_map()
	if not was_open:
		blocking_opened.emit()


func close() -> void:
	_is_open = false
	visible = false


func _update_map() -> void:
	if map_texture == null:
		return

	var exploration = get_node_or_null("/root/ExplorationSystem")
	if exploration and exploration.fog_texture:
		map_texture.texture = exploration.fog_texture


func _process(_delta: float) -> void:
	if not _is_open or _player_ref == null:
		return

	# 更新玩家标记位置
	if map_texture and player_marker:
		var tex_size = map_texture.size
		var player_x = _player_ref.global_position.x
		var player_z = _player_ref.global_position.z

		# 世界坐标 → UI 坐标
		var ui_x = ((player_x + 18.0) / 36.0) * tex_size.x
		var ui_y = ((player_z + 14.0) / 28.0) * tex_size.y
		player_marker.position = Vector2(ui_x, ui_y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		if _is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
