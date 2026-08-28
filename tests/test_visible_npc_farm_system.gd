extends RefCounted

const SCRIPT_PATH := "res://scripts/systems/visible_npc_farm_system.gd"
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript = preload("res://scripts/systems/farming_system.gd")


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
			farm.configure(grid, farming, null, null, "farmer_ahe", Vector3(-3.0, 0.0, -2.0)),
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

	farm.free()
	farming.free()
	grid.free()
