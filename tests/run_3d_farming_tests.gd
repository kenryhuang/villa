extends SceneTree

const TestAssertScript = preload("res://tests/test_assert.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var assertions := TestAssertScript.new()
	var path := "res://scripts/farm3d/farm_session.gd"
	assertions.truthy(ResourceLoader.exists(path), "3D farm session adapter exists")
	if ResourceLoader.exists(path):
		var script = load(path)
		var game_state: Node = root.get_node("GameState")
		var event_bus: Node = root.get_node("EventBus")
		var cell_events: Array = []
		event_bus.cell_state_changed.connect(func(gx: int, gz: int, state: int): cell_events.append(Vector3i(gx, gz, state)))
		var session = script.new()
		session.auto_restore = false
		session.auto_save = false
		root.add_child(session)
		var player := Node3D.new()
		player.position = Vector3(0.5, 0.0, -2.5)
		root.add_child(player)
		assertions.truthy(session.configure(player), "session configures against a flat Node3D player")
		var cell: GridCell = session.grid.get_cell_at_world(0.5, -2.5)
		assertions.truthy(cell != null, "flat grid exposes original coordinate cells")
		if cell != null:
			assertions.truthy(session.act(cell, "hoe").get("ok", false), "near hoe opens a plot")
			assertions.truthy(not cell_events.is_empty(), "flat grid forwards hoe state changes to EventBus grass masking")
			assertions.truthy(session.act(cell, "seed").get("ok", false), "seed spends one grain seed and plants grain")
			assertions.truthy(session.farming._crop_visuals.is_empty(), "3D farming suppresses original fallback crop cuboids")
			assertions.equal(session.act(cell, "harvest").get("reason", ""), "not_mature", "immature grain cannot harvest")
			cell.crop_instance.set_growth_state(float(cell.crop_instance.crop_data.growth_days), CropInstance.LifecycleState.MATURE)
			var exp_lock = game_state.prepare_exp_transaction(1)
			assertions.truthy(exp_lock != null, "test can hold the existing experience transaction")
			assertions.equal(session.act(cell, "harvest").get("reason", ""), "transaction_failed", "busy experience transaction rejects harvest safely")
			assertions.truthy(not session.inventory._restore_notification_transaction_active, "failed harvest releases inventory notification transaction")
			game_state.cancel_exp_transaction(exp_lock)
			var grain_before: int = session.inventory.get_item_count("grain")
			var harvested: Dictionary = session.act(cell, "harvest")
			assertions.truthy(harvested.get("ok", false), "mature grain harvests through the adapter")
			assertions.truthy(session.inventory.get_item_count("grain") - grain_before >= 2, "harvest yields grain")
			assertions.truthy(session.act(cell, "seed").get("ok", false), "harvested plot can be replanted")
			session.season.advance_game_minutes(108)
			assertions.truthy(cell.crop_instance.is_mature(), "original minute growth matures grain after 108 game minutes")
			assertions.equal(session.act(cell, "hoe").get("reason", ""), "crop_mature", "hoe does not auto-harvest mature grain")
			var full_slots: Array[Dictionary] = []
			for _index in range(session.inventory.max_slots):
				full_slots.append({"item_id": "grain", "quantity": 99})
			var original_slots: Array = session.inventory.slots.duplicate(true)
			var original_quick: Array = session.inventory.quick_slot_mappings.duplicate()
			session.inventory.restore_state(full_slots, [-1, -1, -1, -1, -1, -1])
			var exp_before_full: int = game_state.player_state.exp
			assertions.equal(session.act(cell, "harvest").get("reason", ""), "inventory_full", "full inventory rejects mature harvest")
			assertions.truthy(cell.crop_instance != null and cell.crop_instance.is_mature(), "full inventory leaves mature crop intact")
			assertions.equal(game_state.player_state.exp, exp_before_full, "full inventory leaves harvest XP unchanged")
			session.inventory.restore_state(original_slots, original_quick)
			assertions.truthy(session.act(cell, "harvest").get("ok", false), "mature crop harvests after inventory space returns")
			assertions.truthy(game_state.player_state.exp > exp_before_full, "successful harvest awards original XP")
			assertions.truthy(session.act(cell, "seed").get("ok", false), "post-harvest plot plants for winter rule")
			session.season.current_season = SeasonSystem.Season.WINTER
			session.farming.on_day_changed(session.season.total_days + 1)
			assertions.equal(cell.crop_instance.lifecycle_state, CropInstance.LifecycleState.WITHERED, "winter transition withers grain")
			var dead_holder: Node3D = session.visuals._visuals[GridSystem.cell_key(25, 12)]
			var dead_meshes := dead_holder.find_children("WitheredGrain*", "Node3D", true, false)
			assertions.truthy(not dead_meshes.is_empty(), "winter gives mature grain an explicit withered representation")
			var dead_tint := true
			for dead_crop in dead_meshes:
				for mesh_node in dead_crop.find_children("*", "MeshInstance3D", true, false):
					for surface in mesh_node.mesh.get_surface_count():
						var tint: Color = mesh_node.get_active_material(surface).albedo_color
						dead_tint = dead_tint and tint.r > tint.g and tint.g > tint.b
			assertions.truthy(dead_tint, "withered stalks and ears use a dry brown tint")
			var stamina_before_clear: int = game_state.player_state.stamina
			var hoe_before: int = int(session.tools.get_durability("hoe").current)
			assertions.truthy(session.act(cell, "hoe").get("ok", false), "hoe clears withered crop through original tool path")
			assertions.equal(game_state.player_state.stamina, stamina_before_clear - 5, "wither clear charges hoe stamina")
			assertions.equal(int(session.tools.get_durability("hoe").current), hoe_before - 1, "wither clear charges hoe durability")
			session.season.current_season = SeasonSystem.Season.SPRING
			session.act(cell, "seed")
			session.season.current_season = SeasonSystem.Season.WINTER
			session.farming.on_day_changed(session.season.total_days + 1)
			var before_hand_clear_grain: int = session.inventory.get_item_count("grain")
			var before_hand_clear_exp: int = game_state.player_state.exp
			game_state.player_state.stamina = 0
			assertions.truthy(session.act(cell, "harvest").get("ok", false), "harvest mode can remove withered crops by hand")
			assertions.equal(session.inventory.get_item_count("grain"), before_hand_clear_grain, "withered harvest adds no grain")
			assertions.equal(game_state.player_state.exp, before_hand_clear_exp, "withered harvest adds no XP")
			assertions.equal(session.act(cell, "water").get("reason", ""), "insufficient_stamina", "zero stamina receives a precise tool failure")
			game_state.player_state.stamina = 100
			session.season.current_season = SeasonSystem.Season.SPRING
			var seed_count: int = session.inventory.get_item_count("grain_seed")
			session.inventory.remove_item("grain_seed", seed_count)
			assertions.equal(session.act(cell, "seed").get("reason", ""), "no_seed", "missing seed rejects a valid spring plot")
			session.inventory.add_item("grain_seed", 1)
			session.season.current_season = SeasonSystem.Season.WINTER
			assertions.equal(session.act(cell, "seed").get("reason", ""), "wrong_season", "winter rejects grain before spending its seed")
		player.position = Vector3(10.0, 0.0, 10.0)
		var seeds_before: int = session.inventory.get_item_count("grain_seed")
		assertions.equal(session.act(cell, "seed").get("reason", ""), "out_of_range", "range rejects before seed spend")
		assertions.equal(session.inventory.get_item_count("grain_seed"), seeds_before, "range rejection preserves inventory")
		session.save_path = "user://farm_3d_session_test.json"
		assertions.truthy(session.save_game(), "session saves into its separate 3D farm file")
		assertions.truthy(session.save_game(), "atomic save replaces an existing farm save")
		var saved_experience: int = game_state.player_state.exp
		game_state.player_state.exp = 0
		var restored = script.new()
		restored.auto_restore = true
		restored.auto_save = false
		restored.save_path = session.save_path
		root.add_child(restored)
		assertions.truthy(restored.configure(player), "fresh session configures with auto restore")
		assertions.equal(restored.inventory.get_item_count("grain"), session.inventory.get_item_count("grain"), "save roundtrip restores harvest inventory")
		assertions.equal(game_state.player_state.exp, saved_experience, "save roundtrip restores earned XP after resetting live experience")
		assertions.equal(restored.tools.get_durability("hoe"), session.tools.get_durability("hoe"), "save roundtrip restores tool durability")
		var saved_young: GridCell = session.grid.get_cell(22, 12)
		var restored_young: GridCell = restored.grid.get_cell(22, 12)
		assertions.equal(restored_young.crop_instance.to_dict(), saved_young.crop_instance.to_dict(), "save roundtrip restores crop growth and lifecycle")
		var preserved_seeds: int = restored.inventory.get_item_count("grain_seed")
		var corrupt := FileAccess.open(restored.save_path, FileAccess.WRITE)
		corrupt.store_string("not json")
		assertions.truthy(not restored.load_game(), "corrupt save is rejected")
		assertions.equal(restored.inventory.get_item_count("grain_seed"), preserved_seeds, "corrupt save leaves live state untouched")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(restored.save_path))
		restored.queue_free()
		player.queue_free()
		session.queue_free()
	checks = assertions.checks
	failures = assertions.failures
	print("3D FARMING: %s" % ("PASS (%d checks)" % checks if failures.is_empty() else "FAIL (%d/%d checks)" % [failures.size(), checks]))
	quit(0 if failures.is_empty() else 1)
