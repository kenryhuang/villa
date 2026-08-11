class_name TerrainBuilder
extends Node3D

const WORLD_SIZE := Vector2(36.0, 28.0)
const SUBDIVISIONS := 96
const MIN_HEIGHT := -0.12
const MAX_HEIGHT := 0.9
const HEIGHTMAP_PATH := "res://assets/terrain/heightmap-valley.png"

var height_image: Image

static func sample_height(image: Image, world_x: float, world_z: float) -> float:
	if image == null or image.is_empty():
		return 0.0
	var u := clampf(world_x / WORLD_SIZE.x + 0.5, 0.0, 1.0)
	var v := clampf(world_z / WORLD_SIZE.y + 0.5, 0.0, 1.0)
	var pixel_x := clampi(roundi(u * float(image.get_width() - 1)), 0, image.get_width() - 1)
	var pixel_y := clampi(roundi(v * float(image.get_height() - 1)), 0, image.get_height() - 1)
	return lerpf(MIN_HEIGHT, MAX_HEIGHT, image.get_pixel(pixel_x, pixel_y).r)


func build() -> bool:
	var height_texture := load(HEIGHTMAP_PATH) as Texture2D
	height_image = height_texture.get_image() if height_texture else null
	if height_image == null or height_image.is_empty():
		push_error("Unable to load terrain heightmap: %s" % HEIGHTMAP_PATH)
		return false
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	for z_index in range(SUBDIVISIONS + 1):
		var z_ratio := float(z_index) / float(SUBDIVISIONS)
		var world_z := (z_ratio - 0.5) * WORLD_SIZE.y
		for x_index in range(SUBDIVISIONS + 1):
			var x_ratio := float(x_index) / float(SUBDIVISIONS)
			var world_x := (x_ratio - 0.5) * WORLD_SIZE.x
			var height := sample_height(height_image, world_x, world_z)
			heights.append(height)
			surface.set_uv(Vector2(x_ratio * 4.5, z_ratio * 3.5))
			surface.add_vertex(Vector3(world_x, height, world_z))
	var row_size := SUBDIVISIONS + 1
	for z_index in SUBDIVISIONS:
		for x_index in SUBDIVISIONS:
			var a := z_index * row_size + x_index
			var b := a + 1
			var c := a + row_size
			var d := c + 1
			surface.add_index(a)
			surface.add_index(c)
			surface.add_index(b)
			surface.add_index(b)
			surface.add_index(c)
			surface.add_index(d)
	surface.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = surface.commit()
	mesh_instance.material_override = _terrain_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = row_size
	shape.map_depth = row_size
	shape.map_data = heights
	collision.shape = shape
	collision.scale = Vector3(WORLD_SIZE.x / SUBDIVISIONS, 1.0, WORLD_SIZE.y / SUBDIVISIONS)
	body.add_child(collision)
	add_child(body)
	return true

func get_height_at(world_x: float, world_z: float) -> float:
	return sample_height(height_image, world_x, world_z)


func _terrain_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var texture := load("res://assets/terrain/grass-seamless-blended.png") as Texture2D
	if texture:
		material.albedo_texture = texture
	else:
		push_warning("Grass texture missing; using color fallback")
	material.albedo_color = Color(0.72, 0.8, 0.68)
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
