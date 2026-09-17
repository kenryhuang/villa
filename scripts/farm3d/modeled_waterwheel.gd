extends "res://scripts/farm3d/modeled_building.gd"

var production: ProductionSystem
var running := false
var _refresh_in := 0.0
var _pipes: Node3D
var _link_signature := ""

func configure_waterwheel(system: ProductionSystem) -> void:
	production=system
	_refresh_in=0

func _configure_production_yard() -> void:
	var yard := get_node_or_null("ProductionYard")
	if yard != null: remove_child(yard);yard.free()

func _configure_physics() -> void:
	for part in ["Collision","InteractionArea","CameraOccluder","ModelCameraCollision"]:
		_set_box_shape(part,Vector3(1.9,2.5,1.9),1.05)
	_apply_physics_state()

func can_operate(player: Node3D) -> bool:
	return global_position.distance_to(player.global_position)<3.4

func _process(delta: float) -> void:
	super._process(delta)
	if production == null or _preview_mode: return
	_refresh_in-=delta
	if _refresh_in<=0:
		_refresh_in=1.0
		var info := production.get_waterwheel_snapshot(self)
		running=info.get("status","")=="working"
		if info.get("water_connected",false):
			align_to_water(info.water_anchor,grid_x,grid_z)
		_update_pipes(info)
	if running:
		get_node("VisualRoot/Model/Rotor").rotate_x(delta*.55)

func _update_pipes(info: Dictionary) -> void:
	var links: Array=info.get("connections",[])
	var signature := str(links)+str(running)+str(is_construction_complete())+str(get_node("VisualRoot/Model").transform)
	if signature==_link_signature:return
	_link_signature=signature
	if is_instance_valid(_pipes):_pipes.free()
	_pipes=Node3D.new();_pipes.name="SupplyPipes";add_child(_pipes)
	if not is_construction_complete():return
	var mat := StandardMaterial3D.new();mat.albedo_color=Color("508f94") if running else Color("74766c");mat.metallic=.45;mat.roughness=.6
	var outlet: Node3D=get_node("VisualRoot/Model/Details/Outlet")
	for link in links:
		var link_material := mat.duplicate() as StandardMaterial3D
		if not link.active:link_material.albedo_color=Color("74766c")
		var cell: GridCell=production._grid_system.get_cell(link.gx,link.gz)
		var end := to_local(cell.world_position_3d()+Vector3.UP*.23)
		var start := to_local(outlet.global_position)
		# Ground-following segments are presentation only: no added costs or collision.
		var previous := start
		for i in range(1,17):
			var point := start.lerp(end,i/16.0)
			var world := to_global(point)
			world.y=maxf(world.y,preload("res://scripts/farm3d/terrain_profile.gd").surface_height(world.x,world.z)+.12)
			point=to_local(world)
			var mesh := CylinderMesh.new();mesh.top_radius=.055;mesh.bottom_radius=.055;mesh.height=previous.distance_to(point);mesh.radial_segments=8
			var segment := MeshInstance3D.new();segment.mesh=mesh;segment.material_override=link_material;_pipes.add_child(segment)
			segment.position=(previous+point)*.5;segment.quaternion=Quaternion(Vector3.UP,(point-previous).normalized())
			previous=point

func align_to_water(anchor: Vector2i, gx: int, gz: int) -> void:
	var model := get_node("VisualRoot/Model") as Node3D
	var direction := Vector2(anchor)-Vector2(gx+.5,gz+.5)
	model.rotation.y=PI*.5*roundf(atan2(direction.x,direction.y)/(PI*.5))
	# Lowest bucket dips into the water; stone piers extend back into the bank.
	model.position.y=minf(0.0,preload("res://scripts/farm3d/terrain_profile.gd").WATER_HEIGHT-.19-global_position.y)
