class_name BuildingProductionYard
extends Node3D

const TerrainBuilderScript = preload("res://scripts/world/terrain_builder.gd")

const GROUND_TEXTURE_SIZE := Vector2(1024.0, 1024.0)
const GROUND_OVERHANG_PER_SIDE := 0.1
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
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if is_inside_tree():
		_build_clipped_terrain_surface(surface, width, depth)
	else:
		_build_placeholder_surface(surface, width, depth)
	surface.generate_normals()
	_ground_mesh.mesh = surface.commit()
	_rebuilding_ground = false


func _build_placeholder_surface(surface: SurfaceTool, width: float, depth: float) -> void:
	var points := [
		Vector3(-width * 0.5, GROUND_SURFACE_LIFT, -depth * 0.5),
		Vector3(width * 0.5, GROUND_SURFACE_LIFT, -depth * 0.5),
		Vector3(-width * 0.5, GROUND_SURFACE_LIFT, depth * 0.5),
		Vector3(width * 0.5, GROUND_SURFACE_LIFT, depth * 0.5),
	]
	var uvs := [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]
	for index in points.size():
		surface.set_uv(uvs[index])
		surface.add_vertex(points[index])
	for index in [0, 2, 1, 1, 2, 3]:
		surface.add_index(index)


func _build_clipped_terrain_surface(surface: SurfaceTool, width: float, depth: float) -> void:
	var corners := [
		to_global(Vector3(-width * 0.5, 0.0, -depth * 0.5)),
		to_global(Vector3(width * 0.5, 0.0, -depth * 0.5)),
		to_global(Vector3(-width * 0.5, 0.0, depth * 0.5)),
		to_global(Vector3(width * 0.5, 0.0, depth * 0.5)),
	]
	var footprint_min_x := INF
	var footprint_max_x := -INF
	var footprint_min_z := INF
	var footprint_max_z := -INF
	for corner in corners:
		footprint_min_x = minf(footprint_min_x, corner.x)
		footprint_max_x = maxf(footprint_max_x, corner.x)
		footprint_min_z = minf(footprint_min_z, corner.z)
		footprint_max_z = maxf(footprint_max_z, corner.z)
	var half_world_x := TerrainBuilderScript.WORLD_SIZE.x * 0.5
	var half_world_z := TerrainBuilderScript.WORLD_SIZE.y * 0.5
	var clip_min_x := maxf(footprint_min_x, -half_world_x)
	var clip_max_x := minf(footprint_max_x, half_world_x)
	var clip_min_z := maxf(footprint_min_z, -half_world_z)
	var clip_max_z := minf(footprint_max_z, half_world_z)
	if clip_min_x >= clip_max_x or clip_min_z >= clip_max_z:
		_build_placeholder_surface(surface, width, depth)
		return
	var start_x := clampi(
		floori((clip_min_x / TerrainBuilderScript.WORLD_SIZE.x + 0.5) * TerrainBuilderScript.SUBDIVISIONS),
		0,
		TerrainBuilderScript.SUBDIVISIONS - 1
	)
	var end_x := clampi(
		floori((clip_max_x / TerrainBuilderScript.WORLD_SIZE.x + 0.5) * TerrainBuilderScript.SUBDIVISIONS),
		0,
		TerrainBuilderScript.SUBDIVISIONS - 1
	)
	var start_z := clampi(
		floori((clip_min_z / TerrainBuilderScript.WORLD_SIZE.y + 0.5) * TerrainBuilderScript.SUBDIVISIONS),
		0,
		TerrainBuilderScript.SUBDIVISIONS - 1
	)
	var end_z := clampi(
		floori((clip_max_z / TerrainBuilderScript.WORLD_SIZE.y + 0.5) * TerrainBuilderScript.SUBDIVISIONS),
		0,
		TerrainBuilderScript.SUBDIVISIONS - 1
	)
	var pending_indices := PackedInt32Array()
	var vertex_count := 0
	for cell_z in range(start_z, end_z + 1):
		var z0 := (float(cell_z) / float(TerrainBuilderScript.SUBDIVISIONS) - 0.5) * TerrainBuilderScript.WORLD_SIZE.y
		var z1 := (float(cell_z + 1) / float(TerrainBuilderScript.SUBDIVISIONS) - 0.5) * TerrainBuilderScript.WORLD_SIZE.y
		for cell_x in range(start_x, end_x + 1):
			var x0 := (float(cell_x) / float(TerrainBuilderScript.SUBDIVISIONS) - 0.5) * TerrainBuilderScript.WORLD_SIZE.x
			var x1 := (float(cell_x + 1) / float(TerrainBuilderScript.SUBDIVISIONS) - 0.5) * TerrainBuilderScript.WORLD_SIZE.x
			var a := Vector3(x0, TerrainBuilderScript.sample_height(_terrain_height_image, x0, z0), z0)
			var b := Vector3(x1, TerrainBuilderScript.sample_height(_terrain_height_image, x1, z0), z0)
			var c := Vector3(x0, TerrainBuilderScript.sample_height(_terrain_height_image, x0, z1), z1)
			var d := Vector3(x1, TerrainBuilderScript.sample_height(_terrain_height_image, x1, z1), z1)
			for triangle in [[a, c, b], [b, c, d]]:
				var polygon: Array[Vector3] = []
				polygon.assign(triangle)
				polygon = _clip_world_polygon(polygon, 0, clip_min_x, true)
				polygon = _clip_world_polygon(polygon, 0, clip_max_x, false)
				polygon = _clip_world_polygon(polygon, 2, clip_min_z, true)
				polygon = _clip_world_polygon(polygon, 2, clip_max_z, false)
				if polygon.size() < 3:
					continue
				var polygon_start := vertex_count
				for point in polygon:
					var u := clampf((point.x - footprint_min_x) / width, 0.0, 1.0)
					var v := clampf((point.z - footprint_min_z) / depth, 0.0, 1.0)
					surface.set_uv(Vector2(u, v))
					surface.add_vertex(to_local(point + Vector3.UP * GROUND_SURFACE_LIFT))
					vertex_count += 1
				for index in range(1, polygon.size() - 1):
					pending_indices.append(polygon_start)
					pending_indices.append(polygon_start + index)
					pending_indices.append(polygon_start + index + 1)
	for index in pending_indices:
		surface.add_index(index)


func _clip_world_polygon(
	polygon: Array[Vector3],
	axis: int,
	boundary: float,
	keep_greater: bool
) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if polygon.is_empty():
		return result
	var previous := polygon[polygon.size() - 1]
	var previous_value := previous[axis]
	var previous_inside := previous_value >= boundary if keep_greater else previous_value <= boundary
	for current in polygon:
		var current_value := current[axis]
		var current_inside := current_value >= boundary if keep_greater else current_value <= boundary
		if current_inside != previous_inside:
			var denominator := current_value - previous_value
			var ratio := 0.0 if is_zero_approx(denominator) else (boundary - previous_value) / denominator
			var intersection := previous.lerp(current, clampf(ratio, 0.0, 1.0))
			intersection[axis] = boundary
			result.append(intersection)
		if current_inside:
			result.append(current)
		previous = current
		previous_value = current_value
		previous_inside = current_inside
	return result


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
