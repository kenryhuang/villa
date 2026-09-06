extends Node3D

## Native, editable mesh geometry: segmented bamboo rod, reel, guides, line,
## float and fish. The existing farmer skeleton receives two-arm fishing poses.
const FISH_COLORS := {"creek_crucian": Color("b5c1b0"), "river_perch": Color("87a276"), "carp": Color("cb914a"), "rainbow_trout": Color("bba3ba"), "night_catfish": Color("77899b")}
var rod: Node3D
var bobber: Node3D
var fish: Node3D
var splash: MeshInstance3D
var bite_label: Label3D
var tip_world := Vector3.ZERO
var float_world := Vector3.ZERO
var _player: Farm3DPlayer
var _skeleton: Skeleton3D
var _rod_segments: Array[MeshInstance3D] = []
var _guides: Array[MeshInstance3D] = []
var _line: Array[MeshInstance3D] = []
var _fish_material: StandardMaterial3D
var _rest_global: Dictionary = {}
var _reel_handle: Node3D

func configure(player: Farm3DPlayer) -> void:
	_player = player
	var skeletons := player.find_children("*","Skeleton3D",true,false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0]
		for i in _skeleton.get_bone_count():
			_rest_global[i] = _skeleton.get_bone_global_rest(i)
	_build_rod()
	_build_float()
	_build_fish()
	var line_material := _material(Color("e9e4c4"))
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 28:
		_line.append(_cylinder(self,"Line_%02d" % i,.007,.007,1,line_material))
	splash = _torus(self,"WaterRipple",.34,.36,_material(Color("b8eee3")))
	bite_label = Label3D.new()
	bite_label.name = "BitePrompt"
	bite_label.text = "咬钩！"
	bite_label.font_size = 64
	bite_label.pixel_size = .008
	bite_label.modulate = Color("ffe59a")
	bite_label.outline_size = 12
	bite_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(bite_label)
	hide()

func set_equipped(enabled: bool) -> void:
	visible = enabled
	if not is_instance_valid(_player):
		return
	if enabled:
		if _player._animation_player != null:
			_player._animation_player.stop()
		if _skeleton != null:
			_skeleton.reset_bone_poses()
	else:
		if is_instance_valid(_skeleton):
			_skeleton.reset_bone_poses()
		_player.play_motion_animation(false)

func update_pose(state: String, elapsed: float, duration: float, water: Vector3, item_id: String) -> void:
	var t := clampf(elapsed/maxf(duration,.001),0,1)
	var angle := .46
	var bend := .04
	var grip := Vector3(.24,1.15,.40)
	var lean := 0.0
	match state:
		"CASTING":
			if t < .35:
				angle = lerpf(.46,2.15,smoothstep(0,.35,t))
			else:
				angle = lerpf(2.15,.40,smoothstep(.35,.72,t))
			grip.y += .15*sin(t*PI)
			lean = -.12*sin(t*TAU)
			bend = .10*sin(t*PI)
		"BITE":
			bend = .30+.06*sin(elapsed*22)
			angle = .40+.035*sin(elapsed*15)
		"REELING":
			angle = lerpf(.42,1.25,smoothstep(0,.32,t))-.07*sin(t*PI*5)
			bend = .38*(1-t)+.08
			grip.y += .12
			lean = -.13*sin(t*PI)
		"LANDING":
			angle = lerpf(1.25,.94,t)
			grip.y += .12*(1-t)
		"RECOVERING": angle = lerpf(.6,.95,sin(t*PI))
	rod.global_transform = _player.global_transform * Transform3D(Basis(Quaternion(Vector3.UP,Vector3(0,sin(angle),cos(angle)))),grip)
	for i in _rod_segments.size():
		var a := _rod_point(float(i)/_rod_segments.size(),bend)
		var b := _rod_point(float(i+1)/_rod_segments.size(),bend)
		_segment(_rod_segments[i],a,b)
	for i in _guides.size():
		_guides[i].position = _rod_point(float(i+1)/_guides.size(),bend)+Vector3(0,0,.018)
	tip_world = rod.to_global(_rod_point(1,bend))
	_reel_handle.rotation.x = elapsed*15 if state == "REELING" else 0
	float_world = water+Vector3.UP*(.035*sin(elapsed*3))
	if state == "READY":
		float_world = tip_world-Vector3.UP*.55
	elif state == "CASTING":
		var flight := smoothstep(.38,1,t)
		float_world = (tip_world-Vector3.UP*.35).lerp(water,flight)+Vector3.UP*(sin(flight*PI)*1.7)
	elif state == "BITE":
		float_world = water+Vector3.UP*(-.13+.12*sin(elapsed*18))
	elif state == "REELING":
		float_world = water.lerp(_player.to_global(Vector3(.08,1.3,.75)),smoothstep(0,1,t))+Vector3.UP*(sin(t*PI)*1.4)
	elif state == "LANDING":
		float_world = _player.to_global(Vector3(.08,1.3,.75).lerp(Vector3(-.24,1.1,.38),smoothstep(0,1,t)))
	elif state == "RECOVERING":
		float_world = water.lerp(tip_world-Vector3.UP*.55,smoothstep(0,1,t))+Vector3.UP*sin(t*PI)
	bobber.global_position = float_world
	bobber.rotation.z = .16*sin(elapsed*16) if state == "BITE" else .03*sin(elapsed*3)
	bobber.visible = state not in ["REELING","LANDING"]
	_draw_line(tip_world,float_world,.04 if state in ["BITE","REELING"] else .15)
	fish.visible = state in ["REELING","LANDING"]
	if fish.visible:
		_fish_material.albedo_color = FISH_COLORS.get(item_id,Color("b5c1b0"))
		fish.global_position = float_world-Vector3.UP*.27
		fish.global_rotation = Vector3(-1.35+.12*sin(elapsed*18),sin(elapsed*20)*.5,.22*sin(elapsed*26))
		fish.scale = Vector3.ONE*(1.0-.35*t if state == "LANDING" else 1.0)
	splash.visible = state in ["BITE","REELING"] or (state == "CASTING" and t > .9)
	splash.global_position = water+Vector3.UP*.015
	splash.scale = Vector3.ONE*(.7+fmod(elapsed*2.4,1.5))
	bite_label.visible = state == "BITE"
	bite_label.global_position = water+Vector3.UP*.8
	_pose_arms(grip,lean,state,elapsed,t)

func _pose_arms(grip: Vector3, lean: float, state: String, elapsed: float, t: float) -> void:
	if _skeleton == null:
		return
	var spine := _skeleton.find_bone("spine")
	_skeleton.set_bone_pose_rotation(spine,Quaternion(Vector3.RIGHT,lean))
	var left := Vector3(-.14,1.08,.40)
	if state == "REELING":
		left += Vector3(.02*sin(elapsed*15),.035*cos(elapsed*15),0)
	if state == "LANDING":
		left = left.lerp(Vector3(-.24,1.1,.38),t)
	_aim_arm("R",grip)
	_aim_arm("L",left)

func _aim_arm(suffix: String, hand_in_player: Vector3) -> void:
	var upper := _skeleton.find_bone("upper_arm."+suffix)
	var fore := _skeleton.find_bone("forearm."+suffix)
	var shoulder := _skeleton.get_bone_global_pose(upper).origin
	var hand := _skeleton.to_local(_player.to_global(hand_in_player))
	var upper_length := _skeleton.get_bone_rest(fore).origin.length()
	var lower_length := .235
	var reach := hand-shoulder
	var distance := clampf(reach.length(),.08,upper_length+lower_length-.005)
	var direction := reach.normalized()
	var along := (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2*distance)
	var outside := Vector3(1 if suffix == "R" else -1,-.5,0)
	var elbow_direction := (outside-direction*outside.dot(direction)).normalized()
	var elbow := shoulder+direction*along+elbow_direction*sqrt(maxf(0,upper_length*upper_length-along*along))
	_aim_bone(upper,elbow-shoulder)
	_aim_bone(fore,hand-elbow)

func _aim_bone(index: int, direction: Vector3) -> void:
	var rest: Transform3D = _rest_global[index]
	var global_basis := Basis(Quaternion(rest.basis.y.normalized(),direction.normalized()))*rest.basis
	var parent_basis := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(index)).basis
	_skeleton.set_bone_pose_rotation(index,(parent_basis.inverse()*global_basis).get_rotation_quaternion())

func _rod_point(t: float, bend: float) -> Vector3:
	return Vector3(0,t*2.35,bend*t*t)

func _draw_line(start: Vector3, end: Vector3, sag: float) -> void:
	for i in _line.size():
		var a := float(i)/_line.size()
		var b := float(i+1)/_line.size()
		_segment(_line[i],to_local(start.lerp(end,a)-Vector3.UP*(sin(a*PI)*sag)),to_local(start.lerp(end,b)-Vector3.UP*(sin(b*PI)*sag)))

func _build_rod() -> void:
	rod = Node3D.new()
	rod.name = "BambooRod"
	add_child(rod)
	var bamboo := _material(Color("bf9854"))
	var dark := _material(Color("443b30"))
	var metal := _material(Color("b4bfc0"))
	metal.metallic = .7
	for i in 12:
		var radius := lerpf(.025,.007,float(i)/12)
		_rod_segments.append(_cylinder(rod,"RodSection_%02d" % i,radius,radius*.93,1,bamboo))
	var grip := _cylinder(rod,"CorkGrip",.043,.04,.30,dark)
	grip.position.y = .08
	for i in 4:
		_guides.append(_torus(rod,"LineGuide_%d" % i,.025,.035,metal))
	var reel := _cylinder(rod,"ReelSpool",.09,.09,.10,metal)
	reel.position = Vector3(.06,.08,-.09)
	reel.rotation.z = PI*.5
	_reel_handle = Node3D.new()
	_reel_handle.name = "ReelCrank"
	_reel_handle.position = reel.position+Vector3(.07,0,0)
	rod.add_child(_reel_handle)
	var crank := _cylinder(_reel_handle,"Crank",.012,.012,.12,metal)
	crank.position.y = -.045
	var knob := _sphere(_reel_handle,"Knob",Vector3(.045,.045,.045),dark)
	knob.position = Vector3(0,-.11,0)

func _build_float() -> void:
	bobber = Node3D.new()
	bobber.name = "Float"
	add_child(bobber)
	_sphere(bobber,"FloatBody",Vector3(.12,.18,.12),_material(Color("f5e5be")))
	var cap := _sphere(bobber,"RedTip",Vector3(.08,.10,.08),_material(Color("e3573e")))
	cap.position.y = .10
	var stem := _cylinder(bobber,"FloatStem",.012,.012,.30,_material(Color("493e30")))
	stem.position.y = -.04

func _build_fish() -> void:
	fish = Node3D.new()
	fish.name = "CaughtFish"
	add_child(fish)
	_fish_material = _material(Color("b5c1b0"))
	_sphere(fish,"Body",Vector3(.18,.27,.58),_fish_material)
	var belly := _sphere(fish,"Belly",Vector3(.15,.13,.45),_material(Color("e4ddbf")))
	belly.position.y = -.06
	var fin_material := _material(Color("80764e"))
	fin_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fin("Tail",[Vector3(0,0,-.22),Vector3(0,.18,-.43),Vector3(0,-.18,-.43)],fin_material)
	_fin("Dorsal",[Vector3(0,.07,-.12),Vector3(0,.24,-.08),Vector3(0,.1,.18)],fin_material)
	for side in [-1,1]:
		var eye := _sphere(fish,"Eye",Vector3(.025,.025,.025),_material(Color("18232b")))
		eye.position = Vector3(side*.072,.04,.21)
		_fin("SideFin",[Vector3(side*.07,0,.08),Vector3(side*.22,-.08,-.06),Vector3(side*.08,-.06,-.10)],fin_material)

func _fin(title: String, vertices: Array, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices:
		surface.add_vertex(vertex)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = surface.commit()
	instance.material_override = material
	fish.add_child(instance)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .7
	return material

func _cylinder(parent: Node3D, title: String, bottom: float, top: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 8
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _sphere(parent: Node3D, title: String, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 16
	mesh.rings = 8
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = mesh
	instance.scale = dimensions
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _torus(parent: Node3D, title: String, inner: float, outer: float, material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mesh.ring_segments = 6
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _segment(instance: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var direction := b-a
	instance.position = (a+b)*.5
	instance.quaternion = Quaternion(Vector3.UP,direction.normalized()) if direction.length_squared() > .000001 else Quaternion.IDENTITY
	instance.scale = Vector3(1,maxf(.001,direction.length()),1)
