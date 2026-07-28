extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")


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
	inventory.free()
	game_data.free()
