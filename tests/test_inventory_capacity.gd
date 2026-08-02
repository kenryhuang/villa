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
	game_data.free()
