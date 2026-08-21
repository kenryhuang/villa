extends RefCounted

const HudScene = preload("res://scenes/ui/hud.tscn")
const ActionPaletteButtonScript = preload(
	"res://scripts/ui/action_palette_button.gd"
)
const GameDataScript = preload("res://scripts/core/game_data.gd")


class ToolDouble:
	extends RefCounted

	func switch_tool(_tool_type: int) -> void:
		pass


class BuildingDouble:
	extends RefCounted

	var build_mode := false
	var inventory: InventorySystem
	var locked_ids: Dictionary = {}

	func enter_preview_mode(_building: Variant) -> bool:
		build_mode = true
		return true

	func exit_preview_mode() -> void:
		build_mode = false

	func is_in_build_mode() -> bool:
		return build_mode

	func diagnose_resources(building: Variant) -> Dictionary:
		var building_id := str(building)
		var source: Dictionary = GameDataScript.get_building(building_id)
		var missing := {}
		for item_id in source.get("cost", {}):
			var required := int(source.cost[item_id])
			var available := inventory.get_item_count(str(item_id)) if inventory else 0
			if available < required:
				missing[item_id] = {
					"required": required,
					"available": available,
					"missing": required - available,
				}
		return {
			"allowed": missing.is_empty(),
			"code": "ok" if missing.is_empty() else "insufficient_resources",
			"message": "" if missing.is_empty() else "材料不足",
			"building_id": building_id,
			"missing_resources": missing,
		}

	func diagnose_availability(building: Variant) -> Dictionary:
		var building_id := str(building)
		if locked_ids.has(building_id):
			return {
				"allowed": false,
				"code": "blueprint_locked",
				"message": "需要第8天",
				"building_id": building_id,
				"missing_resources": {},
				"unlock_service_id": "blueprint_%s" % building_id,
			}
		return diagnose_resources(building)


class SeasonDouble:
	extends Node

	const DAYS_PER_SEASON := 7
	var current_season := 0
	var current_day := 1
	var hour := 6
	var minute := 0


class EconomyDouble:
	extends RefCounted

	func has_resources(_cost: Dictionary) -> bool:
		return false


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var hud = HudScene.instantiate()
	tree.root.add_child(hud)
	var debug_actions := hud.get_node_or_null("DebugActions")
	var debug_panel_button := hud.get_node_or_null("DebugActions/DebugPanelButton")
	var debug_reset_button := hud.get_node_or_null("DebugActions/DebugResetButton")
	var has_debug_tools_api := hud.has_method("configure_debug_tools")
	var has_debug_reset_api := hud.has_method("configure_debug_reset")
	var has_debug_panel_signal := hud.has_signal("debug_panel_requested")
	var has_debug_reset_signal := hud.has_signal("debug_reset_requested")
	assertions.truthy(
		debug_actions is HBoxContainer,
		"HUD groups debug actions"
	)
	assertions.truthy(
		debug_panel_button is Button,
		"HUD authors the debug panel button"
	)
	assertions.truthy(
		debug_reset_button is Button,
		"HUD authors the debug reset button"
	)
	assertions.truthy(
		has_debug_tools_api,
		"HUD exposes debug tool availability configuration"
	)
	assertions.truthy(
		has_debug_reset_api,
		"HUD keeps the debug reset compatibility configuration"
	)
	assertions.truthy(
		has_debug_panel_signal,
		"HUD exposes the debug panel request signal"
	)
	assertions.truthy(
		has_debug_reset_signal,
		"HUD exposes the debug reset request signal"
	)
	if (
		debug_actions is HBoxContainer
		and debug_panel_button is Button
		and debug_reset_button is Button
		and has_debug_tools_api
		and has_debug_panel_signal
		and has_debug_reset_signal
	):
		var debug_panel_requests: Array[bool] = []
		var debug_reset_requests: Array[bool] = []
		hud.debug_panel_requested.connect(
			func() -> void:
				debug_panel_requests.append(true)
		)
		hud.debug_reset_requested.connect(
			func() -> void:
				debug_reset_requests.append(true)
		)
		hud.configure_debug_tools(false)
		assertions.truthy(
			not debug_actions.visible,
			"debug actions are hidden when unavailable"
		)
		debug_panel_button.pressed.emit()
		debug_reset_button.pressed.emit()
		assertions.equal(debug_panel_requests.size(), 0, "hidden debug panel does not emit")
		assertions.equal(debug_reset_requests.size(), 0, "hidden debug reset does not emit")
		hud.configure_debug_tools(true)
		assertions.truthy(
			debug_actions.visible,
			"debug actions appear when available"
		)
		debug_panel_button.pressed.emit()
		debug_reset_button.pressed.emit()
		assertions.equal(
			debug_panel_requests.size(),
			1,
			"available debug panel emits one request"
		)
		assertions.equal(
			debug_reset_requests.size(),
			1,
			"available debug reset emits one request"
		)
		hud.configure_debug_tools(false)
		debug_panel_button.pressed.emit()
		debug_reset_button.pressed.emit()
		assertions.equal(
			debug_panel_requests.size(),
			1,
			"unavailable debug panel does not emit another request"
		)
		assertions.equal(
			debug_reset_requests.size(),
			1,
			"unavailable debug reset does not emit a request"
		)
		hud.configure_debug_reset(true)
		assertions.truthy(debug_actions.visible, "compatibility API shows all debug tools")
	for item_id in ["wood", "stone", "iron", "glass"]:
		var entry_path := "MaterialsPanel/MaterialsRow/%s" % item_id.capitalize()
		var entry := hud.get_node_or_null(entry_path)
		assertions.truthy(entry != null, "%s material entry is authored" % item_id)
		if entry:
			assertions.truthy(
				entry.get_node_or_null("Icon") is TextureRect,
				"%s has a material icon" % item_id
			)
			assertions.truthy(
				entry.get_node("Icon").texture != null,
				"%s material icon has a local texture" % item_id
			)
			assertions.truthy(
				entry.get_node_or_null("Count") is Label,
				"%s has a count label" % item_id
			)
			assertions.truthy(
				not entry.has_node("Name"),
				"%s has no visible name label" % item_id
			)
	assertions.truthy(
		hud.get_node_or_null("BottomBar/BuildCostBar") is PanelContainer,
		"selected building cost bar is authored"
	)
	assertions.truthy(
		hud.get_node_or_null("BottomBar/BuildFeedbackToast") is PanelContainer,
		"building feedback toast is authored"
	)
	assertions.truthy(
		hud.get_node_or_null("BottomBar/BuildCategoryBar") is HBoxContainer,
		"five-category building bar is authored"
	)
	assertions.truthy(
		hud.get_node_or_null("BuildLockPanel") is PanelContainer,
		"building lock detail panel is authored"
	)
	assertions.truthy(hud.has_signal("building_unlock_requested"), "HUD exposes blueprint deep-link signal")
	assertions.truthy(
		hud.get_node_or_null("BuildFeedbackTimer") is Timer,
		"building feedback timer is authored"
	)
	assertions.truthy(
		hud.get_node("TopBar") is PanelContainer,
		"top status owns a background panel"
	)
	var status_labels: Array[Label] = [
		hud.gold_label,
		hud.level_label,
		hud.season_label,
		hud.time_label,
	]
	for label in status_labels:
		assertions.truthy(
			label.get_theme_font_size("font_size") >= 32,
			"status font is readable"
		)
		assertions.truthy(
			label.get_theme_constant("outline_size") >= 4,
			"status font is outlined"
		)
		assertions.truthy(
			label.get_theme_color("font_color").is_equal_approx(Color("fff1d0")),
			"status text is cream"
		)
	assertions.truthy(
		hud.stamina_bar.custom_minimum_size.y >= 44.0,
		"stamina bar is tall enough"
	)
	assertions.truthy(
		hud.exp_bar.custom_minimum_size.y >= 44.0,
		"experience bar is tall enough"
	)
	var top_style := (hud.get_node("TopBar") as Control).get_theme_stylebox("panel")
	assertions.truthy(
		top_style is StyleBoxFlat,
		"top status uses a flat readable panel"
	)
	if top_style is StyleBoxFlat:
		assertions.truthy(
			top_style.bg_color.a >= 0.86,
			"top panel masks busy world backgrounds"
		)
	var has_action_bar_api := hud.has_method("configure_action_bar")
	assertions.truthy(has_action_bar_api, "HUD exposes action bar configuration")
	if not has_action_bar_api:
		hud.free()
		return

	var inventory_script = load("res://scripts/systems/inventory_system.gd")
	var controller_script = load("res://scripts/actors/player_action_controller.gd")
	var inventory = inventory_script.new()
	tree.root.add_child(inventory)
	inventory.add_item("grain_seed", 2)
	inventory.add_item("wood", 42)
	inventory.add_item("stone", 150)
	inventory.add_item("iron", 50)
	inventory.add_item("glass", 50)
	inventory.set_quick_slot(0, PlayerActionController.SEED_SLOT)
	var building := BuildingDouble.new()
	building.inventory = inventory
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.configure(
		null,
		null,
		null,
		building,
		ToolDouble.new(),
		inventory,
		null
	)
	hud.configure_action_bar(controller, inventory, EconomyDouble.new())
	assertions.equal(
		hud.get_palette_button_count(),
		0,
		"startup HUD hides action shortcuts before P or B"
	)
	assertions.truthy(
		controller.switch_mode(PlayerActionController.ActionMode.FARMING),
		"HUD fixture explicitly enters farming mode"
	)
	assertions.equal(hud.get_palette_button_count(), 6, "P reveals six farming shortcuts")
	var mapping_handler := Callable(hud, "_on_quick_slot_mapping_changed")
	assertions.truthy(
		inventory.quick_slot_mapping_changed.is_connected(mapping_handler),
		"HUD subscribes to quick-slot mapping changes"
	)
	hud.configure_action_bar(controller, inventory, EconomyDouble.new())
	var mapping_connection_count := 0
	for connection in inventory.quick_slot_mapping_changed.get_connections():
		if connection.get("callable") == mapping_handler:
			mapping_connection_count += 1
	assertions.equal(
		mapping_connection_count,
		1,
		"reconfiguring HUD does not duplicate inventory signal connections"
	)
	assertions.truthy(
		hud.has_method("get_material_count_text"),
		"HUD exposes material count inspection"
	)
	if hud.has_method("get_material_count_text"):
		assertions.equal(hud.get_material_count_text("wood"), "42", "HUD shows current wood")
		assertions.equal(hud.get_material_count_text("stone"), "150", "HUD shows current stone")
		assertions.equal(hud.get_material_count_text("iron"), "50", "HUD shows current iron")
		assertions.equal(hud.get_material_count_text("glass"), "50", "HUD shows current glass")
	var season := SeasonDouble.new()
	tree.root.add_child(season)
	assertions.truthy(
		hud.has_method("configure_season_system"),
		"HUD accepts the main scene season system"
	)
	if hud.has_method("configure_season_system"):
		hud.call("configure_season_system", season)
		season.current_day = 2
		hud.call("_on_day_changed", 2)
		assertions.equal(hud.season_label.text, "春 2/7", "HUD refreshes the scene-local day")

	var quick_bar: HBoxContainer = hud.quick_bar
	assertions.equal(quick_bar.get_child_count(), 6, "HUD keeps six action slots")
	for child in quick_bar.get_children():
		assertions.truthy(
			child is ActionPaletteButtonScript,
			"farming uses readable action tiles"
		)
		if child is ActionPaletteButtonScript:
			assertions.equal(
				child.icon_rect.custom_minimum_size,
				Vector2(84, 84),
				"tile icon is large"
			)
	var first_tile := quick_bar.get_child(0)
	var seed_tile := quick_bar.get_child(5)
	if first_tile is ActionPaletteButtonScript:
		assertions.equal(first_tile.name_label.text, "锄头", "first tile labels the hoe")
	if seed_tile is ActionPaletteButtonScript:
		assertions.equal(
			seed_tile.name_label.text,
			"谷物种子 ×2",
			"seed tile names the active default seed"
		)

	var emitted_indices: Array[int] = []
	hud.quick_slot_selected.connect(
		func(index: int) -> void:
			emitted_indices.append(index)
	)
	(quick_bar.get_child(5) as Button).pressed.emit()
	assertions.equal(emitted_indices, [5], "clicking seed slot emits index five")
	assertions.equal(controller.get_selected_slot(), 5, "clicking seed slot changes selection")
	assertions.equal(hud.tool_label.text, "谷物种子", "HUD shows selected seed action")
	assertions.truthy(
		(quick_bar.get_child(5) as Button).button_pressed,
		"selected seed slot is highlighted"
	)
	inventory.add_item("carrot_seed", 1)
	var carrot_slot := -1
	for slot_index in range(inventory.slots.size()):
		if inventory.slots[slot_index].get("item_id", "") == "carrot_seed":
			carrot_slot = slot_index
			break
	assertions.truthy(carrot_slot >= 0, "HUD fixture finds carrot seed inventory slot")
	assertions.truthy(controller.set_selected_plant_item_id("carrot_seed"), "controller selects carrot independently of quick mappings")
	assertions.equal(
		(quick_bar.get_child(5) as ActionPaletteButtonScript).name_label.text,
		"胡萝卜种子 ×1",
		"selected planting tile immediately shows selected carrot seed and quantity"
	)
	assertions.equal(
		hud.tool_label.text,
		"胡萝卜种子",
		"selected planting label immediately names selected carrot seed"
	)
	for planting_case in [
		{"item_id": "rose_seed", "quantity": 3, "text": "玫瑰种子 ×3", "label": "玫瑰种子"},
		{"item_id": "apple_sapling", "quantity": 2, "text": "苹果树苗 ×2", "label": "苹果树苗"},
	]:
		inventory.add_item(planting_case.item_id, planting_case.quantity)
		var planting_slot := -1
		for slot_index in range(inventory.slots.size()):
			if inventory.slots[slot_index].get("item_id", "") == planting_case.item_id:
				planting_slot = slot_index
				break
		assertions.truthy(planting_slot >= 0, "HUD fixture finds %s" % planting_case.item_id)
		assertions.truthy(
			controller.set_selected_plant_item_id(planting_case.item_id),
			"controller selects %s independently" % planting_case.item_id
		)
		assertions.equal(
			(quick_bar.get_child(5) as ActionPaletteButtonScript).name_label.text,
			planting_case.text,
			"selected planting tile immediately shows %s and quantity" % planting_case.item_id
		)
		assertions.equal(
			hud.tool_label.text,
			planting_case.label,
			"selected planting label immediately names %s" % planting_case.item_id
		)
	inventory.set_quick_slot(0, PlayerActionController.SEED_SLOT)
	inventory.swap_slots(0, carrot_slot)
	assertions.equal(
		(quick_bar.get_child(5) as ActionPaletteButtonScript).name_label.text,
		"苹果树苗 ×2",
		"quick-slot remapping cannot replace the independent seed selection"
	)
	assertions.equal(
		hud.tool_label.text,
		"苹果树苗",
		"quick-slot swapping cannot replace the selected planting label"
	)
	assertions.truthy(controller.deselect_slot(), "selected HUD action can be cancelled")
	assertions.equal(hud.tool_label.text, "未选择工具", "HUD shows cancelled tool state")
	for child in quick_bar.get_children():
		assertions.truthy(
			not (child as Button).button_pressed,
			"cancelled tool leaves every action button unpressed"
		)

	inventory.remove_item("apple_sapling", 2)
	hud.refresh_action_bar()
	seed_tile = quick_bar.get_child(5)
	if seed_tile is ActionPaletteButtonScript:
		assertions.equal(
			seed_tile.name_label.text,
			"苹果树苗 ×0",
			"active seed selection remains visible after inventory reaches zero"
		)

	var has_mode_palette_api := (
		hud.has_method("rebuild_action_palette")
		and hud.has_method("set_mode_menu_open")
		and hud.has_method("get_palette_button_count")
	)
	assertions.truthy(has_mode_palette_api, "HUD exposes dynamic mode palette API")
	if not has_mode_palette_api:
		controller.free()
		inventory.free()
		season.free()
		hud.free()
		return

	assertions.equal(hud.get_palette_button_count(), 6, "farming palette has six buttons")
	assertions.truthy(
		hud.mode_button is ActionPaletteButtonScript,
		"mode switch uses the large tile"
	)
	if hud.mode_button is ActionPaletteButtonScript:
		assertions.equal(
			hud.mode_button.name_label.text,
			"种植",
			"mode button shows farming mode"
		)
	assertions.truthy(
		hud.tool_label.get_theme_font_size("font_size") >= 28,
		"selection text is readable"
	)
	var tool_icon_paths: Array[String] = [
		"res://assets/ui/action_icons/hoe.png",
		"res://assets/ui/action_icons/watering_can.png",
		"res://assets/ui/action_icons/axe.png",
		"res://assets/ui/action_icons/pickaxe.png",
		"res://assets/ui/action_icons/fishing_rod.png",
	]
	for path in tool_icon_paths:
		assertions.truthy(ResourceLoader.exists(path), "tool icon imports: %s" % path)
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			assertions.equal(texture.get_width(), 256, "tool icon width is 256")
			assertions.equal(texture.get_height(), 256, "tool icon height is 256")
	for child in quick_bar.get_children():
		assertions.truthy(
			child is ActionPaletteButtonScript and child.icon_rect.texture != null,
			"every farming palette button has an icon"
		)
	assertions.truthy(
		controller.switch_mode(PlayerActionController.ActionMode.BUILDING),
		"controller enters building mode for HUD"
	)
	assertions.truthy(controller.select_mode_slot(3), "affordable well can be selected")
	assertions.equal(hud.tool_label.text, "水井", "building slot four shows the well label")
	inventory.set_quick_slot(carrot_slot, PlayerActionController.SEED_SLOT)
	assertions.equal(
		hud.tool_label.text,
		"水井",
		"planting remaps do not overwrite a selected building label"
	)
	assertions.equal(hud.get_palette_button_count(), 4, "current building category has four buttons")
	assertions.equal(hud.build_category_bar.get_child_count(), 5, "building palette has five category buttons")
	assertions.truthy(hud.build_category_bar.visible, "building categories appear only in building mode")
	if hud.mode_button is ActionPaletteButtonScript:
		assertions.equal(
			hud.mode_button.name_label.text,
			"建造",
			"mode button shows building mode"
		)
	assertions.truthy(
		hud.get_node("BottomBar/ActionRow").get_combined_minimum_size().x <= 1280.0,
		"complete building palette fits a 1280-pixel-wide window"
	)
	for child in quick_bar.get_children():
		assertions.truthy(
			child is ActionPaletteButtonScript and child.icon_rect.texture != null,
			"every building palette button has an icon"
		)
	building.locked_ids.furnace = true
	var unlock_requests: Array[String] = []
	hud.building_unlock_requested.connect(func(service_id: String) -> void: unlock_requests.append(service_id))
	assertions.truthy(controller.set_building_category("production"), "HUD fixture selects production category")
	(quick_bar.get_child(1) as Button).pressed.emit()
	assertions.truthy(hud.build_lock_panel.visible, "locked building opens lock detail")
	assertions.equal(hud.build_lock_unlock_button.disabled, false, "mapped lock can navigate to services")
	hud.build_lock_unlock_button.pressed.emit()
	assertions.equal(unlock_requests, ["blueprint_furnace"], "lock detail emits blueprint service target")
	assertions.truthy(controller.set_building_category("basic"), "HUD fixture returns to basic category")
	var unavailable_tile := quick_bar.get_child(2)
	if unavailable_tile is ActionPaletteButtonScript:
		assertions.truthy(not unavailable_tile.disabled, "unaffordable building remains clickable for feedback")
		assertions.equal(unavailable_tile.build_state, "missing_resources", "unaffordable building uses missing state")
		assertions.equal(
			unavailable_tile.name_label.modulate,
			Color.WHITE,
			"resource dimming keeps text opaque"
		)
		assertions.truthy(
			unavailable_tile.icon_rect.modulate != Color.WHITE,
			"resource dimming targets icon"
		)
		assertions.truthy(
			unavailable_tile.tooltip_text.contains("木板"),
			"missing building keeps localized cost tooltip"
		)
	assertions.truthy(
		hud.has_method("show_build_feedback"),
		"HUD exposes building feedback Toast"
	)
	if hud.has_method("show_build_feedback"):
		var toast = hud.get_node("BottomBar/BuildFeedbackToast")
		hud.show_build_feedback("无法建造谷仓：木材还缺 58", {})
		assertions.truthy(toast.visible, "building feedback Toast becomes visible")
		assertions.equal(
			toast.get_node("Message").text,
			"无法建造谷仓：木材还缺 58",
			"building feedback Toast shows the specific reason"
		)
		hud.show_build_feedback("无法建造谷仓：目标区域包含道路", {})
		assertions.equal(
			hud.get_node("BottomBar/BuildFeedbackToast"),
			toast,
			"repeated feedback reuses one Toast"
		)

	inventory.add_item("plank", 8)
	inventory.add_item("stone_brick", 6)
	inventory.add_item("wooden_crate", 1)
	if hud.has_method("get_material_count_text"):
		assertions.equal(
			hud.get_material_count_text("wood"),
			"42",
			"material count refreshes"
		)
	unavailable_tile = quick_bar.get_child(2)
	assertions.equal(unavailable_tile.build_state, "ready", "building becomes ready when cost is met")
	assertions.truthy(controller.select_mode_slot(2), "affordable barn can be selected")
	assertions.truthy(
		hud.get_node("BottomBar/BuildCostBar").visible,
		"selected building shows persistent cost bar"
	)
	assertions.truthy(
		hud.get_node("BottomBar/BuildCostBar/CostRow/BuildingLabel").text.contains("占地 2×2"),
		"cost bar shows building footprint"
	)
	assertions.truthy(controller.set_building_category("decoration"), "HUD fixture selects decoration category")
	(quick_bar.get_child(1) as Button).pressed.emit()
	assertions.equal(
		controller.get_mode_selected_slot(PlayerActionController.ActionMode.BUILDING),
		1,
		"mouse selects fence through the shared controller API"
	)
	hud.set_mode_menu_open(true)
	assertions.truthy(hud.mode_menu.visible, "mode menu can open above the palette")

	var replacement_inventory = inventory_script.new()
	tree.root.add_child(replacement_inventory)
	replacement_inventory.add_item("grain_seed", 1)
	replacement_inventory.set_quick_slot(0, PlayerActionController.SEED_SLOT)
	var replacement_building := BuildingDouble.new()
	replacement_building.inventory = replacement_inventory
	var replacement_controller = controller_script.new()
	tree.root.add_child(replacement_controller)
	replacement_controller.configure(
		null,
		null,
		null,
		replacement_building,
		ToolDouble.new(),
		replacement_inventory,
		null
	)
	hud.configure_action_bar(
		replacement_controller,
		replacement_inventory,
		EconomyDouble.new()
	)
	assertions.truthy(
		not inventory.quick_slot_mapping_changed.is_connected(mapping_handler),
		"HUD disconnects the previous inventory when reconfigured"
	)
	assertions.truthy(
		replacement_inventory.quick_slot_mapping_changed.is_connected(mapping_handler),
		"HUD subscribes to the replacement inventory"
	)
	var controller_connections := {
		"selection_changed": Callable(hud, "_on_action_selection_changed"),
		"inventory_changed": Callable(hud, "refresh_action_bar"),
		"plant_selection_changed": Callable(hud, "_on_plant_selection_changed"),
		"mode_changed": Callable(hud, "_on_action_mode_changed"),
		"palette_changed": Callable(hud, "_on_action_palette_changed"),
		"build_feedback_requested": Callable(hud, "show_build_feedback"),
		"building_category_changed": Callable(hud, "_on_building_category_changed"),
	}
	for signal_name in controller_connections:
		var callback: Callable = controller_connections[signal_name]
		assertions.truthy(
			not controller.is_connected(signal_name, callback),
			"HUD disconnects old controller callback %s" % signal_name
		)
		assertions.truthy(
			replacement_controller.is_connected(signal_name, callback),
			"HUD connects replacement controller callback %s" % signal_name
		)
	hud.configure_action_bar(
		replacement_controller,
		replacement_inventory,
		EconomyDouble.new()
	)
	for signal_name in controller_connections:
		var callback: Callable = controller_connections[signal_name]
		var callback_count := 0
		for connection in replacement_controller.get_signal_connection_list(signal_name):
			if connection.get("callable") == callback:
				callback_count += 1
		assertions.equal(
			callback_count,
			1,
			"same-controller reconfiguration keeps one %s callback" % signal_name
		)
	replacement_controller.selection_changed.emit(0, "replacement selection")
	assertions.equal(
		hud.tool_label.text,
		"replacement selection",
		"replacement controller updates the HUD"
	)
	controller.selection_changed.emit(0, "stale selection")
	assertions.equal(
		hud.tool_label.text,
		"replacement selection",
		"old controller selection emissions do nothing"
	)
	var toast = hud.get_node("BottomBar/BuildFeedbackToast")
	toast.visible = false
	controller.inventory_changed.emit()
	controller.mode_changed.emit(PlayerActionController.ActionMode.BUILDING)
	controller.palette_changed.emit(PlayerActionController.ActionMode.BUILDING, 0)
	controller.build_feedback_requested.emit("stale feedback", {})
	assertions.truthy(not toast.visible, "old controller feedback emissions do nothing")

	controller.free()
	replacement_controller.free()
	inventory.free()
	replacement_inventory.free()
	season.free()
	hud.free()
