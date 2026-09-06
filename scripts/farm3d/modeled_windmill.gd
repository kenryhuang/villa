extends "res://scripts/farm3d/modeled_building.gd"

const Yard = preload("res://scripts/farm3d/windmill_yard.gd")
const Outputs = preload("res://scripts/farm3d/windmill_outputs.gd")
var rotor_speed := 0.0

func _ensure_nodes() -> void:
	super._ensure_nodes()
	var output := get_node("BuildingOutputDisplay")
	if output.get_script() != Outputs:
		remove_child(output)
		output.free()
		output = Outputs.new()
		output.name = "BuildingOutputDisplay"
		add_child(output)
		output.collection_requested.connect(_on_output_pile_collection_requested)

func _configure_production_yard() -> void:
	var yard := get_node_or_null("ProductionYard")
	if yard == null:
		yard = Yard.new()
		yard.name = "ProductionYard"
		add_child(yard)
	var offset := data.production_yard_offset()
	yard.configure(data.footprint, "timber", offset)
	yard.set_construction_stage(int(construction_stage))
	yard.set_preview_state(_preview_mode, _preview_valid)

func _apply_construction_stage(play_effect: bool) -> void:
	super._apply_construction_stage(play_effect)
	var yard := get_node_or_null("ProductionYard")
	if yard != null:
		yard.set_construction_stage(int(construction_stage))

func _configure_physics() -> void:
	_set_box_shape("Collision", Vector3(3, 1.65, 3), .825)
	_set_box_shape("InteractionArea", Vector3(3.12, 4.25, 3.12), 2.0)
	_set_box_shape("CameraOccluder", Vector3(3.15, 4.3, 3.15), 2.05)
	_set_box_shape("ModelCameraCollision", Vector3(3.15, 4.3, 3.15), 2.05)
	_apply_physics_state()

func _process(delta: float) -> void:
	super._process(delta)
	var running := should_play_activity()
	rotor_speed = move_toward(rotor_speed, .65 if running else 0.0, delta * .6)
	var rotor := get_node_or_null("VisualRoot/Model/Rotor") as Node3D
	if rotor != null and is_construction_complete() and not _preview_mode:
		rotor.rotate_z(rotor_speed * delta)

func can_operate(player: Node3D) -> bool:
	var point := to_local(player.global_position)
	return absf(point.x) <= 2.2 and point.z >= 1.5 and point.z <= 3.4 and absf(point.y) < 1.5
