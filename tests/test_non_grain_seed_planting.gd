extends RefCounted

## Test that non-grain seeds can be planted when they are in inventory
## even if the seed quick slot (5) doesn't contain them directly.
## Validates the fix for: "种子还是不能播种"

const PlayerActionControllerScript = preload("res://scripts/actors/player_action_controller.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")


func run(assertions: TestAssert) -> void:
	# Test 1: _find_first_seed_in_inventory finds seed items
	var controller := PlayerActionControllerScript.new()
	var inventory := InventorySystemScript.new()
	controller.inventory_system = inventory

	# No seeds → empty
	var found := controller._find_first_seed_in_inventory()
	assertions.equal(found, "", "no seeds → _find_first_seed returns empty")

	# tomato_seed in inventory → found
	inventory.add_item("tomato_seed", 5)
	found = controller._find_first_seed_in_inventory()
	assertions.equal(found, "tomato_seed", "tomato_seed found via inventory scan")

	# Test 2: _get_active_plant_item_id falls back to inventory when quick slot is empty
	var active_id := controller._get_active_plant_item_id()
	assertions.equal(active_id, "tomato_seed", "_get_active_plant_item_id finds tomato_seed via fallback")

	# Test 3: crop_id_for_plant_item handles both _seed and _sapling suffixes
	assertions.equal(
		PlayerActionControllerScript.crop_id_for_plant_item("carrot_seed"),
		"carrot",
		"carrot_seed → carrot"
	)
	assertions.equal(
		PlayerActionControllerScript.crop_id_for_plant_item("lemon_sapling"),
		"lemon",
		"lemon_sapling → lemon"
	)
	assertions.equal(
		PlayerActionControllerScript.crop_id_for_plant_item("wood"),
		"",
		"non-seed item returns empty"
	)

	# Test 4: auto_map_seed_to_quick_slot maps the first seed
	inventory.reset_slots()
	inventory.add_item("carrot_seed", 3)
	var mapped := controller.auto_map_seed_to_quick_slot()
	assertions.truthy(mapped, "auto_map_seed_to_quick_slot succeeds with carrot_seed")
	assertions.equal(
		inventory.get_quick_item(PlayerActionController.SEED_SLOT),
		"carrot_seed",
		"quick slot 5 now has carrot_seed"
	)

	# Test 5: auto_map doesn't overwrite an already-mapped valid seed
	inventory.add_item("lemon_sapling", 2)
	var mapped_again := controller.auto_map_seed_to_quick_slot()
	assertions.truthy(not mapped_again, "auto_map does not overwrite existing valid seed mapping")
	assertions.equal(
		inventory.get_quick_item(PlayerActionController.SEED_SLOT),
		"carrot_seed",
		"quick slot 5 still has carrot_seed"
	)

	# Test 6: When quick slot seed is depleted, fallback finds remaining seed
	inventory.remove_item("carrot_seed", 3)
	# Quick slot 5 still points to the (now empty) slot, so get_quick_item may return ""
	# _get_active_plant_item_id should fall back to finding lemon_sapling
	active_id = controller._get_active_plant_item_id()
	assertions.equal(active_id, "lemon_sapling", "depleted quick slot falls back to lemon_sapling")

	controller.free()
