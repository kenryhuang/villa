extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const PlayerActionControllerScript = preload("res://scripts/actors/player_action_controller.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")
const MainScript = preload("res://scripts/main.gd")
const FARMLAND := 1
const PLANTED := 2


class FailingAfterMutationInventory:
	extends InventorySystem
	var restore_calls := 0
	var fail_next_add := true

	func add_item(item_id: String, quantity: int = 1) -> bool:
		var result := super.add_item(item_id, quantity)
		if fail_next_add:
			fail_next_add = false
			return false
		return result

	func restore_state(saved_slots: Variant, saved_quick_mappings: Variant) -> void:
		restore_calls += 1
		super.restore_state(saved_slots, saved_quick_mappings)


class FailingPlantFarming:
	extends FarmingSystem
	var fail_next_plant := true

	func plant(cell: GridCell, crop_data: CropData) -> CropInstance:
		if fail_next_plant:
			fail_next_plant = false
			return null
		return super.plant(cell, crop_data)


class InventorySignalRecorder:
	extends RefCounted
	var events: Array[String] = []

	func on_added(item_id: String, quantity: int) -> void:
		events.append("added:%s:%d" % [item_id, quantity])

	func on_removed(item_id: String, quantity: int) -> void:
		events.append("removed:%s:%d" % [item_id, quantity])


class QuickMappingRecorder:
	extends RefCounted
	var events: Array[Dictionary] = []

	func on_mapping_changed(quick_index: int, item_id: String) -> void:
		events.append({"quick_index": quick_index, "item_id": item_id})


class CropEventRecorder:
	extends Node

	signal crop_planted(gx: int, gz: int, crop_id: String)
	signal crop_harvested(gx: int, gz: int, crop_id: String)
	signal cell_state_changed(gx: int, gz: int, state: int)

	var planted_events: Array[Dictionary] = []
	var harvested_events: Array[Dictionary] = []

	func _init() -> void:
		crop_planted.connect(_on_crop_planted)
		crop_harvested.connect(_on_crop_harvested)

	func _on_crop_planted(gx: int, gz: int, crop_id: String) -> void:
		planted_events.append({"gx": gx, "gz": gz, "crop_id": crop_id})

	func _on_crop_harvested(gx: int, gz: int, crop_id: String) -> void:
		harvested_events.append({"gx": gx, "gz": gz, "crop_id": crop_id})


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_crop_lifecycle_growth(assertions)
	_test_crop_lifecycle_round_trip(assertions)
	_test_crop_lifecycle_validation_is_atomic(assertions)
	_test_runtime_growth_state_invariants(assertions)
	_test_harvest_count_runtime_boundary(assertions, tree)
	_test_harvest_returns_item_quantities(assertions)
	_test_deterministic_tomato_yield_and_regrowth(assertions)
	_test_carrot_yield_and_removal(assertions)
	_test_harvest_count_save_round_trip(assertions, tree)
	_test_controller_harvest_is_atomic(assertions, tree)
	_test_controller_plant_mapping_signal_is_atomic(assertions, tree)
	_test_crop_data_validation(assertions)
	_test_default_roster_and_item_catalog(assertions)
	_test_perennial_harvest_and_greenhouse_rules(assertions)
	_test_regrowing_crop_visual_remains(assertions)
	_test_roster_planting_uses_active_quick_item(assertions, tree)


func _test_crop_lifecycle_growth(assertions: TestAssert) -> void:
	var crop_data = CropDataScript.new()
	crop_data.crop_id = "lifecycle_growth"
	crop_data.growth_days = 3
	var instance = CropInstance.new()
	instance.crop_data = crop_data
	var has_lifecycle_property := _has_property(instance, "lifecycle_state")
	var has_lifecycle_api := (
		instance.has_method("set_lifecycle_state")
		and instance.has_method("derive_active_state")
	)
	assertions.truthy(has_lifecycle_property, "new crops expose persisted lifecycle state")
	assertions.truthy(has_lifecycle_api, "crop lifecycle exposes state and active-state APIs")
	if not has_lifecycle_property or not has_lifecycle_api:
		return

	assertions.equal(instance.get("lifecycle_state"), 0, "new crop starts growing")
	instance.growth_progress = 3.0
	assertions.truthy(not instance.is_mature(), "maturity does not derive from progress alone")
	instance.growth_progress = 0.0
	assertions.truthy(not instance.advance_growth(), "dry growth below maturity does not transition")
	assertions.near(instance.growth_progress, 1.0, 0.001, "dry crop advances one day")
	instance.is_watered_today = true
	assertions.truthy(not instance.advance_growth(), "watered growth below maturity does not transition")
	assertions.near(instance.growth_progress, 2.5, 0.001, "watered crop advances one and a half days")
	instance.is_watered_today = true
	assertions.truthy(instance.advance_growth(), "watered growth crossing threshold transitions")
	assertions.near(instance.growth_progress, 3.0, 0.001, "growth clamps at maturity")
	assertions.equal(instance.get("lifecycle_state"), 1, "threshold transition sets mature state")
	assertions.truthy(instance.is_mature(), "maturity reads lifecycle state")
	assertions.truthy(not instance.advance_growth(), "mature crop does not advance")
	assertions.near(instance.growth_progress, 3.0, 0.001, "mature progress remains stable")
	var dry_transition = CropInstance.new()
	dry_transition.crop_data = crop_data
	dry_transition.growth_progress = 2.0
	assertions.truthy(dry_transition.advance_growth(), "dry growth crossing threshold transitions")
	assertions.equal(dry_transition.lifecycle_state, CropInstance.LifecycleState.MATURE, "dry threshold sets mature state")

	assertions.truthy(instance.set_growth_state(1.25, CropInstance.LifecycleState.DORMANT), "dormant state is accepted")
	instance.is_watered_today = true
	assertions.truthy(not instance.advance_growth(), "dormant crop does not advance")
	assertions.near(instance.growth_progress, 1.25, 0.001, "dormant progress remains stable")
	assertions.equal(instance.call("derive_active_state"), 0, "retained partial progress derives growing")

	assertions.truthy(instance.set_growth_state(3.0, CropInstance.LifecycleState.WITHERED), "withered state is accepted")
	assertions.truthy(not instance.advance_growth(), "withered crop does not advance")
	assertions.near(instance.growth_progress, 3.0, 0.001, "withered progress remains stable")
	assertions.equal(instance.call("derive_active_state"), 1, "retained mature progress derives mature")
	assertions.truthy(instance.call("set_lifecycle_state", 3), "valid lifecycle no-op succeeds")
	assertions.truthy(not instance.call("set_lifecycle_state", -1), "negative lifecycle enum rejects")
	assertions.truthy(not instance.call("set_lifecycle_state", 4), "out-of-range lifecycle enum rejects")
	assertions.equal(instance.get("lifecycle_state"), 3, "invalid lifecycle request preserves state")


func _test_crop_lifecycle_round_trip(assertions: TestAssert) -> void:
	var crop_data = CropDataScript.new()
	crop_data.crop_id = "lifecycle_round_trip"
	crop_data.growth_days = 3
	var states := [0, 1, 2, 3]
	var progress_values := [0.5, 3.0, 1.25, 2.0]
	var probe = CropInstance.new()
	if not _has_property(probe, "lifecycle_state") or not probe.has_method("set_lifecycle_state"):
		assertions.truthy(false, "crop lifecycle round-trip API exists")
		return
	for index in states.size():
		var original = CropInstance.new()
		original.crop_data = crop_data
		original.is_watered_today = index % 2 == 0
		original.harvest_count = index
		assertions.truthy(original.set_growth_state(progress_values[index], states[index]), "lifecycle state %d prepares" % states[index])
		var payload: Variant = JSON.parse_string(JSON.stringify(original.to_dict()))
		var restored = CropInstance.new()
		restored.crop_data = crop_data
		assertions.truthy(restored.from_dict(payload), "lifecycle state %d restores from JSON" % states[index])
		assertions.equal(restored.get("lifecycle_state"), states[index], "lifecycle state %d round trips" % states[index])
		assertions.near(restored.growth_progress, progress_values[index], 0.001, "lifecycle progress %d round trips" % states[index])
		assertions.equal(restored.harvest_count, index, "lifecycle harvest count %d round trips" % states[index])


func _test_crop_lifecycle_validation_is_atomic(assertions: TestAssert) -> void:
	var crop_data = CropDataScript.new()
	crop_data.crop_id = "lifecycle_atomic"
	crop_data.growth_days = 3
	var instance = CropInstance.new()
	instance.crop_data = crop_data
	if not _has_property(instance, "lifecycle_state") or not instance.has_method("set_lifecycle_state"):
		assertions.truthy(false, "crop lifecycle atomic validation API exists")
		return
	instance.is_watered_today = true
	instance.harvest_count = 2
	instance.set_growth_state(1.25, CropInstance.LifecycleState.DORMANT)
	var baseline: Dictionary = instance.to_dict().duplicate(true)
	var extra_field_payload := _crop_payload(crop_data.crop_id, 1.0, 2)
	extra_field_payload["unexpected"] = true
	var invalid_payloads: Array[Dictionary] = [
		{"name": "missing lifecycle", "data": {"crop_id": crop_data.crop_id, "growth_progress": 1.0, "is_watered_today": false, "harvest_count": 0}},
		{"name": "negative lifecycle", "data": _crop_payload(crop_data.crop_id, 1.0, -1)},
		{"name": "high lifecycle", "data": _crop_payload(crop_data.crop_id, 1.0, 4)},
		{"name": "boolean lifecycle", "data": _crop_payload(crop_data.crop_id, 1.0, true)},
		{"name": "fractional lifecycle", "data": _crop_payload(crop_data.crop_id, 1.0, 1.5)},
		{"name": "NaN lifecycle", "data": _crop_payload(crop_data.crop_id, 1.0, NAN)},
		{"name": "infinite lifecycle", "data": _crop_payload(crop_data.crop_id, 1.0, INF)},
		{"name": "negative progress", "data": _crop_payload(crop_data.crop_id, -0.1, 2)},
		{"name": "NaN progress", "data": _crop_payload(crop_data.crop_id, NAN, 2)},
		{"name": "infinite progress", "data": _crop_payload(crop_data.crop_id, INF, 2)},
		{"name": "boolean progress", "data": _crop_payload(crop_data.crop_id, true, 2)},
		{"name": "fractional harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, 1.5)},
		{"name": "negative harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, -1)},
		{"name": "NaN harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, NAN)},
		{"name": "infinite harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, INF)},
		{"name": "unsafe positive integer harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, EconomyLimitsScript.MAX_SAFE_INTEGER + 1)},
		{"name": "unsafe negative integer harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, -EconomyLimitsScript.MAX_SAFE_INTEGER - 1)},
		{"name": "unsafe positive harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, EconomyLimitsScript.MAX_SAFE_INTEGER + 1.0)},
		{"name": "unsafe negative harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, -float(EconomyLimitsScript.MAX_SAFE_INTEGER) - 1.0)},
		{"name": "boolean harvest count", "data": _crop_payload(crop_data.crop_id, 1.0, 2, true)},
		{"name": "non-boolean water", "data": _crop_payload(crop_data.crop_id, 1.0, 2, 0, 1)},
		{"name": "wrong crop id", "data": _crop_payload("other_crop", 1.0, 2)},
		{"name": "growing at maturity", "data": _crop_payload(crop_data.crop_id, 3.0, 0)},
		{"name": "mature below maturity", "data": _crop_payload(crop_data.crop_id, 2.0, 1)},
		{"name": "progress above maturity", "data": _crop_payload(crop_data.crop_id, 3.1, 2)},
		{"name": "extra canonical field", "data": extra_field_payload},
	]
	for fixture in invalid_payloads:
		assertions.truthy(not instance.from_dict(fixture.data), "%s rejects" % fixture.name)
		assertions.equal(instance.to_dict(), baseline, "%s rejection is atomic" % fixture.name)


func _test_runtime_growth_state_invariants(assertions: TestAssert) -> void:
	var crop_data = CropDataScript.new()
	crop_data.crop_id = "runtime_invariants"
	crop_data.growth_days = 3
	var instance = CropInstance.new()
	instance.crop_data = crop_data
	assertions.truthy(instance.has_method("set_growth_state"), "crop exposes atomic growth-state setter")
	if not instance.has_method("set_growth_state"):
		return

	var valid_states: Array[Dictionary] = [
		{"progress": 0.0, "state": CropInstance.LifecycleState.GROWING},
		{"progress": 2.999, "state": CropInstance.LifecycleState.GROWING},
		{"progress": 3.0, "state": CropInstance.LifecycleState.MATURE},
		{"progress": 0.0, "state": CropInstance.LifecycleState.DORMANT},
		{"progress": 1.5, "state": CropInstance.LifecycleState.DORMANT},
		{"progress": 3.0, "state": CropInstance.LifecycleState.DORMANT},
		{"progress": 0.0, "state": CropInstance.LifecycleState.WITHERED},
		{"progress": 1.5, "state": CropInstance.LifecycleState.WITHERED},
		{"progress": 3.0, "state": CropInstance.LifecycleState.WITHERED},
	]
	for fixture in valid_states:
		assertions.truthy(
			instance.call("set_growth_state", fixture.progress, fixture.state),
			"runtime state %d accepts progress %.3f" % [fixture.state, fixture.progress]
		)
		var restored = CropInstance.new()
		restored.crop_data = crop_data
		assertions.truthy(restored.from_dict(instance.to_dict()), "valid runtime state always round trips")

	instance.call("set_growth_state", 1.0, CropInstance.LifecycleState.DORMANT)
	var baseline := instance.to_dict().duplicate(true)
	for fixture in [
		{"progress": -0.1, "state": CropInstance.LifecycleState.DORMANT},
		{"progress": 3.1, "state": CropInstance.LifecycleState.DORMANT},
		{"progress": NAN, "state": CropInstance.LifecycleState.DORMANT},
		{"progress": INF, "state": CropInstance.LifecycleState.DORMANT},
		{"progress": 1.0, "state": -1},
		{"progress": 1.0, "state": 4},
		{"progress": 3.0, "state": CropInstance.LifecycleState.GROWING},
		{"progress": 2.0, "state": CropInstance.LifecycleState.MATURE},
	]:
		assertions.truthy(
			not instance.call("set_growth_state", fixture.progress, fixture.state),
			"invalid runtime progress-state combination rejects"
		)
		assertions.equal(instance.to_dict(), baseline, "invalid runtime update is atomic")

	instance.call("set_growth_state", 1.0, CropInstance.LifecycleState.GROWING)
	instance.lifecycle_state = CropInstance.LifecycleState.MATURE
	assertions.equal(instance.lifecycle_state, CropInstance.LifecycleState.GROWING, "direct state write cannot create early maturity")
	instance.growth_progress = 3.0
	assertions.near(instance.growth_progress, 1.0, 0.001, "direct progress write cannot create full-progress growing")
	assertions.truthy(not instance.set_lifecycle_state(CropInstance.LifecycleState.MATURE), "state-only setter enforces current progress")
	instance.call("set_growth_state", 3.0, CropInstance.LifecycleState.MATURE)
	instance.lifecycle_state = CropInstance.LifecycleState.GROWING
	instance.growth_progress = 2.0
	assertions.equal(instance.lifecycle_state, CropInstance.LifecycleState.MATURE, "direct state write cannot create mature-progress growing")
	assertions.near(instance.growth_progress, 3.0, 0.001, "direct progress write cannot create early mature state")
	var canonical = CropInstance.new()
	canonical.crop_data = crop_data
	assertions.truthy(canonical.from_dict(instance.to_dict()), "direct-write rejections preserve canonical round trip")

	instance.call("set_growth_state", 1.0, CropInstance.LifecycleState.DORMANT)
	instance.harvest_count = EconomyLimitsScript.MAX_SAFE_INTEGER
	var max_json: Variant = JSON.parse_string(JSON.stringify(instance.to_dict()))
	var max_restored = CropInstance.new()
	max_restored.crop_data = crop_data
	assertions.truthy(max_restored.from_dict(max_json), "maximum safe JSON harvest count restores")
	assertions.equal(max_restored.harvest_count, EconomyLimitsScript.MAX_SAFE_INTEGER, "maximum safe harvest count round trips")

	var grid = GridSystemScript.new()
	grid.set_cell_state(6, 6, FARMLAND)
	var planted = grid.plant_crop(6, 6, crop_data)
	planted.lifecycle_state = CropInstance.LifecycleState.MATURE
	planted.growth_progress = 3.0
	assertions.truthy(_harvest(grid, 6, 6).is_empty(), "invalid direct writes cannot enable early harvest")
	assertions.equal(planted.lifecycle_state, CropInstance.LifecycleState.GROWING, "early harvest fixture remains growing")
	assertions.near(planted.growth_progress, 0.0, 0.001, "early harvest fixture retains valid progress")
	grid.free()


func _test_harvest_count_runtime_boundary(assertions: TestAssert, tree: SceneTree) -> void:
	var crop_data = CropDataScript.new()
	crop_data.crop_id = "harvest_count_boundary"
	_set_property_if_present(crop_data, "plant_item_id", "harvest_count_boundary_seed")
	_set_property_if_present(crop_data, "lifecycle_type", "annual_regrow")
	crop_data.growth_days = 4
	crop_data.regrow_days = 2
	crop_data.yield_min = 1
	crop_data.yield_max = 1
	var game_data = tree.root.get_node_or_null("GameData")
	assertions.truthy(game_data != null, "harvest boundary fixture has GameData")
	if game_data == null:
		return
	if game_data.get_crop(crop_data.crop_id) == null:
		assertions.truthy(game_data.register_crop(crop_data), "harvest boundary crop registers")

	var count_probe = CropInstance.new()
	count_probe.crop_data = crop_data
	assertions.truthy(count_probe.has_method("set_harvest_count"), "crop exposes validated harvest-count setter")
	count_probe.harvest_count = EconomyLimitsScript.MAX_SAFE_INTEGER - 1
	count_probe.harvest_count = EconomyLimitsScript.MAX_SAFE_INTEGER + 1
	assertions.equal(count_probe.harvest_count, EconomyLimitsScript.MAX_SAFE_INTEGER - 1, "unsafe direct count increase rejects")
	count_probe.harvest_count = -1
	assertions.equal(count_probe.harvest_count, EconomyLimitsScript.MAX_SAFE_INTEGER - 1, "negative direct count rejects")

	var max_grid = GridSystemScript.new()
	tree.root.add_child(max_grid)
	var max_events := CropEventRecorder.new()
	max_grid.set_cell_state(7, 7, FARMLAND)
	max_grid._event_bus = max_events
	var max_instance = max_grid.plant_crop(7, 7, crop_data)
	max_events.harvested_events.clear()
	max_instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	max_instance.harvest_count = EconomyLimitsScript.MAX_SAFE_INTEGER
	max_instance.is_watered_today = true
	var max_cell = max_grid.get_cell(7, 7)
	max_cell.watered = true
	var max_crop_before := max_instance.to_dict().duplicate(true)
	assertions.truthy(_preview_harvest(max_grid, 7, 7).is_empty(), "max-count crop cannot preview harvest")
	assertions.truthy(_harvest(max_grid, 7, 7).is_empty(), "max-count crop harvest rejects")
	assertions.equal(max_instance.to_dict(), max_crop_before, "max-count rejection preserves exact crop")
	assertions.truthy(max_cell.crop_instance == max_instance, "max-count rejection preserves crop instance")
	assertions.equal(max_cell.state, PLANTED, "max-count rejection preserves planted cell")
	assertions.truthy(max_cell.watered, "max-count rejection preserves cell water")
	assertions.equal(max_events.harvested_events, [], "max-count rejection emits no harvest event")

	var once_grid = GridSystemScript.new()
	tree.root.add_child(once_grid)
	var once_events := CropEventRecorder.new()
	once_grid.set_cell_state(8, 8, FARMLAND)
	once_grid._event_bus = once_events
	var once_instance = once_grid.plant_crop(8, 8, crop_data)
	once_instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	once_instance.harvest_count = EconomyLimitsScript.MAX_SAFE_INTEGER - 1
	assertions.truthy(not _harvest(once_grid, 8, 8).is_empty(), "max-minus-one crop harvests once")
	assertions.equal(once_instance.harvest_count, EconomyLimitsScript.MAX_SAFE_INTEGER, "last valid harvest reaches max count")
	assertions.equal(once_events.harvested_events.size(), 1, "last valid harvest emits one event")
	var max_saved: Variant = JSON.parse_string(JSON.stringify(once_grid.to_dict()))
	var restored = GridSystemScript.new()
	tree.root.add_child(restored)
	assertions.truthy(restored.from_dict(max_saved), "max-count crop saves and restores")
	var restored_instance = restored.get_cell(8, 8).crop_instance
	assertions.equal(restored_instance.harvest_count, EconomyLimitsScript.MAX_SAFE_INTEGER, "restored crop retains max count")
	restored_instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	var restored_events := CropEventRecorder.new()
	restored._event_bus = restored_events
	var restored_before: Dictionary = restored_instance.to_dict().duplicate(true)
	assertions.truthy(_harvest(restored, 8, 8).is_empty(), "restored max-count crop rejects next harvest")
	assertions.equal(restored_instance.to_dict(), restored_before, "restored max-count rejection is atomic")
	assertions.equal(restored_events.harvested_events, [], "restored max-count rejection emits no event")

	var invalid_grid = GridSystemScript.new()
	var invalid_events := CropEventRecorder.new()
	invalid_grid.set_cell_state(9, 9, FARMLAND)
	invalid_grid._event_bus = invalid_events
	var invalid_crop = CropDataScript.new()
	invalid_crop.crop_id = "invalid_growth_timeline"
	invalid_crop.growth_days = 0
	assertions.truthy(invalid_grid.plant_crop(9, 9, invalid_crop) == null, "invalid initial growth state rejects planting")
	assertions.equal(invalid_grid.get_cell(9, 9).state, FARMLAND, "failed planting preserves farmland")
	assertions.truthy(invalid_grid.get_cell(9, 9).crop_instance == null, "failed planting stores no crop")
	assertions.equal(invalid_events.planted_events, [], "failed planting emits no planted event")

	var transition_grid = GridSystemScript.new()
	var transition_events := CropEventRecorder.new()
	transition_grid.set_cell_state(10, 10, FARMLAND)
	transition_grid._event_bus = transition_events
	var transition_crop = CropDataScript.new()
	transition_crop.crop_id = "failed_regrow_transition"
	transition_crop.lifecycle_type = "annual_regrow"
	transition_crop.growth_days = 4
	transition_crop.regrow_days = 2
	var transition_instance = transition_grid.plant_crop(10, 10, transition_crop)
	transition_instance.set_growth_state(4.0, CropInstance.LifecycleState.MATURE)
	transition_instance.is_watered_today = true
	var transition_cell = transition_grid.get_cell(10, 10)
	transition_cell.watered = true
	transition_events.harvested_events.clear()
	transition_crop.growth_days = 0
	var transition_before := transition_instance.to_dict().duplicate(true)
	assertions.truthy(_harvest(transition_grid, 10, 10).is_empty(), "failed regrow transition rejects harvest")
	assertions.equal(transition_instance.to_dict(), transition_before, "failed regrow transition preserves exact crop")
	assertions.truthy(transition_cell.crop_instance == transition_instance, "failed regrow transition preserves instance")
	assertions.equal(transition_cell.state, PLANTED, "failed regrow transition preserves cell")
	assertions.truthy(transition_cell.watered, "failed regrow transition preserves cell water")
	assertions.equal(transition_events.harvested_events, [], "failed regrow transition emits no event")

	max_events.free()
	once_events.free()
	restored_events.free()
	invalid_events.free()
	transition_events.free()
	max_grid.free()
	once_grid.free()
	restored.free()
	invalid_grid.free()
	transition_grid.free()


func _crop_payload(
	crop_id: String,
	progress: Variant,
	lifecycle: Variant,
	count: Variant = 0,
	watered: Variant = false
) -> Dictionary:
	return {
		"crop_id": crop_id,
		"growth_progress": progress,
		"is_watered_today": watered,
		"harvest_count": count,
		"lifecycle_state": lifecycle,
	}


func _test_harvest_returns_item_quantities(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var crop = CropDataScript.new()
	crop.crop_id = "tomato"
	crop.growth_days = 4
	crop.exp_reward = 5
	grid.set_cell_state(1, 1, FARMLAND)
	var instance = grid.plant_crop(1, 1, crop)
	_set_mature(instance, 4.0)

	var result: Dictionary = _harvest(grid, 1, 1)

	assertions.truthy(result.get("items", null) is Dictionary, "harvest returns an item-quantity dictionary")
	if result.get("items", null) is Dictionary:
		assertions.equal(result.items, {"tomato": 1}, "harvest returns item quantities keyed by crop id")
	assertions.equal(result.get("exp", -1), 5, "harvest returns crop experience")
	assertions.equal(result.get("regrowing", null), false, "annual harvest reports no regrowth")
	grid.free()


func _test_deterministic_tomato_yield_and_regrowth(assertions: TestAssert) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "tomato"
	crop.growth_days = 4
	crop.yield_min = 2
	crop.yield_max = 3
	crop.regrow_days = 2
	crop.lifecycle_type = "annual_regrow"
	crop.exp_reward = 5
	seed(42)
	var grid = GridSystemScript.new()
	grid.set_cell_state(1, 1, FARMLAND)
	var instance = grid.plant_crop(1, 1, crop)
	_set_mature(instance, 4.0)
	var result: Dictionary = _harvest(grid, 1, 1)
	assertions.equal(result.get("items", {}), {"tomato": 3}, "tomato harvest has deterministic item quantities")
	assertions.equal(result.get("exp", 0), 5, "tomato harvest keeps authored experience")
	assertions.truthy(bool(result.get("regrowing", false)), "tomato harvest reports explicit lifecycle regrowth")
	seed(42)
	var repeat_grid = GridSystemScript.new()
	repeat_grid.set_cell_state(1, 1, FARMLAND)
	var repeat_instance = repeat_grid.plant_crop(1, 1, crop)
	_set_mature(repeat_instance, 4.0)
	assertions.equal(_harvest(repeat_grid, 1, 1), result, "seed 42 yield repeats after recreating the crop")
	repeat_grid.free()
	var cell = grid.get_cell(1, 1)
	assertions.equal(cell.state, PLANTED, "regrowing tomato remains planted")
	assertions.truthy(cell.crop_instance == instance, "regrowth preserves the crop instance")
	assertions.equal(instance.harvest_count, 1, "harvest increments persisted counter")
	assertions.near(instance.growth_progress, 2.0, 0.001, "tomato resets to two-day regrowth phase")
	if _has_property(instance, "lifecycle_state"):
		assertions.equal(instance.get("lifecycle_state"), 0, "regrowing harvest returns crop to growing")
	instance.advance_growth()
	assertions.truthy(not instance.is_mature(), "tomato is not mature after one regrowth day")
	instance.advance_growth()
	assertions.truthy(instance.is_mature(), "tomato matures after exactly two regrowth days")
	var second: Dictionary = _harvest(grid, 1, 1)
	assertions.equal(second.get("items", {}), {"tomato": 2}, "next harvest uses incremented deterministic vector")
	grid.free()


func _test_carrot_yield_and_removal(assertions: TestAssert) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "carrot"
	crop.growth_days = 3
	crop.yield_min = 2
	crop.yield_max = 3
	var grid = GridSystemScript.new()
	grid.set_cell_state(2, 2, FARMLAND)
	var instance = grid.plant_crop(2, 2, crop)
	_set_mature(instance, 3.0)
	var result: Dictionary = _harvest(grid, 2, 2)
	var quantity := int(result.get("items", {}).get("carrot", 0))
	assertions.truthy(quantity >= 2 and quantity <= 3, "carrot harvest stays within authored yield range")
	assertions.equal(result.get("regrowing", true), false, "carrot reports no regrowth")
	assertions.equal(grid.get_cell(2, 2).state, FARMLAND, "non-regrowing annual carrot is removed")
	assertions.truthy(grid.get_cell(2, 2).crop_instance == null, "carrot instance is cleared")
	grid.free()


func _test_harvest_count_save_round_trip(assertions: TestAssert, tree: SceneTree) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "save_tomato"
	_set_property_if_present(crop, "plant_item_id", "save_tomato_seed")
	_set_property_if_present(crop, "lifecycle_type", "annual_regrow")
	crop.growth_days = 4
	crop.yield_min = 2
	crop.yield_max = 3
	crop.regrow_days = 2
	var game_data = tree.root.get_node_or_null("GameData")
	assertions.truthy(game_data != null, "save fixture has GameData autoload")
	if game_data == null:
		return
	if game_data.get_crop(crop.crop_id) == null:
		assertions.truthy(game_data.register_crop(crop), "save fixture crop registers")

	var grid = GridSystemScript.new()
	tree.root.add_child(grid)
	grid.set_cell_state(4, 4, FARMLAND)
	var instance = grid.plant_crop(4, 4, crop)
	_set_mature(instance, 4.0)
	_harvest(grid, 4, 4)
	var saved: Dictionary = grid.to_dict()
	assertions.equal(saved.get("version", -1), 2, "crop grid save uses version two")
	assertions.equal(saved.cells[0].crop.get("harvest_count", -1), 1, "grid save persists harvest count")
	assertions.equal(saved.cells[0].crop.get("lifecycle_state", -1), 0, "grid save persists regrowing lifecycle")
	var json_saved: Variant = JSON.parse_string(JSON.stringify(saved))
	var restored = GridSystemScript.new()
	tree.root.add_child(restored)
	assertions.truthy(restored.from_dict(json_saved), "grid restores JSON numeric crop state")
	var restored_instance = restored.get_cell(4, 4).crop_instance
	assertions.truthy(restored_instance != null, "JSON crop instance restores")
	if restored_instance:
		assertions.equal(restored_instance.harvest_count, 1, "JSON integral float restores as harvest count")
		assertions.near(restored_instance.growth_progress, 2.0, 0.001, "JSON regrowth progress restores")
		assertions.equal(restored_instance.get("lifecycle_state"), 0, "JSON grid restore preserves lifecycle state")

	var missing_lifecycle: Dictionary = saved.duplicate(true)
	missing_lifecycle.cells[0].crop.erase("lifecycle_state")
	assertions.truthy(not restored.from_dict(missing_lifecycle), "current grid save missing lifecycle rejects")
	assertions.truthy(restored.get_cell(4, 4).crop_instance == restored_instance, "failed grid restore is atomic")
	var missing_harvest_count: Dictionary = saved.duplicate(true)
	missing_harvest_count.cells[0].crop.erase("harvest_count")
	assertions.truthy(not restored.from_dict(missing_harvest_count), "current grid save missing harvest count rejects")
	var invalid_lifecycle: Dictionary = saved.duplicate(true)
	invalid_lifecycle.cells[0].crop.lifecycle_state = 4
	assertions.truthy(not restored.from_dict(invalid_lifecycle), "grid rejects invalid crop lifecycle enum")
	var contradictory_lifecycle: Dictionary = saved.duplicate(true)
	contradictory_lifecycle.cells[0].crop.growth_progress = 4.0
	assertions.truthy(not restored.from_dict(contradictory_lifecycle), "grid rejects growing crop at maturity")
	var old_version: Dictionary = saved.duplicate(true)
	old_version.version = 1
	assertions.truthy(not restored.from_dict(old_version), "version one grid save rejects before deferred migration")
	grid.free()
	restored.free()


func _test_controller_harvest_is_atomic(assertions: TestAssert, tree: SceneTree) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "tomato"
	crop.growth_days = 4
	crop.yield_min = 3
	crop.yield_max = 3
	crop.regrow_days = 2
	crop.lifecycle_type = "annual_regrow"
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	farming.configure(grid, null, null)
	grid.set_cell_state(1, 1, FARMLAND)
	var instance = farming.plant(grid.get_cell(1, 1), crop)
	_set_mature(instance, 4.0)
	var inventory = InventorySystemScript.new()
	inventory.max_slots = 2
	inventory.reset_slots()
	inventory.slots[0] = {"item_id": "tomato", "quantity": 97}
	inventory.slots[1] = {"item_id": "grain", "quantity": 98}
	var controller = PlayerActionControllerScript.new()
	controller.configure(null, grid, farming, null, null, inventory)
	assertions.truthy(not controller._harvest(grid.get_cell(1, 1)), "full multi-quantity result blocks before harvest")
	assertions.equal(inventory.get_item_count("tomato"), 97, "capacity rejection preserves crop inventory")
	assertions.equal(inventory.get_item_count("grain"), 98, "capacity rejection preserves unrelated stack")
	assertions.truthy(grid.get_cell(1, 1).crop_instance == instance, "capacity rejection preserves mature crop")
	assertions.equal(instance.harvest_count, 0, "capacity rejection does not advance harvest counter")

	var failing_inventory = FailingAfterMutationInventory.new()
	failing_inventory.max_slots = 2
	failing_inventory.reset_slots()
	failing_inventory.slots[0] = {"item_id": "tomato", "quantity": 99}
	failing_inventory.slots[1] = {}
	failing_inventory.set_quick_slot(1, 5)
	var slots_before: Array[Dictionary] = failing_inventory.slots.duplicate(true)
	var mappings_before: Array[int] = failing_inventory.quick_slot_mappings.duplicate()
	tree.root.add_child(failing_inventory)
	var failing_controller = PlayerActionControllerScript.new()
	tree.root.add_child(failing_controller)
	failing_controller.configure(null, grid, farming, null, null, failing_inventory)
	var event_bus = tree.root.get_node("EventBus")
	event_bus.set_block_signals(false)
	var recorder := InventorySignalRecorder.new()
	var mapping_recorder := QuickMappingRecorder.new()
	event_bus.item_added.connect(recorder.on_added)
	event_bus.item_removed.connect(recorder.on_removed)
	failing_inventory.quick_slot_mapping_changed.connect(mapping_recorder.on_mapping_changed)
	assertions.truthy(not failing_controller._harvest(grid.get_cell(1, 1)), "injected add failure rejects harvest")
	assertions.equal(failing_inventory.slots, slots_before, "injected failure restores exact slot layout")
	assertions.equal(failing_inventory.quick_slot_mappings, mappings_before, "injected failure restores exact quick mappings")
	assertions.equal(failing_inventory.restore_calls, 1, "rollback uses InventorySystem restore_state")
	assertions.equal(recorder.events, [], "rolled-back harvest emits no partial inventory events")
	assertions.equal(
		mapping_recorder.events,
		[],
		"rolled-back harvest emits no transient quick-mapping notifications"
	)
	assertions.truthy(grid.get_cell(1, 1).crop_instance == instance, "injected add failure preserves crop")
	assertions.equal(instance.harvest_count, 0, "injected add failure preserves harvest counter")
	assertions.truthy(failing_controller._harvest(grid.get_cell(1, 1)), "successful harvest follows rollback")
	assertions.equal(
		mapping_recorder.events,
		[{"quick_index": 5, "item_id": "tomato"}],
		"successful harvest emits one committed quick-mapping notification"
	)
	event_bus.item_added.disconnect(recorder.on_added)
	event_bus.item_removed.disconnect(recorder.on_removed)
	controller.free()
	failing_controller.free()
	inventory.free()
	failing_inventory.free()
	farming.free()
	grid.free()


func _test_controller_plant_mapping_signal_is_atomic(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "grain"
	_set_property_if_present(crop, "plant_item_id", "grain_seed")
	crop.growth_days = 3
	var grid = GridSystemScript.new()
	grid.set_cell_state(2, 2, FARMLAND)
	var farming := FailingPlantFarming.new()
	farming.configure(grid, null, null)
	var inventory = InventorySystemScript.new()
	inventory.add_item("grain_seed", 1)
	inventory.set_quick_slot(0, 5)
	var game_data = tree.root.get_node("GameData")
	if game_data.get_crop_for_plant_item(crop.plant_item_id) == null:
		assertions.truthy(game_data.register_crop(crop), "atomic planting fixture crop registers")
	var recorder := QuickMappingRecorder.new()
	inventory.quick_slot_mapping_changed.connect(recorder.on_mapping_changed)
	var controller = PlayerActionControllerScript.new()
	tree.root.add_child(controller)
	controller.crop_data_override = crop
	controller.configure(null, grid, farming, null, null, inventory)
	assertions.truthy(
		not controller._plant(grid.get_cell(2, 2)),
		"injected plant failure rolls inventory back"
	)
	assertions.equal(recorder.events, [], "failed plant emits no transient mapping signals")
	assertions.equal(inventory.get_item_count("grain_seed"), 1, "failed plant restores seed")
	assertions.truthy(controller._plant(grid.get_cell(2, 2)), "successful plant follows rollback")
	assertions.equal(
		recorder.events,
		[{"quick_index": 5, "item_id": ""}],
		"successful plant emits one committed mapping signal"
	)
	controller.free()
	inventory.free()
	farming.free()
	grid.free()


func _test_roster_planting_uses_active_quick_item(assertions: TestAssert, tree: SceneTree) -> void:
	var game_data = tree.root.get_node("GameData")
	for crop in MainScript.default_crop_definitions():
		if game_data.get_crop(crop.crop_id) == null:
			game_data.register_crop(crop)
	var fixtures := [
		{"item": "grain_seed", "crop": "grain", "season": SeasonSystem.Season.SPRING},
		{"item": "carrot_seed", "crop": "carrot", "season": SeasonSystem.Season.SPRING},
		{"item": "tomato_seed", "crop": "tomato", "season": SeasonSystem.Season.SPRING},
		{"item": "rose_seed", "crop": "rose", "season": SeasonSystem.Season.SPRING},
		{"item": "apple_sapling", "crop": "apple", "season": SeasonSystem.Season.AUTUMN},
	]
	for fixture in fixtures:
		var grid = GridSystemScript.new()
		grid.set_cell_state(10, 10, FARMLAND)
		grid.set_cell_state(11, 10, FARMLAND)
		var season = SeasonSystem.new()
		season.current_season = int(fixture.season) as SeasonSystem.Season
		var farming = FarmingSystemScript.new()
		farming.configure(grid, season, null)
		var inventory = InventorySystemScript.new()
		inventory.add_item(str(fixture.item), 1)
		inventory.set_quick_slot(0, PlayerActionControllerScript.SEED_SLOT)
		var controller = PlayerActionControllerScript.new()
		tree.root.add_child(controller)
		controller.configure(null, grid, farming, null, null, inventory)
		controller.select_slot(PlayerActionControllerScript.SEED_SLOT)
		var planted := controller.perform_cell_action(grid.get_cell(10, 10))
		assertions.truthy(planted, "%s plants from active quick slot" % fixture.item)
		assertions.equal(inventory.get_item_count(str(fixture.item)), 0, "%s consumes exact active item" % fixture.item)
		if planted:
			assertions.equal(grid.get_cell(10, 10).crop_instance.crop_data.crop_id, fixture.crop, "%s plants mapped crop" % fixture.item)
		assertions.truthy(not controller.perform_cell_action(grid.get_cell(11, 10)), "missing selected %s rejects planting" % fixture.item)
		assertions.equal(grid.get_cell(11, 10).state, FARMLAND, "missing %s preserves farmland" % fixture.item)
		controller.free()
		inventory.free()
		farming.free()
		season.free()
		grid.free()

	var lemon_grid = GridSystemScript.new()
	lemon_grid.set_cell_state(12, 10, FARMLAND)
	lemon_grid.set_cell_state(13, 10, FARMLAND)
	var lemon_season = SeasonSystem.new()
	lemon_season.current_season = SeasonSystem.Season.SUMMER
	var lemon_farming = FarmingSystemScript.new()
	lemon_farming.configure(lemon_grid, lemon_season, null)
	lemon_farming.set_greenhouse_cells([Vector2i(13, 10)])
	var lemon_inventory = InventorySystemScript.new()
	lemon_inventory.add_item("lemon_sapling", 2)
	lemon_inventory.set_quick_slot(0, PlayerActionControllerScript.SEED_SLOT)
	var lemon_controller = PlayerActionControllerScript.new()
	tree.root.add_child(lemon_controller)
	lemon_controller.configure(null, lemon_grid, lemon_farming, null, null, lemon_inventory)
	lemon_controller.select_slot(PlayerActionControllerScript.SEED_SLOT)
	assertions.truthy(not lemon_controller.perform_cell_action(lemon_grid.get_cell(12, 10)), "selected lemon sapling rejects outdoor planting")
	assertions.equal(lemon_inventory.get_item_count("lemon_sapling"), 2, "outdoor rejection preserves lemon sapling")
	var lemon_planted := lemon_controller.perform_cell_action(lemon_grid.get_cell(13, 10))
	assertions.truthy(lemon_planted, "selected lemon sapling plants in greenhouse")
	assertions.equal(lemon_inventory.get_item_count("lemon_sapling"), 1, "greenhouse planting consumes lemon sapling")
	if lemon_planted:
		assertions.equal(lemon_grid.get_cell(13, 10).crop_instance.crop_data.crop_id, "lemon", "greenhouse sapling plants lemon crop")
	lemon_controller.free()
	lemon_inventory.free()
	lemon_farming.free()
	lemon_season.free()
	lemon_grid.free()


func _test_crop_data_validation(assertions: TestAssert) -> void:
	var crop = CropDataScript.new()
	assertions.equal(crop.yield_min, 1, "crop yield minimum defaults safely")
	assertions.equal(crop.yield_max, 1, "crop yield maximum defaults safely")
	assertions.equal(crop.regrow_days, 0, "crop regrowth defaults disabled")
	assertions.equal(crop.tags, [], "crop tags default empty")
	assertions.equal(crop.growth_form, "annual", "crop form defaults annual")
	var has_plant_item_id := _has_property(crop, "plant_item_id")
	var has_environment := _has_property(crop, "environment")
	var has_lifecycle_type := _has_property(crop, "lifecycle_type")
	assertions.truthy(has_plant_item_id, "CropData exposes explicit planting item id")
	assertions.truthy(has_environment, "CropData exposes explicit planting environment")
	assertions.truthy(has_lifecycle_type, "CropData exposes explicit lifecycle type")
	assertions.truthy(crop.has_method("is_valid"), "CropData exposes strict validation")
	if not crop.has_method("is_valid") or not has_plant_item_id or not has_environment or not has_lifecycle_type:
		return
	crop.crop_id = "invalid_range"
	crop.plant_item_id = "invalid_range_seed"
	crop.yield_min = 3
	crop.yield_max = 2
	assertions.truthy(not crop.is_valid(), "yield maximum cannot be below minimum")
	crop.yield_max = 3
	crop.lifecycle_type = "tree"
	assertions.truthy(not crop.is_valid(), "persistent lifecycle requires authored regrowth")
	crop.regrow_days = 2
	crop.growth_form = "tree"
	assertions.truthy(crop.is_valid(), "well-formed persistent crop validates")
	crop.regrow_days = 4
	crop.growth_days = 3
	assertions.truthy(not crop.is_valid(), "regrowth cannot exceed the crop growth timeline")
	crop.growth_days = 4
	crop.regrow_days = 2
	crop.lifecycle_type = "annual"
	assertions.truthy(not crop.is_valid(), "annual lifecycle rejects authored regrowth")
	crop.lifecycle_type = "annual_regrow"
	crop.growth_form = "annual"
	assertions.truthy(crop.is_valid(), "annual regrow lifecycle accepts authored regrowth")
	crop.environment = "indoors"
	assertions.truthy(not crop.is_valid(), "unknown planting environment is rejected")
	crop.environment = "outdoor_or_greenhouse"
	crop.lifecycle_type = "perennial"
	assertions.truthy(not crop.is_valid(), "unknown lifecycle type is rejected")
	crop.lifecycle_type = "annual_regrow"
	crop.plant_item_id = "   "
	assertions.truthy(not crop.is_valid(), "blank planting item id is rejected")

	var mirror_crop = CropDataScript.new()
	mirror_crop.crop_id = "mirror_crop"
	mirror_crop.plant_item_id = "mirror_crop_seed"
	assertions.truthy(mirror_crop.is_valid(), "matching default compatibility mirrors validate")
	mirror_crop.environment = "greenhouse_only"
	assertions.truthy(not mirror_crop.is_valid(), "greenhouse environment requires compatibility tag")
	mirror_crop.tags.assign(["greenhouse_only"])
	assertions.truthy(mirror_crop.is_valid(), "greenhouse environment and tag agree")
	mirror_crop.environment = "outdoor_or_greenhouse"
	assertions.truthy(not mirror_crop.is_valid(), "greenhouse tag rejects outdoor environment")
	mirror_crop.tags.assign(["fruit", "flower"])
	assertions.truthy(mirror_crop.is_valid(), "unrelated fruit and flower tags remain valid")
	for lifecycle in ["annual", "annual_regrow"]:
		mirror_crop.lifecycle_type = lifecycle
		mirror_crop.regrow_days = 0 if lifecycle == "annual" else 1
		mirror_crop.growth_form = "tree"
		assertions.truthy(not mirror_crop.is_valid(), "%s lifecycle rejects persistent growth form" % lifecycle)
		mirror_crop.growth_form = "annual"
		assertions.truthy(mirror_crop.is_valid(), "%s lifecycle accepts annual growth form" % lifecycle)
	for lifecycle in ["bush", "tree", "vine"]:
		mirror_crop.lifecycle_type = lifecycle
		mirror_crop.regrow_days = 1
		mirror_crop.growth_form = "annual"
		assertions.truthy(not mirror_crop.is_valid(), "%s lifecycle rejects annual growth form" % lifecycle)
		mirror_crop.growth_form = lifecycle
		assertions.truthy(mirror_crop.is_valid(), "%s lifecycle accepts matching growth form" % lifecycle)


func _test_default_roster_and_item_catalog(assertions: TestAssert) -> void:
	var expected := [
		{"crop_id": "grain", "plant_item_id": "grain_seed", "days": 3, "yield": Vector2i(2, 4), "regrow": 0, "seasons": [0, 1, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "carrot", "plant_item_id": "carrot_seed", "days": 3, "yield": Vector2i(2, 3), "regrow": 0, "seasons": [0, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "potato", "plant_item_id": "potato_seed", "days": 4, "yield": Vector2i(3, 5), "regrow": 0, "seasons": [0, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "tomato", "plant_item_id": "tomato_seed", "days": 4, "yield": Vector2i(2, 3), "regrow": 2, "seasons": [0, 1], "lifecycle_type": "annual_regrow", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "strawberry", "plant_item_id": "strawberry_seed", "days": 4, "yield": Vector2i(2, 3), "regrow": 2, "seasons": [0], "lifecycle_type": "bush", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "blueberry", "plant_item_id": "blueberry_seed", "days": 5, "yield": Vector2i(2, 3), "regrow": 2, "seasons": [1], "lifecycle_type": "bush", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "watermelon", "plant_item_id": "watermelon_seed", "days": 5, "yield": Vector2i(1, 2), "regrow": 0, "seasons": [1], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "sunflower", "plant_item_id": "sunflower_seed", "days": 4, "yield": Vector2i(2, 3), "regrow": 0, "seasons": [1, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "lavender", "plant_item_id": "lavender_seed", "days": 4, "yield": Vector2i(2, 3), "regrow": 0, "seasons": [1, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "pumpkin", "plant_item_id": "pumpkin_seed", "days": 5, "yield": Vector2i(1, 2), "regrow": 0, "seasons": [2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "rose", "plant_item_id": "rose_seed", "days": 4, "yield": Vector2i(2, 3), "regrow": 0, "seasons": [0, 1], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "apple", "plant_item_id": "apple_sapling", "days": 5, "yield": Vector2i(2, 4), "regrow": 3, "seasons": [2], "lifecycle_type": "tree", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "peach", "plant_item_id": "peach_sapling", "days": 5, "yield": Vector2i(2, 3), "regrow": 3, "seasons": [1], "lifecycle_type": "tree", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "grape", "plant_item_id": "grape_seed", "days": 4, "yield": Vector2i(2, 4), "regrow": 2, "seasons": [1, 2], "lifecycle_type": "vine", "environment": "outdoor_or_greenhouse"},
		{"crop_id": "lemon", "plant_item_id": "lemon_sapling", "days": 5, "yield": Vector2i(2, 3), "regrow": 3, "seasons": [], "lifecycle_type": "tree", "environment": "greenhouse_only"},
	]
	var main = MainScript.new()
	assertions.truthy(main.has_method("default_crop_definitions"), "Main exposes deterministic default crop roster")
	if main.has_method("default_crop_definitions"):
		var definitions: Array = main.call("default_crop_definitions")
		var by_id := {}
		for crop in definitions:
			by_id[crop.crop_id] = crop
		assertions.equal(by_id.size(), expected.size(), "default roster contains every crop exactly once")
		var game_data = GameDataScript.new()
		var has_plant_lookup := game_data.has_method("get_crop_for_plant_item")
		assertions.truthy(has_plant_lookup, "GameData exposes explicit planting-item lookup")
		for authored in expected:
			var crop_id := str(authored.crop_id)
			assertions.truthy(by_id.has(crop_id), "%s is registered in default roster" % crop_id)
			if not by_id.has(crop_id):
				continue
			var crop = by_id[crop_id]
			assertions.equal(crop.growth_days, authored.days, "%s growth days match design" % crop_id)
			assertions.equal(Vector2i(crop.yield_min, crop.yield_max), authored.yield, "%s yield matches design" % crop_id)
			assertions.equal(crop.regrow_days, authored.regrow, "%s regrowth matches design" % crop_id)
			assertions.equal(crop.seasons, authored.seasons, "%s seasons match design" % crop_id)
			assertions.equal(_property_value(crop, "plant_item_id"), authored.plant_item_id, "%s planting item matches design" % crop_id)
			assertions.equal(_property_value(crop, "lifecycle_type"), authored.lifecycle_type, "%s lifecycle matches design" % crop_id)
			assertions.equal(_property_value(crop, "environment"), authored.environment, "%s environment matches design" % crop_id)
			assertions.truthy(crop.is_valid(), "%s default definition validates" % crop_id)
			assertions.truthy(game_data.register_crop(crop), "%s registers in explicit crop catalog" % crop_id)
			var plant_item = GameDataScript.get_item(str(authored.plant_item_id))
			var crop_product = GameDataScript.get_item(crop_id)
			assertions.equal(str(plant_item.get("category", "")) if plant_item else "", "seed", "%s planting item category is seed" % crop_id)
			assertions.equal(str(crop_product.get("category", "")) if crop_product else "", "crop", "%s product category is crop" % crop_id)
			if has_plant_lookup:
				assertions.truthy(game_data.call("get_crop_for_plant_item", authored.plant_item_id) == crop, "%s planting lookup returns exact crop" % crop_id)
		if has_plant_lookup:
			assertions.truthy(game_data.call("get_crop_for_plant_item", "unknown_seed") == null, "unknown planting item has no crop mapping")
			var duplicate = CropDataScript.new()
			duplicate.crop_id = "duplicate_grain"
			duplicate.plant_item_id = "grain_seed"
			duplicate.growth_days = 1
			duplicate.environment = "outdoor_or_greenhouse"
			duplicate.lifecycle_type = "annual"
			var original = game_data.call("get_crop_for_plant_item", "grain_seed")
			assertions.truthy(not game_data.register_crop(duplicate), "duplicate planting item registration is rejected")
			assertions.truthy(game_data.call("get_crop_for_plant_item", "grain_seed") == original, "duplicate registration preserves original planting mapping")
			assertions.truthy(game_data.get_crop("grain") == original, "duplicate registration preserves original crop id mapping")
			assertions.truthy(game_data.get_crop("duplicate_grain") == null, "duplicate registration does not add crop id")
			var duplicate_crop_id = CropDataScript.new()
			duplicate_crop_id.crop_id = "grain"
			duplicate_crop_id.plant_item_id = "alternate_grain_seed"
			duplicate_crop_id.growth_days = 1
			assertions.truthy(not game_data.register_crop(duplicate_crop_id), "duplicate crop id registration is rejected")
			assertions.truthy(game_data.get_crop("grain") == original, "crop id collision preserves original crop registry")
			assertions.truthy(game_data.call("get_crop_for_plant_item", "grain_seed") == original, "crop id collision preserves original planting lookup")
			assertions.truthy(game_data.call("get_crop_for_plant_item", "alternate_grain_seed") == null, "crop id collision does not add unique planting lookup")
		game_data.free()
	main.free()

	var inventory_ids := [
		"grain_seed", "carrot_seed", "potato_seed", "tomato_seed", "strawberry_seed",
		"blueberry_seed", "watermelon_seed", "sunflower_seed", "lavender_seed",
		"pumpkin_seed", "rose_seed", "apple_sapling", "peach_sapling", "grape_seed",
		"lemon_sapling", "grain", "carrot", "potato", "tomato", "strawberry",
		"blueberry", "watermelon", "sunflower", "lavender", "pumpkin", "rose",
		"apple", "peach", "grape", "lemon",
	]
	for item_id in inventory_ids:
		assertions.truthy(GameDataScript.get_item(item_id) != null, "%s exists in production inventory catalog" % item_id)


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _property_value(object: Object, property_name: String) -> Variant:
	return object.get(property_name) if _has_property(object, property_name) else null


func _set_property_if_present(object: Object, property_name: String, value: Variant) -> void:
	if _has_property(object, property_name):
		object.set(property_name, value)


func _set_mature(instance: CropInstance, progress: float) -> void:
	instance.set_growth_state(progress, CropInstance.LifecycleState.MATURE)


func _test_perennial_harvest_and_greenhouse_rules(assertions: TestAssert) -> void:
	for crop_id in ["apple", "peach", "grape", "lemon"]:
		var crop = CropDataScript.new()
		crop.crop_id = crop_id
		crop.growth_days = 5
		crop.yield_min = 2
		crop.yield_max = 3
		crop.regrow_days = 3
		crop.lifecycle_type = "vine" if crop_id == "grape" else "tree"
		crop.growth_form = crop.lifecycle_type
		var grid = GridSystemScript.new()
		grid.set_cell_state(5, 5, FARMLAND)
		var instance = grid.plant_crop(5, 5, crop)
		_set_mature(instance, 5.0)
		var result: Dictionary = _harvest(grid, 5, 5)
		assertions.truthy(bool(result.get("regrowing", false)), "%s harvest reports persistent regrowth" % crop_id)
		assertions.equal(grid.get_cell(5, 5).state, PLANTED, "%s remains planted after harvest" % crop_id)
		assertions.truthy(grid.get_cell(5, 5).crop_instance == instance, "%s preserves perennial instance" % crop_id)
		grid.free()

	var lemon = CropDataScript.new()
	lemon.crop_id = "lemon"
	lemon.growth_days = 5
	lemon.yield_min = 2
	lemon.yield_max = 3
	lemon.regrow_days = 3
	lemon.lifecycle_type = "tree"
	lemon.environment = "greenhouse_only"
	lemon.growth_form = "tree"
	lemon.tags.assign(["fruit", "greenhouse_only"])
	var grid = GridSystemScript.new()
	grid.set_cell_state(7, 7, FARMLAND)
	grid.set_cell_state(8, 8, FARMLAND)
	var farming = FarmingSystemScript.new()
	var season = SeasonSystem.new()
	season.current_season = SeasonSystem.Season.SUMMER
	farming.configure(grid, season, null)
	farming.set_greenhouse_cells([Vector2i(8, 8)])
	assertions.truthy(not farming.can_plant(grid.get_cell(7, 7), lemon), "greenhouse-only lemon rejects outdoor planting")
	assertions.truthy(farming.can_plant(grid.get_cell(8, 8), lemon), "greenhouse hook permits lemon planting")
	farming.free()
	season.free()
	grid.free()


func _test_regrowing_crop_visual_remains(assertions: TestAssert) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "visual_tomato"
	crop.growth_days = 4
	crop.yield_min = 2
	crop.yield_max = 3
	crop.regrow_days = 2
	crop.lifecycle_type = "annual_regrow"
	crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	farming.configure(grid, null, null)
	grid.set_cell_state(9, 9, FARMLAND)
	var cell = grid.get_cell(9, 9)
	var instance = farming.plant(cell, crop)
	_set_mature(instance, 4.0)
	assertions.truthy(farming.get_crop_visual(cell) != null, "regrowth fixture starts with a crop visual")
	var result := farming.harvest(cell)
	assertions.truthy(bool(result.get("regrowing", false)), "visual fixture harvest regrows")
	assertions.truthy(farming.get_crop_visual(cell) != null, "regrowing crop visual remains after harvest")
	farming.free()
	grid.free()


func _preview_harvest(grid: GridSystem, gx: int, gz: int) -> Dictionary:
	var farming := FarmingSystemScript.new()
	farming.configure(grid, null, null)
	var result: Dictionary = farming.preview_harvest(grid.get_cell(gx, gz))
	farming.free()
	return result


func _harvest(grid: GridSystem, gx: int, gz: int) -> Dictionary:
	var farming := FarmingSystemScript.new()
	farming.configure(grid, null, null)
	var result: Dictionary = farming.harvest(grid.get_cell(gx, gz))
	farming.free()
	return result
