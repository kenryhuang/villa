extends RefCounted

const EconomySystemScript = preload("res://scripts/systems/economy_system.gd")
const EventBusScript = preload("res://scripts/core/event_bus.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const InventoryUIScript = preload("res://scripts/ui/inventory_ui.gd")


class WalletDouble:
	extends Node

	var gold := 100

	func add_gold(amount: int) -> bool:
		if amount <= 0:
			return false
		gold += amount
		return true

	func spend_gold(amount: int) -> bool:
		if amount <= 0 or amount > gold:
			return false
		gold -= amount
		return true


class QuickMappingRecorder:
	var events: Array[Dictionary] = []

	func on_mapping_changed(quick_index: int, item_id: String) -> void:
		events.append({"quick_index": quick_index, "item_id": item_id})


func run(assertions: TestAssert) -> void:
	_test_game_data(assertions)
	_test_inventory(assertions)
	_test_economy(assertions)
	_test_inventory_ui(assertions)


func _test_game_data(assertions: TestAssert) -> void:
	var data = GameDataScript.new()
	for item_id in ["wood", "clay", "iron_ingot", "honey", "flour", "fruit_jam"]:
		assertions.truthy(not data.get_item(item_id).is_empty(), item_id + " is registered")
	assertions.equal(data.get_item("tomato_seed").buy_price, 5, "seed buy price is available")
	assertions.equal(data.get_item("moonflower").max_stack, 1, "rare item stack limit is one")
	assertions.equal(data.get_all_buildings().size(), 17, "all buildings are registered")
	assertions.equal(data.get_building("barn").cost.wood, 100, "building resource cost is available")
	assertions.equal(data.get_all_villagers().size(), 5, "all villagers are registered")
	assertions.equal(data.get_villager("lao_li").schedule["8-12"], "shop", "villager schedule is available")
	assertions.equal(data.get_all_collectibles().size(), 46, "all collectibles are registered")
	assertions.truthy(data.get_collectible("specimen_20") != null, "last specimen is registered")
	assertions.truthy(data.get_item("missing") == null, "unknown item returns null")


func _test_inventory(assertions: TestAssert) -> void:
	var inventory = InventorySystemScript.new()
	assertions.equal(inventory.slots.size(), 20, "inventory initializes twenty slots")
	assertions.truthy(inventory.add_item("wood", 120), "items split across stacks")
	assertions.equal(inventory.slots[0].quantity, 99, "first stack reaches max")
	assertions.equal(inventory.slots[1].quantity, 21, "overflow uses empty slot")
	assertions.equal(inventory.get_item_count("wood"), 120, "item count spans stacks")
	assertions.truthy(inventory.has_item("wood", 120), "has_item spans stacks")
	assertions.truthy(inventory.remove_item("wood", 100), "remove spans stacks")
	assertions.equal(inventory.get_item_count("wood"), 20, "remove updates total")
	assertions.truthy(not inventory.remove_item("wood", 21), "cannot remove unavailable quantity")
	assertions.truthy(inventory.set_quick_slot(1, 0), "quick slot maps inventory slot")
	assertions.equal(inventory.get_quick_item(0), "wood", "quick slot returns mapped item id")
	assertions.truthy(not inventory.set_quick_slot(1, 6), "quick slot rejects an invalid quick index")
	assertions.truthy(not inventory.set_quick_slot(99, 0), "quick slot rejects an invalid inventory index")
	inventory.swap_slots(0, 1)
	assertions.equal(inventory.get_quick_item(0), "", "quick mapping follows physical slot")
	assertions.truthy(not inventory.add_item("missing", 1), "unknown item is rejected")

	var mapping_inventory = InventorySystemScript.new()
	mapping_inventory.add_item("grain_seed", 2)
	mapping_inventory.add_item("carrot_seed", 1)
	mapping_inventory.add_item("rose_seed", 3)
	var mapping_recorder := QuickMappingRecorder.new()
	assertions.truthy(
		mapping_inventory.has_signal("quick_slot_mapping_changed"),
		"inventory exposes a quick-slot mapping signal"
	)
	if mapping_inventory.has_signal("quick_slot_mapping_changed"):
		mapping_inventory.quick_slot_mapping_changed.connect(
			mapping_recorder.on_mapping_changed
		)
		assertions.truthy(
			mapping_inventory.set_quick_slot(0, 5),
			"mapping signal fixture selects grain seed"
		)
		mapping_inventory.set_quick_slot(0, 5)
		assertions.equal(
			mapping_recorder.events,
			[{"quick_index": 5, "item_id": "grain_seed"}],
			"identical quick-slot assignments emit only once"
		)
		mapping_inventory.set_quick_slot(1, 5)
		assertions.equal(
			mapping_recorder.events.back(),
			{"quick_index": 5, "item_id": "carrot_seed"},
			"changed quick-slot assignments emit the active item"
		)
		assertions.truthy(
			not mapping_inventory.set_quick_slot(99, 5),
			"invalid inventory assignment clears the quick slot"
		)
		mapping_inventory.set_quick_slot(99, 5)
		assertions.equal(
			mapping_recorder.events.size(),
			3,
			"clearing an already empty mapping does not emit twice"
		)
		assertions.equal(
			mapping_recorder.events.back(),
			{"quick_index": 5, "item_id": ""},
			"clearing a mapping emits an empty item id"
		)
		var restored_mappings: Array[int] = [-1, -1, -1, -1, -1, 2]
		mapping_inventory.restore_state(
			mapping_inventory.slots.duplicate(true),
			restored_mappings
		)
		assertions.equal(
			mapping_recorder.events.back(),
			{"quick_index": 5, "item_id": "rose_seed"},
			"restoring a changed mapping emits the restored item"
		)
		var restore_event_count := mapping_recorder.events.size()
		mapping_inventory.restore_state(
			mapping_inventory.slots.duplicate(true),
			restored_mappings
		)
		assertions.equal(
			mapping_recorder.events.size(),
			restore_event_count,
			"restoring identical state does not duplicate mapping events"
		)
		mapping_inventory.reset_slots()
		assertions.equal(
			mapping_recorder.events.back(),
			{"quick_index": 5, "item_id": ""},
			"resetting inventory emits a cleared mapping"
		)

	var lifecycle_inventory = InventorySystemScript.new()
	lifecycle_inventory.add_item("grain_seed", 2)
	lifecycle_inventory.add_item("carrot_seed", 1)
	lifecycle_inventory.add_item("wood", 1)
	var lifecycle_recorder := QuickMappingRecorder.new()
	lifecycle_inventory.quick_slot_mapping_changed.connect(
		lifecycle_recorder.on_mapping_changed
	)
	lifecycle_inventory.set_quick_slot(0, 5)
	lifecycle_recorder.events.clear()
	lifecycle_inventory.swap_slots(0, 1)
	assertions.equal(
		lifecycle_recorder.events,
		[{"quick_index": 5, "item_id": "carrot_seed"}],
		"swapping a mapped slot emits its final effective item once"
	)
	lifecycle_inventory.swap_slots(0, 1)
	assertions.equal(
		lifecycle_recorder.events.back(),
		{"quick_index": 5, "item_id": "grain_seed"},
		"swapping the mapped item back emits the restored effective item"
	)
	var event_count_before_partial_remove := lifecycle_recorder.events.size()
	lifecycle_inventory.remove_item("grain_seed", 1)
	assertions.equal(
		lifecycle_recorder.events.size(),
		event_count_before_partial_remove,
		"partial removal with the same effective item emits no mapping event"
	)
	lifecycle_inventory.remove_item("grain_seed", 1)
	assertions.equal(
		lifecycle_recorder.events.back(),
		{"quick_index": 5, "item_id": ""},
		"depleting a mapped slot emits empty after the slot is cleared"
	)
	lifecycle_inventory.add_item("rose_seed", 2)
	assertions.equal(
		lifecycle_recorder.events.back(),
		{"quick_index": 5, "item_id": "rose_seed"},
		"refilling a mapped empty slot emits its new effective item"
	)
	var event_count_before_partial_add := lifecycle_recorder.events.size()
	lifecycle_inventory.add_item("rose_seed", 1)
	assertions.equal(
		lifecycle_recorder.events.size(),
		event_count_before_partial_add,
		"adding quantity to the same effective item emits no mapping event"
	)
	lifecycle_inventory.set_quick_slot(2, 0)
	lifecycle_recorder.events.clear()
	assertions.truthy(lifecycle_inventory.use_item(2), "mapped material can be consumed")
	assertions.equal(
		lifecycle_recorder.events,
		[{"quick_index": 0, "item_id": ""}],
		"using the last mapped item emits empty after final depletion"
	)

	var transaction_inventory = InventorySystemScript.new()
	transaction_inventory.set_quick_slot(0, 5)
	var transaction_recorder := QuickMappingRecorder.new()
	transaction_inventory.quick_slot_mapping_changed.connect(
		transaction_recorder.on_mapping_changed
	)
	assertions.truthy(
		transaction_inventory.has_method("begin_mapping_transaction")
		and transaction_inventory.has_method("end_mapping_transaction"),
		"inventory exposes an owned quick-mapping transaction boundary"
	)
	if (
		transaction_inventory.has_method("begin_mapping_transaction")
		and transaction_inventory.has_method("end_mapping_transaction")
	):
		var empty_slots: Array[Dictionary] = transaction_inventory.slots.duplicate(true)
		var empty_mappings: Array[int] = transaction_inventory.quick_slot_mappings.duplicate()
		assertions.truthy(
			transaction_inventory.begin_mapping_transaction(),
			"first caller owns the mapping transaction"
		)
		assertions.truthy(
			not transaction_inventory.begin_mapping_transaction(),
			"nested mapping transaction ownership is rejected"
		)
		transaction_inventory.add_item("grain_seed", 1)
		assertions.equal(
			transaction_recorder.events,
			[],
			"mapping notifications stay suppressed during a transaction"
		)
		transaction_inventory.restore_state(empty_slots, empty_mappings)
		assertions.truthy(
			transaction_inventory.end_mapping_transaction(false),
			"transaction owner can finish a rollback"
		)
		assertions.equal(
			transaction_recorder.events,
			[],
			"rolled-back mapping transaction emits no notifications"
		)
		assertions.truthy(
			not transaction_inventory.end_mapping_transaction(true),
			"non-owner cannot finish an inactive mapping transaction"
		)
		assertions.truthy(transaction_inventory.begin_mapping_transaction(), "new owner begins after rollback")
		transaction_inventory.add_item("grain_seed", 1)
		assertions.equal(transaction_recorder.events, [], "successful transaction waits for commit")
		assertions.truthy(transaction_inventory.end_mapping_transaction(true), "owner commits mapping transaction")
		assertions.equal(
			transaction_recorder.events,
			[{"quick_index": 5, "item_id": "grain_seed"}],
			"successful transaction emits one net effective-item change"
		)

	var tiny_inventory = InventorySystemScript.new()
	tiny_inventory.max_slots = 1
	tiny_inventory.reset_slots()
	assertions.truthy(not tiny_inventory.add_item("wood", 100), "full add fails atomically")
	assertions.equal(tiny_inventory.get_item_count("wood"), 0, "failed add does not mutate inventory")

	var legacy_inventory = InventorySystemScript.new()
	var legacy_state: Dictionary = JSON.parse_string(
		'{"slots":[{"item_id":"grain_seed","quantity":3},{}],'
		+ '"quick_mappings":[0,-1,-1,-1,-1,-1]}'
	)
	assertions.truthy(
		legacy_inventory.has_method("restore_state"),
		"inventory exposes a typed legacy-save restore boundary"
	)
	if legacy_inventory.has_method("restore_state"):
		legacy_inventory.call(
			"restore_state",
			legacy_state.get("slots", []),
			legacy_state.get("quick_mappings", [])
		)
		assertions.equal(
			legacy_inventory.slots.size(),
			legacy_inventory.max_slots,
			"legacy save slots are padded to inventory capacity"
		)
		assertions.equal(
			legacy_inventory.get_item_count("grain_seed"),
			3,
			"legacy JSON dictionaries restore into typed inventory slots"
		)
		assertions.equal(
			legacy_inventory.get_quick_item(0),
			"grain_seed",
			"legacy quick mappings restore into the typed integer array"
		)


func _test_economy(assertions: TestAssert) -> void:
	var inventory = InventorySystemScript.new()
	var wallet = WalletDouble.new()
	var economy = EconomySystemScript.new()
	assertions.truthy(economy.configure(inventory, wallet), "economy accepts a wallet")
	assertions.truthy(economy.spend_gold(30), "economy can spend available gold")
	assertions.equal(wallet.gold, 70, "spending changes wallet gold")
	assertions.truthy(not economy.spend_gold(71), "economy rejects overspending")
	assertions.truthy(economy.add_gold(10), "economy adds positive gold")
	assertions.equal(wallet.gold, 80, "adding changes wallet gold")
	assertions.truthy(not economy.add_gold(-1), "economy rejects negative gold")

	assertions.truthy(inventory.add_item("wood", 100), "resources can be prepared")
	assertions.truthy(inventory.add_item("stone", 50), "second resource can be prepared")
	var cost := {"wood": 100, "stone": 50}
	assertions.truthy(economy.has_resources(cost), "resource cost can be checked")
	assertions.truthy(economy.spend_resources(cost), "resource cost can be spent")
	assertions.equal(inventory.get_item_count("wood"), 0, "resource spend removes first material")
	assertions.equal(inventory.get_item_count("stone"), 0, "resource spend removes second material")

	economy.generate_demand_orders(1)
	assertions.equal(economy.get_order_count(), 0, "orders require injected real NPC shortages")
	assertions.truthy(not economy.complete_order("unknown"), "unknown stable order ID is rejected")


func _test_inventory_ui(assertions: TestAssert) -> void:
	var inventory = InventorySystemScript.new()
	var ui = InventoryUIScript.new()
	ui.configure(inventory)
	ui._ready()
	assertions.equal(ui.inventory_grid.columns, 5, "inventory grid has five columns")
	assertions.equal(ui.inventory_grid.get_child_count(), 20, "inventory UI shows twenty slots")
	assertions.equal(ui.quick_bar.get_child_count(), 6, "quick bar shows six slots")
	ui.open()
	assertions.truthy(ui.visible, "open shows inventory UI")
	ui.close()
	assertions.truthy(not ui.visible, "close hides inventory UI")
	ui.free()
