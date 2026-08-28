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

	farm.free()
	farming.free()
	grid.free()
	game_data.free()
