extends "res://scripts/farm3d/windmill_yard.gd"

func configure(_size: Vector2i, _style: String, _offset: Vector3) -> bool:
	clear_immediately()
	_box(Vector3(4,.08,4),Vector3(0,-.02,0),Color("978c72"))
	for x in [-1.94,1.94]:
		for z in [-1.9,0,1.85]:
			_box(Vector3(.085,.58,.085),Vector3(x,.28,z),Color("927345"))
		for y in [.23,.46]:
			_box(Vector3(.055,.055,3.75),Vector3(x,y,0),Color("ad8957"))
	# Two low shelves provide eight display positions; production controls capacity.
	for x in [-1.07,1.07]:
		_box(Vector3(1.75,.08,.75),Vector3(x,.09,1.56),Color("84653e"))
	_apply()
	return true

func get_output_slots() -> Array[Vector3]:
	return [Vector3(-1.5,.14,1.35),Vector3(-1,.14,1.35),Vector3(-.5,.14,1.35),Vector3(.5,.14,1.35),Vector3(1,.14,1.35),Vector3(1.5,.14,1.35),Vector3(-1.25,.14,1.85),Vector3(1.25,.14,1.85)]
