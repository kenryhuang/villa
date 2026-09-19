extends Node3D

## Editable, metre-scale stone well. Fits one grid cell; no image textures required.
func _init() -> void:
	var stone := material("a2a496")
	var dark_stone := material("818779")
	var wood := material("775034")
	var warm := material("b98c57")
	var iron := material("384b49",.65)
	var rope := material("b7a477")
	var foundation := group("Foundation",self)
	# Staggered blocks leave a genuine open shaft instead of a solid cylinder.
	for level in 3:
		for i in 12:
			var angle := TAU*(i+(.5 if level%2 else 0.0))/12.0
			var block := box(foundation,Vector3(sin(angle)*.35,.1+level*.19,cos(angle)*.35),Vector3(.195,.175,.14),stone if (i+level)%3 else dark_stone)
			block.rotation.y=angle
	var walls := group("Walls",self)
	for i in 12:
		var angle := TAU*i/12.0
		var cap := box(walls,Vector3(sin(angle)*.36,.65,cos(angle)*.36),Vector3(.205,.13,.19),stone)
		cap.rotation.y=angle
	cylinder(walls,Vector3(0,.15,0),.265,.02,material("213f43"))
	cylinder(walls,Vector3(0,.22,0),.255,.012,material("4d999d",.2))
	var frame := group("Frame",self)
	for x in [-.40,.40]:
		box(frame,Vector3(x,.95,0),Vector3(.10,1.50,.11),wood)
		box(frame,Vector3(x,.34,0),Vector3(.14,.09,.145),iron)
		box(frame,Vector3(x,1.48,0),Vector3(.13,.045,.13),iron)
	beam(frame,Vector3(-.48,1.70,0),Vector3(.48,1.70,0),.105,wood)
	var roof := group("Roof",self)
	for side in [-1,1]:
		for i in 6:
			var slat := box(roof,Vector3(-.405+i*.162,1.76,side*.20),Vector3(.155,.06,.46),warm if i%2 else wood)
			slat.rotation.x=side*.35
	beam(roof,Vector3(-.5,1.84,0),Vector3(.5,1.84,0),.065,warm)
	var details := group("Details",self)
	beam(details,Vector3(-.49,1.26,0),Vector3(.53,1.26,0),.065,iron)
	var spindle := cylinder(details,Vector3(0,1.26,0),.10,.36,wood)
	spindle.rotation.z=PI/2
	for i in 10:
		var winding := cylinder(details,Vector3(-.135+i*.03,1.26,0),.104,.012,rope)
		winding.rotation.z=PI/2
	beam(details,Vector3(0,1.22,.07),Vector3(0,.76,.07),.017,rope)
	cylinder(details,Vector3(0,.79,.07),.095,.16,warm)
	for y in [.73,.85]: cylinder(details,Vector3(0,y,.07),.099,.02,iron)
	beam(details,Vector3(.51,1.26,0),Vector3(.51,1.08,0),.04,iron)
	beam(details,Vector3(.51,1.08,0),Vector3(.59,1.08,0),.045,wood)
	# The intake fitting explains the well -> pump connection.
	beam(details,Vector3(0,.30,-.14),Vector3(0,.75,-.14),.065,iron)
	beam(details,Vector3(0,.75,-.14),Vector3(0,.75,-.44),.065,iron)
	var outlet := Marker3D.new();outlet.name="Outlet";outlet.position=Vector3(0,.75,-.44);details.add_child(outlet)

func group(label: String, parent: Node) -> Node3D:
	var node := Node3D.new();node.name=label;parent.add_child(node);return node

func material(color: String, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new();result.albedo_color=Color(color);result.roughness=.8;result.metallic=metallic;return result

func box(parent: Node, point: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size=size;mesh.material=mat
	var node := MeshInstance3D.new();node.mesh=mesh;node.position=point;parent.add_child(node);return node

func cylinder(parent: Node, point: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=16;mesh.material=mat
	var node := MeshInstance3D.new();node.mesh=mesh;node.position=point;parent.add_child(node);return node

func beam(parent: Node, a: Vector3, b: Vector3, width: float, mat: Material) -> void:
	var node := box(parent,(a+b)*.5,Vector3(width,a.distance_to(b),width),mat)
	if a != b: node.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
