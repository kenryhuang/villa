extends RefCounted

const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const FishingSystemScript = preload("res://scripts/systems/fishing_system.gd")
const FishingSpotDataScript = preload("res://scripts/data/fishing_spot_data.gd")
const GeographicQueryServiceScript = preload("res://scripts/systems/geographic_query_service.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _fixture(tree)
	var fishing: Node = fixture.fishing
	var manager: Node = fixture.manager
	assertions.truthy(manager.configure_fishing_runtime(fishing), "save manager accepts fishing participant")
	var durable := {
		"version": 1,
		"spots": {"creek-save": {"success_count": 2, "cast_sequence": 5, "reset_day": 4}},
		"unique_catches": ["drift_bottle"],
	}
	assertions.truthy(fishing.from_dict(durable), "fishing fixture accepts durable state")
	var json := JSON.new()
	json.parse(JSON.stringify(durable))
	assertions.truthy(fishing.from_dict(json.data), "JSON-decoded integer-like fishing numbers are accepted")
	assertions.equal(fishing.to_dict(), durable, "JSON-decoded fishing numbers normalize back to integers")
	var gathered: Dictionary = manager.call("_gather_save_data")
	assertions.equal(gathered.get("fishing_state"), durable, "save payload includes exact fishing durable state")
	assertions.truthy(fishing.reset_state(), "fishing state can be reset before restore")
	assertions.truthy(manager.call("_apply_save_data", gathered), "save manager restores fishing participant")
	assertions.equal(fishing.to_dict(), durable, "fishing state round-trips through save manager")

	for invalid_state in [
		{"version": 2, "spots": durable.spots, "unique_catches": durable.unique_catches},
		{"version": 1, "spots": {"unknown": {"success_count": 0, "cast_sequence": 0, "reset_day": 1}}, "unique_catches": []},
		{"version": 1, "spots": {"creek-save": {"success_count": -1, "cast_sequence": 0, "reset_day": 1}}, "unique_catches": []},
		{"version": 1, "spots": {"creek-save": {"success_count": 4, "cast_sequence": 0, "reset_day": 1}}, "unique_catches": []},
		{"version": 1, "spots": durable.spots, "unique_catches": ["drift_bottle", "drift_bottle"]},
		{"version": 1, "spots": durable.spots},
	]:
		var before: Dictionary = fishing.to_dict()
		assertions.truthy(not fishing.validate_dict(invalid_state), "malformed fishing payload is rejected")
		assertions.truthy(not fishing.from_dict(invalid_state), "invalid fishing restore fails")
		assertions.equal(fishing.to_dict(), before, "invalid fishing restore is atomic")

	var rejected_save := gathered.duplicate(true)
	rejected_save.fishing_state.spots["creek-save"].success_count = -1
	var before_rejected: Dictionary = fishing.to_dict()
	assertions.truthy(not manager.call("_apply_save_data", rejected_save), "save manager prevalidates fishing before mutation")
	assertions.equal(fishing.to_dict(), before_rejected, "rejected save leaves live fishing state unchanged")

	fishing.reset_state()
	var started: Dictionary = fishing.start_cast("creek-save", fixture.player_position, 1, 8, 0)
	assertions.truthy(started.ok, "transient cast starts before save")
	assertions.truthy(manager.save_game(94), "saving succeeds with active fishing session")
	assertions.equal(fishing.get_session_state(), FishingSystemScript.SessionState.IDLE, "saving cancels transient fishing session")
	assertions.truthy(manager.clear_save(94), "fishing save fixture is cleaned up")
	_cleanup_fixture(fixture)


func _fixture(tree: SceneTree) -> Dictionary:
	var grid := GridSystemScript.new()
	grid.get_cell(5, 8).state = GridCell.State.WATER
	var geography := GeographicQueryServiceScript.new()
	geography.configure(grid)
	var inventory := InventorySystemScript.new()
	var fishing := FishingSystemScript.new()
	tree.root.add_child(fishing)
	fishing.configure(grid, geography, inventory, GameDataScript, 33)
	var spot := FishingSpotDataScript.new()
	spot.spot_id = "creek-save"
	spot.water_body_id = "save-water"
	spot.fish_table_id = "creek"
	spot.stand_cell = Vector2i(5, 5)
	spot.water_cell = Vector2i(5, 8)
	fishing.register_spot(spot)
	var manager := SaveManagerScript.new()
	manager.save_directory = "D:/UnityProject/villa/tmp/fishing-save-tests"
	tree.root.add_child(manager)
	var stand := grid.grid_to_world(5, 5)
	return {
		"grid": grid,
		"inventory": inventory,
		"fishing": fishing,
		"manager": manager,
		"player_position": Vector3(stand.x, 0.0, stand.y),
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	for key in ["manager", "fishing", "inventory", "grid"]:
		var node: Node = fixture.get(key)
		if is_instance_valid(node):
			node.free()
