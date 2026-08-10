class_name BuildingProductionYard
extends Node3D

const TerrainBuilderScript = preload("res://scripts/world/terrain_builder.gd")

const GROUND_TEXTURE_SIZE := Vector2(1024.0, 1024.0)
const GROUND_OVERHANG_PER_SIDE := 0.1
const GROUND_DECAL_CENTER_Y := 0.35
const GROUND_DECAL_PROJECTION_DEPTH := 2.0
const VALID_STYLES := ["timber", "masonry", "industrial"]
const TEXTURES := {
	"timber": "res://assets/buildings/yards/timber_yard_ground.png",
	"masonry": "res://assets/buildings/yards/masonry_yard_ground.png",
	"industrial": "res://assets/buildings/yards/industrial_yard_ground.png",
}

static var _warned_ground_styles := {}

var _yard_size := Vector2i.ZERO
var _style := ""
var _structure_offset := Vector3.ZERO
var _construction_stage := 3
var _preview_active := false
var _preview_valid := true
var _maintenance_state := "normal"
var _output_slots: Array[Vector3] = []
var _ground_decal: Decal


func configure(size: Vector2i, style: String, structure_offset: Vector3) -> bool:
	if size.x not in [3, 4] or size.y != size.x or style not in VALID_STYLES:
		return false
	clear_immediately()
	_yard_size = size
	_style = style
	_structure_offset = structure_offset
	_output_slots = _slots_for_size(size)
	var texture := _load_ground_texture(style)
	if texture != null:
		_build_ground_decal(texture)
	_apply_visual_state()
	return true


func set_preview_state(active: bool, valid: bool) -> void:
	_preview_active = active
	_preview_valid = valid
	_apply_visual_state()


func set_construction_stage(stage: int) -> void:
	_construction_stage = clampi(stage, 0, 3)


func get_construction_stage() -> int:
	return _construction_stage


func set_maintenance_state(state: String) -> void:
	_maintenance_state = state


func set_interaction_enabled(_enabled: bool) -> void:
	pass


func get_output_slots() -> Array[Vector3]:
	return _output_slots.duplicate()


func get_fence_segment_count() -> int:
	return 0


func get_transition_sprite_count() -> int:
	return 0


func advance_transition_for_test(_delta: float) -> void:
	pass


func get_ground_visual_count() -> int:
	return 1 if _ground_decal != null and is_instance_valid(_ground_decal) else 0


func get_ground_size() -> Vector3:
	return _ground_decal.size if _ground_decal != null else Vector3.ZERO


func get_ground_cull_mask() -> int:
	return _ground_decal.cull_mask if _ground_decal != null else 0


func get_style() -> String:
	return _style


func get_visual_tint() -> Color:
	if _preview_active:
		return Color(0.48, 1.0, 0.52, 0.68) if _preview_valid else Color(1.0, 0.38, 0.38, 0.68)
	return Color.WHITE


func all_output_slots_inside_bounds() -> bool:
	var half_x := float(_yard_size.x) * 0.5
	var half_z := float(_yard_size.y) * 0.5
	for slot in _output_slots:
		if absf(slot.x) >= half_x or absf(slot.z) >= half_z:
			return false
	return true


func has_enabled_collisions() -> bool:
	return false


func get_collision_layers() -> Array[int]:
	return []


func clear_immediately() -> void:
	if _ground_decal != null and is_instance_valid(_ground_decal):
		if _ground_decal.get_parent() == self:
			remove_child(_ground_decal)
		_ground_decal.free()
	_ground_decal = null
	_output_slots.clear()


func _build_ground_decal(texture: Texture2D) -> void:
	_ground_decal = Decal.new()
	_ground_decal.name = "GroundDecal"
	_ground_decal.texture_albedo = texture
	_ground_decal.size = Vector3(
		float(_yard_size.x) + GROUND_OVERHANG_PER_SIDE * 2.0,
		GROUND_DECAL_PROJECTION_DEPTH,
		float(_yard_size.y) + GROUND_OVERHANG_PER_SIDE * 2.0
	)
	_ground_decal.position = Vector3(0.0, GROUND_DECAL_CENTER_Y, 0.0)
	_ground_decal.cull_mask = TerrainBuilderScript.PRODUCTION_GROUND_RENDER_LAYER
	_ground_decal.upper_fade = 0.0
	_ground_decal.lower_fade = 0.0
	add_child(_ground_decal)


func _slots_for_size(size: Vector2i) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var columns := 3 if size.x == 3 else 4
	var spacing := 0.78
	var start_x := -float(columns - 1) * spacing * 0.5
	var first_z := float(size.y) * 0.5 - 0.76
	for row in 2:
		for column in columns:
			result.append(Vector3(start_x + float(column) * spacing, 0.0, first_z - float(row) * 0.54))
	return result


func _apply_visual_state() -> void:
	if _ground_decal != null:
		_ground_decal.modulate = get_visual_tint()


func _load_ground_texture(style: String) -> Texture2D:
	var path := str(TEXTURES.get(style, ""))
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture != null and texture.get_size() == GROUND_TEXTURE_SIZE:
		return texture
	if not _warned_ground_styles.has(style):
		_warned_ground_styles[style] = true
		push_warning(
			"Missing or malformed production ground texture '%s'; ground omitted while output slots remain available."
			% path
		)
	return null
