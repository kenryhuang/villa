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
		})

	func on_capacity(used: int, total: int) -> void:
		capacities.append({"used": used, "total": total})

	func on_bus_contents(changes: Dictionary) -> void:
		bus_contents.append(changes.duplicate(true))

	func on_bus_capacity(used: int, total: int) -> void:
		bus_capacities.append({"used": used, "total": total})


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_empty_state_and_capacity_provider(assertions)
	_test_atomic_add_remove_and_capacity(assertions)
	_test_capacity_overload_behavior(assertions)
	_test_serialization_and_overloaded_restore(assertions)
	_test_strict_request_validation(assertions)
	_test_failed_restore_validation_is_atomic(assertions)
	_test_committed_signal_payloads(assertions, tree)


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
