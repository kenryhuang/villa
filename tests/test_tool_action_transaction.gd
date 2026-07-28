extends RefCounted

const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")


class GridDouble:
	extends RefCounted

	func set_cell_state(gx: int, gz: int, next_state: int) -> bool:
		if gx < 0 or gz < 0 or next_state != GridCell.State.FARMLAND:
			return false
		return true

	func water_cell(_gx: int, _gz: int) -> bool:
		return false


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state = tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "tool transaction test has GameState")
	if game_state == null:
		return
	var original_stamina: int = game_state.player_state.stamina
	game_state.player_state.stamina = 100

	var tool = ToolSystemScript.new()
	tree.root.add_child(tool)
	tool.configure(GridDouble.new(), null, null)
	tool.switch_tool(ToolSystem.ToolType.HOE)

	var invalid := GridCell.new()
	invalid.gx = 1
	invalid.gz = 1
	invalid.state = GridCell.State.FARMLAND
	assertions.truthy(not tool.use_tool_on(invalid), "hoe rejects existing farmland")
	assertions.equal(
		game_state.player_state.stamina,
		100,
		"invalid hoe action consumes no stamina"
	)

	var valid := GridCell.new()
	valid.gx = 2
	valid.gz = 2
	valid.state = GridCell.State.WASTELAND
	assertions.truthy(tool.use_tool_on(valid), "hoe accepts wasteland")
	assertions.equal(
		game_state.player_state.stamina,
		95,
		"successful hoe action consumes stamina"
	)

	tool.free()
	game_state.player_state.stamina = original_stamina
