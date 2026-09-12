extends "res://scripts/farm3d/windmill_outputs.gd"

func configure_for_building(_footprint: Vector2i, _building_id: String) -> void:
	_slots = [Vector3(.92,.08,1.43)]

func _make_pile(id: String, count: int) -> Area3D:
	var pile := Area3D.new()
	pile.name = "Output_"+id
	pile.collision_mask = 0
	pile.set_meta("production_output",id)
	add_child(pile)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.52,.46,.48)
	collider.shape = shape
	collider.position.y = .20
	pile.add_child(collider)
	var basket := CylinderMesh.new()
	basket.top_radius = .235
	basket.bottom_radius = .18
	basket.height = .12
	_mesh(pile,basket,Vector3(0,.06,0),Color("a97b43"))
	var straw := CylinderMesh.new()
	straw.top_radius = .21
	straw.bottom_radius = .21
	straw.height = .02
	_mesh(pile,straw,Vector3(0,.128,0),Color("d1b571"))
	var rim := TorusMesh.new()
	rim.inner_radius = .205
	rim.outer_radius = .237
	_mesh(pile,rim,Vector3(0,.14,0),Color("8b6239"))
	for i in mini(count,6):
		var egg := SphereMesh.new()
		egg.radius = .055
		egg.height = .145
		egg.radial_segments = 12
		egg.rings = 6
		_mesh(pile,egg,Vector3((i%3-1)*.108,.19,(i/3-.5)*.12),Color("f6e6c7"))
	var label := Label3D.new()
	label.text = "鸡蛋 ×%d" % count
	label.position.y = .63
	label.font_size = 25
	label.pixel_size = .0028
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pile.add_child(label)
	return pile
