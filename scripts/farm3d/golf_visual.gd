extends Node3D

const Art = preload("res://scripts/farm3d/golf_course_visual.gd")
var ball_mesh: MeshInstance3D
var club: Node3D
var shaft: MeshInstance3D
var head: MeshInstance3D
var grip_mesh: MeshInstance3D
var marker: Label3D
var aim_dots: Array[MeshInstance3D] = []
var trail: Array[MeshInstance3D] = []
var _player: Farm3DPlayer
var _skeleton: Skeleton3D
var _rests: Dictionary = {}
var _equipped := false
var _head_point := Vector3.ZERO
var _head_meshes: Array[Mesh] = []
var _last_club := -1

func configure(player: Farm3DPlayer) -> void:
	_player = player
	var skeletons := player.find_children("*","Skeleton3D",true,false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0]
		for i in _skeleton.get_bone_count():
			_rests[i] = _skeleton.get_bone_global_rest(i)
	var sphere := SphereMesh.new()
	sphere.radius = Farm3DGolfBall.RADIUS
	sphere.height = sphere.radius*2
	ball_mesh = Art.mesh(self,sphere,Vector3.ZERO,Color("fffcec"))
	ball_mesh.name = "GolfBall"
	marker = Art.label(self,"球",Vector3.ZERO,.006)
	club = Node3D.new()
	club.name = "GolfClub"
	add_child(club)
	shaft = Art.cylinder(club,Vector3.ZERO,.012,1,Color("b7c5c0"))
	grip_mesh = Art.cylinder(club,Vector3.ZERO,.022,1,Color("374339"))
	var club_head := SphereMesh.new()
	club_head.radius = .085
	club_head.height = .11
	head = Art.mesh(club,club_head,Vector3.ZERO,Color("805638"))
	var wedge := PrismMesh.new()
	wedge.size = Vector3(.15,.10,.085)
	var putter := BoxMesh.new()
	putter.size = Vector3(.22,.055,.075)
	_head_meshes.assign([club_head,wedge,putter])
	for i in 22:
		var dot := SphereMesh.new()
		dot.radius = .032
		dot.height = .064
		aim_dots.append(Art.mesh(self,dot,Vector3.ZERO,Color("e5dba7")))
	for i in 12:
		var dot := SphereMesh.new()
		dot.radius = .025*(1-float(i)/15)
		dot.height = dot.radius*2
		trail.append(Art.mesh(self,dot,Vector3.ZERO,Color("fff6cd")))
	set_equipped(false)
	clear_trail()
	ball_mesh.hide()
	marker.hide()

func set_equipped(enabled: bool) -> void:
	if _equipped == enabled:
		club.visible = enabled
		return
	_equipped = enabled
	club.visible = enabled
	if _skeleton != null:
		_skeleton.reset_bone_poses()
	if enabled:
		if _player._animation_player != null:
			_player._animation_player.stop()
	else:
		_player.play_motion_animation(false)
	for dot in aim_dots:
		dot.hide()

func pose(angle: float, club_index: int) -> void:
	if not _equipped:
		return
	var grip := Vector3(.25,1.02,.25)
	grip.y += absf(angle)*.08
	var endpoint := Vector3(.75,.065,.25)
	endpoint = grip + (endpoint-grip).rotated(Vector3.RIGHT,angle)
	club.global_transform = _player.global_transform
	_segment(shaft,grip,endpoint)
	_segment(grip_mesh,grip,grip.lerp(endpoint,.17))
	head.position = endpoint+Vector3(0,-.015,-.105).rotated(Vector3.RIGHT,angle)
	head.rotation.x = angle
	if club_index != _last_club:
		_last_club = club_index
		head.mesh = _head_meshes[club_index]
		(head.material_override as StandardMaterial3D).albedo_color = Color("805638") if club_index == 0 else Color("a7b6ae")
	_head_point = club.to_global(endpoint)
	if _skeleton != null:
		var spine := _skeleton.find_bone("spine")
		_skeleton.set_bone_pose_rotation(spine,Quaternion(Vector3.UP,angle*.18)*Quaternion(Vector3.RIGHT,.1))
		_aim_arm("R",grip)
		_aim_arm("L",grip+Vector3(-.04,.055,0))

func update_ball(position: Vector3, moving: bool, show_marker: bool) -> void:
	ball_mesh.global_position = position
	ball_mesh.visible = true
	marker.global_position = position+Vector3.UP*.6
	marker.visible = show_marker
	if moving:
		for i in range(trail.size()-1,0,-1):
			trail[i].global_position = trail[i-1].global_position
			trail[i].visible = trail[i-1].visible
		trail[0].global_position = position
		trail[0].show()

func clear_trail() -> void:
	for item in trail:
		item.hide()

func show_aim(origin: Vector3, direction: Vector3, club_index: int, power: float) -> void:
	var velocity := Farm3DGolfBall.launch_velocity(direction,power,club_index,Farm3DGolfCourse.surface(Vector2(origin.x,origin.z)))
	var time := maxf(.1,velocity.y*2/9.8)
	for i in aim_dots.size():
		var t := float(i+1)/aim_dots.size()*time
		var p := origin+velocity*t+Vector3.DOWN*4.9*t*t
		if club_index == 2:
			p = origin+direction*float(i+1)/aim_dots.size()*velocity.length_squared()/1.1
		p.y = maxf(p.y,Art.ground(Vector2(p.x,p.z)).y+.09)
		aim_dots[i].global_position = p
		aim_dots[i].show()

func _aim_arm(suffix: String, hand_local: Vector3) -> void:
	var upper := _skeleton.find_bone("upper_arm."+suffix)
	var fore := _skeleton.find_bone("forearm."+suffix)
	var shoulder := _skeleton.get_bone_global_pose(upper).origin
	var hand := _skeleton.to_local(_player.to_global(hand_local))
	var a := _skeleton.get_bone_rest(fore).origin.length()
	var b := .235
	var direction := (hand-shoulder).normalized()
	var distance := clampf(hand.distance_to(shoulder),.08,a+b-.005)
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var outside := Vector3(1 if suffix == "R" else -1,-.5,0)
	var elbow := shoulder+direction*along+(outside-direction*outside.dot(direction)).normalized()*sqrt(maxf(0,a*a-along*along))
	_aim_bone(upper,elbow-shoulder)
	_aim_bone(fore,hand-elbow)

func _aim_bone(index: int, direction: Vector3) -> void:
	var rest: Transform3D = _rests[index]
	var basis := Basis(Quaternion(rest.basis.y.normalized(),direction.normalized()))*rest.basis
	var parent := _skeleton.get_bone_global_pose(_skeleton.get_bone_parent(index)).basis
	_skeleton.set_bone_pose_rotation(index,(parent.inverse()*basis).get_rotation_quaternion())

func _segment(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	mesh.position = (a+b)*.5
	mesh.scale.y = a.distance_to(b)
	mesh.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
