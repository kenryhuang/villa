extends RefCounted

const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const GeographicQueryServiceScript = preload(
	"res://scripts/systems/geographic_query_service.gd"
)
const BUILDING_SYSTEM_SCENE = preload("res://scenes/systems/building_system.tscn")
const BUILD_UI_SCENE = preload("res://scenes/ui/build_ui.tscn")

const ADVANCED_SCENE_IDS := [
	"stone_kiln",
	"furnace",
	"food_workshop",
	"textile_machine",
	"lumberyard",
	"quarry",
	"mine",
]

var _owned_nodes: Array[Node] = []


class EconomyDouble:
	extends RefCounted

	func has_resources(_cost: Dictionary) -> bool:
		return true

	func spend_resources(_cost: Dictionary) -> bool:
		return true


class WalletDouble:
	extends RefCounted
	var gold := 100

	func spend_gold(amount: int) -> bool:
		if amount <= 0 or gold < amount:
			return false
		gold -= amount
		return true


class FailingAddInventory:
	extends InventorySystem
	var add_calls := 0
	var fail_on_call := 2

	func add_item(item_id: String, quantity: int = 1) -> bool:
		add_calls += 1
		var result := super.add_item(item_id, quantity)
		return false if add_calls == fail_on_call else result


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_owned_nodes.clear()
	_test_passive_output_helper(assertions)
	_test_daily_cursor_can_rewind_for_loaded_day(assertions)
	_test_loaded_maintenance_refreshes_greenhouse_on_cursor_sync(assertions)
	_test_beehive_flowers_and_storage_pause(assertions)
	_test_beehive_flower_ownership(assertions)
	_test_coop_feed_is_atomic(assertions)
	_test_waterwheel_geometry_and_daily_order(assertions)
	_test_maintenance_disables_and_restores_daily_coverage(assertions)
	_test_waterwheel_placement_rule(assertions, tree)
	_test_shared_geographic_authority(assertions, tree)
	_test_greenhouse_mapping_and_season_protection(assertions)
	_test_authoritative_greenhouse_crop_and_wheel_scope(assertions)
	_test_barn_collection_is_atomic(assertions)
	_test_barn_grouped_selective_collection(assertions)
	_test_deterministic_resource_outputs(assertions)
	_test_building_definitions_scenes_and_build_ui(assertions, tree)
	_test_main_production_integration(assertions, tree)
	_cleanup_nodes()


func _test_passive_output_helper(assertions: TestAssert) -> void:
	var production := _production()
	assertions.equal(production.passive_output_for("beehive", 1, 4, 2), {}, "beehive rests on odd days")
	assertions.equal(production.passive_output_for("beehive", 2, 0, 0), {}, "beehive stops without mature flowers")
	assertions.equal(production.passive_output_for("beehive", 2, 1, 1), {"honey": 1}, "one flower makes one honey")
	assertions.equal(production.passive_output_for("beehive", 2, 3, 2), {"honey": 2}, "two to three flowers make two honey")
	assertions.equal(production.passive_output_for("beehive", 2, 4, 1), {"honey": 2}, "one flower species cannot make wax")
	assertions.equal(production.passive_output_for("beehive", 2, 4, 2), {"honey": 2, "beeswax": 1}, "four flowers from two species make wax")
	assertions.equal(production.passive_output_for("chicken_coop", 3, 0), {"egg": 2}, "coop helper returns approved daily egg output")
	assertions.equal(production.passive_output_for("well", 2, 0), {}, "manual well has no passive output")


func _test_daily_cursor_can_rewind_for_loaded_day(assertions: TestAssert) -> void:
	var production := _production()
	var coop := _building("chicken_coop", 4, 4, true)
	coop.producer_state.inputs = {"animal_feed": 2}
	production.register_building(coop)
	assertions.truthy(production.sync_daily_cursor(10), "daily cursor accepts a later runtime day")
	assertions.truthy(production.sync_daily_cursor(3), "daily cursor accepts an earlier loaded day")
	assertions.equal(production._last_daily_effects_day, 3, "loaded day rewinds the daily effect cursor exactly")
	assertions.equal(production._last_finished_outputs_day, 3, "loaded day rewinds the output cursor exactly")
	assertions.truthy(not production.sync_daily_cursor(-1), "daily cursor rejects a negative loaded day")
	assertions.equal(production._last_daily_effects_day, 3, "rejected day preserves the daily effect cursor")
	assertions.equal(production._last_finished_outputs_day, 3, "rejected day preserves the output cursor")
	production.finish_daily_outputs(4)
	assertions.equal(coop.producer_state.outputs, {"egg": 2}, "the day after an earlier load produces once")
	assertions.equal(coop.producer_state.inputs, {"animal_feed": 1}, "the day after an earlier load consumes one feed")
	production.finish_daily_outputs(4)
	assertions.equal(coop.producer_state.outputs, {"egg": 2}, "repeating the post-load day does not produce twice")
	assertions.equal(coop.producer_state.inputs, {"animal_feed": 1}, "repeating the post-load day does not consume twice")


func _test_loaded_maintenance_refreshes_greenhouse_on_cursor_sync(assertions: TestAssert) -> void:
	var grid := _grid()
	var farming := _farming(grid)
	var production := _production(grid, farming)
	var greenhouse := _building("greenhouse", 18, 18, false)
	var key := ProductionSystemScript.building_key(greenhouse)
	assertions.truthy(production.sync_daily_cursor(1), "load fixture starts from old runtime day")
	assertions.truthy(production.from_dict({
		"version": 1,
		"maintenance": [{"building_key": key, "due_day": 5}],
		"speed_accumulators": [],
	}), "load fixture restores overdue maintenance before building registration")
	assertions.truthy(production.register_building(greenhouse), "load fixture registers restored greenhouse")
	var greenhouse_cell := production.get_greenhouse_cells(greenhouse)[0]
	assertions.truthy(farming.is_greenhouse_cell(grid.get_cell(greenhouse_cell.x, greenhouse_cell.y)), "old runtime day initially exposes restored greenhouse coverage")
	assertions.truthy(production.sync_daily_cursor(10), "load fixture synchronizes authoritative loaded day")
	assertions.truthy(not farming.is_greenhouse_cell(grid.get_cell(greenhouse_cell.x, greenhouse_cell.y)), "loaded overdue greenhouse coverage is removed immediately on cursor sync")
	assertions.truthy(production.sync_daily_cursor(10), "repeated loaded-day sync is safe")
	var inventory := _inventory()
	inventory.add_item("wood", 1)
	inventory.add_item("stone", 1)
	assertions.truthy(production.maintain(greenhouse, WalletDouble.new(), inventory), "loaded overdue greenhouse can be maintained")
	production.advance_repair_time(ProductionSystemScript.REPAIR_DURATION_SECONDS)
	assertions.truthy(farming.is_greenhouse_cell(grid.get_cell(greenhouse_cell.x, greenhouse_cell.y)), "maintenance restores loaded greenhouse coverage")


func _test_beehive_flowers_and_storage_pause(assertions: TestAssert) -> void:
	var grid := _grid()
	var farming := _farming(grid)
	var production := _production(grid, farming)
	var hive := _building("beehive", 10, 10, true)
	for position in [Vector2i(14, 10), Vector2i(13, 12), Vector2i(11, 7), Vector2i(7, 8), Vector2i(13, 13)]:
		_add_mature_flower(grid, position)
	production.register_building(hive)
	assertions.equal(production.count_nearby_mature_flowers(hive), 4, "hive counts Euclidean-radius mature flowers and caps at four")
	production.finish_daily_outputs(2)
	assertions.equal(hive.producer_state.outputs, {"honey": 2, "beeswax": 1}, "boosted hive output is stored")
	production.finish_daily_outputs(2)
	assertions.equal(hive.producer_state.outputs, {"honey": 2, "beeswax": 1}, "same-day hive settlement is idempotent")

	var blocked := _building("beehive", 20, 20, true)
	blocked.producer_state.outputs = {"honey": 1, "wood": 1, "stone": 1}
	_add_mature_flower(grid, Vector2i(21, 17))
	_add_mature_flower(grid, Vector2i(21, 18))
	_add_mature_flower(grid, Vector2i(21, 19))
	_add_mature_flower(grid, Vector2i(21, 20))
	production.register_building(blocked)
	production.finish_daily_outputs(4)
	assertions.equal(blocked.producer_state.outputs, {"honey": 1, "wood": 1, "stone": 1}, "full hive storage pauses the complete output without loss")


func _test_beehive_flower_ownership(assertions: TestAssert) -> void:
	var grid := _grid()
	var production := _production(grid, _farming(grid))
	var far_hive := _building("beehive", 8, 10, true)
	var nearest_hive := _building("beehive", 11, 10, true)
	var second_hive := _building("beehive", 14, 10, true)
	_add_mature_flower(grid, Vector2i(12, 10), "rose")
	for hive in [far_hive, nearest_hive, second_hive]:
		production.register_building(hive)
	production.finish_daily_outputs(2)
	assertions.equal(nearest_hive.producer_state.outputs, {"honey": 1}, "nearest hive owns the shared flower")
	assertions.equal(second_hive.producer_state.outputs, {"honey": 1}, "second-nearest hive also owns the shared flower")
	assertions.equal(far_hive.producer_state.outputs, {}, "one flower never feeds a third hive")


func _test_coop_feed_is_atomic(assertions: TestAssert) -> void:
	var production := _production()
	var fed := _building("chicken_coop", 4, 4, true)
	fed.producer_state.inputs = {"animal_feed": 2}
	var hungry := _building("chicken_coop", 8, 4, true)
	production.register_building(fed)
	production.register_building(hungry)
	production.finish_daily_outputs(3)
	assertions.equal(fed.producer_state.get_input_count("animal_feed"), 1, "fed coop consumes exactly one feed")
	assertions.equal(fed.producer_state.outputs, {"egg": 2}, "fed coop stores two eggs")
	assertions.equal(hungry.producer_state.inputs, {}, "hungry coop does not mutate inputs")
	assertions.equal(hungry.producer_state.outputs, {}, "hungry coop produces nothing")

	var blocked := _building("chicken_coop", 12, 4, true)
	blocked.producer_state.inputs = {"animal_feed": 1}
	blocked.producer_state.outputs = {"honey": 1, "wood": 1, "stone": 1}
	production.register_building(blocked)
	production.finish_daily_outputs(4)
	assertions.equal(blocked.producer_state.inputs, {"animal_feed": 1}, "full coop storage pauses before feeding")
	assertions.equal(blocked.producer_state.outputs, {"honey": 1, "wood": 1, "stone": 1}, "full coop storage preserves existing output")
	production.finish_daily_outputs(4)
	assertions.equal(blocked.producer_state.inputs, {"animal_feed": 1}, "repeat settlement cannot consume paused feed")

	var natural_full_production := _production()
	var naturally_full := _building("chicken_coop", 16, 4, true)
	naturally_full.producer_state.inputs = {"animal_feed": 4}
	natural_full_production.register_building(naturally_full)
	for day in [1, 2, 3]:
		natural_full_production.finish_daily_outputs(day)
	assertions.equal(naturally_full.producer_state.outputs, {"egg": 6}, "coop stores its configured three-day output buffer")
	assertions.equal(naturally_full.producer_state.inputs, {"animal_feed": 1}, "three stored coop days consume three feed")
	natural_full_production.finish_daily_outputs(4)
	assertions.equal(naturally_full.producer_state.outputs, {"egg": 6}, "naturally full coop pauses output")
	assertions.equal(naturally_full.producer_state.inputs, {"animal_feed": 1}, "naturally full coop pauses before feeding")


func _test_waterwheel_geometry_and_daily_order(assertions: TestAssert) -> void:
	var grid := _grid()
	var farming := _farming(grid)
	var production := _production(grid, farming)
	var wheel := _building("waterwheel", 10, 10, false)
	grid.get_cell(9, 10).state = GridCell.State.WATER
	var near := grid.get_cell(14, 10)
	near.state = GridCell.State.FARMLAND
	var crop_data := CropData.new()
	crop_data.crop_id = "test_crop"
	crop_data.growth_days = 3
	crop_data.growth_duration_minutes = 3
	crop_data.seasons.assign([SeasonSystem.Season.SPRING])
	crop_data.stage_textures.assign(["seed", "mature"])
	near.crop_instance = CropInstance.new()
	near.crop_instance.crop_data = crop_data
	near.state = GridCell.State.PLANTED
	var distant := grid.get_cell(15, 10)
	distant.state = GridCell.State.FARMLAND
	production.register_building(wheel)
	assertions.truthy(production.is_water_connected(wheel), "waterwheel detects an orthogonally bordering water cell")
	var irrigated: Array = production.get_irrigated_cells(wheel)
	assertions.truthy(irrigated.has(Vector2i(14, 10)), "Euclidean radius four includes near valid farm cell")
	assertions.truthy(not irrigated.has(Vector2i(15, 10)), "Euclidean radius four excludes distant farm cell")
	production.apply_daily_effects(2)
	assertions.truthy(near.watered and near.crop_instance.is_watered_today, "waterwheel waters planted cells before growth")
	assertions.truthy(not distant.watered, "waterwheel leaves distant cells dry")
	farming.advance_growth_minutes(1)
	assertions.near(near.crop_instance.growth_progress, 1.5, 0.001, "waterwheel irrigation affects same-day crop growth")
	farming.on_day_changed(2)
	production.apply_daily_effects(2)
	assertions.truthy(not near.watered, "same-day effect replay is idempotent after farming clears water")
	var well := _building("well", 3, 3, false)
	production.register_building(well)
	assertions.equal(production.get_irrigated_cells(well), [], "well remains a manual water source")


func _test_maintenance_disables_and_restores_daily_coverage(assertions: TestAssert) -> void:
	var grid := _grid()
	var farming := _farming(grid)
	var production := _production(grid, farming)
	var wheel := _building("waterwheel", 10, 10, false)
	var greenhouse := _building("greenhouse", 20, 20, false)
	grid.get_cell(9, 10).state = GridCell.State.WATER
	var irrigated := grid.get_cell(14, 10)
	irrigated.state = GridCell.State.FARMLAND
	production.register_building(wheel)
	production.register_building(greenhouse)
	assertions.truthy(production.set_maintenance_due_day(wheel, 2), "wheel maintenance fixture sets due day")
	assertions.truthy(production.set_maintenance_due_day(greenhouse, 2), "greenhouse maintenance fixture sets due day")
	production.apply_daily_effects(1)
	assertions.truthy(irrigated.watered, "waterwheel coverage remains active before due day")
	var greenhouse_cell := production.get_greenhouse_cells(greenhouse)[0]
	assertions.truthy(farming.is_greenhouse_cell(grid.get_cell(greenhouse_cell.x, greenhouse_cell.y)), "greenhouse coverage remains active before due day")
	farming.on_day_changed(1)
	irrigated.watered = false
	production.apply_daily_effects(2)
	assertions.truthy(not irrigated.watered, "waterwheel coverage stops on maintenance due day")
	assertions.truthy(not farming.is_greenhouse_cell(grid.get_cell(greenhouse_cell.x, greenhouse_cell.y)), "greenhouse season coverage stops on maintenance due day")
	var inventory := _inventory()
	inventory.add_item("wood", 2)
	inventory.add_item("stone", 2)
	var wallet := WalletDouble.new()
	assertions.truthy(production.maintain(wheel, wallet, inventory), "overdue waterwheel maintenance succeeds")
	assertions.truthy(production.maintain(greenhouse, wallet, inventory), "overdue greenhouse maintenance succeeds")
	production.advance_repair_time(ProductionSystemScript.REPAIR_DURATION_SECONDS)
	assertions.truthy(farming.is_greenhouse_cell(grid.get_cell(greenhouse_cell.x, greenhouse_cell.y)), "maintenance immediately restores greenhouse coverage")
	production.apply_daily_effects(3)
	assertions.truthy(irrigated.watered, "maintenance restores waterwheel coverage next day")


func _test_waterwheel_placement_rule(assertions: TestAssert, tree: SceneTree) -> void:
	var grid := _grid()
	var building_system := _track(BUILDING_SYSTEM_SCENE.instantiate()) as BuildingSystem
	tree.root.add_child(building_system)
	assertions.truthy(building_system.configure(grid, EconomyDouble.new()), "waterwheel placement fixture configures")
	assertions.truthy(not building_system.can_place("waterwheel", 10, 10), "waterwheel placement rejects land without bordering water")
	grid.get_cell(9, 10).state = GridCell.State.WATER
	assertions.truthy(building_system.can_place("waterwheel", 10, 10), "waterwheel placement accepts orthogonally bordering water")
	var placed := building_system.place_building_by_id("waterwheel", 10, 10)
	assertions.truthy(placed != null, "waterwheel procedural fallback can be instantiated")
	if placed != null:
		var saved := placed.to_dict()
		building_system.remove_building(placed)
		grid.get_cell(9, 10).state = GridCell.State.WASTELAND
		assertions.equal(building_system.restore_buildings([saved]), 0, "waterwheel restore rejects a location that no longer borders water")
	assertions.truthy(not building_system.can_place("waterwheel", 0, 0), "waterwheel footprint at map edge still needs a valid border")


func _test_shared_geographic_authority(assertions: TestAssert, tree: SceneTree) -> void:
	var grid := _grid()
	var farming := _farming(grid)
	var geography := GeographicQueryServiceScript.new()
	assertions.truthy(geography.configure(grid), "shared geography fixture configures")
	var building_system := _track(BUILDING_SYSTEM_SCENE.instantiate()) as BuildingSystem
	tree.root.add_child(building_system)
	assertions.truthy(
		building_system.configure(grid, EconomyDouble.new()),
		"shared placement fixture configures"
	)
	var production := _production(grid, farming)
	assertions.truthy(
		building_system.set_geographic_query_service(geography),
		"placement accepts shared geography"
	)
	assertions.truthy(
		production.set_geographic_query_service(geography),
		"production accepts shared geography"
	)
	assertions.truthy(
		building_system.get_geographic_query_service() == geography,
		"placement retains shared geography identity"
	)
	assertions.truthy(
		production.get_geographic_query_service() == geography,
		"production retains shared geography identity"
	)
	grid.get_cell(9, 9).state = GridCell.State.WATER
	assertions.equal(
		building_system.diagnose_placement("waterwheel", 10, 10).code,
		"water_required",
		"shared shoreline authority rejects diagonal water"
	)
	grid.get_cell(9, 10).state = GridCell.State.WATER
	var diagnostic := building_system.diagnose_placement("waterwheel", 10, 10)
	assertions.truthy(bool(diagnostic.allowed), "shared shoreline authority accepts edge water")
	assertions.equal(
		diagnostic.get("water_anchor", Vector2i(-1, -1)),
		Vector2i(9, 10),
		"successful waterwheel diagnostic exposes stable water anchor"
	)
	var wheel := _building("waterwheel", 10, 10, false)
	assertions.truthy(production.is_water_connected(wheel), "production consumes shared shoreline result")


func _test_greenhouse_mapping_and_season_protection(assertions: TestAssert) -> void:
	var grid := _grid()
	var season := _track(SeasonSystem.new()) as SeasonSystem
	season.current_season = SeasonSystem.Season.WINTER
	var farming := _track(FarmingSystemScript.new()) as FarmingSystem
	farming.configure(grid, season, null)
	var production := _production(grid, farming)
	var greenhouse := _building("greenhouse", 10, 10, false)
	var wheel := _building("waterwheel", 6, 10, false)
	grid.get_cell(5, 10).state = GridCell.State.WATER
	production.register_building(greenhouse)
	production.register_building(wheel)
	var mapped: Array = production.get_greenhouse_cells(greenhouse)
	assertions.equal(mapped.size(), 8, "greenhouse exposes exactly eight deterministic planting cells")
	var unique := {}
	for position in mapped:
		unique[position] = true
	assertions.equal(unique.size(), 8, "greenhouse planting cell mapping has no duplicates")
	assertions.equal(mapped, production.get_greenhouse_cells(greenhouse), "greenhouse mapping derives deterministically from coordinates")
	var protected_cell := grid.get_cell(mapped[0].x, mapped[0].y)
	protected_cell.state = GridCell.State.FARMLAND
	var summer_crop := CropData.new()
	summer_crop.crop_id = "summer_only"
	summer_crop.growth_days = 2
	summer_crop.seasons.assign([SeasonSystem.Season.SUMMER])
	assertions.truthy(farming.can_plant(protected_cell, summer_crop), "greenhouse mapped cells ignore crop seasons")
	var outdoor := grid.get_cell(20, 20)
	outdoor.state = GridCell.State.FARMLAND
	assertions.truthy(not farming.can_plant(outdoor, summer_crop), "outdoor cells still enforce crop seasons")
	assertions.truthy(production.is_greenhouse_water_connected(greenhouse), "greenhouse reports connection when a waterwheel covers a mapped cell")

	var building_system := _track(BUILDING_SYSTEM_SCENE.instantiate()) as BuildingSystem
	building_system.configure(grid, EconomyDouble.new())
	var construction_production := _production()
	construction_production.configure(grid, farming, building_system, null)
	var constructing := building_system.place_building_by_id("greenhouse", 20, 10)
	assertions.truthy(constructing != null, "greenhouse construction fixture is placed")
	if constructing != null:
		var construction_cell := grid.get_cell(20, 9)
		construction_cell.state = GridCell.State.FARMLAND
		assertions.truthy(not farming.can_plant(construction_cell, summer_crop), "unfinished greenhouse does not grant season protection")
		constructing.complete_construction()
		assertions.truthy(farming.can_plant(construction_cell, summer_crop), "greenhouse grants season protection immediately on completion")


func _test_authoritative_greenhouse_crop_and_wheel_scope(assertions: TestAssert) -> void:
	var grid := _grid()
	var farming := _farming(grid)
	var production := _production(grid, farming)
	var greenhouse_a := _building("greenhouse", 10, 10, false)
	var greenhouse_b := _building("greenhouse", 26, 20, false)
	var wheel_a := _building("waterwheel", 6, 10, false)
	var wheel_b := _building("waterwheel", 22, 20, false)
	grid.get_cell(5, 10).state = GridCell.State.WATER
	grid.get_cell(21, 20).state = GridCell.State.WATER
	for building in [greenhouse_a, greenhouse_b, wheel_a, wheel_b]:
		production.register_building(building)
	var crop := CropData.new()
	crop.crop_id = "tomato"
	crop.growth_days = 4
	var instance := CropInstance.new()
	instance.crop_data = crop
	instance.growth_progress = 1.5
	var planted := production.get_greenhouse_cells(greenhouse_a)[0]
	grid.get_cell(planted.x, planted.y).state = GridCell.State.PLANTED
	grid.get_cell(planted.x, planted.y).crop_instance = instance

	var has_crop_query := production.has_method("get_greenhouse_crop_maturity")
	assertions.truthy(has_crop_query, "ProductionSystem owns the greenhouse crop maturity query")
	if has_crop_query:
		var crops: Array = production.call("get_greenhouse_crop_maturity", greenhouse_a)
		assertions.equal(crops.size(), 1, "greenhouse query returns only seeded crops in that greenhouse")
		if not crops.is_empty():
			assertions.equal(crops[0].get("crop_id"), "tomato", "crop maturity snapshot exposes crop id")
			assertions.equal(crops[0].get("remaining_days"), 2, "connected waterwheel projects the same 1.5 daily growth used by day simulation")
			assertions.equal(crops[0].get("maturity_day"), production.get_current_day() + 2, "connected crop maturity exposes the accelerated calendar day")
	var has_wheel_query := production.has_method("get_covered_greenhouses")
	var has_covered_cells := production.has_method("get_waterwheel_covered_cells")
	assertions.truthy(has_wheel_query and has_covered_cells, "ProductionSystem owns per-waterwheel covered cells and greenhouse intersection")
	if has_wheel_query:
		assertions.truthy(planted in production.call("get_waterwheel_covered_cells", wheel_a), "waterwheel authoritative cells include the intersected greenhouse cell")
		assertions.equal(production.call("get_covered_greenhouses", wheel_a), [ProductionSystemScript.building_key(greenhouse_a)], "first wheel reports only its nearby greenhouse")
		assertions.equal(production.call("get_covered_greenhouses", wheel_b), [ProductionSystemScript.building_key(greenhouse_b)], "far second wheel cannot leak into first wheel coverage")
	grid.get_cell(5, 10).state = GridCell.State.WASTELAND
	var disconnected: Array = production.call("get_greenhouse_crop_maturity", greenhouse_a)
	assertions.equal(disconnected[0].get("remaining_days"), 3, "water-disconnected wheel falls back to one growth point per day")
	instance.is_watered_today = true
	var hand_watered: Array = production.call("get_greenhouse_crop_maturity", greenhouse_a)
	assertions.equal(hand_watered[0].get("remaining_days"), 2, "hand-watered crop uses 1.5 growth on its known next advance without a wheel")
	grid.get_cell(5, 10).state = GridCell.State.WATER
	var hand_watered_with_wheel: Array = production.call("get_greenhouse_crop_maturity", greenhouse_a)
	assertions.equal(hand_watered_with_wheel[0].get("remaining_days"), 2, "hand watering and wheel coverage do not double the next growth advance")
	crop.growth_days = 6
	production.set_maintenance_due_day(wheel_a, production.get_current_day())
	var maintenance_paused: Array = production.call("get_greenhouse_crop_maturity", greenhouse_a)
	assertions.equal(maintenance_paused[0].get("remaining_days"), 4, "maintenance-paused wheel preserves the known hand-watered first day but does not accelerate later days")


func _test_barn_collection_is_atomic(assertions: TestAssert) -> void:
	var barn_definition: Dictionary = GameDataScript.get_building("barn")
	assertions.equal(
		barn_definition.get("effect"),
		"farm_storage",
		"barn uses central farm storage semantics"
	)
	assertions.equal(barn_definition.get("effect_value"), 200, "completed barn contributes 200 capacity")
	assertions.equal(
		barn_definition.get("description"),
		"中央仓库容量 +200；可收集半径内建筑产物",
		"barn description distinguishes central storage from nearby collection"
	)
	var collection_config: Variant = (barn_definition.get("effect_config", {}) as Dictionary).get(
		"nearby_output_collection"
	)
	assertions.truthy(collection_config is Dictionary, "barn collection uses an explicit config key")
	if collection_config is Dictionary:
		assertions.equal(collection_config.get("radius"), 6, "explicit barn collection keeps radius six")
	assertions.truthy(
		not (barn_definition.get("effect_config", {}) as Dictionary).has("collection_radius"),
		"barn collection no longer overloads the storage effect config"
	)
	var production := _production()
	var barn := _building("barn", 10, 10, false)
	var hive := _building("beehive", 14, 10, true)
	var coop := _building("chicken_coop", 10, 15, true)
	var far := _building("lumberyard", 25, 25, true)
	hive.producer_state.outputs = {"honey": 2}
	coop.producer_state.outputs = {"egg": 2}
	far.producer_state.outputs = {"wood": 3}
	for building in [barn, hive, coop, far]:
		production.register_building(building)
	var one_slot := _inventory(1)
	assertions.truthy(not production.collect_nearby_outputs(barn, one_slot), "barn preflights the combined player destination")
	assertions.equal(one_slot.get_slot_count(), 0, "failed barn preflight moves no output")
	assertions.equal(hive.producer_state.outputs, {"honey": 2}, "failed barn preflight preserves first producer")
	assertions.equal(coop.producer_state.outputs, {"egg": 2}, "failed barn preflight preserves second producer")
	var inventory := _inventory(2)
	assertions.truthy(production.collect_nearby_outputs(barn, inventory), "barn collects all nearby producer output")
	assertions.equal(inventory.get_item_count("honey"), 2, "barn transfers honey")
	assertions.equal(inventory.get_item_count("egg"), 2, "barn transfers eggs")
	assertions.equal(hive.producer_state.outputs, {}, "successful barn collection clears hive")
	assertions.equal(coop.producer_state.outputs, {}, "successful barn collection clears coop")
	assertions.equal(far.producer_state.outputs, {"wood": 3}, "barn does not collect distant output")

	var rollback_hive := _building("beehive", 11, 8, true)
	rollback_hive.producer_state.outputs = {"honey": 1, "beeswax": 1}
	production.register_building(rollback_hive)
	var failing := _track(FailingAddInventory.new()) as FailingAddInventory
	assertions.truthy(not production.collect_nearby_outputs(barn, failing), "barn reports destination mutation failure")
	assertions.equal(failing.get_slot_count(), 0, "barn rolls back partially added inventory")
	assertions.equal(rollback_hive.producer_state.outputs, {"honey": 1, "beeswax": 1}, "barn rollback preserves producer outputs")


func _test_barn_grouped_selective_collection(assertions: TestAssert) -> void:
	var production := _production()
	var barn := _building("barn", 10, 10, false)
	var hive := _building("beehive", 11, 10, true)
	var coop := _building("chicken_coop", 12, 10, true)
	hive.producer_state.outputs = {"honey": 2, "beeswax": 1}
	coop.producer_state.outputs = {"egg": 2}
	for building in [barn, hive, coop]:
		production.register_building(building)
	var has_group_query := production.has_method("get_nearby_output_groups")
	var has_preflight := production.has_method("preflight_barn_collection")
	var has_collect := production.has_method("collect_barn_outputs")
	assertions.truthy(has_group_query and has_preflight and has_collect, "barn exposes authoritative grouped preflight and collection APIs")
	if not has_group_query or not has_preflight or not has_collect:
		return
	var hive_key := ProductionSystemScript.building_key(hive)
	var groups: Dictionary = production.call("get_nearby_output_groups", barn)
	assertions.equal((groups[hive_key] as Dictionary).get("outputs"), {"honey": 2, "beeswax": 1}, "group snapshot is keyed by stable source key")
	(groups[hive_key].outputs as Dictionary).honey = 99
	assertions.equal(hive.producer_state.outputs.honey, 2, "mutating grouped snapshot cannot mutate producer state")
	var inventory := _inventory(3)
	var result: Dictionary = production.call("collect_barn_outputs", barn, inventory, hive_key, "honey")
	assertions.truthy(result.get("ok", false), "barn selectively collects one item from one source")
	assertions.equal(inventory.get_item_count("honey"), 2, "selected barn item reaches inventory")
	assertions.equal(hive.producer_state.outputs, {"beeswax": 1}, "selected source keeps its other output")
	assertions.equal(coop.producer_state.outputs, {"egg": 2}, "unselected source remains unchanged")

	var full := _inventory(1)
	full.add_item("grain", 99)
	var before_slots := full.slots.duplicate(true)
	var before_outputs := coop.producer_state.outputs.duplicate(true)
	var failed: Dictionary = production.call("collect_barn_outputs", barn, full, ProductionSystemScript.building_key(coop), "egg")
	assertions.equal(failed.get("reason"), "inventory_capacity", "selective barn failure returns structured capacity reason")
	assertions.equal(failed.get("missing_quantity"), 2, "selective barn failure returns exact missing quantity")
	assertions.equal(full.slots, before_slots, "failed selective barn collection leaves inventory unchanged")
	assertions.equal(coop.producer_state.outputs, before_outputs, "failed selective barn collection leaves source unchanged")


func _test_deterministic_resource_outputs(assertions: TestAssert) -> void:
	var production := _production()
	var lumberyard := _building("lumberyard", 2, 2, true)
	var quarry := _building("quarry", 6, 2, true)
	var mine := _building("mine", 10, 2, true)
	mine.data.effect_config.depth_tier = "deep"
	for building in [lumberyard, quarry, mine]:
		production.register_building(building)
	production.finish_daily_outputs(3)
	var lumber_config: Dictionary = lumberyard.data.effect_config
	var quarry_config: Dictionary = quarry.data.effect_config
	var mine_config: Dictionary = mine.data.effect_config
	assertions.equal(lumberyard.producer_state.outputs, lumber_config.daily_output, "lumberyard daily output comes from its data table")
	var expected_quarry: Dictionary = quarry_config.daily_output.duplicate(true)
	if 3 % int(quarry_config.bonus_every_days) == 0:
		_merge_counts(expected_quarry, quarry_config.bonus_output)
	assertions.equal(quarry.producer_state.outputs, expected_quarry, "quarry occasional coal is deterministic from day and config")
	var expected_mine: Dictionary = mine_config.depth_outputs.deep.duplicate(true)
	if 3 % int(mine_config.deep_bonus_every_days) == 0:
		_merge_counts(expected_mine, mine_config.deep_bonus_output)
	assertions.equal(mine.producer_state.outputs, expected_mine, "mine depth-tier ore is deterministic from day and config")
	var first_result := mine.producer_state.outputs.duplicate(true)
	production.finish_daily_outputs(3)
	assertions.equal(mine.producer_state.outputs, first_result, "resource outputs cannot settle twice on one day")


func _test_building_definitions_scenes_and_build_ui(assertions: TestAssert, tree: SceneTree) -> void:
	var game_data := _track(GameDataScript.new())
	var required_ids := ADVANCED_SCENE_IDS + ["waterwheel"]
	for id in required_ids:
		var source: Dictionary = game_data.get_building(id)
		var data := BuildingDataScript.from_dictionary(source)
		assertions.truthy(not source.is_empty(), "%s has a GameData definition" % id)
		assertions.truthy(data.is_valid(), "%s resolves to valid BuildingData" % id)
		assertions.equal(data.effect_type, str(source.effect), "%s effect agrees across data layers" % id)
		assertions.equal(data.station_id, str(source.get("station", "")), "%s station agrees across data layers" % id)
		assertions.equal(data.effect_config, source.get("effect_config", {}), "%s effect config agrees across data layers" % id)
	assertions.equal(game_data.get_building("waterwheel").footprint_x, 2, "waterwheel width is two cells")
	assertions.equal(game_data.get_building("waterwheel").footprint_z, 2, "waterwheel depth is two cells")
	assertions.equal(game_data.get_building("waterwheel").effect, "irrigation", "waterwheel has irrigation effect")
	for id in ADVANCED_SCENE_IDS:
		var path: String = BuildingDataScript.SCENE_PATHS[id]
		var packed := load(path) as PackedScene
		assertions.truthy(packed != null, "%s scene loads" % id)
		if packed != null:
			var instance := packed.instantiate() as BuildingInstance
			assertions.truthy(instance != null, "%s scene root uses BuildingInstance" % id)
			if instance != null:
				assertions.equal(instance.authored_building_id, id, "%s scene authors the matching building id" % id)
				tree.root.add_child(instance)
				assertions.equal(instance.building_id, id, "%s scene resolves its authored definition" % id)
				var back := instance.get_node("VisualRoot/BackLayer") as Sprite3D
				var front := instance.get_node("VisualRoot/FrontLayer") as Sprite3D
				assertions.truthy(
					back.texture != null and back.visible,
					"%s scene shows its painted back layer" % id
				)
				assertions.truthy(
					front.texture != null and front.visible,
					"%s scene shows its painted front layer" % id
				)
				assertions.truthy(
					not instance.get_node("VisualRoot/FallbackBody").visible
					and not instance.get_node("VisualRoot/FallbackRoof").visible,
					"%s scene hides its procedural fallback when painted art exists" % id
				)
				instance.free()
	var build_ui := _track(BUILD_UI_SCENE.instantiate()) as BuildUI
	tree.root.add_child(build_ui)
	build_ui.open()
	assertions.equal(build_ui.grid_container.get_child_count(), game_data.get_all_buildings().size(), "scrollable BuildUI enumerates every GameData building")
	var visible_names := []
	for card in build_ui.grid_container.get_children():
		var box := card.get_child(0)
		if box != null and box.get_child_count() > 0:
			visible_names.append((box.get_child(0) as Label).text)
	for id in required_ids:
		assertions.truthy(visible_names.has(game_data.get_building(id).name), "BuildUI exposes advanced building %s" % id)
	assertions.equal(VillaHud.BUILDING_NAMES.size(), 9, "nine-slot action palette remains unchanged")


func _test_main_production_integration(assertions: TestAssert, tree: SceneTree) -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := _track(main_scene.instantiate())
	main.load_save_on_start = false
	tree.root.add_child(main)
	assertions.truthy(main.production_system is ProductionSystem, "Main instantiates ProductionSystem")
	assertions.equal(main.daily_simulation_system._production_system, main.production_system, "Main injects production into DailySimulationSystem")
	assertions.equal(main.production_system._grid_system, main.grid_system, "Main injects grid into production")
	assertions.equal(main.production_system._farming_system, main.farming_system, "Main injects farming into production")
	assertions.equal(main.production_system._building_system, main.building_system, "Main injects building registry into production")
	assertions.equal(main.production_system._inventory_system, main.inventory_system, "Main injects player inventory into production")
	assertions.truthy(main.production_system._clock_synced, "Main synchronizes the production clock after new/load state")
	assertions.equal(main.production_system._last_clock_minutes, main.season_system.hour * 60 + main.season_system.minute, "production clock matches restored season time")
	assertions.equal(main.production_system._last_daily_effects_day, main.season_system.total_days, "Main anchors loaded daily effects against replay")
	assertions.equal(main.production_system._last_finished_outputs_day, main.season_system.total_days, "Main anchors loaded passive outputs against replay")
	var event_bus := tree.root.get_node("EventBus")
	var time_connections := 0
	for connection in event_bus.time_changed.get_connections():
		var callback: Callable = connection.get("callable", Callable())
		if callback.is_valid() and callback.get_object() == main.production_system:
			time_connections += 1
	assertions.equal(time_connections, 1, "ProductionSystem owns exactly one time listener")


func _production(grid: GridSystem = null, farming: FarmingSystem = null) -> ProductionSystem:
	var production := _track(ProductionSystemScript.new()) as ProductionSystem
	if grid != null:
		production.configure(grid, farming, null, null)
	return production


func _grid() -> GridSystem:
	return _track(GridSystemScript.new()) as GridSystem


func _farming(grid: GridSystem) -> FarmingSystem:
	var farming := _track(FarmingSystemScript.new()) as FarmingSystem
	farming.configure(grid, null, null)
	return farming


func _inventory(max_slots: int = 20) -> InventorySystem:
	var inventory := _track(InventorySystemScript.new()) as InventorySystem
	inventory.max_slots = max_slots
	inventory.reset_slots()
	return inventory


func _building(id: String, gx: int, gz: int, with_state: bool) -> BuildingInstance:
	var building := _track(BuildingInstance.new()) as BuildingInstance
	building.authored_building_id = id
	building.data = BuildingDataScript.from_dictionary(GameDataScript.get_building(id))
	building.grid_x = gx
	building.grid_z = gz
	if with_state:
		building.producer_state = ProducerStateScript.new(id)
		building.producer_state.output_capacity = int(building.data.effect_config.get("output_capacity", 3))
	return building


func _add_mature_flower(grid: GridSystem, position: Vector2i, crop_id: String = "") -> void:
	var flower := CropData.new()
	flower.crop_id = crop_id if not crop_id.is_empty() else "flower_%d_%d" % [position.x, position.y]
	flower.category = "flower"
	flower.growth_days = 1
	var instance := CropInstance.new()
	instance.crop_data = flower
	instance.set_growth_state(1.0, CropInstance.LifecycleState.MATURE)
	var cell := grid.get_cell(position.x, position.y)
	cell.state = GridCell.State.PLANTED
	cell.crop_instance = instance


func _merge_counts(target: Dictionary, additions: Dictionary) -> void:
	for item_id in additions:
		target[item_id] = int(target.get(item_id, 0)) + int(additions[item_id])


func _track(node: Node) -> Node:
	_owned_nodes.append(node)
	return node


func _cleanup_nodes() -> void:
	for index in range(_owned_nodes.size() - 1, -1, -1):
		var node := _owned_nodes[index]
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()
