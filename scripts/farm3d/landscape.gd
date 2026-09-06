class_name Farm3DLandscape
extends Node3D

const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const Oak = preload("res://scenes/vegetation/painted_oak.tscn")
const CHUNK_SIZE := 16
const HEIGHT_COLUMNS := int(Profile.WORLD_SIZE.x) + 1
const HEIGHT_ROWS := int(Profile.WORLD_SIZE.y) + 1
var terrain_material: ShaderMaterial
var _heights := PackedFloat32Array()

func _ready() -> void:
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = preload("res://assets/terrain/landscape.gdshader")
	terrain_material.set_shader_parameter("grass_texture",preload("res://assets/terrain/grass-seamless-blended.png"))
	terrain_material.set_shader_parameter("sand_start", Profile.SAND_START)
	terrain_material.set_shader_parameter("sand_end", Profile.SAND_END)
	_heights.resize(HEIGHT_COLUMNS*HEIGHT_ROWS)
	for z in HEIGHT_ROWS:
		for x in HEIGHT_COLUMNS:
			_heights[z*HEIGHT_COLUMNS+x] = Profile.height_at(x+Profile.WORLD_MIN.x,z+Profile.WORLD_MIN.y)
	for z in range(int(Profile.WORLD_MIN.y),int(Profile.WORLD_MAX.y),CHUNK_SIZE):
		for x in range(int(Profile.WORLD_MIN.x),int(Profile.WORLD_MAX.x),CHUNK_SIZE):
			_build_chunk(x,z)
	_build_river()
	_build_lake()
	_build_fishing_shores()
	_build_bridge()
	_build_trees()
	_build_boundaries()
	_build_skirt()

func _build_chunk(start_x: int, start_z: int) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(start_z,start_z+CHUNK_SIZE+1):
		for x in range(start_x,start_x+CHUNK_SIZE+1):
			vertices.append(Vector3(x,_height(x,z),z))
			normals.append(Vector3(_height(x-1,z)-_height(x+1,z),2,_height(x,z-1)-_height(x,z+1)).normalized())
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var a := z*(CHUNK_SIZE+1)+x
			indices.append_array(PackedInt32Array([a,a+1,a+CHUNK_SIZE+2,a,a+CHUNK_SIZE+2,a+CHUNK_SIZE+1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.name = "Terrain_%d_%d" % [start_x,start_z]
	instance.mesh = mesh
	instance.material_override = terrain_material
	add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	instance.add_child(body)

func _height(x: int, z: int) -> float:
	return _heights[clampi(z-int(Profile.WORLD_MIN.y),0,HEIGHT_ROWS-1)*HEIGHT_COLUMNS+clampi(x-int(Profile.WORLD_MIN.x),0,HEIGHT_COLUMNS-1)]

func _build_river() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(int(Profile.WORLD_MIN.y),int(Profile.WORLD_MAX.y)):
		for side in [-1,1]:
			# Follow the shoreline at each end, never draw water through high banks.
			var points: Array[Vector3] = []
			for zz in [float(z),float(z+1)]:
				var center := Profile.river_x(zz)
				var width := 2.5
				while width < 8 and Profile.height_at(center+side*width,zz) < Profile.WATER_HEIGHT:
					width += .1
				points.append(Vector3(center,Profile.WATER_HEIGHT,zz))
				points.append(Vector3(center+side*width,Profile.WATER_HEIGHT,zz))
			for i in [0,1,3,0,3,2]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(points[i])
	var river := MeshInstance3D.new()
	river.name = "River"
	river.mesh = surface.commit()
	var water := ShaderMaterial.new()
	water.shader = preload("res://assets/terrain/river.gdshader")
	river.material_override = water
	add_child(river)

func _build_lake() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var minimum := Vector2i((Profile.LAKE_CENTER - Profile.LAKE_RADII * 1.3).floor())
	var maximum := Vector2i((Profile.LAKE_CENTER + Profile.LAKE_RADII * 1.3).ceil())
	for z in range(minimum.y, maximum.y):
		for x in range(minimum.x, maximum.x):
			var a := Vector3(x, _height(x,z), z)
			var b := Vector3(x+1, _height(x+1,z), z)
			var c := Vector3(x+1, _height(x+1,z+1), z+1)
			var d := Vector3(x, _height(x,z+1), z+1)
			_add_lake_triangle(surface, [a,b,c])
			_add_lake_triangle(surface, [a,c,d])
	var lake := MeshInstance3D.new()
	lake.name = "SouthLake"
	lake.mesh = surface.commit()
	var water := ShaderMaterial.new()
	water.shader = preload("res://assets/terrain/lake.gdshader")
	lake.material_override = water
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)

func _add_lake_triangle(surface: SurfaceTool, triangle: Array[Vector3]) -> void:
	# Clip each real terrain triangle at water level for an exact, irregular shore.
	var clipped: Array[Vector3] = []
	var previous := triangle[-1]
	for point in triangle:
		var inside := point.y <= Profile.WATER_HEIGHT
		if inside != (previous.y <= Profile.WATER_HEIGHT):
			clipped.append(previous.lerp(point, (Profile.WATER_HEIGHT-previous.y)/(point.y-previous.y)))
		if inside:
			clipped.append(point)
		previous = point
	for index in range(1, clipped.size()-1):
		for point in [clipped[0], clipped[index], clipped[index+1]]:
			surface.set_normal(Vector3.UP)
			surface.set_color(Color(clampf((Profile.WATER_HEIGHT-point.y)/4.0,0,1),0,0,1))
			surface.add_vertex(Vector3(point.x, Profile.WATER_HEIGHT, point.z))

func _build_fishing_shores() -> void:
	var shores := Node3D.new()
	shores.name = "LakeFishingShores"
	add_child(shores)
	for spot in Profile.LAKE_FISHING_SPOTS:
		var shore := Marker3D.new()
		shore.name = spot.id
		shore.position = Vector3(spot.shore.x, Profile.surface_height(spot.shore.x,spot.shore.y), spot.shore.y)
		shores.add_child(shore)
		shore.add_to_group("farm3d_fishing_shores")
		shore.set_meta("water_body_id", "south_lake")
		var target := Marker3D.new()
		target.name = "CastTarget"
		shore.add_child(target)
		target.global_position = Vector3(spot.water.x, Profile.WATER_HEIGHT, spot.water.y)
		shore.look_at(Vector3(target.global_position.x,shore.global_position.y,target.global_position.z))
		# Set after rotation so the cast target keeps its authored world position.
		target.global_position = Vector3(spot.water.x, Profile.WATER_HEIGHT, spot.water.y)

func _build_bridge() -> void:
	var bridge := Node3D.new()
	bridge.name = "RiverBridge"
	add_child(bridge)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("927048")
	wood.roughness = .9
	var center := Profile.river_x(Profile.BRIDGE_Z)
	# Sloped landings meet the banks at ground level, avoiding a step at the first plank.
	for side in [-1,1]:
		var bank_x: float = center+side*9.2
		var deck_x: float = center+side*8.0
		var a := Vector3(bank_x,Profile.surface_height(bank_x,Profile.BRIDGE_Z)-.02,Profile.BRIDGE_Z)
		var b := Vector3(deck_x,Profile.bridge_height(deck_x)+.08,Profile.BRIDGE_Z)
		if side == 1:
			var swap := a
			a = b
			b = swap
		var ramp := MeshInstance3D.new()
		var ramp_mesh := BoxMesh.new()
		ramp_mesh.size = Vector3(a.distance_to(b)+.05,.12,2.3)
		ramp.mesh = ramp_mesh
		ramp.material_override = wood
		ramp.position = (a+b)*.5-Vector3.UP*.06
		ramp.rotation.z = atan2(b.y-a.y,b.x-a.x)
		bridge.add_child(ramp)
		var ramp_body := StaticBody3D.new()
		ramp_body.collision_layer = 1
		var ramp_collision := CollisionShape3D.new()
		var ramp_shape := BoxShape3D.new()
		ramp_shape.size = ramp_mesh.size
		ramp_collision.shape = ramp_shape
		ramp_body.add_child(ramp_collision)
		ramp.add_child(ramp_body)
	for index in 41:
		var x := center-8.0+index*.4
		var arch := Profile.bridge_height(x)
		var plank := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.395,.16,2.3)
		plank.mesh = mesh
		plank.material_override = wood
		plank.position = Vector3(x,arch,Profile.BRIDGE_Z)
		plank.rotation.z = atan2(Profile.bridge_height(x+.2)-Profile.bridge_height(x-.2),.4)
		bridge.add_child(plank)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		collision.shape = shape
		body.add_child(collision)
		plank.add_child(body)
		if index % 4 == 0:
			for side in [-1,1]:
				var post := MeshInstance3D.new()
				var post_mesh := BoxMesh.new()
				post_mesh.size = Vector3(.10,.85,.10)
				post.mesh = post_mesh
				post.material_override = wood
				post.position = Vector3(x,arch+.38,Profile.BRIDGE_Z+side*1.10)
				bridge.add_child(post)
				if index < 40:
					var next_x := x+1.6
					var a := Vector3(x,arch+.72,Profile.BRIDGE_Z+side*1.10)
					var b := Vector3(next_x,Profile.bridge_height(next_x)+.72,a.z)
					var rail := MeshInstance3D.new()
					var rail_mesh := BoxMesh.new()
					rail_mesh.size = Vector3(a.distance_to(b),.09,.09)
					rail.mesh = rail_mesh
					rail.material_override = wood
					rail.position = (a+b)*.5
					rail.rotation.z = atan2(b.y-a.y,b.x-a.x)
					bridge.add_child(rail)
					var rail_body := StaticBody3D.new()
					rail_body.collision_layer = 1
					var rail_collision := CollisionShape3D.new()
					var rail_shape := BoxShape3D.new()
					rail_shape.size = Vector3(rail_mesh.size.x,.8,.10)
					rail_collision.position.y = -.35
					rail_collision.shape = rail_shape
					rail_body.add_child(rail_collision)
					rail.add_child(rail_body)

func _build_skirt() -> void:
	# Close the outer mesh in overview instead of exposing a paper-thin edge.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Profile.WORLD_MIN, Vector2(Profile.WORLD_MAX.x,Profile.WORLD_MIN.y), Profile.WORLD_MAX, Vector2(Profile.WORLD_MIN.x,Profile.WORLD_MAX.y)]
	for side in 4:
		var start: Vector2 = corners[side]
		var end: Vector2 = corners[(side+1)%4]
		var direction := (end-start).normalized()
		for offset in int(start.distance_to(end)):
			var a := start + direction*offset
			var b := a + direction
			var points := [Vector3(a.x,Profile.height_at(a.x,a.y),a.y),Vector3(b.x,Profile.height_at(b.x,b.y),b.y),Vector3(a.x,-8,a.y),Vector3(b.x,-8,b.y)]
			for index in [0,2,3,0,3,1]:
				surface.add_vertex(points[index])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "EarthSides"
	mesh.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("71634e")
	material.roughness = 1
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	add_child(mesh)

func _build_trees() -> void:
	var trees := Node3D.new()
	trees.name = "RegionalOaks"
	add_child(trees)
	for i in Profile.TREES.size():
		var p: Vector2 = Profile.TREES[i]
		var oak := Oak.instantiate() as Node3D
		oak.position = Vector3(p.x,Profile.height_at(p.x,p.y)-.04,p.y)
		oak.scale = Vector3.ONE*(.68+.08*(i%4))
		oak.rotation.y = i*2.399
		trees.add_child(oak)

func _build_boundaries() -> void:
	var body := StaticBody3D.new()
	body.name = "MapBoundary"
	# Player-only boundary: overview picking and the camera must see through it.
	body.collision_layer = 16
	add_child(body)
	var center := (Profile.WORLD_MIN + Profile.WORLD_MAX) * .5
	for side in 4:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1,100,Profile.WORLD_SIZE.y+2) if side < 2 else Vector3(Profile.WORLD_SIZE.x+2,100,1)
		collision.shape = shape
		collision.position = Vector3(Profile.WORLD_MIN.x if side==0 else Profile.WORLD_MAX.x,35,center.y) if side<2 else Vector3(center.x,35,Profile.WORLD_MIN.y if side==2 else Profile.WORLD_MAX.y)
		body.add_child(collision)
