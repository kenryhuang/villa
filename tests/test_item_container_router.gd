extends RefCounted

const RouterScript = preload("res://scripts/systems/item_container_router.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const FarmStorageSystemScript = preload("res://scripts/systems/farm_storage_system.gd")


class FailingInventory:
	extends InventorySystemScript

	var fail_add_item_id := ""
	var fail_remove_item_id := ""
	var restore_calls := 0

	func add_item(item_id: String, quantity: int = 1) -> bool:
		if item_id == fail_add_item_id:
			fail_add_item_id = ""
			super.add_item(item_id, mini(quantity, 1))
			return false
		return super.add_item(item_id, quantity)

	func remove_item(item_id: String, quantity: int = 1) -> bool:
		if item_id == fail_remove_item_id:
			fail_remove_item_id = ""
			super.remove_item(item_id, mini(quantity, 1))
			return false
		return super.remove_item(item_id, quantity)

	func restore_state(saved_slots: Variant, saved_quick_mappings: Variant) -> void:
		restore_calls += 1
		super.restore_state(saved_slots, saved_quick_mappings)


class FailingStorage:
	extends FarmStorageSystemScript

	var fail_next_add := false
	var fail_next_remove := false
	var fail_next_restore := false
	var fail_all_restores := false
	var restore_calls := 0
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

	func restore_items_unchecked(items: Dictionary) -> bool:
		restore_calls += 1
		if fail_all_restores or fail_next_restore:
			fail_next_restore = false
			return false
		return super.restore_items_unchecked(items)


class EventRecorder:
	extends RefCounted

	var router: Node
	var records: Array[Dictionary] = []
	var quick_records: Array[Dictionary] = []
	var local_storage_records: Array[Dictionary] = []

	func _init(configured_router: Node) -> void:
		router = configured_router

	func on_item_added(item_id: String, quantity: int) -> void:
		records.append(_record("inventory_add", item_id, quantity))

	func on_item_removed(item_id: String, quantity: int) -> void:
		records.append(_record("inventory_remove", item_id, quantity))

	func on_storage_changed(changes: Dictionary) -> void:
		var item_id := str(changes.keys()[0]) if not changes.is_empty() else ""
		records.append(_record("storage", item_id, int(changes.get(item_id, 0))))

	func on_local_storage_changed(changes: Dictionary) -> void:
		var item_id := str(changes.keys()[0]) if not changes.is_empty() else ""
		local_storage_records.append(_record("local_storage", item_id, int(changes.get(item_id, 0))))

	func on_quick_changed(quick_index: int, item_id: String) -> void:
		quick_records.append(_record("quick:%d" % quick_index, item_id, 0))

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
	_test_inventory_capacity_identifies_actual_missing_item(assertions, tree)
	_test_composable_publish_observes_final_state(assertions, tree)
	_test_composable_cancel_is_exact_and_silent(assertions, tree)
	_test_failing_inventory_add_and_remove_are_exact_and_silent(assertions, tree)
	_test_restore_snapshot_is_atomic_on_storage_failure(assertions, tree)
	_test_restore_snapshot_uses_normalized_inventory_state(assertions, tree)
	_test_multistage_failure_keeps_original_rollback_boundary(assertions, tree)
	_test_failed_stage_does_not_leak_inventory_event_delta(assertions, tree)
	await _test_late_abandonment_recovers_without_router_call(assertions, tree)
	_test_publish_reentrancy_is_rejected(assertions, tree)
	await _test_reparent_restores_abandonment_monitor(assertions, tree)
	await _test_publish_callbacks_can_release_dependencies(assertions, tree)
	await _test_exit_tree_and_invalid_dependency_release_locks(assertions, tree)
	_test_blocked_event_bus_keeps_publication_retryable(assertions, tree)
	_test_persistent_storage_restore_failure_is_non_mutating(assertions, tree)
	await _test_transaction_ownership_and_abandonment(assertions, tree)
	_test_unconfigured_and_invalid_containers(assertions, tree)
	await tree.process_frame


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
	var recorder := _connect_recorder(fixture, tree)
	fixture.storage.fail_next_add = true
	assertions.truthy(not router.add_items({"wood": 2, "grain": 2}), "second-container add failure is reported")
	assertions.equal(fixture.inventory.slots, before_slots, "failed add restores inventory slots exactly")
	assertions.equal(fixture.inventory.quick_slot_mappings, before_mappings, "failed add restores mappings exactly")
	assertions.equal(fixture.storage.get_items(), before_storage, "failed add restores storage exactly")
	assertions.truthy(fixture.storage.saw_blocked_event_bus, "mixed add blocks EventBus during mutation")
	_assert_recorder_silent(assertions, recorder, "second-container add failure")
	_disconnect_recorder(fixture, tree, recorder)
	_free_fixture(fixture)


func _test_mixed_remove_rolls_back_exactly(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var router: Node = fixture.router
	assertions.truthy(router.add_items({"wood": 3, "grain": 3}), "remove rollback fixture is populated")
	fixture.inventory.set_quick_slot(0, 0)
	var before_slots: Array = fixture.inventory.slots.duplicate(true)
	var before_mappings: Array = fixture.inventory.quick_slot_mappings.duplicate()
	var before_storage: Dictionary = fixture.storage.get_items().duplicate(true)
	var recorder := _connect_recorder(fixture, tree)
	fixture.storage.fail_next_remove = true
	assertions.truthy(not router.remove_items({"wood": 2, "grain": 2}), "second-container remove failure is reported")
	assertions.equal(fixture.inventory.slots, before_slots, "failed remove restores inventory slots exactly")
	assertions.equal(fixture.inventory.quick_slot_mappings, before_mappings, "failed remove restores mappings exactly")
	assertions.equal(fixture.storage.get_items(), before_storage, "failed remove restores storage exactly")
	assertions.truthy(fixture.storage.saw_blocked_event_bus, "mixed remove blocks EventBus during mutation")
	_assert_recorder_silent(assertions, recorder, "second-container remove failure")
	_disconnect_recorder(fixture, tree, recorder)
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


func _test_inventory_capacity_identifies_actual_missing_item(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var fixture := _make_fixture(tree)
	fixture.inventory.max_slots = 2
	fixture.inventory.restore_state(
		[
			{"item_id": "stone", "quantity": 98},
			{"item_id": "grain_seed", "quantity": 99},
		],
		[-1, -1, -1, -1, -1, -1]
	)
	var result: Dictionary = fixture.router.can_add({"stone": 1, "wood": 1})
	assertions.equal(result.get("reason"), "inventory_capacity", "mixed backpack capacity fails")
	assertions.equal(result.get("item_id"), "wood", "capacity identifies the actually missing item")
	assertions.equal(result.get("missing", {}).get("wood"), 1, "capacity retains exact missing batch")
	_free_fixture(fixture)


func _test_composable_publish_observes_final_state(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	assertions.truthy(fixture.router.add_items({"wood": 2, "grain": 2}), "publish fixture is populated")
	assertions.truthy(
		fixture.inventory.set_quick_slot(_item_slot(fixture.inventory, "wood"), 0),
		"publish fixture maps removed item"
	)
	var recorder := _connect_recorder(fixture, tree)
	var token: RefCounted = fixture.router.begin_atomic_transaction()
	assertions.truthy(token != null, "outer transaction begins")
	assertions.truthy(
		fixture.router.stage_remove_items(token, {"wood": 2, "grain": 2}),
		"outer transaction stages mixed removal"
	)
	assertions.equal(fixture.router.get_count("wood"), 0, "staged removal changes inventory state")
	assertions.equal(fixture.router.get_count("grain"), 0, "staged removal changes storage state")
	assertions.equal(recorder.records.size(), 0, "stage publishes no EventBus events")
	assertions.equal(recorder.quick_records.size(), 0, "stage publishes no quick mapping events")
	assertions.equal(recorder.local_storage_records.size(), 0, "stage publishes no storage events")
	var publication: RefCounted = fixture.router.seal_atomic_transaction(token)
	assertions.truthy(publication != null, "outer transaction seals publication")
	assertions.equal(recorder.records.size(), 0, "seal publishes no EventBus events")
	assertions.equal(recorder.quick_records.size(), 0, "seal publishes no quick mapping events")
	assertions.equal(recorder.local_storage_records.size(), 0, "seal publishes no storage events")
	var has_finalize: bool = (
		fixture.router.has_method("finalize_sealed_publication")
		and fixture.router.has_method("dispatch_finalized_publication")
	)
	assertions.truthy(has_finalize, "router exposes finalized publication batches")
	if not has_finalize:
		fixture.router.cancel_sealed_transaction(publication)
		_disconnect_recorder(fixture, tree, recorder)
		_free_fixture(fixture)
		return
	var outer_events := [0]
	var on_outer_event := func(_gold: int) -> void: outer_events[0] += 1
	tree.root.get_node("EventBus").gold_changed.connect(on_outer_event)
	tree.root.get_node("EventBus").gold_changed.emit(99)
	assertions.equal(outer_events[0], 1, "sealed router does not swallow outer-domain events")
	tree.root.get_node("EventBus").gold_changed.disconnect(on_outer_event)
	var batch: Variant = fixture.router.call("finalize_sealed_publication", publication)
	assertions.truthy(batch is RefCounted, "router finalizes publication to a batch")
	assertions.equal(recorder.records.size(), 0, "router finalize emits no EventBus event")
	assertions.equal(recorder.quick_records.size(), 0, "router finalize emits no mapping event")
	assertions.equal(recorder.local_storage_records.size(), 0, "router finalize emits no storage event")
	assertions.truthy(
		bool(fixture.router.call("dispatch_finalized_publication", batch)),
		"router finalized batch dispatches"
	)
	assertions.equal(recorder.records.size(), 2, "publish emits both container EventBus events")
	assertions.equal(recorder.quick_records.size(), 1, "publish emits deferred quick mapping event")
	assertions.equal(recorder.local_storage_records.size(), 1, "publish emits deferred storage event")
	for record in recorder.records + recorder.quick_records + recorder.local_storage_records:
		assertions.equal(record.wood, 0, "publish listener sees final inventory state")
		assertions.equal(record.grain, 0, "publish listener sees final storage state")
	assertions.truthy(
		not bool(fixture.router.call("dispatch_finalized_publication", batch)),
		"router finalized batch cannot dispatch twice"
	)
	_disconnect_recorder(fixture, tree, recorder)
	_free_fixture(fixture)


func _test_composable_cancel_is_exact_and_silent(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var recorder := _connect_recorder(fixture, tree)
	var before_slots: Array = fixture.inventory.slots.duplicate(true)
	var before_mappings: Array = fixture.inventory.quick_slot_mappings.duplicate()
	var before_storage: Dictionary = fixture.storage.get_items().duplicate(true)
	var token: RefCounted = fixture.router.begin_atomic_transaction()
	assertions.truthy(
		fixture.router.stage_add_items(token, {"wood": 2, "grain": 2}),
		"cancel fixture stages mixed add"
	)
	var publication: RefCounted = fixture.router.seal_atomic_transaction(token)
	assertions.truthy(publication != null, "cancel fixture seals publication")
	assertions.truthy(fixture.router.cancel_sealed_transaction(publication), "outer failure cancels publication")
	assertions.equal(fixture.inventory.slots, before_slots, "cancel restores inventory slots exactly")
	assertions.equal(fixture.inventory.quick_slot_mappings, before_mappings, "cancel restores mappings exactly")
	assertions.equal(fixture.storage.get_items(), before_storage, "cancel restores storage exactly")
	_assert_recorder_silent(assertions, recorder, "cancel")
	assertions.truthy(not fixture.router.cancel_sealed_transaction(publication), "publication cannot cancel twice")
	_disconnect_recorder(fixture, tree, recorder)
	_free_fixture(fixture)


func _test_failing_inventory_add_and_remove_are_exact_and_silent(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var add_fixture := _make_fixture(tree)
	var add_recorder := _connect_recorder(add_fixture, tree)
	var add_slots: Array = add_fixture.inventory.slots.duplicate(true)
	var add_mappings: Array = add_fixture.inventory.quick_slot_mappings.duplicate()
	var add_storage: Dictionary = add_fixture.storage.get_items().duplicate(true)
	add_fixture.inventory.fail_add_item_id = "wood"
	assertions.truthy(
		not add_fixture.router.add_items({"grain_seed": 2, "wood": 2, "grain": 2}),
		"inventory mid-add failure aborts mixed batch"
	)
	assertions.equal(add_fixture.inventory.slots, add_slots, "mid-add restores inventory slots exactly")
	assertions.equal(add_fixture.inventory.quick_slot_mappings, add_mappings, "mid-add restores mappings exactly")
	assertions.equal(add_fixture.storage.get_items(), add_storage, "mid-add restores storage exactly")
	_assert_recorder_silent(assertions, add_recorder, "mid-add")
	_disconnect_recorder(add_fixture, tree, add_recorder)
	_free_fixture(add_fixture)

	var remove_fixture := _make_fixture(tree)
	assertions.truthy(
		remove_fixture.router.add_items({"grain_seed": 2, "wood": 2, "grain": 2}),
		"remove failure fixture is populated"
	)
	remove_fixture.inventory.set_quick_slot(_item_slot(remove_fixture.inventory, "wood"), 0)
	var remove_recorder := _connect_recorder(remove_fixture, tree)
	var remove_slots: Array = remove_fixture.inventory.slots.duplicate(true)
	var remove_mappings: Array = remove_fixture.inventory.quick_slot_mappings.duplicate()
	var remove_storage: Dictionary = remove_fixture.storage.get_items().duplicate(true)
	remove_fixture.inventory.fail_remove_item_id = "wood"
	assertions.truthy(
		not remove_fixture.router.remove_items({"grain_seed": 1, "wood": 2, "grain": 1}),
		"inventory mid-remove failure aborts mixed batch"
	)
	assertions.equal(remove_fixture.inventory.slots, remove_slots, "mid-remove restores slots exactly")
	assertions.equal(remove_fixture.inventory.quick_slot_mappings, remove_mappings, "mid-remove restores mappings")
	assertions.equal(remove_fixture.storage.get_items(), remove_storage, "mid-remove restores storage exactly")
	_assert_recorder_silent(assertions, remove_recorder, "mid-remove")
	_disconnect_recorder(remove_fixture, tree, remove_recorder)
	_free_fixture(remove_fixture)


func _test_restore_snapshot_is_atomic_on_storage_failure(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var fixture := _make_fixture(tree)
	assertions.truthy(fixture.router.add_items({"wood": 2, "grain": 2}), "restore target is populated")
	fixture.inventory.set_quick_slot(_item_slot(fixture.inventory, "wood"), 0)
	var target: Dictionary = fixture.router.snapshot_for({"wood": 1, "grain": 1})
	assertions.truthy(fixture.router.add_items({"wood": 1, "grain": 1}), "restore current state diverges")
	var before_slots: Array = fixture.inventory.slots.duplicate(true)
	var before_mappings: Array = fixture.inventory.quick_slot_mappings.duplicate()
	var before_storage: Dictionary = fixture.storage.get_items().duplicate(true)
	var recorder := _connect_recorder(fixture, tree)
	fixture.storage.fail_next_restore = true
	assertions.truthy(not fixture.router.restore_snapshot(target), "storage restore failure is reported")
	assertions.equal(fixture.inventory.slots, before_slots, "failed restore restores calling inventory state")
	assertions.equal(fixture.inventory.quick_slot_mappings, before_mappings, "failed restore restores mappings")
	assertions.equal(fixture.storage.get_items(), before_storage, "failed restore preserves calling storage state")
	_assert_recorder_silent(assertions, recorder, "failed restore")
	_disconnect_recorder(fixture, tree, recorder)
	_free_fixture(fixture)


func _test_restore_snapshot_uses_normalized_inventory_state(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var fixture := _make_fixture(tree)
	var legacy_snapshot := {
		&"inventory": {
			"slots": [{"item_id": "iron", "quantity": 2.0}],
			"quick_mappings": [0.0, -1.0, -1.0, -1.0, -1.0, -1.0],
		},
	}
	assertions.truthy(fixture.router.restore_snapshot(legacy_snapshot), "integral legacy snapshot normalizes")
	assertions.equal(fixture.inventory.get_item_count("iron"), 0, "legacy source ID is not restored raw")
	assertions.equal(fixture.inventory.get_item_count("iron_ingot"), 2, "legacy source migrates to canonical item")
	assertions.equal(
		typeof(fixture.inventory.slots[0].quantity),
		TYPE_INT,
		"integral float quantity restores as canonical integer"
	)
	assertions.equal(fixture.inventory.quick_slot_mappings[0], 0, "float mapping restores as integer")
	var before_slots: Array = fixture.inventory.slots.duplicate(true)
	var hostile := legacy_snapshot.duplicate(true)
	hostile[&"inventory"].slots[0].quantity = 1.5
	assertions.truthy(not fixture.router.restore_snapshot(hostile), "fractional snapshot is rejected")
	assertions.equal(fixture.inventory.slots, before_slots, "rejected snapshot does not mutate inventory")

	assertions.truthy(fixture.router.add_items({"grain": 1}), "read-only snapshot fixture adds storage")
	var public_snapshot: Dictionary = fixture.router.snapshot_for({"iron_ingot": 1, "grain": 1})
	assertions.truthy(public_snapshot.is_read_only(), "public snapshot root is read-only")
	assertions.truthy(public_snapshot[&"inventory"].is_read_only(), "inventory snapshot is read-only")
	assertions.truthy(public_snapshot[&"inventory"].slots.is_read_only(), "snapshot slots are read-only")
	assertions.truthy(public_snapshot[&"inventory"].slots[0].is_read_only(), "snapshot slot is read-only")
	assertions.truthy(public_snapshot[&"inventory"].quick_mappings.is_read_only(), "snapshot mappings are read-only")
	assertions.truthy(public_snapshot[&"farm_storage"].is_read_only(), "storage snapshot is read-only")
	assertions.truthy(public_snapshot[&"farm_storage"].items.is_read_only(), "storage items are read-only")
	_free_fixture(fixture)


func _test_multistage_failure_keeps_original_rollback_boundary(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var rollback_fixture := _make_fixture(tree)
	var rollback_token: RefCounted = rollback_fixture.router.begin_atomic_transaction()
	assertions.truthy(
		rollback_fixture.router.stage_add_items(rollback_token, {"wood": 1, "grain": 1}),
		"first stage succeeds before injected failure"
	)
	rollback_fixture.storage.fail_next_add = true
	assertions.truthy(
		not rollback_fixture.router.stage_add_items(rollback_token, {"wood": 1, "grain": 1}),
		"second stage failure is reported"
	)
	assertions.truthy(rollback_fixture.router.rollback_atomic_transaction(rollback_token), "multistage rolls back")
	assertions.equal(rollback_fixture.router.get_count("wood"), 0, "multistage rollback reaches original inventory")
	assertions.equal(rollback_fixture.router.get_count("grain"), 0, "multistage rollback reaches original storage")
	_free_fixture(rollback_fixture)

	var cancel_fixture := _make_fixture(tree)
	var cancel_token: RefCounted = cancel_fixture.router.begin_atomic_transaction()
	cancel_fixture.router.stage_add_items(cancel_token, {"wood": 1, "grain": 1})
	cancel_fixture.storage.fail_next_add = true
	cancel_fixture.router.stage_add_items(cancel_token, {"wood": 1, "grain": 1})
	assertions.truthy(
		cancel_fixture.router.stage_add_items(cancel_token, {"wood": 1, "grain": 1}),
		"transaction remains usable after restored failed stage"
	)
	var publication: RefCounted = cancel_fixture.router.seal_atomic_transaction(cancel_token)
	assertions.truthy(cancel_fixture.router.cancel_sealed_transaction(publication), "multistage seal cancels")
	assertions.equal(cancel_fixture.router.get_count("wood"), 0, "multistage cancel reaches original inventory")
	assertions.equal(cancel_fixture.router.get_count("grain"), 0, "multistage cancel reaches original storage")
	_free_fixture(cancel_fixture)


func _test_failed_stage_does_not_leak_inventory_event_delta(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var fixture := _make_fixture(tree)
	var recorder := _connect_recorder(fixture, tree)
	var token: RefCounted = fixture.router.begin_atomic_transaction()
	assertions.truthy(
		fixture.router.stage_add_items(token, {"wood": 1, "grain": 1}),
		"event delta fixture stages first batch"
	)
	fixture.storage.fail_next_add = true
	assertions.truthy(
		not fixture.router.stage_add_items(token, {"wood": 2, "grain": 1}),
		"event delta fixture restores failed batch"
	)
	assertions.truthy(
		fixture.router.stage_add_items(token, {"wood": 1, "grain": 1}),
		"event delta fixture remains usable"
	)
	assertions.truthy(fixture.router.commit_atomic_transaction(token), "event delta fixture commits")
	var inventory_quantity := 0
	for record in recorder.records:
		if record.kind == "inventory_add" and record.item_id == "wood":
			inventory_quantity += int(record.quantity)
	assertions.equal(fixture.router.get_count("wood"), 2, "final inventory state has exact quantity")
	assertions.equal(inventory_quantity, 2, "published inventory delta excludes restored failed stage")
	_disconnect_recorder(fixture, tree, recorder)
	_free_fixture(fixture)


func _test_late_abandonment_recovers_without_router_call(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var token_fixture := _make_fixture(tree)
	var token_recorder := _connect_recorder(token_fixture, tree)
	assertions.truthy(not token_fixture.router.is_processing(), "idle router does not process")
	var token: RefCounted = token_fixture.router.begin_atomic_transaction()
	token_fixture.router.stage_add_items(token, {"wood": 1, "grain": 1})
	assertions.truthy(token_fixture.router.is_processing(), "active token enables recovery monitor")
	await tree.process_frame
	await tree.process_frame
	assertions.equal(token_fixture.inventory.get_item_count("wood"), 1, "held token survives two frames")
	token = null
	await tree.process_frame
	await tree.process_frame
	assertions.equal(token_fixture.inventory.get_item_count("wood"), 0, "late token abandonment restores inventory")
	assertions.equal(token_fixture.storage.get_count("grain"), 0, "late token abandonment restores storage")
	assertions.truthy(not token_fixture.router.is_processing(), "token recovery disables monitor")
	_assert_recorder_silent(assertions, token_recorder, "late token abandonment")
	_assert_container_transactions_available(assertions, token_fixture, "late token abandonment")
	_disconnect_recorder(token_fixture, tree, token_recorder)
	_free_fixture(token_fixture)

	var cancel_fixture := _make_fixture(tree)
	var cancel_recorder := _connect_recorder(cancel_fixture, tree)
	var cancel_token: RefCounted = cancel_fixture.router.begin_atomic_transaction()
	cancel_fixture.router.stage_add_items(cancel_token, {"wood": 1, "grain": 1})
	var abandoned_publication: RefCounted = cancel_fixture.router.seal_atomic_transaction(cancel_token)
	await tree.process_frame
	await tree.process_frame
	abandoned_publication = null
	await tree.process_frame
	await tree.process_frame
	assertions.equal(cancel_fixture.inventory.get_item_count("wood"), 0, "late publication abandonment restores inventory")
	assertions.equal(cancel_fixture.storage.get_count("grain"), 0, "late publication abandonment restores storage")
	assertions.truthy(not cancel_fixture.router.is_processing(), "cancelled seal disables monitor")
	_assert_recorder_silent(assertions, cancel_recorder, "late publication abandonment")
	_assert_container_transactions_available(assertions, cancel_fixture, "late publication abandonment")
	_disconnect_recorder(cancel_fixture, tree, cancel_recorder)
	_free_fixture(cancel_fixture)

	var publish_fixture := _make_fixture(tree)
	var publish_recorder := _connect_recorder(publish_fixture, tree)
	var publish_token: RefCounted = publish_fixture.router.begin_atomic_transaction()
	publish_fixture.router.stage_add_items(publish_token, {"wood": 1, "grain": 1})
	var armed_publication: RefCounted = publish_fixture.router.seal_atomic_transaction(publish_token)
	assertions.truthy(publish_fixture.router.arm_sealed_transaction(armed_publication), "abandon publish fixture arms")
	await tree.process_frame
	await tree.process_frame
	armed_publication = null
	await tree.process_frame
	await tree.process_frame
	assertions.equal(publish_fixture.inventory.get_item_count("wood"), 1, "armed abandonment publishes inventory")
	assertions.equal(publish_fixture.storage.get_count("grain"), 1, "armed abandonment publishes storage")
	assertions.equal(publish_recorder.records.size(), 2, "armed abandonment publishes EventBus once")
	assertions.equal(publish_recorder.local_storage_records.size(), 1, "armed abandonment publishes storage once")
	assertions.truthy(not publish_fixture.router.is_processing(), "published seal disables monitor")
	_assert_container_transactions_available(assertions, publish_fixture, "armed publication abandonment")
	_disconnect_recorder(publish_fixture, tree, publish_recorder)
	_free_fixture(publish_fixture)


func _test_publish_reentrancy_is_rejected(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var token: RefCounted = fixture.router.begin_atomic_transaction()
	fixture.router.stage_add_items(token, {"wood": 1, "grain": 1})
	var publication: RefCounted = fixture.router.seal_atomic_transaction(token)
	var recorder := _connect_recorder(fixture, tree)
	var reentered := [false]
	var reentrant_results: Array[bool] = []
	var callback := func(_item_id: String, _quantity: int) -> void:
		if reentered[0]:
			return
		reentered[0] = true
		reentrant_results.append(fixture.router.publish_sealed_transaction(publication))
	tree.root.get_node("EventBus").item_added.connect(callback)
	assertions.truthy(fixture.router.publish_sealed_transaction(publication), "outer publication succeeds")
	assertions.equal(reentrant_results, [false], "publish callback cannot reenter publication")
	assertions.equal(recorder.records.size(), 2, "reentrant publish emits EventBus changes once")
	assertions.equal(recorder.local_storage_records.size(), 1, "reentrant publish emits storage once")
	assertions.equal(fixture.inventory.get_item_count("wood"), 1, "reentrant publish keeps final inventory")
	assertions.equal(fixture.storage.get_count("grain"), 1, "reentrant publish keeps final storage")
	tree.root.get_node("EventBus").item_added.disconnect(callback)
	_disconnect_recorder(fixture, tree, recorder)
	_free_fixture(fixture)


func _test_reparent_restores_abandonment_monitor(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var fixture := _make_fixture(tree)
	var router: Node = fixture.router
	var first_token: RefCounted = router.begin_atomic_transaction()
	router.stage_add_items(first_token, {"wood": 1, "grain": 1})
	tree.root.remove_child(router)
	assertions.equal(fixture.inventory.get_item_count("wood"), 0, "reparent exit restores inventory")
	assertions.equal(fixture.storage.get_count("grain"), 0, "reparent exit restores storage")
	tree.root.add_child(router)
	var second_token: RefCounted = router.begin_atomic_transaction()
	assertions.truthy(second_token != null, "reparented router begins a new transaction")
	assertions.truthy(
		router.stage_add_items(second_token, {"wood": 1, "grain": 1}),
		"reparented router stages a mixed transaction"
	)
	await tree.process_frame
	await tree.process_frame
	second_token = null
	await tree.process_frame
	await tree.process_frame
	assertions.equal(fixture.inventory.get_item_count("wood"), 0, "reparent monitor restores inventory")
	assertions.equal(fixture.storage.get_count("grain"), 0, "reparent monitor restores storage")
	assertions.truthy(not router.is_processing(), "reparent recovery disables the monitor")
	_assert_container_transactions_available(assertions, fixture, "reparent abandonment")
	_free_fixture(fixture)


func _test_publish_callbacks_can_release_dependencies(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var event_bus := tree.root.get_node("EventBus")
	var router_fixture := _make_fixture(tree)
	var router: Node = router_fixture.router
	var router_token: RefCounted = router.begin_atomic_transaction()
	router.stage_add_items(router_token, {"wood": 1, "grain": 1})
	var router_publication: RefCounted = router.seal_atomic_transaction(router_token)
	var router_event_count := [0]
	var router_storage_count := [0]
	var free_router := func(_item_id: String, _quantity: int) -> void:
		router_event_count[0] += 1
		if is_instance_valid(router):
			router.queue_free()
	var count_router_storage := func(_changes: Dictionary) -> void:
		router_storage_count[0] += 1
	event_bus.item_added.connect(free_router)
	router_fixture.storage.contents_changed.connect(count_router_storage)
	var router_publish_result: bool = router.publish_sealed_transaction(router_publication)
	event_bus.item_added.disconnect(free_router)
	if is_instance_valid(router_fixture.storage):
		router_fixture.storage.contents_changed.disconnect(count_router_storage)
	await tree.process_frame
	await tree.process_frame
	assertions.truthy(router_publish_result, "EventBus callback can free router during publication")
	assertions.equal(router_event_count[0], 1, "router release callback runs once")
	assertions.equal(router_storage_count[0], 1, "router release still publishes storage once")
	assertions.truthy(not is_instance_valid(router), "EventBus callback releases router")
	assertions.equal(router_fixture.inventory.get_item_count("wood"), 1, "router release keeps inventory result")
	assertions.equal(router_fixture.storage.get_count("grain"), 1, "router release keeps storage result")
	_assert_container_transactions_available(assertions, router_fixture, "router callback release")
	_free_fixture(router_fixture)

	var inventory_fixture := _make_fixture(tree)
	inventory_fixture.router.add_items({"wood": 1})
	var wood_slot := _item_slot(inventory_fixture.inventory, "wood")
	inventory_fixture.inventory.set_quick_slot(wood_slot, 0)
	var inventory_token: RefCounted = inventory_fixture.router.begin_atomic_transaction()
	inventory_fixture.router.stage_remove_items(inventory_token, {"wood": 1})
	var inventory_publication: RefCounted = inventory_fixture.router.seal_atomic_transaction(inventory_token)
	var inventory_quick_count := [0]
	var inventory_removed_count := [0]
	var free_storage := func(_quick_index: int, _item_id: String) -> void:
		inventory_quick_count[0] += 1
		if is_instance_valid(inventory_fixture.storage):
			inventory_fixture.storage.free()
	var count_inventory_remove := func(_item_id: String, _quantity: int) -> void:
		inventory_removed_count[0] += 1
	inventory_fixture.inventory.quick_slot_mapping_changed.connect(free_storage)
	event_bus.item_removed.connect(count_inventory_remove)
	assertions.truthy(
		inventory_fixture.router.publish_sealed_transaction(inventory_publication),
		"quick-slot callback can free storage after publication"
	)
	event_bus.item_removed.disconnect(count_inventory_remove)
	assertions.equal(inventory_quick_count[0], 1, "quick callback runs once")
	assertions.equal(inventory_removed_count[0], 1, "inventory release emits EventBus removal once")
	assertions.truthy(not is_instance_valid(inventory_fixture.storage), "quick callback releases storage")
	_assert_container_transactions_available(assertions, inventory_fixture, "storage callback release")
	_free_fixture(inventory_fixture)

	var storage_fixture := _make_fixture(tree)
	var storage_token: RefCounted = storage_fixture.router.begin_atomic_transaction()
	storage_fixture.router.stage_add_items(storage_token, {"wood": 1, "grain": 1})
	var storage_publication: RefCounted = storage_fixture.router.seal_atomic_transaction(storage_token)
	var storage_contents_count := [0]
	var storage_event_count := [0]
	var free_inventory := func(_changes: Dictionary) -> void:
		storage_contents_count[0] += 1
		if is_instance_valid(storage_fixture.inventory):
			storage_fixture.inventory.free()
	var count_storage_inventory_event := func(_item_id: String, _quantity: int) -> void:
		storage_event_count[0] += 1
	storage_fixture.storage.contents_changed.connect(free_inventory)
	event_bus.item_added.connect(count_storage_inventory_event)
	assertions.truthy(
		storage_fixture.router.publish_sealed_transaction(storage_publication),
		"storage callback can free inventory during publication"
	)
	event_bus.item_added.disconnect(count_storage_inventory_event)
	assertions.equal(storage_contents_count[0], 1, "inventory release callback runs once")
	assertions.equal(storage_event_count[0], 1, "storage callback still emits prepared inventory event once")
	assertions.truthy(not is_instance_valid(storage_fixture.inventory), "storage callback releases inventory")
	assertions.equal(storage_fixture.storage.get_count("grain"), 1, "inventory release keeps storage result")
	_assert_container_transactions_available(assertions, storage_fixture, "inventory callback release")
	_free_fixture(storage_fixture)


func _test_exit_tree_and_invalid_dependency_release_locks(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var exit_fixture := _make_fixture(tree)
	var exit_recorder := _connect_recorder(exit_fixture, tree)
	var exit_token: RefCounted = exit_fixture.router.begin_atomic_transaction()
	exit_fixture.router.stage_add_items(exit_token, {"wood": 1, "grain": 1})
	exit_fixture.router.queue_free()
	await tree.process_frame
	await tree.process_frame
	assertions.equal(exit_fixture.inventory.get_item_count("wood"), 0, "router exit restores inventory")
	assertions.equal(exit_fixture.storage.get_count("grain"), 0, "router exit restores storage")
	_assert_recorder_silent(assertions, exit_recorder, "router exit")
	_assert_container_transactions_available(assertions, exit_fixture, "router exit")
	_disconnect_recorder(exit_fixture, tree, exit_recorder)
	_free_fixture(exit_fixture)

	var sealed_fixture := _make_fixture(tree)
	var sealed_recorder := _connect_recorder(sealed_fixture, tree)
	var sealed_token: RefCounted = sealed_fixture.router.begin_atomic_transaction()
	sealed_fixture.router.stage_add_items(sealed_token, {"wood": 1, "grain": 1})
	var sealed_publication: RefCounted = sealed_fixture.router.seal_atomic_transaction(sealed_token)
	assertions.truthy(sealed_publication != null, "router exit fixture seals transaction")
	sealed_fixture.router.queue_free()
	await tree.process_frame
	await tree.process_frame
	assertions.equal(sealed_fixture.inventory.get_item_count("wood"), 0, "router exit cancels sealed inventory")
	assertions.equal(sealed_fixture.storage.get_count("grain"), 0, "router exit cancels sealed storage")
	_assert_recorder_silent(assertions, sealed_recorder, "sealed router exit")
	_assert_container_transactions_available(assertions, sealed_fixture, "sealed router exit")
	_disconnect_recorder(sealed_fixture, tree, sealed_recorder)
	_free_fixture(sealed_fixture)

	var invalid_fixture := _make_fixture(tree)
	var invalid_token: RefCounted = invalid_fixture.router.begin_atomic_transaction()
	invalid_fixture.router.stage_add_items(invalid_token, {"wood": 1, "grain": 1})
	invalid_fixture.inventory.get_parent().remove_child(invalid_fixture.inventory)
	invalid_fixture.inventory.free()
	assertions.truthy(
		invalid_fixture.router.rollback_atomic_transaction(invalid_token),
		"rollback tolerates released inventory"
	)
	assertions.equal(invalid_fixture.storage.get_count("grain"), 0, "released dependency still unlocks storage")
	var storage_token: RefCounted = invalid_fixture.storage.begin_atomic_transaction()
	assertions.truthy(storage_token != null, "storage remains transaction-capable after dependency loss")
	if storage_token != null:
		invalid_fixture.storage.rollback_atomic_transaction(storage_token)
	_free_fixture(invalid_fixture)


func _test_blocked_event_bus_keeps_publication_retryable(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var fixture := _make_fixture(tree)
	var token: RefCounted = fixture.router.begin_atomic_transaction()
	fixture.router.stage_add_items(token, {"wood": 1, "grain": 1})
	var publication: RefCounted = fixture.router.seal_atomic_transaction(token)
	assertions.truthy(fixture.router.arm_sealed_transaction(publication), "blocked bus fixture arms publication")
	var recorder := _connect_recorder(fixture, tree)
	var event_bus := tree.root.get_node("EventBus")
	event_bus.set_block_signals(true)
	var blocked_result: bool = fixture.router.publish_sealed_transaction(publication)
	event_bus.set_block_signals(false)
	assertions.truthy(not blocked_result, "blocked EventBus rejects publication")
	assertions.truthy(fixture.router.owns_sealed_transaction(publication), "blocked publication remains owned")
	assertions.truthy(not fixture.router.cancel_sealed_transaction(publication), "armed retryable publication cannot cancel")
	_assert_recorder_silent(assertions, recorder, "blocked publication")
	assertions.truthy(fixture.router.publish_sealed_transaction(publication), "publication retries after unblock")
	assertions.equal(recorder.records.size(), 2, "retried publication emits EventBus once")
	assertions.equal(recorder.local_storage_records.size(), 1, "retried publication emits storage once")
	_disconnect_recorder(fixture, tree, recorder)
	_free_fixture(fixture)


func _test_persistent_storage_restore_failure_is_non_mutating(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var fixture := _make_fixture(tree)
	fixture.router.add_items({"wood": 2, "grain": 2})
	var target: Dictionary = fixture.router.snapshot_for({"wood": 1, "grain": 1})
	fixture.router.add_items({"wood": 1, "grain": 1})
	var before_slots: Array = fixture.inventory.slots.duplicate(true)
	var before_mappings: Array = fixture.inventory.quick_slot_mappings.duplicate()
	var before_storage: Dictionary = fixture.storage.get_items().duplicate(true)
	var inventory_restore_calls: int = fixture.inventory.restore_calls
	var storage_restore_calls: int = fixture.storage.restore_calls
	var recorder := _connect_recorder(fixture, tree)
	fixture.storage.fail_all_restores = true
	assertions.truthy(not fixture.router.restore_snapshot(target), "persistent storage restore failure is reported")
	assertions.equal(fixture.inventory.restore_calls, inventory_restore_calls, "storage failure never touches inventory")
	assertions.equal(fixture.storage.restore_calls, storage_restore_calls + 1, "storage restore is attempted once")
	assertions.equal(fixture.inventory.slots, before_slots, "persistent restore keeps inventory slots")
	assertions.equal(fixture.inventory.quick_slot_mappings, before_mappings, "persistent restore keeps mappings")
	assertions.equal(fixture.storage.get_items(), before_storage, "persistent restore keeps storage")
	_assert_recorder_silent(assertions, recorder, "persistent restore failure")
	fixture.storage.fail_all_restores = false
	_disconnect_recorder(fixture, tree, recorder)
	_free_fixture(fixture)


func _test_transaction_ownership_and_abandonment(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _make_fixture(tree)
	var wrong_token := RefCounted.new()
	var token: RefCounted = fixture.router.begin_atomic_transaction()
	assertions.truthy(token != null, "ownership fixture begins transaction")
	var has_transaction_ownership: bool = fixture.router.has_method("owns_atomic_transaction")
	assertions.truthy(has_transaction_ownership, "router exposes transaction ownership")
	if has_transaction_ownership:
		assertions.truthy(
			bool(fixture.router.call("owns_atomic_transaction", token)),
			"router recognizes active owner"
		)
		assertions.truthy(
			not bool(fixture.router.call("owns_atomic_transaction", wrong_token)),
			"router rejects foreign owner"
		)
	assertions.equal(fixture.router.begin_atomic_transaction(), null, "nested transaction is rejected")
	assertions.truthy(
		not fixture.router.configure(fixture.inventory, fixture.storage),
		"configure is rejected during transaction"
	)
	assertions.truthy(not fixture.router.stage_add_items(wrong_token, {"wood": 1}), "foreign stage is rejected")
	assertions.truthy(not fixture.router.rollback_atomic_transaction(wrong_token), "foreign rollback is rejected")
	assertions.truthy(fixture.router.stage_add_items(token, {"wood": 1, "grain": 1}), "owned stage succeeds")
	token = null
	await tree.process_frame
	await tree.process_frame
	assertions.equal(fixture.router.get_count("wood"), 0, "abandoned token restores inventory")
	assertions.equal(fixture.router.get_count("grain"), 0, "abandoned token restores storage")

	var cancel_token: RefCounted = fixture.router.begin_atomic_transaction()
	fixture.router.stage_add_items(cancel_token, {"wood": 1, "grain": 1})
	var abandoned_publication: RefCounted = fixture.router.seal_atomic_transaction(cancel_token)
	if has_transaction_ownership:
		assertions.truthy(
			not bool(fixture.router.call("owns_atomic_transaction", cancel_token)),
			"sealed router no longer owns the consumed transaction token"
		)
	abandoned_publication = null
	await tree.process_frame
	await tree.process_frame
	assertions.equal(fixture.router.get_count("wood"), 0, "abandoned publication cancels inventory")
	assertions.equal(fixture.router.get_count("grain"), 0, "abandoned publication cancels storage")

	var commit_token: RefCounted = fixture.router.begin_atomic_transaction()
	assertions.truthy(fixture.router.stage_add_items(commit_token, {"wood": 1}), "commit fixture stages")
	assertions.truthy(fixture.router.commit_atomic_transaction(commit_token), "owned transaction commits")
	assertions.truthy(not fixture.router.commit_atomic_transaction(commit_token), "transaction cannot commit twice")
	var rollback_token: RefCounted = fixture.router.begin_atomic_transaction()
	assertions.truthy(fixture.router.stage_remove_items(rollback_token, {"wood": 1}), "rollback fixture stages")
	assertions.truthy(fixture.router.rollback_atomic_transaction(rollback_token), "owned transaction rolls back")
	assertions.truthy(not fixture.router.rollback_atomic_transaction(rollback_token), "transaction cannot roll back twice")
	assertions.equal(fixture.router.get_count("wood"), 1, "rollback preserves committed state")
	_free_fixture(fixture)


func _test_unconfigured_and_invalid_containers(assertions: TestAssert, tree: SceneTree) -> void:
	var router := RouterScript.new()
	tree.root.add_child(router)
	assertions.equal(router.can_add({"wood": 1}).get("reason"), "not_configured", "unconfigured preflight is stable")
	assertions.equal(router.begin_atomic_transaction(), null, "unconfigured transaction is rejected")
	var inventory := FailingInventory.new()
	var storage := FailingStorage.new()
	tree.root.add_child(inventory)
	tree.root.add_child(storage)
	assertions.truthy(router.configure(inventory, storage), "valid containers configure")
	tree.root.remove_child(inventory)
	inventory.free()
	assertions.equal(router.can_add({"wood": 1}).get("reason"), "not_configured", "freed container invalidates router")
	assertions.equal(router.begin_atomic_transaction(), null, "freed container rejects transaction")
	tree.root.remove_child(storage)
	storage.free()
	tree.root.remove_child(router)
	router.free()


func _connect_recorder(fixture: Dictionary, tree: SceneTree) -> EventRecorder:
	var recorder := EventRecorder.new(fixture.router)
	var event_bus := tree.root.get_node("EventBus")
	event_bus.item_added.connect(recorder.on_item_added)
	event_bus.item_removed.connect(recorder.on_item_removed)
	event_bus.farm_storage_changed.connect(recorder.on_storage_changed)
	fixture.inventory.quick_slot_mapping_changed.connect(recorder.on_quick_changed)
	fixture.storage.contents_changed.connect(recorder.on_local_storage_changed)
	return recorder


func _disconnect_recorder(fixture: Dictionary, tree: SceneTree, recorder: EventRecorder) -> void:
	var event_bus := tree.root.get_node("EventBus")
	event_bus.item_added.disconnect(recorder.on_item_added)
	event_bus.item_removed.disconnect(recorder.on_item_removed)
	event_bus.farm_storage_changed.disconnect(recorder.on_storage_changed)
	fixture.inventory.quick_slot_mapping_changed.disconnect(recorder.on_quick_changed)
	fixture.storage.contents_changed.disconnect(recorder.on_local_storage_changed)


func _assert_recorder_silent(assertions: TestAssert, recorder: EventRecorder, context: String) -> void:
	assertions.equal(recorder.records.size(), 0, "%s emits no EventBus events" % context)
	assertions.equal(recorder.quick_records.size(), 0, "%s emits no quick mapping events" % context)
	assertions.equal(recorder.local_storage_records.size(), 0, "%s emits no storage events" % context)


func _assert_container_transactions_available(
	assertions: TestAssert,
	fixture: Dictionary,
	context: String
) -> void:
	if is_instance_valid(fixture.inventory):
		var inventory_available: bool = fixture.inventory.begin_restore_notification_transaction()
		assertions.truthy(inventory_available, "%s releases inventory transaction" % context)
		if inventory_available:
			fixture.inventory.end_restore_notification_transaction(false)
	if is_instance_valid(fixture.storage):
		var storage_token: RefCounted = fixture.storage.begin_atomic_transaction()
		assertions.truthy(storage_token != null, "%s releases storage transaction" % context)
		if storage_token != null:
			fixture.storage.rollback_atomic_transaction(storage_token)


func _item_slot(inventory: Node, item_id: String) -> int:
	for index in range(inventory.slots.size()):
		if inventory.slots[index].get("item_id", "") == item_id:
			return index
	return -1


func _make_fixture(tree: SceneTree, capacity: int = 200) -> Dictionary:
	var inventory := FailingInventory.new()
	var storage := FailingStorage.new()
	var router := RouterScript.new()
	inventory.name = "RouterTestInventory"
	storage.name = "RouterTestStorage"
	storage.configure(func() -> int: return capacity)
	tree.root.add_child(inventory)
	tree.root.add_child(storage)
	tree.root.add_child(router)
	assert(router.configure(inventory, storage))
	return {"router": router, "inventory": inventory, "storage": storage}


func _free_fixture(fixture: Dictionary) -> void:
	for key in ["inventory", "storage", "router"]:
		var node: Variant = fixture.get(key)
		if not is_instance_valid(node):
			continue
		if (node as Node).get_parent() != null:
			(node as Node).get_parent().remove_child(node)
		(node as Node).free()
