class_name GatheringFeedback
extends Node

const ERROR_MESSAGES := {
	"inventory_full": "背包已满",
	"insufficient_stamina": "体力不足",
	"tool_broken": "工具已损坏",
	"resource_depleted": "资源已采空",
	"unreachable": "无法到达",
	"target_invalid": "目标已失效",
	"out_of_range": "距离过远",
	"tree_not_choppable": "此树不可砍伐",
}

var _controller
var _tool_visual: ToolSwingVisual
var _target: Node3D
var _result_time_remaining := 0.0
var _status_time_remaining := 0.0
var _impact_played := false


func _ready() -> void:
	_build_target_ring()
	_build_tree_hover_ring()
	(get_node("Canvas/ProgressRing") as Control).visible = false
	(get_node("Canvas/AutoEquipTip") as Control).visible = false
	(get_node("Canvas/StatusLabel") as Control).visible = false
	(get_node("RemainingLabel") as Label3D).visible = false
	(get_node("ResultLabel") as Label3D).visible = false


func bind(controller, tool_visual: ToolSwingVisual, action_controller = null) -> bool:
	if controller == null or tool_visual == null:
		return false
	_controller = controller
	_tool_visual = tool_visual
	controller.gather_started.connect(_on_gather_started)
	controller.gather_progress.connect(_on_gather_progress)
	controller.gather_completed.connect(_on_gather_completed)
	controller.gather_failed.connect(_on_gather_failed)
	controller.gather_cancelled.connect(_on_gather_cancelled)
	controller.state_changed.connect(_on_state_changed)
	if controller.has_signal("path_ready"):
		controller.path_ready.connect(show_path)
	if action_controller != null:
		if action_controller.has_signal("tree_hover_changed"):
			action_controller.tree_hover_changed.connect(show_tree_hover)
		if action_controller.has_signal("gather_rejected"):
			action_controller.gather_rejected.connect(_on_gather_failed)
	return true


func error_message(reason: String) -> String:
	return str(ERROR_MESSAGES.get(reason, "操作失败"))


static func progress_center_with_label_clearance(
	projected_center: Vector2,
	remaining_label_center: Vector2
) -> Vector2:
	var result := projected_center
	result.y = minf(result.y, remaining_label_center.y - 72.0)
	return result


static func tree_axe_anchor(tree_position: Vector3, _actor_position: Vector3) -> Vector3:
	return tree_position + Vector3.LEFT * 0.45 + Vector3.UP * 0.20


func _process(delta: float) -> void:
	_update_screen_positions()
	_result_time_remaining = maxf(0.0, _result_time_remaining - maxf(delta, 0.0))
	_status_time_remaining = maxf(0.0, _status_time_remaining - maxf(delta, 0.0))
	if _result_time_remaining <= 0.0:
		(get_node("ResultLabel") as Label3D).visible = false
	if _status_time_remaining <= 0.0:
		(get_node("Canvas/StatusLabel") as Control).visible = false


func show_path(points: Array[Vector3]) -> void:
	var preview := get_node("PathPreview") as MeshInstance3D
	if points.size() < 2:
		preview.visible = false
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for index in range(points.size() - 1):
		var start := points[index] + Vector3.UP * 0.08
		var finish := points[index + 1] + Vector3.UP * 0.08
		var segment := finish - start
		var distance := segment.length()
		var step_count := maxi(1, floori(distance / 0.36))
		for step in range(0, step_count, 2):
			var from_ratio := float(step) / float(step_count)
			var to_ratio := minf(1.0, float(step + 1) / float(step_count))
			surface.add_vertex(start.lerp(finish, from_ratio))
			surface.add_vertex(start.lerp(finish, to_ratio))
	preview.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.84, 0.38, 0.72)
	preview.material_override = material
	preview.visible = true


func show_tree_hover(target: Node, allowed: bool) -> void:
	var ring := get_node("TreeHoverRing") as Node3D
	if not target is Node3D:
		ring.visible = false
		return
	ring.global_position = (target as Node3D).global_position + Vector3.UP * 0.04
	var mesh := ring.get_child(0) as MeshInstance3D
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = (
		Color(0.25, 0.9, 0.38, 0.62)
		if allowed
		else Color(0.95, 0.2, 0.18, 0.62)
	)
	ring.visible = true


func _on_gather_started(target: Node, preview: Dictionary) -> void:
	(get_node("TreeHoverRing") as Node3D).visible = false
	(get_node("ResultLabel") as Label3D).visible = false
	(get_node("Canvas/StatusLabel") as Control).visible = false
	_result_time_remaining = 0.0
	_status_time_remaining = 0.0
	_impact_played = false
	_target = target as Node3D
	if _target == null:
		return
	var ring := get_node("TargetRing") as Node3D
	ring.global_position = _target.global_position + Vector3.UP * 0.04
	ring.visible = true
	var remaining := get_node("RemainingLabel") as Label3D
	remaining.text = "%s %d/%d" % [
		_target.call("get_display_name") if _target.has_method("get_display_name") else "资源",
		int(preview.get("remaining_before", 0)),
		int(_target.get("max_units")) if _has_property(_target, "max_units") else 0,
	]
	remaining.global_position = _target.global_position + Vector3.UP * 1.25
	remaining.visible = true
	var tip := get_node("Canvas/AutoEquipTip") as Label
	tip.text = "自动装备%s" % ("斧头" if str(preview.get("tool_id")) == "axe" else "镐")
	tip.visible = true


func _on_state_changed(state: int, context: Dictionary) -> void:
	if _controller == null:
		return
	var state_name := str(_controller.State.keys()[state])
	if state_name == "ACTING" and _target != null:
		(get_node("Canvas/ProgressRing") as Control).visible = true
		if _tool_visual != null:
			var actor := _controller.call("get_actor") as Node3D
			if actor != null and str(_controller._preview.get("tool_id", "")) == "axe" and _target.has_method("begin_felling"):
				_tool_visual.global_position = tree_axe_anchor(_target.global_position, actor.global_position)
				_target.call("begin_felling", 1)
			elif actor != null:
				var direction := _target.global_position - actor.global_position
				direction.y = 0.0
				if direction.is_zero_approx():
					direction = Vector3.RIGHT
				_tool_visual.global_position = actor.global_position + direction.normalized() * 0.46 + Vector3.UP * 0.42
			else:
				_tool_visual.global_position = _target.global_position + Vector3(0.58, 0.15, 0.0)
			_tool_visual.play_tool(str(_controller._preview.get("tool_id", "")))
	elif state_name in ["CANCELLED", "FAILED", "IDLE"] and context.get("target") == null:
		if _tool_visual != null:
			_tool_visual.cancel_tool()


func _on_gather_progress(_target_node: Node, value: float) -> void:
	(get_node("Canvas/ProgressRing") as GatheringProgressRing).set_progress(value)
	if _target_node != null and _target_node.has_method("set_felling_progress"):
		_target_node.call("set_felling_progress", value)
	if _tool_visual != null:
		_tool_visual.set_action_progress(value)
	if not _impact_played and value >= 0.46:
		_impact_played = true
		_play_impact_feedback(_target_node)


func _on_gather_completed(target: Node, result: Dictionary) -> void:
	var label := get_node("ResultLabel") as Label3D
	label.text = "+%d %s" % [
		int(result.get("quantity", 1)),
		_item_display_name(str(result.get("item_id", ""))),
	]
	if _has_property(target, "remaining_units") and int(target.get("remaining_units")) <= 0 and target.has_method("get_respawn_day"):
		label.text += " · 第%d天刷新" % int(target.call("get_respawn_day"))
	if target is Node3D:
		label.global_position = target.global_position + Vector3.UP * 1.55
	label.visible = true
	_result_time_remaining = 1.6
	_hide_active_feedback()


func _on_gather_failed(target_node: Node, reason: String) -> void:
	if target_node != null and target_node.has_method("cancel_felling"):
		target_node.call("cancel_felling")
	var status := get_node("Canvas/StatusLabel") as Label
	var message := error_message(reason)
	if reason == "tool_broken" and target_node != null and _has_property(target_node, "required_tool"):
		message = "斧头已损坏" if str(target_node.get("required_tool")) == "axe" else "镐已损坏"
	status.text = "⚠ %s" % message
	status.visible = true
	_status_time_remaining = 1.8
	_hide_active_feedback()


func _on_gather_cancelled(_reason: String) -> void:
	if _target != null and _target.has_method("cancel_felling"):
		_target.call("cancel_felling")
	_hide_active_feedback()


func _hide_active_feedback() -> void:
	(get_node("TargetRing") as Node3D).visible = false
	(get_node("PathPreview") as MeshInstance3D).visible = false
	(get_node("Canvas/ProgressRing") as Control).visible = false
	(get_node("Canvas/AutoEquipTip") as Control).visible = false
	(get_node("RemainingLabel") as Label3D).visible = false
	if _tool_visual != null:
		_tool_visual.cancel_tool()
	_target = null


func _item_display_name(item_id: String) -> String:
	var game_data := get_node_or_null("/root/GameData") if is_inside_tree() else null
	if game_data != null and game_data.has_method("get_item"):
		var item: Variant = game_data.call("get_item", item_id)
		if item is Dictionary and not str(item.get("name", "")).is_empty():
			return str(item.get("name"))
	return item_id if not item_id.is_empty() else "资源"


func _update_screen_positions() -> void:
	if _target == null or not is_instance_valid(_target) or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(_target.global_position):
		return
	var projected_center := camera.unproject_position(_target.global_position + Vector3.UP * 2.0)
	var remaining_center := camera.unproject_position(_target.global_position + Vector3.UP * 1.25)
	var target_screen := progress_center_with_label_clearance(projected_center, remaining_center)
	(get_node("Canvas/ProgressRing") as Control).position = target_screen - Vector2(48.0, 48.0)
	if _controller != null and _controller.has_method("get_actor"):
		var actor := _controller.call("get_actor") as Node3D
		if actor != null and is_instance_valid(actor) and not camera.is_position_behind(actor.global_position):
			var actor_screen := camera.unproject_position(actor.global_position + Vector3.UP * 1.72)
			(get_node("Canvas/AutoEquipTip") as Control).position = actor_screen - Vector2(220.0, 0.0)


func _play_impact_feedback(target: Node) -> void:
	if not target is Node3D:
		return
	var target_node := target as Node3D
	var visual := target_node.get_node_or_null("Sprite3D") as Node3D
	if visual == null:
		visual = target_node.get_node_or_null("Visual") as Node3D
	if visual != null and target_node.is_inside_tree():
		var original_position := visual.position
		var shake := target_node.create_tween()
		shake.tween_property(visual, "position:x", original_position.x + 0.07, 0.045)
		shake.tween_property(visual, "position:x", original_position.x - 0.05, 0.055)
		shake.tween_property(visual, "position:x", original_position.x, 0.07)

	var particles := CPUParticles3D.new()
	particles.name = "GatherImpact"
	particles.one_shot = true
	particles.amount = 9
	particles.lifetime = 0.42
	particles.explosiveness = 0.92
	particles.direction = Vector3.UP
	particles.spread = 62.0
	particles.initial_velocity_min = 0.45
	particles.initial_velocity_max = 1.05
	particles.gravity = Vector3(0.0, -2.0, 0.0)
	particles.position.y = 0.48
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(0.07, 0.07)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = (
		Color("b97832")
		if _has_property(target, "required_tool") and str(target.get("required_tool")) == "axe"
		else Color("908a80")
	)
	particle_mesh.material = material
	particles.mesh = particle_mesh
	target_node.add_child(particles)
	if target_node.is_inside_tree():
		particles.finished.connect(particles.queue_free)
	particles.emitting = true


func _build_target_ring() -> void:
	var ring := get_node("TargetRing") as Node3D
	if ring.get_child_count() > 0:
		return
	var mesh_instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.72
	mesh_instance.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.82, 0.30, 0.64)
	mesh_instance.material_override = material
	ring.add_child(mesh_instance)
	ring.visible = false


func _build_tree_hover_ring() -> void:
	var ring := get_node("TreeHoverRing") as Node3D
	if ring.get_child_count() > 0:
		return
	var mesh_instance := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 0.82
	mesh_instance.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.25, 0.9, 0.38, 0.62)
	mesh_instance.material_override = material
	ring.add_child(mesh_instance)
	ring.visible = false


func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
