extends RefCounted

const GameDataScript := preload("res://scripts/core/game_data.gd")
const InventorySystemScript := preload("res://scripts/systems/inventory_system.gd")
const FarmingSystemScript := preload("res://scripts/systems/farming_system.gd")
const ControllerScript := preload("res://scripts/actors/player_action_controller.gd")
const HudScene := preload("res://scenes/ui/hud.tscn")
const SeedCardScript := preload("res://scripts/ui/seed_card.gd")

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
	await _test_inventory_refresh_is_deferred_and_coalesced(assertions, tree)
	await _test_reenter_reconnects_authoritative_events(assertions, tree)
	await _test_controller_command_and_legacy_migration(assertions, tree)
	await _test_hud_selection_survives_zero_quantity(assertions, tree)
	await _test_topmost_escape_and_pause_restore(assertions, tree)
	await _test_off_tree_configure_binds_authoritative_events_on_ready(assertions, tree)
	await _test_reconfigure_after_old_dependencies_are_freed(assertions, tree)
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
		assertions.truthy(not panel.has_node("Overlay/Center/Shell/Layout/ColumnHeader"), "seed selector removes the dense table header")
		assertions.truthy(panel.seed_rows is GridContainer, "seed selector owns a responsive card grid")
		if panel.seed_rows is GridContainer:
			assertions.equal(panel.seed_rows.columns, 2 if viewport_size.x >= 900 else 1, "seed selector chooses responsive card columns at %s" % viewport_size)
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
			assertions.truthy(row is SeedCardScript, "seed entry is a reusable card at %s" % viewport_size)
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
	var uses_cards := true
	for item_id in _row_ids(panel):
		uses_cards = uses_cards and _row(panel, item_id) is SeedCardScript
	assertions.truthy(uses_cards, "all selector entries use the reusable seed card")
	if not uses_cards:
		_free_fixture(fixture)
		await tree.process_frame
		return
	for item_id in _row_ids(panel):
		var row := _row(panel, item_id)
		assertions.truthy(row is SeedCardScript, "%s uses the seed card component" % item_id)
		assertions.truthy((row.get_node("Content/Icon") as TextureRect).texture != null, "%s card has a visible icon" % item_id)
		assertions.truthy(not (row.get_node("Content/Details/NameRow/Name") as Label).text.is_empty(), "%s card shows a name" % item_id)
		assertions.truthy(_quantity_label(row).text.begins_with("×"), "%s card shows quantity" % item_id)
		var metadata := (row.get_node("Content/Details/Metadata") as Label).text
		assertions.truthy(metadata.contains("成熟约 30 秒"), "%s card shows real-time growth" % item_id)
		assertions.truthy(metadata.contains("浇水约 20 秒"), "%s card shows watering bonus" % item_id)
		assertions.truthy(metadata.contains("·"), "%s card groups season and environment metadata" % item_id)
	var before: int = fixture.inventory.get_item_count("grain_seed")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_row(panel, "carrot_seed").gui_input.emit(click)
	assertions.truthy(panel.visible, "disabled whole-card click keeps the selector open")
	assertions.truthy(((_row(panel, "carrot_seed").get_node("Content/Details/Status") as Label).text).contains("季节"), "disabled card keeps a clear red reason")
	_row(panel, "grain_seed").gui_input.emit(click)
	assertions.truthy(not panel.visible, "enabled whole-card click confirms and closes")
	assertions.equal(fixture.controller.get_selected_plant_item_id(), "grain_seed", "confirmation stores the plant item ID")
	assertions.equal(fixture.inventory.get_item_count("grain_seed"), before, "selection never consumes or moves seed inventory")
	_free_fixture(fixture)
	await tree.process_frame


func _test_inventory_refresh_is_deferred_and_coalesced(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var panel = fixture.panel
	assertions.truthy(panel != null, "refresh gating fixture instantiates the selector")
	if panel == null:
		_free_fixture(fixture)
		return
	panel.open_for_cell(fixture.cell)
	await tree.process_frame
	var hidden_row_ids := _row_instance_ids(panel)
	var initial_grain_quantity: int = fixture.inventory.get_item_count("grain_seed")
	panel.close()
	assertions.truthy(fixture.inventory.remove_item("grain_seed", 1), "hidden refresh fixture removes one seed")
	await tree.process_frame
	assertions.equal(
		_row_instance_ids(panel),
		hidden_row_ids,
		"hidden selector keeps existing seed row instances until reopened"
	)
	panel.open_for_cell(fixture.cell)
	await tree.process_frame
	var reopened_row := _row(panel, "grain_seed")
	assertions.truthy(reopened_row != null, "reopened selector renders remaining seed row")
	if reopened_row != null:
		assertions.equal(
			_quantity_label(reopened_row).text,
			"×%d" % (initial_grain_quantity - 1),
			"reopened selector reads the authoritative seed quantity"
		)

	var visible_row_ids := _row_instance_ids(panel)
	var quantity_before_batch: int = fixture.inventory.get_item_count("grain_seed")
	var rebuilt_row_instance_ids: Array[int] = []
	var row_enter_callback := func(child: Node) -> void:
		if child.has_meta("plant_item_id"):
			rebuilt_row_instance_ids.append(child.get_instance_id())
	panel.seed_rows.child_entered_tree.connect(row_enter_callback)
	assertions.truthy(fixture.inventory.add_item("grain_seed", 2), "visible refresh fixture adds two seeds")
	assertions.truthy(fixture.inventory.remove_item("grain_seed", 1), "visible refresh fixture removes one seed")
	assertions.equal(
		_row_instance_ids(panel),
		visible_row_ids,
		"visible seed changes do not rebuild rows before the deferred frame"
	)
	await tree.process_frame
	assertions.equal(
		rebuilt_row_instance_ids.size(),
		visible_row_ids.size(),
		"coalesced seed changes perform exactly one complete row rebuild"
	)
	var batched_row := _row(panel, "grain_seed")
	assertions.truthy(batched_row != null, "coalesced refresh keeps the seed row visible")
	if batched_row != null:
		assertions.equal(
			_quantity_label(batched_row).text,
			"×%d" % (quantity_before_batch + 1),
			"coalesced refresh shows the final authoritative quantity"
		)
	if panel.seed_rows.child_entered_tree.is_connected(row_enter_callback):
		panel.seed_rows.child_entered_tree.disconnect(row_enter_callback)
	_free_fixture(fixture)
	await tree.process_frame


func _test_reenter_reconnects_authoritative_events(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var panel = fixture.panel
	assertions.truthy(panel != null, "reenter refresh fixture instantiates the selector")
	if panel == null:
		_free_fixture(fixture)
		return
	var host: Node = fixture.host
	host.remove_child(panel)
	host.add_child(panel)
	panel.open_for_cell(fixture.cell)
	await tree.process_frame
	var before_quantity: int = fixture.inventory.get_item_count("grain_seed")
	var before_row_ids := _row_instance_ids(panel)
	var rebuilt_row_instance_ids: Array[int] = []
	var row_enter_callback := func(child: Node) -> void:
		if child.has_meta("plant_item_id"):
			rebuilt_row_instance_ids.append(child.get_instance_id())
	panel.seed_rows.child_entered_tree.connect(row_enter_callback)
	assertions.truthy(fixture.inventory.add_item("grain_seed", 1), "reentered selector receives a seed event")
	assertions.equal(
		_row_instance_ids(panel),
		before_row_ids,
		"reentered selector defers the seed row rebuild until the frame"
	)
	await tree.process_frame
	assertions.equal(
		rebuilt_row_instance_ids.size(),
		before_row_ids.size(),
		"reentered selector performs one complete deferred rebuild"
	)
	var row := _row(panel, "grain_seed")
	assertions.truthy(row != null, "reentered selector keeps the changed seed row visible")
	if row != null:
		assertions.equal(
			_quantity_label(row).text,
			"×%d" % (before_quantity + 1),
			"reentered selector refreshes from the authoritative inventory"
		)
	if panel.seed_rows.child_entered_tree.is_connected(row_enter_callback):
		panel.seed_rows.child_entered_tree.disconnect(row_enter_callback)
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
	assertions.truthy(
		controller.switch_mode(PlayerActionController.ActionMode.FARMING),
		"seed command fixture explicitly enters farming mode"
	)
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
	assertions.truthy(
		controller.switch_mode(PlayerActionController.ActionMode.FARMING),
		"HUD seed fixture explicitly enters farming mode"
	)
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


func _test_off_tree_configure_binds_authoritative_events_on_ready(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var inventory := InventorySystemScript.new() as InventorySystem
	var farming := FarmingSystemScript.new() as FarmingSystem
	var controller := ControllerScript.new() as PlayerActionController
	tree.root.add_child(inventory)
	tree.root.add_child(farming)
	tree.root.add_child(controller)
	farming.season_system = SeasonDouble.new()
	inventory.add_item("grain_seed", 3)
	controller.configure(null, null, farming, null, null, inventory, null)
	controller.set_selected_plant_item_id("grain_seed")
	var scene := load("res://scenes/ui/seed_selector_panel.tscn") as PackedScene
	var panel = scene.instantiate()
	assertions.truthy(
		panel.configure(inventory, farming, controller),
		"seed selector accepts authoritative dependencies before entering the tree"
	)
	tree.root.add_child(panel)
	panel.open_for_cell()
	await tree.process_frame
	var row := _row(panel, "grain_seed")
	assertions.truthy(row != null, "off-tree configured selector refreshes initial rows on ready")
	if row != null:
		assertions.equal(_quantity_label(row).text, "×3", "off-tree configured selector shows initial quantity")
	assertions.truthy(inventory.add_item("grain_seed", 2), "off-tree event fixture adds selected seed")
	await tree.process_frame
	row = _row(panel, "grain_seed")
	assertions.truthy(row != null, "authoritative add event keeps the selected seed row visible")
	if row != null:
		assertions.equal(_quantity_label(row).text, "×5", "authoritative add event refreshes selector quantity")
	assertions.truthy(inventory.remove_item("grain_seed", 5), "off-tree event fixture drains selected seed")
	await tree.process_frame
	assertions.truthy(_row(panel, "grain_seed") == null, "authoritative remove event removes zero-quantity seed row")
	assertions.truthy(panel.selection_status.text.contains("库存不足"), "authoritative remove event refreshes selected no-seed state")
	panel.close()
	panel.free()
	controller.free()
	farming.free()
	inventory.free()
	await tree.process_frame


func _test_reconfigure_after_old_dependencies_are_freed(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var panel_source := FileAccess.get_file_as_string("res://scripts/ui/seed_selector_panel.gd")
	assertions.truthy(
		panel_source.contains("is_instance_valid(action_controller_ref)"),
		"selector explicitly guards a freed old action controller before disconnect"
	)
	var scene := load("res://scenes/ui/seed_selector_panel.tscn") as PackedScene
	var panel = scene.instantiate()
	tree.root.add_child(panel)
	var old_inventory := InventorySystemScript.new() as InventorySystem
	var old_farming := FarmingSystemScript.new() as FarmingSystem
	var old_controller := ControllerScript.new() as PlayerActionController
	tree.root.add_child(old_inventory)
	tree.root.add_child(old_farming)
	tree.root.add_child(old_controller)
	old_farming.season_system = SeasonDouble.new()
	old_inventory.add_item("grain_seed", 1)
	old_controller.configure(null, null, old_farming, null, null, old_inventory, null)
	assertions.truthy(panel.configure(old_inventory, old_farming, old_controller), "selector configures with the original dependencies")
	assertions.truthy(panel.configure(old_inventory, old_farming, old_controller), "repeated configure is idempotent")
	var callback := Callable(panel, "_on_plant_selection_changed")
	assertions.equal(
		old_controller.plant_selection_changed.get_connections().filter(
			func(connection: Dictionary) -> bool: return connection.get("callable") == callback
		).size(),
		1,
		"repeated configure keeps one old-controller callback"
	)
	old_controller.free()
	old_farming.free()
	old_inventory.free()

	var replacement_inventory := InventorySystemScript.new() as InventorySystem
	var replacement_farming := FarmingSystemScript.new() as FarmingSystem
	var replacement_controller := ControllerScript.new() as PlayerActionController
	tree.root.add_child(replacement_inventory)
	tree.root.add_child(replacement_farming)
	tree.root.add_child(replacement_controller)
	replacement_farming.season_system = SeasonDouble.new()
	replacement_inventory.add_item("grain_seed", 4)
	replacement_controller.configure(
		null,
		null,
		replacement_farming,
		null,
		null,
		replacement_inventory,
		null
	)
	var reconfigured: Variant = panel.configure(
		replacement_inventory,
		replacement_farming,
		replacement_controller
	)
	assertions.truthy(bool(reconfigured), "selector safely reconfigures after every old dependency is freed")
	panel.open_for_cell()
	await tree.process_frame
	var replacement_row := _row(panel, "grain_seed")
	assertions.truthy(replacement_row != null, "reconfigured selector renders replacement inventory")
	if replacement_row != null:
		assertions.equal(_quantity_label(replacement_row).text, "×4", "reconfigured selector uses replacement quantity")
	panel.close()
	panel.free()
	replacement_controller.free()
	replacement_farming.free()
	replacement_inventory.free()
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


func _row_instance_ids(panel) -> Array[int]:
	var result: Array[int] = []
	for row in panel.seed_rows.get_children():
		if row.has_meta("plant_item_id"):
			result.append(row.get_instance_id())
	return result


func _row(panel, plant_item_id: String) -> Control:
	for row_value in panel.seed_rows.get_children():
		var row := row_value as Control
		if str(row.get_meta("plant_item_id", "")) == plant_item_id:
			return row
	return null


func _quantity_label(card: Control) -> Label:
	var nested := card.get_node_or_null("Content/Details/NameRow/Quantity") as Label
	return nested if nested != null else card.get_node_or_null("Quantity") as Label


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
