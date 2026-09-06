class_name Farm3DLandscape
extends Node3D

const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const Oak = preload("res://scenes/vegetation/painted_oak.tscn")
const CHUNK_SIZE := 16
var terrain_material: ShaderMaterial
var _heights := PackedFloat32Array()

func _ready() -> void:
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = preload("res://assets/terrain/landscape.gdshader")
	terrain_material.set_shader_parameter("grass_texture",preload("res://assets/terrain/grass-seamless-blended.png"))
	_heights.resize(161*161)
	for z in 161:
		for x in 161:
			_heights[z*161+x] = Profile.height_at(x-80,z-80)
	for z in range(-80,80,CHUNK_SIZE):
		for x in range(-80,80,CHUNK_SIZE):
			_build_chunk(x,z)
	_build_river()
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
	return _heights[clampi(z+80,0,160)*161+clampi(x+80,0,160)]

func _build_river() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-80,80):
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
	for side in 4:
		for offset in range(-80,80):
			var a := Vector2(offset,-80) if side == 0 else Vector2(80,offset) if side == 1 else Vector2(-offset,80) if side == 2 else Vector2(-80,-offset)
			var b := a+Vector2.RIGHT if side == 0 else a+Vector2.DOWN if side == 1 else a+Vector2.LEFT if side == 2 else a+Vector2.UP
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
	for side in 4:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1,100,162) if side < 2 else Vector3(162,100,1)
		collision.shape = shape
		collision.position = Vector3(-80 if side==0 else 80,35,0) if side<2 else Vector3(0,35,-80 if side==2 else 80)
		body.add_child(collision)
