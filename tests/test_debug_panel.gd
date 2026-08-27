extends RefCounted

const DebugPanelScene := preload("res://scenes/ui/debug_panel.tscn")

const REQUIRED_NODES: Array[String] = [
	"Overlay/Center/Panel/Layout/Header/Title",
	"Overlay/Center/Panel/Layout/Header/CloseButton",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Level",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/ElapsedDays",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Season",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Gold",
	"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Stamina",
	"Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Search",
	"Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Category",
	"Overlay/Center/Panel/Layout/Tabs/Inventory/DebugControls/MaxSlots",
	"Overlay/Center/Panel/Layout/Tabs/Inventory/DebugControls/BuyAllSeedsButton",
	"Overlay/Center/Panel/Layout/Tabs/Inventory/ItemScroll/ItemRows",
	"Overlay/Center/Panel/Layout/Tabs/Agent/IntervalRows",
	"Overlay/Center/Panel/Layout/Tabs/Agent/AgentStatus",
	"Overlay/Center/Panel/Layout/Tabs/Agent/ApplyAgentSettingsButton",
	"Overlay/Center/Panel/Layout/Footer/Status",
	"Overlay/Center/Panel/Layout/Footer/RefreshButton",
	"Overlay/Center/Panel/Layout/Footer/CancelButton",
	"Overlay/Center/Panel/Layout/Footer/ApplyButton",
]


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var panel := DebugPanelScene.instantiate()
	tree.root.add_child(panel)
	var required_nodes_present := true
	for node_path in REQUIRED_NODES:
		var has_required_node := panel.has_node(node_path)
		assertions.truthy(has_required_node, "debug panel authors %s" % node_path)
		required_nodes_present = required_nodes_present and has_required_node
	if not required_nodes_present:
		panel.queue_free()
		await tree.process_frame
		return
	var snapshot := _snapshot()
	assertions.truthy(panel.configure(snapshot), "debug panel accepts a complete snapshot")
	var has_agent_configuration := panel.has_method("configure_agent_settings")
	assertions.truthy(has_agent_configuration, "debug panel exposes Agent interval configuration")
	assertions.truthy(panel.has_signal("agent_settings_apply_requested"), "debug panel exposes Agent settings apply signal")
	if has_agent_configuration:
		assertions.truthy(panel.configure_agent_settings([
			{"agent_id": "farmer_ahe", "display_name": "阿禾", "decision_interval_hours": 1},
			{"agent_id": "lao_li", "display_name": "老李", "decision_interval_hours": 2},
			{"agent_id": "xuezhe_lin", "display_name": "学者林", "decision_interval_hours": 4},
		]), "debug panel accepts three Agent interval records")
	panel.open()
	await tree.process_frame
	assertions.equal(panel.get_visible_item_ids().size(), 3, "debug panel authors every item row")
	var fields := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields"
	) as Control
	var hint := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/PlayerState/Hint"
	) as Label
	assertions.truthy(
		hint.position.y >= fields.position.y + fields.size.y - 1.0,
		"player date hint is laid out below the state fields (%s/%s after %s/%s)"
		% [hint.position.y, hint.size.y, fields.position.y, fields.size.y]
	)
	for label_name in ["LevelLabel", "ElapsedDaysLabel", "GoldLabel", "StaminaLabel"]:
		var field_label := fields.get_node(label_name) as Label
		assertions.truthy(
			field_label.get_theme_color("font_color").get_luminance() < 0.55,
			"%s stays dark on the cream panel" % label_name
		)
	var wood_name := _item_editor(panel, "wood").get_parent().get_node("Name") as Label
	assertions.truthy(
		wood_name.get_theme_color("font_color").get_luminance() < 0.55,
		"dynamic item names stay dark on the cream panel"
	)
	var initial_status := panel.get_node("Overlay/Center/Panel/Layout/Footer/Status") as Label
	assertions.truthy(
		initial_status.get_theme_color("font_color").get_luminance() < 0.55,
		"footer status stays dark on the cream panel"
	)
	assertions.truthy(panel.visible, "debug panel opens")
	var elapsed_days := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/ElapsedDays"
	) as SpinBox
	var season := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Season"
	) as OptionButton
	var autumn_index := _option_index(season, "2")
	assertions.truthy(autumn_index >= 0, "season selector offers autumn")
	if autumn_index >= 0:
		season.select(autumn_index)
		season.item_selected.emit(autumn_index)
		assertions.equal(roundi(elapsed_days.value), 15, "season selection preserves year and day")
		assertions.equal(panel.build_draft().season, 2, "season selection enters the draft")

	(panel.get_node("Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Level") as SpinBox).value = 4
	elapsed_days.value = 28
	elapsed_days.value_changed.emit(elapsed_days.value)
	assertions.equal(
		int(season.get_item_metadata(season.selected)),
		0,
		"elapsed day changes synchronize the season selector"
	)
	(panel.get_node("Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Gold") as SpinBox).value = 9000
	(panel.get_node("Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Stamina") as SpinBox).value = 23
	var max_slots := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/Inventory/DebugControls/MaxSlots"
	) as SpinBox
	max_slots.value = 30
	max_slots.value_changed.emit(max_slots.value)
	var wood_editor := _item_editor(panel, "wood")
	assertions.truthy(wood_editor != null, "wood row owns a quantity editor")
	if wood_editor != null:
		assertions.equal(
			int(wood_editor.max_value),
			2970,
			"capacity expansion immediately raises item quantity editor limits"
		)
		wood_editor.value = 145
	(panel.get_node("Overlay/Center/Panel/Layout/Tabs/Inventory/DebugControls/BuyAllSeedsButton") as Button).pressed.emit()
	assertions.equal(panel.get_visible_item_ids().size(), 4, "buy-all reveals previously empty seed rows")
	assertions.equal(
		int(_item_editor(panel, "wood").max_value),
		2970,
		"buy-all row rebuild keeps the pending expanded capacity limit"
	)
	var show_empty := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/ShowEmpty"
	) as CheckBox
	show_empty.button_pressed = true
	show_empty.toggled.emit(true)
	var draft: Dictionary = panel.build_draft()
	assertions.equal(draft.level, 4, "draft reads edited level")
	assertions.equal(draft.elapsed_days, 28, "draft reads edited elapsed days")
	assertions.equal(draft.season, 0, "draft reads synchronized season")
	assertions.equal(draft.gold, 9000, "draft reads edited gold")
	assertions.equal(draft.stamina, 23, "draft reads edited stamina")
	assertions.equal(draft.max_slots, 30, "draft reads edited inventory capacity")
	assertions.equal((draft.items.wood as Dictionary).quantity, 145, "buy-all and row rebuild preserve other draft edits")
	assertions.equal((draft.items.grain_seed as Dictionary).quantity, 120, "buy-all never reduces an existing seed surplus")
	assertions.equal((draft.items.apple_sapling as Dictionary).quantity, 99, "show-empty rebuild preserves granted saplings")

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
		assertions.equal(
			panel.get_visible_item_ids(),
			["apple_sapling", "grain_seed"],
			"category filters every purchased seed row"
		)

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
	if has_agent_configuration and panel.has_signal("agent_settings_apply_requested"):
		var agent_requests: Array[Dictionary] = []
		panel.agent_settings_apply_requested.connect(func(intervals: Dictionary): agent_requests.append(intervals))
		var farmer_interval := _agent_interval_editor(panel, "farmer_ahe")
		assertions.truthy(farmer_interval != null, "Agent interval rows retain Agent identity")
		if farmer_interval != null:
			farmer_interval.value = 0
		(panel.get_node("Overlay/Center/Panel/Layout/Tabs/Agent/ApplyAgentSettingsButton") as Button).pressed.emit()
		assertions.equal(agent_requests.size(), 1, "Agent settings button emits one focused request")
		if not agent_requests.is_empty():
			assertions.equal(agent_requests[0], {"farmer_ahe": 0, "lao_li": 2, "xuezhe_lin": 4}, "Agent settings request contains every interval")

	panel.show_apply_result(
		{"ok": true, "message": "调试数据已应用；尚未写入存档"},
		snapshot
	)
	var status := panel.get_node("Overlay/Center/Panel/Layout/Footer/Status") as Label
	assertions.equal(status.text, "调试数据已应用；尚未写入存档", "success feedback stays visible")
	assertions.equal((panel.build_draft().items.wood as Dictionary).quantity, 12, "success snapshot clears old draft")
	assertions.equal(panel.build_draft().max_slots, 20, "success snapshot restores authoritative capacity")

	(panel.get_node("Overlay/Center/Panel/Layout/Footer/CancelButton") as Button).pressed.emit()
	assertions.truthy(not panel.visible, "cancel closes without another apply")
	assertions.equal(apply_requests.size(), 1, "cancel never applies")
	panel.queue_free()
	await tree.process_frame


func _snapshot() -> Dictionary:
	return {
		"level": 2,
		"elapsed_days": 8,
		"season": 1,
		"gold": 700,
		"stamina": 75,
		"max_stamina": 100,
		"max_slots": 20,
		"items": {
			"wood": {"id": "wood", "name": "木材", "category": "material", "max_stack": 99, "quantity": 12},
			"stone": {"id": "stone", "name": "石材", "category": "material", "max_stack": 99, "quantity": 8},
			"grain_seed": {"id": "grain_seed", "name": "谷物种子", "category": "seed", "max_stack": 99, "quantity": 120},
			"apple_sapling": {"id": "apple_sapling", "name": "苹果树苗", "category": "seed", "max_stack": 99, "quantity": 0},
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


func _agent_interval_editor(panel: Node, agent_id: String) -> SpinBox:
	var rows := panel.get_node("Overlay/Center/Panel/Layout/Tabs/Agent/IntervalRows")
	for row in rows.get_children():
		if str(row.get_meta("agent_id", "")) == agent_id:
			return row.get_node_or_null("Interval") as SpinBox
	return null


func _option_index(option: OptionButton, metadata: String) -> int:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == metadata:
			return index
	return -1
