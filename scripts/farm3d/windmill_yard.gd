extends Node3D

var _meshes: Array[MeshInstance3D] = []
var _preview := false
var _valid := true
var _stage := 0

func configure(_size: Vector2i, _style: String, _offset: Vector3) -> bool:
	clear_immediately()
	_box(Vector3(3, .08, 3), Vector3(0, -.02, 0), Color("968967"))
	for x in [-1.42, 1.42]:
		for z in [-1.42, 0.0, 1.42]:
			_box(Vector3(.095, .66, .095), Vector3(x, .31, z), Color("8d693c"))
		for y in [.23, .48]:
			_box(Vector3(.06, .065, 2.8), Vector3(x, y, 0), Color("ad8550"))
	for y in [.23, .48]:
		_box(Vector3(2.8, .065, .06), Vector3(0, y, -1.42), Color("ad8550"))
	# The southern opening leaves a clear approach to the three pickup positions.
	_apply()
	return true

func get_output_slots() -> Array[Vector3]:
	return [Vector3(-.87, .06, 1.38), Vector3(0, .06, 1.38), Vector3(.87, .06, 1.38)]

func set_construction_stage(value: int) -> void:
	_stage = value
	_apply()

func set_preview_state(active: bool, valid: bool) -> void:
	_preview = active
	_valid = valid
	_apply()

func set_maintenance_state(_state: String) -> void:
	pass

func set_interaction_enabled(_enabled: bool) -> void:
	pass

func clear_immediately() -> void:
	for child in get_children():
		child.free()
	_meshes.clear()

func _apply() -> void:
	for index in _meshes.size():
		var mesh := _meshes[index]
		mesh.visible = index == 0 or _preview or _stage >= 1
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color = mesh.get_meta("base_color") * (Color(.6, 1, .65, .6) if _valid else Color(1, .4, .3, .6)) if _preview else mesh.get_meta("base_color")
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if _preview else BaseMaterial3D.TRANSPARENCY_DISABLED

func _box(size: Vector3, point: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .95
	mesh.material_override = material
	mesh.set_meta("base_color", color)
	add_child(mesh)
	_meshes.append(mesh)
