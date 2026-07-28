class_name CropSpriteCluster
extends Node3D

@export var back_texture_paths: Array[String] = []
@export var front_texture_paths: Array[String] = []
@export var canvas_world_height := 1.15
@export var front_offset := Vector3(0.025, 0.0, 0.025)
@export var back_modulate := Color(0.9, 0.9, 0.9, 1.0)

var _variant_seed := 0
var _variant_index := -1
var _configured := false


static func variant_index_for_seed(seed: int, count: int) -> int:
	return posmod(seed, count) if count > 0 else -1


func configure_variant_seed(seed: int) -> void:
	_variant_seed = seed
	_configured = true
	if is_inside_tree():
		_apply_variant()


func get_variant_index() -> int:
	return _variant_index


func _ready() -> void:
	_ensure_layers()
	_apply_variant()


func _ensure_layers() -> void:
	if get_node_or_null("BackLayer") == null:
		var back := Sprite3D.new()
		back.name = "BackLayer"
		add_child(back)
	if get_node_or_null("FrontLayer") == null:
		var front := Sprite3D.new()
		front.name = "FrontLayer"
		add_child(front)


func _apply_variant() -> void:
	_ensure_layers()
	var count := mini(back_texture_paths.size(), front_texture_paths.size())
	var index := variant_index_for_seed(_variant_seed if _configured else 0, count)
	if index < 0:
		_show_fallback("no complete painted variants")
		return
	var back := _load_texture(back_texture_paths[index])
	var front := _load_texture(front_texture_paths[index])
	if back == null or front == null:
		_show_fallback("missing painted texture pair at variant %d" % index)
		return
	_variant_index = index
	_configure_sprite($BackLayer, back, Vector3.ZERO, back_modulate, -0.1)
	_configure_sprite($FrontLayer, front, front_offset, Color.WHITE, 0.1)
	_set_fallback_visible(false)


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _configure_sprite(
	sprite: Sprite3D,
	texture: Texture2D,
	offset: Vector3,
	color: Color,
	sort_offset: float
) -> void:
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.pixel_size = canvas_world_height / float(texture.get_height())
	sprite.position = Vector3(offset.x, canvas_world_height * 0.5 + offset.y, offset.z)
	sprite.modulate = color
	sprite.sorting_offset = sort_offset
	sprite.visible = true


func _show_fallback(reason: String) -> void:
	_variant_index = -1
	($BackLayer as Sprite3D).visible = false
	($FrontLayer as Sprite3D).visible = false
	_set_fallback_visible(true)
	push_warning("CropSpriteCluster fallback: %s" % reason)


func _set_fallback_visible(value: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = value
