extends RefCounted

const EconomySystemScript = preload("res://scripts/systems/economy_system.gd")
const EventBusScript = preload("res://scripts/core/event_bus.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const InventoryUIScript = preload("res://scripts/ui/inventory_ui.gd")


func run(assertions: TestAssert) -> void:
	_test_game_data(assertions)
	_test_inventory(assertions)
	_test_economy(assertions)
	_test_inventory_ui(assertions)


func _test_game_data(assertions: TestAssert) -> void:
	var data = GameDataScript.new()
	assertions.equal(data.get_all_items().size(), 27, "all Phase 1 items are registered")
	assertions.equal(data.get_item("tomato_seed").buy_price, 5, "seed buy price is available")
	assertions.equal(data.get_item("moonflower").max_stack, 1, "rare item stack limit is one")
	assertions.equal(data.get_all_buildings().size(), 9, "all buildings are registered")
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
	inventory.swap_slots(0, 1)
	assertions.equal(inventory.get_quick_item(0), "", "quick mapping follows physical slot")
	assertions.truthy(not inventory.add_item("missing", 1), "unknown item is rejected")

	var tiny_inventory = InventorySystemScript.new()
	tiny_inventory.max_slots = 1
	tiny_inventory.reset_slots()
	assertions.truthy(not tiny_inventory.add_item("wood", 100), "full add fails atomically")
	assertions.equal(tiny_inventory.get_item_count("wood"), 0, "failed add does not mutate inventory")


func _test_economy(assertions: TestAssert) -> void:
	var inventory = InventorySystemScript.new()
	var economy = EconomySystemScript.new()
	economy.configure(inventory)
	assertions.truthy(economy.spend_gold(30), "economy can spend available gold")
	assertions.equal(economy.gold, 70, "spending changes gold")
	assertions.truthy(not economy.spend_gold(71), "economy rejects overspending")
	assertions.truthy(economy.add_gold(10), "economy adds positive gold")
	assertions.equal(economy.gold, 80, "adding changes gold")
	assertions.truthy(not economy.add_gold(-1), "economy rejects negative gold")

	assertions.truthy(inventory.add_item("wood", 100), "resources can be prepared")
	assertions.truthy(inventory.add_item("stone", 50), "second resource can be prepared")
	var cost := {"wood": 100, "stone": 50}
	assertions.truthy(economy.has_resources(cost), "resource cost can be checked")
	assertions.truthy(economy.spend_resources(cost), "resource cost can be spent")
	assertions.equal(inventory.get_item_count("wood"), 0, "resource spend removes first material")
	assertions.equal(inventory.get_item_count("stone"), 0, "resource spend removes second material")

	economy.generate_daily_orders()
	assertions.truthy(economy.orders.size() >= 2 and economy.orders.size() <= 3, "daily generation creates two or three orders")
	var order: Dictionary = economy.orders[0]
	assertions.equal(order.days_remaining, 3, "new order lasts three days")
	assertions.truthy(inventory.add_item(order.item_id, order.quantity), "order items can be prepared")
	var old_gold: int = economy.gold
	assertions.truthy(economy.complete_order(0), "complete order consumes inventory")
	assertions.equal(economy.gold, old_gold + order.reward_gold, "order grants gold")
	assertions.equal(economy.get_affinity(order.villager_id), 10, "order grants ten affinity")


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
