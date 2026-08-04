extends RefCounted

const CONTROLLER_PATH := "res://scripts/systems/gathering_controller.gd"


class PlayerDouble:
	extends Node3D

	signal manual_movement_requested
	signal auto_path_finished
	signal auto_path_blocked

	var started_paths: Array = []
	var stopped_reasons: Array[String] = []
	var active := false
	var interaction_range := 2.5

	func start_auto_path(points: Array[Vector3]) -> bool:
		started_paths.append(points.duplicate())
		active = not points.is_empty()
		return active

	func stop_auto_movement(reason: String) -> void:
		stopped_reasons.append(reason)
		active = false

	func has_auto_movement() -> bool:
		return active


class PathfinderDouble:
	extends RefCounted

	var calls := 0
	var path: Array[Vector3] = [Vector3.ZERO, Vector3.RIGHT]

	func find_path_to_interaction(
		_start: Vector3,
		_target: Node3D,
		_range: float
	) -> Array[Vector3]:
		calls += 1
		return path.duplicate()


class ToolsDouble:
	extends RefCounted

	var preview_allowed := true
	var preview_reason := ""
	var selected_tool := ""
	var commit_calls := 0

	func preview_gather_unit(_target: Node) -> Dictionary:
		return {
			"allowed": preview_allowed,
			"reason": preview_reason,
			"tool_id": "pickaxe",
			"item_id": "stone",
			"quantity": 1,
			"stamina_cost": 8,
			"durability_cost": 1,
			"remaining_before": 4,
			"remaining_after": 3,
		}

	func commit_gather_unit(_target: Node) -> Dictionary:
		commit_calls += 1
		var result := preview_gather_unit(_target)
		result.allowed = true
		result.reason = ""
		return result

	func switch_tool_by_id(tool_id: String) -> bool:
		selected_tool = tool_id
		return tool_id in ["axe", "pickaxe"]


class SeasonDouble:
	extends RefCounted

	var owner: Object
	var advanced_minutes := 0

	func acquire_action_clock_lock(value: Object) -> bool:
		if owner != null:
			return false
		owner = value
		return true

	func release_action_clock_lock(value: Object) -> bool:
		if owner != value:
			return false
		owner = null
		return true

	func advance_game_minutes(minutes: int) -> void:
		advanced_minutes += minutes


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.truthy(ResourceLoader.exists(CONTROLLER_PATH), "manual gathering provides a controller")
	if not ResourceLoader.exists(CONTROLLER_PATH):
		return
	var controller_script := load(CONTROLLER_PATH) as Script
	var player := PlayerDouble.new()
	var pathfinder := PathfinderDouble.new()
	var tools := ToolsDouble.new()
	var season := SeasonDouble.new()
	var controller = controller_script.new()
	tree.root.add_child(player)
	tree.root.add_child(controller)
	controller.action_duration = 1.2
	assertions.truthy(controller.configure(player, pathfinder, tools, season), "controller accepts gathering dependencies")
	var completed: Array = []
	var failures: Array[String] = []
	var cancellations: Array[String] = []
	var progress_values: Array[float] = []
	controller.gather_completed.connect(func(_target: Node, result: Dictionary) -> void: completed.append(result))
	controller.gather_failed.connect(func(_target: Node, reason: String) -> void: failures.append(reason))
	controller.gather_cancelled.connect(func(reason: String) -> void: cancellations.append(reason))
	controller.gather_progress.connect(func(_target: Node, progress: float) -> void: progress_values.append(progress))

	var target := Node3D.new()
	tree.root.add_child(target)
	assertions.truthy(controller.request_gather(target), "valid target starts a gather command")
	assertions.equal(tools.selected_tool, "pickaxe", "request automatically equips the required tool")
	assertions.equal(player.started_paths.size(), 1, "request starts one auto path")
	assertions.equal(controller.get_state_name(), "MOVING", "request waits in moving state")
	player.active = false
	player.auto_path_finished.emit()
	assertions.equal(controller.get_state_name(), "ACTING", "arrival begins the action after recheck")
	assertions.equal(season.owner, controller, "action owns a clock lock")
	controller._process(0.6)
	assertions.equal(tools.commit_calls, 0, "half-finished animation does not commit")
	controller._process(0.6)
	assertions.equal(tools.commit_calls, 1, "complete animation commits exactly once")
	assertions.equal(season.advanced_minutes, 10, "successful action advances ten minutes")
	assertions.equal(season.owner, null, "successful action releases its clock lock")
	assertions.equal(completed.size(), 1, "successful action emits completion once")
	assertions.equal(controller.get_state_name(), "IDLE", "single-unit action stops when complete")
	assertions.truthy(not progress_values.is_empty(), "action emits circular progress values")

	var replacement := Node3D.new()
	tree.root.add_child(replacement)
	assertions.truthy(controller.request_gather(target), "replacement fixture starts first command")
	assertions.truthy(controller.request_gather(replacement), "latest target replaces old command")
	assertions.truthy(player.stopped_reasons.has("replaced"), "replacement cancels old movement")
	player.manual_movement_requested.emit()
	assertions.equal(controller.get_state_name(), "IDLE", "manual movement cancels gathering")
	assertions.equal(cancellations[-1], "manual_input", "manual cancellation reports a stable reason")
	assertions.equal(tools.commit_calls, 1, "manual cancellation causes no commit")

	assertions.truthy(controller.request_gather(target), "blocked fixture starts")
	player.auto_path_blocked.emit()
	assertions.equal(pathfinder.calls, 5, "first blockage performs one replacement path query")
	player.auto_path_blocked.emit()
	assertions.equal(failures[-1], "unreachable", "second blockage fails as unreachable")
	assertions.equal(controller.get_state_name(), "IDLE", "unreachable command returns idle")

	assertions.truthy(controller.request_gather(target), "arrival recheck fixture starts")
	tools.preview_allowed = false
	tools.preview_reason = "inventory_full"
	player.auto_path_finished.emit()
	assertions.equal(failures[-1], "inventory_full", "arrival repeats transaction preflight")
	assertions.equal(tools.commit_calls, 1, "failed arrival recheck does not commit")
	tools.preview_allowed = true
	tools.preview_reason = ""

	assertions.truthy(controller.request_gather(target), "action cancel fixture starts")
	player.auto_path_finished.emit()
	controller.cancel_current("mode_changed")
	assertions.equal(season.owner, null, "action cancellation releases the clock lock")
	assertions.equal(tools.commit_calls, 1, "cancelled animation causes no commit")

	target.free()
	replacement.free()
	controller.free()
	player.free()
