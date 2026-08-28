extends RefCounted

const ControllerScript = preload("res://scripts/actors/npc_farm_action_controller.gd")
const NpcScene = preload("res://scenes/actors/npc.tscn")


class FakeFarm:
	extends Node
	signal work_available
	var record := {
		"agent_id": "farmer_ahe",
		"idempotency_key": "v2:work",
		"tool_name": "till",
		"arguments": {"plot": 0},
	}
	var cell := GridCell.new()
	var started := false
	var completed := false

	func _init() -> void:
		cell.gx = 1
		cell.gz = 1

	func peek_work() -> Dictionary:
		return record.duplicate(true) if not completed else {}

	func get_plot_cell(_agent_id: String, _plot: int) -> GridCell:
		return cell

	func mark_work_started(_key: String) -> bool:
		started = true
		return true

	func complete_work(_key: String) -> Dictionary:
		completed = true
		return {"ok": true}

	func fail_work(_key: String, _code: String) -> Dictionary:
		completed = true
		return {"ok": false}


class FakeActor:
	extends Node3D
	var arrived := false
	var moving := false

	func begin_agent_work(_target: Vector3) -> bool:
		moving = true
		return true

	func is_agent_work_arrived() -> bool:
		return arrived

	func stop_agent_work() -> void:
		moving = false

	func face_world_point(_target: Vector3) -> void:
		pass


class FakeVisual:
	extends Node
	signal finished
	var played := false
	var received_texture: Texture2D

	func play(_action: String, texture: Texture2D = null) -> bool:
		played = true
		received_texture = texture
		return true


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var npc = NpcScene.instantiate()
	tree.root.add_child(npc)
	for method_name in [
		"begin_agent_work", "has_agent_work_target", "is_agent_work_arrived",
		"stop_agent_work", "face_world_point",
	]:
		assertions.truthy(npc.has_method(method_name), "NPC exposes %s" % method_name)
	assertions.truthy(npc.get_node_or_null("FarmActionVisual") != null, "NPC scene owns farm action visual")
	npc.queue_free()

	var farm := FakeFarm.new()
	var actor := FakeActor.new()
	var visual := FakeVisual.new()
	var controller := ControllerScript.new()
	tree.root.add_child(farm)
	tree.root.add_child(actor)
	tree.root.add_child(visual)
	tree.root.add_child(controller)
	assertions.truthy(controller.configure(farm, actor, visual), "farm action controller configures")
	assertions.truthy(
		controller.call("_action_texture", {
			"tool_name": "plant",
			"arguments": {"seed_item_id": "carrot_seed"},
		}) != null,
		"plant feedback resolves the selected hand-painted seed texture"
	)
	await tree.process_frame
	assertions.equal(controller.get_work_state(), "moving", "queued work starts movement")
	assertions.truthy(actor.moving, "controller gives actor a movement target")
	assertions.truthy(not farm.started and not farm.completed, "movement does not mutate work")
	actor.arrived = true
	await tree.process_frame
	assertions.equal(controller.get_work_state(), "animating", "arrival starts action feedback")
	assertions.truthy(farm.started and not farm.completed, "arrival reserves work without committing")
	assertions.truthy(visual.played, "arrival plays visual feedback")
	visual.finished.emit()
	await tree.process_frame
	assertions.truthy(farm.completed, "visual completion commits authoritative work")
	assertions.equal(controller.get_work_state(), "idle", "controller returns idle after commit")
	controller.queue_free()
	visual.queue_free()
	actor.queue_free()
	farm.queue_free()
