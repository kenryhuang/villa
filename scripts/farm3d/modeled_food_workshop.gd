extends "res://scripts/farm3d/modeled_building.gd"

const Yard = preload("res://scripts/farm3d/food_workshop_yard.gd")
const Outputs = preload("res://scripts/farm3d/food_workshop_outputs.gd")
var _steam: CPUParticles3D
var _work_light: OmniLight3D

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
	if _steam == null:
		_steam = CPUParticles3D.new()
		_steam.name = "CookingSteam"
		_steam.amount = 10
		_steam.lifetime = 2
		_steam.direction = Vector3.UP
		_steam.spread = 15
		_steam.gravity = Vector3(0,.1,0)
		_steam.initial_velocity_min = .15
		_steam.initial_velocity_max = .3
		_steam.scale_amount_min = .4
		_steam.scale_amount_max = 1
		var puff := SphereMesh.new()
		puff.radius = .085
		puff.height = .17
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(.86,.87,.81,.3)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material = material
		_steam.mesh = puff
		_steam.emitting = false
		get_node("VisualRoot").add_child(_steam)
		_steam.position = Vector3(-.96,3.48,-.83)
		_work_light = OmniLight3D.new()
		_work_light.name = "WarmWorktopLight"
		_work_light.light_color = Color("ffe5b2")
		_work_light.light_energy = .6
		_work_light.omni_range = 2.3
		get_node("VisualRoot").add_child(_work_light)
		_work_light.position = Vector3(0,1.7,.85)

func _configure_production_yard() -> void:
	var yard := get_node_or_null("ProductionYard")
	if yard == null:
		yard = Yard.new()
		yard.name = "ProductionYard"
		add_child(yard)
	yard.configure(data.footprint,"timber",data.production_yard_offset())
	yard.set_construction_stage(int(construction_stage))
	yard.set_preview_state(_preview_mode,_preview_valid)

func _apply_construction_stage(play_effect: bool) -> void:
	super._apply_construction_stage(play_effect)
	var yard := get_node_or_null("ProductionYard")
	if yard != null:
		yard.set_construction_stage(int(construction_stage))

func _configure_physics() -> void:
	var offset := data.production_yard_offset()
	_set_box_shape("Collision",Vector3(3.7,2.25,2.65),1.1,offset)
	_set_box_shape("InteractionArea",Vector3(3.8,3.55,3.25),1.75,offset)
	_set_box_shape("CameraOccluder",Vector3(3.8,3.55,3.25),1.75,offset)
	_set_box_shape("ModelCameraCollision",Vector3(3.8,3.55,3.25),1.75,offset)
	_apply_physics_state()

func _process(delta: float) -> void:
	super._process(delta)
	if _steam != null:
		_steam.visible = is_construction_complete() and not _preview_mode
		_steam.emitting = should_play_activity()
		_work_light.visible = _steam.visible

func can_operate(player: Node3D) -> bool:
	var point := to_local(player.global_position)
	return absf(point.x) < 2.5 and point.z >= 1.5 and point.z <= 3.8 and absf(point.y) < 1.5
