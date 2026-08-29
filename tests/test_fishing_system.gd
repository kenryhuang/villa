extends RefCounted

const FishingSpotDataScript = preload("res://scripts/data/fishing_spot_data.gd")
const FishingSystemScript = preload("res://scripts/systems/fishing_system.gd")
const GeographicQueryServiceScript = preload("res://scripts/systems/geographic_query_service.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")


func run(assertions: TestAssert) -> void:
	_test_spot_validation(assertions)
	_test_preflight_failures(assertions)
	_test_state_machine_and_settlement(assertions)
	_test_capacity_reservation_and_tool_preflight(assertions)
	_test_determinism_depletion_and_reset(assertions)
	_test_empty_candidate_rejection(assertions)


func _test_spot_validation(assertions: TestAssert) -> void:
	var spot := _spot()
	assertions.truthy(spot.is_valid(), "authored fishing spot is valid")
	spot.spot_id = ""
	assertions.truthy(not spot.is_valid(), "fishing spot requires a stable id")
	spot = _spot()
	spot.water_cell = spot.stand_cell
	assertions.truthy(not spot.is_valid(), "stand and water cells must differ")
	var grid := GridSystemScript.new()
	var geography := GeographicQueryServiceScript.new()
	geography.configure(grid)
	var fishing := FishingSystemScript.new()
	var inventory := InventorySystemScript.new()
	fishing.configure(grid, geography, inventory, GameDataScript, 1)
	fishing.set_cast_cost_callbacks(func() -> bool: return true, func() -> bool: return true)
	spot = _spot()
	assertions.truthy(not fishing.register_spot(spot), "spot registration rejects a non-water target")
	grid.get_cell(spot.water_cell.x, spot.water_cell.y).state = GridCell.State.WATER
	assertions.truthy(not fishing.register_spot(spot), "spot registration requires a natural shoreline stand")
	grid.get_cell(5, 6).state = GridCell.State.WATER
	assertions.truthy(fishing.register_spot(spot), "spot registration accepts an authored shoreline and water target")
	fishing.free()
	inventory.free()
	grid.free()


func _test_preflight_failures(assertions: TestAssert) -> void:
	var fixture := _fixture()
	var fishing: Node = fixture.fishing
	assertions.equal(fishing.start_cast("missing", fixture.player_position, 1, 8, 0).reason, "unknown_spot", "unknown spot is rejected")
	assertions.equal(fishing.start_cast("creek-01", Vector3(99.0, 0.0, 99.0), 1, 8, 0).reason, "too_far", "distant player is rejected")
	fixture.grid.get_cell(5, 8).state = GridCell.State.WASTELAND
	assertions.equal(fishing.start_cast("creek-01", fixture.player_position, 1, 8, 0).reason, "water_required", "non-water target is rejected")
	fixture.grid.get_cell(5, 8).state = GridCell.State.WATER
	fixture.grid.get_cell(5, 6).state = GridCell.State.BUILDING
	assertions.equal(fishing.start_cast("creek-01", fixture.player_position, 1, 8, 0).reason, "cast_blocked", "blocked cast line is rejected")
	fixture.grid.get_cell(5, 6).state = GridCell.State.WASTELAND
	fixture.inventory.max_slots = 1
	fixture.inventory.reset_slots()
	fixture.inventory.add_item("wood", 99)
	assertions.equal(fishing.start_cast("creek-01", fixture.player_position, 1, 8, 0).reason, "inventory_full", "full inventory is rejected before casting")
	_free_fixture(fixture)


func _test_state_machine_and_settlement(assertions: TestAssert) -> void:
	var fixture := _fixture()
	var fishing: Node = fixture.fishing
	var cost_calls := {"count": 0}
	fishing.set_cast_cost_callbacks(
		func() -> bool: return true,
		func() -> bool:
			cost_calls.count += 1
			return true
	)
	var started: Dictionary = fishing.start_cast("creek-01", fixture.player_position, 1, 8, 0)
	assertions.truthy(started.ok, "valid shoreline cast starts")
	assertions.equal(fishing.get_session_state(), FishingSystemScript.SessionState.CASTING, "cast enters casting")
	fishing.advance_realtime(0.5)
	assertions.equal(fishing.get_session_state(), FishingSystemScript.SessionState.WAITING_BITE, "cast waits for bite")
	assertions.equal(cost_calls.count, 1, "rod cost commits once when cast reaches water")
	_advance_to_bite(fishing)
	assertions.equal(fishing.get_session_state(), FishingSystemScript.SessionState.BITE_WINDOW, "wait reaches bite window")
	var session_id := int(started.session_id)
	var result: Dictionary = fishing.reel(session_id)
	assertions.truthy(result.ok, "timely reel settles catch")
	assertions.equal(fixture.inventory.get_item_count(str(result.item_id)), 1, "catch enters inventory exactly once")
	assertions.equal(fishing.reel(session_id).reason, "stale_session", "same session cannot settle twice")
	fishing.advance_realtime(0.5)
	assertions.equal(fishing.get_session_state(), FishingSystemScript.SessionState.IDLE, "cooldown returns to idle")

	var cancelled: Dictionary = fishing.start_cast("creek-01", fixture.player_position, 1, 8, 0)
	assertions.truthy(cancelled.ok, "second cast starts")
	assertions.truthy(fishing.cancel("tool_changed"), "active cast can be cancelled")
	assertions.equal(fishing.get_session_state(), FishingSystemScript.SessionState.IDLE, "cancel returns directly to idle")
	assertions.equal(fishing.reel(int(cancelled.session_id)).reason, "stale_session", "cancelled session cannot settle")
	_free_fixture(fixture)


func _test_capacity_reservation_and_tool_preflight(assertions: TestAssert) -> void:
	var fixture := _fixture()
	fixture.inventory.max_slots = 1
	fixture.inventory.reset_slots()
	fixture.fishing.set_cast_cost_callbacks(func() -> bool: return true, func() -> bool: return true)
	var started: Dictionary = fixture.fishing.start_cast("creek-01", fixture.player_position, 1, 8, 0)
	assertions.truthy(started.ok, "valid cast reserves one reward capacity")
	assertions.truthy(not fixture.inventory.add_item("wood", 1), "other writes cannot consume reserved fishing capacity")
	assertions.truthy(fixture.fishing.cancel("test"), "reservation fixture cancels")
	assertions.truthy(fixture.inventory.add_item("wood", 1), "cancellation releases reserved capacity")
	_free_fixture(fixture)

	fixture = _fixture()
	fixture.inventory.max_slots = 2
	fixture.inventory.reset_slots()
	fixture.fishing.set_cast_cost_callbacks(func() -> bool: return true, func() -> bool: return true)
	started = fixture.fishing.start_cast("creek-01", fixture.player_position, 1, 8, 0)
	var rollback_slots: Array = fixture.inventory.slots.duplicate(true)
	var rollback_mappings: Array = fixture.inventory.quick_slot_mappings.duplicate()
	assertions.truthy(fixture.inventory.add_item("wood", 1), "parallel transaction can use unreserved capacity")
	fixture.inventory.restore_state(rollback_slots, rollback_mappings)
	fixture.fishing.advance_realtime(0.5)
	_advance_to_bite(fixture.fishing)
	assertions.truthy(
		fixture.fishing.reel(int(started.session_id)).get("ok", false),
		"unrelated inventory rollback preserves the fishing capacity reservation"
	)
	_free_fixture(fixture)

	fixture = _fixture()
	fixture.fishing.set_cast_cost_callbacks(func() -> bool: return false, func() -> bool: return true)
	var rejected: Dictionary = fixture.fishing.start_cast("creek-01", fixture.player_position, 1, 8, 0)
	assertions.equal(rejected.get("reason"), "tool_unavailable", "broken rod or low stamina rejects before session start")
	assertions.equal(fixture.fishing.get_session_state(), FishingSystemScript.SessionState.IDLE, "tool preflight failure never locks player input")
	assertions.equal(fixture.fishing.to_dict().spots["creek-01"].cast_sequence, 0, "tool preflight failure does not consume cast sequence")
	_free_fixture(fixture)


func _test_determinism_depletion_and_reset(assertions: TestAssert) -> void:
	var first := _fixture(4242)
	var second := _fixture(4242)
	var first_start: Dictionary = first.fishing.start_cast("creek-01", first.player_position, 1, 8, 0)
	var second_start: Dictionary = second.fishing.start_cast("creek-01", second.player_position, 1, 8, 0)
	assertions.equal(first_start.get("item_id"), second_start.get("item_id"), "same seed, spot, day, and sequence select the same catch")
	first.fishing.cancel("test")
	second.fishing.cancel("test")
	for unused in range(3):
		var started: Dictionary = first.fishing.start_cast("creek-01", first.player_position, 1, 8, 0)
		assertions.truthy(started.ok, "available fish capacity starts cast")
		first.fishing.advance_realtime(0.5)
		_advance_to_bite(first.fishing)
		assertions.truthy(first.fishing.reel(int(started.session_id)).ok, "capacity catch settles")
		first.fishing.advance_realtime(0.5)
	assertions.equal(first.fishing.start_cast("creek-01", first.player_position, 1, 8, 0).reason, "depleted", "three successes deplete one spot")
	assertions.truthy(first.fishing.start_cast("creek-01", first.player_position, 2, 8, 0).ok, "next game day resets spot capacity")
	assertions.equal(first.fishing.to_dict().spots["creek-01"].success_count, 0, "reset happens before the new catch settles")
	_free_fixture(first)
	_free_fixture(second)


func _test_empty_candidate_rejection(assertions: TestAssert) -> void:
	var tables := {"FISHING_TABLES": {"creek": [
		{"item_id": "creek_crucian", "weight": 1.0, "seasons": [0], "hour_ranges": [[6, 10]], "unique": false},
	]}}
	var fixture := _fixture(7, tables)
	assertions.equal(fixture.fishing.start_cast("creek-01", fixture.player_position, 22, 12, 0).reason, "no_candidates", "season and hour filter can reject an empty table")
	_free_fixture(fixture)


func _fixture(world_seed: int = 77, game_data: Variant = GameDataScript) -> Dictionary:
	var grid := GridSystemScript.new()
	grid.get_cell(5, 6).state = GridCell.State.WATER
	grid.get_cell(5, 8).state = GridCell.State.WATER
	var geography := GeographicQueryServiceScript.new()
	geography.configure(grid)
	var inventory := InventorySystemScript.new()
	var fishing := FishingSystemScript.new()
	fishing.configure(grid, geography, inventory, game_data, world_seed)
	fishing.set_cast_cost_callbacks(func() -> bool: return true, func() -> bool: return true)
	fishing.register_spot(_spot())
	var stand_world := grid.grid_to_world(5, 5)
	return {
		"grid": grid,
		"geography": geography,
		"inventory": inventory,
		"fishing": fishing,
		"player_position": Vector3(stand_world.x, 0.0, stand_world.y),
	}


func _spot() -> Resource:
	var spot := FishingSpotDataScript.new()
	spot.spot_id = "creek-01"
	spot.water_body_id = "west_creek"
	spot.fish_table_id = "creek"
	spot.stand_cell = Vector2i(5, 5)
	spot.water_cell = Vector2i(5, 8)
	spot.max_distance = 2.0
	spot.daily_capacity = 3
	return spot


func _advance_to_bite(fishing: Node) -> void:
	for unused in range(80):
		if fishing.get_session_state() == FishingSystemScript.SessionState.BITE_WINDOW:
			return
		fishing.advance_realtime(0.1)


func _free_fixture(fixture: Dictionary) -> void:
	for key in ["fishing", "inventory", "grid"]:
		var node: Node = fixture.get(key)
		if is_instance_valid(node):
			node.free()
