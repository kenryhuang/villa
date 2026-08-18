extends RefCounted

const GameDataScript := preload("res://scripts/core/game_data.gd")
const InventorySystemScript := preload("res://scripts/systems/inventory_system.gd")
const FarmingSystemScript := preload("res://scripts/systems/farming_system.gd")
const ControllerScript := preload("res://scripts/actors/player_action_controller.gd")
const HudScene := preload("res://scenes/ui/hud.tscn")

const VIEWPORT_SIZES := [Vector2i(1920, 1080), Vector2i(640, 960)]
var _registered_crop_ids: Array[String] = []


class SeasonDouble:
	extends RefCounted
	var current_season := 1


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_ensure_crop("grain", "grain_seed", "谷物", 3, [0, 1], "outdoor_or_greenhouse")
	_ensure_crop("carrot", "carrot_seed", "胡萝卜", 4, [0], "outdoor_or_greenhouse")
	_ensure_crop("lemon", "lemon_sapling", "柠檬", 5, [], "greenhouse_only", "tree", 3)
	await _test_owned_seed_rows_and_selection(assertions, tree)
	await _test_controller_command_and_legacy_migration(assertions, tree)
	await _test_hud_selection_survives_zero_quantity(assertions, tree)
	await _test_topmost_escape_and_pause_restore(assertions, tree)
	_cleanup_registered_crops()


func run_responsive(assertions: TestAssert, tree: SceneTree) -> void:
	_ensure_crop("grain", "grain_seed", "谷物", 3, [0, 1], "outdoor_or_greenhouse")
	_ensure_crop("carrot", "carrot_seed", "胡萝卜", 4, [0], "outdoor_or_greenhouse")
	_ensure_crop("lemon", "lemon_sapling", "柠檬", 5, [], "greenhouse_only", "tree", 3)
	for viewport_size in VIEWPORT_SIZES:
		var fixture := await _make_fixture(tree, viewport_size)
		var panel = fixture.panel
		assertions.truthy(panel != null, "seed selector scene instantiates at %s" % viewport_size)
		if panel == null:
			_free_fixture(fixture)
			continue
		panel.open_for_cell(fixture.cell)
		await tree.process_frame
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
		var shell := panel.get_node("Overlay/Center/Shell") as Control
		var header := panel.get_node("Overlay/Center/Shell/Layout/Header") as Control
		var list_scroll := panel.get_node("Overlay/Center/Shell/Layout/SeedScroll") as Control
		var footer := panel.get_node("Overlay/Center/Shell/Layout/Footer") as Control
		for control in [shell, header, list_scroll, footer]:
			assertions.truthy(
				viewport_rect.encloses((control as Control).get_global_rect()),
				"seed selector %s stays inside %s: %s"
				% [(control as Control).name, viewport_size, (control as Control).get_global_rect()]
			)
		assertions.truthy(
			not header.get_global_rect().intersects(list_scroll.get_global_rect())
			and not list_scroll.get_global_rect().intersects(footer.get_global_rect()),
			"seed selector sections do not overlap at %s" % viewport_size
		)
		for row_value in panel.seed_rows.get_children():
			var row := row_value as Control
			if not row.has_meta("plant_item_id"):
				continue
			assertions.truthy(
				shell.get_global_rect().encloses(row.get_global_rect()),
				"seed row %s stays inside shell at %s" % [row.name, viewport_size]
			)
			var previous_rect := Rect2()
			for child_value in row.get_children():
				var child := child_value as Control
				var child_rect := child.get_global_rect()
				assertions.truthy(
					row.get_global_rect().encloses(child_rect),
					"seed row %s keeps %s unclipped at %s" % [row.name, child.name, viewport_size]
				)
				if previous_rect.has_area():
					assertions.truthy(
						not previous_rect.intersects(child_rect),
						"seed row %s controls do not overlap at %s" % [row.name, viewport_size]
					)
				previous_rect = child_rect
		_free_fixture(fixture)
		await tree.process_frame
	_cleanup_registered_crops()


func _test_owned_seed_rows_and_selection(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var panel = fixture.panel
	assertions.truthy(panel != null, "dedicated seed selector scene exists")
	if panel == null:
		_free_fixture(fixture)
		return
	assertions.truthy(
		panel.configure(fixture.inventory, fixture.farming, fixture.controller),
		"seed selector accepts authoritative dependencies"
	)
	panel.open_for_cell(fixture.cell)
	await tree.process_frame
	assertions.equal(_row_ids(panel), ["carrot_seed", "grain_seed", "lemon_sapling"], "selector lists only owned mapped positive seed items")
	assertions.equal(_row(panel, "carrot_seed").get_meta("disabled_reason"), "wrong_season", "out-of-season seed keeps stable disabled reason")
	assertions.equal(_row(panel, "lemon_sapling").get_meta("disabled_reason"), "greenhouse_required", "greenhouse seed keeps stable disabled reason")
	assertions.equal(_row(panel, "grain_seed").get_meta("disabled_reason"), "", "compatible seed remains selectable")
	for item_id in _row_ids(panel):
		var row := _row(panel, item_id)
		assertions.truthy((row.get_node("Icon") as TextureRect).texture != null, "%s row has a visible icon" % item_id)
		assertions.truthy(not (row.get_node("Name") as Label).text.is_empty(), "%s row shows a name" % item_id)
		assertions.truthy((row.get_node("Quantity") as Label).text.begins_with("×"), "%s row shows quantity" % item_id)
		assertions.truthy((row.get_node("Growth") as Label).text.contains("天"), "%s row shows first growth days" % item_id)
		assertions.truthy(not (row.get_node("Seasons") as Label).text.is_empty(), "%s row shows seasons" % item_id)
		assertions.truthy(not (row.get_node("Environment") as Label).text.is_empty(), "%s row shows environment" % item_id)
	var before: int = fixture.inventory.get_item_count("grain_seed")
	assertions.truthy(not panel.select_seed("carrot_seed"), "disabled target seed cannot be confirmed")
	assertions.truthy(panel.select_seed("grain_seed"), "compatible seed can be explicitly confirmed")
	assertions.equal(fixture.controller.get_selected_plant_item_id(), "grain_seed", "confirmation stores the plant item ID")
	assertions.equal(fixture.inventory.get_item_count("grain_seed"), before, "selection never consumes or moves seed inventory")
	_free_fixture(fixture)
	await tree.process_frame


func _test_controller_command_and_legacy_migration(assertions: TestAssert, tree: SceneTree) -> void:
	var inventory := InventorySystemScript.new() as InventorySystem
	var farming := FarmingSystemScript.new() as FarmingSystem
	var controller := ControllerScript.new() as PlayerActionController
	tree.root.add_child(inventory)
	tree.root.add_child(farming)
	tree.root.add_child(controller)
	inventory.add_item("wood", 1)
	inventory.add_item("grain_seed", 2)
	var wood_slot := _inventory_slot(inventory, "wood")
	var seed_slot := _inventory_slot(inventory, "grain_seed")
	inventory.set_quick_slot(wood_slot, 0)
	controller.configure(null, null, farming, null, null, inventory, null)
	inventory.set_quick_slot(seed_slot, PlayerActionController.SEED_SLOT)
	assertions.truthy(controller.has_signal("seed_selection_requested"), "controller exposes seed selector request signal")
	var requests: Array = []
	if controller.has_signal("seed_selection_requested"):
		controller.seed_selection_requested.connect(func(cell): requests.append(cell))
	assertions.truthy(controller.select_mode_slot(PlayerActionController.SEED_SLOT), "slot 6 enters planting command")
	assertions.equal(requests.size(), 1, "entering planting command requests the selector once")
	assertions.truthy(controller.has_method("migrate_legacy_seed_quick_slot"), "controller exposes one-shot legacy seed migration")
	if controller.has_method("migrate_legacy_seed_quick_slot"):
		assertions.truthy(controller.migrate_legacy_seed_quick_slot(), "legacy slot 6 seed mapping migrates")
		assertions.equal(controller.get_selected_plant_item_id(), "grain_seed", "migration initializes independent seed selection")
		assertions.equal(inventory.get_quick_item(PlayerActionController.SEED_SLOT), "", "migration clears obsolete slot 6 mapping")
		assertions.equal(inventory.get_quick_item(0), "wood", "migration preserves slots 1-5")
	inventory.free()
	controller.free()
	farming.free()
	await tree.process_frame


func _test_hud_selection_survives_zero_quantity(assertions: TestAssert, tree: SceneTree) -> void:
	var inventory := InventorySystemScript.new() as InventorySystem
	var farming := FarmingSystemScript.new() as FarmingSystem
	var controller := ControllerScript.new() as PlayerActionController
	var hud = HudScene.instantiate()
	tree.root.add_child(inventory)
	tree.root.add_child(farming)
	tree.root.add_child(controller)
	tree.root.add_child(hud)
	inventory.add_item("grain_seed", 2)
	controller.configure(null, null, farming, null, null, inventory, null)
	assertions.truthy(controller.set_selected_plant_item_id("grain_seed"), "HUD fixture selects grain independently")
	hud.configure_action_bar(controller, inventory)
	assertions.equal(hud.get_active_plant_item_display(), "谷物种子 ×2", "HUD slot 6 shows selected seed and total quantity")
	inventory.remove_item("grain_seed", 2)
	hud.refresh_action_bar()
	assertions.equal(controller.get_selected_plant_item_id(), "grain_seed", "selected seed ID remains after quantity reaches zero")
	assertions.equal(hud.get_active_plant_item_display(), "谷物种子 ×0", "HUD slot 6 refreshes selected seed to zero quantity")
	var seed_button = hud.quick_bar.get_child(PlayerActionController.SEED_SLOT)
	assertions.truthy((seed_button.icon_rect as TextureRect).texture != null, "HUD selected seed retains a visible icon")
	hud.free()
	controller.free()
	farming.free()
	inventory.free()
	await tree.process_frame


func _test_topmost_escape_and_pause_restore(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var panel = fixture.panel
	panel.open_for_cell(fixture.cell)
	await tree.process_frame
	assertions.truthy(tree.paused, "open selector pauses lower gameplay input")
	var focus_owner: Control = panel.get_viewport().gui_get_focus_owner()
	assertions.truthy(focus_owner != null and panel.overlay.is_ancestor_of(focus_owner), "open selector traps focus inside the top modal")
	var echoed := InputEventKey.new()
	echoed.keycode = KEY_ESCAPE
	echoed.pressed = true
	echoed.echo = true
	panel._unhandled_input(echoed)
	assertions.truthy(panel.visible, "echoed Escape cannot close the selector")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	panel._unhandled_input(escape)
	assertions.truthy(not panel.visible, "topmost Escape closes the seed selector")
	assertions.truthy(not tree.paused, "closing selector restores an originally running tree")
	tree.paused = true
	panel.open_for_cell()
	panel.close()
	assertions.truthy(tree.paused, "closing selector preserves an originally paused tree")
	tree.paused = false
	_free_fixture(fixture)
	await tree.process_frame


func _make_fixture(tree: SceneTree, viewport_size: Vector2i = Vector2i.ZERO) -> Dictionary:
	var host: Node = tree.root
	if viewport_size != Vector2i.ZERO:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		tree.root.add_child(viewport)
		host = viewport
	var inventory := InventorySystemScript.new() as InventorySystem
	var farming := FarmingSystemScript.new() as FarmingSystem
	var controller := ControllerScript.new() as PlayerActionController
	host.add_child(inventory)
	host.add_child(farming)
	host.add_child(controller)
	farming.season_system = SeasonDouble.new()
	inventory.add_item("grain_seed", 3)
	inventory.add_item("carrot_seed", 2)
	inventory.add_item("lemon_sapling", 1)
	inventory.add_item("wood", 4)
	controller.configure(null, null, farming, null, null, inventory, null)
	var cell := GridCell.new()
	cell.gx = 4
	cell.gz = 7
	cell.state = GridCell.State.FARMLAND
	var scene := load("res://scenes/ui/seed_selector_panel.tscn") as PackedScene
	var panel = scene.instantiate() if scene != null else null
	if panel != null:
		host.add_child(panel)
		panel.configure(inventory, farming, controller)
	await tree.process_frame
	return {"host": host, "panel": panel, "inventory": inventory, "farming": farming, "controller": controller, "cell": cell}


func _free_fixture(fixture: Dictionary) -> void:
	var host: Node = fixture.get("host")
	if host is SubViewport:
		host.free()
		return
	for key in ["panel", "controller", "farming", "inventory"]:
		var node: Node = fixture.get(key)
		if is_instance_valid(node):
			node.free()


func _row_ids(panel) -> Array[String]:
	var result: Array[String] = []
	for row in panel.seed_rows.get_children():
		var item_id := str(row.get_meta("plant_item_id", ""))
		if not item_id.is_empty():
			result.append(item_id)
	return result


func _row(panel, plant_item_id: String) -> Control:
	for row_value in panel.seed_rows.get_children():
		var row := row_value as Control
		if str(row.get_meta("plant_item_id", "")) == plant_item_id:
			return row
	return null


func _inventory_slot(inventory: InventorySystem, item_id: String) -> int:
	for index in range(inventory.slots.size()):
		if str(inventory.slots[index].get("item_id", "")) == item_id:
			return index
	return -1


func _ensure_crop(
	crop_id: String,
	plant_item_id: String,
	display_name: String,
	growth_days: int,
	seasons: Array,
	environment: String,
	lifecycle_type: String = "annual",
	regrow_days: int = 0
) -> void:
	var game_data: Node = Engine.get_main_loop().root.get_node_or_null("GameData")
	if game_data == null or game_data.get_crop_for_plant_item(plant_item_id) != null:
		return
	var crop := CropData.new()
	crop.crop_id = crop_id
	crop.plant_item_id = plant_item_id
	crop.name = display_name
	crop.crop_name = display_name
	crop.category = "fruit" if lifecycle_type == "tree" else "field_crop"
	crop.growth_days = growth_days
	crop.seasons.assign(seasons)
	crop.environment = environment
	crop.lifecycle_type = lifecycle_type
	crop.growth_form = lifecycle_type if lifecycle_type != "annual" else "annual"
	crop.regrow_days = regrow_days
	if environment == "greenhouse_only":
		crop.tags.assign(["greenhouse_only"])
	if game_data.register_crop(crop):
		_registered_crop_ids.append(crop_id)


func _cleanup_registered_crops() -> void:
	if _registered_crop_ids.is_empty():
		return
	var game_data: Node = Engine.get_main_loop().root.get_node_or_null("GameData")
	if game_data == null:
		return
	var crops: Dictionary = game_data.get("_crops")
	var crops_by_item: Dictionary = game_data.get("_crops_by_plant_item")
	for crop_id in _registered_crop_ids:
		var crop := crops.get(crop_id) as CropData
		if crop != null:
			crops_by_item.erase(crop.plant_item_id)
		crops.erase(crop_id)
	_registered_crop_ids.clear()
