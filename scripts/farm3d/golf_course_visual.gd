extends Node3D

const Course = preload("res://scripts/farm3d/golf_course_data.gd")
const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
var entrance_body: StaticBody3D
var flags: Array[Node3D] = []
var score_label: Label3D
var market_site := Vector2.INF

func configure(session: Farm3DSession) -> void:
	for child in get_children():
		child.free()
	flags.clear()
	market_site = session.market_site
	name = "GolfCourse"
	for i in Course.HOLES.size():
		var hole: Dictionary = Course.HOLES[i]
		var flag := Node3D.new()
		flag.name = "Hole%d" % (i+1)
		flag.position = ground(hole.cup)
		add_child(flag)
		flags.append(flag)
		var cup := CylinderMesh.new()
		cup.top_radius = Course.CUP_RADIUS
		cup.bottom_radius = Course.CUP_RADIUS-.015
		cup.height = .32
		cup.cap_top = false
		var liner := mesh(flag,cup,Vector3(0,-.16,0),Color("494937"))
		(liner.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		cylinder(flag,Vector3(0,1.05,0),.018,2.4,Color("eadfc8"))
		var cloth := SurfaceTool.new()
		cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in [Vector3(0,2.25,0),Vector3(.65,2.1,.05),Vector3(0,1.93,0)]:
			cloth.add_vertex(p)
		cloth.generate_normals()
		var flag_mesh := mesh(flag,cloth.commit(),Vector3.ZERO,Color("bd704e"))
		(flag_mesh.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		label(flag,str(i+1),Vector3(.19,2.13,.06),.007)
		var tee := Node3D.new()
		tee.position = ground(hole.tee)
		add_child(tee)
		for side in [-1,1]:
			box(tee,Vector3(side*.65,.09,0),Vector3(.18,.16,.3),Color("e2d7b1"))
		label(tee,"%d  %s\nPAR 3  ·  %d 米" % [i+1,hole.name,roundi(hole.tee.distance_to(hole.cup))],Vector3(-2.6,1.0,-1.4),.0045)
		for side in [-1,1]:
			cylinder(tee,Vector3(-2.6+side*.55,.45,-1.45),.035,.9,Color("81623f"))
		box(tee,Vector3(-2.6,.96,-1.45),Vector3(1.3,.56,.10),Color("3f5740"))
	var entry := Node3D.new()
	entry.name = "ClubRack"
	entry.position = ground(Course.ENTRANCE)
	add_child(entry)
	for x in [-1.65,1.65]:
		box(entry,Vector3(x,1.25,0),Vector3(.15,2.5,.15),Color("8b6b43"))
	box(entry,Vector3(0,2.05,0),Vector3(3.5,1.0,.17),Color("3f5740"))
	box(entry,Vector3(0,2.69,0),Vector3(3.8,.17,.7),Color("a3865a"))
	label(entry,"湖西高尔夫\n点击借杆 · 三洞短场",Vector3(0,2.1,.11),.009)
	score_label = label(entry,"免费练习  ·  鼠标挥杆",Vector3(0,1.3,.12),.006)
	box(entry,Vector3(0,.18,.35),Vector3(2.8,.2,.65),Color("96774b"))
	for x in [-1.0,-.5,0,.5,1.0]:
		cylinder(entry,Vector3(x,.72,.35),.018,1.1,Color("d2d5c9"))
		box(entry,Vector3(x+.045,.18,.35),Vector3(.18,.10,.15),Color("755235"))
	entrance_body = StaticBody3D.new()
	entrance_body.collision_layer = 64
	entrance_body.collision_mask = 0
	entrance_body.set_meta("golf_entrance",true)
	entry.add_child(entrance_body)
	var shape := CollisionShape3D.new()
	var target := BoxShape3D.new()
	target.size = Vector3(3.8,2.8,.9)
	shape.shape = target
	shape.position.y = 1.3
	entrance_body.add_child(shape)
	for x in range(-164,-83,8):
		for z in [56,136]:
			var p := ground(Vector2(x,z))
			cylinder(self,p+Vector3.UP*.45,.045,.9,Color("9e8d67"))
	for z in range(64,136,8):
		for x in [-164,-84]:
			cylinder(self,ground(Vector2(x,z))+Vector3.UP*.45,.045,.9,Color("9e8d67"))
	for point in [Vector2(-161,66),Vector2(-161,113),Vector2(-118,64),Vector2(-116,97),Vector2(-87,130),Vector2(-132,133)]:
		var tree := preload("res://scenes/vegetation/painted_oak.tscn").instantiate() as Node3D
		tree.position = ground(point)
		tree.scale = Vector3.ONE*.65
		add_child(tree)
	# Drape the path over shared terrain. Skip occupied legacy cells.
	var route: Array[Vector2] = [session.market_site+Vector2(-4,3),Vector2(-32,36),Vector2(-53,61),Vector2(-75,72),Vector2(-98,64),Course.ENTRANCE]
	var path := SurfaceTool.new()
	path.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in route.size()-1:
		var a := route[i]
		var b := route[i+1]
		var count := ceili(a.distance_to(b))
		var side := (b-a).orthogonal().normalized()*.85
		for j in count:
			var p := a.lerp(b,float(j)/count)
			var q := a.lerp(b,float(j+1)/count)
			var coords := session.grid.world_to_grid(p.x,p.y)
			var cell := session.grid.get_cell(coords.x,coords.y)
			if cell != null and (cell.crop_instance != null or cell.state in [GridCell.State.FARMLAND,GridCell.State.PLANTED,GridCell.State.BUILDING]):
				continue
			for point in [p-side,q+side,q-side,p-side,p+side,q+side]:
				path.set_normal(Vector3.UP)
				path.add_vertex(ground(point)+Vector3.UP*.026)
	mesh(self,path.commit(),Vector3.ZERO,Color("c0ad80"))
	# A road sign makes the destination discoverable from the existing market.
	var sign_point := session.market_site+Vector2(-5,4)
	cylinder(self,ground(sign_point)+Vector3.UP*.65,.055,1.3,Color("896b45"))
	box(self,ground(sign_point)+Vector3.UP*1.25,Vector3(2.1,.65,.12),Color("496045"))
	label(self,"↙ 湖西高尔夫",ground(sign_point)+Vector3(0,1.25,.09),.006)

static func ground(point: Vector2) -> Vector3:
	return Vector3(point.x,Profile.surface_height(point.x,point.y),point.y)

static func mesh(parent: Node, shape: Mesh, point: Vector3, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = shape
	item.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .85
	item.material_override = material
	parent.add_child(item)
	return item

static func box(parent: Node, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent,shape,point,color)

static func cylinder(parent: Node, point: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	return mesh(parent,shape,point,color)

static func label(parent: Node, text: String, point: Vector3, pixel_size: float) -> Label3D:
	var item := Label3D.new()
	item.text = text
	item.position = point
	item.font_size = 32
	item.pixel_size = pixel_size
	item.no_depth_test = false
	item.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	item.modulate = Color("fff1cf")
	parent.add_child(item)
	return item
