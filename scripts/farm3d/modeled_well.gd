extends "res://scripts/farm3d/modeled_building.gd"

func _configure_production_yard() -> void:
	var yard := get_node_or_null("ProductionYard")
	if yard != null: remove_child(yard);yard.free()

func _configure_physics() -> void:
	for part in ["Collision","InteractionArea","CameraOccluder","ModelCameraCollision"]:
		_set_box_shape(part,Vector3(.92,1.85,.92),.92)
	_apply_physics_state()

func can_operate(player: Node3D) -> bool:
	return Vector2(global_position.x,global_position.z).distance_to(Vector2(player.global_position.x,player.global_position.z)) <= 2.5 and absf(global_position.y-player.global_position.y) <= 1.5
