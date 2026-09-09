extends "res://scripts/farm3d/modeled_building.gd"

const Outputs = preload("res://scripts/farm3d/food_workshop_outputs.gd")
var production: ProductionSystem
var _sample_seconds := 0.0
var _flight_seconds := 0.0
var _foraging := false
var _targets: Array = []

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
	# The modeled hive stands directly on the real terrain, without painted yard art.
	var yard := get_node_or_null("ProductionYard")
	if yard != null:
		remove_child(yard)
		yard.free()

func bee_round_trip_seconds(target: Vector3) -> float:
	return 4.0 + Vector3(0,.47,.65).distance_to(target) * 2.0 / 1.2

func configure_beehive(system: ProductionSystem) -> void:
	production = system
	_sample_seconds = 0

func _configure_physics() -> void:
	_set_box_shape("Collision",Vector3(1.18,1.55,1.05),.78)
	_set_box_shape("InteractionArea",Vector3(1.65,1.8,1.4),.85)
	_set_box_shape("CameraOccluder",Vector3(1.5,1.8,1.25),.85)
	_set_box_shape("ModelCameraCollision",Vector3(1.5,1.8,1.25),.85)
	_apply_physics_state()

func can_operate(player: Node3D) -> bool:
	var point := to_local(player.global_position)
	return Vector2(point.x,point.z).length() <= 2.7 and absf(point.y) < 1.5

func _process(delta: float) -> void:
	super._process(delta)
	var model := get_node_or_null("VisualRoot/Model")
	if model == null: return
	_sample_seconds -= delta
	if _sample_seconds <= 0 and is_instance_valid(production):
		_sample_seconds = 1.0
		var snapshot := production.get_beehive_snapshot(self)
		_targets = snapshot.get("targets", [])
		_foraging = snapshot.get("status") == "working"
	var flying := _foraging and not _targets.is_empty() and not _preview_mode and is_construction_complete() and is_visible_in_tree()
	if flying: _flight_seconds += delta
	for index in model.bees.size():
		var bee: Node3D = model.bees[index]
		bee.visible = flying
		if not flying: continue
		var target := model.to_local(_targets[index % _targets.size()]) as Vector3
		var start := Vector3(0,.47,.65)
		var phase := fposmod(_flight_seconds / bee_round_trip_seconds(target) + index * .197, 1.0)
		var outbound := phase < .5
		var t := clampf(phase * 2 if outbound else (1 - phase) * 2, 0, 1)
		# Low arcs, a short hover at the flower, then return with pollen.
		var blend := smoothstep(.06,.86,t)
		bee.position = start.lerp(target,blend) + Vector3(sin(t*TAU+index)*.13,sin(t*PI)*.6 + sin(_flight_seconds*6+index)*.025,0)
		var direction := target - start if outbound else start - target
		bee.rotation.y = atan2(-direction.x,-direction.z)
		bee.get_node("LeftWing").rotation.z = sin(_flight_seconds*90+index)*.65
		bee.get_node("RightWing").rotation.z = -sin(_flight_seconds*90+index)*.65
		bee.get_node("Pollen").visible = not outbound
	if model.honey != null:
		var stored := producer_state.get_output_count("honey") if producer_state != null else 0
		model.honey.visible = stored > 0 or flying
		model.honey.scale.y = .45 + .55 * minf(1, stored / 4.0) if not flying else .7 + sin(_flight_seconds*2)*.05
