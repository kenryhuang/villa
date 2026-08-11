class_name BuildingProductionYard
extends Node3D

const TerrainBuilderScript = preload("res://scripts/world/terrain_builder.gd")

const GROUND_TEXTURE_SIZE := Vector2(1024.0, 1024.0)
const GROUND_OVERHANG_PER_SIDE := 0.1
const GROUND_SUBDIVISIONS_PER_CELL := 3
const GROUND_SURFACE_LIFT := 0.028
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
var _ground_mesh: MeshInstance3D
var _ground_material: StandardMaterial3D
var _terrain_height_image: Image
var _rebuilding_ground := false


func _init() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_ENTER_TREE, NOTIFICATION_TRANSFORM_CHANGED] and _ground_mesh != null and not _rebuilding_ground:
		_rebuild_ground_mesh()


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
		_build_ground_mesh(texture)
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
	return 1 if _ground_mesh != null and is_instance_valid(_ground_mesh) else 0


func get_ground_size() -> Vector3:
	return _ground_mesh.get_aabb().size if _ground_mesh != null else Vector3.ZERO


func get_style() -> String:
	return _style


func get_visual_tint() -> Color:
	if _preview_active:
		return Color(0.48, 1.0, 0.52, 1.0) if _preview_valid else Color(1.0, 0.38, 0.38, 1.0)
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
	if _ground_mesh != null and is_instance_valid(_ground_mesh):
		if _ground_mesh.get_parent() == self:
			remove_child(_ground_mesh)
		_ground_mesh.free()
	_ground_mesh = null
	_ground_material = null
	_terrain_height_image = null
	_output_slots.clear()


func _build_ground_mesh(texture: Texture2D) -> void:
	_ground_mesh = MeshInstance3D.new()
	_ground_mesh.name = "GroundMesh"
	_ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_texture = texture
	_ground_material.albedo_color = Color.WHITE
	_ground_material.roughness = 1.0
	_ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ground_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ground_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground_material.render_priority = -1
	_ground_mesh.material_override = _ground_material
	add_child(_ground_mesh)
	var height_texture := load(TerrainBuilderScript.HEIGHTMAP_PATH) as Texture2D
	_terrain_height_image = height_texture.get_image() if height_texture != null else null
	_rebuild_ground_mesh()


func _rebuild_ground_mesh() -> void:
	if _ground_mesh == null or _yard_size == Vector2i.ZERO or _rebuilding_ground:
		return
	_rebuilding_ground = true
	var width := float(_yard_size.x) + GROUND_OVERHANG_PER_SIDE * 2.0
	var depth := float(_yard_size.y) + GROUND_OVERHANG_PER_SIDE * 2.0
	var columns := _yard_size.x * GROUND_SUBDIVISIONS_PER_CELL
	var rows := _yard_size.y * GROUND_SUBDIVISIONS_PER_CELL
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var can_sample_world := is_inside_tree()
	for row in range(rows + 1):
		var v := float(row) / float(rows)
		var local_z := lerpf(-depth * 0.5, depth * 0.5, v)
		for column in range(columns + 1):
			var u := float(column) / float(columns)
			var local_x := lerpf(-width * 0.5, width * 0.5, u)
			var local_ground := Vector3(local_x, GROUND_SURFACE_LIFT, local_z)
			if can_sample_world:
				var world_flat := to_global(Vector3(local_x, 0.0, local_z))
				var height := TerrainBuilderScript.sample_surface_height(
					_terrain_height_image,
					world_flat.x,
					world_flat.z
				)
				local_ground = to_local(Vector3(
					world_flat.x,
					height + GROUND_SURFACE_LIFT,
					world_flat.z
				))
			surface.set_uv(Vector2(u, v))
			surface.add_vertex(local_ground)
	var stride := columns + 1
	for row in rows:
		for column in columns:
			var top_left := row * stride + column
			var top_right := top_left + 1
			var bottom_left := top_left + stride
			var bottom_right := bottom_left + 1
			for index in [top_left, bottom_left, top_right, top_right, bottom_left, bottom_right]:
				surface.add_index(index)
	surface.generate_normals()
	_ground_mesh.mesh = surface.commit()
	_rebuilding_ground = false


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
	if _ground_material != null:
		_ground_material.albedo_color = get_visual_tint()


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
