class_name EconomyUIResponsiveTest
extends RefCounted

const EconomyLayout = preload("res://scripts/ui/economy_layout.gd")
const EconomyLayoutScript: Script = preload("res://scripts/ui/economy_layout.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const THEME_PATH := "res://assets/ui/economy/economy_theme.tres"
const VIEWPORT_SIZES := [
	Vector2(3000.0, 2000.0),
	Vector2(1920.0, 1080.0),
	Vector2(1280.0, 720.0),
]
const PANEL_SCENES := [
	"res://scenes/ui/shop_ui.tscn",
	"res://scenes/ui/economy/market_panel.tscn",
	"res://scenes/ui/economy/trade_panel.tscn",
	"res://scenes/ui/economy/order_panel.tscn",
	"res://scenes/ui/economy/contract_panel.tscn",
	"res://scenes/ui/economy/service_panel.tscn",
	"res://scenes/ui/economy/building_economy_ui.tscn",
	"res://scenes/ui/economy/building_production_panel.tscn",
	"res://scenes/ui/economy/building_status_panel.tscn",
	"res://scenes/ui/economy/economy_notification_ui.tscn",
]
const MAIN_TITLE_CONTRACTS := {
	"res://scenes/ui/shop_ui.tscn": "ModalLayer/HubPanel/Margin/Shell/Header/TitleLabel",
	"res://scenes/ui/economy/market_panel.tscn": "Columns/DetailColumn/ItemNameLabel",
	"res://scenes/ui/economy/building_economy_ui.tscn": "ModalLayer/BuildingPanel/Margin/Shell/Header/TitleLabel",
	"res://scenes/ui/economy/building_status_panel.tscn": "SummaryTitle",
	"res://scenes/ui/economy/economy_notification_ui.tscn": "NotificationCenter/Margin/VBox/Header/Title",
}


class InputCounter:
	extends RefCounted
	var count := 0

	func record() -> void:
		count += 1


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_layout_contract(assertions)
	_test_theme_contract(assertions)
	_test_shared_scene_tokens(assertions)
	_test_scene_font_overrides(assertions)
	_test_building_modal_minimum_height(assertions)
	await _test_panel_contracts(assertions, tree)
	await _test_building_modal_control_bounds(assertions, tree)
	await _test_runtime_scale_and_resize_state(assertions, tree)
	await _test_market_drawer_state(assertions, tree)
	await _test_real_keyboard_navigation(assertions, tree)
	await _test_shop_trade_modal_integration(assertions, tree)
	await _test_narrow_shop_pagehost_bounds(assertions, tree)
	await _test_trade_keyboard_and_wheel(assertions, tree)
	await _test_trade_confirmation_modal(assertions, tree)


func _test_layout_contract(assertions: TestAssert) -> void:
	assertions.equal(EconomyLayout.mode_for_size(Vector2(3000, 2000)), "three_column", "target viewport uses columns")
	assertions.equal(EconomyLayout.mode_for_size(Vector2(1920, 1080)), "three_column", "desktop uses columns")
	assertions.equal(EconomyLayout.mode_for_size(Vector2(1500, 900)), "three_column", "drawer threshold is exclusive")
	assertions.equal(EconomyLayout.mode_for_size(Vector2(1499, 900)), "drawer", "narrow logical viewport uses drawer")
	assertions.equal(EconomyLayout.mode_for_size(Vector2(1280, 720)), "drawer", "minimum viewport uses drawer")
	assertions.equal(EconomyLayout.clamp_scale(0.5), 0.8, "scale has lower bound")
	assertions.equal(EconomyLayout.clamp_scale(1.2), 1.2, "scale preserves supported value")
	assertions.equal(EconomyLayout.clamp_scale(2.0), 1.4, "scale has upper bound")
	assertions.equal(EconomyLayout.clamp_scale(NAN), 1.0, "non-finite scale falls back safely")


func _test_building_modal_minimum_height(assertions: TestAssert) -> void:
	var ui := (load("res://scenes/ui/economy/building_economy_ui.tscn") as PackedScene).instantiate()
	var panel := ui.get_node("ModalLayer/BuildingPanel") as Control
	assertions.truthy(
		panel.anchor_bottom - panel.anchor_top >= 0.88,
		"building modal reserves enough vertical room for production controls at 1280x720"
	)
	ui.free()


func _test_building_modal_control_bounds(assertions: TestAssert, tree: SceneTree) -> void:
	var previous_pause := tree.paused
	for viewport_size in VIEWPORT_SIZES:
		tree.paused = false
		var host := Control.new()
		host.size = viewport_size
		tree.root.add_child(host)
		var grid := GridSystem.new()
		var farming := FarmingSystem.new()
		var inventory := InventorySystem.new()
		var production := ProductionSystem.new()
		var progression := EconomyProgressionSystem.new()
		for system in [grid, farming, inventory, production, progression]:
			host.add_child(system)
		farming.configure(grid, null, null)
		production.configure(grid, farming, null, inventory)
		var windmill := (load("res://scenes/buildings/windmill.tscn") as PackedScene).instantiate() as BuildingInstance
		host.add_child(windmill)
		production.register_building(windmill)
		inventory.add_item("grain", 4)
		var progression_state := progression.to_dict()
		progression_state.unlocked_blueprints.append("windmill")
		for recipe in preload("res://scripts/core/recipe_database.gd").get_recipes_for_station("windmill"):
			progression_state.unlocked_recipes.append(str(recipe.id))
		progression.from_dict(progression_state)
		production.start_recipe(windmill, "flour", 1, inventory)
		var ui := (load("res://scenes/ui/economy/building_economy_ui.tscn") as PackedScene).instantiate() as BuildingEconomyUI
		host.add_child(ui)
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await tree.process_frame
		ui.configure(production, inventory, progression, grid, EconomyModalCoordinator.new())
		assertions.truthy(ui.open_for(windmill), "building modal opens at %s" % viewport_size)
		await tree.process_frame
		var paper := ui.get_node("ModalLayer/BuildingPanel") as Control
		var header := ui.get_node("ModalLayer/BuildingPanel/Margin/Shell/Header") as Control
		for content in [header, ui.production_panel]:
			assertions.truthy(
				_rect_covers_with_tolerance(paper.get_global_rect(), content.get_global_rect())
				and _controls_within_rect(content, paper.get_global_rect()),
				"real production modal controls stay inside paper at %s: %s"
				% [viewport_size, _out_of_bounds_description(content, paper.get_global_rect())]
			)
		ui.close()
		host.free()
		await tree.process_frame
	tree.paused = previous_pause


func _test_theme_contract(assertions: TestAssert) -> void:
	assertions.truthy(ResourceLoader.exists(THEME_PATH), "shared economy theme exists")
	if not ResourceLoader.exists(THEME_PATH):
		return
	var theme := load(THEME_PATH) as Theme
	assertions.truthy(theme != null, "shared economy theme loads")
	if theme == null:
		return
	assertions.equal(theme.get_color("font_color", "Label"), Color("#513B2F"), "theme uses exact primary text color")
	assertions.equal(theme.get_color("font_color", "Button"), Color("#513B2F"), "button text uses primary color")
	assertions.equal(theme.get_color("font_disabled_color", "Button"), Color("#7B6758"), "disabled text uses exact secondary color")
	assertions.equal(theme.get_font_size("font_size", "Label"), 18, "body text is at least 18")
	assertions.equal(theme.get_font_size("font_size", "Button"), 20, "button text is 20")
	var panel_style := theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	var card_style := theme.get_stylebox("panel", "EconomyCard") as StyleBoxFlat
	var focus_style := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	assertions.truthy(panel_style != null, "theme supplies panel background")
	assertions.truthy(card_style != null, "theme supplies card background")
	assertions.truthy(focus_style != null and focus_style.border_width_left >= 2, "keyboard focus has visible border")
	if panel_style != null:
		assertions.equal(panel_style.bg_color, Color("#F1E5C8"), "theme uses exact panel color")
		assertions.truthy(panel_style.corner_radius_top_left >= 8 and panel_style.corner_radius_top_left <= 12, "panel radius stays in design range")
	if card_style != null:
		assertions.equal(card_style.bg_color, Color("#FFF7E6"), "theme uses exact card color")
	assertions.truthy(_contrast_ratio(Color("#513B2F"), Color("#F1E5C8")) >= 4.5, "primary text meets WCAG contrast on panel")
	assertions.truthy(_contrast_ratio(Color("#513B2F"), Color("#FFF7E6")) >= 4.5, "primary text meets WCAG contrast on card")
	assertions.equal(theme.get_color("font_color", "EconomyPositive"), Color("#5F8755"), "theme uses exact positive color")
	assertions.equal(theme.get_color("font_color", "EconomyWarning"), Color("#C58B35"), "theme uses exact warning color")
	assertions.equal(theme.get_color("font_color", "EconomyError"), Color("#B65C4B"), "theme uses exact error color")
	assertions.equal((theme.get_stylebox("selected", "ItemList") as StyleBoxFlat).border_color, Color("#7E9D70"), "theme uses exact selection color")
	assertions.equal((theme.get_stylebox("panel", "EconomyModal") as StyleBoxFlat).bg_color, Color("#211A16A6"), "theme uses exact modal color")


func _test_shared_scene_tokens(assertions: TestAssert) -> void:
	var variation_contracts := {
		"res://scenes/ui/shop_ui.tscn": {
			"ModalLayer/HubPanel": "EconomyPaper",
			"ModalLayer/SignConfirmationLayer/Content": "EconomyCard",
		},
		"res://scenes/ui/economy/market_panel.tscn": {".": "EconomyCard"},
		"res://scenes/ui/economy/trade_panel.tscn": {"ConfirmationLayer/Content": "EconomyCard"},
		"res://scenes/ui/economy/building_economy_ui.tscn": {"ModalLayer/BuildingPanel": "EconomyPaper"},
		"res://scenes/ui/economy/economy_notification_ui.tscn": {"NotificationCenter": "EconomyPaper"},
	}
	for scene_path in variation_contracts:
		var panel := (load(scene_path) as PackedScene).instantiate() as Control
		for node_path in variation_contracts[scene_path]:
			var node := panel.get_node(node_path) as Control
			assertions.equal(
				node.theme_type_variation,
				StringName(variation_contracts[scene_path][node_path]),
				"%s %s uses shared theme token" % [scene_path, node_path]
			)
		panel.free()


func _test_scene_font_overrides(assertions: TestAssert) -> void:
	for scene_path in PANEL_SCENES:
		var panel := (load(scene_path) as PackedScene).instantiate() as Control
		for control in _all_controls(panel):
			if not control.has_theme_font_size_override("font_size"):
				continue
			var font_size := control.get_theme_font_size("font_size")
			var control_path := panel.get_path_to(control)
			if control is BaseButton:
				assertions.truthy(font_size >= 20, "%s %s button override is at least 20" % [scene_path, control_path])
			elif control is Label or control is LineEdit or control is RichTextLabel:
				assertions.truthy(font_size >= 18, "%s %s text override is at least 18" % [scene_path, control_path])
			if "title" in str(control.name).to_lower():
				assertions.truthy(
					font_size >= 28 and font_size <= 36,
					"%s %s semantic title is 28-36" % [scene_path, control_path]
				)
		panel.free()
	for scene_path in MAIN_TITLE_CONTRACTS:
		var panel := (load(scene_path) as PackedScene).instantiate() as Control
		var title := panel.get_node(MAIN_TITLE_CONTRACTS[scene_path]) as Control
		var title_size := title.get_theme_font_size("font_size")
		assertions.truthy(title_size >= 28 and title_size <= 36, "%s main title is 28-36" % scene_path)
		panel.free()


func _test_panel_contracts(assertions: TestAssert, tree: SceneTree) -> void:
	for scene_path in PANEL_SCENES:
		assertions.truthy(ResourceLoader.exists(scene_path), "%s exists" % scene_path)
		if not ResourceLoader.exists(scene_path):
			continue
		for viewport_size in VIEWPORT_SIZES:
			var host := Control.new()
			host.size = viewport_size
			tree.root.add_child(host)
			var panel := (load(scene_path) as PackedScene).instantiate() as Control
			host.add_child(panel)
			panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			panel.visible = true
			await tree.process_frame
			assertions.truthy(_controls_within_viewport(panel, viewport_size), "%s controls stay in %s" % [scene_path, viewport_size])
			assertions.truthy(_visible_text_has_size(panel), "%s visible text has positive size at %s" % [scene_path, viewport_size])
			assertions.truthy(_interactive_controls_focusable(panel), "%s interactive controls are focusable" % scene_path)
			host.free()
			await tree.process_frame

	var shop := (load("res://scenes/ui/shop_ui.tscn") as PackedScene).instantiate() as Control
	assertions.equal((shop.get_node("ModalLayer") as Control).mouse_filter, Control.MOUSE_FILTER_STOP, "economy modal consumes pointer input")
	shop.free()
	var notifications := (load("res://scenes/ui/economy/economy_notification_ui.tscn") as PackedScene).instantiate() as Control
	assertions.equal((notifications.get_node("ToastStack") as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "toast background does not consume pointer input")
	notifications.free()


func _test_runtime_scale_and_resize_state(assertions: TestAssert, tree: SceneTree) -> void:
	var method_names: Array[String] = []
	for method in EconomyLayoutScript.get_script_method_list():
		method_names.append(str(method.get("name", "")))
	assertions.truthy("set_ui_scale" in method_names, "layout exposes one runtime scale entry")
	assertions.truthy("get_ui_scale" in method_names, "layout exposes current runtime scale")
	if "set_ui_scale" not in method_names or "get_ui_scale" not in method_names:
		return
	var host := Control.new()
	host.size = Vector2(1920.0, 1080.0)
	tree.root.add_child(host)
	var panels: Array[Control] = []
	var shop: Control
	var market: Control
	for scene_path in PANEL_SCENES:
		var panel := (load(scene_path) as PackedScene).instantiate() as Control
		panels.append(panel)
		host.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if scene_path == "res://scenes/ui/shop_ui.tscn":
			shop = panel
		elif scene_path == "res://scenes/ui/economy/market_panel.tscn":
			market = panel
	shop.visible = true
	market.visible = true
	await tree.process_frame

	shop.call("select_tab", "contracts")
	market.set("selected_category", "crops")
	market.set("selected_item_id", "grain")
	var filler := Control.new()
	filler.custom_minimum_size = Vector2(1.0, 1800.0)
	market.get_node("Columns/CatalogColumn/ItemScroll/ItemRows").add_child(filler)
	await tree.process_frame
	var scroll := market.get_node("Columns/CatalogColumn/ItemScroll") as ScrollContainer
	scroll.scroll_vertical = 120

	EconomyLayoutScript.call("set_ui_scale", 1.2, tree)
	await tree.process_frame
	assertions.equal(EconomyLayoutScript.call("get_ui_scale"), 1.2, "runtime entry supports 120 percent")
	for panel in panels:
		assertions.truthy(is_equal_approx(panel.theme.default_base_scale, 1.2), "%s receives 120 percent theme scale" % panel.name)
	EconomyLayoutScript.call("set_ui_scale", 1.4, tree)
	await tree.process_frame
	assertions.equal(EconomyLayoutScript.call("get_ui_scale"), 1.4, "runtime entry stores supported scale")
	for panel in panels:
		assertions.truthy(is_equal_approx(panel.theme.default_base_scale, 1.4), "%s receives runtime theme scale" % panel.name)
	assertions.equal(market.call("get_layout_mode"), "drawer", "layout uses physical size divided by UI scale")
	assertions.equal(shop.get("selected_tab"), "contracts", "scale keeps selected economy tab")
	assertions.equal(market.get("selected_category"), "crops", "scale keeps selected category")
	assertions.equal(market.get("selected_item_id"), "grain", "scale keeps selected item")
	assertions.equal(scroll.scroll_vertical, 120, "scale keeps market scroll")

	host.size = Vector2(1280.0, 720.0)
	await tree.process_frame
	assertions.equal(shop.get("selected_tab"), "contracts", "resize keeps selected economy tab")
	assertions.equal(market.get("selected_category"), "crops", "resize keeps selected category")
	assertions.equal(market.get("selected_item_id"), "grain", "resize keeps selected item")
	assertions.equal(scroll.scroll_vertical, 120, "resize keeps market scroll")
	EconomyLayoutScript.call("set_ui_scale", 0.2, tree)
	assertions.equal(EconomyLayoutScript.call("get_ui_scale"), 0.8, "runtime entry clamps low scale")
	assertions.equal(market.call("get_layout_mode"), "three_column", "80 percent scale expands 1280 physical pixels to 1600 logical pixels")
	EconomyLayoutScript.call("set_ui_scale", 9.0, tree)
	assertions.equal(EconomyLayoutScript.call("get_ui_scale"), 1.4, "runtime entry clamps high scale")
	EconomyLayoutScript.call("set_ui_scale", NAN, tree)
	assertions.equal(EconomyLayoutScript.call("get_ui_scale"), 1.0, "runtime entry sanitizes non-finite scale")
	EconomyLayoutScript.call("set_ui_scale", 1.0, tree)
	host.free()
	await tree.process_frame


func _test_market_drawer_state(assertions: TestAssert, tree: SceneTree) -> void:
	var panel := (load("res://scenes/ui/economy/market_panel.tscn") as PackedScene).instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	var item_scroll := panel.get_node("Columns/CatalogColumn/ItemScroll") as ScrollContainer
	assertions.equal(
		item_scroll.horizontal_scroll_mode,
		ScrollContainer.SCROLL_MODE_DISABLED,
		"market product list disables horizontal scrolling"
	)
	panel.call("apply_responsive_layout", Vector2(1280, 720))
	assertions.equal(panel.call("get_layout_mode"), "drawer", "market uses drawer at minimum viewport")
	assertions.truthy((panel.get_node("Columns/CatalogColumn") as Control).visible, "drawer starts with product list")
	panel.call("open_details_drawer")
	assertions.truthy(not (panel.get_node("Columns/CatalogColumn") as Control).visible, "drawer details cover the product list")
	assertions.truthy((panel.get_node("Columns/DetailColumn") as Control).visible, "drawer keeps market details visible")
	assertions.truthy((panel.get_node("Columns/TradePanel/Content/BuyTotalLabel") as Control).visible, "drawer keeps trade total visible")
	assertions.truthy((panel.get_node("Columns/TradePanel/Content/DisabledReasonLabel") as Control).visible, "drawer keeps disabled reason visible")
	assertions.truthy(panel.call("handle_top_escape"), "escape closes the open details drawer")
	assertions.truthy((panel.get_node("Columns/CatalogColumn") as Control).visible, "closing drawer restores product list")
	panel.call("apply_responsive_layout", Vector2(1920, 1080))
	assertions.equal(panel.call("get_layout_mode"), "three_column", "market restores three columns after resize")
	panel.free()


func _test_real_keyboard_navigation(assertions: TestAssert, tree: SceneTree) -> void:
	var shop := (load("res://scenes/ui/shop_ui.tscn") as PackedScene).instantiate() as Control
	tree.root.add_child(shop)
	shop.visible = true
	await tree.process_frame
	var market_tab := shop.get_node("ModalLayer/HubPanel/Margin/Shell/Tabs/MarketTab") as Button
	var orders_tab := shop.get_node("ModalLayer/HubPanel/Margin/Shell/Tabs/OrdersTab") as Button
	market_tab.grab_focus()
	await _send_key(tree, KEY_TAB)
	assertions.equal(shop.get_viewport().gui_get_focus_owner(), orders_tab, "Tab advances through economy tabs")
	await _send_key(tree, KEY_TAB, true)
	assertions.equal(shop.get_viewport().gui_get_focus_owner(), market_tab, "Shift+Tab reverses economy tab focus")
	var activation := InputCounter.new()
	market_tab.pressed.connect(activation.record)
	await _send_key(tree, KEY_ENTER)
	assertions.equal(activation.count, 1, "Enter activates focused economy control")
	shop.free()
	await tree.process_frame

	var inventory := InventorySystem.new()
	var market_system := MarketSystem.new()
	var economy := EconomySystem.new()
	tree.root.add_child(inventory)
	tree.root.add_child(market_system)
	tree.root.add_child(economy)
	assertions.truthy(market_system.configure(GameDataScript.get_market_items()), "keyboard fixture configures real market")
	var wallet := tree.root.get_node_or_null("GameState")
	assertions.truthy(wallet != null and economy.configure(inventory, wallet, market_system), "keyboard fixture configures real economy")
	var market := (load("res://scenes/ui/economy/market_panel.tscn") as PackedScene).instantiate() as Control
	tree.root.add_child(market)
	market.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await tree.process_frame
	assertions.truthy(market.call("configure", inventory, economy, market_system), "keyboard fixture builds real market rows")
	var item_rows := market.get_node("Columns/CatalogColumn/ItemScroll/ItemRows") as VBoxContainer
	var product_buttons: Array[Button] = []
	var product_ids: Array[String] = []
	for row in item_rows.get_children():
		var select_button := row.get_node_or_null("Content/SelectButton") as Button
		if select_button != null:
			product_buttons.append(select_button)
			product_ids.append(str(row.get_meta("item_id", "")))
	assertions.truthy(product_buttons.size() >= 3, "keyboard fixture uses several visible dynamic product buttons")
	if product_buttons.size() < 3:
		market.free()
		economy.free()
		market_system.free()
		inventory.free()
		return
	product_buttons[0].grab_focus()
	await _send_key(tree, KEY_DOWN)
	assertions.equal(market.get_viewport().gui_get_focus_owner(), product_buttons[1], "Down moves focus to the next visible dynamic product")
	assertions.equal(market.get("selected_item_id"), product_ids[1], "Down selects the next visible dynamic product")
	await _send_key(tree, KEY_UP)
	assertions.equal(market.get_viewport().gui_get_focus_owner(), product_buttons[0], "Up moves focus to the previous visible dynamic product")
	assertions.equal(market.get("selected_item_id"), product_ids[0], "Up selects the previous visible dynamic product")
	product_buttons[2].grab_focus()
	await _send_key(tree, KEY_ENTER)
	assertions.equal(market.get("selected_item_id"), product_ids[2], "Enter activates the focused dynamic product button")

	market.call("apply_responsive_layout", Vector2(1280.0, 720.0))
	market.set("selected_item_id", product_ids[0])
	product_buttons[0].grab_focus()
	await _send_key(tree, KEY_UP)
	assertions.equal(market.get("selected_item_id"), product_ids[0], "Up at first drawer product preserves selection")
	assertions.equal(market.get_viewport().gui_get_focus_owner(), product_buttons[0], "Up at first drawer product preserves focus")
	assertions.truthy((market.get_node("Columns/CatalogColumn") as Control).visible, "Up at first drawer product keeps catalog open")
	market.set("selected_item_id", product_ids[-1])
	product_buttons[-1].grab_focus()
	await _send_key(tree, KEY_DOWN)
	assertions.equal(market.get("selected_item_id"), product_ids[-1], "Down at last drawer product preserves selection")
	assertions.equal(market.get_viewport().gui_get_focus_owner(), product_buttons[-1], "Down at last drawer product preserves focus")
	assertions.truthy((market.get_node("Columns/CatalogColumn") as Control).visible, "Down at last drawer product keeps catalog open")
	product_buttons[0].grab_focus()
	market.call("open_details_drawer")
	await tree.process_frame


func _test_shop_trade_modal_integration(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := await _create_shop_fixture(assertions, tree, Vector2(1920.0, 1080.0))
	if fixture.is_empty():
		return
	var host := fixture.host as Control
	var shop := fixture.shop as Control
	var market := fixture.market as Control
	var trade := market.get_node("Columns/TradePanel") as Control
	var confirmation := trade.get_node("ConfirmationLayer") as Control
	var confirm_button := trade.get_node("ConfirmationLayer/Content/VBox/Buttons/ConfirmButton") as Button
	var orders_tab := shop.get_node("ModalLayer/HubPanel/Margin/Shell/Tabs/OrdersTab") as Button
	var crops_button := market.get_node("Columns/CatalogColumn/CategoryList/Crops") as Button
	var close_button := shop.get_node("ModalLayer/HubPanel/Margin/Shell/Header/CloseButton") as Button
	var orders_clicks := InputCounter.new()
	var crops_clicks := InputCounter.new()
	var close_clicks := InputCounter.new()
	var confirm_clicks := InputCounter.new()
	orders_tab.pressed.connect(orders_clicks.record)
	crops_button.pressed.connect(crops_clicks.record)
	close_button.pressed.connect(close_clicks.record)
	confirm_button.pressed.connect(confirm_clicks.record)
	confirmation.visible = true
	await tree.process_frame
	assertions.truthy(shop.has_node("ModalLayer/TradeModalBlocker"), "ShopUI provides a full-screen trade modal blocker")
	assertions.truthy((shop.get_node("ModalLayer/TradeModalBlocker") as Control).visible, "trade modal blocker follows confirmation visibility")
	for _step in range(6):
		await _send_key(tree, KEY_TAB)
		var focus_owner := shop.get_viewport().gui_get_focus_owner()
		assertions.truthy(focus_owner != null and confirmation.is_ancestor_of(focus_owner), "trade confirmation traps ShopUI Tab focus")
	assertions.truthy(not confirm_button.disabled, "trade confirmation primary action remains enabled")
	await _send_mouse_click(tree, confirm_button.get_global_rect().get_center())
	assertions.equal(confirm_clicks.count, 1, "trade confirmation primary action receives pointer input above blocker")
	await _send_mouse_click(tree, crops_button.get_global_rect().get_center())
	await _send_mouse_click(tree, orders_tab.get_global_rect().get_center())
	await _send_mouse_click(tree, close_button.get_global_rect().get_center())
	assertions.equal(orders_clicks.count, 0, "trade confirmation blocks economy tab clicks")
	assertions.equal(crops_clicks.count, 0, "trade confirmation blocks market category clicks")
	assertions.equal(close_clicks.count, 0, "trade confirmation blocks ShopUI close clicks")
	assertions.equal(shop.get("selected_tab"), "market", "blocked tab click does not switch economy page")
	assertions.equal(market.get("selected_category"), "raw_materials", "blocked category click does not change market category")
	assertions.truthy(shop.visible, "blocked close click keeps ShopUI open")
	assertions.truthy(not shop.call("select_tab", "orders"), "trade confirmation rejects programmatic page switching")
	confirmation.visible = false
	await tree.process_frame
	assertions.truthy(not (shop.get_node("ModalLayer/TradeModalBlocker") as Control).visible, "closing trade confirmation removes full-screen blocker")
	orders_tab.grab_focus()
	await _send_key(tree, KEY_ENTER)
	assertions.equal(shop.get("selected_tab"), "orders", "closing trade confirmation restores tab activation")
	shop.call("close")
	host.free()
	(fixture.economy as Node).free()
	(fixture.market_system as Node).free()
	(fixture.inventory as Node).free()
	await tree.process_frame


func _test_narrow_shop_pagehost_bounds(assertions: TestAssert, tree: SceneTree) -> void:
	EconomyLayoutScript.call("set_ui_scale", 1.4, tree)
	var fixture := await _create_shop_fixture(assertions, tree, Vector2(1280.0, 720.0))
	if fixture.is_empty():
		EconomyLayoutScript.call("set_ui_scale", 1.0, tree)
		return
	var host := fixture.host as Control
	var shop := fixture.shop as Control
	var market := fixture.market as Control
	var page_host := shop.get_node("ModalLayer/HubPanel/Margin/Shell/PageHost") as Control
	market.call("select_category", "raw_materials")
	market.call("select_item", "wood")
	await tree.process_frame
	assertions.equal(market.call("get_layout_mode"), "drawer", "nested 1280 ShopUI opens market drawer mode")
	assertions.truthy(
		_controls_within_rect(market, page_host.get_global_rect()),
		"nested 1280 market drawer controls stay inside PageHost %s: %s" % [page_host.get_global_rect(), _out_of_bounds_description(market, page_host.get_global_rect())]
	)
	var buy_total := market.get_node("Columns/TradePanel/Content/BuyTotalLabel") as Control
	var disabled_reason := market.get_node("Columns/TradePanel/Content/DisabledReasonLabel") as Control
	assertions.truthy(buy_total.is_visible_in_tree() and page_host.get_global_rect().encloses(buy_total.get_global_rect()), "narrow drawer keeps buy total visible without scrolling")
	assertions.truthy(disabled_reason.is_visible_in_tree() and page_host.get_global_rect().encloses(disabled_reason.get_global_rect()), "narrow drawer keeps disabled reason visible without scrolling")
	shop.call("select_tab", "contracts")
	await tree.process_frame
	var contract_panel := shop.get_node("ModalLayer/HubPanel/Margin/Shell/PageHost/ContractPanel") as Control
	assertions.truthy(
		_controls_within_rect(contract_panel, page_host.get_global_rect()),
		"nested 1280 contract controls stay inside PageHost %s: %s"
		% [page_host.get_global_rect(), _out_of_bounds_description(contract_panel, page_host.get_global_rect())]
	)
	shop.call("close")
	host.free()
	(fixture.economy as Node).free()
	(fixture.market_system as Node).free()
	(fixture.inventory as Node).free()
	EconomyLayoutScript.call("set_ui_scale", 1.0, tree)
	await tree.process_frame


func _create_shop_fixture(assertions: TestAssert, tree: SceneTree, viewport_size: Vector2) -> Dictionary:
	var inventory := InventorySystem.new()
	var market_system := MarketSystem.new()
	var economy := EconomySystem.new()
	tree.root.add_child(inventory)
	tree.root.add_child(market_system)
	tree.root.add_child(economy)
	if not market_system.configure(GameDataScript.get_market_items()):
		assertions.truthy(false, "ShopUI fixture configures real market")
		return {}
	var wallet := tree.root.get_node_or_null("GameState")
	if wallet == null or not economy.configure(inventory, wallet, market_system):
		assertions.truthy(false, "ShopUI fixture configures real economy")
		return {}
	var host := Control.new()
	host.size = viewport_size
	tree.root.add_child(host)
	var shop := (load("res://scenes/ui/shop_ui.tscn") as PackedScene).instantiate() as Control
	host.add_child(shop)
	shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await tree.process_frame
	if not shop.call("configure", inventory, economy, market_system):
		assertions.truthy(false, "ShopUI fixture configures real panels")
		host.free()
		return {}
	shop.call("open", "market")
	await tree.process_frame
	var market := shop.get_node("ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel") as Control
	return {
		"host": host,
		"shop": shop,
		"market": market,
		"inventory": inventory,
		"market_system": market_system,
		"economy": economy,
	}
	var drawer_focus := market.get_viewport().gui_get_focus_owner()
	assertions.truthy(
		drawer_focus != null
		and drawer_focus.is_visible_in_tree()
		and (market.get_node("Columns/TradePanel") as Node).is_ancestor_of(drawer_focus),
		"opening drawer moves focus into visible trade controls"
	)
	market.free()
	economy.free()
	market_system.free()
	inventory.free()
	await tree.process_frame


func _test_trade_keyboard_and_wheel(assertions: TestAssert, tree: SceneTree) -> void:
	var panel := (load("res://scenes/ui/economy/trade_panel.tscn") as PackedScene).instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	var quantity := panel.get_node("Content/QuantityRow/QuantitySpin") as SpinBox
	quantity.max_value = 10
	quantity.value = 3
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	quantity.gui_input.emit(wheel_up)
	assertions.equal(int(quantity.value), 4, "mouse wheel increases trade quantity")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	quantity.gui_input.emit(wheel_down)
	assertions.equal(int(quantity.value), 3, "mouse wheel decreases trade quantity")
	assertions.truthy(quantity.get_line_edit().editable, "quantity supports numeric keyboard entry")
	panel.free()


func _test_trade_confirmation_modal(assertions: TestAssert, tree: SceneTree) -> void:
	var host := Control.new()
	host.size = Vector2(520.0, 680.0)
	tree.root.add_child(host)
	var panel := (load("res://scenes/ui/economy/trade_panel.tscn") as PackedScene).instantiate() as Control
	host.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await tree.process_frame
	var confirmation := panel.get_node("ConfirmationLayer") as Control
	var buy_button := panel.get_node("Content/Actions/BuyButton") as Button
	buy_button.disabled = false
	var click_counter := InputCounter.new()
	buy_button.pressed.connect(click_counter.record)
	confirmation.visible = true
	await tree.process_frame
	assertions.equal(confirmation.mouse_filter, Control.MOUSE_FILTER_STOP, "trade confirmation consumes pointer input")
	assertions.truthy(
		_rect_covers(confirmation.get_global_rect(), panel.get_global_rect()),
		"trade confirmation covers complete panel (%s over %s)" % [confirmation.get_global_rect(), panel.get_global_rect()]
	)
	await _send_key(tree, KEY_TAB)
	var modal_focus := panel.get_viewport().gui_get_focus_owner()
	assertions.truthy(modal_focus != null and confirmation.is_ancestor_of(modal_focus), "visible confirmation traps keyboard focus above underlying trade controls")
	await _send_mouse_click(tree, buy_button.get_global_rect().get_center())
	assertions.equal(click_counter.count, 0, "visible confirmation blocks clicks on underlying trade controls")
	confirmation.visible = false
	await tree.process_frame
	assertions.truthy(buy_button.focus_mode != Control.FOCUS_NONE, "closing confirmation restores underlying focusability")
	host.free()
	await tree.process_frame


func _send_key(tree: SceneTree, keycode: Key, shift_pressed := false) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	press.shift_pressed = shift_pressed
	tree.root.push_input(press, true)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	tree.root.push_input(release, true)
	await tree.process_frame


func _send_mouse_click(tree: SceneTree, position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		tree.root.push_input(event, true)
	await tree.process_frame


func _rect_covers(outer: Rect2, inner: Rect2) -> bool:
	return (
		outer.position.x <= inner.position.x + 0.5
		and outer.position.y <= inner.position.y + 0.5
		and outer.end.x >= inner.end.x - 0.5
		and outer.end.y >= inner.end.y - 0.5
	)


func _controls_within_viewport(root: Control, viewport_size: Vector2) -> bool:
	for child in _all_controls(root):
		if not child.is_visible_in_tree() or child == root:
			continue
		var rect := child.get_global_rect()
		if rect.position.x < -0.5 or rect.position.y < -0.5:
			return false
		if rect.end.x > viewport_size.x + 0.5 or rect.end.y > viewport_size.y + 0.5:
			return false
	return true


func _controls_within_rect(root: Control, bounds: Rect2) -> bool:
	for child in _all_controls(root):
		if not child.is_visible_in_tree() or child == root:
			continue
		if not _rect_covers_with_tolerance(bounds, child.get_global_rect()):
			return false
	return true


func _out_of_bounds_description(root: Control, bounds: Rect2) -> String:
	var entries: Array[String] = []
	for child in _all_controls(root):
		if child.is_visible_in_tree() and child != root and not _rect_covers_with_tolerance(bounds, child.get_global_rect()):
			entries.append("%s=%s" % [root.get_path_to(child), child.get_global_rect()])
	return "; ".join(entries)


func _rect_covers_with_tolerance(outer: Rect2, inner: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x - 0.5
		and inner.position.y >= outer.position.y - 0.5
		and inner.end.x <= outer.end.x + 0.5
		and inner.end.y <= outer.end.y + 0.5
	)


func _visible_text_has_size(root: Control) -> bool:
	for child in _all_controls(root):
		if not child.is_visible_in_tree():
			continue
		var has_text := child is Label or child is Button or child is LineEdit or child is RichTextLabel
		if has_text and not str(child.get("text")).is_empty() and (child.size.x <= 0.0 or child.size.y <= 0.0):
			return false
	return true


func _interactive_controls_focusable(root: Control) -> bool:
	for child in _all_controls(root):
		if not child.is_visible_in_tree() or child.is_queued_for_deletion():
			continue
		if child is BaseButton or child is LineEdit or child is SpinBox or child is ItemList or child is OptionButton:
			if child.focus_mode == Control.FOCUS_NONE:
				return false
	return true


func _all_controls(root: Control) -> Array[Control]:
	var result: Array[Control] = [root]
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			pending.append(child)
			if child is Control:
				result.append(child)
	return result


func _contrast_ratio(a: Color, b: Color) -> float:
	var lighter := maxf(_relative_luminance(a), _relative_luminance(b))
	var darker := minf(_relative_luminance(a), _relative_luminance(b))
	return (lighter + 0.05) / (darker + 0.05)


func _relative_luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)


func _linear_channel(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)
