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
}

var _controller
var _tool_visual: ToolSwingVisual
var _target: Node3D


func _ready() -> void:
	_build_target_ring()
	(get_node("Canvas/ProgressRing") as Control).visible = false
	(get_node("Canvas/AutoEquipTip") as Control).visible = false
	(get_node("Canvas/StatusLabel") as Control).visible = false
	(get_node("RemainingLabel") as Label3D).visible = false
	(get_node("ResultLabel") as Label3D).visible = false


func bind(controller, tool_visual: ToolSwingVisual) -> bool:
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
	return true


func error_message(reason: String) -> String:
	return str(ERROR_MESSAGES.get(reason, "操作失败"))


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


func _on_gather_started(target: Node, preview: Dictionary) -> void:
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
			_tool_visual.global_position = _target.global_position + Vector3(0.58, 0.15, 0.0)
			_tool_visual.play_tool(str(_controller._preview.get("tool_id", "")))
	elif state_name in ["CANCELLED", "FAILED", "IDLE"] and context.get("target") == null:
		if _tool_visual != null:
			_tool_visual.cancel_tool()


func _on_gather_progress(_target_node: Node, value: float) -> void:
	(get_node("Canvas/ProgressRing") as GatheringProgressRing).set_progress(value)
	if _tool_visual != null:
		_tool_visual.set_action_progress(value)


func _on_gather_completed(target: Node, result: Dictionary) -> void:
	var label := get_node("ResultLabel") as Label3D
	label.text = "+1 %s" % str(result.get("item_id", "资源"))
	if target is Node3D:
		label.global_position = target.global_position + Vector3.UP * 1.55
	label.visible = true
	_hide_active_feedback()


func _on_gather_failed(_target_node: Node, reason: String) -> void:
	var status := get_node("Canvas/StatusLabel") as Label
	status.text = "⚠ %s" % error_message(reason)
	status.visible = true
	_hide_active_feedback()


func _on_gather_cancelled(_reason: String) -> void:
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


func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
