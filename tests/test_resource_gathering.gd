extends RefCounted

const RESOURCE_NODE_PATH := "res://scripts/world/resource_node.gd"
const RESOURCE_CATALOG_PATH := "res://scripts/world/resource_catalog.gd"
const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")
const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const PlayerActionControllerScript = preload(
	"res://scripts/actors/player_action_controller.gd"
)
const GameWorldScript = preload("res://scripts/world/world.gd")
const RoadMathScript = preload("res://scripts/world/road_math.gd")
const RoadBuilderScript = preload("res://scripts/world/road_builder.gd")
const DailySimulationSystemScript = preload(
	"res://scripts/systems/daily_simulation_system.gd"
)
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")


class GatherTarget:
	extends Node3D

	func can_gather(_tool_id: String) -> bool:
		return true


class ToolDouble:
	extends RefCounted

	var selected_tool := -1
	var used_targets: Array = []

	func switch_tool(tool_type: int) -> void:
		selected_tool = tool_type

	func use_tool_on(target: Variant) -> bool:
		used_targets.append(target)
		return true


class GatheringDouble:
	extends RefCounted
	var requested: Array[Node] = []
	func request_gather(target: Node) -> bool:
		requested.append(target)
		return true
	func cancel_current(_reason: String) -> void: pass
	func has_active_command() -> bool: return false


class GridDouble:
	extends RefCounted

	func clear_highlights() -> void:
		pass


class BuildingDouble:
	extends RefCounted

	var build_mode := false

	func is_in_build_mode() -> bool:
		return build_mode

	func exit_preview_mode() -> void:
		build_mode = false

	func diagnose_resources(building_id: Variant) -> Dictionary:
		return {
			"allowed": true,
			"code": "ok",
			"message": "",
			"building_id": str(building_id),
			"missing_resources": {},
		}

	func enter_preview_mode(_building_id: Variant) -> bool:
		build_mode = true
		return true


class DailyDouble:
	extends RefCounted
	var last_simulated_day := 0


class ResourceWorldDouble:
	extends RefCounted

	var records: Array[Dictionary] = [{
		"resource_id": "rock-00",
		"position": [1.0, 0.0, 2.0],
		"hits_remaining": 2,
		"respawn_day": 0,
	}]
	var restored: Array = []
	var initialized_days: Array[int] = []

	func to_resource_dicts() -> Array[Dictionary]:
		return records.duplicate(true)

	func validate_resource_dicts(value: Variant, _loaded_day: int = -1) -> bool:
		return value is Array

	func restore_resource_dicts(value: Variant, _loaded_day: int) -> bool:
		restored = value.duplicate(true)
		return true

	func initialize_resources_at_day(day: int) -> void:
		initialized_days.append(day)


class Recorder:
	extends RefCounted
	var calls: Array[String] = []


class ProductionDouble:
	extends RefCounted
	var recorder: Recorder
	func _init(value: Recorder) -> void: recorder = value
	func begin_day(_day: int) -> bool:
		recorder.calls.append("production_begin")
		return true
	func apply_daily_effects(_day: int) -> void: recorder.calls.append("production_pre")
	func finish_daily_outputs(_day: int) -> void: recorder.calls.append("production_post")


class FarmingDouble:
	extends RefCounted
	var recorder: Recorder
	func _init(value: Recorder) -> void: recorder = value
	func on_day_changed(_day: int) -> void: recorder.calls.append("farming")


class EconomyDouble:
	extends RefCounted
	var recorder: Recorder
	func _init(value: Recorder) -> void: recorder = value
	func advance_order_deadlines(_day: int) -> void: recorder.calls.append("orders")
	func generate_demand_orders(_day: int) -> void: recorder.calls.append("demand")


class MarketDouble:
	extends RefCounted
	var recorder: Recorder
	var last_settled_day := 0
	func _init(value: Recorder) -> void: recorder = value
	func can_settle_day(_day: int) -> bool: return true
	func settle_day(day: int) -> bool:
		recorder.calls.append("market")
		last_settled_day = day
		return true
	func to_dict() -> Dictionary: return {"items": {"wood": {}}}


class SaveDouble:
	extends RefCounted
	var recorder: Recorder
	var current_slot := 0
	func _init(value: Recorder) -> void: recorder = value
	func save_game(_slot: int = 0) -> bool:
		recorder.calls.append("save")
		return true


class AdvancingWorldDouble:
	extends RefCounted
	var recorder: Recorder
	func _init(value: Recorder) -> void: recorder = value
	func advance_resource_day(_day: int) -> void: recorder.calls.append("resources")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_resource_catalog_and_v2_contract(assertions)
	_test_target_free_rewards_are_rejected(assertions, tree)
	assertions.truthy(
		ResourceLoader.exists(RESOURCE_NODE_PATH),
		"finite gathering has a common ResourceNode implementation"
	)
	if not ResourceLoader.exists(RESOURCE_NODE_PATH):
		return
	var resource_script := load(RESOURCE_NODE_PATH) as Script
	assertions.truthy(resource_script != null, "ResourceNode script loads")
	if resource_script == null:
		return
	_test_tool_target_matrix(assertions, tree, resource_script)
	_test_depletion_and_exact_respawn(assertions, resource_script)
	_test_atomic_capacity_and_bonus(assertions, tree, resource_script)
	_test_json_state_contract(assertions, resource_script)
	_test_stable_world_generation_and_restore(assertions)
	_test_world_v1_to_v2_normalization_is_complete_and_atomic(assertions)
	_test_real_water_and_riverbank_adjacency(assertions, tree)
	_test_player_target_routing(assertions, tree)
	_test_save_and_legacy_initialization(assertions, tree)
	_test_calendar_coherent_resource_snapshots(assertions, tree)
	_test_daily_coordinator_owns_resource_advance(assertions)


func _test_resource_catalog_and_v2_contract(assertions: TestAssert) -> void:
	assertions.truthy(
		ResourceLoader.exists(RESOURCE_CATALOG_PATH),
		"manual gathering has an immutable resource catalog"
	)
	if not ResourceLoader.exists(RESOURCE_CATALOG_PATH):
		return
	var catalog_script := load(RESOURCE_CATALOG_PATH) as Script
	assertions.truthy(catalog_script != null, "resource catalog script loads")
	if catalog_script == null:
		return
	var tree_definition: Dictionary = catalog_script.call("definition", "tree")
	var gold_definition: Dictionary = catalog_script.call("definition", "gold_ore")
	assertions.equal(tree_definition.get("max_units"), 5, "tree capacity is five")
	assertions.equal(tree_definition.get("respawn_days"), 3, "tree respawns in three days")
	assertions.equal(gold_definition.get("max_units"), 2, "rare ore capacity is two")
	assertions.equal(gold_definition.get("respawn_days"), 7, "rare ore respawns in seven days")
	tree_definition["max_units"] = 99
	assertions.equal(
		(catalog_script.call("definition", "tree") as Dictionary).get("max_units"),
		5,
		"resource catalog definitions are returned by value"
	)

	var resource_script := load(RESOURCE_NODE_PATH) as Script
	var node = resource_script.new()
	assertions.truthy(node.configure_resource({
		"resource_id": "copper-v2",
		"resource_type": "copper_ore",
		"position": Vector3.ZERO,
	}), "resource node configures from catalog type")
	assertions.equal(node.preview_reward("pickaxe"), {"copper_ore": 1}, "visible ore yields one unit")
	var state: Dictionary = node.to_dict()
	assertions.equal(state.get("state_version"), 2, "resource state uses schema v2")
	assertions.equal(state.get("remaining_units"), 3, "resource state stores remaining units")
	assertions.equal(state.get("max_units"), 3, "resource state stores capacity")
	assertions.equal(state.get("visual_stage"), 0, "full resource starts at visual stage zero")
	assertions.truthy(node.has_method("get_interaction_radius"), "resource exposes its interaction radius")
	if node.has_method("get_interaction_radius"):
		assertions.near(float(node.get_interaction_radius()), 0.52, 0.001, "resource interaction radius matches its fallback body")
	node.commit_gather("pickaxe", 4)
	state = node.to_dict()
	assertions.equal(state.get("remaining_units"), 2, "one action removes one resource unit")
	assertions.equal(state.get("visual_stage"), 1, "partial resource advances its visual stage")
	node.free()


func _test_target_free_rewards_are_rejected(assertions: TestAssert, tree: SceneTree) -> void:
	var inventory := InventorySystemScript.new()
	var tools := ToolSystemScript.new()
	tree.root.add_child(inventory)
	tree.root.add_child(tools)
	tools.configure(null, inventory, null)
	tools.switch_tool(ToolSystem.ToolType.AXE)
	var game_state = Engine.get_main_loop().root.get_node_or_null("GameState")
	var stamina_before := int(game_state.player_state.stamina) if game_state else 0
	assertions.truthy(not tools.use_tool_on(null), "axe without a target fails")
	assertions.equal(inventory.get_item_count("wood"), 0, "target-free axe grants no wood")
	if game_state:
		assertions.equal(game_state.player_state.stamina, stamina_before, "failed axe spends no stamina")
	tools.free()
	inventory.free()
	if game_state:
		game_state.player_state.stamina = stamina_before


func _test_tool_target_matrix(
	assertions: TestAssert,
	tree: SceneTree,
	resource_script: Script
) -> void:
	var inventory := InventorySystemScript.new()
	var tools := ToolSystemScript.new()
	tree.root.add_child(inventory)
	tree.root.add_child(tools)
	var game_state = tree.root.get_node_or_null("GameState")
	var stamina_before := int(game_state.player_state.stamina) if game_state else 0
	if game_state:
		game_state.player_state.stamina = 100
	tools.configure(null, inventory, null)
	var rock = _resource(resource_script, "rock-test", "pickaxe", {"stone": 2})
	tools.switch_tool(ToolSystem.ToolType.AXE)
	var rock_hits: int = int(rock.hits_remaining)
	assertions.truthy(not tools.use_tool_on(rock), "axe cannot gather rock")
	assertions.equal(rock.hits_remaining, rock_hits, "mismatched tool does not damage rock")
	assertions.equal(inventory.get_item_count("stone"), 0, "mismatched tool grants nothing")

	tools.switch_tool(ToolSystem.ToolType.PICKAXE)
	assertions.truthy(tools.use_tool_on(rock), "pickaxe gathers rock")
	assertions.equal(inventory.get_item_count("stone"), 1, "rock action grants one stone")

	var image := Image.create_empty(16, 24, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var tree_node := TreeInstanceScript.new()
	tree_node.configure({
		"id": "tree-test",
		"x": 0.0,
		"z": 0.0,
		"width": 2.0,
		"height": 3.0,
		"clearance": 1.0,
		"gatherable": true,
	}, texture, 0.0)
	tools.switch_tool(ToolSystem.ToolType.AXE)
	assertions.truthy(tools.use_tool_on(tree_node), "axe gathers a tree")
	assertions.equal(inventory.get_item_count("wood"), 1, "tree action grants one wood")
	assertions.equal(tree_node.required_tool, "axe", "tree requires axe")
	assertions.equal(tree_node.max_units, 5, "gatherable tree has five units")
	assertions.equal(tree_node.respawn_days, 3, "tree uses three-day respawn")
	tree_node.free()
	rock.free()
	tools.free()
	inventory.free()
	if game_state:
		game_state.player_state.stamina = stamina_before


func _test_depletion_and_exact_respawn(assertions: TestAssert, resource_script: Script) -> void:
	var node = _resource(resource_script, "respawn-rock", "pickaxe", {"stone": 2}, [], 3)
	for hit_index in range(3):
		var reward: Dictionary = node.commit_gather("pickaxe", 7)
		assertions.equal(reward, {"stone": 1}, "successful action %d returns one unit" % (hit_index + 1))
	assertions.equal(node.hits_remaining, 0, "exactly three successful hits deplete")
	assertions.truthy(not node.can_gather("pickaxe"), "depleted node is non-gatherable")
	assertions.equal(node.get_respawn_day(), 10, "depletion records exact respawn boundary")
	assertions.truthy(not node.advance_day(9), "node does not respawn one day early")
	assertions.equal(node.hits_remaining, 0, "early day preserves depletion")
	assertions.truthy(node.advance_day(10), "node respawns on configured day")
	assertions.equal(node.hits_remaining, 3, "respawn restores all hits")
	node.free()


func _test_atomic_capacity_and_bonus(
	assertions: TestAssert,
	tree: SceneTree,
	resource_script: Script
) -> void:
	var inventory := InventorySystemScript.new()
	var tools := ToolSystemScript.new()
	tree.root.add_child(inventory)
	tree.root.add_child(tools)
	var game_state = tree.root.get_node_or_null("GameState")
	var stamina_before := int(game_state.player_state.stamina) if game_state else 0
	if game_state:
		game_state.player_state.stamina = 100
	tools.configure(null, inventory, null)
	tools.switch_tool(ToolSystem.ToolType.PICKAXE)
	var node = _resource(
		resource_script,
		"bonus-rock",
		"pickaxe",
		{"stone": 2},
		[{"item_id": "coal", "quantity": 1, "every_hits": 1, "offset": 0}],
		3
	)
	_fill_inventory(inventory, 20)
	var hits_before: int = int(node.hits_remaining)
	assertions.truthy(not tools.use_tool_on(node), "single-unit reward rejects a full inventory")
	assertions.equal(node.hits_remaining, hits_before, "failed reward preflight causes no damage")
	assertions.equal(inventory.get_item_count("stone"), 0, "failed reward commits no item")

	inventory.clear()
	assertions.truthy(tools.use_tool_on(node), "single-unit reward succeeds with capacity")
	assertions.equal(inventory.get_item_count("stone"), 1, "successful action adds one stone")
	assertions.equal(inventory.get_item_count("coal"), 0, "legacy probability bonus is ignored")

	var tree_node = _resource(resource_script, "full-tree", "axe", {"wood": 2})
	_fill_inventory(inventory, 20)
	tools.switch_tool(ToolSystem.ToolType.AXE)
	hits_before = tree_node.hits_remaining
	assertions.truthy(not tools.use_tool_on(tree_node), "full inventory rejects gathering")
	assertions.equal(tree_node.hits_remaining, hits_before, "full inventory prevents damage")
	tree_node.free()
	node.free()
	tools.free()
	inventory.free()
	if game_state:
		game_state.player_state.stamina = stamina_before


func _test_json_state_contract(assertions: TestAssert, resource_script: Script) -> void:
	var source = _resource(resource_script, "json-rock", "pickaxe", {"stone": 2})
	source.position = Vector3(1.25, 0.5, -2.75)
	source.commit_gather("pickaxe", 4)
	var encoded := JSON.stringify(source.to_dict())
	var decoded: Variant = JSON.parse_string(encoded)
	var restored = _resource(resource_script, "json-rock", "pickaxe", {"stone": 2})
	assertions.truthy(restored.from_dict(decoded), "JSON-decoded resource state restores")
	assertions.equal(restored.to_dict(), source.to_dict(), "resource state round-trips exactly")

	var integral_floats: Dictionary = source.to_dict()
	integral_floats["remaining_units"] = float(integral_floats.remaining_units)
	integral_floats["max_units"] = float(integral_floats.max_units)
	integral_floats["respawn_day"] = float(integral_floats.respawn_day)
	assertions.truthy(restored.from_dict(integral_floats), "integral JSON floats are accepted")
	var before: Dictionary = restored.to_dict()
	var malformed := integral_floats.duplicate(true)
	malformed["remaining_units"] = 1.5
	assertions.truthy(not restored.from_dict(malformed), "fractional hit state is rejected")
	assertions.equal(restored.to_dict(), before, "malformed state is rejected atomically")
	malformed = integral_floats.duplicate(true)
	malformed["position"] = [NAN, 0.0, 0.0]
	assertions.truthy(not restored.from_dict(malformed), "non-finite position is rejected")
	assertions.equal(restored.to_dict(), before, "non-finite state causes no partial mutation")
	source.free()
	restored.free()


func _test_stable_world_generation_and_restore(assertions: TestAssert) -> void:
	var definition_source: Variant = GameWorldScript.new()
	var first: Array[Dictionary] = definition_source.call("generated_resource_definitions")
	var second: Array[Dictionary] = definition_source.call("generated_resource_definitions")
	definition_source.free()
	assertions.equal(first, second, "fixed world seed repeats exact resource definitions")
	var ids := {}
	var zones := {}
	var type_counts := {}
	for definition in first:
		ids[str(definition.resource_id)] = true
		zones[str(definition.zone)] = true
		var resource_type := str(definition.get("resource_type", ""))
		type_counts[resource_type] = int(type_counts.get(resource_type, 0)) + 1
		assertions.truthy(
			not definition.has("bonus_table") and not definition.has("yield_per_hit"),
			"world resource %s has a visible deterministic yield" % definition.resource_id
		)
	assertions.equal(ids.size(), first.size(), "generated resource IDs are unique")
	assertions.equal(first.size(), 13, "world generates thirteen surface mineral nodes")
	assertions.equal(type_counts, {
		"stone": 4,
		"coal": 2,
		"copper_ore": 2,
		"iron_ore": 2,
		"silver_ore": 1,
		"gold_ore": 1,
		"crystal": 1,
	}, "surface mineral counts match the approved distribution")
	assertions.truthy(zones.has("common_mine"), "common minerals occupy the common mine zone")
	assertions.truthy(zones.has("rare_mine"), "rare minerals occupy the remote mine zone")

	var world: Variant = GameWorldScript.new()
	var container := Node3D.new()
	container.name = "ResourceNodes"
	world.add_child(container)
	assertions.equal(world.call("generate_resource_nodes"), first.size(), "world creates every resource definition")
	var count_before := container.get_child_count()
	var state: Array[Dictionary] = world.call("to_resource_dicts")
	assertions.truthy(bool(world.call("restore_resource_dicts", state, 5)), "generated state restores by stable ID")
	assertions.equal(container.get_child_count(), count_before, "load does not duplicate resource nodes")
	assertions.equal(world.call("to_resource_dicts"), state, "stable-ID restore preserves generated order")
	var rewind_target: Variant = container.get_child(0)
	var rewind_capacity := int(rewind_target.get("max_units"))
	for _hit in range(rewind_capacity):
		rewind_target.call("commit_gather", "pickaxe", 5)
	var rewind_state: Array[Dictionary] = world.call("to_resource_dicts")
	world.call("advance_resource_day", 20)
	assertions.truthy(
		bool(world.call("restore_resource_dicts", rewind_state, 5)),
		"runtime load accepts an earlier resource snapshot"
	)
	world.call("advance_resource_day", 8)
	assertions.equal(
		int(rewind_target.get("hits_remaining")),
		rewind_capacity,
		"resource cursor rewinds so the loaded respawn boundary still runs"
	)
	world.free()


func _test_world_v1_to_v2_normalization_is_complete_and_atomic(
	assertions: TestAssert
) -> void:
	var world: Variant = GameWorldScript.new()
	var container := Node3D.new()
	container.name = "ResourceNodes"
	world.add_child(container)
	world.call("generate_resource_nodes")
	assertions.truthy(
		world.has_method("normalize_resource_dicts"),
		"resource world exposes a pure save normalizer"
	)
	if not world.has_method("normalize_resource_dicts"):
		world.free()
		return
	var legacy := [{
		"resource_id": "river-clay-00",
		"position": [-14.65, 0.0, -1.8],
		"hits_remaining": 2,
		"respawn_day": 0,
		"bonus_table": [{"item_id": "coal", "chance": 1.0}],
	}]
	var normalized: Variant = world.call("normalize_resource_dicts", legacy, 5)
	assertions.truthy(normalized is Array, "legacy partial resource array normalizes")
	if normalized is Array:
		assertions.equal(
			normalized.size(),
			world.to_resource_dicts().size(),
			"normalization backfills every newly catalogued resource"
		)
		var migrated := _record_by_id(normalized, "stone-00")
		assertions.equal(migrated.get("state_version"), 2, "legacy record migrates to v2")
		assertions.equal(migrated.get("remaining_units"), 3, "real v1 hits scale upward from capacity three")
		assertions.truthy(not migrated.has("bonus_table"), "legacy random bonus is discarded")
		assertions.truthy(
			migrated.get("position") != legacy[0].position,
			"legacy ID migration adopts the current authored resource position"
		)
		var new_resource := _record_by_id(normalized, "gold-00")
		assertions.equal(new_resource.get("remaining_units"), 2, "missing rare ore starts full")
		assertions.equal(new_resource.get("respawn_day"), 0, "backfilled resource has no respawn timer")

	var before: Array[Dictionary] = world.to_resource_dicts()
	var duplicate := legacy.duplicate(true)
	duplicate.append(legacy[0].duplicate(true))
	assertions.equal(
		world.call("normalize_resource_dicts", duplicate, 5),
		null,
		"duplicate stable resource IDs reject the entire snapshot"
	)
	assertions.truthy(
		not world.restore_resource_dicts(duplicate, 5),
		"duplicate resource snapshot cannot partially apply"
	)
	assertions.equal(world.to_resource_dicts(), before, "rejected normalization leaves world unchanged")
	var invalid := before.duplicate(true)
	invalid[0]["remaining_units"] = 0
	invalid[0]["respawn_day"] = 5
	invalid[0]["visual_stage"] = 3
	assertions.truthy(
		not world.restore_resource_dicts(invalid, 5),
		"expired respawn boundary rejects the entire snapshot"
	)
	assertions.equal(world.to_resource_dicts(), before, "invalid respawn leaves every resource unchanged")
	var stone_node: Node = container.get_node("stone-00")
	var authored_position: Array = _record_by_id(before, "stone-00").position
	stone_node.position = Vector3(99.0, 0.0, 99.0)
	var defaults: Array = world.normalize_resource_dicts([], 5)
	assertions.equal(
		_record_by_id(defaults, "stone-00").position,
		authored_position,
		"missing new resource uses immutable authored position, not prior runtime state"
	)
	world.free()


func _record_by_id(records: Array, resource_id: String) -> Dictionary:
	for record in records:
		if record is Dictionary and str(record.get("resource_id", "")) == resource_id:
			return record
	return {}


func _test_real_water_and_riverbank_adjacency(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	assertions.truthy(main_scene != null, "fresh Main loads for resource-water integration")
	if main_scene == null:
		return
	var main: Variant = main_scene.instantiate()
	main.set("load_save_on_start", false)
	tree.root.add_child(main)
	var water_cells: Array[GridCell] = []
	for gz in range(GridSystem.GRID_DEPTH):
		for gx in range(GridSystem.GRID_WIDTH):
			var cell: GridCell = main.grid_system.get_cell(gx, gz)
			if cell.state == GridCell.State.WATER:
				water_cells.append(cell)
	assertions.truthy(not water_cells.is_empty(), "fresh Main initializes positive WATER cells")
	var water_container: Node = main.world.get_node_or_null("Water")
	assertions.truthy(water_container != null, "world scene exposes deterministic Water container")
	var world_records: Array[Dictionary] = main.world.to_resource_dicts()
	var saved_tree_count := 0
	for record in world_records:
		if str(record.resource_type) == "tree":
			saved_tree_count += 1
	assertions.equal(world_records.size(), 25, "world saves minerals and designated resource trees only")
	assertions.equal(saved_tree_count, 12, "world saves twelve gatherable resource-forest trees")
	var blocked_regions: Variant = (
		main.world.call("get_blocked_regions")
		if main.world.has_method("get_blocked_regions")
		else []
	)
	assertions.truthy(
		blocked_regions is Array and not blocked_regions.is_empty(),
		"world exposes fixed blocked water regions"
	)
	if water_container != null and blocked_regions is Array:
		assertions.equal(
			water_container.get_child_count(),
			blocked_regions.size(),
			"water mesh fallback covers every fixed region"
		)
	var authored_route: Array[Dictionary] = []
	for route_point in RoadBuilderScript.MAIN_ROUTE:
		authored_route.append(route_point)
	for definition in GameWorldScript.generated_resource_definitions():
		var point3: Vector3 = definition.position
		assertions.truthy(
			RoadMathScript.distance_to_route(
				Vector2(point3.x, point3.z),
				0.7,
				authored_route
			) >= 0.45,
			"resource %s does not block the authored road" % definition.resource_id
		)
		for region in blocked_regions:
			assertions.truthy(
				not (region.rect as Rect2).has_point(Vector2(point3.x, point3.z)),
				"resource %s does not spawn inside water" % definition.resource_id
			)
	main.free()


func _test_player_target_routing(assertions: TestAssert, tree: SceneTree) -> void:
	var tools := ToolDouble.new()
	var building := BuildingDouble.new()
	var controller := PlayerActionControllerScript.new()
	tree.root.add_child(controller)
	controller.configure(null, GridDouble.new(), null, building, tools, null)
	var gathering := GatheringDouble.new()
	assertions.truthy(controller.configure_gathering(gathering), "controller accepts gathering routing")
	var target := GatherTarget.new()
	var collider := Area3D.new()
	target.add_child(collider)
	tree.root.add_child(target)
	assertions.truthy(controller.select_slot(2), "axe slot selects in farming mode")
	assertions.truthy(controller.perform_target_interaction(target), "axe slot routes gather target")
	assertions.equal(gathering.requested, [target], "gather target reaches GatheringController once")
	assertions.equal(controller._find_interaction_target(collider), target, "raycast collider resolves gatherable parent")
	assertions.truthy(controller.switch_mode(PlayerActionController.ActionMode.BUILDING), "fixture enters build mode")
	assertions.truthy(not controller.perform_target_interaction(target), "build mode cannot gather resources")
	assertions.equal(gathering.requested.size(), 1, "blocked build-mode gather creates no command")
	target.free()
	controller.free()


func _test_save_and_legacy_initialization(assertions: TestAssert, tree: SceneTree) -> void:
	var market := MarketSystemScript.new()
	var daily := DailyDouble.new()
	var world := ResourceWorldDouble.new()
	var manager := SaveManagerScript.new()
	tree.root.add_child(manager)
	assertions.truthy(market.configure([_wood_definition()]), "resource save market configures")
	assertions.truthy(
		bool(manager.call("configure_economy", market, daily, null, world)),
		"save manager accepts resource world"
	)
	var gathered := manager._gather_save_data()
	assertions.equal(gathered.get("resource_nodes"), world.records, "save includes resource-node state")

	market.last_settled_day = 6
	daily.last_simulated_day = 6
	var old_versioned := {
		"economy_version": 1,
		"market": market.to_dict(),
		"last_simulated_day": 6,
		"total_days": 6,
	}
	assertions.truthy(manager._apply_save_data(old_versioned), "old save without resources still loads")
	assertions.equal(world.initialized_days, [6], "old save initializes resources at loaded day without replay")
	manager.free()
	market.free()


func _test_calendar_coherent_resource_snapshots(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var world: Variant = GameWorldScript.new()
	var container := Node3D.new()
	container.name = "ResourceNodes"
	world.add_child(container)
	world.call("generate_resource_nodes")
	var market := MarketSystemScript.new()
	var daily := DailyDouble.new()
	var manager := SaveManagerScript.new()
	tree.root.add_child(manager)
	assertions.truthy(market.configure([_wood_definition()]), "calendar save market configures")
	assertions.truthy(
		bool(manager.call("configure_economy", market, daily, null, world)),
		"calendar save manager accepts real resource world"
	)
	var before_resources: Array[Dictionary] = world.call("to_resource_dicts")
	var stale_resources := before_resources.duplicate(true)
	var stale_record: Dictionary = stale_resources[0]
	stale_record["remaining_units"] = 0
	stale_record["respawn_day"] = 3
	stale_record["visual_stage"] = 3
	stale_resources[0] = stale_record
	var saved_market: Dictionary = market.to_dict()
	saved_market["last_settled_day"] = 10
	var stale_save := {
		"economy_version": 1,
		"market": saved_market,
		"last_simulated_day": 10,
		"total_days": 10,
		"resource_nodes": stale_resources,
	}
	assertions.truthy(
		not manager._apply_save_data(stale_save),
		"depleted resource with elapsed respawn day rejects save"
	)
	assertions.equal(world.call("to_resource_dicts"), before_resources, "stale resource save applies no world mutation")
	assertions.equal(market.last_settled_day, 0, "stale resource save applies no market mutation")
	assertions.equal(daily.last_simulated_day, 0, "stale resource save applies no day mutation")

	var future_resources := before_resources.duplicate(true)
	var future_record: Dictionary = future_resources[0]
	future_record["remaining_units"] = 0
	future_record["respawn_day"] = 12
	future_record["visual_stage"] = 3
	future_resources[0] = future_record
	var future_save := stale_save.duplicate(true)
	future_save["resource_nodes"] = future_resources
	assertions.truthy(manager._apply_save_data(future_save), "future coherent respawn state loads")
	assertions.equal(daily.last_simulated_day, 10, "valid resource save restores loaded day")
	assertions.equal(
		int((world.call("to_resource_dicts") as Array)[0].respawn_day),
		12,
		"valid future respawn boundary is preserved"
	)
	manager.free()
	market.free()
	world.free()


func _test_daily_coordinator_owns_resource_advance(assertions: TestAssert) -> void:
	var recorder := Recorder.new()
	var daily := DailySimulationSystemScript.new()
	var market := MarketDouble.new(recorder)
	assertions.truthy(bool(daily.call("configure",
		ProductionDouble.new(recorder),
		FarmingDouble.new(recorder),
		null,
		EconomyDouble.new(recorder),
		market,
		SaveDouble.new(recorder),
		AdvancingWorldDouble.new(recorder)
	)), "daily coordinator accepts resource advancement dependency")
	assertions.truthy(daily.run_day(1), "daily coordinator advances resource day")
	assertions.equal(recorder.calls, [
		"production_begin",
		"production_pre",
		"farming",
		"production_post",
		"orders",
		"market",
		"demand",
		"resources",
		"save",
	], "resource advancement runs once before day commit and save")
	daily.free()


func _resource(
	resource_script: Script,
	resource_id: String,
	required_tool: String,
	yield_per_hit: Dictionary,
	bonus_table: Array = [],
	hits: int = 3
) -> Node:
	var node = resource_script.new()
	node.configure_resource({
		"resource_id": resource_id,
		"required_tool": required_tool,
		"hits": hits,
		"yield_per_hit": yield_per_hit,
		"bonus_table": bonus_table,
		"respawn_days": 3,
		"position": Vector3.ZERO,
		"visual_kind": "rock",
	})
	return node


func _fill_inventory(inventory: InventorySystem, occupied_slots: int) -> void:
	inventory.clear()
	for index in range(mini(occupied_slots, inventory.slots.size())):
		inventory.slots[index] = {"item_id": "grain_seed", "quantity": 99}


func _wood_definition() -> Dictionary:
	return {
		"id": "wood",
		"base_price": 3,
		"target_stock": 80,
		"initial_stock": 60,
		"daily_liquidity": 30,
		"volatility": "essential",
	}


func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)
	return Vector2(dx, dz).length()
