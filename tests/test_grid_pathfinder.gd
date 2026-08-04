extends RefCounted

const GRID_PATHFINDER_PATH := "res://scripts/systems/grid_pathfinder.gd"
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")


func run(assertions: TestAssert) -> void:
	assertions.truthy(
		ResourceLoader.exists(GRID_PATHFINDER_PATH),
		"manual gathering provides a grid pathfinder"
	)
	if not ResourceLoader.exists(GRID_PATHFINDER_PATH):
		return
	var pathfinder_script := load(GRID_PATHFINDER_PATH) as Script
	assertions.truthy(pathfinder_script != null, "grid pathfinder script loads")
	if pathfinder_script == null:
		return

	var grid := GridSystemScript.new()
	assertions.equal(grid.get_navigation_revision(), 0, "fresh grid navigation revision starts at zero")
	assertions.truthy(grid.set_navigation_blocker("resource-a", Vector2i(4, 4), true), "resource blocker registers")
	assertions.equal(grid.get_navigation_revision(), 1, "new blocker increments navigation revision")
	assertions.truthy(not grid.set_navigation_blocker("resource-a", Vector2i(4, 4), true), "identical blocker update is ignored")
	assertions.equal(grid.get_navigation_revision(), 1, "ignored blocker does not change revision")
	assertions.truthy(not grid.is_navigation_cell_walkable(Vector2i(4, 4)), "active resource cell is blocked")
	assertions.truthy(grid.set_navigation_blocker("resource-a", Vector2i(4, 4), false), "resource blocker unregisters")
	assertions.truthy(grid.is_navigation_cell_walkable(Vector2i(4, 4)), "depleted resource cell becomes walkable")

	var pathfinder = pathfinder_script.new()
	assertions.truthy(pathfinder.configure(grid), "pathfinder accepts the grid")
	var direct: Array = pathfinder.find_path_cells(Vector2i(2, 2), Vector2i(6, 2))
	assertions.truthy(not direct.is_empty(), "pathfinder finds a direct route")
	assertions.equal(pathfinder.get_rebuild_count(), 1, "first query builds AStar once")
	pathfinder.find_path_cells(Vector2i(2, 2), Vector2i(6, 2))
	assertions.equal(pathfinder.get_rebuild_count(), 1, "unchanged revision reuses AStar")

	assertions.truthy(grid.set_cell_state(4, 2, GridCell.State.BUILDING), "fixture places a building blocker")
	var detour: Array = pathfinder.find_path_cells(Vector2i(2, 2), Vector2i(6, 2))
	assertions.equal(pathfinder.get_rebuild_count(), 2, "building revision rebuilds AStar once")
	assertions.truthy(not detour.has(Vector2i(4, 2)), "path detours around a building")

	grid.get_cell(3, 2).state = GridCell.State.WATER
	grid.get_cell(2, 3).state = GridCell.State.WATER
	grid.notify_navigation_state_changed()
	var corner_path: Array = pathfinder.find_path_cells(Vector2i(2, 2), Vector2i(3, 3))
	assertions.truthy(not corner_path.is_empty(), "corner fixture remains reachable by a detour")
	assertions.truthy(
		corner_path.size() < 2 or corner_path[1] != Vector2i(3, 3),
		"diagonal path cannot squeeze between two blocked cells"
	)

	grid.set_navigation_blocker("target", Vector2i(8, 8), true)
	var target := Node3D.new()
	var target_world: Vector2 = grid.grid_to_world(8, 8)
	target.position = Vector3(target_world.x, 0.0, target_world.y)
	var start_world: Vector2 = grid.grid_to_world(2, 8)
	var interaction_path: Array = pathfinder.find_path_to_interaction(
		Vector3(start_world.x, 0.0, start_world.y),
		target,
		1.6
	)
	assertions.truthy(not interaction_path.is_empty(), "pathfinder reaches a target interaction cell")
	assertions.truthy(
		interaction_path[-1].distance_to(target.position) <= 1.6,
		"interaction endpoint is within gathering range"
	)
	assertions.truthy(
		Vector2(interaction_path[-1].x, interaction_path[-1].z) != target_world,
		"interaction path never ends inside the resource"
	)

	grid.set_navigation_blocker("sealed-a", Vector2i(11, 10), true)
	grid.set_navigation_blocker("sealed-b", Vector2i(9, 10), true)
	grid.set_navigation_blocker("sealed-c", Vector2i(10, 9), true)
	grid.set_navigation_blocker("sealed-d", Vector2i(10, 11), true)
	grid.set_navigation_blocker("sealed-target", Vector2i(10, 10), true)
	var sealed := Node3D.new()
	var sealed_world := grid.grid_to_world(10, 10)
	sealed.position = Vector3(sealed_world.x, 0.0, sealed_world.y)
	assertions.truthy(
		pathfinder.find_path_to_interaction(Vector3.ZERO, sealed, 1.1).is_empty(),
		"unreachable target returns an empty path"
	)
	target.free()
	sealed.free()
	grid.free()
