extends RefCounted

const SCRIPT_PATH := "res://scripts/systems/visible_npc_farm_system.gd"
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")


class FakeNpcState:
	extends RefCounted
	var inventory := {"carrot_seed": 2}

	func to_dict() -> Dictionary:
		return {"inventory": inventory.duplicate(true)}

	func from_dict(value: Dictionary) -> bool:
		inventory = (value.get("inventory", {}) as Dictionary).duplicate(true)
		return true


class FakeEconomy:
	extends RefCounted
	var state := FakeNpcState.new()

	func get_npc_state(agent_id: String):
		return state if agent_id == "farmer_ahe" else null

	func receive_item(agent_id: String, item_id: String, quantity: int) -> bool:
		if agent_id != "farmer_ahe" or quantity <= 0:
			return false
		state.inventory[item_id] = int(state.inventory.get(item_id, 0)) + quantity
		return true


class FakeGameData:
	extends Node
	var crop: CropData

	func get_all_crops() -> Array:
		return [crop] if crop != null else []

	func get_crop_for_plant_item(item_id: String) -> CropData:
		return crop if crop != null and crop.plant_item_id == item_id else null


func run(assertions: TestAssert) -> void:
	var exists := ResourceLoader.exists(SCRIPT_PATH)
	assertions.truthy(exists, "visible NPC farm system script exists")
	if not exists:
		return
	var script := load(SCRIPT_PATH) as Script
	assertions.truthy(script != null, "visible NPC farm system script loads")
	if script == null:
		return
	var farm = script.new()
	var grid := GridSystemScript.new()
	var farming := FarmingSystemScript.new()
	farming.configure(grid, null, null)
	var blocked_tree_cell := Vector2i(15, 12)
	grid.set_navigation_blocker("test-tree", blocked_tree_cell, true)
	assertions.truthy(
		grid.has_method("is_navigation_cell_blocked"),
		"grid exposes indexed navigation occupancy"
	)
	if grid.has_method("is_navigation_cell_blocked"):
		assertions.truthy(
			grid.call("is_navigation_cell_blocked", blocked_tree_cell),
			"indexed occupancy reports a registered tree footprint"
		)
		var moved_tree_cell := blocked_tree_cell + Vector2i(1, 0)
		grid.set_navigation_blocker("moving-tree", blocked_tree_cell, true)
		grid.set_navigation_blocker("moving-tree", moved_tree_cell, true)
		grid.set_navigation_blocker("test-tree", Vector2i.ZERO, false)
		assertions.truthy(
			not grid.call("is_navigation_cell_blocked", blocked_tree_cell),
			"moving and removing blockers releases the old indexed cell"
		)
		assertions.truthy(
			grid.call("is_navigation_cell_blocked", moved_tree_cell),
			"moving a blocker occupies its new indexed cell"
		)
		grid.set_navigation_blocker("moving-tree", Vector2i.ZERO, false)
		grid.set_navigation_blocker("test-tree", blocked_tree_cell, true)
	var economy := FakeEconomy.new()
	var game_data := FakeGameData.new()
	var crop := CropData.new()
	crop.crop_id = "carrot"
	crop.plant_item_id = "carrot_seed"
	crop.name = "胡萝卜"
	crop.growth_days = 3
	crop.growth_duration_minutes = 108
	crop.yield_min = 2
	crop.yield_max = 2
	crop.seasons = []
	game_data.crop = crop
	assertions.truthy(
		farm.has_method("configure")
		and farm.has_method("get_plot_count")
		and farm.has_method("get_plot")
		and farm.has_method("get_plot_cell")
		and farm.has_method("get_snapshot"),
		"visible farm exposes mapping and snapshot APIs"
	)
	if farm.has_method("configure"):
		assertions.truthy(
			farm.configure(grid, farming, economy, game_data, "farmer_ahe", Vector3(-3.0, 0.0, -2.0)),
			"Ahe visible farm configures near her spawn"
		)
		assertions.equal(farm.get_plot_count("farmer_ahe"), 20, "Ahe owns twenty plots")
		var coordinates: Array[Vector2i] = []
		for index in range(20):
			var plot: Dictionary = farm.get_plot("farmer_ahe", index)
			assertions.equal(int(plot.get("plot_index", -1)), index, "plot index %d remains stable" % index)
			coordinates.append(plot.get("coordinate", Vector2i(-1, -1)))
			var cell: GridCell = farm.get_plot_cell("farmer_ahe", index)
			assertions.truthy(cell != null, "plot %d maps to a real grid cell" % index)
			if cell != null:
				assertions.truthy(
					grid.call("is_reserved_for", cell.gx, cell.gz, "farmer_ahe"),
					"plot %d is reserved for Ahe" % index
				)
				assertions.truthy(
					not grid.call("can_actor_use_cell", cell.gx, cell.gz, "player"),
					"player cannot use Ahe plot %d" % index
				)
		assertions.equal(coordinates.duplicate().reduce(
			func(unique: Array, coordinate: Vector2i):
				if coordinate not in unique:
					unique.append(coordinate)
				return unique,
			[]
		).size(), 20, "all visible farm coordinates are unique")
		assertions.truthy(
			blocked_tree_cell not in coordinates,
			"visible farm never covers a tree navigation footprint"
		)
		var snapshot: Array = farm.get_snapshot("farmer_ahe", 0)
		assertions.equal(snapshot.size(), 20, "Agent snapshot exposes all real plots")
		assertions.equal(str((snapshot[0] as Dictionary).get("state", "")), "untilled", "fresh plot snapshot is untilled")

		var controller := PlayerActionController.new()
		controller.grid_system = grid
		controller.farming_system = farming
		controller.set("_action_mode", PlayerActionController.ActionMode.FARMING)
		controller.set("_selected_slot", 0)
		var first_cell: GridCell = farm.get_plot_cell("farmer_ahe", 0)
		assertions.truthy(not controller.perform_cell_action(first_cell), "player farming rejects Ahe plot")
		assertions.equal(
			str(controller.get_last_action_failure_details().get("reason", "")),
			"reserved_plot",
			"player rejection identifies reserved plot"
		)
		controller.queue_free()

		var batch := {
			"agent_id": "farmer_ahe",
			"decision_id": "decision-farm",
			"expected_revision": 0,
			"actions": [
				{"action_id": "till", "idempotency_key": "v2:till", "tool_name": "till", "arguments": {"plot": 0}},
				{"action_id": "plant", "idempotency_key": "v2:plant", "tool_name": "plant", "arguments": {"plot": 0, "seed_item_id": "carrot_seed"}},
			],
		}
		var queued: Array = farm.queue_batch(batch, 10)
		assertions.equal(queued.size(), 2, "dependent till and plant queue together")
		assertions.equal(str(queued[0].status), "in_progress", "queued till reports in progress")
		assertions.equal(first_cell.state, GridCell.State.WASTELAND, "queue does not mutate real soil")
		assertions.equal(economy.state.inventory.carrot_seed, 2, "queue does not consume seed")
		assertions.truthy(farm.mark_work_started("v2:till"), "front work starts")
		assertions.truthy(farm.complete_work("v2:till").ok, "arrival commits till")
		assertions.equal(first_cell.state, GridCell.State.FARMLAND, "committed till changes real grid")
		assertions.truthy(farm.mark_work_started("v2:plant"), "dependent plant starts next")
		assertions.truthy(farm.complete_work("v2:plant").ok, "arrival commits plant")
		assertions.equal(first_cell.state, GridCell.State.PLANTED, "committed plant changes real grid")
		assertions.equal(economy.state.inventory.carrot_seed, 1, "committed plant consumes one NPC seed")
		assertions.truthy(first_cell.crop_instance != null, "visible farm uses real CropInstance")
		assertions.truthy(not farm.has_pending_work("farmer_ahe"), "completed batch clears queue")
		var saved: Dictionary = farm.to_dict()
		assertions.truthy(farm.validate_dict(saved), "visible farm save validates")
		var original_crop_coordinate: Vector2i = farm.get_plot("farmer_ahe", 0).coordinate
		var restored_blocker: Vector2i = farm.get_plot("farmer_ahe", 19).coordinate
		grid.set_navigation_blocker("restored-tree", restored_blocker, true)
		assertions.truthy(farm.from_dict(saved), "visible farm mapping and queue restore")
		var restored_coordinates: Array[Vector2i] = []
		for plot_index in range(20):
			restored_coordinates.append(farm.get_plot("farmer_ahe", plot_index).coordinate)
		assertions.truthy(
			restored_blocker not in restored_coordinates,
			"restored farm relocates away from a newly occupied tree footprint"
		)
		assertions.truthy(
			farm.get_plot_cell("farmer_ahe", 0).crop_instance != null,
			"farm relocation carries the real planted crop to its stable plot index"
		)
		assertions.equal(
			grid.get_cell(original_crop_coordinate.x, original_crop_coordinate.y).state,
			GridCell.State.WASTELAND,
			"farm relocation clears the previous physical footprint"
		)

	_test_harvest_cleanup(assertions, farm, farming, economy)
	_test_crop_options(assertions, farm, farming, crop, economy)
	farm.free()
	farming.free()
	grid.free()
	game_data.free()


func _farm_action(tool: String, key: String, arguments: Dictionary) -> Dictionary:
	return {"agent_id": "farmer_ahe", "decision_id": key, "actions": [{
		"action_id": key, "idempotency_key": key, "tool_name": tool, "arguments": arguments,
	}]}


func _test_harvest_cleanup(assertions: TestAssert, farm: Variant, farming: FarmingSystem, economy: FakeEconomy) -> void:
	var cell: GridCell = farm.get_plot_cell("farmer_ahe", 0)
	var instance: CropInstance = cell.crop_instance
	var harvest := _farm_action("harvest", "growing-harvest", {"plot": 0})
	assertions.equal(farm.queue_batch(harvest, 20)[0].get("error"), "crop_not_mature", "growing crops cannot be harvested")
	instance.set_lifecycle_state(CropInstance.LifecycleState.DORMANT)
	assertions.equal(farm.queue_batch(harvest, 20)[0].get("error"), "crop_not_mature", "dormant crops cannot be harvested")
	instance.set_lifecycle_state(CropInstance.LifecycleState.WITHERED)
	var inventory_before := economy.state.inventory.duplicate(true)
	var batch := _farm_action("harvest", "clear-withered", {"plot": 0})
	batch.actions.append(_farm_action("plant", "replant-cleared", {"plot": 0, "seed_item_id": "carrot_seed"}).actions[0])
	var results: Array = farm.queue_batch(batch, 21)
	assertions.equal(results.size(), 2, "withered harvest and replant queue in one batch")
	assertions.truthy(bool(results[0].get("ok", false)), "withered harvest queues successfully")
	if results.size() != 2 or not bool(results[0].get("ok", false)):
		return
	assertions.truthy(cell.crop_instance == instance, "queueing cleanup leaves the real crop intact")
	var cleared: Dictionary = farm.complete_work("clear-withered")
	assertions.truthy(bool(cleared.get("ok", false)), "withered harvest clears the crop")
	assertions.equal(cleared.get("resource_delta"), {}, "cleanup rewards no items")
	assertions.equal(cleared.get("cleared_withered"), true, "cleanup identifies clearing rather than productive harvest")
	assertions.equal(economy.state.inventory, inventory_before, "cleanup preserves the entire NPC inventory")
	assertions.equal(cell.state, GridCell.State.FARMLAND, "cleanup restores tilled soil")
	assertions.truthy(cell.crop_instance == null, "cleanup removes the dead crop")
	assertions.truthy(not cell.watered, "cleanup resets watering")
	assertions.truthy(farm.complete_work("replant-cleared").ok, "same batch can plant on the cleared plot")
	var replanted: CropInstance = cell.crop_instance
	var replay: Array = farm.queue_batch(_farm_action("harvest", "clear-withered", {"plot": 0}), 22)
	assertions.equal(replay[0], cleared, "cleanup replay returns the original result")
	assertions.truthy(cell.crop_instance == replanted, "cleanup replay cannot erase the replacement crop")
	replanted.set_growth_state(float(replanted.crop_data.growth_days), CropInstance.LifecycleState.MATURE)
	var mature: Array = farm.queue_batch(_farm_action("harvest", "mature-harvest", {"plot": 0}), 23)
	assertions.truthy(mature[0].ok, "mature crop still queues for harvest")
	var harvested: Dictionary = farm.complete_work("mature-harvest")
	assertions.truthy(harvested.ok, "mature harvest still succeeds")
	assertions.equal(harvested.get("resource_delta"), {"carrot": 2}, "mature harvest still rewards crop yield")
	assertions.equal(economy.state.inventory.get("carrot"), 2, "mature harvest credits NPC inventory")


func _test_crop_options(assertions: TestAssert, farm: Variant, farming: FarmingSystem, crop: CropData, economy: FakeEconomy) -> void:
	var season := SeasonSystem.new()
	season.current_season = SeasonSystem.Season.WINTER
	farming.season_system = season
	economy.state.inventory.carrot_seed = 2
	crop.seasons.assign([SeasonSystem.Season.SPRING])
	var cell: GridCell = farm.get_plot_cell("farmer_ahe", 0)
	if cell.crop_instance == null:
		farming.plant(cell, crop)
	cell.crop_instance.set_lifecycle_state(CropInstance.LifecycleState.WITHERED)
	var snapshot: Array = farm.get_snapshot("farmer_ahe", 100)
	assertions.equal(snapshot[0].get("season_valid"), false, "withered spring crop reports invalid winter season")
	assertions.truthy(not snapshot[1].has("season_valid"), "empty plots do not promise seed season validity")
	assertions.equal(snapshot[0].get("available_actions"), ["harvest"], "withered snapshot advertises cleanup through harvest")
	assertions.truthy(farm.has_method("get_crop_options"), "visible farm exposes real crop options")
	if farm.has_method("get_crop_options"):
		farming.clear_withered(cell)
		var options: Array = farm.get_crop_options("farmer_ahe")
		assertions.equal(options.size(), 1, "crop options include registered crops")
		if not options.is_empty():
			var option: Dictionary = options[0]
			assertions.equal(option.get("seed_item_id"), "carrot_seed", "crop option names authoritative seed")
			assertions.equal(option.get("season_names"), ["spring"], "crop option names its allowed seasons")
			assertions.equal(option.get("season_valid"), false, "spring-only seed is unavailable outdoors in winter")
			assertions.equal(option.get("plantable_plots"), [], "invalid season yields no plantable plots")
			assertions.equal(option.get("unavailable_reason"), "wrong_season", "crop option explains winter restriction")
			assertions.equal(option.get("growth_duration_minutes"), 108, "crop option uses authoritative growth duration")
			farming.set_greenhouse_cells([Vector2i(cell.gx, cell.gz)])
			options = farm.get_crop_options("farmer_ahe")
			assertions.equal(options[0].get("plantable_plots"), [0], "greenhouse preview permits planting despite outdoor season")
			assertions.equal(options[0].get("unavailable_reason"), "", "greenhouse clears planting restriction")
			economy.state.inventory.carrot_seed = 0
			options = farm.get_crop_options("farmer_ahe")
			assertions.equal(options[0].get("plantable_plots"), [], "missing seeds cannot advertise immediately plantable plots")
			assertions.equal(options[0].get("unavailable_reason"), "seed_unavailable", "missing seeds explain planting rejection")
			assertions.equal(farm.get_crop_options("lao_li"), [], "crop options do not expose another NPC's farm")
	farming.season_system = null
	season.free()
