extends Node3D

const HudScript = preload("res://scripts/farm3d/farm_hud.gd")
const Catalog = preload("res://scripts/farm3d/target_catalog.gd")
const FishingScript = preload("res://scripts/farm3d/farm_fishing.gd")
var fishing: Node3D
var golf: Node3D
var market_building: Node3D
var session: Node
var player: Node3D
var hud: CanvasLayer
var category := ""
var target_id := ""
var target_cell: GridCell
var _marker: Node3D
var _marker_material: StandardMaterial3D
var _cooldown := 0.0
var _pointer := Vector2.ZERO
var _front_target := false

func configure(farm_session: Node, farmer: Node3D) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_marker.hide()
	hud = HudScript.new()
	hud.name = "FarmHUD"
	add_child(hud)
	hud.configure(session)
	hud.target_requested.connect(select_target)
	hud.category_requested.connect(select_category)
	hud.rest_requested.connect(_rest)
	hud.save_requested.connect(_save)
	fishing = FishingScript.new()
	fishing.process_mode = Node.PROCESS_MODE_PAUSABLE
	fishing.name = "Fishing"
	add_child(fishing)
	fishing.configure(session,player,hud)
	session.fishing = fishing
	hud.fishing_requested.connect(_toggle_fishing)
	hud.fishing_action_requested.connect(func(): fishing.act())
	hud.fishing_cancel_requested.connect(func(): fishing.cancel())
	market_building = preload("res://scripts/farm3d/market_building.gd").new()
	add_child(market_building)
	market_building.configure(session)
	golf = preload("res://scripts/farm3d/farm_golf.gd").new()
	add_child(golf)
	session.golf = golf
	golf.configure(session,player,hud)
	session.action_controller.cancel_current_selection()

func _process(delta: float) -> void:
	if session == null:
		return
	_cooldown = maxf(0, _cooldown - delta)
	if target_id.is_empty() or fishing.is_equipped() or hud.is_modal_open() or get_viewport().gui_get_hovered_control() != null:
		target_cell = null
		_marker.hide()
		session.buildings._preview_root.visible = false
		return
	target_cell = front_cell() if _front_target or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else cell_at_pointer(_pointer)
	_marker.visible = target_cell != null and category != "building"
	if target_cell == null:
		session.buildings._preview_root.visible = false
		return
	_marker.global_position = target_cell.world_position_3d() + Vector3.UP * 0.075
	var p := target_cell.world_position()
	var profile = Farm3DTerrainProfile
	var normal := Vector3(profile.surface_height(p.x-.5,p.y)-profile.surface_height(p.x+.5,p.y),1,profile.surface_height(p.x,p.y-.5)-profile.surface_height(p.x,p.y+.5)).normalized()
	_marker.quaternion = Quaternion(Vector3.UP,normal)
	var allowed: bool = session._in_range(target_cell)
	if category == "building":
		if not session.buildings.is_in_build_mode():
			session.buildings.enter_preview_mode(target_id)
		session.buildings.update_preview_grid(target_cell.gx, target_cell.gz)
		session.buildings._preview_root.visible = true
	else:
		allowed = allowed and _target_allowed(target_cell)
		_marker_material.albedo_color = Color("e2d9a3") if allowed else Color("df8468")

func _input(event: InputEvent) -> void:
	if session == null:
		return
	if golf != null and golf.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if hud.food_workshop_view.visible:
				hud.food_workshop_view.handle_escape()
			elif hud.windmill_view.visible:
				hud.windmill_view.handle_escape()
			elif hud.market_view.visible:
				hud.market_view.handle_escape()
			else:
				cancel_selection()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			hud.toggle_inventory()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			hud.toggle_minimap()
			get_viewport().set_input_as_handled()
	if hud.is_modal_open() and not hud.market_view.visible and not hud.windmill_view.visible and event is InputEventKey:
		get_viewport().set_input_as_handled()

func cancel_selection() -> void:
	if golf != null and golf.visual != null:
		golf.release_control()
	if fishing != null:
		fishing.cancel()
	category = ""
	target_id = ""
	target_cell = null
	_cooldown = 0
	_marker.hide()
	session.buildings.exit_preview_mode()
	player.cancel_farm_action()
	session.action_controller.cancel_current_selection()
	hud.show_category("")
	hud.close_panels()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func select_category(next_category: String) -> void:
	cancel_selection()
	if next_category in ["farmland", "seed", "building"]:
		category = next_category
		hud.show_category(category)

func select_target(next_category: String, id: String) -> void:
	var selected: Dictionary = {}
	for entry in Catalog.entries(next_category):
		if entry.id == id:
			selected = entry
	if selected.is_empty():
		return
	if golf != null:
		golf.release_control()
	fishing.cancel()
	session.buildings.exit_preview_mode()
	category = next_category
	target_id = id
	hud.close_panels()
	hud.set_target(category, id)
	var detail: String = selected.detail
	if category == "building":
		session.buildings.enter_preview_mode(id)
		var cost: Dictionary = Catalog.Data.get_building(id).cost
		var materials: Array[String] = []
		for item_id in cost:
			materials.append("%s ×%d" % [session.item_name(item_id), cost[item_id]])
		detail += " · " + "、".join(materials)
	hud.notify_message("已选择%s · %s。点击地面放置。" % [selected.name, detail], true)

func _unhandled_input(event: InputEvent) -> void:
	if session == null or hud.is_modal_open():
		return
	if event is InputEventMouseMotion and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_pointer = event.position
		_front_target = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return
		_pointer = event.position
		_front_target = false
		if golf != null and golf.try_world_click(event.position):
			get_viewport().set_input_as_handled()
			return
		var windmill_hit := windmill_at_pointer(event.position)
		if not windmill_hit.is_empty():
			if str(windmill_hit.item_id).is_empty():
				open_windmill(windmill_hit.building)
			else:
				collect_windmill(windmill_hit.building, windmill_hit.item_id)
		elif market_at_pointer(event.position):
			open_market()
		else:
			perform(cell_at_pointer(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_front_target = true
		perform(front_cell())
		get_viewport().set_input_as_handled()

func front_cell() -> GridCell:
	var point := player.global_position + player.global_basis.z * 1.25
	return _cell_at(point)

func windmill_at_pointer(pointer: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var origin := camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far, 1 | 16 | 64 | 128)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var node: Node = hit.collider
	var item_id := str(node.get_meta("production_output",node.get_meta("windmill_output", "")))
	while node != null:
		if node is BuildingInstance:
			return {"building": node, "item_id": item_id} if node.building_id in ["windmill","food_workshop"] else {}
		node = node.get_parent()
	return {}

func open_windmill(building: BuildingInstance) -> bool:
	if hud.is_modal_open():
		return false
	if not building.is_construction_complete():
		hud.notify_message("%s尚未建造完成" % building.data.display_name, false)
		return false
	if not building.can_operate(player):
		hud.notify_message("请走到%s南面的操作台前，再点击建筑" % building.data.display_name, false)
		return false
	cancel_selection()
	return hud.open_windmill(building)

func collect_windmill(building: BuildingInstance, item_id: String) -> bool:
	if hud.is_modal_open() or not building.can_operate(player):
		hud.notify_message("请走到%s南面收取成品" % building.data.display_name, false)
		return false
	cancel_selection()
	var result: Dictionary = session.production.collect_outputs(building, session.inventory, item_id)
	if not result.get("ok", false):
		hud.notify_message("背包空间不足，请先整理背包" if str(result.get("reason", "")) == "inventory_capacity" else "暂无可收取的成品", false)
		return false
	hud.notify_message("%s已收进背包" % session.item_name(item_id), true)
	if session.auto_save and not session.save_game():
		hud.notify_message("自动保存失败，请手动保存", false)
	return true

func market_at_pointer(pointer: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var origin := camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far, 1 | 64)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and bool(hit.collider.get_meta("farm_market", false))

func open_market() -> bool:
	if hud.is_modal_open():
		return false
	if not market_building.can_trade(player):
		hud.notify_message("请走到市集南面的柜台前，再点击摊位交易", false)
		return false
	cancel_selection()
	hud.open_market()
	return true

func cell_at_pointer(pointer: Vector2) -> GridCell:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(pointer)
	var direction := camera.project_ray_normal(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * camera.far, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return null if hit.is_empty() else _cell_at(hit.position)

func _cell_at(point: Vector3) -> GridCell:
	var coordinates: Vector2i = session.grid.world_to_grid(point.x, point.z)
	return session.grid.get_cell(coordinates.x, coordinates.y)

func perform(cell: GridCell) -> Dictionary:
	if hud.is_modal_open():
		return {"ok": false, "reason": "ui_blocked"}
	if fishing.is_equipped():
		return fishing.act()
	if _cooldown > 0:
		return {"ok": false, "reason": "busy"}
	# A category alone isn't a placement target; keep the world unchanged until a leaf is chosen.
	if not category.is_empty() and target_id.is_empty():
		hud.notify_message("请继续选择具体目标", false)
		return {"ok": false, "reason": "choose_target"}
	var result: Dictionary = session.apply_target(cell, category, target_id)
	hud.notify_message(str(result.get("message", "操作未完成")), bool(result.ok))
	if result.ok:
		_cooldown = 0.35
		player.begin_farm_action(cell.world_position_3d())
	return result

func _target_allowed(cell: GridCell) -> bool:
	if category == "farmland":
		return cell.crop_instance == null and cell.state in [GridCell.State.WASTELAND, GridCell.State.FARMLAND]
	if category == "seed":
		return session.inventory.get_item_count(target_id) > 0 and session.farming.preview_plant(cell, target_id).get("ok", false)
	return false

func _rest() -> void:
	if golf != null:
		golf.release_control()
	fishing.cancel()
	var result: Dictionary = session.rest()
	hud.notify_message(str(result.message), bool(result.ok))

func _save() -> void:
	var saved: bool = session.save_game()
	hud.notify_message("农庄已保存" if saved else "保存失败，请检查存储空间", saved)

func _toggle_fishing() -> void:
	if fishing.is_equipped():
		fishing.cancel()
		return
	# Verify the position again even when invoked without clicking the HUD button.
	fishing.refresh_location()
	if fishing.available_location.is_empty() or hud.is_modal_open():
		return
	cancel_selection()
	fishing.equip()
