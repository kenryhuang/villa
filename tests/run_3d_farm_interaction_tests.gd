extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func():
		push_error("3D farm interaction test timed out")
		quit(1)
	)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1440, 960)
	var preview := (load("res://scenes/preview/farm_3d_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	await process_frame
	_check(preview.has_node("FarmSession"), "Default 3D game starts the real farming session")
	_check(preview.has_node("FarmInteraction"), "Default 3D game provides playable farming controls")
	_check(preview.has_node("PaintedMeadow"), "Default 3D game integrates painted meadow")
	if failures.is_empty():
		var session = preview.get_node("FarmSession")
		var interaction = preview.get_node("FarmInteraction")
		var player = preview.get_node("Player")
		session.season.set_process(false)
		var cell: GridCell = session.grid.get_cell(19, 16)
		player.global_position = Vector3(0.2, 0.0, 3.3)
		await _frames(12)
		_check(cell.state == GridCell.State.WASTELAND, "New nearby ground starts uncultivated")
		var camera: Camera3D = preview.get_viewport().get_camera_3d()
		var pointer := camera.unproject_position(cell.world_position_3d())
		_check(interaction.cell_at_pointer(pointer) == cell, "Visible ground ray selects the correct one-meter cell")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = pointer
		root.push_input(click, true)
		await _frames(36)
		_check(cell.state == GridCell.State.FARMLAND, "Real left-click with hoe cultivates the pointed ground")
		if cell.state != GridCell.State.FARMLAND:
			preview.queue_free()
			await process_frame
			quit(1)
			return
		var meadow = preview.get_node("PaintedMeadow")
		var records: Array = meadow._by_cell.get(Vector2i(cell.gx, cell.gz), [])
		_check(not records.is_empty(), "Interaction test cell contains grass before cultivation")
		for record_index in records:
			var record: Dictionary = meadow._instances[int(record_index)]
			_check(record.get("hidden", false), "Cultivation event removes grass from the actual targeted cell")
		var seed_count: int = session.inventory.get_item_count("grain_seed")
		var key := InputEventKey.new()
		key.keycode = KEY_2
		key.pressed = true
		Input.parse_input_event(key)
		await _frames(2)
		_check(interaction.mode == "seed", "Number key selects the seed tool")
		var plant_result: Dictionary = interaction.perform(cell)
		_check(plant_result.get("ok", false) and cell.crop_instance != null, "Selected seed plants a real crop")
		_check(session.inventory.get_item_count("grain_seed") == seed_count - 1, "Planting spends one inventory seed")
		await _frames(36)
		interaction.select_mode("harvest")
		var early: Dictionary = interaction.perform(cell)
		_check(not early.get("ok", false) and cell.crop_instance != null, "Early harvest preserves the living crop")
		session.season.advance_game_minutes(54)
		await _frames(2)
		_check(cell.crop_instance != null and not cell.crop_instance.is_mature(), "Original clock advances the intermediate growth stage")
		session.season.advance_game_minutes(54)
		await _frames(2)
		_check(cell.crop_instance.is_mature(), "Original clock ripens the crop in 108 game minutes")
		var grain_count: int = session.inventory.get_item_count("grain")
		var harvest_result: Dictionary = interaction.perform(cell)
		_check(harvest_result.get("ok", false) and cell.crop_instance == null, "Harvest clears the crop from the live scene")
		_check(session.inventory.get_item_count("grain") >= grain_count + 2, "Harvest deposits original yield into inventory")
		_check(cell.state == GridCell.State.FARMLAND, "Harvested soil remains ready for another planting")
		await _frames(36)
		interaction.hud.buttons[0].pressed.emit()
		_check(interaction.mode == "hoe", "HUD button switches back to hoe")
		var far_cell: GridCell = session.grid.get_cell(30, 20)
		var stamina_before: int = root.get_node("GameState").player_state.stamina
		_check(not interaction.perform(far_cell).get("ok", false), "Faraway clicks cannot cultivate remote land")
		_check(root.get_node("GameState").player_state.stamina == stamina_before, "Rejected remote action consumes no stamina")
		var day_before: int = session.season.total_days
		root.get_node("GameState").player_state.stamina = 5
		interaction.hud.rest_requested.emit()
		_check(session.season.total_days == day_before + 1, "HUD rest action advances the original day clock")
		_check(root.get_node("GameState").player_state.stamina == 100, "Rest restores stamina for the next farming day")
	preview.queue_free()
	await process_frame
	print("3D FARM INTERACTION: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for index in count:
		await physics_frame
	await process_frame
