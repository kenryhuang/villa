extends Node3D

## 主场景 - 农庄模式
## 编排所有系统初始化、连接和运行

const GRID_SYSTEM_SCENE := preload("res://scenes/systems/grid_system.tscn")
const FARMING_SYSTEM_SCENE := preload("res://scenes/systems/farming_system.tscn")
const BUILDING_SYSTEM_SCENE := preload("res://scenes/systems/building_system.tscn")

@export var load_save_on_start := true

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

# 系统引用
var grid_system: GridSystem
var farming_system: FarmingSystem
var season_system: SeasonSystem
var economy_system: EconomySystem
var inventory_system: InventorySystem
var building_system: BuildingSystem
var tool_system: ToolSystem
var villager_system
var exploration_system: ExplorationSystem
var collectible_system: CollectibleSystem
var story_system: StorySystem
var puzzle_system: PuzzleSystem
@onready var save_manager: Node = get_node("/root/SaveManager")

# 建筑容器
var buildings_container: Node3D


func _ready() -> void:
	_initialize_systems()
	_connect_systems()
	_setup_player()
	_setup_npcs()
	_setup_ui()
	_initial_game_state()


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

	economy_system = EconomySystem.new()
	economy_system.name = "EconomySystem"
	add_child(economy_system)

	inventory_system = InventorySystem.new()
	inventory_system.name = "InventorySystem"
	add_child(inventory_system)

	building_system = BUILDING_SYSTEM_SCENE.instantiate() as BuildingSystem
	add_child(building_system)

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

func _connect_systems() -> void:
	# GridSystem 需要地形引用
	var terrain = world.terrain if world else null
	if terrain:
		var route: Array[Dictionary] = []
		for point in RoadBuilder.MAIN_ROUTE:
			route.append(point.duplicate())
		grid_system.configure(terrain, route)

	# FarmingSystem 依赖 GridSystem + SeasonSystem + GameState
	farming_system.configure(grid_system, season_system, get_node_or_null("/root/GameState"))

	# EconomySystem 依赖 InventorySystem
	economy_system.configure(inventory_system)

	# BuildingSystem 依赖 GridSystem + EconomySystem
	building_system.configure(grid_system, economy_system, buildings_container)

	# ToolSystem 依赖 GridSystem + InventorySystem + Player
	tool_system.configure(grid_system, inventory_system, player)

	# ExplorationSystem 依赖 Player
	exploration_system.configure(player)


func _setup_player() -> void:
	# 放置玩家到地形上
	_place_on_terrain(player, Vector2(0.0, 0.0))
	player.configure(camera_rig, world, tool_system, grid_system)
	action_controller.configure(
		player,
		grid_system,
		farming_system,
		building_system,
		tool_system,
		inventory_system
	)
	camera_rig.set_target(player)


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
		hud.configure_action_bar(action_controller, inventory_system)

	# 背包 UI
	if inventory_ui:
		inventory_ui.configure(inventory_system)

	# 建造 UI
	if build_ui:
		build_ui.configure(building_system)

	# 地图 UI
	if map_ui:
		map_ui.configure(player)

	# 连接建造系统信号
	building_system.build_mode_entered.connect(_on_build_mode_entered)
	building_system.build_mode_exited.connect(_on_build_mode_exited)


func _initial_game_state() -> void:
	_register_default_crops()
	var loaded: bool = load_save_on_start and save_manager.load_game(0)
	if loaded:
		_backfill_legacy_grain_slot()
	else:
		_grant_new_game_items()
	farming_system.rebuild_visuals()
	economy_system.generate_daily_orders()
	if hud:
		hud.refresh_action_bar()


func _register_default_crops() -> void:
	var game_data = get_node_or_null("/root/GameData")
	if game_data == null:
		return

	if game_data.get_crop("grain") == null:
		var grain := CropData.new()
		grain.crop_id = "grain"
		grain.name = "谷物"
		grain.growth_days = 3
		grain.seasons.assign([0, 1, 2])
		grain.exp_reward = 5
		grain.stage_scenes.assign([
			"res://assets/crops/grain/grain_stage_0_seed.tscn",
			"res://assets/crops/grain/grain_stage_1_sprout.tscn",
			"res://assets/crops/grain/grain_stage_2_growing.tscn",
			"res://assets/crops/grain/grain_stage_3_mature.tscn",
		])
		game_data.register_crop(grain)

	# 注册番茄
	if game_data.get_crop("tomato") == null:
		var tomato = CropData.new()
		tomato.crop_id = "tomato"
		tomato.name = "番茄"
		tomato.growth_days = 4
		tomato.seasons.assign([0, 1])  # 春夏
		tomato.exp_reward = 5
		tomato.stage_textures.assign(["seed", "sprout", "growing", "mature"])
		game_data.register_crop(tomato)

	# 注册胡萝卜
	if game_data.get_crop("carrot") == null:
		var carrot = CropData.new()
		carrot.crop_id = "carrot"
		carrot.name = "胡萝卜"
		carrot.growth_days = 3
		carrot.seasons.assign([0, 2])  # 春秋
		carrot.exp_reward = 4
		carrot.stage_textures.assign(["seed", "sprout", "growing", "mature"])
		game_data.register_crop(carrot)

	# 注册土豆
	if game_data.get_crop("potato") == null:
		var potato = CropData.new()
		potato.crop_id = "potato"
		potato.name = "土豆"
		potato.growth_days = 5
		potato.seasons.assign([0, 2])  # 春秋
		potato.exp_reward = 6
		potato.stage_textures.assign(["seed", "sprout", "growing", "mature"])
		game_data.register_crop(potato)


func _grant_new_game_items() -> void:
	inventory_system.clear()
	inventory_system.add_item("grain_seed", 20)
	inventory_system.add_item("wood", 250)
	inventory_system.add_item("stone", 150)
	inventory_system.add_item("iron", 50)
	inventory_system.add_item("glass", 50)
	_map_grain_seed_to_quick_slot()


func _backfill_legacy_grain_slot() -> void:
	if inventory_system.get_quick_item(5) == "grain_seed":
		return
	_map_grain_seed_to_quick_slot()


func _map_grain_seed_to_quick_slot() -> bool:
	for index in range(inventory_system.slots.size()):
		if inventory_system.slots[index].item_id == "grain_seed":
			return inventory_system.set_quick_slot(index, 5)
	return false


# ============================================================
# 信号回调
# ============================================================

func _on_dialogue_started(villager_id: String) -> void:
	if dialogue_ui:
		dialogue_ui.start_dialogue(villager_id)


func _on_build_mode_entered() -> void:
	pass


func _on_build_mode_exited() -> void:
	pass


# ============================================================
# 辅助方法
# ============================================================

func _place_on_terrain(actor: Node3D, point: Vector2) -> void:
	if world == null:
		return
	actor.global_position = Vector3(point.x, world.get_height_at(point.x, point.y) + 1.0, point.y)
