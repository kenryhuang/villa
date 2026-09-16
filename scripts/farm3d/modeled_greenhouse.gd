extends "res://scripts/farm3d/modeled_building.gd"

func _configure_production_yard() -> void:
	var yard := get_node_or_null("ProductionYard")
	if yard != null:
		remove_child(yard)
		yard.free()

func _configure_physics() -> void:
	# Cold frames never block rays to their real crop cells.
	_set_box_shape("Collision",Vector3(2.76,2.0,2.76),1.0)
	_set_box_shape("InteractionArea",Vector3(2.82,2.9,2.82),1.45)
	_set_box_shape("CameraOccluder",Vector3(2.82,3.0,2.82),1.5)
	_set_box_shape("ModelCameraCollision",Vector3(2.82,3.0,2.82),1.5)
	_apply_physics_state()

func _apply_visual_color() -> void:
	super._apply_visual_color()
	# The shared modeled-building tint normally makes every material opaque.
	for entry in _model_materials:
		if entry.color.a < 1:
			entry.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func can_operate(player: Node3D) -> bool:
	var point := to_local(player.global_position)
	return Vector2(point.x,point.z).length() <= 4.2 and absf(point.y) < 1.5
