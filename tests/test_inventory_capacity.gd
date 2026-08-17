extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")


class InventoryEventBus:
	extends Node

	signal item_added(item_id: String, quantity: int)
	signal item_removed(item_id: String, quantity: int)


class InventoryNotificationRecorder:
	extends RefCounted
	var events: Array[String] = []

	func on_quick_changed(index: int, item_id: String) -> void:
		events.append("quick:%d:%s" % [index, item_id])

	func on_item_added(item_id: String, quantity: int) -> void:
		events.append("added:%s:%d" % [item_id, quantity])

	func on_item_removed(item_id: String, quantity: int) -> void:
		events.append("removed:%s:%d" % [item_id, quantity])


func run(assertions: TestAssert) -> void:
	var game_data := GameDataScript.new()
	assertions.equal(
		game_data.get_item("grain_seed").get("category", ""),
		"seed",
		"grain seed is registered"
	)
	assertions.equal(
		game_data.get_item("grain").get("category", ""),
		"crop",
		"grain harvest is registered"
	)

	var inventory_script = load("res://scripts/systems/inventory_system.gd")
	assertions.truthy(inventory_script != null, "inventory script loads")
	if inventory_script == null:
		game_data.free()
		return
	var inventory = inventory_script.new()
	inventory.max_slots = 1
	inventory.reset_slots()
	var has_capacity_api: bool = inventory.has_method("can_add_item")
	assertions.truthy(has_capacity_api, "inventory exposes capacity preflight")
	if not has_capacity_api:
		inventory.free()
		game_data.free()
		return
	assertions.truthy(
		inventory.call("can_add_item", "grain_seed", 99),
		"empty slot accepts one full stack"
	)
	assertions.truthy(
		not inventory.call("can_add_item", "grain_seed", 100),
		"empty slot rejects more than one full stack"
	)
	inventory.add_item("grain_seed", 98)
	assertions.truthy(
		inventory.call("can_add_item", "grain_seed", 1),
		"partial stack accepts remaining item"
	)
	assertions.truthy(
		not inventory.call("can_add_item", "grain", 1),
		"full inventory rejects a different item"
	)
	var has_structured_preflight: bool = inventory.has_method("preflight_add_items")
	assertions.truthy(has_structured_preflight, "inventory exposes structured multi-item capacity preflight")
	if has_structured_preflight:
		var full_result: Dictionary = inventory.call("preflight_add_items", {"grain": 1})
		assertions.equal(full_result.get("reason"), "inventory_capacity", "full inventory reports a stable capacity reason")
		assertions.equal(full_result.get("missing_slots"), 1, "full inventory reports the exact missing slot count")
		assertions.equal(full_result.get("missing_quantity"), 1, "full inventory reports the exact missing quantity")
		var partial_result: Dictionary = inventory.call("preflight_add_items", {"grain_seed": 2})
		assertions.equal(partial_result.get("available_quantity"), 1, "preflight counts usable partial-stack space")
		assertions.equal(partial_result.get("missing_quantity"), 1, "partial capacity reports only the unplaceable quantity")
		assertions.equal(partial_result.get("missing_slots"), 1, "partial capacity reports the one additional slot required")
	inventory.free()
	_test_restore_notification_transaction(assertions, inventory_script)
	game_data.free()


func _test_restore_notification_transaction(assertions: TestAssert, inventory_script: Script) -> void:
	var inventory = inventory_script.new()
	var events := InventoryEventBus.new()
	var recorder := InventoryNotificationRecorder.new()
	inventory._event_bus = events
	inventory.restore_state(
		[{"item_id": "grain_seed", "quantity": 2}],
		[0, -1, -1, -1, -1, -1]
	)
	inventory.quick_slot_mapping_changed.connect(recorder.on_quick_changed)
	events.item_added.connect(recorder.on_item_added)
	events.item_removed.connect(recorder.on_item_removed)

	assertions.truthy(
		inventory.has_method("begin_restore_notification_transaction")
		and inventory.has_method("end_restore_notification_transaction"),
		"inventory exposes scoped restore notification isolation"
	)
	if not inventory.has_method("begin_restore_notification_transaction"):
		inventory.free()
		events.free()
		return
	assertions.truthy(inventory.begin_restore_notification_transaction(), "inventory begins one restore notification transaction")
	assertions.truthy(not inventory.begin_restore_notification_transaction(), "inventory rejects nested restore notification ownership")
	inventory.restore_state(
		[{"item_id": "carrot_seed", "quantity": 2}],
		[0, -1, -1, -1, -1, -1]
	)
	assertions.truthy(inventory.add_item("wood", 1), "inventory accepts staged write during restore notification transaction")
	assertions.truthy(inventory.remove_item("wood", 1), "inventory accepts staged removal during restore notification transaction")
	assertions.equal(recorder.events, [], "inventory restore and item notifications stay silent while tentative")
	inventory.restore_state(
		[{"item_id": "grain_seed", "quantity": 2}],
		[0, -1, -1, -1, -1, -1]
	)
	assertions.truthy(inventory.end_restore_notification_transaction(false), "inventory discards rolled-back restore notifications")
	assertions.equal(recorder.events, [], "inventory rollback emits no tentative or compensating notifications")
	assertions.truthy(inventory.begin_restore_notification_transaction(), "inventory transaction is reusable after rollback")
	inventory.restore_state(
		[{"item_id": "carrot_seed", "quantity": 2}],
		[0, -1, -1, -1, -1, -1]
	)
	assertions.equal(recorder.events, [], "successful inventory restore remains silent before commit")
	assertions.truthy(inventory.end_restore_notification_transaction(true), "inventory commits restore notifications")
	assertions.equal(
		recorder.events,
		["quick:0:carrot_seed"],
		"inventory commit emits one coalesced final quick-slot notification"
	)

	inventory.free()
	events.free()
