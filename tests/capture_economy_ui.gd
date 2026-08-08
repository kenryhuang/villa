extends SceneTree

const OUTPUT_DIR := "res://.godot/economy-ui-verification"
const STATES := [
	"market_normal",
	"shortage_large_confirmation",
	"running_producer",
	"full_maintenance_paused",
	"orders_contracts",
	"waterwheel_overlay",
	"merged_toasts",
	"empty_error",
]
const SIZES := [Vector2i(3000, 2000), Vector2i(1920, 1080), Vector2i(1280, 720)]
const GameDataScript := preload("res://scripts/core/game_data.gd")
const MarketSystemScript := preload("res://scripts/systems/market_system.gd")
const EconomySystemScript := preload("res://scripts/systems/economy_system.gd")
const InventorySystemScript := preload("res://scripts/systems/inventory_system.gd")
const NpcEconomySystemScript := preload("res://scripts/systems/npc_economy_system.gd")
const ProductionSystemScript := preload("res://scripts/systems/production_system.gd")
const ProgressionSystemScript := preload("res://scripts/systems/economy_progression_system.gd")
const NotificationSystemScript := preload("res://scripts/systems/economy_notification_system.gd")
const ProducerStateScript := preload("res://scripts/data/producer_state.gd")
const GridSystemScript := preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript := preload("res://scripts/systems/farming_system.gd")
const ModalCoordinatorScript := preload("res://scripts/ui/economy_modal_coordinator.gd")
const BuildingEconomyScene := preload("res://scenes/ui/economy/building_economy_ui.tscn")
const EconomyTheme := preload("res://assets/ui/economy/economy_theme.tres")

var _wallet_snapshot: Dictionary
var _failed := false


func _init() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("real UI capture requires --display-driver windows with the OpenGL3 renderer")
		return
	var user_arguments := OS.get_cmdline_user_args()
	if "--self-test-failure" in user_arguments:
		_fail("injected capture failure")
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("cannot create capture directory: %s" % error_string(directory_error))
		return
	var wallet := root.get_node_or_null("GameState")
	if wallet == null:
		_fail("GameState autoload is required")
		return
	_wallet_snapshot = {"gold": wallet.gold, "level": wallet.player_state.level}
	var selected_states: Array = STATES.duplicate()
	var selected_sizes: Array = SIZES.duplicate()
	for argument in user_arguments:
		if argument.begins_with("--state="):
			var requested_state := argument.trim_prefix("--state=")
			if requested_state not in STATES:
				_fail("unknown capture state: %s" % requested_state)
				return
			selected_states = [requested_state]
		elif argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x", false)
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				_fail("invalid capture size: %s" % argument)
				return
			var requested_size := Vector2i(int(parts[0]), int(parts[1]))
			if requested_size not in SIZES:
				_fail("unsupported capture size: %s" % requested_size)
				return
			selected_sizes = [requested_size]
	var captures: Array[String] = []
	for state_id in selected_states:
		for viewport_size in selected_sizes:
			root.content_scale_size = viewport_size
			root.size = viewport_size
			wallet.gold = 5000
			wallet.player_state.level = 5
			var stage := await _build_state(state_id, viewport_size, wallet)
			if _failed:
				return
			if stage == null:
				_fail("cannot build state %s" % state_id)
				return
			for _frame in range(3):
				await process_frame
				if _failed:
					return
			await RenderingServer.frame_post_draw
			if _failed:
				return
			var image := root.get_texture().get_image()
			if image == null or image.is_empty():
				_fail("empty capture for %s at %s" % [state_id, viewport_size])
				return
			if image.get_width() != viewport_size.x or image.get_height() != viewport_size.y:
				_fail("wrong capture size for %s: %dx%d" % [state_id, image.get_width(), image.get_height()])
				return
			var file_name := "%s_%dx%d.png" % [state_id, viewport_size.x, viewport_size.y]
			var save_error := image.save_png(output_path.path_join(file_name))
			if save_error != OK:
				_fail("cannot save %s: %s" % [file_name, error_string(save_error)])
				return
			captures.append(file_name)
			print("CAPTURE_PROGRESS: %s" % file_name)
			stage.free()
			paused = false
			await process_frame
			if _failed:
				return
	wallet.gold = _wallet_snapshot.gold
	wallet.player_state.level = _wallet_snapshot.level
	var expected_count := selected_states.size() * selected_sizes.size()
	if captures.size() != expected_count:
		_fail("expected %d captures, got %d" % [expected_count, captures.size()])
		return
	if _failed:
		return
	assert(not _failed, "failed capture run cannot reach the success exit")
	captures.sort()
	for file_name in captures:
		print("CAPTURED: %s" % file_name)
	print("PASS: %d deterministic economy UI captures in %s" % [captures.size(), output_path])
	quit(0)


func _build_state(state_id: String, viewport_size: Vector2i, wallet: Node) -> Control:
	var stage := _new_stage(viewport_size, _state_title(state_id))
	root.add_child(stage)
	await process_frame
	if _failed:
		stage.free()
		return null
	match state_id:
		"market_normal":
			await _build_market(stage, wallet, false)
			if _failed:
				stage.free()
				return null
		"shortage_large_confirmation":
			await _build_market(stage, wallet, true)
			if _failed:
				stage.free()
				return null
		"running_producer":
			await _build_producer(stage, false)
			if _failed:
				stage.free()
				return null
		"full_maintenance_paused":
			await _build_producer(stage, true)
			if _failed:
				stage.free()
				return null
		"orders_contracts":
			await _build_orders_contracts(stage, wallet)
			if _failed:
				stage.free()
				return null
		"waterwheel_overlay":
			await _build_waterwheel(stage)
			if _failed:
				stage.free()
				return null
		"merged_toasts":
			await _build_toasts(stage)
			if _failed:
				stage.free()
				return null
		"empty_error":
			await _build_empty_error(stage)
			if _failed:
				stage.free()
				return null
		_:
			stage.free()
			return null
	return stage


func _new_stage(viewport_size: Vector2i, title: String) -> Control:
	var stage := Control.new()
	stage.name = "EconomyCaptureStage"
	stage.theme = EconomyTheme
	stage.size = Vector2(viewport_size)
	var background := ColorRect.new()
	background.name = "CaptureBackground"
	background.color = Color("#6F8B67")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	var header := Label.new()
	header.name = "CaptureTitle"
	header.text = title
	header.add_theme_font_size_override("font_size", 32)
	header.add_theme_color_override("font_color", Color("#FFF7E6"))
	header.position = Vector2(36, 20)
	header.size = Vector2(viewport_size.x - 72, 54)
	stage.add_child(header)
	return stage


func _content_host(stage: Control) -> MarginContainer:
	var host := MarginContainer.new()
	host.name = "ContentHost"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.offset_left = maxf(28.0, stage.size.x * 0.035)
	host.offset_top = 86.0
	host.offset_right = -maxf(28.0, stage.size.x * 0.035)
	host.offset_bottom = -maxf(28.0, stage.size.y * 0.035)
	stage.add_child(host)
	return host


func _build_market(stage: Control, wallet: Node, shortage: bool) -> void:
	var inventory := InventorySystemScript.new() as InventorySystem
	var market := MarketSystemScript.new() as MarketSystem
	var economy := EconomySystemScript.new() as EconomySystem
	for node in [inventory, market, economy]:
		stage.add_child(node)
	var definition: Dictionary = GameDataScript.get_item("wood").duplicate(true)
	definition.initial_stock = 2 if shortage else 60
	definition.target_stock = 80
	definition.daily_liquidity = 10
	market.configure([definition])
	for day in range(1, 7):
		market.settle_day(day)
	economy.configure(inventory, wallet, market)
	inventory.add_item("wood", 30)
	var panel := preload("res://scenes/ui/economy/market_panel.tscn").instantiate()
	_content_host(stage).add_child(panel)
	await process_frame
	if _failed:
		return
	panel.configure(inventory, economy, market)
	panel.select_item("wood")
	if shortage:
		panel.trade_panel.quantity_spin.value = 10
		panel.trade_panel.request_sell()


func _build_producer(stage: Control, paused_and_full: bool) -> void:
	stage.get_node("CaptureTitle").visible = false
	var fixture := _production_fixture(stage)
	_unlock_station(fixture.progression, "windmill")
	fixture.production.set_progression_system(fixture.progression)
	fixture.inventory.add_item("grain", 4)
	var windmill := _building("windmill", 4, 5)
	stage.add_child(windmill)
	fixture.production.register_building(windmill)
	fixture.production.start_recipe(windmill, "flour", 1, fixture.inventory)
	if paused_and_full:
		windmill.producer_state.outputs = {"flour": 1, "animal_feed": 1, "sunflower_oil": 1}
		fixture.production.set_maintenance_due_day(windmill, 0)
	var ui := BuildingEconomyScene.instantiate() as BuildingEconomyUI
	stage.add_child(ui)
	await process_frame
	if _failed:
		return
	ui.configure(fixture.production, fixture.inventory, fixture.progression, fixture.grid, ModalCoordinatorScript.new())
	ui.open_for(windmill)
	ui.production_panel.select_recipe("flour")


func _build_orders_contracts(stage: Control, wallet: Node) -> void:
	stage.get_node("CaptureTitle").visible = false
	var fixture := _order_fixture(stage, wallet)
	var shop := preload("res://scenes/ui/shop_ui.tscn").instantiate()
	stage.add_child(shop)
	await process_frame
	if _failed:
		return
	shop.configure(fixture.inventory, fixture.economy, fixture.market, null, null, null, fixture.npc)
	shop.open("contracts")
	shop.contract_panel.select_contract("lao_li:grain:1:3")


func _build_waterwheel(stage: Control) -> void:
	stage.get_node("CaptureTitle").visible = false
	stage.get_node("CaptureBackground").visible = false
	var fixture := _production_fixture(stage)
	var wheel := (load("res://scenes/buildings/waterwheel.tscn") as PackedScene).instantiate() as BuildingInstance
	var definition: Dictionary = GameDataScript.get_building("waterwheel")
	wheel.configure(BuildingData.from_dictionary(definition), 10, 10, [])
	stage.add_child(wheel)
	var wheel_point: Vector2 = fixture.grid.grid_to_world(10, 10)
	wheel.position = Vector3(wheel_point.x, 0.08, wheel_point.y)
	fixture.grid.get_cell(9, 10).state = GridCell.State.WATER
	for position in [Vector2i(10, 12), Vector2i(12, 10), Vector2i(13, 10), Vector2i(10, 14)]:
		fixture.grid.get_cell(position.x, position.y).state = GridCell.State.FARMLAND
	fixture.production.register_building(wheel)
	var world := _build_waterwheel_world(stage, fixture.grid, fixture.production.get_irrigated_cells(wheel), wheel.position)
	var ui := BuildingEconomyScene.instantiate() as BuildingEconomyUI
	stage.add_child(ui)
	await process_frame
	if _failed:
		return
	ui.configure(fixture.production, fixture.inventory, fixture.progression, fixture.grid, ModalCoordinatorScript.new())
	ui.open_for(wheel)
	ui.status_panel.range_preview_button.button_pressed = true
	ui.status_panel.range_preview_button.toggled.emit(true)
	# Keep the actual status shell visible while exposing enough of the world to
	# inspect projection, depth occlusion, and click-through around it.
	ui.modal_layer.color = Color(0.13, 0.10, 0.09, 0.32)
	var building_panel := ui.get_node("ScreenLayer/ModalLayer/BuildingPanel") as Control
	building_panel.anchor_left = 0.56
	building_panel.anchor_top = 0.05
	building_panel.anchor_right = 0.97
	building_panel.anchor_bottom = 0.95
	building_panel.offset_left = 0.0
	building_panel.offset_top = 0.0
	building_panel.offset_right = 0.0
	building_panel.offset_bottom = 0.0
	for range_cell in ui.range_overlay.get_children():
		if range_cell is CollisionObject3D:
			_fail("WorldRangeOverlay must stay click-through")
			return
		var mesh_instance := range_cell as MeshInstance3D
		var material := mesh_instance.mesh.material as StandardMaterial3D if mesh_instance != null else null
		if material == null or material.no_depth_test:
			_fail("WorldRangeOverlay must participate in camera depth occlusion")
			return
	if world == null or ui.range_overlay.get_child_count() == 0:
		_fail("waterwheel capture requires a live camera and WorldRangeOverlay geometry")


func _build_waterwheel_world(stage: Control, grid: GridSystem, cells: Array, target: Vector3) -> Node3D:
	var world_root := Node3D.new()
	world_root.name = "WaterwheelCaptureWorld"
	stage.add_child(world_root)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#87AFC2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#FFF2CF")
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	world_root.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	world_root.add_child(sun)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(18.0, 18.0)
	ground_mesh.material = _world_material(Color("#789767"))
	ground.mesh = ground_mesh
	ground.position = Vector3(target.x, 0.0, target.z)
	world_root.add_child(ground)
	var channel := MeshInstance3D.new()
	var channel_mesh := BoxMesh.new()
	channel_mesh.size = Vector3(1.35, 0.055, 15.0)
	channel_mesh.material = _world_material(Color("#4F91A8"))
	channel.mesh = channel_mesh
	channel.position = Vector3(target.x - 1.5, 0.025, target.z)
	world_root.add_child(channel)
	for cell in cells:
		var farmland := MeshInstance3D.new()
		var farmland_mesh := BoxMesh.new()
		farmland_mesh.size = Vector3(0.96, 0.025, 0.96)
		farmland_mesh.material = _world_material(Color("#8D694B"))
		farmland.mesh = farmland_mesh
		var point := grid.grid_to_world(cell.x, cell.y)
		farmland.position = Vector3(point.x, 0.012, point.y)
		world_root.add_child(farmland)
	# An opaque world obstacle crosses one real overlay cell. The range mesh
	# remains behind it because its material keeps depth testing enabled.
	if cells.size() > 1:
		var obstacle := MeshInstance3D.new()
		obstacle.name = "OcclusionProbe"
		var obstacle_mesh := BoxMesh.new()
		obstacle_mesh.size = Vector3(0.58, 0.48, 0.58)
		obstacle_mesh.material = _world_material(Color("#665143"))
		obstacle.mesh = obstacle_mesh
		var blocked_cell: Vector2i = cells[1]
		var blocked_point := grid.grid_to_world(blocked_cell.x, blocked_cell.y)
		obstacle.position = Vector3(blocked_point.x, 0.24, blocked_point.y)
		world_root.add_child(obstacle)
	var rig := (load("res://scenes/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	world_root.add_child(rig)
	var anchor := Node3D.new()
	anchor.position = target + Vector3(3.0, 0.0, 3.0)
	world_root.add_child(anchor)
	rig.orthographic_size = 14.0
	rig.set_target(anchor)
	return world_root


func _world_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material


func _build_toasts(stage: Control) -> void:
	var system := NotificationSystemScript.new() as EconomyNotificationSystem
	stage.add_child(system)
	var ui := preload("res://scenes/ui/economy/economy_notification_ui.tscn").instantiate()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(ui)
	await process_frame
	if _failed:
		return
	ui.configure(system)
	for index in range(3):
		var target := "windmill:%d:%d" % [index + 1, index + 2]
		for count in range(3):
			system.push("completed", "生产完成", "风车 %d 完成面粉生产" % [index + 1], 9, "building", target, float(index * 10 + count))


func _build_empty_error(stage: Control) -> void:
	var wallet := root.get_node("GameState")
	var inventory := InventorySystemScript.new() as InventorySystem
	var market := MarketSystemScript.new() as MarketSystem
	var economy := EconomySystemScript.new() as EconomySystem
	for node in [inventory, market, economy]:
		stage.add_child(node)
	var definition: Dictionary = GameDataScript.get_item("wood").duplicate(true)
	definition.initial_stock = 2
	definition.target_stock = 80
	definition.daily_liquidity = 10
	market.configure([definition])
	economy.configure(inventory, wallet, market)
	inventory.add_item("wood", 30)
	var panel := preload("res://scenes/ui/economy/market_panel.tscn").instantiate()
	_content_host(stage).add_child(panel)
	await process_frame
	if _failed:
		return
	panel.configure(inventory, economy, market)
	var wood_row := panel.item_rows.get_node("ItemRow_wood") as Control
	(wood_row.get_node("Content/SelectButton") as Button).pressed.emit()
	panel.trade_panel.quantity_spin.value = 10
	panel.trade_panel.sell_button.pressed.emit()
	# A real authority mutation invalidates the open confirmation and produces
	# the failure feedback through the normal signal/refresh path.
	inventory.add_item("wood", 1)
	(panel.category_buttons["crops"] as Button).pressed.emit()


func _production_fixture(parent: Node) -> Dictionary:
	var grid := GridSystemScript.new() as GridSystem
	var farming := FarmingSystemScript.new() as FarmingSystem
	var inventory := InventorySystemScript.new() as InventorySystem
	var production := ProductionSystemScript.new() as ProductionSystem
	var progression := ProgressionSystemScript.new() as EconomyProgressionSystem
	for node in [grid, farming, inventory, production, progression]:
		parent.add_child(node)
	farming.configure(grid, null, null)
	production.configure(grid, farming, null, inventory)
	return {"grid": grid, "farming": farming, "inventory": inventory, "production": production, "progression": progression}


func _order_fixture(parent: Node, wallet: Node) -> Dictionary:
	var market := MarketSystemScript.new() as MarketSystem
	market.configure([
		_definition("iron_ore", 10), _definition("grain", 10), _definition("honey", 20),
	])
	var npc := NpcEconomySystemScript.new() as NpcEconomySystem
	npc.configure(market, [
		_profile("tiejiang_zhang", "铁匠张", {"iron_ore": 10}),
		_profile("lao_li", "老李", {"grain": 5}),
	], [])
	var inventory := InventorySystemScript.new() as InventorySystem
	inventory.add_item("iron_ore", 10)
	inventory.add_item("grain", 5)
	var economy := EconomySystemScript.new() as EconomySystem
	economy.configure(inventory, wallet, market, npc)
	for node in [market, npc, inventory, economy]:
		parent.add_child(node)
	market.settle_day(1)
	npc.sync_daily_cursor(1)
	economy.advance_order_deadlines(1)
	economy.generate_demand_orders(1)
	var state := economy.to_dict()
	state.contracts.append({
		"contract_id": "lao_li:grain:1:3", "npc_id": "lao_li", "item_id": "grain",
		"quantity_per_day": 5, "unit_price": 10, "reward_gold": 50,
		"start_day": 1, "end_day": 3, "delivered_days": [], "breaches": 0,
		"signed": false, "completed": false, "expired": false,
	})
	economy.from_dict(state)
	return {"market": market, "npc": npc, "inventory": inventory, "economy": economy}


func _unlock_station(progression: EconomyProgressionSystem, station: String) -> void:
	var state := progression.to_dict()
	if station not in state.unlocked_blueprints:
		state.unlocked_blueprints.append(station)
	for recipe in preload("res://scripts/core/recipe_database.gd").get_recipes_for_station(station):
		if str(recipe.id) not in state.unlocked_recipes:
			state.unlocked_recipes.append(str(recipe.id))
	progression.from_dict(state)


func _building(building_id: String, gx: int, gz: int) -> BuildingInstance:
	var definition: Dictionary = GameDataScript.get_building(building_id)
	var building := BuildingInstance.new()
	building.authored_building_id = building_id
	building.data = BuildingData.from_dictionary(definition)
	building.grid_x = gx
	building.grid_z = gz
	if str(definition.get("effect", "")) == "crafting":
		building.producer_state = ProducerStateScript.new(str(definition.get("station", building_id)))
	return building


func _definition(item_id: String, price: int) -> Dictionary:
	return {"id": item_id, "base_price": price, "initial_stock": 20, "target_stock": 20, "daily_liquidity": 10}


func _profile(npc_id: String, display_name: String, targets: Dictionary) -> Dictionary:
	return {
		"id": npc_id, "display_name": display_name, "gold": 0, "inventory": {},
		"essential_targets": {}, "reserve_targets": targets, "production_recipes": [],
		"sale_targets": {}, "investment_gold_threshold": 1000, "import_buffer": false,
	}


func _state_title(state_id: String) -> String:
	return {
		"market_normal": "市集 · 正常行情",
		"shortage_large_confirmation": "紧缺 · 大额交易确认",
		"running_producer": "建筑生产 · 正在加工",
		"full_maintenance_paused": "仓库已满 · 维护暂停",
		"orders_contracts": "订单与合同",
		"waterwheel_overlay": "水车 · 灌溉范围",
		"merged_toasts": "生产通知 · 三组已合并提醒",
		"empty_error": "空状态与错误反馈",
	}.get(state_id, state_id)


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	var wallet := root.get_node_or_null("GameState")
	if wallet != null and not _wallet_snapshot.is_empty():
		wallet.gold = _wallet_snapshot.gold
		wallet.player_state.level = _wallet_snapshot.level
	paused = false
	push_error(message)
	quit(1)
