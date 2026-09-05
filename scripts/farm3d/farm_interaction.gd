extends Node3D

const HudScript = preload("res://scripts/farm3d/farm_hud.gd")
const ToolVisualScript = preload("res://scripts/farm3d/farm_tool_visual.gd")
const MODES := ["hoe", "seed", "water", "harvest"]
const REACH := 2.6
var session: Node
var player: Node3D
var hud: CanvasLayer
var mode := "hoe"
var target_cell: GridCell
var _marker: Node3D
var _marker_material: StandardMaterial3D
var _tool_visual: Node3D
var _cooldown := 0.0
var _front_target := true
var _pointer := Vector2.ZERO

func configure(farm_session: Node, farmer: Node3D) -> void:
	session = farm_session
	player = farmer
	_marker = Node3D.new()
	_marker.name = "TargetCell"
	add_child(_marker)
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in 4:
		var edge := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.98, 0.013, 0.027) if side < 2 else Vector3(0.027, 0.013, 0.98)
		edge.mesh = box
		edge.position = Vector3(0, 0, -0.48 if side == 0 else 0.48) if side < 2 else Vector3(-0.48 if side == 2 else 0.48, 0, 0)
		edge.material_override = _marker_material
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marker.add_child(edge)
	_tool_visual = ToolVisualScript.new()
	_tool_visual.name = "FarmTool"
	player.add_child(_tool_visual)
	hud = HudScript.new()
	hud.name = "FarmHUD"
	add_child(hud)
	hud.configure(session)
	hud.mode_requested.connect(select_mode)
	hud.rest_requested.connect(_rest)
	hud.save_requested.connect(_save)
	select_mode("hoe")

func _process(delta: float) -> void:
	if session == null:
		return
	_cooldown = maxf(0, _cooldown - delta)
	if _front_target or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		target_cell = front_cell()
	elif get_viewport().gui_get_hovered_control() != null:
		target_cell = null
	else:
		target_cell = cell_at_pointer(_pointer)
	_marker.visible = target_cell != null
	if target_cell == null:
		hud.show_target("靠近草地，左键耕作 · E 操作前方", true)
		return
	_marker.global_position = target_cell.world_position_3d() + Vector3.UP * 0.075
	var details := target_details(target_cell)
	_marker_material.albedo_color = Color("d9d895") if details.allowed else Color("d79477")
	hud.show_target(details.text, details.allowed)

func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_pointer = event.position
		_front_target = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return
		_pointer = event.position
		_front_target = false
		perform(cell_at_pointer(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			select_mode(MODES[event.keycode - KEY_1])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			_front_target = true
			perform(front_cell())
			get_viewport().set_input_as_handled()

func select_mode(selected: String) -> void:
	if selected not in MODES:
		return
	mode = selected
	hud.set_mode(mode)
	_tool_visual.set_mode(mode)

func front_cell() -> GridCell:
	var point := player.global_position + player.global_basis.z * 1.25
	return _cell_at(point)

func cell_at_pointer(pointer: Vector2) -> GridCell:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(pointer)
	var direction := camera.project_ray_normal(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 100, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return null if hit.is_empty() else _cell_at(hit.position)

func _cell_at(point: Vector3) -> GridCell:
	var coordinates: Vector2i = session.grid.world_to_grid(point.x, point.z)
	return session.grid.get_cell(coordinates.x, coordinates.y)

func perform(cell: GridCell) -> Dictionary:
	if _cooldown > 0.0:
		return {"ok": false, "reason": "busy"}
	var result: Dictionary = session.act(cell, mode)
	var succeeded := bool(result.get("ok", false))
	hud.notify_message(str(result.get("message", "操作完成" if succeeded else "这里暂时无法操作")), succeeded)
	if succeeded:
		_cooldown = 0.5
		player.begin_farm_action(cell.world_position_3d())
		if mode == "hoe":
			_tool_visual.swing()
	return result

func target_details(cell: GridCell) -> Dictionary:
	if Vector2(player.global_position.x, player.global_position.z).distance_to(cell.world_position()) > REACH:
		return {"allowed": false, "text": "距离太远 · 请走近这块土地"}
	if cell.state not in [GridCell.State.WASTELAND, GridCell.State.FARMLAND, GridCell.State.PLANTED]:
		return {"allowed": false, "text": "道路、树根和石头旁不能开垦"}
	if cell.crop_instance != null:
		var crop: CropInstance = cell.crop_instance
		if crop.lifecycle_state == CropInstance.LifecycleState.WITHERED:
			return {"allowed": mode in ["hoe", "harvest"], "text": "谷物已枯萎 · 用锄头或收获清理"}
		if crop.is_mature():
			return {"allowed": mode == "harvest", "text": "谷物成熟了 · 选择 4 收获"}
		var progress := crop.growth_progress / float(crop.crop_data.growth_days)
		var minutes_left := ceili((1.0 - progress) * float(crop.crop_data.growth_duration_minutes))
		return {"allowed": mode == "water" and not cell.watered, "text": "谷物生长 %d%% · 约 %d 游戏分钟后成熟%s" % [int(progress * 100), minutes_left, " · 已浇水" if cell.watered else ""]}
	if cell.state == GridCell.State.WASTELAND:
		return {"allowed": mode == "hoe", "text": "草地 · 选择 1 锄头开垦"}
	if mode == "seed":
		var preview: Dictionary = session.farming.preview_plant(cell, "grain_seed")
		if not preview.get("ok", false):
			return {"allowed": false, "text": "当前季节不适宜谷物 · 春、夏、秋可播种"}
		if session.inventory.get_item_count("grain_seed") < 1:
			return {"allowed": false, "text": "谷物种子已用完"}
	return {"allowed": mode == "seed", "text": "已开垦土地 · 选择 2 播种谷物"}

func _rest() -> void:
	var result: Dictionary = session.rest()
	hud.notify_message(str(result.get("message", "新的一天开始了，体力已恢复")), bool(result.get("ok", true)))

func _save() -> void:
	var saved: bool = session.save_game()
	hud.notify_message("农庄已保存" if saved else "保存失败，请检查存储空间", saved)
