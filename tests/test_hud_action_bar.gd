extends RefCounted

const HudScene = preload("res://scenes/ui/hud.tscn")
const ActionPaletteButtonScript = preload(
	"res://scripts/ui/action_palette_button.gd"
)


class ToolDouble:
	extends RefCounted

	func switch_tool(_tool_type: int) -> void:
		pass


class BuildingDouble:
	extends RefCounted

	var build_mode := false

	func enter_preview_mode(_building: Variant) -> bool:
		build_mode = true
		return true

	func exit_preview_mode() -> void:
		build_mode = false

	func is_in_build_mode() -> bool:
		return build_mode


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
	inventory.add_item("grain_seed", 2)
	var controller = controller_script.new()
	tree.root.add_child(controller)
	controller.configure(
		null,
		null,
		null,
		BuildingDouble.new(),
		ToolDouble.new(),
		inventory
	)
	hud.configure_action_bar(controller, inventory, EconomyDouble.new())
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
			"种子 ×2",
			"seed tile keeps quantity concise and readable"
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
	assertions.truthy(controller.deselect_slot(), "selected HUD action can be cancelled")
	assertions.equal(hud.tool_label.text, "未选择工具", "HUD shows cancelled tool state")
	for child in quick_bar.get_children():
		assertions.truthy(
			not (child as Button).button_pressed,
			"cancelled tool leaves every action button unpressed"
		)

	inventory.remove_item("grain_seed", 1)
	hud.refresh_action_bar()
	seed_tile = quick_bar.get_child(5)
	if seed_tile is ActionPaletteButtonScript:
		assertions.equal(
			seed_tile.name_label.text,
			"种子 ×1",
			"seed count refreshes after inventory change"
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
	assertions.equal(hud.get_palette_button_count(), 9, "building palette has nine buttons")
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
	var unavailable_tile := quick_bar.get_child(0)
	if unavailable_tile is ActionPaletteButtonScript:
		assertions.equal(
			unavailable_tile.name_label.modulate,
			Color.WHITE,
			"resource dimming keeps text opaque"
		)
		assertions.truthy(
			unavailable_tile.icon_rect.modulate != Color.WHITE,
			"resource dimming targets icon"
		)
	(quick_bar.get_child(8) as Button).pressed.emit()
	assertions.equal(
		controller.get_mode_selected_slot(PlayerActionController.ActionMode.BUILDING),
		8,
		"mouse selects fence through the shared controller API"
	)
	hud.set_mode_menu_open(true)
	assertions.truthy(hud.mode_menu.visible, "mode menu can open above the palette")

	controller.free()
	inventory.free()
	season.free()
	hud.free()
