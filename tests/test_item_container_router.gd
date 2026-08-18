extends RefCounted

const RouterScript = preload("res://scripts/systems/item_container_router.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const FarmStorageSystemScript = preload("res://scripts/systems/farm_storage_system.gd")


class FailingStorage:
	extends FarmStorageSystemScript

	var fail_next_add := false
	var fail_next_remove := false
	var saw_blocked_event_bus := false

	func stage_add_items(token: Variant, requested: Dictionary) -> bool:
		var event_bus := get_node_or_null("/root/EventBus")
		saw_blocked_event_bus = event_bus != null and event_bus.is_blocking_signals()
		if fail_next_add:
			fail_next_add = false
			return false
		return super.stage_add_items(token, requested)

	func stage_remove_items(token: Variant, requested: Dictionary) -> bool:
		var event_bus := get_node_or_null("/root/EventBus")
		saw_blocked_event_bus = event_bus != null and event_bus.is_blocking_signals()
		if fail_next_remove:
			fail_next_remove = false
			return false
		return super.stage_remove_items(token, requested)


class EventRecorder:
	extends RefCounted

	var router: Node
	var records: Array[Dictionary] = []

	func _init(configured_router: Node) -> void:
		router = configured_router

	func on_item_added(item_id: String, quantity: int) -> void:
		records.append(_record("inventory_add", item_id, quantity))

	func on_item_removed(item_id: String, quantity: int) -> void:
		records.append(_record("inventory_remove", item_id, quantity))

	func on_storage_changed(changes: Dictionary) -> void:
		var item_id := str(changes.keys()[0]) if not changes.is_empty() else ""
		records.append(_record("storage", item_id, int(changes.get(item_id, 0))))

	func _record(kind: String, item_id: String, quantity: int) -> Dictionary:
		return {
			"kind": kind,
			"item_id": item_id,
			"quantity": quantity,
			"wood": router.get_count("wood"),
			"grain": router.get_count("grain"),
		}


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_explicit_category_routing(assertions, tree)
	_test_unknown_and_invalid_requests(assertions, tree)
	_test_structured_preflight_failures(assertions, tree)
	_test_mixed_add_remove_and_snapshot_restore(assertions, tree)
	_test_mixed_add_rolls_back_exactly(assertions, tree)
	_test_mixed_remove_rolls_back_exactly(assertions, tree)
	_test_mixed_events_publish_only_after_commit(assertions, tree)


func _test_explicit_category_routing(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var router: Node = fixture.router
	assertions.equal(router.container_kind("grain_seed"), &"inventory", "seed routes to inventory")
	assertions.equal(router.container_kind("grain"), &"farm_storage", "crop routes to farm storage")
	assertions.equal(router.container_kind("wood"), &"inventory", "existing material routes to inventory")
	assertions.truthy(router.add_items({"grain_seed": 2, "grain": 3, "wood": 4}), "typed mixed add succeeds")
	assertions.equal(fixture.inventory.get_item_count("grain_seed"), 2, "seed is stored in inventory")
	assertions.equal(fixture.inventory.get_item_count("wood"), 4, "material is stored in inventory")
	assertions.equal(fixture.storage.get_count("grain"), 3, "crop is stored in farm storage")
	assertions.equal(router.get_count("grain_seed"), 2, "router reads inventory count")
	assertions.equal(router.get_count("grain"), 3, "router reads storage count")
	_free_fixture(fixture)


func _test_unknown_and_invalid_requests(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var router: Node = fixture.router
	assertions.equal(router.container_kind("missing_item"), &"unknown", "unknown item has no inferred container")
	for operation in [&"can_add", &"can_remove"]:
		var result: Dictionary = router.call(operation, {"missing_item": 1})
		assertions.equal(result.get("reason"), "unknown_item", "%s reports stable unknown reason" % operation)
		assertions.equal(result.get("item_id"), "missing_item", "%s identifies unknown item" % operation)
	assertions.truthy(not router.add_items({"missing_item": 1}), "unknown add does not mutate")
	assertions.truthy(not router.remove_items({"missing_item": 1}), "unknown remove does not mutate")
	for invalid in [{}, {"wood": 0}, {"wood": -1}, {"wood": 1.5}, {7: 1}]:
		assertions.equal(router.can_add(invalid).get("reason"), "invalid_request", "invalid add request is rejected")
		assertions.equal(router.can_remove(invalid).get("reason"), "invalid_request", "invalid remove request is rejected")
	_free_fixture(fixture)


func _test_structured_preflight_failures(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree, 2)
	var router: Node = fixture.router
	assertions.truthy(fixture.storage.add_items({"grain": 1}), "capacity fixture stores initial crop")
	var storage_full: Dictionary = router.can_add({"grain": 3})
	assertions.equal(storage_full.get("reason"), "storage_capacity", "crop capacity has stable reason")
	assertions.equal(storage_full.get("missing_capacity"), 2, "crop capacity reports exact shortfall")
	assertions.equal(storage_full.get("item_id"), "grain", "crop capacity identifies item")

	var full_slots: Array[Dictionary] = []
	for _index in range(fixture.inventory.max_slots):
		full_slots.append({"item_id": "stone", "quantity": 99})
	fixture.inventory.restore_state(full_slots, [-1, -1, -1, -1, -1, -1])
	var inventory_full: Dictionary = router.can_add({"wood": 1})
	assertions.equal(inventory_full.get("reason"), "inventory_capacity", "backpack capacity has stable reason")
	assertions.equal(inventory_full.get("item_id"), "wood", "backpack capacity identifies item")

	var missing_seed: Dictionary = router.can_remove({"grain_seed": 2})
	assertions.equal(missing_seed.get("reason"), "insufficient_seed", "seed shortage has category reason")
	assertions.equal(missing_seed.get("missing_quantity"), 2, "seed shortage is exact")
	var missing_crop: Dictionary = router.can_remove({"grain": 2})
	assertions.equal(missing_crop.get("reason"), "insufficient_crop", "crop shortage has category reason")
	assertions.equal(missing_crop.get("missing_quantity"), 1, "crop shortage is exact")
	var missing_resource: Dictionary = router.can_remove({"wood": 1})
	assertions.equal(missing_resource.get("reason"), "insufficient_resources", "material shortage uses generic reason")
	_free_fixture(fixture)


func _test_mixed_add_remove_and_snapshot_restore(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var router: Node = fixture.router
	assertions.truthy(router.can_add({"grain": 2, "wood": 3}).get("ok", false), "mixed add preflight succeeds")
	assertions.truthy(router.add_items({"grain": 2, "wood": 3}), "mixed add succeeds")
	fixture.inventory.set_quick_slot(0, 0)
	var snapshot: Dictionary = router.snapshot_for({"grain": 1, "wood": 1})
	assertions.truthy(not snapshot.is_empty(), "mixed snapshot is created")
	assertions.truthy(router.can_remove({"grain": 1, "wood": 2}).get("ok", false), "mixed remove preflight succeeds")
	assertions.truthy(router.remove_items({"grain": 1, "wood": 2}), "mixed remove succeeds")
	assertions.equal(router.get_count("grain"), 1, "mixed remove consumes crop")
	assertions.equal(router.get_count("wood"), 1, "mixed remove consumes material")
	assertions.truthy(router.restore_snapshot(snapshot), "snapshot restores both containers")
	assertions.equal(router.get_count("grain"), 2, "snapshot restores crop exactly")
	assertions.equal(router.get_count("wood"), 3, "snapshot restores inventory exactly")
	assertions.equal(fixture.inventory.quick_slot_mappings[0], 0, "snapshot restores quick mapping exactly")
	_free_fixture(fixture)


func _test_mixed_add_rolls_back_exactly(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var router: Node = fixture.router
	assertions.truthy(fixture.inventory.add_item("wood", 1), "rollback fixture adds initial material")
	fixture.inventory.set_quick_slot(0, 0)
	var before_slots: Array = fixture.inventory.slots.duplicate(true)
	var before_mappings: Array = fixture.inventory.quick_slot_mappings.duplicate()
	var before_storage: Dictionary = fixture.storage.get_items().duplicate(true)
	fixture.storage.fail_next_add = true
	assertions.truthy(not router.add_items({"wood": 2, "grain": 2}), "second-container add failure is reported")
	assertions.equal(fixture.inventory.slots, before_slots, "failed add restores inventory slots exactly")
	assertions.equal(fixture.inventory.quick_slot_mappings, before_mappings, "failed add restores mappings exactly")
	assertions.equal(fixture.storage.get_items(), before_storage, "failed add restores storage exactly")
	assertions.truthy(fixture.storage.saw_blocked_event_bus, "mixed add blocks EventBus during mutation")
	_free_fixture(fixture)


func _test_mixed_remove_rolls_back_exactly(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var router: Node = fixture.router
	assertions.truthy(router.add_items({"wood": 3, "grain": 3}), "remove rollback fixture is populated")
	fixture.inventory.set_quick_slot(0, 0)
	var before_slots: Array = fixture.inventory.slots.duplicate(true)
	var before_mappings: Array = fixture.inventory.quick_slot_mappings.duplicate()
	var before_storage: Dictionary = fixture.storage.get_items().duplicate(true)
	fixture.storage.fail_next_remove = true
	assertions.truthy(not router.remove_items({"wood": 2, "grain": 2}), "second-container remove failure is reported")
	assertions.equal(fixture.inventory.slots, before_slots, "failed remove restores inventory slots exactly")
	assertions.equal(fixture.inventory.quick_slot_mappings, before_mappings, "failed remove restores mappings exactly")
	assertions.equal(fixture.storage.get_items(), before_storage, "failed remove restores storage exactly")
	assertions.truthy(fixture.storage.saw_blocked_event_bus, "mixed remove blocks EventBus during mutation")
	_free_fixture(fixture)


func _test_mixed_events_publish_only_after_commit(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var router: Node = fixture.router
	var event_bus := tree.root.get_node("EventBus")
	var recorder := EventRecorder.new(router)
	event_bus.item_added.connect(recorder.on_item_added)
	event_bus.item_removed.connect(recorder.on_item_removed)
	event_bus.farm_storage_changed.connect(recorder.on_storage_changed)

	assertions.truthy(router.add_items({"wood": 2, "grain": 2}), "event fixture mixed add succeeds")
	assertions.equal(recorder.records.size(), 2, "successful mixed add publishes one event per container")
	for record in recorder.records:
		assertions.equal(record.wood, 2, "add listener observes committed inventory")
		assertions.equal(record.grain, 2, "add listener observes committed storage")
	recorder.records.clear()
	fixture.storage.fail_next_remove = true
	assertions.truthy(not router.remove_items({"wood": 1, "grain": 1}), "event fixture mixed remove fails")
	assertions.equal(recorder.records.size(), 0, "failed mixed mutation publishes no success events")

	event_bus.item_added.disconnect(recorder.on_item_added)
	event_bus.item_removed.disconnect(recorder.on_item_removed)
	event_bus.farm_storage_changed.disconnect(recorder.on_storage_changed)
	_free_fixture(fixture)


func _make_fixture(tree: SceneTree, capacity: int = 200) -> Dictionary:
	var inventory := InventorySystemScript.new()
	var storage := FailingStorage.new()
	var router := RouterScript.new()
	inventory.name = "RouterTestInventory"
	storage.name = "RouterTestStorage"
	storage.configure(func() -> int: return capacity)
	tree.root.add_child(inventory)
	tree.root.add_child(storage)
	assert(router.configure(inventory, storage))
	return {"router": router, "inventory": inventory, "storage": storage}


func _free_fixture(fixture: Dictionary) -> void:
	fixture.inventory.get_parent().remove_child(fixture.inventory)
	fixture.storage.get_parent().remove_child(fixture.storage)
	fixture.inventory.free()
	fixture.storage.free()
	fixture.router.free()
