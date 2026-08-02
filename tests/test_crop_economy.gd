extends RefCounted

const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const PlayerActionControllerScript = preload("res://scripts/actors/player_action_controller.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const MainScript = preload("res://scripts/main.gd")
const FARMLAND := 1
const PLANTED := 2


class FailingAfterMutationInventory:
	extends InventorySystem
	var restore_calls := 0

	func add_item(item_id: String, quantity: int = 1) -> bool:
		super.add_item(item_id, quantity)
		return false

	func restore_state(saved_slots: Variant, saved_quick_mappings: Variant) -> void:
		restore_calls += 1
		super.restore_state(saved_slots, saved_quick_mappings)


class InventorySignalRecorder:
	extends RefCounted
	var events: Array[String] = []

	func on_added(item_id: String, quantity: int) -> void:
		events.append("added:%s:%d" % [item_id, quantity])

	func on_removed(item_id: String, quantity: int) -> void:
		events.append("removed:%s:%d" % [item_id, quantity])


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_harvest_returns_item_quantities(assertions)
	_test_deterministic_tomato_yield_and_regrowth(assertions)
	_test_carrot_yield_and_removal(assertions)
	_test_harvest_count_save_round_trip(assertions, tree)
	_test_controller_harvest_is_atomic(assertions, tree)
	_test_crop_data_validation(assertions)
	_test_default_roster_and_item_catalog(assertions)
	_test_perennial_harvest_and_greenhouse_rules(assertions)
	_test_regrowing_crop_visual_remains(assertions)
	_test_roster_planting_uses_active_quick_item(assertions, tree)


func _test_harvest_returns_item_quantities(assertions: TestAssert) -> void:
	var grid = GridSystemScript.new()
	var crop = CropDataScript.new()
	crop.crop_id = "tomato"
	crop.growth_days = 4
	crop.exp_reward = 5
	grid.set_cell_state(1, 1, FARMLAND)
	var instance = grid.plant_crop(1, 1, crop)
	instance.growth_progress = 4.0

	var result: Dictionary = grid.harvest_crop(1, 1)

	assertions.truthy(result.get("items", null) is Dictionary, "harvest returns an item-quantity dictionary")
	if result.get("items", null) is Dictionary:
		assertions.equal(result.items, {"tomato": 1}, "harvest returns item quantities keyed by crop id")
	assertions.equal(result.get("exp", -1), 5, "harvest returns crop experience")
	assertions.equal(result.get("regrowing", null), false, "annual harvest reports no regrowth")
	grid.free()


func _test_deterministic_tomato_yield_and_regrowth(assertions: TestAssert) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "tomato"
	crop.growth_days = 4
	crop.yield_min = 2
	crop.yield_max = 3
	crop.regrow_days = 2
	crop.exp_reward = 5
	seed(42)
	var grid = GridSystemScript.new()
	grid.set_cell_state(1, 1, FARMLAND)
	var instance = grid.plant_crop(1, 1, crop)
	instance.growth_progress = 4.0
	var result: Dictionary = grid.harvest_crop(1, 1)
	assertions.equal(result, {"items": {"tomato": 3}, "exp": 5, "regrowing": true}, "tomato harvest has exact deterministic result shape")
	seed(42)
	var repeat_grid = GridSystemScript.new()
	repeat_grid.set_cell_state(1, 1, FARMLAND)
	var repeat_instance = repeat_grid.plant_crop(1, 1, crop)
	repeat_instance.growth_progress = 4.0
	assertions.equal(repeat_grid.harvest_crop(1, 1), result, "seed 42 yield repeats after recreating the crop")
	repeat_grid.free()
	var cell = grid.get_cell(1, 1)
	assertions.equal(cell.state, PLANTED, "regrowing tomato remains planted")
	assertions.truthy(cell.crop_instance == instance, "regrowth preserves the crop instance")
	assertions.equal(instance.harvest_count, 1, "harvest increments persisted counter")
	assertions.near(instance.growth_progress, 2.0, 0.001, "tomato resets to two-day regrowth phase")
	instance.advance_growth()
	assertions.truthy(not instance.is_mature(), "tomato is not mature after one regrowth day")
	instance.advance_growth()
	assertions.truthy(instance.is_mature(), "tomato matures after exactly two regrowth days")
	var second: Dictionary = grid.harvest_crop(1, 1)
	assertions.equal(second.get("items", {}), {"tomato": 2}, "next harvest uses incremented deterministic vector")
	grid.free()


func _test_carrot_yield_and_removal(assertions: TestAssert) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "carrot"
	crop.growth_days = 3
	crop.yield_min = 2
	crop.yield_max = 3
	var grid = GridSystemScript.new()
	grid.set_cell_state(2, 2, FARMLAND)
	var instance = grid.plant_crop(2, 2, crop)
	instance.growth_progress = 3.0
	var result: Dictionary = grid.harvest_crop(2, 2)
	var quantity := int(result.get("items", {}).get("carrot", 0))
	assertions.truthy(quantity >= 2 and quantity <= 3, "carrot harvest stays within authored yield range")
	assertions.equal(result.get("regrowing", true), false, "carrot reports no regrowth")
	assertions.equal(grid.get_cell(2, 2).state, FARMLAND, "non-regrowing annual carrot is removed")
	assertions.truthy(grid.get_cell(2, 2).crop_instance == null, "carrot instance is cleared")
	grid.free()


func _test_harvest_count_save_round_trip(assertions: TestAssert, tree: SceneTree) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "save_tomato"
	crop.growth_days = 4
	crop.yield_min = 2
	crop.yield_max = 3
	crop.regrow_days = 2
	var game_data = tree.root.get_node_or_null("GameData")
	assertions.truthy(game_data != null, "save fixture has GameData autoload")
	if game_data == null:
		return
	if game_data.get_crop(crop.crop_id) == null:
		assertions.truthy(game_data.register_crop(crop), "save fixture crop registers")

	var grid = GridSystemScript.new()
	tree.root.add_child(grid)
	grid.set_cell_state(4, 4, FARMLAND)
	var instance = grid.plant_crop(4, 4, crop)
	instance.growth_progress = 4.0
	grid.harvest_crop(4, 4)
	var saved: Dictionary = grid.to_dict()
	assertions.equal(saved.cells[0].crop.get("harvest_count", -1), 1, "grid save persists harvest count")
	var json_saved: Variant = JSON.parse_string(JSON.stringify(saved))
	var restored = GridSystemScript.new()
	tree.root.add_child(restored)
	assertions.truthy(restored.from_dict(json_saved), "grid restores JSON numeric crop state")
	var restored_instance = restored.get_cell(4, 4).crop_instance
	assertions.truthy(restored_instance != null, "JSON crop instance restores")
	if restored_instance:
		assertions.equal(restored_instance.harvest_count, 1, "JSON integral float restores as harvest count")
		assertions.near(restored_instance.growth_progress, 2.0, 0.001, "JSON regrowth progress restores")

	var legacy: Dictionary = saved.duplicate(true)
	legacy.cells[0].crop.erase("harvest_count")
	var legacy_restored = GridSystemScript.new()
	tree.root.add_child(legacy_restored)
	assertions.truthy(legacy_restored.from_dict(legacy), "legacy crop save without harvest count restores")
	assertions.equal(legacy_restored.get_cell(4, 4).crop_instance.harvest_count, 0, "legacy crop save defaults harvest count safely")
	grid.free()
	restored.free()
	legacy_restored.free()


func _test_controller_harvest_is_atomic(assertions: TestAssert, tree: SceneTree) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "tomato"
	crop.growth_days = 4
	crop.yield_min = 3
	crop.yield_max = 3
	crop.regrow_days = 2
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	farming.configure(grid, null, null)
	grid.set_cell_state(1, 1, FARMLAND)
	var instance = farming.plant(grid.get_cell(1, 1), crop)
	instance.growth_progress = 4.0
	var inventory = InventorySystemScript.new()
	inventory.max_slots = 2
	inventory.reset_slots()
	inventory.slots[0] = {"item_id": "tomato", "quantity": 97}
	inventory.slots[1] = {"item_id": "grain", "quantity": 98}
	var controller = PlayerActionControllerScript.new()
	controller.configure(null, grid, farming, null, null, inventory)
	assertions.truthy(not controller._harvest(grid.get_cell(1, 1)), "full multi-quantity result blocks before harvest")
	assertions.equal(inventory.get_item_count("tomato"), 97, "capacity rejection preserves crop inventory")
	assertions.equal(inventory.get_item_count("grain"), 98, "capacity rejection preserves unrelated stack")
	assertions.truthy(grid.get_cell(1, 1).crop_instance == instance, "capacity rejection preserves mature crop")
	assertions.equal(instance.harvest_count, 0, "capacity rejection does not advance harvest counter")

	var failing_inventory = FailingAfterMutationInventory.new()
	failing_inventory.max_slots = 2
	failing_inventory.reset_slots()
	failing_inventory.slots[0] = {"item_id": "tomato", "quantity": 99}
	failing_inventory.slots[1] = {}
	failing_inventory.set_quick_slot(0, 5)
	var slots_before: Array[Dictionary] = failing_inventory.slots.duplicate(true)
	var mappings_before: Array[int] = failing_inventory.quick_slot_mappings.duplicate()
	tree.root.add_child(failing_inventory)
	var failing_controller = PlayerActionControllerScript.new()
	tree.root.add_child(failing_controller)
	failing_controller.configure(null, grid, farming, null, null, failing_inventory)
	var event_bus = tree.root.get_node("EventBus")
	event_bus.set_block_signals(false)
	var recorder := InventorySignalRecorder.new()
	event_bus.item_added.connect(recorder.on_added)
	event_bus.item_removed.connect(recorder.on_removed)
	assertions.truthy(not failing_controller._harvest(grid.get_cell(1, 1)), "injected add failure rejects harvest")
	assertions.equal(failing_inventory.slots, slots_before, "injected failure restores exact slot layout")
	assertions.equal(failing_inventory.quick_slot_mappings, mappings_before, "injected failure restores exact quick mappings")
	assertions.equal(failing_inventory.restore_calls, 1, "rollback uses InventorySystem restore_state")
	assertions.equal(recorder.events, [], "rolled-back harvest emits no partial inventory events")
	assertions.truthy(grid.get_cell(1, 1).crop_instance == instance, "injected add failure preserves crop")
	assertions.equal(instance.harvest_count, 0, "injected add failure preserves harvest counter")
	event_bus.item_added.disconnect(recorder.on_added)
	event_bus.item_removed.disconnect(recorder.on_removed)
	controller.free()
	failing_controller.free()
	inventory.free()
	failing_inventory.free()
	farming.free()
	grid.free()


func _test_roster_planting_uses_active_quick_item(assertions: TestAssert, tree: SceneTree) -> void:
	var game_data = tree.root.get_node("GameData")
	for crop in MainScript.default_crop_definitions():
		if game_data.get_crop(crop.crop_id) == null:
			game_data.register_crop(crop)
	var fixtures := [
		{"item": "grain_seed", "crop": "grain", "season": SeasonSystem.Season.SPRING},
		{"item": "carrot_seed", "crop": "carrot", "season": SeasonSystem.Season.SPRING},
		{"item": "tomato_seed", "crop": "tomato", "season": SeasonSystem.Season.SPRING},
		{"item": "rose_seed", "crop": "rose", "season": SeasonSystem.Season.SPRING},
		{"item": "apple_sapling", "crop": "apple", "season": SeasonSystem.Season.AUTUMN},
	]
	for fixture in fixtures:
		var grid = GridSystemScript.new()
		grid.set_cell_state(10, 10, FARMLAND)
		grid.set_cell_state(11, 10, FARMLAND)
		var season = SeasonSystem.new()
		season.current_season = int(fixture.season) as SeasonSystem.Season
		var farming = FarmingSystemScript.new()
		farming.configure(grid, season, null)
		var inventory = InventorySystemScript.new()
		inventory.add_item(str(fixture.item), 1)
		inventory.set_quick_slot(0, PlayerActionControllerScript.SEED_SLOT)
		var controller = PlayerActionControllerScript.new()
		tree.root.add_child(controller)
		controller.configure(null, grid, farming, null, null, inventory)
		controller.select_slot(PlayerActionControllerScript.SEED_SLOT)
		var planted := controller.perform_cell_action(grid.get_cell(10, 10))
		assertions.truthy(planted, "%s plants from active quick slot" % fixture.item)
		assertions.equal(inventory.get_item_count(str(fixture.item)), 0, "%s consumes exact active item" % fixture.item)
		if planted:
			assertions.equal(grid.get_cell(10, 10).crop_instance.crop_data.crop_id, fixture.crop, "%s plants mapped crop" % fixture.item)
		assertions.truthy(not controller.perform_cell_action(grid.get_cell(11, 10)), "missing selected %s rejects planting" % fixture.item)
		assertions.equal(grid.get_cell(11, 10).state, FARMLAND, "missing %s preserves farmland" % fixture.item)
		controller.free()
		inventory.free()
		farming.free()
		season.free()
		grid.free()

	var lemon_grid = GridSystemScript.new()
	lemon_grid.set_cell_state(12, 10, FARMLAND)
	lemon_grid.set_cell_state(13, 10, FARMLAND)
	var lemon_season = SeasonSystem.new()
	lemon_season.current_season = SeasonSystem.Season.SUMMER
	var lemon_farming = FarmingSystemScript.new()
	lemon_farming.configure(lemon_grid, lemon_season, null)
	lemon_farming.set_greenhouse_cells([Vector2i(13, 10)])
	var lemon_inventory = InventorySystemScript.new()
	lemon_inventory.add_item("lemon_sapling", 2)
	lemon_inventory.set_quick_slot(0, PlayerActionControllerScript.SEED_SLOT)
	var lemon_controller = PlayerActionControllerScript.new()
	tree.root.add_child(lemon_controller)
	lemon_controller.configure(null, lemon_grid, lemon_farming, null, null, lemon_inventory)
	lemon_controller.select_slot(PlayerActionControllerScript.SEED_SLOT)
	assertions.truthy(not lemon_controller.perform_cell_action(lemon_grid.get_cell(12, 10)), "selected lemon sapling rejects outdoor planting")
	assertions.equal(lemon_inventory.get_item_count("lemon_sapling"), 2, "outdoor rejection preserves lemon sapling")
	var lemon_planted := lemon_controller.perform_cell_action(lemon_grid.get_cell(13, 10))
	assertions.truthy(lemon_planted, "selected lemon sapling plants in greenhouse")
	assertions.equal(lemon_inventory.get_item_count("lemon_sapling"), 1, "greenhouse planting consumes lemon sapling")
	if lemon_planted:
		assertions.equal(lemon_grid.get_cell(13, 10).crop_instance.crop_data.crop_id, "lemon", "greenhouse sapling plants lemon crop")
	lemon_controller.free()
	lemon_inventory.free()
	lemon_farming.free()
	lemon_season.free()
	lemon_grid.free()


func _test_crop_data_validation(assertions: TestAssert) -> void:
	var crop = CropDataScript.new()
	assertions.equal(crop.yield_min, 1, "crop yield minimum defaults safely")
	assertions.equal(crop.yield_max, 1, "crop yield maximum defaults safely")
	assertions.equal(crop.regrow_days, 0, "crop regrowth defaults disabled")
	assertions.equal(crop.tags, [], "crop tags default empty")
	assertions.equal(crop.growth_form, "annual", "crop form defaults annual")
	assertions.truthy(crop.has_method("is_valid"), "CropData exposes strict validation")
	if not crop.has_method("is_valid"):
		return
	crop.crop_id = "invalid_range"
	crop.yield_min = 3
	crop.yield_max = 2
	assertions.truthy(not crop.is_valid(), "yield maximum cannot be below minimum")
	crop.yield_max = 3
	crop.growth_form = "tree"
	assertions.truthy(not crop.is_valid(), "persistent form requires authored regrowth")
	crop.regrow_days = 2
	assertions.truthy(crop.is_valid(), "well-formed persistent crop validates")
	crop.regrow_days = 4
	crop.growth_days = 3
	assertions.truthy(not crop.is_valid(), "regrowth cannot exceed the crop growth timeline")


func _test_default_roster_and_item_catalog(assertions: TestAssert) -> void:
	var expected := {
		"grain": {"days": 3, "yield": Vector2i(2, 4), "regrow": 0, "seasons": [0, 1, 2], "form": "annual", "tags": []},
		"carrot": {"days": 3, "yield": Vector2i(2, 3), "regrow": 0, "seasons": [0, 2], "form": "annual", "tags": []},
		"potato": {"days": 4, "yield": Vector2i(3, 5), "regrow": 0, "seasons": [0, 2], "form": "annual", "tags": []},
		"tomato": {"days": 4, "yield": Vector2i(2, 3), "regrow": 2, "seasons": [0, 1], "form": "annual", "tags": []},
		"strawberry": {"days": 4, "yield": Vector2i(2, 3), "regrow": 2, "seasons": [0], "form": "bush", "tags": []},
		"blueberry": {"days": 5, "yield": Vector2i(2, 3), "regrow": 2, "seasons": [1], "form": "bush", "tags": []},
		"watermelon": {"days": 5, "yield": Vector2i(1, 2), "regrow": 0, "seasons": [1], "form": "annual", "tags": []},
		"sunflower": {"days": 4, "yield": Vector2i(2, 3), "regrow": 0, "seasons": [1, 2], "form": "annual", "tags": ["flower"]},
		"lavender": {"days": 4, "yield": Vector2i(2, 3), "regrow": 0, "seasons": [1, 2], "form": "annual", "tags": ["flower"]},
		"pumpkin": {"days": 5, "yield": Vector2i(1, 2), "regrow": 0, "seasons": [2], "form": "annual", "tags": []},
		"rose": {"days": 4, "yield": Vector2i(2, 3), "regrow": 0, "seasons": [0, 1], "form": "annual", "tags": ["flower"]},
		"apple": {"days": 5, "yield": Vector2i(2, 4), "regrow": 3, "seasons": [2], "form": "tree", "tags": ["fruit"]},
		"peach": {"days": 5, "yield": Vector2i(2, 3), "regrow": 3, "seasons": [1], "form": "tree", "tags": ["fruit"]},
		"grape": {"days": 4, "yield": Vector2i(2, 4), "regrow": 2, "seasons": [1, 2], "form": "vine", "tags": ["fruit"]},
		"lemon": {"days": 5, "yield": Vector2i(2, 3), "regrow": 3, "seasons": [], "form": "tree", "tags": ["fruit", "greenhouse_only"]},
	}
	var main = MainScript.new()
	assertions.truthy(main.has_method("default_crop_definitions"), "Main exposes deterministic default crop roster")
	if main.has_method("default_crop_definitions"):
		var definitions: Array = main.call("default_crop_definitions")
		var by_id := {}
		for crop in definitions:
			by_id[crop.crop_id] = crop
		assertions.equal(by_id.size(), expected.size(), "default roster contains every crop exactly once")
		for crop_id in expected:
			assertions.truthy(by_id.has(crop_id), "%s is registered in default roster" % crop_id)
			if not by_id.has(crop_id):
				continue
			var crop = by_id[crop_id]
			var authored: Dictionary = expected[crop_id]
			assertions.equal(crop.growth_days, authored.days, "%s growth days match design" % crop_id)
			assertions.equal(Vector2i(crop.yield_min, crop.yield_max), authored.yield, "%s yield matches design" % crop_id)
			assertions.equal(crop.regrow_days, authored.regrow, "%s regrowth matches design" % crop_id)
			assertions.equal(crop.seasons, authored.seasons, "%s seasons match design" % crop_id)
			assertions.equal(crop.growth_form, authored.form, "%s growth form matches design" % crop_id)
			assertions.equal(crop.tags, authored.tags, "%s tags match design" % crop_id)
			assertions.truthy(crop.is_valid(), "%s default definition validates" % crop_id)
	main.free()

	var inventory_ids := [
		"grain_seed", "carrot_seed", "potato_seed", "tomato_seed", "strawberry_seed",
		"blueberry_seed", "watermelon_seed", "sunflower_seed", "lavender_seed",
		"pumpkin_seed", "rose_seed", "apple_sapling", "peach_sapling", "grape_seed",
		"lemon_sapling", "grain", "carrot", "potato", "tomato", "strawberry",
		"blueberry", "watermelon", "sunflower", "lavender", "pumpkin", "rose",
		"apple", "peach", "grape", "lemon",
	]
	for item_id in inventory_ids:
		assertions.truthy(GameDataScript.get_item(item_id) != null, "%s exists in production inventory catalog" % item_id)


func _test_perennial_harvest_and_greenhouse_rules(assertions: TestAssert) -> void:
	for crop_id in ["apple", "peach", "grape", "lemon"]:
		var crop = CropDataScript.new()
		crop.crop_id = crop_id
		crop.growth_days = 5
		crop.yield_min = 2
		crop.yield_max = 3
		crop.regrow_days = 3
		crop.growth_form = "vine" if crop_id == "grape" else "tree"
		var grid = GridSystemScript.new()
		grid.set_cell_state(5, 5, FARMLAND)
		var instance = grid.plant_crop(5, 5, crop)
		instance.growth_progress = 5.0
		var result := grid.harvest_crop(5, 5)
		assertions.truthy(bool(result.get("regrowing", false)), "%s harvest reports persistent regrowth" % crop_id)
		assertions.equal(grid.get_cell(5, 5).state, PLANTED, "%s remains planted after harvest" % crop_id)
		assertions.truthy(grid.get_cell(5, 5).crop_instance == instance, "%s preserves perennial instance" % crop_id)
		grid.free()

	var lemon = CropDataScript.new()
	lemon.crop_id = "lemon"
	lemon.growth_days = 5
	lemon.yield_min = 2
	lemon.yield_max = 3
	lemon.regrow_days = 3
	lemon.growth_form = "tree"
	lemon.tags.assign(["fruit", "greenhouse_only"])
	var grid = GridSystemScript.new()
	grid.set_cell_state(7, 7, FARMLAND)
	grid.set_cell_state(8, 8, FARMLAND)
	var farming = FarmingSystemScript.new()
	var season = SeasonSystem.new()
	season.current_season = SeasonSystem.Season.SUMMER
	farming.configure(grid, season, null)
	farming.set_greenhouse_cells([Vector2i(8, 8)])
	assertions.truthy(not farming.can_plant(grid.get_cell(7, 7), lemon), "greenhouse-only lemon rejects outdoor planting")
	assertions.truthy(farming.can_plant(grid.get_cell(8, 8), lemon), "greenhouse hook permits lemon planting")
	farming.free()
	season.free()
	grid.free()


func _test_regrowing_crop_visual_remains(assertions: TestAssert) -> void:
	var crop = CropDataScript.new()
	crop.crop_id = "visual_tomato"
	crop.growth_days = 4
	crop.yield_min = 2
	crop.yield_max = 3
	crop.regrow_days = 2
	crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
	var grid = GridSystemScript.new()
	var farming = FarmingSystemScript.new()
	farming.configure(grid, null, null)
	grid.set_cell_state(9, 9, FARMLAND)
	var cell = grid.get_cell(9, 9)
	var instance = farming.plant(cell, crop)
	instance.growth_progress = 4.0
	assertions.truthy(farming.get_crop_visual(cell) != null, "regrowth fixture starts with a crop visual")
	var result := farming.harvest(cell)
	assertions.truthy(bool(result.get("regrowing", false)), "visual fixture harvest regrows")
	assertions.truthy(farming.get_crop_visual(cell) != null, "regrowing crop visual remains after harvest")
	farming.free()
	grid.free()
