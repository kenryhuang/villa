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
var _contact_local := Vector3(0,.065,.8)
var _contact_marker: MeshInstance3D
var _aim_signature: Array = []
var _aim_updated := -1000

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
	var contact_dot := SphereMesh.new()
	contact_dot.radius = .012
	contact_dot.height = .024
	_contact_marker = Art.mesh(self,contact_dot,Vector3.ZERO,Color("c96e3d"))
	_contact_marker.hide()
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
		var guide_dot := Art.mesh(self,dot,Vector3.ZERO,Color("e5dba7"))
		guide_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(guide_dot.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		aim_dots.append(guide_dot)
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
	hide_aim()

func hide_aim() -> void:
	_aim_signature.clear()
	for dot in aim_dots:
		dot.hide()
	_contact_marker.hide()

func set_contact(ball_position: Vector3, direction: Vector3, height: float) -> void:
	var vertical := clampf(height,-1,1)*.8
	var point := ball_position-direction*Farm3DGolfBall.RADIUS*sqrt(1-vertical*vertical)+Vector3.UP*Farm3DGolfBall.RADIUS*vertical
	_contact_local = _player.to_local(point)
	_contact_marker.global_position = point
	_contact_marker.visible = _equipped

func pose(angle: float, club_index: int) -> void:
	if not _equipped:
		return
	var grip := Vector3(.12,1.04,.35)
	grip.y += absf(angle)*.08
	# Player faces the ball along local +Z; the shot travels toward local -X.
	# Raise the club to the right, then sweep left through the contact point.
	var endpoint := grip + (_contact_local-grip).rotated(Vector3.BACK,angle)
	var head_center := endpoint+Vector3(.075,.025,0).rotated(Vector3.BACK,angle)
	club.global_transform = _player.global_transform
	_segment(shaft,grip,head_center)
	_segment(grip_mesh,grip,grip.lerp(head_center,.17))
	head.position = head_center
	head.rotation = Vector3(0,0,angle)
	if club_index != _last_club:
		_last_club = club_index
		head.mesh = _head_meshes[club_index]
		(head.material_override as StandardMaterial3D).albedo_color = Color("805638") if club_index == 0 else Color("a7b6ae")
	_head_point = club.to_global(endpoint)
	if _skeleton != null:
		var spine := _skeleton.find_bone("spine")
		_skeleton.set_bone_pose_rotation(spine,Quaternion(Vector3.UP,angle*.18)*Quaternion(Vector3.RIGHT,.1))
		_aim_arm("R",grip)
		_aim_arm("L",grip+(grip-head_center).normalized()*.065)

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

func show_aim(origin: Vector3, direction: Vector3, club_index: int, power: float, contact_height := -2.0) -> void:
	var signature := [origin,direction,club_index,power,contact_height]
	var now := Time.get_ticks_msec()
	if signature == _aim_signature or (not _aim_signature.is_empty() and now-_aim_updated < 80):
		return
	_aim_signature = signature
	_aim_updated = now
	var points := Farm3DGolfBall.preview_path(origin,direction,power,club_index,contact_height)
	for i in aim_dots.size():
		var index := roundi(float(i+1)/aim_dots.size()*(points.size()-1))
		aim_dots[i].global_position = points[index]+Vector3.UP*.035
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
