extends Node3D

signal collection_requested(item_id: String)
var _slots: Array[Vector3] = []
var _piles: Dictionary = {}
var _snapshot: Dictionary = {}

func configure_for_yard(slots: Array[Vector3], _building_id: String) -> void:
	_slots = slots.duplicate()

func configure_for_building(_footprint: Vector2i, _building_id: String) -> void:
	_slots = [Vector3(-.85, .06, 1.08), Vector3(0, .06, 1.08), Vector3(.85, .06, 1.08)]

func sync_outputs(outputs: Dictionary, _capacity: int, enabled: bool) -> void:
	if _snapshot != outputs:
		clear_immediately()
		_snapshot = outputs.duplicate()
		var ids := outputs.keys()
		ids.sort()
		for i in mini(ids.size(), _slots.size()):
			var id := str(ids[i])
			if int(outputs[id]) <= 0:
				continue
			var pile := _make_pile(id, int(outputs[id]))
			pile.position = _slots[i]
			_piles[id] = pile
	visible = enabled and not _piles.is_empty()
	for pile in _piles.values():
		pile.collision_layer = 128 if enabled else 0

func get_pile_count() -> int:
	return _piles.size()

func get_item_ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(_piles.keys())
	return result

func show_collection_failure(_id: String, _reason: String) -> void:
	pass # The 3D interaction publishes the actionable reason to the HUD.

func clear_immediately() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_piles.clear()
	_snapshot.clear()

func _make_pile(id: String, count: int) -> Area3D:
	var pile := Area3D.new()
	pile.name = "Output_" + id
	pile.collision_mask = 0
	pile.set_meta("windmill_output", id)
	add_child(pile)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.55, .65, .55)
	shape.shape = box
	shape.position.y = .3
	pile.add_child(shape)
	if id == "sunflower_oil":
		var bottle := CylinderMesh.new()
		bottle.top_radius = .12
		bottle.bottom_radius = .14
		bottle.height = .32
		_mesh(pile, bottle, Vector3(0, .17, 0), Color("b5a351"))
		var neck := CylinderMesh.new()
		neck.top_radius = .044
		neck.bottom_radius = .06
		neck.height = .12
		_mesh(pile, neck, Vector3(0, .38, 0), Color("988849"))
	else:
		var sack := SphereMesh.new()
		sack.radius = .20
		sack.height = .44
		_mesh(pile, sack, Vector3(0, .21, 0), Color("cdbb8c") if id == "flour" else Color("9baf77"))
		var tie := TorusMesh.new()
		tie.inner_radius = .05
		tie.outer_radius = .07
		_mesh(pile, tie, Vector3(0, .4, 0), Color("6f5736"))
	var label := Label3D.new()
	label.text = "%s ×%d" % [str(GameData.get_item(id).get("name", id)), count]
	label.position = Vector3(0, .68, 0)
	label.font_size = 28
	label.pixel_size = .0035
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color("fff0cf")
	pile.add_child(label)
	return pile

func _mesh(root: Node3D, shape: Mesh, point: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .85
	mesh.material_override = material
	root.add_child(mesh)
