extends Node3D

## Native, staged 3D geometry; the original production system owns all yields.
var _materials := {}
var bees: Array[Node3D] = []
var honey: Node3D

func _init() -> void:
	var foundation := _group("Foundation")
	var frame := _group("Frame")
	var walls := _group("Walls")
	var roof := _group("Roof")
	var details := _group("Details")
	var swarm := _group("Bees")
	for x in [-.49, .49]:
		for z in [-.39, .39]:
			_box(foundation, Vector3(x,.12,z), Vector3(.24,.24,.24), "857b68")
			_box(frame, Vector3(x,.28,z), Vector3(.13,.36,.13), "755039")
	_box(frame, Vector3(0,.36,0), Vector3(1.24,.12,1.05), "98683e")
	# Three stacked supers, with inset seams and staggered wooden joints.
	for tier in 3:
		var y := .57 + tier * .29
		_box(walls, Vector3(0,y,0), Vector3(1.06,.265,.86), ["d8a155","e7b76d","c89553"][tier])
		for x in [-.51,.51]:
			for joint in 3:
				_box(walls, Vector3(x,y-.085+joint*.08,.438), Vector3(.085,.047,.022), "ad743c")
		# Fine grain follows the planks, avoiding a flat plastic appearance.
		for line in 3:
			_box(walls, Vector3(-.09+line*.085,y-.07+line*.052,.434), Vector3(.58-line*.08,.007,.006), "c18a49")
		for side in [-1,1]:
			_box(details, Vector3(side*.546,y+.015,0), Vector3(.032,.07,.26), "9b6c3b")
			_box(details, Vector3(side*.573,y-.012,0), Vector3(.037,.032,.20), "555c4f")
	_box(details, Vector3(0,.435,.448), Vector3(.52,.056,.026), "49392b")
	_box(details, Vector3(0,.397,.60), Vector3(.77,.05,.40), "b38046")
	for x in [-.27,0,.27]:
		_box(details, Vector3(x,.424,.59), Vector3(.009,.008,.31), "8c643d")
	# Painted green pitched roof and copper ridge.
	for side in [-1,1]:
		for slat in 5:
			var tile := _box(roof, Vector3(side*.355,1.46,-.48+slat*.24), Vector3(.84,.09,.225), ["647958","728564","58704f"][slat%3])
			tile.rotation.z = side * -.35
	_box(roof, Vector3(0,1.625,0), Vector3(.10,.07,1.22), "a47843")
	for z in [-.59,.59]:
		for side in [-1,1]:
			var trim := _box(roof, Vector3(side*.355,1.405,z), Vector3(.85,.075,.07), "40563e")
			trim.rotation.z = side * -.35
	# Honeycomb badge on the front; real six-sided geometry.
	var badge := _cylinder(details, Vector3(0,1.10,.454), .125,.025,"f1ce75",6)
	badge.rotation.x = PI / 2
	for x in [-.047,.047]:
		var cell := _cylinder(details, Vector3(x,1.10,.474),.041,.015,"aa7133",6)
		cell.rotation.x = PI / 2
	_box(details, Vector3(.79,.32,.20),Vector3(.38,.065,.55),"986d44")
	for z in [-.01,.42]:
		_box(details,Vector3(.79,.17,z),Vector3(.25,.3,.06),"785637")
	_cylinder(details,Vector3(.79,.43,.19),.13,.17,"715336")
	honey = _cylinder(details,Vector3(.79,.465,.19),.115,.13,"e6a934")
	honey.name = "HoneyStore"
	_cylinder(details,Vector3(.79,.55,.19),.14,.045,"d3bc85")
	for index in 5:
		var bee := Node3D.new()
		bee.name = "Bee%d" % index
		swarm.add_child(bee)
		_ellipsoid(bee,Vector3.ZERO,Vector3(.09,.075,.14),"efbc49")
		for z in [-.018,.032]:
			var band := _cylinder(bee,Vector3(0,0,z),.043,.021,"433b2c",10)
			band.rotation.x = PI/2
		_ellipsoid(bee,Vector3(0,.008,-.069),Vector3(.067,.062,.059),"403a2c")
		for side in [-1,1]:
			var wing := _ellipsoid(bee,Vector3(side*.051,.04,-.013),Vector3(.09,.012,.045),"dce7d7")
			wing.name = "LeftWing" if side < 0 else "RightWing"
		var pollen := _ellipsoid(bee,Vector3(0,-.039,.022),Vector3(.055,.04,.05),"e4a32a")
		pollen.name = "Pollen"
		bee.hide()
		bees.append(bee)

func _group(id: String) -> Node3D:
	var result := Node3D.new()
	result.name = id
	add_child(result)
	return result

func _mesh(parent: Node3D, position_value: Vector3, mesh: Mesh, color: String) -> MeshInstance3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .88
		_materials[color] = material
	mesh.material = _materials[color]
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.position = position_value
	parent.add_child(result)
	return result

func _box(parent: Node3D, point: Vector3, dimensions: Vector3, color: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(parent,point,mesh,color)

func _cylinder(parent: Node3D, point: Vector3, radius: float, height: float, color: String, sides := 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	return _mesh(parent,point,mesh,color)

func _ellipsoid(parent: Node3D, point: Vector3, dimensions: Vector3, color: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 10
	mesh.rings = 5
	var result := _mesh(parent,point,mesh,color)
	result.scale = dimensions
	return result
