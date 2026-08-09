extends RefCounted

const DebugPanelScene := preload("res://scenes/ui/debug_panel.tscn")

const REQUIRED_NODES: Array[String] = [
	"Overlay/Center/Panel/Layout/Header/Title",
	"Overlay/Center/Panel/Layout/Header/CloseButton",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Level",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/ElapsedDays",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Gold",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Stamina",
	"Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Search",
	"Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Category",
	"Overlay/Center/Panel/Layout/Tabs/Inventory/ItemScroll/ItemRows",
	"Overlay/Center/Panel/Layout/Footer/Status",
	"Overlay/Center/Panel/Layout/Footer/RefreshButton",
	"Overlay/Center/Panel/Layout/Footer/CancelButton",
	"Overlay/Center/Panel/Layout/Footer/ApplyButton",
]


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var panel := DebugPanelScene.instantiate()
	tree.root.add_child(panel)
	for node_path in REQUIRED_NODES:
		assertions.truthy(panel.has_node(node_path), "debug panel authors %s" % node_path)
	var snapshot := _snapshot()
	assertions.truthy(panel.configure(snapshot), "debug panel accepts a complete snapshot")
	assertions.equal(panel.get_visible_item_ids().size(), 3, "debug panel authors every item row")
	panel.open()
	assertions.truthy(panel.visible, "debug panel opens")

	(panel.get_node("Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Level") as SpinBox).value = 4
	(panel.get_node("Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/ElapsedDays") as SpinBox).value = 28
	(panel.get_node("Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Gold") as SpinBox).value = 9000
	(panel.get_node("Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Stamina") as SpinBox).value = 23
	var wood_editor := _item_editor(panel, "wood")
	assertions.truthy(wood_editor != null, "wood row owns a quantity editor")
	if wood_editor != null:
		wood_editor.value = 145
	var draft: Dictionary = panel.build_draft()
	assertions.equal(draft.level, 4, "draft reads edited level")
	assertions.equal(draft.elapsed_days, 28, "draft reads edited elapsed days")
	assertions.equal(draft.gold, 9000, "draft reads edited gold")
	assertions.equal(draft.stamina, 23, "draft reads edited stamina")
	assertions.equal((draft.items.wood as Dictionary).quantity, 145, "draft reads edited resource")

	var search := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Search"
	) as LineEdit
	search.text = "木"
	search.text_changed.emit(search.text)
	assertions.equal(panel.get_visible_item_ids(), ["wood"], "Chinese search filters item rows")
	assertions.equal((panel.build_draft().items.wood as Dictionary).quantity, 145, "filter keeps hidden draft values")
	search.text = ""
	search.text_changed.emit(search.text)
	var category := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Category"
	) as OptionButton
	var seed_index := _option_index(category, "seed")
	assertions.truthy(seed_index >= 0, "category filter includes seed category")
	if seed_index >= 0:
		category.select(seed_index)
		category.item_selected.emit(seed_index)
		assertions.equal(panel.get_visible_item_ids(), ["grain_seed"], "category filters item rows")

	var apply_requests: Array[Dictionary] = []
	var refresh_requests: Array[bool] = []
	panel.apply_requested.connect(
		func(requested: Dictionary) -> void:
			apply_requests.append(requested)
	)
	panel.refresh_requested.connect(
		func() -> void:
			refresh_requests.append(true)
	)
	(panel.get_node("Overlay/Center/Panel/Layout/Footer/ApplyButton") as Button).pressed.emit()
	(panel.get_node("Overlay/Center/Panel/Layout/Footer/RefreshButton") as Button).pressed.emit()
	assertions.equal(apply_requests.size(), 1, "apply emits one complete draft")
	assertions.equal(refresh_requests.size(), 1, "refresh emits one snapshot request")

	panel.show_apply_result(
		{"ok": true, "message": "调试数据已应用；尚未写入存档"},
		snapshot
	)
	var status := panel.get_node("Overlay/Center/Panel/Layout/Footer/Status") as Label
	assertions.equal(status.text, "调试数据已应用；尚未写入存档", "success feedback stays visible")
	assertions.equal((panel.build_draft().items.wood as Dictionary).quantity, 12, "success snapshot clears old draft")

	(panel.get_node("Overlay/Center/Panel/Layout/Footer/CancelButton") as Button).pressed.emit()
	assertions.truthy(not panel.visible, "cancel closes without another apply")
	assertions.equal(apply_requests.size(), 1, "cancel never applies")
	panel.queue_free()
	await tree.process_frame


func _snapshot() -> Dictionary:
	return {
		"level": 2,
		"elapsed_days": 8,
		"gold": 700,
		"stamina": 75,
		"max_stamina": 100,
		"max_slots": 20,
		"items": {
			"wood": {"id": "wood", "name": "木材", "category": "material", "max_stack": 99, "quantity": 12},
			"stone": {"id": "stone", "name": "石材", "category": "material", "max_stack": 99, "quantity": 8},
			"grain_seed": {"id": "grain_seed", "name": "谷物种子", "category": "seed", "max_stack": 99, "quantity": 4},
		},
	}


func _item_editor(panel: Node, item_id: String) -> SpinBox:
	var rows := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/Inventory/ItemScroll/ItemRows"
	)
	for row in rows.get_children():
		if str(row.get_meta("item_id", "")) == item_id:
			return row.get_node_or_null("Quantity") as SpinBox
	return null


func _option_index(option: OptionButton, metadata: String) -> int:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == metadata:
			return index
	return -1
