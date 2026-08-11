extends RefCounted

const VISUAL_SCRIPT_PATH := "res://scripts/buildings/building_maintenance_visual.gd"
const WARNING_ASSET_PATH := "res://assets/buildings/maintenance/maintenance_warning.svg"
const BROKEN_ASSET_PATH := "res://assets/buildings/maintenance/maintenance_broken.svg"


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.truthy(ResourceLoader.exists(VISUAL_SCRIPT_PATH), "maintenance visual script exists")
	assertions.truthy(ResourceLoader.exists(WARNING_ASSET_PATH), "warning damage art exists")
	assertions.truthy(ResourceLoader.exists(BROKEN_ASSET_PATH), "broken damage art exists")
	var script := load(VISUAL_SCRIPT_PATH) as Script
	if script == null:
		return
	var visual := script.new() as Node3D
	tree.root.add_child(visual)
	assertions.truthy(visual.call("configure", Vector2(2.0, 2.0), Vector2(0.5, 0.9375)), "maintenance visual configures")
	assertions.equal(visual.process_mode, Node.PROCESS_MODE_ALWAYS, "repair animation runs while UI pauses")
	visual.call("set_state", "normal", 0.0)
	assertions.truthy(not visual.get_node("WarningOverlay").visible, "normal hides warning damage")
	assertions.truthy(not visual.get_node("BrokenOverlay").visible, "normal hides broken damage")
	visual.call("set_state", "warning", 0.0)
	assertions.truthy(visual.get_node("WarningOverlay").visible, "warning shows subtle damage")
	visual.call("set_state", "overdue", 0.0)
	assertions.truthy(visual.get_node("BrokenOverlay").visible, "overdue shows broken damage")
	visual.call("set_state", "repairing", 1.5)
	var hammer := visual.get_node("RepairFeedback/HammerPivot") as Node3D
	assertions.truthy(hammer.visible, "repairing shows painted hammer")
	var rotation_before := hammer.rotation.z
	visual.call("advance_animation", 0.3)
	assertions.truthy(not is_equal_approx(hammer.rotation.z, rotation_before), "repair hammer swings around its handle")
	assertions.truthy(not visual.get_node("RepairFeedback/Progress").visible, "repair omits construction progress disk")
	visual.free()
