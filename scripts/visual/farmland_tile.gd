class_name FarmlandTile
extends MeshInstance3D

const TEXTURE_PATH := "res://assets/terrain/farmland-soil-hand-painted.png"
const SURFACE_LIFT := 0.042


func configure(
	cell: GridCell,
	terrain: TerrainBuilder,
	origin_x: float,
	origin_z: float,
	cell_size: float
) -> bool:
	if cell == null or terrain == null or cell_size <= 0.0:
		return false
	name = "FarmlandVisual_%d_%d" % [cell.gx, cell.gz]
	set_meta("gx", cell.gx)
	set_meta("gz", cell.gz)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var x0 := origin_x + float(cell.gx) * cell_size
	var z0 := origin_z + float(cell.gz) * cell_size
	var x1 := x0 + cell_size
	var z1 := z0 + cell_size
	var points := [
		Vector3(x0, terrain.get_height_at(x0, z0) + SURFACE_LIFT, z0),
		Vector3(x1, terrain.get_height_at(x1, z0) + SURFACE_LIFT, z0),
		Vector3(x1, terrain.get_height_at(x1, z1) + SURFACE_LIFT, z1),
		Vector3(x0, terrain.get_height_at(x0, z1) + SURFACE_LIFT, z1),
	]
	var uvs := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size():
		surface.set_uv(uvs[index])
		surface.add_vertex(points[index])
	for index in [0, 2, 1, 0, 3, 2]:
		surface.add_index(index)
	surface.generate_normals()
	mesh = surface.commit()

	var material := StandardMaterial3D.new()
	material.albedo_texture = load(TEXTURE_PATH) as Texture2D
	material.albedo_color = Color(0.9, 0.82, 0.7)
	material.roughness = 0.96
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material_override = material
	return material.albedo_texture != null
