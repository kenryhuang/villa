extends "res://scripts/farm3d/windmill_outputs.gd"

func _make_pile(id: String, count: int) -> Area3D:
	var pile := Area3D.new()
	pile.name = "Output_"+id
	pile.collision_mask = 0
	pile.set_meta("production_output",id)
	add_child(pile)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.43,.52,.43)
	shape.shape = box
	shape.position.y = .25
	pile.add_child(shape)
	if id in ["bread","honey_cake","grilled_fish","bouquet"]:
		var tray := CylinderMesh.new()
		tray.top_radius = .22
		tray.bottom_radius = .20
		tray.height = .04
		_mesh(pile,tray,Vector3(0,.025,0),Color("9f7d4a"))
		var food := SphereMesh.new()
		food.radius = .18
		food.height = .19
		_mesh(pile,food,Vector3(0,.13,0),{"bread":Color("d49949"),"honey_cake":Color("edbf62"),"grilled_fish":Color("b59465"),"bouquet":Color("c57183")}[id])
	else:
		var jar := CylinderMesh.new()
		jar.top_radius = .11
		jar.bottom_radius = .12
		jar.height = .27
		_mesh(pile,jar,Vector3(0,.16,0),{"fruit_jam":Color("b85c53"),"pickles":Color("91a36a"),"tomato_sauce":Color("b75b3b"),"fruit_juice":Color("d59450"),"pickled_fish":Color("aea789"),"perfume":Color("baa3bc")}.get(id,Color("c1ac83")))
		var lid := CylinderMesh.new()
		lid.top_radius = .12
		lid.bottom_radius = .12
		lid.height = .04
		_mesh(pile,lid,Vector3(0,.315,0),Color("8d704b"))
	var label := Label3D.new()
	label.text = "%s ×%d" % [GameData.get_item(id).name,count]
	label.position.y = .53
	label.font_size = 26
	label.pixel_size = .0027
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pile.add_child(label)
	return pile
