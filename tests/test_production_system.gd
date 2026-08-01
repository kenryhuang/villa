extends RefCounted

const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const GRID_SYSTEM_SCENE := preload("res://scenes/systems/grid_system.tscn")
const BUILDING_SYSTEM_SCENE := preload("res://scenes/systems/building_system.tscn")

var _owned_nodes: Array[Node] = []


class FailingRemovalInventory:
	extends InventorySystem
	var remove_calls := 0
	var fail_on_call := 2

	func remove_item(item_id: String, quantity: int = 1) -> bool:
		remove_calls += 1
		var result := super.remove_item(item_id, quantity)
		if remove_calls == fail_on_call:
			return false
		return result


class FailingAddInventory:
	extends InventorySystem
	var add_calls := 0
	var fail_on_call := 2

	func add_item(item_id: String, quantity: int = 1) -> bool:
		add_calls += 1
		var result := super.add_item(item_id, quantity)
		if add_calls == fail_on_call:
			return false
		return result


class FailingEnqueueState:
	extends ProducerState

	func enqueue_job(job: Dictionary) -> bool:
		super.enqueue_job(job)
		return false


class FailingInputState:
	extends ProducerState

	func add_input(item_id: String, quantity: int) -> bool:
		super.add_input(item_id, quantity)
		return false


class FailingOutputRemovalState:
	extends ProducerState

	func remove_outputs(requested: Dictionary) -> bool:
		super.remove_outputs(requested)
		return false


class EconomyDouble:
	extends RefCounted

	func has_resources(_cost: Dictionary) -> bool:
		return true

	func spend_resources(_cost: Dictionary) -> bool:
		return true


class InventorySignalRecorder:
	extends RefCounted

	var added: Array[Dictionary] = []
	var removed: Array[Dictionary] = []

	func on_added(item_id: String, quantity: int) -> void:
		added.append({"item_id": item_id, "quantity": quantity})

	func on_removed(item_id: String, quantity: int) -> void:
		removed.append({"item_id": item_id, "quantity": quantity})


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_owned_nodes.clear()
	_test_state_round_trip(assertions)
	_test_queue_lifecycle(assertions)
	_test_start_failures_are_atomic(assertions)
	_test_queue_limit_and_output_pause(assertions)
	_test_collection_is_atomic(assertions)
	_test_rollback_signals_are_atomic(assertions, tree)
	_test_input_transfer(assertions)
	_test_building_round_trip(assertions)
	_test_building_system_restore(assertions, tree)
	_test_clock(assertions, tree)
	_cleanup_nodes()


func _test_state_round_trip(assertions: TestAssert) -> void:
	var original := ProducerStateScript.new("workbench")
	original.max_queue_slots = 4
	original.output_capacity = 5
	original.inputs = {"animal_feed": 2}
	original.jobs = [{
		"recipe_id": "plank",
		"batches": 2,
		"remaining_minutes": 90,
		"status": "running",
	}]
	original.outputs = {"plank": 3}
	var saved := original.to_dict()
	var restored := ProducerStateScript.new()
	assertions.truthy(restored.from_dict(saved), "producer state round-trip succeeds")
	assertions.equal(restored.to_dict(), saved, "producer state round-trip is exact")
	var json_saved: Variant = JSON.parse_string(JSON.stringify(original.to_dict()))
	var json_restored := ProducerStateScript.new()
	assertions.truthy(json_saved is Dictionary, "producer state crosses real JSON boundary")
	if json_saved is Dictionary:
		assertions.truthy(json_restored.from_dict(json_saved), "producer state restores JSON numeric values")
		assertions.equal(json_restored.to_dict(), original.to_dict(), "producer JSON round-trip is exact")
	saved.jobs[0].remaining_minutes = 1
	saved.outputs.plank = 99
	assertions.equal(restored.jobs[0].remaining_minutes, 90, "jobs are deep copied")
	assertions.equal(restored.outputs.plank, 3, "outputs are deep copied")

	var before := restored.to_dict()
	assertions.truthy(not restored.from_dict({
		"station_id": "workbench",
		"max_queue_slots": 2,
		"output_capacity": 3,
		"jobs": [{"recipe_id": "plank", "batches": 0, "remaining_minutes": 1}],
		"outputs": {},
		"inputs": {},
	}), "invalid nested producer job is rejected")
	assertions.equal(restored.to_dict(), before, "invalid producer restore is atomic")
	assertions.truthy(not restored.from_dict({
		"station_id": "workbench",
		"max_queue_slots": 2.5,
		"output_capacity": 3,
		"jobs": [],
		"outputs": {},
		"inputs": {},
	}), "fractional producer limits are rejected")
	for invalid_state in [
		_with_producer_field(before, "max_queue_slots", NAN),
		_with_producer_field(before, "max_queue_slots", 9223372036854775807),
		_with_producer_field(before, "output_capacity", -1),
		_with_producer_job_field(before, "batches", 1.5),
		_with_producer_job_field(before, "remaining_minutes", 1.25),
		_with_producer_count(before, "outputs", "plank", 1.5),
		_with_producer_count(before, "outputs", "plank", -1),
		_with_producer_count(before, "inputs", "animal_feed", NAN),
		_with_producer_count(before, "outputs", "unknown_saved_item", 1),
		_with_producer_count(before, "inputs", "unknown_saved_item", 1),
		_with_producer_job_field(before, "recipe_id", "unknown_saved_recipe"),
	]:
		var candidate := ProducerStateScript.new()
		candidate.from_dict(before)
		assertions.truthy(not candidate.from_dict(invalid_state), "invalid persisted producer number or id is rejected")
		assertions.equal(candidate.to_dict(), before, "invalid producer payload leaves state unchanged")
	var wrong_station_job := before.duplicate(true)
	wrong_station_job.station_id = "furnace"
	var station_candidate := ProducerStateScript.new()
	station_candidate.from_dict(before)
	assertions.truthy(not station_candidate.from_dict(wrong_station_job), "persisted job must match producer station")
	assertions.equal(station_candidate.to_dict(), before, "station-invalid producer payload is atomic")


func _test_queue_lifecycle(assertions: TestAssert) -> void:
	var production := _production()
	var workbench := _building("workbench")
	var inventory := _inventory()
	inventory.add_item("wood", 6)
	assertions.truthy(production.start_recipe(workbench, "plank", 1, inventory), "queue starts")
	assertions.equal(inventory.get_item_count("wood"), 4, "one plank batch consumes multiplied inputs")
	production.advance_minutes(120)
	assertions.equal(workbench.producer_state.get_output_count("plank"), 1, "output stored")
	assertions.equal(workbench.producer_state.jobs.size(), 0, "completed stored job leaves queue")
	assertions.truthy(production.collect_all(workbench, inventory), "collection succeeds")
	assertions.equal(inventory.get_item_count("plank"), 1, "collection moves output to inventory")
	assertions.equal(workbench.producer_state.get_output_count("plank"), 0, "collected output leaves building")

	assertions.truthy(production.start_recipe(workbench, "plank", 2, inventory), "multi-batch queue starts")
	assertions.equal(inventory.get_item_count("wood"), 0, "multi-batch consumes four wood atomically")
	production.advance_minutes(239)
	assertions.equal(workbench.producer_state.get_output_count("plank"), 0, "multi-batch waits full duration")
	production.advance_minutes(1)
	assertions.equal(workbench.producer_state.get_output_count("plank"), 2, "multi-batch stores multiplied output")


func _test_start_failures_are_atomic(assertions: TestAssert) -> void:
	var production := _production()
	var workbench := _building("workbench")
	var inventory := _inventory()
	inventory.add_item("wood", 1)
	assertions.truthy(not production.start_recipe(workbench, "plank", 1, inventory), "missing inputs rejected")
	assertions.equal(inventory.get_item_count("wood"), 1, "missing-input failure preserves inventory")
	assertions.equal(workbench.producer_state.jobs.size(), 0, "missing-input failure preserves queue")
	assertions.truthy(not production.start_recipe(_building("furnace"), "plank", 1, inventory), "station mismatch rejected")
	assertions.truthy(not production.start_recipe(workbench, "missing", 1, inventory), "unknown recipe rejected")
	assertions.truthy(not production.start_recipe(workbench, "plank", 0, inventory), "zero batches rejected")
	assertions.truthy(not production.start_recipe(workbench, "plank", -1, inventory), "negative batches rejected")
	assertions.truthy(not production.preflight_recipe(null, "plank", 1, inventory).ok, "missing building rejected")
	assertions.truthy(not production.preflight_recipe(workbench, "plank", 1, null).ok, "missing inventory rejected")

	var mutation_inventory := FailingRemovalInventory.new()
	_owned_nodes.append(mutation_inventory)
	mutation_inventory.add_item("iron_ore", 2)
	mutation_inventory.add_item("coal", 1)
	var furnace := _building("furnace")
	assertions.truthy(not production.start_recipe(furnace, "iron_ingot", 1, mutation_inventory), "partial input removal failure is reported")
	assertions.equal(mutation_inventory.get_item_count("iron_ore"), 2, "partial input rollback restores ore")
	assertions.equal(mutation_inventory.get_item_count("coal"), 1, "partial input rollback restores coal")
	assertions.equal(furnace.producer_state.jobs.size(), 0, "partial input rollback preserves queue")

	var enqueue_inventory := _inventory()
	enqueue_inventory.add_item("wood", 2)
	var failing_state := FailingEnqueueState.new("workbench")
	var failing_building := _building("workbench", failing_state)
	assertions.truthy(not production.start_recipe(failing_building, "plank", 1, enqueue_inventory), "enqueue mutation failure is reported")
	assertions.equal(enqueue_inventory.get_item_count("wood"), 2, "enqueue failure restores removed input")
	assertions.equal(failing_building.producer_state.jobs.size(), 0, "enqueue failure restores mutated queue")


func _test_queue_limit_and_output_pause(assertions: TestAssert) -> void:
	var production := _production()
	var inventory := _inventory()
	inventory.add_item("wood", 6)
	var workbench := _building("workbench")
	assertions.truthy(production.start_recipe(workbench, "plank", 1, inventory), "first queue slot starts")
	assertions.truthy(production.start_recipe(workbench, "plank", 1, inventory), "second queue slot starts")
	assertions.truthy(not production.start_recipe(workbench, "plank", 1, inventory), "third queue slot rejected")
	assertions.equal(inventory.get_item_count("wood"), 2, "queue-full rejection does not consume inputs")

	var blocked := _building("workbench")
	blocked.producer_state.outputs = {"stone": 1, "coal": 1, "fiber": 1}
	var blocked_inventory := _inventory()
	blocked_inventory.add_item("wood", 2)
	assertions.truthy(production.start_recipe(blocked, "plank", 1, blocked_inventory), "blocked fixture queues")
	production.advance_minutes(120)
	assertions.equal(blocked.producer_state.get_output_count("plank"), 0, "full output stores no partial product")
	assertions.equal(blocked.producer_state.jobs.size(), 1, "full output retains completed job")
	assertions.equal(blocked.producer_state.jobs[0].remaining_minutes, 0, "blocked job remains authoritatively complete")
	assertions.equal(blocked.producer_state.jobs[0].status, "output_full", "blocked job exposes full-output status")
	assertions.equal(blocked.producer_state.outputs, {"stone": 1, "coal": 1, "fiber": 1}, "full output loses nothing")
	assertions.truthy(production.collect_item(blocked, "stone", blocked_inventory), "one stored item can be collected")
	production.advance_minutes(1)
	assertions.equal(blocked.producer_state.get_output_count("plank"), 1, "pending completed job stores after capacity frees")
	assertions.equal(blocked.producer_state.jobs.size(), 0, "unblocked completed job leaves queue")


func _test_collection_is_atomic(assertions: TestAssert) -> void:
	var production := _production()
	var building := _building("workbench")
	building.producer_state.outputs = {"plank": 1, "rope": 1}
	var one_slot := _inventory()
	one_slot.max_slots = 1
	one_slot.reset_slots()
	assertions.truthy(not production.collect_all(building, one_slot), "combined collection capacity is preflighted")
	assertions.equal(one_slot.get_slot_count(), 0, "capacity preflight moves nothing")
	assertions.equal(building.producer_state.outputs, {"plank": 1, "rope": 1}, "capacity preflight preserves every output")

	var full_inventory := _inventory()
	full_inventory.max_slots = 1
	full_inventory.reset_slots()
	full_inventory.add_item("wood", 99)
	assertions.truthy(not production.collect_item(building, "plank", full_inventory), "full player inventory rejects collection")
	assertions.equal(building.producer_state.get_output_count("plank"), 1, "full inventory leaves output stored")

	var mutation_inventory := FailingAddInventory.new()
	_owned_nodes.append(mutation_inventory)
	assertions.truthy(not production.collect_all(building, mutation_inventory), "partial inventory-add failure is reported")
	assertions.equal(mutation_inventory.get_item_count("plank"), 0, "failed collection rolls back first add")
	assertions.equal(mutation_inventory.get_item_count("rope"), 0, "failed collection rolls back failed add")
	assertions.equal(building.producer_state.outputs, {"plank": 1, "rope": 1}, "failed collection preserves source outputs")

	var removal_state := FailingOutputRemovalState.new("workbench")
	removal_state.outputs = {"plank": 1}
	var removal_building := _building("workbench", removal_state)
	var destination := _inventory()
	assertions.truthy(not production.collect_all(removal_building, destination), "source removal failure is reported")
	assertions.equal(destination.get_item_count("plank"), 0, "source failure rolls destination back")
	assertions.equal(removal_building.producer_state.outputs, {"plank": 1}, "source failure restores outputs")
	assertions.truthy(not production.collect_item(building, "missing", destination), "unknown output collection rejected")


func _test_input_transfer(assertions: TestAssert) -> void:
	var production := _production()
	var building := _building("chicken_coop")
	var inventory := _inventory()
	inventory.add_item("animal_feed", 2)
	assertions.truthy(production.add_input(building, "animal_feed", 2, inventory), "building input transfer succeeds")
	assertions.equal(inventory.get_item_count("animal_feed"), 0, "input transfer removes player item")
	assertions.equal(building.producer_state.get_input_count("animal_feed"), 2, "input transfer stores building item")
	assertions.truthy(not production.add_input(building, "animal_feed", 0, inventory), "zero input transfer rejected")
	assertions.truthy(not production.add_input(building, "missing", 1, inventory), "unknown input transfer rejected")
	var mutation_inventory := _inventory()
	mutation_inventory.add_item("animal_feed", 1)
	var mutation_state := FailingInputState.new("chicken_coop")
	var mutation_building := _building("chicken_coop", mutation_state)
	assertions.truthy(not production.add_input(mutation_building, "animal_feed", 1, mutation_inventory), "input storage mutation failure is reported")
	assertions.equal(mutation_inventory.get_item_count("animal_feed"), 1, "input storage failure restores inventory")
	assertions.equal(mutation_state.get_input_count("animal_feed"), 0, "input storage failure restores producer input")


func _test_building_round_trip(assertions: TestAssert) -> void:
	var building := _building("workbench")
	building.grid_x = 7
	building.grid_z = 8
	building.occupied_cells = [{"gx": 7, "gz": 8, "previous_state": 0}]
	building.producer_state.outputs = {"plank": 2}
	building.producer_state.jobs = [{
		"recipe_id": "plank",
		"batches": 1,
		"remaining_minutes": 40,
		"status": "running",
	}]
	var saved := building.to_dict()
	assertions.truthy(saved.has("producer_state"), "building save includes producer state")
	var restored := _track(BuildingInstance.new()) as BuildingInstance
	assertions.truthy(restored.from_dict(saved), "building state round-trip succeeds")
	assertions.equal(restored.producer_state.to_dict(), building.producer_state.to_dict(), "building restores producer state")
	assertions.equal(restored.grid_x, 7, "building restores grid x")
	assertions.equal(restored.grid_z, 8, "building restores grid z")
	var json_saved: Variant = JSON.parse_string(JSON.stringify(saved))
	var json_restored := _track(BuildingInstance.new()) as BuildingInstance
	assertions.truthy(json_saved is Dictionary, "building state crosses real JSON boundary")
	if json_saved is Dictionary:
		assertions.truthy(json_restored.from_dict(json_saved), "building restores JSON numeric values")
		assertions.equal(json_restored.to_dict(), saved, "building JSON round-trip preserves producer state")

	var legacy := saved.duplicate(true)
	legacy.erase("producer_state")
	var legacy_building := _track(BuildingInstance.new()) as BuildingInstance
	assertions.truthy(legacy_building.from_dict(legacy), "old building save without producer state succeeds")
	assertions.equal(legacy_building.producer_state.station_id, "workbench", "old producer save gets an empty station state")
	assertions.equal(legacy_building.producer_state.jobs.size(), 0, "old producer save gets no invented jobs")
	var before := restored.to_dict()
	var malformed := saved.duplicate(true)
	malformed.producer_state.jobs[0].batches = 0
	assertions.truthy(not restored.from_dict(malformed), "malformed building producer state rejected")
	assertions.equal(restored.to_dict(), before, "malformed building restore is atomic")
	var mismatched := saved.duplicate(true)
	mismatched.producer_state.station_id = "furnace"
	mismatched.producer_state.jobs = []
	assertions.truthy(not restored.from_dict(mismatched), "building rejects mismatched producer station")
	assertions.equal(restored.to_dict(), before, "station mismatch restore is atomic")
	for invalid_building in [
		_with_building_field(saved, "gx", 7.5),
		_with_building_field(saved, "gz", NAN),
		_with_building_field(saved, "gx", -1),
		_with_building_field(saved, "construction_stage", 1.5),
		_with_building_field(saved, "construction_stage", 99),
		_with_occupied_field(saved, "gx", 7.25),
		_with_occupied_field(saved, "gz", NAN),
		_with_occupied_field(saved, "previous_state", 1.5),
		_with_occupied_field(saved, "previous_state", 99),
	]:
		var candidate := _track(BuildingInstance.new()) as BuildingInstance
		candidate.from_dict(before)
		assertions.truthy(not candidate.from_dict(invalid_building), "invalid persisted building number is rejected")
		assertions.equal(candidate.to_dict(), before, "invalid building payload leaves state unchanged")


func _test_clock(assertions: TestAssert, tree: SceneTree) -> void:
	var production := _production()
	tree.root.add_child(production)
	var inventory := _inventory()
	inventory.add_item("wood", 20)
	var workbench := _building("workbench")
	production.start_recipe(workbench, "plank", 10, inventory)
	assertions.truthy(production.sync_clock(10, 0), "clock sync accepts valid time")
	var event_bus := tree.root.get_node("EventBus")
	event_bus.emit_signal("time_changed", 11, 0)
	assertions.equal(workbench.producer_state.jobs[0].remaining_minutes, 1140, "forward clock advances elapsed minutes")
	event_bus.emit_signal("time_changed", 11, 0)
	assertions.equal(workbench.producer_state.jobs[0].remaining_minutes, 1140, "repeated clock value does not advance")
	event_bus.emit_signal("time_changed", 9, 0)
	assertions.equal(workbench.producer_state.jobs[0].remaining_minutes, 1140, "backward clock value does not advance")
	event_bus.emit_signal("time_changed", 12, 0)
	assertions.equal(workbench.producer_state.jobs[0].remaining_minutes, 1080, "forward clock remains anchored after backward value")
	assertions.truthy(production.sync_clock(23, 50), "late clock sync succeeds")
	event_bus.emit_signal("time_changed", 22, 0)
	assertions.equal(workbench.producer_state.jobs[0].remaining_minutes, 1080, "late-day backward clock is not a rollover")
	event_bus.emit_signal("time_changed", 6, 10)
	assertions.equal(workbench.producer_state.jobs[0].remaining_minutes, 1060, "day rollover advances active game minutes")
	assertions.truthy(not production.sync_clock(24, 0), "invalid hour is rejected")
	assertions.truthy(not production.sync_clock(12, 60), "invalid minute is rejected")
	production.apply_daily_effects(2)
	production.apply_daily_effects(2)
	production.finish_daily_outputs(2)
	production.finish_daily_outputs(2)


func _test_rollback_signals_are_atomic(assertions: TestAssert, tree: SceneTree) -> void:
	var production := _production()
	tree.root.add_child(production)
	var event_bus := tree.root.get_node("EventBus")
	var recorder := InventorySignalRecorder.new()
	event_bus.item_added.connect(recorder.on_added)
	event_bus.item_removed.connect(recorder.on_removed)

	var failing_remove := FailingRemovalInventory.new()
	_owned_nodes.append(failing_remove)
	failing_remove.add_item("iron_ore", 2)
	failing_remove.add_item("coal", 1)
	tree.root.add_child(failing_remove)
	assertions.truthy(not production.start_recipe(_building("furnace"), "iron_ingot", 1, failing_remove), "signal rollback fixture fails start")
	assertions.equal(recorder.removed, [], "failed start emits no partial removal signals")
	failing_remove.remove_calls = 0
	failing_remove.fail_on_call = 99
	assertions.truthy(production.start_recipe(_building("furnace"), "iron_ingot", 1, failing_remove), "successful start follows rollback")
	assertions.equal(recorder.removed.size(), 2, "successful start emits committed input removals")

	var failing_add := FailingAddInventory.new()
	_owned_nodes.append(failing_add)
	tree.root.add_child(failing_add)
	var output_building := _building("workbench")
	output_building.producer_state.outputs = {"plank": 1, "rope": 1}
	assertions.truthy(not production.collect_all(output_building, failing_add), "signal rollback fixture fails collection")
	assertions.equal(recorder.added, [], "failed collection emits no partial add signals")
	failing_add.add_calls = 0
	failing_add.fail_on_call = 99
	assertions.truthy(production.collect_all(output_building, failing_add), "successful collection follows rollback")
	assertions.equal(recorder.added.size(), 2, "successful collection emits committed output additions")

	event_bus.item_added.disconnect(recorder.on_added)
	event_bus.item_removed.disconnect(recorder.on_removed)


func _test_building_system_restore(assertions: TestAssert, tree: SceneTree) -> void:
	var grid := _track(GRID_SYSTEM_SCENE.instantiate()) as GridSystem
	var system := _track(BUILDING_SYSTEM_SCENE.instantiate()) as BuildingSystem
	tree.root.add_child(grid)
	tree.root.add_child(system)
	assertions.truthy(system.configure(grid, EconomyDouble.new()), "production save fixture configures building system")
	grid.set_cell_state(10, 10, GridCell.State.FARMLAND)
	var placed := system.place_building_by_id("workbench", 10, 10)
	assertions.truthy(placed is BuildingInstance, "production save fixture places workbench")
	placed.producer_state.outputs = {"plank": 2}
	placed.producer_state.jobs = [{
		"recipe_id": "plank",
		"batches": 1,
		"remaining_minutes": 40,
		"status": "running",
	}]
	var records := [placed.to_dict()]
	assertions.equal(system.restore_buildings(records), 1, "building system restores producer record")
	var restored := system.get_building_at(10, 10)
	assertions.equal(restored.producer_state.get_output_count("plank"), 2, "building system restores stored output")
	assertions.equal(restored.producer_state.jobs.size(), 1, "building system restores queued job")
	if not restored.producer_state.jobs.is_empty():
		assertions.equal(restored.producer_state.jobs[0].remaining_minutes, 40, "building system restores remaining job time")
	assertions.truthy(system.remove_building(restored), "valid restored producer can be removed")
	assertions.truthy(grid.get_cell(10, 10).state != GridCell.State.BUILDING, "removal clears authoritative producer footprint")

	grid.set_cell_state(10, 10, GridCell.State.FARMLAND)
	var outside_state := grid.get_cell(11, 10).state
	var displaced_record: Dictionary = records[0].duplicate(true)
	displaced_record.occupied_cells = [{
		"gx": 11,
		"gz": 10,
		"previous_state": GridCell.State.WASTELAND,
	}]
	assertions.equal(system.restore_buildings([displaced_record]), 0, "restore rejects displaced saved footprint")
	if system.get_building_count() > 0:
		system.remove_building(system.get_all_buildings()[0])
	assertions.truthy(grid.get_cell(10, 10).state != GridCell.State.BUILDING, "rejected footprint leaves authoritative cell clear")
	assertions.equal(grid.get_cell(11, 10).state, outside_state, "rejected footprint never mutates outside cell")

	var duplicate_record: Dictionary = records[0].duplicate(true)
	duplicate_record.occupied_cells.append(duplicate_record.occupied_cells[0].duplicate(true))
	assertions.equal(system.restore_buildings([duplicate_record]), 0, "restore rejects duplicate saved footprint coordinates")
	assertions.truthy(grid.get_cell(10, 10).state != GridCell.State.BUILDING, "duplicate footprint rejection clears authoritative mark")

	grid.set_cell_state(10, 10, GridCell.State.FARMLAND)
	var malicious_state_record: Dictionary = records[0].duplicate(true)
	malicious_state_record.occupied_cells[0].previous_state = GridCell.State.BUILDING
	assertions.equal(system.restore_buildings([malicious_state_record]), 0, "restore rejects a saved building previous state")
	assertions.equal(grid.get_cell(10, 10).state, GridCell.State.FARMLAND, "malicious previous state cannot leave a building mark")

	grid.set_cell_state(10, 10, GridCell.State.FARMLAND)
	var invalid_overlap: Dictionary = records[0].duplicate(true)
	invalid_overlap.producer_state.station_id = "furnace"
	invalid_overlap.producer_state.jobs = []
	assertions.equal(system.restore_buildings([records[0], invalid_overlap]), 1, "invalid overlapping record is skipped")
	assertions.equal(system.get_building_count(), 1, "valid overlapping record remains registered")
	assertions.equal(grid.get_cell(10, 10).state, GridCell.State.BUILDING, "invalid overlap preserves accepted building mark")
	var accepted := system.get_building_at(10, 10)
	assertions.truthy(accepted is BuildingInstance, "valid overlapping building remains addressable")
	if accepted is BuildingInstance:
		assertions.truthy(system.remove_building(accepted), "valid overlapping building can be removed")
	assertions.equal(grid.get_cell(10, 10).state, GridCell.State.FARMLAND, "accepted overlap removal restores prior state")

	grid.set_cell_state(10, 10, GridCell.State.FARMLAND)
	var duplicate_valid: Dictionary = records[0].duplicate(true)
	assertions.equal(system.restore_buildings([records[0], duplicate_valid]), 1, "duplicate valid footprint restores only once")
	assertions.equal(system.get_building_count(), 1, "duplicate valid footprint has one owner")
	assertions.equal(grid.get_cell(10, 10).state, GridCell.State.BUILDING, "accepted duplicate footprint remains marked")
	var duplicate_owner := system.get_building_at(10, 10)
	assertions.truthy(duplicate_owner is BuildingInstance, "accepted duplicate footprint is addressable")
	if duplicate_owner is BuildingInstance:
		assertions.truthy(system.remove_building(duplicate_owner), "accepted duplicate footprint can be removed")
	assertions.equal(system.get_building_count(), 0, "duplicate footprint removal clears its only owner")
	assertions.equal(grid.get_cell(10, 10).state, GridCell.State.FARMLAND, "duplicate footprint removal restores prior state once")

	grid.set_cell_state(10, 10, GridCell.State.BUILDING)
	assertions.equal(system.restore_buildings(records), 1, "unclaimed loaded building mark can be restored")
	var loaded_owner := system.get_building_at(10, 10)
	assertions.truthy(loaded_owner is BuildingInstance, "loaded building mark gains an owner")
	if loaded_owner is BuildingInstance:
		assertions.truthy(system.remove_building(loaded_owner), "loaded building owner can be removed")
	assertions.equal(grid.get_cell(10, 10).state, GridCell.State.FARMLAND, "loaded building removal restores saved terrain")


func _building(station_id: String, state: ProducerState = null) -> BuildingInstance:
	var building := _track(BuildingInstance.new()) as BuildingInstance
	building.authored_building_id = station_id
	building.producer_state = state if state != null else ProducerStateScript.new(station_id)
	return building


func _with_producer_field(source: Dictionary, field: String, value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	result[field] = value
	return result


func _with_producer_job_field(source: Dictionary, field: String, value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	result.jobs[0][field] = value
	return result


func _with_producer_count(
	source: Dictionary,
	map_name: String,
	item_id: String,
	value: Variant
) -> Dictionary:
	var result := source.duplicate(true)
	result[map_name][item_id] = value
	return result


func _with_building_field(source: Dictionary, field: String, value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	result[field] = value
	return result


func _with_occupied_field(source: Dictionary, field: String, value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	if result.occupied_cells.is_empty():
		result.occupied_cells = [{"gx": 7, "gz": 8, "previous_state": 0}]
	result.occupied_cells[0][field] = value
	return result


func _production() -> ProductionSystem:
	return _track(ProductionSystemScript.new()) as ProductionSystem


func _inventory() -> InventorySystem:
	return _track(InventorySystemScript.new()) as InventorySystem


func _track(node: Node) -> Node:
	_owned_nodes.append(node)
	return node


func _cleanup_nodes() -> void:
	for index in range(_owned_nodes.size() - 1, -1, -1):
		var node := _owned_nodes[index]
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()
