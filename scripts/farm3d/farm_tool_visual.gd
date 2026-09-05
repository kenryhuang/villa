extends Node3D

var _hoe: Node3D
var _swing: Tween
const REST_ROTATION := Vector3(-0.25, 0.15, -0.28)

func _ready() -> void:
	position = Vector3(0.46, 1.04, 0.25)
	_hoe = Node3D.new()
	_hoe.name = "Hoe"
	add_child(_hoe)
	_hoe.rotation = REST_ROTATION
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("926033")
	wood.roughness = 0.86
	var handle := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.025
	shaft.bottom_radius = 0.035
	shaft.height = 1.36
	shaft.radial_segments = 12
	handle.mesh = shaft
	handle.material_override = wood
	_hoe.add_child(handle)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("56636a")
	iron.metallic = 0.65
	iron.roughness = 0.43
	var head := MeshInstance3D.new()
	var blade := BoxMesh.new()
	blade.size = Vector3(0.27, 0.045, 0.23)
	head.mesh = blade
	head.position = Vector3(0, -0.62, 0.085)
	head.rotation.x = -0.3
	head.material_override = iron
	_hoe.add_child(head)
	var collar := MeshInstance3D.new()
	var socket := CylinderMesh.new()
	socket.top_radius = 0.045
	socket.bottom_radius = 0.042
	socket.height = 0.11
	socket.radial_segments = 12
	collar.mesh = socket
	collar.position.y = -0.56
	collar.material_override = iron
	_hoe.add_child(collar)

func set_mode(mode: String) -> void:
	visible = mode == "hoe"

func cancel_action() -> void:
	if _swing != null:
		_swing.kill()
	_hoe.rotation = REST_ROTATION
	hide()

func swing() -> void:
	if _swing != null and _swing.is_running():
		_swing.kill()
	_swing = create_tween()
	_swing.tween_property(_hoe, "rotation:x", -1.9, 0.12).set_trans(Tween.TRANS_QUAD)
	_swing.tween_property(_hoe, "rotation:x", 0.75, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing.tween_property(_hoe, "rotation", REST_ROTATION, 0.2)
