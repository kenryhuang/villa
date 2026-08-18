extends RefCounted

const InventorySystemScript := preload("res://scripts/systems/inventory_system.gd")
const FarmStorageSystemScript := preload("res://scripts/systems/farm_storage_system.gd")
const InventoryUIScene := preload("res://scenes/ui/inventory_ui.tscn")


class StorageRowObserver:
	extends RefCounted
	var ui: InventoryUI
	var row_after_contents: Node

	func capture(_changes: Dictionary) -> void:
		if ui != null and ui.storage_rows.get_child_count() > 0:
			row_after_contents = ui.storage_rows.get_child(0)


func run(assertions: TestAssert, tree: SceneTree) -> void:
	await _test_scene_and_storage_content(assertions, tree)
	await _test_event_isolation_and_selection(assertions, tree)
	await _test_reconfigure_disconnects_previous_storage(assertions, tree)
	await _test_keyboard_input_contract(assertions, tree)
	await _test_storage_signal_refresh_coalescing(assertions, tree)


func _test_scene_and_storage_content(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var ui: InventoryUI = fixture.ui
	var storage: FarmStorageSystem = fixture.storage
	assertions.truthy(ui.tab_bar != null, "inventory scene exposes the compact tab bar")
	assertions.equal(ui.tab_bar.tab_count, 2, "inventory tab bar has exactly two options")
	assertions.truthy(ui.inventory_grid != null, "backpack grid remains present")
	assertions.truthy(ui.quick_bar != null, "backpack quick bar remains present")
	ui.open()
	assertions.truthy(ui.select_tab(&"farm_storage"), "farm storage tab can be selected")
	assertions.truthy(not ui.backpack_content.visible, "storage tab hides backpack content")
	assertions.truthy(ui.storage_content.visible, "storage tab shows storage content")

	assertions.truthy(storage.add_items({"tomato": 4, "grain": 2, "carrot": 7}), "storage fixture accepts crops")
	await tree.process_frame
	assertions.equal(ui.storage_capacity_label.text, "13 / 200", "storage capacity displays used and total")
	assertions.equal(_row_item_ids(ui), ["tomato", "carrot", "grain"], "name sort follows crop display names")
	assertions.equal(_row_text(ui, "tomato"), "番茄    x4", "storage row displays crop name and quantity")
	for row_value in ui.storage_rows.get_children():
		var row := row_value as Control
		assertions.truthy(not row is BaseButton, "storage crop rows are not actionable buttons")
		assertions.equal(row.mouse_filter, Control.MOUSE_FILTER_IGNORE, "storage crop rows ignore pointer input")
		assertions.truthy(not row.has_meta("slot_index"), "storage crop rows have no backpack slot identity")
		var icon := row.get_node("Icon") as TextureRect
		assertions.truthy(
			icon.texture != null and not icon.texture is PlaceholderTexture2D,
			"storage rows always expose visible non-debug fallback art"
		)
		if str(row.get_meta("item_id", "")) == "tomato" and icon.texture != null:
			var fallback_image := icon.texture.get_image()
			assertions.truthy(
				fallback_image != null
				and not fallback_image.is_empty()
				and fallback_image.get_used_rect().has_area(),
				"generated crop fallback contains visible pixels"
			)
		var text_label := row.get_node("Text") as Label
		assertions.equal(text_label.get_theme_color("font_color"), Color("#513B2F"), "storage row text stays readable on the light panel")

	ui.storage_sort.select(1)
	ui.storage_sort.item_selected.emit(1)
	assertions.equal(_row_item_ids(ui), ["carrot", "tomato", "grain"], "quantity sort is descending and deterministic")
	assertions.truthy(storage.restore_items_unchecked({"grain": 201}), "unchecked restore creates overload fixture")
	await tree.process_frame
	assertions.truthy(ui.storage_warning_label.visible, "overloaded storage shows a warning")
	assertions.equal(ui.storage_warning_label.text, "仓库超载 201 / 200", "overload warning includes exact capacity")
	assertions.equal(
		ui.storage_warning_label.get_theme_color("font_color"),
		Color("#B65C4B"),
		"overload warning uses the existing warning color"
	)
	_free_fixture(fixture)
	await tree.process_frame


func _test_event_isolation_and_selection(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var ui: InventoryUI = fixture.ui
	var inventory: InventorySystem = fixture.inventory
	var storage: FarmStorageSystem = fixture.storage
	assertions.truthy(storage.add_items({"grain": 3}), "event fixture adds initial crop")
	ui.open()
	assertions.truthy(ui.select_tab(&"farm_storage"), "event fixture selects storage")
	await tree.process_frame
	var backpack_slot := ui.inventory_grid.get_child(0)
	assertions.truthy(storage.add_items({"tomato": 2}), "storage event fixture adds another crop")
	await tree.process_frame
	assertions.truthy(is_instance_valid(backpack_slot), "storage events do not rebuild backpack slots")
	assertions.equal(_row_text(ui, "tomato"), "番茄    x2", "open storage tab refreshes from storage events")
	var storage_row: Node = ui.storage_rows.get_child(0)
	assertions.truthy(inventory.add_item("wood", 1), "inventory event fixture adds backpack item")
	await tree.process_frame
	assertions.truthy(is_instance_valid(storage_row), "backpack events do not rebuild storage rows")
	assertions.equal(ui.inventory_grid.get_child_count(), inventory.max_slots, "backpack event refresh keeps all slots")
	assertions.equal(ui.get_selected_tab(), &"farm_storage", "refresh preserves selected storage tab")
	ui.close()
	ui.open()
	assertions.equal(ui.get_selected_tab(), &"farm_storage", "reopen preserves selected tab in the session")
	assertions.truthy(not ui.select_tab(&"invalid"), "unknown inventory tab is rejected")
	assertions.equal(ui.get_selected_tab(), &"farm_storage", "rejected tab does not change selection")
	_free_fixture(fixture)
	await tree.process_frame


func _test_reconfigure_disconnects_previous_storage(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var ui: InventoryUI = fixture.ui
	var inventory: InventorySystem = fixture.inventory
	var old_storage: FarmStorageSystem = fixture.storage
	var replacement := FarmStorageSystemScript.new() as FarmStorageSystem
	tree.root.add_child(replacement)
	assertions.truthy(replacement.configure(), "replacement storage configures")
	assertions.truthy(replacement.add_items({"carrot": 5}), "replacement storage accepts crop")
	ui.call("configure", inventory, replacement)
	assertions.equal(_method_argument_count(ui, &"configure"), 2, "inventory UI configure accepts inventory and storage")
	ui.open()
	ui.select_tab(&"farm_storage")
	await tree.process_frame
	assertions.equal(_row_item_ids(ui), ["carrot"], "reconfigure displays replacement storage")
	var replacement_row: Node = ui.storage_rows.get_child(0)
	assertions.truthy(old_storage.add_items({"grain": 1}), "detached storage still mutates")
	await tree.process_frame
	assertions.truthy(is_instance_valid(replacement_row), "detached storage events no longer refresh the UI")
	assertions.equal(_row_item_ids(ui), ["carrot"], "detached storage cannot replace visible rows")
	_free_fixture(fixture)
	replacement.free()
	await tree.process_frame


func _test_keyboard_input_contract(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var ui: InventoryUI = fixture.ui
	for keycode in [KEY_TAB, KEY_I, KEY_ESCAPE]:
		ui.open()
		var echoed := InputEventKey.new()
		echoed.keycode = keycode
		echoed.pressed = true
		echoed.echo = true
		ui.call("_unhandled_input", echoed)
		assertions.truthy(ui.visible, "echoed %s does not change inventory visibility" % keycode)
	ui.open()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ui.call("_unhandled_input", escape)
	assertions.truthy(not ui.visible, "Escape closes the visible inventory")
	_free_fixture(fixture)
	await tree.process_frame


func _test_storage_signal_refresh_coalescing(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _make_fixture(tree)
	var ui: InventoryUI = fixture.ui
	var storage: FarmStorageSystem = fixture.storage
	ui.open()
	ui.select_tab(&"farm_storage")
	var observer := StorageRowObserver.new()
	observer.ui = ui
	storage.contents_changed.connect(observer.capture)
	assertions.truthy(storage.add_items({"grain": 3}), "coalescing fixture adds a crop")
	assertions.truthy(
		is_instance_valid(observer.row_after_contents),
		"capacity notification keeps the row built by contents notification"
	)
	assertions.truthy(
		observer.row_after_contents == ui.storage_rows.get_child(0),
		"contents and capacity notifications produce one row rebuild"
	)
	var row_before_capacity: Node = ui.storage_rows.get_child(0)
	assertions.truthy(storage.configure(func() -> int: return 300), "capacity-only fixture reconfigures storage")
	assertions.equal(ui.storage_capacity_label.text, "3 / 300", "capacity-only notification refreshes capacity text")
	assertions.truthy(
		is_instance_valid(row_before_capacity) and row_before_capacity == ui.storage_rows.get_child(0),
		"capacity-only notification does not rebuild storage rows"
	)
	_free_fixture(fixture)
	await tree.process_frame


func _make_fixture(tree: SceneTree) -> Dictionary:
	var inventory := InventorySystemScript.new() as InventorySystem
	var storage := FarmStorageSystemScript.new() as FarmStorageSystem
	var ui := InventoryUIScene.instantiate() as InventoryUI
	tree.root.add_child(inventory)
	tree.root.add_child(storage)
	tree.root.add_child(ui)
	storage.configure()
	if _method_argument_count(ui, &"configure") >= 2:
		ui.call("configure", inventory, storage)
	else:
		ui.configure(inventory)
	await tree.process_frame
	return {"inventory": inventory, "storage": storage, "ui": ui}


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.ui as Node).free()
	(fixture.storage as Node).free()
	(fixture.inventory as Node).free()


func _row_item_ids(ui: InventoryUI) -> Array[String]:
	var result: Array[String] = []
	for row in ui.storage_rows.get_children():
		result.append(str(row.get_meta("item_id", "")))
	return result


func _row_text(ui: InventoryUI, item_id: String) -> String:
	for row in ui.storage_rows.get_children():
		if str(row.get_meta("item_id", "")) == item_id:
			return str((row.get_node("Text") as Label).text)
	return ""


func _method_argument_count(target: Object, method_name: StringName) -> int:
	for method_value in target.get_method_list():
		var method := method_value as Dictionary
		if StringName(method.get("name", &"")) == method_name:
			return (method.get("args", []) as Array).size()
	return -1
