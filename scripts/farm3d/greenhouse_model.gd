extends Node3D

## Editable native mesh source. Eight cold frames align with get_greenhouse_cells.
const BED_CENTERS := [Vector3(-1,0,-2),Vector3(0,0,-2),Vector3(1,0,-2),Vector3(-2,0,0),Vector3(2,0,0),Vector3(-1,0,2),Vector3(0,0,2),Vector3(1,0,2)]
var materials := {}

func _init() -> void:
	var base := _group("Foundation")
	var frame := _group("Frame")
	var walls := _group("Walls")
	var roof := _group("Roof")
	var details := _group("Details")
	_box(base,Vector3(0,.06,0),Vector3(2.82,.12,2.82),"8c8874")
	# Cut limestone blocks, staggered joints and a warm brick floor.
	for side in [-1,1]:
		for i in 7:
			_box(base,Vector3(side*1.34,.20,-1.17+i*.39),Vector3(.18,.27,.37),["a6a18b","b6ad96","9d9986"][i%3])
			if i not in [2,3,4] or side < 0:
				_box(base,Vector3(-1.17+i*.39,.20,side*1.34),Vector3(.37,.27,.18),["b1a891","969781","aaa58d"][i%3])
	for z in 8:
		for x in 7:
			_box(base,Vector3(-1.17+x*.39,.135,-1.19+z*.34),Vector3(.375,.022,.322),["ba977b","c4a588","ac8d73"][(x+z)%3])
	# Sage painted timber / iron mullions, with a tall ridge and small copper finials.
	for side in [-1,1]:
		for z in [-1.30,-.65,0,.65,1.30]:
			_box(frame,Vector3(side*1.30,1.12,z),Vector3(.065,1.72,.065),"526e5a")
		for y in [.37,1.05,1.95]:
			_box(frame,Vector3(side*1.30,y,0),Vector3(.075,.065,2.67),"66816a")
		for x in [-1.30,-.65,0,.65,1.30]:
			if x == 0 and side > 0: continue
			_box(frame,Vector3(x,1.12,side*1.30),Vector3(.065,1.72,.065),"526e5a")
		_box(frame,Vector3(0,1.95,side*1.30),Vector3(2.67,.085,.075),"405e4b")
		for z in [-1.35,-.675,0,.675,1.35]:
			_beam(roof,Vector3(0,2.92,z),Vector3(side*1.43,1.92,z),.065,"476750")
		for fraction in [.35,.7]:
			_box(roof,Vector3(side*1.43*fraction,2.92-fraction,0),Vector3(.048,.048,2.78),"6b8367")
		for z in 4:
			var pane := _box(roof,Vector3(side*.715,2.42,-1.0125+z*.675),Vector3(1.72,.018,.625),"glass")
			pane.rotation.z = -side*atan2(1.0,1.43)
		for z in 4:
			for row in 2:
				if side > 0 and z == 3: continue # Side door avoids the south growing beds.
				_box(walls,Vector3(side*1.297,.70+row*.81,-.975+z*.65),Vector3(.015,.70,.585),"glass")
		for x in [-.98,.98]:
			for row in 2:
				_box(walls,Vector3(x,.70+row*.81,side*1.297),Vector3(.575,.70,.015),"glass")
		_gable(walls,side*1.297)
		# Narrow gutters and external downpipes, clear of the crop beds.
		_box(details,Vector3(side*1.43,1.91,0),Vector3(.09,.075,2.95),"7a624b")
		_box(details,Vector3(side*1.40,1.02,-1.41),Vector3(.047,1.80,.047),"766749")
	_box(roof,Vector3(0,2.94,0),Vector3(.10,.10,2.97),"8e724c")
	for z in [-1.48,1.48]:
		_ball(details,Vector3(0,3.06,z),Vector3(.14,.20,.14),"ad8756")
		_beam(details,Vector3(0,2.96,z),Vector3(0,3.15,z),.035,"735b41")
	# South observation window; the service door is on the clear southeast corner.
	for x in [-.50,.50]:
		_box(walls,Vector3(x,1.1,1.32),Vector3(.065,1.77,.07),"405e4b")
	for y in [.28,.91,1.89]:
		_box(walls,Vector3(0,y,1.32),Vector3(1.05,.055,.07),"405e4b")
	_box(walls,Vector3(0,1.40,1.32),Vector3(.90,.88,.018),"glass")
	for x in 5:
		_box(walls,Vector3(-.39+x*.195,.58,1.32),Vector3(.18,.55,.04),"779075")
	for x in [-.32,.32]:
		for y in [.70,1.51]: _box(walls,Vector3(x,y,-1.297),Vector3(.57,.70,.015),"glass")
	_box(walls,Vector3(1.45,.18,.975),Vector3(.32,.12,.72),"b4aa90")
	for y in [.3,.91,1.89]: _box(walls,Vector3(1.32,y,.975),Vector3(.07,.055,.65),"405e4b")
	_box(walls,Vector3(1.32,1.40,.975),Vector3(.018,.88,.575),"glass")
	_box(walls,Vector3(1.32,.6,.975),Vector3(.04,.57,.57),"779075")
	_box(details,Vector3(1.38,1.03,1.16),Vector3(.045,.17,.045),"c9a35e")
	_box(details,Vector3(0,2.14,1.37),Vector3(.66,.20,.045),"c1ab7d")
	# Sprout emblem; no text baked into the mesh.
	_beam(details,Vector3(0,2.07,1.403),Vector3(0,2.22,1.403),.018,"4d694d")
	for side in [-1,1]:
		var leaf := _ball(details,Vector3(side*.052,2.16,1.404),Vector3(.12,.048,.018),"4d694d")
		leaf.rotation.z = side*.45
	# Potting benches are furnishings, not fake harvestable crops.
	for side in [-1,1]:
		_box(details,Vector3(side*.94,.85,-.16),Vector3(.51,.08,1.85),"ab855c")
		for z in [-.9,.58]:
			for x in [.75,1.12]:
				_box(details,Vector3(side*x,.48,z),Vector3(.055,.70,.055),"69523c")
		for z in [-.72,-.30,.12,.48]:
			_pot(details,Vector3(side*.94,.95,z))
	# Cold frames sit over the real external planting cells. Open lids leave crops visible.
	for index in BED_CENTERS.size():
		var bed := Node3D.new()
		bed.name = "ColdFrame%d" % (index+1)
		bed.position = BED_CENTERS[index]
		details.add_child(bed)
		for side in [-1,1]:
			_box(bed,Vector3(side*.46,.10,0),Vector3(.055,.20,.95),"aa8760")
			_box(bed,Vector3(0,.10,side*.46),Vector3(.91,.20,.055),"bb9870")
		var lid := Node3D.new()
		lid.name = "OpenGlassLid"
		lid.position = Vector3(0,.2,-.46)
		lid.rotation.x = -1.08
		bed.add_child(lid)
		_box(lid,Vector3(0,0,.44),Vector3(.87,.014,.85),"glass")
		for side in [-1,1]: _box(lid,Vector3(side*.45,0,.44),Vector3(.035,.035,.91),"698367")
		for z in [0,.44,.89]: _box(lid,Vector3(0,0,z),Vector3(.92,.035,.035),"698367")
		_box(bed,Vector3(.40,.40,-.13),Vector3(.016,.54,.016),"867354")
		_box(bed,Vector3(-.34,.15,.493),Vector3(.14,.07,.016),"ddc695")

func _group(id: String) -> Node3D:
	var node := Node3D.new()
	node.name = id
	add_child(node)
	return node

func _gable(parent: Node3D, z: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_material("glass"))
	for vertex in [Vector3(-1.26,1.98,z),Vector3(1.26,1.98,z),Vector3(0,2.87,z)]:
		surface.set_normal(Vector3(0,0,signf(z)))
		surface.add_vertex(vertex)
	var pane := MeshInstance3D.new()
	pane.mesh = surface.commit()
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pane)

func _material(id: String) -> StandardMaterial3D:
	if materials.has(id): return materials[id]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.58,.80,.75,.20) if id == "glass" else Color(id)
	material.roughness = .22 if id == "glass" else .83
	if id == "glass":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials[id] = material
	return material

func _mesh(parent: Node3D, point: Vector3, mesh: PrimitiveMesh, color: String) -> MeshInstance3D:
	mesh.material = _material(color)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = point
	if color == "glass": node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _box(parent: Node3D, point: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent,point,mesh,color)

func _beam(parent: Node3D, start: Vector3, end: Vector3, width: float, color: String) -> void:
	var node := _box(parent,(start+end)*.5,Vector3(width,start.distance_to(end),width),color)
	var direction := (end-start).normalized()
	node.quaternion = Quaternion(Vector3.UP,direction)

func _ball(parent: Node3D, point: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 10
	mesh.rings = 5
	var node := _mesh(parent,point,mesh,color)
	node.scale = size
	return node

func _pot(parent: Node3D, point: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = .10
	mesh.bottom_radius = .073
	mesh.height = .14
	mesh.radial_segments = 12
	_mesh(parent,point,mesh,"b77e59")
	var soil := CylinderMesh.new()
	soil.top_radius = .083
	soil.bottom_radius = .083
	soil.height = .009
	soil.radial_segments = 12
	_mesh(parent,point+Vector3.UP*.071,soil,"564b35")
