extends RefCounted

const ButtonScene = preload("res://scenes/ui/action_palette_button.tscn")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var button = ButtonScene.instantiate()
	tree.root.add_child(button)
	var texture := load("res://assets/ui/action_icons/hoe.png") as Texture2D
	button.configure(1, "锄头", texture)

	assertions.equal(
		button.custom_minimum_size,
		Vector2(112, 116),
		"action tile uses readable size"
	)
	assertions.equal(
		button.icon_rect.custom_minimum_size,
		Vector2(84, 84),
		"icon gets an 84px square"
	)
	assertions.equal(button.icon_rect.texture, texture, "configured icon is displayed")
	assertions.equal(button.shortcut_label.text, "1", "shortcut badge shows key")
	assertions.equal(button.name_label.text, "锄头", "tile shows action name")
	assertions.truthy(
		button.name_label.get_theme_font_size("font_size") >= 22,
		"action name uses readable font"
	)
	assertions.truthy(
		button.name_label.get_theme_constant("outline_size") >= 3,
		"action name has a dark outline"
	)
	assertions.equal(
		button.icon_rect.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"icon cannot consume tile clicks"
	)

	button.set_available(false)
	assertions.truthy(
		button.icon_rect.modulate != Color.WHITE,
		"unavailable dims only icon"
	)
	assertions.equal(
		button.name_label.modulate,
		Color.WHITE,
		"unavailable keeps name legible"
	)
	button.set_selected(true)
	assertions.truthy(button.button_pressed, "selected state uses button pressed state")
	assertions.truthy(button.has_method("set_build_state"), "palette tile exposes four-state building API")
	if button.has_method("set_build_state"):
		button.set_build_state("ready")
		assertions.truthy(not button.disabled, "ready building is clickable")
		button.set_build_state("missing_resources")
		assertions.truthy(not button.disabled, "missing-resource building stays clickable for feedback")
		button.set_build_state("locked")
		assertions.truthy(not button.disabled, "locked building stays clickable for unlock detail")
		button.set_build_state("invalid")
		assertions.truthy(button.disabled, "invalid building is disabled")
	button.free()
