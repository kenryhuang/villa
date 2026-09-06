extends BuildingInstance

## 3D-only presentation. Construction, costs, storage and saves stay shared.
const MaintenanceVisual = preload("res://scripts/farm3d/modeled_maintenance_visual.gd")
@export var model_scene: PackedScene
var _model_materials: Array[Dictionary] = []

func deactivate() -> void:
	super.deactivate()
	(get_node("ModelCameraCollision") as StaticBody3D).collision_layer = 0

func _ensure_nodes() -> void:
	super._ensure_nodes()
	var maintenance := get_node("BuildingMaintenanceVisual")
	if maintenance.get_script() != MaintenanceVisual:
		remove_child(maintenance)
		maintenance.free()
		maintenance = MaintenanceVisual.new()
		maintenance.name = "BuildingMaintenanceVisual"
		add_child(maintenance)
	var root := get_node("VisualRoot")
	if model_scene != null and root.get_node_or_null("Model") == null:
		var model := model_scene.instantiate() as Node3D
		model.name = "Model"
		root.add_child(model)
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface) as StandardMaterial3D
				if source == null:
					continue
				var material := source.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface,material)
				_model_materials.append({"material": material,"color": material.albedo_color})
	_ensure_physics_node("ModelCameraCollision",StaticBody3D)

func _configure_visuals() -> void:
	_hide_legacy_art()
	(get_node("ConstructionFeedback") as ConstructionFeedback).configure(data.visual_size)
	get_node("BuildingMaintenanceVisual").configure(data.visual_size,data.ground_anchor_uv)
	get_node("BuildingMaintenanceVisual").set_state(_maintenance_visual_state)
	_apply_visual_color()

func _hide_legacy_art() -> void:
	for child in get_node("VisualRoot").get_children():
		if child is Node3D and child.name != "Model":
			child.hide()

func _apply_construction_stage(_play_effect: bool) -> void:
	if data == null:
		return
	_ensure_nodes()
	_hide_legacy_art()
	var model := get_node("VisualRoot/Model")
	for part in model.get_children():
		if part is Node3D:
			var stage: int = {"Foundation": 0,"Frame": 1,"Walls": 2,"Roof": 3,"Details": 3}.get(str(part.name),3)
			part.visible = _preview_mode or int(construction_stage) >= stage
	_sync_construction_feedback()
	_sync_output_display_state()
	_apply_physics_state()

func _configure_physics() -> void:
	# Stone foundation and wall silhouette match the Blender mesh in metres.
	_set_box_shape("Collision",Vector3(1.96,2.28,1.96),.94)
	_set_box_shape("InteractionArea",Vector3(2.5,3.2,2.5),1.6)
	_set_box_shape("CameraOccluder",Vector3(2.4,3.2,2.4),1.6)
	_set_box_shape("ModelCameraCollision",Vector3(2.4,3.2,2.4),1.6)
	var roof := get_node_or_null("Collision/RoofShape") as CollisionShape3D
	if roof == null:
		roof = CollisionShape3D.new()
		roof.name = "RoofShape"
		get_node("Collision").add_child(roof)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-1.16,1.98,-1.16),Vector3(1.16,1.98,-1.16),Vector3(0,3.17,-1.16),
		Vector3(-1.16,1.98,1.16),Vector3(1.16,1.98,1.16),Vector3(0,3.17,1.16),
	])
	roof.shape = shape
	_apply_physics_state()

func _apply_physics_state() -> void:
	super._apply_physics_state()
	var camera_body := get_node_or_null("ModelCameraCollision") as StaticBody3D
	if camera_body != null:
		camera_body.collision_layer = 32 if not _preview_mode and construction_stage > ConstructionStage.FOUNDATION else 0
		camera_body.collision_mask = 0
	var roof := get_node_or_null("Collision/RoofShape") as CollisionShape3D
	if roof != null:
		roof.disabled = construction_stage < ConstructionStage.COMPLETE

func _apply_visual_color() -> void:
	super._apply_visual_color()
	var tint := Color.WHITE
	if _preview_mode:
		tint = Color(.55,1,.60,.62) if _preview_valid else Color(1,.35,.30,.62)
	elif _maintenance_visual_state != "normal":
		tint = Color(.80,.78,.72)
	for entry in _model_materials:
		var material: StandardMaterial3D = entry.material
		material.albedo_color = entry.color*tint
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if _preview_mode else BaseMaterial3D.TRANSPARENCY_DISABLED
		material.emission_enabled = _preview_mode
		material.emission = Color(.08,.32,.09) if _preview_valid else Color(.38,.035,.02)
		material.emission_energy_multiplier = .4
	# Material alpha works in Compatibility rendering too.
	for mesh in _visual_geometry():
		if mesh is MeshInstance3D:
			mesh.transparency = 0
