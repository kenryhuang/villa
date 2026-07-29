extends RefCounted

const HudScene = preload("res://scenes/ui/hud.tscn")


class ToolDouble:
	extends RefCounted

	func switch_tool(_tool_type: int) -> void:
		pass


class SeasonDouble:
	extends Node

	const DAYS_PER_SEASON := 7
	var current_season := 0
	var current_day := 1
	var hour := 6
	var minute := 0


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var hud = HudScene.instantiate()
	tree.root.add_child(hud)
	var has_action_bar_api := hud.has_method("configure_action_bar")
	assertions.truthy(has_action_bar_api, "HUD exposes action bar configuration")
	if not has_action_bar_api:
		hud.free()
		return

	var inventory_script = load("res://scripts/systems/inventory_system.gd")
	var controller_script = load("res://scripts/actors/player_action_controller.gd")
	var inventory = inventory_script.new()
	inventory.add_item("grain_seed", 2)
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.configure(null, null, null, null, ToolDouble.new(), inventory)
	hud.configure_action_bar(controller, inventory)
	var season := SeasonDouble.new()
	tree.root.add_child(season)
	assertions.truthy(
		hud.has_method("configure_season_system"),
		"HUD accepts the main scene season system"
	)
	if hud.has_method("configure_season_system"):
		hud.call("configure_season_system", season)
		season.current_day = 2
		hud.call("_on_day_changed", 2)
		assertions.equal(hud.season_label.text, "春 2/7", "HUD refreshes the scene-local day")

	var quick_bar := hud.get_node("BottomBar/QuickBar")
	assertions.equal(quick_bar.get_child_count(), 6, "HUD keeps six action slots")
	for child in quick_bar.get_children():
		assertions.truthy(child is Button, "every action slot is clickable")
	assertions.equal(
		(quick_bar.get_child(0) as Button).text,
		"1\n锄头",
		"first slot labels the hoe"
	)
	assertions.equal(
		(quick_bar.get_child(5) as Button).text,
		"6\n谷物种子 x2",
		"seed slot shows inventory count"
	)

	var emitted_indices: Array[int] = []
	hud.quick_slot_selected.connect(
		func(index: int) -> void:
			emitted_indices.append(index)
	)
	(quick_bar.get_child(5) as Button).pressed.emit()
	assertions.equal(emitted_indices, [5], "clicking seed slot emits index five")
	assertions.equal(controller.get_selected_slot(), 5, "clicking seed slot changes selection")
	assertions.equal(hud.tool_label.text, "谷物种子", "HUD shows selected seed action")
	assertions.truthy(
		(quick_bar.get_child(5) as Button).button_pressed,
		"selected seed slot is highlighted"
	)
	assertions.truthy(controller.deselect_slot(), "selected HUD action can be cancelled")
	assertions.equal(hud.tool_label.text, "未选择工具", "HUD shows cancelled tool state")
	for child in quick_bar.get_children():
		assertions.truthy(
			not (child as Button).button_pressed,
			"cancelled tool leaves every action button unpressed"
		)

	inventory.remove_item("grain_seed", 1)
	hud.refresh_action_bar()
	assertions.equal(
		(quick_bar.get_child(5) as Button).text,
		"6\n谷物种子 x1",
		"seed count refreshes after inventory change"
	)

	controller.free()
	inventory.free()
	season.free()
	hud.free()
