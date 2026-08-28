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
const FarmStorageSystemScript := preload("res://scripts/systems/farm_storage_system.gd")
const ItemContainerRouterScript := preload("res://scripts/systems/item_container_router.gd")
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
const DebugStateEditorScript := preload("res://scripts/debug/debug_state_editor.gd")
const DebugPanelScene := preload("res://scenes/ui/debug_panel.tscn")
const AgentDebugWindowScene := preload("res://scenes/ui/agent_debug_window.tscn")
const HudMessageBusScript := preload("res://scripts/ui/hud_message_bus.gd")
const AgentRuntimeScript := preload("res://scripts/ai_agent/agent_runtime.gd")
const AGENT_NPC_BINDINGS := {
	"NpcNorthwest": {
		"agent_id": "farmer_ahe",
		"spawn": Vector2(-3.0, -2.0),
		"visual_priority": 1,
		"visual_path": (
			"res://assets/characters/npcs/farmer_ahe/farmer_ahe_directions.png"
		),
	},
	"NpcSouth": {
		"agent_id": "lao_li",
		"spawn": Vector2(3.0, -3.0),
		"visual_priority": 3,
		"visual_path": "res://assets/characters/npcs/lao_li/lao_li_directions.png",
	},
	"NpcEast": {
		"agent_id": "xuezhe_lin",
		"spawn": Vector2(4.0, 2.0),
		"visual_priority": 5,
		"visual_path": (
			"res://assets/characters/npcs/xuezhe_lin/xuezhe_lin_directions.png"
		),
	},
}
const AGENT_SERVICE_UNAVAILABLE_MESSAGE := "Agent 服务不可用，请稍后再试。"
const NEW_GAME_STARTER_ITEMS := {
	"grain_seed": 99,
	"wood": 99,
	"stone": 99,
	"fiber": 99,
	"plank": 99,
	"stone_brick": 99,
	"brick": 99,
	"charcoal": 99,
	"glass": 99,
	"iron_ingot": 99,
	"rope": 99,
	"steel": 99,
	"wooden_crate": 99,
	"farm_tools": 99,
	"machine_parts": 99,
	"lamp": 99,
}
const NEW_GAME_STARTER_GOLD := 50_000
const TWO_STAGE_CROP_IDS: Array[String] = [
	"potato", "tomato", "lavender", "rose", "carrot",
	"apple", "peach", "lemon", "grape",
	"blueberry", "strawberry",
	"watermelon", "pumpkin", "sunflower",
]

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
@onready var seed_selector_panel = $SeedSelectorPanel
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
var hud_message_bus: Node
var agent_runtime: Node
var daily_simulation_system: Node
var inventory_system: InventorySystem
var farm_storage_system: FarmStorageSystem
var item_container_router: ItemContainerRouterScript
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
var debug_state_editor: Variant
var debug_panel: Variant
var agent_debug_window: Variant
var building_economy_modal := EconomyModalCoordinatorScript.new() as EconomyModalCoordinator

# 建筑容器
var buildings_container: Node3D
var _world_navigation_blockers: Dictionary = {}
var _agent_npcs: Dictionary = {}
var _agent_dialogue_requests: Dictionary = {}


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
	if agent_runtime != null and agent_runtime.has_method("set_save_slot"):
		agent_runtime.call("set_save_slot", save_slot)


func _unhandled_input(event: InputEvent) -> void:
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_F8
	):
		_on_agent_debug_requested()
		get_viewport().set_input_as_handled()
		return
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_N
	):
		if _advance_debug_crop_day():
			get_viewport().set_input_as_handled()


func _advance_debug_crop_day() -> bool:
	if farming_system == null:
		return false
	var result: Dictionary = farming_system.debug_advance_growth_stage()
	var advanced := int(result.get("advanced", 0))
	var matured := int(result.get("matured", 0))
	var message := (
		"推进了 %d 株作物，其中 %d 株成熟" % [advanced, matured]
		if advanced > 0
		else "没有可推进的作物"
	)
	_publish_hud_message("debug", "debug", message)
	return true


# ============================================================
# 系统初始化
# ============================================================

func _initialize_systems() -> void:
	# 创建系统节点
	hud_message_bus = HudMessageBusScript.new()
	hud_message_bus.name = "HudMessageBus"
	add_child(hud_message_bus)

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

	agent_runtime = AgentRuntimeScript.new()
	agent_runtime.name = "AgentRuntime"
	add_child(agent_runtime)
	agent_runtime.call("set_save_slot", save_slot)

	daily_simulation_system = DailySimulationSystemScript.new()
	daily_simulation_system.name = "DailySimulationSystem"
	add_child(daily_simulation_system)

	inventory_system = InventorySystem.new()
	inventory_system.name = "InventorySystem"
	add_child(inventory_system)

	farm_storage_system = FarmStorageSystemScript.new() as FarmStorageSystem
	farm_storage_system.name = "FarmStorageSystem"
	farm_storage_system.add_to_group("farm_storage_system")
	add_child(farm_storage_system)
	farm_storage_system.configure()

	item_container_router = ItemContainerRouterScript.new()
	item_container_router.name = "ItemContainerRouter"
	add_child(item_container_router)

	economy_system = EconomySystem.new()
	economy_system.name = "EconomySystem"
	add_child(economy_system)

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
	if not farming_system.visual_asset_failed.is_connected(_on_crop_visual_asset_failed):
		farming_system.visual_asset_failed.connect(_on_crop_visual_asset_failed)

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
	if not bool(agent_runtime.call(
		"configure", npc_economy_system, market_system, season_system, hud_message_bus
	)):
		return false
	var agent_dialogue_callback := Callable(self, "_on_agent_dialogue_ready")
	if not agent_runtime.is_connected("dialogue_ready", agent_dialogue_callback):
		agent_runtime.connect("dialogue_ready", agent_dialogue_callback)
	for signal_record in [
		{"name": "dialogue_stream_started", "method": "_on_agent_dialogue_stream_started"},
		{"name": "dialogue_stream_delta", "method": "_on_agent_dialogue_stream_delta"},
		{"name": "dialogue_stream_failed", "method": "_on_agent_dialogue_stream_failed"},
	]:
		var callback := Callable(self, str(signal_record.method))
		if not agent_runtime.is_connected(str(signal_record.name), callback):
			agent_runtime.connect(str(signal_record.name), callback)

	if not item_container_router.configure(inventory_system, farm_storage_system):
		return false

	# EconomySystem 依赖权威物品路由、GameState 钱包和 MarketSystem。
	if not economy_system.configure(
		inventory_system,
		get_node_or_null("/root/GameState"),
		market_system,
		npc_economy_system,
		item_container_router
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
	if not building_system.building_construction_completed.is_connected(
		_on_farm_storage_building_completed
	):
		building_system.building_construction_completed.connect(
			_on_farm_storage_building_completed
		)
	if not production_system.configure(
		grid_system,
		farming_system,
		building_system,
		inventory_system,
		item_container_router
	):
		return false

	# Tool and progression share the same authoritative wallet and inventory.
	tool_system.configure(grid_system, inventory_system, player, farming_system)
	if not economy_progression_system.configure(
		tool_system,
		production_system,
		inventory_system,
		season_system,
		get_node_or_null("/root/GameState")
	):
		return false
	var event_bus := get_node_or_null("/root/EventBus")
	if (
		event_bus != null
		and event_bus.has_signal("building_upgrade_changed")
		and not event_bus.building_upgrade_changed.is_connected(
			_on_farm_storage_building_upgraded
		)
	):
		event_bus.building_upgrade_changed.connect(_on_farm_storage_building_upgraded)
	if not farm_storage_system.configure(_farm_storage_capacity):
		return false
	if not economy_notification_system.configure(
		get_node_or_null("/root/EventBus"),
		market_system,
		economy_system,
		season_system
	):
		return false
	var economy_message_callback := Callable(self, "_on_economy_notification_pushed")
	if not economy_notification_system.notification_pushed.is_connected(economy_message_callback):
		economy_notification_system.notification_pushed.connect(economy_message_callback)

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
		economy_notification_system,
		self,
		farm_storage_system
	))
	if not save_manager_configured:
		return false
	if (
		not save_manager.has_method("configure_agent_runtime")
		or not bool(save_manager.call("configure_agent_runtime", agent_runtime))
		or not bool(agent_runtime.call("configure_save_manager", save_manager))
	):
		return false
	_connect_save_load_completed()
	if not daily_simulation_system.configure(
		production_system,
		farming_system,
		npc_economy_system,
		economy_system,
		market_system,
		save_manager,
		world,
		economy_notification_system
	):
		return false

	# ExplorationSystem 依赖 Player
	exploration_system.configure(player)

	# Auto-map seeds to the seed quick slot when acquired
	if event_bus and event_bus.has_signal("item_added"):
		var callback := Callable(self, "_on_item_added_auto_map_seed")
		if not event_bus.is_connected("item_added", callback):
			event_bus.item_added.connect(callback)

	# Route planting failures into the unified HUD message stream.
	if action_controller and action_controller.has_signal("action_failure_hint"):
		var hint_callback := Callable(self, "_on_action_failure_hint")
		if not action_controller.action_failure_hint.is_connected(hint_callback):
			action_controller.action_failure_hint.connect(hint_callback)
	if action_controller and action_controller.has_signal("action_feedback_requested"):
		var feedback_callback := Callable(self, "_on_action_feedback_requested")
		if not action_controller.action_feedback_requested.is_connected(feedback_callback):
			action_controller.action_feedback_requested.connect(feedback_callback)

	return true


func cancel_transient_actions(reason: String = "save_restore") -> void:
	if gathering_controller != null:
		gathering_controller.cancel_current(reason)


func _connect_save_load_completed() -> void:
	if save_manager == null or not save_manager.has_signal("load_completed"):
		return
	var callback := Callable(self, "_on_save_load_completed")
	if not save_manager.is_connected("load_completed", callback):
		save_manager.connect("load_completed", callback)


func _on_save_load_completed(_slot: int) -> void:
	_initialize_plant_selection()
	if (
		farm_storage_system != null
		and (
			save_manager == null
			or not save_manager.has_method("manages_farm_storage")
			or not bool(save_manager.call("manages_farm_storage", farm_storage_system))
		)
	):
		farm_storage_system.refresh_capacity()
	if production_system == null or season_system == null:
		return
	_rebind_restored_buildings()
	if not production_system.sync_daily_cursor(season_system.total_days):
		push_error("Unable to synchronize production day after load.")
		return
	production_system.sync_clock(season_system.hour, season_system.minute)
	_register_resource_navigation()
	if npc_economy_system != null:
		npc_economy_system.sync_daily_cursor(season_system.total_days)


func _rebind_restored_buildings() -> void:
	if building_system == null:
		return
	for building in building_system.get_all_buildings():
		_on_building_instance_placed(building)


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
		inventory_system,
		farm_storage_system
	)
	if not action_controller.configure_gathering(gathering_controller):
		push_error("Unable to configure player gathering actions.")
		return
	if not gathering_feedback.bind(gathering_controller, tool_swing_visual, action_controller):
		push_error("Unable to configure gathering feedback.")
		return
	_register_resource_navigation()
	camera_rig.set_target(player)


func _register_resource_navigation() -> void:
	if world == null or grid_system == null or not world.has_method("get_navigation_obstacle_nodes"):
		return
	for resource in world.get_navigation_obstacle_nodes():
		if not resource is Node3D:
			continue
		var callback := Callable(self, "_on_resource_gathering_active_changed").bind(resource)
		if (
			resource.has_signal("gathering_active_changed")
			and not resource.is_connected("gathering_active_changed", callback)
		):
			resource.connect("gathering_active_changed", callback)
		var active := (
			not bool(resource.get("gathering_enabled"))
			or int(resource.get("remaining_units")) > 0
		)
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
	var instance_id := resource.get_instance_id()
	for blocker_id in _world_navigation_blockers.get(instance_id, []):
		grid_system.set_navigation_blocker(str(blocker_id), Vector2i.ZERO, false)
	_world_navigation_blockers.erase(instance_id)
	if not active:
		return
	var node := resource as Node3D
	var position := node.global_position if node.is_inside_tree() else node.position
	var center_cell := grid_system.world_to_grid(position.x, position.z)
	var obstacle_radius := (
		float(resource.call("get_interaction_radius"))
		if resource.has_method("get_interaction_radius")
		else 0.45
	)
	var player_radius := 0.35
	var cell_half_diagonal := GridSystem.CELL_SIZE * sqrt(0.5)
	var blocking_distance := obstacle_radius + player_radius + cell_half_diagonal
	var cell_radius := ceili(blocking_distance / GridSystem.CELL_SIZE)
	var blocker_ids: Array[String] = []
	for gz in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
		for gx in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
			var cell := Vector2i(gx, gz)
			var cell_world := grid_system.grid_to_world(gx, gz)
			if Vector2(position.x, position.z).distance_to(cell_world) > blocking_distance:
				continue
			var blocker_id := "world:%d:%d:%d" % [instance_id, gx, gz]
			grid_system.set_navigation_blocker(blocker_id, cell, true)
			blocker_ids.append(blocker_id)
	_world_navigation_blockers[instance_id] = blocker_ids


func _setup_npcs() -> void:
	_agent_npcs.clear()
	_agent_dialogue_requests.clear()
	for node_name in AGENT_NPC_BINDINGS:
		var binding: Dictionary = AGENT_NPC_BINDINGS[node_name]
		var npc = npcs.get_node_or_null(str(node_name)) if npcs != null else null
		if npc == null:
			push_error("Missing visible Agent NPC node: %s" % node_name)
			continue
		var agent_id := str(binding.agent_id)
		_place_on_terrain(npc, binding.spawn as Vector2)
		var display_name := str(agent_runtime.call("get_agent_display_name", agent_id))
		if not bool(npc.call("configure_agent", player, agent_id, display_name)):
			push_error("Unable to bind visible NPC %s to Agent %s" % [node_name, agent_id])
			continue
		npc.call("configure_agent_visual_priority", int(binding.visual_priority))
		var atlas := load(str(binding.visual_path)) as Texture2D
		if not bool(npc.call("configure_agent_visual", atlas)):
			push_error("Unable to configure visual for Agent NPC %s" % agent_id)
		_agent_npcs[agent_id] = npc
		var callback := Callable(self, "_on_dialogue_started")
		if not npc.dialogue_started.is_connected(callback):
			npc.dialogue_started.connect(callback)


func get_agent_npc(agent_id: String) -> Node:
	return _agent_npcs.get(agent_id) as Node


func _set_agent_npc_busy(agent_id: String, busy: bool) -> void:
	var npc := get_agent_npc(agent_id)
	if npc != null and is_instance_valid(npc) and npc.has_method("set_dialogue_busy"):
		npc.call("set_dialogue_busy", busy)


func _publish_agent_service_unavailable(agent_id: String) -> void:
	_publish_hud_message(
		"agent",
		"warning",
		AGENT_SERVICE_UNAVAILABLE_MESSAGE,
		{"agent_id": agent_id}
	)


func _setup_ui() -> void:
	# HUD 初始化
	if hud:
		hud.visible = true
		if not hud.configure_message_bus(hud_message_bus):
			push_error("Unable to configure HUD message bus.")
		hud.configure_season_system(season_system)
		hud.configure_action_bar(action_controller, inventory_system, economy_system)
		hud.configure_debug_tools(OS.is_debug_build())
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
		var inventory_callback := Callable(self, "_on_inventory_requested")
		if not hud.inventory_requested.is_connected(inventory_callback):
			hud.inventory_requested.connect(inventory_callback)
		var unlock_callback := Callable(self, "_on_building_unlock_requested")
		if hud.has_signal("building_unlock_requested") and not hud.building_unlock_requested.is_connected(unlock_callback):
			hud.building_unlock_requested.connect(unlock_callback)
	_setup_runtime_debug_tools()
	_connect_agent_dialogue_ui()

	# 背包 UI
	if inventory_ui:
		inventory_ui.configure(inventory_system, farm_storage_system)
	if seed_selector_panel:
		if not seed_selector_panel.configure(inventory_system, farming_system, action_controller):
			push_error("Unable to configure seed selector UI.")
		var seed_selector_callback := Callable(self, "_on_seed_selection_requested")
		if not action_controller.seed_selection_requested.is_connected(seed_selector_callback):
			action_controller.seed_selection_requested.connect(seed_selector_callback)

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
	if building_economy_ui != null and building_economy_ui.has_signal("unlock_requested"):
		var building_unlock_callback := Callable(self, "_on_building_unlock_requested")
		if not building_economy_ui.is_connected("unlock_requested", building_unlock_callback):
			building_economy_ui.connect("unlock_requested", building_unlock_callback)
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


func _setup_runtime_debug_tools() -> void:
	if hud != null:
		hud.configure_debug_tools(OS.is_debug_build())
	if not OS.is_debug_build():
		return
	debug_state_editor = DebugStateEditorScript.new()
	if not debug_state_editor.configure(
		get_node_or_null("/root/GameState"),
		season_system,
		inventory_system,
		production_system,
		economy_system,
		market_system,
		npc_economy_system,
		daily_simulation_system,
		world,
		get_node_or_null("/root/EventBus"),
		economy_progression_system
	):
		debug_state_editor = null
		push_error("Unable to configure runtime debug state editor.")
		return
	debug_panel = DebugPanelScene.instantiate()
	debug_panel.name = "DebugPanel"
	add_child(debug_panel)
	if not debug_panel.configure(debug_state_editor.snapshot()):
		debug_panel.queue_free()
		debug_panel = null
		push_error("Unable to configure runtime debug panel.")
		return
	var open_callback := Callable(self, "_on_debug_panel_requested")
	if not hud.debug_panel_requested.is_connected(open_callback):
		hud.debug_panel_requested.connect(open_callback)
	var apply_callback := Callable(self, "_on_debug_panel_apply_requested")
	if not debug_panel.apply_requested.is_connected(apply_callback):
		debug_panel.apply_requested.connect(apply_callback)
	var refresh_callback := Callable(self, "_on_debug_panel_refresh_requested")
	if not debug_panel.refresh_requested.is_connected(refresh_callback):
		debug_panel.refresh_requested.connect(refresh_callback)
	var agent_debug_callback := Callable(self, "_on_agent_debug_requested")
	if not debug_panel.agent_debug_requested.is_connected(agent_debug_callback):
		debug_panel.agent_debug_requested.connect(agent_debug_callback)
	if not _connect_agent_debug_settings():
		push_error("Unable to configure Agent debug settings.")
	agent_debug_window = AgentDebugWindowScene.instantiate()
	agent_debug_window.name = "AgentDebugWindow"
	add_child(agent_debug_window)
	if not agent_debug_window.configure(agent_runtime.call("get_session_trace")):
		agent_debug_window.queue_free()
		agent_debug_window = null
		push_error("Unable to configure Agent debug window.")


func _on_debug_panel_requested() -> void:
	if not OS.is_debug_build() or debug_panel == null or debug_state_editor == null:
		return
	debug_panel.open(debug_state_editor.snapshot())
	debug_panel.configure_agent_settings(agent_runtime.call("get_agent_debug_settings"))


func _connect_agent_debug_settings() -> bool:
	if (
		debug_panel == null
		or agent_runtime == null
		or not debug_panel.has_method("configure_agent_settings")
		or not debug_panel.has_signal("agent_settings_apply_requested")
		or not agent_runtime.has_method("get_agent_debug_settings")
		or not agent_runtime.has_method("apply_agent_debug_intervals")
	):
		return false
	if not bool(debug_panel.call("configure_agent_settings", agent_runtime.call("get_agent_debug_settings"))):
		return false
	var callback := Callable(self, "_on_agent_settings_apply_requested")
	if not debug_panel.is_connected("agent_settings_apply_requested", callback):
		debug_panel.connect("agent_settings_apply_requested", callback)
	return true


func _on_agent_settings_apply_requested(intervals: Dictionary) -> void:
	var ok := bool(agent_runtime.call("apply_agent_debug_intervals", intervals))
	if debug_panel != null and debug_panel.has_method("show_agent_settings_result"):
		debug_panel.call("show_agent_settings_result", ok)


func _on_agent_debug_requested() -> void:
	if OS.is_debug_build() and agent_debug_window != null:
		agent_debug_window.toggle()


func _on_debug_panel_apply_requested(draft: Dictionary) -> void:
	if not OS.is_debug_build() or debug_panel == null or debug_state_editor == null:
		return
	var result: Dictionary = debug_state_editor.apply(draft)
	if bool(result.get("ok", false)):
		_publish_hud_message("debug", "success", str(result.get("message", "调试数据已应用")))
		if hud != null:
			hud.configure_season_system(season_system)
			hud.refresh_action_bar()
		if inventory_ui != null and inventory_ui.has_method("refresh"):
			inventory_ui.call("refresh")
		debug_panel.show_apply_result(result, debug_state_editor.snapshot())
		return
	_publish_hud_message("debug", "error", "调试应用失败：%s" % str(result.get("reason", "unknown")))
	debug_panel.show_apply_result(result)


func _on_action_failure_hint(text: String) -> void:
	_publish_hud_message("action", "warning", text)


func _on_action_feedback_requested(
	text: String,
	severity: String,
	details: Dictionary
) -> void:
	_publish_hud_message("action", severity, text, details)


func _on_economy_notification_pushed(record: Dictionary, _merged: bool) -> void:
	var kind := str(record.get("kind", ""))
	_publish_hud_message(
		"economy",
		"warning" if EconomyNotificationSystemScript.is_urgent_kind(kind) else "info",
		str(record.get("body", "")),
		{
			"target_type": str(record.get("target_type", "")),
			"target_id": str(record.get("target_id", "")),
			"game_time": "第%d天" % int(record.get("total_day", 0)),
		}
	)


func _publish_hud_message(source: String, severity: String, text: String, metadata: Dictionary = {}) -> bool:
	if hud_message_bus == null or not is_instance_valid(hud_message_bus):
		return false
	return bool(hud_message_bus.call("publish", source, severity, text, metadata))


func _on_debug_panel_refresh_requested() -> void:
	if not OS.is_debug_build() or debug_panel == null or debug_state_editor == null:
		return
	debug_panel.refresh_from_snapshot(debug_state_editor.snapshot())


func _on_market_requested() -> void:
	open_economy_tab("market")


func _on_building_unlock_requested(service_id: String) -> void:
	open_economy_tab("services", service_id)


func _on_notifications_requested() -> void:
	if economy_notification_ui != null:
		economy_notification_ui.toggle_center()


func _on_inventory_requested() -> void:
	if inventory_ui == null:
		_publish_hud_message("inventory", "error", "背包界面尚未就绪")
		return
	if inventory_ui.visible:
		inventory_ui.close()
		return
	for modal in [map_ui, build_ui, shop_ui, building_economy_ui]:
		if modal != null and modal.has_method("close"):
			modal.close()
	if economy_notification_ui != null:
		economy_notification_ui.hide_center()
	inventory_ui.open()


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
			"services":
				panel = shop_ui.get("service_panel")
				select_method = "select_service"
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
		_initialize_plant_selection()
	else:
		market_system.last_settled_day = season_system.total_days
		daily_simulation_system.last_simulated_day = season_system.total_days
		npc_economy_system.sync_daily_cursor(season_system.total_days)
		economy_system.reset_order_state(season_system.total_days)
		_grant_new_game_items()
		_initialize_plant_selection()
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
		{"id": "grain", "plant_item_id": "grain_seed", "name": "谷物", "days": 3, "yield": [2, 4], "regrow": 0, "seasons": [0, 1, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse", "exp": 5},
		{"id": "carrot", "plant_item_id": "carrot_seed", "name": "胡萝卜", "days": 3, "yield": [2, 3], "regrow": 0, "seasons": [0, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse", "exp": 4},
		{"id": "potato", "plant_item_id": "potato_seed", "name": "土豆", "days": 4, "yield": [3, 5], "regrow": 0, "seasons": [0, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse", "exp": 6},
		{"id": "tomato", "plant_item_id": "tomato_seed", "name": "番茄", "days": 4, "yield": [2, 3], "regrow": 2, "seasons": [0, 1], "lifecycle_type": "annual_regrow", "environment": "outdoor_or_greenhouse", "exp": 5},
		{"id": "strawberry", "plant_item_id": "strawberry_seed", "name": "草莓", "days": 4, "yield": [2, 3], "regrow": 2, "seasons": [0], "lifecycle_type": "bush", "environment": "outdoor_or_greenhouse", "exp": 5},
		{"id": "blueberry", "plant_item_id": "blueberry_seed", "name": "蓝莓", "days": 5, "yield": [2, 3], "regrow": 2, "seasons": [1], "lifecycle_type": "bush", "environment": "outdoor_or_greenhouse", "exp": 6},
		{"id": "watermelon", "plant_item_id": "watermelon_seed", "name": "西瓜", "days": 5, "yield": [1, 2], "regrow": 0, "seasons": [1], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse", "exp": 7},
		{"id": "sunflower", "plant_item_id": "sunflower_seed", "name": "向日葵", "days": 4, "yield": [2, 3], "regrow": 0, "seasons": [1, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse", "tags": ["flower"], "category": "flower", "exp": 5},
		{"id": "lavender", "plant_item_id": "lavender_seed", "name": "薰衣草", "days": 4, "yield": [2, 3], "regrow": 0, "seasons": [1, 2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse", "tags": ["flower"], "category": "flower", "exp": 5},
		{"id": "pumpkin", "plant_item_id": "pumpkin_seed", "name": "南瓜", "days": 5, "yield": [1, 2], "regrow": 0, "seasons": [2], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse", "exp": 7},
		{"id": "rose", "plant_item_id": "rose_seed", "name": "玫瑰", "days": 4, "yield": [2, 3], "regrow": 0, "seasons": [0, 1], "lifecycle_type": "annual", "environment": "outdoor_or_greenhouse", "tags": ["flower"], "category": "flower", "exp": 5},
		{"id": "apple", "plant_item_id": "apple_sapling", "name": "苹果", "days": 5, "yield": [2, 4], "regrow": 3, "seasons": [2], "lifecycle_type": "tree", "environment": "outdoor_or_greenhouse", "tags": ["fruit"], "category": "fruit", "exp": 8},
		{"id": "peach", "plant_item_id": "peach_sapling", "name": "桃子", "days": 5, "yield": [2, 3], "regrow": 3, "seasons": [1], "lifecycle_type": "tree", "environment": "outdoor_or_greenhouse", "tags": ["fruit"], "category": "fruit", "exp": 8},
		{"id": "grape", "plant_item_id": "grape_seed", "name": "葡萄", "days": 4, "yield": [2, 4], "regrow": 2, "seasons": [1, 2], "lifecycle_type": "vine", "environment": "outdoor_or_greenhouse", "tags": ["fruit"], "category": "fruit", "exp": 7},
		{"id": "lemon", "plant_item_id": "lemon_sapling", "name": "柠檬", "days": 5, "yield": [2, 3], "regrow": 3, "seasons": [], "lifecycle_type": "tree", "environment": "greenhouse_only", "tags": ["fruit", "greenhouse_only"], "category": "fruit", "exp": 8},
	]
	var definitions: Array[CropData] = []
	for row in rows:
		var crop := CropData.new()
		crop.crop_id = str(row.id)
		crop.plant_item_id = str(row.plant_item_id)
		crop.name = str(row.name)
		crop.crop_name = str(row.name)
		crop.category = str(row.get("category", "crop"))
		crop.environment = str(row.environment)
		crop.lifecycle_type = str(row.lifecycle_type)
		crop.growth_days = int(row.days)
		crop.yield_min = int(row.yield[0])
		crop.yield_max = int(row.yield[1])
		crop.regrow_days = int(row.get("regrow", 0))
		crop.seasons.assign(row.seasons)
		crop.growth_form = "annual" if crop.lifecycle_type == "annual_regrow" else crop.lifecycle_type
		crop.tags.assign(row.get("tags", []))
		crop.exp_reward = int(row.exp)
		var seed_scene := "res://assets/crops/%s/%s_stage_0_seed.tscn" % [crop.crop_id, crop.crop_id]
		var sprout_scene := "res://assets/crops/%s/%s_stage_1_sprout.tscn" % [crop.crop_id, crop.crop_id]
		var growing_scene := "res://assets/crops/%s/%s_stage_2_growing.tscn" % [crop.crop_id, crop.crop_id]
		var mature_scene := "res://assets/crops/%s/%s_stage_3_mature.tscn" % [crop.crop_id, crop.crop_id]
		if crop.crop_id in TWO_STAGE_CROP_IDS:
			var seed_texture := "res://assets/crops/%s/painted/stage_0/variant_0_front.png" % crop.crop_id
			var mature_texture := "res://assets/crops/%s/painted/stage_3/variant_0_front.png" % crop.crop_id
			crop.stage_textures.assign([seed_texture, seed_texture, seed_texture, mature_texture])
			crop.stage_scenes.assign([seed_scene, seed_scene, seed_scene, mature_scene])
		else:
			crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
			crop.stage_scenes.assign([seed_scene, sprout_scene, growing_scene, mature_scene])
		definitions.append(crop)
	return definitions


func _on_crop_visual_asset_failed(stage_scene_path: String, reason: String) -> void:
	_publish_hud_message(
		"debug",
		"warning",
		"作物美术资源异常：%s（%s）" % [stage_scene_path.get_file(), reason]
	)


func _grant_new_game_items() -> void:
	inventory_system.clear()
	for item_id in NEW_GAME_STARTER_ITEMS:
		inventory_system.add_item(item_id, int(NEW_GAME_STARTER_ITEMS[item_id]))
	var game_state = get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.gold = NEW_GAME_STARTER_GOLD
		var event_bus = get_node_or_null("/root/EventBus")
		if event_bus != null:
			event_bus.gold_changed.emit(game_state.gold)
	_auto_map_seed_to_quick_slot()


func _backfill_legacy_grain_slot() -> void:
	_initialize_plant_selection()


func _initialize_plant_selection() -> bool:
	if action_controller == null or inventory_system == null:
		return false
	if action_controller.migrate_legacy_seed_quick_slot():
		return true
	if not action_controller.get_selected_plant_item_id().is_empty():
		inventory_system.set_quick_slot(-1, PlayerActionController.SEED_SLOT)
		return true
	return _auto_map_seed_to_quick_slot()


func _auto_map_seed_to_quick_slot() -> bool:
	if action_controller != null and action_controller.has_method("auto_map_seed_to_quick_slot"):
		return action_controller.auto_map_seed_to_quick_slot()
	return false


func _on_item_added_auto_map_seed(item_id: String, _quantity: int) -> void:
	if item_id.ends_with("_seed") or item_id.ends_with("_sapling"):
		_auto_map_seed_to_quick_slot()



func _on_seed_selection_requested(cell: GridCell) -> void:
	if seed_selector_panel != null:
		seed_selector_panel.open_for_cell(cell)


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
	if (
		building != null
		and building.output_collection_requested.is_connected(
			_on_building_output_collection_requested
		)
	):
		building.output_collection_requested.disconnect(
			_on_building_output_collection_requested
		)
	if _is_farm_storage_barn(building) and farm_storage_system != null:
		farm_storage_system.refresh_capacity()
	if economy_progression_system != null:
		economy_progression_system.clear_building_upgrades(building)


func _on_farm_storage_building_completed(building: BuildingInstance) -> void:
	if _is_farm_storage_barn(building) and farm_storage_system != null:
		farm_storage_system.refresh_capacity()


func _on_farm_storage_building_upgraded(
	building: BuildingInstance,
	upgrade_id: String,
	_level: int
) -> void:
	if (
		upgrade_id == "storage"
		and _is_farm_storage_barn(building)
		and farm_storage_system != null
	):
		farm_storage_system.refresh_capacity()


func _farm_storage_capacity() -> int:
	var total := FarmStorageSystem.DEFAULT_CAPACITY
	if building_system == null:
		return total
	for building in building_system.get_all_buildings():
		if not _is_farm_storage_barn(building) or not building.is_construction_complete():
			continue
		total += 200
		if economy_progression_system != null:
			var level := economy_progression_system.get_upgrade_level(building, "storage")
			total += clampi(level, 0, 3) * 100
	return total


func _is_farm_storage_barn(building: BuildingInstance) -> bool:
	return (
		building != null
		and is_instance_valid(building)
		and building.building_id == "barn"
	)


func _on_building_instance_placed(building: BuildingInstance) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not building.interacted.is_connected(_on_building_interacted):
		building.interacted.connect(_on_building_interacted)
	if not building.output_collection_requested.is_connected(
		_on_building_output_collection_requested
	):
		building.output_collection_requested.connect(
			_on_building_output_collection_requested
		)


func _on_building_output_collection_requested(
	building: BuildingInstance,
	item_id: String
) -> void:
	if (
		building == null
		or not is_instance_valid(building)
		or production_system == null
		or inventory_system == null
	):
		return
	var result := production_system.collect_outputs(
		building,
		inventory_system,
		item_id
	)
	if bool(result.get("ok", false)):
		return
	var reason := str(result.get("reason", "transaction_failed"))
	building.show_output_collection_failure(item_id, reason)
	if hud != null and hud.has_method("show_build_feedback"):
		var message := (
			"资产库空间不足"
			if reason == "inventory_capacity"
			else "无法收取制品"
		)
		hud.call("show_build_feedback", message, result)


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
	if _agent_npcs.has(villager_id):
		if (
			agent_runtime != null
			and is_instance_valid(agent_runtime)
			and agent_runtime.has_method("is_agent_managed")
			and bool(agent_runtime.call("is_agent_managed", villager_id))
			and dialogue_ui != null
			and dialogue_ui.has_method("open_agent_dialogue")
			and bool(dialogue_ui.call(
				"open_agent_dialogue",
				villager_id,
				agent_runtime.call("get_agent_display_name", villager_id)
			))
		):
			_set_player_dialogue_movement_blocked(true)
			return
		_set_agent_npc_busy(villager_id, false)
		return
	if dialogue_ui:
		dialogue_ui.start_dialogue(villager_id)


func _on_agent_dialogue_stream_started(villager_id: String, request_id: String) -> void:
	var active_request := str(_agent_dialogue_requests.get(villager_id, ""))
	if active_request == request_id:
		return
	if not active_request.is_empty():
		return
	_agent_dialogue_requests[villager_id] = request_id
	if dialogue_ui and dialogue_ui.has_method("begin_agent_dialogue"):
		dialogue_ui.call("begin_agent_dialogue", villager_id, request_id)


func _on_agent_dialogue_stream_delta(_villager_id: String, request_id: String, delta: String) -> void:
	if (
		str(_agent_dialogue_requests.get(_villager_id, "")) == request_id
		and dialogue_ui
		and dialogue_ui.has_method("append_agent_dialogue")
	):
		dialogue_ui.call("append_agent_dialogue", request_id, delta)


func _on_agent_dialogue_stream_failed(villager_id: String, request_id: String, _error: String) -> void:
	var active_request := str(_agent_dialogue_requests.get(villager_id, ""))
	if not active_request.is_empty() and active_request != request_id:
		return
	if dialogue_ui and dialogue_ui.has_method("fail_agent_dialogue"):
		dialogue_ui.call("fail_agent_dialogue", request_id)
	_agent_dialogue_requests.erase(villager_id)
	_publish_agent_service_unavailable(villager_id)


func _on_agent_dialogue_ready(villager_id: String, request_id: String, speech: String) -> void:
	if str(_agent_dialogue_requests.get(villager_id, "")) != request_id:
		return
	if dialogue_ui and dialogue_ui.has_method("finish_agent_dialogue"):
		dialogue_ui.call("finish_agent_dialogue", request_id, speech)
	_agent_dialogue_requests.erase(villager_id)


func _on_agent_message_submitted(villager_id: String, message: String) -> void:
	if (
		agent_runtime != null
		and agent_runtime.has_method("trigger_dialogue")
		and bool(agent_runtime.call("trigger_dialogue", villager_id, message))
	):
		var request_id := str(agent_runtime.call("get_in_flight_request_id", villager_id))
		if not request_id.is_empty():
			_agent_dialogue_requests[villager_id] = request_id
			if dialogue_ui != null and dialogue_ui.has_method("begin_agent_dialogue"):
				dialogue_ui.call("begin_agent_dialogue", villager_id, request_id)
			return
	if dialogue_ui != null and dialogue_ui.has_method("fail_agent_submission"):
		dialogue_ui.call("fail_agent_submission", villager_id, AGENT_SERVICE_UNAVAILABLE_MESSAGE)
	_publish_agent_service_unavailable(villager_id)


func _on_agent_dialogue_cancelled(villager_id: String, request_id: String) -> void:
	if str(_agent_dialogue_requests.get(villager_id, "")) != request_id:
		return
	if agent_runtime != null and agent_runtime.has_method("cancel_dialogue"):
		agent_runtime.call("cancel_dialogue", villager_id, request_id)


func _on_agent_dialogue_closed(villager_id: String, request_id: String) -> void:
	var active_request := str(_agent_dialogue_requests.get(villager_id, ""))
	if not request_id.is_empty() and not active_request.is_empty() and active_request != request_id:
		return
	if request_id.is_empty() and not active_request.is_empty():
		return
	_agent_dialogue_requests.erase(villager_id)
	_set_agent_npc_busy(villager_id, false)
	_set_player_dialogue_movement_blocked(false)


func _set_player_dialogue_movement_blocked(blocked: bool) -> void:
	if player != null and is_instance_valid(player) and player.has_method("set_movement_input_blocked"):
		player.call("set_movement_input_blocked", blocked)


func _connect_agent_dialogue_ui() -> void:
	if dialogue_ui == null or not is_instance_valid(dialogue_ui):
		return
	for signal_record in [
		{"name": "agent_message_submitted", "method": "_on_agent_message_submitted"},
		{"name": "agent_dialogue_cancelled", "method": "_on_agent_dialogue_cancelled"},
		{"name": "agent_dialogue_closed", "method": "_on_agent_dialogue_closed"},
	]:
		var signal_name := str(signal_record.name)
		if not dialogue_ui.has_signal(signal_name):
			continue
		var callback := Callable(self, str(signal_record.method))
		if not dialogue_ui.is_connected(signal_name, callback):
			dialogue_ui.connect(signal_name, callback)


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
