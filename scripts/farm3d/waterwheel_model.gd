extends Node3D

## Editable metre-scale geometry; +Z faces the water, X is the axle.
func _init() -> void:
	var stone := material(Color("777f78"))
	var wood := material(Color("825333"))
	var light := material(Color("bc915a"))
	var iron := material(Color("354846"),.65)
	var water := material(Color("54b4be"),.15)
	var foundation := group("Foundation",self)
	for x in [-.72,.72]:
		for level in 8:
			box(foundation,Vector3(x,-.38+level*.25,.35),Vector3(.42,.23,1.1),stone)
	var frame := group("Frame",self)
	for x in [-.73,.73]:
		beam(frame,Vector3(x,1.5,-.3),Vector3(x,1.15,2.05),.16,wood)
		beam(frame,Vector3(x,.85,.35),Vector3(x,1.15,2.05),.16,wood)
	beam(frame,Vector3(-.95,1.15,2.05),Vector3(.95,1.15,2.05),.18,iron)
	var rotor := group("Rotor",self)
	rotor.position=Vector3(0,1.15,2.05)
	for x in [-.33,.33]:
		for i in 24:
			var a := TAU*i/24.0
			var b := TAU*(i+1)/24.0
			beam(rotor,Vector3(x,cos(a),sin(a))*Vector3(1,1.14,1.14),Vector3(x,cos(b),sin(b))*Vector3(1,1.14,1.14),.105,wood)
			beam(rotor,Vector3(x,cos(a)*.98,sin(a)*.98),Vector3(x,cos(b)*.98,sin(b)*.98),.035,iron)
		for i in 8:
			var a := TAU*i/8.0
			beam(rotor,Vector3(x,0,0),Vector3(x,cos(a)*1.1,sin(a)*1.1),.09,light)
	for i in 16:
		var a := TAU*i/16.0
		var paddle := group("Bucket%d"%i,rotor)
		paddle.position=Vector3(0,cos(a)*1.10,sin(a)*1.10);paddle.rotation.x=a
		box(paddle,Vector3.ZERO,Vector3(.78,.065,.25),light)
		box(paddle,Vector3(0,.085,.10),Vector3(.78,.18,.045),wood)
		for x in [-.36,.36]:box(paddle,Vector3(x,.07,0),Vector3(.05,.16,.24),wood)
	var walls := group("Walls",self)
	# Receiving cistern and gravity outlet; service side is on dry land.
	for x in [-.64,.64]:beam(walls,Vector3(x,0,-.65),Vector3(x,1.9,-.65),.12,wood)
	box(walls,Vector3(0,1.75,-.65),Vector3(1.4,.10,.58),wood)
	for z in [-.94,-.36]:box(walls,Vector3(0,1.92,z),Vector3(1.4,.32,.07),light)
	for x in [-.68,.68]:box(walls,Vector3(x,1.92,-.65),Vector3(.07,.32,.62),light)
	# A shallow collecting chute joins the buckets to the receiving tank.
	beam(walls,Vector3(0,2.02,1.9),Vector3(0,1.85,-.38),.22,light)
	for x in [-.16,.16]:beam(walls,Vector3(x,2.10,1.9),Vector3(x,1.93,-.38),.07,wood)
	var roof := group("Roof",self)
	box(roof,Vector3(0,1.86,-.65),Vector3(1.27,.02,.48),water)
	beam(roof,Vector3(0,1.78,-.8),Vector3(0,1.55,-.8),.13,iron)
	beam(roof,Vector3(0,1.55,-.8),Vector3(0,1.55,-1.03),.13,iron)
	var details := group("Details",self)
	for x in [-.76,.76]:box(details,Vector3(x,1.15,2.05),Vector3(.15,.32,.30),iron)
	for i in 5:box(details,Vector3(-.49+i*.245,1.48,-.5),Vector3(.22,.08,.85),light)
	box(details,Vector3(.79,.48,-.63),Vector3(.1,.28,.25),iron)
	var outlet := Marker3D.new();outlet.name="Outlet";outlet.position=Vector3(0,1.55,-1.03);details.add_child(outlet)

func group(label: String, parent: Node) -> Node3D:
	var node := Node3D.new();node.name=label;parent.add_child(node);return node

func material(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new();result.albedo_color=color;result.roughness=.78;result.metallic=metallic;return result

func box(parent: Node, point: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size=size;mesh.material=mat
	var node := MeshInstance3D.new();node.mesh=mesh;node.position=point;parent.add_child(node);return node

func beam(parent: Node, a: Vector3, b: Vector3, width: float, mat: Material) -> void:
	var node := box(parent,(a+b)*.5,Vector3(width,a.distance_to(b),width),mat)
	node.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
