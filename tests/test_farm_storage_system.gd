extends RefCounted

const FarmStorageSystemScript = preload("res://scripts/systems/farm_storage_system.gd")
const EconomyLimitsScript = preload("res://scripts/core/economy_limits.gd")


class MutableCapacity:
	extends RefCounted
	var value: Variant

	func _init(initial_value: Variant) -> void:
		value = initial_value

	func provide() -> Variant:
		return value


class DisposableCapacity:
	extends Object
	var value: Variant

	func _init(initial_value: Variant) -> void:
		value = initial_value

	func provide() -> Variant:
		return value


class SignalRecorder:
	extends RefCounted
	var storage: Node
	var contents: Array[Dictionary] = []
	var capacities: Array[Dictionary] = []
	var bus_contents: Array[Dictionary] = []
	var bus_capacities: Array[Dictionary] = []

	func _init(target: Node) -> void:
		storage = target

	func on_contents(changes: Dictionary) -> void:
		contents.append({
			"changes": changes.duplicate(true),
			"state": storage.call("get_items"),
			"read_only": changes.is_read_only(),
		})

	func on_capacity(used: int, total: int) -> void:
		capacities.append({"used": used, "total": total})

	func on_bus_contents(changes: Dictionary) -> void:
		bus_contents.append(changes.duplicate(true))

	func on_bus_capacity(used: int, total: int) -> void:
		bus_capacities.append({"used": used, "total": total})


class ReentrantContentsRecorder:
	extends RefCounted
	var storage: Node
	var nested_add_attempted := false
	var nested_add_results: Array[bool] = []
	var local_contents: Array[Dictionary] = []
	var bus_contents: Array[Dictionary] = []
	var local_capacities: Array[Dictionary] = []
	var bus_capacities: Array[Dictionary] = []
	var timeline: Array[String] = []

	func _init(target: Node) -> void:
		storage = target

	func on_contents(changes: Dictionary) -> void:
		local_contents.append(changes)
		timeline.append("local_contents:%s" % str(changes.keys()[0]))
		if not nested_add_attempted:
			nested_add_attempted = true
			nested_add_results.append(bool(storage.call("add_items", {"tomato": 1})))

	func on_bus_contents(changes: Dictionary) -> void:
		bus_contents.append(changes)
		timeline.append("bus_contents:%s" % str(changes.keys()[0]))

	func on_capacity(used: int, total: int) -> void:
		local_capacities.append({"used": used, "total": total})
		timeline.append("local_capacity:%d:%d" % [used, total])

	func on_bus_capacity(used: int, total: int) -> void:
		bus_capacities.append({"used": used, "total": total})
		timeline.append("bus_capacity:%d:%d" % [used, total])


class ReentrantCapacityRecorder:
	extends RefCounted
	var storage: Node
	var capacity: Variant
	var nested_refresh_attempted := false
	var local_capacities: Array[Dictionary] = []
	var bus_capacities: Array[Dictionary] = []
	var timeline: Array[String] = []

	func _init(target: Node, provider: Variant) -> void:
		storage = target
		capacity = provider

	func on_capacity(used: int, total: int) -> void:
		local_capacities.append({"used": used, "total": total})
		timeline.append("local:%d" % total)
		if not nested_refresh_attempted:
			nested_refresh_attempted = true
			capacity.value = 7
			storage.call("refresh_capacity")

	func on_bus_capacity(used: int, total: int) -> void:
		bus_capacities.append({"used": used, "total": total})
		timeline.append("bus:%d" % total)


class ReadOnlyPayloadRecorder:
	extends RefCounted
	var read_only_results: Array[bool] = []
	var payloads: Array[Dictionary] = []

	func on_first(changes: Dictionary) -> void:
		_record(changes)

	func on_second(changes: Dictionary) -> void:
		_record(changes)

	func on_bus(changes: Dictionary) -> void:
		_record(changes)

	func _record(changes: Dictionary) -> void:
		read_only_results.append(changes.is_read_only())
		payloads.append(changes)


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_empty_state_and_capacity_provider(assertions)
	_test_refresh_emits_only_when_capacity_changes(assertions, tree)
	_test_atomic_add_remove_and_capacity(assertions)
	_test_capacity_overload_behavior(assertions)
	_test_serialization_and_overloaded_restore(assertions)
	_test_strict_request_validation(assertions)
	_test_failed_restore_validation_is_atomic(assertions)
	_test_committed_signal_payloads(assertions, tree)
	_test_atomic_notification_transaction(assertions, tree)
	_test_sealed_transaction_defers_fifo_notifications(assertions, tree)
	_test_abandoned_active_and_armed_transactions(assertions, tree)
	_test_contents_reentrancy_preserves_notification_order(assertions, tree)
	_test_capacity_reentrancy_preserves_notification_order(assertions, tree)
	_test_change_payload_is_read_only_for_all_listeners(assertions, tree)
	_test_rejected_operations_and_freed_provider_are_silent(assertions, tree)


func _test_refresh_emits_only_when_capacity_changes(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var capacity := MutableCapacity.new(200)
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	assertions.truthy(storage.configure(capacity.provide), "derived capacity fixture configures")
	var recorder := SignalRecorder.new(storage)
	storage.capacity_changed.connect(recorder.on_capacity)
	storage.refresh_capacity()
	assertions.equal(recorder.capacities, [], "unchanged derived capacity emits no refresh event")
	capacity.value = 400
	storage.refresh_capacity()
	assertions.equal(
		recorder.capacities,
		[{"used": 0, "total": 400}],
		"changed derived capacity emits one refresh event"
	)
	storage.refresh_capacity()
	assertions.equal(recorder.capacities.size(), 1, "repeated unchanged refresh stays silent")
	storage.capacity_changed.disconnect(recorder.on_capacity)
	storage.free()


func _test_atomic_notification_transaction(assertions: TestAssert, tree: SceneTree) -> void:
	var capacity := MutableCapacity.new(6)
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	storage.configure(capacity.provide)
	assertions.truthy(storage.add_items({"grain": 1}), "transaction fixture starts with grain")
	var recorder := SignalRecorder.new(storage)
	var event_bus = tree.root.get_node("EventBus")
	storage.contents_changed.connect(recorder.on_contents)
	storage.capacity_changed.connect(recorder.on_capacity)
	event_bus.farm_storage_changed.connect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.connect(recorder.on_bus_capacity)

	assertions.truthy(storage.has_method("begin_atomic_transaction"), "storage exposes atomic transaction begin")
	assertions.truthy(storage.has_method("commit_atomic_transaction"), "storage exposes atomic transaction commit")
	assertions.truthy(storage.has_method("rollback_atomic_transaction"), "storage exposes atomic transaction rollback")
	assertions.truthy(storage.has_method("stage_add_items"), "storage exposes owned staged additions")
	assertions.truthy(storage.has_method("stage_remove_items"), "storage exposes owned staged removals")
	assertions.truthy(storage.has_method("stage_refresh_capacity"), "storage exposes owned staged capacity refresh")
	if (
		not storage.has_method("begin_atomic_transaction")
		or not storage.has_method("stage_add_items")
		or not storage.has_method("stage_remove_items")
		or not storage.has_method("stage_refresh_capacity")
	):
		storage.queue_free()
		return

	var rollback_token: Variant = storage.call("begin_atomic_transaction")
	assertions.truthy(rollback_token != null, "storage begins one owned transaction")
	assertions.truthy(rollback_token is RefCounted, "transaction ownership uses an unforgeable object handle")
	assertions.equal(storage.call("begin_atomic_transaction"), null, "nested transaction ownership is rejected")
	if rollback_token is RefCounted:
		assertions.truthy(not storage.call("rollback_atomic_transaction", RefCounted.new()), "forged transaction ownership is rejected")
	assertions.truthy(not storage.add_items({"potato": 1}), "unowned add cannot join an active transaction")
	assertions.truthy(not storage.remove_items({"grain": 1}), "unowned remove cannot join an active transaction")
	assertions.truthy(storage.call("stage_add_items", rollback_token, {"tomato": 2}), "owned transaction stages crop writes")
	capacity.value = 4
	storage.refresh_capacity()
	assertions.equal(storage.get_total_capacity(), 6, "unowned capacity refresh cannot join an active transaction")
	assertions.truthy(storage.call("stage_refresh_capacity", rollback_token), "owned transaction stages capacity refresh")
	assertions.equal(storage.get_items(), {"grain": 1, "tomato": 2}, "staged contents are visible to coherent listeners")
	assertions.equal(storage.get_total_capacity(), 4, "staged capacity is visible")
	assertions.equal(recorder.contents, [], "staged write emits no local contents signal")
	assertions.equal(recorder.bus_contents, [], "staged write emits no EventBus contents signal")
	assertions.equal(recorder.capacities, [], "staged write emits no local capacity signal")
	assertions.equal(recorder.bus_capacities, [], "staged write emits no EventBus capacity signal")
	assertions.truthy(storage.call("rollback_atomic_transaction", rollback_token), "owned transaction rolls back")
	assertions.equal(storage.get_items(), {"grain": 1}, "rollback restores exact item snapshot")
	assertions.equal(storage.get_total_capacity(), 6, "rollback restores exact capacity snapshot")
	assertions.equal(recorder.contents, [], "rollback emits no local contents signal")
	assertions.equal(recorder.bus_contents, [], "rollback emits no EventBus contents signal")
	assertions.truthy(not storage.call("rollback_atomic_transaction", rollback_token), "stale rollback token is rejected")

	var commit_token: Variant = storage.call("begin_atomic_transaction")
	assertions.truthy(storage.call("stage_add_items", commit_token, {"tomato": 2}), "commit transaction stages first write")
	assertions.truthy(storage.call("stage_add_items", commit_token, {"grain": 1}), "commit transaction stages second write")
	assertions.truthy(storage.call("stage_remove_items", commit_token, {"tomato": 1}), "commit transaction stages a removal")
	assertions.equal(recorder.contents, [], "all commit writes remain silent until commit")
	assertions.truthy(storage.call("commit_atomic_transaction", commit_token), "owned transaction commits")
	assertions.equal(storage.get_items(), {"grain": 2, "tomato": 1}, "commit retains final staged contents")
	assertions.equal(recorder.contents.size(), 1, "commit emits one local net contents event")
	assertions.equal(recorder.bus_contents.size(), 1, "commit emits one EventBus net contents event")
	assertions.equal(recorder.contents[0].changes, {"grain": 1, "tomato": 1}, "commit publishes only net deltas")
	assertions.truthy(recorder.contents[0].read_only, "transaction payload is immutable")
	assertions.equal(recorder.capacities, [{"used": 3, "total": 6}], "commit publishes one final capacity event")
	assertions.equal(recorder.bus_capacities, [{"used": 3, "total": 6}], "EventBus sees one final capacity event")
	assertions.truthy(not storage.call("commit_atomic_transaction", commit_token), "stale commit token is rejected")

	storage.contents_changed.disconnect(recorder.on_contents)
	storage.capacity_changed.disconnect(recorder.on_capacity)
	event_bus.farm_storage_changed.disconnect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.disconnect(recorder.on_bus_capacity)
	storage.queue_free()


func _test_sealed_transaction_defers_fifo_notifications(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var capacity := MutableCapacity.new(6)
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	storage.configure(capacity.provide)
	assertions.truthy(storage.add_items({"grain": 1}), "sealed fixture starts with grain")
	var recorder := SignalRecorder.new(storage)
	var event_bus = tree.root.get_node("EventBus")
	storage.contents_changed.connect(recorder.on_contents)
	storage.capacity_changed.connect(recorder.on_capacity)
	event_bus.farm_storage_changed.connect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.connect(recorder.on_bus_capacity)

	for method_name in [
		"seal_atomic_transaction",
		"publish_sealed_transaction",
		"cancel_sealed_transaction",
		"owns_sealed_transaction",
	]:
		assertions.truthy(storage.has_method(method_name), "storage exposes %s" % method_name)
	if not storage.has_method("cancel_sealed_transaction"):
		storage.queue_free()
		return

	var token: Variant = storage.begin_atomic_transaction()
	assertions.truthy(storage.stage_add_items(token, {"tomato": 2}), "seal fixture stages base harvest")
	var publication: Variant = storage.call("seal_atomic_transaction", token)
	assertions.truthy(publication is RefCounted, "seal returns unforgeable publication ownership")
	assertions.truthy(storage.call("owns_sealed_transaction", publication), "storage recognizes sealed owner")
	assertions.equal(storage.get_items(), {"grain": 1, "tomato": 2}, "sealed state remains committed")
	assertions.equal(recorder.contents, [], "seal dispatches no local notification")
	assertions.equal(recorder.bus_contents, [], "seal dispatches no EventBus notification")
	assertions.equal(storage.begin_atomic_transaction(), null, "sealed storage rejects new transactions")
	assertions.truthy(not storage.add_items({"grain": 1}), "sealed storage rejects immediate additions")
	assertions.truthy(not storage.remove_items({"grain": 1}), "sealed storage rejects immediate removals")
	assertions.truthy(not storage.restore_items_unchecked({"potato": 1}), "sealed storage rejects restore writes")
	capacity.value = 8
	storage.refresh_capacity()
	assertions.equal(storage.get_total_capacity(), 6, "sealed storage rejects capacity refresh")
	assertions.equal(recorder.contents, [], "rejected sealed writes emit no contents notification")
	assertions.equal(recorder.capacities, [], "rejected sealed writes emit no capacity notification")
	assertions.truthy(
		storage.call("cancel_sealed_transaction", publication),
		"sealed owner can cancel before publication"
	)
	assertions.equal(storage.get_items(), {"grain": 1}, "sealed cancel restores exact contents")
	assertions.equal(storage.get_total_capacity(), 6, "sealed cancel restores exact capacity")
	assertions.equal(recorder.contents, [], "sealed cancel emits no notification")
	assertions.truthy(storage.add_items({"potato": 1}), "cancel clears the storage barrier")

	var publish_recorder := ReentrantContentsRecorder.new(storage)
	storage.contents_changed.connect(publish_recorder.on_contents)
	storage.capacity_changed.connect(publish_recorder.on_capacity)
	event_bus.farm_storage_changed.connect(publish_recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.connect(publish_recorder.on_bus_capacity)
	var publish_token: Variant = storage.begin_atomic_transaction()
	assertions.truthy(storage.stage_add_items(publish_token, {"tomato": 2}), "publish fixture stages harvest")
	var publish_owner: Variant = storage.call("seal_atomic_transaction", publish_token)
	storage.call("publish_sealed_transaction", publish_owner)
	assertions.equal(publish_recorder.nested_add_results, [true], "publish unlocks storage before callbacks")
	assertions.equal(
		publish_recorder.local_contents.map(func(changes: Dictionary) -> Dictionary: return changes.duplicate(true)),
		[{"tomato": 2}, {"tomato": 1}],
		"base sealed notification precedes reentrant write notification"
	)
	assertions.equal(storage.get_items(), {"grain": 1, "potato": 1, "tomato": 3}, "published and reentrant writes both remain")

	storage.contents_changed.disconnect(publish_recorder.on_contents)
	storage.capacity_changed.disconnect(publish_recorder.on_capacity)
	event_bus.farm_storage_changed.disconnect(publish_recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.disconnect(publish_recorder.on_bus_capacity)
	var abandoned_token: Variant = storage.begin_atomic_transaction()
	assertions.truthy(storage.stage_add_items(abandoned_token, {"grain": 1}), "abandoned fixture stages a write")
	var abandoned_owner: Variant = storage.call("seal_atomic_transaction", abandoned_token)
	assertions.truthy(abandoned_owner is RefCounted, "abandoned fixture seals")
	abandoned_owner = null
	assertions.truthy(storage.add_items({"grain": 1}), "next write recovers an abandoned seal")
	assertions.equal(storage.get_count("grain"), 2, "abandoned staged write rolls back before next write")
	assertions.equal(recorder.contents.back().changes, {"grain": 1}, "abandoned base notification never leaks")

	storage.contents_changed.disconnect(recorder.on_contents)
	storage.capacity_changed.disconnect(recorder.on_capacity)
	event_bus.farm_storage_changed.disconnect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.disconnect(recorder.on_bus_capacity)
	storage.queue_free()


func _test_abandoned_active_and_armed_transactions(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	var recorder := SignalRecorder.new(storage)
	storage.contents_changed.connect(recorder.on_contents)
	storage.capacity_changed.connect(recorder.on_capacity)

	var empty_owner: Variant = storage.begin_atomic_transaction()
	assertions.truthy(empty_owner is RefCounted, "abandoned empty transaction starts")
	empty_owner = null
	var recovered_empty: Variant = storage.begin_atomic_transaction()
	assertions.truthy(recovered_empty is RefCounted, "lost empty transaction releases ownership")
	assertions.truthy(storage.rollback_atomic_transaction(recovered_empty), "recovered empty transaction can roll back")

	var staged_owner: Variant = storage.begin_atomic_transaction()
	assertions.truthy(storage.stage_add_items(staged_owner, {"grain": 2}), "abandoned active transaction stages")
	staged_owner = null
	var recovered_staged: Variant = storage.begin_atomic_transaction()
	assertions.truthy(recovered_staged is RefCounted, "lost staged transaction releases ownership")
	assertions.equal(storage.get_items(), {}, "lost staged transaction restores exact contents")
	assertions.equal(recorder.contents, [], "lost staged transaction remains silent")
	assertions.truthy(storage.rollback_atomic_transaction(recovered_staged), "transaction after staged recovery succeeds")

	for method_name in [
		"can_arm_sealed_transaction",
		"arm_sealed_transaction",
	]:
		assertions.truthy(storage.has_method(method_name), "storage exposes %s" % method_name)
	if not storage.has_method("arm_sealed_transaction"):
		storage.queue_free()
		return

	var commit_owner: Variant = storage.begin_atomic_transaction()
	assertions.truthy(storage.stage_add_items(commit_owner, {"grain": 1}), "armed fixture stages")
	var publication: Variant = storage.seal_atomic_transaction(commit_owner)
	assertions.truthy(storage.call("can_arm_sealed_transaction", publication), "sealed publication prevalidates")
	storage.call("arm_sealed_transaction", publication)
	assertions.truthy(
		not storage.cancel_sealed_transaction(publication),
		"cancellation is illegal after the commit point"
	)
	publication = null
	assertions.truthy(storage.add_items({"tomato": 1}), "lost armed publication auto-commits and unlocks")
	assertions.equal(storage.get_items(), {"grain": 1, "tomato": 1}, "armed abandonment keeps staged state")
	assertions.equal(
		recorder.contents.map(func(entry: Dictionary) -> Dictionary: return entry.changes),
		[{"grain": 1}, {"tomato": 1}],
		"armed base notification precedes the next write"
	)

	storage.contents_changed.disconnect(recorder.on_contents)
	storage.capacity_changed.disconnect(recorder.on_capacity)
	storage.queue_free()


func _test_empty_state_and_capacity_provider(assertions: TestAssert) -> void:
	var storage = FarmStorageSystemScript.new()
	assertions.equal(storage.get_items(), {}, "farm storage starts empty")
	assertions.truthy(storage.get_items().is_read_only(), "farm storage returns a read-only item snapshot")
	assertions.equal(storage.get_count("grain"), 0, "empty farm storage has zero item count")
	assertions.equal(storage.get_used_capacity(), 0, "empty farm storage uses no capacity")
	assertions.equal(storage.get_total_capacity(), 200, "farm storage defaults to 200 capacity")
	assertions.equal(storage.get_missing_capacity({"grain": 1}), 0, "empty default storage has no missing capacity")
	assertions.equal(storage.get_missing_capacity({"wood": 1}), -1, "invalid add request has stable missing capacity")

	var capacity := MutableCapacity.new(7)
	assertions.truthy(storage.configure(capacity.provide), "farm storage accepts a valid capacity provider")
	assertions.equal(storage.get_total_capacity(), 7, "farm storage uses configured capacity")
	capacity.value = 3
	storage.refresh_capacity()
	assertions.equal(storage.get_total_capacity(), 3, "farm storage refreshes changed provider capacity")
	capacity.value = 0
	storage.refresh_capacity()
	assertions.equal(storage.get_total_capacity(), 0, "zero is a valid provider capacity")
	capacity.value = 3
	storage.refresh_capacity()

	for invalid_value in [true, 3.0, -1, EconomyLimitsScript.MAX_SAFE_INTEGER + 1]:
		capacity.value = invalid_value
		storage.refresh_capacity()
		assertions.equal(
			storage.get_total_capacity(),
			3,
			"invalid provider result %s preserves last valid capacity" % invalid_value
		)
	capacity.value = 4
	storage.refresh_capacity()
	var invalid_provider := MutableCapacity.new(1.5)
	assertions.truthy(
		not storage.configure(invalid_provider.provide),
		"configure rejects an invalid provider result"
	)
	capacity.value = 5
	storage.refresh_capacity()
	assertions.equal(storage.get_total_capacity(), 5, "failed configure preserves the previous provider")
	assertions.truthy(storage.configure(), "empty provider restores default capacity")
	assertions.equal(storage.get_total_capacity(), 200, "empty provider restores the default total")

	var serialized: Dictionary = storage.to_dict()
	serialized.items["grain"] = 99
	assertions.equal(storage.get_count("grain"), 0, "serialized item dictionary does not alias storage state")
	storage.free()


func _test_atomic_add_remove_and_capacity(assertions: TestAssert) -> void:
	var capacity := MutableCapacity.new(5)
	var storage = FarmStorageSystemScript.new()
	storage.configure(capacity.provide)
	assertions.truthy(storage.can_add({"grain": 2, "tomato": 2}), "valid crop batch fits storage")
	assertions.truthy(storage.add_items({"grain": 2, "tomato": 2}), "valid crop batch adds atomically")
	assertions.equal(storage.get_items(), {"grain": 2, "tomato": 2}, "batch add commits every crop")
	assertions.equal(storage.get_count("grain"), 2, "get_count returns stored quantity")
	assertions.equal(storage.get_used_capacity(), 4, "every stored crop uses one capacity")
	assertions.equal(storage.get_missing_capacity({"potato": 1}), 0, "exact remaining capacity fits")
	assertions.equal(storage.get_missing_capacity({"potato": 3}), 2, "missing capacity is exact")

	var before_full_rejection: Dictionary = storage.get_items()
	assertions.truthy(not storage.can_add({"potato": 2}), "batch exceeding capacity cannot add")
	assertions.truthy(not storage.add_items({"potato": 2}), "batch exceeding capacity is rejected")
	assertions.equal(storage.get_items(), before_full_rejection, "capacity failure leaves all items unchanged")

	assertions.truthy(storage.can_remove({"grain": 1, "tomato": 2}), "available crop batch can remove")
	assertions.truthy(storage.remove_items({"grain": 1, "tomato": 2}), "available crop batch removes atomically")
	assertions.equal(storage.get_items(), {"grain": 1}, "remove erases depleted crop entries")
	var before_insufficient: Dictionary = storage.get_items()
	assertions.truthy(not storage.remove_items({"grain": 1, "tomato": 1}), "insufficient multi-remove is rejected")
	assertions.equal(storage.get_items(), before_insufficient, "insufficient multi-remove has no partial mutation")
	storage.free()


func _test_capacity_overload_behavior(assertions: TestAssert) -> void:
	var capacity := MutableCapacity.new(5)
	var storage = FarmStorageSystemScript.new()
	storage.configure(capacity.provide)
	assertions.truthy(storage.add_items({"grain": 3, "tomato": 2}), "overload fixture fills initial capacity")
	capacity.value = 2
	storage.refresh_capacity()
	assertions.equal(storage.get_used_capacity(), 5, "capacity lowering never deletes contents")
	assertions.equal(storage.get_total_capacity(), 2, "lower provider capacity is authoritative")
	assertions.equal(storage.get_missing_capacity({"potato": 1}), 4, "overloaded missing capacity includes overload")
	assertions.truthy(not storage.can_add({"potato": 1}), "overloaded storage blocks additions")
	assertions.truthy(storage.remove_items({"grain": 1}), "remove remains allowed while overloaded")
	assertions.equal(storage.get_used_capacity(), 4, "overloaded remove commits normally")
	assertions.truthy(storage.remove_items({"grain": 2}), "remove can bring overload closer to capacity")
	assertions.truthy(storage.remove_items({"tomato": 1}), "remove can bring storage to capacity")
	assertions.equal(storage.get_used_capacity(), 1, "removal can bring storage below capacity")
	assertions.truthy(storage.can_add({"potato": 1}), "add resumes when request fits current capacity")
	storage.free()


func _test_serialization_and_overloaded_restore(assertions: TestAssert) -> void:
	var capacity := MutableCapacity.new(2)
	var storage = FarmStorageSystemScript.new()
	storage.configure(capacity.provide)
	assertions.truthy(
		storage.restore_items_unchecked({"grain": 3, "tomato": 1}),
		"validated restore preserves contents above current capacity"
	)
	assertions.equal(storage.get_used_capacity(), 4, "overloaded restored state preserves every quantity")
	var saved: Dictionary = storage.to_dict()
	assertions.equal(saved, {"items": {"grain": 3, "tomato": 1}}, "storage serializes the items envelope")
	assertions.truthy(storage.validate_dict(saved), "serialized storage validates")

	var restored = FarmStorageSystemScript.new()
	restored.configure(capacity.provide)
	assertions.truthy(restored.from_dict(saved), "valid storage state deserializes")
	assertions.equal(restored.to_dict(), saved, "storage serialization round trip is exact")
	assertions.equal(restored.get_used_capacity(), 4, "round trip keeps overloaded data")
	saved.items["grain"] = 1
	assertions.equal(restored.get_count("grain"), 3, "from_dict duplicates incoming state")
	restored.free()
	storage.free()


func _test_strict_request_validation(assertions: TestAssert) -> void:
	var storage = FarmStorageSystemScript.new()
	assertions.truthy(storage.add_items({"grain": 2}), "validation fixture stores a crop")
	var invalid_requests: Array[Dictionary] = [
		{},
		{1: 1},
		{"": 1},
		{"grain": true},
		{"grain": 1.0},
		{"grain": 0},
		{"grain": -1},
		{"grain": EconomyLimitsScript.MAX_SAFE_INTEGER + 1},
		{"grain": EconomyLimitsScript.MAX_SAFE_INTEGER, "tomato": 1},
		{"missing_crop": 1},
		{"grain_seed": 1},
		{"wood": 1},
	]
	for index in range(invalid_requests.size()):
		var request := invalid_requests[index]
		var before: Dictionary = storage.get_items()
		assertions.equal(storage.get_missing_capacity(request), -1, "invalid request %d has stable missing result" % index)
		assertions.truthy(not storage.can_add(request), "invalid request %d cannot add" % index)
		assertions.truthy(not storage.add_items(request), "invalid request %d add is rejected" % index)
		assertions.truthy(not storage.can_remove(request), "invalid request %d cannot remove" % index)
		assertions.truthy(not storage.remove_items(request), "invalid request %d remove is rejected" % index)
		assertions.equal(storage.get_items(), before, "invalid request %d leaves state unchanged" % index)

	var before_mixed: Dictionary = storage.get_items()
	assertions.truthy(
		not storage.add_items({"tomato": 1, "wood": 1}),
		"mixed valid and invalid add rejects the whole batch"
	)
	assertions.equal(storage.get_items(), before_mixed, "mixed invalid add has no partial mutation")
	assertions.truthy(
		not storage.remove_items({"grain": 1, "tomato": 1}),
		"mixed sufficient and insufficient remove rejects the whole batch"
	)
	assertions.equal(storage.get_items(), before_mixed, "mixed insufficient remove has no partial mutation")
	storage.free()

	var maximum_capacity := MutableCapacity.new(EconomyLimitsScript.MAX_SAFE_INTEGER)
	var maximum_storage = FarmStorageSystemScript.new()
	assertions.truthy(maximum_storage.configure(maximum_capacity.provide), "maximum safe provider capacity is valid")
	assertions.truthy(
		maximum_storage.add_items({"grain": EconomyLimitsScript.MAX_SAFE_INTEGER}),
		"maximum safe item quantity is valid"
	)
	assertions.equal(
		maximum_storage.get_used_capacity(),
		EconomyLimitsScript.MAX_SAFE_INTEGER,
		"maximum safe quantity preserves exact used capacity"
	)
	assertions.truthy(not maximum_storage.can_add({"grain": 1}), "addition beyond safe total is rejected")
	maximum_storage.free()


func _test_failed_restore_validation_is_atomic(assertions: TestAssert) -> void:
	var storage = FarmStorageSystemScript.new()
	storage.add_items({"grain": 2})
	var before: Dictionary = storage.to_dict()
	var invalid_data: Array[Dictionary] = [
		{},
		{"items": []},
		{"items": {}, "extra": true},
		{"items": {1: 1}},
		{"items": {"": 1}},
		{"items": {"grain": false}},
		{"items": {"grain": 1.0}},
		{"items": {"grain": 0}},
		{"items": {"grain": -1}},
		{"items": {"grain": EconomyLimitsScript.MAX_SAFE_INTEGER + 1}},
		{"items": {"grain": EconomyLimitsScript.MAX_SAFE_INTEGER, "tomato": 1}},
		{"items": {"unknown": 1}},
		{"items": {"grain_seed": 1}},
		{"items": {"wood": 1}},
	]
	for index in range(invalid_data.size()):
		assertions.truthy(not storage.validate_dict(invalid_data[index]), "invalid save %d fails validation" % index)
		assertions.truthy(not storage.from_dict(invalid_data[index]), "invalid save %d fails restore" % index)
		assertions.equal(storage.to_dict(), before, "invalid save %d preserves prior state" % index)

	assertions.truthy(
		not storage.restore_items_unchecked({"grain": 1, "wood": 1}),
		"unchecked restore still rejects non-crop state"
	)
	assertions.equal(storage.to_dict(), before, "failed unchecked restore preserves prior state")
	assertions.truthy(storage.validate_dict({"items": {}}), "empty item state is valid save data")
	assertions.truthy(storage.from_dict({"items": {}}), "valid empty state restores")
	assertions.equal(storage.get_items(), {}, "empty restore clears storage")
	storage.free()


func _test_committed_signal_payloads(assertions: TestAssert, tree: SceneTree) -> void:
	var capacity := MutableCapacity.new(4)
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	storage.configure(capacity.provide)
	var recorder := SignalRecorder.new(storage)
	var event_bus = tree.root.get_node("EventBus")
	storage.contents_changed.connect(recorder.on_contents)
	storage.capacity_changed.connect(recorder.on_capacity)
	event_bus.farm_storage_changed.connect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.connect(recorder.on_bus_capacity)

	assertions.truthy(storage.add_items({"grain": 2, "tomato": 1}), "signal fixture add succeeds")
	assertions.equal(recorder.contents.size(), 1, "successful add emits one local contents event")
	assertions.equal(recorder.bus_contents.size(), 1, "successful add emits one EventBus contents event")
	assertions.equal(recorder.capacities.size(), 1, "successful add emits one local capacity event")
	assertions.equal(recorder.bus_capacities.size(), 1, "successful add emits one EventBus capacity event")
	assertions.equal(recorder.contents[0].changes, {"grain": 2, "tomato": 1}, "add event carries positive deltas")
	assertions.equal(recorder.contents[0].state, {"grain": 2, "tomato": 1}, "contents event observes committed state")
	assertions.equal(recorder.capacities[0], {"used": 3, "total": 4}, "add capacity event carries committed totals")

	assertions.truthy(not storage.add_items({"potato": 2}), "capacity failure is rejected silently")
	assertions.truthy(not storage.remove_items({"grain": 3}), "insufficient remove is rejected silently")
	assertions.truthy(not storage.add_items({"wood": 1}), "invalid item add is rejected silently")
	assertions.equal(recorder.contents.size(), 1, "failed operations emit no local contents events")
	assertions.equal(recorder.bus_contents.size(), 1, "failed operations emit no EventBus contents events")
	assertions.equal(recorder.capacities.size(), 1, "failed operations emit no local capacity events")
	assertions.equal(recorder.bus_capacities.size(), 1, "failed operations emit no EventBus capacity events")

	assertions.truthy(storage.remove_items({"grain": 1}), "signal fixture remove succeeds")
	assertions.equal(recorder.contents[1].changes, {"grain": -1}, "remove event carries negative deltas")
	assertions.equal(recorder.capacities[1], {"used": 2, "total": 4}, "remove capacity event carries committed totals")
	assertions.truthy(storage.restore_items_unchecked({"potato": 2}), "signal fixture restore succeeds")
	assertions.equal(
		recorder.contents[2].changes,
		{"grain": -1, "tomato": -1, "potato": 2},
		"restore event carries exact replacement deltas"
	)
	assertions.equal(recorder.contents[2].state, {"potato": 2}, "restore event observes replacement state")
	assertions.equal(recorder.capacities.size(), 2, "equal-used restore does not emit capacity change")
	assertions.truthy(storage.restore_items_unchecked({"potato": 2}), "identical restore succeeds")
	assertions.equal(recorder.contents.size(), 3, "identical restore emits no contents event")

	capacity.value = 3
	storage.refresh_capacity()
	assertions.equal(recorder.capacities[2], {"used": 2, "total": 3}, "provider refresh emits derived capacity")
	assertions.equal(recorder.bus_capacities[2], {"used": 2, "total": 3}, "EventBus receives derived capacity")
	capacity.value = 1.5
	storage.refresh_capacity()
	assertions.equal(recorder.capacities.size(), 3, "invalid provider refresh emits no local capacity event")
	assertions.equal(recorder.bus_capacities.size(), 3, "invalid provider refresh emits no EventBus capacity event")
	assertions.equal(recorder.bus_contents, [
		{"grain": 2, "tomato": 1},
		{"grain": -1},
		{"grain": -1, "tomato": -1, "potato": 2},
	], "EventBus contents payloads match committed local payloads")

	storage.contents_changed.disconnect(recorder.on_contents)
	storage.capacity_changed.disconnect(recorder.on_capacity)
	event_bus.farm_storage_changed.disconnect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.disconnect(recorder.on_bus_capacity)
	storage.free()


func _test_contents_reentrancy_preserves_notification_order(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var capacity := MutableCapacity.new(4)
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	storage.configure(capacity.provide)
	var recorder := ReentrantContentsRecorder.new(storage)
	var event_bus = tree.root.get_node("EventBus")
	storage.contents_changed.connect(recorder.on_contents)
	storage.capacity_changed.connect(recorder.on_capacity)
	event_bus.farm_storage_changed.connect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.connect(recorder.on_bus_capacity)

	assertions.truthy(storage.add_items({"grain": 1}), "outer add succeeds during contents reentrancy test")
	assertions.equal(recorder.nested_add_results, [true], "contents listener nested add succeeds once")
	assertions.equal(recorder.local_contents, [{"grain": 1}, {"tomato": 1}], "local content deltas stay in commit order")
	assertions.equal(recorder.bus_contents, [{"grain": 1}, {"tomato": 1}], "EventBus content deltas stay in commit order")
	assertions.equal(recorder.timeline, [
		"local_contents:grain",
		"bus_contents:grain",
		"local_capacity:1:4",
		"bus_capacity:1:4",
		"local_contents:tomato",
		"bus_contents:tomato",
		"local_capacity:2:4",
		"bus_capacity:2:4",
	], "nested mutation notifications drain as complete FIFO batches")
	var expected_final := {"used": storage.get_used_capacity(), "total": storage.get_total_capacity()}
	assertions.equal(recorder.local_capacities.back(), expected_final, "final local capacity matches nested committed state")
	assertions.equal(recorder.bus_capacities.back(), expected_final, "final EventBus capacity matches nested committed state")
	assertions.equal(storage.get_items(), {"grain": 1, "tomato": 1}, "both reentrant mutations remain committed")

	storage.contents_changed.disconnect(recorder.on_contents)
	storage.capacity_changed.disconnect(recorder.on_capacity)
	event_bus.farm_storage_changed.disconnect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.disconnect(recorder.on_bus_capacity)
	storage.free()


func _test_capacity_reentrancy_preserves_notification_order(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var capacity := MutableCapacity.new(4)
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	storage.configure(capacity.provide)
	var recorder := ReentrantCapacityRecorder.new(storage, capacity)
	var event_bus = tree.root.get_node("EventBus")
	storage.capacity_changed.connect(recorder.on_capacity)
	event_bus.farm_storage_capacity_changed.connect(recorder.on_bus_capacity)

	capacity.value = 5
	storage.refresh_capacity()
	assertions.equal(recorder.timeline, ["local:5", "bus:5", "local:7", "bus:7"], "nested refresh notifications stay in commit order")
	var expected_final := {"used": storage.get_used_capacity(), "total": storage.get_total_capacity()}
	assertions.equal(recorder.local_capacities.back(), expected_final, "final local payload matches refreshed provider total")
	assertions.equal(recorder.bus_capacities.back(), expected_final, "final EventBus payload matches refreshed provider total")
	assertions.equal(storage.get_total_capacity(), 7, "nested provider refresh commits the latest total")

	storage.capacity_changed.disconnect(recorder.on_capacity)
	event_bus.farm_storage_capacity_changed.disconnect(recorder.on_bus_capacity)
	storage.free()


func _test_change_payload_is_read_only_for_all_listeners(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	var recorder := ReadOnlyPayloadRecorder.new()
	var event_bus = tree.root.get_node("EventBus")
	storage.contents_changed.connect(recorder.on_first)
	storage.contents_changed.connect(recorder.on_second)
	event_bus.farm_storage_changed.connect(recorder.on_bus)

	assertions.truthy(storage.add_items({"grain": 2}), "read-only payload fixture add succeeds")
	assertions.equal(recorder.read_only_results, [true, true, true], "all local and EventBus listeners receive read-only changes")
	assertions.equal(recorder.payloads, [{"grain": 2}, {"grain": 2}, {"grain": 2}], "shared read-only payload remains unchanged across listeners")

	storage.contents_changed.disconnect(recorder.on_first)
	storage.contents_changed.disconnect(recorder.on_second)
	event_bus.farm_storage_changed.disconnect(recorder.on_bus)
	storage.free()


func _test_rejected_operations_and_freed_provider_are_silent(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var capacity := DisposableCapacity.new(4)
	var storage = FarmStorageSystemScript.new()
	tree.root.add_child(storage)
	storage.configure(capacity.provide)
	var recorder := SignalRecorder.new(storage)
	var event_bus = tree.root.get_node("EventBus")
	storage.contents_changed.connect(recorder.on_contents)
	storage.capacity_changed.connect(recorder.on_capacity)
	event_bus.farm_storage_changed.connect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.connect(recorder.on_bus_capacity)

	assertions.truthy(not storage.from_dict({"items": {"wood": 1}}), "invalid from_dict is rejected")
	assertions.truthy(not storage.restore_items_unchecked({"grain": 1, "wood": 1}), "invalid unchecked restore is rejected")
	var invalid_provider := MutableCapacity.new(4.0)
	assertions.truthy(not storage.configure(invalid_provider.provide), "invalid provider configure is rejected")
	capacity.free()
	storage.refresh_capacity()
	assertions.equal(storage.get_total_capacity(), 4, "freed provider target preserves last valid total")
	assertions.equal(recorder.contents, [], "rejected restore operations emit no local contents signals")
	assertions.equal(recorder.bus_contents, [], "rejected restore operations emit no EventBus contents signals")
	assertions.equal(recorder.capacities, [], "failed configure and freed provider emit no local capacity signals")
	assertions.equal(recorder.bus_capacities, [], "failed configure and freed provider emit no EventBus capacity signals")

	storage.contents_changed.disconnect(recorder.on_contents)
	storage.capacity_changed.disconnect(recorder.on_capacity)
	event_bus.farm_storage_changed.disconnect(recorder.on_bus_contents)
	event_bus.farm_storage_capacity_changed.disconnect(recorder.on_bus_capacity)
	storage.free()
