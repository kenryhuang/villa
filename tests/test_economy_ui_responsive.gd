class_name EconomyUIResponsiveTest
extends RefCounted

const EconomyLayout = preload("res://scripts/ui/economy_layout.gd")
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


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_layout_contract(assertions)
	_test_theme_contract(assertions)
	_test_shared_scene_tokens(assertions)
	await _test_panel_contracts(assertions, tree)
	await _test_market_drawer_state(assertions, tree)
	await _test_trade_keyboard_and_wheel(assertions, tree)


func _test_layout_contract(assertions: TestAssert) -> void:
	assertions.equal(EconomyLayout.mode_for_size(Vector2(3000, 2000)), "three_column", "target viewport uses columns")
	assertions.equal(EconomyLayout.mode_for_size(Vector2(1920, 1080)), "three_column", "desktop uses columns")
	assertions.equal(EconomyLayout.mode_for_size(Vector2(1500, 900)), "three_column", "drawer threshold is exclusive")
	assertions.equal(EconomyLayout.mode_for_size(Vector2(1499, 900)), "drawer", "narrow logical viewport uses drawer")
	assertions.equal(EconomyLayout.mode_for_size(Vector2(1280, 720)), "drawer", "minimum viewport uses drawer")
	assertions.equal(EconomyLayout.clamp_scale(0.5), 0.8, "scale has lower bound")
	assertions.equal(EconomyLayout.clamp_scale(1.2), 1.2, "scale preserves supported value")
	assertions.equal(EconomyLayout.clamp_scale(2.0), 1.4, "scale has upper bound")


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
		"res://scenes/ui/economy/trade_panel.tscn": {"ConfirmationLayer": "EconomyCard"},
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


func _test_market_drawer_state(assertions: TestAssert, tree: SceneTree) -> void:
	var panel := (load("res://scenes/ui/economy/market_panel.tscn") as PackedScene).instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	panel.call("apply_responsive_layout", Vector2(1280, 720))
	assertions.equal(panel.call("get_layout_mode"), "drawer", "market uses drawer at minimum viewport")
	assertions.truthy((panel.get_node("Columns/CatalogColumn") as Control).visible, "drawer starts with product list")
	panel.call("open_details_drawer")
	assertions.truthy(not (panel.get_node("Columns/CatalogColumn") as Control).visible, "drawer details cover the product list")
	assertions.truthy((panel.get_node("Columns/DetailColumn") as Control).visible, "drawer keeps market details visible")
	assertions.truthy((panel.get_node("Columns/TradePanel/BuyTotalLabel") as Control).visible, "drawer keeps trade total visible")
	assertions.truthy((panel.get_node("Columns/TradePanel/DisabledReasonLabel") as Control).visible, "drawer keeps disabled reason visible")
	assertions.truthy(panel.call("handle_top_escape"), "escape closes the open details drawer")
	assertions.truthy((panel.get_node("Columns/CatalogColumn") as Control).visible, "closing drawer restores product list")
	panel.call("apply_responsive_layout", Vector2(1920, 1080))
	assertions.equal(panel.call("get_layout_mode"), "three_column", "market restores three columns after resize")
	panel.free()


func _test_trade_keyboard_and_wheel(assertions: TestAssert, tree: SceneTree) -> void:
	var panel := (load("res://scenes/ui/economy/trade_panel.tscn") as PackedScene).instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	var quantity := panel.get_node("QuantityRow/QuantitySpin") as SpinBox
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
