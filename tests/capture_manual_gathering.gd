extends SceneTree

const OUTPUT_DIR := "res://.godot/manual-gathering-validation"
const STATES := [
	"tree_path",
	"tree_action",
	"tree_hover_green",
	"tree_hover_red",
	"tree_frame_1",
	"tree_frame_2",
	"tree_frame_3",
	"tree_fall_left",
	"tree_fall_right",
	"tree_result_stump",
	"ore_stages",
	"inventory_full",
	"unreachable",
]
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3000, 2000)]

var _failed := false


func _init() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("manual gathering capture requires the Windows display driver")
		return
	var selected_states: Array = STATES.duplicate()
	var selected_sizes: Array = SIZES.duplicate()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--state="):
			var requested_state := argument.trim_prefix("--state=")
			if requested_state not in STATES:
				_fail("unknown capture state: %s" % requested_state)
				return
			selected_states = [requested_state]
		elif argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x", false)
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				_fail("invalid capture size: %s" % argument)
				return
			var requested_size := Vector2i(int(parts[0]), int(parts[1]))
			if requested_size not in SIZES:
				_fail("unsupported capture size: %s" % requested_size)
				return
			selected_sizes = [requested_size]
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("cannot create capture directory: %s" % error_string(directory_error))
		return
	var captures: Array[String] = []
	for state_id in selected_states:
		for viewport_size in selected_sizes:
			root.content_scale_size = viewport_size
			root.size = viewport_size
			var main := await _new_main()
			if main == null or not await _prepare_state(main, state_id):
				if main != null:
					current_scene = null
					main.free()
				_fail("cannot prepare capture state: %s" % state_id)
				return
			for _frame in range(8):
				await process_frame
				await physics_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			if image == null or image.is_empty():
				_fail("empty capture: %s" % state_id)
				return
			if image.get_size() != viewport_size:
				_fail("wrong capture size for %s: %s" % [state_id, image.get_size()])
				return
			var file_name := "%s_%dx%d.png" % [state_id, viewport_size.x, viewport_size.y]
			var save_error := image.save_png(output_path.path_join(file_name))
			if save_error != OK:
				_fail("cannot save %s: %s" % [file_name, error_string(save_error)])
				return
			captures.append(file_name)
			print("CAPTURE_PROGRESS: %s" % file_name)
			current_scene = null
			main.free()
			await process_frame
	if captures.size() != selected_states.size() * selected_sizes.size():
		_fail("capture count mismatch")
		return
	print("PASS: %d deterministic manual gathering captures in %s" % [captures.size(), output_path])
	quit(0)


func _new_main() -> Node:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		return null
	var main := packed.instantiate()
	main.load_save_on_start = false
	root.add_child(main)
	current_scene = main
	for _frame in range(5):
		await process_frame
		await physics_frame
	return main


func _prepare_state(main: Node, state_id: String) -> bool:
	match state_id:
		"tree_path":
			var tree := _requestable_resource(main, "tree")
			if tree == null:
				return false
			_focus(main, [main.player.global_position, tree.global_position], 10.5)
			return true
		"tree_action":
			var tree := _requestable_resource(main, "tree")
			if tree == null or not _arrive(main):
				return false
			main.gathering_controller._process(0.48)
			_focus(main, [tree.global_position], 6.0)
			return main.gathering_controller.get_state_name() == "ACTING"
		"tree_hover_green":
			var tree := _find_resource(main, "tree")
			if tree == null:
				return false
			main.gathering_feedback.show_tree_hover(tree, true)
			_focus(main, [tree.global_position], 6.0)
			return true
		"tree_hover_red":
			var tree := _find_decorative_tree(main)
			if tree == null:
				return false
			main.gathering_feedback.show_tree_hover(tree, false)
			_focus(main, [tree.global_position], 6.0)
			return true
		"tree_frame_1", "tree_frame_2", "tree_frame_3":
			var tree := _requestable_resource(main, "tree")
			if tree == null or not _arrive(main):
				return false
			var elapsed: float = float({"tree_frame_1": 0.20, "tree_frame_2": 1.0, "tree_frame_3": 1.7}[state_id])
			main.gathering_controller._process(elapsed)
			_focus(main, [tree.global_position], 6.0)
			return main.gathering_controller.get_state_name() == "ACTING"
		"tree_fall_left", "tree_fall_right":
			var tree := _find_resource(main, "tree")
			if tree == null:
				return false
			var direction: int = -1 if state_id == "tree_fall_left" else 1
			tree.begin_felling(direction)
			tree.set_felling_progress(0.85)
			_focus(main, [tree.global_position], 6.0)
			return tree.get_felling_frame() == 2
		"tree_result_stump":
			var tree := _find_resource(main, "tree")
			if tree == null:
				return false
			if not main.gathering_controller.request_gather(tree) or not _arrive(main):
				return false
			main.gathering_controller._process(2.0)
			_focus(main, [tree.global_position], 5.5)
			return tree.remaining_units == 0
		"ore_stages":
			return _prepare_ore_gallery(main)
		"inventory_full":
			main.inventory_system.reset_slots()
			for index in range(main.inventory_system.slots.size()):
				main.inventory_system.slots[index] = {"item_id": "grain_seed", "quantity": 99}
			var tree := _find_resource(main, "tree")
			if tree == null:
				return false
			var rejected: bool = not bool(main.gathering_controller.request_gather(tree))
			_focus(main, [tree.global_position], 6.5)
			return rejected and (main.gathering_feedback.get_node("Canvas/StatusLabel") as Label).visible
		"unreachable":
			var ore := _find_resource(main, "gold_ore")
			if ore == null:
				return false
			var target_cell: Vector2i = main.grid_system.world_to_grid(
				ore.global_position.x, ore.global_position.z
			)
			for z in range(target_cell.y - 4, target_cell.y + 5):
				for x in range(target_cell.x - 4, target_cell.x + 5):
					main.grid_system.set_navigation_blocker(
						"capture:%d:%d" % [x, z], Vector2i(x, z), true
					)
			var rejected: bool = not bool(main.gathering_controller.request_gather(ore))
			_focus(main, [ore.global_position], 7.0)
			return rejected and (main.gathering_feedback.get_node("Canvas/StatusLabel") as Label).visible
	return false


func _requestable_resource(main: Node, resource_type: String) -> Node3D:
	for candidate in main.world.get_gatherable_nodes():
		if str(candidate.get("resource_type")) != resource_type:
			continue
		if main.gathering_controller.request_gather(candidate):
			return candidate as Node3D
	return null


func _find_resource(main: Node, resource_type: String) -> Node3D:
	for candidate in main.world.get_gatherable_nodes():
		if str(candidate.get("resource_type")) == resource_type:
			return candidate as Node3D
	return null


func _find_decorative_tree(main: Node) -> Node3D:
	for candidate in main.world.get_navigation_obstacle_nodes():
		if candidate.has_method("is_chop_eligible") and not bool(candidate.call("is_chop_eligible")):
			return candidate as Node3D
	return null


func _arrive(main: Node) -> bool:
	if main.player._auto_path.is_empty():
		return false
	var endpoint: Vector3 = main.player._auto_path[-1]
	main.player._auto_path_index = main.player._auto_path.size() - 1
	main.player.global_position = endpoint
	main.player._update_auto_movement(0.0)
	return main.gathering_controller.get_state_name() == "ACTING"


func _prepare_ore_gallery(main: Node) -> bool:
	var ores: Array[Node3D] = []
	for resource_type in ["stone", "copper_ore", "gold_ore"]:
		var ore := _find_resource(main, resource_type)
		if ore == null:
			return false
		ores.append(ore)
	var anchor := Vector3(0.0, main.world.get_height_at(0.0, 0.0), 0.0)
	var labels := ["完整矿脉", "受损矿脉", "碎石残骸"]
	for index in range(ores.size()):
		var ore := ores[index]
		var x := float(index - 1) * 2.25
		ore.global_position = anchor + Vector3(x, 0.0, 0.0)
		if index == 0:
			ore.remaining_units = ore.max_units
		elif index == 1:
			ore.remaining_units = 1
		else:
			ore.remaining_units = 0
			ore._respawn_day = main.season_system.total_days + ore.respawn_days
		ore.call("_update_visual_stage")
		ore.call("_set_gather_active", ore.remaining_units > 0)
		var label := Label3D.new()
		label.text = labels[index]
		label.font_size = 28
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, 1.35, 0.0)
		ore.add_child(label)
	_focus(main, [anchor], 7.5)
	return true


func _focus(main: Node, points: Array, orthographic_size: float) -> void:
	var focus := Marker3D.new()
	focus.name = "ManualGatheringCaptureFocus"
	main.add_child(focus)
	var total := Vector3.ZERO
	for point in points:
		total += point as Vector3
	focus.global_position = total / float(points.size())
	main.camera_rig.orthographic_size = orthographic_size
	main.camera_rig.set_target(focus)


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	quit(1)
