extends Node3D

## 主场景 - 农庄模式
## 编排所有系统初始化、连接和运行

const GRID_SYSTEM_SCENE := preload("res://scenes/systems/grid_system.tscn")
const GameDataScript := preload("res://scripts/core/game_data.gd")
const FARMING_SYSTEM_SCENE := preload("res://scenes/systems/farming_system.tscn")
const BUILDING_SYSTEM_SCENE := preload("res://scenes/systems/building_system.tscn")
const DailySimulationSystemScript := preload(
	"res://scripts/systems/daily_simulation_system.gd"
)
const ProductionSystemScript := preload("res://scripts/systems/production_system.gd")
const NpcEconomySystemScript := preload("res://scripts/systems/npc_economy_system.gd")
const EconomyProgressionSystemScript := preload(
	"res://scripts/systems/economy_progression_system.gd"
)
const EconomyNotificationSystemScript := preload(
	"res://scripts/systems/economy_notification_system.gd"
)
const EconomyModalCoordinatorScript := preload("res://scripts/ui/economy_modal_coordinator.gd")
const GridPathfinderScript := preload("res://scripts/systems/grid_pathfinder.gd")
const GatheringControllerScript := preload("res://scripts/systems/gathering_controller.gd")

@export var load_save_on_start := true
@export var save_slot := 0:
	set(value):
		save_slot = value
		_sync_save_slot()

static var _pending_debug_reload_save_slot := -1

@onready var world = $World
@onready var player = $Actors/Player
@onready var action_controller: PlayerActionController = $Actors/Player/ActionController
@onready var npcs: Node3D = $Actors/Npcs
@onready var camera_rig = $CameraRig
@onready var hud = $HUD
@onready var inventory_ui = $InventoryUI
@onready var dialogue_ui = $DialogueUI
@onready var build_ui = $BuildUI
@onready var map_ui = $MapUI
@onready var shop_ui = $ShopUI
@onready var building_economy_ui = $BuildingEconomyUI
@onready var economy_notification_ui: EconomyNotificationUI = $EconomyNotificationUI
@onready var gathering_feedback: GatheringFeedback = $GatheringFeedback
@onready var tool_swing_visual: ToolSwingVisual = $Actors/Player/ToolSwingVisual

# 系统引用
var grid_system: GridSystem
var farming_system: FarmingSystem
var season_system: SeasonSystem
var economy_system: EconomySystem
var market_system: MarketSystem
var production_system: ProductionSystem
var economy_progression_system: EconomyProgressionSystem
var npc_economy_system: NpcEconomySystem
var economy_notification_system: EconomyNotificationSystem
var daily_simulation_system: Node
var inventory_system: InventorySystem
var building_system: BuildingSystem
var tool_system: ToolSystem
var grid_pathfinder: GridPathfinder
var gathering_controller: GatheringController
var villager_system
var exploration_system: ExplorationSystem
var collectible_system: CollectibleSystem
var story_system: StorySystem
var puzzle_system: PuzzleSystem
var save_manager: Node
var building_economy_modal := EconomyModalCoordinatorScript.new() as EconomyModalCoordinator

# 建筑容器
var buildings_container: Node3D


func _ready() -> void:
	if save_manager == null:
		save_manager = get_node("/root/SaveManager")
	_sync_save_slot()
	_initialize_systems()
	if not _connect_systems():
		push_error("Unable to configure required gameplay economy systems.")
		return
	_setup_player()
	_setup_npcs()
	_setup_ui()
	_initial_game_state()


func _sync_save_slot() -> void:
	if save_manager != null:
		save_manager.current_slot = save_slot


func _unhandled_input(event: InputEvent) -> void:
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_N
		and season_system != null
	):
		season_system.advance_to_next_day()
		get_viewport().set_input_as_handled()


# ============================================================
# 系统初始化
# ============================================================

func _initialize_systems() -> void:
	# 创建系统节点
	grid_system = GRID_SYSTEM_SCENE.instantiate() as GridSystem
	add_child(grid_system)

	farming_system = FARMING_SYSTEM_SCENE.instantiate() as FarmingSystem
	add_child(farming_system)

	season_system = SeasonSystem.new()
	season_system.name = "SeasonSystem"
	add_child(season_system)

	market_system = MarketSystem.new()
	market_system.name = "MarketSystem"
	add_child(market_system)

	npc_economy_system = NpcEconomySystemScript.new() as NpcEconomySystem
	npc_economy_system.name = "NpcEconomySystem"
	add_child(npc_economy_system)

	economy_system = EconomySystem.new()
	economy_system.name = "EconomySystem"
	add_child(economy_system)

	daily_simulation_system = DailySimulationSystemScript.new()
	daily_simulation_system.name = "DailySimulationSystem"
	add_child(daily_simulation_system)

	inventory_system = InventorySystem.new()
	inventory_system.name = "InventorySystem"
	add_child(inventory_system)

	building_system = BUILDING_SYSTEM_SCENE.instantiate() as BuildingSystem
	add_child(building_system)

	production_system = ProductionSystemScript.new() as ProductionSystem
	production_system.name = "ProductionSystem"
	add_child(production_system)

	economy_progression_system = EconomyProgressionSystemScript.new() as EconomyProgressionSystem
	economy_progression_system.name = "EconomyProgressionSystem"
	add_child(economy_progression_system)

	economy_notification_system = EconomyNotificationSystemScript.new() as EconomyNotificationSystem
	economy_notification_system.name = "EconomyNotificationSystem"
	add_child(economy_notification_system)

	tool_system = ToolSystem.new()
	tool_system.name = "ToolSystem"
	add_child(tool_system)

	villager_system = VillagerSystem.new()
	villager_system.name = "VillagerSystem"
	add_child(villager_system)

	exploration_system = ExplorationSystem.new()
	exploration_system.name = "ExplorationSystem"
	add_child(exploration_system)

	collectible_system = CollectibleSystem.new()
	collectible_system.name = "CollectibleSystem"
	add_child(collectible_system)

	story_system = StorySystem.new()
	story_system.name = "StorySystem"
	add_child(story_system)

	puzzle_system = PuzzleSystem.new()
	puzzle_system.name = "PuzzleSystem"
	add_child(puzzle_system)

	# 建筑容器
	buildings_container = Node3D.new()
	buildings_container.name = "Buildings"
	add_child(buildings_container)

func _connect_systems() -> bool:
	# GridSystem 需要地形引用
	var terrain = world.terrain if world else null
	if terrain:
		var route: Array[Dictionary] = []
		for point in RoadBuilder.MAIN_ROUTE:
			route.append(point.duplicate())
		grid_system.configure(terrain, route, world.get_blocked_regions())

	# FarmingSystem 依赖 GridSystem + SeasonSystem + GameState
	farming_system.configure(grid_system, season_system, get_node_or_null("/root/GameState"))

	# MarketSystem 使用静态市场目录创建运行时库存
	var game_data = get_node_or_null("/root/GameData")
	if game_data == null or not market_system.configure(game_data.get_market_items()):
		return false
	if not npc_economy_system.configure(
		market_system,
		game_data.get_npc_economy_profiles(),
		game_data.get_population_demand_profiles()
	):
		return false

	# EconomySystem 依赖 InventorySystem + GameState 钱包 + MarketSystem
	if not economy_system.configure(
		inventory_system,
		get_node_or_null("/root/GameState"),
		market_system,
		npc_economy_system
	):
		return false

	# Building and production share one authoritative registry and player inventory.
	if not building_system.configure(
		grid_system, economy_system, buildings_container, economy_progression_system
	):
		return false
	if not building_system.building_instance_removed.is_connected(_on_economy_building_removed):
		building_system.building_instance_removed.connect(_on_economy_building_removed)
	if not building_system.building_instance_placed.is_connected(_on_building_instance_placed):
		building_system.building_instance_placed.connect(_on_building_instance_placed)
	if not production_system.configure(
		grid_system,
		farming_system,
		building_system,
		inventory_system
	):
		return false

	# Tool and progression share the same authoritative wallet and inventory.
	tool_system.configure(grid_system, inventory_system, player)
	if not economy_progression_system.configure(
		tool_system,
		production_system,
		inventory_system,
		season_system,
		get_node_or_null("/root/GameState")
	):
		return false
	if not economy_notification_system.configure(
		get_node_or_null("/root/EventBus"),
		market_system,
		economy_system,
		season_system
	):
		return false

	# SaveManager 与每日协调器共享同一份市场状态
	if not save_manager.has_method("configure_economy"):
		return false
	var save_manager_configured := bool(save_manager.call(
		"configure_economy",
		market_system,
		daily_simulation_system,
		season_system,
		world,
		npc_economy_system,
		economy_system,
		economy_progression_system,
		tool_system,
		production_system,
		economy_notification_system
	))
	if not save_manager_configured:
		return false
	_connect_save_load_completed()
	if not daily_simulation_system.configure(
		production_system,
		farming_system,
		npc_economy_system,
		economy_system,
		market_system,
		save_manager,
		world
	):
		return false

	# ExplorationSystem 依赖 Player
	exploration_system.configure(player)
	return true


func _connect_save_load_completed() -> void:
	if save_manager == null or not save_manager.has_signal("load_completed"):
		return
	var callback := Callable(self, "_on_save_load_completed")
	if not save_manager.is_connected("load_completed", callback):
		save_manager.connect("load_completed", callback)


func _on_save_load_completed(_slot: int) -> void:
	if production_system == null or season_system == null:
		return
	if not production_system.sync_daily_cursor(season_system.total_days):
		push_error("Unable to synchronize production day after load.")
		return
	production_system.sync_clock(season_system.hour, season_system.minute)
	if npc_economy_system != null:
		npc_economy_system.sync_daily_cursor(season_system.total_days)


func _setup_player() -> void:
	# 放置玩家到地形上
	_place_on_terrain(player, Vector2(0.0, 0.0))
	player.configure(camera_rig, world, tool_system, grid_system)
	grid_pathfinder = GridPathfinderScript.new() as GridPathfinder
	if not grid_pathfinder.configure(grid_system):
		push_error("Unable to configure gathering pathfinder.")
		return
	gathering_controller = GatheringControllerScript.new() as GatheringController
	gathering_controller.name = "GatheringController"
	add_child(gathering_controller)
	if not gathering_controller.configure(
		player,
		grid_pathfinder,
		tool_system,
		season_system
	):
		push_error("Unable to configure gathering controller.")
		return
	action_controller.configure(
		player,
		grid_system,
		farming_system,
		building_system,
		tool_system,
		inventory_system
	)
	if not action_controller.configure_gathering(gathering_controller):
		push_error("Unable to configure player gathering actions.")
		return
	if not gathering_feedback.bind(gathering_controller, tool_swing_visual):
		push_error("Unable to configure gathering feedback.")
		return
	_register_resource_navigation()
	camera_rig.set_target(player)


func _register_resource_navigation() -> void:
	if world == null or grid_system == null or not world.has_method("get_gatherable_nodes"):
		return
	for resource in world.get_gatherable_nodes():
		if not resource is Node3D:
			continue
		var callback := Callable(self, "_on_resource_gathering_active_changed").bind(resource)
		if (
			resource.has_signal("gathering_active_changed")
			and not resource.is_connected("gathering_active_changed", callback)
		):
			resource.connect("gathering_active_changed", callback)
		var active := int(resource.get("remaining_units")) > 0
		_set_resource_navigation_blocker(resource, active)


func _on_resource_gathering_active_changed(
	_resource_id: String,
	active: bool,
	resource: Node
) -> void:
	_set_resource_navigation_blocker(resource, active)


func _set_resource_navigation_blocker(resource: Node, active: bool) -> void:
	if grid_system == null or not resource is Node3D:
		return
	var node := resource as Node3D
	var position := node.global_position if node.is_inside_tree() else node.position
	grid_system.set_navigation_blocker(
		"resource:%s" % str(resource.get("resource_id")),
		grid_system.world_to_grid(position.x, position.z),
		active
	)


func _setup_npcs() -> void:
	# 村民初始位置和配置
	var villager_ids = ["lao_li", "xiao_hua", "tiejiang_zhang", "afu_shui", "xuezhe_lin"]
	var spawn_points = [
		Vector2(-3.0, -2.0),
		Vector2(3.0, -3.0),
		Vector2(4.0, 2.0),
		Vector2(-5.0, 3.0),
		Vector2(2.0, 5.0),
	]

	for i in range(mini(npcs.get_child_count(), villager_ids.size())):
		var npc = npcs.get_child(i)
		_place_on_terrain(npc, spawn_points[i])
		npc.configure(player)
		npc.villager_id = villager_ids[i]
		npc.dialogue_started.connect(_on_dialogue_started)


func _setup_ui() -> void:
	# HUD 初始化
	if hud:
		hud.visible = true
		hud.configure_season_system(season_system)
		hud.configure_action_bar(action_controller, inventory_system, economy_system)
		hud.configure_debug_reset(OS.is_debug_build())
		hud.configure_notifications(economy_notification_system)
		var reset_callback := Callable(self, "_on_debug_reset_requested")
		if not hud.debug_reset_requested.is_connected(reset_callback):
			hud.debug_reset_requested.connect(reset_callback)
		var market_callback := Callable(self, "_on_market_requested")
		if not hud.market_requested.is_connected(market_callback):
			hud.market_requested.connect(market_callback)
		var notification_callback := Callable(self, "_on_notifications_requested")
		if not hud.notifications_requested.is_connected(notification_callback):
			hud.notifications_requested.connect(notification_callback)

	# 背包 UI
	if inventory_ui:
		inventory_ui.configure(inventory_system)

	# 建造 UI
	if build_ui:
		build_ui.keyboard_shortcut_enabled = false
		build_ui.configure(building_system)

	# 地图 UI
	if map_ui:
		map_ui.configure(player)

	# 经济中心兼容沿用 ShopUI 场景，由 Main 注入权威系统引用。
	if shop_ui and not shop_ui.configure(
		inventory_system,
		economy_system,
		market_system,
		economy_progression_system,
		tool_system,
		production_system,
		npc_economy_system
	):
		push_error("Unable to configure economy hub UI.")

	if building_economy_ui and not building_economy_ui.configure(
		production_system,
		inventory_system,
		economy_progression_system,
		grid_system,
		building_economy_modal
	):
		push_error("Unable to configure building economy UI.")
	if economy_notification_ui and not economy_notification_ui.configure(
		economy_notification_system,
		self
	):
		push_error("Unable to configure economy notification UI.")
	for building in building_system.get_all_buildings():
		_on_building_instance_placed(building)

	# 连接建造系统信号
	building_system.build_mode_entered.connect(_on_build_mode_entered)
	building_system.build_mode_exited.connect(_on_build_mode_exited)


func _on_market_requested() -> void:
	open_economy_tab("market")


func _on_notifications_requested() -> void:
	if economy_notification_ui != null:
		economy_notification_ui.toggle_center()


func open_economy_tab(tab_id: String, target_id: String = "") -> bool:
	if shop_ui == null or tab_id not in ["market", "orders", "contracts", "services"]:
		return false
	var panel: Variant = null
	var select_method := ""
	if not target_id.is_empty():
		match tab_id:
			"market":
				if market_system == null or not market_system.has_method("get_item_state") or (market_system.call("get_item_state", target_id) as Dictionary).is_empty():
					return false
				panel = shop_ui.get("market_panel")
				select_method = "select_item"
			"orders":
				if not _economy_record_exists("get_orders", "order_id", target_id):
					return false
				panel = shop_ui.get("order_panel")
				select_method = "select_order"
			"contracts":
				if not _economy_record_exists("get_contracts", "contract_id", target_id):
					return false
				panel = shop_ui.get("contract_panel")
				select_method = "select_contract"
			_:
				return false
		if panel == null or not panel.has_method(select_method):
			return false
	for modal in [inventory_ui, map_ui, build_ui, building_economy_ui]:
		if modal != null and modal.has_method("close"):
			modal.close()
	if economy_notification_ui != null:
		economy_notification_ui.hide_center()
	shop_ui.call("open", tab_id)
	if panel != null:
		panel.call(select_method, target_id)
	return true


func open_building_economy(building: BuildingInstance) -> bool:
	if (
		building == null
		or not is_instance_valid(building)
		or not building.can_open_economy_panel()
		or building_economy_ui == null
		or not building_economy_ui.has_method("open_for")
	):
		return false
	for modal in [inventory_ui, map_ui, build_ui, shop_ui]:
		if modal != null and modal.has_method("close"):
			modal.close()
	return bool(building_economy_ui.call("open_for", building))


func close_economy_modal() -> void:
	if shop_ui != null and shop_ui.has_method("close"):
		shop_ui.close()
	if building_economy_ui != null and building_economy_ui.has_method("close"):
		building_economy_ui.close()
	if economy_notification_ui != null:
		economy_notification_ui.hide_center()


func navigate_economy_target(target_type: String, target_id: String) -> bool:
	match notification_route_kind(target_type, target_id):
		"market_item":
			return open_economy_tab("market", target_id)
		"order":
			return open_economy_tab("orders", target_id)
		"contract":
			return open_economy_tab("contracts", target_id)
		"building":
			return open_building_economy(_find_notification_building(target_id))
	return false


func navigate_notification_target(target_type: String, target_id: String) -> bool:
	return navigate_economy_target(target_type, target_id)


func notification_route_kind(target_type: String, target_id: String) -> String:
	if target_id.is_empty():
		return ""
	if target_type in ["market_item", "order", "contract"]:
		return target_type
	if target_type == "building" and is_valid_building_notification_target(target_id):
		return "building"
	return ""


func is_valid_building_notification_target(target_id: String) -> bool:
	return not _canonical_building_target(target_id).is_empty()


func _canonical_building_target(target_id: String) -> String:
	var building_id := ""
	var gx_text := ""
	var gz_text := ""
	if target_id.contains("@"):
		var halves := target_id.split("@", false)
		if halves.size() != 2:
			return ""
		var coordinates := halves[1].split(",", false)
		if coordinates.size() != 2:
			return ""
		building_id = halves[0]
		gx_text = coordinates[0]
		gz_text = coordinates[1]
	else:
		var parts := target_id.split(":", false)
		if parts.size() != 3:
			return ""
		building_id = parts[0]
		gx_text = parts[1]
		gz_text = parts[2]
	if building_id.is_empty() or not gx_text.is_valid_int() or not gz_text.is_valid_int():
		return ""
	if GameDataScript.get_building(building_id).is_empty():
		return ""
	return "%s:%d:%d" % [building_id, int(gx_text), int(gz_text)]


func _find_notification_building(target_id: String) -> BuildingInstance:
	var canonical := _canonical_building_target(target_id)
	if canonical.is_empty() or building_system == null:
		return null
	for building in building_system.get_all_buildings():
		if building != null and "%s:%d:%d" % [building.building_id, building.grid_x, building.grid_z] == canonical:
			return building
	return null


func _economy_record_exists(method_name: String, id_field: String, target_id: String) -> bool:
	if economy_system == null or not economy_system.has_method(method_name):
		return false
	for record in economy_system.call(method_name):
		if record is Dictionary and str(record.get(id_field, "")) == target_id:
			return true
	return false


func _initial_game_state() -> void:
	_consume_debug_reload_save_slot()
	_register_default_crops()
	var loaded: bool = load_save_on_start and save_manager.load_game(save_slot)
	if loaded:
		_backfill_legacy_grain_slot()
	else:
		market_system.last_settled_day = season_system.total_days
		daily_simulation_system.last_simulated_day = season_system.total_days
		npc_economy_system.sync_daily_cursor(season_system.total_days)
		economy_system.reset_order_state(season_system.total_days)
		_grant_new_game_items()
	production_system.rebuild_registered_buildings()
	if not production_system.sync_daily_cursor(season_system.total_days):
		push_error("Unable to synchronize production day during startup.")
		return
	production_system.sync_clock(season_system.hour, season_system.minute)
	farming_system.rebuild_visuals()
	if hud:
		hud.refresh_action_bar()


func _register_default_crops() -> void:
	var game_data = get_node_or_null("/root/GameData")
	if game_data == null:
		return
	for crop in default_crop_definitions():
		if game_data.get_crop(crop.crop_id) == null:
			game_data.register_crop(crop)


static func default_crop_definitions() -> Array[CropData]:
	var rows := [
		{"id": "grain", "name": "谷物", "days": 3, "yield": [2, 4], "seasons": [0, 1, 2], "exp": 5},
		{"id": "carrot", "name": "胡萝卜", "days": 3, "yield": [2, 3], "seasons": [0, 2], "exp": 4},
		{"id": "potato", "name": "土豆", "days": 4, "yield": [3, 5], "seasons": [0, 2], "exp": 6},
		{"id": "tomato", "name": "番茄", "days": 4, "yield": [2, 3], "regrow": 2, "seasons": [0, 1], "exp": 5},
		{"id": "strawberry", "name": "草莓", "days": 4, "yield": [2, 3], "regrow": 2, "seasons": [0], "form": "bush", "exp": 5},
		{"id": "blueberry", "name": "蓝莓", "days": 5, "yield": [2, 3], "regrow": 2, "seasons": [1], "form": "bush", "exp": 6},
		{"id": "watermelon", "name": "西瓜", "days": 5, "yield": [1, 2], "seasons": [1], "exp": 7},
		{"id": "sunflower", "name": "向日葵", "days": 4, "yield": [2, 3], "seasons": [1, 2], "tags": ["flower"], "category": "flower", "exp": 5},
		{"id": "lavender", "name": "薰衣草", "days": 4, "yield": [2, 3], "seasons": [1, 2], "tags": ["flower"], "category": "flower", "exp": 5},
		{"id": "pumpkin", "name": "南瓜", "days": 5, "yield": [1, 2], "seasons": [2], "exp": 7},
		{"id": "rose", "name": "玫瑰", "days": 4, "yield": [2, 3], "seasons": [0, 1], "tags": ["flower"], "category": "flower", "exp": 5},
		{"id": "apple", "name": "苹果", "days": 5, "yield": [2, 4], "regrow": 3, "seasons": [2], "form": "tree", "tags": ["fruit"], "category": "fruit", "exp": 8},
		{"id": "peach", "name": "桃子", "days": 5, "yield": [2, 3], "regrow": 3, "seasons": [1], "form": "tree", "tags": ["fruit"], "category": "fruit", "exp": 8},
		{"id": "grape", "name": "葡萄", "days": 4, "yield": [2, 4], "regrow": 2, "seasons": [1, 2], "form": "vine", "tags": ["fruit"], "category": "fruit", "exp": 7},
		{"id": "lemon", "name": "柠檬", "days": 5, "yield": [2, 3], "regrow": 3, "seasons": [], "form": "tree", "tags": ["fruit", "greenhouse_only"], "category": "fruit", "exp": 8},
	]
	var definitions: Array[CropData] = []
	for row in rows:
		var crop := CropData.new()
		crop.crop_id = str(row.id)
		crop.name = str(row.name)
		crop.crop_name = str(row.name)
		crop.category = str(row.get("category", "crop"))
		crop.growth_days = int(row.days)
		crop.yield_min = int(row.yield[0])
		crop.yield_max = int(row.yield[1])
		crop.regrow_days = int(row.get("regrow", 0))
		crop.seasons.assign(row.seasons)
		crop.growth_form = str(row.get("form", "annual"))
		crop.tags.assign(row.get("tags", []))
		crop.exp_reward = int(row.exp)
		crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
		if crop.crop_id == "grain":
			crop.stage_scenes.assign([
				"res://assets/crops/grain/grain_stage_0_seed.tscn",
				"res://assets/crops/grain/grain_stage_1_sprout.tscn",
				"res://assets/crops/grain/grain_stage_2_growing.tscn",
				"res://assets/crops/grain/grain_stage_3_mature.tscn",
			])
		definitions.append(crop)
	return definitions


func _grant_new_game_items() -> void:
	inventory_system.clear()
	inventory_system.add_item("grain_seed", 12)
	inventory_system.add_item("wood", 30)
	inventory_system.add_item("stone", 20)
	inventory_system.add_item("fiber", 10)
	var game_state = get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.gold = 150
		var event_bus = get_node_or_null("/root/EventBus")
		if event_bus != null:
			event_bus.gold_changed.emit(game_state.gold)
	_map_grain_seed_to_quick_slot()


func _backfill_legacy_grain_slot() -> void:
	if not inventory_system.get_quick_item(PlayerActionController.SEED_SLOT).is_empty():
		return
	_map_grain_seed_to_quick_slot()


func _map_grain_seed_to_quick_slot() -> bool:
	for index in range(inventory_system.slots.size()):
		if inventory_system.slots[index].get("item_id", "") == "grain_seed":
			return inventory_system.set_quick_slot(index, PlayerActionController.SEED_SLOT)
	return false


func reset_debug_state() -> bool:
	if not OS.is_debug_build():
		return false
	if not save_manager.clear_save(save_slot):
		return false
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		game_state.reset_to_new_game()
	if building_system.is_in_build_mode():
		building_system.exit_preview_mode()
	building_system.clear_buildings(true)
	economy_progression_system.reset_to_new_game()
	tool_system.reset_durability()
	production_system.reset_maintenance(season_system.total_days)
	economy_notification_system.reset_notifications()
	_grant_new_game_items()
	if hud:
		hud.refresh_action_bar()
	return true


func _on_economy_building_removed(building: BuildingInstance) -> void:
	if building_economy_ui != null and building_economy_ui.current_building() == building:
		building_economy_ui.close()
	if building != null and building.interacted.is_connected(_on_building_interacted):
		building.interacted.disconnect(_on_building_interacted)
	if economy_progression_system != null:
		economy_progression_system.clear_building_upgrades(building)


func _on_building_instance_placed(building: BuildingInstance) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not building.interacted.is_connected(_on_building_interacted):
		building.interacted.connect(_on_building_interacted)


func _on_building_interacted(building: BuildingInstance, _player: Node) -> void:
	if building == null or not building.can_open_economy_panel():
		return
	for modal in [inventory_ui, map_ui, build_ui, shop_ui]:
		if modal != null and modal.has_method("close"):
			modal.close()
	building_economy_ui.open_for(building)


func _prepare_debug_reload() -> void:
	_pending_debug_reload_save_slot = save_slot


func _cancel_debug_reload() -> void:
	_pending_debug_reload_save_slot = -1


func _consume_debug_reload_save_slot() -> void:
	if _pending_debug_reload_save_slot < 0:
		return
	save_slot = _pending_debug_reload_save_slot
	_pending_debug_reload_save_slot = -1


# ============================================================
# 信号回调
# ============================================================

func _on_debug_reset_requested() -> void:
	if not OS.is_debug_build():
		return
	if not reset_debug_state():
		push_error("Unable to clear the current debug save.")
		return
	_prepare_debug_reload()
	var reload_error := get_tree().reload_current_scene()
	if reload_error != OK:
		_cancel_debug_reload()
		push_error("Unable to reload the current scene: %s" % error_string(reload_error))

func _on_dialogue_started(villager_id: String) -> void:
	if dialogue_ui:
		dialogue_ui.start_dialogue(villager_id)


func _on_build_mode_entered() -> void:
	if building_economy_ui != null:
		building_economy_ui.on_build_mode_entered()


func _on_build_mode_exited() -> void:
	pass


# ============================================================
# 辅助方法
# ============================================================

func _place_on_terrain(actor: Node3D, point: Vector2) -> void:
	if world == null:
		return
	actor.global_position = Vector3(point.x, world.get_height_at(point.x, point.y) + 1.0, point.y)
