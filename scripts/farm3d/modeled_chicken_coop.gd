extends "res://scripts/farm3d/modeled_building.gd"

const HenScene = preload("res://assets/models/buildings/chicken_coop/hen.glb")
const Outputs = preload("res://scripts/farm3d/chicken_coop_outputs.gd")
var hens: Array[Node3D] = []
var _hen_rigs: Array[Dictionary] = []
var _grain: MeshInstance3D
var _hen_seconds := 0.0

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
	if hens.is_empty():
		for i in 2:
			var hen: Node3D = HenScene.instantiate()
			hen.name = "Hen%d" % i
			get_node("VisualRoot/Model/Details").add_child(hen)
			hens.append(hen)
			_hen_rigs.append({"head":hen.find_child("Head",true,false),"left":hen.find_child("LeftFoot",true,false),"right":hen.find_child("RightFoot",true,false)})
		_grain = MeshInstance3D.new()
		_grain.name = "GrainFill"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.40,.035,.30)
		_grain.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("d9b262")
		material.roughness = .96
		_grain.material_override = material
		_model_materials.append({"material":material,"color":material.albedo_color})
		_grain.position = Vector3(.56,.18,.70)
		get_node("VisualRoot/Model/Details").add_child(_grain)
		_update_hens(0)

func _configure_production_yard() -> void:
	# The GLB contains the entire wooden run. No inherited flat yard illustration.
	var yard := get_node_or_null("ProductionYard")
	if yard != null:
		remove_child(yard)
		yard.free()

func _apply_structure_offset() -> void:
	get_node("VisualRoot").position = Vector3.ZERO

func _sync_economy_indicator() -> void:
	super._sync_economy_indicator()
	var label := get_node_or_null("EconomyIndicator") as Label3D
	if label != null:
		label.text = "蛋篮已满" if _economy_indicator_kind == "full" else ""
		label.position = Vector3(0,2.52,-.4)
		label.font_size = 25
		label.pixel_size = .0035
		label.fixed_size = false
		label.outline_size = 4
		label.no_depth_test = false

func _configure_physics() -> void:
	_set_box_shape("Collision",Vector3(2.88,.8,2.88),.4)
	_set_box_shape("InteractionArea",Vector3(2.92,2.35,2.85),1.1)
	_set_box_shape("CameraOccluder",Vector3(2.0,2.4,1.9),1.15,Vector3(0,0,-.48))
	_set_box_shape("ModelCameraCollision",Vector3(2.0,2.4,1.9),1.15,Vector3(0,0,-.48))
	# A separate house volume blocks camera, ball and actor rays above the low run.
	var upper := get_node_or_null("Collision/HouseShape") as CollisionShape3D
	if upper == null:
		upper = CollisionShape3D.new()
		upper.name = "HouseShape"
		get_node("Collision").add_child(upper)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.95,2.2,1.85)
	upper.shape = shape
	upper.position = Vector3(0,1.1,-.47)
	_apply_physics_state()

func can_operate(player: Node3D) -> bool:
	var point := to_local(player.global_position)
	return absf(point.x) < 2.2 and point.z >= 1.5 and point.z <= 3.7 and absf(point.y) < 1.5

func _process(delta: float) -> void:
	super._process(delta)
	_update_hens(delta)

func _update_hens(delta: float) -> void:
	var active := is_inside_tree() and is_construction_complete() and not _preview_mode and is_visible_in_tree()
	var fed := producer_state != null and producer_state.get_input_count("animal_feed") > 0
	if _grain != null: _grain.visible = active and fed
	for hen in hens: hen.visible = active
	if not active: return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(global_position) > 45.0*45.0: return
	_hen_seconds += delta
	for i in hens.size():
		var hen := hens[i]
		var phase := fposmod(_hen_seconds+i*3.7,12.0)
		var walk := phase < 7.0
		var angle := minf(phase/7.0,1.0)*TAU
		var center := Vector3(-1.04,0,.66) if i == 0 else Vector3(.52,0,1.06)
		var radius := Vector2(.14,.13) if i == 0 else Vector2(.22,.04)
		hen.position = center+Vector3(sin(angle)*radius.x,0,cos(angle)*radius.y)
		hen.rotation.y = atan2(cos(angle)*radius.x,-sin(angle)*radius.y)
		var head: Node3D = _hen_rigs[i].head
		head.rotation.x = (.25+.65*maxf(0,sin(_hen_seconds*5))) if not walk and fed else sin(_hen_seconds*3)*.07
		for part in ["left","right"]:
			var foot: Node3D = _hen_rigs[i][part]
			foot.rotation.x = sin(_hen_seconds*10+(0 if part == "left" else PI))*.42 if walk else 0
		hen.position.y = absf(sin(_hen_seconds*10))*.013 if walk else 0
